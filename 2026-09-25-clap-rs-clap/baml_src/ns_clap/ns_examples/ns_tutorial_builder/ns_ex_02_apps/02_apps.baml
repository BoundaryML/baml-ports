// Port of clap/examples/tutorial_builder/02_apps.rs

function main() -> void {
    let matches = root.clap.Command.new("MyApp")
        .version("1.0")
        .about("Does awesome things")
        .arg(root.clap.arg("--two <VALUE>").required(true))
        .arg(root.clap.arg("--one <VALUE>").required(true))
        .get_matches();

    baml.io.println(`two: ${root.clap.debug_str(matches.get_one<string>("two") ?? baml.sys.panic("required"))}`);
    baml.io.println(`one: ${root.clap.debug_str(matches.get_one<string>("one") ?? baml.sys.panic("required"))}`);
}
