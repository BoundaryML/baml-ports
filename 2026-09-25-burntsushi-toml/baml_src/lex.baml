// Port of lex.go.
//
// The Go lexer is a state machine in the style of Rob Pike's "Lexical Scanning
// in Go": every state is a function `func(*lexer) stateFn` that returns the
// next state. The port keeps the exact same states and transitions, but a
// state is an enum variant (`StateFn`) and `run_state` dispatches on it; see
// PORTING.md ("state functions") for why.
//
// Go indexes strings by byte, and positions reported in errors are byte
// offsets. The port lexes the raw UTF-8 bytes of the input (an `int[]`),
// decoding runes with the `root.go` utf8 shim, so positions are identical.

enum ItemType {
    Error,
    EOF,
    Text,
    String,
    StringEsc,
    RawString,
    MultilineString,
    RawMultilineString,
    Bool,
    Integer,
    Float,
    Datetime,
    Array, // the start of an array
    ArrayEnd,
    TableStart,
    TableEnd,
    ArrayTableStart,
    ArrayTableEnd,
    KeyStart,
    KeyEnd,
    CommentStart,
    InlineTableStart,
    InlineTableEnd,
}

// const eof = 0
function eof() -> int {
    0
}

// type stateFn func(lx *lexer) stateFn
//
// Every state function of the Go lexer is a variant here; `Nil` is Go's nil
// stateFn (returned after an error or EOF has been emitted).
enum StateFn {
    Nil,
    LexTop,
    LexTopEnd,
    LexTableStart,
    LexTableEnd,
    LexArrayTableEnd,
    LexTableNameStart,
    LexTableNameEnd,
    LexBareName,
    LexQuotedName,
    LexKeyStart,
    LexKeyNameStart,
    LexKeyEnd,
    LexValue,
    LexArrayValue,
    LexArrayValueEnd,
    LexArrayEnd,
    LexInlineTableValue,
    LexInlineTableValueEnd,
    LexInlineTableEnd,
    LexString,
    LexMultilineString,
    LexRawString,
    LexMultilineRawString,
    LexMultilineStringEscape,
    LexStringEscape,
    LexHexEscape,
    LexShortUnicodeEscape,
    LexLongUnicodeEscape,
    LexNumberOrDateStart,
    LexNumberOrDate,
    LexDatetime,
    LexHexInteger,
    LexOctalInteger,
    LexBinaryInteger,
    LexDecimalNumber,
    LexDecimalNumberStart,
    LexBaseNumberOrDate,
    LexFloat,
    LexBool,
    LexCommentStart,
    LexComment,
}

// func (p Position) String() string
function position_string(p: Position) -> string {
    `at line ${p.line}; start ${p.start}; length ${p.len}`
}

class Lexer {
    input: int[], // the document as UTF-8 bytes
    start: int,
    pos: int,
    line: int,
    state: StateFn,
    items: Item[], // Go: a buffered channel; here a FIFO queue.
    esc: bool,

    // Allow for backing up up to 4 runes. This is necessary because TOML
    // contains 3-rune tokens (""" and ''').
    prev_widths: int[],
    nprev: int, // how many of prevWidths are in use
    at_eof: bool, // If we emit an eof, we can still back up, but it is not OK to call next again.

    // A stack of state functions used to maintain context.
    //
    // The idea is to reuse parts of the state machine in various places. For
    // example, values can appear at the top level or within arbitrarily nested
    // arrays. The last state on the stack is used after a value has been lexed.
    // Similarly for comments.
    stack: StateFn[],

    function next_item(self) -> Item {
        while (true) {
            if (self.items.length() > 0) {
                return self.items.shift() ?? bug("empty item queue");
            }
            if (self.state == StateFn.Nil) {
                bug("lexer state is nil but no items are queued");
            }
            self.state = run_state(self, self.state);
        }
        bug("unreachable")
    }

    function push(self, state: StateFn) -> void {
        self.stack.push(state);
    }

    function pop(self) -> StateFn {
        if (self.stack.length() == 0) {
            go_panic("BUG in lexer: no states to pop");
        }
        self.stack.pop() ?? StateFn.Nil
    }

    function current(self) -> string {
        root.go.string_slice(self.input, self.start, self.pos)
    }

    function get_pos(self) -> Position {
        let p = Position { line: self.line, col: 0, start: self.start, len: self.pos - self.start };
        if (p.len <= 0) {
            p.len = 1;
        }
        p
    }

    function emit(self, typ: ItemType) -> void {
        // Needed for multiline strings ending with an incomplete UTF-8 sequence.
        if (self.start > self.pos) {
            let _ = self.error(ErrLexUTF8 { b: self.input[self.pos] });
            return;
        }
        self.items.push(Item { typ: typ, pos: self.get_pos(), val: self.current(), err: null });
        self.start = self.pos;
    }

    function emit_trim(self, typ: ItemType) -> void {
        self.items.push(Item { typ: typ, pos: self.get_pos(), val: self.current().trim(), err: null });
        self.start = self.pos;
    }

    function next(self) -> int {
        if (self.at_eof) {
            go_panic("BUG in lexer: next called after EOF");
        }
        if (self.pos >= self.input.length()) {
            self.at_eof = true;
            return eof();
        }

        if (self.input[self.pos] == 10) {
            self.line += 1;
        }
        self.prev_widths[3] = self.prev_widths[2];
        self.prev_widths[2] = self.prev_widths[1];
        self.prev_widths[1] = self.prev_widths[0];
        if (self.nprev < 4) {
            self.nprev += 1;
        }

        let d = root.go.decode_rune(self.input, self.pos);
        let r = d.r;
        let w = d.size;
        if (r == root.go.rune_error() && w == 1) {
            let _ = self.error(ErrLexUTF8 { b: self.input[self.pos] });
            return root.go.rune_error();
        }

        // Note: don't use peek() here, as this calls next().
        if (is_control(r) || (r == 13 && (self.input.length() - 1 == self.pos || self.input[self.pos + 1] != 10))) {
            let _ = self.error_control_char(r);
            return root.go.rune_error();
        }

        self.prev_widths[0] = w;
        self.pos += w;
        r
    }

