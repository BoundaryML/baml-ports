// Ported from sasso `src/musl_math.rs` (namespace `root.musl_math`).
//
// A bit-faithful port of musl's double-precision `pow` (the ARM
// optimized-routines implementation, Copyright (c) 2018, Arm Limited,
// SPDX-License-Identifier: MIT — the same algorithm glibc >= 2.28 ships,
// in its non-FMA form).
//
// Color-space conversion calls THIS pow rather than `f64::powf`: platform
// libms round differently in the last ulp on real inputs, and those
// single-ulp differences are visible in sasso's byte-exact color output.
// Measured against the full sass-spec color corpus this implementation
// matches the expectations best (the corpus is of mixed provenance — a
// V8/fdlibm port was tried too and loses 20 net cases). The port is
// validated bit-for-bit against the compiled musl C (see `oracle_tests`).

// PORT: `include!("musl_math_tables.rs")` → the tables live in namespace
// `root.musl_math_tables` and are referenced fully qualified.
//
// PORT: `u64` values are `bigint`s holding the unsigned 64-bit pattern
// (`root.std.u64_*` for wrapping ops; a `<<` that can overflow 64 bits is
// masked with `root.std.U64_MASK()`); `u32`/`i32`/`usize` values are `int`s
// (`root.std.u32_wrapping_sub` for the `u32` wrapping compares).

function OFF() -> bigint {
    0x3fe6955500000000n
}

function SIGN_BIAS() -> int {
    0x800 << 7
}

function top12(x: float) -> int {
    root.std.int_of(root.std.f64_to_bits(x) >> 52)
}

function log_inline(ix: bigint) -> root.std.Tuple2<float, float> {
    // PORT: the `LOG_POLY` table is read once into a local.
    let log_poly = root.musl_math_tables.LOG_POLY();
    let tmp = root.std.u64_wrapping_sub(ix, OFF());
    let i = root.std.int_of((tmp >> (52 - 7)) % 128n);
    // PORT: `(tmp as i64) >> 52` — reinterpret as signed, then an arithmetic
    // shift (bigint `>>` floors, like Rust's `i64 >>`).
    let tmp_signed = if (tmp >= (1n << 63)) {
        tmp - (1n << 64)
    } else {
        tmp
    };
    let k = root.std.int_of(tmp_signed >> 52);
    let iz = root.std.u64_wrapping_sub(ix, tmp & (0xfffn << 52));
    let z = root.std.f64_from_bits(iz);
    let kd = k * 1.0;
    let t = root.musl_math_tables.LOG_TAB()[i];
    let invc = t._0;
    let logc = t._1;
    let logctail = t._2;
    // non-FMA split (glibc baseline x86-64 has no FMA in the generic build)
    let zhi = root.std.f64_from_bits(
        root.std.u64_wrapping_add(iz, 1n << 31)
            & ((root.std.U64_MASK() << 32) & root.std.U64_MASK()),
    );
    let zlo = z - zhi;
    let rhi = zhi * invc - 1.0;
    let rlo = zlo * invc;
    let r = rhi + rlo;
    let t1 = kd * root.musl_math_tables.LN2HI() + logc;
    let t2 = t1 + r;
    let lo1 = kd * root.musl_math_tables.LN2LO() + logctail;
    let lo2 = t1 - t2 + r;
    let ar = log_poly[0] * r;
    let ar2 = r * ar;
    let ar3 = r * ar2;
    let arhi = log_poly[0] * rhi;
    let arhi2 = rhi * arhi;
    let hi = t2 + arhi2;
    let lo3 = rlo * (ar + arhi);
    let lo4 = t2 - hi + arhi2;
    let p = ar3
        * (
            log_poly[1]
                + r * log_poly[2]
                + ar2 * (log_poly[3] + r * log_poly[4] + ar2 * (log_poly[5] + r * log_poly[6]))
        );
    let lo = lo1 + lo2 + lo3 + lo4 + p;
    let y = hi + lo;
    root.std.Tuple2 { _0: y, _1: hi - y + lo }
}

