// Port of clap_builder/src/parser/validator.rs

class Validator {
    _cmd: Command,
    _required: ChildGraph<Id>,

    function new(cmd: Command) -> Validator {
        let required = cmd.required_graph();
        Validator { _cmd: cmd, _required: required }
    }

    function validate(self, matcher: ArgMatcher) -> void throws Error {
        let conflicts = Conflicts.with_args(self._cmd, matcher);
        let has_subcmd = matcher.subcommand_name() != null;

        if (!has_subcmd && self._cmd.is_arg_required_else_help_set()) {
            let num_user_values = matcher.args().get_values()
                .filter((matched) -> { matched.check_explicit(ArgPredicateIsPresent {}) })
                .length();
            if (num_user_values == 0) {
                let message = self._cmd.write_help_err(false);
                throw error_display_help_error(self._cmd, message);
            }
        }
        if (!has_subcmd && self._cmd.is_subcommand_required_set()) {
            let bn = self._cmd.get_bin_name_fallback();
            throw error_missing_subcommand(
                self._cmd,
                bn,
                self._cmd.all_subcommand_names(),
                Usage.new(self._cmd)
                    .required(self._required)
                    .create_usage_with_title([]),
            );
        }

        self.validate_conflicts(matcher, conflicts);
        if (!(self._cmd.is_subcommand_negates_reqs_set() && has_subcmd)) {
            self.validate_required(matcher, conflicts);
        }
    }

    function present_ids(self, matcher: ArgMatcher) -> Id[] {
        let keys = matcher.args().get_keys();
        let values = matcher.args().get_values();
        let out: Id[] = [];
        for (let i in baml.iter.Range.new(0, keys.length())) {
            if (values[i].check_explicit(ArgPredicateIsPresent {})) {
                out.push(keys[i]);
            }
        }
        out
    }

    function validate_conflicts(self, matcher: ArgMatcher, conflicts: Conflicts) -> void throws Error {
        self.validate_exclusive(matcher);

        for (let arg_id in self.present_ids(matcher).filter((arg_id) -> { self._cmd.find(arg_id) != null })) {
            let c = conflicts.gather_conflicts(self._cmd, arg_id);
            self.build_conflict_err(arg_id, c, matcher);
        }
    }

    function validate_exclusive(self, matcher: ArgMatcher) -> void throws Error {
        let present = self.present_ids(matcher);
        let args_count = present
            // Avoid including our own groups by checking none of them.  If a group is present, the
            // args for the group will be.
            .filter((arg_id) -> { self._cmd.find(arg_id) != null })
            .length();
        if (args_count <= 1) {
            // Nothing present to conflict with
            return;
        }

        for (let id in present) {
            if let arg: Arg = self._cmd.find(id) {
                // Find `arg`s which are exclusive but also appear with other args.
                if (arg.is_exclusive_set() && args_count > 1) {
                    // Throw an error for the first conflict found.
                    throw error_argument_conflict(
                        self._cmd,
                        arg.to_string(),
                        [],
                        Usage.new(self._cmd)
                            .required(self._required)
                            .create_usage_with_title([]),
                    );
                }
            }
        }
    }

    function build_conflict_err(self, name: Id, conflict_ids_in: Id[], matcher: ArgMatcher) -> void throws Error {
        if (conflict_ids_in.length() == 0) {
            return;
        }

        let set: FlatSet<Id> = FlatSet.new();
        for (let c_id in conflict_ids_in) {
            if (self._cmd.find_group(c_id) != null) {
                set.extend(self._cmd.unroll_args_in_group(c_id));
            } else {
                set.insert(c_id);
            }
        }
        let conflict_ids = set.into_vec();

        let conflicts = conflict_ids.map((c_id) -> {
            let c_arg = self._cmd.find(c_id) ?? baml.sys.panic(INTERNAL_ERROR_MSG());
            c_arg.to_string()
        });

        let former_arg = self._cmd.find(name) ?? baml.sys.panic(INTERNAL_ERROR_MSG());
        let usg = self.build_conflict_err_usage(matcher, conflict_ids);
        throw error_argument_conflict(
            self._cmd,
            former_arg.to_string(),
            conflicts,
            usg,
        )
    }

