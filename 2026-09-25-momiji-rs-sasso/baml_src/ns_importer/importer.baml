// Ported from sasso `src/importer.rs` (namespace `root.importer`).
//
// The `Importer` trait plus the built-in filesystem importer (`FsImporter`)
// and its dart-faithful partial / index / import-only resolver.

/// An opaque, importer-defined canonical identifier for a resolved stylesheet.
///
/// Two URLs that canonicalize to the same `CanonicalUrl` are the SAME loaded
/// file — it is the module-cache / dedup key. What "canonical" *means* is the
/// importer's to define; sasso only uses it as an `Eq`/`Hash` key. For
/// [`FsImporter`] it is the absolute filesystem path. The field is private so
/// constraints/normalization can be added later without an API break.
class CanonicalUrl {
    _0: string,
    /// Wrap an importer-chosen canonical identifier.
    function new(url: string) -> CanonicalUrl {
        CanonicalUrl { _0: url }
    }

    /// The underlying string.
    function as_str(self) -> string {
        self._0
    }
}

/// The source an [`Importer::load`] produced for a [`CanonicalUrl`] — dart-sass's
/// `ImporterResult`.
class ImporterResult {
    /// The stylesheet source text.
    contents: string,
    /// The syntax `contents` should be parsed with (SCSS / indented / plain CSS).
    syntax: root.Syntax,
    /// The URL to record for this source in generated source maps (dart-sass
    /// `ImporterResult.sourceMapUrl`); `None` falls back to the canonical URL.
    source_map_url: string?,
}

/// A real importer failure — an I/O error, a permission error, an ambiguous
/// match, an invalid URL, … — as distinct from a plain miss. Surfaced as an
/// actionable compile [`crate::Error`], never silently treated as "not found".
class ImporterError {
    /// Human-readable description, used as the compile error message.
    message: string,
}

/// Context passed to [`Importer::canonicalize`] (dart-sass's `CanonicalizeContext`).
class CanonicalizeContext {
    /// `true` when resolving an `@import` (which additionally considers
    /// import-only `*.import.{scss,sass}` files), `false` for `@use`/`@forward`.
    from_import: bool,
    /// The canonical URL of the stylesheet containing the rule being resolved,
    /// if any (`None` only when there is no containing file). Relative URLs
    /// resolve against it.
    containing_url: CanonicalUrl?,
}

/// Resolves `@use` / `@forward` / `@import` URLs in dart-sass's two phases.
///
/// [`canonicalize`](Importer::canonicalize) maps a (possibly relative,
/// extension-less) URL to a stable canonical identity WITHOUT loading it (the
/// result is the module-cache key); [`load`](Importer::load) then fetches that
/// identity's source. Both methods distinguish three outcomes: `Ok(Some(_))` =
/// handled; `Ok(None)` = this importer doesn't handle the URL; `Err(_)` =
/// handled but failed (a real, reportable error).
///
/// Implementing this gives the caller full control over where partials come
/// from — and, crucially, keeps all file access on the caller's side of a
/// sandbox boundary.
///
/// PORT: `Err(ImporterError)` is thrown (`throw ImporterError { … }`).
interface Importer {
    /// Map `url` to its canonical identity, or `Ok(None)` if this importer
    /// cannot resolve it. MUST NOT load the file.
    function canonicalize(
        self,
        url: string,
        ctx: CanonicalizeContext,
    ) -> CanonicalUrl? throws unknown;

    /// Load the source for a [`CanonicalUrl`] previously returned by
    /// [`canonicalize`](Importer::canonicalize); `Ok(None)` if it can no longer
    /// be found.
    function load(self, canonical: CanonicalUrl) -> ImporterResult? throws unknown;
}

/// A filesystem [`Importer`] resolving Sass partials (`_name.scss`,
/// `name/_index.scss`) against a list of load paths.
///
/// Intended for CLI/standalone use; an embedder inside a sandbox should
/// supply its own [`Importer`] that routes through the sandbox's file
/// capability instead of touching the disk directly.
class FsImporter {
    load_paths: string[],
    dependencies: DependencySet,
    /// Create an importer that searches `load_paths` in order.
    function new(load_paths: string[]) -> FsImporter {
        FsImporter { load_paths: load_paths, dependencies: DependencySet.default() }
    }

