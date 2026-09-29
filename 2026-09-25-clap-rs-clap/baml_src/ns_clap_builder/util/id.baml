// Port of clap_builder/src/util/id.rs
//
// `Id` is Rust's `struct Id(Str)`: an interned, cheap-to-clone argument name.
// BAML strings are already immutable values, so `Id` is an alias of `string`.

/// [`Arg`] or [`ArgGroup`] identifier
///
/// This is used for accessing the value in [`ArgMatches`] or defining
/// relationships between [`Arg`]s and [`ArgGroup`]s with functions like
/// [`Arg::conflicts_with`].
type Id = string

/// `Id::HELP`
function ID_HELP() -> Id { "help" }

/// `Id::VERSION`
function ID_VERSION() -> Id { "version" }

/// `Id::EXTERNAL`
function ID_EXTERNAL() -> Id { "" }
