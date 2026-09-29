// Ported from sasso `src/builtins/color_ext.rs` (namespace `root.builtins.color_ext`).
//
// Extended color built-ins (`adjust-hue`, `saturate`, `desaturate`,
// `complement`, `invert`, `grayscale`, `opacify`/`transparentize`, the
// `hue`/`saturation`/`lightness` getters, …).
//
// Results are *computed* colors: they carry no source spelling, so they
// serialize via the normal `rgb()`/`rgba()`/hex rule, matching dart-sass.
// The adjusters keep the input color's SPACE, though — dart hands
// `saturate(hsl(…), 10%)` back as an `hsl()` — which is what
// [`legacy_hsl_adjust`] and [`legacy_alpha_adjust`] are for.

/// The modern change/adjust/scale path: used when `$space` is given, or when
/// the color is non-legacy (its own space is the default). Returns `None` for a
/// legacy color with no `$space`, so the caller runs the legacy path.
function modify_with_space(
    c: root.value.Color,
    named: root.std.Tuple2<string, root.value.Value>[],
    op: root.builtins.color.modern.ModifyOp,
    pos: root.scanner.Pos,
) -> (root.std.Ok<root.value.Value> | root.std.Err<root.error.Error>)? {
    let space_arg_v = named
        .find((t) -> {
            t._0 == "space"
        })
        ?._1;
    let is_legacy = match (c.modern) {
        let m: root.value.ModernColor => m.space.is_legacy(),
        _ => true,
    };
    if (space_arg_v == null && is_legacy) {
        return null;
    }
    let space: root.value.ColorSpace = match (space_arg_v) {
        let v: root.value.Value => {
            root.builtins.color.math.space_arg(v, pos) catch (e) {
                let err: root.error.Error => {
                    return root.std.Err { error: err };
                }
            }
        },
        _ => match (c.modern) {
            let m: root.value.ModernColor => m.space,
            _ => root.value.ColorSpace.Rgb,
        },
    };
    // `$color` (when passed by name) and `$space` are not channels.
    let chans: root.std.Tuple2<string, root.value.Value>[] = named
        .filter((t) -> {
            t._0 != "space" && t._0 != "color"
        })
        .map((t) -> {
            root.std.Tuple2 { _0: t._0, _1: t._1 }
        });
    // An explicit `$space` enables the powerless-channel missing check.
    result_of(() -> {
        root.builtins.color.modern.modify_in_space_opt(
            c,
            space,
            chans,
            op,
            space_arg_v != null,
            pos,
        )
    })
}

/// Build a *computed* color, tagging it with a CSS named-color spelling when
/// its rounded RGB exactly matches one of the 148 CSS color names and it is
/// fully opaque. dart-sass serializes such colors by name (e.g.
/// `lighten(red, 100%)` → `white`, `adjust-hue(red, 180)` → `aqua`); colors
/// that don't match a name fall back to the usual hex/rgb rule via `repr =
/// None`.
function computed(r: float, g: float, b: float, a: float) -> root.value.Color {
    let c = root.value.Color.rgb(r, g, b, a);
    // dart has no untagged color: an rgb RESULT that left the [0, 255] gamut —
    // a NaN channel included, which is what mixing an infinite channel
    // produces — is written through its hsl form. That rule lives in
    // `ModernColor::legacy_css`, so tag the color to reach it; an in-gamut
    // result keeps the plain hex/rgb/name spelling.
    // PORT: `(lo..=hi).contains(&v)` → `v >= lo && v <= hi` (a NaN fails the
    // upper bound: BAML orders NaN above every number).
    let in_gamut = (v: float) -> bool {
        v >= -0.000000001 && v <= 255.0 + 0.000000001
    };
    if (in_gamut(r) && in_gamut(g) && in_gamut(b)) {
        c.repr = named_repr(r, g, b, a);
    } else {
        let channels: (float?)[] = [r, g, b];
        c.modern
            = root.value.ModernColor {
                space: root.value.ColorSpace.Rgb,
                channels: channels,
                alpha: a,
            };
    }
    c
}

