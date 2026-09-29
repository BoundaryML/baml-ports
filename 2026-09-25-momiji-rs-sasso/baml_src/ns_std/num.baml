// Numeric helpers: Rust's `as` casts, f64 bit patterns, Rust float
// formatting, wrapping/checked integer arithmetic, min/max.
//
// BAML `int` is 63-bit (±2^62). Rust integers that can exceed that — `u64`
// hashes and bit patterns, `u128` — are `bigint` here.

/// 2^64 - 1, the `u64` mask.
function U64_MASK() -> bigint {
    18446744073709551615n
}

/// 2^32 - 1.
function U32_MASK() -> int {
    4294967295
}

/// `i64::MAX` clamped into BAML's int range (BAML ints are 63-bit).
function INT_MAX() -> int {
    4611686018427387903
}

function INT_MIN() -> int {
    -4611686018427387904
}

// ---------------------------------------------------------------- f64 consts

function F64_EPSILON() -> float {
    2.220446049250313e-16
}

function F64_MAX() -> float {
    1.7976931348623157e308
}

function F64_MIN() -> float {
    -1.7976931348623157e308
}

function F64_MIN_POSITIVE() -> float {
    2.2250738585072014e-308
}

function F64_INFINITY() -> float {
    1.0 / 0.0
}

function F64_NEG_INFINITY() -> float {
    -1.0 / 0.0
}

function F64_NAN() -> float {
    0.0 / 0.0
}

function F64_PI() -> float {
    3.141592653589793
}

function F64_E() -> float {
    2.718281828459045
}

// ---------------------------------------------------------------- f64 bits

/// Exact 2^k as a float, for k in [-1074, 1023].
function pow2(k: int) -> float {
    if (k > 1023) {
        return 1.0 / 0.0;
    }
    if (k < -1074) {
        return 0.0;
    }
    if (k >= -1022) {
        return 2.0.pow(k * 1.0);
    }
    // Subnormal: scale in two exact steps.
    2.0.pow((k + 600) * 1.0) * 2.0.pow(-600.0)
}

/// Whether `x` is negative zero or negative (sign bit set).
function is_sign_negative(x: float) -> bool {
    if (x.is_nan()) {
        return false;
    }
    x < 0.0 || (x == 0.0 && 1.0 / x < 0.0)
}

/// `x.is_sign_positive()`.
function is_sign_positive(x: float) -> bool {
    !is_sign_negative(x)
}

/// `f64::to_bits` as an unsigned 64-bit pattern (a `bigint`). A NaN maps to
/// the canonical quiet NaN `0x7ff8000000000000`.
function f64_to_bits(x: float) -> bigint {
    if (x.is_nan()) {
        return 9221120237041090560n;
    }
    let sign: bigint = if (is_sign_negative(x)) {
        1n
    } else {
        0n
    };
    let a = x.abs();
    if (a == 0.0) {
        return sign << 63;
    }
    if (a.is_infinite()) {
        return (sign << 63) | (2047n << 52);
    }
    // Find e with 2^e <= a < 2^(e+1).
    let e = a.log2().floor().itrunc() catch (err) {
        _ => 0
    };
    if (e > 1023) {
        e = 1023;
    }
    if (e < -1074) {
        e = -1074;
    }
    while (e > -1074 && pow2(e) > a) {
        e -= 1;
    }
    while (e < 1023 && pow2(e + 1) <= a) {
        e += 1;
    }
    if (e >= -1022) {
        // Normal: a / 2^e in [1, 2), exact.
        let frac = (a / pow2(e) - 1.0) * 4503599627370496.0;
        let mant = frac.itrunc() catch (err) {
            _ => 0
        };
        let biased = e + 1023;
        (sign << 63) | (bigint_of(biased) << 52) | bigint_of(mant)
    } else {
        // Subnormal: a * 2^1074 is the integer mantissa, exact.
        let m = a * 2.0.pow(537.0) * 2.0.pow(537.0);
        let mant = m.itrunc() catch (err) {
            _ => 0
        };
        (sign << 63) | bigint_of(mant)
    }
}