// `lo = one - hi + y + lo` must keep its left-to-right summation order
// (clippy's `lo += …` suggestion would reassociate and change the bits).
function specialcase(tmp: float, sbits: bigint, ki: bigint) -> float {
    if ((ki & 0x80000000n) == 0n) {
        sbits = root.std.u64_wrapping_sub(sbits, 1009n << 52);
        let scale = root.std.f64_from_bits(sbits);
        return root.std.f64_from_bits(0x7f00000000000000n) * (scale + scale * tmp);
    }
    sbits = root.std.u64_wrapping_add(sbits, 1022n << 52);
    let scale = root.std.f64_from_bits(sbits);
    let y = scale + scale * tmp;
    if (y.abs() < 1.0) {
        let one = if (y < 0.0) {
            -1.0
        } else {
            1.0
        };
        let lo = scale - y + scale * tmp;
        let hi = one + y;
        lo = one - hi + y + lo;
        y = hi + lo - one;
        if (y == 0.0) {
            y = root.std.f64_from_bits(sbits & 0x8000000000000000n);
        }
    }
    root.std.f64_from_bits(0x0010000000000000n) * y
}

function exp_inline(x: float, xtail: float, sign_bias: int) -> float {
    let abstop = top12(x) & 0x7ff;
    if (root.std.u32_wrapping_sub(abstop, 0x3c9) >= 0x408 - 0x3c9) {
        if (root.std.u32_wrapping_sub(abstop, 0x3c9) >= 0x80000000) {
            let one = 1.0 + x;
            return if (sign_bias != 0) {
                -one
            } else {
                one
            };
        }
        if (abstop >= 0x409) {
            if ((root.std.f64_to_bits(x) >> 63) != 0n) {
                // PORT: `-0.0` built from its bits — BAML merges the float
                // constants `-0.0` and `0.0` within one function (they
                // compare equal), so a literal `-0.0` here would come back
                // as `+0.0`.
                return if (sign_bias != 0) {
                    root.std.f64_from_bits(0x8000000000000000n)
                } else {
                    0.0
                };
            }
            return if (sign_bias != 0) {
                root.std.F64_NEG_INFINITY()
            } else {
                root.std.F64_INFINITY()
            };
        }
        abstop = 0;
    }
    // PORT: the `EXP_TAB` table is read once into a local.
    let exp_tab = root.musl_math_tables.EXP_TAB();
    let z = root.musl_math_tables.INVLN2N() * x;
    let kd_shifted = z + root.musl_math_tables.SHIFT();
    let ki = root.std.f64_to_bits(kd_shifted);
    let kd = kd_shifted - root.musl_math_tables.SHIFT();
    let r = x + kd * root.musl_math_tables.NEGLN2HIN() + kd * root.musl_math_tables.NEGLN2LON() + xtail;
    let idx = root.std.int_of(2n * (ki % 128n));
    let top = (root.std.u64_wrapping_add(ki, root.std.bigint_of(sign_bias)) << (52 - 7)) & root.std.U64_MASK();
    let tail = root.std.f64_from_bits(exp_tab[idx]);
    let sbits = root.std.u64_wrapping_add(exp_tab[idx + 1], top);
    let r2 = r * r;
    let tmp = tail
        + r
        + r2 * (root.musl_math_tables.C2() + r * root.musl_math_tables.C3())
        + r2 * r2 * (root.musl_math_tables.C4() + r * root.musl_math_tables.C5());
    if (abstop == 0) {
        return specialcase(tmp, sbits, ki);
    }
    let scale = root.std.f64_from_bits(sbits);
    scale + scale * tmp
}

function checkint(iy: bigint) -> int {
    let e = root.std.int_of((iy >> 52) & 0x7ffn);
    if (e < 0x3ff) {
        return 0;
    }
    if (e > 0x3ff + 52) {
        return 2;
    }
    if ((iy & ((1n << (0x3ff + 52 - e)) - 1n)) != 0n) {
        return 0;
    }
    if ((iy & (1n << (0x3ff + 52 - e))) != 0n) {
        return 1;
    }
    2
}

