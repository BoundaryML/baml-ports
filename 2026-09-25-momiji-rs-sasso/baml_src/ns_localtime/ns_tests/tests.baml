// Ported from sasso `src/localtime/mod.rs` `mod tests` (namespace `root.localtime.tests`).
//
// PORT: `use super::*;` → items of `root.localtime` are written fully qualified.
// PORT: `#[cfg(all(test, unix))]` — the unix build is the one ported.

// End to end against vendored bytes, so the expected strings can be
// written down rather than computed by the code under test.
test "the_stamp_reads_as_dart_writes_it" {
    // PORT: `include_bytes!("../../tests/fixtures/tz/Australia_Lord_Howe")` →
    // the same 1846 bytes embedded as base64 (sha256 a323c543…4bab9df).
    let LORD_HOWE: uint8array = uint8array.from_base64(
        "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",
    );
    let tz = root.std.expect(root.localtime.tzif.TimeZone.parse(LORD_HOWE), "parse");

    // 2026-07-15 12:00 UTC. Lord Howe is +10:30 in its winter (July),
    // so 22:30 the same day.
    let secs = 1784116800;
    let off = root.std.expect(tz.offset_at(secs), "offset");
    assert.equal(off, 10 * 3600 + 1800);
    let c = root.localtime.civil.civil_from_unix(secs + off);
    // a half-hour zone must not be rounded to the hour
    assert.equal(root.localtime.format_stamp(c), "[2026-07-15 22:30:00]")
}

test "a_machine_with_no_tzdata_drops_the_stamp_rather_than_lying" {
    // Exercised through the real path: whatever this machine has, the
    // function must either give a well-formed stamp or nothing.
    match (root.localtime.local_stamp(root.localtime.now())) {
        null => {},
        let s: string => {
            // [YYYY-MM-DD HH:MM:SS] is 21 chars: {s:?}
            assert.equal(s.length(), 21);
            // {s:?}
            assert.is_true(s.starts_with("[") && s.ends_with("]"));
            let inner = s.slice(1, s.length() - 1);
            let date_time = root.std.expect(root.std.split_once(inner, " "), "one space");
            let date = date_time._0;
            let time = date_time._1;
            // {s:?}
            assert.equal(date.split("-").length(), 3);
            // second resolution: {s:?}
            assert.equal(time.split(":").length(), 3);
            assert.is_true(
                inner.chars().every((c) -> {
                    c.is_ascii_numeric() || c == "-" || c == ":" || c == " "
                }),
            );
        },
    }
}

