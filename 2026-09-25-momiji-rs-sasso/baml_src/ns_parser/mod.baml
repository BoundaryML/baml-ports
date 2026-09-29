// Ported from sasso `src/parser/mod.rs` (namespace `root.parser`).
//
// The SCSS parser: a character-level recursive-descent parser.
//
// SCSS is context-sensitive — a leading `:` can begin a declaration
// value or a pseudo-class selector — so statements are disambiguated by
// a bounded lookahead ([`Parser::classify`]) that finds whether a
// top-level `{` (a rule) or `;`/`}` (a declaration) comes first.

// mod at_rules → namespace `root.parser.at_rules`

// mod control_flow → namespace `root.parser.control_flow`

// mod statements → namespace `root.parser.statements`

// mod value → namespace `root.parser.value`

enum NextKind {
    Rule,
    Declaration,
}

/// How [`Parser::parse_template_mode`] treats `/* */` (loud) and `//` (silent)
/// comments encountered while scanning a selector / prelude / property.
enum CommentMode {
    /// Keep every comment verbatim in the literal (legacy behaviour: values
    /// and grammars that capture text exactly).
    Keep,
    /// Drop every comment, replacing it with a single space, at any nesting.
    /// dart-sass normalises selectors and structured grammars this way, so a
    /// comment behaves purely as whitespace (`a/**/b` → `a b`).
    Strip,
    /// Strip only *top-level* (outside `()`/`[]`) comments, replacing them with
    /// a single space; comments nested inside parentheses are kept verbatim.
    /// dart-sass parses `@supports` and `@-moz-document` preludes with a
    /// structured grammar that drops trivia comments between tokens while the
    /// parenthesised content is captured raw (`(a /**/ b)` is preserved).
    StripTopLevel,
    /// Unknown / interpolation-prelude directives (`@page`, `@font-face`,
    /// `@layer`, any unknown `@foo`, …): a `//` silent comment is dropped to
    /// end of line (it acts as whitespace); a `/* */` loud comment is *kept*
    /// verbatim. A leading comment is already removed by `skip_ws_inline`
    /// before the prelude template starts. Applied only at the top level;
    /// nested content is kept verbatim.
    UnknownPrelude,
    /// A declaration's property name: like `Strip`, except that ONE loud
    /// comment directly glued to the name (no whitespace between) joins it
    /// verbatim — dart `_declarationOrBuffer` appends `rawText(loudComment)`
    /// to the name buffer when `/*` immediately follows the identifier
    /// (issue_1422: `foo/*c*/: bar` keeps the comment, `foo /*c*/ : bar`
    /// drops it).
    DeclName,
}

enum MessageKind {
    Warn,
    Debug,
    Error,
}

/// `trim(piece)` as a new shared buffer, or `None` when the trim removed
/// nothing and the piece can be left alone. A literal's text is shared, so
/// copying it to say "unchanged" is pure waste.
function trimmed_lit(piece: string, trim: (string) -> string throws unknown) -> string? {
    let trimmed = trim(piece);
    if (trimmed.length() != piece.length()) {
        trimmed
    } else {
        null
    }
}

/// Trim leading/trailing whitespace from a parsed prelude template, dropping
/// any whitespace-only literals at the ends. Interior interpolation is kept.
function trim_prelude(pieces: root.ast.TplPiece[]) -> root.ast.TplPiece[] {
    // PORT: `let mut pieces = pieces;` — parameters are reassignable; the
    // caller hands over a freshly parsed template, so it is edited in place.
    if let first: root.ast.TplPiece_Lit = pieces.at(0) {
        // A prelude written without leading padding — the usual one — has
        // nothing to trim, and keeps the buffer it was parsed into.
        let first_text = first._0;
        let trimmed = trimmed_lit(first_text, root.std.trim_start);
        if (trimmed != null) {
            // PORT: `*first = trimmed` — the slot gets a new piece instead of
            // mutating a piece object that could be shared.
            first_text = trimmed;
            pieces[0] = root.ast.TplPiece_Lit { _0: first_text };
        }
        if (first_text == "") {
            let _ = pieces.remove_at(0);
        }
    }
    if let last: root.ast.TplPiece_Lit = root.std.last(pieces) {
        let last_text = last._0;
        let trimmed = trimmed_lit(last_text, root.std.trim_end);
        if (trimmed != null) {
            // PORT: `*last = trimmed` (see above).
            last_text = trimmed;
            pieces[pieces.length() - 1] = root.ast.TplPiece_Lit { _0: last_text };
        }
        if (last_text == "") {
            let _ = pieces.pop();
        }
    }
    pieces
}

/// Whether a parsed media identifier template is exactly the plain keyword
/// `kw` (case-insensitively). Interpolation never matches a keyword.
function media_ident_is(pieces: root.ast.TplPiece[], kw: string) -> bool {
    match (media_ident_plain(pieces)) {
        let s: string => root.std.eq_ignore_ascii_case(s, kw),
        null => false,
    }
}

/// The plain text of a media identifier template, or `None` if it contains
/// interpolation.
function media_ident_plain(pieces: root.ast.TplPiece[]) -> string? {
    match (pieces) {
        [root.ast.TplPiece_Lit { _0: let s }] => s,
        [] => "",
        _ => null,
    }
}

/// The plain (non-interpolated) text of a template, or `None` if it contains
/// any `#{…}` interpolation (dart-sass `Interpolation.asPlain`).
function tpl_plain(pieces: root.ast.TplPiece[]) -> string? {
    let s = root.std.StrBuf.new();
    for (let p in pieces) {
        match (p) {
            let t: root.ast.TplPiece_Lit => s.push_str(t._0),
            let _i: root.ast.TplPiece_Interp => {
                return null;
            },
            _ => root.std.unreachable(),
        }
    }
    s.as_str()
}

/// If `pieces` is exactly one `#{…}` interpolation (no surrounding literal),
/// return its expression; otherwise `None`.
function tpl_single_interp(pieces: root.ast.TplPiece[]) -> root.ast.Expr? {
    if (pieces.length() == 1) {
        if let e: root.ast.TplPiece_Interp = pieces[0] {
            return e._0;
        }
    }
    null
}

