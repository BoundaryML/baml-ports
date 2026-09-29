// Port of toml_test.go.
//
// Go's TestToml runs the whole toml-test suite through tomltest.Runner and
// reports each case with t.Run(test.Path, ...). The port lists the cases at
// test-collection time and registers one BAML test per case inside a dynamic
// `testset`, so each toml-test case is reported (and can be selected with
// `baml test -i`) individually, like a Go subtest.

// Test if the error message matches what we want for invalid tests. Every slice
// entry is tested with strings.Contains.
//
// Filepaths are glob'd
function error_tests() -> map<string, string[]> {
    {
        "encoding/bad-utf8*": ["invalid UTF-8 byte"],
        "encoding/utf16*": ["files cannot contain NULL bytes; probably using UTF-16"],
        "string/multiline-bad-escape-02": ["invalid escape: '\\ '"],
    }
}

// Test metadata; all keys listed as "keyname: type".
function meta_tests() -> map<string, string> {
    {
        "implicit-and-explicit-after": "
            a.b.c:         Hash
            a.b.c.answer:  Integer
            a:             Hash
            a.better:      Integer
        ",
        "implicit-and-explicit-before": "
            a:             Hash
            a.better:      Integer
            a.b.c:         Hash
            a.b.c.answer:  Integer
        ",
        "key/case-sensitive": "
            sectioN:       String
            section:       Hash
            section.name:  String
            section.NAME:  String
            section.Name:  String
            Section:       Hash
            Section.name:  String
            Section.\"μ\":   String
            Section.\"Μ\":   String
            Section.M:     String
        ",
        "key/dotted-01": "
            name.first:            String
            name.last:             String
            many.dots.dot.dot.dot: Integer
        ",
        "key/dotted-02": "
            count.a: Integer
            count.b: Integer
            count.c: Integer
            count.d: Integer
            count.e: Integer
            count.f: Integer
            count.g: Integer
            count.h: Integer
            count.i: Integer
            count.j: Integer
            count.k: Integer
            count.l: Integer
        ",
        "key/dotted-03": "
            top.key:     Integer
            tbl:         Hash
            tbl.a.b.c:   Float
            a.few.dots:                   Hash
            a.few.dots.polka.dot:         String
            a.few.dots.polka.dance-with:  String
        ",
        "key/dotted-04": "
            top.key:     Integer
            arr:         ArrayHash
            arr.a.b.c:   Integer
            arr.a.b.d:   Integer
            arr:         ArrayHash
            arr.a.b.c:   Integer
            arr.a.b.d:   Integer
         ",
        "key/empty-01": "
            \"\": String
        ",
        "key/quoted-dots": "
            plain:                          Integer
            \"with.dot\":                     Integer
            plain_table:                    Hash
            plain_table.plain:              Integer
            plain_table.\"with.dot\":         Integer
            table.withdot:                  Hash
            table.withdot.plain:            Integer
            table.withdot.\"key.with.dots\":  Integer
            table.withdot.\"escaped.dot\":  Integer
        ",
        // TODO: doesn't deal correctly with the double spaces; probably an error in
        // the test rather than code
        // "key/space": ...
        "key/special-chars": "\n" + "\"=~!@$^&*()_+-`1234567890[]|/?><.,;:'=\": Integer\n",

        // TODO: "(albums): Hash" is missing; the problem is that this is an
        // "implied key", which is recorded in the parser in implicits, rather than
        // in keys. (See the Go source for the full comment.)
        "table/array-implicit": "
            albums.songs:       ArrayHash
            albums.songs.name:  String
        ",

        // TODO: people and people.* listed many times; not entirely sure if that's
        // what we want? (See the Go source for the full comment.)
        "table/array-many": "
            people:             ArrayHash
            people.first_name:  String
            people.last_name:   String
            people:             ArrayHash
            people.first_name:  String
            people.last_name:   String
            people:             ArrayHash
            people.first_name:  String
            people.last_name:   String
        ",
        "table/array-nest": "
            albums:             ArrayHash
            albums.name:        String
            albums.songs:       ArrayHash
            albums.songs.name:  String
            albums.songs:       ArrayHash
            albums.songs.name:  String
            albums:             ArrayHash
            albums.name:        String
            albums.songs:       ArrayHash
            albums.songs.name:  String
            albums.songs:       ArrayHash
            albums.songs.name:  String
        ",
        "table/array-one": "
            people:             ArrayHash
            people.first_name:  String
            people.last_name:   String
        ",
        "table/array-table-array": "
            a:        ArrayHash
            a.b:      ArrayHash
            a.b.c:    Hash
            a.b.c.d:  String
            a.b:      ArrayHash
            a.b.c:    Hash
            a.b.c.d:  String
        ",
        "table/empty": "
            a: Hash
        ",
        "table/keyword": "
            true:   Hash
            false:  Hash
            inf:    Hash
            nan:    Hash
        ",
        "table/names": "
            a.b.c:    Hash
            a.\"b.c\":  Hash
            a.\"d.e\":  Hash
            a.\" x \":  Hash
            d.e.f:    Hash
            g.h.i:    Hash
            j.\"ʞ\".l:  Hash
            x.1.2:    Hash
        ",
        "table/no-eol-01": "
            table: Hash
        ",
        "table/sub-empty": "
            a:    Hash
            a.b:  Hash
        ",
        "table/whitespace": "
            \"valid key\": Hash
        ",
        "table/with-literal-string": "
            a:                   Hash
            a.\"\\\"b\\\"\":           Hash
            a.\"\\\"b\\\"\".c:         Hash
            a.\"\\\"b\\\"\".c.answer:  Integer
        ",
        "table/with-pound": "
            \"key#group\":         Hash
            \"key#group\".answer:  Integer
        ",
        "table/with-single-quotes": "
            a:             Hash
            a.b:           Hash
            a.b.c:         Hash
            a.b.c.answer:  Integer
        ",
        "table/without-super": "
            x.y.z.w:  Hash
            x:        Hash
        ",
        "table/without-super-with-values": "
            x.y.z.w: Hash
            x.y.z.w.a: Integer
            x.y.z.w.b: Integer
            x: Hash
            x.c: Integer
            x.d: Integer
        ",
    }
}

