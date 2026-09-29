// Ported from sasso `src/builtins/color/math.rs` (namespace `root.builtins.color.math`).

// =====================================================================
// CSS Color 4 color-space conversion engine.
//
// Channels are stored in each space's canonical units:
//   * rgb/srgb/srgb-linear/display-p3/a98-rgb/prophoto-rgb/rec2020:
//       red/green/blue in 0..=1 (the legacy `rgb` space additionally keeps a
//       0..=255 mirror in Color::{r,g,b}).
//   * hsl: hue deg, saturation/lightness in percent (0..=100).
//   * hwb: hue deg, whiteness/blackness in percent (0..=100).
//   * xyz / xyz-d50: x/y/z unbounded.
//   * lab: lightness 0..=100, a/b unbounded; lch: lightness 0..=100,
//       chroma >= 0, hue deg.
//   * oklab: lightness 0..=1, a/b unbounded; oklch: lightness 0..=1,
//       chroma >= 0, hue deg.
// A `None` channel is a missing channel; conversions treat it as 0.
// =====================================================================

// PORT: local helpers (not in the Rust). BAML orders a NaN float ABOVE every
// other float (`NaN > x` and `NaN >= x` are true, `x < NaN` is true), where
// Rust's IEEE comparisons are all false; and `root.std.fclamp` maps a NaN to
// `hi` where `f64::clamp` keeps it NaN. These give the Rust answers wherever a
// NaN can reach a `>`/`>=`/`clamp`.

/// PORT: Rust's IEEE `a > b` (false when either side is NaN).
function f_gt(a: float, b: float) -> bool {
    !a.is_nan() && !b.is_nan() && a > b
}

/// PORT: Rust's IEEE `a >= b` (false when either side is NaN).
function f_ge(a: float, b: float) -> bool {
    !a.is_nan() && !b.is_nan() && a >= b
}

/// PORT: Rust's `f64::clamp` (a NaN stays NaN).
function f_clamp(x: float, lo: float, hi: float) -> float {
    if (x.is_nan()) {
        x
    } else {
        root.std.fclamp(x, lo, hi)
    }
}

/// PORT: `ModernColor::clone()` — a copy whose channel array is not shared
/// with the original (a Rust `[Option<f64>; 3]` is copied by value).
function clone_mc(mc: root.value.ModernColor) -> root.value.ModernColor {
    root.value.ModernColor {
        space: mc.space,
        channels: root.std.clone_vec(mc.channels),
        alpha: mc.alpha,
    }
}

/// Replace a missing (`None`) channel with `0.0` for arithmetic.
function z(v: float?) -> float {
    v ?? 0.0
}

/// The CSS Color 4 "analogous component" category of a channel, used to carry
/// a missing channel through a color-space conversion. `None` for channels that
/// are never analogous to a differently-named channel.
enum ChannelCategory {
    Red,
    Green,
    Blue,
    Lightness,
    Colorfulness,
    // saturation / chroma
    Hue,
    LabA,
    LabB,
    Whiteness,
    Blackness,
}

function channel_category(space: root.value.ColorSpace, idx: int) -> ChannelCategory? {
    // PORT: `use ChannelCategory::*; use ColorSpace::*;` spelled out; the
    // `(space, idx)` tuple match is a match on `space` with an `idx` guard
    // (an or-pattern mixing indices is split into one arm per index).
    let cat: ChannelCategory = match (space) {
        root.value.ColorSpace.Rgb
            | root.value.ColorSpace.Srgb
            | root.value.ColorSpace.SrgbLinear
            | root.value.ColorSpace.DisplayP3
            | root.value.ColorSpace.DisplayP3Linear
            | root.value.ColorSpace.A98Rgb
            | root.value.ColorSpace.ProphotoRgb
            | root.value.ColorSpace.Rec2020
            if idx == 0 =>
        {
            ChannelCategory.Red
        },
        root.value.ColorSpace.Rgb
            | root.value.ColorSpace.Srgb
            | root.value.ColorSpace.SrgbLinear
            | root.value.ColorSpace.DisplayP3
            | root.value.ColorSpace.DisplayP3Linear
            | root.value.ColorSpace.A98Rgb
            | root.value.ColorSpace.ProphotoRgb
            | root.value.ColorSpace.Rec2020
            if idx == 1 =>
        {
            ChannelCategory.Green
        },
        root.value.ColorSpace.Rgb
            | root.value.ColorSpace.Srgb
            | root.value.ColorSpace.SrgbLinear
            | root.value.ColorSpace.DisplayP3
            | root.value.ColorSpace.DisplayP3Linear
            | root.value.ColorSpace.A98Rgb
            | root.value.ColorSpace.ProphotoRgb
            | root.value.ColorSpace.Rec2020
            if idx == 2 =>
        {
            ChannelCategory.Blue
        },
        root.value.ColorSpace.Hsl | root.value.ColorSpace.Hwb if idx == 0 => ChannelCategory.Hue,
        root.value.ColorSpace.Lch | root.value.ColorSpace.Oklch if idx == 2 => ChannelCategory.Hue,
        root.value.ColorSpace.Hsl | root.value.ColorSpace.Lch | root.value.ColorSpace.Oklch
            if idx == 1 => ChannelCategory.Colorfulness,
        root.value.ColorSpace.Hsl if idx == 2 => ChannelCategory.Lightness,
        root.value.ColorSpace.Lab
            | root.value.ColorSpace.Lch
            | root.value.ColorSpace.Oklab
            | root.value.ColorSpace.Oklch
            if idx == 0 =>
        {
            ChannelCategory.Lightness
        },
        root.value.ColorSpace.Hwb if idx == 1 => ChannelCategory.Whiteness,
        root.value.ColorSpace.Hwb if idx == 2 => ChannelCategory.Blackness,
        root.value.ColorSpace.Lab | root.value.ColorSpace.Oklab if idx == 1 => ChannelCategory.LabA,
        root.value.ColorSpace.Lab | root.value.ColorSpace.Oklab if idx == 2 => ChannelCategory.LabB,
        // CSS Color 4 groups the xyz channels with the analogous rgb channels
        // for missing-component carry (Reds: r/x, Greens: g/y, Blues: b/z).
        root.value.ColorSpace.XyzD65 | root.value.ColorSpace.XyzD50 if idx == 0 => {
            ChannelCategory.Red
        },
        root.value.ColorSpace.XyzD65 | root.value.ColorSpace.XyzD50 if idx == 1 => {
            ChannelCategory.Green
        },
        root.value.ColorSpace.XyzD65 | root.value.ColorSpace.XyzD50 if idx == 2 => {
            ChannelCategory.Blue
        },
        _ => {
            return null;
        },
    };
    cat
}

