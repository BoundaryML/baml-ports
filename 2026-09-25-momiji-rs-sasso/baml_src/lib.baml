// Ported from sasso `src/lib.rs` (namespace `root`).
//
// `sasso` — a pure-Rust SCSS → CSS compiler.
//
// A small, zero-dependency, embeddable Sass engine aiming at byte-exact
// parity with **current** dart-sass on the subset it implements (e.g.
// computed colors serialize as `rgb(25%, 50%, 75%)`, not rounded
// hex). It is sandbox-friendly: `@import` resolution goes through a
// caller-supplied [`Importer`], so an embedder controls all file access.
//
// # Example
//
// ```
// use sasso::{compile, Options};
//
// let css = compile("$c: #333; a { color: $c; &:hover { color: $c; } }", &Options::default()).unwrap();
// assert!(css.contains("a {"));
// assert!(css.contains("a:hover {"));
// ```
//
// ## Scope
//
// This covers a large slice of Sass: variables (`!default`/`!global`),
// nesting and the `&` parent selector, `#{}` interpolation, `//` and
// `/* */` comments, unit arithmetic, the color functions, control flow,
// mixins/functions, `@extend`, `@import`, and the `@use`/`@forward` module
// system. Both input syntaxes are supported — the brace/semicolon SCSS
// syntax and the indented `.sass` syntax (selected via [`Options::with_syntax`]
// or, in the CLI, the input file's extension) — parsing into the same AST and
// sharing the evaluator and emitter. The north-star target is 100% of the
// official `sass-spec` suite, tracked by the harness in `spec/`.

// The library's `unsafe` is confined to one audited module — `arena`, the
// scoped bump allocator (perf #5), verified by unit tests + Miri. Every other
// module is `deny(unsafe_code)` (see Cargo.toml `[lints]`); `arena` is the only
// `#[allow]`. The wasm wrapper (`/wasm`, a separate crate) has its own FFI unsafe.
// mod arena → namespace `root.arena`

// mod ast → namespace `root.ast`

// mod ast_writer → namespace `root.ast_writer`

// mod builtins → namespace `root.builtins`

// mod deprecation → namespace `root.deprecation`

// mod diag → namespace `root.diag`

// mod emit → namespace `root.emit`

// mod error → namespace `root.error`

// mod eval → namespace `root.eval`

// mod fxhash → namespace `root.fxhash`

// mod host_fn → namespace `root.host_fn`

// mod importer → namespace `root.importer`

// mod musl_math → namespace `root.musl_math`

// mod parser → namespace `root.parser`

// Path spelling by platform, as a value rather than a `#[cfg]`: the binary
// includes this same file (see `main.rs`) so both relativisations share one
// set of rules.
// mod pathstyle → namespace `root.pathstyle`

// mod ryu → namespace `root.ryu`

// mod sass_parser → namespace `root.sass_parser`

// mod scanner → namespace `root.scanner`

// mod selector → namespace `root.selector`

// Source Map v3 generation: the encoding primitives + JSON model (Phase A),
// wired into emit (Phase B/C) and surfaced through `compile_with_source_map`.
// mod sourcemap → namespace `root.sourcemap`

// mod value → namespace `root.value`

/// This compiler's version, as in `Cargo.toml`.
///
/// Exposed so a wrapper can report the version of the compiler it actually
/// bundles rather than its own: the FFI crate (`ffi/`) is versioned separately,
/// and its `sasso_version()` used to return `CARGO_PKG_VERSION`, i.e. the
/// wrapper's number. Reading it from here cannot drift.
function VERSION() -> string {
    // PORT: `env!("CARGO_PKG_VERSION")`, read from sasso's `Cargo.toml`.
    "0.18.0"
}

// PORT: `pub use arena::{set_arena_bytes, ScopedAlloc}`, `error::Error`,
// `host_fn::{host_value_op, HostFunction}`, `importer::{…}` and
// `sourcemap::SourceMap` re-exports — BAML has no re-exports; use the
// `root.arena.*`, `root.error.*`, `root.host_fn.*`, `root.importer.*` and
// `root.sourcemap.*` paths.

