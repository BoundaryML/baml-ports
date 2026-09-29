// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2021 Taneli Hukkinen
// Licensed to PSF under a Contributor Agreement.
//
// BAML port of `tomli/_re.py`.
//
// Differences from the original:
// * BAML has no module-level constants, so every `RE_*` constant is a
//   zero-argument function. It returns the pattern *source*, not a compiled
//   `baml.regex.Regex`, because a compiled regex cannot report its pattern
//   and `re_match_at` needs to wrap it in an anchor.
// * `re.VERBOSE` patterns are written as concatenations of string pieces with
//   the original inline comments kept as BAML comments.
// * Python's `pattern.match(src, pos)` (match anchored at `pos`) has no
//   `baml.regex` equivalent; `re_match_at` emulates it (see there).
// * `functools.lru_cache` has no equivalent (no module-level state), so
//   `cached_tz` is not cached.

function _time_re_str() -> string {
    "([01][0-9]|2[0-3])" // hours
        + ":([0-5][0-9])" // minutes
        + "(?:"
        + ":([0-5][0-9])" // optional seconds
        + "(?:\\.([0-9]{1,6})[0-9]*)?" // optional fractions of a second
        + ")?"
}

function RE_NUMBER() -> string {
    (
        "0"
            + "(?:"
            + "x[0-9A-Fa-f](?:_?[0-9A-Fa-f])*" // hex
            + "|"
            + "b[01](?:_?[01])*" // bin
            + "|"
            + "o[0-7](?:_?[0-7])*" // oct
            + ")"
            + "|"
            + "[+-]?(?:0|[1-9](?:_?[0-9])*)" // dec, integer part
            + "(?P<floatpart>"
            + "(?:\\.[0-9](?:_?[0-9])*)?" // optional fractional part
            + "(?:[eE][+-]?[0-9](?:_?[0-9])*)?" // optional exponent part
            + ")"
    )
}

function RE_LOCALTIME() -> string {
    _time_re_str()
}

function RE_DATETIME() -> string {
    (
        "([0-9]{4})-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])" // date, e.g. 1988-10-27
            + "(?:"
            + "[Tt ]"
            + _time_re_str()
            + "(?:([Zz])|([+-])([01][0-9]|2[0-3]):([0-5][0-9]))?" // optional time offset
            + ")?"
    )
}

/// The subset of Python's `re.Match` API that tomli uses.
class ReMatch {
    /// `groups[0]` is the whole match; `null` = group did not participate.
    _groups: (string?)[],
    _named: map<string, string?>,
    _end: int,

    /// `m.group()`
    function group(self) -> string {
        self._groups[0] ?? ""
    }

    /// `match.group(name)`
    function named_group(self, name: string) -> string? {
        self._named.get(name) ?? null
    }

    /// `m.groups()`
    function groups(self) -> (string?)[] {
        self._groups.slice(1, self._groups.length())
    }

    /// `match.end()`
    function end(self) -> int {
        self._end
    }
}

/// Python's `pattern.match(src, pos)`: match `re` anchored at `pos`.
///
/// `baml.regex.Regex` can only search a whole haystack, so the pattern is
/// wrapped as `^(?:...)` and run against the tail of `src`. None of tomli's
/// patterns can match a newline, so only the rest of the current line is
/// handed to the regex engine (an optimisation that does not change results).
function re_match_at(pattern: string, src: string, pos: int) -> ReMatch? {
    let line_end = str_find(src, "\n", pos) ?? src.length();
    let anchored = baml.regex.new("^(?:" + pattern + ")") catch (e) {
        baml.regex.Error => baml.sys.panic("cannot anchor pattern: " + e.message)
    };
    let m = anchored.match_once(src.slice(pos, line_end));
    if (m == null) {
        return null;
    }
    let named: map<string, string?> = {};
    for (let name in m.named.keys()) {
        // NOTE: `m.named.get(name)?.text` is rejected (E0007: "type
        // `baml.regex.Group | null` has no member `text`") -- `?.` on a
        // `map<string, T?>.get()` result (i.e. `T | null | null`) does not
        // strip the null. Bind and narrow explicitly instead.
        let grp = m.named.get(name) ?? null;
        named.set(
            name,
            if (grp == null) {
                null
            } else {
                grp.text
            },
        );
    }
    ReMatch {
        _groups: m.groups.map((g) -> {
            g?.text
        }),
        _named: named,
        _end: pos + m.end,
    }
}