/// Convert a [`ModernColor`] to a new space, preserving alpha and carrying
/// over missing channels into analogous channels of the target (CSS Color 4).
function convert_modern(
    mc: root.value.ModernColor,
    target: root.value.ColorSpace,
) -> root.value.ModernColor {
    if (mc.space == target) {
        return clone_mc(mc);
    }
    let src = [z(mc.channels[0]), z(mc.channels[1]), z(mc.channels[2])];
    // dart-sass's exact conversion graph: one precomputed matrix between
    // linear spaces, glibc-rounded `pow`, and dart's formula shapes — see
    // `builtins::colorspace`.
    let out = root.builtins.colorspace.convert(mc.space, target, src);
    // For each output channel, become missing if the analogous source channel
    // was missing.
    let missing_in_src = (cat: ChannelCategory) -> bool {
        root.std.range(0, 3).some((i) -> {
            mc.channels[i] == null && channel_category(mc.space, i) == cat
        })
    };
    let mk = (i: int) -> float? {
        match (channel_category(target, i)) {
            let cat: ChannelCategory if missing_in_src(cat) => null,
            _ => out[i],
        }
    };
    let channels: (float?)[] = [mk(0), mk(1), mk(2)];
    // A hue that is powerless in the result becomes a missing channel,
    // matching dart-sass's conversion behavior: lch/oklch at zero chroma, hsl
    // at fuzzy-zero saturation, and hwb when whiteness+blackness covers
    // everything. (The legacy result fill then turns a missing hsl/hwb hue
    // into 0.)
    // Each of these is dart's `fuzzyEquals(channel, 0)`, with the 1e11 rounding
    // clause that makes 6e-12 NOT zero. `[measured]` against dart-sass 1.104.1:
    // `color.is-missing(color.to-space(lab(50% 0.000000000006 0), lch), "hue")`
    // is false.
    let fz = root.value.fuzzy_eq;
    if (
        (target == root.value.ColorSpace.Lch || target == root.value.ColorSpace.Oklch)
            && fz(out[1], 0.0)
    ) {
        channels[2] = null;
    }
    // dart's lch → lab conversion marks a/b POWERLESS when the lightness is
    // missing or fuzzy-zero (LabColorSpace.convert dest=lab: `powerlessAB =
    // lightness == null || fuzzyEquals(lightness, 0)`). Oklab has NO such
    // rule (`oklch(none 20% 30deg)` keeps its computed a/b), and a same-space
    // conversion is an identity shortcut that never reaches here.
    let lch_to_lab = mc.space == root.value.ColorSpace.Lch && target == root.value.ColorSpace.Lab;
    if (lch_to_lab && (channels[0] == null || fz(out[0], 0.0))) {
        channels[1] = null;
        channels[2] = null;
    }
    if (target == root.value.ColorSpace.Hsl && fz(out[1], 0.0)) {
        channels[0] = null;
    }
    if (target == root.value.ColorSpace.Hwb) {
        let sum = out[1] + out[2];
        if (f_gt(sum, 100.0) || fz(sum, 100.0)) {
            channels[0] = null;
        }
    }
    root.value.ModernColor { space: target, channels: channels, alpha: mc.alpha }
}

/// [`convert_modern`] for a conversion that produces a user-facing RESULT
/// color: a LEGACY result zero-fills its propagated missing channels and a
/// missing alpha (dart-sass `toSpace`'s default `legacyMissing: true`), so
/// `to-space(lab-with-missing, hsl)` and the result leg of `scale`/`adjust`/
/// `change`/`mix`/`to-gamut` with a legacy space emit the plain comma form
/// (`color.scale(hsl(none 50% 50%), $space: hwb)` -> `hsl(0, 50%, 50%)`).
/// INTERMEDIATE conversions (a `$method`/`$space` working leg feeding further
/// computation, e.g. `complement`'s hue rotation or `mix`'s interpolation
/// inputs) keep using raw [`convert_modern`] so missing-ness survives the
/// round trip. Same-space conversion stays the identity in both.
function convert_modern_filled(
    mc: root.value.ModernColor,
    target: root.value.ColorSpace,
) -> root.value.ModernColor {
    let out = convert_modern(mc, target);
    // Same-space is the identity in dart too, and keeps every missing channel.
    if (mc.space == target) {
        return out;
    }
    // A REAL conversion resolves a missing ALPHA to 0 whatever the target —
    // `color.is-missing(color.to-space(oklch(50% 0.1 20deg / none), oklab),
    // "alpha")` is false in dart — where the CHANNELS are only zero-filled for
    // a legacy target.
    let alpha: float? = out.alpha ?? 0.0;
    if (!target.is_legacy()) {
        return root.value.ModernColor { ...out, alpha: alpha };
    }
    root.value.ModernColor {
        space: target,
        channels: [out.channels[0] ?? 0.0, out.channels[1] ?? 0.0, out.channels[2] ?? 0.0],
        alpha: alpha,
    }
}

/// The color's alpha the way dart's `SassColor.alpha` getter answers it: a
/// MISSING alpha reads as **0**, like any other missing channel.
///
/// [`Color::a`] cannot stand in for this. It mirrors a missing alpha as the
/// opaque `1.0` that *serialization* falls back to, so reading it makes
/// `color.alpha(hsl(240 100% 50% / none))` answer 1 where dart answers 0, and
/// carries that 1 into every arithmetic built on top of it.
function stored_alpha(c: root.value.Color) -> float {
    match (c.modern) {
        let m: root.value.ModernColor => m.alpha ?? 0.0,
        null => c.a,
    }
}

/// Build a [`ModernColor`] from a legacy [`Color`] (its current space is
/// `rgb`/`hsl`/`hwb` per `mc.modern`, or plain sRGB → `rgb`).
function legacy_to_modern(c: root.value.Color) -> root.value.ModernColor {
    if let m: root.value.ModernColor = c.modern {
        return clone_mc(m);
    }
    root.value.ModernColor {
        space: root.value.ColorSpace.Rgb,
        channels: [c.r, c.g, c.b],
        alpha: c.a,
    }
}

/// Wrap a [`ModernColor`] in a [`Color`], deriving an in-gamut sRGB-byte
/// approximation for the legacy `r`/`g`/`b`/`a` fields (so legacy code paths
/// that read them keep working). The modern representation drives
/// serialization and channel access.
function make_modern(mc: root.value.ModernColor) -> root.value.Color {
    let mc = normalize_polar(mc);
    let srgb = convert_modern(mc, root.value.ColorSpace.Rgb);
    let c = root.value.Color.rgb(
        f_clamp(z(srgb.channels[0]), 0.0, 255.0),
        f_clamp(z(srgb.channels[1]), 0.0, 255.0),
        f_clamp(z(srgb.channels[2]), 0.0, 255.0),
        mc.alpha ?? 1.0,
    );
    c.modern = mc;
    c
}

/// dart `SassColor._normalizeHue`: `(hue % 360 + 360 + (invert ? 180 : 0))
/// % 360`. The EXACT fmod sequence matters bit-for-bit — adding 360 and
/// reducing again perturbs the last ulp vs a single euclidean remainder, and
/// sass-spec expectations carry that perturbation.
///
/// dart pattern-matches `0` and any non-finite hue BEFORE the invert shift,
/// which is not the same as shifting and reducing: a 0 hue stays 0 even when a
/// negative saturation asks for the 180° offset. `[measured]` against dart-sass
/// 1.104.1: `color.change(hsl(120, 50%, 50%), $hue: 0, $saturation: -50%)` is
/// `hsl(0, 50%, 50%)`, and `color.change(lch(50% 20 0), $chroma: -20)` keeps
/// `0deg`.
function normalize_hue(hue: float, invert: bool) -> float {
    if (hue == 0.0 || !hue.is_finite()) {
        return 0.0;
    }
    let shift = if (invert) {
        180.0
    } else {
        0.0
    };
    (hue % 360.0 + 360.0 + shift) % 360.0
}