    /// The files this importer has resolved through a load path so far (see
    /// [`DependencySet`]): a shared handle that keeps filling in as the compile
    /// proceeds, so a diagnostic handler can consult it mid-compile. The record
    /// is per compilation, not per importer: hand it to
    /// [`crate::Options::with_quiet_deps`] and each compile starts it afresh.
    function dependencies_(self) -> DependencySet {
        // PORT: `self.dependencies.clone()` — clones share one set, so the
        // handle is the same object.
        self.dependencies
    }

    implements Importer {
        function canonicalize(self, url: string, ctx: CanonicalizeContext) -> CanonicalUrl? {
            // dart-sass resolves a relative URL against the containing file's
            // directory first, then the configured load paths. A `CanonicalUrl`
            // here IS the absolute fs path, so the containing dir is its parent; a
            // containing URL with no parent (a bare entry name like `input.scss`)
            // means the current directory — reproducing the old base of
            // `dirname_of(url).unwrap_or_default()` (an empty string => CWD).
            //
            // NB: this `parent()`-based dirname must stay consistent with the
            // evaluator's `dirname_of` (eval/mod.rs), which derives
            // `current_file_dir` (the `@import` cache key) from the same canonical
            // URL — both use `Path::parent` + treat an empty parent as CWD.
            let base_dir: string = match (ctx.containing_url) {
                let c: CanonicalUrl => {
                    let par = root.std.path_parent(c.as_str());
                    if (par != null && par != "") {
                        par
                    } else {
                        ""
                    }
                },
                null => "",
            };
            let bases = [base_dir].concat(self.load_paths);
            // PORT: `bases.enumerate()` as an index loop.
            let i = 0;
            while (i < bases.length()) {
                let base = bases[i];
                // `@use`/`@forward` (`from_import == false`) never consider
                // `.import` files (those are an `@import`-only escape hatch).
                match (resolve_in_base(base, url, ctx.from_import)) {
                    Resolution_Found { _0: let p } => {
                        // The canonical key is the absolute, lexically normalized
                        // path (dart `p.canonicalize`), so the same file loaded via
                        // different URLs is cached once. Symlinks are NOT resolved,
                        // as in dart-sass: a file reached through two links is two
                        // modules, and a source map names the link path (a pnpm
                        // `node_modules/<pkg>` path, not its `.pnpm` target).
                        let key = absolute_normalized(p);
                        // Base 0 is the containing file's directory; anything
                        // else is a load path. A file found through a load path,
                        // or relatively from a file that was, is a dependency.
                        let via_load_path = i > 0;
                        let from_dependency = match (ctx.containing_url) {
                            let c: CanonicalUrl => self.dependencies.is_dependency(c.as_str()),
                            null => false,
                        };
                        if (via_load_path || from_dependency) {
                            self.dependencies.mark(key);
                        }
                        return CanonicalUrl.new(key);
                    },
                    // An ambiguous match is an error in dart-sass; we preserve the
                    // existing behavior of surfacing it as a miss (the eval layer
                    // turns that into the import error) rather than an `Err`.
                    Resolution_Ambiguous {} => {
                        return null;
                    },
                    Resolution_NotFound {} => {},
                    _ => root.std.unreachable(),
                }
                i += 1;
            }
            null
        }
        function load(self, canonical: CanonicalUrl) -> ImporterResult? {
            let p = canonical.as_str();
            // PORT: catch arms take no guard; the two `Err` arms are an `if`.
            let contents = root.std.read_to_string(p) catch (e) {
                let io: baml.errors.Io => {
                    // The file vanished between `canonicalize` and `load` -> a miss.
                    if (io_error_is_not_found(io)) {
                        return null;
                    }
                    // Any other read failure (permission, invalid UTF-8, I/O) is a real,
                    // reportable error via the `ImporterError` channel, not a misleading
                    // "can't find stylesheet".
                    throw ImporterError {
                        message: `Cannot read ${p}: ${io_error_display(io, p)}`,
                    };
                }
            };
            ImporterResult { contents: contents, syntax: syntax_for_path(p), source_map_url: null }
        }
    }
}

