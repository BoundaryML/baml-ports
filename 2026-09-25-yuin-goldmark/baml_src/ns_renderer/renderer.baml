// Port of goldmark renderer/renderer.go.
//
// Package renderer renders the given AST to certain formats.
//
// Porting notes:
// - Go's renderer types are generic over the writer type `W` and the format
//   config type `C`. This port keeps `C` generic but fixes `W` to
//   `root.util.BufWriter` (Go's HTML renderer always wraps its `io.Writer` in a
//   `util.BufWriter` anyway); BAML has no `io.Writer`.
// - Go finds the embedded `renderer.Config[W, C]` inside a format config with
//   reflection (`getConfig`). Here format configs implement `FormatConfig`,
//   which exposes that embedded Config.
// - Go's `Default() C` type-assertion trick becomes an explicit default config
//   passed to `HelperBuilder`.
// - Render errors: goldmark's in-memory writers never fail, and BAML's
//   BufWriter has no error channel, so render functions return no error.
// - `ContextKey` values are strings (no package-level counters).

/// ContextKey is a key that is used to set arbitrary values to the context.
type ContextKey = string

/// NewContextKey return a new ContextKey value (the caller supplies a unique name).
function new_context_key(name: string) -> ContextKey {
    name
}

/// RenderFunc renders a node (Go: `func(any, []byte, ast.Node, Context) error`).
type RenderFunc = (w: root.util.BufWriter, source: uint8array, n: root.ast.Node, rc: Context) -> void throws never

/// Context is a context for rendering.
interface Context {
    /// Get returns a value associated with the given key.
    function get(self, key: ContextKey) -> unknown throws never

    /// ComputeIfAbsent computes a value if a value associated with the given key is absent and returns the value.
    function compute_if_absent(self, key: ContextKey, f: () -> unknown throws never) -> unknown throws never

    /// Set sets the given value to the context.
    function set(self, key: ContextKey, value: unknown) -> void throws never

    /// Render renders the given node using the renderer associated with this context.
    function render(self, w: root.util.BufWriter, source: uint8array, n: root.ast.Node) -> void throws never

    /// Clone returns a copy of this context.
    function clone(self) -> Context throws never
}

/// ContextOption is a functional option for NewContext.
type ContextOption = (c: RenderContext) -> void throws never

/// WithRenderFunc sets the render function of a context.
function with_render_func(f: RenderFunc) -> ContextOption {
    (c: RenderContext) -> void {
        c.render_func = f;
    }
}

/// Go's unexported `renderContext`.
class RenderContext {
    store: map<string, unknown>,
    render_func: RenderFunc?,

    /// SetRenderFunc sets the render function.
    function set_render_func(self, f: RenderFunc) -> void {
        self.render_func = f;
    }

    implements Context {
        function get(self, key: ContextKey) -> unknown {
            self.store.get(key)
        }

        function compute_if_absent(self, key: ContextKey, f: () -> unknown throws never) -> unknown {
            let v = self.store.get(key);
            if (v == null) {
                let nv = f();
                self.store[key] = nv;
                return nv;
            }
            v
        }

        function set(self, key: ContextKey, value: unknown) -> void {
            self.store[key] = value;
        }

        function render(self, w: root.util.BufWriter, source: uint8array, n: root.ast.Node) -> void {
            let f = self.render_func;
            if (f != null) {
                f(w, source, n, self);
            }
        }

        function clone(self) -> Context {
            let store: map<string, unknown> = {};
            for (let k in self.store.keys()) {
                store[k] = self.store[k];
            }
            RenderContext { store: store, render_func: self.render_func }
        }
    }
}

/// NewContext returns a new Context.
function new_context(opts: ContextOption[] = []) -> RenderContext {
    let c = RenderContext { store: {}, render_func: null };
    for (let opt in opts) {
        opt(c);
    }
    c
}

/// Renderer is an interface for renderers.
interface Renderer {
    /// Render renders the given AST node to the given writer with the given Renderer.
    function render(self, w: root.util.BufWriter, source: uint8array, n: root.ast.Node, opts: RenderOption[]) -> void throws never

    /// RenderStringSource renders the given AST node to the given writer with the given Renderer.
    function render_string_source(self, w: root.util.BufWriter, source: string, n: root.ast.Node, opts: RenderOption[]) -> void throws never
}

/// NodeRenderer interface renders a given node.
interface NodeRenderer {
    /// Render renders the given node.
    function render(self, w: root.util.BufWriter, source: uint8array, n: root.ast.Node, entering: bool, rc: Context) -> root.ast.WalkStatus throws never
}

/// The function type adapted by NodeRendererFunc.
type NodeRendererFuncType = (w: root.util.BufWriter, source: uint8array, n: root.ast.Node, entering: bool, rc: Context) -> root.ast.WalkStatus throws never

/// Go's unexported `nodeRendererFunc`.
class NodeRendererFuncImpl {
    f: NodeRendererFuncType,

    implements NodeRenderer {
        function render(self, w: root.util.BufWriter, source: uint8array, n: root.ast.Node, entering: bool, rc: Context) -> root.ast.WalkStatus {
            let f = self.f;
            f(w, source, n, entering, rc)
        }
    }
}