/// Whether a `@supports` declaration name is a CSS custom property: an unquoted
/// identifier whose plain text begins with `--` (dart-sass
/// `SupportsDeclaration.isCustomProperty`).
function expr_is_custom_property(name: root.ast.Expr) -> bool {
    match (name) {
        let ident: root.ast.Expr_Ident => match (ident._0.at(0)) {
            let s: root.ast.TplPiece_Lit => s._0.starts_with("--"),
            _ => false,
        },
        _ => false,
    }
}

/// Whether two range comparison operators form a valid range: both must point
/// the same direction (`<`/`<=` then `<`/`<=`, or `>`/`>=` then `>`/`>=`), and
/// neither may be `=`.
function range_ops_compatible(op1: string, op2: string) -> bool {
    let dir = (op: string) -> bool? {
        match (op) {
            "<" | "<=" => true,
            ">" | ">=" => false,
            _ => null,
        }
    };
    // PORT: `match (dir(op1), dir(op2))` → an `if` over both results.
    let a = dir(op1);
    let b = dir(op2);
    if (a != null && b != null) {
        a == b
    } else {
        false
    }
}

class Parser {
    sc: root.scanner.Scanner,
    /// Interned unit names for numeric literals. A stylesheet spells a handful
    /// of distinct units — `px`, `rem`, `%`, and the empty one — hundreds of
    /// times each, and the AST hands its `Rc<str>` to every value the literal
    /// evaluates to, so one buffer per distinct name serves the whole file.
    /// Searched linearly: the list is a few entries long, never more.
    unit_names: string[],
    /// Depth of enclosing `calc()`/math-function contexts. Inside one, `/`
    /// is always real division (never a slash separator) and `+`/`-` must be
    /// surrounded by whitespace.
    calc_depth: int,
    /// Set by `parse_unicode_range` when a `?`-wildcard range token is
    /// immediately followed (no whitespace) by an identifier. dart-sass treats
    /// the wildcard as terminal and starts a new space-list element with an
    /// implicit separator (`U+A?BCDE` -> `U+A? BCDE`); `space_list` consumes
    /// the flag to continue without requiring whitespace.
    pending_unicode_split: bool,
    /// Depth of enclosing `{ … }` blocks. `@use`/`@forward` are only valid at
    /// the top level (depth 0); inside any block they are "This at-rule is not
    /// allowed here.".
    block_depth: int,
    /// When set, `parse_template_mode` records each top-level `#{…}`
    /// interpolation's expression span (line, start col, col of `}`) here —
    /// used by rule selectors for the dual-span "error in interpolated
    /// output" diagnostic. Nested template parses (inside an interpolation's
    /// expression) suspend collection.
    collect_interp_spans: bool,
    interp_spans: root.std.Tuple3<int, int, int>[],
    /// Set once a top-level statement that is *not* a variable declaration,
    /// comment, `@charset`, `@use`, or `@forward` has been parsed. A later
    /// `@use`/`@forward` then errors ("@use rules must be written before any
    /// other rules.").
    seen_non_module_stmt: bool,
    /// Plain-CSS mode (a `.css` file loaded via `@use`/`@forward`). SassScript
    /// and Sass-only statements are rejected: this is the analogue of dart-sass's
    /// `CssParser`. Nesting is still parsed (CSS nesting is preserved in output);
    /// the difference is that Sass features become errors.
    plain_css: bool,
    /// Set once an interpolation body has been read in plain-CSS mode, where
    /// `#{…}` is an error wherever it stands. A backtracking attempt (the
    /// modern `if()` grammar) that read one therefore cannot be retried under
    /// another grammar — no grammar accepts that text — so it must propagate
    /// the error dart reports instead of the one the retry would raise.
    plain_css_interp: bool,
    /// Indented-syntax mode: the input is the position-preserving SCSS
    /// reconstruction of a `.sass` file (see `sass_parser`), and the few
    /// grammar liberties dart's `SassParser` takes over `ScssParser` apply —
    /// an `@import` URL may be an unquoted token.
    indented: bool,
    /// Skip inline whitespace; report whether any was consumed.
    function skip_ws_inline(self) -> bool {
        let any = false;
        while (true) {
            match (self.sc.peek()) {
                let c: string if c.is_whitespace() => {
                    self.sc.bump();
                    any = true;
                },
                // `/* ... */` loud and `// ...` silent comments act as
                // whitespace between value tokens (`c /* d */ e`, `c // d`).
                "/" if self.sc.peek_at(1) == "*" => {
                    self.sc.bump();
                    self.sc.bump();
                    while let c: string = self.sc.peek() {
                        if (c == "*" && self.sc.peek_at(1) == "/") {
                            self.sc.bump();
                            self.sc.bump();
                            break;
                        }
                        self.sc.bump();
                    }
                    any = true;
                },
                // In plain CSS `//` is not a comment: each `/` is a value token
                // (`1///bar` round-trips), so it must not be skipped.
                "/" if self.sc.peek_at(1) == "/" && !self.plain_css => {
                    while let c: string = self.sc.peek() {
                        if (c == "\n") {
                            break;
                        }
                        self.sc.bump();
                    }
                    any = true;
                },
                _ => {
                    break;
                },
            }
        }
        any
    }

    /// Parse a `{ … }` statement block.
    function parse_braced_body(self) -> root.ast.Stmt[] {
        self.parse_braced_body_lines()._0
    }

