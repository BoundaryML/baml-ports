// Ported from sasso `src/builtins/color/mod.rs` (namespace `root.builtins.color`).
//
// Core color builtins: `rgb`/`rgba`/`hsl`/`hsla`/`mix`, the legacy
// `lighten`/`darken`, `percentage`, and the channel getters
// `red`/`green`/`blue`/`alpha`.
//
// Split into focused submodules around the `try_call` dispatch (below), the
// legacy color constructors ([`legacy`]), the modern `sass:color` module
// members ([`modern`]), and the shared color-space math ([`math`]). This is a
// pure organizational split: every `color::…` path external callers use is
// preserved via the re-exports at the bottom of this file.

// Core color builtins: `rgb`/`rgba`/`hsl`/`hsla`/`mix`, the legacy
// `lighten`/`darken`, `percentage`, and the channel getters
// `red`/`green`/`blue`/`alpha`.
//
// Split into focused submodules around the `try_call` dispatch (below), the
// legacy color constructors ([`legacy`]), the modern `sass:color` module
// members ([`modern`]), and the shared color-space math ([`math`]). This is a
// pure organizational split: every `color::…` path external callers use is
// preserved via the re-exports at the bottom of this file.
// mod deprecate → namespace `root.builtins.color.deprecate`

// mod legacy → namespace `root.builtins.color.legacy`

// mod math → namespace `root.builtins.color.math`

// mod modern → namespace `root.builtins.color.modern`

// mod removed → namespace `root.builtins.color.removed`

/// Whether a value is a "special" channel argument that cannot be evaluated
/// to a plain number — a `var()`/`env()`/`attr()` (an unquoted string holding
/// a CSS function) or a `calc()` (a [`Value::Calc`]). dart-sass does not error
/// on these; it preserves the whole color call verbatim, re-serialized from
/// the evaluated arguments.
function is_special(v: root.value.Value) -> bool {
    match (v) {
        root.value.Value_Calc {} => true,
        root.value.Value_Str { _0: let s } => !s.quoted && s.text.includes("("),
        _ => false,
    }
}

/// Whether a value is specifically a `var(...)` reference (an unquoted string
/// whose first CSS function is `var`, case-insensitively). dart's legacy
/// two-argument `rgb($color, $alpha)` / `hsl` overloads short-circuit to a
/// verbatim passthrough only for `var()` — not `env()`, `calc()`, or any other
/// special — so the color-type check is suppressed exactly when a `var()` is
/// present.
function is_var(v: root.value.Value) -> bool {
    match (v) {
        root.value.Value_Str { _0: let s } if !s.quoted => {
            let t = root.std.trim_start(s.text);
            t.length() >= 4 && root.std.eq_ignore_ascii_case(t.slice(0, 4), "var(")
        },
        _ => false,
    }
}

/// Like [`is_special`] but for the legacy `rgb`/`hsl` channels, where a
/// `calc()` that folds to a degenerate constant (`infinity`, `-infinity`,
/// `NaN`) is *not* special — dart-sass folds it to that floating point value
/// and computes/clamps the real channel rather than preserving the call.
function is_special_legacy(v: root.value.Value) -> bool {
    match (v) {
        root.value.Value_Calc { _0: let node } => degenerate_const(node) == null,
        let other => is_special(other),
    }
}

/// The floating-point value of a degenerate `calc()` constant
/// (`calc(infinity)`, `calc(-infinity)`, `calc(NaN)`), or `None` for any other
/// calculation. dart-sass folds these constants to the corresponding `f64`.
function degenerate_const(node: root.value.CalcNode) -> float? {
    if let s: root.value.CalcNode_Str = node {
        return match (root.std.ascii_lower(root.std.trim(s._0))) {
            "infinity" => root.std.F64_INFINITY(),
            "-infinity" => root.std.F64_NEG_INFINITY(),
            "nan" => root.std.F64_NAN(),
            _ => null,
        };
    }
    null
}

/// Whether a value is the `none` missing-channel keyword (an unquoted `none`).
function is_none_keyword(v: root.value.Value) -> bool {
    match (v) {
        root.value.Value_Str { _0: let s }
            if !s.quoted && root.std.eq_ignore_ascii_case(s.text, "none") => true,
        _ => false,
    }
}

