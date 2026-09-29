// Port of clap_builder/src/error/kind.rs

/// Command line argument parser kind of error
enum ErrorKind {
    /// Occurs when an [`Arg`][crate::Arg] has a set of possible values,
    /// and the user provides a value which isn't in that set.
    InvalidValue,
    /// Occurs when a user provides a flag, option, argument or subcommand which isn't defined.
    UnknownArgument,
    /// Occurs when the user provides an unrecognized [`Subcommand`] which meets the threshold for
    /// being similar enough to an existing subcommand.
    /// If it doesn't meet the threshold, or the 'suggestions' feature is disabled,
    /// the more general [`UnknownArgument`] error is returned.
    InvalidSubcommand,
    /// Occurs when the user doesn't use equals for an option that requires equal
    /// sign to provide values.
    NoEquals,
    /// Occurs when the user provides a value for an argument with a custom validation and the
    /// value fails that validation.
    ValueValidation,
    /// Occurs when a user provides more values for an argument than were defined by setting
    /// [`Arg::num_args`].
    TooManyValues,
    /// Occurs when the user provides fewer values for an argument than were defined by setting
    /// [`Arg::num_args`].
    TooFewValues,
    /// Occurs when the user provides a different number of values for an argument than what's
    /// been defined by setting [`Arg::num_args`] or than was implicitly set by
    /// [`Arg::value_names`].
    WrongNumberOfValues,
    /// Occurs when the user provides two values which conflict with each other and can't be used
    /// together.
    ArgumentConflict,
    /// Occurs when the user does not provide one or more required arguments.
    MissingRequiredArgument,
    /// Occurs when a subcommand is required (as defined by [`Command::subcommand_required`]),
    /// but the user does not provide one.
    MissingSubcommand,
    /// Occurs when the user provides a value containing invalid UTF-8.
    InvalidUtf8,
    /// Not a true "error" as it means `--help` or similar was used.
    /// The help message will be sent to `stdout`.
    ///
    /// **Note**: If the help is displayed due to an error (such as missing subcommands) it will
    /// be sent to `stderr` instead of `stdout`.
    DisplayHelp,
    /// Occurs when either an argument or a [`Subcommand`] is required, as defined by
    /// [`Command::arg_required_else_help`] , but the user did not provide
    /// one.
    DisplayHelpOnMissingArgumentOrSubcommand,
    /// Not a true "error" as it means `--version` or similar was used.
    /// The message will be sent to `stdout`.
    DisplayVersion,
    /// Represents an [I/O error].
    /// Can occur when writing to `stderr` or `stdout` or reading a configuration file.
    Io,
    /// Represents a [Format error] (which is a part of [`Display`]).
    /// Typically caused by writing to `stderr` or `stdout`.
    Format,
}

/// Provide an error message for this kind of error
function error_kind_as_str(k: ErrorKind) -> string? {
    match (k) {
        ErrorKind.InvalidValue => "one of the values isn't valid for an argument",
        ErrorKind.UnknownArgument => "unexpected argument found",
        ErrorKind.InvalidSubcommand => "unrecognized subcommand",
        ErrorKind.NoEquals => "equal is needed when assigning values to one of the arguments",
        ErrorKind.ValueValidation => "invalid value for one of the arguments",
        ErrorKind.TooManyValues => "unexpected value for an argument found",
        ErrorKind.TooFewValues => "more values required for an argument",
        ErrorKind.WrongNumberOfValues => "too many or too few values for an argument",
        ErrorKind.ArgumentConflict => "an argument cannot be used with one or more of the other specified arguments",
        ErrorKind.MissingRequiredArgument => "one or more required arguments were not provided",
        ErrorKind.MissingSubcommand => "a subcommand is required but one was not provided",
        ErrorKind.InvalidUtf8 => "invalid UTF-8 was detected in one or more arguments",
        _ => null,
    }
}

/// `impl Display for ErrorKind`
function error_kind_to_string(k: ErrorKind) -> string { error_kind_as_str(k) ?? "" }
