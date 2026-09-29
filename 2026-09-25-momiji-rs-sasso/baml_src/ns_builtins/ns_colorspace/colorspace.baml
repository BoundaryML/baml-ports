// Ported from sasso `src/builtins/colorspace.rs` (namespace `root.builtins.colorspace`).
//
// dart-sass's exact color-space conversion engine.
//
// A bit-faithful port of `ColorSpace.convert`/`convertLinear` and the
// per-space `convert` overrides from dart-sass (extracted from the shipped
// JS bundle): conversions go through ONE precomputed transformation matrix
// between linear spaces — not an XYZ hub — and every `Math.pow` call maps to
// the glibc/musl `pow` port in [`crate::musl_math`]. Formula shapes, branch
// constants, and operation order are copied exactly; this is what makes the
// converted channel values byte-identical to the sass-spec expectations.

// mod matrices → namespace `root.builtins.colorspace.matrices`

/// The nodes of dart's transformation-matrix graph: the linear form of each
/// RGB family plus the three hub spaces. `ColorSpace`s sharing a node differ
/// only in their transfer functions (`Srgb`/`Rgb`/`SrgbLinear` are all
/// `LinSrgb`).
enum Lin {
    Srgb,
    DisplayP3,
    A98,
    Prophoto,
    Rec2020,
    XyzD65,
    XyzD50,
    Lms,
}

