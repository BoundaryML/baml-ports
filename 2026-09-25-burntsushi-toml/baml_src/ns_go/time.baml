// Shim: the subset of Go's `time` package used by the toml package and its
// tests: time.Time with a *Location, ParseInLocation/Format driven by Go's
// reference-time layouts, time.Date, Add, and time.Duration with String and
// ParseDuration.
//
// BAML's stdlib has baml.time.{ZonedDateTime,PlainDateTime,...}, but the toml
// package round-trips its local date/time kinds through *which Location* a
// time.Time carries (internal.LocalDatetime etc.), and the tests compare Go's
// exact Format/String output, so the port models Go's time.Time directly.

class Location {
    name: string, // Location.String(), e.g. "UTC", "Local", "datetime-local"
    offset: int, // seconds east of UTC
    abbr: string, // zone abbreviation printed by the "MST" layout element
}

function utc() -> Location {
    Location { name: "UTC", offset: 0, abbr: "UTC" }
}

// time.Local. BAML exposes no portable "current zone offset" that matches Go's
// time.Now().Zone(), so the port behaves as if TZ=UTC.
function local() -> Location {
    Location { name: "Local", offset: 0, abbr: "UTC" }
}

// time.FixedZone(name, offset).
function fixed_zone(name: string, offset: int) -> Location {
    Location { name: name, offset: offset, abbr: name }
}

function same_location(a: Location, b: Location) -> bool {
    a.name == b.name && a.offset == b.offset && a.abbr == b.abbr
}

// time.Time as a civil (wall clock) time in a Location.
class Time {
    year: int,
    month: int, // 1..12
    day: int,
    hour: int,
    min: int,
    sec: int,
    nsec: int,
    loc: Location,

    // func (t Time) Location() *Location
    function location(self) -> Location {
        self.loc
    }

    // func (t Time) Add(d Duration) Time
    function add(self, d: Duration) -> Time {
        let total_ns = self.nsec + d.ns;
        let carry_s = floor_div(total_ns, 1000000000);
        let nsec = total_ns - carry_s * 1000000000;
        let secs = self.hour * 3600 + self.min * 60 + self.sec + carry_s;
        let carry_d = floor_div(secs, 86400);
        secs = secs - carry_d * 86400;
        let days = days_from_civil(self.year, self.month, self.day) + carry_d;
        let c = civil_from_days(days);
        Time {
            year: c[0],
            month: c[1],
            day: c[2],
            hour: secs / 3600,
            min: (secs % 3600) / 60,
            sec: secs % 60,
            nsec: nsec,
            loc: self.loc,
        }
    }

    // func (t Time) Equal(u Time) bool (instant equality)
    function unix_nano_key(self) -> string {
        let days = days_from_civil(self.year, self.month, self.day);
        let s = days * 86400 + self.hour * 3600 + self.min * 60 + self.sec - self.loc.offset;
        `${s}.${self.nsec}`
    }

    function is_zero(self) -> bool {
        self.year == 1 && self.month == 1 && self.day == 1 && self.hour == 0 && self.min == 0 && self.sec == 0
            && self.nsec == 0 && self.loc.offset == 0
    }

    // func (t Time) Format(layout string) string
    function format(self, layout: string) -> string {
        format_time(self, layout)
    }

    implements baml.ToString {
        // func (t Time) String() string
        function to_string(self) -> string throws never {
            format_time(self, "2006-01-02 15:04:05.999999999 -0700 MST")
        }
    }
}

// The zero time.Time{}: January 1, year 1, 00:00:00 UTC.
function zero_time() -> Time {
    Time { year: 1, month: 1, day: 1, hour: 0, min: 0, sec: 0, nsec: 0, loc: utc() }
}

// time.Date(year, month, day, hour, min, sec, nsec, loc), without
// normalisation of out-of-range fields (the port never needs it).
function date(year: int, month: int, day: int, hour: int, min: int, sec: int, nsec: int, loc: Location) -> Time {
    Time { year: year, month: month, day: day, hour: hour, min: min, sec: sec, nsec: nsec, loc: loc }
}

function floor_div(a: int, b: int) -> int {
    let q = a / b;
    if ((a % b != 0) && ((a < 0) != (b < 0))) {
        q -= 1;
    }
    q
}

