// Ported from sasso `tests/warn_event_path.rs` (namespace `root.tests.warn_event_path`).
//
// `WarnEvent::path`: the stylesheet a diagnostic came from, as an identity —
// for a file the importer loaded, the importer's canonical URL (the resolved
// absolute path with `FsImporter`); for the entry stylesheet, `Options::url`
// exactly as supplied. That is what a CLI needs to tell a load-path
// dependency from the entry (dart-sass `--quiet-deps`), since
// `WarnEvent::url` is dart's short display form (a load-path file's basename).
//
// PORT: `use sasso::{compile, FsImporter, Options, WarnEvent}` → `root.compile`,
// `root.importer.FsImporter`, `root.Options`, `root.WarnEvent`
// (`sasso::WarnHandler` → `root.WarnHandler`). `FsImporter::dependencies()` is
// `dependencies_()` in the port (the field shares the name). A
// `DependencySet` is one shared object, so `deps.clone()` / `Rc::clone` alias
// it. `Rc<RefCell<Vec<…>>>` is a plain array the handler closure pushes into.
// `PathBuf`/`Path` are `string`s; `std::env::temp_dir()` →
// `root.tests.support.temp_dir()`; `std::process::id()` → `baml.sys.pid()`.
// `.expect(…)` / `.unwrap()` on a fallible call → the call itself (a thrown
// error fails the test).

/// The canonical url `FsImporter` keys a resolved file by: the absolute path
/// as it was reached, with the ASCII case folding `absolute_normalized` applies
/// on Windows (dart's `Style.windows` canonicalizes each part, and that
/// filesystem is case-insensitive).
function canon_key(p: string) -> string {
    // `PathBuf::push` does not respell `/` as the platform separator, so a
    // `join("lp/_dep.scss")` keeps its `/` on Windows while the importer's key,
    // built from the real path, uses `\`. Re-collecting the components respells
    // it the way the platform does.
    let p = root.std.path_from_components(root.std.path_components(p));
    let s = p;
    // PORT: `#[cfg(windows)] let s = s.to_lowercase();` — not the host build.
    s
}

function scratch() -> string {
    let dir = root.std.path_join(root.tests.support.temp_dir(), `sasso_warn_path_${baml.sys.pid()}`);
    // PORT: `.expect("mkdir")` — the thrown `Io` fails the test.
    root.std.create_dir_all(root.std.path_join(dir, "lp"));
    dir
}

/// PORT: `std::fs::remove_dir_all(&dir).ok()`.
function remove_dir_all_ok(dir: string) -> void {
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    };
}

test "warn_event_path_is_the_resolved_file_path" {
    let dir = scratch();
    let entry = root.std.path_join(dir, "entry.scss");
    root.std.write_file(entry, "@import \"dep\";\n@warn \"from entry\";\n");
    root.std.write_file(
        root.std.path_join(dir, "lp/_dep.scss"),
        "@import \"dep2\";\n@warn \"from dep\";\n",
    );
    root.std.write_file(root.std.path_join(dir, "lp/_dep2.scss"), "e { f: 2; }\n");

    // (message, deprecation?, url, path) per event.
    // PORT: `type Seen = Vec<(String, bool, String, String)>` inlined; the
    // `Rc<RefCell<Seen>>` is the array itself, captured by the handler.
    let seen: root.std.Tuple4<string, bool, string, string>[] = [];
    let sink = seen;
    let importer = root.importer.FsImporter.new([root.std.path_join(dir, "lp")]);
    let url = entry;
    let opts = root.Options.default().with_importer(importer).with_url(url).with_warn_handler((
        ev: root.WarnEvent,
    ) -> void {
        sink.push(root.std.Tuple4 { _0: ev.message, _1: ev.deprecation, _2: ev.url, _3: ev.path });
    });
    let src = root.std.read_to_string(entry);
    root.compile(src, opts);
    let events = seen;

    let dep_canon = canon_key(root.std.path_join(dir, "lp/_dep.scss"));
    // The entry's own @import deprecation: path is the entry (as given).
    let entry_dep = root.std.expect(
        events.find((e) -> {
            e._1 && e._0.includes("@import")
        }),
        "entry deprecation",
    );
    // entry deprecation carries the entry path
    assert.equal(entry_dep._3, url);
    // The dependency's @import deprecation: display url is the file's path,
    // path is the resolved file.
    let dep_dep = root.std.expect(
        events
            .filter((e) -> {
                e._1 && e._0.includes("@import")
            })
            .at(1),
        "dependency deprecation",
    );
    // The display url is dart's `prettyUri`: the path from the current directory
    // (or absolute when that would be longer) — not a bare basename.
    // display url is the file's path, got {:?}
    // PORT: `Path::ends_with` compares components → `root.std.path_ends_with`.
    assert.is_true(root.std.path_ends_with(dep_dep._2, "lp/_dep.scss") && dep_dep._2 != "_dep.scss");
    // path is the resolved load-path file
    assert.equal(dep_dep._3, dep_canon);
    // @warn from the dependency and from the entry.
    let w_dep = root.std.expect(
        events.find((e) -> {
            e._0 == "from dep"
        }),
        "@warn from dep",
    );
    assert.equal(w_dep._3, dep_canon);
    // A `@warn` event carries the same display url as its stack frame.
    // @warn url is the file's display path
    assert.equal(w_dep._2, dep_dep._2);
    let w_entry = root.std.expect(
        events.find((e) -> {
            e._0 == "from entry"
        }),
        "@warn from entry",
    );
    assert.equal(w_entry._3, url);
    // PORT: `drop(events)` — nothing to release.
    remove_dir_all_ok(dir)
}

