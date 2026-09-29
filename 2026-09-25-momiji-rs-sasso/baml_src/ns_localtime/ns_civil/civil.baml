// Ported from sasso `src/localtime/civil.rs` (namespace `root.localtime.civil`).
//
// Calendar arithmetic: Unix seconds to a civil date and back.
//
// No I/O, no timezone knowledge, no allocation — give it a count of seconds
// and it gives you the fields. Everything timezone-aware is a matter of
// adding an offset before calling in here.
//
// The two conversions are Howard Hinnant's `civil_from_days` and
// `days_from_civil`, the same pair every date library uses underneath. They
// are exact for the whole `i64` range and have no leap-year special cases
// beyond the formulas themselves, which is why they are worth copying
// rather than reinventing with `if` statements.

// Calendar arithmetic: Unix seconds to a civil date and back.
//
// No I/O, no timezone knowledge, no allocation — give it a count of seconds
// and it gives you the fields. Everything timezone-aware is a matter of
// adding an offset before calling in here.
//
// The two conversions are Howard Hinnant's `civil_from_days` and
// `days_from_civil`, the same pair every date library uses underneath. They
// are exact for the whole `i64` range and have no leap-year special cases
// beyond the formulas themselves, which is why they are worth copying
// rather than reinventing with `if` statements.
// Half of this module exists for the POSIX TZ-string reader, which only a
// machine with a tz database needs (`posix` is `#[cfg(unix)]`). Off POSIX
// the stamp's offset comes from the platform instead, so `civil_from_unix`
// is the only entry point a lib or bin build reaches and the other four read
// as dead.
//
// Allowed rather than `#[cfg(unix)]`-gated, because they are NOT dead in a
// test build on any platform: the calendar tests below are pure, need no tz
// database, and are exactly the kind that should run everywhere — gating the
// functions would take the tests with them.
/// A civil date and time, with no zone attached.
class Civil {
    year: int,
    month: int,
    day: int,
    hour: int,
    minute: int,
    second: int,
}

/// Days since 1970-01-01 to `(year, month, day)`.
function civil_from_days(z: int) -> root.std.Tuple3<int, int, int> {
    // Shift the epoch to 0000-03-01 so leap days land at the end of the
    // 400-year cycle and the month formula below stays branch-free.
    let z = z + 719468;
    let era = (
        if (z >= 0) {
            z
        } else {
            z - 146096
        }
    )
        / 146097;
    let doe = z - era * 146097; // day of era, [0, 146096]
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365; // [0, 399]
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100); // day of year, [0, 365]
    let mp = (5 * doy + 2) / 153; // month, March-based, [0, 11]
    let d = doy - (153 * mp + 2) / 5 + 1; // [1, 31]
    let m = if (mp < 10) {
        mp + 3
    } else {
        mp - 9
    }; // [1, 12]
    root.std.Tuple3 {
        _0: if (m <= 2) {
            y + 1
        } else {
            y
        },
        _1: m,
        _2: d,
    }
}

/// `(year, month, day)` to days since 1970-01-01. The exact inverse of
/// [`civil_from_days`].
function days_from_civil(y: int, m: int, d: int) -> int {
    let y = if (m <= 2) {
        y - 1
    } else {
        y
    };
    let era = (
        if (y >= 0) {
            y
        } else {
            y - 399
        }
    )
        / 400;
    let yoe = y - era * 400;
    let mp = if (m > 2) {
        m - 3
    } else {
        m + 9
    };
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146097 + doe - 719468
}

/// Day of the week, 0 = Sunday. 1970-01-01 was a Thursday, hence the `+ 4`.
function weekday(days: int) -> int {
    root.std.rem_euclid(days + 4, 7)
}

function is_leap(y: int) -> bool {
    (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
}

/// Days in `month` of `year`, 1-based month.
function days_in_month(year: int, month: int) -> int {
    // PORT: the function-local `const LENGTHS` is a local array.
    let LENGTHS: int[] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if (month == 2 && is_leap(year)) {
        29
    } else {
        LENGTHS[month - 1]
    }
}

/// Split a count of seconds since the epoch into civil fields. The caller
/// has already added whatever UTC offset applies, so this is "local" only in
/// the sense that it does not add one itself.
function civil_from_unix(secs: int) -> Civil {
    let days = root.std.div_euclid(secs, 86400);
    let rem = root.std.rem_euclid(secs, 86400);
    let ymd = civil_from_days(days);
    let year = ymd._0;
    let month = ymd._1;
    let day = ymd._2;
    Civil {
        year: year,
        month: month,
        day: day,
        hour: rem / 3600,
        minute: rem % 3600 / 60,
        second: rem % 60,
    }
}
