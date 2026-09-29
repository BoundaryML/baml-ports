// Port of internal/toml-test/runner.go (namespace root.tomltest).
//
// Differences from Go, all forced by the language/runtime:
//   * Go embeds the test files with //go:embed and exposes them as an fs.FS;
//     BAML has no embedding, so `Files` reads them from a directory on disk
//     (testdata/toml-test, a copy of internal/toml-test/tests) and synthesises
//     the "encoder/" tree from "valid/" just like TestCases() does.
//   * Go runs tests on goroutines with a per-test timeout (context.WithTimeout);
//     the port runs them sequentially without a timeout.
//   * Test input is kept as raw bytes (int[]): several tests contain invalid
//     UTF-8, which a BAML string cannot hold.

enum TestType {
    Valid,
    Encoder,
    Invalid,
}

function default_version() -> string {
    "1.0.0"
}

// An fs.FS over the toml-test files.
class Files {
    root: string,

    // fs.ReadFile(fsys, path) as bytes.
    function read_file(self, path: string) -> int[] {
        let real = path;
        if (path.starts_with("encoder/")) {
            real = "valid/" + path.slice(8, path.length());
        }
        let f = baml.fs.open(self.root + "/" + real, "r") catch (e) {
            _ => {
                throw root.GoError { msg: `open ${path}: file does not exist`, wrapped: null }
            },
        };
        let b = f.bytes() catch (e) {
            _ => {
                throw root.GoError { msg: `read ${path}: error`, wrapped: null }
            },
        };
        let _ = f.close() catch (e) {
            _ => null
        };
        b.to_array()
    }

    function read_string(self, path: string) -> string {
        root.go.string_of(self.read_file(path))
    }

    function exists(self, path: string) -> bool {
        let real = path;
        if (path.starts_with("encoder")) {
            real = "valid" + path.slice(7, path.length());
        }
        baml.fs.exists(self.root + "/" + real) catch (e) {
            _ => false
        }
    }

    // fs.WalkDir(fsys, dir, ...) collecting every file path, in lexical order.
    function walk(self, dir: string) -> string[] {
        let real = dir;
        if (dir.starts_with("encoder")) {
            real = "valid" + dir.slice(7, dir.length());
        }
        let out: string[] = [];
        let entries = baml.fs.read_dir(self.root + "/" + real) catch (e) {
            _ => {
                return out;
            },
        };
        let names: string[] = [];
        let is_dir: map<string, bool> = {};
        for (let e in entries) {
            names.push(e.name);
            is_dir.set(e.name, e.is_dir);
        }
        names = names.sort_by((a: string, b: string) -> baml.ops.Ordering { a.cmp(b) });
        for (let n in names) {
            let p = dir + "/" + n;
            if (is_dir[n]) {
                out = out.concat(self.walk(p));
            } else {
                out.push(p);
            }
        }
        out
    }
}

// TestCases embedded in toml-test, rooted to the "test/" directory.
function test_cases() -> Files {
    Files { root: "testdata/toml-test" }
}

// The output of one Parser.Run: Go returns (pid, output, outputIsError, err).
class RunResult {
    pid: int,
    output: string,
    output_is_error: bool,
    err: string?,
}

// A Parser instance is used to call the TOML parser we test.
//
// By default this is done through an external command.
interface Parser {
    // Run a parser command (decoder or encoder).
    //
    // If outputIsError is true then it's assumed that an encoding error
    // occurred.
    //
    // An error return should only be used in case an unrecoverable error
    // occurred; failing to encode to TOML is not an error, but the encoder
    // unexpectedly panicking is.
    function run(self, input: int[]) -> RunResult throws root.Panic;

    function cmd(self) -> string[] throws never;
}

// Runner runs a set of tests.
//
// The validity of the parameters is not checked extensively; the caller should
// verify this if need be. See ./cmd/toml-test for an example.
class Runner {
    files: Files, // Test files.
    decoder: Parser, // Send data to a parser.
    encoder: Parser?,
    run_tests: string[], // Tests to run; run all if blank.
    skip_tests: string[], // Tests to skip.
    version: string, // TOML version to run tests for.
    parallel: int, // Number of tests to run in parallel
    int_as_float: bool, // Int values have type=float.
    errors: map<string, string>, // Expected errors list.
    skip_must_error: bool, // Tests in SkipTests must fail. Useful for CI.

