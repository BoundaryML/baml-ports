// Port of clap_builder/src/parser/matches/arg_matches.rs

/// `(&str, &ArgMatches)` returned by [`ArgMatches::subcommand`]
class SubcommandMatch {
    name: string,
    matches: ArgMatches,
}

/// Container for parse results.
///
/// Used to get information about the arguments that were supplied to the program at runtime by
/// the user. New instances of this struct are obtained by using the [`Command::get_matches`] family of
/// methods.
///
/// # Examples
///
/// ```baml
/// let matches = Command.new("MyApp")
///     .arg(Arg.new("out")
///         .long("output")
///         .required(true)
///         .action(ArgAction.Set)
///         .default_value("-"))
///     .arg(Arg.new("cfg")
///         .short("c")
///         .action(ArgAction.Set))
///     .get_matches(); // builds the instance of ArgMatches
///
/// // to get information about the "cfg" argument we created, such as the value supplied we use
/// // various ArgMatches methods, such as [ArgMatches::get_one]
/// if let c: string = matches.get_one<string>("cfg") {
///     baml.io.println(`Value for -c: ${c}`);
/// }
/// ```
class ArgMatches {
    _valid_args: Id[],
    _valid_subcommands: Str[],
    _args: FlatMap<Id, MatchedArg>,
    _subcommand: SubCommand?,

    function new() -> ArgMatches {
        ArgMatches { _valid_args: [], _valid_subcommands: [], _args: FlatMap.new(), _subcommand: null }
    }

    /// Gets the value of a specific option or positional argument.
    ///
    /// i.e. an argument that [takes an additional value][crate::Arg::num_args] at runtime.
    ///
    /// Returns an error if the wrong type was used.
    ///
    /// Returns `None` if the option wasn't present.
    ///
    /// **NOTE:** This will always return `Some(value)` if [`default_value`] has been set.
    /// [`ArgMatches::value_source`] can be used to check if a value is present at runtime.
    ///
    /// # Panic
    ///
    /// If the argument definition and access mismatch (debug builds). To handle this case
    /// programmatically, see [`ArgMatches::try_get_one`].
    function get_one<T>(self, id: string) -> T? {
        self.try_get_one<T>(id) catch (e) {
            let err: MatchesError => matches_error_panic(id, err),
        }
    }

    /// Gets the value of a specific [`ArgAction::Count`][crate::ArgAction::Count] flag
    ///
    /// # Panic
    ///
    /// If the argument's action is not [`ArgAction::Count`][crate::ArgAction::Count]
    function get_count(self, id: string) -> int {
        self.get_one<int>(id) ?? baml.sys.panic(`arg \`${id}\`'s \`ArgAction\` should be \`Count\` which should provide a default`)
    }

    /// Gets the value of a specific [`ArgAction::SetTrue`][crate::ArgAction::SetTrue] or [`ArgAction::SetFalse`][crate::ArgAction::SetFalse] flag
    ///
    /// # Panic
    ///
    /// If the argument's action is not [`ArgAction::SetTrue`][crate::ArgAction::SetTrue] or [`ArgAction::SetFalse`][crate::ArgAction::SetFalse]
    function get_flag(self, id: string) -> bool {
        self.get_one<bool>(id) ?? baml.sys.panic(`arg \`${id}\`'s \`ArgAction\` should be one of \`SetTrue\`, \`SetFalse\` which should provide a default`)
    }

    /// Iterate over values of a specific option or positional argument.
    ///
    /// i.e. an argument that takes multiple values at runtime.
    ///
    /// Returns an error if the wrong type was used.
    ///
    /// Returns `None` if the option wasn't present.
    ///
    /// # Panic
    ///
    /// If the argument definition and access mismatch (debug builds). To handle this case
    /// programmatically, see [`ArgMatches::try_get_many`].
    function get_many<T>(self, id: string) -> T[]? {
        self.try_get_many<T>(id) catch (e) {
            let err: MatchesError => matches_error_panic(id, err),
        }
    }

