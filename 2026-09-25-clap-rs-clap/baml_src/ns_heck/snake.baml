// Port of heck-0.5.0/src/snake.rs

/// This function converts to snake case.
///
/// ```baml
/// assert.equal(to_snake_case("We carry a new world here, in our hearts."), "we_carry_a_new_world_here_in_our_hearts")
/// ```
function to_snake_case(s: string) -> string { transform(s, WordStyle.Lower, "_") }

/// Oh heck, `SnekCase` is an alias for `SnakeCase`.
function to_snek_case(s: string) -> string { to_snake_case(s) }
