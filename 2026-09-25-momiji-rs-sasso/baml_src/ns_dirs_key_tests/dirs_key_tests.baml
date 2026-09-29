// Ported from sasso `src/main.rs` `#[cfg(test)] mod dirs_key_tests`
// (namespace `root.dirs_key_tests`).
//
// PORT: `use super::dirs_key` — reached as `root.dirs_key`; `std::path::Path`
// is a `string` (ops in `root.std.path_*`).

/// Windows: two spellings of one directory are one key.
///
/// The importer lowercases a canonical path there and the command line
/// says whatever was typed, so without the fold the same directory
/// enters the snapshot twice — and the copy that is not marked as ours
/// watches the mtime our own output moves, which is a self-recompile
/// loop. #146 was this mistake one layer down.
// PORT: `#[cfg(windows)]` — not compiled for the macOS/Linux host build the
// port targets (guide §11), where `dirs_key` keys under `Style::Posix` (that
// half is the next test). Kept, asserting the Windows rule on this host:
// `dirs_key` is `path_key(normalize_path(cwd.join(p)))`, `path_key` under
// `Style::Posix` is the identity, and on Windows it is
// `path_key_in(Style::Windows, …)` — so the Windows key of `p` is
// `path_key_in(Style::Windows, dirs_key(p))` here.
test "two_spellings_of_one_directory_are_one_key" {
    assert.equal(
        root.path_key_in(root.pathstyle.Style.Windows, root.dirs_key("SRC\\Sub")),
        root.path_key_in(root.pathstyle.Style.Windows, root.dirs_key("src\\sub")),
    )
}

/// …and everywhere else they are two directories, because they are two
/// files. Folding here would merge a watch's `src/` and `SRC/`.
// `#[cfg(not(windows))]`
test "case_is_part_of_the_name_off_windows" {
    assert.is_true(root.dirs_key("SRC/Sub") != root.dirs_key("src/sub"))
}

/// Either way it is absolute: the command line says `out.css` and the
/// importer says the whole path, and a set holding both must see one
/// directory.
test "a_relative_path_is_keyed_against_the_working_directory" {
    let key = root.dirs_key("out.css");
    // {key:?}
    assert.is_true(root.std.path_is_absolute(key));
    let cwd = root.std.current_dir();
    assert.equal(key, root.dirs_key(root.std.path_join(cwd, "out.css")))
}