/// Normalize a polar color's stored channels exactly like dart's
/// `SassColor.forSpaceInternal`: hsl and lch/oklch take the ABSOLUTE
/// saturation/chroma, inverting the hue by 180° when it was negative beyond
/// fuzz; every legacy/polar hue reduces through [`normalize_hue`]'s fmod
/// sequence. Other spaces are returned unchanged.
function normalize_polar(mc: root.value.ModernColor) -> root.value.ModernColor {
    // PORT: Rust takes `mc` by value (`mut mc`); work on a copy so the
    // caller's color (and its channel array) is never mutated in place.
    let mc = clone_mc(mc);
    // dart `fuzzyLessThan(channel1, 0)`: below zero and not `fuzzyEquals` to
    // it, with both clauses of that comparison — a saturation of -6e-12 is NOT
    // zero to dart (scaling by 1e11 rounds to -1), so it inverts the hue.
    let fuzzy_less_than_zero = (v: float) -> bool {
        v < 0.0 && !root.value.fuzzy_eq(v, 0.0)
    };
    let idxs: root.std.Tuple2<int, int?> = match (mc.space) {
        root.value.ColorSpace.Hsl => root.std.Tuple2 { _0: 0, _1: 1 },
        root.value.ColorSpace.Hwb => root.std.Tuple2 { _0: 0, _1: null },
        root.value.ColorSpace.Lch | root.value.ColorSpace.Oklch => root.std.Tuple2 { _0: 2, _1: 1 },
        _ => {
            return normalize_degenerate(mc);
        },
    };
    let hue_idx = idxs._0;
    let mag_idx = idxs._1;
    let invert = false;
    if (mag_idx != null) {
        let i = mag_idx;
        let c = mc.channels[i];
        if (c != null) {
            invert = fuzzy_less_than_zero(c);
            mc.channels[i] = c.abs();
        }
    }
    let h = mc.channels[hue_idx];
    if (h != null) {
        // No finite guard here: dart's fmod sends an infinite hue to NaN, which
        // `normalize_degenerate` then turns into 0 — the same 0 the CSS spec
        // asks for.
        mc.channels[hue_idx] = normalize_hue(h, invert);
    }
    normalize_degenerate(mc)
}

/// dart-sass 1.104.0: "Colors now convert NaN and negative zero, as well as
/// infinity and negative infinity for polar-hue channels, to 0 as per the CSS
/// spec." Applied to the STORED channels, so a NaN a conversion produced (not
/// just one the call spelled out) converts too. An infinite NON-hue channel is
/// left alone: it still serializes as `calc(infinity * 1%)`.
function normalize_degenerate(mc: root.value.ModernColor) -> root.value.ModernColor {
    // PORT: Rust takes `mc` by value (`mut mc`); work on a copy so the
    // caller's color (and its channel array) is never mutated in place.
    let mc = clone_mc(mc);
    let hue_idx: int? = match (mc.space) {
        root.value.ColorSpace.Hsl | root.value.ColorSpace.Hwb => 0,
        root.value.ColorSpace.Lch | root.value.ColorSpace.Oklch => 2,
        _ => null,
    };
    // PORT: `iter_mut().enumerate()` → an index loop writing back through
    // `mc.channels[i]`.
    for (let i in baml.iter.Range.new(0, mc.channels.length())) {
        let v = mc.channels[i];
        if (v != null) {
            if (v.is_nan() || v == 0.0 || (hue_idx == i && v.is_infinite())) {
                mc.channels[i] = 0.0;
            }
        }
    }
    // The alpha is a channel as well, and it reaches here from a COMPUTATION
    // as readily as from a call: `change`/`adjust`/`scale` write `work.alpha`
    // directly, so `color.change(oklch(50% 0.1 20deg), $alpha: -0)` is
    // `… / 0`, not `… / -0`.
    let a = mc.alpha;
    if (a != null) {
        if (a.is_nan() || a == 0.0) {
            mc.alpha = 0.0;
        }
    }
    mc
}

/// The known predefined `color()` spaces and their [`ColorSpace`].
function predefined_space(name: string) -> root.value.ColorSpace? {
    match (name) {
        "srgb" => root.value.ColorSpace.Srgb,
        "srgb-linear" => root.value.ColorSpace.SrgbLinear,
        "display-p3" => root.value.ColorSpace.DisplayP3,
        "display-p3-linear" => root.value.ColorSpace.DisplayP3Linear,
        "a98-rgb" => root.value.ColorSpace.A98Rgb,
        "prophoto-rgb" => root.value.ColorSpace.ProphotoRgb,
        "rec2020" => root.value.ColorSpace.Rec2020,
        "xyz" | "xyz-d65" => root.value.ColorSpace.XyzD65,
        "xyz-d50" => root.value.ColorSpace.XyzD50,
        _ => null,
    }
}

/// Parse a numeric channel value for a modern `color()`/lab-family call into a
/// canonical channel value, or `None` for a `none` channel. `pct_base` scales a
/// `%` value (e.g. 1.0 for rgb channels in 0..1, 100.0 for lab lightness).
/// Degenerate calc constants fold to infinity/NaN. The result is NOT clamped.
function modern_channel(v: root.value.Value, pct_base: float) -> float? {
    if (root.builtins.color.is_none_keyword(v)) {
        return null;
    }
    if let root.value.Value_Calc { _0: let node } = v {
        let c = root.builtins.color.degenerate_const(node);
        if (c != null) {
            return c;
        }
    }
    // A slash-division carries its quotient AND its unit, so `50%/2` is 25% of
    // the channel's base — not the raw 25 — and a FOLDED numeric `calc()`,
    // which only survives where the evaluator preserves calculations (inside
    // `@supports`), is a number like any other.
    match (root.builtins.color.channel_unit_number(v)) {
        let num: root.value.Number => {
            if (num.unit() == "%") {
                // dart's `_percentageOrUnitless` is `max * value / 100`, and
                // the order is observable: `0.4 * -40 / 100` is exactly -0.16
                // where `-40 / 100 * 0.4` is -0.16000000000000003, which the
                // compressed number writer rounds -- and, rounding, drops the
                // leading zero dart keeps.
                pct_base * num.value / 100.0
            } else {
                num.value
            }
        },
        null => 0.0,
    }
}

/// Parse a hue channel (degrees), converting angle units. `none` → `None`.
function modern_hue(v: root.value.Value) -> float? {
    if (root.builtins.color.is_none_keyword(v)) {
        return null;
    }
    if let root.value.Value_Calc { _0: let node } = v {
        let c = root.builtins.color.degenerate_const(node);
        if (c != null) {
            return c;
        }
    }
    // A slash-division carries its angle unit too (`1turn/4` is 90deg), as does
    // a folded numeric `calc()` preserved inside `@supports`.
    match (root.builtins.color.channel_unit_number(v)) {
        let num: root.value.Number => match (num.unit()) {
            // PORT: Rust's `f64::to_degrees` via `root.builtins.math.f64_to_degrees`
            // (BAML's `Float.to_degrees` can differ in the last bit).
            "rad" => root.builtins.math.f64_to_degrees(num.value),
            "grad" => num.value * 360.0 / 400.0,
            "turn" => num.value * 360.0,
            _ => num.value,
        },
        null => 0.0,
    }
}

/// Parse a modern alpha channel. `none` → `None`; otherwise clamp to 0..1.
function modern_alpha(v: root.value.Value?) -> float? {
    match (v) {
        null => 1.0,
        let a: root.value.Value if root.builtins.color.is_none_keyword(a) => null,
        let a: root.value.Value => {
            let c = root.builtins.color.degenerate_value(a);
            if (c != null) {
                return if (c.is_nan()) {
                    0.0
                } else {
                    f_clamp(c, 0.0, 1.0)
                };
            }
            match (a) {
                root.value.Value_Number { _0: let num } => {
                    let val = if (num.unit() == "%") {
                        num.value / 100.0
                    } else {
                        num.value
                    };
                    f_clamp(val, 0.0, 1.0)
                },
                root.value.Value_Slash { _0: let num } => f_clamp(num.value, 0.0, 1.0),
                _ => 1.0,
            }
        },
    }
}

