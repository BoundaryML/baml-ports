// Port of clap/examples/derive_ref/augment_subcommands.rs

/// `#[derive(Parser)] enum Subcommands { Derived { derived_flag: bool } }`
type Subcommands = Derived

class Derived {
    /// #[arg(short, long)]
    derived_flag: bool,
}

function main() -> void {
    let cli = root.clap.Command.new("Built CLI");
    // Augment with derived subcommands
    //
    // (A BAML union has no static methods, so `Subcommands::augment_subcommands(cli)`
    // is spelled through `clap_derive`.)
    let cli2 = root.clap_derive.augment_subcommands<Subcommands>(cli);

    let matches = cli2.get_matches();
    let derived_subcommands = root.clap_derive.subcommand_from_matches<Subcommands>(matches) catch (e) {
        let err: root.clap.Error => err.exit(),
    };
    match (derived_subcommands) {
        let d: Derived => baml.io.println(`Derived subcommands: Derived {\n    derived_flag: ${d.derived_flag},\n}`),
    }
}
