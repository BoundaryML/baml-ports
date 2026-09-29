// Ported from sasso `src/parser/at_rules.rs` (namespace `root.parser.at_rules`).
//
// At-rule parsing: the largest cluster — `parse_at_rule` dispatch plus
// `@use`/`@forward`/`@import`/`@include`, `@supports`, `@media`,
// `@function`/`@mixin` definitions, `@at-root`, keyframes, generic and
// interpolated at-rules, and their helpers. Extracted verbatim from [`super`].

/// Source-map: stamp the `@` keyword's position onto the lines-carrying
/// at-rule variants — its 0-based column, and its line, which is not the brace
/// line when the prelude spans several lines (dart maps the rule's span
/// start). Purely additive: `start_col`/`map_line` are read only by source-map
/// generation, never by the serializer.
function stamp_at_keyword(stmt: root.ast.Stmt, pos: root.scanner.Pos) -> void {
    // PORT: `&mut Stmt` is the (reference-typed) variant itself; `lines` is a
    // `Copy` struct, so it is replaced by a modified copy instead of mutated.
    match (stmt) {
        let s: root.ast.Stmt_AtRule => {
            s.lines
                = root.ast.SrcLines {
                    ...s.lines,
                    start_col: root.std.saturating_sub_u(pos.col, 1),
                    map_line: pos.line,
                };
        },
        let s: root.ast.Stmt_InterpAtRule => {
            s.lines
                = root.ast.SrcLines {
                    ...s.lines,
                    start_col: root.std.saturating_sub_u(pos.col, 1),
                    map_line: pos.line,
                };
        },
        let s: root.ast.Stmt_Media => {
            s.lines
                = root.ast.SrcLines {
                    ...s.lines,
                    start_col: root.std.saturating_sub_u(pos.col, 1),
                    map_line: pos.line,
                };
        },
        let s: root.ast.Stmt_Supports => {
            s.lines
                = root.ast.SrcLines {
                    ...s.lines,
                    start_col: root.std.saturating_sub_u(pos.col, 1),
                    map_line: pos.line,
                };
        },
        let s: root.ast.Stmt_Keyframes => {
            s.lines
                = root.ast.SrcLines {
                    ...s.lines,
                    start_col: root.std.saturating_sub_u(pos.col, 1),
                    map_line: pos.line,
                };
        },
        _ => {},
    }
}

interface ParserAtRules {
    function parse_at_rule(self) -> root.ast.Stmt throws unknown;

    /// Parse `@import <arg> [, <arg>]* ;`. Each argument is either a Sass
    /// import (a bare quoted string with no modifiers and a non-CSS URL,
    /// which is inlined) or a plain CSS `@import` (a `url(...)` URL, a `.css`/
    /// protocol URL, or a URL followed by media-query/`supports()` modifiers,
    /// which is emitted verbatim).
    function parse_import(
        self,
        pos: root.scanner.Pos,
        start_mark: root.scanner.Mark,
    ) -> root.ast.Stmt throws unknown;

    /// Parse `@use "<url>" [as <namespace>|as *];`. The URL is a quoted string
    /// without interpolation; an explicit `as ns` / `as *` overrides the
    /// default namespace (the segment after the last `/`, or after `sass:`).
    function parse_use(
        self,
        pos: root.scanner.Pos,
        start_mark: root.scanner.Mark,
    ) -> root.ast.Stmt throws unknown;

    /// Parse `@forward "<url>" [as <prefix>-*] [show ...|hide ...] [with (...)];`.
    function parse_forward(
        self,
        pos: root.scanner.Pos,
        start_mark: root.scanner.Mark,
    ) -> root.ast.Stmt throws unknown;

    /// Parse a `with ( $name: value [!default], ... )` configuration clause.
    function parse_config_clause(
        self,
        pos: root.scanner.Pos,
    ) -> root.ast.ConfigEntry[] throws unknown;

    /// Parse a `show`/`hide` member list: comma-separated identifiers and
    /// `$variable` names.
    function parse_forward_members(
        self,
        pos: root.scanner.Pos,
    ) -> root.ast.ForwardMember[] throws unknown;

    /// Read a quoted module URL (no interpolation allowed) for `@use`/`@forward`.
    function parse_module_url(self, pos: root.scanner.Pos) -> string throws unknown;

    /// Skip whitespace and `/* */` / `//` comments (discarding them); used
    /// between the `@import` keyword, URLs, modifiers, and commas.
    function skip_ws_trivia(self) -> void throws unknown;

    /// Parse one `@import` argument and classify it as Sass or plain CSS.
    function parse_import_arg(self, pos: root.scanner.Pos) -> root.ast.ImportArg throws unknown;

    /// Whether the cursor is at a `url(` function call — the name matched the
    /// way dart matches it, case-insensitively and with CSS escapes decoded
    /// (`u\72l(` IS `url(`). A vendor-prefixed spelling does NOT count here:
    /// dart rejects `@import -c-url(…)` with "Expected string.", unlike in a
    /// value position where `-c-url(` is a url token.
    function peek_is_url_func(self) -> bool throws unknown;

    /// Read the `url(...)` argument of an `@import`, mirroring dart-sass
    /// `dynamicUrl`: the contents are tried as a plain URL token first — the
    /// same trial a url in a value position uses, so whitespace padding is
    /// dropped, escapes decode canonically and `#{…}` resolves — and when that
    /// fails (a quoted string, a `$variable`, whitespace in the MIDDLE of the
    /// token) the call is parsed as an ordinary function whose arguments
    /// evaluate, so `@import url($base + "x.css")` imports the computed url
    /// rather than emitting the SassScript verbatim.
    function parse_import_url(self) -> root.ast.TplPiece[] throws unknown;

    /// Parse the optional modifiers that follow an `@import` URL, mirroring
    /// dart-sass `tryImportModifiers`: a run of bare identifiers and unknown
    /// functions (kept near-verbatim), at most interleaved `supports(<query>)`
    /// clauses (parsed structurally so they re-serialize canonically), then —
    /// terminally — a media query list, entered either at a `(`-feature or at
    /// a comma following a bare identifier (a media type). After the media
    /// list the modifiers END: a following `supports(...)`/identifier is a
    /// syntax error surfaced by `parse_import`'s `;` check.
    function parse_import_modifiers(self) -> root.ast.ImportModifier[] throws unknown;

    /// dart-sass `_importSupportsQuery`: the content of an `@import ...
    /// supports(...)` modifier. Returns the condition and whether it was a bare
    /// declaration (`supports(a: b)`), whose serialization carries its own
    /// parens.
    function parse_import_supports_query(
        self,
    ) -> root.std.Tuple2<root.ast.SupportsCondition, bool> throws unknown;

    /// Parse `@warn`/`@debug`/`@error <expr>;`.
    function parse_message(
        self,
        kind: root.parser.MessageKind,
        pos: root.scanner.Pos,
        start_mark: root.scanner.Mark,
    ) -> root.ast.Stmt throws unknown;

    /// Parse `@extend <selector> [!optional];`. The selector is captured as a
    /// template (resolving `#{...}` at eval time); a trailing `!optional`
    /// suppresses the "didn't match" error.
    function parse_extend(self, pos: root.scanner.Pos) -> root.ast.Stmt throws unknown;

    // ---- @supports --------------------------------------------------
    /// Parse `@supports <condition> { body }`. The condition is parsed into a
    /// structured [`SupportsCondition`] (dart-sass grammar) so it serializes
    /// canonically and malformed conditions are rejected; the body bubbles like
    /// any at-rule.
    function parse_supports(self) -> root.ast.Stmt throws unknown;

    /// dart-sass `_supportsCondition`: an optional leading `not`, otherwise a
    /// condition-in-parens followed by a uniform `and`/`or` chain.
    function parse_supports_condition(self) -> root.ast.SupportsCondition throws unknown;

    /// dart-sass `_supportsConditionInParens`: a parenthesised condition, a
    /// function call, or a lone interpolation.
    function parse_supports_condition_in_parens(self) -> root.ast.SupportsCondition throws unknown;

    /// Parse the name expression of a `@supports` declaration: a space-/comma-
    /// separated SassScript expression that stops at a top-level `:` (dart-sass
    /// `_expression`). Unlike the general value grammar, a trailing `:` cleanly
    /// terminates the expression rather than erroring, so `(a /**/: b)` and
    /// `(a : b)` parse as declarations.
    function parse_supports_decl_name(self) -> root.ast.Expr throws unknown;

    /// dart-sass `_trySupportsOperation`: if a single-interpolation identifier
    /// is followed by `and`/`or`, parse the operation chain (`Ok`); otherwise
    /// restore the scanner position and return the identifier for reuse (`Err`).
    function try_supports_operation(
        self,
        identifier: root.ast.TplPiece[],
    ) -> root.std.Ok<root.ast.SupportsCondition> | root.std.Err<root.ast.TplPiece[]> throws unknown;

    /// dart-sass `_interpolatedDeclarationValue`, specialized for `@supports`
    /// (silent comments are dropped, loud comments kept; whitespace collapses;
    /// `#{…}` interpolation captured as template pieces). Stops at an unbalanced
    /// `)`/`}`/`]`, at `;` (unless `allow_semicolon`), at a top-level `:` (unless
    /// `allow_colon`), or at `{`. Errors "Expected token." when `!allow_empty`
    /// and nothing was read.
    function parse_supports_decl_value(
        self,
        allow_empty: bool,
        allow_semicolon: bool,
        allow_colon: bool,
    ) -> root.ast.TplPiece[] throws unknown;

    /// dart-sass `_lookingAtInterpolatedIdentifier`: whether the cursor begins
    /// an identifier (possibly with `#{…}` interpolation).
    function looking_at_interpolated_identifier(self) -> bool throws unknown;

    /// Whether the cursor begins a plain (non-interpolated) identifier — used to
    /// detect a trailing `and`/`or` keyword in a supports condition.
    function looking_at_plain_identifier(self) -> bool throws unknown;

    /// Parse a loud comment's body — the text after `/*`, consuming the closing
    /// `*/` — into template pieces so `#{…}` interpolation resolves at eval
    /// time. Literal text (including newlines) is preserved verbatim. An
    /// unterminated comment ends at EOF, matching dart-sass.
    function parse_loud_comment_body(self) -> root.ast.TplPiece[] throws unknown;

    /// dart-sass `interpolatedIdentifier`: an identifier with optional `#{…}`
    /// interpolation, returned as template pieces. Errors if no identifier.
    function parse_interpolated_identifier(self) -> root.ast.TplPiece[] throws unknown;

    /// Consume the body of an interpolated identifier (name chars, escapes,
    /// `#{…}`) into the given piece/literal accumulators.
    function interpolated_identifier_body(
        self,
        pieces: root.ast.TplPiece[],
        lit: root.std.StrBuf,
    ) -> void throws unknown;

    /// Scan a bare keyword (case-insensitive) when it stands as a complete
    /// identifier; on a match consume it and return true, else leave the
    /// position unchanged.
    function scan_keyword_ci(self, kw: string) -> bool throws unknown;

    /// Expect a bare keyword (case-insensitive); error in dart-sass's spelling
    /// (`Expected "and".`) when it doesn't match.
    function expect_keyword_ci(self, kw: string) -> void throws unknown;

    /// Parse `@at-root [query] { body }`. The optional query is the
    /// parenthesised `(with: …)` / `(without: …)` form; an inline selector
    /// (`@at-root .x { … }`) is desugared into a single rule inside the body.
    function parse_at_root(self) -> root.ast.Stmt throws unknown;

    /// Parse and validate the `@at-root (with: …)` / `(without: …)` query
    /// (the scanner is on the opening `(`), returning the reconstructed query
    /// template for eval. dart-sass requires `( "with"|"without" : <expr> )`:
    /// a bad keyword is `Expected "with" or "without".`, a missing colon
    /// `expected ":".`, an empty value `Expected expression.`, and a stray
    /// token (e.g. a comma in the value, or junk after `)`) errors in turn
    /// (`expected ")".` / `expected "{".`) — none are silently accepted.
    function parse_at_root_query(self) -> root.ast.TplPiece[] throws unknown;

    /// Parse `@keyframes <name> { from {…} 50% {…} … }`. The body is parsed as
    /// ordinary statements; each frame block classifies as a rule (its keyframe
    /// selector is terminated by `{`). Parent resolution is suppressed at eval
    /// time so the frame selectors emit verbatim.
    function parse_keyframes(self, name: string) -> root.ast.Stmt throws unknown;

    /// Parse a generic/unknown at-rule: `@name <prelude up to { ; or }>` then
    /// either a `{ … }` body or a terminating `;` (or an immediate `}` closing
    /// the enclosing block, as in `@page … {@g}`). Covers `@font-face`,
    /// `@page`, `@charset`, vendor `@foo`, and unknown directives.
    /// Parse the rest of an at-rule whose name contains interpolation:
    /// finish the name template, then a generic prelude and optional body.
    function parse_interp_at_rule(self, name: root.ast.TplPiece[]) -> root.ast.Stmt throws unknown;

    function parse_generic_at_rule(self, name: string) -> root.ast.Stmt throws unknown;

    // ---- @media -----------------------------------------------------
    /// Parse `@media <media-query-list> { body }`. The query is parsed into a
    /// structured form: a comma list of queries, each a media-type form
    /// (`[not|only]? <type> (and <cond>)*`) or a condition form (one or more
    /// parenthesised conditions joined by `and`/`or`). SassScript expressions
    /// inside feature values are kept as `Expr`s for eval-time resolution.
    /// Malformed queries are rejected, matching dart-sass.
    function parse_media(self) -> root.ast.Stmt throws unknown;

    /// Skip whitespace and `/* */` / `//` comments (allowed between media
    /// query tokens). Reports whether any whitespace or comment was consumed.
    function skip_media_ws(self) -> bool throws unknown;

    function parse_media_query_list(self) -> root.ast.MediaQueryList throws unknown;

    /// Parse one media query (dart-sass `_mediaQuery`).
    function parse_media_query(self) -> root.ast.MediaQuery throws unknown;

    /// After a leading condition, parse the rest of an `and`/`or` sequence.
    /// All conjunctions in one condition must match (no mixing `and`/`or`).
    function parse_media_logic_sequence(
        self,
        first: root.ast.MediaInParens,
    ) -> root.std.Tuple2<root.ast.MediaInParens[], root.ast.Conjunction> throws unknown;

    /// Parse one or more `and`-separated media-in-parens (used after a media
    /// type's `and`). `or` is not allowed here. The first operand may be a
    /// `not <media-in-parens>`, which terminates the query (no more conditions).
    function parse_media_and_conditions(self) -> root.ast.MediaInParens[] throws unknown;

    /// Parse a `_mediaOrInterp`: a raw `#{…}` interpolation operand or a single
    /// `(...)` media-in-parens.
    function parse_media_or_interp(self) -> root.ast.MediaInParens throws unknown;

    /// Parse a single media-in-parens (dart-sass `_mediaInParens`): `(feature)`,
    /// `(not <in-parens>)` → `not <in-parens>`, `((cond) and/or (cond)…)` group,
    /// or a raw `#{…}` interpolation operand.
    function parse_media_in_parens(self) -> root.ast.MediaInParens throws unknown;

    /// Whether the cursor is at a raw `not` keyword (used to start a nested
    /// `(not (...))` group).
    function media_at_not_keyword(self) -> bool throws unknown;