// =====================================================================
// Modern `sass:color` module members (color.space / color.channel /
// color.to-space / color.is-legacy / color.is-missing / color.is-in-gamut /
// color.is-powerless / color.to-gamut / color.same). These are dispatched
// from the module seam under the global names `color-space`, `color-channel`,
// etc.
// =====================================================================
/// The space of a [`Color`] as a [`ColorSpace`] (`rgb` for plain legacy).
function color_space_of(c: root.value.Color) -> root.value.ColorSpace {
    c.modern?.space ?? root.value.ColorSpace.Rgb
}

/// Look up a channel name within `space`, returning its index (and the special
/// `"alpha"`/missing handling left to the caller).
function channel_index_in(space: root.value.ColorSpace, channel: string) -> int? {
    space.channel_names().find_index((n) -> {
        n == channel
    })
}

/// Parse a `$space` argument into a [`ColorSpace`]. dart-sass requires an
/// *unquoted* string: a quoted one errors "Expected … to be an unquoted
/// string".
function space_arg(v: root.value.Value, pos: root.scanner.Pos) -> root.value.ColorSpace {
    let name = match (v) {
        root.value.Value_Str { _0: let s } if !s.quoted => s.text,
        root.value.Value_Str { _0: let s } => {
            throw root.error.Error.at(
                `$space: Expected "${s.text}" to be an unquoted string.`,
                pos,
            );
        },
        let other => {
            throw root.error.Error.at(
                `$space: ${other.to_css(false)} is not a string.`,
                pos,
            );
        },
    };
    let space = root.value.ColorSpace_from_name(name);
    if (space == null) {
        throw root.error.Error.at(`$space: Unknown color space "${name}".`, pos);
    }
    space
}

/// Build a [`Color`] for `mc` already in `space`, choosing whether to leave the
/// `modern` tag attached. Plain-legacy rgb (no missing channels) drops the
/// `modern` field so it serializes like a normal sRGB color.
function make_modern_in(
    mc: root.value.ModernColor,
    unused_space: root.value.ColorSpace,
) -> root.value.Color {
    let mc = normalize_degenerate(mc);
    if (
        mc.space == root.value.ColorSpace.Rgb
            && mc.channels.every((c) -> {
                c != null
            })
            && mc.alpha != null
    ) {
        let r = mc.channels[0] ?? 0.0;
        let g = mc.channels[1] ?? 0.0;
        let b = mc.channels[2] ?? 0.0;
        let a = mc.alpha ?? 1.0;
        let c = root.value.Color.rgb(r, g, b, a);
        // Out-of-gamut legacy rgb serializes via hsl; attach modern so the
        // serializer can apply that rule. Otherwise a computed in-gamut rgb
        // uses its CSS named-color spelling when it matches one.
        //
        // The bound is dart's `_isChannelInGamut`, fuzzily — a channel 6e-12
        // past 255 is out of gamut to dart, and a looser tolerance here decides
        // the form before the serializer's own exact rules ever run.
        // `[measured]`: `color.change(red, $red: 255.000000000006)` is
        // `hsl(0, 100%, 50%)`, not `red`.
        let in_gamut = (v: float) -> bool {
            let fz = root.value.fuzzy_eq;
            (f_gt(v, 0.0) || fz(v, 0.0)) && (v < 255.0 || fz(v, 255.0))
        };
        if (!(in_gamut(r) && in_gamut(g) && in_gamut(b))) {
            c.modern = mc;
        } else {
            c.repr = root.builtins.color_ext.named_repr(r, g, b, a);
        }
        return c;
    }
    make_modern(mc)
}

/// The legacy hsl-space adjusters — `lighten`/`darken`, `saturate`/
/// `desaturate` and `adjust-hue` — the way dart-sass runs them: READ the
/// color's hsl channels (a missing channel reads as 0), let `f` change them,
/// rebuild an hsl color from those plain numbers, and hand it back in the
/// color's OWN space.
///
/// Keeping the space is what makes `lighten(hsl(240, 100%, 50%), 10%)` stay
/// `hsl(240, 100%, 60%)` instead of collapsing to `#3333ff`, and it keeps the
/// untouched channels bit-exact for an `hsl()` input — the trip to hsl and
/// back is the identity there, so `lighten(hsl(240, 150%, 50%), 10%)` is
/// `hsl(240, 150%, 60%)`, out of gamut and all. An `hwb()` input stays `hwb`
/// and the trip back applies the ordinary conversion rules, so a result whose
/// whiteness and blackness cover everything picks up a powerless `none` hue
/// (`lighten(hwb(240 90% 0%), 50%)` is `hwb(none 100% 0%)`). Only an
/// `rgb()`/hex/named input still collapses to sRGB, which is where it started.
///
/// Rebuilding from plain numbers is also why a MISSING channel does not
/// survive: `lighten(hsl(240 none 50%), 10%)` is `hsl(240, 0%, 60%)`, where
/// `color.adjust($lightness: 10%)` on the same color keeps the `none`.
function legacy_hsl_adjust(
    c: root.value.Color,
    f: (float[]) -> void throws unknown,
) -> root.value.Color {
    let src = legacy_to_modern(c);
    let space = src.space;
    let hsl = convert_modern(src, root.value.ColorSpace.Hsl);
    let ch = [z(hsl.channels[0]), z(hsl.channels[1]), z(hsl.channels[2])];
    f(ch);
    // Rebuilding the hsl color normalizes it the way dart's `SassColor.hsl`
    // constructor does, BEFORE the trip back: a non-finite hue becomes 0 there
    // (so `adjust-hue(red, NaN)` is red, not a color of NaN channels), where
    // converting first would hand the rgb arithmetic a hue it has no answer
    // for.
    let adjusted = normalize_polar(
        root.value.ModernColor {
            space: root.value.ColorSpace.Hsl,
            channels: [ch[0], ch[1], ch[2]],
            alpha: z(src.alpha),
        },
    );
    make_modern_in(convert_modern(adjusted, space), space)
}

/// The alpha-only legacy adjusters (`opacify`/`fade-in` and
/// `transparentize`/`fade-out`): dart rebuilds the color in its own space from
/// its own channels, so the space and every channel survive untouched
/// (`transparentize(hsl(240, 100%, 50%), 0.2)` is `hsla(240, 100%, 50%, 0.8)`)
/// and only a missing channel is filled in with 0.
///
/// `f` is handed the STORED alpha, a missing one reading as 0 like any other
/// missing channel — not the 1.0 that `Color::a` mirrors it as for
/// serialization. That is the alpha dart shifts, so
/// `opacify(hsl(240 100% 50% / none), 0.2)` is `hsla(240, 100%, 50%, 0.2)`
/// and `transparentize` of the same color stays at 0.
function legacy_alpha_adjust(
    c: root.value.Color,
    f: (float) -> float throws unknown,
) -> root.value.Color {
    let src = legacy_to_modern(c);
    let space = src.space;
    let mc = root.value.ModernColor {
        space: space,
        channels: [z(src.channels[0]), z(src.channels[1]), z(src.channels[2])],
        alpha: f(z(src.alpha)),
    };
    make_modern_in(mc, space)
}

/// Convert `mc` to `space`, carrying over the hue of a polar source when the
/// chroma/saturation is zero (powerless), matching dart-sass's missing-channel
/// behavior is not applied here — only the plain numeric conversion.
function convert_to_space(
    mc: root.value.ModernColor,
    space: root.value.ColorSpace,
) -> root.value.ModernColor {
    convert_modern_filled(mc, space)
}

