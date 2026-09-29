// Port of clap/examples/tutorial_derive/01_quick.rs

/// #[command(version, about, long_about = None)]
class Cli {
    /// Optional name to operate on
    name: string?,

    /// Sets a custom config file
    /// #[arg(short, long, value_name = "FILE")]
    config: root.clap.PathBuf?,

    /// Turn debugging information on
    /// #[arg(short, long, action = clap::ArgAction::Count)]
    debug: int,

    /// #[command(subcommand)]
    command: Commands?,

    implements root.clap_builder.Parser {}
    implements root.clap_builder.CommandFactory {}
    implements root.clap_builder.FromArgMatches {}
    implements root.clap_builder.Args {}
}

/// `#[derive(Subcommand)] enum Commands { Test { list: bool } }`
type Commands = Test

/// does testing things
class Test {
    /// lists test values
    /// #[arg(short, long)]
    list: bool,
}

function main() -> void {
    let cli = Cli.parse();

    // You can check the value provided by positional arguments, or option arguments
    if let name: string = cli.name {
        baml.io.println(`Value for name: ${name}`);
    }

    if let config_path: root.clap.PathBuf = cli.config {
        baml.io.println(`Value for config: ${config_path}`);
    }

    // You can see how many times a particular flag or argument occurred
    // Note, only flags can have multiple occurrences
    match (cli.debug) {
        0 => baml.io.println("Debug mode is off"),
        1 => baml.io.println("Debug mode is kind of on"),
        2 => baml.io.println("Debug mode is on"),
        _ => baml.io.println("Don't be crazy"),
    }

    // You can check for the existence of subcommands, and if found use their
    // matches just as you would the top level cmd
    match (cli.command) {
        let t: Test => {
            if (t.list) {
                baml.io.println("Printing testing lists...");
            } else {
                baml.io.println("Not printing testing lists...");
            }
        },
        null => {},
    }

    // Continued program logic goes here...
}