    function build_conflict_err_usage(self, matcher: ArgMatcher, conflicting_keys: Id[]) -> StyledStr? {
        let used_filtered: Id[] = self.present_ids(matcher)
            .filter((n) -> {
                // Filter out the args we don't want to specify.
                if let a: Arg = self._cmd.find(n) { !a.is_hide_set() } else { false }
            })
            .filter((key) -> { !conflicting_keys.includes(key) });

        let required: Id[] = used_filtered
            .filter_map((key) -> { self._cmd.find(key) })
            .flat_map((arg) -> { arg._requires.map((item) -> { item.id }) })
            .filter((key) -> { !used_filtered.includes(key) && !conflicting_keys.includes(key) })
            .concat(used_filtered);
        Usage.new(self._cmd)
            .required(self._required)
            .create_usage_with_title(required)
    }

    function gather_requires(self, matcher: ArgMatcher) -> void {
        let keys = matcher.args().get_keys();
        let values = matcher.args().get_values();
        for (let i in baml.iter.Range.new(0, keys.length())) {
            let name = keys[i];
            let matched = values[i];
            if (!matched.check_explicit(ArgPredicateIsPresent {})) {
                continue;
            }
            if let arg: Arg = self._cmd.find(name) {
                let is_relevant = (r: ArgRequire) -> Id? {
                    let required = matched.check_explicit(r.predicate);
                    if (required) { r.id } else { null }
                };

                for (let req in self._cmd.unroll_arg_requires(is_relevant, arg.get_id())) {
                    self._required.insert(req);
                }
            } else if let g: ArgGroup = self._cmd.find_group(name) {
                for (let r in g._requires) {
                    self._required.insert(r);
                }
            }
        }
    }

    function validate_required(self, matcher: ArgMatcher, conflicts: Conflicts) -> void throws Error {
        self.gather_requires(matcher);

        let missing_required: Id[] = [];
        let highest_index = 0;

        let is_exclusive_present = self.present_ids(matcher).some((id) -> {
            if let arg: Arg = self._cmd.find(id) { arg.is_exclusive_set() } else { false }
        });

        for (let arg_or_group in self._required.iter().filter((r) -> { !matcher.check_explicit(r, ArgPredicateIsPresent {}) })) {
            if let arg: Arg = self._cmd.find(arg_or_group) {
                if (!is_exclusive_present && !self.is_missing_required_ok(arg, conflicts)) {
                    missing_required.push(arg.get_id());
                    if (!arg.is_last_set()) {
                        let idx = arg.get_index() ?? 0;
                        if (idx > highest_index) { highest_index = idx; }
                    }
                }
            } else if let group: ArgGroup = self._cmd.find_group(arg_or_group) {
                if (!self._cmd.unroll_args_in_group(group._id).some((a) -> { matcher.check_explicit(a, ArgPredicateIsPresent {}) })) {
                    missing_required.push(group.get_id());
                }
            }
        }

        // Validate the conditionally required args
        for (let a in self._cmd.get_arguments().filter((a) -> { !matcher.check_explicit(a.get_id(), ArgPredicateIsPresent {}) })) {
            let required = false;

            for (let rif in a._r_ifs) {
                if (matcher.check_explicit(rif.id, ArgPredicateEquals { value: rif.value })) {
                    required = true;
                }
            }

            let match_all = a._r_ifs_all.every((rif) -> { matcher.check_explicit(rif.id, ArgPredicateEquals { value: rif.value }) });
            if (match_all && a._r_ifs_all.length() > 0) {
                required = true;
            }

            if ((a._r_unless.length() > 0 || a._r_unless_all.length() > 0)
                && self.fails_arg_required_unless(a, matcher)) {
                required = true;
            }

            if (!is_exclusive_present && required) {
                missing_required.push(a.get_id());
                if (!a.is_last_set()) {
                    let idx = a.get_index() ?? 0;
                    if (idx > highest_index) { highest_index = idx; }
                }
            }
        }

        // For display purposes, include all of the preceding positional arguments
        if (!self._cmd.is_allow_missing_positional_set()) {
            for (let pos in self._cmd.get_positionals().filter((a) -> { !matcher.check_explicit(a.get_id(), ArgPredicateIsPresent {}) })) {
                let idx = pos.get_index();
                let less = if let i: int = idx { i < highest_index } else { true };
                if (less) {
                    missing_required.push(pos.get_id());
                }
            }
        }

        if (missing_required.length() > 0) {
            self.missing_required_error(matcher, missing_required);
        }
    }

    function is_missing_required_ok(self, a: Arg, conflicts: Conflicts) -> bool {
        if (conflicts.gather_conflicts(self._cmd, a.get_id()).length() > 0) {
            return true;
        }

        for (let group_id in self._cmd.groups_for_arg(a.get_id())) {
            if (conflicts.gather_conflicts(self._cmd, group_id).length() > 0) {
                return true;
            }
        }
        false
    }

