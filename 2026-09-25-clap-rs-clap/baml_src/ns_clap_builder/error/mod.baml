// Port of clap_builder/src/error/mod.rs
//
// Error reporting
//
//   mod context;  -> context.baml (ContextKind, ContextValue)
//   mod format;   -> format.baml  (ErrorFormatter, KindFormatter, RichFormatter)
//   mod kind;     -> kind.baml    (ErrorKind)
//
// Rust's `Error<F: ErrorFormatter = DefaultFormatter>` carries the formatter as
// a type parameter; here it is a stored function, switched with `apply<EF>()`.

/// `pub type Result<T, E = Error> = StdResult<T, E>;` -- BAML functions use
/// `-> T throws Error` instead.

/// `Message`: raw text or pre-formatted output
class Message {
    _raw: string?,
    _formatted: StyledStr?,

    function raw(s: string) -> Message { Message { _raw: s, _formatted: null } }
    function formatted(s: StyledStr) -> Message { Message { _raw: null, _formatted: s } }

    function format(self, cmd: Command, usage: StyledStr?) -> void {
        if let s: string = self._raw {
            let styled = format_error_message(s, cmd.get_styles(), cmd, usage);
            self._raw = null;
            self._formatted = styled;
        }
    }

    function get_formatted(self, styles: Styles) -> StyledStr {
        if let f: StyledStr = self._formatted {
            f
        } else {
            format_error_message(self._raw ?? "", styles, null, null)
        }
    }
}

/// `(ContextKind, ContextValue)`
class ContextEntry {
    kind: ContextKind,
    value: ContextValue,
}

/// Command Line Argument Parser Error
///
/// See [`Command::error`] to create an error.
class Error {
    _kind: ErrorKind,
    _context: FlatMap<ContextKind, ContextValue>,
    _message: Message?,
    /// `Option<Box<dyn error::Error>>`, kept as its `Display` rendering
    _source: string?,
    _help_flag: string?,
    _styles: Styles,
    _color_when: ColorChoice,
    _color_help_when: ColorChoice,
    _backtrace: root.backtrace.Backtrace?,
    /// `PhantomData<F>`: the `ErrorFormatter`
    _formatter: (Error) -> StyledStr throws never,

    /// Create an unformatted error
    ///
    /// This is for you need to pass the error up to
    /// a place that has access to the `Command` at which point you can call [`Error::format`].
    ///
    /// Prefer [`Command::error`] for generating errors.
    function raw(kind: ErrorKind, message: string) -> Error {
        Error.new(kind).set_message(Message.raw(message))
    }

    /// Create an error with a pre-defined message
    ///
    /// See also
    /// - [`Error::insert`]
    /// - [`Error::with_cmd`]
    function new(kind: ErrorKind) -> Error {
        Error {
            _kind: kind,
            _context: FlatMap.new(),
            _message: null,
            _source: null,
            _help_flag: null,
            _styles: Styles.plain(),
            _color_when: ColorChoice.Never,
            _color_help_when: ColorChoice.Never,
            _backtrace: if (features().debug) { root.backtrace.Backtrace.new() } else { null },
            _formatter: default_formatter(),
        }
    }

    /// Format the existing message with the Command's context
    function format(self, cmd: Command) -> Error {
        cmd._build_self(false);
        let usage = cmd.render_usage_();
        if let m: Message = self._message {
            m.format(cmd, usage);
        }
        self.with_cmd(cmd)
    }

    /// Apply [`Command`]'s formatting to the error
    ///
    /// Generally, this is used with [`Error::new`]
    function with_cmd(self, cmd: Command) -> Error {
        self.set_styles(cmd.get_styles())
            .set_color(cmd.get_color())
            .set_colored_help(cmd.color_help())
            .set_help_flag(get_help_flag(cmd))
    }

    /// Apply an alternative formatter to the error
    function apply<EF extends ErrorFormatter>(self) -> Error {
        self._formatter = (e: Error) -> StyledStr { (EF as ErrorFormatter).format_error(e) };
        self
    }

