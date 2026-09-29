// Port of clap_builder/src/error/format.rs

/// Defines how to format an error for displaying to the user
interface ErrorFormatter {
    /// Stylize the error for the terminal
    function format_error(error: Error) -> StyledStr throws never
}

/// Report [`ErrorKind`]
///
/// No context is included.
///
/// **NOTE:** Consider removing the `error-context` default feature if using this to remove all
/// overhead for [`RichFormatter`].
class KindFormatter {
    implements ErrorFormatter {
        function format_error(error: Error) -> StyledStr throws never {
            let styles = error._styles;
            let styled = StyledStr.new();

            start_error(styled, styles);
            if let msg: string = error_kind_as_str(error.kind()) {
                styled.push_str(msg);
            } else if let source: string = error._source {
                styled.push_str(source);
            } else {
                styled.push_str("unknown cause");
            }
            styled.push_str("\n");
            styled
        }
    }
}

/// Richly formatted error context
///
/// This follows the [rustc diagnostic style guide](https://rustc-dev-guide.rust-lang.org/diagnostics.html#suggestion-style-guide).
class RichFormatter {
    implements ErrorFormatter {
        function format_error(error: Error) -> StyledStr throws never {
            let styles = error._styles;
            let valid = styles.get_valid();

            let styled = StyledStr.new();
            start_error(styled, styles);

            if (!write_dynamic_context(error, styled, styles)) {
                if let msg: string = error_kind_as_str(error.kind()) {
                    styled.push_str(msg);
                } else if let source: string = error._source {
                    styled.push_str(source);
                } else {
                    styled.push_str("unknown cause");
                }
            }

            let suggested = false;
            if let v: ContextValue = error.get(ContextKind.SuggestedSubcommand) {
                styled.push_str("\n");
                if (!suggested) {
                    styled.push_str("\n");
                    suggested = true;
                }
                did_you_mean_styled(styled, styles, "subcommand", v);
            }
            if let v: ContextValue = error.get(ContextKind.SuggestedArg) {
                styled.push_str("\n");
                if (!suggested) {
                    styled.push_str("\n");
                    suggested = true;
                }
                did_you_mean_styled(styled, styles, "argument", v);
            }
            if let v: ContextValue = error.get(ContextKind.SuggestedValue) {
                styled.push_str("\n");
                if (!suggested) {
                    styled.push_str("\n");
                    suggested = true;
                }
                did_you_mean_styled(styled, styles, "value", v);
            }
            let suggestions = error.get(ContextKind.Suggested);
            if let s: ContextValueStyledStrs = suggestions {
                if (!suggested) {
                    styled.push_str("\n");
                }
                for (let suggestion in s.value) {
                    styled.push_str(`\n${TAB()}`);
                    styled.push_styled_str(valid, "tip:");
                    styled.push_str(" ");
                    styled.push_styled(suggestion);
                }
            }

            let usage = error.get(ContextKind.Usage);
            if let u: ContextValueStyledStr = usage {
                put_usage(styled, u.value);
            }

            try_help(styled, styles, error._help_flag);

            styled
        }
    }
}

function start_error(styled: StyledStr, styles: Styles) -> void {
    let error = styles.get_error();
    styled.push_styled_str(error, "error:");
    styled.push_str(" ");
}

