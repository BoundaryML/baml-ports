// Port of clap/examples/tutorial_derive/03_01_flag_count.rs

/// #[command(version, about, long_about = None)]
class Cli {
    /// #[arg(short, long, action = clap::ArgAction::Count)]
    verbose: int,

    implements root.clap_builder.Parser {}
    implements root.clap_builder.CommandFactory {}
    implements root.clap_builder.FromArgMatches {}
    implements root.clap_builder.Args {}
}

function main() -> void {
    let cli = Cli.parse();

    baml.io.println(`verbose: ${cli.verbose}`);
}
