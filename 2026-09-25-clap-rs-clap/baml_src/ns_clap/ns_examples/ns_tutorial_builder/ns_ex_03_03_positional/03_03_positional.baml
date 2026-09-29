// Port of clap/examples/tutorial_builder/03_03_positional.rs

function main() -> void {
    let matches = root.clap.command() // requires `cargo` feature
        .arg(root.clap.Arg.new("name"))
        .get_matches();

    baml.io.println(`name: ${root.clap.debug_opt_str(matches.get_one<string>("name"))}`);
}
