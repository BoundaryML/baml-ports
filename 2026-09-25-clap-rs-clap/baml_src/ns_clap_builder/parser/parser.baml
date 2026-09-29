// Port of clap_builder/src/parser/parser.rs
//
// Rust's `pub(crate) struct Parser` is `CmdParser` here (see `parser/mod.baml`).

enum ParseStateKind {
    ValuesDone,
    Opt,
    Pos,
}

/// `enum ParseState { ValuesDone, Opt(Id), Pos(Id) }`
class ParseState {
    kind: ParseStateKind,
    id: Id,
}

function parse_state_values_done() -> ParseState { ParseState { kind: ParseStateKind.ValuesDone, id: "" } }
function parse_state_opt(id: Id) -> ParseState { ParseState { kind: ParseStateKind.Opt, id: id } }
function parse_state_pos(id: Id) -> ParseState { ParseState { kind: ParseStateKind.Pos, id: id } }

enum ParseResultKind {
    FlagSubCommand,
    Opt,
    ValuesDone,
    AttachedValueNotConsumed,
    /// This long flag doesn't need a value but is provided one.
    UnneededAttachedValue,
    MaybeHyphenValue,
    EqualsNotProvided,
    /// Failed to match a Arg.
    NoMatchingArg,
    /// No argument found e.g. parser is given `-` when parsing a flag.
    NoArg,
}

/// `enum ParseResult`: variants carry `name` (FlagSubCommand, Opt), `rest`/`used`/`arg`
/// (UnneededAttachedValue), or `arg` (EqualsNotProvided, NoMatchingArg)
class ParseResult {
    kind: ParseResultKind,
    name: string,
    rest: string,
    used: Id[],
    arg: string,
}

function parse_result(kind: ParseResultKind) -> ParseResult {
    ParseResult { kind: kind, name: "", rest: "", used: [], arg: "" }
}

function parse_result_named(kind: ParseResultKind, name: string) -> ParseResult {
    ParseResult { kind: kind, name: name, rest: "", used: [], arg: "" }
}

function parse_result_arg(kind: ParseResultKind, arg: string) -> ParseResult {
    ParseResult { kind: kind, name: "", rest: "", used: [], arg: arg }
}

class PendingArg {
    id: Id,
    ident: Identifier?,
    raw_vals: OsString[],
    trailing_idx: int?,
}

enum Identifier {
    Short,
    Long,
    Index,
}

class CmdParser {
    _cmd: Command,
    /// Index of the previous flag subcommand in a group of flags.
    _cur_idx: int,
    /// Index of the previous flag subcommand in a group of flags.
    _flag_subcmd_at: int?,
    /// Counter indicating the number of items to skip
    /// when revisiting the group of flags which includes the flag subcommand.
    _flag_subcmd_skip: int,

    // ===== Initializing Methods =====

    function new(cmd: Command) -> CmdParser {
        CmdParser { _cmd: cmd, _cur_idx: 0, _flag_subcmd_at: null, _flag_subcmd_skip: 0 }
    }

    // ===== Parsing Methods =====

    // The actual parsing function
    function get_matches_with(self, matcher: ArgMatcher, raw_args: root.clap_lex.RawArgs, args_cursor: root.clap_lex.ArgCursor) -> void throws Error {
        self.parse(matcher, raw_args, args_cursor) catch (e) {
            let err: Error => {
                if (self._cmd.is_ignore_errors_set()) {
                    if (features().env) {
                        self.add_env(matcher) catch_all (e2) { _ => null };
                    }
                    self.add_defaults(matcher) catch_all (e3) { _ => null };
                }
                throw err;
            },
        };
        self.resolve_pending(matcher);

        if (features().env) {
            self.add_env(matcher);
        }
        self.add_defaults(matcher);
        Validator.new(self._cmd).validate(matcher)
    }

