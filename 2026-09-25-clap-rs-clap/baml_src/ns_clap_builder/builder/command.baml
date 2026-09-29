// Port of clap_builder/src/builder/command.rs

/// `(Str, bool)` / `(char, bool)`: alias name and whether it is visible
class CmdAlias {
    name: string,
    visible: bool,
}

/// `struct TermWidth(usize)`
class TermWidth { _0: int }

/// `struct MaxTermWidth(usize)`
class MaxTermWidth { _0: int }

/// Build a command-line interface.
///
/// This includes defining arguments, subcommands, parser behavior, and help output.
/// Once all configuration is complete,
/// the [`Command::get_matches`] family of methods starts the runtime-parsing
/// process. These methods then return information about the user supplied
/// arguments (or lack thereof).
///
/// When deriving a [`Parser`][crate::Parser], you can use
/// [`CommandFactory::command`][crate::CommandFactory::command] to access the
/// `Command`.
///
/// - [Basic API][crate::Command#basic-api]
/// - [Application-wide Settings][crate::Command#application-wide-settings]
/// - [Command-specific Settings][crate::Command#command-specific-settings]
/// - [Subcommand-specific Settings][crate::Command#subcommand-specific-settings]
/// - [Reflection][crate::Command#reflection]
///
/// # Examples
///
/// ```baml
/// let m = Command.new("My Program")
///     .author("Me, me@mail.com")
///     .version("1.0.2")
///     .about("Explains in brief what the program does")
///     .arg(
///         Arg.new("in_file")
///     )
///     .after_help("Longer explanation to appear after the options when \
///                  displaying the help information from --help or -h")
///     .get_matches();
///
/// // Your program logic starts here...
/// ```
class Command {
    _name: Str,
    _long_flag: Str?,
    _short_flag: string?,
    _display_name: string?,
    _bin_name: string?,
    _author: Str?,
    _version: Str?,
    _long_version: Str?,
    _about: StyledStr?,
    _long_about: StyledStr?,
    _before_help: StyledStr?,
    _before_long_help: StyledStr?,
    _after_help: StyledStr?,
    _after_long_help: StyledStr?,
    _aliases: CmdAlias[],
    _short_flag_aliases: CmdAlias[],
    _long_flag_aliases: CmdAlias[],
    _usage_str: StyledStr?,
    _usage_name: string?,
    _help_str: StyledStr?,
    _disp_ord: int?,
    _template: StyledStr?,
    _settings: AppFlags,
    _g_settings: AppFlags,
    _args: MKeyMap,
    _subcommands: Command[],
    _groups: ArgGroup[],
    _current_help_heading: Str?,
    _current_disp_ord: int?,
    _subcommand_value_name: Str?,
    _subcommand_heading: Str?,
    _external_value_parser: ValueParser?,
    _long_help_exists: bool,
    _deferred: ((Command) -> Command throws never)?,
    _ext: Extensions,
    _app_ext: Extensions,

    // ===== Basic API =====

    /// Creates a new instance of an `Command`.
    ///
    /// It is common, but not required, to use binary name as the `name`. This
    /// name will only be displayed to the user when they request to print
    /// version or help and usage information.
    ///
    /// See also [`command!`](crate::command!) and [`crate_name!`](crate::crate_name!).
    function new(name: Str) -> Command {
        let c = Command.default();
        c._name = name;
        c
    }

    /// `impl Default for Command`
    function default() -> Command {
        Command {
            _name: "",
            _long_flag: null,
            _short_flag: null,
            _display_name: null,
            _bin_name: null,
            _author: null,
            _version: null,
            _long_version: null,
            _about: null,
            _long_about: null,
            _before_help: null,
            _before_long_help: null,
            _after_help: null,
            _after_long_help: null,
            _aliases: [],
            _short_flag_aliases: [],
            _long_flag_aliases: [],
            _usage_str: null,
            _usage_name: null,
            _help_str: null,
            _disp_ord: null,
            _template: null,
            _settings: AppFlags.new(),
            _g_settings: AppFlags.new(),
            _args: MKeyMap.new(),
            _subcommands: [],
            _groups: [],
            _current_help_heading: null,
            _current_disp_ord: 0,
            _subcommand_value_name: null,
            _subcommand_heading: null,
            _external_value_parser: null,
            _long_help_exists: false,
            _deferred: null,
            _ext: Extensions.new(),
            _app_ext: Extensions.new(),
        }
    }

    /// Adds an [argument] to the list of valid possibilities.
    function arg(self, a: Arg) -> Command {
        self.arg_internal(a);
        self
    }

    function arg_internal(self, arg: Arg) -> void {
        if let current: int = self._current_disp_ord {
            if (!arg.is_positional()) {
                if (arg._disp_ord == null) { arg._disp_ord = current; }
                self._current_disp_ord = current + 1;
            }
        }

        if (!arg._help_heading_set) {
            arg._help_heading_set = true;
            arg._help_heading = self._current_help_heading;
        }
        self._args.push(arg);
    }

    /// Adds multiple [arguments] to the list of valid possibilities.
    function args(self, args: Arg[]) -> Command {
        for (let a in args) { self.arg_internal(a); }
        self
    }

    /// Allows one to mutate an [`Arg`] after it's been added to a [`Command`].
    ///
    /// # Panics
    ///
    /// If the argument is undefined
    function mut_arg(self, arg_id: string, f: (Arg) -> Arg throws never) -> Command {
        let a = self._args.remove_by_name(arg_id);
        if let arg: Arg = a {
            self._args.push(f(arg));
        } else {
            baml.sys.panic(`Argument \`${arg_id}\` is undefined`);
        }
        self
    }

    /// Allows one to mutate all [`Arg`]s after they've been added to a [`Command`].
    ///
    /// This does not affect the built-in `--help` or `--version` arguments.
    function mut_args(self, f: (Arg) -> Arg throws never) -> Command {
        self._args.mut_args(f);
        self
    }

    /// Allows one to mutate an [`ArgGroup`] after it's been added to a [`Command`].
    ///
    /// # Panics
    ///
    /// If the argument is undefined
    function mut_group(self, arg_id: string, f: (ArgGroup) -> ArgGroup throws never) -> Command {
        let index = self._groups.find_index((g) -> { g.get_id() == arg_id });
        if let i: int = index {
            let a = self._groups.remove_at(i);
            if let g: ArgGroup = a { self._groups.push(f(g)); }
        } else {
            baml.sys.panic(`Group \`${arg_id}\` is undefined`);
        }
        self
    }

    /// Allows one to mutate a [`Command`] after it's been added as a subcommand.
    ///
    /// This can be useful for modifying auto-generated arguments of nested subcommands with
    /// [`Command::mut_arg`].
    ///
    /// # Panics
    ///
    /// If the subcommand is undefined
    function mut_subcommand(self, name: string, f: (Command) -> Command throws never) -> Command {
        let pos = self._subcommands.find_index((s) -> { s._name == name });
        if let idx: int = pos {
            let sc = self._subcommands.remove_at(idx);
            if let s: Command = sc { self._subcommands.push(f(s)); }
        } else {
            baml.sys.panic(`Command \`${name}\` is undefined`);
        }
        self
    }

    /// Allows one to mutate all [`Command`]s after they've been added as subcommands.
    ///
    /// This does not affect the built-in `--help` or `--version` arguments.
    function mut_subcommands(self, f: (Command) -> Command throws never) -> Command {
        self._subcommands = self._subcommands.map(f);
        self
    }

    /// Adds an [`ArgGroup`] to the application.
    ///
    /// [`ArgGroup`]s are a family of related arguments.
    /// By placing them in a logical group, you can build easier requirement and exclusion rules.
    ///
    /// Example use cases:
    /// - Make an entire [`ArgGroup`] required, meaning that one (and *only*
    ///   one) argument from that group must be present at runtime.
    /// - Name an [`ArgGroup`] as a conflict to another argument.
    ///   Meaning any of the arguments that belong to that group will cause a failure if present with
    ///   the conflicting argument.
    /// - Ensure exclusion between arguments.
    /// - Extract a value from a group instead of determining exactly which argument was used.
    function group(self, group: ArgGroup) -> Command {
        self._groups.push(group);
        self
    }

    /// Adds multiple [`ArgGroup`]s to the [`Command`] at once.
    function groups(self, groups: ArgGroup[]) -> Command {
        for (let g in groups) { self._groups.push(g); }
        self
    }

    /// Adds a subcommand to the list of valid possibilities.
    ///
    /// Subcommands are effectively sub-[`Command`]s, because they can contain their own arguments,
    /// subcommands, version, usage, etc. They also function just like [`Command`]s, in that they get
    /// their own auto generated help, version, and usage.
    ///
    /// A subcommand's [`Command::name`] will be used for:
    /// - The argument the user passes in
    /// - Programmatically looking up the subcommand
    function subcommand(self, subcmd: Command) -> Command {
        self.subcommand_internal(subcmd)
    }

    function subcommand_internal(self, subcmd: Command) -> Command {
        if let current: int = self._current_disp_ord {
            if (subcmd._disp_ord == null) { subcmd._disp_ord = current; }
            self._current_disp_ord = current + 1;
        }
        self._subcommands.push(subcmd);
        self
    }

    /// Adds multiple subcommands to the list of valid possibilities.
    function subcommands(self, subcmds: Command[]) -> Command {
        let s = self;
        for (let sc in subcmds) { s = s.subcommand(sc); }
        s
    }

    /// Delay initialization for parts of the `Command`
    ///
    /// This is useful for large applications to delay definitions of subcommands until they are
    /// being invoked.
    ///
    /// Rust: `Command::defer`. `defer` is a BAML keyword, hence the trailing underscore.
    function defer_(self, deferred: (Command) -> Command throws never) -> Command {
        self._deferred = deferred;
        self
    }

    /// Catch problems earlier in the development cycle.
    ///
    /// Most error states are handled as asserts under the assumption they are programming mistake
    /// and not something to handle at runtime.  Rather than relying on tests (manual or automated)
    /// that exhaustively test your CLI to ensure the asserts are evaluated, this will run those
    /// asserts in a way convenient for running as a test.
    function debug_assert(self) -> void {
        self.build();
    }

    /// Custom error message for post-parsing validation
    ///
    /// **Note:** this will ensure the `Command` has been sufficiently [built][Command::build] for any
    /// relevant context, including usage.
    ///
    /// # Panics
    ///
    /// If contradictory arguments or settings exist (debug builds).
    function error(self, kind: ErrorKind, message: string) -> Error {
        Error.raw(kind, message).format(self)
    }

    /// Parse [`env::args_os`], [exiting][Error::exit] on failure.
    ///
    /// # Panics
    ///
    /// If contradictory arguments or settings exist (debug builds).
    function get_matches(self) -> ArgMatches {
        self.get_matches_from(root.clap_lex.args_os())
    }

    /// Parse [`env::args_os`], [exiting][Error::exit] on failure.
    ///
    /// Like [`Command::get_matches`] but doesn't consume the `Command`.
    function get_matches_mut(self) -> ArgMatches {
        self.try_get_matches_from_mut(root.clap_lex.args_os()) catch (e) {
            let err: Error => err.exit(),
        }
    }