/// The CSS named-color spelling for an exact, fully-opaque RGB triple, using
/// dart-sass's canonical name for each color (e.g. `aqua` not `cyan`, `gray`
/// not `grey`). Returns `None` for translucent colors, non-integer channels,
/// or colors with no name.
function named_repr(r: float, g: float, b: float, a: float) -> string? {
    if (!root.value.fuzzy_eq(a, 1.0)) {
        return null;
    }
    // PORT: the closure `int` is named `int_` (`int` is a type name).
    let int_ = (v: float) -> int? {
        // dart finds the name by looking the color up in `namesByColor`, so the
        // hit needs `fuzzyHashCode` — the 1e11 rounding of `fuzzyEquals` — to
        // agree on every channel. `[measured]`:
        // `color.change(red, $red: 254.9999999999)` is `rgb(100%, 0%, 0%)`, not
        // `red`, even though the channel is 1e-10 from 255.
        let r = v.round();
        if (root.value.fuzzy_eq(v, r) && r >= 0.0 && r <= 255.0) {
            root.std.f64_to_int(r)
        } else {
            null
        }
    };
    let ri = int_(r);
    if (ri == null) {
        return null;
    }
    let gi = int_(g);
    if (gi == null) {
        return null;
    }
    let bi = int_(b);
    if (bi == null) {
        return null;
    }
    // PORT: `match (r, g, b) { (0, 0, 0) => … }` → a match on the key
    // `"r,g,b"` (a tuple cannot be matched).
    let name = match (`${ri},${gi},${bi}`) {
        "0,0,0" => "black",
        "0,0,128" => "navy",
        "0,0,139" => "darkblue",
        "0,0,205" => "mediumblue",
        "0,0,255" => "blue",
        "0,100,0" => "darkgreen",
        "0,128,0" => "green",
        "0,128,128" => "teal",
        "0,139,139" => "darkcyan",
        "0,191,255" => "deepskyblue",
        "0,206,209" => "darkturquoise",
        "0,250,154" => "mediumspringgreen",
        "0,255,0" => "lime",
        "0,255,127" => "springgreen",
        "0,255,255" => "aqua",
        "25,25,112" => "midnightblue",
        "30,144,255" => "dodgerblue",
        "32,178,170" => "lightseagreen",
        "34,139,34" => "forestgreen",
        "46,139,87" => "seagreen",
        "47,79,79" => "darkslategray",
        "50,205,50" => "limegreen",
        "60,179,113" => "mediumseagreen",
        "64,224,208" => "turquoise",
        "65,105,225" => "royalblue",
        "70,130,180" => "steelblue",
        "72,61,139" => "darkslateblue",
        "72,209,204" => "mediumturquoise",
        "75,0,130" => "indigo",
        "85,107,47" => "darkolivegreen",
        "95,158,160" => "cadetblue",
        "100,149,237" => "cornflowerblue",
        "102,51,153" => "rebeccapurple",
        "102,205,170" => "mediumaquamarine",
        "105,105,105" => "dimgray",
        "106,90,205" => "slateblue",
        "107,142,35" => "olivedrab",
        "112,128,144" => "slategray",
        "119,136,153" => "lightslategray",
        "123,104,238" => "mediumslateblue",
        "124,252,0" => "lawngreen",
        "127,255,0" => "chartreuse",
        "127,255,212" => "aquamarine",
        "128,0,0" => "maroon",
        "128,0,128" => "purple",
        "128,128,0" => "olive",
        "128,128,128" => "gray",
        "135,206,235" => "skyblue",
        "135,206,250" => "lightskyblue",
        "138,43,226" => "blueviolet",
        "139,0,0" => "darkred",
        "139,0,139" => "darkmagenta",
        "139,69,19" => "saddlebrown",
        "143,188,143" => "darkseagreen",
        "144,238,144" => "lightgreen",
        "147,112,219" => "mediumpurple",
        "148,0,211" => "darkviolet",
        "152,251,152" => "palegreen",
        "153,50,204" => "darkorchid",
        "154,205,50" => "yellowgreen",
        "160,82,45" => "sienna",
        "165,42,42" => "brown",
        "169,169,169" => "darkgray",
        "173,216,230" => "lightblue",
        "173,255,47" => "greenyellow",
        "175,238,238" => "paleturquoise",
        "176,196,222" => "lightsteelblue",
        "176,224,230" => "powderblue",
        "178,34,34" => "firebrick",
        "184,134,11" => "darkgoldenrod",
        "186,85,211" => "mediumorchid",
        "188,143,143" => "rosybrown",
        "189,183,107" => "darkkhaki",
        "192,192,192" => "silver",
        "199,21,133" => "mediumvioletred",
        "205,92,92" => "indianred",
        "205,133,63" => "peru",
        "210,105,30" => "chocolate",
        "210,180,140" => "tan",
        "211,211,211" => "lightgray",
        "216,191,216" => "thistle",
        "218,112,214" => "orchid",
        "218,165,32" => "goldenrod",
        "219,112,147" => "palevioletred",
        "220,20,60" => "crimson",
        "220,220,220" => "gainsboro",
        "221,160,221" => "plum",
        "222,184,135" => "burlywood",
        "224,255,255" => "lightcyan",
        "230,230,250" => "lavender",
        "233,150,122" => "darksalmon",
        "238,130,238" => "violet",
        "238,232,170" => "palegoldenrod",
        "240,128,128" => "lightcoral",
        "240,230,140" => "khaki",
        "240,248,255" => "aliceblue",
        "240,255,240" => "honeydew",
        "240,255,255" => "azure",
        "244,164,96" => "sandybrown",
        "245,222,179" => "wheat",
        "245,245,220" => "beige",
        "245,245,245" => "whitesmoke",
        "245,255,250" => "mintcream",
        "248,248,255" => "ghostwhite",
        "250,128,114" => "salmon",
        "250,235,215" => "antiquewhite",
        "250,240,230" => "linen",
        "250,250,210" => "lightgoldenrodyellow",
        "253,245,230" => "oldlace",
        "255,0,0" => "red",
        "255,0,255" => "fuchsia",
        "255,20,147" => "deeppink",
        "255,69,0" => "orangered",
        "255,99,71" => "tomato",
        "255,105,180" => "hotpink",
        "255,127,80" => "coral",
        "255,140,0" => "darkorange",
        "255,160,122" => "lightsalmon",
        "255,165,0" => "orange",
        "255,182,193" => "lightpink",
        "255,192,203" => "pink",
        "255,215,0" => "gold",
        "255,218,185" => "peachpuff",
        "255,222,173" => "navajowhite",
        "255,228,181" => "moccasin",
        "255,228,196" => "bisque",
        "255,228,225" => "mistyrose",
        "255,235,205" => "blanchedalmond",
        "255,239,213" => "papayawhip",
        "255,240,245" => "lavenderblush",
        "255,245,238" => "seashell",
        "255,248,220" => "cornsilk",
        "255,250,205" => "lemonchiffon",
        "255,250,240" => "floralwhite",
        "255,250,250" => "snow",
        "255,255,0" => "yellow",
        "255,255,224" => "lightyellow",
        "255,255,240" => "ivory",
        "255,255,255" => "white",
        _ => {
            return null;
        },
    };
    name
}

/// The names the `color_ext` family owns by name (the single source of truth,
/// mirroring the `try_call` match arms below).
function NAMES() -> string[] {
    [
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
        // NOTE: `whiteness`/`blackness` are deliberately absent. dart-sass never
        // had *global* HWB getters: its `global` list (lib/src/functions/color.dart
        // :31-449) declares `_channelFunction`s only for red/green/blue and
        // hue/saturation/lightness, while `whiteness`/`blackness` appear solely in
        // the `sass:color` module list (same file, lines 532-541). Registering them
        // globally made `whiteness(c)` compute 25% where dart emits the untouched
        // plain-CSS `whiteness(hsl(120, 50%, 50%))`. They stay reachable as the
        // deprecated module members via `call_module_member` below.
        "opacity",
        "ie-hex-str",
        "scale-color",
        "adjust-color",
        "change-color",
    ]
}

