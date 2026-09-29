// Port of clap_builder/src/builder/arg.rs

/// `(Str, bool)`: an alias and whether it is visible
class ArgAlias {
    name: string,
    visible: bool,
}

/// `(ArgPredicate, Id)`
class ArgRequire {
    predicate: ArgPredicate,
    id: Id,
}

/// `(Id, OsStr)`
class ArgIdValue {
    id: Id,
    value: OsStr,
}

/// `(Id, ArgPredicate, Option<Vec<OsStr>>)`
class DefaultValueIf {
    id: Id,
    predicate: ArgPredicate,
    values: OsStr[]?,
}

/// `(OsStr, Option<OsString>)`: env var name and its value at build time
class ArgEnv {
    name: OsStr,
    value: string?,
}

/// The abstract representation of a command line argument. Used to set all the options and
/// relationships that define a valid argument for the program.
///
/// There are two methods for constructing [`Arg`]s, using the builder pattern and setting options
/// manually, or using a usage string which is far less verbose but has fewer options. You can also
/// use a combination of the two methods to achieve the best of both worlds.
///
/// - [Basic API][crate::Arg#basic-api]
/// - [Value Handling][crate::Arg#value-handling]
/// - [Help][crate::Arg#help-1]
/// - [Advanced Argument Relations][crate::Arg#advanced-argument-relations]
/// - [Reflection][crate::Arg#reflection]
///
/// # Examples
///
/// ```baml
/// // Using the traditional builder pattern and setting each option manually
/// let cfg = Arg.new("config")
///       .short("c")
///       .long("config")
///       .action(ArgAction.Set)
///       .value_name("FILE")
///       .help("Provides a config file to myprog");
/// // Using a usage string (setting a similar argument to the one above)
/// let input = arg("-i, --input <FILE> 'Provides an input file to the program'");
/// ```
class Arg {
    _id: Id,
    _help: StyledStr?,
    _long_help: StyledStr?,
    _action: ArgAction?,
    _value_parser: ValueParser?,
    _blacklist: Id[],
    _settings: ArgFlags,
    _overrides: Id[],
    _groups: Id[],
    _requires: ArgRequire[],
    _r_ifs: ArgIdValue[],
    _r_ifs_all: ArgIdValue[],
    _r_unless: Id[],
    _r_unless_all: Id[],
    _short: string?,
    _long: Str?,
    _aliases: ArgAlias[],
    _short_aliases: ArgAlias[],
    _disp_ord: int?,
    _val_names: Str[],
    _num_vals: ValueRange?,
    _val_delim: string?,
    _default_vals: OsStr[],
    _default_vals_ifs: DefaultValueIf[],
    _default_missing_vals: OsStr[],
    _env: ArgEnv?,
    _terminator: Str?,
    _index: int?,
    /// `Option<Option<Str>>`: unset / explicitly-no-heading / heading
    _help_heading_set: bool,
    _help_heading: Str?,
    _ext: Extensions,

    // ===== Basic API =====

    /// Create a new [`Arg`] with a unique name.
    ///
    /// The name is used to check whether or not the argument was used at
    /// runtime, get values, set relationships with other args, etc..
    ///
    /// **NOTE:** In the case of arguments that take values (i.e. [`Arg::action(ArgAction::Set)`])
    /// and positional arguments (i.e. those without a preceding `-` or `--`) the name will also
    /// be displayed when the user prints the usage/help information of the program.
    function new(id: Id) -> Arg {
        Arg.default().id(id)
    }

    /// `impl Default for Arg`
    function default() -> Arg {
        Arg {
            _id: "",
            _help: null,
            _long_help: null,
            _action: null,
            _value_parser: null,
            _blacklist: [],
            _settings: ArgFlags.new(),
            _overrides: [],
            _groups: [],
            _requires: [],
            _r_ifs: [],
            _r_ifs_all: [],
            _r_unless: [],
            _r_unless_all: [],
            _short: null,
            _long: null,
            _aliases: [],
            _short_aliases: [],
            _disp_ord: null,
            _val_names: [],
            _num_vals: null,
            _val_delim: null,
            _default_vals: [],
            _default_vals_ifs: [],
            _default_missing_vals: [],
            _env: null,
            _terminator: null,
            _index: null,
            _help_heading_set: false,
            _help_heading: null,
            _ext: Extensions.new(),
        }
    }

    /// Set the identifier used for referencing this argument in the clap API.
    ///
    /// See [`Arg::new`] for more details.
    function id(self, id: Id) -> Arg {
        self._id = id;
        self
    }

    /// Sets the short version of the argument without the preceding `-`.
    ///
    /// By default `V` and `h` are used by the auto-generated `version` and `help` arguments,
    /// respectively. You will need to disable the auto-generated flags
    /// ([`disable_help_flag`][crate::Command::disable_help_flag],
    /// [`disable_version_flag`][crate::Command::disable_version_flag]) and define your own.
    function short(self, s: string?) -> Arg {
        if let c: string = s {
            assert.is_true(c != "-");
            self._short = c;
        } else {
            self._short = null;
        }
        self
    }

    /// Sets the long version of the argument without the preceding `--`.
    ///
    /// By default `version` and `help` are used by the auto-generated `version` and `help`
    /// arguments, respectively. You may use the word `version` or `help` for the long form of your
    /// own arguments, in which case `clap` simply will not assign those to the auto-generated
    /// `version` or `help` arguments.
    ///
    /// **NOTE:** Any leading `-` characters will be stripped
    function long(self, l: Str?) -> Arg {
        self._long = l;
        self
    }

    /// Add an alias, which functions as a hidden long flag.
    ///
    /// This is more efficient, and easier than creating multiple hidden arguments as one only needs
    /// to check for the existence of this command, and not all variants.
    function alias(self, name: Str?) -> Arg {
        if let n: string = name {
            self._aliases.push(ArgAlias { name: n, visible: false });
        } else {
            self._aliases.clear();
        }
        self
    }

    /// Add an alias, which functions as a hidden short flag.
    function short_alias(self, name: string?) -> Arg {
        if let n: string = name {
            assert.is_true(n != "-");
            self._short_aliases.push(ArgAlias { name: n, visible: false });
        } else {
            self._short_aliases.clear();
        }
        self
    }

    /// Add aliases, which function as hidden long flags.
    function aliases(self, names: Str[]) -> Arg {
        for (let n in names) { self._aliases.push(ArgAlias { name: n, visible: false }); }
        self
    }

    /// Add aliases, which functions as a hidden short flag.
    function short_aliases(self, names: string[]) -> Arg {
        for (let s in names) {
            assert.is_true(s != "-");
            self._short_aliases.push(ArgAlias { name: s, visible: false });
        }
        self
    }

    /// Add an alias, which functions as a visible long flag.
    ///
    /// Like [`Arg::alias`], except that they are visible inside the help message.
    function visible_alias(self, name: Str?) -> Arg {
        if let n: string = name {
            self._aliases.push(ArgAlias { name: n, visible: true });
        } else {
            self._aliases.clear();
        }
        self
    }

