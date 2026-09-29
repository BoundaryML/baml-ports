// Port of clap/examples/tutorial_builder/04_02_validate.rs

function main() -> void {
    let matches = root.clap.command() // requires `cargo` feature
        .arg(
            root.clap.arg("<PORT>")
                .help("Network port to use")
                .value_parser(root.clap.FnValueParser.new<int>((s) -> { port_in_range(s) })),
        )
        .get_matches();

    // Note, it's safe to call unwrap() because the arg is required
    let port = matches.get_one<int>("PORT") ?? baml.sys.panic("'PORT' is required and parsing will fail if its missing");
    baml.io.println(`PORT = ${port}`);
}

/// `const PORT_RANGE: RangeInclusive<usize> = 1..=65535;`
function PORT_RANGE_START() -> int { 1 }
function PORT_RANGE_END() -> int { 65535 }

function port_in_range(s: string) -> int throws string {
    let port = baml.Int.parse(s) catch_all (e) { _ => throw `\`${s}\` isn't a port number` };
    if (port < 0) {
        throw `\`${s}\` isn't a port number`;
    }
    if (PORT_RANGE_START() <= port && port <= PORT_RANGE_END()) {
        port
    } else {
        throw `port not in range ${PORT_RANGE_START()}-${PORT_RANGE_END()}`
    }
}
