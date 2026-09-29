// Port of clap/examples/git-derive.rs

/// A fictional versioning CLI
/// #[command(name = "git")]
/// #[command(about = "A fictional versioning CLI", long_about = None)]
class Cli {
    /// #[command(subcommand)]
    command: Commands,

    implements root.clap_builder.Parser {}
    implements root.clap_builder.CommandFactory {}
    implements root.clap_builder.FromArgMatches {}
    implements root.clap_builder.Args {}
}

/// `#[derive(Subcommand)] enum Commands`
///
/// `Clone` and `Push` have the same fields, so each carries a `kind`
/// discriminator (filled in by the derive) to keep them apart when decoding.
type Commands = Clone | Diff | Push | Add | StashArgs | string[]

/// Clones repos
/// #[command(arg_required_else_help = true)]
class Clone {
    kind: "clone",
    /// The remote to clone
    remote: string,
}

/// Compare two commits
class Diff {
    /// #[arg(value_name = "COMMIT")]
    base: root.clap.OsString?,
    /// #[arg(value_name = "COMMIT")]
    head: root.clap.OsString?,
    /// #[arg(last = true)]
    path: root.clap.OsString?,
    /// #[arg(
    ///     long,
    ///     require_equals = true,
    ///     value_name = "WHEN",
    ///     num_args = 0..=1,
    ///     default_value_t = ColorWhen::Auto,
    ///     default_missing_value = "always",
    ///     value_enum
    /// )]
    color: ColorWhen,
}

/// pushes things
/// #[command(arg_required_else_help = true)]
class Push {
    kind: "push",
    /// The remote to target
    remote: string,
}

/// adds things
/// #[command(arg_required_else_help = true)]
class Add {
    /// Stuff to add
    /// #[arg(required = true)]
    path: root.clap.PathBuf[],
}

enum ColorWhen {
    Always,
    Auto,
    Never,
}

/// `impl std::fmt::Display for ColorWhen`
function color_when_to_string(c: ColorWhen) -> string {
    match (c) {
        ColorWhen.Always => "always",
        ColorWhen.Auto => "auto",
        ColorWhen.Never => "never",
    }
}

/// #[command(name = "stash")]
/// #[command(args_conflicts_with_subcommands = true)]
/// #[command(flatten_help = true)]
class StashArgs {
    /// #[command(subcommand)]
    command: StashCommands?,

    /// #[command(flatten)]
    push: StashPushArgs,
}

/// `#[derive(Subcommand)] enum StashCommands`
type StashCommands = StashPushArgs | Pop | Apply

class StashPushArgs {
    kind: "push",
    /// #[arg(short, long)]
    message: string?,
}

class Pop {
    kind: "pop",
    stash: string?,
}

class Apply {
    kind: "apply",
    stash: string?,
}

function main() -> void {
    let args = Cli.parse();

    match (args.command) {
        let c: Clone => {
            baml.io.println(`Cloning ${c.remote}`);
        },
        let d: Diff => {
            let base = d.base;
            let head = d.head;
            let path = d.path;
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
            baml.io.println(`Diffing ${b}..${h} ${p} (color=${color_when_to_string(d.color)})`);
        },
        let p: Push => {
            baml.io.println(`Pushing to ${p.remote}`);
        },
        let a: Add => {
            baml.io.println(`Adding ${root.clap.debug_str_list(a.path)}`);
        },
        let stash: StashArgs => {
            let stash_cmd: StashCommands = stash.command ?? stash.push;
            match (stash_cmd) {
                let push: StashPushArgs => {
                    baml.io.println(`Pushing StashPushArgs { message: ${root.clap.debug_opt_str(push.message)} }`);
                },
                let pop: Pop => {
                    baml.io.println(`Popping ${root.clap.debug_opt_str(pop.stash)}`);
                },
                let apply: Apply => {
                    baml.io.println(`Applying ${root.clap.debug_opt_str(apply.stash)}`);
                },
            }
        },
        let ext: string[] => {
            baml.io.println(`Calling out to ${root.clap.debug_str(ext[0])} with ${root.clap.debug_str_list(ext.slice(1, ext.length()))}`);
        },
    }

    // Continued program logic goes here...
}
