// Port of clap_builder/src/builder/debug_asserts.rs
//
// Rust only compiles these checks with `debug_assertions`; they catch
// programming mistakes in a `Command` definition. The port always runs them
// (panicking via `baml.sys.panic`), matching a debug build.

function assert_app(cmd: Command) -> void {
    let short_flags: Flag[] = [];
    let long_flags: Flag[] = [];

    // Invalid version flag settings
    if (cmd.get_version() == null && cmd.get_long_version() == null) {
        // PropagateVersion is meaningless if there is no version
        if (cmd.is_propagate_version_set()) {
            baml.sys.panic(`Command ${cmd.get_name()}: No version information via Command::version or Command::long_version to propagate`);
        }

        // Used `Command::mut_arg("version", ..) but did not provide any version information to display
        let version_needed = cmd.get_arguments()
            .filter((x) -> { x.get_action() == ArgAction.Version })
            .map((x) -> { x.get_id() });

        if (version_needed.length() > 0) {
            baml.sys.panic(`Command ${cmd.get_name()}: \`ArgAction::Version\` used without providing Command::version or Command::long_version`);
        }
    }

    for (let sc in cmd.get_subcommands()) {
        if let s: string = sc.get_short_flag() {
            short_flags.push(Flag { is_command: true, flag: `-${s}`, owner: sc.get_name() });
        }

        for (let short_alias in sc.get_all_short_flag_aliases()) {
            short_flags.push(Flag { is_command: true, flag: `-${short_alias}`, owner: sc.get_name() });
        }

        if let l: string = sc.get_long_flag() {
            if (l.starts_with("-")) {
                baml.sys.panic(`Command ${sc.get_name()}: long_flag ${debug_str(l)} must not start with a \`-\`, that will be handled by the parser`);
            }
            long_flags.push(Flag { is_command: true, flag: `--${l}`, owner: sc.get_name() });
        }

        for (let long_alias in sc.get_all_long_flag_aliases()) {
            long_flags.push(Flag { is_command: true, flag: `--${long_alias}`, owner: sc.get_name() });
        }
    }

    for (let arg in cmd.get_arguments()) {
        assert_arg(arg);

        if (cmd.is_multicall_set()) {
            baml.sys.panic(`Command ${cmd.get_name()}: Arguments like ${arg.get_id()} cannot be set on a multicall command`);
        }

        if let s: string = arg.get_short() {
            short_flags.push(Flag { is_command: false, flag: `-${s}`, owner: arg.get_id() });
        }

        for (let short_alias in arg._short_aliases) {
            short_flags.push(Flag { is_command: false, flag: `-${short_alias.name}`, owner: arg.get_id() });
        }

        if let l: string = arg.get_long() {
            if (l.starts_with("-")) {
                baml.sys.panic(`Argument ${arg.get_id()}: long ${debug_str(l)} must not start with a \`-\`, that will be handled by the parser`);
            }
            long_flags.push(Flag { is_command: false, flag: `--${l}`, owner: arg.get_id() });
        }

        for (let long_alias in arg._aliases) {
            long_flags.push(Flag { is_command: false, flag: `--${long_alias.name}`, owner: arg.get_id() });
        }

        // Name conflicts
        if let pair: Arg[] = cmd.two_args_of((x) -> { x.get_id() == arg.get_id() }) {
            baml.sys.panic(`Command ${cmd.get_name()}: Argument names must be unique, but '${arg.get_id()}' is in use by more than one argument or group${duplicate_tip(cmd, pair[0], pair[1])}`);
        }

        // Long conflicts
        if let l: string = arg.get_long() {
            if let pair: Arg[] = cmd.two_args_of((x) -> { x.get_long() == l }) {
                baml.sys.panic(`Command ${cmd.get_name()}: Long option names must be unique for each argument, but '--${l}' is in use by both '${pair[0].get_id()}' and '${pair[1].get_id()}'${duplicate_tip(cmd, pair[0], pair[1])}`);
            }
        }

        // Short conflicts
        if let s: string = arg.get_short() {
            if let pair: Arg[] = cmd.two_args_of((x) -> { x.get_short() == s }) {
                baml.sys.panic(`Command ${cmd.get_name()}: Short option names must be unique for each argument, but '-${s}' is in use by both '${pair[0].get_id()}' and '${pair[1].get_id()}'${duplicate_tip(cmd, pair[0], pair[1])}`);
            }
        }

        // Index conflicts
        if let idx: int = arg._index {
            if let pair: Arg[] = cmd.two_args_of((x) -> { x.is_positional() && x.get_index() == idx }) {
                baml.sys.panic(`Command ${cmd.get_name()}: Argument '${pair[0].get_id()}' has the same index as '${pair[1].get_id()}' and they are both positional arguments\n\n\t Use \`Arg::num_args(1..)\` to allow one positional argument to take multiple values`);
            }
        }

        // requires, r_if, r_unless
        for (let r in arg._requires) {
            if (arg._id == r.id) {
                baml.sys.panic(`Argument ${arg.get_id()} cannot require itself`);
            }
            if (!cmd.id_exists(r.id)) {
                baml.sys.panic(`Command ${cmd.get_name()}: Argument or group '${r.id}' specified in 'requires*' for '${arg.get_id()}' does not exist`);
            }
        }

        for (let req in arg._r_ifs) {
            if (arg.is_required_set()) {
                baml.sys.panic(`Argument ${arg.get_id()}: \`required\` conflicts with \`required_if_eq*\``);
            }
            if (!cmd.id_exists(req.id)) {
                baml.sys.panic(`Command ${cmd.get_name()}: Argument or group '${req.id}' specified in 'required_if_eq*' for '${arg.get_id()}' does not exist`);
            }
        }

        for (let req in arg._r_ifs_all) {
            if (arg.is_required_set()) {
                baml.sys.panic(`Argument ${arg.get_id()}: \`required\` conflicts with \`required_if_eq_all\``);
            }
            if (!cmd.id_exists(req.id)) {
                baml.sys.panic(`Command ${cmd.get_name()}: Argument or group '${req.id}' specified in 'required_if_eq_all' for '${arg.get_id()}' does not exist`);
            }
        }

        for (let req in arg._r_unless) {
            if (arg.is_required_set()) {
                baml.sys.panic(`Argument ${arg.get_id()}: \`required\` conflicts with \`required_unless*\``);
            }
            if (!cmd.id_exists(req)) {
                baml.sys.panic(`Command ${cmd.get_name()}: Argument or group '${req}' specified in 'required_unless*' for '${arg.get_id()}' does not exist`);
            }
        }

        for (let req in arg._r_unless_all) {
            if (arg.is_required_set()) {
                baml.sys.panic(`Argument ${arg.get_id()}: \`required\` conflicts with \`required_unless*\``);
            }
            if (!cmd.id_exists(req)) {
                baml.sys.panic(`Command ${cmd.get_name()}: Argument or group '${req}' specified in 'required_unless*' for '${arg.get_id()}' does not exist`);
            }
        }

        // blacklist
        for (let req in arg._blacklist) {
            if (!cmd.id_exists(req)) {
                baml.sys.panic(`Command ${cmd.get_name()}: Argument or group '${req}' specified in 'conflicts_with*' for '${arg.get_id()}' does not exist`);
            }
        }

        // overrides
        for (let req in arg._overrides) {
            if (!cmd.id_exists(req)) {
                baml.sys.panic(`Command ${cmd.get_name()}: Argument or group '${req}' specified in 'overrides_with*' for '${arg.get_id()}' does not exist`);
            }
        }

        if (arg.is_last_set()) {
            if (arg.get_long() != null) {
                baml.sys.panic(`Command ${cmd.get_name()}: Flags or Options cannot have last(true) set. '${arg.get_id()}' has both a long and last(true) set.`);
            }
            if (arg.get_short() != null) {
                baml.sys.panic(`Command ${cmd.get_name()}: Flags or Options cannot have last(true) set. '${arg.get_id()}' has both a short and last(true) set.`);
            }
        }

        if (arg.is_required_set() && arg.is_global_set()) {
            baml.sys.panic(`Command ${cmd.get_name()}: Global arguments cannot be required.\n\n\t'${arg.get_id()}' is marked as both global and required`);
        }

        if (arg.get_value_hint() == ValueHint.CommandWithArguments) {
            if (!arg.is_positional()) {
                baml.sys.panic(`Command ${cmd.get_name()}: Argument '${arg.get_id()}' has hint CommandWithArguments and must be positional.`);
            }

            if (!(arg.is_trailing_var_arg_set() || arg.is_last_set())) {
                baml.sys.panic(`Command ${cmd.get_name()}: Positional argument '${arg.get_id()}' has hint CommandWithArguments, so Command must have \`trailing_var_arg(true)\` or \`last(true)\` set.`);
            }
        }
    }

    for (let group in cmd.get_groups()) {
        // Name conflicts
        if (cmd.get_groups().filter((x) -> { x._id == group._id }).length() >= 2) {
            baml.sys.panic(`Command ${cmd.get_name()}: Argument group name must be unique\n\n\t'${group.get_id()}' is already in use`);
        }

        // Groups should not have naming conflicts with Args
        if (cmd.get_arguments().some((x) -> { x.get_id() == group.get_id() })) {
            baml.sys.panic(`Command ${cmd.get_name()}: Argument group name '${group.get_id()}' must not conflict with argument name`);
        }

        for (let a in group._args) {
            // Args listed inside groups should exist
            if (!cmd.get_arguments().some((x) -> { x.get_id() == a })) {
                baml.sys.panic(`Command ${cmd.get_name()}: Argument group '${group.get_id()}' contains non-existent argument '${a}'`);
            }
        }

        for (let a in group._requires) {
            // Args listed inside groups should exist
            if (!cmd.id_exists(a)) {
                baml.sys.panic(`Command ${cmd.get_name()}: Argument group '${group.get_id()}' requires non-existent '${a}' id`);
            }
        }

        for (let a in group._conflicts) {
            // Args listed inside groups should exist
            if (!cmd.id_exists(a)) {
                baml.sys.panic(`Command ${cmd.get_name()}: Argument group '${group.get_id()}' conflicts with non-existent '${a}' id`);
            }
        }
    }

    // Conflicts between flags and subcommands

    let sorted_long = long_flags.sort_by((a, b) -> { a.flag.cmp(b.flag) });
    let sorted_short = short_flags.sort_by((a, b) -> { a.flag.cmp(b.flag) });

    detect_duplicate_flags(sorted_long, "long");
    detect_duplicate_flags(sorted_short, "short");

    let subs: FlatSet<string> = FlatSet.new();
    for (let sc in cmd.get_subcommands()) {
        if (!subs.insert(sc.get_name())) {
            baml.sys.panic(`Command ${cmd.get_name()}: command name \`${sc.get_name()}\` is duplicated`);
        }
        for (let alias in sc.get_all_aliases()) {
            if (!subs.insert(alias)) {
                baml.sys.panic(`Command ${cmd.get_name()}: command \`${sc.get_name()}\` alias \`${alias}\` is duplicated`);
            }
        }
    }

    _verify_positionals(cmd);

    if (features().help) {
        if let help_template: StyledStr = cmd.get_help_template() {
            if (help_template.to_string().includes("{flags}")) {
                baml.sys.panic(`Command ${cmd.get_name()}: \`{flags}\` template variable was removed in clap3, they are now included in \`{options}\``);
            }

            if (help_template.to_string().includes("{unified}")) {
                baml.sys.panic(`Command ${cmd.get_name()}: \`{unified}\` template variable was removed in clap3, use \`{options}\` instead`);
            }

            if (features().unstable_v5 && help_template.to_string().includes("{bin}")) {
                baml.sys.panic(`Command ${cmd.get_name()}: \`{bin}\` template variable was removed in clap5, use \`{name}\` instead`);
            }
        }
    }

    cmd._panic_on_missing_help(cmd.is_help_expected_set());
    assert_app_flags(cmd);
}

