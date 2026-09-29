// Ported from sasso `src/value.rs` `#[cfg(test)] mod tests`
// (namespace `root.value.tests`; `use super::*` → `root.value.*`).

test "fmt_num_trims_and_rounds" {
    assert.equal(root.value.fmt_num(153.0, false), "153");
    assert.equal(root.value.fmt_num(178.5, false), "178.5");
    assert.equal(root.value.fmt_num(0.5, false), "0.5");
    // A NEGATIVE ZERO keeps its sign from dart-sass 1.104.0 on; a tiny
    // negative that merely rounds to zero does not.
    // PORT: `-0.0` → `root.std.NEG_ZERO()`: the compiler merges the `-0.0` and
    // `0.0` constants of one function (guide §15).
    assert.equal(root.value.fmt_num(root.std.NEG_ZERO(), false), "-0");
    assert.equal(root.value.fmt_num(0.0, false), "0");
    assert.equal(root.value.fmt_num(-0.00000000001, false), "0");
    assert.equal(root.value.fmt_num(16.0, false), "16")
}

test "fmt_num_large_values_stay_plain_decimals" {
    // Exact integers print in full, never exponential.
    assert.equal(root.value.fmt_num(123456789012345.0, false), "123456789012345");
    assert.equal(root.value.fmt_num(-123456789012345.0, false), "-123456789012345");
    assert.equal(root.value.fmt_num(1e20, false), "100000000000000000000");
    // Within int64, the exact decimal expansion (dart VM int printing).
    assert.equal(root.value.fmt_num(1234567890123456789.0, false), "1234567890123456768");
    assert.equal(root.value.fmt_num(593644542057412224.0, false), "593644542057412224");
    // 2^63 saturates to int64 max and still round-trips (dart VM).
    assert.equal(root.value.fmt_num(9223372036854775808.0, false), "9223372036854775807");
    // Beyond int64 the shortest round-tripping form matches dart-sass.
    assert.equal(root.value.fmt_num(92233720368547758070.0, false), "92233720368547760000");
    assert.equal(
        root.value.fmt_num(99999999999999999999999999999.0, false),
        "100000000000000000000000000000",
    )
}

test "fmt_num_rounds_fractions_to_ten_places" {
    assert.equal(root.value.fmt_num(0.1 + 0.2, false), "0.3");
    assert.equal(root.value.fmt_num(1.0 / 3.0, false), "0.3333333333");
    assert.equal(root.value.fmt_num(2.0 / 3.0, false), "0.6666666667");
    assert.equal(root.value.fmt_num(123456.78901234567, false), "123456.7890123457");
    // Below the tenth decimal place rounds away entirely.
    assert.equal(root.value.fmt_num(1e-11, false), "0");
    // Halfway digits round away from zero (dart-sass), not to even.
    assert.equal(root.value.fmt_num(0.00000000015, false), "0.0000000002");
    assert.equal(root.value.fmt_num(0.00000000035, false), "0.0000000004");
    assert.equal(root.value.fmt_num(0.99999999995, false), "1");
    assert.equal(root.value.fmt_num(0.30000000005, false), "0.3000000001")
}

test "fmt_num_compressed_drops_leading_zero" {
    assert.equal(root.value.fmt_num(0.5, true), ".5");
    // A NEGATIVE number keeps its zero: dart looks for a literal `0.`
    // prefix, which the minus sign has pushed out of the way (verified
    // against dart-sass 1.103.1, 2026-09-15).
    assert.equal(root.value.fmt_num(-0.25, true), "-0.25");
    assert.equal(root.value.fmt_num(2.0, true), "2")
}

