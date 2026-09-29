// Ported from sasso `src/parser/statements.rs` (namespace `root.parser.statements`).
//
// Statement and declaration parsing: the top-level statement loop
// (`parse_statements`), trivia/comment skipping, the rule-vs-declaration
// lookahead (`classify`), style rules, declarations + nested property sets,
// and variable declarations. Extracted verbatim from [`super`].

interface ParserStatements {
    function parse_statements(self, top: bool) -> root.ast.Stmt[] throws unknown;

    /// Skip whitespace and comments, collecting loud `/* */` comments into
    /// the statement stream so they emit in source order.
    function skip_trivia(self, out: root.ast.Stmt[]) -> void throws unknown;

    /// Look ahead to decide whether the next statement is a rule (a
    /// top-level `{` comes first) or a declaration (`;`/`}` comes first),
    /// skipping over strings, comments, interpolation and bracket pairs.
    ///
    /// A top-level `{` after a `property:` is a *nested property set* (a
    /// declaration with a block) rather than a style rule when the value is
    /// empty (`b: { … }` / `b:{ … }`) or whitespace/comment immediately
    /// follows the colon (`b: c { … }`). Otherwise (`a:hover { … }`) the `{`
    /// opens a style rule — matching dart-sass declaration disambiguation.
    function classify(self) -> root.parser.NextKind throws unknown;

    function parse_rule(self) -> root.ast.Stmt throws unknown;

    function parse_declaration(self) -> root.ast.Stmt throws unknown;

    /// Parse the `{ … }` block of a nested property set (the cursor is at `{`),
    /// consuming an optional trailing `;` so a following sibling parses cleanly
    /// (`b: { c: { d: e }; f: g }`).
    function parse_property_set_body(self) -> root.ast.Stmt[] throws unknown;

    function parse_var_decl(self) -> root.ast.Stmt throws unknown;

    /// Whether the scanner is at the start of a namespaced variable assignment
    /// `ns.$name` (an identifier, then `.`, then `$`). Does not consume input.
    function peek_namespaced_var_decl(self) -> bool throws unknown;
}