function write_dynamic_context(error: Error, styled: StyledStr, styles: Styles) -> bool {
    let valid = styles.get_valid();
    let invalid = styles.get_invalid();
    let literal = styles.get_literal();

    match (error.kind()) {
        ErrorKind.ArgumentConflict => {
            let prior_arg = error.get(ContextKind.PriorArg);
            if let ia: ContextValueString = error.get(ContextKind.InvalidArg) {
                let invalid_arg = ia.value;
                let same = if let p: ContextValueString = prior_arg { p.value == invalid_arg } else { false };
                if (same) {
                    prior_arg = null;
                    styled.push_str("the argument '");
                    styled.push_styled_str(invalid, invalid_arg);
                    styled.push_str("' cannot be used multiple times");
                } else {
                    styled.push_str("the argument '");
                    styled.push_styled_str(invalid, invalid_arg);
                    styled.push_str("' cannot be used with");
                }
            } else if let isub: ContextValueString = error.get(ContextKind.InvalidSubcommand) {
                styled.push_str("the subcommand '");
                styled.push_styled_str(invalid, isub.value);
                styled.push_str("' cannot be used with");
            } else {
                styled.push_str(error_kind_as_str(error.kind()) ?? "");
            }

            if let pa: ContextValue = prior_arg {
                match (pa) {
                    let values: ContextValueStrings => {
                        styled.push_str(":");
                        for (let v in values.value) {
                            styled.push_str(`\n${TAB()}`);
                            styled.push_styled_str(invalid, v);
                        }
                    },
                    let value: ContextValueString => {
                        styled.push_str(" '");
                        styled.push_styled_str(invalid, value.value);
                        styled.push_str("'");
                    },
                    _ => {
                        styled.push_str(" one or more of the other specified arguments");
                    },
                }
            }

            true
        },
        ErrorKind.NoEquals => {
            if let ia: ContextValueString = error.get(ContextKind.InvalidArg) {
                styled.push_str("equal sign is needed when assigning values to '");
                styled.push_styled_str(invalid, ia.value);
                styled.push_str("'");
                true
            } else {
                false
            }
        },
        ErrorKind.InvalidValue => {
            let invalid_arg = error.get(ContextKind.InvalidArg);
            let invalid_value = error.get(ContextKind.InvalidValue);
            if let ia: ContextValueString = invalid_arg {
                if let iv: ContextValueString = invalid_value {
                    if (iv.value.is_empty()) {
                        styled.push_str("a value is required for '");
                        styled.push_styled_str(invalid, ia.value);
                        styled.push_str("' but none was supplied");
                    } else {
                        styled.push_str("invalid value '");
                        styled.push_styled_str(invalid, iv.value);
                        styled.push_str("' for '");
                        styled.push_styled_str(literal, ia.value);
                        styled.push_str("'");
                    }

                    let values = error.get(ContextKind.ValidValue);
                    write_values_list("possible values", styled, valid, values);

                    return true;
                }
            }
            false
        },
        ErrorKind.InvalidSubcommand => {
            if let isub: ContextValueString = error.get(ContextKind.InvalidSubcommand) {
                styled.push_str("unrecognized subcommand '");
                styled.push_styled_str(invalid, isub.value);
                styled.push_str("'");
                true
            } else {
                false
            }
        },
        ErrorKind.MissingRequiredArgument => {
            if let ia: ContextValueStrings = error.get(ContextKind.InvalidArg) {
                styled.push_str("the following required arguments were not provided:");
                for (let v in ia.value) {
                    styled.push_str(`\n${TAB()}`);
                    styled.push_styled_str(valid, v);
                }
                true
            } else {
                false
            }
        },
        ErrorKind.MissingSubcommand => {
            if let isub: ContextValueString = error.get(ContextKind.InvalidSubcommand) {
                styled.push_str("'");
                styled.push_styled_str(invalid, isub.value);
                styled.push_str("' requires a subcommand but one was not provided");
                let values = error.get(ContextKind.ValidSubcommand);
                write_values_list("subcommands", styled, valid, values);

                true
            } else {
                false
            }
        },
        ErrorKind.InvalidUtf8 => false,
        ErrorKind.TooManyValues => {
            let invalid_arg = error.get(ContextKind.InvalidArg);
            let invalid_value = error.get(ContextKind.InvalidValue);
            if let ia: ContextValueString = invalid_arg {
                if let iv: ContextValueString = invalid_value {
                    styled.push_str("unexpected value '");
                    styled.push_styled_str(invalid, iv.value);
                    styled.push_str("' for '");
                    styled.push_styled_str(literal, ia.value);
                    styled.push_str("' found; no more were expected");
                    return true;
                }
            }
            false
        },
        ErrorKind.TooFewValues => {
            let invalid_arg = error.get(ContextKind.InvalidArg);
            let actual_num_values = error.get(ContextKind.ActualNumValues);
            let min_values = error.get(ContextKind.MinValues);
            if let ia: ContextValueString = invalid_arg {
                if let an: ContextValueNumber = actual_num_values {
                    if let mv: ContextValueNumber = min_values {
                        let were_provided = singular_or_plural(an.value);
                        styled.push_styled_str(valid, `${mv.value}`);
                        styled.push_str(" values required by '");
                        styled.push_styled_str(literal, ia.value);
                        styled.push_str("'; only ");
                        styled.push_styled_str(invalid, `${an.value}`);
                        styled.push_str(were_provided);
                        return true;
                    }
                }
            }
            false
        },
        ErrorKind.ValueValidation => {
            let invalid_arg = error.get(ContextKind.InvalidArg);
            let invalid_value = error.get(ContextKind.InvalidValue);
            if let ia: ContextValueString = invalid_arg {
                if let iv: ContextValueString = invalid_value {
                    styled.push_str("invalid value '");
                    styled.push_styled_str(invalid, iv.value);
                    styled.push_str("' for '");
                    styled.push_styled_str(literal, ia.value);
                    styled.push_str("'");
                    if let source: string = error._source {
                        styled.push_str(`: ${source}`);
                    }
                    return true;
                }
            }
            false
        },
        ErrorKind.WrongNumberOfValues => {
            let invalid_arg = error.get(ContextKind.InvalidArg);
            let actual_num_values = error.get(ContextKind.ActualNumValues);
            let num_values = error.get(ContextKind.ExpectedNumValues);
            if let ia: ContextValueString = invalid_arg {
                if let an: ContextValueNumber = actual_num_values {
                    if let nv: ContextValueNumber = num_values {
                        let were_provided = singular_or_plural(an.value);
                        styled.push_styled_str(valid, `${nv.value}`);
                        styled.push_str(" values required for '");
                        styled.push_styled_str(literal, ia.value);
                        styled.push_str("' but ");
                        styled.push_styled_str(invalid, `${an.value}`);
                        styled.push_str(were_provided);
                        return true;
                    }
                }
            }
            false
        },
        ErrorKind.UnknownArgument => {
            if let ia: ContextValueString = error.get(ContextKind.InvalidArg) {
                styled.push_str("unexpected argument '");
                styled.push_styled_str(invalid, ia.value);
                styled.push_str("' found");
                true
            } else {
                false
            }
        },
        _ => false,
    }
}