    // The actual parsing function
    function parse(self, matcher: ArgMatcher, raw_args: root.clap_lex.RawArgs, args_cursor: root.clap_lex.ArgCursor) -> void throws Error {
        // Verify all positional assertions pass

        let subcmd_name: string? = null;
        let keep_state = false;
        let parse_state = parse_state_values_done();
        let pos_counter = 1;

        // Already met any valid arg(then we shouldn't expect subcommands after it).
        let valid_arg_found = false;
        // If the user already passed '--'. Meaning only positional args follow.
        let trailing_values = false;

        // Count of positional args
        let positional_count = self._cmd.get_keymap().keys().filter((x) -> { key_is_position(x) }).length();
        // If any arg sets .last(true)
        let contains_last = self._cmd.get_arguments().some((x) -> { x.is_last_set() });

        while let arg_os: root.clap_lex.ParsedArg = raw_args.next(args_cursor) {
            // Has the user already passed '--'? Meaning only positional args follow
            if (!trailing_values) {
                if (self._cmd.is_subcommand_precedence_over_arg_set()
                    || !(parse_state.kind == ParseStateKind.Opt || parse_state.kind == ParseStateKind.Pos)) {
                    // Does the arg match a subcommand name, or any of its aliases (if defined)
                    let sc_name = self.possible_subcommand(arg_os.to_value(), valid_arg_found);
                    if let name: string = sc_name {
                        if (name == "help" && !self._cmd.is_disable_help_subcommand_set()) {
                            self.parse_help_subcommand(raw_args.remaining(args_cursor));
                            baml.sys.panic("`parse_help_subcommand` always errors");
                        } else {
                            subcmd_name = name;
                        }
                        break;
                    }
                }

                let handled = false;
                if (arg_os.is_escape()) {
                    if ((parse_state.kind == ParseStateKind.Opt || parse_state.kind == ParseStateKind.Pos)
                        && command_index(self._cmd, parse_state.id).is_allow_hyphen_values_set()) {
                        // ParseResult::MaybeHyphenValue, do nothing
                    } else {
                        let pos_arg = self._cmd.get_keymap().get_position(pos_counter);
                        if let pa: Arg = pos_arg {
                            if (self.check_terminator(pa, arg_os.to_value_os()) != null) {
                                // count as both an escape and terminator
                                pos_counter += 1;
                            }
                        }
                        trailing_values = true;
                        matcher.start_trailing();
                        continue;
                    }
                } else if let long: root.clap_lex.LongFlag = arg_os.to_long() {
                    let vaf = ValidArgFound { value: valid_arg_found };
                    let parse_result = self.parse_long_arg(
                        matcher,
                        long.flag,
                        long.value,
                        parse_state,
                        pos_counter,
                        vaf,
                    );
                    valid_arg_found = vaf.value;
                    match (parse_result.kind) {
                        ParseResultKind.NoArg => {
                            baml.sys.panic("`to_long` always has the flag specified");
                        },
                        ParseResultKind.ValuesDone => {
                            parse_state = parse_state_values_done();
                            continue;
                        },
                        ParseResultKind.Opt => {
                            parse_state = parse_state_opt(parse_result.name);
                            continue;
                        },
                        ParseResultKind.FlagSubCommand => {
                            subcmd_name = parse_result.name;
                            break;
                        },
                        ParseResultKind.EqualsNotProvided => {
                            self.resolve_pending(matcher) catch_all (e) { _ => null };
                            throw error_no_equals(
                                self._cmd,
                                parse_result.arg,
                                Usage.new(self._cmd).create_usage_with_title([]),
                            );
                        },
                        ParseResultKind.NoMatchingArg => {
                            self.resolve_pending(matcher) catch_all (e) { _ => null };
                            let remaining_args = raw_args.remaining(args_cursor);
                            throw self.did_you_mean_error(
                                parse_result.arg,
                                matcher,
                                remaining_args,
                                trailing_values,
                            );
                        },
                        ParseResultKind.UnneededAttachedValue => {
                            self.resolve_pending(matcher) catch_all (e) { _ => null };
                            throw error_too_many_values(
                                self._cmd,
                                parse_result.rest,
                                parse_result.arg,
                                Usage.new(self._cmd).create_usage_with_title(parse_result.used),
                            );
                        },
                        ParseResultKind.MaybeHyphenValue => {
                            // Maybe a hyphen value, do nothing.
                        },
                        ParseResultKind.AttachedValueNotConsumed => {
                            baml.sys.panic("unreachable");
                        },
                    }
                } else if let short_arg: root.clap_lex.ShortFlags = arg_os.to_short() {
                    // Arg looks like a short flag, and not a possible number

                    // Try to parse short args like normal, if allow_hyphen_values or
                    // AllowNegativeNumbers is set, parse_short_arg will *not* throw
                    // an error, and instead return Ok(None)
                    let vaf = ValidArgFound { value: valid_arg_found };
                    let parse_result = self.parse_short_arg(
                        matcher,
                        short_arg,
                        parse_state,
                        pos_counter,
                        vaf,
                    );
                    valid_arg_found = vaf.value;
                    // If it's None, we then check if one of those two AppSettings was set
                    match (parse_result.kind) {
                        ParseResultKind.NoArg => {
                            // Is a single dash `-`, try positional.
                        },
                        ParseResultKind.ValuesDone => {
                            parse_state = parse_state_values_done();
                            continue;
                        },
                        ParseResultKind.Opt => {
                            parse_state = parse_state_opt(parse_result.name);
                            continue;
                        },
                        ParseResultKind.FlagSubCommand => {
                            // If there are more short flags to be processed, we should keep the state, and later
                            // revisit the current group of short flags skipping the subcommand.
                            keep_state = false;
                            if let at: int = self._flag_subcmd_at {
                                raw_args.seek(args_cursor, root.clap_lex.SeekFromCurrent { pos: -1 });
                                // Since we are now saving the current state, the number of flags to skip during state recovery should
                                // be the current index (`cur_idx`) minus ONE UNIT TO THE LEFT of the starting position.
                                self._flag_subcmd_skip = self._cur_idx - at + 1;
                                keep_state = true;
                            }

                            subcmd_name = parse_result.name;
                            break;
                        },
                        ParseResultKind.EqualsNotProvided => {
                            self.resolve_pending(matcher) catch_all (e) { _ => null };
                            throw error_no_equals(
                                self._cmd,
                                parse_result.arg,
                                Usage.new(self._cmd).create_usage_with_title([]),
                            );
                        },
                        ParseResultKind.NoMatchingArg => {
                            self.resolve_pending(matcher) catch_all (e) { _ => null };
                            // We already know it looks like a flag
                            let suggested_trailing_arg = !trailing_values && self._cmd.has_positionals();
                            throw error_unknown_argument(
                                self._cmd,
                                parse_result.arg,
                                null,
                                suggested_trailing_arg,
                                Usage.new(self._cmd).create_usage_with_title([]),
                            );
                        },
                        ParseResultKind.MaybeHyphenValue => {
                            // Maybe a hyphen value, do nothing.
                        },
                        _ => {
                            baml.sys.panic("unreachable");
                        },
                    }
                }

                if (parse_state.kind == ParseStateKind.Opt) {
                    let id = parse_state.id;
                    // Assume this is a value of a previous arg.

                    // get the option so we can check the settings
                    let arg = command_index(self._cmd, id);
                    let pr = self.check_terminator(arg, arg_os.to_value_os());
                    let next_state = if let r: ParseResult = pr {
                        r
                    } else {
                        let tv = false;
                        let arg_values = matcher.pending_values_mut(id, null, tv);
                        arg_values.push(arg_os.to_value_os());
                        if (matcher.needs_more_vals(arg)) {
                            parse_result_named(ParseResultKind.Opt, arg.get_id())
                        } else {
                            parse_result(ParseResultKind.ValuesDone)
                        }
                    };
                    parse_state = match (next_state.kind) {
                        ParseResultKind.Opt => parse_state_opt(next_state.name),
                        ParseResultKind.ValuesDone => parse_state_values_done(),
                        _ => baml.sys.panic("unreachable"),
                    };
                    // get the next value from the iterator
                    continue;
                }
            }

            // Correct pos_counter.
            pos_counter = {
                let is_second_to_last = pos_counter + 1 == positional_count;

                // The last positional argument, or second to last positional
                // argument may be set to .multiple_values(true) or `.multiple_occurrences(true)`
                let positionals = self._cmd.get_positionals();
                let low_index_mults = is_second_to_last
                    && positionals.some((a) -> { a.is_multiple() && (positional_count != (a.get_index() ?? 0)) })
                    && (if let p_name: Arg = positionals.at(-1) { !p_name.is_last_set() } else { false });

                let is_terminated = if let a: Arg = self._cmd.get_keymap().get_position(pos_counter) {
                    a.get_value_terminator() != null
                } else {
                    false
                };

                let missing_pos = self._cmd.is_allow_missing_positional_set()
                    && is_second_to_last
                    && !trailing_values;

                if ((low_index_mults || missing_pos) && !is_terminated) {
                    let skip_current = if let n: root.clap_lex.ParsedArg = raw_args.peek(args_cursor) {
                        let pc = pos_counter;
                        if let arg: Arg = positionals.find((a) -> { a.get_index() == pc }) {
                            // If next value looks like a new_arg or it's a
                            // subcommand, skip positional argument under current
                            // pos_counter(which means current value cannot be a
                            // positional argument with a value next to it), assume
                            // current value matches the next arg.
                            self.is_new_arg(n, arg)
                                || self.possible_subcommand(n.to_value(), valid_arg_found) != null
                        } else {
                            true
                        }
                    } else {
                        true
                    };

                    if (skip_current) {
                        pos_counter + 1
                    } else {
                        pos_counter
                    }
                } else if (trailing_values
                    && (self._cmd.is_allow_missing_positional_set() || contains_last)) {
                    // Came to -- and one positional has .last(true) set, so we go immediately
                    // to the last (highest index) positional
                    positional_count
                } else {
                    pos_counter
                }
            };

            if let arg: Arg = self._cmd.get_keymap().get_position(pos_counter) {
                if (arg.is_last_set() && !trailing_values) {
                    self.resolve_pending(matcher) catch_all (e) { _ => null };
                    // Its already considered a positional, we don't need to suggest turning it
                    // into one
                    let suggested_trailing_arg = false;
                    throw error_unknown_argument(
                        self._cmd,
                        arg_os.display(),
                        null,
                        suggested_trailing_arg,
                        Usage.new(self._cmd).create_usage_with_title([]),
                    );
                }

                if (arg.is_trailing_var_arg_set()) {
                    trailing_values = true;
                }

                if (matcher.pending_arg_id() != arg.get_id() || !arg.is_multiple_values_set()) {
                    self.resolve_pending(matcher);
                }
                let term = self.check_terminator(arg, arg_os.to_value_os());
                parse_state = if (term != null) {
                    pos_counter += 1;
                    parse_state_values_done()
                } else {
                    let arg_values = matcher.pending_values_mut(
                        arg.get_id(),
                        Identifier.Index,
                        trailing_values,
                    );
                    arg_values.push(arg_os.to_value_os());

                    // Only increment the positional counter if it doesn't allow multiples
                    if (!arg.is_multiple()) {
                        pos_counter += 1;
                        parse_state_values_done()
                    } else {
                        parse_state_pos(arg.get_id())
                    }
                };
                valid_arg_found = true;
            } else if let external_parser: ValueParser = self._cmd.get_external_subcommand_value_parser() {
                // Get external subcommand name
                let sc_name = arg_os.to_value();

                // Collect the external subcommand args
                let sc_m = ArgMatcher.new(self._cmd);
                sc_m.start_occurrence_of_external(self._cmd);

                for (let raw_val in raw_args.remaining(args_cursor)) {
                    let val = external_parser.parse_ref(
                        self._cmd,
                        null,
                        raw_val,
                        ValueSource.CommandLine,
                    );
                    let external_id = ID_EXTERNAL();
                    sc_m.add_val_to(external_id, val, raw_val);
                }

                matcher.subcommand(SubCommand {
                    name: sc_name,
                    matches: sc_m.into_inner(),
                });
                return;
            } else {
                // Start error processing
                self.resolve_pending(matcher) catch_all (e) { _ => null };
                throw self.match_arg_error(arg_os, valid_arg_found, trailing_values, matcher);
            }
        }

        if let pos_sc_name: string = subcmd_name {
            if (self._cmd.is_args_conflicts_with_subcommands_set() && valid_arg_found) {
                throw error_subcommand_conflict(
                    self._cmd,
                    pos_sc_name,
                    matcher.arg_ids()
                        // skip groups
                        .filter_map((id) -> { if let a: Arg = self._cmd.find(id) { a.to_string() } else { null } }),
                    Usage.new(self._cmd).create_usage_with_title([]),
                );
            }
            let found = self._cmd.find_subcommand(pos_sc_name) ?? baml.sys.panic(INTERNAL_ERROR_MSG());
            let sc_name = found.get_name();
            self.parse_subcommand(sc_name, matcher, raw_args, args_cursor, keep_state);
        }
    }