    /// Iterate over the values passed to each occurrence of an option.
    ///
    /// Each item is itself an iterator containing the arguments passed to a single occurrence
    /// of the option.
    ///
    /// If the option doesn't support multiple occurrences, or there was only a single occurrence,
    /// the iterator will only contain a single item.
    ///
    /// Returns `None` if the option wasn't present.
    ///
    /// # Panics
    ///
    /// If the argument definition and access mismatch (debug builds). To handle this case
    /// programmatically, see [`ArgMatches::try_get_occurrences`].
    function get_occurrences<T>(self, id: string) -> T[][]? {
        self.try_get_occurrences<T>(id) catch (e) {
            let err: MatchesError => matches_error_panic(id, err),
        }
    }

    /// Iterate over the original argument values.
    ///
    /// An `OsStr` on Unix-like systems is any series of bytes, regardless of whether or not they
    /// contain valid UTF-8. Since [`String`]s in Rust are guaranteed to be valid UTF-8, a valid
    /// filename on a Unix system as an argument value may contain invalid UTF-8.
    ///
    /// Returns `None` if the option wasn't present.
    ///
    /// # Panic
    ///
    /// If the argument definition and access mismatch (debug builds). To handle this case
    /// programmatically, see [`ArgMatches::try_get_raw`].
    function get_raw(self, id: string) -> OsString[]? {
        self.try_get_raw(id) catch (e) {
            let err: MatchesError => matches_error_panic(id, err),
        }
    }

    /// Iterate over the original values for each occurrence of an option.
    ///
    /// Similar to [`ArgMatches::get_occurrences`] but returns raw values.
    function get_raw_occurrences(self, id: string) -> OsString[][]? {
        self.try_get_raw_occurrences(id) catch (e) {
            let err: MatchesError => matches_error_panic(id, err),
        }
    }

    /// Returns the value of a specific option or positional argument.
    ///
    /// i.e. an argument that [takes an additional value][crate::Arg::num_args] at runtime.
    ///
    /// Returns an error if the wrong type was used.  No item will have been removed.
    ///
    /// Returns `None` if the option wasn't present.
    ///
    /// **NOTE:** This will always return `Some(value)` if [`default_value`] has been set.
    /// [`ArgMatches::value_source`] can be used to check if a value is present at runtime.
    ///
    /// # Panic
    ///
    /// If the argument definition and access mismatch (debug builds). To handle this case
    /// programmatically, see [`ArgMatches::try_remove_one`].
    function remove_one<T>(self, id: string) -> T? {
        self.try_remove_one<T>(id) catch (e) {
            let err: MatchesError => matches_error_panic(id, err),
        }
    }

    /// Return values of a specific option or positional argument.
    ///
    /// i.e. an argument that takes multiple values at runtime.
    ///
    /// Returns an error if the wrong type was used.  No item will have been removed.
    ///
    /// Returns `None` if the option wasn't present.
    ///
    /// # Panic
    ///
    /// If the argument definition and access mismatch (debug builds). To handle this case
    /// programmatically, see [`ArgMatches::try_remove_many`].
    function remove_many<T>(self, id: string) -> T[]? {
        self.try_remove_many<T>(id) catch (e) {
            let err: MatchesError => matches_error_panic(id, err),
        }
    }

    /// Return values for each occurrence of an option.
    ///
    /// Each item is itself an iterator containing the arguments passed to a single occurrence of
    /// the option.
    ///
    /// If the option doesn't support multiple occurrences, or there was only a single occurrence,
    /// the iterator will only contain a single item.
    ///
    /// Returns `None` if the option wasn't present.
    ///
    /// # Panic
    ///
    /// If the argument definition and access mismatch (debug builds). To handle this case
    /// programmatically, see [`ArgMatches::try_remove_occurrences`].
    function remove_occurrences<T>(self, id: string) -> T[][]? {
        self.try_remove_occurrences<T>(id) catch (e) {
            let err: MatchesError => matches_error_panic(id, err),
        }
    }

    /// Check if values are present for the argument or group id
    ///
    /// *NOTE:* This will always return `true` if [`default_value`] has been set.
    /// [`ArgMatches::value_source`] can be used to check if a value is present at runtime.
    ///
    /// # Panics
    ///
    /// If `id` is not a valid argument or group name (debug builds).  To handle this case programmatically, see
    /// [`ArgMatches::try_contains_id`].
    function contains_id(self, id: string) -> bool {
        self.try_contains_id(id) catch (e) {
            let err: MatchesError => matches_error_panic(id, err),
        }
    }

