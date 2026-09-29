// Port of clap_builder/src/derive.rs
//
// This module contains traits that are usable with the `#[derive(...)]`
// macros in `clap_derive`.
//
// The traits are BAML interfaces. In Rust, `#[derive(Parser)]` writes the trait
// bodies at compile time; BAML has no macros, so the interfaces carry default
// bodies that dispatch to `clap_derive`'s reflection-based expansion
// (`root.clap_derive`). A class opts in the same way a Rust struct derives:
//
// ```baml
// /// A simple program
// /// #[command(version, about, long_about = None)]
// class Cli {
//     /// Name of the person to greet
//     /// #[arg(short, long)]
//     name: string,
//
//     implements root.clap_builder.Parser {}
//     implements root.clap_builder.CommandFactory {}
//     implements root.clap_builder.FromArgMatches {}
//     implements root.clap_builder.Args {}
// }
//
// let cli = Cli.parse();
// ```
//
// (`#[derive(Parser)]` expands to the same four impls in Rust.)

/// Parse command-line arguments into `Self`.
///
/// The primary one-stop-shop trait used to create an instance of a `clap`
/// [`Command`], conduct the parsing, and turn the resulting [`ArgMatches`] back
/// into concrete instance of the user struct.
///
/// This trait is primarily a convenience on top of [`FromArgMatches`] +
/// [`CommandFactory`] which uses those two underlying traits to build the two
/// fundamental functions `parse` which uses the `std::env::args_os` iterator,
/// and `parse_from` which allows the consumer to supply the iterator (along
/// with fallible options for each).
///
/// See also [`Subcommand`] and [`Args`].
///
/// **NOTE:** Deriving requires the `derive` feature flag
interface Parser requires FromArgMatches, CommandFactory {
    /// Parse from `std::env::args_os()`, [exit][Error::exit] on error.
    function parse() -> Self throws never {
        let matches = (Self as CommandFactory).command().get_matches();
        (Self as FromArgMatches).from_arg_matches_mut(matches) catch (e) {
            // Since this is more of a development-time error, we aren't doing as fancy of a quit
            // as `get_matches`
            let err: Error => format_error<Self>(err).exit(),
        }
    }

    /// Parse from `std::env::args_os()`, return Err on error.
    function try_parse() -> Self throws Error {
        let matches = (Self as CommandFactory).command().try_get_matches();
        (Self as FromArgMatches).from_arg_matches_mut(matches) catch (e) {
            let err: Error => throw format_error<Self>(err),
        }
    }

    /// Parse from iterator, [exit][Error::exit] on error.
    function parse_from(itr: string[]) -> Self throws never {
        let matches = (Self as CommandFactory).command().get_matches_from(itr);
        (Self as FromArgMatches).from_arg_matches_mut(matches) catch (e) {
            // Since this is more of a development-time error, we aren't doing as fancy of a quit
            // as `get_matches_from`
            let err: Error => format_error<Self>(err).exit(),
        }
    }

    /// Parse from iterator, return Err on error.
    function try_parse_from(itr: string[]) -> Self throws Error {
        let matches = (Self as CommandFactory).command().try_get_matches_from(itr);
        (Self as FromArgMatches).from_arg_matches_mut(matches) catch (e) {
            let err: Error => throw format_error<Self>(err),
        }
    }

    /// Update from iterator, [exit][Error::exit] on error.
    ///
    /// Unlike [`Parser::parse`], this works with an existing instance of `self`.
    /// The assumption is that all required fields are already provided and any [`Args`] or
    /// [`Subcommand`]s provided by the user will modify only what is specified.
    function update_from(self, itr: string[]) -> void throws never {
        let matches = (Self as CommandFactory).command_for_update().get_matches_from(itr);
        self.update_from_arg_matches_mut(matches) catch (e) {
            // Since this is more of a development-time error, we aren't doing as fancy of a quit
            // as `get_matches_from`
            let err: Error => format_error<Self>(err).exit(),
        }
    }

    /// Update from iterator, return Err on error.
    function try_update_from(self, itr: string[]) -> void throws Error {
        let matches = (Self as CommandFactory).command_for_update().try_get_matches_from(itr);
        self.update_from_arg_matches_mut(matches) catch (e) {
            let err: Error => throw format_error<Self>(err),
        }
    }
}

/// Create a [`Command`] relevant for a user-defined container.
///
/// Derived as part of [`Parser`].
interface CommandFactory {
    /// Build a [`Command`] that can instantiate `Self`.
    ///
    /// See [`FromArgMatches::from_arg_matches_mut`] for instantiating `Self`.
    function command() -> Command throws never {
        root.clap_derive.into_app<Self>()
    }