    /// Type of error for programmatic processing
    function kind(self) -> ErrorKind { self._kind }

    /// Additional information to further qualify the error
    function context(self) -> ContextEntry[] {
        let keys = self._context.get_keys();
        let values = self._context.get_values();
        baml.Array.generate(keys.length(), (i) -> { ContextEntry { kind: keys[i], value: values[i] } })
    }

    /// Lookup a piece of context
    function get(self, kind: ContextKind) -> ContextValue? {
        self._context.get(kind)
    }

    /// Insert a piece of context
    ///
    /// If this `ContextKind` is already present, its value is replaced and the old value is returned.
    function insert(self, kind: ContextKind, value: ContextValue) -> ContextValue? {
        self._context.insert(kind, value)
    }

    /// Remove a piece of context, return the old value if any
    ///
    /// The context is currently implemented in a vector, so `remove` takes
    /// linear time.
    function remove(self, kind: ContextKind) -> ContextValue? {
        self._context.remove(kind)
    }

    /// Should the message be written to `stdout` or not?
    function use_stderr(self) -> bool {
        self.stream() == Stream.Stderr
    }

    function stream(self) -> Stream {
        match (self.kind()) {
            ErrorKind.DisplayHelp | ErrorKind.DisplayVersion => Stream.Stdout,
            _ => Stream.Stderr,
        }
    }

    /// Returns the exit code that `.exit` will exit the process with.
    ///
    /// When the error's kind would print to `stderr` this returns `2`,
    /// else it returns `0`.
    function exit_code(self) -> int {
        if (self.use_stderr()) { USAGE_CODE() } else { SUCCESS_CODE() }
    }

    /// Prints the error and exits.
    ///
    /// Depending on the error kind, this either prints to `stderr` and exits with a status of `2`
    /// or prints to `stdout` and exits with a status of `0`.
    function exit(self) -> never {
        // Swallow broken pipe errors
        self.print();
        baml.sys.exit(self.exit_code())
    }

    /// Prints formatted and colored error to `stdout` or `stderr` according to its error kind
    function print(self) -> void {
        let style = self.formatted();
        let color_when = match (self.kind()) {
            ErrorKind.DisplayHelp | ErrorKind.DisplayHelpOnMissingArgumentOrSubcommand => self._color_help_when,
            _ => self._color_when,
        };
        let c = Colorizer.new(self.stream(), color_when).with_content(style);
        c.print();
    }

    /// Render the error message to a [`StyledStr`].
    function render(self) -> StyledStr {
        self.formatted()
    }

    function for_app(kind: ErrorKind, cmd: Command, styled: StyledStr) -> Error {
        Error.new(kind).set_message(Message.formatted(styled)).with_cmd(cmd)
    }

    function set_message(self, message: Message) -> Error {
        self._message = message;
        self
    }

    function set_source(self, source: string) -> Error {
        self._source = source;
        self
    }

    function set_styles(self, styles: Styles) -> Error {
        self._styles = styles;
        self
    }

    function set_color(self, color_when: ColorChoice) -> Error {
        self._color_when = color_when;
        self
    }

    function set_colored_help(self, color_help_when: ColorChoice) -> Error {
        self._color_help_when = color_help_when;
        self
    }

    function set_help_flag(self, help_flag: string?) -> Error {
        self._help_flag = help_flag;
        self
    }

    /// Does not verify if `ContextKind` is already present
    function insert_context_unchecked(self, kind: ContextKind, value: ContextValue) -> Error {
        self._context.insert_unchecked(kind, value);
        self
    }

    /// Does not verify if `ContextKind` is already present
    function extend_context_unchecked(self, context: ContextEntry[]) -> Error {
        for (let c in context) {
            self._context.insert_unchecked(c.kind, c.value);
        }
        self
    }

    function formatted(self) -> StyledStr {
        if let m: Message = self._message {
            m.get_formatted(self._styles)
        } else {
            let f = self._formatter;
            f(self)
        }
    }