function duplicate_tip(cmd: Command, first: Arg, second: Arg) -> string {
    if (!cmd.is_disable_help_flag_set()
        && (first.get_id() == ID_HELP() || second.get_id() == ID_HELP())) {
        " (call `cmd.disable_help_flag(true)` to remove the auto-generated `--help`)"
    } else if (!cmd.is_disable_version_flag_set()
        && (first.get_id() == ID_VERSION() || second.get_id() == ID_VERSION())) {
        " (call `cmd.disable_version_flag(true)` to remove the auto-generated `--version`)"
    } else {
        ""
    }
}

/// `enum Flag<'a> { Command(String, &'a str), Arg(String, &'a str) }`
class Flag {
    is_command: bool,
    flag: string,
    owner: string,
}


function detect_duplicate_flags(flags: Flag[], short_or_long: string) -> void {
    for (let i in baml.iter.Range.new(1, flags.length())) {
        let a = flags[i - 1];
        let b = flags[i];
        if (a.flag != b.flag) {
            continue;
        }
        if (a.is_command && b.is_command && a.owner != b.owner) {
            baml.sys.panic(`the '${a.flag}' ${short_or_long} flag is specified for both '${a.owner}' and '${b.owner}' subcommands`);
        } else if (!a.is_command && !b.is_command && a.owner != b.owner) {
            baml.sys.panic(`${short_or_long} option names must be unique, but '${a.flag}' is in use by both '${a.owner}' and '${b.owner}'`);
        } else if (a.is_command != b.is_command) {
            let arg = if (a.is_command) { b.owner } else { a.owner };
            let sub = if (a.is_command) { a.owner } else { b.owner };
            baml.sys.panic(`the '${a.flag}' ${short_or_long} flag for the '${arg}' argument conflicts with the short flag for '${sub}' subcommand`);
        }
    }
}

