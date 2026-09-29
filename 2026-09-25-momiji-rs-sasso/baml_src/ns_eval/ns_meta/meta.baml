// Ported from sasso `src/eval/meta.rs` (namespace `root.eval.meta`).

/// Resolve `member` against the built-in modules a user module re-exports with
/// `@forward "sass:…"`, returning the owning module and the member's bare name.
///
/// Both the member and the forward's prefix are read in their canonical
/// spelling first: `_` and `-` are one character in a Sass identifier, so
/// `@forward "sass:map" as p-*` answers to `p_get` and `as p_*` answers to
/// `p-get`. (The `show`/`hide` sets are canonicalized when the forward is
/// recorded, so `visible` is asked with the canonical bare name.)
function resolve_forwarded_builtin(
    module: root.eval.Module,
    member: string,
) -> root.std.Tuple2<string, string>? {
    resolve_forwarded(module, member, root.eval.ForwardKind.Name, (m: string, b: string) -> bool {
        root.builtins.module_has_member(m, b)
    })
}

/// The same, for a `$variable` a `@forward "sass:…"` re-exports (`$pi` from
/// `sass:math`).
function resolve_forwarded_builtin_var(
    module: root.eval.Module,
    member: string,
) -> root.std.Tuple2<string, string>? {
    resolve_forwarded(module, member, root.eval.ForwardKind.Var, (m: string, b: string) -> bool {
        // PORT: `.is_ok()` → catch the `Error` as `false`.
        {
            let _v = root.builtins.module_var(m, b, root.scanner.Pos.NONE());
            true
        } catch (e) {
            let _e: root.error.Error => false
        }
    })
}

/// The same, for a built-in mixin (`load-css`/`apply` from `sass:meta`).
function resolve_forwarded_builtin_mixin(
    module: root.eval.Module,
    member: string,
) -> root.std.Tuple2<string, string>? {
    resolve_forwarded(module, member, root.eval.ForwardKind.Name, (m: string, b: string) -> bool {
        root.eval.is_builtin_mixin(m, b)
    })
}

function resolve_forwarded(
    module: root.eval.Module,
    member: string,
    kind: root.eval.ForwardKind,
    owns: (string, string) -> bool throws unknown,
) -> root.std.Tuple2<string, string>? {
    let member = member.replace_all("_", "-");
    for (let fb in module.forwarded_builtins) {
        let bare = root.std.strip_prefix(member, fb.prefix());
        if (bare == null) {
            continue;
        }
        if (fb.visible(bare, kind) && owns(fb.module, bare)) {
            return root.std.Tuple2 { _0: fb.module, _1: bare };
        }
    }
    null
}

/// `Result<Value, Error>` held as a value (what [`EvaluatorMeta::try_meta_eval_call`]
/// returns), turned back into `?`-propagation: the value, or the error thrown.
// PORT: helper for the Rust `return r;` / `r?` on a stored `Result`.
function unwrap_result(
    r: root.std.Ok<root.value.Value> | root.std.Err<root.error.Error>,
) -> root.value.Value {
    match (r) {
        let ok: root.std.Ok<root.value.Value> => ok.value,
        let err: root.std.Err<root.error.Error> => {
            throw err.error;
        },
    }
}

interface EvaluatorMeta {
    /// Dispatch a namespaced call `ns.member(args)`. Resolves a user module
    /// first, then a built-in module bound to `ns`.
    function eval_module_call(
        self,
        ns: string,
        member: string,
        args: root.ast.CallArg[],
        pos: root.scanner.Pos,
        length: int,
    ) -> root.value.Value throws unknown;

    /// Handle a `sass:meta` member that depends on the evaluator's state
    /// (variable/function/mixin/content existence). Returns `None` for any
    /// member this layer does not own, so the caller falls back to the
    /// value-only `call_module`. The arguments are already evaluated.
    function try_meta_eval_call(
        self,
        member: string,
        pos_args: root.value.Value[],
        named: root.std.Tuple2<string, root.value.Value>[],
        pos: root.scanner.Pos,
        length: int,
    ) -> (root.std.Ok<root.value.Value> | root.std.Err<root.error.Error>)? throws unknown;

    /// `meta.accepts-content($mixin)`: whether the mixin reference's body uses a
    /// `@content` block. The only built-in mixin that does is `meta.apply`.
    function meta_accepts_content(
        self,
        pos_args: root.value.Value[],
        named: root.std.Tuple2<string, root.value.Value>[],
        pos: root.scanner.Pos,
    ) -> root.value.Value throws unknown;

    /// `meta.get-function($name, $css: false, $module: null)`: capture a
    /// reference to the named function. A `$module` argument needs the user
    /// module loader (unsupported here) and is reported as an error. A user
    /// `@function` is captured by identity; otherwise a built-in (or, with
    /// `$css: true`, a plain-CSS) reference is returned.
    function meta_get_function(
        self,
        pos_args: root.value.Value[],
        named: root.std.Tuple2<string, root.value.Value>[],
        pos: root.scanner.Pos,
    ) -> root.value.Value throws unknown;

    /// The function a bare NAME resolves to: a user `@function` first, then a
    /// member a `@use … as *` exposes (from a user module or a built-in one),
    /// then the global. `None` when nothing owns it — `get-function` reports
    /// that as an error, while `call("name")` lets the plain-CSS dispatcher
    /// have it.
    function resolve_function_name(
        self,
        name: string,
        pos: root.scanner.Pos,
    ) -> root.value.SassFunction? throws unknown;

    /// `meta.get-mixin($name, $module: null)`: capture a reference to the named
    /// mixin. A user `@mixin` is captured by identity (so a later redefinition
    /// yields a distinct reference); the built-in `sass:meta` mixins
    /// (`load-css`, `apply`) are captured by name. A `$module` argument resolves
    /// the mixin from that `@use`d module's namespace.
    function meta_get_mixin(
        self,
        pos_args: root.value.Value[],
        named: root.std.Tuple2<string, root.value.Value>[],
        pos: root.scanner.Pos,
    ) -> root.value.Value throws unknown;

    /// Resolve a `$module`-qualified mixin reference for `meta.get-mixin`. The
    /// namespace must name a currently-`@use`d module; a built-in module's
    /// mixins (`meta.load-css`, `meta.apply`) resolve by name.
    /// `meta.get-function($name, $module: ns)`: capture a function reference from
    /// the module bound to `ns` — a user `@function` by identity, or a built-in
    /// member by name.
    function get_function_from_module(
        self,
        name: string,
        module_name: string,
        pos: root.scanner.Pos,
    ) -> root.value.Value throws unknown;

    function get_mixin_from_module(
        self,
        name: string,
        module_name: string,
        pos: root.scanner.Pos,
    ) -> root.value.Value throws unknown;

    /// `meta.call($function, $args...)`: invoke a function reference (or, when
    /// `$function` is a string, the named function). The trailing arguments were
    /// already splat-expanded by `eval_call_args`. `pos`/`length` span the
    /// `meta.call(...)` expression, the call site in dart's trace.
    function meta_call(
        self,
        pos_args: root.value.Value[],
        named: root.std.Tuple2<string, root.value.Value>[],
        pos: root.scanner.Pos,
        length: int,
    ) -> root.value.Value throws unknown;

    /// Invoke a resolved function reference with already-evaluated arguments.
    /// `pos`/`length` span the invoking expression (`meta.call(...)`), which
    /// is the call site in dart's trace and the caret of an `@error` raised in
    /// the body; a caller with no span passes a zero position.
    function invoke_function_ref(
        self,
        f: root.value.SassFunction,
        pos_args: root.value.Value[],
        named: root.std.Tuple2<string, root.value.Value>[],
        pos: root.scanner.Pos,
        length: int,
    ) -> root.value.Value throws unknown;