    /// Parse a `{ … }` statement block, also reporting the `{`/`}` source
    /// lines (for the serializer's trailing-comment rule; `file` stays 0).
    function parse_braced_body_lines(self) -> root.std.Tuple2<root.ast.Stmt[], root.ast.SrcLines> {
        self.skip_ws_inline();
        let brace_line = self.sc.position().line;
        if (!self.sc.eat("{")) {
            throw root.error.Error.at("expected \"{\".", self.sc.position());
        }
        self.block_depth += 1;
        // PORT: Rust keeps the `Result` and decrements `block_depth` before
        // `body?`; the error arm restores the depth before re-throwing.
        let body = self.parse_statements(false) catch (e) {
            let err: root.error.Error => {
                self.block_depth -= 1;
                throw err;
            }
        };
        self.block_depth -= 1;
        if (!self.sc.eat("}")) {
            throw root.error.Error.at("expected \"}\"", self.sc.position());
        }
        let lines = root.ast.SrcLines {
            file: 0,
            start: brace_line,
            end: self.sc.position().line,
            col: 0,
            start_col: 0,
            map_file: 0,
            map_line: 0,
        };
        root.std.Tuple2 { _0: body, _1: lines }
    }

    /// Parse an interpolated template (selector or property name) up to,
    /// but not including, one of `stops` at bracket depth 0.
    function parse_template(self, stops: string[]) -> root.ast.TplPiece[] {
        self.parse_template_mode(stops, CommentMode.Keep)
    }

    /// Consume the `/* ... */` loud comment at the cursor (the leading `/*`
    /// must already be confirmed by the caller) and return its inner text
    /// including the surrounding delimiters, i.e. the full `/* ... */`.
    function consume_loud_comment(self) -> string {
        let s = root.std.StrBuf.from("/*");
        self.sc.bump();
        self.sc.bump();
        while (true) {
            match (self.sc.peek()) {
                null => {
                    break;
                },
                "*" if self.sc.peek_at(1) == "/" => {
                    self.sc.bump();
                    self.sc.bump();
                    s.push_str("*/");
                    break;
                },
                let c: string => {
                    s.push(c);
                    self.sc.bump();
                },
            }
        }
        s.as_str()
    }

    /// Consume the `// ...` silent comment at the cursor up to (but not
    /// including) the newline; the leading `//` must already be confirmed.
    function consume_silent_comment(self) -> void {
        while let c: string = self.sc.peek() {
            if (c == "\n") {
                break;
            }
            self.sc.bump();
        }
    }

    /// In plain-CSS mode, a `#{…}` interpolation is an error. dart-sass raises
    /// it at the END of `singleInterpolation`, once the body has parsed and the
    /// `}` is consumed, so a malformed expression inside reports itself first
    /// (`#{$x}` is "Sass variables aren't allowed in plain CSS", `#{ }` is
    /// "Expected expression") and the caret spans the whole `#{…}`. `mark` must
    /// be the cursor as it stood at the `#`.
    function reject_plain_css_interp(self, mark: root.scanner.Mark) -> void {
        if (self.plain_css) {
            throw root.error.Error.at("Interpolation isn't allowed in plain CSS.", mark.pos_())
                .with_length(self.sc.byte_len_from(mark));
        }
    }

    /// Parse the expression inside a `#{ … }` (cursor just past the `{`).
    ///
    /// Interpolation is a full SassScript context even when it sits inside a
    /// calculation: dart-sass evaluates `#{-$x}` in `calc(#{-$x} - 1px)` as an
    /// ordinary expression and splices the resulting text into the calc. So
    /// the calc-only grammar restrictions (no `-$x`, no `- 1px`, no `/`
    /// division) must not leak into the interpolated expression — suspend
    /// `calc_depth` for its duration.
    function parse_interp_value(self) -> root.ast.Expr {
        self.plain_css_interp = self.plain_css_interp || self.plain_css;
        let saved = self.calc_depth;
        self.calc_depth = 0;
        // PORT: Rust keeps the `Result` and restores `calc_depth` before
        // returning it; the error arm restores it before re-throwing.
        let e = self.parse_value() catch (err) {
            let x: root.error.Error => {
                self.calc_depth = saved;
                throw x;
            }
        };
        self.calc_depth = saved;
        e
    }

