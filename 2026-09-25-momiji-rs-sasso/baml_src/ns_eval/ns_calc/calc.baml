// Ported from sasso `src/eval/calc.rs` (namespace `root.eval.calc`).

interface EvaluatorCalc {
    /// Serialize a CSS math function (`min`/`max`/`clamp`/…) verbatim inside a
    /// `@supports` declaration: each argument is resolved through the
    /// (non-folding) calc machinery and joined with `, `. Used only when
    /// `in_supports_declaration` is set.
    function eval_supports_calc_func(
        self,
        name: string,
        args: root.ast.CallArg[],
        pos: root.scanner.Pos,
    ) -> root.value.Value throws unknown;

    /// Try to evaluate a single-/double-argument math calculation (`sin`,
    /// `sqrt`, `pow`, `log`, `hypot`, …) as a calculation. Each argument is
    /// evaluated through the calc machinery, which rejects disallowed operators
    /// (`%`, comparisons) the way dart-sass does.
    ///
    /// - When *every* argument folds to a single number, returns `Ok(None)`:
    ///   the caller falls through to the ordinary builtin, which computes the
    ///   result and applies its unit checks (so `sqrt(2)`, `sin(1deg)`,
    ///   `sin(1px)`-the-error all behave exactly as before).
    /// - When an argument still carries an opaque operand — a `var()`,
    ///   interpolation, or unknown identifier — the whole call is preserved as a
    ///   calculation string (`sin(2px + var(--c))`).
    /// - When an argument reduces to a numeric operation we cannot collapse to a
    ///   single number (compound/inverse units), returns `Ok(None)` so the
    ///   builtin re-evaluates and reports its own error, rather than silently
    ///   preserving a value dart-sass would reject.
    function try_eval_calc_math_call(
        self,
        name: string,
        args: root.ast.CallArg[],
        unused_pos: root.scanner.Pos,
    ) -> root.value.Value? throws unknown;

    /// What separates a preserved calculation's arguments: compressed output
    /// takes the space out, exactly as `CalcNode::Func` does for the calls that
    /// reach emit as a typed node rather than as text.
    function calc_arg_sep(self) -> string throws unknown;

    /// Evaluate a three-argument `clamp(min, value, max)` calculation. Each
    /// argument is evaluated through the calc machinery (rejecting `%` and other
    /// non-calculation operators). When every argument folds to a single number,
    /// the builtin clamps/unit-checks them as before; when an argument keeps a
    /// `var()`/calculation operand the call is preserved
    /// (`clamp(1% + 1px, 2px, 3px)`). A resolved operand with complex units is
    /// rejected like dart-sass.
    function try_eval_clamp(
        self,
        args: root.ast.CallArg[],
        pos: root.scanner.Pos,
    ) -> root.value.Value throws unknown;

    /// Evaluate a `calc-size(target, value)` calculation. The target (`auto`,
    /// `none`, `size`, a `var()`, or a nested calculation) and the optional
    /// value are each evaluated through the calc machinery and the call is kept
    /// preserved (`calc-size()` never reduces to a number). Exactly one or two
    /// arguments are accepted.
    function eval_calc_size(
        self,
        args: root.ast.CallArg[],
        pos: root.scanner.Pos,
    ) -> root.value.Value throws unknown;

    /// Evaluate the interior of a `calc()` into a simplified node tree.
    /// Numeric `number <op> number` subtrees with compatible units fold;
    /// everything else (variables, interpolations, incompatible units) is
    /// preserved for canonical serialization, mirroring dart-sass's
    /// "only simplify number+number" rule.
    function eval_calc(self, expr: root.ast.Expr) -> root.value.CalcNode throws unknown;
}