function matrix(src: Lin, dst: Lin) -> float[] {
    // PORT: `match (src, dst)` → an if/else chain.
    if (src == Lin.Srgb && dst == Lin.DisplayP3) {
        root.builtins.colorspace.matrices.LINEAR_SRGB_TO_LINEAR_DISPLAY_P3()
    } else if (src == Lin.Srgb && dst == Lin.A98) {
        root.builtins.colorspace.matrices.LINEAR_SRGB_TO_LINEAR_A98_RGB()
    } else if (src == Lin.Srgb && dst == Lin.Prophoto) {
        root.builtins.colorspace.matrices.LINEAR_SRGB_TO_LINEAR_PROPHOTO_RGB()
    } else if (src == Lin.Srgb && dst == Lin.Rec2020) {
        root.builtins.colorspace.matrices.LINEAR_SRGB_TO_LINEAR_REC2020()
    } else if (src == Lin.Srgb && dst == Lin.XyzD65) {
        root.builtins.colorspace.matrices.LINEAR_SRGB_TO_XYZ_D65()
    } else if (src == Lin.Srgb && dst == Lin.XyzD50) {
        root.builtins.colorspace.matrices.LINEAR_SRGB_TO_XYZ_D50()
    } else if (src == Lin.Srgb && dst == Lin.Lms) {
        root.builtins.colorspace.matrices.LINEAR_SRGB_TO_LMS()
    } else if (src == Lin.DisplayP3 && dst == Lin.Srgb) {
        root.builtins.colorspace.matrices.LINEAR_DISPLAY_P3_TO_LINEAR_SRGB()
    } else if (src == Lin.DisplayP3 && dst == Lin.A98) {
        root.builtins.colorspace.matrices.LINEAR_DISPLAY_P3_TO_LINEAR_A98_RGB()
    } else if (src == Lin.DisplayP3 && dst == Lin.Prophoto) {
        root.builtins.colorspace.matrices.LINEAR_DISPLAY_P3_TO_LINEAR_PROPHOTO_RGB()
    } else if (src == Lin.DisplayP3 && dst == Lin.Rec2020) {
        root.builtins.colorspace.matrices.LINEAR_DISPLAY_P3_TO_LINEAR_REC2020()
    } else if (src == Lin.DisplayP3 && dst == Lin.XyzD65) {
        root.builtins.colorspace.matrices.LINEAR_DISPLAY_P3_TO_XYZ_D65()
    } else if (src == Lin.DisplayP3 && dst == Lin.XyzD50) {
        root.builtins.colorspace.matrices.LINEAR_DISPLAY_P3_TO_XYZ_D50()
    } else if (src == Lin.DisplayP3 && dst == Lin.Lms) {
        root.builtins.colorspace.matrices.LINEAR_DISPLAY_P3_TO_LMS()
    } else if (src == Lin.A98 && dst == Lin.Srgb) {
        root.builtins.colorspace.matrices.LINEAR_A98_RGB_TO_LINEAR_SRGB()
    } else if (src == Lin.A98 && dst == Lin.DisplayP3) {
        root.builtins.colorspace.matrices.LINEAR_A98_RGB_TO_LINEAR_DISPLAY_P3()
    } else if (src == Lin.A98 && dst == Lin.Prophoto) {
        root.builtins.colorspace.matrices.LINEAR_A98_RGB_TO_LINEAR_PROPHOTO_RGB()
    } else if (src == Lin.A98 && dst == Lin.Rec2020) {
        root.builtins.colorspace.matrices.LINEAR_A98_RGB_TO_LINEAR_REC2020()
    } else if (src == Lin.A98 && dst == Lin.XyzD65) {
        root.builtins.colorspace.matrices.LINEAR_A98_RGB_TO_XYZ_D65()
    } else if (src == Lin.A98 && dst == Lin.XyzD50) {
        root.builtins.colorspace.matrices.LINEAR_A98_RGB_TO_XYZ_D50()
    } else if (src == Lin.A98 && dst == Lin.Lms) {
        root.builtins.colorspace.matrices.LINEAR_A98_RGB_TO_LMS()
    } else if (src == Lin.Prophoto && dst == Lin.Srgb) {
        root.builtins.colorspace.matrices.LINEAR_PROPHOTO_RGB_TO_LINEAR_SRGB()
    } else if (src == Lin.Prophoto && dst == Lin.DisplayP3) {
        root.builtins.colorspace.matrices.LINEAR_PROPHOTO_RGB_TO_LINEAR_DISPLAY_P3()
    } else if (src == Lin.Prophoto && dst == Lin.A98) {
        root.builtins.colorspace.matrices.LINEAR_PROPHOTO_RGB_TO_LINEAR_A98_RGB()
    } else if (src == Lin.Prophoto && dst == Lin.Rec2020) {
        root.builtins.colorspace.matrices.LINEAR_PROPHOTO_RGB_TO_LINEAR_REC2020()
    } else if (src == Lin.Prophoto && dst == Lin.XyzD65) {
        root.builtins.colorspace.matrices.LINEAR_PROPHOTO_RGB_TO_XYZ_D65()
    } else if (src == Lin.Prophoto && dst == Lin.XyzD50) {
        root.builtins.colorspace.matrices.LINEAR_PROPHOTO_RGB_TO_XYZ_D50()
    } else if (src == Lin.Prophoto && dst == Lin.Lms) {
        root.builtins.colorspace.matrices.LINEAR_PROPHOTO_RGB_TO_LMS()
    } else if (src == Lin.Rec2020 && dst == Lin.Srgb) {
        root.builtins.colorspace.matrices.LINEAR_REC2020_TO_LINEAR_SRGB()
    } else if (src == Lin.Rec2020 && dst == Lin.DisplayP3) {
        root.builtins.colorspace.matrices.LINEAR_REC2020_TO_LINEAR_DISPLAY_P3()
    } else if (src == Lin.Rec2020 && dst == Lin.A98) {
        root.builtins.colorspace.matrices.LINEAR_REC2020_TO_LINEAR_A98_RGB()
    } else if (src == Lin.Rec2020 && dst == Lin.Prophoto) {
        root.builtins.colorspace.matrices.LINEAR_REC2020_TO_LINEAR_PROPHOTO_RGB()
    } else if (src == Lin.Rec2020 && dst == Lin.XyzD65) {
        root.builtins.colorspace.matrices.LINEAR_REC2020_TO_XYZ_D65()
    } else if (src == Lin.Rec2020 && dst == Lin.XyzD50) {
        root.builtins.colorspace.matrices.LINEAR_REC2020_TO_XYZ_D50()
    } else if (src == Lin.Rec2020 && dst == Lin.Lms) {
        root.builtins.colorspace.matrices.LINEAR_REC2020_TO_LMS()
    } else if (src == Lin.XyzD65 && dst == Lin.Srgb) {
        root.builtins.colorspace.matrices.XYZ_D65_TO_LINEAR_SRGB()
    } else if (src == Lin.XyzD65 && dst == Lin.DisplayP3) {
        root.builtins.colorspace.matrices.XYZ_D65_TO_LINEAR_DISPLAY_P3()
    } else if (src == Lin.XyzD65 && dst == Lin.A98) {
        root.builtins.colorspace.matrices.XYZ_D65_TO_LINEAR_A98_RGB()
    } else if (src == Lin.XyzD65 && dst == Lin.Prophoto) {
        root.builtins.colorspace.matrices.XYZ_D65_TO_LINEAR_PROPHOTO_RGB()
    } else if (src == Lin.XyzD65 && dst == Lin.Rec2020) {
        root.builtins.colorspace.matrices.XYZ_D65_TO_LINEAR_REC2020()
    } else if (src == Lin.XyzD65 && dst == Lin.XyzD50) {
        root.builtins.colorspace.matrices.XYZ_D65_TO_XYZ_D50()
    } else if (src == Lin.XyzD65 && dst == Lin.Lms) {
        root.builtins.colorspace.matrices.XYZ_D65_TO_LMS()
    } else if (src == Lin.XyzD50 && dst == Lin.Srgb) {
        root.builtins.colorspace.matrices.XYZ_D50_TO_LINEAR_SRGB()
    } else if (src == Lin.XyzD50 && dst == Lin.DisplayP3) {
        root.builtins.colorspace.matrices.XYZ_D50_TO_LINEAR_DISPLAY_P3()
    } else if (src == Lin.XyzD50 && dst == Lin.A98) {
        root.builtins.colorspace.matrices.XYZ_D50_TO_LINEAR_A98_RGB()
    } else if (src == Lin.XyzD50 && dst == Lin.Prophoto) {
        root.builtins.colorspace.matrices.XYZ_D50_TO_LINEAR_PROPHOTO_RGB()
    } else if (src == Lin.XyzD50 && dst == Lin.Rec2020) {
        root.builtins.colorspace.matrices.XYZ_D50_TO_LINEAR_REC2020()
    } else if (src == Lin.XyzD50 && dst == Lin.XyzD65) {
        root.builtins.colorspace.matrices.XYZ_D50_TO_XYZ_D65()
    } else if (src == Lin.XyzD50 && dst == Lin.Lms) {
        root.builtins.colorspace.matrices.XYZ_D50_TO_LMS()
    } else if (src == Lin.Lms && dst == Lin.Srgb) {
        root.builtins.colorspace.matrices.LMS_TO_LINEAR_SRGB()
    } else if (src == Lin.Lms && dst == Lin.DisplayP3) {
        root.builtins.colorspace.matrices.LMS_TO_LINEAR_DISPLAY_P3()
    } else if (src == Lin.Lms && dst == Lin.A98) {
        root.builtins.colorspace.matrices.LMS_TO_LINEAR_A98_RGB()
    } else if (src == Lin.Lms && dst == Lin.Prophoto) {
        root.builtins.colorspace.matrices.LMS_TO_LINEAR_PROPHOTO_RGB()
    } else if (src == Lin.Lms && dst == Lin.Rec2020) {
        root.builtins.colorspace.matrices.LMS_TO_LINEAR_REC2020()
    } else if (src == Lin.Lms && dst == Lin.XyzD65) {
        root.builtins.colorspace.matrices.LMS_TO_XYZ_D65()
    } else if (src == Lin.Lms && dst == Lin.XyzD50) {
        root.builtins.colorspace.matrices.LMS_TO_XYZ_D50()
    } else {
        // Same node: no matrix is applied (callers short-circuit).
        root.std.panic(
            "internal error: entered unreachable code: no transformation matrix for identical linear nodes",
        )
    }
}

