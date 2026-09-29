// Ported from sasso `src/builtins/meta.rs` `#[cfg(test)] mod tests`
// (namespace `root.builtins.meta.tests`; `use super::*` →
// `root.builtins.meta.*`, plus the parent's imports `root.value.*`,
// `root.scanner.Pos`, `root.error.Error`; `use crate::value::{Color, List,
// Number}` → `root.value.Color` / `root.value.List` / `root.value.Number`).

function pos() -> root.scanner.Pos {
    root.scanner.Pos { line: 1, col: 1 }
}

function n(value: float, unit: string) -> root.value.Value {
    root.value.Value_Number { _0: root.value.Number.with_unit(value, unit) }
}

function sq(text: string) -> root.value.Value {
    root.value.Value_Str { _0: root.value.SassStr { text: text, quoted: true } }
}

function su(text: string) -> root.value.Value {
    root.value.Value_Str { _0: root.value.SassStr { text: text, quoted: false } }
}

function list(items: root.value.Value[], sep: root.value.ListSep) -> root.value.Value {
    root.value.Value_List { _0: root.value.List.new(items, sep, false) }
}

function call(name: string, args: root.value.Value[]) -> root.value.Value {
    let named: root.std.Tuple2<string, root.value.Value>[] = [];
    let r = root.std.expect(
        root.builtins.meta.try_call(name, args, named, pos()),
        "name owned by meta family",
    );
    // PORT: `Result::expect("no error")` on the stored `Ok`/`Err` value.
    match (r) {
        let ok: root.std.Ok<root.value.Value> => ok.value,
        let err: root.std.Err<root.error.Error> => root.std.panic(`no error: ${err.error.message}`),
    }
}

function call_err(name: string, args: root.value.Value[]) -> root.error.Error {
    let named: root.std.Tuple2<string, root.value.Value>[] = [];
    let r = root.std.expect(
        root.builtins.meta.try_call(name, args, named, pos()),
        "name owned by meta family",
    );
    // PORT: `Result::expect_err("expected error")` on the stored `Ok`/`Err` value.
    match (r) {
        let ok: root.std.Ok<root.value.Value> => {
            root.std.panic(`expected error: ${ok.value.to_css(false)}`)
        },
        let err: root.std.Err<root.error.Error> => err.error,
    }
}

test "type_of_reports_type_name" {
    assert.equal(call("type-of", [n(1.0, "px")]).to_css(false), "number");
    assert.equal(call("type-of", [sq("hi")]).to_css(false), "string");
    assert.equal(
        call("type-of", [root.value.Value_Color { _0: root.value.Color.rgb(255.0, 0.0, 0.0, 1.0) }])
            .to_css(false),
        "color",
    );
    assert.equal(
        call("type-of", [list([n(1.0, ""), n(2.0, "")], root.value.ListSep.Comma)]).to_css(false),
        "list",
    );
    assert.equal(call("type-of", [root.value.Value_Bool { _0: true }]).to_css(false), "bool");
    assert.equal(call("type-of", [root.value.Value_Null {  }]).to_css(false), "null")
}

test "unit_is_quoted" {
    assert.equal(call("unit", [n(1.0, "px")]).to_css(false), "\"px\"");
    assert.equal(call("unit", [n(5.0, "%")]).to_css(false), "\"%\"");
    assert.equal(call("unit", [n(5.0, "")]).to_css(false), "\"\"");
    assert.is_true(call_err("unit", [sq("x")]).message.includes("is not a number"))
}

test "unitless_reports_bool" {
    assert.is_true(
        match (call("unitless", [n(5.0, "")])) {
            root.value.Value_Bool { _0: true } => true,
            _ => false,
        },
    );
    assert.is_true(
        match (call("unitless", [n(5.0, "px")])) {
            root.value.Value_Bool { _0: false } => true,
            _ => false,
        },
    )
}

test "comparable_unit_groups" {
    let t = (a: root.value.Value, b: root.value.Value) -> bool {
        match (call("comparable", [a, b])) {
            root.value.Value_Bool { _0: true } => true,
            _ => false,
        }
    };
    assert.is_true(t(n(1.0, "px"), n(2.0, "px")));
    assert.is_true(t(n(1.0, "px"), n(2.0, "cm")));
    assert.is_true(t(n(1.0, "in"), n(2.0, "pt")));
    assert.is_true(t(n(1.0, "px"), n(5.0, ""))); // unitless
    assert.is_true(t(n(5.0, ""), n(5.0, "")));
    assert.is_true(t(n(1.0, "deg"), n(1.0, "turn")));
    assert.is_true(t(n(1.0, "s"), n(1.0, "ms")));
    assert.is_true(t(n(1.0, "Hz"), n(1.0, "kHz")));
    assert.is_true(t(n(1.0, "dpi"), n(1.0, "dppx")));
    assert.is_true(t(n(1.0, "foo"), n(1.0, "foo"))); // identical unknown units

    assert.is_true(!t(n(1.0, "px"), n(1.0, "em")));
    assert.is_true(!t(n(1.0, "px"), n(5.0, "%")));
    assert.is_true(!t(n(1.0, "Q"), n(1.0, "in"))); // Q has no length factor
    assert.is_true(!t(n(1.0, "foo"), n(1.0, "bar")));
    assert.is_true(!t(n(1.0, "px"), n(1.0, "s")))
}

