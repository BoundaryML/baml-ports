// Ported from sasso `src/pathstyle.rs` `#[cfg(test)] mod tests`
// (namespace `root.pathstyle.tests`).
//
// PORT: `use super::{file_url_path, has_scheme, pretty, pretty_name,
// relative_parts, style_for, Style, HOST}` — reached as `root.pathstyle.*`
// (`HOST` is the zero-arg function `root.pathstyle.HOST()`). Rust raw strings
// `r"C:\a"` are spelled with doubled backslashes.

/// Joined with the style's own separator, which is what a diagnostic path
/// uses. `None` is "no relative spelling exists".
function rel(style: root.pathstyle.Style, base: string, target: string) -> string? {
    let p = root.pathstyle.relative_parts(style, base, target);
    if (p != null) {
        p.join(style.sep())
    } else {
        null
    }
}

/// #146, verbatim from the first Windows CI run: `FsImporter`'s canonical
/// key is lowercased (dart's `p.canonicalize` for `Style.windows`) while
/// `current_dir()` keeps the filesystem's spelling. Compared literally, the
/// two match only as far as the drive letter and every loaded file is shown
/// as an absolute temp path.
test "windows_relativises_a_lowercased_key_against_a_mixed_case_cwd" {
    assert.equal(
        rel(
            root.pathstyle.Style.Windows,
            "C:\\Users\\RUNNER~1\\AppData\\Local\\Temp\\sasso_frames",
            "c:\\users\\runner~1\\appdata\\local\\temp\\sasso_frames\\src\\sub\\_warnme.scss",
        ),
        "src\\sub\\_warnme.scss",
    )
}

/// The same spelling difference is a real difference on POSIX, where two
/// cases are two files.
test "posix_case_is_significant" {
    assert.equal(
        rel(root.pathstyle.Style.Posix, "/Users/me/app", "/users/me/app/src/a.scss"),
        "../../../users/me/app/src/a.scss",
    );
    assert.equal(
        rel(root.pathstyle.Style.Posix, "/Users/me/app", "/Users/me/app/src/a.scss"),
        "src/a.scss",
    )
}

/// Windows reads `/` as a separator, so a path spelled either way splits
/// and compares the same.
test "windows_accepts_either_separator" {
    assert.equal(
        rel(root.pathstyle.Style.Windows, "C:\\dev\\app", "C:/dev/app/src/a.scss"),
        "src\\a.scss",
    )
}

/// A `..` chain when the target is not under the base, and the mixed case
/// that produced #146 on the way out of the tree as well as into it.
test "walks_up_out_of_the_base" {
    assert.equal(
        rel(root.pathstyle.Style.Windows, "C:\\Dev\\App\\out", "c:\\dev\\app\\src\\a.scss"),
        "..\\src\\a.scss",
    );
    assert.equal(
        rel(root.pathstyle.Style.Posix, "/dev/app/out", "/dev/other/a.scss"),
        "../../other/a.scss",
    )
}

/// Different roots have no relative spelling: a `..` chain across drives
/// would name nothing at all. Callers fall back to the absolute path.
test "different_roots_have_no_relative_spelling" {
    assert.equal(
        rel(root.pathstyle.Style.Windows, "C:\\dev\\app", "D:\\dev\\app\\src\\a.scss"),
        null,
    );
    assert.equal(
        rel(root.pathstyle.Style.Windows, "\\\\nas\\share\\app", "\\\\nas\\other\\app\\a.scss"),
        null,
    );
    // One side relative: there is no common root to measure from.
    assert.equal(rel(root.pathstyle.Style.Windows, "dev", "C:\\dev\\a.scss"), null);
    assert.equal(rel(root.pathstyle.Style.Posix, "/dev", "dev/a.scss"), null)
}

/// A UNC share is the root, not two leading segments, and it folds case
/// like any other Windows name.
test "unc_share_is_the_root" {
    assert.equal(
        rel(root.pathstyle.Style.Windows, "\\\\NAS\\Share\\app", "\\\\nas\\share\\app\\src\\a.scss"),
        "src\\a.scss",
    );
    assert.equal(
        rel(
            root.pathstyle.Style.Windows,
            "\\\\nas\\share\\app\\out",
            "\\\\nas\\share\\app\\src\\a.scss",
        ),
        "..\\src\\a.scss",
    )
}

