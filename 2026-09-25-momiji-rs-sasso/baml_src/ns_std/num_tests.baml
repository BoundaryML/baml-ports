// Checks the `std` numeric shims against values printed by real Rust (rustc 1.x).

testset "num" {
    test "f64_0" {
        let x = 0.0;
        assert.equal(f64_to_bits(x).to_string(), "0");
        assert.equal(f64_to_bits(f64_from_bits(0n)).to_string(), "0");
        assert.equal(fmt_f64(x), "0");
        assert.equal(fmt_f64_debug(x), "0.0");
        assert.equal(fmt_f64_exp(x), "0e0");
        assert.equal(fmt_f64_prec(x, 3), "0.000");
        assert.equal(fmt_f64_prec(x, 0), "0");
        assert.equal(fmt_f64(powi(x, 3)), "0")
    }
    test "f64_1" {
        let x = -0.0;
        assert.equal(f64_to_bits(x).to_string(), "9223372036854775808");
        assert.equal(
            f64_to_bits(f64_from_bits(9223372036854775808n)).to_string(),
            "9223372036854775808",
        );
        assert.equal(fmt_f64(x), "-0");
        assert.equal(fmt_f64_debug(x), "-0.0");
        assert.equal(fmt_f64_exp(x), "-0e0");
        assert.equal(fmt_f64_prec(x, 3), "-0.000");
        assert.equal(fmt_f64_prec(x, 0), "-0");
        assert.equal(fmt_f64(powi(x, 3)), "-0")
    }
    test "f64_2" {
        let x = 1.0;
        assert.equal(f64_to_bits(x).to_string(), "4607182418800017408");
        assert.equal(
            f64_to_bits(f64_from_bits(4607182418800017408n)).to_string(),
            "4607182418800017408",
        );
        assert.equal(fmt_f64(x), "1");
        assert.equal(fmt_f64_debug(x), "1.0");
        assert.equal(fmt_f64_exp(x), "1e0");
        assert.equal(fmt_f64_prec(x, 3), "1.000");
        assert.equal(fmt_f64_prec(x, 0), "1");
        assert.equal(fmt_f64(powi(x, 3)), "1")
    }
    test "f64_3" {
        let x = -1.5;
        assert.equal(f64_to_bits(x).to_string(), "13832806255468478464");
        assert.equal(
            f64_to_bits(f64_from_bits(13832806255468478464n)).to_string(),
            "13832806255468478464",
        );
        assert.equal(fmt_f64(x), "-1.5");
        assert.equal(fmt_f64_debug(x), "-1.5");
        assert.equal(fmt_f64_exp(x), "-1.5e0");
        assert.equal(fmt_f64_prec(x, 3), "-1.500");
        assert.equal(fmt_f64_prec(x, 0), "-2");
        assert.equal(fmt_f64(powi(x, 3)), "-3.375")
    }
    test "f64_4" {
        let x = 0.1;
        assert.equal(f64_to_bits(x).to_string(), "4591870180066957722");
        assert.equal(
            f64_to_bits(f64_from_bits(4591870180066957722n)).to_string(),
            "4591870180066957722",
        );
        assert.equal(fmt_f64(x), "0.1");
        assert.equal(fmt_f64_debug(x), "0.1");
        assert.equal(fmt_f64_exp(x), "1e-1");
        assert.equal(fmt_f64_prec(x, 3), "0.100");
        assert.equal(fmt_f64_prec(x, 0), "0");
        assert.equal(fmt_f64(powi(x, 3)), "0.0010000000000000002")
    }
    test "f64_5" {
        let x = 1e21;
        assert.equal(f64_to_bits(x).to_string(), "4921056587992461136");
        assert.equal(
            f64_to_bits(f64_from_bits(4921056587992461136n)).to_string(),
            "4921056587992461136",
        );
        assert.equal(fmt_f64(x), "1000000000000000000000");
        assert.equal(fmt_f64_debug(x), "1e21");
        assert.equal(fmt_f64_exp(x), "1e21");
        assert.equal(fmt_f64_prec(x, 3), "1000000000000000000000.000");
        assert.equal(fmt_f64_prec(x, 0), "1000000000000000000000");
        assert.equal(
            fmt_f64(powi(x, 3)),
            "1000000000000000000000000000000000000000000000000000000000000000",
        )
    }
    test "f64_6" {
        let x = 1e-7;
        assert.equal(f64_to_bits(x).to_string(), "4502148214488346440");
        assert.equal(
            f64_to_bits(f64_from_bits(4502148214488346440n)).to_string(),
            "4502148214488346440",
        );
        assert.equal(fmt_f64(x), "0.0000001");
        assert.equal(fmt_f64_debug(x), "1e-7");
        assert.equal(fmt_f64_exp(x), "1e-7");
        assert.equal(fmt_f64_prec(x, 3), "0.000");
        assert.equal(fmt_f64_prec(x, 0), "0");
        assert.equal(fmt_f64(powi(x, 3)), "0.0000000000000000000009999999999999997")
    }
    test "f64_7" {
        let x = 5e-324;
        assert.equal(f64_to_bits(x).to_string(), "1");
        assert.equal(f64_to_bits(f64_from_bits(1n)).to_string(), "1");
        assert.equal(
            fmt_f64(x),
            "0.000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005",
        );
        assert.equal(fmt_f64_debug(x), "5e-324");
        assert.equal(fmt_f64_exp(x), "5e-324");
        assert.equal(fmt_f64_prec(x, 3), "0.000");
        assert.equal(fmt_f64_prec(x, 0), "0");
        assert.equal(fmt_f64(powi(x, 3)), "0")
    }
    test "f64_8" {
        let x = 2.2250738585072014e-308;
        assert.equal(f64_to_bits(x).to_string(), "4503599627370496");
        assert.equal(f64_to_bits(f64_from_bits(4503599627370496n)).to_string(), "4503599627370496");
        assert.equal(
            fmt_f64(x),
            "0.000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022250738585072014",
        );
        assert.equal(fmt_f64_debug(x), "2.2250738585072014e-308");
        assert.equal(fmt_f64_exp(x), "2.2250738585072014e-308");
        assert.equal(fmt_f64_prec(x, 3), "0.000");
        assert.equal(fmt_f64_prec(x, 0), "0");
        assert.equal(fmt_f64(powi(x, 3)), "0")
    }
    test "f64_9" {
        let x = 1.7976931348623157e308;
        assert.equal(f64_to_bits(x).to_string(), "9218868437227405311");
        assert.equal(
            f64_to_bits(f64_from_bits(9218868437227405311n)).to_string(),
            "9218868437227405311",
        );
        assert.equal(
            fmt_f64(x),
            "179769313486231570000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
        );
        assert.equal(fmt_f64_debug(x), "1.7976931348623157e308");
        assert.equal(fmt_f64_exp(x), "1.7976931348623157e308");
        assert.equal(
            fmt_f64_prec(x, 3),
            "179769313486231570814527423731704356798070567525844996598917476803157260780028538760589558632766878171540458953514382464234321326889464182768467546703537516986049910576551282076245490090389328944075868508455133942304583236903222948165808559332123348274797826204144723168738177180919299881250404026184124858368.000",
        );
        assert.equal(
            fmt_f64_prec(x, 0),
            "179769313486231570814527423731704356798070567525844996598917476803157260780028538760589558632766878171540458953514382464234321326889464182768467546703537516986049910576551282076245490090389328944075868508455133942304583236903222948165808559332123348274797826204144723168738177180919299881250404026184124858368",
        );
        assert.equal(fmt_f64(powi(x, 3)), "inf")
    }
    test "f64_10" {
        let x = 123456.789;
        assert.equal(f64_to_bits(x).to_string(), "4683220299150161609");
        assert.equal(
            f64_to_bits(f64_from_bits(4683220299150161609n)).to_string(),
            "4683220299150161609",
        );
        assert.equal(fmt_f64(x), "123456.789");
        assert.equal(fmt_f64_debug(x), "123456.789");
        assert.equal(fmt_f64_exp(x), "1.23456789e5");
        assert.equal(fmt_f64_prec(x, 3), "123456.789");
        assert.equal(fmt_f64_prec(x, 0), "123457");
        assert.equal(fmt_f64(powi(x, 3)), "1881676371789155")
    }
    test "f64_11" {
        let x = 0.3333333333333333;
        assert.equal(f64_to_bits(x).to_string(), "4599676419421066581");
        assert.equal(
            f64_to_bits(f64_from_bits(4599676419421066581n)).to_string(),
            "4599676419421066581",
        );
        assert.equal(fmt_f64(x), "0.3333333333333333");
        assert.equal(fmt_f64_debug(x), "0.3333333333333333");
        assert.equal(fmt_f64_exp(x), "3.333333333333333e-1");
        assert.equal(fmt_f64_prec(x, 3), "0.333");
        assert.equal(fmt_f64_prec(x, 0), "0");
        assert.equal(fmt_f64(powi(x, 3)), "0.037037037037037035")
    }
    test "f64_12" {
        let x = 1e16;
        assert.equal(f64_to_bits(x).to_string(), "4846369599423283200");
        assert.equal(
            f64_to_bits(f64_from_bits(4846369599423283200n)).to_string(),
            "4846369599423283200",
        );
        assert.equal(fmt_f64(x), "10000000000000000");
        assert.equal(fmt_f64_debug(x), "1e16");
        assert.equal(fmt_f64_exp(x), "1e16");
        assert.equal(fmt_f64_prec(x, 3), "10000000000000000.000");
        assert.equal(fmt_f64_prec(x, 0), "10000000000000000");
        assert.equal(fmt_f64(powi(x, 3)), "1000000000000000000000000000000000000000000000000")
    }
    test "f64_13" {
        let x = 1e15;
        assert.equal(f64_to_bits(x).to_string(), "4831355200913801216");
        assert.equal(
            f64_to_bits(f64_from_bits(4831355200913801216n)).to_string(),
            "4831355200913801216",
        );
        assert.equal(fmt_f64(x), "1000000000000000");
        assert.equal(fmt_f64_debug(x), "1000000000000000.0");
        assert.equal(fmt_f64_exp(x), "1e15");
        assert.equal(fmt_f64_prec(x, 3), "1000000000000000.000");
        assert.equal(fmt_f64_prec(x, 0), "1000000000000000");
        assert.equal(fmt_f64(powi(x, 3)), "1000000000000000100000000000000000000000000000")
    }
    test "f64_14" {
        let x = 9.999999e-6;
        assert.equal(f64_to_bits(x).to_string(), "4532020583020639726");
        assert.equal(
            f64_to_bits(f64_from_bits(4532020583020639726n)).to_string(),
            "4532020583020639726",
        );
        assert.equal(fmt_f64(x), "0.000009999999");
        assert.equal(fmt_f64_debug(x), "9.999999e-6");
        assert.equal(fmt_f64_exp(x), "9.999999e-6");
        assert.equal(fmt_f64_prec(x, 3), "0.000");
        assert.equal(fmt_f64_prec(x, 0), "0");
        assert.equal(fmt_f64(powi(x, 3)), "0.00000000000000099999970000003")
    }
    test "f64_15" {
        let x = 2.5;
        assert.equal(f64_to_bits(x).to_string(), "4612811918334230528");
        assert.equal(
            f64_to_bits(f64_from_bits(4612811918334230528n)).to_string(),
            "4612811918334230528",
        );
        assert.equal(fmt_f64(x), "2.5");
        assert.equal(fmt_f64_debug(x), "2.5");
        assert.equal(fmt_f64_exp(x), "2.5e0");
        assert.equal(fmt_f64_prec(x, 3), "2.500");
        assert.equal(fmt_f64_prec(x, 0), "2");
        assert.equal(fmt_f64(powi(x, 3)), "15.625")
    }
    test "f64_16" {
        let x = 0.125;
        assert.equal(f64_to_bits(x).to_string(), "4593671619917905920");
        assert.equal(
            f64_to_bits(f64_from_bits(4593671619917905920n)).to_string(),
            "4593671619917905920",
        );
        assert.equal(fmt_f64(x), "0.125");
        assert.equal(fmt_f64_debug(x), "0.125");
        assert.equal(fmt_f64_exp(x), "1.25e-1");
        assert.equal(fmt_f64_prec(x, 3), "0.125");
        assert.equal(fmt_f64_prec(x, 0), "0");
        assert.equal(fmt_f64(powi(x, 3)), "0.001953125")
    }
    test "f64_17" {
        let x = 1e100;
        assert.equal(f64_to_bits(x).to_string(), "6103021453049119613");
        assert.equal(
            f64_to_bits(f64_from_bits(6103021453049119613n)).to_string(),
            "6103021453049119613",
        );
        assert.equal(
            fmt_f64(x),
            "10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
        );
        assert.equal(fmt_f64_debug(x), "1e100");
        assert.equal(fmt_f64_exp(x), "1e100");
        assert.equal(
            fmt_f64_prec(x, 3),
            "10000000000000000159028911097599180468360808563945281389781327557747838772170381060813469985856815104.000",
        );
        assert.equal(
            fmt_f64_prec(x, 0),
            "10000000000000000159028911097599180468360808563945281389781327557747838772170381060813469985856815104",
        );
        assert.equal(
            fmt_f64(powi(x, 3)),
            "1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
        )
    }
    test "f64_18" {
        let x = 3.0e-310;
        assert.equal(f64_to_bits(x).to_string(), "60720675992193");
        assert.equal(f64_to_bits(f64_from_bits(60720675992193n)).to_string(), "60720675992193");
        assert.equal(
            fmt_f64(x),
            "0.0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003",
        );
        assert.equal(fmt_f64_debug(x), "3e-310");
        assert.equal(fmt_f64_exp(x), "3e-310");
        assert.equal(fmt_f64_prec(x, 3), "0.000");
        assert.equal(fmt_f64_prec(x, 0), "0");
        assert.equal(fmt_f64(powi(x, 3)), "0")
    }
    test "f64_19" {
        let x = 6.02214076e23;
        assert.equal(f64_to_bits(x).to_string(), "4962933279127225623");
        assert.equal(
            f64_to_bits(f64_from_bits(4962933279127225623n)).to_string(),
            "4962933279127225623",
        );
        assert.equal(fmt_f64(x), "602214076000000000000000");
        assert.equal(fmt_f64_debug(x), "6.02214076e23");
        assert.equal(fmt_f64_exp(x), "6.02214076e23");
        assert.equal(fmt_f64_prec(x, 3), "602214075999999987023872.000");
        assert.equal(fmt_f64_prec(x, 0), "602214075999999987023872");
        assert.equal(
            fmt_f64(powi(x, 3)),
            "218400036772254780000000000000000000000000000000000000000000000000000000",
        )
    }
    test "f64_20" {
        let x = 255.0 / 3.0;
        assert.equal(f64_to_bits(x).to_string(), "4635681760191971328");
        assert.equal(
            f64_to_bits(f64_from_bits(4635681760191971328n)).to_string(),
            "4635681760191971328",
        );
        assert.equal(fmt_f64(x), "85");
        assert.equal(fmt_f64_debug(x), "85.0");
        assert.equal(fmt_f64_exp(x), "8.5e1");
        assert.equal(fmt_f64_prec(x, 3), "85.000");
        assert.equal(fmt_f64_prec(x, 0), "85");
        assert.equal(fmt_f64(powi(x, 3)), "614125")
    }
    test "f64_21" {
        let x = 1.0 / 3.0;
        assert.equal(f64_to_bits(x).to_string(), "4599676419421066581");
        assert.equal(
            f64_to_bits(f64_from_bits(4599676419421066581n)).to_string(),
            "4599676419421066581",
        );
        assert.equal(fmt_f64(x), "0.3333333333333333");
        assert.equal(fmt_f64_debug(x), "0.3333333333333333");
        assert.equal(fmt_f64_exp(x), "3.333333333333333e-1");
        assert.equal(fmt_f64_prec(x, 3), "0.333");
        assert.equal(fmt_f64_prec(x, 0), "0");
        assert.equal(fmt_f64(powi(x, 3)), "0.037037037037037035")
    }
}
