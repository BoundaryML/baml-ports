// Ported from sasso `src/eval/modules.rs` (namespace `root.eval.modules`).

/// The evaluator file-context fields swapped by [`Evaluator::enter_origin_file`]
/// and restored by [`Evaluator::leave_module_file`]:
/// `(current_url, current_source, current_file_dir, current_canonical)`.
type SavedModuleFile = root.std.Tuple4<string, string, string?, root.importer.CanonicalUrl?>;

interface EvaluatorModules {
    /// Register an `@extend` directive: validate the (interpolation-resolved)
    /// target, then record one [`PendingExtend`] per comma-separated target.
    /// `parents` is the enclosing style-rule selector list; `@extend` outside a
    /// style rule (top level or directly inside `@at-root`/an at-rule) is an
    /// error.
    function register_extend(
        self,
        selector: root.ast.TplPiece[],
        optional: bool,
        pos: root.scanner.Pos,
        parents: string[],
    ) -> void throws unknown;

    /// Post-eval extension pass: rewrite every emitted style-rule selector list
    /// according to the collected `@extend` directives, drop placeholder-only
    /// rules, and error on an unmatched non-`!optional` extend.
    function apply_extends(self, out: root.eval.OutNode[]) -> void throws unknown;

    /// `@include meta.load-css($url, $with: (...))`: load the module at `$url`
    /// and emit its CSS into the current sink, optionally configuring it with
    /// `$with`. Unlike `@use`, it binds no namespace and exposes no members; it
    /// reuses the shared `load_module` machinery (cache, cycle guard, CSS emit).
    function exec_load_css(
        self,
        args: root.ast.CallArg[],
        content: root.ast.Stmt[]?,
        pos: root.scanner.Pos,
        parents: string[],
        sink: root.std.Cell<root.eval.Sink>,
    ) -> void throws unknown;

    /// `meta.load-css` with its arguments already evaluated — the form a
    /// first-class reference to it arrives in (`meta.apply(meta.get-mixin(
    /// "load-css"), …)`).
    function load_css_evaled(
        self,
        pos_args: root.value.Value[],
        named: root.std.Tuple2<string, root.value.Value>[],
        content: root.ast.Stmt[]?,
        pos: root.scanner.Pos,
        parents: string[],
        sink: root.std.Cell<root.eval.Sink>,
    ) -> void throws unknown;

    /// Install a saved environment snapshot, returning the displaced one to
    /// restore afterwards.
    function install_env(
        self,
        env_: root.eval.SavedModuleEnv,
    ) -> root.eval.SavedModuleEnv throws unknown;

    /// Clone the current per-module environment (for capturing a content block's
    /// call-site closure).
    function snapshot_env(self) -> root.eval.SavedModuleEnv throws unknown;

    /// Process a `@use "<url>" [as ns|as *] [with (...)];` for a built-in
    /// `sass:*` module or a user stylesheet.
    function exec_use(
        self,
        url: string,
        namespace: string?,
        star: bool,
        config: root.ast.ConfigEntry[],
        pos: root.scanner.Pos,
        parents: string[],
        sink: root.std.Cell<root.eval.Sink>,
    ) -> void throws unknown;

    /// Reject a namespace already bound by another `@use` in the same sheet.
    function check_namespace_free(self, ns: string, pos: root.scanner.Pos) -> void throws unknown;

    /// Evaluate a `with (...)` configuration clause into a name -> (value,
    /// is_default) map.
    function eval_config(
        self,
        config: root.ast.ConfigEntry[],
    ) -> map<string, root.std.Tuple2<root.value.Value, bool>> throws unknown;

    /// Load (and cache) a user module: resolve its URL, evaluate it once into an
    /// isolated environment with `config` applied to its `!default` variables,
    /// emit its CSS into `sink`, and return the shared module instance plus the
    /// list of config keys the module consumed (for `@forward ... with`
    /// pass-through).
    /// Collect a module's full subtree CSS (dependencies upstream-first,
    /// each module once), un-wrapping embedded module-scope nodes — used for
    /// `meta.load-css`, which re-emits the whole subtree at the call site
    /// (dart `_combineCss` with `clone: true`).
    /// A fresh explicit-configuration identity.
    function fresh_config_id(self) -> int throws unknown;

    function subtree_css(self, key: string) -> root.eval.OutNode[] throws unknown;

    function walk_subtree(
        self,
        key: string,
        visited: map<string, bool>,
        out: root.eval.OutNode[],
    ) -> void throws unknown;

    /// Register a unique `meta.load-css` copy scope for `key` at the current
    /// call site: the caller gains a load edge to the copy (its extensions
    /// apply to it), and origins inside the base's subtree are linked during
    /// `apply_extends`.
    function register_load_css_copy(self, key: string) -> string throws unknown;

    /// The copy scope and subtree CSS for one forced re-emit. Inside a
    /// module-loading `@import`, all loads share the import's single copy key
    /// and visited set (a diamond's shared upstream emits once per import);
    /// a `meta.load-css` call gets its own key and a fresh walk.
    function clone_module_css(
        self,
        key: string,
    ) -> root.std.Tuple2<string, root.eval.OutNode[]> throws unknown;

    function load_module(
        self,
        url: string,
        config: map<string, root.std.Tuple2<root.value.Value, bool>>,
        config_id: int,
        pos: root.scanner.Pos,
        parents: string[],
        force_reemit: bool,
        sink: root.std.Cell<root.eval.Sink>,
    ) -> root.std.Tuple2<root.eval.Module, string[]> throws unknown;

    /// Evaluate a parsed module sheet in an isolated environment. The module's
    /// top-level CSS is emitted into `sink`; its members are captured into a
    /// [`Module`]. `config` overrides its `!default` variables.
    function eval_module(
        self,
        key: string,
        diag_url: string,
        module_source: string,
        sheet: root.ast.Stylesheet,
        config: map<string, root.std.Tuple2<root.value.Value, bool>>,
        config_id: int,
        pos: root.scanner.Pos,
        sink: root.std.Cell<root.eval.Sink>,
        css: bool,
    ) -> root.std.Tuple2<root.eval.Module, string[]> throws unknown;

    /// Process a `@forward "<url>" [as p-*] [show ..|hide ..] [with (..)];`:
    /// load the target module (emitting its CSS), then re-export its public
    /// members from the module currently being evaluated, applying prefix and
    /// show/hide filters.
    function exec_forward(
        self,
        url: string,
        prefix: string?,
        show: root.ast.ForwardMember[]?,
        hide: root.ast.ForwardMember[]?,
        config: root.ast.ConfigEntry[],
        pos: root.scanner.Pos,
        parents: string[],
        sink: root.std.Cell<root.eval.Sink>,
    ) -> void throws unknown;

    /// Enter the file a callable or content block was written in, for the
    /// duration of its body (dart evaluates a mixin, function, or `@content`
    /// block where it was written: its output maps to that file, and its
    /// diagnostics show that file's name and source). Returns `None` — and
    /// swaps nothing — when the body is in the current file already, so a
    /// same-file call costs a string comparison; pass the result to
    /// [`Self::leave_module_file`].
    function enter_origin_file(
        self,
        origin: root.value.MixinOrigin?,
    ) -> SavedModuleFile? throws unknown;

    /// Snapshot the current file context as a [`crate::value::MixinOrigin`]:
    /// the defining file of a callable being captured, or of a content block
    /// at its `@include` (so a later `meta.apply` from another file still
    /// resolves its relative loads here). There is always a context to
    /// snapshot — an entry compiled without `Options::url` has an empty
    /// display url and canonical, and a callable it defines must still switch
    /// back to it (so its diagnostics report the entry's empty `url`/`path`)
    /// when invoked from inside a loaded file.
    function current_mixin_origin(self) -> root.value.MixinOrigin throws unknown;

    /// Restore the file swapped out by [`Self::enter_origin_file`].
    function leave_module_file(self, saved: SavedModuleFile?) -> void throws unknown;

    /// The diagnostic display URL for a `@use`/`@import`ed module, as dart-sass
    /// spells it in stack frames. A filesystem path — the `FsImporter`'s
    /// canonical key is the resolved absolute path — is shown relative to the
    /// current directory (`src/sub/_partial.scss`, whether it was reached
    /// relatively or through a load path), unless that spelling has more
    /// segments than the absolute path, which is then shown as is (dart's
    /// `p.prettyUri`). Any other canonical URL (a custom importer's key) shows
    /// its last segment, falling back to the `@use` url when the key has none.
    function module_diag_url(self, url: string, key: string) -> string throws unknown;

    /// How a stack frame names `key`, when `key` names a file at all.
    ///
    /// A path and a `file://` URL are two spellings the two front ends
    /// arrive with — the binary passes paths, the JS API passes URLs because
    /// its importer bridge resolves relative `@use` against them — and both
    /// must produce the frame dart produces. `None` is "not a file": a
    /// `data:` URL, or a custom importer's key, which keep their own rule.
    function pretty_name(self, key: string) -> string? throws unknown;

    /// Install `module`'s environment for a cross-module member invocation,
    /// returning the previous environment to restore with [`leave_module`].
    function enter_module(
        self,
        module: root.eval.Module,
    ) -> root.eval.SavedModuleEnv throws unknown;

    /// Restore the environment captured by [`enter_module`]. If the saved env
    /// recorded a module, its (possibly mutated) global scope is written back so
    /// a `!global` assignment inside the module persists.
    function leave_module(self, saved: root.eval.SavedModuleEnv) -> void throws unknown;

    /// Resolve a namespaced module variable `ns.$name`. Resolves a user module
    /// first, then a built-in module bound to `ns`.
    function eval_module_var(
        self,
        ns: string,
        name: string,
        pos: root.scanner.Pos,
    ) -> root.value.Value throws unknown;
}