    function parse_template_mode(
        self,
        stops: string[],
        comments: CommentMode,
    ) -> root.ast.TplPiece[] {
        let pieces: root.ast.TplPiece[] = [];
        let lit = root.std.StrBuf.new();
        let paren = 0;
        let bracket = 0;
        // Whether a glued loud comment already joined a DeclName template
        // (dart appends at most ONE `rawText(loudComment)` to the name).
        let glued = false;
        while let c: string = self.sc.peek() {
            // A CSS escape makes the next character literal identifier text:
            // an escaped stop char (`.govuk-\!-font-size-19`) is part of the
            // selector, never a boundary (dart consumes `\X` in identifiers).
            // A NEWLINE is not a character it can escape — dart's `escape()`
            // fails there, so `.a,\` + `.b` is an error rather than a selector
            // containing an escaped line break.
            if (c == "\\") {
                let next = self.sc.peek_at(1);
                if (next == "\n" || next == "\r" || next == "\f") {
                    self.sc.bump();
                    throw root.error.Error.at("Expected escape sequence.", self.sc.position());
                }
                lit.push(c);
                self.sc.bump();
                let n = self.sc.bump();
                if (n != null) {
                    lit.push(n);
                }
                continue;
            }
            if (paren == 0 && bracket == 0 && stops.includes(c)) {
                break;
            }
            // Comment handling depends on the mode and nesting depth.
            if (c == "/" && comments != CommentMode.Keep) {
                let top = paren == 0 && bracket == 0;
                let strip_here = match (comments) {
                    CommentMode.Strip | CommentMode.DeclName => true,
                    CommentMode.StripTopLevel | CommentMode.UnknownPrelude => top,
                    CommentMode.Keep => false,
                };
                if (strip_here) {
                    match (self.sc.peek_at(1)) {
                        "*" => {
                            // A loud comment is kept verbatim for unknown
                            // preludes (dart-sass preserves it) and when glued
                            // directly to a declaration name (issue_1422);
                            // otherwise it collapses to whitespace.
                            let last = lit.last_char();
                            let glue_to_name = comments == CommentMode.DeclName
                                && !glued
                                && (
                                    if (last != null) {
                                        !last.is_whitespace()
                                    } else {
                                        pieces.length() != 0
                                    }
                                );
                            if (comments == CommentMode.UnknownPrelude || glue_to_name) {
                                let text = self.consume_loud_comment();
                                lit.push_str(text);
                                glued = true;
                            } else {
                                let _ = self.consume_loud_comment();
                                lit.push(" ");
                            }
                            continue;
                        },
                        "/" => {
                            // A silent comment always acts as whitespace. For
                            // unknown preludes nothing is inserted (the trailing
                            // newline left in the source provides the gap and
                            // edges are trimmed); otherwise a single space.
                            self.consume_silent_comment();
                            if (comments != CommentMode.UnknownPrelude) {
                                lit.push(" ");
                            }
                            continue;
                        },
                        _ => {},
                    }
                }
            }
            // For unknown at-rule preludes dart collapses a whitespace run
            // WITHOUT a newline to one space and keeps a run WITH one from
            // its first newline (`@asdf a  b` → `a b`; `c \n   d` →
            // `c\n   d`). Comments terminate a run, so `foo //\n  bar`
            // keeps foo's trailing space AND the newline indent.
            if (comments == CommentMode.UnknownPrelude && c.is_whitespace()) {
                let run = root.std.StrBuf.new();
                while (root.std.is_whitespace(self.sc.peek())) {
                    let w = self.sc.bump();
                    if (w != null) {
                        run.push(w);
                    }
                }
                let run_text = run.as_str();
                match (run_text.index_of("\n")) {
                    let nl: int => lit.push_str(run_text.slice(nl, run_text.length())),
                    null => lit.push(" "),
                }
                continue;
            }
            match (c) {
                "#" if self.sc.peek_at(1) == "{" => {
                    let interp_mark = self.sc.mark();
                    if (!lit.is_empty()) {
                        pieces.push(take_lit(lit));
                    }
                    self.sc.bump();
                    self.sc.bump();
                    // Record the expression span for a rule selector's
                    // dual-span diagnostic; nested template parses inside the
                    // expression suspend collection.
                    let span_start = self.sc.position();
                    let collect = self.collect_interp_spans;
                    self.collect_interp_spans = false;
                    let e = self.parse_value();
                    self.skip_ws_inline();
                    self.collect_interp_spans = collect;
                    if (collect) {
                        let end = self.sc.position();
                        self.interp_spans.push(
                            root.std.Tuple3 { _0: span_start.line, _1: span_start.col, _2: end.col },
                        );
                    }
                    if (!self.sc.eat("}")) {
                        throw root.error.Error.at("expected \"}\"", self.sc.position());
                    }
                    self.reject_plain_css_interp(interp_mark);
                    pieces.push(root.ast.TplPiece_Interp { _0: e });
                },
                "\"" | "'" => {
                    // The quote characters are literal prelude text, but `#{…}`
                    // inside the string is still interpolation (dart-sass resolves
                    // `"foo#{x}baz"` in an at-rule prelude to `"foo<x>baz"`).
                    lit.push(c);
                    self.sc.bump();
                    while let ch: string = self.sc.peek() {
                        if (ch == "\\") {
                            // A `\` before a newline is a CSS line continuation
                            // and the pair vanishes, as in any other string;
                            // copying it through left a raw line break in the
                            // selector text.
                            let next = self.sc.peek_at(1);
                            if (next == "\n" || next == "\r" || next == "\f") {
                                self.sc.bump();
                                if (self.sc.peek() == "\r") {
                                    self.sc.bump();
                                    self.sc.eat("\n");
                                } else {
                                    self.sc.bump();
                                }
                                continue;
                            }
                            lit.push(ch);
                            self.sc.bump();
                            let n = self.sc.bump();
                            if (n != null) {
                                lit.push(n);
                            }
                            continue;
                        }
                        if (ch == "#" && self.sc.peek_at(1) == "{") {
                            let interp_mark = self.sc.mark();
                            if (!lit.is_empty()) {
                                pieces.push(take_lit(lit));
                            }
                            self.sc.bump();
                            self.sc.bump();
                            let e = self.parse_value();
                            self.skip_ws_inline();
                            if (!self.sc.eat("}")) {
                                throw root.error.Error.at("expected \"}\"", self.sc.position());
                            }
                            self.reject_plain_css_interp(interp_mark);
                            pieces.push(root.ast.TplPiece_Interp { _0: e });
                            continue;
                        }
                        lit.push(ch);
                        self.sc.bump();
                        if (ch == c) {
                            break;
                        }
                    }
                },
                "(" => {
                    paren += 1;
                    lit.push(c);
                    self.sc.bump();
                },
                ")" => {
                    paren -= 1;
                    lit.push(c);
                    self.sc.bump();
                },
                "[" => {
                    bracket += 1;
                    lit.push(c);
                    self.sc.bump();
                },
                "]" => {
                    bracket -= 1;
                    lit.push(c);
                    self.sc.bump();
                },
                _ => {
                    lit.push(c);
                    self.sc.bump();
                },
            }
        }
        if (!lit.is_empty()) {
            pieces.push(take_lit(lit));
        }
        pieces
    }

    /// Consume a CSS escape sequence and return the code point it stands for.
    /// The opening `\` must be the next character; it is consumed here. A
    /// backslash at end-of-input decodes to U+FFFD, matching dart-sass; a
    /// backslash before a NEWLINE is not an escape at all (dart's `escape()`
    /// fails there, and only its string reader drops the pair as a CSS line
    /// continuation before ever calling it). Errors on an out-of-range Unicode
    /// code point.
    function consume_escape(self) -> string {
        let pos = self.sc.position();
        self.sc.bump(); // the leading backslash
        match (self.sc.peek()) {
            // A line continuation is legal only inside a quoted string, and the
            // string reader consumes it before this is reached.
            "\n" | "\r" | "\f" => {
                throw root.error.Error.at("Expected escape sequence.", self.sc.position());
            },
            let c: string if c.is_ascii_hex() => {
                let value = 0;
                let digits = 0;
                while (digits < 6) {
                    match (self.sc.peek()) {
                        let h: string if h.is_ascii_hex() => {
                            value = value * 16 + (root.std.to_digit(h, 16) ?? 0);
                            self.sc.bump();
                            digits += 1;
                        },
                        _ => {
                            break;
                        },
                    }
                }
                // A single trailing whitespace character terminates the escape
                // and is consumed — one CHARACTER, so the `\n` of a CRLF is
                // left behind and still separates tokens: dart reads
                // `b: \61` + CRLF + `b` as the two identifiers `a b`.
                if (is_escape_terminator(self.sc.peek())) {
                    self.sc.bump();
                }
                if (value > 0x10FFFF) {
                    throw root.error.Error.at("Invalid Unicode code point.", pos);
                }
                // Surrogate code points cannot be represented and become the
                // replacement char; NUL is kept (it serializes as `\0 `).
                root.std.chr(value) ?? "�"
            },
            // Any other character escapes to itself literally.
            let c: string => {
                self.sc.bump();
                c
            },
            null => "�",
        }
    }

