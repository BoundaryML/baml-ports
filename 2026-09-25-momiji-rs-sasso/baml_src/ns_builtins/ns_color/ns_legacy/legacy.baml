// Ported from sasso `src/builtins/color/legacy.rs` (namespace `root.builtins.color.legacy`).

function fn_rgb(
    name: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["red", "green", "blue", "alpha"];
    root.builtins.check_arity(4, pos_args, named, pos);
    // rgb($color, $alpha) two-argument form: a concrete color and an alpha.
    // The result is a computed color (serialized by name/hex/rgba), not the
    // literal rgb() spelling. When either argument is a special value the
    // call is preserved verbatim instead. The arguments may be passed by name
    // (`rgb($color: red, $alpha: 0.5)`).
    let color_alpha = legacy_color_alpha(pos_args, named);
    if (color_alpha != null) {
        let color = color_alpha._0;
        let alpha = color_alpha._1;
        // A special first argument (`var()`) is not a color but the call is
        // preserved verbatim by the channels passthrough below; everything
        // else binding to `$color` must be a real color, matching dart's
        // legacy `rgb($color, $alpha)` overload.
        if let cv: root.value.Value_Color = color {
            let c = cv._0;
            if (root.builtins.color.is_special_legacy(alpha)) {
                // A special alpha (`var()`/`env()` or a non-foldable `calc()`
                // such as `calc(var(--a))`) keeps the call opaque, so dart-sass
                // echoes the spelling the caller wrote: `rgb(blue, calc(var(--a)))`
                // stays `rgb`, `rgba(blue, var(--a))` stays `rgba`. (A `calc()`
                // that folds to a number, e.g. `calc(0.4)`, is a `Value::Number`
                // before this point and never reaches this branch — it resolves
                // to a real color via the `computed` path below, where the
                // `rgb`/`rgba` spelling is chosen by the alpha value.)
                let r: root.value.Value = root.value.Value_Number { _0: int_num(c.r) };
                let g: root.value.Value = root.value.Value_Number { _0: int_num(c.g) };
                let b: root.value.Value = root.value.Value_Number { _0: int_num(c.b) };
                return root.builtins.color.special_call(name, [r, g, b, alpha]);
            }
            let a = root.builtins.color.alpha_value(alpha, pos);
            return root.value.Value_Color { _0: root.builtins.color_ext.computed(c.r, c.g, c.b, a) };
        }
        // The `$color` must be a real color. dart's legacy `rgb($color,
        // $alpha)` overload only short-circuits to a verbatim passthrough when
        // an argument is specifically a `var()` (not `env()`/`calc()`/any other
        // special), so `rgb(1, var(--foo))` is preserved but `rgb(1, env(--x))`
        // and `rgb(env(--x), 0.5)` both error. A `var()` here falls through to
        // the channels passthrough below, which re-serializes the call.
        if (!root.builtins.color.is_var(color) && !root.builtins.color.is_var(alpha)) {
            throw root.error.Error.at(`$color: ${color.to_inspect_message()} is not a color.`, pos);
        }
    }
    // Otherwise gather the channel list and an optional alpha.
    let channels = Channels.collect(params, pos_args, named, pos);
    // The special/relative passthroughs echo the spelling the caller used
    // (`rgb` vs `rgba`), matching dart-sass; the `none`-only passthrough inside
    // `special_passthrough` normalizes to the canonical `rgb`.
    if let verbatim: root.value.Value = channels.relative_passthrough(name) {
        return verbatim;
    }
    if let c: root.value.Value = legacy_none_color(channels, root.value.ColorSpace.Rgb, pos) {
        return c;
    }
    if let verbatim: root.value.Value = channels.special_passthrough(name, "rgb") {
        return verbatim;
    }
    channels.validate_numeric(["red", "green", "blue"], pos);
    channels.validate_positional_numeric(["red", "green", "blue"], pos);
    root.builtins.color.validate_alpha_unit(channels.alpha, pos);
    channels.validate_count("rgb", pos);
    channels.validate_rgb_units(["red", "green", "blue"], pos);
    let comps = channels.comps;
    let alpha = channels.alpha;
    // PORT: `let z = crate::value::without_negative_zero;` → a closure.
    let z = (v: float) -> float {
        root.value.without_negative_zero(v)
    };
    let r = z(rgb_channel(comps[0], pos));
    let g = z(rgb_channel(comps[1], pos));
    let b = z(rgb_channel(comps[2], pos));
    let a = if (alpha != null) {
        z(root.builtins.color.alpha_value(alpha, pos))
    } else {
        1.0
    };
    let c = root.value.Color.rgb(r, g, b, a);
    // rgb()/rgba() literals keep their function representation, matching
    // dart-sass (the channels form never collapses to a hex spelling).
    //
    // An ALL-INTEGER triple only: dart re-spells a triple with any non-integral
    // channel as percentages (`rgb(127.5, 0, 127.5)` -> `rgb(50%, 0%, 50%)`),
    // so leave `repr` unset there and let `Color::to_css` apply that rule.
    // PORT: IEEE comparisons (`root.std.flt/fge`) since BAML orders NaN (guide §15).
    let as_int = (v: float) -> bool {
        root.std.flt((v - v.round()).abs(), 1e-11)
            && (root.std.fge(v, 0.0) && root.std.flt(v, 256.0))
    };
    if (as_int(r) && as_int(g) && as_int(b)) {
        c.repr = rgb_repr(r, g, b, a);
    }
    root.value.Value_Color { _0: c }
}

/// A whole number as a unitless [`Number`] (for re-serializing a color's
/// channels in a special-value passthrough call).
function int_num(v: float) -> root.value.Number {
    root.value.Number.unitless(v.round())
}

/// Bind a two-argument legacy `rgb`/`rgba` call to the `rgb($color, $alpha)`
/// overload, returning `(color, alpha)` when it cleanly fits and `None`
/// otherwise (so the caller falls through to the `$channels` path, which
/// preserves a special-value first argument and reports the channel-shape
/// errors dart raises for the other overloads).
///
/// dart resolves a two-argument call to this overload only when both
/// parameters bind: positionally (`rgb(c, a)`) or by the exact names
/// `$color`/`$alpha` (`rgb($color: c, $alpha: a)`, in any order, including a
/// positional `$color` plus a named `$alpha`). Any other named argument
/// (`$green`, `$red`, …) or a positional/named collision leaves the overload
/// unbound — dart then reports `Missing argument $channels.` /
/// `No parameter named $X.` from the `$channels` overload, which the existing
/// channel-collection path already produces (an exit-code match).
function legacy_color_alpha(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
) -> root.std.Tuple2<root.value.Value, root.value.Value>? {
    if (pos_args.length() + named.length() != 2) {
        return null;
    }
    let by_name = (key: string) -> root.value.Value? {
        let found = named.find((kv) -> {
            kv._0 == key
        });
        if (found != null) {
            found._1
        } else {
            null
        }
    };
    // Every named argument must be one of the overload's parameters, and must
    // not duplicate a parameter already filled positionally.
    for (let kv in named) {
        let k = kv._0;
        if (k != "color" && k != "alpha") {
            return null;
        }
        let filled_positionally = (k == "color" && pos_args.length() != 0) || (k == "alpha" && pos_args.length() >= 2);
        if (filled_positionally) {
            return null;
        }
    }
    let color = pos_args.at(0) ?? by_name("color");
    if (color == null) {
        return null;
    }
    let alpha = pos_args.at(1) ?? by_name("alpha");
    if (alpha == null) {
        return null;
    }
    root.std.Tuple2<root.value.Value, root.value.Value> { _0: color, _1: alpha }
}

/// Read an rgb channel value (`0..=255`): a `%` is taken as a fraction of
/// 255. NaN maps to 0, `±Infinity` clamp to the bounds. Delegates to the
/// shared [`channel`] helper for the finite case, then normalizes NaN.
function rgb_channel(v: root.value.Value, pos: root.scanner.Pos) -> float {
    // The degenerate check comes FIRST, whatever spelling the channel has:
    // `channel` clamps, and a clamp keeps a NaN, so `rgb(0/0 0 0)` would
    // serialize one instead of the `rgb(0, 0, 0)` dart-sass gives.
    let c = root.builtins.color.degenerate_value(v);
    if (c != null) {
        if (c.is_nan()) {
            return 0.0;
        }
        return clamp_finite(c, 0.0, 255.0);
    }
    // A finite slash-division's quotient goes through the same unit handling
    // as a literal number, so `50%/2` is 25% of 255 — not the raw 25.
    if let sl: root.value.Value_Slash = v {
        return root.builtins.channel(root.value.Value_Number { _0: sl._0 }, pos);
    }
    root.builtins.channel(v, pos)
}

/// Clamp to `[lo, hi]`, mapping NaN to `lo` (matching dart-sass's channel
/// clamping, where `calc(NaN)` becomes the lower bound).
function clamp_finite(v: float, lo: float, hi: float) -> float {
    if (v.is_nan()) {
        lo
    } else {
        root.std.fclamp(v, lo, hi)
    }
}

/// The parsed channel arguments of a legacy color function, normalized from
/// either the three-positional form (`rgb(1, 2, 3)`) or the one-argument
/// channels form (`rgb(1 2 3)`, `rgb(1 2 3 / 0.5)`).
class Channels {
    /// The (up to three) channel component values.
    comps: root.value.Value[],
    /// The alpha value, if one was supplied.
    alpha: root.value.Value?,
    /// The original single channels value when this came from the one-argument
    /// form, used to re-serialize a verbatim passthrough.
    single: root.value.Value?,
    /// Whether `alpha` was peeled from the trailing item of `single` (a
    /// `… / alpha` slash). A verbatim passthrough then re-serializes `single`
    /// (which still holds the glued alpha) rather than reconstructing a comma
    /// call from the components plus a separate alpha.
    alpha_split: bool,
    /// Gather the channel components and optional alpha. The three- and
    /// four-positional forms map directly; a single positional/named argument
    /// is treated as a channels list, splitting a trailing slash-division
    /// (`1 2 3 / 0.5`) into components plus alpha.
    function collect(
        params: string[],
        pos_args: root.value.Value[],
        named: root.std.Tuple2<string, root.value.Value>[],
        pos: root.scanner.Pos,
    ) -> Channels {
        let count = pos_args.length() + named.length();
        if (count >= 3) {
            let c0 = root.builtins.require(params, pos_args, named, 0, pos);
            let c1 = root.builtins.require(params, pos_args, named, 1, pos);
            let c2 = root.builtins.require(params, pos_args, named, 2, pos);
            let alpha = root.builtins.arg(params, pos_args, named, 3);
            return Channels { comps: [c0, c1, c2], alpha: alpha, single: null, alpha_split: false };
        }
        // One argument: a channels value. dart-sass also accepts this single
        // value under the name `$channels` (`hsl($channels: 0 100% 50%)`); a
        // second positional/`$alpha` argument is an explicit alpha for a
        // special-value channels list.
        let first = root.builtins.arg(params, pos_args, named, 0);
        let channels: root.value.Value = if (first != null) {
            first
        } else {
            let found = named.find((n) -> {
                n._0 == "channels"
            });
            if (found == null) {
                throw root.error.Error.at("Missing argument $channels.", pos);
            }
            found._1
        };
        // A channels list must be unbracketed and space/slash-separated. A
        // bracketed and/or comma list is rejected with dart-sass's message.
        if let lv: root.value.Value_List = channels {
            let l = lv._0;
            let comma = l.sep == root.value.ListSep.Comma;
            if (l.bracketed || comma) {
                let kind = if (l.bracketed && comma) {
                    "an unbracketed, space- or slash-separated list"
                } else if (l.bracketed) {
                    "an unbracketed list"
                } else {
                    "a space- or slash-separated list"
                };
                // A bracketed list serializes with its own `[...]`; a bare
                // (unbracketed) comma list is shown parenthesized, matching
                // dart-sass (`(1, 2, 3)`).
                let shown = if (l.bracketed) {
                    channels.to_css(false)
                } else {
                    root.builtins.color.list_paren_css(channels)
                };
                throw root.error.Error.at(`$channels: Expected ${kind}, was ${shown}`, pos);
            }
        }
        let extra_alpha = root.builtins.arg(params, pos_args, named, 1);
        let split = split_channels(channels);
        let comps = split.comps;
        let alpha = split.alpha;
        let alpha_split = split.alpha_split;
        if (extra_alpha != null) {
            alpha = extra_alpha;
            // An explicit `$alpha` is not part of the `single` spelling, so a
            // verbatim passthrough must reconstruct rather than re-serialize.
            alpha_split = false;
        }
        Channels { comps: comps, alpha: alpha, single: channels, alpha_split: alpha_split }
    }

