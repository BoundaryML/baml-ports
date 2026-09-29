// Ported from sasso `src/builtins/mod.rs` (namespace `root.builtins`).
//
// The built-in function library.
//
// Each family lives in its own module and exposes `try_call`, returning
// `Some(result)` for the names it owns and `None` otherwise. The
// dispatcher tries the families in turn and falls back to preserving an
// unknown function verbatim as a plain CSS call (`translate(...)`,
// `var(...)`), matching dart-sass.
//
// The modules are disjoint, so new families can be implemented in
// parallel: an implementer fills one `try_call` without touching another.

// The built-in function library.
//
// Each family lives in its own module and exposes `try_call`, returning
// `Some(result)` for the names it owns and `None` otherwise. The
// dispatcher tries the families in turn and falls back to preserving an
// unknown function verbatim as a plain CSS call (`translate(...)`,
// `var(...)`), matching dart-sass.
//
// The modules are disjoint, so new families can be implemented in
// parallel: an implementer fills one `try_call` without touching another.
// mod color → namespace `root.builtins.color`

// mod color_ext → namespace `root.builtins.color_ext`

// mod colorspace → namespace `root.builtins.colorspace`

// mod list → namespace `root.builtins.list`

// mod map → namespace `root.builtins.map`

// mod math → namespace `root.builtins.math`

// mod meta → namespace `root.builtins.meta`

// mod selector → namespace `root.builtins.selector`

// mod string → namespace `root.builtins.string`

// The plain-CSS filter overloads, in the one spelling both the dispatcher and
// the evaluator's deprecations read them from: the global rule, the narrower
// module rule, and the Microsoft `alpha()` form.
// PORT: `pub(crate) use color::legacy::{ms_filter_args, ms_filter_text}` and
// `pub(crate) use color_ext::{…}` — re-exports do not exist in BAML; callers
// use the defining module's path.

// dart-sass `inspect()` serialization. The one-rule-wider form a diagnostic
// embeds (`Value::to_inspect_message`) is built on it.
// PORT: `pub(crate) use meta::inspect_value` — use `root.builtins.meta.inspect_value`.

// Color-space conversion, needed by `ModernColor::to_css` for the
// out-of-range `color-mix(in …, color(xyz …) 100%, black)` fallback.
// PORT: `pub(crate) use color::convert_modern` — use the defining module's path.
// Color <-> space conversion helpers reused by the host-function value bridge
// (src/host_fn.rs) to serialize/reconstruct colors across the embedder boundary.
// PORT: `pub(crate) use color::{legacy_to_modern, make_modern_in}` — likewise.

// The engine's srgb <-> hsl and hwb -> srgb (dart's exact formulas): the
// legacy out-of-gamut rgb serialization in `value.rs` converts one way, and
// the degenerate-channel `hsl()` constructor the other.
// PORT: `pub(crate) use colorspace::{hsl_to_srgb, hwb_to_srgb, srgb_to_hsl}` —
// use `root.builtins.colorspace.*`.

/// PORT: helper — unwraps a family's `Some(result)`: the `Ok` value, or the
/// `Err` re-thrown (Rust `return r;` of a `Result<Value, Error>`).
function result_value(
    r: root.std.Ok<root.value.Value> | root.std.Err<root.error.Error>,
) -> root.value.Value {
    match (r) {
        let ok: root.std.Ok<root.value.Value> => ok.value,
        let err: root.std.Err<root.error.Error> => throw err.error,
    }
}