/// NodeRendererFunc adapts f into a NodeRenderer.
function node_renderer_func(f: NodeRendererFuncType) -> NodeRenderer {
    NodeRendererFuncImpl { f: f }
}

/// NodeRendererDecorator is a function that decorates a NodeRenderer.
type NodeRendererDecorator = (next: NodeRenderer) -> NodeRenderer throws never

/// Config is a configuration for renderers (embedded in format configs).
class Config {
    node_renderers: map<string, NodeRenderer>?,
    node_renderer_decorators: map<string, NodeRendererDecorator>?,
    extensions: unknown[],

    function copy(self) -> Config {
        Config {
            node_renderers: self.node_renderers,
            node_renderer_decorators: self.node_renderer_decorators,
            extensions: self.extensions,
        }
    }
}

function new_config() -> Config {
    Config { node_renderers: null, node_renderer_decorators: null, extensions: [] }
}

/// A format config that embeds a renderer Config (Go: struct embedding found
/// through reflection by `getConfig`).
interface FormatConfig {
    function renderer_config(self) -> Config throws never
}

/// Option is an option for renderers (Go: `Option[C]`).
interface Option<C> {
    function set_format_option(self, c: C) -> void throws never
}

/// Go's unexported `optionFunc[C]`.
class OptionFunc<C> {
    f: (c: C) -> void throws never,

    implements Option<C> {
        function set_format_option(self, c: C) -> void {
            let f = self.f;
            f(c);
        }
    }
}

/// NewOptionFunc returns a new Option that calls the given function.
function new_option_func<C>(f: (c: C) -> void throws never) -> Option<C> {
    OptionFunc<C> { f: f }
}

/// WithNodeRenderers sets node renderers for the given node kinds.
function with_node_renderers<C extends FormatConfig>(node_renderers: map<string, NodeRenderer>) -> Option<C> {
    new_option_func<C>((c: C) -> void {
        let cfg = c.renderer_config();
        let nrs = cfg.node_renderers ?? {};
        for (let k in node_renderers.keys()) {
            nrs[k] = node_renderers[k];
        }
        cfg.node_renderers = nrs;
    })
}

/// WithNodeRenderer sets a node renderer for the given node kind.
function with_node_renderer<C extends FormatConfig>(kind: root.ast.NodeKind, node_renderer: NodeRenderer) -> Option<C> {
    new_option_func<C>((c: C) -> void {
        let cfg = c.renderer_config();
        let nrs = cfg.node_renderers ?? {};
        nrs[kind] = node_renderer;
        cfg.node_renderers = nrs;
    })
}

function compose_decorators(decorator: NodeRendererDecorator, existing: NodeRendererDecorator) -> NodeRendererDecorator {
    (next: NodeRenderer) -> NodeRenderer {
        decorator(existing(next))
    }
}

/// WithNodeRendererDecorators sets node renderer decorators for the given node kinds.
///
/// If a decorator is already set for a node kind, the new decorator will be applied to the existing one.
function with_node_renderer_decorators<C extends FormatConfig>(decorators: map<string, NodeRendererDecorator>) -> Option<C> {
    new_option_func<C>((c: C) -> void {
        let cfg = c.renderer_config();
        let decs = cfg.node_renderer_decorators ?? {};
        for (let kind in decorators.keys()) {
            let decorator = decorators[kind];
            let existing = decs.get(kind);
            if (existing != null) {
                decs[kind] = compose_decorators(decorator, existing);
            } else {
                decs[kind] = decorator;
            }
        }
        cfg.node_renderer_decorators = decs;
    })
}

/// WithNodeRendererDecorator sets a node renderer decorator for the given node kind.
///
/// If a decorator is already set for a node kind, the new decorator will be applied to the existing one.
function with_node_renderer_decorator<C extends FormatConfig>(kind: root.ast.NodeKind, decorator: NodeRendererDecorator) -> Option<C> {
    new_option_func<C>((c: C) -> void {
        let cfg = c.renderer_config();
        let decs = cfg.node_renderer_decorators ?? {};
        let existing = decs.get(kind);
        if (existing != null) {
            decs[kind] = compose_decorators(decorator, existing);
        } else {
            decs[kind] = decorator;
        }
        cfg.node_renderer_decorators = decs;
    })
}

/// WithExtensions adds extensions (Go: `Extension[C]`; stored untyped in the
/// non-generic Config and recovered by `Helper.render`).
function with_extensions<C extends FormatConfig>(ext: Extension<C>[]) -> Option<C> {
    new_option_func<C>((c: C) -> void {
        let cfg = c.renderer_config();
        for (let e in ext) {
            cfg.extensions.push(e);
        }
    })
}

/// OnBeforeRender callback type.
type BeforeRenderFunc = (w: root.util.BufWriter, source: uint8array, n: root.ast.Node, rc: Context) -> void throws never

/// HelperBuilder is a builder for Helper.
class HelperBuilder<C extends FormatConfig> {
    options: Option<C>[],
    on_before_render: BeforeRenderFunc?,
    default_config: C,