/// `FsImporter::dependencies()`: dart's rule is about how a file was resolved.
/// Through a load path -> dependency; relatively from a dependency ->
/// dependency; relatively from the entry -> not one, even inside the load-path
/// directory.
test "fs_importer_tracks_load_path_dependencies" {
    let dir = root.std.path_join(root.tests.support.temp_dir(), `sasso_dep_set_${baml.sys.pid()}`);
    root.std.create_dir_all(root.std.path_join(dir, "lp"));
    let entry = root.std.path_join(dir, "entry.scss");
    // `@use` first (must precede other rules), then the load-path import.
    root.std.write_file(entry, "@use \"lp/rel\";\n@import \"dep\";\n");
    root.std.write_file(root.std.path_join(dir, "lp/_rel.scss"), "q { r: 1; }\n");
    root.std.write_file(root.std.path_join(dir, "lp/_dep.scss"), "@import \"dep-child\";\n");
    root.std.write_file(root.std.path_join(dir, "lp/_dep-child.scss"), "s { t: 1; }\n");

    let importer = root.importer.FsImporter.new([root.std.path_join(dir, "lp")]);
    let deps = importer.dependencies_();
    let url = entry;
    let opts = root.Options.default().with_importer(importer).with_url(url).with_warn_handler((
        _ev: root.WarnEvent,
    ) -> void {});
    root.compile(root.std.read_to_string(entry), opts);

    let canon = (rel: string) -> string {
        canon_key(root.std.path_join(dir, rel))
    };
    // resolved relative to the entry
    assert.is_true(!deps.is_dependency(canon("lp/_rel.scss")));
    // resolved through the load path
    assert.is_true(deps.is_dependency(canon("lp/_dep.scss")));
    // loaded relatively FROM a dependency
    assert.is_true(deps.is_dependency(canon("lp/_dep-child.scss")));
    // the entry is never a dependency
    assert.is_true(!deps.is_dependency(url));
    remove_dir_all_ok(dir)
}

