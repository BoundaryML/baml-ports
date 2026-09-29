// Port of clap/examples/tutorial_builder/02_crate.rs

function main() -> void {
    // requires `cargo` feature, reading name, version, author, and description from `Cargo.toml`
    let matches = root.clap.command()
        .arg(root.clap.arg("--two <VALUE>").required(true))
        .arg(root.clap.arg("--one <VALUE>").required(true))
        .get_matches();

    baml.io.println(`two: ${root.clap.debug_str(matches.get_one<string>("two") ?? baml.sys.panic("required"))}`);
    baml.io.println(`one: ${root.clap.debug_str(matches.get_one<string>("one") ?? baml.sys.panic("required"))}`);
}