    /// Add an alias, which functions as a visible short flag.
    ///
    /// Like [`Arg::short_alias`], except that they are visible inside the help message.
    function visible_short_alias(self, name: string?) -> Arg {
        if let n: string = name {
            assert.is_true(n != "-");
            self._short_aliases.push(ArgAlias { name: n, visible: true });
        } else {
            self._short_aliases.clear();
        }
        self
    }

    /// Add aliases, which function as visible long flags.
    ///
    /// Like [`Arg::aliases`], except that they are visible inside the help message.
    function visible_aliases(self, names: Str[]) -> Arg {
        for (let n in names) { self._aliases.push(ArgAlias { name: n, visible: true }); }
        self
    }

    /// Add aliases, which function as visible short flags.
    ///
    /// Like [`Arg::short_aliases`], except that they are visible inside the help message.
    function visible_short_aliases(self, names: string[]) -> Arg {
        for (let n in names) {
            assert.is_true(n != "-");
            self._short_aliases.push(ArgAlias { name: n, visible: true });
        }
        self
    }

    /// Specifies the index of a positional argument **starting at** 1.
    ///
    /// **NOTE:** The index refers to position according to **other positional argument**. It does
    /// not define position in the argument list as a whole.
    ///
    /// **NOTE:** You can optionally leave off the `index` method, and the index will be
    /// assigned in order of evaluation. Utilizing the `index` method allows for setting
    /// indexes out of order
    function index(self, idx: int?) -> Arg {
        self._index = idx;
        self
    }

    /// This is a "var arg" and everything that follows should be captured by it, as if the user had
    /// used a `--`.
    ///
    /// **NOTE:** To start the trailing "var arg" on unknown flags (and not just a positional
    /// value), set [`allow_hyphen_values`][Arg::allow_hyphen_values].  Either way, users still
    /// have the option to explicitly escape ambiguous arguments with `--`.
    ///
    /// **NOTE:** [`Arg::value_delimiter`] still applies if set.
    ///
    /// **NOTE:** Setting this requires [`Arg::num_args(..)`].
    function trailing_var_arg(self, yes: bool) -> Arg {
        if (yes) { self.setting(ArgSettings.TrailingVarArg) } else { self.unset_setting(ArgSettings.TrailingVarArg) }
    }

    /// This arg is the last, or final, positional argument (i.e. has the highest
    /// index) and is *only* able to be accessed via the `--` syntax (i.e. `$ prog args --
    /// last_arg`).
    ///
    /// Even, if no other arguments are left to parse, if the user omits the `--` syntax
    /// they will receive an [`UnknownArgument`] error. Setting an argument to `.last(true)` also
    /// allows one to access this arg early using the `--` syntax. Accessing an arg early, even with
    /// the `--` syntax is otherwise not possible.
    function last(self, yes: bool) -> Arg {
        if (yes) { self.setting(ArgSettings.Last) } else { self.unset_setting(ArgSettings.Last) }
    }

    /// Specifies that the argument must be present.
    ///
    /// Required by default means it is required, when no other conflicting rules or overrides have
    /// been evaluated. Conflicting rules take precedence over being required.
    ///
    /// **Pro tip:** Flags (i.e. not positional, or arguments that take values) shouldn't be
    /// required by default. This is because if a flag were to be required, it should simply be
    /// implied. No additional information is required from user. Flags by their very nature are
    /// simply boolean on/off switches. The only time a user *should* be required to use a flag
    /// is if the operation is destructive in nature, and the user is essentially proving to you,
    /// "Yes, I know what I'm doing."
    function required(self, yes: bool) -> Arg {
        if (yes) { self.setting(ArgSettings.Required) } else { self.unset_setting(ArgSettings.Required) }
    }

    /// Sets an argument that is required when this one is present
    ///
    /// i.e. when using this argument, the following argument *must* be present.
    ///
    /// **NOTE:** [Conflicting] rules and [override] rules take precedence over being required
    function requires(self, arg_id: Id?) -> Arg {
        if let id: string = arg_id {
            self._requires.push(ArgRequire { predicate: ArgPredicateIsPresent {}, id: id });
        } else {
            self._requires.clear();
        }
        self
    }

    /// This argument must be passed alone; it conflicts with all other arguments.
    function exclusive(self, yes: bool) -> Arg {
        if (yes) { self.setting(ArgSettings.Exclusive) } else { self.unset_setting(ArgSettings.Exclusive) }
    }

    /// Specifies that an argument can be matched to all child [`Subcommand`]s.
    ///
    /// **NOTE:** Global arguments *only* propagate down, **not** up (to parent commands), however
    /// their values once a user uses them will be propagated back up to parents. In effect, this
    /// means one should *define* all global arguments at the top level, however it doesn't matter
    /// where the user *uses* the global argument.
    function global(self, yes: bool) -> Arg {
        if (yes) { self.setting(ArgSettings.Global) } else { self.unset_setting(ArgSettings.Global) }
    }

    function is_set(self, s: ArgSettings) -> bool { self._settings.is_set(s) }

    function setting(self, setting: ArgSettings) -> Arg {
        self._settings.set(setting);
        self
    }

    function unset_setting(self, setting: ArgSettings) -> Arg {
        self._settings.unset(setting);
        self
    }

    // ===== Value Handling =====

    /// Specify how to react to an argument when parsing it.
    ///
    /// [`ArgAction`] controls things like
    /// - Overwriting previous values with new ones
    /// - Appending new values to all previous ones
    /// - Counting how many times a flag occurs
    ///
    /// The default action is `ArgAction::Set`
    function action(self, action: ArgAction?) -> Arg {
        self._action = action;
        self
    }

    /// Specify the typed behavior of the argument.
    ///
    /// This allows parsing and validating a value before storing it into
    /// [`ArgMatches`][crate::ArgMatches] as the given type.
    ///
    /// Possible value parsers include:
    /// - [`value_parser!(T)`][crate::value_parser!] for auto-selecting a value parser for a given type
    ///   - Or [range expressions like `0..=1`][std::ops::RangeBounds] as a shorthand for [`RangedI64ValueParser`][crate::builder::RangedI64ValueParser]
    /// - `Fn(&str) -> Result<T, E>`
    /// - `[&str]` and [`PossibleValuesParser`][crate::builder::PossibleValuesParser] for static enumerated values
    /// - [`BoolishValueParser`][crate::builder::BoolishValueParser], and [`FalseyValueParser`][crate::builder::FalseyValueParser] for alternative `bool` implementations
    /// - [`NonEmptyStringValueParser`][crate::builder::NonEmptyStringValueParser] for basic validation for strings
    /// - or any other [`TypedValueParser`][crate::builder::TypedValueParser] implementation
    ///
    /// The default value parser is [`ValueParser::string`].
    function value_parser(self, parser: ValueParser | TypedValueParser | string[] | PossibleValue[] | null) -> Arg {
        self._value_parser = match (parser) {
            null => null,
            let p: ValueParser | TypedValueParser | string[] | PossibleValue[] => into_value_parser(p),
        };
        self
    }

