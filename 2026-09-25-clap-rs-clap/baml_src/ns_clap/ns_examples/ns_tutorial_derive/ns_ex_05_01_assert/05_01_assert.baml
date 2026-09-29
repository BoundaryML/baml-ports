// Port of clap/examples/tutorial_derive/05_01_assert.rs

/// #[command(version, about, long_about = None)]
class Cli {
    /// Network port to use
    /// #[arg(value_parser = clap::value_parser!(u16))]
    port: int,

    implements root.clap_builder.Parser {}
    implements root.clap_builder.CommandFactory {}
    implements root.clap_builder.FromArgMatches {}
    implements root.clap_builder.Args {}
}

function main() -> void {
    let cli = Cli.parse();

    baml.io.println(`PORT = ${cli.port}`);
}

test "verify_cli" {
    Cli.command().debug_assert();
    assert.is_true(true)
}
