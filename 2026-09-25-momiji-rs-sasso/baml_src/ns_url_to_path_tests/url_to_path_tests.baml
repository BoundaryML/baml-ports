// Ported from sasso `src/main.rs` `#[cfg(test)] mod url_to_path_tests`
// (namespace `root.url_to_path_tests`).
//
// [`url_to_path`], including the arm production cannot reach.
//
// The `file:` arm is unreachable today — `FsImporter` hands back absolute
// paths, so the CLI suite hits it 0 times — which is exactly why it needs
// cases of its own. Dead-but-defensive code that nobody checks is how the
// third copy of the decoder drifted from the other two without anyone
// noticing (#188).
//
// PORT: `use super::url_to_path` — reached as `root.url_to_path`; `PathBuf`
// is a `string`, `Option<PathBuf>` a `string?`. `#[cfg(unix)]` items are the
// host build's (guide §11). Rust raw strings `r"C:\a"` are spelled with
// doubled backslashes.

function at(url: string) -> string? {
    root.url_to_path(url)
}

/// An absolute path, spelled the way THIS platform spells one.
///
/// `/w/a` is not absolute on Windows: `Path::is_absolute` wants a prefix
/// as well as a root there, so a bare rooted path answers `false`. The
/// function under test asks the host (`is_absolute`, and `file_url_to_path`
/// through `pathstyle::HOST`), so its tests have to as well — a POSIX
/// spelling here would pass on this machine and fail the Windows job.
// `#[cfg(unix)]`
// PORT: the `#[cfg(windows)]` twin, `const ABS: &str = r"C:\w\src\a.scss";`,
// is not compiled for the host build.
function ABS() -> string {
    "/w/src/a.scss"
}

/// A decoded `file:` URL, spelled for this platform: `pathstyle` emits
/// `\` under `Style::Windows` and roots a driveless path at `\`.
function want(posix: string) -> string? {
    // `#[cfg(unix)]`
    // PORT: the `#[cfg(windows)]` block, `Some(PathBuf::from(posix.replace('/', "\\")))`,
    // is not compiled for the host build.
    posix
}

/// The arm that actually runs: a canonical IS an absolute path.
test "an_absolute_path_is_its_own_answer" {
    assert.equal(at(ABS()), ABS());
    // …and a relative one names nothing to stat.
    assert.equal(at("src/a.scss"), null);
    assert.equal(at(""), null)
}

/// A custom importer's canonical has no filesystem path, and `--update`
/// reads that as "unknowable input, rebuild".
test "a_non_file_scheme_has_no_path" {
    assert.equal(at("myscheme:thing"), null);
    assert.equal(at("https://example.com/a.scss"), null);
    // `stdin` is the evaluator's synthetic name, not a path.
    assert.equal(at("stdin"), null)
}

/// The `file:` arm, through the shared decoder.
test "a_file_url_decodes_the_way_the_rest_of_the_crate_does" {
    assert.equal(at("file:///w/a.scss"), want("/w/a.scss"));
    // A space arrives percent-encoded; a path that keeps `%20` is a path
    // nobody has.
    assert.equal(at("file:///my%20docs/a.scss"), want("/my docs/a.scss"))
}

/// The drift this file's own copy had, now impossible to have on one side:
/// `localhost` is this machine, exactly as the empty authority is.
test "a_localhost_authority_is_this_machine" {
    assert.equal(at("file://localhost/w/a.scss"), want("/w/a.scss"))
}

/// A UNC authority is a Windows spelling: no such path exists on POSIX,
/// and `None` is the safe answer there for both callers.
// `#[cfg(unix)]`
test "a_unc_authority_is_not_a_posix_path" {
    assert.equal(at("file://server/share/a.scss"), null)
}

/// …and on Windows it IS a path. The copy this file used to carry refused
/// it on every platform, including the one that can open it — which is
/// half of #188 and the half no POSIX machine can check.
// PORT: `#[cfg(windows)]` — not compiled for the macOS/Linux host build the
// port targets (guide §11), where `at` answers `None` (the test above). Kept,
// asserting what `url_to_path` computes on Windows, with the style made
// explicit: a `file:` url goes to `file_url_to_path`, which is the STRICT
// (UTF-8-checked) decode of `pathstyle::file_url_bytes(HOST, url)` — here
// with `Style::Windows` in place of `HOST`.
test "a_unc_authority_is_a_windows_path" {
    let bytes = root.pathstyle.file_url_bytes(root.pathstyle.Style.Windows, "file://server/share/a.scss");
    let windows_at: string? = if (bytes != null) {
        string.from_utf8(bytes)
    } else {
        null
    };
    assert.equal(windows_at, "\\\\server\\share\\a.scss")
}

/// The strings the `#[cfg(windows)]` arms above assert, pinned HERE —
/// on every platform.
///
/// Those arms run on one machine in CI and on none of ours, so their
/// expected values are predictions. `Style` is a value precisely so a
/// prediction like that can be checked anywhere: this asserts the same
/// four answers against `Style::Windows` directly, and it caught the
/// first draft of the UNC arm above, which had `\\\\server` — a raw
/// string does not process escapes, so the literal carried four
/// backslashes where the path has two.
///
/// `want()` is the same rule as a `/` -> `\` replacement, which is why
/// the first three can be written that way and the UNC one cannot.
test "the_windows_arms_expect_what_the_windows_rules_produce" {
    // PORT: `use crate::pathstyle::{file_url_path, Style}` — reached as
    // `root.pathstyle.*`; `.as_deref()` is the identity on a `string?`.
    let win = (url: string) -> string? {
        root.pathstyle.file_url_path(root.pathstyle.Style.Windows, url)
    };
    assert.equal(win("file:///w/a.scss"), "\\w\\a.scss");
    assert.equal(win("file://localhost/w/a.scss"), "\\w\\a.scss");
    assert.equal(win("file:///my%20docs/a.scss"), "\\my docs\\a.scss");
    assert.equal(win("file://server/share/a.scss"), "\\\\server\\share\\a.scss")
}

/// Undecodable bytes are refused rather than substituted: a name with
/// U+FFFD in it is a different name, and this path is about to be
/// `stat`ed.
test "a_name_that_is_not_utf8_is_not_guessed_at" {
    assert.equal(at("file:///w/a%FFb.scss"), null)
}
