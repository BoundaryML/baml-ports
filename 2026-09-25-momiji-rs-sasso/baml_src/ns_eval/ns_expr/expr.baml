// Ported from sasso `src/eval/expr.rs` (namespace `root.eval.expr`).

/// Where each `#{…}` in a template landed in its output: `(char start, char
/// length)`, in source order. A template with a single interpolation — `.item-#{$i}`
/// and every selector shaped like it — keeps its one range inline, because a
/// vector for it would be an allocation per style rule on the path that resolves
/// every selector in the sheet.
interface InterpBounds {
    // PORT: Rust's `push(&mut self, b)` reassigns `*self`; BAML cannot, so it
    // returns the new value and the caller assigns it (`bounds = bounds.push(b)`).
    function push(self, b: root.std.Tuple2<int, int>) -> InterpBounds throws never {
        match (self) {
            InterpBounds_None {} => InterpBounds_One { _0: b },
            InterpBounds_One { _0: let first } => InterpBounds_Many { _0: [first, b] },
            let m: InterpBounds_Many => {
                m._0.push(b);
                m
            },
            _ => root.std.unreachable(),
        }
    }

    function as_slice(self) -> root.std.Tuple2<int, int>[] throws never {
        match (self) {
            InterpBounds_None {} => [],
            InterpBounds_One { _0: let b } => [b],
            InterpBounds_Many { _0: let v } => v,
            _ => root.std.unreachable(),
        }
    }
}

class InterpBounds_None {
    implements InterpBounds {}
}

class InterpBounds_One {
    _0: root.std.Tuple2<int, int>,
    implements InterpBounds {}
}

class InterpBounds_Many {
    _0: root.std.Tuple2<int, int>[],
    implements InterpBounds {}
}

/// How many bytes one `#{…}` is assumed to contribute when a template's buffer
/// is sized: what a serialized value usually is — a short identifier, a number
/// with a unit, a hex color. Only an estimate; the buffer still grows if an
/// interpolation turns out longer.
function INTERP_ALLOWANCE() -> int {
    8
}

/// Room for a template's output: every literal byte, plus an allowance for each
/// interpolation. A template is built by pushing onto a `String`, and one that
/// starts empty takes the allocator's minimum block and then regrows — twice for
/// a selector or a value list of any length. Sizing it up front trades a walk
/// over a handful of pieces for those copies, on a path that runs for every
/// selector, property name and interpolated value in the sheet.
// PORT: `t.len()` (bytes) → `t.length()` (chars); the result is only a
// capacity hint.
function template_capacity(pieces: root.ast.TplPiece[]) -> int {
    pieces
        .map((piece: root.ast.TplPiece) -> int {
            match (piece) {
                root.ast.TplPiece_Lit { _0: let t } => t.length(),
                root.ast.TplPiece_Interp {} => INTERP_ALLOWANCE(),
                _ => root.std.unreachable(),
            }
        })
        .reduce(
            (acc: int, n: int) -> int {
                acc + n
            },
            0,
        )
}

interface EvaluatorExpr {
    // ---- templates & expressions ------------------------------------
    function eval_template(self, pieces: root.ast.TplPiece[]) -> string throws unknown;

    /// The template's text as a shared string. A template that is a single
    /// literal piece — every `color`, every `solid`, every `.card` — already has
    /// its text in the AST, and this hands that buffer out rather than copying
    /// it, so the string it becomes costs a refcount bump. Anything with
    /// interpolation in it has to be built, and pays one buffer for the result
    /// exactly as before.
    function eval_template_shared(self, pieces: root.ast.TplPiece[]) -> string throws unknown;

    /// Like [`Self::eval_template`], additionally returning each `Interp`
    /// piece's (char start, char length) range in the output — used to decide
    /// whether a resolved-selector error column falls inside interpolated
    /// text (the dual-span "error in interpolated output" diagnostic).
    ///
    /// The text is borrowed from the AST when the template is a single literal —
    /// the shape of nearly every selector — which is why it is a [`Cow`]: that
    /// case has nothing to build and no interpolation to record, so it costs
    /// neither the buffer nor the bounds vector.
    function eval_template_bounds(
        self,
        pieces: root.ast.TplPiece[],
    ) -> root.std.Tuple2<string, InterpBounds> throws unknown;

    /// The value of `&` in value position: the current resolved selector list
    /// as a comma-separated Sass list where each item is one complex selector
    /// (a space-separated list of compound-selector strings). At the document
    /// root (no enclosing style rule) this is `null`. This matches dart-sass,
    /// where `&` is always a comma list even for a single selector.
    function parent_selector_value(self) -> root.value.Value throws unknown;

    function eval_expr(self, expr: root.ast.Expr) -> root.value.Value throws unknown;

    function eval_expr_inner(self, expr: root.ast.Expr) -> root.value.Value throws unknown;
}

