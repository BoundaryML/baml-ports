// Ported from sasso `src/eval/control_flow.rs` (namespace `root.eval.control_flow`).

/// Iteration source for `@each`. A list is held as its shared `Rc<[Value]>`
/// handle so each iteration clones a single element on demand (avoiding the
/// up-front `Vec<Value>` copy of the whole collection); maps and scalars are
/// materialised into a small owned set.
interface EachItems {
    function len(self) -> int throws never {
        match (self) {
            let items: EachItems_Shared => items._0.length(),
            let items: EachItems_Owned => items._0.length(),
            _ => root.std.unreachable(),
        }
    }

    /// Clone the `i`th item — one element, never the whole collection.
    function get(self, i: int) -> root.value.Value throws never {
        // PORT: `items[i].clone()` → the shared element itself (values are
        // never mutated in place).
        match (self) {
            let items: EachItems_Shared => items._0[i],
            let items: EachItems_Owned => items._0[i],
            _ => root.std.unreachable(),
        }
    }
}

class EachItems_Shared {
    _0: root.value.Value[],
    implements EachItems {}
}

class EachItems_Owned {
    _0: root.value.Value[],
    implements EachItems {}
}

interface EvaluatorControlFlow {
    /// Evaluate a `@for` bound to a [`Number`], preserving its unit (the loop
    /// variable inherits the `from` bound's unit).
    function eval_for_number(self, e: root.ast.Expr) -> root.value.Number throws unknown;

    /// Resolve a `@for`'s bounds: the integer start, the integer end (the TO
    /// bound converted to the FROM bound's unit), and the loop variable's unit
    /// (taken from FROM). Errors on incompatible units or a non-integer bound,
    /// matching dart-sass.
    function for_bounds(
        self,
        from: root.ast.Expr,
        to: root.ast.Expr,
    ) -> root.std.Tuple3<int, int, string> throws unknown;

    /// The values `@each` iterates: a list yields its items, `null` yields
    /// nothing, and any other value is iterated once. A list returns its
    /// `Rc<[Value]>` handle directly (a refcount bump) so the loop can clone
    /// one element per iteration instead of deep-copying the whole collection
    /// up front; maps and scalars build a small owned set.
    function eval_each_items(self, e: root.ast.Expr) -> EachItems throws unknown;

    /// Bind `@each` variables to an item, destructuring a list across
    /// multiple variables (missing elements become `null`).
    /// `span` is the definition span every bound variable gets — dart binds all
    /// of them to `_expressionNode(node.list)`, the list expression itself
    /// (evaluate.dart:1441, `_setMultipleVariables` at 1465).
    function bind_each(
        self,
        vars: string[],
        item: root.value.Value,
        span: root.eval.VarSpan,
    ) -> void throws unknown;

    /// Evaluate a call's argument list into separate positional and keyword
    /// vectors, expanding any `...` splat (a list spreads into positional
    /// args, a map into keyword args). Duplicate keyword names (after
    /// hyphen/underscore normalization) are rejected, and a positional arg
    /// after a keyword arg is an error — matching dart-sass.
    ///
    /// This form discards the source-map definition spans — and so never
    /// collects them; callers that bind the results to user parameters want
    /// [`Self::eval_call_args_spanned`].
    function eval_call_args(self, args: root.ast.CallArg[]) -> root.eval.EvaledArgs throws unknown;

    /// As [`Self::eval_call_args`], but also returns each argument's definition
    /// span (dart `ArgumentResults.positionalNodes` / `namedNodes`), so a bound
    /// parameter can inherit the span of the argument it was bound to.
    function eval_call_args_spanned(
        self,
        args: root.ast.CallArg[],
    ) -> root.std.Tuple2<root.eval.EvaledArgs, root.eval.ArgSpans> throws unknown;

    /// The shared body. `want_spans` is the caller's answer to "will anything
    /// read the spans?" — a built-in binds its arguments by position and by
    /// name, never by span, so `math.div($a, $b)` was building a vector of them
    /// and dropping it on return.
    ///
    /// Together with `EvalOptions::source_map`, which gates definition-span
    /// bookkeeping everywhere else, that decides whether spans are tracked at
    /// all. When they are not, the three span vectors below stay EMPTY and
    /// never allocate: an [`ArgSpans`] entry that is absent reads back as the
    /// "unknown" span, which is what an untracked argument carries anyway.
    function eval_call_args_inner(
        self,
        args: root.ast.CallArg[],
        want_spans: bool,
    ) -> root.std.Tuple2<root.eval.EvaledArgs, root.eval.ArgSpans> throws unknown;

    /// Bind evaluated arguments into the CURRENT (freshly pushed) scope.
    /// Parameter defaults evaluate inside the callee environment with the
    /// already-bound parameters visible (`@mixin m($a, $b: $a)`), matching
    /// dart's progressive binding.
    ///
    /// `spans` carries each argument's definition span; a parameter inherits the
    /// span of whatever it was bound to — the matching argument, or, when it
    /// falls back to its declared default, that default's own expression node
    /// (dart evaluate.dart:3572-3592). Source-map only.
    function bind_evaled_into_scope(
        self,
        params: root.ast.ParamList,
        evaled: root.eval.EvaledArgs,
        spans: root.eval.ArgSpans,
        decl: root.eval.Declared,
    ) -> void throws unknown;

    /// Call a user-defined `@function`, returning its `@return` value. `call`,
    /// when present, is the (name-start position, byte length) of the call
    /// expression, recorded as a diagnostic stack frame around the body.
    function call_function(
        self,
        func: root.eval.UserCallable,
        args: root.ast.CallArg[],
        call: root.std.Tuple2<root.scanner.Pos, int>?,
    ) -> root.value.Value throws unknown;

    /// Run a function body, propagating the first `@return` (including from
    /// nested control flow). Functions emit no CSS, so a returned value
    /// short-circuits the whole call.
    function run_fn_body(self, stmts: root.ast.Stmt[]) -> root.value.Value? throws unknown;

    /// Execute an `@include`: bind args into a call frame, make the content
    /// block available, and run the mixin body into the current sink.
    function exec_include(
        self,
        name: string,
        args: root.ast.CallArg[],
        content: root.ast.Stmt[]?,
        content_params: root.ast.ParamList?,
        module: string?,
        pos: root.scanner.Pos,
        length: int,
        full_length: int,
        parents: string[],
        sink: root.std.Cell<root.eval.Sink>,
    ) -> void throws unknown;

    /// Execute an `@include ns.mixin` where `ns` is a user module: run the mixin
    /// body in the module's own environment, while its `@content` block (if any)
    /// runs back in the call site's environment.
    function run_module_mixin(
        self,
        module: root.eval.Module,
        mixin: root.eval.UserCallable,
        args: root.ast.CallArg[],
        content: root.ast.Stmt[]?,
        content_params: root.ast.ParamList?,
        pos: root.scanner.Pos,
        length: int,
        parents: string[],
        sink: root.std.Cell<root.eval.Sink>,
    ) -> void throws unknown;

    /// `@include meta.apply($mixin, $args...)`: invoke a first-class mixin
    /// reference. The first argument is the mixin reference; the rest are the
    /// arguments passed on to that mixin (which may also accept a `@content`
    /// block).
    function exec_apply(
        self,
        args: root.ast.CallArg[],
        content: root.ast.Stmt[]?,
        content_params: root.ast.ParamList?,
        pos: root.scanner.Pos,
        length: int,
        parents: string[],
        sink: root.std.Cell<root.eval.Sink>,
    ) -> void throws unknown;

    /// `meta.apply` with its arguments already evaluated — the form a
    /// first-class reference to it arrives in.
    function apply_evaled(
        self,
        pos_args: root.value.Value[],
        named: root.std.Tuple2<string, root.value.Value>[],
        content: root.ast.Stmt[]?,
        content_params: root.ast.ParamList?,
        pos: root.scanner.Pos,
        length: int,
        parents: string[],
        sink: root.std.Cell<root.eval.Sink>,
    ) -> void throws unknown;

    /// Invoke a resolved mixin reference with already-evaluated arguments and an
    /// optional `@content` block, emitting into `sink`.
    function invoke_mixin_ref(
        self,
        mixin: root.value.SassMixin,
        pos_args: root.value.Value[],
        named: root.std.Tuple2<string, root.value.Value>[],
        content: root.ast.Stmt[]?,
        content_params: root.ast.ParamList?,
        pos: root.scanner.Pos,
        length: int,
        parents: string[],
        sink: root.std.Cell<root.eval.Sink>,
    ) -> void throws unknown;

    /// Run the innermost active `@content` block. For a cross-module include the
    /// block carries a snapshot of the call-site environment, which is installed
    /// for the duration so the content resolves there rather than in the mixin's
    /// module.
    function exec_content(
        self,
        args: root.ast.CallArg[],
        pos: root.scanner.Pos,
        parents: string[],
        sink: root.std.Cell<root.eval.Sink>,
    ) -> void throws unknown;

    /// The lazy `if($condition, $if-true, $if-false)` function: evaluates
    /// the condition, then only the selected branch.
    function eval_if_function(
        self,
        args: root.ast.CallArg[],
        pos: root.scanner.Pos,
    ) -> root.value.Value throws unknown;