    /// Read the single string `$name` argument of an existence predicate,
    /// enforcing arity (1 positional, or `$name`) and the string type.
    /// Parse the `$name` (and optional `$module` namespace, when `allow_module`)
    /// arguments of an existence predicate. A `null` `$module` is treated as
    /// absent. Returns `(name, module)`.
    function exists_name_module_args(
        self,
        pos_args: root.value.Value[],
        named: root.std.Tuple2<string, root.value.Value>[],
        pos: root.scanner.Pos,
        allow_module: bool,
    ) -> root.std.Tuple2<string, string?> throws unknown;

    /// Whether the module bound to namespace `ns` defines a member `name` of the
    /// given kind (function/mixin/variable). An unknown namespace is an error.
    function module_member_exists(
        self,
        ns: string,
        name: string,
        kind: root.eval.MemberKind,
        pos: root.scanner.Pos,
    ) -> bool throws unknown;

    /// `meta.module-variables/-functions/-mixins($module)`: a map from each
    /// (non-private) member name of the `@use`d module bound to `$module` to its
    /// value (variables) or a first-class reference (functions/mixins). Members
    /// are ordered by name (dart-sass uses source order; every spec module
    /// defines them alphabetically, so this matches byte-for-byte).
    function meta_module_members(
        self,
        pos_args: root.value.Value[],
        named: root.std.Tuple2<string, root.value.Value>[],
        pos: root.scanner.Pos,
        kind: root.eval.MemberKind,
    ) -> root.value.Value throws unknown;

    /// `meta.variable-exists($name)` / `meta.global-variable-exists($name)`:
    /// whether a variable of that name is in scope (globally only when
    /// `global`). Names are matched dash/underscore-insensitively.
    function meta_variable_exists(
        self,
        pos_args: root.value.Value[],
        named: root.std.Tuple2<string, root.value.Value>[],
        pos: root.scanner.Pos,
        global: bool,
    ) -> root.value.Value throws unknown;

    /// `meta.mixin-exists($name)`: whether a mixin of that name is defined.
    function meta_mixin_exists(
        self,
        pos_args: root.value.Value[],
        named: root.std.Tuple2<string, root.value.Value>[],
        pos: root.scanner.Pos,
    ) -> root.value.Value throws unknown;

    /// `meta.function-exists($name)`: whether a user `@function` or a built-in
    /// of that name exists.
    function meta_function_exists(
        self,
        pos_args: root.value.Value[],
        named: root.std.Tuple2<string, root.value.Value>[],
        pos: root.scanner.Pos,
    ) -> root.value.Value throws unknown;

    /// Every built-in member a `name` written unprefixed reaches through a
    /// `@use … as *` — a built-in module starred directly, or a user module
    /// starred that re-exports one with `@forward "sass:…"` (under whatever
    /// name that forward gives it).
    ///
    /// Deduplicated by IDENTITY, because that is what dart's ambiguity rule is
    /// about: `@use "fwd" as *` next to `@use "sass:map" as *`, where `fwd`
    /// forwards `sass:map`, exposes ONE `map.get` and resolves fine, while
    /// `sass:list`'s `index` next to `sass:string`'s is two members and an
    /// error.
    function star_builtin_hits(
        self,
        name: string,
        kind: root.eval.MemberKind,
    ) -> root.std.Tuple2<string, string>[] throws unknown;

    /// Count how many `@use … as *` modules expose `name` as the given member
    /// kind; more than one means an unqualified reference is ambiguous.
    function star_member_count(
        self,
        name: string,
        kind: root.eval.MemberKind,
    ) -> int throws unknown;

    /// `meta.content-exists()`: whether the enclosing mixin was passed a
    /// `@content` block. It is an error to call this outside a mixin body.
    function meta_content_exists(
        self,
        pos_args: root.value.Value[],
        pos: root.scanner.Pos,
    ) -> root.value.Value throws unknown;

    /// Try `member` against a built-in module re-exported by `module` via
    /// `@forward "sass:x"` (honouring an `as p-*` prefix).
    function try_forwarded_builtin_call(
        self,
        module: root.eval.Module,
        member: string,
        args: root.ast.CallArg[],
        pos: root.scanner.Pos,
        length: int,
    ) -> root.value.Value? throws unknown;

    /// Call a user module's function in the module's own environment: bind the
    /// arguments in the caller's context, then swap in the module's globals/
    /// functions/mixins/used-modules so the body resolves against the module.
    function call_user_module_function(
        self,
        module: root.eval.Module,
        func: root.eval.UserCallable,
        args: root.ast.CallArg[],
        call: root.std.Tuple2<root.scanner.Pos, int>?,
    ) -> root.value.Value throws unknown;
}

