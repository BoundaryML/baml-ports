// Ported from sasso `tests/callable_origin.rs` (namespace `root.tests.callable_origin`).
//
// A mixin, function, or `@content` block runs against the file that wrote
// it (dart-sass evaluates a callable where it was defined): its output maps
// to that file, and its diagnostics name that file and render its source —
// whether it was reached through `@use`, a textual `@import`, or a
// first-class reference. A content block belongs to the file of the
// `@include` that wrote it, not to the mixin's.
//
// PORT: `use sasso::{…}` — `compile` → `root.compile`,
// `compile_with_source_map` → `root.compile_with_source_map`, `Options` →
// `root.Options`, `Syntax` → `root.Syntax`, `WarnEvent` → `root.WarnEvent`, and
// `CanonicalUrl`/`CanonicalizeContext`/`FsImporter`/`Importer`/`ImporterError`/
// `ImporterResult` → `root.importer.*`. `Rc<RefCell<Vec<…>>>` is a plain array
// (a reference type) the handler closure pushes into; `PathBuf`/`Path` are
// `string`s; `std::env::temp_dir()` → `root.tests.support.temp_dir()`;
// `std::process::id()` → `baml.sys.pid()`. `compile(..).expect(..)` /
// `.unwrap()` → the call itself (a thrown error fails the test).

function DEP() -> string {
    "@mixin m {\n  x: 1;\n  @content;\n  z: 3;\n}\n@function f($v) {\n  @warn \"in f\";\n  @return $v + 1;\n}\n@mixin undef {\n  q: $nope;\n}\n"
}

function IMP() -> string {
    "@import \"dep\";\na {\n  @include m {\n    @warn \"in content\";\n    y: f(1);\n  }\n}\n"
}

function scratch(tag: string) -> string {
    let dir = root.std.path_join(root.tests.support.temp_dir(), `sasso_origin_${tag}_${baml.sys.pid()}`);
    // PORT: `.expect("mkdir")` — the thrown `Io` fails the test.
    root.std.create_dir_all(root.std.path_join(dir, "src"));
    root.std.write_file(root.std.path_join(dir, "src/_dep.scss"), DEP());
    dir
}

/// The canonical url `FsImporter` keys a resolved file by: the absolute path
/// as it was reached, with the ASCII case folding `absolute_normalized` applies
/// on Windows (dart's `Style.windows` canonicalizes each part, and that
/// filesystem is case-insensitive).
function canon_key(p: string) -> string {
    // `PathBuf::push` does not respell `/` as the platform separator, so a
    // `join("src/imp.scss")` keeps its `/` on Windows while the importer's key,
    // built from the real path, uses `\`. Re-collecting the components respells
    // it the way the platform does.
    let p = root.std.path_from_components(root.std.path_components(p));
    let s = p;
    // PORT: `#[cfg(windows)] let s = s.to_lowercase();` — not the host build.
    s
}

function canon(dir: string, rel: string) -> string {
    canon_key(root.std.path_join(dir, rel))
}

/// A path fragment as a LOADED file's frame spells it: the importer reached the
/// file through the filesystem, so on Windows it is `\`-separated. An ENTRY is
/// echoed as it was given instead — the urls here are built with a `/` and keep
/// it — so entry fragments are deliberately NOT respelled.
function loaded(frag: string) -> string {
    // PORT: `if cfg!(windows) { frag.replace('/', "\\") } else { … }` — the host
    // build is not Windows, so only the `else` branch remains.
    frag
}

/// PORT: `compile(src, &opts).expect_err(msg).to_string()` — the rendered
/// `root.error.Error`; a successful compile panics with `msg`, as
/// `Result::expect_err` does.
function expect_err(source: string, options: root.Options, msg: string) -> string {
    let css = root.compile(source, options) catch (e) {
        let err: root.error.Error => {
            return err.to_string();
        }
    };
    root.std.panic(`${msg}: ${root.std.debug_str(css)}`)
}

