// Ported from sasso `src/parser/value.rs` (namespace `root.parser.value`).
//
// The SCSS value / expression parser: a Pratt-style recursive-descent over
// SassScript expressions (comma/space lists, the operator-precedence ladder,
// atoms, calls, numbers, colors, strings, `if()`). Byte-sensitive — feeds the
// value serialization path. Extracted verbatim from [`super`].

interface ParserValue {
    // ---- value expressions -------------------------------------------
    function parse_value(self) -> root.ast.Expr throws unknown;

    function at_value_terminator(self) -> bool throws unknown;

    /// Whether the scanner is positioned at the start of a value atom (the
    /// dispatch set of [`primary`]/[`unary`]). Used to decide whether a quoted
    /// string adjacency continues a space-list: only when a real atom follows,
    /// not a separator/operator such as `:` (a map key-value colon) or `=`.
    function at_value_atom_start(self) -> bool throws unknown;

    /// Whether the cursor sits on `!` followed (after optional whitespace) by
    /// the identifier `important` (case-insensitively) — dart's
    /// `_importantExpression` lookahead, so a `!default`/`!global` flag never
    /// reads as a value term.
    function looking_at_important(self) -> bool throws unknown;

    function comma_list(self) -> root.ast.Expr throws unknown;

    function space_list(self) -> root.ast.Expr throws unknown;

    // Operator precedence, lowest to highest: `or`, `and`, `not`, equality
    // (== !=), relational (< > <= >=), then additive (below). The logical
    // keywords are bare identifiers recognized only in operator position.
    function or_expr(self) -> root.ast.Expr throws unknown;

    function and_expr(self) -> root.ast.Expr throws unknown;

    function equality(self) -> root.ast.Expr throws unknown;

    function relational(self) -> root.ast.Expr throws unknown;

    /// Consume the bare keyword `kw` (`and`/`or`/`not`) if it appears next
    /// in operator position (after optional whitespace), matched as a whole
    /// identifier. Restores the cursor and returns false otherwise.
    function try_keyword(self, kw: string) -> bool throws unknown;

    function additive(self) -> root.ast.Expr throws unknown;

    /// Whether the `%` at the cursor is followed (after whitespace) by
    /// something that can start an operand — otherwise it's a lone `%` token.
    function percent_has_rhs(self) -> bool throws unknown;

    function multiplicative(self) -> root.ast.Expr throws unknown;

    function unary(self) -> root.ast.Expr throws unknown;

    function primary(self) -> root.ast.Expr throws unknown;

    /// Parse a CSS unicode-range token (`U+1A2B`, `U+4??`, `U+0-7F`, …). The
    /// leading `u`/`U` and `+` are not yet consumed; the caller guarantees the
    /// next two characters are `[uU]` and `+`. The original case is preserved
    /// verbatim and the token is lowered to an unquoted [`Expr::Ident`].
    ///
    /// Grammar (mirrors dart-sass `_unicodeRange`):
    ///   - 1–6 hex digits, optionally followed by `?` wildcards (total ≤ 6);
    ///   - if no `?` was seen, an optional `-` then 1–6 hex end digits;
    ///   - the token must end at a non-identifier boundary.
    function parse_unicode_range(self) -> root.ast.Expr throws unknown;

    /// Continue a comma list whose first element (`first`) has already been
    /// parsed at the space-list level, stopping before the closing `)`. Used
    /// when the leading element of a parenthesised group turned out not to be
    /// a map key. With no following commas this is just `first`.
    /// Like [`finish_paren_list`], but the list ends at `]`.
    function finish_bracket_list(self, first: root.ast.Expr) -> root.ast.Expr throws unknown;

    function finish_paren_list(self, first: root.ast.Expr) -> root.ast.Expr throws unknown;

    /// Parse the remaining entries of a map literal after the first key was
    /// parsed and the `:` separator confirmed (but not yet consumed). Each
    /// entry is `key: value` at the space-list level, comma-separated, with an
    /// optional trailing comma before `)`.
    function parse_map_after_first_key(
        self,
        first_key: root.ast.Expr,
    ) -> root.ast.Expr throws unknown;

    /// Parse a bracketed list literal `[ ... ]`. An empty `[]` is a bracketed
    /// empty space list; otherwise the interior is parsed as an ordinary value
    /// (which may itself be a comma/space list) and re-marked as bracketed.
    function parse_bracketed_list(self) -> root.ast.Expr throws unknown;

    /// The interned `Rc<str>` for a numeric literal's unit (`""` included).
    function unit_name(self, unit: string) -> string throws unknown;

    function parse_number(self) -> root.ast.Expr throws unknown;

    function parse_hex(self) -> root.ast.Expr throws unknown;

    /// dart-sass `_hexColorContents`: the character after `#` was a digit, so
    /// this is a hex color or an error. Read 3/4/6/8 hex digits in committed
    /// stages (each `read_hex_digit` is mandatory, mirroring dart's `_hexDigit`)
    /// and leave any trailing token for the caller (`#000g` -> `#000` color +
    /// `g`; `#0000g` -> 4-digit color + `g`).
    function parse_hex_color_contents(self) -> root.ast.Expr throws unknown;

    /// Read one required hex digit into `out`, or raise dart's
    /// "Expected hex digit." at the offending position.
    function read_hex_digit(self, out: root.std.StrBuf) -> void throws unknown;

    function parse_quoted_string(self) -> root.ast.TplPiece[] throws unknown;

    function parse_ident_or_call(self) -> root.ast.Expr throws unknown;

    /// Try to parse a `namespace.member` reference after the namespace
    /// identifier `ns` has been consumed and the next character is `.`.
    /// Returns `Some(Expr)` for `ns.fn(...)` or `ns.$var`, or `None` (without
    /// consuming the `.`) when the dot does not begin a namespaced member.
    function try_parse_namespaced(
        self,
        ns: string,
        name_pos: root.scanner.Pos,
        name_mark: root.scanner.Mark,
    ) -> root.ast.Expr? throws unknown;

    function parse_ident_template(self) -> root.ast.TplPiece[] throws unknown;

    /// As [`parse_ident_template`], with `emitted` pre-seeded — the
    /// continuation of `#{foo}\-` is MID-identifier, so its escapes use the
    /// name-char rule, not the name-START rule.
    function parse_ident_template_from(
        self,
        start_emitted: int,
    ) -> root.ast.TplPiece[] throws unknown;

    function parse_call(
        self,
        name: string,
        name_pos: root.scanner.Pos,
        name_mark: root.scanner.Mark,
    ) -> root.ast.Expr throws unknown;

    /// Capture the argument list of a special CSS function verbatim after the
    /// opening `(` has been consumed. `canonical` is the lower-cased function
    /// name to emit. The contents are preserved literally except that:
    ///   - `#{...}` interpolation is resolved;
    ///   - runs of whitespace collapse to a single space;
    ///   - silent `//` comments are dropped (the whitespace around them stays);
    ///   - loud `/* */` comments, quoted strings, and all other characters
    ///     (`%`, `@`, `=`, punctuation, …) are emitted verbatim.
    ///
    /// Nested parentheses are balanced.
    function parse_special_function(self, canonical: string) -> root.ast.Expr throws unknown;

    /// Parse an IE `progid:` special function whose `[-vendor-]progid` prefix
    /// (passed as `name`, with the `:` not yet consumed) has been recognised.
    /// The prefix is lower-cased on emit; a `.`-separated chain of ASCII-letter
    /// name segments follows the `:` (kept verbatim, case preserved), then an
    /// opening `(` is required and the argument list is captured verbatim
    /// (resolving only `#{...}` interpolation). Mirrors dart-sass's `progid`
    /// branch of `_trySpecialFunction`.
    function parse_progid(self, name: string) -> root.ast.Expr throws unknown;

    /// Continue capturing a verbatim special-function argument list, given the
    /// already-accumulated template `pieces`/`lit` (which must end with the
    /// opening `(` that has just been consumed). The closing `)` is consumed.
    /// Used by both the named special functions (`calc()`, `element()`, …) and
    /// the IE `progid:` form, which share dart-sass's interpolated-declaration
    /// value grammar.
    function capture_verbatim_args(
        self,
        pieces: root.ast.TplPiece[],
        lit: root.std.StrBuf,
    ) -> root.ast.Expr throws unknown;

    /// Try to read the contents of a `url(` as a plain unquoted URL (the `(`
    /// is already consumed). Returns `Some(pieces)` emitting a canonical
    /// `url(<contents>)` (vendor prefix dropped, name lower-cased) when the
    /// contents are a plain URL — arbitrary url-safe characters plus `#{...}`
    /// interpolation, balanced parentheses, and quoted strings. Returns `None`
    /// (without committing the cursor — the caller resets) when a top-level
    /// `$variable` appears, signalling that the call must instead be parsed as
    /// an ordinary function so its arguments evaluate.
    function try_plain_url_contents(self) -> root.ast.TplPiece[]? throws unknown;

    /// Attempt to parse the modern `if()` grammar after the opening `(` was
    /// consumed. Returns `Ok(Some(_))` if the input matches the modern
    /// clause syntax (consuming through the closing `)`), `Ok(None)` if it
    /// is clearly the legacy comma-arg form, or `Err` on a genuine modern
    /// syntax error (which surfaces to the caller as a hard error after the
    /// trial succeeds in committing to modern).
    function try_parse_modern_if(self) -> root.ast.IfClause[]? throws unknown;

    /// Parse one `if()` clause: `<condition>: <value>` or `else: <value>`.
    /// When `probe` is true a failure to recognise the leading condition
    /// returns `Ok(None)` (signalling a fall-back to legacy) rather than an
    /// error.
    function parse_if_clause(self, probe: bool) -> root.ast.IfClause? throws unknown;

    /// Parse a full `if()` condition. dart-sass's grammar:
    ///   `not <operand>`                        (a single negated operand)
    ///   `<operand> (and <operand>)+`           (an `and` chain)
    ///   `<operand> (or <operand>)+`            (an `or` chain)
    ///   `<operand>`                            (a lone operand)
    /// Mixing `and` and `or` at the same level is an error; `not` only
    /// applies to a single non-multi-token operand and cannot be chained.
    /// Keywords (`not`/`and`/`or`) are matched case-insensitively.
    function parse_if_cond(self, probe: bool) -> root.ast.IfCond? throws unknown;

    /// Unwrap an operand that may have failed to parse.
    function expect_operand(self, operand: root.ast.IfCond?) -> root.ast.IfCond throws unknown;

    /// Parse one condition operand: a parenthesised condition, `sass(<expr>)`,
    /// or a raw substitution sequence. When `single` is true (the operand of
    /// `not`), only a single raw token is consumed (a paren or one function
    /// call), not a multi-token sequence. Returns `Ok(None)` (when probing)
    /// if the position cannot begin an operand.
    function parse_if_operand(self, probe: bool, single: bool) -> root.ast.IfCond? throws unknown;

    /// Parse a sequence of raw substitution tokens (`css(...)`,
    /// `<ident>(...)`, `#{...}`) joined by spaces into a single non-evaluable
    /// condition. When `single` is true, at most one token is read. A
    /// `sass()` token inside the sequence is the "arbitrary substitution"
    /// error. Returns `Ok(None)` (when probing) if the input cannot begin a
    /// raw token.
    function parse_if_raw_sequence(
        self,
        probe: bool,
        single: bool,
    ) -> root.ast.IfCond? throws unknown;

    /// Whether the next token starts a raw substitution token: an
    /// interpolation or an identifier (which must be followed by `(`).
    function peek_starts_raw_token(self) -> bool throws unknown;

    /// Read one raw substitution token (`<ident>(...)` or `#{...}`),
    /// appending its serialized pieces. A bare interpolation token is valid;
    /// a bare identifier (not followed by `(`) is not. Returns false if the
    /// position does not start such a token.
    function read_if_raw_token(self, pieces: root.ast.TplPiece[]) -> bool throws unknown;

    /// Read a balanced `( ... )` group verbatim (resolving interpolation),
    /// appending to `pieces`. Assumes the next char is `(`.
    function read_if_raw_parens(self, pieces: root.ast.TplPiece[]) -> void throws unknown;

    /// Read an identifier that may contain leading/embedded `#{...}`
    /// interpolation (e.g. `#{css}`), as a template.
    function read_ident_template(self) -> root.ast.TplPiece[] throws unknown;

    /// Peek whether the next word equals `kw` case-insensitively (followed
    /// by a non-ident char). `if()` keywords are case-insensitive.
    function peek_word_is_ci(self, kw: string) -> bool throws unknown;

    /// At the current position, peek whether a conjunction follows.
    /// `Some(true)` for `and`, `Some(false)` for `or`, `None` otherwise.
    function peek_if_conjunction(self) -> bool? throws unknown;

    /// Consume the keyword `kw` (case-insensitively) if it is the next word
    /// (followed by a non-ident char). Does not skip leading whitespace.
    function eat_if_keyword(self, kw: string) -> bool throws unknown;

    /// After consuming `not`/`and`/`or`, dart-sass requires whitespace
    /// before a following `(` (otherwise `and(` etc. is a function call,
    /// which is an error in condition position).
    function require_paren_whitespace_after(self, kw: string) -> void throws unknown;

    /// Peek whether the next word is `kw` (case-insensitive) immediately
    /// followed by `(`.
    function peek_keyword_paren_ci(self, kw: string) -> bool throws unknown;

    /// Parse a call's argument list, assuming the opening `(` was already
    /// consumed, through the closing `)`. Args are positional or
    /// `$name: value`. Shared by function calls and `@include`.
    /// A function-argument value: a space-list optionally followed by one or
    /// more single-`=` Microsoft-filter operators (`alpha(opacity=80)`). The
    /// `=` is the lowest-precedence value operator and is recognised only here,
    /// inside an argument list (a lone `=` is a syntax error elsewhere). A
    /// `==` is the equality operator and is handled at its own precedence, so
    /// only a `=` not followed by `=` is consumed.
    function arg_value(self) -> root.ast.Expr throws unknown;

