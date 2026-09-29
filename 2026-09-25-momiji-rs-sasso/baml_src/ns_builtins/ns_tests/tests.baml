// Ported from sasso `src/builtins/mod.rs` `#[cfg(test)] mod tests`
// (namespace `root.builtins.tests`; `use super::is_builtin` →
// `root.builtins.is_builtin`; `super::<family>::NAMES` →
// `root.builtins.<family>.NAMES()`).

/// Lock the byte-observable `is_builtin` classification: a sample across
/// every family must report `true` (including the case-insensitive math
/// name `SiN`, the list-owned `length`, and a function-existence-relevant
/// name like `function-exists`), and unknown / plain-CSS names must report
/// `false`. Mis-classification flips CSS output (slash-division collapse,
/// `function-exists`/`feature-exists`), so this is a real behavior lock.
test "is_builtin_locks_classification" {
    for (
        let name in [
            "lighten", // color_ext
            "rgb", // color
            "color-space", // color (modern)
            "sin", // math
            "SiN", // math, case-insensitive
            "map-get", // map
            "length", // list (not map)
            "selector-parse", // selector
            "function-exists", // meta
        ]
    ) {
        // expected `{name}` to be a builtin
        assert.is_true(root.builtins.is_builtin(name));
    }
    for (let name in ["totally-unknown-fn", "rotate", "translatex"]) {
        // expected `{name}` not to be a builtin
        assert.is_true(!root.builtins.is_builtin(name));
    }
}

/// Equivalence guard: the new per-family-`NAMES` union must classify
/// *exactly* the historical hardcoded set (the union of the pre-refactor
/// `is_builtin` `matches!` arms + `is_math_builtin_name` arms). Locks that
/// the single-source refactor changed no name's classification, and that no
/// extra name leaked into the union. Math names are tested case-insensitively
/// (`SiN`) since the family lowercases before dispatch.
test "is_builtin_matches_historical_set" {
    // The exact pre-refactor non-math `matches!` arms.
    // PORT: the fn-local `const` items are plain local bindings.
    let OLD_NON_MATH: string[] = [
        // color (legacy + modern)
        "rgb",
        "rgba",
        "hsl",
        "hsla",
        "hwb",
        "lab",
        "lch",
        "oklab",
        "oklch",
        "color",
        "mix",
        "lighten",
        "darken",
        "percentage",
        "red",
        "green",
        "blue",
        "alpha",
        "color-space",
        "color-channel",
        "color-to-space",
        "color-is-legacy",
        "color-is-missing",
        "color-is-in-gamut",
        "color-is-powerless",
        "color-to-gamut",
        "color-same",
        // color_ext
        "adjust-hue",
        "complement",
        "invert",
        "grayscale",
        "saturate",
        "desaturate",
        "opacify",
        "fade-in",
        "transparentize",
        "fade-out",
        "hue",
        "saturation",
        "lightness",
        // `whiteness`/`blackness` were in the historical set but never
        // belonged there: dart-sass has no *global* HWB getters (they exist
        // only as `sass:color` members, lib/src/functions/color.dart:532-541
        // vs. the `global` list at line 31). They were removed from
        // `color_ext::NAMES`, so the historical baseline is corrected here
        // rather than the union being bent back to match it.
        "opacity",
        "ie-hex-str",
        "scale-color",
        "adjust-color",
        "change-color",
        // string
        "quote",
        "unquote",
        "to-upper-case",
        "to-lower-case",
        "str-length",
        "str-index",
        "str-slice",
        "str-insert",
        "unique-id",
        // map
        "map-get",
        "map-keys",
        "map-values",
        "map-has-key",
        "map-merge",
        "map-remove",
        // list (length/nth are list-owned)
        "length",
        "nth",
        "set-nth",
        "join",
        "append",
        "index",
        "list-separator",
        "is-bracketed",
        "zip",
        // meta
        "get-function",
        "type-of",
        "unit",
        "unitless",
        "comparable",
        "inspect",
        "feature-exists",
        "function-exists",
        "calc-name",
        "calc-args",
        // selector
        "selector-nest",
        "selector-append",
        "selector-extend",
        "selector-replace",
        "selector-unify",
        "is-superselector",
        "simple-selectors",
        "selector-parse",
    ];
    // The exact pre-refactor `is_math_builtin_name` arms (lowercase).
    let OLD_MATH: string[] = [
        "abs",
        "ceil",
        "floor",
        "round",
        "min",
        "max",
        "clamp",
        "sign",
        "pow",
        "sqrt",
        "exp",
        "log",
        "hypot",
        "sin",
        "cos",
        "tan",
        "asin",
        "acos",
        "atan",
        "atan2",
        "rem",
        "mod",
        "random",
    ];

    // Direction 1: every name the old set owned is still a builtin.
    for (let name in OLD_NON_MATH.concat(OLD_MATH)) {
        // old builtin `{name}` no longer classified
        assert.is_true(root.builtins.is_builtin(name));
    }

    // Direction 2: the new union introduces no name the old set lacked.
    let new_union: string[] = root.builtins.color.NAMES()
        .concat(root.builtins.color.MODERN_NAMES())
        .concat(root.builtins.color_ext.NAMES())
        .concat(root.builtins.string.NAMES())
        .concat(root.builtins.map.NAMES())
        .concat(root.builtins.list.NAMES())
        .concat(root.builtins.meta.NAMES())
        .concat(root.builtins.selector.NAMES())
        .concat(root.builtins.math.NAMES());
    // PORT: `BTreeSet<&str>` → `map<string, bool>` (`root.std.set_of`).
    let old_set: map<string, bool> = root.std.set_of(OLD_NON_MATH.concat(OLD_MATH));
    for (let name in new_union) {
        // new union introduced unexpected name `{name}`
        assert.is_true(old_set.has(name));
    }
    // Cardinality match (no duplicates within the families, exact size).
    let new_set: map<string, bool> = root.std.set_of(new_union);
    // duplicate name in family NAMES
    assert.equal(new_set.length(), new_union.length());
    // new union != historical builtin set
    // PORT: `BTreeSet` equality → compare the sorted key lists.
    assert.equal(root.std.sorted_keys(new_set), root.std.sorted_keys(old_set))
}