test "imported_callable_output_maps_to_its_file_and_content_to_the_includers" {
    // dart: sources [imp.scss, _dep.scss], mappings `AACA;ECAE;EDGE;ECDF` —
    // `x: 1` and `z: 3` in the mixin's file, `y: f(1)` (the content block)
    // back in the entry.
    let dir = scratch("map");
    let entry = root.std.path_join(dir, "src/imp.scss");
    root.std.write_file(entry, IMP());
    let url = entry;
    let imp = root.importer.FsImporter.new([]);
    let opts = root.Options.default().with_importer(imp).with_url(url);
    let r = root.compile_with_source_map(IMP(), opts);
    assert.equal(r.css, "a {\n  x: 1;\n  y: 2;\n  z: 3;\n}");
    assert.equal(r.source_map.sources, [url, canon(dir, "src/_dep.scss")]);
    assert.equal(r.source_map.mappings, "AACA;ECAE;EDGE;ECDF");
    // PORT: `std::fs::remove_dir_all(&dir).ok()`.
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    };
}

test "warn_events_inside_callables_carry_the_defining_file" {
    let dir = scratch("warn");
    let entry = root.std.path_join(dir, "src/imp.scss");
    root.std.write_file(entry, IMP());
    let url = entry;
    // (message, url, path, formatted) per non-deprecation event.
    // PORT: `type Seen = Vec<(String, String, String, String)>` inlined; the
    // `Rc<RefCell<Seen>>` is the array itself, captured by the handler.
    let seen: root.std.Tuple4<string, string, string, string>[] = [];
    let sink = seen;
    let imp = root.importer.FsImporter.new([]);
    let opts = root.Options.default().with_importer(imp).with_url(url).with_warn_handler((ev: root.WarnEvent) -> void {
        if (!ev.deprecation) {
            sink.push(root.std.Tuple4 { _0: ev.message, _1: ev.url, _2: ev.path, _3: ev.formatted });
        }
    });
    root.compile(IMP(), opts);
    let events = seen;
    let dep = canon(dir, "src/_dep.scss");
    // The content block's `@warn` is the entry's: path = entry, and the
    // innermost frame is the `@content` member in the entry, then the
    // `@content;` statement in the mixin (m(), line 3), then the include.
    let content = root.std.expect(
        events.find((e) -> {
            e._0 == "in content"
        }),
        "content warn",
    );
    assert.equal(content._2, url);
    // display url of the entry is its url as given
    assert.equal(content._1, url);
    // (Frames are column-aligned, so match the fields, not the padding.)
    // {content.3}
    assert.is_true(content._3.includes("src/imp.scss 4:5") && content._3.includes("  @content\n"));
    // {content.3}
    assert.is_true(
        content._3.includes(loaded("src/_dep.scss 3:3")) && content._3.includes("  m()\n"),
    );
    // The function's `@warn` is the dependency's: path = its resolved file,
    // url = its display path, member f().
    let f = root.std.expect(
        events.find((e) -> {
            e._0 == "in f"
        }),
        "f warn",
    );
    assert.equal(f._2, dep);
    // url {f.1:?}
    // PORT: `Path::ends_with` compares components → `root.std.path_ends_with`.
    assert.is_true(root.std.path_ends_with(f._1, "src/_dep.scss"));
    // {f.3}
    assert.is_true(f._3.includes(loaded("src/_dep.scss 7:3")) && f._3.includes("  f()\n"));
    // PORT: `drop(events)` — nothing to release.
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    };
}

