// Port of error_test.go.

class ErrorPositionCase {
    test_: string,
    err: string,
}

testset "TestErrorPosition" {
    // Note: take care to use leading spaces (not tabs).
    let tests = [
        ErrorPositionCase {
            test_: "array/missing-separator-02.toml",
            err: "
toml: error: expected a comma (',') or array terminator (']'), but got '2'

At line 1, column 13:

      1 | wrong = [ 1 2 3 ]
                      ^",
        },
        ErrorPositionCase {
            test_: "array/no-close-01.toml",
            err: "
toml: error: expected a comma (',') or array terminator (']'), but got end of file

At line 1, column 24:

      1 | no-close-01 = [ 1, 2, 3
                                 ^",
        },
        ErrorPositionCase {
            test_: "array/tables-02.toml",
            err: "
toml: error: Key 'fruit.variety' has already been defined.

At line 9, column 4-8:

      7 | " + "
      8 |   # This table conflicts with the previous table
      9 |   [fruit.variety]
             ^^^^^",
        },
        ErrorPositionCase {
            test_: "local-date/trailing-t.toml",
            err: "
toml: error: invalid datetime: \"2006-01-30T\"

At line 2, column 5-15:

      1 | # Date cannot end with trailing T
      2 | d = 2006-01-30T
              ^^^^^^^^^^^",
        },
        ErrorPositionCase {
            test_: "key/without-value-01.toml",
            err: "
toml: error: expected '.' or '=', but got '\\n' instead

At line 1, column 4:

      1 | key
             ^",
        },
        // Position looks wonky, but test has trailing space, so it's correct.
        ErrorPositionCase {
            test_: "key/without-value-02.toml",
            err: "
toml: error: expected value but found '\\n' instead

At line 1, column 7:

      1 | key = " + "
                ^",
        },
    ];
    let fsys = tomltest.test_cases();
    for (let tt in tests) {
        test tt.test_ {
            let input = fsys.read_file("invalid/" + tt.test_);

            let perr: ParseError? = null;
            let ok = decode_bytes_any(input) catch (err) {
                // errors.As(err, &pErr)
                let pe: ParseError => {
                    perr = pe;
                    false
                },
                let e: TomlError => {
                    throw `err is not a ParseError: ${e.error()}`
                },
            };
            if (ok) {
                throw "err is nil";
            }
            let pe = perr ?? go_panic("unreachable");

            let want_err = tt.err.slice(1, tt.err.length()) + "\n"; // Remove first newline, and add trailing.
            let want = pe.error_with_usage();

            if (!want.includes(want_err)) {
                throw `\nwant:\n${want_err}\nhave:\n${want}`;
            }
        }
    }
}

function decode_bytes_any(input: int[]) -> bool throws TomlError {
    let _ = new_decoder(go.new_bytes_reader(input)).decode<Any>(null);
    true
}

// ---- TestParseError ---------------------------------------------------------

class PeInt8 {
    Int: go.Int8,
}

class PeInt {
    Int: int,
}

class PeFloat32 {
    Float: go.Float32,
}

class PeDuration {
    D: go.Duration,
}

class PeTime {
    D: go.Time,
}

class PeString {
    String: string,
}

function usage_block() -> string {
    "
			| Error help:
			|
			|     This number is too large; this may be an error in the TOML, but it can also be a
			|     bug in the program that uses too small of an integer.
			|
			|     The maximum and minimum values are:
			|
			|         size   │ lowest         │ highest
			|         ───────┼────────────────┼──────────────
			|         int8   │ -128           │ 127
			|         int16  │ -32,768        │ 32,767
			|         int32  │ -2,147,483,648 │ 2,147,483,647
			|         int64  │ -9.2 × 10¹⁷    │ 9.2 × 10¹⁷
			|         uint8  │ 0              │ 255
			|         uint16 │ 0              │ 65,535
			|         uint32 │ 0              │ 4,294,967,295
			|         uint64 │ 0              │ 1.8 × 10¹⁸
			|
			|     int refers to int32 on 32-bit systems and int64 on 64-bit systems.
			"
}

function escape_help_block() -> string {
    "
			| Error help:
			|
			|     A '\\' inside a \"-delimited string is interpreted as an escape character.
			|
			|     The following escape sequences are supported:
			|     \\b, \\t, \\n, \\f, \\r, \\\", \\\\, \\uXXXX, and \\UXXXXXXXX
			|
			|     To prevent a '\\' from being recognized as an escape character, use either:
			|
			|     - a ' or '''-delimited string; escape characters aren't processed in them; or
			|     - write two backslashes to get a single backslash: '\\\\'.
			|
			|     If you're trying to add a Windows path (e.g. \"C:\\Users\\martin\") then using '/'
			|     instead of '\\' will usually also work: \"C:/Users/martin\".
			"
}

// prep() from the Go test: strip everything up to and including the first
// "|" and one following space on each line.
function prep(s: string) -> string {
    let lines = s.trim().split("\n");
    let out: string[] = [];
    for (let l in lines) {
        let line = l;
        let j = line.index_of("|");
        if (j != null) {
            line = line.slice(j + 1, line.length());
            if (line.starts_with(" ")) {
                line = line.slice(1, line.length());
            }
        }
        out.push(line);
    }
    out.join("\n") + "\n"
}

// Decode `toml` into the Go type the case names and return the ParseError's
// ErrorWithUsage(), or throw if decoding succeeded / failed differently.
function parse_error_usage(kind: string, toml: string) -> string {
    let perr: ParseError? = null;
    let ok = decode_kind(kind, toml) catch (err) {
        let pe: ParseError => {
            perr = pe;
            false
        },
        let e: TomlError => {
            throw `err is not a ParseError: ${e.error()}`
        },
    };
    if (ok) {
        throw "err is nil";
    }
    let pe = perr ?? go_panic("unreachable");
    pe.error_with_usage()
}

function decode_kind(kind: string, toml: string) -> bool throws TomlError {
    match (kind) {
        "int8" => {
            let _ = decode<PeInt8>(toml);
        },
        "int" => {
            let _ = decode<PeInt>(toml);
        },
        "float32" => {
            let _ = decode<PeFloat32>(toml);
        },
        "duration" => {
            let _ = decode<PeDuration>(toml);
        },
        "time" => {
            let _ = decode<PeTime>(toml);
        },
        "string" => {
            let _ = decode<PeString>(toml);
        },
        _ => {
            let _ = decode<map<string, Any>>(toml);
        },
    }
    true
}

class ParseErrorCase {
    kind: string,
    toml: string,
    err: string,
}

testset "TestParseError" {
    let tests = [
        ParseErrorCase {
            kind: "int8",
            toml: "Int = 200",
            err: "
			| toml: error: 200 is out of range for int8
			|
			| At line 1, column 7-9:
			|
			|       1 | Int = 200
			|                 ^^^" + usage_block(),
        },
        ParseErrorCase {
            kind: "int",
            toml: "Int = 9223372036854775808",
            err: "
			| toml: error: 9223372036854775808 is out of range for int64
			|
			| At line 1, column 7-25:
			|
			|       1 | Int = 9223372036854775808
			|                 ^^^^^^^^^^^^^^^^^^^" + usage_block(),
        },
        ParseErrorCase {
            kind: "float32",
            toml: "Float = 1.1e99",
            err: "
			| toml: error: 1.1e+99 is out of range for float32
			|
			| At line 1, column 9-14:
			|
			|       1 | Float = 1.1e99
			|                   ^^^^^^" + usage_block(),
        },
        ParseErrorCase {
            kind: "duration",
            toml: "D = \"99 bottles\"",
            err: "
			| toml: error: invalid duration: \"99 bottles\"
			|
			| At line 1, column 6-15:
			|
			|       1 | D = \"99 bottles\"
			|                ^^^^^^^^^^
			| Error help:
			|
			|     A duration must be as \"number<unit>\", without any spaces. Valid units are:
			|
			|         ns         nanoseconds (billionth of a second)
			|         us, µs     microseconds (millionth of a second)
			|         ms         milliseconds (thousands of a second)
			|         s          seconds
			|         m          minutes
			|         h          hours
			|
			|     You can combine multiple units; for example \"5m10s\" for 5 minutes and 10
			|     seconds.
			",
        },
        ParseErrorCase {
            kind: "time",
            toml: "D = 2006-01-99",
            err: "
			| toml: error: invalid datetime: \"2006-01-99\"
			|
			| At line 1, column 5-14:
			|
			|       1 | D = 2006-01-99
			|               ^^^^^^^^^^
			| Error help:
			|
			|     A TOML datetime must be in one of the following formats:
			|
			|         2006-01-02T15:04:05Z07:00   Date and time, with timezone.
			|         2006-01-02T15:04:05         Date and time, but without timezone.
			|         2006-01-02                  Date without a time or timezone.
			|         15:04:05                    Just a time, without any timezone.
			|
			|     Seconds may optionally have a fraction, up to nanosecond precision:
			|
			|         15:04:05.123
			|         15:04:05.856018510
			|
			|     The seconds part in times is optional, and may be omitted:
			|
			|         2006-01-02T15:04Z07:00
			|         2006-01-02T15:04
			|         15:04
			",
        },
        ParseErrorCase {
            kind: "string",
            toml: "string = \"test",
            err: "
			| toml: error: unexpected EOF; expected '\"'
			|
			| At line 1, column 14:
			|
			|       1 | string = \"test
			|                        ^
			",
        },
        ParseErrorCase {
            kind: "map",
            toml: "key = \"\\",
            err: "
			| toml: error: unexpected end of line after '\\'
			|
			| At line 1, column 8:
			|
			|       1 | key = \"\\
			|                  ^" + escape_help_block(),
        },
        ParseErrorCase {
            kind: "map",
            toml: "a = 123\n" + "key = \"\\",
            err: "
			| toml: error: unexpected end of line after '\\'
			|
			| At line 2, column 8:
			|
			|       1 | a = 123
			|       2 | key = \"\\
			|                  ^" + escape_help_block(),
        },
    ];

    let i = 0;
    for (let tt in tests) {
        test `#0${i}` {
            let have = parse_error_usage(tt.kind, tt.toml);
            let want = prep(tt.err);
            if (have != want) {
                throw `\nwant:\n${want}\nhave:\n${have}`;
            }
        }
        i += 1;
    }
}

// var errInvalidValue = errors.New("invalid value")
function err_invalid_value() -> GoError {
    GoError { msg: "invalid value", wrapped: null }
}

// errors.Is: walk the Unwrap chain looking for an error equal to target.
// Go compares error values with ==; the port compares the rendered message
// and the concrete type, since BAML class instances have no identity
// comparison distinct from structural equality for this purpose.
function errors_is(err: TomlError?, target: TomlError) -> bool {
    let cur: TomlError? = err;
    let depth = 0;
    while (depth < 32) {
        match (cur) {
            null => {
                return false;
            },
            let c: TomlError => {
                if (c.error() == target.error()
                    && reflect.Type.of_value(c) == reflect.Type.of_value(target)) {
                    return true;
                }
                cur = error_unwrap(c);
            },
        }
        depth += 1;
    }
    false
}

function error_unwrap(e: TomlError) -> TomlError? {
    match (e) {
        let pe: ParseError => pe.unwrap(),
        let ge: GoError => ge.wrapped,
        _ => null,
    }
}

// type Enum1 uint8 with a pointer-receiver UnmarshalText.
class Enum1 {
    v: int,

    implements TextUnmarshaler {
        function unmarshal_text(self, text: string) -> Enum1 throws TomlError {
            let t = text.trim();
            match (t) {
                "ok" => Enum1 { v: 1 },
                _ => {
                    throw GoError { msg: `${err_invalid_value().error()}: ${go.quote(t)}`, wrapped: err_invalid_value() }
                },
            }
        }
    }
}

class UnmarshalTypeErrorC {
    K1: string @alias("k1"),
    K2: Enum1 @alias("k2"),
    K3: Enum1 @alias("k3"),
}

// Make sure custom types are wrapped in ParseError with correct location.
test "TestUnmarshalTypeError" {
    let perr: ParseError? = null;
    let got_err: TomlError? = null;
    let ok = decode_typeerror_c("k1 = 'asd'\nk2 = 'ok'\nk3 = 'invalid'\nk4 = 'ok'") catch (err) {
        let pe: ParseError => {
            perr = pe;
            got_err = pe;
            false
        },
        let e: TomlError => {
            got_err = e;
            false
        },
    };
    if (ok) {
        throw "error is nil";
    }
    if (!errors_is(got_err, err_invalid_value())) {
        throw "error does not wrap errInvalidValue";
    }
    let pe = match (perr) {
        null => throw "not a ParseError",
        let p: ParseError => p,
    };

    let want = "toml: error: invalid value: \"invalid\"

At line 3, column 7-13:

      1 | k1 = 'asd'
      2 | k2 = 'ok'
      3 | k3 = 'invalid'
                ^^^^^^^
";
    assert.equal(pe.error_with_usage(), want)
}

function decode_typeerror_c(s: string) -> bool throws TomlError {
    let _ = decode<UnmarshalTypeErrorC>(s);
    true
}

// type Enum2 uint8 with a pointer-receiver UnmarshalTOML.
class Enum2 {
    v: int,

    implements Unmarshaler {
        function unmarshal_toml(self, text: Any?) -> Enum2 throws TomlError {
            let s = match (text) {
                let s: string => s,
                _ => go_panic("interface conversion: interface {} is not string"),
            };
            let t = s.trim();
            match (t) {
                "ok" => Enum2 { v: 1 },
                _ => {
                    throw GoError { msg: `${err_invalid_value().error()}: ${go.quote(t)}`, wrapped: err_invalid_value() }
                },
            }
        }
    }
}

class MarshalErrorC {
    K1: string @alias("k1"),
    K2: Enum2 @alias("k2"),
    K3: Enum2 @alias("k3"),
}

function decode_marshalerror_c(s: string) -> bool throws TomlError {
    let _ = decode<MarshalErrorC>(s);
    true
}

test "TestMarshalError" {
    let perr: ParseError? = null;
    let got_err: TomlError? = null;
    let ok = decode_marshalerror_c("k1 = 'asd'\nk2 = 'ok'\nk3 = 'invalid'\nk4 = 'ok'") catch (err) {
        let pe: ParseError => {
            perr = pe;
            got_err = pe;
            false
        },
        let e: TomlError => {
            got_err = e;
            false
        },
    };
    if (ok) {
        throw "error is nil";
    }
    if (!errors_is(got_err, err_invalid_value())) {
        throw "error does not wrap errInvalidValue";
    }
    let pe = match (perr) {
        null => throw "not a ParseError",
        let p: ParseError => p,
    };

    let want = "toml: error: invalid value: \"invalid\"

At line 3, column 7-13:

      1 | k1 = 'asd'
      2 | k2 = 'ok'
      3 | k3 = 'invalid'
                ^^^^^^^
";
    assert.equal(pe.error_with_usage(), want)
}

function get_err(tml: string) -> ParseError {
    let perr: ParseError? = null;
    let ok = decode_kind("map", tml) catch (err) {
        let pe: ParseError => {
            perr = pe;
            false
        },
        let e: TomlError => {
            throw `not a ParseError: ${e.error()}`
        },
    };
    if (ok) {
        throw "err is nil";
    }
    perr ?? go_panic("unreachable")
}

test "TestErrorIndent" {
    let err = get_err("\tspaces = xxx");
    let want = "toml: error: expected value but found \"xxx\" instead

At line 1, column 11-13:

      1 |         spaces = xxx
                           ^^^
";
    assert.equal(err.error_with_usage(), want);

    err = get_err("\tspaces\t=\txxx");
    want = "toml: error: expected value but found \"xxx\" instead

At line 1, column 11-13:

      1 |         spaces  =       xxx
                                  ^^^
";
    assert.equal(err.error_with_usage(), want);

    err = get_err("\txxx \t = \t 1\n\tspaces\t=\txxx");
    want = "toml: error: expected value but found \"xxx\" instead

At line 2, column 11-13:

      1 |         xxx      =       1
      2 |         spaces  =       xxx
                                  ^^^
";
    assert.equal(err.error_with_usage(), want)
}
