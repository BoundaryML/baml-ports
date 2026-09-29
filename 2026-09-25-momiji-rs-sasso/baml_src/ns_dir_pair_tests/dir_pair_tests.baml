// Ported from sasso `src/main.rs` `#[cfg(test)] mod dir_pair_tests`
// (namespace `root.dir_pair_tests`).
//
// The two directory-relationship rules, asked of BOTH styles.
//
// Item 2 of #172: the case-folding half of `path_key` was covered for
// diagnostic path spelling (`pathstyle`, 29 tests) and for the watch
// snapshot's directory key, but not for the use it was filed about — "is
// this file inside the destination". It was `#[cfg(windows)]`-gated, so a
// POSIX run compiled the other body and had nothing to check.
//
// The POSIX column is measured against dart-sass 1.104.1 on macOS, with a
// stylesheet already sitting in the destination:
//
// ```text
//   sass Src:src/css   ->  src/css/a.css AND src/css/css/old.css
//   sass src:src/css   ->  src/css/a.css only
// ```
//
// The first is the proof that dart does NOT fold case off Windows, even on
// a case-insensitive volume where `Src/` and `src/` are one directory on
// disk: it read the two spellings as two trees, called the destination not
// nested, and mirrored the destination into itself.
//
// PORT: `use super::{dest_nested_in_src, key_inside, path_key_in}` — reached
// as `root.*`; `crate::pathstyle::Style` is `root.pathstyle.Style`; `Path` /
// `PathBuf` are `string`s. The `[(Style, bool); 2]` tables are
// `root.std.Tuple2<root.pathstyle.Style, bool>[]`.

/// A path as the loop would key it. The style is the ONLY thing that
/// differs between platforms here, which is why it is the only thing
/// these tests vary.
function k(style: root.pathstyle.Style, p: string) -> string {
    root.path_key_in(style, p)
}

/// `Src:src/css` — one directory under two spellings.
test "case_decides_nesting_only_under_the_windows_rules" {
    let rows: root.std.Tuple2<root.pathstyle.Style, bool>[] = [
        root.std.Tuple2<root.pathstyle.Style, bool> { _0: root.pathstyle.Style.Windows, _1: true },
        root.std.Tuple2<root.pathstyle.Style, bool> { _0: root.pathstyle.Style.Posix, _1: false },
    ];
    for (let row in rows) {
        let style = row._0;
        let nested = row._1;
        // {style:?}: Src:src/css
        assert.equal(root.dest_nested_in_src(k(style, "/w/Src"), k(style, "/w/src/css")), nested);
    }
}

/// The same fold, for the per-file question the loop asks.
test "a_file_is_inside_the_destination_by_the_same_rules" {
    let rows: root.std.Tuple2<root.pathstyle.Style, bool>[] = [
        root.std.Tuple2<root.pathstyle.Style, bool> { _0: root.pathstyle.Style.Windows, _1: true },
        root.std.Tuple2<root.pathstyle.Style, bool> { _0: root.pathstyle.Style.Posix, _1: false },
    ];
    for (let row in rows) {
        let style = row._0;
        let inside = row._1;
        // {style:?}: is src/css/old.scss under src/CSS
        assert.equal(
            root.key_inside(k(style, "/w/src/CSS"), k(style, "/w/src/css/old.scss")),
            inside,
        );
    }
}

/// …and for "is this file its own destination", which the loop asks as an
/// equality between two keys.
test "a_file_is_its_own_destination_by_the_same_rules" {
    let rows: root.std.Tuple2<root.pathstyle.Style, bool>[] = [
        root.std.Tuple2<root.pathstyle.Style, bool> { _0: root.pathstyle.Style.Windows, _1: true },
        root.std.Tuple2<root.pathstyle.Style, bool> { _0: root.pathstyle.Style.Posix, _1: false },
    ];
    for (let row in rows) {
        let style = row._0;
        let same = row._1;
        // {style:?}: DIR/plain.css vs dir/plain.css
        // PORT: `PathBuf` `==` compares components → `root.std.path_eq`.
        assert.equal(
            root.std.path_eq(k(style, "/w/DIR/plain.css"), k(style, "/w/dir/plain.css")),
            same,
        );
    }
}

/// Equal is not nested, or `sasso dir` (which is `dir:dir`) would skip
/// every file it was asked to compile.
test "a_destination_equal_to_the_source_is_not_nested" {
    let styles: root.pathstyle.Style[] = [root.pathstyle.Style.Posix, root.pathstyle.Style.Windows];
    for (let style in styles) {
        assert.is_true(!root.dest_nested_in_src(k(style, "/w/dir"), k(style, "/w/dir")));
    }
    // …and under Windows, not even spelled differently.
    assert.is_true(
        !root.dest_nested_in_src(
            k(root.pathstyle.Style.Windows, "/w/Dir"),
            k(root.pathstyle.Style.Windows, "/w/dir"),
        ),
    )
}

/// Nesting is by whole components: a sibling whose name merely starts
/// with the source's is not inside it. Without this, `.:cssx` would skip
/// everything under a directory it never writes to.
test "a_prefix_of_a_name_is_not_a_parent" {
    let styles: root.pathstyle.Style[] = [root.pathstyle.Style.Posix, root.pathstyle.Style.Windows];
    for (let style in styles) {
        assert.is_true(!root.dest_nested_in_src(k(style, "/w/src"), k(style, "/w/src2")));
        assert.is_true(!root.key_inside(k(style, "/w/src"), k(style, "/w/src2/a.scss")));
    }
}

/// It is the DESTINATION that bounds the skip, not an intermediate
/// directory: `.:css/deep` still compiles `css/stale.scss`.
test "only_what_is_under_the_destination_is_skipped" {
    let style: root.pathstyle.Style = root.pathstyle.Style.Posix;
    let dest = k(style, "/w/css/deep");
    assert.is_true(root.key_inside(dest, k(style, "/w/css/deep/old.scss")));
    assert.is_true(!root.key_inside(dest, k(style, "/w/css/stale.scss")))
}
