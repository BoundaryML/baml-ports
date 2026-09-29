// Ported from sasso `src/builtins/math.rs` `#[cfg(test)] mod tests`
// (namespace `root.builtins.math.tests`; `use super::*` →
// `root.builtins.math.*`, plus the parent's imports `root.value.*`,
// `root.error.Error`; `use crate::scanner::Pos` → `root.scanner.Pos`;
// `use crate::value::SassStr` → `root.value.SassStr`).

function pos() -> root.scanner.Pos {
    root.scanner.Pos { line: 1, col: 1 }
}

function n(value: float, unit: string) -> root.value.Value {
    root.value.Value_Number { _0: root.value.Number.with_unit(value, unit) }
}

function call(name: string, args: root.value.Value[]) -> root.value.Value {
    let named: root.std.Tuple2<string, root.value.Value>[] = [];
    let r = root.std.expect(
        root.builtins.math.try_call(name, args, named, pos()),
        "name owned by math family",
    );
    // PORT: `Result::expect("no error")` on the stored `Ok`/`Err` value.
    match (r) {
        let ok: root.std.Ok<root.value.Value> => ok.value,
        let err: root.std.Err<root.error.Error> => root.std.panic(`no error: ${err.error.message}`),
    }
}

function err(name: string, args: root.value.Value[]) -> bool {
    let named: root.std.Tuple2<string, root.value.Value>[] = [];
    let r = root.std.expect(root.builtins.math.try_call(name, args, named, pos()), "name owned");
    // PORT: `Result::is_err()` on the stored `Ok`/`Err` value.
    match (r) {
        let _ok: root.std.Ok<root.value.Value> => false,
        let _err: root.std.Err<root.error.Error> => true,
    }
}

test "abs_keeps_unit_and_magnitude" {
    assert.equal(call("abs", [n(-3.0, "px")]).to_css(false), "3px");
    assert.equal(call("abs", [n(3.0, "")]).to_css(false), "3")
}

test "ceil_and_floor_keep_unit" {
    assert.equal(call("ceil", [n(4.2, "px")]).to_css(false), "5px");
    assert.equal(call("floor", [n(4.8, "%")]).to_css(false), "4%")
}

test "round_is_half_away_from_zero" {
    assert.equal(call("round", [n(2.5, "")]).to_css(false), "3");
    assert.equal(call("round", [n(-2.5, "deg")]).to_css(false), "-3deg");
    assert.equal(call("round", [n(0.5, "")]).to_css(false), "1")
}

test "round_strategies_with_step" {
    let kw = (s: string) -> root.value.Value {
        root.value.Value_Str { _0: root.value.SassStr { text: s, quoted: false } }
    };
    let no_args: root.value.Value[] = [];
    assert.equal(
        call("round", [kw("nearest"), n(117.0, "px"), n(25.0, "px")]).to_css(false),
        "125px",
    );
    assert.equal(call("round", [kw("up"), n(101.0, "px"), n(25.0, "px")]).to_css(false), "125px");
    assert.equal(call("round", [kw("down"), n(122.0, "px"), n(25.0, "px")]).to_css(false), "100px");
    // to-zero with a negative step keeps the step's sign in the rounding.
    assert.equal(
        call("round", [kw("to-zero"), n(-120.0, "px"), n(-25.0, "px")]).to_css(false),
        "-125px",
    );
    // Two-argument nearest-with-step and unit coercion.
    assert.equal(call("round", [n(117.0, ""), n(25.0, "")]).to_css(false), "125");
    assert.equal(call("round", [n(117.0, "cm"), n(25.0, "mm")]).to_css(false), "117.5cm");
    // A zero step yields NaN, serialized as a calculation.
    assert.equal(
        call("round", [kw("nearest"), n(10.0, "px"), n(0.0, "px")]).to_css(false),
        "calc(NaN * 1px)",
    );
    // An infinite number rounds to itself (a calculation).
    assert.equal(
        call("round", [kw("nearest"), kw("infinity"), n(5.0, "")]).to_css(false),
        "calc(infinity)",
    );
    // A bare strategy with no step, a unit mismatch, and a missing arg all
    // error.
    assert.is_true(err("round", [kw("nearest"), n(5.0, "")]));
    assert.is_true(err("round", [n(10.0, "px"), n(5.0, "")]));
    assert.is_true(err("round", no_args))
}

test "min_max_pick_winning_argument_unit" {
    assert.equal(call("min", [n(1.0, "px"), n(2.0, "px")]).to_css(false), "1px");
    assert.equal(call("max", [n(1.0, ""), n(2.0, ""), n(3.0, "")]).to_css(false), "3");
    // min(1in, 2cm): 1in == 2.54cm > 2cm, so 2cm wins (keeps cm).
    assert.equal(call("min", [n(1.0, "in"), n(2.0, "cm")]).to_css(false), "2cm");
    // single arg returns itself even with an unknown unit.
    assert.equal(call("min", [n(1.0, "vw")]).to_css(false), "1vw")
}

