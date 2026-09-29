// Port of clap/examples/tutorial_builder/03_01_flag_count.rs

function main() -> void {
    let matches = root.clap.command() // requires `cargo` feature
        .arg(
            root.clap.Arg.new("verbose")
                .short("v")
                .long("verbose")
                .action(root.clap_builder.ArgAction.Count),
        )
        .get_matches();

    baml.io.println(`verbose: ${matches.get_count("verbose")}`);
}