/// A drive letter without a separator after it is DRIVE-RELATIVE: `C:foo`
/// means "foo in whatever directory this process is in on C:", which is
/// not something a relative path can be measured from or to.
test "a_drive_without_a_separator_is_not_a_root" {
    assert.equal(rel(root.pathstyle.Style.Windows, "C:\\dev\\app", "C:foo"), null);
    assert.equal(rel(root.pathstyle.Style.Windows, "C:foo", "C:\\dev\\app\\a.scss"), null);
    // Both drive-relative: still nothing to measure, even though the two
    // spellings share a drive letter.
    assert.equal(rel(root.pathstyle.Style.Windows, "C:foo", "C:bar"), null);
    // The drive alone is the same case.
    assert.equal(rel(root.pathstyle.Style.Windows, "C:", "C:\\a.scss"), null)
}

/// A share is spelled `\\server\share` when it is the whole path and
/// `\\server\share\` when something follows it, so a working directory
/// that IS the share used to match nothing under it.
test "a_root_matches_with_or_without_its_trailing_separator" {
    assert.equal(
        rel(root.pathstyle.Style.Windows, "\\\\nas\\share", "\\\\nas\\share\\app\\a.scss"),
        "app\\a.scss",
    );
    assert.equal(
        rel(root.pathstyle.Style.Windows, "\\\\nas\\share\\", "\\\\nas\\share\\app\\a.scss"),
        "app\\a.scss",
    );
    // A different share still does not match, trailing separator or not.
    assert.equal(
        rel(root.pathstyle.Style.Windows, "\\\\nas\\share", "\\\\nas\\other\\a.scss"),
        null,
    )
}

/// `std::fs::canonicalize` returns a verbatim path and `current_dir` does
/// not, so one side of a comparison can carry a `\\?\` the other lacks.
test "a_verbatim_prefix_is_not_part_of_the_root_identity" {
    assert.equal(
        rel(root.pathstyle.Style.Windows, "\\\\?\\C:\\dev\\app", "C:\\dev\\app\\src\\a.scss"),
        "src\\a.scss",
    );
    assert.equal(
        rel(root.pathstyle.Style.Windows, "C:\\dev\\app", "\\\\?\\c:\\dev\\app\\src\\a.scss"),
        "src\\a.scss",
    )
}

/// Repeated separators and a trailing one are not empty segments.
test "empty_segments_are_dropped" {
    assert.equal(
        rel(root.pathstyle.Style.Windows, "C:\\dev\\app\\", "C:\\dev\\\\app\\src\\a.scss"),
        "src\\a.scss",
    );
    assert.equal(rel(root.pathstyle.Style.Posix, "/dev/app/", "/dev/app//src/a.scss"), "src/a.scss")
}

/// The root itself: dart counts it as one segment when it splits a path,
/// which is what `segments` deliberately does not include.
test "segments_exclude_the_root" {
    // PORT: `Style::Windows.segments(..)` — the variant is bound to a
    // `Style`-typed local first (a bare variant literal has no methods), and
    // `segments` already returns the collected `Vec`.
    let windows: root.pathstyle.Style = root.pathstyle.Style.Windows;
    let posix: root.pathstyle.Style = root.pathstyle.Style.Posix;
    assert.equal(windows.segments("C:\\dev\\app\\a.scss"), ["dev", "app", "a.scss"]);
    assert.equal(windows.segments("\\\\nas\\share\\a.scss"), ["a.scss"]);
    assert.equal(windows.segments("\\\\?\\C:\\dev\\a.scss"), ["dev", "a.scss"]);
    assert.equal(posix.segments("/dev/a.scss"), ["dev", "a.scss"]);
    assert.equal(posix.segments("dev/a.scss"), ["dev", "a.scss"])
}

/// The Windows fold is ASCII-only, as dart's is — and the canonical key it
/// is compared against was lowercased with full Unicode rules, so a
/// non-ASCII uppercase letter anywhere in the path defeats relativisation
/// on both implementations alike.
test "the_windows_fold_is_ascii_only" {
    // the non-ASCII segment does not fold, so the walk leaves the directory
    assert.equal(
        rel(root.pathstyle.Style.Windows, "C:\\dev\\ÄRGER", "c:\\dev\\ärger\\a.scss"),
        "..\\ärger\\a.scss",
    )
}