// ---- transfer functions (dart's exact constants) ---------------------

// PORT: BAML's `float.signum()` maps NaN to `1.0` (Rust: NaN); every
// `signum()` below multiplies a `pow`/arithmetic result that is already NaN
// for a NaN channel, so the products are identical.

function srgb_to_linear(c: float) -> float {
    let abs = c.abs();
    if (abs <= 0.04045) {
        c / 12.92
    } else {
        c.signum() * root.musl_math.pow((abs + 0.055) / 1.055, 2.4)
    }
}

function srgb_from_linear(c: float) -> float {
    let abs = c.abs();
    if (abs <= 0.0031308) {
        c * 12.92
    } else {
        c.signum() * (1.055 * root.musl_math.pow(abs, 0.4166666666666667) - 0.055)
    }
}

function a98_to_linear(c: float) -> float {
    c.signum() * root.musl_math.pow(c.abs(), 2.19921875)
}

function a98_from_linear(c: float) -> float {
    c.signum() * root.musl_math.pow(c.abs(), 0.4547069271758437)
}

function prophoto_to_linear(c: float) -> float {
    let abs = c.abs();
    if (abs <= 0.03125) {
        c / 16.0
    } else {
        c.signum() * root.musl_math.pow(abs, 1.8)
    }
}

function prophoto_from_linear(c: float) -> float {
    let abs = c.abs();
    if (abs >= 0.001953125) {
        c.signum() * root.musl_math.pow(abs, 0.5555555555555556)
    } else {
        16.0 * c
    }
}

// dart-sass 1.102.0 switched rec2020 from the BT.2020 piecewise curve to the
// pure 2.4 gamma of the latest CSS Color 4 draft (rec2020.dart).
function rec2020_to_linear(c: float) -> float {
    c.signum() * root.musl_math.pow(c.abs(), 2.4)
}

function rec2020_from_linear(c: float) -> float {
    c.signum() * root.musl_math.pow(c.abs(), 1.0 / 2.4)
}

