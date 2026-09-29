// Port of goldmark _benchmark/cmark/goldmark_benchmark.go.
//
// Run: bin/b run --function goldmark_benchmark -- goldmark_benchmark --n 50 --file _benchmark/cmark/_data.md
// (Go's optional 3rd argument writes a pprof CPU profile; BAML has no
// profiler API, so it is not supported.)

function goldmark_benchmark(n: int = 50, file: string = "_benchmark/cmark/_data.md") -> string {
    let source_str = baml.fs.read(file) catch_all (e) {
        _ => {
            baml.sys.panic("cannot read " + file);
            ""
        }
    };
    let source = source_str.to_utf8();
    let p = root.parser.new();
    let r = root.renderer.html.new(opts = [root.renderer.html.with_xhtml(), root.renderer.html.with_unsafe()]);
    let out = root.util.new_buffer();

    let sum_ns = 0;
    let i = 0;
    while (i < n) {
        let start = baml.time.Instant.now();
        out.reset();
        let doc = p.parse(source, []);
        r.render(out, source, doc, []);
        sum_ns += start.elapsed().to_nanoseconds().to_int() catch_all (e) { _ => 0 };
        i += 1;
    }
    // BAML has no int.to_float(); mixed int/float arithmetic converts.
    let avg = (sum_ns / n) / 1000000000.0;
    let report = "------- goldmark -------\n" + "file: " + file + "\n" + "iteration: " + n.to_string() + "\n" + "average: " + avg.to_string() + " sec\n";
    baml.io.print(report);
    report
}