    /// `impl Display for Error`
    implements baml.ToString {
        function to_string(self) -> string throws never {
            // Assuming `self.message` already has a trailing newline, from `try_help` or similar
            let out = self.formatted().to_string();
            if let bt: root.backtrace.Backtrace = self._backtrace {
                out = out + `\nBacktrace:\n${bt.debug()}\n`;
            }
            out
        }
    }
}

/// `DefaultFormatter`: `RichFormatter` with the `error-context` feature, else `KindFormatter`
function default_formatter() -> (Error) -> StyledStr throws never {
    if (features().error_context) {
        (e: Error) -> StyledStr { (RichFormatter as ErrorFormatter).format_error(e) }
    } else {
        (e: Error) -> StyledStr { (KindFormatter as ErrorFormatter).format_error(e) }
    }
}

/// `impl From<io::Error> for Error`
function error_from_io(e: baml.errors.Io) -> Error { Error.raw(ErrorKind.Io, e.message) }

function context_entry(kind: ContextKind, value: ContextValue) -> ContextEntry {
    ContextEntry { kind: kind, value: value }
}

function others_value(others: string[]) -> ContextValue {
    match (others.length()) {
        0 => ContextValueNone {},
        1 => ContextValueString { value: others[0] },
        _ => ContextValueStrings { value: others },
    }
}

function with_usage(err: Error, usage: StyledStr?) -> Error {
    if let u: StyledStr = usage {
        err.insert_context_unchecked(ContextKind.Usage, ContextValueStyledStr { value: u })
    } else {
        err
    }
}

function error_display_help(cmd: Command, styled: StyledStr) -> Error {
    Error.for_app(ErrorKind.DisplayHelp, cmd, styled)
}

function error_display_help_error(cmd: Command, styled: StyledStr) -> Error {
    Error.for_app(ErrorKind.DisplayHelpOnMissingArgumentOrSubcommand, cmd, styled)
}

function error_display_version(cmd: Command, styled: StyledStr) -> Error {
    Error.for_app(ErrorKind.DisplayVersion, cmd, styled)
}

function error_argument_conflict(cmd: Command, arg: string, others: string[], usage: StyledStr?) -> Error {
    let err = Error.new(ErrorKind.ArgumentConflict).with_cmd(cmd);

    if (features().error_context) {
        err = err.extend_context_unchecked([
            context_entry(ContextKind.InvalidArg, ContextValueString { value: arg }),
            context_entry(ContextKind.PriorArg, others_value(others)),
        ]);
        err = with_usage(err, usage);
    }

    err
}

function error_subcommand_conflict(cmd: Command, sub: string, others: string[], usage: StyledStr?) -> Error {
    let err = Error.new(ErrorKind.ArgumentConflict).with_cmd(cmd);

    if (features().error_context) {
        err = err.extend_context_unchecked([
            context_entry(ContextKind.InvalidSubcommand, ContextValueString { value: sub }),
            context_entry(ContextKind.PriorArg, others_value(others)),
        ]);
        err = with_usage(err, usage);
    }

    err
}

function error_empty_value(cmd: Command, good_vals: string[], arg: string) -> Error {
    error_invalid_value(cmd, "", good_vals, arg)
}

function error_no_equals(cmd: Command, arg: string, usage: StyledStr?) -> Error {
    let err = Error.new(ErrorKind.NoEquals).with_cmd(cmd);

    if (features().error_context) {
        err = err.extend_context_unchecked([context_entry(ContextKind.InvalidArg, ContextValueString { value: arg })]);
        err = with_usage(err, usage);
    }

    err
}

function error_invalid_value(cmd: Command, bad_val: string, good_vals: string[], arg: string) -> Error {
    let suggestion = did_you_mean(bad_val, good_vals).pop();
    let err = Error.new(ErrorKind.InvalidValue).with_cmd(cmd);

    if (features().error_context) {
        err = err.extend_context_unchecked([
            context_entry(ContextKind.InvalidArg, ContextValueString { value: arg }),
            context_entry(ContextKind.InvalidValue, ContextValueString { value: bad_val }),
            context_entry(ContextKind.ValidValue, ContextValueStrings { value: good_vals }),
        ]);
        if let s: string = suggestion {
            err = err.insert_context_unchecked(ContextKind.SuggestedValue, ContextValueString { value: s });
        }
    }

    err
}