function toml_test_skips() -> string[] {
    [
        // fixedInGo123: the port implements the Go >= 1.23 behaviour, so
        // "invalid/datetime/offset-overflow-hour" is not skipped.

        // Go accepts e.g. 12:60, which becomes 13:00, but rejects :61.
        // TODO: might be bug in Go? It was changed before but I'm not sure
        // if accepting :60 was intentional.
        // Ref: https://github.com/BurntSushi/toml/issues/407
        "invalid/datetime/offset-overflow-minute",

        // TODO: fix this; we allow appending to tables, but shouldn't.
        "invalid/array/extend-defined-aot",
        "invalid/inline-table/duplicate-key-03",
        "invalid/inline-table/overwrite-02",
        "invalid/inline-table/overwrite-08",
        "invalid/spec-1.0.0/inline-table-2-0",
        "invalid/spec-1.0.0/table-9-1",
        "invalid/spec-1.1.0/common-46-1",
        "invalid/spec-1.1.0/common-49-0",
        "invalid/table/append-to-array-with-dotted-keys",
        "invalid/table/append-with-dotted-keys-01",
        "invalid/table/append-with-dotted-keys-02",
        "invalid/table/append-with-dotted-keys-03",
        "invalid/table/append-with-dotted-keys-05",
        "invalid/table/append-with-dotted-keys-08",
        "invalid/table/duplicate-key-04",
        "invalid/table/duplicate-key-05",
        "invalid/table/duplicate-key-dotted-table-01",
        "invalid/table/duplicate-key-dotted-table-02",
        "invalid/table/redefine-02",
        "invalid/table/redefine-03",
    ]
}

function toml_test_runner() -> tomltest.Runner {
    tomltest.Runner {
        files: tomltest.test_cases(),
        decoder: TestDecoder {},
        encoder: TestEncoder {},
        run_tests: [],
        skip_tests: toml_test_skips(),
        version: "1.1.0",
        parallel: 1,
        int_as_float: false,
        errors: {},
        skip_must_error: true,
    }
}

// Run one toml-test case exactly like the body of Go's t.Run(test.Path, ...).
function run_toml_test_case(path: string) -> null {
    let r = toml_test_runner();
    let counts = tomltest.Tests {
        tests: [],
        skipped: 0,
        passed_valid: 0,
        failed_valid: 0,
        passed_invalid: 0,
        failed_invalid: 0,
        passed_encoder: 0,
        failed_encoder: 0,
    };
    let t = r.run_one(path, counts);
    if (t == null) {
        return null;
    }
    if (t.failed()) {
        throw `\nError:\n${t.failure}\n\nInput:\n${go.string_of(t.input)}\nOutput:\n${t.output}\nWant:\n${t.want}\n`;
    }

    // Test error message.
    if (t.type() == tomltest.TestType.Invalid) {
        test_error(t);
    }
    // Test metadata
    if (t.type() == tomltest.TestType.Valid) {
        test_meta(t);
    }
    null
}

function list_toml_tests() -> string[] {
    let r = toml_test_runner();
    let ls = r.list() catch (e) {
        _ => {
            let empty: string[] = [];
            empty
        },
    };
    ls
}

testset "TestToml" {
    for (let path in list_toml_tests()) {
        test path {
            run_toml_test_case(path)
        }
    }
}

