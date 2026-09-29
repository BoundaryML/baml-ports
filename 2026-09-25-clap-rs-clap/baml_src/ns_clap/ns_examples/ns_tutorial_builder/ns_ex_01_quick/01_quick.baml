// Port of clap/examples/tutorial_builder/01_quick.rs

function main() -> void {
    let matches = root.clap.command() // requires `cargo` feature
        .arg(root.clap.arg("[name] \"Optional name to operate on\""))
        .arg(
            root.clap.arg("-c --config <FILE> \"Sets a custom config file\"")
            // We don't have syntax yet for optional options, so manually calling `required`
            .required(false)
            .value_parser(root.clap.value_parser<root.clap.PathBuf>()),
        )
        .arg(root.clap.arg("-d --debug ... \"Turn debugging information on\""))
        .subcommand(
            root.clap.Command.new("test")
                .about("does testing things")
                .arg(root.clap.arg("-l --list \"lists test values\"").action(root.clap_builder.ArgAction.SetTrue)),
        )
        .get_matches();

    // You can check the value provided by positional arguments, or option arguments
    if let name: string = matches.get_one<string>("name") {
        baml.io.println(`Value for name: ${name}`);
    }

    if let config_path: root.clap.PathBuf = matches.get_one<root.clap.PathBuf>("config") {
        baml.io.println(`Value for config: ${config_path}`);
    }

    // You can see how many times a particular flag or argument occurred
    // Note, only flags can have multiple occurrences
    match (matches.get_one<int>("debug") ?? baml.sys.panic("Counts are defaulted")) {
        0 => baml.io.println("Debug mode is off"),
        1 => baml.io.println("Debug mode is kind of on"),
        2 => baml.io.println("Debug mode is on"),
        _ => baml.io.println("Don't be crazy"),
    }

    // You can check for the existence of subcommands, and if found use their
    // matches just as you would the top level cmd
    if let sub: root.clap.ArgMatches = matches.subcommand_matches("test") {
        // "$ myapp test" was run
        if (sub.get_flag("list")) {
            // "$ myapp test -l" was run
            baml.io.println("Printing testing lists...");
        } else {
            baml.io.println("Not printing testing lists...");
        }
    }

    // Continued program logic goes here...
}
