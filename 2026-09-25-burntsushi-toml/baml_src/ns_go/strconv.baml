// Shim: the parts of Go's `strconv`, `strings` and `math` that the toml
// package uses.

class ParseIntResult {
    value: bigint,
    // "" on success, "syntax" or "range" (strconv.ErrSyntax / ErrRange).
    err: string,
}

class ParseFloatResult {
    value: float,
    err: string,
}

function digit_value(c: int) -> int {
    if (c >= 48 && c <= 57) {
        return c - 48;
    }
    if (c >= 97 && c <= 122) {
        return c - 97 + 10;
    }
    if (c >= 65 && c <= 90) {
        return c - 65 + 10;
    }
    99
}

/// strconv.ParseInt(s, base, bitSize) for bitSize 64. With base 0 the base is
/// implied by the prefix (0x, 0o, 0b, or a leading 0 for octal), and
/// underscores are permitted as digit separators, as in Go.
function parse_int(s0: string, base0: int, bit_size: int) -> ParseIntResult {
    let s = bytes_of(s0);
    if (s.length() == 0) {
        return ParseIntResult { value: 0n, err: "syntax" };
    }
    let neg = false;
    let i = 0;
    if (s[0] == 43) {
        i = 1;
    } else if (s[0] == 45) {
        neg = true;
        i = 1;
    }
    let base = base0;
    let allow_underscores = false;
    if (base == 0) {
        allow_underscores = true;
        base = 10;
        if (i < s.length() && s[i] == 48) {
            if (i + 2 < s.length() + 1 && i + 1 < s.length() && (s[i + 1] | 32) == 120) {
                base = 16;
                i += 2;
            } else if (i + 1 < s.length() && (s[i + 1] | 32) == 111) {
                base = 8;
                i += 2;
            } else if (i + 1 < s.length() && (s[i + 1] | 32) == 98) {
                base = 2;
                i += 2;
            } else {
                base = 8;
                i += 1;
            }
        }
    }
    if (i >= s.length() && !(base == 8 && s0 != "" && i > 0 && s[i - 1] == 48)) {
        return ParseIntResult { value: 0n, err: "syntax" };
    }
    let n = 0n;
    let saw_digit = false;
    while (i < s.length()) {
        let c = s[i];
        if (c == 95 && allow_underscores) {
            i += 1;
            continue;
        }
        let d = digit_value(c);
        if (d >= base) {
            return ParseIntResult { value: 0n, err: "syntax" };
        }
        n = n * base + d;
        saw_digit = true;
        i += 1;
    }
    if (neg) {
        n = -n;
    }
    let bits = 1n << (bit_size - 1);
    if (n >= bits || n < -bits) {
        return ParseIntResult { value: n, err: "range" };
    }
    ParseIntResult { value: n, err: "" }
}

/// strconv.ParseUint(s, 16, 32) for the short hex strings produced by the
/// lexer. Returns -1 on a syntax error.
function parse_hex(s: string) -> int {
    if (s.length() == 0) {
        return -1;
    }
    let n = 0;
    for (let c in bytes_of(s)) {
        let d = digit_value(c);
        if (d >= 16) {
            return -1;
        }
        n = n * 16 + d;
    }
    n
}

/// strconv.ParseFloat(s, 64). BAML's float.parse does the actual conversion;
/// Go's out-of-range rule (a finite literal that rounds to ±Inf) is layered on
/// top.
function parse_float(s: string) -> ParseFloatResult {
    let lower = s.to_lower_case();
    let unsigned = if (lower.starts_with("+") || lower.starts_with("-")) {
        lower.slice(1, lower.length())
    } else {
        lower
    };
    let f = float.parse(s) catch (e) {
        _ => {
            return ParseFloatResult { value: 0.0, err: "syntax" };
        },
    };
    if (f.is_infinite() && unsigned != "inf" && unsigned != "infinity") {
        return ParseFloatResult { value: f, err: "range" };
    }
    ParseFloatResult { value: f, err: "" }
}

/// math.Signbit. NaN's sign cannot be observed in BAML (see PORTING_NOTES.md),
/// so it reports false for every NaN.
function signbit(f: float) -> bool {
    if (f.is_nan()) {
        return false;
    }
    if (f == 0.0) {
        return 1.0 / f < 0.0;
    }
    f < 0.0
}

/// math.Copysign.
function copysign(f: float, sign: float) -> float {
    if (signbit(f) != signbit(sign)) {
        return -f;
    }
    f
}

/// The shortest decimal digits of a finite, non-zero |f| together with the
/// position of the decimal point (Go's `decimalSlice{d, nd, dp}`), recovered
/// from BAML's shortest round-trip positional rendering.
class DecimalDigits {
    digits: string,
    dp: int,
}

function shortest_digits(f: float) -> DecimalDigits {
    let s = f.abs().to_string();
    let parts = s.split(".");
    let int_part = parts[0];
    let frac_part = if (parts.length() > 1) { parts[1] } else { "" };
    let all = int_part + frac_part;
    let dp = int_part.length();
    // Strip leading zeros (adjusting the decimal point).
    let start = 0;
    while (start < all.length() && all.at(start) == "0") {
        start += 1;
        dp -= 1;
    }
    let end = all.length();
    while (end > start && all.at(end - 1) == "0") {
        end -= 1;
    }
    if (start >= end) {
        return DecimalDigits { digits: "0", dp: 1 };
    }
    DecimalDigits { digits: all.slice(start, end), dp: dp }
}

