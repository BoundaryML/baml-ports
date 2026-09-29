// Ported from sasso `src/builtins/color/deprecate.rs` (namespace `root.builtins.color.deprecate`).
//
// The replacement code dart-sass prints in a `[color-functions]` deprecation.
//
// Every legacy `sass:color` member Color 4 replaced carries a suggestion
// computed from the call's OWN arguments: a channel getter names the channel
// and its space, while a legacy adjuster offers `color.scale` (a relative
// move, whose percentage depends on where the colour already is) and
// `color.adjust` (the absolute one it always was). Every shape here was
// measured against dart-sass 1.103.1.

/// The suggestions for a deprecated call, or `None` when the member carries no
/// `[color-functions]` deprecation at all (`alpha`, `mix`, `grayscale`,
/// `complement` and `invert` do not).
///
/// Called only once the function itself has SUCCEEDED, which is where dart
/// raises it too — a call whose arguments are invalid warns about nothing — so
/// the arguments are known good and anything unreadable here simply yields
/// `None`.
function suggestions(
    name: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
) -> string[]? {
    let space = channel_space(name);
    if (space != null) {
        return [`color.channel($color, "${name}", $space: ${space})`];
    }
    let adj = adjuster(name);
    if (adj == null) {
        return null;
    }
    let channel = adj._0;
    let sign = adj._1;
    let param = adj._2;
    let color_v = arg(pos_args, named, 0, "color");
    if (color_v == null) {
        return null;
    }
    let amount_v = arg(pos_args, named, 1, param);
    if (amount_v == null) {
        return null;
    }
    // PORT: `let Value::Color(color) = color else { return None };` (and the
    // same for `amount`) → a `match`; the shadowed names get a `_v` suffix.
    let color = match (color_v) {
        root.value.Value_Color { _0: let c } => c,
        _ => {
            return null;
        },
    };
    let amount = match (amount_v) {
        root.value.Value_Number { _0: let n } => n,
        _ => {
            return null;
        },
    };

    // `$hue` is an angle, converted to degrees and never scaled: a hue has no
    // bound to move a fraction of the way towards.
    if (channel == "hue") {
        let deg = match (amount.unit()) {
            // PORT: Rust's `f64::to_degrees` via `root.builtins.math.f64_to_degrees`
            // (BAML's `Float.to_degrees` can differ in the last bit).
            "rad" => root.builtins.math.f64_to_degrees(amount.value),
            "grad" => amount.value * 360.0 / 400.0,
            "turn" => amount.value * 360.0,
            _ => amount.value,
        };
        return [adjust_line(channel, deg, "deg")];
    }

    // `$lightness`/`$saturation` are read and written as percentages; `$alpha`
    // is the unitless 0-1 value it is passed as.
    // PORT: `let (current, limit, unit) = match …` → a `Tuple3` taken apart.
    let current_limit_unit: root.std.Tuple3<float, float, string> = match (channel) {
        "alpha" => {
            root.std.Tuple3 { _0: root.builtins.color.math.stored_alpha(color), _1: 1.0, _2: "" }
        },
        "saturation" => root.std.Tuple3 { _0: hsl_channel(color, 1), _1: 100.0, _2: "%" },
        _ => root.std.Tuple3 { _0: hsl_channel(color, 2), _1: 100.0, _2: "%" },
    };
    let current = current_limit_unit._0;
    let limit = current_limit_unit._1;
    let unit = current_limit_unit._2;
    let signed = sign * amount.value;
    let out: string[] = [];
    // Moving by nothing scales by nothing, and dart omits the line entirely.
    if (signed != 0.0) {
        // `color.scale` moves a fraction of the way to the channel's bound, so
        // the equivalent fraction is the move over the distance left in that
        // direction — clamped, since the distance can be zero (lightening
        // white is "all the way" however much you ask for).
        let room = if (signed > 0.0) {
            limit - current
        } else {
            current
        };
        let pct = root.builtins.color_ext.clamp_f64(signed / room * 100.0, -100.0, 100.0);
        out.push(`color.scale($color, $${channel}: ${number(pct, "%")})`);
    }
    out.push(adjust_line(channel, signed, unit));
    out
}