implements EvaluatorModules for root.eval.Evaluator {
    /// Register an `@extend` directive: validate the (interpolation-resolved)
    /// target, then record one [`PendingExtend`] per comma-separated target.
    /// `parents` is the enclosing style-rule selector list; `@extend` outside a
    /// style rule (top level or directly inside `@at-root`/an at-rule) is an
    /// error.
    function register_extend(self, selector: root.ast.TplPiece[], optional: bool, pos: root.scanner.Pos, parents: string[]) -> void {
        // dart checks `_styleRule` (null inside `@at-root` before any nested
        // rule), not `_styleRuleIgnoringAtRoot` (which still feeds `&`).
        if (parents.length() == 0 || self.at_root_excluding_style_rule) {
            throw root.error.Error.at("@extend may only be used within style rules.", pos);
        }
        let extenders: string[] = match (self.current_selector) {
            let sel: string[] => sel,
            null => root.std.clone_vec(parents),
        };
        let target = self.eval_template(selector);
        if (root.std.trim(target) == "") {
            throw root.error.Error.at("expected selector.", pos);
        }
        // dart rejects a *leading* empty component (`@extend ,a`) as
        // "expected selector.", while still allowing a trailing comma
        // (`@extend a,`); an empty middle component falls through to the
        // usual "target selector was not found." path.
        if (root.std.trim_start(target).starts_with(",")) {
            throw root.error.Error.at("expected selector.", pos);
        }
        let in_media = self.media_queries.length() != 0;
        for (let t in root.eval.split_commas(target).deref()) {
            let t = root.std.trim(t);
            if (t == "") {
                continue;
            }
            match (root.selector.classify_target(t)) {
                let simple: root.selector.TargetClass_Simple => {
                    self.extends_.push(root.eval.PendingExtend {
                        origin: self.current_module,
                        target: simple._0,
                        target_str: t,
                        extenders: extenders,
                        extender_breaks: root.std.clone_vec(self.current_linebreaks),
                        optional: optional,
                        in_media: in_media,
                        pos: pos,
                    });
                }
                root.selector.TargetClass_Complex {} => {
                    throw root.error.Error.at("complex selectors may not be extended.", pos);
                }
                root.selector.TargetClass_Compound {} => {
                    throw root.error.Error.at(
                        "compound selectors may no longer be extended.\nConsider `@extend a, :hover` instead.\nSee https://sass-lang.com/d/extend-compound for details.",
                        pos,
                    );
                }
                root.selector.TargetClass_Invalid {} => {
                    throw root.error.Error.at("expected selector.", pos);
                }
                _ => root.std.unreachable(),
            }
        }
    }

    /// Post-eval extension pass: rewrite every emitted style-rule selector list
    /// according to the collected `@extend` directives, drop placeholder-only
    /// rules, and error on an unmatched non-`!optional` extend.
    function apply_extends(self, out: root.eval.OutNode[]) -> void {
        // Per-origin upstream closures over the recorded load edges (the
        // module keys each origin can see, including itself).
        let deps = self.module_deps;
        let bfs = (start: string) -> map<string, bool> {
            let seen: map<string, bool> = {};
            let _ = root.std.set_insert(seen, start);
            let stack: string[] = [start];
            while let k: string = stack.pop() {
                let nexts = deps.get(k);
                if (nexts != null) {
                    for (let n in nexts.keys()) {
                        if (root.std.set_insert(seen, n)) {
                            stack.push(n);
                        }
                    }
                }
            }
            seen
        };
        let raw_cache: map<string, map<string, bool>> = {};
        for (let pe in self.extends_) {
            if (raw_cache.has(pe.origin)) {
                continue;
            }
            let seen = bfs(pe.origin);
            let _ = raw_cache.set(pe.origin, seen);
        }
        // A `meta.load-css` copy is also visible to any origin inside the
        // copied module's subtree: the clone carries that subtree's own
        // extensions (dart bakes them into the cloned CSS).
        let copies = self.load_css_copies;
        for (let copy in copies) {
            let copy_key = copy._0;
            let base = copy._1;
            let base_reach = bfs(base);
            for (let origin in raw_cache.keys()) {
                let set = raw_cache[origin];
                if (base_reach.has(origin)) {
                    let _ = set.set(copy_key, true);
                }
            }
        }
        // An origin NOT reachable from the root tree (it was only ever
        // pulled in through `meta.load-css`) exists solely inside the
        // clones: its extensions apply to copy scopes only, never to the
        // main tree's module scopes (dart: such a module's extension store
        // never joins the root `_combineCss`).
        if (copies.length() != 0) {
            let main_reach = bfs("");
            for (let origin in raw_cache.keys()) {
                let set = raw_cache[origin];
                if (origin != "" && !main_reach.has(origin)) {
                    root.std.map_retain(set, (s: string, _v: bool) -> bool {
                        copies.some((c) -> { c._0 == s })
                    });
                }
            }
        }
        // PORT: `drop(copies); drop(deps);` (RefCell borrows) — nothing to release.
        // PORT: `Rc<HashSet>` values → the sets themselves (shared by reference).
        let closure_cache: map<string, map<string, bool>> = raw_cache;
        let extensions: root.selector.Extension[] = [];
        // PORT: `.enumerate()` → an index counter.
        let reg_idx = 0;
        for (let pe in self.extends_) {
            let extenders: root.selector.Complex[] = [];
            let extender_breaks: bool[] = [];
            let i = 0;
            for (let ext in pe.extenders) {
                let c = root.selector.parse.parse_complex_one(ext);
                if (c != null) {
                    // A bogus extender with a trailing combinator (`d +`) can't
                    // extend anything — dart-sass drops it (with a deprecation).
                    if (c.trailing.length() == 0) {
                        extenders.push(c);
                        extender_breaks.push(pe.extender_breaks.at(i) ?? false);
                    }
                }
                i += 1;
            }
            extensions.push(root.selector.Extension {
                target: pe.target,
                extenders: extenders,
                extender_breaks: extender_breaks,
                optional: pe.optional,
                matched: root.std.Cell.new(false),
                origin: pe.origin,
                reg_idx: reg_idx,
                derived: false,
                via_origin: null,
                origin_closure: closure_cache[pe.origin],
            });
            reg_idx += 1;
        }
        // Keep GLOBAL REGISTRATION ORDER (module eval order): a scope's own
        // extensions register before its downstream loaders', and foreign
        // modules follow first-load order — the incremental fold inserts each
        // later application's products closest to the source complex, which
        // reproduces dart's combine-time sequence (own products innermost,
        // foreign stores reverse-load in the OUTPUT). Same-module extenders
        // stay in document order for the merged per-store batches. (An
        // earlier descending-closure-size sort approximated this but
        // misplaced sibling stores with unequal upstream counts — bulma's
        // form vs elements modules.)

        // An `@extend` registered inside `@media` may not extend a selector
        // outside any media context (dart-sass "You may not @extend selectors
        // across media queries."). Detect when an in-media extend's target
        // matches a root-level (non-media) rule.
        for (let pe in self.extends_) {
            if (pe.in_media && root.eval.root_rule_contains_target(out, pe.target)) {
                throw root.error.Error.at(
                    "You may not @extend selectors across media queries.",
                    pe.pos,
                );
            }
        }

        // Per-module visibility: an extension's origin can rewrite a module's
        // CSS when that module is (transitively) loaded by the origin.
        // Parallel to the (sorted) extensions list.
        let origins: string[] = extensions.map((e) -> { e.origin });
        let closures: map<string, map<string, bool>> = {};
        for (let k in closure_cache.keys()) {
            let _ = closures.set(k, root.std.clone_map(closure_cache[k]));
        }
        // The store-merge order context: reverse load edges + first-load
        // ranks (an origin's registrations are contiguous, so its smallest
        // reg index is its load rank).
        let rev_deps: map<string, string[]> = {};
        for (let loader in self.module_deps.keys()) {
            let loadeds = self.module_deps[loader];
            for (let loaded in loadeds.keys()) {
                let empty: string[] = [];
                rev_deps.get_or_insert(loaded, empty).push(loader);
            }
        }
        let first_reg: map<string, int> = {};
        let j = 0;
        for (let pe in self.extends_) {
            let _ = first_reg.get_or_insert(pe.origin, j);
            j += 1;
        }
        let has_import_clones = self.load_css_copies.length() != 0
            || rev_deps.keys().some((k) -> { k.includes("#import") || k.includes("#copy") });
        if (has_import_clones) {
            // Legacy order for @import-mixed compiles (the store-merge model
            // below assumes pure-@use module identity): downstream-first by
            // closure size, stable within a module.
            // PORT: `into_iter().zip(origins).map(..).collect()` → an index loop.
            let keyed: root.std.Tuple3<int, root.selector.Extension, string>[] = [];
            let z = 0;
            while (z < extensions.length() && z < origins.length()) {
                let e = extensions[z];
                let o = origins[z];
                let c = closure_cache.get(o);
                keyed.push(root.std.Tuple3 {
                    _0: if (c != null) { c.length() } else { 0 },
                    _1: e,
                    _2: o,
                });
                z += 1;
            }
            // PORT: `sort_by_key(|(n, _, _)| Reverse(*n))` → key `-n` (stable).
            let _ = keyed.sort_by_key((t) -> { 0 - t._0 });
            extensions = keyed.map((t) -> { t._1 });
            origins = keyed.map((t) -> { t._2 });
        }
        let order = root.eval.ExtendOrderCtx {
            rev_deps: rev_deps,
            first_reg: first_reg,
            has_import_clones: has_import_clones,
        };
        root.eval.rewrite_nodes_scoped(out, "", extensions, origins, closures, order);

        // Report the first unmatched non-optional extend. A target that only
        // appears in an omitted bogus-combinator rule still counts as found
        // (dart extends it; the result is bogus too and is omitted).
        // PORT: `self.extends.iter().zip(extensions.iter())` → an index loop.
        let x = 0;
        while (x < self.extends_.length() && x < extensions.length()) {
            let pe = self.extends_[x];
            let ext = extensions[x];
            x += 1;
            // A private placeholder (`%-x`/`%_x`) is only visible within its
            // own module; any other target is visible across the extension's
            // module closure.
            let private = match (pe.target) {
                root.selector.Simple_Placeholder { _0: let n } if n.starts_with("-") || n.starts_with("_") => true,
                _ => false,
            };
            if (!ext.optional
                && !ext.matched.get()
                && !self.bogus_selectors
                    .some((s) -> { root.selector.selector_contains_simple(s, pe.target) })
                && !self.placeholder_rules.some((ms) -> {
                    let m = ms._0;
                    let s = ms._1;
                    let visible = if (private) {
                        m == ext.origin
                    } else {
                        ext.origin_closure.has(m)
                    };
                    visible && root.selector.selector_contains_simple(s, pe.target)
                }))
            {
                throw root.error.Error.at(
                    `The target selector was not found.\nUse "@extend ${pe.target_str} !optional" to avoid this error.`,
                    pe.pos,
                );
            }
        }
    }

    /// `@include meta.load-css($url, $with: (...))`: load the module at `$url`
    /// and emit its CSS into the current sink, optionally configuring it with
    /// `$with`. Unlike `@use`, it binds no namespace and exposes no members; it
    /// reuses the shared `load_module` machinery (cache, cycle guard, CSS emit).
    function exec_load_css(self, args: root.ast.CallArg[], content: root.ast.Stmt[]?, pos: root.scanner.Pos, parents: string[], sink: root.std.Cell<root.eval.Sink>) -> void {
        let evaled = self.eval_call_args(args);
        let pos_args = evaled._0;
        let named = evaled._1;
        self.load_css_evaled(pos_args, named, content, pos, parents, sink)
    }

    /// `meta.load-css` with its arguments already evaluated — the form a
    /// first-class reference to it arrives in (`meta.apply(meta.get-mixin(
    /// "load-css"), …)`).
    function load_css_evaled(self, pos_args: root.value.Value[], named: root.std.Tuple2<string, root.value.Value>[], content: root.ast.Stmt[]?, pos: root.scanner.Pos, parents: string[], sink: root.std.Cell<root.eval.Sink>) -> void {
        if (content != null) {
            throw root.error.Error.at(
                "Mixin doesn't accept a content block.",
                pos,
            );
        }
        // PORT: `pos_args.into_iter()` + `iter.next()` ×3 → indexed reads.
        let url_val: root.value.Value? = pos_args.at(0);
        let with_val: root.value.Value? = pos_args.at(1);
        if (pos_args.length() > 2) {
            throw root.error.Error.at(
                "Only 2 arguments allowed, but 3 were passed.",
                pos,
            );
        }
        for (let nv in named) {
            let n = nv._0;
            let v = nv._1;
            match (n) {
                "url" => {
                    url_val = v;
                }
                "with" => {
                    with_val = v;
                }
                let other => {
                    throw root.error.Error.at("No argument named $" + other + ".", pos);
                }
            }
        }
        let url = match (url_val) {
            let s: root.value.Value_Str => s._0.text,
            null => {
                throw root.error.Error.at("Missing argument $url.", pos);
            }
            let other: root.value.Value => {
                throw root.error.Error.at(
                    "$url: " + other.to_css(false) + " is not a string.",
                    pos,
                );
            }
        };
        // Build the configuration from the `$with` map (string keys → variables).
        let config: map<string, root.std.Tuple2<root.value.Value, bool>> = {};
        // PORT: `with_val.take()` → `with_val` (not read afterwards).
        match (with_val) {
            null => {}
            // An empty literal `()` parses as an empty list, not a map.
            let l: root.value.Value_List if l._0.items.length() == 0 => {}
            let m: root.value.Value_Map => {
                for (let kv in m._0.entries) {
                    let k = kv._0;
                    let v = kv._1;
                    let key = match (k) {
                        let s: root.value.Value_Str => root.eval.normalize_var_name(s._0.text),
                        let other => {
                            throw root.error.Error.at(
                                "$with key: " + other.to_css(false) + " is not a string.",
                                pos,
                            );
                        }
                    };
                    // Dash/underscore-insensitive: `a-b` and `a_b` collide.
                    if (config.has(key)) {
                        throw root.error.Error.at(
                            "The variable $" + key + " was configured twice.",
                            pos,
                        );
                    }
                    let _ = config.set(key, root.std.Tuple2 { _0: v.without_slash(), _1: false });
                }
            }
            let other: root.value.Value => {
                throw root.error.Error.at(
                    "$with: " + other.to_css(false) + " is not a map.",
                    pos,
                );
            }
        }
        // A built-in `sass:*` module emits no CSS (and can't be configured).
        let m = root.std.strip_prefix(url, "sass:");
        if (m != null) {
            if (root.builtins.is_module(m)) {
                if (config.length() != 0) {
                    throw root.error.Error.at(
                        `Built-in module sass:${m} can't be configured.`,
                        pos,
                    );
                }
                return;
            }
            throw root.error.Error.at("Can't find stylesheet to import.", pos);
        }
        let conf_keys: string[] = config.keys();
        // Evaluate the module into a fresh TOP-LEVEL buffer so its body runs in
        // its own top-level context — a module top-level declaration errors no
        // matter where load-css is invoked (dart-sass) — then splice the emitted
        // nodes into the caller's position.
        let buf: root.eval.OutNode[] = [];
        let consumed = {
            let top: root.eval.Sink = root.eval.Sink_Top { _0: buf };
            let module_sink = root.std.Cell.new(top);
            let config_id = if (config.length() == 0) {
                0
            } else {
                self.fresh_config_id()
            };
            let loaded = self.load_module(url, config, config_id, pos, parents, true, module_sink);
            let _module = loaded._0;
            loaded._1
        };
        if (conf_keys.some((k) -> { !consumed.includes(k) })) {
            throw root.error.Error.at(
                "This variable was not declared with !default in the @used module.",
                pos,
            );
        }
        root.eval.splice_nodes(sink, buf);
    }

    /// Install a saved environment snapshot, returning the displaced one to
    /// restore afterwards.
    function install_env(self, env_: root.eval.SavedModuleEnv) -> root.eval.SavedModuleEnv {
        // PORT: each `std::mem::replace(&mut self.f, env.f)` → read then assign.
        // The parameter is `env_`: a bare `env.x` is BAML's `env` reference.
        let scopes = self.scopes;
        self.scopes = env_.scopes;
        let var_spans = self.var_spans;
        self.var_spans = env_.var_spans;
        let scope_semi_global = self.scope_semi_global;
        self.scope_semi_global = env_.scope_semi_global;
        let functions = self.functions;
        self.functions = env_.functions;
        let mixins = self.mixins;
        self.mixins = env_.mixins;
        let used_modules = self.used_modules;
        self.used_modules = env_.used_modules;
        let star_modules = self.star_modules;
        self.star_modules = env_.star_modules;
        let used_user_modules = self.used_user_modules;
        self.used_user_modules = env_.used_user_modules;
        let star_user_modules = self.star_user_modules;
        self.star_user_modules = env_.star_user_modules;
        root.eval.SavedModuleEnv {
            scopes: scopes,
            var_spans: var_spans,
            scope_semi_global: scope_semi_global,
            functions: functions,
            mixins: mixins,
            used_modules: used_modules,
            star_modules: star_modules,
            used_user_modules: used_user_modules,
            star_user_modules: star_user_modules,
            write_back: null,
        }
    }

    /// Clone the current per-module environment (for capturing a content block's
    /// call-site closure).
    function snapshot_env(self) -> root.eval.SavedModuleEnv {
        // Like a callable's closure, the snapshot SHARES its frames with the
        // chain it was taken from, so they have to exist first.
        root.eval.materialize_fn_frames(self.functions);
        root.eval.materialize_fn_frames(self.mixins);
        // PORT: `Vec`/`HashMap` `.clone()` → shallow copies (the chains are
        // pushed/popped in place afterwards; the frames themselves stay shared).
        root.eval.SavedModuleEnv {
            scopes: root.std.clone_vec(self.scopes),
            var_spans: root.std.clone_vec(self.var_spans),
            scope_semi_global: root.std.clone_vec(self.scope_semi_global),
            functions: root.std.clone_vec(self.functions),
            mixins: root.std.clone_vec(self.mixins),
            used_modules: root.std.clone_map(self.used_modules),
            star_modules: root.std.clone_vec(self.star_modules),
            used_user_modules: root.std.clone_map(self.used_user_modules),
            star_user_modules: root.std.clone_vec(self.star_user_modules),
            write_back: null,
        }
    }

    /// Process a `@use "<url>" [as ns|as *] [with (...)];` for a built-in
    /// `sass:*` module or a user stylesheet.
    function exec_use(self, url: string, namespace: string?, star: bool, config: root.ast.ConfigEntry[], pos: root.scanner.Pos, parents: string[], sink: root.std.Cell<root.eval.Sink>) -> void {
        // Built-in `sass:<mod>` modules.
        let m = root.std.strip_prefix(url, "sass:");
        if (m != null) {
            let module = root.builtins.module_name(m);
            if (module == null) {
                throw root.error.Error.at("Can't find stylesheet to import.", pos);
            }
            if (config.length() != 0) {
                throw root.error.Error.at(
                    "Built-in modules can't be configured.",
                    pos,
                );
            }
            if (star) {
                if (!self.star_modules.includes(module)) {
                    self.star_modules.push(module);
                }
                return;
            }
            let ns = namespace ?? module;
            self.check_namespace_free(ns, pos);
            let _ = self.used_modules.set(ns, module);
            return;
        }

        // A user stylesheet module.
        let conf = self.eval_config(config);
        let conf_keys: string[] = conf.keys();
        let config_id = if (conf.length() == 0) {
            0
        } else {
            self.fresh_config_id()
        };
        // `parents` is only non-empty when this `@use` sits at the top of a
        // sheet imported INSIDE a style rule: the module still evaluates in a
        // clean context, but its emitted CSS joins the importing rule's
        // selectors (dart nests the whole import subtree's CSS —
        // nested_import_into_use).
        // The load runs under a diagnostic `@use` frame so an error anywhere
        // in the module (parse or eval) carries the loader chain
        // (dart: `_mod.scss 3:19  @use` / `main.scss 1:1  root stylesheet`).
        let saved_member = self.enter_call(pos, 0, "@use");
        // PORT: `let result = …; self.leave_call(..); result?` → the `Err` path
        // leaves the frame in the catch arm before rethrowing.
        let result = self.load_module(url, conf, config_id, pos, parents, false, sink) catch (e) {
            let err: root.error.Error => {
                self.leave_call(saved_member);
                throw err;
            }
        };
        self.leave_call(saved_member);
        let module = result._0;
        let consumed = result._1;
        // Any configured variable the module did not consume via a `!default`
        // declaration is an error.
        if (conf_keys.some((k) -> { !consumed.includes(k) })) {
            throw root.error.Error.at(
                "This variable was not declared with !default in the @used module.",
                pos,
            );
        }
        if (star) {
            // A member the new global module exposes that the current sheet
            // already defines at the top level is a conflict.
            let g = self.scopes.at(0);
            if (g != null) {
                for (let name in module.vars.keys()) {
                    if (!root.eval.is_private_member(name) && g.has(name)) {
                        throw root.error.Error.at(
                            "This module and the new module both define a variable named \"$" + name + "\".",
                            pos,
                        );
                    }
                }
            }
            // `@use`ing the same module twice as `*` is idempotent (no
            // ambiguity), so de-duplicate by module identity.
            // PORT: `Rc::as_ptr` identity → the module's `_id`.
            let ptr = module._id;
            if (!self.star_user_modules.some((m) -> { m._id == ptr })) {
                self.star_user_modules.push(module);
            }
            return;
        }
        let ns = match (namespace) {
            let n: string => n,
            null => root.eval.default_namespace(url, pos),
        };
        self.check_namespace_free(ns, pos);
        let _ = self.used_user_modules.set(ns, module);
    }

    /// Reject a namespace already bound by another `@use` in the same sheet.
    function check_namespace_free(self, ns: string, pos: root.scanner.Pos) -> void {
        if (self.used_modules.has(ns) || self.used_user_modules.has(ns)) {
            throw root.error.Error.at(
                `There's already a module with namespace "${ns}".`,
                pos,
            );
        }
    }

    /// Evaluate a `with (...)` configuration clause into a name -> (value,
    /// is_default) map.
    function eval_config(self, config: root.ast.ConfigEntry[]) -> map<string, root.std.Tuple2<root.value.Value, bool>> {
        let map: map<string, root.std.Tuple2<root.value.Value, bool>> = {};
        for (let entry in config) {
            let v = self.eval_expr(entry.value).without_slash();
            // Variable names are dash/underscore-insensitive: store the
            // canonical (dashed) form so `$a_b` and `$a-b` configure the same
            // variable. A duplicate key is an error.
            let key = root.eval.normalize_var_name(entry.name);
            if (map.has(key)) {
                throw root.error.Error.unpositioned(
                    "The variable $" + entry.name + " was configured twice.",
                );
            }
            let _ = map.set(key, root.std.Tuple2 { _0: v, _1: entry.is_default });
        }
        map
    }

    /// Load (and cache) a user module: resolve its URL, evaluate it once into an
    /// isolated environment with `config` applied to its `!default` variables,
    /// emit its CSS into `sink`, and return the shared module instance plus the
    /// list of config keys the module consumed (for `@forward ... with`
    /// pass-through).
    /// Collect a module's full subtree CSS (dependencies upstream-first,
    /// each module once), un-wrapping embedded module-scope nodes — used for
    /// `meta.load-css`, which re-emits the whole subtree at the call site
    /// (dart `_combineCss` with `clone: true`).
    /// A fresh explicit-configuration identity.
    function fresh_config_id(self) -> int {
        let n = self.config_id_counter + 1;
        self.config_id_counter = n;
        n
    }

    function subtree_css(self, key: string) -> root.eval.OutNode[] {
        let out: root.eval.OutNode[] = [];
        let visited: map<string, bool> = {};
        self.walk_subtree(key, visited, out);
        root.eval.trim_leading_blanks(out);
        out
    }

    function walk_subtree(self, key: string, visited: map<string, bool>, out: root.eval.OutNode[]) -> void {
        if (!root.std.set_insert(visited, key)) {
            return;
        }
        let order = self.module_dep_order.get(key);
        let deps: string[] = if (order != null) { root.std.clone_vec(order) } else { [] };
        for (let d in deps) {
            self.walk_subtree(d, visited, out);
        }
        let m = self.module_cache.get(key);
        if (m != null) {
            for (let n in m.css) {
                // An embedded dependency's scope wrapper is covered by the
                // dependency walk above; a materialized clone (no load edge)
                // stays.
                if let scope: root.eval.OutNode_ModuleScope = n {
                    let k = scope.key;
                    if (!k.includes("#copy") && !k.includes("#import")) {
                        continue;
                    }
                }
                // PORT: `n.clone()` is a deep clone of the node tree (the
                // extend pass later rewrites each copy in place).
                out.push(baml.deep_copy(n));
            }
        }
    }

    /// Register a unique `meta.load-css` copy scope for `key` at the current
    /// call site: the caller gains a load edge to the copy (its extensions
    /// apply to it), and origins inside the base's subtree are linked during
    /// `apply_extends`.
    function register_load_css_copy(self, key: string) -> string {
        let n = self.copy_counter + 1;
        self.copy_counter = n;
        let copy_key = `${key}#copy${n}`;
        let empty: map<string, bool> = {};
        let _ = self.module_deps
            .get_or_insert(self.current_module, empty)
            .set(copy_key, true);
        self.load_css_copies.push(root.std.Tuple2 { _0: copy_key, _1: key });
        copy_key
    }

    /// The copy scope and subtree CSS for one forced re-emit. Inside a
    /// module-loading `@import`, all loads share the import's single copy key
    /// and visited set (a diamond's shared upstream emits once per import);
    /// a `meta.load-css` call gets its own key and a fresh walk.
    function clone_module_css(self, key: string) -> root.std.Tuple2<string, root.eval.OutNode[]> {
        let state = self.import_clone;
        self.import_clone = null;
        if (state != null) {
            let k = state._0;
            let visited = state._1;
            let copy_key = k;
            let empty: map<string, bool> = {};
            let _ = self.module_deps
                .get_or_insert(self.current_module, empty)
                .set(copy_key, true);
            self.load_css_copies.push(root.std.Tuple2 { _0: copy_key, _1: key });
            let out: root.eval.OutNode[] = [];
            self.walk_subtree(key, visited, out);
            root.eval.trim_leading_blanks(out);
            self.import_clone = root.std.Tuple2 { _0: k, _1: visited };
            root.std.Tuple2 { _0: copy_key, _1: out }
        } else {
            let copy_key = self.register_load_css_copy(key);
            root.std.Tuple2 { _0: copy_key, _1: self.subtree_css(key) }
        }
    }

    function load_module(self, url: string, config: map<string, root.std.Tuple2<root.value.Value, bool>>, config_id: int, pos: root.scanner.Pos, parents: string[], force_reemit: bool, sink: root.std.Cell<root.eval.Sink>) -> root.std.Tuple2<root.eval.Module, string[]> {
        // Inside a module-loading `@import`, every load re-emits as a clone.
        // A TRUE `meta.load-css` call (not an @import clone): dart re-visits
        // the combined css node-by-node, so every re-visited top-level style
        // rule re-acquires isGroupEnd — the copy's rules blank-separate like
        // freshly written ones (reveal.js print/pdf.scss).
        let is_load_css = force_reemit;
        let force_reemit = force_reemit || self.import_clone != null;
        let importer = self.options.importer;
        // The caller's importer runs OUTSIDE the arena scope: anything it
        // allocates (e.g. a cache of paths it owns) must survive past this
        // compile's arena reset, so route its allocations to the system
        // allocator. The returned `String`s are then deep-copied into the arena
        // below by the parse/eval pipeline.
        let paused = root.arena.pause();
        // Phase 1 of resolution: canonicalize, inside the arena pause so the
        // importer's owned allocations survive this compile's arena reset.
        // `@use`/`@forward` never consider import-only files.
        //
        // Phase 2 (`load`) used to run here too, unconditionally. It is now
        // deferred past the module-cache probe below, because the canonical URL
        // is the cache key and a hit never reads the loaded text: a second
        // `@use` of an already-evaluated module re-emits nothing and re-parses
        // nothing, so reading the file again is a syscall spent on a string
        // that is dropped. dart-sass caches the same way and at the same
        // granularity -- `ImportCache.importCanonical` memoizes per canonical
        // URL, not per edge -- and this file's `@import` path already probes
        // `import_cache` ahead of both phases.
        let phase1: root.std.Tuple3<string, root.importer.CanonicalUrl, root.importer.Importer>? = match (importer) {
            let imp: root.importer.Importer => {
                let ctx = root.importer.CanonicalizeContext {
                    from_import: false,
                    containing_url: self.current_canonical,
                };
                // PORT: an importer failure (`Err(ImporterError)`) is a thrown
                // `root.importer.ImporterError`; the pause guard is lifted by
                // hand before the early return (Rust drops it on `return`).
                let canon = imp.canonicalize(url, ctx) catch (e) {
                    let err: root.importer.ImporterError => {
                        paused.drop();
                        throw root.error.Error.at(err.message, pos);
                    }
                };
                if (canon == null) {
                    null
                } else {
                    // The key is built inside the pause: it outlives this
                    // compile's arena reset in `module_cache`. `imp` rides
                    // along so phase 2 cannot be handed a different importer
                    // than the one that produced `canon`.
                    root.std.Tuple3 { _0: canon.as_str(), _1: canon, _2: imp }
                }
            }
            null => null,
        };
        paused.drop();
        if (phase1 == null) {
            throw root.error.Error.at("Can't find stylesheet to import.", pos);
        }
        let key = phase1._0;
        let canon = phase1._1;
        let imp = phase1._2;
        // The cache probe, and phase 2 only on a miss. Both sit ABOVE the sink
        // mutation below on purpose: popping the pre-module comment run is an
        // edit to the output, and an error out of `load` must not leave it
        // already popped.
        let cached = self.module_cache.get(key);
        let loaded: root.std.Tuple3<string, root.Syntax, string?>? = if (cached != null) {
            null
        } else {
            let paused = root.arena.pause();
            // PORT: the `Err` arm's early return is captured and thrown after
            // the pause guard drops (Rust drops it on `return`). A `catch` arm
            // that throws here would trip a BAML flow-analysis bug: the checker
            // then treats this whole `else` branch as diverging and folds the
            // `cached != null` test below to `true`.
            let load_failed: root.importer.ImporterError? = null;
            let res = imp.load(canon) catch (e) {
                let err: root.importer.ImporterError => {
                    load_failed = err;
                    null
                }
            };
            paused.drop();
            if (load_failed != null) {
                throw root.error.Error.at(load_failed.message, pos);
            }
            if (res != null) {
                root.std.Tuple3 { _0: res.contents, _1: res.syntax, _2: res.source_map_url }
            } else {
                throw root.error.Error.at("Can't find stylesheet to import.", pos);
            }
        };
        // Pop the comment run textually preceding this `@use`/`@forward` so
        // each outcome below can put it back in front of the module's CSS.
        // dart-sass 1.104.1 emits such a comment exactly ONCE: up to 1.104.0 a
        // repeat edge into an already-loaded module re-emitted the comments
        // that preceded its first load, which is the duplication that release
        // fixed.
        let own_run: root.eval.OutNode[] = match (sink.value) {
            let t: root.eval.Sink_Top => {
                let out = t._0;
                let i = out.length();
                while (i > 0 && (out[i - 1] is root.eval.OutNode_Comment || out[i - 1] is root.eval.OutNode_Blank)) {
                    i -= 1;
                }
                root.std.split_off(out, i)
            }
            _ => [],
        };
        // PORT: nested `fn push_run` hoisted to `load_module__push_run` below.
        // A module evaluated once and cached is shared; its CSS is NOT
        // re-emitted. Re-loading it with configuration is an error — unless the
        // configuration targets no variable the module actually defines (a
        // module with no configurable variables may be loaded with or without
        // config). The keys it *does* define count as consumed for the caller.
        if (cached != null) {
            let existing = cached;
            let consumed: string[] = config.keys().filter((k) -> { existing.var(k) != null });
            if (consumed.length() != 0) {
                // An *implicit* configuration (an `@import`'s visible
                // variables) silently reuses the already-evaluated module —
                // `$a: changed; @import "fwd"` keeps the first load's values
                // (dart `Configuration.implicit`) — and re-emits its CSS at
                // this import site (dart clones the module's CSS per import).
                if (self.config_is_implicit) {
                    let empty_set: map<string, bool> = {};
                    let _ = self.module_deps
                        .get_or_insert(self.current_module, empty_set)
                        .set(key, true);
                    {
                        let ord = self.module_dep_order;
                        let empty_order: string[] = [];
                        let v = ord.get_or_insert(self.current_module, empty_order);
                        if (!v.includes(key)) {
                            v.push(key);
                        }
                    }
                    load_module__push_run(sink, own_run);
                    // PORT: `existing.css.clone()` is a deep clone of the node tree.
                    root.eval.splice_nodes(
                        sink,
                        [root.eval.OutNode_ModuleScope {
                            key: key,
                            nodes: root.eval.reparent_nodes(baml.deep_copy(existing.css), parents),
                        }],
                    );
                    return root.std.Tuple2 { _0: existing, _1: consumed };
                }
                // A configuration distributed through several forwards keeps
                // its ORIGINAL identity: re-reaching an already-loaded module
                // with the same original silently reuses it (dart-sass
                // sameOriginal).
                if (config_id != 0 && existing.config_origin == config_id) {
                    load_module__push_run(sink, own_run);
                    return root.std.Tuple2 { _0: existing, _1: consumed };
                }
                throw root.error.Error.at(
                    "This module was already loaded, so it can't be configured using \"with\".",
                    pos,
                );
            }
            // The cached module consumed nothing (it defines none of the
            // configured variables); the caller's own/forwarded handling decides
            // whether the leftover configuration is an error. `meta.load-css`
            // still re-emits the cached CSS at the call site — WITHOUT a load
            // edge to the base module (the caller only gains the copy edge, so
            // a module pulled in solely through load-css never joins the main
            // tree's extension reachability).
            if (!force_reemit) {
                let empty_set: map<string, bool> = {};
                let _ = self.module_deps
                    .get_or_insert(self.current_module, empty_set)
                    .set(key, true);
                let ord = self.module_dep_order;
                let empty_order: string[] = [];
                let v = ord.get_or_insert(self.current_module, empty_order);
                if (!v.includes(key)) {
                    v.push(key);
                }
            }
            // A repeat edge emits nothing of its own: this site's comments stay
            // in place, and dart-sass 1.104.1 no longer re-emits the ones that
            // preceded the module's first load.
            load_module__push_run(sink, own_run);
            if (force_reemit) {
                // A `meta.load-css` copy re-emits the module's whole SUBTREE
                // at the call site under a unique copy scope: the caller's
                // extensions apply to it (caller -> copy edge), the subtree's
                // own extensions apply to the clone, and other loaders'
                // extensions do not (dart `_combineCss` with `clone: true`).
                let cloned = self.clone_module_css(key);
                let copy_key = cloned._0;
                let nodes = cloned._1;
                let nodes = if (is_load_css) {
                    let prev_rule = root.std.Cell.new(false);
                    regroup_load_css_copy(nodes, prev_rule)
                } else {
                    nodes
                };
                root.eval.splice_nodes(
                    sink,
                    [root.eval.OutNode_ModuleScope {
                        key: copy_key,
                        nodes: root.eval.reparent_nodes(nodes, parents),
                    }],
                );
            } else if (!existing.emitted_main) {
                // First loaded inside an import/load-css clone: this plain
                // load is the module's first appearance in the MAIN tree.
                existing.emitted_main = true;
                root.eval.splice_nodes(
                    sink,
                    [root.eval.OutNode_ModuleScope {
                        key: key,
                        nodes: root.eval.reparent_nodes(baml.deep_copy(existing.css), parents),
                    }],
                );
            }
            let none: string[] = [];
            return root.std.Tuple2 { _0: existing, _1: none };
        }
        // Guard against a load cycle.
        if (self.loading.includes(key)) {
            throw root.error.Error.at(
                "Module loop: this module is already being loaded.",
                pos,
            );
        }
        // Past the cache-hit block, every branch of which returns, so phase 2
        // ran and this is `Some`. Erring rather than unwrapping keeps a later
        // edit to that block from turning a missed `return` into a panic.
        if (loaded == null) {
            throw root.error.Error.at("Can't find stylesheet to import.", pos);
        }
        let src = loaded._0;
        let syntax = loaded._1;
        let source_map_url = loaded._2;
        // The display URL a snippet/frame shows for this file.
        let diag_url = self.module_diag_url(url, key);
        // One shared copy of the module's text: for the source-map table, for
        // the module's own evaluation context, and — through that context —
        // for the `MixinOrigin` every callable defined in the file captures,
        // which is what a later cross-module invocation renders against.
        // Nothing reads it when diagnostics and source maps are both off, so
        // skip the copy.
        let text: string = if (self.diag_enabled() || self.options.source_map) {
            src
        } else {
            ""
        };
        if (self.options.source_map) {
            let _ = self.file_texts.set(key, text);
        }
        // A loaded sheet is validated like the entry (a misplaced `@import`
        // in a mixin body is dart's "This at-rule is not allowed here.");
        // plain CSS has nothing to validate.
        // PORT: `let parsed = …and_then(..); match parsed { Ok, Err }` → one
        // block with a `catch` for the `Err` arm.
        let sheet = {
            let sheet = root.eval.parse_with_syntax(src, syntax);
            if (syntax != root.Syntax.Css) {
                root.eval.validate_declarations(sheet);
            }
            sheet
        } catch (err) {
            let e: root.error.Error => {
                // A parse or validation error names the LOADED file: render
                // eagerly under its url/source (the caller's `@use`/`@forward`
                // frame is already on the stack), like dart's
                // `_mod.scss 3:19  @use` + loader chain.
                let saved_url = self.current_url;
                self.current_url = diag_url;
                let saved_source = self.current_source;
                self.current_source = text;
                let e = self.finalize_error(e);
                self.current_url = saved_url;
                self.current_source = saved_source;
                throw e;
            }
        };
        // If the importer asked for a custom source-map URL for this file, record
        // it under the canonical key the source map keys on (the `@import`
        // path in mod.rs does the same for a file it loads).
        if (source_map_url != null) {
            let _ = self.file_map_urls.set(key, source_map_url);
        }
        let is_css = syntax == root.Syntax.Css;
        // A `meta.load-css` first load also records only the copy edge (see
        // the cache-hit branch above).
        if (!force_reemit) {
            let empty_set: map<string, bool> = {};
            let _ = self.module_deps
                .get_or_insert(self.current_module, empty_set)
                .set(key, true);
            let ord = self.module_dep_order;
            let empty_order: string[] = [];
            let v = ord.get_or_insert(self.current_module, empty_order);
            if (!v.includes(key)) {
                v.push(key);
            }
        }
        // Evaluate into a buffer so the emitted CSS can be captured on the
        // module (for per-import re-emission) before splicing into the
        // caller's sink.
        let css_buf: root.eval.OutNode[] = [];
        let evaluated = {
            let top: root.eval.Sink = root.eval.Sink_Top { _0: css_buf };
            let buf_sink = root.std.Cell.new(top);
            self.eval_module(
                key,
                diag_url,
                text,
                sheet,
                config,
                config_id,
                pos,
                buf_sink,
                is_css,
            )
        };
        let module = evaluated._0;
        let consumed = evaluated._1;
        // PORT: `css_buf.clone()` is a deep clone of the node tree (the
        // original is spliced into the output and rewritten in place later).
        module.css = baml.deep_copy(css_buf);
        // PORT: `Rc::new(module)` — the class is already a shared reference.
        let _ = self.module_cache.set(key, module);
        load_module__push_run(sink, own_run);
        // A first load through `meta.load-css` (force_reemit) splices the
        // module's whole subtree under a unique copy scope at the call site;
        // an ordinary `@use`/`@forward` load wraps its own CSS in its module
        // scope.
        if (force_reemit) {
            let cloned = self.clone_module_css(key);
            let copy_key = cloned._0;
            let nodes = cloned._1;
            let nodes = if (is_load_css) {
                let prev_rule = root.std.Cell.new(false);
                regroup_load_css_copy(nodes, prev_rule)
            } else {
                nodes
            };
            root.eval.splice_nodes(
                sink,
                [root.eval.OutNode_ModuleScope {
                    key: copy_key,
                    nodes: root.eval.reparent_nodes(nodes, parents),
                }],
            );
        } else {
            module.emitted_main = true;
            root.eval.splice_nodes(
                sink,
                [root.eval.OutNode_ModuleScope {
                    key: key,
                    nodes: root.eval.reparent_nodes(css_buf, parents),
                }],
            );
        }
        root.std.Tuple2 { _0: module, _1: consumed }
    }

    /// Evaluate a parsed module sheet in an isolated environment. The module's
    /// top-level CSS is emitted into `sink`; its members are captured into a
    /// [`Module`]. `config` overrides its `!default` variables.
    function eval_module(self, key: string, diag_url: string, module_source: string, sheet: root.ast.Stylesheet, config: map<string, root.std.Tuple2<root.value.Value, bool>>, config_id: int, pos: root.scanner.Pos, sink: root.std.Cell<root.eval.Sink>, css: bool) -> root.std.Tuple2<root.eval.Module, string[]> {
        // Save and reset the per-module environment, then restore on the way out.
        // The module's body runs against its own source file for diagnostics
        // (`module_source` is the loaded text itself, not a display-url lookup).
        // Relative URLs inside the module resolve against ITS directory.
        // PORT: each `std::mem::replace`/`std::mem::take`/`Option::take` → read
        // the field, then assign the replacement.
        let module_dir = root.eval.dirname_of(key);
        let saved_dir = self.current_file_dir;
        self.current_file_dir = module_dir;
        // Track the module's canonical URL in lockstep with its directory, so a
        // relative `@use`/`@import` inside the module resolves against IT.
        let saved_canonical = self.current_canonical;
        self.current_canonical = root.importer.CanonicalUrl.new(key);
        let saved_url = self.current_url;
        self.current_url = diag_url;
        self.current_url_stamp = 0;
        let saved_source = self.current_source;
        self.current_source = module_source;
        let saved_scopes = self.scopes;
        self.scopes = [root.eval.new_scope()];
        let saved_var_spans = self.var_spans;
        self.var_spans = if (self.options.source_map) {
            [root.eval.new_span_scope()]
        } else {
            []
        };
        let saved_semi = self.scope_semi_global;
        self.scope_semi_global = [true];
        let saved_funcs = self.functions;
        self.functions = [null];
        let saved_mixins = self.mixins;
        self.mixins = [null];
        let saved_used = self.used_modules;
        self.used_modules = {};
        let saved_star = self.star_modules;
        self.star_modules = [];
        let saved_used_user = self.used_user_modules;
        self.used_user_modules = {};
        let saved_star_user = self.star_user_modules;
        self.star_user_modules = [];
        let saved_fwd = self.forwarded;
        self.forwarded = root.eval.Forwarded.default();
        let saved_config = self.pending_config;
        self.pending_config = config;
        let saved_config_id = self.pending_config_id;
        self.pending_config_id = config_id;
        let saved_consumed = self.consumed_config;
        self.consumed_config = [];
        let saved_selector = self.current_selector;
        self.current_selector = null;
        let saved_module = self.current_module;
        self.current_module = key;
        self.loading.push(key);

        // A `$var: ... !global` anywhere in the module — even in a branch that
        // never evaluates — creates a variable slot defaulting to null, so the
        // module always exposes the same members regardless of how it's
        // evaluated (dart-sass).
        if (!css) {
            let slots: string[] = [];
            root.eval.collect_global_var_decls(sheet.stmts, slots);
            let g = self.scopes.at(0);
            if (g != null) {
                for (let name in slots) {
                    let _ = g.get_or_insert(name, root.value.Value_Null {});
                }
            }
        }

        // A plain-CSS module preserves its nesting (no Sass flattening, `&` kept
        // literal); a Sass module runs the normal evaluator — after its own
        // `@import` deprecations, which dart emits at parse time.
        // PORT: the `Result` is kept as `failed` (the `Err`), caught around each
        // branch.
        let failed: root.error.Error? = null;
        if (css) {
            self.exec_css(sheet.stmts, [], sink) catch (e) {
                let err: root.error.Error => {
                    failed = err;
                }
            };
        } else {
            self.warn_import_rules(sheet.stmts);
            self.exec(sheet.stmts, [], sink) catch (e) {
                let err: root.error.Error => {
                    failed = err;
                }
            };
        }
        // Render a body error NOW, while the module's url/source and the
        // loader's `@use`/`@forward` frame are still current — after the
        // restores below, finalize would name the caller's file instead.
        if (failed != null) {
            failed = self.finalize_error(failed);
        }

        let _ = self.loading.pop();
        // Capture this module's evaluated members before restoring the caller's
        // environment.
        let taken_scopes = self.scopes;
        self.scopes = [];
        let vars_scope = taken_scopes.at(0) ?? root.eval.new_scope();
        // The definition-span frame parallel to `vars_scope` (source-map only).
        let taken_spans = self.var_spans;
        self.var_spans = [];
        let var_spans_scope = taken_spans.at(0) ?? root.eval.new_span_scope();
        // The module's top-level function/mixin frames, shared by Rc with the
        // chains the module's own callables captured. A module always exposes a
        // table even when it declares nothing (its members are looked up
        // through the `Module`, not through a chain), so an empty frame
        // materializes here.
        // PORT: `.into_iter().next().flatten().unwrap_or_else(..)` → one
        // explicit null test over the (doubly optional) first frame.
        let taken_functions = self.functions;
        self.functions = [];
        let first_fn: root.eval.FnFrame = if (taken_functions.length() > 0) { taken_functions[0] } else { null };
        let functions: root.eval.FnScope = if (first_fn != null) { first_fn } else { root.eval.new_fn_scope() };
        let taken_mixins = self.mixins;
        self.mixins = [];
        let first_mixin: root.eval.FnFrame = if (taken_mixins.length() > 0) { taken_mixins[0] } else { null };
        let mixins: root.eval.FnScope = if (first_mixin != null) { first_mixin } else { root.eval.new_fn_scope() };
        let used_user_modules = self.used_user_modules;
        self.used_user_modules = {};
        let star_user_modules = self.star_user_modules;
        self.star_user_modules = [];
        let used_builtin_modules = self.used_modules;
        self.used_modules = {};
        let star_builtin_modules = self.star_modules;
        self.star_modules = [];
        let forwarded = self.forwarded;
        self.forwarded = root.eval.Forwarded.default();
        // Config keys this module actually consumed (via a `!default` declaration
        // or by passing them through a `@forward ... with`).
        let consumed = self.consumed_config;
        self.consumed_config = [];

        // Restore the caller's environment.
        self.scopes = saved_scopes;
        self.var_spans = saved_var_spans;
        self.scope_semi_global = saved_semi;
        self.functions = saved_funcs;
        self.mixins = saved_mixins;
        self.used_modules = saved_used;
        self.star_modules = saved_star;
        self.used_user_modules = saved_used_user;
        self.star_user_modules = saved_star_user;
        self.forwarded = saved_fwd;
        self.pending_config = saved_config;
        self.pending_config_id = saved_config_id;
        self.consumed_config = saved_consumed;
        self.current_selector = saved_selector;
        self.current_module = saved_module;
        self.current_file_dir = saved_dir;
        self.current_canonical = saved_canonical;
        self.current_url = saved_url;
        self.current_url_stamp = 0;
        self.current_source = saved_source;

        if (failed != null) {
            throw failed;
        }
        let _ = pos;

        // Merge `@forward`ed members (lower precedence than the module's own).
        // A member the module did NOT shadow keeps its origin binding, so
        // reads/writes/calls route to the defining module.
        let var_origins: map<string, root.std.Tuple2<root.eval.Module, string>> = {};
        let fn_origins: map<string, root.eval.Module> = {};
        let mixin_origins: map<string, root.eval.Module> = {};
        // Assignments write through to the forwarded module even when the
        // module's own same-named variable shadows it for reads.
        let var_write_origins: map<string, root.std.Tuple2<root.eval.Module, string>> = {};
        for (let k in forwarded.var_origins.keys()) {
            let mo = forwarded.var_origins[k];
            let _ = var_write_origins.set(k, root.std.Tuple2 { _0: mo._0, _1: mo._1 });
        }
        {
            let vars = vars_scope;
            let spans = var_spans_scope;
            for (let k in forwarded.vars.keys()) {
                let v = forwarded.vars[k];
                // PORT: `if let Entry::Vacant(e) = vars.entry(k)` → `!vars.has(k)`.
                if (!vars.has(k)) {
                    let _ = vars.set(k, v);
                    // Carry the forwarded definition span alongside the value.
                    let sp = forwarded.var_spans.get(k);
                    if (sp != null) {
                        let _ = spans.set(k, sp);
                    }
                    let o = forwarded.var_origins.get(k);
                    if (o != null) {
                        let _ = var_origins.set(k, root.std.Tuple2 { _0: o._0, _1: o._1 });
                    }
                }
            }
        }
        {
            let fns = functions;
            for (let k in forwarded.functions.keys()) {
                let v = forwarded.functions[k];
                if (!fns.has(k)) {
                    let _ = fns.set(k, v);
                    let o = forwarded.fn_origins.get(k);
                    if (o != null) {
                        let _ = fn_origins.set(k, o);
                    }
                }
            }
        }
        {
            let mxs = mixins;
            for (let k in forwarded.mixins.keys()) {
                let v = forwarded.mixins[k];
                if (!mxs.has(k)) {
                    let _ = mxs.set(k, v);
                    let o = forwarded.mixin_origins.get(k);
                    if (o != null) {
                        let _ = mixin_origins.set(k, o);
                    }
                }
            }
        }

        root.std.Tuple2 {
            _0: root.eval.Module {
                vars: vars_scope,
                var_spans: var_spans_scope,
                functions: functions,
                mixins: mixins,
                used_user_modules: used_user_modules,
                star_user_modules: star_user_modules,
                used_builtin_modules: used_builtin_modules,
                star_builtin_modules: star_builtin_modules,
                forwarded_builtins: forwarded.builtins,
                var_origins: var_origins,
                var_write_origins: var_write_origins,
                fn_origins: fn_origins,
                mixin_origins: mixin_origins,
                config_origin: self.pending_config_id,
                emitted_main: false,
                css: [],
                _id: root.std.fresh_id(),
            },
            _1: consumed,
        }
    }

    /// Process a `@forward "<url>" [as p-*] [show ..|hide ..] [with (..)];`:
    /// load the target module (emitting its CSS), then re-export its public
    /// members from the module currently being evaluated, applying prefix and
    /// show/hide filters.
    function exec_forward(self, url: string, prefix: string?, show: root.ast.ForwardMember[]?, hide: root.ast.ForwardMember[]?, config: root.ast.ConfigEntry[], pos: root.scanner.Pos, parents: string[], sink: root.std.Cell<root.eval.Sink>) -> void {
        // `@forward "sass:<mod>"` re-exports a built-in module. Built-ins can't
        // be configured.
        let m = root.std.strip_prefix(url, "sass:");
        if (m != null) {
            if (!root.builtins.is_module(m)) {
                throw root.error.Error.at("Can't find stylesheet to import.", pos);
            }
            if (config.length() != 0) {
                throw root.error.Error.at(
                    "Built-in modules can't be configured.",
                    pos,
                );
            }
            self.forwarded.builtins.push(root.eval.ForwardedBuiltin {
                module: m,
                // The prefix is stored canonically, like the `show`/`hide`
                // names: `@forward "sass:map" as p_*` answers to `p-get`.
                filters: [root.eval.ForwardFilter {
                    prefix: if (prefix != null) { prefix.replace_all("_", "-") } else { "" },
                    has_show: show != null,
                    show: root.eval.member_set(show, false),
                    hide: root.eval.member_set(hide, false),
                    show_vars: root.eval.member_set(show, true),
                    hide_vars: root.eval.member_set(hide, true),
                }],
            });
            return;
        }

        // Build the configuration passed to the forwarded module. The forward's
        // own `with (...)` entries combine with the configuration of the module
        // currently being evaluated (`pending_config`): a non-`!default` forward
        // entry hard-overrides; a `!default` forward entry yields to a matching
        // downstream override; downstream entries for variables the forward
        // re-exports (visible and matching its `as` prefix) flow through.
        let forward_conf = self.eval_config(config);
        let downstream = root.std.clone_map(self.pending_config);
        // Only downstream config for variables this forward actually re-exports
        // flows through. A `show`/`hide` filter or an `as p-*` prefix that hides
        // a variable also makes it unconfigurable through this forward. The map
        // value tracks (upstream-name, downstream-name) so consumption maps back.
        let var_visible = root.eval.forward_var_visibility(show, hide);
        let pfx_opt = prefix;
        let passthrough: map<string, root.std.Tuple2<root.value.Value, bool>> = {};
        // upstream config key -> downstream key it came from.
        let passthrough_origin: map<string, string> = {};
        for (let dk in downstream.keys()) {
            let dv = downstream[dk];
            // Map a downstream (prefixed) name back to the upstream member name.
            let upstream_name = if (pfx_opt != null) {
                let rest = root.std.strip_prefix(dk, pfx_opt);
                if (rest == null) {
                    continue;
                }
                rest
            } else {
                dk
            };
            if (root.eval.is_private_member(upstream_name) || !var_visible(upstream_name)) {
                continue;
            }
            let _ = passthrough.set(upstream_name, dv);
            let _ = passthrough_origin.set(upstream_name, dk);
        }
        let combined: map<string, root.std.Tuple2<root.value.Value, bool>> = root.std.clone_map(passthrough);
        // Keys whose downstream entry a `!default` forward override consumed.
        let forward_claimed: string[] = [];
        // The forward's own (non-passthrough) keys, which the forwarded module
        // must consume (else configuring a non-`!default` variable -> error).
        let forward_own: string[] = [];
        // Keys (upstream-side) a non-`!default` forward entry hard-overrode.
        let forward_shadowed: string[] = [];
        for (let name in forward_conf.keys()) {
            let entry = forward_conf[name];
            let val = entry._0;
            let is_default = entry._1;
            if (is_default) {
                // A downstream override wins over a `!default` forward entry —
                // but a `null` downstream value counts as "not configured", so
                // the forward default still applies.
                let pt = passthrough.get(name);
                let downstream_overrides = if (pt != null) {
                    !(pt._0 is root.value.Value_Null)
                } else {
                    false
                };
                if (downstream_overrides) {
                    forward_claimed.push(name);
                } else {
                    let _ = combined.set(name, root.std.Tuple2 { _0: val, _1: false });
                    forward_own.push(name);
                }
            } else {
                if (passthrough.has(name)) {
                    forward_shadowed.push(name);
                }
                let _ = combined.set(name, root.std.Tuple2 { _0: val, _1: false });
                forward_own.push(name);
            }
        }

        // A forward with its own `with (...)` entries makes the configuration
        // explicit (already-loaded then errors); pure passthrough keeps the
        // caller's implicit/explicit status.
        let saved_implicit = self.config_is_implicit;
        if (forward_conf.length() != 0) {
            self.config_is_implicit = false;
        }
        // A pure passthrough keeps the original configuration identity; a
        // forward with its own `with (...)` starts a new one.
        let combined_id = if (forward_conf.length() == 0) {
            self.pending_config_id
        } else {
            self.fresh_config_id()
        };
        // Diagnostic `@forward` frame — see the matching `@use` wrap in
        // `exec_use`.
        let saved_member = self.enter_call(pos, 0, "@forward");
        // PORT: `let load_result = …; <restores>; load_result?` → the `Err`
        // path runs the restores in the catch arm before rethrowing.
        let load_result = self.load_module(url, combined, combined_id, pos, parents, false, sink) catch (e) {
            let err: root.error.Error => {
                self.leave_call(saved_member);
                self.config_is_implicit = saved_implicit;
                throw err;
            }
        };
        self.leave_call(saved_member);
        self.config_is_implicit = saved_implicit;
        let module = load_result._0;
        let consumed = load_result._1;

        // A non-passthrough forward entry the module never consumed configured a
        // variable that isn't `!default` in the forwarded module.
        if (forward_own.some((k) -> { !consumed.includes(k) })) {
            throw root.error.Error.at(
                "This variable was not declared with !default in the @used module.",
                pos,
            );
        }
        // Mark the downstream config keys this forward consumed (passthrough +
        // `!default`-claimed) as consumed in the enclosing module, so they are
        // not reported as unused. A key a non-`!default` forward entry shadowed
        // stays unconsumed (the downstream override is then an error). The
        // consumed keys are upstream-side; map them back to downstream names.
        for (let up in consumed.concat(forward_claimed)) {
            if (forward_shadowed.includes(up)) {
                continue;
            }
            let dk = passthrough_origin.get(up);
            if (dk != null) {
                if (!self.consumed_config.includes(dk)) {
                    self.consumed_config.push(dk);
                }
            }
        }

        let show_vars = root.eval.member_set(show, true);
        let show_names = root.eval.member_set(show, false);
        let hide_vars = root.eval.member_set(hide, true);
        let hide_names = root.eval.member_set(hide, false);
        let has_show = show != null;

        // `show`/`hide` names are dash/underscore-insensitive, so compare the
        // canonical (dashed) form.
        let visible_var = (name: string) -> bool {
            if (root.eval.is_private_member(name)) {
                return false;
            }
            let n = root.eval.normalize_var_name(name);
            if (has_show) {
                show_vars?.has(n) ?? false
            } else {
                !(hide_vars?.has(n) ?? false)
            }
        };
        let visible_name = (name: string) -> bool {
            if (root.eval.is_private_member(name)) {
                return false;
            }
            let n = root.eval.normalize_var_name(name);
            if (has_show) {
                show_names?.has(n) ?? false
            } else {
                !(hide_names?.has(n) ?? false)
            }
        };

        // Two `@forward`s that bring the same member name from DIFFERENT modules
        // conflict — an error reported immediately, even when the member is
        // never used. Re-forwarding the SAME module is idempotent.
        // With a prefix, `show`/`hide` names match the PREFIXED member name.
        // Private members (by their ORIGINAL name) are never re-exported.
        // PORT: `Rc::as_ptr` identity → the module's `_id`.
        let src = module._id;
        let pfx = prefix ?? "";
        let module_vars: root.std.Tuple2<string, root.value.Value>[] = module.vars
            .keys()
            .map((k) -> { root.std.Tuple2 { _0: k, _1: module.vars[k] } });
        for (let nv in module_vars) {
            let name = nv._0;
            let val = nv._1;
            let key = `${pfx}${name}`;
            if (!root.eval.is_private_member(name) && visible_var(key)) {
                // The member's true home: follow the module's own origin
                // entry (a re-forward stays bound to the defining module).
                let origin = module.var_origin(name) ?? root.std.Tuple2 { _0: module, _1: name };
                // Conflict identity is that home module, so two forwards that
                // both re-export the SAME upstream member don't collide
                // (distributed configuration trees).
                let member_src = origin._0._id;
                let prev = self.forwarded.var_src.get(key);
                if (prev != null) {
                    if (prev != member_src) {
                        throw root.error.Error.at(
                            "Two forwarded modules both define a variable named $" + key + ".",
                            pos,
                        );
                    }
                }
                let _ = self.forwarded.vars.set(key, val);
                let sp = module.var_spans.get(name);
                if (sp != null) {
                    let _ = self.forwarded.var_spans.set(key, sp);
                }
                let _ = self.forwarded.var_origins.set(key, origin);
                let _ = self.forwarded.var_src.set(key, member_src);
            }
        }
        for (let name in module.functions.keys()) {
            let f = module.functions[name];
            let key = `${pfx}${name}`;
            if (!root.eval.is_private_member(name) && visible_name(key)) {
                let fo = module.fn_origin(name);
                let f_src = if (fo != null) { fo._id } else { src };
                let prev = self.forwarded.fn_src.get(key);
                if (prev != null) {
                    if (prev != f_src) {
                        throw root.error.Error.at(
                            `Two forwarded modules both define a function named ${key}.`,
                            pos,
                        );
                    }
                }
                let origin = module.fn_origin(name) ?? module;
                let _ = self.forwarded.functions.set(key, f);
                let _ = self.forwarded.fn_origins.set(key, origin);
                let _ = self.forwarded.fn_src.set(key, f_src);
            }
        }
        for (let name in module.mixins.keys()) {
            let mx = module.mixins[name];
            let key = `${pfx}${name}`;
            if (!root.eval.is_private_member(name) && visible_name(key)) {
                let mo = module.mixin_origin(name);
                let m_src = if (mo != null) { mo._id } else { src };
                let prev = self.forwarded.mixin_src.get(key);
                if (prev != null) {
                    if (prev != m_src) {
                        throw root.error.Error.at(
                            `Two forwarded modules both define a mixin named ${key}.`,
                            pos,
                        );
                    }
                }
                let origin = module.mixin_origin(name) ?? module;
                let _ = self.forwarded.mixins.set(key, mx);
                let _ = self.forwarded.mixin_origins.set(key, origin);
                let _ = self.forwarded.mixin_src.set(key, m_src);
            }
        }
        // A built-in this module re-exports is re-exported again: its members
        // are as public here as the module's own. Each inner filter is re-based
        // under this forward's prefix and this forward's own `show`/`hide` is
        // appended, so a member has to survive every rule it passed through.
        let outer_prefix = pfx.replace_all("_", "-");
        for (let fb in module.forwarded_builtins) {
            let filters = root.std.clone_vec(fb.filters);
            // Each existing filter keeps the prefix it was DECLARED under — an
            // inner `show p-get` names `p-get`, whatever the outer rule renames
            // it to. Only the filter this `@forward` adds sees the full name.
            filters.push(root.eval.ForwardFilter {
                prefix: `${outer_prefix}${fb.prefix()}`,
                has_show: has_show,
                show: show_names,
                hide: hide_names,
                show_vars: show_vars,
                hide_vars: hide_vars,
            });
            self.forwarded.builtins.push(root.eval.ForwardedBuiltin {
                module: fb.module,
                filters: filters,
            });
        }
    }

    /// Enter the file a callable or content block was written in, for the
    /// duration of its body (dart evaluates a mixin, function, or `@content`
    /// block where it was written: its output maps to that file, and its
    /// diagnostics show that file's name and source). Returns `None` — and
    /// swaps nothing — when the body is in the current file already, so a
    /// same-file call costs a string comparison; pass the result to
    /// [`Self::leave_module_file`].
    function enter_origin_file(self, origin: root.value.MixinOrigin?) -> SavedModuleFile? {
        if (origin == null) {
            return null;
        }
        let o = origin;
        if (o.diag_url == self.current_url && o.canonical == self.current_path()) {
            return null;
        }
        // The source comes from the origin ITSELF (see `MixinOrigin::source`):
        // a display url is a name two files can share, never an identity.
        let dir: string? = if (o.file_dir != "") { o.file_dir } else { null };
        self.current_url_stamp = 0;
        // PORT: the tuple's `mem::replace`/`Option::replace` fields → read, then
        // assign, in field order.
        let saved_url = self.current_url;
        self.current_url = o.diag_url;
        let saved_source = self.current_source;
        self.current_source = o.source;
        let saved_dir = self.current_file_dir;
        self.current_file_dir = dir;
        let saved_canonical = self.current_canonical;
        self.current_canonical = root.importer.CanonicalUrl.new(o.canonical);
        root.std.Tuple4 {
            _0: saved_url,
            _1: saved_source,
            _2: saved_dir,
            _3: saved_canonical,
        }
    }

    /// Snapshot the current file context as a [`crate::value::MixinOrigin`]:
    /// the defining file of a callable being captured, or of a content block
    /// at its `@include` (so a later `meta.apply` from another file still
    /// resolves its relative loads here). There is always a context to
    /// snapshot — an entry compiled without `Options::url` has an empty
    /// display url and canonical, and a callable it defines must still switch
    /// back to it (so its diagnostics report the entry's empty `url`/`path`)
    /// when invoked from inside a loaded file.
    function current_mixin_origin(self) -> root.value.MixinOrigin {
        let canonical = self.current_canonical;
        root.value.MixinOrigin {
            source: self.current_source,
            diag_url: self.current_url,
            file_dir: self.current_file_dir ?? "",
            canonical: if (canonical != null) { canonical.as_str() } else { "" },
        }
    }

    /// Restore the file swapped out by [`Self::enter_origin_file`].
    function leave_module_file(self, saved: SavedModuleFile?) -> void {
        if (saved != null) {
            self.current_url = saved._0;
            self.current_url_stamp = 0;
            self.current_source = saved._1;
            self.current_file_dir = saved._2;
            self.current_canonical = saved._3;
        }
    }

    /// The diagnostic display URL for a `@use`/`@import`ed module, as dart-sass
    /// spells it in stack frames. A filesystem path — the `FsImporter`'s
    /// canonical key is the resolved absolute path — is shown relative to the
    /// current directory (`src/sub/_partial.scss`, whether it was reached
    /// relatively or through a load path), unless that spelling has more
    /// segments than the absolute path, which is then shown as is (dart's
    /// `p.prettyUri`). Any other canonical URL (a custom importer's key) shows
    /// its last segment, falling back to the `@use` url when the key has none.
    function module_diag_url(self, url: string, key: string) -> string {
        // `pretty_name` answers only for a key that names a file absolutely —
        // a path or a `file://` URL. A custom importer's key is neither, and
        // `virtual/foo.scss` must keep showing as `foo.scss` rather than
        // whole.
        let named = self.pretty_name(key);
        if (named != null) {
            return named;
        }
        // PORT: `key.rsplit(['/', '\\']).next()` is the text after the last
        // separator (all of `key` when it has none).
        let sep = root.std.rfind_by(key, (c) -> { c == "/" || c == "\\" });
        let base = if (sep != null) { key.slice(sep + 1, key.length()) } else { key };
        if (base == "") {
            url
        } else {
            base
        }
    }

    /// How a stack frame names `key`, when `key` names a file at all.
    ///
    /// A path and a `file://` URL are two spellings the two front ends
    /// arrive with — the binary passes paths, the JS API passes URLs because
    /// its importer bridge resolves relative `@use` against them — and both
    /// must produce the frame dart produces. `None` is "not a file": a
    /// `data:` URL, or a custom importer's key, which keep their own rule.
    function pretty_name(self, key: string) -> string? {
        // PORT: `OnceCell::get_or_init` → `null` is the uninitialized cell.
        let cell = self.cwd_cache;
        let cwd: string? = if (cell != null) {
            cell.value
        } else {
            let init: string? = match (self.options.cwd) {
                let c: string => c,
                null => root.std.current_dir() catch (e) {
                    let _io: baml.errors.Io => null
                },
            };
            self.cwd_cache = root.std.Some { value: init };
            init
        };
        // The style the DATA is in, not the one this build was compiled for:
        // the wasm module is always `Posix` by that measure and still has to
        // read `C:\work` on Windows node. See `pathstyle::style_for`.
        root.pathstyle.pretty_name(root.pathstyle.style_for(cwd, key), key, cwd)
    }

    /// Install `module`'s environment for a cross-module member invocation,
    /// returning the previous environment to restore with [`leave_module`].
    function enter_module(self, module: root.eval.Module) -> root.eval.SavedModuleEnv {
        // The module's global scope is SHARED (the same Rc its callables
        // captured), so writes inside the module are immediately visible to
        // its closures and to later cross-module reads.
        let module_scope = module.vars;
        let module_spans: root.eval.SpanScope[] = if (self.options.source_map) {
            [module.var_spans]
        } else {
            []
        };
        // PORT: each `std::mem::replace` field → read, then assign, in field
        // order; the module's tables are `.clone()`d (shallow copies).
        let scopes = self.scopes;
        self.scopes = [module_scope];
        let var_spans = self.var_spans;
        self.var_spans = module_spans;
        let scope_semi_global = self.scope_semi_global;
        self.scope_semi_global = [true];
        let functions = self.functions;
        self.functions = [module.functions];
        let mixins = self.mixins;
        self.mixins = [module.mixins];
        let used_modules = self.used_modules;
        self.used_modules = root.std.clone_map(module.used_builtin_modules);
        let star_modules = self.star_modules;
        self.star_modules = root.std.clone_vec(module.star_builtin_modules);
        let used_user_modules = self.used_user_modules;
        self.used_user_modules = root.std.clone_map(module.used_user_modules);
        let star_user_modules = self.star_user_modules;
        self.star_user_modules = root.std.clone_vec(module.star_user_modules);
        root.eval.SavedModuleEnv {
            scopes: scopes,
            var_spans: var_spans,
            scope_semi_global: scope_semi_global,
            functions: functions,
            mixins: mixins,
            used_modules: used_modules,
            star_modules: star_modules,
            used_user_modules: used_user_modules,
            star_user_modules: star_user_modules,
            write_back: module,
        }
    }

    /// Restore the environment captured by [`enter_module`]. If the saved env
    /// recorded a module, its (possibly mutated) global scope is written back so
    /// a `!global` assignment inside the module persists.
    function leave_module(self, saved: root.eval.SavedModuleEnv) -> void {
        // The module scope is shared by Rc; writes already land in
        // module.vars without an explicit copy-back.
        let _ = saved.write_back;
        self.scopes = saved.scopes;
        self.scope_semi_global = saved.scope_semi_global;
        self.functions = saved.functions;
        self.mixins = saved.mixins;
        self.used_modules = saved.used_modules;
        self.star_modules = saved.star_modules;
        self.used_user_modules = saved.used_user_modules;
        self.star_user_modules = saved.star_user_modules;
    }

    /// Resolve a namespaced module variable `ns.$name`. Resolves a user module
    /// first, then a built-in module bound to `ns`.
    function eval_module_var(self, ns: string, name: string, pos: root.scanner.Pos) -> root.value.Value {
        let module = self.used_user_modules.get(ns);
        if (module != null) {
            if (root.eval.is_private_member(name)) {
                // Not part of the module's public view: dart reports it missing
                // (a literal `ns.-name` is the parser's privacy error instead).
                throw root.error.Error.at("Undefined variable.", pos);
            }
            let v = module.var(name);
            if (v != null) {
                return v.without_slash();
            }
            // A built-in this module re-exports brings its variables along
            // (`@forward "sass:math"` re-exports `$pi`).
            let fwd = root.eval.meta.resolve_forwarded_builtin_var(module, name);
            if (fwd != null) {
                let owner = fwd._0;
                let bare = fwd._1;
                return root.builtins.module_var(owner, bare, pos);
            }
            throw root.error.Error.at("Undefined variable.", pos);
        }
        match (self.used_modules.get(ns)) {
            let module: string => root.builtins.module_var(module, name, pos),
            null => {
                throw root.error.Error.at(
                    `There is no module with the namespace "${ns}".`,
                    pos,
                );
            }
        }
    }

}