    // List all tests in Files for the current TOML version.
    function list(self) -> string[] {
        let vs = versions();
        let v0 = vs.get(self.version);
        if (v0 == null) {
            let v: string[] = vs.keys().sort_by((a: string, b: string) -> baml.ops.Ordering { a.cmp(b) });
            throw root.GoError {
                msg: `tomltest.Runner.Run: unknown version: ${root.go.quote(self.version)} (supported: "${v.join("\", \"")}")`,
                wrapped: null,
            };
        }

        let v = v0;
        let exclude: string[] = [];
        while (true) {
            let excl = v.exclude.slice(0, v.exclude.length());
            for (let vv in v.exclude) {
                if (vv.starts_with("valid")) {
                    excl.push("encoder" + vv.slice(5, vv.length()));
                }
            }
            exclude = exclude.concat(excl);
            if (v.inherit == "") {
                break;
            }
            let next = vs.get(v.inherit);
            if (next == null) {
                break;
            }
            v = next;
        }

        let ls: string[] = [];
        ls = ls.concat(self.find_toml("valid", exclude));
        ls = ls.concat(self.find_toml("encoder", exclude));
        ls = ls.concat(self.find_toml("invalid", exclude));
        ls
    }

    // Run all tests listed in t.RunTests.
    //
    // TODO: give option to:
    // - Run all tests with \n replaced with \r\n
    // - Run all tests with EOL removed
    // - Run all tests with '# comment' appended to every line.
    function run(self) -> Tests {
        let skipped = self.find_tests();
        if (self.parallel == 0) {
            self.parallel = 1;
        }
        let nerr: map<string, string> = {};
        for (let k0 in self.errors.keys()) {
            let k = k0;
            if (!k.starts_with("invalid/")) {
                k = "invalid/" + k;
            }
            if (k.ends_with(".toml")) {
                k = k.slice(0, k.length() - 5);
            }
            nerr.set(k, self.errors[k0]);
        }
        self.errors = nerr;

        let tests = Tests {
            tests: [],
            skipped: skipped,
            passed_valid: 0,
            failed_valid: 0,
            passed_invalid: 0,
            failed_invalid: 0,
            passed_encoder: 0,
            failed_encoder: 0,
        };
        for (let p in self.run_tests) {
            let t = self.run_one(p, tests);
            if (t != null) {
                tests.tests.push(t);
            }
        }

        // Sort valid first, encoder second, and invalid last.
        tests.tests = tests.tests.sort_by((a: Test, b: Test) -> baml.ops.Ordering {
            sort_key(a.path).cmp(sort_key(b.path))
        });

        if (self.errors.length() > 0) {
            throw root.GoError { msg: `errors didn't match anything: ${self.errors.keys().join(", ")}`, wrapped: null };
        }
        tests
    }

    // The body of Run's per-test goroutine, exposed so that a BAML testset can
    // run (and report) each toml-test case as its own test. `tests` receives
    // the pass/fail counts; returns null when the test is not run at all.
    function run_one(self, p: string, tests: Tests) -> Test? {
        let t = new_test(p, self.int_as_float);
        if (self.encoder == null && t.encoder()) {
            return null;
        }
        if (self.has_skip(p) && !self.skip_must_error) {
            tests.skipped += 1;
            t.skipped = true;
            return t;
        }

        let cmd = self.decoder;
        if (t.encoder()) {
            let enc = self.encoder;
            if (enc != null) {
                cmd = enc;
            }
        }
        t = t.run(cmd, self.files);

        let e = self.errors.get(p);
        if (e != null) {
            if (t.invalid() && !t.failed() && !t.output.includes(e)) {
                t.failure = `${root.go.quote(t.output)} does not contain ${root.go.quote(e)}`;
            }
        }
        let _ = self.errors.delete(p);

        if (self.skip_must_error && self.has_skip(p)) {
            if (t.failed()) {
                tests.skipped += 1;
                t.skipped = true;
                t.failure = "";
            } else {
                t.failure = "Test skipped with -skip but didn't fail";
                if (t.invalid()) {
                    tests.failed_invalid += 1;
                } else if (t.encoder()) {
                    tests.failed_encoder += 1;
                } else {
                    tests.failed_valid += 1;
                }
            }
        } else if (t.failed()) {
            if (t.invalid()) {
                tests.failed_invalid += 1;
            } else if (t.encoder()) {
                tests.failed_encoder += 1;
            } else {
                tests.failed_valid += 1;
            }
        } else {
            if (t.invalid()) {
                tests.passed_invalid += 1;
            } else if (t.encoder()) {
                tests.passed_encoder += 1;
            } else {
                tests.passed_valid += 1;
            }
        }
        t
    }