    function match_arg_error(self, arg_os: root.clap_lex.ParsedArg, valid_arg_found: bool, trailing_values: bool, matcher: ArgMatcher) -> Error {
        // If argument follows a `--`
        if (trailing_values) {
            // If the arg matches a subcommand name, or any of its aliases (if defined)
            if (self.possible_subcommand(arg_os.to_value(), valid_arg_found) != null) {
                return error_unnecessary_double_dash(
                    self._cmd,
                    arg_os.display(),
                    Usage.new(self._cmd).create_usage_with_title([]),
                );
            }
        }

        let suggested_trailing_arg = !trailing_values
            && self._cmd.has_positionals()
            && (arg_os.is_long() || arg_os.is_short());

        if (self._cmd.has_subcommands()) {
            if (self._cmd.is_args_conflicts_with_subcommands_set() && valid_arg_found) {
                return error_subcommand_conflict(
                    self._cmd,
                    arg_os.display(),
                    matcher.arg_ids()
                        .filter_map((id) -> { if let a: Arg = self._cmd.find(id) { a.to_string() } else { null } }),
                    Usage.new(self._cmd).create_usage_with_title([]),
                );
            }

            let candidates = did_you_mean(arg_os.display(), self._cmd.all_subcommand_names());
            // If the argument looks like a subcommand.
            if (candidates.length() > 0) {
                return error_invalid_subcommand(
                    self._cmd,
                    arg_os.display(),
                    candidates,
                    self._cmd.get_bin_name_fallback(),
                    suggested_trailing_arg,
                    Usage.new(self._cmd).create_usage_with_title([]),
                );
            }

            // If the argument must be a subcommand.
            if (!self._cmd.has_positionals() || self._cmd.is_infer_subcommands_set()) {
                return error_unrecognized_subcommand(
                    self._cmd,
                    arg_os.display(),
                    Usage.new(self._cmd).create_usage_with_title([]),
                );
            }
        }

        error_unknown_argument(
            self._cmd,
            arg_os.display(),
            null,
            suggested_trailing_arg,
            Usage.new(self._cmd).create_usage_with_title([]),
        )
    }

