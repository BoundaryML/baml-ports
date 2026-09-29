// Port of clap/examples/tutorial_derive/03_05_default_values.rs

/// #[command(version, about, long_about = None)]
class Cli {
    /// #[arg(default_value_t = 2020)]
    port: int,

    implements root.clap_builder.Parser {}
    implements root.clap_builder.CommandFactory {}
    implements root.clap_builder.FromArgMatches {}
    implements root.clap_builder.Args {}
}

function main() -> void {
    let cli = Cli.parse();

    baml.io.println(`port: ${cli.port}`);
}
