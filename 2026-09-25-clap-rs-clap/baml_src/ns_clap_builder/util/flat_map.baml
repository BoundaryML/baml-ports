// Port of clap_builder/src/util/flat_map.rs

/// Flat (Vec) backed map
///
/// This preserves insertion order
class FlatMap<K, V> {
    keys: K[],
    values: V[],

    function new() -> FlatMap<K, V> { FlatMap { keys: [], values: [] } }

    function insert(self, key: K, value: V) -> V? {
        for (let index in baml.iter.Range.new(0, self.keys.length())) {
            if (self.keys[index] == key) {
                let old = self.values[index];
                self.values[index] = value;
                return old;
            }
        }
        self.insert_unchecked(key, value);
        null
    }

    function insert_unchecked(self, key: K, value: V) -> void {
        self.keys.push(key);
        self.values.push(value);
    }

    // NOTE: `Array.index_of`/`includes` compare class instances by identity;
    // clap's `FlatMap` relies on `PartialEq`, i.e. BAML's structural `==`.
    function position(self, key: K) -> int? {
        self.keys.find_index((k) -> { k == key })
    }

    function contains_key(self, key: K) -> bool {
        self.position(key) != null
    }

    function remove(self, key: K) -> V? {
        let index = self.position(key);
        if let i: int = index {
            self.keys.remove_at(i);
            self.values.remove_at(i)
        } else {
            null
        }
    }

    function is_empty(self) -> bool { self.keys.length() == 0 }

    function length(self) -> int { self.keys.length() }

    /// `entry(key).or_insert(default)`
    function or_insert(self, key: K, default: V) -> V {
        let index = self.position(key);
        if let i: int = index {
            self.values[i]
        } else {
            self.keys.push(key);
            self.values.push(default);
            default
        }
    }

    function get(self, k: K) -> V? {
        let index = self.position(k);
        if let i: int = index { self.values[i] } else { null }
    }

    function get_keys(self) -> K[] { self.keys }

    function get_values(self) -> V[] { self.values }
}

testset "flat_map" {
    test "insert_get_remove" {
        let m: FlatMap<string, int> = FlatMap.new();
        assert.equal(m.insert("a", 1), null);
        assert.equal(m.insert("b", 2), null);
        assert.equal(m.insert("a", 3), 1);
        assert.equal(m.get("a"), 3);
        assert.equal(m.get_keys(), ["a", "b"]);
        assert.equal(m.remove("a"), 3);
        assert.equal(m.get_keys(), ["b"]);
        assert.equal(m.or_insert("c", 5), 5);
        assert.equal(m.or_insert("c", 7), 5)
    }
}
