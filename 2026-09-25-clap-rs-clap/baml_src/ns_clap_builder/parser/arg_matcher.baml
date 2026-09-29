// Port of clap_builder/src/parser/arg_matcher.rs

class ArgMatcher {
    _matches: ArgMatches,
    _pending: PendingArg?,

    function new(cmd: Command) -> ArgMatcher {
        let m = ArgMatches.new();
        m._valid_args = cmd.get_arguments().map((a) -> { a.get_id() }).concat(cmd.get_groups().map((g) -> { g.get_id() }));
        m._valid_subcommands = cmd.get_subcommands().map((sc) -> { sc.get_name_str() });
        ArgMatcher { _matches: m, _pending: null }
    }

    function into_inner(self) -> ArgMatches { self._matches }

    /// `impl Deref for ArgMatcher { type Target = ArgMatches; }`
    function inner(self) -> ArgMatches { self._matches }

    function propagate_globals(self, global_arg_vec: Id[]) -> void {
        let vals_map: FlatMap<Id, MatchedArg> = FlatMap.new();
        self.fill_in_global_values(global_arg_vec, vals_map);
    }

    function fill_in_global_values(self, global_arg_vec: Id[], vals_map: FlatMap<Id, MatchedArg>) -> void {
        for (let global_arg in global_arg_vec) {
            if let ma: MatchedArg = self.get(global_arg) {
                // We have to check if the parent's global arg wasn't used but still exists
                // such as from a default value.
                //
                // For example, `myprog subcommand --global-arg=value` where `--global-arg` defines
                // a default value of `other` myprog would have an existing MatchedArg for
                // `--global-arg` where the value is `other`
                let to_update = if let parent_ma: MatchedArg = vals_map.get(global_arg) {
                    if (value_source_opt_gt(parent_ma.source(), ma.source())) {
                        parent_ma
                    } else {
                        ma
                    }
                } else {
                    ma
                };
                vals_map.insert(global_arg, to_update.clone());
            }
        }
        if let sc: SubCommand = self._matches._subcommand {
            let am = ArgMatcher { _matches: sc.matches, _pending: null };
            am.fill_in_global_values(global_arg_vec, vals_map);
            sc.matches = am._matches;
        }

        let keys = vals_map.get_keys();
        let values = vals_map.get_values();
        for (let i in baml.iter.Range.new(0, keys.length())) {
            self._matches._args.insert(keys[i], values[i].clone());
        }
    }

    function get(self, arg: Id) -> MatchedArg? { self._matches._args.get(arg) }

    function get_mut(self, arg: Id) -> MatchedArg? { self._matches._args.get(arg) }

    function remove(self, arg: Id) -> bool { self._matches._args.remove(arg) != null }

    function contains(self, arg: Id) -> bool { self._matches._args.contains_key(arg) }

    function arg_ids(self) -> Id[] { self._matches._args.get_keys() }

    function args(self) -> FlatMap<Id, MatchedArg> { self._matches._args }

    function subcommand(self, sc: SubCommand) -> void { self._matches._subcommand = sc; }

    function subcommand_name(self) -> string? { self._matches.subcommand_name() }

    function check_explicit(self, arg: Id, predicate: ArgPredicate) -> bool {
        if let a: MatchedArg = self.get(arg) { a.check_explicit(predicate) } else { false }
    }

    function start_custom_arg(self, arg: Arg, source: ValueSource) -> void {
        let id = arg.get_id();
        let ma = self._matches._args.or_insert(id, MatchedArg.new_arg(arg));
        ma.set_source(source);
        ma.new_val_group();
    }

    function start_custom_group(self, id: Id, source: ValueSource) -> void {
        let ma = self._matches._args.or_insert(id, MatchedArg.new_group());
        ma.set_source(source);
        ma.new_val_group();
    }

    function start_occurrence_of_external(self, cmd: Command) -> void {
        let id = ID_EXTERNAL();
        let ma = self._matches._args.or_insert(id, MatchedArg.new_external(cmd));
        ma.set_source(ValueSource.CommandLine);
        ma.new_val_group();
    }

    function add_val_to(self, arg: Id, val: AnyValue, raw_val: OsString) -> void {
        let ma = self.get_mut(arg) ?? baml.sys.panic(INTERNAL_ERROR_MSG());
        ma.append_val(val, raw_val);
    }

    function add_index_to(self, arg: Id, idx: int) -> void {
        let ma = self.get_mut(arg) ?? baml.sys.panic(INTERNAL_ERROR_MSG());
        ma.push_index(idx);
    }

    function needs_more_vals(self, o: Arg) -> bool {
        let num_pending = if let p: PendingArg = self._pending {
            if (p.id == o.get_id()) { p.raw_vals.length() } else { 0 }
        } else {
            0
        };
        let expected = o.get_num_args() ?? baml.sys.panic(INTERNAL_ERROR_MSG());
        expected.accepts_more(num_pending)
    }

    function pending_arg_id(self) -> Id? {
        if let p: PendingArg = self._pending { p.id } else { null }
    }

    function pending_values_mut(self, id: Id, ident: Identifier?, trailing_values: bool) -> OsString[] {
        if (self._pending == null) {
            self._pending = PendingArg { id: id, ident: ident, raw_vals: [], trailing_idx: null };
        }
        let pending = self._pending ?? baml.sys.panic(INTERNAL_ERROR_MSG());
        if (trailing_values) {
            if (pending.trailing_idx == null) { pending.trailing_idx = pending.raw_vals.length(); }
        }
        pending.raw_vals
    }

    function start_trailing(self) -> void {
        if let pending: PendingArg = self._pending {
            // Allow asserting its started on subsequent calls
            if (pending.trailing_idx == null) { pending.trailing_idx = pending.raw_vals.length(); }
        }
    }

    function take_pending(self) -> PendingArg? {
        let p = self._pending;
        self._pending = null;
        p
    }

    // `Deref` to `ArgMatches`
    function subcommand_name_deref(self) -> string? { self._matches.subcommand_name() }
}
