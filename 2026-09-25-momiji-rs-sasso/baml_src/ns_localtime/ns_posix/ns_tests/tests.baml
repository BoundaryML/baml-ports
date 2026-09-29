// Ported from sasso `src/localtime/posix.rs` `mod tests` (namespace `root.localtime.posix.tests`).
//
// PORT: `use super::*;` → items of `root.localtime.posix` (and the
// `super::civil` items it imports) are written fully qualified.

function p(s: string) -> root.localtime.posix.Posix {
    root.localtime.posix.parse(s) ?? root.std.panic(`failed to parse ${root.std.debug_str(s)}`)
}

// Every shape that appears in the vendored fixtures, so a parser change
// that breaks one of them fails here rather than in a date far away.
test "the_footers_tzdata_actually_ships" {
    // Ordinary northern DST.
    let ny = p("EST5EDT,M3.2.0,M11.1.0");
    // POSIX writes offsets west-positive
    assert.equal(ny.std_offset, -5 * 3600);
    let dst = root.std.expect(ny.dst, "New York has DST");
    // an omitted DST offset is std + 1h
    assert.equal(dst.offset, -4 * 3600);
    assert.equal(dst.start, root.localtime.posix.Rule_Month { month: 3, week: 2, weekday: 0 });
    // the default transition time
    assert.equal(dst.start_time, 2 * 3600);

    // An explicit transition time.
    assert.equal(root.std.unwrap(p("GMT0IST,M3.5.0/1,M10.5.0").dst).start_time, 3600);

    // Half-hour offsets, southern hemisphere (start month AFTER end).
    let lh = p("<+1030>-10:30<+11>-11,M10.1.0,M4.1.0");
    assert.equal(lh.std_offset, 10 * 3600 + 1800);
    assert.equal(root.std.unwrap(lh.dst).offset, 11 * 3600);

    // 45-minute offsets with 45-minute transition times.
    let ch = p("<+1245>-12:45<+1345>,M9.5.0/2:45,M4.1.0/3:45");
    assert.equal(ch.std_offset, 12 * 3600 + 45 * 60);
    assert.equal(root.std.unwrap(ch.dst).offset, 13 * 3600 + 45 * 60);
    assert.equal(root.std.unwrap(ch.dst).start_time, 2 * 3600 + 45 * 60);

    // A negative transition time: 01:00 the PREVIOUS day.
    let nuuk = p("<-02>2<-01>,M3.5.0/-1,M10.5.0/0");
    assert.equal(nuuk.std_offset, -2 * 3600);
    assert.equal(root.std.unwrap(nuuk.dst).offset, -3600);
    assert.equal(root.std.unwrap(nuuk.dst).start_time, -3600);
    assert.equal(root.std.unwrap(nuuk.dst).end_time, 0);

    // Fixed offsets, no DST clause at all.
    assert.equal(
        p("<+0545>-5:45"),
        root.localtime.posix.Posix { std_offset: 5 * 3600 + 45 * 60, dst: null },
    );
    assert.equal(p("CST-8"), root.localtime.posix.Posix { std_offset: 8 * 3600, dst: null });
    assert.equal(p("UTC0"), root.localtime.posix.Posix { std_offset: 0, dst: null })
}

test "junk_is_refused_rather_than_half_understood" {
    // A half-parsed rule is worse than none: the caller can fall back to
    // the last tabulated offset, which is right far more often than a
    // guess would be.
    for (
        let bad in [
            "", // empty
            "EST", // no offset
            "<unterminated5", // no closing bracket
            "EST5EDT", // DST named with no rules
            "EST5EDT,M3.2.0", // only one rule
            "EST5EDT,M3.2.0,M11.1.0,X", // trailing junk
            "EST5EDT,M13.2.0,M11.1.0", // month 13
            "EST5EDT,M3.9.0,M11.1.0", // week 9
            "EST5EDT,M3.2.9,M11.1.0", // weekday 9
            "EST5EDT,J0,M11.1.0", // Julian is 1-based
            "EST5EDT,J400,M11.1.0", // beyond the year
            "EST5EDT,999,M11.1.0", // day beyond the year
        ]
    ) {
        // should have refused {bad:?}
        assert.is_true(root.localtime.posix.parse(bad) == null);
    }
}

