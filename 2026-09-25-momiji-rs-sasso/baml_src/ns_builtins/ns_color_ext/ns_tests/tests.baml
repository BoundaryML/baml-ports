// Ported from sasso `src/builtins/color_ext.rs` `#[cfg(test)] mod tests`
// (namespace `root.builtins.color_ext.tests`; `use super::*` →
// `root.builtins.color_ext.*`, `crate::value::Color` → `root.value.Color`).

function pos() -> root.scanner.Pos {
    root.scanner.Pos { line: 1, col: 1 }
}

function col(s: string) -> root.value.Value {
    let digits = root.std.strip_prefix(s, "#") ?? s;
    root.value.Value_Color { _0: root.std.expect(root.value.Color.from_hex(digits), "valid hex") }
}

function n(v: float, unit: string) -> root.value.Value {
    root.value.Value_Number { _0: root.value.Number.with_unit(v, unit) }
}

function css(name: string, args: root.value.Value[]) -> string {
    let named: root.std.Tuple2<string, root.value.Value>[] = [];
    let r = root.std.expect(
        root.builtins.color_ext.try_call(name, args, named, pos()),
        "name owned by color_ext family",
    );
    // PORT: `Result::expect("no error")` on the stored `Ok`/`Err` value.
    let v: root.value.Value = match (r) {
        let ok: root.std.Ok<root.value.Value> => ok.value,
        let err: root.std.Err<root.error.Error> => root.std.panic(`no error: ${err.error.message}`),
    };
    v.to_css(false)
}

test "adjust_hue_and_complement" {
    assert.equal(css("adjust-hue", [col("#6b717f"), n(60.0, "deg")]), "#796b7f");
    assert.equal(css("adjust-hue", [col("#6b717f"), n(-60.0, "deg")]), "#6b7f79");
    assert.equal(css("complement", [col("#6b717f")]), "#7f796b")
}

test "invert_full_and_weighted" {
    assert.equal(css("invert", [col("#b37399")]), "#4c8c66");
    assert.equal(
        css("invert", [col("#b37399"), n(80.0, "%")]),
        "rgb(37.8823529412%, 52.9411764706%, 44%)",
    );
    assert.equal(css("invert", [col("#b37399"), n(50.0, "%")]), "rgb(50%, 50%, 50%)")
}

test "grayscale_saturate_desaturate" {
    assert.equal(css("grayscale", [col("#6b717f")]), "#757575");
    assert.equal(css("saturate", [col("#cc6699"), n(30.0, "%")]), "rgb(92%, 28%, 60%)");
    assert.equal(css("desaturate", [col("#6b717f"), n(20.0, "%")]), "#757575")
}

test "alpha_shifts" {
    let rgba: root.value.Value = root.value.Value_Color { _0: root.value.Color.rgb(0.0, 51.0, 102.0, 0.7) };
    assert.equal(css("opacify", [rgba, n(0.2, "")]), "rgba(0, 51, 102, 0.9)");
    assert.equal(css("fade-in", [rgba, n(0.2, "")]), "rgba(0, 51, 102, 0.9)");
    assert.equal(css("transparentize", [rgba, n(0.2, "")]), "rgba(0, 51, 102, 0.5)");
    // Opacify past full opacity collapses to an opaque hex.
    assert.equal(css("opacify", [rgba, n(0.5, "")]), "#003366")
}

test "hsl_getters_units" {
    assert.equal(css("hue", [col("#6b717f")]), "222deg");
    assert.equal(css("saturation", [col("#6b717f")]), "8.547008547%");
    assert.equal(css("lightness", [col("#6b717f")]), "45.8823529412%")
}

test "unowned_returns_none" {
    let no_args: root.value.Value[] = [];
    let named: root.std.Tuple2<string, root.value.Value>[] = [];
    assert.is_true(
        root.builtins.color_ext.try_call("not-a-color-fn", no_args, named, pos()) == null,
    )
}
