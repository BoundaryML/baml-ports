// Port of clap/examples/tutorial_builder/03_02_option_mult.rs

function main() -> void {
    let matches = root.clap.command() // requires `cargo` feature
        .arg(
            root.clap.Arg.new("name")
                .short("n")
                .long("name")
                .action(root.clap_builder.ArgAction.Append),
        )
        .get_matches();

    let args = matches.get_many<string>("name") ?? [];
    baml.io.println(`names: ${root.clap.debug_str_list(args)}`);
}