/// The local filesystem path a `file:` URL names, or `None` when it names
/// no local file.
///
/// Handles what every caller of such a thing has to: the `file://` prefix,
/// the empty authority and `localhost` (both mean this machine), percent
/// escapes, a Windows drive letter arriving as `/C:/`, and a UNC authority
/// that only Windows can spell.
///
/// STRICT about UTF-8 — `None` rather than replacement characters — because
/// a caller of this is about to open the path, and a name with U+FFFD
/// substituted into it is a different name. The lossy reading belongs to
/// whoever is about to PRINT the path, and lives beside it in `pathstyle`.
///
/// This exists because `napi/` had its own copy of the same rule and the
/// two had already drifted (#161, #163): its copy accepted a `localhost`
/// authority that this one declined, so a `file://localhost/…` entry was
/// read happily and then printed as a URL in the frame.
function file_url_to_path(url: string) -> string? {
    let bytes = root.pathstyle.file_url_bytes(root.pathstyle.HOST(), url);
    if (bytes == null) {
        return null;
    }
    string.from_utf8(bytes) catch (e) {
        baml.errors.InvalidArgument => null
    }
}

/// Output formatting style.
enum OutputStyle {
    /// Human-readable, indented output (the default).
    Expanded,
    /// Minified, single-line output.
    Compressed,
}

/// derive(Default): `OutputStyle::Expanded`.
function OutputStyle_default() -> OutputStyle {
    OutputStyle.Expanded
}

/// The input syntax flavour.
///
/// Both flavours parse into the same AST and share the evaluator and emitter;
/// only the *block structure* differs (`{}`/`;` for SCSS, indentation +
/// newlines for the indented `.sass` syntax).
enum Syntax {
    /// The brace/semicolon SCSS syntax (the default).
    Scss,
    /// The indented `.sass` syntax: blocks come from indentation, statements
    /// end at a newline.
    Sass,
    /// Plain CSS (a `.css` file loaded via `@use`/`@forward`): the brace/semicolon
    /// grammar, but Sass features are rejected, nesting is preserved verbatim,
    /// and values are emitted without SassScript evaluation.
    Css,
}

/// derive(Default): `Syntax::Scss`.
function Syntax_default() -> Syntax {
    Syntax.Scss
}

/// Compilation options.
class Options {
    /// Output style.
    style: OutputStyle,
    /// Input syntax (SCSS or indented `.sass`).
    syntax: Syntax,
    /// Importer used to resolve `@import`; `None` disables file imports.
    importer: root.importer.Importer?,
    /// The input's path/URL as it should appear in diagnostics (e.g.
    /// `input.scss`). `None` disables byte-exact diagnostic snippets (errors
    /// then render as the legacy `Error: <msg> (line:col)` one-liner).
    ///
    /// A `file://` URL is accepted and SHOWN as a path — the JS API passes
    /// one because its importer bridge resolves relative `@use` against it,
    /// and a frame reading `file:///Users/…/src/a.scss` names a file nobody
    /// can paste into an editor. See [`Options::cwd`] for what it is spelled
    /// relative to.
    url: string?,
    /// The directory diagnostic paths are spelled relative to, as dart's
    /// `p.prettyUri` does. `None` asks the operating system.
    ///
    /// It exists because one target cannot be asked: `wasm32-unknown-unknown`
    /// has no `getcwd`, so `std::env::current_dir()` there always fails and
    /// every frame kept an absolute path — or, for a `file://` key, only the
    /// file's own name. A host that knows better says so.
    cwd: string?,
    /// Whether to draw diagnostic snippets with Unicode box-drawing glyphs
    /// (`true`, the default) or the ASCII fallback (`false`, dart's
    /// `--no-unicode`).
    unicode: bool,
    /// Whether [`compile_with_source_map`] populates the source map's
    /// `sourcesContent` field with the full text of each source (dart-sass
    /// `--embed-sources`). Default `false` (the map references sources by URL
    /// only). Ignored by the plain [`compile`] path.
    source_map_include_sources: bool,
    /// Host-defined custom functions (dart-sass `functions`), registered via
    /// [`Options::with_function`]. Consulted after user `@function`s and module
    /// members but before built-in global functions.
    functions: root.host_fn.HostFn[],
    /// Diagnostic handler (dart-sass `logger`). When set, every `@warn`/`@debug`/
    /// deprecation warning is delivered here instead of printed to stderr.
    warn: WarnHandler?,
    /// dart-sass `quietDeps`: deprecation warnings raised inside a dependency
    /// (a file this set marks, see [`FsImporter::dependencies`]) are dropped
    /// before they are counted or delivered.
    quiet_deps: root.importer.DependencySet?,
    /// dart-sass `silenceDeprecations`: deprecation ids dropped before they
    /// are counted or delivered. Empty means every deprecation is emitted.
    silenced_deprecations: string[],
    /// Emit a `@charset "UTF-8";` (expanded) / U+FEFF BOM (compressed) prefix
    /// when the output contains non-ASCII (dart-sass `charset`, default `true`).
    /// `false` suppresses it.
    charset: bool,

