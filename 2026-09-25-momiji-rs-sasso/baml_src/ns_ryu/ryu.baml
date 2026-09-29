// Ported from sasso `src/ryu.rs` (namespace `root.ryu`).
//
// `f64` → shortest round-trip decimal, byte-compatible with Rust's `{}`
// Display formatting (which never uses exponential notation), without the
// `core::fmt` machinery. A line-faithful port of the Ryū `d2s` algorithm
// (Ulf Adams, "Ryū: fast float-to-string conversion", PLDI 2018) with the
// 125-bit full tables; the tables are generated offline with arbitrary-
// precision integers (see the checksum test) like `musl_math`'s.
//
// Verified against `format!("{n}")` by an exhaustive-category differential
// fuzz (every exponent × random mantissas, boundaries, halfway ties) — see
// `tests/ryu_fuzz.rs` — and by the full sass-spec suite.

// PORT: `#![allow(clippy::many_single_char_names)]` dropped; `include!("ryu_tables.rs")`
// → the tables live in namespace `root.ryu_tables`.

function MANTISSA_BITS() -> int {
    52
}

function EXPONENT_BITS() -> int {
    11
}

function BIAS() -> int {
    1023
}

function POW5_INV_BITCOUNT() -> int {
    125
}

function POW5_BITCOUNT() -> int {
    125
}

/// ceil(log2(5^e)), for 0 <= e <= 3528.
function pow5bits(e: int) -> int {
    // PORT: `e as u64` — e is in 0..=3528, so the product fits an `int`.
    ((e * 1217359) >> 19) + 1
}

/// floor(e * log10(2)), for 0 <= e <= 1650.
function log10_pow2(e: int) -> int {
    (e * 78913) >> 18
}

/// floor(e * log10(5)), for 0 <= e <= 2620.
function log10_pow5(e: int) -> int {
    (e * 732923) >> 20
}

function pow5_factor(value: bigint) -> int {
    let count = 0;
    while (true) {
        // debug_assert!(value != 0);
        let q = value / 5n;
        if (q * 5n != value) {
            return count;
        }
        value = q;
        count += 1;
    }
    // PORT: `loop` only exits by `return`; BAML needs a tail value after `while (true)`.
    root.std.unreachable()
}

/// Whether `value` is divisible by `5^p`.
function multiple_of_power_of_5(value: bigint, p: int) -> bool {
    pow5_factor(value) >= p
}

/// Whether `value` is divisible by `2^p`.
function multiple_of_power_of_2(value: bigint, p: int) -> bool {
    (value & ((1n << p) - 1n)) == 0n
}

/// (m * mul) >> j, where mul is a 128-bit value as (lo, hi) and 64 <= j < 128.
function mul_shift_64(m: bigint, mul: root.std.Tuple2<bigint, bigint>, j: int) -> bigint {
    let b0 = m * mul._0;
    let b2 = m * mul._1;
    // PORT: `as u64` truncation → mask to 64 bits.
    (((b0 >> 64) + b2) >> (j - 64)) & root.std.U64_MASK()
}

/// The shortest decimal: `digits * 10^exponent` round-trips to the input.
class FloatingDecimal64 {
    digits: bigint,
    exponent: int,
}