function assert_app_flags(cmd: Command) -> void {
    if (cmd.is_multicall_set()) {
        let s = "";
        if (cmd.is_no_binary_name_set()) {
            s = s + "  AppSettings::is_no_binary_name_set conflicts with AppSettings::is_multicall_set.\n";
        }
        if (!s.is_empty()) {
            baml.sys.panic(`${cmd.get_name()}\n${s}`);
        }
    }
}

function _verify_positionals(cmd: Command) -> bool {
    // Because you must wait until all arguments have been supplied, this is the first chance
    // to make assertions on positional argument indexes
    //
    // First we verify that the index highest supplied index, is equal to the number of
    // positional arguments to verify there are no gaps (i.e. supplying an index of 1 and 3
    // but no 2)

    let positions = cmd.get_keymap().keys().filter_map((x) -> {
        match (x) {
            let p: KeyPosition => p.n,
            _ => null,
        }
    });
    let highest_idx = positions.reduce((acc, n) -> { if (n > acc) { n } else { acc } }, 0);

    let num_p = positions.length();

    if (highest_idx != num_p) {
        baml.sys.panic(`Found positional argument whose index is ${highest_idx} but there are only ${num_p} positional arguments defined`);
    }

    for (let arg in cmd.get_arguments()) {
        if ((arg._index ?? 0) == highest_idx) {
            if (arg.is_trailing_var_arg_set() && arg.is_last_set()) {
                baml.sys.panic(`${cmd.get_name()}:${arg.get_id()}: \`Arg::trailing_var_arg\` and \`Arg::last\` cannot be used together`);
            }

            if (arg.is_trailing_var_arg_set()) {
                if (!arg.is_multiple()) {
                    baml.sys.panic(`${cmd.get_name()}:${arg.get_id()}: \`Arg::trailing_var_arg\` must accept multiple values`);
                }
            }
        } else {
            if (arg.is_trailing_var_arg_set()) {
                baml.sys.panic(`${cmd.get_name()}:${arg.get_id()}: \`Arg::trailing_var_arg\` can only apply to last positional`);
            }
        }
    }

    // Next we verify that only the highest index has takes multiple arguments (if any)
    let only_highest = (a: Arg) -> bool { a.is_multiple() && ((a.get_index() ?? 0) != highest_idx) };
    if (cmd.get_positionals().some(only_highest)) {
        // First we make sure if there is a positional that allows multiple values
        // the one before it (second to last) has one of these:
        //  * a value terminator
        //  * ArgSettings::Last
        //  * The last arg is Required

        // We can't pass the closure (it.next()) to the macro directly because each call to
        // find() (iterator, not macro) gets called repeatedly.
        let last = cmd.get_keymap().get_position(highest_idx) ?? baml.sys.panic(INTERNAL_ERROR_MSG());
        let second_to_last = cmd.get_keymap().get_position(highest_idx - 1) ?? baml.sys.panic(INTERNAL_ERROR_MSG());

        // Either the final positional is required
        // Or the second to last has a terminator or .last(true) set
        let ok = last.is_required_set()
            || (second_to_last._terminator != null || second_to_last.is_last_set())
            || last.is_last_set();
        if (!ok) {
            baml.sys.panic(`Positional argument \`${last}\` *must* have \`required(true)\` or \`last(true)\` set because a prior positional argument (\`${second_to_last}\`) has \`num_args(1..)\``);
        }

        // We make sure if the second to last is Multiple the last is ArgSettings::Last
        let ok2 = second_to_last.is_multiple() || last.is_last_set();
        if (!ok2) {
            baml.sys.panic("Only the last positional argument, or second to last positional argument may be set to `.num_args(1..)`");
        }

        // Next we check how many have both Multiple and not a specific number of values set
        let count = cmd.get_positionals()
            .filter((p) -> {
                p.is_multiple_values_set()
                    && p.get_value_terminator() == null
                    && !(p.get_num_args() ?? ValueRange.SINGLE()).is_fixed()
            })
            .length();
        let ok3 = count <= 1
            || (last.is_last_set()
                && last.is_multiple()
                && second_to_last.is_multiple()
                && count == 2);
        if (!ok3) {
            baml.sys.panic("Only one positional argument with `.num_args(1..)` set is allowed per command, unless the second one also has .last(true) set");
        }
    }

    let found = false;

    if (cmd.is_allow_missing_positional_set()) {
        // Check that if a required positional argument is found, all positions with a lower
        // index are also required.
        let foundx2 = false;

        for (let p in cmd.get_positionals()) {
            if (foundx2 && !p.is_required_set()) {
                baml.sys.panic(`Found non-required positional argument with a lower index than a required positional argument by two or more: ${debug_str(p.get_id())} index ${debug_opt_int(p.get_index())}`);
            } else if (p.is_required_set() && !p.is_last_set()) {
                // Args that .last(true) don't count since they can be required and have
                // positionals with a lower index that aren't required
                // Imagine: prog <req1> [opt1] -- <req2>
                // Both of these are valid invocations:
                //      $ prog r1 -- r2
                //      $ prog r1 o1 -- r2
                if (found) {
                    foundx2 = true;
                    continue;
                }
                found = true;
            } else {
                found = false;
            }
        }
    } else {
        // Check that if a required positional argument is found, all positions with a lower
        // index are also required
        let n = num_p;
        while (n >= 1) {
            if let p: Arg = cmd.get_keymap().get_position(n) {
                if (found) {
                    if (!p.is_required_set()) {
                        baml.sys.panic(`Found non-required positional argument with a lower index than a required positional argument: ${debug_str(p.get_id())} index ${debug_opt_int(p.get_index())}`);
                    }
                } else if (p.is_required_set() && !p.is_last_set()) {
                    // Args that .last(true) don't count since they can be required and have
                    // positionals with a lower index that aren't required
                    // Imagine: prog <req1> [opt1] -- <req2>
                    // Both of these are valid invocations:
                    //      $ prog r1 -- r2
                    //      $ prog r1 o1 -- r2
                    found = true;
                }
            }
            n -= 1;
        }
    }
    if (cmd.get_positionals().filter((p) -> { p.is_last_set() }).length() >= 2) {
        baml.sys.panic("Only one positional argument may have last(true) set. Found two.");
    }
    if (cmd.get_positionals().some((p) -> { p.is_last_set() && p.is_required_set() })
        && cmd.has_subcommands()
        && !cmd.is_subcommand_negates_reqs_set()) {
        baml.sys.panic("Having a required positional argument with .last(true) set *and* child subcommands without setting SubcommandsNegateReqs isn't compatible.");
    }

    true
}