    /// Iterate over [`Arg`][crate::Arg] and [`ArgGroup`][crate::ArgGroup] [`Id`]s via [`ArgMatches::ids`].
    function ids(self) -> Id[] { self._args.get_keys() }

    /// Check if any [`Arg`][crate::Arg]s were present on the command line
    ///
    /// See [`ArgMatches::subcommand_name()`] or [`ArgMatches::subcommand()`] to check if a
    /// subcommand was present on the command line.
    function args_present(self) -> bool {
        self._args.get_values().some((v) -> {
            if let s: ValueSource = v.source() { value_source_is_explicit(s) } else { false }
        })
    }

    /// Report where argument value came from
    ///
    /// # Panics
    ///
    /// If `id` is not a valid argument or group id (debug builds).
    function value_source(self, id: string) -> ValueSource? {
        let value = self.get_arg(id);
        if let v: MatchedArg = value { v.source() } else { null }
    }

    /// The first index of that an argument showed up.
    ///
    /// Indices are similar to argv indices, but are not exactly 1:1.
    ///
    /// For flags (i.e. those arguments which don't have an associated value), indices refer
    /// to occurrence of the switch, such as `-f`, or `--flag`. However, for options the indices
    /// refer to the *values* `-o val` would therefore not represent two distinct indices, only the
    /// index for `val` would be recorded. This is by design.
    ///
    /// Besides the flag/option discrepancy, the primary difference between an argv index and clap
    /// index, is that clap continues counting once all arguments have properly separated, whereas
    /// an argv index does not.
    ///
    /// The examples should clear this up.
    ///
    /// **NOTE:** If an argument is allowed multiple times, this method will only give the *first*
    /// index.  See [`ArgMatches::indices_of`].
    ///
    /// # Panics
    ///
    /// If `id` is not a valid argument or group id (debug builds).
    function index_of(self, id: string) -> int? {
        let arg = self.get_arg(id);
        if let a: MatchedArg = arg { a.get_index(0) } else { null }
    }

    /// All indices an argument appeared at when parsing.
    ///
    /// Indices are similar to argv indices, but are not exactly 1:1.
    ///
    /// For flags (i.e. those arguments which don't have an associated value), indices refer
    /// to occurrence of the switch, such as `-f`, or `--flag`. However, for options the indices
    /// refer to the *values* `-o val` would therefore not represent two distinct indices, only the
    /// index for `val` would be recorded. This is by design.
    ///
    /// *NOTE:* For more information about how clap indices compared to argv indices, see
    /// [`ArgMatches::index_of`]
    ///
    /// # Panics
    ///
    /// If `id` is not a valid argument or group id (debug builds).
    function indices_of(self, id: string) -> int[]? {
        let arg = self.get_arg(id);
        if let a: MatchedArg = arg { a.indices() } else { null }
    }

    // ===== Subcommands =====

    /// The name and `ArgMatches` of the current [subcommand].
    ///
    /// Subcommand values are put in a child [`ArgMatches`]
    ///
    /// Returns `None` if the subcommand wasn't present at runtime,
    function subcommand(self) -> SubcommandMatch? {
        if let sc: SubCommand = self._subcommand {
            SubcommandMatch { name: sc.name, matches: sc.matches }
        } else {
            null
        }
    }

    /// Return the name and `ArgMatches` of the current [subcommand].
    ///
    /// Subcommand values are put in a child [`ArgMatches`]
    ///
    /// Returns `None` if the subcommand wasn't present at runtime,
    function remove_subcommand(self) -> SubcommandMatch? {
        let sc = self.subcommand();
        self._subcommand = null;
        sc
    }

    /// The `ArgMatches` for the current [subcommand].
    ///
    /// Subcommand values are put in a child [`ArgMatches`]
    ///
    /// Returns `None` if the subcommand wasn't present at runtime,
    ///
    /// # Panics
    ///
    /// If `id` is not a valid subcommand (debug builds).
    function subcommand_matches(self, name: string) -> ArgMatches? {
        let sc = self.get_subcommand(name);
        if let s: SubCommand = sc { s.matches } else { null }
    }

