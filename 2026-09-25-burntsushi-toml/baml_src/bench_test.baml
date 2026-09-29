// Port of bench_test.go (plus BenchmarkEscapes/BenchmarkKey from
// decode_test.go).
//
// BAML has no benchmark harness (no testing.B, no b.N calibration). Each
// benchmark is a function `bench_*(n)` running the Go loop body n times; the
// tests below run it with a small fixed n and report ns/op on stdout, so the
// benchmarks at least execute (and can be timed by hand with larger n via
// `baml run`).

function now_ns() -> bigint {
    baml.time.Instant.now().to_timestamp_nanoseconds()
}

function report(name: string, n: int, start: bigint) -> null {
    let el = now_ns() - start;
    baml.io.println(`Benchmark${name}\t${n}\t${el / (0n + n)} ns/op`);
    null
}

// Groups of valid/ test documents keyed by directory ("top" for the root),
// in sorted group order: the `files` map built by fs.WalkDir in Go.
class BenchGroup {
    group: string,
    toml: string[],
}

function bench_groups() -> BenchGroup[] {
    let fsys = tomltest.test_cases();
    let files: map<string, string[]> = {};
    for (let path in fsys.walk("valid")) {
        if (!path.ends_with(".toml")) {
            continue;
        }
        let rel = path.slice(6, path.length());
        let slash = rel.last_index_of("/");
        let g = if (slash == null) { "top" } else { rel.slice(0, slash) };
        let d = fsys.read_string(path);
        let list = files.get(g) ?? [];
        list.push(d);
        files.set(g, list);
    }
    let tests: BenchGroup[] = [];
    for (let k in files.keys()) {
        tests.push(BenchGroup { group: k, toml: files[k] });
    }
    tests.sort_by((a: BenchGroup, b: BenchGroup) -> baml.ops.Ordering { a.group.cmp(b.group) })
}

function bench_decode_group(g: BenchGroup, n: int) -> null {
    let start = now_ns();
    let i = 0;
    while (i < n) {
        for (let f in g.toml) {
            let _ = decode<map<string, Any>>(f) catch (e) {
                _ => null
            };
        }
        i += 1;
    }
    report(`Decode/${g.group}`, n, start)
}

function bench_decode_large_doc(n: int) -> null {
    let f = baml.fs.open("testdata/Cargo.toml", "r");
    let doc = go.string_of(f.bytes().to_array());
    let _ = f.close();

    let start = now_ns();
    let i = 0;
    while (i < n) {
        let _ = decode<map<string, Any>>(doc);
        i += 1;
    }
    report("Decode/large-doc", n, start)
}

testset "BenchmarkDecode" {
    for (let tt in bench_groups()) {
        test tt.group {
            bench_decode_group(tt, 1)
        }
    }
    test "large-doc" {
        bench_decode_large_doc(1)
    }
}

// "next" version of TOML.
function bench_encode_skip(path: string) -> bool {
    path == "valid/string/escape-esc.toml" || path == "valid/datetime/no-seconds.toml"
        || path == "valid/string/hex-escape.toml" || path == "valid/inline-table/newline.toml"
}

class EncodeBenchGroup {
    group: string,
    data: map<string, Any>[],
}

function bench_encode_groups() -> EncodeBenchGroup[] {
    let fsys = tomltest.test_cases();
    let files: map<string, map<string, Any>[]> = {};
    for (let path in fsys.walk("valid")) {
        if (!path.ends_with(".toml") || bench_encode_skip(path)) {
            continue;
        }
        let rel = path.slice(6, path.length());
        let slash = rel.last_index_of("/");
        let g = if (slash == null) { "top" } else { rel.slice(0, slash) };

        let dec = decode<map<string, Any>>(fsys.read_string(path)) catch (e) {
            let te: TomlError => {
                throw `decode ${go.quote(path)}: ${te.error()}`
            },
        };
        let ok = true;
        new_encoder(go.new_buffer()).encode(dec.value) catch (e) {
            _ => {
                // b.Logf("encode failed for %q (skipping): %s", path, err)
                ok = false;
            },
        };
        if (!ok) {
            continue;
        }
        let list = files.get(g) ?? [];
        list.push(dec.value);
        files.set(g, list);
    }
    let tests: EncodeBenchGroup[] = [];
    for (let k in files.keys()) {
        tests.push(EncodeBenchGroup { group: k, data: files[k] });
    }
    tests.sort_by((a: EncodeBenchGroup, b: EncodeBenchGroup) -> baml.ops.Ordering { a.group.cmp(b.group) })
}