test "week_five_means_the_last_one" {
    // October 2026 has five Sundays, November has five as well but the
    // fifth falls on the 29th; a month with only four must step back.
    // 2026-10: Sundays are 4, 11, 18, 25 — only four.
    let last_sunday_oct = root.localtime.posix.day_of_year(
        root.localtime.posix.Rule_Month { month: 10, week: 5, weekday: 0 },
        2026,
    );
    let jan1 = root.localtime.civil.days_from_civil(2026, 1, 1);
    let ymd = root.localtime.civil.civil_from_days(jan1 + last_sunday_oct);
    let m = ymd._1;
    let d = ymd._2;
    // the last Sunday of October 2026
    assert.equal(
        root.std.Tuple2<int, int> { _0: m, _1: d },
        root.std.Tuple2<int, int> { _0: 10, _1: 25 },
    );

    // And a month where the fifth genuinely exists.
    let fifth_friday_jan = root.localtime.posix.day_of_year(
        root.localtime.posix.Rule_Month { month: 1, week: 5, weekday: 5 },
        2027,
    );
    let jan1 = root.localtime.civil.days_from_civil(2027, 1, 1);
    let ymd = root.localtime.civil.civil_from_days(jan1 + fifth_friday_jan);
    let m = ymd._1;
    let d = ymd._2;
    // the last Friday of January 2027
    assert.equal(
        root.std.Tuple2<int, int> { _0: m, _1: d },
        root.std.Tuple2<int, int> { _0: 1, _1: 29 },
    )
}

test "julian_days_skip_the_leap_day" {
    // J60 is 1 March in every year, leap or not — that is the whole
    // point of the J form.
    for (let year in [2023, 2024]) {
        let jan1 = root.localtime.civil.days_from_civil(year, 1, 1);
        let d = root.localtime.posix.day_of_year(root.localtime.posix.Rule_Julian { _0: 60 }, year);
        let ymd = root.localtime.civil.civil_from_days(jan1 + d);
        let m = ymd._1;
        let day = ymd._2;
        // J60 in {year}
        assert.equal(
            root.std.Tuple2<int, int> { _0: m, _1: day },
            root.std.Tuple2<int, int> { _0: 3, _1: 1 },
        );
    }
    // The n form does not skip it, so day 60 moves.
    let jan1 = root.localtime.civil.days_from_civil(2024, 1, 1);
    let ymd = root.localtime.civil.civil_from_days(
        jan1 + root.localtime.posix.day_of_year(root.localtime.posix.Rule_Zero { _0: 60 }, 2024),
    );
    let m = ymd._1;
    let day = ymd._2;
    // day 60 of a leap year is 1 March (0-based)
    assert.equal(
        root.std.Tuple2<int, int> { _0: m, _1: day },
        root.std.Tuple2<int, int> { _0: 3, _1: 1 },
    )
}

test "the_southern_window_spans_new_year" {
    // Lord Howe: DST from October to April, so January IS daylight time
    // and July is not. A northern-only comparison gets both backwards.
    let lh = p("<+1030>-10:30<+11>-11,M10.1.0,M4.1.0");
    let jan = root.localtime.civil.days_from_civil(2027, 1, 15) * 86400;
    let jul = root.localtime.civil.days_from_civil(2027, 7, 15) * 86400;
    // January is DST in the south
    assert.equal(root.localtime.posix.offset_at(lh, jan), 11 * 3600);
    // July is standard
    assert.equal(root.localtime.posix.offset_at(lh, jul), 10 * 3600 + 1800)
}

test "a_transition_is_placed_to_the_second" {
    // New York 2027: DST starts 2027-03-14 at 02:00 EST, which is
    // 07:00 UTC. One second either side must land on either side.
    let ny = p("EST5EDT,M3.2.0,M11.1.0");
    let at = root.localtime.civil.days_from_civil(2027, 3, 14) * 86400 + 7 * 3600;
    // still standard
    assert.equal(root.localtime.posix.offset_at(ny, at - 1), -5 * 3600);
    // daylight from this second
    assert.equal(root.localtime.posix.offset_at(ny, at), -4 * 3600)
}