    /// The name of the current [subcommand].
    ///
    /// Returns `None` if the subcommand wasn't present at runtime,
    function subcommand_name(self) -> string? {
        if let sc: SubCommand = self._subcommand { sc.name } else { null }
    }

    /// Check if a subcommand can be queried
    ///
    /// By default, `ArgMatches` functions assert that it is valid to query a subcommand, to help
    /// catch programmer mistakes. In some context, this doesn't work, like when forwarding
    /// arguments to another function that happens to be a subcommand.
    function is_valid_subcommand(self, name: string) -> bool {
        name.is_empty() || self._valid_subcommands.some((s) -> { s == name })
    }

    // ===== Advanced =====

    /// Non-panicking version of [`ArgMatches::get_one`]
    function try_get_one<T>(self, id: string) -> T? throws MatchesError {
        let arg = self.try_get_arg_t<T>(id);
        let value = if let a: MatchedArg = arg { a.first() } else { null };
        if let v: AnyValue = value {
            // enforced by `try_get_arg_t`
            unwrap_downcast_ref<T>(v)
        } else {
            null
        }
    }

    /// Non-panicking version of [`ArgMatches::get_many`]
    function try_get_many<T>(self, id: string) -> T[]? throws MatchesError {
        let arg = self.try_get_arg_t<T>(id);
        if let a: MatchedArg = arg {
            // enforced by `try_get_arg_t`
            a.vals_flatten().map((v) -> { unwrap_downcast_ref<T>(v) })
        } else {
            null
        }
    }

    /// Non-panicking version of [`ArgMatches::get_occurrences`]
    function try_get_occurrences<T>(self, id: string) -> T[][]? throws MatchesError {
        let arg = self.try_get_arg_t<T>(id);
        if let a: MatchedArg = arg {
            a.vals().map((g) -> { g.map((v) -> { unwrap_downcast_ref<T>(v) }) })
        } else {
            null
        }
    }

    /// Non-panicking version of [`ArgMatches::get_raw`]
    function try_get_raw(self, id: string) -> OsString[]? throws MatchesError {
        let arg = self.try_get_arg(id);
        if let a: MatchedArg = arg { a.raw_vals_flatten() } else { null }
    }

    /// Non-panicking version of [`ArgMatches::get_raw_occurrences`]
    function try_get_raw_occurrences(self, id: string) -> OsString[][]? throws MatchesError {
        let arg = self.try_get_arg(id);
        if let a: MatchedArg = arg { a.raw_vals() } else { null }
    }

    /// Non-panicking version of [`ArgMatches::remove_one`]
    function try_remove_one<T>(self, id: string) -> T? throws MatchesError {
        let values = self.try_remove_arg_t<T>(id);
        if let m: MatchedArg = values {
            // enforced by `try_get_arg_t`
            let first = m.into_vals_flatten().at(0);
            if let v: AnyValue = first { unwrap_downcast_ref<T>(v) } else { null }
        } else {
            null
        }
    }

    /// Non-panicking version of [`ArgMatches::remove_many`]
    function try_remove_many<T>(self, id: string) -> T[]? throws MatchesError {
        let arg = self.try_remove_arg_t<T>(id);
        if let a: MatchedArg = arg {
            a.into_vals_flatten().map((v) -> { unwrap_downcast_ref<T>(v) })
        } else {
            null
        }
    }

    /// Non-panicking version of [`ArgMatches::remove_occurrences`]
    function try_remove_occurrences<T>(self, id: string) -> T[][]? throws MatchesError {
        let arg = self.try_remove_arg_t<T>(id);
        if let a: MatchedArg = arg {
            a.into_vals().map((g) -> { g.map((v) -> { unwrap_downcast_ref<T>(v) }) })
        } else {
            null
        }
    }

    /// Non-panicking version of [`ArgMatches::contains_id`]
    function try_contains_id(self, id: string) -> bool throws MatchesError {
        self.verify_arg(id);

        let presence = self._args.contains_key(id);
        presence
    }