    // find all TOML files in 'path' relative to the test directory.
    function find_toml(self, path: string, exclude: string[]) -> string[] {
        let out: string[] = [];
        // It's okay if the directory doesn't exist. Mainly to make testing a bit
        // easier.
        if (!self.files.exists(path)) {
            return out;
        }

        for (let p0 in self.files.walk(path)) {
            if (!p0.ends_with(".toml")) {
                continue;
            }
            let p = p0.slice(0, p0.length() - 5);
            let excluded = false;
            for (let e in exclude) {
                if (match_glob(e, p)) {
                    excluded = true;
                    break;
                }
            }
            if (!excluded) {
                out.push(p);
            }
        }
        out
    }

    // Expand RunTest glob patterns, or return all tests if RunTests if empty.
    function find_tests(self) -> int {
        let ls = self.list();

        let skip = 0;
        if (self.run_tests.length() == 0) {
            self.run_tests = ls;
        } else {
            let run: string[] = [];
            for (let l in ls) {
                for (let r in self.run_tests) {
                    if (match_glob(r, l)) {
                        run.push(l);
                        break;
                    }
                }
            }
            skip = ls.length() - run.length();
            self.run_tests = run;
        }

        // Expand invalid tests ending in ".multi.toml"
        let expanded: string[] = [];
        for (let path in self.run_tests) {
            if (!path.ends_with(".multi")) {
                expanded.push(path);
                continue;
            }
            // Go prints the file and drops the test.
            baml.io.println(self.files.read_string(path + ".toml"));
        }
        self.run_tests = expanded;
        skip
    }

    function has_skip(self, path: string) -> bool {
        for (let s in self.skip_tests) {
            if (s != "" && match_glob(s, path)) {
                return true;
            }
        }
        false
    }
}

function sort_key(p: string) -> string {
    p.replace("encoder/", "wencoder/").replace("invalid/", "zinvalid/")
}

function new_runner(r: Runner) -> Runner {
    if (r.version == "" || r.version == "1.0") {
        r.version = "1.0.0";
    } else if (r.version == "1.1") {
        r.version = "1.1.0";
    } else if (r.version == "latest") {
        r.version = "1.1.0";
    }
    r
}

// Tests are tests to run.
class Tests {
    tests: Test[],

    // Set when test are run.

    skipped: int,
    passed_valid: int,
    failed_valid: int,
    passed_invalid: int,
    failed_invalid: int,
    passed_encoder: int,
    failed_encoder: int,
}

// Result is the result of a single test.
class Test {
    path: string, // Path of test, e.g. "valid/string-test"

    // Set when a test is run.

    skipped: bool, // Skipped this test?
    failure: string, // Failure message.
    key: string, // TOML key the failure occured on; may be blank.
    input: int[], // The test case that we sent to the external program.
    output: string, // Output from the external program.
    want: string, // The output we want.
    output_from_stderr: bool, // The Output came from stderr, not stdout.
    pid: int, // PID from test run.
    int_as_float: bool, // Int values have type=float.

    // Go's Test is a value type: every method that "modifies" it works on a
    // copy. BAML classes are references, so the port copies explicitly.
    function copy(self) -> Test {
        Test {
            path: self.path,
            skipped: self.skipped,
            failure: self.failure,
            key: self.key,
            input: self.input,
            output: self.output,
            want: self.want,
            output_from_stderr: self.output_from_stderr,
            pid: self.pid,
            int_as_float: self.int_as_float,
        }
    }

    // Run this test.
    function run(self, p: Parser, fsys: Files) -> Test {
        if (self.invalid()) {
            return self.run_invalid(p, fsys);
        }
        self.run_valid(p, fsys)
    }

