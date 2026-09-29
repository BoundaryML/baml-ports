// Port of clap/examples/derive_ref/hand_subcommand.rs

class AddArgs {
    kind: "add",
    name: string[],

    implements root.clap_builder.Parser {}
    implements root.clap_builder.CommandFactory {}
    implements root.clap_builder.FromArgMatches {}
    implements root.clap_builder.Args {}
}

class RemoveArgs {
    kind: "remove",
    /// #[arg(short, long)]
    force: bool,
    name: string[],

    implements root.clap_builder.Parser {}
    implements root.clap_builder.CommandFactory {}
    implements root.clap_builder.FromArgMatches {}
    implements root.clap_builder.Args {}
}

/// Rust: `enum CliSub { Add(AddArgs), Remove(RemoveArgs) }` with hand-written
/// `FromArgMatches` and `Subcommand` impls. A BAML union cannot implement
/// interfaces, so the enum is a class wrapping the variant.
class CliSub {
    variant: AddArgs | RemoveArgs,

    implements root.clap_builder.FromArgMatches {
        function from_arg_matches(matches: root.clap.ArgMatches) -> CliSub throws root.clap.Error {
            let sub = matches.subcommand();
            match (sub?.name) {
                "add" => CliSub { variant: AddArgs.from_arg_matches(sub?.matches ?? baml.sys.panic("unreachable")) },
                "remove" => CliSub { variant: RemoveArgs.from_arg_matches(sub?.matches ?? baml.sys.panic("unreachable")) },
                let n: string => throw root.clap.Error.raw(
                    root.clap_builder.ErrorKind.InvalidSubcommand,
                    "Valid subcommands are `add` and `remove`",
                ),
                null => throw root.clap.Error.raw(
                    root.clap_builder.ErrorKind.MissingSubcommand,
                    "Valid subcommands are `add` and `remove`",
                ),
            }
        }

        function update_from_arg_matches(self, matches: root.clap.ArgMatches) -> void throws root.clap.Error {
            let sub = matches.subcommand();
            match (sub?.name) {
                "add" => { self.variant = AddArgs.from_arg_matches(sub?.matches ?? baml.sys.panic("unreachable")); },
                "remove" => { self.variant = RemoveArgs.from_arg_matches(sub?.matches ?? baml.sys.panic("unreachable")); },
                let n: string => {
                    throw root.clap.Error.raw(
                        root.clap_builder.ErrorKind.InvalidSubcommand,
                        "Valid subcommands are `add` and `remove`",
                    );
                },
                null => {},
            }
        }
    }

    implements root.clap_builder.Subcommand {
        function augment_subcommands(cmd: root.clap.Command) -> root.clap.Command {
            cmd.subcommand(AddArgs.augment_args(root.clap.Command.new("add")))
                .subcommand(RemoveArgs.augment_args(root.clap.Command.new("remove")))
                .subcommand_required(true)
        }

        function augment_subcommands_for_update(cmd: root.clap.Command) -> root.clap.Command {
            cmd.subcommand(AddArgs.augment_args(root.clap.Command.new("add")))
                .subcommand(RemoveArgs.augment_args(root.clap.Command.new("remove")))
                .subcommand_required(true)
        }

        function has_subcommand(name: string) -> bool {
            name == "add" || name == "remove"
        }
    }
}

class Cli {
    /// #[arg(short, long)]
    top_level: bool,

    /// #[command(subcommand)]
    subcommand: CliSub,

    implements root.clap_builder.Parser {}
    implements root.clap_builder.CommandFactory {}
    implements root.clap_builder.FromArgMatches {}
    implements root.clap_builder.Args {}
}

function debug_names(names: string[]) -> string {
    if (names.length() == 0) {
        return "[]";
    }
    `[\n${names.map((n) -> { `                ${root.clap.debug_str(n)},\n` }).join("")}            ]`
}

function main() -> void {
    let args = Cli.parse();
    let sub = match (args.subcommand.variant) {
        let a: AddArgs => `Add(\n        AddArgs {\n            name: ${debug_names(a.name)},\n        },\n    )`,
        let r: RemoveArgs => `Remove(\n        RemoveArgs {\n            force: ${r.force},\n            name: ${debug_names(r.name)},\n        },\n    )`,
    };
    baml.io.println(`Cli {\n    top_level: ${args.top_level},\n    subcommand: ${sub},\n}`);
}