test "min_max_preserve_css_form_on_incompatible" {
    assert.equal(call("min", [n(1.0, "px"), n(2.0, "vw")]).to_css(false), "min(1px, 2vw)");
    // a non-number argument also forces the preserved form.
    let var = root.value.Value_Str { _0: root.value.SassStr { text: "var(--x)", quoted: false } };
    assert.equal(call("min", [n(1.0, "px"), var]).to_css(false), "min(1px, var(--x))")
}

test "clamp_orders_min_value_max" {
    assert.equal(call("clamp", [n(1.0, "px"), n(5.0, "px"), n(3.0, "px")]).to_css(false), "3px");
    assert.equal(call("clamp", [n(1.0, "px"), n(0.0, "px"), n(3.0, "px")]).to_css(false), "1px");
    // unresolvable middle arg preserves the CSS call.
    let var = root.value.Value_Str { _0: root.value.SassStr { text: "var(--x)", quoted: false } };
    assert.equal(
        call("clamp", [n(1.0, "px"), var, n(3.0, "px")]).to_css(false),
        "clamp(1px, var(--x), 3px)",
    )
}

test "pow_sqrt_exp_log_are_unitless" {
    assert.equal(call("pow", [n(2.0, ""), n(3.0, "")]).to_css(false), "8");
    assert.equal(call("sqrt", [n(4.0, "")]).to_css(false), "2");
    assert.equal(call("exp", [n(0.0, "")]).to_css(false), "1");
    assert.equal(call("log", [n(8.0, ""), n(2.0, "")]).to_css(false), "3");
    assert.is_true(err("sqrt", [n(4.0, "px")]));
    assert.is_true(err("pow", [n(2.0, "px"), n(2.0, "")]))
}

test "trig_accepts_angles_and_returns_unitless" {
    assert.equal(call("sin", [n(30.0, "deg")]).to_css(false), "0.5");
    assert.equal(call("cos", [n(0.0, "")]).to_css(false), "1");
    assert.equal(call("tan", [n(45.0, "deg")]).to_css(false), "1");
    assert.equal(call("sin", [n(100.0, "grad")]).to_css(false), "1");
    assert.equal(call("sin", [n(0.25, "turn")]).to_css(false), "1");
    assert.is_true(err("sin", [n(1.0, "px")]))
}

test "inverse_trig_returns_degrees" {
    assert.equal(call("asin", [n(0.5, "")]).to_css(false), "30deg");
    assert.equal(call("acos", [n(1.0, "")]).to_css(false), "0deg");
    assert.equal(call("atan", [n(1.0, "")]).to_css(false), "45deg");
    assert.equal(call("atan2", [n(1.0, ""), n(1.0, "")]).to_css(false), "45deg")
}

test "sign_keeps_units" {
    assert.equal(call("sign", [n(-5.0, "px")]).to_css(false), "-1px");
    // Zero keeps the operand's unit too (dart `coerceToMatch`).
    assert.equal(call("sign", [n(0.0, "px")]).to_css(false), "0px");
    assert.equal(call("sign", [n(3.0, "")]).to_css(false), "1");
    // A `%` operand preserves the call.
    assert.equal(call("sign", [n(7.0, "%")]).to_css(false), "sign(7%)")
}

test "hypot_converts_onto_first_unit" {
    assert.equal(call("hypot", [n(3.0, ""), n(4.0, "")]).to_css(false), "5");
    assert.equal(call("hypot", [n(3.0, "px"), n(4.0, "px")]).to_css(false), "5px");
    assert.is_true(err("hypot", [n(3.0, "px"), n(4.0, "")]))
}

test "rem_and_mod_signs" {
    assert.equal(call("rem", [n(10.0, ""), n(3.0, "")]).to_css(false), "1");
    assert.equal(call("rem", [n(-10.0, ""), n(3.0, "")]).to_css(false), "-1");
    assert.equal(call("mod", [n(-10.0, ""), n(3.0, "")]).to_css(false), "2");
    // 10px rem 3pt -> 3pt == 4px, 10 % 4 == 2 -> 2px.
    assert.equal(call("rem", [n(10.0, "px"), n(3.0, "pt")]).to_css(false), "2px");
    assert.is_true(err("rem", [n(10.0, "px"), n(3.0, "")]))
}

test "rejects_non_numbers_and_unknown_names" {
    let named: root.std.Tuple2<string, root.value.Value>[] = [];
    let e = root.builtins.math.try_call("abs", [root.value.Value_Bool { _0: true }], named, pos());
    assert.is_true(e != null);
    // PORT: `e.expect("some").is_err()` on the stored `Ok`/`Err` value.
    assert.is_true(
        match (root.std.expect(e, "some")) {
            let _ok: root.std.Ok<root.value.Value> => false,
            let _err: root.std.Err<root.error.Error> => true,
        },
    );
    assert.is_true(
        root.builtins.math.try_call("definitely-not-math", [n(4.0, "")], named, pos()) == null,
    )
}
