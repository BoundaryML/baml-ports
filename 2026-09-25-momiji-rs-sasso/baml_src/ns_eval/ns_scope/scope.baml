// Ported from sasso `src/eval/scope.rs` (namespace `root.eval.scope`).

interface EvaluatorScope {
    // ---- scopes ------------------------------------------------------
    function lookup(self, name: string) -> root.value.Value? throws unknown;

    /// The DEFINITION span of `name`, innermost frame first — dart
    /// `Environment.getVariableNode` (environment.dart:488). Walks the same
    /// chain as [`Self::lookup`], falling back to the `@use … as *` modules the
    /// value lookup would have reached. Source-map only.
    function lookup_var_span(self, name: string) -> root.eval.VarSpan? throws unknown;

    /// dart `_expressionNode` (evaluate.dart:4538): the node whose span should
    /// be blamed for `expr`'s value. A bare variable reference resolves to
    /// wherever that variable was DEFINED (transitively — `$b: $a` stored `$a`'s
    /// own definition node, so `$b` reaches the original literal); every other
    /// expression shape is its own node, which is `fallback` (the position where
    /// `expr`'s text starts in the current file).
    ///
    /// Note the asymmetry this bakes in, and which dart's boundary confirms:
    /// only a BARE `$x` resolves. `$x * 2`, `f($x)`, `#{$x}` and `$x $x` are
    /// `Binary`/`Func`/`Interp`/`List` nodes, so they keep their own span.
    function expression_node(
        self,
        expr: root.ast.Expr,
        fallback: root.scanner.Pos,
    ) -> root.eval.VarSpan throws unknown;

    /// The definition span of a `ns.$name` module variable, following a
    /// `@forward` to the module that actually defines it (dart
    /// `_getVariableNodeFromGlobalModule` / `Module.variableNodes`).
    function module_var_span(self, ns: string, name: string) -> root.eval.VarSpan? throws unknown;

    /// Turn a 1-based source position in the CURRENT file into a [`VarSpan`]
    /// (interned file id + 0-based line/col). [`Pos::NONE`] yields the "unknown"
    /// span, which the source map drops.
    function span_at(self, pos: root.scanner.Pos) -> root.eval.VarSpan throws unknown;

    /// Capture the current variable and function/mixin scope chains as a
    /// callable's lexical closure (dart `Environment.closure()` — shared
    /// frames, not snapshots).
    function capture_callable(
        self,
        def: root.ast.Callable,
    ) -> root.eval.UserCallable throws unknown;

    /// Rebind an existing callable's variable/function/mixin scopes to the
    /// current environment while keeping what belongs to its DEFINITION: the
    /// file it was written in and the `@use` namespaces it closed over. A
    /// member `@forward`ed through a textual `@import` becomes a member of the
    /// importing scope (dart's import is textual inclusion), but its body
    /// still maps to and diagnoses against the file that wrote it, and still
    /// resolves `math.div` through THAT file's `@use "sass:math"`.
    function recapture_callable(
        self,
        src: root.eval.UserCallable,
    ) -> root.eval.UserCallable throws unknown;

    function capture_callable_from(
        self,
        def: root.ast.Callable,
        origin: root.value.MixinOrigin,
        env_modules: root.eval.EnvModules,
    ) -> root.eval.UserCallable throws unknown;

    /// Install a callable's captured `@use` namespace tables for the duration
    /// of its body, returning the caller's tables for [`Self::restore_env_modules`].
    function install_env_modules(
        self,
        m: root.eval.EnvModules,
    ) -> root.eval.EnvModules throws unknown;

    function restore_env_modules(self, saved: root.eval.EnvModules) -> void throws unknown;

    /// Push a new scope. `semi_global` requests semi-global behavior (control
    /// flow), which only takes effect when the current innermost scope is
    /// already semi-global (dart-sass `Environment.scope`). The function and
    /// mixin chains push in lockstep with the variable chain.
    function push_scope(self, semi_global: bool) -> void throws unknown;

    function pop_scope(self) -> void throws unknown;