    // ignore skips over the pending input before this point.
    function ignore(self) -> void {
        self.start = self.pos;
    }

    // backup steps back one rune. Can be called 4 times between calls to next.
    function backup(self) -> void {
        if (self.at_eof) {
            self.at_eof = false;
            return;
        }
        if (self.nprev < 1) {
            go_panic("BUG in lexer: backed up too far");
        }
        let w = self.prev_widths[0];
        self.prev_widths[0] = self.prev_widths[1];
        self.prev_widths[1] = self.prev_widths[2];
        self.prev_widths[2] = self.prev_widths[3];
        self.nprev -= 1;

        self.pos -= w;
        if (self.pos < self.input.length() && self.input[self.pos] == 10) {
            self.line -= 1;
        }
    }

    // accept consumes the next rune if it's equal to `valid`.
    function accept(self, valid: int) -> bool {
        if (self.next() == valid) {
            return true;
        }
        self.backup();
        false
    }

    // peek returns but does not consume the next rune in the input.
    function peek(self) -> int {
        let r = self.next();
        self.backup();
        r
    }

    // skip ignores all input that matches the given predicate.
    function skip(self, pred: (int) -> bool) -> void {
        while (true) {
            let r = self.next();
            if (pred(r)) {
                continue;
            }
            self.backup();
            self.ignore();
            return;
        }
    }

    // error stops all lexing by emitting an error and returning `nil`.
    //
    // Note that any value that is a character is escaped if it's a special
    // character (newlines, tabs, etc.).
    function error(self, err: TomlError) -> StateFn {
        self.items.push(Item { typ: ItemType.Error, pos: self.get_pos(), val: "", err: err });
        StateFn.Nil
    }

    // errorfPrevline is like error(), but sets the position to the last column of
    // the previous line.
    //
    // This is so that unexpected EOF or NL errors don't show on a new blank line.
    function error_prev_line(self, err: TomlError) -> StateFn {
        let pos = self.get_pos();
        pos.line -= 1;
        pos.len = 1;
        pos.start = self.pos - 1;
        self.items.push(Item { typ: ItemType.Error, pos: pos, val: "", err: err });
        StateFn.Nil
    }

    // errorPos is like error(), but allows explicitly setting the position.
    function error_pos(self, start: int, length: int, err: TomlError) -> StateFn {
        let pos = self.get_pos();
        pos.start = start;
        pos.len = length;
        self.items.push(Item { typ: ItemType.Error, pos: pos, val: "", err: err });
        StateFn.Nil
    }

    // errorf is like error, and creates a new error.
    //
    // Go takes a format string and arguments; BAML has no varargs/printf, so
    // callers pass the already-formatted message.
    function errorf(self, msg: string) -> StateFn {
        if (self.at_eof) {
            let pos = self.get_pos();
            if (self.pos >= 1 && self.input[self.pos - 1] == 10) {
                pos.line -= 1;
            }
            pos.len = 1;
            pos.start = self.pos - 1;
            self.items.push(Item { typ: ItemType.Error, pos: pos, val: "", err: GoError { msg: msg } });
            return StateFn.Nil;
        }
        self.items.push(Item { typ: ItemType.Error, pos: self.get_pos(), val: "", err: GoError { msg: msg } });
        StateFn.Nil
    }

    function error_control_char(self, cc: int) -> StateFn {
        self.error_pos(self.pos - 1, 1, ErrLexControl { r: cc })
    }
}

class Item {
    typ: ItemType,
    val: string,
    err: TomlError?,
    pos: Position,

    implements baml.ToString {
        function to_string(self) -> string throws never {
            `(${item_type_string(self.typ)}, ${self.val})`
        }
    }
}

function lex(input: int[]) -> Lexer {
    Lexer {
        input: input,
        start: 0,
        pos: 0,
        line: 1,
        state: StateFn.LexTop,
        items: [],
        esc: false,
        prev_widths: [0, 0, 0, 0],
        nprev: 0,
        at_eof: false,
        stack: [],
    }
}