    /// Specifies the number of arguments parsed per occurrence
    ///
    /// For example, if you had a `-f <file>` argument where you wanted exactly 3 'files' you would
    /// set `.num_args(3)`, and this argument wouldn't be satisfied unless the user
    /// provided 3 and only 3 values.
    ///
    /// Users may specify values for arguments in any of the following methods
    ///
    /// - Using a space such as `-o value` or `--option value`
    /// - Using an equals and no space such as `-o=value` or `--option=value`
    /// - Use a short and no space such as `-ovalue`
    ///
    /// **WARNING:**
    ///
    /// Setting a variable number of values (e.g. `1..=10`) for an argument without
    /// other details can be dangerous in some circumstances. Because multiple values are
    /// allowed, `--option val1 val2 val3` is perfectly valid. Be careful when designing a CLI
    /// where **positional arguments** or **subcommands** are *also* expected as `clap` will continue
    /// parsing *values* until one of the following happens:
    ///
    /// - It reaches the maximum number of values
    /// - It reaches a specific number of values
    /// - It finds another flag or option (i.e. something that starts with a `-`)
    /// - It reaches the [`Arg::value_terminator`] if set
    ///
    /// Alternatively,
    /// - Use a delimiter between values with [`Arg::value_delimiter`]
    /// - Require a flag occurrence per value with [`ArgAction::Append`]
    /// - Require positional arguments to appear after `--` with [`Arg::last`]
    function num_args(self, qty: ValueRange | int | null) -> Arg {
        self._num_vals = match (qty) {
            null => null,
            let r: ValueRange | int => into_value_range(r),
        };
        self
    }

    /// Placeholder for the argument's value in the help message / usage.
    ///
    /// This name is cosmetic only; the name is **not** used to access arguments.
    /// This setting can be very helpful when describing the type of input the user should be
    /// using, such as `FILE`, `INTERFACE`, etc. Although not required, it's somewhat convention to
    /// use all capital letters for the value name.
    ///
    /// **NOTE:** implicitly sets [`Arg::action(ArgAction::Set)`]
    function value_name(self, name: Str?) -> Arg {
        if let n: string = name {
            self.value_names([n])
        } else {
            self._val_names.clear();
            self
        }
    }

    /// Placeholders for the argument's values in the help message / usage.
    ///
    /// A placeholder name is used for each argument value, in order.
    ///
    /// **Pro Tip:** It may help to use [`Arg::next_line_help(true)`] if there are long, or
    /// multiple value names in order to not throw off the help text alignment of all options.
    ///
    /// **NOTE:** implicitly sets [`Arg::action(ArgAction::Set)`] and [`Arg::num_args(1..)`].
    function value_names(self, names: Str[]) -> Arg {
        self._val_names = names.slice(0, names.length());
        self
    }

    /// Provide the shell a hint about how to complete this argument.
    ///
    /// See [`ValueHint`] for more information.
    ///
    /// **NOTE:** implicitly sets [`Arg::action(ArgAction::Set)`].
    function value_hint(self, value_hint: ValueHint?) -> Arg {
        // HACK: we should use `Self::add` and `Self::remove` to type-check that `ArgExt` is used
        match (value_hint) {
            null => { self._ext.remove<ValueHint>(); },
            let h: ValueHint => { self._ext.set<ValueHint>(h); },
        }
        self
    }

    /// Match values against [`PossibleValuesParser`][crate::builder::PossibleValuesParser] without matching case.
    ///
    /// When other arguments are conditionally required based on the
    /// value of a case-insensitive argument, the equality check done
    /// by [`Arg::required_if_eq`], [`Arg::required_if_eq_any`], or
    /// [`Arg::required_if_eq_all`] is case-insensitive.
    ///
    /// **NOTE:** Setting this requires [taking values][Arg::num_args]
    ///
    /// **NOTE:** To do unicode case folding, enable the `unicode` feature flag.
    function ignore_case(self, yes: bool) -> Arg {
        if (yes) { self.setting(ArgSettings.IgnoreCase) } else { self.unset_setting(ArgSettings.IgnoreCase) }
    }

    /// Allows values which start with a leading hyphen (`-`)
    ///
    /// To limit values to just numbers, see
    /// [`allow_negative_numbers`][Arg::allow_negative_numbers].
    ///
    /// See also [`trailing_var_arg`][Arg::trailing_var_arg].
    ///
    /// **NOTE:** Setting this requires [taking values][Arg::num_args]
    ///
    /// **WARNING:** Prior arguments with `allow_hyphen_values(true)` get precedence over known
    /// flags but known flags get precedence over the next possible positional argument with
    /// `allow_hyphen_values(true)`.  When combined with [`Arg::num_args(..)`],
    /// [`Arg::value_terminator`] is one way to ensure processing stops.
    ///
    /// **WARNING**: Take caution when using this setting combined with another argument using
    /// [`Arg::num_args`], as this becomes ambiguous `$ prog --arg -- -- val`. All
    /// three `--, --, val` will be values when the user may have thought the second `--` would
    /// constitute the normal, "Only positional args follow" idiom.
    function allow_hyphen_values(self, yes: bool) -> Arg {
        if (yes) { self.setting(ArgSettings.AllowHyphenValues) } else { self.unset_setting(ArgSettings.AllowHyphenValues) }
    }

    /// Allows negative numbers to pass as values.
    ///
    /// This is similar to [`Arg::allow_hyphen_values`] except that it only allows numbers,
    /// all other undefined leading hyphens will fail to parse.
    ///
    /// **NOTE:** Setting this requires [taking values][Arg::num_args]
    function allow_negative_numbers(self, yes: bool) -> Arg {
        if (yes) { self.setting(ArgSettings.AllowNegativeNumbers) } else { self.unset_setting(ArgSettings.AllowNegativeNumbers) }
    }

    /// Requires that options use the `--option=val` syntax
    ///
    /// i.e. an equals between the option and associated value.
    ///
    /// **NOTE:** Setting this requires [taking values][Arg::num_args]
    function require_equals(self, yes: bool) -> Arg {
        if (yes) { self.setting(ArgSettings.RequireEquals) } else { self.unset_setting(ArgSettings.RequireEquals) }
    }

    /// Deprecated, replaced with [`Arg::value_delimiter`]
    function use_value_delimiter(self, yes: bool) -> Arg {
        if (yes) {
            if (self._val_delim == null) { self._val_delim = ","; }
        } else {
            self._val_delim = null;
        }
        self
    }

    /// Allow grouping of multiple values via a delimiter.
    ///
    /// i.e. allow values (`val1,val2,val3`) to be parsed as three values (`val1`, `val2`,
    /// and `val3`) instead of one value (`val1,val2,val3`).
    function value_delimiter(self, d: string?) -> Arg {
        self._val_delim = d;
        self
    }