    // Checks if the arg matches a subcommand name, or any of its aliases (if defined)
    function possible_subcommand(self, arg: string, valid_arg_found: bool) -> string? {
        if (!(self._cmd.is_args_conflicts_with_subcommands_set() && valid_arg_found)) {
            if (self._cmd.is_infer_subcommands_set()) {
                // For subcommand `test`, we accepts it's prefix: `t`, `te`,
                // `tes` and `test`.
                let matched = self._cmd.get_subcommands().filter_map((s) -> {
                    if (s.get_name().starts_with(arg)) {
                        return s.get_name();
                    }

                    // Use find here instead of chaining the iterator because we want to accept
                    // conflicts in aliases.
                    s.get_all_aliases().find((a) -> { a.starts_with(arg) })
                });
                if (matched.length() == 1) {
                    return matched[0];
                }
            }

            // Don't use an else here because we want inference to support exact matching even if
            // there are conflicts.
            if let sc: Command = self._cmd.find_subcommand(arg) {
                return sc.get_name();
            }
        }
        null
    }

    // Checks if the arg matches a long flag subcommand name, or any of its aliases (if defined)
    function possible_long_flag_subcommand(self, arg: string) -> string? {
        if (self._cmd.is_infer_subcommands_set()) {
            let matched = self._cmd.get_subcommands().filter_map((sc) -> {
                if let long: string = sc.get_long_flag() {
                    if (long.starts_with(arg)) {
                        sc.get_name()
                    } else if (sc.get_all_long_flag_aliases().some((alias) -> { alias.starts_with(arg) })) {
                        sc.get_name()
                    } else {
                        null
                    }
                } else {
                    null
                }
            });
            if (matched.length() == 1) {
                return matched[0];
            }
        }
        if let sc_name: string = self._cmd.find_long_subcmd(arg) {
            return sc_name;
        }
        null
    }

    function parse_help_subcommand(self, cmds: string[]) -> void throws Error {
        let cmd = self._cmd.clone();
        let sc = cmd;
        for (let c in cmds) {
            let found = sc.find_subcommand(c);
            if let f: Command = found {
                let sc_name = f.get_name();
                sc = sc._build_subcommand(sc_name) ?? baml.sys.panic(INTERNAL_ERROR_MSG());
            } else {
                throw error_unrecognized_subcommand(
                    sc,
                    c,
                    Usage.new(sc).create_usage_with_title([]),
                );
            }
        }

        let parser = CmdParser.new(sc);

        throw parser.help_err(true)
    }

    function is_new_arg(self, next: root.clap_lex.ParsedArg, current_positional: Arg) -> bool {
        let cur = command_index(self._cmd, current_positional.get_id());
        if (cur.is_allow_hyphen_values_set()
            || (cur.is_allow_negative_numbers_set() && next.is_negative_number())) {
            // If allow hyphen, this isn't a new arg.
            false
        } else if (next.is_long()) {
            // If this is a long flag, this is a new arg.
            true
        } else if (next.is_short()) {
            // If this is a short flag, this is a new arg. But a single '-' by
            // itself is a value and typically means "stdin" on unix systems.
            true
        } else {
            // Nothing special, this is a value.
            false
        }
    }