/// A space's (linear node, toLinear, fromLinear) triple.
type LinTransfer = root.std.Tuple3<Lin, (float) -> float throws unknown, (float) -> float throws unknown>;

/// The linear node and transfer functions of a matrix-graph color space.
/// `Rgb` participates with srgb transfers over 0..1 channels (the 0..255
/// scaling is applied at the [`convert`] boundary).
function lin_of(space: root.value.ColorSpace) -> LinTransfer {
    match (space) {
        root.value.ColorSpace.Rgb
            | root.value.ColorSpace.Srgb
            | root.value.ColorSpace.Hsl
            | root.value.ColorSpace.Hwb =>
        {
            lin_transfer(Lin.Srgb, srgb_to_linear, srgb_from_linear)
        },
        root.value.ColorSpace.SrgbLinear => lin_transfer(Lin.Srgb, lin_of__id, lin_of__id),
        root.value.ColorSpace.DisplayP3 => {
            lin_transfer(Lin.DisplayP3, srgb_to_linear, srgb_from_linear)
        },
        root.value.ColorSpace.DisplayP3Linear => lin_transfer(Lin.DisplayP3, lin_of__id, lin_of__id),
        root.value.ColorSpace.A98Rgb => lin_transfer(Lin.A98, a98_to_linear, a98_from_linear),
        root.value.ColorSpace.ProphotoRgb => {
            lin_transfer(Lin.Prophoto, prophoto_to_linear, prophoto_from_linear)
        },
        root.value.ColorSpace.Rec2020 => {
            lin_transfer(Lin.Rec2020, rec2020_to_linear, rec2020_from_linear)
        },
        root.value.ColorSpace.XyzD65 => lin_transfer(Lin.XyzD65, lin_of__id, lin_of__id),
        root.value.ColorSpace.XyzD50 => lin_transfer(Lin.XyzD50, lin_of__id, lin_of__id),
        root.value.ColorSpace.Lab
            | root.value.ColorSpace.Lch
            | root.value.ColorSpace.Oklab
            | root.value.ColorSpace.Oklch =>
        {
            root.std.panic(
                "internal error: entered unreachable code: lab-family spaces are handled before the matrix graph",
            )
        },
    }
}

function lin_of__id(c: float) -> float {
    c
}

/// PORT: builds a `LinTransfer` tuple (`(lin, to_linear, from_linear)` in
/// Rust): a bare tuple literal of plain functions infers `throws never`
/// function types, which do not unify with `LinTransfer`'s.
function lin_transfer(
    lin: Lin,
    to_linear: (float) -> float throws unknown,
    from_linear: (float) -> float throws unknown,
) -> LinTransfer {
    root.std.Tuple3 { _0: lin, _1: to_linear, _2: from_linear }
}

// ---- hsl / hwb (dart `HslColorSpace.convert` / `HwbColorSpace.convert`) --

/// JS `Math.max` (NaN-propagating, unlike Rust's `f64::max` which ignores
/// NaN) — the comparisons in the conversion code must see dart's values.
function js_max(a: float, b: float) -> float {
    if (a.is_nan() || b.is_nan()) {
        root.std.F64_NAN()
    } else {
        root.std.fmax(a, b)
    }
}

/// JS `Math.min` (NaN-propagating).
function js_min(a: float, b: float) -> float {
    if (a.is_nan() || b.is_nan()) {
        root.std.F64_NAN()
    } else {
        root.std.fmin(a, b)
    }
}

/// dart `hueToRgb(m1, m2, hue)` — the CSS2 algorithm.
function hue_to_rgb(m1: float, m2: float, hue: float) -> float {
    if (hue < 0.0) {
        hue += 1.0;
    }
    if (hue > 1.0) {
        hue -= 1.0;
    }
    if (hue < 0.16666666666666666) {
        m1 + (m2 - m1) * hue * 6.0
    } else if (hue < 0.5) {
        m2
    } else if (hue < 0.6666666666666666) {
        m1 + (m2 - m1) * (0.6666666666666666 - hue) * 6.0
    } else {
        m1
    }
}

/// hsl [hue-deg, sat-%, light-%] -> srgb [0..1].
function hsl_to_srgb(hsl: float[]) -> float[] {
    let scaled_hue = root.std.f_rem_euclid(hsl[0] / 360.0, 1.0);
    let scaled_saturation = hsl[1] / 100.0;
    let scaled_lightness = hsl[2] / 100.0;
    let m2 = if (scaled_lightness <= 0.5) {
        scaled_lightness * (scaled_saturation + 1.0)
    } else {
        scaled_lightness + scaled_saturation - scaled_lightness * scaled_saturation
    };
    let m1 = scaled_lightness * 2.0 - m2;
    [
        hue_to_rgb(m1, m2, scaled_hue + 0.3333333333333333),
        hue_to_rgb(m1, m2, scaled_hue),
        hue_to_rgb(m1, m2, scaled_hue - 0.3333333333333333),
    ]
}

