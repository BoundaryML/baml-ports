// Port of clap/examples/tutorial_builder/03_01_flag_bool.rs

function main() -> void {
    let matches = root.clap.command() // requires `cargo` feature
        .arg(
            root.clap.Arg.new("verbose")
                .short("v")
                .long("verbose")
                .action(root.clap_builder.ArgAction.SetTrue),
        )
        .get_matches();

    baml.io.println(`verbose: ${matches.get_flag("verbose")}`);
}