    /// Build a [`Command`] that can update `self`.
    ///
    /// See [`FromArgMatches::update_from_arg_matches_mut`] for updating `self`.
    function command_for_update() -> Command throws never {
        root.clap_derive.into_app_for_update<Self>()
    }
}

/// Converts an instance of [`ArgMatches`] to a user-defined container.
///
/// Derived as part of [`Parser`], [`Args`], and [`Subcommand`].
interface FromArgMatches {
    /// Instantiate `Self` from [`ArgMatches`], parsing the arguments as needed.
    ///
    /// Motivation: If our application had two CLI options, `--name
    /// <STRING>` and the flag `--debug`, we may create a struct as follows:
    ///
    /// ```baml
    /// class Context {
    ///     name: string,
    ///     debug: bool,
    /// }
    /// ```
    ///
    /// We then need to convert the `ArgMatches` that `clap` generated into our struct.
    /// `from_arg_matches` serves as the equivalent of:
    ///
    /// ```baml
    /// function from_arg_matches(m: ArgMatches) -> Context {
    ///    Context {
    ///        name: m.get_one<string>("name") ?? "",
    ///        debug: m.get_flag("debug"),
    ///    }
    /// }
    /// ```
    function from_arg_matches(matches: ArgMatches) -> Self throws Error {
        root.clap_derive.from_arg_matches<Self>(matches)
    }

    /// Instantiate `Self` from [`ArgMatches`], parsing the arguments as needed.
    ///
    /// Motivation: If our application had two CLI options, `--name
    /// <STRING>` and the flag `--debug`, we may create a struct as follows:
    ///
    /// We then need to convert the `ArgMatches` that `clap` generated into our struct.
    /// `from_arg_matches_mut` serves as the equivalent of:
    function from_arg_matches_mut(matches: ArgMatches) -> Self throws Error {
        (Self as FromArgMatches).from_arg_matches(matches)
    }

    /// Assign values from `ArgMatches` to `self`.
    function update_from_arg_matches(self, matches: ArgMatches) -> void throws Error {
        root.clap_derive.update_from_arg_matches<Self>(self, matches)
    }

    /// Assign values from `ArgMatches` to `self`.
    function update_from_arg_matches_mut(self, matches: ArgMatches) -> void throws Error {
        self.update_from_arg_matches(matches)
    }

    /// BAML-only: dispatch `from_arg_matches` on the runtime type of `self`.
    ///
    /// `clap_derive` only knows a flattened/subcommand field's type at runtime;
    /// calling through a "witness" instance reaches a hand-written override
    /// (`(Self as FromArgMatches)` resolves to the concrete class).
    function from_arg_matches_dyn(self, matches: ArgMatches) -> unknown throws Error {
        (Self as FromArgMatches).from_arg_matches(matches)
    }
}

/// Parse a set of arguments into a user-defined container.
///
/// Implementing this trait lets a parent container delegate argument parsing behavior to `Self`.
/// with:
/// - `#[command(flatten)] args: ChildArgs`: Attribute can only be used with struct fields that impl
///   `Args`.
/// - `Variant(ChildArgs)`: No attribute is used with enum variants that impl `Args`.
///
/// **NOTE:** Deriving requires the `derive` feature flag
interface Args requires FromArgMatches {
    /// Report the [`ArgGroup::id`][crate::ArgGroup::id] for this set of arguments
    function group_id() -> Id? throws never {
        root.clap_derive.args_group_id<Self>()
    }

    /// Append to [`Command`] so it can instantiate `Self` via
    /// [`FromArgMatches::from_arg_matches_mut`]
    ///
    /// This is used to implement `#[command(flatten)]`
    ///
    /// See also [`CommandFactory::command`].
    function augment_args(cmd: Command) -> Command throws never {
        root.clap_derive.augment_args<Self>(cmd)
    }

    /// Append to [`Command`] so it can instantiate `self` via
    /// [`FromArgMatches::update_from_arg_matches_mut`]
    ///
    /// This is used to implement `#[command(flatten)]`
    ///
    /// See also [`CommandFactory::command_for_update`].
    function augment_args_for_update(cmd: Command) -> Command throws never {
        root.clap_derive.augment_args_for_update<Self>(cmd)
    }