/// Core Ryū d2d on a non-zero, finite double's IEEE fields.
function d2d(ieee_mantissa: bigint, ieee_exponent: int) -> FloatingDecimal64 {
    // PORT: tuple destructuring `let (e2, m2) = …` → a Tuple2, then its fields.
    let e2_m2: root.std.Tuple2<int, bigint> = if (ieee_exponent == 0) {
        root.std.Tuple2<int, bigint> { _0: 1 - BIAS() - MANTISSA_BITS() - 2, _1: ieee_mantissa }
    } else {
        root.std.Tuple2<int, bigint> {
            _0: ieee_exponent - BIAS() - MANTISSA_BITS() - 2,
            _1: (1n << MANTISSA_BITS()) | ieee_mantissa,
        }
    };
    let e2 = e2_m2._0;
    let m2 = e2_m2._1;
    let even = (m2 & 1n) == 0n;
    let accept_bounds = even;

    // Step 2: determine the interval of valid decimal representations.
    let mv = m2 * 4;
    // Implicit bool -> int conversion: 1 when the lower bound is closer.
    let mm_shift: bigint = u64_from_bool(ieee_mantissa != 0n || ieee_exponent <= 1);

    // Step 3: convert to a decimal power base via 128-bit arithmetic.
    // PORT: BAML has no uninitialised `let`; the four are assigned on every path below.
    let vr: bigint = 0n;
    let vp: bigint = 0n;
    let vm: bigint = 0n;
    let e10: int = 0;
    let vm_is_trailing_zeros = false;
    let vr_is_trailing_zeros = false;
    if (e2 >= 0) {
        let q = log10_pow2(e2)
            - (
                if (e2 > 3) {
                    1
                } else {
                    0
                }
            );
        e10 = q;
        let k = POW5_INV_BITCOUNT() + pow5bits(q) - 1;
        let i = -e2 + q + k;
        let mul = root.ryu_tables.DOUBLE_POW5_INV_SPLIT()[q];
        vr = mul_shift_64(mv, mul, i);
        vp = mul_shift_64(mv + 2n, mul, i);
        vm = mul_shift_64(mv - 1n - mm_shift, mul, i);
        if (q <= 21) {
            // Only one of mp, mv, mm can be a multiple of 5, if any.
            if (mv % 5n == 0n) {
                vr_is_trailing_zeros = multiple_of_power_of_5(mv, q);
            } else if (accept_bounds) {
                vm_is_trailing_zeros = multiple_of_power_of_5(mv - 1n - mm_shift, q);
            } else {
                vp = vp - u64_from_bool(multiple_of_power_of_5(mv + 2n, q));
            }
        }
    } else {
        let q = log10_pow5(-e2)
            - (
                if (-e2 > 1) {
                    1
                } else {
                    0
                }
            );
        e10 = q + e2;
        let i = -e2 - q;
        let k = pow5bits(i) - POW5_BITCOUNT();
        let j = q - k;
        let mul = root.ryu_tables.DOUBLE_POW5_SPLIT()[i];
        vr = mul_shift_64(mv, mul, j);
        vp = mul_shift_64(mv + 2n, mul, j);
        vm = mul_shift_64(mv - 1n - mm_shift, mul, j);
        if (q <= 1) {
            // {vr,vp,vm} is trailing zeros if {mv,mp,mm} has at least q
            // trailing zero bits.
            vr_is_trailing_zeros = true;
            if (accept_bounds) {
                // mm = mv - 1 - mm_shift, so it has 1 trailing 0 bit iff
                // mm_shift == 1.
                vm_is_trailing_zeros = mm_shift == 1n;
            } else {
                // mp = mv + 2, so it always has at least one trailing 0 bit.
                vp = vp - 1n;
            }
        } else if (q < 63) {
            vr_is_trailing_zeros = multiple_of_power_of_2(mv, q);
        }
    }

    // Step 4: find the shortest decimal representation in the interval.
    let removed: int = 0;
    let last_removed_digit: int = 0;
    let output: bigint = if (vm_is_trailing_zeros || vr_is_trailing_zeros) {
        // General case (rare).
        while (true) {
            let vp_div10 = vp / 10n;
            let vm_div10 = vm / 10n;
            if (vp_div10 <= vm_div10) {
                break;
            }
            let vm_mod10 = root.std.int_of(vm - vm_div10 * 10);
            let vr_div10 = vr / 10n;
            let vr_mod10 = root.std.int_of(vr - vr_div10 * 10);
            vm_is_trailing_zeros = vm_is_trailing_zeros && vm_mod10 == 0;
            last_removed_digit = root.std.as_u8(vr_mod10);
            vr = vr_div10;
            vp = vp_div10;
            vm = vm_div10;
            removed += 1;
        }
        if (vm_is_trailing_zeros) {
            while (true) {
                let vm_div10 = vm / 10n;
                let vm_mod10 = root.std.int_of(vm - vm_div10 * 10);
                if (vm_mod10 != 0) {
                    break;
                }
                let vp_div10 = vp / 10n;
                let vr_div10 = vr / 10n;
                let vr_mod10 = root.std.int_of(vr - vr_div10 * 10);
                last_removed_digit = root.std.as_u8(vr_mod10);
                vr = vr_div10;
                vp = vp_div10;
                vm = vm_div10;
                removed += 1;
            }
        }
        // Reference Ryū rounds an exact .....50..0 tie to EVEN here (ECMA
        // toString semantics). Rust's Display rounds such exact ties UP
        // (half away from zero) — verified by the differential fuzz — so the
        // even-adjustment is deliberately omitted.
        // We need to take vr + 1 if vr is outside bounds or we need to round up.
        vr
            + u64_from_bool((vr == vm && (!accept_bounds || !vm_is_trailing_zeros)) || last_removed_digit >= 5)
    } else {
        // Specialized common case: no trailing zeros in vr/vm.
        let round_up = false;
        let vp_div100 = vp / 100n;
        let vm_div100 = vm / 100n;
        if (vp_div100 > vm_div100) {
            let vr_div100 = vr / 100n;
            let vr_mod100 = root.std.int_of(vr - vr_div100 * 100);
            round_up = vr_mod100 >= 50;
            vr = vr_div100;
            vp = vp_div100;
            vm = vm_div100;
            removed += 2;
        }
        while (true) {
            let vp_div10 = vp / 10n;
            let vm_div10 = vm / 10n;
            if (vp_div10 <= vm_div10) {
                break;
            }
            let vr_div10 = vr / 10n;
            let vr_mod10 = root.std.int_of(vr - vr_div10 * 10);
            round_up = vr_mod10 >= 5;
            vr = vr_div10;
            vp = vp_div10;
            vm = vm_div10;
            removed += 1;
        }
        vr + u64_from_bool(vr == vm || round_up)
    };
    FloatingDecimal64 { digits: output, exponent: e10 + removed }
}

