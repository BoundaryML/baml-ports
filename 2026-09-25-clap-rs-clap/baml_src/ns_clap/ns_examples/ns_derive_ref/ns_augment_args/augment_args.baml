// Port of clap/examples/derive_ref/augment_args.rs

class DerivedArgs {
    /// #[arg(short, long)]
    derived: bool,

    implements root.clap_builder.FromArgMatches {}
    implements root.clap_builder.Args {}
}

function main() -> void {
    let cli = root.clap.Command.new("CLI").arg(root.clap.arg("-b --built").action(root.clap_builder.ArgAction.SetTrue));
    // Augment built args with derived args
    let cli2 = DerivedArgs.augment_args(cli);

    let matches = cli2.get_matches();
    baml.io.println(`Value of built: ${matches.get_flag("built")}`);
    baml.io.println(`Value of derived via ArgMatches: ${matches.get_flag("derived")}`);

    // Since DerivedArgs implements FromArgMatches, we can extract it from the unstructured ArgMatches.
    // This is the main benefit of using derived arguments.
    let derived_matches = DerivedArgs.from_arg_matches(matches) catch (e) {
        let err: root.clap.Error => err.exit(),
    };
    baml.io.println(`Value of derived: DerivedArgs {\n    derived: ${derived_matches.derived},\n}`);
}
