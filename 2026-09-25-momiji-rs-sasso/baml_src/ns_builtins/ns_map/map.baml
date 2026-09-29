// Ported from sasso `src/builtins/map.rs` (namespace `root.builtins.map`).
//
// Map built-in functions (`map-get`, `map-keys`, `map-values`,
// `map-has-key`, `map-merge`, `map-remove`) plus the map-aware overloads of
// `length`/`nth`.
//
// Sass maps are ordered key/value collections; keys compare by Sass `==`.
// This family is registered ahead of the list family so that `length`/`nth`
// on a map are handled here, while the same names on a list fall through to
// the list family (this `try_call` returns `None` for them unless the first
// argument is actually a map). Shared argument helpers live in the parent
// module: `super::{arg, require, num}`.

/// The names the map family owns *unconditionally* by name (the single source
/// of truth, mirroring the `map-*` match arms below). `length`/`nth` are
/// deliberately absent: they are owned by the list family and only claimed here
/// when the first argument is a map (a runtime condition that never removes
/// them from the builtin set), so they live in [`super::list::NAMES`].
function NAMES() -> string[] {
    ["map-get", "map-keys", "map-values", "map-has-key", "map-merge", "map-remove"]
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
                "map-get" => fn_map_get(pos_args, named, pos),
                "map-keys" => fn_map_keys(pos_args, named, pos),
                "map-values" => fn_map_values(pos_args, named, pos),
                "map-has-key" => fn_map_has_key(pos_args, named, pos),
                "map-merge" => fn_map_merge(pos_args, named, pos),
                "map-remove" => fn_map_remove(pos_args, named, pos),
                // `length`/`nth` are owned by the list family; this family only claims
                // them when the first argument is a map (so list calls fall through).
                "length" if first_is_map(pos_args, named) => fn_length(pos_args, named, pos),
                "nth" if first_is_map(pos_args, named) => fn_nth(pos_args, named, pos),
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

/// Dispatch a `sass:map` member that has no global alias (`set`, `deep-merge`,
/// `deep-remove`). Returns `None` for any other member so the caller can report
/// it as undefined.
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
                "set" => fn_map_set(pos_args, named, pos),
                "deep-merge" => fn_map_deep_merge(pos_args, named, pos),
                "deep-remove" => fn_map_deep_remove(pos_args, named, pos),
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

/// Whether the first argument (positional or by the conventional first
/// parameter name) is a map. Used to decide whether `length`/`nth` belong to
/// this family or fall through to the list family.
function first_is_map(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
) -> bool {
    let v = pos_args.at(0);
    if (v != null) {
        return v is root.value.Value_Map;
    }
    named.some((e) -> {
        (e._0 == "list" || e._0 == "map") && e._1 is root.value.Value_Map
    })
}

/// Coerce a value into map entries. A map yields its entries; the empty list
/// `()` is the empty map; any other value is not a map (an error).
function as_map(
    v: root.value.Value,
    fname: string,
    pos: root.scanner.Pos,
) -> root.std.Tuple2<root.value.Value, root.value.Value>[] {
    match (v) {
        root.value.Value_Map { _0: let m } => root.std.clone_vec(m.entries),
        // The empty list doubles as the empty map.
        root.value.Value_List { _0: let l } if l.items.length() == 0 => {
            let empty: root.std.Tuple2<root.value.Value, root.value.Value>[] = [];
            empty
        },
        let other => {
            throw root.error.Error.at(
                "$map: " + other.to_css(false) + " is not a map for `" + fname + "`.",
                pos,
            );
        },
    }
}

function unitless(value: float) -> root.value.Value {
    root.value.Value_Number { _0: root.value.Number.unitless(value) }
}

/// A comma list of the given items. dart-sass `map-keys`/`map-values` always
/// return a comma-separated list, even when empty (so `list.separator()` of an
/// empty result reports `comma`).
function comma_list(items: root.value.Value[]) -> root.value.Value {
    root.value.Value_List {
        _0: root.value.List {
            items: items,
            sep: root.value.ListSep.Comma,
            bracketed: false,
            keywords: null,
        },
    }
}

/// Collect the `($key, $keys...)` arguments of a nested map accessor. The first
/// key is `$key` (positional or named), the rest is the `$keys...` splat (all
/// further positional arguments). dart-sass requires at least the one `$key`.
function key_path(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value[] {
    let keys: root.value.Value[] = [];
    let first = pos_args.at(1);
    if (first != null) {
        keys.push(first);
    } else {
        let found = named.find((e) -> {
            e._0 == "key"
        });
        if (found != null) {
            keys.push(found._1);
        }
    }
    if (keys.length() == 0) {
        throw root.error.Error.at("Missing argument $key.", pos);
    }
    root.std.extend(keys, pos_args.slice(2, pos_args.length()));
    keys
}

/// `map-get($map, $key, $keys...)`: the value at the nested key path, or `null`
/// when any key along the path is absent (or an intermediate value is not a map).
function fn_map_get(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let map_v = root.builtins.require(["map"], pos_args, named, 0, pos);
    let entries = as_map(map_v, "map-get", pos);
    let keys = key_path(pos_args, named, pos);
    // PORT: `.iter().enumerate()` → an index counter.
    let i = 0;
    for (let key in keys) {
        let found_e = entries.find((e) -> {
            e._0.sass_eq(key)
        });
        let found: root.value.Value? = if (found_e != null) {
            found_e._1
        } else {
            null
        };
        if (found != null) {
            let v = found;
            if (i + 1 == keys.length()) {
                return v;
            }
            // Descend; a non-map intermediate value means "not found".
            match (v) {
                root.value.Value_Map { _0: let m } => {
                    entries = root.std.clone_vec(m.entries);
                },
                root.value.Value_List { _0: let l } if l.items.length() == 0 => {
                    entries = [];
                },
                _ => {
                    return root.value.Value_Null {  };
                },
            };
        } else {
            return root.value.Value_Null {  };
        }
        i += 1;
    }
    root.value.Value_Null {  }
}

/// Reject more positional arguments than a fixed-arity function accepts
/// (dart-sass "Only N argument(s) allowed, but M were passed.").
function check_arity(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    max: int,
    pos: root.scanner.Pos,
) -> void {
    root.builtins.check_arity(max, pos_args, named, pos)
}

/// `map-keys($map)`: a comma list of the map's keys in order.
function fn_map_keys(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    check_arity(pos_args, named, 1, pos);
    let map_v = root.builtins.require(["map"], pos_args, named, 0, pos);
    let entries = as_map(map_v, "map-keys", pos);
    comma_list(
        entries.map((e) -> {
            e._0
        }),
    )
}

/// `map-values($map)`: a comma list of the map's values in order.
function fn_map_values(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    check_arity(pos_args, named, 1, pos);
    let map_v = root.builtins.require(["map"], pos_args, named, 0, pos);
    let entries = as_map(map_v, "map-values", pos);
    comma_list(
        entries.map((e) -> {
            e._1
        }),
    )
}

/// `map-has-key($map, $key, $keys...)`: whether the map contains the nested key
/// path.
function fn_map_has_key(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let map_v = root.builtins.require(["map"], pos_args, named, 0, pos);
    let entries = as_map(map_v, "map-has-key", pos);
    let keys = key_path(pos_args, named, pos);
    // PORT: `.iter().enumerate()` → an index counter.
    let i = 0;
    for (let key in keys) {
        let found_e = entries.find((e) -> {
            e._0.sass_eq(key)
        });
        let found: root.value.Value? = if (found_e != null) {
            found_e._1
        } else {
            null
        };
        if (found != null) {
            let v = found;
            if (i + 1 == keys.length()) {
                return root.value.Value_Bool { _0: true };
            }
            match (v) {
                root.value.Value_Map { _0: let m } => {
                    entries = root.std.clone_vec(m.entries);
                },
                root.value.Value_List { _0: let l } if l.items.length() == 0 => {
                    entries = [];
                },
                _ => {
                    return root.value.Value_Bool { _0: false };
                },
            };
        } else {
            return root.value.Value_Bool { _0: false };
        }
        i += 1;
    }
    root.value.Value_Bool { _0: false }
}

/// Merge `b`'s entries into `a` (shallow): `a` keeps its order, shared keys take
/// `b`'s value, and `b`'s new keys append in order.
function shallow_merge(
    a: root.std.Tuple2<root.value.Value, root.value.Value>[],
    b: root.std.Tuple2<root.value.Value, root.value.Value>[],
) -> root.value.Map {
    let map = root.value.Map.new(a);
    for (let e in b) {
        map.insert(e._0, e._1);
    }
    map
}

/// Borrow a value's map entries when it is a map (or the empty list, which
/// doubles as the empty map), else `None`.
function entries_of(v: root.value.Value) -> root.std.Tuple2<root.value.Value, root.value.Value>[]? {
    match (v) {
        root.value.Value_Map { _0: let m } => root.std.clone_vec(m.entries),
        root.value.Value_List { _0: let l } if l.items.length() == 0 => {
            let empty: root.std.Tuple2<root.value.Value, root.value.Value>[] = [];
            empty
        },
        _ => null,
    }
}

/// Recursively merge `b` into `a`: a value that is a map in *both* operands is
/// merged in turn; otherwise `b`'s value wins (dart-sass `deepMergeImpl`). The
/// empty list `()` counts as the empty map on either side.
function deep_merge(
    a: root.std.Tuple2<root.value.Value, root.value.Value>[],
    b: root.std.Tuple2<root.value.Value, root.value.Value>[],
) -> root.value.Map {
    let map = root.value.Map.new(a);
    for (let e in b) {
        let k = e._0;
        let v = e._1;
        // PORT: `match (x, y) { (Some(existing), Some(incoming)) => …, _ => v }`
        // → nested `if`s.
        let existing_v = map.get(k);
        let existing = if (existing_v != null) {
            entries_of(existing_v)
        } else {
            null
        };
        let incoming = entries_of(v);
        let merged: root.value.Value = if (existing != null) {
            if (incoming != null) {
                root.value.Value_Map { _0: deep_merge(existing, incoming) }
            } else {
                v
            }
        } else {
            v
        };
        map.insert(k, merged);
    }
    map
}

/// Navigate `entries` along `keys`, build maps for missing/non-map nodes, apply
/// `transform` to the value at the leaf, and rebuild the map spine. With an
/// empty `keys` the transform applies to the whole map directly.
function modify_map(
    entries: root.std.Tuple2<root.value.Value, root.value.Value>[],
    keys: root.value.Value[],
    transform: (root.value.Value?) -> root.value.Value throws unknown,
) -> root.std.Tuple2<root.value.Value, root.value.Value>[] {
    match (keys) {
        [] => {
            // No keys: transform receives the whole map and replaces it.
            match (transform(root.value.Value_Map { _0: root.value.Map.new(entries) })) {
                root.value.Value_Map { _0: let m } => root.std.clone_vec(m.entries),
                // A non-map result at the root degrades to an empty map spine;
                // callers always pass at least the map itself for this case.
                _ => {
                    let empty: root.std.Tuple2<root.value.Value, root.value.Value>[] = [];
                    empty
                },
            }
        },
        [let key, ..let rest] => {
            let map = root.value.Map.new(entries);
            let child = map.get(key);
            let new_child: root.value.Value = if (rest.length() == 0) {
                transform(child)
            } else {
                let child_entries: root.std.Tuple2<root.value.Value, root.value.Value>[] = match (child) {
                    root.value.Value_Map { _0: let m } => root.std.clone_vec(m.entries),
                    root.value.Value_List { _0: let l } if l.items.length() == 0 => [],
                    _ => [],
                };
                root.value.Value_Map {
                    _0: root.value.Map.new(modify_map(child_entries, rest, transform)),
                }
            };
            map.insert(key, new_child);
            root.std.clone_vec(map.entries)
        },
    }
}

/// `map-merge($map1, $map2)` or the nested `map-merge($map1, $keys..., $map2)`:
/// merge `$map2` into the (possibly nested) submap of `$map1` at the key path.
function fn_map_merge(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    merge_impl(pos_args, named, pos, false)
}

/// `map-deep-merge($map1, $map2)`: like `map-merge` but recursive.
function fn_map_deep_merge(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    merge_impl(pos_args, named, pos, true)
}

/// Shared body for `map.merge` / `map.deep-merge`. With named `$map1`/`$map2`
/// the call is the simple two-map form; otherwise the first positional argument
/// is `$map1`, the last is `$map2`, and the keys in between form the nested path.
function merge_impl(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
    deep: bool,
) -> root.value.Value {
    let merge = (
        a: root.std.Tuple2<root.value.Value, root.value.Value>[],
        b: root.std.Tuple2<root.value.Value, root.value.Value>[],
    ) -> root.value.Map {
        if (deep) {
            deep_merge(a, b)
        } else {
            shallow_merge(a, b)
        }
    };
    // Resolve `$map1` (positional 0 or named) and the path/`$map2`.
    let map1_v = root.builtins.require(["map1"], pos_args, named, 0, pos);
    let map1 = as_map_named(map1_v, "map1", pos);
    if (pos_args.length() <= 1) {
        // Two-map form via named `$map2`.
        let found = named.find((e) -> {
            e._0 == "map2"
        });
        if (found == null) {
            throw root.error.Error.at("Missing argument $map2.", pos);
        }
        let map2_v = found._1;
        let map2 = as_map_named(map2_v, "map2", pos);
        return root.value.Value_Map { _0: merge(map1, map2) };
    }
    // Positional form: last arg is `$map2`, middle args are the key path.
    let map2_v = pos_args[pos_args.length() - 1];
    let map2 = as_map_named(map2_v, "map2", pos);
    let keys: root.value.Value[] = pos_args.slice(1, pos_args.length() - 1);
    if (keys.length() == 0) {
        return root.value.Value_Map { _0: merge(map1, map2) };
    }
    let transform = (child: root.value.Value?) -> root.value.Value {
        let child_entries: root.std.Tuple2<root.value.Value, root.value.Value>[] = match (child) {
            root.value.Value_Map { _0: let m } => root.std.clone_vec(m.entries),
            root.value.Value_List { _0: let l } if l.items.length() == 0 => [],
            _ => [],
        };
        root.value.Value_Map { _0: merge(child_entries, root.std.clone_vec(map2)) }
    };
    root.value.Value_Map { _0: root.value.Map.new(modify_map(map1, keys, transform)) }
}

/// `map-set($map, $key, $keys..., $value)`: set the value at the nested key
/// path, creating maps along the way. Requires the map, at least one key, and a
/// value (the last argument).
function fn_map_set(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let map_v = root.builtins.require(["map"], pos_args, named, 0, pos);
    let entries = as_map_named(map_v, "map", pos);
    // Named two-arg form `map.set($map, $key, $value)` via $key/$value.
    let named_key_e = named.find((e) -> {
        e._0 == "key"
    });
    let named_key: root.value.Value? = if (named_key_e != null) {
        named_key_e._1
    } else {
        null
    };
    let named_value_e = named.find((e) -> {
        e._0 == "value"
    });
    let named_value: root.value.Value? = if (named_value_e != null) {
        named_value_e._1
    } else {
        null
    };
    // PORT: `match (named_key, named_value) { (Some(k), Some(v)) => …, _ => … }`
    // → nested `if`s assigning `keys`/`value`.
    let keys: root.value.Value[] = [];
    let value: root.value.Value = root.value.Value_Null {  };
    let both = false;
    if (named_key != null) {
        if (named_value != null) {
            keys = [named_key];
            value = named_value;
            both = true;
        }
    }
    if (!both) {
        // Positional: $map, then keys..., then $value (the last positional).
        if (pos_args.length() < 3) {
            throw root.error.Error.at("Expected $args to contain a key.", pos);
        }
        value = pos_args[pos_args.length() - 1];
        keys = pos_args.slice(1, pos_args.length() - 1);
    }
    let transform = (_old: root.value.Value?) -> root.value.Value {
        value
    };
    root.value.Value_Map { _0: root.value.Map.new(modify_map(entries, keys, transform)) }
}

/// `map-remove($map, $keys...)`: drop every entry whose key matches one of the
/// `$keys`. The `$keys` rest is positional; a single key may also be passed as
/// the named `$key` (but not mixed with positional keys).
function fn_map_remove(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let map_v = root.builtins.require(["map"], pos_args, named, 0, pos);
    let entries = as_map_named(map_v, "map", pos);
    // Every argument after the map is a positional key to remove.
    let keys: root.value.Value[] = pos_args.slice(1, pos_args.length());
    // A named `$key` provides a single key, but mixing it with positional rest
    // keys is the same argument supplied twice (dart-sass errors).
    let found = named.find((e) -> {
        e._0 == "key"
    });
    if (found != null) {
        if (keys.length() != 0) {
            throw root.error.Error.at(
                "Argument $keys was passed both by position and by name.",
                pos,
            );
        }
        keys.push(found._1);
    }
    root.std.retain(entries, (e) -> {
        !keys.some((rk) -> {
            rk.sass_eq(e._0)
        })
    });
    root.value.Value_Map { _0: root.value.Map.new(entries) }
}

/// `map-deep-remove($map, $key, $keys...)`: remove the entry at the nested key
/// path. Needs at least one key (dart-sass).
function fn_map_deep_remove(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let map_v = root.builtins.require(["map"], pos_args, named, 0, pos);
    let entries = as_map_named(map_v, "map", pos);
    let keys = key_path(pos_args, named, pos);
    // The last key is removed; the keys before it locate the parent submap.
    // PORT: `keys.split_last()` → a length check and two slices.
    if (keys.length() == 0) {
        return root.value.Value_Map { _0: root.value.Map.new(entries) };
    }
    let last = keys[keys.length() - 1];
    let parents = keys.slice(0, keys.length() - 1);
    root.value.Value_Map { _0: root.value.Map.new(deep_remove(entries, parents, last)) }
}

/// Navigate `entries` along `parents`; at the located submap, drop `last`. A
/// missing intermediate map leaves the structure unchanged.
function deep_remove(
    entries: root.std.Tuple2<root.value.Value, root.value.Value>[],
    parents: root.value.Value[],
    last: root.value.Value,
) -> root.std.Tuple2<root.value.Value, root.value.Value>[] {
    match (parents) {
        [] => {
            let entries = entries;
            root.std.retain(entries, (e) -> {
                !e._0.sass_eq(last)
            });
            entries
        },
        [let key, ..let rest] => {
            let map = root.value.Map.new(entries);
            if let root.value.Value_Map { _0: let child } = map.get(key) {
                let new_child = deep_remove(root.std.clone_vec(child.entries), rest, last);
                map.insert(key, root.value.Value_Map { _0: root.value.Map.new(new_child) });
            }
            root.std.clone_vec(map.entries)
        },
    }
}

/// Coerce a value into map entries with a parameter-named error message
/// (`$map1: 1 is not a map.`) matching dart-sass.
function as_map_named(
    v: root.value.Value,
    param: string,
    pos: root.scanner.Pos,
) -> root.std.Tuple2<root.value.Value, root.value.Value>[] {
    match (v) {
        root.value.Value_Map { _0: let m } => root.std.clone_vec(m.entries),
        root.value.Value_List { _0: let l } if l.items.length() == 0 => {
            let empty: root.std.Tuple2<root.value.Value, root.value.Value>[] = [];
            empty
        },
        let other => {
            throw root.error.Error.at(
                "$" + param + ": " + other.to_css(false) + " is not a map.",
                pos,
            );
        },
    }
}

/// `length($map)`: the number of entries.
function fn_length(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let map_v = root.builtins.require(["map"], pos_args, named, 0, pos);
    let entries = as_map(map_v, "length", pos);
    unitless(entries.length() * 1.0)
}

/// `nth($map, $n)`: the 1-based (negative-from-end) entry as a `key value`
/// space list.
function fn_nth(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["list", "n"];
    let map_v = root.builtins.require(params, pos_args, named, 0, pos);
    let entries = as_map(map_v, "nth", pos);
    let n = root.builtins.require(params, pos_args, named, 1, pos);
    let raw = root.builtins.num(n, pos);
    if (root.std.fne(root.std.fract(raw), 0.0)) {
        throw root.error.Error.at(
            "$n: " + root.value.fmt_num(raw, false) + " is not an int.",
            pos,
        );
    }
    let len = entries.length();
    let index = root.std.f64_to_int(raw);
    if (index == 0) {
        throw root.error.Error.at("$n: List index may not be 0.", pos);
    }
    if (index.abs() > len) {
        let plural = if (len == 1) {
            ""
        } else {
            "s"
        };
        throw root.error.Error.at(
            `\$n: Invalid index ${root.value.fmt_num(raw, false)} for a list with ${len} element${plural}.`,
            pos,
        );
    }
    let zero_based = if (index > 0) {
        index - 1
    } else {
        len + index
    };
    let kv = entries[zero_based];
    let k = kv._0;
    let v = kv._1;
    root.value.Value_List {
        _0: root.value.List {
            items: [k, v],
            sep: root.value.ListSep.Space,
            bracketed: false,
            keywords: null,
        },
    }
}
