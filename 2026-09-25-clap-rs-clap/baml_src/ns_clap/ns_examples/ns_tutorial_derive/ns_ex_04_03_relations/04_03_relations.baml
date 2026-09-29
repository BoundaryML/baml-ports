// Port of clap/examples/tutorial_derive/04_03_relations.rs

/// #[command(version, about, long_about = None)]
class Cli {
    /// #[command(flatten)]
    vers: Vers,

    /// some regular input
    /// #[arg(group = "input")]
    input_file: string?,

    /// some special input argument
    /// #[arg(long, group = "input")]
    spec_in: string?,

    /// #[arg(short, requires = "input")]
    config: string?,

    implements root.clap_builder.Parser {}
    implements root.clap_builder.CommandFactory {}
    implements root.clap_builder.FromArgMatches {}
    implements root.clap_builder.Args {}
}

/// #[group(required = true, multiple = false)]
class Vers {
    /// set version manually
    /// #[arg(long, value_name = "VER")]
    set_ver: string?,

    /// auto inc major
    /// #[arg(long)]
    major: bool,

    /// auto inc minor
    /// #[arg(long)]
    minor: bool,

    /// auto inc patch
    /// #[arg(long)]
    patch: bool,

    implements root.clap_builder.FromArgMatches {}
    implements root.clap_builder.Args {}
}

function main() -> void {
    let cli = Cli.parse();

    // Let's assume the old version 1.2.3
    let major = 1;
    let minor = 2;
    let patch = 3;

    // See if --set_ver was used to set the version manually
    let vers = cli.vers;
    let version = if let ver: string = vers.set_ver {
        ver
    } else {
        // Increment the one requested (in a real program, we'd reset the lower numbers)
        if (vers.major) {
            major += 1;
        } else if (vers.minor) {
            minor += 1;
        } else if (vers.patch) {
            patch += 1;
        } else {
            baml.sys.panic("unreachable");
        }
        `${major}.${minor}.${patch}`
    };

    baml.io.println(`Version: ${version}`);

    // Check for usage of -c
    if let config: string = cli.config {
        let input = cli.input_file ?? cli.spec_in ?? baml.sys.panic("unwrap");
        baml.io.println(`Doing work using input ${input} and config ${config}`);
    }
}