    /// Sentinel to **stop** parsing multiple values of a given argument.
    ///
    /// By default when
    /// one sets [`num_args(1..)`] on an argument, clap will continue parsing values for that
    /// argument until it reaches another valid argument, or one of the other more specific settings
    /// for multiple values is used (such as [`num_args`]).
    ///
    /// **NOTE:** This setting only applies to [options] and [positional arguments]
    ///
    /// **NOTE:** When the terminator is passed in on the command line, it is **not** stored as one
    /// of the values
    function value_terminator(self, term: Str?) -> Arg {
        self._terminator = term;
        self
    }

    /// Consume all following arguments.
    ///
    /// Do not parse them individually, but rather pass them in entirety.
    ///
    /// It is worth noting that setting this requires all values to come after a `--` to indicate
    /// they should all be captured. For example:
    ///
    /// ```text
    /// --foo something -- -v -v -v -b -b -b --baz -q -u -x
    /// ```
    ///
    /// Will result in everything after `--` to be considered one raw argument. This behavior
    /// may not be exactly what you are expecting and using [`Arg::trailing_var_arg`]
    /// may be more appropriate.
    ///
    /// **NOTE:** Implicitly sets [`Arg::action(ArgAction::Set)`], [`Arg::num_args(1..)`],
    /// [`Arg::allow_hyphen_values(true)`], and [`Arg::last(true)`] when set to `true`.
    function raw(self, yes: bool) -> Arg {
        if (yes) {
            if (self._num_vals == null) { self._num_vals = ValueRange.from(1); }
        }
        self.allow_hyphen_values(yes).last(yes)
    }

    /// Value for the argument when not present.
    ///
    /// Like with command-line values, this will be split by [`Arg::value_delimiter`].
    ///
    /// **NOTE:** If the user *does not* use this argument at runtime [`ArgMatches::contains_id`] will
    /// still return `true`. If you wish to determine whether the argument was used at runtime or
    /// not, consider [`ArgMatches::value_source`][crate::ArgMatches::value_source].
    ///
    /// **NOTE:** This setting is perfectly compatible with [`Arg::default_value_if`] but slightly
    /// different. `Arg::default_value` *only* takes effect when the user has not provided this arg
    /// at runtime. `Arg::default_value_if` however only takes effect when the user has not provided
    /// a value at runtime **and** these other conditions are met as well. If you have set
    /// `Arg::default_value` and `Arg::default_value_if`, and the user **did not** provide this arg
    /// at runtime, nor were the conditions met for `Arg::default_value_if`, the `Arg::default_value`
    /// will be applied.
    function default_value(self, val: OsStr?) -> Arg {
        if let v: string = val {
            self.default_values([v])
        } else {
            self._default_vals.clear();
            self
        }
    }

    /// Deprecated, replaced with [`Arg::default_value`]
    function default_value_os(self, val: OsStr) -> Arg { self.default_values([val]) }

    /// Value for the argument when not present.
    ///
    /// See [`Arg::default_value`].
    function default_values(self, vals: OsStr[]) -> Arg {
        self._default_vals = vals.slice(0, vals.length());
        self
    }

    /// Deprecated, replaced with [`Arg::default_values`]
    function default_values_os(self, vals: OsStr[]) -> Arg { self.default_values(vals) }

    /// Value for the argument when the flag is present but no value is specified.
    ///
    /// This configuration option is often used to give the user a shortcut and allow them to
    /// efficiently specify an option argument without requiring an explicitly value. The `--color`
    /// argument is a common example. By supplying a default, such as `default_missing_value("always")`,
    /// the user can quickly just add `--color` to the command line to produce the desired color output.
    ///
    /// Like with command-line values, this will be split by [`Arg::value_delimiter`].
    ///
    /// **NOTE:** using this configuration option requires the use of the
    /// [`.num_args(0..N)`][Arg::num_args] and the
    /// [`.require_equals(true)`][Arg::require_equals] configuration option. These are required in
    /// order to unambiguously determine what, if any, value was supplied for the argument.
    function default_missing_value(self, val: OsStr?) -> Arg {
        if let v: string = val {
            self.default_missing_values_os([v])
        } else {
            self._default_missing_vals.clear();
            self
        }
    }

    /// Value for the argument when the flag is present but no value is specified.
    function default_missing_value_os(self, val: OsStr) -> Arg { self.default_missing_values_os([val]) }

    /// Value for the argument when the flag is present but no value is specified.
    function default_missing_values(self, vals: OsStr[]) -> Arg { self.default_missing_values_os(vals) }

    /// Value for the argument when the flag is present but no value is specified.
    function default_missing_values_os(self, vals: OsStr[]) -> Arg {
        self._default_missing_vals = vals.slice(0, vals.length());
        self
    }

    /// Read from `name` environment variable when argument is not present.
    ///
    /// If it is not present in the environment, then default
    /// rules will apply.
    ///
    /// If user sets the argument in the environment:
    /// - When [`Arg::action(ArgAction::Set)`] is not set, the flag is considered raised.
    /// - When [`Arg::action(ArgAction::Set)`] is set,
    ///   [`ArgMatches::get_one`][crate::ArgMatches::get_one] will
    ///   return value of the environment variable.
    ///
    /// If user doesn't set the argument in the environment:
    /// - When [`Arg::action(ArgAction::Set)`] is not set, the flag is considered off.
    /// - When [`Arg::action(ArgAction::Set)`] is set,
    ///   [`ArgMatches::get_one`][crate::ArgMatches::get_one] will
    ///   return the default specified.
    ///
    /// Like with command-line values, this will be split by [`Arg::value_delimiter`].
    function env(self, name: OsStr?) -> Arg {
        if let n: string = name {
            let value = baml.env.get(n) catch_all (e) { _ => null };
            self._env = ArgEnv { name: n, value: value };
        } else {
            self._env = null;
        }
        self
    }

    /// Deprecated, replaced with [`Arg::env`]
    function env_os(self, name: OsStr) -> Arg { self.env(name) }

    // ===== Help =====

    /// Sets the description of the argument for short help (`-h`).
    ///
    /// Typically, this is a short (one line) description of the arg.
    ///
    /// If [`Arg::long_help`] is not specified, this message will be displayed for `--help`.
    ///
    /// **NOTE:** Only `Arg::help` is used in completion script generation in order to be concise
    function help(self, h: StyledStr | string | null) -> Arg {
        self._help = into_styled_opt(h);
        self
    }

    /// Sets the description of the argument for long help (`--help`).
    ///
    /// Typically this a more detailed (multi-line) message
    /// that describes the arg.
    ///
    /// If [`Arg::help`] is not specified, this message will be displayed for `-h`.
    ///
    /// **NOTE:** Only [`Arg::help`] is used in completion script generation in order to be concise
    function long_help(self, h: StyledStr | string | null) -> Arg {
        self._long_help = into_styled_opt(h);
        self
    }

