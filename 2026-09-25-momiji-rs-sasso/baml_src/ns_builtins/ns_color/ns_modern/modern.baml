// Ported from sasso `src/builtins/color/modern.rs` (namespace `root.builtins.color.modern`).

/// The modern CSS Color 4 `sass:color` members this submodule owns by name
/// (the single source of truth, mirroring the `try_call_modern` match arms
/// below). Folded into the family's [`super::NAMES`].
function NAMES() -> string[] {
    [
        "color-space",
        "color-channel",
        "color-to-space",
        "color-is-legacy",
        "color-is-missing",
        "color-is-in-gamut",
        "color-is-powerless",
        "color-to-gamut",
        "color-same",
    ]
}

function try_call_modern(
    name: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> (root.std.Ok<root.value.Value> | root.std.Err<root.error.Error>)? {
    // PORT: each arm's `Result` is held as a value (`Ok`/`Err`): a thrown
    // `Error` is caught into `Err`; an unknown name returns `null` (`None`).
    let result: root.std.Ok<root.value.Value> | root.std.Err<root.error.Error> = {
        root.std.Ok {
            value: match (name) {
                "color-space" => fn_space(pos_args, named, pos),
                "color-channel" => fn_color_channel(pos_args, named, pos),
                "color-to-space" => fn_to_space(pos_args, named, pos),
                "color-is-legacy" => fn_is_legacy(pos_args, named, pos),
                "color-is-missing" => fn_is_missing(pos_args, named, pos),
                "color-is-in-gamut" => fn_is_in_gamut(pos_args, named, pos),
                "color-is-powerless" => fn_is_powerless(pos_args, named, pos),
                "color-to-gamut" => fn_to_gamut(pos_args, named, pos),
                "color-same" => fn_same(pos_args, named, pos),
                _ => {
                    return null;
                },
            },
        }
    } catch (e) {
        let err: root.error.Error => root.std.Err { error: err }
    };
    result
}

/// Read a channel-name argument. dart-sass requires it to be a *quoted*
/// string: an unquoted string (`hue`) errors "Expected … to be a quoted
/// string"; a non-string errors "… is not a string".
function channel_name_arg(v: root.value.Value, pos: root.scanner.Pos) -> string {
    match (v) {
        root.value.Value_Str { _0: let s } if s.quoted => s.text,
        root.value.Value_Str { _0: let s } => {
            throw root.error.Error.at(
                `$channel: Expected ${s.text} to be a quoted string.`,
                pos,
            );
        },
        let other => {
            throw root.error.Error.at(
                `$channel: ${other.to_css(false)} is not a string.`,
                pos,
            );
        },
    }
}

function fn_space(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["color"];
    root.builtins.check_arity(params.length(), pos_args, named, pos);
    let c = root.builtins.as_color(root.builtins.require(params, pos_args, named, 0, pos), pos);
    root.value.Value_Str {
        _0: root.value.SassStr {
            text: root.builtins.color.math.color_space_of(c).name(),
            quoted: false,
        },
    }
}

function fn_is_legacy(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["color"];
    root.builtins.check_arity(params.length(), pos_args, named, pos);
    let c = root.builtins.as_color(root.builtins.require(params, pos_args, named, 0, pos), pos);
    root.value.Value_Bool { _0: root.builtins.color.math.color_space_of(c).is_legacy() }
}

function fn_to_space(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["color", "space"];
    root.builtins.check_arity(2, pos_args, named, pos);
    let c = root.builtins.as_color(root.builtins.require(params, pos_args, named, 0, pos), pos);
    let space = root.builtins.color.math.space_arg(root.builtins.require(params, pos_args, named, 1, pos), pos);
    let mc = root.builtins.color.math.legacy_to_modern(c);
    if (mc.space == space) {
        return root.value.Value_Color { _0: c };
    }
    let out = root.builtins.color.math.convert_to_space(mc, space);
    root.value.Value_Color { _0: root.builtins.color.math.make_modern_in(out, space) }
}

function fn_color_channel(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["color", "channel", "space"];
    root.builtins.check_arity(3, pos_args, named, pos);
    let c = root.builtins.as_color(root.builtins.require(params, pos_args, named, 0, pos), pos);
    let chan = channel_name_arg(root.builtins.require(params, pos_args, named, 1, pos), pos);
    let mc = root.builtins.color.math.legacy_to_modern(c);
    // The space to read the channel in: explicit `$space`, else the color's own.
    let space = match (root.builtins.arg(params, pos_args, named, 2)) {
        let v: root.value.Value => root.builtins.color.math.space_arg(v, pos),
        null => mc.space,
    };
    if (chan == "alpha") {
        let a = mc.alpha ?? 0.0;
        return root.value.Value_Number { _0: root.value.Number.unitless(a) };
    }
    let target = root.builtins.color.math.convert_modern(mc, space);
    let idx = root.builtins.color.math.channel_index_in(space, chan);
    if (idx == null) {
        throw root.error.Error.at(
            // dart interpolates the color with `Value.toString()`, i.e. the
            // INSPECT serializer, not CSS output (lib/src/value.dart:439;
            // message at lib/src/functions/color.dart:699).
            `$channel: Color ${c.inspect_css()} has no channel named ${chan}.`,
            pos,
        );
    }
    // dart reads the stored channel verbatim: hwb normalization happens at
    // CONSTRUCTION (and on `change`), so an `adjust`/`scale` result whose
    // whiteness + blackness exceed 100 reads its raw values here.
    let raw = target.channels[idx] ?? 0.0;
    root.value.Value_Number { _0: root.builtins.color.math.channel_number(space, idx, raw) }
}

function fn_is_missing(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["color", "channel"];
    root.builtins.check_arity(params.length(), pos_args, named, pos);
    let c = root.builtins.as_color(root.builtins.require(params, pos_args, named, 0, pos), pos);
    let chan = channel_name_arg(root.builtins.require(params, pos_args, named, 1, pos), pos);
    let mc = root.builtins.color.math.legacy_to_modern(c);
    let missing = if (chan == "alpha") {
        mc.alpha == null
    } else {
        match (root.builtins.color.math.channel_index_in(mc.space, chan)) {
            let idx: int => mc.channels[idx] == null,
            null => {
                // Inspect semantics, as above: dart's message is built in
                // `SassColor.isChannelMissing` (lib/src/value/color.dart:733)
                // and interpolates `$this` through `Value.toString()`.
                throw root.error.Error.at(
                    `$channel: Color ${c.inspect_css()} doesn't have a channel named "${chan}".`,
                    pos,
                );
            },
        }
    };
    root.value.Value_Bool { _0: missing }
}

function fn_is_in_gamut(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["color", "space"];
    root.builtins.check_arity(2, pos_args, named, pos);
    let c = root.builtins.as_color(root.builtins.require(params, pos_args, named, 0, pos), pos);
    let mc = root.builtins.color.math.legacy_to_modern(c);
    let space = match (root.builtins.arg(params, pos_args, named, 1)) {
        let v: root.value.Value => root.builtins.color.math.space_arg(v, pos),
        null => mc.space,
    };
    root.value.Value_Bool { _0: root.builtins.color.math.in_gamut(mc, space) }
}

function fn_is_powerless(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["color", "channel", "space"];
    root.builtins.check_arity(3, pos_args, named, pos);
    let c = root.builtins.as_color(root.builtins.require(params, pos_args, named, 0, pos), pos);
    let chan = channel_name_arg(root.builtins.require(params, pos_args, named, 1, pos), pos);
    let mc = root.builtins.color.math.legacy_to_modern(c);
    let space = match (root.builtins.arg(params, pos_args, named, 2)) {
        let v: root.value.Value => root.builtins.color.math.space_arg(v, pos),
        null => mc.space,
    };
    let conv = root.builtins.color.math.convert_modern(mc, space);
    if (chan == "alpha") {
        return root.value.Value_Bool { _0: false };
    }
    let idx = root.builtins.color.math.channel_index_in(space, chan);
    if (idx == null) {
        // Inspect semantics, as above: dart's message is built in
        // `SassColor.isChannelPowerless` (lib/src/value/color.dart:757).
        throw root.error.Error.at(
            `$channel: Color ${c.inspect_css()} doesn't have a channel named "${chan}".`,
            pos,
        );
    }
    root.value.Value_Bool { _0: root.builtins.color.math.channel_powerless(space, idx, conv) }
}

function fn_same(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["color1", "color2"];
    root.builtins.check_arity(params.length(), pos_args, named, pos);
    let c1 = root.builtins.as_color(root.builtins.require(params, pos_args, named, 0, pos), pos);
    let c2 = root.builtins.as_color(root.builtins.require(params, pos_args, named, 1, pos), pos);
    let m1 = root.builtins.color.math.legacy_to_modern(c1);
    let m2 = root.builtins.color.math.legacy_to_modern(c2);
    // color.same compares the *realized* colors: a missing channel counts as 0
    // and is NOT carried through the conversion (the spec converts none -> 0
    // before the xyz conversion). Fill none with 0 so convert_modern yields
    // plain numbers rather than carrying missing components into xyz.
    let fill0 = (m: root.value.ModernColor) -> root.value.ModernColor {
        root.value.ModernColor {
            space: m.space,
            channels: [
                root.builtins.color.math.z(m.channels[0]),
                root.builtins.color.math.z(m.channels[1]),
                root.builtins.color.math.z(m.channels[2]),
            ],
            alpha: m.alpha,
        }
    };
    // Compare in xyz-d65 (a canonical space) with alpha.
    let x1 = root.builtins.color.math.convert_modern(fill0(m1), root.value.ColorSpace.XyzD65);
    let x2 = root.builtins.color.math.convert_modern(fill0(m2), root.value.ColorSpace.XyzD65);
    let close = (a: float, b: float) -> bool {
        (a - b).abs() < 1e-7
    };
    let same = close(root.builtins.color.math.z(x1.channels[0]), root.builtins.color.math.z(x2.channels[0]))
        && close(root.builtins.color.math.z(x1.channels[1]), root.builtins.color.math.z(x2.channels[1]))
        && close(root.builtins.color.math.z(x1.channels[2]), root.builtins.color.math.z(x2.channels[2]))
        && close(m1.alpha ?? 1.0, m2.alpha ?? 1.0);
    root.value.Value_Bool { _0: same }
}

function fn_to_gamut(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["color", "space", "method"];
    root.builtins.check_arity(params.length(), pos_args, named, pos);
    let c = root.builtins.as_color(root.builtins.require(params, pos_args, named, 0, pos), pos);
    let mc = root.builtins.color.math.legacy_to_modern(c);
    let space = match (root.builtins.arg(params, pos_args, named, 1)) {
        let v: root.value.Value => root.builtins.color.math.space_arg(v, pos),
        null => mc.space,
    };
    // `$method` is required (forwards-compatibility with the CSS spec).
    let method = match (root.builtins.arg(params, pos_args, named, 2)) {
        let v: root.value.Value => v,
        null => {
            throw root.error.Error.at(
                "$method: color.to-gamut() requires a $method argument for forwards-compatibility with changes in the CSS spec. Suggestion:\n\n$method: local-minde",
                pos,
            );
        },
    };
    let clip = match (method) {
        root.value.Value_Str { _0: let s }
            if !s.quoted && root.std.eq_ignore_ascii_case(s.text, "clip") => true,
        root.value.Value_Str { _0: let s }
            if !s.quoted && root.std.eq_ignore_ascii_case(s.text, "local-minde") => false,
        root.value.Value_Str { _0: let s } if s.quoted => {
            throw root.error.Error.at(
                `$method: Expected "${s.text}" to be an unquoted string.`,
                pos,
            );
        },
        let other => {
            throw root.error.Error.at(
                `$method: ${other.to_css(false)} must be either clip or local-minde.`,
                pos,
            );
        },
    };
    // dart returns the color untouched when the target space is unbounded.
    if (root.builtins.color.math.channel_bounds(space) == null) {
        return root.value.Value_Color { _0: c };
    }
    // dart ALWAYS round-trips: `toSpace(space)` (keeping missing channels) →
    // map only when out of gamut → `toSpace(color.space, legacyMissing:
    // false)` (zero-fills legacy missing on the way back). Even an in-gamut
    // color picks up the round-trip conversion (powerless-hue → none etc).
    let work = root.builtins.color.math.convert_modern(mc, space);
    let mapped = if (root.builtins.color.math.is_in_gamut(work)) {
        work
    } else if (clip) {
        root.builtins.color.math.clip_in_own_space(work)
    } else {
        root.builtins.color.math.gamut_map(work)
    };
    let back = root.builtins.color.math.convert_modern_filled(mapped, mc.space);
    root.value.Value_Color { _0: root.builtins.color.math.make_modern_in(back, mc.space) }
}

/// The kind of modify operation for the modern change/adjust/scale path.
enum ModifyOp {
    Change,
    Adjust,
    Scale,
}

/// The modern `color.change`/`adjust`/`scale` with an explicit `$space`:
/// convert the color to `space`, apply the per-channel operation, convert back
/// to the color's original space.
function modify_in_space(
    c: root.value.Color,
    space: root.value.ColorSpace,
    chans: root.std.Tuple2<string, root.value.Value>[],
    op: ModifyOp,
    pos: root.scanner.Pos,
) -> root.value.Value {
    modify_in_space_full(c, space, chans, op, false, true, pos)
}

/// As [`modify_in_space`], but with control over whether a *powerless* channel
/// (e.g. an hsl hue at zero saturation) counts as missing. The explicit-`$space`
/// path treats powerless channels as missing (erroring on `adjust`/`scale`); the
/// legacy keyword path operates on the color's stored channels and does not.
function modify_in_space_opt(
    c: root.value.Color,
    space: root.value.ColorSpace,
    chans: root.std.Tuple2<string, root.value.Value>[],
    op: ModifyOp,
    powerless_check: bool,
    pos: root.scanner.Pos,
) -> root.value.Value {
    modify_in_space_full(c, space, chans, op, powerless_check, false, pos)
}

/// The shared `change`/`adjust`/`scale` core. `legacy_format` selects how the
/// result is serialized: the legacy-keyword path (no `$space`) keeps the
/// original color's format when the result lands in the sRGB gamut, but falls
/// back to the working space (keeping its canonical channels) when it doesn't —
/// so e.g. `adjust(red, $lightness: 100%)` stays `hsl(0, 100%, 150%)` instead of
/// the negative-saturation rgb round-trip. The explicit-`$space`/non-legacy path
/// always converts back to the color's original space.
function modify_in_space_full(
    c: root.value.Color,
    space: root.value.ColorSpace,
    chans: root.std.Tuple2<string, root.value.Value>[],
    op: ModifyOp,
    powerless_check: bool,
    legacy_format: bool,
    pos: root.scanner.Pos,
) -> root.value.Value {
    let orig = root.builtins.color.math.legacy_to_modern(c);
    let work = root.builtins.color.math.convert_modern(orig, space);
    // A missing channel INTRODUCED by the conversion (a powerless hue from an
    // achromatic source, e.g. `black` -> hsl) is filled with 0 so modifying it
    // works (dart's working-space conversion fills legacy missing channels);
    // an AUTHORED missing channel (analogous to a source `none`) stays
    // missing, so `adjust` still errors on it and `change` still sets it.
    if (orig.space != space) {
        let missing_in_src = (cat: root.builtins.color.math.ChannelCategory) -> bool {
            root.std.range(0, 3).some((i) -> {
                orig.channels[i] == null
                    && root.builtins.color.math.channel_category(orig.space, i) == cat
            })
        };
        for (let i in baml.iter.Range.new(0, 3)) {
            if (work.channels[i] == null) {
                let cat = root.builtins.color.math.channel_category(space, i);
                let authored = if (cat != null) {
                    missing_in_src(cat)
                } else {
                    false
                };
                if (!authored) {
                    work.channels[i] = 0.0;
                }
            }
        }
    }
    // `adjust`/`scale` combine each amount with the channel's current value, so
    // a missing (`none`) channel is unsupported (dart-sass errors rather than
    // guessing). `change` *sets* the channel, so a missing channel is fine. The
    // error serializes the source color in the working space.
    let combining = op == ModifyOp.Adjust || op == ModifyOp.Scale;
    // A channel only becomes powerless-as-missing through a *conversion* (an
    // achromatic source whose hue collapses); a color already in the working
    // space keeps its explicit (if powerless) channels.
    let powerless_active = powerless_check && orig.space != space;
    // For the error message, such a powerless channel is serialized as `none`.
    let orig_work = root.builtins.color.math.clone_mc(work);
    let missing_channel_error = (name: string) -> root.error.Error {
        let color = if (powerless_active) {
            root.builtins.color.math.make_modern(
                root.builtins.color.math.null_powerless(orig_work, space),
            )
        } else {
            root.builtins.color.math.make_modern(root.builtins.color.math.clone_mc(orig_work))
        };
        missing_channel_err(name, root.value.Value_Color { _0: color }, pos)
    };
    let alpha_given = false;
    for (let entry in chans) {
        let name = entry._0;
        let v = entry._1;
        if (name == "alpha") {
            if (combining && orig_work.alpha == null) {
                throw missing_channel_error(name);
            }
            work.alpha = apply_alpha(work.alpha ?? 1.0, v, op, pos);
            alpha_given = true;
            continue;
        }
        let idx = root.builtins.color.math.channel_index_in(space, name);
        if (idx == null) {
            throw root.error.Error.at(
                `\$${name}: Color space ${space.name()} doesn't have a channel with this name.`,
                pos,
            );
        }
        // Validate the channel value's unit (skipped for a scale `%` and for a
        // `none` change keyword, handled below).
        if (op != ModifyOp.Scale && !root.builtins.color.is_none_keyword(v)) {
            root.builtins.color.math.validate_modify_unit(
                space,
                idx,
                name,
                v,
                op == ModifyOp.Change,
                pos,
            );
        }
        // `adjust`/`scale` combine each amount with the channel's current value,
        // so a missing (`none`) — or, on a conversion's powerless — channel of
        // the source color is unsupported (checked against the original, like
        // dart-sass).
        let powerless = powerless_active && root.builtins.color.math.channel_powerless(space, idx, orig_work);
        if (combining && (orig_work.channels[idx] == null || powerless)) {
            throw missing_channel_error(name);
        }
        match (op) {
            ModifyOp.Change => {
                if (root.builtins.color.is_none_keyword(v)) {
                    work.channels[idx] = null;
                } else {
                    work.channels[idx]
                        = root.builtins.color.math.modify_channel_value(space, idx, v);
                }
            },
            ModifyOp.Adjust => {
                let amt = root.builtins.color.math.modify_channel_value(space, idx, v) ?? 0.0;
                let cur = work.channels[idx] ?? 0.0;
                work.channels[idx]
                    = root.builtins.color.math.clamp_adjust_channel(space, idx, cur + amt);
            },
            ModifyOp.Scale => {
                let bounds = root.builtins.color.math.scale_bounds(space, idx);
                if (bounds == null) {
                    throw root.error.Error.at(`\$${name}: Channel isn't scalable.`, pos);
                }
                let factor = root.builtins.color.math.scale_pct(name, v, pos);
                let cur = work.channels[idx] ?? 0.0;
                work.channels[idx] = root.builtins.color.math.scale_to(cur, factor, bounds);
            },
        }
    }
    // `change` rebuilds through the hwb constructor in dart, which normalizes
    // a whiteness + blackness sum past 100; `adjust`/`scale` keep raw values.
    if (op == ModifyOp.Change && space == root.value.ColorSpace.Hwb) {
        // PORT: `if let (Some(wv), Some(bv)) = (…)` → two locals and nested `if`s.
        let wv = work.channels[1];
        let bv = work.channels[2];
        if (wv != null) {
            if (bv != null) {
                if (root.builtins.color.math.f_gt(wv + bv, 100.0)) {
                    let t = wv + bv;
                    work.channels[1] = wv / t * 100.0;
                    work.channels[2] = bv / t * 100.0;
                }
            }
        }
    }
    // dart rebuilds a `change` result with `alpha ?? color.alpha`, and that
    // getter answers 0 for a missing alpha — so `change` hands back a CONCRETE
    // alpha even when it was missing and even when no channel was named
    // (`color.change(hsl(240 100% 50% / none), $lightness: 60%)` is
    // `hsla(240, 100%, 60%, 0)`). Only an explicit `$alpha: none` keeps it
    // missing. `adjust`/`scale` errored on a missing alpha long before here.
    if (op == ModifyOp.Change && !alpha_given) {
        work.alpha = work.alpha ?? 0.0;
    }
    // dart-sass builds the modified color in the WORKING space -- through
    // `SassColor.forSpaceInternal` -- and only then converts it back, so the
    // whole of 1.104.0's channel normalization applies to the new channel
    // VALUES. `change(red, $hue: NaN)` is `hsl(0, 100%, 50%)`, i.e. red again,
    // not the black an unnormalized NaN hue would convert to; and a polar hue
    // is reduced into `[0, 360)` BEFORE the conversion reads it, which only a
    // conversion can observe: `(390 % 360) / 360` is exactly `1/12` while
    // `(390 / 360) % 1` is an ulp short, and that ulp is the difference between
    // `color.complement(rgba(10, 20, 30, 0.4))` writing `rgba(30, 20, 10, 0.4)`
    // and writing a percentage triple.
    let work = root.builtins.color.math.normalize_polar(work);
    // The legacy-keyword path keeps the original format when the result is in
    // the sRGB gamut, otherwise serializes in the (legacy) working space.
    let dest = if (legacy_format && !root.builtins.color.math.in_gamut(work, root.value.ColorSpace.Rgb)) {
        space
    } else {
        orig.space
    };
    // Result leg: a legacy destination fills missing channels.
    let back = root.builtins.color.math.convert_modern_filled(work, dest);
    root.value.Value_Color { _0: root.builtins.color.math.make_modern_in(back, dest) }
}

/// The "modifying a missing channel" error dart-sass raises when `adjust`/
/// `scale` is applied to a `none` channel. `color` is the source color
/// serialized in the working space.
function missing_channel_err(
    name: string,
    color: root.value.Value,
    pos: root.scanner.Pos,
) -> root.error.Error {
    root.error.Error.at(
        `\$${name}: Because the CSS working group is still deciding on the best behavior, Sass doesn't currently support modifying missing channels (color: ${color.to_css(false)}).`,
        pos,
    )
}

/// Apply a change/adjust/scale to the alpha channel. Returns `None` for a
/// `change` to `none`.
function apply_alpha(
    cur: float,
    v: root.value.Value,
    op: ModifyOp,
    pos: root.scanner.Pos,
) -> float? {
    match (op) {
        ModifyOp.Change => {
            if (root.builtins.color.is_none_keyword(v)) {
                return null;
            }
            // `change` validates the alpha is within [0,1] (or [0%,100%]). A
            // non-`%` unit is used as a raw value (within [0,1]); the bounds in
            // the error message carry that unit (e.g. `0px and 1px`).
            // PORT: the `Value::Number(n) | Value::Slash(n, _)` or-pattern binds
            // `n` across two variants, which BAML rejects: `n` is bound first
            // (one arm per variant), then the shared arm body runs.
            let n: root.value.Number = match (v) {
                // One arm for both spellings, as in `alpha_value`: a
                // slash-division's quotient is validated like any number. (A
                // named `$alpha:` argument has already evaluated to a number,
                // so nothing reaches here as a `Slash` today.)
                root.value.Value_Number { _0: let n } => n,
                root.value.Value_Slash { _0: let n } => n,
                let other => {
                    throw root.error.Error.at(
                        `$alpha: ${other.to_css(false)} is not a number or unquoted "none".`,
                        pos,
                    );
                },
            };
            // A COMPOUND unit only reports its first numerator, so it
            // is not the percentage it starts with: `50%/2px` is a
            // `%/px` value bounded at 1, not a 25% alpha.
            let pct = !n.has_complex_units() && n.unit() == "%";
            let max_disp = if (pct) {
                100.0
            } else {
                1.0
            };
            if (n.value.is_nan() || n.value < 0.0 || n.value > max_disp) {
                let bs: root.std.Tuple2<string, string> = if (pct) {
                    root.std.Tuple2 { _0: "0%", _1: "100%" }
                } else {
                    let u = n.unit_string();
                    root.std.Tuple2 { _0: `0${u}`, _1: `1${u}` }
                };
                let b0 = bs._0;
                let b1 = bs._1;
                throw root.error.Error.at(
                    `$alpha: Expected ${n.to_css(false)} to be within ${b0} and ${b1}.`,
                    pos,
                );
            }
            if (pct) {
                n.value / 100.0
            } else {
                n.value
            }
        },
        ModifyOp.Adjust => {
            // Alpha is natively unitless: dart-sass strips any unit (warning to
            // stderr for `%`/other units) and uses the raw number directly. A
            // non-number amount (including `none`) is an error.
            let amt = match (v) {
                root.value.Value_Number { _0: let n } => n.value,
                root.value.Value_Slash { _0: let n } => n.value,
                let other => {
                    throw root.error.Error.at(
                        `$alpha: ${other.to_css(false)} is not a number.`,
                        pos,
                    );
                },
            };
            root.builtins.color.math.f_clamp(cur + amt, 0.0, 1.0)
        },
        ModifyOp.Scale => {
            let factor = root.builtins.color.math.scale_pct("alpha", v, pos);
            root.builtins.color.math.scale_to(cur, factor, root.std.Tuple2 { _0: 0.0, _1: 1.0 })
        },
    }
}

/// CSS Color 4 `color.invert($color, $weight, $space)`: invert each channel in
/// `space` (mixing toward the original by `1 - weight`), then convert back to
/// the color's original space.
function invert_in_space(
    c: root.value.Color,
    space: root.value.ColorSpace,
    weight: float,
    powerless_check: bool,
    pos: root.scanner.Pos,
) -> root.value.Color {
    let orig = root.builtins.color.math.legacy_to_modern(c);
    let dest = orig.space;
    let src = root.builtins.color.math.convert_modern(orig, space);
    // A channel only becomes powerless-as-missing through a *conversion*.
    let powerless_active = powerless_check && orig.space != space;
    // Inverting transforms each *modified* channel using its current value, so a
    // missing (`none`) — or, after a conversion, powerless — channel is
    // unsupported. Pass-through channels (e.g. hsl saturation, lch chroma, the
    // hwb whiteness/blackness swap) are exempt. Report the first offending
    // channel in storage order, like dart-sass.
    for (let idx in baml.iter.Range.new(0, 3)) {
        if (!root.builtins.color.math.invert_modifies(space, idx)) {
            continue;
        }
        let powerless = powerless_active && root.builtins.color.math.channel_powerless(space, idx, src);
        if (src.channels[idx] == null || powerless) {
            let name = space.channel_names()[idx];
            let color = if (powerless_active) {
                root.builtins.color.math.make_modern(
                    root.builtins.color.math.null_powerless(src, space),
                )
            } else {
                root.builtins.color.math.make_modern(root.builtins.color.math.clone_mc(src))
            };
            throw missing_channel_err(name, root.value.Value_Color { _0: color }, pos);
        }
    }
    let inverted = root.builtins.color.math.invert_channels(space, src);
    // A full-weight invert IS the inverted color (no mixing) — mixing would
    // resurrect a missing channel from the original via the interpolation
    // missing-takes-other rule.
    if ((weight - 1.0).abs() < 1e-11) {
        let back = root.builtins.color.math.convert_modern_filled(inverted, dest);
        // Like `change` and `grayscale`, the rebuilt color carries a concrete
        // alpha even when no conversion resolved it:
        // `invert(oklch(50% 0.1 20deg / none), $space: oklch)` is `/ 0`.
        back.alpha = back.alpha ?? 0.0;
        return root.builtins.color.math.make_modern_in(back, dest);
    }
    // Mix the inverted color toward the original by `1 - weight` (per channel).
    let mix = (a: float?, b: float?, hue: bool) -> float? {
        // PORT: `match (a, b)` → nested `if`s.
        if (a != null) {
            if (b != null) {
                let x = a;
                let y = b;
                return if (hue) {
                    root.builtins.color.math.interpolate_hue(
                        x,
                        y,
                        weight,
                        root.builtins.color.legacy.HueMethod.Shorter,
                    )
                } else {
                    x * weight + y * (1.0 - weight)
                };
            }
        }
        a ?? b
    };
    let hue_idx: int? = match (space) {
        root.value.ColorSpace.Hsl | root.value.ColorSpace.Hwb => 0,
        root.value.ColorSpace.Lch | root.value.ColorSpace.Oklch => 2,
        _ => null,
    };
    let channels: (float?)[] = [
        mix(inverted.channels[0], src.channels[0], hue_idx == 0),
        mix(inverted.channels[1], src.channels[1], hue_idx == 1),
        mix(inverted.channels[2], src.channels[2], hue_idx == 2),
    ];
    let mc = root.value.ModernColor { space: space, channels: channels, alpha: src.alpha };
    // Result leg: a legacy destination fills missing channels (incl. a hue
    // the working-space round trip made powerless).
    let back = root.builtins.color.math.convert_modern_filled(mc, dest);
    root.builtins.color.math.make_modern_in(back, dest)
}

/// `color.grayscale` for a non-legacy color: set the oklch chroma to 0 (a
/// perceptual gray), then convert back to the color's own space.
function grayscale_modern(c: root.value.Color) -> root.value.Color {
    let orig = root.builtins.color.math.legacy_to_modern(c);
    let dest = orig.space;
    let oklch = root.builtins.color.math.convert_modern(orig, root.value.ColorSpace.Oklch);
    oklch.channels[1] = 0.0;
    let back = root.builtins.color.math.convert_modern(oklch, dest);
    // Like `change`, the rebuilt color carries a concrete alpha:
    // `grayscale(hsl(240 100% 50% / none))` is `hsla(240, 100%, 50%, 0)`.
    back.alpha = back.alpha ?? 0.0;
    root.builtins.color.math.make_modern_in(back, dest)
}
