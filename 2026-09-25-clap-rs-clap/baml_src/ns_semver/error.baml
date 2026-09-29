// Port of semver-1.x/src/error.rs

/// Error parsing a SemVer version or version requirement.
class Error {
    message: string,

    implements baml.ToString {
        function to_string(self) -> string throws never { self.message }
    }
}

enum Position {
    Major,
    Minor,
    Patch,
    Pre,
    Build,
}

/// `impl Display for Position`
function position_to_string(p: Position) -> string {
    match (p) {
        Position.Major => "major version number",
        Position.Minor => "minor version number",
        Position.Patch => "patch version number",
        Position.Pre => "pre-release identifier",
        Position.Build => "build metadata",
    }
}

function error_empty() -> Error { Error { message: "empty string, expected a semver version" } }

function error_unexpected_end(pos: Position) -> Error {
    Error { message: `unexpected end of input while parsing ${position_to_string(pos)}` }
}

function error_unexpected_char(pos: Position, ch: string) -> Error {
    Error { message: `unexpected character ${debug_char(ch)} while parsing ${position_to_string(pos)}` }
}

function error_unexpected_char_after(pos: Position, ch: string) -> Error {
    Error { message: `unexpected character ${debug_char(ch)} after ${position_to_string(pos)}` }
}

function error_leading_zero(pos: Position) -> Error {
    Error { message: `invalid leading zero in ${position_to_string(pos)}` }
}

function error_overflow(pos: Position) -> Error {
    Error { message: `value of ${position_to_string(pos)} exceeds u64::MAX` }
}

function error_empty_segment(pos: Position) -> Error {
    Error { message: `empty identifier segment in ${position_to_string(pos)}` }
}

/// Rust's `{:?}` for a `char`
function debug_char(ch: string) -> string {
    if (ch == "'") { "'\\''" } else { `'${ch}'` }
}