/// Build the [`Number`] for a channel value, applying dart-sass's per-channel
/// unit: percentage for lightness/saturation/lightness/whiteness/blackness,
/// `deg` for hue, plain otherwise. Legacy rgb red/green/blue are 0..255.
function channel_number(space: root.value.ColorSpace, idx: int, raw: float) -> root.value.Number {
    // PORT: `use ColorSpace::*;` spelled out.
    let names = space.channel_names();
    let cname = names[idx];
    // dart's channel() builds a `%` number via `value * 100 / channel.max` —
    // the round trip perturbs the last ulp on far-range values, and the spec
    // expectations carry it (a max of 100 is NOT a no-op in floating point).
    let pct = (v: float, max: float) -> root.value.Number {
        root.value.Number.with_unit(v * 100.0 / max, "%")
    };
    let deg = (v: float) -> root.value.Number {
        root.value.Number.with_unit(v, "deg")
    };
    let plain = (v: float) -> root.value.Number {
        root.value.Number.unitless(v)
    };
    // PORT: the `(space, cname)` tuple match is a match on `space` with a
    // `cname` guard.
    match (space) {
        root.value.ColorSpace.Hsl if cname == "saturation" || cname == "lightness" => {
            pct(raw, 100.0)
        },
        root.value.ColorSpace.Hwb if cname == "whiteness" || cname == "blackness" => pct(raw, 100.0),
        root.value.ColorSpace.Lab | root.value.ColorSpace.Lch if cname == "lightness" => {
            pct(raw, 100.0)
        },
        root.value.ColorSpace.Oklab | root.value.ColorSpace.Oklch if cname == "lightness" => {
            pct(raw, 1.0)
        },
        _ if cname == "hue" => deg(raw),
        _ => plain(raw),
    }
}

/// Whether `mc` is within the gamut of `space`. The bounded RGB-style spaces
/// check their own channels; the legacy hsl/hwb spaces share the sRGB gamut
/// (their rgb representation must fit `[0,255]`); the unbounded perceptual/xyz
/// spaces are always in gamut.
/// Per-channel gamut bounds of a BOUNDED space's own channels (dart's
/// `LinearChannel` min/max); `None` entry = an unbounded (polar hue) channel,
/// outer `None` = an unbounded space (always in gamut).
function channel_bounds(space: root.value.ColorSpace) -> (root.std.Tuple2<float, float>?)[]? {
    // PORT: `use ColorSpace::*;` spelled out.
    let bounds: (root.std.Tuple2<float, float>?)[] = match (space) {
        root.value.ColorSpace.Rgb => baml.Array.filled(3, root.std.Tuple2 { _0: 0.0, _1: 255.0 }),
        root.value.ColorSpace.Srgb
            | root.value.ColorSpace.SrgbLinear
            | root.value.ColorSpace.DisplayP3
            | root.value.ColorSpace.DisplayP3Linear
            | root.value.ColorSpace.A98Rgb
            | root.value.ColorSpace.ProphotoRgb
            | root.value.ColorSpace.Rec2020 =>
        {
            baml.Array.filled(3, root.std.Tuple2 { _0: 0.0, _1: 1.0 })
        },
        root.value.ColorSpace.Hsl | root.value.ColorSpace.Hwb => {
            [null, root.std.Tuple2 { _0: 0.0, _1: 100.0 }, root.std.Tuple2 { _0: 0.0, _1: 100.0 }]
        },
        _ => {
            return null;
        },
    };
    bounds
}

/// dart `SassColor.isInGamut`: a bounded space checks each channel (missing
/// reads as 0) against its own bounds with fuzzy (1e-11) edges; unbounded
/// spaces and polar hue channels are always in gamut.
function is_in_gamut(mc: root.value.ModernColor) -> bool {
    let bounds = channel_bounds(mc.space);
    if (bounds == null) {
        return true;
    }
    let fuzzy_eq = (a: float, b: float) -> bool {
        (a - b).abs() < 1e-11
    };
    // PORT: `bounds.iter().zip(&mc.channels)` → an index loop.
    let i = 0;
    while (i < bounds.length() && i < mc.channels.length()) {
        let bound = bounds[i];
        let channel = mc.channels[i];
        if (bound != null) {
            let min = bound._0;
            let max = bound._1;
            let v = channel ?? 0.0;
            let ok = (v < max || fuzzy_eq(v, max)) && (f_gt(v, min) || fuzzy_eq(v, min));
            if (!ok) {
                return false;
            }
        }
        i += 1;
    }
    true
}

/// dart `ClipGamutMap`: clamp each bounded channel in the color's OWN space
/// (NaN collapses to the minimum, a missing channel stays missing, polar hue
/// channels pass through).
function clip_in_own_space(mc: root.value.ModernColor) -> root.value.ModernColor {
    let bounds = channel_bounds(mc.space);
    if (bounds == null) {
        return clone_mc(mc);
    }
    let clamp1 = (v: float?, b: root.std.Tuple2<float, float>?) -> float? {
        // PORT: `match (v, b)` → nested `if`s.
        if (v != null) {
            if (b != null) {
                let min = b._0;
                let max = b._1;
                return if (v.is_nan()) {
                    min
                } else {
                    f_clamp(v, min, max)
                };
            }
        }
        v
    };
    root.value.ModernColor {
        space: mc.space,
        channels: [
            clamp1(mc.channels[0], bounds[0]),
            clamp1(mc.channels[1], bounds[1]),
            clamp1(mc.channels[2], bounds[2]),
        ],
        alpha: mc.alpha,
    }
}

/// In-gamut check after converting into `space` (the public `is-in-gamut`
/// shape, also used by the legacy-format serialization probe).
function in_gamut(mc: root.value.ModernColor, space: root.value.ColorSpace) -> bool {
    if (mc.space == space) {
        return is_in_gamut(mc);
    }
    is_in_gamut(convert_modern(mc, space))
}

/// dart-sass powerless rules (with fuzzy comparison): hsl hue is powerless at
/// saturation ~0; hwb hue is powerless when whiteness+blackness >= 100;
/// lch/oklch hue is powerless at chroma ~0. (hsl saturation is never powerless.)
function channel_powerless(
    space: root.value.ColorSpace,
    idx: int,
    conv: root.value.ModernColor,
) -> bool {
    // PORT: `use ColorSpace::*;` spelled out; the `(space, idx)` tuple match
    // is a match on `space` with an `idx` guard.
    let ch = (i: int) -> float {
        conv.channels[i] ?? 0.0
    };
    let fuzzy_zero = (v: float) -> bool {
        v.abs() < 1e-11
    };
    match (space) {
        root.value.ColorSpace.Hsl if idx == 0 => fuzzy_zero(ch(1)),
        root.value.ColorSpace.Hwb if idx == 0 => f_ge(ch(1) + ch(2), 100.0 - 1e-11),
        root.value.ColorSpace.Lch | root.value.ColorSpace.Oklch if idx == 2 => fuzzy_zero(ch(1)),
        _ => false,
    }
}

/// Return `mc` with any powerless channel (e.g. an hsl hue at zero saturation)
/// set to missing, so the missing-channel error serializes it as `none`.
function null_powerless(
    mc: root.value.ModernColor,
    space: root.value.ColorSpace,
) -> root.value.ModernColor {
    let out = clone_mc(mc);
    for (let idx in baml.iter.Range.new(0, 3)) {
        if (channel_powerless(space, idx, mc)) {
            out.channels[idx] = null;
        }
    }
    out
}

