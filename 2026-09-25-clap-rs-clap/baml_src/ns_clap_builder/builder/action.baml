// Port of clap_builder/src/builder/action.rs

/// Behavior of arguments when they are encountered while parsing
///
/// # Examples
///
/// ```baml
/// let cmd = Command.new("mycmd")
///     .arg(
///         Arg.new("special-help")
///             .short("?")
///             .action(ArgAction.Help)
///     );
/// ```
enum ArgAction {
    /// When encountered, store the associated value(s) in [`ArgMatches`][crate::ArgMatches]
    ///
    /// **NOTE:** If the argument has previously been seen, it will result in a
    /// [`ArgumentConflict`][crate::error::ErrorKind::ArgumentConflict] unless
    /// [`Command::args_override_self(true)`][crate::Command::args_override_self] is set.
    Set,
    /// When encountered, store the associated value(s) in [`ArgMatches`][crate::ArgMatches]
    Append,
    /// When encountered, act as if `"true"` was encountered on the command-line
    ///
    /// If no [`default_value`][super::Arg::default_value] is set, it will be `false`.
    ///
    /// No value is allowed. To optionally accept a value, see
    /// [`Arg::default_missing_value`][super::Arg::default_missing_value]
    SetTrue,
    /// When encountered, act as if `"false"` was encountered on the command-line
    ///
    /// If no [`default_value`][super::Arg::default_value] is set, it will be `true`.
    SetFalse,
    /// When encountered, increment a `u8` counter starting from `0`.
    ///
    /// If no [`default_value`][super::Arg::default_value] is set, it will be `0`.
    Count,
    /// When encountered, display [`Command::print_help`][super::Command::print_help]
    ///
    /// Depending on the flag, [`Command::print_long_help`][super::Command::print_long_help] may be shown
    Help,
    /// When encountered, display [`Command::print_help`][super::Command::print_help]
    HelpShort,
    /// When encountered, display [`Command::print_long_help`][super::Command::print_long_help]
    HelpLong,
    /// When encountered, display [`Command::version`][super::Command::version]
    ///
    /// Depending on the flag, [`Command::long_version`][super::Command::long_version] may be shown
    Version,
}

/// Returns whether this action accepts values on the command-line
///
/// [`default_values`][super::Arg::default_values] and [`env`][super::Arg::env] may still be
/// processed.
function action_takes_values(a: ArgAction) -> bool {
    match (a) {
        ArgAction.Set => true,
        ArgAction.Append => true,
        _ => false,
    }
}

function action_max_num_args(a: ArgAction) -> ValueRange {
    match (a) {
        ArgAction.Set => ValueRange.FULL(),
        ArgAction.Append => ValueRange.FULL(),
        ArgAction.SetTrue => ValueRange.OPTIONAL(),
        ArgAction.SetFalse => ValueRange.OPTIONAL(),
        _ => ValueRange.EMPTY(),
    }
}

function action_default_num_args(a: ArgAction) -> ValueRange {
    match (a) {
        ArgAction.Set => ValueRange.SINGLE(),
        ArgAction.Append => ValueRange.SINGLE(),
        _ => ValueRange.EMPTY(),
    }
}

function action_default_value(a: ArgAction) -> OsStr? {
    match (a) {
        ArgAction.SetTrue => "false",
        ArgAction.SetFalse => "true",
        ArgAction.Count => "0",
        _ => null,
    }
}

function action_default_missing_value(a: ArgAction) -> OsStr? {
    match (a) {
        ArgAction.SetTrue => "true",
        ArgAction.SetFalse => "false",
        _ => null,
    }
}

function action_default_value_parser(a: ArgAction) -> ValueParser? {
    match (a) {
        ArgAction.SetTrue => ValueParser.bool(),
        ArgAction.SetFalse => ValueParser.bool(),
        ArgAction.Count => ValueParser.new(RangedU64ValueParser.new().range(0, 255).count_type()),
        _ => null,
    }
}

function action_value_type_id(a: ArgAction) -> AnyValueId? {
    match (a) {
        ArgAction.Count => AnyValueId.of<CountType>(),
        _ => null,
    }
}

/// `Debug` for `ArgAction`
function action_debug(a: ArgAction) -> string { a.to_string() }

/// `pub(crate) type CountType = u8;`
type CountType = int
