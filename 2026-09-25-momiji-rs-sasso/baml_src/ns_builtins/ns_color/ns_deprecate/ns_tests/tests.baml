// Ported from sasso `src/builtins/color/deprecate.rs` `#[cfg(test)] mod tests`
// (namespace `root.builtins.color.deprecate.tests`; `use super::{deprecates,
// suggestions}` → `root.builtins.color.deprecate.*`, `crate::value::{Color,
// Number, Value}` → `root.value.*`).

/// Every name that can reach the `[color-functions]` gate: the union of the
/// per-family `NAMES` tables `is_builtin` is built from, plus the two
/// `sass:color` members that have no global alias and therefore appear in no
/// `NAMES` table at all (`color_ext::call_module_member`).
function every_builtin_name() -> string[] {
    let v: string[] = root.builtins.color.NAMES()
        .concat(root.builtins.color.MODERN_NAMES())
        .concat(root.builtins.color_ext.NAMES())
        .concat(root.builtins.string.NAMES())
        .concat(root.builtins.map.NAMES())
        .concat(root.builtins.list.NAMES())
        .concat(root.builtins.meta.NAMES())
        .concat(root.builtins.selector.NAMES())
        .concat(root.builtins.math.NAMES());
    v.push("whiteness");
    v.push("blackness");
    root.std.sort_strings(v);
    root.std.dedup(v);
    v
}

/// Drift guard for the name-only gate. [`deprecates`] exists so a caller can
/// reject a call before doing any colour maths, which means it is asked
/// FIRST and its answer is final: a name it says `false` to never reaches
/// [`suggestions`], so if the two ever disagree the gate wins and a warning
/// disappears silently. This asserts they cannot disagree, over the whole
/// universe of names that can reach the gate.
test "the_name_gate_agrees_with_the_suggestion_tables" {
    // Arguments every adjuster can read: a colour and an amount. The channel
    // getters ignore them.
    let args: root.value.Value[] = [
        root.value.Value_Color { _0: root.value.Color.rgb(171.0, 205.0, 239.0, 1.0) },
        root.value.Value_Number { _0: root.value.Number.with_unit(10.0, "%") },
    ];
    let named: root.std.Tuple2<string, root.value.Value>[] = [];
    let gated: string[] = [];
    for (let name in every_builtin_name()) {
        let gate = root.builtins.color.deprecate.deprecates(name);
        let sug = root.builtins.color.deprecate.suggestions(name, args, named) != null;
        // `{name}`: gate says {gate}, suggestions() says {sug}
        assert.equal(gate, sug);
        if (sug) {
            gated.push(name);
        }
    }
    // And the set itself, so a table that silently loses an arm fails here
    // rather than quietly stopping a warning. These are exactly the legacy
    // members Color 4 replaced; `alpha`, `mix`, `grayscale`, `complement`
    // and `invert` are deliberately absent (see [`suggestions`]).
    assert.equal(
        gated,
        [
            "adjust-hue",
            "blackness",
            "blue",
            "darken",
            "desaturate",
            "fade-in",
            "fade-out",
            "green",
            "hue",
            "lighten",
            "lightness",
            "opacify",
            "red",
            "saturate",
            "saturation",
            "transparentize",
            "whiteness",
        ],
    )
}

/// The one direction that is allowed to disagree, and why it is safe.
/// [`suggestions`] reads the call's arguments and yields `None` when it
/// cannot, so it is NARROWER than the gate. That order is the safe one: the
/// gate over-admits, the exact path then declines, and nothing is lost.
/// Reversed — a gate narrower than the tables — would drop warnings.
test "the_gate_over_admits_and_never_under_admits" {
    let no_args: root.value.Value[] = [];
    let named: root.std.Tuple2<string, root.value.Value>[] = [];
    assert.is_true(root.builtins.color.deprecate.deprecates("lighten"));
    assert.is_true(root.builtins.color.deprecate.suggestions("lighten", no_args, named) == null);
    // A colour with no amount is the same shape: admitted, then declined.
    let color: root.value.Value[] = [root.value.Value_Color { _0: root.value.Color.rgb(1.0, 2.0, 3.0, 1.0) }];
    assert.is_true(root.builtins.color.deprecate.suggestions("lighten", color, named) == null);
    // A channel getter needs no arguments at all, so it never declines.
    assert.is_true(root.builtins.color.deprecate.deprecates("red"));
    assert.is_true(root.builtins.color.deprecate.suggestions("red", no_args, named) != null)
}
