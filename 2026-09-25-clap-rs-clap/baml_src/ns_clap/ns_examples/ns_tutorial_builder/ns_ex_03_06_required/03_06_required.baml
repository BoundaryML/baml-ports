// Port of clap/examples/tutorial_builder/03_06_required.rs

function main() -> void {
    let matches = root.clap.command() // requires `cargo` feature
        .arg(root.clap.Arg.new("name").required(true))
        .get_matches();

    baml.io.println(`name: ${root.clap.debug_str(matches.get_one<string>("name") ?? baml.sys.panic("clap `required` ensures its present"))}`);
}
