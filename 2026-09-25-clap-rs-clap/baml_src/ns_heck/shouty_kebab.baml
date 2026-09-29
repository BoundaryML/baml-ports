// Port of heck-0.5.0/src/shouty_kebab.rs

/// This function converts to shouty kebab case.
///
/// ```baml
/// assert.equal(to_shouty_kebab_case("I am a shouty kebab."), "I-AM-A-SHOUTY-KEBAB")
/// ```
function to_shouty_kebab_case(s: string) -> string { transform(s, WordStyle.Upper, "-") }