    /// `impl Default for Options`.
    function default() -> Options {
        Options {
            style: OutputStyle_default(),
            syntax: Syntax_default(),
            importer: null,
            url: null,
            cwd: null,
            unicode: true,
            source_map_include_sources: false,
            functions: [],
            warn: null,
            quiet_deps: null,
            silenced_deprecations: [],
            charset: true,
        }
    }

    // PORT: the builders take `self` by value in Rust (the caller's options are
    // moved in), so they set the field on `self` in place and return it.

    /// Create default options (expanded, SCSS, no importer).
    function new() -> Options {
        Options.default()
    }

    /// Builder: set the output style.
    function with_style(self, style: OutputStyle) -> Options {
        self.style = style;
        self
    }

    /// Builder: set the input syntax.
    function with_syntax(self, syntax: Syntax) -> Options {
        self.syntax = syntax;
        self
    }

    /// Builder: set the importer.
    function with_importer(self, importer: root.importer.Importer) -> Options {
        self.importer = importer;
        self
    }

    /// Builder: set the diagnostic display URL (enables byte-exact snippets).
    function with_url(self, url: string) -> Options {
        self.url = url;
        self
    }

    /// Builder: the directory diagnostic paths are spelled relative to.
    ///
    /// Only a host that knows better than `getcwd` needs this — see
    /// [`Options::cwd`]. On `wasm32-unknown-unknown` there is no `getcwd` at
    /// all, so without it every frame keeps an absolute path.
    function with_cwd(self, cwd: string) -> Options {
        self.cwd = cwd;
        self
    }

    /// Builder: select the diagnostic glyph set (`false` = ASCII / `--no-unicode`).
    function with_unicode(self, unicode: bool) -> Options {
        self.unicode = unicode;
        self
    }

    /// Builder: whether [`compile_with_source_map`] embeds each source's full
    /// text in the map's `sourcesContent` (default `false`).
    function with_source_map_include_sources(self, include: bool) -> Options {
        self.source_map_include_sources = include;
        self
    }

    /// Register a host-defined custom function (dart-sass `functions`).
    ///
    /// `signature` is a Sass function signature — a name and parameter list,
    /// e.g. `"pow($base, $exponent)"` or `"to-list($args...)"`. `callback`
    /// receives the bound arguments serialized to sasso's host-value wire format
    /// and returns the result serialized the same way (or an `Err(message)` that
    /// becomes a compile error). This byte-oriented boundary lets embedders
    /// (wasm/FFI) bridge to their own value system without exposing sasso's
    /// internal `Value` type.
    ///
    /// Custom functions take precedence over built-in global functions but not
    /// over user `@function` definitions or `@use`d module members. A malformed
    /// signature is reported only if the function is actually called.
    ///
    /// That precedence is where sasso is deliberately more permissive than
    /// dart-sass 1.103.1, whose `functions` do not shadow a built-in global at
    /// all (registering `type-of($v)` there leaves the built-in running and the
    /// callback never invoked). The `[global-builtin]` deprecation follows
    /// dart: writing a deprecated global's name warns whether or not a custom
    /// function of that name is registered.
    function with_function(
        self,
        signature: string,
        callback: root.host_fn.HostFunction,
    ) -> Options {
        let parsed = root.host_fn.parse_signature(signature);
        let name = parsed._0;
        let params = parsed._1;
        self.functions.push(root.host_fn.HostFn { name: name, params: params, callback: callback });
        self
    }