    /// Read a variable name (after `$`), normalizing `_` to `-` like dart's
    /// `variableName()` — `$a_b` and `$a-b` are the SAME variable. Function /
    /// mixin and CSS identifiers keep their spelling (normalization for those
    /// happens at definition/lookup, so plain-CSS output preserves `_`).
    function read_variable_name(self) -> string {
        let name = self.read_ident_name();
        if (name.includes("_")) {
            name.replace_all("_", "-")
        } else {
            name
        }
    }

    function read_ident_name(self) -> string {
        let s = root.std.StrBuf.new();
        while (true) {
            match (self.sc.peek()) {
                let c: string if is_ident_char(c) => {
                    self.sc.bump();
                    s.push(c);
                },
                // dart decodes identifier escapes at the lexer level —
                // `@w\61rn` IS `@warn` and `f\6Fo-bar` defines `foo-bar` —
                // so the stored name is the decoded spelling.
                "\\" => s.push(self.read_escape_char()),
                _ => {
                    break;
                },
            }
        }
        if (s.is_empty()) {
            throw root.error.Error.at("expected an identifier", self.sc.position());
        }
        s.as_str()
    }

    /// Read a module namespace / forward prefix. dart-sass requires a real
    /// identifier here, so a digit-leading name (`@use "x" as 0`) is
    /// "Expected identifier." rather than a silently-accepted namespace.
    function read_namespace_ident(self) -> string {
        if (root.std.is_ascii_digit(self.sc.peek())) {
            throw root.error.Error.at("Expected identifier.", self.sc.position());
        }
        self.read_ident_name()
    }

    /// Decode a `\` escape inside an identifier (dart `escapeCharacter`):
    /// 1-6 hex digits (plus one optional trailing whitespace) become the
    /// code point — zero, surrogates, and out-of-range collapse to U+FFFD —
    /// and any other character is taken literally.
    function read_escape_char(self) -> string {
        self.sc.bump(); // the backslash
        let first = match (self.sc.peek()) {
            // A form feed is a newline to dart (`isNewline`), so it is not a
            // character an escape can stand for either.
            null | "\n" | "\r" | "\f" => {
                throw root.error.Error.at("Expected escape sequence.", self.sc.position());
            },
            let c: string => c,
        };
        if (first.is_ascii_hex()) {
            let value = 0;
            for (let _ in baml.iter.Range.new(0, 6)) {
                match (self.sc.peek()) {
                    let c: string if c.is_ascii_hex() => {
                        value = (value << 4) + root.std.unwrap(root.std.to_digit(c, 16));
                        self.sc.bump();
                    },
                    _ => {
                        break;
                    },
                }
            }
            // One optional whitespace terminator. A CRLF counts as ONE line
            // break here — `--x: \61` + CRLF + `b` is `ab` in dart, with no
            // line break left in the value.
            if (is_escape_terminator(self.sc.peek())) {
                let cr = self.sc.peek() == "\r";
                self.sc.bump();
                if (cr) {
                    self.sc.eat("\n");
                }
            }
            // NUL is KEPT (it re-serializes as `\0 `, dart's consume_escape);
            // surrogates and out-of-range code points become the replacement
            // character.
            if ((value >= 0xD800 && value <= 0xDFFF) || value > 0x10FFFF) {
                return "�";
            }
            root.std.chr(value) ?? "�"
        } else {
            self.sc.bump();
            first
        }
    }
}

/// PORT: helper for Rust's `matches!(x, Some(' ' | '\t' | '\n' | '\r' | '\u{c}'))`
/// (the whitespace that may terminate a hex escape).
function is_escape_terminator(c: string?) -> bool {
    c == " " || c == "\t" || c == "\n" || c == "\r" || c == "\f"
}

/// Parse a complete stylesheet (SCSS).
function parse(src: string) -> root.ast.Stylesheet {
    parse_inner(src, false, false)
}

/// Parse a plain-CSS stylesheet (a loaded `.css` file): the same brace/semicolon
/// grammar, but Sass features are rejected.
function parse_plain_css(src: string) -> root.ast.Stylesheet {
    parse_inner(src, true, false)
}

/// Parse the SCSS reconstruction of an indented-syntax (`.sass`) stylesheet.
function parse_indented(src: string) -> root.ast.Stylesheet {
    parse_inner(src, false, true)
}

function parse_inner(src: string, plain_css: bool, indented: bool) -> root.ast.Stylesheet {
    let p = Parser {
        sc: root.scanner.Scanner.new(src),
        unit_names: [],
        calc_depth: 0,
        pending_unicode_split: false,
        block_depth: 0,
        collect_interp_spans: false,
        interp_spans: [],
        seen_non_module_stmt: false,
        plain_css: plain_css,
        plain_css_interp: false,
        indented: indented,
    };
    let stmts = p.parse_statements(true);
    root.ast.Stylesheet { stmts: stmts }
}

function is_ident_char(c: string) -> bool {
    // dart `isName`: any non-ASCII code point is a valid identifier char
    // (`$vär`, `föö` need no escaping).
    c.is_ascii_alphanumeric() || c == "-" || c == "_" || root.std.ord(c) >= 0x80
}