    /// The POSITIONAL form's all-numeric pass: it skips `validate_numeric`,
    /// so confirm every channel is a number first, with dart's `$<param>:`
    /// prefix — which the bare [`channel`]/[`num`] readers do not attach. dart
    /// runs this before any unit is examined, so a non-number channel is
    /// reported ahead of a later bad-unit one.
    function validate_positional_numeric(self, names: string[], pos: root.scanner.Pos) -> void {
        if (self.single != null) {
            return;
        }
        for (let i in baml.iter.Range.new(0, self.comps.length())) {
            let comp = self.comps[i];
            let numeric = comp is root.value.Value_Number
                || comp is root.value.Value_Slash
                || root.builtins.color.is_degenerate_calc(comp);
            if (!numeric) {
                throw root.error.Error.at(
                    `$${names[root.std.imin(i, names.length() - 1)]}: ${root.builtins.color.channel_err_css(comp)} is not a number.`,
                    pos,
                );
            }
        }
    }

    /// Validate that every channel of a single-argument channels list is a
    /// number, matching dart-sass's per-channel check. A non-number channel
    /// (a plain string such as a non-`from` relative keyword, e.g.
    /// `rgb(c #aaa r g b)`) reports `Expected <name> channel to be a number,
    /// was X` before the channel-count check. Special/`none` channels are
    /// handled earlier by [`Channels::special_passthrough`], so callers run
    /// this only after it returns `None`; the positional forms (`single ==
    /// None`) keep their own per-argument errors.
    function validate_numeric(self, names: string[], pos: root.scanner.Pos) -> void {
        if (self.single == null) {
            return;
        }
        for (let i in baml.iter.Range.new(0, self.comps.length())) {
            let comp = self.comps[i];
            // A degenerate `calc()` is a valid (NaN/infinity) channel value, so
            // it is left for the count/compute path rather than reported here.
            let numeric = comp is root.value.Value_Number
                || comp is root.value.Value_Slash
                || root.builtins.color.is_degenerate_calc(comp)
                || root.builtins.color.is_none_keyword(comp);
            if (!numeric) {
                throw root.error.Error.at(
                    `$channels: Expected ${root.builtins.color.legacy_channel_name(names, i)} to be a number, was ${root.builtins.color.channel_err_css(comp)}.`,
                    pos,
                );
            }
        }
    }

    /// Validate the unit of every `rgb`/`rgba` channel, matching dart-sass:
    /// each `$red`/`$green`/`$blue` must be unitless or carry exactly `%`. Any
    /// other unit (`px`, `deg`, a complex `px*px`, or a unit-bearing degenerate
    /// `calc(infinity * 1px)`) raises `$<param>: Expected <value> to have unit
    /// "%" or no units.`.
    ///
    /// Run only after the special/`none`/relative passthroughs (so `var()`,
    /// `none`, `from …` are preserved) and after the numeric and count checks
    /// (dart reports a non-number or wrong-channel-count channel first). For the
    /// positional comma form (`single == None`) this also supplies the
    /// `$<param>:` prefix on the per-channel "is not a number" error, which
    /// dart attaches but the bare [`channel`] helper does not; the check runs
    /// left-to-right so a non-number channel is reported before a later
    /// bad-unit one, matching dart's two-pass (coerce-then-unit) order.
    function validate_rgb_units(self, names: string[], pos: root.scanner.Pos) -> void {
        self.validate_positional_numeric(names, pos);
        for (let i in baml.iter.Range.new(0, self.comps.length())) {
            let comp = self.comps[i];
            let num = root.builtins.color.channel_unit_number(comp);
            if (num != null) {
                let ok = num.is_unitless() || (!num.has_complex_units() && num.unit() == "%");
                if (!ok) {
                    throw root.error.Error.at(
                        `$${names[root.std.imin(i, names.length() - 1)]}: Expected ${comp.to_css(false)} to have unit "%" or no units.`,
                        pos,
                    );
                }
            }
        }
    }

    /// Validate that a single-argument channels list holds exactly three
    /// components for a legacy color space. dart-sass only enforces this when
    /// all channels are plain (a special/`none` channel preserves the call), so
    /// callers must run this *after* [`Channels::special_passthrough`] returns
    /// `None`. The three/four-positional forms (`single == None`) skip the
    /// check — their arity is validated by the argument count.
    function validate_count(self, space: string, pos: root.scanner.Pos) -> void {
        let single = self.single;
        if (single != null) {
            if (self.comps.length() != 3) {
                throw root.error.Error.at(
                    `$channels: The ${space} color space has 3 channels but ${root.builtins.color.list_paren_css(single)} has ${self.comps.length()}.`,
                    pos,
                );
            }
        }
    }

    /// If this is a relative-color call (`rgb(from … )`), preserve it verbatim.
    /// dart-sass keeps the whole `from`-based form rather than computing it.
    function relative_passthrough(self, name: string) -> root.value.Value? {
        let is_relative = match (self.comps.at(0)) {
            root.value.Value_Str { _0: let s }
                if !s.quoted && root.std.eq_ignore_ascii_case(s.text, "from") => true,
            _ => false,
        };
        if (!is_relative) {
            return null;
        }
        self.verbatim_passthrough(name)
    }

    /// If these channels contain a special value (`var()`, `calc()`, …) or a
    /// `none` keyword, return the re-serialized passthrough call dart-sass
    /// would emit; otherwise `None` (the channels are all plain numbers and a
    /// real color should be computed, or a count error should be raised).
    function special_passthrough(self, name: string, canonical: string) -> root.value.Value? {
        let self_alpha = self.alpha;
        let comps_special = self.comps.some((v) -> {
            root.builtins.color.is_special_legacy(v)
        });
        let alpha_special = if (self_alpha != null) {
            root.builtins.color.is_special_legacy(self_alpha)
        } else {
            false
        };
        let comps_none = self.comps.some((v) -> {
            root.builtins.color.is_none_keyword(v)
        });
        let alpha_none = if (self_alpha != null) {
            root.builtins.color.is_none_keyword(self_alpha)
        } else {
            false
        };
        let has_special = comps_special || alpha_special;
        let has_none = comps_none || alpha_none;
        if (!has_special && !has_none) {
            return null;
        }
        // A special function present forces the legacy comma form when the
        // channel count is exactly three (a `none` is simply one of the three
        // comma items). With a different count the *original* spelling is kept
        // verbatim (so the `/` alpha separator stays glued).
        if (has_special) {
            if (self.comps.length() == 3) {
                let args: root.value.Value[] = root.std.clone_vec(self.comps);
                if (self_alpha != null) {
                    args.push(self_alpha);
                }
                return root.builtins.color.special_call(name, args);
            }
            return self.verbatim_passthrough(name);
        }
        // No special function, only a `none`: the space/slash form is kept when
        // there are exactly three channels (hsl gives a bare hue a `deg`). A
        // wrong channel count falls through to the count error.
        if (self.comps.length() != 3) {
            return null;
        }
        // A `none`-only call normalizes to the canonical space name (dart-sass
        // emits `rgb`/`hsl` here, never the `rgba`/`hsla` the caller may have
        // written).
        let is_hsl = root.std.eq_ignore_ascii_case(canonical, "hsl");
        self.none_verbatim(canonical, is_hsl)
    }

    /// Re-serialize a special-value passthrough whose channel count is not the
    /// canonical three. Prefer the *original* single channels value (which
    /// keeps the glued `/` alpha spelling) when the alpha was peeled from it or
    /// no alpha was supplied; otherwise reconstruct a comma call.
    function verbatim_passthrough(self, name: string) -> root.value.Value {
        let single = self.single;
        if (single != null) {
            if (self.alpha == null || self.alpha_split) {
                return root.builtins.color.verbatim_call(name, single);
            }
        }
        let args: root.value.Value[] = root.std.clone_vec(self.comps);
        let a = self.alpha;
        if (a != null) {
            args.push(a);
        }
        root.builtins.color.special_call(name, args)
    }

    /// Serialize a legacy color call preserved because of a `none` channel, in
    /// the space-separated (slash-alpha) form. For hsl/hsla a bare-number hue
    /// gains an explicit `deg` (`hsl(180 none 50%)` → `hsl(180deg none 50%)`).
    function none_verbatim(self, name: string, is_hsl: bool) -> root.value.Value {
        let hue = match (self.comps[0]) {
            root.value.Value_Number { _0: let n } if is_hsl && n.is_unitless() => {
                `${root.value.fmt_num(n.value, false)}deg`
            },
            let other => other.to_css(false),
        };
        let body = `${hue} ${self.comps[1].to_css(false)} ${self.comps[2].to_css(false)}`;
        let a = self.alpha;
        let text = if (a != null) {
            `${name}(${body} / ${a.to_css(false)})`
        } else {
            `${name}(${body})`
        };
        root.value.Value_Str { _0: root.value.SassStr { text: text, quoted: false } }
    }
}

/// The components and optional alpha peeled off a one-argument channels value.
class SplitChannels {
    /// The channel components (the alpha removed if one was found).
    comps: root.value.Value[],
    /// The alpha value, if a trailing `… / alpha` was peeled off.
    alpha: root.value.Value?,
    /// Whether `alpha` was peeled from the trailing item of the original
    /// channels value (rather than being absent). This drives the verbatim
    /// passthrough, which prefers to re-serialize the *original* channels list
    /// when the channel count is wrong.
    alpha_split: bool,
}

