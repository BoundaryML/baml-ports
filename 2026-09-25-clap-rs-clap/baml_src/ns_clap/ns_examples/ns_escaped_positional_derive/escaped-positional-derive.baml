// Port of clap/examples/escaped-positional-derive.rs

/// #[command(version, about, long_about = None)]
class Cli {
    /// #[arg(short = 'f')]
    eff: bool,

    /// #[arg(short = 'p', value_name = "PEAR")]
    pea: string?,

    /// #[arg(last = true)]
    slop: string[],

    implements root.clap_builder.Parser {}
    implements root.clap_builder.CommandFactory {}
    implements root.clap_builder.FromArgMatches {}
    implements root.clap_builder.Args {}
}

function main() -> void {
    let args = Cli.parse();

    // This is what will happen with `myprog -f -p=bob -- sloppy slop slop`...
    baml.io.println(`-f used: ${args.eff}`); // -f used: true
    baml.io.println(`-p's value: ${root.clap.debug_opt_str(args.pea)}`); // -p's value: Some("bob")
    baml.io.println(`'slops' values: ${root.clap.debug_str_list(args.slop)}`); // 'slops' values: Some(["sloppy", "slop", "slop"])

    // Continued program logic goes here...
}
