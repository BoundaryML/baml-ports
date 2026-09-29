// Port of anstyle-query-1.1.5/src/lib.rs
//
// Low level terminal capability lookups. A dependency of `anstream`.

function env_var(name: string) -> string? {
    baml.env.get(name) catch_all (e) { _ => null }
}

/// Check [CLICOLOR] status
///
/// - When `true`, ANSI colors are supported and should be used when the program isn't piped,
///   similar to [`term_supports_color`]
/// - When `false`, don’t output ANSI color escape codes, similar to [`no_color`]
function clicolor() -> bool? {
    let value = env_var("CLICOLOR");
    if let v: string = value { v != "0" } else { null }
}

/// Check [CLICOLOR_FORCE] status
///
/// ANSI colors should be enabled no matter what.
function clicolor_force() -> bool {
    non_empty(env_var("CLICOLOR_FORCE"))
}

/// Check [NO_COLOR] status
///
/// When `true`, should prevent the addition of ANSI color.
function no_color() -> bool {
    non_empty(env_var("NO_COLOR"))
}

/// Check `TERM` for color support
function term_supports_color() -> bool {
    match (env_var("TERM")) {
        null => false,
        "dumb" => false,
        _ => true,
    }
}

/// Check `TERM` for ANSI color support
function term_supports_ansi_color() -> bool {
    term_supports_color()
}

/// Check [COLORTERM] for truecolor support
function truecolor() -> bool {
    let value = env_var("COLORTERM") ?? "";
    value == "truecolor" || value == "24bit"
}

/// Report whether this is running in CI
///
/// CI is a common environment where, despite being piped, ansi color codes are supported
function is_ci() -> bool {
    env_var("CI") != null
}

function non_empty(v: string?) -> bool {
    !((v ?? "").is_empty())
}

testset "anstyle_query" {
    test "non_empty_not_present" { assert.is_true(!non_empty(null)) }
    test "non_empty_empty" { assert.is_true(!non_empty("")) }
    test "non_empty_texty" { assert.is_true(non_empty("hello")) }
}