function error_invalid_subcommand(cmd: Command, subcmd: string, did_you_mean: string[], name: string, suggested_trailing_arg: bool, usage: StyledStr?) -> Error {
    let styles = cmd.get_styles();
    let invalid = styles.get_invalid();
    let valid = styles.get_valid();
    let err = Error.new(ErrorKind.InvalidSubcommand).with_cmd(cmd);

    if (features().error_context) {
        let suggestions: StyledStr[] = [];
        if (suggested_trailing_arg) {
            let styled_suggestion = StyledStr.new();
            styled_suggestion.push_str("to pass '");
            styled_suggestion.push_styled_str(invalid, subcmd);
            styled_suggestion.push_str("' as a value, use '");
            styled_suggestion.push_styled_str(valid, `${name} -- ${subcmd}`);
            styled_suggestion.push_str("'");
            suggestions.push(styled_suggestion);
        }

        err = err.extend_context_unchecked([
            context_entry(ContextKind.InvalidSubcommand, ContextValueString { value: subcmd }),
            context_entry(ContextKind.SuggestedSubcommand, ContextValueStrings { value: did_you_mean }),
            context_entry(ContextKind.Suggested, ContextValueStyledStrs { value: suggestions }),
        ]);
        err = with_usage(err, usage);
    }

    err
}

function error_unrecognized_subcommand(cmd: Command, subcmd: string, usage: StyledStr?) -> Error {
    let err = Error.new(ErrorKind.InvalidSubcommand).with_cmd(cmd);

    if (features().error_context) {
        err = err.extend_context_unchecked([context_entry(ContextKind.InvalidSubcommand, ContextValueString { value: subcmd })]);
        err = with_usage(err, usage);
    }

    err
}

function error_missing_required_argument(cmd: Command, required: string[], usage: StyledStr?) -> Error {
    let err = Error.new(ErrorKind.MissingRequiredArgument).with_cmd(cmd);

    if (features().error_context) {
        err = err.extend_context_unchecked([context_entry(ContextKind.InvalidArg, ContextValueStrings { value: required })]);
        err = with_usage(err, usage);
    }

    err
}

function error_missing_subcommand(cmd: Command, parent: string, available: string[], usage: StyledStr?) -> Error {
    let err = Error.new(ErrorKind.MissingSubcommand).with_cmd(cmd);

    if (features().error_context) {
        err = err.extend_context_unchecked([
            context_entry(ContextKind.InvalidSubcommand, ContextValueString { value: parent }),
            context_entry(ContextKind.ValidSubcommand, ContextValueStrings { value: available }),
        ]);
        err = with_usage(err, usage);
    }

    err
}

function error_invalid_utf8(cmd: Command, usage: StyledStr?) -> Error {
    let err = Error.new(ErrorKind.InvalidUtf8).with_cmd(cmd);

    if (features().error_context) {
        err = with_usage(err, usage);
    }

    err
}

function error_too_many_values(cmd: Command, val: string, arg: string, usage: StyledStr?) -> Error {
    let err = Error.new(ErrorKind.TooManyValues).with_cmd(cmd);

    if (features().error_context) {
        err = err.extend_context_unchecked([
            context_entry(ContextKind.InvalidArg, ContextValueString { value: arg }),
            context_entry(ContextKind.InvalidValue, ContextValueString { value: val }),
        ]);
        err = with_usage(err, usage);
    }

    err
}

function error_too_few_values(cmd: Command, arg: string, min_vals: int, curr_vals: int, usage: StyledStr?) -> Error {
    let err = Error.new(ErrorKind.TooFewValues).with_cmd(cmd);

    if (features().error_context) {
        err = err.extend_context_unchecked([
            context_entry(ContextKind.InvalidArg, ContextValueString { value: arg }),
            context_entry(ContextKind.MinValues, ContextValueNumber { value: min_vals }),
            context_entry(ContextKind.ActualNumValues, ContextValueNumber { value: curr_vals }),
        ]);
        err = with_usage(err, usage);
    }

    err
}