/// #146, as the first Windows CI run reported it: the canonical key is
/// lowercased and the working directory is not, and the display used to
/// fall all the way through to the absolute temp path.
test "a_loaded_file_under_a_mixed_case_windows_cwd_is_relative" {
    assert.equal(
        root.pathstyle.pretty(
            root.pathstyle.Style.Windows,
            "c:\\users\\runner~1\\appdata\\local\\temp\\sasso_frames\\src\\sub\\_warnme.scss",
            "C:\\Users\\RUNNER~1\\AppData\\Local\\Temp\\sasso_frames",
        ),
        "src\\sub\\_warnme.scss",
    )
}

/// dart writes the relative spelling in the platform's style, so a frame is
/// `\`-separated on Windows and `/`-separated everywhere else — and that is
/// true of the entry stylesheet's frame too, however it was typed on the
/// command line (#151).
test "the_separator_is_the_platforms" {
    assert.equal(
        root.pathstyle.pretty(root.pathstyle.Style.Posix, "/dev/app/src/sub/a.scss", "/dev/app"),
        "src/sub/a.scss",
    );
    assert.equal(
        root.pathstyle.pretty(
            root.pathstyle.Style.Windows,
            "C:\\dev\\app\\src\\sub\\a.scss",
            "C:\\dev\\app",
        ),
        "src\\sub\\a.scss",
    )
}

/// dart's `p.prettyUri` prefers the ABSOLUTE path once the relative one
/// would have more segments — a file far outside the tree reads better as
/// itself than as a stack of `..`. The root counts as one segment, so a
/// path one level out of the tree is a tie and the relative form wins it.
test "a_file_far_outside_the_tree_stays_absolute" {
    // 5 `..` + 2 segments = 7 against 1 + 2 = 3: absolute.
    assert.equal(
        root.pathstyle.pretty(
            root.pathstyle.Style.Posix,
            "/tmp/scratch/a.scss",
            "/dev/app/deep/deeper/deepest",
        ),
        "/tmp/scratch/a.scss",
    );
    // 1 `..` + 2 segments = 3 against 1 + 3 = 4: relative.
    assert.equal(
        root.pathstyle.pretty(root.pathstyle.Style.Posix, "/dev/src/a.scss", "/dev/app"),
        "../src/a.scss",
    )
}

/// A different drive has no relative spelling, so it is shown as it is
/// rather than as a `..` chain that would resolve somewhere else entirely.
test "another_drive_is_shown_absolute" {
    assert.equal(
        root.pathstyle.pretty(root.pathstyle.Style.Windows, "D:\\lib\\a.scss", "C:\\dev\\app"),
        "D:\\lib\\a.scss",
    )
}

/// dart's `p.relative(x, from: x)` is `.`, not the empty string — which is
/// what joining no segments at all would produce.
test "a_path_that_is_the_working_directory_is_a_dot" {
    assert.equal(root.pathstyle.pretty(root.pathstyle.Style.Posix, "/dev/app", "/dev/app"), ".");
    assert.equal(
        root.pathstyle.pretty(root.pathstyle.Style.Windows, "C:\\dev\\app", "c:\\dev\\app"),
        ".",
    );
    // The root itself, where there are no segments on either side.
    assert.equal(root.pathstyle.pretty(root.pathstyle.Style.Posix, "/", "/"), ".")
}

/// A `file://` URL is what the JS API hands the compiler, because its
/// importer bridge resolves relative `@use` against it. Every frame it
/// appears in used to print it verbatim, scheme and all.
test "a_file_url_names_the_path_it_points_at" {
    assert.equal(
        root.pathstyle.file_url_path(root.pathstyle.Style.Posix, "file:///a/b/c.scss"),
        "/a/b/c.scss",
    );
    assert.equal(
        root.pathstyle.file_url_path(root.pathstyle.Style.Windows, "file:///C:/a/b.scss"),
        "C:\\a\\b.scss",
    );
    // A UNC share has no POSIX spelling, so POSIX declines rather than
    // inventing one.
    assert.equal(
        root.pathstyle.file_url_path(root.pathstyle.Style.Windows, "file://server/share/a.scss"),
        "\\\\server\\share\\a.scss",
    );
    assert.equal(
        root.pathstyle.file_url_path(root.pathstyle.Style.Posix, "file://server/share/a.scss"),
        null,
    );
    // Not a file URL at all.
    assert.equal(
        root.pathstyle.file_url_path(root.pathstyle.Style.Posix, "data:;base64,YQ=="),
        null,
    );
    assert.equal(root.pathstyle.file_url_path(root.pathstyle.Style.Posix, "/a/b.scss"), null);
    // `localhost` is this machine, exactly as the empty authority is.
    // The napi copy of this decoder accepted it while this one did not,
    // which is how an entry spelled that way was read happily and then
    // printed as a URL in the frame (#161, #163).
    assert.equal(
        root.pathstyle.file_url_path(root.pathstyle.Style.Posix, "file://localhost/a/b.scss"),
        "/a/b.scss",
    );
    assert.equal(
        root.pathstyle.file_url_path(root.pathstyle.Style.Windows, "file://localhost/C:/a.scss"),
        "C:\\a.scss",
    );
    // Nothing after the authority is not a path.
    assert.equal(root.pathstyle.file_url_path(root.pathstyle.Style.Posix, "file://"), null)
}