// Dispatch a state "function" (see the comment on StateFn).
function run_state(lx: Lexer, s: StateFn) -> StateFn {
    match (s) {
        StateFn.Nil => bug("called nil state function"),
        StateFn.LexTop => lex_top(lx),
        StateFn.LexTopEnd => lex_top_end(lx),
        StateFn.LexTableStart => lex_table_start(lx),
        StateFn.LexTableEnd => lex_table_end(lx),
        StateFn.LexArrayTableEnd => lex_array_table_end(lx),
        StateFn.LexTableNameStart => lex_table_name_start(lx),
        StateFn.LexTableNameEnd => lex_table_name_end(lx),
        StateFn.LexBareName => lex_bare_name(lx),
        StateFn.LexQuotedName => lex_quoted_name(lx),
        StateFn.LexKeyStart => lex_key_start(lx),
        StateFn.LexKeyNameStart => lex_key_name_start(lx),
        StateFn.LexKeyEnd => lex_key_end(lx),
        StateFn.LexValue => lex_value(lx),
        StateFn.LexArrayValue => lex_array_value(lx),
        StateFn.LexArrayValueEnd => lex_array_value_end(lx),
        StateFn.LexArrayEnd => lex_array_end(lx),
        StateFn.LexInlineTableValue => lex_inline_table_value(lx),
        StateFn.LexInlineTableValueEnd => lex_inline_table_value_end(lx),
        StateFn.LexInlineTableEnd => lex_inline_table_end(lx),
        StateFn.LexString => lex_string(lx),
        StateFn.LexMultilineString => lex_multiline_string(lx),
        StateFn.LexRawString => lex_raw_string(lx),
        StateFn.LexMultilineRawString => lex_multiline_raw_string(lx),
        StateFn.LexMultilineStringEscape => lex_multiline_string_escape(lx),
        StateFn.LexStringEscape => lex_string_escape(lx),
        StateFn.LexHexEscape => lex_hex_escape(lx),
        StateFn.LexShortUnicodeEscape => lex_short_unicode_escape(lx),
        StateFn.LexLongUnicodeEscape => lex_long_unicode_escape(lx),
        StateFn.LexNumberOrDateStart => lex_number_or_date_start(lx),
        StateFn.LexNumberOrDate => lex_number_or_date(lx),
        StateFn.LexDatetime => lex_datetime(lx),
        StateFn.LexHexInteger => lex_hex_integer(lx),
        StateFn.LexOctalInteger => lex_octal_integer(lx),
        StateFn.LexBinaryInteger => lex_binary_integer(lx),
        StateFn.LexDecimalNumber => lex_decimal_number(lx),
        StateFn.LexDecimalNumberStart => lex_decimal_number_start(lx),
        StateFn.LexBaseNumberOrDate => lex_base_number_or_date(lx),
        StateFn.LexFloat => lex_float(lx),
        StateFn.LexBool => lex_bool(lx),
        StateFn.LexCommentStart => lex_comment_start(lx),
        StateFn.LexComment => lex_comment(lx),
    }
}

// lexTop consumes elements at the top level of TOML data.
function lex_top(lx: Lexer) -> StateFn {
    let r = lx.next();
    if (is_whitespace(r) || is_nl(r)) {
        return lex_skip(lx, StateFn.LexTop);
    }
    if (r == 35) { // '#'
        lx.push(StateFn.LexTop);
        return StateFn.LexCommentStart;
    }
    if (r == 91) { // '['
        return StateFn.LexTableStart;
    }
    if (r == eof()) {
        if (lx.pos > lx.start) {
            // TODO: never reached? I think this can only occur on a bug in the
            // lexer(?)
            return lx.errorf("unexpected EOF");
        }
        lx.emit(ItemType.EOF);
        return StateFn.Nil;
    }

    // At this point, the only valid item can be a key, so we back up
    // and let the key lexer do the rest.
    lx.backup();
    lx.push(StateFn.LexTopEnd);
    StateFn.LexKeyStart
}

// lexTopEnd is entered whenever a top-level item has been consumed. (A value
// or a table.) It must see only whitespace, and will turn back to lexTop
// upon a newline. If it sees EOF, it will quit the lexer successfully.
function lex_top_end(lx: Lexer) -> StateFn {
    let r = lx.next();
    if (r == 35) {
        // a comment will read to a newline for us.
        lx.push(StateFn.LexTop);
        return StateFn.LexCommentStart;
    }
    if (is_whitespace(r)) {
        return StateFn.LexTopEnd;
    }
    if (is_nl(r)) {
        lx.ignore();
        return StateFn.LexTop;
    }
    if (r == eof()) {
        lx.emit(ItemType.EOF);
        return StateFn.Nil;
    }
    lx.errorf(`expected a top-level item to end with a newline, comment, or EOF, but got ${root.go.quote_rune(r)} instead`)
}

// lexTable lexes the beginning of a table. Namely, it makes sure that
// it starts with a character other than '.' and ']'.
// It assumes that '[' has already been consumed.
// It also handles the case that this is an item in an array of tables.
// e.g., '[[name]]'.
function lex_table_start(lx: Lexer) -> StateFn {
    if (lx.peek() == 91) {
        let _ = lx.next();
        lx.emit(ItemType.ArrayTableStart);
        lx.push(StateFn.LexArrayTableEnd);
    } else {
        lx.emit(ItemType.TableStart);
        lx.push(StateFn.LexTableEnd);
    }
    StateFn.LexTableNameStart
}

function lex_table_end(lx: Lexer) -> StateFn {
    lx.emit(ItemType.TableEnd);
    StateFn.LexTopEnd
}

function lex_array_table_end(lx: Lexer) -> StateFn {
    let r = lx.next();
    if (r != 93) {
        return lx.errorf(`expected end of table array name delimiter ']', but got ${root.go.quote_rune(r)} instead`);
    }
    lx.emit(ItemType.ArrayTableEnd);
    StateFn.LexTopEnd
}

function lex_table_name_start(lx: Lexer) -> StateFn {
    lx.skip(is_whitespace);
    let r = lx.peek();
    if (r == 93 || r == eof()) {
        return lx.errorf("unexpected end of table name (table names cannot be empty)");
    }
    if (r == 46) {
        return lx.errorf("unexpected table separator (table names cannot be empty)");
    }
    if (r == 34 || r == 39) {
        lx.ignore();
        lx.push(StateFn.LexTableNameEnd);
        return StateFn.LexQuotedName;
    }
    lx.push(StateFn.LexTableNameEnd);
    StateFn.LexBareName
}

// lexTableNameEnd reads the end of a piece of a table name, optionally
// consuming whitespace.
function lex_table_name_end(lx: Lexer) -> StateFn {
    lx.skip(is_whitespace);
    let r = lx.next();
    if (r == 46) {
        lx.ignore();
        return StateFn.LexTableNameStart;
    }
    if (r == 93) {
        return lx.pop();
    }
    lx.errorf(`expected '.' or ']' to end table name, but got ${root.go.quote_rune(r)} instead`)
}

