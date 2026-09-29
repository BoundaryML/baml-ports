// Port of syn-2.0.117/src/parse.rs (+ the expression parser from src/expr.rs)

/// Cursor position within a token stream.
///
/// Rust's `ParseStream<'a>` is a `&ParseBuffer<'a>`.
class ParseBuffer {
    _trees: root.proc_macro2.TokenTree[],
    _pos: int,

    function new(stream: root.proc_macro2.TokenStream) -> ParseBuffer {
        ParseBuffer { _trees: stream.trees, _pos: 0 }
    }

    /// Returns whether there are no more tokens remaining to be parsed from
    /// this stream.
    function is_empty(self) -> bool { self._pos >= self._trees.length() }

    function peek_tree(self, offset: int) -> root.proc_macro2.TokenTree? {
        self._trees.at(self._pos + offset)
    }

    function span(self) -> root.proc_macro2.Span {
        if let t: root.proc_macro2.TokenTree = self.peek_tree(0) {
            root.proc_macro2.token_tree_span(t)
        } else {
            root.proc_macro2.Span.call_site()
        }
    }

    /// Triggers an error at the current position of the parse stream.
    function error(self, message: string) -> Error {
        let near = if let t: root.proc_macro2.TokenTree = self.peek_tree(0) { `: \`${root.proc_macro2.token_tree_to_string(t)}\`` } else { " (end of input)" };
        Error.new(self.span(), message + near)
    }

    /// Is the next token the punctuation sequence `p` (e.g. `::`, `..=`)?
    function peek_punct(self, p: string) -> bool {
        let chars = p.chars();
        for (let i in baml.iter.Range.new(0, chars.length())) {
            let t = self.peek_tree(i);
            let ok = match (t) {
                let pu: root.proc_macro2.Punct => pu.ch == chars[i] && (i == chars.length() - 1 || pu.spacing == root.proc_macro2.Spacing.Joint),
                _ => false,
            };
            if (!ok) {
                return false;
            }
        }
        true
    }

    function eat_punct(self, p: string) -> bool {
        if (self.peek_punct(p)) {
            self._pos += p.length();
            true
        } else {
            false
        }
    }

    function expect_punct(self, p: string) -> void throws Error {
        if (!self.eat_punct(p)) {
            throw self.error(`expected \`${p}\``);
        }
    }

    function peek_ident(self) -> string? {
        match (self.peek_tree(0)) {
            let i: root.proc_macro2.Ident => i.sym,
            _ => null,
        }
    }

    function parse_ident(self) -> string throws Error {
        if let s: string = self.peek_ident() {
            self._pos += 1;
            s
        } else {
            throw self.error("expected identifier")
        }
    }

    function peek_group(self, d: root.proc_macro2.Delimiter) -> root.proc_macro2.Group? {
        match (self.peek_tree(0)) {
            let g: root.proc_macro2.Group => if (g.delimiter == d) { g } else { null },
            _ => null,
        }
    }

    function peek_lit_str(self) -> bool {
        match (self.peek_tree(0)) {
            let l: root.proc_macro2.Literal => lit_from_literal(l) is LitStr,
            _ => false,
        }
    }

    /// `input.parse::<LitStr>()`
    function parse_lit_str(self) -> LitStr throws Error {
        match (self.peek_tree(0)) {
            let l: root.proc_macro2.Literal => {
                let lit = lit_from_literal(l);
                match (lit) {
                    let s: LitStr => {
                        self._pos += 1;
                        s
                    },
                    _ => throw self.error("expected string literal"),
                }
            },
            _ => throw self.error("expected string literal"),
        }
    }

    // ===== Expressions (syn::Expr::parse) =====

