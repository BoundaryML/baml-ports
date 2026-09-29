// Port of goldmark testutil/testutil.go.
//
// Package testutil provides utilities for unit tests.
//
// Porting notes:
// - Go's `testing.T` is modelled by `TestingT`; `RecordingT` collects
//   failures so a BAML `test` block can assert that none were recorded.
// - Go's `DoTestCase` uses `recover()` so that a panicking case is reported
//   and the remaining cases still run. BAML panics cannot be caught, so a
//   panic aborts the whole enclosing BAML test. (This is why the spec suite is
//   additionally split into one BAML test per example.)
// - Go's `os.Args` `case=` filtering (`ParseCliCaseArg`) reads the process
//   arguments; this port reads them from `baml.sys.argv()`.
// - Files are read relative to the current working directory (run the tests
//   from the project root).

/// TestingT is a subset of testing.T.
interface TestingT {
    function logf(self, msg: string) -> void throws never
    function skipf(self, msg: string) -> void throws never
    function errorf(self, msg: string) -> void throws never
    function fail_now(self) -> void throws never
}

/// A TestingT that records messages instead of failing immediately.
class RecordingT {
    errors: string[],
    logs: string[],
    skipped: bool,

    implements TestingT {
        function logf(self, msg: string) -> void {
            self.logs.push(msg);
        }

        function skipf(self, msg: string) -> void {
            self.skipped = true;
            self.logs.push(msg);
        }

        function errorf(self, msg: string) -> void {
            self.errors.push(msg);
        }

        function fail_now(self) -> void {
            baml.sys.panic("FailNow: " + self.errors.join("\n"));
        }
    }
}

function new_recording_t() -> RecordingT {
    RecordingT { errors: [], logs: [], skipped: false }
}

class MarkdownToStringFuncConfig {
    parse_options: root.parser.ParseOption[],
    render_options: root.renderer.RenderOption[],
}

/// MarkdownToStringFuncOption is an option for MarkdownToStringFunc.
type MarkdownToStringFuncOption = (c: MarkdownToStringFuncConfig) -> void throws never

/// MarkdownToStringFunc converts a Markdown source into a string.
type MarkdownToStringFunc = (source: string, opts: MarkdownToStringFuncOption[]) -> string throws never

/// NewMarkdownToStringFunc returns a new MarkdownToStringFunc that uses the given parser and renderer.
function new_markdown_to_string_func(p: root.parser.Parser, r: root.renderer.Renderer) -> MarkdownToStringFunc {
    (source: string, opts: MarkdownToStringFuncOption[]) -> string {
        let cfg = MarkdownToStringFuncConfig { parse_options: [], render_options: [] };
        for (let opt in opts) {
            opt(cfg);
        }

        let buf = root.util.new_buffer();
        let b = source.to_utf8();
        let doc = p.parse(b, cfg.parse_options);
        r.render(buf, b, doc, cfg.render_options);
        buf.string()
    }
}

/// MarkdownTestCase represents a test case.
class MarkdownTestCase {
    no: int,
    description: string,
    options: MarkdownTestCaseOptions,
    markdown: string,
    expected: string,
}

/// MarkdownTestCaseOptions represents options for each test case.
/// Go's `encoding/json` matches keys case-insensitively (`"enableEscape"`
/// fills `EnableEscape`); `baml.json` matches raw field names exactly, so the
/// fields are spelled the way the test data spells the keys.
class MarkdownTestCaseOptions {
    enableEscape: bool?,
    trim: bool?,
}

function empty_options() -> MarkdownTestCaseOptions {
    MarkdownTestCaseOptions { enableEscape: false, trim: false }
}

function source(t: MarkdownTestCase) -> string {
    let ret = t.markdown;
    if (t.options.trim ?? false) {
        ret = ret.trim();
    }
    if (t.options.enableEscape ?? false) {
        return apply_escape_sequence(ret.to_utf8()).to_string();
    }
    ret
}