    /// Parse [`env::args_os`], returning a [`clap::Result`] on failure.
    ///
    /// **NOTE:** This method WILL NOT exit when `--help` or `--version` (or short versions) are
    /// used. It will return a [`clap::Error`], where the [`kind`] is a
    /// [`ErrorKind::DisplayHelp`] or [`ErrorKind::DisplayVersion`] respectively. You must call
    /// [`Error::exit`] or perform a [`std::process::exit`].
    function try_get_matches(self) -> ArgMatches throws Error {
        // Start the parsing
        self.try_get_matches_from(root.clap_lex.args_os())
    }

    /// Parse the specified arguments, [exiting][Error::exit] on failure.
    ///
    /// **NOTE:** The first argument will be parsed as the binary name unless
    /// [`Command::no_binary_name`] is used.
    function get_matches_from(self, itr: string[]) -> ArgMatches {
        self.try_get_matches_from_mut(itr) catch (e) {
            let err: Error => err.exit(),
        }
    }

    /// Parse the specified arguments, returning a [`clap::Result`] on failure.
    ///
    /// **NOTE:** This method WILL NOT exit when `--help` or `--version` (or short versions) are
    /// used. It will return a [`clap::Error`], where the [`kind`] is a [`ErrorKind::DisplayHelp`]
    /// or [`ErrorKind::DisplayVersion`] respectively. You must call [`Error::exit`] or
    /// perform a [`std::process::exit`] yourself.
    ///
    /// **NOTE:** The first argument will be parsed as the binary name unless
    /// [`Command::no_binary_name`] is used.
    function try_get_matches_from(self, itr: string[]) -> ArgMatches throws Error {
        self.try_get_matches_from_mut(itr)
    }

    /// Parse the specified arguments, returning a [`clap::Result`] on failure.
    ///
    /// Like [`Command::try_get_matches_from`] but doesn't consume the `Command`.
    function try_get_matches_from_mut(self, itr: string[]) -> ArgMatches throws Error {
        let raw_args = root.clap_lex.RawArgs.new(itr);
        let cursor = raw_args.cursor();

        if (self._settings.is_set(AppSettings.Multicall)) {
            if let argv0: string = raw_args.next_os(cursor) {
                let command = file_stem(argv0);
                if (!command.is_empty()) {
                    // Reinserting command into arguments so subcommand parser matches it
                    raw_args.insert(cursor, [command]);
                    // Clearing name and bin_name so that displayed command name starts with applet name
                    self._name = "";
                    self._bin_name = null;
                    return self._do_parse(raw_args, cursor);
                }
            }
        }

        // Get the name of the program (argument 1 of env::args()) and determine the
        // actual file
        // that was used to execute the program. This is because a program called
        // ./target/release/my_prog -a
        // will have two arguments, './target/release/my_prog', '-a' but we don't want
        // to display
        // the full path when displaying help messages and such
        if (!self._settings.is_set(AppSettings.NoBinaryName)) {
            if let name: string = raw_args.next_os(cursor) {
                let f = file_name(name);
                if (!f.is_empty()) {
                    if (self._bin_name == null) {
                        self._bin_name = f;
                    }
                }
            }
        }

        self._do_parse(raw_args, cursor)
    }

    /// Prints the short help message (`-h`) to [`io::stdout()`].
    ///
    /// See also [`Command::print_long_help`].
    function print_help(self) -> void {
        self._build_self(false);
        let color = self.color_help();

        let styled = StyledStr.new();
        let usage = Usage.new(self);
        write_help(styled, self, usage, false);

        let c = Colorizer.new(Stream.Stdout, color).with_content(styled);
        c.print();
    }

    /// Prints the long help message (`--help`) to [`io::stdout()`].
    ///
    /// See also [`Command::print_help`].
    function print_long_help(self) -> void {
        self._build_self(false);
        let color = self.color_help();

        let styled = StyledStr.new();
        let usage = Usage.new(self);
        write_help(styled, self, usage, true);

        let c = Colorizer.new(Stream.Stdout, color).with_content(styled);
        c.print();
    }

    /// Render the short help message (`-h`) to a [`StyledStr`]
    ///
    /// See also [`Command::render_long_help`].
    function render_help(self) -> StyledStr {
        self._build_self(false);

        let styled = StyledStr.new();
        let usage = Usage.new(self);
        write_help(styled, self, usage, false);
        styled
    }

    /// Render the long help message (`--help`) to a [`StyledStr`].
    ///
    /// See also [`Command::render_help`].
    function render_long_help(self) -> StyledStr {
        self._build_self(false);

        let styled = StyledStr.new();
        let usage = Usage.new(self);
        write_help(styled, self, usage, true);
        styled
    }

    /// Version message rendered as if the user ran `-V`.
    ///
    /// See also [`Command::render_long_version`].
    ///
    /// ### Coloring
    ///
    /// This function does not try to color the message nor it inserts any [ANSI escape codes].
    function render_version(self) -> string { self._render_version(false) }

    /// Version message rendered as if the user ran `--version`.
    ///
    /// See also [`Command::render_version`].
    function render_long_version(self) -> string { self._render_version(true) }

    /// Usage statement
    function render_usage(self) -> StyledStr {
        self.render_usage_() ?? StyledStr.new()
    }

    function render_usage_(self) -> StyledStr? {
        // If there are global arguments, or settings we need to propagate them down to subcommands
        // before parsing incase we run into a subcommand
        self._build_self(false);

        Usage.new(self).create_usage_with_title([])
    }

    // ===== Application-wide Settings =====
    //
    // These settings will apply to the top-level command and all subcommands, by default.  Some
    // settings can be overridden in subcommands.

    /// Specifies that the parser should not assume the first argument passed is the binary name.
    ///
    /// This is normally the case when using a "daemon" style mode.  For shells / REPLs, see
    /// [`Command::multicall`][Command::multicall].
    function no_binary_name(self, yes: bool) -> Command {
        if (yes) { self.global_setting(AppSettings.NoBinaryName) } else { self.unset_global_setting(AppSettings.NoBinaryName) }
    }

    /// Try not to fail on parse errors, like missing option values.
    ///
    /// **NOTE:** This choice is propagated to all child subcommands.
    function ignore_errors(self, yes: bool) -> Command {
        if (yes) { self.global_setting(AppSettings.IgnoreErrors) } else { self.unset_global_setting(AppSettings.IgnoreErrors) }
    }

    /// Replace prior occurrences of arguments rather than error
    ///
    /// For any argument that would conflict with itself by default (e.g.
    /// [`ArgAction::Set`], it will now override itself.
    ///
    /// This is the equivalent to saying the `foo` arg using [`Arg::overrides_with("foo")`] for all
    /// defined arguments.
    ///
    /// **NOTE:** This choice is propagated to all child subcommands.
    function args_override_self(self, yes: bool) -> Command {
        if (yes) { self.global_setting(AppSettings.AllArgsOverrideSelf) } else { self.unset_global_setting(AppSettings.AllArgsOverrideSelf) }
    }

    /// Disables the automatic delimiting of values after `--` or when [`Arg::trailing_var_arg`]
    /// was used.
    ///
    /// **NOTE:** The same thing can be done manually by setting the final positional argument to
    /// [`Arg::value_delimiter(None)`]. Using this setting is safer, because it's easier to locate
    /// when making changes.
    ///
    /// **NOTE:** This choice is propagated to all child subcommands.
    function dont_delimit_trailing_values(self, yes: bool) -> Command {
        if (yes) { self.global_setting(AppSettings.DontDelimitTrailingValues) } else { self.unset_global_setting(AppSettings.DontDelimitTrailingValues) }
    }

    /// Sets when to color output.
    ///
    /// To customize how the output is styled, see [`Command::styles`].
    ///
    /// **NOTE:** This choice is propagated to all child subcommands.
    ///
    /// **NOTE:** Default behaviour is [`ColorChoice::Auto`].
    function color(self, color: ColorChoice) -> Command {
        let cmd = self
            .unset_global_setting(AppSettings.ColorAuto)
            .unset_global_setting(AppSettings.ColorAlways)
            .unset_global_setting(AppSettings.ColorNever);
        match (color) {
            ColorChoice.Auto => cmd.global_setting(AppSettings.ColorAuto),
            ColorChoice.Always => cmd.global_setting(AppSettings.ColorAlways),
            ColorChoice.Never => cmd.global_setting(AppSettings.ColorNever),
        }
    }

    /// Sets the [`Styles`] for terminal output
    ///
    /// **NOTE:** This choice is propagated to all child subcommands.
    ///
    /// **NOTE:** Default behaviour is [`Styles::default`].
    function styles(self, styles: Styles) -> Command {
        self._app_ext.set<Styles>(styles);
        self
    }

    /// Sets the terminal width at which to wrap help messages.
    ///
    /// Using `0` will ignore terminal widths and use source formatting.
    ///
    /// Defaults to current terminal width when `wrap_help` feature flag is enabled.  If current
    /// width cannot be determined, the default is 100.
    ///
    /// **`unstable-v5` feature**: Defaults to unbound, being subject to
    /// [`Command::max_term_width`].
    ///
    /// **NOTE:** This setting applies globally and *not* on a per-command basis.
    ///
    /// **NOTE:** This requires the `wrap_help` feature
    function term_width(self, width: int) -> Command {
        self._app_ext.set<TermWidth>(TermWidth { _0: width });
        self
    }

    /// Limit the line length for wrapping help when using the current terminal's width.
    ///
    /// This only applies when [`term_width`][Command::term_width] is unset so that the current
    /// terminal's width will be used.  See [`Command::term_width`] for more details.
    ///
    /// Using `0` will ignore this, always respecting [`Command::term_width`] (default).
    ///
    /// **`unstable-v5` feature**: Defaults to 100.
    ///
    /// **NOTE:** This setting applies globally and *not* on a per-command basis.
    ///
    /// **NOTE:** This requires the `wrap_help` feature
    function max_term_width(self, width: int) -> Command {
        self._app_ext.set<MaxTermWidth>(MaxTermWidth { _0: width });
        self
    }

    /// Disables `-V` and `--version` flag.
    function disable_version_flag(self, yes: bool) -> Command {
        if (yes) { self.global_setting(AppSettings.DisableVersionFlag) } else { self.unset_global_setting(AppSettings.DisableVersionFlag) }
    }

    /// Specifies to use the version of the current command for all [`subcommands`].
    ///
    /// Defaults to `false`; subcommands have independent version strings from their parents.
    ///
    /// **NOTE:** This choice is propagated to all child subcommands.
    function propagate_version(self, yes: bool) -> Command {
        if (yes) { self.global_setting(AppSettings.PropagateVersion) } else { self.unset_global_setting(AppSettings.PropagateVersion) }
    }

    /// Places the help string for all arguments and subcommands on the line after them.
    ///
    /// **NOTE:** This choice is propagated to all child subcommands.
    function next_line_help(self, yes: bool) -> Command {
        if (yes) { self.global_setting(AppSettings.NextLineHelp) } else { self.unset_global_setting(AppSettings.NextLineHelp) }
    }

