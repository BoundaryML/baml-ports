// Ported from sasso `src/builtins/color/removed.rs` (namespace `root.builtins.color.removed`).
//
// The nine legacy adjusters CSS Color 4 REMOVED from `sass:color`.
//
// `lighten`, `darken`, `saturate`, `desaturate`, `opacify`, `fade-in`,
// `transparentize`, `fade-out` and `adjust-hue` still exist as GLOBAL
// functions (deprecated, implemented in [`super::super::color_ext`]) but are
// gone from the module, where dart-sass keeps a stub whose whole job is to
// name the member, hand back a replacement computed from the call's own
// arguments, and link the docs. They are real members for every other
// purpose: `meta.function-exists`, `meta.get-function`, `@forward`, and a
// `@use "sass:color" as *` that makes the bare name shadow the global.
//
// Three details of the replacement text look like they should come from the
// `[color-functions]` deprecation next door ([`super::deprecate`]) and do not
// — that one describes a call that SUCCEEDED, this one a call that cannot:
//
// - it echoes the call's own `$color` argument where the deprecation writes a
//   `$color` placeholder;
// - the negation is TEXTUAL, a `-` written in front of whatever the amount
//   serialized to, so `darken($c, -10%)` recommends `$lightness: --10%`, `0%`
//   recommends `-0%`, and `"x"` recommends `-"x"`;
// - no unit conversion happens: `adjust-hue($c, 0.25turn)` recommends
//   `$hue: 0.25turn`, where the deprecation would say `90deg`.
//
// The arguments are never validated — `color.lighten("nope", 10%)` reports the
// same removal, with `"nope"` in the recommendation — but the ARITY is checked
// first, by the declaration dart gives the stub (`$color, $amount`, for
// `adjust-hue` too, where the global binds `$degrees`).
//
// Every shape here was measured against dart-sass 1.104.1 on 2026-09-19.

/// The stub's own parameter list, which is what the arity error names.
function PARAMS() -> string[] {
    ["color", "amount"]
}

/// Each removed member: the `color.adjust` channel its replacement moves, and
/// whether the amount is negated on the way.
function REMOVED() -> root.std.Tuple3<string, string, bool>[] {
    [
        root.std.Tuple3 { _0: "adjust-hue", _1: "hue", _2: false },
        root.std.Tuple3 { _0: "darken", _1: "lightness", _2: true },
        root.std.Tuple3 { _0: "desaturate", _1: "saturation", _2: true },
        root.std.Tuple3 { _0: "fade-in", _1: "alpha", _2: false },
        root.std.Tuple3 { _0: "fade-out", _1: "alpha", _2: true },
        root.std.Tuple3 { _0: "lighten", _1: "lightness", _2: false },
        root.std.Tuple3 { _0: "opacify", _1: "alpha", _2: false },
        root.std.Tuple3 { _0: "saturate", _1: "saturation", _2: false },
        root.std.Tuple3 { _0: "transparentize", _1: "alpha", _2: true },
    ]
}

/// Whether `member` is one of the removed members — a `sass:color` member that
/// exists, and always fails. Callers pass the canonical spelling
/// (`color.fade_in` is `fade-in`).
function is_member(member: string) -> bool {
    REMOVED().some((t) -> {
        t._0 == member
    })
}

/// Dispatch `color.<removed>(…)`. Always `Some(Err(…))` for a name this module
/// owns: there is no argument list that makes the call succeed.
function call_module_member(
    member: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> (root.std.Ok<root.value.Value> | root.std.Err<root.error.Error>)? {
    let found = REMOVED().find((t) -> {
        t._0 == member
    });
    if (found == null) {
        return null;
    }
    let channel = found._1;
    let negate = found._2;
    root.std.Err { error: error(member, channel, negate, pos_args, named, pos) }
}

/// dart's three-part message: what is gone, what to write instead, where to
/// read about it. The arity of the stub's declaration is reported first, so a
/// call that could not have bound its arguments says so rather than
/// recommending a replacement built from arguments it does not have.
function error(
    member: string,
    channel: string,
    negate: bool,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.error.Error {
    // PORT: `check_arity(…).and_then(|()| { … })` then `match bound { Ok(pair)
    // => pair, Err(e) => return e }` → a block whose thrown `Error` is caught
    // and returned.
    let bound = {
        root.builtins.check_arity(2, pos_args, named, pos);
        let color = root.builtins.require(PARAMS(), pos_args, named, 0, pos);
        let amount = root.builtins.require(PARAMS(), pos_args, named, 1, pos);
        root.std.Tuple2 { _0: color, _1: amount }
    } catch (e) {
        let err: root.error.Error => {
            return err;
        }
    };
    let color = bound._0;
    let amount = bound._1;
    let sign = if (negate) {
        "-"
    } else {
        ""
    };
    root.error.Error.at(
        `The function ${member}() isn't in the sass:color module.\n\nRecommendation: color.adjust(${color.to_inspect_message()}, $${channel}: ${sign}${amount.to_inspect_message()})\n\nMore info: https://sass-lang.com/documentation/functions/color#${member}`,
        pos,
    )
}
