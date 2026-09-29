// Ported from sasso `src/localtime/mod.rs` (namespace `root.localtime`).
//
// Local wall-clock time, with no dependencies and no `unsafe`.
//
// `--update` and `--watch` each print one line per file they write, and
// dart-sass stamps it with the local time:
//
// ```text
// [2026-09-19 12:58:07] Compiled src/one.scss to out/one.css.
// ```
//
// `std` gives UTC seconds and nothing else — no calendar, no timezone — so
// that stamp has to come from somewhere. The options, measured on
// 2026-09-19:
//
// | route | dependencies | `unsafe` |
// |---|---|---|
// | `jiff` | 2 crates | none of ours |
// | `chrono` | 5 crates | none of ours |
// | `time` | 8 crates | none of ours |
// | declaring `localtime_r` ourselves | none | yes |
// | reading the tz database ourselves | none | none |
//
// This is the last row. It is not an exotic choice: it is what `jiff` does
// internally (it reads `/usr/share/zoneinfo` rather than calling libc), and
// what the `tz-rs` crate exists to provide. Calling `localtime_r` directly
// is the route the ecosystem has been moving away from since
// RUSTSEC-2020-0159, and it would also be the second exception to this
// crate's one-audited-`unsafe`-module rule, with no way to check it under
// Miri.
//
// # Shape
//
// Four modules, split so that only one of them can fail in a way that
// depends on the machine it runs on:
//
// - [`civil`] — calendar arithmetic. Pure.
// - [`posix`] — the POSIX TZ string. Pure.
// - [`tzif`] — the TZif binary format. Pure, borrows its input, allocates
//   nothing, never panics on malformed bytes.
// - [`sys`] — reads `/etc/localtime` or `$TZ`. The only I/O, and the only
//   platform `cfg`.
//
// Nothing here refers to anything else in sasso, by design: if this grows
// past being a timestamp for one log line it should leave and become its
// own crate, and that should be a move rather than a rewrite.
//
// # Windows
//
// There is no TZif file to read, so [`local_stamp`] returns `None` and the
// caller prints the line without its bracket. Correct-but-absent beats
// present-but-wrong, and the alternatives — FFI to `GetLocalTime`, or
// embedding the whole tz database as `jiff` does at ~427 KB — are both too
// much for one line. Worth revisiting when there is Windows CI to test it
// on (#85).
//
// # How this is known to be right
//
// The reader agrees with Python's `zoneinfo` on **every zone the system
// ships, at twelve instants each** — 598 zones, 7176 checks, on macOS and
// on Linux/glibc (2026-09-19). The instants are chosen to be awkward: DST
// transition seconds, half-hour and 45-minute zones, the southern
// hemisphere, 1906, 1944, 2065 in both summer and winter, and 2100.
//
// That sweep found a bug in the reference rather than in the reader: for
// the three Greenland zones, whose footer uses angle-bracket abbreviations
// (`<-02>2<-01>,M3.5.0/-1,M10.5.0/0`), macOS's own `date` stops applying
// the footer past 2037 and reports standard time all year. `zoneinfo`
// agrees with us.
//
// That sweep is `#[ignore]`d — it needs the host's zoneinfo and a Python to
// disagree with, neither of which the everyday suite should depend on — and
// CI opts in with `cargo test --bin sasso -- --ignored`. What runs on every
// `cargo test` are the vendored-fixture tests, which need no oracle, no
// tzdata on the host, and give the same answer in five years when these
// zones' rules have moved on.