/// `push_run` (nested in [`Evaluator::load_module`]): put a popped comment run
/// back at the end of a top-level sink.
function load_module__push_run(
    sink: root.std.Cell<root.eval.Sink>,
    run: root.eval.OutNode[],
) -> void {
    if let out: root.eval.Sink_Top = sink.value {
        root.std.extend(out._0, run);
    }
}

/// dart `meta.load-css` re-visits the combined css node-by-node
/// (`_combineCss(module, clone: true).accept(this)`), so each re-visited
/// top-level STYLE RULE re-acquires `isGroupEnd` and the next visible node
/// blank-separates — regardless of how the rules were grouped in the source
/// module. Rebuild the copy's separators to that rule: drop the cloned
/// grouping (blanks + sentinels), walk through module-scope wrappers, leave
/// at-rule bodies untouched (their children keep their own separators).
function regroup_load_css_copy(
    nodes: root.eval.OutNode[],
    prev_rule: root.std.Cell<bool>,
) -> root.eval.OutNode[] {
    let out: root.eval.OutNode[] = [];
    for (let n in nodes) {
        match (n) {
            root.eval.OutNode_Blank {}
                | root.eval.OutNode_GroupEnd {}
                | root.eval.OutNode_AtRootPackTight {} =>
            {},
            let ms: root.eval.OutNode_ModuleScope => {
                let inner = regroup_load_css_copy(ms.nodes, prev_rule);
                out.push(root.eval.OutNode_ModuleScope { key: ms.key, nodes: inner });
            },
            let other => {
                if (prev_rule.get()) {
                    out.push(root.eval.OutNode_Blank {  });
                }
                prev_rule.set(other is root.eval.OutNode_Rule);
                out.push(other);
            },
        }
    }
    out
}