test "fmt_num_compressed_leading_zero_follows_the_writer" {
    // Which fractions lose the leading zero depends on which of dart's two
    // number writers renders them, so the rule has three regimes rather
    // than one. Every expectation here was measured against dart-sass
    // 1.104.1 on 2026-09-19, sweeping `0.1` … `0.1234567891234` and their
    // negations.
    //
    // 1. Shorter than `precision + 2` = 12 characters, sign included: the
    //    direct writer, which tests for a literal `0.` prefix.
    assert.equal(root.value.fmt_num(0.123456789, true), ".123456789");
    assert.equal(root.value.fmt_num(-0.123456789, true), "-0.123456789");
    // 2. Long enough for `_writeRounded`, but with nothing to round away:
    //    the spelling passes through verbatim and keeps its zero even when
    //    positive, one character longer than it needs to be.
    assert.equal(root.value.fmt_num(0.1234567891, true), "0.1234567891");
    assert.equal(root.value.fmt_num(-0.1234567891, true), "-0.1234567891");
    assert.equal(root.value.fmt_num(0.0123456789, true), "0.0123456789");
    assert.equal(root.value.fmt_num(0.0000000001, true), "0.0000000001");
    // 3. `_writeRounded` with digits to drop: the integer `0` goes for
    //    EITHER sign.
    assert.equal(root.value.fmt_num(0.12345678912, true), ".1234567891");
    assert.equal(root.value.fmt_num(-0.12345678912, true), "-.1234567891");
    assert.equal(root.value.fmt_num(-0.00123456789, true), "-.0012345679");
    assert.equal(root.value.fmt_num(0.00000000005, true), ".0000000001");
    // A carry out of the fraction removes the leading zero the other way;
    // a tiny negative that rounds to zero is still `0`, never `-.0`.
    assert.equal(root.value.fmt_num(-0.99999999995, true), "-1");
    assert.equal(root.value.fmt_num(-1e-11, true), "0");
    // Expanded output keeps every leading zero in all three regimes.
    assert.equal(root.value.fmt_num(0.123456789, false), "0.123456789");
    assert.equal(root.value.fmt_num(0.12345678912, false), "0.1234567891");
    assert.equal(root.value.fmt_num(-0.12345678912, false), "-0.1234567891")
}

test "push_num_writes_at_an_offset" {
    // `push_num` rounds, carries, strips a leading zero and rewrites `-0`
    // by mutating the bytes it just wrote, addressed from `out.len()` at
    // entry. Every one of those fix-ups must therefore be blind to what is
    // already in the buffer: a number appended after a prefix must render
    // exactly as it does into an empty string, and must leave the prefix
    // untouched — including a multibyte one, where a byte-indexed
    // `truncate`/`remove` would panic if the offset arithmetic slipped.
    let cases: float[] = [
        153.0,
        178.5,
        // PORT: `-0.0` → `root.std.NEG_ZERO()` (guide §15).
        root.std.NEG_ZERO(),
        -0.25,
        0.5,
        1.0 / 3.0,
        // Rounding that carries through every digit, with and without a
        // digit to increment on the left of the dot.
        0.99999999995,
        9.99999999995,
        0.30000000005,
        1e-11,
        // Exponent removal, at both ends of the range.
        1e-7,
        1e20,
        1.5e300,
        // A shortest form whose literal last digit drives the rounding.
        2154.15598416745,
    ];
    for (let prefix in ["", "margin:", "邊界：", "🎨 "]) {
        for (let compressed in [false, true]) {
            for (let n in cases) {
                let out = root.std.StrBuf.from(prefix);
                root.value.push_num(out, n, compressed);
                // prefix {prefix:?} clobbered writing {n} (compressed {compressed})
                // PORT: byte offsets `prefix.len()` → char offsets (guide §8).
                assert.equal(out.slice(0, prefix.length()), prefix);
                // {n} rendered differently after {prefix:?} (compressed {compressed})
                assert.equal(out.slice_from(prefix.length()), root.value.fmt_num(n, compressed));
            }
        }
    }
}

function num(value: float, unit: string) -> root.value.CalcNode {
    root.value.CalcNode_Number { _0: root.value.Number.with_unit(value, unit) }
}

test "calc_serialization_drops_redundant_parens" {
    // `1px + 2% * var(--c)`: `*` binds tighter, so no parens are needed.
    let node = root.value.CalcNode_Op {
        op: root.value.CalcOp.Add,
        left: num(1.0, "px"),
        right: root.value.CalcNode_Op {
            op: root.value.CalcOp.Mul,
            left: num(2.0, "%"),
            right: root.value.CalcNode_Str { _0: "var(--c)" },
        },
    };
    assert.equal(root.value.Value_Calc { _0: node }.to_css(false), "calc(1px + 2% * var(--c))")
}

test "calc_serialization_keeps_required_parens_and_flips_sign" {
    // `1px - (2% + var(--c))`: subtracting a sum needs parens.
    let node = root.value.CalcNode_Op {
        op: root.value.CalcOp.Sub,
        left: num(1.0, "px"),
        right: root.value.CalcNode_Op {
            op: root.value.CalcOp.Add,
            left: num(2.0, "%"),
            right: root.value.CalcNode_Str { _0: "var(--c)" },
        },
    };
    assert.equal(root.value.Value_Calc { _0: node }.to_css(false), "calc(1px - (2% + var(--c)))");
    // `1% + -1px` serializes as `1% - 1px`.
    let flip = root.value.CalcNode_Op {
        op: root.value.CalcOp.Add,
        left: num(1.0, "%"),
        right: num(-1.0, "px"),
    };
    assert.equal(root.value.Value_Calc { _0: flip }.to_css(false), "calc(1% - 1px)")
}

