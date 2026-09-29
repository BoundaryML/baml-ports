// Port of clap/examples/tutorial_builder/02_app_settings.rs

function main() -> void {
    let matches = root.clap.command() // requires `cargo` feature
        .next_line_help(true)
        .arg(root.clap.arg("--two <VALUE>").required(true).action(root.clap_builder.ArgAction.Set))
        .arg(root.clap.arg("--one <VALUE>").required(true).action(root.clap_builder.ArgAction.Set))
        .get_matches();

    baml.io.println(`two: ${root.clap.debug_str(matches.get_one<string>("two") ?? baml.sys.panic("required"))}`);
    baml.io.println(`one: ${root.clap.debug_str(matches.get_one<string>("one") ?? baml.sys.panic("required"))}`);
}
