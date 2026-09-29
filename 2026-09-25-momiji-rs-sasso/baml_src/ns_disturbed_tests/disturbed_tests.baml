// Ported from sasso `src/main.rs` `#[cfg(test)] mod disturbed_tests`
// (namespace `root.disturbed_tests`).
//
// PORT: `use super::*` — the binary root's items are reached as `root.*`
// (`Shared`, `Unit`, `Outcome`, `Status`, `finish_compile_error`,
// `compile_source`, `append_ext`, and `sasso::{OutputStyle, Syntax}`).
// `std::env::temp_dir()` → `$TMPDIR`, else `/tmp` (its Unix definition);
// `Path`/`PathBuf` are `string`s; `std::fs::remove_dir_all(&dir).ok()` →
// `baml.fs.remove_dir_all` with its `Io` caught.

/// `--watch` with `--no-error-css`: the only combination that removes an
/// output rather than writing an error stylesheet over it. `--watch`
/// alone is what the created-file guards need, and the removal guards
/// need both.
function shared() -> root.Shared {
    root.Shared {
        load_paths: [],
        style: root.OutputStyle.Expanded,
        unicode: true,
        charset: true,
        quiet: false,
        quiet_deps: false,
        update: false,
        silenced: [],
        no_css: false,
        embed_sources: false,
        embed_source_map: false,
        source_map_urls: root.SourceMapUrls.Relative,
        file_source_map: false,
        watch: true,
        provisional: false,
        file_error_css: false,
        stdout_error_css: false,
    }
}

function unit(dir: string) -> root.Unit {
    root.Unit {
        source: root.Source_File { _0: root.std.path_join(dir, "main.scss") },
        url: "main.scss",
        syntax: root.Syntax.Scss,
        target: root.Target_File { _0: root.std.path_join(dir, "out.css") },
    }
}

function scratch(name: string) -> string {
    let dir = root.std.path_join(root.std.env_var("TMPDIR") ?? "/tmp", `sasso_${name}`);
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    };
    root.std.create_dir_all(dir);
    dir
}

/// A removal that removed nothing disturbed nothing.
///
/// `disturbed` is a one-way door: `Snapshot::follow` puts the name into
/// the directory's `minus` set and never takes it out again. Recording a
/// removal that did not happen would therefore blind the watch to that
/// filename for the rest of the run — so the push belongs on the `Ok`
/// arm, and `NotFound` must reach neither it nor the error report.
test "a_removal_of_an_absent_output_disturbs_nothing" {
    let dir = scratch("no_error_css_absent");
    let outcome = root.Outcome.failed(root.Status.CompileError, "");
    root.finish_compile_error(unit(dir), shared(), [], "boom", "boom", outcome);
    let disturbed = root.std.clone_vec(outcome.disturbed);
    let stderr = outcome.stderr;
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    };
    // {disturbed:?}
    assert.is_true(disturbed.length() == 0);
    // {stderr:?}
    assert.is_true(stderr == "")
}

/// A write that FAILED still records what it created.
///
/// `write_css_file` writes the map first and the CSS second, so an
/// unwritable output leaves a brand-new `.map` behind and returns `Err`.
/// Recording only on the `Ok` arm leaves that creation unowned: the
/// directory holding it is not re-stamped and the name is not in its
/// `minus` set, so our own sidecar can be read back as somebody else's
/// arrival.
///
/// The output is a DIRECTORY here — the one way to make the CSS write
/// fail that needs no permission bit, and so behaves the same for root
/// and in CI.
test "a_failed_write_records_the_map_it_created" {
    let dir = scratch("partial_write");
    let out = root.std.path_join(dir, "out.css");
    // PORT: `std::fs::create_dir(&out).unwrap()` — non-recursive `mkdir`.
    let _ = baml.fs.mkdir(out, baml.fs.MkdirOptions { recursive: false });
    let shared = root.Shared { ...root.disturbed_tests.shared(), file_source_map: true };
    let unit = root.Unit {
        source: root.Source_File { _0: root.std.path_join(dir, "main.scss") },
        url: "main.scss",
        syntax: root.Syntax.Scss,
        target: root.Target_File { _0: out },
    };
    let outcome = root.compile_source(unit, ".a { color: red; }\n", shared);
    let disturbed = root.std.clone_vec(outcome.disturbed);
    let map = root.append_ext(out, "map");
    let map_landed = root.std.exists(map);
    let failed = outcome.status == root.Status.IoError;
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    };

    // the CSS write was supposed to fail: {:?}
    assert.is_true(failed);
    // the map is written first, so it should be there
    assert.is_true(map_landed);
    // the map this compile created went unrecorded
    assert.equal(disturbed, [map])
}

/// …and a write that created nothing records nothing, so the guard above
/// cannot be satisfied by recording unconditionally.
test "a_failed_write_that_created_nothing_records_nothing" {
    let dir = scratch("partial_write_nothing");
    let out = root.std.path_join(dir, "out.css");
    // PORT: `std::fs::create_dir(&out).unwrap()` — non-recursive `mkdir`.
    let _ = baml.fs.mkdir(out, baml.fs.MkdirOptions { recursive: false });
    // The map is already there, so this compile creates neither file.
    root.std.write_file(root.append_ext(out, "map"), "{}");
    let shared = root.Shared { ...root.disturbed_tests.shared(), file_source_map: true };
    let unit = root.Unit {
        source: root.Source_File { _0: root.std.path_join(dir, "main.scss") },
        url: "main.scss",
        syntax: root.Syntax.Scss,
        target: root.Target_File { _0: out },
    };
    let outcome = root.compile_source(unit, ".a { color: red; }\n", shared);
    let disturbed = root.std.clone_vec(outcome.disturbed);
    let failed = outcome.status == root.Status.IoError;
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    };

    // the CSS write was supposed to fail
    assert.is_true(failed);
    // {disturbed:?}
    assert.is_true(disturbed.length() == 0)
}

/// …and one that did remove a file did, because that moves the
/// directory's mtime exactly as a creation does.
test "a_removal_of_a_present_output_is_a_disturbance" {
    let dir = scratch("no_error_css_present");
    let out = root.std.path_join(dir, "out.css");
    root.std.write_file(out, ".a{}");
    let outcome = root.Outcome.failed(root.Status.CompileError, "");
    root.finish_compile_error(unit(dir), shared(), [], "boom", "boom", outcome);
    let disturbed = root.std.clone_vec(outcome.disturbed);
    let survived = root.std.exists(out);
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    };
    assert.equal(disturbed, [out]);
    // the stale output outlived the failed compile
    assert.is_true(!survived)
}