implements EvaluatorCalc for root.eval.Evaluator {
    /// Serialize a CSS math function (`min`/`max`/`clamp`/…) verbatim inside a
    /// `@supports` declaration: each argument is resolved through the
    /// (non-folding) calc machinery and joined with `, `. Used only when
    /// `in_supports_declaration` is set.
    function eval_supports_calc_func(self, name: string, args: root.ast.CallArg[], pos: root.scanner.Pos) -> root.value.Value {
        if (args.some((a) -> { a.splat })) {
            throw root.error.Error.at("Rest arguments can't be used with calculations.", pos);
        }
        let parts: string[] = [];
        for (let a in args) {
            let inner = self.eval_calc(a.value).to_calc_css(self.compressed());
            // A named argument (`min($a: 1)`) is not valid in a calculation, but
            // we preserve any name verbatim to mirror the surface syntax.
            match (a.name) {
                let n: string => {
                    parts.push(`$${n}: ${inner}`);
                }
                null => {
                    parts.push(inner);
                }
            }
        }
        root.value.Value_Str {
            _0: root.value.SassStr {
                text: `${name}(${parts.join(", ")})`,
                quoted: false,
            },
        }
    }

    /// Try to evaluate a single-/double-argument math calculation (`sin`,
    /// `sqrt`, `pow`, `log`, `hypot`, …) as a calculation. Each argument is
    /// evaluated through the calc machinery, which rejects disallowed operators
    /// (`%`, comparisons) the way dart-sass does.
    ///
    /// - When *every* argument folds to a single number, returns `Ok(None)`:
    ///   the caller falls through to the ordinary builtin, which computes the
    ///   result and applies its unit checks (so `sqrt(2)`, `sin(1deg)`,
    ///   `sin(1px)`-the-error all behave exactly as before).
    /// - When an argument still carries an opaque operand — a `var()`,
    ///   interpolation, or unknown identifier — the whole call is preserved as a
    ///   calculation string (`sin(2px + var(--c))`).
    /// - When an argument reduces to a numeric operation we cannot collapse to a
    ///   single number (compound/inverse units), returns `Ok(None)` so the
    ///   builtin re-evaluates and reports its own error, rather than silently
    ///   preserving a value dart-sass would reject.
    function try_eval_calc_math_call(self, name: string, args: root.ast.CallArg[], unused_pos: root.scanner.Pos) -> root.value.Value? {
        let nodes: root.value.CalcNode[] = [];
        for (let a in args) {
            nodes.push(self.eval_calc(a.value));
        }
        // Every argument is a plain number: let the builtin compute.
        if (nodes.every((n) -> { n is root.value.CalcNode_Number })) {
            return null;
        }
        // No opaque operand anywhere: the calculation is purely numeric but did
        // not collapse (compound/inverse units). Defer to the builtin so it can
        // raise the dart-sass error instead of us preserving an invalid value.
        if (!nodes.some((n) -> { root.eval.calc_node_has_opaque(n) })) {
            return null;
        }
        let lname = root.std.ascii_lower(name);
        let compressed = self.compressed();
        let parts: string[] = nodes.map((n) -> { n.to_calc_css(compressed) });
        root.value.Value_Str {
            _0: root.value.SassStr {
                text: `${lname}(${parts.join(self.calc_arg_sep())})`,
                quoted: false,
            },
        }
    }

    /// What separates a preserved calculation's arguments: compressed output
    /// takes the space out, exactly as `CalcNode::Func` does for the calls that
    /// reach emit as a typed node rather than as text.
    function calc_arg_sep(self) -> string {
        if (self.compressed()) {
            ","
        } else {
            ", "
        }
    }

    /// Evaluate a three-argument `clamp(min, value, max)` calculation. Each
    /// argument is evaluated through the calc machinery (rejecting `%` and other
    /// non-calculation operators). When every argument folds to a single number,
    /// the builtin clamps/unit-checks them as before; when an argument keeps a
    /// `var()`/calculation operand the call is preserved
    /// (`clamp(1% + 1px, 2px, 3px)`). A resolved operand with complex units is
    /// rejected like dart-sass.
    function try_eval_clamp(self, args: root.ast.CallArg[], pos: root.scanner.Pos) -> root.value.Value {
        let nodes: root.value.CalcNode[] = [];
        for (let a in args) {
            let node = self.eval_calc(a.value);
            if let complex: root.value.CalcNode = root.eval.calc_complex_unit_operand(node) {
                throw root.error.Error.at(
                    `Number calc(${complex.to_calc_css(false)}) isn't compatible with CSS calculations.`,
                    pos,
                );
            }
            nodes.push(node);
        }
        // Every argument is a plain number: let the builtin clamp them (and run
        // its incompatible-unit and complex-unit checks).
        if (nodes.every((n) -> { n is root.value.CalcNode_Number })) {
            let values: root.value.Value[] = nodes.map((n: root.value.CalcNode) -> root.value.Value {
                match (n) {
                    let num: root.value.CalcNode_Number => root.value.Value_Number { _0: num._0 },
                    // Unreachable: guarded by the `all` check above.
                    let other: root.value.CalcNode => root.value.Value_Calc { _0: other },
                }
            });
            return root.builtins.call("clamp", values, [], pos);
        }
        let compressed = self.compressed();
        let parts: string[] = nodes.map((n) -> { n.to_calc_css(compressed) });
        root.value.Value_Str {
            _0: root.value.SassStr {
                text: `clamp(${parts.join(self.calc_arg_sep())})`,
                quoted: false,
            },
        }
    }

    /// Evaluate a `calc-size(target, value)` calculation. The target (`auto`,
    /// `none`, `size`, a `var()`, or a nested calculation) and the optional
    /// value are each evaluated through the calc machinery and the call is kept
    /// preserved (`calc-size()` never reduces to a number). Exactly one or two
    /// arguments are accepted.
    function eval_calc_size(self, args: root.ast.CallArg[], pos: root.scanner.Pos) -> root.value.Value {
        if (args.length() == 0) {
            throw root.error.Error.at("Missing argument.", pos);
        }
        if (args.length() > 2) {
            throw root.error.Error.at(
                `Only 2 arguments allowed, but ${args.length()} were passed.`,
                pos,
            );
        }
        let parts: string[] = [];
        for (let a in args) {
            parts.push(self.eval_calc(a.value).to_calc_css(self.compressed()));
        }
        root.value.Value_Str {
            _0: root.value.SassStr {
                text: `calc-size(${parts.join(self.calc_arg_sep())})`,
                quoted: false,
            },
        }
    }

    /// Evaluate the interior of a `calc()` into a simplified node tree.
    /// Numeric `number <op> number` subtrees with compatible units fold;
    /// everything else (variables, interpolations, incompatible units) is
    /// preserved for canonical serialization, mirroring dart-sass's
    /// "only simplify number+number" rule.
    function eval_calc(self, expr: root.ast.Expr) -> root.value.CalcNode {
        match (expr) {
            let b: root.ast.Expr_Binary => {
                let calc_op: root.value.CalcOp = match (b.op) {
                    root.ast.BinOp.Add => root.value.CalcOp.Add,
                    root.ast.BinOp.Sub => root.value.CalcOp.Sub,
                    root.ast.BinOp.Mul => root.value.CalcOp.Mul,
                    // Modulo, comparisons, and `and`/`or` are not arithmetic;
                    // dart-sass rejects them inside a calculation rather than
                    // evaluating them (`calc(1px % 2px)`, `calc(1 > 2)`).
                    _ => {
                        throw root.error.Error.at("This operation can't be used in a calculation.", b.pos);
                    }
                };
                let l = self.eval_calc(b.lhs);
                let r = self.eval_calc(b.rhs);
                if (self.in_supports_declaration) {
                    return root.value.CalcNode_Op {
                        op: calc_op,
                        left: l,
                        right: r,
                    };
                }
                root.eval.fold_calc(calc_op, l, r, b.pos)
            }
            let d: root.ast.Expr_Div => {
                let l = self.eval_calc(d.lhs);
                let r = self.eval_calc(d.rhs);
                if (self.in_supports_declaration) {
                    return root.value.CalcNode_Op {
                        op: root.value.CalcOp.Div,
                        left: l,
                        right: r,
                    };
                }
                root.eval.fold_calc(root.value.CalcOp.Div, l, r, d.pos)
            }
            root.ast.Expr_Unary { op: root.ast.UnOp.Neg, operand: let operand } => {
                let node = self.eval_calc(operand);
                match (node) {
                    let n: root.value.CalcNode_Number => root.value.CalcNode_Number { _0: n._0.copy_units(-n._0.value) },
                    let other: root.value.CalcNode => root.value.CalcNode_Op {
                        op: root.value.CalcOp.Mul,
                        left: root.value.CalcNode_Number { _0: root.value.Number.unitless(-1.0) },
                        right: other,
                    },
                }
            }
            // Parentheses around a single opaque operand (a `var()`,
            // identifier, or interpolation) are preserved verbatim; around a
            // number or an operation they are redundant and dropped (operator
            // precedence reintroduces them where needed).
            let p: root.ast.Expr_Paren => {
                let node = self.eval_calc(p._0);
                match (node) {
                    let s: root.value.CalcNode_Str => root.value.CalcNode_Str { _0: `(${s._0})` },
                    let other: root.value.CalcNode => other,
                }
            }
            // A nested calc() flattens into the surrounding calculation —
            // except inside a `@supports` declaration, where dart-sass keeps the
            // calculation unsimplified, so the inner `calc(...)` stays wrapped.
            // Otherwise an unresolved single-string operand (an interpolation or
            // a `var()` substitution that is not a clean operand) is
            // parenthesized: dart-sass writes `calc(calc(#{"c*"}))` as
            // `calc((c*))` and `calc(1 + calc(var(--c)))` as `calc(1 +
            // (var(--c)))`. A clean identifier, number, operation, or complete
            // sub-calculation flattens without extra parens.
            let c: root.ast.Expr_Calc => {
                if (self.in_supports_declaration) {
                    let s = self.eval_calc(c.inner).to_calc_css(self.compressed());
                    return root.value.CalcNode_Str { _0: `calc(${s})` };
                }
                let node = self.eval_calc(c.inner);
                match (node) {
                    let s: root.value.CalcNode_Str if root.eval.nested_calc_needs_parens(s._0) => root.value.CalcNode_Str { _0: `(${s._0})` },
                    let other: root.value.CalcNode => other,
                }
            }
            // A space-separated list written directly in the calc interior is
            // an "unparsed" run: it is only valid when it contains a `var()`/
            // `env()` substitution, an interpolation, or a variable holding an
            // unquoted string — all of which dart-sass splices verbatim
            // (`calc(var(--c) 1)`, `calc(#{"1 +"} 2)` -> `calc(1 + 2)`,
            // `calc(1 $c)` with `$c: unquote("+ 2")` -> `calc(1 + 2)`). A
            // space-list of ordinary operands (`calc(1 2)`, `calc(c 1 2)`) or
            // of number-valued variables (`calc(1 $n)`) has no operator
            // between adjacent terms: "Missing math operator.".
            root.ast.Expr_List {
                items: let items,
                sep: root.value.ListSep.Space,
                bracketed: false,
            } => {
                let has_subst = items.some((e) -> { root.eval.expr_has_substitution(e) });
                if (!has_subst
                    && !items
                        .some((e) -> { e is root.ast.Expr_Var || e is root.ast.Expr_NsVar })) {
                    throw root.error.Error.unpositioned("Missing math operator.");
                }
                let parts: string[] = [];
                let any_str = false;
                for (let it in items) {
                    let node = self.eval_calc(it);
                    if (node is root.value.CalcNode_Str) {
                        any_str = true;
                    }
                    parts.push(node.to_calc_css(false));
                }
                // Variables alone only justify the splice when at least one
                // resolved to raw text.
                if (!has_subst && !any_str) {
                    throw root.error.Error.unpositioned("Missing math operator.");
                }
                root.value.CalcNode_Str { _0: root.std.join(parts, " ") }
            }
            // Any leaf (number, var(), interpolation, ident) evaluates to a
            // value and becomes a calc operand.
            let other: root.ast.Expr => {
                let v = self.eval_expr(other);
                // The calc constants `pi`/`e`/`infinity`/`-infinity`/`nan`
                // (case-insensitive) resolve to their numeric values inside a
                // calculation, so `calc(infinity * 2)` folds to `calc(infinity)`
                // and `calc(NaN)` canonicalizes its spelling.
                if let s: root.value.Value_Str = v {
                    if (!s._0.quoted) {
                        if let value: float = root.eval.calc_constant(s._0.text) {
                            return root.value.CalcNode_Number { _0: root.value.Number.unitless(value) };
                        }
                    }
                }
                // Only a number, a nested calculation, or an unquoted string
                // (a `var()`, interpolation, ident, or other special CSS value)
                // is a legal calculation operand. A null, bool, color, list,
                // map, or quoted string evaluated into the calc — typically via
                // a `$variable` or function call — is rejected the way
                // dart-sass does ("Value … can't be used in a calculation.").
                match (v) {
                    root.value.Value_Number {} | root.value.Value_Calc {} | root.value.Value_Slash {} => {}
                    root.value.Value_Str { _0: root.value.SassStr { quoted: false } } => {}
                    let bad: root.value.Value => {
                        throw root.error.Error.unpositioned(
                            `Value ${root.eval.calc_value_repr(bad)} can't be used in a calculation.`,
                        );
                    }
                }
                root.eval.value_to_calc_node(v)
            }
        }
    }

}
