// Port of clap/examples/tutorial_builder/05_01_assert.rs

function main() -> void {
    let matches = cmd().get_matches();

    // Note, it's safe to call unwrap() because the arg is required
    let port = matches.get_one<int>("PORT") ?? baml.sys.panic("'PORT' is required and parsing will fail if its missing");
    baml.io.println(`PORT = ${port}`);
}

function cmd() -> root.clap.Command {
    root.clap.command() // requires `cargo` feature
        .arg(
            root.clap.arg("<PORT>")
                .help("Network port to use")
                .value_parser(root.clap.value_parser_usize()),
        )
}

test "verify_cmd" {
    cmd().debug_assert();
    assert.is_true(true)
}
