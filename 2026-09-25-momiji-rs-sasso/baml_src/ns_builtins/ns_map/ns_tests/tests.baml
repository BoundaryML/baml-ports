// Ported from sasso `src/builtins/map.rs` `#[cfg(test)] mod tests`
// (namespace `root.builtins.map.tests`; `use super::*` →
// `root.builtins.map.*`, plus the parent's imports `root.value.*`,
// `root.scanner.Pos`; `use crate::value::SassStr` → `root.value.SassStr`).

function pos() -> root.scanner.Pos {
    root.scanner.Pos { line: 1, col: 1 }
}

function s(text: string) -> root.value.Value {
    root.value.Value_Str { _0: root.value.SassStr { text: text, quoted: false } }
}

function n(value: float) -> root.value.Value {
    root.builtins.map.unitless(value)
}

function map(pairs: root.std.Tuple2<string, root.value.Value>[]) -> root.value.Value {
    root.value.Value_Map {
        _0: root.value.Map.new(
            pairs.map((p) -> root.std.Tuple2<root.value.Value, root.value.Value> {
                root.std.Tuple2<root.value.Value, root.value.Value> { _0: s(p._0), _1: p._1 }
            }),
        ),
    }
}

/// `(&str, Value)` tuple literal helper for `map(&[("c", s("d"))])`.
// PORT: tuple literals → `kv("c", s("d"))`.
function kv(k: string, v: root.value.Value) -> root.std.Tuple2<string, root.value.Value> {
    root.std.Tuple2<string, root.value.Value> { _0: k, _1: v }
}

function call(name: string, args: root.value.Value[]) -> root.value.Value {
    let named: root.std.Tuple2<string, root.value.Value>[] = [];
    let r = root.std.expect(
        root.builtins.map.try_call(name, args, named, pos()),
        "name owned by map family",
    );
    // PORT: `Result::expect("no error")` on the stored `Ok`/`Err` value.
    match (r) {
        let ok: root.std.Ok<root.value.Value> => ok.value,
        let err: root.std.Err<root.error.Error> => root.std.panic(`no error: ${err.error.message}`),
    }
}

test "map_get_returns_value_or_null" {
    let m = map([kv("c", s("d"))]);
    // PORT: `m.clone()` → `m` (neither copy is mutated).
    assert.equal(call("map-get", [m, s("c")]).to_css(false), "d");
    assert.is_true(call("map-get", [m, s("z")]) is root.value.Value_Null)
}

test "map_keys_and_values_are_comma_lists" {
    let m = map([kv("c", n(1.0)), kv("d", n(2.0))]);
    // PORT: `std::slice::from_ref(&m)` → `[m]`.
    assert.equal(call("map-keys", [m]).to_css(false), "c, d");
    assert.equal(call("map-values", [m]).to_css(false), "1, 2")
}

test "map_has_key_reports_presence" {
    let m = map([kv("c", s("d"))]);
    assert.equal(call("map-has-key", [m, s("c")]).to_css(false), "true");
    assert.equal(call("map-has-key", [m, s("z")]).to_css(false), "false")
}

test "map_merge_overwrites_and_appends" {
    let a = map([kv("c", s("d"))]);
    let b = map([kv("e", s("f"))]);
    assert.equal(call("map-merge", [a, b]).to_css(false), "(c: d, e: f)");
    let a = map([kv("c", n(1.0))]);
    let b = map([kv("c", n(2.0))]);
    assert.equal(call("map-merge", [a, b]).to_css(false), "(c: 2)")
}

test "map_remove_drops_keys" {
    let m = map([kv("c", s("d")), kv("x", s("y"))]);
    assert.equal(call("map-remove", [m, s("c")]).to_css(false), "(x: y)")
}

test "length_and_nth_on_maps" {
    let m = map([kv("c", n(1.0)), kv("d", n(2.0))]);
    assert.equal(call("length", [m]).to_css(false), "2");
    assert.equal(call("nth", [m, n(1.0)]).to_css(false), "c 1")
}

test "length_and_nth_decline_non_maps" {
    let named: root.std.Tuple2<string, root.value.Value>[] = [];
    // A non-map first argument leaves these for the list family.
    assert.is_true(root.builtins.map.try_call("length", [s("x")], named, pos()) == null);
    assert.is_true(root.builtins.map.try_call("nth", [s("x"), n(1.0)], named, pos()) == null)
}

test "empty_list_acts_as_empty_map" {
    let no_items: root.value.Value[] = [];
    let empty: root.value.Value = root.value.Value_List {
        _0: root.value.List {
            items: no_items,
            sep: root.value.ListSep.Space,
            bracketed: false,
            keywords: null,
        },
    };
    assert.equal(call("map-keys", [empty]).to_css(false), "");
    assert.is_true(call("map-get", [empty, s("a")]) is root.value.Value_Null)
}
