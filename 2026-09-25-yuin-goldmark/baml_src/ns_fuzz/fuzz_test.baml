// Port of goldmark fuzz/fuzz_test.go.
//
// Go's native fuzzing (`testing.F`) has no BAML counterpart. Under plain
// `go test`, a fuzz target only runs its seed corpus; that is what these tests
// do (FuzzDefault seeds from the spec examples). In addition, `fuzz_mutations`
// runs a small deterministic mutation fuzzer (seeded Xoshiro256++) over the
// seeds, standing in for `go test -fuzz`. BAML panics cannot be caught, so a
// crashing input aborts the test (which is also how a Go fuzz failure shows up).

/// Go's `fuzz(f)` body: parse and render `orig` with every extension enabled.
function fuzz_one(orig: string) -> void {
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
}

class SpecSeed {
    markdown: string,
}

function spec_seeds() -> string[] {
    let bs = baml.fs.read("testdata/spec.json") catch_all (e) {
        _ => {
            baml.sys.panic("cannot read testdata/spec.json");
            ""
        }
    };
    let cases = baml.json.from_string<SpecSeed[]>(bs) catch_all (e) {
        _ => {
            baml.sys.panic("cannot decode testdata/spec.json");
            let none: SpecSeed[] = [];
            none
        }
    };
    cases.map((c: SpecSeed) -> string { c.markdown })
}

/// Runs the seed corpus; returns the number of inputs processed.
function fuzz_seeds(seeds: string[]) -> int {
    for (let s in seeds) {
        fuzz_one(s);
    }
    seeds.length()
}

/// Markdown-significant bytes the mutator likes to insert.
function fuzz_alphabet() -> string {
    "*_`[]()<>!#-+=~|:\\\"'&;{}.\n\t 1aZ"
}

/// A deterministic mutation fuzzer standing in for `go test -fuzz`.
function fuzz_mutations(seeds: string[], iterations: int, seed: int) -> int {
    // Xoshiro256++ needs a 32-byte seed.
    let seed_bytes = root.util.new_bytes();
    let i = 0;
    while (i < 32) {
        seed_bytes.push((seed * 31 + i * 17) % 256);
        i += 1;
    }
    let rng = baml.random.Xoshiro256PlusPlus.new(seed = seed_bytes);
    let alphabet = fuzz_alphabet().to_utf8();
    let n = 0;
    let base_seeds = if (seeds.length() == 0) { [""] } else { seeds };
    while (n < iterations) {
        let pick = rng.random_int();
        if (pick < 0) {
            pick = -pick;
        }
        let input = base_seeds[pick % base_seeds.length()].to_utf8();
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
                // insert
                let out = input.slice(0, at);
                out.push(ch);
                root.util.append_bytes(out, input.slice(at, input.length()));
                input = out;
            } else if (op == 1) {
                // delete
                let pos = at % input.length();
                input = input.slice(0, pos).concat(input.slice(pos + 1, input.length()));
            } else {
                // duplicate a chunk
                let pos = at % input.length();
                let end = pos + (rv / 13) % 16;
                let e = if (end > input.length()) { input.length() } else { end };
                input = input.slice(0, e).concat(input.slice(pos, input.length()));
            }
            k += 1;
        }
        fuzz_one(input.to_string());
        n += 1;
    }
    n
}

/// FuzzDefault: seed corpus = every CommonMark spec example.
test "FuzzDefault" {
    let seeds = spec_seeds();
    assert.equal(fuzz_seeds(seeds), seeds.length());
    assert.equal(fuzz_mutations(seeds, 300, 1), 300);
}