    function run_invalid(self, p: Parser, fsys: Files) -> Test {
        let t = self.copy();
        t.input = t.read_input(fsys) catch (e) {
            let ge: root.GoError => {
                return t.bug(ge.msg);
            },
        };

        // Go's parsers recover panics into their error return.
        let res = p.run(t.input) catch (e) {
            let pn: root.Panic => {
                return t.fail(pn.msg);
            },
        };
        t.pid = res.pid;
        t.output = res.output;
        t.output_from_stderr = res.output_is_error;
        let err = res.err;
        if (err != null) {
            return t.fail(err);
        }
        if (!t.output_from_stderr) {
            return t.fail("Expected an error, but no error was reported.");
        }
        t
    }

    function run_valid(self, p: Parser, fsys: Files) -> Test {
        let t = self.copy();
        t.input = t.read_input(fsys) catch (e) {
            let ge: root.GoError => {
                return t.bug(ge.msg);
            },
        };

        // Go's parsers recover panics into their error return.
        let res = p.run(t.input) catch (e) {
            let pn: root.Panic => {
                return t.fail(pn.msg);
            },
        };
        t.pid = res.pid;
        t.output = res.output;
        t.output_from_stderr = res.output_is_error;
        let err = res.err;
        if (err != null) {
            return t.fail(err);
        }
        if (t.output_from_stderr) {
            return t.fail(t.output);
        }
        if (t.output == "") {
            return t.fail("stdout is empty");
        }

        // Compare for encoder test
        if (t.encoder()) {
            let want = t.read_want_toml(fsys) catch (e) {
                let ge: root.GoError => {
                    return t.bug(ge.msg);
                },
            };
            let have = root.decode<root.Any>(t.output) catch (e) {
                let te: root.TomlError => {
                    return t.fail(`decode TOML from encoder:\n  ${te.error()}`);
                },
            };
            return t.compare_toml(want, have.value);
        }

        // Compare for decoder test
        let want = t.read_want_json(fsys) catch (e) {
            let ge: root.GoError => {
                return t.fail(ge.msg);
            },
        };

        let have = baml.json.parse(t.output) catch (e) {
            let pe: baml.json.ParseError => {
                return t.fail(`decode JSON output from parser:\n  ${pe.message}`);
            },
        };

        t.compare_json(want, have)
    }

    // ReadInput reads the file sent to the encoder.
    function read_input(self, fsys: Files) -> int[] {
        let path = self.path + if (self.encoder()) { ".json" } else { ".toml" };
        fsys.read_file(path)
    }

    function read_want(self, fsys: Files) -> string {
        if (self.invalid()) {
            root.go_panic("testoml.Test.ReadWant: invalid tests do not have a 'correct' version");
        }

        let path = self.path + if (self.encoder()) { ".toml" } else { ".json" };
        fsys.read_string(path)
    }

    function read_want_json(self, fsys: Files) -> baml.json.json {
        self.want = self.read_want(fsys);
        baml.json.parse(self.want) catch (e) {
            let pe: baml.json.ParseError => {
                throw root.GoError { msg: `decode JSON file ${root.go.quote(self.path)}:\n  ${pe.message}`, wrapped: null }
            },
        }
    }

    function read_want_toml(self, fsys: Files) -> root.Any {
        self.want = self.read_want(fsys);
        let v = root.decode<root.Any>(self.want) catch (e) {
            let te: root.TomlError => {
                throw root.GoError { msg: `could not decode TOML file ${root.go.quote(self.path)}:\n  ${te.error()}`, wrapped: null }
            },
        };

        // All numbers are floats, but assume that natural numbers are encoded
        // without the .0.
        if (self.int_as_float) {
            match (v.value) {
                let vv: map<string, root.Any> => {
                    return float_to_int(vv);
                },
                _ => {},
            }
        }
        v.value
    }

    // Test type: "valid", "encoder", "invalid"
    function type(self) -> TestType {
        if (self.path.starts_with("invalid")) {
            return TestType.Invalid;
        }
        if (self.path.starts_with("encoder")) {
            return TestType.Encoder;
        }
        TestType.Valid
    }

    function encoder(self) -> bool {
        self.type() == TestType.Encoder
    }

    function invalid(self) -> bool {
        self.type() == TestType.Invalid
    }