/// Split a one-argument channels value into its components and optional alpha.
/// A space list contributes its items; a trailing slash-division on the last
/// item (`1 2 3 / 0.5`, parsed as `[1, 2, 3/0.5]`) peels off the alpha. When
/// the trailing slash crosses a special value (`var()`, `calc()`, `none`, …)
/// the division does not fold to a [`Value::Slash`] but to an unquoted string
/// like `var(--x)/0.4` or `3/none`; that trailing `X/Y` string is split at its
/// top-level slash into the last channel and the alpha (each becoming a plain
/// [`Number`] or an unquoted string).
function split_channels(channels: root.value.Value) -> SplitChannels {
    let no_split = (comps: root.value.Value[]) -> SplitChannels {
        SplitChannels { comps: comps, alpha: null, alpha_split: false }
    };
    let l = match (channels) {
        root.value.Value_List { _0: let l } => l,
        _ => {
            return no_split([channels]);
        },
    };
    if (l.sep == root.value.ListSep.Slash) {
        // The `<channels> / <alpha>` form (the caller rejects any element count
        // other than two): the first element is the channels (a space list),
        // the second is the alpha.
        if (l.items.length() == 2) {
            // Only an unbracketed space list expands into channels; a bracketed
            // first element stays a single value so the caller rejects it
            // ("Expected an unbracketed list"), matching dart-sass.
            let comps: root.value.Value[] = match (l.items[0]) {
                root.value.Value_List { _0: let inner }
                    if inner.sep == root.value.ListSep.Space && !inner.bracketed => {
                    root.std.clone_vec(inner.items)
                },
                let other => [other],
            };
            return SplitChannels { comps: comps, alpha: l.items[1], alpha_split: true };
        }
        return no_split(root.std.clone_vec(l.items));
    }
    if (l.sep != root.value.ListSep.Space) {
        return no_split(root.std.clone_vec(l.items));
    }
    let items: root.value.Value[] = root.std.clone_vec(l.items);
    // A trailing `n / a` slash-division shows up as a `Slash` whose textual
    // spelling contains `/`; recover the channel and alpha (each may carry a
    // unit, e.g. `50%/0.4`). The split is at the LAST top-level slash, which is
    // dart's rule for a chain: the final element is the alpha and every earlier
    // slash stays a DIVISION inside the last channel, so `0 0 0/50%/2` is alpha
    // `2` with a blue of `0/50%` — the spelling its own diagnostic shows.
    if let sl: root.value.Value_Slash = root.std.last(items) {
        let repr = sl._1;
        let idx = top_level_slash(repr);
        if (idx != null) {
            let lhs = root.std.trim(repr.slice(0, idx));
            let rhs = root.std.trim(repr.slice(idx + 1, repr.length()));
            let last = slash_channel_token(lhs);
            let alpha = numeric_token(rhs);
            if (last != null) {
                if (alpha != null) {
                    items.pop();
                    items.push(last);
                    return SplitChannels { comps: items, alpha: alpha, alpha_split: true };
                }
            }
        }
    }
    // A trailing unquoted `X/Y` string: the slash crossed a special value (or a
    // `none`), so it evaluated to a string rather than a numeric `Slash`. Split
    // it at the top-level slash into the last channel and the alpha.
    if let sv: root.value.Value_Str = root.std.last(items) {
        let s = sv._0;
        if (!s.quoted) {
            let idx = top_level_slash(s.text);
            if (idx != null) {
                let lhs = root.std.trim(s.text.slice(0, idx));
                let rhs = root.std.trim(s.text.slice(idx + 1, s.text.length()));
                if (lhs != "" && rhs != "") {
                    let last = channel_token(lhs);
                    let alpha = channel_token(rhs);
                    items.pop();
                    items.push(last);
                    return SplitChannels { comps: items, alpha: alpha, alpha_split: true };
                }
            }
        }
    }
    no_split(items)
}

/// A channel token that must be NUMERIC: a plain number or a degenerate
/// `calc()`. Anything else (a keyword, a `var()`, a leftover slash) is `None`,
/// so the caller leaves the list unsplit rather than inventing a channel.
function numeric_token(s: string) -> root.value.Value? {
    let v = channel_token(s);
    if (v is root.value.Value_Number || v is root.value.Value_Calc) {
        return v;
    }
    // The UNIT-bearing degenerate spelling a slash repr can carry
    // (`calc(NaN * 1%)`), which the plain token reader does not recognize.
    let n = parse_degenerate_token(s);
    if (n != null) {
        root.value.Value_Number { _0: n }
    } else {
        null
    }
}

/// A channel token that may itself be a chain of divisions (`0/50%`): each
/// slash divides, and the result keeps the authored spelling, which is what
/// the channel's unit diagnostic reports. `None` if any piece is not numeric.
function slash_channel_token(s: string) -> root.value.Value? {
    let idx = top_level_slash(s);
    if (idx == null) {
        return numeric_token(s);
    }
    let left = slash_channel_token(root.std.trim(s.slice(0, idx)));
    if (left == null) {
        return null;
    }
    let right = numeric_token(root.std.trim(s.slice(idx + 1, s.length())));
    if (right == null) {
        return null;
    }
    let a = root.builtins.color.channel_unit_number(left);
    if (a == null) {
        return null;
    }
    let b = root.builtins.color.channel_unit_number(right);
    if (b == null) {
        return null;
    }
    root.value.Value_Slash { _0: a.div(b), _1: s }
}

/// Find the byte index of the (single) top-level `/` in an unquoted channel
/// string — the slash that separates the last channel from the alpha. Slashes
/// inside parentheses (e.g. `calc(a/b)`) are skipped. Returns the last such
/// slash, or `None` if there is none.
// PORT: returns a CHARACTER index (guide §8), used only to slice this same string.
function top_level_slash(s: string) -> int? {
    let depth = 0;
    let found: int? = null;
    let i = 0;
    for (let c in s.chars()) {
        match (c) {
            "(" | "[" => {
                depth += 1;
            },
            ")" | "]" => {
                depth -= 1;
            },
            "/" if depth == 0 => {
                found = i;
            },
            _ => {},
        }
        i += 1;
    }
    found
}

/// Convert one side of a split `X/Y` channel string into a value: a numeric
/// token (`0.4`, `50%`) becomes a [`Number`]; a degenerate calculation
/// (`calc(NaN)`, `calc(infinity)`, `calc(-infinity)`) is recovered as a
/// [`Value::Calc`] so it folds/serializes like the original; anything else
/// (`var(--x)`, `none`, other `calc(…)`) becomes an unquoted string.
function channel_token(s: string) -> root.value.Value {
    let n = parse_number_token(s);
    if (n != null) {
        // Reject a token that has leftover non-unit text (e.g. `1px2` would not
        // round-trip); `parse_number_token` only consumes the numeric prefix.
        if (fmt_token_matches(n, s)) {
            return root.value.Value_Number { _0: n };
        }
    }
    let inner = degenerate_calc_str(s);
    if (inner != null) {
        return root.value.Value_Calc { _0: root.value.CalcNode_Str { _0: inner } };
    }
    root.value.Value_Str { _0: root.value.SassStr { text: s, quoted: false } }
}

/// The inner constant of a `calc(<const>)` string when `<const>` is a
/// degenerate constant (`NaN`, `infinity`, `-infinity`), or `None` otherwise.
/// Used to recover a [`Value::Calc`] from a split channel/alpha string.
function degenerate_calc_str(s: string) -> string? {
    let s = root.std.trim(s);
    if (!root.std.ascii_lower(s).starts_with("calc(") || !s.ends_with(")")) {
        return null;
    }
    let inner = root.std.trim(s.slice(5, s.length() - 1));
    match (root.std.ascii_lower(inner)) {
        "nan" | "infinity" | "-infinity" => inner,
        _ => null,
    }
}

/// Whether `n` re-serializes to exactly `s` (so the whole token was numeric).
function fmt_token_matches(n: root.value.Number, s: string) -> bool {
    `${root.value.fmt_num(n.value, false)}${n.unit()}` == s
}

/// Parse a CSS number token that may carry a unit (`"3"`, `"0.5"`, `"50%"`)
/// into a [`Number`]. Returns `None` for anything not of that shape.
/// Parse the textual spelling of a degenerate calc back into its number:
/// `calc(NaN)`, `calc(infinity)`, `calc(-infinity)`, and the unit-bearing
/// `calc(<const> * 1<unit>)` forms a slash repr may carry.
function parse_degenerate_token(s: string) -> root.value.Number? {
    let t = root.std.trim(s);
    let after_prefix = root.std.strip_prefix(t, "calc(");
    if (after_prefix == null) {
        return null;
    }
    let before_suffix = root.std.strip_suffix(after_prefix, ")");
    if (before_suffix == null) {
        return null;
    }
    let inner = root.std.trim(before_suffix);
    // PORT: the `(const_part, unit)` tuple match → two locals set per arm.
    let const_part = inner;
    let unit = "";
    let parts = root.std.split_once(inner, "*");
    if (parts != null) {
        const_part = root.std.trim(parts._0);
        let u = root.std.strip_prefix(root.std.trim(parts._1), "1");
        if (u == null) {
            return null;
        }
        unit = u;
    }
    let value = match (root.std.ascii_lower(const_part)) {
        "nan" => root.std.F64_NAN(),
        "infinity" => root.std.F64_INFINITY(),
        "-infinity" => root.std.F64_NEG_INFINITY(),
        _ => {
            return null;
        },
    };
    root.value.Number.with_unit(value, unit)
}

function parse_number_token(s: string) -> root.value.Number? {
    let s = root.std.trim(s);
    // PORT: `char_indices().find(..).map(|(i, _)| i).unwrap_or(s.len())` → an
    // index loop over the chars (character offsets, guide §8).
    let cs = s.chars();
    let split = cs.length();
    let i = 0;
    while (i < cs.length()) {
        let c = cs[i];
        if (!(root.std.is_ascii_digit(c) || c == "." || c == "-" || c == "+" || c == "e" || c == "E")) {
            split = i;
            break;
        }
        i += 1;
    }
    let num_part = s.slice(0, split);
    let unit = s.slice(split, s.length());
    let value = baml.Float.parse(num_part) catch (e) {
        baml.errors.ParseError => {
            return null;
        },
    };
    root.value.Number.with_unit(value, unit)
}

function rgb_repr(r: float, g: float, b: float, a: float) -> string {
    if (root.value.fuzzy_eq(a, 1.0)) {
        `rgb(${root.value.fmt_num(r, false)}, ${root.value.fmt_num(g, false)}, ${root.value.fmt_num(b, false)})`
    } else {
        `rgba(${root.value.fmt_num(r, false)}, ${root.value.fmt_num(g, false)}, ${root.value.fmt_num(b, false)}, ${root.value.fmt_num(a, false)})`
    }
}

