// Port verification harness (not part of the Rust crate).
//
// Runs every case in `port/corpus/` through the ported `root.compile` in one
// process and compares with the output the Rust sasso binary produced for the
// same input (`NNNN.expected`, CLI output: CSS plus a trailing newline when
// non-empty). Run from the project root:
//
//     baml run port_harness.run_corpus -- --dir port/corpus --limit 0 --verbose false

class CaseResult {
    name: string,
    ok: bool,
    detail: string,
}

/// Compile one corpus case the way the CLI's `--stdin` path does.
function run_case(dir: string, name: string) -> CaseResult {
    let scss = root.std.read_to_string(`${dir}/${name}.scss`);
    let style_s = root.std.trim(root.std.read_to_string(`${dir}/${name}.style`));
    let expected = root.std.read_to_string(`${dir}/${name}.expected`);
    let code = root.std.trim(root.std.read_to_string(`${dir}/${name}.expected_code`));
    let style: root.OutputStyle = if (style_s == "compressed") {
        root.OutputStyle.Compressed
    } else {
        root.OutputStyle.Expanded
    };
    let options = root.Options.default().with_style(style);
    let got = root.compile(scss, options) catch (e) {
        let err: root.error.Error => {
            if (code != "0") {
                return CaseResult { name: name, ok: true, detail: "error (expected)" };
            }
            return CaseResult {
                name: name,
                ok: false,
                detail: `compile error: ${err.message} (${err.line}:${err.col})`,
            };
        },
        _ => {
            return CaseResult { name: name, ok: false, detail: "unexpected throw" };
        },
    };
    if (code != "0") {
        return CaseResult { name: name, ok: false, detail: "expected a compile error, got CSS" };
    }
    let actual = if (got == "") {
        ""
    } else {
        got + "\n"
    };
    if (actual == expected) {
        CaseResult { name: name, ok: true, detail: "" }
    } else {
        CaseResult {
            name: name,
            ok: false,
            detail: `mismatch\n--- expected\n${expected}--- actual\n${actual}`,
        }
    }
}

/// Run every case (or the first `limit` when > 0); print failures; return
/// "passed/total".
function run_corpus(dir: string, limit: int, verbose: bool) -> string {
    let names: string[] = [];
    for (let f in root.std.read_dir_names(dir)) {
        if (f.ends_with(".scss")) {
            names.push(f.slice(0, f.length() - 5));
        }
    }
    root.std.sort_strings(names);
    if (limit > 0 && names.length() > limit) {
        names = names.slice(0, limit);
    }
    let passed = 0;
    for (let name in names) {
        let r = run_case(dir, name) catch_all (e) {
            _ => CaseResult { name: name, ok: false, detail: `panic: ${e}` }
        };
        if (r.ok) {
            passed += 1;
        } else {
            baml.io.println(
                `FAIL ${name}: ${if (verbose) { r.detail } else { r.detail.split("\n")[0] }}`,
            );
        }
    }
    `${passed}/${names.length()}`
}
