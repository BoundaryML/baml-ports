// Ported from sasso `src/lib.rs` `#[cfg(test)] mod file_url_tests`
// (namespace `root.file_url_tests`).
//
// The two readings of one `file:` URL decoder, and why they differ.
//
// `pathstyle::file_url_path` produces a name to SHOW; `file_url_to_path`
// produces a path to OPEN. Everything else about them — the `file://`
// prefix, the empty and `localhost` authorities, percent escapes, a
// Windows drive letter, a UNC authority — is one function since #163,
// after two copies of it had drifted apart twice.
//
// Here rather than in `pathstyle.rs` because that file is also compiled
// into the BINARY (see `main.rs`), where `crate::` is the bin root and
// has no `file_url_to_path`.
//
// PORT: `use crate::pathstyle::{file_url_path, Style, HOST}` — reached as
// `root.pathstyle.*`; `super::file_url_to_path` is `root.file_url_to_path`.

test "an_undecodable_byte_is_shown_and_not_opened" {
    // Shown with the replacement character: a frame naming the file is
    // still better than no frame.
    //
    // Both styles spelled out rather than `HOST`, which is the whole
    // point of `Style` being a value: an assertion written against the
    // host passes here and fails on the Windows job, where the same
    // URL comes back `\a\u{fffd}b.scss`.
    assert.equal(
        root.pathstyle.file_url_path(root.pathstyle.Style.Posix, "file:///a%FFb.scss"),
        "/a�b.scss",
    );
    assert.equal(
        root.pathstyle.file_url_path(root.pathstyle.Style.Windows, "file:///a%FFb.scss"),
        "\\a�b.scss",
    );
    // …and refused for opening, because a name with U+FFFD substituted
    // into it is a different name. Host-independent: the strict reading
    // fails at the UTF-8 step, before any separator is chosen.
    assert.equal(root.file_url_to_path("file:///a%FFb.scss"), null)
}

test "and_they_agree_about_everything_decodable" {
    for (
        let url in [
            "file:///a/b.scss",
            "file://localhost/a/b.scss",
            "file:///my%20docs/a.scss",
            "data:;base64,YQ==",
            "file://",
            "/a/b.scss",
        ]
    ) {
        // the two readings disagreed about {url}
        assert.equal(
            root.pathstyle.file_url_path(root.pathstyle.HOST(), url),
            root.file_url_to_path(url),
        );
    }
}
