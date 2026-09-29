// Port of goldmark _benchmark/go/benchmark_test.go.
//
// Only the "goldmark/v2" sub-benchmark is portable: the others benchmark
// third-party Go libraries (gomarkdown, lute, golang-commonmark, goldmark v1).
// BAML has no benchmark harness (`testing.B`), so `benchmark_markdown` runs a
// fixed number of iterations and reports ns/op; the test runs one iteration.

type RenderFunc = (src: uint8array) -> uint8array throws never

function benchmark_markdown(iterations: int) -> string {
    let gp = root.parser.new();
    let gr = root.renderer.html.new(opts = [root.renderer.html.with_xhtml(), root.renderer.html.with_unsafe()]);
    let r: RenderFunc = (src: uint8array) -> uint8array {
        let out = root.util.new_buffer();
        gr.render(out, src, gp.parse(src, []), []);
        out.bytes()
    };
    "goldmark/v2: " + do_benchmark(iterations, r)
}

/// The different frameworks have different APIs. Create an adapter that
/// should behave the same in the memory department.
function do_benchmark(n: int, render: RenderFunc) -> string {
    let source_str = baml.fs.read("_benchmark/cmark/_data.md") catch_all (e) {
        _ => {
            baml.sys.panic("cannot read _data.md");
            ""
        }
    };
    let source = source_str.to_utf8();
    let start = baml.time.Instant.now();
    let i = 0;
    while (i < n) {
        let out = render(source);
        if (out.length() < 100) {
            baml.sys.panic("No result");
        }
        i += 1;
    }
    let ns = start.elapsed().to_nanoseconds().to_int() catch_all (e) { _ => 0 };
    (ns / n).to_string() + " ns/op"
}

test "BenchmarkMarkdown" {
    assert.is_true(benchmark_markdown(1).starts_with("goldmark/v2: "));
}
