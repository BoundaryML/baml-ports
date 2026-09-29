// Port of clap/examples/pacman.rs

function main() -> void {
    let matches = root.clap.Command.new("pacman")
        .about("package manager utility")
        .version("5.2.1")
        .subcommand_required(true)
        .arg_required_else_help(true)
        // Query subcommand
        //
        // Only a few of its arguments are implemented below.
        .subcommand(
            root.clap.Command.new("query")
                .short_flag("Q")
                .long_flag("query")
                .about("Query the package database.")
                .arg(
                    root.clap.Arg.new("search")
                        .short("s")
                        .long("search")
                        .help("search locally installed packages for matching strings")
                        .conflicts_with("info")
                        .action(root.clap_builder.ArgAction.Set)
                        .num_args(root.clap.ValueRange.from(1)),
                )
                .arg(
                    root.clap.Arg.new("info")
                        .long("info")
                        .short("i")
                        .conflicts_with("search")
                        .help("view package information")
                        .action(root.clap_builder.ArgAction.Set)
                        .num_args(root.clap.ValueRange.from(1)),
                ),
        )
        // Sync subcommand
        //
        // Only a few of its arguments are implemented below.
        .subcommand(
            root.clap.Command.new("sync")
                .short_flag("S")
                .long_flag("sync")
                .about("Synchronize packages.")
                .arg(
                    root.clap.Arg.new("search")
                        .short("s")
                        .long("search")
                        .conflicts_with("info")
                        .action(root.clap_builder.ArgAction.Set)
                        .num_args(root.clap.ValueRange.from(1))
                        .help("search remote repositories for matching strings"),
                )
                .arg(
                    root.clap.Arg.new("info")
                        .long("info")
                        .conflicts_with("search")
                        .short("i")
                        .action(root.clap_builder.ArgAction.SetTrue)
                        .help("view package information"),
                )
                .arg(
                    root.clap.Arg.new("package")
                        .help("packages")
                        .required_unless_present("search")
                        .action(root.clap_builder.ArgAction.Set)
                        .num_args(root.clap.ValueRange.from(1)),
                ),
        )
        .get_matches();

    let sub = matches.subcommand();
    match (sub?.name) {
        "sync" => {
            let sync_matches = sub?.matches ?? baml.sys.panic("unreachable");
            if (sync_matches.contains_id("search")) {
                let packages = sync_matches.get_many<string>("search") ?? baml.sys.panic("contains_id");
                let values = packages.join(", ");
                baml.io.println(`Searching for ${values}...`);
                return;
            }

            let packages = sync_matches.get_many<string>("package") ?? baml.sys.panic("is present");
            let values = packages.join(", ");

            if (sync_matches.get_flag("info")) {
                baml.io.println(`Retrieving info for ${values}...`);
            } else {
                baml.io.println(`Installing ${values}...`);
            }
        },
        "query" => {
            let query_matches = sub?.matches ?? baml.sys.panic("unreachable");
            if let packages: string[] = query_matches.get_many<string>("info") {
                let comma_sep = packages.join(", ");
                baml.io.println(`Retrieving info for ${comma_sep}...`);
            } else if let queries: string[] = query_matches.get_many<string>("search") {
                let comma_sep = queries.join(", ");
                baml.io.println(`Searching Locally for ${comma_sep}...`);
            } else {
                baml.io.println("Displaying all locally installed packages...");
            }
        },
        _ => baml.sys.panic("unreachable"), // If all subcommands are defined above, anything else is unreachable
    }
}
