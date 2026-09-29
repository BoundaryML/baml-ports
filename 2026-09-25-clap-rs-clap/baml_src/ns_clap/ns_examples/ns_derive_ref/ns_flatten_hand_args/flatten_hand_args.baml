// Port of clap/examples/derive_ref/flatten_hand_args.rs

class CliArgs {
    foo: bool,
    bar: bool,
    quuz: string?,

    implements root.clap_builder.FromArgMatches {
        function from_arg_matches(matches: root.clap.ArgMatches) -> CliArgs throws root.clap.Error {
            let m = matches.clone();
            CliArgs.from_arg_matches_mut(m)
        }

        function from_arg_matches_mut(matches: root.clap.ArgMatches) -> CliArgs throws root.clap.Error {
            CliArgs {
                foo: matches.get_flag("foo"),
                bar: matches.get_flag("bar"),
                quuz: matches.remove_one<string>("quuz"),
            }
        }

        function update_from_arg_matches(self, matches: root.clap.ArgMatches) -> void throws root.clap.Error {
            let m = matches.clone();
            self.update_from_arg_matches_mut(m)
        }

        function update_from_arg_matches_mut(self, matches: root.clap.ArgMatches) -> void throws root.clap.Error {
            self.foo = self.foo || matches.get_flag("foo");
            self.bar = self.bar || matches.get_flag("bar");
            if let quuz: string = matches.remove_one<string>("quuz") {
                self.quuz = quuz;
            }
        }
    }

    implements root.clap_builder.Args {
        function augment_args(cmd: root.clap.Command) -> root.clap.Command {
            cmd.arg(
                root.clap.Arg.new("foo")
                    .short("f")
                    .long("foo")
                    .action(root.clap_builder.ArgAction.SetTrue),
            )
            .arg(
                root.clap.Arg.new("bar")
                    .short("b")
                    .long("bar")
                    .action(root.clap_builder.ArgAction.SetTrue),
            )
            .arg(
                root.clap.Arg.new("quuz")
                    .short("q")
                    .long("quuz")
                    .action(root.clap_builder.ArgAction.Set),
            )
        }

        function augment_args_for_update(cmd: root.clap.Command) -> root.clap.Command {
            cmd.arg(
                root.clap.Arg.new("foo")
                    .short("f")
                    .long("foo")
                    .action(root.clap_builder.ArgAction.SetTrue),
            )
            .arg(
                root.clap.Arg.new("bar")
                    .short("b")
                    .long("bar")
                    .action(root.clap_builder.ArgAction.SetTrue),
            )
            .arg(
                root.clap.Arg.new("quuz")
                    .short("q")
                    .long("quuz")
                    .action(root.clap_builder.ArgAction.Set),
            )
        }
    }
}

class Cli {
    /// #[arg(short, long)]
    top_level: bool,

    /// #[command(flatten)]
    more_args: CliArgs,

    implements root.clap_builder.Parser {}
    implements root.clap_builder.CommandFactory {}
    implements root.clap_builder.FromArgMatches {}
    implements root.clap_builder.Args {}
}

function main() -> void {
    let args = Cli.parse();
    let quuz = if let q: string = args.more_args.quuz { `Some(\n            ${root.clap.debug_str(q)},\n        )` } else { "None" };
    baml.io.println(`Cli {\n    top_level: ${args.top_level},\n    more_args: CliArgs {\n        foo: ${args.more_args.foo},\n        bar: ${args.more_args.bar},\n        quuz: ${quuz},\n    },\n}`);
}