/// PORT: `e.kind() == std::io::ErrorKind::NotFound` for a `baml.errors.Io`,
/// which carries only the message (ending in the OS error, `ENOENT` = 2).
function io_error_is_not_found(e: baml.errors.Io) -> bool {
    e.message.ends_with("(os error 2)")
}

/// PORT: the `Display` of the `std::io::Error` behind a `baml.errors.Io` from
/// reading `p`: BAML prefixes Rust's text with `Failed to read file '<p>': `.
function io_error_display(e: baml.errors.Io, p: string) -> string {
    root.std.strip_prefix(e.message, `Failed to read file '${p}': `) ?? e.message
}

/// The files a [`FsImporter`] resolved through a load path — dart-sass's
/// "dependencies", the stylesheets `--quiet-deps` silences compiler warnings
/// from — keyed by canonical URL (what [`crate::WarnEvent::path`] carries).
///
/// dart's rule is about how a file was RESOLVED, not where it lives: a file
/// reached through a load path is a dependency, and so is anything a
/// dependency loads relatively; a file the entry (or any non-dependency) loads
/// relatively is not, even if it happens to sit under a load-path directory.
/// Clones share one set. A file reached both ways within one compilation
/// counts as a dependency (the record is a set, not a per-load trace).
///
/// The record is per compilation: a compile that receives the set through
/// [`crate::Options::with_quiet_deps`] starts it empty and, if it was itself
/// started from inside another compile (a warn handler running a nested
/// `compile` with the same importer), hands the outer compile's record back
/// when it finishes. A set shared by CONCURRENT compiles is not meaningful.
///
/// PORT: `Arc<Mutex<DependencyState>>` → the shared `DependencyState` object
/// itself (a class is a reference; `clone()` aliases it).
class DependencySet {
    _0: DependencyState,

    // PORT: `impl std::fmt::Debug` dropped (nothing formats a set with `{:?}`).

    /// An empty set. Allocated with the bump arena paused, like every other
    /// access (see [`DependencySet::lock`]), so a set constructed from inside
    /// a compile does not have its `Arc` reclaimed by that compile's arena
    /// reset while the set lives on. (The library pauses the arena around
    /// importer, warn-handler, and host-function callbacks as well, so this
    /// guards the type on its own terms rather than relying on that.)
    function default() -> DependencySet {
        let _paused = root.arena.pause();
        // PORT: RAII — the pause lifts when `_paused` drops at scope exit.
        defer {
            _paused.drop()
        }
        DependencySet { _0: DependencyState.default() }
    }

    /// Lock the state with the bump arena paused. The set outlives any one
    /// compile, so nothing it owns may live in a compile's arena — and the
    /// std `Mutex` allocates its OS mutex lazily on FIRST lock: with the CLI's
    /// `ScopedAlloc` installed, a first lock from inside a compile would put
    /// that mutex in the arena, which the compile resets on the way out, and
    /// the next lock (the error-CSS re-render, a nested compile, the drop of
    /// the importer) would touch freed memory. Every access goes through here,
    /// and the guard is returned so the caller's own allocations under it
    /// (an inserted key) stay off the arena as well.
    ///
    /// PORT: the `MutexGuard` is the shared state itself; a BAML object cannot
    /// be poisoned, so this never returns `None`. The caller drops the returned
    /// `Paused` when its guard would go out of scope.
    function lock(self) -> root.std.Tuple2<root.arena.Paused, DependencyState>? {
        let paused = root.arena.pause();
        let guard = self._0;
        root.std.Tuple2 { _0: paused, _1: guard }
    }

    /// Whether the file at `canonical` was reached through a load path.
    function is_dependency(self, canonical: string) -> bool {
        let locked = self.lock();
        if (locked != null) {
            let _paused = locked._0;
            defer {
                _paused.drop()
            }
            let st = locked._1;
            st.set.has(canonical)
        } else {
            false
        }
    }

    /// Forget every recorded dependency. A compile scoped on this set (see
    /// [`crate::Options::with_quiet_deps`]) does this itself when it starts;
    /// an embedder reading the set by hand should do it between compiles.
    function clear(self) -> void {
        let locked = self.lock();
        if (locked != null) {
            let _paused = locked._0;
            defer {
                _paused.drop()
            }
            let st = locked._1;
            st.set.clear();
        }
    }