    function parse_subcommand(self, sc_name: string, matcher: ArgMatcher, raw_args: root.clap_lex.RawArgs, args_cursor: root.clap_lex.ArgCursor, keep_state: bool) -> void throws Error {
        let partial_parsing_enabled = self._cmd.is_ignore_errors_set();

        if let sc: Command = self._cmd._build_subcommand(sc_name) {
            let sc_matcher = ArgMatcher.new(sc);

            {
                let p = CmdParser.new(sc);
                // HACK: maintain indexes between parsers
                // FlagSubCommand short arg needs to revisit the current short args, but skip the subcommand itself
                if (keep_state) {
                    p._cur_idx = self._cur_idx;
                    p._flag_subcmd_at = self._flag_subcmd_at;
                    p._flag_subcmd_skip = self._flag_subcmd_skip;
                }
                p.get_matches_with(sc_matcher, raw_args, args_cursor) catch (e) {
                    let error: Error => {
                        if (partial_parsing_enabled && error.use_stderr()) {
                            // ignored error in subcommand
                        } else {
                            throw error;
                        }
                    },
                };
            }
            matcher.subcommand(SubCommand {
                name: sc.get_name(),
                matches: sc_matcher.into_inner(),
            });
        }
    }

    function parse_long_arg(self, matcher: ArgMatcher, long_arg: string, long_value: string?, parse_state: ParseState, pos_counter: int, valid_arg_found: ValidArgFound) -> ParseResult throws Error {
        // maybe here lifetime should be 'a
        if ((parse_state.kind == ParseStateKind.Opt || parse_state.kind == ParseStateKind.Pos)
            && command_index(self._cmd, parse_state.id).is_allow_hyphen_values_set()) {
            return parse_result(ParseResultKind.MaybeHyphenValue);
        }

        let found: Arg? = if let a: Arg = self._cmd.get_keymap().get_long(long_arg) {
            a
        } else if (self._cmd.is_infer_long_args_set()) {
            let matches = self._cmd.get_arguments().filter((a) -> {
                if let long: string = a.get_long() {
                    if (long.starts_with(long_arg)) {
                        return true;
                    }
                }
                a._aliases.some((alias) -> { alias.name.starts_with(long_arg) })
            });
            if (matches.length() == 1) { matches[0] } else { null }
        } else {
            null
        };

        if let arg: Arg = found {
            let ident = Identifier.Long;
            valid_arg_found.value = true;
            if (arg.is_takes_value_set()) {
                let has_eq = long_value != null;
                self.parse_opt_value(ident, long_value, arg, matcher, has_eq)
            } else if let rest: string = long_value {
                let required = self._cmd.required_graph();
                let used: Id[] = matcher.arg_ids()
                    .filter((arg_id) -> { matcher.check_explicit(arg_id, ArgPredicateIsPresent {}) })
                    .filter((n) -> {
                        if let a: Arg = self._cmd.find(n) { !(a.is_hide_set() || required.contains(a.get_id())) } else { true }
                    });
                used.push(arg.get_id());

                ParseResult {
                    kind: ParseResultKind.UnneededAttachedValue,
                    name: "",
                    rest: rest,
                    used: used,
                    arg: arg.to_string(),
                }
            } else {
                let trailing_idx: int? = null;
                self.react(
                    ident,
                    ValueSource.CommandLine,
                    arg,
                    [],
                    trailing_idx,
                    matcher,
                )
            }
        } else if let sc_name: string = self.possible_long_flag_subcommand(long_arg) {
            parse_result_named(ParseResultKind.FlagSubCommand, sc_name)
        } else if (if let a: Arg = self._cmd.get_keymap().get_position(pos_counter) { a.is_allow_hyphen_values_set() && !a.is_last_set() } else { false }) {
            parse_result(ParseResultKind.MaybeHyphenValue)
        } else {
            parse_result_arg(ParseResultKind.NoMatchingArg, long_arg)
        }
    }

    function parse_short_arg(self, matcher: ArgMatcher, short_arg: root.clap_lex.ShortFlags, parse_state: ParseState, pos_counter: int, valid_arg_found: ValidArgFound) -> ParseResult throws Error {
        let pos_arg = self._cmd.get_keymap().get_position(pos_counter);
        if ((parse_state.kind == ParseStateKind.Opt || parse_state.kind == ParseStateKind.Pos)
            && (command_index(self._cmd, parse_state.id).is_allow_hyphen_values_set()
                || (command_index(self._cmd, parse_state.id).is_allow_negative_numbers_set() && short_arg.is_negative_number()))) {
            return parse_result(ParseResultKind.MaybeHyphenValue);
        } else if ((if let a: Arg = pos_arg { a.is_allow_negative_numbers_set() } else { false })
            && short_arg.is_negative_number()) {
            return parse_result(ParseResultKind.MaybeHyphenValue);
        } else if ((if let a: Arg = pos_arg { a.is_allow_hyphen_values_set() && !a.is_last_set() } else { false })
            && short_arg._chars.slice(short_arg._pos, short_arg._chars.length()).some((c) -> { !self._cmd.contains_short(c) })) {
            return parse_result(ParseResultKind.MaybeHyphenValue);
        }

        let ret = parse_result(ParseResultKind.NoArg);

        let skip = self._flag_subcmd_skip;
        self._flag_subcmd_skip = 0;
        short_arg.advance_by(skip);

        while let c: string = short_arg.next_flag() {
            // Check for matching short options, and return the name if there is no trailing
            // concatenated value: -oval
            // Option: -o
            // Value: val
            if let arg: Arg = self._cmd.get_keymap().get_short(c) {
                let ident = Identifier.Short;
                valid_arg_found.value = true;
                if (!arg.is_takes_value_set()) {
                    let arg_values: OsString[] = [];
                    let trailing_idx: int? = null;
                    ret = self.react(
                        ident,
                        ValueSource.CommandLine,
                        arg,
                        arg_values,
                        trailing_idx,
                        matcher,
                    );
                    continue;
                }

                // Check for trailing concatenated value
                //
                // Cloning the iterator, so we rollback if it isn't there.
                let rest = short_arg._chars.slice(short_arg._pos, short_arg._chars.length()).join("");
                let val: string? = if (rest.is_empty()) { null } else { rest };

                // Default to "we're expecting a value later".
                //
                // If attached value is not consumed, we may have more short
                // flags to parse, continue.
                //
                // e.g. `-xvf`, when require_equals && x.min_vals == 0, we don't
                // consume the `vf`, even if it's provided as value.
                let has_eq = false;
                if let v: string = val {
                    if (v.starts_with("=")) {
                        val = v.slice(1, v.length());
                        has_eq = true;
                    }
                }
                let r = self.parse_opt_value(ident, val, arg, matcher, has_eq);
                if (r.kind == ParseResultKind.AttachedValueNotConsumed) {
                    continue;
                }
                return r;
            }

            return if let sc_name: string = self._cmd.find_short_subcmd(c) {
                // Make sure indices get updated before reading `self.cur_idx`
                self.resolve_pending(matcher);
                self._cur_idx = self._cur_idx + 1;

                let name = sc_name;
                // Get the index of the previously saved flag subcommand in the group of flags (if exists).
                // If it is a new flag subcommand, then the formentioned index should be the current one
                // (ie. `cur_idx`), and should be registered.
                let cur_idx = self._cur_idx;
                if (self._flag_subcmd_at == null) { self._flag_subcmd_at = cur_idx; }
                let done_short_args = short_arg.is_empty();
                if (done_short_args) {
                    self._flag_subcmd_at = null;
                }
                parse_result_named(ParseResultKind.FlagSubCommand, name)
            } else {
                parse_result_arg(ParseResultKind.NoMatchingArg, `-${c}`)
            };
        }
        ret
    }