/// hwb [hue-deg, white-%, black-%] -> srgb [0..1].
function hwb_to_srgb(hwb: float[]) -> float[] {
    let scaled_hue = root.std.f_rem_euclid(hwb[0], 360.0) / 360.0;
    let scaled_whiteness = hwb[1] / 100.0;
    let scaled_blackness = hwb[2] / 100.0;
    let sum = scaled_whiteness + scaled_blackness;
    if (sum > 1.0) {
        scaled_whiteness /= sum;
        scaled_blackness /= sum;
    }
    let factor = 1.0 - scaled_whiteness - scaled_blackness;
    let to_rgb = (hue: float) -> float {
        hue_to_rgb(0.0, 1.0, hue) * factor + scaled_whiteness
    };
    [
        to_rgb(scaled_hue + 0.3333333333333333),
        to_rgb(scaled_hue),
        to_rgb(scaled_hue - 0.3333333333333333),
    ]
}

/// srgb [0..1] -> hsl [hue-deg, sat-%, light-%] (dart `SrgbColorSpace.convert`
/// for an hsl destination, including the negative-saturation normalization
/// out-of-gamut channels produce).
function srgb_to_hsl(rgb: float[]) -> float[] {
    let red = rgb[0];
    let green = rgb[1];
    let blue = rgb[2];
    let max = js_max(js_max(red, green), blue);
    let min = js_min(js_min(red, green), blue);
    let delta = max - min;
    let hue = if (max == min) {
        0.0
    } else if (max == red) {
        60.0 * (green - blue) / delta + 360.0
    } else if (max == green) {
        60.0 * (blue - red) / delta + 120.0
    } else {
        60.0 * (red - green) / delta + 240.0
    };
    let lightness = (min + max) / 2.0;
    let saturation = if (lightness == 0.0 || lightness == 1.0) {
        0.0
    } else {
        100.0 * (max - lightness) / root.std.fmin(lightness, 1.0 - lightness)
    };
    if (saturation < 0.0) {
        hue += 180.0;
        saturation = saturation.abs();
    };
    // PORT: `;` above so the array literal is not parsed as an index.
    [root.std.f_rem_euclid(hue, 360.0), saturation, lightness * 100.0]
}

/// srgb [0..1] -> hwb [hue-deg, white-%, black-%].
function srgb_to_hwb(rgb: float[]) -> float[] {
    let red = rgb[0];
    let green = rgb[1];
    let blue = rgb[2];
    let max = js_max(js_max(red, green), blue);
    let min = js_min(js_min(red, green), blue);
    let delta = max - min;
    let hue = if (max == min) {
        0.0
    } else if (max == red) {
        60.0 * (green - blue) / delta + 360.0
    } else if (max == green) {
        60.0 * (blue - red) / delta + 120.0
    } else {
        60.0 * (red - green) / delta + 240.0
    };
    [root.std.f_rem_euclid(hue, 360.0), min * 100.0, 100.0 - max * 100.0]
}

// ---- lab / lch (dart `LabColorSpace` / `XyzD50ColorSpace`) ---------------

/// dart's `math.pow(x, 3)` compiles to `x*x*x` on the VM (small-integer
/// exponents are intrinsics, NOT the libm pow) — using the real pow here
/// drifts a ulp from the dart-VM oracle on far-range inputs.
function cube(t: float) -> float {
    t * t * t
}

/// dart's `math.pow(x, 2)` intrinsic (see [`cube`]).
function square(t: float) -> float {
    t * t
}

function LAB_EPSILON() -> float {
    0.008856451679035631 // 216/24389
}

function LAB_KAPPA() -> float {
    903.2962962962963 // 24389/27
}

function D50_X() -> float {
    0.9642956764295677
}

function D50_Z() -> float {
    0.8251046025104602
}

/// dart `LabColorSpace._convertFToXorZ`.
function lab_f_to_x_or_z(component: float) -> float {
    let cubed = cube(component);
    if (cubed > LAB_EPSILON()) {
        cubed
    } else {
        (116.0 * component - 16.0) / LAB_KAPPA()
    }
}

/// lab [L, a, b] -> xyz-d50 (dart `LabColorSpace.convert`, default arm).
function lab_to_xyz_d50(lab: float[]) -> float[] {
    let f1 = (lab[0] + 16.0) / 116.0;
    let x = lab_f_to_x_or_z(lab[1] / 500.0 + f1) * D50_X();
    let y = if (lab[0] > 8.0) {
        cube(f1)
    } else {
        lab[0] / LAB_KAPPA()
    };
    let z = lab_f_to_x_or_z(f1 - lab[2] / 200.0) * D50_Z();
    [x, y, z]
}