/// What this decoder hands back is ROOTED, in either style.
///
/// The napi bridge asks "is this usable as a filesystem base" and used
/// to answer by looking for a leading `/` — which reads `C:\a` and
/// `\\server\share` as relative, so on Windows a `file:///C:/…`
/// containing URL resolved nothing and every relative `@use` fell
/// through to the load paths. It asks the host now (#163).
///
/// The host check itself cannot be exercised off its host. This can:
/// it pins the half that decides the answer, which is that the decoder
/// produces something each style calls rooted.
test "what_it_decodes_is_rooted_in_its_own_style" {
    let cases: root.std.Tuple2<root.pathstyle.Style, string>[] = [
        root.std.Tuple2<root.pathstyle.Style, string> {
            _0: root.pathstyle.Style.Posix,
            _1: "file:///a/b.scss",
        },
        root.std.Tuple2<root.pathstyle.Style, string> {
            _0: root.pathstyle.Style.Posix,
            _1: "file://localhost/a/b.scss",
        },
        root.std.Tuple2<root.pathstyle.Style, string> {
            _0: root.pathstyle.Style.Windows,
            _1: "file:///C:/a/b.scss",
        },
        root.std.Tuple2<root.pathstyle.Style, string> {
            _0: root.pathstyle.Style.Windows,
            _1: "file://localhost/C:/a.scss",
        },
        root.std.Tuple2<root.pathstyle.Style, string> {
            _0: root.pathstyle.Style.Windows,
            _1: "file://server/share/a.scss",
        },
    ];
    for (let case in cases) {
        let style = case._0;
        let url = case._1;
        let p = root.std.expect(root.pathstyle.file_url_path(style, url), "decodes");
        // {url:?} decoded to {p:?}, which {style:?} does not call rooted
        assert.is_true(style.root_len(p) > 0);
    }
}

/// A directory with a space arrives percent-encoded. A frame naming
/// `my%20docs` names a file nobody has.
test "percent_escapes_are_decoded" {
    assert.equal(
        root.pathstyle.file_url_path(root.pathstyle.Style.Posix, "file:///my%20docs/a%2Bb.scss"),
        "/my docs/a+b.scss",
    );
    // A stray `%` is a literal one, as `Uri.toFilePath` treats it.
    assert.equal(
        root.pathstyle.file_url_path(root.pathstyle.Style.Posix, "file:///100%/a.scss"),
        "/100%/a.scss",
    );
    // Multi-byte UTF-8 survives being split across escapes.
    assert.equal(
        root.pathstyle.file_url_path(root.pathstyle.Style.Posix, "file:///%E6%A8%A3/a.scss"),
        "/樣/a.scss",
    )
}

/// The whole point: both front ends' spellings of one file produce the
/// same frame. The binary passes a path, the JS API passes a URL.
test "both_front_ends_name_a_file_the_same_way" {
    let cwd = "/work/proj";
    assert.equal(
        root.pathstyle.pretty_name(root.pathstyle.Style.Posix, "file:///work/proj/src/a.scss", cwd),
        "src/a.scss",
    );
    assert.equal(
        root.pathstyle.pretty_name(root.pathstyle.Style.Posix, "/work/proj/src/a.scss", cwd),
        "src/a.scss",
    );
    // And on Windows, where the drive letter is the root.
    assert.equal(
        root.pathstyle.pretty_name(
            root.pathstyle.Style.Windows,
            "file:///C:/work/proj/src/a.scss",
            "C:\\work\\proj",
        ),
        "src\\a.scss",
    )
}