// lexBareName lexes one part of a key or table.
//
// It assumes that at least one valid character for the table has already been
// read.
//
// Lexes only one part, e.g. only 'a' inside 'a.b'.
function lex_bare_name(lx: Lexer) -> StateFn {
    let r = lx.next();
    if (is_bare_key_char(r)) {
        return StateFn.LexBareName;
    }
    lx.backup();
    lx.emit(ItemType.Text);
    lx.pop()
}

// lexQuotedName lexes one part of a quoted key or table name. It assumes that
// it starts lexing at the quote itself (" or ').
//
// Lexes only one part, e.g. only '"a"' inside '"a".b'.
function lex_quoted_name(lx: Lexer) -> StateFn {
    let r = lx.next();
    if (r == 34) {
        lx.ignore(); // ignore the '"'
        return StateFn.LexString;
    }
    if (r == 39) {
        lx.ignore(); // ignore the "'"
        return StateFn.LexRawString;
    }
    // TODO: I don't think any of the below conditions can ever be reached?
    if (is_whitespace(r)) {
        return lex_skip(lx, StateFn.LexValue);
    }
    if (r == eof()) {
        return lx.errorf("unexpected EOF; expected value");
    }
    lx.errorf(`expected value but found ${root.go.quote_rune(r)} instead`)
}

// lexKeyStart consumes all key parts until a '='.
function lex_key_start(lx: Lexer) -> StateFn {
    lx.skip(is_whitespace);
    let r = lx.peek();
    if (r == 61 || r == eof()) {
        return lx.errorf("unexpected '=': key name appears blank");
    }
    if (r == 46) {
        return lx.errorf("unexpected '.': keys cannot start with a '.'");
    }
    if (r == 34 || r == 39) {
        lx.ignore();
    }
    // (Go: `fallthrough` into the bare-key default case.)
    lx.emit(ItemType.KeyStart);
    StateFn.LexKeyNameStart
}

function lex_key_name_start(lx: Lexer) -> StateFn {
    lx.skip(is_whitespace);
    let r = lx.peek();
    if (r == 34 || r == 39) {
        lx.ignore();
        lx.push(StateFn.LexKeyEnd);
        return StateFn.LexQuotedName;
    }
    // TODO: I think these can never be reached?
    if (r == 61 || r == eof()) {
        return lx.errorf("unexpected '='");
    }
    if (r == 46) {
        return lx.errorf("unexpected '.'");
    }
    lx.push(StateFn.LexKeyEnd);
    StateFn.LexBareName
}

// lexKeyEnd consumes the end of a key and trims whitespace (up to the key
// separator).
function lex_key_end(lx: Lexer) -> StateFn {
    lx.skip(is_whitespace);
    let r = lx.next();
    if (is_whitespace(r)) {
        return lex_skip(lx, StateFn.LexKeyEnd);
    }
    if (r == eof()) { // TODO: never reached
        return lx.errorf("unexpected EOF; expected key separator '='");
    }
    if (r == 46) {
        lx.ignore();
        return StateFn.LexKeyNameStart;
    }
    if (r == 61) {
        lx.emit(ItemType.KeyEnd);
        return lex_skip(lx, StateFn.LexValue);
    }
    if (r == 10) {
        return lx.error_prev_line(GoError { msg: `expected '.' or '=', but got ${root.go.quote_rune(r)} instead` });
    }
    lx.errorf(`expected '.' or '=', but got ${root.go.quote_rune(r)} instead`)
}

// lexValue starts the consumption of a value anywhere a value is expected.
// lexValue will ignore whitespace.
// After a value is lexed, the last state on the next is popped and returned.
function lex_value(lx: Lexer) -> StateFn {
    // We allow whitespace to precede a value, but NOT newlines.
    // In array syntax, the array states are responsible for ignoring newlines.
    let r = lx.next();
    if (is_whitespace(r)) {
        return lex_skip(lx, StateFn.LexValue);
    }
    if (is_digit(r)) {
        lx.backup(); // avoid an extra state and use the same as above
        return StateFn.LexNumberOrDateStart;
    }
    if (r == 91) { // '['
        lx.ignore();
        lx.emit(ItemType.Array);
        return StateFn.LexArrayValue;
    }
    if (r == 123) { // '{'
        lx.ignore();
        lx.emit(ItemType.InlineTableStart);
        return StateFn.LexInlineTableValue;
    }
    if (r == 34) { // '"'
        if (lx.accept(34)) {
            if (lx.accept(34)) {
                lx.ignore(); // Ignore """
                return StateFn.LexMultilineString;
            }
            lx.backup();
        }
        lx.ignore(); // ignore the '"'
        return StateFn.LexString;
    }
    if (r == 39) { // '\''
        if (lx.accept(39)) {
            if (lx.accept(39)) {
                lx.ignore(); // Ignore """
                return StateFn.LexMultilineRawString;
            }
            lx.backup();
        }
        lx.ignore(); // ignore the "'"
        return StateFn.LexRawString;
    }
    if (r == 46) { // special error case, be kind to users
        return lx.errorf("floats must start with a digit, not '.'");
    }
    if (r == 105 || r == 110) { // 'i', 'n'
        if ((lx.accept(110) && lx.accept(102)) || (lx.accept(97) && lx.accept(110))) {
            lx.emit(ItemType.Float);
            return lx.pop();
        }
    } else if (r == 45 || r == 43) { // '-', '+'
        return StateFn.LexDecimalNumberStart;
    }
    if (root.go.is_letter(r)) {
        // Be permissive here; lexBool will give a nice error if the
        // user wrote something like
        //   x = foo
        // (i.e. not 'true' or 'false' but is something else word-like.)
        lx.backup();
        return StateFn.LexBool;
    }
    if (r == eof()) {
        return lx.errorf("unexpected EOF; expected value");
    }
    if (r == 10) {
        return lx.error_prev_line(GoError { msg: `expected value but found ${root.go.quote_rune(r)} instead` });
    }
    lx.errorf(`expected value but found ${root.go.quote_rune(r)} instead`)
}