    /// Allows custom ordering of args within the help message.
    ///
    /// `Arg`s with a lower value will be displayed first in the help message.
    /// Those with the same display order will be sorted.
    ///
    /// `Arg`s are automatically assigned a display order based on the order they are added to the
    /// [`Command`][crate::Command].
    /// Overriding this is helpful when the order arguments are added in isn't the same as the
    /// display order, whether in one-off cases or to automatically sort arguments.
    ///
    /// To change, see [`Command::next_display_order`][crate::Command::next_display_order].
    ///
    /// **NOTE:** This setting is ignored for [positional arguments] which are always displayed in
    /// [index] order.
    function display_order(self, ord: int?) -> Arg {
        self._disp_ord = ord;
        self
    }

    /// Override the `current` help section.
    ///
    /// For more on the default help section, see
    /// [`Command::next_help_heading`][crate::Command::next_help_heading].
    function help_heading(self, heading: Str?) -> Arg {
        self._help_heading_set = true;
        self._help_heading = heading;
        self
    }

    /// Render the [help][Arg::help] on the line after the argument.
    ///
    /// This can be helpful for arguments with very long or complex help messages.
    /// This can also be helpful for arguments with very long flag names, or many/long value names.
    ///
    /// **NOTE:** To apply this setting to all arguments and subcommands, consider using
    /// [`crate::Command::next_line_help`]
    function next_line_help(self, yes: bool) -> Arg {
        if (yes) { self.setting(ArgSettings.NextLineHelp) } else { self.unset_setting(ArgSettings.NextLineHelp) }
    }

    /// Do not display the argument in help message.
    ///
    /// **NOTE:** This does **not** hide the argument from usage strings on error
    function hide(self, yes: bool) -> Arg {
        if (yes) { self.setting(ArgSettings.Hidden) } else { self.unset_setting(ArgSettings.Hidden) }
    }

    /// Do not display the [possible values][crate::builder::ValueParser::possible_values] in the help message.
    ///
    /// This is useful for args with many values, or ones which are explained elsewhere in the
    /// help text.
    ///
    /// To set this for all arguments, see
    /// [`Command::hide_possible_values`][crate::Command::hide_possible_values].
    ///
    /// **NOTE:** Setting this requires [taking values][Arg::num_args]
    function hide_possible_values(self, yes: bool) -> Arg {
        if (yes) { self.setting(ArgSettings.HidePossibleValues) } else { self.unset_setting(ArgSettings.HidePossibleValues) }
    }

    /// Do not display the default value of the argument in the help message.
    ///
    /// This is useful when default behavior of an arg is explained elsewhere in the help text.
    ///
    /// **NOTE:** Setting this requires [taking values][Arg::num_args]
    function hide_default_value(self, yes: bool) -> Arg {
        if (yes) { self.setting(ArgSettings.HideDefaultValue) } else { self.unset_setting(ArgSettings.HideDefaultValue) }
    }

    /// Do not display in help the environment variable name.
    ///
    /// This is useful when the variable option is explained elsewhere in the help text.
    function hide_env(self, yes: bool) -> Arg {
        if (yes) { self.setting(ArgSettings.HideEnv) } else { self.unset_setting(ArgSettings.HideEnv) }
    }

    /// Do not display in help any values inside the associated ENV variables for the argument.
    ///
    /// This is useful when ENV vars contain sensitive values.
    function hide_env_values(self, yes: bool) -> Arg {
        if (yes) { self.setting(ArgSettings.HideEnvValues) } else { self.unset_setting(ArgSettings.HideEnvValues) }
    }

    /// Hides an argument from short help (`-h`).
    ///
    /// **NOTE:** This does **not** hide the argument from usage strings on error
    ///
    /// **NOTE:** Setting this option will cause next-line-help output style to be used
    /// when long help (`--help`) is called.
    function hide_short_help(self, yes: bool) -> Arg {
        if (yes) { self.setting(ArgSettings.HiddenShortHelp) } else { self.unset_setting(ArgSettings.HiddenShortHelp) }
    }

    /// Hides an argument from long help (`--help`).
    ///
    /// **NOTE:** This does **not** hide the argument from usage strings on error
    ///
    /// **NOTE:** Setting this option will cause next-line-help output style to be used
    /// when long help (`--help`) is called.
    function hide_long_help(self, yes: bool) -> Arg {
        if (yes) { self.setting(ArgSettings.HiddenLongHelp) } else { self.unset_setting(ArgSettings.HiddenLongHelp) }
    }

    // ===== Advanced Argument Relations =====

    /// The name of the [`ArgGroup`] the argument belongs to.
    function group(self, group_id: Id?) -> Arg {
        if let g: string = group_id {
            self._groups.push(g);
        } else {
            self._groups.clear();
        }
        self
    }

    /// The names of [`ArgGroup`]'s the argument belongs to.
    function groups(self, group_ids: Id[]) -> Arg {
        for (let g in group_ids) { self._groups.push(g); }
        self
    }

    /// Specifies the value of the argument if `arg` has been used at runtime.
    ///
    /// If `default` is set to `None`, `default_value` will be removed.
    ///
    /// Like with command-line values, this will be split by [`Arg::value_delimiter`].
    ///
    /// **NOTE:** This setting is perfectly compatible with [`Arg::default_value`] but slightly
    /// different. `Arg::default_value` *only* takes effect when the user has not provided this arg
    /// at runtime. This setting however only takes effect when the user has not provided a value at
    /// runtime **and** these other conditions are met as well. If you have set `Arg::default_value`
    /// and `Arg::default_value_if`, and the user **did not** provide this arg at runtime, nor were
    /// the conditions met for `Arg::default_value_if`, the `Arg::default_value` will be applied.
    function default_value_if(self, arg_id: Id, predicate: ArgPredicate | string, default: OsStr?) -> Arg {
        self._default_vals_ifs.push(DefaultValueIf {
            id: arg_id,
            predicate: into_arg_predicate(predicate),
            values: if let d: string = default { [d] } else { null },
        });
        self
    }

    /// Specifies the values of the argument if `arg` has been used at runtime.
    ///
    /// See [`Arg::default_value_if`].
    function default_values_if(self, arg_id: Id, predicate: ArgPredicate | string, defaults: OsStr[]) -> Arg {
        self._default_vals_ifs.push(DefaultValueIf {
            id: arg_id,
            predicate: into_arg_predicate(predicate),
            values: defaults,
        });
        self
    }

    /// Specifies multiple values and conditions in the same manner as [`Arg::default_value_if`].
    ///
    /// The method takes a slice of tuples in the `(arg, predicate, default)` format.
    ///
    /// Like with command-line values, this will be split by [`Arg::value_delimiter`].
    ///
    /// **NOTE**: The conditions are stored in order and evaluated in the same order. I.e. the first
    /// if multiple conditions are true, the first one found will be applied and the ultimate value.
    function default_value_ifs(self, ifs: DefaultValueIf[]) -> Arg {
        for (let i in ifs) { self._default_vals_ifs.push(i); }
        self
    }