/// Reject generic/unknown at-rules in a context that forbids them (function
/// bodies, nested property sets), recursing into control-flow bodies.
function reject_at_rules_in(stmts: root.ast.Stmt[]) -> void {
    for (let s in stmts) {
        match (s) {
            root.ast.Stmt_AtRule {} | root.ast.Stmt_InterpAtRule {} => {
                throw root.error.Error.unpositioned("This at-rule is not allowed here.");
            },
            let branches: root.ast.Stmt_If => {
                for (let b in branches._0) {
                    reject_at_rules_in(b.body);
                }
            },
            root.ast.Stmt_For { body: let body }
                | root.ast.Stmt_Each { body: let body }
                | root.ast.Stmt_While { body: let body } =>
            {
                reject_at_rules_in(body);
            },
            _ => {},
        }
    }
}

/// Whether `name` is a global Sass function with no plain-CSS meaning, so a
/// `.css` file calling it is an error (the CSS color/math functions — `rgb`,
/// `hsl`, `grayscale`, `saturate`, `min`, `calc`, … — are deliberately absent,
/// since plain CSS preserves those verbatim).
function is_sass_only_function(name: string) -> bool {
    match (name) {
        // list
        "index"
            | "nth"
            | "set-nth"
            | "join"
            | "append"
            | "zip"
            | "list-separator"
            | "is-bracketed"
            | "length"
            // map
            | "map-get"
            | "map-merge"
            | "map-remove"
            | "map-keys"
            | "map-values"
            | "map-has-key"
            // meta
            | "type-of"
            | "unit"
            | "unitless"
            | "comparable"
            | "inspect"
            | "keywords"
            | "feature-exists"
            | "variable-exists"
            | "global-variable-exists"
            | "function-exists"
            | "mixin-exists"
            | "content-exists"
            | "get-function"
            | "call"
            | "get-mixin"
            // string
            | "str-length"
            | "str-insert"
            | "str-index"
            | "str-slice"
            | "to-upper-case"
            | "to-lower-case"
            | "unique-id"
            // color (Sass-only adjusters / getters, not CSS functions)
            | "mix"
            | "adjust-hue"
            | "lighten"
            | "darken"
            | "desaturate"
            | "opacify"
            | "transparentize"
            | "fade-in"
            | "fade-out"
            | "scale-color"
            | "adjust-color"
            | "change-color"
            | "ie-hex-str"
            // selector
            | "selector-nest"
            | "selector-append"
            | "selector-replace"
            | "selector-unify"
            | "is-superselector"
            | "simple-selectors"
            | "selector-parse"
            | "selector-extend" =>
        {
            true
        },
        _ => false,
    }
}

/// Whether a top-level statement may legally appear *before* a `@use` rule.
/// dart-sass permits variable declarations, loud comments, `@charset`, `@use`,
/// and `@forward`; everything else means a following `@use` is too late.
function stmt_allowed_before_use(stmt: root.ast.Stmt) -> bool {
    match (stmt) {
        root.ast.Stmt_VarDecl {}
            | root.ast.Stmt_Comment {}
            | root.ast.Stmt_Use {}
            | root.ast.Stmt_Forward {} =>
        {
            true
        },
        let at: root.ast.Stmt_AtRule => root.std.eq_ignore_ascii_case(at.name, "charset"),
        _ => false,
    }
}

/// Whether `c` may begin a CSS identifier *without* escaping: an ASCII letter,
/// `_`, or any non-ASCII code point (matches dart-sass `isNameStart`).
function is_name_start_codepoint(c: string) -> bool {
    c.is_ascii_alphabetic() || c == "_" || root.std.ord(c) >= 0x80
}

/// Whether `c` may appear in an identifier body without escaping (matches
/// dart-sass `isName`): a name-start char, an ASCII digit, or `-`.
function is_name_codepoint(c: string) -> bool {
    is_name_start_codepoint(c) || c.is_ascii_numeric() || c == "-"
}

/// Append the canonical spelling of an *escaped* identifier code point to `out`,
/// matching dart-sass's `escape()`. `identifier_start` is true when this escape
/// is the first code point of the identifier (or the code point right after a
/// single leading `-`), in which case digits and `-` are escaped and only a
/// name-start char passes through literally.
function push_ident_escape(out: root.std.StrBuf, c: string, identifier_start: bool) -> void {
    let cp = root.std.ord(c);
    let literal_ok = if (identifier_start) {
        is_name_start_codepoint(c)
    } else {
        is_name_codepoint(c)
    };
    if (literal_ok) {
        out.push(c);
    } else if (cp <= 0x1F || cp == 0x7F || (identifier_start && c.is_ascii_numeric())) {
        // Control characters (and a leading digit) serialize as a hex escape
        // with a trailing space, e.g. `\9 ` for a tab or `\30 ` for a leading 0.
        out.push("\\");
        out.push_str(root.std.hex_lower(cp));
        out.push(" ");
    } else {
        // Other printable ASCII punctuation: a backslash followed by the literal
        // character (e.g. `\:`, `\@`, `\-`).
        out.push("\\");
        out.push(c);
    }
}

/// Classify a function name (the identifier immediately before a `(`) as a
/// "special" CSS function whose argument list must be preserved verbatim
/// rather than parsed as SassScript. Matching is case-insensitive and the
/// returned name is the dart-sass canonical (lower-cased) spelling that is
/// emitted.
///
/// `calc`, `element`, and `expression` are special with or without a single
/// vendor prefix (`-x-`). `type` is special only when *un*prefixed. `url`,
/// `var`, and `env` are handled separately (they have their own raw paths).
function special_function_name(name: string) -> string? {
    let lower = root.std.ascii_lower(name);
    // Strip a single leading vendor prefix: `-<vendor>-`.
    let unprefixed = strip_vendor_prefix(lower);
    match (unprefixed) {
        "calc" | "element" | "expression" => lower,
        // `type` is special only with no vendor prefix.
        "type" if unprefixed == lower => lower,
        _ => null,
    }
}

