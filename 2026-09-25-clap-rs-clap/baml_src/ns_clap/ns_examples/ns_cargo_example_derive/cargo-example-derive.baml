// Port of clap/examples/cargo-example-derive.rs

// Rust derives `Parser` on `enum CargoCli { ExampleDerive(ExampleDeriveArgs) }`.
// A BAML union cannot implement an interface, so the parser is a class holding
// the subcommand; the generated `Command` is the same.

/// #[command(name = "cargo")]
/// #[command(bin_name = "cargo")]
/// #[command(styles = CLAP_STYLING)]
class CargoCli {
    /// #[command(subcommand)]
    command: ExampleDeriveArgs,

    implements root.clap_builder.Parser {}
    implements root.clap_builder.CommandFactory {}
    implements root.clap_builder.FromArgMatches {}
    implements root.clap_builder.Args {}
}

// See also `clap_cargo::style::CLAP_STYLING`
function CLAP_STYLING() -> root.clap.Styles {
    root.clap.Styles.styled()
        .header(root.clap_cargo.HEADER())
        .usage(root.clap_cargo.USAGE())
        .literal(root.clap_cargo.LITERAL())
        .placeholder(root.clap_cargo.PLACEHOLDER())
        .error(root.clap_cargo.ERROR())
        .valid(root.clap_cargo.VALID())
        .invalid(root.clap_cargo.INVALID())
}

/// #[command(name = "example-derive")]
/// #[command(version, about, long_about = None)]
class ExampleDeriveArgs {
    /// #[arg(long)]
    manifest_path: root.clap.PathBuf?,

    implements root.clap_builder.FromArgMatches {}
    implements root.clap_builder.Args {}
}

function main() -> void {
    let cli = CargoCli.parse();
    let args = cli.command;
    baml.io.println(root.clap.debug_opt_str(args.manifest_path));
}
