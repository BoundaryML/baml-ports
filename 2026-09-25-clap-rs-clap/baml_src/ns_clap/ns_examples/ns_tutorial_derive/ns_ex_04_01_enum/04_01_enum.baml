// Port of clap/examples/tutorial_derive/04_01_enum.rs

/// #[command(version, about, long_about = None)]
class Cli {
    /// What mode to run the program in
    /// #[arg(value_enum)]
    mode: Mode,

    implements root.clap_builder.Parser {}
    implements root.clap_builder.CommandFactory {}
    implements root.clap_builder.FromArgMatches {}
    implements root.clap_builder.Args {}
}

/// `#[derive(ValueEnum)]`: a BAML `enum` is a `ValueEnum` by reflection
enum Mode {
    /// Run swiftly
    Fast,
    /// Crawl slowly but steadily
    ///
    /// This paragraph is ignored because there is no long help text for possible values.
    Slow,
}

function main() -> void {
    let cli = Cli.parse();

    match (cli.mode) {
        Mode.Fast => {
            baml.io.println("Hare");
        },
        Mode.Slow => {
            baml.io.println("Tortoise");
        },
    }
}