function fn_hsl(
    name: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["hue", "saturation", "lightness", "alpha"];
    root.builtins.check_arity(4, pos_args, named, pos);
    let channels = Channels.collect(params, pos_args, named, pos);
    // Echo the caller's spelling (`hsl` vs `hsla`) in the special/relative
    // passthroughs; the `none`-only path normalizes to canonical `hsl`.
    if let verbatim: root.value.Value = channels.relative_passthrough(name) {
        return verbatim;
    }
    // A `none` channel (with no real special function) builds a modern legacy
    // hsl color rather than a verbatim string.
    if let c: root.value.Value = legacy_none_color(channels, root.value.ColorSpace.Hsl, pos) {
        return c;
    }
    if let verbatim: root.value.Value = channels.special_passthrough(name, "hsl") {
        return verbatim;
    }
    // hsl/hsla has no two-argument `$color, $alpha` overload (unlike rgb). A
    // plain two-positional call (`hsl(1, 0.5)`, `hsl(#123, 0.5)`) therefore
    // binds to the `hsl($hue, $saturation, $lightness, $alpha)` signature with
    // `$lightness` unfilled, which dart reports as `Missing argument
    // $lightness.`. A special first argument is preserved verbatim above, so it
    // does not reach here; the exotic named-argument fallbacks (which dart maps
    // to the `$channels` overload's `No parameter named …` / `Missing argument
    // $channels.`) keep their existing channel-shape errors (an exit-code
    // match).
    if (pos_args.length() == 2 && named.length() == 0) {
        throw root.error.Error.at("Missing argument $lightness.", pos);
    }
    channels.comps = root.builtins.color.normalize_channels(channels.comps, 0);
    // A degenerate channel that SURVIVED normalization — an infinite
    // saturation or lightness — builds an hsl color that CARRIES the infinity,
    // with each channel coerced per dart-sass's modern parsing (see
    // `hsl_degenerate`). A NaN channel and a non-finite hue are 0 by now.
    if (
        channels.comps.length() == 3
            && channels.comps.some((v) -> {
                root.builtins.color.is_degenerate_calc(v)
            })
    ) {
        return hsl_degenerate(channels, pos);
    }
    channels.validate_numeric(["hue", "saturation", "lightness"], pos);
    channels.validate_positional_numeric(["hue", "saturation", "lightness"], pos);
    root.builtins.color.validate_alpha_unit(channels.alpha, pos);
    channels.validate_count("hsl", pos);
    let comps = channels.comps;
    let alpha = channels.alpha;
    let h = hsl_hue(comps[0], pos);
    // The repr preserves the supplied saturation/lightness percentages, except
    // saturation is floored at 0 (matching dart-sass: `hsl(0, 500%, 50%)` keeps
    // `500%`, `hsl(0, -100%, 50%)` becomes `0%`, lightness is left untouched).
    let s_raw = channel_value(comps[1], pos);
    let l_raw = channel_value(comps[2], pos);
    // PORT: `let z = crate::value::without_negative_zero;` → a closure.
    let z = (v: float) -> float {
        root.value.without_negative_zero(v)
    };
    let s_pct = z(
        if (s_raw.is_nan()) {
            0.0
        } else {
            root.std.fmax(s_raw, 0.0)
        },
    );
    let l_pct = z(
        if (l_raw.is_nan()) {
            0.0
        } else {
            l_raw
        },
    );
    let a = if (alpha != null) {
        root.builtins.color.alpha_value(alpha, pos)
    } else {
        1.0
    };
    let c = root.value.Color.from_hsl(
        h,
        root.std.fclamp(s_pct / 100.0, 0.0, 1.0),
        root.std.fclamp(l_pct / 100.0, 0.0, 1.0),
        a,
    );
    // hsl()/hsla() literals keep their function representation, matching
    // dart-sass (e.g. `hsl(120, 50%, 40%)` does not collapse to hex). The hue
    // is normalized to degrees in `[0, 360)`. The modern Hsl tag carries the
    // space so `color.space`/`color.channel` work; serialization uses the
    // classic comma form via `ModernColor::legacy_css`.
    let h_norm = root.value.without_negative_zero(root.std.f_rem_euclid(h, 360.0));
    c.modern
        = root.value.ModernColor {
            space: root.value.ColorSpace.Hsl,
            channels: [h_norm, s_pct, l_pct],
            alpha: a,
        };
    root.value.Value_Color { _0: c }
}

/// Read an hsl hue value in degrees, converting `rad`/`grad`/`turn` units
/// (matching dart-sass's lenient legacy angle handling). Other/empty units
/// are taken as degrees.
function hsl_hue(v: root.value.Value, pos: root.scanner.Pos) -> float {
    // PORT: the `Value::Number(num) | Value::Slash(num, _)` or-pattern binds
    // across two variant classes, which BAML rejects; the arm is repeated.
    match (v) {
        // A slash-division carries its quotient AND its unit, so `1turn/2` is
        // half a turn — 180deg — not 0.5.
        root.value.Value_Number { _0: let num } => match (num.unit()) {
            // PORT: Rust's `f64::to_degrees` via `root.builtins.math.f64_to_degrees`
            // (BAML's `Float.to_degrees` can differ in the last bit).
            "rad" => root.builtins.math.f64_to_degrees(num.value),
            "grad" => num.value * 360.0 / 400.0,
            "turn" => num.value * 360.0,
            _ => num.value,
        },
        root.value.Value_Slash { _0: let num } => match (num.unit()) {
            // PORT: Rust's `f64::to_degrees` via `root.builtins.math.f64_to_degrees`
            // (BAML's `Float.to_degrees` can differ in the last bit).
            "rad" => root.builtins.math.f64_to_degrees(num.value),
            "grad" => num.value * 360.0 / 400.0,
            "turn" => num.value * 360.0,
            _ => num.value,
        },
        let other => {
            throw root.error.Error.at(`${other.to_css(false)} is not a number.`, pos);
        },
    }
}

/// Read a legacy channel's numeric value, accepting the quotient a
/// slash-division carries: inside a SPACE-separated channels list `60%/2`
/// keeps its spelling, and `num` alone calls it "not a number".
function channel_value(v: root.value.Value, pos: root.scanner.Pos) -> float {
    let n = root.builtins.color.channel_unit_number(v);
    if (n != null) {
        n.value
    } else {
        root.builtins.num(v, pos)
    }
}

/// Fold a degenerate `calc()` channel (`calc(NaN)`, `calc(infinity * 1%)`)
/// to its plain number, keeping the unit; any other value passes through.
function fold_degenerate(v: root.value.Value) -> root.value.Value {
    if let cv: root.value.Value_Calc = v {
        let node = cv._0;
        let c = root.builtins.color.degenerate_const(node);
        if (c != null) {
            return root.value.Value_Number { _0: root.value.Number.unitless(c) };
        }
        if let nn: root.value.CalcNode_Number = node {
            let n = nn._0;
            if (!n.value.is_finite()) {
                return root.value.Value_Number { _0: n };
            }
        }
    }
    v
}

/// Build an `hsl()`/`hsla()` color that carries an infinite saturation or
/// lightness. dart-sass parses this into a REAL color — `meta.type-of` says
/// `color`, `color.channel($c, "lightness")` hands the infinity back — so the
/// channels are STORED rather than spelled out: the hue is reduced modulo 360,
/// saturation is floored at 0 (so `-infinity` → `0%`), and the surviving
/// infinity stays in its channel, where `ModernColor`'s legacy serialization
/// renders it as `calc(infinity * 1%)` in either output style. A NaN channel
/// reaches here too (`hsl(0, 100%, calc(NaN * 1%))`) and is stored as it is:
/// that same serialization writes a NaN as `0%`, which is what dart prints for
/// it.
function hsl_degenerate(channels: Channels, pos: root.scanner.Pos) -> root.value.Value {
    let h = root.value.without_negative_zero(root.std.f_rem_euclid(hsl_hue(channels.comps[0], pos), 360.0));
    let s = hsl_degenerate_chan(channels.comps[1], true, pos);
    let l = hsl_degenerate_chan(channels.comps[2], false, pos);
    let alpha = channels.alpha;
    let a = if (alpha != null) {
        root.builtins.color.alpha_value(alpha, pos)
    } else {
        1.0
    };
    // The legacy rgb shadow is the plain hsl -> sRGB conversion, unclamped, so
    // it keeps the infinity and whatever NaN that conversion's own arithmetic
    // makes of it. dart's legacy rgb view of the color is the same conversion,
    // and both properties matter: `color.mix()` of two legacy colors mixes
    // these very channels, and a shadow clamped to the gamut edge — black for
    // `-infinity`, white for `infinity` — would make the cross-space
    // `hsl(0, 100%, calc(-infinity * 1%)) == rgb(0, 0, 0)` true, where dart
    // says false. Nothing serializes the shadow: the modern tag below carries
    // the infinity, and a non-finite channel is out of gamut, so even
    // compressed output — which otherwise prefers the rgb spelling — keeps the
    // hsl form.
    let srgb = root.builtins.colorspace.hsl_to_srgb([h, s, l]);
    let c = root.value.Color.rgb(srgb[0] * 255.0, srgb[1] * 255.0, srgb[2] * 255.0, a);
    c.modern
        = root.value.ModernColor { space: root.value.ColorSpace.Hsl, channels: [h, s, l], alpha: a };
    root.value.Value_Color { _0: c }
}

/// The stored value of a saturation/lightness channel of a degenerate hsl()
/// call. An infinite channel is a `%` value like a written one, so it is kept
/// as its bare number; saturation floors a negative channel (infinite or not)
/// at 0, lightness keeps its sign.
function hsl_degenerate_chan(
    v: root.value.Value,
    is_saturation: bool,
    pos: root.scanner.Pos,
) -> float {
    let d = root.builtins.color.degenerate_value(v);
    let raw = if (d != null) {
        d
    } else {
        channel_value(v, pos)
    };
    // `f64::max` returns the non-NaN side, so a NaN saturation floors to 0 the
    // way the ordinary path's does.
    root.value.without_negative_zero(
        if (is_saturation) {
            root.std.fmax(raw, 0.0)
        } else {
            raw
        },
    )
}