test "hex_parsing_and_serialization" {
    // dart-sass preserves the authored spelling of opaque 3-/6-digit hex.
    let c = root.std.expect(root.value.Color.from_hex("336699"), "valid hex");
    assert.equal(c.to_css(false), "#336699");
    let short = root.std.expect(root.value.Color.from_hex("369"), "valid hex");
    assert.equal(short.to_css(false), "#369");
    // Uppercase and mixed case round-trip verbatim.
    let upper = root.std.expect(root.value.Color.from_hex("FFAA00"), "valid hex");
    assert.equal(upper.to_css(false), "#FFAA00");
    let upper_short = root.std.expect(root.value.Color.from_hex("ABC"), "valid hex");
    assert.equal(upper_short.to_css(false), "#ABC");
    // Compressed mode ignores the authored form and shortens.
    assert.equal(upper.to_css(true), "#fa0");
    // 4-/8-digit alpha forms are canonicalized, not preserved. An opaque
    // one collapses to lowercase 6-digit hex; partial alpha -> rgba().
    let opaque4 = root.std.expect(root.value.Color.from_hex("369f"), "valid hex");
    assert.equal(opaque4.to_css(false), "#336699");
    let partial = root.std.expect(root.value.Color.from_hex("33669980"), "valid hex");
    assert.is_true(partial.to_css(false).starts_with("rgba("))
}

test "an_authored_spelling_is_built_once_and_then_shared" {
    // `hex_repr` assembles `#` + digits in a stack buffer instead of a
    // `format!`, addressed from a fixed offset, so every legal literal
    // length has to come out byte-identical to the formatted spelling —
    // including the ones with alpha digits, where a slipped offset would
    // truncate or over-copy.
    for (let digits in ["fff", "FFF", "abc", "0f0", "ffff", "369f", "336699", "FFAA00", "33669980"]) {
        // {digits}
        assert.equal(root.value.hex_repr(digits.to_utf8()), `#${digits}`);
    }
    // The 4-/8-digit forms are canonicalized rather than preserved, still
    // lowercase and two digits per channel.
    assert.equal(root.std.expect(root.value.Color.from_hex("369f"), "valid hex").repr, "#336699");
    assert.equal(root.std.expect(root.value.Color.from_hex("ABCF"), "valid hex").repr, "#aabbcc");
    // A partial-alpha literal has no authored spelling to keep.
    assert.is_true(root.std.expect(root.value.Color.from_hex("33669980"), "valid hex").repr == null);
    // Cloning a literal — what evaluation does on every read of it — must
    // share that one spelling, not copy the bytes into a new allocation.
    let literal = root.std.expect(root.value.Color.from_hex("336699"), "valid hex");
    // PORT: `Color::clone` → a shallow class copy (`repr` is shared as-is).
    let read = root.value.Color { ...literal };
    assert.equal(read.to_css(false), "#336699");
    let a = root.std.expect(literal.repr, "kept");
    let b = root.std.expect(read.repr, "kept");
    // the clone copied the spelling instead of sharing it
    // PORT: `Rc::ptr_eq` has no BAML counterpart (strings are values with no
    // identity); the observable half — the clone keeps the same spelling — is
    // asserted instead.
    assert.equal(a, b);
    // A named literal shares the same way.
    let named = root.std.expect(root.value.named_color("rebeccapurple"), "named");
    let copy = root.value.Color { ...named };
    // PORT: `Rc::ptr_eq` → `==` (see above).
    assert.equal(root.std.expect(named.repr, "kept"), root.std.expect(copy.repr, "kept"))
}

test "compressed_uses_shortest_of_name_or_hex" {
    // dart-sass compressed emits whichever is shorter, the canonical name or
    // the shortest hex (name wins ties).
    let name = (hex: string) -> string {
        root.std.expect(root.value.Color.from_hex(hex), "valid hex").to_css(true)
    };

    // Name strictly shorter than hex -> name.
    assert.equal(name("ff0000"), "red"); // red(3) < #f00(4)
    assert.equal(name("ffa500"), "orange"); // orange(6) < #ffa500(7)
    // Tie (#rgb-expandable, 4 vs 4) -> name wins.
    assert.equal(name("00ffff"), "aqua");
    assert.equal(name("0000ff"), "blue");
    assert.equal(name("00ff00"), "lime");
    // Hex shorter than name -> hex.
    assert.equal(name("ff00ff"), "#f0f"); // magenta(7) > #f0f(4)
    assert.equal(name("ffffff"), "#fff"); // white(5) > #fff(4)
    // No name -> hex.
    assert.equal(name("3366cc"), "#36c");

    // Duplicate names resolve to dart's canonical pick (value, not spelling).
    assert.equal(root.std.unwrap(root.value.named_color("cyan")).to_css(true), "aqua");
    assert.equal(root.std.unwrap(root.value.named_color("grey")).to_css(true), "gray");
    // A computed (non-literal) color still names by value.
    assert.equal(root.value.Color.rgb(0.0, 255.0, 255.0, 1.0).to_css(true), "aqua");

    // Expanded is unaffected: authored spelling is preserved.
    assert.equal(root.std.unwrap(root.value.Color.from_hex("ff0000")).to_css(false), "#ff0000");
    assert.equal(root.std.unwrap(root.value.named_color("red")).to_css(false), "red")
}