function zeroinfnan(i: bigint) -> bool {
    root.std.u64_wrapping_sub(root.std.u64_wrapping_mul(i, 2n), 1n)
        >= root.std.u64_wrapping_sub(0x7ffn << 53, 1n)
}

function pow(x: float, y: float) -> float {
    let sign_bias: int = 0;
    let ix = root.std.f64_to_bits(x);
    let iy = root.std.f64_to_bits(y);
    let topx = top12(x);
    let topy = top12(y);
    if (
        root.std.u32_wrapping_sub(topx, 1) >= 0x7ff - 1
            || root.std.u32_wrapping_sub(topy & 0x7ff, 0x3be) >= 0x43e - 0x3be
    ) {
        if (zeroinfnan(iy)) {
            if (root.std.u64_wrapping_mul(iy, 2n) == 0n) {
                return 1.0;
            }
            if (ix == root.std.f64_to_bits(1.0)) {
                return 1.0;
            }
            if (
                root.std.u64_wrapping_mul(ix, 2n)
                    > root.std.u64_wrapping_mul(root.std.f64_to_bits(root.std.F64_INFINITY()), 2n)
                    || root.std.u64_wrapping_mul(iy, 2n)
                        > root.std.u64_wrapping_mul(
                            root.std.f64_to_bits(root.std.F64_INFINITY()),
                            2n,
                        )
            ) {
                return x + y;
            }
            if (
                root.std.u64_wrapping_mul(ix, 2n)
                    == root.std.u64_wrapping_mul(root.std.f64_to_bits(1.0), 2n)
            ) {
                return 1.0;
            }
            if (
                (
                    root.std.u64_wrapping_mul(ix, 2n)
                        < root.std.u64_wrapping_mul(root.std.f64_to_bits(1.0), 2n)
                )
                    == ((iy >> 63) == 0n)
            ) {
                return 0.0;
            }
            return y * y;
        }
        if (zeroinfnan(ix)) {
            let x2 = x * x;
            if ((ix >> 63) != 0n && checkint(iy) == 1) {
                x2 = -x2;
            }
            return if ((iy >> 63) != 0n) {
                1.0 / x2
            } else {
                x2
            };
        }
        if ((ix >> 63) != 0n) {
            let yint = checkint(iy);
            if (yint == 0) {
                return root.std.F64_NAN();
            }
            if (yint == 1) {
                sign_bias = SIGN_BIAS();
            }
            ix = ix & 0x7fffffffffffffffn;
            topx = topx & 0x7ff;
        }
        if (root.std.u32_wrapping_sub(topy & 0x7ff, 0x3be) >= 0x43e - 0x3be) {
            if (ix == root.std.f64_to_bits(1.0)) {
                return 1.0;
            }
            if ((topy & 0x7ff) < 0x3be) {
                return if (ix > root.std.f64_to_bits(1.0)) {
                    1.0 + y
                } else {
                    1.0 - y
                };
            }
            return if ((ix > root.std.f64_to_bits(1.0)) == ((topy & 0x800) == 0)) {
                root.std.F64_INFINITY()
            } else {
                0.0
            };
        }
        if (topx == 0) {
            ix = root.std.f64_to_bits(x * root.std.f64_from_bits(0x4330000000000000n));
            ix = ix & 0x7fffffffffffffffn;
            ix = root.std.u64_wrapping_sub(ix, 52n << 52);
        }
    }
    let hi_lo = log_inline(ix);
    let hi = hi_lo._0;
    let lo = hi_lo._1;
    let yhi = root.std.f64_from_bits(iy & ((root.std.U64_MASK() << 27) & root.std.U64_MASK()));
    let ylo = y - yhi;
    let lhi = root.std.f64_from_bits(
        root.std.f64_to_bits(hi) & ((root.std.U64_MASK() << 27) & root.std.U64_MASK()),
    );
    let llo = hi - lhi + lo;
    let ehi = yhi * lhi;
    let elo = ylo * lhi + y * llo;
    exp_inline(ehi, elo, sign_bias)
}