// Local wall-clock time, with no dependencies and no `unsafe`.
//
// `--update` and `--watch` each print one line per file they write, and
// dart-sass stamps it with the local time:
//
// ```text
// [2026-09-19 12:58:07] Compiled src/one.scss to out/one.css.
// ```
//
// `std` gives UTC seconds and nothing else — no calendar, no timezone — so
// that stamp has to come from somewhere. The options, measured on
// 2026-09-19:
//
// | route | dependencies | `unsafe` |
// |---|---|---|
// | `jiff` | 2 crates | none of ours |
// | `chrono` | 5 crates | none of ours |
// | `time` | 8 crates | none of ours |
// | declaring `localtime_r` ourselves | none | yes |
// | reading the tz database ourselves | none | none |
//
// This is the last row. It is not an exotic choice: it is what `jiff` does
// internally (it reads `/usr/share/zoneinfo` rather than calling libc), and
// what the `tz-rs` crate exists to provide. Calling `localtime_r` directly
// is the route the ecosystem has been moving away from since
// RUSTSEC-2020-0159, and it would also be the second exception to this
// crate's one-audited-`unsafe`-module rule, with no way to check it under
// Miri.
//
// # Shape
//
// Four modules, split so that only one of them can fail in a way that
// depends on the machine it runs on:
//
// - [`civil`] — calendar arithmetic. Pure.
// - [`posix`] — the POSIX TZ string. Pure.
// - [`tzif`] — the TZif binary format. Pure, borrows its input, allocates
//   nothing, never panics on malformed bytes.
// - [`sys`] — reads `/etc/localtime` or `$TZ`. The only I/O, and the only
//   platform `cfg`.
//
// Nothing here refers to anything else in sasso, by design: if this grows
// past being a timestamp for one log line it should leave and become its
// own crate, and that should be a move rather than a rewrite.
//
// # Windows
//
// There is no TZif file to read, so [`local_stamp`] returns `None` and the
// caller prints the line without its bracket. Correct-but-absent beats
// present-but-wrong, and the alternatives — FFI to `GetLocalTime`, or
// embedding the whole tz database as `jiff` does at ~427 KB — are both too
// much for one line. Worth revisiting when there is Windows CI to test it
// on (#85).
//
// # How this is known to be right
//
// The reader agrees with Python's `zoneinfo` on **every zone the system
// ships, at twelve instants each** — 598 zones, 7176 checks, on macOS and
// on Linux/glibc (2026-09-19). The instants are chosen to be awkward: DST
// transition seconds, half-hour and 45-minute zones, the southern
// hemisphere, 1906, 1944, 2065 in both summer and winter, and 2100.
//
// That sweep found a bug in the reference rather than in the reader: for
// the three Greenland zones, whose footer uses angle-bracket abbreviations
// (`<-02>2<-01>,M3.5.0/-1,M10.5.0/0`), macOS's own `date` stops applying
// the footer past 2037 and reports standard time all year. `zoneinfo`
// agrees with us.
//
// That sweep is `#[ignore]`d — it needs the host's zoneinfo and a Python to
// disagree with, neither of which the everyday suite should depend on — and
// CI opts in with `cargo test --bin sasso -- --ignored`. What runs on every
// `cargo test` are the vendored-fixture tests, which need no oracle, no
// tzdata on the host, and give the same answer in five years when these
// zones' rules have moved on.
// `civil` is wanted everywhere a stamp is printed — it turns "UTC seconds
// plus an offset" into a date, and that arithmetic is the same whoever
// supplied the offset. The other three read the tz database, which only a
// POSIX machine has, and on any other target they would be dead code that
// `-D warnings` is right to reject.
// mod civil → namespace `root.localtime.civil`

// mod posix → namespace `root.localtime.posix`

// mod sys → namespace `root.localtime.sys`

// mod tzif → namespace `root.localtime.tzif`

/// What the machine says about its zone, resolved at most once per process.
///
/// A directory build asks for a timestamp once per written file — thousands
/// of times for a large tree — and re-reading `/etc/localtime` each time
/// would be silly. Parsing, by contrast, is left per call: it is a header
/// read and a binary search over a borrowed slice, with no allocation, so
/// caching the parse would buy nothing and would need a self-referential
/// struct to hold it.
///
/// The consequence worth stating: a change to the machine's timezone, or to
/// `TZ`, is not picked up by a running `--watch`. Neither is it by dart.
// PORT: the process-wide `OnceLock` cache is dropped (BAML has no globals):
// the zone is resolved on every call.
function loaded() -> root.localtime.sys.Loaded {
    root.localtime.sys.load()
}

