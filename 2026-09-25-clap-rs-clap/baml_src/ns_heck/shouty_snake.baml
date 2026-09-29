// Port of heck-0.5.0/src/shouty_snake.rs

/// This function converts to shouty snake case.
///
/// ```baml
/// assert.equal(to_shouty_snake_case("That world is growing in this minute."), "THAT_WORLD_IS_GROWING_IN_THIS_MINUTE")
/// ```
function to_shouty_snake_case(s: string) -> string { transform(s, WordStyle.Upper, "_") }

/// Oh heck, `ToShoutySnekCase` is an alias for `ToShoutySnakeCase`.
function to_shouty_snek_case(s: string) -> string { to_shouty_snake_case(s) }
