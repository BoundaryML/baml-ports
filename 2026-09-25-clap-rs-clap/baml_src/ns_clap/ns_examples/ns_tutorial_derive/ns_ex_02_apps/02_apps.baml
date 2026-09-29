// Port of clap/examples/tutorial_derive/02_apps.rs

/// #[command(name = "MyApp")]
/// #[command(version = "1.0")]
/// #[command(about = "Does awesome things", long_about = None)]
class Cli {
    /// #[arg(long)]
    two: string,
    /// #[arg(long)]
    one: string,

    implements root.clap_builder.Parser {}
    implements root.clap_builder.CommandFactory {}
    implements root.clap_builder.FromArgMatches {}
    implements root.clap_builder.Args {}
}

function main() -> void {
    let cli = Cli.parse();

    baml.io.println(`two: ${root.clap.debug_str(cli.two)}`);
    baml.io.println(`one: ${root.clap.debug_str(cli.one)}`);
}
