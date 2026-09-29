// Ported from sasso `src/localtime/civil.rs` `mod tests` (namespace `root.localtime.civil.tests`).
//
// PORT: `use super::*;` → items of `root.localtime.civil` are written fully qualified.

test "the_two_conversions_are_inverses" {
    // Every day across four centuries, which covers all four leap-year
    // rules including the 400-year exception that 2000 and 2400 hit and
    // 1900 and 2100 do not.
    let start = root.localtime.civil.days_from_civil(1800, 1, 1);
    let end = root.localtime.civil.days_from_civil(2200, 1, 1);
    for (let d in baml.iter.Range.new(start, end)) {
        let ymd = root.localtime.civil.civil_from_days(d);
        let y = ymd._0;
        let m = ymd._1;
        let day = ymd._2;
        // round trip at day {d} -> {y}-{m}-{day}
        assert.equal(root.localtime.civil.days_from_civil(y, m, day), d);
    }
}

test "known_dates" {
    assert.equal(
        root.localtime.civil.civil_from_days(0),
        root.std.Tuple3<int, int, int> { _0: 1970, _1: 1, _2: 1 },
    );
    assert.equal(
        root.localtime.civil.civil_from_days(-1),
        root.std.Tuple3<int, int, int> { _0: 1969, _1: 12, _2: 31 },
    );
    assert.equal(root.localtime.civil.days_from_civil(1970, 1, 1), 0);
    // A leap day that exists, and the century that skips one.
    assert.equal(
        root.localtime.civil.civil_from_days(root.localtime.civil.days_from_civil(2000, 2, 29)),
        root.std.Tuple3<int, int, int> { _0: 2000, _1: 2, _2: 29 },
    );
    assert.equal(root.localtime.civil.days_in_month(2000, 2), 29);
    assert.equal(root.localtime.civil.days_in_month(1900, 2), 28);
    assert.equal(root.localtime.civil.days_in_month(2100, 2), 28);
    assert.equal(root.localtime.civil.days_in_month(2024, 2), 29)
}

test "weekdays" {
    // 1970-01-01 was a Thursday
    assert.equal(root.localtime.civil.weekday(0), 4);
    // a Saturday
    assert.equal(root.localtime.civil.weekday(root.localtime.civil.days_from_civil(2026, 9, 19)), 6);
    // Before the epoch the arithmetic must still wrap the right way.
    // a Sunday
    assert.equal(
        root.localtime.civil.weekday(root.localtime.civil.days_from_civil(1969, 12, 28)),
        0,
    )
}

test "negative_seconds_floor_rather_than_truncate" {
    // The hour before the epoch is 1969-12-31 23:00, not 1970-01-01
    // -1:00. Integer division truncates toward zero and would give the
    // latter, which is why div_euclid/rem_euclid are used.
    let c = root.localtime.civil.civil_from_unix(-3600);
    assert.equal(
        root.std.Tuple4<int, int, int, int> { _0: c.year, _1: c.month, _2: c.day, _3: c.hour },
        root.std.Tuple4<int, int, int, int> { _0: 1969, _1: 12, _2: 31, _3: 23 },
    )
}

test "fields_split_correctly" {
    let c = root.localtime.civil.civil_from_unix(
        root.localtime.civil.days_from_civil(2026, 9, 19) * 86400 + 13 * 3600 + 5 * 60 + 7,
    );
    assert.equal(
        c,
        root.localtime.civil.Civil { year: 2026, month: 9, day: 19, hour: 13, minute: 5, second: 7 },
    )
}