    /// Evaluate a modern CSS `if()`: a `;`-separated list of clauses, each
    /// `<condition>: <value>` (or `else: <value>`). Conditions mix evaluated
    /// `sass(<expr>)` with non-evaluable `css(...)` / arbitrary substitution
    /// pieces. If every reachable condition resolves statically, the matching
    /// value is returned; otherwise the whole `if()` is re-serialized
    /// verbatim (with statically-true/false conditions folded away) as an
    /// unquoted string.
    function eval_modern_if(self, clauses: root.ast.IfClause[]) -> root.value.Value throws unknown;

    /// Evaluate an `if()` clause value. dart-sass emits it in plain CSS
    /// serialization format (since 1.101.4), not `meta.inspect()` format.
    function eval_if_value(self, expr: root.ast.Expr) -> string throws unknown;

    /// Evaluate a modern `if()` condition into a tri-state result: a static
    /// boolean (from `sass(...)` atoms) or a residual non-evaluable CSS
    /// condition that must be re-serialized verbatim.
    function eval_if_cond(self, cond: root.ast.IfCond) -> root.eval.CondEval throws unknown;
}

implements EvaluatorControlFlow for root.eval.Evaluator {
    /// Evaluate a `@for` bound to a [`Number`], preserving its unit (the loop
    /// variable inherits the `from` bound's unit).
    function eval_for_number(self, e: root.ast.Expr) -> root.value.Number {
        match (self.eval_expr(e)) {
            let n: root.value.Value_Number => n._0,
            let other: root.value.Value => {
                throw root.error.Error.unpositioned(`${other.type_name()} is not a number.`);
            }
        }
    }

    /// Resolve a `@for`'s bounds: the integer start, the integer end (the TO
    /// bound converted to the FROM bound's unit), and the loop variable's unit
    /// (taken from FROM). Errors on incompatible units or a non-integer bound,
    /// matching dart-sass.
    function for_bounds(self, from: root.ast.Expr, to: root.ast.Expr) -> root.std.Tuple3<int, int, string> {
        let start = self.eval_for_number(from);
        let end = self.eval_for_number(to);
        // The loop variable takes FROM's unit; TO is converted to match. A
        // unitless side defers (no conversion); two incompatible real units err.
        let end_value = if (start.is_unitless() || end.is_unitless()) {
            end.value
        } else {
            match (root.value.convert_factor(end.unit(), start.unit())) {
                let f: float => end.value * f,
                null => {
                    let end_v: root.value.Value = root.value.Value_Number { _0: end };
                    throw root.error.Error.unpositioned(
                        `Expected ${end_v.to_css(false)} to have unit ${start.unit()}.`,
                    );
                }
            }
        };
        // Both bounds must be integers (dart-sass: "<n> is not an int.").
        let to_int = (v: float, n: root.value.Number) -> int {
            if (root.std.flt((v - v.round()).abs(), 1e-11)) {
                root.std.f64_to_int(v.round())
            } else {
                let n_v: root.value.Value = root.value.Value_Number { _0: n };
                throw root.error.Error.unpositioned(`${n_v.to_css(false)} is not an int.`);
            }
        };
        let start_i = to_int(start.value, start);
        let end_i = to_int(end_value, root.value.Number.with_unit(end_value, start.unit()));
        root.std.Tuple3 { _0: start_i, _1: end_i, _2: start.unit() }
    }

    /// The values `@each` iterates: a list yields its items, `null` yields
    /// nothing, and any other value is iterated once. A list returns its
    /// `Rc<[Value]>` handle directly (a refcount bump) so the loop can clone
    /// one element per iteration instead of deep-copying the whole collection
    /// up front; maps and scalars build a small owned set.
    function eval_each_items(self, e: root.ast.Expr) -> EachItems {
        match (self.eval_expr(e)) {
            let l: root.value.Value_List => EachItems_Shared { _0: l._0.items },
            // `@each` over a map yields each `key value` pair as a two-element
            // space list, so `@each $k, $v in $map` destructures correctly.
            let m: root.value.Value_Map => EachItems_Owned {
                _0: m._0.entries.map((kv: root.std.Tuple2<root.value.Value, root.value.Value>) -> root.value.Value {
                    root.value.Value_List {
                        _0: root.value.List {
                            items: [kv._0, kv._1],
                            sep: root.value.ListSep.Space,
                            bracketed: false,
                            keywords: null,
                        },
                    }
                }),
            },
            // Any non-list — INCLUDING null — iterates as a singleton (dart
            // `Value.asList` defaults to `[this]`; bootstrap's `valid-radius`
            // relies on `@each $v in null` running once with `$v: null`).
            let other: root.value.Value => EachItems_Owned { _0: [other] },
        }
    }

    /// Bind `@each` variables to an item, destructuring a list across
    /// multiple variables (missing elements become `null`).
    /// `span` is the definition span every bound variable gets — dart binds all
    /// of them to `_expressionNode(node.list)`, the list expression itself
    /// (evaluate.dart:1441, `_setMultipleVariables` at 1465).
    function bind_each(self, vars: string[], item: root.value.Value, span: root.eval.VarSpan) -> void {
        if (vars.length() == 1) {
            self.set_local(vars[0], item, span);
            return;
        }
        match (item) {
            // Index the list's `Rc<[Value]>` directly — cloning only the
            // elements the vars need, with no intermediate `Vec<Value>`.
            let l: root.value.Value_List => {
                let i = 0;
                for (let v in vars) {
                    let val = l._0.items.at(i) ?? root.value.Value_Null {};
                    self.set_local(v, val, span);
                    i += 1;
                }
            }
            // A non-list binds to the first var; the remaining vars are null.
            let other: root.value.Value => {
                self.set_local(vars[0], other, span);
                for (let v in vars.slice(1, vars.length())) {
                    self.set_local(v, root.value.Value_Null {}, span);
                }
            }
        }
    }

    /// Evaluate a call's argument list into separate positional and keyword
    /// vectors, expanding any `...` splat (a list spreads into positional
    /// args, a map into keyword args). Duplicate keyword names (after
    /// hyphen/underscore normalization) are rejected, and a positional arg
    /// after a keyword arg is an error — matching dart-sass.
    ///
    /// This form discards the source-map definition spans — and so never
    /// collects them; callers that bind the results to user parameters want
    /// [`Self::eval_call_args_spanned`].
    function eval_call_args(self, args: root.ast.CallArg[]) -> root.eval.EvaledArgs {
        self.eval_call_args_inner(args, false)._0
    }

    /// As [`Self::eval_call_args`], but also returns each argument's definition
    /// span (dart `ArgumentResults.positionalNodes` / `namedNodes`), so a bound
    /// parameter can inherit the span of the argument it was bound to.
    function eval_call_args_spanned(self, args: root.ast.CallArg[]) -> root.std.Tuple2<root.eval.EvaledArgs, root.eval.ArgSpans> {
        self.eval_call_args_inner(args, true)
    }

    /// The shared body. `want_spans` is the caller's answer to "will anything
    /// read the spans?" — a built-in binds its arguments by position and by
    /// name, never by span, so `math.div($a, $b)` was building a vector of them
    /// and dropping it on return.
    ///
    /// Together with `EvalOptions::source_map`, which gates definition-span
    /// bookkeeping everywhere else, that decides whether spans are tracked at
    /// all. When they are not, the three span vectors below stay EMPTY and
    /// never allocate: an [`ArgSpans`] entry that is absent reads back as the
    /// "unknown" span, which is what an untracked argument carries anyway.
    function eval_call_args_inner(self, args: root.ast.CallArg[], want_spans: bool) -> root.std.Tuple2<root.eval.EvaledArgs, root.eval.ArgSpans> {
        let track_spans = want_spans && self.options.source_map;
        // Explicit positional args are gathered first; positionals spread from
        // a `...` splat are appended after them, so `f([1, 2]..., 3)` binds
        // `3` before `1, 2` (matching dart-sass's misplaced-rest behaviour).
        let explicit_pos: root.value.Value[] = [];
        let splat_pos: root.value.Value[] = [];
        let keyword: root.std.Tuple2<string, root.value.Value>[] = [];
        let seen_named = false;
        // Definition spans tracked in lockstep with the three value vectors
        // above (dart builds `positionalNodes`/`namedNodes` the same way,
        // evaluate.dart:3812-3824). Every element a splat expands to gets the
        // SPLAT EXPRESSION's own span, not a per-element one — dart fills the
        // whole run with `restNodeForSpan` (evaluate.dart:3851).
        let explicit_pos_spans: root.eval.VarSpan[] = [];
        let splat_pos_spans: root.eval.VarSpan[] = [];
        let keyword_spans: root.std.Tuple2<string, root.eval.VarSpan>[] = [];
        // A splatted list's separator survives into the callee's rest arglist
        // (`foo(c d e...)` binds `$zs` as a SPACE-separated arglist).
        let rest_sep: root.value.ListSep = root.value.ListSep.Comma;
        let push_named = (
            keyword: root.std.Tuple2<string, root.value.Value>[],
            spans: root.std.Tuple2<string, root.eval.VarSpan>[],
            name: string,
            v: root.value.Value,
            sp: root.eval.VarSpan,
        ) -> void {
            let norm = root.eval.normalize_arg_name(name);
            if (keyword.some((p) -> { root.eval.normalize_arg_name(p._0) == norm })) {
                throw root.error.Error.unpositioned("Duplicate argument.");
            }
            if (track_spans) {
                spans.push(root.std.Tuple2 { _0: name, _1: sp });
            }
            keyword.push(root.std.Tuple2 { _0: name, _1: v });
        };
        for (let a in args) {
            let v = self.eval_expr(a.value);
            // dart resolves each argument's node right after evaluating it
            // (evaluate.dart:3814), so a bare `$x` argument carries `$x`'s
            // DEFINITION rather than the call site. Resolving one walks the
            // scope chain, so it waits until something wants the answer too.
            let sp = if (track_spans) {
                self.expression_node(a.value, a.value_pos)
            } else {
                root.eval.VarSpan.default()
            };
            if (a.splat) {
                // A splat list spreads into positional args; a map spreads
                // into keyword args (string keys only). A single non-list/map
                // value acts as one positional arg; `null` spreads to nothing.
                match (v) {
                    let m: root.value.Value_Map => {
                        for (let kv in m._0.entries) {
                            let k = kv._0;
                            let val = kv._1;
                            let key = match (k) {
                                let s: root.value.Value_Str => s._0.text,
                                let other: root.value.Value => {
                                    throw root.error.Error.unpositioned(
                                        `${other.to_css(false)} is not a string in $args.`,
                                    );
                                }
                            };
                            push_named(keyword, keyword_spans, key, val, sp);
                        }
                    }
                    let l: root.value.Value_List => {
                        if (l._0.sep != root.value.ListSep.Undecided) {
                            rest_sep = l._0.sep;
                        }
                        // `iter::repeat_n` is 1.82; the crate's MSRV is 1.74.
                        if (track_spans) {
                            for (let _x in l._0.items) {
                                splat_pos_spans.push(sp);
                            }
                        }
                        root.std.extend(splat_pos, l._0.items);
                        // An argument-list splat (`$args...`) also forwards its
                        // captured keyword arguments as named arguments.
                        let kw = l._0.keywords;
                        if (kw != null) {
                            for (let kv in kw) {
                                if let s: root.value.Value_Str = kv._0 {
                                    push_named(
                                        keyword,
                                        keyword_spans,
                                        s._0.text,
                                        kv._1,
                                        sp,
                                    );
                                }
                            }
                        }
                    }
                    root.value.Value_Null {} => {}
                    let other: root.value.Value => {
                        splat_pos.push(other);
                        if (track_spans) {
                            splat_pos_spans.push(sp);
                        }
                    }
                }
                continue;
            }
            match (a.name) {
                let n: string => {
                    push_named(keyword, keyword_spans, n, v, sp);
                    seen_named = true;
                }
                null => {
                    // A plain positional arg may not follow a keyword arg.
                    if (seen_named) {
                        throw root.error.Error.unpositioned(
                            "Positional arguments must come before keyword arguments.",
                        );
                    }
                    explicit_pos.push(v);
                    if (track_spans) {
                        explicit_pos_spans.push(sp);
                    }
                }
            }
        }
        root.std.extend(explicit_pos, splat_pos);
        root.std.extend(explicit_pos_spans, splat_pos_spans);
        root.std.Tuple2 {
            _0: root.std.Tuple3 { _0: explicit_pos, _1: keyword, _2: rest_sep },
            _1: root.eval.ArgSpans {
                positional: explicit_pos_spans,
                named: keyword_spans,
            },
        }
    }

    /// Bind evaluated arguments into the CURRENT (freshly pushed) scope.
    /// Parameter defaults evaluate inside the callee environment with the
    /// already-bound parameters visible (`@mixin m($a, $b: $a)`), matching
    /// dart's progressive binding.
    ///
    /// `spans` carries each argument's definition span; a parameter inherits the
    /// span of whatever it was bound to — the matching argument, or, when it
    /// falls back to its declared default, that default's own expression node
    /// (dart evaluate.dart:3572-3592). Source-map only.
    function bind_evaled_into_scope(self, params: root.ast.ParamList, evaled: root.eval.EvaledArgs, spans: root.eval.ArgSpans, decl: root.eval.Declared) -> void {
        let positional = evaled._0;
        let keyword_vec = evaled._1;
        let rest_sep = evaled._2;
        let keyword: map<string, root.value.Value> = {};
        let keyword_order: root.std.Tuple2<string, string>[] = [];
        for (let nv in keyword_vec) {
            let n = nv._0;
            let v = nv._1;
            let norm = root.eval.normalize_arg_name(n);
            if (!keyword.has(norm)) {
                keyword_order.push(root.std.Tuple2 { _0: norm, _1: n });
            }
            let _ = keyword.set(norm, v);
        }
        let positional_count = positional.length();
        // PORT: `positional.into_iter().enumerate()` → an index cursor
        // (`pos_next` is the index the iterator would yield next).
        let pos_next = 0;
        for (let param in params.params) {
            let bound: root.std.Tuple2<root.value.Value, root.eval.VarSpan> = if (pos_next < positional.length()) {
                let i = pos_next;
                pos_next += 1;
                root.std.Tuple2 { _0: positional[i], _1: spans.positional_(i) }
            } else if let v: root.value.Value = keyword.delete(root.eval.normalize_arg_name(param.name)) {
                root.std.Tuple2 { _0: v, _1: spans.named_(param.name) }
            } else if let def: root.ast.Expr = param.default {
                let v = self.eval_expr(def);
                // A default is resolved through `_expressionNode` too, so
                // `@mixin m($a, $b: $a)` gives `$b` whatever `$a` points at.
                let sp = self.expression_node(def, param.default_pos);
                root.std.Tuple2 { _0: v, _1: sp }
            } else {
                // dart reports a missing argument against the INVOCATION as
                // its primary span, with the declaration it was measured
                // against beside it. Every call path pushes the call's frame
                // before binding, so it is the innermost one.
                throw self.error_at_call_with_declaration(`Missing argument $${param.name}.`, decl);
            };
            let val = bound._0;
            let span = bound._1;
            let sc = root.std.last(self.scopes);
            if (sc != null) {
                let _ = sc.set(param.name, val);
            }
            let frame = root.std.last(self.var_spans);
            if (frame != null) {
                let _ = frame.set(param.name, span);
            }
        }
        let rest = params.rest;
        if (rest != null) {
            let remaining: root.value.Value[] = positional.slice(pos_next, positional.length());
            let kw: root.std.Tuple2<root.value.Value, root.value.Value>[] = keyword_order
                .filter_map((p: root.std.Tuple2<string, string>) -> root.std.Tuple2<root.value.Value, root.value.Value>? {
                    let norm = p._0;
                    let v = keyword.delete(norm);
                    if (v != null) {
                        root.std.Tuple2 {
                            _0: root.value.Value_Str {
                                _0: root.value.SassStr {
                                    text: norm,
                                    quoted: false,
                                },
                            },
                            _1: v,
                        }
                    } else {
                        null
                    }
                });
            let sc = root.std.last(self.scopes);
            if (sc != null) {
                let _ = sc.set(
                    rest,
                    root.value.Value_List {
                        _0: root.value.List {
                            items: remaining,
                            sep: rest_sep,
                            bracketed: false,
                            keywords: kw,
                        },
                    },
                );
            }
            // dart blames the CALL node for a `$rest...` arglist
            // (evaluate.dart:3609), which is not a value position sasso maps;
            // record "unknown" so no segment is emitted for it.
            let frame = root.std.last(self.var_spans);
            if (frame != null) {
                let _ = frame.set(rest, root.eval.VarSpan.default());
            }
        } else if (pos_next < positional.length()) {
            // dart counts what was DECLARED against what was passed, and
            // agrees with itself about the verb.
            let allowed = params.params.length();
            let passed = positional_count;
            // dart says "positional" the moment a NAMED argument is in
            // play, and counts only the positional ones.
            let positional_word = if (keyword_order.length() == 0) {
                ""
            } else {
                "positional "
            };
            let plural = if (allowed == 1) { "" } else { "s" };
            let verb = if (passed == 1) { "was" } else { "were" };
            throw self.error_at_call_with_declaration(
                `Only ${allowed} ${positional_word}argument${plural} allowed, but ${passed} ${verb} passed.`,
                decl,
            );
        }
        if (params.rest == null && keyword.length() > 0) {
            let leftover: string[] = keyword_order
                .filter((p) -> { keyword.has(p._0) })
                .map((p) -> { p._1 });
            // PORT: `leftover.split_last()` → the last element and the slice before it.
            if (leftover.length() > 0) {
                let last = leftover[leftover.length() - 1];
                let init = leftover.slice(0, leftover.length() - 1);
                let msg = if (init.length() == 0) {
                    `No parameter named $${last}.`
                } else {
                    let head = init
                        .map((n) -> { `$${n}` })
                        .join(", ");
                    `No parameters named ${head} or $${last}.`
                };
                throw self.error_at_call_with_declaration(msg, decl);
            }
        }
    }

    /// Call a user-defined `@function`, returning its `@return` value. `call`,
    /// when present, is the (name-start position, byte length) of the call
    /// expression, recorded as a diagnostic stack frame around the body.
    function call_function(self, func: root.eval.UserCallable, args: root.ast.CallArg[], call: root.std.Tuple2<root.scanner.Pos, int>?) -> root.value.Value {
        // Arguments evaluate in the CALLER's environment; the body (and the
        // parameter defaults) run against the callable's LEXICAL closure.
        let evaled_spans = self.eval_call_args_spanned(args);
        let evaled = evaled_spans._0;
        let arg_spans = evaled_spans._1;
        // The call frame records the CALL site (this file); the body then runs
        // against the function's defining file.
        let saved: string? = if (call != null) {
            self.enter_call(call._0, call._1, `${func.def.name}()`)
        } else {
            null
        };
        let saved_file = self.enter_origin_file(func.origin);
        // PORT: `std::mem::replace(&mut self.x, func.env_x.clone())` → save the
        // current chain, install a shallow copy of the captured one (the
        // evaluator pushes/pops on it; the closure's own array must not move).
        let saved_scopes = self.scopes;
        self.scopes = root.std.clone_vec(func.env);
        let saved_var_spans = self.var_spans;
        self.var_spans = root.std.clone_vec(func.env_spans);
        let saved_semi = self.scope_semi_global;
        self.scope_semi_global = root.std.clone_vec(func.env_semi);
        let saved_fns = self.functions;
        self.functions = root.std.clone_vec(func.env_fns);
        let saved_mixins = self.mixins;
        self.mixins = root.std.clone_vec(func.env_mixins);
        let saved_env_modules = self.install_env_modules(func.env_modules);
        self.push_scope(false);
        // PORT: the `Result` chain (`bind … .and_then(…).map_err(…)`) is caught
        // into `err` (and the body's value into `result`), re-thrown after the
        // cleanup below.
        let err: root.error.Error? = null;
        let result: root.value.Value? = null;
        self.bind_evaled_into_scope(func.def.params, evaled, arg_spans, declared(func)) catch (e) {
            let x: root.error.Error => {
                err = x;
            }
        };
        if (err == null) {
            // A function body is not a mixin body: `meta.content-exists()`
            // called from a function (even one invoked by a mixin) errors.
            self.in_mixin.push(false);
            result = self.run_fn_body(func.def.body) catch (e) {
                let x: root.error.Error => {
                    err = x;
                    null
                }
            };
            let _ = self.in_mixin.pop();
        }
        // Render a positioned error while its file is still current.
        if (err != null) {
            err = self.finalize_error(err);
        }
        self.pop_scope();
        self.scopes = saved_scopes;
        self.var_spans = saved_var_spans;
        self.scope_semi_global = saved_semi;
        self.functions = saved_fns;
        self.mixins = saved_mixins;
        self.restore_env_modules(saved_env_modules);
        self.leave_module_file(saved_file);
        if (saved != null) {
            self.leave_call(saved);
        }
        if (err != null) {
            throw err;
        }
        match (result) {
            // A bare slash-division returned from a function collapses to
            // its number (dart-sass `withoutSlash`); slashes nested in a
            // returned list are preserved.
            let v: root.value.Value => v.without_slash(),
            null => {
                throw root.error.Error.unpositioned(
                    `Function ${func.def.name}() did not @return a value.`,
                );
            }
        }
    }

    /// Run a function body, propagating the first `@return` (including from
    /// nested control flow). Functions emit no CSS, so a returned value
    /// short-circuits the whole call.
    function run_fn_body(self, stmts: root.ast.Stmt[]) -> root.value.Value? {
        // PORT: a nested body's `Result<Option<Value>>` is split into a caught
        // `root.error.Error?` (`result_err`) and the `Value?` (`result`).
        for (let stmt in stmts) {
            match (stmt) {
                let v: root.ast.Stmt_VarDecl => {
                    self.apply_var(v._0);
                }
                root.ast.Stmt_Comment {} => {}
                let e: root.ast.Stmt_Return => {
                    return self.eval_expr(e._0);
                }
                let s: root.ast.Stmt_FunctionDef => {
                    let c = s._0;
                    let captured = self.capture_callable(c);
                    self.define_function(c.name, captured);
                }
                let s: root.ast.Stmt_If => {
                    for (let branch in s._0) {
                        let take = match (branch.cond) {
                            null => true,
                            let c: root.ast.Expr => self.eval_expr(c).is_truthy(),
                        };
                        if (take) {
                            self.push_scope(true);
                            let result_err: root.error.Error? = null;
                            let result = self.run_fn_body(branch.body) catch (e) {
                                let x: root.error.Error => {
                                    result_err = x;
                                    null
                                }
                            };
                            self.pop_scope();
                            if (result_err != null) {
                                throw result_err;
                            }
                            if (result != null) {
                                return result;
                            }
                            break;
                        }
                    }
                }
                let s: root.ast.Stmt_For => {
                    let bounds = self.for_bounds(s.from, s.to);
                    let start_i = bounds._0;
                    let end_i = bounds._1;
                    let unit = bounds._2;
                    self.push_scope(true);
                    // dart resolves the loop variable's node INSIDE the loop
                    // scope (evaluate.dart:1666) — but `@for` pushes a fresh
                    // frame, so the lookup still sees the outer bindings.
                    let span = self.expression_node(s.from, s.from_pos);
                    let result_err: root.error.Error? = null;
                    let result: root.value.Value? = null;
                    for (let i in root.eval.for_indices(start_i, end_i, s.inclusive)) {
                        self.set_local(s.var, root.value.Value_Number { _0: root.value.Number.with_unit(i * 1.0, unit) }, span);
                        result = self.run_fn_body(s.body) catch (e) {
                            let x: root.error.Error => {
                                result_err = x;
                                null
                            }
                        };
                        if (result_err == null && result == null) {
                            continue;
                        }
                        break;
                    }
                    self.pop_scope();
                    if (result_err != null) {
                        throw result_err;
                    }
                    if (result != null) {
                        return result;
                    }
                }
                let s: root.ast.Stmt_Each => {
                    let items = self.eval_each_items(s.list);
                    // Resolved BEFORE the loop scope is pushed, like dart
                    // (evaluate.dart:1441 precedes `_environment.scope`).
                    let span = self.expression_node(s.list, s.list_pos);
                    self.push_scope(true);
                    let result_err: root.error.Error? = null;
                    let result: root.value.Value? = null;
                    for (let i in baml.iter.Range.new(0, items.len())) {
                        self.bind_each(s.vars, items.get(i), span);
                        result = self.run_fn_body(s.body) catch (e) {
                            let x: root.error.Error => {
                                result_err = x;
                                null
                            }
                        };
                        if (result_err == null && result == null) {
                            continue;
                        }
                        break;
                    }
                    self.pop_scope();
                    if (result_err != null) {
                        throw result_err;
                    }
                    if (result != null) {
                        return result;
                    }
                }
                let s: root.ast.Stmt_While => {
                    self.push_scope(true);
                    let result_err: root.error.Error? = null;
                    let result: root.value.Value? = null;
                    let guard = 0;
                    while (true) {
                        // PORT: `match self.eval_expr(cond)` — an `Err` lands in
                        // `result_err` and leaves `v` null.
                        let v: root.value.Value? = self.eval_expr(s.cond) catch (e) {
                            let x: root.error.Error => {
                                result_err = x;
                                null
                            }
                        };
                        if (v == null) {
                            break;
                        }
                        if (!v.is_truthy()) {
                            break;
                        }
                        result = self.run_fn_body(s.body) catch (e) {
                            let x: root.error.Error => {
                                result_err = x;
                                null
                            }
                        };
                        if (result_err != null || result != null) {
                            break;
                        }
                        guard += 1;
                        if (guard >= 100000) {
                            result_err = root.error.Error.unpositioned("@while exceeded 100000 iterations");
                            break;
                        }
                    }
                    self.pop_scope();
                    if (result_err != null) {
                        throw result_err;
                    }
                    if (result != null) {
                        return result;
                    }
                }
                let s: root.ast.Stmt_Warn => {
                    self.emit_warn(s.value, s.pos);
                }
                let s: root.ast.Stmt_Debug => {
                    self.emit_debug(s.value, s.pos);
                }
                let s: root.ast.Stmt_Error => {
                    throw self.build_error(s.value, s.pos, s.length);
                }
                _ => {
                    throw root.error.Error.unpositioned(
                        "only variable assignments, control flow and @return are allowed in a function.",
                    );
                }
            }
        }
        null
    }

    /// Execute an `@include`: bind args into a call frame, make the content
    /// block available, and run the mixin body into the current sink.
    function exec_include(self, name: string, args: root.ast.CallArg[], content: root.ast.Stmt[]?, content_params: root.ast.ParamList?, module: string?, pos: root.scanner.Pos, length: int, full_length: int, parents: string[], sink: root.std.Cell<root.eval.Sink>) -> void {
        // (parameter notes) `length`: the CALL's byte length, content block
        // excluded — dart's `spanWithoutContent`, which sizes an error about the
        // call itself. `full_length`: the whole statement's byte length — an
        // error about the RULE (this mixin does not exist, that namespace does
        // not exist) carets all of it, content block included, as dart's `span`
        // does.
        // NOTE: the diagnostic call frame for this `@include` is pushed by the
        // caller (the `Stmt::Include` arm) so it wraps every resolution path.
        // The built-in `@include meta.apply(...)` / `meta.load-css(...)` are
        // bound to the `sass:meta` namespace, so resolve them before the generic
        // module path.
        if let ns: string = module {
            if (self.used_modules.get(ns) == "meta") {
                // `_` and `-` are one character in a Sass identifier, so
                // `meta.load_css(…)` is `meta.load-css(…)`.
                match (root.eval.normalize_arg_name(name)) {
                    "apply" => {
                        self.exec_apply(args, content, content_params, pos, length, parents, sink);
                        return;
                    }
                    "load-css" => {
                        self.exec_load_css(args, content, pos, parents, sink);
                        return;
                    }
                    _ => {}
                }
            }
        }
        // A namespaced `@include ns.mixin`: resolve a user module bound to the
        // namespace, then a built-in (which exposes no mixins in this build).
        if let ns: string = module {
            if let target: root.eval.Module = self.used_user_modules.get(ns) {
                if (root.eval.is_private_member(name)) {
                    // dart omits private members from a module's public view,
                    // so a reference to one is simply not found. (A LITERAL
                    // `ns.-name` never reaches here — the parser rejects it
                    // with dart's privacy error; what does is an ESCAPED
                    // spelling, which dart treats as an ordinary member.)
                    throw root.error.Error.at("Undefined mixin.", pos).with_length(full_length);
                }
                // A built-in this module re-exports brings its mixins along
                // (`@forward "sass:meta"` re-exports `load-css`/`apply`).
                if (target.mixin(name) == null) {
                    if let fwd: root.std.Tuple2<string, string> = root.eval.meta.resolve_forwarded_builtin_mixin(target, name) {
                        let owner = fwd._0;
                        let bare = fwd._1;
                        if (owner == "meta" && bare == "apply") {
                            self.exec_apply(
                                args,
                                content,
                                content_params,
                                pos,
                                length,
                                parents,
                                sink,
                            );
                            return;
                        }
                        if (owner == "meta" && bare == "load-css") {
                            self.exec_load_css(args, content, pos, parents, sink);
                            return;
                        }
                    }
                }
                let mixin = target.mixin(name);
                if (mixin == null) {
                    throw root.error.Error.at("Undefined mixin.", pos).with_length(full_length);
                }
                // A forwarded mixin runs in its DEFINING module's environment.
                let exec = target.mixin_origin(name) ?? target;
                self.run_module_mixin(
                    exec,
                    mixin,
                    args,
                    content,
                    content_params,
                    pos,
                    length,
                    parents,
                    sink,
                );
                return;
            }
            if (!self.used_modules.has(ns)) {
                throw root.error.Error.at(`There is no module with the namespace "${ns}".`, pos)
                    .with_length(full_length);
            }
            throw root.error.Error.at("Undefined mixin.", pos).with_length(full_length);
        }
        // A bare `@include` may resolve a user module mixin exposed unprefixed
        // via `@use … as *`.
        if (self.lookup_mixin(name) == null && !root.eval.is_private_member(name)) {
            let hits: root.std.Tuple2<root.eval.Module, root.eval.UserCallable>[] = self
                .star_user_modules
                .filter_map((m: root.eval.Module) -> root.std.Tuple2<root.eval.Module, root.eval.UserCallable>? {
                    let mx = m.mixin(name);
                    if (mx != null) {
                        root.std.Tuple2 { _0: m, _1: mx }
                    } else {
                        null
                    }
                });
            // A built-in mixin exposed unprefixed the same way (`load-css` and
            // `apply` from `sass:meta`, directly or through a user module that
            // forwards it) competes for the same bare name.
            let builtin_hits = self.star_builtin_hits(name, root.eval.MemberKind.Mixin);
            if (hits.length() + builtin_hits.length() > 1) {
                // dart carets the `@include` (and adds a secondary row per
                // `@use`, which this renderer cannot draw yet).
                throw root.error.Error.at("This mixin is available from multiple global modules.", pos)
                    .with_length(full_length);
            }
            if let hit: root.std.Tuple2<root.eval.Module, root.eval.UserCallable> = hits.at(0) {
                self.run_module_mixin(
                    hit._0,
                    hit._1,
                    args,
                    content,
                    content_params,
                    pos,
                    length,
                    parents,
                    sink,
                );
                return;
            }
            if let bhit: root.std.Tuple2<string, string> = builtin_hits.at(0) {
                let owner = bhit._0;
                let bare = bhit._1;
                if (owner == "meta" && bare == "apply") {
                    self.exec_apply(args, content, content_params, pos, length, parents, sink);
                    return;
                }
                if (owner == "meta" && bare == "load-css") {
                    self.exec_load_css(args, content, pos, parents, sink);
                    return;
                }
            }
        }
        let mixin = self.lookup_mixin(name);
        if (mixin == null) {
            throw root.error.Error.at("Undefined mixin.", pos).with_length(full_length);
        }
        // dart-sass: passing a content block to a mixin that never uses
        // `@content` is an error, even when the block is empty.
        if (content != null && !root.eval.body_uses_content(mixin.def.body)) {
            // Raised BEFORE the mixin is entered, so its own frame is not on
            // the stack — dart shows only the caller's.
            throw self.error_with_declaration_at(
                "Mixin doesn't accept a content block.",
                pos,
                length,
                declared(mixin),
            );
        }
        // Arguments evaluate in the caller's environment; the body runs in
        // the mixin's lexical closure. The content block captures the CALL
        // SITE so `@content` sees the includer's variables.
        let evaled_spans = self.eval_call_args_spanned(args);
        let evaled = evaled_spans._0;
        let arg_spans = evaled_spans._1;
        let content_block: root.eval.ContentBlock? = if let stmts: root.ast.Stmt[] = content {
            let snapshot = self.snapshot_env();
            root.eval.ContentBlock {
                stmts: stmts,
                params: content_params,
                caller_env: snapshot,
                origin: self.current_mixin_origin(),
            }
        } else {
            null
        };
        // The body runs against the mixin's defining file (the `@include`
        // frame, recorded by the caller, already names this file).
        let saved_file = self.enter_origin_file(mixin.origin);
        // PORT: `std::mem::replace(&mut self.x, mixin.env_x.clone())` → save the
        // current chain, install a shallow copy of the captured one.
        let saved_scopes = self.scopes;
        self.scopes = root.std.clone_vec(mixin.env);
        let saved_var_spans = self.var_spans;
        self.var_spans = root.std.clone_vec(mixin.env_spans);
        let saved_semi = self.scope_semi_global;
        self.scope_semi_global = root.std.clone_vec(mixin.env_semi);
        let saved_fns = self.functions;
        self.functions = root.std.clone_vec(mixin.env_fns);
        let saved_mixins = self.mixins;
        self.mixins = root.std.clone_vec(mixin.env_mixins);
        let saved_env_modules = self.install_env_modules(mixin.env_modules);
        self.push_scope(false);
        // PORT: the `Result` chain (`bind … .and_then(…).map_err(…)`) is caught
        // into `result: root.error.Error?`, re-thrown after the cleanup below.
        let result: root.error.Error? = null;
        self.bind_evaled_into_scope(mixin.def.params, evaled, arg_spans, declared(mixin)) catch (e) {
            let x: root.error.Error => {
                result = x;
            }
        };
        if (result == null) {
            self.content_stack.push(content_block);
            self.in_mixin.push(true);
            self.exec(mixin.def.body, parents, sink) catch (e) {
                let x: root.error.Error => {
                    result = x;
                }
            };
            let _ = self.in_mixin.pop();
            let _ = self.content_stack.pop();
        }
        if (result != null) {
            result = self.finalize_error(result);
        }
        self.pop_scope();
        self.scopes = saved_scopes;
        self.var_spans = saved_var_spans;
        self.scope_semi_global = saved_semi;
        self.functions = saved_fns;
        self.mixins = saved_mixins;
        self.restore_env_modules(saved_env_modules);
        self.leave_module_file(saved_file);
        if (result != null) {
            throw result;
        }
    }

    /// Execute an `@include ns.mixin` where `ns` is a user module: run the mixin
    /// body in the module's own environment, while its `@content` block (if any)
    /// runs back in the call site's environment.
    function run_module_mixin(self, module: root.eval.Module, mixin: root.eval.UserCallable, args: root.ast.CallArg[], content: root.ast.Stmt[]?, content_params: root.ast.ParamList?, pos: root.scanner.Pos, length: int, parents: string[], sink: root.std.Cell<root.eval.Sink>) -> void {
        if (content != null && !root.eval.body_uses_content(mixin.def.body)) {
            // Raised BEFORE the mixin is entered, so its own frame is not on
            // the stack — dart shows only the caller's.
            throw self.error_with_declaration_at(
                "Mixin doesn't accept a content block.",
                pos,
                length,
                declared(mixin),
            );
        }
        // Evaluate the arguments at the call site (so they resolve in the
        // caller's scope), then enter the module's environment and the
        // mixin's lexical closure for the body. Snapshot the call-site env
        // so a `@content` block runs there, not in the module.
        let evaled_spans = self.eval_call_args_spanned(args);
        let evaled = evaled_spans._0;
        let arg_spans = evaled_spans._1;
        let content_block: root.eval.ContentBlock? = if let stmts: root.ast.Stmt[] = content {
            let snapshot = self.snapshot_env();
            root.eval.ContentBlock {
                stmts: stmts,
                params: content_params,
                caller_env: snapshot,
                origin: self.current_mixin_origin(),
            }
        } else {
            null
        };
        let saved = self.enter_module(module);
        // The mixin's own defining file beats the module handed to us: a
        // multi-hop `@forward` can name a module other than the file that
        // wrote the mixin.
        let saved_file = self.enter_origin_file(mixin.origin);
        // PORT: `std::mem::replace(&mut self.x, mixin.env_x.clone())` → save the
        // current chain, install a shallow copy of the captured one.
        let saved_scopes = self.scopes;
        self.scopes = root.std.clone_vec(mixin.env);
        let saved_var_spans = self.var_spans;
        self.var_spans = root.std.clone_vec(mixin.env_spans);
        let saved_semi = self.scope_semi_global;
        self.scope_semi_global = root.std.clone_vec(mixin.env_semi);
        let saved_fns = self.functions;
        self.functions = root.std.clone_vec(mixin.env_fns);
        let saved_mixins = self.mixins;
        self.mixins = root.std.clone_vec(mixin.env_mixins);
        let saved_env_modules = self.install_env_modules(mixin.env_modules);
        self.push_scope(false);
        // PORT: the `Result` chain is caught into `result`, re-thrown after the
        // cleanup below.
        let result: root.error.Error? = null;
        self.bind_evaled_into_scope(mixin.def.params, evaled, arg_spans, declared(mixin)) catch (e) {
            let x: root.error.Error => {
                result = x;
            }
        };
        if (result == null) {
            self.content_stack.push(content_block);
            // A mixin body: `meta.content-exists()` is allowed and answers
            // for THIS include (as on the direct include path).
            self.in_mixin.push(true);
            self.exec(mixin.def.body, parents, sink) catch (e) {
                let x: root.error.Error => {
                    result = x;
                }
            };
            let _ = self.in_mixin.pop();
            let _ = self.content_stack.pop();
        }
        if (result != null) {
            result = self.finalize_error(result);
        }
        self.pop_scope();
        self.scopes = saved_scopes;
        self.var_spans = saved_var_spans;
        self.scope_semi_global = saved_semi;
        self.functions = saved_fns;
        self.mixins = saved_mixins;
        self.restore_env_modules(saved_env_modules);
        self.leave_module_file(saved_file);
        self.leave_module(saved);
        if (result != null) {
            throw result;
        }
    }

    /// `@include meta.apply($mixin, $args...)`: invoke a first-class mixin
    /// reference. The first argument is the mixin reference; the rest are the
    /// arguments passed on to that mixin (which may also accept a `@content`
    /// block).
    function exec_apply(self, args: root.ast.CallArg[], content: root.ast.Stmt[]?, content_params: root.ast.ParamList?, pos: root.scanner.Pos, length: int, parents: string[], sink: root.std.Cell<root.eval.Sink>) -> void {
        // (parameter note) `length`: the CALL's byte length, content block
        // excluded — what an error about the call itself carets, exactly as a
        // direct `@include` does.
        // Evaluate apply's own arguments (expanding any `...` splat). The first
        // positional (or named `$mixin`) is the mixin reference; the remainder
        // are forwarded to the mixin.
        let evaled = self.eval_call_args(args);
        let pos_args = evaled._0;
        let named = evaled._1;
        // PORT: the in-place `*v = … .without_slash()` rewrites → index loops
        // (both vectors were freshly built by `eval_call_args`).
        let i = 0;
        while (i < pos_args.length()) {
            pos_args[i] = pos_args[i].without_slash();
            i += 1;
        }
        let j = 0;
        while (j < named.length()) {
            named[j] = root.std.Tuple2 { _0: named[j]._0, _1: named[j]._1.without_slash() };
            j += 1;
        }
        self.apply_evaled(
            pos_args,
            named,
            content,
            content_params,
            pos,
            length,
            parents,
            sink,
        );
    }

    /// `meta.apply` with its arguments already evaluated — the form a
    /// first-class reference to it arrives in.
    function apply_evaled(self, pos_args: root.value.Value[], named: root.std.Tuple2<string, root.value.Value>[], content: root.ast.Stmt[]?, content_params: root.ast.ParamList?, pos: root.scanner.Pos, length: int, parents: string[], sink: root.std.Cell<root.eval.Sink>) -> void {
        // (parameter note) `pos`/`length`: the `@include` this invocation came
        // from — what an error inside the mixin carets, exactly as a direct
        // `@include meta.load-css(…)` does.
        // PORT: `(Value, Vec<Value>)` tuple → two locals.
        let mixin_val: root.value.Value = root.value.Value_Null {};
        let rest_pos: root.value.Value[] = [];
        if (pos_args.length() > 0) {
            let first = pos_args.at(0) ?? root.value.Value_Null {};
            mixin_val = first;
            rest_pos = pos_args.slice(1, pos_args.length());
        } else if let idx: int = named.find_index((p) -> { p._0 == "mixin" }) {
            mixin_val = root.std.unwrap(named.remove_at(idx))._1;
            rest_pos = [];
        } else {
            throw root.error.Error.unpositioned("Missing argument $mixin.");
        }
        let rest_named: root.std.Tuple2<string, root.value.Value>[] = named.filter((p) -> { p._0 != "mixin" });
        let mixin = match (mixin_val) {
            let m: root.value.Value_Mixin => m._0,
            let other: root.value.Value => {
                throw root.error.Error.unpositioned(
                    `$mixin: ${other.to_css(false)} is not a mixin reference.`,
                );
            }
        };
        self.invoke_mixin_ref(
            mixin,
            rest_pos,
            rest_named,
            content,
            content_params,
            pos,
            length,
            parents,
            sink,
        );
    }

    /// Invoke a resolved mixin reference with already-evaluated arguments and an
    /// optional `@content` block, emitting into `sink`.
    function invoke_mixin_ref(self, mixin: root.value.SassMixin, pos_args: root.value.Value[], named: root.std.Tuple2<string, root.value.Value>[], content: root.ast.Stmt[]?, content_params: root.ast.ParamList?, pos: root.scanner.Pos, length: int, parents: string[], sink: root.std.Cell<root.eval.Sink>) -> void {
        // A captured user `@mixin`: recover the type-erased `Callable`.
        let callable: root.eval.UserCallable = if (mixin.user != null) {
            match (mixin.user) {
                let c: root.eval.UserCallable => c,
                _ => {
                    throw root.error.Error.unpositioned("Undefined mixin.");
                }
            }
        } else {
            // A built-in mixin reference (`meta.load-css`/`meta.apply`): dart
            // invokes it like any other, so dispatch by name.
            match (mixin.name.replace_all("_", "-")) {
                "load-css" => {
                    self.load_css_evaled(pos_args, named, content, pos, parents, sink);
                    return;
                }
                "apply" => {
                    self.apply_evaled(
                        pos_args,
                        named,
                        content,
                        content_params,
                        pos,
                        length,
                        parents,
                        sink,
                    );
                    return;
                }
                _ => {
                    if (content != null) {
                        throw root.error.Error.unpositioned("Mixin doesn't accept a content block.");
                    }
                    throw root.error.Error.unpositioned("Undefined mixin.");
                }
            }
        };
        if (content != null && !root.eval.body_uses_content(callable.def.body)) {
            // Raised BEFORE the mixin is entered, so its own frame is not on
            // the stack — dart shows only the caller's.
            throw self.error_with_declaration_at(
                "Mixin doesn't accept a content block.",
                pos,
                length,
                declared(callable),
            );
        }
        let content_block: root.eval.ContentBlock? = if let stmts: root.ast.Stmt[] = content {
            let snapshot = self.snapshot_env();
            root.eval.ContentBlock {
                stmts: stmts,
                params: content_params,
                caller_env: snapshot,
                origin: self.current_mixin_origin(),
            }
        } else {
            null
        };
        // A mixin captured from another module runs in that module's
        // environment; either way the body runs in its lexical closure and
        // the `@content` block runs back at the call site.
        let module: root.eval.Module? = match (mixin.module) {
            let m: root.eval.Module => m,
            _ => null,
        };
        let saved: root.eval.SavedModuleEnv? = if (module != null) {
            self.enter_module(module)
        } else {
            null
        };
        // Frames inside the body name the mixin itself (`m()`), not the
        // `meta.apply` that invoked it.
        let saved_member_name = self.member;
        self.member = `${callable.def.name}()`;
        // The body runs against the mixin's defining file (so its output and
        // diagnostics belong there, and a relative `meta.load-css` resolves
        // against it): the callable's own capture, which every callable has.
        let saved_file = self.enter_origin_file(callable.origin);
        // PORT: `std::mem::replace(&mut self.x, callable.env_x.clone())` → save
        // the current chain, install a shallow copy of the captured one.
        let saved_scopes = self.scopes;
        self.scopes = root.std.clone_vec(callable.env);
        let saved_var_spans = self.var_spans;
        self.var_spans = root.std.clone_vec(callable.env_spans);
        let saved_semi = self.scope_semi_global;
        self.scope_semi_global = root.std.clone_vec(callable.env_semi);
        let saved_fns = self.functions;
        self.functions = root.std.clone_vec(callable.env_fns);
        let saved_mixins = self.mixins;
        self.mixins = root.std.clone_vec(callable.env_mixins);
        let saved_env_modules = self.install_env_modules(callable.env_modules);
        self.push_scope(false);
        // A first-class mixin reference arrives here with already-evaluated,
        // RESHUFFLED arguments (`meta.apply` strips `$mixin` off the front), so
        // the caller's per-argument spans no longer line up positionally. Bind
        // with no spans: the parameters get the "unknown" span and emit no
        // mapping segment, rather than a plausible-but-wrong one.
        // PORT: the `Result` chain is caught into `result`, re-thrown after the
        // cleanup below.
        let result: root.error.Error? = null;
        let comma: root.value.ListSep = root.value.ListSep.Comma;
        self.bind_evaled_into_scope(
            callable.def.params,
            root.std.Tuple3 { _0: pos_args, _1: named, _2: comma },
            root.eval.ArgSpans.default(),
            declared(callable),
        ) catch (e) {
            let x: root.error.Error => {
                result = x;
            }
        };
        if (result == null) {
            self.content_stack.push(content_block);
            self.in_mixin.push(true);
            self.exec(callable.def.body, parents, sink) catch (e) {
                let x: root.error.Error => {
                    result = x;
                }
            };
            let _ = self.in_mixin.pop();
            let _ = self.content_stack.pop();
        }
        if (result != null) {
            result = self.finalize_error(result);
        }
        self.pop_scope();
        self.scopes = saved_scopes;
        self.var_spans = saved_var_spans;
        self.scope_semi_global = saved_semi;
        self.functions = saved_fns;
        self.mixins = saved_mixins;
        self.restore_env_modules(saved_env_modules);
        self.leave_module_file(saved_file);
        self.member = saved_member_name;
        if (saved != null) {
            self.leave_module(saved);
        }
        if (result != null) {
            throw result;
        }
    }

    /// Run the innermost active `@content` block. For a cross-module include the
    /// block carries a snapshot of the call-site environment, which is installed
    /// for the duration so the content resolves there rather than in the mixin's
    /// module.
    function exec_content(self, args: root.ast.CallArg[], pos: root.scanner.Pos, parents: string[], sink: root.std.Cell<root.eval.Sink>) -> void {
        // PORT: `match self.content_stack.last() { Some(Some(block)) => …, _ =>
        // return }` — both `None` and `Some(None)` read back as `null`.
        let block: root.eval.ContentBlock? = root.std.last(self.content_stack);
        if (block == null) {
            return;
        }
        let stmts = block.stmts;
        let params = block.params;
        // PORT: `(**e).clone()` → a field-wise shallow copy: the frames stay
        // shared, but the chain vectors installed below are this call's own
        // (the evaluator pushes/pops on them; the block's snapshot must not move).
        let caller_env: root.eval.SavedModuleEnv? = if let e: root.eval.SavedModuleEnv = block.caller_env {
            root.eval.SavedModuleEnv {
                scopes: root.std.clone_vec(e.scopes),
                var_spans: root.std.clone_vec(e.var_spans),
                scope_semi_global: root.std.clone_vec(e.scope_semi_global),
                functions: root.std.clone_vec(e.functions),
                mixins: root.std.clone_vec(e.mixins),
                used_modules: root.std.clone_map(e.used_modules),
                star_modules: root.std.clone_vec(e.star_modules),
                used_user_modules: root.std.clone_map(e.used_user_modules),
                star_user_modules: root.std.clone_vec(e.star_user_modules),
                write_back: e.write_back,
            }
        } else {
            null
        };
        let origin = block.origin;
        // `@content(args)` evaluates its arguments at the call site (the mixin
        // body); they are bound to the block's `using (params)` below, once the
        // block's own environment is in place, so a parameter DEFAULT evaluates
        // where the block was written (dart: a content block is a callable
        // closing over its `@include`; `using ($y: $caller)` sees the
        // includer's `$caller`, not the mixin module's variables).
        let evaled: root.std.Tuple2<root.eval.EvaledArgs, root.eval.ArgSpans>? = match (params) {
            let _p: root.ast.ParamList => self.eval_call_args_spanned(args),
            null => {
                // A content block with no `using (params)` accepts no
                // arguments; passing any is an error (dart-sass).
                if (args.length() > 0) {
                    let n = args.length();
                    let verb = if (n == 1) { "was" } else { "were" };
                    throw root.error.Error.unpositioned(
                        `Only 0 arguments allowed, but ${n} ${verb} passed.`,
                    );
                }
                null
            }
        };
        // dart's trace: the `@content;` statement is a call site in the mixin
        // body (a frame in the mixin's file, attributed to the mixin), and the
        // block's own statements belong to the `@content` member, back in the
        // file that wrote the block — where its output maps to as well.
        let saved_member = self.enter_content_call(pos);
        let saved_file = self.enter_origin_file(origin);
        let restore: root.eval.SavedModuleEnv? = if (caller_env != null) {
            self.install_env(caller_env)
        } else {
            null
        };
        // A content block is a user-defined callable in dart: its body always
        // runs in a fresh child scope, so a `$var:` first declared inside it
        // stays local to the block (and the `using` parameters bind there).
        self.push_scope(false);
        // The block runs in its DEFINITION environment's content context: a
        // `@content` inside it forwards to the block one level up, not to
        // itself (a recursive mixin chaining `@content` must terminate).
        // PORT: `pop()` yields `Option<Option<ContentBlock>>`; whether a slot
        // was popped at all is kept in `had_running`.
        let had_running = self.content_stack.length() > 0;
        let running = self.content_stack.pop();
        // PORT: the `Result` chain is caught into `result`, re-thrown after the
        // cleanup below; `match (&params, evaled)` → nested `if`s.
        let result: root.error.Error? = null;
        if (params != null) {
            if (evaled != null) {
                self.bind_evaled_into_scope(
                    params,
                    evaled._0,
                    evaled._1,
                    // A `using (…)` clause has no `name(params)` declaration to
                    // point back at; dart reports these against the call alone.
                    root.eval.Declared {
                        pos: root.scanner.Pos.NONE(),
                        length: 0,
                        origin: null,
                    },
                ) catch (e) {
                    let x: root.error.Error => {
                        result = x;
                    }
                };
            }
        }
        if (result == null) {
            self.exec(stmts, parents, sink) catch (e) {
                let x: root.error.Error => {
                    result = x;
                }
            };
        }
        if (result != null) {
            result = self.finalize_error(result);
        }
        if (had_running) {
            self.content_stack.push(running);
        }
        self.pop_scope();
        if (restore != null) {
            self.leave_module(restore);
        }
        self.leave_module_file(saved_file);
        self.leave_call(saved_member);
        if (result != null) {
            throw result;
        }
    }

    /// The lazy `if($condition, $if-true, $if-false)` function: evaluates
    /// the condition, then only the selected branch.
    function eval_if_function(self, args: root.ast.CallArg[], pos: root.scanner.Pos) -> root.value.Value {
        // PORT: the fn-local `enum IfArg` and `fn slot_index` are hoisted below
        // the `implements` block (`IfArg`, `eval_if_function__slot_index`).
        let by_pos: IfArg[] = [];
        // $condition / $if-true / $if-false by name.
        let named: (IfArg?)[] = [null, null, null];
        for (let a in args) {
            if (a.splat) {
                match (self.eval_expr(a.value)) {
                    let l: root.value.Value_List => {
                        let kw = l._0.keywords;
                        if (kw != null) {
                            for (let kv in kw) {
                                if let s: root.value.Value_Str = kv._0 {
                                    match (eval_if_function__slot_index(s._0.text)) {
                                        let i: int => {
                                            named[i] = IfArg_Eager { _0: kv._1 };
                                        }
                                        null => {
                                            throw root.error.Error.at(
                                                `if() has no argument named $${s._0.text}.`,
                                                pos,
                                            );
                                        }
                                    }
                                }
                            }
                        }
                        for (let item in l._0.items) {
                            by_pos.push(IfArg_Eager { _0: item });
                        }
                    }
                    let m: root.value.Value_Map => {
                        for (let kv in m._0.entries) {
                            let name = match (kv._0) {
                                let s: root.value.Value_Str => s._0.text,
                                let other: root.value.Value => {
                                    throw root.error.Error.at(
                                        `Variable keyword argument map must have string keys.\n${other.to_css(false)} is not a string.`,
                                        pos,
                                    );
                                }
                            };
                            match (eval_if_function__slot_index(name)) {
                                let i: int => {
                                    named[i] = IfArg_Eager { _0: kv._1 };
                                }
                                null => {
                                    throw root.error.Error.at(
                                        `if() has no argument named $${name}.`,
                                        pos,
                                    );
                                }
                            }
                        }
                    }
                    let other: root.value.Value => {
                        by_pos.push(IfArg_Eager { _0: other });
                    }
                }
                continue;
            }
            match (a.name) {
                let name: string => match (eval_if_function__slot_index(name)) {
                    let i: int => {
                        named[i] = IfArg_Lazy { _0: a.value };
                    }
                    null => {
                        throw root.error.Error.at(`if() has no argument named $${name}.`, pos);
                    }
                },
                null => {
                    by_pos.push(IfArg_Lazy { _0: a.value });
                }
            }
        }
        let cond: IfArg? = named[0];
        let t_val: IfArg? = named[1];
        let f_val: IfArg? = named[2];
        // PORT: `by_pos.into_iter()` + `x.or_else(|| pos_iter.next())` → an
        // index cursor, advanced only for a slot not already filled by name.
        let pos_next = 0;
        if (cond == null) {
            cond = by_pos.at(pos_next);
            pos_next += 1;
        }
        if (t_val == null) {
            t_val = by_pos.at(pos_next);
            pos_next += 1;
        }
        if (f_val == null) {
            f_val = by_pos.at(pos_next);
            pos_next += 1;
        }
        // PORT: `match (cond, t_val, f_val)` → nested `if`s; falling through is
        // the `_` arm.
        if (cond != null) {
            if (t_val != null) {
                if (f_val != null) {
                    let truthy = match (cond) {
                        let e: IfArg_Lazy => self.eval_expr(e._0).is_truthy(),
                        let v: IfArg_Eager => v._0.is_truthy(),
                        _ => root.std.unreachable(),
                    };
                    // if() is a function boundary: a bare slash-division branch
                    // collapses to its number (dart-sass `withoutSlash`).
                    let branch = if (truthy) { t_val } else { f_val };
                    return match (branch) {
                        let e: IfArg_Lazy => self.eval_expr(e._0).without_slash(),
                        let v: IfArg_Eager => v._0.without_slash(),
                        _ => root.std.unreachable(),
                    };
                }
            }
        }
        throw root.error.Error.at(
            "if() requires arguments $condition, $if-true, $if-false.",
            pos,
        );
    }

    /// Evaluate a modern CSS `if()`: a `;`-separated list of clauses, each
    /// `<condition>: <value>` (or `else: <value>`). Conditions mix evaluated
    /// `sass(<expr>)` with non-evaluable `css(...)` / arbitrary substitution
    /// pieces. If every reachable condition resolves statically, the matching
    /// value is returned; otherwise the whole `if()` is re-serialized
    /// verbatim (with statically-true/false conditions folded away) as an
    /// unquoted string.
    function eval_modern_if(self, clauses: root.ast.IfClause[]) -> root.value.Value {
        let verbatim: string[]? = null;
        for (let clause in clauses) {
            // The `else` clause has no condition: it always matches.
            let result: root.eval.CondEval = match (clause.condition) {
                null => root.eval.CondEval_Bool { _0: true },
                let cond: root.ast.IfCond => self.eval_if_cond(cond),
            };
            // PORT: `match (&mut verbatim, result)` → an `if` on `verbatim`, then
            // a `match` on `result`.
            if let out: string[] = verbatim {
                match (result) {
                    // Already verbatim: fold each remaining clause.
                    root.eval.CondEval_Bool { _0: true } => {
                        let value = self.eval_if_value(clause.value);
                        out.push(`else: ${value}`);
                    }
                    root.eval.CondEval_Bool { _0: false } => {}
                    let rc: root.eval.CondEval_Css => {
                        let value = self.eval_if_value(clause.value);
                        out.push(`${rc._0.to_css()}: ${value}`);
                    }
                    _ => root.std.unreachable(),
                }
            } else {
                match (result) {
                    // Not yet verbatim: a static-true (or `else`) clause wins.
                    root.eval.CondEval_Bool { _0: true } => {
                        return self.eval_expr(clause.value).without_slash();
                    }
                    // Not yet verbatim: a static-false clause is skipped.
                    root.eval.CondEval_Bool { _0: false } => {}
                    // First non-evaluable condition: enter verbatim mode.
                    let rc: root.eval.CondEval_Css => {
                        let value = self.eval_if_value(clause.value);
                        verbatim = [`${rc._0.to_css()}: ${value}`];
                    }
                    _ => root.std.unreachable(),
                }
            }
        }
        match (verbatim) {
            let parts: string[] => root.value.Value_Str {
                _0: root.value.SassStr {
                    text: `if(${parts.join("; ")})`,
                    quoted: false,
                },
            },
            // No clause matched and no `else`: the modern `if()` is null.
            null => root.value.Value_Null {},
        }
    }

    /// Evaluate an `if()` clause value. dart-sass emits it in plain CSS
    /// serialization format (since 1.101.4), not `meta.inspect()` format.
    function eval_if_value(self, expr: root.ast.Expr) -> string {
        // No without_slash: dart serializes the clause value as-is, so a
        // preserved slash-division (`20/10`) keeps its slash form.
        let v = self.eval_expr(expr);
        root.eval.serialize_if_value(v)
    }

    /// Evaluate a modern `if()` condition into a tri-state result: a static
    /// boolean (from `sass(...)` atoms) or a residual non-evaluable CSS
    /// condition that must be re-serialized verbatim.
    function eval_if_cond(self, cond: root.ast.IfCond) -> root.eval.CondEval {
        match (cond) {
            let s: root.ast.IfCond_Sass => root.eval.CondEval_Bool { _0: self.eval_expr(s._0).is_truthy() },
            let r: root.ast.IfCond_Raw => {
                let text = self.eval_template(r.pieces);
                // dart re-serializes the raw token run with collapsed
                // whitespace and no space inside empty parens
                // (`css(\n)` is `css()`).
                let collapsed = root.std.StrBuf.new();
                let prev_ws = false;
                for (let c in text.chars()) {
                    if (root.std.is_whitespace(c)) {
                        prev_ws = true;
                        continue;
                    }
                    if (prev_ws && !collapsed.is_empty() && c != ")") {
                        collapsed.push(" ");
                    }
                    prev_ws = false;
                    collapsed.push(c);
                }
                let collapsed = collapsed.as_str().replace_all("( ", "(");
                root.eval.CondEval_Css { _0: root.eval.RCond_Css { _0: collapsed } }
            }
            let n: root.ast.IfCond_Not => match (self.eval_if_cond(n._0)) {
                let b: root.eval.CondEval_Bool => root.eval.CondEval_Bool { _0: !b._0 },
                let rc: root.eval.CondEval_Css => root.eval.CondEval_Css { _0: root.eval.RCond_Not { _0: rc._0 } },
                _ => root.std.unreachable(),
            },
            let p: root.ast.IfCond_Paren => match (self.eval_if_cond(p._0)) {
                let b: root.eval.CondEval_Bool => root.eval.CondEval_Bool { _0: b._0 },
                let rc: root.eval.CondEval_Css => root.eval.CondEval_Css { _0: root.eval.RCond_Paren { _0: rc._0 } },
                _ => root.std.unreachable(),
            },
            let a: root.ast.IfCond_And => {
                let residuals: root.eval.RCond[] = [];
                for (let item in a._0) {
                    match (self.eval_if_cond(item)) {
                        // A statically-false operand makes the whole `and`
                        // false and short-circuits the rest.
                        root.eval.CondEval_Bool { _0: false } => {
                            return root.eval.CondEval_Bool { _0: false };
                        }
                        // A statically-true operand drops out of the `and`.
                        root.eval.CondEval_Bool { _0: true } => {}
                        let rc: root.eval.CondEval_Css => {
                            residuals.push(rc._0);
                        }
                        _ => root.std.unreachable(),
                    }
                }
                root.eval.combine_residuals(residuals, true)
            }
            let o: root.ast.IfCond_Or => {
                let residuals: root.eval.RCond[] = [];
                for (let item in o._0) {
                    match (self.eval_if_cond(item)) {
                        // A statically-true operand makes the whole `or`
                        // true and short-circuits the rest.
                        root.eval.CondEval_Bool { _0: true } => {
                            return root.eval.CondEval_Bool { _0: true };
                        }
                        // A statically-false operand drops out of the `or`.
                        root.eval.CondEval_Bool { _0: false } => {}
                        let rc: root.eval.CondEval_Css => {
                            residuals.push(rc._0);
                        }
                        _ => root.std.unreachable(),
                    }
                }
                root.eval.combine_residuals(residuals, false)
            }
            _ => root.std.unreachable(),
        }
    }

}

/// An argument of the lazy `if()` function (hoisted from
/// `Evaluator::eval_if_function`, where it is a fn-local `enum IfArg<'a>`).
/// An argument is lazy (an unevaluated branch expression) unless it
/// came from a `...` splat: dart's macro-argument handling evaluates
/// the splat eagerly and reconstitutes its elements (and an argument
/// list's keywords) as already-evaluated arguments.
interface IfArg {}

class IfArg_Lazy {
    _0: root.ast.Expr,
    implements IfArg {}
}

class IfArg_Eager {
    _0: root.value.Value,
    implements IfArg {}
}

/// Hoisted from `Evaluator::eval_if_function` (fn-local `fn slot_index`).
function eval_if_function__slot_index(name: string) -> int? {
    match (name) {
        "condition" => 0,
        "if-true" => 1,
        "if-false" => 2,
        _ => null,
    }
}

/// The declaration description a bound callable carries: its `name(params)`
/// span, in the file it was written in.
function declared(callable: root.eval.UserCallable) -> root.eval.Declared {
    root.eval.Declared {
        pos: callable.def.decl_pos,
        length: callable.def.decl_length,
        origin: callable.origin,
    }
}
