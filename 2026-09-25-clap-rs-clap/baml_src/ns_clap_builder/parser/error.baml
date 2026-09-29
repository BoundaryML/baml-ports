// Port of clap_builder/src/parser/error.rs

/// Violation of [`ArgMatches`][crate::ArgMatches] assumptions
type MatchesError = MatchesErrorDowncast | MatchesErrorUnknownArgument

/// Failed to downcast `AnyValue` to the specified type
class MatchesErrorDowncast {
    /// Type for value stored in [`ArgMatches`][crate::ArgMatches]
    actual: AnyValueId,
    /// The target type to downcast to
    expected: AnyValueId,
}

/// Argument not defined in [`Command`][crate::Command]
class MatchesErrorUnknownArgument {}

/// `MatchesError::unwrap`: panic with the error
function matches_error_panic(id: string, err: MatchesError) -> never {
    baml.sys.panic(`Mismatch between definition and access of \`${id}\`. ${matches_error_to_string(err)}`)
}

/// `impl Display for MatchesError`
function matches_error_to_string(err: MatchesError) -> string {
    match (err) {
        let d: MatchesErrorDowncast => `Could not downcast to ${d.expected.debug()}, need to downcast to ${d.actual.debug()}\n`,
        let u: MatchesErrorUnknownArgument => "Unknown argument or group id.  Make sure you are using the argument id and not the short or long flags\n",
    }
}