function debug_opt_int(v: int?) -> string {
    if let x: int = v { `Some(${x})` } else { "None" }
}

function assert_arg(arg: Arg) -> void {
    // Self conflict
    // TODO: this check should be recursive
    if (arg._blacklist.some((x) -> { x == arg.get_id() })) {
        baml.sys.panic(`Argument '${arg.get_id()}' cannot conflict with itself`);
    }

    let nargs = arg.get_num_args() ?? ValueRange.new(1);
    if (nargs.max_values() > action_max_num_args(arg.get_action()).max_values()) {
        baml.sys.panic(`Argument \`${arg.get_id()}\`'s action ${arg.get_action()} is incompatible with \`num_args(${nargs})\``);
    }
    if let action_type_id: AnyValueId = action_value_type_id(arg.get_action()) {
        if (action_type_id != arg.get_value_parser().type_id()) {
            baml.sys.panic(`Argument \`${arg.get_id()}\`'s selected action ${arg.get_action()} contradicts \`value_parser\` (${arg.get_value_parser().debug()})`);
        }
    }

    if (arg.get_value_hint() != ValueHint.Unknown) {
        if (!arg.is_takes_value_set()) {
            baml.sys.panic(`Argument '${arg.get_id()}' has value hint but takes no value`);
        }

        if (arg.get_value_hint() == ValueHint.CommandWithArguments) {
            if (!arg.is_multiple_values_set()) {
                baml.sys.panic(`Argument '${arg.get_id()}' uses hint CommandWithArguments and must accept multiple values`);
            }
        }
    }

    if (arg._index != null) {
        if (!arg.is_positional()) {
            baml.sys.panic(`Argument '${arg.get_id()}' is a positional argument and can't have short or long name versions`);
        }
        if (!arg.is_takes_value_set()) {
            let suffix = if (arg.get_id() == ID_HELP()) {
                " (`mut_arg` no longer works with implicit `--help`)"
            } else if (arg.get_id() == ID_VERSION()) {
                " (`mut_arg` no longer works with implicit `--version`)"
            } else {
                ""
            };
            baml.sys.panic(`Argument '${arg.get_id()}' is positional and it must take a value but action is ${arg.get_action()}${suffix}`);
        }
    }

    let num_vals = arg.get_num_args() ?? baml.sys.panic(INTERNAL_ERROR_MSG());
    // This can be the cause of later asserts, so put this first
    if (num_vals != ValueRange.EMPTY()) {
        // HACK: Don't check for flags to make the derive easier
        let num_val_names = (arg.get_value_names() ?? []).length();
        if (num_vals.max_values() < num_val_names) {
            baml.sys.panic(`Argument ${arg.get_id()}: Too many value names (${num_val_names}) compared to \`num_args\` (${num_vals})`);
        }
    }

    if (num_vals.is_multiple() != arg.is_multiple_values_set()) {
        baml.sys.panic(`Argument ${arg.get_id()}: mismatch between \`num_args\` (${num_vals}) and \`multiple_values\``);
    }

    if (1 < num_vals.min_values()) {
        if (arg.is_require_equals_set()) {
            baml.sys.panic(`Argument ${arg.get_id()}: cannot accept more than 1 arg (num_args=${num_vals}) with require_equals`);
        }
    }

    if (num_vals == ValueRange.SINGLE()) {
        if (arg.is_multiple_values_set()) {
            baml.sys.panic(`Argument ${arg.get_id()}: mismatch between \`num_args\` and \`multiple_values\``);
        }
    }

    assert_arg_flags(arg);
}

function assert_arg_flags(arg: Arg) -> void {
    let s = "";
    if (!arg.is_takes_value_set()) {
        let checks: string[] = [];
        if (arg.is_hide_possible_values_set()) { checks.push("is_hide_possible_values_set"); }
        if (arg.is_allow_hyphen_values_set()) { checks.push("is_allow_hyphen_values_set"); }
        if (arg.is_allow_negative_numbers_set()) { checks.push("is_allow_negative_numbers_set"); }
        if (arg.is_require_equals_set()) { checks.push("is_require_equals_set"); }
        if (arg.is_last_set()) { checks.push("is_last_set"); }
        if (arg.is_hide_default_value_set()) { checks.push("is_hide_default_value_set"); }
        if (arg.is_multiple_values_set()) { checks.push("is_multiple_values_set"); }
        if (arg.is_ignore_case_set()) { checks.push("is_ignore_case_set"); }
        if let first: string = checks.at(0) {
            s = `  Arg::is_takes_value_set is required when Arg::${first} is set.\n`;
        }
    }
    if (!s.is_empty()) {
        baml.sys.panic(`Argument ${debug_str(arg.get_id())}\n${s}`);
    }
}