/// Strip a single leading `-<vendor>-` prefix from an already-lower-cased
/// identifier, returning the remainder. A vendor prefix is `-`, one or more
/// identifier characters, then `-` (e.g. `-webkit-`). If no such prefix is
/// present the whole string is returned unchanged.
function strip_vendor_prefix(lower: string) -> string {
    // PORT: `lower.as_bytes().first() != Some(&b'-')` → `starts_with("-")`;
    // offsets below are char offsets (see the guide's string rules).
    if (!lower.starts_with("-")) {
        return lower;
    }
    // Find the second `-` after at least one inner character.
    let rel = lower.slice(1, lower.length()).index_of("-");
    if (rel != null) {
        if (rel >= 1) {
            return lower.slice(1 + rel + 1, lower.length());
        }
    }
    lower
}

/// Decode the CSS identifier starting at `cs[i]`, resolving `\XXXXXX` hex and
/// `\c` literal escapes, and return it with the index just past its last
/// character. An empty name means there was no identifier there.
function decode_ident(cs: string[], i: int) -> root.std.Tuple2<string, int> {
    let name = root.std.StrBuf.new();
    while let c: string = cs.at(i) {
        if (c == "\\") {
            i += 1;
            let hex = "";
            while (hex.length() < 6 && root.std.is_ascii_hexdigit(cs.at(i))) {
                hex = hex + cs[i];
                i += 1;
            }
            if (hex == "") {
                match (cs.at(i)) {
                    let c2: string => {
                        name.push(c2);
                        i += 1;
                    },
                    null => {
                        break;
                    },
                }
            } else {
                // One whitespace character may terminate a hex escape — dart's
                // `isWhitespace`, which is space, tab and the three CSS
                // newlines, NOT every Unicode space (a vertical tab ends the
                // identifier instead, as the parser reads it).
                if (is_escape_terminator(cs.at(i))) {
                    i += 1;
                    if (cs.at(i - 1) == "\r" && cs.at(i) == "\n") {
                        i += 1;
                    }
                }
                // A surrogate or out-of-range code point becomes the
                // replacement character, as `read_escape_char` resolves it —
                // stopping here instead would report the name's PREFIX
                // (`@import\D800` as `import`), and the line analysis would
                // then apply `@import`'s rules to a generic at-rule.
                // PORT: `u32::from_str_radix(&hex, 16).unwrap_or(0xFFFD)` —
                // `hex` is 1-6 hex digits, so it always parses.
                let value = 0;
                for (let h in hex.chars()) {
                    value = value * 16 + (root.std.to_digit(h, 16) ?? 0);
                }
                name.push(
                    if ((value >= 0xD800 && value <= 0xDFFF) || value > 0x10FFFF) {
                        "�"
                    } else {
                        root.std.chr(value) ?? "�"
                    },
                );
            }
            continue;
        }
        if (is_ident_char(c)) {
            name.push(c);
            i += 1;
            continue;
        }
        break;
    }
    root.std.Tuple2 { _0: name.as_str(), _1: i }
}

/// Whether `name` is a `url(` function — `url` itself or any vendor-prefixed
/// `-x-url`, case-insensitively. dart-sass parses these with its special URL
/// grammar (a plain, unquoted URL is preserved verbatim and the call is
/// emitted as a bare `url(...)`).
function is_url_function(name: string) -> bool {
    let lower = root.std.ascii_lower(name);
    strip_vendor_prefix(lower) == "url"
}

/// Whether `name` (the identifier immediately before a `:`) introduces an IE
/// `progid:` special function — `progid` itself or any vendor-prefixed
/// `-x-progid`, case-insensitively. dart-sass recognises a value-position
/// token of the form `[-vendor-]progid:Name(...)` and preserves its argument
/// list verbatim. The whole `[-vendor-]progid` prefix is lower-cased on emit
/// (the `Name` after the `:` keeps its original case).
function is_progid_name(name: string) -> bool {
    let lower = root.std.ascii_lower(name);
    strip_vendor_prefix(lower) == "progid"
}

/// Validate a modern `if()` condition: an evaluated `sass()` may not coexist
/// in an `and`/`or` chain with an *unparenthesised* multi-token "arbitrary
/// substitution". Parenthesising the substitution shields it (a `sass()`
/// nested in parens is NOT shielded). Returns `(sass_anywhere, direct_multi)`
/// where `sass_anywhere` is true if any `sass()` exists in the subtree
/// (descending through parens), and `direct_multi` is true if an
/// unparenthesised multi-token raw exists at this boolean level.
function validate_if_cond(cond: root.ast.IfCond) -> root.std.Tuple2<bool, bool> {
    let r: root.std.Tuple2<bool, bool> = match (cond) {
        root.ast.IfCond_Sass {} => root.std.Tuple2 { _0: true, _1: false },
        let raw: root.ast.IfCond_Raw => root.std.Tuple2 { _0: false, _1: raw.multi },
        let not_: root.ast.IfCond_Not => validate_if_cond(not_._0),
        // A paren shields a multi-token substitution from the parent level,
        // but a `sass()` inside still propagates.
        let paren: root.ast.IfCond_Paren => {
            let inner = validate_if_cond(paren._0);
            let s = inner._0;
            root.std.Tuple2 { _0: s, _1: false }
        },
        root.ast.IfCond_And { _0: let items } | root.ast.IfCond_Or { _0: let items } => {
            let sass = false;
            let multi = false;
            for (let it in items) {
                let sm = validate_if_cond(it);
                sass = sass || sm._0;
                multi = multi || sm._1;
            }
            root.std.Tuple2 { _0: sass, _1: multi }
        },
        _ => root.std.unreachable(),
    };
    let sass = r._0;
    let multi = r._1;
    if (sass && multi) {
        throw root.error.Error.unpositioned(
            "if() conditions with arbitrary substitutions may not contain sass() expressions.",
        );
    }
    root.std.Tuple2 { _0: sass, _1: multi }
}

