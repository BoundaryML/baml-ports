// Ported from sasso `src/host_fn.rs` `#[cfg(test)] mod tests`
// (namespace `root.host_fn.tests`; `crate::{compile, Options}` →
// `root.compile` / `root.Options`, `use super::{deserialize_args,
// serialize_one}` → `root.host_fn.*`, `crate::value::{ListSep, Number,
// SassStr, Value}` → `root.value.*`).
//
// PORT: a callback's `Err(message)` is a thrown `root.std.StrError`
// (`root.std.err_str(message)`), and `?` on `deserialize_args` propagates it.

function opts_pow() -> root.Options {
    // pow($base, $exponent) -> number
    let cb: root.host_fn.HostFunction = (bytes: uint8array) -> uint8array {
        let args = root.host_fn.deserialize_args(bytes);
        let base = match (args[0]) {
            root.value.Value_Number { _0: let n } => n.value,
            _ => root.std.err_str("base must be a number"),
        };
        let exp = match (args[1]) {
            root.value.Value_Number { _0: let n } => n.value,
            _ => root.std.err_str("exponent must be a number"),
        };
        root.host_fn.serialize_one(
            root.value.Value_Number { _0: root.value.Number.unitless(base.pow(exp)) },
        )
    };
    root.Options.default().with_function("pow($base, $exponent)", cb)
}

test "custom_function_number" {
    let css = root.compile(".a { width: pow(2, 10) * 1px; }", opts_pow());
    // got: {css}
    assert.is_true(css.includes("width: 1024px"))
}

test "custom_function_keyword_args" {
    let css = root.compile(".a { x: pow($exponent: 3, $base: 2); }", opts_pow());
    // got: {css}
    assert.is_true(css.includes("x: 8"))
}

test "custom_function_overrides_builtin_but_not_user" {
    // A custom function shadows the builtin global of the same name...
    let cb: root.host_fn.HostFunction = (unused: uint8array) -> uint8array {
        root.host_fn.serialize_one(
            root.value.Value_Str { _0: root.value.SassStr { text: "custom", quoted: false } },
        )
    };
    let o = root.Options.default().with_function("type-of($v)", cb);
    let css = root.compile(".a { x: type-of(1); }", o);
    // custom should override builtin: {css}
    assert.is_true(css.includes("x: custom"));
    // ...but a user @function still wins.
    let cb2: root.host_fn.HostFunction = (unused: uint8array) -> uint8array {
        root.host_fn.serialize_one(
            root.value.Value_Str { _0: root.value.SassStr { text: "custom", quoted: false } },
        )
    };
    let o2 = root.Options.default().with_function("foo($v)", cb2);
    let css2 = root.compile("@function foo($v) { @return user; }\n.a { x: foo(1); }", o2);
    // user @function should win: {css2}
    assert.is_true(css2.includes("x: user"))
}

test "custom_function_string_list_map_roundtrip" {
    // Receive a MAP + a LIST, read into them, and return a quoted STRING —
    // exercising deserialization of all three on the way in.
    let cb: root.host_fn.HostFunction = (bytes: uint8array) -> uint8array {
        let args = root.host_fn.deserialize_args(bytes);
        let map = match (args[0]) {
            root.value.Value_Map { _0: let m } => m,
            _ => root.std.err_str("arg 1 must be a map"),
        };
        // map value for key `b`
        let b: root.value.Value = map.get(root.value.Value_Str { _0: root.value.SassStr { text: "b", quoted: false } })
            ?? root.value.Value_Null {  };
        let bn = if let bv: root.value.Value_Number = b {
            bv._0.value
        } else {
            -1.0
        };
        let list = match (args[1]) {
            root.value.Value_List { _0: let l } => l,
            _ => root.std.err_str("arg 2 must be a list"),
        };
        let count = list.items.length();
        root.host_fn.serialize_one(
            root.value.Value_Str {
                _0: root.value.SassStr { text: `b=${root.std.fmt_f64(bn)} n=${count}`, quoted: true },
            },
        )
    };
    let o = root.Options.default().with_function("probe($m, $l)", cb);
    let css = root.compile(".a { x: probe((a: 1, b: 2), (x y z)); }", o);
    // map+list deserialized, string round-trips: {css}
    assert.is_true(css.includes("\"b=2 n=3\""));
    let _ = root.value.ListSep.Comma;
}

test "custom_function_rest_args" {
    // sum($nums...) -> number
    let cb: root.host_fn.HostFunction = (bytes: uint8array) -> uint8array {
        let args = root.host_fn.deserialize_args(bytes);
        let list = match (args[0]) {
            root.value.Value_List { _0: let l } => l,
            _ => root.std.err_str("expected an arglist"),
        };
        let total: float = list.items
            .map((v: root.value.Value) -> float {
                if let nv: root.value.Value_Number = v {
                    nv._0.value
                } else {
                    0.0
                }
            })
            .reduce(
                (acc: float, x: float) -> float {
                    acc + x
                },
                0.0,
            );
        root.host_fn.serialize_one(
            root.value.Value_Number { _0: root.value.Number.unitless(total) },
        )
    };
    let o = root.Options.default().with_function("sum($nums...)", cb);
    let css = root.compile(".a { x: sum(1, 2, 3, 4); }", o);
    // got: {css}
    assert.is_true(css.includes("x: 10"))
}