    /// Define a user `@function` in the innermost frame (dart
    /// `visitFunctionRule`: always `_functions.length - 1`, no semi-global
    /// special case), so the definition is scoped to the enclosing block.
    /// Keys are dash-normalized like dart's parse-time `identifier(normalize:
    /// true)` — `@function a_b` and `@function a-b` define the SAME name (the
    /// AST keeps the original spelling for plain-CSS fallback and messages).
    function define_function(self, name: string, c: root.eval.UserCallable) -> void throws unknown;

    /// Define a user `@mixin` in the innermost frame (dart `visitMixinRule`).
    function define_mixin(self, name: string, c: root.eval.UserCallable) -> void throws unknown;

    /// Look up a user `@function` (dash/underscore-insensitively, like dart),
    /// innermost frame first.
    function lookup_function(self, name: string) -> root.eval.UserCallable? throws unknown;

    /// Look up a user `@mixin` (dash/underscore-insensitively), innermost
    /// frame first.
    function lookup_mixin(self, name: string) -> root.eval.UserCallable? throws unknown;

    /// Look up a user `@function` dash/underscore-insensitively (for the
    /// `meta` introspection functions), innermost frame first.
    function lookup_function_norm(self, key: string) -> root.eval.UserCallable? throws unknown;

    /// Look up a user `@mixin` dash/underscore-insensitively, innermost first.
    function lookup_mixin_norm(self, key: string) -> root.eval.UserCallable? throws unknown;

    /// Assign a non-global variable (dart-sass `Environment.setVariable`). The
    /// value updates the variable at the innermost scope where it already
    /// exists; if it exists only in the global scope and the current scope is
    /// not semi-global, a new local is created instead so a nested rule cannot
    /// silently rewrite a global.
    function assign(
        self,
        name: string,
        val: root.value.Value,
        span: root.eval.VarSpan,
    ) -> void throws unknown;

    function apply_var(self, v: root.ast.VarDecl) -> void throws unknown;

    /// Assign to a `@use`d module's variable (`ns.$name: value`). The variable
    /// must already exist in the module and be public; `!default` only assigns
    /// when the existing value is null; built-in modules are immutable.
    function assign_module_var(self, ns: string, v: root.ast.VarDecl) -> void throws unknown;

    // ---- loop helpers ------------------------------------------------
    /// Set a variable in the innermost scope. A loop pushes its own scope, so a
    /// loop variable bound here lives in the loop's scope and is re-bound each
    /// iteration (dart-sass `setLocalVariable`).
    function set_local(
        self,
        name: string,
        val: root.value.Value,
        span: root.eval.VarSpan,
    ) -> void throws unknown;
}

