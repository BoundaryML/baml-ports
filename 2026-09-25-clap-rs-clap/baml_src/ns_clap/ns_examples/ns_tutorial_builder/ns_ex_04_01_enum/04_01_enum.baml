// Port of clap/examples/tutorial_builder/04_01_enum.rs

enum Mode {
    Fast,
    Slow,
}

// Can also be derived with feature flag `derive`
//
// Rust implements `ValueEnum` directly on `enum Mode`; BAML enums cannot
// implement interfaces, so the hand-written impl lives on a wrapper class.
class ModeValue {
    mode: Mode,

    implements root.clap_builder.ValueEnum {
        function value_variants() -> ModeValue[] {
            [ModeValue { mode: Mode.Fast }, ModeValue { mode: Mode.Slow }]
        }

        function to_possible_value(self) -> root.clap.PossibleValue? {
            match (self.mode) {
                Mode.Fast => root.clap.PossibleValue.new("fast").help("Run swiftly"),
                Mode.Slow => root.clap.PossibleValue.new("slow").help("Crawl slowly but steadily"),
            }
        }
    }

    /// `impl std::fmt::Display for Mode`
    implements baml.ToString {
        function to_string(self) -> string {
            (self.to_possible_value() ?? baml.sys.panic("no values are skipped")).get_name()
        }
    }
}

function main() -> void {
    let matches = root.clap.command() // requires `cargo` feature
        .arg(
            root.clap.arg("<MODE>")
                .help("What mode to run the program in")
                .value_parser(root.clap.value_parser_value_enum<ModeValue>()),
        )
        .get_matches();

    // Note, it's safe to call unwrap() because the arg is required
    let mode = matches.get_one<ModeValue>("MODE") ?? baml.sys.panic("'MODE' is required and parsing will fail if its missing");
    match (mode.mode) {
        Mode.Fast => {
            baml.io.println("Hare");
        },
        Mode.Slow => {
            baml.io.println("Tortoise");
        },
    }
}