/// CSS Color 4 gamut mapping (`local-minde`): reduce oklch chroma via binary
/// search, clipping in the target space, until the clipped color is within a
/// just-noticeable difference (deltaEOK). Ported from the CSS Color 4 spec /
/// dart-sass.
/// dart `LocalMindeGamutMap.map`: `color` is already in the target space.
function gamut_map(color: root.value.ModernColor) -> root.value.ModernColor {
    let fuzzy_eq = (a: float, b: float) -> bool {
        (a - b).abs() < 1e-11
    };
    let origin_oklch = convert_modern(color, root.value.ColorSpace.Oklch);
    let lightness = origin_oklch.channels[0];
    let hue = origin_oklch.channels[2];
    let alpha = color.alpha;
    let l = lightness ?? 0.0;
    if (f_gt(l, 1.0) || fuzzy_eq(l, 1.0)) {
        // A legacy color maps to white via rgb(255,255,255); a modern bounded
        // space takes its channels literally at their maxima (1,1,1).
        return if (color.space.is_legacy()) {
            convert_modern(
                root.value.ModernColor {
                    space: root.value.ColorSpace.Rgb,
                    channels: [255.0, 255.0, 255.0],
                    alpha: alpha,
                },
                color.space,
            )
        } else {
            root.value.ModernColor { space: color.space, channels: [1.0, 1.0, 1.0], alpha: alpha }
        };
    }
    if (l < 0.0 || fuzzy_eq(l, 0.0)) {
        return convert_modern(
            root.value.ModernColor {
                space: root.value.ColorSpace.Rgb,
                channels: [0.0, 0.0, 0.0],
                alpha: alpha,
            },
            color.space,
        );
    }
    let clipped = if (is_in_gamut(color)) {
        clone_mc(color)
    } else {
        clip_in_own_space(color)
    };
    if (delta_eok(clipped, color) < 0.02) {
        return clipped;
    }
    let max = origin_oklch.channels[1] ?? 0.0;
    let min = 0.0;
    let min_in_gamut = true;
    while (f_gt(max - min, 0.0001)) {
        let chroma = (min + max) / 2.0;
        let current = convert_modern(
            root.value.ModernColor {
                space: root.value.ColorSpace.Oklch,
                channels: [lightness, chroma, hue],
                alpha: alpha,
            },
            color.space,
        );
        if (min_in_gamut && is_in_gamut(current)) {
            min = chroma;
            continue;
        }
        clipped
            = if (is_in_gamut(current)) {
                clone_mc(current)
            } else {
                clip_in_own_space(current)
            };
        let e = delta_eok(clipped, current);
        if (e < 0.02) {
            if (0.02 - e < 0.0001) {
                return clipped;
            }
            min = chroma;
            min_in_gamut = false;
        } else {
            max = chroma;
        }
    }
    clipped
}

/// The deltaEOK (Euclidean distance in oklab) between two colors. dart's
/// `math.pow(d, 2)` is the VM's `d*d` square intrinsic (identical bits to a
/// correctly-rounded pow for squares).
function delta_eok(a: root.value.ModernColor, b: root.value.ModernColor) -> float {
    let a = convert_modern(a, root.value.ColorSpace.Oklab);
    let b = convert_modern(b, root.value.ColorSpace.Oklab);
    let dl = z(a.channels[0]) - z(b.channels[0]);
    let da = z(a.channels[1]) - z(b.channels[1]);
    let db = z(a.channels[2]) - z(b.channels[2]);
    (dl * dl + da * da + db * db).sqrt()
}

/// CSS Color 4 `color.mix($c1, $c2, $weight, $method)` interpolation in
/// `space`. `weight` is the percentage (0..100) of `c1`. Channels are
/// interpolated with premultiplied alpha (except the hue, which uses
/// `hue_method`); a channel missing in one color takes the other's value.
function interpolate_mix(
    c1: root.value.Color,
    c2: root.value.Color,
    weight: float,
    space: root.value.ColorSpace,
    hue_method: root.builtins.color.legacy.HueMethod,
) -> root.value.Color {
    let p = weight / 100.0;
    // Powerless channels are blanked in each color's own space first, so the
    // missing carries through the conversion to the interpolation space.
    let m1 = convert_modern(blank_powerless(legacy_to_modern(c1)), space);
    let m2 = convert_modern(blank_powerless(legacy_to_modern(c2)), space);
    let a1 = m1.alpha;
    let a2 = m2.alpha;
    // Result alpha (missing treated as the other's, else 1).
    let ra1 = a1 ?? (a2 ?? 1.0);
    let ra2 = a2 ?? (a1 ?? 1.0);
    let result_alpha = ra1 * p + ra2 * (1.0 - p);
    let hue_idx: int? = match (space) {
        root.value.ColorSpace.Hsl | root.value.ColorSpace.Hwb => 0,
        root.value.ColorSpace.Lch | root.value.ColorSpace.Oklch => 2,
        _ => null,
    };
    let out: (float?)[] = [null, null, null];
    // PORT: `out.iter_mut().enumerate()` → an index loop writing `out[i]`.
    for (let i in baml.iter.Range.new(0, out.length())) {
        let v1 = m1.channels[i];
        let v2 = m2.channels[i];
        // A channel missing in both stays missing.
        if (v1 == null && v2 == null) {
            out[i] = null;
            continue;
        }
        // Missing in one: take the other's value (carry).
        let x1 = v1 ?? (v2 ?? 0.0);
        let x2 = v2 ?? (v1 ?? 0.0);
        if (hue_idx == i) {
            out[i] = interpolate_hue(x1, x2, p, hue_method);
        } else {
            // Premultiplied-alpha interpolation. A missing alpha counts as 1.
            let pa1 = a1 ?? 1.0;
            let pa2 = a2 ?? 1.0;
            let premul = x1 * pa1 * p + x2 * pa2 * (1.0 - p);
            out[i]
                = if (result_alpha.abs() < 1e-12) {
                    x1 * p + x2 * (1.0 - p)
                } else {
                    premul / result_alpha
                };
        }
    }
    let alpha: float? = if (a1 == null && a2 == null) {
        null
    } else {
        result_alpha
    };
    let mc = root.value.ModernColor { space: space, channels: out, alpha: alpha };
    // The result is expressed in c1's original space (CSS Color 4 / dart-sass):
    // a legacy c1 yields a legacy result (missing channels filled), a modern c1
    // keeps its own space.
    let dest = legacy_to_modern(c1).space;
    let back = convert_modern_filled(mc, dest);
    make_modern_in(back, dest)
}

/// Interpolate two hue angles (degrees) by `p` (fraction of `h1`) using the
/// CSS Color 4 hue interpolation method.
function interpolate_hue(
    h1: float,
    h2: float,
    p: float,
    method: root.builtins.color.legacy.HueMethod,
) -> float {
    // PORT: plain comparisons are kept: a NaN hue (the only way BAML's NaN
    // ordering could pick a different branch) makes the result NaN either way.
    let a = root.std.f_rem_euclid(h1, 360.0);
    let b = root.std.f_rem_euclid(h2, 360.0);
    match (method) {
        root.builtins.color.legacy.HueMethod.Shorter => {
            let diff = b - a;
            if (diff > 180.0) {
                a += 360.0;
            } else if (diff < -180.0) {
                b += 360.0;
            }
        },
        root.builtins.color.legacy.HueMethod.Longer => {
            // The longer arc: take the complement of the shorter direction.
            let diff = b - a;
            if (0.0 <= diff && diff < 180.0) {
                b += 360.0;
            } else if (-180.0 <= diff && diff < 0.0) {
                a += 360.0;
            }
        },
        root.builtins.color.legacy.HueMethod.Increasing => {
            if (b < a) {
                b += 360.0;
            }
        },
        root.builtins.color.legacy.HueMethod.Decreasing => {
            if (a < b) {
                a += 360.0;
            }
        },
    }
    a * p + b * (1.0 - p)
}