    function parse_args_after_paren(self) -> root.ast.CallArg[] throws unknown;

    /// Parse a comma-separated argument list after a consumed `(`.
    ///
    /// When `allow_empty_second_arg` is set (dart-sass's `var()` special case),
    /// a `,` immediately followed by `)` right after the *first* argument adds
    /// an empty unquoted-string second argument (`var(--c,)` -> `var(--c, )`)
    /// instead of being treated as a normal ignorable trailing comma.
    function parse_args_after_paren_opt_empty_second(
        self,
        allow_empty_second_arg: bool,
    ) -> root.ast.CallArg[] throws unknown;
}

implements ParserValue for root.parser.Parser {
    // ---- value expressions -------------------------------------------
    function parse_value(self) -> root.ast.Expr {
        // dart-sass skips whitespace AND comments before an expression
        // (`singleInterpolation` runs `whitespace()` first), so `#{ a }` and
        // `"#{ a /* c */ }"` parse — a comment ends at the first `*/` and is
        // never itself scanned for interpolation. Established callers skip
        // before calling, making this a no-op for them.
        self.skip_ws_inline();
        self.comma_list()
    }

    function at_value_terminator(self) -> bool {
        match (self.sc.peek()) {
            null | "," | ";" | "}" | ")" | "]" | "{" => true,
            // `!important` is a value term (dart `_importantExpression`); any
            // other `!` (a `!default`/`!global` flag) ends the value.
            "!" => !self.looking_at_important(),
            _ => false,
        }
    }

    /// Whether the scanner is positioned at the start of a value atom (the
    /// dispatch set of [`primary`]/[`unary`]). Used to decide whether a quoted
    /// string adjacency continues a space-list: only when a real atom follows,
    /// not a separator/operator such as `:` (a map key-value colon) or `=`.
    function at_value_atom_start(self) -> bool {
        match (self.sc.peek()) {
            "." => root.std.is_ascii_digit(self.sc.peek_at(1)),
            "!" => self.looking_at_important(),
            let c: string => {
                root.std.is_ascii_digit(c)
                    || (match (c) {
                        "$" | "#" | "\"" | "'" | "(" | "[" | "&" | "+" | "-" | "\\" => true,
                        _ => false,
                    })
                    || root.parser.is_ident_char(c)
            }
            null => false,
        }
    }

    /// Whether the cursor sits on `!` followed (after optional whitespace) by
    /// the identifier `important` (case-insensitively) — dart's
    /// `_importantExpression` lookahead, so a `!default`/`!global` flag never
    /// reads as a value term.
    function looking_at_important(self) -> bool {
        if (self.sc.peek() != "!") {
            return false;
        }
        let i = 1;
        while (match (self.sc.peek_at(i)) {
            " " | "\t" | "\n" | "\r" | "\f" => true,
            _ => false,
        }) {
            i += 1;
        }
        for (let ch in "important".chars()) {
            match (self.sc.peek_at(i)) {
                let c: string if root.std.eq_ignore_ascii_case(c, ch) => {
                    i += 1;
                }
                _ => {
                    return false;
                }
            }
        }
        // The identifier must end here (`!importantx` is not the keyword).
        !(match (self.sc.peek_at(i)) {
            let c: string if root.parser.is_ident_char(c) => true,
            _ => false,
        })
    }

    function comma_list(self) -> root.ast.Expr {
        let first = self.space_list();
        let rest: root.ast.Expr[] = [];
        while (true) {
            let mark = self.sc.mark();
            self.skip_ws_inline();
            if (self.sc.peek() == ",") {
                self.sc.bump();
                self.skip_ws_inline();
                if (self.at_value_terminator()) {
                    break;
                }
                rest.push(self.space_list());
            } else {
                self.sc.reset(mark);
                break;
            }
        }
        if (rest.length() == 0) {
            first
        } else {
            let items: root.ast.Expr[] = [];
            items.push(first);
            root.std.extend(items, rest);
            root.ast.Expr_List {
                items: items,
                sep: root.value.ListSep.Comma,
                bracketed: false,
            }
        }
    }

    function space_list(self) -> root.ast.Expr {
        let first = self.or_expr();
        let prev_was_string = root.parser.expr_is_quoted_string(first);
        let rest: root.ast.Expr[] = [];
        while (true) {
            // A `?`-wildcard unicode-range token immediately followed by an
            // identifier inserts an implicit space separator (`U+A?BCDE` ->
            // `U+A? BCDE`), so continue without consuming whitespace.
            // PORT: `std::mem::take(&mut self.pending_unicode_split)` → read, then clear.
            let pending_split = self.pending_unicode_split;
            self.pending_unicode_split = false;
            if (pending_split) {
                let e = self.or_expr();
                prev_was_string = root.parser.expr_is_quoted_string(e);
                rest.push(e);
                continue;
            }
            let mark = self.sc.mark();
            let had_ws = self.skip_ws_inline();
            // Two atoms that touch with no whitespace normally end the list, but
            // dart-sass forms an implicit space-separated list when a quoted
            // string abuts an adjacent atom: `"["'foo'"]"` -> `"[" "foo" "]"`,
            // `gamme "'"delta` -> `gamme "'" delta`. This applies when the
            // previous atom was a quoted string, or the next atom begins one
            // (any binary operator was already consumed by `or_expr`, so a
            // remaining non-terminator atom here is a genuine list element).
            let adjacent_string = !had_ws
                && self.at_value_atom_start()
                && (prev_was_string || self.sc.peek() == "\"" || self.sc.peek() == "'");
            // dart-sass's space list doesn't require whitespace between atoms
            // at all (`_spaceListOrValue` loops while `lookingAtExpression`):
            // `(x)y` is `x y`, `5px(3)` is `5px 3`. A touching atom start
            // begins a new term. (Operators were already consumed by
            // `or_expr`, and an ident followed by `(` was consumed as a
            // call, so what reaches here is a genuine new atom.)
            let adjacent_atom = !had_ws && self.at_value_atom_start();
            // An interpolation directly after a complete atom begins a new
            // term with an implicit separator (`1#{0}` is the list `1 0`), as
            // does a `-#{…}` interpolated identifier (`10-#{10}` → `10 -10`);
            // an interpolation that continues an identifier was already
            // consumed by the identifier template, so a `#{` seen here is a
            // fresh atom.
            let adjacent_interp = !had_ws
                && ((self.sc.peek() == "#" && self.sc.peek_at(1) == "{")
                    || (self.sc.peek() == "-"
                        && self.sc.peek_at(1) == "#"
                        && self.sc.peek_at(2) == "{"));
            // A lone `=` (not `==`) ends the space-list so an enclosing
            // argument list can apply the single-`=` Microsoft-filter operator
            // (`foo(a = b)`); `==` stays the equality operator, parsed above.
            // A `:` likewise ends it — a map key may be separated from its
            // colon by whitespace (`(b \n : c)`), which the paren handler
            // then resolves as a map.
            // A `...` splat ends the list too — the value may be separated
            // from its `...` by whitespace (`a($d ...)`, `a($d\n  ...)`).
            if ((!had_ws && !adjacent_string && !adjacent_interp && !adjacent_atom)
                || self.at_value_terminator()
                || (self.sc.peek() == "=" && self.sc.peek_at(1) != "=")
                || (self.sc.peek() == ":" && self.sc.peek_at(1) != ":")
                || (self.sc.peek() == "."
                    && self.sc.peek_at(1) == "."
                    && self.sc.peek_at(2) == "."))
            {
                self.sc.reset(mark);
                break;
            }
            let e = self.or_expr();
            prev_was_string = root.parser.expr_is_quoted_string(e);
            rest.push(e);
        }
        if (rest.length() == 0) {
            first
        } else {
            let items: root.ast.Expr[] = [];
            items.push(first);
            root.std.extend(items, rest);
            root.ast.Expr_List {
                items: items,
                sep: root.value.ListSep.Space,
                bracketed: false,
            }
        }
    }

    // Operator precedence, lowest to highest: `or`, `and`, `not`, equality
    // (== !=), relational (< > <= >=), then additive (below). The logical
    // keywords are bare identifiers recognized only in operator position.
    function or_expr(self) -> root.ast.Expr {
        let lhs = self.and_expr();
        // In plain CSS `or`/`and`/`not` are ordinary identifiers, not operators.
        while (!self.plain_css && self.try_keyword("or")) {
            self.skip_ws_inline();
            let pos = self.sc.position();
            let rhs = self.and_expr();
            lhs = root.ast.Expr_Binary {
                op: root.ast.BinOp.Or,
                lhs: lhs,
                rhs: rhs,
                pos: pos,
            };
        }
        lhs
    }

    function and_expr(self) -> root.ast.Expr {
        let lhs = self.equality();
        while (!self.plain_css && self.try_keyword("and")) {
            self.skip_ws_inline();
            let pos = self.sc.position();
            let rhs = self.equality();
            lhs = root.ast.Expr_Binary {
                op: root.ast.BinOp.And,
                lhs: lhs,
                rhs: rhs,
                pos: pos,
            };
        }
        lhs
    }

    function equality(self) -> root.ast.Expr {
        let lhs = self.relational();
        while (true) {
            let mark = self.sc.mark();
            self.skip_ws_inline();
            let op: root.ast.BinOp = if (self.sc.peek() == "=" && self.sc.peek_at(1) == "=") {
                self.sc.bump();
                self.sc.bump();
                root.ast.BinOp.Eq
            } else if (self.sc.peek() == "!" && self.sc.peek_at(1) == "=") {
                self.sc.bump();
                self.sc.bump();
                root.ast.BinOp.Neq
            } else {
                self.sc.reset(mark);
                break;
            };
            if (self.plain_css) {
                throw root.error.Error.at(
                    "Operators aren't allowed in plain CSS.",
                    self.sc.position(),
                );
            }
            let pos = self.sc.position();
            self.skip_ws_inline();
            let rhs = self.relational();
            lhs = root.ast.Expr_Binary {
                op: op,
                lhs: lhs,
                rhs: rhs,
                pos: pos,
            };
        }
        lhs
    }

    function relational(self) -> root.ast.Expr {
        let lhs = self.additive();
        while (true) {
            let mark = self.sc.mark();
            self.skip_ws_inline();
            // PORT: `match (peek(), peek_at(1))` over a tuple → an if/else chain.
            let p0 = self.sc.peek();
            let p1 = self.sc.peek_at(1);
            let op: root.ast.BinOp = if (p0 == "<" && p1 == "=") {
                self.sc.bump();
                self.sc.bump();
                root.ast.BinOp.Le
            } else if (p0 == ">" && p1 == "=") {
                self.sc.bump();
                self.sc.bump();
                root.ast.BinOp.Ge
            } else if (p0 == "<") {
                self.sc.bump();
                root.ast.BinOp.Lt
            } else if (p0 == ">") {
                self.sc.bump();
                root.ast.BinOp.Gt
            } else {
                self.sc.reset(mark);
                break;
            };
            if (self.plain_css) {
                throw root.error.Error.at(
                    "Operators aren't allowed in plain CSS.",
                    self.sc.position(),
                );
            }
            let pos = self.sc.position();
            self.skip_ws_inline();
            let rhs = self.additive();
            lhs = root.ast.Expr_Binary {
                op: op,
                lhs: lhs,
                rhs: rhs,
                pos: pos,
            };
        }
        lhs
    }

    /// Consume the bare keyword `kw` (`and`/`or`/`not`) if it appears next
    /// in operator position (after optional whitespace), matched as a whole
    /// identifier. Restores the cursor and returns false otherwise.
    function try_keyword(self, kw: string) -> bool {
        let mark = self.sc.mark();
        self.skip_ws_inline();
        if (!root.std.is_ascii_alphabetic(self.sc.peek())) {
            self.sc.reset(mark);
            return false;
        }
        let word = "";
        while (match (self.sc.peek()) {
            let c: string if root.parser.is_ident_char(c) => true,
            _ => false,
        }) {
            if let c: string = self.sc.bump() {
                word = word + c;
            }
        }
        if (word == kw) {
            true
        } else {
            self.sc.reset(mark);
            false
        }
    }

    function additive(self) -> root.ast.Expr {
        let lhs = self.multiplicative();
        while (true) {
            // A `?`-wildcard unicode-range token is terminal: a directly
            // following `-name` begins a fresh space-list element (handled by
            // `space_list`), not a subtraction, so don't consume the operator.
            if (self.pending_unicode_split) {
                break;
            }
            let mark = self.sc.mark();
            let had_ws = self.skip_ws_inline();
            let op: root.ast.BinOp? = match (self.sc.peek()) {
                "+" => root.ast.BinOp.Add,
                "-" => root.ast.BinOp.Sub,
                _ => null,
            };
            // A `-` directly followed by `#{` begins an interpolated
            // identifier (`10-#{10}` is the list `10 -10`), never a
            // subtraction — regardless of surrounding whitespace. After a
            // quoted string a `-` that begins an identifier (`"q"-l`) likewise
            // starts a new term (dart-sass can't continue a string token).
            if (op == root.ast.BinOp.Sub) {
                let interp_next = self.sc.peek_at(1) == "#" && self.sc.peek_at(2) == "{";
                let ident_next = match (self.sc.peek_at(1)) {
                    let c: string if c.is_alphabetic() || c == "_" || c == "-" || c == "\\" => true,
                    _ => false,
                };
                // `--` always begins an identifier (a CSS custom-ident like
                // `--em-2--em`), never a subtraction: `1--em` is the space
                // list `1 --em`.
                let custom_ident_next = self.sc.peek_at(1) == "-";
                if (interp_next || custom_ident_next || (root.parser.expr_is_quoted_string(lhs) && ident_next)) {
                    self.sc.reset(mark);
                    break;
                }
            }
            if (op != null) {
                // Whitespace OR a comment (`/* */`, `//`) immediately
                // after the operator counts as separation, matching
                // dart-sass's `1 /**/+/**/ 2` handling.
                let ws_after = root.std.is_whitespace(self.sc.peek_at(1))
                    || (self.sc.peek_at(1) == "/"
                        && (self.sc.peek_at(2) == "*" || self.sc.peek_at(2) == "/"));
                // dart-sass: `+`/`-` in operator position is binary unless
                // it has whitespace before but NOT after AND begins a new
                // space-list term. A `+` here is ALWAYS binary (`c +d` is
                // `c + d`, the strict-unary deprecation case); a `-` starts
                // a new term only when it begins a number (`1 -2`) or an
                // identifier (`c -d`, `-#{…}`) — otherwise (`c -$d`,
                // `10 -(2)`, `c -"x"`) it is binary too. Inside a
                // calculation it must be surrounded on both sides.
                let binary = if (self.calc_depth > 0) {
                    had_ws && ws_after
                } else if (!had_ws || ws_after) {
                    true
                } else {
                    match (op) {
                        root.ast.BinOp.Add => true,
                        _ => {
                            let n1 = self.sc.peek_at(1);
                            let starts_term = (match (n1) {
                                let c: string if root.std.is_ascii_digit(c) || c == "." || c == "-" || c == "_" || c.is_alphabetic() => true,
                                _ => false,
                            })
                                || (n1 == "#" && self.sc.peek_at(2) == "{")
                                || n1 == "\\";
                            !starts_term
                        }
                    }
                };
                if (binary) {
                    // Outside a calculation, `+`/`-` is a Sass operator,
                    // which plain CSS forbids (inside calc it is real math).
                    if (self.plain_css && self.calc_depth == 0) {
                        throw root.error.Error.at(
                            "Operators aren't allowed in plain CSS.",
                            self.sc.position(),
                        );
                    }
                    let pos = self.sc.position();
                    self.sc.bump();
                    self.skip_ws_inline();
                    let rhs = self.multiplicative();
                    lhs = root.ast.Expr_Binary {
                        op: op,
                        lhs: lhs,
                        rhs: rhs,
                        pos: pos,
                    };
                } else if (self.calc_depth > 0) {
                    // Inside calc(), `+`/`-` must be whitespace-surrounded.
                    throw root.error.Error.at(
                        "\"+\" and \"-\" must be surrounded by whitespace in calculations.",
                        self.sc.position(),
                    );
                } else {
                    self.sc.reset(mark);
                    break;
                }
            } else {
                self.sc.reset(mark);
                break;
            }
        }
        lhs
    }

    /// Whether the `%` at the cursor is followed (after whitespace) by
    /// something that can start an operand — otherwise it's a lone `%` token.
    function percent_has_rhs(self) -> bool {
        let i = 1;
        while (root.std.is_whitespace(self.sc.peek_at(i))) {
            i += 1;
        }
        !(match (self.sc.peek_at(i)) {
            null | "}" | ")" | "]" | ";" | "," | "!" => true,
            _ => false,
        })
    }

    function multiplicative(self) -> root.ast.Expr {
        let lhs = self.unary();
        while (true) {
            let mark = self.sc.mark();
            self.skip_ws_inline();
            let op: root.ast.BinOp? = match (self.sc.peek()) {
                "*" => root.ast.BinOp.Mul,
                // `%` is modulo only when an operand follows; a trailing `%`
                // (`a {b: c %}`, `f(g %)`) is a lone unquoted-string token
                // handled by the space-list/primary layer (dart-sass).
                "%" if self.percent_has_rhs() => root.ast.BinOp.Mod,
                _ => null,
            };
            // `/` is the deprecated slash operator (handled specially), but
            // never treat `*/` or a `/` opening a comment as an operator —
            // except in plain CSS, where `//` is two slash separators
            // (`1///bar` keeps all three).
            if (op == null
                && self.sc.peek() == "/"
                && (self.sc.peek_at(1) != "/" || self.plain_css)
                && self.sc.peek_at(1) != "*")
            {
                let pos = self.sc.position();
                self.sc.bump();
                self.skip_ws_inline();
                let rhs = self.unary();
                // Inside calc() `/` is always real division; elsewhere it
                // keeps the slash spelling between number literals.
                let slash = self.calc_depth == 0 && root.parser.is_slash_operand(lhs) && root.parser.is_slash_operand(rhs);
                lhs = root.ast.Expr_Div {
                    lhs: lhs,
                    rhs: rhs,
                    slash: slash,
                    pos: pos,
                };
                continue;
            }
            if (op != null) {
                // `*`/`%` are Sass operators (real math inside calc only).
                if (self.plain_css && self.calc_depth == 0) {
                    throw root.error.Error.at(
                        "Operators aren't allowed in plain CSS.",
                        self.sc.position(),
                    );
                }
                let pos = self.sc.position();
                self.sc.bump();
                self.skip_ws_inline();
                let rhs = self.unary();
                lhs = root.ast.Expr_Binary {
                    op: op,
                    lhs: lhs,
                    rhs: rhs,
                    pos: pos,
                };
            } else {
                self.sc.reset(mark);
                break;
            }
        }
        lhs
    }

    function unary(self) -> root.ast.Expr {
        // `not` is a unary operator over a single expression (dart-sass
        // `identifierLike` → `UnaryOperation(not, singleExpression())`), so it
        // binds tighter than every binary operator: `not 1 + 2` is
        // `(not 1) + 2` and `not $a == $b` is `(not $a) == $b`.
        if (!self.plain_css && self.try_keyword("not")) {
            self.skip_ws_inline();
            let operand = self.unary();
            return root.ast.Expr_Unary {
                op: root.ast.UnOp.Not,
                operand: operand,
            };
        }
        // Inside a calculation a unary `+`/`-` is only legal as the sign of a
        // numeric literal written tight against the digit (`-1px`, `+3`,
        // `2 * +3`). Any other unary form — separated by whitespace (`- 1px`),
        // or applied to a parenthesis/variable (`-(1px)`, `-$x`) — is rejected
        // by dart-sass ("This expression can't be used in a calculation."). A
        // tight `-`/`+` before an identifier (`-var(--c)`, `-webkit-x`) is part
        // of the identifier and is handled by `primary`, not here.
        let in_calc = self.calc_depth > 0;
        match (self.sc.peek()) {
            "-" => {
                // `-` directly before a number/paren/variable is numeric
                // negation (`-5`, `-(1)`, `-$x`); when separated by whitespace
                // it is the unary-minus operator over any value (`- red` ->
                // `-red`). A `-` immediately followed by an identifier char is
                // instead part of an identifier (`-webkit-foo`, `-red`) and
                // falls through to `primary`.
                if (match (self.sc.peek_at(1)) {
                    let c: string if root.std.is_ascii_digit(c) || c == "." || c == "$" || c == "(" => true,
                    _ => false,
                }) {
                    if (in_calc && (self.sc.peek_at(1) == "$" || self.sc.peek_at(1) == "(")) {
                        throw root.error.Error.at(
                            "This expression can't be used in a calculation.",
                            self.sc.position(),
                        );
                    }
                    self.sc.bump();
                    let operand = self.unary();
                    return root.ast.Expr_Unary {
                        op: root.ast.UnOp.Neg,
                        operand: operand,
                    };
                }
                if (root.std.is_whitespace(self.sc.peek_at(1))) {
                    if (in_calc) {
                        throw root.error.Error.at(
                            "This expression can't be used in a calculation.",
                            self.sc.position(),
                        );
                    }
                    self.sc.bump();
                    self.skip_ws_inline();
                    let operand = self.unary();
                    return root.ast.Expr_Unary {
                        op: root.ast.UnOp.Neg,
                        operand: operand,
                    };
                }
            }
            "+" => {
                // `+` is never part of an identifier, so a leading `+` in value
                // position is always the unary-plus operator (numeric identity
                // for a number, otherwise an unquoted `+<value>` string).
                // Optional whitespace separates it from its operand. A `+` with
                // no following operand falls through to `primary` (which reports
                // the error).
                let next = self.sc.peek_at(1);
                if (in_calc) {
                    // Only a tight `+` against a numeric literal is a legal sign
                    // inside a calculation; everything else is rejected.
                    if (match (next) {
                        let c: string if root.std.is_ascii_digit(c) || c == "." => true,
                        _ => false,
                    }) {
                        self.sc.bump();
                        let operand = self.unary();
                        return root.ast.Expr_Unary {
                            op: root.ast.UnOp.Plus,
                            operand: operand,
                        };
                    }
                    throw root.error.Error.at(
                        "This expression can't be used in a calculation.",
                        self.sc.position(),
                    );
                }
                let starts_operand = match (next) {
                    let c: string if root.std.is_ascii_digit(c)
                        || c == "."
                        || c == "$"
                        || c == "("
                        || c == "\""
                        || c == "'"
                        || c == "#"
                        || c == "+"
                        || c == "-"
                        || root.parser.is_ident_char(c) => true,
                    _ => false,
                };
                if (starts_operand || root.std.is_whitespace(next)) {
                    self.sc.bump();
                    self.skip_ws_inline();
                    let operand = self.unary();
                    return root.ast.Expr_Unary {
                        op: root.ast.UnOp.Plus,
                        operand: operand,
                    };
                }
            }
            _ => {}
        }
        self.primary()
    }

    function primary(self) -> root.ast.Expr {
        match (self.sc.peek()) {
            let c: string if root.std.is_ascii_digit(c) => self.parse_number(),
            "." if root.std.is_ascii_digit(self.sc.peek_at(1)) => self.parse_number(),
            // `!important` (any case, whitespace after `!` allowed) is a value
            // term: the canonical unquoted string `!important` (dart
            // `_importantExpression`).
            "!" if self.looking_at_important() => {
                self.sc.bump();
                self.skip_ws_inline();
                let _ = self.read_ident_name();
                root.ast.Expr_Ident { _0: [root.ast.TplPiece_Lit { _0: "!important" }] }
            }
            "$" => {
                let pos = self.sc.position();
                if (self.plain_css) {
                    throw root.error.Error.at("Sass variables aren't allowed in plain CSS.", pos);
                }
                self.sc.bump();
                let name = self.read_variable_name();
                root.ast.Expr_Var { name: name, pos: pos }
            }
            "#" if self.sc.peek_at(1) == "{" => {
                let interp_mark = self.sc.mark();
                let interp_pos = self.sc.position();
                self.sc.bump();
                self.sc.bump();
                // Whitespace (including newlines) is permitted around the
                // interpolated expression: `#{ x }` / `#{\n  x\n}`.
                self.skip_ws_inline();
                let e = self.parse_interp_value();
                self.skip_ws_inline();
                if (!self.sc.eat("}")) {
                    throw root.error.Error.at("expected \"}\"", self.sc.position());
                }
                self.reject_plain_css_interp(interp_mark);
                // A directly-following identifier character (or another
                // interpolation) continues the same interpolated identifier:
                // `#{1}0` is the single token `10`, `#{1}px` is `1px` (a
                // string), matching dart-sass `identifierLike`.
                if ((match (self.sc.peek()) {
                    let c: string if root.parser.is_ident_char(c) => true,
                    _ => false,
                })
                    || (self.sc.peek() == "#" && self.sc.peek_at(1) == "{")
                    || self.sc.peek() == "\\")
                {
                    let pieces: root.ast.TplPiece[] = [root.ast.TplPiece_Interp { _0: e }];
                    root.std.extend(pieces, self.parse_ident_template_from(1));
                    // `(` directly after makes this a dynamic plain-CSS call
                    // (`#{1 + 1}foo(arg)` -> `2foo(arg)`).
                    if (self.sc.peek() == "(") {
                        self.sc.bump();
                        let args = self.parse_args_after_paren();
                        return root.ast.Expr_InterpFunc {
                            name: pieces,
                            args: args,
                            pos: interp_pos,
                        };
                    }
                    return root.ast.Expr_Ident { _0: pieces };
                }
                // A directly-following `(` makes the interpolation a dynamic
                // plain-CSS function name (`#{foo}(arg)` -> `foo(arg)`).
                if (self.sc.peek() == "(") {
                    self.sc.bump();
                    let args = self.parse_args_after_paren();
                    return root.ast.Expr_InterpFunc {
                        name: [root.ast.TplPiece_Interp { _0: e }],
                        args: args,
                        pos: interp_pos,
                    };
                }
                root.ast.Expr_Interp { _0: e }
            }
            "#" => self.parse_hex(),
            // A leading `/` begins a slash-separated value with an empty left
            // operand (`font: / 2` → `/2`, `(1, / 2)` → `1, /2`), matching
            // dart-sass — in plain CSS too (`1/ / /bar` is `1///bar`).
            "/" if self.calc_depth == 0 => {
                let pos = self.sc.position();
                self.sc.bump();
                self.skip_ws_inline();
                let rhs = self.multiplicative();
                root.ast.Expr_Div {
                    lhs: root.ast.Expr_Ident { _0: [root.ast.TplPiece_Lit { _0: "" }] },
                    rhs: rhs,
                    slash: true,
                    pos: pos,
                }
            }
            "\"" | "'" => {
                let pieces = self.parse_quoted_string();
                root.ast.Expr_QuotedString { _0: pieces }
            }
            "(" => {
                // A grouping paren is a Sass construct, but parens INSIDE a
                // calculation are legitimate CSS (`calc(2 * (1px + 1%))`).
                if (self.plain_css && self.calc_depth == 0) {
                    throw root.error.Error.at(
                        "Parentheses aren't allowed in plain CSS.",
                        self.sc.position(),
                    );
                }
                self.sc.bump();
                self.skip_ws_inline();
                if (self.sc.peek() == ")") {
                    self.sc.bump();
                    return root.ast.Expr_List {
                        items: [],
                        sep: root.value.ListSep.Undecided,
                        bracketed: false,
                    };
                }
                // Parse the first sub-expression at the space-list level. A
                // following `:` makes this a map literal `(k: v, …)`; anything
                // else is an ordinary parenthesised expression / list.
                let first = self.space_list();
                self.skip_ws_inline();
                if (self.sc.peek() == ":" && self.sc.peek_at(1) != ":") {
                    return self.parse_map_after_first_key(first);
                }
                let e = self.finish_paren_list(first);
                self.skip_ws_inline();
                if (!self.sc.eat(")")) {
                    throw root.error.Error.at("expected \")\"", self.sc.position());
                }
                root.ast.Expr_Paren { _0: e }
            }
            "[" => self.parse_bracketed_list(),
            "&" => {
                if (self.plain_css) {
                    throw root.error.Error.at(
                        "The parent selector isn't allowed in plain CSS.",
                        self.sc.position(),
                    );
                }
                self.sc.bump();
                root.ast.Expr_Parent {}
            }
            // CSS unicode-range token: `u`/`U` immediately followed by `+`
            // (no whitespace) commits to the unicode-range grammar, matching
            // dart-sass. `u + 1` (with whitespace) is ordinary concatenation
            // and falls through to the identifier branch below.
            "u" | "U" if self.sc.peek_at(1) == "+" => self.parse_unicode_range(),
            // Any non-ASCII code point starts an identifier (dart isNameStart).
            let c: string if root.std.is_ascii_alphabetic(c) || c == "-" || c == "_" || root.std.ord(c) >= 0x80 => {
                self.parse_ident_or_call()
            }
            // A value beginning with a CSS escape (`\41`, `\9`, …) is an
            // identifier; let `parse_ident_or_call` consume the escape run.
            "\\" => self.parse_ident_or_call(),
            // A lone `%` in value position (no left operand, so it is not the
            // modulo operator) is a standalone unquoted-string token, as in
            // dart-sass: `attr(c, %)` keeps the `%`, and `%foo` parses as the
            // two space-list elements `%` and `foo`. Only a single `%` is
            // consumed here.
            "%" => {
                self.sc.bump();
                root.ast.Expr_Ident { _0: [root.ast.TplPiece_Lit { _0: "%" }] }
            }
            // dart names what it WANTED here, whatever it found — a character
            // that cannot start one, or the end of the file.
            _ => {
                throw root.error.Error.at("Expected expression.", self.sc.position());
            }
        }
    }

    /// Parse a CSS unicode-range token (`U+1A2B`, `U+4??`, `U+0-7F`, …). The
    /// leading `u`/`U` and `+` are not yet consumed; the caller guarantees the
    /// next two characters are `[uU]` and `+`. The original case is preserved
    /// verbatim and the token is lowered to an unquoted [`Expr::Ident`].
    ///
    /// Grammar (mirrors dart-sass `_unicodeRange`):
    ///   - 1–6 hex digits, optionally followed by `?` wildcards (total ≤ 6);
    ///   - if no `?` was seen, an optional `-` then 1–6 hex end digits;
    ///   - the token must end at a non-identifier boundary.
    function parse_unicode_range(self) -> root.ast.Expr {
        let start = self.sc.position();
        let s = "";
        if let c: string = self.sc.bump() {
            s = s + c; // `u` / `U`
        }
        if let c: string = self.sc.bump() {
            s = s + c; // `+`
        }
        // First range: up to 6 hex digits, then `?` wildcards (total ≤ 6).
        let count = 0;
        while (count < 6 && root.std.is_ascii_hexdigit(self.sc.peek())) {
            if let c: string = self.sc.bump() {
                s = s + c;
            }
            count += 1;
        }
        let saw_question = false;
        while (count < 6 && self.sc.peek() == "?") {
            self.sc.bump();
            s = s + "?";
            saw_question = true;
            count += 1;
        }
        if (count == 0) {
            throw root.error.Error.at("Expected hex digit or \"?\".", self.sc.position());
        }
        // After a wildcard form, no `-end` range is allowed.
        if (!saw_question && self.sc.peek() == "-") {
            self.sc.bump();
            s = s + "-";
            let end_count = 0;
            while (end_count < 6 && root.std.is_ascii_hexdigit(self.sc.peek())) {
                if let c: string = self.sc.bump() {
                    s = s + c;
                }
                end_count += 1;
            }
            if (end_count == 0) {
                throw root.error.Error.at("Expected hex digit.", self.sc.position());
            }
        }
        // When the 6-digit cap is reached but more hex digits or `?`
        // wildcards immediately follow, dart-sass reports "Expected at most 6
        // digits." (spanning the whole token). Below the cap the token simply
        // ends and any following identifier becomes the next list element.
        if (count == 6 && (match (self.sc.peek()) {
            let c: string if root.std.is_ascii_hexdigit(c) || c == "?" => true,
            _ => false,
        })) {
            throw root.error.Error.at("Expected at most 6 digits.", start);
        }
        let token = root.ast.Expr_Ident { _0: [root.ast.TplPiece_Lit { _0: s }] };
        if (!saw_question) {
            // A plain or `-end` range is terminal: any directly-following
            // identifier char (a stray `-name` chain like `U+123-456-ABC`, or
            // a non-hex letter like `U+1234GH`) is "Expected end of
            // identifier." in dart-sass.
            if ((match (self.sc.peek()) {
                let c: string if root.parser.is_ident_char(c) => true,
                _ => false,
            })
                || (self.sc.peek() == "#" && self.sc.peek_at(1) == "{"))
            {
                throw root.error.Error.at("Expected end of identifier.", self.sc.position());
            }
            return token;
        }
        // After a `?` wildcard form, dart-sass does not allow a `-end` range,
        // so the wildcard token is terminal. A directly-following `-<digit>`
        // (no whitespace) continues as a subtraction whose unquoted-string
        // join yields `U+A?-1234`. A directly-following identifier
        // (`U+A?BCDE`, `U+A?-BCDE`) instead begins a fresh space-list element
        // with an implicit separator, handled by `space_list`.
        if (self.sc.peek() == "-"
            && (match (self.sc.peek_at(1)) {
                let c: string if root.std.is_ascii_digit(c) || c == "." => true,
                _ => false,
            }))
        {
            let pos = self.sc.position();
            self.sc.bump(); // '-'
            let rhs = self.multiplicative();
            return root.ast.Expr_Binary {
                op: root.ast.BinOp.Sub,
                lhs: token,
                rhs: rhs,
                pos: pos,
            };
        }
        if ((match (self.sc.peek()) {
            let c: string if root.parser.is_ident_char(c) || c == "." => true,
            _ => false,
        })
            || (self.sc.peek() == "#" && self.sc.peek_at(1) == "{"))
        {
            // Signal `space_list` to continue without requiring whitespace.
            self.pending_unicode_split = true;
        }
        token
    }

    /// Continue a comma list whose first element (`first`) has already been
    /// parsed at the space-list level, stopping before the closing `)`. Used
    /// when the leading element of a parenthesised group turned out not to be
    /// a map key. With no following commas this is just `first`.
    /// Like [`finish_paren_list`], but the list ends at `]`.
    function finish_bracket_list(self, first: root.ast.Expr) -> root.ast.Expr {
        let rest: root.ast.Expr[] = [];
        let trailing = false;
        while (true) {
            let mark = self.sc.mark();
            self.skip_ws_inline();
            if (self.sc.peek() == ",") {
                self.sc.bump();
                self.skip_ws_inline();
                if (self.sc.peek() == "]") {
                    trailing = true;
                    break;
                }
                rest.push(self.space_list());
            } else {
                self.sc.reset(mark);
                break;
            }
        }
        if (rest.length() == 0 && !trailing) {
            return first;
        }
        let items: root.ast.Expr[] = [];
        items.push(first);
        root.std.extend(items, rest);
        root.ast.Expr_List {
            items: items,
            sep: root.value.ListSep.Comma,
            bracketed: false,
        }
    }

    function finish_paren_list(self, first: root.ast.Expr) -> root.ast.Expr {
        let rest: root.ast.Expr[] = [];
        let trailing = false;
        while (true) {
            let mark = self.sc.mark();
            self.skip_ws_inline();
            if (self.sc.peek() == ",") {
                self.sc.bump();
                self.skip_ws_inline();
                if (self.sc.peek() == ")") {
                    trailing = true;
                    break;
                }
                rest.push(self.space_list());
            } else {
                self.sc.reset(mark);
                break;
            }
        }
        if (rest.length() == 0 && !trailing) {
            return first;
        }
        let items: root.ast.Expr[] = [];
        items.push(first);
        root.std.extend(items, rest);
        root.ast.Expr_List {
            items: items,
            sep: root.value.ListSep.Comma,
            bracketed: false,
        }
    }

    /// Parse the remaining entries of a map literal after the first key was
    /// parsed and the `:` separator confirmed (but not yet consumed). Each
    /// entry is `key: value` at the space-list level, comma-separated, with an
    /// optional trailing comma before `)`.
    function parse_map_after_first_key(self, first_key: root.ast.Expr) -> root.ast.Expr {
        let entries: root.std.Tuple2<root.ast.Expr, root.ast.Expr>[] = [];
        // Consume the `:` for the first entry and read its value.
        self.sc.bump();
        self.skip_ws_inline();
        let first_val = self.space_list();
        entries.push(root.std.Tuple2 { _0: first_key, _1: first_val });
        while (true) {
            self.skip_ws_inline();
            if (!self.sc.eat(",")) {
                break;
            }
            self.skip_ws_inline();
            if (self.sc.peek() == ")") {
                break; // trailing comma
            }
            let key = self.space_list();
            self.skip_ws_inline();
            if (!(self.sc.peek() == ":" && self.sc.peek_at(1) != ":")) {
                throw root.error.Error.at("expected \":\".", self.sc.position());
            }
            self.sc.bump();
            self.skip_ws_inline();
            let val = self.space_list();
            entries.push(root.std.Tuple2 { _0: key, _1: val });
        }
        self.skip_ws_inline();
        if (!self.sc.eat(")")) {
            throw root.error.Error.at("expected \")\"", self.sc.position());
        }
        root.ast.Expr_Map { _0: entries }
    }

    /// Parse a bracketed list literal `[ ... ]`. An empty `[]` is a bracketed
    /// empty space list; otherwise the interior is parsed as an ordinary value
    /// (which may itself be a comma/space list) and re-marked as bracketed.
    function parse_bracketed_list(self) -> root.ast.Expr {
        self.sc.bump(); // '['
        self.skip_ws_inline();
        if (self.sc.peek() == "]") {
            self.sc.bump();
            return root.ast.Expr_List {
                items: [],
                sep: root.value.ListSep.Undecided,
                bracketed: true,
            };
        }
        // Parse like a paren group so a trailing comma marks a one-element
        // COMMA list (`[1,]` keeps its separator, like `(1,)`).
        let first = self.space_list();
        let inner = self.finish_bracket_list(first);
        self.skip_ws_inline();
        if (!self.sc.eat("]")) {
            throw root.error.Error.at("expected \"]\"", self.sc.position());
        }
        // An *unbracketed* list interior (the comma/space list produced by
        // parsing several elements) keeps its separator and is simply marked
        // bracketed. A scalar — or a single nested bracketed list like
        // `[[c]]` — becomes a one-item bracketed list instead of being
        // unwrapped.
        match (inner) {
            root.ast.Expr_List {
                items: let items,
                sep: let sep,
                bracketed: false,
            } => root.ast.Expr_List {
                items: items,
                sep: sep,
                bracketed: true,
            },
            // A single-element bracketed list (`[1]`, `[[c]]`) has no decided
            // separator yet, so it stays undecided like a bare value would.
            let other => root.ast.Expr_List {
                items: [other],
                sep: root.value.ListSep.Undecided,
                bracketed: true,
            },
        }
    }

    /// The interned `Rc<str>` for a numeric literal's unit (`""` included).
    function unit_name(self, unit: string) -> string {
        if let u: string = self.unit_names.find((u) -> { u == unit }) {
            return u;
        }
        let interned: string = unit;
        self.unit_names.push(interned);
        interned
    }

    function parse_number(self) -> root.ast.Expr {
        let s = "";
        while (root.std.is_ascii_digit(self.sc.peek())) {
            if let c: string = self.sc.bump() {
                s = s + c;
            }
        }
        if (self.sc.peek() == "." && root.std.is_ascii_digit(self.sc.peek_at(1))) {
            if let c: string = self.sc.bump() {
                s = s + c;
            }
            while (root.std.is_ascii_digit(self.sc.peek())) {
                if let c: string = self.sc.bump() {
                    s = s + c;
                }
            }
        }
        // Scientific notation: dart-sass commits to an exponent as soon as
        // `e`/`E` is followed by a digit OR a sign, then *requires* at least
        // one digit — so `1e-`, `1e-x`, `1e++5`, `1e--5` are "Expected digit.",
        // not a fall-through to a `1e-` unit. A unit like `1em` (or a spaced
        // `1e + 2`) is unaffected: `e` is followed by a letter / whitespace.
        if (self.sc.peek() == "e" || self.sc.peek() == "E") {
            let after = self.sc.peek_at(1);
            let is_exp = match (after) {
                let c: string if root.std.is_ascii_digit(c) || c == "+" || c == "-" => true,
                _ => false,
            };
            if (is_exp) {
                if let c: string = self.sc.bump() {
                    s = s + c;
                }
                if (self.sc.peek() == "+" || self.sc.peek() == "-") {
                    if let c: string = self.sc.bump() {
                        s = s + c;
                    }
                }
                if (!root.std.is_ascii_digit(self.sc.peek())) {
                    throw root.error.Error.at("Expected digit.", self.sc.position());
                }
                while (root.std.is_ascii_digit(self.sc.peek())) {
                    if let c: string = self.sc.bump() {
                        s = s + c;
                    }
                }
            }
        }
        let value: float = baml.Float.parse(s) catch (e) {
            baml.errors.ParseError => {
                throw root.error.Error.at(`invalid number ${root.std.debug_str(s)}`, self.sc.position());
            }
        };
        let unit = "";
        if (self.sc.peek() == "%") {
            self.sc.bump();
            unit = unit + "%";
        } else {
            while (true) {
                match (self.sc.peek()) {
                    let c: string if root.std.is_ascii_alphabetic(c) || c == "_" => {
                        self.sc.bump();
                        unit = unit + c;
                    }
                    // An identifier BODY may contain digits (`1a2b3c` is the
                    // single unit `a2b3c`), just not start with one.
                    let c: string if root.std.is_ascii_digit(c) && unit != "" => {
                        self.sc.bump();
                        unit = unit + c;
                    }
                    // dart `identifier(unit: true)`: a `-` joins the unit
                    // unless a digit or dot follows (so `10px-10px` still
                    // subtracts but `10px- 10px` is the unit `px-`).
                    "-" if unit != "" => {
                        match (self.sc.peek_at(1)) {
                            let c: string if root.std.is_ascii_digit(c) || c == "." => {
                                break;
                            }
                            _ => {
                                self.sc.bump();
                                unit = unit + "-";
                            }
                        }
                    }
                    // A unit may START with `-` only when an identifier
                    // follows (`1-em` is 1 with unit `-em`; `1--em` is the
                    // list `1 --em`, `1- 2` subtracts).
                    "-" if unit == "" => {
                        match (self.sc.peek_at(1)) {
                            let c: string if root.std.is_ascii_alphabetic(c) || c == "_" => {
                                self.sc.bump();
                                unit = unit + "-";
                            }
                            _ => {
                                break;
                            }
                        }
                    }
                    // A CSS escape is part of the unit, decoded like any
                    // identifier (`1\65 m` is the unit `em`).
                    "\\" => {
                        unit = unit + self.read_escape_char();
                    }
                    _ => {
                        break;
                    }
                }
            }
        }
        root.ast.Expr_Number { _0: value, _1: self.unit_name(unit) }
    }

    function parse_hex(self) -> root.ast.Expr {
        let pos = self.sc.position();
        self.sc.bump(); // '#'

        // dart-sass splits on the character right after `#`. A *digit* commits
        // to a hex color: it must be 3/4/6/8 hex digits (read in committed
        // stages), and a short or malformed run is "Expected hex digit." —
        // never a hash-identifier (`#0`, `#00000`, `#0g`, `#12g` all error).
        // A *name-start* char is read as a full identifier that is a color only
        // when the whole spelling is a valid hex (`#abc`/`#abcd12` -> color;
        // `#abcde`/`#xyz`/`#foo` -> `#…` string).
        if (root.std.is_ascii_digit(self.sc.peek())) {
            return self.parse_hex_color_contents();
        }
        let hex = "";
        while (root.std.is_ascii_hexdigit(self.sc.peek())) {
            if let c: string = self.sc.bump() {
                hex = hex + c;
            }
        }
        // A `#` token that isn't a valid color is an ID token (CSS `nav-up`
        // and friends accept IDs): keep consuming the identifier and emit
        // the literal (`#ab`, `#abcde`, `#abcg`).
        let continues = match (self.sc.peek()) {
            let c: string if root.parser.is_ident_char(c) || c == "\\" => true,
            _ => false,
        };
        if (!continues) {
            if let c: root.value.Color = root.value.Color.from_hex(hex) {
                return root.ast.Expr_Color { _0: c };
            }
        }
        // PORT: `ident` is a `StrBuf` (it is appended to in a loop and passed
        // to `push_ident_escape` as `&mut String`).
        let ident = root.std.StrBuf.from(hex);
        while (true) {
            match (self.sc.peek()) {
                let c: string if root.parser.is_ident_char(c) => {
                    self.sc.bump();
                    ident.push(c);
                }
                // Escapes store their canonical spelling (`#f00000\9\0` keeps
                // `\9 \0 ` — a control character re-serializes as a hex
                // escape, like dart's identifier canonicalization).
                "\\" => {
                    let c = self.read_escape_char();
                    root.parser.push_ident_escape(ident, c, false);
                }
                _ => {
                    break;
                }
            }
        }
        if (ident.is_empty()) {
            throw root.error.Error.at("Expected identifier.", pos);
        }
        root.ast.Expr_Ident { _0: [root.ast.TplPiece_Lit { _0: `#${ident.as_str()}` }] }
    }

    /// dart-sass `_hexColorContents`: the character after `#` was a digit, so
    /// this is a hex color or an error. Read 3/4/6/8 hex digits in committed
    /// stages (each `read_hex_digit` is mandatory, mirroring dart's `_hexDigit`)
    /// and leave any trailing token for the caller (`#000g` -> `#000` color +
    /// `g`; `#0000g` -> 4-digit color + `g`).
    function parse_hex_color_contents(self) -> root.ast.Expr {
        let hex = root.std.StrBuf.new();
        // digit1..3 are mandatory (`#0`, `#00`, `#0g` error here).
        self.read_hex_digit(hex);
        self.read_hex_digit(hex);
        self.read_hex_digit(hex);
        if (root.std.is_ascii_hexdigit(self.sc.peek())) {
            // a 4th digit -> #RGBA, unless a 5th follows...
            self.read_hex_digit(hex);
            if (root.std.is_ascii_hexdigit(self.sc.peek())) {
                // ...which commits to #RRGGBB — digit5, digit6 are mandatory
                // (`#00000`, `#0000000` error here).
                self.read_hex_digit(hex);
                self.read_hex_digit(hex);
                if (root.std.is_ascii_hexdigit(self.sc.peek())) {
                    // ...and a 7th commits to #RRGGBBAA — digit7, digit8 too.
                    self.read_hex_digit(hex);
                    self.read_hex_digit(hex);
                }
            }
        }
        // The staged read only ever accumulates 3/4/6/8 digits, so `from_hex`
        // always succeeds; the error arm is unreachable defence (no panic).
        match (root.value.Color.from_hex(hex.as_str())) {
            let c: root.value.Color => root.ast.Expr_Color { _0: c },
            null => {
                throw root.error.Error.at("Expected hex digit.", self.sc.position());
            }
        }
    }

    /// Read one required hex digit into `out`, or raise dart's
    /// "Expected hex digit." at the offending position.
    function read_hex_digit(self, out: root.std.StrBuf) -> void {
        match (self.sc.peek()) {
            let c: string if root.std.is_ascii_hexdigit(c) => {
                self.sc.bump();
                out.push(c);
            }
            _ => {
                throw root.error.Error.at("Expected hex digit.", self.sc.position());
            }
        }
    }

    function parse_quoted_string(self) -> root.ast.TplPiece[] {
        let q = match (self.sc.bump()) {
            let c: string => c,
            null => {
                throw root.error.Error.at("expected a string", self.sc.position());
            }
        };
        let pieces: root.ast.TplPiece[] = [];
        let lit = root.std.StrBuf.new();
        while (true) {
            match (self.sc.peek()) {
                null => {
                    throw root.error.Error.at("unterminated string", self.sc.position());
                }
                let c: string if c == q => {
                    self.sc.bump();
                    break;
                }
                "#" if self.sc.peek_at(1) == "{" => {
                    let interp_mark = self.sc.mark();
                    if (!lit.is_empty()) {
                        pieces.push(root.parser.take_lit(lit));
                    }
                    self.sc.bump();
                    self.sc.bump();
                    let e = self.parse_interp_value();
                    self.skip_ws_inline();
                    if (!self.sc.eat("}")) {
                        throw root.error.Error.at("expected \"}\"", self.sc.position());
                    }
                    self.reject_plain_css_interp(interp_mark);
                    pieces.push(root.ast.TplPiece_Interp { _0: e });
                }
                // A `\` before a newline is a CSS line continuation: dart's
                // `string()` drops the pair itself, before the escape reader —
                // which rejects a newline — ever sees it. This is the ONLY
                // place the continuation is legal.
                "\\" if self.sc.peek_at(1) == "\n" || self.sc.peek_at(1) == "\r" || self.sc.peek_at(1) == "\f" => {
                    self.sc.bump();
                    if (self.sc.peek() == "\r") {
                        self.sc.bump();
                        self.sc.eat("\n"); // CRLF
                    } else {
                        self.sc.bump();
                    }
                }
                "\\" => {
                    // Decode the escape to its code point and store it raw; the
                    // string serializer re-escapes only what it must.
                    // `\#{...}` decodes the `#` literally, so the sequence
                    // becomes a plain `#{` rather than interpolation. Inside a
                    // quoted string a NUL escape becomes the Unicode
                    // replacement character (unlike an identifier, where it
                    // serializes as `\0 `).
                    let c = self.consume_escape();
                    lit.push(if (c == "\0") { root.std.chr_unchecked(0xFFFD) } else { c });
                }
                // A literal newline cannot appear inside a quoted string; it must
                // be written as a `\` line continuation or a `\a` escape. dart-sass
                // reports the unterminated string with `Expected "<quote>".`.
                "\n" | "\r" | "\f" => {
                    throw root.error.Error.at(`Expected ${q}.`, self.sc.position());
                }
                let c: string => {
                    lit.push(c);
                    self.sc.bump();
                }
            }
        }
        if (!lit.is_empty()) {
            pieces.push(root.parser.take_lit(lit));
        }
        pieces
    }

    function parse_ident_or_call(self) -> root.ast.Expr {
        // Position/mark of the identifier (function name) start, for diagnostic
        // spans that must point at the name (e.g. `rgb(1, 2)` highlights `rgb`).
        let name_pos = self.sc.position();
        let name_mark = self.sc.mark();
        let pieces = self.parse_ident_template();
        if (pieces.length() == 1) {
            if let first: root.ast.TplPiece_Lit = pieces.at(0) {
                let name = first._0;
                // A `namespace.member` reference: a plain identifier followed by
                // `.` and either `member(...)` (a namespaced function call) or
                // `$var` (a namespaced variable). Only recognised when the `.`
                // is directly followed by an identifier start or `$`; otherwise
                // it is left for ordinary parsing.
                if (self.sc.peek() == ".") {
                    if let expr: root.ast.Expr = self.try_parse_namespaced(name, name_pos, name_mark) {
                        return expr;
                    }
                }
                if (self.sc.peek() == "(") {
                    return self.parse_call(name, name_pos, name_mark);
                }
                // IE `progid:` special function: `[-vendor-]progid:Name(...)`.
                // The identifier `progid` (or a vendor-prefixed `-x-progid`) is
                // recognised only when immediately followed by a `:`. The
                // argument list (and any further `.Name` chain) is preserved
                // verbatim with only `#{...}` interpolation resolved.
                if (self.sc.peek() == ":" && root.parser.is_progid_name(name)) {
                    return self.parse_progid(name);
                }
                // In plain CSS `true`/`false`/`null` have no special meaning;
                // they stay plain identifiers (dart-sass `CssParser`).
                if (!self.plain_css) {
                    match (name) {
                        "true" => {
                            return root.ast.Expr_Bool { _0: true };
                        }
                        "false" => {
                            return root.ast.Expr_Bool { _0: false };
                        }
                        "null" => {
                            return root.ast.Expr_Null {};
                        }
                        _ => {}
                    }
                }
                // A colour KEYWORD is a Sass value, not a CSS one: dart's
                // `CssParser` leaves `white` an identifier, so it passes
                // through with its own spelling instead of compressing to
                // `#fff` (and `TRANSPARENT` keeps its case).
                if (!self.plain_css) {
                    if let color: root.value.Color = root.value.named_color(name) {
                        return root.ast.Expr_Color { _0: color };
                    }
                }
            }
        }
        // An interpolated identifier directly followed by `(` is a plain-CSS
        // call with a dynamic name (`qu#{o}te(arg)` serializes as `quote(arg)`
        // — never dispatched to a real function).
        if (self.sc.peek() == "("
            && pieces.some((p) -> { p is root.ast.TplPiece_Interp })
            && !self.plain_css)
        {
            self.sc.bump();
            let args = self.parse_args_after_paren();
            return root.ast.Expr_InterpFunc {
                name: pieces,
                args: args,
                pos: name_pos,
            };
        }
        root.ast.Expr_Ident { _0: pieces }
    }

    /// Try to parse a `namespace.member` reference after the namespace
    /// identifier `ns` has been consumed and the next character is `.`.
    /// Returns `Some(Expr)` for `ns.fn(...)` or `ns.$var`, or `None` (without
    /// consuming the `.`) when the dot does not begin a namespaced member.
    function try_parse_namespaced(self, ns: string, name_pos: root.scanner.Pos, name_mark: root.scanner.Mark) -> root.ast.Expr? {
        let mark = self.sc.mark();
        self.sc.bump(); // '.'
        match (self.sc.peek()) {
            // `ns.$var`
            "$" => {
                self.sc.bump();
                // Privacy is the LITERAL spelling (`ns.$\2d x` is an ordinary
                // member for dart), and the caret covers the whole `ns.$name`
                // reference as written.
                let literally_private = self.sc.peek() == "-" || self.sc.peek() == "_";
                let name = self.read_variable_name();
                if (literally_private) {
                    throw root.error.Error.at(
                        "Private members can't be accessed from outside their modules.",
                        name_pos,
                    )
                    .with_length(self.sc.byte_len_from(name_mark));
                }
                let length = self.sc.byte_len_from(name_mark);
                root.ast.Expr_NsVar {
                    module: ns,
                    name: name,
                    pos: name_pos,
                    length: length,
                }
            }
            // `ns.member(...)` — the member must be an identifier immediately
            // followed by `(`.
            let c: string if root.std.is_ascii_alphabetic(c) || c == "-" || c == "_" || c == "\\" => {
                let member_pos = self.sc.position();
                let member_mark = self.sc.mark();
                // Privacy is the LITERAL spelling, and the caret covers the
                // member as written (an escape counts its source bytes).
                let literally_private = self.sc.peek() == "-" || self.sc.peek() == "_";
                let member = self.read_ident_name();
                if (self.sc.peek() == "(") {
                    if (literally_private) {
                        throw root.error.Error.at(
                            "Private members can't be accessed from outside their modules.",
                            member_pos,
                        )
                        .with_length(self.sc.byte_len_from(member_mark));
                    }
                    self.sc.bump(); // '('
                    let args = self.parse_args_after_paren();
                    root.ast.Expr_Func {
                        name: member,
                        args: args,
                        pos: name_pos,
                        length: self.sc.byte_len_from(name_mark),
                        module: ns,
                    }
                } else {
                    // A namespaced reference that is not a call is not a value
                    // (dart-sass only allows `ns.$var` and `ns.fn(...)`); back
                    // off and let ordinary parsing handle the `.`.
                    self.sc.reset(mark);
                    null
                }
            }
            _ => {
                self.sc.reset(mark);
                null
            }
        }
    }

    function parse_ident_template(self) -> root.ast.TplPiece[] {
        self.parse_ident_template_from(0)
    }

    /// As [`parse_ident_template`], with `emitted` pre-seeded — the
    /// continuation of `#{foo}\-` is MID-identifier, so its escapes use the
    /// name-char rule, not the name-START rule.
    function parse_ident_template_from(self, start_emitted: int) -> root.ast.TplPiece[] {
        let pieces: root.ast.TplPiece[] = [];
        let lit = root.std.StrBuf.new();
        // `emitted` counts code points written to the identifier so far (across
        // both literal and interpolation pieces) so the leading-digit / first
        // -char escaping rules can be applied. `first_hyphen` records whether
        // the identifier begins with `-` (a digit right after it is escaped).
        let emitted = start_emitted;
        let first_hyphen = false;
        while (true) {
            match (self.sc.peek()) {
                "#" if self.sc.peek_at(1) == "{" => {
                    let interp_mark = self.sc.mark();
                    if (!lit.is_empty()) {
                        pieces.push(root.parser.take_lit(lit));
                    }
                    self.sc.bump();
                    self.sc.bump();
                    let e = self.parse_interp_value();
                    self.skip_ws_inline();
                    if (!self.sc.eat("}")) {
                        throw root.error.Error.at("expected \"}\"", self.sc.position());
                    }
                    self.reject_plain_css_interp(interp_mark);
                    pieces.push(root.ast.TplPiece_Interp { _0: e });
                    emitted += 1;
                },
                "\\" => {
                    let c = self.consume_escape();
                    // The escape is at "identifier start" when it is the very
                    // first code point, or the code point right after a single
                    // leading literal/escaped `-`.
                    let identifier_start = emitted == 0 || (emitted == 1 && first_hyphen);
                    root.parser.push_ident_escape(lit, c, identifier_start);
                    emitted += 1;
                },
                let c: string if root.parser.is_ident_char(c) => {
                    lit.push(c);
                    self.sc.bump();
                    if (emitted == 0 && c == "-") {
                        first_hyphen = true;
                    }
                    emitted += 1;
                },
                _ => {
                    break;
                },
            }
        }
        if (!lit.is_empty()) {
            pieces.push(root.parser.take_lit(lit));
        }
        pieces
    }

    function parse_call(self, name: string, name_pos: root.scanner.Pos, name_mark: root.scanner.Mark) -> root.ast.Expr {
        // A plain-CSS function call is preserved verbatim, but a Sass-only global
        // function (one with no plain-CSS meaning, e.g. `index`) is rejected.
        if (self.plain_css && root.parser.is_sass_only_function(name)) {
            throw root.error.Error.at("This function isn't allowed in plain CSS.", name_pos);
        }
        self.sc.bump(); // '('
        // `calc()` interior is parsed as a real arithmetic
        // expression and simplified at evaluation time. The
        // name is matched case-insensitively (`CaLc(1px)` ->
        // `1px`); a vendor-prefixed `-webkit-calc(…)` does not
        // match and stays a verbatim special function.
        if (root.std.eq_ignore_ascii_case(name, "calc")) {
            self.skip_ws_inline();
            if (self.sc.peek() == ")") {
                // An empty `calc()` is NOT a calculation (calc needs one
                // argument) nor a verbatim special function; it's a regular
                // function call, so a user `@function calc()` can be invoked
                // (dart-sass).
                let args = self.parse_args_after_paren();
                return root.ast.Expr_Func {
                    name: name,
                    args: args,
                    pos: name_pos,
                    length: self.sc.byte_len_from(name_mark),
                    module: null,
                };
            }
            self.calc_depth += 1;
            // PORT: Rust restores `calc_depth` before propagating the `Result`;
            // the error arm restores it and rethrows.
            let inner = self.parse_value() catch (e) {
                let err: root.error.Error => {
                    self.calc_depth -= 1;
                    throw err;
                }
            };
            self.calc_depth -= 1;
            self.skip_ws_inline();
            if (!self.sc.eat(")")) {
                throw root.error.Error.at("expected \")\"", self.sc.position());
            }
            return root.ast.Expr_Calc {
                inner: inner,
            };
        }
        // CSS functions whose contents must be preserved verbatim (they may
        // contain arithmetic that is not Sass math), while still resolving
        // any `#{...}` interpolation inside them. `min`/`max`/`clamp` are
        // NOT here: they route to the math builtins, which evaluate their
        // arguments as Sass values and reduce when every argument is a
        // compatible-unit number, otherwise fall back to a preserved CSS
        // `min()`/`max()`/`clamp()` form (so `min(1px, 2vw)` round-trips).
        // A `url(` function (case-insensitively, with an optional vendor
        // prefix): dart-sass tries to read a plain unquoted URL verbatim. If
        // that succeeds the call is emitted as a bare lower-cased `url(...)`
        // (the vendor prefix is dropped); if the contents contain SassScript
        // (a `$variable`), the trial fails and the call is parsed as an
        // ordinary function so its arguments evaluate (keeping the original
        // name, e.g. `-e-url($a)` -> `-e-url(b)`).
        if (root.parser.is_url_function(name)) {
            let mark = self.sc.mark();
            if let pieces: root.ast.TplPiece[] = self.try_plain_url_contents() {
                return root.ast.Expr_Ident { _0: pieces };
            }
            self.sc.reset(mark);
            let args = self.parse_args_after_paren();
            return root.ast.Expr_Func {
                name: name,
                args: args,
                pos: name_pos,
                length: self.sc.byte_len_from(name_mark),
                module: null,
            };
        }
        // `var()` and `env()` are plain CSS functions whose arguments are
        // ordinary SassScript: dart-sass evaluates the fallback/value
        // arguments, normalises surrounding whitespace, and expands a
        // `var($args...)` splat. They route through the regular function-call
        // eval path (neither is a Sass builtin, so the result is preserved
        // verbatim as `var(...)`/`env(...)`). The single exception is `var`'s
        // `allowEmptySecondArg`: `var(--c,)` keeps a trailing empty argument
        // (`var(--c, )`), case-insensitively for the name `var` only — `env`
        // and every other case follow the normal trailing-comma rules.
        {
            let lower = root.std.ascii_lower(name);
            if (lower == "var" || lower == "env") {
                let args = self.parse_args_after_paren_opt_empty_second(lower == "var");
                return root.ast.Expr_Func {
                    name: name,
                    args: args,
                    pos: name_pos,
                    length: self.sc.byte_len_from(name_mark),
                    module: null,
                };
            }
        }
        // Special CSS functions (`calc()`, `element()`, `expression()` with or
        // without a vendor prefix; `type()` unprefixed) preserve their
        // arguments verbatim — they may contain `%`, `@`, `=`, IE-hack syntax,
        // comments, and other non-SassScript characters. Only `#{...}`
        // interpolation is resolved; the function name is lower-cased.
        if let canonical: string = root.parser.special_function_name(name) {
            return self.parse_special_function(canonical);
        }
        // The modern CSS `if()` uses `:`/`;` clause syntax and `css()`/
        // `sass()` wrappers, which the comma-arg parser cannot handle. Try
        // the modern grammar first; if it does not match, reset and fall
        // back to the legacy `if($cond, $t, $f)` builtin.
        if (name == "if") {
            let mark = self.sc.mark();
            let seen_interp = self.plain_css_interp;
            // PORT: `match self.try_parse_modern_if()` — the `Err` arms are the
            // catch arm (yielding `None`, i.e. "reset"), the `Ok` arms follow.
            let modern = self.try_parse_modern_if() catch (e) {
                let err: root.error.Error => {
                    // An attempt that read a `#{…}` in plain CSS cannot be retried:
                    // the legacy argument grammar has to reject that text too, and
                    // would report its own complaint (`Operators aren't allowed in
                    // plain CSS.` at a `>` the raw grammar reads verbatim) in place
                    // of the one dart raises inside the interpolation.
                    if (self.plain_css_interp && !seen_interp) {
                        throw err;
                    }
                    null
                }
            };
            if let clauses: root.ast.IfClause[] = modern {
                return root.ast.Expr_ModernIf { _0: clauses };
            }
            self.sc.reset(mark);
        }
        let args = self.parse_args_after_paren();
        root.ast.Expr_Func {
            name: name,
            args: args,
            pos: name_pos,
            length: self.sc.byte_len_from(name_mark),
            module: null,
        }
    }

    /// Capture the argument list of a special CSS function verbatim after the
    /// opening `(` has been consumed. `canonical` is the lower-cased function
    /// name to emit. The contents are preserved literally except that:
    ///   - `#{...}` interpolation is resolved;
    ///   - runs of whitespace collapse to a single space;
    ///   - silent `//` comments are dropped (the whitespace around them stays);
    ///   - loud `/* */` comments, quoted strings, and all other characters
    ///     (`%`, `@`, `=`, punctuation, …) are emitted verbatim.
    ///
    /// Nested parentheses are balanced.
    function parse_special_function(self, canonical: string) -> root.ast.Expr {
        let pieces: root.ast.TplPiece[] = [];
        let lit = root.std.StrBuf.from(`${canonical}(`);
        self.capture_verbatim_args(pieces, lit)
    }

    /// Parse an IE `progid:` special function whose `[-vendor-]progid` prefix
    /// (passed as `name`, with the `:` not yet consumed) has been recognised.
    /// The prefix is lower-cased on emit; a `.`-separated chain of ASCII-letter
    /// name segments follows the `:` (kept verbatim, case preserved), then an
    /// opening `(` is required and the argument list is captured verbatim
    /// (resolving only `#{...}` interpolation). Mirrors dart-sass's `progid`
    /// branch of `_trySpecialFunction`.
    function parse_progid(self, name: string) -> root.ast.Expr {
        let lit = root.std.StrBuf.from(root.std.ascii_lower(name));
        self.sc.bump(); // ':'
        lit.push(":");
        // The name chain: ASCII letters and `.` only (e.g.
        // `DXImageTransform.Microsoft.gradient`). Anything else stops the chain
        // and the required `(` check below produces dart-sass's error.
        while let c: string = self.sc.peek() {
            if (c.is_ascii_alphabetic() || c == ".") {
                lit.push(c);
                self.sc.bump();
            } else {
                break;
            }
        }
        if (!self.sc.eat("(")) {
            throw root.error.Error.at("expected \"(\".", self.sc.position());
        }
        lit.push("(");
        self.capture_verbatim_args([], lit)
    }

    /// Continue capturing a verbatim special-function argument list, given the
    /// already-accumulated template `pieces`/`lit` (which must end with the
    /// opening `(` that has just been consumed). The closing `)` is consumed.
    /// Used by both the named special functions (`calc()`, `element()`, …) and
    /// the IE `progid:` form, which share dart-sass's interpolated-declaration
    /// value grammar.
    function capture_verbatim_args(self, pieces: root.ast.TplPiece[], lit: root.std.StrBuf) -> root.ast.Expr {
        let depth = 1;
        while (true) {
            match (self.sc.peek()) {
                null => {
                    break;
                },
                "#" if self.sc.peek_at(1) == "{" => {
                    let interp_mark = self.sc.mark();
                    if (!lit.is_empty()) {
                        pieces.push(root.parser.take_lit(lit));
                    }
                    self.sc.bump();
                    self.sc.bump();
                    let e = self.parse_interp_value();
                    self.skip_ws_inline();
                    if (!self.sc.eat("}")) {
                        throw root.error.Error.at("expected \"}\"", self.sc.position());
                    }
                    self.reject_plain_css_interp(interp_mark);
                    pieces.push(root.ast.TplPiece_Interp { _0: e });
                },
                // Quoted strings: copy verbatim (parens inside do not
                // nest), but `#{…}` interpolation INSIDE still resolves
                // (`src="#{foo}"` emits `src="foo"`).
                let q: string if q == "\"" || q == "'" => {
                    lit.push(q);
                    self.sc.bump();
                    while (true) {
                        match (self.sc.peek()) {
                            null => {
                                break;
                            },
                            "#" if self.sc.peek_at(1) == "{" => {
                                let interp_mark = self.sc.mark();
                                if (!lit.is_empty()) {
                                    pieces.push(root.parser.take_lit(lit));
                                }
                                self.sc.bump();
                                self.sc.bump();
                                let e = self.parse_interp_value();
                                self.skip_ws_inline();
                                if (!self.sc.eat("}")) {
                                    throw root.error.Error.at("expected \"}\"", self.sc.position());
                                }
                                self.reject_plain_css_interp(interp_mark);
                                pieces.push(root.ast.TplPiece_Interp { _0: e });
                            },
                            "\\" => {
                                lit.push("\\");
                                self.sc.bump();
                                if let esc: string = self.sc.bump() {
                                    lit.push(esc);
                                }
                            },
                            let ch: string => {
                                lit.push(ch);
                                self.sc.bump();
                                if (ch == q) {
                                    break;
                                }
                            },
                        }
                    }
                },
                // Loud comment: emit verbatim.
                "/" if self.sc.peek_at(1) == "*" => {
                    lit.push("/");
                    lit.push("*");
                    self.sc.bump();
                    self.sc.bump();
                    while (true) {
                        match (self.sc.peek()) {
                            null => {
                                break;
                            },
                            "*" if self.sc.peek_at(1) == "/" => {
                                lit.push("*");
                                lit.push("/");
                                self.sc.bump();
                                self.sc.bump();
                                break;
                            },
                            let c: string => {
                                lit.push(c);
                                self.sc.bump();
                            },
                        }
                    }
                },
                // Silent comment: drop it (surrounding whitespace is kept).
                "/" if self.sc.peek_at(1) == "/" => {
                    while let c: string = self.sc.peek() {
                        if (c == "\n") {
                            break;
                        }
                        self.sc.bump();
                    }
                },
                // A backslash escapes the next character: both are emitted
                // verbatim, and the escaped character (e.g. `\(` or `\)`) does
                // NOT affect parenthesis nesting. Mirrors dart-sass's
                // `_interpolatedDeclarationValue` escape handling.
                "\\" => {
                    lit.push("\\");
                    self.sc.bump();
                    if let c: string = self.sc.bump() {
                        lit.push(c);
                    }
                },
                // Whitespace run collapses to a single space.
                let c: string if c.is_whitespace() => {
                    while (root.std.is_whitespace(self.sc.peek())) {
                        self.sc.bump();
                    }
                    lit.push(" ");
                },
                "(" => {
                    depth += 1;
                    lit.push("(");
                    self.sc.bump();
                },
                ")" => {
                    depth -= 1;
                    lit.push(")");
                    self.sc.bump();
                    if (depth == 0) {
                        break;
                    }
                },
                let c: string => {
                    lit.push(c);
                    self.sc.bump();
                },
            }
        }
        if (depth != 0) {
            throw root.error.Error.at("expected \")\"", self.sc.position());
        }
        if (!lit.is_empty()) {
            pieces.push(root.parser.take_lit(lit));
        }
        root.ast.Expr_Ident { _0: pieces }
    }

    /// Try to read the contents of a `url(` as a plain unquoted URL (the `(`
    /// is already consumed). Returns `Some(pieces)` emitting a canonical
    /// `url(<contents>)` (vendor prefix dropped, name lower-cased) when the
    /// contents are a plain URL — arbitrary url-safe characters plus `#{...}`
    /// interpolation, balanced parentheses, and quoted strings. Returns `None`
    /// (without committing the cursor — the caller resets) when a top-level
    /// `$variable` appears, signalling that the call must instead be parsed as
    /// an ordinary function so its arguments evaluate.
    function try_plain_url_contents(self) -> root.ast.TplPiece[]? {
        let pieces: root.ast.TplPiece[] = [];
        let lit = root.std.StrBuf.from("url(");
        let depth = 1;
        // dart-sass skips leading whitespace (without comments, so `/* */`
        // stays literal) right after the opening paren before reading the URL.
        // PORT: `matches!(peek, Some(' ' | '\t' | '\n' | '\r' | '\x0c'))` is
        // exactly `is_ascii_whitespace`.
        while (root.std.is_ascii_whitespace(self.sc.peek())) {
            self.sc.bump();
        }
        while (true) {
            match (self.sc.peek()) {
                null => {
                    return null;
                },
                // A top-level `$variable` is SassScript, not a plain URL.
                "$" => {
                    return null;
                },
                "#" if self.sc.peek_at(1) == "{" => {
                    let interp_mark = self.sc.mark();
                    if (!lit.is_empty()) {
                        pieces.push(root.parser.take_lit(lit));
                    }
                    self.sc.bump();
                    self.sc.bump();
                    let e = self.parse_interp_value();
                    self.skip_ws_inline();
                    if (!self.sc.eat("}")) {
                        throw root.error.Error.at("expected \"}\"", self.sc.position());
                    }
                    self.reject_plain_css_interp(interp_mark);
                    pieces.push(root.ast.TplPiece_Interp { _0: e });
                },
                // A quoted string makes this a NORMAL function call, not a
                // plain-URL token (dart-sass): the string argument then
                // serializes canonically (double quotes preferred), so
                // `url('x.png')` emits `url("x.png")`.
                "\"" | "'" => {
                    return null;
                },
                // A CSS escape in unquoted URL contents is decoded and
                // re-serialized with the identifier rules (always in body
                // position, so a leading digit or `-` stays literal). This also
                // makes `\#{}` a literal `#{}` rather than interpolation.
                "\\" => {
                    let c = self.consume_escape();
                    root.parser.push_ident_escape(lit, c, false);
                },
                "(" => {
                    depth += 1;
                    lit.push("(");
                    self.sc.bump();
                },
                ")" => {
                    depth -= 1;
                    lit.push(")");
                    self.sc.bump();
                    if (depth == 0) {
                        break;
                    }
                },
                // dart-sass allows whitespace in a plain-URL token only
                // directly before the closing `)`. A space followed by more
                // contents makes this a NORMAL function call instead, so
                // `url(foo + bar)` evaluates SassScript (-> `url(foobar)`).
                " " | "\t" | "\n" | "\r" | "\f" => {
                    while (root.std.is_ascii_whitespace(self.sc.peek())) {
                        self.sc.bump();
                    }
                    if (self.sc.peek() != ")") {
                        return null;
                    }
                },
                let c: string => {
                    lit.push(c);
                    self.sc.bump();
                },
            }
        }
        if (depth != 0) {
            return null;
        }
        if (!lit.is_empty()) {
            pieces.push(root.parser.take_lit(lit));
        }
        pieces
    }

    /// Attempt to parse the modern `if()` grammar after the opening `(` was
    /// consumed. Returns `Ok(Some(_))` if the input matches the modern
    /// clause syntax (consuming through the closing `)`), `Ok(None)` if it
    /// is clearly the legacy comma-arg form, or `Err` on a genuine modern
    /// syntax error (which surfaces to the caller as a hard error after the
    /// trial succeeds in committing to modern).
    function try_parse_modern_if(self) -> root.ast.IfClause[]? {
        self.skip_ws_inline();
        // Recognise the first clause to decide between modern and legacy.
        // A modern clause starts with `else` or a condition atom; if the
        // first token cannot begin a condition, this is the legacy form.
        let first = match (self.parse_if_clause(true)) {
            let c: root.ast.IfClause => c,
            null => {
                return null;
            },
        };
        let clauses: root.ast.IfClause[] = [first];
        while (true) {
            self.skip_ws_inline();
            if (self.sc.eat(";")) {
                self.skip_ws_inline();
                if (self.sc.peek() == ")") {
                    break; // trailing semicolon
                }
                match (self.parse_if_clause(false)) {
                    let c: root.ast.IfClause => {
                        clauses.push(c);
                    },
                    null => {
                        throw root.error.Error.at("Expected identifier.", self.sc.position());
                    },
                }
                continue;
            }
            break;
        }
        self.skip_ws_inline();
        if (!self.sc.eat(")")) {
            throw root.error.Error.at("expected \")\".", self.sc.position());
        }
        clauses
    }

    /// Parse one `if()` clause: `<condition>: <value>` or `else: <value>`.
    /// When `probe` is true a failure to recognise the leading condition
    /// returns `Ok(None)` (signalling a fall-back to legacy) rather than an
    /// error.
    function parse_if_clause(self, probe: bool) -> root.ast.IfClause? {
        self.skip_ws_inline();
        // `else` clause: bare keyword, no condition.
        let else_mark = self.sc.mark();
        if (self.try_keyword("else")) {
            self.skip_ws_inline();
            if (self.sc.peek() == ":") {
                self.sc.bump();
                self.skip_ws_inline();
                let value = self.space_list();
                return root.ast.IfClause {
                    condition: null,
                    value: value,
                };
            }
            // `else` not followed by `:` — not a modern else clause.
            self.sc.reset(else_mark);
        }
        let condition = match (self.parse_if_cond(probe)) {
            let c: root.ast.IfCond => c,
            null => {
                return null;
            },
        };
        // A condition may not mix an evaluated `sass()` with a multi-token
        // "arbitrary substitution" raw sequence at the same boolean level.
        let _ = root.parser.validate_if_cond(condition);
        self.skip_ws_inline();
        if (!self.sc.eat(":")) {
            throw root.error.Error.at("expected \":\".", self.sc.position());
        }
        self.skip_ws_inline();
        let value = self.space_list();
        root.ast.IfClause {
            condition: condition,
            value: value,
        }
    }

    /// Parse a full `if()` condition. dart-sass's grammar:
    ///   `not <operand>`                        (a single negated operand)
    ///   `<operand> (and <operand>)+`           (an `and` chain)
    ///   `<operand> (or <operand>)+`            (an `or` chain)
    ///   `<operand>`                            (a lone operand)
    /// Mixing `and` and `or` at the same level is an error; `not` only
    /// applies to a single non-multi-token operand and cannot be chained.
    /// Keywords (`not`/`and`/`or`) are matched case-insensitively.
    function parse_if_cond(self, probe: bool) -> root.ast.IfCond? {
        self.skip_ws_inline();
        // Leading `not`: a single operand, no following `and`/`or`.
        if (self.eat_if_keyword("not")) {
            self.require_paren_whitespace_after("not");
            self.skip_ws_inline();
            let operand = self.parse_if_operand(false, true);
            return root.ast.IfCond_Not { _0: self.expect_operand(operand) };
        }
        let first = match (self.parse_if_operand(probe, false)) {
            let c: root.ast.IfCond => c,
            null => {
                return null;
            },
        };
        // Peek for a conjunction (case-insensitive).
        let mark = self.sc.mark();
        self.skip_ws_inline();
        let conj = self.peek_if_conjunction();
        self.sc.reset(mark);
        match (conj) {
            let is_and: bool => {
                let kw = if (is_and) { "and" } else { "or" };
                let other = if (is_and) { "or" } else { "and" };
                let items: root.ast.IfCond[] = [first];
                while (true) {
                    let mark = self.sc.mark();
                    self.skip_ws_inline();
                    if (self.eat_if_keyword(kw)) {
                        self.require_paren_whitespace_after(kw);
                        self.skip_ws_inline();
                        let operand = self.parse_if_operand(false, false);
                        items.push(self.expect_operand(operand));
                        continue;
                    }
                    // Mixing the other conjunction is an error.
                    if (self.peek_word_is_ci(other)) {
                        throw root.error.Error.at("expected \":\".", self.sc.position());
                    }
                    self.sc.reset(mark);
                    break;
                }
                if (is_and) {
                    root.ast.IfCond_And { _0: items }
                } else {
                    root.ast.IfCond_Or { _0: items }
                }
            },
            null => first,
        }
    }

    /// Unwrap an operand that may have failed to parse.
    function expect_operand(self, operand: root.ast.IfCond?) -> root.ast.IfCond {
        // PORT: `operand.ok_or_else(|| Error::at(..))` → throw on `None`.
        if (operand == null) {
            throw root.error.Error.at("expected \"(\".", self.sc.position());
        }
        operand
    }

    /// Parse one condition operand: a parenthesised condition, `sass(<expr>)`,
    /// or a raw substitution sequence. When `single` is true (the operand of
    /// `not`), only a single raw token is consumed (a paren or one function
    /// call), not a multi-token sequence. Returns `Ok(None)` (when probing)
    /// if the position cannot begin an operand.
    function parse_if_operand(self, probe: bool, single: bool) -> root.ast.IfCond? {
        self.skip_ws_inline();
        match (self.sc.peek()) {
            "(" => {
                self.sc.bump();
                self.skip_ws_inline();
                let inner = match (self.parse_if_cond(false)) {
                    let c: root.ast.IfCond => c,
                    null => {
                        throw root.error.Error.at("Expected identifier.", self.sc.position());
                    },
                };
                self.skip_ws_inline();
                if (!self.sc.eat(")")) {
                    throw root.error.Error.at("expected \")\".", self.sc.position());
                }
                root.ast.IfCond_Paren { _0: inner }
            },
            _ if self.peek_keyword_paren_ci("sass") => {
                if (self.plain_css) {
                    throw root.error.Error.at(
                        "sass() conditions aren't allowed in plain CSS",
                        self.sc.position(),
                    );
                }
                for (let _i in baml.iter.Range.new(0, "sass".length())) {
                    self.sc.bump();
                }
                self.sc.bump(); // '('
                self.skip_ws_inline();
                let expr = self.space_list();
                self.skip_ws_inline();
                if (!self.sc.eat(")")) {
                    throw root.error.Error.at("expected \")\".", self.sc.position());
                }
                // A `sass()` atom may not be space-adjacent to a raw token
                // ("arbitrary substitution"): `sass(true) var(--x)` is illegal.
                let mark = self.sc.mark();
                let had_ws = self.skip_ws_inline();
                let next_is_raw = had_ws && self.peek_starts_raw_token();
                self.sc.reset(mark);
                if (next_is_raw) {
                    throw root.error.Error.at(
                        "if() conditions with arbitrary substitutions may not contain sass() expressions.",
                        self.sc.position(),
                    );
                }
                root.ast.IfCond_Sass { _0: expr }
            },
            _ => self.parse_if_raw_sequence(probe, single),
        }
    }

    /// Parse a sequence of raw substitution tokens (`css(...)`,
    /// `<ident>(...)`, `#{...}`) joined by spaces into a single non-evaluable
    /// condition. When `single` is true, at most one token is read. A
    /// `sass()` token inside the sequence is the "arbitrary substitution"
    /// error. Returns `Ok(None)` (when probing) if the input cannot begin a
    /// raw token.
    function parse_if_raw_sequence(self, probe: bool, single: bool) -> root.ast.IfCond? {
        let pieces: root.ast.TplPiece[] = [];
        if (!self.read_if_raw_token(pieces)) {
            if (probe) {
                return null;
            }
            throw root.error.Error.at("expected \"(\".", self.sc.position());
        }
        let token_count = 1;
        if (!single) {
            while (true) {
                let mark = self.sc.mark();
                let had_ws = self.skip_ws_inline();
                if (!had_ws || !self.peek_starts_raw_token()) {
                    self.sc.reset(mark);
                    break;
                }
                // A `sass()` token adjacent to raw substitution is illegal.
                if (self.peek_keyword_paren_ci("sass")) {
                    throw root.error.Error.at(
                        "if() conditions with arbitrary substitutions may not contain sass() expressions.",
                        self.sc.position(),
                    );
                }
                pieces.push(root.ast.TplPiece_Lit { _0: " " });
                if (!self.read_if_raw_token(pieces)) {
                    self.sc.reset(mark);
                    break;
                }
                token_count += 1;
            }
        }
        root.ast.IfCond_Raw {
            pieces: pieces,
            multi: token_count > 1,
        }
    }

    /// Whether the next token starts a raw substitution token: an
    /// interpolation or an identifier (which must be followed by `(`).
    function peek_starts_raw_token(self) -> bool {
        match (self.sc.peek()) {
            "#" if self.sc.peek_at(1) == "{" => true,
            let c: string if root.parser.is_ident_char(c) => {
                // A bare keyword (`and`/`or`/`not`) is not a raw token.
                !(self.peek_word_is_ci("and") || self.peek_word_is_ci("or") || self.peek_word_is_ci("not"))
            },
            _ => false,
        }
    }

    /// Read one raw substitution token (`<ident>(...)` or `#{...}`),
    /// appending its serialized pieces. A bare interpolation token is valid;
    /// a bare identifier (not followed by `(`) is not. Returns false if the
    /// position does not start such a token.
    function read_if_raw_token(self, pieces: root.ast.TplPiece[]) -> bool {
        // PORT: BAML's guard grammar rejects a parenthesised `(self.…)` operand,
        // so the (side-effect-free) keyword lookahead of the reserved-word arm's
        // guard is computed up front.
        let reserved_kw_paren = self.peek_keyword_paren_ci("not")
            || self.peek_keyword_paren_ci("and")
            || self.peek_keyword_paren_ci("or");
        match (self.sc.peek()) {
            "#" if self.sc.peek_at(1) == "{" => {
                let interp_mark = self.sc.mark();
                self.sc.bump();
                self.sc.bump();
                let e = self.parse_interp_value();
                self.skip_ws_inline();
                if (!self.sc.eat("}")) {
                    throw root.error.Error.at("expected \"}\"", self.sc.position());
                }
                self.reject_plain_css_interp(interp_mark);
                pieces.push(root.ast.TplPiece_Interp { _0: e });
                // An interpolation followed immediately by `(` is a function.
                if (self.sc.peek() == "(") {
                    self.read_if_raw_parens(pieces);
                }
                true
            },
            // `not`/`and`/`or` are reserved: written as `not(`/`and(`/`or(`
            // (no space) they are the "whitespace required" error, not a
            // function call.
            let c: string if c.is_ascii_alphabetic() && reserved_kw_paren => {
                let kw = if (self.peek_keyword_paren_ci("not")) {
                    "not"
                } else if (self.peek_keyword_paren_ci("and")) {
                    "and"
                } else {
                    "or"
                };
                // Skip the keyword to point the error at the `(`.
                for (let _i in baml.iter.Range.new(0, kw.length())) {
                    self.sc.bump();
                }
                throw root.error.Error.at(
                    `Whitespace is required between "${kw}" and "("`,
                    self.sc.position(),
                );
            },
            let c: string if root.parser.is_ident_char(c) => {
                let mark = self.sc.mark();
                let name_pieces = self.read_ident_template();
                if (self.sc.peek() != "(") {
                    // Bare identifier — not a raw token unless it contained
                    // interpolation (e.g. `#{"x"}`), which is a valid token.
                    if (name_pieces.every((p) -> { p is root.ast.TplPiece_Lit })) {
                        self.sc.reset(mark);
                        return false;
                    }
                    root.std.extend(pieces, name_pieces);
                    return true;
                }
                root.std.extend(pieces, name_pieces);
                self.read_if_raw_parens(pieces);
                true
            },
            _ => false,
        }
    }

    /// Read a balanced `( ... )` group verbatim (resolving interpolation),
    /// appending to `pieces`. Assumes the next char is `(`.
    function read_if_raw_parens(self, pieces: root.ast.TplPiece[]) -> void {
        let lit = root.std.StrBuf.new();
        let depth = 0;
        while (true) {
            match (self.sc.peek()) {
                null => {
                    throw root.error.Error.at("expected \")\".", self.sc.position());
                },
                "#" if self.sc.peek_at(1) == "{" => {
                    let interp_mark = self.sc.mark();
                    if (!lit.is_empty()) {
                        pieces.push(root.parser.take_lit(lit));
                    }
                    self.sc.bump();
                    self.sc.bump();
                    let e = self.parse_interp_value();
                    self.skip_ws_inline();
                    if (!self.sc.eat("}")) {
                        throw root.error.Error.at("expected \"}\"", self.sc.position());
                    }
                    self.reject_plain_css_interp(interp_mark);
                    pieces.push(root.ast.TplPiece_Interp { _0: e });
                },
                "(" => {
                    depth += 1;
                    lit.push("(");
                    self.sc.bump();
                },
                ")" => {
                    depth -= 1;
                    lit.push(")");
                    self.sc.bump();
                    if (depth == 0) {
                        break;
                    }
                },
                let c: string => {
                    lit.push(c);
                    self.sc.bump();
                },
            }
        }
        if (!lit.is_empty()) {
            pieces.push(root.parser.take_lit(lit));
        }
    }

    /// Read an identifier that may contain leading/embedded `#{...}`
    /// interpolation (e.g. `#{css}`), as a template.
    function read_ident_template(self) -> root.ast.TplPiece[] {
        let pieces: root.ast.TplPiece[] = [];
        let lit = root.std.StrBuf.new();
        while (true) {
            match (self.sc.peek()) {
                "#" if self.sc.peek_at(1) == "{" => {
                    let interp_mark = self.sc.mark();
                    if (!lit.is_empty()) {
                        pieces.push(root.parser.take_lit(lit));
                    }
                    self.sc.bump();
                    self.sc.bump();
                    let e = self.parse_interp_value();
                    self.skip_ws_inline();
                    if (!self.sc.eat("}")) {
                        throw root.error.Error.at("expected \"}\"", self.sc.position());
                    }
                    self.reject_plain_css_interp(interp_mark);
                    pieces.push(root.ast.TplPiece_Interp { _0: e });
                },
                let c: string if root.parser.is_ident_char(c) => {
                    lit.push(c);
                    self.sc.bump();
                },
                _ => {
                    break;
                },
            }
        }
        if (!lit.is_empty()) {
            pieces.push(root.parser.take_lit(lit));
        }
        if (pieces.length() == 0) {
            throw root.error.Error.at("Expected identifier.", self.sc.position());
        }
        pieces
    }

    /// Peek whether the next word equals `kw` case-insensitively (followed
    /// by a non-ident char). `if()` keywords are case-insensitive.
    function peek_word_is_ci(self, kw: string) -> bool {
        // PORT: `Scanner::rest()` copies the whole tail in BAML, so the lookahead
        // indexes the scanner in place: `rest.len()` is `chars.length() - pos`,
        // `rest[i]` is `chars[pos + i]`, `rest.get(n)` is `peek_at(n)`.
        let rest_len = self.sc.chars.length() - self.sc.pos;
        let kw_chars = kw.chars();
        if (rest_len < kw_chars.length()) {
            return false;
        }
        let i = 0;
        for (let kc in kw_chars) {
            if (!root.std.eq_ignore_ascii_case(self.sc.chars[self.sc.pos + i], kc)) {
                return false;
            }
            i += 1;
        }
        match (self.sc.peek_at(kw_chars.length())) {
            let c: string => !root.parser.is_ident_char(c),
            null => true,
        }
    }

    /// At the current position, peek whether a conjunction follows.
    /// `Some(true)` for `and`, `Some(false)` for `or`, `None` otherwise.
    function peek_if_conjunction(self) -> bool? {
        if (self.peek_word_is_ci("and")) {
            true
        } else if (self.peek_word_is_ci("or")) {
            false
        } else {
            null
        }
    }

    /// Consume the keyword `kw` (case-insensitively) if it is the next word
    /// (followed by a non-ident char). Does not skip leading whitespace.
    function eat_if_keyword(self, kw: string) -> bool {
        if (self.peek_word_is_ci(kw)) {
            for (let _i in baml.iter.Range.new(0, kw.length())) {
                self.sc.bump();
            }
            true
        } else {
            false
        }
    }

    /// After consuming `not`/`and`/`or`, dart-sass requires whitespace
    /// before a following `(` (otherwise `and(` etc. is a function call,
    /// which is an error in condition position).
    function require_paren_whitespace_after(self, kw: string) -> void {
        if (self.sc.peek() == "(") {
            throw root.error.Error.at(
                `Whitespace is required between "${kw}" and "("`,
                self.sc.position(),
            );
        }
    }

    /// Peek whether the next word is `kw` (case-insensitive) immediately
    /// followed by `(`.
    function peek_keyword_paren_ci(self, kw: string) -> bool {
        // PORT: `Scanner::rest()` copies the whole tail in BAML, so the lookahead
        // indexes the scanner in place (see `peek_word_is_ci`).
        let rest_len = self.sc.chars.length() - self.sc.pos;
        let kw_chars = kw.chars();
        if (rest_len <= kw_chars.length()) {
            return false;
        }
        let i = 0;
        for (let kc in kw_chars) {
            if (!root.std.eq_ignore_ascii_case(self.sc.chars[self.sc.pos + i], kc)) {
                return false;
            }
            i += 1;
        }
        self.sc.peek_at(kw_chars.length()) == "("
    }

    /// Parse a call's argument list, assuming the opening `(` was already
    /// consumed, through the closing `)`. Args are positional or
    /// `$name: value`. Shared by function calls and `@include`.
    /// A function-argument value: a space-list optionally followed by one or
    /// more single-`=` Microsoft-filter operators (`alpha(opacity=80)`). The
    /// `=` is the lowest-precedence value operator and is recognised only here,
    /// inside an argument list (a lone `=` is a syntax error elsewhere). A
    /// `==` is the equality operator and is handled at its own precedence, so
    /// only a `=` not followed by `=` is consumed.
    function arg_value(self) -> root.ast.Expr {
        let lhs: root.ast.Expr = self.space_list();
        while (true) {
            let mark = self.sc.mark();
            self.skip_ws_inline();
            if (self.sc.peek() == "=" && self.sc.peek_at(1) != "=") {
                let pos = self.sc.position();
                self.sc.bump();
                self.skip_ws_inline();
                let rhs = self.space_list();
                lhs = root.ast.Expr_Binary {
                    op: root.ast.BinOp.SingleEq,
                    lhs: lhs,
                    rhs: rhs,
                    pos: pos,
                };
            } else {
                self.sc.reset(mark);
                break;
            }
        }
        lhs
    }

    function parse_args_after_paren(self) -> root.ast.CallArg[] {
        self.parse_args_after_paren_opt_empty_second(false)
    }

    /// Parse a comma-separated argument list after a consumed `(`.
    ///
    /// When `allow_empty_second_arg` is set (dart-sass's `var()` special case),
    /// a `,` immediately followed by `)` right after the *first* argument adds
    /// an empty unquoted-string second argument (`var(--c,)` -> `var(--c, )`)
    /// instead of being treated as a normal ignorable trailing comma.
    function parse_args_after_paren_opt_empty_second(self, allow_empty_second_arg: bool) -> root.ast.CallArg[] {
        let args: root.ast.CallArg[] = [];
        self.skip_ws_inline();
        if (self.sc.peek() != ")") {
            while (true) {
                self.skip_ws_inline();
                let name_opt: string? = null;
                if (self.sc.peek() == "$") {
                    if (self.plain_css) {
                        throw root.error.Error.at(
                            "Sass variables aren't allowed in plain CSS.",
                            self.sc.position(),
                        );
                    }
                    let mark = self.sc.mark();
                    self.sc.bump();
                    let argname = self.read_variable_name();
                    self.skip_ws_inline();
                    if (self.sc.peek() == ":" && self.sc.peek_at(1) != ":") {
                        self.sc.bump();
                        self.skip_ws_inline();
                        name_opt = argname;
                    } else {
                        self.sc.reset(mark);
                    }
                }
                // Source-map: where this argument's value text begins — the
                // span a bound parameter inherits as its definition node.
                let value_pos = self.sc.position();
                let value = self.arg_value();
                // A trailing `...` marks a splat argument: a list spreads into
                // positional args and a map into keyword args. A named arg may
                // not be a splat. Whitespace (including newlines) may separate
                // the value from its `...` (`a($d\n  ...)`).
                self.skip_ws_inline();
                let splat = name_opt == null
                    && self.sc.peek() == "."
                    && self.sc.peek_at(1) == "."
                    && self.sc.peek_at(2) == ".";
                if (splat) {
                    if (self.plain_css) {
                        throw root.error.Error.at("expected \")\".", self.sc.position());
                    }
                    self.sc.bump();
                    self.sc.bump();
                    self.sc.bump();
                }
                let is_first = args.length() == 0;
                let is_named = name_opt != null;
                args.push(root.ast.CallArg {
                    name: name_opt,
                    value: value,
                    splat: splat,
                    value_pos: value_pos,
                });
                self.skip_ws_inline();
                if (self.sc.eat(",")) {
                    self.skip_ws_inline();
                    if (self.sc.peek() == ")") {
                        // `var(<first>,)`: the trailing comma after exactly the
                        // first POSITIONAL (non-splat, non-named) argument
                        // introduces an empty second argument rather than being
                        // ignored (dart: `positional.length == 1 &&
                        // named.isEmpty`) — `var($arg: --c, )` keeps the
                        // ordinary trailing-comma behavior.
                        if (allow_empty_second_arg && is_first && !splat && !is_named) {
                            args.push(root.ast.CallArg {
                                name: null,
                                value: root.ast.Expr_Ident { _0: [] },
                                splat: false,
                                // Synthesized, not written in the source.
                                value_pos: root.scanner.Pos.NONE(),
                            });
                        }
                        break;
                    }
                    continue;
                }
                break;
            }
        }
        self.skip_ws_inline();
        if (!self.sc.eat(")")) {
            throw root.error.Error.at("expected \")\"", self.sc.position());
        }
        args
    }

}
