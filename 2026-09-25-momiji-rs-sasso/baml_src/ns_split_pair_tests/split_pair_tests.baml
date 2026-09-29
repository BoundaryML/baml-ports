// Ported from sasso `src/main.rs` `#[cfg(test)] mod split_pair_tests`
// (namespace `root.split_pair_tests`).
//
// The drive-letter pair grammar, which had no case anywhere before #172 —
// no `C:\` literal existed under `tests/`, and the rule was `cfg!`-gated, so
// a POSIX run took the false branch and a Windows run had nothing to take.
// Every expectation here is measured against dart-sass 1.104.1; the table in
// [`is_drive_colon`] is the measurement.
//
// PORT: `use super::split_pair` — reached as `root.split_pair`; `PathBuf` is a
// `string`. The `Result<Option<(String, String)>, String>` the table asserts is
// kept as a value: `root.std.Ok<root.std.Tuple2<string, string>?> |
// root.std.Err<string>` (`split_pair` throws a `root.std.StrError` for `Err`).
// Rust raw strings `r"C:\a"` are spelled with doubled backslashes.

/// What `split_pair` said, in a shape a table can assert.
function split(
    arg: string,
) -> root.std.Ok<root.std.Tuple2<string, string>?> | root.std.Err<string> {
    let o = root.split_pair(arg) catch (e) {
        let e: root.std.StrError => {
            return root.std.Err<string> { error: e.message };
        }
    };
    let mapped: root.std.Tuple2<string, string>? = if (o != null) {
        root.std.Tuple2<string, string> { _0: o._0, _1: o._1 }
    } else {
        null
    };
    root.std.Ok<root.std.Tuple2<string, string>?> { value: mapped }
}

function pair(
    a: string,
    b: string,
) -> root.std.Ok<root.std.Tuple2<string, string>?> | root.std.Err<string> {
    root.std.Ok<root.std.Tuple2<string, string>?> {
        value: root.std.Tuple2<string, string> { _0: a, _1: b },
    }
}

test "a_drive_colon_is_part_of_the_path_on_every_platform" {
    // One pair, two drive colons.
    assert.equal(split("C:\\in.scss:C:\\out.css"), pair("C:\\in.scss", "C:\\out.css"));
    // One path, NOT a pair — the whole point of the rule.
    assert.equal(
        split("C:\\in.scss"),
        root.std.Ok<root.std.Tuple2<string, string>?> { value: null },
    );
    // The destination carries the only drive.
    assert.equal(split("in.scss:C:\\out.css"), pair("in.scss", "C:\\out.css"));
    // A lowercase drive is a drive.
    assert.equal(split("c:\\in.scss:c:\\out.css"), pair("c:\\in.scss", "c:\\out.css"));
    // A separator after the colon is not required: `C:in.scss` is
    // drive-relative, and dart reads it as one path too.
    assert.equal(split("C:in.scss"), root.std.Ok<root.std.Tuple2<string, string>?> { value: null })
}

test "a_second_separator_is_still_an_error" {
    let err = (a: string) -> root.std.Ok<root.std.Tuple2<string, string>?> | root.std.Err<string> {
        root.std.Err<string> { error: `"${a}" may only contain one ":".` }
    };
    assert.equal(split("C:\\in.scss:out.css:x"), err("C:\\in.scss:out.css:x"));
    assert.equal(split("in.scss:out.css:x"), err("in.scss:out.css:x"));
    // A digit is not a drive letter, so this splits at index 1 and the
    // destination `\in.scss:out.css` carries the extra colon.
    assert.equal(split("1:\\in.scss:out.css"), err("1:\\in.scss:out.css"))
}

test "a_one_letter_source_is_a_drive_not_a_pair" {
    // The cost of parity, pinned so it cannot regress silently: `a:b` was
    // a working POSIX pair before #172 and is one path now, because `a:`
    // is a drive. dart-sass 1.104.1 answers `Error reading a:b`.
    assert.equal(split("a:b"), root.std.Ok<root.std.Tuple2<string, string>?> { value: null });
    // Two letters is not a drive, so this stays a pair.
    assert.equal(split("ab:b"), pair("ab", "b"));
    // Past the skipped drive colon, the NEXT colon separates: dart
    // answers `Error reading a:b`, naming `a:b` as the source.
    assert.equal(split("a:b:c"), pair("a:b", "c"))
}

test "an_ordinary_pair_is_untouched" {
    assert.equal(split("in.scss:out.css"), pair("in.scss", "out.css"));
    assert.equal(split("src:css"), pair("src", "css"));
    assert.equal(split("in.scss"), root.std.Ok<root.std.Tuple2<string, string>?> { value: null });
    assert.equal(split("/abs/in.scss:/abs/out.css"), pair("/abs/in.scss", "/abs/out.css"))
}

/// `PathBuf` round-trips the spellings above without normalising them —
/// the backslashes are data on POSIX, and this asserts the assertions.
// PORT: `PathBuf::from(s).to_string_lossy()` is `s` itself in the port, where
// a path is a `string`: the round trip is the identity.
test "the_table_above_is_comparing_what_it_thinks" {
    assert.equal("C:\\out.css", "C:\\out.css")
}