    function parse_opt_value(self, ident: Identifier, attached_value: string?, arg: Arg, matcher: ArgMatcher, has_eq: bool) -> ParseResult throws Error {
        // require_equals is set, but no '=' is provided, try throwing error.
        if (arg.is_require_equals_set() && !has_eq) {
            if (arg.get_min_vals() == 0) {
                let arg_values: OsString[] = [];
                let trailing_idx: int? = null;
                self.react(
                    ident,
                    ValueSource.CommandLine,
                    arg,
                    arg_values,
                    trailing_idx,
                    matcher,
                );
                if (attached_value != null) {
                    parse_result(ParseResultKind.AttachedValueNotConsumed)
                } else {
                    parse_result(ParseResultKind.ValuesDone)
                }
            } else {
                parse_result_arg(ParseResultKind.EqualsNotProvided, arg.to_string())
            }
        } else if let v: string = attached_value {
            let arg_values: OsString[] = [v];
            let trailing_idx: int? = null;
            self.react(
                ident,
                ValueSource.CommandLine,
                arg,
                arg_values,
                trailing_idx,
                matcher,
            );
            // Attached are always done
            parse_result(ParseResultKind.ValuesDone)
        } else {
            self.resolve_pending(matcher);
            let trailing_values = false;
            matcher.pending_values_mut(arg.get_id(), ident, trailing_values);
            parse_result_named(ParseResultKind.Opt, arg.get_id())
        }
    }

    function check_terminator(self, arg: Arg, val: string) -> ParseResult? {
        if (arg._terminator != null && arg._terminator == val) {
            parse_result(ParseResultKind.ValuesDone)
        } else {
            null
        }
    }

    function push_arg_values(self, arg: Arg, raw_vals: OsString[], source: ValueSource, matcher: ArgMatcher) -> void throws Error {
        for (let raw_val in raw_vals) {
            // update the current index because each value is a distinct index to clap
            self._cur_idx = self._cur_idx + 1;
            let value_parser = arg.get_value_parser();
            let val = value_parser.parse_ref(self._cmd, arg, raw_val, source);

            matcher.add_val_to(arg.get_id(), val, raw_val);
            matcher.add_index_to(arg.get_id(), self._cur_idx);
        }
    }

    function resolve_pending(self, matcher: ArgMatcher) -> void throws Error {
        let pending = matcher.take_pending();
        if let p: PendingArg = pending {
            let arg = self._cmd.find(p.id) ?? baml.sys.panic(INTERNAL_ERROR_MSG());
            self.react(
                p.ident,
                ValueSource.CommandLine,
                arg,
                p.raw_vals,
                p.trailing_idx,
                matcher,
            );
        }
    }

