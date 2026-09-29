// Port of clap_builder/src/output/usage.rs

function DEFAULT_SUB_VALUE_NAME() -> string { "COMMAND" }
function USAGE_SEP() -> string { "\n       " }

class Usage {
    _cmd: Command,
    _styles: Styles,
    _required: ChildGraph<Id>?,

    function new(cmd: Command) -> Usage {
        Usage { _cmd: cmd, _styles: cmd.get_styles(), _required: null }
    }

    function required(self, required: ChildGraph<Id>) -> Usage {
        self._required = required;
        self
    }

    // Creates a usage string for display. This happens just after all arguments were parsed, but before
    // any subcommands have been parsed (so as to give subcommands their own usage recursively)
    function create_usage_with_title(self, used: Id[]) -> StyledStr? {
        let styled = StyledStr.new();
        styled.push_str(`${self._styles.get_usage().render()}Usage:${self._styles.get_usage().render_reset()} `);
        if (self.write_usage_no_title(styled, used)) {
            styled.trim_end();
        } else {
            return null;
        }
        styled
    }

    // Creates a usage string (*without title*) if one was not provided by the user manually.
    function create_usage_no_title(self, used: Id[]) -> StyledStr? {
        let styled = StyledStr.new();
        if (self.write_usage_no_title(styled, used)) {
            styled.trim_end();
            styled
        } else {
            null
        }
    }

    // Creates a usage string (*without title*) if one was not provided by the user manually.
    function write_usage_no_title(self, styled: StyledStr, used: Id[]) -> bool {
        if let u: StyledStr = self._cmd.get_override_usage() {
            styled.push_styled(u);
            true
        } else if (features().usage) {
            if (used.length() == 0) {
                self.write_help_usage(styled);
            } else {
                self.write_smart_usage(styled, used);
            }
            true
        } else {
            false
        }
    }

    // Creates a usage string for display in help messages (i.e. not for errors)
    function write_help_usage(self, styled: StyledStr) -> void {
        if (self._cmd.has_visible_subcommands() && self._cmd.is_flatten_help_set()) {
            if (!self._cmd.is_subcommand_required_set()
                || self._cmd.is_args_conflicts_with_subcommands_set()) {
                self.write_arg_usage(styled, [], true);
                styled.trim_end();
                styled.push_str(USAGE_SEP());
            }
            let cmd = self._cmd.clone();
            cmd.build();
            let visible = cmd.get_subcommands().filter((c) -> { !c.is_hide_set() });
            for (let i in baml.iter.Range.new(0, visible.length())) {
                if (i != 0) {
                    styled.trim_end();
                    styled.push_str(USAGE_SEP());
                }
                Usage.new(visible[i]).write_usage_no_title(styled, []);
            }
        } else {
            self.write_arg_usage(styled, [], true);
            self.write_subcommand_usage(styled);
        }
    }

    // Creates a context aware usage string, or "smart usage" from currently used
    // args, and requirements
    function write_smart_usage(self, styled: StyledStr, used: Id[]) -> void {
        let placeholder = self._styles.get_placeholder();

        self.write_arg_usage(styled, used, true);

        if (self._cmd.is_subcommand_required_set()) {
            let value_name = self._cmd.get_subcommand_value_name() ?? DEFAULT_SUB_VALUE_NAME();
            styled.push_styled_str(placeholder, `<${value_name}>`);
        }
    }

    function write_arg_usage(self, styled: StyledStr, used: Id[], incl_reqs: bool) -> void {
        let literal = self._styles.get_literal();
        let placeholder = self._styles.get_placeholder();

        let bin_name = self._cmd.get_usage_name_fallback();
        if (!bin_name.is_empty()) {
            // the trim won't properly remove a leading space due to the formatting
            styled.push_styled_str(literal, bin_name);
            styled.push_str(" ");
        }

        if (used.length() == 0 && self.needs_options_tag()) {
            styled.push_styled_str(placeholder, "[OPTIONS]");
            styled.push_str(" ");
        }

        self.write_args(styled, used, !incl_reqs);
    }