/// The global `hwb()` function. It takes a single channels argument
/// (`hwb(h w b)`, `hwb(h w b / a)`). With all plain numeric channels it
/// converts HWB → sRGB → HSL and emits the `hsl()`/`hsla()` spelling that
/// dart-sass uses for legacy hwb colors. With a special value (`var()`,
/// `calc()`) or a `none` missing-channel keyword it preserves the call
/// verbatim, space-joined, with a bare numeric hue suffixed `deg`.
function fn_hwb(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["channels"];
    // Only an OVERFLOW is an arity error, and only POSITIONAL arguments count
    // toward it: with nothing passed the parameter is simply missing, and dart
    // says so (`hwb()` is `Missing argument $channels.`, not "but 0 were
    // passed").
    root.builtins.check_arity(1, pos_args, named, pos);
    let channels = root.builtins.require(params, pos_args, named, 0, pos);
    // A single channels list must be unbracketed and space/slash-separated; a
    // bracketed and/or comma list is rejected with dart-sass's message.
    if let lv: root.value.Value_List = channels {
        let l = lv._0;
        let comma = l.sep == root.value.ListSep.Comma;
        if (l.bracketed || comma) {
            let kind = if (l.bracketed && comma) {
                "an unbracketed, space- or slash-separated list"
            } else if (l.bracketed) {
                "an unbracketed list"
            } else {
                "a space- or slash-separated list"
            };
            let shown = if (l.bracketed) {
                channels.to_css(false)
            } else {
                root.builtins.color.list_paren_css(channels)
            };
            throw root.error.Error.at(`$channels: Expected ${kind}, was ${shown}`, pos);
        }
    }
    let split = split_channels(channels);
    let comps = split.comps;
    let alpha = split.alpha;
    // A relative-color call (`hwb(from … )`) or a special function
    // (`var()`/`calc()`/…) anywhere preserves the *original* spelling verbatim
    // (a bare numeric hue keeps its bare form, the `/` alpha separator stays
    // glued), regardless of channel count.
    let is_relative = match (comps.at(0)) {
        root.value.Value_Str { _0: let s }
            if !s.quoted && root.std.eq_ignore_ascii_case(s.text, "from") => true,
        _ => false,
    };
    // A degenerate `calc()` channel or alpha (`calc(NaN)`, `calc(infinity *
    // 1%)`) folds to its number — dart constructs the color and lets the
    // hwb -> hsl legacy serialization propagate the non-finite values —
    // rather than preserving the call verbatim.
    let comps_func = comps.some((v) -> {
        root.builtins.color.is_special(v) && !root.builtins.color.is_degenerate_calc(v)
    });
    let alpha_func = if (alpha != null) {
        root.builtins.color.is_special(alpha) && !root.builtins.color.is_degenerate_calc(alpha)
    } else {
        false
    };
    if (is_relative || comps_func || alpha_func) {
        return root.builtins.color.verbatim_call("hwb", channels);
    }
    let folded: root.value.Value[] = comps.map((v) -> {
        fold_degenerate(v)
    });
    let comps = root.builtins.color.normalize_channels(folded, 0);
    // A non-number channel (a non-`from` keyword such as `c`, or a quoted
    // string) is reported before the channel-count check, matching dart-sass.
    for (let i in baml.iter.Range.new(0, comps.length())) {
        let comp = comps[i];
        let numeric = comp is root.value.Value_Number
            || comp is root.value.Value_Slash
            || root.builtins.color.is_none_keyword(comp)
            || root.builtins.color.is_degenerate_calc(comp);
        if (!numeric) {
            throw root.error.Error.at(
                `$channels: Expected ${root.builtins.color.legacy_channel_name(["hue", "whiteness", "blackness"], i)} to be a number, was ${root.builtins.color.channel_err_css(comp)}.`,
                pos,
            );
        }
    }
    root.builtins.color.validate_alpha_unit(alpha, pos);
    // Without a special function, the channel count must be exactly three.
    if (comps.length() != 3) {
        throw root.error.Error.at(
            `$channels: The hwb color space has 3 channels but ${root.builtins.color.list_paren_css(channels)} has ${comps.length()}.`,
            pos,
        );
    }
    // Whiteness and blackness must carry a `%` unit (dart-sass), reported per
    // channel before the value is read — and before the `none` construction
    // below, which exempts only the `none` channels themselves.
    let unit_checks: root.std.Tuple2<int, string>[] = [
        root.std.Tuple2<int, string> { _0: 1, _1: "whiteness" },
        root.std.Tuple2<int, string> { _0: 2, _1: "blackness" },
    ];
    for (let ic in unit_checks) {
        let i = ic._0;
        let cname = ic._1;
        let num = root.builtins.color.channel_unit_number(comps[i]);
        if (num != null) {
            // A COMPOUND unit only reports its first numerator, so `%/px` must
            // be rejected explicitly rather than read as a percentage.
            if (num.has_complex_units() || num.unit() != "%") {
                // The message shows the spelling the caller wrote, not the
                // zero a degenerate channel normalizes to.
                throw root.error.Error.at(
                    `$${cname}: Expected ${folded[i].to_css(false)} to have unit "%".`,
                    pos,
                );
            }
        }
    }
    // A `none` missing-channel keyword (with otherwise plain numbers) builds a
    // modern legacy hwb color.
    let comps_none = comps.some((v) -> {
        root.builtins.color.is_none_keyword(v)
    });
    let alpha_none = if (alpha != null) {
        root.builtins.color.is_none_keyword(alpha)
    } else {
        false
    };
    if (comps_none || alpha_none) {
        let h: float? = if (root.builtins.color.is_none_keyword(comps[0])) {
            null
        } else {
            root.builtins.color.math.modern_hue(comps[0])
        };
        let w: float? = root.builtins.color.math.modern_channel(comps[1], 100.0);
        let bl: float? = root.builtins.color.math.modern_channel(comps[2], 100.0);
        // dart normalizes at CONSTRUCTION (`_colorFromChannels`): when both
        // whiteness and blackness are present and sum past 100, both scale
        // back to a 100 total. Reads then see the normalized storage.
        let wv = w;
        let bv = bl;
        if (wv != null) {
            if (bv != null) {
                if (root.std.fgt(wv + bv, 100.0)) {
                    let t = wv + bv;
                    w = wv / t * 100.0;
                    bl = bv / t * 100.0;
                }
            }
        }
        let mc = root.value.ModernColor {
            space: root.value.ColorSpace.Hwb,
            channels: [h, w, bl],
            alpha: root.builtins.color.math.modern_alpha(alpha),
        };
        return root.value.Value_Color { _0: root.builtins.color.math.make_modern(mc) };
    }
    let h = hsl_hue(comps[0], pos);
    let w_pct = channel_value(comps[1], pos);
    let b_pct = channel_value(comps[2], pos);
    let a = if (alpha != null) {
        root.builtins.color.alpha_value(alpha, pos)
    } else {
        1.0
    };
    // dart normalizes at CONSTRUCTION (`_colorFromChannels`): a whiteness +
    // blackness sum past 100 scales both back to a 100 total, and every read
    // path (channel getters, inspect) sees the normalized storage. `change`
    // re-normalizes; `adjust`/`scale` results stay raw.
    // PORT: `root.std.fgt` keeps Rust's IEEE `>` (an `∞ + -∞` sum is NaN).
    if (root.std.fgt(w_pct + b_pct, 100.0)) {
        let t = w_pct + b_pct;
        w_pct = w_pct / t * 100.0;
        b_pct = b_pct / t * 100.0;
    }
    // dart-sass 1.104.0 converts a NaN channel — and a negative zero — to 0
    // when the color is CONSTRUCTED, which is after that normalization. An
    // infinite whiteness becomes NaN there (`∞ / ∞`) and lands on 0, so
    // `hwb(0, calc(infinity * 1%), 40%)` is plain red; and because this path
    // stores its own channels rather than going through `make_modern`, it is
    // also where `hwb(0, -0%, 0%)` would otherwise keep a signed zero that
    // `color.channel` and `meta.inspect` read straight back.
    let channel_zero = (v: float) -> float {
        if (v.is_nan()) {
            0.0
        } else {
            root.value.without_negative_zero(v)
        }
    };
    // PORT: `let (w_pct, b_pct) = (…);` rebinding → reassignment.
    w_pct = channel_zero(w_pct);
    b_pct = channel_zero(b_pct);
    let out = hwb_to_color(h, w_pct, b_pct, a);
    // Carry the modern Hwb tag (so `color.space`/`color.channel` work);
    // serialization uses the classic hsl comma form via `legacy_css`.
    let h_norm = root.value.without_negative_zero(root.std.f_rem_euclid(h, 360.0));
    out.modern
        = root.value.ModernColor {
            space: root.value.ColorSpace.Hwb,
            channels: [h_norm, w_pct, b_pct],
            alpha: a,
        };
    root.value.Value_Color { _0: out }
}