// Make sure the keys in metaTests and errorTests actually exist; easy to
// make a typo and nothing will get tested.
test "TestToml_meta_and_error_tests_exist" {
    let paths = list_toml_tests();
    let missing: string[] = [];
    for (let k in meta_tests().keys()) {
        if (!paths.includes("valid/" + k)) {
            missing.push("valid/" + k);
        }
    }
    for (let k in error_tests().keys()) {
        let found = false;
        for (let p in paths) {
            if (tomltest.match_glob("invalid/" + k, p)) {
                found = true;
            }
        }
        if (!found) {
            missing.push("invalid/" + k);
        }
    }
    assert.equal(missing.join(", "), "")
}

// var reCollapseSpace = regexp.MustCompile(` +`)
function collapse_space(s: string) -> string {
    let out = s;
    while (out.includes("  ")) {
        out = out.replace_all("  ", " ");
    }
    out
}

function test_meta(tt: tomltest.Test) -> null {
    let want0 = meta_tests().get(tt.path.slice(6, tt.path.length()));
    if (want0 == null || !tt.path.starts_with("valid/")) {
        return null;
    }

    let meta = unmarshal_meta(tt.input);

    let b = "";
    let i = 0;
    for (let k in meta.keys()) {
        if (i > 0) {
            b += "\n";
        }
        b += `${k.to_string()}: ${meta.type(k.parts)}`;
        i += 1;
    }
    let have = b;

    // Go: strings.ReplaceAll(strings.TrimSpace(want), "\t", "") then collapse
    // runs of spaces. The BAML literals are indented with spaces rather than
    // tabs, so leading indentation is stripped per line as well.
    let lines: string[] = [];
    for (let l in want0.trim().split("\n")) {
        lines.push(l.replace_all("\t", "").trim_start());
    }
    let want = collapse_space(lines.join("\n"));
    if (have != want) {
        throw `MetaData wrong\nhave:\n${have}\nwant:\n${want}`;
    }
    null
}

function unmarshal_meta(input: int[]) -> MetaData throws TomlError {
    new_decoder(go.new_bytes_reader(input)).decode<Any>(null).meta
}

function test_error(tt: tomltest.Test) -> null {
    let path = tt.path.slice(8, tt.path.length());

    let errs = error_tests().get(path);
    if (errs == null) {
        for (let k in error_tests().keys()) {
            if (tomltest.match_glob(k, path)) {
                errs = error_tests()[k];
                break;
            }
        }
    }
    if (errs == null) {
        return null;
    }

    for (let e in errs) {
        if (!tt.output.includes(e)) {
            throw `\nwrong error message\nhave: ${tt.output}\nwant: ${e}`;
        }
    }
    null
}

class TestDecoder {
    implements tomltest.Parser {
        function cmd(self) -> string[] {
            []
        }

        function run(self, input: int[]) -> tomltest.RunResult {
            // Go: defer/recover turns a panic into retErr. BAML panics cannot be
            // caught; the port's own "panics" (bug(), go_panic) are thrown
            // `Panic` values and are caught here.
            let d = new_decoder(go.new_bytes_reader(input)).decode<Any>(null) catch (err) {
                let p: Panic => {
                    return tomltest.RunResult { pid: 0, output: "", output_is_error: false, err: p.msg };
                },
                let e: TomlError => {
                    return tomltest.RunResult { pid: 0, output: e.error(), output_is_error: true, err: null };
                },
            };

            let j = tag.add("", d.value);
            tomltest.RunResult { pid: 0, output: baml.json.stringify_pretty(j), output_is_error: false, err: null }
        }
    }
}

class TestEncoder {
    implements tomltest.Parser {
        function cmd(self) -> string[] {
            []
        }

        function run(self, input: int[]) -> tomltest.RunResult {
            let tmp = baml.json.parse(go.string_of(input)) catch (e) {
                let pe: baml.json.ParseError => {
                    return tomltest.RunResult { pid: 0, output: "", output_is_error: false, err: pe.message };
                },
            };

            let rm = tag.remove(tmp) catch (err) {
                let e: GoError => {
                    return tomltest.RunResult { pid: 0, output: e.msg, output_is_error: true, err: null };
                },
            };

            let buf = go.new_buffer();
            new_encoder(buf).encode(rm) catch (err) {
                let p: Panic => {
                    return tomltest.RunResult { pid: 0, output: "", output_is_error: false, err: p.msg };
                },
                let e: TomlError => {
                    return tomltest.RunResult { pid: 0, output: e.error(), output_is_error: true, err: null };
                },
            };

            let s = buf.string();
            if (s == "") {
                s = "\n";
            }
            tomltest.RunResult { pid: 0, output: s, output_is_error: false, err: null }
        }
    }
}
