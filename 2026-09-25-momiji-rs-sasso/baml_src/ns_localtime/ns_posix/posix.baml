// Ported from sasso `src/localtime/posix.rs` (namespace `root.localtime.posix`).
//
// The POSIX TZ string, which is where a TZif file's answers come from once
// its transition table runs out (RFC 8536 §3.3).
//
// Tables stop around 2037 by convention, so without this a timestamp in
// 2038 is an hour out for half the year — measured, not assumed: the first
// version of this reader was exactly one hour wrong for
// `America/New_York` on 2065-07-01.
//
// The grammar, from the footers actually shipped in tzdata:
//
// ```text
// EST5EDT,M3.2.0,M11.1.0                      ordinary northern DST
// GMT0IST,M3.5.0/1,M10.5.0                    a transition at 01:00
// <+1030>-10:30<+11>-11,M10.1.0,M4.1.0        southern: DST spans New Year
// <+1245>-12:45<+1345>,M9.5.0/2:45,M4.1.0/3:45   45-minute offsets
// <-02>2<-01>,M3.5.0/-1,M10.5.0/0             a NEGATIVE transition time
// <+0545>-5:45                                fixed offset, no DST at all
// ```
//
// Two traps worth stating because they are silent when wrong:
//
// 1. POSIX writes offsets **west-positive** — `EST5` means UTC-5. Every
//    other number in this module is east-positive, so the sign is flipped
//    the moment it is parsed and never again.
// 2. The two rule times are in **different clocks**: the start is local
//    standard time, the end is local daylight time. Using one offset for
//    both misplaces each transition by an hour, which only shows up within
//    an hour of a transition and so survives casual testing.

/// When a transition happens, within a year.
interface Rule {}

/// `Mm.w.d` — the `w`-th `d`-weekday of month `m`, where `w == 5` means
/// the last one, whether that is the fourth or the fifth.
class Rule_Month {
    month: int,
    week: int,
    weekday: int,
    implements Rule {}
}

/// `Jn` — day `n` of the year, 1..=365, never counting 29 February.
class Rule_Julian {
    _0: int,
    implements Rule {}
}

/// `n` — day `n`, 0..=365, counting 29 February.
class Rule_Zero {
    _0: int,
    implements Rule {}
}

/// A parsed POSIX TZ string. Offsets are east-positive seconds.
class Posix {
    std_offset: int,
    /// `None` for a zone with no daylight saving, which is most of them.
    dst: Dst?,
}

class Dst {
    offset: int,
    start: Rule,
    /// Seconds after local midnight, in STANDARD time. May be negative.
    start_time: int,
    end: Rule,
    /// Seconds after local midnight, in DAYLIGHT time. May be negative.
    end_time: int,
}

class Cursor {
    s: uint8array,
    i: int,
    function peek(self) -> int? {
        self.s.at(self.i)
    }

    function eat(self, c: int) -> bool {
        if (self.peek() == c) {
            self.i += 1;
            true
        } else {
            false
        }
    }

    function number(self) -> int? {
        let start = self.i;
        // b'0'..=b'9'
        while (
            match (self.peek()) {
                let b: int if b >= 48 && b <= 57 => true,
                _ => false,
            }
        ) {
            self.i += 1;
        }
        if (self.i == start || self.i - start > 6) {
            return null; // empty, or long enough to be junk
        }
        let n: int = 0;
        for (let b in self.s.slice(start, self.i).to_array()) {
            n = n * 10 + (b - 48);
        }
        n
    }

    /// A zone abbreviation, which carries no information we use — only its
    /// length matters, so it is skipped rather than kept. Either `<...>` or
    /// a run of letters.
    // PORT: Rust returns `Option<()>`; here `true` is `Some(())`, `false` is `None`.
    function skip_name(self) -> bool {
        if (self.eat(60)) { // b'<'
            while let c: int = self.peek() {
                self.i += 1;
                if (c == 62) { // b'>'
                    return true;
                }
            }
            return false; // unterminated
        }
        let start = self.i;
        // `c.is_ascii_alphabetic()`
        while (
            match (self.peek()) {
                let c: int if c >= 65 && c <= 90 || c >= 97 && c <= 122 => true,
                _ => false,
            }
        ) {
            self.i += 1;
        }
        self.i > start
    }

    /// `[+|-]hh[:mm[:ss]]`, returned east-positive (POSIX writes it the
    /// other way round, so an unsigned value comes back negated).
    function offset(self) -> int? {
        let west = self.signed()
            ?? return null;
        -west
    }

    /// The same syntax as an offset but used for a time of day, where the
    /// sign means what it says and is not flipped.
    function time(self) -> int? {
        self.signed()
    }

    function signed(self) -> int? {
        let neg = if (self.eat(45)) { // b'-'
            true
        } else {
            let _ = self.eat(43); // b'+'
            false
        };
        let secs = checked_mul(
            self.number()
                ?? return null,
            3600,
        )
            ?? return null;
        if (self.eat(58)) { // b':'
            secs
                = checked_add(
                    secs,
                    (
                        self.number()
                            ?? return null
                    )
                        * 60,
                )
                    ?? return null;
            if (self.eat(58)) { // b':'
                secs
                    = checked_add(
                        secs,
                        self.number()
                            ?? return null,
                    )
                        ?? return null;
            }
        }
        if (neg) {
            -secs
        } else {
            secs
        }
    }