    /// Record `canonical` as a dependency. [`FsImporter`] calls this from its
    /// own resolution; an embedder whose importer resolves load paths itself —
    /// the wasm bridge, whose host does every file lookup — marks each
    /// dependency here, so `quietDeps` follows dart's provenance rule rather
    /// than guessing from where a file happens to live.
    function mark(self, canonical: string) -> void {
        let locked = self.lock();
        if (locked != null) {
            let _paused = locked._0;
            defer {
                _paused.drop()
            }
            let st = locked._1;
            let _ = root.std.set_insert(st.set, canonical);
        }
    }

    /// Scope the record to the compile that is starting: it begins empty, and
    /// the guard restores the enclosing compile's record when a NESTED compile
    /// ends (an outermost compile leaves its record in place, readable
    /// afterwards).
    function enter_compile(self) -> DependencyScope {
        let locked = self.lock();
        let saved: map<string, bool> = if (locked != null) {
            let _paused = locked._0;
            defer {
                _paused.drop()
            }
            let st = locked._1;
            st.depth += 1;
            // PORT: `std::mem::take(&mut st.set)`.
            let taken = st.set;
            st.set = {};
            taken
        } else {
            let empty: map<string, bool> = {};
            empty
        };
        DependencyScope { set: self, saved: saved }
    }
}

class DependencyState {
    set: map<string, bool>,
    /// How many compiles scoped on this set are running (nested ones count).
    depth: int,

    /// derive(Default)
    function default() -> DependencyState {
        DependencyState { set: {}, depth: 0 }
    }
}

/// Guard from [`DependencySet::enter_compile`]; see there.
class DependencyScope {
    set: DependencySet,
    saved: map<string, bool>,
    // PORT: `impl Drop` — a plain method; the owner calls it where Rust drops
    // the guard (see `root.compile_inner`).
    function drop(self) -> void {
        let locked = self.set.lock();
        if (locked != null) {
            let _paused = locked._0;
            defer {
                _paused.drop()
            }
            let st = locked._1;
            st.depth = root.std.saturating_sub_u(st.depth, 1);
            if (st.depth > 0) {
                // A nested compile ends: the outer compile's record comes back.
                // PORT: `std::mem::take(&mut self.saved)`.
                st.set = self.saved;
                self.saved = {};
            }
        }
    }
}

/// The syntax a resolved file should be parsed with, from its extension: a
/// `.sass` file is the indented syntax, anything else (`.scss`) is SCSS.
function syntax_for_path(p: string) -> root.Syntax {
    match (root.std.path_extension(p)) {
        let e: string if root.std.eq_ignore_ascii_case(e, "sass") => root.Syntax.Sass,
        let e: string if root.std.eq_ignore_ascii_case(e, "css") => root.Syntax.Css,
        _ => root.Syntax.Scss,
    }
}

/// Outcome of resolving an `@import` argument within a single load path.
interface Resolution {}

/// Exactly one candidate file matched.
class Resolution_Found {
    _0: string,
    implements Resolution {}
}

/// Two or more candidates matched at the same precedence tier — dart-sass
/// treats this as an error ("It's not clear which file to import.").
class Resolution_Ambiguous {
    implements Resolution {}
}

/// No candidate matched in this base directory.
class Resolution_NotFound {
    implements Resolution {}
}

