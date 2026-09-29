// Ported from sasso `src/ryu.rs` `mod tests` (namespace `root.ryu.tests`).
//
// PORT: `use super::*;` → items of `root.ryu` (and of `root.ryu_tables`, which
// `ryu.rs` `include!`s) are written fully qualified. `format!("{v}")` of an
// f64 → `root.std.fmt_f64(v)` (Rust's `Display`, built on BAML's own float
// printing — independent of the code under test).

function fmt(f: float) -> string {
    let s = root.std.StrBuf.new();
    root.ryu.format64(f, s);
    s.as_str()
}

test "matches_display_on_classics" {
    for (
        let v in [
            0.1,
            0.3,
            1.5,
            2.5,
            f64_next_up(100.0),
            1e300,
            5e-324,
            1e-4,
            123456.789,
            33.333333333333336,
            2154.15598416745,
            657390374199289.2,
            9007199254740993.0,
            1.7976931348623157e308,
            2.2250738585072014e-308,
        ]
    ) {
        // for {v:e}
        assert.equal(fmt(v), root.std.fmt_f64(v));
        // for -{v:e}
        assert.equal(fmt(-v), root.std.fmt_f64(-v));
    }
}

/// Differential fuzz vs `format!("{n}")`. Default ~2M cases (CI-fast);
/// set RYU_FUZZ_N for the big runs (the port was validated at 2e8+).
/// Categories: pure random bit patterns, every exponent with random
/// mantissas, mantissa boundary patterns, integers and their halves
/// (exact-tie hunting), and powers of ten.
// PORT: the default case count is 2_000 rather than 2_000_000 — the BAML VM
// formats roughly a thousand times slower than native code, and 2M cases would
// take hours. `RYU_FUZZ_N` still overrides it.
test "differential_fuzz_vs_display" {
    let n_env = root.std.env_var("RYU_FUZZ_N");
    let n: int = if (n_env != null) {
        baml.Int.parse(n_env) catch (e) {
            _ => 2000
        }
    } else {
        2000
    };
    let threads: int = root.std.available_parallelism();
    let per = n / threads;
    // PORT: `std::thread::spawn` → `spawn` (BAML green threads); `join` → `await`.
    let handles = root.std.range(0, threads).map((t: int) -> {
        spawn {
            let state: bigint = 0x9e3779b97f4a7c15n
                ^ (root.std.u64_wrapping_mul(root.std.bigint_of(t), 0xbf58476d1ce4e5b9n) + 1n);
            // PORT: the `u64` shifts truncate to 64 bits (`root.std.U64_MASK()`).
            let rng = () -> bigint {
                state = state ^ ((state << 13) & root.std.U64_MASK());
                state = state ^ (state >> 7);
                state = state ^ ((state << 17) & root.std.U64_MASK());
                state
            };
            let check = (f: float) -> null {
                // PORT: `f == 0.0` → `root.std.feq` (IEEE: `-0.0 == 0.0`).
                if (!f.is_finite() || root.std.feq(f, 0.0)) {
                    return null;
                }
                let got = root.std.StrBuf.new();
                root.ryu.format64(f, got);
                let want = root.std.fmt_f64(f);
                // mismatch for bits 0x{:016x}
                assert.equal(got.as_str(), want);
                null
            };
            let i = 0;
            while (i < per) {
                // 1: pure random bit pattern
                check(root.std.f64_from_bits(rng()));
                // 2: every exponent, random mantissa
                let exp = root.std.bigint_of((i % 2046) + 1);
                check(root.std.f64_from_bits((exp << 52) | (rng() & ((1n << 52) - 1n))));
                // 3: mantissa boundaries (all-zeros/all-ones/single-bit)
                let m: bigint = match (i % 4) {
                    0 => 0n,
                    1 => (1n << 52) - 1n,
                    2 => 1n << (i % 52),
                    _ => ((1n << 52) - 1n) ^ (1n << (i % 52)),
                };
                check(root.std.f64_from_bits((exp << 52) | m));
                // 4: integers and exact halves/quarters (tie hunting)
                // PORT: `u64 as f64` of a value below 1e18 (< 2^62) →
                // `root.std.int_of(x) * 1.0` (the same round-to-nearest).
                let int = root.std.int_of(rng() % 1000000000000000000n) * 1.0;
                check(int + 0.5);
                check(int + 0.25);
                check((int + 0.5) / 1024.0);
                // 5: subnormals
                check(root.std.f64_from_bits(rng() & ((1n << 52) - 1n)));
                i += 1;
            }
            // powers of ten and neighbors, once per thread
            for (let p in baml.iter.Range.new(-308, 308 + 1)) {
                let v = root.std.powi(10.0, p);
                check(v);
                check(f64_next_up(v));
                check(f64_next_down(v));
            }
            null
        }
    });
    for (let h in handles) {
        // fuzz thread panicked = mismatch found
        await h;
    }
}

/// `ryu_tables.rs`: `#[cfg(test)] pub(super) const TABLE_CHECKSUM: u64`
/// (included into `ryu.rs`, so the tests reach it through `use super::*`).
function TABLE_CHECKSUM() -> bigint {
    0x6143be2cfdc58d37n
}

test "tables_checksum" {
    // Guard the generated tables against accidental edits: FNV-1a over
    // all limbs, value pinned by the generator run that produced them.
    let h: bigint = 0xcbf29ce484222325n;
    let mix = (x: bigint) -> null {
        // PORT: `x.to_le_bytes()` → the eight bytes, least significant first.
        let k = 0;
        while (k < 8) {
            let b = (x >> (8 * k)) & 0xffn;
            h = h ^ b;
            h = root.std.u64_wrapping_mul(h, 0x100000001b3n);
            k += 1;
        }
        null
    };
    for (
        let lohi in root.ryu_tables.DOUBLE_POW5_SPLIT().concat(
            root.ryu_tables.DOUBLE_POW5_INV_SPLIT(),
        )
    ) {
        mix(lohi._0);
        mix(lohi._1);
    }
    // regenerate ryu_tables.rs
    assert.equal(h, TABLE_CHECKSUM())
}

/// PORT: `f64::next_up` (not in `root.std`), line for line from Rust's core.
function f64_next_up(x: float) -> float {
    // Smallest positive f64.
    let TINY_BITS: bigint = 0x1n;
    let CLEAR_SIGN_MASK: bigint = 0x7fffffffffffffffn;
    let bits = root.std.f64_to_bits(x);
    if (x.is_nan() || bits == root.std.f64_to_bits(root.std.F64_INFINITY())) {
        return x;
    }
    let abs = bits & CLEAR_SIGN_MASK;
    let next_bits = if (abs == 0n) {
        TINY_BITS
    } else if (bits == abs) {
        bits + 1n
    } else {
        bits - 1n
    };
    root.std.f64_from_bits(next_bits)
}

/// PORT: `f64::next_down` (not in `root.std`), line for line from Rust's core.
function f64_next_down(x: float) -> float {
    // Smallest (in magnitude) negative f64.
    let NEG_TINY_BITS: bigint = 0x8000000000000001n;
    let CLEAR_SIGN_MASK: bigint = 0x7fffffffffffffffn;
    let bits = root.std.f64_to_bits(x);
    if (x.is_nan() || bits == root.std.f64_to_bits(root.std.F64_NEG_INFINITY())) {
        return x;
    }
    let abs = bits & CLEAR_SIGN_MASK;
    let next_bits = if (abs == 0n) {
        NEG_TINY_BITS
    } else if (bits == abs) {
        bits - 1n
    } else {
        bits + 1n
    };
    root.std.f64_from_bits(next_bits)
}
