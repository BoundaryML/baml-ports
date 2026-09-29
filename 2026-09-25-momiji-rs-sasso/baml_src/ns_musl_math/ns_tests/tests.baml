// Ported from sasso `src/musl_math.rs` `mod tests` (namespace `root.musl_math.tests`).
//
// PORT: `use super::pow;` → `root.musl_math.pow`.

test "special_cases" {
    assert.equal(root.musl_math.pow(2.0, 0.0), 1.0);
    assert.equal(root.musl_math.pow(root.std.F64_NAN(), 0.0), 1.0);
    assert.equal(root.musl_math.pow(0.0, 3.0), 0.0);
    // PORT: `-0.0` via `root.std.NEG_ZERO()` (a `-0.0` literal merges with the
    // `0.0` literals in this block — PORTING_GUIDE.md §15).
    assert.equal(
        root.std.f64_to_bits(root.musl_math.pow(root.std.NEG_ZERO(), 3.0)),
        root.std.f64_to_bits(root.std.NEG_ZERO()),
    );
    assert.equal(root.musl_math.pow(0.0, -2.0), root.std.F64_INFINITY());
    assert.equal(root.musl_math.pow(-2.0, 3.0), -8.0);
    assert.equal(root.musl_math.pow(-2.0, 2.0), 4.0);
    assert.is_true(root.musl_math.pow(-2.0, 2.5).is_nan());
    assert.equal(root.musl_math.pow(root.std.F64_INFINITY(), -1.0), 0.0);
    assert.equal(root.musl_math.pow(0.5, root.std.F64_INFINITY()), 0.0);
    assert.equal(root.musl_math.pow(0.5, root.std.F64_NEG_INFINITY()), root.std.F64_INFINITY());
    assert.equal(root.musl_math.pow(-1.0, root.std.F64_INFINITY()), 1.0)
}

/// Bit-exact fuzz against the locally-compiled musl C `pow` built with the
/// non-FMA path (set `MUSL_POW_ORACLE=/path/to/powtest`); skipped when
/// unset.
test "matches_musl_c_oracle" {
    let oracle = root.std.env_var("MUSL_POW_ORACLE");
    if (oracle == null) {
        return;
    }
    // PORT: `use std::process::{Command, Stdio};` — `baml.sys.exec` below.
    let exps = [
        2.4,
        1.0 / 2.4,
        0.4166666666666667,
        1.0 / 3.0,
        0.3333333333333333,
        3.0,
        2.0,
        1.8,
        0.5555555555555556,
        2.19921875,
        0.4547069271758437,
        0.45,
        2.2222222222222223,
        0.5,
        -1.5,
        7.3,
    ];
    let pairs: root.std.Tuple2<float, float>[] = [];
    let state: bigint = 0x243F6A8885A308D3n;
    let rnd = () -> bigint {
        state
            = root.std.u64_wrapping_add(
                root.std.u64_wrapping_mul(state, 6364136223846793005n),
                1442695040888963407n,
            );
        state
    };
    for (let _i in baml.iter.Range.new(0, 20000)) {
        // PORT: `x as f64` of a `u64` below 2^53 → `root.std.int_of(x) * 1.0` (exact).
        let m = root.std.int_of(rnd() >> 11) * 1.0 / (root.std.int_of(1n << 53) * 1.0);
        let e = root.std.int_of(rnd() % 121n) - 60;
        let base = m * root.std.powi(2.0, e);
        for (let y in exps) {
            pairs.push(root.std.Tuple2<float, float> { _0: base, _1: y });
        }
    }
    for (let _i in baml.iter.Range.new(0, 100000)) {
        let x = root.std.f64_from_bits(rnd() & 0x7fefffffffffffffn);
        let y = root.std.f64_from_bits(rnd() & 0x7fefffffffffffffn);
        pairs.push(root.std.Tuple2<float, float> { _0: x, _1: y });
        pairs.push(root.std.Tuple2<float, float> { _0: -x, _1: y.round() });
    }
    // PORT: `.collect::<String>()` over the formatted lines → `root.std.concat`.
    let input: string = root.std.concat(
        pairs.map((p) -> string {
            `${hex016(root.std.f64_to_bits(p._0))} ${hex016(root.std.f64_to_bits(p._1))}\n`
        }),
    );
    // PORT: `std::env::temp_dir()` → `$TMPDIR`, else `/tmp` (Rust's Unix rule).
    let dir = root.std.env_var("TMPDIR") ?? "/tmp";
    let in_path = root.std.path_join(dir, "musl_pow_in.txt");
    let out_path = root.std.path_join(dir, "musl_pow_out.txt");
    root.std.write_file(in_path, input) catch (e) {
        _ => root.std.panic("write input")
    };
    // PORT: `File::open(&in_path)` / `File::create(&out_path)` handed to
    // `Command::new(&oracle).stdin(..).stdout(..).status()` → `/bin/sh`
    // redirects the oracle's stdin/stdout to the same two files (BAML's
    // `exec` takes stdin only as a string and captures stdout through a pipe,
    // which deadlocks on a 17 MB input).
    let status = baml.sys.exec("/bin/sh", ["-c", "exec \"$0\" <\"$1\" >\"$2\"", oracle, in_path, out_path], null) catch (e) {
        _ => root.std.panic("oracle run")
    };
    assert.is_true(status.ok());
    let expected: bigint[] = root.std
        .trim(
            root.std.read_to_string(out_path) catch (e) {
                _ => root.std.panic("read output")
            },
        )
        .lines()
        .map((l) -> bigint {
            u64_from_str_radix16(root.std.trim(l)) ?? root.std.panic("hex")
        });
    assert.equal(expected.length(), pairs.length());
    let bad = 0;
    // PORT: `.zip(&expected)` → an index loop.
    let k = 0;
    while (k < pairs.length()) {
        let x = pairs[k]._0;
        let y = pairs[k]._1;
        let want_bits = expected[k];
        k += 1;
        let got = root.musl_math.pow(x, y);
        if (root.std.f64_from_bits(want_bits).is_nan()) {
            // pow({x:e}, {y:e}) want NaN got {got:e}
            assert.is_true(got.is_nan());
            continue;
        }
        if (root.std.f64_to_bits(got) != want_bits) {
            bad += 1;
            if (bad <= 10) {
                baml.io.eprintln(
                    `pow(${root.std.fmt_f64_exp(x)}, ${root.std.fmt_f64_exp(y)}): got ${hex016(root.std.f64_to_bits(got))} want ${hex016(want_bits)}`,
                );
            }
        }
    }
    // {bad}/{} mismatches vs musl C
    assert.equal(bad, 0)
}

/// PORT: `format!("{:016x}", bits)` for a `u64` bit pattern (a `bigint`).
function hex016(bits: bigint) -> string {
    let digits = "0123456789abcdef".chars();
    let out = "";
    let v = bits;
    let k = 0;
    while (k < 16) {
        out = digits[root.std.int_of(v & 15n)] + out;
        v = v >> 4;
        k += 1;
    }
    out
}

/// PORT: `u64::from_str_radix(s, 16).ok()` (a `bigint`; `null` on a bad digit,
/// an empty string, or a value past `u64::MAX`).
function u64_from_str_radix16(s: string) -> bigint? {
    if (s == "") {
        return null;
    }
    let v: bigint = 0n;
    for (let c in s.chars()) {
        let d = root.std.to_digit(c, 16);
        if (d == null) {
            return null;
        }
        v = (v << 4) | root.std.bigint_of(d);
    }
    if (v > root.std.U64_MASK()) {
        return null;
    }
    v
}