function write_values_list(list_name: string, styled: StyledStr, valid: Style, possible_values: ContextValue?) -> void {
    if let pv: ContextValueStrings = possible_values {
        if (pv.value.length() > 0) {
            styled.push_str(`\n${TAB()}[${list_name}: `);

            for (let idx in baml.iter.Range.new(0, pv.value.length())) {
                if (idx > 0) {
                    styled.push_str(", ");
                }
                styled.push_styled_str(valid, Escape.new(pv.value[idx]).to_cow());
            }

            styled.push_str("]");
        }
    }
}

function format_error_message(message: string, styles: Styles, cmd: Command?, usage: StyledStr?) -> StyledStr {
    let styled = StyledStr.new();
    start_error(styled, styles);
    styled.push_str(message);
    if let u: StyledStr = usage {
        put_usage(styled, u);
    }
    if let c: Command = cmd {
        try_help(styled, styles, get_help_flag(c));
    }
    styled
}

/// Returns the singular or plural form on the verb to be based on the argument's value.
function singular_or_plural(n: int) -> string {
    if (n > 1) { " were provided" } else { " was provided" }
}

function put_usage(styled: StyledStr, usage: StyledStr) -> void {
    styled.push_str("\n\n");
    styled.push_styled(usage);
}

function get_help_flag(cmd: Command) -> string? {
    if (!cmd.is_disable_help_flag_set()) {
        "--help"
    } else if let flag: string = get_user_help_flag(cmd) {
        flag
    } else if (cmd.has_subcommands() && !cmd.is_disable_help_subcommand_set()) {
        "help"
    } else {
        null
    }
}

function get_user_help_flag(cmd: Command) -> string? {
    let found = cmd.get_arguments().find((arg) -> {
        match (arg.get_action()) {
            ArgAction.Help | ArgAction.HelpShort | ArgAction.HelpLong => true,
            _ => false,
        }
    });
    if let arg: Arg = found {
        if let long: string = arg.get_long() {
            `--${long}`
        } else if let short: string = arg.get_short() {
            `-${short}`
        } else {
            null
        }
    } else {
        null
    }
}

function try_help(styled: StyledStr, styles: Styles, help: string?) -> void {
    if let h: string = help {
        let literal = styles.get_literal();
        styled.push_str("\n\nFor more information, try '");
        styled.push_styled_str(literal, h);
        styled.push_str("'.\n");
    } else {
        styled.push_str("\n");
    }
}

function did_you_mean_styled(styled: StyledStr, styles: Styles, context: string, possibles: ContextValue) -> void {
    let valid = styles.get_valid();
    styled.push_str(TAB());
    styled.push_styled_str(valid, "tip:");
    match (possibles) {
        let possible: ContextValueString => {
            styled.push_str(` a similar ${context} exists: '`);
            styled.push_styled_str(valid, possible.value);
            styled.push_str("'");
        },
        let ps: ContextValueStrings => {
            if (ps.value.length() == 1) {
                styled.push_str(` a similar ${context} exists: `);
            } else {
                styled.push_str(` some similar ${context}s exist: `);
            }
            for (let i in baml.iter.Range.new(0, ps.value.length())) {
                if (i != 0) {
                    styled.push_str(", ");
                }
                styled.push_str("'");
                styled.push_styled_str(valid, ps.value[i]);
                styled.push_str("'");
            }
        },
        _ => {},
    }
}
