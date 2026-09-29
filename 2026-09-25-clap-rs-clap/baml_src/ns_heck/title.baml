// Port of heck-0.5.0/src/title.rs

/// This function converts to title case.
///
/// ```baml
/// assert.equal(to_title_case("We have always lived in slums and holes in the wall."), "We Have Always Lived In Slums And Holes In The Wall")
/// ```
function to_title_case(s: string) -> string { transform(s, WordStyle.Capitalize, " ") }
