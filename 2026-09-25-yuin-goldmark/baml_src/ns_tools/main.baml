// Port of goldmark _tools/main.go.
//
// Development tools. Run with
//   bin/b run --function tools_main -- tools_main --json-args '{"args": ["emb-structs", "-i", "in.json", "-o", "out.go"]}'
// (Go reads `os.Args`; BAML functions take their arguments explicitly.)

function tools_main(args: string[]) -> int {
    let cmd = "-h";
    let rest: string[] = [];
    if (args.length() > 0) {
        cmd = args[0];
    }
    if (args.length() > 1) {
        rest = args.slice(1, args.length());
    }
    match (cmd) {
        "oss-fuzz-corpus" => oss_fuzz_corpus_sub_command(rest),
        "unicode-case-folding-map" => unicode_case_folding_map_sub_command(rest),
        "emb-structs" => emb_structs_sub_command(rest),
        _ => {
            baml.io.eprint("Usage: _tools <subcommand> [options]\nsubcommands:\n  oss-fuzz-corpus\n  unicode-case-folding-map\n  emb-structs\n");
            1
        }
    }
}

/// Go's `usage(u, err)`: print usage (and the error), then exit(1).
function usage(u: string, err: string?) -> int {
    baml.io.eprint(u);
    if (err != null) {
        baml.io.eprint(err);
    }
    1
}

/// A minimal port of Go's `flag.FlagSet` for string flags: accepts `-name value`,
/// `-name=value` and `--name` forms. Returns null (Go: a parse error) on an
/// unknown flag or a missing value.
function parse_string_flags(args: string[], defaults: map<string, string>) -> map<string, string>? {
    let out: map<string, string> = {};
    for (let k in defaults.keys()) {
        out[k] = defaults[k];
    }
    let i = 0;
    while (i < args.length()) {
        let a = args[i];
        if (!a.starts_with("-") || a == "-" || a == "--") {
            break;
        }
        let name = if (a.starts_with("--")) { a.slice(2, a.length()) } else { a.slice(1, a.length()) };
        let value: string? = null;
        let eq = name.index_of("=");
        if (eq != null) {
            value = name.slice(eq + 1, name.length());
            name = name.slice(0, eq);
        }
        if (!defaults.has(name)) {
            return null;
        }
        if (value == null) {
            if (i + 1 >= args.length()) {
                return null;
            }
            i += 1;
            value = args[i];
        }
        out[name] = value ?? "";
        i += 1;
    }
    out
}