    /// Disables `-h` and `--help` flag.
    ///
    /// **NOTE:** This choice is propagated to all child subcommands.
    function disable_help_flag(self, yes: bool) -> Command {
        if (yes) { self.global_setting(AppSettings.DisableHelpFlag) } else { self.unset_global_setting(AppSettings.DisableHelpFlag) }
    }

    /// Disables the `help` [`subcommand`].
    ///
    /// **NOTE:** This choice is propagated to all child subcommands.
    function disable_help_subcommand(self, yes: bool) -> Command {
        if (yes) { self.global_setting(AppSettings.DisableHelpSubcommand) } else { self.unset_global_setting(AppSettings.DisableHelpSubcommand) }
    }

    /// Disables colorized help messages.
    ///
    /// **NOTE:** This choice is propagated to all child subcommands.
    function disable_colored_help(self, yes: bool) -> Command {
        if (yes) { self.global_setting(AppSettings.DisableColoredHelp) } else { self.unset_global_setting(AppSettings.DisableColoredHelp) }
    }

    /// Panic if help descriptions are omitted.
    ///
    /// **NOTE:** When deriving [`Parser`][crate::Parser], you could instead check this at
    /// compile-time with `#![deny(missing_docs)]`
    ///
    /// **NOTE:** This choice is propagated to all child subcommands.
    function help_expected(self, yes: bool) -> Command {
        if (yes) { self.global_setting(AppSettings.HelpExpected) } else { self.unset_global_setting(AppSettings.HelpExpected) }
    }

    /// Deprecated: This is now the default behavior
    function dont_collapse_args_in_usage(self, _yes: bool) -> Command { self }

    /// Tells `clap` *not* to print possible values when displaying help information.
    ///
    /// This can be useful if there are many values, or they are explained elsewhere.
    ///
    /// To set this per argument, see
    /// [`Arg::hide_possible_values`][crate::Arg::hide_possible_values].
    ///
    /// **NOTE:** This choice is propagated to all child subcommands.
    function hide_possible_values(self, yes: bool) -> Command {
        if (yes) { self.global_setting(AppSettings.HidePossibleValues) } else { self.unset_global_setting(AppSettings.HidePossibleValues) }
    }

    /// Allow partial matches of long arguments or their [aliases].
    ///
    /// For example, to match an argument named `--test`, one could use `--t`, `--te`, `--tes`, and
    /// `--test`.
    ///
    /// **NOTE:** The match *must not* be ambiguous at all in order to succeed. i.e. to match
    /// `--te` to `--test` there could not also be another argument or alias `--temp` because both
    /// start with `--te`
    ///
    /// **NOTE:** This choice is propagated to all child subcommands.
    function infer_long_args(self, yes: bool) -> Command {
        if (yes) { self.global_setting(AppSettings.InferLongArgs) } else { self.unset_global_setting(AppSettings.InferLongArgs) }
    }

    /// Allow partial matches of [subcommand] names and their [aliases].
    ///
    /// For example, to match a subcommand named `test`, one could use `t`, `te`, `tes`, and
    /// `test`.
    ///
    /// **NOTE:** The match *must not* be ambiguous at all in order to succeed. i.e. to match `te`
    /// to `test` there could not also be a subcommand or alias `temp` because both start with `te`
    ///
    /// **WARNING:** This setting can interfere with [positional/free arguments], take care when
    /// designing CLIs which allow inferred subcommands and have potential positional/free
    /// arguments whose values could start with the same characters as subcommands. If this is the
    /// case, it's recommended to use settings such as [`Command::args_conflicts_with_subcommands`] in
    /// conjunction with this setting.
    ///
    /// **NOTE:** This choice is propagated to all child subcommands.
    function infer_subcommands(self, yes: bool) -> Command {
        if (yes) { self.global_setting(AppSettings.InferSubcommands) } else { self.unset_global_setting(AppSettings.InferSubcommands) }
    }

    // ===== Command-specific Settings =====
    //
    // These apply only to the current command and are not inherited by subcommands.

    /// (Re)Sets the program's name.
    ///
    /// See [`Command::new`] for more details.
    function name(self, name: Str) -> Command {
        self._name = name;
        self
    }

    /// Overrides the runtime-determined name of the binary for help and error messages.
    ///
    /// This should only be used when absolutely necessary, such as when the binary name for your
    /// application is misleading, or perhaps *not* how the user should invoke your program.
    ///
    /// **Pro-tip:** When building things such as third party `cargo`
    /// subcommands, this setting **should** be used!
    ///
    /// **NOTE:** This *does not* change or set the name of the binary file on
    /// disk. It only changes what clap thinks the name is for the purposes of
    /// error or help messages.
    function bin_name(self, name: string?) -> Command {
        self._bin_name = name;
        self
    }

    /// Overrides the runtime-determined display name of the program for help and error messages.
    function display_name(self, name: string?) -> Command {
        self._display_name = name;
        self
    }

    /// Sets the author(s) for the help message.
    ///
    /// **Pro-tip:** Use `clap`s convenience macro [`crate_authors!`] to
    /// automatically set your application's author(s) to the same thing as your
    /// crate at compile time.
    ///
    /// **NOTE:** A custom [`help_template`][Command::help_template] is needed for author to show
    /// up.
    function author(self, author: Str?) -> Command {
        self._author = author;
        self
    }

    /// Sets the program's description for the short help (`-h`).
    ///
    /// If [`Command::long_about`] is not specified, this message will be displayed for `--help`.
    ///
    /// See also [`crate_description!`](crate::crate_description!).
    function about(self, about: StyledStr | string | null) -> Command {
        self._about = into_styled_opt(about);
        self
    }

    /// Sets the program's description for the long help (`--help`).
    ///
    /// If not set, [`Command::about`] will be used for long help in addition to short help
    /// (`-h`).
    ///
    /// **NOTE:** Only [`Command::about`] (short format) is used in completion
    /// script generation in order to be concise.
    function long_about(self, long_about: StyledStr | string | null) -> Command {
        self._long_about = into_styled_opt(long_about);
        self
    }

    /// Free-form help text for after auto-generated short help (`-h`).
    ///
    /// This is often used to describe how to use the arguments, caveats to be noted, or license
    /// and contact information.
    ///
    /// If [`Command::after_long_help`] is not specified, this message will be displayed for `--help`.
    function after_help(self, help: StyledStr | string | null) -> Command {
        self._after_help = into_styled_opt(help);
        self
    }

    /// Free-form help text for after auto-generated long help (`--help`).
    ///
    /// This is often used to describe how to use the arguments, caveats to be noted, or license
    /// and contact information.
    ///
    /// If not set, [`Command::after_help`] will be used for long help in addition to short help
    /// (`-h`).
    function after_long_help(self, help: StyledStr | string | null) -> Command {
        self._after_long_help = into_styled_opt(help);
        self
    }

    /// Free-form help text for before auto-generated short help (`-h`).
    ///
    /// This is often used for header, copyright, or license information.
    ///
    /// If [`Command::before_long_help`] is not specified, this message will be displayed for `--help`.
    function before_help(self, help: StyledStr | string | null) -> Command {
        self._before_help = into_styled_opt(help);
        self
    }

    /// Free-form help text for before auto-generated long help (`--help`).
    ///
    /// This is often used for header, copyright, or license information.
    ///
    /// If not set, [`Command::before_help`] will be used for long help in addition to short help
    /// (`-h`).
    function before_long_help(self, help: StyledStr | string | null) -> Command {
        self._before_long_help = into_styled_opt(help);
        self
    }

    /// Sets the version for the short version (`-V`) and help messages.
    ///
    /// If [`Command::long_version`] is not specified, this message will be displayed for `--version`.
    ///
    /// **Pro-tip:** Use `clap`s convenience macro [`crate_version!`] to
    /// automatically set your application's version to the same thing as your
    /// crate at compile time.
    function version(self, ver: Str?) -> Command {
        self._version = ver;
        self
    }

    /// Sets the version for the long version (`--version`) and help messages.
    ///
    /// If [`Command::version`] is not specified, this message will be displayed for `-V`.
    function long_version(self, ver: Str?) -> Command {
        self._long_version = ver;
        self
    }

    /// Overrides the `clap` generated usage string for help and error messages.
    ///
    /// **NOTE:** Using this setting disables `clap`s "context-aware" usage
    /// strings. After this setting is set, this will be *the only* usage string
    /// displayed to the user!
    ///
    /// **NOTE:** Multiple usage lines may be present in the usage argument, but
    /// some rules need to be followed to ensure the usage lines are formatted
    /// correctly by the default help formatter:
    ///
    /// - Do not indent the first usage line.
    /// - Indent all subsequent usage lines with seven spaces.
    /// - The last line must not end with a newline.
    function override_usage(self, usage: StyledStr | string | null) -> Command {
        self._usage_str = into_styled_opt(usage);
        self
    }

    /// Overrides the `clap` generated help message (both `-h` and `--help`).
    ///
    /// This should only be used when the auto-generated message does not suffice.
    ///
    /// **NOTE:** This **only** replaces the help message for the current
    /// command, meaning if you are using subcommands, those help messages will
    /// still be auto-generated unless you specify a [`Command::override_help`] for
    /// them as well.
    function override_help(self, help: StyledStr | string | null) -> Command {
        self._help_str = into_styled_opt(help);
        self
    }

    /// Sets the help template to be used, overriding the default format.
    ///
    /// Tags are given inside curly brackets.
    ///
    /// Valid tags are:
    ///
    ///   * `{name}`                - Display name for the (sub-)command.
    ///   * `{bin}`                 - Binary name.(deprecated)
    ///   * `{version}`             - Version number.
    ///   * `{author}`              - Author information.
    ///   * `{author-with-newline}` - Author followed by `\n`.
    ///   * `{author-section}`      - Author preceded and followed by `\n`.
    ///   * `{about}`               - General description (from [`Command::about`] or
    ///     [`Command::long_about`]).
    ///   * `{about-with-newline}`  - About followed by `\n`.
    ///   * `{about-section}`       - About preceded and followed by '\n'.
    ///   * `{usage-heading}`       - Automatically generated usage heading.
    ///   * `{usage}`               - Automatically generated or given usage string.
    ///   * `{all-args}`            - Help for all arguments (options, flags, positional
    ///     arguments, and subcommands) including titles.
    ///   * `{options}`             - Help for options.
    ///   * `{positionals}`         - Help for positional arguments.
    ///   * `{subcommands}`         - Help for subcommands.
    ///   * `{tab}`                 - Standard tab sized used within clap
    ///   * `{after-help}`          - Help from [`Command::after_help`] or [`Command::after_long_help`].
    ///   * `{before-help}`         - Help from [`Command::before_help`] or [`Command::before_long_help`].
    function help_template(self, s: StyledStr | string | null) -> Command {
        self._template = into_styled_opt(s);
        self
    }

    function setting(self, setting: AppSettings) -> Command {
        self._settings.set(setting);
        self
    }