implements EvaluatorScope for root.eval.Evaluator {
    // ---- scopes ------------------------------------------------------
    function lookup(self, name: string) -> root.value.Value? {
        // PORT: `.iter().rev()` → a descending index loop.
        let si = self.scopes.length();
        while (si > 0) {
            si -= 1;
            let v = self.scopes[si].get(name);
            if (v != null) {
                return v;
            }
        }
        null
    }

    /// The DEFINITION span of `name`, innermost frame first — dart
    /// `Environment.getVariableNode` (environment.dart:488). Walks the same
    /// chain as [`Self::lookup`], falling back to the `@use … as *` modules the
    /// value lookup would have reached. Source-map only.
    function lookup_var_span(self, name: string) -> root.eval.VarSpan? {
        // PORT: `.iter().rev()` → a descending index loop.
        let fi = self.var_spans.length();
        while (fi > 0) {
            fi -= 1;
            let sp = self.var_spans[fi].get(name);
            if (sp != null) {
                return sp;
            }
        }
        // A name resolved through `@use … as *` lives in the module's own
        // frame; mirror `eval_expr`'s fallback order so the span matches the
        // value that was actually read.
        if (!root.eval.is_private_member(name)) {
            for (let m in self.star_user_modules) {
                if (m.vars.has(name)) {
                    return m.var_spans.get(name);
                }
            }
        }
        null
    }

    /// dart `_expressionNode` (evaluate.dart:4538): the node whose span should
    /// be blamed for `expr`'s value. A bare variable reference resolves to
    /// wherever that variable was DEFINED (transitively — `$b: $a` stored `$a`'s
    /// own definition node, so `$b` reaches the original literal); every other
    /// expression shape is its own node, which is `fallback` (the position where
    /// `expr`'s text starts in the current file).
    ///
    /// Note the asymmetry this bakes in, and which dart's boundary confirms:
    /// only a BARE `$x` resolves. `$x * 2`, `f($x)`, `#{$x}` and `$x $x` are
    /// `Binary`/`Func`/`Interp`/`List` nodes, so they keep their own span.
    function expression_node(self, expr: root.ast.Expr, fallback: root.scanner.Pos) -> root.eval.VarSpan {
        if (!self.options.source_map) {
            return root.eval.VarSpan.default();
        }
        let resolved = match (expr) {
            let e: root.ast.Expr_Var => self.lookup_var_span(e.name),
            let e: root.ast.Expr_NsVar => self.module_var_span(e.module, e.name),
            _ => null,
        };
        match (resolved) {
            let sp: root.eval.VarSpan => sp,
            _ => self.span_at(fallback),
        }
    }

    /// The definition span of a `ns.$name` module variable, following a
    /// `@forward` to the module that actually defines it (dart
    /// `_getVariableNodeFromGlobalModule` / `Module.variableNodes`).
    function module_var_span(self, ns: string, name: string) -> root.eval.VarSpan? {
        let module = self.used_user_modules.get(ns);
        if (module == null) {
            return null;
        }
        let to = module.var_origin(name) ?? root.std.Tuple2<root.eval.Module, string> { _0: module, _1: name };
        let target = to._0;
        let orig = to._1;
        let sp = target.var_spans.get(orig);
        sp
    }

    /// Turn a 1-based source position in the CURRENT file into a [`VarSpan`]
    /// (interned file id + 0-based line/col). [`Pos::NONE`] yields the "unknown"
    /// span, which the source map drops.
    function span_at(self, pos: root.scanner.Pos) -> root.eval.VarSpan {
        if (!self.options.source_map || !pos.is_known()) {
            return root.eval.VarSpan.default();
        }
        root.eval.VarSpan {
            file: self.intern_current_file(),
            line: pos.line - 1,
            col: pos.col - 1,
        }
    }

    /// Capture the current variable and function/mixin scope chains as a
    /// callable's lexical closure (dart `Environment.closure()` — shared
    /// frames, not snapshots).
    function capture_callable(self, def: root.ast.Callable) -> root.eval.UserCallable {
        // PORT: the tables are copied (Rust `.clone()`): the evaluator keeps
        // mutating its own after the capture.
        let env_modules = root.eval.EnvModules {
            used_modules: root.std.clone_map(self.used_modules),
            star_modules: root.std.clone_vec(self.star_modules),
            used_user_modules: root.std.clone_map(self.used_user_modules),
            star_user_modules: root.std.clone_vec(self.star_user_modules),
        };
        self.capture_callable_from(def, self.current_mixin_origin(), env_modules)
    }

    /// Rebind an existing callable's variable/function/mixin scopes to the
    /// current environment while keeping what belongs to its DEFINITION: the
    /// file it was written in and the `@use` namespaces it closed over. A
    /// member `@forward`ed through a textual `@import` becomes a member of the
    /// importing scope (dart's import is textual inclusion), but its body
    /// still maps to and diagnoses against the file that wrote it, and still
    /// resolves `math.div` through THAT file's `@use "sass:math"`.
    function recapture_callable(self, src: root.eval.UserCallable) -> root.eval.UserCallable {
        // PORT: `src.env_modules.clone()` is an alias — a captured table set is
        // never mutated (`install_env_modules` copies it on the way in).
        self.capture_callable_from(src.def, src.origin, src.env_modules)
    }

    function capture_callable_from(self, def: root.ast.Callable, origin: root.value.MixinOrigin, env_modules: root.eval.EnvModules) -> root.eval.UserCallable {
        // The closure must SHARE the frames it captures, so every frame it
        // takes has to exist by the time it is cloned.
        root.eval.materialize_fn_frames(self.functions);
        root.eval.materialize_fn_frames(self.mixins);
        // PORT: `self.scopes.clone()` etc. copy the chain arrays (shallow): the
        // frames themselves stay shared, the evaluator's own chains keep
        // pushing and popping.
        root.eval.UserCallable {
            def: def,
            origin: origin,
            env: root.std.clone_vec(self.scopes),
            env_spans: root.std.clone_vec(self.var_spans),
            env_semi: root.std.clone_vec(self.scope_semi_global),
            env_fns: root.std.clone_vec(self.functions),
            env_mixins: root.std.clone_vec(self.mixins),
            env_modules: env_modules,
        }
    }

    /// Install a callable's captured `@use` namespace tables for the duration
    /// of its body, returning the caller's tables for [`Self::restore_env_modules`].
    function install_env_modules(self, m: root.eval.EnvModules) -> root.eval.EnvModules {
        // PORT: `std::mem::replace` per field → save, then assign a copy.
        let used_modules = self.used_modules;
        self.used_modules = root.std.clone_map(m.used_modules);
        let star_modules = self.star_modules;
        self.star_modules = root.std.clone_vec(m.star_modules);
        let used_user_modules = self.used_user_modules;
        self.used_user_modules = root.std.clone_map(m.used_user_modules);
        let star_user_modules = self.star_user_modules;
        self.star_user_modules = root.std.clone_vec(m.star_user_modules);
        root.eval.EnvModules {
            used_modules: used_modules,
            star_modules: star_modules,
            used_user_modules: used_user_modules,
            star_user_modules: star_user_modules,
        }
    }

    function restore_env_modules(self, saved: root.eval.EnvModules) -> void {
        self.used_modules = saved.used_modules;
        self.star_modules = saved.star_modules;
        self.used_user_modules = saved.used_user_modules;
        self.star_user_modules = saved.star_user_modules;
    }

    /// Push a new scope. `semi_global` requests semi-global behavior (control
    /// flow), which only takes effect when the current innermost scope is
    /// already semi-global (dart-sass `Environment.scope`). The function and
    /// mixin chains push in lockstep with the variable chain.
    function push_scope(self, semi_global: bool) -> void {
        let effective = semi_global && (root.std.last(self.scope_semi_global) ?? false);
        // A table left behind by a block that has already closed, if there is
        // one: a sheet's blocks come and go in strict LIFO order, and a scope
        // nothing captured is indistinguishable from a fresh one once cleared.
        let scope = self.scope_pool.pop() ?? root.eval.new_scope();
        self.scopes.push(scope);
        if (self.options.source_map) {
            let frame = self.span_pool.pop() ?? root.eval.new_span_scope();
            self.var_spans.push(frame);
        }
        self.scope_semi_global.push(effective);
        // Empty frames: the block gets a table only if it declares something
        // (or a closure captures the chain). See [`FnFrame`].
        self.functions.push(null);
        self.mixins.push(null);
    }

    function pop_scope(self) -> void {
        let scope = self.scopes.pop();
        if (scope != null) {
            root.eval.recycle_scope(self.scope_pool, scope);
        }
        let frame = self.var_spans.pop();
        if (frame != null) {
            root.eval.recycle_scope(self.span_pool, frame);
        }
        let _ = self.scope_semi_global.pop();
        let _ = self.functions.pop();
        let _ = self.mixins.pop();
    }

    /// Define a user `@function` in the innermost frame (dart
    /// `visitFunctionRule`: always `_functions.length - 1`, no semi-global
    /// special case), so the definition is scoped to the enclosing block.
    /// Keys are dash-normalized like dart's parse-time `identifier(normalize:
    /// true)` — `@function a_b` and `@function a-b` define the SAME name (the
    /// AST keeps the original spelling for plain-CSS fallback and messages).
    function define_function(self, name: string, c: root.eval.UserCallable) -> void {
        let last = self.functions.length() - 1;
        if (last >= 0) {
            // PORT: `get_or_insert_with(new_fn_scope)` on the frame slot.
            let frame = self.functions[last] ?? root.eval.new_fn_scope();
            self.functions[last] = frame;
            let _ = frame.set(root.eval.normalize_arg_name(name), c);
        }
    }

    /// Define a user `@mixin` in the innermost frame (dart `visitMixinRule`).
    function define_mixin(self, name: string, c: root.eval.UserCallable) -> void {
        let last = self.mixins.length() - 1;
        if (last >= 0) {
            // PORT: `get_or_insert_with(new_fn_scope)` on the frame slot.
            let frame = self.mixins[last] ?? root.eval.new_fn_scope();
            self.mixins[last] = frame;
            let _ = frame.set(root.eval.normalize_arg_name(name), c);
        }
    }

    /// Look up a user `@function` (dash/underscore-insensitively, like dart),
    /// innermost frame first.
    function lookup_function(self, name: string) -> root.eval.UserCallable? {
        let key = root.eval.normalize_arg_name(name);
        // PORT: `.iter().rev().flatten()` → a descending index loop skipping
        // empty frames.
        let fi = self.functions.length();
        while (fi > 0) {
            fi -= 1;
            let frame = self.functions[fi];
            if (frame != null) {
                let f = frame.get(key);
                if (f != null) {
                    return f;
                }
            }
        }
        null
    }

    /// Look up a user `@mixin` (dash/underscore-insensitively), innermost
    /// frame first.
    function lookup_mixin(self, name: string) -> root.eval.UserCallable? {
        let key = root.eval.normalize_arg_name(name);
        // PORT: `.iter().rev().flatten()` → a descending index loop skipping
        // empty frames.
        let fi = self.mixins.length();
        while (fi > 0) {
            fi -= 1;
            let frame = self.mixins[fi];
            if (frame != null) {
                let m = frame.get(key);
                if (m != null) {
                    return m;
                }
            }
        }
        null
    }

    /// Look up a user `@function` dash/underscore-insensitively (for the
    /// `meta` introspection functions), innermost frame first.
    function lookup_function_norm(self, key: string) -> root.eval.UserCallable? {
        let fi = self.functions.length();
        while (fi > 0) {
            fi -= 1;
            let frame = self.functions[fi];
            if (frame != null) {
                for (let k in frame.keys()) {
                    if (root.eval.normalize_arg_name(k) == key) {
                        return frame[k];
                    }
                }
            }
        }
        null
    }

    /// Look up a user `@mixin` dash/underscore-insensitively, innermost first.
    function lookup_mixin_norm(self, key: string) -> root.eval.UserCallable? {
        let fi = self.mixins.length();
        while (fi > 0) {
            fi -= 1;
            let frame = self.mixins[fi];
            if (frame != null) {
                for (let k in frame.keys()) {
                    if (root.eval.normalize_arg_name(k) == key) {
                        return frame[k];
                    }
                }
            }
        }
        null
    }

    /// Assign a non-global variable (dart-sass `Environment.setVariable`). The
    /// value updates the variable at the innermost scope where it already
    /// exists; if it exists only in the global scope and the current scope is
    /// not semi-global, a new local is created instead so a nested rule cannot
    /// silently rewrite a global.
    function assign(self, name: string, val: root.value.Value, span: root.eval.VarSpan) -> void {
        if (self.scopes.length() == 1) {
            let g = self.scopes.at(0);
            if (g != null) {
                let _ = g.set(name, val);
            }
            let gs = self.var_spans.at(0);
            if (gs != null) {
                let _ = gs.set(name, span);
            }
            return;
        }
        // Innermost scope index holding the variable (None if undeclared).
        let index: int? = null;
        let si = self.scopes.length();
        while (si > 0) {
            si -= 1;
            if (self.scopes[si].has(name)) {
                index = si;
                break;
            }
        }
        let in_semi_global = root.std.last(self.scope_semi_global) ?? false;
        let target = match (index) {
            0 if !in_semi_global => self.scopes.length() - 1,
            let i: int => i,
            _ => self.scopes.length() - 1,
        };
        let scope = self.scopes.at(target);
        if (scope != null) {
            let _ = scope.set(name, val);
        }
        // The span frame is the same index in the parallel chain (dart writes
        // `_variables[index]` and `_variableNodes[index]` together).
        let frame = self.var_spans.at(target);
        if (frame != null) {
            let _ = frame.set(name, span);
        }
    }

    function apply_var(self, v: root.ast.VarDecl) -> void {
        // A namespaced assignment `ns.$name: value` updates the variable in the
        // `@use`d module bound to `ns`.
        let ns = v.namespace;
        if (ns != null) {
            return self.assign_module_var(ns, v);
        }
        // A top-level `!default` declaration whose name is exposed by more than
        // one `@use … as *` module can't resolve which global it shadows.
        if (v.is_default
            && self.scopes.length() == 1
            && self.lookup(v.name) == null
            && !root.eval.is_private_member(v.name)
            && self
                .star_user_modules
                .filter((m) -> { m.var(v.name) != null })
                .length()
                > 1) {
            throw root.error.Error.unpositioned(
                "This variable is available from multiple global modules.",
            );
        }
        // A top-level `!default` variable in a module being evaluated with
        // configuration: the supplied value overrides the default (unless the
        // override itself is `!default` and the variable already has a value).
        // Configuration is keyed by the canonical (dashed) variable name.
        if (v.is_default && self.scopes.length() == 1) {
            let key = root.eval.normalize_var_name(v.name);
            let cfg = self.pending_config.get(key);
            if (cfg != null) {
                let cfg_val = cfg._0;
                let cfg_is_default = cfg._1;
                self.consumed_config.push(key);
                let already_set = match (self.lookup(v.name)) {
                    null => false,
                    root.value.Value_Null {} => false,
                    _ => true,
                };
                // A `null` configuration value leaves the `!default` in place;
                // a `@forward ... with ($x !default)` only applies if the module
                // hasn't already defined the variable.
                if (!(cfg_val is root.value.Value_Null || cfg_is_default && already_set)) {
                    let g = self.scopes.at(0);
                    if (g != null) {
                        let _ = g.set(v.name, cfg_val);
                    }
                    // dart blames `override.assignmentNode` here — the span of
                    // the value inside the `@use … with (...)` clause, which
                    // lives in the CONFIGURING file (evaluate.dart:2679). sasso
                    // does not yet carry configuration spans across that
                    // boundary, so record "unknown" rather than the `!default`
                    // text we are overriding: an unknown span emits no mapping
                    // segment, whereas a wrong one would emit a wrong segment.
                    let gs = self.var_spans.at(0);
                    if (gs != null) {
                        let _ = gs.set(v.name, root.eval.VarSpan.default());
                    }
                    return;
                }
            }
        }
        // A `!default` assignment whose target already holds a non-null value
        // is a no-op — and crucially, the right-hand side must NOT be evaluated
        // (dart-sass short-circuits a guarded declaration before evaluating its
        // expression). Evaluating it would surface errors from an expression
        // that is never actually used, e.g. Bootstrap's
        // `$x: 1rem + .5em !default` after `$x` was already set to a `rem`.
        if (v.is_default) {
            let existing = self.lookup(v.name);
            if (existing != null) {
                if (!(existing is root.value.Value_Null)) {
                    return;
                }
            }
            // Same guard for a name owned by exactly one `@use … as *` module.
            if ((self.scopes.length() == 1 || v.is_global) && !root.eval.is_private_member(v.name)) {
                let g = self.scopes.at(0);
                if (g != null) {
                    if (!g.has(v.name)) {
                        // PORT: the lazy `filter_map` iterator is collected
                        // eagerly; `targets.next()` twice → the first two slots.
                        let targets = self.star_user_modules.filter_map((m) -> { m.var(v.name) });
                        let first = targets.at(0);
                        if (first != null) {
                            if (targets.length() == 1 && !(first is root.value.Value_Null)) {
                                return;
                            }
                        }
                    }
                }
            }
        }
        let val = self.eval_expr(v.value);
        // dart `visitVariableDeclaration` stores `_expressionNode(node
        // .expression)` as the binding's node (evaluate.dart:2721): a bare
        // `$a: $b` inherits `$b`'s ORIGIN, so a chain `$a: red; $b: $a; c: $b`
        // maps `c`'s value all the way back to `red`. Computed AFTER the RHS is
        // evaluated so `$x: $x` still sees the outgoing binding, matching dart's
        // evaluation order.
        let span = self.expression_node(v.value, v.value_pos);
        // A top-level (or nested `!global`) assignment to a name not in the
        // global scope but exposed by exactly one `@use … as *` module updates
        // that module's variable (so the module's own functions/mixins observe
        // the change).
        if ((self.scopes.length() == 1 || v.is_global) && !root.eval.is_private_member(v.name)) {
            let g = self.scopes.at(0);
            if (g != null) {
                if (!g.has(v.name)) {
                    let targets = self
                        .star_user_modules
                        .filter((m) -> { m.var(v.name) != null });
                    if (targets.length() == 1) {
                        let _ = targets[0].vars.set(v.name, val);
                        if (self.options.source_map) {
                            let _ = targets[0].var_spans.set(v.name, span);
                        }
                        return;
                    }
                }
            }
        }
        if (v.is_global) {
            let g = self.scopes.at(0);
            if (g != null) {
                let _ = g.set(v.name, val);
            }
            let gs = self.var_spans.at(0);
            if (gs != null) {
                let _ = gs.set(v.name, span);
            }
        } else {
            self.assign(v.name, val, span);
        }
    }

    /// Assign to a `@use`d module's variable (`ns.$name: value`). The variable
    /// must already exist in the module and be public; `!default` only assigns
    /// when the existing value is null; built-in modules are immutable.
    function assign_module_var(self, ns: string, v: root.ast.VarDecl) -> void {
        if (root.eval.is_private_member(v.name)) {
            throw root.error.Error.unpositioned(
                "Private members can't be accessed from outside their modules.",
            );
        }
        let module = match (self.used_user_modules.get(ns)) {
            let m: root.eval.Module => m,
            _ => {
                if (self.used_modules.has(ns)) {
                    throw root.error.Error.unpositioned("Cannot modify built-in variable.");
                }
                throw root.error.Error.unpositioned(
                    `There is no module with the namespace "${ns}".`,
                );
            }
        };
        // A forwarded variable writes through to its defining module (under
        // its ORIGINAL name), so the module's own functions see the new value.
        let origin = module.var_write_origin(v.name) ?? root.std.Tuple2<root.eval.Module, string> { _0: module, _1: v.name };
        let target = origin._0;
        let name = origin._1;
        // One lookup feeds both the existence check and the `!default` guard
        // (`Module::var` clones the value, so don't call it twice).
        let existing = target.var(name);
        if (existing == null) {
            throw root.error.Error.unpositioned("Undefined variable.");
        }
        // Short-circuit a `!default` no-op before evaluating the RHS, so an
        // unused guarded expression can't raise an error (matches dart-sass).
        if (v.is_default && !(existing is root.value.Value_Null)) {
            return;
        }
        let val = self.eval_expr(v.value).without_slash();
        let span = self.expression_node(v.value, v.value_pos);
        let _ = target.vars.set(name, val);
        if (self.options.source_map) {
            let _ = target.var_spans.set(name, span);
        }
    }

    // ---- loop helpers ------------------------------------------------
    /// Set a variable in the innermost scope. A loop pushes its own scope, so a
    /// loop variable bound here lives in the loop's scope and is re-bound each
    /// iteration (dart-sass `setLocalVariable`).
    function set_local(self, name: string, val: root.value.Value, span: root.eval.VarSpan) -> void {
        let sc = root.std.last(self.scopes);
        if (sc != null) {
            rebind(sc, name, val);
        }
        let frame = root.std.last(self.var_spans);
        if (frame != null) {
            rebind(frame, name, span);
        }
    }

}

/// Bind `name` in an already-open scope, keeping the key that is already there.
///
/// A loop pushes ONE scope for all of its iterations and rebinds its variable
/// inside it, so from the second iteration on the entry exists and only its
/// value is new — `insert` would spell the name into a fresh `String` and throw
/// away the one the map is already holding.
function rebind<T>(vars: map<string, T>, name: string, val: T) -> void {
    // PORT: BAML maps have no `get_mut`; both arms store through `set`.
    if (vars.has(name)) {
        let _ = vars.set(name, val);
    } else {
        let _ = vars.set(name, val);
    }
}