function expected(t: MarkdownTestCase) -> string {
    let ret = t.expected;
    if (t.options.trim ?? false) {
        ret = ret.trim();
    }
    if (t.options.enableEscape ?? false) {
        return apply_escape_sequence(ret.to_utf8()).to_string();
    }
    ret
}

function ATTRIBUTE_SEPARATOR() -> string {
    "//- - - - - - - - -//"
}

function CASE_SEPARATOR() -> string {
    "//= = = = = = = = = = = = = = = = = = = = = = = =//"
}

/// Go's `optionsRegexp`.
function options_regexp() -> baml.regex.Regex {
    baml.regex.new("(?i)\\s*options:(.*)") catch_all (e) {
        _ => {
            baml.sys.panic("bad options regexp");
            baml.regex.new("x") catch_all (e2) { _ => baml.sys.panic("unreachable") }
        }
    }
}

/// ParseCliCaseArg parses `case=` arguments.
function parse_cli_case_arg() -> int[] {
    let ret: int[] = [];
    for (let a in baml.sys.argv()) {
        if (a.starts_with("case=")) {
            let parts = a.split("=");
            for (let cas in parts[1].split(",")) {
                let v = parse_int(cas.trim());
                if (v != null) {
                    ret.push(v);
                }
            }
        }
    }
    ret
}

/// Go: `strconv.Atoi`; null on error.
function parse_int(s: string) -> int? {
    let b = s.to_utf8();
    if (b.length() == 0) {
        return null;
    }
    let neg = false;
    let i = 0;
    if (b[0] == 45 || b[0] == 43) {
        neg = b[0] == 45;
        i = 1;
        if (b.length() == 1) {
            return null;
        }
    }
    let v = 0;
    while (i < b.length()) {
        let c = b[i];
        if (c < 48 || c > 57) {
            return null;
        }
        v = v * 10 + (c - 48);
        i += 1;
    }
    if (neg) {
        return -v;
    }
    v
}

/// Go's line splitting (`bufio.Scanner` with `ScanLines`): splits on '\n',
/// drops one trailing '\r' per line, and ignores a final empty line.
function scan_lines(content: string) -> string[] {
    let lines = content.split("\n");
    if (lines.length() > 0 && lines[lines.length() - 1] == "") {
        lines = lines.slice(0, lines.length() - 1);
    }
    lines.map((l: string) -> string {
        if (l.ends_with("\r")) {
            return l.slice(0, l.length() - 1);
        }
        l
    })
}

/// Parses a goldmark test case file (the parsing half of Go's DoTestCaseFile).
function parse_test_case_file(filename: string, no: int[] = []) -> MarkdownTestCase[] {
    let content = baml.fs.read(filename) catch_all (e) {
        _ => {
            baml.sys.panic("cannot read " + filename);
            ""
        }
    };
    let lines = scan_lines(content);
    let cases: MarkdownTestCase[] = [];
    let idx = 0;
    let n = lines.length();
    let line = 0;
    // Go reuses one MarkdownTestCase value `c` for every case and only
    // assigns `c.Options` when an OPTIONS line is present, so options carry
    // over into later cases (test data relies on this).
    let carried_options = empty_options();
    while (idx < n) {
        let text = lines[idx];
        idx += 1;
        line += 1;
        if (root.util.is_blank(text.to_utf8())) {
            continue;
        }
        let c = MarkdownTestCase { no: -1, description: "", options: carried_options, markdown: "", expected: "" };
        let header = text;
        let cno: int? = null;
        if (header.includes(":")) {
            let parts = header.split(":");
            cno = parse_int(parts[0].trim());
            c.description = parts.slice(1, parts.length()).join(":");
        } else {
            cno = parse_int(text);
        }
        if (cno == null) {
            baml.sys.panic(filename + ": invalid case No at line " + line.to_string());
        }
        c.no = cno ?? -1;
        if (idx >= n) {
            baml.sys.panic(filename + ": invalid case at line " + line.to_string());
        }
        text = lines[idx];
        idx += 1;
        line += 1;
        let m = options_regexp().match_once(text);
        if (m != null) {
            let g = m.groups[1];
            let json = if (g == null) { "" } else { g.text };
            let parsed = baml.json.from_string<MarkdownTestCaseOptions>(json) catch_all (e) {
                _ => {
                    baml.sys.panic(filename + ": invalid options at line " + line.to_string());
                    empty_options()
                }
            };
            // json.Unmarshal only overwrites the keys present in the JSON.
            let merged = MarkdownTestCaseOptions {
                enableEscape: parsed.enableEscape ?? carried_options.enableEscape,
                trim: parsed.trim ?? carried_options.trim,
            };
            c.options = merged;
            carried_options = merged;
            text = if (idx < n) { lines[idx] } else { "" };
            idx += 1;
            line += 1;
        }
        if (text != ATTRIBUTE_SEPARATOR()) {
            baml.sys.panic(filename + ": invalid separator '" + text + "' at line " + line.to_string());
        }
        let buf: string[] = [];
        while (idx < n) {
            let t = lines[idx];
            idx += 1;
            line += 1;
            if (t == ATTRIBUTE_SEPARATOR()) {
                break;
            }
            buf.push(t);
        }
        c.markdown = buf.join("\n");
        buf = [];
        while (idx < n) {
            let t = lines[idx];
            idx += 1;
            line += 1;
            if (t == CASE_SEPARATOR()) {
                break;
            }
            buf.push(t);
        }
        c.expected = buf.join("\n");
        if (c.expected.length() != 0) {
            c.expected = c.expected + "\n";
        }
        let should_add = no.length() == 0;
        if (!should_add) {
            should_add = no.includes(c.no);
        }
        if (should_add) {
            cases.push(c);
        }
    }
    cases
}