    /// BAML-only: dispatch `group_id` on the runtime type of `self` (see `from_arg_matches_dyn`)
    function group_id_dyn(self) -> Id? throws never {
        (Self as Args).group_id()
    }

    /// BAML-only: dispatch `augment_args` on the runtime type of `self` (see `from_arg_matches_dyn`)
    function augment_args_dyn(self, cmd: Command) -> Command throws never {
        (Self as Args).augment_args(cmd)
    }

    /// BAML-only: dispatch `augment_args_for_update` on the runtime type of `self`
    function augment_args_for_update_dyn(self, cmd: Command) -> Command throws never {
        (Self as Args).augment_args_for_update(cmd)
    }
}

/// Parse a sub-command into a user-defined enum.
///
/// Implementing this trait lets a parent container delegate subcommand behavior to `Self`.
/// with:
/// - `#[command(subcommand)] field: SubCmd`: Attribute can be used with either struct fields or enum
///   variants that impl `Subcommand`.
/// - `#[command(flatten)] Variant(SubCmd)`: Attribute can only be used with enum variants that impl
///   `Subcommand`.
///
/// In BAML a derived subcommand "enum" is a union of classes (see `clap_derive`);
/// a union cannot implement an interface, so this trait is only implemented by
/// hand (e.g. a class that dispatches manually, like Rust's `hand_subcommand` example).
interface Subcommand requires FromArgMatches {
    /// Append to [`Command`] so it can instantiate `Self` via
    /// [`FromArgMatches::from_arg_matches_mut`]
    ///
    /// This is used to implement `#[command(flatten)]`
    ///
    /// See also [`CommandFactory::command`].
    function augment_subcommands(cmd: Command) -> Command throws never

    /// Append to [`Command`] so it can instantiate `self` via
    /// [`FromArgMatches::update_from_arg_matches_mut`]
    ///
    /// This is used to implement `#[command(flatten)]`
    ///
    /// See also [`CommandFactory::command_for_update`].
    function augment_subcommands_for_update(cmd: Command) -> Command throws never

    /// Test whether `Self` can parse a specific subcommand
    function has_subcommand(name: string) -> bool throws never

    /// BAML-only: dispatch `augment_subcommands` on the runtime type of `self` (see `FromArgMatches.from_arg_matches_dyn`)
    function augment_subcommands_dyn(self, cmd: Command) -> Command throws never {
        (Self as Subcommand).augment_subcommands(cmd)
    }

    /// BAML-only: dispatch `augment_subcommands_for_update` on the runtime type of `self`
    function augment_subcommands_for_update_dyn(self, cmd: Command) -> Command throws never {
        (Self as Subcommand).augment_subcommands_for_update(cmd)
    }

    /// BAML-only: dispatch `has_subcommand` on the runtime type of `self`
    function has_subcommand_dyn(self, name: string) -> bool throws never {
        (Self as Subcommand).has_subcommand(name)
    }
}

/// Parse arguments into enums.
///
/// When deriving [`Parser`], a field whose type implements `ValueEnum` can have the attribute
/// `#[arg(value_enum)]` which will
/// - Call [`EnumValueParser`][crate::builder::EnumValueParser]
/// - Allowing using the `#[arg(default_value_t)]` attribute without implementing `Display`.
///
/// A BAML `enum` is a `ValueEnum` by reflection (see `clap_derive`); a class may
/// also implement this interface by hand.
///
/// **NOTE:** Deriving requires the `derive` feature flag
interface ValueEnum {
    /// All possible argument values, in display order.
    function value_variants() -> Self[] throws never

    /// Parse an argument into `Self`.
    function from_str(input: string, ignore_case: bool) -> Self throws string {
        let found = (Self as ValueEnum).value_variants().find((v) -> {
            let pv = v.to_possible_value() ?? baml.sys.panic("ValueEnum::value_variants contains only values with a corresponding ValueEnum::to_possible_value");
            pv.matches(input, ignore_case)
        });
        found ?? throw `invalid variant: ${input}`
    }

    /// The canonical argument value.
    ///
    /// The value is `None` for skipped variants.
    function to_possible_value(self) -> PossibleValue? throws never
}

function format_error<I extends CommandFactory>(err: Error) -> Error {
    let cmd = (I as CommandFactory).command();
    err.format(cmd)
}

/// `ValueEnum::value_variants` + `to_possible_value` for a BAML `enum` or a
/// class implementing [`ValueEnum`] (used by `EnumValueParser`)
function enum_variants<E>() -> EnumVariant[] {
    root.clap_derive.value_enum_variants<E>()
}