    function write_subcommand_usage(self, styled: StyledStr) -> void {
        // incl_reqs is only false when this function is called recursively
        if (self._cmd.has_visible_subcommands() || self._cmd.is_allow_external_subcommands_set()) {
            let literal = self._styles.get_literal();
            let placeholder = self._styles.get_placeholder();
            let value_name = self._cmd.get_subcommand_value_name() ?? DEFAULT_SUB_VALUE_NAME();
            if (self._cmd.is_subcommand_negates_reqs_set()
                || self._cmd.is_args_conflicts_with_subcommands_set()) {
                styled.trim_end();
                styled.push_str(USAGE_SEP());
                if (self._cmd.is_args_conflicts_with_subcommands_set()) {
                    let bin_name = self._cmd.get_usage_name_fallback();
                    // Short-circuit full usage creation since no args will be relevant
                    styled.push_styled_str(literal, bin_name);
                    styled.push_str(" ");
                } else {
                    self.write_arg_usage(styled, [], false);
                }
                styled.push_styled_str(placeholder, `<${value_name}>`);
            } else if (self._cmd.is_subcommand_required_set()) {
                styled.push_styled_str(placeholder, `<${value_name}>`);
            } else {
                styled.push_styled_str(placeholder, `[${value_name}]`);
            }
        }
    }

    // Determines if we need the `[OPTIONS]` tag in the usage string
    function needs_options_tag(self) -> bool {
        for (let f in self._cmd.get_non_positionals()) {
            // Don't print `[OPTIONS]` just for help or version
            if (f.get_long() == "help" || f.get_long() == "version") {
                continue;
            }
            match (f.get_action()) {
                ArgAction.Help | ArgAction.HelpShort | ArgAction.HelpLong | ArgAction.Version => {
                    continue;
                },
                _ => {},
            }

            if (f.is_hide_set()) {
                continue;
            }
            if (f.is_required_set()) {
                continue;
            }
            let in_required_group = self._cmd.groups_for_arg(f.get_id()).some((grp_s) -> {
                self._cmd.get_groups().some((g) -> { g._id == grp_s && g._required })
            });
            if (in_required_group) {
                continue;
            }

            return true;
        }

        false
    }

    function required_graph(self) -> ChildGraph<Id> {
        if let r: ChildGraph<Id> = self._required { r } else { self._cmd.required_graph() }
    }

    // Returns the required args in usage string form by fully unrolling all groups
    function write_args(self, styled: StyledStr, incls: Id[], force_optional: bool) -> void {
        let literal = self._styles.get_literal();

        let required = self.required_graph();

        let unrolled_reqs: Id[] = [];
        for (let a in required.iter()) {
            let is_relevant = (r: ArgRequire) -> Id? {
                let req = match (r.predicate) {
                    let e: ArgPredicateEquals => false,
                    let p: ArgPredicateIsPresent => true,
                };
                if (req) { r.id } else { null }
            };
            for (let aa in self._cmd.unroll_arg_requires(is_relevant, a)) {
                // if we don't check for duplicates here this causes duplicate error messages
                // see https://github.com/clap-rs/clap/issues/2770
                unrolled_reqs.push(aa);
            }
            // always include the required arg itself. it will not be enumerated
            // by unroll_requirements_for_arg.
            unrolled_reqs.push(a);
        }

        let required_groups_members: FlatSet<Id> = FlatSet.new();
        let required_groups: FlatSet<StyledStr> = FlatSet.new();
        for (let req in unrolled_reqs.concat(incls)) {
            if (self._cmd.find_group(req) != null) {
                let group_members = self._cmd.unroll_args_in_group(req);
                let elem = self._cmd.format_group(req);
                required_groups.insert(elem);
                required_groups_members.extend(group_members);
            }
        }

        let required_opts: FlatSet<StyledStr> = FlatSet.new();
        let required_positionals: (StyledStr | null)[] = [];
        for (let req in unrolled_reqs.concat(incls)) {
            if let arg: Arg = self._cmd.find(req) {
                if (required_groups_members.contains(arg.get_id())) {
                    continue;
                }

                let stylized = arg.stylized(self._styles, !force_optional);
                if let index: int = arg.get_index() {
                    while (required_positionals.length() < index + 1) {
                        required_positionals.push(null);
                    }
                    required_positionals[index] = stylized;
                } else {
                    required_opts.insert(stylized);
                }
            }
        }

        for (let pos in self._cmd.get_positionals()) {
            if (pos.is_hide_set()) {
                continue;
            }
            if (required_groups_members.contains(pos.get_id())) {
                continue;
            }

            let index = pos.get_index() ?? 0;
            while (required_positionals.length() < index + 1) {
                required_positionals.push(null);
            }
            if let existing: StyledStr = required_positionals[index] {
                if (pos.is_last_set()) {
                    let n = StyledStr.new();
                    n.push_styled_str(literal, "--");
                    n.push_str(" ");
                    n.push_styled(existing);
                    required_positionals[index] = n;
                }
            } else {
                let s = StyledStr.new();
                if (pos.is_last_set()) {
                    s.push_styled_str(literal, "[--");
                    s.push_str(" ");
                    s.push_styled(pos.stylized(self._styles, true));
                    s.push_styled_str(literal, "]");
                } else {
                    s = pos.stylized(self._styles, false);
                }
                required_positionals[index] = s;
            }
            if (pos.is_last_set() && force_optional) {
                required_positionals[index] = null;
            }
        }

        if (!force_optional) {
            for (let a in required_opts.into_vec()) {
                styled.push_styled(a);
                styled.push_str(" ");
            }
            for (let a in required_groups.into_vec()) {
                styled.push_styled(a);
                styled.push_str(" ");
            }
        }
        for (let p in required_positionals) {
            if let a: StyledStr = p {
                styled.push_styled(a);
                styled.push_str(" ");
            }
        }
    }