/// Dispatch a function call by name across the builtin families.
function call(
    name: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    // `_` and `-` are the same character in a Sass identifier, so a global
    // built-in answers to either spelling (`map_get(…)` IS `map-get(…)`), like
    // the module members `call_module` already normalizes. Only the LOOKUP is
    // canonicalized: a name that turns out to be no builtin at all falls
    // through to plain CSS spelled exactly as it was written.
    let written = name;
    let lookup = canonical_name(name);
    let name = lookup;
    let r = root.builtins.color.try_call(name, pos_args, named, pos);
    if (r != null) {
        return result_value(r);
    }
    let r = root.builtins.color_ext.try_call(name, pos_args, named, pos);
    if (r != null) {
        return result_value(r);
    }
    let r = root.builtins.math.try_call(name, pos_args, named, pos);
    if (r != null) {
        return result_value(r);
    }
    let r = root.builtins.string.try_call(name, pos_args, named, pos);
    if (r != null) {
        return result_value(r);
    }
    // Map runs before list so `length`/`nth` on a map are handled here; the
    // map family declines those names for non-map arguments, falling through.
    let r = root.builtins.map.try_call(name, pos_args, named, pos);
    if (r != null) {
        return result_value(r);
    }
    let r = root.builtins.list.try_call(name, pos_args, named, pos);
    if (r != null) {
        return result_value(r);
    }
    let r = root.builtins.meta.try_call(name, pos_args, named, pos);
    if (r != null) {
        return result_value(r);
    }
    let r = root.builtins.selector.try_call(name, pos_args, named, pos);
    if (r != null) {
        return result_value(r);
    }
    plain_css_function(written, pos_args, named, pos)
}

/// The `[color-functions]` suggestions for a deprecated legacy `sass:color`
/// member, or `None` when the member carries no such deprecation. See
/// [`color::deprecate`].
function color_function_suggestions(
    name: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
) -> string[]? {
    root.builtins.color.deprecate.suggestions(name, pos_args, named)
}

/// The name-only half of [`color_function_suggestions`]: whether `name` is a
/// legacy `sass:color` member that carries a `[color-functions]` deprecation at
/// all. Lets a caller reject a call before evaluating any suggestion text.
function color_function_deprecates(name: string) -> bool {
    root.builtins.color.deprecate.deprecates(name)
}

/// A name in its canonical spelling: `_` is `-` in every Sass identifier. The
/// input is borrowed unchanged when it already holds no underscore, so the
/// common case allocates nothing.
function canonical_name(name: string) -> string {
    if (name.includes("_")) {
        name.replace_all("_", "-")
    } else {
        name
    }
}

/// Whether `name` is a real Sass builtin function (as opposed to an unknown
/// plain CSS function that is preserved verbatim). Used by the evaluator to
/// decide whether a slash-division argument should collapse to its number:
/// Sass functions collapse it, plain CSS functions keep the `a/b` spelling.
///
/// This is a pure name-only ownership test: each family's `try_call` decides
/// ownership solely from the function name (returning `Some(..)` — possibly an
/// arity/type `Err` — for the names it owns, `None` otherwise). To kill the
/// old two-point sync hazard, each family now declares its owned names in a
/// `pub(super) const NAMES` placed directly above its `try_call` (the source of
/// truth), and this test is exactly the union of those per-family `NAMES`. A new
/// builtin is therefore a single-site change in its family module.
///
/// Two name-only subtleties mirror the dispatch exactly:
/// - the `math` family lowercases the name before matching (its functions
///   double as case-insensitive CSS calc functions like `SiN`), so `math::NAMES`
///   holds the *lowercase* names and is tested against the lowercased input;
/// - `length`/`nth` are owned unconditionally by the `list` family (the `map`
///   family only claims them when the first argument is a map, which never
///   removes them from the builtin set), so they live in `list::NAMES` and are
///   deliberately absent from `map::NAMES`.
function is_builtin(name: string) -> bool {
    // Underscore and dash are one character in a Sass identifier, so the test
    // runs on the canonical spelling (`str_index` is `str-index`).
    let canonical = canonical_name(name);
    let name = canonical;
    // The `math` family matches `name.to_ascii_lowercase()`, so it owns these
    // names case-insensitively.
    if (is_math_builtin_name(name)) {
        return true;
    }
    let families: string[][] = [
        root.builtins.color.NAMES(),
        root.builtins.color.MODERN_NAMES(),
        root.builtins.color_ext.NAMES(),
        root.builtins.string.NAMES(),
        root.builtins.map.NAMES(),
        root.builtins.list.NAMES(),
        root.builtins.meta.NAMES(),
        root.builtins.selector.NAMES(),
    ];
    families.some((family: string[]) -> bool {
        family.includes(name)
    })
}

