// Port of clap_builder/src/parser/matches/matched_arg.rs

class MatchedArg {
    _source: ValueSource?,
    _indices: int[],
    _type_id: AnyValueId?,
    _vals: AnyValue[][],
    _raw_vals: OsString[][],
    _ignore_case: bool,

    function new_arg(arg: Arg) -> MatchedArg {
        let ignore_case = arg.is_ignore_case_set();
        MatchedArg {
            _source: null,
            _indices: [],
            _type_id: arg.get_value_parser().type_id(),
            _vals: [],
            _raw_vals: [],
            _ignore_case: ignore_case,
        }
    }

    function new_group() -> MatchedArg {
        let ignore_case = false;
        MatchedArg {
            _source: null,
            _indices: [],
            _type_id: null,
            _vals: [],
            _raw_vals: [],
            _ignore_case: ignore_case,
        }
    }

    function new_external(cmd: Command) -> MatchedArg {
        let ignore_case = false;
        let vp = cmd.get_external_subcommand_value_parser() ?? baml.sys.panic(INTERNAL_ERROR_MSG());
        MatchedArg {
            _source: null,
            _indices: [],
            _type_id: vp.type_id(),
            _vals: [],
            _raw_vals: [],
            _ignore_case: ignore_case,
        }
    }

    function indices(self) -> int[] { self._indices }

    function get_index(self, index: int) -> int? { self._indices.at(index) }

    function push_index(self, index: int) -> void { self._indices.push(index); }

    function vals(self) -> AnyValue[][] { self._vals }

    function into_vals(self) -> AnyValue[][] { self._vals }

    function vals_flatten(self) -> AnyValue[] { self._vals.flat_map((v) -> { v }) }

    function into_vals_flatten(self) -> AnyValue[] { self.vals_flatten() }

    function raw_vals(self) -> OsString[][] { self._raw_vals }

    function raw_vals_flatten(self) -> OsString[] { self._raw_vals.flat_map((v) -> { v }) }

    function first(self) -> AnyValue? { self.vals_flatten().at(0) }

    function first_raw(self) -> OsString? { self.raw_vals_flatten().at(0) }

    function new_val_group(self) -> void {
        self._vals.push([]);
        self._raw_vals.push([]);
    }

    function append_val(self, val: AnyValue, raw_val: OsString) -> void {
        // We assume there is always a group created before.
        self._vals[-1].push(val);
        self._raw_vals[-1].push(raw_val);
    }

    function num_vals(self) -> int {
        self._vals.reduce((acc, v) -> { acc + v.length() }, 0)
    }

    // Will be used later
    function num_vals_last_group(self) -> int {
        if let last: AnyValue[] = self._vals.at(-1) { last.length() } else { 0 }
    }

    function check_explicit(self, predicate: ArgPredicate) -> bool {
        if let s: ValueSource = self._source {
            if (!value_source_is_explicit(s)) {
                return false;
            }
        }

        match (predicate) {
            let eq: ArgPredicateEquals => self.raw_vals_flatten().some((v) -> {
                if (self._ignore_case) {
                    // If `v` isn't utf8, it can't match `val`, so `OsStr::to_str` should be fine
                    eq_ignore_case(v, eq.value)
                } else {
                    v == eq.value
                }
            }),
            let p: ArgPredicateIsPresent => true,
        }
    }

    function source(self) -> ValueSource? { self._source }

    function set_source(self, source: ValueSource) -> void {
        if let existing: ValueSource = self._source {
            self._source = value_source_max(existing, source);
        } else {
            self._source = source;
        }
    }

    function type_id(self) -> AnyValueId? { self._type_id }

    function infer_type_id(self, expected: AnyValueId) -> AnyValueId {
        if let t: AnyValueId = self._type_id {
            return t;
        }
        let actual = self.vals_flatten().map((v) -> { v.type_id() }).find((actual) -> { actual != expected });
        actual ?? expected
    }

    function clone(self) -> MatchedArg {
        MatchedArg {
            ...self,
            _indices: self._indices.slice(0, self._indices.length()),
            _vals: self._vals.map((g) -> { g.slice(0, g.length()) }),
            _raw_vals: self._raw_vals.map((g) -> { g.slice(0, g.length()) }),
        }
    }
}