    function get_required_usage_from(self, incls: Id[], matcher: ArgMatcher?, incl_last: bool) -> StyledStr[] {
        let required = self.required_graph();

        let unrolled_reqs: Id[] = [];
        for (let a in required.iter()) {
            let is_relevant = (r: ArgRequire) -> Id? {
                let req = match (r.predicate) {
                    let e: ArgPredicateEquals => if let m: ArgMatcher = matcher { m.check_explicit(a, r.predicate) } else { false },
                    let p: ArgPredicateIsPresent => true,
                };
                if (req) { r.id } else { null }
            };
            for (let aa in self._cmd.unroll_arg_requires(is_relevant, a)) {
                // if we don't check for duplicates here this causes duplicate error messages
                // see https://github.com/clap-rs/clap/issues/2770
                unrolled_reqs.push(aa);
            }
            // always include the required arg itself. it will not be enumerated
            // by unroll_requirements_for_arg.
            unrolled_reqs.push(a);
        }

        let required_groups_members: FlatSet<Id> = FlatSet.new();
        let required_groups: FlatSet<StyledStr> = FlatSet.new();
        for (let req in unrolled_reqs.concat(incls)) {
            if (self._cmd.find_group(req) != null) {
                let group_members = self._cmd.unroll_args_in_group(req);
                let is_present = if let m: ArgMatcher = matcher {
                    group_members.some((arg) -> { m.check_explicit(arg, ArgPredicateIsPresent {}) })
                } else {
                    false
                };
                if (is_present) {
                    continue;
                }

                let elem = self._cmd.format_group(req);
                required_groups.insert(elem);
                required_groups_members.extend(group_members);
            }
        }

        let required_opts: FlatSet<StyledStr> = FlatSet.new();
        let required_positionals: (StyledStr | null)[] = [];
        for (let req in unrolled_reqs.concat(incls)) {
            if let arg: Arg = self._cmd.find(req) {
                if (required_groups_members.contains(arg.get_id())) {
                    continue;
                }

                let is_present = if let m: ArgMatcher = matcher { m.check_explicit(req, ArgPredicateIsPresent {}) } else { false };
                if (is_present) {
                    continue;
                }

                let stylized = arg.stylized(self._styles, true);
                if let index: int = arg.get_index() {
                    if (!arg.is_last_set() || incl_last) {
                        while (required_positionals.length() < index + 1) {
                            required_positionals.push(null);
                        }
                        required_positionals[index] = stylized;
                    }
                } else {
                    required_opts.insert(stylized);
                }
            }
        }

        let ret_val: StyledStr[] = [];
        for (let o in required_opts.into_vec()) { ret_val.push(o); }
        for (let g in required_groups.into_vec()) { ret_val.push(g); }
        for (let p in required_positionals) {
            if let pos: StyledStr = p { ret_val.push(pos); }
        }
        ret_val
    }
}
