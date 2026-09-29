// Port of goldmark commonmark_test.go.

class CommonmarkSpecTestCase {
    markdown: string,
    html: string,
    example: int,
    start_line: int,
    end_line: int,
    section: string,
}

function load_spec_cases() -> root.testutil.MarkdownTestCase[] {
    let bs = baml.fs.read("testdata/spec.json") catch_all (e) {
        _ => {
            baml.sys.panic("cannot read testdata/spec.json");
            ""
        }
    };
    let test_cases = baml.json.from_string<CommonmarkSpecTestCase[]>(bs) catch_all (e) {
        _ => {
            baml.sys.panic("cannot decode testdata/spec.json");
            let empty: CommonmarkSpecTestCase[] = [];
            empty
        }
    };
    let cases: root.testutil.MarkdownTestCase[] = [];
    let nos = root.testutil.parse_cli_case_arg();
    for (let c in test_cases) {
        let should_add = nos.length() == 0;
        if (!should_add) {
            should_add = nos.includes(c.example);
        }
        if (should_add) {
            cases.push(root.testutil.MarkdownTestCase {
                no: c.example,
                description: "",
                options: root.testutil.empty_options(),
                markdown: c.markdown,
                expected: c.html,
            });
        }
    }
    cases
}

function spec_markdown() -> root.testutil.MarkdownToStringFunc {
    root.testutil.new_markdown_to_string_func(
        root.parser.new(),
        root.renderer.html.new(opts = [root.renderer.html.with_xhtml(), root.renderer.html.with_unsafe()]),
    )
}

/// TestSpec runs every CommonMark spec example (Go: TestSpec).
function test_spec() -> string[] {
    let t = root.testutil.new_recording_t();
    root.testutil.do_test_cases(spec_markdown(), load_spec_cases(), t);
    t.errors
}

test "TestSpec" {
    let errors = test_spec();
    assert.equal(errors.length(), 0);
}

/// Developer helper (not in Go): runs the spec examples in [from, to] and
/// returns a summary of failures.
function spec_report(from: int, to: int) -> string {
    let m = spec_markdown();
    let passed = 0;
    let failed: string[] = [];
    for (let c in load_spec_cases()) {
        if (c.no < from || c.no > to) {
            continue;
        }
        let t = root.testutil.new_recording_t();
        root.testutil.do_test_case(m, c, t);
        if (t.errors.length() == 0) {
            passed += 1;
        } else {
            failed.push(c.no.to_string());
        }
    }
    "passed=" + passed.to_string() + " failed=" + failed.length().to_string() + " [" + failed.join(",") + "]"
}
