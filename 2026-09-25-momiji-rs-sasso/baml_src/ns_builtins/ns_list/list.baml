// Ported from sasso `src/builtins/list.rs` (namespace `root.builtins.list`).
//
// List built-in functions (`length`, `nth`, `set-nth`, `join`, `append`,
// `index`, `list-separator`).
//
// A non-list value behaves as a single-element list (length 1); the empty
// list `()` has length 0. Sass indexes lists 1-based, with negative indices
// counting back from the end. Shared argument helpers live in the parent
// module: `super::{arg, require, num, as_color, channel, clamp01}`. Return
// `Some(Ok(..))`/`Some(Err(..))` for a name this family owns, or `None` to
// let the next family try.

/// The names the list family owns by name (the single source of truth,
/// mirroring the `try_call` match arms below). `length`/`nth` are list-owned:
/// the map family only claims them when the first argument is a map, so they
/// belong here (and are absent from [`super::map::NAMES`]).
function NAMES() -> string[] {
    ["length", "nth", "set-nth", "join", "append", "index", "list-separator", "is-bracketed", "zip"]
}

function try_call(
    name: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> (root.std.Ok<root.value.Value> | root.std.Err<root.error.Error>)? {
    // PORT: `Some(match name { … })` — the arm's `Result` is held as an
    // `Ok`/`Err` value; `_ => return None` returns `null`.
    let result: root.std.Ok<root.value.Value> | root.std.Err<root.error.Error> = {
        root.std.Ok {
            value: match (name) {
                "length" => fn_length(pos_args, named, pos),
                "nth" => fn_nth(pos_args, named, pos),
                "set-nth" => fn_set_nth(pos_args, named, pos),
                "join" => fn_join(pos_args, named, pos),
                "append" => fn_append(pos_args, named, pos),
                "index" => fn_index(pos_args, named, pos),
                "list-separator" => fn_list_separator(pos_args, named, pos),
                "is-bracketed" => fn_is_bracketed(pos_args, named, pos),
                "zip" => fn_zip(pos_args, named),
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

/// Dispatch a `sass:list` member that has no global alias (`slash`). Returns
/// `None` for any other member so the caller can report it as undefined.
function call_module_member(
    member: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> (root.std.Ok<root.value.Value> | root.std.Err<root.error.Error>)? {
    // PORT: `Some(match member { … })` — the arm's `Result` is held as an
    // `Ok`/`Err` value; `_ => return None` returns `null`.
    let result: root.std.Ok<root.value.Value> | root.std.Err<root.error.Error> = {
        root.std.Ok {
            value: match (member) {
                "slash" => fn_slash(pos_args, named, pos),
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

/// `list.slash($elements...)`: a slash-separated list of the arguments
/// (e.g. `list.slash(1, 2, 3)` → `1 / 2 / 3`). dart-sass requires at least two
/// elements.
function fn_slash(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    if (named.length() != 0) {
        throw root.error.Error.at(
            "No arguments named ($" + named[0]._0 + ").",
            pos,
        );
    }
    if (pos_args.length() < 2) {
        throw root.error.Error.at("At least two elements are required.", pos);
    }
    root.value.Value_List {
        _0: root.value.List {
            items: root.std.clone_vec(pos_args),
            sep: root.value.ListSep.Slash,
            bracketed: false,
            keywords: null,
        },
    }
}

/// Borrow a value as a list of elements and its separator. A list yields its
/// own items and separator; a map yields its entries as `key value` space
/// lists (comma-separated); any other value (including `null`) is a
/// single-element list. dart-sass reports a lone non-list as space-separated.
function as_items(v: root.value.Value) -> root.std.Tuple2<root.value.Value[], root.value.ListSep> {
    match (v) {
        root.value.Value_List { _0: let l } => {
            root.std.Tuple2 { _0: root.std.clone_vec(l.items), _1: l.sep }
        },
        root.value.Value_Map { _0: let m } => {
            let items: root.value.Value[] = m.entries.map((e) -> root.value.Value {
                root.value.Value_List {
                    _0: root.value.List {
                        items: [e._0, e._1],
                        sep: root.value.ListSep.Space,
                        bracketed: false,
                        keywords: null,
                    },
                }
            });
            let sep: root.value.ListSep = root.value.ListSep.Comma;
            root.std.Tuple2 { _0: items, _1: sep }
        },
        let other => {
            let items: root.value.Value[] = [other];
            let sep: root.value.ListSep = root.value.ListSep.Space;
            root.std.Tuple2 { _0: items, _1: sep }
        },
    }
}

/// The element count of a value treated as a list.
function list_len(v: root.value.Value) -> int {
    match (v) {
        root.value.Value_List { _0: let l } => l.items.length(),
        _ => 1,
    }
}

function unitless(value: float) -> root.value.Value {
    root.value.Value_Number { _0: root.value.Number.unitless(value) }
}

/// Resolve a 1-based (possibly negative) Sass index against a list of `len`
/// elements into a 0-based offset, erroring exactly like dart-sass on a
/// non-integer, zero, or out-of-range index. `$n` may carry a unit, which is
/// ignored (matching dart-sass).
function resolve_index(
    params: string[],
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    i: int,
    len: int,
    pos: root.scanner.Pos,
) -> int {
    let v = root.builtins.require(params, pos_args, named, i, pos);
    let pname = params.at(i) ?? "";
    let raw = match (v) {
        root.value.Value_Number { _0: let n } => n.value,
        let other => {
            throw root.error.Error.at(
                `\$${pname}: ${other.to_css(false)} is not a number.`,
                pos,
            );
        },
    };
    if (root.std.fne(root.std.fract(raw), 0.0)) {
        throw root.error.Error.at(
            `\$${pname}: ${root.value.fmt_num(raw, false)} is not an int.`,
            pos,
        );
    }
    let index = root.std.f64_to_int(raw);
    if (index == 0) {
        throw root.error.Error.at(`\$${pname}: List index may not be 0.`, pos);
    }
    let len_i = len;
    if (index.abs() > len_i) {
        let plural = if (len == 1) {
            ""
        } else {
            "s"
        };
        throw root.error.Error.at(
            `\$${pname}: Invalid index ${root.value.fmt_num(raw, false)} for a list with ${len} element${plural}.`,
            pos,
        );
    }
    // Map 1-based / negative index to a 0-based offset.
    let zero_based = if (index > 0) {
        index - 1
    } else {
        len_i + index
    };
    zero_based
}

/// Parse a `$separator` argument into a concrete `ListSep`, or `None` for the
/// keyword `auto`. Accepts `space`/`comma`/`slash`.
function parse_separator(v: root.value.Value, pos: root.scanner.Pos) -> root.value.ListSep? {
    if let root.value.Value_Str { _0: let s } = v {
        match (s.text) {
            "auto" => {
                return null;
            },
            "comma" => {
                return root.value.ListSep.Comma;
            },
            "space" => {
                return root.value.ListSep.Space;
            },
            "slash" => {
                return root.value.ListSep.Slash;
            },
            _ => {},
        };
    }
    throw root.error.Error.at(
        "$separator: Must be \"space\", \"comma\", \"slash\", or \"auto\".",
        pos,
    );
}

/// `length($list)`: the unitless element count.
function fn_length(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    validate_args(["list"], pos_args, named, pos);
    let v = root.builtins.require(["list"], pos_args, named, 0, pos);
    unitless(list_len(v) * 1.0)
}

/// `nth($list, $n)`: the element at the 1-based (negative-from-end) index.
function fn_nth(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["list", "n"];
    validate_args(params, pos_args, named, pos);
    let list = root.builtins.require(params, pos_args, named, 0, pos);
    let items = as_items(list)._0;
    let idx = resolve_index(params, pos_args, named, 1, items.length(), pos);
    let item = items.at(idx);
    if (item == null) {
        throw root.error.Error.at("Internal index error.", pos);
    }
    item
}

/// `set-nth($list, $n, $value)`: a copy of the list with one element replaced,
/// preserving the original separator.
function fn_set_nth(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["list", "n", "value"];
    validate_args(params, pos_args, named, pos);
    let list = root.builtins.require(params, pos_args, named, 0, pos);
    let as_items_r = as_items(list);
    let items = as_items_r._0;
    let sep = as_items_r._1;
    let idx = resolve_index(params, pos_args, named, 1, items.length(), pos);
    let value = root.builtins.require(params, pos_args, named, 2, pos);
    // PORT: `if let Some(slot) = items.get_mut(idx)` → a bounds check.
    if (idx < items.length()) {
        items[idx] = value;
    }
    // `set-nth` preserves the source list's bracketing (dart-sass).
    let bracketed = match (list) {
        root.value.Value_List { _0: let l } if l.bracketed => true,
        _ => false,
    };
    root.value.Value_List { _0: root.value.List.new(items, sep, bracketed) }
}

/// The "settled" separator of a value, or `None` when undecided. A non-empty
/// `List` value carries its own separator; a bare value defaults to space.
/// An empty list is normally undecided (dart-sass defaults it to space), but an
/// empty *comma* list is one that was deliberately built comma-separated
/// (e.g. the result of `map.keys(())`/`map.values(())`), so its separator is
/// settled to comma — a literal empty `()` is stored space-separated and stays
/// undecided.
function settled_sep(v: root.value.Value) -> root.value.ListSep? {
    match (v) {
        // A list with a real (non-undecided) separator is settled, even when
        // empty or single-element — the separator is an explicit choice that
        // `list.join`/`list.append` must honour.
        root.value.Value_List { _0: let l } if l.sep != root.value.ListSep.Undecided => l.sep,
        // A non-empty map behaves as a comma-separated list of its entries.
        root.value.Value_Map { _0: let m } if m.entries.length() != 0 => root.value.ListSep.Comma,
        // An undecided list, or a bare value, has no settled separator.
        _ => null,
    }
}

/// `join($list1, $list2, $separator: auto, $bracketed: auto)`: concatenated
/// list. With `auto`, the separator is list1's settled separator (or list2's
/// when list1 has none), defaulting to space when neither is settled. The
/// `$bracketed` flag defaults to list1's bracketing (`auto`), or is forced
/// true/false by a truthy/falsey argument.
function fn_join(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["list1", "list2", "separator", "bracketed"];
    validate_args(params, pos_args, named, pos);
    let list1 = root.builtins.require(params, pos_args, named, 0, pos);
    let list2 = root.builtins.require(params, pos_args, named, 1, pos);
    let items1 = as_items(list1)._0;
    let items2 = as_items(list2)._0;

    let sep_arg = root.builtins.arg(params, pos_args, named, 2);
    let sep: root.value.ListSep = if (sep_arg != null) {
        let parsed = parse_separator(sep_arg, pos);
        if (parsed != null) {
            parsed
        } else {
            join_auto_separator(list1, list2)
        }
    } else {
        join_auto_separator(list1, list2)
    };

    // `$bracketed`: `auto` (default) inherits list1's brackets; any other value
    // is truthy/falsey.
    let bracketed = match (root.builtins.arg(params, pos_args, named, 3)) {
        null => match (list1) {
            root.value.Value_List { _0: let l } if l.bracketed => true,
            _ => false,
        },
        root.value.Value_Str { _0: let s } if !s.quoted && s.text == "auto" => {
            match (list1) {
                root.value.Value_List { _0: let l } if l.bracketed => true,
                _ => false,
            }
        },
        let v: root.value.Value => v.is_truthy(),
    };

    let items = items1;
    root.std.extend(items, items2);
    root.value.Value_List { _0: root.value.List.new(items, sep, bracketed) }
}

/// The dart-sass "Only N argument(s) allowed, but M were passed." error.
/// `named` decides the "positional" wording, as in [`super::check_arity`].
function too_many(
    passed: int,
    max: int,
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.error.Error {
    let kind = if (named.length() == 0) {
        ""
    } else {
        "positional "
    };
    let plural = if (max == 1) {
        ""
    } else {
        "s"
    };
    let verb = if (passed == 1) {
        "was"
    } else {
        "were"
    };
    root.error.Error.at(
        `Only ${max} ${kind}argument${plural} allowed, but ${passed} ${verb} passed.`,
        pos,
    )
}

/// Validate a fixed-arity (non-variadic) builtin's argument list against its
/// declared `params`, in dart's own order: a POSITIONAL overflow is the
/// "Only N argument(s) allowed…" error (only positional arguments count toward
/// it — see [`super::check_arity`]), and only then is a named argument whose
/// name is not a declared parameter "No parameter named $X.".
function validate_args(
    params: string[],
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> void {
    // dart's order (`ArgumentDeclaration.verify`): the positional overflow is
    // reported before an unrecognized name.
    if (pos_args.length() > params.length()) {
        throw too_many(pos_args.length(), params.length(), named, pos);
    }
    let unknown = named.find((e) -> {
        !params.includes(e._0)
    });
    if (unknown != null) {
        let n = unknown._0;
        throw root.error.Error.at(`No parameter named \$${n}.`, pos);
    }
}

/// `join`'s `auto` rule: list1's settled separator, else list2's, else space.
/// `join` always yields a *decided* separator (dart-sass), so even
/// `join((), ())` is space-separated, not undecided.
function join_auto_separator(
    list1: root.value.Value,
    list2: root.value.Value,
) -> root.value.ListSep {
    settled_sep(list1) ?? settled_sep(list2) ?? root.value.ListSep.Space
}

/// `append($list, $val, $separator: auto)`: the list with `$val` appended.
/// With `auto`, the existing list's settled separator is kept, defaulting to
/// space for a bare value or empty list.
function fn_append(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["list", "val", "separator"];
    validate_args(params, pos_args, named, pos);
    let list = root.builtins.require(params, pos_args, named, 0, pos);
    let val = root.builtins.require(params, pos_args, named, 1, pos);
    let items = as_items(list)._0;

    let sep_arg = root.builtins.arg(params, pos_args, named, 2);
    let sep: root.value.ListSep = if (sep_arg != null) {
        let parsed = parse_separator(sep_arg, pos);
        if (parsed != null) {
            parsed
        } else {
            settled_sep(list) ?? root.value.ListSep.Space
        }
    } else {
        settled_sep(list) ?? root.value.ListSep.Space
    };
    // `append` keeps the source list's bracketing (dart-sass).
    let bracketed = match (list) {
        root.value.Value_List { _0: let l } if l.bracketed => true,
        _ => false,
    };

    items.push(val);
    root.value.Value_List { _0: root.value.List.new(items, sep, bracketed) }
}

/// `index($list, $value)`: the 1-based position of the first element equal to
/// `$value` (by Sass `==`), or `null` when absent.
function fn_index(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["list", "value"];
    validate_args(params, pos_args, named, pos);
    let list = root.builtins.require(params, pos_args, named, 0, pos);
    let value = root.builtins.require(params, pos_args, named, 1, pos);
    let items = as_items(list)._0;
    let i = items.find_index((item) -> {
        item.sass_eq(value)
    });
    if (i != null) {
        unitless((i + 1) * 1.0)
    } else {
        root.value.Value_Null {  }
    }
}

/// `list-separator($list)`: the unquoted keyword `comma` or `space`. An empty
/// list or a bare value is "undecided" and reports `space`.
function fn_list_separator(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    validate_args(["list"], pos_args, named, pos);
    let v = root.builtins.require(["list"], pos_args, named, 0, pos);
    // A bare value or empty list is "undecided", which dart-sass reports as
    // space; otherwise the list's own separator is authoritative.
    let sep: root.value.ListSep = settled_sep(v) ?? root.value.ListSep.Space;
    let text = match (sep) {
        root.value.ListSep.Comma => "comma",
        root.value.ListSep.Space | root.value.ListSep.Undecided => "space",
        root.value.ListSep.Slash => "slash",
    };
    root.value.Value_Str { _0: root.value.SassStr { text: text, quoted: false } }
}

/// `is-bracketed($list)`: `true` when the list was written with square
/// brackets. A bare value or an empty/non-bracketed list reports `false`.
function fn_is_bracketed(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    validate_args(["list"], pos_args, named, pos);
    let v = root.builtins.require(["list"], pos_args, named, 0, pos);
    let bracketed = match (v) {
        root.value.Value_List { _0: let l } if l.bracketed => true,
        _ => false,
    };
    root.value.Value_Bool { _0: bracketed }
}

/// `zip($lists...)`: combine corresponding elements of each list into a
/// comma-separated list of space-separated sublists, truncating to the
/// shortest input. With a single element per row the row is that bare value;
/// when any input is empty (length 0) the result is the empty list.
function fn_zip(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
) -> root.value.Value {
    // `zip` takes only the variadic positional `$lists`; any trailing named
    // arguments are treated as further lists, matching dart-sass's rest list.
    let lists: root.value.Value[][] = pos_args
        .concat(
            named.map((e) -> {
                e._1
            }),
        )
        .map((v) -> {
            as_items(v)._0
        });
    // PORT: `.map(len).min().unwrap_or(0)` → a fold seeded with the first length.
    let lens = lists.map((l) -> {
        l.length()
    });
    let rows = if (lens.length() == 0) {
        0
    } else {
        lens.reduce(
            (a, b) -> {
                root.std.imin(a, b)
            },
            lens[0],
        )
    };
    let out: root.value.Value[] = [];
    for (let i in baml.iter.Range.new(0, rows)) {
        let row: root.value.Value[] = lists.map((l) -> {
            l[i]
        });
        out.push(
            root.value.Value_List {
                _0: root.value.List {
                    items: row,
                    sep: root.value.ListSep.Space,
                    bracketed: false,
                    keywords: null,
                },
            },
        );
    }
    root.value.Value_List {
        _0: root.value.List {
            items: out,
            sep: root.value.ListSep.Comma,
            bracketed: false,
            keywords: null,
        },
    }
}