    function unset_setting(self, setting: AppSettings) -> Command {
        self._settings.unset(setting);
        self
    }

    function global_setting(self, setting: AppSettings) -> Command {
        self._settings.set(setting);
        self._g_settings.set(setting);
        self
    }

    function unset_global_setting(self, setting: AppSettings) -> Command {
        self._settings.unset(setting);
        self._g_settings.unset(setting);
        self
    }

    /// Flatten subcommand help into the current command's help
    ///
    /// This shows a summary of subcommands within the usage and help for the current command, similar to
    /// `git stash --help` showing information on `push`, `pop`, etc.
    /// To see more information, a user can still pass `--help` to the individual subcommands.
    function flatten_help(self, yes: bool) -> Command {
        if (yes) { self.setting(AppSettings.FlattenHelp) } else { self.unset_setting(AppSettings.FlattenHelp) }
    }

    /// Set the default section heading for future args.
    ///
    /// This will be used for any arg that hasn't had [`Arg::help_heading`] called.
    ///
    /// This is useful if the default `Options` or `Arguments` headings are
    /// not specific enough for one's use case.
    ///
    /// For subcommands, see [`Command::subcommand_help_heading`]
    function next_help_heading(self, heading: Str?) -> Command {
        self._current_help_heading = heading;
        self
    }

    /// Change the starting value for assigning future display orders for args.
    ///
    /// This will be used for any arg that hasn't had [`Arg::display_order`] called.
    function next_display_order(self, disp_ord: int?) -> Command {
        self._current_disp_ord = disp_ord;
        self
    }

    /// Exit gracefully if no arguments are present (e.g. `$ myprog`).
    ///
    /// **NOTE:** [`subcommands`] count as arguments
    function arg_required_else_help(self, yes: bool) -> Command {
        if (yes) { self.setting(AppSettings.ArgRequiredElseHelp) } else { self.unset_setting(AppSettings.ArgRequiredElseHelp) }
    }

    /// Deprecated, replaced with [`Arg::allow_hyphen_values`]
    function allow_hyphen_values(self, yes: bool) -> Command {
        if (yes) { self.setting(AppSettings.AllowHyphenValues) } else { self.unset_setting(AppSettings.AllowHyphenValues) }
    }

    /// Deprecated, replaced with [`Arg::allow_negative_numbers`]
    function allow_negative_numbers(self, yes: bool) -> Command {
        if (yes) { self.setting(AppSettings.AllowNegativeNumbers) } else { self.unset_setting(AppSettings.AllowNegativeNumbers) }
    }

    /// Deprecated, replaced with [`Arg::trailing_var_arg`]
    function trailing_var_arg(self, yes: bool) -> Command {
        if (yes) { self.setting(AppSettings.TrailingVarArg) } else { self.unset_setting(AppSettings.TrailingVarArg) }
    }

    /// Allows one to implement two styles of CLIs where positionals can be used out of order.
    ///
    /// The first example is a CLI where the second to last positional argument is optional, but
    /// the final positional argument is required. Such as `$ prog [optional] <required>` where one
    /// of the two following usages is allowed:
    ///
    /// * `$ prog [optional] <required>`
    /// * `$ prog <required>`
    ///
    /// This would otherwise not be allowed. This is useful when `[optional]` has a default value.
    ///
    /// **Note:** when using this style of "missing positionals" the final positional *must* be
    /// [required] if `--` will not be used to skip to the final positional argument.
    ///
    /// **Note:** This style also only allows a single positional argument to be "skipped" without
    /// the use of `--`. To skip more than one, you must use [the `--` syntax].
    ///
    /// The second example is when one wants to skip multiple optional positional arguments, and use
    /// of the `--` operator is OK (but not required if all arguments will be specified anyways).
    ///
    /// For example, imagine a CLI which has three positional arguments `[foo] [bar] [baz]...` where
    /// `baz` accepts multiple values (similar to man `ARGS...` style training arguments).
    ///
    /// With this setting the following invocations are posisble:
    ///
    /// * `$ prog foo bar baz1 baz2 baz3`
    /// * `$ prog foo -- baz1 baz2 baz3`
    /// * `$ prog -- baz1 baz2 baz3`
    function allow_missing_positional(self, yes: bool) -> Command {
        if (yes) { self.setting(AppSettings.AllowMissingPositional) } else { self.unset_setting(AppSettings.AllowMissingPositional) }
    }

    // ===== Subcommand-specific Settings =====

    /// Sets the short version of the subcommand flag without the preceding `-`.
    ///
    /// Allows the subcommand to be used as if it were an [`Arg::short`].
    function short_flag(self, short: string?) -> Command {
        self._short_flag = short;
        self
    }

    /// Sets the long version of the subcommand flag without the preceding `--`.
    ///
    /// Allows this subcommand to be used as if it were an [`Arg::long`].
    ///
    /// **NOTE:** Any leading `-` characters will be stripped.
    function long_flag(self, long: Str) -> Command {
        self._long_flag = long;
        self
    }

    /// Sets a hidden alias to this subcommand.
    ///
    /// This allows the subcommand to be accessed via *either* the original name, or this given
    /// alias. This is more efficient and easier than creating multiple hidden subcommands as one
    /// only needs to check for the existence of this command, and not all aliased variants.
    ///
    /// **NOTE:** Aliases defined with this method are *hidden* from the help
    /// message. If you're looking for aliases that will be displayed in the help
    /// message, see [`Command::visible_alias`].
    ///
    /// **NOTE:** When using aliases and checking for the existence of a
    /// particular subcommand within an [`ArgMatches`] struct, one only needs to
    /// search for the original name and not all aliases.
    function alias(self, name: Str?) -> Command {
        if let n: string = name {
            self._aliases.push(CmdAlias { name: n, visible: false });
        } else {
            self._aliases.clear();
        }
        self
    }

    /// Add an alias, which functions as  "hidden" short flag subcommand
    function short_flag_alias(self, name: string?) -> Command {
        if let n: string = name {
            assert.is_true(n != "-");
            self._short_flag_aliases.push(CmdAlias { name: n, visible: false });
        } else {
            self._short_flag_aliases.clear();
        }
        self
    }

    /// Add an alias, which functions as a "hidden" long flag subcommand.
    function long_flag_alias(self, name: Str?) -> Command {
        if let n: string = name {
            self._long_flag_aliases.push(CmdAlias { name: n, visible: false });
        } else {
            self._long_flag_aliases.clear();
        }
        self
    }

    /// Sets multiple hidden aliases to this subcommand.
    function aliases(self, names: Str[]) -> Command {
        for (let n in names) { self._aliases.push(CmdAlias { name: n, visible: false }); }
        self
    }

    /// Add aliases, which function as "hidden" short flag subcommands.
    function short_flag_aliases(self, names: string[]) -> Command {
        for (let s in names) {
            assert.is_true(s != "-");
            self._short_flag_aliases.push(CmdAlias { name: s, visible: false });
        }
        self
    }

    /// Add aliases, which function as "hidden" long flag subcommands.
    function long_flag_aliases(self, names: Str[]) -> Command {
        for (let s in names) { self._long_flag_aliases.push(CmdAlias { name: s, visible: false }); }
        self
    }

    /// Sets a visible alias to this subcommand.
    ///
    /// This allows the subcommand to be accessed via *either* the
    /// original name or the given alias. This is more efficient and easier
    /// than creating hidden subcommands as one only needs to check for
    /// the existence of this command and not all aliased variants.
    ///
    /// **NOTE:** The alias defined is displayed in the help message.
    function visible_alias(self, name: Str?) -> Command {
        if let n: string = name {
            self._aliases.push(CmdAlias { name: n, visible: true });
        } else {
            self._aliases.clear();
        }
        self
    }

    /// Add an alias, which functions as  "visible" short flag subcommand
    function visible_short_flag_alias(self, name: string?) -> Command {
        if let n: string = name {
            assert.is_true(n != "-");
            self._short_flag_aliases.push(CmdAlias { name: n, visible: true });
        } else {
            self._short_flag_aliases.clear();
        }
        self
    }

    /// Add an alias, which functions as a "visible" long flag subcommand.
    function visible_long_flag_alias(self, name: Str?) -> Command {
        if let n: string = name {
            self._long_flag_aliases.push(CmdAlias { name: n, visible: true });
        } else {
            self._long_flag_aliases.clear();
        }
        self
    }

    /// Sets multiple visible aliases to this subcommand.
    function visible_aliases(self, names: Str[]) -> Command {
        for (let n in names) { self._aliases.push(CmdAlias { name: n, visible: true }); }
        self
    }

    /// Add aliases, which function as *visible* short flag subcommands.
    function visible_short_flag_aliases(self, names: string[]) -> Command {
        for (let s in names) {
            assert.is_true(s != "-");
            self._short_flag_aliases.push(CmdAlias { name: s, visible: true });
        }
        self
    }

    /// Add aliases, which function as *visible* long flag subcommands.
    function visible_long_flag_aliases(self, names: Str[]) -> Command {
        for (let s in names) { self._long_flag_aliases.push(CmdAlias { name: s, visible: true }); }
        self
    }

    /// Set the placement of this subcommand within the help.
    ///
    /// Subcommands with a lower value will be displayed first in the help message.
    /// Those with the same display order will be sorted.
    ///
    /// `Command`s are automatically assigned a display order based on the order they are added to
    /// their parent [`Command`].
    /// Overriding this is helpful when the order commands are added in isn't the same as the
    /// display order, whether in one-off cases or to automatically sort commands.
    function display_order(self, ord: int?) -> Command {
        self._disp_ord = ord;
        self
    }

    /// Specifies that this [`subcommand`] should be hidden from help messages
    function hide(self, yes: bool) -> Command {
        if (yes) { self.setting(AppSettings.Hidden) } else { self.unset_setting(AppSettings.Hidden) }
    }

    /// If no [`subcommand`] is present at runtime, error and exit gracefully.
    function subcommand_required(self, yes: bool) -> Command {
        if (yes) { self.setting(AppSettings.SubcommandRequired) } else { self.unset_setting(AppSettings.SubcommandRequired) }
    }

    /// Assume unexpected positional arguments are a [`subcommand`].
    ///
    /// Arguments will be stored in the `""` argument in the [`ArgMatches`]
    ///
    /// **NOTE:** Use this setting with caution,
    /// as a truly unexpected argument (i.e. one that is *NOT* an external subcommand)
    /// will **not** cause an error and instead be treated as a potential subcommand.
    /// One should check for such cases manually and inform the user appropriately.
    ///
    /// **NOTE:** A built-in subcommand will be parsed as an external subcommand when escaped with
    /// `--`.
    function allow_external_subcommands(self, yes: bool) -> Command {
        if (yes) { self.setting(AppSettings.AllowExternalSubcommands) } else { self.unset_setting(AppSettings.AllowExternalSubcommands) }
    }