/// Convert a `RE_DATETIME` match to `ZonedDateTime` (tz-aware `datetime`),
/// `PlainDateTime` (naive `datetime`) or `PlainDate` (`datetime.date`).
///
/// Raises ValueError if the match does not correspond to a valid date
/// or datetime.
function match_to_datetime(
    m: ReMatch,
) -> baml.time.ZonedDateTime | baml.time.PlainDateTime | baml.time.PlainDate throws ValueError {
    let g = m.groups();
    let year_str = g[0] ?? "";
    let month_str = g[1] ?? "";
    let day_str = g[2] ?? "";
    let hour_str = g[3];
    let minute_str = g[4] ?? "";
    let sec_str = g[5];
    let micros_str = g[6];
    let zulu_time = g[7];
    let offset_sign_str = g[8];
    let offset_hour_str = g[9] ?? "";
    let offset_minute_str = g[10] ?? "";

    let year = _small_int(year_str);
    let month = _small_int(month_str);
    let day = _small_int(day_str);
    // Python's `datetime.date` only supports years 1..9999 (MINYEAR..MAXYEAR);
    // `baml.time.PlainDate` also accepts year 0 (ISO 8601 astronomical year
    // numbering), so enforce Python's range explicitly.
    if (year < 1) {
        throw ValueError { message: "year " + year.to_string() + " is out of range" };
    }
    if (hour_str == null) {
        return baml.time.PlainDate.from_components(year, month, day) catch (e) {
            baml.errors.InvalidArgument => {
                throw ValueError { message: e.message }
            },
        };
    }
    let hour = _small_int(hour_str);
    let minute = _small_int(minute_str);
    let sec = if (sec_str) {
        _small_int(sec_str)
    } else {
        0
    };
    let micros = if (micros_str) {
        _small_int(_ljust(micros_str, 6, "0"))
    } else {
        0
    };
    let plain = baml.time.PlainDateTime.from_components(
        year,
        month,
        day,
        hour = hour,
        minute = minute,
        second = sec,
        millisecond = micros / 1000,
        microsecond = micros % 1000,
    ) catch (e) {
        baml.errors.InvalidArgument => {
            throw ValueError { message: e.message }
        },
    };
    let tz: baml.time.TimeZoneOffset? = null;
    if (offset_sign_str) {
        tz = cached_tz(offset_hour_str, offset_minute_str, offset_sign_str);
    } else if (zulu_time) {
        tz = baml.time.TimeZoneOffset.utc();
    } else { // local date-time
        tz = null;
    }
    if (tz == null) {
        return plain;
    }
    plain.to_zoned(tz) catch (e) {
        _ => {
            throw ValueError { message: "cannot attach timezone offset" }
        },
    }
}

// No need to limit cache size. This is only ever called on input
// that matched RE_DATETIME, so there is an implicit bound of
// 24 (hours) * 60 (minutes) * 2 (offset direction) = 2880.
// (BAML port: not actually cached -- no module-level state.)
function cached_tz(
    hour_str: string,
    minute_str: string,
    sign_str: string,
) -> baml.time.TimeZoneOffset {
    let sign = if (sign_str == "+") {
        1
    } else {
        -1
    };
    baml.time.TimeZoneOffset.new(sign * _small_int(hour_str), sign * _small_int(minute_str)) catch (e) {
        baml.errors.InvalidArgument => {
            baml.sys.panic("unreachable: offset out of range: " + e.message)
        }
    }
}

function match_to_localtime(m: ReMatch) -> baml.time.PlainTime {
    let g = m.groups();
    let hour_str = g[0] ?? "";
    let minute_str = g[1] ?? "";
    let sec_str = g[2];
    let micros_str = g[3];
    let sec = if (sec_str) {
        _small_int(sec_str)
    } else {
        0
    };
    let micros = if (micros_str) {
        _small_int(_ljust(micros_str, 6, "0"))
    } else {
        0
    };
    baml.time.PlainTime.from_components(
        _small_int(hour_str),
        minute = _small_int(minute_str),
        second = sec,
        millisecond = micros / 1000,
        microsecond = micros % 1000,
    ) catch (e) {
        baml.errors.InvalidArgument => {
            baml.sys.panic("unreachable: regex guarantees a valid time: " + e.message)
        }
    }
}

function match_to_number(m: ReMatch, parse_float: ParseFloat) -> Value throws unknown {
    if (m.named_group("floatpart")) {
        return parse_float(m.group());
    }
    py_int_base0(m.group())
}

/// `int(s)` for the short all-digit strings the regexes capture.
function _small_int(s: string) -> int {
    baml.Int.parse(s) catch (e) {
        baml.errors.ParseError => baml.sys.panic("unreachable: not an int: " + s)
    }
}

/// Python's `str.ljust(width, fillchar)`.
function _ljust(s: string, width: int, fill: string) -> string {
    let out = s;
    while (out.length() < width) {
        out = out + fill;
    }
    out
}