    function parse_expr(self) -> Expr throws Error {
        // range with no start: `..2`, `..=2`, `..`
        if (self.peek_punct("..=") || self.peek_punct("..")) {
            let closed = self.eat_punct("..=");
            if (!closed) { self.expect_punct(".."); }
            let end = if (self.can_begin_expr()) { self.parse_binary() } else { null };
            return ExprRange { start: null, end: end, closed: closed };
        }
        let start = self.parse_binary();
        if (self.peek_punct("..=") || self.peek_punct("..")) {
            let closed = self.eat_punct("..=");
            if (!closed) { self.expect_punct(".."); }
            let end = if (self.can_begin_expr()) { self.parse_binary() } else { null };
            return ExprRange { start: start, end: end, closed: closed };
        }
        start
    }

    function can_begin_expr(self) -> bool {
        match (self.peek_tree(0)) {
            null => false,
            let p: root.proc_macro2.Punct => p.ch == "-" || p.ch == "!" || p.ch == "&" || p.ch == "|" || p.ch == ":" || p.ch == "*",
            _ => true,
        }
    }

    function parse_binary(self) -> Expr throws Error {
        let left = self.parse_unary();
        while (true) {
            let op = if (self.peek_punct("+") && !self.peek_punct("+=")) {
                "+"
            } else if (self.peek_punct("*") && !self.peek_punct("*=")) {
                "*"
            } else if (self.peek_punct("/") && !self.peek_punct("/=")) {
                "/"
            } else if (self.peek_punct("-") && !self.peek_punct("->") && !self.peek_punct("-=")) {
                "-"
            } else {
                ""
            };
            if (op == "") {
                break;
            }
            self.expect_punct(op);
            let right = self.parse_unary();
            left = ExprBinary { left: left, op: op, right: right };
        }
        left
    }

    function parse_unary(self) -> Expr throws Error {
        if (self.eat_punct("-")) {
            return ExprUnary { op: "-", expr: self.parse_unary() };
        }
        if (self.eat_punct("!")) {
            return ExprUnary { op: "!", expr: self.parse_unary() };
        }
        if (self.eat_punct("*")) {
            return ExprUnary { op: "*", expr: self.parse_unary() };
        }
        if (self.eat_punct("&")) {
            if (self.peek_ident() == "mut") { self._pos += 1; }
            return ExprReference { expr: self.parse_unary() };
        }
        self.parse_postfix()
    }

    function parse_postfix(self) -> Expr throws Error {
        let e = self.parse_primary();
        while (true) {
            if let g: root.proc_macro2.Group = self.peek_group(root.proc_macro2.Delimiter.Parenthesis) {
                self._pos += 1;
                e = ExprCall { func: e, args: parse_comma_exprs(g.stream) };
                continue;
            }
            if (self.peek_punct(".") && !self.peek_punct("..")) {
                self._pos += 1;
                let member = if let s: string = self.peek_ident() {
                    self._pos += 1;
                    s
                } else {
                    match (self.peek_tree(0)) {
                        let l: root.proc_macro2.Literal => {
                            self._pos += 1;
                            l.repr
                        },
                        _ => throw self.error("expected identifier after `.`"),
                    }
                };
                let turbofish: string[] = [];
                if (self.peek_punct("::") && self.peek_is_lt_after_colons()) {
                    self._pos += 2;
                    turbofish = self.parse_generic_args();
                }
                if let g: root.proc_macro2.Group = self.peek_group(root.proc_macro2.Delimiter.Parenthesis) {
                    self._pos += 1;
                    e = ExprMethodCall { receiver: e, method: member, turbofish: turbofish, args: parse_comma_exprs(g.stream) };
                } else {
                    e = ExprField { base: e, member: member };
                }
                continue;
            }
            if (self.eat_punct("?")) {
                continue;
            }
            break;
        }
        e
    }

    function peek_is_lt_after_colons(self) -> bool {
        match (self.peek_tree(2)) {
            let p: root.proc_macro2.Punct => p.ch == "<",
            _ => false,
        }
    }

