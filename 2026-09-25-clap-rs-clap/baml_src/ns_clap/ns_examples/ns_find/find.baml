// Port of clap/examples/find.rs

function main() -> void {
    let matches = cli().get_matches();
    let values = from_matches(matches, cli().get_groups().map((g) -> { g.get_id() }));
    baml.io.println(debug_values(values));
}

function cli() -> root.clap.Command {
    root.clap.command()
        .group(root.clap.ArgGroup.new("tests").multiple(true))
        .next_help_heading("TESTS")
        .args([
            position_sensitive_flag(root.clap.Arg.new("empty"))
                .long("empty")
                .action(root.clap_builder.ArgAction.Append)
                .help("File is empty and is either a regular file or a directory")
                .group("tests"),
            root.clap.Arg.new("name")
                .long("name")
                .action(root.clap_builder.ArgAction.Append)
                .help("Base of file name (the path with the leading directories removed) matches shell pattern pattern")
                .group("tests"),
        ])
        .group(root.clap.ArgGroup.new("operators").multiple(true))
        .next_help_heading("OPERATORS")
        .args([
            position_sensitive_flag(root.clap.Arg.new("or"))
                .short("o")
                .long("or")
                .action(root.clap_builder.ArgAction.Append)
                .help("expr2 is not evaluate if exp1 is true")
                .group("operators"),
            position_sensitive_flag(root.clap.Arg.new("and"))
                .short("a")
                .long("and")
                .action(root.clap_builder.ArgAction.Append)
                .help("Same as `expr1 expr1`")
                .group("operators"),
        ])
}

function position_sensitive_flag(arg: root.clap.Arg) -> root.clap.Arg {
    // Flags don't track the position of each occurrence, so we need to emulate flags with
    // value-less options to get the same result
    arg.num_args(0)
        .value_parser(root.clap.value_parser<bool>())
        .default_missing_value("true")
        .default_value("false")
}

/// `pub enum Value { Bool(bool), String(String) }`
type Value = bool | string

/// `(clap::Id, Value)`
class IdValue {
    id: root.clap.Id,
    value: Value,
    index: int,
}

function from_matches(matches: root.clap.ArgMatches, group_ids: root.clap.Id[]) -> IdValue[] {
    let values: IdValue[] = [];
    for (let id in matches.ids()) {
        // Rust detects groups with `matches.try_get_many::<clap::Id>(id).is_ok()`, relying on
        // `Id` being a distinct type from `String`. In BAML `Id` is an alias of `string`, so
        // the group ids are taken from the `Command` instead.
        let is_group = group_ids.includes(id);
        if (is_group) {
            // ignore groups
            continue;
        }

        let value_source = matches.value_source(id) ?? baml.sys.panic("id came from matches");
        if (value_source != root.clap_builder.ValueSource.CommandLine) {
            // Any other source just gets tacked on at the end (like default values)
            continue;
        }

        if (extract<string>(matches, id, values)) {
            continue;
        }

        if (extract<bool>(matches, id, values)) {
            continue;
        }

        baml.sys.panic(`unknown type for ${id}`);
    }

    // `BTreeMap<usize, (Id, Value)>::into_values()`: ordered by index
    values.sort_by_key((v) -> { v.index })
}

function extract<T>(matches: root.clap.ArgMatches, id: root.clap.Id, output: IdValue[]) -> bool {
    let found = matches.try_get_many<T>(id) catch (e) {
        let d: root.clap_builder.MatchesErrorDowncast => { return false; },
        let u: root.clap_builder.MatchesErrorUnknownArgument => baml.sys.panic("id came from matches"),
    };
    if let values: T[] = found {
        let indices = matches.indices_of(id) ?? baml.sys.panic("id came from matches");
        for (let i in baml.iter.Range.new(0, values.length())) {
            let v = values[i];
            let value: Value = match (v) {
                let s: string => s,
                let b: bool => b,
                _ => baml.sys.panic("unsupported"),
            };
            output.push(IdValue { id: id, value: value, index: indices[i] });
        }
        true
    } else {
        baml.sys.panic("`ids` only reports what is present")
    }
}

/// `println!("{values:#?}")`
function debug_values(values: IdValue[]) -> string {
    let lines: string[] = ["["];
    for (let v in values) {
        lines.push("    (");
        lines.push(`        ${root.clap.debug_str(v.id)},`);
        match (v.value) {
            let b: bool => {
                lines.push("        Bool(");
                lines.push(`            ${b},`);
            },
            let s: string => {
                lines.push("        String(");
                lines.push(`            ${root.clap.debug_str(s)},`);
            },
        }
        lines.push("        ),");
        lines.push("    ),");
    }
    lines.push("]");
    if (values.length() == 0) {
        return "[]";
    }
    lines.join("\n")
}
