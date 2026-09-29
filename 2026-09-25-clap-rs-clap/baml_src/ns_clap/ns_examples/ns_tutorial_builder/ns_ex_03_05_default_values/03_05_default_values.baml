// Port of clap/examples/tutorial_builder/03_05_default_values.rs

function main() -> void {
    let matches = root.clap.command() // requires `cargo` feature
        .arg(
            root.clap.arg("[PORT]")
                .value_parser(root.clap.value_parser_u16())
                .default_value("2020"),
        )
        .get_matches();

    baml.io.println(`port: ${matches.get_one<int>("PORT") ?? baml.sys.panic("default ensures there is always a value")}`);
}