    /// Set the diagnostic handler (dart-sass `logger`). Each `@warn`/`@debug`/
    /// deprecation warning is delivered to `handler` instead of being printed to
    /// stderr (the default when unset).
    ///
    /// Deprecations suppressed by [`Options::with_quiet_deps`] or
    /// [`Options::with_silenced_deprecations`] never reach `handler`: both are
    /// applied in the compiler, ahead of the repetition cap, so a suppressed
    /// deprecation is not counted either. See [`WarnHandler`].
    function with_warn_handler(self, handler: WarnHandler) -> Options {
        self.warn = handler;
        self
    }

    /// Silence deprecation warnings from dependencies (dart-sass `quietDeps`):
    /// files that `deps` — normally [`FsImporter::dependencies`] of the importer
    /// in use — marks as reached through a load path. Applied before the
    /// repetition cap, so silenced warnings do not surface as "N repetitive
    /// deprecation warnings omitted" either. `@warn`/`@debug` are unaffected,
    /// as in dart.
    function with_quiet_deps(self, deps: root.importer.DependencySet) -> Options {
        self.quiet_deps = deps;
        self
    }

    /// dart-sass `silenceDeprecations` / `--silence-deprecation`: drop these
    /// deprecations by id, keeping every other warning.
    ///
    /// Applied where `quiet_deps` is, which is before the per-id cap — so a
    /// silenced deprecation neither consumes one of the five printed slots nor
    /// counts towards the "N repetitive deprecation warnings omitted" footer.
    /// Filtering in a warn handler instead leaves that footer behind, counting
    /// warnings the caller asked not to see (dart prints nothing at all).
    ///
    /// Ids sasso never emits are accepted and do nothing: a build script
    /// written for `sass` should not fail here for naming one.
    function with_silenced_deprecations(self, ids: string[]) -> Options {
        // PORT: `ids.into_iter().map(Into::into).collect()` — a fresh array.
        self.silenced_deprecations = root.std.clone_vec(ids);
        self
    }

    /// Set whether to emit the `@charset`/BOM prefix for non-ASCII output
    /// (dart-sass `charset`, default `true`).
    function with_charset(self, charset: bool) -> Options {
        self.charset = charset;
        self
    }
}

/// The kind of a diagnostic delivered to a [`WarnHandler`].
enum WarnKind {
    /// A `@warn` directive (or a deprecation warning).
    Warn,
    /// A `@debug` directive.
    Debug,
}