/// PORT: `u64::from(b: bool)` (0 or 1) — Rust's `From<bool>` has no BAML
/// counterpart; a local helper.
function u64_from_bool(b: bool) -> bigint {
    if (b) {
        1n
    } else {
        0n
    }
}

/// Format a finite, non-zero `f64` exactly as Rust's `{}` Display does —
/// shortest round-trip digits in plain positional notation, no exponent
/// form ever (`1e300` prints all 301 characters). The caller handles NaN,
/// infinities, and zero.
function format64(f: float, out: root.std.StrBuf) -> void {
    let bits = root.std.f64_to_bits(f);
    let sign = (bits >> (MANTISSA_BITS() + EXPONENT_BITS())) != 0n;
    let ieee_mantissa = bits & ((1n << MANTISSA_BITS()) - 1n);
    let ieee_exponent = root.std.int_of((bits >> MANTISSA_BITS()) & ((1n << EXPONENT_BITS()) - 1n));
    // debug_assert!(ieee_exponent != ((1 << EXPONENT_BITS) - 1) && (ieee_exponent != 0 || ieee_mantissa != 0));

    if (sign) {
        out.push("-");
    }
    let v = d2d(ieee_mantissa, ieee_exponent);

    // Decimal digits of v.digits, written into a stack buffer back-to-front.
    let buf = baml.Uint8Array.zeroes(17) catch (e) {
        _ => root.std.unreachable()
    };
    let n = v.digits;
    let at = buf.length();
    while (true) {
        at -= 1;
        buf[at] = 48 + root.std.as_u8(root.std.int_of(n % 10n));
        n = n / 10n;
        if (n == 0n) {
            break;
        }
    }
    // Validate the ASCII digit run ONCE; the branches below slice this `&str`
    // (str slicing is byte-indexed, so no further UTF-8 checks) instead of
    // re-validating each fragment.
    let digits = string.from_utf8(buf.slice(at, buf.length())) catch (e) {
        _ => root.std.panic("ascii digits")
    };
    // PORT: `digits` is ASCII, so its char length equals Rust's byte length.
    let len = digits.length();
    // The decimal point sits after `point` digits: digits * 10^exponent.
    let point = len + v.exponent;
    if (v.exponent >= 0) {
        // All digits before the point, then exponent zeros: 123000…
        // PORT: `out.reserve(..)` dropped (StrBuf manages its own capacity).
        out.push_str(digits);
        push_zeros(out, v.exponent);
    } else if (point > 0) {
        // Point inside the digit run: 12.3…
        let point = point;
        // PORT: `out.reserve(..)` dropped.
        out.push_str(digits.slice(0, point));
        out.push(".");
        out.push_str(digits.slice(point, digits.length()));
    } else {
        // 0.00…digits
        let zeros = -point;
        // PORT: `out.reserve(..)` dropped.
        out.push_str("0.");
        push_zeros(out, zeros);
        out.push_str(digits);
    }
}

/// Append `n` ASCII '0' bytes (a single extend, not a per-char push loop).
function push_zeros(out: root.std.StrBuf, n: int) -> void {
    out.push_str("0".repeat(n));
}