// lexArrayValue consumes one value in an array. It assumes that '[' or ','
// have already been consumed. All whitespace and newlines are ignored.
function lex_array_value(lx: Lexer) -> StateFn {
    let r = lx.next();
    if (is_whitespace(r) || is_nl(r)) {
        return lex_skip(lx, StateFn.LexArrayValue);
    }
    if (r == 35) {
        lx.push(StateFn.LexArrayValue);
        return StateFn.LexCommentStart;
    }
    if (r == 44) {
        return lx.errorf("unexpected comma");
    }
    if (r == 93) {
        return StateFn.LexArrayEnd;
    }

    lx.backup();
    lx.push(StateFn.LexArrayValueEnd);
    StateFn.LexValue
}

// lexArrayValueEnd consumes everything between the end of an array value and
// the next value (or the end of the array): it ignores whitespace and newlines
// and expects either a ',' or a ']'.
function lex_array_value_end(lx: Lexer) -> StateFn {
    let r = lx.next();
    if (is_whitespace(r) || is_nl(r)) {
        return lex_skip(lx, StateFn.LexArrayValueEnd);
    }
    if (r == 35) {
        lx.push(StateFn.LexArrayValueEnd);
        return StateFn.LexCommentStart;
    }
    if (r == 44) {
        lx.ignore();
        return StateFn.LexArrayValue; // move on to the next value
    }
    if (r == 93) {
        return StateFn.LexArrayEnd;
    }
    lx.errorf(`expected a comma (',') or array terminator (']'), but got ${rune_or_eof(r)}`)
}

// lexArrayEnd finishes the lexing of an array.
// It assumes that a ']' has just been consumed.
function lex_array_end(lx: Lexer) -> StateFn {
    lx.ignore();
    lx.emit(ItemType.ArrayEnd);
    lx.pop()
}

// lexInlineTableValue consumes one key/value pair in an inline table.
// It assumes that '{' or ',' have already been consumed. Whitespace is ignored.
function lex_inline_table_value(lx: Lexer) -> StateFn {
    let r = lx.next();
    if (is_whitespace(r)) {
        return lex_skip(lx, StateFn.LexInlineTableValue);
    }
    if (is_nl(r)) {
        return lex_skip(lx, StateFn.LexInlineTableValue);
    }
    if (r == 35) {
        lx.push(StateFn.LexInlineTableValue);
        return StateFn.LexCommentStart;
    }
    if (r == 44) {
        return lx.errorf("unexpected comma");
    }
    if (r == 125) {
        return StateFn.LexInlineTableEnd;
    }
    lx.backup();
    lx.push(StateFn.LexInlineTableValueEnd);
    StateFn.LexKeyStart
}

// lexInlineTableValueEnd consumes everything between the end of an inline table
// key/value pair and the next pair (or the end of the table):
// it ignores whitespace and expects either a ',' or a '}'.
function lex_inline_table_value_end(lx: Lexer) -> StateFn {
    let r = lx.next();
    if (is_whitespace(r)) {
        return lex_skip(lx, StateFn.LexInlineTableValueEnd);
    }
    if (is_nl(r)) {
        return lex_skip(lx, StateFn.LexInlineTableValueEnd);
    }
    if (r == 35) {
        lx.push(StateFn.LexInlineTableValueEnd);
        return StateFn.LexCommentStart;
    }
    if (r == 44) {
        lx.ignore();
        lx.skip(is_whitespace);
        if (lx.peek() == 125) {
            return StateFn.LexInlineTableValueEnd;
        }
        return StateFn.LexInlineTableValue;
    }
    if (r == 125) {
        return StateFn.LexInlineTableEnd;
    }
    lx.errorf(`expected a comma or an inline table terminator '}', but got ${rune_or_eof(r)} instead`)
}

function rune_or_eof(r: int) -> string {
    if (r == eof()) {
        return "end of file";
    }
    "'" + root.go.rune_string(r) + "'"
}

// lexInlineTableEnd finishes the lexing of an inline table.
// It assumes that a '}' has just been consumed.
function lex_inline_table_end(lx: Lexer) -> StateFn {
    lx.ignore();
    lx.emit(ItemType.InlineTableEnd);
    lx.pop()
}

// lexString consumes the inner contents of a string. It assumes that the
// beginning '"' has already been consumed and ignored.
function lex_string(lx: Lexer) -> StateFn {
    let r = lx.next();
    if (r == eof()) {
        return lx.errorf(`unexpected EOF; expected '"'`);
    }
    if (is_nl(r)) {
        return lx.error_prev_line(ErrLexStringNL {});
    }
    if (r == 92) { // '\\'
        lx.push(StateFn.LexString);
        return StateFn.LexStringEscape;
    }
    if (r == 34) {
        lx.backup();
        if (lx.esc) {
            lx.esc = false;
            lx.emit(ItemType.StringEsc);
        } else {
            lx.emit(ItemType.String);
        }
        let _ = lx.next();
        lx.ignore();
        return lx.pop();
    }
    StateFn.LexString
}