/// Re-serialize a special-value color call: `name(arg1, arg2, …)`, each
/// argument via `to_css(false)`, comma-joined (the form dart-sass normalizes
/// every legacy `rgb()`/`hsl()` special-value call to).
function special_call(name: string, args: root.value.Value[]) -> root.value.Value {
    let parts: string[] = args.map((v) -> {
        v.to_css(false)
    });
    root.value.Value_Str {
        _0: root.value.SassStr { text: `${name}(${parts.join(", ")})`, quoted: false },
    }
}

/// Preserve a color call verbatim from a single channels value (space- or
/// slash-joined), matching dart-sass's "wrong channel count" passthrough
/// (`rgb(var(--foo) 2)` → `rgb(var(--foo) 2)`).
function verbatim_call(name: string, channels: root.value.Value) -> root.value.Value {
    root.value.Value_Str {
        _0: root.value.SassStr { text: `${name}(${channels.to_css(false)})`, quoted: false },
    }
}

/// The name of the channel at index `i` for a legacy color-function error
/// message: a named channel for the first three (`red channel`,
/// `hue channel`, …), or `channel <N>` (1-based) for any overflow position,
/// matching dart-sass.
function legacy_channel_name(names: string[], i: int) -> string {
    match (names.at(i)) {
        let name: string => `${name} channel`,
        _ => `channel ${i + 1}`,
    }
}

// The modern color-space member names live with their dispatch in `modern`;
// aliased here (a `const` alias, not a `use` re-export, to keep `modern::NAMES`
// `pub(super)`) so `is_builtin`'s family table can fold them into the color
// family without duplicating the list.
function MODERN_NAMES() -> string[] {
    root.builtins.color.modern.NAMES()
}

/// The core color names this module's `try_call` owns by name (the single
/// source of truth, mirroring the match arms below). The modern CSS Color 4
/// members `try_call` delegates to live in [`MODERN_NAMES`]; the family's full
/// name set is the union of the two (see `is_builtin`).
function NAMES() -> string[] {
    [
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
    ]
}