/// `wasm32-unknown-unknown` has no `getcwd`, so the host may have nothing
/// to offer. An absolute path is better than a URL even unrelativised.
test "without_a_cwd_it_is_still_a_path_not_a_url" {
    assert.equal(
        root.pathstyle.pretty_name(root.pathstyle.Style.Posix, "file:///work/proj/src/a.scss", null),
        "/work/proj/src/a.scss",
    )
}

/// Only a name that is absolute is ours to respell. A relative one is
/// either already the spelling the caller wanted (the binary hands one
/// over pre-made) or a custom importer's key, and a name carrying another
/// scheme belongs to an importer outright.
///
/// The first version of this asserted that a relative name came back
/// UNCHANGED — the same string a caller gets by declining, so it read as
/// correct while hiding the difference that matters to
/// `module_diag_url`, whose rule for a relative key is its LAST SEGMENT.
/// The test codified the bug.
test "only_an_absolute_name_is_ours_to_respell" {
    assert.equal(
        root.pathstyle.pretty_name(root.pathstyle.Style.Posix, "src/a.scss", "/work"),
        null,
    );
    assert.equal(
        root.pathstyle.pretty_name(root.pathstyle.Style.Posix, "data:;base64,YQ==", "/work"),
        null,
    );
    assert.equal(
        root.pathstyle.pretty_name(root.pathstyle.Style.Posix, "npm:foo/bar.scss", "/work"),
        null,
    );
    assert.equal(
        root.pathstyle.pretty_name(root.pathstyle.Style.Posix, "/work/src/a.scss", "/work"),
        "src/a.scss",
    )
}

/// A one-letter "scheme" is a Windows drive. Read the other way, every
/// Windows path is a URL and no frame on Windows names a file.
test "a_drive_letter_is_not_a_scheme" {
    assert.is_true(!root.pathstyle.has_scheme("C:\\work\\a.scss"));
    assert.is_true(!root.pathstyle.has_scheme("C:/work/a.scss"));
    assert.is_true(root.pathstyle.has_scheme("data:;base64,YQ=="));
    assert.is_true(root.pathstyle.has_scheme("file:///a"));
    assert.is_true(root.pathstyle.has_scheme("npm:foo"));
    assert.equal(
        root.pathstyle.pretty_name(
            root.pathstyle.Style.Windows,
            "C:\\work\\proj\\src\\a.scss",
            "C:\\work\\proj",
        ),
        "src\\a.scss",
    )
}

/// dart keeps the absolute spelling once the relative one costs more
/// segments — `pretty` already does this, and a URL must not escape it.
test "a_url_far_outside_the_tree_stays_absolute" {
    let far = root.pathstyle.pretty_name(
        root.pathstyle.Style.Posix,
        "file:///a.scss",
        "/work/proj/deep/deeper",
    );
    assert.equal(far, "/a.scss");
    assert.equal(
        root.pathstyle.pretty(root.pathstyle.Style.Posix, "/a.scss", "/work/proj/deep/deeper"),
        "/a.scss",
    )
}

/// `file://localhost/a` is the same file as `file:///a` (RFC 8089), and
/// the importer's own decoder in `napi` already accepts it — so a frame
/// that declined it printed the URL for a file the compiler had happily
/// read.
test "the_localhost_authority_is_the_local_machine" {
    assert.equal(
        root.pathstyle.file_url_path(root.pathstyle.Style.Posix, "file://localhost/a/b.scss"),
        "/a/b.scss",
    );
    assert.equal(
        root.pathstyle.file_url_path(root.pathstyle.Style.Windows, "file://localhost/C:/a/b.scss"),
        "C:\\a\\b.scss",
    );
    assert.equal(
        root.pathstyle.pretty_name(
            root.pathstyle.Style.Posix,
            "file://localhost/work/proj/src/a.scss",
            "/work/proj",
        ),
        "src/a.scss",
    );
    // Any OTHER authority is still a UNC share, or nothing.
    assert.equal(
        root.pathstyle.file_url_path(root.pathstyle.Style.Posix, "file://server/share/a.scss"),
        null,
    )
}