test "error_inside_an_imported_mixin_renders_its_source" {
    // dart: the snippet shows `q: $nope;` from _dep.scss with the frame
    // `_dep.scss 11:6  undef()`, then the include site in the entry.
    let dir = scratch("err");
    let entry = root.std.path_join(dir, "src/undef.scss");
    let src = "@import \"dep\";\na {\n  @include undef;\n}\n";
    root.std.write_file(entry, src);
    let url = entry;
    let imp = root.importer.FsImporter.new([]);
    let opts = root.Options.default().with_importer(imp).with_url(url);
    let err = expect_err(src, opts, "undefined variable");
    // {err}
    assert.is_true(err.starts_with("Error: Undefined variable.\n"));
    // {err}
    assert.is_true(err.includes("11 │   q: $nope;\n"));
    // {err}
    assert.is_true(err.includes(loaded("src/_dep.scss 11:6")) && err.includes("  undef()\n"));
    // {err}
    assert.is_true(
        err.includes("src/undef.scss 3:3") && root.std.trim_end(err).ends_with("  root stylesheet"),
    );
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    };
}

test "meta_call_resolves_namespaces_at_the_definition_site" {
    // A function invoked through `meta.call` runs against its own `@use`
    // namespaces (dart: `b: 7px`), not the caller's — which has no `math`.
    let dir = scratch("call_ns");
    root.std.write_file(
        root.std.path_join(dir, "src/_lib.scss"),
        "@use \"sass:math\";\n@use \"sass:string\" as s;\n@function half($v) {\n  @return math.div($v, 2) + s.length(\"ab\");\n}\n",
    );
    let entry = root.std.path_join(dir, "src/main.scss");
    let src = "@use \"sass:meta\";\n@use \"lib\";\na {\n  b: meta.call(meta.get-function(\"half\", $module: \"lib\"), 10px);\n}\n";
    root.std.write_file(entry, src);
    let url = entry;
    let imp = root.importer.FsImporter.new([]);
    let opts = root.Options.default().with_importer(imp).with_url(url);
    assert.equal(root.compile(src, opts), "a {\n  b: 7px;\n}");
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    };
}

test "members_forwarded_through_an_import_keep_their_namespaces" {
    // `@import "fwd"` over `@forward "dep"`: the members join the importer's
    // scope, but their bodies still resolve `math.div` and the `h.` alias
    // through _dep.scss's own `@use`s (dart: `b: 11px; padding: 2px 2px`).
    let dir = scratch("fwd_ns");
    root.std.write_file(
        root.std.path_join(dir, "src/_helpers.scss"),
        "$unit: 1px;\n@function twice($v) {\n  @return $v * 2;\n}\n",
    );
    root.std.write_file(
        root.std.path_join(dir, "src/_lib.scss"),
        "@use \"sass:math\";\n@use \"helpers\" as h;\n$scale: 3;\n@function half($v) {\n  @return math.div($v, 2) + h.twice(h.$unit) * $scale;\n}\n@mixin pad($v) {\n  padding: math.div($v, 2) h.twice(1px);\n}\n",
    );
    root.std.write_file(root.std.path_join(dir, "src/_fwd.scss"), "@forward \"lib\";\n");
    let entry = root.std.path_join(dir, "src/main.scss");
    let src = "@import \"fwd\";\na {\n  b: half(10px);\n  @include pad(4px);\n}\n";
    root.std.write_file(entry, src);
    let url = entry;
    let imp = root.importer.FsImporter.new([]);
    let opts = root.Options.default().with_importer(imp).with_url(url).with_warn_handler((_ev: root.WarnEvent) -> void {});
    assert.equal(root.compile(src, opts), "a {\n  b: 11px;\n  padding: 2px 2px;\n}");
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    };
}