/// A `@warn` / `@debug` / deprecation diagnostic delivered to an embedder's
/// [`WarnHandler`] (dart-sass `logger`).
///
/// Produced by the compiler and read by handlers; `#[non_exhaustive]` so a
/// future field is not a breaking change for anyone matching on it.
class WarnEvent {
    /// Warning vs debug.
    kind: WarnKind,
    /// True for a deprecation warning.
    deprecation: bool,
    /// The deprecation id (e.g. `"slash-div"`), or `""` when not a deprecation.
    deprecation_id: string,
    /// The raw message text (the `@warn`/`@debug` value, or deprecation message).
    message: string,
    /// The full dart-style block sasso would otherwise print to stderr (header +
    /// snippet + stack trace), for a faithful default logger.
    formatted: string,
    /// The source URL for the diagnostic's span, as dart-sass displays it in a
    /// stack frame: the entry's [`Options::url`] as given, or a loaded file's
    /// path from the working directory (absolute when that would be longer;
    /// a custom importer's non-path key shows its last segment). For an entry
    /// compiled without [`Options::url`] it is `""` under [`compile`] and
    /// `"stdin"` under [`compile_with_source_map`] (the source map has to name
    /// the entry somehow, like dart's `-`); the line is still set. `""` for the
    /// "repetitive deprecation warnings omitted" footer, which has no span.
    url: string,
    /// The 1-based line for the diagnostic's span; `0` when not available.
    line: int,
    /// The canonical URL of the stylesheet being evaluated when the diagnostic
    /// fired, or `""` when not available. For a file the importer loaded this
    /// is the importer's canonical URL — the resolved absolute path with
    /// [`FsImporter`] — which is what [`DependencySet::is_dependency`] keys on.
    /// For the entry stylesheet it is [`Options::url`] exactly as supplied
    /// (the library never canonicalizes the entry). Unlike `url` (dart's display
    /// form, relative to the working directory) it is stable across working
    /// directories and identifies the file.
    path: string,
}

/// An embedder's diagnostic handler (dart-sass `logger`). Receives every
/// `@warn` / `@debug` / deprecation warning that the options do not suppress;
/// if unset, they print to stderr.
///
/// Two options suppress before this point, because both decide what is worth
/// reporting rather than how to report it, and dart-sass applies them in the
/// compiler for the same reason: [`Options::with_quiet_deps`] drops
/// deprecations raised inside dependencies, and
/// [`Options::with_silenced_deprecations`] drops the ids it names. A
/// suppressed deprecation is not merely withheld from the handler — it is not
/// counted either, so it cannot turn up in the "N repetitive deprecation
/// warnings omitted" tally.
type WarnHandler = (WarnEvent) -> void throws unknown;

/// How the entry names itself in a parse error's lone `root stylesheet`
/// frame. A parse error never reaches the evaluator, so it cannot use the
/// evaluator's rule and needs the same one applied here — see
/// [`Options::url`] for why a `file://` URL arrives at all.
function entry_frame_name(url: string, cwd: string?) -> string {
    let from_os: string? = null;
    let cwd = match (cwd) {
        let c: string => c,
        null => {
            // Lossily, as the evaluator's own lookup does. `to_str` would
            // hand back `None` for a directory with one non-UTF-8 component
            // and leave a PARSE error absolute while an evaluation error in
            // the same file came out relative.
            from_os
                = root.std.current_dir() catch (e) {
                    let _e: baml.errors.Io => null
                };
            from_os
        },
    };
    root.pathstyle.pretty_name(root.pathstyle.style_for(cwd, url), url, cwd) ?? url
}

