// Port support for the integration-test crates in `tests/` (not a Rust file).
//
// Cargo gives each integration test `env!("CARGO_BIN_EXE_sasso")`, the path of
// the freshly built CLI. The BAML equivalent is the `baml pack`ed executable
// at `dist/sasso` (rebuild it with `RUST_MIN_STACK=1073741824 baml pack main -o dist/sasso`
// after changing the port). Tests run with the project root as the cwd.

/// `env!("CARGO_BIN_EXE_sasso")`.
function sasso_bin() -> string {
    let root = root.std.current_dir() catch (e) {
        _ => "."
    };
    root + "/dist/sasso"
}

/// `env!("CARGO_MANIFEST_DIR")` — the Rust crate root, where the upstream
/// test fixtures live.
function manifest_dir() -> string {
    let root = root.std.current_dir() catch (e) {
        _ => "."
    };
    root + "/port/upstream/sasso"
}

/// `std::env::temp_dir()`.
function temp_dir() -> string {
    let t = root.std.env_var("TMPDIR") ?? "/tmp";
    root.std.trim_end_matches(t, "/")
}
