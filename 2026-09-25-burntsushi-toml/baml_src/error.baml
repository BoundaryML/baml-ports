// Port of error.go.

// ParseError is returned when there is an error parsing the TOML syntax such as
// invalid syntax, duplicate keys, etc.
//
// In addition to the error message itself, you can also print detailed location
// information with context by using [ErrorWithPosition]:
//
//	toml: error: Key 'fruit' was already created and cannot be used as an array.
//
//	At line 4, column 2-7:
//
//	      2 | fruit = []
//	      3 |
//	      4 | [[fruit]] # Not allowed
//	            ^^^^^
//
// [ErrorWithUsage] can be used to print the above with some more detailed usage
// guidance:
//
//	toml: error: newlines not allowed within inline tables
//
//	At line 1, column 18:
//
//	      1 | x = [{ key = 42 #
//	                           ^
//
//	Error help:
//
//	  Inline tables must always be on a single line:
//
//	      table = {key = 42, second = 43}
//
//	  It is invalid to split them over multiple lines like so:
//
//	      # INVALID
//	      table = {
//	          key    = 42,
//	          second = 43
//	      }
//
//	  Use regular for this:
//
//	      [table]
//	      key    = 42
//	      second = 43
class ParseError {
    message: string, // Short technical message.
    usage: string, // Longer message with usage guidance; may be blank.
    position: Position, // Position of the error
    last_key: string, // Last parsed key, may be blank.

    // Line the error occurred.
    //
    // Deprecated: use [Position].
    line: int,

    err: TomlError?,
    // Go keeps the input as a string, which may hold invalid UTF-8; the port
    // keeps the raw bytes so byte offsets in Position stay meaningful.
    input: int[],

    // func (pe ParseError) Error() string. (Named error_string: a class method
    // with the same name as an interface method it implements shadows it; see
    // PORTING_NOTES.md.)
    function error_string(self) -> string {
        if (self.last_key == "") {
            return `toml: line ${self.position.line}: ${self.message}`;
        }
        `toml: line ${self.position.line} (last key ${root.go.quote(self.last_key)}): ${self.message}`
    }

    function unwrap(self) -> TomlError? {
        self.err
    }

    // ErrorWithPosition returns the error with detailed location context.
    //
    // See the documentation on [ParseError].
    function error_with_position(self) -> string {
        if (self.input.length() == 0) { // Should never happen, but just in case.
            return self.error_string();
        }

        // TODO: don't show control characters as literals? This may not show up
        // well everywhere.

        let lines = split_lines_bytes(self.input);
        let b = "";
        if (self.position.len == 1) {
            b += `toml: error: ${self.message}\n\nAt line ${self.position.line}, column ${self.position.col}:\n\n`;
        } else {
            b += `toml: error: ${self.message}\n\nAt line ${self.position.line}, column ${self.position.col}-${self.position.col + self.position.len - 1}:\n\n`;
        }
        if (self.position.line > 2) {
            b += `${root.go.pad_left((self.position.line - 2).to_string(), 7)} | ${expand_tab(lines[self.position.line - 3])}\n`;
        }
        if (self.position.line > 1) {
            b += `${root.go.pad_left((self.position.line - 1).to_string(), 7)} | ${expand_tab(lines[self.position.line - 2])}\n`;
        }

        /// Expand tabs, so that the ^^^s are at the correct position, but leave
        /// "column 10-13" intact. Adjusting this to the visual column would be
        /// better, but we don't know the tabsize of the user in their editor, which
        /// can be 8, 4, 2, or something else. We can't know. So leaving it as the
        /// character index is probably the "most correct".
        let expanded = expand_tab(lines[self.position.line - 1]);
        let diff = root.go.bytes_of(expanded).length() - root.go.bytes_of(lines[self.position.line - 1]).length();

        b += `${root.go.pad_left(self.position.line.to_string(), 7)} | ${expanded}\n`;
        b += `${root.go.pad_left("", 10)}${" ".repeat(self.position.col - 1 + diff)}${"^".repeat(self.position.len)}\n`;
        b
    }

    // ErrorWithUsage returns the error with detailed location context and usage
    // guidance.
    //
    // See the documentation on [ParseError].
    function error_with_usage(self) -> string {
        let m = self.error_with_position();
        let e = self.err;
        let u = if (e != null) { e.usage() } else { "" };
        if (u != "") {
            let lines = u.trim().split("\n");
            let i = 0;
            while (i < lines.length()) {
                if (lines[i] != "") {
                    lines[i] = "    " + lines[i];
                }
                i += 1;
            }
            return m + "Error help:\n\n" + lines.join("\n") + "\n";
        }
        m
    }