test "url_less_entry_keeps_its_identity_across_callables" {
    // An entry compiled without `Options::url` has the empty display url and
    // path. Its content block passed to a module mixin, and its own mixin
    // included from inside an imported file, still run as the entry: their
    // `@warn` events report the entry's empty `url`/`path`, not the module's.
    let dir = scratch("nourl");
    root.std.write_file(
        root.std.path_join(dir, "src/_mod.scss"),
        "@mixin m {\n  x: 1;\n  @content;\n}\n@mixin call-back {\n  @include from-entry;\n}\n",
    );
    let src = "@use \"mod\";\n@mixin from-entry {\n  @warn \"entry mixin\";\n  y: 2;\n}\na {\n  @include mod.m {\n    @warn \"entry content\";\n  }\n}\n";
    // (message, url, path) per non-deprecation event.
    // PORT: `type Seen = Vec<(String, String, String)>` inlined.
    let seen: root.std.Tuple3<string, string, string>[] = [];
    let sink = seen;
    let imp = root.importer.FsImporter.new([root.std.path_join(dir, "src")]);
    let opts = root.Options.default().with_importer(imp).with_warn_handler((ev: root.WarnEvent) -> void {
        if (!ev.deprecation) {
            sink.push(root.std.Tuple3 { _0: ev.message, _1: ev.url, _2: ev.path });
        }
    });
    let css = root.compile(src, opts);
    assert.equal(css, "a {\n  x: 1;\n}");
    let events = seen;
    let content = root.std.expect(
        events.find((e) -> {
            e._0 == "entry content"
        }),
        "content warn",
    );
    // content block is the entry's
    assert.equal([content._1, content._2], ["", ""]);
    // PORT: `drop(events)` — nothing to release.
    // The other direction: the entry's mixin, included from inside an
    // imported file's mixin, runs as the entry again.
    root.std.write_file(
        root.std.path_join(dir, "src/_imp.scss"),
        "@mixin call-back {\n  z: 3;\n  @include from-entry;\n}\n",
    );
    let src2 = "@import \"imp\";\n@mixin from-entry {\n  @warn \"entry mixin\";\n  y: 2;\n}\na {\n  @include call-back;\n}\n";
    seen.clear();
    let css = root.compile(src2, opts);
    assert.equal(css, "a {\n  z: 3;\n  y: 2;\n}");
    let events = seen;
    let mixin = root.std.expect(
        events.find((e) -> {
            e._0 == "entry mixin"
        }),
        "entry mixin warn",
    );
    // entry mixin is the entry's
    assert.equal([mixin._1, mixin._2], ["", ""]);
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    };
}

test "module_callables_know_whether_they_are_a_mixin" {
    // `meta.content-exists()` answers for the include at hand inside a
    // `@use`d module's mixin (dart: `has: content` / `has: none`), and errors
    // inside a module function even when a mixin with a content block called
    // it — the same rules as the direct include and call paths.
    let dir = scratch("in_mixin");
    root.std.write_file(
        root.std.path_join(dir, "src/_lib.scss"),
        "@use \"sass:meta\";\n@mixin m {\n  @if meta.content-exists() {\n    has: content;\n    @content;\n  } @else {\n    has: none;\n  }\n}\n@function probe() {\n  @return meta.content-exists();\n}\n",
    );
    let entry = root.std.path_join(dir, "src/main.scss");
    let url = entry;
    let imp = root.importer.FsImporter.new([]);
    let opts = root.Options.default().with_importer(imp).with_url(url);
    let src = "@use \"lib\";\na {\n  @include lib.m {\n    b: 1;\n  }\n}\nc {\n  @include lib.m;\n}\n";
    root.std.write_file(entry, src);
    assert.equal(
        root.compile(src, opts),
        "a {\n  has: content;\n  b: 1;\n}\n\nc {\n  has: none;\n}",
    );
    let src = "@use \"lib\";\n@mixin wrap {\n  x: lib.probe();\n  @content;\n}\na {\n  @include wrap {\n    b: 1;\n  }\n}\n";
    root.std.write_file(entry, src);
    let err = expect_err(src, opts, "not in a mixin");
    // {err}
    assert.is_true(err.starts_with("Error: content-exists() may only be called within a mixin.\n"));
    // Match the frame with its whitespace collapsed: the trace pads its
    // location column to the widest frame, and which frame that is depends on
    // where the scratch tree sits relative to the process's working directory.
    // A build sandbox that puts $TMPDIR above the cwd (Nix uses /build and
    // /build/source) renders this frame relative and the entry's absolute, so
    // the gap here is not always two spaces.
    let line = err.lines().find((l) -> {
        l.includes("_lib.scss 11:11")
    });
    let frame = if (line != null) {
        root.std.split_whitespace(line).join(" ")
    } else {
        ""
    };
    // {err}
    assert.is_true(frame.ends_with("_lib.scss 11:11 probe()"));
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    };
}