/// Resolve `@import "path"` against `base`, following dart-sass precedence.
///
/// dart-sass tries, in strict order (each "tier" is checked together; if a
/// tier has more than one match it is ambiguous, if it has exactly one that
/// wins, otherwise fall through to the next tier):
///
/// 1. import-only, non-index: `name.import.{scss,sass}` + partials
/// 2. normal, non-index:      `name.{scss,sass}` + partials
/// 3. import-only index:      `name/index.import.{…}` + `_index.import.{…}`
/// 4. normal index:           `name/index.{…}` + `_index.{…}`
///
/// An explicit `.scss`/`.sass` extension keeps only the matching extension but
/// still honours the import-only override (`name.import.scss`).
///
/// We deliberately do **not** resolve plain `.css` files here: importing a CSS
/// file as a stylesheet is a distinct feature (with its own strict-CSS parsing
/// rules) that this build doesn't implement, and treating `foo.css` as a
/// stylesheet would mis-handle constructs that dart-sass rejects.
///
/// An import-only file whose body is only `@forward`/`@use` (the real-world
/// shape — re-exporting another module) is treated as unusable and skipped,
/// since this build has no module system; resolution then falls through to the
/// normal file, matching the output we can actually produce.
function resolve_in_base(base: string, path: string, allow_import_only: bool) -> Resolution {
    // dart-sass normalizes the URL lexically before touching the filesystem,
    // so `foo/bar/../baz` resolves even when `foo/bar` doesn't exist.
    let normalized = lexical_normalize(path);
    let path = normalized;
    let p = path;
    let par = root.std.path_parent(p);
    let dir = if (par != null && par != "") {
        root.std.path_join(base, par)
    } else {
        base
    };
    let file = root.std.path_file_name(p) ?? path;

    // Explicit `.css` extension: only the plain-CSS candidate is considered.
    // (An `@import "x.css"` never reaches here — it's a passthrough upstream —
    // but `@use "x.css"` does.)
    let css_stem = root.std.strip_suffix(file, ".css");
    if (css_stem != null) {
        return match (tier_exact(dir, css_stem, ["css"], false)) {
            Tier_One { _0: let p } => Resolution_Found { _0: p },
            Tier_Many {} => Resolution_Ambiguous {  },
            Tier_None {} => Resolution_NotFound {  },
            _ => root.std.unreachable(),
        };
    }

    // Explicit `.scss`/`.sass` extension: only that extension is considered.
    let explicit_ext = [".scss", ".sass"].find((ext: string) -> bool {
        file.ends_with(ext)
    });

    if (explicit_ext != null) {
        let ext = explicit_ext;
        let stem = file.slice(0, file.length() - ext.length());
        // Strip the leading dot so `ext` is e.g. "scss".
        let ext = ext.slice(1, ext.length());
        // Tier 1: import-only override for the explicit extension.
        if (allow_import_only) {
            match (tier_exact(dir, stem, [ext], true)) {
                Tier_One { _0: let p } => {
                    return Resolution_Found { _0: p };
                },
                Tier_Many {} => {
                    return Resolution_Ambiguous {  };
                },
                Tier_None {} => {},
                _ => root.std.unreachable(),
            }
        }
        // Tier 2: the file as written (+ partial).
        return match (tier_exact(dir, stem, [ext], false)) {
            Tier_One { _0: let p } => Resolution_Found { _0: p },
            Tier_Many {} => Resolution_Ambiguous {  },
            Tier_None {} => Resolution_NotFound {  },
            _ => root.std.unreachable(),
        };
    }

    // Extensionless: scss/sass are equal precedence, css is a fallback.
    let non_index: root.std.Tuple2<string, bool>[] = [];
    if (allow_import_only) {
        non_index.push(root.std.Tuple2 { _0: file, _1: true });
    }
    non_index.push(root.std.Tuple2 { _0: file, _1: false });
    for (let entry in non_index) {
        let stem = entry._0;
        let import_only = entry._1;
        match (tier_with_extensions(dir, stem, import_only)) {
            Tier_One { _0: let p } => {
                return Resolution_Found { _0: p };
            },
            Tier_Many {} => {
                return Resolution_Ambiguous {  };
            },
            Tier_None {} => {},
            _ => root.std.unreachable(),
        }
    }

    // A plain `.css` file (loaded in plain-CSS mode): after the Sass
    // candidates, but BEFORE index files (dart-sass `_tryPathWithExtensions`
    // tries `$path.css` before `_tryPathAsDirectory`).
    match (tier_exact(dir, file, ["css"], false)) {
        Tier_One { _0: let p } => {
            return Resolution_Found { _0: p };
        },
        Tier_Many {} => {
            return Resolution_Ambiguous {  };
        },
        Tier_None {} => {},
        _ => root.std.unreachable(),
    }

    // Index files live in a subdirectory named after the import path.
    let index_dir = root.std.path_join(dir, file);
    let index_modes: bool[] = if (allow_import_only) {
        [true, false]
    } else {
        [false]
    };
    for (let import_only in index_modes) {
        match (tier_with_extensions(index_dir, "index", import_only)) {
            Tier_One { _0: let p } => {
                return Resolution_Found { _0: p };
            },
            Tier_Many {} => {
                return Resolution_Ambiguous {  };
            },
            Tier_None {} => {},
            _ => root.std.unreachable(),
        }
    }

    Resolution_NotFound {  }
}

