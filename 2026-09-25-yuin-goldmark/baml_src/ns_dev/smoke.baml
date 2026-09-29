// Developer helpers used while porting (not part of goldmark): AST/HTML
// smoke runs, performance probes and the differential-fuzzing dump used with
// tools/difffuzz.
function smoke_dump(src: string) -> string {
    let p = root.parser.new();
    let doc = p.parse(src.to_utf8(), []);
    let buf = root.util.new_buffer();
    doc.dump(src.to_utf8()).pretty_print(buf, src.to_utf8());
    buf.string()
}

function smoke_html(src: string) -> string {
    let m = root.spec_markdown();
    m(src, [])
}

function count_cases(file: string) -> int {
    root.testutil.parse_test_case_file(file).length()
}

function negative_control() -> int {
    let markdown = root.testutil.new_markdown_to_string_func(root.parser.new(), root.renderer.html.new());
    let t = root.testutil.new_recording_t();
    let c = root.testutil.MarkdownTestCase { no: 1, description: "neg", options: root.testutil.empty_options(), markdown: "*a*", expected: "<p>WRONG</p>" };
    root.testutil.do_test_case(markdown, c, t);
    t.errors.length()
}

function perf_probe(kind: string, n: int) -> int {
    let src = match (kind) {
        "label" => "[".repeat(n) + "]".repeat(n),
        "pi" => "a " + "<?".repeat(n),
        "cdata" => "a <![CDATA[".repeat(n),
        "decl" => "a <!A ".repeat(n),
        _ => "a <!-- ".repeat(n),
    };
    let started = baml.time.Instant.now();
    let m = root.spec_markdown();
    m(src, []);
    started.elapsed().to_milliseconds().to_int() catch_all (e) { _ => -1 }
}





function dump_tables() -> string {
    let out: string[] = [];
    let c = 0;
    while (c < 256) {
        out.push(`${if (root.util.is_space(c)) { 1 } else { 0 }},${if (root.util.is_punct(c)) { 1 } else { 0 }},${if (root.util.url_safe_byte(c)) { 1 } else { 0 }},${root.util.utf8_len(c)}`);
        c += 1;
    }
    out.join(";")
}

function micro(kind: string, reps: int, size: int) -> int {
    let b = "a".repeat(size).to_utf8();
    let started = baml.time.Instant.now();
    let i = 0;
    let acc = 0;
    while (i < reps) {
        if (kind == "slice") {
            acc += b.slice(1, size).length();
        } else if (kind == "from_utf8") {
            let s = baml.String.from_utf8(b) catch_all (e) { _ => "" };
            acc += 1;
        } else if (kind == "index_of") {
            acc += b.index_of(98) ?? 0;
        } else if (kind == "str_index") {
            let s = baml.String.from_utf8(b) catch_all (e) { _ => "" };
            acc += s.index_of("]]>") ?? 0;
        } else if (kind == "to_string") {
            acc += b.to_string().byte_length();
        }
        i += 1;
    }
    started.elapsed().to_milliseconds().to_int() catch_all (e) { _ => -1 }
}

function perf_parse_only(n: int, unit: string) -> int {
    let src = unit.repeat(n).to_utf8();
    let started = baml.time.Instant.now();
    root.parser.new().parse(src, []);
    started.elapsed().to_milliseconds().to_int() catch_all (e) { _ => -1 }
}

function perf_render_only(n: int, unit: string) -> string {
    let src = unit.repeat(n).to_utf8();
    let doc = root.parser.new().parse(src, []);
    let started = baml.time.Instant.now();
    let r = root.renderer.html.new(opts = [root.renderer.html.with_xhtml(), root.renderer.html.with_unsafe()]);
    let b = root.util.new_buffer();
    r.render(b, src, doc, []);
    let t = started.elapsed().to_milliseconds().to_int() catch_all (e) { _ => -1 };
    let texts = 0;
    let c = doc.first_child()?.first_child();
    while (c != null) {
        texts += 1;
        c = c.next_sibling();
    }
    t.to_string() + "ms inline-children=" + texts.to_string()
}

function fuzz_campaign(iterations: int, seed: int) -> int {
    root.fuzz.fuzz_mutations(root.fuzz.spec_seeds(), iterations, seed)
}

class FuzzPair {
    input: string,
    output: string,
}

