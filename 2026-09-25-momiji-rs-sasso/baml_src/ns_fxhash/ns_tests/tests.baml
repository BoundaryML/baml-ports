// Ported from sasso `src/fxhash.rs` `mod tests` (namespace `root.fxhash.tests`).
//
// PORT: `use super::*;` → items of `root.fxhash` are written fully qualified.

// PORT: `FxHashMap<String, i32>` → `map<string, int>` (PORTING_GUIDE.md §3:
// every `FxHashMap` is a BAML map; the hasher is not pluggable).
test "basic_map_roundtrips" {
    let m: map<string, int> = {};
    for (let i in baml.iter.Range.new(0, 1000)) {
        let _ = m.set(`key-${i}`, i);
    }
    assert.equal(m.length(), 1000);
    for (let i in baml.iter.Range.new(0, 1000)) {
        assert.equal(m.get(`key-${i}`), i);
    }
    assert.equal(m.get("missing"), null)
}

test "distinct_keys_mostly_distinct_hashes" {
    // Sanity: the hasher spreads short identifier-like keys (no all-equal).
    let h = (s: string) -> bigint {
        let hasher = root.fxhash.FxHasher.default();
        hasher.write(s.to_utf8());
        hasher.finish()
    };
    assert.is_true(h("color") != h("width"));
    assert.is_true(h("a") != h("b"));
    assert.is_true(h("margin-top") != h("margin-bottom"))
}