/// dart `XyzD50ColorSpace._convertComponentToLabF`.
function xyz_component_to_lab_f(component: float) -> float {
    if (component > LAB_EPSILON()) {
        root.musl_math.pow(component, 0.3333333333333333)
    } else {
        (LAB_KAPPA() * component + 16.0) / 116.0
    }
}

/// xyz-d50 -> lab (dart `XyzD50ColorSpace.convert`, lab/lch arm).
function xyz_d50_to_lab(xyz: float[]) -> float[] {
    let f0 = xyz_component_to_lab_f(xyz[0] / D50_X());
    let f1 = xyz_component_to_lab_f(xyz[1] / 1.0);
    let f2 = xyz_component_to_lab_f(xyz[2] / D50_Z());
    [116.0 * f1 - 16.0, 500.0 * (f0 - f1), 200.0 * (f1 - f2)]
}

function PI() -> float {
    3.141592653589793
}

/// lch-style [L, chroma, hue-deg] -> lab-style [L, a, b] (dart
/// `LchColorSpace.convert` / `OklchColorSpace.convert`).
function lch_to_lab(lch: float[]) -> float[] {
    let hue_radians = lch[2] * PI() / 180.0;
    [lch[0], lch[1] * hue_radians.cos(), lch[1] * hue_radians.sin()]
}

/// lab-style [L, a, b] -> lch-style [L, chroma, hue-deg] (dart `labToLch`:
/// `pow(a, 2)` — the VM's square intrinsic — and a `+360` negative-hue fold).
function lab_to_lch(lab: float[]) -> float[] {
    let chroma = (square(lab[1]) + square(lab[2])).sqrt();
    let hue = lab[2].atan2(lab[1]) * 180.0 / PI();
    if (hue < 0.0) {
        hue += 360.0;
    };
    // PORT: `;` above so the array literal is not parsed as an index.
    [lab[0], chroma, hue]
}

// ---- oklab / oklch (dart `OklabColorSpace` / `LmsColorSpace`) ------------

/// oklab [L, a, b] -> LMS (dart `OklabColorSpace.convert`: matrix rows cubed
/// through `pow(x, 3)` — the VM's `x*x*x` intrinsic).
function oklab_to_lms(oklab: float[]) -> float[] {
    let m = root.builtins.colorspace.matrices.OKLAB_TO_LMS();
    [
        cube(m[0] * oklab[0] + m[1] * oklab[1] + m[2] * oklab[2]),
        cube(m[3] * oklab[0] + m[4] * oklab[1] + m[5] * oklab[2]),
        cube(m[6] * oklab[0] + m[7] * oklab[1] + m[8] * oklab[2]),
    ]
}

/// LMS -> oklab (dart `LmsColorSpace.convert`, oklab arm: signed cube roots
/// via `pow(abs, 1/3) * sign`, then the lmsToOklab matrix).
function lms_to_oklab(lms: float[]) -> float[] {
    let scale = (t: float) -> float {
        root.musl_math.pow(t.abs(), 0.3333333333333333) * t.signum()
    };
    let l = scale(lms[0]);
    let m = scale(lms[1]);
    let s = scale(lms[2]);
    let t = root.builtins.colorspace.matrices.LMS_TO_OKLAB();
    [t[0] * l + t[1] * m + t[2] * s, t[3] * l + t[4] * m + t[5] * s, t[6] * l + t[7] * m + t[8] * s]
}

// ---- the conversion engine ----------------------------------------------

/// Convert `ch` (in `src`'s canonical channel units) to `dest`'s units,
/// following dart-sass's exact conversion graph.
function convert(src: root.value.ColorSpace, dest: root.value.ColorSpace, ch: float[]) -> float[] {
    if (src == dest) {
        return ch;
    }
    match (src) {
        root.value.ColorSpace.Hsl => from_srgb_source(hsl_to_srgb(ch), dest),
        root.value.ColorSpace.Hwb => from_srgb_source(hwb_to_srgb(ch), dest),
        root.value.ColorSpace.Rgb => {
            from_srgb_source([ch[0] / 255.0, ch[1] / 255.0, ch[2] / 255.0], dest)
        },
        root.value.ColorSpace.Lab => from_lab_source(ch, dest),
        root.value.ColorSpace.Lch => {
            let lab = lch_to_lab(ch);
            if (dest == root.value.ColorSpace.Lab) {
                lab
            } else {
                from_lab_source(lab, dest)
            }
        },
        root.value.ColorSpace.Oklab => from_oklab_source(ch, dest),
        root.value.ColorSpace.Oklch => {
            // dart's `OklabColorSpace.convert` has NO same-space case, so an
            // oklch source bound for oklab still round-trips through LMS
            // (cube then cube root) — `oklch(10% 999999 0deg)` comes back as
            // `oklab(9.9999999976% 999998.9999999992 0)`. Only a direct
            // oklab→oklab conversion short-circuits (at the toSpace level).
            from_oklab_source(lch_to_lab(ch), dest)
        },
        _ => convert_linear(src, ch, dest),
    }
}