function try_call(
    name: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> (root.std.Ok<root.value.Value> | root.std.Err<root.error.Error>)? {
    // PORT: `Some(match name { … })` — an arm yielding a `Result` is captured as
    // an `Ok`/`Err` value by `result_of`; a `return` arm hands its `Option` back.
    match (name) {
        "adjust-hue" => {
            result_of(() -> {
                fn_adjust_hue(pos_args, named, pos)
            })
        },
        "complement" => {
            result_of(() -> {
                fn_complement(pos_args, named, pos)
            })
        },
        "invert" => fn_invert(pos_args, named, pos),
        "grayscale" => fn_grayscale(pos_args, named, pos),
        "saturate" => fn_saturate(name, pos_args, named, pos, 1.0),
        "desaturate" => {
            result_of(() -> {
                fn_saturate_two(name, pos_args, named, pos, -1.0)
            })
        },
        "opacify" | "fade-in" => {
            result_of(() -> {
                fn_fade(name, pos_args, named, pos, 1.0)
            })
        },
        "transparentize" | "fade-out" => {
            result_of(() -> {
                fn_fade(name, pos_args, named, pos, -1.0)
            })
        },
        // `whiteness`/`blackness` are *not* listed here: they are module-only
        // (see `call_module_member`).
        "hue" | "saturation" | "lightness" => {
            result_of(() -> {
                fn_hsl_getter(name, pos_args, named, pos)
            })
        },
        "opacity" => fn_opacity(pos_args, named, pos),
        "ie-hex-str" => {
            result_of(() -> {
                fn_ie_hex_str(pos_args, named, pos)
            })
        },
        "scale-color" => {
            result_of(() -> {
                fn_scale_color(pos_args, named, pos)
            })
        },
        "adjust-color" => {
            result_of(() -> {
                fn_adjust_color(pos_args, named, pos)
            })
        },
        "change-color" => {
            result_of(() -> {
                fn_change_color(pos_args, named, pos)
            })
        },
        _ => null,
    }
}

/// `sass:color` members of this family that have **no global alias**.
///
/// dart-sass exposes `whiteness`/`blackness` only on `sass:color`
/// (lib/src/functions/color.dart:532-541, inside the `module` list); its
/// `global` list (same file, line 31) has no such entries, so a bare
/// `whiteness(…)` call is an unknown plain-CSS function that dart passes
/// through verbatim. Dispatching them here — from `call_module` only — keeps
/// `color.whiteness()` / `color.blackness()` working without leaking the names
/// back into the global namespace via `NAMES`/`try_call`.
function call_module_member(
    member: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> (root.std.Ok<root.value.Value> | root.std.Err<root.error.Error>)? {
    match (member) {
        "whiteness" | "blackness" => {
            result_of(() -> {
                fn_hsl_getter(member, pos_args, named, pos)
            })
        },
        _ => null,
    }
}

/// Error when more than `max` POSITIONAL arguments were supplied to a
/// fixed-arity builtin — named ones do not count toward the limit, they only
/// change the wording. See [`super::check_arity`].
function check_max_args(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    max: int,
    pos: root.scanner.Pos,
) -> void {
    root.builtins.check_arity(max, pos_args, named, pos)
}

/// True when a value is a plain-CSS "special" expression (a number, a
/// calculation, or an unquoted string holding a CSS function like `var(...)`).
/// The legacy filter-overloaded color functions (`invert`, `grayscale`,
/// `saturate`, `opacity`) pass such an argument straight through as a CSS
/// function call rather than treating it as a color.
function is_css_special(v: root.value.Value) -> bool {
    match (v) {
        root.value.Value_Number {} | root.value.Value_Calc {} | root.value.Value_Slash {} => true,
        root.value.Value_Str { _0: let s } => !s.quoted && s.text.includes("("),
        _ => false,
    }
}

/// Whether a call to one of the four filter-overloaded names takes the
/// plain-CSS path rather than the Sass one.
///
/// ONE definition, consulted by the functions below AND by the evaluator's
/// deprecation check. They were separate once and disagreed: the call was
/// correctly passed through as CSS while `global-builtin` was deprecated
/// anyway, so `filter: grayscale(1)` told the author to rewrite a CSS filter
/// as `color.grayscale` (#122). dart warns only on the Sass path, and the two
/// decisions have to come from the same place to stay that way.
function is_plain_css_filter_call(
    name: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
) -> bool {
    let arg = (param: string) -> root.value.Value? {
        bound_arg(pos_args, named, param)
    };
    let one_arg = pos_args.length() + named.length() == 1;
    // PORT: `arg(p).is_some_and(is_css_special)` → a `match` on the option.
    match (name) {
        // `saturate($amount)` is the CSS filter; `saturate($color, $amount)`
        // is the Sass function, so arity decides before the argument does.
        "saturate" => {
            one_arg
                && match (arg("amount")) {
                    let a: root.value.Value => is_css_special(a),
                    _ => false,
                }
        },
        // `grayscale`, `opacity` and `invert` do NOT take an arity guard, and
        // that is measured rather than assumed. dart treats `grayscale(1, 2)`
        // as the plain-CSS overload and reports only its arity error; adding
        // `one_arg` here makes the call miss this branch, so the evaluator
        // deprecates it as a global built-in and prints a warning dart never
        // does. `invert` shows the same thing from the other side: its CSS
        // branch is what raises "Only one argument may be passed to the
        // plain-CSS invert() function."
        "grayscale" | "opacity" | "invert" => match (arg("color")) {
            let a: root.value.Value => is_css_special(a),
            _ => false,
        },
        _ => false,
    }
}

/// The argument bound to `$param`, positionally or by name — the same binding
/// the function itself will use.
function bound_arg(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    param: string,
) -> root.value.Value? {
    pos_args.at(0)
        ?? named
            .find((t) -> {
                t._0 == param
            })
            ?._1
}

/// What a `sass:color` MEMBER call does with an argument that the GLOBAL
/// spelling of the same name would have passed through as a plain-CSS filter.
enum ModuleFilterArg {
    /// A number: the filter overload, which the module path still takes and
    /// dart deprecates there (`color-module-compat`).
    Filter,
    /// Any other plain-CSS token — `var(--c)`, `env(…)`, an unsimplifiable
    /// `calc()`, or a bare identifier like `c`. The module path does NOT take
    /// the overload for these; they are colour arguments, and fail as ones.
    NotAColor,
}

/// Which of those two a `color.grayscale`/`color.invert`/`color.opacity` call
/// is, or `None` when the argument is not plain-CSS-special at all (an ordinary
/// colour argument, handled by the function itself).
///
/// The module rule is NARROWER than [`is_plain_css_filter_call`]'s global one,
/// measured against dart-sass 1.104.1: `invert(var(--c))` is a CSS filter,
/// `color.invert(var(--c))` is `$color: var(--c) is not a color.`. Both readers
/// of that rule — the dispatcher, which must raise the error, and the
/// evaluator, which must deprecate exactly the calls that do take the overload
/// — ask this one function, because a disagreement between them would put the
/// warning where dart puts an error (#124; the same shape as #122/#123 one
/// layer up).
///
/// A `calc()` that simplifies to a number IS a number by the time it arrives,
/// so `color.grayscale(calc(1px))` is the filter overload and warns, while
/// `calc(1px + 1em)` is not and does not.
///
/// [`ModuleFilterArg::NotAColor`] covers every UNQUOTED string, not just the
/// `var(…)`-shaped ones [`is_css_special`] recognizes, because that is the only
/// place dart's `$color: ` message prefix is reproduced today: a bare
/// `color.grayscale(c)` reaches it too, and dropping to the generic colour
/// assertion loses the prefix. (That assertion is missing the prefix for every
/// other argument type as well — `null`, `true`, a map, a list — which is a
/// separate gap across the colour and math members, not this rule's.)
function module_filter_arg(
    member: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
) -> root.std.Tuple2<ModuleFilterArg, root.value.Value>? {
    let owned = match (member) {
        "grayscale" | "invert" | "opacity" => true,
        _ => false,
    };
    if (!owned) {
        return null;
    }
    let arg = bound_arg(pos_args, named, "color");
    if (arg == null) {
        return null;
    }
    if (arg is root.value.Value_Number) {
        let filter: root.std.Tuple2<ModuleFilterArg, root.value.Value> = root.std.Tuple2 { _0: ModuleFilterArg.Filter, _1: arg };
        return filter;
    }
    let unquoted_str = match (arg) {
        root.value.Value_Str { _0: let s } if !s.quoted => true,
        _ => false,
    };
    // PORT: `bool::then_some` → `if`/`else`.
    if (is_css_special(arg) || unquoted_str) {
        let not_a_color: root.std.Tuple2<ModuleFilterArg, root.value.Value> = root.std.Tuple2 { _0: ModuleFilterArg.NotAColor, _1: arg };
        not_a_color
    } else {
        null
    }
}

/// The CSS text a one-argument filter overload passes through as
/// (`invert(10%)`, `grayscale(var(--c))`) — dart's `_functionString`. Also the
/// `Recommendation:` line of the `color-module-compat` deprecation, from here
/// so that the recommendation cannot spell the call differently from the value
/// the call returns.
function plain_filter_text(name: string, arg: root.value.Value) -> string {
    `${name}(${arg.to_css(false)})`
}

/// Preserve a one-argument filter overload verbatim (`invert(10%)`,
/// `grayscale(var(--c))`).
function plain_filter(name: string, arg: root.value.Value) -> root.value.Value {
    root.value.Value_Str {
        _0: root.value.SassStr { text: plain_filter_text(name, arg), quoted: false },
    }
}

/// `adjust-hue($color, $degrees)` — rotate the hue by `$degrees`, converting
/// any angle unit (`rad`/`grad`/`turn`) to degrees first.
function fn_adjust_hue(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["color", "degrees"];
    check_max_args(pos_args, named, 2, pos);
    let c = root.builtins.as_color(root.builtins.require(params, pos_args, named, 0, pos), pos);
    root.builtins.require_legacy_color(c, "adjust-hue", pos);
    let degrees = angle_degrees(root.builtins.require(params, pos_args, named, 1, pos), pos);
    root.value.Value_Color { _0: rotate_hue(c, degrees) }
}

/// Extract a hue angle in degrees from a number, converting the common CSS
/// angle units. Unknown units (and the deprecated unitless/`in` cases) are
/// treated as degrees, matching dart-sass's lenient legacy behavior.
function angle_degrees(v: root.value.Value, pos: root.scanner.Pos) -> float {
    match (v) {
        root.value.Value_Number { _0: let n } => match (n.unit()) {
            // PORT: Rust's `f64::to_degrees` via `root.builtins.math.f64_to_degrees`
            // (BAML's `Float.to_degrees` can differ in the last bit).
            "rad" => root.builtins.math.f64_to_degrees(n.value),
            "grad" => n.value * 360.0 / 400.0,
            "turn" => n.value * 360.0,
            _ => n.value,
        },
        let other => {
            throw root.error.Error.at(
            `${other.to_css(false)} is not a number.`,
            pos,
        )
        },
    }
}

/// `complement($color, $space)` — rotate the hue by 180 degrees in `$space`
/// (default `hsl` for legacy colors; required for non-legacy colors).
function fn_complement(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["color", "space"];
    check_max_args(pos_args, named, 2, pos);
    let c = root.builtins.as_color(root.builtins.require(params, pos_args, named, 0, pos), pos);
    let space_v = root.builtins.arg(params, pos_args, named, 1);
    let is_legacy = match (c.modern) {
        let m: root.value.ModernColor => m.space.is_legacy(),
        _ => true,
    };
    let space: root.value.ColorSpace = if (space_v != null) {
        root.builtins.color.math.space_arg(space_v, pos)
    } else if (is_legacy) {
        root.value.ColorSpace.Hsl
    } else {
        throw root.error.Error.at(
            `$space: To use color.complement() with non-legacy color ${c.to_css(false)}, you must provide a $space.`,
            pos,
        );
    };
    // The space must have a hue channel.
    if (
        space != root.value.ColorSpace.Hsl
            && space != root.value.ColorSpace.Hwb
            && space != root.value.ColorSpace.Lch
            && space != root.value.ColorSpace.Oklch
    ) {
        throw root.error.Error.at(
            `$space: Color space ${space.name()} doesn't have a hue channel.`,
            pos,
        );
    }
    // complement = adjust the hue by +180deg in the space. An explicit `$space`
    // enables the powerless-channel missing check.
    let deg: root.value.Value = root.value.Value_Number { _0: root.value.Number.with_unit(180.0, "deg") };
    root.builtins.color.modern.modify_in_space_opt(
        c,
        space,
        [root.std.Tuple2 { _0: "hue", _1: deg }],
        root.builtins.color.modern.ModifyOp.Adjust,
        space_v != null,
        pos,
    )
}

function rotate_hue(c: root.value.Color, degrees: float) -> root.value.Color {
    // The hue is normalized back into `[0, 360)` when the result is rebuilt,
    // and an `rgb()`/hex input still ends up as a computed sRGB color — so
    // `adjust-hue(red, 180)` is still `aqua`.
    root.builtins.color.math.legacy_hsl_adjust(c, (ch: float[]) -> void {
        ch[0] += degrees;
    })
}

/// `invert($color, $weight: 100%)` — invert the RGB channels, then mix the
/// inverted color toward the original by `(100% - weight)`.
///
/// When the single argument is a plain-CSS special value (a number, `var()`,
/// …) this is the CSS `invert()` filter and is preserved verbatim; passing a
/// weight alongside that form is an error.
function fn_invert(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> (root.std.Ok<root.value.Value> | root.std.Err<root.error.Error>)? {
    let params = ["color", "weight"];
    // PORT: `if let Err(e) = …` / `Err(e) => return Some(Err(e))` → catch the
    // thrown error and hand it back as an `Err` value.
    check_max_args(pos_args, named, 3, pos) catch (e) {
        let err: root.error.Error => {
            return root.std.Err { error: err };
        }
    };
    let color = root.builtins.require(params, pos_args, named, 0, pos) catch (e) {
        let err: root.error.Error => {
            return root.std.Err { error: err };
        }
    };
    if (is_plain_css_filter_call("invert", pos_args, named)) {
        if (pos_args.length() + named.length() > 1) {
            return root.std.Err {
                error: root.error.Error.at(
                    "Only one argument may be passed to the plain-CSS invert() function.",
                    pos,
                ),
            };
        }
        return root.std.Ok { value: plain_filter("invert", color) };
    }
    let params = ["color", "weight", "space"];
    // PORT: `Some((|| { … })())` → `result_of(() -> { … })`; a `return Err(e)`
    // inside the closure is a `throw`.
    result_of(() -> {
        let c = root.builtins.as_color(color, pos);
        let weight = match (root.builtins.arg(params, pos_args, named, 1)) {
            let v: root.value.Value => {
                let n = root.builtins.num(v, pos);
                // A NaN is within no range (dart rejects it like any
                // out-of-range value), and the bounds carry the value's unit.
                if (n.is_nan() || !(n >= 0.0 && n <= 100.0)) {
                    let unit = weight_unit(v);
                    throw root.error.Error.at(
                        `$weight: Expected ${v.to_css(false)} to be within 0${unit} and 100${unit}.`,
                        pos,
                    );
                }
                n
            },
            _ => 100.0,
        };
        let w = clamp_f64(weight / 100.0, 0.0, 1.0);
        let space_v = root.builtins.arg(params, pos_args, named, 2);
        let is_legacy = match (c.modern) {
            let m: root.value.ModernColor => m.space.is_legacy(),
            _ => true,
        };
        // The modern form (`$space` given, or a non-legacy color) inverts each
        // channel in that space; a non-legacy color without $space errors.
        if (space_v != null || !is_legacy) {
            let space: root.value.ColorSpace = if (space_v != null) {
                root.builtins.color.math.space_arg(space_v, pos)
            } else {
                throw root.error.Error.at(
                    `$color: To use color.invert() with non-legacy color ${c.to_css(false)}, you must provide a $space.`,
                    pos,
                );
            };
            // An explicit `$space` enables the powerless-channel missing check.
            let inverted: root.value.Value = root.value.Value_Color {
                _0: root.builtins.color.modern.invert_in_space(c, space, w, space_v != null, pos),
            };
            return inverted;
        }
        // Legacy color, no `$space`: invert in rgb (which still rejects a missing
        // rgb channel, but has no powerless channels).
        root.value.Value_Color {
            _0: root.builtins.color.modern.invert_in_space(c, root.value.ColorSpace.Rgb, w, false, pos),
        }
    })
}

/// `grayscale($color)` — set the HSL saturation to 0. With a plain-CSS
/// special argument it is the CSS `grayscale()` filter, preserved verbatim.
function fn_grayscale(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> (root.std.Ok<root.value.Value> | root.std.Err<root.error.Error>)? {
    let params = ["color"];
    // PORT: an `Err` from the argument checks is caught and handed back as a
    // value (see `fn_invert`).
    check_max_args(pos_args, named, 1, pos) catch (e) {
        let err: root.error.Error => {
            return root.std.Err { error: err };
        }
    };
    let color = root.builtins.require(params, pos_args, named, 0, pos) catch (e) {
        let err: root.error.Error => {
            return root.std.Err { error: err };
        }
    };
    if (is_plain_css_filter_call("grayscale", pos_args, named)) {
        return root.std.Ok { value: plain_filter("grayscale", color) };
    }
    result_of(() -> {
        let c = root.builtins.as_color(color, pos);
        // A non-legacy color is desaturated by setting its oklch chroma to 0
        // and converting back to its own space; legacy colors set HSL
        // saturation to 0.
        let is_legacy = match (c.modern) {
            let m: root.value.ModernColor => m.space.is_legacy(),
            _ => true,
        };
        if (!is_legacy) {
            let gray: root.value.Value = root.value.Value_Color { _0: root.builtins.color.modern.grayscale_modern(c) };
            return gray;
        }
        // Legacy grayscale is `change($saturation: 0)` in HSL: a same-space
        // hsl input keeps its hue and missing channels; an rgb/hwb input
        // round-trips through hsl and back to its own space (whose legacy
        // serialization then renders the now-powerless hue as 0).
        let zero: root.value.Value = root.value.Value_Number { _0: root.value.Number.with_unit(0.0, "%") };
        let chans: root.std.Tuple2<string, root.value.Value>[] = [root.std.Tuple2 { _0: "saturation", _1: zero }];
        root.builtins.color.modern.modify_in_space_full(
            c,
            root.value.ColorSpace.Hsl,
            chans,
            root.builtins.color.modern.ModifyOp.Change,
            false,
            false,
            pos,
        )
    })
}

/// `saturate($amount)` (CSS filter overload) and `saturate($color, $amount)`.
/// The one-argument form with a special CSS value is preserved verbatim.
function fn_saturate(
    name: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
    sign: float,
) -> (root.std.Ok<root.value.Value> | root.std.Err<root.error.Error>)? {
    // One argument that is a plain-CSS special value → CSS `saturate()` filter.
    if (is_plain_css_filter_call("saturate", pos_args, named)) {
        let v = root.std.expect(
            pos_args.at(0)
                ?? named
                    .find((t) -> {
                        t._0 == "amount"
                    })
                    ?._1,
            "the predicate matched an argument",
        );
        return root.std.Ok { value: plain_filter("saturate", v) };
    }
    result_of(() -> {
        fn_saturate_two(name, pos_args, named, pos, sign)
    })
}

/// `saturate`/`desaturate` — adjust HSL saturation by `$amount` percent
/// (validated to be within 0 and 100).
function fn_saturate_two(
    name: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
    sign: float,
) -> root.value.Value {
    let params = ["color", "amount"];
    check_max_args(pos_args, named, 2, pos);
    let c = root.builtins.as_color(root.builtins.require(params, pos_args, named, 0, pos), pos);
    root.builtins.require_legacy_color(c, name, pos);
    let amount_v = root.builtins.require(params, pos_args, named, 1, pos);
    // PORT: the shadowed `amount` (value, then number) is `amount_v`/`amount`.
    let amount = bounded(amount_v, 0.0, 100.0, true, pos);
    root.value.Value_Color {
        _0: root.builtins.color.math.legacy_hsl_adjust(c, (ch: float[]) -> void {
            ch[1] = clamp_f64(ch[1] + sign * amount, 0.0, 100.0);
        }),
    }
}

/// The unit a `$weight`/`$amount` percentage argument carries into the bounds
/// of its range error (`0% and 100%`, `0px and 100px`, `0 and 100`). A
/// COMPOUND unit carries whole (`0%/px and 100%/px`), so this is the full unit
/// spelling, not the first numerator.
function weight_unit(v: root.value.Value) -> string {
    match (v) {
        root.value.Value_Number { _0: let n } => n.unit_string(),
        root.value.Value_Slash { _0: let n } => n.unit_string(),
        _ => "",
    }
}

/// Read a number argument and require its value to be within `[lo, hi]`,
/// raising dart-sass's "Expected … to be within …" error otherwise. A NaN is
/// within no range at all, so it is rejected like any out-of-range value
/// (`saturate(red, math.div(0, 0))` is an error in dart-sass, not a color).
/// The number's unit is preserved in the message, and `unit_bounds` spells the
/// BOUNDS with it as well — which dart does for the percentage `$amount`
/// (`saturate(red, 200px)` says `0px and 100px`) but not for the alpha ratio
/// (`transparentize(red, 2px)` still says `0 and 1`).
function bounded(
    v: root.value.Value,
    lo: float,
    hi: float,
    unit_bounds: bool,
    pos: root.scanner.Pos,
) -> float {
    match (v) {
        root.value.Value_Number { _0: let n } => {
            if (n.value.is_nan() || n.value < lo || n.value > hi) {
                let unit = if (unit_bounds) {
                    n.unit_string()
                } else {
                    ""
                };
                throw root.error.Error.at(
                    `$amount: Expected ${n.to_css(false)} to be within ${fmt_bound(lo)}${unit} and ${fmt_bound(hi)}${unit}.`,
                    pos,
                );
            } else {
                n.value
            }
        },
        let other => {
            throw root.error.Error.at(
            `$amount: ${other.to_css(false)} is not a number.`,
            pos,
        )
        },
    }
}

function fmt_bound(v: float) -> string {
    if (root.std.fract(v) == 0.0) {
        `${root.std.f64_to_int(v)}`
    } else {
        root.std.fmt_f64(v)
    }
}

/// `opacify`/`fade-in` (`sign = +1`) and `transparentize`/`fade-out`
/// (`sign = -1`) — shift the alpha by `$amount`, clamped to `[0, 1]`.
function fn_fade(
    name: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
    sign: float,
) -> root.value.Value {
    let params = ["color", "amount"];
    check_max_args(pos_args, named, 2, pos);
    let c = root.builtins.as_color(root.builtins.require(params, pos_args, named, 0, pos), pos);
    root.builtins.require_legacy_color(c, name, pos);
    let amount_v = root.builtins.require(params, pos_args, named, 1, pos);
    // PORT: the shadowed `amount` (value, then number) is `amount_v`/`amount`.
    let amount = bounded(amount_v, 0.0, 1.0, false, pos);
    root.value.Value_Color {
        _0: root.builtins.color.math.legacy_alpha_adjust(c, (a: float) -> float {
            root.builtins.clamp01(a + sign * amount)
        }),
    }
}

/// `hue` (deg), `saturation`/`lightness` (%), and the HWB-derived
/// `whiteness`/`blackness` (%) getters.
function fn_hsl_getter(
    name: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["color"];
    check_max_args(pos_args, named, 1, pos);
    let c = root.builtins.as_color(root.builtins.require(params, pos_args, named, 0, pos), pos);
    // These legacy getters only support legacy colors.
    let is_legacy = match (c.modern) {
        let m: root.value.ModernColor => m.space.is_legacy(),
        _ => true,
    };
    if (!is_legacy) {
        let space = if (name == "whiteness" || name == "blackness") {
            "hwb"
        } else {
            "hsl"
        };
        throw root.error.Error.at(
            `color.${name}() is only supported for legacy colors. Please use color.channel() instead with an explicit $space argument.\n\ncolor.channel($color, "${name}", $space: ${space})`,
            pos,
        );
    }
    // Prefer the stored hsl/hwb channels (exact) over re-deriving from rgb.
    let m = c.modern;
    if (m != null) {
        // PORT: `match (m.space, name) { … }` → an `if`/`else` chain.
        let hsl = m.space == root.value.ColorSpace.Hsl;
        let hwb = m.space == root.value.ColorSpace.Hwb;
        let idx: root.std.Tuple2<int, string>? = if ((hsl && name == "hue") || (hwb && name == "hue")) {
            root.std.Tuple2 { _0: 0, _1: "deg" }
        } else if (hsl && name == "saturation") {
            root.std.Tuple2 { _0: 1, _1: "%" }
        } else if (hsl && name == "lightness") {
            root.std.Tuple2 { _0: 2, _1: "%" }
        } else if (hwb && name == "whiteness") {
            root.std.Tuple2 { _0: 1, _1: "%" }
        } else if (hwb && name == "blackness") {
            root.std.Tuple2 { _0: 2, _1: "%" }
        } else {
            null
        };
        if (idx != null) {
            let i = idx._0;
            let unit = idx._1;
            return root.value.Value_Number { _0: root.value.Number.with_unit(m.channels[i] ?? 0.0, unit) };
        }
    }
    let hsl3 = c.to_hsl();
    let h = hsl3._0;
    let s = hsl3._1;
    let l = hsl3._2;
    // PORT: `let (value, unit) = match name { … }` → a `Tuple2` taken apart.
    let value_unit: root.std.Tuple2<float, string> = match (name) {
        "hue" => root.std.Tuple2 { _0: h, _1: "deg" },
        "saturation" => root.std.Tuple2 { _0: s * 100.0, _1: "%" },
        "lightness" => root.std.Tuple2 { _0: l * 100.0, _1: "%" },
        "whiteness" => {
            root.std.Tuple2 {
                _0: root.std.fmin(root.std.fmin(c.r, c.g), c.b) / 255.0 * 100.0,
                _1: "%",
            }
        },
        // blackness
        _ => {
            root.std.Tuple2 {
                _0: (1.0 - root.std.fmax(root.std.fmax(c.r, c.g), c.b) / 255.0) * 100.0,
                _1: "%",
            }
        },
    };
    let value = value_unit._0;
    let unit = value_unit._1;
    root.value.Value_Number { _0: root.value.Number.with_unit(value, unit) }
}

/// `opacity($color)` returns the alpha; `opacity($number)` (CSS filter
/// overload) is preserved verbatim.
function fn_opacity(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> (root.std.Ok<root.value.Value> | root.std.Err<root.error.Error>)? {
    let params = ["color"];
    // PORT: an `Err` from the argument checks is caught and handed back as a
    // value (see `fn_invert`).
    check_max_args(pos_args, named, 1, pos) catch (e) {
        let err: root.error.Error => {
            return root.std.Err { error: err };
        }
    };
    let color = root.builtins.require(params, pos_args, named, 0, pos) catch (e) {
        let err: root.error.Error => {
            return root.std.Err { error: err };
        }
    };
    if (is_plain_css_filter_call("opacity", pos_args, named)) {
        return root.std.Ok { value: plain_filter("opacity", color) };
    }
    result_of(() -> {
        let c = root.builtins.as_color(color, pos);
        root.value.Value_Number {
            _0: root.value.Number.unitless(root.builtins.color.math.stored_alpha(c)),
        }
    })
}

/// `ie-hex-str($color)` — the `#AARRGGBB` Internet Explorer hex string.
function fn_ie_hex_str(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["color"];
    check_max_args(pos_args, named, 1, pos);
    let c = root.builtins.as_color(root.builtins.require(params, pos_args, named, 0, pos), pos);
    let byte = (v: float) -> int {
        root.std.f64_to_u8(clamp_f64(v.round(), 0.0, 255.0))
    };
    // PORT: `{:02X}` → `hex_upper` left-padded with `0` to two digits.
    let hex2 = (n: int) -> string {
        let h = root.std.hex_upper(n);
        if (h.length() < 2) {
            "0" + h
        } else {
            h
        }
    };
    let text = `#${hex2(byte(root.builtins.color.math.stored_alpha(c) * 255.0))}${hex2(byte(c.r))}${hex2(byte(c.g))}${hex2(byte(c.b))}`;
    root.value.Value_Str { _0: root.value.SassStr { text: text, quoted: false } }
}

// ---- scale-color / adjust-color / change-color ------------------------
/// Which legacy color space a set of keyword channels operates in.
enum Space {
    Rgb,
    Hsl,
    Hwb,
}

interface SpaceMethods {
    function name(self) -> string throws unknown;
}

implements SpaceMethods for Space {
    function name(self) -> string {
        match (self) {
            Space.Rgb => "rgb",
            Space.Hsl => "hsl",
            Space.Hwb => "hwb",
        }
    }

}

/// The legacy [`Space`] a color is already in — the fallback working space
/// when no channel keyword names one.
function own_space(c: root.value.Color) -> Space {
    match (c.modern?.space) {
        root.value.ColorSpace.Hsl => Space.Hsl,
        root.value.ColorSpace.Hwb => Space.Hwb,
        _ => Space.Rgb,
    }
}

/// A resolved channel argument: its keyword name and the supplied value.
type ChannelArg = root.std.Tuple2<string, root.value.Value>;

/// A channel keyword (`red`, `hue`, `alpha`, …) and the space(s) it belongs
/// to. `hue` is shared between HSL and HWB; `alpha` is universal.
function channel_space(name: string) -> root.std.Tuple2<Space?, bool>? {
    // (specific space, is_hue_shared)
    let r: root.std.Tuple2<Space?, bool> = match (name) {
        "red" | "green" | "blue" => root.std.Tuple2 { _0: Space.Rgb, _1: false },
        "saturation" | "lightness" => root.std.Tuple2 { _0: Space.Hsl, _1: false },
        "whiteness" | "blackness" => root.std.Tuple2 { _0: Space.Hwb, _1: false },
        "hue" => root.std.Tuple2 { _0: null, _1: true },
        "alpha" => {
            return root.std.Tuple2 { _0: null, _1: false };
        },
        _ => {
            return null;
        },
    };
    r
}

/// Collect the channel keyword arguments and resolve the operating space,
/// matching dart-sass's legacy detection: the first space-specific channel
/// fixes the space (hue-only defaults to HSL); any later channel not valid in
/// that space is an error.
function resolve_channels(
    unused_fname: string,
    c: root.value.Color,
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.std.Tuple2<Space, ChannelArg[]> {
    // The `$color` argument may be passed by name; it is not a channel.
    let chans: ChannelArg[] = named
        .filter((t) -> {
            t._0 != "color"
        })
        .map((t) -> {
            root.std.Tuple2 { _0: t._0, _1: t._1 }
        });
    // Determine the space from the first space-specific channel. If only the
    // shared `hue` channel is given, default to HSL; with no recognized
    // channel at all — a channel-less or alpha-only call, or an unknown
    // channel name — dart works in the COLOR'S OWN space. That is only
    // observable through a missing channel, which an unnecessary round trip
    // through rgb would fill in (`color.change(hsl(240 none 50%), $alpha: 0.5)`
    // is `hsl(240deg none 50% / 0.5)`, not `hsla(0, 0%, 50%, 0.5)`), and
    // through the unknown-channel error, which names that space.
    let space: Space? = null;
    let has_hue = false;
    for (let t in chans) {
        let n = t._0;
        // PORT: `match channel_space(n) { Some((Some(s), _)) => …, Some((None,
        // true)) => …, _ => {} }` → an `if` chain.
        let cs = channel_space(n);
        if (cs != null) {
            let s = cs._0;
            if (s != null) {
                space = s;
                break;
            } else if (cs._1) {
                has_hue = true;
            }
        }
    }
    let space: Space = space
        ?? (
            if (has_hue) {
                Space.Hsl
            } else {
                own_space(c)
            }
        );
    // Validate every channel belongs to the resolved space (alpha is allowed
    // everywhere; unknown channels error against the resolved space too).
    for (let t in chans) {
        let n = t._0;
        if (n == "alpha") {
            continue;
        }
        let cs = channel_space(n);
        let ok = if (cs == null) {
            false
        } else if (cs._0 != null) {
            cs._0 == space
        } else if (cs._1) {
            space != Space.Rgb // hue
        } else {
            false
        };
        if (!ok) {
            throw root.error.Error.at(
                `$${n}: Color space ${space.name()} doesn't have a channel with this name.`,
                pos,
            );
        }
    }
    root.std.Tuple2 { _0: space, _1: chans }
}

/// `adjust-color($color, channels…)` — add each amount to the matching
/// channel (rgb values 0–255, hsl/hwb percentages, hue degrees, alpha 0–1),
/// then clamp.
function fn_adjust_color(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["color"];
    let c = root.builtins.as_color(root.builtins.require(params, pos_args, named, 0, pos), pos);
    if (pos_args.length() > 1) {
        throw root.error.Error.at(
            "Only one positional argument is allowed. All other arguments must be passed by name.",
            pos,
        );
    }
    let r = modify_with_space(c, named, root.builtins.color.modern.ModifyOp.Adjust, pos);
    if (r != null) {
        return into_result(r);
    }
    // Legacy color with no $space: detect the legacy space from the channel
    // keywords, then run the modern adjust path (which clamps only rgb/[0,255]
    // and the perceptual lightness/chroma, leaving hsl/hwb percentages free).
    let resolved = resolve_channels("adjust-color", c, named, pos);
    let space = resolved._0;
    let chans = resolved._1;
    let cspace: root.value.ColorSpace = match (space) {
        Space.Rgb => root.value.ColorSpace.Rgb,
        Space.Hsl => root.value.ColorSpace.Hsl,
        Space.Hwb => root.value.ColorSpace.Hwb,
    };
    let chan_args: root.std.Tuple2<string, root.value.Value>[] = chans.map((t) -> {
        root.std.Tuple2 { _0: t._0, _1: t._1 }
    });
    root.builtins.color.modern.modify_in_space(
        c,
        cspace,
        chan_args,
        root.builtins.color.modern.ModifyOp.Adjust,
        pos,
    )
}

/// `change-color($color, channels…)` — set each channel to the given value
/// (alpha validated to `[0, 1]`).
function fn_change_color(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["color"];
    let c = root.builtins.as_color(root.builtins.require(params, pos_args, named, 0, pos), pos);
    if (pos_args.length() > 1) {
        throw root.error.Error.at(
            "Only one positional argument is allowed. All other arguments must be passed by name.",
            pos,
        );
    }
    let r = modify_with_space(c, named, root.builtins.color.modern.ModifyOp.Change, pos);
    if (r != null) {
        return into_result(r);
    }
    // Legacy color with no $space: detect the legacy space from the channel
    // keywords, then run the modern (non-clamping, `none`-aware) modify path so
    // out-of-range channels and missing channels match dart-sass.
    let resolved = resolve_channels("change-color", c, named, pos);
    let space = resolved._0;
    let chans = resolved._1;
    let cspace: root.value.ColorSpace = match (space) {
        Space.Rgb => root.value.ColorSpace.Rgb,
        Space.Hsl => root.value.ColorSpace.Hsl,
        Space.Hwb => root.value.ColorSpace.Hwb,
    };
    let chan_args: root.std.Tuple2<string, root.value.Value>[] = chans.map((t) -> {
        root.std.Tuple2 { _0: t._0, _1: t._1 }
    });
    root.builtins.color.modern.modify_in_space(
        c,
        cspace,
        chan_args,
        root.builtins.color.modern.ModifyOp.Change,
        pos,
    )
}

/// `scale-color($color, channels…)` — fluidly scale each channel a percentage
/// of the way toward its bound. Each amount must be a `%` within `[-100,
/// 100]`.
function fn_scale_color(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["color"];
    let c = root.builtins.as_color(root.builtins.require(params, pos_args, named, 0, pos), pos);
    if (pos_args.length() > 1) {
        throw root.error.Error.at(
            "Only one positional argument is allowed. All other arguments must be passed by name.",
            pos,
        );
    }
    let r = modify_with_space(c, named, root.builtins.color.modern.ModifyOp.Scale, pos);
    if (r != null) {
        return into_result(r);
    }
    let resolved = resolve_channels("scale-color", c, named, pos);
    let space = resolved._0;
    let chans = resolved._1;
    let cspace: root.value.ColorSpace = match (space) {
        Space.Rgb => root.value.ColorSpace.Rgb,
        Space.Hsl => root.value.ColorSpace.Hsl,
        Space.Hwb => root.value.ColorSpace.Hwb,
    };
    // A color with missing channels keeps them when only the alpha (or
    // nothing) is scaled — the byte-tuple decomposition below would collapse
    // `rgb(none none none)` to black (dart preserves the missing channels).
    {
        let mc = root.builtins.color.math.legacy_to_modern(c);
        if (
            mc.channels.some((ch) -> {
                ch == null
            })
                && chans.every((t) -> {
                    t._0 == "alpha"
                })
        ) {
            // PORT: `let mut out = mc;` — a shallow copy, since `legacy_to_modern`
            // may hand back the color's own `modern` (an alias in BAML).
            let out = root.value.ModernColor { ...mc };
            for (let t in chans) {
                let v = t._1;
                // `scale` combines the amount with the channel's current value,
                // so a MISSING alpha is unsupported here exactly as it is on the
                // common path — this shortcut must not read it as opaque.
                if (out.alpha == null) {
                    throw root.builtins.color.modern.missing_channel_err("alpha", root.value.Value_Color { _0: c }, pos);
                }
                let factor = scale_factor("alpha", v, pos);
                let a = out.alpha ?? 1.0;
                out.alpha = scale_toward(a, factor, 1.0);
            }
            let space = out.space;
            return root.value.Value_Color { _0: root.builtins.color.math.make_modern_in(out, space) };
        }
    };
    // Run the modern scale path (like adjust/change above): it operates on
    // the color's OWN stored channels — so an hwb color keeps its space and
    // its raw (un-normalized) whiteness/blackness, matching dart.
    let chan_args: root.std.Tuple2<string, root.value.Value>[] = chans.map((t) -> {
        root.std.Tuple2 { _0: t._0, _1: t._1 }
    });
    root.builtins.color.modern.modify_in_space(
        c,
        cspace,
        chan_args,
        root.builtins.color.modern.ModifyOp.Scale,
        pos,
    )
}

/// Scale `current` by `factor` (`-1..=1`) toward `max` (when positive) or `0`
/// (when negative).
function scale_toward(current: float, factor: float, max: float) -> float {
    if (factor > 0.0) {
        current + (max - current) * factor
    } else {
        current + current * factor
    }
}

/// Read a scale-color amount: a `%` within `[-100, 100]`, returned as a
/// fraction in `[-1, 1]`.
function scale_factor(name: string, v: root.value.Value, pos: root.scanner.Pos) -> float {
    match (v) {
        root.value.Value_Number { _0: let n } => {
            // A COMPOUND unit only reports its first numerator, so `%*px` must
            // be rejected explicitly rather than read as a percentage.
            if (n.has_complex_units() || n.unit() != "%") {
                throw root.error.Error.at(
                    `$${name}: Expected ${n.to_css(false)} to have unit "%".`,
                    pos,
                );
            }
            // A NaN is within no range, so it is rejected like any
            // out-of-range value rather than scaling the channel to nothing.
            if (n.value.is_nan() || n.value < -100.0 || n.value > 100.0) {
                throw root.error.Error.at(
                    `$${name}: Expected ${n.to_css(false)} to be within -100% and 100%.`,
                    pos,
                );
            }
            n.value / 100.0
        },
        let other => {
            throw root.error.Error.at(
            `$${name}: ${other.to_css(false)} is not a number.`,
            pos,
        )
        },
    }
}

// ---- PORT helpers (no Rust counterpart) -------------------------------

/// PORT: capture a `Result<Value, Error>` as a value — `Ok(f())`, or the
/// thrown `Error` as `Err` (Rust's `Some((|| { … })())` / `Some(f(…))` in the
/// `Option<Result<…>>` dispatchers).
function result_of(
    f: () -> root.value.Value throws unknown,
) -> root.std.Ok<root.value.Value> | root.std.Err<root.error.Error> {
    {
        root.std.Ok { value: f() }
    } catch (e) {
        let err: root.error.Error => root.std.Err { error: err }
    }
}

/// PORT: a `Result<Value, Error>` value handed back with `?` semantics —
/// `Ok(v)` → `v`, `Err(e)` → `throw e` (Rust: `return r;` from a `Result` fn).
function into_result(
    r: root.std.Ok<root.value.Value> | root.std.Err<root.error.Error>,
) -> root.value.Value {
    match (r) {
        let ok: root.std.Ok<root.value.Value> => ok.value,
        let err: root.std.Err<root.error.Error> => throw err.error,
    }
}

/// PORT: Rust's `f64::clamp`, which returns a NaN unchanged. (`root.std.fclamp`
/// maps NaN to `hi`, because BAML orders NaN above every number.)
function clamp_f64(x: float, lo: float, hi: float) -> float {
    if (x.is_nan()) {
        x
    } else {
        root.std.fclamp(x, lo, hi)
    }
}