test "hsl_roundtrip_is_exact_for_integer_rgb" {
    // #336699 == hsl(210, 50%, 40%)
    let c = root.std.expect(root.value.Color.from_hex("336699"), "valid hex");
    let hsl = c.to_hsl();
    let h = hsl._0;
    let s = hsl._1;
    let l = hsl._2;
    assert.approx_equal(h, 210.0, 1e-9);
    assert.approx_equal(s, 0.5, 1e-9);
    assert.approx_equal(l, 0.4, 1e-9);
    // lighten by 10% -> exactly dart-sass's fractional rgb.
    let lit = root.value.Color.from_hsl(h, s, l + 0.1, 1.0);
    assert.equal(lit.to_css(false), "rgb(25%, 50%, 75%)")
}

test "computed_fractional_channels_serialize_as_rgb" {
    let c = root.value.Color.rgb(153.0, 178.5, 204.0, 1.0);
    assert.equal(c.to_css(false), "rgb(60%, 70%, 80%)")
}

test "compressed_picks_shortest_of_rgb_and_hsl" {
    // dart-sass 1.101.0 compressed output emits whichever legacy form is
    // shorter, the rgb()/rgba() form or the equivalent hsl()/hsla() form.

    // A `darken(#336699, 10%)` result: a fractional triple, so both forms
    // spell the channels as percentages.
    let darkened = root.value.Color.from_hsl(210.0, 0.5, 0.3, 1.0); // rgb(38.25, 76.5, 114.75)
    assert.equal(darkened.to_css(true), "rgb(15%,30%,45%)");
    assert.equal(darkened.to_css(false), "rgb(15%, 30%, 45%)");

    // A `saturate(#888, 20%)` result: the hsl form is longer -> stays rgb.
    let saturated = root.value.Color.rgb(159.8, 112.2, 112.2, 1.0);
    assert.equal(saturated.to_css(true), "rgb(62.6666666667%,44%,44%)");

    // Non-opaque: rgba vs hsla; the percentage rgba form wins (alpha keeps `.5`).
    let translucent = root.value.Color.from_hsl(210.0, 0.5, 0.3, 0.5);
    assert.equal(translucent.to_css(true), "rgba(15%,30%,45%,.5)");

    // A computed gray: the fractional rgb triple is far longer than hsl.
    let gray = root.value.Color.rgb(127.5, 127.5, 127.5, 1.0);
    assert.equal(gray.to_css(true), "hsl(0,0%,50%)");

    // An integer in-gamut color still collapses to hex/name (always
    // shorter than hsl); the new hsl candidate must not regress this.
    let integer = root.value.Color.from_hsl(210.0, 0.5, 0.4, 1.0); // == #336699
    assert.equal(integer.to_css(true), "#369");
    assert.equal(root.value.Color.rgb(0.0, 0.0, 0.0, 0.5).to_css(true), "rgba(0,0,0,.5)")
}

test "alpha_color_serializes_as_rgba" {
    let c = root.value.Color.rgb(0.0, 0.0, 0.0, 0.5);
    assert.equal(c.to_css(false), "rgba(0, 0, 0, 0.5)")
}

test "named_colors_resolve_and_preserve_spelling" {
    let red = root.std.expect(root.value.named_color("red"), "named");
    assert.equal(red.to_css(false), "red");
    assert.is_true(root.value.named_color("definitely-not-a-color") == null);
    // Extended CSS names resolve to their exact sRGB channels.
    let plum = root.std.expect(root.value.named_color("plum"), "named");
    assert.equal(
        root.std.Tuple4<float, float, float, float> {
            _0: plum.r,
            _1: plum.g,
            _2: plum.b,
            _3: plum.a,
        },
        root.std.Tuple4<float, float, float, float> { _0: 221.0, _1: 160.0, _2: 221.0, _3: 1.0 },
    );
    let rebecca = root.std.expect(root.value.named_color("rebeccapurple"), "named");
    assert.equal(
        root.std.Tuple3<float, float, float> { _0: rebecca.r, _1: rebecca.g, _2: rebecca.b },
        root.std.Tuple3<float, float, float> { _0: 102.0, _1: 51.0, _2: 153.0 },
    );
    // Grey/gray aliases share channel values (the repr keeps the spelling).
    let grey = root.std.expect(root.value.named_color("darkgrey"), "named");
    let gray = root.std.expect(root.value.named_color("darkgray"), "named");
    assert.equal(
        root.std.Tuple3<float, float, float> { _0: grey.r, _1: grey.g, _2: grey.b },
        root.std.Tuple3<float, float, float> { _0: gray.r, _1: gray.g, _2: gray.b },
    )
}