/// Set a powerless channel to missing (`None`) for interpolation: the hue of
/// hsl (at zero saturation), hwb (whiteness+blackness >= 100) and lch/oklch
/// (at zero chroma) carries no information.
function blank_powerless(mc: root.value.ModernColor) -> root.value.ModernColor {
    // PORT: Rust takes `mc` by value (`mut mc`); work on a copy so the
    // caller's color (and its channel array) is never mutated in place.
    let mc = clone_mc(mc);
    let ch = (i: int) -> float {
        mc.channels[i] ?? 0.0
    };
    match (mc.space) {
        root.value.ColorSpace.Hsl if ch(1) == 0.0 => {
            mc.channels[0] = null;
        },
        root.value.ColorSpace.Hwb if f_ge(ch(1) + ch(2), 100.0) => {
            mc.channels[0] = null;
        },
        root.value.ColorSpace.Lch | root.value.ColorSpace.Oklch if ch(1) == 0.0 => {
            mc.channels[2] = null;
        },
        _ => {},
    }
    mc
}

// ---- modern change / adjust / scale (with $space) -------------------
/// The scaling bounds [min, max] for a channel of `space` (used by
/// `scale-color`). `None` for the hue channel (not scalable).
function scale_bounds(space: root.value.ColorSpace, idx: int) -> root.std.Tuple2<float, float>? {
    // PORT: `use ColorSpace::*;` spelled out.
    let names = space.channel_names();
    if (names[idx] == "hue") {
        return null;
    }
    let bounds: root.std.Tuple2<float, float> = match (space) {
        root.value.ColorSpace.Rgb => root.std.Tuple2 { _0: 0.0, _1: 255.0 },
        root.value.ColorSpace.Srgb
            | root.value.ColorSpace.SrgbLinear
            | root.value.ColorSpace.DisplayP3
            | root.value.ColorSpace.DisplayP3Linear
            | root.value.ColorSpace.A98Rgb
            | root.value.ColorSpace.ProphotoRgb
            | root.value.ColorSpace.Rec2020 =>
        {
            root.std.Tuple2 { _0: 0.0, _1: 1.0 }
        },
        root.value.ColorSpace.Hsl | root.value.ColorSpace.Hwb => {
            root.std.Tuple2 { _0: 0.0, _1: 100.0 }
        },
        root.value.ColorSpace.Lab => {
            if (idx == 0) {
                root.std.Tuple2 { _0: 0.0, _1: 100.0 }
            } else {
                root.std.Tuple2 { _0: -125.0, _1: 125.0 }
            }
        },
        root.value.ColorSpace.Lch => {
            if (idx == 0) {
                root.std.Tuple2 { _0: 0.0, _1: 100.0 }
            } else {
                root.std.Tuple2 { _0: 0.0, _1: 150.0 }
            }
        },
        root.value.ColorSpace.Oklab => {
            if (idx == 0) {
                root.std.Tuple2 { _0: 0.0, _1: 1.0 }
            } else {
                root.std.Tuple2 { _0: -0.4, _1: 0.4 }
            }
        },
        root.value.ColorSpace.Oklch => {
            if (idx == 0) {
                root.std.Tuple2 { _0: 0.0, _1: 1.0 }
            } else {
                root.std.Tuple2 { _0: 0.0, _1: 0.4 }
            }
        },
        root.value.ColorSpace.XyzD65 | root.value.ColorSpace.XyzD50 => {
            root.std.Tuple2 { _0: 0.0, _1: 1.0 }
        },
    };
    bounds
}

/// Read a channel value argument for the modern modify path, in the channel's
/// canonical unit. `idx` selects whether it is the polar hue channel.
function modify_channel_value(
    space: root.value.ColorSpace,
    idx: int,
    v: root.value.Value,
) -> float? {
    if (space.is_polar(idx)) {
        modern_hue(v)
    } else {
        modern_channel(v, channel_pct_base(space, idx))
    }
}

interface ColorSpaceMath {
    /// Whether the channel at `index` is a polar hue channel.
    function is_polar(self, index: int) -> bool throws unknown;
}

implements ColorSpaceMath for root.value.ColorSpace {
    /// Whether the channel at `index` is a polar hue channel.
    function is_polar(self, index: int) -> bool {
        self.channel_names()[index] == "hue"
    }

}

/// The percentage reference (100% = ?) for a channel of `space`.
function channel_pct_base(space: root.value.ColorSpace, idx: int) -> float {
    // PORT: `use ColorSpace::*;` spelled out; the `(space, names[idx])` tuple
    // match is a match on `space` with a channel-name guard.
    let names = space.channel_names();
    let cname = names[idx];
    match (space) {
        root.value.ColorSpace.Rgb => 255.0,
        root.value.ColorSpace.Srgb
            | root.value.ColorSpace.SrgbLinear
            | root.value.ColorSpace.DisplayP3
            | root.value.ColorSpace.DisplayP3Linear
            | root.value.ColorSpace.A98Rgb
            | root.value.ColorSpace.ProphotoRgb
            | root.value.ColorSpace.Rec2020 =>
        {
            1.0
        },
        root.value.ColorSpace.Hsl | root.value.ColorSpace.Hwb => 100.0,
        root.value.ColorSpace.Lab | root.value.ColorSpace.Lch if cname == "lightness" => 100.0,
        root.value.ColorSpace.Oklab | root.value.ColorSpace.Oklch if cname == "lightness" => 1.0,
        root.value.ColorSpace.Lab => 125.0,
        root.value.ColorSpace.Oklab => 0.4,
        root.value.ColorSpace.Lch if cname == "chroma" => 150.0,
        root.value.ColorSpace.Oklch if cname == "chroma" => 0.4,
        root.value.ColorSpace.XyzD65 | root.value.ColorSpace.XyzD50 => 1.0,
        _ => 1.0,
    }
}

/// Read a `scale-color` percentage factor in `[-1, 1]`. Every message names
/// the CHANNEL being scaled (`$red`, `$alpha`, …), as dart-sass does — the
/// parameter is the channel, not a generic `$amount`.
function scale_pct(name: string, v: root.value.Value, pos: root.scanner.Pos) -> float {
    match (v) {
        // A COMPOUND unit only reports its first numerator, so `%*px` must be
        // rejected explicitly rather than read as a percentage.
        root.value.Value_Number { _0: let n } if !n.has_complex_units() && n.unit() == "%" => {
            // A NaN is within no range, so it is rejected like any
            // out-of-range value rather than scaling the channel to nothing.
            if (n.value.is_nan() || n.value < -100.0 || n.value > 100.0) {
                throw root.error.Error.at(
                    `\$${name}: Expected ${n.to_css(false)} to be within -100% and 100%.`,
                    pos,
                );
            }
            n.value / 100.0
        },
        root.value.Value_Number { _0: let n } => {
            throw root.error.Error.at(
                `\$${name}: Expected ${n.to_css(false)} to have unit "%".`,
                pos,
            );
        },
        let other => {
            throw root.error.Error.at(
                `\$${name}: ${other.to_css(false)} is not a number.`,
                pos,
            );
        },
    }
}

/// Scale `current` by `factor` (`-1..=1`) toward `bounds.1` (positive) or
/// `bounds.0` (negative). dart `_scaleChannel`: a channel already past the
/// targeted bound stays put (scaling can't pull it back into range).
function scale_to(current: float, factor: float, bounds: root.std.Tuple2<float, float>) -> float {
    if (factor == 0.0) {
        current
    } else if (f_gt(factor, 0.0)) {
        if (f_ge(current, bounds._1)) {
            current
        } else {
            current + (bounds._1 - current) * factor
        }
    } else if (current <= bounds._0) {
        current
    } else {
        current + (current - bounds._0) * factor
    }
}

/// dart names `none` among the things it wanted wherever it would have been
/// accepted — which is `change`, the only modify op that takes one.
function none_suffix(accepts_none: bool) -> string {
    if (accepts_none) {
        " or unquoted \"none\""
    } else {
        ""
    }
}