/// dart `SrgbColorSpace.convert`: srgb channels already in [0..1].
function from_srgb_source(rgb: float[], dest: root.value.ColorSpace) -> float[] {
    match (dest) {
        root.value.ColorSpace.Hsl => srgb_to_hsl(rgb),
        root.value.ColorSpace.Hwb => srgb_to_hwb(rgb),
        root.value.ColorSpace.Rgb => [rgb[0] * 255.0, rgb[1] * 255.0, rgb[2] * 255.0],
        root.value.ColorSpace.Srgb => rgb,
        root.value.ColorSpace.SrgbLinear => {
            [srgb_to_linear(rgb[0]), srgb_to_linear(rgb[1]), srgb_to_linear(rgb[2])]
        },
        _ => convert_linear(root.value.ColorSpace.Srgb, rgb, dest),
    }
}

/// dart `LabColorSpace.convert`, default arm: lab -> xyz-d50 -> onward.
function from_lab_source(lab: float[], dest: root.value.ColorSpace) -> float[] {
    match (dest) {
        root.value.ColorSpace.Lab => lab,
        root.value.ColorSpace.Lch => lab_to_lch(lab),
        _ => convert_linear(root.value.ColorSpace.XyzD50, lab_to_xyz_d50(lab), dest),
    }
}

/// dart `OklabColorSpace.convert`: an oklch destination goes through
/// `labToLch`; EVERYTHING else — including oklab itself — falls to the
/// default LMS arm (dart has no same-space case here, so an oklab
/// destination cubes into LMS and cube-roots straight back).
function from_oklab_source(oklab: float[], dest: root.value.ColorSpace) -> float[] {
    match (dest) {
        root.value.ColorSpace.Oklch => lab_to_lch(oklab),
        _ => convert_linear_from_lms(oklab_to_lms(oklab), dest),
    }
}

/// dart `ColorSpace.convertLinear` with an `Lms` source (LMS has no
/// `ColorSpace` of its own here).
function convert_linear_from_lms(lms: float[], dest: root.value.ColorSpace) -> float[] {
    let through = through_of(dest);
    let through_lin = through._0;
    let finalize = through._1;
    let transformed = if (through_lin == Lin.Lms) {
        lms
    } else {
        let m = matrix(Lin.Lms, through_lin);
        let from_linear = lin_of_through(through_lin, dest)._2;
        apply(m, lms, from_linear)
    };
    finalize_dest(transformed, dest, finalize)
}

/// dart `ColorSpace.convertLinear`: toLinear each channel, ONE matrix into the
/// destination's through-space, fromLinear each channel, then the
/// destination's special finalization.
function convert_linear(
    src: root.value.ColorSpace,
    ch: float[],
    dest: root.value.ColorSpace,
) -> float[] {
    let src_transfer = lin_of(src);
    let src_lin = src_transfer._0;
    let to_linear = src_transfer._1;
    let through = through_of(dest);
    let through_lin = through._0;
    let finalize = through._1;
    let same_space = src_lin == through_lin && through_space_equals_src(src, dest);
    let transformed = if (same_space) {
        ch
    } else {
        let linear = [to_linear(ch[0]), to_linear(ch[1]), to_linear(ch[2])];
        let from_linear = lin_of_through(through_lin, dest)._2;
        if (src_lin == through_lin) {
            [from_linear(linear[0]), from_linear(linear[1]), from_linear(linear[2])]
        } else {
            apply(matrix(src_lin, through_lin), linear, from_linear)
        }
    };
    finalize_dest(transformed, dest, finalize)
}

function apply(m: float[], v: float[], from_linear: (float) -> float throws unknown) -> float[] {
    [
        from_linear(m[0] * v[0] + m[1] * v[1] + m[2] * v[2]),
        from_linear(m[3] * v[0] + m[4] * v[1] + m[5] * v[2]),
        from_linear(m[6] * v[0] + m[7] * v[1] + m[8] * v[2]),
    ]
}

/// Which finalization the destination needs after reaching its through-space.
enum Finalize {
    None,
    Hsl,
    Hwb,
    Rgb255,
    Lab,
    Lch,
    Oklab,
    Oklch,
}