/// Compile SCSS source to CSS.
///
/// # Errors
///
/// Returns [`Error`] on a parse or evaluation failure (with a 1-based
/// source position when known).
///
/// # Allocator scope
///
/// When the binary installs [`ScopedAlloc`] as its `#[global_allocator]`, this
/// function brackets the whole compile in a bump-arena scope: every allocation
/// `compile_inner` makes is a pointer bump from a per-thread arena that is freed
/// wholesale when the scope ends. The returned `Result` is allocated *in* the
/// arena, so it is deep-cloned out to the system allocator *before* the arena is
/// reset — the value handed back to the caller never points into the arena. When
/// no `ScopedAlloc` is installed the scope primitives are inert (depth tracking
/// only) and every allocation goes to the system allocator as usual, so this
/// wrapper is correct (just with a redundant clone) under any global allocator.
function compile(source: string, options: Options) -> string {
    // Enter the arena scope. The RAII guard's `Drop` leaves + resets the arena
    // on the *panic* path; the success path below finishes manually and forgets
    // the guard, so there is no double-leave.
    let guard = root.arena.Scope.enter();
    // PORT: RAII — the guard's `drop` runs at scope exit unless `forget`
    // (below) has run; anything thrown other than the `Err` is the panic path.
    let forgotten = false;
    defer {
        if (!forgotten) {
            guard.drop();
        }
    }
    // All allocations here bump from the arena (when ScopedAlloc is installed).
    // PORT: the `Result` is held as a value (`Ok`/`Err`) so an `Err` runs the
    // same bookkeeping below before it is re-thrown.
    let result: root.std.Ok<string> | root.std.Err<root.error.Error> = {
        root.std.Ok { value: compile_inner(source, options) }
    } catch (e) {
        let err: root.error.Error => root.std.Err { error: err }
    };
    // Leave the scope WITHOUT resetting yet: depth drops to 0, so the arena is
    // now inactive and subsequent allocations route to the system allocator —
    // but the arena memory is still intact and `result` may point into it.
    let outermost = root.arena.leave_no_reset();
    // Deep-clone the result to the system allocator while the scope is inactive.
    // `Error` derives `Clone`, so both the `Ok(String)` and `Err(message)` cases
    // are copied out byte-for-byte to system-owned memory.
    // PORT: nothing in BAML lives in the arena and neither copy is mutated
    // afterwards, so the clone is the value itself.
    let owned = result;
    // Drop the arena-resident original (in-arena `dealloc` is a no-op) before
    // the region it lives in is reclaimed.
    // PORT: `drop(result)` — nothing to free.
    // Only the outermost scope owns the arena's lifetime; reset frees it all.
    if (outermost) {
        root.arena.reset();
    }
    // We finished the scope manually; suppress the guard's `Drop` to avoid a
    // second leave/reset.
    forgotten = true;
    match (owned) {
        let ok: root.std.Ok<string> => ok.value,
        let err: root.std.Err<root.error.Error> => throw err.error,
    }
}

/// The CSS plus its source map, returned by [`compile_with_source_map`].
class CompileResult {
    /// The compiled CSS (identical to what [`compile`] would return for the
    /// same `source`/`options` — the map is generated alongside, not instead).
    css: string,
    /// The Source Map v3 describing `css`. Serialize it with
    /// [`SourceMap::to_json`].
    source_map: root.sourcemap.SourceMap,
}

/// Compile SCSS source to CSS *and* a [Source Map v3](SourceMap).
///
/// The `css` field is byte-for-byte what [`compile`] returns; the map is built
/// alongside it. The map's `file` is the basename of [`Options::url`] (or
/// `"stdin"` when no URL is set) and its `sources` are the source URLs.
/// [`Options::with_source_map_include_sources`] controls whether each source's
/// full text is embedded in `sourcesContent`.
///
/// Maps the start of each selector, declaration property name, declaration
/// value, at-rule keyword, and comment. A value that is a bare `$name` maps
/// back to where that variable was DEFINED, like dart-sass.
///
/// # Errors
///
/// Returns [`Error`] on a parse or evaluation failure, like [`compile`].
function compile_with_source_map(source: string, options: Options) -> CompileResult {
    // Mirror `compile`'s arena bracketing so the returned value is deep-cloned
    // out to the system allocator before the arena is reset.
    let guard = root.arena.Scope.enter();
    // PORT: RAII guard + `Result` value, as in `compile`.
    let forgotten = false;
    defer {
        if (!forgotten) {
            guard.drop();
        }
    }
    let result: root.std.Ok<CompileResult> | root.std.Err<root.error.Error> = {
        root.std.Ok { value: compile_inner_sm(source, options) }
    } catch (e) {
        let err: root.error.Error => root.std.Err { error: err }
    };
    let outermost = root.arena.leave_no_reset();
    // PORT: the clone is the value itself, as in `compile`.
    let owned = result;
    // PORT: `drop(result)` — nothing to free.
    if (outermost) {
        root.arena.reset();
    }
    forgotten = true;
    match (owned) {
        let ok: root.std.Ok<CompileResult> => ok.value,
        let err: root.std.Err<root.error.Error> => throw err.error,
    }
}