/// Whether `name` (case-insensitively) is a `math` builtin. `math::NAMES` holds
/// the lowercase spellings, because the family's own dispatcher
/// (`math::try_call`) lowercases before it matches — so `SiN` and `sin` both count.
/// The comparison here folds case in place instead of allocating a lowercase
/// copy of `name` just to compare it.
function is_math_builtin_name(name: string) -> bool {
    root.builtins.math.NAMES().some((n: string) -> bool {
        root.std.eq_ignore_ascii_case(name, n)
    })
}

// ---- shared argument helpers, available to every family module --------
/// The argument at index `i`: positional first, then by name (`params[i]`).
function arg(
    params: string[],
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    i: int,
) -> root.value.Value? {
    let v = pos_args.at(i);
    if (v != null) {
        return v;
    }
    let pname = params.at(i);
    if (pname == null) {
        return null;
    }
    let found = named.find((t: root.std.Tuple2<string, root.value.Value>) -> bool {
        t._0 == pname
    });
    if (found != null) {
        found._1
    } else {
        null
    }
}

/// Like [`arg`] but errors with a "missing argument" message when absent.
///
/// dart names only the PARAMETER (`Missing argument $amount.`) — never the
/// function — because the frame underneath already points at the declaration
/// the parameter belongs to. A user-defined function's message has always read
/// that way here; this is the built-in half of the same sentence.
function require(
    params: string[],
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    i: int,
    pos: root.scanner.Pos,
) -> root.value.Value {
    let v = arg(params, pos_args, named, i);
    if (v == null) {
        let pname = params.at(i) ?? "";
        throw root.error.Error.at("Missing argument $" + pname + ".", pos);
    }
    v
}