// lexMultilineString consumes the inner contents of a string. It assumes that
// the beginning '"""' has already been consumed and ignored.
function lex_multiline_string(lx: Lexer) -> StateFn {
    let r = lx.next();
    if (r == eof()) {
        return lx.errorf(`unexpected EOF; expected '"""'`);
    }
    if (r == 92) {
        return StateFn.LexMultilineStringEscape;
    }
    if (r == 34) {
        /// Found " → try to read two more "".
        if (lx.accept(34)) {
            if (lx.accept(34)) {
                /// Peek ahead: the string can contain " and "", including at the
                /// end: """str"""""
                /// 6 or more at the end, however, is an error.
                if (lx.peek() == 34) {
                    /// Check if we already lexed 5 's; if so we have 6 now, and
                    /// that's just too many man!
                    ///
                    /// Second check is for the edge case:
                    ///
                    ///            two quotes allowed.
                    ///            vv
                    ///   """lol \""""""
                    ///          ^^  ^^^---- closing three
                    ///     escaped
                    ///
                    /// But ugly, but it works
                    let cur = lx.current();
                    if (cur.ends_with(`"""""`) && !cur.ends_with(`\\"""""`)) {
                        return lx.errorf(`unexpected '""""""'`);
                    }
                    lx.backup();
                    lx.backup();
                    return StateFn.LexMultilineString;
                }

                lx.backup(); /// backup: don't include the """ in the item.
                lx.backup();
                lx.backup();
                lx.esc = false;
                lx.emit(ItemType.MultilineString);
                let _ = lx.next(); /// Read over ''' again and discard it.
                let _ = lx.next();
                let _ = lx.next();
                lx.ignore();
                return lx.pop();
            }
            lx.backup();
        }
        return StateFn.LexMultilineString;
    }
    StateFn.LexMultilineString
}

// lexRawString consumes a raw string. Nothing can be escaped in such a string.
// It assumes that the beginning "'" has already been consumed and ignored.
function lex_raw_string(lx: Lexer) -> StateFn {
    let r = lx.next();
    if (r == eof()) {
        return lx.errorf(`unexpected EOF; expected "'"`);
    }
    if (is_nl(r)) {
        return lx.error_prev_line(ErrLexStringNL {});
    }
    if (r == 39) {
        lx.backup();
        lx.emit(ItemType.RawString);
        let _ = lx.next();
        lx.ignore();
        return lx.pop();
    }
    StateFn.LexRawString
}

// lexMultilineRawString consumes a raw string. Nothing can be escaped in such a
// string. It assumes that the beginning triple-' has already been consumed and
// ignored.
function lex_multiline_raw_string(lx: Lexer) -> StateFn {
    let r = lx.next();
    if (r == eof()) {
        return lx.errorf(`unexpected EOF; expected "'''"`);
    }
    if (r == 39) {
        /// Found ' → try to read two more ''.
        if (lx.accept(39)) {
            if (lx.accept(39)) {
                /// Peek ahead: the string can contain ' and '', including at the
                /// end: '''str'''''
                /// 6 or more at the end, however, is an error.
                if (lx.peek() == 39) {
                    /// Check if we already lexed 5 's; if so we have 6 now, and
                    /// that's just too many man!
                    if (lx.current().ends_with("'''''")) {
                        return lx.errorf(`unexpected "''''''"`);
                    }
                    lx.backup();
                    lx.backup();
                    return StateFn.LexMultilineRawString;
                }

                lx.backup(); /// backup: don't include the ''' in the item.
                lx.backup();
                lx.backup();
                lx.emit(ItemType.RawMultilineString);
                let _ = lx.next(); /// Read over ''' again and discard it.
                let _ = lx.next();
                let _ = lx.next();
                lx.ignore();
                return lx.pop();
            }
            lx.backup();
        }
        return StateFn.LexMultilineRawString;
    }
    StateFn.LexMultilineRawString
}

// lexMultilineStringEscape consumes an escaped character. It assumes that the
// preceding '\\' has already been consumed.
function lex_multiline_string_escape(lx: Lexer) -> StateFn {
    if (is_nl(lx.next())) { /// \ escaping newline.
        return StateFn.LexMultilineString;
    }
    lx.backup();
    lx.push(StateFn.LexMultilineString);
    lex_string_escape(lx)
}

function lex_string_escape(lx: Lexer) -> StateFn {
    lx.esc = true;
    let r = lx.next();
    match (r) {
        // 'e', 'b', 't', 'n', 'f', 'r', '"', ' ', '\t', '\\'
        //
        // Inside """ .. """ strings you can use \ to escape newlines, and any
        // amount of whitespace can be between the \ and \n.
        101 | 98 | 116 | 110 | 102 | 114 | 34 | 32 | 9 | 92 => lx.pop(),
        120 => StateFn.LexHexEscape, // 'x'
        117 => StateFn.LexShortUnicodeEscape, // 'u'
        85 => StateFn.LexLongUnicodeEscape, // 'U'
        _ => lx.error(ErrLexEscape { r: r }),
    }
}

function lex_hex_escape(lx: Lexer) -> StateFn {
    let i = 0;
    while (i < 2) {
        let r = lx.next();
        if (!is_hex(r)) {
            return lx.errorf(`expected two hexadecimal digits after '\\x', but got ${root.go.quote(lx.current())} instead`);
        }
        i += 1;
    }
    lx.pop()
}

function lex_short_unicode_escape(lx: Lexer) -> StateFn {
    let i = 0;
    while (i < 4) {
        let r = lx.next();
        if (!is_hex(r)) {
            return lx.errorf(`expected four hexadecimal digits after '\\u', but got ${root.go.quote(lx.current())} instead`);
        }
        i += 1;
    }
    lx.pop()
}