test "inspect_scalars" {
    assert.equal(call("inspect", [sq("hi")]).to_css(false), "\"hi\"");
    assert.equal(call("inspect", [su("hi")]).to_css(false), "hi");
    assert.equal(call("inspect", [root.value.Value_Null {  }]).to_css(false), "null");
    assert.equal(call("inspect", [n(1.0, "px")]).to_css(false), "1px");
    assert.equal(call("inspect", [root.value.Value_Bool { _0: true }]).to_css(false), "true");
    let red = root.value.Color { r: 255.0, g: 0.0, b: 0.0, a: 1.0, repr: "red", modern: null };
    assert.equal(call("inspect", [root.value.Value_Color { _0: red }]).to_css(false), "red");
    // A computed color inspects as its css form.
    assert.equal(
        call("inspect", [root.value.Value_Color { _0: root.value.Color.rgb(255.0, 0.0, 0.0, 1.0) }])
            .to_css(false),
        "#ff0000",
    )
}

test "inspect_lists" {
    let empty: root.value.Value[] = [];
    // top-level comma/space lists: no outer parens
    assert.equal(
        call("inspect", [list([n(1.0, ""), n(2.0, ""), n(3.0, "")], root.value.ListSep.Comma)])
            .to_css(false),
        "1, 2, 3",
    );
    assert.equal(
        call("inspect", [list([n(1.0, ""), n(2.0, ""), n(3.0, "")], root.value.ListSep.Space)])
            .to_css(false),
        "1 2 3",
    );
    // empty list
    assert.equal(call("inspect", [list(empty, root.value.ListSep.Space)]).to_css(false), "()");
    // single-element comma list keeps trailing comma
    assert.equal(
        call("inspect", [list([n(1.0, "")], root.value.ListSep.Comma)]).to_css(false),
        "(1,)",
    )
}

test "inspect_nested_lists" {
    let empty: root.value.Value[] = [];
    let comma2 = (a: root.value.Value, b: root.value.Value) -> root.value.Value {
        list([a, b], root.value.ListSep.Comma)
    };
    let space2 = (a: root.value.Value, b: root.value.Value) -> root.value.Value {
        list([a, b], root.value.ListSep.Space)
    };

    // comma list nested in comma parent -> parens
    assert.equal(
        call("inspect", [comma2(n(1.0, ""), list([n(2.0, ""), n(3.0, "")], root.value.ListSep.Comma))])
            .to_css(false),
        "1, (2, 3)",
    );
    // space list nested in comma parent -> no parens
    assert.equal(
        call("inspect", [comma2(n(1.0, ""), list([n(2.0, ""), n(3.0, "")], root.value.ListSep.Space))])
            .to_css(false),
        "1, 2 3",
    );
    // space lists nested in a space parent -> parens
    assert.equal(
        call(
            "inspect",
            [
                space2(
                    list([n(1.0, ""), n(2.0, "")], root.value.ListSep.Space),
                    list([n(3.0, ""), n(4.0, "")], root.value.ListSep.Space),
                ),
            ],
        )
            .to_css(false),
        "(1 2) (3 4)",
    );
    // comma lists nested in a space parent -> parens
    assert.equal(
        call(
            "inspect",
            [
                space2(
                    list([n(1.0, ""), n(2.0, "")], root.value.ListSep.Comma),
                    list([n(3.0, ""), n(4.0, "")], root.value.ListSep.Comma),
                ),
            ],
        )
            .to_css(false),
        "(1, 2) (3, 4)",
    );
    // single-element comma list nested in a space parent keeps its own parens
    assert.equal(
        call("inspect", [space2(list([n(1.0, "")], root.value.ListSep.Comma), n(2.0, ""))]).to_css(
            false,
        ),
        "(1,) 2",
    );
    // empty list nested keeps its own parens
    assert.equal(
        call("inspect", [comma2(list(empty, root.value.ListSep.Space), n(1.0, ""))]).to_css(false),
        "(), 1",
    )
}

test "feature_exists_known_set" {
    let t = (name: string, quoted: bool) -> root.value.Value {
        call(
            "feature-exists",
            [root.value.Value_Str { _0: root.value.SassStr { text: name, quoted: quoted } }],
        )
    };
    assert.is_true(
        match (t("at-error", false)) {
            root.value.Value_Bool { _0: true } => true,
            _ => false,
        },
    );
    assert.is_true(
        match (t("custom-property", true)) {
            root.value.Value_Bool { _0: true } => true,
            _ => false,
        },
    );
    assert.is_true(
        match (t("global-variable-shadowing", false)) {
            root.value.Value_Bool { _0: true } => true,
            _ => false,
        },
    );
    assert.is_true(
        match (t("nope", false)) {
            root.value.Value_Bool { _0: false } => true,
            _ => false,
        },
    );
    // A non-string argument errors.
    assert.is_true(call_err("feature-exists", [n(1.0, "")]).message.includes("is not a string"))
}

test "rejects_unknown_names" {
    let named: root.std.Tuple2<string, root.value.Value>[] = [];
    assert.is_true(
        root.builtins.meta.try_call("frobnicate", [root.value.Value_Null {  }], named, pos())
            == null,
    )
}