/// Two virtual modules whose canonical URLs share a last segment, so both
/// display as `foo` in diagnostics.
class SameNameImporter {
    implements root.importer.Importer {
        function canonicalize(
            self,
            url: string,
            ctx: root.importer.CanonicalizeContext,
        ) -> root.importer.CanonicalUrl? {
            // PORT: `_ctx` is unused.
            match (url) {
                "a" => root.importer.CanonicalUrl.new("custom://a/foo"),
                "b" => root.importer.CanonicalUrl.new("custom://b/foo"),
                _ => null,
            }
        }

        function load(
            self,
            canonical: root.importer.CanonicalUrl,
        ) -> root.importer.ImporterResult? {
            let contents = match (canonical.as_str()) {
                "custom://a/foo" => {
                    "@mixin ma {\n  p: $nope;\n}\n@mixin boom {\n  @error \"boom\";\n}\n@mixin need($x) {\n  p: $x;\n}\n"
                },
                "custom://b/foo" => {
                    "@use \"a\";\n@mixin mb {\n\n\n  q: $nope;\n}\n@mixin via-a {\n\n\n\n\n  @include a.boom;\n}\n@mixin via-ma {\n  @include a.ma;\n}\n@mixin via-need {\n  @include a.need;\n}\n"
                },
                _ => {
                    return null;
                },
            };
            root.importer.ImporterResult {
                contents: contents,
                syntax: root.Syntax.Scss,
                source_map_url: null,
            }
        }
    }
}

test "custom_importer_modules_sharing_a_display_name_render_their_own_source" {
    // The display name `foo` is ambiguous; the callable's origin carries its
    // own source, so an error inside `a.ma` shows A's text (line 2), not B's,
    // even though B was registered under `foo` last.
    let imp = SameNameImporter {  };
    let opts = root.Options.default().with_importer(imp).with_url("entry.scss");
    let err = expect_err("@use \"a\";\n@use \"b\";\nx {\n  @include a.ma;\n}\n", opts, "undefined variable");
    // {err}
    assert.is_true(err.includes("2 │   p: $nope;\n"));
    // {err}
    assert.is_true(err.includes("foo 2:6"));
    // {err}
    assert.is_true(!err.includes("q: $nope"));
    // And the other way round: an `@error` in A's mixin, included from B's
    // mixin, attaches at B's `@include a.boom` (line 12 of B) — the frame
    // carries B's text, so the snippet is B's line, not A's.
    let err = expect_err("@use \"b\";\nx {\n  @include b.via-a;\n}\n", opts, "boom");
    // {err}
    assert.is_true(err.starts_with("Error: \"boom\"\n"));
    // {err}
    assert.is_true(err.includes("12 │   @include a.boom;\n"));
    // {err}
    assert.is_true(err.includes("foo 12:3"));
    // Nested: B loads A while B itself displays as `foo`, so A is evaluated
    // (and its callables capture their origin) with the loader already named
    // `foo`. A's mixin must still carry A's text: `p: $nope` on A's line 2,
    // not B's line 2.
    let opts = root.Options.default().with_importer(imp).with_url("entry.scss");
    let err = expect_err("@use \"b\";\nx {\n  @include b.via-ma;\n}\n", opts, "undefined variable");
    // {err}
    assert.is_true(err.includes("2 │   p: $nope;\n"));
    // {err}
    assert.is_true(err.includes("foo 2:6"));
    // {err}
    assert.is_true(!err.includes("@mixin mb"))
}