    /// Specifies how to parse external subcommand arguments.
    ///
    /// The default parser is for `OsString`.  This can be used to switch it to `String` or another
    /// type.
    ///
    /// **NOTE:** Setting this requires [`Command::allow_external_subcommands`]
    function external_subcommand_value_parser(self, parser: ValueParser | TypedValueParser | null) -> Command {
        self._external_value_parser = match (parser) {
            null => null,
            let p: ValueParser | TypedValueParser => into_value_parser(p),
        };
        self
    }

    /// Specifies that use of an argument prevents the use of [`subcommands`].
    ///
    /// By default `clap` allows arguments between subcommands such
    /// as `<cmd> [cmd_args] <subcmd> [subcmd_args] <subsubcmd> [subsubcmd_args]`.
    ///
    /// This setting disables that functionality and says that arguments can
    /// only follow the *final* subcommand. For instance using this setting
    /// makes only the following invocations possible:
    ///
    /// * `<cmd> <subcmd> <subsubcmd> [subsubcmd_args]`
    /// * `<cmd> <subcmd> [subcmd_args]`
    /// * `<cmd> [cmd_args]`
    function args_conflicts_with_subcommands(self, yes: bool) -> Command {
        if (yes) { self.setting(AppSettings.ArgsNegateSubcommands) } else { self.unset_setting(AppSettings.ArgsNegateSubcommands) }
    }

    /// Prevent subcommands from being consumed as an arguments value.
    ///
    /// By default, if an option taking multiple values is followed by a subcommand, the
    /// subcommand will be parsed as another value.
    ///
    /// ```text
    /// cmd --foo val1 val2 subcommand
    ///           --------- ----------
    ///             values   another value
    /// ```
    ///
    /// This setting instructs the parser to stop when encountering a subcommand instead of
    /// greedily consuming arguments.
    ///
    /// ```text
    /// cmd --foo val1 val2 subcommand
    ///           --------- ----------
    ///             values   subcommand
    /// ```
    function subcommand_precedence_over_arg(self, yes: bool) -> Command {
        if (yes) { self.setting(AppSettings.SubcommandPrecedenceOverArg) } else { self.unset_setting(AppSettings.SubcommandPrecedenceOverArg) }
    }

    /// Allows [`subcommands`] to override all requirements of the parent command.
    ///
    /// For example, if you had a subcommand or top level application with a required argument
    /// that is only required as long as there is no subcommand present,
    /// using this setting would allow you to set those arguments to [`Arg::required(true)`]
    /// and yet receive no error so long as the user uses a valid subcommand instead.
    ///
    /// **NOTE:** This defaults to false (using subcommand does *not* negate requirements)
    function subcommand_negates_reqs(self, yes: bool) -> Command {
        if (yes) { self.setting(AppSettings.SubcommandsNegateReqs) } else { self.unset_setting(AppSettings.SubcommandsNegateReqs) }
    }

    /// Multiple-personality program dispatched on the binary name (`argv[0]`)
    ///
    /// A "multicall" executable is a single executable
    /// that contains a variety of applets,
    /// and decides which applet to run based on the name of the file.
    /// The executable can be called from different names by creating hard links
    /// or symbolic links to it.
    ///
    /// This is desirable for:
    /// - Easy distribution, a single binary that can install hardlinks to access the different
    ///   personalities.
    /// - Minimal binary size by sharing common code (e.g. standard library, clap)
    /// - Custom shells or REPLs where there isn't a single top-level command
    ///
    /// Setting `multicall` will cause
    /// - `argv[0]` to be stripped to the base name and parsed as the first argument, as if
    ///   [`Command::no_binary_name`][Command::no_binary_name] was set.
    /// - Help and errors to report subcommands as if they were the top-level command
    ///
    /// When the subcommand is not present, there are several strategies you may employ, depending
    /// on your needs:
    /// - Let the error percolate up normally
    /// - Print a specialized error message using the
    ///   [`Error::context`][crate::Error::context]
    /// - Print the [help][Command::write_help] but this might be ambiguous
    /// - Disable `multicall` and re-parse it
    /// - Disable `multicall` and re-parse it with a specific subcommand
    ///
    /// When detecting the error condition, the [`ErrorKind`] isn't sufficient as a sub-subcommand
    /// might report the same error.  Enable
    /// [`allow_external_subcommands`][Command::allow_external_subcommands] if you want to specifically
    /// get the unrecognized binary name.
    ///
    /// **NOTE:** Multicall can't be used with [`no_binary_name`] since they interpret
    /// the command name in incompatible ways.
    ///
    /// **NOTE:** The multicall command cannot have arguments.
    ///
    /// **NOTE:** Applets are slightly semantically different from subcommands,
    /// so it's recommended to use [`Command::subcommand_help_heading`] and
    /// [`Command::subcommand_value_name`] to change the descriptive text as above.
    function multicall(self, yes: bool) -> Command {
        if (yes) { self.setting(AppSettings.Multicall) } else { self.unset_setting(AppSettings.Multicall) }
    }

    /// Sets the value name used for subcommands when printing usage and help.
    ///
    /// By default, this is "COMMAND".
    ///
    /// See also [`Command::subcommand_help_heading`]
    function subcommand_value_name(self, value_name: Str?) -> Command {
        self._subcommand_value_name = value_name;
        self
    }

    /// Sets the help heading used for subcommands when printing usage and help.
    ///
    /// By default, this is "Commands".
    ///
    /// See also [`Command::subcommand_value_name`]
    function subcommand_help_heading(self, heading: Str?) -> Command {
        self._subcommand_heading = heading;
        self
    }

    // ===== Reflection =====

    function get_usage_name(self) -> string? { self._usage_name }

    function get_usage_name_fallback(self) -> string {
        if (features().usage) { self.get_usage_name() ?? self.get_bin_name_fallback() } else { self.get_bin_name_fallback() }
    }

    /// Get the name of the binary.
    function get_display_name(self) -> string? { self._display_name }

    /// Get the name of the binary.
    function get_bin_name(self) -> string? { self._bin_name }

    /// Get the name of the binary.
    function get_bin_name_fallback(self) -> string { self._bin_name ?? self.get_name() }

    /// Set binary name. Uses `&mut self` instead of `self`.
    function set_bin_name(self, name: string) -> void { self._bin_name = name; }

    /// Get the name of the cmd.
    function get_name(self) -> string { self._name }

    function get_name_str(self) -> Str { self._name }

    /// Get all known names of the cmd (i.e. primary name and visible aliases).
    function get_name_and_visible_aliases(self) -> string[] {
        [self._name].concat(self.get_visible_aliases())
    }

    /// Get the version of the cmd.
    function get_version(self) -> string? { self._version }

    /// Get the long version of the cmd.
    function get_long_version(self) -> string? { self._long_version }

    /// Get the placement within help
    function get_display_order(self) -> int { self._disp_ord ?? 999 }

    /// Get the authors of the cmd.
    function get_author(self) -> string? { self._author }

    /// Get the short flag of the subcommand.
    function get_short_flag(self) -> string? { self._short_flag }

    /// Get the long flag of the subcommand.
    function get_long_flag(self) -> string? { self._long_flag }

    /// Get the help message specified via [`Command::about`].
    function get_about(self) -> StyledStr? { self._about }

    /// Get the help message specified via [`Command::long_about`].
    function get_long_about(self) -> StyledStr? { self._long_about }

    /// Get the custom section heading specified via [`Command::flatten_help`].
    function is_flatten_help_set(self) -> bool { self.is_set(AppSettings.FlattenHelp) }

    /// Get the custom section heading specified via [`Command::next_help_heading`].
    function get_next_help_heading(self) -> string? { self._current_help_heading }

    /// Iterate through the *visible* aliases for this subcommand.
    function get_visible_aliases(self) -> string[] {
        self._aliases.filter((a) -> { a.visible }).map((a) -> { a.name })
    }

    /// Iterate through the *visible* short aliases for this subcommand.
    function get_visible_short_flag_aliases(self) -> string[] {
        self._short_flag_aliases.filter((a) -> { a.visible }).map((a) -> { a.name })
    }

    /// Iterate through the *visible* long aliases for this subcommand.
    function get_visible_long_flag_aliases(self) -> string[] {
        self._long_flag_aliases.filter((a) -> { a.visible }).map((a) -> { a.name })
    }

    /// Iterate through the set of *all* the aliases for this subcommand, both visible and hidden.
    function get_all_aliases(self) -> string[] { self._aliases.map((a) -> { a.name }) }

    /// Iterate through the set of *all* the short aliases for this subcommand, both visible and hidden.
    function get_all_short_flag_aliases(self) -> string[] { self._short_flag_aliases.map((a) -> { a.name }) }

    /// Iterate through the set of *all* the long aliases for this subcommand, both visible and hidden.
    function get_all_long_flag_aliases(self) -> string[] { self._long_flag_aliases.map((a) -> { a.name }) }

    /// Iterate through the *hidden* aliases for this subcommand.
    function get_aliases(self) -> string[] {
        self._aliases.filter((a) -> { !a.visible }).map((a) -> { a.name })
    }

    function is_set(self, s: AppSettings) -> bool {
        self._settings.is_set(s) || self._g_settings.is_set(s)
    }

    /// Should we color the output?
    function get_color(self) -> ColorChoice {
        if (features().color) {
            if (self.is_set(AppSettings.ColorNever)) {
                ColorChoice.Never
            } else if (self.is_set(AppSettings.ColorAlways)) {
                ColorChoice.Always
            } else {
                ColorChoice.Auto
            }
        } else {
            ColorChoice.Never
        }
    }

    /// Return the current `Styles` for the `Command`
    function get_styles(self) -> Styles {
        self._app_ext.get<Styles>() ?? default_styles()
    }

    /// Iterate through the set of subcommands, getting a reference to each.
    function get_subcommands(self) -> Command[] { self._subcommands }

    /// Iterate through the set of subcommands, getting a mutable reference to each.
    function get_subcommands_mut(self) -> Command[] { self._subcommands }

    /// Returns `true` if this `Command` has subcommands.
    function has_subcommands(self) -> bool { self._subcommands.length() > 0 }

    /// Returns the help heading for listing subcommands.
    function get_subcommand_help_heading(self) -> string? { self._subcommand_heading }

    /// Returns the subcommand value name.
    function get_subcommand_value_name(self) -> string? { self._subcommand_value_name }

    /// Returns the help heading for listing subcommands.
    function get_before_help(self) -> StyledStr? { self._before_help }

    /// Returns the help heading for listing subcommands.
    function get_before_long_help(self) -> StyledStr? { self._before_long_help }

    /// Returns the help heading for listing subcommands.
    function get_after_help(self) -> StyledStr? { self._after_help }

    /// Returns the help heading for listing subcommands.
    function get_after_long_help(self) -> StyledStr? { self._after_long_help }

    /// Find subcommand such that its name or one of aliases equals `name`.
    ///
    /// This does not recurse through subcommands of subcommands.
    function find_subcommand(self, name: string) -> Command? {
        self._subcommands.find((s) -> { s.aliases_to(name) })
    }

    /// Find subcommand such that its name or one of aliases equals `name`, returning
    /// a mutable reference to the subcommand.
    ///
    /// This does not recurse through subcommands of subcommands.
    function find_subcommand_mut(self, name: string) -> Command? {
        self._subcommands.find((s) -> { s.aliases_to(name) })
    }

