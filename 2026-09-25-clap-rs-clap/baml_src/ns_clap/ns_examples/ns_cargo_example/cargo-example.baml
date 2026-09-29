// Port of clap/examples/cargo-example.rs

function main() -> void {
    let cmd = root.clap.Command.new("cargo")
        .bin_name("cargo")
        .styles(CLAP_STYLING())
        .subcommand_required(true)
        .subcommand(
            root.clap.command(name = "example").arg(
                root.clap.arg("--\"manifest-path\" <PATH>")
                    .value_parser(root.clap.value_parser<root.clap.PathBuf>()),
            ),
        );
    let matches = cmd.get_matches();
    let sub = matches.subcommand();
    let m = match (sub?.name) {
        "example" => sub?.matches ?? baml.sys.panic("unreachable"),
        _ => baml.sys.panic("clap should ensure we don't get here"),
    };
    let manifest_path = m.get_one<root.clap.PathBuf>("manifest-path");
    baml.io.println(root.clap.debug_opt_str(manifest_path));
}

// See also `clap_cargo::style::CLAP_STYLING`
function CLAP_STYLING() -> root.clap.Styles {
    root.clap.Styles.styled()
        .header(root.clap_cargo.HEADER())
        .usage(root.clap_cargo.USAGE())
        .literal(root.clap_cargo.LITERAL())
        .placeholder(root.clap_cargo.PLACEHOLDER())
        .error(root.clap_cargo.ERROR())
        .valid(root.clap_cargo.VALID())
        .invalid(root.clap_cargo.INVALID())
}