/// The colour's saturation (`i == 1`) or lightness (`i == 2`), as a
/// percentage.
///
/// An `hsl()` colour KEEPS its channels, and dart's suggestion is derived from
/// those, not from a round trip through rgb. The difference is normally
/// invisible, but the scale percentage divides by the room left in the channel
/// — so against a colour at 99.9999% saturation it is the difference between
/// dart's `9.9999999997%` and a re-derived `9.9999999982%`. The same reading
/// the `saturation`/`lightness` getters already prefer.
function hsl_channel(color: root.value.Color, i: int) -> float {
    let m = color.modern;
    if (m != null) {
        if (m.space == root.value.ColorSpace.Hsl) {
            return m.channels[i] ?? 0.0;
        }
    }
    let hsl = color.to_hsl();
    let channel = if (i == 1) {
        hsl._1
    } else {
        hsl._2
    };
    channel * 100.0
}

/// `color.adjust($color, $<channel>: <amount>)`.
function adjust_line(channel: string, amount: float, unit: string) -> string {
    `color.adjust($color, $${channel}: ${number(amount, unit)})`
}

/// A number in the spelling Sass would write it, which is what dart embeds in
/// the suggestion.
function number(value: float, unit: string) -> string {
    let v: root.value.Value = root.value.Value_Number { _0: root.value.Number.with_unit(value, unit) };
    v.to_css(false)
}

/// The space a deprecated channel getter reads its channel from. dart names it
/// explicitly in the suggestion because `color.channel` defaults to the
/// colour's own space, which a legacy colour does not pin down.
function channel_space(name: string) -> string? {
    match (name) {
        "red" | "green" | "blue" => "rgb",
        "hue" | "saturation" | "lightness" => "hsl",
        "whiteness" | "blackness" => "hwb",
        _ => null,
    }
}

/// The channel a legacy adjuster moves, the direction it moves it, and the
/// name of the parameter carrying the amount.
///
/// The pairs differ only by sign (`darken` is `lighten` negated), and dart's
/// suggestion spells the signed amount. The parameter name is not uniform:
/// `adjust-hue` binds `$degrees` where the rest bind `$amount`, and reading
/// the wrong one loses the warning entirely for a call that names it.
function adjuster(name: string) -> root.std.Tuple3<string, float, string>? {
    let r: root.std.Tuple3<string, float, string> = match (name) {
        "lighten" => root.std.Tuple3 { _0: "lightness", _1: 1.0, _2: "amount" },
        "darken" => root.std.Tuple3 { _0: "lightness", _1: -1.0, _2: "amount" },
        "saturate" => root.std.Tuple3 { _0: "saturation", _1: 1.0, _2: "amount" },
        "desaturate" => root.std.Tuple3 { _0: "saturation", _1: -1.0, _2: "amount" },
        "opacify" | "fade-in" => root.std.Tuple3 { _0: "alpha", _1: 1.0, _2: "amount" },
        "transparentize" | "fade-out" => root.std.Tuple3 { _0: "alpha", _1: -1.0, _2: "amount" },
        "adjust-hue" => root.std.Tuple3 { _0: "hue", _1: 1.0, _2: "degrees" },
        _ => {
            return null;
        },
    };
    r
}

/// The `i`th argument, positionally or by name — the same binding the function
/// itself used.
function arg(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    i: int,
    name: string,
) -> root.value.Value? {
    pos_args.at(i)
        ?? named
            .find((t) -> {
                t._0 == name
            })
            ?._1
}

/// Whether `name` is a legacy colour member that [`suggestions`] describes —
/// the name-only half of that test, so a caller can reject a call before doing
/// any colour maths. Must stay in lockstep with [`suggestions`]: both are
/// exactly the union of the `channel_space` and `adjuster` tables.
function deprecates(name: string) -> bool {
    channel_space(name) != null || adjuster(name) != null
}
