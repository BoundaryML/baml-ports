// Port of clap_builder-4.6.0/src/lib.rs
//
// > **Command Line Argument Parser for Rust**
//
// This is the BAML port of `clap_builder`, the builder API that `clap`
// re-exports. Every Rust crate is a BAML namespace, and every Rust module is a
// file at the same relative path:
//
//   src/lib.rs                     -> lib.baml
//   src/macros.rs                  -> macros.baml
//   src/derive.rs                  -> derive.baml
//   src/mkeymap.rs                 -> mkeymap.baml
//   src/builder/*.rs               -> builder/*.baml
//   src/error/*.rs                 -> error/*.baml
//   src/output/*.rs                -> output/*.baml
//   src/output/textwrap/*.rs       -> output/textwrap/*.baml
//   src/parser/*.rs                -> parser/*.baml
//   src/parser/features/*.rs       -> parser/features/*.baml
//   src/parser/matches/*.rs        -> parser/matches/*.baml
//   src/util/*.rs                  -> util/*.baml
//
// All modules share the `root.clap_builder` namespace (BAML folders without an
// `ns_` prefix do not open a namespace), much like Rust's `pub use` re-exports
// flatten the public API into the crate root.
//
// Rust-to-BAML conventions used throughout:
// - Private struct fields are prefixed with `_` (BAML fields and methods share
//   one namespace, and clap has both a `short` field and a `short()` builder).
// - `Option<T>` is `T?`; `Resettable<T>` (value or reset) is also `T?`.
// - `Result<T, Error>` is `T throws Error`.
// - `Str`, `OsStr`, `Id` are `string` aliases.
// - Rust enums with data are unions of classes; `impl` blocks on fieldless
//   enums become free functions (BAML enums cannot have methods).
// - `const`s are zero-argument functions (BAML has no top-level `let`).

/// `pub type Error = error::Error<error::DefaultFormatter>;`
///
/// See `error/mod.baml` for the `Error` class itself.

/// `const INTERNAL_ERROR_MSG`
function INTERNAL_ERROR_MSG() -> string {
    "Fatal internal error. Please consider filing a bug report at https://github.com/clap-rs/clap/issues"
}

/// Cargo features of `clap_builder`.
///
/// Rust selects these at compile time with `#[cfg(feature = "...")]`. BAML
/// has no conditional compilation, so they are runtime flags. The defaults
/// match `clap`'s default feature set (`std`, `color`, `help`, `usage`,
/// `error-context`, `suggestions`).
class Features {
    color: bool,
    help: bool,
    usage: bool,
    error_context: bool,
    suggestions: bool,
    env: bool,
    wrap_help: bool,
    unicode: bool,
    string: bool,
    cargo: bool,
    debug: bool,
    unstable_v5: bool,
}

/// The enabled feature set.
///
/// Optional features can be switched on through the `CLAP_FEATURES`
/// environment variable, a comma-separated list such as `env,wrap_help`
/// (and default ones switched off with a `-` prefix, e.g. `-color`).
function features() -> Features {
    let f = Features {
        color: true,
        help: true,
        usage: true,
        error_context: true,
        suggestions: true,
        env: true,
        wrap_help: false,
        unicode: false,
        string: true,
        cargo: true,
        debug: false,
        unstable_v5: false,
    };
    let raw = (baml.env.get("CLAP_FEATURES") catch_all (e) { _ => null }) ?? "";
    for (let part in raw.split(",")) {
        let name = part.trim();
        let on = !name.starts_with("-");
        let key = if (on) { name } else { name.slice(1, name.length()) };
        match (key.replace_all("-", "_")) {
            "color" => { f.color = on; },
            "help" => { f.help = on; },
            "usage" => { f.usage = on; },
            "error_context" => { f.error_context = on; },
            "suggestions" => { f.suggestions = on; },
            "env" => { f.env = on; },
            "wrap_help" => { f.wrap_help = on; },
            "unicode" => { f.unicode = on; },
            "string" => { f.string = on; },
            "cargo" => { f.cargo = on; },
            "debug" => { f.debug = on; },
            "unstable_v5" => { f.unstable_v5 = on; },
            _ => {},
        }
    }
    f
}
