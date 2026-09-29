// Port of heck-0.5.0/src/upper_camel.rs

/// This function converts to upper camel case.
///
/// ```baml
/// assert.equal(to_upper_camel_case("We are not in the least afraid of ruins."), "WeAreNotInTheLeastAfraidOfRuins")
/// ```
function to_upper_camel_case(s: string) -> string { transform(s, WordStyle.Capitalize, "") }

/// `ToPascalCase` is an alias for `ToUpperCamelCase`.
function to_pascal_case(s: string) -> string { to_upper_camel_case(s) }