/// Validate a channel value's unit for the modern change/adjust path. A hue
/// requires an angle unit (or none); other channels accept `%` or no unit.
function validate_modify_unit(
    space: root.value.ColorSpace,
    idx: int,
    name: string,
    v: root.value.Value,
    accepts_none: bool,
    pos: root.scanner.Pos,
) -> void {
    // PORT: the `Value::Number(n) | Value::Slash(n, _)` or-pattern binds `n`
    // across two variants, which BAML rejects: one arm per variant.
    let num: root.value.Number = match (v) {
        // One arm for both spellings, as in the channel readers: a
        // slash-division's quotient is unit-checked like any number. (Nothing
        // reaches here as a `Slash` today — an argument's division has already
        // evaluated — but the two must not diverge if one ever does.)
        root.value.Value_Number { _0: let n } => n,
        root.value.Value_Slash { _0: let n } => n,
        // A DEGENERATE `calc()` is a channel value; a folded numeric one —
        // which only survives where the evaluator preserves calculations,
        // inside `@supports` — is not a number at all.
        root.value.Value_Calc { _0: let node }
            if root.builtins.color.degenerate_const(node) != null => {
            return;
        },
        let other => {
            throw root.error.Error.at(
                `\$${name}: ${other.to_css(false)} is not a number${none_suffix(accepts_none)}.`,
                pos,
            );
        },
    };
    if (space.is_polar(idx)) {
        // Legacy hsl/hwb treat any hue unit leniently (as degrees); the modern
        // spaces require a real angle unit.
        if (space.is_legacy()) {
            return;
        }
        let unit = num.unit();
        let ok = num.is_unitless() || unit == "deg" || unit == "grad" || unit == "rad" || unit == "turn";
        if (!ok) {
            throw root.error.Error.at(
                `\$${name}: Expected ${num.to_css(false)} to have an angle unit (deg, grad, rad, turn).`,
                pos,
            );
        }
    } else if (space == root.value.ColorSpace.Hsl) {
        // Legacy hsl `saturation`/`lightness` accept any unit: dart-sass emits a
        // deprecation warning (to stderr) for a non-`%` unit but uses the value.
    } else if (space == root.value.ColorSpace.Hwb) {
        // Legacy hwb `whiteness`/`blackness` strictly require `%` (note: the
        // error message has no "or no units" — unitless is also rejected).
        if (num.unit() != "%") {
            throw root.error.Error.at(
                `\$${name}: Expected ${num.to_css(false)} to have unit "%".`,
                pos,
            );
        }
    } else if (!num.is_unitless() && num.unit() != "%") {
        throw root.error.Error.at(
            `\$${name}: Expected ${num.to_css(false)} to have unit "%" or no units.`,
            pos,
        );
    }
}

/// Clamp an `adjust-color` result channel: legacy rgb channels clamp to
/// `[0,255]`, lab/lch/oklab/oklch lightness clamps to its range, and lch/oklch
/// chroma is floored at 0. hsl/hwb percentages and the modern rgb-style spaces
/// are left unbounded (matching dart-sass).
function clamp_adjust_channel(space: root.value.ColorSpace, idx: int, v: float) -> float {
    // PORT: `use ColorSpace::*;` spelled out; the `(space, names[idx])` tuple
    // match is a match on `space` with a channel-name guard.
    let names = space.channel_names();
    let cname = names[idx];
    match (space) {
        root.value.ColorSpace.Rgb => f_clamp(v, 0.0, 255.0),
        root.value.ColorSpace.Lab | root.value.ColorSpace.Lch if cname == "lightness" => {
            f_clamp(v, 0.0, 100.0)
        },
        root.value.ColorSpace.Oklab | root.value.ColorSpace.Oklch if cname == "lightness" => {
            f_clamp(v, 0.0, 1.0)
        },
        root.value.ColorSpace.Lch | root.value.ColorSpace.Oklch if cname == "chroma" => {
            root.std.fmax(v, 0.0)
        },
        // hsl saturation can exceed 100% but not go negative; dart-sass clamps
        // the lower bound only (so `adjust($c, $saturation: -100%)` desaturates
        // to grey rather than flipping the hue).
        root.value.ColorSpace.Hsl if cname == "saturation" => root.std.fmax(v, 0.0),
        _ => v,
    }
}

/// Invert each channel of `src` (already in `space`) per CSS Color 4: rgb-style
/// and lightness channels invert toward their max, lab/oklab a/b negate, hue
/// shifts 180 degrees, chroma is unchanged, and hwb swaps whiteness/blackness.
function invert_channels(
    space: root.value.ColorSpace,
    src: root.value.ModernColor,
) -> root.value.ModernColor {
    // PORT: `use ColorSpace::*;` spelled out.
    let ch = src.channels;
    let inv_max = (v: float?, max: float) -> float? {
        if (v != null) {
            max - v
        } else {
            null
        }
    };
    let negate = (v: float?) -> float? {
        if (v != null) {
            -v
        } else {
            null
        }
    };
    let shift_hue = (v: float?) -> float? {
        if (v != null) {
            v + 180.0
        } else {
            null
        }
    };
    let channels: (float?)[] = match (space) {
        root.value.ColorSpace.Rgb => {
            [inv_max(ch[0], 255.0), inv_max(ch[1], 255.0), inv_max(ch[2], 255.0)]
        },
        root.value.ColorSpace.Srgb
            | root.value.ColorSpace.SrgbLinear
            | root.value.ColorSpace.DisplayP3
            | root.value.ColorSpace.DisplayP3Linear
            | root.value.ColorSpace.A98Rgb
            | root.value.ColorSpace.ProphotoRgb
            | root.value.ColorSpace.Rec2020
            | root.value.ColorSpace.XyzD65
            | root.value.ColorSpace.XyzD50 =>
        {
            [inv_max(ch[0], 1.0), inv_max(ch[1], 1.0), inv_max(ch[2], 1.0)]
        },
        root.value.ColorSpace.Hsl => [shift_hue(ch[0]), ch[1], inv_max(ch[2], 100.0)],
        root.value.ColorSpace.Hwb => [shift_hue(ch[0]), ch[2], ch[1]],
        root.value.ColorSpace.Lab => [inv_max(ch[0], 100.0), negate(ch[1]), negate(ch[2])],
        root.value.ColorSpace.Oklab => [inv_max(ch[0], 1.0), negate(ch[1]), negate(ch[2])],
        root.value.ColorSpace.Lch => [inv_max(ch[0], 100.0), ch[1], shift_hue(ch[2])],
        root.value.ColorSpace.Oklch => [inv_max(ch[0], 1.0), ch[1], shift_hue(ch[2])],
    };
    root.value.ModernColor { space: space, channels: channels, alpha: src.alpha }
}

/// Whether `invert` transforms the channel at `idx` of `space` using its value
/// (so a missing/powerless value is an error), as opposed to passing it through
/// unchanged (hsl saturation, lch/oklch chroma) or merely swapping it (hwb
/// whiteness/blackness).
function invert_modifies(space: root.value.ColorSpace, idx: int) -> bool {
    // PORT: `use ColorSpace::*;` spelled out; `matches!` on the `(space, idx)`
    // tuple is a match on `space` with an `idx` guard.
    let passes_through = match (space) {
        root.value.ColorSpace.Hsl if idx == 1 => true,
        root.value.ColorSpace.Hwb if idx == 1 => true,
        root.value.ColorSpace.Hwb if idx == 2 => true,
        root.value.ColorSpace.Lch if idx == 1 => true,
        root.value.ColorSpace.Oklch if idx == 1 => true,
        _ => false,
    };
    !passes_through
}
