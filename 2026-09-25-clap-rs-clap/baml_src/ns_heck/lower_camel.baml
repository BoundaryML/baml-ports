// Port of heck-0.5.0/src/lower_camel.rs

/// This function converts to lower camel case.
///
/// ```baml
/// assert.equal(to_lower_camel_case("It is we who built these palaces and cities."), "itIsWeWhoBuiltThesePalacesAndCities")
/// ```
function to_lower_camel_case(s: string) -> string { transform(s, WordStyle.Capitalize, "", first_style = WordStyle.Lower) }