/// `f64::from_bits` of an unsigned 64-bit pattern (a `bigint`).
function f64_from_bits(bits: bigint) -> float {
    let b = bits & U64_MASK();
    let sign = ((b >> 63) & 1n) == 1n;
    let exp = int_of((b >> 52) & 2047n);
    let mant = int_of(b & 4503599627370495n);
    let mag = if (exp == 2047) {
        if (mant == 0) {
            1.0 / 0.0
        } else {
            0.0 / 0.0
        }
    } else if (exp == 0) {
        mant * 1.0 * 2.0.pow(-537.0) * 2.0.pow(-537.0)
    } else {
        let m = (4503599627370496 + mant) * 1.0;
        let k = exp - 1075;
        if (k >= -1022) {
            m * pow2(k)
        } else {
            m * pow2(k + 600) * pow2(-600)
        }
    };
    if (sign) {
        -mag
    } else {
        mag
    }
}

/// A `bigint` from an `int`.
function bigint_of(i: int) -> bigint {
    let z: bigint = 0n;
    z + i
}

/// An `int` from a `bigint` that is known to fit (panics otherwise).
function int_of(b: bigint) -> int {
    b.to_int() catch (e) {
        _ => baml.sys.panic(`std.int_of: ${b} does not fit in int`)
    }
}

// ---------------------------------------------------------------- `as` casts

/// `x as i64` (and `as i32`/`as isize` when the value is known to fit):
/// truncates toward zero, saturates, NaN -> 0. BAML ints are 63-bit, so the
/// saturation bounds are BAML's.
function f64_to_int(x: float) -> int {
    if (x.is_nan()) {
        return 0;
    }
    if (x >= 4611686018427387903.0) {
        return INT_MAX();
    }
    if (x <= -4611686018427387904.0) {
        return INT_MIN();
    }
    x.itrunc() catch (e) {
        _ => 0
    }
}

/// `x as i32`: truncate toward zero, saturate to i32, NaN -> 0.
function f64_to_i32(x: float) -> int {
    let i = f64_to_int(x);
    if (i > 2147483647) {
        2147483647
    } else if (i < -2147483648) {
        -2147483648
    } else {
        i
    }
}

/// `x as u32`: truncate toward zero, saturate to [0, u32::MAX], NaN -> 0.
function f64_to_u32(x: float) -> int {
    let i = f64_to_int(x);
    if (i < 0) {
        0
    } else if (i > 4294967295) {
        4294967295
    } else {
        i
    }
}

/// `x as u8`: truncate toward zero, saturate to [0, 255], NaN -> 0.
function f64_to_u8(x: float) -> int {
    let i = f64_to_int(x);
    if (i < 0) {
        0
    } else if (i > 255) {
        255
    } else {
        i
    }
}

/// `x as usize` / `x as u64`: truncate, saturate at 0, NaN -> 0.
function f64_to_usize(x: float) -> int {
    let i = f64_to_int(x);
    if (i < 0) {
        0
    } else {
        i
    }
}

/// `i as f64`.
function int_to_f64(i: int) -> float {
    i * 1.0
}

/// `i as u8` (wrapping).
function as_u8(i: int) -> int {
    i & 255
}

/// `i as u16` (wrapping).
function as_u16(i: int) -> int {
    i & 65535
}

/// `i as u32` (wrapping).
function as_u32(i: int) -> int {
    i & 4294967295
}

/// `i as i32` (wrapping, from any int).
function as_i32(i: int) -> int {
    let u = i & 4294967295;
    if (u >= 2147483648) {
        u - 4294967296
    } else {
        u
    }
}

/// `i as i8` (wrapping).
function as_i8(i: int) -> int {
    let u = i & 255;
    if (u >= 128) {
        u - 256
    } else {
        u
    }
}

// ---------------------------------------------------------------- float ops

/// `a.max(b)` for f64: NaN is ignored if the other is a number.
function fmax(a: float, b: float) -> float {
    if (a.is_nan()) {
        return b;
    }
    if (b.is_nan()) {
        return a;
    }
    if (a > b) {
        a
    } else if (b > a) {
        b
    } else if (is_sign_negative(a)) {
        b
    } else {
        a
    }
}