    /// Specifies multiple values and conditions in the same manner as [`Arg::default_values_if`].
    function default_values_ifs(self, ifs: DefaultValueIf[]) -> Arg {
        for (let i in ifs) { self._default_vals_ifs.push(i); }
        self
    }

    /// Set this arg as [required] as long as the specified argument is not present at runtime.
    ///
    /// **Pro Tip:** Using `Arg::required_unless_present` implies [`Arg::required`] and is therefore not
    /// mandatory to also set.
    function required_unless_present(self, arg_id: Id?) -> Arg {
        if let id: string = arg_id {
            self._r_unless.push(id);
        } else {
            self._r_unless.clear();
        }
        self
    }

    /// Sets this arg as [required] unless *all* of the specified arguments are present at runtime.
    ///
    /// In other words, parsing will succeed only if user either
    /// * supplies the `self` arg.
    /// * supplies *all* of the `names` arguments.
    ///
    /// **NOTE:** If you wish for this argument to only be required unless *any of* these args are
    /// present see [`Arg::required_unless_present_any`]
    function required_unless_present_all(self, names: Id[]) -> Arg {
        for (let n in names) { self._r_unless_all.push(n); }
        self
    }

    /// Sets this arg as [required] unless *any* of the specified arguments are present at runtime.
    ///
    /// In other words, parsing will succeed only if user either
    /// * supplies the `self` arg.
    /// * supplies *one or more* of the `unless` arguments.
    ///
    /// **NOTE:** If you wish for this argument to be required unless *all of* these args are
    /// present see [`Arg::required_unless_present_all`]
    function required_unless_present_any(self, names: Id[]) -> Arg {
        for (let n in names) { self._r_unless.push(n); }
        self
    }

    /// This argument is [required] only if the specified `arg` is present at runtime and its value
    /// equals `val`.
    function required_if_eq(self, arg_id: Id, val: OsStr) -> Arg {
        self._r_ifs.push(ArgIdValue { id: arg_id, value: val });
        self
    }

    /// Specify this argument is [required] based on multiple conditions.
    ///
    /// The conditions are set up in a `(arg, val)` style tuple. The requirement will only become
    /// valid if one of the specified `arg`'s value equals its corresponding `val`.
    function required_if_eq_any(self, ifs: ArgIdValue[]) -> Arg {
        for (let i in ifs) { self._r_ifs.push(i); }
        self
    }

    /// Specify this argument is [required] based on multiple conditions.
    ///
    /// The conditions are set up in a `(arg, val)` style tuple. The requirement will only become
    /// valid if every one of the specified `arg`'s value equals its corresponding `val`.
    function required_if_eq_all(self, ifs: ArgIdValue[]) -> Arg {
        for (let i in ifs) { self._r_ifs_all.push(i); }
        self
    }

    /// Require another argument if this arg matches the [`ArgPredicate`]
    ///
    /// This method takes `value, another_arg` pair. At runtime, clap will check
    /// if this arg (`self`) matches the [`ArgPredicate`].
    /// If it does, `another_arg` will be marked as required.
    function requires_if(self, val: ArgPredicate | string, arg_id: Id) -> Arg {
        self._requires.push(ArgRequire { predicate: into_arg_predicate(val), id: arg_id });
        self
    }

    /// Allows multiple conditional requirements.
    ///
    /// The requirement will only become valid if this arg's value matches the
    /// [`ArgPredicate`].
    function requires_ifs(self, ifs: ArgRequire[]) -> Arg {
        for (let i in ifs) { self._requires.push(i); }
        self
    }

    /// Deprecated, replaced with [`Arg::requires_ifs`]
    function requires_all(self, ids: Id[]) -> Arg {
        for (let id in ids) { self._requires.push(ArgRequire { predicate: ArgPredicateIsPresent {}, id: id }); }
        self
    }

    /// This argument is mutually exclusive with the specified argument.
    ///
    /// **NOTE:** Conflicting rules take precedence over being required by default. Conflict rules
    /// only need to be set for one of the two arguments, they do not need to be set for each.
    ///
    /// **NOTE:** Defining a conflict is two-way, but does *not* need to defined for both arguments
    /// (i.e. if A conflicts with B, defining `A.conflicts_with(B)` is sufficient. You do not
    /// need to also do `B.conflicts_with(A)`)
    ///
    /// **NOTE:** [`Arg::conflicts_with_all(names)`] allows specifying an argument which conflicts with more than one argument.
    ///
    /// **NOTE** [`Arg::exclusive(true)`] allows specifying an argument which conflicts with every other argument.
    ///
    /// **NOTE:** All arguments implicitly conflict with themselves.
    function conflicts_with(self, arg_id: Id?) -> Arg {
        if let id: string = arg_id {
            self._blacklist.push(id);
        } else {
            self._blacklist.clear();
        }
        self
    }

    /// This argument is mutually exclusive with the specified arguments.
    ///
    /// See [`Arg::conflicts_with`].
    function conflicts_with_all(self, names: Id[]) -> Arg {
        for (let n in names) { self._blacklist.push(n); }
        self
    }

    /// Sets an overridable argument.
    ///
    /// i.e. this argument and the following argument
    /// will override each other in POSIX style (whichever argument was specified at runtime
    /// **last** "wins")
    ///
    /// **NOTE:** When an argument is overridden it is essentially as if it never was used, any
    /// conflicts, requirements, etc. are evaluated **after** all "overrides" have been removed
    ///
    /// **NOTE:** Overriding an argument implies they [conflict][Arg::conflicts_with`].
    function overrides_with(self, arg_id: Id?) -> Arg {
        if let id: string = arg_id {
            self._overrides.push(id);
        } else {
            self._overrides.clear();
        }
        self
    }

    /// Sets multiple mutually overridable arguments by name.
    ///
    /// i.e. this argument and the following argument will override each other in POSIX style
    /// (whichever argument was specified at runtime **last** "wins")
    function overrides_with_all(self, names: Id[]) -> Arg {
        for (let n in names) { self._overrides.push(n); }
        self
    }

    // ===== Reflection =====

    /// Get the name of the argument
    function get_id(self) -> Id { self._id }

    /// Get the help specified for this argument, if any
    function get_help(self) -> StyledStr? { self._help }

    /// Get the long help specified for this argument, if any
    function get_long_help(self) -> StyledStr? { self._long_help }

    /// Get the placement within help
    function get_display_order(self) -> int { self._disp_ord ?? 999 }

    /// Get the help heading specified for this argument, if any
    function get_help_heading(self) -> string? {
        if (self._help_heading_set) { self._help_heading } else { null }
    }

    /// Get the short option name for this argument, if any
    function get_short(self) -> string? { self._short }

