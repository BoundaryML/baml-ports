// Port of clap/examples/git.rs

function cli() -> root.clap.Command {
    root.clap.Command.new("git")
        .about("A fictional versioning CLI")
        .subcommand_required(true)
        .arg_required_else_help(true)
        .allow_external_subcommands(true)
        .subcommand(
            root.clap.Command.new("clone")
                .about("Clones repos")
                .arg(root.clap.arg("<REMOTE> \"The remote to clone\""))
                .arg_required_else_help(true),
        )
        .subcommand(
            root.clap.Command.new("diff")
                .about("Compare two commits")
                .arg(root.clap.arg("base: [COMMIT]"))
                .arg(root.clap.arg("head: [COMMIT]"))
                .arg(root.clap.arg("path: [PATH]").last(true))
                .arg(
                    root.clap.arg("--color <WHEN>")
                        .value_parser(["always", "auto", "never"])
                        .num_args(root.clap.ValueRange.inclusive(0, 1))
                        .require_equals(true)
                        .default_value("auto")
                        .default_missing_value("always"),
                ),
        )
        .subcommand(
            root.clap.Command.new("push")
                .about("pushes things")
                .arg(root.clap.arg("<REMOTE> \"The remote to target\""))
                .arg_required_else_help(true),
        )
        .subcommand(
            root.clap.Command.new("add")
                .about("adds things")
                .arg_required_else_help(true)
                .arg(root.clap.arg("<PATH> ... \"Stuff to add\"").value_parser(root.clap.value_parser<root.clap.PathBuf>())),
        )
        .subcommand(
            root.clap.Command.new("stash")
                .args_conflicts_with_subcommands(true)
                .flatten_help(true)
                .args(push_args())
                .subcommand(root.clap.Command.new("push").args(push_args()))
                .subcommand(root.clap.Command.new("pop").arg(root.clap.arg("[STASH]")))
                .subcommand(root.clap.Command.new("apply").arg(root.clap.arg("[STASH]"))),
        )
}

function push_args() -> root.clap.Arg[] {
    [root.clap.arg("-m --message <MESSAGE>")]
}

function main() -> void {
    let matches = cli().get_matches();

    let sub = matches.subcommand();
    match (sub?.name) {
        "clone" => {
            let sub_matches = sub?.matches ?? baml.sys.panic("unreachable");
            baml.io.println(`Cloning ${sub_matches.get_one<string>("REMOTE") ?? baml.sys.panic("required")}`);
        },
        "diff" => {
            let sub_matches = sub?.matches ?? baml.sys.panic("unreachable");
            let color = sub_matches.get_one<string>("color") ?? baml.sys.panic("defaulted in clap");

            let base = sub_matches.get_one<string>("base");
            let head = sub_matches.get_one<string>("head");
            let path = sub_matches.get_one<string>("path");
            if (path == null) {
                path = head;
                head = null;
                if (path == null) {
                    path = base;
                    base = null;
                }
            }
            let b = base ?? "stage";
            let h = head ?? "worktree";
            let p = path ?? "";
            baml.io.println(`Diffing ${b}..${h} ${p} (color=${color})`);
        },
        "push" => {
            let sub_matches = sub?.matches ?? baml.sys.panic("unreachable");
            baml.io.println(`Pushing to ${sub_matches.get_one<string>("REMOTE") ?? baml.sys.panic("required")}`);
        },
        "add" => {
            let sub_matches = sub?.matches ?? baml.sys.panic("unreachable");
            let paths = sub_matches.get_many<root.clap.PathBuf>("PATH") ?? [];
            baml.io.println(`Adding ${root.clap.debug_str_list(paths)}`);
        },
        "stash" => {
            let sub_matches = sub?.matches ?? baml.sys.panic("unreachable");
            let stash_command = sub_matches.subcommand() ?? root.clap.SubcommandMatch { name: "push", matches: sub_matches };
            match (stash_command.name) {
                "apply" => {
                    let stash = stash_command.matches.get_one<string>("STASH");
                    baml.io.println(`Applying ${root.clap.debug_opt_str(stash)}`);
                },
                "pop" => {
                    let stash = stash_command.matches.get_one<string>("STASH");
                    baml.io.println(`Popping ${root.clap.debug_opt_str(stash)}`);
                },
                "push" => {
                    let message = stash_command.matches.get_one<string>("message");
                    baml.io.println(`Pushing ${root.clap.debug_opt_str(message)}`);
                },
                let name => baml.sys.panic(`Unsupported subcommand \`${name}\``),
            }
        },
        let ext: string => {
            let sub_matches = sub?.matches ?? baml.sys.panic("unreachable");
            let args = sub_matches.get_many<root.clap.OsString>("") ?? [];
            baml.io.println(`Calling out to ${root.clap.debug_str(ext)} with ${root.clap.debug_str_list(args)}`);
        },
        null => baml.sys.panic("unreachable"), // If all subcommands are defined above, anything else is unreachable!()
    }

    // Continued program logic goes here...
}