/// `a.min(b)` for f64: NaN is ignored if the other is a number.
function fmin(a: float, b: float) -> float {
    if (a.is_nan()) {
        return b;
    }
    if (b.is_nan()) {
        return a;
    }
    if (a < b) {
        a
    } else if (b < a) {
        b
    } else if (is_sign_negative(a)) {
        a
    } else {
        b
    }
}

/// `x.clamp(lo, hi)` for f64 — a NaN `x` stays NaN (BAML's total order
/// would otherwise sort NaN above `hi`).
function fclamp(x: float, lo: float, hi: float) -> float {
    if (x.is_nan()) {
        return x;
    }
    if (x < lo) {
        lo
    } else if (x > hi) {
        hi
    } else {
        x
    }
}

/// `x.rem_euclid(m)` for f64.
function f_rem_euclid(x: float, m: float) -> float {
    let r = x % m;
    if (r < 0.0) {
        r + m.abs()
    } else {
        r
    }
}

/// `x.div_euclid(m)` for f64.
function f_div_euclid(x: float, m: float) -> float {
    let q = (x / m).trunc();
    if (x % m < 0.0) {
        if (m > 0.0) {
            q - 1.0
        } else {
            q + 1.0
        }
    } else {
        q
    }
}

/// `x.fract()` as Rust defines it: `x - x.trunc()`.
function fract(x: float) -> float {
    x - x.trunc()
}

/// `x.powi(n)` as LLVM lowers it (`__powidf2`: repeated squaring, then a
/// reciprocal for a negative exponent) — NOT `powf`, which can differ in the
/// last bit.
function powi(x: float, n: int) -> float {
    let recip = n < 0;
    let b = if (recip) {
        0 - n
    } else {
        n
    };
    let a = x;
    let r = 1.0;
    while (true) {
        if ((b & 1) != 0) {
            r = r * a;
        }
        b = b / 2;
        if (b == 0) {
            break;
        }
        a = a * a;
    }
    if (recip) {
        1.0 / r
    } else {
        r
    }
}

/// `x.copysign(sign)`.
function copysign(x: float, sign: float) -> float {
    let mag = x.abs();
    if (is_sign_negative(sign)) {
        -mag
    } else {
        mag
    }
}

// ---------------------------------------------------------------- int ops

function imax(a: int, b: int) -> int {
    if (a >= b) {
        a
    } else {
        b
    }
}

function imin(a: int, b: int) -> int {
    if (a <= b) {
        a
    } else {
        b
    }
}

function iclamp(x: int, lo: int, hi: int) -> int {
    if (x < lo) {
        lo
    } else if (x > hi) {
        hi
    } else {
        x
    }
}

/// `a.rem_euclid(m)` for ints.
function rem_euclid(a: int, m: int) -> int {
    let r = a % m;
    if (r < 0) {
        r + m.abs()
    } else {
        r
    }
}

/// `a.div_euclid(m)` for ints.
function div_euclid(a: int, m: int) -> int {
    let q = a / m;
    if (a % m < 0) {
        if (m > 0) {
            q - 1
        } else {
            q + 1
        }
    } else {
        q
    }
}

/// `a.saturating_sub(b)` for unsigned ints (floors at 0).
function saturating_sub_u(a: int, b: int) -> int {
    if (a > b) {
        a - b
    } else {
        0
    }
}

/// `a.checked_sub(b)` for unsigned ints (`None` below 0).
function checked_sub_u(a: int, b: int) -> int? {
    if (a >= b) {
        a - b
    } else {
        null
    }
}

/// `a.abs_diff(b)`.
function abs_diff(a: int, b: int) -> int {
    if (a > b) {
        a - b
    } else {
        b - a
    }
}

/// `a.wrapping_add(b)` for `u32`.
function u32_wrapping_add(a: int, b: int) -> int {
    (a + b) & 4294967295
}

/// `a.wrapping_sub(b)` for `u32`.
function u32_wrapping_sub(a: int, b: int) -> int {
    (a - b) & 4294967295
}