    function react(self, ident: Identifier?, source: ValueSource, arg: Arg, raw_vals_in: OsString[], trailing_idx_in: int?, matcher: ArgMatcher) -> ParseResult throws Error {
        self.resolve_pending(matcher);

        let raw_vals = raw_vals_in;
        let trailing_idx = trailing_idx_in;

        // Process before `default_missing_values` to avoid it counting as values from the command
        // line
        if (source == ValueSource.CommandLine) {
            self.verify_num_args(arg, raw_vals);
        }

        if (raw_vals.length() == 0) {
            // We assume this case is valid: require equals, but min_vals == 0.
            if (arg._default_missing_vals.length() > 0) {
                trailing_idx = null;
                raw_vals = raw_vals.concat(arg._default_missing_vals);
            }
        }

        if let val_delim: string = arg.get_value_delimiter() {
            if (self._cmd.is_dont_delimit_trailing_values_set() && trailing_idx == 0) {
                // Nothing to do
            } else {
                let split_raw_vals: OsString[] = [];
                for (let i in baml.iter.Range.new(0, raw_vals.length())) {
                    let raw_val = raw_vals[i];
                    if (!raw_val.includes(val_delim)
                        || (self._cmd.is_dont_delimit_trailing_values_set() && trailing_idx == i)) {
                        split_raw_vals.push(raw_val);
                    } else {
                        for (let x in raw_val.split(val_delim)) { split_raw_vals.push(x); }
                    }
                }
                raw_vals = split_raw_vals;
            }
        }

        match (arg.get_action()) {
            ArgAction.Set => {
                if (source == ValueSource.CommandLine
                    && (ident == Identifier.Short || ident == Identifier.Long)) {
                    // Record flag's index
                    self._cur_idx = self._cur_idx + 1;
                }
                if (matcher.remove(arg.get_id())
                    && !(self._cmd.is_args_override_self() || arg._overrides.includes(arg.get_id()))) {
                    throw error_argument_conflict(
                        self._cmd,
                        arg.to_string(),
                        [arg.to_string()],
                        Usage.new(self._cmd).create_usage_with_title([]),
                    );
                }
                self.start_custom_arg(matcher, arg, source);
                self.push_arg_values(arg, raw_vals, source, matcher);
                parse_result(ParseResultKind.ValuesDone)
            },
            ArgAction.Append => {
                if (source == ValueSource.CommandLine
                    && (ident == Identifier.Short || ident == Identifier.Long)) {
                    // Record flag's index
                    self._cur_idx = self._cur_idx + 1;
                }
                self.start_custom_arg(matcher, arg, source);
                self.push_arg_values(arg, raw_vals, source, matcher);
                parse_result(ParseResultKind.ValuesDone)
            },
            ArgAction.SetTrue => {
                let rv = if (raw_vals.length() == 0) { ["true"] } else { raw_vals };

                if (matcher.remove(arg.get_id())
                    && !(self._cmd.is_args_override_self() || arg._overrides.includes(arg.get_id()))) {
                    throw error_argument_conflict(
                        self._cmd,
                        arg.to_string(),
                        [arg.to_string()],
                        Usage.new(self._cmd).create_usage_with_title([]),
                    );
                }
                self.start_custom_arg(matcher, arg, source);
                self.push_arg_values(arg, rv, source, matcher);
                parse_result(ParseResultKind.ValuesDone)
            },
            ArgAction.SetFalse => {
                let rv = if (raw_vals.length() == 0) { ["false"] } else { raw_vals };

                if (matcher.remove(arg.get_id())
                    && !(self._cmd.is_args_override_self() || arg._overrides.includes(arg.get_id()))) {
                    throw error_argument_conflict(
                        self._cmd,
                        arg.to_string(),
                        [arg.to_string()],
                        Usage.new(self._cmd).create_usage_with_title([]),
                    );
                }
                self.start_custom_arg(matcher, arg, source);
                self.push_arg_values(arg, rv, source, matcher);
                parse_result(ParseResultKind.ValuesDone)
            },
            ArgAction.Count => {
                let rv = if (raw_vals.length() == 0) {
                    let existing_value = matcher.inner().get_one<CountType>(arg.get_id()) ?? 0;
                    let next_value = if (existing_value >= 255) { 255 } else { existing_value + 1 };
                    [`${next_value}`]
                } else {
                    raw_vals
                };

                matcher.remove(arg.get_id());
                self.start_custom_arg(matcher, arg, source);
                self.push_arg_values(arg, rv, source, matcher);
                parse_result(ParseResultKind.ValuesDone)
            },
            ArgAction.Help => {
                let use_long = match (ident) {
                    Identifier.Long => true,
                    Identifier.Short => false,
                    Identifier.Index => true,
                    null => true,
                };
                throw self.help_err(use_long)
            },
            ArgAction.HelpShort => {
                let use_long = false;
                throw self.help_err(use_long)
            },
            ArgAction.HelpLong => {
                let use_long = true;
                throw self.help_err(use_long)
            },
            ArgAction.Version => {
                let use_long = match (ident) {
                    Identifier.Long => true,
                    Identifier.Short => false,
                    Identifier.Index => true,
                    null => true,
                };
                throw self.version_err(use_long)
            },
        }
    }

    function verify_num_args(self, arg: Arg, raw_vals: OsString[]) -> void throws Error {
        if (self._cmd.is_ignore_errors_set()) {
            return;
        }

        let actual = raw_vals.length();
        let expected = arg.get_num_args() ?? baml.sys.panic(INTERNAL_ERROR_MSG());

        if (0 < expected.min_values() && actual == 0) {
            // Issue 665 (https://github.com/clap-rs/clap/issues/665)
            // Issue 1105 (https://github.com/clap-rs/clap/issues/1105)
            throw error_empty_value(
                self._cmd,
                get_possible_values_cli(arg)
                    .filter((pv) -> { !pv.is_hide_set() })
                    .map((n) -> { n.get_name() }),
                arg.to_string(),
            );
        } else if let exp: int = expected.num_values() {
            if (exp != actual) {
                throw error_wrong_number_of_values(
                    self._cmd,
                    arg.to_string(),
                    exp,
                    actual,
                    Usage.new(self._cmd).create_usage_with_title([]),
                );
            }
        } else if (actual < expected.min_values()) {
            throw error_too_few_values(
                self._cmd,
                arg.to_string(),
                expected.min_values(),
                actual,
                Usage.new(self._cmd).create_usage_with_title([]),
            );
        } else if (expected.max_values() < actual) {
            throw error_too_many_values(
                self._cmd,
                raw_vals[-1],
                arg.to_string(),
                Usage.new(self._cmd).create_usage_with_title([]),
            );
        }
    }