    /// Get visible short aliases for this argument, if any
    function get_visible_short_aliases(self) -> string[]? {
        if (self._short_aliases.length() == 0) {
            null
        } else {
            self._short_aliases.filter((a) -> { a.visible }).map((a) -> { a.name })
        }
    }

    /// Get *all* short aliases for this argument, if any, both visible and hidden.
    function get_all_short_aliases(self) -> string[]? {
        if (self._short_aliases.length() == 0) {
            null
        } else {
            self._short_aliases.map((a) -> { a.name })
        }
    }

    /// Get the short option name and its visible aliases, if any
    function get_short_and_visible_aliases(self) -> string[]? {
        let short = self._short;
        if (short == null) {
            return null;
        }
        let shorts: string[] = [short ?? ""];
        if let aliases: string[] = self.get_visible_short_aliases() {
            for (let a in aliases) { shorts.push(a); }
        }
        shorts
    }

    /// Get the long option name for this argument, if any
    function get_long(self) -> string? { self._long }

    /// Get visible aliases for this argument, if any
    function get_visible_aliases(self) -> string[]? {
        if (self._aliases.length() == 0) {
            null
        } else {
            self._aliases.filter((a) -> { a.visible }).map((a) -> { a.name })
        }
    }

    /// Get *all* aliases for this argument, if any, both visible and hidden.
    function get_all_aliases(self) -> string[]? {
        if (self._aliases.length() == 0) {
            null
        } else {
            self._aliases.map((a) -> { a.name })
        }
    }

    /// Get the long option name and its visible aliases, if any
    function get_long_and_visible_aliases(self) -> string[]? {
        let long = self._long;
        if (long == null) {
            return null;
        }
        let longs: string[] = [long ?? ""];
        if let aliases: string[] = self.get_visible_aliases() {
            for (let a in aliases) { longs.push(a); }
        }
        longs
    }

    /// Get hidden aliases for this argument, if any
    function get_aliases(self) -> string[]? {
        if (self._aliases.length() == 0) {
            null
        } else {
            self._aliases.filter((a) -> { !a.visible }).map((a) -> { a.name })
        }
    }

    /// Get the names of possible values for this argument. Only useful for user
    /// facing applications, such as building help messages or man files
    function get_possible_values(self) -> PossibleValue[] {
        if (!self.is_takes_value_set()) {
            []
        } else {
            self.get_value_parser().possible_values() ?? []
        }
    }

    /// Get the names of values for this argument.
    function get_value_names(self) -> Str[]? {
        if (self._val_names.length() == 0) { null } else { self._val_names }
    }

    /// Get the number of values for this argument.
    function get_num_args(self) -> ValueRange? { self._num_vals }

    function get_min_vals(self) -> int {
        (self.get_num_args() ?? ValueRange.SINGLE()).min_values()
    }

    /// Get the delimiter between multiple values
    function get_value_delimiter(self) -> string? { self._val_delim }

    /// Get the value terminator for this argument. The `value_terminator` is a value
    /// that terminates parsing of multi-valued arguments.
    function get_value_terminator(self) -> Str? { self._terminator }

    /// Get the index of this argument, if any
    function get_index(self) -> int? { self._index }

    /// Get the value hint of this argument
    function get_value_hint(self) -> ValueHint {
        // HACK: we should use `Self::add` and `Self::remove` to type-check that `ArgExt` is used
        let hint = self._ext.get<ValueHint>();
        if let h: ValueHint = hint {
            return h;
        }
        if (self.is_takes_value_set()) {
            let type_id = self.get_value_parser().type_id();
            if (type_id == AnyValueId.of<PathBuf>() && self.get_value_parser().is_path()) {
                ValueHint.AnyPath
            } else {
                ValueHint.Unknown
            }
        } else {
            ValueHint.Unknown
        }
    }

    /// Get the environment variable name specified for this argument, if any
    function get_env(self) -> OsStr? {
        if let e: ArgEnv = self._env { e.name } else { null }
    }

    /// Get the default values specified for this argument, if any
    function get_default_values(self) -> OsStr[] { self._default_vals }

    /// Checks whether this argument is a positional or not.
    function is_positional(self) -> bool {
        self.get_long() == null && self.get_short() == null
    }

    /// Reports whether [`Arg::required`] is set
    function is_required_set(self) -> bool { self.is_set(ArgSettings.Required) }

    function is_multiple_values_set(self) -> bool {
        (self.get_num_args() ?? ValueRange.SINGLE()).is_multiple()
    }

    function is_takes_value_set(self) -> bool {
        (self.get_num_args() ?? ValueRange.new(1)).takes_values()
    }

    /// Report whether [`Arg::allow_hyphen_values`] is set
    function is_allow_hyphen_values_set(self) -> bool { self.is_set(ArgSettings.AllowHyphenValues) }

    /// Report whether [`Arg::allow_negative_numbers`] is set
    function is_allow_negative_numbers_set(self) -> bool { self.is_set(ArgSettings.AllowNegativeNumbers) }

    /// Behavior when parsing the argument
    function get_action(self) -> ArgAction { self._action ?? ArgAction.Set }

    /// Configured parser for argument values
    function get_value_parser(self) -> ValueParser {
        if let vp: ValueParser = self._value_parser { vp } else { ValueParser.string() }
    }

    /// Report whether [`Arg::global`] is set
    function is_global_set(self) -> bool { self.is_set(ArgSettings.Global) }

    /// Report whether [`Arg::next_line_help`] is set
    function is_next_line_help_set(self) -> bool { self.is_set(ArgSettings.NextLineHelp) }

    /// Report whether [`Arg::hide`] is set
    function is_hide_set(self) -> bool { self.is_set(ArgSettings.Hidden) }

    /// Report whether [`Arg::hide_default_value`] is set
    function is_hide_default_value_set(self) -> bool { self.is_set(ArgSettings.HideDefaultValue) }

    /// Report whether [`Arg::hide_possible_values`] is set
    function is_hide_possible_values_set(self) -> bool { self.is_set(ArgSettings.HidePossibleValues) }

    /// Report whether [`Arg::hide_env`] is set
    function is_hide_env_set(self) -> bool { self.is_set(ArgSettings.HideEnv) }

    /// Report whether [`Arg::hide_env_values`] is set
    function is_hide_env_values_set(self) -> bool { self.is_set(ArgSettings.HideEnvValues) }

    /// Report whether [`Arg::hide_short_help`] is set
    function is_hide_short_help_set(self) -> bool { self.is_set(ArgSettings.HiddenShortHelp) }

    /// Report whether [`Arg::hide_long_help`] is set
    function is_hide_long_help_set(self) -> bool { self.is_set(ArgSettings.HiddenLongHelp) }

    /// Report whether [`Arg::require_equals`] is set
    function is_require_equals_set(self) -> bool { self.is_set(ArgSettings.RequireEquals) }

