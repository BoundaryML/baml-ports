// Port of clap/examples/tutorial_builder/03_04_subcommands.rs

function main() -> void {
    let matches = root.clap.command() // requires `cargo` feature
        .propagate_version(true)
        .subcommand_required(true)
        .arg_required_else_help(true)
        .subcommand(
            root.clap.Command.new("add")
                .about("Adds files to myapp")
                .arg(root.clap.arg("[NAME]")),
        )
        .get_matches();

    let sub = matches.subcommand();
    match (sub?.name) {
        "add" => {
            let sub_matches = sub?.matches ?? baml.sys.panic("unreachable");
            baml.io.println(`'myapp add' was used, name is: ${root.clap.debug_opt_str(sub_matches.get_one<string>("NAME"))}`);
        },
        _ => baml.sys.panic("Exhausted list of subcommands and subcommand_required prevents `None`"),
    }
}
