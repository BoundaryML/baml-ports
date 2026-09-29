// Port of clap/examples/tutorial_builder/04_04_custom.rs

function main() -> void {
    // Create application like normal
    let cmd = root.clap.command() // requires `cargo` feature
        // Add the version arguments
        .arg(root.clap.arg("--\"set-ver\" <VER> \"set version manually\""))
        .arg(root.clap.arg("--major         \"auto inc major\"").action(root.clap_builder.ArgAction.SetTrue))
        .arg(root.clap.arg("--minor         \"auto inc minor\"").action(root.clap_builder.ArgAction.SetTrue))
        .arg(root.clap.arg("--patch         \"auto inc patch\"").action(root.clap_builder.ArgAction.SetTrue))
        // Arguments can also be added to a group individually, these two arguments
        // are part of the "input" group which is not required
        .arg(root.clap.arg("[INPUT_FILE] \"some regular input\"").value_parser(root.clap.value_parser<root.clap.PathBuf>()))
        .arg(
            root.clap.arg("--\"spec-in\" <SPEC_IN> \"some special input argument\"")
                .value_parser(root.clap.value_parser<root.clap.PathBuf>()),
        )
        // Now let's assume we have a -c [config] argument which requires one of
        // (but **not** both) the "input" arguments
        .arg(root.clap.arg("config: -c <CONFIG>").value_parser(root.clap.value_parser<root.clap.PathBuf>()));
    let matches = cmd.get_matches_mut();

    // Let's assume the old version 1.2.3
    let major = 1;
    let minor = 2;
    let patch = 3;

    // See if --set-ver was used to set the version manually
    let version = if let ver: string = matches.get_one<string>("set-ver") {
        if (matches.get_flag("major") || matches.get_flag("minor") || matches.get_flag("patch")) {
            cmd.error(
                root.clap_builder.ErrorKind.ArgumentConflict,
                "Can't do relative and absolute version change",
            )
            .exit();
        }
        ver
    } else {
        // Increment the one requested (in a real program, we'd reset the lower numbers)
        let maj = matches.get_flag("major");
        let min = matches.get_flag("minor");
        let pat = matches.get_flag("patch");
        if (maj && !min && !pat) {
            major += 1;
        } else if (!maj && min && !pat) {
            minor += 1;
        } else if (!maj && !min && pat) {
            patch += 1;
        } else {
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
    if (matches.contains_id("config")) {
        let input = matches.get_one<root.clap.PathBuf>("INPUT_FILE")
            ?? matches.get_one<root.clap.PathBuf>("spec-in")
            ?? cmd.error(
                root.clap_builder.ErrorKind.MissingRequiredArgument,
                "INPUT_FILE or --spec-in is required when using --config",
            )
            .exit();
        baml.io.println(`Doing work using input ${input} and config ${matches.get_one<root.clap.PathBuf>("config") ?? baml.sys.panic("unwrap")}`);
    }
}
