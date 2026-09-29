// Ported from sasso `src/builtins/meta.rs` (namespace `root.builtins.meta`).
//
// Meta / introspection built-ins (`type-of`, `unit`, `unitless`,
// `comparable`, `inspect`).
//
// `if()` is not handled here — the evaluator implements it lazily.
//
// Shared argument helpers live in the parent module:
// `super::{arg, require, num, as_color, channel, clamp01}`. Return
// `Some(Ok(..))`/`Some(Err(..))` for a name this family owns, or `None`
// to let the next family try.

/// The names the meta family owns by name (the single source of truth,
/// mirroring the `try_call` arms below — including `get-function`, which is
/// dispatched ahead of the `match` but is still owned by this family).
function NAMES() -> string[] {
    [
        "get-function",
        "type-of",
        "unit",
        "unitless",
        "comparable",
        "inspect",
        "feature-exists",
        "function-exists",
        "calc-name",
        "calc-args",
    ]
}

function try_call(
    name: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> (root.std.Ok<root.value.Value> | root.std.Err<root.error.Error>)? {
    // `get-function` validates arity/type here; a well-formed call needs a
    // function reference, which this value-only layer cannot construct, so
    // `fn_get_function` returns `None` to fall through to verbatim CSS.
    if (name == "get-function") {
        return fn_get_function(pos_args, named, pos);
    }
    // Fixed-arity members reject extra positional arguments before running.
    let max: int? = match (name) {
        "type-of" | "unit" | "unitless" | "inspect" | "feature-exists" | "calc-name" | "calc-args" => {
            1
        },
        "comparable" => 2,
        _ => null,
    };
    if (max != null) {
        root.builtins.check_arity(max, pos_args, named, pos) catch (e) {
            let err: root.error.Error => {
                return root.std.Err { error: err };
            }
        };
    }
    // PORT: `Some(match name { … })` — the arm's `Result` is held as an
    // `Ok`/`Err` value; `_ => return None` returns `null`.
    let result: root.std.Ok<root.value.Value> | root.std.Err<root.error.Error> = {
        root.std.Ok {
            value: match (name) {
                "type-of" => fn_type_of(pos_args, named, pos),
                "unit" => fn_unit(pos_args, named, pos),
                "unitless" => fn_unitless(pos_args, named, pos),
                "comparable" => fn_comparable(pos_args, named, pos),
                "inspect" => fn_inspect(pos_args, named, pos),
                "feature-exists" => fn_feature_exists(pos_args, named, pos),
                "function-exists" => fn_function_exists(pos_args, named, pos),
                "calc-name" => fn_calc_name(pos_args, named, pos),
                "calc-args" => fn_calc_args(pos_args, named, pos),
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

/// `meta.calc-name($calc)`: the calculation's function name as a quoted string
/// (`"calc"`, `"min"`, `"clamp"`, …).
function fn_calc_name(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let v = root.builtins.require(["calc"], pos_args, named, 0, pos);
    match (v) {
        root.value.Value_Calc { _0: let node } => {
            let name = match (node) {
                root.value.CalcNode_Func { name: let name } => name,
                _ => "calc",
            };
            root.value.Value_Str { _0: root.value.SassStr { text: name, quoted: true } }
        },
        let other => {
            throw root.error.Error.at(
                "$calc: " + other.to_css(false) + " is not a calculation.",
                pos,
            );
        },
    }
}

/// `meta.calc-args($calc)`: the calculation's arguments as a comma-separated
/// list. A `calc()` holds a single argument (its expression): a bare number
/// stays a number, a nested operation becomes an unquoted string, and any other
/// operand (a `var()`/interpolation result) is its unquoted string.
function fn_calc_args(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let v = root.builtins.require(["calc"], pos_args, named, 0, pos);
    match (v) {
        // A function calculation (`min`/`clamp`/…) exposes its own arguments; a
        // bare `calc()` has a single argument, its expression.
        root.value.Value_Calc { _0: root.value.CalcNode_Func { args: let args } } => {
            root.value.Value_List {
                _0: root.value.List.new(
                    args.map((a) -> root.value.Value {
                        calc_node_to_value(a)
                    }),
                    root.value.ListSep.Comma,
                    false,
                ),
            }
        },
        root.value.Value_Calc { _0: let node } => {
            root.value.Value_List {
                _0: root.value.List.new([calc_node_to_value(node)], root.value.ListSep.Comma, false),
            }
        },
        let other => {
            throw root.error.Error.at(
                "$calc: " + other.to_css(false) + " is not a calculation.",
                pos,
            );
        },
    }
}

/// Convert one calculation argument node to the Sass value `meta.calc-args`
/// returns for it: a number stays a number; a nested function calculation stays
/// a calculation; an operation or any opaque operand becomes an unquoted string.
function calc_node_to_value(node: root.value.CalcNode) -> root.value.Value {
    match (node) {
        root.value.CalcNode_Number { _0: let n } => {
            root.value.Value_Number { _0: root.value.Number { ...n } }
        },
        root.value.CalcNode_Str { _0: let s } => {
            root.value.Value_Str { _0: root.value.SassStr { text: s, quoted: false } }
        },
        root.value.CalcNode_Func {} => root.value.Value_Calc { _0: node },
        root.value.CalcNode_Op {} => {
            root.value.Value_Str {
                _0: root.value.SassStr { text: node.to_calc_css(false), quoted: false },
            }
        },
        _ => root.std.unreachable(),
    }
}

/// An unquoted string value.
function unquoted(text: string) -> root.value.Value {
    root.value.Value_Str { _0: root.value.SassStr { text: text, quoted: false } }
}

/// A quoted string value.
function quoted(text: string) -> root.value.Value {
    root.value.Value_Str { _0: root.value.SassStr { text: text, quoted: true } }
}

/// `type-of($value)`: the value's type as an unquoted string
/// (`number`, `string`, `color`, `list`, `bool`, `null`).
function fn_type_of(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let v = root.builtins.require(["value"], pos_args, named, 0, pos);
    unquoted(v.type_name())
}

/// `unit($number)`: the number's unit as a *quoted* string (`"px"`, `"%"`,
/// or `""` for a unitless number). Errors on a non-number, matching
/// dart-sass.
function fn_unit(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let v = root.builtins.require(["number"], pos_args, named, 0, pos);
    match (v) {
        root.value.Value_Number { _0: let n } => quoted(n.unit_string()),
        let other => {
            throw root.error.Error.at(
                "$number: " + other.to_css(false) + " is not a number.",
                pos,
            );
        },
    }
}

/// `unitless($number)`: `true` when the number carries no unit. Errors on a
/// non-number.
function fn_unitless(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let v = root.builtins.require(["number"], pos_args, named, 0, pos);
    match (v) {
        root.value.Value_Number { _0: let n } => root.value.Value_Bool { _0: n.is_unitless() },
        let other => {
            throw root.error.Error.at(
                "$number: " + other.to_css(false) + " is not a number.",
                pos,
            );
        },
    }
}

/// `comparable($number1, $number2)`: `true` when the two numbers' units are
/// compatible — either operand unitless, or the full unit lists convert.
function fn_comparable(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["number1", "number2"];
    let a = root.builtins.require(params, pos_args, named, 0, pos);
    let b = root.builtins.require(params, pos_args, named, 1, pos);
    let num_of = (v: root.value.Value, which: string) -> root.value.Number {
        match (v) {
            root.value.Value_Number { _0: let n } => n,
            let other => {
                throw root.error.Error.at(
                    "$" + which + ": " + other.to_css(false) + " is not a number.",
                    pos,
                );
            },
        }
    };
    let na = num_of(a, "number1");
    let nb = num_of(b, "number2");
    // dart `isComparableTo`: a unitless number is comparable to anything;
    // otherwise the FULL unit lists must convert (so `1px` vs the true
    // quotient `1px^-1` of `1/1px` is NOT comparable).
    let compatible = na.is_unitless()
        || nb.is_unitless()
        || root.value.unit_lists_factor(
            root.std.Tuple2 { _0: na.numer_units(), _1: na.denom_units() },
            root.std.Tuple2 { _0: nb.numer_units(), _1: nb.denom_units() },
        )
            != null;
    root.value.Value_Bool { _0: compatible }
}

/// `feature-exists($feature)`: `true` when `$feature` names a Sass language
/// feature this implementation supports. dart-sass recognizes a fixed set of
/// feature names (accepting both quoted and unquoted strings); any other name
/// is `false`, and a non-string argument is an error.
function fn_feature_exists(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let v = root.builtins.require(["feature"], pos_args, named, 0, pos);
    let name = match (v) {
        root.value.Value_Str { _0: let s } => s.text,
        let other => {
            throw root.error.Error.at(
                "$feature: " + other.to_css(false) + " is not a string.",
                pos,
            );
        },
    };
    // The canonical dart-sass feature set (all long-stable language features).
    let known = match (name) {
        "global-variable-shadowing"
            | "extend-selector-pseudoclass"
            | "units-level-3"
            | "at-error"
            | "custom-property" =>
        {
            true
        },
        _ => false,
    };
    root.value.Value_Bool { _0: known }
}

/// `function-exists($name, $module: null)`: whether a function with the given
/// name is available. dart-sass validates arity (1–2 args) and that `$name` is
/// a string, then checks the current scope. This value-only layer cannot see
/// user-defined functions, so it recognizes built-in functions via the
/// dispatcher's ownership probe and reports `false` otherwise — which matches
/// dart-sass for built-ins and for genuinely-absent names. (A `$module`
/// argument requires `@use`, which is unsupported, so it is accepted and
/// ignored.)
function fn_function_exists(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["name", "module"];
    root.builtins.check_arity(params.length(), pos_args, named, pos);
    let v = root.builtins.require(params, pos_args, named, 0, pos);
    let name = match (v) {
        root.value.Value_Str { _0: let s } => s.text,
        let other => {
            throw root.error.Error.at(
                "$name: " + other.to_css(false) + " is not a string.",
                pos,
            );
        },
    };
    root.value.Value_Bool { _0: root.builtins.is_builtin(name) }
}

/// `get-function($name, $css: false, $module: null)`: returns a reference to
/// the named function. This value-only layer has no function-reference value
/// and no view of user-defined functions, so it only enforces the validation
/// dart-sass performs *before* resolution — arity (1–3 args) and that `$name`
/// is a string — and otherwise declines (`None`), letting a well-formed call
/// fall through to verbatim CSS. Returning `Some(Err(..))` for the bad-arity /
/// bad-type cases converts those spec cases from a silent pass-through into the
/// error dart-sass raises.
function fn_get_function(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> (root.std.Ok<root.value.Value> | root.std.Err<root.error.Error>)? {
    let params = ["name", "css", "module"];
    root.builtins.check_arity(params.length(), pos_args, named, pos) catch (e) {
        let err: root.error.Error => {
            return root.std.Err { error: err };
        }
    };
    let v = root.builtins.arg(params, pos_args, named, 0);
    if (v == null) {
        return root.std.Err { error: root.error.Error.at("Missing argument $name.", pos) };
    }
    match (v) {
        root.value.Value_Str {} => null,
        let other => {
            root.std.Err {
                error: root.error.Error.at("$name: " + other.to_css(false) + " is not a string.", pos),
            }
        },
    }
}

/// `inspect($value)`: an unquoted string with the value's debug
/// representation, matching dart-sass's `inspect()` — quoted strings keep
/// their quotes, `null` becomes `null`, the empty list becomes `()`, and a
/// single-element comma list keeps its trailing comma `(x,)`.
function fn_inspect(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let v = root.builtins.require(["value"], pos_args, named, 0, pos);
    unquoted(inspect_value(v))
}

/// Serialize a value as dart-sass `inspect()` would. Bracketed lists are
/// wrapped in `[...]`; an unbracketed empty list is `()` and a single-element
/// comma list keeps its trailing comma `(x,)`. Maps render `(k: v, …)` with
/// nested keys/values inspected recursively.
function inspect_value(v: root.value.Value) -> string {
    match (v) {
        root.value.Value_Null {} => "null",
        root.value.Value_Str { _0: let s } => {
            if (s.quoted) {
                // dart `_visitQuotedString`: single quotes when the text has a
                // `"` and no `'`, and the quote and backslash escaped — a naive
                // `"{text}"` turns `a"b` into INVALID CSS.
                root.value.serialize_quoted(s.text)
            } else {
                // `_visitUnquotedString`, and so its private-use escape, runs
                // HERE: dart inspects with `serializeValue(inspect: true)`,
                // whose style is the default one, and hands back a string that
                // already carries `\e000` — long enough to change
                // `string.length`, and ASCII enough to leave a compressed
                // stylesheet without the BOM a raw character would earn it.
                root.value.serialize_unquoted(s.text, false)
            }
        },
        root.value.Value_List { _0: let l } => {
            let sep_str = match (l.sep) {
                root.value.ListSep.Comma => ", ",
                root.value.ListSep.Space | root.value.ListSep.Undecided => " ",
                root.value.ListSep.Slash => " / ",
            };
            let body = match (l.items.length()) {
                0 => {
                    // An unbracketed empty list is `()`; a bracketed one is `[]`.
                    return if (l.bracketed) {
                        "[]"
                    } else {
                        "()"
                    };
                },
                1 if l.sep == root.value.ListSep.Comma => {
                    `${inspect_element(l.items[0], l.sep)},`
                },
                1 if l.sep == root.value.ListSep.Slash => {
                    // A single-element slash list keeps a trailing `/` (no spaces),
                    // mirroring the comma list's trailing `,`.
                    `${inspect_element(l.items[0], l.sep)}/`
                },
                _ => {
                    root.std.join(
                        l.items.map((e) -> {
                            inspect_element(e, l.sep)
                        }),
                        sep_str,
                    )
                },
            };
            if (l.bracketed) {
                `[${body}]`
            } else if (
                l.items.length() == 1
                    && (l.sep == root.value.ListSep.Comma || l.sep == root.value.ListSep.Slash)
            ) {
                // An unbracketed single-element comma/slash list needs its own
                // parens: `(1,)` / `(1/)`.
                `(${body})`
            } else {
                body
            }
        },
        root.value.Value_Map { _0: let m } => {
            if (m.entries.length() == 0) {
                return "()";
            }
            // Map keys and values sit in a comma-separated context, so a
            // comma-list key/value is parenthesized (dart-sass).
            let inner = root.std.join(
                m.entries.map((e) -> {
                    `${inspect_map_element(e._0)}: ${inspect_map_element(e._1)}`
                }),
                ", ",
            );
            `(${inner})`
        },
        // A color inspects in dart's `inspect: true` serializer mode: hwb
        // keeps its own `hwb(...)` form, and out-of-gamut rgb skips the hsl
        // reroute (see `ModernColor::inspect_css`).
        root.value.Value_Color { _0: let c } => c.inspect_css(),
        // Numbers and booleans inspect exactly as they serialize.
        let other => other.to_css(false),
    }
}

/// Serialize a list element, adding surrounding parentheses when dart-sass
/// would: a multi-element *unbracketed* list nested in a comma parent needs
/// parens only when it is itself comma-separated; nested in a space parent, any
/// multi-element unbracketed list needs them. A bracketed list carries its own
/// `[...]`, and empty / single-element comma lists carry their own parens via
/// [`inspect_value`].
/// Serialize a map key or value, matching dart-sass's `_writeMapElement`: an
/// unbracketed comma-separated list is wrapped in parens regardless of length,
/// so an empty arglist becomes `(())`. `inspect_element` only wraps lists of
/// length >= 1, so the empty-comma case is handled here; everything else
/// defers to it (a comma parent, since map entries sit in a comma context).
function inspect_map_element(v: root.value.Value) -> string {
    if let root.value.Value_List { _0: let l } = v {
        if (l.items.length() == 0 && l.sep == root.value.ListSep.Comma && !l.bracketed) {
            return `(${inspect_value(v)})`;
        }
    }
    inspect_element(v, root.value.ListSep.Comma)
}

function inspect_element(v: root.value.Value, parent_sep: root.value.ListSep) -> string {
    if let root.value.Value_List { _0: let l } = v {
        // A 2+-element list, or a single-element comma list (`(1,)`, whose own
        // serialization already carries parens), is wrapped again when nested in
        // a list/map that would otherwise swallow its separator.
        let single_comma = l.items.length() == 1 && l.sep == root.value.ListSep.Comma;
        let candidate = !l.bracketed && (l.items.length() >= 2 || single_comma);
        if (candidate) {
            let needs_parens = match (parent_sep) {
                root.value.ListSep.Comma => l.sep == root.value.ListSep.Comma,
                // A single-element comma list already disambiguates itself in a
                // space context (`(1,) 2`), so it is NOT re-wrapped there; a
                // 2+-element list still is. (Undecided behaves like space.)
                root.value.ListSep.Space | root.value.ListSep.Undecided => !single_comma,
                root.value.ListSep.Slash => {
                    l.sep == root.value.ListSep.Comma || l.sep == root.value.ListSep.Slash
                },
            };
            if (needs_parens) {
                return `(${inspect_value(v)})`;
            }
        }
    }
    inspect_value(v)
}