    /// Clears the values for the given `id`
    ///
    /// Alternative to [`try_remove_*`][ArgMatches::try_remove_one] when the type is not known.
    ///
    /// Returns `Err([``MatchesError``])` if the given `id` isn't valid for current `ArgMatches` instance.
    ///
    /// Returns `Ok(true)` if there were any matches with the given `id`, `Ok(false)` otherwise.
    function try_clear_id(self, id: string) -> bool throws MatchesError {
        self.verify_arg(id);
        self._args.remove(id) != null
    }

    // ===== Private methods =====

    function try_get_arg(self, arg: string) -> MatchedArg? throws MatchesError {
        self.verify_arg(arg);
        self._args.get(arg)
    }

    function try_get_arg_t<T>(self, arg: string) -> MatchedArg? throws MatchesError {
        let a = self.try_get_arg(arg);
        if let m: MatchedArg = a {
            self.verify_arg_t<T>(m);
            m
        } else {
            null
        }
    }

    function try_remove_arg_t<T>(self, arg: string) -> MatchedArg? throws MatchesError {
        self.verify_arg(arg);
        let removed = self._args.remove(arg);
        if let matched: MatchedArg = removed {
            let expected = AnyValueId.of<T>();
            let actual = matched.infer_type_id(expected);
            if (type_ids_compatible(actual, expected)) {
                matched
            } else {
                self._args.insert(arg, matched);
                throw MatchesErrorDowncast { actual: actual, expected: expected }
            }
        } else {
            null
        }
    }

    function verify_arg_t<T>(self, arg: MatchedArg) -> void throws MatchesError {
        let expected = AnyValueId.of<T>();
        let actual = arg.infer_type_id(expected);
        if (!type_ids_compatible(actual, expected)) {
            throw MatchesErrorDowncast { actual: actual, expected: expected };
        }
    }

    function verify_arg(self, arg: string) -> void throws MatchesError {
        if (arg == ID_EXTERNAL() || self._valid_args.some((s) -> { s == arg })) {
        } else {
            throw MatchesErrorUnknownArgument {};
        }
    }

    function get_arg(self, arg: string) -> MatchedArg? {
        if (arg == ID_EXTERNAL() || self._valid_args.some((s) -> { s == arg })) {
        } else {
            baml.sys.panic(`"${arg}" is not an id of an argument or a group.\nMake sure you're using the name of the argument itself and not the name of short or long flags.`);
        }

        self._args.get(arg)
    }

    function get_subcommand(self, name: string) -> SubCommand? {
        if (name.is_empty() || self._valid_subcommands.some((s) -> { s == name })) {
        } else {
            baml.sys.panic(`\`${name}\` is not a name of a subcommand.`);
        }

        if let sc: SubCommand = self._subcommand {
            if (sc.name == name) {
                return sc;
            }
        }

        null
    }

    function clone(self) -> ArgMatches {
        let args: FlatMap<Id, MatchedArg> = FlatMap.new();
        let keys = self._args.get_keys();
        let values = self._args.get_values();
        for (let i in baml.iter.Range.new(0, keys.length())) {
            args.insert_unchecked(keys[i], values[i].clone());
        }
        ArgMatches {
            _valid_args: self._valid_args,
            _valid_subcommands: self._valid_subcommands,
            _args: args,
            _subcommand: if let sc: SubCommand = self._subcommand { SubCommand { name: sc.name, matches: sc.matches.clone() } } else { null },
        }
    }
}

class SubCommand {
    name: string,
    matches: ArgMatches,
}

/// `TypeId` equality, with BAML's `unknown` accepting anything (there is no
/// Rust equivalent: `Any` itself cannot be the target of `downcast_ref`)
function type_ids_compatible(actual: AnyValueId, expected: AnyValueId) -> bool {
    if (expected.type_name == "unknown" || actual.type_name == "unknown") {
        return true;
    }
    if (actual == expected) {
        return true;
    }
    // A union target (e.g. `string | int`) accepts any of its members
    expected.type_name.split(" | ").includes(actual.type_name)
}

function unwrap_downcast_ref<T>(value: AnyValue) -> T {
    match (value.inner()) {
        let t: T => t,
        _ => baml.sys.panic(INTERNAL_ERROR_MSG()),
    }
}