test "unit_dimensions_group_known_units" {
    assert.equal(root.value.unit_dimension("px"), root.value.Dim.Length);
    assert.equal(root.value.unit_dimension("deg"), root.value.Dim.Angle);
    assert.equal(root.value.unit_dimension("ms"), root.value.Dim.Time);
    assert.equal(root.value.unit_dimension("kHz"), root.value.Dim.Frequency);
    assert.equal(root.value.unit_dimension("dppx"), root.value.Dim.Resolution);
    // The conversion table is case-sensitive (dart: `1in + 1Q` errors,
    // `1in + 1q` converts), so `PT`/`khz` have no group; nor do `%`,
    // viewport units, or unitless.
    assert.equal(root.value.unit_dimension("PT"), null);
    assert.equal(root.value.unit_dimension("khz"), null);
    assert.equal(root.value.unit_dimension("%"), null);
    assert.equal(root.value.unit_dimension("vw"), null);
    assert.equal(root.value.unit_dimension(""), null)
}

test "units_compatible_within_groups_only" {
    assert.is_true(root.value.units_compatible("in", "cm"));
    assert.is_true(root.value.units_compatible("deg", "turn"));
    assert.is_true(root.value.units_compatible("s", "ms"));
    assert.is_true(root.value.units_compatible("Hz", "kHz"));
    assert.is_true(root.value.units_compatible("dpi", "dppx"));
    // equal units are always compatible, even `%` and unknown units.
    assert.is_true(root.value.units_compatible("%", "%"));
    assert.is_true(root.value.units_compatible("PX", "PX"));
    // cross-group, unknown, and case-mismatched units are incompatible
    // (dart: `1px + 1PX` errors).
    assert.is_true(!root.value.units_compatible("px", "s"));
    assert.is_true(!root.value.units_compatible("px", "vw"));
    assert.is_true(!root.value.units_compatible("px", "PX"));
    assert.is_true(!root.value.units_compatible("khz", "hz"))
}

test "convert_factor_matches_dart_sass" {
    // length: 1in == 96px, 1cm == 96/2.54 px.
    assert.equal(root.value.convert_factor("in", "px"), 96.0);
    assert.equal(root.value.convert_factor("px", "px"), 1.0);
    let cm_to_in = root.std.expect(root.value.convert_factor("cm", "in"), "compatible");
    assert.approx_equal(cm_to_in, 1.0 / 2.54, 1e-12);
    // 1in + 1cm in inches: 1 + 1*(1/2.54) == 1.3937007874...
    assert.approx_equal(1.0 + cm_to_in, 1.393700787401575, 1e-12);
    // time: 1ms == 0.001s.
    assert.equal(root.value.convert_factor("ms", "s"), 0.001);
    // angle: 1turn == 360deg, 100grad == 90deg.
    assert.equal(root.value.convert_factor("turn", "deg"), 360.0);
    assert.equal(root.value.convert_factor("grad", "deg"), 0.9);
    // resolution: 1dppx == 96dpi.
    assert.equal(root.value.convert_factor("dppx", "dpi"), 96.0);
    // incompatible -> None.
    assert.equal(root.value.convert_factor("px", "s"), null);
    assert.equal(root.value.convert_factor("px", "vw"), null)
}

test "fuzzy_is_int_needs_both_clauses_of_fuzzy_equals" {
    // Exactly integral, and the dust an hsl conversion leaves behind: both
    // are integers to dart's `fuzzyIsInt`.
    assert.is_true(root.value.fuzzy_is_int(204.0));
    assert.is_true(root.value.fuzzy_is_int(203.999_999_999_999_97));
    assert.is_true(root.value.fuzzy_is_int(50.999_999_999_999_986));
    // PORT: `-0.0` → `root.std.NEG_ZERO()` (guide §15).
    assert.is_true(root.value.fuzzy_is_int(root.std.NEG_ZERO()));
    // 5e-12 below 20 is INSIDE the epsilon, so the first clause of
    // `fuzzyEquals` passes it -- and the second one, which rounds both
    // sides at 1e11, rejects it (1999999999999 against 2000000000000).
    // dart therefore spells this channel as a percentage even under
    // `meta.inspect`.
    assert.is_true(!root.value.fuzzy_is_int(19.999_999_999_994_987));
    // Plainly non-integral, and non-finite.
    assert.is_true(!root.value.fuzzy_is_int(127.5));
    assert.is_true(!root.value.fuzzy_is_int(root.std.F64_INFINITY()));
    assert.is_true(!root.value.fuzzy_is_int(root.std.F64_NAN()))
}