implements EvaluatorMeta for root.eval.Evaluator {
    /// Dispatch a namespaced call `ns.member(args)`. Resolves a user module
    /// first, then a built-in module bound to `ns`.
    function eval_module_call(self, ns: string, member: string, args: root.ast.CallArg[], pos: root.scanner.Pos, length: int) -> root.value.Value {
        // A user module bound to this namespace.
        let user_module = self.used_user_modules.get(ns);
        if (user_module != null) {
            let module = user_module;
            if (root.eval.is_private_member(member)) {
                // Not part of the module's public view: dart reports it missing
                // (a literal `ns.-name` is the parser's privacy error instead).
                throw root.error.Error.at("Undefined function.", pos).with_length(length);
            }
            let func = module.function_(member);
            if (func != null) {
                // A forwarded function executes in its DEFINING module's
                // environment (its body closes over that module's globals).
                let exec = module.fn_origin(member) ?? module;
                return self.call_user_module_function(exec, func, args, root.std.Tuple2 { _0: pos, _1: length });
            }
            // Fall back to a built-in re-exported by this module via @forward.
            // Its errors report against the call, like a direct built-in's.
            // PORT: `match … { Ok(Some(v)) / Ok(None) / Err(e) }` → catch + null check.
            let fwd = self.try_forwarded_builtin_call(module, member, args, pos, length) catch (e) {
                let err: root.error.Error => {
                    throw err.with_length_at(pos, length);
                }
            };
            if (fwd != null) {
                return fwd;
            }
            throw root.error.Error.at("Undefined function.", pos).with_length(length);
        }
        // A built-in module bound to this namespace.
        let bound = self.used_modules.get(ns);
        if (bound == null) {
            throw root.error.Error.at(`There is no module with the namespace "${ns}".`, pos)
                .with_length(length);
        }
        let module = bound;
        // `call_module` canonicalizes the member (`_` and `-` are one
        // character in a Sass identifier); so must every lookup here, or
        // `meta.feature_exists(…)` reaches the dispatcher unannounced and
        // `meta.get_function(…)` never reaches the evaluator at all.
        let canonical = if (member.includes("_")) {
            member.replace_all("_", "-")
        } else {
            member
        };
        let member = canonical;
        let evaled = self.eval_call_args(args);
        let pos_args = evaled._0;
        let named = evaled._1;
        // Reported AFTER the arguments, so a deprecated call inside one warns
        // first, as dart's does — and against the module's REAL name, which is
        // not the namespace it was bound to (`@use "sass:meta" as m`).
        self.emit_call_deprecations(member, module, pos, length);
        // PORT: the in-place `mem::replace(v, Null).without_slash()` loops build
        // fresh vectors (the evaluated vectors may share their elements).
        pos_args = pos_args.map((v) -> { v.without_slash() });
        named = named.map((p) -> {
            root.std.Tuple2 { _0: p._0, _1: p._1.without_slash() }
        });
        // The `sass:meta` introspection predicates need the evaluator's scopes /
        // definitions, which the value-only `call_module` cannot see.
        if (module == "meta") {
            let r = self.try_meta_eval_call(member, pos_args, named, pos, length);
            if (r != null) {
                return unwrap_result(r);
            }
        }
        // Call results are slash-free (dart `withoutSlash()` on every call).
        let v = root.builtins.call_module(module, member, pos_args, named, pos) catch (e) {
            let err: root.error.Error => {
                throw err.with_length_at(pos, length);
            }
        };
        self.emit_color_function_deprecation(member, module, pos, length, pos_args, named);
        v.without_slash()
    }

    /// Handle a `sass:meta` member that depends on the evaluator's state
    /// (variable/function/mixin/content existence). Returns `None` for any
    /// member this layer does not own, so the caller falls back to the
    /// value-only `call_module`. The arguments are already evaluated.
    function try_meta_eval_call(self, member: string, pos_args: root.value.Value[], named: root.std.Tuple2<string, root.value.Value>[], pos: root.scanner.Pos, length: int) -> (root.std.Ok<root.value.Value> | root.std.Err<root.error.Error>)? {
        // Whatever these report, dart carets the CALL that reported it.
        // PORT: `sized` maps the error only; each arm's `Result` is captured as a
        // value below (`Ok`/`Err`), and a member this layer does not own
        // returns `None` straight away.
        let sized = (e: root.error.Error) -> root.error.Error { e.with_length_at(pos, length) };
        let out: root.value.Value = {
            match (member) {
                "variable-exists" => self.meta_variable_exists(pos_args, named, pos, false),
                "global-variable-exists" => self.meta_variable_exists(pos_args, named, pos, true),
                "mixin-exists" => self.meta_mixin_exists(pos_args, named, pos),
                "function-exists" => self.meta_function_exists(pos_args, named, pos),
                "content-exists" => self.meta_content_exists(pos_args, pos),
                "get-function" => self.meta_get_function(pos_args, named, pos),
                "get-mixin" => self.meta_get_mixin(pos_args, named, pos),
                "call" => self.meta_call(pos_args, named, pos, length),
                "module-variables" => self.meta_module_members(pos_args, named, pos, root.eval.MemberKind.Variable),
                "module-functions" => self.meta_module_members(pos_args, named, pos, root.eval.MemberKind.Function),
                "module-mixins" => self.meta_module_members(pos_args, named, pos, root.eval.MemberKind.Mixin),
                "accepts-content" => self.meta_accepts_content(pos_args, named, pos),
                "keywords" => Evaluator_meta_keywords(pos_args, named, pos),
                _ => {
                    return null;
                }
            }
        } catch (e) {
            let err: root.error.Error => {
                return root.std.Err { error: sized(err) };
            }
        };
        root.std.Ok { value: out }
    }

    /// `meta.accepts-content($mixin)`: whether the mixin reference's body uses a
    /// `@content` block. The only built-in mixin that does is `meta.apply`.
    function meta_accepts_content(self, pos_args: root.value.Value[], named: root.std.Tuple2<string, root.value.Value>[], pos: root.scanner.Pos) -> root.value.Value {
        let v = pos_args.at(0) ?? named.find((p) -> { p._0 == "mixin" })?._1;
        if (v == null) {
            throw root.error.Error.at("Missing argument $mixin.", pos);
        }
        let mixin = match (v) {
            root.value.Value_Mixin { _0: let m } => m,
            let other => {
                throw root.error.Error.at(
                    `$mixin: ${other.to_css(false)} is not a mixin reference.`,
                    pos
                );
            }
        };
        let accepts = if (mixin.user != null) {
            // PORT: `Rc::downcast::<UserCallable>()` → a type match on the
            // type-erased payload.
            match (mixin.user) {
                let c: root.eval.UserCallable => root.eval.body_uses_content(c.def.body),
                _ => false,
            }
        } else {
            mixin.name == "apply"
        };
        root.value.Value_Bool { _0: accepts }
    }

    /// `meta.get-function($name, $css: false, $module: null)`: capture a
    /// reference to the named function. A `$module` argument needs the user
    /// module loader (unsupported here) and is reported as an error. A user
    /// `@function` is captured by identity; otherwise a built-in (or, with
    /// `$css: true`, a plain-CSS) reference is returned.
    function meta_get_function(self, pos_args: root.value.Value[], named: root.std.Tuple2<string, root.value.Value>[], pos: root.scanner.Pos) -> root.value.Value {
        let params = ["name", "css", "module"];
        root.builtins.check_arity(params.length(), pos_args, named, pos);
        let arg = (i: int) -> root.value.Value? {
            pos_args.at(i) ?? named.find((p) -> { p._0 == params[i] })?._1
        };
        let name = match (arg(0)) {
            root.value.Value_Str { _0: let s } => s.text,
            let other: root.value.Value => {
                throw root.error.Error.at(
                    `$name: ${other.to_css(false)} is not a string.`,
                    pos
                );
            }
            null => {
                throw root.error.Error.at("Missing argument $name.", pos);
            }
        };
        // PORT: `matches!(arg(1), Some(v) if v.is_truthy())` → an `if` on a local.
        let css_arg = arg(1);
        let css = if (css_arg != null) { css_arg.is_truthy() } else { false };
        // A `$module` namespace resolves the function from that `@use`d module.
        let module_v = arg(2);
        if (module_v != null) {
            match (module_v) {
                root.value.Value_Null {} => {}
                root.value.Value_Str { _0: let s } => {
                    return self.get_function_from_module(name, s.text, pos);
                }
                let other => {
                    throw root.error.Error.at(
                        `$module: ${other.to_css(false)} is not a string.`,
                        pos
                    );
                }
            }
        }
        if (css) {
            return root.value.Value_Function {
                _0: root.value.SassFunction {
                    name: name,
                    css: true,
                    module: null,
                    user: null,
                },
            };
        }
        let resolved = self.resolve_function_name(name, pos);
        if (resolved != null) {
            root.value.Value_Function { _0: resolved }
        } else {
            throw root.error.Error.at(
                `Function not found: ${root.value.serialize_quoted(name)}`,
                pos
            );
        }
    }

    /// The function a bare NAME resolves to: a user `@function` first, then a
    /// member a `@use … as *` exposes (from a user module or a built-in one),
    /// then the global. `None` when nothing owns it — `get-function` reports
    /// that as an error, while `call("name")` lets the plain-CSS dispatcher
    /// have it.
    function resolve_function_name(self, name: string, pos: root.scanner.Pos) -> root.value.SassFunction? {
        // A user `@function` of that name (dash/underscore-insensitive) wins.
        let key = root.eval.normalize_arg_name(name);
        let f = self.lookup_function_norm(key);
        if (f != null) {
            return root.value.SassFunction {
                name: name,
                css: false,
                module: null,
                user: f,
            };
        }
        // A function exposed unprefixed via `@use … as *` (or forwarded into one).
        if (!root.eval.is_private_member(name)) {
            // A built-in module's member exposed unprefixed the same way is
            // still that module's: dart keeps `get-function("get")` bound to
            // `map.get` after `@use "sass:map" as *`, not to the global alias.
            // Both kinds compete for the bare name, so one check covers them.
            let star_user: root.eval.UserCallable[] = self
                .star_user_modules
                .filter_map((m) -> { m.function_(name) });
            let star_builtin = self.star_builtin_hits(name, root.eval.MemberKind.Function);
            if (star_user.length() + star_builtin.length() > 1) {
                throw root.error.Error.at(
                    "This function is available from multiple global modules.",
                    pos
                );
            }
            let first_user = star_user.at(0);
            if (first_user != null) {
                return root.value.SassFunction {
                    name: name,
                    css: false,
                    module: null,
                    user: first_user,
                };
            }
            let first_builtin = star_builtin.at(0);
            if (first_builtin != null) {
                let owner = first_builtin._0;
                let bare = first_builtin._1;
                let module = root.value.BuiltinModule_from_name(owner);
                if (module != null) {
                    return root.value.SassFunction {
                        name: bare,
                        css: false,
                        module: module,
                        user: null,
                    };
                }
            }
        }
        // The canonical spelling is what a reference is stored under, as dart
        // stores it: `inspect(get-function("map_get"))` is
        // `get-function("map-get")`.
        let canonical = name.replace_all("_", "-");
        if (root.builtins.is_builtin(canonical)
            || root.builtins.EVAL_GLOBAL_NAMES().includes(canonical)) {
            return root.value.SassFunction {
                name: canonical,
                css: false,
                module: null,
                user: null,
            };
        }
        null
    }

    /// `meta.get-mixin($name, $module: null)`: capture a reference to the named
    /// mixin. A user `@mixin` is captured by identity (so a later redefinition
    /// yields a distinct reference); the built-in `sass:meta` mixins
    /// (`load-css`, `apply`) are captured by name. A `$module` argument resolves
    /// the mixin from that `@use`d module's namespace.
    function meta_get_mixin(self, pos_args: root.value.Value[], named: root.std.Tuple2<string, root.value.Value>[], pos: root.scanner.Pos) -> root.value.Value {
        let params = ["name", "module"];
        root.builtins.check_arity(params.length(), pos_args, named, pos);
        let arg = (i: int) -> root.value.Value? {
            pos_args.at(i) ?? named.find((p) -> { p._0 == params[i] })?._1
        };
        let name = match (arg(0)) {
            root.value.Value_Str { _0: let s } => s.text,
            let other: root.value.Value => {
                throw root.error.Error.at(
                    `$name: ${other.to_css(false)} is not a string.`,
                    pos
                );
            }
            null => {
                throw root.error.Error.at("Missing argument $name.", pos);
            }
        };
        // A `$module` argument resolves the mixin from another module's scope.
        let module_val = arg(1);
        if (module_val != null) {
            if (!(module_val is root.value.Value_Null)) {
                let module_name = match (module_val) {
                    root.value.Value_Str { _0: let s } => s.text,
                    let other => {
                        throw root.error.Error.at(
                            `$module: ${other.to_css(false)} is not a string.`,
                            pos
                        );
                    }
                };
                return self.get_mixin_from_module(name, module_name, pos);
            }
        }
        // A user `@mixin` of that name (dash/underscore-insensitive) wins.
        let key = root.eval.normalize_arg_name(name);
        let m = self.lookup_mixin_norm(key);
        if (m != null) {
            return root.value.Value_Mixin {
                _0: root.value.SassMixin {
                    name: name,
                    user: m,
                    module: null,
                    // Same-module capture: remember the defining file so a later
                    // `meta.apply` from elsewhere resolves relative loads here.
                },
            };
        }
        // A mixin exposed unprefixed via `@use … as *`. Its body runs in the
        // owning module's environment, so capture that module too. A BUILT-IN
        // mixin exposed the same way (`load-css` from a starred `sass:meta`,
        // or from a starred module that forwards it) competes for the same bare
        // name, so one check covers both.
        let builtin_hits = self.star_builtin_hits(name, root.eval.MemberKind.Mixin);
        {
            let hits: root.eval.Module[] = if (root.eval.is_private_member(name)) {
                []
            } else {
                self.star_user_modules
                    .filter((sm) -> { sm.mixin(name) != null })
            };
            if (hits.length() + builtin_hits.length() > 1) {
                throw root.error.Error.at(
                    "This mixin is available from multiple global modules.",
                    pos
                );
            }
            let module = hits.at(0);
            if (module != null) {
                let hm = module.mixin(name);
                if (hm == null) {
                    throw root.error.Error.at(
                        `Mixin not found: ${root.value.serialize_quoted(name)}`,
                        pos
                    );
                }
                return root.value.Value_Mixin {
                    _0: root.value.SassMixin {
                        name: name,
                        user: hm,
                        module: module,
                    },
                };
            }
            let first_builtin = builtin_hits.at(0);
            if (first_builtin != null) {
                let bare = first_builtin._1;
                return root.value.Value_Mixin {
                    _0: root.value.SassMixin {
                        name: bare,
                        user: null,
                        module: null,
                    },
                };
            }
        }
        throw root.error.Error.at(
            `Mixin not found: ${root.value.serialize_quoted(name)}`,
            pos
        );
    }

    /// Resolve a `$module`-qualified mixin reference for `meta.get-mixin`. The
    /// namespace must name a currently-`@use`d module; a built-in module's
    /// mixins (`meta.load-css`, `meta.apply`) resolve by name.
    /// `meta.get-function($name, $module: ns)`: capture a function reference from
    /// the module bound to `ns` — a user `@function` by identity, or a built-in
    /// member by name.
    function get_function_from_module(self, name: string, module_name: string, pos: root.scanner.Pos) -> root.value.Value {
        let module = self.used_user_modules.get(module_name);
        if (module != null) {
            if (root.eval.is_private_member(name)) {
                // A private member is not in the module's public view, so the
                // by-name lookup simply does not find it.
                throw root.error.Error.at(
                    `Function not found: ${root.value.serialize_quoted(name)}`,
                    pos
                );
            }
            let f = module.function_(name);
            if (f != null) {
                return root.value.Value_Function {
                    _0: root.value.SassFunction {
                        name: name,
                        css: false,
                        module: null,
                        user: f,
                    },
                };
            }
            // A built-in this module re-exports with `@forward "sass:…"` is
            // reachable by reference exactly as it is by call, under the name
            // the forward gives it. The reference itself is the MEMBER's
            // (`@forward "sass:map" as p-*` answers to `p-get` and inspects as
            // `get-function("get")`).
            let fwd = resolve_forwarded_builtin(module, name);
            if (fwd != null) {
                let bare = fwd._1;
                let owner = root.value.BuiltinModule_from_name(fwd._0);
                if (owner != null) {
                    return root.value.Value_Function {
                        _0: root.value.SassFunction {
                            name: bare,
                            css: false,
                            module: owner,
                            user: null,
                        },
                    };
                }
            }
            throw root.error.Error.at(
                `Function not found: ${root.value.serialize_quoted(name)}`,
                pos
            );
        }
        let builtin = self.used_modules.get(module_name);
        if (builtin != null) {
            if (root.builtins.module_has_member(builtin, name)) {
                // The reference keeps the MEMBER's name and remembers the
                // module it came from, so invoking it dispatches through that
                // module (`color.scale` is not the global `scale-color`, and
                // dart neither prints nor compares them as the same function).
                let module = root.value.BuiltinModule_from_name(builtin);
                return root.value.Value_Function {
                    _0: root.value.SassFunction {
                        name: name.replace_all("_", "-"),
                        css: false,
                        module: module,
                        user: null,
                    },
                };
            }
            throw root.error.Error.at(
                `Function not found: ${root.value.serialize_quoted(name)}`,
                pos
            );
        }
        throw root.error.Error.at(
            `There is no module with the namespace "${module_name}".`,
            pos
        );
    }

    function get_mixin_from_module(self, name: string, module_name: string, pos: root.scanner.Pos) -> root.value.Value {
        let module = self.used_user_modules.get(module_name);
        if (module != null) {
            if (root.eval.is_private_member(name)) {
                throw root.error.Error.at(
                    `Mixin not found: ${root.value.serialize_quoted(name)}`,
                    pos
                );
            }
            let m = module.mixin(name);
            if (m != null) {
                return root.value.Value_Mixin {
                    _0: root.value.SassMixin {
                        name: name,
                        user: m,
                        module: module,
                    },
                };
            }
            // A built-in mixin this module re-exports is part of its public
            // API too (`@forward "sass:meta"` brings `load-css`/`apply`).
            let fwd = resolve_forwarded_builtin_mixin(module, name);
            if (fwd != null) {
                let bare = fwd._1;
                return root.value.Value_Mixin {
                    _0: root.value.SassMixin {
                        name: bare,
                        user: null,
                        module: null,
                    },
                };
            }
            throw root.error.Error.at(
                `Mixin not found: ${root.value.serialize_quoted(name)}`,
                pos
            );
        }
        let builtin = self.used_modules.get(module_name);
        if (builtin != null) {
            // The RESOLVED module, not the namespace it was bound to: `@use
            // "sass:meta" as m` makes `$module: "m"` the `meta` module.
            if (root.eval.is_builtin_mixin(builtin, name)) {
                return root.value.Value_Mixin {
                    _0: root.value.SassMixin {
                        // Canonical, as dart stores it: `get-mixin("load_css")`
                        // inspects as `get-mixin("load-css")` and compares equal
                        // to one taken under that spelling.
                        name: name.replace_all("_", "-"),
                        user: null,
                        module: null,
                    },
                };
            }
            throw root.error.Error.at(
                `Mixin not found: ${root.value.serialize_quoted(name)}`,
                pos
            );
        }
        throw root.error.Error.at(
            `There is no module with the namespace "${module_name}".`,
            pos
        );
    }

    /// `meta.call($function, $args...)`: invoke a function reference (or, when
    /// `$function` is a string, the named function). The trailing arguments were
    /// already splat-expanded by `eval_call_args`. `pos`/`length` span the
    /// `meta.call(...)` expression, the call site in dart's trace.
    function meta_call(self, pos_args: root.value.Value[], named: root.std.Tuple2<string, root.value.Value>[], pos: root.scanner.Pos, length: int) -> root.value.Value {
        // `$function` is the first positional argument, or the named `$function`.
        // PORT: the `(func_val, rest_pos)` tuple binding → a `Tuple2` local.
        let first = pos_args.at(0);
        let split: root.std.Tuple2<root.value.Value, root.value.Value[]> = if (first != null) {
            root.std.Tuple2 { _0: first, _1: pos_args.slice(1, pos_args.length()) }
        } else {
            let found = named.find((p) -> { p._0 == "function" });
            if (found != null) {
                root.std.Tuple2 { _0: found._1, _1: [] }
            } else {
                throw root.error.Error.at("Missing argument $function.", pos);
            }
        };
        let func_val = split._0;
        let rest_pos = split._1;
        // The remaining named args (excluding `$function`) are call keywords.
        let rest_named: root.std.Tuple2<string, root.value.Value>[] =
            named.filter((p) -> { p._0 != "function" });

        match (func_val) {
            // A first-class function reference.
            root.value.Value_Function { _0: let f } => self.invoke_function_ref(f, rest_pos, rest_named, pos, length),
            // The deprecated string form: look up by name.
            root.value.Value_Str { _0: let s } => {
                self.emit_deprecation(
                    root.deprecation.Deprecation.call_string(s.text),
                    pos,
                    length
                );
                // The NAME resolves exactly as it would have if it were
                // written: a user `@function`, a member a `@use … as *`
                // exposes, then the global. An unknown one is left alone for
                // the plain-CSS dispatcher.
                let f = self.resolve_function_name(s.text, pos) ?? root.value.SassFunction {
                    name: s.text,
                    css: false,
                    module: null,
                    user: null,
                };
                self.invoke_function_ref(f, rest_pos, rest_named, pos, length)
            }
            let other => {
                throw root.error.Error.at(
                    `$function: ${other.to_css(false)} is not a function reference.`,
                    pos
                );
            }
        }
    }

    /// Invoke a resolved function reference with already-evaluated arguments.
    /// `pos`/`length` span the invoking expression (`meta.call(...)`), which
    /// is the call site in dart's trace and the caret of an `@error` raised in
    /// the body; a caller with no span passes a zero position.
    function invoke_function_ref(self, f: root.value.SassFunction, pos_args: root.value.Value[], named: root.std.Tuple2<string, root.value.Value>[], pos: root.scanner.Pos, length: int) -> root.value.Value {
        // Reaching a built-in through a reference is still using it, and dart
        // reports that against the INVOCATION — as the GLOBAL it is only when
        // the reference was taken globally, which is why the module it came
        // from is remembered. (A reference with no position is an internal
        // invocation — the user-overridden `calc()` hook — which reports
        // nothing.)
        // A reference resolves to the same built-in, so it takes the same
        // plain-CSS path for a plain-CSS argument and deprecates as little:
        // `meta.call(meta.get-function("grayscale"), 1)` is the CSS filter and
        // dart says nothing. Fixing only the direct call left this one warning
        // (#122).
        let f_module = f.module;
        let css_filter_ref =
            f_module == null && root.builtins.color_ext.is_plain_css_filter_call(f.name, pos_args, named);
        if (f.user == null && !f.css && pos.line > 0 && !css_filter_ref) {
            let module_name: string? = if (f_module != null) { f_module.name() } else { null };
            self.emit_call_deprecations(f.name, module_name, pos, length);
        }
        // A captured user `@function`: bind the evaluated args and run its
        // body in the callable's lexical closure. The payload is a
        // type-erased `Rc<UserCallable>` (cloning the `Rc` releases the
        // borrow on `f` before running the body).
        // PORT: `Rc::downcast::<UserCallable>()` → `if let` on the payload type.
        if let callable: root.eval.UserCallable = f.user {
            // dart's trace: the `meta.call(...)` expression is a call
            // site (a frame at `pos`, attributed to the current member),
            // and frames inside the body name the function itself
            // (`f()`). An internal invocation with no position (the
            // user-overridden `calc()` hook) records no frame. The body
            // then runs against the function's defining file.
            let saved_member: string? = if (pos.line > 0) {
                self.enter_call(pos, length, `${callable.def.name}()`)
            } else {
                null
            };
            let saved_file = self.enter_origin_file(callable.origin);
            // PORT: `mem::replace(&mut self.x, callable.env_x.clone())` — the
            // captured chains are copied (the frames stay shared) so pushing
            // scopes never grows the closure's own vectors.
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
            // The body resolves `ns.member` against ITS definition site's
            // `@use` namespaces, not the caller's (as the direct-call and
            // mixin-reference paths already do).
            let saved_env_modules = self.install_env_modules(callable.env_modules);
            self.push_scope(false);
            // Like `invoke_mixin_ref`: the arguments arrive already
            // evaluated and reordered by `meta.call`, so no per-argument
            // span survives. Bind with none rather than guess.
            // PORT: the `Result` is held as a value (`Ok`/`Err`) so the
            // restoration below runs before it is propagated.
            let comma: root.value.ListSep = root.value.ListSep.Comma;
            let evaled: root.eval.EvaledArgs = root.std.Tuple3 {
                _0: pos_args,
                _1: named,
                _2: comma,
            };
            let result: root.std.Ok<root.value.Value?> | root.std.Err<root.error.Error> = {
                self.bind_evaled_into_scope(
                    callable.def.params,
                    evaled,
                    root.eval.ArgSpans.default(),
                    root.eval.control_flow.declared(callable)
                );
                self.in_mixin.push(false);
                let r = self.run_fn_body(callable.def.body) catch (e) {
                    let err: root.error.Error => {
                        let _ = self.in_mixin.pop();
                        throw err;
                    }
                };
                let _ = self.in_mixin.pop();
                root.std.Ok { value: r }
            } catch (e) {
                let err: root.error.Error => root.std.Err { error: self.finalize_error(err) }
            };
            self.pop_scope();
            self.scopes = saved_scopes;
            self.var_spans = saved_var_spans;
            self.scope_semi_global = saved_semi;
            self.functions = saved_fns;
            self.mixins = saved_mixins;
            self.restore_env_modules(saved_env_modules);
            self.leave_module_file(saved_file);
            if (saved_member != null) {
                self.leave_call(saved_member);
            }
            let returned = match (result) {
                let ok: root.std.Ok<root.value.Value?> => ok.value,
                let err: root.std.Err<root.error.Error> => {
                    throw err.error;
                }
            };
            return if (returned != null) {
                returned.without_slash()
            } else {
                throw root.error.Error.unpositioned(
                    `Function ${callable.def.name}() did not @return a value.`
                );
            };
        }
        // A plain-CSS reference is preserved verbatim as a CSS function call.
        if (f.css) {
            let parts: string[] = pos_args.map((v) -> { v.to_css(false) });
            for (let p in named) {
                let n = p._0;
                let v = p._1;
                parts.push("$" + n + ": " + v.to_css(false));
            }
            return root.value.Value_Str {
                _0: root.value.SassStr {
                    text: `${f.name}(${parts.join(", ")})`,
                    quoted: false,
                },
            };
        }
        // A built-in reference. The `sass:meta` introspection functions need
        // the evaluator's scopes/definitions; everything else dispatches
        // through the value-only builtin library — through the MODULE when the
        // reference was taken from one, since a member and its global alias are
        // not always the same function (`color.scale` vs `scale-color`).
        //
        // The name is looked up canonically (`call("variable_exists", …)` comes
        // straight from a string and has never been through `get-function`),
        // while `f.name` keeps the spelling a plain-CSS reference serializes.
        let canonical = if (f.name.includes("_")) {
            f.name.replace_all("_", "-")
        } else {
            f.name
        };
        let is_meta = if (f_module != null) { f_module == root.value.BuiltinModule.Meta } else { true };
        if (is_meta) {
            let r = self.try_meta_eval_call(canonical, pos_args, named, pos, length);
            if (r != null) {
                return unwrap_result(r);
            }
        }
        let owner: string? = if (f_module != null) { f_module.name() } else { null };
        let v = if (owner != null) {
            root.builtins.call_module(owner, canonical, pos_args, named, pos)
        } else {
            root.builtins.call(canonical, pos_args, named, pos)
        };
        // A reference reaches the same function, so it carries the same
        // deprecation — reported against the INVOCATION, as the others are.
        if (pos.line > 0) {
            self.emit_color_function_deprecation(canonical, owner, pos, length, pos_args, named);
        }
        v.without_slash()
    }

    /// Read the single string `$name` argument of an existence predicate,
    /// enforcing arity (1 positional, or `$name`) and the string type.
    /// Parse the `$name` (and optional `$module` namespace, when `allow_module`)
    /// arguments of an existence predicate. A `null` `$module` is treated as
    /// absent. Returns `(name, module)`.
    function exists_name_module_args(self, pos_args: root.value.Value[], named: root.std.Tuple2<string, root.value.Value>[], pos: root.scanner.Pos, allow_module: bool) -> root.std.Tuple2<string, string?> {
        let max = if (allow_module) { 2 } else { 1 };
        root.builtins.check_arity(max, pos_args, named, pos);
        let name_v = pos_args.at(0) ?? named.find((p) -> { p._0 == "name" })?._1;
        if (name_v == null) {
            throw root.error.Error.at("Missing argument $name.", pos);
        }
        let name = match (name_v) {
            root.value.Value_Str { _0: let s } => s.text,
            let other => {
                throw root.error.Error.at(
                    `$name: ${other.to_css(false)} is not a string.`,
                    pos
                );
            }
        };
        let module: string? = if (allow_module) {
            let m = pos_args.at(1) ?? named.find((p) -> { p._0 == "module" })?._1;
            match (m) {
                null => null,
                root.value.Value_Null {} => null,
                root.value.Value_Str { _0: let s } => s.text,
                let other: root.value.Value => {
                    throw root.error.Error.at(
                        `$module: ${other.to_css(false)} is not a string.`,
                        pos
                    );
                }
            }
        } else {
            null
        };
        root.std.Tuple2 { _0: name, _1: module }
    }

    /// Whether the module bound to namespace `ns` defines a member `name` of the
    /// given kind (function/mixin/variable). An unknown namespace is an error.
    function module_member_exists(self, ns: string, name: string, kind: root.eval.MemberKind, pos: root.scanner.Pos) -> bool {
        let user_module = self.used_user_modules.get(ns);
        if (user_module != null) {
            // PORT: a non-optional local, so the closure below can capture it.
            let m = user_module;
            // A built-in the module re-exports brings its own members along.
            let forwarded = () -> root.std.Tuple2<string, string>? { resolve_forwarded_builtin(m, name) };
            return match (kind) {
                root.eval.MemberKind.Function => m.function_(name) != null || forwarded() != null,
                root.eval.MemberKind.Mixin => {
                    m.mixin(name) != null || resolve_forwarded_builtin_mixin(m, name) != null
                }
                root.eval.MemberKind.Variable => {
                    m.var(name) != null || resolve_forwarded_builtin_var(m, name) != null
                }
            };
        }
        let builtin = self.used_modules.get(ns);
        if (builtin != null) {
            return match (kind) {
                root.eval.MemberKind.Function => root.builtins.module_has_member(builtin, name),
                root.eval.MemberKind.Mixin => root.eval.is_builtin_mixin(builtin, name),
                // PORT: `.is_ok()` → catch the `Error` as `false`.
                root.eval.MemberKind.Variable => {
                    {
                        let _v = root.builtins.module_var(builtin, name, pos);
                        true
                    } catch (e) {
                        let _e: root.error.Error => false
                    }
                }
            };
        }
        throw root.error.Error.at(
            `There is no module with the namespace "${ns}".`,
            pos
        );
    }

    /// `meta.module-variables/-functions/-mixins($module)`: a map from each
    /// (non-private) member name of the `@use`d module bound to `$module` to its
    /// value (variables) or a first-class reference (functions/mixins). Members
    /// are ordered by name (dart-sass uses source order; every spec module
    /// defines them alphabetically, so this matches byte-for-byte).
    function meta_module_members(self, pos_args: root.value.Value[], named: root.std.Tuple2<string, root.value.Value>[], pos: root.scanner.Pos, kind: root.eval.MemberKind) -> root.value.Value {
        if (pos_args.length() > 1) {
            throw root.error.Error.at(
                `Only 1 argument allowed, but ${pos_args.length()} were passed.`,
                pos
            );
        }
        let v = pos_args.at(0) ?? named.find((p) -> { p._0 == "module" })?._1;
        if (v == null) {
            throw root.error.Error.at("Missing argument $module.", pos);
        }
        let ns = match (v) {
            root.value.Value_Str { _0: let s } => s.text,
            let other => {
                throw root.error.Error.at(
                    `$module: ${other.to_css(false)} is not a string.`,
                    pos
                );
            }
        };
        let user_module = self.used_user_modules.get(ns);
        if (user_module == null) {
            // A built-in module: `sass:meta` is modeled member-by-member
            // (the suite probes it); other built-ins have no variables and
            // their callables are dispatched, not enumerated, so report the
            // names we know.
            let builtin = self.used_modules.get(ns);
            if (builtin != null) {
                // The enumerated references belong to the module, not to the
                // namespace they were reached through.
                let owner = root.value.BuiltinModule_from_name(builtin);
                // PORT: `match (*builtin, kind)` → an `if` chain.
                let names: string[] = if (builtin == "meta" && kind == root.eval.MemberKind.Function) {
                    root.builtins.META_FUNCTION_NAMES()
                } else if (builtin == "meta" && kind == root.eval.MemberKind.Mixin) {
                    root.builtins.META_MIXIN_NAMES()
                } else {
                    []
                };
                let entries: root.std.Tuple2<root.value.Value, root.value.Value>[] = names
                    .map((name) -> {
                        let key: root.value.Value = root.value.Value_Str {
                            _0: root.value.SassStr {
                                text: name,
                                quoted: true,
                            },
                        };
                        let val: root.value.Value = match (kind) {
                            root.eval.MemberKind.Function => root.value.Value_Function {
                                _0: root.value.SassFunction {
                                    name: name,
                                    css: false,
                                    module: owner,
                                    user: null,
                                },
                            },
                            root.eval.MemberKind.Mixin => root.value.Value_Mixin {
                                _0: root.value.SassMixin {
                                    name: name,
                                    user: null,
                                    module: null,
                                },
                            },
                            root.eval.MemberKind.Variable => root.value.Value_Null {},
                        };
                        root.std.Tuple2 { _0: key, _1: val }
                    });
                return root.value.Value_Map { _0: root.value.Map.new(entries) };
            }
            // dart drops the article in the `module-*` functions ONLY: every
            // other namespace error says "with the namespace".
            throw root.error.Error.at(
                `There is no module with namespace "${ns}".`,
                pos
            );
        }
        let module = user_module;
        let names: string[] = match (kind) {
            root.eval.MemberKind.Variable => module.vars.keys(),
            root.eval.MemberKind.Function => module.functions.keys(),
            root.eval.MemberKind.Mixin => module.mixins.keys(),
        };
        root.std.retain(names, (n) -> { !root.eval.is_private_member(n) });
        root.std.sort_strings(names);
        let entries: root.std.Tuple2<root.value.Value, root.value.Value>[] = names
            .map((name) -> {
                // Member names are canonicalized to the dashed form for the map
                // key (dart-sass: `$e_f` is keyed `"e-f"`); the value keeps the
                // variable's own value verbatim.
                let key: root.value.Value = root.value.Value_Str {
                    _0: root.value.SassStr {
                        text: name.replace_all("_", "-"),
                        quoted: true,
                    },
                };
                let val: root.value.Value = match (kind) {
                    root.eval.MemberKind.Variable => module.var(name) ?? root.value.Value_Null {},
                    root.eval.MemberKind.Function => root.value.Value_Function {
                        _0: root.value.SassFunction {
                            name: name,
                            css: false,
                            module: null,
                            user: module.function_(name),
                        },
                    },
                    root.eval.MemberKind.Mixin => root.value.Value_Mixin {
                        _0: root.value.SassMixin {
                            name: name,
                            user: module.mixin(name),
                            module: module,
                        },
                    },
                };
                root.std.Tuple2 { _0: key, _1: val }
            });
        root.value.Value_Map { _0: root.value.Map.new(entries) }
    }

    /// `meta.variable-exists($name)` / `meta.global-variable-exists($name)`:
    /// whether a variable of that name is in scope (globally only when
    /// `global`). Names are matched dash/underscore-insensitively.
    function meta_variable_exists(self, pos_args: root.value.Value[], named: root.std.Tuple2<string, root.value.Value>[], pos: root.scanner.Pos, global: bool) -> root.value.Value {
        // Only `global-variable-exists` takes the optional `$module` namespace.
        let args = self.exists_name_module_args(pos_args, named, pos, global);
        let name = args._0;
        let module = args._1;
        if (module != null) {
            return root.value.Value_Bool {
                _0: self.module_member_exists(
                    module,
                    name,
                    root.eval.MemberKind.Variable,
                    pos
                ),
            };
        }
        let key = root.eval.normalize_arg_name(name);
        let scopes: root.eval.Scope[] = if (global) { self.scopes.slice(0, 1) } else { self.scopes };
        let found = scopes
            .some((s) -> { s.keys().some((k) -> { root.eval.normalize_arg_name(k) == key }) });
        if (found) {
            return root.value.Value_Bool { _0: true };
        }
        // A variable exposed unprefixed via `@use … as *` (or forwarded into
        // one) — from a user module or a built-in one. Exposure of two
        // DIFFERENT variables under the name is ambiguous.
        let count = self.star_member_count(name, root.eval.MemberKind.Variable)
            + self.star_builtin_hits(name, root.eval.MemberKind.Variable).length();
        if (count > 1) {
            throw root.error.Error.at(
                "This variable is available from multiple global modules.",
                pos
            );
        }
        root.value.Value_Bool { _0: count >= 1 }
    }

    /// `meta.mixin-exists($name)`: whether a mixin of that name is defined.
    function meta_mixin_exists(self, pos_args: root.value.Value[], named: root.std.Tuple2<string, root.value.Value>[], pos: root.scanner.Pos) -> root.value.Value {
        let args = self.exists_name_module_args(pos_args, named, pos, true);
        let name = args._0;
        let module = args._1;
        if (module != null) {
            return root.value.Value_Bool {
                _0: self.module_member_exists(
                    module,
                    name,
                    root.eval.MemberKind.Mixin,
                    pos
                ),
            };
        }
        let key = root.eval.normalize_arg_name(name);
        let local = self.lookup_mixin_norm(key) != null;
        if (local) {
            return root.value.Value_Bool { _0: true };
        }
        let count = self.star_member_count(name, root.eval.MemberKind.Mixin)
            + self.star_builtin_hits(name, root.eval.MemberKind.Mixin).length();
        if (count > 1) {
            throw root.error.Error.at(
                "This mixin is available from multiple global modules.",
                pos
            );
        }
        root.value.Value_Bool { _0: count >= 1 }
    }

    /// `meta.function-exists($name)`: whether a user `@function` or a built-in
    /// of that name exists.
    function meta_function_exists(self, pos_args: root.value.Value[], named: root.std.Tuple2<string, root.value.Value>[], pos: root.scanner.Pos) -> root.value.Value {
        let args = self.exists_name_module_args(pos_args, named, pos, true);
        let name = args._0;
        let module = args._1;
        if (module != null) {
            return root.value.Value_Bool {
                _0: self.module_member_exists(
                    module,
                    name,
                    root.eval.MemberKind.Function,
                    pos
                ),
            };
        }
        let key = root.eval.normalize_arg_name(name);
        let user = self.lookup_function_norm(key) != null;
        if (user) {
            return root.value.Value_Bool { _0: true };
        }
        // A function exposed unprefixed via `@use … as *` (or forwarded into a
        // module that is itself `@use`d as `*`), and a BUILT-IN module's member
        // exposed the same way — `map.get` is no global, so only that lookup
        // finds it. They compete for one name, so one count covers both.
        let count = self.star_member_count(name, root.eval.MemberKind.Function)
            + self.star_builtin_hits(name, root.eval.MemberKind.Function).length();
        if (count > 1) {
            throw root.error.Error.at(
                "This function is available from multiple global modules.",
                pos
            );
        }
        if (count >= 1) {
            return root.value.Value_Bool { _0: true };
        }
        root.value.Value_Bool {
            _0: root.builtins.is_builtin(name)
                || root.builtins.EVAL_GLOBAL_NAMES().includes(name.replace_all("_", "-")),
        }
    }

    /// Every built-in member a `name` written unprefixed reaches through a
    /// `@use … as *` — a built-in module starred directly, or a user module
    /// starred that re-exports one with `@forward "sass:…"` (under whatever
    /// name that forward gives it).
    ///
    /// Deduplicated by IDENTITY, because that is what dart's ambiguity rule is
    /// about: `@use "fwd" as *` next to `@use "sass:map" as *`, where `fwd`
    /// forwards `sass:map`, exposes ONE `map.get` and resolves fine, while
    /// `sass:list`'s `index` next to `sass:string`'s is two members and an
    /// error.
    function star_builtin_hits(self, name: string, kind: root.eval.MemberKind) -> root.std.Tuple2<string, string>[] {
        // The common case is no `@use … as *` at all; every call, variable and
        // include asks this, so answer it before allocating anything.
        if (self.star_modules.length() == 0 && self.star_user_modules.length() == 0) {
            return [];
        }
        let name = name.replace_all("_", "-");
        let hits: root.std.Tuple2<string, string>[] = [];
        for (let m in self.star_modules) {
            let owns = match (kind) {
                root.eval.MemberKind.Function => root.builtins.module_has_member(m, name),
                // PORT: `.is_ok()` → catch the `Error` as `false`.
                root.eval.MemberKind.Variable => {
                    {
                        let _v = root.builtins.module_var(m, name, root.scanner.Pos.NONE());
                        true
                    } catch (e) {
                        let _e: root.error.Error => false
                    }
                }
                root.eval.MemberKind.Mixin => root.eval.is_builtin_mixin(m, name),
            };
            let hit = root.std.Tuple2 { _0: m, _1: name };
            // PORT: `Vec::contains` compares by value → `root.std.contains`.
            if (owns && !root.std.contains(hits, hit)) {
                hits.push(hit);
            }
        }
        for (let m in self.star_user_modules) {
            // A module's OWN member shadows the built-in it forwards under the
            // same name — `@forward "sass:string"` beside `@function index` is
            // that module's `index`, namespaced and starred alike — so the
            // forwarded one is not a second member competing for the name.
            let own = match (kind) {
                root.eval.MemberKind.Function => m.function_(name) != null,
                root.eval.MemberKind.Variable => m.var(name) != null,
                root.eval.MemberKind.Mixin => m.mixin(name) != null,
            };
            if (own) {
                continue;
            }
            let found = match (kind) {
                root.eval.MemberKind.Function => resolve_forwarded_builtin(m, name),
                root.eval.MemberKind.Variable => resolve_forwarded_builtin_var(m, name),
                root.eval.MemberKind.Mixin => resolve_forwarded_builtin_mixin(m, name),
            };
            if (found != null) {
                if (!root.std.contains(hits, found)) {
                    hits.push(found);
                }
            }
        }
        hits
    }

    /// Count how many `@use … as *` modules expose `name` as the given member
    /// kind; more than one means an unqualified reference is ambiguous.
    function star_member_count(self, name: string, kind: root.eval.MemberKind) -> int {
        if (root.eval.is_private_member(name)) {
            return 0;
        }
        self.star_user_modules
            .filter((m) -> {
                match (kind) {
                    root.eval.MemberKind.Variable => m.var(name) != null,
                    root.eval.MemberKind.Mixin => m.mixin(name) != null,
                    root.eval.MemberKind.Function => m.function_(name) != null,
                }
            })
            .length()
    }

    /// `meta.content-exists()`: whether the enclosing mixin was passed a
    /// `@content` block. It is an error to call this outside a mixin body.
    function meta_content_exists(self, pos_args: root.value.Value[], pos: root.scanner.Pos) -> root.value.Value {
        if (pos_args.length() != 0) {
            throw root.error.Error.at(
                `Only 0 arguments allowed, but ${pos_args.length()} were passed.`,
                pos
            );
        }
        if (root.std.last(self.in_mixin) != true) {
            throw root.error.Error.at(
                "content-exists() may only be called within a mixin.",
                pos
            );
        }
        // PORT: `matches!(last(), Some(Some(_)))` — an empty stack and a `None`
        // top both read as `null` here, and both are `false`.
        let has = root.std.last(self.content_stack) != null;
        root.value.Value_Bool { _0: has }
    }

    /// Try `member` against a built-in module re-exported by `module` via
    /// `@forward "sass:x"` (honouring an `as p-*` prefix).
    function try_forwarded_builtin_call(self, module: root.eval.Module, member: string, args: root.ast.CallArg[], pos: root.scanner.Pos, length: int) -> root.value.Value? {
        let fwd = resolve_forwarded_builtin(module, member);
        if (fwd == null) {
            return null;
        }
        let owner = fwd._0;
        let bare = fwd._1;
        // Reached through a `@forward "sass:…"`, the member is still that
        // module's — and still deprecated if it is (`m.feature-exists(…)`
        // after `@forward "sass:meta"`).
        let evaled = self.eval_call_args(args);
        let pos_args = evaled._0;
        let named = evaled._1;
        self.emit_call_deprecations(bare, owner, pos, length);
        // PORT: the in-place `mem::replace(v, Null).without_slash()` loops build
        // fresh vectors (the evaluated vectors may share their elements).
        pos_args = pos_args.map((v) -> { v.without_slash() });
        named = named.map((p) -> {
            root.std.Tuple2 { _0: p._0, _1: p._1.without_slash() }
        });
        // The `sass:meta` predicates resolve against the evaluator, which the
        // value-only dispatcher cannot do — a forwarded `meta.get-function` is
        // still `get-function`.
        if (owner == "meta") {
            let r = self.try_meta_eval_call(bare, pos_args, named, pos, length);
            if (r != null) {
                return unwrap_result(r);
            }
        }
        let v = root.builtins.call_module(owner, bare, pos_args, named, pos);
        self.emit_color_function_deprecation(bare, owner, pos, length, pos_args, named);
        v.without_slash()
    }

    /// Call a user module's function in the module's own environment: bind the
    /// arguments in the caller's context, then swap in the module's globals/
    /// functions/mixins/used-modules so the body resolves against the module.
    function call_user_module_function(self, module: root.eval.Module, func: root.eval.UserCallable, args: root.ast.CallArg[], call: root.std.Tuple2<root.scanner.Pos, int>?) -> root.value.Value {
        let spanned = self.eval_call_args_spanned(args);
        let evaled = spanned._0;
        let arg_spans = spanned._1;
        let saved_member: string? = if (call != null) {
            self.enter_call(call._0, call._1, `${func.def.name}()`)
        } else {
            null
        };
        let saved = self.enter_module(module);
        // The function's own defining file beats the module handed to us (a
        // multi-hop `@forward` can name another module).
        let saved_file = self.enter_origin_file(func.origin);
        // PORT: `mem::replace(&mut self.x, func.env_x.clone())` — the captured
        // chains are copied (the frames stay shared) so pushing scopes never
        // grows the closure's own vectors.
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
        // The captured tables beat the module's own: a multi-hop `@forward`
        // can hand us a module whose namespaces differ from the file that
        // DEFINED the function (uswds `units()` reaching `sass:meta`).
        let saved_env_modules = self.install_env_modules(func.env_modules);
        self.push_scope(false);
        // PORT: the `Result` is held as a value (`Ok`/`Err`) so the restoration
        // below runs before it is propagated.
        let result: root.std.Ok<root.value.Value?> | root.std.Err<root.error.Error> = {
            self.bind_evaled_into_scope(
                func.def.params,
                evaled,
                arg_spans,
                root.eval.control_flow.declared(func)
            );
            // A function body is not a mixin body: `meta.content-exists()`
            // called from a module function (even one a mixin with a
            // content block invokes) errors, as on the direct-call path.
            self.in_mixin.push(false);
            let r = self.run_fn_body(func.def.body) catch (e) {
                let err: root.error.Error => {
                    let _ = self.in_mixin.pop();
                    throw err;
                }
            };
            let _ = self.in_mixin.pop();
            root.std.Ok { value: r }
        } catch (e) {
            let err: root.error.Error => root.std.Err { error: self.finalize_error(err) }
        };
        self.pop_scope();
        self.scopes = saved_scopes;
        self.var_spans = saved_var_spans;
        self.scope_semi_global = saved_semi;
        self.functions = saved_fns;
        self.mixins = saved_mixins;
        self.restore_env_modules(saved_env_modules);
        self.leave_module_file(saved_file);
        self.leave_module(saved);
        if (saved_member != null) {
            self.leave_call(saved_member);
        }
        let returned = match (result) {
            let ok: root.std.Ok<root.value.Value?> => ok.value,
            let err: root.std.Err<root.error.Error> => {
                throw err.error;
            }
        };
        if (returned != null) {
            returned.without_slash()
        } else {
            throw root.error.Error.unpositioned(
                `Function ${func.def.name}() did not @return a value.`
            );
        }
    }

}

/// `meta.keywords($args)`: the keyword arguments captured by a `$args...`
/// rest parameter, as a map from each name (hyphen-normalized, unquoted) to
/// its value. The argument must be an argument list, not an ordinary value.
function Evaluator_meta_keywords(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let v = pos_args.at(0)
        ?? named
            .find((p) -> {
                p._0 == "args"
            })
            ?._1;
    if (v == null) {
        throw root.error.Error.at("Missing argument $args.", pos);
    }
    // PORT: the `Value::List(l) if l.keywords.is_some()` guard → an `if let`
    // on the keywords inside the arm.
    if let l: root.value.Value_List = v {
        let kw = l._0.keywords;
        if (kw != null) {
            return root.value.Value_Map { _0: root.value.Map.new(root.std.clone_vec(kw)) };
        }
    }
    throw root.error.Error.at(
        `$args: ${v.to_css(false)} is not an argument list.`,
        pos
    );
}
