// Port of clap/examples/tutorial_derive/04_02_validate.rs

/// #[command(version, about, long_about = None)]
class Cli {
    /// Network port to use
    /// #[arg(value_parser = port_in_range)]
    port: int,

    implements root.clap_builder.Parser {}
    implements root.clap_builder.CommandFactory {}
    implements root.clap_builder.FromArgMatches {}
    implements root.clap_builder.Args {}
}

function main() -> void {
    let cli = Cli.parse();

    baml.io.println(`PORT = ${cli.port}`);
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