    function fail(self, msg: string) -> Test {
        let t = self.copy();
        t.failure = msg;
        t
    }

    function bug(self, msg: string) -> Test {
        self.fail("BUG IN TEST CASE: " + msg)
    }

    function failed(self) -> bool {
        self.failure != ""
    }

    function kjoin(self, key: string) -> Test {
        let t = self.copy();
        if (t.key.length() == 0) {
            t.key = key;
        } else {
            t.key += "." + key;
        }
        t
    }

    // CompareJSON compares the given arguments (json.go).
    function compare_json(self, want: baml.json.json, have: baml.json.json) -> Test {
        compare_json(self, want, have)
    }

    // CompareTOML compares the given arguments (toml.go).
    function compare_toml(self, want: root.Any?, have: root.Any?) -> Test {
        compare_toml(self, want, have)
    }
}

function new_test(path: string, int_as_float: bool) -> Test {
    Test {
        path: path,
        skipped: false,
        failure: "",
        key: "",
        input: [],
        output: "",
        want: "",
        output_from_stderr: false,
        pid: 0,
        int_as_float: int_as_float,
    }
}

function float_to_int(m: map<string, root.Any>) -> map<string, root.Any> {
    let newm: map<string, root.Any> = {};
    for (let k in m.keys()) {
        let v = m[k];
        match (v) {
            let vv: float => {
                let frac = vv.fract();
                let max_safe_float = 9007199254740991.0;
                if (!vv.is_nan() && !vv.is_infinite() && vv <= max_safe_float && frac == 0.0) {
                    v = bigint.parse(vv.itrunc().to_string()) catch (e) {
                        _ => 0n
                    };
                }
            },
            let vv: map<string, root.Any> => {
                v = float_to_int(vv);
            },
            let vv: map<string, root.Any>[] => {
                let arr: map<string, root.Any>[] = [];
                for (let t in vv) {
                    arr.push(float_to_int(t));
                }
                v = arr;
            },
            let vv: root.Any[] => {
                let arr: root.Any[] = [];
                for (let t0 in vv) {
                    // TODO: doesn't process nested arrays. It's okay for now as no
                    // tests need it.
                    let t = t0;
                    match (t0) {
                        let tt: float => {
                            if (!tt.is_nan() && !tt.is_infinite() && tt == tt.round()) {
                                t = bigint.parse(tt.itrunc().to_string()) catch (e) {
                                    _ => 0n
                                };
                            }
                        },
                        let tt: map<string, root.Any> => {
                            t = float_to_int(tt);
                        },
                        _ => {},
                    }
                    arr.push(t);
                }
                v = arr;
            },
            _ => {},
        }
        newm.set(k, v);
    }
    newm
}

// filepath.Match for the patterns toml-test uses: `*` (any run of
// non-separator characters), `?` (one non-separator character) and literals.
function match_glob(pattern: string, name: string) -> bool {
    // Fast paths (the VM is slow enough that listing the suite with a naive
    // matcher took seconds): no wildcard, or a literal prefix that differs.
    let star = pattern.index_of("*");
    let q = pattern.index_of("?");
    if (star == null && q == null) {
        return pattern == name;
    }
    let lit_end = star ?? pattern.length();
    if (q != null) {
        if (q < lit_end) {
            lit_end = q;
        }
    }
    if (!name.starts_with(pattern.slice(0, lit_end))) {
        return false;
    }
    glob_at(pattern.chars(), 0, name.chars(), 0)
}

function glob_at(p: string[], pi: int, n: string[], ni: int) -> bool {
    if (pi == p.length()) {
        return ni == n.length();
    }
    let c = p[pi];
    if (c == "*") {
        let k = ni;
        while (true) {
            if (glob_at(p, pi + 1, n, k)) {
                return true;
            }
            if (k >= n.length() || n[k] == "/") {
                return false;
            }
            k += 1;
        }
        return false;
    }
    if (ni >= n.length()) {
        return false;
    }
    if (c == "?") {
        if (n[ni] == "/") {
            return false;
        }
        return glob_at(p, pi + 1, n, ni + 1);
    }
    if (c != n[ni]) {
        return false;
    }
    glob_at(p, pi + 1, n, ni + 1)
}
