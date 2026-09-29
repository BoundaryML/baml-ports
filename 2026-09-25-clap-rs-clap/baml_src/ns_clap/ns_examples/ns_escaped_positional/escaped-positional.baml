// Port of clap/examples/escaped-positional.rs

function main() -> void {
    let matches = root.clap.command() // requires `cargo` feature
        .arg(root.clap.arg("eff: -f").action(root.clap_builder.ArgAction.SetTrue))
        .arg(root.clap.arg("pea: -p <PEAR>").value_parser(root.clap.value_parser<string>()))
        .arg(
            // Indicates that `slop` is only accessible after `--`.
            root.clap.arg("slop: [SLOP]")
                .num_args(root.clap.ValueRange.from(1))
                .last(true)
                .value_parser(root.clap.value_parser<string>()),
        )
        .get_matches();

    // This is what will happen with `myprog -f -p=bob -- sloppy slop slop`...

    // -f used: true
    baml.io.println(`-f used: ${matches.get_flag("eff")}`);
    // -p's value: Some("bob")
    baml.io.println(`-p's value: ${root.clap.debug_opt_str(matches.get_one<string>("pea"))}`);
    // 'slops' values: Some(["sloppy", "slop", "slop"])
    baml.io.println(`'slops' values: ${root.clap.debug_str_list(matches.get_many<string>("slop") ?? [])}`);

    // Continued program logic goes here...
}