    /// Parse the interior of a single `(...)` media feature.
    function parse_media_feature(self) -> root.ast.MediaFeature throws unknown;

    /// Parse a comparison operator (`<`, `<=`, `>`, `>=`, `=`). The two-char
    /// forms may not contain whitespace (`< =` is rejected).
    function parse_media_comparison(self) -> string throws unknown;

    /// Parse a media-feature expression (a SassScript expression that stops
    /// before a top-level comparison operator: the additive level).
    function media_expression(self) -> root.ast.Expr throws unknown;

    /// The `and` level of [`Self::media_expression`], over additive operands.
    function media_and_chain(self) -> root.ast.Expr throws unknown;

    /// Parse an identifier/template that may include interpolation, used for a
    /// media modifier or type. Stops at whitespace, `,`, `(`, `{`, or `;`.
    function parse_media_identifier(self) -> root.ast.TplPiece[] throws unknown;

    /// Whether the cursor is positioned at the start of a media identifier
    /// (a letter, `-`, `_`, or interpolation) — used to distinguish a type
    /// from a following condition.
    function looking_at_media_identifier(self) -> bool throws unknown;

    /// Consume the bare keyword `kw` (`and`/`or`) if it is next as a whole
    /// identifier; restores the cursor and returns false otherwise. Matched
    /// case-insensitively.
    function try_media_keyword(self, kw: string) -> bool throws unknown;

    /// After a media `and`/`or`/`not` keyword, dart-sass requires whitespace
    /// (or a comment) before the next operand: `and(b)` is an error.
    function parse_media_keyword_whitespace(self) -> void throws unknown;

    /// Parse a `@function name(params) { … }` or `@mixin name(params) { … }`.
    function parse_callable_def(self, is_function: bool) -> root.ast.Stmt throws unknown;

    /// After a lowercase `@function`/`@mixin` keyword, peek whether the name
    /// that follows begins with `--` (a plain CSS custom function/mixin).
    function peek_callable_name_is_custom(self) -> bool throws unknown;

    /// Parse a plain CSS custom `@function`/`@mixin` (`keyword` is the literal
    /// at-rule name, e.g. `function`/`FUNCTION`/`mixin`). The prelude (the name,
    /// optional parameter list, and optional `returns <type>` clause) is
    /// captured as a template up to `{`; the body's top-level declarations keep
    /// their values verbatim. Only `#{...}` interpolation is resolved.
    function parse_css_custom_callable(self, keyword: string) -> root.ast.Stmt throws unknown;

    /// Parse the `{ … }` body of a plain CSS custom `@function`/`@mixin` after
    /// the `{` has been consumed, up to and including the matching `}`. Each
    /// top-level item is a declaration `property: value`. When the property is
    /// a plain literal the value is captured verbatim (a template); when it
    /// contains interpolation the value is parsed as SassScript.
    function parse_css_custom_body(self) -> root.ast.CssCustomItem[] throws unknown;

    /// Capture a verbatim CSS custom declaration value after the `:`, up to the
    /// terminating top-level `;` or `}`. Whitespace runs collapse to a single
    /// space (matching dart-sass serialization); `#{...}` interpolation is
    /// resolved; each closer is matched against the bracket it opened, so a
    /// braced value such as `{b: c}` is captured whole and `(]` is an error.
    /// The terminating `;` is consumed; a `}` is left for the body loop.
    function parse_css_custom_value(self) -> root.ast.TplPiece[] throws unknown;

    /// Capture a custom-property (`--name`) declaration value verbatim, from
    /// just after the colon up to the terminating top-level `;` or `}`. This
    /// mirrors dart-sass `_interpolatedDeclarationValue`: `#{…}` interpolation
    /// resolves *everywhere* (including inside strings), `//` and `/* */` are
    /// literal value characters (not comments), strings and `()`/`[]`/`{}` keep
    /// their delimiters, and whitespace runs collapse to a single space. The
    /// captured pieces are trimmed of surrounding whitespace; the terminating
    /// `;` is left for the caller.
    function parse_custom_property_value(self) -> root.ast.TplPiece[] throws unknown;

    /// Parse a declared parameter list `($a, $b: default, $rest...)`.
    /// Missing parentheses means no parameters.
    function parse_param_list(self) -> root.ast.ParamList throws unknown;

    /// Parse `@return <expr>;`.
    function parse_return(self) -> root.ast.Stmt throws unknown;

    /// Parse `@include name[(args)] [{ content }];`.
    function parse_include(
        self,
        pos: root.scanner.Pos,
        start_mark: root.scanner.Mark,
    ) -> root.ast.Stmt throws unknown;
}