function lex_long_unicode_escape(lx: Lexer) -> StateFn {
    let i = 0;
    while (i < 8) {
        let r = lx.next();
        if (!is_hex(r)) {
            return lx.errorf(`expected eight hexadecimal digits after '\\U', but got ${root.go.quote(lx.current())} instead`);
        }
        i += 1;
    }
    lx.pop()
}

// lexNumberOrDateStart processes the first character of a value which begins
// with a digit. It exists to catch values starting with '0', so that
// lexBaseNumberOrDate can differentiate base prefixed integers from other
// types.
function lex_number_or_date_start(lx: Lexer) -> StateFn {
    if (lx.next() == 48) {
        return StateFn.LexBaseNumberOrDate;
    }
    StateFn.LexNumberOrDate
}

// lexNumberOrDate consumes either an integer, float or datetime.
function lex_number_or_date(lx: Lexer) -> StateFn {
    let r = lx.next();
    if (is_digit(r)) {
        return StateFn.LexNumberOrDate;
    }
    match (r) {
        45 | 58 => { return StateFn.LexDatetime; }, // '-', ':'
        95 => { return StateFn.LexDecimalNumber; }, // '_'
        46 | 101 | 69 => { return StateFn.LexFloat; }, // '.', 'e', 'E'
        _ => {},
    }

    lx.backup();
    lx.emit(ItemType.Integer);
    lx.pop()
}

// lexDatetime consumes a Datetime, to a first approximation.
// The parser validates that it matches one of the accepted formats.
function lex_datetime(lx: Lexer) -> StateFn {
    let r = lx.next();
    if (is_digit(r)) {
        return StateFn.LexDatetime;
    }
    match (r) {
        // '-', ':', 'T', 't', ' ', '.', 'Z', 'z', '+'
        45 | 58 | 84 | 116 | 32 | 46 | 90 | 122 | 43 => { return StateFn.LexDatetime; },
        _ => {},
    }

    lx.backup();
    lx.emit_trim(ItemType.Datetime);
    lx.pop()
}

// lexHexInteger consumes a hexadecimal integer after seeing the '0x' prefix.
function lex_hex_integer(lx: Lexer) -> StateFn {
    let r = lx.next();
    if (is_hex(r)) {
        return StateFn.LexHexInteger;
    }
    if (r == 95) {
        return StateFn.LexHexInteger;
    }

    lx.backup();
    lx.emit(ItemType.Integer);
    lx.pop()
}

// lexOctalInteger consumes an octal integer after seeing the '0o' prefix.
function lex_octal_integer(lx: Lexer) -> StateFn {
    let r = lx.next();
    if (is_octal(r)) {
        return StateFn.LexOctalInteger;
    }
    if (r == 95) {
        return StateFn.LexOctalInteger;
    }

    lx.backup();
    lx.emit(ItemType.Integer);
    lx.pop()
}

// lexBinaryInteger consumes a binary integer after seeing the '0b' prefix.
function lex_binary_integer(lx: Lexer) -> StateFn {
    let r = lx.next();
    if (is_binary(r)) {
        return StateFn.LexBinaryInteger;
    }
    if (r == 95) {
        return StateFn.LexBinaryInteger;
    }

    lx.backup();
    lx.emit(ItemType.Integer);
    lx.pop()
}

// lexDecimalNumber consumes a decimal float or integer.
function lex_decimal_number(lx: Lexer) -> StateFn {
    let r = lx.next();
    if (is_digit(r)) {
        return StateFn.LexDecimalNumber;
    }
    if (r == 46 || r == 101 || r == 69) {
        return StateFn.LexFloat;
    }
    if (r == 95) {
        return StateFn.LexDecimalNumber;
    }

    lx.backup();
    lx.emit(ItemType.Integer);
    lx.pop()
}

// lexDecimalNumber consumes the first digit of a number beginning with a sign.
// It assumes the sign has already been consumed. Values which start with a sign
// are only allowed to be decimal integers or floats.
//
// The special "nan" and "inf" values are also recognized.
function lex_decimal_number_start(lx: Lexer) -> StateFn {
    let r = lx.next();

    // Special error cases to give users better error messages
    if (r == 105) { // 'i'
        if (!lx.accept(110) || !lx.accept(102)) {
            return lx.errorf(`invalid float: '${lx.current()}'`);
        }
        lx.emit(ItemType.Float);
        return lx.pop();
    }
    if (r == 110) { // 'n'
        if (!lx.accept(97) || !lx.accept(110)) {
            return lx.errorf(`invalid float: '${lx.current()}'`);
        }
        lx.emit(ItemType.Float);
        return lx.pop();
    }
    if (r == 48) { // '0'
        let p = lx.peek();
        if (p == 98 || p == 111 || p == 120) {
            return lx.errorf(`cannot use sign with non-decimal numbers: '${lx.current()}${root.go.rune_string(p)}'`);
        }
    }
    if (r == 46) {
        return lx.errorf("floats must start with a digit, not '.'");
    }

    if (is_digit(r)) {
        return StateFn.LexDecimalNumber;
    }

    lx.errorf(`expected a digit but got ${root.go.quote_rune(r)}`)
}