/// The UTC offset in seconds east of Greenwich at `unix_secs`, or `None`
/// when no zone can be determined at all.
///
/// `Some(0)` and `None` are different answers and the distinction is the
/// point: `TZ=` asks for UTC and gets it, while a machine that has a local
/// zone we cannot read (Windows) gets nothing, so the caller prints no
/// time rather than a confident wrong one.
// PORT: the `#[cfg(unix)]` variant; the Windows (chrono) and wasm variants
// are not ported.
function local_offset_at(unix_secs: int) -> int? {
    match (loaded()) {
        root.localtime.sys.Loaded_Utc {} => 0,
        root.localtime.sys.Loaded_Tzif { _0: let bytes } => {
            let tz = root.localtime.tzif.TimeZone.parse(bytes)
                ?? return null;
            tz.offset_at(unix_secs)
        },
        root.localtime.sys.Loaded_Nothing {} => null,
        _ => root.std.unreachable(),
    }
}

/// dart-sass's stamp for `unix_secs`: `[YYYY-MM-DD HH:MM:SS]`, local time to
/// the second. `None` when the local offset cannot be determined, which the
/// caller renders as no stamp at all rather than as a wrong one.
///
/// # Why seconds, when `sass` from npm prints none
///
/// dart-sass builds the stamp by stripping a fixed SEVEN characters off
/// `DateTime.now().toString()` (`sass.dart.js` around the `"Compiled "`
/// line):
///
/// ```js
///   nowStr = DateTime.now().toString();
///   timestamp = nowStr.substring(0, nowStr.length - 7);
/// ```
///
/// Seven is `.` plus six microsecond digits, which is what the Dart VM
/// prints. dart2js prints three fractional digits, so on the npm build the
/// slice eats `:SS` as well:
///
/// ```text
///   VM       2026-09-22 23:36:00.123456   len 26   -> 2026-09-22 23:36:00
///   dart2js  2026-09-22 23:36:00.123      len 23   -> 2026-09-22 23:36
/// ```
///
/// So the two distributions of ONE dart version disagree, and the shorter
/// one is a truncation bug rather than a format: the code intends to drop a
/// fractional part and keep the seconds. Measured on macOS, same machine,
/// same second (#190):
///
/// ```text
///   dart native (macos-arm64 release)   [2026-09-22 23:36:00]
///   dart npm    (dart2js)               [2026-09-22 23:36]
/// ```
///
/// sasso matched the npm build, because every dart measurement in this repo
/// is taken against it. It matches dart's INTENT now, which is also what a
/// Windows user sees, and what `brew install sass` gives you.
function local_stamp(unix_secs: int) -> string? {
    format_stamp(
        root.localtime.civil.civil_from_unix(
            unix_secs
                + (
                    local_offset_at(unix_secs)
                        ?? return null
                ),
        ),
    )
}

/// The bracket itself, split out so the fixture test below asserts against
/// THIS rather than against a second `format!` written to match it. The two
/// had to agree by inspection before; now there is only one.
function format_stamp(c: root.localtime.civil.Civil) -> string {
    `[${root.std.zero_pad(c.year, 4)}-${root.std.zero_pad(c.month, 2)}-${root.std.zero_pad(c.day, 2)} ${root.std.zero_pad(c.hour, 2)}:${root.std.zero_pad(c.minute, 2)}:${root.std.zero_pad(c.second, 2)}]`
}

/// Seconds since the Unix epoch, or 0 if the system clock predates it.
function now() -> int {
    // PORT: `SystemTime::now().duration_since(UNIX_EPOCH)` is the wall clock
    // in nanoseconds; a pre-epoch clock (the `Err` case) gives 0.
    let nanos = root.std.now_nanos();
    if (nanos < 0n) {
        0
    } else {
        root.std.int_of(nanos / 1000000000n)
    }
}