/// Whether a quoted `@import` URL (parsed into template pieces) is a *plain
/// CSS* URL — one ending in `.css`, or beginning with a protocol/`//`. Such
/// URLs are emitted verbatim rather than inlined as Sass partials. Only the
/// leading/trailing literal text is inspected (interpolated URLs are dynamic
/// Sass paths and handled elsewhere).
function import_url_is_css(pieces: root.ast.TplPiece[]) -> bool {
    let head = "";
    if let s: root.ast.TplPiece_Lit = pieces.at(0) {
        head = s._0;
    }
    let tail = "";
    if let s: root.ast.TplPiece_Lit = root.std.last(pieces) {
        tail = s._0;
    }
    tail.ends_with(".css")
        || head.starts_with("http://")
        || head.starts_with("https://")
        || head.starts_with("//")
}

/// Drop trailing whitespace-only literal pieces and trim the last literal.
/// Append a single literal character to a template, merging into a trailing
/// `Lit` piece when possible.
///
/// The merge is load-bearing, not an optimization: adjacent literals must stay
/// one piece, because [`import_url_is_css`] reads the first and last piece as
/// whole affixes, [`trim_prelude`] trims only the end pieces, and a template
/// that is a single literal is the one evaluation hands out without copying.
/// Rebuilding the piece is what an `Rc<str>` costs to extend, and this runs a
/// few times per `@import` that has modifiers at all — never in a loop.
function push_lit(pieces: root.ast.TplPiece[], c: string) -> void {
    if let s: root.ast.TplPiece_Lit = root.std.last(pieces) {
        // PORT: `*s = …` — the slot gets a new piece (pieces are shared).
        pieces[pieces.length() - 1] = root.ast.TplPiece_Lit { _0: `${s._0}${c}` };
    } else {
        pieces.push(root.ast.TplPiece_Lit { _0: c });
    }
}

/// End the literal piece accumulated in `lit`, keeping its buffer for the next
/// one. A piece's text is shared from here on — a single-literal template hands
/// it straight to the string it evaluates to — so it is copied into its own
/// allocation exactly once, here.
function take_lit(lit: root.std.StrBuf) -> root.ast.TplPiece {
    let piece = root.ast.TplPiece_Lit { _0: lit.as_str() };
    lit.clear();
    piece
}

/// Whether `expr` is eligible to keep the deprecated `/` slash spelling.
/// dart-sass keeps the slash only between number literals (including a
/// unary-signed literal) and chains of such slash divisions; variables,
/// function calls, parentheses, and other operations force real division.
function is_slash_operand(expr: root.ast.Expr) -> bool {
    match (expr) {
        root.ast.Expr_Number {} => true,
        // dart-sass also keeps the slash spelling when an operand is a
        // `calc()` (and the math-function family parsed as calculations):
        // `calc(1)/2` -> `1/2`, `calc(2px)/calc(4px)` -> `2px/4px`. The calc
        // operand folds to a number at eval time, so the slash repr is its
        // serialized value.
        root.ast.Expr_Calc {} => true,
        let div: root.ast.Expr_Div => div.slash,
        root.ast.Expr_Unary { op: root.ast.UnOp.Neg, operand: let operand } => {
            is_slash_operand(operand)
        },
        _ => false,
    }
}

/// Whether `expr` is a bare quoted-string atom. dart-sass forms an implicit
/// space-separated list when a quoted string abuts an adjacent value atom with
/// no whitespace, so the space-list parser uses this to decide whether a
/// no-whitespace boundary continues the list (`"["'foo'"]"` -> a three-element
/// list) rather than ending it.
function expr_is_quoted_string(expr: root.ast.Expr) -> bool {
    expr is root.ast.Expr_QuotedString
}

/// Strip a `-foo-` vendor prefix (a `-`, ASCII letters, then `-`). `--x`,
/// `-moz_x` (underscore), and an unprefixed name are returned unchanged.
function unvendor(name: string) -> string {
    // PORT: iterates chars instead of bytes (every test is ASCII, and a
    // non-ASCII char is not ASCII-alphabetic either); offsets are char offsets.
    let bytes = name.chars();
    if (bytes.at(0) != "-" || bytes.at(1) == "-") {
        return name;
    }
    let i = 1;
    while (i < bytes.length()) {
        let c = bytes[i];
        if (c == "-") {
            return name.slice(i + 1, name.length());
        }
        if (!c.is_ascii_alphabetic()) {
            return name;
        }
        i += 1;
    }
    name
}

/// Whether `name` is reserved and may not be a user `@function` name (dart-sass
/// "Invalid function name."). The SassScript operators and the raw-content CSS
/// functions `url`/`expression` match exactly (so `-a-and`, `AND`, `-a-url` are
/// allowed); `element` matches after stripping a vendor prefix; `type` matches
/// case-insensitively.
function is_reserved_function_name(name: string) -> bool {
    (
        match (name) {
            "and" | "or" | "not" | "url" | "expression" => true,
            _ => false,
        }
    )
        || unvendor(name) == "element"
        || root.std.eq_ignore_ascii_case(name, "type")
}

/// Whether a property-name template begins, *literally*, with `--` (a custom
/// property). A name whose first piece is `#{…}` interpolation is not literal,
/// so `#{--b}` namespaces normally while a written `--b` is a custom property.
function property_is_literal_custom(property: root.ast.TplPiece[]) -> bool {
    match (property.at(0)) {
        let s: root.ast.TplPiece_Lit => root.std.trim_start(s._0).starts_with("--"),
        _ => false,
    }
}

/// Whether the span between a `property:` colon and the following `{` is empty
/// of any value — only whitespace and `/* */` / `//` comments. Such a span
/// makes `property: { … }` a bare nested property set (no leading value).
function value_is_only_comments(span: string[]) -> bool {
    let i = 0;
    while (i < span.length()) {
        let c = span[i];
        if (c.is_whitespace()) {
            i += 1;
        } else if (c == "/" && span.at(i + 1) == "*") {
            i += 2;
            while (i + 1 < span.length() && !(span[i] == "*" && span[i + 1] == "/")) {
                i += 1;
            }
            i += 2;
        } else if (c == "/" && span.at(i + 1) == "/") {
            while (i < span.length() && span[i] != "\n") {
                i += 1;
            }
        } else {
            return false;
        }
    }
    true
}
