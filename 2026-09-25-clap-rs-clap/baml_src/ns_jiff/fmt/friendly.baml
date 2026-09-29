// Port of jiff/src/fmt/friendly (parser + printer), for `SignedDuration`
//
// The "friendly" format: a sequence of `<integer><unit>` pairs with optional
// whitespace, e.g. `10s`, `1h 30m`, `2 hours 5 minutes`, `-3ms`.

class Unit {
    names: string[],
    nanos: int,
}

function friendly_units() -> Unit[] {
    [
        Unit { names: ["hours", "hour", "hrs", "hr", "h"], nanos: 3600000000000 },
        Unit { names: ["minutes", "minute", "mins", "min", "m"], nanos: 60000000000 },
        Unit { names: ["seconds", "second", "secs", "sec", "s"], nanos: 1000000000 },
        Unit { names: ["milliseconds", "millisecond", "millis", "milli", "msecs", "msec", "ms"], nanos: 1000000 },
        Unit { names: ["microseconds", "microsecond", "micros", "micro", "usecs", "usec", "us", "µsecs", "µsec", "µs"], nanos: 1000 },
        Unit { names: ["nanoseconds", "nanosecond", "nanos", "nano", "nsecs", "nsec", "ns"], nanos: 1 },
    ]
}

function friendly_error(msg: string) -> Error {
    Error { message: `failed to parse input in the "friendly" duration format: ${msg}` }
}

function parse_friendly(input: string) -> SignedDuration throws Error {
    let chars = input.chars();
    let i = 0;
    let negative = false;
    if (i < chars.length() && (chars[i] == "-" || chars[i] == "+")) {
        negative = chars[i] == "-";
        i += 1;
        while (i < chars.length() && chars[i] == " ") { i += 1; }
    }
    if (i >= chars.length() || !chars[i].is_ascii_numeric()) {
        throw friendly_error("expected duration to start with a unit value (a decimal integer) after an optional sign, but no integer was found");
    }
    let total = 0;
    while (i < chars.length()) {
        let start = i;
        while (i < chars.length() && chars[i].is_ascii_numeric()) { i += 1; }
        if (start == i) {
            throw friendly_error(`expected to find a unit value (a decimal integer), but found ${debug_rest(chars, i)}`);
        }
        let value = baml.Int.parse(chars.slice(start, i).join("")) catch_all (e) { _ => throw friendly_error("unit value overflowed") };
        while (i < chars.length() && chars[i] == " ") { i += 1; }
        let ustart = i;
        while (i < chars.length() && (chars[i].is_alphabetic() || chars[i] == "µ")) { i += 1; }
        let designator = chars.slice(ustart, i).join("");
        if (designator.is_empty()) {
            throw friendly_error(`expected to find unit designator suffix (e.g., 'years' or 'secs') after parsing integer`);
        }
        let unit = friendly_units().find((u) -> { u.names.includes(designator) });
        if let u: Unit = unit {
            total = total + value * u.nanos;
        } else {
            throw friendly_error(`parsed value '${value}', but unit designator '${designator}' is not valid for a signed duration`);
        }
        while (i < chars.length() && (chars[i] == " " || chars[i] == ",")) { i += 1; }
    }
    SignedDuration.from_nanos(if (negative) { 0 - total } else { total })
}

function debug_rest(chars: string[], i: int) -> string {
    `"${chars.slice(i, chars.length()).join("")}"`
}

function format_friendly(d: SignedDuration) -> string {
    let total = d.as_nanos();
    if (total == 0) {
        return "0s";
    }
    let negative = total < 0;
    let remaining = if (negative) { 0 - total } else { total };
    let parts: string[] = [];
    let designators = ["h", "m", "s", "ms", "µs", "ns"];
    let units = friendly_units();
    for (let k in baml.iter.Range.new(0, units.length())) {
        let n = remaining / units[k].nanos;
        if (n > 0) {
            parts.push(`${n}${designators[k]}`);
            remaining = remaining - n * units[k].nanos;
        }
    }
    (if (negative) { "-" } else { "" }) + parts.join(" ")
}

testset "jiff_friendly" {
    test "parse_and_display" {
        let d = parse_friendly("10s") catch_all (e) { _ => SignedDuration.from_secs(0) };
        assert.equal(`${d}`, "10s");
        let d2 = parse_friendly("1h 30m") catch_all (e) { _ => SignedDuration.from_secs(0) };
        assert.equal(`${d2}`, "1h 30m");
        let d3 = parse_friendly("2 hours 5 minutes") catch_all (e) { _ => SignedDuration.from_secs(0) };
        assert.equal(d3.secs, 7500)
    }
    test "error" {
        let e = parse_friendly("forever") catch (err) { let x: Error => x.message };
        assert.equal(`${e}`, "failed to parse input in the \"friendly\" duration format: expected duration to start with a unit value (a decimal integer) after an optional sign, but no integer was found")
    }
}