/// DoTestCaseFile runs test cases in a given file.
function do_test_case_file(m: MarkdownToStringFunc, filename: string, t: TestingT, no: int[] = []) -> void {
    let cases = parse_test_case_file(filename, no = no);
    do_test_cases(m, cases, t);
}

/// DoTestCases runs a set of test cases.
function do_test_cases(m: MarkdownToStringFunc, cases: MarkdownTestCase[], t: TestingT) -> void {
    for (let test_case in cases) {
        do_test_case(m, test_case, t);
    }
}

/// DoTestCase runs a test case.
function do_test_case(m: MarkdownToStringFunc, test_case: MarkdownTestCase, t: TestingT) -> void {
    let description = "";
    if (test_case.description.length() != 0) {
        description = ": " + test_case.description;
    }
    // Go recovers from panics here; BAML panics cannot be caught.
    let result = m(source(test_case), []);
    let out = result;
    let ok = root.util.bytes_equal(root.util.trim_space(out.to_utf8()), root.util.trim_space(expected(test_case).to_utf8()));
    if (!ok) {
        let msg = "============= case " + test_case.no.to_string() + description + " ================\n"
            + "Markdown:\n-----------\n" + source(test_case) + "\n\n"
            + "Expected:\n----------\n" + expected(test_case) + "\n\n"
            + "Actual\n---------\n" + out + "\n\n"
            + "Diff\n---------\n" + diff_pretty(expected(test_case), out).to_string() + "\n";
        t.errorf(msg);
    }
}

// diffType
function DIFF_REMOVED() -> int {
    0
}

function DIFF_ADDED() -> int {
    1
}

function DIFF_NONE() -> int {
    2
}

class Diff {
    typ: int,
    lines: string[],
}

function simple_diff(v1: string, v2: string) -> Diff[] {
    simple_diff_aux(v1.split("\n"), v2.split("\n"))
}