test "custom_function_color_roundtrip" {
    // PORT: `use crate::value::{Color, ColorSpace, ModernColor}` → `root.value.*`.
    // ident($c) returns the color unchanged (forces a full serialize +
    // reconstruct cycle); a legacy color stays legacy and re-emits as hex.
    let ident: root.host_fn.HostFunction = (bytes: uint8array) -> uint8array {
        let args = root.host_fn.deserialize_args(bytes);
        root.host_fn.serialize_one(args[0])
    };
    let o = root.Options.default().with_function("ident($c)", ident);
    let css = root.compile(".a { color: ident(#0080ff); }", o);
    // legacy color round-trips: {css}
    assert.is_true(css.includes("#0080ff"));

    // read a channel out of a received color
    let red: root.host_fn.HostFunction = (bytes: uint8array) -> uint8array {
        let args = root.host_fn.deserialize_args(bytes);
        let c = match (args[0]) {
            root.value.Value_Color { _0: let c } => c,
            _ => root.std.err_str("not a color"),
        };
        root.host_fn.serialize_one(root.value.Value_Number { _0: root.value.Number.unitless(c.r) })
    };
    let o2 = root.Options.default().with_function("redof($c)", red);
    let css2 = root.compile(".a { x: redof(rgb(12, 0, 0)); }", o2);
    // channel read: {css2}
    assert.is_true(css2.includes("x: 12"));

    // return a MODERN color (oklch) built by the callback
    let mk: root.host_fn.HostFunction = (unused: uint8array) -> uint8array {
        let mc = root.value.ModernColor {
            space: root.value.ColorSpace.Oklch,
            channels: [0.5, 0.2, 180.0],
            alpha: 1.0,
        };
        // PORT: `super::make_modern_in` is host_fn's import of
        // `crate::builtins::color::math::make_modern_in`.
        root.host_fn.serialize_one(
            root.value.Value_Color {
                _0: root.builtins.color.math.make_modern_in(mc, root.value.ColorSpace.Oklch),
            },
        )
    };
    let o3 = root.Options.default().with_function("mkcolor()", mk);
    let css3 = root.compile(".a { color: mkcolor(); }", o3);
    // modern color round-trips: {css3}
    assert.is_true(css3.includes("oklch("));
    let _ = root.value.Color.rgb(0.0, 0.0, 0.0, 1.0);
}

test "custom_function_error_surfaces" {
    let cb: root.host_fn.HostFunction = (unused: uint8array) -> uint8array {
        root.std.err_str("boom")
    };
    let o = root.Options.default().with_function("bad($x)", cb);
    // PORT: `.unwrap_err()` → catch the `Error`; an `Ok` panics as Rust's
    // `unwrap_err` would.
    let err = {
        let css = root.compile(".a { x: bad(1); }", o);
        root.std.panic(
            `called \`Result::unwrap_err()\` on an \`Ok\` value: ${root.std.debug_str(css)}`,
        )
    } catch (e) {
        let x: root.error.Error => x
    };
    // got: {err.message}
    assert.is_true(err.message.includes("boom"))
}

test "value_op_number_convert" {
    // PORT: `use super::{deserialize_value, host_value_op, serialize_args,
    // OP_NUMBER_CONVERT}` → `root.host_fn.*`; `crate::value::List` →
    // `root.value.List`.
    let strs = (u: string) -> root.value.Value {
        root.value.Value_List {
            _0: root.value.List.new(
                [root.value.Value_Str { _0: root.value.SassStr { text: u, quoted: false } }],
                root.value.ListSep.Space,
                false,
            ),
        }
    };
    let no_items: root.value.Value[] = [];
    let empty: root.value.Value = root.value.Value_List { _0: root.value.List.new(no_items, root.value.ListSep.Space, false) };
    // 96px -> in == 1in (convert)
    let args: root.value.Value[] = [
        root.value.Value_Number { _0: root.value.Number.with_unit(96.0, "px") },
        strs("in"),
        empty,
        root.value.Value_Bool { _0: false },
    ];
    let out = root.host_fn.host_value_op(root.host_fn.OP_NUMBER_CONVERT(), root.host_fn.serialize_args(args));
    match (root.host_fn.deserialize_value(out)) {
        root.value.Value_Number { _0: let n } => {
            // got {n.value}
            assert.approx_equal(n.value, 1.0, 1e-9);
        },
        // PORT: `{v:?}` → the value's inspect form.
        let v => root.std.panic(`expected number, got ${v.to_inspect_message()}`),
    };
    // incompatible (s -> px) errors
    let bad: root.value.Value[] = [
        root.value.Value_Number { _0: root.value.Number.with_unit(1.0, "s") },
        strs("px"),
        empty,
        root.value.Value_Bool { _0: false },
    ];
    let failed = (
        root.host_fn.host_value_op(
            root.host_fn.OP_NUMBER_CONVERT(),
            root.host_fn.serialize_args(bad),
        ) catch (e) {
            let _e: root.std.StrError => null
        }
    )
        == null;
    assert.is_true(failed)
}