function numval(value: float, unit: string) -> root.value.Value {
    root.value.Value_Number { _0: root.value.Number.with_unit(value, unit) }
}

test "sass_eq_numbers_are_unit_aware_and_fuzzy" {
    // Same unit, equal value.
    assert.is_true(numval(2.0, "px").sass_eq(numval(2.0, "px")));
    // Convertible units compare after conversion.
    assert.is_true(numval(1.0, "in").sass_eq(numval(96.0, "px")));
    assert.is_true(numval(96.0, "px").sass_eq(numval(1.0, "in")));
    assert.is_true(numval(1.0, "cm").sass_eq(numval(10.0, "mm")));
    assert.is_true(numval(100.0, "grad").sass_eq(numval(90.0, "deg")));
    assert.is_true(numval(1.0, "s").sass_eq(numval(1000.0, "ms")));
    // Fuzzy: tiny differences within epsilon are equal.
    assert.is_true(numval(1.000_000_000_000_1, "px").sass_eq(numval(1.0, "px")));
    // Just outside epsilon is not equal.
    assert.is_true(!numval(1.000_000_001, "px").sass_eq(numval(1.0, "px")));
    // Unitless vs unit-bearing, incompatible units, `%`, and uppercase
    // units (case-sensitive) are never equal.
    assert.is_true(!numval(1.0, "").sass_eq(numval(1.0, "px")));
    assert.is_true(!numval(1.0, "px").sass_eq(numval(1.0, "em")));
    assert.is_true(!numval(50.0, "%").sass_eq(numval(50.0, "")));
    assert.is_true(!numval(1.0, "PX").sass_eq(numval(1.0, "px")));
    assert.is_true(!numval(1.0, "IN").sass_eq(numval(96.0, "px")))
}

test "sass_eq_colors_compare_channels_fuzzily" {
    // `purple` (128,0,128) equals an HSL color that resolves to channels
    // a tiny epsilon away (127.999999999998607...).
    let purple: root.value.Value = root.value.Value_Color { _0: root.value.Color.rgb(128.0, 0.0, 128.0, 1.0) };
    let computed: root.value.Value = root.value.Value_Color {
        _0: root.value.Color.rgb(127.999_999_999_998_6, 0.0, 127.999_999_999_998_6, 1.0),
    };
    assert.is_true(purple.sass_eq(computed));
    // Genuinely different channels are not equal.
    assert.is_true(
        !purple.sass_eq(root.value.Value_Color { _0: root.value.Color.rgb(255.0, 0.0, 0.0, 1.0) }),
    );
    // A fractional channel is not equal to its rounded neighbour.
    let frac: root.value.Value = root.value.Value_Color { _0: root.value.Color.rgb(0.4, 0.0, 0.0, 1.0) };
    assert.is_true(
        !frac.sass_eq(root.value.Value_Color { _0: root.value.Color.rgb(0.0, 0.0, 0.0, 1.0) }),
    );
    assert.is_true(
        frac.sass_eq(root.value.Value_Color { _0: root.value.Color.rgb(0.4, 0.0, 0.0, 1.0) }),
    );
    // Differing alpha is not equal.
    assert.is_true(
        !purple.sass_eq(root.value.Value_Color { _0: root.value.Color.rgb(128.0, 0.0, 128.0, 0.5) }),
    )
}