function error_value_validation(arg: string, val: string, source: string) -> Error {
    let err = Error.new(ErrorKind.ValueValidation).set_source(source);

    if (features().error_context) {
        err = err.extend_context_unchecked([
            context_entry(ContextKind.InvalidArg, ContextValueString { value: arg }),
            context_entry(ContextKind.InvalidValue, ContextValueString { value: val }),
        ]);
    }

    err
}

function error_wrong_number_of_values(cmd: Command, arg: string, num_vals: int, curr_vals: int, usage: StyledStr?) -> Error {
    let err = Error.new(ErrorKind.WrongNumberOfValues).with_cmd(cmd);

    if (features().error_context) {
        err = err.extend_context_unchecked([
            context_entry(ContextKind.InvalidArg, ContextValueString { value: arg }),
            context_entry(ContextKind.ExpectedNumValues, ContextValueNumber { value: num_vals }),
            context_entry(ContextKind.ActualNumValues, ContextValueNumber { value: curr_vals }),
        ]);
        err = with_usage(err, usage);
    }

    err
}

/// `Option<(String, Option<String>)>`: suggested flag and the subcommand it belongs to
class SuggestedArg {
    arg: string,
    subcmd: string?,
}

function error_unknown_argument(cmd: Command, arg: string, did_you_mean: SuggestedArg?, suggested_trailing_arg: bool, usage: StyledStr?) -> Error {
    let styles = cmd.get_styles();
    let invalid = styles.get_invalid();
    let valid = styles.get_valid();
    let err = Error.new(ErrorKind.UnknownArgument).with_cmd(cmd);

    if (features().error_context) {
        let suggestions: StyledStr[] = [];
        if (suggested_trailing_arg) {
            let styled_suggestion = StyledStr.new();
            styled_suggestion.push_str("to pass '");
            styled_suggestion.push_styled_str(invalid, arg);
            styled_suggestion.push_str("' as a value, use '");
            styled_suggestion.push_styled_str(valid, `-- ${arg}`);
            styled_suggestion.push_str("'");
            suggestions.push(styled_suggestion);
        }

        err = err.extend_context_unchecked([context_entry(ContextKind.InvalidArg, ContextValueString { value: arg })]);
        err = with_usage(err, usage);
        if let dym: SuggestedArg = did_you_mean {
            if let sub: string = dym.subcmd {
                let styled_suggestion = StyledStr.new();
                styled_suggestion.push_str("'");
                styled_suggestion.push_styled_str(valid, `${sub} ${dym.arg}`);
                styled_suggestion.push_str("' exists");
                suggestions.push(styled_suggestion);
            } else {
                err = err.insert_context_unchecked(ContextKind.SuggestedArg, ContextValueString { value: dym.arg });
            }
        }
        if (suggestions.length() > 0) {
            err = err.insert_context_unchecked(ContextKind.Suggested, ContextValueStyledStrs { value: suggestions });
        }
    }

    err
}

function error_unnecessary_double_dash(cmd: Command, arg: string, usage: StyledStr?) -> Error {
    let styles = cmd.get_styles();
    let invalid = styles.get_invalid();
    let valid = styles.get_valid();
    let err = Error.new(ErrorKind.UnknownArgument).with_cmd(cmd);

    if (features().error_context) {
        let styled_suggestion = StyledStr.new();
        styled_suggestion.push_str("subcommand '");
        styled_suggestion.push_styled_str(valid, arg);
        styled_suggestion.push_str("' exists; to use it, remove the '");
        styled_suggestion.push_styled_str(invalid, "--");
        styled_suggestion.push_str("' before it");

        err = err.extend_context_unchecked([
            context_entry(ContextKind.InvalidArg, ContextValueString { value: arg }),
            context_entry(ContextKind.Suggested, ContextValueStyledStrs { value: [styled_suggestion] }),
        ]);
        err = with_usage(err, usage);
    }

    err
}