/// strconv.FormatFloat(f, 'g', -1, bitSize).
///
/// bitSize 32 formats the float64 value's shortest digits: BAML has no float32
/// type, so a float32's own shortest representation cannot be recovered.
function format_float_g(f: float, bit_size: int) -> string {
    if (f.is_nan()) {
        return "NaN";
    }
    if (f.is_infinite()) {
        return if (f > 0.0) { "+Inf" } else { "-Inf" };
    }
    let neg = signbit(f);
    let sign = if (neg) { "-" } else { "" };
    if (f == 0.0) {
        return sign + "0";
    }
    let d = shortest_digits(f);
    let nd = d.digits.length();
    let exp = d.dp - 1;
    // Go: "if precision was the shortest possible, use precision 6 for this
    // decision" (eprec = 6).
    let eprec = 6;
    if (eprec > nd && nd >= d.dp) {
        eprec = nd;
    }
    eprec = 6;
    if (exp < -4 || exp >= eprec) {
        let mant = d.digits.slice(0, 1);
        if (nd > 1) {
            mant += "." + d.digits.slice(1, nd);
        }
        let esign = if (exp < 0) { "-" } else { "+" };
        let e = if (exp < 0) { -exp } else { exp };
        let es = e.to_string();
        if (es.length() < 2) {
            es = "0" + es;
        }
        return sign + mant + "e" + esign + es;
    }
    // %f with max(nd-dp, 0) fraction digits.
    if (d.dp <= 0) {
        return sign + "0." + "0".repeat(-d.dp) + d.digits;
    }
    if (d.dp >= nd) {
        return sign + d.digits + "0".repeat(d.dp - nd);
    }
    sign + d.digits.slice(0, d.dp) + "." + d.digits.slice(d.dp, nd)
}

/// fmt's %f (precision 6) for a finite float.
function format_float_f6(f: float) -> string {
    if (f.is_nan()) {
        return "NaN";
    }
    if (f.is_infinite()) {
        return if (f > 0.0) { "+Inf" } else { "-Inf" };
    }
    let neg = f < 0.0;
    let a = f.abs();
    // Round to 6 decimals using the shortest digits, done in decimal to avoid
    // binary rounding artefacts.
    let d = shortest_digits(a);
    if (a == 0.0) {
        d = DecimalDigits { digits: "0", dp: 1 };
    }
    // Build the digit string with exactly 6 fraction digits (+1 for rounding).
    let digits = d.digits;
    let dp = d.dp;
    let int_part = "";
    let frac = "";
    if (dp <= 0) {
        int_part = "0";
        frac = "0".repeat(-dp) + digits;
    } else if (dp >= digits.length()) {
        int_part = digits + "0".repeat(dp - digits.length());
        frac = "";
    } else {
        int_part = digits.slice(0, dp);
        frac = digits.slice(dp, digits.length());
    }
    while (frac.length() < 7) {
        frac += "0";
    }
    let keep = int_part + frac.slice(0, 6);
    let round_up = frac.slice(6, 7) >= "5";
    if (round_up) {
        keep = decimal_increment(keep);
    }
    let il = keep.length() - 6;
    let out = keep.slice(0, il) + "." + keep.slice(il, keep.length());
    if (neg) { "-" + out } else { out }
}

function decimal_increment(s: string) -> string {
    let cs = s.chars();
    let i = cs.length() - 1;
    while (i >= 0) {
        if (cs[i] == "9") {
            cs[i] = "0";
            i -= 1;
        } else {
            let d = int.parse(cs[i]) catch (e) { _ => 0 };
            cs[i] = (d + 1).to_string();
            return cs.join("");
        }
    }
    "1" + cs.join("")
}

/// strconv.FormatBool / fmt %v of a bool.
function format_bool(b: bool) -> string {
    if (b) { "true" } else { "false" }
}

// ---- strings ----

/// strings.HasPrefix on byte slices.
function has_prefix(s: int[], prefix: int[]) -> bool {
    if (s.length() < prefix.length()) {
        return false;
    }
    let i = 0;
    while (i < prefix.length()) {
        if (s[i] != prefix[i]) {
            return false;
        }
        i += 1;
    }
    true
}

/// Index of byte `c` in s at or after `from`, or -1 (strings.IndexByte).
function index_byte(s: int[], from: int, c: int) -> int {
    let i = from;
    while (i < s.length()) {
        if (s[i] == c) {
            return i;
        }
        i += 1;
    }
    -1
}

/// `for _, r := range s` — the runes of a string.
function runes_of(s: string) -> int[] {
    s.to_code_points()
}

/// strings.FieldsFunc with a predicate on one-character strings.
function fields_func(s: string, f: (string) -> bool) -> string[] {
    let out: string[] = [];
    let cur = "";
    let in_field = false;
    for (let c in s.chars()) {
        if (f(c)) {
            if (in_field) {
                out.push(cur);
                cur = "";
                in_field = false;
            }
        } else {
            cur += c;
            in_field = true;
        }
    }
    if (in_field) {
        out.push(cur);
    }
    out
}

/// strings.EqualFold (simple Unicode case folding approximated with
/// to_lower_case).
function equal_fold(a: string, b: string) -> bool {
    a == b || a.to_lower_case() == b.to_lower_case()
}

/// strings.Map-style replacement of several literal substrings at once, as
/// strings.NewReplacer(old1, new1, ...).Replace(s): at every position the
/// first matching `old` in argument order wins.
function replace_many(s: string, pairs: string[][]) -> string {
    let out = "";
    let cs = s.chars();
    let i = 0;
    while (i < cs.length()) {
        let matched = false;
        for (let p in pairs) {
            let old = p[0];
            let n = old.length();
            if (n > 0 && i + n <= cs.length() && cs.slice(i, i + n).join("") == old) {
                out += p[1];
                i += n;
                matched = true;
                break;
            }
        }
        if (!matched) {
            out += cs[i];
            i += 1;
        }
    }
    out
}

/// strconv.Itoa for big integers.
function itoa(n: int) -> string {
    n.to_string()
}
