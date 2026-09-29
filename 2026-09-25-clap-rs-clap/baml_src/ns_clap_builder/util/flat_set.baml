// Port of clap_builder/src/util/flat_set.rs

/// Flat (Vec) backed set
///
/// This preserves insertion order
class FlatSet<T> {
    inner: T[],

    function new() -> FlatSet<T> { FlatSet { inner: [] } }

    // NOTE: `Array.includes` compares class instances by identity; clap's
    // `FlatSet` relies on `PartialEq`, i.e. BAML's structural `==`.
    function insert(self, value: T) -> bool {
        if (self.inner.some((existing) -> { existing == value })) {
            return false;
        }
        self.inner.push(value);
        true
    }

    function contains(self, value: T) -> bool { self.inner.some((existing) -> { existing == value }) }

    function retain(self, f: (T) -> bool throws never) -> void {
        self.inner = self.inner.filter(f);
    }

    function is_empty(self) -> bool { self.inner.length() == 0 }

    function iter(self) -> T[] { self.inner }

    function extend(self, values: T[]) -> void {
        for (let v in values) { self.insert(v); }
    }

    function into_vec(self) -> T[] { self.inner }
}