/// The linear node a destination converts THROUGH (dart's dest mapping in
/// `convertLinear`), plus its finalization step.
function through_of(dest: root.value.ColorSpace) -> root.std.Tuple2<Lin, Finalize> {
    match (dest) {
        root.value.ColorSpace.Hsl => root.std.Tuple2 { _0: Lin.Srgb, _1: Finalize.Hsl },
        root.value.ColorSpace.Hwb => root.std.Tuple2 { _0: Lin.Srgb, _1: Finalize.Hwb },
        root.value.ColorSpace.Rgb => root.std.Tuple2 { _0: Lin.Srgb, _1: Finalize.Rgb255 },
        root.value.ColorSpace.Lab => root.std.Tuple2 { _0: Lin.XyzD50, _1: Finalize.Lab },
        root.value.ColorSpace.Lch => root.std.Tuple2 { _0: Lin.XyzD50, _1: Finalize.Lch },
        root.value.ColorSpace.Oklab => root.std.Tuple2 { _0: Lin.Lms, _1: Finalize.Oklab },
        root.value.ColorSpace.Oklch => root.std.Tuple2 { _0: Lin.Lms, _1: Finalize.Oklch },
        _ => root.std.Tuple2 { _0: lin_of(dest)._0, _1: Finalize.None },
    }
}

/// Whether dart's `t2 === _this` short-circuit applies: the destination's
/// through-SPACE (not just node) is the source space, so the channels pass
/// through untouched (e.g. srgb -> hsl skips the linear round-trip).
function through_space_equals_src(src: root.value.ColorSpace, dest: root.value.ColorSpace) -> bool {
    let through_space: root.value.ColorSpace = match (dest) {
        root.value.ColorSpace.Hsl | root.value.ColorSpace.Hwb | root.value.ColorSpace.Rgb => {
            root.value.ColorSpace.Srgb
        },
        root.value.ColorSpace.Lab | root.value.ColorSpace.Lch => root.value.ColorSpace.XyzD50,
        // Oklab/Oklch go through LMS, which no ColorSpace equals.
        root.value.ColorSpace.Oklab | root.value.ColorSpace.Oklch => {
            return false;
        },
        let other => other,
    };
    through_space == src
}

/// The fromLinear of the through-space (hsl/hwb/rgb255 finalize from srgb,
/// lab/lch from xyz-d50, oklab/oklch from LMS — all with their through-space
/// transfer, which for the hubs is the identity).
function lin_of_through(through: Lin, dest: root.value.ColorSpace) -> LinTransfer {
    match (through) {
        Lin.Srgb => match (dest) {
            // The srgb-through destinations apply srgb's own transfer.
            root.value.ColorSpace.SrgbLinear => {
                lin_transfer(Lin.Srgb, lin_of_through__id, lin_of_through__id)
            },
            _ => lin_transfer(Lin.Srgb, srgb_to_linear, srgb_from_linear),
        },
        Lin.DisplayP3 => match (dest) {
            root.value.ColorSpace.DisplayP3Linear => {
                lin_transfer(Lin.DisplayP3, lin_of_through__id, lin_of_through__id)
            },
            _ => lin_transfer(Lin.DisplayP3, srgb_to_linear, srgb_from_linear),
        },
        Lin.A98 => lin_transfer(Lin.A98, a98_to_linear, a98_from_linear),
        Lin.Prophoto => lin_transfer(Lin.Prophoto, prophoto_to_linear, prophoto_from_linear),
        Lin.Rec2020 => lin_transfer(Lin.Rec2020, rec2020_to_linear, rec2020_from_linear),
        Lin.XyzD65 | Lin.XyzD50 | Lin.Lms => {
            lin_transfer(through, lin_of_through__id, lin_of_through__id)
        },
    }
}

function lin_of_through__id(c: float) -> float {
    c
}

function finalize_dest(
    transformed: float[],
    unused_dest: root.value.ColorSpace,
    finalize: Finalize,
) -> float[] {
    match (finalize) {
        Finalize.None => transformed,
        Finalize.Hsl => srgb_to_hsl(transformed),
        Finalize.Hwb => srgb_to_hwb(transformed),
        Finalize.Rgb255 => [transformed[0] * 255.0, transformed[1] * 255.0, transformed[2] * 255.0],
        Finalize.Lab => xyz_d50_to_lab(transformed),
        Finalize.Lch => lab_to_lch(xyz_d50_to_lab(transformed)),
        Finalize.Oklab => lms_to_oklab(transformed),
        Finalize.Oklch => lab_to_lch(lms_to_oklab(transformed)),
    }
}
