// Ported from sasso `src/eval/mod.rs` `#[cfg(test)] mod tests`
// (namespace `root.eval.tests`; `use super::*` → `root.eval.*`, and the
// `Value` family that `eval/mod.rs` imports → `root.value.*`).

/// The memo's retention bound. [`Evaluator::probe_arg_memoizable`]'s match is
/// exhaustive, so the compiler already forces a new [`Value`] variant to be
/// classified; what this locks is the ANSWER, because the answer that costs
/// memory — admit it, and retain whatever graph it points at — is the one a
/// hurried patch reaches for. Every shape is written out, so widening the
/// rule has to be a visible edit here rather than a silent change in
/// footprint.
test "the_probe_memo_admits_only_bounded_argument_shapes" {
    // What `color_function_suggestions` actually reads, and nothing else.
    let admitted: root.value.Value[] = [
        root.value.Value_Number { _0: root.value.Number.unitless(1.0) },
        root.value.Value_Number { _0: root.value.Number.with_unit(10.0, "%") },
        root.value.Value_Color { _0: root.value.Color.rgb(171.0, 205.0, 239.0, 1.0) },
    ];
    for (let v in admitted) {
        // should be memoizable: {v:?}
        assert.is_true(root.eval.Evaluator.probe_arg_memoizable(v));
    }

    let refused: root.value.Value[] = [
        // A simple unit is a shared `Rc<str>`; a complex unit list is a
        // boxed pair of `Vec`s, and it clones deeply.
        root.value.Value_Number { _0: root.value.Number.with_units(1.0, ["px", "px"], []) },
        root.value.Value_Str { _0: root.value.SassStr { text: "x", quoted: true } },
        root.value.Value_List { _0: root.value.List.new([], root.value.ListSep.Space, false) },
        root.value.Value_Map { _0: root.value.Map.new([]) },
        root.value.Value_Bool { _0: true },
        root.value.Value_Null {  },
        root.value.Value_Slash { _0: root.value.Number.unitless(1.0), _1: "1/2" },
        root.value.Value_Calc { _0: root.value.CalcNode_Str { _0: "var(--x)" } },
        root.value.Value_Function {
            _0: root.value.SassFunction { name: "f", css: false, module: null, user: null },
        },
        root.value.Value_Mixin { _0: root.value.SassMixin { name: "m", user: null, module: null } },
    ];
    for (let v in refused) {
        // should not be memoizable: {v:?}
        assert.is_true(!root.eval.Evaluator.probe_arg_memoizable(v));
    }

    // The two lists together are the whole enum, so a new variant cannot be
    // added without landing on one side of it or the other.
    let variants = root.std.set_of(
        admitted.concat(refused).map((v) -> {
            discriminant(v)
        }),
    );
    // one case per `Value` variant
    assert.equal(variants.length(), 11)
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

/// What the reused serialization buffer must never do: leak the tail of the
/// value before it. Every declaration is written into the same `String`, so a
/// missing `clear()` — or a later serializer that appends where it means to
/// overwrite — surfaces as one declaration wearing the end of its
/// predecessor. This sheet therefore steps DOWN in length twice, and covers
/// both declaration paths: ordinary declarations and a property set's
/// leading value (`border: 1px solid #abcdef { radius: 4px; }`), which
/// serializes through the same buffer while a nested block is being built.
test "the_reused_value_buffer_never_leaks_the_previous_value" {
    // PORT: `concat!(…)` → `+` over the same string pieces.
    let src = ".a {\n"
        + "  box-shadow: 0 12px 24px rgba(0, 0, 0, 0.35), inset 0 1px 0 #ffffff;\n"
        + "  color: #abc;\n"
        + "  z-index: 1;\n"
        + "  border: 1px solid #abcdef { radius: 4px; }\n"
        + "  outline: 0;\n"
        + "}\n";
    // PORT: `.expect("compiles")` → an `Err` propagates out of the test and fails it.
    let css = root.compile(src, root.Options.default());
    let expected = ".a {\n"
        + "  box-shadow: 0 12px 24px rgba(0, 0, 0, 0.35), inset 0 1px 0 #ffffff;\n"
        + "  color: #abc;\n"
        + "  z-index: 1;\n"
        + "  border: 1px solid #abcdef;\n"
        + "  border-radius: 4px;\n"
        + "  outline: 0;\n"
        + "}";
    assert.equal(root.std.trim_end(css), expected)
}