/// `a.wrapping_mul(b)` for `u32` (split into 16-bit halves so the product
/// never leaves BAML's 63-bit range).
function u32_wrapping_mul(a: int, b: int) -> int {
    let a_lo = a & 65535;
    let a_hi = (a >> 16) & 65535;
    let b_lo = b & 65535;
    let lo = a_lo * b_lo;
    let mid = (a_hi * b_lo + a_lo * ((b >> 16) & 65535)) & 65535;
    (lo + (mid << 16)) & 4294967295
}

/// `a.rotate_left(n)` for `u32`.
function u32_rotate_left(a: int, n: int) -> int {
    let k = n % 32;
    ((a << k) | (a >> (32 - k))) & 4294967295
}

/// `a.wrapping_add(b)` for `u64` (as bigint).
function u64_wrapping_add(a: bigint, b: bigint) -> bigint {
    (a + b) & U64_MASK()
}

/// `a.wrapping_sub(b)` for `u64` (as bigint).
function u64_wrapping_sub(a: bigint, b: bigint) -> bigint {
    (a - b) & U64_MASK()
}

/// `a.wrapping_mul(b)` for `u64` (as bigint).
function u64_wrapping_mul(a: bigint, b: bigint) -> bigint {
    (a * b) & U64_MASK()
}

/// `a.rotate_left(n)` for `u64` (as bigint).
function u64_rotate_left(a: bigint, n: int) -> bigint {
    let k = n % 64;
    ((a << k) | (a >> (64 - k))) & U64_MASK()
}

/// `a.leading_zeros()` for a `u64` held in a bigint.
function u64_leading_zeros(a: bigint) -> int {
    let v = a & U64_MASK();
    if (v == 0n) {
        return 64;
    }
    let n = 0;
    let probe: bigint = 1n << 63;
    while ((v & probe) == 0n) {
        n += 1;
        probe = probe >> 1;
    }
    n
}

/// `a.trailing_zeros()` for a `u64` held in a bigint.
function u64_trailing_zeros(a: bigint) -> int {
    let v = a & U64_MASK();
    if (v == 0n) {
        return 64;
    }
    let n = 0;
    while ((v & 1n) == 0n) {
        n += 1;
        v = v >> 1;
    }
    n
}

// ---------------------------------------------------------------- formatting

/// `format!("{}", x)` for an f64 — Rust's `Display`: shortest round-trip
/// digits, never an exponent, no `.0` on integral values, `inf`/`-inf`/`NaN`.
function fmt_f64(x: float) -> string {
    if (x.is_nan()) {
        return "NaN";
    }
    if (x.is_infinite()) {
        return if (x > 0.0) {
            "inf"
        } else {
            "-inf"
        };
    }
    let s = x.to_string();
    if (s.ends_with(".0")) {
        s.slice(0, s.length() - 2)
    } else {
        s
    }
}

/// `format!("{:?}", x)` for an f64 — Rust's `Debug`: like `Display` but keeps
/// `.0` on integral values and switches to exponent form outside
/// `1e-5 <= |x| < 1e16`.
function fmt_f64_debug(x: float) -> string {
    if (x.is_nan()) {
        return "NaN";
    }
    if (x.is_infinite()) {
        return if (x > 0.0) {
            "inf"
        } else {
            "-inf"
        };
    }
    let a = x.abs();
    if (a != 0.0 && (a < 0.00001 || a >= 10000000000000000.0)) {
        return fmt_f64_exp(x);
    }
    let s = x.to_string();
    if (s.includes(".")) {
        s
    } else {
        s + ".0"
    }
}