implements ParserStatements for root.parser.Parser {
    function parse_statements(self, top: bool) -> root.ast.Stmt[] {
        let stmts: root.ast.Stmt[] = [];
        while (true) {
            self.skip_trivia(stmts);
            match (self.sc.peek()) {
                null => {
                    if (top) {
                        break;
                    }
                    // dart names what it wanted, not what it found: a file
                    // that ends inside a block is `expected "}".`
                    throw root.error.Error.at("expected \"}\".", self.sc.position());
                }
                "}" => {
                    if (top) {
                        throw root.error.Error.at("unexpected \"}\"", self.sc.position());
                    }
                    break;
                }
                // A stray `;` (e.g. after a `}` rule block) is an empty
                // statement: dart-sass accepts and ignores it.
                ";" => {
                    self.sc.bump();
                    continue;
                }
                "$" => {
                    stmts.push(self.parse_var_decl());
                }
                "@" => {
                    stmts.push(self.parse_at_rule());
                }
                // The indented syntax's mixin shorthands, read in place so
                // every column after the keyword stays a `.sass` column:
                // `=name(params)` defines a mixin (dart `SassParser`'s `=`),
                // `+name(args)` includes one. A `+` NOT followed by a name is
                // the next-sibling combinator, i.e. a selector.
                "=" if self.indented => {
                    self.sc.bump();
                    self.skip_ws_inline();
                    // `=--name` is the plain-CSS mixin spelling dart reserves,
                    // rejected exactly as `@mixin --name` is (dart points at
                    // the name, which is where the shorthand puts it).
                    if (self.peek_callable_name_is_custom()) {
                        throw root.error.Error.at(
                            "Sass @mixin names beginning with -- are forbidden for forward-compatibility with plain CSS mixins.",
                            self.sc.position(),
                        );
                    }
                    stmts.push(self.parse_callable_def(false));
                }
                "+" if self.indented
                    && match (self.sc.peek_at(1)) {
                        null => false,
                        let c: string => root.parser.is_ident_char(c) || c == "#" || c == "\\",
                    } => {
                    let pos = self.sc.position();
                    let start_mark = self.sc.mark();
                    self.sc.bump();
                    stmts.push(self.parse_include(pos, start_mark));
                }
                // The legacy escaped-selector form: a leading `\` marks the
                // line as a SELECTOR rather than the old `:prop value`
                // declaration syntax, and is not part of it. Consumed here so
                // the selector keeps its own column (dart maps `\:hover` to
                // the `:`), not upstream where dropping it shifted the line.
                "\\" if self.indented => {
                    self.sc.bump();
                    stmts.push(self.parse_rule());
                }
                // A namespaced variable assignment `ns.$name: value`.
                _ if self.peek_namespaced_var_decl() => {
                    stmts.push(self.parse_var_decl());
                }
                _ => {
                    match (self.classify()) {
                        root.parser.NextKind.Rule => {
                            stmts.push(self.parse_rule());
                        }
                        root.parser.NextKind.Declaration => {
                            stmts.push(self.parse_declaration());
                        }
                    }
                }
            }
            // Track, at the top level, whether anything that must follow `@use`
            // has been seen. A variable declaration, `@charset`, `@use`, and
            // `@forward` (and comments, which `skip_trivia` collects) are
            // permitted before `@use`; anything else "uses up" the position.
            if (top) {
                if let last: root.ast.Stmt = root.std.last(stmts) {
                    if (!root.parser.stmt_allowed_before_use(last)) {
                        self.seen_non_module_stmt = true;
                    }
                }
            }
        }
        stmts
    }

    /// Skip whitespace and comments, collecting loud `/* */` comments into
    /// the statement stream so they emit in source order.
    function skip_trivia(self, out: root.ast.Stmt[]) -> void {
        while (true) {
            match (self.sc.peek()) {
                let c: string if c.is_whitespace() => {
                    self.sc.bump();
                }
                "/" if self.sc.peek_at(1) == "/" => {
                    if (self.plain_css) {
                        throw root.error.Error.at(
                            "Silent comments aren't allowed in plain CSS.",
                            self.sc.position(),
                        );
                    }
                    while let c: string = self.sc.peek() {
                        if (c == "\n") {
                            break;
                        }
                        self.sc.bump();
                    }
                }
                "/" if self.sc.peek_at(1) == "*" => {
                    let start = self.sc.position();
                    let col0 = start.col - 1;
                    self.sc.bump();
                    self.sc.bump();
                    let pieces = self.parse_loud_comment_body();
                    let end_line = self.sc.position().line;
                    out.push(root.ast.Stmt_Comment {
                        _0: pieces,
                        _1: root.ast.SrcLines {
                            file: 0,
                            start: start.line,
                            end: end_line,
                            col: start.col,
                            // The `/*`'s 0-based column, for source-map output.
                            start_col: col0,
                            map_file: 0,
                            map_line: 0,
                        },
                    });
                }
                _ => {
                    break;
                }
            }
        }
    }

    /// Look ahead to decide whether the next statement is a rule (a
    /// top-level `{` comes first) or a declaration (`;`/`}` comes first),
    /// skipping over strings, comments, interpolation and bracket pairs.
    ///
    /// A top-level `{` after a `property:` is a *nested property set* (a
    /// declaration with a block) rather than a style rule when the value is
    /// empty (`b: { … }` / `b:{ … }`) or whitespace/comment immediately
    /// follows the colon (`b: c { … }`). Otherwise (`a:hover { … }`) the `{`
    /// opens a style rule — matching dart-sass declaration disambiguation.
    function classify(self) -> root.parser.NextKind {
        // PORT: `self.sc.rest()` copies the remaining source on every call
        // (O(n) per statement); scan the scanner's own buffer instead, with `i`
        // starting at the cursor so every index below is absolute.
        let cs = self.sc.chars;
        let i = root.std.imin(self.sc.pos, cs.length());
        let paren = 0;
        let bracket = 0;
        // Index just past the first top-level `:`, plus whether whitespace or a
        // comment immediately follows it. `None` until the colon is seen.
        let after_colon: int? = null;
        let ws_after_colon = false;
        // Whether the statement's first non-whitespace characters are `--`: a
        // custom-property name. With a top-level `:` it is always a custom
        // declaration (`--ambiguous:foo {…}`), never a style rule.
        let starts_custom = {
            let first: int? = null;
            let k = i;
            while (k < cs.length()) {
                if (!cs[k].is_whitespace()) {
                    first = k;
                    break;
                }
                k += 1;
            }
            match (first) {
                let p: int => cs.at(p) == "-" && cs.at(p + 1) == "-",
                _ => false,
            }
        };
        while (i < cs.length()) {
            let c = cs[i];
            match (c) {
                "\"" | "'" => {
                    let q = c;
                    i += 1;
                    while (i < cs.length() && cs[i] != q) {
                        if (cs[i] == "\\") {
                            i += 1;
                        }
                        i += 1;
                    }
                    i += 1;
                    continue;
                }
                "/" if cs.at(i + 1) == "/" => {
                    while (i < cs.length() && cs[i] != "\n") {
                        i += 1;
                    }
                    continue;
                }
                "/" if cs.at(i + 1) == "*" => {
                    i += 2;
                    while (i + 1 < cs.length() && !(cs[i] == "*" && cs[i + 1] == "/")) {
                        i += 1;
                    }
                    i += 2;
                    continue;
                }
                "#" if cs.at(i + 1) == "{" => {
                    i += 2;
                    let depth = 1;
                    while (i < cs.length() && depth > 0) {
                        match (cs[i]) {
                            "{" => {
                                depth += 1;
                            }
                            "}" => {
                                depth -= 1;
                            }
                            _ => {}
                        }
                        i += 1;
                    }
                    continue;
                }
                // A CSS escape: the next character (`something\:`) is part of
                // the identifier, never a declaration colon.
                "\\" => {
                    i += 2;
                    continue;
                }
                "(" => {
                    paren += 1;
                }
                ")" => {
                    paren -= 1;
                }
                "[" => {
                    bracket += 1;
                }
                "]" => {
                    bracket -= 1;
                }
                ":" if paren == 0 && bracket == 0 && after_colon == null => {
                    // A custom-property name with a `:` is always a declaration,
                    // even when a `{` follows (`--ambiguous:foo {…}`).
                    if (starts_custom) {
                        return root.parser.NextKind.Declaration;
                    }
                    after_colon = i + 1;
                    ws_after_colon = match (cs.at(i + 1)) {
                        let n: string => n.is_whitespace(),
                        _ => false,
                    }
                        || (cs.at(i + 1) == "/" && (cs.at(i + 2) == "*" || cs.at(i + 2) == "/"));
                }
                "{" if paren == 0 && bracket == 0 => {
                    return match (after_colon) {
                        // No `property:` before this `{` — an ordinary rule.
                        null => root.parser.NextKind.Rule,
                        // `property:` then a block: a nested property set if the
                        // value is empty, or whitespace/comment followed the
                        // colon; otherwise (`a:hover {`) a style rule.
                        let start: int => {
                            let empty_value = cs.slice(start, i).every((ch: string) -> bool { ch.is_whitespace() })
                                || root.parser.value_is_only_comments(cs.slice(start, i));
                            if (empty_value || ws_after_colon) {
                                root.parser.NextKind.Declaration
                            } else {
                                root.parser.NextKind.Rule
                            }
                        },
                    };
                }
                ";" if paren == 0 && bracket == 0 => {
                    return root.parser.NextKind.Declaration;
                }
                "}" if paren == 0 && bracket == 0 => {
                    return root.parser.NextKind.Declaration;
                }
                _ => {}
            }
            i += 1;
        }
        root.parser.NextKind.Declaration
    }

    function parse_rule(self) -> root.ast.Stmt {
        let selector_pos = self.sc.position();
        let saved_spans = self.interp_spans;
        self.interp_spans = [];
        let saved_collect = self.collect_interp_spans;
        self.collect_interp_spans = true;
        // A top-level `!` is not valid in a selector: dart-sass stops the
        // selector there and then fails to find the `{` (`a !important {…}` →
        // `expected "{".`). It is only a stop at depth 0 — a `!` inside an
        // attribute selector (`[a="x!y"]`) or a string is consumed normally.
        // PORT: Rust restores the collection state before `selector?`; BAML
        // throws at the call, so the restore also runs in the catch arm.
        let selector = self.parse_template_mode(["{", "!"], root.parser.CommentMode.Strip) catch (e) {
            let err: root.error.Error => {
                self.collect_interp_spans = saved_collect;
                self.interp_spans = saved_spans;
                throw err;
            }
        };
        self.collect_interp_spans = saved_collect;
        let selector_interp_spans = self.interp_spans;
        self.interp_spans = saved_spans;
        let brace_line = self.sc.position().line;
        if (!self.sc.eat("{")) {
            throw root.error.Error.at("expected \"{\".", self.sc.position());
        }
        self.block_depth += 1;
        // PORT: Rust restores `block_depth` before `body?`; see above.
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
        let end_line = self.sc.position().line;
        root.ast.Stmt_Rule {
            _0: root.ast.Rule {
                selector: selector,
                body: body,
                selector_pos: selector_pos,
                selector_interp_spans: selector_interp_spans,
                brace_line: brace_line,
                end_line: end_line,
            },
        }
    }

    function parse_declaration(self) -> root.ast.Stmt {
        let pos = self.sc.position();
        // An IE property hack may start with a single punctuation character;
        // `*x`/`.x`/`#x` fall out of template parsing naturally, but a leading
        // `:` (`:x: y`) must be consumed up front so the property name doesn't
        // terminate at it (dart-sass `_declarationOrBuffer` reads one leading
        // `:`/`*`/`.`/`#` before the identifier).
        let colon_hack = self.sc.peek() == ":"
            && match (self.sc.peek_at(1)) {
                let c: string => c.is_alphanumeric() || c == "-" || c == "_" || c == "\\",
                _ => false,
            };
        if (colon_hack) {
            self.sc.bump();
        }
        let property = self.parse_template_mode([":"], root.parser.CommentMode.DeclName);
        if (colon_hack) {
            match (property.at(0)) {
                let lit: root.ast.TplPiece_Lit => {
                    lit._0 = `:${lit._0}`;
                }
                _ => {
                    property.insert(root.ast.TplPiece_Lit { _0: ":" }, 0);
                }
            }
        }
        if (!self.sc.eat(":")) {
            throw root.error.Error.at("expected \":\" in declaration", self.sc.position());
        }
        // A declaration whose name *literally* begins with `--` is a custom
        // property: its value is captured verbatim (only `#{…}` interpolation
        // resolves, no SassScript), and a trailing `{` is part of the value —
        // never a nested property set.
        if (root.parser.property_is_literal_custom(property)) {
            // Source-map: the verbatim value text starts right after the colon,
            // leading whitespace included (dart's `node.value.span`).
            let value_pos = self.sc.position();
            let value = self.parse_custom_property_value();
            let end_line = self.sc.position().line;
            // The value reader stops at `;`, `}`, the end of the file — or at a
            // closer with no opener, which dart reports as a missing separator
            // (`--x: ];` fails at the `]`, not at the end of the file).
            let next = self.sc.peek();
            if (!(next == null || next == ";" || next == "}")) {
                throw root.error.Error.at("expected \";\".", self.sc.position());
            }
            self.sc.eat(";");
            return root.ast.Stmt_CustomDecl {
                _0: root.ast.CustomDecl {
                    property: property,
                    value: value,
                    pos: pos,
                    end_line: end_line,
                    value_pos: value_pos,
                },
            };
        }
        let ws_after_colon = self.skip_ws_inline();
        // Bare nested property set: `prop: { … }` / `prop:{ … }` (no value).
        if (self.sc.peek() == "{") {
            let body = self.parse_property_set_body();
            return root.ast.Stmt_PropertySet {
                _0: root.ast.PropertySet {
                    property: property,
                    value: null,
                    important: false,
                    body: body,
                    pos: pos,
                },
            };
        }
        // Source-map: where the value's own text begins (dart's
        // `CssValue.span.start` for a declaration value). Captured before
        // `parse_value` consumes it.
        let value_pos = self.sc.position();
        let value = self.parse_value();
        // The line where the declaration's span ends, for the serializer's
        // trailing-comment rule — captured before whitespace is skipped (an
        // `!important` flag extends the span).
        let end_line = self.sc.position().line;
        let important = false;
        self.skip_ws_inline();
        if (self.sc.peek() == "!") {
            // `!important` is consumed by the expression layer as a value
            // term, so a `!` here is a stray flag (`!default` after a plain
            // declaration) — dart stops the declaration at the `!` and fails
            // wanting the terminator.
            let bang_pos = self.sc.position();
            if (!self.looking_at_important()) {
                throw root.error.Error.at("expected \";\".", bang_pos);
            }
            self.sc.bump();
            self.skip_ws_inline();
            let _ = self.read_ident_name() catch (e) {
                let _err: root.error.Error => "",
            };
            important = true;
            end_line = self.sc.position().line;
        }
        // Value-plus-block nested property set: `prop: value [!important] { … }`.
        // Only a value separated from the colon by whitespace (or comment)
        // qualifies — `prop:value { … }` is a style rule.
        if (ws_after_colon) {
            let mark = self.sc.mark();
            self.skip_ws_inline();
            if (self.sc.peek() == "{") {
                let body = self.parse_property_set_body();
                return root.ast.Stmt_PropertySet {
                    _0: root.ast.PropertySet {
                        property: property,
                        value: value,
                        important: important,
                        body: body,
                        pos: pos,
                    },
                };
            }
            self.sc.reset(mark);
        }
        self.skip_ws_inline();
        self.sc.eat(";");
        root.ast.Stmt_Decl {
            _0: root.ast.Declaration {
                property: property,
                value: value,
                important: important,
                pos: pos,
                end_line: end_line,
                value_pos: value_pos,
            },
        }
    }

    /// Parse the `{ … }` block of a nested property set (the cursor is at `{`),
    /// consuming an optional trailing `;` so a following sibling parses cleanly
    /// (`b: { c: { d: e }; f: g }`).
    function parse_property_set_body(self) -> root.ast.Stmt[] {
        if (self.plain_css) {
            throw root.error.Error.at(
                "Nested declarations aren't allowed in plain CSS.",
                self.sc.position(),
            );
        }
        self.sc.bump(); // '{'
        self.block_depth += 1;
        // PORT: Rust restores `block_depth` before `body?`; BAML throws at the
        // call, so the restore also runs in the catch arm.
        let body = self.parse_statements(false) catch (e) {
            let err: root.error.Error => {
                self.block_depth -= 1;
                throw err;
            }
        };
        self.block_depth -= 1;
        // Unknown at-rules aren't allowed in a nested property set.
        root.parser.reject_at_rules_in(body);
        // dart's `_declarationChild` parses every non-`@` child of a nested
        // property set as a declaration, so a style rule there is its
        // `expected ":".` (the selector reads as a property name).
        // PORT: the nested `fn reject_rules_in` is hoisted to
        // `parse_property_set_body__reject_rules_in` below.
        parse_property_set_body__reject_rules_in(body);
        if (!self.sc.eat("}")) {
            throw root.error.Error.at("expected \"}\".", self.sc.position());
        }
        let mark = self.sc.mark();
        self.skip_ws_inline();
        if (!self.sc.eat(";")) {
            self.sc.reset(mark);
        }
        body
    }

    function parse_var_decl(self) -> root.ast.Stmt {
        let pos = self.sc.position();
        if (self.plain_css) {
            throw root.error.Error.at("Sass variables aren't allowed in plain CSS.", pos);
        }
        // An optional `ns.` prefix: `ns.$name: value` assigns to a module
        // variable. `peek_namespaced_var_decl` guarantees the shape.
        let namespace: string? = null;
        if (self.sc.peek() != "$") {
            namespace = self.read_ident_name();
            self.sc.eat(".");
        }
        self.sc.bump(); // '$'
        let name = self.read_variable_name();
        self.skip_ws_inline();
        if (!self.sc.eat(":")) {
            throw root.error.Error.at(
                "expected \":\" after variable name",
                self.sc.position(),
            );
        }
        self.skip_ws_inline();
        // Source-map: where the assigned value's text begins. This is the span
        // dart stores in `Environment._variableNodes` as the variable's
        // definition node, which a later bare `$name` reference resolves to.
        let value_pos = self.sc.position();
        let value = self.parse_value();
        let is_default = false;
        let is_global = false;
        while (true) {
            self.skip_ws_inline();
            if (self.sc.peek() == "!") {
                self.sc.bump();
                let flag = self.read_ident_name();
                match (flag) {
                    "default" => {
                        is_default = true;
                    }
                    "global" => {
                        is_global = true;
                    }
                    let other => {
                        throw root.error.Error.at(`invalid flag !${other}`, pos);
                    }
                }
            } else {
                break;
            }
        }
        self.skip_ws_inline();
        self.sc.eat(";");
        root.ast.Stmt_VarDecl {
            _0: root.ast.VarDecl {
                name: name,
                value: value,
                is_default: is_default,
                is_global: is_global,
                namespace: namespace,
                value_pos: value_pos,
            },
        }
    }

    /// Whether the scanner is at the start of a namespaced variable assignment
    /// `ns.$name` (an identifier, then `.`, then `$`). Does not consume input.
    function peek_namespaced_var_decl(self) -> bool {
        let i = 0;
        // Leading identifier.
        match (self.sc.peek_at(0)) {
            let c: string if c == "-" || c == "_" || c.is_ascii_alphabetic() || !c.is_ascii() => {}
            _ => {
                return false;
            }
        }
        while (match (self.sc.peek_at(i)) {
            let c: string => root.parser.is_ident_char(c),
            _ => false,
        }) {
            i += 1;
        }
        if (i == 0 || self.sc.peek_at(i) != ".") {
            return false;
        }
        self.sc.peek_at(i + 1) == "$"
    }

}

/// `reject_rules_in` — the nested helper of [`Parser::parse_property_set_body`]
/// (hoisted).
function parse_property_set_body__reject_rules_in(stmts: root.ast.Stmt[]) -> void {
    for (let s in stmts) {
        match (s) {
            let _r: root.ast.Stmt_Rule => {
                throw root.error.Error.unpositioned("expected \":\".");
            },
            let branches: root.ast.Stmt_If => {
                for (let b in branches._0) {
                    parse_property_set_body__reject_rules_in(b.body);
                }
            },
            let f: root.ast.Stmt_For => {
                parse_property_set_body__reject_rules_in(f.body);
            },
            let e: root.ast.Stmt_Each => {
                parse_property_set_body__reject_rules_in(e.body);
            },
            let w: root.ast.Stmt_While => {
                parse_property_set_body__reject_rules_in(w.body);
            },
            _ => {},
        }
    }
}