    /// Iterate through the set of groups.
    function get_groups(self) -> ArgGroup[] { self._groups }

    /// Iterate through the set of arguments.
    function get_arguments(self) -> Arg[] { self._args.args() }

    /// Iterate through the *positionals* arguments.
    function get_positionals(self) -> Arg[] {
        self.get_arguments().filter((a) -> { a.is_positional() })
    }

    /// Iterate through the *options*.
    function get_opts(self) -> Arg[] {
        self.get_arguments().filter((a) -> { a.is_takes_value_set() && !a.is_positional() })
    }

    /// Get a list of all arguments the given argument conflicts with.
    ///
    /// If the provided argument is declared as global, the conflicts will be determined
    /// based on the propagation rules of global arguments.
    ///
    /// ### Panics
    ///
    /// If the given arg contains a conflict with an argument that is unknown to
    /// this `Command`.
    function get_arg_conflicts_with(self, arg: Arg) -> Arg[] {
        if (arg.is_global_set()) {
            self.get_global_arg_conflicts_with(arg)
        } else {
            let result: Arg[] = [];
            for (let id in arg._blacklist) {
                if let a: Arg = self.find(id) {
                    result.push(a);
                } else if let group: ArgGroup = self.find_group(id) {
                    for (let gid in self.unroll_args_in_group(group._id)) {
                        if let ga: Arg = self.find(gid) { result.push(ga); }
                    }
                } else {
                    baml.sys.panic("Command::get_arg_conflicts_with: The passed arg conflicts with an arg unknown to the cmd");
                }
            }
            result
        }
    }

    function get_global_arg_conflicts_with(self, arg: Arg) -> Arg[] {
        let containing = self.get_subcommands_containing(arg);
        let all_args = self._args.args().concat(containing.flat_map((x) -> { x._args.args() }));
        arg._blacklist.map((id) -> {
            all_args.find((a) -> { a.get_id() == id }) ?? baml.sys.panic("Command::get_arg_conflicts_with: The passed arg conflicts with an arg unknown to the cmd")
        })
    }

    function get_subcommands_containing(self, arg: Arg) -> Command[] {
        let vec: Command[] = [];
        for (let sc in self._subcommands) {
            if (sc._args.args().some((ar) -> { ar.get_id() == arg.get_id() })) {
                vec.push(sc);
                for (let x in sc.get_subcommands_containing(arg)) { vec.push(x); }
            }
        }
        vec
    }

    /// Report whether [`Command::no_binary_name`] is set
    function is_no_binary_name_set(self) -> bool { self.is_set(AppSettings.NoBinaryName) }

    /// Report whether [`Command::ignore_errors`] is set
    function is_ignore_errors_set(self) -> bool { self.is_set(AppSettings.IgnoreErrors) }

    /// Report whether [`Command::dont_delimit_trailing_values`] is set
    function is_dont_delimit_trailing_values_set(self) -> bool { self.is_set(AppSettings.DontDelimitTrailingValues) }

    /// Report whether [`Command::disable_version_flag`] is set
    function is_disable_version_flag_set(self) -> bool {
        self.is_set(AppSettings.DisableVersionFlag) || (self._version == null && self._long_version == null)
    }

    /// Report whether [`Command::propagate_version`] is set
    function is_propagate_version_set(self) -> bool { self.is_set(AppSettings.PropagateVersion) }

    /// Report whether [`Command::next_line_help`] is set
    function is_next_line_help_set(self) -> bool { self.is_set(AppSettings.NextLineHelp) }

    /// Report whether [`Command::disable_help_flag`] is set
    function is_disable_help_flag_set(self) -> bool { self.is_set(AppSettings.DisableHelpFlag) }

    /// Report whether [`Command::disable_help_subcommand`] is set
    function is_disable_help_subcommand_set(self) -> bool { self.is_set(AppSettings.DisableHelpSubcommand) }

    /// Report whether [`Command::disable_colored_help`] is set
    function is_disable_colored_help_set(self) -> bool { self.is_set(AppSettings.DisableColoredHelp) }

    function is_help_expected_set(self) -> bool { self.is_set(AppSettings.HelpExpected) }

    /// Deprecated: This is now the default behavior
    function is_dont_collapse_args_in_usage_set(self) -> bool { true }

    function is_infer_long_args_set(self) -> bool { self.is_set(AppSettings.InferLongArgs) }

    function is_infer_subcommands_set(self) -> bool { self.is_set(AppSettings.InferSubcommands) }

    /// Report whether [`Command::arg_required_else_help`] is set
    function is_arg_required_else_help_set(self) -> bool { self.is_set(AppSettings.ArgRequiredElseHelp) }

    function is_allow_hyphen_values_set(self) -> bool { self.is_set(AppSettings.AllowHyphenValues) }

    /// Deprecated, replaced with [`Arg::is_allow_negative_numbers_set`]
    function is_allow_negative_numbers_set(self) -> bool { self.is_set(AppSettings.AllowNegativeNumbers) }

    /// Deprecated, replaced with [`Arg::is_trailing_var_arg_set`]
    function is_trailing_var_arg_set(self) -> bool { self.is_set(AppSettings.TrailingVarArg) }

    /// Report whether [`Command::allow_missing_positional`] is set
    function is_allow_missing_positional_set(self) -> bool { self.is_set(AppSettings.AllowMissingPositional) }

    /// Report whether [`Command::hide`] is set
    function is_hide_set(self) -> bool { self.is_set(AppSettings.Hidden) }

    /// Report whether [`Command::subcommand_required`] is set
    function is_subcommand_required_set(self) -> bool { self.is_set(AppSettings.SubcommandRequired) }

    /// Report whether [`Command::allow_external_subcommands`] is set
    function is_allow_external_subcommands_set(self) -> bool { self.is_set(AppSettings.AllowExternalSubcommands) }

    /// Configured parser for values passed to an external subcommand
    function get_external_subcommand_value_parser(self) -> ValueParser? {
        if (!self.is_allow_external_subcommands_set()) {
            null
        } else {
            self._external_value_parser ?? ValueParser.os_string()
        }
    }

    /// Report whether [`Command::args_conflicts_with_subcommands`] is set
    function is_args_conflicts_with_subcommands_set(self) -> bool { self.is_set(AppSettings.ArgsNegateSubcommands) }

    function is_args_override_self(self) -> bool { self.is_set(AppSettings.AllArgsOverrideSelf) }

    /// Report whether [`Command::subcommand_precedence_over_arg`] is set
    function is_subcommand_precedence_over_arg_set(self) -> bool { self.is_set(AppSettings.SubcommandPrecedenceOverArg) }

    /// Report whether [`Command::subcommand_negates_reqs`] is set
    function is_subcommand_negates_reqs_set(self) -> bool { self.is_set(AppSettings.SubcommandsNegateReqs) }

    /// Report whether [`Command::multicall`] is set
    function is_multicall_set(self) -> bool { self.is_set(AppSettings.Multicall) }

    // ===== Internally used only =====

    function get_override_usage(self) -> StyledStr? { self._usage_str }

    function get_override_help(self) -> StyledStr? { self._help_str }

    function get_help_template(self) -> StyledStr? { self._template }

    function get_term_width(self) -> int? {
        if let t: TermWidth = self._app_ext.get<TermWidth>() { t._0 } else { null }
    }

    function get_max_term_width(self) -> int? {
        if let t: MaxTermWidth = self._app_ext.get<MaxTermWidth>() { t._0 } else { null }
    }

    function get_keymap(self) -> MKeyMap { self._args }

    function get_used_global_args(self, matches: ArgMatches, global_arg_vec: Id[]) -> void {
        for (let a in self._args.args()) {
            if (a.is_global_set()) { global_arg_vec.push(a._id); }
        }

        if let sub: SubcommandMatch = matches.subcommand() {
            if let used_sub: Command = self.find_subcommand(sub.name) {
                used_sub.get_used_global_args(sub.matches, global_arg_vec);
            }
        }
    }

    function _do_parse(self, raw_args: root.clap_lex.RawArgs, args_cursor: root.clap_lex.ArgCursor) -> ArgMatches throws Error {
        // If there are global arguments, or settings we need to propagate them down to subcommands
        // before parsing in case we run into a subcommand
        self._build_self(false);

        let matcher = ArgMatcher.new(self);

        // do the real parsing
        let parser = CmdParser.new(self);
        parser.get_matches_with(matcher, raw_args, args_cursor) catch (e) {
            let error: Error => {
                if (self.is_set(AppSettings.IgnoreErrors) && error.use_stderr()) {
                    // ignoring error
                } else {
                    throw error;
                }
            },
        };

        let global_arg_vec: Id[] = [];
        self.get_used_global_args(matcher.inner(), global_arg_vec);

        matcher.propagate_globals(global_arg_vec);

        matcher.into_inner()
    }

    /// Prepare for introspecting on all included [`Command`]s
    ///
    /// Call this on the top-level [`Command`] when done building and before reading state for
    /// cases like completions, custom help output, etc.
    function build(self) -> void {
        self._build_recursive(true);
        self._build_bin_names_internal();
    }

    function _build_recursive(self, expand_help_tree: bool) -> void {
        self._build_self(expand_help_tree);
        for (let subcmd in self.get_subcommands_mut()) {
            subcmd._build_recursive(expand_help_tree);
        }
    }

    function _build_self(self, expand_help_tree: bool) -> void {
        if (!self._settings.is_set(AppSettings.Built)) {
            if let deferred: (Command) -> Command throws never = self._deferred {
                self._deferred = null;
                let built = deferred(self);
                if (!is_same_command(built, self)) {
                    self.replace_with(built);
                }
            }

            // Make sure all the globally set flags apply to us as well
            self._settings = self._settings.or(self._g_settings);

            if (self.is_multicall_set()) {
                self._settings.set(AppSettings.SubcommandRequired);
                self._settings.set(AppSettings.DisableHelpFlag);
                self._settings.set(AppSettings.DisableVersionFlag);
            }
            if (!features().help && self.get_override_help() == null) {
                self._settings.set(AppSettings.DisableHelpFlag);
                self._settings.set(AppSettings.DisableHelpSubcommand);
            }
            if (self.is_set(AppSettings.ArgsNegateSubcommands)) {
                self._settings.set(AppSettings.SubcommandsNegateReqs);
            }
            if (self._external_value_parser != null) {
                self._settings.set(AppSettings.AllowExternalSubcommands);
            }
            if (!self.has_subcommands()) {
                self._settings.set(AppSettings.DisableHelpSubcommand);
            }

            self._propagate();
            self._check_help_and_version(expand_help_tree);
            self._propagate_global_args();

            let pos_counter = 1;
            let hide_pv = self.is_set(AppSettings.HidePossibleValues);
            for (let a in self._args.args()) {
                // Fill in the groups
                for (let g in a._groups) {
                    let existing = self._groups.find((grp) -> { grp._id == g });
                    if let ag: ArgGroup = existing {
                        ag._args.push(a.get_id());
                    } else {
                        let ag = ArgGroup.new(g);
                        ag._args.push(a.get_id());
                        self._groups.push(ag);
                    }
                }

                // Figure out implied settings
                a._build();
                if (hide_pv && a.is_takes_value_set()) {
                    a._settings.set(ArgSettings.HidePossibleValues);
                }
                if (a.is_positional() && a._index == null) {
                    a._index = pos_counter;
                    pos_counter += 1;
                }
            }

            self._args._build();

            {
                let highest_idx = self.get_keymap().keys().reduce((acc, x) -> {
                    match (x) {
                        let p: KeyPosition => if (p.n > acc) { p.n } else { acc },
                        _ => acc,
                    }
                }, 0);

                let is_trailing_var_arg_set = self.is_trailing_var_arg_set();
                let is_allow_hyphen_values_set = self.is_allow_hyphen_values_set();
                let is_allow_negative_numbers_set = self.is_allow_negative_numbers_set();
                for (let arg in self._args.args()) {
                    if (is_allow_hyphen_values_set && arg.is_takes_value_set()) {
                        arg._settings.set(ArgSettings.AllowHyphenValues);
                    }
                    if (is_allow_negative_numbers_set && arg.is_takes_value_set()) {
                        arg._settings.set(ArgSettings.AllowNegativeNumbers);
                    }
                    if (is_trailing_var_arg_set && arg.get_index() == highest_idx) {
                        arg._settings.set(ArgSettings.TrailingVarArg);
                    }
                }
            }

            assert_app(self);
            self._settings.set(AppSettings.Built);
        }
    }