    implements TomlError {
        function error(self) -> string throws never {
            self.error_string()
        }
    }
}

// Position of an error.
class Position {
    line: int, // Line number, starting at 1.
    col: int, // Error column, starting at 1.
    start: int, // Start of error, as byte offset starting at 0.
    len: int, // Length of the error in bytes.

    implements baml.ToString {
        function to_string(self) -> string throws never {
            position_string(self)
        }
    }

    function with_col(self, toml_file: int[]) -> Position {
        let p = Position { line: self.line, col: self.col, start: self.start, len: self.len };
        let pos = 0;
        for (let line_len in line_byte_lengths(toml_file)) {
            let ll = line_len + 1; // +1 for the removed newline
            if (pos + ll >= p.start) {
                p.col = root.go.max(p.start - pos + 1, 1); // Should never happen, but just in case.
                break;
            }
            pos += ll;
        }
        p
    }
}

// len() of every element of strings.Split(input, "\n"), in bytes.
function line_byte_lengths(input: int[]) -> int[] {
    let out: int[] = [];
    let start = 0;
    let i = 0;
    while (i < input.length()) {
        if (input[i] == 10) {
            out.push(i - start);
            start = i + 1;
        }
        i += 1;
    }
    out.push(input.length() - start);
    out
}

// strings.Split(input, "\n") on the raw input bytes. Each line is converted to
// a BAML string (invalid UTF-8 becomes U+FFFD); byte lengths are computed on
// the original bytes by line_byte_lengths.
function split_lines_bytes(input: int[]) -> string[] {
    let out: string[] = [];
    let start = 0;
    let i = 0;
    while (i < input.length()) {
        if (input[i] == 10) {
            out.push(root.go.string_slice(input, start, i));
            start = i + 1;
        }
        i += 1;
    }
    out.push(root.go.string_slice(input, start, input.length()));
    out
}

function expand_tab(s: string) -> string {
    let b = "";
    let l = 0;
    for (let r in s.chars()) {
        if (r == "\t") {
            let tw = 8 - l % 8;
            b += " ".repeat(tw);
            l += tw;
        } else {
            b += r;
            l += 1;
        }
    }
    b
}

// Go's `error` interface, extended with the optional `Usage() string` method
// that ErrorWithUsage looks for. Go discovers `Usage` with a type assertion; a
// BAML interface cannot be "partially" implemented, so `usage` has a default
// body returning "" (which Go treats the same as "no usage").
interface TomlError {
    function error(self) -> string throws never
    function usage(self) -> string throws never {
        ""
    }
}

// errors.New / fmt.Errorf: an error that is just a message.
class GoError {
    msg: string,
    // %w-wrapped error, if any.
    wrapped: TomlError?,

    implements TomlError {
        function error(self) -> string throws never {
            self.msg
        }
    }
}

class ErrLexControl {
    r: int,
    implements TomlError {
        function error(self) -> string throws never {
            `TOML files cannot contain control characters: '0x${root.go.hex2(self.r)}'`
        }
        function usage(self) -> string throws never {
            ""
        }
    }
}

class ErrLexEscape {
    r: int,
    implements TomlError {
        function error(self) -> string throws never {
            if (self.r == 0 || self.r == 13 || self.r == 10) {
                return `unexpected end of line after '\\'`;
            }
            `invalid escape in string '\\${root.go.rune_string(self.r)}'`
        }
        function usage(self) -> string throws never {
            usage_escape()
        }
    }
}

class ErrLexUTF8 {
    b: int,
    implements TomlError {
        function error(self) -> string throws never {
            `invalid UTF-8 byte: 0x${root.go.hex2(self.b)}`
        }
        function usage(self) -> string throws never {
            ""
        }
    }
}

class ErrParseDate {
    v: string,
    implements TomlError {
        function error(self) -> string throws never {
            `invalid datetime: ${root.go.quote(self.v)}`
        }
        function usage(self) -> string throws never {
            usage_date()
        }
    }
}

class ErrLexStringNL {
    implements TomlError {
        function error(self) -> string throws never {
            "strings cannot contain newlines"
        }
        function usage(self) -> string throws never {
            usage_string_newline()
        }
    }
}

class ErrParseRange {
    i: string, // int or float, already formatted with %v
    size: string, // "int64", "uint16", etc.
    implements TomlError {
        function error(self) -> string throws never {
            `${self.i} is out of range for ${self.size}`
        }
        function usage(self) -> string throws never {
            usage_int_overflow()
        }
    }
}

