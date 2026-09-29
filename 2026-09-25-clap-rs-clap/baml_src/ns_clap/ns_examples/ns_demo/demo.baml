// Port of clap/examples/demo.rs

/// Simple program to greet a person
/// #[command(version, about, long_about = None)]
class Args {
    /// Name of the person to greet
    /// #[arg(short, long)]
    name: string,

    /// Number of times to greet
    /// #[arg(short, long, default_value_t = 1)]
    count: int,

    implements root.clap_builder.Parser {}
    implements root.clap_builder.CommandFactory {}
    implements root.clap_builder.FromArgMatches {}
    implements root.clap_builder.Args {}
}

function main() -> void {
    let args = Args.parse();

    for (let i in baml.iter.Range.new(0, args.count)) {
        baml.io.println(`Hello ${args.name}!`);
    }
}
