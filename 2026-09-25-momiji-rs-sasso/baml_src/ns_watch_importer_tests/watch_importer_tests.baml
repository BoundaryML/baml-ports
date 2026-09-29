// Ported from sasso `src/main.rs` `#[cfg(test)] mod watch_importer_tests`
// (namespace `root.watch_importer_tests`).
//
// PORT: `use super::RecordingImporter` — reached as `root.RecordingImporter`;
// `use sasso::{CanonicalizeContext, Importer}` — `root.importer.*` (the trait
// methods are called on the class directly). `std::env::temp_dir()` →
// `$TMPDIR`, else `/tmp` (its Unix definition); `std::process::id()` →
// `baml.sys.pid()`; `Path`/`PathBuf` are `string`s.

/// A dependency that vanishes between `canonicalize` and `load`.
///
/// The importer answers `None` — its own comment calls that a miss —
/// and the url never reaches `unresolved`, because canonicalizing it
/// SUCCEEDED. So nothing would follow the file or the directory it
/// lives in, and recreating it in a subdirectory would never reach the
/// watch. The stamp is taken for a miss as well as a hit; only `loaded`
/// is reserved for what was actually read.
///
/// The race is the test: the file is deleted between the two calls, by
/// hand, so there is no timing to get right.
test "a_dependency_that_vanishes_mid_load_is_still_followed" {
    let dir = root.std.path_join(root.std.env_var("TMPDIR") ?? "/tmp", `sasso-vanish-${baml.sys.pid()}`);
    root.std.create_dir_all(root.std.path_join(dir, "sub"));
    let dep = root.std.path_join(root.std.path_join(dir, "sub"), "_v.scss");
    root.std.write_file(dep, "$c: red;\n");

    let importer = root.RecordingImporter.new([dir]);
    let ctx = root.importer.CanonicalizeContext { from_import: false, containing_url: null };
    // PORT: `.expect("canonicalize")` on the `Result` → an `ImporterError`
    // becomes a panic; `.expect(…)` on the `Option` → `root.std.expect`.
    let canonical = root.std.expect(
        importer.canonicalize("sub/v", ctx) catch (e) {
            let err: root.importer.ImporterError => root.std.panic(`canonicalize: ${err.message}`)
        },
        "the file is there at this point",
    );

    root.std.remove_file(dep);

    // a miss is not an error
    let loaded = importer.load(canonical) catch (e) {
        let err: root.importer.ImporterError => {
            root.std.panic(`a miss is not an error: ${err.message}`)
        }
    };
    let stamps = importer.loaded_stamps();
    let paths = importer.loaded_paths();
    // PORT: `std::fs::remove_dir_all(&dir).ok()`.
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    };

    // the file was deleted, so this is a miss
    assert.is_true(loaded == null);
    // a miss must still be followed: {stamps:?}
    // PORT: `Path::ends_with` compares components → `root.std.path_ends_with`.
    assert.is_true(
        stamps.some((pair) -> {
            root.std.path_ends_with(pair._0, "_v.scss")
        }),
    );
    // …but nothing was READ, so it is not a dependency: {paths:?}
    assert.is_true(paths.length() == 0)
}
