// Port of clap_builder/src/builder/range.rs

/// `usize::MAX`
function USIZE_MAX() -> int { 4611686018427387903 }

/// Values per occurrence for an argument
class ValueRange {
    _start_inclusive: int,
    _end_inclusive: int,

    /// Nor argument values, or a flag
    function EMPTY() -> ValueRange { ValueRange { _start_inclusive: 0, _end_inclusive: 0 } }

    /// A single argument value, the most common case for options
    function SINGLE() -> ValueRange { ValueRange { _start_inclusive: 1, _end_inclusive: 1 } }

    function OPTIONAL() -> ValueRange { ValueRange { _start_inclusive: 0, _end_inclusive: 1 } }

    function FULL() -> ValueRange { ValueRange { _start_inclusive: 0, _end_inclusive: USIZE_MAX() } }

    /// Create a range
    ///
    /// Rust accepts any range expression (`1..=3`, `2..`, `..4`, `3`). BAML
    /// has no range syntax, so pass a fixed count or use the constructors
    /// below (`ValueRange.inclusive(1, 3)`, `ValueRange.from(2)`, ...).
    ///
    /// # Panics
    ///
    /// If the end is less than the start (debug builds)
    function new(range: ValueRange | int) -> ValueRange {
        match (range) {
            let n: int => ValueRange.raw(n, n),
            let r: ValueRange => r,
        }
    }

    function raw(start_inclusive: int, end_inclusive: int) -> ValueRange {
        assert.is_true(start_inclusive <= end_inclusive);
        ValueRange { _start_inclusive: start_inclusive, _end_inclusive: end_inclusive }
    }

    /// `start..end`
    function range(start: int, end: int) -> ValueRange {
        ValueRange.raw(start, if (end > 0) { end - 1 } else { 0 })
    }

    /// `start..=end`
    function inclusive(start: int, end: int) -> ValueRange { ValueRange.raw(start, end) }

    /// `start..`
    function from(start: int) -> ValueRange { ValueRange.raw(start, USIZE_MAX()) }

    /// `..end`
    function to(end: int) -> ValueRange { ValueRange.raw(0, if (end > 0) { end - 1 } else { 0 }) }

    /// `..=end`
    function to_inclusive(end: int) -> ValueRange { ValueRange.raw(0, end) }

    /// Fewest number of values the argument accepts
    function min_values(self) -> int { self._start_inclusive }

    /// Most number of values the argument accepts
    function max_values(self) -> int { self._end_inclusive }

    /// Report whether the argument takes any values (ie is a flag)
    function takes_values(self) -> bool { self._end_inclusive != 0 }

    function is_unbounded(self) -> bool { self._end_inclusive == USIZE_MAX() }

    function is_fixed(self) -> bool { self._start_inclusive == self._end_inclusive }

    function is_multiple(self) -> bool {
        self._start_inclusive != self._end_inclusive || 1 < self._start_inclusive
    }

    function num_values(self) -> int? {
        if (self.is_fixed()) { self._start_inclusive } else { null }
    }

    function accepts_more(self, current: int) -> bool { current < self._end_inclusive }

    implements baml.ToString {
        function to_string(self) -> string throws never {
            let s = `${self._start_inclusive}`;
            if (self.is_fixed()) {
                s
            } else if (self._end_inclusive == USIZE_MAX()) {
                s + ".."
            } else {
                s + `..=${self._end_inclusive}`
            }
        }
    }
}

/// `impl<I: Into<ValueRange>> IntoResettable<ValueRange> for I`
function into_value_range(r: ValueRange | int) -> ValueRange { ValueRange.new(r) }

testset "value_range" {
    test "from_fixed" {
        let range = ValueRange.new(5);
        assert.equal(range.min_values(), 5);
        assert.equal(range.max_values(), 5);
        assert.is_true(range.takes_values());
        assert.is_true(range.is_multiple())
    }
    test "from_fixed_empty" {
        let range = ValueRange.new(0);
        assert.equal(range.min_values(), 0);
        assert.equal(range.max_values(), 0);
        assert.is_true(!range.takes_values());
        assert.is_true(!range.is_multiple())
    }
    test "from_range" {
        let range = ValueRange.range(5, 10);
        assert.equal(range.min_values(), 5);
        assert.equal(range.max_values(), 9);
        assert.is_true(range.takes_values());
        assert.is_true(range.is_multiple())
    }
    test "from_range_inclusive" {
        let range = ValueRange.inclusive(5, 10);
        assert.equal(range.min_values(), 5);
        assert.equal(range.max_values(), 10);
        assert.is_true(range.is_multiple())
    }
    test "from_range_full" {
        let range = ValueRange.FULL();
        assert.equal(range.min_values(), 0);
        assert.equal(range.max_values(), USIZE_MAX());
        assert.is_true(range.is_multiple())
    }
    test "from_range_from" {
        let range = ValueRange.from(5);
        assert.equal(range.min_values(), 5);
        assert.equal(range.max_values(), USIZE_MAX())
    }
    test "from_range_to" {
        let range = ValueRange.to(10);
        assert.equal(range.min_values(), 0);
        assert.equal(range.max_values(), 9)
    }
    test "from_range_to_inclusive" {
        let range = ValueRange.to_inclusive(10);
        assert.equal(range.min_values(), 0);
        assert.equal(range.max_values(), 10)
    }
    test "display" {
        assert.equal(`${ValueRange.new(1)}`, "1");
        assert.equal(`${ValueRange.from(1)}`, "1..");
        assert.equal(`${ValueRange.inclusive(1, 3)}`, "1..=3")
    }
}