function simple_diff_aux(v1lines: string[], v2lines: string[]) -> Diff[] {
    let v1index: map<string, int[]> = {};
    let i = 0;
    for (let line in v1lines) {
        let key = line;
        let cur = v1index.get(key) ?? [];
        cur.push(i);
        v1index[key] = cur;
        i += 1;
    }
    let overlap: map<string, int> = {};
    let v1start = 0;
    let v2start = 0;
    let length = 0;
    let v2pos = 0;
    for (let line in v2lines) {
        let new_overlap: map<string, int> = {};
        let key = line;
        for (let v1pos in v1index.get(key) ?? []) {
            let value = 0;
            if (v1pos != 0) {
                let v = overlap.get((v1pos - 1).to_string());
                if (v != null) {
                    value = v;
                }
            }
            new_overlap[v1pos.to_string()] = value + 1;
            if (value + 1 > length) {
                length = value + 1;
                v1start = v1pos - length + 1;
                v2start = v2pos - length + 1;
            }
        }
        overlap = new_overlap;
        v2pos += 1;
    }
    if (length == 0) {
        let diffs: Diff[] = [];
        if (v1lines.length() != 0) {
            diffs.push(Diff { typ: DIFF_REMOVED(), lines: v1lines });
        }
        if (v2lines.length() != 0) {
            diffs.push(Diff { typ: DIFF_ADDED(), lines: v2lines });
        }
        return diffs;
    }
    let diffs = simple_diff_aux(v1lines.slice(0, v1start), v2lines.slice(0, v2start));
    diffs.push(Diff { typ: DIFF_NONE(), lines: v2lines.slice(v2start, v2start + length) });
    diffs.concat(simple_diff_aux(v1lines.slice(v1start + length, v1lines.length()), v2lines.slice(v2start + length, v2lines.length())))
}

/// DiffPretty returns pretty formatted diff between given bytes.
function diff_pretty(v1: string, v2: string) -> uint8array {
    let b = root.util.new_buffer();
    for (let d in simple_diff(v1, v2)) {
        let c = if (d.typ == DIFF_ADDED()) { "+" } else if (d.typ == DIFF_REMOVED()) { "-" } else { " " };
        for (let line in d.lines) {
            if (c != " ") {
                b.write_string(c + " | " + root.util.visualize_spaces(line.to_utf8()).to_string() + "\n");
            } else {
                b.write_string(c + " | " + line + "\n");
            }
        }
    }
    b.bytes()
}

function apply_escape_sequence(b: uint8array) -> uint8array {
    let result = root.util.new_bytes();
    let i = 0;
    while (i < b.length()) {
        if (b[i] == 92 && i != b.length() - 1) {
            let nx = b[i + 1];
            if (nx == 97) {
                result.push(7);
                i += 2;
                continue;
            } else if (nx == 98) {
                result.push(8);
                i += 2;
                continue;
            } else if (nx == 102) {
                result.push(12);
                i += 2;
                continue;
            } else if (nx == 110) {
                result.push(10);
                i += 2;
                continue;
            } else if (nx == 114) {
                result.push(13);
                i += 2;
                continue;
            } else if (nx == 116) {
                result.push(9);
                i += 2;
                continue;
            } else if (nx == 118) {
                result.push(11);
                i += 2;
                continue;
            } else if (nx == 92) {
                result.push(92);
                i += 2;
                continue;
            } else if (nx == 120) {
                if (b.length() >= i + 3 && i + 3 < b.length() && root.util.is_hex_decimal(b[i + 2]) && root.util.is_hex_decimal(b[i + 3])) {
                    result.push(root.text.parse_uint(b.slice(i + 2, i + 4), 16));
                    i += 4;
                    continue;
                }
            } else if (nx == 117 || nx == 85) {
                if (b.length() > i + 2) {
                    let num = root.util.new_bytes();
                    let j = i + 2;
                    while (j < b.length()) {
                        if (root.util.is_hex_decimal(b[j])) {
                            num.push(b[j]);
                            j += 1;
                            continue;
                        }
                        break;
                    }
                    if (num.length() >= 4 && num.length() < 8) {
                        let v = root.text.parse_uint(num.slice(0, 4), 16);
                        root.util.append_bytes(result, root.util.utf8_encode_rune(v));
                        i += 6;
                        continue;
                    }
                    if (num.length() >= 8) {
                        let v = root.text.parse_uint(num.slice(0, 8), 16);
                        root.util.append_bytes(result, root.util.utf8_encode_rune(v));
                        i += 10;
                        continue;
                    }
                }
            }
        }
        result.push(b[i]);
        i += 1;
    }
    result
}