/// `with_quiet_deps` is per compilation: reusing one importer (and its set)
/// for a second compile must not carry over what the first one classified.
test "quiet_deps_record_is_per_compilation_even_with_a_reused_importer" {
    let dir = root.std.path_join(root.tests.support.temp_dir(), `sasso_dep_reuse_${baml.sys.pid()}`);
    root.std.create_dir_all(root.std.path_join(dir, "lp"));
    root.std.write_file(root.std.path_join(dir, "lp/_dep.scss"), "@import \"leaf\";\n");
    root.std.write_file(root.std.path_join(dir, "lp/_leaf.scss"), "q { r: 1; }\n");
    let a = root.std.path_join(dir, "a.scss");
    let b = root.std.path_join(dir, "b.scss");
    root.std.write_file(a, "@import \"dep\";\n"); // via the load path: a dependency
    root.std.write_file(b, "@use \"lp/dep\";\n"); // relative: not one

    let importer = root.importer.FsImporter.new([root.std.path_join(dir, "lp")]);
    let deps = importer.dependencies_();
    let seen: string[] = [];
    let sink = seen;
    let handler: root.WarnHandler = (ev: root.WarnEvent) -> void {
        if (ev.deprecation) {
            sink.push(ev.path);
        }
    };
    let dep_canon = canon_key(root.std.path_join(dir, "lp/_dep.scss"));

    let url_a = a;
    let opts_a = root.Options.default()
        .with_importer(importer)
        .with_url(url_a)
        .with_quiet_deps(deps)
        .with_warn_handler(handler);
    root.compile(root.std.read_to_string(a), opts_a);
    // reached through the load path in compile a
    assert.is_true(deps.is_dependency(dep_canon));
    // only a's own @import warns; the dependency's is silenced
    assert.equal(seen.length(), 1);

    seen.clear();
    let url_b = b;
    let opts_b = root.Options.default()
        .with_importer(importer)
        .with_url(url_b)
        .with_quiet_deps(deps)
        .with_warn_handler(handler);
    root.compile(root.std.read_to_string(b), opts_b);
    // compile b starts from an empty record
    assert.is_true(!deps.is_dependency(dep_canon));
    // the relatively-loaded file's @import warns in compile b
    assert.equal(seen, [dep_canon]);
    remove_dir_all_ok(dir)
}

/// The evaluator caches textual `@import` resolution per (url, base dir), so
/// the importer — where provenance is recorded — is skipped on a hit. A file
/// first imported from a non-dependency and later from a dependency must still
/// become a dependency on that second, cached load.
test "dependency_provenance_survives_the_import_cache" {
    let dir = root.std.path_join(root.tests.support.temp_dir(), `sasso_dep_cache_${baml.sys.pid()}`);
    root.std.create_dir_all(root.std.path_join(dir, "lp"));
    root.std.write_file(root.std.path_join(dir, "lp/_a.scss"), "@import \"x\";\n"); // reached relatively: not a dependency
    root.std.write_file(root.std.path_join(dir, "lp/_b.scss"), "@import \"x\";\n"); // reached through -I lp: a dependency
    root.std.write_file(root.std.path_join(dir, "lp/_x.scss"), "q { r: 1; }\n");
    let entry = root.std.path_join(dir, "entry.scss");
    root.std.write_file(entry, "@import \"lp/a\";\n@import \"b\";\n");
    let importer = root.importer.FsImporter.new([root.std.path_join(dir, "lp")]);
    let deps = importer.dependencies_();
    let url = entry;
    let opts = root.Options.default()
        .with_importer(importer)
        .with_url(url)
        .with_quiet_deps(deps)
        .with_warn_handler((_ev: root.WarnEvent) -> void {});
    root.compile(root.std.read_to_string(entry), opts);
    let canon = (rel: string) -> string {
        canon_key(root.std.path_join(dir, rel))
    };
    assert.is_true(!deps.is_dependency(canon("lp/_a.scss")));
    assert.is_true(deps.is_dependency(canon("lp/_b.scss")));
    // x was loaded from b (a dependency) via the import cache
    assert.is_true(deps.is_dependency(canon("lp/_x.scss")));
    remove_dir_all_ok(dir)
}

