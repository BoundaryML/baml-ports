// Port of clap/examples/tutorial_derive/03_03_positional_mult.rs

/// #[command(version, about, long_about = None)]
class Cli {
    name: string[],

    implements root.clap_builder.Parser {}
    implements root.clap_builder.CommandFactory {}
    implements root.clap_builder.FromArgMatches {}
    implements root.clap_builder.Args {}
}

function main() -> void {
    let cli = Cli.parse();

    baml.io.println(`name: ${root.clap.debug_str_list(cli.name)}`);
}