/// dart's arity check (`ArgumentDeclaration.verify`): only POSITIONAL
/// arguments count against a function's parameter count, and the moment any
/// NAMED argument is present the message says so —
/// `lighten(red, 10%, 3, $nope: 1)` is "Only 2 positional arguments allowed,
/// but 3 were passed.", counting the three positional ones, not the four
/// arguments written.
///
/// A named argument that matches no parameter is a separate error, which dart
/// raises after this one — and which sasso does not raise at all yet outside
/// `list.rs`'s `validate_args` (momiji-rs/sasso#62). Nothing downstream checks
/// it: `require` only looks a parameter up BY name, so an unrecognized one is
/// simply never read.
function check_arity(
    max: int,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> void {
    let n = pos_args.length();
    if (n <= max) {
        return;
    }
    let noun = if (max == 1) {
        "argument"
    } else {
        "arguments"
    };
    let kind = if (named.length() == 0) {
        ""
    } else {
        "positional "
    };
    let verb = if (n == 1) {
        "was"
    } else {
        "were"
    };
    throw root.error.Error.at(`Only ${max} ${kind}${noun} allowed, but ${n} ${verb} passed.`, pos);
}

/// Extract an `f64` from a number value (ignoring its unit).
function num(v: root.value.Value, pos: root.scanner.Pos) -> float {
    match (v) {
        root.value.Value_Number { _0: let n } => n.value,
        let other => throw root.error.Error.at(`${other.to_css(false)} is not a number.`, pos),
    }
}

/// Extract a color value.
function as_color(v: root.value.Value, pos: root.scanner.Pos) -> root.value.Color {
    match (v) {
        // PORT: `c.clone()` → a shallow copy, so a caller that mutates the
        // returned color does not alias the argument.
        root.value.Value_Color { _0: let c } => root.value.Color { ...c },
        let other => throw root.error.Error.at(`${other.to_css(false)} is not a color.`, pos),
    }
}

/// Reject a non-legacy color passed to a legacy-only modification function
/// (`darken`/`lighten`/`saturate`/`desaturate`/`opacify`/`transparentize`/
/// `adjust-hue`), matching dart-sass's "<fn>() is only supported for legacy
/// colors." error. `fname` is the called name (hyphenated, no `()`).
function require_legacy_color(c: root.value.Color, fname: string, pos: root.scanner.Pos) -> void {
    // PORT: `c.modern.as_ref().is_some_and(|m| !m.space.is_legacy())` → nested `if`s.
    let m = c.modern;
    if (m != null) {
        if (!m.space.is_legacy()) {
            throw root.error.Error.at(fname + "() is only supported for legacy colors. Please use color.adjust() instead with an explicit $space argument.", pos);
        }
    }
}

/// Extract an RGB channel value (`0..=255`), converting a percentage.
function channel(v: root.value.Value, pos: root.scanner.Pos) -> float {
    match (v) {
        root.value.Value_Number { _0: let n } => {
            if (n.unit() == "%") {
                // `255 * value / 100`, in dart's order: see `modern_channel`.
                f64_clamp(255.0 * n.value / 100.0, 0.0, 255.0)
            } else {
                f64_clamp(n.value, 0.0, 255.0)
            }
        },
        let other => throw root.error.Error.at(`${other.to_css(false)} is not a number.`, pos),
    }
}

/// Clamp a value to `[0, 1]` (e.g. alpha).
function clamp01(v: float) -> float {
    f64_clamp(v, 0.0, 1.0)
}

/// PORT: helper — Rust `f64::clamp`, which returns NaN for a NaN input.
/// `root.std.fclamp` compares with BAML's total float order (NaN is above
/// every number), so it would clamp NaN to `hi`.
function f64_clamp(x: float, lo: float, hi: float) -> float {
    if (x.is_nan()) {
        return x;
    }
    root.std.fclamp(x, lo, hi)
}

/// Preserve an unknown function call verbatim as an unquoted CSS string.
/// Plain CSS has no keyword arguments, and a value with no CSS
/// representation (an empty unbracketed list, a map) is rejected — while
/// `null` serializes to nothing and a bracketed empty list stays `[]`
/// (dart-sass).
function plain_css_function(
    name: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    if (named.length() != 0) {
        throw root.error.Error.at("Plain CSS functions don't support keyword arguments.", pos);
    }
    let parts: string[] = [];
    for (let v in pos_args) {
        match (v) {
            root.value.Value_List { _0: let l } if l.items.length() == 0 && !l.bracketed => {
                throw root.error.Error.at("() isn't a valid CSS value.", pos);
            },
            root.value.Value_Map {} => {
                throw root.error.Error.at(`${v.to_css(false)} isn't a valid CSS value.`, pos);
            },
            _ => parts.push(v.to_css(false)),
        }
    }
    root.value.Value_Str {
        _0: root.value.SassStr { text: `${name}(${parts.join(", ")})`, quoted: false },
    }
}

// ---- built-in module system (`@use "sass:<mod>"`) ----------------------
/// The `sass:*` member dart names when a GLOBAL built-in with a module
/// equivalent is called — the `global-builtin` deprecation's `Use … instead.`
/// line. `None` for a global dart keeps: a CSS function it shares a name with
/// (`abs`, `round`, `min`, `sqrt`, …), `if()` (which has its own deprecation),
/// and `ie-hex-str`, which has no module form.
///
/// Every entry was measured against dart-sass 1.103.1 — the mapping is not
/// mechanical: the legacy colour adjusters all point at `color.adjust`,
/// `unitless` at `math.is-unitless`, `comparable` at `math.compatible`, and
/// `list-separator` at `list.separator`.
function global_builtin_replacement(name: string) -> string? {
    // Matched EXACTLY apart from the underscore spelling every Sass identifier
    // allows: dart resolves these Sass-only globals case-sensitively, so
    // `MAP-GET(…)` and `FLOOR(…)` are plain CSS to it — no call, and so no
    // deprecation — while `map_get(…)` is the deprecated `map-get(…)`. (The
    // case-insensitive globals are the ones CSS shares, `abs`/`round`/`min`/
    // `sin`/…, none of which are deprecated.)
    let canonical = canonical_name(name);
    match (canonical) {
        // sass:color — the getters keep their names, every legacy adjuster
        // becomes `color.adjust`.
        "red" => "color.red",
        "green" => "color.green",
        "blue" => "color.blue",
        "hue" => "color.hue",
        "saturation" => "color.saturation",
        "lightness" => "color.lightness",
        "alpha" => "color.alpha",
        "opacity" => "color.opacity",
        "mix" => "color.mix",
        "invert" => "color.invert",
        "grayscale" => "color.grayscale",
        "complement" => "color.complement",
        "change-color" => "color.change",
        "scale-color" => "color.scale",
        "adjust-color"
            | "adjust-hue"
            | "lighten"
            | "darken"
            | "saturate"
            | "desaturate"
            | "opacify"
            | "fade-in"
            | "transparentize"
            | "fade-out" =>
        {
            "color.adjust"
        },
        // sass:math — only the members CSS has no function for.
        "percentage" => "math.percentage",
        "floor" => "math.floor",
        "ceil" => "math.ceil",
        "random" => "math.random",
        "unit" => "math.unit",
        "unitless" => "math.is-unitless",
        "comparable" => "math.compatible",
        // sass:list
        "length" => "list.length",
        "nth" => "list.nth",
        "set-nth" => "list.set-nth",
        "join" => "list.join",
        "append" => "list.append",
        "zip" => "list.zip",
        "index" => "list.index",
        "list-separator" => "list.separator",
        "is-bracketed" => "list.is-bracketed",
        // sass:map
        "map-get" => "map.get",
        "map-merge" => "map.merge",
        "map-remove" => "map.remove",
        "map-keys" => "map.keys",
        "map-values" => "map.values",
        "map-has-key" => "map.has-key",
        // sass:string
        "quote" => "string.quote",
        "unquote" => "string.unquote",
        "to-upper-case" => "string.to-upper-case",
        "to-lower-case" => "string.to-lower-case",
        "str-length" => "string.length",
        "str-index" => "string.index",
        "str-insert" => "string.insert",
        "str-slice" => "string.slice",
        "unique-id" => "string.unique-id",
        // sass:meta
        "type-of" => "meta.type-of",
        "inspect" => "meta.inspect",
        "keywords" => "meta.keywords",
        "call" => "meta.call",
        "get-function" => "meta.get-function",
        "function-exists" => "meta.function-exists",
        "feature-exists" => "meta.feature-exists",
        "variable-exists" => "meta.variable-exists",
        "global-variable-exists" => "meta.global-variable-exists",
        "mixin-exists" => "meta.mixin-exists",
        "content-exists" => "meta.content-exists",
        // sass:selector
        "selector-parse" => "selector.parse",
        "selector-append" => "selector.append",
        "selector-nest" => "selector.nest",
        "selector-unify" => "selector.unify",
        "selector-replace" => "selector.replace",
        "selector-extend" => "selector.extend",
        "is-superselector" => "selector.is-superselector",
        "simple-selectors" => "selector.simple-selectors",
        _ => {
            return null;
        },
    }
}

/// Whether `module` names a built-in `sass:*` module this build supports.
function is_module(module: string) -> bool {
    module_name(module) != null
}

/// The canonical name of the built-in module `module` names, as a `'static`
/// string, or `None` when there is no such module.
///
/// The set is closed and known at compile time, so a namespace bound by
/// `@use "sass:math"` points at the program's own copy of the name instead of
/// owning one: the tables that hold them are cloned into every callable's
/// lexical environment and read back on every `ns.member()` call.
function module_name(module: string) -> string? {
    let m = root.value.BuiltinModule_from_name(module);
    if (m != null) {
        m.name()
    } else {
        null
    }
}

/// Translate a `(module, member)` pair to the global builtin name that
/// implements it, or `None` when the member is not a function this build can
/// dispatch to a global implementation. The global implementations are reused
/// verbatim — module members are just renamed views of them.
function module_member_to_global(module: string, member: string) -> string? {
    // Names returned as `Some` must be real global builtins (so the dispatcher
    // finds them). Members handled specially (e.g. `math.div`) or unsupported
    // (color-space math, first-class functions) are deliberately absent.
    match (module) {
        "math" => match (member) {
            "abs" => "abs",
            "ceil" => "ceil",
            "floor" => "floor",
            // `math.min`/`math.max`/`math.clamp`/`math.round` are the numeric
            // forms (dispatched directly in `call_module`), distinct from the
            // global CSS-calc functions which preserve unknown args.
            "sqrt" => "sqrt",
            "pow" => "pow",
            "exp" => "exp",
            "log" => "log",
            "sin" => "sin",
            "cos" => "cos",
            "tan" => "tan",
            "asin" => "asin",
            "acos" => "acos",
            "atan" => "atan",
            "atan2" => "atan2",
            "hypot" => "hypot",
            "sign" => "sign",
            "percentage" => "percentage",
            "unit" => "unit",
            "is-unitless" => "unitless",
            "compatible" => "comparable",
            "random" => "random",
            // `div` is implemented directly in `call_module`; the module
            // variables are resolved by `module_var`.
            _ => null,
        },
        "map" => match (member) {
            "get" => "map-get",
            "merge" => "map-merge",
            "remove" => "map-remove",
            "keys" => "map-keys",
            "values" => "map-values",
            "has-key" => "map-has-key",
            // `set`/`deep-merge`/`deep-remove` are module-only (no global alias
            // in dart-sass); they are dispatched directly in `call_module`.
            _ => null,
        },
        "string" => match (member) {
            "length" => "str-length",
            "insert" => "str-insert",
            "index" => "str-index",
            "slice" => "str-slice",
            "quote" => "quote",
            "unquote" => "unquote",
            "to-upper-case" => "to-upper-case",
            "to-lower-case" => "to-lower-case",
            "unique-id" => "unique-id",
            // `split` is module-only (no global alias); dispatched in
            // `call_module`.
            _ => null,
        },
        "list" => match (member) {
            "length" => "length",
            "nth" => "nth",
            "set-nth" => "set-nth",
            "append" => "append",
            "join" => "join",
            "zip" => "zip",
            "index" => "index",
            "separator" => "list-separator",
            "is-bracketed" => "is-bracketed",
            _ => null,
        },
        "selector" => match (member) {
            "nest" => "selector-nest",
            "append" => "selector-append",
            "extend" => "selector-extend",
            "replace" => "selector-replace",
            "unify" => "selector-unify",
            "parse" => "selector-parse",
            "is-superselector" => "is-superselector",
            "simple-selectors" => "simple-selectors",
            _ => null,
        },
        "color" => match (member) {
            // Legacy members map to the global color functions.
            "adjust" => "adjust-color",
            "scale" => "scale-color",
            "change" => "change-color",
            "red" => "red",
            "green" => "green",
            "blue" => "blue",
            "hue" => "hue",
            "saturation" => "saturation",
            "lightness" => "lightness",
            // `whiteness`/`blackness` have no global alias in dart-sass (they
            // live only in the `sass:color` module list) — they are dispatched
            // directly in `call_module` via `color_ext::call_module_member`.
            "alpha" => "alpha",
            "opacity" => "opacity",
            "grayscale" => "grayscale",
            "complement" => "complement",
            "invert" => "invert",
            "mix" => "mix",
            "ie-hex-str" => "ie-hex-str",
            // Modern CSS Color 4 color-space members. These dispatch to the
            // color-space-aware implementations in the color builtin family
            // under disambiguated global names.
            "space" => "color-space",
            "channel" => "color-channel",
            "to-space" => "color-to-space",
            "is-legacy" => "color-is-legacy",
            "is-missing" => "color-is-missing",
            "is-in-gamut" => "color-is-in-gamut",
            "is-powerless" => "color-is-powerless",
            "to-gamut" => "color-to-gamut",
            "same" => "color-same",
            _ => null,
        },
        "meta" => match (member) {
            "type-of" => "type-of",
            "inspect" => "inspect",
            "feature-exists" => "feature-exists",
            "calc-name" => "calc-name",
            "calc-args" => "calc-args",
            // `keywords`, `call`, `get-function`, the `*-exists`/`get-mixin`/
            // `apply`/`module-*` members need evaluator context or first-class
            // functions not available in this value-only dispatch — left
            // unsupported (Undefined function).
            _ => null,
        },
        _ => null,
    }
}

/// Whether `module` exposes `member` as a callable function (used by the
/// evaluator to resolve unprefixed `@use … as *` members).
/// The `sass:meta` module's function members (dart-sass 1.100), for
/// `meta.module-functions("meta")` and `$module`-qualified lookups.
function META_FUNCTION_NAMES() -> string[] {
    [
        "accepts-content",
        "calc-args",
        "calc-name",
        "call",
        "content-exists",
        "feature-exists",
        "function-exists",
        "get-function",
        "get-mixin",
        "global-variable-exists",
        "inspect",
        "keywords",
        "mixin-exists",
        "module-functions",
        "module-mixins",
        "module-variables",
        "type-of",
        "variable-exists",
    ]
}

/// The `sass:meta` module's mixin members.
function META_MIXIN_NAMES() -> string[] {
    ["apply", "load-css"]
}

/// The `sass:meta` members that are ALSO global functions and are owned by the
/// evaluator rather than by this value-only layer: each resolves against the
/// evaluator's scopes, definitions or call state, so none of them appears in a
/// family `NAMES` table and [`is_builtin`] does not know them. dart exposes
/// them like any other global — callable, referenceable through
/// `get-function`, and deprecated for being global — so the places that need
/// the full global picture consult this list alongside `is_builtin`.
function EVAL_GLOBAL_NAMES() -> string[] {
    [
        "call",
        "content-exists",
        "function-exists",
        "get-function",
        "global-variable-exists",
        "keywords",
        "mixin-exists",
        "variable-exists",
    ]
}

function module_has_member(module: string, member: string) -> bool {
    let canonical = canonical_name(member);
    let member = canonical;
    if (module == "meta" && META_FUNCTION_NAMES().includes(member)) {
        return true;
    }
    if (
        module == "math"
            && (
                member == "div"
                    || member == "clamp"
                    || member == "min"
                    || member == "max"
                    || member == "round"
            )
    ) {
        return true;
    }
    if (module == "map" && (member == "set" || member == "deep-merge" || member == "deep-remove")) {
        return true;
    }
    if (module == "string" && member == "split") {
        return true;
    }
    // `color.hwb` (comma form) and the deprecated `color.whiteness`/
    // `color.blackness` getters are module-only: they have no global alias, so
    // `module_member_to_global` cannot see them.
    if (module == "color" && (member == "hwb" || member == "whiteness" || member == "blackness")) {
        return true;
    }
    // The nine adjusters CSS Color 4 removed are members that always FAIL, and
    // that distinction is what this predicate answers: they are found by
    // `meta.function-exists`, captured by `meta.get-function`, re-exported by
    // `@forward "sass:color"`, and — the visible half — SHADOW the global of the
    // same name under `@use "sass:color" as *`, where dart reports the removal
    // instead of running the deprecated global. See [`color::removed`].
    if (module == "color" && root.builtins.color.removed.is_member(member)) {
        return true;
    }
    module_member_to_global(module, member) != null
}

/// Call a module member `module.member(args)`, dispatching to the reused global
/// implementation. An unknown member is "Undefined function." (dart-sass).
function call_module(
    module: string,
    member: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    // Member names are dash/underscore-interchangeable like every Sass
    // identifier (`string.unique_id()` is `string.unique-id()`).
    // PORT: the Rust `let normalized;` borrow holder is not needed.
    let member = if (member.includes("_")) {
        member.replace_all("_", "-")
    } else {
        member
    };
    // `math.div(a, b)` is true (always-divide) division, unit-aware.
    if (module == "math" && member == "div") {
        return root.builtins.math.module_div(pos_args, named, pos);
    }
    // `math.clamp`/`math.min`/`math.max` are the numeric forms, not the
    // CSS-calc functions of the same name.
    if (module == "math") {
        match (member) {
            "clamp" => {
                return root.builtins.math.module_clamp(pos_args, named, pos);
            },
            "min" => {
                return root.builtins.math.module_min_max(pos_args, named, pos, true);
            },
            "max" => {
                return root.builtins.math.module_min_max(pos_args, named, pos, false);
            },
            "round" => {
                return root.builtins.math.module_round(pos_args, named, pos);
            },
            _ => {},
        };
    }
    // `sass:map` members without a global alias (`set`, `deep-merge`,
    // `deep-remove`).
    if (module == "map") {
        let r = root.builtins.map.call_module_member(member, pos_args, named, pos);
        if (r != null) {
            return result_value(r);
        }
    }
    // `sass:string` members without a global alias (`split`).
    if (module == "string") {
        let r = root.builtins.string.call_module_member(member, pos_args, named, pos);
        if (r != null) {
            return result_value(r);
        }
    }
    // `sass:list` members without a global alias (`slash`).
    if (module == "list") {
        let r = root.builtins.list.call_module_member(member, pos_args, named, pos);
        if (r != null) {
            return result_value(r);
        }
    }
    // `sass:color` members without a global alias (the comma-form `hwb`, and
    // the deprecated HWB getters `whiteness`/`blackness`).
    if (module == "color") {
        // The removed adjusters go first: they own their names outright on this
        // module (the surviving implementations of those names are GLOBAL only),
        // and their message is the whole point of the member existing.
        let r = root.builtins.color.removed.call_module_member(member, pos_args, named, pos);
        if (r != null) {
            return result_value(r);
        }
        let r = root.builtins.color.legacy.call_module_member(member, pos_args, named, pos);
        if (r != null) {
            return result_value(r);
        }
        let r = root.builtins.color_ext.call_module_member(member, pos_args, named, pos);
        if (r != null) {
            return result_value(r);
        }
        // `color.grayscale`/`color.invert`/`color.opacity` keep the global
        // filter overload only for a NUMBER (passed through, and deprecated by
        // the evaluator). Every other plain-CSS-special argument — `var(--c)`,
        // `env(…)`, an unsimplifiable `calc()`, a slash-separated list — is a
        // colour argument here and fails as one, where the global spelling
        // passes it through verbatim. `module_filter_arg` is that rule, and the
        // deprecation asks it too, so the two cannot disagree (#124).
        let filter_arg = root.builtins.color_ext.module_filter_arg(member, pos_args, named);
        if (filter_arg != null) {
            if (filter_arg._0 == root.builtins.color_ext.ModuleFilterArg.NotAColor) {
                let v = filter_arg._1;
                throw root.error.Error.at("$color: " + v.to_css(false) + " is not a color.", pos);
            }
        }
    }
    let global = module_member_to_global(module, member);
    if (global != null) {
        call(global, pos_args, named, pos)
    } else {
        throw root.error.Error.at("Undefined function.", pos)
    }
}

/// Resolve a built-in module variable (`math.$pi`, etc.). dart-sass exposes
/// these only on `sass:math`; an unknown member is "Undefined variable.".
function module_var(module: string, name: string, pos: root.scanner.Pos) -> root.value.Value {
    let number = (value: float) -> root.value.Value {
        root.value.Value_Number { _0: root.value.Number.unitless(value) }
    };
    if (module == "math") {
        return match (name) {
            "pi" => number(root.std.F64_PI()),
            "e" => number(root.std.F64_E()),
            "epsilon" => number(root.std.F64_EPSILON()),
            "max-safe-integer" => number(9007199254740991.0),
            "min-safe-integer" => number(-9007199254740991.0),
            "max-number" => number(root.std.F64_MAX()),
            // The smallest positive (subnormal) double, matching dart-sass's
            // `$min-number` (`5e-324`), not the smallest *normal* value.
            "min-number" => number(root.std.f64_from_bits(1n)),
            _ => throw root.error.Error.at("Undefined variable.", pos),
        };
    }
    throw root.error.Error.at("Undefined variable.", pos)
}