    /// Parse `<A, B<C>>` after `::`, returning each argument as raw source
    function parse_generic_args(self) -> string[] throws Error {
        self.expect_punct("<");
        let args: string[] = [];
        let current: string[] = [];
        let depth = 1;
        while (!self.is_empty()) {
            let t = self.peek_tree(0) ?? baml.sys.panic("unreachable");
            self._pos += 1;
            let text = root.proc_macro2.token_tree_to_string(t);
            if (text == "<") {
                depth += 1;
            } else if (text == ">") {
                depth -= 1;
                if (depth == 0) {
                    if (current.length() > 0) { args.push(current.join("")); }
                    return args;
                }
            } else if (text == "," && depth == 1) {
                args.push(current.join(""));
                current = [];
                continue;
            }
            current.push(text);
        }
        throw self.error("unclosed generic arguments")
    }

    function parse_path(self) -> Path throws Error {
        let leading = self.eat_punct("::");
        let segments: PathSegment[] = [];
        segments.push(PathSegment { ident: self.parse_ident(), arguments: [] });
        while (self.peek_punct("::")) {
            if (self.peek_is_lt_after_colons()) {
                self._pos += 2;
                segments[-1].arguments = self.parse_generic_args();
                continue;
            }
            self._pos += 2;
            segments.push(PathSegment { ident: self.parse_ident(), arguments: [] });
        }
        Path { leading_colon: leading, segments: segments }
    }

    function parse_primary(self) -> Expr throws Error {
        let t = self.peek_tree(0);
        match (t) {
            null => throw self.error("expected expression"),
            let l: root.proc_macro2.Literal => {
                self._pos += 1;
                ExprLit { lit: lit_from_literal(l) }
            },
            let g: root.proc_macro2.Group => {
                self._pos += 1;
                match (g.delimiter) {
                    root.proc_macro2.Delimiter.Bracket => ExprArray { elems: parse_comma_exprs(g.stream) },
                    root.proc_macro2.Delimiter.Parenthesis => {
                        let elems = parse_comma_exprs(g.stream);
                        let has_trailing_comma = g.stream.trees.length() > 0 && root.proc_macro2.token_tree_to_string(g.stream.trees[-1]) == ",";
                        if (elems.length() == 1 && !has_trailing_comma) { ExprParen { expr: elems[0] } } else { ExprTuple { elems: elems } }
                    },
                    _ => throw self.error("unsupported block expression"),
                }
            },
            let p: root.proc_macro2.Punct => {
                if (p.ch == "|") {
                    // closure: `|a, b| body`
                    self._pos += 1;
                    let inputs: string[] = [];
                    while (!self.eat_punct("|")) {
                        let name = self.parse_ident();
                        if (self.eat_punct(":")) {
                            // skip a simple type annotation
                            self.parse_ident();
                        }
                        inputs.push(name);
                        self.eat_punct(",");
                    }
                    ExprClosure { inputs: inputs, body: self.parse_expr() }
                } else if (p.ch == ":" || p.ch == "<") {
                    ExprPath { path: self.parse_path() }
                } else {
                    throw self.error("expected expression")
                }
            },
            let i: root.proc_macro2.Ident => {
                if (i.sym == "true" || i.sym == "false") {
                    self._pos += 1;
                    return ExprLit { lit: LitBool { value: i.sym == "true" } };
                }
                let path = self.parse_path();
                if (self.peek_punct("!") && !self.peek_punct("!=")) {
                    // macro invocation: `path!(...)`
                    if let g: root.proc_macro2.Group = self.peek_group_after_bang() {
                        self._pos += 2;
                        return ExprMacro { path: path, tokens: g.stream };
                    }
                }
                ExprPath { path: path }
            },
        }
    }

    function peek_group_after_bang(self) -> root.proc_macro2.Group? {
        match (self.peek_tree(1)) {
            let g: root.proc_macro2.Group => g,
            _ => null,
        }
    }
}

/// Parse a comma-separated list of expressions (with optional trailing comma)
function parse_comma_exprs(stream: root.proc_macro2.TokenStream) -> Expr[] throws Error {
    let input = ParseBuffer.new(stream);
    let out: Expr[] = [];
    while (!input.is_empty()) {
        out.push(input.parse_expr());
        if (!input.is_empty()) {
            input.expect_punct(",");
        }
    }
    out
}