/// A calculation is the one value whose serialization is recursive, so
/// writing it into the caller's buffer is the one place where a missed
/// `return`, a stale offset or a dropped parenthesis can lose or duplicate
/// text that no single-node case would show. Every shape that decides a
/// byte is listed — precedence parens on both sides, the `+ -n` operator
/// flip that returns early, a function with several arguments, a
/// unit-bearing non-finite number, an opaque operand — asserted against the
/// spelling dart-sass 1.104.1 produces for the same input, and asserted
/// again written after existing text.
test "writing_a_calculation_appends_dart_sass_spelling" {
    let num = writing_a_calculation_appends_dart_sass_spelling__num;
    let op = writing_a_calculation_appends_dart_sass_spelling__op;
    let var_x = () -> root.value.CalcNode {
        root.value.CalcNode_Str { _0: "var(--x)" }
    };

    // (node, expanded, compressed) — `None` where our compressed spelling
    // is a known pre-existing divergence (the `+ -n` flip is skipped when
    // compressed), which this change neither introduces nor fixes.
    let cases: root.std.Tuple3<root.value.CalcNode, string, string?>[] = [
        root.std.Tuple3<root.value.CalcNode, string, string?> {
            _0: op(root.value.CalcOp.Sub, num(100.0, "%"), num(16.0, "px")),
            _1: "calc(100% - 16px)",
            _2: "calc(100% - 16px)",
        },
        // The right operand's sign flips the operator, and returns early.
        root.std.Tuple3<root.value.CalcNode, string, string?> {
            _0: op(root.value.CalcOp.Add, var_x(), num(-16.0, "px")),
            _1: "calc(var(--x) - 16px)",
            _2: null,
        },
        // A looser child parenthesizes on the left...
        root.std.Tuple3<root.value.CalcNode, string, string?> {
            _0: op(
                root.value.CalcOp.Mul,
                op(root.value.CalcOp.Add, var_x(), num(2.0, "px")),
                num(3.0, ""),
            ),
            _1: "calc((var(--x) + 2px) * 3)",
            _2: "calc((var(--x) + 2px)*3)",
        },
        // ...and on the right, where equal precedence under `/` also does.
        root.std.Tuple3<root.value.CalcNode, string, string?> {
            _0: op(
                root.value.CalcOp.Div,
                num(1.0, "px"),
                op(root.value.CalcOp.Mul, var_x(), num(3.0, "")),
            ),
            _1: "calc(1px / (var(--x) * 3))",
            _2: "calc(1px/(var(--x)*3))",
        },
        // A tighter child does not.
        root.std.Tuple3<root.value.CalcNode, string, string?> {
            _0: op(
                root.value.CalcOp.Add,
                num(1.0, "px"),
                op(root.value.CalcOp.Mul, num(2.0, "px"), var_x()),
            ),
            _1: "calc(1px + 2px * var(--x))",
            _2: "calc(1px + 2px*var(--x))",
        },
        root.std.Tuple3<root.value.CalcNode, string, string?> {
            _0: root.value.CalcNode_Func {
                name: "min",
                args: [
                    root.value.CalcNode_Number { _0: root.value.Number.with_unit(10.0, "px") },
                    op(root.value.CalcOp.Add, var_x(), num(1.0, "px")),
                    root.value.CalcNode_Number { _0: root.value.Number.with_unit(2.0, "px") },
                ],
            },
            _1: "min(10px, var(--x) + 1px, 2px)",
            _2: "min(10px,var(--x) + 1px,2px)",
        },
        // A unit-bearing infinity is itself an operation, so it
        // parenthesizes like one — and it is written, not formatted.
        root.std.Tuple3<root.value.CalcNode, string, string?> {
            _0: root.value.CalcNode_Number {
                _0: root.value.Number.with_unit(root.std.F64_INFINITY(), "px"),
            },
            _1: "calc(infinity * 1px)",
            _2: "calc(infinity*1px)",
        },
        root.std.Tuple3<root.value.CalcNode, string, string?> {
            _0: op(
                root.value.CalcOp.Div,
                var_x(),
                root.value.CalcNode_Number {
                    _0: root.value.Number.with_unit(root.std.F64_NEG_INFINITY(), "px"),
                },
            ),
            _1: "calc(var(--x) / (-infinity * 1px))",
            _2: "calc(var(--x)/(-infinity*1px))",
        },
        root.std.Tuple3<root.value.CalcNode, string, string?> {
            _0: var_x(),
            _1: "calc(var(--x))",
            _2: "calc(var(--x))",
        },
    ];

    for (let case_ in cases) {
        let node = case_._0;
        let expanded = case_._1;
        let compressed = case_._2;
        let styles: root.std.Tuple2<bool, string?>[] = [
            root.std.Tuple2<bool, string?> { _0: false, _1: expanded },
            root.std.Tuple2<bool, string?> { _0: true, _1: compressed },
        ];
        for (let pair in styles) {
            let style = pair._0;
            let expected = pair._1;
            if (expected == null) {
                continue;
            }
            // calc spelling (compressed = {style}) for {node:?}
            assert.equal(node.to_calc_value_css(style), expected);
            // The same bytes when there is already text in the buffer: the
            // walk must append, never assume it starts at zero.
            let buf = root.std.StrBuf.from("PREFIX:");
            node.write_calc_value_css(buf, style);
            assert.equal(buf.as_str(), `PREFIX:${expected}`);
        }
    }
}

// Hoisted from `writing_a_calculation_appends_dart_sass_spelling`'s nested
// `fn num`.
function writing_a_calculation_appends_dart_sass_spelling__num(
    v: float,
    unit: string,
) -> root.value.CalcNode {
    root.value.CalcNode_Number {
        _0: if (unit == "") {
            root.value.Number.unitless(v)
        } else {
            root.value.Number.with_unit(v, unit)
        },
    }
}