/// A warn handler may run a nested `compile` with the same importer and set.
/// The nested compile starts from an empty record and, when it ends, hands the
/// outer compile's record back — so the outer compile's later dependency
/// deprecations are still silenced and its record is not polluted.
test "quiet_deps_record_is_reentrant_across_a_nested_compile" {
    let dir = root.std.path_join(root.tests.support.temp_dir(), `sasso_dep_nested_${baml.sys.pid()}`);
    root.std.create_dir_all(root.std.path_join(dir, "lp"));
    // Outer dependency: warns (which triggers the nested compile), THEN imports.
    root.std.write_file(
        root.std.path_join(dir, "lp/_dep.scss"),
        "@warn \"nest\";\n@import \"leaf\";\n",
    );
    root.std.write_file(root.std.path_join(dir, "lp/_leaf.scss"), "q { r: 1; }\n");
    // Nested entry: reaches a different dependency.
    root.std.write_file(root.std.path_join(dir, "lp/_other.scss"), "@import \"leaf\";\n");
    let inner_entry = root.std.path_join(dir, "inner.scss");
    root.std.write_file(inner_entry, "@import \"other\";\n");
    let outer_entry = root.std.path_join(dir, "outer.scss");
    root.std.write_file(outer_entry, "@import \"dep\";\n");

    // PORT: `Rc::new(FsImporter::new(…))` / `Rc::clone` → one shared object.
    let importer = root.importer.FsImporter.new([root.std.path_join(dir, "lp")]);
    let deps = importer.dependencies_();
    let outer_deprecations: string[] = [];
    let sink = outer_deprecations;
    let nested_importer = importer;
    let nested_deps = deps;
    let nested_url = inner_entry;
    let nested_src = root.std.read_to_string(inner_entry);
    let handler: root.WarnHandler = (ev: root.WarnEvent) -> void {
        if (ev.deprecation) {
            sink.push(ev.path);
        } else if (ev.message == "nest") {
            let opts = root.Options.default()
                .with_importer(nested_importer)
                .with_url(nested_url)
                .with_quiet_deps(nested_deps)
                .with_warn_handler((_ev: root.WarnEvent) -> void {});
            // PORT: `.expect("nested compile")` — a thrown error propagates.
            root.compile(nested_src, opts);
        }
    };
    let url = outer_entry;
    let opts = root.Options.default()
        .with_importer(importer)
        .with_url(url)
        .with_quiet_deps(deps)
        .with_warn_handler(handler);
    root.compile(root.std.read_to_string(outer_entry), opts);

    let canon = (rel: string) -> string {
        canon_key(root.std.path_join(dir, rel))
    };
    // Only the outer entry's own @import reached the handler: dep's @import
    // (fired AFTER the nested compile returned) was still silenced.
    assert.equal(outer_deprecations, [url]);
    // outer record intact after the nested compile
    assert.is_true(deps.is_dependency(canon("lp/_dep.scss")));
    // the nested compile's record did not leak into the outer one
    assert.is_true(!deps.is_dependency(canon("lp/_other.scss")));
    remove_dir_all_ok(dir)
}

/// The per-compilation scope is entered before parsing, so a compile that
/// fails early (a syntax error) still starts the record empty rather than
/// leaving the previous compile's files visible.
test "quiet_deps_record_is_scoped_even_when_the_compile_fails_early" {
    let dir = root.std.path_join(root.tests.support.temp_dir(), `sasso_dep_fail_${baml.sys.pid()}`);
    root.std.create_dir_all(root.std.path_join(dir, "lp"));
    root.std.write_file(root.std.path_join(dir, "lp/_dep.scss"), "q { r: 1; }\n");
    let importer = root.importer.FsImporter.new([root.std.path_join(dir, "lp")]);
    let deps = importer.dependencies_();
    let silent: root.WarnHandler = (_ev: root.WarnEvent) -> void {};
    let opts = root.Options.default()
        .with_importer(importer)
        .with_url("ok.scss")
        .with_quiet_deps(deps)
        .with_warn_handler(silent);
    root.compile("@import \"dep\";\n", opts);
    let dep_canon = canon_key(root.std.path_join(dir, "lp/_dep.scss"));
    assert.is_true(deps.is_dependency(dep_canon));
    let opts = root.Options.default()
        .with_importer(importer)
        .with_url("broken.scss")
        .with_quiet_deps(deps)
        .with_warn_handler(silent);
    // a parse error
    // PORT: `compile(..).is_err()` → catch the `root.error.Error`.
    let failed = (
        root.compile("a { b: c ", opts) catch (e) {
            let _e: root.error.Error => null
        }
    )
        == null;
    assert.is_true(failed);
    // the failed compile still started its record empty
    assert.is_true(!deps.is_dependency(dep_canon));
    remove_dir_all_ok(dir)
}
