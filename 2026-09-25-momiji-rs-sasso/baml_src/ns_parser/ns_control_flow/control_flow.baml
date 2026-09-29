// Ported from sasso `src/parser/control_flow.rs` (namespace `root.parser.control_flow`).
//
// `@for` / `@each` / `@while` / `@if`-`@else` control-flow statement
// parsing. Extracted verbatim from [`super`].

interface ParserControlFlow {
    /// `@for $i from <start> through|to <end> { … }`. Bounds are parsed at
    /// the additive level so the `through`/`to` keywords are not swallowed
    /// into a space list.
    function parse_for(self) -> root.ast.Stmt throws unknown;

    /// `@each $v[, $k…] in <list> { … }`.
    function parse_each(self) -> root.ast.Stmt throws unknown;

    /// `@while <cond> { … }`.
    function parse_while(self) -> root.ast.Stmt throws unknown;

    /// Parse an `@if <cond> { … }` with its `@else if` / `@else` chain.
    function parse_if(self) -> root.ast.Stmt throws unknown;
}

implements ParserControlFlow for root.parser.Parser {
    /// `@for $i from <start> through|to <end> { … }`. Bounds are parsed at
    /// the additive level so the `through`/`to` keywords are not swallowed
    /// into a space list.
    function parse_for(self) -> root.ast.Stmt {
        self.skip_ws_inline();
        if (!self.sc.eat("$")) {
            throw root.error.Error.at("expected a variable after @for", self.sc.position());
        }
        let var = self.read_variable_name();
        if (!self.try_keyword("from")) {
            throw root.error.Error.at("expected \"from\"", self.sc.position());
        }
        self.skip_ws_inline();
        // Source-map: the loop variable's definition span is `from`'s.
        let from_pos = self.sc.position();
        let from = self.additive();
        let inclusive = if (self.try_keyword("through")) {
            true
        } else if (self.try_keyword("to")) {
            false
        } else {
            throw root.error.Error.at("expected \"through\" or \"to\"", self.sc.position());
        };
        self.skip_ws_inline();
        let to = self.additive();
        let body = self.parse_braced_body();
        root.ast.Stmt_For {
            var: var,
            from: from,
            to: to,
            inclusive: inclusive,
            body: body,
            from_pos: from_pos,
        }
    }

    /// `@each $v[, $k…] in <list> { … }`.
    function parse_each(self) -> root.ast.Stmt {
        let vars: string[] = [];
        while (true) {
            self.skip_ws_inline();
            if (!self.sc.eat("$")) {
                throw root.error.Error.at("expected a variable after @each", self.sc.position());
            }
            vars.push(self.read_variable_name());
            self.skip_ws_inline();
            if (self.sc.eat(",")) {
                continue;
            }
            break;
        }
        if (!self.try_keyword("in")) {
            throw root.error.Error.at("expected \"in\"", self.sc.position());
        }
        self.skip_ws_inline();
        // Source-map: every `@each` variable's definition span is the list's.
        let list_pos = self.sc.position();
        let list = self.parse_value();
        let body = self.parse_braced_body();
        root.ast.Stmt_Each {
            vars: vars,
            list: list,
            body: body,
            list_pos: list_pos,
        }
    }

    /// `@while <cond> { … }`.
    function parse_while(self) -> root.ast.Stmt {
        self.skip_ws_inline();
        let cond = self.parse_value();
        let body = self.parse_braced_body();
        root.ast.Stmt_While { cond: cond, body: body }
    }

    /// Parse an `@if <cond> { … }` with its `@else if` / `@else` chain.
    function parse_if(self) -> root.ast.Stmt {
        let branches: root.ast.IfBranch[] = [];
        self.skip_ws_inline();
        let cond = self.parse_value();
        let body = self.parse_braced_body();
        branches.push(root.ast.IfBranch {
            cond: cond,
            body: body,
        });
        while (true) {
            let mark = self.sc.mark();
            let discard: root.ast.Stmt[] = [];
            self.skip_trivia(discard);
            if (self.sc.peek() != "@") {
                self.sc.reset(mark);
                break;
            }
            self.sc.bump(); // '@'
            // `@elseif` is a deprecated spelling of `@else if` (dart still
            // accepts it with an [elseif] deprecation warning).
            let kw = self.read_ident_name() catch (e) {
                let _err: root.error.Error => "",
            };
            if (kw == "elseif") {
                self.skip_ws_inline();
                let cond = self.parse_value();
                let body = self.parse_braced_body();
                branches.push(root.ast.IfBranch {
                    cond: cond,
                    body: body,
                });
                continue;
            }
            if (kw != "else") {
                self.sc.reset(mark);
                break;
            }
            if (self.try_keyword("if")) {
                self.skip_ws_inline();
                let cond = self.parse_value();
                let body = self.parse_braced_body();
                branches.push(root.ast.IfBranch {
                    cond: cond,
                    body: body,
                });
            } else {
                let body = self.parse_braced_body();
                branches.push(root.ast.IfBranch { cond: null, body: body });
                break;
            }
        }
        root.ast.Stmt_If { _0: branches }
    }

}
