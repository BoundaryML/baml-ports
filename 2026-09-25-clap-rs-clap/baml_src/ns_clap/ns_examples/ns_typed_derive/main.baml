// Port of clap/examples/typed-derive/main.rs
//
//   mod builtin;       -> builtin.baml
//   mod custom;        -> custom.baml
//   mod fn_parser;     -> fn_parser.baml
//   mod foreign_crate; -> foreign_crate.baml
//   mod implicit;      -> implicit.baml
//
// Rust derives `Parser` on `enum Cli { Implicit(..), Builtin(..), FnParser(..), Custom(..) }`.
// A BAML union cannot implement an interface, so the parser is a class holding
// the subcommand. `ImplicitParsers` has only optional fields and would accept
// any variant's values when decoding, so each variant carries a `kind` tag.

/// #[command(term_width = 0)] // Just to make testing across clap features easier
/// #[command(bin_name = "typed-derive")] // Make testing easier by avoiding `.exe` in Usage on Windows
class Cli {
    /// #[command(subcommand)]
    command: Commands,

    implements root.clap_builder.Parser {}
    implements root.clap_builder.CommandFactory {}
    implements root.clap_builder.FromArgMatches {}
    implements root.clap_builder.Args {}
}

type Commands = ImplicitParsers | BuiltInParsers | FnParser | CustomParser

function main() -> void {
    let cli = Cli.parse();
    let debug = match (cli.command) {
        let i: ImplicitParsers => `Implicit(${i.debug()})`,
        let b: BuiltInParsers => `Builtin(${b.debug()})`,
        let f: FnParser => `FnParser(${f.debug()})`,
        let c: CustomParser => `Custom(${c.debug()})`,
    };
    baml.io.println(debug);
}

/// Rust's `{:?}` for an `Option<T>` whose `T` renders via `render`
function debug_opt(v: string?) -> string {
    if let s: string = v { `Some(${s})` } else { "None" }
}