// The whole tz database, against an independent implementation.
//
// `#[ignore]`d because it needs two things the everyday suite must not:
// the host's `/usr/share/zoneinfo`, and a Python with `zoneinfo` to
// disagree with us. CI runs it explicitly
// (`cargo test --bin sasso -- --ignored`); the vendored-fixture tests
// above are what run on every `cargo test`.
//
// Python's `zoneinfo` is the oracle rather than the system `date`,
// which is not always right: for the three Greenland zones, whose
// footer uses angle-bracket abbreviations, macOS's `date` stops
// applying the footer past 2037 and reports standard time all year.
// The first version of this sweep reported six failures that were all
// the reference being wrong.
test "agrees_with_zoneinfo_on_every_zone" {
    // PORT: `#[ignore = "needs the host tz database and a Python with zoneinfo"]`
    // → BAML tests have no ignore flag, so the body runs only when the
    // environment variable `SASSO_RUN_IGNORED` is set (the counterpart of
    // `cargo test -- --ignored`); otherwise the test passes without running.
    if (root.std.env_var("SASSO_RUN_IGNORED") != null) {
        // PORT: `use std::process::Command;` → `baml.sys.exec`.

        // Awkward on purpose: DST transition seconds, half-hour and
        // 45-minute zones, both hemispheres, deep history, and well past
        // the transition table where the POSIX footer takes over.
        let INSTANTS: int[] = [
            0,
            1772949600, // a US spring-forward instant
            1780000000,
            1788000000,
            1796000000,
            -800000000, // 1944
            -2000000000, // 1906
            2500000000, // 2049
            3000000000, // 2065, winter
            3013651200, // 2065, summer
            3045187200, // 2066, summer
            4102444800, // 2100
        ];

        // PORT: the Rust raw string `r#"…"#`; `\\t` keeps Python's own `\t` escape.
        let script = `
            import sys, datetime, zoneinfo
            times = [int(x) for x in sys.argv[1:]]
            for z in sorted(zoneinfo.available_timezones()):
                try:
                    tz = zoneinfo.ZoneInfo(z)
                except Exception:
                    continue
                row = [z]
                for t in times:
                    try:
                        row.append(str(int(datetime.datetime.fromtimestamp(t, tz).utcoffset().total_seconds())))
                    except Exception:
                        row.append("skip")
                print("\\t".join(row))
        `;
        let out = baml.sys.exec(
            "python3",
            ["-c", script].concat(
                INSTANTS.map((t) -> {
                    t.to_string()
                }),
            ),
            null,
        ) catch (e) {
            // PORT: `let Ok(out) = out else { panic!(…) };` folded into the catch.
            let _e: baml.errors.Io => {
                root.std.panic("python3 is required for this test; it is #[ignore]d so CI opts in")
            }
        };
        // PORT: `String::from_utf8_lossy` → `uint8array.to_string()` (lossy).
        let table = out.stdout.to_string();
        // expected a real zone list, got {} lines; stderr: {}
        assert.is_true(table.lines().length() > 100);

        // `bad` is capped so a systematic break prints twenty lines rather
        // than seven thousand; `wrong` is the honest count that goes in the
        // message, because "20 of 7176" when it is really 7176 would send
        // the next reader looking for a subtle bug instead of a total one.
        let checked = 0;
        let zones = 0;
        let wrong = 0;
        let bad: string[] = [];
        for (let line in table.lines()) {
            let cols = line.split("\t");
            let zone = cols.at(0);
            if (zone == null) {
                continue;
            }
            let bytes = root.std.read_bytes(`/usr/share/zoneinfo/${zone}`) catch (e) {
                let _e: baml.errors.Io => null
            };
            if (bytes == null) {
                continue;
            }
            let tz = root.localtime.tzif.TimeZone.parse(bytes);
            if (tz == null) {
                wrong += 1;
                bad.push(`${zone}: did not parse`);
                continue;
            }
            zones += 1;
            // PORT: `INSTANTS.iter().zip(cols)` → an index loop over both
            // (`cols` has already yielded the zone, so its i-th item is `cols[i + 1]`).
            let i = 0;
            while (i < INSTANTS.length() && i + 1 < cols.length()) {
                let t = INSTANTS[i];
                let want_s = cols[i + 1];
                i += 1;
                if (want_s == "skip") {
                    continue;
                }
                let want: int = baml.Int.parse(want_s) catch (e) {
                    let _e: baml.errors.ParseError => root.std.panic("an integer offset")
                };
                let got = tz.offset_at(t);
                checked += 1;
                if (got != want) {
                    wrong += 1;
                    if (bad.length() < 20) {
                        let got_s = if (got == null) {
                            "None"
                        } else {
                            `Some(${got})`
                        };
                        bad.push(`${zone} @ ${t}: zoneinfo=${want} ours=${got_s}`);
                    }
                }
            }
        }
        // PORT: print the assertion message first so a failure is readable.
        if (wrong != 0) {
            baml.io.eprintln(
                `${wrong} of ${checked} checks across ${zones} zones disagreed (first ${bad.length()}):\n  ${bad.join("\n  ")}`,
            );
        }
        // {wrong} of {checked} checks across {zones} zones disagreed (first {}):\n  {}
        assert.is_true(wrong == 0);
        // only {checked} checks ran — the sweep is not covering the database
        assert.is_true(checked > 5000);
        baml.io.eprintln(
            `localtime sweep: ${checked} checks across ${zones} zones, all matching zoneinfo`,
        );
    }
}

test "now_is_plausible" {
    // Not a clock test — only that the epoch conversion has not lost a
    // factor of 1000, which is the classic way this goes wrong.
    let t = root.localtime.now();
    // before 2023: {t}
    assert.is_true(t > 1700000000);
    // after 2100: {t}
    assert.is_true(t < 4102444800)
}