function bench_encode_group(g: EncodeBenchGroup, n: int) -> null {
    let start = now_ns();
    let i = 0;
    while (i < n) {
        for (let f in g.data) {
            new_encoder(go.new_buffer()).encode(f);
        }
        i += 1;
    }
    report(`Encode/${g.group}`, n, start)
}

testset "BenchmarkEncode" {
    for (let tt in bench_encode_groups()) {
        test tt.group {
            bench_encode_group(tt, 1)
        }
    }
}

// Copy from _example/example.go
class BenchExampleServer {
    IP: string,
    Hostname: string,
    Enabled: bool,
}

// duration struct{ time.Duration } with UnmarshalText.
class BenchDuration {
    Duration: go.Duration @description("go:\"embed\""),

    implements TextUnmarshaler {
        function unmarshal_text(self, text: string) -> BenchDuration throws TomlError {
            let d = go.parse_duration(text);
            match (d) {
                null => {
                    throw GoError { msg: `time: invalid duration ${go.quote(text)}`, wrapped: null }
                },
                let dd: go.Duration => BenchDuration { Duration: dd },
            }
        }
    }
}

class BenchExample {
    Title: string,
    Integers: int[],
    Times: example.FmtTime[],
    Duration: BenchDuration[],
    Distros: example.Distro[],
    Servers: map<string, BenchExampleServer>,
    Characters: map<string, example.Character[]>,
}

function bench_example(n: int) -> null {
    let f = baml.fs.open("_example/example.toml", "r");
    let t = go.string_of(f.bytes().to_array());
    let _ = f.close();

    let decoded = decode<BenchExample>(t).value;

    let buf = go.new_buffer();
    new_encoder(buf).encode(decoded);

    let start = now_ns();
    let i = 0;
    while (i < n) {
        let _ = decode<BenchExample>(t);
        i += 1;
    }
    report("Example/decode", n, start);

    start = now_ns();
    i = 0;
    while (i < n) {
        new_encoder(go.new_buffer()).encode(decoded);
        i += 1;
    }
    report("Example/encode", n, start)
}

test "BenchmarkExample" {
    bench_example(1)
}

function bench_escapes(n: int) -> null {
    let p = Parser {
        lx: lex([]),
        max_depth: 0,
        arr_depth: 0,
        context: new_key([]),
        current_key: "",
        pos: Position { line: 0, col: 0, start: 0, len: 0 },
        ordered: [],
        key_info: {},
        mapping: {},
        implicits: {},
    };
    let it = Item { typ: ItemType.Error, val: "", err: null, pos: Position { line: 0, col: 0, start: 0, len: 0 } };
    let str = "hello, world!\n".repeat(10);
    let start = now_ns();
    let i = 0;
    while (i < n) {
        let _ = p.replace_escapes(it, str);
        i += 1;
    }
    report("Escapes", n, start)
}

test "BenchmarkEscapes" {
    bench_escapes(10)
}

function bench_key(n: int) -> null {
    let k = new_key(["cargo-credential-macos-keychain", "version"]);
    let start = now_ns();
    let i = 0;
    while (i < n) {
        let _ = k.to_string();
        i += 1;
    }
    report("Key", n, start)
}

test "BenchmarkKey" {
    bench_key(100)
}