/// A custom importer's canonical key can be relative and is not a path.
/// `module_diag_url` shows its last segment; answering with the whole key
/// would quietly change every such frame.
test "a_relative_key_is_not_a_path_to_relativise" {
    assert.equal(
        root.pathstyle.pretty_name(root.pathstyle.Style.Posix, "virtual/foo.scss", "/work"),
        null,
    );
    assert.equal(root.pathstyle.pretty_name(root.pathstyle.Style.Posix, "foo.scss", "/work"), null);
    assert.equal(
        root.pathstyle.pretty_name(root.pathstyle.Style.Windows, "virtual\\foo.scss", "C:\\work"),
        null,
    );
    // An absolute one still answers.
    assert.is_true(
        root.pathstyle.pretty_name(root.pathstyle.Style.Posix, "/work/virtual/foo.scss", "/work")
            != null,
    )
}

/// The wasm module is `wasm32-unknown-unknown`, so `HOST` is `Posix` in it
/// even when it is running on Windows node — where the host hands it
/// `C:\work` and `file:///C:/work/a.scss`. Read by POSIX rules those come
/// out as `/C:/work/a.scss`, which is neither the path nor what the addon
/// on the same machine prints.
test "the_spelling_decides_the_style_not_the_build" {
    assert.equal(
        root.pathstyle.style_for("C:\\work\\proj", "file:///C:/work/proj/a.scss"),
        root.pathstyle.Style.Windows,
    );
    assert.equal(
        root.pathstyle.style_for("\\\\server\\share", "file://server/share/a.scss"),
        root.pathstyle.Style.Windows,
    );
    // Whatever this build is, a POSIX working directory is read as POSIX.
    assert.equal(
        root.pathstyle.style_for("/work/proj", "file:///work/proj/a.scss"),
        root.pathstyle.HOST(),
    );
    // With no cwd the name is all there is to go on.
    assert.equal(
        root.pathstyle.style_for(null, "file:///C:/work/a.scss"),
        root.pathstyle.Style.Windows,
    );
    assert.equal(root.pathstyle.style_for(null, "file:///work/a.scss"), root.pathstyle.HOST());

    // The whole point, spelled out: the Windows answer, from a build whose
    // HOST is POSIX.
    assert.equal(
        root.pathstyle.pretty_name(
            root.pathstyle.style_for("C:\\work\\proj", "file:///C:/work/proj/src/a.scss"),
            "file:///C:/work/proj/src/a.scss",
            "C:\\work\\proj",
        ),
        "src\\a.scss",
    )
}

/// A UNC file URL carries its platform in the authority, and that is the
/// only clue when no working directory was supplied — the legacy no-cwd
/// wasm ABI, or an embedder that sets none. Read as POSIX it has no
/// spelling at all, so the frame printed the URL.
test "a_unc_url_is_windows_even_with_no_cwd" {
    assert.equal(
        root.pathstyle.style_for(null, "file://server/share/a.scss"),
        root.pathstyle.Style.Windows,
    );
    assert.equal(
        root.pathstyle.pretty_name(
            root.pathstyle.style_for(null, "file://server/share/a.scss"),
            "file://server/share/a.scss",
            null,
        ),
        "\\\\server\\share\\a.scss",
    );
    // `localhost` is the local machine, not a share: it must NOT flip the
    // style, or every plain file URL on POSIX would be read as Windows.
    assert.equal(root.pathstyle.style_for(null, "file://localhost/a/b.scss"), root.pathstyle.HOST());
    assert.equal(root.pathstyle.style_for(null, "file:///a/b.scss"), root.pathstyle.HOST())
}

/// The drive letter can arrive percent-encoded, and `file_url_path`
/// decodes — so inferring the style from the RAW text disagreed with the
/// function it was choosing the style for: `file:///C%3A/work/a.scss`
/// came out as the POSIX path `/C:/work/a.scss`.
test "an_encoded_drive_letter_is_still_a_drive" {
    assert.equal(
        root.pathstyle.style_for(null, "file:///C%3A/work/a.scss"),
        root.pathstyle.Style.Windows,
    );
    assert.equal(
        root.pathstyle.pretty_name(
            root.pathstyle.style_for(null, "file:///C%3A/work/a.scss"),
            "file:///C%3A/work/a.scss",
            null,
        ),
        "C:\\work\\a.scss",
    )
}
