// Ported from sasso `src/musl_math_tables.rs` `mod table_tests` (namespace
// `root.musl_math_tables.table_tests`).

test "table_bit_exactness" {
    assert.equal(root.std.f64_to_bits(root.musl_math_tables.LN2HI()), 0x3fe62e42fefa3800n);
    assert.equal(root.std.f64_to_bits(root.musl_math_tables.LN2LO()), 0x3d2ef35793c76730n);
    assert.equal(root.std.f64_to_bits(root.musl_math_tables.INVLN2N()), 0x40671547652b82fen);
    assert.equal(root.std.f64_to_bits(root.musl_math_tables.NEGLN2HIN()), 0xbf762e42fefa0000n);
    assert.equal(root.std.f64_to_bits(root.musl_math_tables.NEGLN2LON()), 0xbd0cf79abc9e3b3an);
    assert.equal(root.std.f64_to_bits(root.musl_math_tables.SHIFT()), 0x4338000000000000n);
    assert.equal(root.std.f64_to_bits(root.musl_math_tables.C2()), 0x3fdffffffffffdbdn);
    assert.equal(root.std.f64_to_bits(root.musl_math_tables.C3()), 0x3fc555555555543cn);
    assert.equal(root.std.f64_to_bits(root.musl_math_tables.C4()), 0x3fa55555cf172b91n);
    assert.equal(root.std.f64_to_bits(root.musl_math_tables.C5()), 0x3f81111167a4d017n);
    let log_poly_bits: bigint[] = [
        0xbfe0000000000000n,
        0xbfe5555555555560n,
        0x3fe0000000000006n,
        0x3fe999999959554en,
        0xbfe555555529a47an,
        0xbff2495b9b4845e9n,
        0x3ff0002b8b263fc3n,
    ];
    assert.equal(root.musl_math_tables.LOG_POLY().map(root.std.f64_to_bits), log_poly_bits);
    let tab_checksum: bigint = root.musl_math_tables.LOG_TAB().reduce(
        (acc: bigint, t: root.std.Tuple3<float, float, float>) -> bigint {
            // PORT: `|acc, (a, b, c)|` — the tuple's fields are `_0`, `_1`, `_2`.
            let a = t._0;
            let b = t._1;
            let c = t._2;
            root.std.u64_wrapping_add(
                root.std.u64_wrapping_mul(
                    root.std.u64_wrapping_add(
                        root.std.u64_wrapping_mul(
                            root.std.u64_wrapping_add(
                                root.std.u64_wrapping_mul(acc, 1099511628211n),
                                root.std.f64_to_bits(a),
                            ),
                            1099511628211n,
                        ),
                        root.std.f64_to_bits(b),
                    ),
                    1099511628211n,
                ),
                root.std.f64_to_bits(c),
            )
        },
        0n,
    );
    assert.equal(tab_checksum, 0x0b4db3eef08a6be7n)
}