// lexBaseNumberOrDate differentiates between the possible values which
// start with '0'. It assumes that before reaching this state, the initial '0'
// has been consumed.
function lex_base_number_or_date(lx: Lexer) -> StateFn {
    let r = lx.next();
    // Note: All datetimes start with at least two digits, so we don't
    // handle date characters (':', '-', etc.) here.
    if (is_digit(r)) {
        return StateFn.LexNumberOrDate;
    }
    if (r == 95) {
        // Can only be decimal, because there can't be an underscore
        // between the '0' and the base designator, and dates can't
        // contain underscores.
        return StateFn.LexDecimalNumber;
    }
    if (r == 46 || r == 101 || r == 69) {
        return StateFn.LexFloat;
    }
    if (r == 98) { // 'b'
        let p = lx.peek();
        if (!is_binary(p)) {
            let _ = lx.errorf(`not a binary number: '${lx.current()}${root.go.rune_string(p)}'`);
        }
        return StateFn.LexBinaryInteger;
    }
    if (r == 111) { // 'o'
        let p = lx.peek();
        if (!is_octal(p)) {
            let _ = lx.errorf(`not an octal number: '${lx.current()}${root.go.rune_string(p)}'`);
        }
        return StateFn.LexOctalInteger;
    }
    if (r == 120) { // 'x'
        let p = lx.peek();
        if (!is_hex(p)) {
            let _ = lx.errorf(`not a hexadecimal number: '${lx.current()}${root.go.rune_string(p)}'`);
        }
        return StateFn.LexHexInteger;
    }

    lx.backup();
    lx.emit(ItemType.Integer);
    lx.pop()
}

// lexFloat consumes the elements of a float. It allows any sequence of
// float-like characters, so floats emitted by the lexer are only a first
// approximation and must be validated by the parser.
function lex_float(lx: Lexer) -> StateFn {
    let r = lx.next();
    if (is_digit(r)) {
        return StateFn.LexFloat;
    }
    match (r) {
        // '_', '.', '-', '+', 'e', 'E'
        95 | 46 | 45 | 43 | 101 | 69 => { return StateFn.LexFloat; },
        _ => {},
    }

    lx.backup();
    lx.emit(ItemType.Float);
    lx.pop()
}

// lexBool consumes a bool string: 'true' or 'false.
function lex_bool(lx: Lexer) -> StateFn {
    let rs: int[] = [];
    while (true) {
        let r = lx.next();
        if (!root.go.is_letter(r)) {
            lx.backup();
            break;
        }
        rs.push(r);
    }
    let s = rs.map((r) -> { root.go.rune_string(r) }).join("");
    if (s == "true" || s == "false") {
        lx.emit(ItemType.Bool);
        return lx.pop();
    }
    lx.errorf(`expected value but found ${root.go.quote(s)} instead`)
}

// lexCommentStart begins the lexing of a comment. It will emit
// itemCommentStart and consume no characters, passing control to lexComment.
function lex_comment_start(lx: Lexer) -> StateFn {
    lx.ignore();
    lx.emit(ItemType.CommentStart);
    StateFn.LexComment
}

// lexComment lexes an entire comment. It assumes that '#' has been consumed.
// It will consume *up to* the first newline character, and pass control
// back to the last state on the stack.
function lex_comment(lx: Lexer) -> StateFn {
    let r = lx.next();
    if (is_nl(r) || r == eof()) {
        lx.backup();
        lx.emit(ItemType.Text);
        return lx.pop();
    }
    StateFn.LexComment
}

// lexSkip ignores all slurped input and moves on to the next state.
function lex_skip(lx: Lexer, next_state: StateFn) -> StateFn {
    lx.ignore();
    next_state
}

// func (s stateFn) String() string
//
// Go recovers the function name with runtime.FuncForPC; the port maps each
// enum variant back to the Go function name it stands for.
function state_fn_string(s: StateFn) -> string {
    if (s == StateFn.Nil) {
        return "<nil>";
    }
    let name = s.to_string();
    // "LexFooBar" -> "lexFooBar"
    name.slice(0, 1).to_lower_case() + name.slice(1, name.length()) + "()"
}

function item_type_string(itype: ItemType) -> string {
    match (itype) {
        ItemType.Error => "Error",
        ItemType.EOF => "EOF",
        ItemType.Text => "Text",
        ItemType.String | ItemType.StringEsc | ItemType.RawString | ItemType.MultilineString | ItemType.RawMultilineString => "String",
        ItemType.Bool => "Bool",
        ItemType.Integer => "Integer",
        ItemType.Float => "Float",
        ItemType.Datetime => "DateTime",
        ItemType.Array => "Array",
        ItemType.ArrayEnd => "ArrayEnd",
        ItemType.TableStart => "TableStart",
        ItemType.TableEnd => "TableEnd",
        ItemType.ArrayTableStart => "ArrayTableStart",
        ItemType.ArrayTableEnd => "ArrayTableEnd",
        ItemType.KeyStart => "KeyStart",
        ItemType.KeyEnd => "KeyEnd",
        ItemType.CommentStart => "CommentStart",
        ItemType.InlineTableStart => "InlineTableStart",
        ItemType.InlineTableEnd => "InlineTableEnd",
    }
}

function is_whitespace(r: int) -> bool {
    r == 9 || r == 32
}

function is_nl(r: int) -> bool {
    r == 10 || r == 13
}

function is_control(r: int) -> bool { // Control characters except \t, \r, \n
    if (r == 9 || r == 13 || r == 10) {
        return false;
    }
    (r >= 0 && r <= 31) || r == 127
}

function is_digit(r: int) -> bool {
    r >= 48 && r <= 57
}

function is_binary(r: int) -> bool {
    r == 48 || r == 49
}

function is_octal(r: int) -> bool {
    r >= 48 && r <= 55
}

function is_hex(r: int) -> bool {
    (r >= 48 && r <= 57) || ((r | 32) >= 97 && (r | 32) <= 102)
}

function is_bare_key_char(r: int) -> bool {
    (r >= 65 && r <= 90) || (r >= 97 && r <= 122) || (r >= 48 && r <= 57) || r == 95 || r == 45
}
