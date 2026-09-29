// Port of clap_builder/src/error/context.rs

/// Semantics for a piece of error information
enum ContextKind {
    /// The cause of the error
    InvalidSubcommand,
    /// The cause of the error
    InvalidArg,
    /// Existing arguments
    PriorArg,
    /// Accepted subcommands
    ValidSubcommand,
    /// Accepted values
    ValidValue,
    /// Rejected values
    InvalidValue,
    /// Number of values present
    ActualNumValues,
    /// Number of allowed values
    ExpectedNumValues,
    /// Minimum number of allowed values
    MinValues,
    /// Potential fix for the user
    SuggestedCommand,
    /// Potential fix for the user
    SuggestedSubcommand,
    /// Potential fix for the user
    SuggestedArg,
    /// Potential fix for the user
    SuggestedValue,
    /// Trailing argument
    TrailingArg,
    /// Potential fix for the user
    Suggested,
    /// A usage string
    Usage,
    /// An opaque message to the user
    Custom,
}

/// End-user description of the error case, where relevant
function context_kind_as_str(k: ContextKind) -> string? {
    match (k) {
        ContextKind.InvalidSubcommand => "Invalid Subcommand",
        ContextKind.InvalidArg => "Invalid Argument",
        ContextKind.PriorArg => "Prior Argument",
        ContextKind.ValidSubcommand => "Valid Subcommand",
        ContextKind.ValidValue => "Valid Value",
        ContextKind.InvalidValue => "Invalid Value",
        ContextKind.ActualNumValues => "Actual Number of Values",
        ContextKind.ExpectedNumValues => "Expected Number of Values",
        ContextKind.MinValues => "Minimum Number of Values",
        ContextKind.SuggestedCommand => "Suggested Command",
        ContextKind.SuggestedSubcommand => "Suggested Subcommand",
        ContextKind.SuggestedArg => "Suggested Argument",
        ContextKind.SuggestedValue => "Suggested Value",
        ContextKind.TrailingArg => "Trailing Argument",
        ContextKind.Suggested => "Suggested",
        ContextKind.Usage => null,
        ContextKind.Custom => null,
    }
}

/// A piece of error information
type ContextValue = ContextValueNone
    | ContextValueBool
    | ContextValueString
    | ContextValueStrings
    | ContextValueStyledStr
    | ContextValueStyledStrs
    | ContextValueNumber

/// [`ContextKind`] is self-sufficient, no additional information needed
class ContextValueNone {}
/// A single value
class ContextValueBool { value: bool }
/// A single value
class ContextValueString { value: string }
/// Many values
class ContextValueStrings { value: string[] }
/// A single value
class ContextValueStyledStr { value: StyledStr }
/// many value
class ContextValueStyledStrs { value: StyledStr[] }
/// A single value
class ContextValueNumber { value: int }

/// `impl Display for ContextValue`
function context_value_to_string(v: ContextValue) -> string {
    match (v) {
        let n: ContextValueNone => "",
        let b: ContextValueBool => `${b.value}`,
        let s: ContextValueString => s.value,
        let s: ContextValueStrings => s.value.join(", "),
        let s: ContextValueStyledStr => s.value.to_string(),
        let s: ContextValueStyledStrs => s.value.map((x) -> { x.to_string() }).join(", "),
        let n: ContextValueNumber => `${n.value}`,
    }
}