class ErrUnsafeFloat {
    i: string, // float32 or float64, already formatted with %v
    size: string, // "float32" or "float64"
    implements TomlError {
        function error(self) -> string throws never {
            `${self.i} is out of the safe ${self.size} range`
        }
        function usage(self) -> string throws never {
            usage_unsafe_float()
        }
    }
}

class ErrParseDuration {
    d: string,
    implements TomlError {
        function error(self) -> string throws never {
            `invalid duration: ${root.go.quote(self.d)}`
        }
        function usage(self) -> string throws never {
            usage_duration()
        }
    }
}

function usage_escape() -> string {
    "\nA '\\' inside a \"-delimited string is interpreted as an escape character.\n\nThe following escape sequences are supported:\n\\b, \\t, \\n, \\f, \\r, \\\", \\\\, \\uXXXX, and \\UXXXXXXXX\n\nTo prevent a '\\' from being recognized as an escape character, use either:\n\n- a ' or '''-delimited string; escape characters aren't processed in them; or\n- write two backslashes to get a single backslash: '\\\\'.\n\nIf you're trying to add a Windows path (e.g. \"C:\\Users\\martin\") then using '/'\ninstead of '\\' will usually also work: \"C:/Users/martin\".\n"
}

function usage_string_newline() -> string {
    "\nStrings must always be on a single line, and cannot span more than one line:\n\n    # INVALID\n    string = \"Hello,\n    world!\"\n\nInstead use \"\"\" or ''' to split strings over multiple lines:\n\n    string = \"\"\"Hello,\n    world!\"\"\"\n"
}

function usage_int_overflow() -> string {
    "\nThis number is too large; this may be an error in the TOML, but it can also be a\nbug in the program that uses too small of an integer.\n\nThe maximum and minimum values are:\n\n    size   │ lowest         │ highest\n    ───────┼────────────────┼──────────────\n    int8   │ -128           │ 127\n    int16  │ -32,768        │ 32,767\n    int32  │ -2,147,483,648 │ 2,147,483,647\n    int64  │ -9.2 × 10¹⁷    │ 9.2 × 10¹⁷\n    uint8  │ 0              │ 255\n    uint16 │ 0              │ 65,535\n    uint32 │ 0              │ 4,294,967,295\n    uint64 │ 0              │ 1.8 × 10¹⁸\n\nint refers to int32 on 32-bit systems and int64 on 64-bit systems.\n"
}

function usage_unsafe_float() -> string {
    "\nThis number is outside of the \"safe\" range for floating point numbers; whole\n(non-fractional) numbers outside the below range can not always be represented\naccurately in a float, leading to some loss of accuracy.\n\nExplicitly mark a number as a fractional unit by adding \".0\", which will incur\nsome loss of accuracy; for example:\n\n\tf = 2_000_000_000.0\n\nAccuracy ranges:\n\n\tfloat32 =            16,777,215\n\tfloat64 = 9,007,199,254,740,991\n"
}

function usage_duration() -> string {
    "\nA duration must be as \"number<unit>\", without any spaces. Valid units are:\n\n    ns         nanoseconds (billionth of a second)\n    us, µs     microseconds (millionth of a second)\n    ms         milliseconds (thousands of a second)\n    s          seconds\n    m          minutes\n    h          hours\n\nYou can combine multiple units; for example \"5m10s\" for 5 minutes and 10\nseconds.\n"
}

function usage_date() -> string {
    "\nA TOML datetime must be in one of the following formats:\n\n    2006-01-02T15:04:05Z07:00   Date and time, with timezone.\n    2006-01-02T15:04:05         Date and time, but without timezone.\n    2006-01-02                  Date without a time or timezone.\n    15:04:05                    Just a time, without any timezone.\n\nSeconds may optionally have a fraction, up to nanosecond precision:\n\n    15:04:05.123\n    15:04:05.856018510\n\nThe seconds part in times is optional, and may be omitted:\n\n    2006-01-02T15:04Z07:00\n    2006-01-02T15:04\n    15:04\n"
}

// A Go runtime panic that is not a ParseError (Go: `panic(fmt.Sprintf(...))`
// from p.bug(), or panic("...") in the lexer). Thrown so that callers that
// `recover()` in Go (the toml-test decoder) can catch it.
class Panic {
    msg: string,
    implements TomlError {
        function error(self) -> string throws never {
            self.msg
        }
    }
}

function go_panic(msg: string) -> never {
    throw Panic { msg: msg }
}

// (*parser).bug
function bug(msg: string) -> never {
    throw Panic { msg: `BUG: ${msg}\n\n` }
}