    /// Options adds options.
    function add_options(self, opts: Option<C>[]) -> HelperBuilder<C> {
        for (let o in opts) {
            self.options.push(o);
        }
        self
    }

    /// OnBeforeRender sets a function that is called before rendering.
    function set_on_before_render(self, f: BeforeRenderFunc) -> HelperBuilder<C> {
        self.on_before_render = f;
        self
    }

    /// Build returns a new Helper.
    function build(self) -> Helper<C> {
        let h = new_helper<C>(self.default_config, self.options);
        h.on_before_render = self.on_before_render;
        h
    }
}

/// Returns an empty HelperBuilder (Go: `var hb renderer.HelperBuilder[W, C]`),
/// given the format config's default value (Go: `C.Default()`).
function new_helper_builder<C extends FormatConfig>(default_config: C) -> HelperBuilder<C> {
    HelperBuilder<C> { options: [], on_before_render: null, default_config: default_config }
}

/// Helper is a helper for implementing renderers.
class Helper<C extends FormatConfig> {
    config: C,
    options: Option<C>[],
    node_renderers: map<string, NodeRenderer>,
    initialized: bool,
    on_before_render: BeforeRenderFunc?,

    /// Config returns the config of this helper.
    function get_config(self) -> C {
        self.config
    }

    function render_fn(self, w: root.util.BufWriter, source: uint8array, n: root.ast.Node, rc: Context) -> void {
        let nrs = self.node_renderers;
        root.ast.walk(n, (nd: root.ast.Node, entering: bool) -> root.ast.WalkStatus {
            let f = nrs.get(nd.kind());
            if (f != null) {
                return f.render(w, source, nd, entering, rc);
            }
            root.ast.WalkStatus.WalkContinue
        });
    }

    /// Go's `initSync.Do(...)` body.
    function init_once(self) -> void {
        if (self.initialized) {
            return;
        }
        self.initialized = true;
        for (let opt in self.options) {
            opt.set_format_option(self.config);
        }
        let cfg = self.config.renderer_config();
        // Go ranges over `cfg.extensions` once; extensions added while applying
        // extension options are not visited.
        let exts = cfg.extensions.slice(0, cfg.extensions.length());
        for (let ext in exts) {
            match (ext) {
                let e: Extension<C> => {
                    for (let opt in e.renderer_options(self.config)) {
                        opt.set_format_option(self.config);
                    }
                }
                _ => {}
            }
        }
        let nrs = cfg.node_renderers ?? {};
        let decs = cfg.node_renderer_decorators ?? {};
        for (let kind in nrs.keys()) {
            let nr = nrs[kind];
            let decorator = decs.get(kind);
            if (decorator != null) {
                self.node_renderers[kind] = decorator(nr);
            } else {
                self.node_renderers[kind] = nr;
            }
        }
    }

    /// Render renders the given node.
    function render(self, w: root.util.BufWriter, source: uint8array, n: root.ast.Node, opts: RenderOption[] = []) -> void {
        self.init_once();

        // BAML: assigning a bound method straight into a field crashes the
        // compiler (MakeBoundMethod in emit_rvalue_pull); bind it to a local.
        let rf: RenderFunc = self.render_fn;
        let rc: Context? = null;
        if (opts.length() != 0) {
            let rcfg = RenderConfig { context: null };
            for (let opt in opts) {
                opt.set_render_option(rcfg);
            }
            let ctx = rcfg.context;
            if (ctx != null) {
                match (ctx) {
                    let c: RenderContext => {
                        if (c.render_func == null) {
                            c.render_func = rf;
                        }
                    }
                    _ => {}
                }
                rc = ctx;
            }
        }
        let the_rc: Context = rc ?? new_context(opts = [with_render_func(rf)]);
        let obr = self.on_before_render;
        if (obr != null) {
            obr(w, source, n, the_rc);
        }
        self.render_fn(w, source, n, the_rc);
        w.flush();
    }

    /// RenderStringSource renders the given node from a string source.
    function render_string_source(self, w: root.util.BufWriter, source: string, n: root.ast.Node, opts: RenderOption[] = []) -> void {
        self.render(w, source.to_utf8(), n, opts = opts);
    }
}

function new_helper<C extends FormatConfig>(default_config: C, opts: Option<C>[]) -> Helper<C> {
    Helper<C> {
        options: opts,
        config: default_config,
        node_renderers: {},
        initialized: false,
        on_before_render: null,
    }
}

class RenderConfig {
    context: Context?,
}

/// RenderOption is an option for Render.
interface RenderOption {
    function set_render_option(self, c: RenderConfig) -> void throws never
}

class WithContextOption {
    context: Context,

    implements RenderOption {
        function set_render_option(self, c: RenderConfig) -> void {
            c.context = self.context;
        }
    }
}

/// WithContext is a RenderOption that sets the Context for rendering.
function with_context(context: Context) -> RenderOption {
    WithContextOption { context: context }
}

/// Extension is an interface that represents an extension for renderers.
interface Extension<C> {
    /// RendererOptions returns options for renderers.
    function renderer_options(self, c: C) -> Option<C>[] throws never
}