/// Differential fuzzing helper: returns mutated inputs and their rendered HTML.
function fuzz_dump(iterations: int, seed: int) -> FuzzPair[] {
    let seeds = root.fuzz.spec_seeds();
    for (let f in ["testdata/extra.txt", "extension/testdata/table.txt", "extension/testdata/footnote.txt", "extension/testdata/definition_list.txt", "extension/testdata/linkify.txt", "extension/testdata/strikethrough.txt", "extension/testdata/tasklist.txt", "extension/testdata/typographer.txt"]) {
        for (let c in root.testutil.parse_test_case_file(f)) {
            seeds.push(root.testutil.source(c));
        }
    }
    let seed_bytes = root.util.new_bytes();
    let i = 0;
    while (i < 32) {
        seed_bytes.push((seed * 31 + i * 17) % 256);
        i += 1;
    }
    let rng = baml.random.Xoshiro256PlusPlus.new(seed = seed_bytes);
    let alphabet = root.fuzz.fuzz_alphabet().to_utf8();
    let out: FuzzPair[] = [];
    let n = 0;
    while (n < iterations) {
        let pick = rng.random_int();
        if (pick < 0) {
            pick = -pick;
        }
        let input = seeds[pick % seeds.length()].to_utf8();
        let edits = 1 + (pick / 7) % 8;
        let k = 0;
        while (k < edits) {
            let rv = rng.random_int();
            if (rv < 0) {
                rv = -rv;
            }
            let op = rv % 3;
            let at = if (input.length() == 0) { 0 } else { (rv / 3) % (input.length() + 1) };
            let ch = alphabet[(rv / 11) % alphabet.length()];
            if (op == 0 || input.length() == 0) {
                let o = input.slice(0, at);
                o.push(ch);
                root.util.append_bytes(o, input.slice(at, input.length()));
                input = o;
            } else if (op == 1) {
                let pos = at % input.length();
                input = input.slice(0, pos).concat(input.slice(pos + 1, input.length()));
            } else {
                let pos = at % input.length();
                let end = pos + (rv / 13) % 16;
                let e = if (end > input.length()) { input.length() } else { end };
                input = input.slice(0, e).concat(input.slice(pos, input.length()));
            }
            k += 1;
        }
        let s = input.to_string();
        out.push(FuzzPair { input: s, output: fuzz_render(s) });
        n += 1;
    }
    out
}

function fuzz_render(orig: string) -> string {
    let p = root.parser.new(options = [
        root.parser.with_auto_heading_id(),
        root.parser.with_attribute(),
        root.parser.with_extensions([
            root.extension.new_definition_list_parser(),
            root.extension.new_footnote_parser(),
            root.extension.new_gfm_parser(),
            root.extension.new_typographer_parser(),
            root.extension.new_linkify_parser(),
            root.extension.new_table_parser(),
            root.extension.new_task_list_item_parser(),
        ]),
    ]);
    let r = root.renderer.html.new(opts = [
        root.renderer.html.with_unsafe(),
        root.renderer.html.with_xhtml(),
        root.renderer.html.with_extensions([
            root.extension.new_definition_list_html_renderer(),
            root.extension.new_footnote_html_renderer(),
            root.extension.new_gfm_html_renderer(),
            root.extension.new_table_html_renderer(),
            root.extension.new_task_list_item_html_renderer(),
        ]),
    ]);
    let src = orig.to_utf8();
    let b = root.util.new_buffer();
    r.render(b, src, p.parse(src, []), []);
    b.string()
}

function fuzz_dump_json(iterations: int, seed: int) -> string {
    baml.json.to_string(fuzz_dump(iterations, seed)) catch_all (e) { _ => "[]" }
}

function fuzz_dump_file(iterations: int, seed: int, path: string) -> int {
    let pairs = fuzz_dump(iterations, seed);
    let js = baml.json.to_string(pairs) catch_all (e) { _ => "[]" };
    baml.fs.write(path, js) catch_all (e) { _ => 0 };
    pairs.length()
}

function dump_file_pairs(files: string[], path: string) -> int {
    let pairs: FuzzPair[] = [];
    for (let f in files) {
        let s = baml.fs.read(f) catch_all (e) { _ => "" };
        pairs.push(FuzzPair { input: s, output: fuzz_render(s) });
    }
    let js = baml.json.to_string(pairs) catch_all (e) { _ => "[]" };
    baml.fs.write(path, js) catch_all (e) { _ => 0 };
    pairs.length()
}