    function remove_overrides(self, arg: Arg, matcher: ArgMatcher) -> void {
        for (let override_id in arg._overrides) {
            matcher.remove(override_id);
        }

        // Override anything that can override us
        let transitive: Id[] = [];
        for (let arg_id in matcher.arg_ids()) {
            if let overrider: Arg = self._cmd.find(arg_id) {
                if (overrider._overrides.includes(arg.get_id())) {
                    transitive.push(overrider.get_id());
                }
            }
        }
        for (let overrider_id in transitive) {
            matcher.remove(overrider_id);
        }
    }

    function add_env(self, matcher: ArgMatcher) -> void throws Error {
        for (let arg in self._cmd.get_arguments()) {
            // Use env only if the arg was absent among command line args,
            // early return if this is not the case.
            if (matcher.contains(arg._id)) {
                continue;
            }
            if let arg_env: ArgEnv = arg._env {
                if let val: string = arg_env.value {
                    let arg_values: OsString[] = [val];
                    let trailing_idx: int? = null;
                    self.react(
                        null,
                        ValueSource.EnvVariable,
                        arg,
                        arg_values,
                        trailing_idx,
                        matcher,
                    );
                }
            }
        }
    }

    function add_defaults(self, matcher: ArgMatcher) -> void throws Error {
        for (let arg in self._cmd.get_arguments()) {
            self.add_default_value(arg, matcher);
        }
    }

    function add_default_value(self, arg: Arg, matcher: ArgMatcher) -> void throws Error {
        if (arg._default_vals_ifs.length() > 0) {
            if (!matcher.contains(arg.get_id())) {
                for (let dvi in arg._default_vals_ifs) {
                    let add = if let a: MatchedArg = matcher.get(dvi.id) {
                        match (dvi.predicate) {
                            let eq: ArgPredicateEquals => a.raw_vals_flatten().some((value) -> { eq.value == value }),
                            let p: ArgPredicateIsPresent => true,
                        }
                    } else {
                        false
                    };

                    if (add) {
                        if let default: OsStr[] = dvi.values {
                            let trailing_idx: int? = null;
                            self.react(
                                null,
                                ValueSource.DefaultValue,
                                arg,
                                default,
                                trailing_idx,
                                matcher,
                            );
                        }
                        return;
                    }
                }
            }
        }

        if (arg._default_vals.length() > 0) {
            if (matcher.contains(arg.get_id())) {
                // do nothing
            } else {
                let arg_values = arg._default_vals.slice(0, arg._default_vals.length());
                let trailing_idx: int? = null;
                self.react(
                    null,
                    ValueSource.DefaultValue,
                    arg,
                    arg_values,
                    trailing_idx,
                    matcher,
                );
            }
        }
    }

    function start_custom_arg(self, matcher: ArgMatcher, arg: Arg, source: ValueSource) -> void {
        if (source == ValueSource.CommandLine) {
            // With each new occurrence, remove overrides from prior occurrences
            self.remove_overrides(arg, matcher);
        }
        matcher.start_custom_arg(arg, source);
        if (value_source_is_explicit(source)) {
            for (let group in self._cmd.groups_for_arg(arg.get_id())) {
                matcher.start_custom_group(group, source);
                matcher.add_val_to(
                    group,
                    AnyValue.new(arg.get_id()),
                    arg.get_id(),
                );
            }
        }
    }

    // ===== Error, Help, and Version Methods =====

    /// Is only used for the long flag(which is the only one needs fuzzy searching)
    function did_you_mean_error(self, arg: string, matcher: ArgMatcher, remaining_args: string[], trailing_values: bool) -> Error {
        // Didn't match a flag or option
        let longs = self._cmd.get_keymap().keys().filter_map((x) -> {
            match (x) {
                let l: KeyLong => l.s,
                _ => null,
            }
        });

        let did_you_mean = did_you_mean_flag(
            arg,
            remaining_args,
            longs,
            self._cmd.get_subcommands_mut(),
        );

        // Add the arg to the matches to build a proper usage string
        if (!self._cmd.is_ignore_errors_set()) {
            if let dym: FlagSuggestion = did_you_mean {
                if let a: Arg = self._cmd.get_keymap().get_long(dym.candidate) {
                    self.start_custom_arg(matcher, a, ValueSource.CommandLine);
                }
            }
        }
        let suggested = if let dym: FlagSuggestion = did_you_mean {
            SuggestedArg { arg: `--${dym.candidate}`, subcmd: dym.subcommand }
        } else {
            null
        };

        let required = self._cmd.required_graph();
        let used: Id[] = matcher.arg_ids()
            .filter((arg_id) -> { matcher.check_explicit(arg_id, ArgPredicateIsPresent {}) })
            .filter((n) -> { if let a: Arg = self._cmd.find(n) { !a.is_hide_set() } else { false } });

        // `did_you_mean` is a lot more likely and should cause us to skip the `--` suggestion
        // with the one exception being that the CLI is trying to capture arguments
        //
        // In theory, this is only called for `--long`s, so we don't need to check
        let suggested_trailing_arg = (suggested == null
            || self._cmd.get_positionals().some((a) -> { a.is_last_set() || a.is_trailing_var_arg_set() }))
            && !trailing_values
            && self._cmd.has_positionals();
        error_unknown_argument(
            self._cmd,
            `--${arg}`,
            suggested,
            suggested_trailing_arg,
            Usage.new(self._cmd)
                .required(required)
                .create_usage_with_title(used),
        )
    }

    function help_err(self, use_long: bool) -> Error {
        let styled = self._cmd.write_help_err(use_long);
        error_display_help(self._cmd, styled)
    }

    function version_err(self, use_long: bool) -> Error {
        let styled = self._cmd.write_version_err(use_long);
        error_display_version(self._cmd, styled)
    }
}

/// `&mut bool` out-parameter
class ValidArgFound {
    value: bool,
}