// Days since 1970-01-01 of a proleptic Gregorian date (Howard Hinnant).
function days_from_civil(y0: int, m: int, d: int) -> int {
    let y = if (m <= 2) { y0 - 1 } else { y0 };
    let era = floor_div(y, 400);
    let yoe = y - era * 400;
    let mp = if (m > 2) { m - 3 } else { m + 9 };
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146097 + doe - 719468
}

function civil_from_days(z0: int) -> int[] {
    let z = z0 + 719468;
    let era = floor_div(z, 146097);
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if (mp < 10) { mp + 3 } else { mp - 9 };
    [if (m <= 2) { y + 1 } else { y }, m, d]
}

function is_leap(year: int) -> bool {
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

function days_in(month: int, year: int) -> int {
    if (month == 2) {
        return if (is_leap(year)) { 29 } else { 28 };
    }
    if (month == 4 || month == 6 || month == 9 || month == 11) {
        return 30;
    }
    31
}

function rfc3339() -> string {
    "2006-01-02T15:04:05Z07:00"
}

function rfc3339_nano() -> string {
    "2006-01-02T15:04:05.999999999Z07:00"
}

// ---- layout handling --------------------------------------------------------

// The layout elements the port understands (a subset of Go's std* chunks).
function layout_elements() -> string[] {
    [
        "2006",
        "01",
        "02",
        "15",
        "04",
        "05",
        ".999999999",
        ".000000000",
        ".999999",
        ".999",
        "Z07:00",
        "-07:00",
        "-0700",
        "MST",
    ]
}

// Splits a layout into literal runs and layout elements, like repeated calls
// to Go's nextStdChunk.
function layout_chunks(layout: string) -> string[] {
    let out: string[] = [];
    let lit = "";
    let i = 0;
    let n = layout.length();
    while (i < n) {
        let found = "";
        for (let e in layout_elements()) {
            if (i + e.length() <= n && layout.slice(i, i + e.length()) == e) {
                found = e;
                break;
            }
        }
        if (found == "") {
            lit += layout.slice(i, i + 1);
            i += 1;
            continue;
        }
        if (lit != "") {
            out.push("L" + lit);
            lit = "";
        }
        out.push("S" + found);
        i += found.length();
    }
    if (lit != "") {
        out.push("L" + lit);
    }
    out
}

function pad_int(n: int, width: int) -> string {
    let s = n.abs().to_string();
    while (s.length() < width) {
        s = "0" + s;
    }
    if (n < 0) { "-" + s } else { s }
}

function format_time(t: Time, layout: string) -> string throws never {
    let b = "";
    for (let c in layout_chunks(layout)) {
        let kind = c.slice(0, 1);
        let v = c.slice(1, c.length());
        let vlen = v.length();
        if (kind == "L") {
            b += v;
            continue;
        }
        match (v) {
            "2006" => {
                b += pad_int(t.year, 4);
            },
            "01" => {
                b += pad_int(t.month, 2);
            },
            "02" => {
                b += pad_int(t.day, 2);
            },
            "15" => {
                b += pad_int(t.hour, 2);
            },
            "04" => {
                b += pad_int(t.min, 2);
            },
            "05" => {
                b += pad_int(t.sec, 2);
            },
            ".000000000" => {
                b += "." + pad_int(t.nsec, 9);
            },
            ".999999999" | ".999999" | ".999" => {
                let digits = vlen - 1;
                let s = pad_int(t.nsec, 9).slice(0, digits);
                while (s.length() > 0 && s.ends_with("0")) {
                    s = s.slice(0, s.length() - 1);
                }
                if (s != "") {
                    b += "." + s;
                }
            },
            "Z07:00" | "-07:00" | "-0700" => {
                let off = t.loc.offset;
                if (off == 0 && v == "Z07:00") {
                    b += "Z";
                } else {
                    let sign = if (off < 0) { "-" } else { "+" };
                    let a = off.abs() / 60;
                    b += sign + pad_int(a / 60, 2);
                    if (v != "-0700") {
                        b += ":";
                    }
                    b += pad_int(a % 60, 2);
                }
            },
            "MST" => {
                if (t.loc.abbr != "") {
                    b += t.loc.abbr;
                } else {
                    // No time zone known for this time, but we must print one.
                    // Use the -0700 format.
                    let off = t.loc.offset;
                    let sign = if (off < 0) { "-" } else { "+" };
                    let a = off.abs() / 60;
                    b += sign + pad_int(a / 60, 2) + pad_int(a % 60, 2);
                }
            },
            _ => {
                b += v;
            },
        }
    }
    b
}

function is_digit_str(s: string, i: int) -> bool {
    let c = s.slice(i, i + 1);
    c >= "0" && c <= "9" && c.length() == 1
}

class NumResult {
    n: int,
    rest: string,
    ok: bool,
}

// getnum(s, fixed): one or two leading digits (exactly two if fixed).
function getnum(s: string, fixed: bool) -> NumResult {
    if (!is_digit_str(s, 0)) {
        return NumResult { n: 0, rest: s, ok: false };
    }
    if (!is_digit_str(s, 1)) {
        if (fixed) {
            return NumResult { n: 0, rest: s, ok: false };
        }
        return NumResult { n: atoi_or(s.slice(0, 1), 0), rest: s.slice(1, s.length()), ok: true };
    }
    NumResult { n: atoi_or(s.slice(0, 2), 0), rest: s.slice(2, s.length()), ok: true }
}

function atoi_or(s: string, dflt: int) -> int {
    int.parse(s) catch (e) {
        _ => dflt
    }
}

// parseNanoseconds for ".ddd..." (value[0] is the separator; n bytes long).
function parse_nanoseconds(value: string, nbytes: int) -> int {
    let digits = value.slice(1, nbytes);
    if (digits.length() > 9) {
        digits = digits.slice(0, 9);
    }
    let ns = atoi_or(digits, 0);
    let scale = 9 - digits.length();
    while (scale > 0) {
        ns *= 10;
        scale -= 1;
    }
    ns
}

// time.ParseInLocation(layout, value, loc). Returns null on any parse error
// (the toml package only checks `err == nil`).
function parse_in_location(layout: string, value0: string, local: Location) -> Time? {
    let value = value0;
    let year = 0;
    let month = -1;
    let day = -1;
    let hour = 0;
    let min = 0;
    let sec = 0;
    let nsec = 0;
    let z_utc = false;
    let zone_offset = -1;
    let range_err = false;

    let chunks = layout_chunks(layout);
    let ci = 0;
    while (ci < chunks.length()) {
        let c = chunks[ci];
        let kind = c.slice(0, 1);
        let v = c.slice(1, c.length());
        ci += 1;
        if (kind == "L") {
            if (!value.starts_with(v)) {
                return null;
            }
            value = value.slice(v.length(), value.length());
            continue;
        }
        match (v) {
            "2006" => {
                if (value.length() < 4 || !is_digit_str(value, 0)) {
                    return null;
                }
                let p = value.slice(0, 4);
                let ok = true;
                for (let ch in p.chars()) {
                    if (ch < "0" || ch > "9") {
                        ok = false;
                    }
                }
                if (!ok) {
                    return null;
                }
                year = atoi_or(p, 0);
                value = value.slice(4, value.length());
            },
            "01" => {
                let r = getnum(value, true);
                if (!r.ok) {
                    return null;
                }
                if (r.n <= 0 || 12 < r.n) {
                    range_err = true;
                }
                month = r.n;
                value = r.rest;
            },
            "02" => {
                let r = getnum(value, true);
                if (!r.ok) {
                    return null;
                }
                day = r.n;
                value = r.rest;
            },
            "15" => {
                let r = getnum(value, false);
                if (!r.ok) {
                    return null;
                }
                if (r.n < 0 || 24 <= r.n) {
                    range_err = true;
                }
                hour = r.n;
                value = r.rest;
            },
            "04" => {
                let r = getnum(value, true);
                if (!r.ok) {
                    return null;
                }
                if (r.n < 0 || 60 <= r.n) {
                    range_err = true;
                }
                min = r.n;
                value = r.rest;
            },
            "05" => {
                let r = getnum(value, true);
                if (!r.ok) {
                    return null;
                }
                if (r.n < 0 || 60 <= r.n) {
                    range_err = true;
                }
                sec = r.n;
                value = r.rest;
                // Special case: do we have a fractional second but no
                // fractional second in the format?
                if (value.length() >= 2 && (value.starts_with(".") || value.starts_with(",")) && is_digit_str(value, 1)) {
                    let next_is_frac = ci < chunks.length() && chunks[ci].starts_with("S.");
                    if (!next_is_frac) {
                        let n = 2;
                        while (n < value.length() && is_digit_str(value, n)) {
                            n += 1;
                        }
                        nsec = parse_nanoseconds(value, n);
                        value = value.slice(n, value.length());
                    }
                }
            },
            ".999999999" | ".999999" | ".999" => {
                // Fractional second omitted?
                if (value.length() < 2 || !(value.starts_with(".") || value.starts_with(",")) || !is_digit_str(value, 1)) {
                    // nothing
                } else {
                    let i = 0;
                    while (i + 1 < value.length() && is_digit_str(value, i + 1)) {
                        i += 1;
                    }
                    nsec = parse_nanoseconds(value, 1 + i);
                    value = value.slice(1 + i, value.length());
                }
            },
            ".000000000" => {
                let ndigit = 10;
                if (value.length() < ndigit) {
                    return null;
                }
                nsec = parse_nanoseconds(value, ndigit);
                value = value.slice(ndigit, value.length());
            },
            "Z07:00" | "-07:00" => {
                if (v == "Z07:00" && value.starts_with("Z")) {
                    value = value.slice(1, value.length());
                    z_utc = true;
                } else {
                    if (value.length() < 6) {
                        return null;
                    }
                    let sign = value.slice(0, 1);
                    if (value.slice(3, 4) != ":" || (sign != "-" && sign != "+")) {
                        return null;
                    }
                    let hr = getnum(value.slice(1, 3), true);
                    let mm = getnum(value.slice(4, 6), true);
                    if (!hr.ok || !mm.ok) {
                        return null;
                    }
                    // The range test use > rather than >=, as some people do
                    // write offsets of 24 hours or 60 minutes.
                    if (hr.n > 24 || mm.n > 60) {
                        range_err = true;
                    }
                    zone_offset = (hr.n * 60 + mm.n) * 60;
                    if (sign == "-") {
                        zone_offset = -zone_offset;
                    }
                    value = value.slice(6, value.length());
                }
            },
            _ => {
                return null;
            },
        }
    }
    if (range_err) {
        return null;
    }
    if (value != "") {
        return null; // extra text
    }

    if (month < 0) {
        month = 1;
    }
    if (day < 0) {
        day = 1;
    }
    // Validate the day of the month.
    if (day < 1 || day > days_in(month, year)) {
        return null;
    }

    if (z_utc) {
        return date(year, month, day, hour, min, sec, nsec, utc());
    }
    if (zone_offset != -1) {
        // Look for local zone with the given offset. If that zone was in
        // effect at the given time, use it. Otherwise create a fake zone to
        // record the offset.
        if (local.offset == zone_offset) {
            return date(year, month, day, hour, min, sec, nsec, local);
        }
        return date(year, month, day, hour, min, sec, nsec, fixed_zone("", zone_offset));
    }
    date(year, month, day, hour, min, sec, nsec, local)
}

// ---- time.Duration ----------------------------------------------------------

class Duration {
    ns: int,

    implements baml.ToString {
        function to_string(self) -> string throws never {
            duration_string(self.ns)
        }
    }
}

function nanosecond() -> int {
    1
}

function microsecond() -> int {
    1000
}

function millisecond() -> int {
    1000000
}

function second() -> int {
    1000000000
}

function minute() -> int {
    60000000000
}

function hour() -> int {
    3600000000000
}

// fmtFrac/fmtInt helpers of Duration.String, operating on strings.
function duration_string(d: int) -> string throws never {
    if (d == 0) {
        return "0s";
    }
    let neg = d < 0;
    let u = d.abs();
    let out = "";
    if (u < second()) {
        // Special case: if duration is smaller than a second,
        // use smaller units, like 1.2ms
        let prec = 0;
        let unit = "";
        if (u < microsecond()) {
            prec = 0;
            unit = "ns";
        } else if (u < millisecond()) {
            prec = 3;
            unit = "µs";
        } else {
            prec = 6;
            unit = "ms";
        }
        out = frac_string(u, prec) + unit;
    } else {
        let secs_part = frac_string(u, 9); // seconds with fraction
        let total_secs = u / second();
        let s = total_secs % 60;
        let frac_ns = u % second();
        let sec_str = frac_string(s * second() + frac_ns, 9) + "s";
        let mins = total_secs / 60;
        if (mins > 0) {
            let m = mins % 60;
            let hours = mins / 60;
            sec_str = m.to_string() + "m" + sec_str;
            if (hours > 0) {
                sec_str = hours.to_string() + "h" + sec_str;
            }
        }
        let _ = secs_part;
        out = sec_str;
    }
    if (neg) { "-" + out } else { out }
}

// v / 10^prec rendered with the fraction's trailing zeros (and a bare ".")
// removed, like Go's fmtFrac + fmtInt.
function frac_string(v: int, prec: int) -> string throws never {
    let scale = 1;
    let i = 0;
    while (i < prec) {
        scale *= 10;
        i += 1;
    }
    let whole = v / scale;
    let frac = v % scale;
    if (prec == 0 || frac == 0) {
        return whole.to_string();
    }
    let fs = frac.to_string();
    while (fs.length() < prec) {
        fs = "0" + fs;
    }
    while (fs.ends_with("0")) {
        fs = fs.slice(0, fs.length() - 1);
    }
    whole.to_string() + "." + fs
}

// time.ParseDuration. Returns null on error.
function parse_duration(s0: string) -> Duration? {
    // [-+]?([0-9]*(\.[0-9]*)?[a-z]+)+
    let s = s0;
    let d = 0;
    let neg = false;

    // Consume [-+]?
    if (s != "") {
        let c = s.slice(0, 1);
        if (c == "-" || c == "+") {
            neg = c == "-";
            s = s.slice(1, s.length());
        }
    }
    // Special case: if all that is left is "0", this is zero.
    if (s == "0") {
        return Duration { ns: 0 };
    }
    if (s == "") {
        return null;
    }
    while (s != "") {
        // The next character must be [0-9.]
        let c = s.slice(0, 1);
        if (!(c == "." || (c >= "0" && c <= "9"))) {
            return null;
        }
        // Consume [0-9]*
        let pl = s.length();
        let i = 0;
        while (i < s.length() && is_digit_str(s, i)) {
            i += 1;
        }
        let int_str = s.slice(0, i);
        s = s.slice(i, s.length());
        let pre = pl != s.length(); // whether we consumed anything before a period

        // Consume (\.[0-9]*)?
        let post = false;
        let frac_str = "";
        if (s != "" && s.slice(0, 1) == ".") {
            s = s.slice(1, s.length());
            let pl2 = s.length();
            let j = 0;
            while (j < s.length() && is_digit_str(s, j)) {
                j += 1;
            }
            frac_str = s.slice(0, j);
            s = s.slice(j, s.length());
            post = pl2 != s.length();
        }
        if (!pre && !post) {
            // no digits (e.g. ".s" or "-.s")
            return null;
        }

        // Consume unit.
        let k = 0;
        while (k < s.length()) {
            let ch = s.slice(k, k + 1);
            if (ch == "." || (ch >= "0" && ch <= "9")) {
                break;
            }
            k += 1;
        }
        if (k == 0) {
            return null; // missing unit
        }
        let u = s.slice(0, k);
        s = s.slice(k, s.length());
        let unit = match (u) {
            "ns" => nanosecond(),
            "us" | "µs" | "μs" => microsecond(),
            "ms" => millisecond(),
            "s" => second(),
            "m" => minute(),
            "h" => hour(),
            _ => -1,
        };
        if (unit < 0) {
            return null; // unknown unit
        }
        let v = if (int_str == "") { 0 } else { atoi_or(int_str, -1) };
        if (v < 0) {
            return null;
        }
        d += v * unit;
        if (frac_str != "") {
            // Add the fractional part, truncating like Go.
            let scale = 1;
            let f = 0;
            for (let fc in frac_str.chars()) {
                if (scale * 10 > 1000000000000000000 / 10) {
                    break;
                }
                f = f * 10 + atoi_or(fc, 0);
                scale *= 10;
            }
            d += truncate_float((0.0 + f) * (0.0 + unit) / (0.0 + scale));
        }
    }
    if (neg) {
        return Duration { ns: -d };
    }
    Duration { ns: d }
}

function truncate_float(f: float) -> int {
    f.itrunc() catch (e) {
        _ => 0
    }
}