    // Failing a required unless means, the arg's "unless" wasn't present, and neither were they
    function fails_arg_required_unless(self, a: Arg, matcher: ArgMatcher) -> bool {
        let exists = (id: Id) -> bool { matcher.check_explicit(id, ArgPredicateIsPresent {}) };

        (a._r_unless_all.length() == 0 || !a._r_unless_all.every(exists))
            && !a._r_unless.some(exists)
    }

    // `req_args`: an arg to include in the error even if not used
    function missing_required_error(self, matcher: ArgMatcher, raw_req_args: Id[]) -> void throws Error {
        let usg = Usage.new(self._cmd).required(self._required);

        let req_args = if (features().usage) {
            usg.get_required_usage_from(raw_req_args, matcher, true).map((s) -> { s.to_string() })
        } else {
            let set: FlatSet<string> = FlatSet.new();
            for (let id in raw_req_args) {
                if let arg: Arg = self._cmd.find(id) {
                    set.insert(arg.to_string());
                } else if (self._cmd.find_group(id) != null) {
                    set.insert(self._cmd.format_group(id).to_string());
                } else {
                    set.insert("");
                }
            }
            set.into_vec()
        };

        let used: Id[] = self.present_ids(matcher)
            .filter((n) -> {
                // Filter out the args we don't want to specify.
                if let a: Arg = self._cmd.find(n) { !a.is_hide_set() } else { false }
            })
            .concat(raw_req_args);

        throw error_missing_required_argument(
            self._cmd,
            req_args,
            usg.create_usage_with_title(used),
        )
    }
}

class Conflicts {
    _potential: FlatMap<Id, Id[]>,

    function with_args(cmd: Command, matcher: ArgMatcher) -> Conflicts {
        let potential: FlatMap<Id, Id[]> = FlatMap.new();
        let keys = matcher.args().get_keys();
        let values = matcher.args().get_values();
        for (let i in baml.iter.Range.new(0, keys.length())) {
            if (values[i].check_explicit(ArgPredicateIsPresent {})) {
                let conf = gather_direct_conflicts(cmd, keys[i]);
                potential.insert_unchecked(keys[i], conf);
            }
        }
        Conflicts { _potential: potential }
    }

    function gather_conflicts(self, cmd: Command, arg_id: Id) -> Id[] {
        let conflicts: Id[] = [];

        let arg_id_conflicts = self.get_direct_conflicts(arg_id) ?? gather_direct_conflicts(cmd, arg_id);
        // `is_missing_required_ok` is a case where we check not-present args for conflicts

        let keys = self._potential.get_keys();
        let values = self._potential.get_values();
        for (let i in baml.iter.Range.new(0, keys.length())) {
            let other_arg_id = keys[i];
            let other_arg_id_conflicts = values[i];
            if (arg_id == other_arg_id) {
                continue;
            }

            if (arg_id_conflicts.includes(other_arg_id)) {
                conflicts.push(other_arg_id);
            }
            if (other_arg_id_conflicts.includes(arg_id)) {
                conflicts.push(other_arg_id);
            }
        }

        conflicts
    }

    function get_direct_conflicts(self, arg_id: Id) -> Id[]? {
        self._potential.get(arg_id)
    }
}

function gather_direct_conflicts(cmd: Command, id: Id) -> Id[] {
    if let arg: Arg = cmd.find(id) {
        gather_arg_direct_conflicts(cmd, arg)
    } else if let group: ArgGroup = cmd.find_group(id) {
        gather_group_direct_conflicts(group)
    } else {
        []
    }
}

function gather_arg_direct_conflicts(cmd: Command, arg: Arg) -> Id[] {
    let conf = arg._blacklist.slice(0, arg._blacklist.length());
    for (let group_id in cmd.groups_for_arg(arg.get_id())) {
        let group = cmd.find_group(group_id) ?? baml.sys.panic(INTERNAL_ERROR_MSG());
        for (let c in group._conflicts) { conf.push(c); }
        if (!group._multiple) {
            for (let member_id in group._args) {
                if (member_id != arg.get_id()) {
                    conf.push(member_id);
                }
            }
        }
    }

    // Overrides are implicitly conflicts
    for (let o in arg._overrides) { conf.push(o); }

    conf
}

function gather_group_direct_conflicts(group: ArgGroup) -> Id[] {
    group._conflicts.slice(0, group._conflicts.length())
}

function get_possible_values_cli(a: Arg) -> PossibleValue[] {
    if (!a.is_takes_value_set()) {
        []
    } else {
        a.get_value_parser().possible_values() ?? []
    }
}
