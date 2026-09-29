// Port of clap/examples/tutorial_derive/04_04_custom.rs

/// #[command(version, about, long_about = None)]
class Cli {
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

    /// some regular input
    input_file: string?,

    /// some special input argument
    /// #[arg(long)]
    spec_in: string?,

    /// #[arg(short)]
    config: string?,

    implements root.clap_builder.Parser {}
    implements root.clap_builder.CommandFactory {}
    implements root.clap_builder.FromArgMatches {}
    implements root.clap_builder.Args {}
}

function main() -> void {
    let cli = Cli.parse();

    // Let's assume the old version 1.2.3
    let major = 1;
    let minor = 2;
    let patch = 3;

    // See if --set-ver was used to set the version manually
    let version = if let ver: string = cli.set_ver {
        if (cli.major || cli.minor || cli.patch) {
            let cmd = Cli.command();
            cmd.error(
                root.clap_builder.ErrorKind.ArgumentConflict,
                "Can't do relative and absolute version change",
            )
            .exit();
        }
        ver
    } else {
        // Increment the one requested (in a real program, we'd reset the lower numbers)
        let maj = cli.major;
        let min = cli.minor;
        let pat = cli.patch;
        if (maj && !min && !pat) {
            major += 1;
        } else if (!maj && min && !pat) {
            minor += 1;
        } else if (!maj && !min && pat) {
            patch += 1;
        } else {
            let cmd = Cli.command();
            cmd.error(
                root.clap_builder.ErrorKind.ArgumentConflict,
                "Can only modify one version field",
            )
            .exit();
        }
        `${major}.${minor}.${patch}`
    };

    baml.io.println(`Version: ${version}`);

    // Check for usage of -c
    if let config: string = cli.config {
        // 'or' is preferred to 'or_else' here since `Option::as_deref` is 'const'
        let input = cli.input_file ?? cli.spec_in ?? Cli.command().error(
            root.clap_builder.ErrorKind.MissingRequiredArgument,
            "INPUT_FILE or --spec-in is required when using --config",
        ).exit();
        baml.io.println(`Doing work using input ${input} and config ${config}`);
    }
}
