// Port of goldmark doc_test.go.
//
// TestDoc parses README.md (with the BAML parser port), extracts every
// runnable Go code block, and runs it with `go run` against the Go goldmark
// module. Porting notes:
// - Go reads `README.md` from the goldmark repository root and uses that
//   directory (`os.Getwd()`) as the `replace` target for the goldmark module.
//   This port reads `testdata/README.md` (a copy) and uses the Go source tree
//   given by $GOLDMARK_GO_SRC (default: `../goldmark-baml-port-src`), since the
//   snippets are Go programs using the Go API.
// - `os.MkdirTemp` -> `mktemp -d`; `runtime.Version()` -> `go env GOVERSION`;
//   `exec.CommandContext` with a 15s timeout -> `baml.sys.exec` with
//   `timeout_ms`.
// - Go panics on setup errors; this port reports them as test errors.

function this_package() -> string {
    "github.com/yuin/goldmark/v2"
}

function run_cmd(dir: string, program: string, args: string[], timeout_ms: int?) -> baml.sys.ShellOutput? {
    baml.sys.exec(program, args, baml.sys.ProcessOptions {
        cwd: dir,
        env: null,
        timeout_ms: timeout_ms,
        stdin: null,
        stderr: baml.sys.StderrMode.Pipe,
    }) catch_all (e) { _ => null }
}

/// BAML: `r == null || !r.ok()` does not narrow `r` in the right operand.
function succeeded(r: baml.sys.ShellOutput?) -> bool {
    if (r == null) {
        return false;
    }
    r.ok()
}

function cmd_stdout(dir: string, program: string, args: string[]) -> string {
    let out = run_cmd(dir, program, args, null);
    if (out == null) {
        return "";
    }
    out.stdout.to_string().trim()
}

function test_doc() -> string[] {
    let errors: string[] = [];
    let go_src_env = baml.env.get("GOLDMARK_GO_SRC") catch_all (e) { _ => null };
    let go_src_rel = go_src_env ?? "../goldmark-baml-port-src";
    let cwd = cmd_stdout(go_src_rel, "pwd", []);
    if (cwd == "") {
        return ["cannot resolve the Go source directory " + go_src_rel];
    }
    let p = root.parser.new();
    let source_str = baml.fs.read("testdata/README.md") catch_all (e) { _ => "" };
    if (source_str == "") {
        return ["cannot read testdata/README.md"];
    }
    let source = source_str.to_utf8();
    let doc = p.parse(source, []);
    let code_blocks: root.ast.CodeBlock[] = [];
    root.ast.walk(doc, (n: root.ast.Node, entering: bool) -> root.ast.WalkStatus {
        match (n) {
            let cb: root.ast.CodeBlock => {
                if (entering) {
                    code_blocks.push(cb);
                }
            }
            _ => {}
        }
        root.ast.WalkStatus.WalkContinue
    });
    let pat = baml.regex.new("(?s)import\\s*\\((.*?)\\)") catch_all (e) {
        _ => {
            return ["bad import regexp"];
        }
    };
    let go_version = cmd_stdout(cwd, "go", ["env", "GOVERSION"]);
    let go_version_num = if (go_version.starts_with("go")) { go_version.slice(2, go_version.length()) } else { go_version };
    let ran = 0;
    for (let cb in code_blocks) {
        let l = cb.language(source);
        if (l == null) {
            continue;
        }
        if (l != "go") {
            continue;
        }
        if (cb.info.str(source).includes("no-run")) {
            continue;
        }
        let code = cb.value.str(source);

        let import_match = pat.match_once(code);
        let import_section: string? = null;
        if (import_match != null) {
            let g = import_match.groups[1];
            if (g != null) {
                import_section = g.text;
            }
        }
        let body = code.replace_all(pat, "");

        let third_party_imports: string[] = [];
        if (import_section != null) {
            for (let line0 in import_section.split("\n")) {
                let line = line0.trim();
                if (line != "" && line.includes(".") && !line.includes(this_package())) {
                    third_party_imports.push(line.slice(1, line.length() - 1)); // remove quotes
                }
            }
        }

        let d = cmd_stdout(".", "mktemp", ["-d", "-t", "goldmark_test"]);
        if (d == "") {
            return ["cannot create a temporary directory"];
        }
        let major_version = this_package().slice(this_package().length() - 1, this_package().length());
        let gomod = "module test\n\ngo " + go_version_num + "\nrequire(\n" + this_package() + " v" + major_version + ".0.0\n)\n"
            + "replace " + this_package() + " v" + major_version + ".0.0 => " + cwd + "\n";
        baml.fs.write(d + "/go.mod", gomod) catch_all (e) { _ => 0 };

        let main_go = "package main\n";
        if (import_section != null) {
            main_go = main_go + "import (\n" + import_section + "\n)\n";
        }
        main_go = main_go + "func main() {\n" + body + "}\n";
        baml.fs.write(d + "/main.go", main_go) catch_all (e) { _ => 0 };

        for (let imp in third_party_imports) {
            let r = run_cmd(d, "go", ["get", imp + "@latest"], 15000);
            if (!succeeded(r)) {
                errors.push("go get " + imp + " failed");
            }
        }
        let tidy = run_cmd(d, "go", ["mod", "tidy"], 15000);
        if (!succeeded(tidy)) {
            errors.push("go mod tidy failed in " + d);
        }

        let out = run_cmd(d, "go", ["run", "main.go"], null);
        ran += 1;
        let ok = if (out == null) { false } else { out.ok() };
        if (!ok) {
            let output = if (out == null) { "" } else { out.stdout.to_string() + out.stderr.to_string() };
            errors.push("Code block failed to run: \n  Line: " + pos_to_line(source, cb.value.segments()[0].start).to_string()
                + "\n  Code:\n" + add_indent(main_go, 4) + "  Output:\n" + add_indent(output, 4));
        }
        run_cmd(".", "rm", ["-rf", d], null);
    }
    if (ran == 0) {
        errors.push("no runnable Go code blocks found in README.md");
    }
    errors
}

test "TestDoc" {
    assert.equal(test_doc(), []);
}

function pos_to_line(source: uint8array, pos: int) -> int {
    let line = 1;
    let i = 0;
    while (i < pos && i < source.length()) {
        if (source[i] == 10) {
            line += 1;
        }
        i += 1;
    }
    line
}

function add_indent(s: string, w: int) -> string {
    let indent = " ".repeat(w);
    let lines = s.split("\n").map((l: string) -> string { indent + l });
    lines.join("\n").trim_end() + "\n"
}