/// The basename of a path/URL (everything after the last `/`), used for the
/// source map's `file` field.
function basename(url: string) -> string {
    root.std.last(url.split("/")) ?? url
}

/// The source-map compile pipeline: parse + evaluate exactly like
/// [`compile_inner`], then emit with the source-map collector and assemble the
/// [`SourceMap`].
function compile_inner_sm(source: string, options: Options) -> CompileResult {
    // dart's `quietDeps` is a per-compilation notion: scope the record to this
    // compile — it starts empty, and a nested compile (a warn handler running
    // `compile` with the same importer) hands the enclosing record back when
    // it ends — so provenance cannot leak between compiles sharing an importer.
    // Entered before parsing, so a compile that fails early still leaves the
    // record in its per-compilation state.
    let quiet_deps = options.quiet_deps;
    let _dep_scope = if (quiet_deps != null) {
        quiet_deps.enter_compile()
    } else {
        null
    };
    // PORT: RAII — the scope's `Drop` runs when this function returns or throws.
    defer {
        if (_dep_scope != null) {
            _dep_scope.drop();
        }
    }
    let glyphs: root.diag.GlyphSet = if (options.unicode) {
        root.diag.GlyphSet.Unicode
    } else {
        root.diag.GlyphSet.Ascii
    };
    // Reject `@function`/`@mixin` declarations in control directives or
    // function/mixin bodies, and a misplaced `@import` (a compile-time
    // restriction, checked before eval and rendered like a parse error).
    // PORT: `.and_then(..)` + `match sheet { Ok, Err(mut e) }` → one block
    // with a `catch` for the `Err` arm.
    let sheet = {
        let sheet = match (options.syntax) {
            Syntax.Scss => root.parser.parse(source),
            Syntax.Css => root.parser.parse_plain_css(source),
            Syntax.Sass => root.sass_parser.parse(source),
        };
        if (options.syntax != Syntax.Css) {
            root.eval.validate_declarations(sheet);
        }
        sheet
    } catch (e) {
        let e: root.error.Error => {
            let url = options.url;
            if (url != null) {
                if (e.rendered == null && e.has_position()) {
                    let span = root.diag.trim_empty_span_to_content(
                        source,
                        root.diag.Span { line: e.line, col: e.col, length: e.length },
                    );
                    e.line = span.line;
                    e.col = span.col;
                    e.rendered
                        = root.diag.render_error(
                            e.message,
                            source,
                            entry_frame_name(url, options.cwd),
                            span,
                            glyphs,
                        );
                }
            }
            throw e;
        }
    };
    // The entry name labels the entry source in the map (its `sources` entry,
    // once a mapping references it; an import-only entry has none). It is also
    // the evaluator's `current_url`, so every entry-file node is stamped with a
    // non-zero file id; its source text is kept for `sourcesContent`. The
    // source-map path always passes the real source (so
    // `sourcesContent` works even without a diagnostic URL); this only enriches
    // the *error* path with snippets — the CSS/map success path is unaffected.
    let entry_name = options.url ?? "stdin";
    let ev = root.eval.Evaluator.new(
        root.eval.EvalOptions {
            style: options.style,
            importer: options.importer,
            functions: options.functions,
            cwd: options.cwd,
            source: source,
            url: entry_name,
            glyphs: glyphs,
            warn: options.warn,
            quiet_deps: options.quiet_deps,
            silenced_deprecations: options.silenced_deprecations,
            plain_css: options.syntax == Syntax.Css,
            source_map: true,
        },
    );
    let out: root.eval.OutNode[] = [];
    ev.eval_sheet(sheet, out);
    let emitted = root.emit.emit_with_map(out, options.style, options.charset);
    let css = emitted._0;
    let body_off = emitted._1;
    let collector = emitted._2;
    let mappings = collector.finalize(css, body_off);
    let table = ev.source_table(mappings.source_ids_(), options.source_map_include_sources);
    let sources = table._0;
    let sources_content = table._1;
    let mappings = mappings.encode();
    let source_map = root.sourcemap.SourceMap {
        file: basename(entry_name),
        sources: sources,
        sources_content: sources_content,
        mappings: mappings,
    };
    CompileResult { css: css, source_map: source_map }
}

