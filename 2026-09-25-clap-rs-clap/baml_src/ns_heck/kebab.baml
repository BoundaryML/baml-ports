// Port of heck-0.5.0/src/kebab.rs

/// This function converts to kebab case.
///
/// ```baml
/// assert.equal(to_kebab_case("We are going to inherit the earth."), "we-are-going-to-inherit-the-earth")
/// ```
function to_kebab_case(s: string) -> string { transform(s, WordStyle.Lower, "-") }