implements EvaluatorExpr for root.eval.Evaluator {
    // ---- templates & expressions ------------------------------------
    function eval_template(self, pieces: root.ast.TplPiece[]) -> string {
        let s = root.std.StrBuf.with_capacity(template_capacity(pieces));
        for (let piece in pieces) {
            match (piece) {
                root.ast.TplPiece_Lit { _0: let t } => s.push_str(t),
                root.ast.TplPiece_Interp { _0: let e } => {
                    let v = self.eval_expr(e);
                    root.eval.interp_checked_into(s, v);
                },
                _ => root.std.unreachable(),
            }
        }
        s.as_str()
    }

    /// The template's text as a shared string. A template that is a single
    /// literal piece — every `color`, every `solid`, every `.card` — already has
    /// its text in the AST, and this hands that buffer out rather than copying
    /// it, so the string it becomes costs a refcount bump. Anything with
    /// interpolation in it has to be built, and pays one buffer for the result
    /// exactly as before.
    function eval_template_shared(self, pieces: root.ast.TplPiece[]) -> string {
        if (pieces.length() == 1) {
            if let lit: root.ast.TplPiece_Lit = pieces[0] {
                return lit._0;
            }
        }
        self.eval_template(pieces)
    }

    /// Like [`Self::eval_template`], additionally returning each `Interp`
    /// piece's (char start, char length) range in the output — used to decide
    /// whether a resolved-selector error column falls inside interpolated
    /// text (the dual-span "error in interpolated output" diagnostic).
    ///
    /// The text is borrowed from the AST when the template is a single literal —
    /// the shape of nearly every selector — which is why it is a [`Cow`]: that
    /// case has nothing to build and no interpolation to record, so it costs
    /// neither the buffer nor the bounds vector.
    function eval_template_bounds(self, pieces: root.ast.TplPiece[]) -> root.std.Tuple2<string, InterpBounds> {
        if (pieces.length() == 1) {
            if let lit: root.ast.TplPiece_Lit = pieces[0] {
                return root.std.Tuple2<string, InterpBounds> { _0: lit._0, _1: InterpBounds_None {} };
            }
        }
        // One walk sizes both buffers up front, so neither the text nor the
        // ranges reallocate: a generated selector can carry a dozen
        // interpolations. See [`template_capacity`] for the text estimate.
        let interps = 0;
        let capacity = 0;
        for (let piece in pieces) {
            match (piece) {
                root.ast.TplPiece_Lit { _0: let t } => {
                    capacity += t.length();
                },
                root.ast.TplPiece_Interp {} => {
                    interps += 1;
                    capacity += INTERP_ALLOWANCE();
                },
                _ => root.std.unreachable(),
            }
        }
        let s = root.std.StrBuf.with_capacity(capacity);
        let chars = 0;
        let bounds: InterpBounds = if (interps > 1) {
            InterpBounds_Many { _0: [] }
        } else {
            InterpBounds_None {}
        };
        for (let piece in pieces) {
            match (piece) {
                root.ast.TplPiece_Lit { _0: let t } => {
                    s.push_str(t);
                    chars += t.length();
                },
                root.ast.TplPiece_Interp { _0: let e } => {
                    let v = self.eval_expr(e);
                    // Written into the output first, then measured there: the
                    // range is what the interpolation occupies in `s`, which is
                    // the same count either way and one buffer cheaper.
                    let at = s.len();
                    root.eval.interp_checked_into(s, v);
                    // PORT: `s[at..].chars().count()` — the buffer counts chars.
                    let len = s.len() - at;
                    bounds = bounds.push(root.std.Tuple2<int, int> { _0: chars, _1: len });
                    chars += len;
                },
                _ => root.std.unreachable(),
            }
        }
        root.std.Tuple2<string, InterpBounds> { _0: s.as_str(), _1: bounds }
    }

    /// The value of `&` in value position: the current resolved selector list
    /// as a comma-separated Sass list where each item is one complex selector
    /// (a space-separated list of compound-selector strings). At the document
    /// root (no enclosing style rule) this is `null`. This matches dart-sass,
    /// where `&` is always a comma list even for a single selector.
    function parent_selector_value(self) -> root.value.Value {
        let selectors = self.current_selector;
        if (selectors == null) {
            return root.value.Value_Null {};
        }
        if (selectors.length() == 0) {
            return root.value.Value_Null {};
        }
        let items: root.value.Value[] = selectors.map((complex: string) -> root.value.Value {
            // Every complex selector is a SPACE LIST of compounds (dart:
            // `meta.type-of(list.nth(&, 1))` is `list` even for `.foo`).
            let compounds: root.value.Value[] = root.std.split_whitespace(complex).map((c: string) -> root.value.Value {
                root.value.Value_Str {
                    _0: root.value.SassStr {
                        text: c,
                        quoted: false,
                    },
                }
            });
            root.value.Value_List {
                _0: root.value.List {
                    items: compounds,
                    sep: root.value.ListSep.Space,
                    bracketed: false,
                    keywords: null,
                },
            }
        });
        root.value.Value_List {
            _0: root.value.List {
                items: items,
                sep: root.value.ListSep.Comma,
                bracketed: false,
                keywords: null,
            },
        }
    }

    function eval_expr(self, expr: root.ast.Expr) -> root.value.Value {
        // Finalize any positioned error into a rendered diagnostic block here,
        // where `current_url`/`current_source`/`call_stack` still describe the
        // file and call context the error was raised in (cross-file safe).
        self.eval_expr_inner(expr) catch (e) {
            let err: root.error.Error => {
                throw self.finalize_error(err);
            }
        }
    }

    function eval_expr_inner(self, expr: root.ast.Expr) -> root.value.Value {
        match (expr) {
            root.ast.Expr_Number { _0: let v, _1: let unit } => root.value.Value_Number { _0: root.value.Number.with_shared_unit(v, unit) },
            root.ast.Expr_Color { _0: let c } => root.value.Value_Color { _0: root.value.Color { ...c } },
            root.ast.Expr_Bool { _0: let b } => root.value.Value_Bool { _0: b },
            root.ast.Expr_Null {} => root.value.Value_Null {},
            root.ast.Expr_Parent {} => self.parent_selector_value(),
            // Reading a variable drops a bare slash-division's spelling
            // (dart-sass `withoutSlash`): `$x: 1/2; a {b: $x}` is `0.5`.
            // Slashes nested inside a stored list are preserved.
            root.ast.Expr_Var { name: let name, pos: let pos } => match (self.lookup(name)) {
                // `lookup` already returns an owned clone out of the scope;
                // `without_slash` consumes it, so a second clone is wasted.
                let v: root.value.Value => v.without_slash(),
                null => {
                    // A user module variable exposed unprefixed via `@use … as *`.
                    let star_hits: root.value.Value[] = if (root.eval.is_private_member(name)) {
                        []
                    } else {
                        self.star_user_modules.filter_map((m: root.eval.Module) -> root.value.Value? { m.var(name) })
                    };
                    // A built-in module variable exposed unprefixed the same
                    // way (`$pi` from `sass:math`, directly or through a user
                    // module that forwards it) competes for the same bare name.
                    let builtin_hits = self.star_builtin_hits(name, root.eval.MemberKind.Variable);
                    if (star_hits.length() + builtin_hits.length() > 1) {
                        throw root.error.Error.at(
                            "This variable is available from multiple global modules.",
                            pos,
                        );
                    }
                    let star_first = star_hits.at(0);
                    if (star_first != null) {
                        return star_first.without_slash();
                    }
                    let builtin_first = builtin_hits.at(0);
                    if (builtin_first != null) {
                        let owner = builtin_first._0;
                        let bare = builtin_first._1;
                        return root.builtins.module_var(owner, bare, pos);
                    }
                    // The caret covers `$name` (the `$` plus the identifier).
                    // PORT: `name.len()` is a byte length (the caret is in source bytes).
                    throw root.error.Error.at("Undefined variable.", pos).with_length(1 + name.byte_length());
                },
            },
            root.ast.Expr_NsVar {
                module: let module,
                name: let name,
                pos: let pos,
                length: let length,
            } => self
                .eval_module_var(module, name, pos) catch (e) {
                    let err: root.error.Error => {
                        throw err.with_length(length);
                    }
                },
            // A string expression (quoted/unquoted/lone-interpolation) resolves
            // its interpolation in a context where the `@supports`-declaration
            // no-simplify flag is OFF, so `(a: #{calc(1 + 2)})` -> `(a: 3)`
            // (the interpolated calc simplifies), matching dart-sass
            // `visitStringExpression`.
            // PORT: Rust restores the flag before `text?` propagates an error;
            // here the restore is a `defer` around the evaluation.
            root.ast.Expr_QuotedString { _0: let pieces } => {
                let saved = self.in_supports_declaration;
                self.in_supports_declaration = false;
                let text = {
                    defer {
                        self.in_supports_declaration = saved;
                    }
                    self.eval_template_shared(pieces)
                };
                root.value.Value_Str {
                    _0: root.value.SassStr {
                        text: text,
                        quoted: true,
                    },
                }
            },
            root.ast.Expr_Ident { _0: let pieces } => {
                let saved = self.in_supports_declaration;
                self.in_supports_declaration = false;
                let text = {
                    defer {
                        self.in_supports_declaration = saved;
                    }
                    self.eval_template_shared(pieces)
                };
                root.value.Value_Str {
                    _0: root.value.SassStr {
                        text: text,
                        quoted: false,
                    },
                }
            },
            root.ast.Expr_Interp { _0: let inner } => {
                let saved = self.in_supports_declaration;
                self.in_supports_declaration = false;
                let v = {
                    defer {
                        self.in_supports_declaration = saved;
                    }
                    self.eval_expr(inner)
                };
                // A map or empty list has no CSS serialization, so it cannot be
                // interpolated (`#{(a: 1)}`, `#{()}`); dart-sass errors instead
                // of injecting the inspected/empty text.
                root.value.Value_Str {
                    _0: root.value.SassStr {
                        text: root.eval.interp_checked(v),
                        quoted: false,
                    },
                }
            },
            root.ast.Expr_ModernIf { _0: let clauses } => self.eval_modern_if(clauses),
            // Parentheses force the deprecated slash to perform real
            // division: `(1/2)` is `0.5`, not the slash value `1/2`.
            root.ast.Expr_Paren { _0: let inner } => self.eval_expr(inner).without_slash(),
            root.ast.Expr_List {
                items: let items,
                sep: let sep,
                bracketed: let bracketed,
            } => {
                let vals: root.value.Value[] = [];
                for (let it in items) {
                    vals.push(self.eval_expr(it));
                }
                root.value.Value_List {
                    _0: root.value.List {
                        items: vals,
                        sep: sep,
                        bracketed: bracketed,
                        keywords: null,
                    },
                }
            },
            root.ast.Expr_Map { _0: let entries } => {
                let map = root.value.Map {
                    entries: [],
                };
                for (let entry in entries) {
                    let k = entry._0;
                    let v = entry._1;
                    let key = self.eval_expr(k).without_slash();
                    let val = self.eval_expr(v);
                    // A duplicate literal key is an error in dart-sass.
                    if (map.get(key) != null) {
                        throw root.error.Error.unpositioned("Duplicate key.");
                    }
                    map.insert(key, val);
                }
                root.value.Value_Map { _0: map }
            },
            root.ast.Expr_Unary { op: let op, operand: let operand } => {
                let v = self.eval_expr(operand).without_slash();
                match (op) {
                    // Unary minus negates a number; on any other operand
                    // dart-sass produces an unquoted `-<value>` string
                    // (`- red` -> `-red`, `- "q"` -> `-"q"`). A calculation that
                    // could not reduce to a number has no negation operator, so
                    // dart-sass rejects it ("Undefined operation \"-calc(…)\".").
                    root.ast.UnOp.Neg => match (v) {
                        root.value.Value_Number { _0: let n } => root.value.Value_Number { _0: n.copy_units(-n.value) },
                        root.value.Value_Calc {} => throw root.error.Error.unpositioned(
                            `Undefined operation "-${v.to_css(false)}".`,
                        ),
                        // A map or empty list cannot be serialized into the
                        // unquoted `-<value>` string dart-sass produces, so it
                        // errors before the join (`-(a: 1)`, `-()`).
                        let other => match (root.eval.css_value_error_msg(other)) {
                            let msg: string => throw root.error.Error.unpositioned(msg),
                            null => root.value.Value_Str {
                                _0: root.value.SassStr {
                                    text: `-${other.to_css(false)}`,
                                    quoted: false,
                                },
                            },
                        },
                    },
                    // Unary plus is numeric identity; on any other operand it
                    // prepends `+` as an unquoted string (`+foo` -> `+foo`). A
                    // residual calculation has no unary-plus operator and is
                    // rejected the same way.
                    root.ast.UnOp.Plus => match (v) {
                        root.value.Value_Number {} => v,
                        root.value.Value_Calc {} => throw root.error.Error.unpositioned(
                            `Undefined operation "+${v.to_css(false)}".`,
                        ),
                        // As with unary `-`, a map or empty list has no CSS
                        // serialization to prepend `+` to (`+(a: 1)`, `+()`).
                        let other => match (root.eval.css_value_error_msg(other)) {
                            let msg: string => throw root.error.Error.unpositioned(msg),
                            null => root.value.Value_Str {
                                _0: root.value.SassStr {
                                    text: `+${other.to_css(false)}`,
                                    quoted: false,
                                },
                            },
                        },
                    },
                    root.ast.UnOp.Not => root.value.Value_Bool { _0: !v.is_truthy() },
                }
            },
            root.ast.Expr_Binary { op: let op, lhs: let lhs, rhs: let rhs, pos: let pos } => {
                // `and`/`or` short-circuit and yield a value, so the
                // right operand is only evaluated when needed.
                let l = self.eval_expr(lhs);
                match (op) {
                    root.ast.BinOp.And => {
                        if (l.is_truthy()) {
                            self.eval_expr(rhs)
                        } else {
                            l
                        }
                    },
                    root.ast.BinOp.Or => {
                        if (l.is_truthy()) {
                            l
                        } else {
                            self.eval_expr(rhs)
                        }
                    },
                    _ => {
                        let r = self.eval_expr(rhs);
                        root.eval.binop.eval_binary(op, l.without_slash(), r.without_slash(), pos)
                    },
                }
            },
            root.ast.Expr_Div {
                lhs: let lhs,
                rhs: let rhs,
                slash: let slash,
                pos: let pos,
            } => {
                let l = self.eval_expr(lhs);
                let r = self.eval_expr(rhs);
                root.eval.binop.eval_div(l, r, slash, pos)
            },
            root.ast.Expr_Calc { inner: let inner } => {
                // dart resolves user functions BEFORE calculation semantics: a
                // user-defined `@function calc(...)` shadows the CSS
                // calculation (issue_1706), receiving the argument evaluated
                // as an ordinary expression. Vendor-prefixed `-x-calc(` stays
                // a parse-time special function and can't be overridden.
                if (!self.in_plain_css) {
                    let callable = self.lookup_function("calc");
                    if (callable != null) {
                        let arg = self.eval_expr(inner).without_slash();
                        let f = root.value.SassFunction {
                            name: "calc",
                            css: false,
                            module: null,
                            user: callable,
                        };
                        let no_named: root.std.Tuple2<string, root.value.Value>[] = [];
                        return self
                            .invoke_function_ref(f, [arg], no_named, root.scanner.Pos { line: 0, col: 0 }, 0)
                            .without_slash();
                    }
                }
                let node = self.eval_calc(inner);
                // Inside a `@supports` declaration the calculation is kept
                // unsimplified: the `calc()` wrapper is always preserved (even
                // around a single number), matching dart-sass `simplify: false`.
                if (self.in_supports_declaration) {
                    return root.value.Value_Calc { _0: node };
                }
                // A calculation that reduces to a single finite number unwraps
                // to it; a non-finite result (infinity/NaN) stays a
                // calculation so it serializes as `calc(infinity)` etc., and
                // anything still containing an operation stays a calculation.
                match (node) {
                    // A calculation that reduces to a single number unwraps to
                    // it — including a non-finite result (dart-sass:
                    // `meta.type-of(calc(NaN)) == number`); the Number's own
                    // serialization restores the `calc(NaN)`/`calc(infinity *
                    // 1px)` spelling.
                    root.value.CalcNode_Number { _0: let n } => root.value.Value_Number { _0: n },
                    // `calc()` wrapping a single already-complete calculation
                    // (`calc(min(1%, 2px))`, `calc(clamp(…))`, etc.) is
                    // redundant: dart-sass drops the outer `calc()` and emits
                    // the inner calculation directly. (A non-calculation leaf
                    // such as `calc(var(--x))` keeps its wrapper.)
                    root.value.CalcNode_Str { _0: let s } if root.eval.is_complete_calculation(s) => root.value.Value_Str {
                        _0: root.value.SassStr {
                            text: s,
                            quoted: false,
                        },
                    },
                    let other => root.value.Value_Calc { _0: other },
                }
            },
            // An interpolated-name call is a *plain CSS* function (dart-sass
            // `PlainCssCallable`): the resolved name is never dispatched to a
            // built-in or user function; the arguments evaluate and the call
            // serializes verbatim. Keyword arguments are rejected.
            root.ast.Expr_InterpFunc { name: let name, args: let args, pos: let pos } => {
                let fname = self.eval_template(name);
                if (args.some((a: root.ast.CallArg) -> bool { a.name != null })) {
                    throw root.error.Error.at(
                        "Plain CSS functions don't support keyword arguments.",
                        pos,
                    );
                }
                let parts: string[] = [];
                for (let a in args) {
                    // As on the ordinary plain-CSS call path: the result is a
                    // STRING, and dart builds one with the default style
                    // whatever the output style is.
                    let v = self.eval_expr(a.value);
                    parts.push(v.to_css(false));
                }
                root.value.Value_Str {
                    _0: root.value.SassStr {
                        text: `${fname}(${parts.join(", ")})`,
                        quoted: false,
                    },
                }
            },
            root.ast.Expr_Func {
                name: let name,
                args: let args,
                pos: let pos,
                length: let length,
                module: let module,
            } => {
                // A namespaced call `ns.fn(...)` resolves only against the used
                // built-in module bound to `ns`.
                if (module != null) {
                    return self.eval_module_call(module, name, args, pos, length);
                }
                // In a plain-CSS module no function is invoked (dart-sass
                // `plainCss` looks none up): the call re-serializes verbatim
                // with its arguments evaluated. CSS calculations (min/max/…)
                // still simplify through their normal paths below.
                if (self.in_plain_css
                    && !root.eval.is_supports_calc_function(name)
                    && !root.std.eq_ignore_ascii_case(name, "calc")
                    && !args.some((a: root.ast.CallArg) -> bool { a.splat || a.name != null }))
                {
                    let parts: string[] = [];
                    for (let a in args) {
                        // The call becomes a STRING here, and dart builds that
                        // string with the default style whatever the output
                        // style is — so `rgb(0.5, 2, 3)` keeps its zero and its
                        // `, ` even when compressing.
                        parts.push(self.eval_expr(a.value).to_css(false));
                    }
                    return root.value.Value_Str {
                        _0: root.value.SassStr {
                            text: `${name}(${parts.join(", ")})`,
                            quoted: false,
                        },
                    };
                }
                // Resolve a user `@function` of this name ONCE (it was probed
                // 6+ times along this arm). A `--`-prefixed call is always plain
                // CSS (dart reserves it for custom functions), so it never binds
                // to a user function even though `@function __a` would normalize
                // to the same `--a` key. Every later "no user override" guard
                // reuses `has_user_fn`.
                let user_fn: root.eval.UserCallable? = if (name.starts_with("--")) {
                    null
                } else {
                    self.lookup_function(name)
                };
                let has_user_fn = user_fn != null;
                // Inside a `@supports` declaration, a CSS math function
                // (`min`/`max`/`clamp`/…) is kept unsimplified: its arguments
                // are resolved through the (non-folding) calc machinery and the
                // call is serialized verbatim, matching dart-sass
                // `simplify: false`. A user-defined function of the same name
                // still wins, so this only applies to builtins.
                if (self.in_supports_declaration && root.eval.is_supports_calc_function(name) && !has_user_fn) {
                    return self.eval_supports_calc_func(name, args, pos);
                }
                // if() is lazy: only the selected branch is evaluated. (Its
                // `[if-function]` deprecation is raised when the FILE is
                // parsed, not here — see `warn_import_rules`.)
                if (name == "if") {
                    return self.eval_if_function(args, pos);
                }
                // User-defined @function takes precedence over builtins.
                if (user_fn != null) {
                    return self.call_function(user_fn, args, root.std.Tuple2<root.scanner.Pos, int> { _0: pos, _1: length });
                }
                // `_` and `-` are one character in a Sass identifier, so every
                // built-in lookup from here down runs on the canonical spelling
                // (`map_get(…)` IS the deprecated `map-get(…)`). The name as
                // WRITTEN stays in `name` for the plain-CSS passthrough.
                let canonical = if (name.includes("_")) {
                    name.replace_all("_", "-")
                } else {
                    name
                };
                // A member exposed unprefixed via `@use … as *` — from a user
                // module, or from a built-in one (directly or through a user
                // module that forwards it). All of them compete for the bare
                // name, so ONE ambiguity check covers them, and it runs before
                // the arguments are evaluated: a call that resolves to nothing
                // must not warn about what is inside it.
                let star_user: root.std.Tuple2<root.eval.Module, root.eval.UserCallable>[] = if (root.eval.is_private_member(name)) {
                    []
                } else {
                    self.star_user_modules.filter_map((m: root.eval.Module) -> root.std.Tuple2<root.eval.Module, root.eval.UserCallable>? {
                        let f = m.function_(name);
                        if (f != null) {
                            root.std.Tuple2<root.eval.Module, root.eval.UserCallable> { _0: m, _1: f }
                        } else {
                            null
                        }
                    })
                };
                let star_builtin = self.star_builtin_hits(canonical, root.eval.MemberKind.Function);
                if (star_user.length() + star_builtin.length() > 1) {
                    throw root.error.Error.at(
                        "This function is available from multiple global modules.",
                        pos,
                    );
                }
                let star_user_first = star_user.at(0);
                if (star_user_first != null) {
                    let m = star_user_first._0;
                    let f = star_user_first._1;
                    return self.call_user_module_function(m, f, args, root.std.Tuple2<root.scanner.Pos, int> { _0: pos, _1: length });
                }
                let via_star = star_builtin.at(0);
                // A bare `calc()` reaches here as a plain call (the parser only
                // treats `calc(<arg>)` as a calculation), so a user
                // `@function calc()` could have handled it above. With no user
                // override it is the CSS `calc()`, which requires an argument.
                if (root.std.eq_ignore_ascii_case(name, "calc") && args.length() == 0) {
                    throw root.error.Error.at("Missing argument.", pos);
                }
                // The pure CSS-calculation functions are parsed as
                // calculations, which cannot take a `...` rest argument.
                if (root.eval.is_calc_function(name) && args.some((a: root.ast.CallArg) -> bool { a.splat })) {
                    throw root.error.Error.at("Rest arguments can't be used with calculations.", pos);
                }
                // The single-/double-argument math calculations (`sin`, `cos`,
                // `sqrt`, `pow`, `log`, `hypot`, …) parse their arguments as
                // calculation expressions, not ordinary SassScript. That means a
                // disallowed operator (`%`, comparison) inside an argument is
                // rejected ("This operation can't be used in a calculation."),
                // and an argument that does not reduce to a single number — it
                // still references a `var()`/interpolation/unknown ident — keeps
                // the whole call as a preserved calculation
                // (`sin(2px + var(--c))`) rather than erroring. When every
                // argument reduces to a plain number the normal builtin path
                // computes the result (and applies its unit checks), so this only
                // changes the two calc-specific behaviours above.
                if (root.eval.is_pure_calc_math_function(name)
                    && !has_user_fn
                    && !args.some((a: root.ast.CallArg) -> bool { a.splat || a.name != null }))
                {
                    let v = self.try_eval_calc_math_call(name, args, pos);
                    if (v != null) {
                        return v;
                    }
                }
                // `calc-size()` is a two-argument calculation: a sizing keyword
                // (or `var()`/calculation) plus a calculation, always preserved.
                if (root.std.eq_ignore_ascii_case(name, "calc-size")
                    && !has_user_fn
                    && !args.some((a: root.ast.CallArg) -> bool { a.splat || a.name != null }))
                {
                    return self.eval_calc_size(args, pos);
                }
                // A three-argument `clamp()` evaluates its bounds and value as
                // calculations, so a `var()`/operation argument (`1% + 1px`)
                // keeps the call preserved instead of erroring as Sass
                // arithmetic. Other arities (a preserved single argument, or an
                // arity error) fall through to the builtin.
                if (root.std.eq_ignore_ascii_case(name, "clamp")
                    && !has_user_fn
                    && args.length() == 3
                    && !args.some((a: root.ast.CallArg) -> bool { a.splat || a.name != null }))
                {
                    return self.try_eval_clamp(args, pos);
                }
                // `abs()` is a legacy global function that also exists as the CSS
                // `abs()` calculation. When its single positional argument
                // references a `var()`/interpolation it is parsed as a
                // calculation and preserved with its numeric subtree folded
                // (`abs(1px + 2px - var(--c))` -> `abs(3px - var(--c))`).
                // Without such a substitution the argument resolves to a plain
                // number, so the deprecated `math.abs` global handles it as
                // before (`abs(1 + 1px)` -> `2px`, `abs(-3) -> 3`).
                if (root.std.eq_ignore_ascii_case(name, "abs")
                    && !has_user_fn
                    && args.length() == 1
                    && args[0].name == null
                    && !args[0].splat
                    && root.eval.expr_contains_calc_substitution(args[0].value))
                {
                    let node = self.eval_calc(args[0].value);
                    return root.value.Value_Str {
                        _0: root.value.SassStr {
                            text: `abs(${node.to_calc_css(self.compressed())})`,
                            quoted: false,
                        },
                    };
                }
                // `round()` is likewise the CSS round() calculation: each
                // argument evaluates as a calculation (so `1.4px + var(--c)`
                // keeps its `+` with the numeric subtree folded, and
                // `1px + 4px` folds to `5px`). If every argument simplifies
                // (numbers, plus a leading strategy keyword), the normal
                // builtin computes the result; otherwise the call is
                // preserved. Calc-incompatible SassScript (`7 % 3`) falls back
                // to the legacy one-argument `math.round` (arity errors and
                // all).
                if (root.std.eq_ignore_ascii_case(name, "round")
                    && !has_user_fn
                    && args.length() >= 1
                    && args.length() <= 3
                    && !args.some((a: root.ast.CallArg) -> bool { a.splat || a.name != null }))
                {
                    // A SassScript-only operator (`7 % 3`) makes the call a
                    // plain function, and the only plain `round` is the legacy
                    // one-argument `math.round` — multi-argument forms are an
                    // arity error (dart-sass).
                    if (args.some((a: root.ast.CallArg) -> bool { root.eval.expr_has_non_calc_op(a.value) })) {
                        if (args.length() > 1) {
                            throw root.error.Error.at(
                                `Only 1 argument allowed, but ${args.length()} were passed.`,
                                pos,
                            );
                        }
                        // A single argument falls through to the legacy builtin.
                    } else {
                        // PORT: `if let Ok(nodes) = …collect::<Result<Vec<_>, Error>>()`
                        // → catch the evaluator's `Error` into `null`.
                        let nodes_r: root.value.CalcNode[]? = args
                            .map((a: root.ast.CallArg) -> root.value.CalcNode { self.eval_calc(a.value) }) catch (e) {
                                let _e: root.error.Error => null
                            };
                        if let nodes: root.value.CalcNode[] = nodes_r {
                            let simplified = (i: int, n: root.value.CalcNode) -> bool {
                                match (n) {
                                    root.value.CalcNode_Number {} => true,
                                    // A leading strategy keyword participates as a
                                    // keyword, not an operand.
                                    root.value.CalcNode_Str { _0: let s } => {
                                        let lower = root.std.ascii_lower(s);
                                        i == 0
                                            && nodes.length() >= 2
                                            && (lower == "nearest" || lower == "up" || lower == "down" || lower == "to-zero")
                                    },
                                    _ => false,
                                }
                            };
                            // PORT: `.iter().enumerate().all(..)` → index loop.
                            let all_simplified = true;
                            let i = 0;
                            while (i < nodes.length()) {
                                if (!simplified(i, nodes[i])) {
                                    all_simplified = false;
                                    break;
                                }
                                i += 1;
                            }
                            if (!all_simplified) {
                                // A preserved round is a first-class Calculation
                                // (`meta.calc-name`/`calc-args` see it).
                                return root.value.Value_Calc {
                                    _0: root.value.CalcNode_Func {
                                        name: "round",
                                        args: nodes,
                                    },
                                };
                            }
                            // Fall through to the normal builtin path below.
                        }
                    }
                }
                // `min`/`max` are likewise CSS calculations: their arguments
                // fold as calc expressions, and any unsimplifiable operand
                // (`1px + var(--c)`) preserves the call with the folded
                // subtrees spelled as calc (`max(5px, 1px + var(--c))`). When
                // every argument folds to a number the builtin computes as
                // before, and SassScript-only operators (`7 % 3`) keep the
                // whole call on the legacy path.
                if ((root.std.eq_ignore_ascii_case(name, "min") || root.std.eq_ignore_ascii_case(name, "max"))
                    && !has_user_fn
                    && args.length() != 0
                    && !args.some((a: root.ast.CallArg) -> bool { a.splat || a.name != null })
                    && !args.some((a: root.ast.CallArg) -> bool { root.eval.expr_has_non_calc_op(a.value) }))
                {
                    let nodes_r: root.value.CalcNode[]? = args
                        .map((a: root.ast.CallArg) -> root.value.CalcNode { self.eval_calc(a.value) }) catch (e) {
                            let _e: root.error.Error => null
                        };
                    if let nodes: root.value.CalcNode[] = nodes_r {
                        if (!nodes.every((n: root.value.CalcNode) -> bool { n is root.value.CalcNode_Number })) {
                            // A preserved min/max is a first-class Calculation
                            // (`meta.calc-name`/`calc-args` see it).
                            return root.value.Value_Calc {
                                _0: root.value.CalcNode_Func {
                                    name: root.std.ascii_lower(name),
                                    args: nodes,
                                },
                            };
                        }
                    }
                    // Fall through to the normal builtin path below.
                }
                // Evaluate args, expanding any `...` splat into positional /
                // keyword arguments.
                let evaled = self.eval_call_args(args);
                let pos_args = evaled._0;
                let named = evaled._1;
                let call_sep = evaled._2;
                // Whatever this call is deprecated for, it is reported here:
                // before every dispatch — the `sass:meta` predicates below
                // resolve against evaluator state and return early — and after
                // the arguments, so a call inside one of them warns first, as
                // dart's does.
                //
                // A `@use "sass:…" as *` makes the bare name that module's
                // MEMBER, so it is deprecated as a function, if at all, and not
                // as a global. A host function of the same name is NOT such a
                // case: dart's `functions` do not shadow a built-in global at
                // all (measured against 1.103.1's JS API — the built-in runs
                // and still warns).
                // The proprietary Microsoft `alpha()` filter overload (below)
                // is not a call to the global `alpha()` at all — dart passes it
                // through as a CSS function and deprecates nothing.
                //
                // GLOBAL calls only, like `css_filter_call` below: after `@use
                // "sass:color" as *` the bare `alpha(opacity=20)` is
                // `color.alpha`, which dart passes through AND deprecates as
                // `color-module-compat`. Returning it from here would skip the
                // star branch that dispatches to the module and emits that
                // warning, so the star path must fall through to it (#124).
                let ms_alpha_filter = via_star == null
                    && canonical == "alpha"
                    && root.builtins.color.legacy.ms_filter_args(pos_args, named) != null;
                // Same reasoning for the four names that are BOTH a CSS filter
                // function and a Sass global colour function: with a plain-CSS
                // argument (`filter: grayscale(1)`) the call is the CSS filter
                // and dart deprecates nothing. This asks the predicate the
                // builtins themselves use, so the warning cannot disagree with
                // which path the call actually took — it did, and told authors
                // to rewrite CSS filters as `color.adjust` (#122).
                // Global calls only, for the DEPRECATION: a namespaced
                // `color.grayscale(1)` is not a global built-in, so there is
                // nothing to deprecate for being one. (What dart raises there
                // instead is `color-module-compat`, which sasso does not
                // implement yet — #124, a separate gap this does not touch.)
                // ...and only when the built-in is what runs. A registered
                // host function of the same name takes precedence in sasso
                // (see `Options::with_function`), so the call is that
                // callback, not a CSS filter — and the contract there is that
                // a deprecated global's NAME warns whether or not one is
                // registered. Suppressing it here would have made
                // `with_function("grayscale($x)", …)` quietly exempt.
                // Order matters for cost, not just for correctness: the
                // predicate is a match on four names and rejects almost every
                // call outright, while the host-function check normalizes a
                // name and scans the registry. Computing the second one first
                // put that scan on EVERY call in a stylesheet that registers
                // any host function at all.
                let css_filter_call = via_star == null
                    && root.builtins.color_ext.is_plain_css_filter_call(canonical, pos_args, named)
                    && !(self.options.functions.length() != 0 && {
                        let norm = root.host_fn.normalize_name(canonical);
                        self.options.functions.some((f: root.host_fn.HostFn) -> bool { f.name == norm })
                    });
                if (!ms_alpha_filter && !css_filter_call) {
                    self.emit_call_deprecations(
                        canonical,
                        via_star?._0,
                        pos,
                        length,
                    );
                }
                // The global (deprecated) aliases of the `sass:meta` existence
                // predicates resolve against the evaluator state, not the
                // value-only builtin layer. A user-defined function of the same
                // name still wins (checked above).
                if (root.builtins.EVAL_GLOBAL_NAMES().includes(canonical)) {
                    // PORT: the in-place `*v = mem::replace(v, Null).without_slash()` loops
                    // rebuild the vectors instead (the evaluated args may alias a splatted list).
                    pos_args = pos_args.map((v: root.value.Value) -> root.value.Value { v.without_slash() });
                    named = named.map((nv: root.std.Tuple2<string, root.value.Value>) -> root.std.Tuple2<string, root.value.Value> {
                        root.std.Tuple2<string, root.value.Value> { _0: nv._0, _1: nv._1.without_slash() }
                    });
                    let r = self.try_meta_eval_call(canonical, pos_args, named, pos, length);
                    if (r != null) {
                        return match (r) {
                            let ok: root.std.Ok<root.value.Value> => ok.value,
                            let err: root.std.Err<root.error.Error> => throw err.error,
                        };
                    }
                }
                // The proprietary Microsoft `alpha()` filter overload (see
                // `ms_filter_args`): dart-sass passes the call through verbatim
                // as a CSS function instead of treating the argument as a
                // color. Returned from here, ahead of the dispatcher, because
                // the global spelling must not deprecate on the way.
                if (ms_alpha_filter) {
                    let ms_args = root.builtins.color.legacy.ms_filter_args(pos_args, named);
                    if (ms_args != null) {
                        return root.value.Value_Str {
                            _0: root.value.SassStr {
                                text: root.builtins.color.legacy.ms_filter_text(ms_args),
                                quoted: false,
                            },
                        };
                    }
                }
                // A member exposed unprefixed via `@use "sass:<mod>" as *` is
                // that module's, and it SHADOWS the global of the same name:
                // after `@use "sass:string" as *`, `index("abc", "b")` is
                // `string.index` (2), not the list one.
                if (via_star != null) {
                    let owner = via_star._0;
                    let bare = via_star._1;
                    // PORT: the in-place `*v = mem::replace(v, Null).without_slash()` loops
                    // rebuild the vectors instead (the evaluated args may alias a splatted list).
                    pos_args = pos_args.map((v: root.value.Value) -> root.value.Value { v.without_slash() });
                    named = named.map((nv: root.std.Tuple2<string, root.value.Value>) -> root.std.Tuple2<string, root.value.Value> {
                        root.std.Tuple2<string, root.value.Value> { _0: nv._0, _1: nv._1.without_slash() }
                    });
                    // A `sass:meta` member resolves against the evaluator, which
                    // the value-only dispatcher cannot do.
                    if (owner == "meta") {
                        let r = self.try_meta_eval_call(bare, pos_args, named, pos, length);
                        if (r != null) {
                            return match (r) {
                                let ok: root.std.Ok<root.value.Value> => ok.value,
                                let err: root.std.Err<root.error.Error> => throw err.error,
                            };
                        }
                    }
                    // The caret spans the INVOCATION, as it does for the same
                    // member written with its namespace (which sizes the error
                    // the same way). Without this a member reached through the
                    // star drew a one-column caret under the opening `i` of
                    // `index(1, 2, 3)`.
                    let v = root.builtins.call_module(owner, bare, pos_args, named, pos) catch (e) {
                        let err: root.error.Error => {
                            throw err.with_length_at(pos, length);
                        }
                    };
                    self.emit_color_function_deprecation(
                        bare,
                        owner,
                        pos,
                        length,
                        pos_args,
                        named,
                    );
                    return v.without_slash();
                }
                // Host-defined custom functions (dart-sass `functions`): they
                // override built-in globals but lose to user `@function`s and
                // module members (checked above). Resolved by calling back into
                // the embedder with the bound args serialized to the host-value
                // wire format.
                if (self.options.functions.length() != 0) {
                    let norm = root.host_fn.normalize_name(name);
                    let idx = self.options.functions.find_index((f: root.host_fn.HostFn) -> bool { f.name == norm });
                    if (idx != null) {
                        // Extract the owned signature + callback so the immutable
                        // borrow on `self.options` ends before any `&mut self`.
                        let sig: root.std.Tuple2<string[], string?> = {
                            let hf = self.options.functions[idx];
                            match (hf.params) {
                                let p: root.std.Ok<root.ast.ParamList> => root.std.Tuple2<string[], string?> {
                                    _0: p.value.params.map((x: root.ast.Param) -> string { x.name }),
                                    _1: p.value.rest,
                                },
                                let e: root.std.Err<string> => throw root.error.Error.at(e.error, pos),
                            }
                        };
                        let param_names = sig._0;
                        let rest_name = sig._1;
                        let callback = self.options.functions[idx].callback;
                        // Real Sass function: collapse slash-division args.
                        // PORT: the in-place `*v = mem::replace(v, Null).without_slash()` loops
                        // rebuild the vectors instead (the evaluated args may alias a splatted list).
                        pos_args = pos_args.map((v: root.value.Value) -> root.value.Value { v.without_slash() });
                        named = named.map((nv: root.std.Tuple2<string, root.value.Value>) -> root.std.Tuple2<string, root.value.Value> {
                            root.std.Tuple2<string, root.value.Value> { _0: nv._0, _1: nv._1.without_slash() }
                        });
                        // PORT: `std::mem::take(&mut pos_args)` / `named` → the
                        // locals are handed over (neither is read again).
                        let bound = root.host_fn.bind_host_args(
                            param_names,
                            rest_name,
                            pos_args,
                            named,
                            call_sep,
                            norm,
                        ) catch (e) {
                            let err: root.std.StrError => {
                                throw root.error.Error.at(err.message, pos);
                            }
                        };
                        // First-class function/mixin args round-trip as opaque
                        // handles into a per-dispatch table; save/restore the
                        // outer table so a nested custom-function call is safe.
                        let saved = root.host_fn.swap_handles([]);
                        // The host runs with the bump arena paused, like an
                        // importer or warn handler: whatever it allocates and
                        // keeps (a cache, a nested compile's result) must not
                        // sit in this compile's arena, which is reset on exit.
                        // PORT: the `Result<Value, String>` `and_then` chain →
                        // a block whose `StrError` is caught into an `Err`.
                        let result: root.std.Ok<root.value.Value> | root.std.Err<string> = {
                            let b = root.host_fn.serialize_args(bound);
                            let returned = {
                                let _paused = root.arena.pause();
                                defer {
                                    _paused.drop();
                                }
                                callback(b)
                            };
                            root.std.Ok<root.value.Value> { value: root.host_fn.deserialize_value(returned) }
                        } catch (e) {
                            let err: root.std.StrError => root.std.Err<string> { error: err.message }
                        };
                        root.host_fn.swap_handles(saved);
                        return match (result) {
                            let ok: root.std.Ok<root.value.Value> => ok.value.without_slash(),
                            let err: root.std.Err<string> => throw root.error.Error.at(err.error, pos),
                        };
                    }
                }
                // A bare slash-division argument collapses to its number when
                // passed to a real Sass function (dart-sass `withoutSlash`);
                // plain CSS functions (`foo(1/2)`) keep the slash verbatim.
                if (root.builtins.is_builtin(name)) {
                    // PORT: the in-place `*v = mem::replace(v, Null).without_slash()` loops
                    // rebuild the vectors instead (the evaluated args may alias a splatted list).
                    pos_args = pos_args.map((v: root.value.Value) -> root.value.Value { v.without_slash() });
                    named = named.map((nv: root.std.Tuple2<string, root.value.Value>) -> root.std.Tuple2<string, root.value.Value> {
                        root.std.Tuple2<string, root.value.Value> { _0: nv._0, _1: nv._1.without_slash() }
                    });
                }
                // A function call's RESULT is slash-free too (dart applies
                // `withoutSlash()` to every call result): `list.nth(3 1/2 4,
                // 2)` returns 0.5, not the slash form.
                // The name as WRITTEN: `builtins::call` canonicalizes its own
                // lookup, and a name that is no builtin passes through as the
                // plain-CSS function it was spelled as.
                let v = root.builtins.call(name, pos_args, named, pos);
                self.emit_color_function_deprecation(canonical, null, pos, length, pos_args, named);
                v.without_slash()
            },
            _ => root.std.unreachable(),
        }
    }

}