    /// Reports whether [`Arg::exclusive`] is set
    function is_exclusive_set(self) -> bool { self.is_set(ArgSettings.Exclusive) }

    /// Report whether [`Arg::trailing_var_arg`] is set
    function is_trailing_var_arg_set(self) -> bool { self.is_set(ArgSettings.TrailingVarArg) }

    /// Reports whether [`Arg::last`] is set
    function is_last_set(self) -> bool { self.is_set(ArgSettings.Last) }

    /// Reports whether [`Arg::ignore_case`] is set
    function is_ignore_case_set(self) -> bool { self.is_set(ArgSettings.IgnoreCase) }

    // ===== Internal =====

    function _build(self) -> void {
        if (self._action == null) {
            if (self._num_vals == ValueRange.EMPTY()) {
                self._action = ArgAction.SetTrue;
            } else {
                let unbounded = (self._num_vals ?? ValueRange.SINGLE()).is_unbounded();
                // Allow collecting arguments interleaved with flags
                //
                // Bounded values are probably a group and the user should explicitly opt-in to
                // Append
                self._action = if (self.is_positional() && unbounded) { ArgAction.Append } else { ArgAction.Set };
            }
        }

        if let action: ArgAction = self._action {
            if let default_value: string = action_default_value(action) {
                if (self._default_vals.length() == 0) {
                    self._default_vals = [default_value];
                }
            }
            if let default_value: string = action_default_missing_value(action) {
                if (self._default_missing_vals.length() == 0) {
                    self._default_missing_vals = [default_value];
                }
            }
        }

        if (self._value_parser == null) {
            let default = if let a: ArgAction = self._action { action_default_value_parser(a) } else { null };
            self._value_parser = default ?? ValueParser.string();
        }

        let val_names_len = self._val_names.length();
        if (val_names_len > 1) {
            if (self._num_vals == null) { self._num_vals = ValueRange.new(val_names_len); }
        } else {
            let nargs = action_default_num_args(self.get_action());
            if (self._num_vals == null) { self._num_vals = nargs; }
        }
    }

    /// Used for positionals when printing
    function name_no_brackets(self) -> string {
        let delim = " ";
        if (self._val_names.length() > 0) {
            if (self._val_names.length() > 1) {
                self._val_names.map((n) -> { `<${n}>` }).join(delim)
            } else {
                self._val_names[0]
            }
        } else {
            self.get_id()
        }
    }

    function stylized(self, styles: Styles, required: bool?) -> StyledStr {
        let literal = styles.get_literal();

        let styled = StyledStr.new();
        // Write the name such --long or -l
        if let l: string = self.get_long() {
            styled.push_styled_str(literal, `--${l}`);
        } else if let s: string = self.get_short() {
            styled.push_styled_str(literal, `-${s}`);
        }
        styled.push_styled(self.stylize_arg_suffix(styles, required));
        styled
    }

    function stylize_arg_suffix(self, styles: Styles, required: bool?) -> StyledStr {
        let literal = styles.get_literal();
        let placeholder = styles.get_placeholder();
        let styled = StyledStr.new();

        let need_closing_bracket = false;
        if (self.is_takes_value_set() && !self.is_positional()) {
            let is_optional_val = self.get_min_vals() == 0;
            let style = placeholder;
            let start = " ";
            if (self.is_require_equals_set()) {
                if (is_optional_val) {
                    need_closing_bracket = true;
                    start = "[=";
                } else {
                    style = literal;
                    start = "=";
                }
            } else if (is_optional_val) {
                need_closing_bracket = true;
                start = " [";
            }
            styled.push_styled_str(style, start);
        }
        if (self.is_takes_value_set() || self.is_positional()) {
            let req = required ?? self.is_required_set();
            let arg_val = self.render_arg_val(req);
            styled.push_styled_str(placeholder, arg_val);
        } else if (self.get_action() == ArgAction.Count) {
            styled.push_styled_str(placeholder, "...");
        }
        if (need_closing_bracket) {
            styled.push_styled_str(placeholder, "]");
        }

        styled
    }

    function render_arg_val(self, required: bool) -> string {
        let rendered = "";

        let num_vals = self.get_num_args() ?? ValueRange.new(1);

        let val_names = if (self._val_names.length() == 0) {
            [self._id]
        } else {
            self._val_names.slice(0, self._val_names.length())
        };
        if (val_names.length() == 1) {
            let min = if (num_vals.min_values() > 1) { num_vals.min_values() } else { 1 };
            let val_name = val_names[0];
            val_names = baml.Array.filled(min, val_name);
        }

        for (let n in baml.iter.Range.new(0, val_names.length())) {
            let val_name = val_names[n];
            let arg_name = if (self.is_positional() && (num_vals.min_values() == 0 || !required)) {
                `[${val_name}]`
            } else {
                `<${val_name}>`
            };

            if (n != 0) {
                rendered = rendered + " ";
            }
            rendered = rendered + arg_name;
        }

        let extra_values = val_names.length() < num_vals.max_values();
        if (self.is_positional() && self.get_action() == ArgAction.Append) {
            extra_values = true;
        }
        if (extra_values) {
            rendered = rendered + "...";
        }

        rendered
    }

    /// Either multiple values or occurrences
    function is_multiple(self) -> bool {
        self.is_multiple_values_set() || self.get_action() == ArgAction.Append
    }

    /// `impl Clone for Arg`
    function clone(self) -> Arg {
        Arg {
            ...self,
            _blacklist: self._blacklist.slice(0, self._blacklist.length()),
            _settings: self._settings.copy(),
            _overrides: self._overrides.slice(0, self._overrides.length()),
            _groups: self._groups.slice(0, self._groups.length()),
            _requires: self._requires.slice(0, self._requires.length()),
            _r_ifs: self._r_ifs.slice(0, self._r_ifs.length()),
            _r_ifs_all: self._r_ifs_all.slice(0, self._r_ifs_all.length()),
            _r_unless: self._r_unless.slice(0, self._r_unless.length()),
            _r_unless_all: self._r_unless_all.slice(0, self._r_unless_all.length()),
            _aliases: self._aliases.slice(0, self._aliases.length()),
            _short_aliases: self._short_aliases.slice(0, self._short_aliases.length()),
            _val_names: self._val_names.slice(0, self._val_names.length()),
            _default_vals: self._default_vals.slice(0, self._default_vals.length()),
            _default_vals_ifs: self._default_vals_ifs.slice(0, self._default_vals_ifs.length()),
            _default_missing_vals: self._default_missing_vals.slice(0, self._default_missing_vals.length()),
            _ext: self._ext.clone(),
        }
    }

    /// `impl Display for Arg`
    implements baml.ToString {
        function to_string(self) -> string throws never {
            let plain = Styles.plain();
            self.stylized(plain, null).to_string()
        }
    }
}

/// `impl PartialEq for Arg` (compares ids)
function arg_eq(a: Arg, b: Arg) -> bool { a.get_id() == b.get_id() }