implements ParserAtRules for root.parser.Parser {
    function parse_at_rule(self) -> root.ast.Stmt {
        let pos = self.sc.position();
        // Mark at the `@` so span-carrying at-rules (`@error`, `@include`) can
        // measure their byte length for the diagnostic caret.
        let start_mark = self.sc.mark();
        self.sc.bump(); // '@'
        // An interpolated NAME makes this a generic (unknown) at-rule with no
        // Sass parse-time behavior (`@#{"media"} …`).
        if (self.sc.peek() == "#" && self.sc.peek_at(1) == "{") {
            let stmt = self.parse_interp_at_rule([]);
            stamp_at_keyword(stmt, pos);
            return stmt;
        }
        let name = self.read_ident_name();
        if (self.sc.peek() == "#" && self.sc.peek_at(1) == "{") {
            let stmt = self.parse_interp_at_rule([root.ast.TplPiece_Lit { _0: name }]);
            stamp_at_keyword(stmt, pos);
            return stmt;
        }
        // In plain CSS the Sass control/definition at-rules are rejected; only
        // genuine CSS at-rules (`@media`, `@supports`, `@font-face`,
        // `@keyframes`, `@import`, `@charset`, `@page`, and unknown vendor
        // at-rules emitted verbatim) are allowed.
        if (self.plain_css) {
            // `@function --x`/`@mixin --x` are plain-CSS custom callables (the
            // `--` prefix), which CSS allows; a bare `@function`/`@mixin` is the
            // Sass definition and is rejected like the other control at-rules.
            let sass_callable = (name == "function" || name == "mixin") && !self.peek_callable_name_is_custom();
            let control = match (name) {
                "if" | "else" | "each" | "for" | "while" | "include" | "content" | "return" | "warn" | "debug" | "error" | "extend" | "at-root" | "use" | "forward" => true,
                _ => false,
            };
            if (sass_callable || control) {
                throw root.error.Error.at("This at-rule isn't allowed in plain CSS.", pos);
            }
        }
        let stmt: root.ast.Stmt = match (name) {
            "import" => self.parse_import(pos, start_mark),
            "if" => self.parse_if(),
            // A stray `@else` (one not consumed as part of an `@if` chain by
            // `parse_if`) is never valid on its own.
            "else" => throw root.error.Error.at("This at-rule is not allowed here.", pos),
            "for" => self.parse_for(),
            "each" => self.parse_each(),
            "while" => self.parse_while(),
            // Lowercase `@function`/`@mixin` define Sass callables — UNLESS the
            // name begins with `--`, which dart-sass reserves for plain CSS
            // custom functions/mixins (a function then passes through verbatim;
            // a mixin is a hard error).
            "function" if self.peek_callable_name_is_custom() => self.parse_css_custom_callable(name),
            "mixin" if self.peek_callable_name_is_custom() => throw root.error.Error.at(
                "Sass @mixin names beginning with -- are forbidden for forward-compatibility with plain CSS mixins.",
                pos,
            ),
            "function" => self.parse_callable_def(true),
            "mixin" => self.parse_callable_def(false),
            "return" => self.parse_return(),
            "include" => self.parse_include(pos, start_mark),
            "content" => {
                self.skip_ws_inline();
                let args: root.ast.CallArg[] = if (self.sc.peek() == "(") {
                    self.sc.bump();
                    self.parse_args_after_paren()
                } else {
                    []
                };
                self.skip_ws_inline();
                self.sc.eat(";");
                root.ast.Stmt_Content { args: args, pos: pos }
            },
            "warn" => self.parse_message(root.parser.MessageKind.Warn, pos, start_mark),
            "debug" => self.parse_message(root.parser.MessageKind.Debug, pos, start_mark),
            "error" => self.parse_message(root.parser.MessageKind.Error, pos, start_mark),
            "at-root" => self.parse_at_root(),
            "media" => self.parse_media(),
            "keyframes" | "-webkit-keyframes" | "-moz-keyframes" | "-o-keyframes" | "-ms-keyframes" => {
                self.parse_keyframes(name)
            },
            "extend" => self.parse_extend(pos),
            // `@charset` takes exactly one quoted string. A non-string (or
            // missing) argument is dart's "Expected string."; anything after
            // the string is left for the next statement (so `@charset "a" "b"`
            // fails as a malformed following rule, `expected "{".`). The value
            // itself is not emitted — the serializer re-derives `@charset` from
            // the output's own non-ASCII content.
            "charset" => {
                self.skip_ws_inline();
                let line = self.sc.position().line;
                if (!(self.sc.peek() == "\"" || self.sc.peek() == "'")) {
                    throw root.error.Error.at("Expected string.", self.sc.position());
                }
                let prelude: root.ast.TplPiece[] = [root.ast.TplPiece_Lit { _0: "\"" }];
                root.std.extend(prelude, self.parse_quoted_string());
                prelude.push(root.ast.TplPiece_Lit { _0: "\"" });
                self.skip_ws_inline();
                self.sc.eat(";");
                root.ast.Stmt_AtRule {
                    name: name,
                    prelude: prelude,
                    body: null,
                    lines: root.ast.SrcLines {
                        file: 0,
                        start: line,
                        end: line,
                        col: 0,
                        start_col: 0,
                        map_file: 0,
                        map_line: 0,
                    },
                }
            },
            "supports" => self.parse_supports(),
            "use" => self.parse_use(pos, start_mark),
            // @forward is parked for the module-system epic.
            "forward" => self.parse_forward(pos, start_mark),
            // A non-lowercase spelling of `@function`/`@mixin` (e.g. `@FUNCTION`,
            // `@Mixin`) is never a Sass definition; dart-sass parses it as a
            // plain CSS custom function/mixin (verbatim body), regardless of
            // whether the name begins with `--`.
            _ if root.std.eq_ignore_ascii_case(name, "function") || root.std.eq_ignore_ascii_case(name, "mixin") => {
                self.parse_css_custom_callable(name)
            },
            _ => self.parse_generic_at_rule(name),
        };
        stamp_at_keyword(stmt, pos);
        stmt
    }

    /// Parse `@import <arg> [, <arg>]* ;`. Each argument is either a Sass
    /// import (a bare quoted string with no modifiers and a non-CSS URL,
    /// which is inlined) or a plain CSS `@import` (a `url(...)` URL, a `.css`/
    /// protocol URL, or a URL followed by media-query/`supports()` modifiers,
    /// which is emitted verbatim).
    function parse_import(self, pos: root.scanner.Pos, start_mark: root.scanner.Mark) -> root.ast.Stmt {
        let args: root.ast.ImportArg[] = [];
        // Byte length of the rule from `@import` up to (not including) the
        // `;` — trailing whitespace included, which is how dart spans a
        // misplaced `@import "x"   ;` (verified against 1.103.1).
        // PORT: BAML has no deferred initialization; the loop always assigns it.
        let length = 0;
        while (true) {
            self.skip_ws_trivia();
            let arg = self.parse_import_arg(pos);
            args.push(arg);
            length = self.sc.byte_len_from(start_mark);
            self.skip_ws_trivia();
            if (self.sc.peek() == ",") {
                // Plain CSS `@import` takes a single URL — a comma-separated
                // list is a Sass-only feature.
                if (self.plain_css) {
                    throw root.error.Error.at("expected \";\".", self.sc.position());
                }
                self.sc.bump();
                continue;
            }
            break;
        }
        self.skip_ws_trivia();
        // After the last argument only `;`, `}`, or EOF may follow; anything
        // else (e.g. a supports()/identifier after a media query list, the
        // `wrong_order` cases) is a syntax error like dart-sass.
        match (self.sc.peek()) {
            null | ";" | "}" => {},
            _ => {
                throw root.error.Error.at("expected \";\".", self.sc.position());
            },
        }
        self.sc.eat(";");
        root.ast.Stmt_Import { args: args, pos: pos, length: length }
    }

    /// Parse `@use "<url>" [as <namespace>|as *];`. The URL is a quoted string
    /// without interpolation; an explicit `as ns` / `as *` overrides the
    /// default namespace (the segment after the last `/`, or after `sass:`).
    function parse_use(self, pos: root.scanner.Pos, start_mark: root.scanner.Mark) -> root.ast.Stmt {
        if (self.block_depth > 0) {
            throw root.error.Error.at("This at-rule is not allowed here.", pos);
        }
        // dart reads the whole rule before complaining about its placement, and
        // carets all of it — so the check waits for the length.
        let misplaced = self.seen_non_module_stmt;
        self.skip_ws_trivia();
        let url = self.parse_module_url(pos);
        self.skip_ws_trivia();
        let namespace: string? = null;
        let star = false;
        if (self.try_keyword("as")) {
            self.skip_ws_inline();
            if (self.sc.eat("*")) {
                star = true;
            } else {
                namespace = self.read_namespace_ident();
            }
            self.skip_ws_trivia();
        }
        // `with (...)` overrides the module's `!default` variables.
        let config: root.ast.ConfigEntry[] = [];
        if (self.try_keyword("with")) {
            config = self.parse_config_clause(pos);
        }
        // dart reports against everything before the `;`, including the
        // whitespace in front of it (`@use "x" with ($a: 1)   ;`).
        self.skip_ws_trivia();
        let length = self.sc.byte_len_from(start_mark);
        self.sc.eat(";");
        if (misplaced) {
            throw root.error.Error.at("@use rules must be written before any other rules.", pos).with_length(length);
        }
        root.ast.Stmt_Use {
            url: url,
            namespace: namespace,
            star: star,
            config: config,
            pos: pos,
            length: length,
        }
    }

    /// Parse `@forward "<url>" [as <prefix>-*] [show ...|hide ...] [with (...)];`.
    function parse_forward(self, pos: root.scanner.Pos, start_mark: root.scanner.Mark) -> root.ast.Stmt {
        if (self.block_depth > 0) {
            throw root.error.Error.at("This at-rule is not allowed here.", pos);
        }
        let misplaced = self.seen_non_module_stmt;
        self.skip_ws_trivia();
        let url = self.parse_module_url(pos);
        self.skip_ws_trivia();
        let prefix: string? = null;
        if (self.try_keyword("as")) {
            self.skip_ws_inline();
            let name = self.read_namespace_ident();
            if (!self.sc.eat("*")) {
                throw root.error.Error.at("expected \"*\".", self.sc.position());
            }
            prefix = name;
            self.skip_ws_trivia();
        }
        let show: root.ast.ForwardMember[]? = null;
        let hide: root.ast.ForwardMember[]? = null;
        if (self.try_keyword("show")) {
            show = self.parse_forward_members(pos);
            self.skip_ws_trivia();
        } else if (self.try_keyword("hide")) {
            hide = self.parse_forward_members(pos);
            self.skip_ws_trivia();
        }
        let config: root.ast.ConfigEntry[] = [];
        if (self.try_keyword("with")) {
            config = self.parse_config_clause(pos);
        }
        self.skip_ws_trivia();
        let length = self.sc.byte_len_from(start_mark);
        self.sc.eat(";");
        if (misplaced) {
            throw root.error.Error.at("@forward rules must be written before any other rules.", pos).with_length(length);
        }
        root.ast.Stmt_Forward {
            url: url,
            prefix: prefix,
            show: show,
            hide: hide,
            config: config,
            pos: pos,
            length: length,
        }
    }

    /// Parse a `with ( $name: value [!default], ... )` configuration clause.
    function parse_config_clause(self, pos: root.scanner.Pos) -> root.ast.ConfigEntry[] {
        self.skip_ws_trivia();
        if (!self.sc.eat("(")) {
            throw root.error.Error.at("expected \"(\".", self.sc.position());
        }
        let entries: root.ast.ConfigEntry[] = [];
        while (true) {
            self.skip_ws_trivia();
            if (self.sc.eat(")")) {
                break;
            }
            let entry_pos = self.sc.position();
            if (self.sc.peek() != "$") {
                throw root.error.Error.at("expected \"$\".", entry_pos);
            }
            self.sc.bump();
            let name = self.read_variable_name();
            self.skip_ws_trivia();
            if (!self.sc.eat(":")) {
                throw root.error.Error.at("expected \":\".", self.sc.position());
            }
            self.skip_ws_trivia();
            // A configuration value is a single (space-list) expression: a
            // comma is the entry separator, so a comma-list value needs parens.
            let value = self.space_list();
            let is_default = false;
            self.skip_ws_inline();
            if (self.sc.peek() == "!") {
                self.sc.bump();
                let flag = self.read_ident_name();
                if (flag == "default") {
                    is_default = true;
                } else {
                    throw root.error.Error.at("Invalid flag name.", entry_pos);
                }
            }
            entries.push(root.ast.ConfigEntry {
                name: name,
                value: value,
                is_default: is_default,
            });
            self.skip_ws_trivia();
            if (self.sc.eat(",")) {
                continue;
            }
            self.skip_ws_trivia();
            if (self.sc.eat(")")) {
                break;
            }
            throw root.error.Error.at("expected \")\".", self.sc.position());
        }
        let _ = pos;
        entries
    }

    /// Parse a `show`/`hide` member list: comma-separated identifiers and
    /// `$variable` names.
    function parse_forward_members(self, pos: root.scanner.Pos) -> root.ast.ForwardMember[] {
        let members: root.ast.ForwardMember[] = [];
        while (true) {
            self.skip_ws_trivia();
            if (self.sc.peek() == "$") {
                self.sc.bump();
                let name = self.read_variable_name();
                members.push(root.ast.ForwardMember_Var { _0: name });
            } else {
                let name = self.read_ident_name();
                members.push(root.ast.ForwardMember_Name { _0: name });
            }
            self.skip_ws_trivia();
            if (self.sc.eat(",")) {
                continue;
            }
            break;
        }
        if (members.length() == 0) {
            throw root.error.Error.at("Expected variable, mixin, or function name", pos);
        }
        members
    }

    /// Read a quoted module URL (no interpolation allowed) for `@use`/`@forward`.
    function parse_module_url(self, pos: root.scanner.Pos) -> string {
        match (self.sc.peek()) {
            "\"" | "'" => {
                let pieces = self.parse_quoted_string();
                let url = "";
                for (let p in pieces) {
                    match (p) {
                        let s: root.ast.TplPiece_Lit => {
                            url = url + s._0;
                        },
                        let _i: root.ast.TplPiece_Interp => {
                            throw root.error.Error.at("dynamic module URLs are not supported", pos);
                        },
                        _ => root.std.unreachable(),
                    }
                }
                url
            },
            _ => throw root.error.Error.at("expected a string.", pos),
        }
    }

    /// Skip whitespace and `/* */` / `//` comments (discarding them); used
    /// between the `@import` keyword, URLs, modifiers, and commas.
    function skip_ws_trivia(self) -> void {
        while (true) {
            match (self.sc.peek()) {
                let c: string if root.std.is_whitespace(c) => {
                    self.sc.bump();
                },
                "/" if self.sc.peek_at(1) == "/" => {
                    while let c: string = self.sc.peek() {
                        if (c == "\n") {
                            break;
                        }
                        self.sc.bump();
                    }
                },
                "/" if self.sc.peek_at(1) == "*" => {
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
                                break;
                            },
                            _ => {
                                self.sc.bump();
                            },
                        }
                    }
                },
                _ => {
                    break;
                },
            }
        }
    }

    /// Parse one `@import` argument and classify it as Sass or plain CSS.
    function parse_import_arg(self, pos: root.scanner.Pos) -> root.ast.ImportArg {
        // `url(...)` form — always a plain CSS import.
        if (self.peek_is_url_func()) {
            let url_pos = self.sc.position();
            let url = self.parse_import_url();
            self.skip_ws_trivia();
            let modifiers = self.parse_import_modifiers();
            return root.ast.ImportArg_Css {
                url: url,
                modifiers: modifiers,
                pos: url_pos,
            };
        }
        // The indented syntax allows an UNQUOTED URL (`@import foo, sub/bar`,
        // `@import other.css`). dart `SassParser.importArgument` reads it to
        // the next top-level comma or the end of the statement — SPACES
        // INCLUDED, so `@import foo screen` is one url `foo screen` (dart:
        // "Can't find stylesheet to import." pointing at all ten characters),
        // not a url plus a modifier. Only a quoted url takes modifiers.
        if (self.indented && !(self.sc.peek() == "\"" || self.sc.peek() == "'")) {
            let url_pos = self.sc.position();
            let raw = root.std.StrBuf.new();
            let has_interp = false;
            while let c: string = self.sc.peek() {
                // A CSS escape hides the character after it, so `\#{` is the
                // literal text `#{` — a STATIC path, as the quoted form reads
                // it — and an escaped comma is url text rather than a
                // separator.
                if (c == "\\") {
                    raw.push(c);
                    self.sc.bump();
                    let n = self.sc.peek();
                    if (n != null) {
                        raw.push(n);
                        self.sc.bump();
                    }
                    continue;
                }
                // `#{…}` is opaque: a comma inside it does not end the url.
                if (c == "#" && self.sc.peek_at(1) == "{") {
                    has_interp = true;
                    let depth = 0;
                    while let c: string = self.sc.peek() {
                        raw.push(c);
                        self.sc.bump();
                        match (c) {
                            "{" => {
                                depth += 1;
                            },
                            "}" => {
                                depth -= 1;
                                if (depth == 0) {
                                    break;
                                }
                            },
                            _ => {},
                        }
                    }
                    continue;
                }
                if (c == "," || c == ";" || c == "\n") {
                    break;
                }
                raw.push(c);
                self.sc.bump();
            }
            // Trailing whitespace before the `,`/`;` is not part of the url,
            // and the deprecation caret is sized from the trimmed token.
            let path = root.std.trim_end(raw.as_str());
            if (path == "") {
                throw root.error.Error.at("expected a string after @import", self.sc.position());
            }
            let url_len = path.byte_length();
            // A `.css`/protocol url is a plain-CSS import, emitted QUOTED with
            // its text verbatim — dart writes `@import "#{$x}o.css";`, leaving
            // even an interpolation unresolved.
            if (root.parser.import_url_is_css([root.ast.TplPiece_Lit { _0: path }])) {
                return root.ast.ImportArg_Css {
                    url: [root.ast.TplPiece_Lit { _0: root.value.serialize_quoted(path) }],
                    modifiers: [],
                    pos: url_pos,
                };
            }
            // A Sass import's path is static here, as in the quoted form —
            // an ESCAPED `\#{` is literal text and does not make it dynamic.
            if (has_interp) {
                throw root.error.Error.at("dynamic @import paths are not supported", pos);
            }
            return root.ast.ImportArg_Sass {
                path: path,
                pos: url_pos,
                length: url_len,
            };
        }
        // Quoted-string form.
        match (self.sc.peek()) {
            "\"" | "'" => {
                let url_pos = self.sc.position();
                let mark = self.sc.mark();
                let pieces = self.parse_quoted_string();
                let url_len = self.sc.byte_len_from(mark);
                let raw_url = self.sc.slice_from(mark);
                self.skip_ws_trivia();
                let modifiers = self.parse_import_modifiers();
                let css_url = root.parser.import_url_is_css(pieces);
                if (modifiers.length() == 0 && !css_url) {
                    // A bare Sass path. Reject interpolation (dynamic paths).
                    let path = "";
                    for (let p in pieces) {
                        match (p) {
                            let s: root.ast.TplPiece_Lit => {
                                path = path + s._0;
                            },
                            let _i: root.ast.TplPiece_Interp => {
                                throw root.error.Error.at("dynamic @import paths are not supported", pos);
                            },
                            _ => root.std.unreachable(),
                        }
                    }
                    root.ast.ImportArg_Sass {
                        path: path,
                        pos: url_pos,
                        length: url_len,
                    }
                } else {
                    root.ast.ImportArg_Css {
                        url: [root.ast.TplPiece_Lit { _0: raw_url }],
                        modifiers: modifiers,
                        pos: url_pos,
                    }
                }
            },
            _ => throw root.error.Error.at("expected a string after @import", self.sc.position()),
        }
    }

    /// Whether the cursor is at a `url(` function call — the name matched the
    /// way dart matches it, case-insensitively and with CSS escapes decoded
    /// (`u\72l(` IS `url(`). A vendor-prefixed spelling does NOT count here:
    /// dart rejects `@import -c-url(…)` with "Expected string.", unlike in a
    /// value position where `-c-url(` is a url token.
    function peek_is_url_func(self) -> bool {
        // PORT: decodes straight from the scanner's buffer at its cursor rather
        // than from a copied `rest()` tail, so `k` is an absolute index.
        let cs = self.sc.chars;
        let decoded = root.parser.decode_ident(cs, self.sc.pos);
        let name = decoded._0;
        let k = decoded._1;
        root.std.eq_ignore_ascii_case(name, "url") && cs.at(k) == "("
    }

    /// Read the `url(...)` argument of an `@import`, mirroring dart-sass
    /// `dynamicUrl`: the contents are tried as a plain URL token first — the
    /// same trial a url in a value position uses, so whitespace padding is
    /// dropped, escapes decode canonically and `#{…}` resolves — and when that
    /// fails (a quoted string, a `$variable`, whitespace in the MIDDLE of the
    /// token) the call is parsed as an ordinary function whose arguments
    /// evaluate, so `@import url($base + "x.css")` imports the computed url
    /// rather than emitting the SassScript verbatim.
    function parse_import_url(self) -> root.ast.TplPiece[] {
        let url_pos = self.sc.position();
        let name_mark = self.sc.mark();
        // The name is whatever spells `url` (`URL(`, `u\72l(`); step past it
        // and the `(`.
        // PORT: decoded from the scanner's buffer at its cursor (not a copied
        // `rest()` tail), then made relative to the cursor again.
        let name_len = root.parser.decode_ident(self.sc.chars, self.sc.pos)._1 - self.sc.pos;
        for (let _i in baml.iter.Range.new(0, name_len + 1)) {
            self.sc.bump();
        }
        let pieces = self.try_plain_url_contents();
        if (pieces != null) {
            return pieces;
        }
        self.sc.reset(name_mark);
        for (let _i in baml.iter.Range.new(0, name_len + 1)) {
            self.sc.bump();
        }
        let args = self.parse_args_after_paren();
        [root.ast.TplPiece_Interp {
            _0: root.ast.Expr_Func {
                // dart writes the canonical spelling, not the one in the source.
                name: "url",
                args: args,
                pos: url_pos,
                length: self.sc.byte_len_from(name_mark),
                module: null,
            },
        }]
    }

    /// Parse the optional modifiers that follow an `@import` URL, mirroring
    /// dart-sass `tryImportModifiers`: a run of bare identifiers and unknown
    /// functions (kept near-verbatim), at most interleaved `supports(<query>)`
    /// clauses (parsed structurally so they re-serialize canonically), then —
    /// terminally — a media query list, entered either at a `(`-feature or at
    /// a comma following a bare identifier (a media type). After the media
    /// list the modifiers END: a following `supports(...)`/identifier is a
    /// syntax error surfaced by `parse_import`'s `;` check.
    function parse_import_modifiers(self) -> root.ast.ImportModifier[] {
        let mods: root.ast.ImportModifier[] = [];
        // The current run of identifiers/unknown-functions, space-joined.
        let raw: root.ast.TplPiece[] = [];
        let flush = (raw: root.ast.TplPiece[], mods: root.ast.ImportModifier[]) -> void {
            if (raw.length() != 0) {
                mods.push(root.ast.ImportModifier_Raw { _0: root.std.take_all(raw) });
            }
        };
        let space = (raw: root.ast.TplPiece[]) -> void {
            if (raw.length() != 0) {
                if let s: root.ast.TplPiece_Lit = raw[raw.length() - 1] {
                    raw[raw.length() - 1] = root.ast.TplPiece_Lit { _0: `${s._0} ` };
                } else {
                    raw.push(root.ast.TplPiece_Lit { _0: " " });
                }
            }
        };
        while (true) {
            self.skip_ws_trivia();
            if (self.looking_at_interpolated_identifier()) {
                let identifier = self.parse_interpolated_identifier();
                let plain = root.parser.tpl_plain(identifier);
                let name: string? = if (plain != null) { root.std.ascii_lower(plain) } else { null };
                if (name != "and" && self.sc.peek() == "(") {
                    if (name == "supports") {
                        self.sc.bump(); // '('
                        flush(raw, mods);
                        let query = self.parse_import_supports_query();
                        let condition = query._0;
                        let declaration = query._1;
                        if (!self.sc.eat(")")) {
                            throw root.error.Error.at("expected \")\"", self.sc.position());
                        }
                        mods.push(root.ast.ImportModifier_Supports {
                            condition: condition,
                            declaration: declaration,
                        });
                    } else {
                        // Unknown function: `name(<declaration-value>)` verbatim.
                        self.sc.bump(); // '('
                        space(raw);
                        root.std.extend(raw, identifier);
                        root.parser.push_lit(raw, "(");
                        let args = self.parse_supports_decl_value(true, true, true);
                        root.std.extend(raw, args);
                        if (!self.sc.eat(")")) {
                            throw root.error.Error.at("expected \")\"", self.sc.position());
                        }
                        root.parser.push_lit(raw, ")");
                    }
                    continue;
                }
                // A bare identifier (or `and`).
                space(raw);
                root.std.extend(raw, identifier);
                self.skip_ws_trivia();
                if (self.sc.peek() == ",") {
                    // The identifier was a media type; the comma continues its
                    // media query LIST (only media queries may follow).
                    self.sc.bump();
                    flush(raw, mods);
                    let list = self.parse_media_query_list();
                    mods.push(root.ast.ImportModifier_Media {
                        list: list,
                        comma_before: true,
                    });
                    return mods;
                }
                continue;
            } else if (self.sc.peek() == "(") {
                // A media feature begins the terminal media query list.
                flush(raw, mods);
                let list = self.parse_media_query_list();
                mods.push(root.ast.ImportModifier_Media {
                    list: list,
                    comma_before: false,
                });
                return mods;
            } else {
                flush(raw, mods);
                return mods;
            }
        }
    }

    /// dart-sass `_importSupportsQuery`: the content of an `@import ...
    /// supports(...)` modifier. Returns the condition and whether it was a bare
    /// declaration (`supports(a: b)`), whose serialization carries its own
    /// parens.
    function parse_import_supports_query(self) -> root.std.Tuple2<root.ast.SupportsCondition, bool> {
        self.skip_ws_trivia();
        if (self.scan_keyword_ci("not")) {
            self.skip_ws_trivia();
            let inner = self.parse_supports_condition_in_parens();
            return root.std.Tuple2 { _0: root.ast.SupportsCondition_Negation { _0: inner }, _1: false };
        }
        if (self.sc.peek() == "(") {
            let condition = self.parse_supports_condition();
            let declaration = condition is root.ast.SupportsCondition_Declaration;
            return root.std.Tuple2 { _0: condition, _1: declaration };
        }
        // `name(<args>)` function form (e.g. `supports(calc(1))`).
        if (self.looking_at_interpolated_identifier()) {
            let mark = self.sc.mark();
            let identifier = self.parse_interpolated_identifier();
            if (self.sc.eat("(")) {
                let arguments = self.parse_supports_decl_value(true, true, true);
                if (!self.sc.eat(")")) {
                    throw root.error.Error.at("expected \")\"", self.sc.position());
                }
                return root.std.Tuple2 {
                    _0: root.ast.SupportsCondition_Function {
                        name: identifier,
                        arguments: arguments,
                    },
                    _1: false,
                };
            }
            self.sc.reset(mark);
        }
        // Bare declaration: `<name>: <value>`.
        let name = self.parse_supports_decl_name();
        self.skip_ws_trivia();
        if (!self.sc.eat(":")) {
            throw root.error.Error.at("expected \":\".", self.sc.position());
        }
        let custom = root.parser.expr_is_custom_property(name);
        let value: root.ast.SupportsValue = if (custom) {
            let raw = self.parse_supports_decl_value(false, false, true);
            root.ast.SupportsValue_Raw { _0: raw }
        } else {
            self.skip_ws_trivia();
            let v = self.parse_value();
            self.skip_ws_trivia();
            root.ast.SupportsValue_Expr { _0: v }
        };
        root.std.Tuple2 {
            _0: root.ast.SupportsCondition_Declaration {
                name: name,
                value: value,
                custom: custom,
            },
            _1: true,
        }
    }

    /// Parse `@warn`/`@debug`/`@error <expr>;`.
    function parse_message(self, kind: root.parser.MessageKind, pos: root.scanner.Pos, start_mark: root.scanner.Mark) -> root.ast.Stmt {
        self.skip_ws_inline();
        let value = self.parse_value();
        // Byte length of the `@error <expr>` span (from the `@` through the end
        // of the value, before the trailing `;`), for the diagnostic caret.
        let length = self.sc.byte_len_from(start_mark);
        self.skip_ws_inline();
        self.sc.eat(";");
        match (kind) {
            root.parser.MessageKind.Warn => root.ast.Stmt_Warn { value: value, pos: pos },
            root.parser.MessageKind.Debug => root.ast.Stmt_Debug { value: value, pos: pos },
            root.parser.MessageKind.Error => root.ast.Stmt_Error { value: value, pos: pos, length: length },
        }
    }

    /// Parse `@extend <selector> [!optional];`. The selector is captured as a
    /// template (resolving `#{...}` at eval time); a trailing `!optional`
    /// suppresses the "didn't match" error.
    function parse_extend(self, pos: root.scanner.Pos) -> root.ast.Stmt {
        self.skip_ws_inline();
        let selector = root.parser.trim_prelude(self.parse_template_mode(["!", ";", "}", "{"], root.parser.CommentMode.Strip));
        let optional = false;
        if (self.sc.peek() == "!") {
            self.sc.bump();
            self.skip_ws_inline();
            let flag = self.read_ident_name();
            if (!root.std.eq_ignore_ascii_case(flag, "optional")) {
                throw root.error.Error.at(`Invalid flag name: !${flag}`, pos);
            }
            optional = true;
        }
        self.skip_ws_inline();
        self.sc.eat(";");
        root.ast.Stmt_Extend {
            selector: selector,
            optional: optional,
            pos: pos,
        }
    }

    // ---- @supports --------------------------------------------------
    /// Parse `@supports <condition> { body }`. The condition is parsed into a
    /// structured [`SupportsCondition`] (dart-sass grammar) so it serializes
    /// canonically and malformed conditions are rejected; the body bubbles like
    /// any at-rule.
    function parse_supports(self) -> root.ast.Stmt {
        self.skip_ws_inline();
        let condition = self.parse_supports_condition();
        let body_lines = self.parse_braced_body_lines();
        let body = body_lines._0;
        let lines = body_lines._1;
        root.ast.Stmt_Supports {
            condition: condition,
            body: body,
            lines: lines,
        }
    }

    /// dart-sass `_supportsCondition`: an optional leading `not`, otherwise a
    /// condition-in-parens followed by a uniform `and`/`or` chain.
    function parse_supports_condition(self) -> root.ast.SupportsCondition {
        if (self.scan_keyword_ci("not")) {
            self.skip_ws_inline();
            let inner = self.parse_supports_condition_in_parens();
            return root.ast.SupportsCondition_Negation { _0: inner };
        }
        let condition: root.ast.SupportsCondition = self.parse_supports_condition_in_parens();
        self.skip_ws_inline();
        let operator: root.ast.Conjunction? = null;
        while (self.looking_at_plain_identifier()) {
            match (operator) {
                root.ast.Conjunction.And => {
                    self.expect_keyword_ci("and");
                },
                root.ast.Conjunction.Or => {
                    self.expect_keyword_ci("or");
                },
                null => {
                    if (self.scan_keyword_ci("or")) {
                        operator = root.ast.Conjunction.Or;
                    } else {
                        self.expect_keyword_ci("and");
                        operator = root.ast.Conjunction.And;
                    }
                },
            }
            self.skip_ws_inline();
            let right = self.parse_supports_condition_in_parens();
            condition = root.ast.SupportsCondition_Operation {
                left: condition,
                right: right,
                op: operator ?? root.ast.Conjunction.And,
            };
            self.skip_ws_inline();
        }
        condition
    }

    /// dart-sass `_supportsConditionInParens`: a parenthesised condition, a
    /// function call, or a lone interpolation.
    function parse_supports_condition_in_parens(self) -> root.ast.SupportsCondition {
        if (self.looking_at_interpolated_identifier()) {
            let pos = self.sc.position();
            let identifier = self.parse_interpolated_identifier();
            let plain = root.parser.tpl_plain(identifier);
            let is_not: bool? = if (plain != null) { root.std.eq_ignore_ascii_case(plain, "not") } else { null };
            if (is_not == true) {
                throw root.error.Error.at("\"not\" is not a valid identifier here.", pos);
            }
            if (self.sc.eat("(")) {
                let arguments = self.parse_supports_decl_value(true, true, true);
                if (!self.sc.eat(")")) {
                    throw root.error.Error.at("expected \")\"", self.sc.position());
                }
                return root.ast.SupportsCondition_Function {
                    name: identifier,
                    arguments: arguments,
                };
            } else if let expr: root.ast.Expr = root.parser.tpl_single_interp(identifier) {
                return root.ast.SupportsCondition_Interpolation { _0: expr };
            } else {
                throw root.error.Error.at("Expected @supports condition.", pos);
            }
        }

        let start = self.sc.position();
        if (!self.sc.eat("(")) {
            throw root.error.Error.at("expected \"(\"", start);
        }
        self.skip_ws_inline();
        if (self.scan_keyword_ci("not")) {
            self.skip_ws_inline();
            let condition = self.parse_supports_condition_in_parens();
            if (!self.sc.eat(")")) {
                throw root.error.Error.at("expected \")\"", self.sc.position());
            }
            return root.ast.SupportsCondition_Negation { _0: condition };
        } else if (self.sc.peek() == "(") {
            let condition = self.parse_supports_condition();
            if (!self.sc.eat(")")) {
                throw root.error.Error.at("expected \")\"", self.sc.position());
            }
            return condition;
        }

        // Backtracking branch: try `<expression> ":" <value>` (a declaration),
        // and on failure re-parse as an interpolated identifier followed either
        // by an `and`/`or` operation or by an arbitrary "anything" value.
        let name_mark = self.sc.mark();
        // PORT: `parsed: Result<Option<Expr>, Error>` — only `Ok(Some(name))` is
        // told apart below, so it is an `Expr?` (`null` = `Ok(None)` or `Err`).
        let decl_name: root.ast.Expr? = self.parse_supports_decl_name() catch (e) {
            let _err: root.error.Error => null
        };
        let parsed: root.ast.Expr? = null;
        if (decl_name != null) {
            self.skip_ws_inline();
            if (self.sc.eat(":")) {
                parsed = decl_name;
            }
        }
        if (parsed != null) {
            let name = parsed;
            let custom = root.parser.expr_is_custom_property(name);
            let value: root.ast.SupportsValue = if (custom) {
                // A custom-property value is captured verbatim.
                let raw = self.parse_supports_decl_value(false, false, true);
                root.ast.SupportsValue_Raw { _0: raw }
            } else {
                self.skip_ws_inline();
                let v = self.parse_value();
                // Consume any trailing whitespace/comments before `)`
                // (dart-sass `_expression` leaves the cursor at `)`).
                self.skip_ws_inline();
                root.ast.SupportsValue_Expr { _0: v }
            };
            if (!self.sc.eat(")")) {
                throw root.error.Error.at("expected \")\"", self.sc.position());
            }
            root.ast.SupportsCondition_Declaration {
                name: name,
                value: value,
                custom: custom,
            }
        } else {
            self.sc.reset(name_mark);
            let identifier = self.parse_interpolated_identifier();
            match (self.try_supports_operation(identifier)) {
                let ok: root.std.Ok<root.ast.SupportsCondition> => {
                    let op = ok.value;
                    if (!self.sc.eat(")")) {
                        throw root.error.Error.at("expected \")\"", self.sc.position());
                    }
                    op
                },
                let err: root.std.Err<root.ast.TplPiece[]> => {
                    let contents = err.error;
                    // Otherwise parse an `<anything>` value (forbidding a
                    // top-level colon: a colon there means this was meant to
                    // be a declaration, so we report the missing-`:` error).
                    let rest = self.parse_supports_decl_value(true, true, false);
                    root.std.extend(contents, rest);
                    if (self.sc.peek() == ":") {
                        throw root.error.Error.at("expected \":\".", self.sc.position());
                    }
                    if (!self.sc.eat(")")) {
                        throw root.error.Error.at("expected \")\"", self.sc.position());
                    }
                    root.ast.SupportsCondition_Anything { _0: contents }
                },
            }
        }
    }

    /// Parse the name expression of a `@supports` declaration: a space-/comma-
    /// separated SassScript expression that stops at a top-level `:` (dart-sass
    /// `_expression`). Unlike the general value grammar, a trailing `:` cleanly
    /// terminates the expression rather than erroring, so `(a /**/: b)` and
    /// `(a : b)` parse as declarations.
    function parse_supports_decl_name(self) -> root.ast.Expr {
        let commas: root.ast.Expr[] = [];
        while (true) {
            let spaces: root.ast.Expr[] = [self.or_expr()];
            while (true) {
                let mark = self.sc.mark();
                let had_ws = self.skip_ws_inline();
                // Stop the space-list before a top-level `:`, a `,`, or any
                // value terminator; require whitespace to continue otherwise.
                if (!had_ws || self.sc.peek() == ":" || self.at_value_terminator()) {
                    self.sc.reset(mark);
                    break;
                }
                spaces.push(self.or_expr());
            }
            let element: root.ast.Expr = if (spaces.length() == 1) {
                spaces.pop() ?? root.ast.Expr_Null {}
            } else {
                root.ast.Expr_List {
                    items: spaces,
                    sep: root.value.ListSep.Space,
                    bracketed: false,
                }
            };
            commas.push(element);
            let mark = self.sc.mark();
            self.skip_ws_inline();
            if (self.sc.peek() == ",") {
                self.sc.bump();
                self.skip_ws_inline();
                if (self.sc.peek() == ":" || self.at_value_terminator()) {
                    self.sc.reset(mark);
                    break;
                }
                continue;
            }
            self.sc.reset(mark);
            break;
        }
        if (commas.length() == 1) {
            commas.pop() ?? root.ast.Expr_Null {}
        } else {
            root.ast.Expr_List {
                items: commas,
                sep: root.value.ListSep.Comma,
                bracketed: false,
            }
        }
    }

    /// dart-sass `_trySupportsOperation`: if a single-interpolation identifier
    /// is followed by `and`/`or`, parse the operation chain (`Ok`); otherwise
    /// restore the scanner position and return the identifier for reuse (`Err`).
    function try_supports_operation(self, identifier: root.ast.TplPiece[]) -> root.std.Ok<root.ast.SupportsCondition> | root.std.Err<root.ast.TplPiece[]> {
        // PORT: `Result<Result<SupportsCondition, Vec<TplPiece>>, Error>` — the
        // outer `Err` is thrown; the inner result is an `Ok | Err` value.
        // Only a single-interpolation identifier can form an operation. Pull
        // the lone interpolation expression out; if it isn't one, give back the
        // identifier untouched.
        let expr: root.ast.Expr = if (identifier.length() == 1 && identifier[0] is root.ast.TplPiece_Interp) {
            match (identifier.pop()) {
                let i: root.ast.TplPiece_Interp => i._0,
                let other => {
                    // Unreachable given the guard above, but stay panic-free.
                    if (other != null) {
                        identifier.push(other);
                    }
                    return root.std.Err { error: identifier };
                },
            }
        } else {
            return root.std.Err { error: identifier };
        };

        let before_ws = self.sc.mark();
        self.skip_ws_inline();
        let operation: root.ast.SupportsCondition? = null;
        let left_expr: root.ast.Expr? = expr;
        let operator: root.ast.Conjunction? = null;
        while (self.looking_at_plain_identifier()) {
            match (operator) {
                root.ast.Conjunction.And => {
                    self.expect_keyword_ci("and");
                },
                root.ast.Conjunction.Or => {
                    self.expect_keyword_ci("or");
                },
                null => {
                    if (self.scan_keyword_ci("and")) {
                        operator = root.ast.Conjunction.And;
                    } else if (self.scan_keyword_ci("or")) {
                        operator = root.ast.Conjunction.Or;
                    } else {
                        self.sc.reset(before_ws);
                        // Reconstruct the single-interpolation identifier.
                        let e = left_expr ?? root.ast.Expr_Null {};
                        left_expr = null;
                        let pieces: root.ast.TplPiece[] = [root.ast.TplPiece_Interp { _0: e }];
                        return root.std.Err { error: pieces };
                    }
                },
            }
            self.skip_ws_inline();
            let right = self.parse_supports_condition_in_parens();
            // PORT: `operation.take()` / `left_expr.take()` spelled out.
            let taken = operation;
            operation = null;
            let left: root.ast.SupportsCondition = if (taken != null) {
                taken
            } else {
                let e = left_expr ?? root.ast.Expr_Null {};
                left_expr = null;
                root.ast.SupportsCondition_Interpolation { _0: e }
            };
            operation = root.ast.SupportsCondition_Operation {
                left: left,
                right: right,
                op: operator ?? root.ast.Conjunction.And,
            };
            self.skip_ws_inline();
        }
        if (operation != null) {
            root.std.Ok { value: operation }
        } else {
            let e = left_expr ?? root.ast.Expr_Null {};
            left_expr = null;
            let pieces: root.ast.TplPiece[] = [root.ast.TplPiece_Interp { _0: e }];
            root.std.Err { error: pieces }
        }
    }

    /// dart-sass `_interpolatedDeclarationValue`, specialized for `@supports`
    /// (silent comments are dropped, loud comments kept; whitespace collapses;
    /// `#{…}` interpolation captured as template pieces). Stops at an unbalanced
    /// `)`/`}`/`]`, at `;` (unless `allow_semicolon`), at a top-level `:` (unless
    /// `allow_colon`), or at `{`. Errors "Expected token." when `!allow_empty`
    /// and nothing was read.
    function parse_supports_decl_value(self, allow_empty: bool, allow_semicolon: bool, allow_colon: bool) -> root.ast.TplPiece[] {
        let start = self.sc.position();
        let pieces: root.ast.TplPiece[] = [];
        let lit = root.std.StrBuf.new();
        let brackets: string[] = [];
        // Whether the immediately-preceding source character was a newline
        // (dart-sass `wroteNewline`/`peekChar(-1).isNewline`): used to preserve
        // indentation and collapse consecutive newlines.
        let prev_newline = false;
        let wrote_anything = false;
        while let c: string = self.sc.peek() {
            match (c) {
                "\\" => {
                    // A hex escape is more than two characters, and dart
                    // re-serializes it canonically (`\\61 b` prints as `ab`).
                    let ch = self.read_escape_char();
                    root.parser.push_ident_escape(lit, ch, true);
                    prev_newline = false;
                    wrote_anything = true;
                },
                "\"" | "'" => {
                    lit.push(c);
                    self.sc.bump();
                    while (true) {
                        match (self.sc.peek()) {
                            null => {
                                break;
                            },
                            "\\" => {
                                lit.push("\\");
                                self.sc.bump();
                                let n = self.sc.bump();
                                if (n != null) {
                                    lit.push(n);
                                }
                            },
                            // Interpolation resolves inside a quoted string as
                            // well as outside it — the string's TEXT is
                            // verbatim, `#{…}` is not part of it.
                            "#" if self.sc.peek_at(1) == "{" => {
                                let interp_mark = self.sc.mark();
                                if (!lit.is_empty()) {
                                    pieces.push(root.parser.take_lit(lit));
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
                            },
                            let ch: string => {
                                lit.push(ch);
                                self.sc.bump();
                                if (ch == c) {
                                    break;
                                }
                            },
                        }
                    }
                    prev_newline = false;
                    wrote_anything = true;
                },
                "/" if self.sc.peek_at(1) == "*" => {
                    lit.push_str(self.consume_loud_comment());
                    prev_newline = false;
                    wrote_anything = true;
                },
                "/" if self.sc.peek_at(1) == "/" => {
                    self.consume_silent_comment();
                    prev_newline = false;
                },
                "#" if self.sc.peek_at(1) == "{" => {
                    let interp_mark = self.sc.mark();
                    if (!lit.is_empty()) {
                        pieces.push(root.parser.take_lit(lit));
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
                    prev_newline = false;
                    wrote_anything = true;
                },
                // PORT: Rust's explicit `' ' | '\t' | '\n' | '\r' | '\u{c}'` set
                // is exactly `is_ascii_whitespace`.
                " " | "\t" if !prev_newline && root.std.is_ascii_whitespace(self.sc.peek_at(1)) => {
                    // Collapse runs of whitespace to a single character, unless
                    // following a newline (then it's indentation, preserved).
                    self.sc.bump();
                },
                " " | "\t" => {
                    lit.push(c);
                    self.sc.bump();
                    wrote_anything = true;
                },
                "\n" | "\r" | "\f" => {
                    // Collapse multiple newlines into one.
                    if (!prev_newline) {
                        lit.push("\n");
                        wrote_anything = true;
                    }
                    self.sc.bump();
                    prev_newline = true;
                },
                "(" | "[" | "{" => {
                    // Open brackets are always pushed (dart-sass
                    // `allowOpenBrace` defaults true): a `@supports` value reader
                    // always lives inside `(...)`, so the at-rule body `{` is
                    // never reached here — it follows the unbalanced `)`.
                    self.sc.bump();
                    lit.push(c);
                    let closer = match (c) {
                        "(" => ")",
                        "[" => "]",
                        _ => "}",
                    };
                    brackets.push(closer);
                    prev_newline = false;
                    wrote_anything = true;
                },
                ")" | "]" | "}" => {
                    let expected = root.std.last(brackets);
                    if (expected == null) {
                        break;
                    }
                    if (c != expected) {
                        throw root.error.Error.at(`expected "${expected}".`, self.sc.position());
                    }
                    brackets.pop();
                    self.sc.bump();
                    lit.push(c);
                    prev_newline = false;
                    wrote_anything = true;
                },
                ";" => {
                    if (!allow_semicolon && brackets.length() == 0) {
                        break;
                    }
                    lit.push(c);
                    self.sc.bump();
                    prev_newline = false;
                    wrote_anything = true;
                },
                ":" => {
                    if (!allow_colon && brackets.length() == 0) {
                        break;
                    }
                    lit.push(c);
                    self.sc.bump();
                    prev_newline = false;
                    wrote_anything = true;
                },
                _ => {
                    lit.push(c);
                    self.sc.bump();
                    prev_newline = false;
                    wrote_anything = true;
                },
            }
        }
        let unclosed = root.std.last(brackets);
        if (unclosed != null) {
            throw root.error.Error.at(`expected "${unclosed}"`, self.sc.position());
        }
        if (!lit.is_empty()) {
            pieces.push(root.parser.take_lit(lit));
        }
        if (!allow_empty && !wrote_anything) {
            throw root.error.Error.at("Expected token.", start);
        }
        pieces
    }

    /// dart-sass `_lookingAtInterpolatedIdentifier`: whether the cursor begins
    /// an identifier (possibly with `#{…}` interpolation).
    function looking_at_interpolated_identifier(self) -> bool {
        match (self.sc.peek()) {
            null => false,
            "\\" => true,
            "#" => self.sc.peek_at(1) == "{",
            "-" => match (self.sc.peek_at(1)) {
                null => false,
                "#" => self.sc.peek_at(2) == "{",
                "-" | "\\" => true,
                let c: string => root.parser.is_name_start_codepoint(c),
            },
            let c: string => root.parser.is_name_start_codepoint(c),
        }
    }

    /// Whether the cursor begins a plain (non-interpolated) identifier — used to
    /// detect a trailing `and`/`or` keyword in a supports condition.
    function looking_at_plain_identifier(self) -> bool {
        match (self.sc.peek()) {
            "\\" => true,
            "-" => {
                match (self.sc.peek_at(1)) {
                    let c: string if root.parser.is_name_start_codepoint(c) || c == "-" || c == "\\" => true,
                    _ => false,
                }
            },
            let c: string => root.parser.is_name_start_codepoint(c),
            null => false,
        }
    }

    /// Parse a loud comment's body — the text after `/*`, consuming the closing
    /// `*/` — into template pieces so `#{…}` interpolation resolves at eval
    /// time. Literal text (including newlines) is preserved verbatim. An
    /// unterminated comment ends at EOF, matching dart-sass.
    function parse_loud_comment_body(self) -> root.ast.TplPiece[] {
        let pieces: root.ast.TplPiece[] = [];
        let lit = root.std.StrBuf.new();
        while (true) {
            match (self.sc.peek()) {
                null => {
                    break;
                },
                "*" if self.sc.peek_at(1) == "/" => {
                    self.sc.bump();
                    self.sc.bump();
                    break;
                },
                "#" if self.sc.peek_at(1) == "{" => {
                    let interp_mark = self.sc.mark();
                    if (!lit.is_empty()) {
                        pieces.push(root.parser.take_lit(lit));
                    }
                    self.sc.bump();
                    self.sc.bump();
                    let e = self.parse_value();
                    self.skip_ws_inline();
                    if (!self.sc.eat("}")) {
                        throw root.error.Error.at("expected \"}\".", self.sc.position());
                    }
                    self.reject_plain_css_interp(interp_mark);
                    pieces.push(root.ast.TplPiece_Interp { _0: e });
                },
                // CSS treats CR, FF, and CRLF as newlines inside a comment;
                // dart-sass normalizes them all to LF in the comment contents.
                let c: string if c == "\r" || c == "\f" => {
                    self.sc.bump();
                    if (c == "\r" && self.sc.peek() == "\n") {
                        self.sc.bump();
                    }
                    lit.push("\n");
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
        pieces
    }

    /// dart-sass `interpolatedIdentifier`: an identifier with optional `#{…}`
    /// interpolation, returned as template pieces. Errors if no identifier.
    function parse_interpolated_identifier(self) -> root.ast.TplPiece[] {
        let pieces: root.ast.TplPiece[] = [];
        let lit = root.std.StrBuf.new();
        // A leading `--` (custom-property-style) is always a valid start.
        if (self.sc.peek() == "-") {
            lit.push("-");
            self.sc.bump();
            if (self.sc.peek() == "-") {
                lit.push("-");
                self.sc.bump();
                self.interpolated_identifier_body(pieces, lit);
                if (!lit.is_empty()) {
                    pieces.push(root.parser.take_lit(lit));
                }
                return pieces;
            }
        }
        match (self.sc.peek()) {
            null => {
                throw root.error.Error.at("Expected identifier.", self.sc.position());
            },
            "\\" => {
                let ch = self.consume_escape();
                lit.push(ch);
            },
            "#" if self.sc.peek_at(1) == "{" => {
                let interp_mark = self.sc.mark();
                self.sc.bump();
                self.sc.bump();
                let e = self.parse_value();
                self.skip_ws_inline();
                if (!self.sc.eat("}")) {
                    throw root.error.Error.at("expected \"}\"", self.sc.position());
                }
                self.reject_plain_css_interp(interp_mark);
                if (!lit.is_empty()) {
                    pieces.push(root.parser.take_lit(lit));
                }
                pieces.push(root.ast.TplPiece_Interp { _0: e });
            },
            let c: string if root.parser.is_name_start_codepoint(c) => {
                lit.push(c);
                self.sc.bump();
            },
            _ => {
                throw root.error.Error.at("Expected identifier.", self.sc.position());
            },
        }
        self.interpolated_identifier_body(pieces, lit);
        if (!lit.is_empty()) {
            pieces.push(root.parser.take_lit(lit));
        }
        pieces
    }

    /// Consume the body of an interpolated identifier (name chars, escapes,
    /// `#{…}`) into the given piece/literal accumulators.
    function interpolated_identifier_body(self, pieces: root.ast.TplPiece[], lit: root.std.StrBuf) -> void {
        while (true) {
            match (self.sc.peek()) {
                let c: string if c == "_" || c == "-" || root.std.is_ascii_alphanumeric(c) || root.std.ord(c) >= 0x80 => {
                    lit.push(c);
                    self.sc.bump();
                },
                "\\" => {
                    let ch = self.consume_escape();
                    lit.push(ch);
                },
                "#" if self.sc.peek_at(1) == "{" => {
                    let interp_mark = self.sc.mark();
                    self.sc.bump();
                    self.sc.bump();
                    let e = self.parse_value();
                    self.skip_ws_inline();
                    if (!self.sc.eat("}")) {
                        throw root.error.Error.at("expected \"}\"", self.sc.position());
                    }
                    self.reject_plain_css_interp(interp_mark);
                    if (!lit.is_empty()) {
                        pieces.push(root.parser.take_lit(lit));
                    }
                    pieces.push(root.ast.TplPiece_Interp { _0: e });
                },
                _ => {
                    break;
                },
            }
        }
    }

    /// Scan a bare keyword (case-insensitive) when it stands as a complete
    /// identifier; on a match consume it and return true, else leave the
    /// position unchanged.
    function scan_keyword_ci(self, kw: string) -> bool {
        let mark = self.sc.mark();
        // PORT: reads the scanner's buffer from its cursor (`base`) instead of a
        // copied `rest()` tail; `i` stays relative to the cursor.
        let cs = self.sc.chars;
        let base = self.sc.pos;
        let i = 0;
        while (base + i < cs.length() && root.parser.is_ident_char(cs[base + i])) {
            i += 1;
        }
        let word = root.std.concat(cs.slice(base, base + i));
        if (root.std.eq_ignore_ascii_case(word, kw)) {
            for (let _i in baml.iter.Range.new(0, i)) {
                self.sc.bump();
            }
            true
        } else {
            self.sc.reset(mark);
            false
        }
    }

    /// Expect a bare keyword (case-insensitive); error in dart-sass's spelling
    /// (`Expected "and".`) when it doesn't match.
    function expect_keyword_ci(self, kw: string) -> void {
        if (self.scan_keyword_ci(kw)) {
            return;
        } else {
            throw root.error.Error.at(`Expected "${kw}".`, self.sc.position());
        }
    }

    /// Parse `@at-root [query] { body }`. The optional query is the
    /// parenthesised `(with: …)` / `(without: …)` form; an inline selector
    /// (`@at-root .x { … }`) is desugared into a single rule inside the body.
    function parse_at_root(self) -> root.ast.Stmt {
        self.skip_ws_inline();
        let query: root.ast.TplPiece[]? = if (self.sc.peek() == "(") {
            self.parse_at_root_query()
        } else if (self.sc.peek() == "{") {
            null
        } else {
            // The shorthand prelude is a SELECTOR; an at-rule there is
            // dart's "expected selector." (issue_238764 `@at-root @bar`).
            if (self.sc.peek() == "@") {
                throw root.error.Error.at("expected selector.", self.sc.position());
            }
            let selector_pos = self.sc.position();
            let selector = self.parse_template(["{"]);
            let body_lines = self.parse_braced_body_lines();
            let body = body_lines._0;
            let lines = body_lines._1;
            return root.ast.Stmt_AtRoot {
                query: null,
                body: [root.ast.Stmt_Rule {
                    _0: root.ast.Rule {
                        selector: selector,
                        body: body,
                        selector_pos: selector_pos,
                        selector_interp_spans: [],
                        brace_line: lines.start,
                        end_line: lines.end,
                    },
                }],
            };
        };
        // Whitespace / comments / newlines may sit between a `(…)` query (or
        // the bare `@at-root`) and the body block.
        self.skip_ws_trivia();
        let body = self.parse_braced_body();
        root.ast.Stmt_AtRoot { query: query, body: body }
    }

    /// Parse and validate the `@at-root (with: …)` / `(without: …)` query
    /// (the scanner is on the opening `(`), returning the reconstructed query
    /// template for eval. dart-sass requires `( "with"|"without" : <expr> )`:
    /// a bad keyword is `Expected "with" or "without".`, a missing colon
    /// `expected ":".`, an empty value `Expected expression.`, and a stray
    /// token (e.g. a comma in the value, or junk after `)`) errors in turn
    /// (`expected ")".` / `expected "{".`) — none are silently accepted.
    function parse_at_root_query(self) -> root.ast.TplPiece[] {
        self.sc.bump(); // '('
        self.skip_ws_inline();
        let kw_pos = self.sc.position();
        let kw = self.read_ident_name() catch (e) {
            let _err: root.error.Error => ""
        };
        if (!root.std.eq_ignore_ascii_case(kw, "with") && !root.std.eq_ignore_ascii_case(kw, "without")) {
            throw root.error.Error.at("Expected \"with\" or \"without\".", kw_pos);
        }
        self.skip_ws_inline();
        if (!self.sc.eat(":")) {
            throw root.error.Error.at("expected \":\".", self.sc.position());
        }
        self.skip_ws_inline();
        let value_pos = self.sc.position();
        // The value is a space-separated expression; a top-level comma ends it
        // and then dart expects `)` (`(with: rule, media)` → `expected ")".`).
        let value = self.parse_template([")", ","]);
        if (value.every((p: root.ast.TplPiece) -> bool {
            match (p) {
                let s: root.ast.TplPiece_Lit => root.std.trim(s._0) == "",
                _ => false,
            }
        })) {
            throw root.error.Error.at("Expected expression.", value_pos);
        }
        if (!self.sc.eat(")")) {
            throw root.error.Error.at("expected \")\".", self.sc.position());
        }
        let pieces: root.ast.TplPiece[] = [root.ast.TplPiece_Lit { _0: `(${kw}: ` }];
        root.std.extend(pieces, root.parser.trim_prelude(value));
        pieces.push(root.ast.TplPiece_Lit { _0: ")" });
        pieces
    }

    /// Parse `@keyframes <name> { from {…} 50% {…} … }`. The body is parsed as
    /// ordinary statements; each frame block classifies as a rule (its keyframe
    /// selector is terminated by `{`). Parent resolution is suppressed at eval
    /// time so the frame selectors emit verbatim.
    function parse_keyframes(self, name: string) -> root.ast.Stmt {
        self.skip_ws_inline();
        let prelude = root.parser.trim_prelude(self.parse_template(["{"]));
        let body_lines = self.parse_braced_body_lines();
        let body = body_lines._0;
        let lines = body_lines._1;
        root.ast.Stmt_Keyframes {
            name: name,
            prelude: prelude,
            body: body,
            lines: lines,
        }
    }

    /// Parse a generic/unknown at-rule: `@name <prelude up to { ; or }>` then
    /// either a `{ … }` body or a terminating `;` (or an immediate `}` closing
    /// the enclosing block, as in `@page … {@g}`). Covers `@font-face`,
    /// `@page`, `@charset`, vendor `@foo`, and unknown directives.
    /// Parse the rest of an at-rule whose name contains interpolation:
    /// finish the name template, then a generic prelude and optional body.
    function parse_interp_at_rule(self, name: root.ast.TplPiece[]) -> root.ast.Stmt {
        while (true) {
            if (self.sc.peek() == "#" && self.sc.peek_at(1) == "{") {
                let interp_mark = self.sc.mark();
                self.sc.bump();
                self.sc.bump();
                self.skip_ws_inline();
                let e = self.parse_value();
                self.skip_ws_inline();
                if (!self.sc.eat("}")) {
                    throw root.error.Error.at("expected \"}\"", self.sc.position());
                }
                self.reject_plain_css_interp(interp_mark);
                name.push(root.ast.TplPiece_Interp { _0: e });
                continue;
            }
            match (self.sc.peek()) {
                let c: string if root.parser.is_ident_char(c) => {
                    let lit = self.read_ident_name();
                    name.push(root.ast.TplPiece_Lit { _0: lit });
                }
                _ => {
                    break;
                }
            }
        }
        self.skip_ws_inline();
        let prelude = root.parser.trim_prelude(self.parse_template_mode(["{", ";", "}"], root.parser.CommentMode.UnknownPrelude));
        self.skip_ws_inline();
        let body_lines: root.std.Tuple2<root.ast.Stmt[]?, root.ast.SrcLines> = if (self.sc.peek() == "{") {
            let bl = self.parse_braced_body_lines();
            root.std.Tuple2 { _0: bl._0, _1: bl._1 }
        } else {
            self.sc.eat(";");
            // The `;` form: the statement starts and ends on the `;` line.
            let line = self.sc.position().line;
            root.std.Tuple2 {
                _0: null,
                _1: root.ast.SrcLines {
                    file: 0,
                    start: line,
                    end: line,
                    col: 0,
                    start_col: 0,
                    map_file: 0,
                    map_line: 0,
                },
            }
        };
        let body = body_lines._0;
        let lines = body_lines._1;
        root.ast.Stmt_InterpAtRule {
            name: name,
            prelude: prelude,
            body: body,
            lines: lines,
        }
    }

    function parse_generic_at_rule(self, name: string) -> root.ast.Stmt {
        self.skip_ws_inline();
        // dart-sass parses `@-moz-document` (only the exact lowercase spelling)
        // with a structured grammar that strips trivia comments between tokens;
        // every other at-rule keeps loud comments verbatim and treats silent
        // comments as whitespace. (`@supports` has its own dedicated parser.)
        let comment_mode: root.parser.CommentMode = if (name == "-moz-document") {
            root.parser.CommentMode.StripTopLevel
        } else {
            root.parser.CommentMode.UnknownPrelude
        };
        let prelude = self.parse_template_mode(["{", ";", "}"], comment_mode);
        let prelude = root.parser.trim_prelude(prelude);
        self.skip_ws_inline();
        let body_lines: root.std.Tuple2<root.ast.Stmt[]?, root.ast.SrcLines> = if (self.sc.peek() == "{") {
            let bl = self.parse_braced_body_lines();
            root.std.Tuple2 { _0: bl._0, _1: bl._1 }
        } else {
            self.sc.eat(";");
            // The `;` form: the statement starts and ends on the `;` line.
            let line = self.sc.position().line;
            root.std.Tuple2 {
                _0: null,
                _1: root.ast.SrcLines {
                    file: 0,
                    start: line,
                    end: line,
                    col: 0,
                    start_col: 0,
                    map_file: 0,
                    map_line: 0,
                },
            }
        };
        let body = body_lines._0;
        let lines = body_lines._1;
        root.ast.Stmt_AtRule {
            name: name,
            prelude: prelude,
            body: body,
            lines: lines,
        }
    }

    // ---- @media -----------------------------------------------------
    /// Parse `@media <media-query-list> { body }`. The query is parsed into a
    /// structured form: a comma list of queries, each a media-type form
    /// (`[not|only]? <type> (and <cond>)*`) or a condition form (one or more
    /// parenthesised conditions joined by `and`/`or`). SassScript expressions
    /// inside feature values are kept as `Expr`s for eval-time resolution.
    /// Malformed queries are rejected, matching dart-sass.
    function parse_media(self) -> root.ast.Stmt {
        let query = self.parse_media_query_list();
        let body_lines = self.parse_braced_body_lines();
        let body = body_lines._0;
        let lines = body_lines._1;
        root.ast.Stmt_Media { query: query, body: body, lines: lines }
    }

    /// Skip whitespace and `/* */` / `//` comments (allowed between media
    /// query tokens). Reports whether any whitespace or comment was consumed.
    function skip_media_ws(self) -> bool {
        let any = false;
        while (true) {
            match (self.sc.peek()) {
                let c: string if c.is_whitespace() => {
                    self.sc.bump();
                    any = true;
                }
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
                }
                "/" if self.sc.peek_at(1) == "/" => {
                    while let c: string = self.sc.peek() {
                        if (c == "\n") {
                            break;
                        }
                        self.sc.bump();
                    }
                    any = true;
                }
                _ => {
                    break;
                }
            }
        }
        any
    }

    function parse_media_query_list(self) -> root.ast.MediaQueryList {
        let queries: root.ast.MediaQuery[] = [];
        while (true) {
            self.skip_media_ws();
            queries.push(self.parse_media_query());
            self.skip_media_ws();
            if (self.sc.eat(",")) {
                continue;
            }
            break;
        }
        root.ast.MediaQueryList { queries: queries }
    }

    /// Parse one media query (dart-sass `_mediaQuery`).
    function parse_media_query(self) -> root.ast.MediaQuery {
        // Condition-only form: a leading `(` (a media-in-parens).
        if (self.sc.peek() == "(") {
            let first = self.parse_media_in_parens();
            let seq = self.parse_media_logic_sequence(first);
            let conditions = seq._0;
            let conjunction = seq._1;
            return root.ast.MediaQuery_Condition {
                conditions: conditions,
                conjunction: conjunction,
            };
        }

        let ident1 = self.parse_media_identifier();
        // `not (...)` → condition form (only when `not` is a raw keyword and a
        // media-in-parens follows rather than another identifier). dart-sass
        // requires whitespace after `not`.
        if (root.parser.media_ident_is(ident1, "not")) {
            self.parse_media_keyword_whitespace();
            if (!self.looking_at_media_identifier()) {
                let inner = self.parse_media_or_interp();
                let first = root.ast.MediaInParens_Not { _0: inner };
                let seq = self.parse_media_logic_sequence(first);
                let conditions = seq._0;
                let conjunction = seq._1;
                return root.ast.MediaQuery_Condition {
                    conditions: conditions,
                    conjunction: conjunction,
                };
            }
        }
        self.skip_media_ws();
        if (!self.looking_at_media_identifier()) {
            // `@media screen { … }` — bare media type.
            return root.ast.MediaQuery_Type {
                modifier: null,
                mtype: ident1,
                conditions: [],
            };
        }
        let ident2 = self.parse_media_identifier();
        let modifier_mtype: root.std.Tuple2<root.ast.TplPiece[]?, root.ast.TplPiece[]> = if (root.parser.media_ident_is(ident2, "and")) {
            // `@media screen and …` — ident1 is the type, "and" begins the
            // condition sequence.
            root.std.Tuple2 { _0: null, _1: ident1 }
        } else {
            self.skip_media_ws();
            // `@media only screen [and …]` — ident1 is the modifier (kept as
            // a template verbatim: it may contain interpolation, and dart
            // preserves its original case).
            let modifier: root.ast.TplPiece[]? = ident1;
            if (!self.try_media_keyword("and")) {
                return root.ast.MediaQuery_Type {
                    modifier: modifier,
                    mtype: ident2,
                    conditions: [],
                };
            }
            root.std.Tuple2 { _0: modifier, _1: ident2 }
        };
        let modifier = modifier_mtype._0;
        let mtype = modifier_mtype._1;
        // We have consumed `and`; parse the condition sequence (and-only).
        let conditions = self.parse_media_and_conditions();
        root.ast.MediaQuery_Type {
            modifier: modifier,
            mtype: mtype,
            conditions: conditions,
        }
    }

    /// After a leading condition, parse the rest of an `and`/`or` sequence.
    /// All conjunctions in one condition must match (no mixing `and`/`or`).
    function parse_media_logic_sequence(self, first: root.ast.MediaInParens) -> root.std.Tuple2<root.ast.MediaInParens[], root.ast.Conjunction> {
        let conditions: root.ast.MediaInParens[] = [first];
        let conjunction: root.ast.Conjunction = root.ast.Conjunction.And;
        let chosen: root.ast.Conjunction? = null;
        while (true) {
            let mark = self.sc.mark();
            self.skip_media_ws();
            let next: root.ast.Conjunction = if (self.try_media_keyword("and")) {
                root.ast.Conjunction.And
            } else if (self.try_media_keyword("or")) {
                root.ast.Conjunction.Or
            } else {
                self.sc.reset(mark);
                break;
            };
            if let prev: root.ast.Conjunction = chosen {
                if (prev != next) {
                    throw root.error.Error.at("expected \"{\".", self.sc.position());
                }
            }
            chosen = next;
            conjunction = next;
            self.parse_media_keyword_whitespace();
            conditions.push(self.parse_media_or_interp());
        }
        root.std.Tuple2 { _0: conditions, _1: conjunction }
    }

    /// Parse one or more `and`-separated media-in-parens (used after a media
    /// type's `and`). `or` is not allowed here. The first operand may be a
    /// `not <media-in-parens>`, which terminates the query (no more conditions).
    function parse_media_and_conditions(self) -> root.ast.MediaInParens[] {
        self.parse_media_keyword_whitespace();
        // `<type> and not (<feature>)` — a single negated condition, nothing
        // may follow it (matching dart-sass).
        if (self.try_media_keyword("not")) {
            self.parse_media_keyword_whitespace();
            let inner = self.parse_media_or_interp();
            return [root.ast.MediaInParens_Not { _0: inner }];
        }
        let conditions: root.ast.MediaInParens[] = [self.parse_media_or_interp()];
        while (true) {
            let mark = self.sc.mark();
            self.skip_media_ws();
            if (self.try_media_keyword("and")) {
                self.parse_media_keyword_whitespace();
                conditions.push(self.parse_media_or_interp());
            } else if (self.try_media_keyword("or")) {
                // `or` after a media type's `and` chain is invalid.
                throw root.error.Error.at("expected \"{\".", self.sc.position());
            } else {
                self.sc.reset(mark);
                break;
            }
        }
        conditions
    }

    /// Parse a `_mediaOrInterp`: a raw `#{…}` interpolation operand or a single
    /// `(...)` media-in-parens.
    function parse_media_or_interp(self) -> root.ast.MediaInParens {
        self.skip_media_ws();
        if (self.sc.peek() == "#" && self.sc.peek_at(1) == "{") {
            let interp_mark = self.sc.mark();
            self.sc.bump();
            self.sc.bump();
            let e = self.parse_value();
            self.skip_ws_inline();
            if (!self.sc.eat("}")) {
                throw root.error.Error.at("expected \"}\"", self.sc.position());
            }
            self.reject_plain_css_interp(interp_mark);
            return root.ast.MediaInParens_Interp { _0: e };
        }
        self.parse_media_in_parens()
    }

    /// Parse a single media-in-parens (dart-sass `_mediaInParens`): `(feature)`,
    /// `(not <in-parens>)` → `not <in-parens>`, `((cond) and/or (cond)…)` group,
    /// or a raw `#{…}` interpolation operand.
    function parse_media_in_parens(self) -> root.ast.MediaInParens {
        self.skip_media_ws();
        // A raw interpolation operand is spliced verbatim.
        if (self.sc.peek() == "#" && self.sc.peek_at(1) == "{") {
            let interp_mark = self.sc.mark();
            self.sc.bump();
            self.sc.bump();
            let e = self.parse_value();
            self.skip_ws_inline();
            if (!self.sc.eat("}")) {
                throw root.error.Error.at("expected \"}\"", self.sc.position());
            }
            self.reject_plain_css_interp(interp_mark);
            return root.ast.MediaInParens_Interp { _0: e };
        }
        if (!self.sc.eat("(")) {
            throw root.error.Error.at(
                "expected media condition in parentheses.",
                self.sc.position(),
            );
        }
        self.skip_media_ws();
        // `(not (...))` → `not (...)`: the wrapping parens are dropped.
        if (self.media_at_not_keyword()) {
            self.parse_media_identifier(); // consume "not"
            self.parse_media_keyword_whitespace();
            let inner = self.parse_media_in_parens();
            self.skip_media_ws();
            if (!self.sc.eat(")")) {
                throw root.error.Error.at("expected \")\".", self.sc.position());
            }
            return root.ast.MediaInParens_Not { _0: inner };
        }
        // Nested parens → a sub-condition group, kept wrapped.
        if (self.sc.peek() == "(") {
            let first = self.parse_media_in_parens();
            let seq = self.parse_media_logic_sequence(first);
            let conditions = seq._0;
            let conjunction = seq._1;
            self.skip_media_ws();
            if (!self.sc.eat(")")) {
                throw root.error.Error.at("expected \")\".", self.sc.position());
            }
            return root.ast.MediaInParens_Group {
                conditions: conditions,
                conjunction: conjunction,
            };
        }
        // Otherwise a media feature: `<expr> [: <expr> | <op> <expr> [<op> <expr>]]`.
        let feature = self.parse_media_feature();
        self.skip_media_ws();
        if (!self.sc.eat(")")) {
            throw root.error.Error.at("expected \")\".", self.sc.position());
        }
        root.ast.MediaInParens_Feature { _0: feature }
    }

    /// Whether the cursor is at a raw `not` keyword (used to start a nested
    /// `(not (...))` group).
    function media_at_not_keyword(self) -> bool {
        let i = 0;
        let word = "";
        while let c: string = self.sc.peek_at(i) {
            if (root.parser.is_ident_char(c)) {
                word = word + c;
                i += 1;
            } else {
                break;
            }
        }
        root.std.eq_ignore_ascii_case(word, "not")
    }

    /// Parse the interior of a single `(...)` media feature.
    function parse_media_feature(self) -> root.ast.MediaFeature {
        let first = self.media_expression();
        self.skip_media_ws();
        match (self.sc.peek()) {
            ":" => {
                self.sc.bump();
                self.skip_media_ws();
                let value = self.parse_value();
                root.ast.MediaFeature_Decl {
                    name: first,
                    value: value,
                }
            }
            "<" | ">" | "=" => {
                let op1 = self.parse_media_comparison();
                self.skip_media_ws();
                let second = self.media_expression();
                self.skip_media_ws();
                let rest: root.std.Tuple2<string, root.ast.Expr>? = match (self.sc.peek()) {
                    "<" | ">" | "=" => {
                        let op2 = self.parse_media_comparison();
                        // A range must use a consistent direction. `=` may not
                        // be the second operator either.
                        if (!root.parser.range_ops_compatible(op1, op2)) {
                            throw root.error.Error.at("expected \")\".", self.sc.position());
                        }
                        self.skip_media_ws();
                        let third = self.media_expression();
                        self.skip_media_ws();
                        // A third comparison operator is invalid.
                        let after = self.sc.peek();
                        if (after == "<" || after == ">" || after == "=") {
                            throw root.error.Error.at("expected \")\".", self.sc.position());
                        }
                        root.std.Tuple2 { _0: op2, _1: third }
                    }
                    _ => null,
                };
                root.ast.MediaFeature_Range {
                    first: first,
                    op1: op1,
                    second: second,
                    rest: rest,
                }
            }
            _ => root.ast.MediaFeature_Decl {
                name: first,
                value: null,
            },
        }
    }

    /// Parse a comparison operator (`<`, `<=`, `>`, `>=`, `=`). The two-char
    /// forms may not contain whitespace (`< =` is rejected).
    function parse_media_comparison(self) -> string {
        match (self.sc.peek()) {
            "=" => {
                self.sc.bump();
                "="
            }
            "<" | ">" => {
                let c = self.sc.bump() ?? "<";
                if (self.sc.peek() == "=") {
                    self.sc.bump();
                    `${c}=`
                } else {
                    c
                }
            }
            _ => {
                throw root.error.Error.at("Expected expression.", self.sc.position());
            }
        }
    }

    /// Parse a media-feature expression (a SassScript expression that stops
    /// before a top-level comparison operator: the additive level).
    function media_expression(self) -> root.ast.Expr {
        self.skip_media_ws();
        // `=` directly here (e.g. after `<` with a space) is invalid.
        if (self.sc.peek() == "=") {
            throw root.error.Error.at("Expected expression.", self.sc.position());
        }
        // dart `_expressionUntilComparison`: a full SassScript expression
        // stopping at `<`, `>`, or a single `=` — `(screen and (color))`
        // evaluates as ONE boolean expression (issue_485: `and` returns its
        // second operand, so the feature renders `(color)`), while range
        // syntax `(width > 0)` still leaves the comparison to the media
        // grammar (the additive operand never consumes those).
        let lhs = self.media_and_chain();
        while (true) {
            let mark = self.sc.mark();
            self.skip_ws_inline();
            if (!self.plain_css && self.try_keyword("or")) {
                self.skip_ws_inline();
                let pos = self.sc.position();
                let rhs = self.media_and_chain();
                lhs = root.ast.Expr_Binary {
                    op: root.ast.BinOp.Or,
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

    /// The `and` level of [`Self::media_expression`], over additive operands.
    function media_and_chain(self) -> root.ast.Expr {
        let lhs = self.additive();
        while (true) {
            let mark = self.sc.mark();
            self.skip_ws_inline();
            if (!self.plain_css && self.try_keyword("and")) {
                self.skip_ws_inline();
                let pos = self.sc.position();
                let rhs = self.additive();
                lhs = root.ast.Expr_Binary {
                    op: root.ast.BinOp.And,
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

    /// Parse an identifier/template that may include interpolation, used for a
    /// media modifier or type. Stops at whitespace, `,`, `(`, `{`, or `;`.
    function parse_media_identifier(self) -> root.ast.TplPiece[] {
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
                    let e = self.parse_value();
                    self.skip_ws_inline();
                    if (!self.sc.eat("}")) {
                        throw root.error.Error.at("expected \"}\"", self.sc.position());
                    }
                    self.reject_plain_css_interp(interp_mark);
                    pieces.push(root.ast.TplPiece_Interp { _0: e });
                }
                let c: string if root.parser.is_ident_char(c) => {
                    lit.push(c);
                    self.sc.bump();
                }
                // A media type/modifier may carry identifier escapes
                // (`@media screen\9`); decode and re-serialize canonically
                // (`screen\9 ` keeps the escape's terminating space).
                "\\" => {
                    let at_start = lit.is_empty() && pieces.length() == 0;
                    let c = self.read_escape_char();
                    root.parser.push_ident_escape(lit, c, at_start);
                }
                _ => {
                    break;
                }
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

    /// Whether the cursor is positioned at the start of a media identifier
    /// (a letter, `-`, `_`, or interpolation) — used to distinguish a type
    /// from a following condition.
    function looking_at_media_identifier(self) -> bool {
        match (self.sc.peek()) {
            "#" if self.sc.peek_at(1) == "{" => true,
            let c: string => c.is_ascii_alphabetic() || c == "-" || c == "_",
            null => false,
        }
    }

    /// Consume the bare keyword `kw` (`and`/`or`) if it is next as a whole
    /// identifier; restores the cursor and returns false otherwise. Matched
    /// case-insensitively.
    function try_media_keyword(self, kw: string) -> bool {
        let mark = self.sc.mark();
        if (!root.std.is_ascii_alphabetic(self.sc.peek())) {
            self.sc.reset(mark);
            return false;
        }
        let word = "";
        while (match (self.sc.peek()) {
            let c: string => root.parser.is_ident_char(c),
            _ => false,
        }) {
            if let c: string = self.sc.bump() {
                word = word + c;
            }
        }
        if (root.std.eq_ignore_ascii_case(word, kw)) {
            true
        } else {
            self.sc.reset(mark);
            false
        }
    }

    /// After a media `and`/`or`/`not` keyword, dart-sass requires whitespace
    /// (or a comment) before the next operand: `and(b)` is an error.
    function parse_media_keyword_whitespace(self) -> void {
        if (!self.skip_media_ws()) {
            // An interpolation operand needs no space; `(` does.
            if (!(self.sc.peek() == "#" && self.sc.peek_at(1) == "{")) {
                throw root.error.Error.at("Expected whitespace.", self.sc.position());
            }
        }
    }

    /// Parse a `@function name(params) { … }` or `@mixin name(params) { … }`.
    function parse_callable_def(self, is_function: bool) -> root.ast.Stmt {
        self.skip_ws_inline();
        let name_pos = self.sc.position();
        let name_mark = self.sc.mark();
        let name = self.read_ident_name();
        // A user `@function` may not reuse a name the parser treats as a
        // SassScript operator or a special plain-CSS function (dart-sass).
        if (is_function && root.parser.is_reserved_function_name(name)) {
            throw root.error.Error.at("Invalid function name.", name_pos);
        }
        // The `declaration` span an argument error points back at is
        // `name(params)` — or just the name when no parameter list follows, so
        // the whitespace `parse_param_list` skips on its way to nothing is not
        // underlined.
        let name_length = self.sc.byte_len_from(name_mark);
        let before_params = self.sc.mark();
        self.skip_ws_inline();
        let has_params = self.sc.peek() == "(";
        self.sc.reset(before_params);
        let params = self.parse_param_list();
        let decl_length = if (has_params) {
            self.sc.byte_len_from(name_mark)
        } else {
            name_length
        };
        let body = self.parse_braced_body();
        // Unknown at-rules aren't allowed in a function body (parse-time in
        // dart-sass: "This at-rule is not allowed here.").
        if (is_function) {
            root.parser.reject_at_rules_in(body);
        }
        let callable = root.ast.Callable {
            name: name,
            params: params,
            body: body,
            decl_pos: name_pos,
            decl_length: decl_length,
        };
        if (is_function) {
            root.ast.Stmt_FunctionDef { _0: callable }
        } else {
            root.ast.Stmt_MixinDef { _0: callable }
        }
    }

    /// After a lowercase `@function`/`@mixin` keyword, peek whether the name
    /// that follows begins with `--` (a plain CSS custom function/mixin).
    function peek_callable_name_is_custom(self) -> bool {
        // PORT: `self.sc.rest()` copies the remaining source; scan the scanner's
        // own buffer instead, with `i` starting at the cursor (absolute indices).
        let cs = self.sc.chars;
        let i = root.std.imin(self.sc.pos, cs.length());
        while (i < cs.length() && cs[i].is_whitespace()) {
            i += 1;
        }
        cs.at(i) == "-" && cs.at(i + 1) == "-"
    }

    /// Parse a plain CSS custom `@function`/`@mixin` (`keyword` is the literal
    /// at-rule name, e.g. `function`/`FUNCTION`/`mixin`). The prelude (the name,
    /// optional parameter list, and optional `returns <type>` clause) is
    /// captured as a template up to `{`; the body's top-level declarations keep
    /// their values verbatim. Only `#{...}` interpolation is resolved.
    function parse_css_custom_callable(self, keyword: string) -> root.ast.Stmt {
        self.skip_ws_inline();
        let prelude = root.parser.trim_prelude(self.parse_template(["{", ";", "}"]));
        self.skip_ws_inline();
        if (self.sc.peek() != "{") {
            // A bodyless form (`@mixin --a;`) is not valid CSS here.
            throw root.error.Error.at("expected \"{\".", self.sc.position());
        }
        self.sc.bump(); // '{'
        let body = self.parse_css_custom_body();
        root.ast.Stmt_CssCustomAtRule {
            name: keyword,
            prelude: prelude,
            body: body,
        }
    }

    /// Parse the `{ … }` body of a plain CSS custom `@function`/`@mixin` after
    /// the `{` has been consumed, up to and including the matching `}`. Each
    /// top-level item is a declaration `property: value`. When the property is
    /// a plain literal the value is captured verbatim (a template); when it
    /// contains interpolation the value is parsed as SassScript.
    function parse_css_custom_body(self) -> root.ast.CssCustomItem[] {
        let items: root.ast.CssCustomItem[] = [];
        while (true) {
            self.skip_ws_inline();
            match (self.sc.peek()) {
                null => {
                    throw root.error.Error.at("expected \"}\".", self.sc.position());
                }
                "}" => {
                    self.sc.bump();
                    break;
                }
                ";" => {
                    self.sc.bump();
                    continue;
                }
                _ => {}
            }
            // Property name up to `:` (interpolation allowed).
            let property = root.parser.trim_prelude(self.parse_template([":", "{", ";", "}"]));
            if (!self.sc.eat(":")) {
                throw root.error.Error.at("expected \":\".", self.sc.position());
            }
            let has_interp = property.some((p: root.ast.TplPiece) -> bool { p is root.ast.TplPiece_Interp });
            if (has_interp) {
                self.skip_ws_inline();
                // An interpolated property name follows the ordinary nested-
                // property rules: a value-less `{ … }` block expands each
                // child as `property-child` (`#{re}sult: {b: c}` emits
                // `result-b: c`) — unlike a literal `result`, whose value is
                // captured verbatim (braces and all).
                if (self.sc.peek() == "{") {
                    self.sc.bump();
                    let children: root.std.Tuple2<root.ast.TplPiece[], root.ast.Expr>[] = [];
                    while (true) {
                        self.skip_ws_inline();
                        match (self.sc.peek()) {
                            null => {
                                throw root.error.Error.at("expected \"}\".", self.sc.position());
                            }
                            "}" => {
                                self.sc.bump();
                                break;
                            }
                            ";" => {
                                self.sc.bump();
                                continue;
                            }
                            _ => {}
                        }
                        let child = root.parser.trim_prelude(self.parse_template([":", "{", ";", "}"]));
                        if (!self.sc.eat(":")) {
                            throw root.error.Error.at("expected \":\".", self.sc.position());
                        }
                        self.skip_ws_inline();
                        let expr = self.parse_value();
                        self.skip_ws_inline();
                        self.sc.eat(";");
                        children.push(root.std.Tuple2 { _0: child, _1: expr });
                    }
                    items.push(root.ast.CssCustomItem {
                        property: property,
                        value: root.ast.CssCustomValue_Set { _0: children },
                    });
                    continue;
                }
                let expr = self.parse_value();
                self.skip_ws_inline();
                self.sc.eat(";");
                items.push(root.ast.CssCustomItem {
                    property: property,
                    value: root.ast.CssCustomValue_Script { _0: expr },
                });
            } else {
                let raw = self.parse_css_custom_value();
                // The reader consumes its `;` and stops at `}` or at the end of
                // the file — except at a closer with no opener, which dart
                // reports as a missing separator rather than as a bad property
                // name (`result: ];` fails at the `]`).
                let next = self.sc.peek();
                if (next == ")" || next == "]") {
                    throw root.error.Error.at("expected \";\".", self.sc.position());
                }
                items.push(root.ast.CssCustomItem {
                    property: property,
                    value: root.ast.CssCustomValue_Raw { _0: raw },
                });
            }
        }
        items
    }

    /// Capture a verbatim CSS custom declaration value after the `:`, up to the
    /// terminating top-level `;` or `}`. Whitespace runs collapse to a single
    /// space (matching dart-sass serialization); `#{...}` interpolation is
    /// resolved; each closer is matched against the bracket it opened, so a
    /// braced value such as `{b: c}` is captured whole and `(]` is an error.
    /// The terminating `;` is consumed; a `}` is left for the body loop.
    function parse_css_custom_value(self) -> root.ast.TplPiece[] {
        let pieces: root.ast.TplPiece[] = [];
        let lit = root.std.StrBuf.new();
        let brackets: string[] = [];
        while (true) {
            match (self.sc.peek()) {
                null => {
                    break;
                }
                ";" if brackets.length() == 0 => {
                    self.sc.bump();
                    break;
                }
                // An escape is one token, so an escaped delimiter is literal
                // text rather than a bracket (dart re-serializes it canonically).
                "\\" => {
                    let c = self.read_escape_char();
                    root.parser.push_ident_escape(lit, c, true);
                }
                "#" if self.sc.peek_at(1) == "{" => {
                    let interp_mark = self.sc.mark();
                    if (!lit.is_empty()) {
                        pieces.push(root.parser.take_lit(lit));
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
                }
                let q: string if q == "\"" || q == "'" => {
                    lit.push(q);
                    self.sc.bump();
                    while (true) {
                        match (self.sc.peek()) {
                            null => {
                                break;
                            }
                            "\\" => {
                                lit.push("\\");
                                self.sc.bump();
                                if let esc: string = self.sc.bump() {
                                    lit.push(esc);
                                }
                            }
                            // Interpolation resolves inside the string too, as
                            // the documented behaviour of this reader says and
                            // as the custom-property reader already did.
                            "#" if self.sc.peek_at(1) == "{" => {
                                let interp_mark = self.sc.mark();
                                if (!lit.is_empty()) {
                                    pieces.push(root.parser.take_lit(lit));
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
                            }
                            let ch: string => {
                                lit.push(ch);
                                self.sc.bump();
                                if (ch == q) {
                                    break;
                                }
                            }
                        }
                    }
                }
                let c: string if c.is_whitespace() => {
                    while (root.std.is_whitespace(self.sc.peek())) {
                        self.sc.bump();
                    }
                    lit.push(" ");
                }
                let c: string if c == "(" || c == "[" || c == "{" => {
                    brackets.push(match (c) {
                        "(" => ")",
                        "[" => "]",
                        _ => "}",
                    });
                    lit.push(c);
                    self.sc.bump();
                }
                let c: string if c == ")" || c == "]" || c == "}" => {
                    // A closer with no opener ENDS the value (the caller then
                    // wants its `;`); a closer that does not match the bracket
                    // it would close is an error, as in every other verbatim
                    // value reader.
                    let expected = root.std.last(brackets);
                    if (expected == null) {
                        break;
                    }
                    if (c != expected) {
                        throw root.error.Error.at(`expected "${expected}".`, self.sc.position());
                    }
                    brackets.pop();
                    lit.push(c);
                    self.sc.bump();
                }
                let c: string => {
                    lit.push(c);
                    self.sc.bump();
                }
            }
        }
        if let expected: string = root.std.last(brackets) {
            throw root.error.Error.at(`expected "${expected}".`, self.sc.position());
        }
        if (!lit.is_empty()) {
            pieces.push(root.parser.take_lit(lit));
        }
        pieces
    }

    /// Capture a custom-property (`--name`) declaration value verbatim, from
    /// just after the colon up to the terminating top-level `;` or `}`. This
    /// mirrors dart-sass `_interpolatedDeclarationValue`: `#{…}` interpolation
    /// resolves *everywhere* (including inside strings), `//` and `/* */` are
    /// literal value characters (not comments), strings and `()`/`[]`/`{}` keep
    /// their delimiters, and whitespace runs collapse to a single space. The
    /// captured pieces are trimmed of surrounding whitespace; the terminating
    /// `;` is left for the caller.
    function parse_custom_property_value(self) -> root.ast.TplPiece[] {
        let pieces: root.ast.TplPiece[] = [];
        let lit = root.std.StrBuf.new();
        // dart-sass matches each closer against the bracket it opened, so `(]`
        // is an error rather than a pair that cancels out, and a closer with no
        // opener ENDS the value (the caller then expects its `;`).
        let brackets: string[] = [];
        // dart-sass `_interpolatedDeclarationValue` writes whitespace lazily:
        // a run of spaces/tabs collapses to its *last* character (a tab survives
        // a tab-only run), while a run containing a newline emits one `\n` plus
        // the following indentation verbatim. `wrote_newline` tracks whether the
        // most recently written character was a newline so indentation after a
        // newline is preserved and blank lines are not duplicated. The value is
        // NOT trimmed — leading whitespace after the colon and trailing
        // whitespace are both significant for a custom property.
        let wrote_newline = false;
        while (true) {
            match (self.sc.peek()) {
                null => {
                    break;
                }
                ";" if brackets.length() == 0 => {
                    break;
                }
                // An escape is one token: the delimiter behind it is literal
                // text, so `--x: \\{` is a complete value rather than an open
                // brace that swallows everything after it. dart re-serializes
                // the escape canonically (`\\7b` and `\\{` both print as `\\{`,
                // `\\61 b` as `ab`), passing `identifierStart: true`.
                "\\" => {
                    let c = self.read_escape_char();
                    root.parser.push_ident_escape(lit, c, true);
                    wrote_newline = false;
                }
                "#" if self.sc.peek_at(1) == "{" => {
                    let interp_mark = self.sc.mark();
                    if (!lit.is_empty()) {
                        pieces.push(root.parser.take_lit(lit));
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
                    wrote_newline = false;
                }
                let q: string if q == "\"" || q == "'" => {
                    // Capture the string, resolving interpolation inside it but
                    // keeping the quotes and other characters verbatim.
                    lit.push(q);
                    self.sc.bump();
                    while (true) {
                        match (self.sc.peek()) {
                            null => {
                                break;
                            }
                            "\\" => {
                                lit.push("\\");
                                self.sc.bump();
                                if let esc: string = self.sc.peek() {
                                    lit.push(esc);
                                    self.sc.bump();
                                }
                            }
                            "#" if self.sc.peek_at(1) == "{" => {
                                let interp_mark = self.sc.mark();
                                if (!lit.is_empty()) {
                                    pieces.push(root.parser.take_lit(lit));
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
                            }
                            let c: string => {
                                lit.push(c);
                                self.sc.bump();
                                if (c == q) {
                                    break;
                                }
                            }
                        }
                    }
                    wrote_newline = false;
                }
                let c: string if c == "\n" || c == "\r" || c == "\f" => {
                    self.sc.bump();
                    // Treat `\r\n` as one newline.
                    if (c == "\r" && self.sc.peek() == "\n") {
                        self.sc.bump();
                    }
                    if (!wrote_newline) {
                        lit.push("\n");
                        wrote_newline = true;
                    }
                }
                let c: string if c == " " || c == "\t" => {
                    // Write this space/tab only if we just emitted a newline (so
                    // indentation is preserved) or it is the last whitespace of
                    // the run (so an inline run collapses to its final char).
                    let next_is_inline_ws = self.sc.peek_at(1) == " " || self.sc.peek_at(1) == "\t";
                    if (wrote_newline || !next_is_inline_ws) {
                        lit.push(c);
                    }
                    self.sc.bump();
                }
                let c: string if c == "(" || c == "[" || c == "{" => {
                    brackets.push(match (c) {
                        "(" => ")",
                        "[" => "]",
                        _ => "}",
                    });
                    lit.push(c);
                    self.sc.bump();
                    wrote_newline = false;
                }
                let c: string if c == ")" || c == "]" || c == "}" => {
                    let expected = root.std.last(brackets);
                    if (expected == null) {
                        break;
                    }
                    if (c != expected) {
                        throw root.error.Error.at(`expected "${expected}".`, self.sc.position());
                    }
                    brackets.pop();
                    lit.push(c);
                    self.sc.bump();
                    wrote_newline = false;
                }
                let c: string => {
                    lit.push(c);
                    self.sc.bump();
                    wrote_newline = false;
                }
            }
        }
        if let expected: string = root.std.last(brackets) {
            throw root.error.Error.at(`expected "${expected}".`, self.sc.position());
        }
        if (!lit.is_empty()) {
            pieces.push(root.parser.take_lit(lit));
        }
        // A trailing newline-run collapses to a single space (dart-sass emits a
        // trailing newline before the terminator as a space, not a line break).
        if let s: root.ast.TplPiece_Lit = root.std.last(pieces) {
            if (s._0.ends_with("\n")) {
                s._0 = `${root.std.trim_end_by(s._0, (ch: string) -> bool { ch == " " || ch == "\t" || ch == "\n" })} `;
            }
        }
        pieces
    }

    /// Parse a declared parameter list `($a, $b: default, $rest...)`.
    /// Missing parentheses means no parameters.
    function parse_param_list(self) -> root.ast.ParamList {
        let params: root.ast.Param[] = [];
        let rest: string? = null;
        // dart-sass forbids two parameters with the same name, treating `-` and
        // `_` as identical (`$a-b` and `$a_b` collide) — track the normalized
        // names seen so far and reject a repeat with "Duplicate parameter.".
        let seen: string[] = [];
        self.skip_ws_inline();
        if (self.sc.peek() != "(") {
            return root.ast.ParamList { params: params, rest: rest };
        }
        self.sc.bump(); // '('
        self.skip_ws_inline();
        if (self.sc.peek() == ")") {
            self.sc.bump();
            return root.ast.ParamList { params: params, rest: rest };
        }
        while (true) {
            self.skip_ws_inline();
            let name_pos = self.sc.position();
            if (!self.sc.eat("$")) {
                throw root.error.Error.at("expected a parameter", self.sc.position());
            }
            let name = self.read_variable_name();
            let norm = name.replace_all("_", "-");
            if (seen.includes(norm)) {
                throw root.error.Error.at("Duplicate parameter.", name_pos);
            }
            seen.push(norm);
            self.skip_ws_inline();
            if (self.sc.peek() == "."
                && self.sc.peek_at(1) == "."
                && self.sc.peek_at(2) == ".") {
                self.sc.bump();
                self.sc.bump();
                self.sc.bump();
                rest = name;
                self.skip_ws_inline();
                // An optional trailing comma is allowed after `$rest...`.
                self.sc.eat(",");
                self.skip_ws_inline();
                break;
            }
            // Source-map: a parameter bound from its declared default takes
            // that default's span as its definition node, so record where the
            // default's text starts (Pos::NONE when there is no default).
            let default_pos = root.scanner.Pos.NONE();
            let default: root.ast.Expr? = if (self.sc.peek() == ":") {
                self.sc.bump();
                self.skip_ws_inline();
                default_pos = self.sc.position();
                self.space_list()
            } else {
                null
            };
            params.push(root.ast.Param {
                name: name,
                default: default,
                default_pos: default_pos,
            });
            self.skip_ws_inline();
            if (self.sc.eat(",")) {
                self.skip_ws_inline();
                // A trailing comma before `)` ends the list.
                if (self.sc.peek() == ")") {
                    break;
                }
                continue;
            }
            break;
        }
        self.skip_ws_inline();
        if (!self.sc.eat(")")) {
            throw root.error.Error.at("expected \")\"", self.sc.position());
        }
        root.ast.ParamList { params: params, rest: rest }
    }

    /// Parse `@return <expr>;`.
    function parse_return(self) -> root.ast.Stmt {
        self.skip_ws_inline();
        let value = self.parse_value();
        self.skip_ws_inline();
        self.sc.eat(";");
        root.ast.Stmt_Return { _0: value }
    }

    /// Parse `@include name[(args)] [{ content }];`.
    function parse_include(self, pos: root.scanner.Pos, start_mark: root.scanner.Mark) -> root.ast.Stmt {
        self.skip_ws_inline();
        let include_name_pos = self.sc.position();
        let name = self.read_ident_name();
        // `@include --a` is reserved for plain CSS mixins (dart-sass), even
        // though `@mixin __a` normalizes to the same name.
        if (name.starts_with("--")) {
            throw root.error.Error.at(
                "Sass @mixin names beginning with -- are forbidden for forward-compatibility with plain CSS mixins.",
                include_name_pos,
            );
        }
        // `@include ns.mixin(...)` — a namespaced mixin reference.
        let module: string? = null;
        if (self.sc.peek() == ".") {
            self.sc.bump();
            module = name;
            let member_pos = self.sc.position();
            let member_mark = self.sc.mark();
            // Privacy is the LITERAL spelling: dart reads `ns.\2d priv` as an
            // ordinary member (and then fails to find it); only a written
            // `-`/`_` is private.
            let literally_private = self.sc.peek() == "-" || self.sc.peek() == "_";
            name = self.read_ident_name();
            if (literally_private) {
                // The caret covers the member name AS WRITTEN, escapes and all.
                throw root.error.Error.at(
                    "Private members can't be accessed from outside their modules.",
                    member_pos,
                )
                    .with_length(self.sc.byte_len_from(member_mark));
            }
        }
        // Byte length of `@include name` so far, before any whitespace that
        // separates the name from a content block (`@include m {`).
        let name_length = self.sc.byte_len_from(start_mark);
        self.skip_ws_inline();
        let args_length: root.std.Tuple2<root.ast.CallArg[], int> = if (self.sc.peek() == "(") {
            self.sc.bump();
            let args = self.parse_args_after_paren();
            // Byte length of `@include name(args)` through the closing `)`.
            root.std.Tuple2 { _0: args, _1: self.sc.byte_len_from(start_mark) }
        } else {
            root.std.Tuple2 { _0: [], _1: name_length }
        };
        let args = args_length._0;
        let length = args_length._1;
        // How much of the statement is WRITTEN in the source: the call, plus a
        // `using (…)` clause if there is one. Whitespace and braces after that
        // can be the indented front end's own (it wraps a child block to hand
        // the parser SCSS), so they are not a source span to point at.
        let source_length = length;
        self.skip_ws_inline();
        // An optional `using (params)` clause names the content block's
        // parameters, bound from the `@content(args)` call.
        let using_mark = self.sc.mark();
        // PORT: `.read_ident_name().ok().is_some_and(..)` — a failed read is `None`.
        let using_kw: string? = self.read_ident_name() catch (e) {
            let _err: root.error.Error => null,
        };
        let content_params: root.ast.ParamList? = if (match (using_kw) {
            let kw: string => root.std.eq_ignore_ascii_case(kw, "using"),
            _ => false,
        }) {
            self.skip_ws_inline();
            // `using` must be followed by a parenthesized parameter list.
            if (self.sc.peek() != "(") {
                throw root.error.Error.at("expected \"(\".", self.sc.position());
            }
            let params = self.parse_param_list();
            source_length = self.sc.byte_len_from(start_mark);
            params
        } else {
            self.sc.reset(using_mark);
            null
        };
        self.skip_ws_inline();
        // dart carets an error about the RULE (an undefined mixin) over all of
        // it, `using` clause and content block included, and an error about the
        // CALL (a content block the mixin does not take) over
        // `@include name(args)` only. Neither covers the terminating `;`.
        // PORT: Rust's deferred `let full_length;` — every path below assigns it.
        let full_length = 0;
        let content: root.ast.Stmt[]? = if (self.sc.peek() == "{") {
            let body = self.parse_braced_body();
            // In the indented syntax the braces around a child block are
            // SYNTHETIC — the front end wrote them into the reconstruction —
            // so the text they enclose is not a source span to point at, and
            // the span stops where the WRITTEN text does. dart spans the
            // children; matching that needs the front end to map a
            // reconstruction span back to source.
            full_length = if (self.indented) {
                source_length
            } else {
                self.sc.byte_len_from(start_mark)
            };
            body
        } else if (content_params != null) {
            // A `using (params)` clause requires a content block to bind into.
            throw root.error.Error.at("expected \"{\".", self.sc.position());
        } else {
            full_length = self.sc.byte_len_from(start_mark);
            self.sc.eat(";");
            null
        };
        root.ast.Stmt_Include {
            name: name,
            args: args,
            content: content,
            content_params: content_params,
            module: module,
            pos: pos,
            length: length,
            full_length: full_length,
        }
    }

}