// Hoisted from `writing_a_calculation_appends_dart_sass_spelling`'s nested
// `fn op`.
function writing_a_calculation_appends_dart_sass_spelling__op(
    op: root.value.CalcOp,
    left: root.value.CalcNode,
    right: root.value.CalcNode,
) -> root.value.CalcNode {
    root.value.CalcNode_Op { op: op, left: left, right: right }
}

// PORT: `std::mem::discriminant` → the variant class's name (BAML has no
// discriminant value; a `match` over the variant classes stands in).
function discriminant(v: root.value.Value) -> string {
    match (v) {
        root.value.Value_Number {} => "Number",
        root.value.Value_Color {} => "Color",
        root.value.Value_Str {} => "Str",
        root.value.Value_List {} => "List",
        root.value.Value_Map {} => "Map",
        root.value.Value_Bool {} => "Bool",
        root.value.Value_Null {} => "Null",
        root.value.Value_Slash {} => "Slash",
        root.value.Value_Calc {} => "Calc",
        root.value.Value_Function {} => "Function",
        root.value.Value_Mixin {} => "Mixin",
        _ => root.std.unreachable(),
    }
}

/// [`Value::write_css`] and [`Value::to_css`] are two spellings of one
/// serialization, and callers pick between them by whether they already hold
/// a buffer — so a variant spelled out in one and not the other must still
/// produce the same bytes. Every variant is listed, in both output styles,
/// because the way this breaks is a new in-place arm that formats slightly
/// differently from the owned one it was copied from and only shows up in the
/// two places (declarations, interpolation) that take the buffer path.
test "writing_a_value_in_place_matches_serializing_it_to_a_string" {
    let values: root.value.Value[] = [
        root.value.Value_Number { _0: root.value.Number.with_unit(12.5, "px") },
        root.value.Value_Color { _0: root.value.Color.rgb(51.0, 102.0, 153.0, 1.0) },
        root.value.Value_Str { _0: root.value.SassStr { text: "a b", quoted: true } },
        root.value.Value_Str { _0: root.value.SassStr { text: "solid", quoted: false } },
        root.value.Value_List {
            _0: root.value.List.new(
                [
                    root.value.Value_Number { _0: root.value.Number.with_unit(1.0, "px") },
                    root.value.Value_Color { _0: root.value.Color.rgb(0.0, 0.0, 0.0, 0.5) },
                ],
                root.value.ListSep.Space,
                false,
            ),
        },
        root.value.Value_Map {
            _0: root.value.Map.new(
                [
                    root.std.Tuple2<root.value.Value, root.value.Value> {
                        _0: root.value.Value_Str { _0: root.value.SassStr { text: "k", quoted: false } },
                        _1: root.value.Value_Number { _0: root.value.Number.unitless(1.0) },
                    },
                ],
            ),
        },
        root.value.Value_Bool { _0: true },
        root.value.Value_Bool { _0: false },
        root.value.Value_Null {  },
        root.value.Value_Slash { _0: root.value.Number.unitless(0.5), _1: "1/2" },
        root.value.Value_Calc {
            _0: root.value.CalcNode_Op {
                op: root.value.CalcOp.Sub,
                left: root.value.CalcNode_Number { _0: root.value.Number.with_unit(100.0, "%") },
                right: root.value.CalcNode_Number { _0: root.value.Number.with_unit(16.0, "px") },
            },
        },
        root.value.Value_Function {
            _0: root.value.SassFunction { name: "f", css: false, module: null, user: null },
        },
        root.value.Value_Mixin { _0: root.value.SassMixin { name: "m", user: null, module: null } },
    ];
    // The list above is the whole enum, so a new variant cannot be added
    // without being written down here.
    let variants = root.std.set_of(
        values.map((v) -> {
            discriminant(v)
        }),
    );
    // one case per `Value` variant
    assert.equal(variants.length(), 11);

    for (let compressed in [false, true]) {
        for (let v in values) {
            let buf = root.std.StrBuf.from("PREFIX:");
            v.write_css(buf, compressed);
            // write_css disagrees with to_css (compressed = {compressed}) for {v:?}
            assert.equal(buf.as_str(), `PREFIX:${v.to_css(compressed)}`);
        }
    }
    // The same for the interpolation pair, which shares the fall-through.
    for (let v in values) {
        let buf = root.std.StrBuf.new();
        v.write_interp(buf);
        // write_interp disagrees with to_interp for {v:?}
        assert.equal(buf.as_str(), v.to_interp());
    }
}