    function rule(self) -> root.std.Tuple2<Rule, int>? {
        let rule: Rule = if (self.eat(77)) { // b'M'
            let month = self.number()
                ?? return null;
            if (!self.eat(46)) { // b'.'
                return null;
            }
            let week = self.number()
                ?? return null;
            if (!self.eat(46)) { // b'.'
                return null;
            }
            let weekday = self.number()
                ?? return null;
            if (!(month >= 1 && month <= 12) || !(week >= 1 && week <= 5) || weekday > 6) {
                return null;
            }
            Rule_Month { month: month, week: week, weekday: weekday }
        } else if (self.eat(74)) { // b'J'
            let n = self.number()
                ?? return null;
            if (!(n >= 1 && n <= 365)) {
                return null;
            }
            Rule_Julian { _0: n }
        } else {
            let n = self.number()
                ?? return null;
            if (n > 365) {
                return null;
            }
            Rule_Zero { _0: n }
        };
        // Default 02:00:00 when the `/time` part is absent.
        let time = if (self.eat(47)) {
            self.time()
                ?? return null
        } else {
            2 * 3600
        }; // b'/'
        root.std.Tuple2 { _0: rule, _1: time }
    }
}

/// `i64::checked_mul`.
// PORT: helper for Rust's checked arithmetic; the bound is BAML's 63-bit int
// range rather than i64's.
function checked_mul(a: int, b: int) -> int? {
    let r = root.std.bigint_of(a) * root.std.bigint_of(b);
    if (r > root.std.bigint_of(root.std.INT_MAX()) || r < root.std.bigint_of(root.std.INT_MIN())) {
        null
    } else {
        root.std.int_of(r)
    }
}

/// `i64::checked_add`.
// PORT: helper for Rust's checked arithmetic; the bound is BAML's 63-bit int
// range rather than i64's.
function checked_add(a: int, b: int) -> int? {
    let r = root.std.bigint_of(a) + root.std.bigint_of(b);
    if (r > root.std.bigint_of(root.std.INT_MAX()) || r < root.std.bigint_of(root.std.INT_MIN())) {
        null
    } else {
        root.std.int_of(r)
    }
}

/// Parse a POSIX TZ string. Returns `None` on anything it does not fully
/// understand — a partly-understood rule would be worse than no rule,
/// because the caller can fall back to the last tabulated offset.
function parse(s: string) -> Posix? {
    let c = Cursor { s: s.to_utf8(), i: 0 };
    if (!c.skip_name()) {
        return null;
    }
    let std_offset = c.offset()
        ?? return null;
    if (c.i == c.s.length()) {
        return Posix { std_offset: std_offset, dst: null };
    }
    if (!c.skip_name()) {
        return null;
    }
    // An omitted DST offset means one hour east of standard.
    let offset = if (c.peek() == 44) { // b','
        std_offset + 3600
    } else {
        c.offset()
            ?? return null
    };
    if (!c.eat(44)) { // b','
        return null;
    }
    let start_rule = c.rule()
        ?? return null;
    let start = start_rule._0;
    let start_time = start_rule._1;
    if (!c.eat(44)) { // b','
        return null;
    }
    let end_rule = c.rule()
        ?? return null;
    let end = end_rule._0;
    let end_time = end_rule._1;
    if (c.i != c.s.length()) {
        return null; // trailing junk: do not guess
    }
    Posix {
        std_offset: std_offset,
        dst: Dst { offset: offset, start: start, start_time: start_time, end: end, end_time: end_time },
    }
}

/// Days from 1 January of `year` to the day a rule names.
function day_of_year(rule: Rule, year: int) -> int {
    match (rule) {
        // Julian days never count 29 February, so from 1 March onwards in a
        // leap year the ordinal and the actual day part company by one.
        Rule_Julian { _0: let n } => {
            if (root.localtime.civil.is_leap(year) && n >= 60) {
                n
            } else {
                n - 1
            }
        },
        Rule_Zero { _0: let n } => n,
        Rule_Month { month: let month, week: let week, weekday: let want } => {
            let first = root.localtime.civil.days_from_civil(year, month, 1);
            let shift = root.std.rem_euclid(want - root.localtime.civil.weekday(first), 7);
            let day = 1 + shift + (week - 1) * 7;
            // `week == 5` means "the last such weekday", which for a month
            // with only four of them overshoots; step back until it fits.
            let last = root.localtime.civil.days_in_month(year, month);
            while (day > last) {
                day -= 7;
            }
            root.localtime.civil.days_from_civil(year, month, day)
                - root.localtime.civil.days_from_civil(year, 1, 1)
        },
        _ => root.std.unreachable(),
    }
}

/// The UTC offset this rule set gives at `secs`.
function offset_at(p: Posix, secs: int) -> int {
    let dst = p.dst;
    if (dst == null) {
        return p.std_offset;
    }
    // Which local year is it? Standard time picks the right one except
    // within an hour of New Year, where either answer gives the same
    // in/out-of-DST verdict anyway.
    let year = root.localtime.civil.civil_from_days(root.std.div_euclid(secs + p.std_offset, 86400))._0;
    let jan1 = root.localtime.civil.days_from_civil(year, 1, 1);

    // The two times are in different clocks — see the module docs.
    let start = (jan1 + day_of_year(dst.start, year)) * 86400 + dst.start_time - p.std_offset;
    let end = (jan1 + day_of_year(dst.end, year)) * 86400 + dst.end_time - dst.offset;

    let in_dst = if (start <= end) {
        secs >= start && secs < end // northern hemisphere
    } else {
        secs >= start || secs < end // southern: the DST window spans New Year
    };
    if (in_dst) {
        dst.offset
    } else {
        p.std_offset
    }
}