function try_call(
    name: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> (root.std.Ok<root.value.Value> | root.std.Err<root.error.Error>)? {
    // PORT: `Some(match name { … })` — each arm's `Result` is captured as an
    // `Ok`/`Err` value by `color_ext::result_of`.
    match (name) {
        "rgb" | "rgba" => {
            root.builtins.color_ext.result_of(() -> {
                root.builtins.color.legacy.fn_rgb(name, pos_args, named, pos)
            })
        },
        "hsl" | "hsla" => {
            root.builtins.color_ext.result_of(() -> {
                root.builtins.color.legacy.fn_hsl(name, pos_args, named, pos)
            })
        },
        "hwb" => {
            root.builtins.color_ext.result_of(() -> {
                root.builtins.color.legacy.fn_hwb(pos_args, named, pos)
            })
        },
        "lab" | "lch" | "oklab" | "oklch" => {
            root.builtins.color_ext.result_of(() -> {
                root.builtins.color.legacy.fn_lab_family(name, pos_args, named, pos)
            })
        },
        "color" => {
            root.builtins.color_ext.result_of(() -> {
                root.builtins.color.legacy.fn_color(pos_args, named, pos)
            })
        },
        "mix" => {
            root.builtins.color_ext.result_of(() -> {
                root.builtins.color.legacy.fn_mix(pos_args, named, pos)
            })
        },
        "lighten" => {
            root.builtins.color_ext.result_of(() -> {
                root.builtins.color.legacy.fn_adjust_lightness(name, pos_args, named, pos, 1.0)
            })
        },
        "darken" => {
            root.builtins.color_ext.result_of(() -> {
                root.builtins.color.legacy.fn_adjust_lightness(name, pos_args, named, pos, -1.0)
            })
        },
        "percentage" => {
            root.builtins.color_ext.result_of(() -> {
                root.builtins.color.legacy.fn_percentage(pos_args, named, pos)
            })
        },
        "red" | "green" | "blue" => {
            root.builtins.color_ext.result_of(() -> {
                root.builtins.color.legacy.fn_channel(name, pos_args, named, pos)
            })
        },
        "alpha" => {
            root.builtins.color_ext.result_of(() -> {
                root.builtins.color.legacy.fn_alpha(pos_args, named, pos)
            })
        },
        _ => root.builtins.color.modern.try_call_modern(name, pos_args, named, pos),
    }
}

/// Read an alpha argument: a `%` is divided by 100, a unitless number is used
/// directly, and the result is clamped to `[0, 1]`. NaN clamps to 0. Any
/// other unit is an error (`Expected … to have unit "%" or no units.`).
function alpha_value(v: root.value.Value, pos: root.scanner.Pos) -> float {
    let c = degenerate_value(v);
    if (c != null) {
        // A degenerate alpha is still an alpha: its UNIT is checked first, so
        // `calc(infinity * 1px)` is the wrong unit rather than an opaque
        // color. A `%` one divides like a literal percentage (which changes
        // nothing for a non-finite value, but keeps the two paths the same).
        let pct = match (channel_unit_number(v)) {
            let n: root.value.Number if !n.has_complex_units() && n.unit() == "%" => true,
            let n: root.value.Number if !n.is_unitless() => {
                throw root.error.Error.at(
                    `$alpha: Expected ${v.to_css(false)} to have unit "%" or no units.`,
                    pos,
                );
            },
            _ => false,
        };
        return clamp_alpha(
            if (pct) {
                c / 100.0
            } else {
                c
            },
        );
    }
    // PORT: `Value::Number(num) | Value::Slash(num, _) => { … }` — an or-pattern
    // cannot bind across variant classes, so both arms run `number_arm`.
    let number_arm = (num: root.value.Number) -> float {
        // A COMPOUND unit only reports its first numerator, so `%*px` is
        // not the percentage it starts with.
        let raw = if (!num.has_complex_units() && num.unit() == "%") {
            num.value / 100.0
        } else if (num.is_unitless()) {
            num.value
        } else {
            throw root.error.Error.at(
                `$alpha: Expected ${num.to_css(false)} to have unit "%" or no units.`,
                pos,
            );
        };
        clamp_alpha(raw)
    };
    match (v) {
        // One arm for both spellings: a slash-division's quotient carries its
        // unit like any number, so it cannot drift from the literal path. (No
        // input reaches here as a `Slash` today — a channels list's alpha is
        // split out as a plain token, and a division anywhere else has already
        // evaluated to a number — but the two must not diverge if one ever
        // does.)
        root.value.Value_Number { _0: let num } => number_arm(num),
        root.value.Value_Slash { _0: let num } => number_arm(num),
        let other => {
            throw root.error.Error.at(
            `$alpha: ${channel_err_css(other)} is not a number.`,
            pos,
        )
        },
    }
}

/// Clamp an alpha value to `[0, 1]`, mapping NaN — and a negative zero, which
/// `clamp` keeps — to 0 (matching dart-sass).
function clamp_alpha(v: float) -> float {
    if (v.is_nan()) {
        0.0
    } else {
        root.value.without_negative_zero(root.builtins.color_ext.clamp_f64(v, 0.0, 1.0))
    }
}

/// Whether a value is a `calc()` that folds to a degenerate constant
/// (`infinity`, `-infinity`, `NaN`).
function is_degenerate_calc(v: root.value.Value) -> bool {
    degenerate_value(v) != null
}

/// The non-finite value of a degenerate channel: a non-finite number (the
/// usual form, since a fully-folded `calc()` unwraps to a number), the
/// quotient a slash-division carries (`hsl(0/0 50% 50%)` — inside a
/// SPACE-separated channels list `0/0` keeps its spelling instead of
/// collapsing to a number), or a residual `calc()` constant.
function degenerate_value(v: root.value.Value) -> float? {
    match (v) {
        root.value.Value_Number { _0: let n } if !n.value.is_finite() => n.value,
        root.value.Value_Slash { _0: let n } if !n.value.is_finite() => n.value,
        root.value.Value_Calc { _0: let node } => match (node) {
            root.value.CalcNode_Number { _0: let n } if !n.value.is_finite() => n.value,
            _ => degenerate_const(node),
        },
        _ => null,
    }
}

/// The [`Number`] underlying a color channel for unit inspection and
/// normalization: a plain number, the quotient of a slash-division (`6px/2`,
/// whose unit decides the channel's), or a degenerate `calc()` that folded to
/// a unit-bearing number (`calc(infinity * 1px)`). Returns `None` for any
/// non-numeric channel (handled by the "is not a number" / passthrough paths).
function channel_unit_number(v: root.value.Value) -> root.value.Number? {
    match (v) {
        root.value.Value_Number { _0: let n } => n,
        root.value.Value_Slash { _0: let n } => n,
        root.value.Value_Calc { _0: root.value.CalcNode_Number { _0: let n } } => n,
        _ => null,
    }
}

/// dart-sass 1.104.0: "Colors now convert NaN and negative zero, as well as
/// infinity and negative infinity for polar-hue channels, to 0 as per the CSS
/// spec." This runs on the channel VALUE before anything else inspects it, so
/// a `NaN` channel stops being degenerate at all and the call parses into an
/// ordinary color. Only a surviving infinity is still degenerate and keeps its
/// `calc(...)` spelling (`hsl(0, calc(infinity * 1%), 50%)`).
///
/// A FINITE negative zero converts here too, rather than on the stored
/// channels: the degenerate path a surviving infinity takes serializes the
/// values it was handed instead of a built color, so `hsl(-0, calc(infinity),
/// 50%)` would otherwise write the sign back out.
function normalize_channel(v: root.value.Value, polar_hue: bool) -> root.value.Value {
    let num = channel_unit_number(v);
    let converts = match (degenerate_value(v)) {
        let c: float => c.is_nan() || (polar_hue && c.is_infinite()),
        _ => {
            if (num != null) {
                num.value == 0.0 && root.std.is_sign_negative(num.value)
            } else {
                false
            }
        },
    };
    if (!converts) {
        return v;
    }
    // The zero keeps the channel's UNIT, so the per-channel unit checks still
    // see what the caller wrote: `calc(NaN * 1%)` is a `%` whiteness, and
    // `calc(NaN * 1px)` is still the wrong unit.
    let zero = match (num) {
        let n: root.value.Number => n.copy_units(0.0),
        _ => root.value.Number.unitless(0.0),
    };
    root.value.Value_Number { _0: zero }
}

/// Apply [`normalize_channel`] to every component of a channel list, where
/// `polar_hue` is the index of the space's hue channel (if it has one).
function normalize_channels(comps: root.value.Value[], polar_hue: int?) -> root.value.Value[] {
    // PORT: `.iter().enumerate().map(…).collect()` → an index loop.
    let out: root.value.Value[] = [];
    let i = 0;
    for (let v in comps) {
        out.push(normalize_channel(v, polar_hue == i));
        i += 1;
    }
    out
}

/// dart validates the ALPHA's unit early — after the all-numeric channel pass
/// but before the channel COUNT and before the channels' own units — so a bad
/// alpha is what gets reported when the channels are wrong as well. Only the
/// unit is checked here; every other alpha error stays where it is.
function validate_alpha_unit(alpha: root.value.Value?, pos: root.scanner.Pos) -> void {
    if (alpha == null) {
        return;
    }
    let a = alpha;
    let n = channel_unit_number(a);
    if (n != null) {
        if (!n.is_unitless() && (n.has_complex_units() || n.unit() != "%")) {
            throw root.error.Error.at(
                `$alpha: Expected ${a.to_css(false)} to have unit "%" or no units.`,
                pos,
            );
        }
    }
}

/// Render a non-number CHANNEL for a "channel to be a number" diagnostic: an
/// unbracketed multi-item list is parenthesized (`(1 2)`, `(1, 2)`), matching
/// dart-sass; a bracketed one already carries its own delimiters, and every
/// other value prints plainly.
function channel_err_css(v: root.value.Value) -> string {
    match (v) {
        root.value.Value_List { _0: let l } if l.items.length() > 1 && !l.bracketed => {
            list_paren_css(v)
        },
        _ => v.to_css(false),
    }
}

/// Serialize a list value wrapped in parentheses, as dart-sass does in its
/// channel-list error messages (`(1%, 2, 3)`, `(1% 2)`).
function list_paren_css(v: root.value.Value) -> string {
    `(${v.to_css(false)})`
}
