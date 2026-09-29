// Port of clap/examples/tutorial_builder/04_01_possible.rs

function main() -> void {
    let matches = root.clap.command() // requires `cargo` feature
        .arg(
            root.clap.arg("<MODE>")
                .help("What mode to run the program in")
                .value_parser(["fast", "slow"]),
        )
        .get_matches();

    // Note, it's safe to call unwrap() because the arg is required
    match (matches.get_one<string>("MODE") ?? baml.sys.panic("'MODE' is required and parsing will fail if its missing")) {
        "fast" => {
            baml.io.println("Hare");
        },
        "slow" => {
            baml.io.println("Tortoise");
        },
        _ => baml.sys.panic("unreachable"),
    }
}