    function _build_subcommand(self, name: string) -> Command? {
        let mid_string = " ";
        if (features().usage) {
            if (!self.is_subcommand_negates_reqs_set() && !self.is_args_conflicts_with_subcommands_set()) {
                let reqs = Usage.new(self).get_required_usage_from([], null, true); // maybe Some(m)

                for (let s in reqs) {
                    mid_string = mid_string + s.to_string() + " ";
                }
            }
        }
        let is_multicall_set = self.is_multicall_set();

        let found = self._subcommands.find((s) -> { s._name == name });
        if (found == null) {
            return null;
        }
        let sc = found ?? self;

        // Display subcommand name, short and long in usage
        let sc_names = sc._name;
        let flag_subcmd = false;
        if let l: string = sc.get_long_flag() {
            sc_names = sc_names + `|--${l}`;
            flag_subcmd = true;
        }
        if let s: string = sc.get_short_flag() {
            sc_names = sc_names + `|-${s}`;
            flag_subcmd = true;
        }

        if (flag_subcmd) {
            sc_names = `{${sc_names}}`;
        }

        let usage_name = if let bin_name: string = self._bin_name { `${bin_name}${mid_string}${sc_names}` } else { sc_names };
        sc._usage_name = usage_name;

        // bin_name should be parent's bin_name + [<reqs>] + the sc's name separated by
        // a space
        let bin_name = `${self._bin_name ?? ""}${if (self._bin_name != null) { " " } else { "" }}${sc._name}`;
        sc._bin_name = bin_name;

        if (sc._display_name == null) {
            let self_display_name = if (is_multicall_set) {
                self._display_name ?? ""
            } else {
                self._display_name ?? self._name
            };
            let display_name = `${self_display_name}${if (!self_display_name.is_empty()) { "-" } else { "" }}${sc._name}`;
            sc._display_name = display_name;
        }

        // Ensure all args are built and ready to parse
        sc._build_self(false);

        sc
    }

    function _build_bin_names_internal(self) -> void {
        if (!self.is_set(AppSettings.BinNameBuilt)) {
            let mid_string = " ";
            if (features().usage) {
                if (!self.is_subcommand_negates_reqs_set() && !self.is_args_conflicts_with_subcommands_set()) {
                    let reqs = Usage.new(self).get_required_usage_from([], null, true); // maybe Some(m)

                    for (let s in reqs) {
                        mid_string = mid_string + s.to_string() + " ";
                    }
                }
            }
            let is_multicall_set = self.is_multicall_set();

            let self_bin_name = if (is_multicall_set) {
                self._bin_name ?? ""
            } else {
                self._bin_name ?? self._name
            };

            for (let sc in self._subcommands) {
                if (sc._usage_name == null) {
                    // Display subcommand name, short and long in usage
                    let sc_names = sc._name;
                    let flag_subcmd = false;
                    if let l: string = sc.get_long_flag() {
                        sc_names = sc_names + `|--${l}`;
                        flag_subcmd = true;
                    }
                    if let s: string = sc.get_short_flag() {
                        sc_names = sc_names + `|-${s}`;
                        flag_subcmd = true;
                    }

                    if (flag_subcmd) {
                        sc_names = `{${sc_names}}`;
                    }

                    let usage_name = `${self_bin_name}${mid_string}${sc_names}`;
                    sc._usage_name = usage_name;
                }

                if (sc._bin_name == null) {
                    let bin_name = `${self_bin_name}${if (!self_bin_name.is_empty()) { " " } else { "" }}${sc._name}`;
                    sc._bin_name = bin_name;
                }

                if (sc._display_name == null) {
                    let self_display_name = if (is_multicall_set) {
                        self._display_name ?? ""
                    } else {
                        self._display_name ?? self._name
                    };
                    let display_name = `${self_display_name}${if (!self_display_name.is_empty()) { "-" } else { "" }}${sc._name}`;
                    sc._display_name = display_name;
                }

                sc._build_bin_names_internal();
            }
            self._settings.set(AppSettings.BinNameBuilt);
        }
    }

    function _panic_on_missing_help(self, help_required_globally: bool) -> void {
        if (self.is_set(AppSettings.HelpExpected) || help_required_globally) {
            let args_missing_help = self._args.args()
                .filter((arg) -> { arg.get_help() == null && arg.get_long_help() == null })
                .map((arg) -> { arg.get_id() });

            if (args_missing_help.length() > 0) {
                baml.sys.panic(`Command::help_expected is enabled for the Command ${self._name}, but at least one of its arguments does not have either \`help\` or \`long_help\` set. List of such arguments: ${args_missing_help.join(", ")}`);
            }
        }

        for (let sub_app in self._subcommands) {
            sub_app._panic_on_missing_help(help_required_globally);
        }
    }

    /// Returns the first two arguments that match the condition.
    ///
    /// If fewer than two arguments that match the condition, `None` is returned.
    function two_args_of(self, condition: (Arg) -> bool throws never) -> Arg[]? {
        two_elements_of(self._args.args().filter(condition))
    }

    /// Returns the first two groups that match the condition.
    ///
    /// If fewer than two groups that match the condition, `None` is returned.
    function two_groups_of(self, condition: (ArgGroup) -> bool throws never) -> ArgGroup[]? {
        two_elements_of(self._groups.filter(condition))
    }

    /// Propagate global args
    function _propagate_global_args(self) -> void {
        let autogenerated_help_subcommand = !self.is_disable_help_subcommand_set();

        for (let sc in self._subcommands) {
            if (sc.get_name() == "help" && autogenerated_help_subcommand) {
                // Avoid propagating args to the autogenerated help subtrees used in completion.
                // This prevents args from showing up during help completions like
                // `myapp help subcmd <TAB>`, which should only suggest subcommands and not args,
                // while still allowing args to show up properly on the generated help message.
                continue;
            }

            for (let a in self._args.args()) {
                if (!a.is_global_set()) {
                    continue;
                }
                if (sc.find(a._id) != null) {
                    continue;
                }
                sc._args.push(a.clone());
            }
        }
    }

    /// Propagate settings
    function _propagate(self) -> void {
        for (let sc in self._subcommands) {
            self._propagate_subcommand(sc);
        }
    }

    function _propagate_subcommand(self, sc: Command) -> void {
        // We have to create a new scope in order to tell rustc the borrow of `sc` is
        // done and to recursively call this method
        {
            if (self._settings.is_set(AppSettings.PropagateVersion)) {
                if let version: string = self._version {
                    if (sc._version == null) { sc._version = version; }
                }
                if let long_version: string = self._long_version {
                    if (sc._long_version == null) { sc._long_version = long_version; }
                }
            }

            sc._settings = sc._settings.or(self._g_settings);
            sc._g_settings = sc._g_settings.or(self._g_settings);
            sc._app_ext.update(self._app_ext);
        }
    }

    function _check_help_and_version(self, expand_help_tree: bool) -> void {
        self._long_help_exists = self.long_help_exists_();

        if (!self.is_disable_help_flag_set()) {
            let arg = Arg.new(ID_HELP())
                .short("h")
                .long("help")
                .action(ArgAction.Help);
            if (self._long_help_exists) {
                arg = arg
                    .help("Print help (see more with '--help')")
                    .long_help("Print help (see a summary with '-h')");
            } else {
                arg = arg.help("Print help");
            }
            // Avoiding `arg_internal` to not be sensitive to `next_help_heading` /
            // `next_display_order`
            self._args.push(arg);
        }
        if (!self.is_disable_version_flag_set()) {
            let arg = Arg.new(ID_VERSION())
                .short("V")
                .long("version")
                .action(ArgAction.Version)
                .help("Print version");
            // Avoiding `arg_internal` to not be sensitive to `next_help_heading` /
            // `next_display_order`
            self._args.push(arg);
        }

        if (!self.is_set(AppSettings.DisableHelpSubcommand)) {
            let help_about = "Print this message or the help of the given subcommand(s)";

            let help_subcmd = if (expand_help_tree) {
                // Slow code path to recursively clone all other subcommand subtrees under help
                let hs = Command.new("help")
                    .about(help_about)
                    .global_setting(AppSettings.DisableHelpSubcommand)
                    .subcommands(self.get_subcommands().map((c) -> { c._copy_subtree_for_help() }));

                let help_help_subcmd = Command.new("help").about(help_about);
                help_help_subcmd._version = null;
                help_help_subcmd._long_version = null;
                help_help_subcmd = help_help_subcmd
                    .setting(AppSettings.DisableHelpFlag)
                    .setting(AppSettings.DisableVersionFlag);

                hs.subcommand(help_help_subcmd)
            } else {
                Command.new("help").about(help_about).arg(
                    Arg.new("subcommand")
                        .action(ArgAction.Append)
                        .num_args(ValueRange.FULL())
                        .value_name("COMMAND")
                        .help("Print help for the subcommand(s)"),
                )
            };
            self._propagate_subcommand(help_subcmd);

            // The parser acts like this is set, so let's set it so we don't falsely
            // advertise it to the user
            help_subcmd._version = null;
            help_subcmd._long_version = null;
            help_subcmd = help_subcmd
                .setting(AppSettings.DisableHelpFlag)
                .setting(AppSettings.DisableVersionFlag)
                .unset_global_setting(AppSettings.PropagateVersion);

            self._subcommands.push(help_subcmd);
        }
    }