/// `format!("{:e}", x)` — shortest digits in `d.ddde<exp>` form.
function fmt_f64_exp(x: float) -> string {
    if (x.is_nan()) {
        return "NaN";
    }
    if (x.is_infinite()) {
        return if (x > 0.0) {
            "inf"
        } else {
            "-inf"
        };
    }
    let neg = is_sign_negative(x);
    let s = fmt_f64(x.abs());
    // Split into digits and decimal-point position.
    let dot = s.index_of(".");
    let int_part = if (dot == null) {
        s
    } else {
        s.slice(0, dot)
    };
    let frac_part = if (dot == null) {
        ""
    } else {
        s.slice(dot + 1, s.length())
    };
    let digits = int_part + frac_part;
    let point = int_part.length();
    // Strip leading zeros.
    let lead = 0;
    while (lead < digits.length() - 1 && digits.at(lead) == "0") {
        lead += 1;
    }
    digits = digits.slice(lead, digits.length());
    let exp = point - lead - 1;
    // Strip trailing zeros.
    let end = digits.length();
    while (end > 1 && digits.at(end - 1) == "0") {
        end -= 1;
    }
    digits = digits.slice(0, end);
    let mantissa = if (digits.length() > 1) {
        digits.slice(0, 1) + "." + digits.slice(1, digits.length())
    } else {
        digits
    };
    let body = if (x == 0.0) {
        "0e0"
    } else {
        `${mantissa}e${exp}`
    };
    if (neg) {
        "-" + body
    } else {
        body
    }
}

/// `format!("{:.prec$}", x)` — exact decimal rounding (round-half-to-even on
/// the exact binary value), as Rust's formatter does.
function fmt_f64_prec(x: float, prec: int) -> string {
    if (x.is_nan()) {
        return "NaN";
    }
    if (x.is_infinite()) {
        return if (x > 0.0) {
            "inf"
        } else {
            "-inf"
        };
    }
    let neg = is_sign_negative(x);
    let bits = f64_to_bits(x.abs());
    let exp = int_of((bits >> 52) & 2047n);
    let mant = bits & 4503599627370495n;
    let m: bigint = if (exp == 0) {
        mant
    } else {
        mant | 4503599627370496n
    };
    let e = if (exp == 0) {
        -1074
    } else {
        exp - 1075
    };
    let ten: bigint = 10n;
    let scale = ten.pow(bigint_of(prec));
    let q: bigint = 0n;
    if (e >= 0) {
        q = (m << e) * scale;
    } else {
        let num = m * scale;
        let den: bigint = 1n << (0 - e);
        q = num / den;
        let r = num % den;
        let twice = r * 2n;
        if (twice > den || (twice == den && (q & 1n) == 1n)) {
            q = q + 1n;
        }
    }
    let digits = q.to_string();
    if (prec > 0) {
        if (digits.length() <= prec) {
            digits = "0".repeat(prec - digits.length() + 1) + digits;
        }
        let cut = digits.length() - prec;
        digits = digits.slice(0, cut) + "." + digits.slice(cut, digits.length());
    }
    if (neg) {
        "-" + digits
    } else {
        digits
    }
}

/// `-0.0`. Written via its bit pattern because the BAML compiler merges a
/// `-0.0` literal with a `0.0` literal in the same function.
function NEG_ZERO() -> float {
    f64_from_bits(9223372036854775808n)
}

// IEEE-754 comparisons. BAML's float `==`/`<`/`>`… use a TOTAL order in
// which NaN equals itself and sorts above every number (`NaN > 1.0` is
// true); Rust's operators are IEEE (every comparison with NaN is false,
// except `!=`). Use these where a NaN can reach the comparison.

/// Rust `a == b` for f64.
function feq(a: float, b: float) -> bool {
    !a.is_nan() && !b.is_nan() && a == b
}

/// Rust `a != b` for f64.
function fne(a: float, b: float) -> bool {
    !feq(a, b)
}

/// Rust `a < b` for f64.
function flt(a: float, b: float) -> bool {
    !a.is_nan() && !b.is_nan() && a < b
}

/// Rust `a <= b` for f64.
function fle(a: float, b: float) -> bool {
    !a.is_nan() && !b.is_nan() && a <= b
}

/// Rust `a > b` for f64.
function fgt(a: float, b: float) -> bool {
    !a.is_nan() && !b.is_nan() && a > b
}

/// Rust `a >= b` for f64.
function fge(a: float, b: float) -> bool {
    !a.is_nan() && !b.is_nan() && a >= b
}