/// `sass:color` members without a global alias. The global `hwb()` is
/// modern-only (`hwb($channels)`), but `sass:color` additionally exposes the
/// Sass-legacy comma form `color.hwb($hue, $whiteness, $blackness, $alpha: 1)`,
/// so it cannot reuse the global dispatch.
function call_module_member(
    member: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> (root.std.Ok<root.value.Value> | root.std.Err<root.error.Error>)? {
    match (member) {
        "hwb" => {
            let r = fn_color_hwb(pos_args, named, pos) catch (e) {
                let err: root.error.Error => {
                    return root.std.Err<root.error.Error> { error: err };
                },
            };
            root.std.Ok<root.value.Value> { value: r }
        },
        _ => null,
    }
}

/// `color.hwb()`: the modern single-argument channels form delegates to the
/// global `hwb()`; the comma form rebuilds an `h w b` (+ ` / alpha`) channels
/// value so the global's none/special/compute paths apply unchanged.
function fn_color_hwb(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    root.builtins.check_arity(4, pos_args, named, pos);
    if (pos_args.length() + named.length() <= 1) {
        return fn_hwb(pos_args, named, pos);
    }
    let params = ["hue", "whiteness", "blackness", "alpha"];
    let ch = Channels.collect(params, pos_args, named, pos);
    let space: root.value.Value = root.value.Value_List {
        _0: root.value.List {
            items: ch.comps,
            sep: root.value.ListSep.Space,
            bracketed: false,
            keywords: null,
        },
    };
    let ch_alpha = ch.alpha;
    let channels: root.value.Value = if (ch_alpha != null) {
        root.value.Value_List {
            _0: root.value.List {
                items: [space, ch_alpha],
                sep: root.value.ListSep.Slash,
                bracketed: false,
                keywords: null,
            },
        }
    } else {
        space
    };
    fn_hwb([channels], [], pos)
}

/// Convert HWB (hue degrees, whiteness/blackness percentages) to an sRGB
/// color. Whiteness and blackness are normalized when their sum exceeds 100.
function hwb_to_color(h: float, w_pct: float, b_pct: float, a: float) -> root.value.Color {
    let w = w_pct / 100.0;
    let b = b_pct / 100.0;
    if (root.std.fgt(w + b, 1.0)) {
        let sum = w + b;
        w = w / sum;
        b = b / sum;
    }
    let base = root.value.Color.from_hsl(h, 1.0, 0.5, a);
    let mix = (v: float) -> float {
        (v / 255.0 * (1.0 - w - b) + w) * 255.0
    };
    root.value.Color.rgb(mix(base.r), mix(base.g), mix(base.b), a)
}

/// The three channel names of a CIE/OK color space, for error messages.
function lab_channel_names(name: string) -> string[] {
    match (name) {
        "lch" | "oklch" => ["lightness", "chroma", "hue"],
        // lab / oklab
        _ => ["lightness", "a", "b"],
    }
}

/// The modern CIE/OK color functions `lab()`, `lch()`, `oklab()`, `oklch()`.
///
/// Full color-space math is out of scope: a fully numeric, well-formed call is
/// preserved verbatim (it is never reduced to another space here), and a call
/// containing a special value (`var()`/`calc()`), a `none` channel, or the
/// `from` relative-color keyword is likewise preserved verbatim. Malformed
/// calls raise the same validation errors as dart-sass.
function fn_lab_family(
    name: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["channels"];
    root.builtins.check_arity(1, pos_args, named, pos);
    if (pos_args.length() == 0 && named.length() == 0) {
        throw root.error.Error.at("Missing argument $channels.", pos);
    }
    let channels = root.builtins.require(params, pos_args, named, 0, pos);
    // A comma-separated or bracketed list is not a valid channels list.
    if let lv: root.value.Value_List = channels {
        let l = lv._0;
        let comma = l.sep == root.value.ListSep.Comma;
        if (l.bracketed || comma) {
            let kind = if (l.bracketed && comma) {
                "an unbracketed, space- or slash-separated list"
            } else if (l.bracketed) {
                "an unbracketed list"
            } else {
                "a space- or slash-separated list"
            };
            let shown = if (l.bracketed) {
                channels.to_css(false)
            } else {
                root.builtins.color.list_paren_css(channels)
            };
            throw root.error.Error.at(`$channels: Expected ${kind}, was ${shown}`, pos);
        }
        if (l.items.length() == 0) {
            throw root.error.Error.at(
                "$channels: Color component list may not be empty.",
                pos,
            );
        }
        // A slash-separated channels list is the `<channels> / <alpha>` form, so
        // dart-sass allows exactly two slash elements (e.g. via `list.slash`).
        if (l.sep == root.value.ListSep.Slash && l.items.length() != 2) {
            throw root.error.Error.at(
                `$channels: Only 2 slash-separated elements allowed, but ${l.items.length()} were passed.`,
                pos,
            );
        }
    }
    let split = split_channels(channels);
    let comps = split.comps;
    let alpha = split.alpha;
    // A relative-color call (`lab(from … )`) or a special function
    // (`var()`/non-degenerate `calc()`) is preserved verbatim. A `none`
    // channel is computed (it produces a missing channel).
    let is_relative = match (comps.at(0)) {
        root.value.Value_Str { _0: let s }
            if !s.quoted && root.std.eq_ignore_ascii_case(s.text, "from") => true,
        _ => false,
    };
    let special = (v: root.value.Value) -> bool {
        root.builtins.color.is_special(v) && !root.builtins.color.is_degenerate_calc(v)
    };
    let alpha_special = if (alpha != null) {
        special(alpha)
    } else {
        false
    };
    let has_special = comps.some(special) || alpha_special;
    if (is_relative || has_special) {
        return root.builtins.color.verbatim_call(name, channels);
    }
    let is_polar_space = name == "lch" || name == "oklch";
    let normalized = root.builtins.color.normalize_channels(
        comps,
        if (is_polar_space) {
            2
        } else {
            null
        },
    );
    // All-plain channels, in dart's order: every channel is a NUMBER, then the
    // alpha's unit, then the channel COUNT, then the channels' own units.
    let names = lab_channel_names(name);
    for (let i in baml.iter.Range.new(0, comps.length())) {
        let comp = comps[i];
        if (root.builtins.color.is_none_keyword(comp) || root.builtins.color.is_degenerate_calc(comp)) {
            continue;
        }
        if (root.builtins.color.channel_unit_number(comp) == null) {
            throw root.error.Error.at(
                `$channels: Expected ${root.builtins.color.legacy_channel_name(names, i)} to be a number, was ${root.builtins.color.channel_err_css(comp)}.`,
                pos,
            );
        }
    }
    root.builtins.color.validate_alpha_unit(alpha, pos);
    if (comps.length() != 3) {
        throw root.error.Error.at(
            `$channels: The ${name} color space has 3 channels but ${root.builtins.color.list_paren_css(channels)} has ${comps.length()}.`,
            pos,
        );
    }
    let is_hue = (i: int) -> bool {
        is_polar_space && i == 2
    };
    // Every numeric channel is unit-checked, whatever spelling it arrived in:
    // a degenerate `calc()` is the wrong unit as readily as a plain number
    // (`lab(1% calc(NaN * 1px) -3)`), and so is a slash-division
    // (`lab(1% 6px/2 -3)`). The message shows what the caller WROTE, not the
    // zero a degenerate channel normalizes to.
    for (let i in baml.iter.Range.new(0, comps.length())) {
        let comp = comps[i];
        // A unitless degenerate constant (`calc(NaN)`) carries no unit, and a
        // non-number channel was reported by the pass above.
        let num = root.builtins.color.channel_unit_number(comp);
        if (num == null) {
            continue;
        }
        let shown = comp.to_css(false);
        if (is_hue(i)) {
            // A COMPOUND unit only reports its first numerator, so `deg/px`
            // must be rejected explicitly rather than read as an angle.
            // PORT: the `matches!` on the unit is computed first (a `match` after
            // `||` inside parentheses misparses, guide §15).
            let angle_unit = match (num.unit()) {
                "deg" | "grad" | "rad" | "turn" => true,
                _ => false,
            };
            let ok = !num.has_complex_units() && (num.is_unitless() || angle_unit);
            if (!ok) {
                throw root.error.Error.at(
                    `$hue: Expected ${shown} to have an angle unit (deg, grad, rad, turn).`,
                    pos,
                );
            }
        } else if (!num.is_unitless() && (num.has_complex_units() || num.unit() != "%")) {
            throw root.error.Error.at(
                `$${names[i]}: Expected ${shown} to have unit "%" or no units.`,
                pos,
            );
        }
    }
    if (alpha != null) {
        // Validate the alpha's unit (errors on e.g. `0.4px`).
        if (!root.builtins.color.is_none_keyword(alpha)) {
            root.builtins.color.alpha_value(alpha, pos);
        }
    }
    let comps = normalized;
    // Compute the modern color. Lightness is clamped (lab/lch 0..100, oklab/oklch
    // 0..1); chroma is floored at 0; a/b and the hue are unclamped.
    let space_max_base: root.std.Tuple3<root.value.ColorSpace, float, float> = match (name) {
        "lab" => {
            root.std.Tuple3<root.value.ColorSpace, float, float> {
                _0: root.value.ColorSpace.Lab,
                _1: 100.0,
                _2: 100.0,
            }
        },
        "lch" => {
            root.std.Tuple3<root.value.ColorSpace, float, float> {
                _0: root.value.ColorSpace.Lch,
                _1: 100.0,
                _2: 100.0,
            }
        },
        "oklab" => {
            root.std.Tuple3<root.value.ColorSpace, float, float> {
                _0: root.value.ColorSpace.Oklab,
                _1: 1.0,
                _2: 1.0,
            }
        },
        _ => {
            root.std.Tuple3<root.value.ColorSpace, float, float> {
                _0: root.value.ColorSpace.Oklch,
                _1: 1.0,
                _2: 1.0,
            }
        },
    };
    let space = space_max_base._0;
    let l_max = space_max_base._1;
    let l_base = space_max_base._2;
    let is_polar = is_polar_space;
    // Percentage references per CSS Color 4: lab a/b 100% = 125, oklab a/b
    // 100% = 0.4, lch chroma 100% = 150, oklch chroma 100% = 0.4.
    let bases: root.std.Tuple2<float, float> = match (name) {
        "lab" => root.std.Tuple2<float, float> { _0: 125.0, _1: 0.0 },
        "lch" => root.std.Tuple2<float, float> { _0: 0.0, _1: 150.0 },
        "oklab" => root.std.Tuple2<float, float> { _0: 0.4, _1: 0.0 },
        _ => root.std.Tuple2<float, float> { _0: 0.0, _1: 0.4 }, // oklch
    };
    let ab_base = bases._0;
    let chroma_base = bases._1;
    // A degenerate lightness clamps like dart-sass (NaN -> 0, +infinity -> max,
    // -infinity -> 0); a/b/chroma/hue instead keep their non-finite value, which
    // serializes as `calc(...)` (chroma is additionally floored at 0).
    let l_raw = root.builtins.color.math.modern_channel(comps[0], l_base);
    let l: float? = if (l_raw != null) {
        if (l_raw.is_nan()) {
            0.0
        } else {
            root.std.fclamp(l_raw, 0.0, l_max)
        }
    } else {
        null
    };
    // PORT: `let (c1, c2) = if … { (…) } else { (…) };` → two locals set per branch.
    let c1: float? = null;
    let c2: float? = null;
    if (is_polar) {
        // [lightness, chroma, hue]
        let chroma = root.builtins.color.math.modern_channel(comps[1], chroma_base);
        c1
            = if (chroma != null) {
                root.std.fmax(chroma, 0.0)
            } else {
                null
            };
        c2 = root.builtins.color.math.modern_hue(comps[2]);
    } else {
        // [lightness, a, b]
        c1 = root.builtins.color.math.modern_channel(comps[1], ab_base);
        c2 = root.builtins.color.math.modern_channel(comps[2], ab_base);
    }
    let mc = root.value.ModernColor {
        space: space,
        channels: [l, c1, c2],
        alpha: root.builtins.color.math.modern_alpha(alpha),
    };
    root.value.Value_Color { _0: root.builtins.color.math.make_modern(mc) }
}

/// The channel names a `color()` space reports in its per-channel
/// diagnostics: the xyz spaces name their axes, every rgb-like space names
/// `red`/`green`/`blue`.
function color_channel_names(space: string) -> string[] {
    match (space) {
        "xyz" | "xyz-d50" | "xyz-d65" => ["x", "y", "z"],
        _ => ["red", "green", "blue"],
    }
}

/// The known predefined color spaces accepted by `color()`. All have three
/// channels, so the channel-count message is uniform.
function is_known_color_space(name: string) -> bool {
    match (name) {
        "srgb"
            | "srgb-linear"
            | "display-p3"
            | "display-p3-linear"
            | "a98-rgb"
            | "prophoto-rgb"
            | "rec2020"
            | "xyz"
            | "xyz-d50"
            | "xyz-d65" =>
        {
            true
        },
        _ => false,
    }
}

/// The `color()` function for predefined color spaces
/// (`color(srgb 0.1 0.2 0.3)`). Full color-space math is out of scope: a
/// well-formed call (and any special/`none`/`from`-relative call) is preserved
/// verbatim, while malformed calls raise dart-sass's validation errors.
function fn_color(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["description"];
    root.builtins.check_arity(1, pos_args, named, pos);
    if (pos_args.length() == 0 && named.length() == 0) {
        throw root.error.Error.at("Missing argument $description.", pos);
    }
    let desc = root.builtins.require(params, pos_args, named, 0, pos);
    if let lv: root.value.Value_List = desc {
        let l = lv._0;
        let comma = l.sep == root.value.ListSep.Comma;
        if (l.bracketed || comma) {
            let kind = if (l.bracketed && comma) {
                "an unbracketed, space- or slash-separated list"
            } else if (l.bracketed) {
                "an unbracketed list"
            } else {
                "a space- or slash-separated list"
            };
            let shown = if (l.bracketed) {
                desc.to_css(false)
            } else {
                root.builtins.color.list_paren_css(desc)
            };
            throw root.error.Error.at(
                `$description: Expected ${kind}, was ${shown}`,
                pos,
            );
        }
    }
    let split = split_channels(desc);
    let items = split.comps;
    let alpha = split.alpha;
    // The first item names the color space; the rest are channels.
    let space = items.at(0);
    if (space == null) {
        throw root.error.Error.at(
            "$description: Color component list may not be empty.",
            pos,
        );
    }
    let space_name = match (space) {
        root.value.Value_Str { _0: let s } if !s.quoted => s.text,
        root.value.Value_Str { _0: let s } => {
            throw root.error.Error.at(
                `$description: Expected "${s.text}" to be an unquoted string.`,
                pos,
            );
        },
        let other => {
            throw root.error.Error.at(
                `$description: ${other.to_css(false)} is not a string.`,
                pos,
            );
        },
    };
    // Color-space names are ASCII case-insensitive: match and serialize against
    // the lower-cased form, but keep the original spelling for the "Unknown
    // color space" diagnostic (dart-sass shows `color(BOGUS …)` verbatim there).
    let space_lower = root.std.ascii_lower(space_name);
    let channels = items.slice(1, items.length());
    // A relative-color call (`color(from … )`) or any special/`none` channel
    // is preserved verbatim. A *degenerate* `calc()` (`calc(NaN)`/`infinity`)
    // is not special here: dart-sass folds it to a finite/NaN channel value and
    // parses the color, so it flows through validation and the modern
    // (space-around-`/`) serialization below.
    let is_relative = root.std.eq_ignore_ascii_case(space_name, "from");
    let special_chan = (v: root.value.Value) -> bool {
        root.builtins.color.is_special(v) && !root.builtins.color.is_degenerate_calc(v)
    };
    let alpha_special = if (alpha != null) {
        special_chan(alpha)
    } else {
        false
    };
    let has_special = channels.some(special_chan) || alpha_special;
    if (is_relative || has_special) {
        return root.builtins.color.verbatim_call("color", desc);
    }
    if (!is_known_color_space(space_lower)) {
        throw root.error.Error.at(
            `$description: Unknown color space "${space_name}".`,
            pos,
        );
    }
    // Type-check each supplied channel before the count check, matching
    // dart-sass (`color(srgb (0.1 0.2 0.3))` reports a non-number channel
    // rather than a wrong count) — a degenerate `calc()` or a slash-division
    // is a number channel. A channel past the third is named by its INDEX.
    let names = color_channel_names(space_lower);
    for (let i in baml.iter.Range.new(0, channels.length())) {
        let comp = channels[i];
        if (root.builtins.color.is_none_keyword(comp) || root.builtins.color.is_degenerate_calc(comp)) {
            continue;
        }
        if (root.builtins.color.channel_unit_number(comp) == null) {
            throw root.error.Error.at(
                `$description: Expected ${root.builtins.color.legacy_channel_name(names, i)} to be a number, was ${root.builtins.color.channel_err_css(comp)}.`,
                pos,
            );
        }
    }
    root.builtins.color.validate_alpha_unit(alpha, pos);
    if (channels.length() != 3) {
        throw root.error.Error.at(
            `$description: The ${space_lower} color space has 3 channels but ${color_desc_css(desc)} has ${channels.length()}.`,
            pos,
        );
    }
    // The channels' own units, after the count — dart's order. This runs on
    // the channels as WRITTEN, so the message shows `calc(NaN * 1px)` rather
    // than the zero it is about to normalize to.
    for (let i in baml.iter.Range.new(0, channels.length())) {
        let comp = channels[i];
        let name = names.at(i) ?? "";
        let num = root.builtins.color.channel_unit_number(comp);
        if (num == null) {
            continue;
        }
        if (!num.is_unitless() && (num.has_complex_units() || num.unit() != "%")) {
            throw root.error.Error.at(
                `$${name}: Expected ${comp.to_css(false)} to have unit "%" or no units.`,
                pos,
            );
        }
    }
    // No predefined `color()` space has a polar hue, so only a NaN channel
    // normalizes to 0 here.
    // PORT: the `let channels = &channels[..];` reborrow has no BAML equivalent.
    let channels = root.builtins.color.normalize_channels(channels, null);
    if (alpha != null) {
        if (!root.builtins.color.is_none_keyword(alpha)) {
            root.builtins.color.alpha_value(alpha, pos);
        }
    }
    // `display-p3-linear` is accepted but not a real CSS Color 4 space in
    // dart-sass; it is preserved verbatim.
    let space_opt = root.builtins.color.math.predefined_space(space_lower);
    if (space_opt == null) {
        return root.builtins.color.verbatim_call("color", desc);
    }
    let space: root.value.ColorSpace = space_opt;
    // Compute the color: predefined `color()` spaces store red/green/blue (and
    // xyz x/y/z) channels in 0..1 with no clamping. A degenerate `calc()`
    // channel (`calc(infinity)`, `calc(1/0)`) folds to its bare infinity and
    // is stored like any other channel — a `%` one included, since a
    // percentage of an infinity is still infinite — because dart-sass builds
    // the color and serializes its channels rather than echoing the call.
    // `ModernColor::chan` renders it back as `calc(infinity)`. A degenerate
    // ALPHA folds to a number (`infinity` → 1 = opaque, `-infinity`/`NaN` → 0).
    let ch: (float?)[] = [
        root.builtins.color.math.modern_channel(channels[0], 1.0),
        root.builtins.color.math.modern_channel(channels[1], 1.0),
        root.builtins.color.math.modern_channel(channels[2], 1.0),
    ];
    let mc = root.value.ModernColor {
        space: space,
        channels: ch,
        alpha: root.builtins.color.math.modern_alpha(alpha),
    };
    root.value.Value_Color { _0: root.builtins.color.math.make_modern(mc) }
}

/// Serialize a `color()` description for its channel-count error message:
/// wrapped in parentheses for a multi-item list, bare for a single value
/// (`color(srgb)` → `srgb`).
function color_desc_css(desc: root.value.Value) -> string {
    match (desc) {
        root.value.Value_List { _0: let l } if l.items.length() > 1 => {
            root.builtins.color.list_paren_css(desc)
        },
        _ => desc.to_css(false),
    }
}

function fn_mix(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["color1", "color2", "weight", "method"];
    root.builtins.check_arity(4, pos_args, named, pos);
    let c1 = root.builtins.as_color(root.builtins.require(params, pos_args, named, 0, pos), pos);
    let c2 = root.builtins.as_color(root.builtins.require(params, pos_args, named, 1, pos), pos);
    let weight = match (root.builtins.arg(params, pos_args, named, 2)) {
        root.value.Value_Number { _0: let w } => {
            // A NaN is within no range, and the bounds carry the value's unit
            // (`200%` -> `0% and 100%`, `200` -> `0 and 100`).
            if (w.value.is_nan() || w.value < 0.0 || w.value > 100.0) {
                let unit = w.unit_string();
                throw root.error.Error.at(
                    `$weight: Expected ${w.to_css(false)} to be within 0${unit} and 100${unit}.`,
                    pos,
                );
            }
            w.value
        },
        let other: root.value.Value => {
            throw root.error.Error.at(
                `$weight: ${other.to_css(false)} is not a number.`,
                pos,
            );
        },
        _ => 50.0,
    };
    // A $method (CSS Color 4 interpolation method) triggers real color-space
    // interpolation in the named space; without it, the legacy mix runs (which
    // requires both colors to be legacy).
    if let method: root.value.Value = root.builtins.arg(params, pos_args, named, 3) {
        let space_hue = validate_mix_method(method, pos);
        return root.value.Value_Color {
            _0: root.builtins.color.math.interpolate_mix(c1, c2, weight, space_hue._0, space_hue._1),
        };
    }
    for (let i in baml.iter.Range.new(0, 2)) {
        let c = [c1, c2][i];
        if (!root.builtins.color.math.color_space_of(c).is_legacy()) {
            throw root.error.Error.at(
                `$color${i + 1}: To use color.mix() with non-legacy color ${c.to_css(false)}, you must provide a $method.`,
                pos,
            );
        }
    }
    let p = weight / 100.0;
    let w = p * 2.0 - 1.0;
    // A missing alpha weighs as 0, not as the opaque 1.0 the color mirrors it
    // as: `mix(hsl(240 100% 50% / none), white, 50%)` is
    // `rgba(255, 255, 255, 0.5)`, the transparent blue contributing no color.
    let a1 = root.builtins.color.math.stored_alpha(c1);
    let a2 = root.builtins.color.math.stored_alpha(c2);
    let a = a1 - a2;
    let w1 = (
        (
            if (root.std.feq(w * a, -1.0)) {
                w
            } else {
                (w + a) / (1.0 + w * a)
            }
        )
            + 1.0
    )
        / 2.0;
    let w2 = 1.0 - w1;
    let r = c1.r * w1 + c2.r * w2;
    let g = c1.g * w1 + c2.g * w2;
    let b = c1.b * w1 + c2.b * w2;
    let alpha = a1 * p + a2 * (1.0 - p);
    root.value.Value_Color { _0: root.builtins.color_ext.computed(r, g, b, alpha) }
}

/// The color-interpolation spaces dart-sass accepts for `mix()`'s `$method`,
/// with whether each is *polar* (carries a hue channel: a hue interpolation
/// method may follow it).
function mix_method_space(name: string) -> bool? {
    match (name) {
        "hsl" | "hwb" | "lch" | "oklch" => true,
        "rgb"
            | "srgb"
            | "srgb-linear"
            | "display-p3"
            | "a98-rgb"
            | "prophoto-rgb"
            | "rec2020"
            | "xyz"
            | "xyz-d50"
            | "xyz-d65"
            | "lab"
            | "oklab" =>
        {
            false
        },
        _ => null,
    }
}

/// The hue interpolation method for a polar `mix()` `$method`.
enum HueMethod {
    Shorter,
    Longer,
    Increasing,
    Decreasing,
}

/// Validate a `mix()` `$method` value (a CSS Color 4 interpolation method:
/// `srgb`, `oklch longer hue`, …). Errors match dart-sass exactly. Returns the
/// resolved interpolation space and hue method.
function validate_mix_method(
    method: root.value.Value,
    pos: root.scanner.Pos,
) -> root.std.Tuple2<root.value.ColorSpace, HueMethod> {
    // PORT: `err` builds the error; `return err(…)` → `throw err(…)`.
    let err = (msg: string) -> root.error.Error {
        root.error.Error.at(msg, pos)
    };
    // The method is either a bare color-space string or a space-separated
    // list `space [<hue> hue]`.
    let items: root.value.Value[] = match (method) {
        root.value.Value_List { _0: let l } if l.sep == root.value.ListSep.Space => {
            root.std.clone_vec(l.items)
        },
        let single => [single],
    };
    let space_val = items[0];
    let space = match (space_val) {
        root.value.Value_Str { _0: let s } if !s.quoted => s.text,
        root.value.Value_Str { _0: let s } => {
            throw err(`$method: Expected "${s.text}" to be an unquoted string.`);
        },
        let other => {
            throw err(`$method: ${other.to_css(false)} is not a string.`);
        },
    };
    let space = root.std.ascii_lower(space);
    let polar = match (mix_method_space(space)) {
        let p: bool => p,
        _ => {
            throw err(`$method: Unknown color space "${space}".`);
        },
    };
    let cspace: root.value.ColorSpace = root.value.ColorSpace_from_name(space) ?? root.value.ColorSpace.Srgb;
    // A bare color space (no trailing hue method) is always valid.
    if (items.length() == 1) {
        return root.std.Tuple2<root.value.ColorSpace, HueMethod> { _0: cspace, _1: HueMethod.Shorter };
    }
    // `space <hue-method> hue`: the second token names a hue interpolation
    // method and the list must end with the literal `hue`.
    let method_token = match (items[1]) {
        root.value.Value_Str { _0: let s } if !s.quoted => s.text,
        // A parenthesized list shows wrapped in parens (`(decreasing hue)`).
        root.value.Value_List {} => {
            throw err(`$method: ${root.builtins.color.list_paren_css(items[1])} is not a string.`);
        },
        let other => {
            throw err(`$method: ${other.to_css(false)} is not a string.`);
        },
    };
    // The hue-method keyword is validated before the trailing `hue` keyword,
    // matching dart-sass's error order.
    let hue_method: HueMethod = match (root.std.ascii_lower(method_token)) {
        "shorter" => HueMethod.Shorter,
        "longer" => HueMethod.Longer,
        "increasing" => HueMethod.Increasing,
        "decreasing" => HueMethod.Decreasing,
        "specified" => {
            throw err("$method: Unknown hue interpolation method specified.");
        },
        let other => {
            throw err(`$method: Unknown hue interpolation method ${other}.`);
        },
    };
    // The list must end with an unquoted `hue` keyword.
    let last = items[items.length() - 1];
    let last_is_hue = match (last) {
        root.value.Value_Str { _0: let s }
            if !s.quoted && root.std.eq_ignore_ascii_case(s.text, "hue") => true,
        _ => false,
    };
    if (items.length() == 2) {
        // `space <method>` with no trailing `hue`.
        throw err(`$method: Expected unquoted string "hue" after (${method.to_css(false)}).`);
    }
    if (!last_is_hue) {
        throw err(
            `$method: Expected unquoted string "hue" at the end of (${method.to_css(false)}), was ${last.to_css(false)}.`,
        );
    }
    // A hue method may not be applied to a rectangular (non-polar) space.
    if (!polar) {
        throw err(
            `$method: Hue interpolation method "HueInterpolationMethod.${method_token} hue" may not be set for rectangular color space ${space}.`,
        );
    }
    root.std.Tuple2<root.value.ColorSpace, HueMethod> { _0: cspace, _1: hue_method }
}

function fn_adjust_lightness(
    name: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
    sign: float,
) -> root.value.Value {
    let params = ["color", "amount"];
    root.builtins.check_arity(2, pos_args, named, pos);
    let c = root.builtins.as_color(root.builtins.require(params, pos_args, named, 0, pos), pos);
    root.builtins.require_legacy_color(c, name, pos);
    let amount = match (root.builtins.require(params, pos_args, named, 1, pos)) {
        root.value.Value_Number { _0: let num } => {
            // A NaN is within no range, and the bounds carry the value's unit.
            if (num.value.is_nan() || num.value < 0.0 || num.value > 100.0) {
                let unit = num.unit_string();
                throw root.error.Error.at(
                    `$amount: Expected ${num.to_css(false)} to be within 0${unit} and 100${unit}.`,
                    pos,
                );
            }
            num.value
        },
        let other => {
            throw root.error.Error.at(
                `$amount: ${other.to_css(false)} is not a number.`,
                pos,
            );
        },
    };
    // dart shifts the hsl LIGHTNESS and returns the color in its own space,
    // so an `hsl()` input stays `hsl` rather than collapsing to a hex.
    root.value.Value_Color {
        _0: root.builtins.color.math.legacy_hsl_adjust(c, (ch: float[]) -> void {
            ch[2] = root.std.fclamp(ch[2] + sign * amount, 0.0, 100.0);
        }),
    }
}

function fn_percentage(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["number"];
    root.builtins.check_arity(params.length(), pos_args, named, pos);
    let arg = root.builtins.require(params, pos_args, named, 0, pos);
    if let nv: root.value.Value_Number = arg {
        let num = nv._0;
        if (!num.is_unitless()) {
            throw root.error.Error.at(
                `$number: Expected ${num.to_css(false)} to have no units.`,
                pos,
            );
        }
    }
    let n = root.builtins.num(arg, pos);
    root.value.Value_Number { _0: root.value.Number.with_unit(n * 100.0, "%") }
}

function fn_channel(
    name: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["color"];
    root.builtins.check_arity(params.length(), pos_args, named, pos);
    let c = root.builtins.as_color(root.builtins.require(params, pos_args, named, 0, pos), pos);
    // The legacy red/green/blue getters only support legacy colors.
    let m = c.modern;
    let non_legacy = if (m != null) {
        !m.space.is_legacy()
    } else {
        false
    };
    if (non_legacy) {
        throw root.error.Error.at(
            `color.${name}() is only supported for legacy colors. Please use color.channel() instead with an explicit $space argument.`,
            pos,
        );
    }
    let v = match (name) {
        "red" => c.r,
        "green" => c.g,
        "blue" => c.b,
        _ => 0.0,
    };
    root.value.Value_Number { _0: root.value.Number.unitless(v.round()) }
}

/// Whether `text` is a Microsoft `alpha()` filter argument: ASCII letters,
/// optional whitespace, then `=` (dart-sass's `^[a-zA-Z]+\s*=` shape).
function is_ms_filter_arg(text: string) -> bool {
    // PORT: the peekable `char_indices()` iterator → an index cursor over the chars.
    let chars = text.chars();
    let idx = 0;
    let saw_letter = false;
    // One or more ASCII letters.
    while (idx < chars.length()) {
        let c = chars[idx];
        if (c.is_ascii_alphabetic()) {
            saw_letter = true;
            idx += 1;
        } else {
            break;
        }
    }
    if (!saw_letter) {
        return false;
    }
    // Optional whitespace, then a `=`.
    while (idx < chars.length()) {
        let c = chars[idx];
        if (root.std.is_whitespace(c)) {
            idx += 1;
        } else {
            break;
        }
    }
    chars.at(idx) == "="
}

/// The arguments of a proprietary Microsoft `alpha()` filter call, in the order
/// dart writes them back out, or `None` when the call is not that overload.
///
/// Each argument must be an unquoted string matching `<identifier>=…` (an IE
/// `alpha(opacity=80)` hack, produced by the single-`=` operator); the whole
/// call is then passed through verbatim as a CSS function instead of the
/// argument being read as a colour. `1=c` is not one, so it stays a non-colour
/// error.
///
/// dart declares `alpha` TWICE — `alpha($color)` beside the variadic
/// `alpha($args...)` — and takes this path from either, so the single argument
/// may also arrive by name: `alpha($color: opacity=20)` passes through just as
/// `alpha(opacity=20)` does. The variadic form binds positional arguments only.
///
/// ONE definition, for the same reason the four filter names have one: the
/// dispatcher passes the call through here, the evaluator must not deprecate
/// what it passed through, and on `sass:color` it must deprecate exactly this
/// (`color-module-compat`, #124).
function ms_filter_args(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
) -> root.value.Value[]? {
    let args: root.value.Value[] = if (named.length() == 0) {
        if (pos_args.length() == 0) {
            return null;
        }
        root.std.clone_vec(pos_args)
    } else if (pos_args.length() == 0 && named.length() == 1 && named[0]._0 == "color") {
        [named[0]._1]
    } else {
        return null;
    };
    if (
        args.every((v) -> {
            match (v) {
                root.value.Value_Str { _0: let s } if !s.quoted && is_ms_filter_arg(s.text) => true,
                _ => false,
            }
        })
    ) {
        args
    } else {
        null
    }
}

/// The CSS text such a call passes through as — dart's `_functionString`, and
/// also the `Recommendation:` line of its deprecation.
function ms_filter_text(args: root.value.Value[]) -> string {
    let inner = args
        .map((v) -> {
            v.to_css(false)
        })
        .join(", ");
    `alpha(${inner})`
}

function fn_alpha(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["color"];
    // The Microsoft filter overload. dart-sass accepts it for `color.alpha()`
    // too (with a `color-module-compat` deprecation to stderr) rather than
    // enforcing the one-argument count.
    let args = ms_filter_args(pos_args, named);
    if (args != null) {
        return root.value.Value_Str {
            _0: root.value.SassStr { text: ms_filter_text(args), quoted: false },
        };
    }
    // `alpha()` is declared in dart as an OVERLOADED function (the `$color`
    // getter beside the variadic ms-filter form above), and its overload
    // dispatch reports the arity without dart's "positional" wording even when
    // a named argument is present: `alpha(red, 1, $nope: 2)` is "Only 1
    // argument allowed, but 2 were passed." where every non-overloaded member
    // says "Only 1 positional argument allowed". Hence the empty `named` here.
    root.builtins.check_arity(1, pos_args, [], pos);
    let c = root.builtins.as_color(root.builtins.require(params, pos_args, named, 0, pos), pos);
    // The legacy alpha getter only supports legacy colors.
    let m = c.modern;
    let non_legacy = if (m != null) {
        !m.space.is_legacy()
    } else {
        false
    };
    if (non_legacy) {
        throw root.error.Error.at(
            "color.alpha() is only supported for legacy colors. Please use color.channel() instead.",
            pos,
        );
    }
    root.value.Value_Number {
        _0: root.value.Number.unitless(root.builtins.color.math.stored_alpha(c)),
    }
}

/// Build a modern legacy color (rgb/hsl) from a [`Channels`] set when it
/// contains a `none` channel (and no real special function), matching
/// dart-sass's modern parsing. Returns `Ok(None)` when there is no `none`
/// channel or a real special function is present (the caller falls through to
/// its existing handling).
function legacy_none_color(
    channels: Channels,
    space: root.value.ColorSpace,
    pos: root.scanner.Pos,
) -> root.value.Value? {
    let channels_alpha = channels.alpha;
    let comps_special = channels.comps.some((v) -> {
        root.builtins.color.is_special_legacy(v)
    });
    let alpha_special = if (channels_alpha != null) {
        root.builtins.color.is_special_legacy(channels_alpha)
    } else {
        false
    };
    if (comps_special || alpha_special) {
        return null;
    }
    let comps_none = channels.comps.some((v) -> {
        root.builtins.color.is_none_keyword(v)
    });
    let alpha_none = if (channels_alpha != null) {
        root.builtins.color.is_none_keyword(channels_alpha)
    } else {
        false
    };
    if (!(comps_none || alpha_none)) {
        return null;
    }
    if (channels.comps.length() != 3) {
        return null;
    }
    // This path returns before the caller's own validation, so it runs the
    // same checks: a `none` channel exempts ITSELF, not the call — `rgb(none
    // 1px 0)` is still the green channel's unit error, and a positional
    // `none` is not a channel at all (`rgb(none, 1px, 0)`).
    let names: string[] = match (space) {
        root.value.ColorSpace.Hsl => ["hue", "saturation", "lightness"],
        _ => ["red", "green", "blue"],
    };
    channels.validate_numeric(names, pos);
    channels.validate_positional_numeric(names, pos);
    root.builtins.color.validate_alpha_unit(channels.alpha, pos);
    if (space != root.value.ColorSpace.Hsl) {
        channels.validate_rgb_units(names, pos);
    }
    let comps = channels.comps;
    let ch: (float?)[] = match (space) {
        root.value.ColorSpace.Hsl => {
            [
                if (root.builtins.color.is_none_keyword(comps[0])) {
                    null
                } else {
                    root.builtins.color.math.modern_hue(comps[0])
                },
                root.builtins.color.math.modern_channel(comps[1], 100.0),
                root.builtins.color.math.modern_channel(comps[2], 100.0),
            ]
        },
        // rgb: channels in 0..255.
        _ => {
            [
                root.builtins.color.math.modern_channel(comps[0], 255.0),
                root.builtins.color.math.modern_channel(comps[1], 255.0),
                root.builtins.color.math.modern_channel(comps[2], 255.0),
            ]
        },
    };
    let mc = root.value.ModernColor {
        space: space,
        channels: ch,
        alpha: root.builtins.color.math.modern_alpha(channels.alpha),
    };
    root.value.Value_Color { _0: root.builtins.color.math.make_modern(mc) }
}