    function _copy_subtree_for_help(self) -> Command {
        let cmd = Command.new(self._name)
            .hide(self.is_hide_set())
            .global_setting(AppSettings.DisableHelpFlag)
            .global_setting(AppSettings.DisableVersionFlag)
            .subcommands(self.get_subcommands().map((c) -> { c._copy_subtree_for_help() }));
        if let about: StyledStr = self.get_about() {
            cmd = cmd.about(about.clone());
        }
        cmd
    }

    function _render_version(self, use_long: bool) -> string {
        let ver = if (use_long) {
            self._long_version ?? self._version ?? ""
        } else {
            self._version ?? self._long_version ?? ""
        };
        let display_name = self.get_display_name() ?? self.get_name();
        `${display_name} ${ver}\n`
    }

    function format_group(self, g: Id) -> StyledStr {
        let g_string = self.unroll_args_in_group(g)
            .filter_map((x) -> { self.find(x) })
            .map((x) -> {
                if (x.is_positional()) {
                    // Print val_name for positional arguments. e.g. <file_name>
                    x.name_no_brackets()
                } else {
                    // Print usage string for flags arguments, e.g. <--help>
                    x.to_string()
                }
            })
            .join("|");
        let placeholder = self.get_styles().get_placeholder();
        let styled = StyledStr.new();
        styled.push_styled_str(placeholder, `<${g_string}>`);
        styled
    }

    // ===== Internal Query Methods =====

    /// Iterate through the *flags* & *options* arguments.
    function get_non_positionals(self) -> Arg[] {
        self.get_arguments().filter((a) -> { !a.is_positional() })
    }

    function find(self, arg_id: Id) -> Arg? {
        self._args.args().find((a) -> { a.get_id() == arg_id })
    }

    function contains_short(self, s: string) -> bool {
        self._args.contains_short(s)
    }

    function set(self, s: AppSettings) -> void {
        self._settings.set(s);
    }

    function has_positionals(self) -> bool {
        self.get_positionals().length() > 0
    }

    function has_visible_subcommands(self) -> bool {
        self._subcommands.some((sc) -> { sc._name != "help" && !sc.is_set(AppSettings.Hidden) })
    }

    /// Check if this subcommand can be referred to as `name`. In other words,
    /// check if `name` is the name of this subcommand or is one of its aliases.
    function aliases_to(self, name: string) -> bool {
        self.get_name() == name || self.get_all_aliases().some((alias) -> { alias == name })
    }

    /// Check if this subcommand can be referred to as `name`. In other words,
    /// check if `name` is the name of this short flag subcommand or is one of its short flag aliases.
    function short_flag_aliases_to(self, flag: string) -> bool {
        self._short_flag == flag || self.get_all_short_flag_aliases().some((alias) -> { flag == alias })
    }

    /// Check if this subcommand can be referred to as `name`. In other words,
    /// check if `name` is the name of this long flag subcommand or is one of its long flag aliases.
    function long_flag_aliases_to(self, flag: string) -> bool {
        match (self._long_flag) {
            let long_flag: string => long_flag == flag || self.get_all_long_flag_aliases().some((alias) -> { alias == flag }),
            null => self.get_all_long_flag_aliases().some((alias) -> { alias == flag }),
        }
    }

    function id_exists(self, id: Id) -> bool {
        self._args.args().some((x) -> { x.get_id() == id }) || self._groups.some((x) -> { x._id == id })
    }

    /// Iterate through the groups this arg is member of.
    function groups_for_arg(self, arg: Id) -> Id[] {
        self._groups
            .filter((grp) -> { grp._args.some((a) -> { a == arg }) })
            .map((grp) -> { grp._id })
    }

    function find_group(self, group_id: Id) -> ArgGroup? {
        self._groups.find((g) -> { g._id == group_id })
    }

    /// Iterate through all the names of all subcommands (not recursively), including aliases.
    /// Used for suggestions.
    function all_subcommand_names(self) -> string[] {
        self.get_subcommands().flat_map((sc) -> { [sc.get_name()].concat(sc.get_all_aliases()) })
    }

    function required_graph(self) -> ChildGraph<Id> {
        let reqs: ChildGraph<Id> = ChildGraph.with_capacity(5);
        for (let a in self._args.args()) {
            if (a.is_required_set()) {
                reqs.insert(a.get_id());
            }
        }
        for (let group in self._groups) {
            if (group._required) {
                let idx = reqs.insert(group._id);
                for (let a in group._requires) {
                    reqs.insert_child(idx, a);
                }
            }
        }

        reqs
    }

    function unroll_args_in_group(self, group: Id) -> Id[] {
        let g_vec: Id[] = [group];
        let args: Id[] = [];

        while let g: string = g_vec.pop() {
            let grp = self._groups.find((grp) -> { grp._id == g });
            let members = if let gr: ArgGroup = grp { gr._args } else { baml.sys.panic(INTERNAL_ERROR_MSG()) };
            for (let n in members) {
                if (!args.includes(n)) {
                    if (self.find(n) != null) {
                        args.push(n);
                    } else {
                        g_vec.push(n);
                    }
                }
            }
        }

        args
    }

    function unroll_arg_requires(self, func: (ArgRequire) -> Id? throws never, arg: Id) -> Id[] {
        let processed: Id[] = [];
        let r_vec: Id[] = [arg];
        let args: Id[] = [];

        while let a: string = r_vec.pop() {
            if (processed.includes(a)) {
                continue;
            }

            processed.push(a);

            if let ar: Arg = self.find(a) {
                for (let r in ar._requires.filter_map(func)) {
                    if let req: Arg = self.find(r) {
                        if (req._requires.length() > 0) {
                            r_vec.push(req.get_id());
                        }
                    }
                    args.push(r);
                }
            }
        }

        args
    }

    /// Find a flag subcommand name by short flag or an alias
    function find_short_subcmd(self, c: string) -> string? {
        let sc = self.get_subcommands().find((sc) -> { sc.short_flag_aliases_to(c) });
        if let s: Command = sc { s.get_name() } else { null }
    }

    /// Find a flag subcommand name by long flag or an alias
    function find_long_subcmd(self, long: string) -> string? {
        let sc = self.get_subcommands().find((sc) -> { sc.long_flag_aliases_to(long) });
        if let s: Command = sc { s.get_name() } else { null }
    }

    function write_help_err(self, use_long: bool) -> StyledStr {
        let ul = use_long && self.long_help_exists();

        let usage = Usage.new(self);

        let styled = StyledStr.new();
        write_help(styled, self, usage, ul);

        styled
    }

    function write_version_err(self, use_long: bool) -> StyledStr {
        let msg = self._render_version(use_long);
        StyledStr.from(msg)
    }

    function long_help_exists(self) -> bool { self._long_help_exists }

    function long_help_exists_(self) -> bool {
        // In this case, both must be checked. This allows the retention of
        // original formatting, but also ensures that the actual -h or --help
        // specified by the user is sent through. If hide_short_help is not included,
        // then items specified with hidden_short_help will also be hidden.
        let should_long = (v: Arg) -> bool {
            !v.is_hide_set()
                && (v.get_long_help() != null
                    || v.is_hide_long_help_set()
                    || v.is_hide_short_help_set()
                    || (!v.is_hide_possible_values_set()
                        && v.get_possible_values().some((pv) -> { pv.should_show_help() })))
        };

        // Subcommands aren't checked because we prefer short help for them, deferring to
        // `cmd subcmd --help` for more.
        self.get_long_about() != null
            || self.get_before_long_help() != null
            || self.get_after_long_help() != null
            || self.get_arguments().some(should_long)
    }

    // Should we color the help?
    function color_help(self) -> ColorChoice {
        if (features().color) {
            if (self.is_disable_colored_help_set()) {
                return ColorChoice.Never;
            }
        }

        self.get_color()
    }

    /// `*self = other` (used by `defer`)
    function replace_with(self, other: Command) -> void {
        self._name = other._name;
        self._long_flag = other._long_flag;
        self._short_flag = other._short_flag;
        self._display_name = other._display_name;
        self._bin_name = other._bin_name;
        self._author = other._author;
        self._version = other._version;
        self._long_version = other._long_version;
        self._about = other._about;
        self._long_about = other._long_about;
        self._before_help = other._before_help;
        self._before_long_help = other._before_long_help;
        self._after_help = other._after_help;
        self._after_long_help = other._after_long_help;
        self._aliases = other._aliases;
        self._short_flag_aliases = other._short_flag_aliases;
        self._long_flag_aliases = other._long_flag_aliases;
        self._usage_str = other._usage_str;
        self._usage_name = other._usage_name;
        self._help_str = other._help_str;
        self._disp_ord = other._disp_ord;
        self._template = other._template;
        self._settings = other._settings;
        self._g_settings = other._g_settings;
        self._args = other._args;
        self._subcommands = other._subcommands;
        self._groups = other._groups;
        self._current_help_heading = other._current_help_heading;
        self._current_disp_ord = other._current_disp_ord;
        self._subcommand_value_name = other._subcommand_value_name;
        self._subcommand_heading = other._subcommand_heading;
        self._external_value_parser = other._external_value_parser;
        self._long_help_exists = other._long_help_exists;
        self._deferred = other._deferred;
        self._ext = other._ext;
        self._app_ext = other._app_ext;
    }

    /// `impl Clone for Command`
    function clone(self) -> Command {
        Command {
            ...self,
            _aliases: self._aliases.slice(0, self._aliases.length()),
            _short_flag_aliases: self._short_flag_aliases.slice(0, self._short_flag_aliases.length()),
            _long_flag_aliases: self._long_flag_aliases.slice(0, self._long_flag_aliases.length()),
            _settings: self._settings.copy(),
            _g_settings: self._g_settings.copy(),
            _args: self._args.clone(),
            _subcommands: self._subcommands.map((s) -> { s.clone() }),
            _groups: self._groups.map((g) -> { g.clone() }),
            _ext: self._ext.clone(),
            _app_ext: self._app_ext.clone(),
        }
    }

    /// `impl Display for Command`
    implements baml.ToString {
        function to_string(self) -> string throws never { self._name }
    }
}

/// `impl Index<&Id> for Command`
function command_index(cmd: Command, key: Id) -> Arg {
    cmd.find(key) ?? baml.sys.panic(INTERNAL_ERROR_MSG())
}

/// Identity check for class references (BAML `==` is structural)
function is_same_command(a: Command, b: Command) -> bool {
    let tag = `__clap_identity_${baml.id.new()}`;
    let old = a._usage_name;
    a._usage_name = tag;
    let same = b._usage_name == tag;
    a._usage_name = old;
    same
}

function two_elements_of<T>(items: T[]) -> T[]? {
    if (items.length() >= 2) { [items[0], items[1]] } else { null }
}

/// `Path::new(p).file_name()`
function file_name(p: string) -> string {
    let trimmed = if (p.ends_with("/") && p.length() > 1) { p.slice(0, p.length() - 1) } else { p };
    trimmed.split("/").at(-1) ?? ""
}

/// `Path::new(p).file_stem()`
function file_stem(p: string) -> string {
    let name = file_name(p);
    if let idx: int = name.last_index_of(".") {
        if (idx > 0) { name.slice(0, idx) } else { name }
    } else {
        name
    }
}