/// dart `p.canonicalize`: the absolute path with `.`/`..` segments removed
/// lexically — no `realpath`, so symlinks stay unresolved. A relative path is
/// taken from the current directory.
///
/// On Windows the result is lowercased, as dart's `Style.windows` canonicalizes
/// each part: the filesystem is case-insensitive there, so two spellings of one
/// path must produce ONE key or the module would be loaded twice and appear
/// twice in a source map's `sources`. Elsewhere the path is used as written,
/// again like dart — which case-folds for no other style, not even on a
/// case-insensitive macOS volume.
function absolute_normalized(p: string) -> string {
    let abs = if (root.std.path_is_absolute(p)) {
        p
    } else {
        let cwd = root.std.current_dir() catch (e) {
            let _e: baml.errors.Io => null
        };
        if (cwd != null) {
            root.std.path_join(cwd, p)
        } else {
            p
        }
    };
    // PORT: the `PathBuf` being built is kept as its component list
    // (`"/"` = RootDir, `"."` = CurDir, `".."` = ParentDir, else Normal) and
    // rebuilt with `path_from_components` at the end.
    let out: string[] = [];
    for (let comp in root.std.path_components(abs)) {
        match (comp) {
            "." => {},
            ".." => {
                // `/..` at the root stays at the root, like `p.normalize`.
                let last = root.std.last(out);
                if (last != null && last != "/" && last != "." && last != "..") {
                    let _ = out.pop();
                }
            },
            let c => {
                out.push(c);
            },
        }
    }
    let out = root.std.path_from_components(out);
    // PORT: `#[cfg(windows)] let out = out.to_lowercase();` — not a Windows build.
    out
}

/// Lexically remove `.` and `..` segments from a URL path (no filesystem
/// access; leading `..` segments that would escape are kept).
function lexical_normalize(path: string) -> string {
    let out: string[] = [];
    for (let seg in path.split("/")) {
        match (seg) {
            "" | "." => {},
            ".." => {
                let last = root.std.last(out);
                if (last != null && last != "..") {
                    let _ = out.pop();
                } else {
                    out.push("..");
                }
            },
            let s => {
                out.push(s);
            },
        }
    }
    let s = root.std.join(out, "/");
    if (path.starts_with("/")) {
        s = "/" + s;
    }
    if (s == "") {
        s = s + ".";
    }
    s
}

/// One precedence tier's matches.
interface Tier {}

class Tier_None {
    implements Tier {}
}

class Tier_One {
    _0: string,
    implements Tier {}
}

class Tier_Many {
    implements Tier {}
}

/// `Tier::from`.
function Tier_from(found: string[]) -> Tier {
    match (found.length()) {
        0 => Tier_None {  },
        1 => Tier_One { _0: found.pop() ?? "" },
        _ => Tier_Many {  },
    }
}

/// Try a tier with the standard extension grouping: `scss` and `sass` are
/// checked together (any match there wins the tier). Each extension is checked
/// in both non-partial and partial (`_name`) forms.
function tier_with_extensions(dir: string, stem: string, import_only: bool) -> Tier {
    tier_exact(dir, stem, ["scss", "sass"], import_only)
}

/// Collect existing candidate files for `stem` under `dir` across `exts`, in
/// non-partial and partial forms, optionally inserting the `.import` suffix
/// (import-only files). Returns how many matched.
function tier_exact(dir: string, stem: string, exts: string[], import_only: bool) -> Tier {
    let found: string[] = [];
    let suffix = if (import_only) {
        ".import"
    } else {
        ""
    };
    for (let ext in exts) {
        for (let name in [`_${stem}${suffix}.${ext}`, `${stem}${suffix}.${ext}`]) {
            let cand = root.std.path_join(dir, name);
            if (root.std.is_file(cand)) {
                found.push(cand);
            }
        }
    }
    Tier_from(found)
}