test "using_defaults_evaluate_where_the_block_was_written" {
    // `@include dep.m using ($x, $y: $caller)`: `@content(1)` supplies `$x` from
    // the mixin, and the default for `$y` evaluates in the INCLUDER's file —
    // dart: `b: 3` — so a default naming the module's own `$inner` is an
    // undefined variable there, reported under the `@content` member.
    let dir = scratch("using_defaults");
    root.std.write_file(
        root.std.path_join(dir, "src/_dep.scss"),
        "$inner: 100;\n@mixin m {\n  @content(1);\n}\n",
    );
    let entry = root.std.path_join(dir, "src/main.scss");
    let url = entry;
    let imp = root.importer.FsImporter.new([]);
    let opts = root.Options.default().with_importer(imp).with_url(url);
    let src = "@use \"dep\";\n$caller: 2;\na {\n  @include dep.m using ($x, $y: $caller) {\n    b: $x + $y;\n  }\n}\n";
    root.std.write_file(entry, src);
    assert.equal(root.compile(src, opts), "a {\n  b: 3;\n}");
    let src = "@use \"dep\";\na {\n  @include dep.m using ($x, $y: $inner) {\n    b: $x + $y;\n  }\n}\n";
    root.std.write_file(entry, src);
    let err = expect_err(src, opts, "undefined variable");
    // {err}
    assert.is_true(err.starts_with("Error: Undefined variable.\n"));
    // {err}
    assert.is_true(err.includes("3 │   @include dep.m using ($x, $y: $inner) {\n"));
    // {err}
    assert.is_true(err.includes("main.scss 3:33") && err.includes("  @content\n"));
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    };
}

test "a_cross_module_capture_renders_its_own_module_source" {
    // A mixin captured from another module with `meta.get-mixin($module:)` and
    // invoked through `meta.apply` runs against the file it was WRITTEN in,
    // which it carries with it. Both modules here display as `foo`, so a
    // snippet fetched by that display name would come from whichever was
    // registered last — B's line 2 instead of A's.
    let imp = SameNameImporter {  };
    let opts = root.Options.default().with_importer(imp).with_url("entry.scss");
    let src = "@use \"sass:meta\";\n@use \"a\";\n@use \"b\";\nx {\n  @include meta.apply(meta.get-mixin(\"ma\", $module: \"a\"));\n}\n";
    let err = expect_err(src, opts, "undefined variable");
    // {err}
    assert.is_true(err.includes("2 │   p: $nope;\n"));
    // {err}
    assert.is_true(!err.includes("@mixin mb"));
    // {err}
    assert.is_true(err.includes("foo 2:6"))
}

test "a_two_span_error_keeps_files_that_share_a_display_name_apart" {
    // `Missing argument` points at the call AND at the declaration it was
    // measured against. Here they are in DIFFERENT files that both display as
    // `foo`, so grouping the two spans by display name alone would draw the
    // declaration against the caller's lines. Each keeps its own block and its
    // own text. (The block SHAPE is locked against dart by
    // `tests/diagnostics.rs`; a custom importer is not reproducible in the dart
    // CLI, so this test locks only the identity.)
    let imp = SameNameImporter {  };
    let opts = root.Options.default().with_importer(imp).with_url("entry.scss");
    let err = expect_err("@use \"b\";\nx {\n  @include b.via-need;\n}\n", opts, "missing argument");
    // {err}
    assert.is_true(err.starts_with("Error: Missing argument $x.\n"));
    // Two blocks, each headed by the name the two files share.
    // PORT: `"\u{250c}\u{2500}\u{2500}> foo\n"` written literally;
    // `str::matches(p).count()` → the number of `split` gaps.
    // {err}
    assert.equal(err.split("┌──> foo\n").length() - 1, 2);
    // The invocation is B's line 18, the declaration A's line 7 — and each is
    // rendered from ITS file, so neither block shows the other's text.
    // {err}
    assert.is_true(err.includes("18 │   @include a.need;\n"));
    // {err}
    assert.is_true(err.includes("7 │ @mixin need($x) {\n"));
    // {err}
    assert.is_true(!err.includes("@mixin via-need"))
}