/// The actual compile pipeline. Runs inside the arena scope established by
/// [`compile`]; all of its allocations may be arena-resident, so its result is
/// copied out by the wrapper before the arena is reset.
function compile_inner(source: string, options: Options) -> string {
    // dart's `quietDeps` is a per-compilation notion: scope the record to this
    // compile — it starts empty, and a nested compile (a warn handler running
    // `compile` with the same importer) hands the enclosing record back when
    // it ends — so provenance cannot leak between compiles sharing an importer.
    // Entered before parsing, so a compile that fails early still leaves the
    // record in its per-compilation state.
    let quiet_deps = options.quiet_deps;
    let _dep_scope = if (quiet_deps != null) {
        quiet_deps.enter_compile()
    } else {
        null
    };
    // PORT: RAII — the scope's `Drop` runs when this function returns or throws.
    defer {
        if (_dep_scope != null) {
            _dep_scope.drop();
        }
    }
    let glyphs_for = () -> root.diag.GlyphSet {
        if (options.unicode) {
            root.diag.GlyphSet.Unicode
        } else {
            root.diag.GlyphSet.Ascii
        }
    };
    // Reject `@function`/`@mixin` declarations in control directives or
    // function/mixin bodies, and a misplaced `@import` (a compile-time
    // restriction, checked before eval and rendered like a parse error).
    // PORT: `.and_then(..)` + `match sheet { Ok, Err(mut e) }` → one block
    // with a `catch` for the `Err` arm.
    let sheet = {
        let sheet = match (options.syntax) {
            Syntax.Scss => root.parser.parse(source),
            Syntax.Css => root.parser.parse_plain_css(source),
            Syntax.Sass => root.sass_parser.parse(source),
        };
        if (options.syntax != Syntax.Css) {
            root.eval.validate_declarations(sheet);
        }
        sheet
    } catch (e) {
        // A parse error never reached the evaluator, so render its snippet here
        // (single `root stylesheet` frame) when a diagnostic URL is configured.
        let e: root.error.Error => {
            let url = options.url;
            if (url != null) {
                if (e.rendered == null && e.has_position()) {
                    let span = root.diag.trim_empty_span_to_content(
                        source,
                        root.diag.Span { line: e.line, col: e.col, length: e.length },
                    );
                    e.line = span.line;
                    e.col = span.col;
                    e.rendered
                        = root.diag.render_error(
                            e.message,
                            source,
                            entry_frame_name(url, options.cwd),
                            span,
                            glyphs_for(),
                        );
                }
            }
            throw e;
        }
    };
    // Diagnostics are enabled only when the caller supplies a display URL; then
    // the evaluator renders byte-exact `Error:`/`WARNING:` blocks against the
    // source. Without a URL it falls back to the legacy one-liner.
    let diag = match (options.url) {
        let url: string => root.std.Tuple2 { _0: source, _1: url },
        null => root.std.Tuple2 { _0: "", _1: "" },
    };
    let diag_source = diag._0;
    let diag_url = diag._1;
    let glyphs: root.diag.GlyphSet = if (options.unicode) {
        root.diag.GlyphSet.Unicode
    } else {
        root.diag.GlyphSet.Ascii
    };
    let ev = root.eval.Evaluator.new(
        root.eval.EvalOptions {
            style: options.style,
            importer: options.importer,
            functions: options.functions,
            cwd: options.cwd,
            source: diag_source,
            url: diag_url,
            glyphs: glyphs,
            warn: options.warn,
            quiet_deps: options.quiet_deps,
            silenced_deprecations: options.silenced_deprecations,
            plain_css: options.syntax == Syntax.Css,
            source_map: false,
        },
    );
    let out: root.eval.OutNode[] = [];
    ev.eval_sheet(sheet, out);
    root.emit.emit(out, options.style, options.charset)
}
