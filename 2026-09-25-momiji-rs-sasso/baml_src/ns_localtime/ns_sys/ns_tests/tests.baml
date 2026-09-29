// Ported from sasso `src/localtime/sys.rs` `mod tests` (namespace `root.localtime.sys.tests`).
//
// PORT: `use super::*;` → items of `root.localtime.sys` are written fully qualified.
// PORT: `#[cfg(all(test, unix))]` — the unix build is the one ported.

function file(p: string) -> root.localtime.sys.Source {
    root.localtime.sys.Source_File { _0: p }
}

test "unset_means_the_system_link" {
    assert.equal(root.localtime.sys.tz_source(null), file("/etc/localtime"))
}

// `TZ=` is a request for UTC, not an absent `TZ`. Measured: `TZ= date`
// and `TZ= sass --update` both report UTC where an unset `TZ` reports
// local time.
test "an_explicitly_empty_tz_is_utc" {
    let utc: root.localtime.sys.Source = root.localtime.sys.Source_Utc {  };
    assert.equal(root.localtime.sys.tz_source(""), utc);
    // a bare colon is the same request
    assert.equal(root.localtime.sys.tz_source(":"), utc)
}

test "a_name_resolves_under_zoneinfo" {
    assert.equal(
        root.localtime.sys.tz_source("Asia/Taipei"),
        file("/usr/share/zoneinfo/Asia/Taipei"),
    );
    // POSIX allows a leading colon and some tools emit one.
    assert.equal(
        root.localtime.sys.tz_source(":Asia/Taipei"),
        file("/usr/share/zoneinfo/Asia/Taipei"),
    );
    // Three components happen (America/Argentina/Salta).
    assert.equal(
        root.localtime.sys.tz_source("America/Argentina/Salta"),
        file("/usr/share/zoneinfo/America/Argentina/Salta"),
    )
}

test "an_absolute_path_is_taken_as_given" {
    assert.equal(root.localtime.sys.tz_source("/etc/localtime"), file("/etc/localtime"))
}

// Reading an arbitrary file because an environment variable said so is
// a bad trade for a timestamp. These resolve to UTC — the same answer
// libc gives for a zone it cannot find — rather than to a read.
test "a_name_cannot_escape_the_zoneinfo_directory" {
    let utc: root.localtime.sys.Source = root.localtime.sys.Source_Utc {  };
    for (
        let bad in [
            "../../../etc/passwd",
            "America/../../etc/passwd",
            ".",
            "..",
            "Asia/./Taipei",
            "Asia//Taipei",
        ]
    ) {
        // TZ={bad:?} must not be read
        assert.equal(root.localtime.sys.tz_source(bad), utc);
    }
}

// Not an assertion about the host's timezone — CI machines are UTC and
// developers are not — only that the lookup reaches something usable.
// The values themselves are checked against vendored fixtures, where
// the expected answer is known.
test "the_system_zone_is_usable" {
    match (root.localtime.sys.load()) {
        root.localtime.sys.Loaded_Utc {} => {},
        root.localtime.sys.Loaded_Nothing {} => {},
        root.localtime.sys.Loaded_Tzif { _0: let bytes } => {
            // the system's own tzdata did not parse ({} bytes)
            assert.is_true(root.localtime.tzif.TimeZone.parse(bytes) != null);
        },
        _ => root.std.unreachable(),
    }
}
