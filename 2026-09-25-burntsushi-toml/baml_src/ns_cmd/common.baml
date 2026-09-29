// Helpers shared by the ports of cmd/* (namespace root.cmd).

// io.ReadAll(os.Stdin). BAML's baml.io.input reads one line and cannot tell
// an empty line from EOF, so stdin is opened as a file.
function read_stdin() -> int[] {
    let f = baml.fs.open("/dev/stdin", "r") catch (e) {
        _ => log_fatal("Error reading stdin"),
    };
    let b = f.bytes() catch (e) {
        _ => log_fatal("Error reading stdin"),
    };
    b.to_array()
}

// log.Fatalf with log.SetFlags(0): message to stderr, exit status 1.
function log_fatal(msg: string) -> never {
    baml.io.eprintln(msg);
    baml.sys.exit(1)
}

// encoding/json of the decoded `any` value, the way Go renders the Go types
// the decoder produces (time.Time as RFC 3339, map keys sorted).
function any_to_plain_json(v: root.Any?) -> baml.json.json {
    match (v) {
        null => null,
        let s: string => s,
        let i: bigint => i,
        let f: float => f,
        let b: bool => b,
        let t: root.go.Time => t.format(root.go.rfc3339_nano()),
        let aot: map<string, root.Any>[] => {
            let out: baml.json.json[] = [];
            for (let m in aot) {
                out.push(any_to_plain_json(m));
            }
            out
        },
        let a: root.Any[] => {
            let out: baml.json.json[] = [];
            for (let x in a) {
                out.push(any_to_plain_json(x));
            }
            out
        },
        let m: map<string, root.Any> => {
            let out: map<string, baml.json.json> = {};
            let keys = m.keys().sort_by((a: string, b: string) -> baml.ops.Ordering { a.cmp(b) });
            for (let k in keys) {
                out.set(k, any_to_plain_json(m[k]));
            }
            out
        },
    }
}

// json.Encoder.Encode with SetIndent("", "  "): pretty JSON plus newline,
// with map keys sorted like encoding/json.
function sorted_json(j: baml.json.json) -> baml.json.json {
    match (j) {
        let m: map<string, baml.json.json> => {
            let out: map<string, baml.json.json> = {};
            let keys = m.keys().sort_by((a: string, b: string) -> baml.ops.Ordering { a.cmp(b) });
            for (let k in keys) {
                out.set(k, sorted_json(m[k]));
            }
            out
        },
        let a: baml.json.json[] => {
            let out: baml.json.json[] = [];
            for (let x in a) {
                out.push(sorted_json(x));
            }
            out
        },
        _ => j,
    }
}
