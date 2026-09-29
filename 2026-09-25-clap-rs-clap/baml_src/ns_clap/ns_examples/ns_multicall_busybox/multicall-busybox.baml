// Port of clap/examples/multicall-busybox.rs

function applet_commands() -> root.clap.Command[] {
    [
        root.clap.Command.new("true").about("does nothing successfully"),
        root.clap.Command.new("false").about("does nothing unsuccessfully"),
    ]
}

function main() -> void {
    // `env!("CARGO_CRATE_NAME")`
    let cmd = root.clap.Command.new("multicall_busybox")
        .multicall(true)
        .subcommand(
            root.clap.Command.new("busybox")
                .arg_required_else_help(true)
                .subcommand_value_name("APPLET")
                .subcommand_help_heading("APPLETS")
                .arg(
                    root.clap.Arg.new("install")
                        .long("install")
                        .help("Install hardlinks for all subcommands in path")
                        .exclusive(true)
                        .action(root.clap_builder.ArgAction.Set)
                        .default_missing_value("/usr/local/bin")
                        .value_parser(root.clap.value_parser<root.clap.PathBuf>()),
                )
                .subcommands(applet_commands()),
        )
        .subcommands(applet_commands());

    let matches = cmd.get_matches();
    let subcommand = matches.subcommand();
    if (subcommand?.name == "busybox") {
        let m = subcommand?.matches ?? baml.sys.panic("unreachable");
        if (m.contains_id("install")) {
            baml.sys.panic("not implemented: Make hardlinks to the executable here");
        }
        subcommand = m.subcommand();
    }
    match (subcommand?.name) {
        "false" => baml.sys.exit(1),
        "true" => baml.sys.exit(0),
        _ => baml.sys.panic("parser should ensure only valid subcommand names are used"),
    }
}
