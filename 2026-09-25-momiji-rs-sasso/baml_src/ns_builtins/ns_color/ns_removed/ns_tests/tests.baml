// Ported from sasso `src/builtins/color/removed.rs` `#[cfg(test)] mod tests`
// (namespace `root.builtins.color.removed.tests`; `use super::{is_member,
// REMOVED}` → `root.builtins.color.removed.*`).

/// The table is the set dart-sass removed, and nothing else. A name added
/// here that dart still implements would turn a working call into an error.
test "the_table_is_the_nine_removed_members" {
    let names: string[] = root.builtins.color.removed.REMOVED().map((t) -> {
        t._0
    });
    let sorted = root.std.clone_vec(names);
    root.std.sort_strings(names);
    // keep REMOVED sorted by name
    assert.equal(names, sorted);
    assert.equal(
        names,
        [
            "adjust-hue",
            "darken",
            "desaturate",
            "fade-in",
            "fade-out",
            "lighten",
            "opacify",
            "saturate",
            "transparentize",
        ],
    )
}

/// The members that LOOK like these and are not: every one of them is still
/// a live `sass:color` member, so claiming it here would break a call that
/// works.
test "the_surviving_members_are_not_claimed" {
    for (
        let name in [
            "adjust",
            "scale",
            "change",
            "alpha",
            "opacity",
            "grayscale",
            "invert",
            "complement",
            "mix",
            "hue",
            "saturation",
            "lightness",
            "whiteness",
            "blackness",
            "channel",
            "ie-hex-str",
        ]
    ) {
        // `{name}` is still a member
        assert.is_true(!root.builtins.color.removed.is_member(name));
    }
}
