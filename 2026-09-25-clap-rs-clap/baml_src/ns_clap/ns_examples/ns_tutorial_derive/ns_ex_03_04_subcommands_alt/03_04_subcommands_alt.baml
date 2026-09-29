// Port of clap/examples/tutorial_derive/03_04_subcommands_alt.rs

/// #[command(version, about, long_about = None)]
/// #[command(propagate_version = true)]
class Cli {
    /// #[command(subcommand)]
    command: Commands,

    implements root.clap_builder.Parser {}
    implements root.clap_builder.CommandFactory {}
    implements root.clap_builder.FromArgMatches {}
    implements root.clap_builder.Args {}
}

/// `#[derive(Subcommand)] enum Commands { Add(AddArgs) }`
type Commands = AddArgs

/// Adds files to myapp
/// #[command(name = "add")]
class AddArgs {
    name: string?,

    implements root.clap_builder.FromArgMatches {}
    implements root.clap_builder.Args {}
}

function main() -> void {
    let cli = Cli.parse();

    // You can check for the existence of subcommands, and if found use their
    // matches just as you would the top level cmd
    match (cli.command) {
        let name: AddArgs => {
            baml.io.println(`'myapp add' was used, name is: ${root.clap.debug_opt_str(name.name)}`);
        },
    }
}
