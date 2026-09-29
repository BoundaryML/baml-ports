// Ported from sasso `tests/cli_dart_compat.rs` (namespace
// `root.tests.cli_dart_compat`), part 1 of 2 (part 2 is
// `cli_dart_compat_p2.baml`, same namespace).
//
// End-to-end tests for the dart-sass-compatible CLI surface: the positional
// grammar (`<input> [output]`), `in:out` pairs (files and directories),
// parallel compilation, dart's defaults (source maps and an error stylesheet
// when writing to a file), `--embed-source-map`, `--quiet`/`--quiet-deps`,
// `--stop-on-error`, and dart's exit codes. Drives the REAL built binary
// (`env!("CARGO_BIN_EXE_sasso")`).
//
// A gated dart-sass differential (opt-in via `SASSO_PARITY=1` + a reachable
// `$SASS_BIN` that is the dart-sass CLI) runs the same invocation through
// dart-sass and compares the produced files byte-for-byte.
//
// PORT: `Path`/`PathBuf` are `string`s (`dir.join(x)` → `root.std.path_join`);
// `std::fs::remove_dir_all(&dir).ok()` → `baml.fs.remove_dir_all` with its
// `Io` caught; the binary is the `baml pack`ed CLI (`root.tests.support`).
// `baml test` runs the tests concurrently in one process, which is what the
// Rust harness does too (threads): every test uses its own scratch directory.

/// `const BIN: &str = env!("CARGO_BIN_EXE_sasso");`
function BIN() -> string {
    root.tests.support.sasso_bin()
}

/// dart-sass exit codes.
function EXIT_USAGE() -> int {
    64
}

function EXIT_COMPILE() -> int {
    65
}

function EXIT_IO() -> int {
    66
}

function scratch(tag: string) -> string {
    let dir = root.std.path_join(
        root.tests.support.temp_dir(),
        `sasso_cli_dc_${tag}_${baml.sys.pid()}_${unique()}`,
    );
    root.std.create_dir_all(dir) catch (e) {
        let io: baml.errors.Io => root.std.panic(`create scratch dir: ${io.message}`)
    };
    dir
}

/// `static N: AtomicU64` inside `unique`.
// PORT: a top-level `client` holds the process-wide counter (guide §15);
// `fetch_add(1, Relaxed)` → read then write (green threads switch only at
// suspension points, so this is atomic).
client unique__N_CELL = root.std.Cell<int> { value: 0 };

function unique__N() -> root.std.Cell<int> {
    unique__N_CELL
}

function unique() -> int {
    let n = unique__N();
    let v = n.value;
    n.value = v + 1;
    v
}

class Run {
    code: int,
    stdout: string,
    stderr: string,
}

function run_bin(bin: string, cwd: string, args: string[], stdin: string?) -> Run {
    run_bin_bytes(bin, cwd, args, stdin?.to_utf8())
}

/// [`run_bin`] with raw bytes on stdin (for input that is not valid UTF-8).
// PORT: `Command::spawn` + `wait_with_output` → `baml.sys.start_process`
// with stdout and stderr piped and drained concurrently. The child's stdin is
// always a pipe here; `Stdio::null()` → a pipe closed straight away (the same
// immediate EOF).
function run_bin_bytes(bin: string, cwd: string, args: string[], stdin: uint8array?) -> Run {
    let child = baml.sys.start_process(
        bin,
        args,
        baml.sys.ProcessOptions {
            cwd: cwd,
            env: null,
            timeout_ms: null,
            stdin: null,
            stderr: baml.sys.StderrMode.Pipe,
        },
    ) catch (e) {
        let io: baml.errors.Io => root.std.panic(`spawn: ${io.message}`)
    };
    if (stdin != null) {
        // A child that never reads stdin (a usage error, or an invocation whose
        // input is a file) may exit before this write lands; the resulting
        // closed pipe is not a test failure. Any other write error is.
        let _ = child.stdin.write(stdin) catch (e) {
            let io: baml.errors.Io => {
                // stdin write failed: {e}
                assert.is_true(io.message.includes("Broken pipe"));
                0
            }
        };
    }
    let _ = child.stdin.close() catch (e) {
        let _io: baml.errors.Io => null
    };
    let stdout_pipe = child.stdout;
    let stderr_pipe = child.stderr;
    let out_f = spawn { run_bin_bytes__drain(stdout_pipe) };
    let err_f = spawn { run_bin_bytes__drain(stderr_pipe) };
    let out_stdout = await out_f;
    let out_stderr = await err_f;
    let status = child.wait() catch (e) {
        _ => root.std.panic("wait")
    };
    Run {
        code: if (status.signal != null) {
            -1
        } else {
            status.exit_code
        },
        stdout: root.std.from_utf8_lossy(out_stdout),
        stderr: root.std.from_utf8_lossy(out_stderr),
    }
}

// PORT: reading one of the child's pipes to EOF (what `wait_with_output`
// does for each).
function run_bin_bytes__drain(pipe: baml.sys.ReadPipe?) -> uint8array {
    if (pipe == null) {
        return b"";
    }
    pipe.bytes() catch (e) {
        let io: baml.errors.Io => root.std.panic(`wait: ${io.message}`)
    }
}

function sasso(cwd: string, args: string[]) -> Run {
    run_bin(BIN(), cwd, args, null)
}

function write(dir: string, name: string, contents: string) -> string {
    let p = root.std.path_join(dir, name);
    let parent = root.std.path_parent(p);
    if (parent != null) {
        root.std.create_dir_all(parent) catch (e) {
            let io: baml.errors.Io => root.std.panic(`mkdir -p: ${io.message}`)
        };
    }
    root.std.write_file(p, contents) catch (e) {
        let io: baml.errors.Io => root.std.panic(`write input: ${io.message}`)
    };
    p
}

function read(dir: string, name: string) -> string {
    root.std.read_to_string(root.std.path_join(dir, name)) catch (e) {
        let io: baml.errors.Io => root.std.panic(`read ${name}: ${io.message}`)
    }
}

/// The dart-sass CLI binary for the gated differential, if enabled and set to
/// a real executable (the `npx` default of the other parity tests is not a
/// file-writing CLI we can point at a scratch dir reliably).
function dart_bin() -> string? {
    let parity = root.std.env_var("SASSO_PARITY");
    if (parity == null || parity == "0") {
        return null;
    }
    let bin = root.std.env_var("SASS_BIN");
    if (bin == null) {
        return null;
    }
    if (bin == "npx" || !root.std.is_file(bin)) {
        return null;
    }
    // Absolute, so a relative `SASS_BIN` still resolves once the child runs in
    // a scratch directory.
    root.std.canonicalize(bin) catch (e) {
        let _io: baml.errors.Io => null
    }
}

/// Run the same `args` through dart-sass in a sibling scratch dir seeded with
/// the same `files`, and assert every file in `outputs` matches byte-for-byte.
function assert_dart_files_match(
    files: root.std.Tuple2<string, string>[],
    args: string[],
    outputs: string[],
) -> void {
    let dart = dart_bin();
    if (dart == null) {
        return;
    }
    let ours = scratch("parity_ours");
    let theirs = scratch("parity_theirs");
    for (let file in files) {
        write(ours, file._0, file._1);
        write(theirs, file._0, file._1);
    }
    let a = sasso(ours, args);
    let b = run_bin(dart, theirs, args, null);
    // exit codes differ for {args:?}\nours: {a.stderr}\ndart: {b.stderr}
    assert.equal(a.code, b.code);
    for (let out in outputs) {
        let x: string? = root.std.read_to_string(root.std.path_join(ours, out)) catch (e) {
            let _io: baml.errors.Io => null
        };
        let y: string? = root.std.read_to_string(root.std.path_join(theirs, out)) catch (e) {
            let _io: baml.errors.Io => null
        };
        // {out} differs from dart-sass for {args:?}
        assert.equal(x, y);
    }
    let _ = baml.fs.remove_dir_all(ours) catch (e) {
        let _io: baml.errors.Io => null
    };
    let _ = baml.fs.remove_dir_all(theirs) catch (e) {
        let _io: baml.errors.Io => null
    };
}

function GOOD() -> string {
    "$c: red;\na { color: $c; }\n"
}

function GOOD_CSS() -> string {
    "a {\n  color: red;\n}\n"
}

function BAD() -> string {
    "a { b: $x }\n"
}

// ---------------------------------------------------------------------------
// Positional grammar
// ---------------------------------------------------------------------------

test "second_positional_is_the_output_file" {
    let dir = scratch("pos");
    write(dir, "in.scss", GOOD());
    let r = sasso(dir, ["--no-source-map", "in.scss", "out.css"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    // nothing on stdout when writing a file
    assert.equal(r.stdout, "");
    assert.equal(read(dir, "out.css"), GOOD_CSS());
    // `--stdin [output]`
    let r = run_bin(BIN(), dir, ["--stdin", "--no-source-map", "from-stdin.css"], "x { y: z }\n");
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.equal(read(dir, "from-stdin.css"), "x {\n  y: z;\n}\n");
    // A stdin entry has no path: dart records its text as a `data:` URI in the
    // map's `sources`, both in a sidecar and inside an embedded map.
    let r = run_bin(BIN(), dir, ["--stdin", "stdin-map.css"], "a{b:c}\n");
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.equal(
        read(dir, "stdin-map.css.map"),
        "{\"version\":3,\"sourceRoot\":\"\",\"sources\":[\"data:;charset=utf-8,a%7Bb:c%7D%0A\"],\"names\":[],\"mappings\":\"AAAA;EAAE\",\"file\":\"stdin-map.css\"}",
    );
    let r = run_bin(BIN(), dir, ["--stdin", "--embed-source-map"], "a{b:c}\n");
    // {r.stderr}
    assert.equal(r.code, 0);
    // {r.stdout}
    assert.is_true(
        r.stdout.includes("%22sources%22:%5B%22data:;charset=utf-8,a%257Bb:c%257D%250A%22%5D"),
    );
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "dash_positional_reads_stdin" {
    let dir = scratch("dash");
    let r = run_bin(BIN(), dir, ["--no-source-map", "-"], "x { y: z }\n");
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.equal(r.stdout, "x {\n  y: z;\n}\n");
    let r = run_bin(BIN(), dir, ["--no-source-map", "-", "a.css"], "x { y: z }\n");
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.equal(read(dir, "a.css"), "x {\n  y: z;\n}\n");
    let r = run_bin(BIN(), dir, ["--no-source-map", "-:b.css"], "x { y: z }\n");
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.equal(read(dir, "b.css"), "x {\n  y: z;\n}\n");
    // A `-` INPUT is stdin whatever the final `--[no-]stdin` value (dart).
    let r = run_bin(BIN(), dir, ["--no-source-map", "-", "--no-stdin", "c.css"], "x { y: z }\n");
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.equal(read(dir, "c.css"), "x {\n  y: z;\n}\n");
    // … and `--stdin --no-stdin` is off: the positional is the input.
    write(dir, "in.scss", GOOD());
    let r = run_bin(BIN(), dir, ["--no-source-map", "--stdin", "--no-stdin", "in.scss"], "x { y: z }\n");
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.equal(r.stdout, GOOD_CSS());
    // A `-` in the OUTPUT position is a file called `-`, as in dart; the input
    // is left alone.
    let r = run_bin(BIN(), dir, ["--no-source-map", "in.scss", "-"], "x { y: z }\n");
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.equal(read(dir, "-"), GOOD_CSS());
    assert.equal(read(dir, "in.scss"), GOOD());
    // `-:out` is a pair like any other and mixes with file pairs (dart keeps
    // `-` as a source in the same map); the same source twice is an error.
    write(dir, "b.scss", "p { q: 1 }\n");
    let r = run_bin(BIN(), dir, ["--no-source-map", "-:d.css", "b.scss:bb.css"], "x { y: z }\n");
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.equal(read(dir, "d.css"), "x {\n  y: z;\n}\n");
    assert.equal(read(dir, "bb.css"), "p {\n  q: 1;\n}\n");
    let r = run_bin(BIN(), dir, ["--no-source-map", "-:e.css", "-:f.css"], "x { y: z }\n");
    assert.equal(r.code, EXIT_USAGE());
    // {r.stderr}
    assert.is_true(r.stderr.includes("Duplicate source \"-\"."));
    assert.is_true(
        !root.std.exists(root.std.path_join(dir, "e.css"))
            && !root.std.exists(root.std.path_join(dir, "f.css")),
    );
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "too_many_positionals_is_a_usage_error" {
    let dir = scratch("pos_err");
    write(dir, "in.scss", GOOD());
    let r = sasso(dir, ["in.scss", "a.css", "b.css"]);
    assert.equal(r.code, EXIT_USAGE());
    // {r.stderr}
    assert.is_true(r.stderr.includes("Only two positional args may be passed."));
    let r = run_bin(BIN(), dir, ["--stdin", "a.css", "b.css"], "a{b:c}");
    assert.equal(r.code, EXIT_USAGE());
    // {r.stderr}
    assert.is_true(r.stderr.includes("Only one argument is allowed with --stdin."));
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

// ---------------------------------------------------------------------------
// `in:out` pairs and directory mode
// ---------------------------------------------------------------------------

test "pairs_compile_each_input_to_its_own_output" {
    let dir = scratch("pairs");
    write(dir, "a.scss", GOOD());
    write(dir, "b.scss", "b { w: 1px + 1px; }\n");
    let r = sasso(dir, ["--no-source-map", "a.scss:out/a.css", "b.scss:out/b.css"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.equal(r.stdout, "");
    // missing output dirs are created
    assert.equal(read(dir, "out/a.css"), GOOD_CSS());
    assert.equal(read(dir, "out/b.css"), "b {\n  w: 2px;\n}\n");
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "pairs_get_a_source_map_by_default" {
    let dir = scratch("pairs_map");
    write(dir, "src/a.scss", GOOD());
    let r = sasso(dir, ["src/a.scss:out/a.css"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.equal(read(dir, "out/a.css"), `${GOOD_CSS()}\n/*# sourceMappingURL=a.css.map */\n`);
    let map = read(dir, "out/a.css.map");
    // {map}
    assert.is_true(
        map.starts_with("{\"version\":3,\"sourceRoot\":\"\",\"sources\":[\"../src/a.scss\"]"),
    );
    // {map}
    assert.is_true(map.ends_with(",\"file\":\"a.css\"}"));
    // `--no-source-map` opts out: no footer, no sidecar.
    let r = sasso(dir, ["--no-source-map", "src/a.scss:out/b.css"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.equal(read(dir, "out/b.css"), GOOD_CSS());
    assert.is_true(!root.std.exists(root.std.path_join(dir, "out/b.css.map")));
    assert_dart_files_match(
        [root.std.Tuple2<string, string> { _0: "src/a.scss", _1: GOOD() }],
        ["src/a.scss:out/a.css"],
        ["out/a.css", "out/a.css.map"],
    );
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "directory_pair_mirrors_the_tree_and_skips_partials" {
    let dir = scratch("dirmode");
    write(dir, "src/a.scss", GOOD());
    write(dir, "src/_partial.scss", "$p: 1px;\n");
    write(dir, "src/sub/nested.scss", "@use \"../partial\";\nb { w: partial.$p; }\n");
    write(dir, "src/plain.sass", "c\n  d: e\n");
    write(dir, "src/raw.css", "f{g:h}\n");
    write(dir, "src/notes.txt", "ignored\n");
    let r = sasso(dir, ["--no-source-map", "src:out"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.equal(read(dir, "out/a.css"), GOOD_CSS());
    assert.equal(read(dir, "out/sub/nested.css"), "b {\n  w: 1px;\n}\n");
    // .sass compiles as indented syntax
    assert.equal(read(dir, "out/plain.css"), "c {\n  d: e;\n}\n");
    // .css compiles as plain CSS
    assert.equal(read(dir, "out/raw.css"), "f {\n  g: h;\n}\n");
    // partials are skipped
    assert.is_true(!root.std.exists(root.std.path_join(dir, "out/_partial.css")));
    assert.is_true(
        !root.std.exists(root.std.path_join(dir, "out/notes.css"))
            && !root.std.exists(root.std.path_join(dir, "out/notes.txt")),
    );
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "pairs_cannot_mix_with_positionals_or_stdin" {
    let dir = scratch("pairs_mix");
    write(dir, "a.scss", GOOD());
    let r = sasso(dir, ["a.scss:out.css", "a.scss"]);
    assert.equal(r.code, EXIT_USAGE());
    // {r.stderr}
    assert.is_true(r.stderr.includes("Positional and \":\" arguments may not both be used."));
    let r = run_bin(BIN(), dir, ["--stdin", "-:out.css"], "a{b:c}");
    assert.equal(r.code, EXIT_USAGE());
    // {r.stderr}
    assert.is_true(r.stderr.includes("--stdin may not be used with \":\" arguments."));
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

// ---------------------------------------------------------------------------
// Source-map flags on stdout, and `--embed-source-map`
// ---------------------------------------------------------------------------

test "stdout_source_map_flags_need_embed_source_map" {
    let dir = scratch("stdout_map");
    write(dir, "a.scss", GOOD());
    let r = sasso(dir, ["--source-map", "a.scss"]);
    assert.equal(r.code, EXIT_USAGE());
    // {r.stderr}
    assert.is_true(
        r.stderr.includes("When printing to stdout, --source-map requires --embed-source-map."),
    );
    let r = sasso(dir, ["--embed-sources", "a.scss"]);
    assert.equal(r.code, EXIT_USAGE());
    // {r.stderr}
    assert.is_true(
        r.stderr.includes("When printing to stdout, --embed-sources requires --embed-source-map."),
    );
    let r = sasso(dir, ["--embed-source-map", "--no-source-map", "a.scss"]);
    assert.equal(r.code, EXIT_USAGE());
    // {r.stderr}
    assert.is_true(r.stderr.includes("--embed-source-map isn't allowed with --no-source-map."));
    // dart's remaining combinations.
    let cases: root.std.Tuple2<string[], string>[] = [
        root.std.Tuple2<string[], string> {
            _0: ["--embed-sources", "--no-source-map", "a.scss", "o.css"],
            _1: "--embed-sources isn't allowed with --no-source-map.",
        },
        root.std.Tuple2<string[], string> {
            _0: ["--source-map-urls=absolute", "--no-source-map", "a.scss", "o.css"],
            _1: "--source-map-urls isn't allowed with --no-source-map.",
        },
        root.std.Tuple2<string[], string> {
            _0: ["--source-map-urls=absolute", "a.scss"],
            _1: "When printing to stdout, --source-map-urls requires --embed-source-map.",
        },
        root.std.Tuple2<string[], string> {
            _0: ["--source-map-urls=relative", "--embed-source-map", "a.scss"],
            _1: "--source-map-urls=relative isn't allowed when printing to stdout.",
        },
    ];
    for (let c in cases) {
        let args = c._0;
        let msg = c._1;
        let r = sasso(dir, args);
        // {args:?}: {r.stderr}
        assert.equal(r.code, EXIT_USAGE());
        // {args:?}: {r.stderr}
        assert.is_true(r.stderr.includes(msg));
    }
    // … while the explicit default is fine where a map is written.
    let r = sasso(dir, ["--source-map-urls=relative", "a.scss", "o.css"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "embedded_map_cannot_close_the_footer_comment" {
    // `--embed-sources` puts the source text into the data: URI; a `*/` in it
    // must not terminate the `/*# sourceMappingURL=… */` comment early.
    let dir = scratch("star_footer");
    write(dir, "in.scss", "/* end */ a { b: c }\n");
    let r = sasso(dir, ["--embed-source-map", "--embed-sources", "in.scss", "out.css"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    let css = read(dir, "out.css");
    // PORT: `css.rsplit(pat).next().unwrap()` — the text after the last `pat`.
    let footer = root.std.expect(root.std.last(css.split("/*# sourceMappingURL=")), "rsplit");
    let uri = root.std.expect(root.std.strip_suffix(footer, " */\n"), "footer closes once, at the very end");
    // the URI must not contain a comment terminator: {uri}
    assert.is_true(!uri.includes("*/"));
    // dart escapes `*/` as `%2A/`: {uri}
    assert.is_true(uri.includes("%2A/"));
    assert_dart_files_match(
        [root.std.Tuple2<string, string> { _0: "in.scss", _1: "/* end */ a { b: c }\n" }],
        ["--embed-source-map", "--embed-sources", "in.scss", "out.css"],
        ["out.css"],
    );
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "map_is_written_before_css" {
    // If the sidecar cannot be written, no CSS that points at it may appear.
    let dir = scratch("map_first");
    write(dir, "in.scss", GOOD());
    root.std.create_dir_all(root.std.path_join(dir, "out.css.map")); // a directory blocks the map
    let r = sasso(dir, ["in.scss", "out.css"]);
    // {r.stderr}
    assert.equal(r.code, EXIT_IO());
    // CSS must not be published without its map
    assert.is_true(!root.std.exists(root.std.path_join(dir, "out.css")));
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "embed_source_map_inlines_a_data_uri" {
    let dir = scratch("embed");
    write(dir, "src/a.scss", GOOD());
    // To a file: relative sources, a `file` field, and no sidecar.
    let r = sasso(dir, ["--embed-source-map", "src/a.scss:out/a.css"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    let css = read(dir, "out/a.css");
    let expected_prefix = `${GOOD_CSS()}\n/*# sourceMappingURL=data:application/json;charset=utf-8,%7B%22version%22:3,%22sourceRoot%22:%22%22,%22sources%22:%5B%22../src/a.scss%22%5D,%22names%22:%5B%5D,%22mappings%22:%22`;
    // {css}
    assert.is_true(css.starts_with(expected_prefix));
    // {css}
    assert.is_true(css.ends_with("%22,%22file%22:%22a.css%22%7D */\n"));
    // no sidecar when embedded
    assert.is_true(!root.std.exists(root.std.path_join(dir, "out/a.css.map")));
    // `--embed-sources` rides along inside the data URI.
    let r = sasso(dir, ["--embed-source-map", "--embed-sources", "src/a.scss:out/b.css"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    let css = read(dir, "out/b.css");
    // {css}
    assert.is_true(
        css.includes(
            "%22sourcesContent%22:%5B%22$c:%20red;%5Cna%20%7B%20color:%20$c;%20%7D%5Cn%22%5D",
        ),
    );
    // To stdout: absolute `file://` sources and no `file` field, like dart.
    let r = sasso(dir, ["--embed-source-map", "src/a.scss"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    // {r.stdout}
    assert.is_true(
        r.stdout.starts_with(
            `${GOOD_CSS()}\n/*# sourceMappingURL=data:application/json;charset=utf-8,`,
        ),
    );
    // {r.stdout}
    assert.is_true(r.stdout.includes("%22sources%22:%5B%22file:///"));
    // {r.stdout}
    assert.is_true(!r.stdout.includes("%22file%22"));
    // {r.stdout}
    assert.is_true(r.stdout.ends_with("%7D */\n"));
    assert_dart_files_match(
        [root.std.Tuple2<string, string> { _0: "src/a.scss", _1: GOOD() }],
        ["--embed-source-map", "--embed-sources", "src/a.scss:out/a.css"],
        ["out/a.css"],
    );
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

// ---------------------------------------------------------------------------
// Error handling: error CSS, exit codes, --stop-on-error
// ---------------------------------------------------------------------------

/// dart's error stylesheet for `BAD` compiled from `in.scss` (Unicode glyphs
/// in `content`, ASCII glyphs in the comment).
function BAD_ERROR_CSS() -> string {
    "/* Error: Undefined variable.\n *   ,\n * 1 | a { b: $x }\n *   |        ^^\n *   '\n *   in.scss 1:8  root stylesheet */\n\nbody::before {\n  font-family: \"Source Code Pro\", \"SF Mono\", Monaco, Inconsolata, \"Fira Mono\",\n      \"Droid Sans Mono\", monospace, monospace;\n  white-space: pre;\n  display: block;\n  padding: 1em;\n  margin-bottom: 1em;\n  border-bottom: 2px solid black;\n  content: \"Error: Undefined variable.\\a   \\2577 \\a 1 \\2502  a { b: $x }\\a   \\2502         ^^\\a   \\2575 \\a   in.scss 1:8  root stylesheet\";\n}\n"
}

test "error_css_is_written_for_file_output_by_default" {
    let dir = scratch("errcss");
    write(dir, "in.scss", BAD());
    let r = sasso(dir, ["--no-source-map", "in.scss", "out.css"]);
    assert.equal(r.code, EXIT_COMPILE());
    // {r.stderr}
    assert.is_true(r.stderr.starts_with("Error: Undefined variable.\n"));
    assert.equal(read(dir, "out.css"), BAD_ERROR_CSS());
    // Non-ASCII in the message is escaped in `content` (dart: `\e9 `), and the
    // comment keeps it raw.
    write(dir, "uni.scss", "a { b: $é }\n");
    let r = sasso(dir, ["--no-source-map", "--style=compressed", "uni.scss", "uni.css"]);
    assert.equal(r.code, EXIT_COMPILE());
    let css = read(dir, "uni.css");
    // {css}
    assert.is_true(css.includes(" * 1 | a { b: $é }\n"));
    // {css}
    assert.is_true(css.includes("a { b: $\\e9  }\\a "));
    // compressed style still writes the expanded error sheet: {css}
    assert.is_true(css.starts_with("/* Error:"));
    // `--no-unicode` switches the `content` glyphs to ASCII too.
    let r = sasso(dir, ["--no-source-map", "--no-unicode", "in.scss", "ascii.css"]);
    assert.equal(r.code, EXIT_COMPILE());
    assert.is_true(
        read(dir, "ascii.css").includes(
            "content: \"Error: Undefined variable.\\a   ,\\a 1 | a { b: $x }\\a   |        ^^\\a   '\\a   in.scss 1:8  root stylesheet\";",
        ),
    );
    assert_dart_files_match(
        [root.std.Tuple2<string, string> { _0: "in.scss", _1: BAD() }],
        ["--no-source-map", "in.scss", "out.css"],
        ["out.css"],
    );
    assert_dart_files_match(
        [root.std.Tuple2<string, string> { _0: "in.scss", _1: BAD() }],
        ["--no-source-map", "--no-unicode", "in.scss", "out.css"],
        ["out.css"],
    );
    // `*/` inside the message must not close the comment (dart: U+2215).
    write(dir, "star.scss", "@error \"a */ b\";\n");
    let r = sasso(dir, ["--no-source-map", "star.scss", "star.css"]);
    assert.equal(r.code, EXIT_COMPILE());
    let css = read(dir, "star.css");
    // PORT: `\u{2215}` (DIVISION SLASH) built with `chr_unchecked`.
    // {css}
    assert.is_true(css.includes("/* Error: \"a *" + root.std.chr_unchecked(0x2215) + " b\"\n"));
    // {css}
    assert.is_true(css.includes("content: \"Error: \\\"a */ b\\\"\\a "));
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "no_error_css_and_stdout_errors_write_nothing" {
    let dir = scratch("noerrcss");
    write(dir, "in.scss", BAD());
    let r = sasso(dir, ["--no-source-map", "--no-error-css", "in.scss", "out.css"]);
    assert.equal(r.code, EXIT_COMPILE());
    // --no-error-css writes no file
    assert.is_true(!root.std.exists(root.std.path_join(dir, "out.css")));
    // To stdout the default is off …
    let r = sasso(dir, ["in.scss"]);
    assert.equal(r.code, EXIT_COMPILE());
    assert.equal(r.stdout, "");
    // … unless asked for explicitly.
    let r = sasso(dir, ["--error-css", "in.scss"]);
    assert.equal(r.code, EXIT_COMPILE());
    assert.equal(r.stdout, BAD_ERROR_CSS());
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "dependency_provenance_is_per_compilation" {
    // The same file can be a dependency of one entry (reached through `-I lp`)
    // and not of another (reached relatively), even within one process: dart
    // decides per compilation, so with `-j 1` the second unit must not inherit
    // the first unit's classification.
    let dir = scratch("deps_per_unit");
    write(dir, "lp/_dep.scss", "@import \"x\";\n");
    write(dir, "lp/_x.scss", "q { r: 1; }\n");
    write(dir, "a.scss", "@import \"dep\";\n");
    write(dir, "b.scss", "@use \"lp/dep\";\n");
    let r = sasso(
        dir,
        [
            "-j",
            "1",
            "--quiet-deps",
            "--no-source-map",
            "-I",
            "lp",
            "a.scss:out/a.css",
            "b.scss:out/b.css",
        ],
    );
    // {r.stderr}
    assert.equal(r.code, 0);
    // a: its own @import warns, the dependency's @import is silenced.
    // b: `lp/dep` is relative, so its @import "x" warns.
    // PORT: `s.matches(p).count()` → `s.split(p).length() - 1`.
    // {r.stderr}
    assert.equal(r.stderr.split("DEPRECATION WARNING [import]").length() - 1, 2);
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

// PORT: `#[cfg(unix)]` — this port targets macOS/Linux, so the test is kept.
test "directory_pair_survives_a_symlink_cycle" {
    let dir = scratch("symlink_cycle");
    write(dir, "src/a.scss", GOOD());
    write(dir, "src/sub/b.scss", "b { c: d }\n");
    baml.fs.symlink("..", root.std.path_join(dir, "src/sub/up")) catch (e) {
        let io: baml.errors.Io => root.std.panic(`symlink: ${io.message}`)
    };
    let r = sasso(dir, ["--no-source-map", "src:out"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.equal(read(dir, "out/a.css"), GOOD_CSS());
    assert.equal(read(dir, "out/sub/b.css"), "b {\n  c: d;\n}\n");
    // the cycle is visited once, not mirrored
    assert.is_true(!root.std.exists(root.std.path_join(dir, "out/sub/up")));
    // Two names for one directory: the first in sorted order is mirrored, the
    // other skipped — the same way every run, whatever `read_dir` yields.
    baml.fs.symlink("sub", root.std.path_join(dir, "src/zz-alias")) catch (e) {
        let io: baml.errors.Io => root.std.panic(`symlink: ${io.message}`)
    };
    for (let _i in root.std.range(0, 2)) {
        let _ = baml.fs.remove_dir_all(root.std.path_join(dir, "out")) catch (e) {
            let _io: baml.errors.Io => null
        };
        let r = sasso(dir, ["--no-source-map", "src:out"]);
        // {r.stderr}
        assert.equal(r.code, 0);
        // `sub` sorts before `zz-alias` and wins
        assert.is_true(root.std.exists(root.std.path_join(dir, "out/sub/b.css")));
        assert.is_true(!root.std.exists(root.std.path_join(dir, "out/zz-alias")));
    }
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "no_css_has_no_side_effects_on_failure_either" {
    let dir = scratch("no_css_fail");
    write(dir, "bad.scss", BAD());
    write(dir, "out.css", "old { css: yes }\n");
    let r = sasso(dir, ["--no-css", "bad.scss:out.css"]);
    assert.equal(r.code, EXIT_COMPILE());
    // {r.stderr}
    assert.is_true(r.stderr.includes("Undefined variable"));
    // neither replaced nor removed
    assert.equal(read(dir, "out.css"), "old { css: yes }\n");
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "error_without_error_css_removes_a_stale_output" {
    let dir = scratch("stale");
    write(dir, "bad.scss", BAD());
    write(dir, "out.css", "old { css: yes }\n");
    write(dir, "out.css.map", "old map");
    // dart deletes the stale CSS (not the map) when error CSS is off …
    let r = sasso(dir, ["--no-error-css", "--no-source-map", "bad.scss", "out.css"]);
    assert.equal(r.code, EXIT_COMPILE());
    // stale CSS must not survive a failed build
    assert.is_true(!root.std.exists(root.std.path_join(dir, "out.css")));
    // the map is left alone
    assert.is_true(root.std.exists(root.std.path_join(dir, "out.css.map")));
    // … and overwrites it with the error stylesheet when it is on.
    write(dir, "out.css", "old { css: yes }\n");
    let r = sasso(dir, ["--no-source-map", "bad.scss", "out.css"]);
    assert.equal(r.code, EXIT_COMPILE());
    assert.is_true(read(dir, "out.css").starts_with("/* Error: Undefined variable."));
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "invalid_utf8_is_a_compile_error_with_error_css" {
    let dir = scratch("utf8");
    root.std.write_file_bytes(root.std.path_join(dir, "bad.scss"), b"a { b: c }\n\xff\xfe\n");
    let r = sasso(dir, ["--no-source-map", "bad.scss", "out.css"]);
    assert.equal(r.code, EXIT_COMPILE());
    // {r.stderr}
    assert.is_true(r.stderr.starts_with("Error: Invalid UTF-8."));
    let css = read(dir, "out.css");
    // {css}
    assert.is_true(css.starts_with("/* Error: Invalid UTF-8. */\n\nbody::before {"));
    // {css}
    assert.is_true(css.includes("content: \"Error: Invalid UTF-8.\";"));
    // Without error CSS a stale output goes away, like any compile error.
    let r = sasso(dir, ["--no-error-css", "--no-source-map", "bad.scss", "out.css"]);
    assert.equal(r.code, EXIT_COMPILE());
    assert.is_true(!root.std.exists(root.std.path_join(dir, "out.css")));
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "missing_input_exits_66" {
    let dir = scratch("missing");
    let r = sasso(dir, ["nope.scss"]);
    assert.equal(r.code, EXIT_IO());
    assert.equal(r.stderr, "Error reading nope.scss: Cannot open file.\n");
    let r = sasso(dir, ["nope.scss:out.css"]);
    assert.equal(r.code, EXIT_IO());
    assert.is_true(!root.std.exists(root.std.path_join(dir, "out.css")));
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "stop_on_error_skips_the_rest_but_default_continues" {
    let dir = scratch("stop");
    write(dir, "bad.scss", BAD());
    write(dir, "good.scss", GOOD());
    // Default: every pair is attempted, exit 65.
    let r = sasso(dir, ["--no-source-map", "--no-error-css", "bad.scss:out/bad.css", "good.scss:out/good.css"]);
    assert.equal(r.code, EXIT_COMPILE());
    assert.is_true(!root.std.exists(root.std.path_join(dir, "out/bad.css")));
    assert.equal(read(dir, "out/good.css"), GOOD_CSS());
    // `--stop-on-error` (with one worker, so "the rest" is deterministic).
    let _ = baml.fs.remove_dir_all(root.std.path_join(dir, "out")) catch (e) {
        let _io: baml.errors.Io => null
    };
    let r = sasso(
        dir,
        [
            "-j",
            "1",
            "--no-source-map",
            "--no-error-css",
            "--stop-on-error",
            "bad.scss:out/bad.css",
            "good.scss:out/good.css",
        ],
    );
    assert.equal(r.code, EXIT_COMPILE());
    // later units are not started after a failure
    assert.is_true(!root.std.exists(root.std.path_join(dir, "out/good.css")));
    // {r.stderr}
    assert.is_true(r.stderr.includes("Undefined variable"));
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

// ---------------------------------------------------------------------------
// Parallelism
// ---------------------------------------------------------------------------

test "parallel_pairs_match_sequential_and_report_in_order" {
    let dir = scratch("parallel");
    let pairs: string[] = [];
    for (let i in root.std.range(0, 24)) {
        // Each file warns, so stderr ordering is observable too.
        write(
            dir,
            `in/f${root.std.zero_pad(i, 2)}.scss`,
            `@warn "w${root.std.zero_pad(i, 2)}";\n$n: ${i};\n.f${root.std.zero_pad(i, 2)} { w: $n * 1px; }\n`,
        );
        pairs.push(`in/f${root.std.zero_pad(i, 2)}.scss:par/f${root.std.zero_pad(i, 2)}.css`);
    }
    // An explicit worker count: on a single-core runner the default would be
    // 1 and `compile_all` would take its sequential path, leaving the
    // scheduler and the ordered result buffering untested.
    let args: string[] = ["-j", "8", "--no-source-map"].concat(pairs);
    let par = sasso(dir, args);
    // {par.stderr}
    assert.equal(par.code, 0);
    let seq_pairs: string[] = pairs.map((p) -> {
        p.replace_all(":par/", ":seq/")
    });
    let seq_args = ["-j", "1", "--no-source-map"];
    root.std.extend(seq_args, seq_pairs);
    let seq = sasso(dir, seq_args);
    // {seq.stderr}
    assert.equal(seq.code, 0);
    for (let i in root.std.range(0, 24)) {
        assert.equal(
            read(dir, `par/f${root.std.zero_pad(i, 2)}.css`),
            read(dir, `seq/f${root.std.zero_pad(i, 2)}.css`),
        );
        assert.equal(
            read(dir, `par/f${root.std.zero_pad(i, 2)}.css`),
            `.f${root.std.zero_pad(i, 2)} {\n  w: ${i}px;\n}\n`,
        );
    }
    // Warnings come out in command-line order regardless of which worker ran what.
    let order: string[] = par.stderr.lines().filter((l) -> {
        l.starts_with("WARNING: w")
    });
    let expected: string[] = root.std.range(0, 24).map((i) -> {
        `WARNING: w${root.std.zero_pad(i, 2)}`
    });
    assert.equal(order, expected);
    assert.equal(par.stderr, seq.stderr);
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

// ---------------------------------------------------------------------------
// Warnings: --quiet, --quiet-deps
// ---------------------------------------------------------------------------

test "quiet_silences_warnings_but_not_errors" {
    let dir = scratch("quiet");
    write(dir, "w.scss", "@warn \"loud\";\n@debug \"dbg\";\n@import \"dep\";\n");
    write(dir, "_dep.scss", "a { b: c }\n");
    let r = sasso(dir, ["w.scss"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    // {r.stderr}
    assert.is_true(
        r.stderr.includes("WARNING: loud")
            && r.stderr.includes("dbg")
            && r.stderr.includes("DEPRECATION WARNING [import]"),
    );
    let r = sasso(dir, ["-q", "w.scss"]);
    assert.equal(r.code, 0);
    // --quiet drops every warning
    assert.equal(r.stderr, "");
    assert.equal(r.stdout, "a {\n  b: c;\n}\n");
    write(dir, "bad.scss", BAD());
    let r = sasso(dir, ["--quiet", "bad.scss"]);
    assert.equal(r.code, EXIT_COMPILE());
    // errors still print under --quiet: {r.stderr}
    assert.is_true(r.stderr.includes("Error: Undefined variable."));
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "quiet_deps_silences_deprecations_from_load_path_files_only" {
    let dir = scratch("quiet_deps");
    // Entry: an @import (deprecation) of a load-path dependency that itself
    // has an @import (deprecation) and a @warn.
    write(dir, "entry.scss", "@import \"dep\";\n@warn \"from entry\";\n");
    write(dir, "lp/_dep.scss", "@import \"dep2\";\n@warn \"from dep\";\n");
    write(dir, "lp/_dep2.scss", "e { f: 2; }\n");
    let all = sasso(dir, ["-I", "lp", "entry.scss"]);
    // {all.stderr}
    assert.equal(all.code, 0);
    // {all.stderr}
    assert.equal(all.stderr.split("DEPRECATION WARNING [import]").length() - 1, 2);
    let quiet_deps = sasso(dir, ["--quiet-deps", "-I", "lp", "entry.scss"]);
    // {quiet_deps.stderr}
    assert.equal(quiet_deps.code, 0);
    // The entry's own deprecation stays; the dependency's goes; @warn from
    // both stays (dart: only COMPILER warnings from dependencies are silenced).
    // {quiet_deps.stderr}
    assert.equal(quiet_deps.stderr.split("DEPRECATION WARNING [import]").length() - 1, 1);
    // the remaining deprecation is the entry's: {quiet_deps.stderr}
    assert.is_true(quiet_deps.stderr.includes("entry.scss 1:9"));
    // {quiet_deps.stderr}
    assert.is_true(quiet_deps.stderr.includes("WARNING: from dep"));
    // {quiet_deps.stderr}
    assert.is_true(quiet_deps.stderr.includes("WARNING: from entry"));
    // dart's rule is about how a file was RESOLVED, not where it lives: a
    // relative `@use "lp/…"` from the entry is not a dependency even though
    // the file sits in the load-path directory, so its deprecation prints.
    write(dir, "rel.scss", "@use \"lp/rel-dep\";\n");
    write(dir, "lp/_rel-dep.scss", "@import \"dep2\";\n");
    let rel = sasso(dir, ["--quiet-deps", "-I", "lp", "rel.scss"]);
    // {rel.stderr}
    assert.equal(rel.code, 0);
    // a relatively-resolved file is not a dependency: {rel.stderr}
    assert.equal(rel.stderr.split("DEPRECATION WARNING [import]").length() - 1, 1);
    // Nor is the entry itself, even inside the load path.
    write(dir, "lp/main.scss", "@import \"dep2\";\n");
    let inside = sasso(dir, ["--quiet-deps", "-I", "lp", "lp/main.scss"]);
    // {inside.stderr}
    assert.equal(inside.code, 0);
    // {inside.stderr}
    assert.equal(inside.stderr.split("DEPRECATION WARNING [import]").length() - 1, 1);
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

// ---------------------------------------------------------------------------
// Misc flags
// ---------------------------------------------------------------------------

test "quiet_deps_leaves_no_repetition_footer" {
    // The compiler caps repeated deprecations at five per id and reports the
    // rest as "N repetitive deprecation warnings omitted". Under --quiet-deps
    // a dependency's deprecations are dropped BEFORE that count (dart applies
    // quietDeps ahead of its repetition logger), so nothing surfaces.
    let dir = scratch("quiet_deps_footer");
    let dep = "";
    for (let i in root.std.range(1, 8 + 1)) {
        dep = dep + `@import "leaf${i}";\n`;
        write(dir, `lp/_leaf${i}.scss`, `l${i} { m: ${i}; }\n`);
    }
    write(dir, "lp/_dep.scss", dep);
    write(dir, "entry.scss", "@use \"dep\";\n");
    let loud = sasso(dir, ["--no-source-map", "-I", "lp", "entry.scss"]);
    // {loud.stderr}
    assert.equal(loud.code, 0);
    // {loud.stderr}
    assert.is_true(loud.stderr.includes("repetitive deprecation warnings omitted"));
    let quiet = sasso(dir, ["--no-source-map", "--quiet-deps", "-I", "lp", "entry.scss"]);
    // {quiet.stderr}
    assert.equal(quiet.code, 0);
    // no deprecations and no footer
    assert.equal(quiet.stderr, "");
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "compat_flags_and_no_css" {
    let dir = scratch("misc");
    write(dir, "u.scss", "a { content: \"é\" }\n");
    let r = sasso(dir, ["--no-color", "-c", "u.scss"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    // {r.stdout}
    assert.is_true(r.stdout.starts_with("@charset \"UTF-8\";\n"));
    let r = sasso(dir, ["--no-charset", "u.scss"]);
    assert.equal(r.code, 0);
    // --no-charset drops the @charset: {r.stdout}
    assert.is_true(r.stdout.starts_with("a {"));
    let r = sasso(dir, ["--no-css", "u.scss"]);
    assert.equal(r.code, 0);
    // --no-css compiles but prints nothing
    assert.equal(r.stdout, "");
    let r = sasso(dir, ["--no-css", "u.scss", "u.css"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    // --no-css writes no files either
    assert.is_true(
        !root.std.exists(root.std.path_join(dir, "u.css"))
            && !root.std.exists(root.std.path_join(dir, "u.css.map")),
    );
    let r = sasso(dir, ["--no-css", "u.scss:pair.css"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.is_true(!root.std.exists(root.std.path_join(dir, "pair.css")));
    let r = sasso(dir, ["--no-css", "--loop", "2", "u.scss"]);
    assert.equal(r.code, 0);
    assert.equal(r.stdout, "");
    // {r.stderr}
    assert.is_true(r.stderr.includes("2 compiles in"));
    let r = sasso(dir, ["--loop", "2", "u.scss:out.css"]);
    // --loop is stdout-only
    assert.equal(r.code, EXIT_USAGE());
    let r = sasso(dir, ["--loop", "2", "--embed-source-map", "u.scss"]);
    // --loop has no source-map mode
    assert.equal(r.code, EXIT_USAGE());
    // {r.stderr}
    assert.is_true(r.stderr.includes("--loop does not generate source maps"));
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "pair_with_a_second_colon_is_a_usage_error" {
    let dir = scratch("two_colons");
    write(dir, "a.scss", GOOD());
    let r = sasso(dir, ["--no-source-map", "a.scss:out.css:wut"]);
    assert.equal(r.code, EXIT_USAGE());
    // {r.stderr}
    assert.is_true(r.stderr.includes("\"a.scss:out.css:wut\" may only contain one \":\"."));
    assert.is_true(!root.std.exists(root.std.path_join(dir, "out.css:wut")));
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "bare_directory_positional_compiles_in_place" {
    // dart: `sass dir` is `dir:dir`; a directory with an output, or as the
    // output, "may not be a positional arg".
    let dir = scratch("dir_positional");
    write(dir, "src/a.scss", GOOD());
    write(dir, "src/sub/b.scss", "b { c: d }\n");
    write(dir, "src/_p.scss", "$x: 1;\n");
    let r = sasso(dir, ["--no-source-map", "src"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.equal(r.stdout, "");
    assert.equal(read(dir, "src/a.css"), GOOD_CSS());
    assert.equal(read(dir, "src/sub/b.css"), "b {\n  c: d;\n}\n");
    assert.is_true(!root.std.exists(root.std.path_join(dir, "src/_p.css")));
    let r = sasso(dir, ["--no-source-map", "src", "out"]);
    assert.equal(r.code, EXIT_USAGE());
    // {r.stderr}
    assert.is_true(r.stderr.includes("Directory \"src\" may not be a positional arg."));
    root.std.create_dir_all(root.std.path_join(dir, "od"));
    let r = sasso(dir, ["--no-source-map", "src/a.scss", "od"]);
    assert.equal(r.code, EXIT_USAGE());
    // {r.stderr}
    assert.is_true(r.stderr.includes("Directory \"od\" may not be a positional arg."));
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "diagnostics_of_consecutive_units_are_separated_by_a_blank_line" {
    let dir = scratch("separators");
    // Two unreadable inputs: dart prints the two lines with a blank line between.
    let r = sasso(dir, ["-j", "1", "--no-source-map", "n1.scss:o1.css", "n2.scss:o2.css"]);
    assert.equal(r.code, EXIT_IO());
    assert.equal(
        r.stderr,
        "Error reading n1.scss: Cannot open file.\n\nError reading n2.scss: Cannot open file.\n",
    );
    // Two compile errors: one blank line between, none trailing.
    write(dir, "bad1.scss", BAD());
    write(dir, "bad2.scss", "c { d: $y }\n");
    let r = sasso(dir, ["-j", "1", "--no-source-map", "--no-error-css", "bad1.scss:b1.css", "bad2.scss:b2.css"]);
    assert.equal(r.code, EXIT_COMPILE());
    // {r.stderr}
    assert.equal(r.stderr.split("\n\nError: Undefined variable.").length() - 1, 1);
    // {r.stderr}
    assert.is_true(r.stderr.ends_with("root stylesheet\n") && !r.stderr.ends_with("\n\n"));
    // A warning block already ends in a blank line: no extra one is added.
    write(dir, "warn.scss", "@warn \"hi\";\nz { y: 1 }\n");
    let r = sasso(dir, ["-j", "1", "--no-source-map", "--no-error-css", "warn.scss:w.css", "bad1.scss:b1.css"]);
    assert.equal(r.code, EXIT_COMPILE());
    // {r.stderr}
    assert.is_true(r.stderr.includes("root stylesheet\n\nError: Undefined variable."));
    // {r.stderr}
    assert.is_true(!r.stderr.includes("\n\n\n"));
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "invalid_utf8_on_stdin_fails_like_a_file" {
    // dart crashes on invalid UTF-8 from stdin (exit 255, nothing written);
    // sasso treats it as the compile error it is, with the same error-CSS and
    // stale-output handling a file input gets.
    let dir = scratch("stdin_utf8");
    let bad: uint8array = b"a { b: c }\n\xff\xfe\n";
    let r = run_bin_bytes(BIN(), dir, ["--no-source-map", "--stdin", "out.css"], bad);
    assert.equal(r.code, EXIT_COMPILE());
    assert.equal(r.stderr, "Error: Invalid UTF-8.\n");
    // error stylesheet for a file target
    assert.is_true(read(dir, "out.css").starts_with("/* Error: Invalid UTF-8. */"));
    write(dir, "stale.css", "old { css: yes }\n");
    let r = run_bin_bytes(BIN(), dir, ["--no-source-map", "--no-error-css", "-:stale.css"], bad);
    assert.equal(r.code, EXIT_COMPILE());
    // stale CSS removed like any compile error
    assert.is_true(!root.std.exists(root.std.path_join(dir, "stale.css")));
    let r = run_bin_bytes(BIN(), dir, ["--no-source-map", "-"], bad);
    assert.equal(r.code, EXIT_COMPILE());
    assert.equal(r.stdout, "");
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "bare_directory_is_file_output_for_flag_validation" {
    // `sasso --source-map dir` etc. are file-output invocations (dart accepts
    // them all); `--loop dir` is not stdout-only and is rejected.
    let dir = scratch("dir_flags");
    write(dir, "src/a.scss", GOOD());
    let all_args: string[][] = [
        ["--source-map", "src"],
        ["--embed-sources", "src"],
        ["--source-map-urls=absolute", "src"],
        ["--embed-source-map", "src"],
    ];
    for (let args in all_args) {
        let _ = root.std.remove_file(root.std.path_join(dir, "src/a.css")) catch (e) {
            let _io: baml.errors.Io => null
        };
        let _ = root.std.remove_file(root.std.path_join(dir, "src/a.css.map")) catch (e) {
            let _io: baml.errors.Io => null
        };
        let r = sasso(dir, args);
        // {args:?}: {r.stderr}
        assert.equal(r.code, 0);
        // {args:?}
        assert.is_true(read(dir, "src/a.css").includes("sourceMappingURL="));
    }
    let r = sasso(dir, ["--loop", "2", "src"]);
    // {r.stderr}
    assert.equal(r.code, EXIT_USAGE());
    // {r.stderr}
    assert.is_true(r.stderr.includes("--loop compiles to stdout only"));
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "double_dash_ends_option_parsing" {
    // dart's argument parser honours `--`: what follows is operands, so an
    // input or output whose name starts with `-` can be named. Pairs and the
    // stdin `-` keep their meaning after it.
    let dir = scratch("double_dash");
    write(dir, "--theme.scss", GOOD());
    write(dir, "-dash.scss", "q { r: 1 }\n");
    let r = sasso(dir, ["--no-source-map", "--", "--theme.scss"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.equal(r.stdout, GOOD_CSS());
    let r = sasso(dir, ["--no-source-map", "--", "-dash.scss:out.css"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.equal(read(dir, "out.css"), "q {\n  r: 1;\n}\n");
    let r = run_bin(BIN(), dir, ["--no-source-map", "--", "-"], "x { y: z }\n");
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.equal(r.stdout, "x {\n  y: z;\n}\n");
    // An option-looking token after `--` is an operand: here the output file.
    let r = sasso(dir, ["--no-source-map", "--", "--theme.scss", "--out.css"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.equal(read(dir, "--out.css"), GOOD_CSS());
    // Without `--` such a name is still an unknown option.
    let r = sasso(dir, ["--no-source-map", "--theme.scss"]);
    assert.equal(r.code, EXIT_USAGE());
    // {r.stderr}
    assert.is_true(r.stderr.includes("unknown option --theme.scss"));
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "source_map_file_and_footer_are_url_encoded" {
    // The map's `file` and the footer's `sourceMappingURL` are URLs: dart
    // percent-encodes the output basename (space, `#`, `%`).
    let dir = scratch("url_encoded_names");
    write(dir, "in.scss", GOOD());
    let r = sasso(dir, ["in.scss", "out file#1.css"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    let css = read(dir, "out file#1.css");
    // {css}
    assert.is_true(css.ends_with("\n\n/*# sourceMappingURL=out%20file%231.css.map */\n"));
    let map = read(dir, "out file#1.css.map");
    // {map}
    assert.is_true(map.ends_with(",\"file\":\"out%20file%231.css\"}"));
    let r = sasso(dir, ["in.scss", "out%20x.css"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    // a literal % is encoded
    assert.is_true(read(dir, "out%20x.css").includes("sourceMappingURL=out%2520x.css.map */"));
    assert.is_true(read(dir, "out%20x.css.map").ends_with(",\"file\":\"out%2520x.css\"}"));
    assert_dart_files_match(
        [root.std.Tuple2<string, string> { _0: "in.scss", _1: GOOD() }],
        ["in.scss", "out file#1.css"],
        ["out file#1.css", "out file#1.css.map"],
    );
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "empty_stylesheet_to_a_file_is_one_newline" {
    // dart always terminates a CSS file with one newline, an empty stylesheet
    // included; stdout gets nothing for empty output.
    let dir = scratch("empty_file");
    write(dir, "empty.scss", "");
    write(dir, "comment.scss", "// nothing to emit\n");
    let r = sasso(dir, ["--no-source-map", "empty.scss", "e1.css"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.equal(read(dir, "e1.css"), "\n");
    let r = sasso(dir, ["--no-source-map", "--style=compressed", "comment.scss:e2.css"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.equal(read(dir, "e2.css"), "\n");
    let r = sasso(dir, ["empty.scss", "e3.css"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.equal(read(dir, "e3.css"), "\n\n/*# sourceMappingURL=e3.css.map */\n");
    let r = sasso(dir, ["--no-source-map", "empty.scss"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    // stdout stays empty for empty output
    assert.equal(r.stdout, "");
    assert_dart_files_match(
        [root.std.Tuple2<string, string> { _0: "empty.scss", _1: "" }],
        ["--no-source-map", "empty.scss", "e1.css"],
        ["e1.css"],
    );
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "equivalent_source_spellings_coalesce_to_the_later_destination" {
    // dart keeps sources in a path-keyed map: `a.scss` and `./a.scss` are one
    // source, compiled once, to the destination named last. An exact repeat
    // is still the `Duplicate source` error.
    let dir = scratch("coalesce");
    write(dir, "a.scss", GOOD());
    root.std.create_dir_all(root.std.path_join(dir, "sub"));
    let r = sasso(dir, ["--no-source-map", "a.scss:o1.css", "./a.scss:o2.css", "sub/../a.scss:o3.css"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    // earlier destinations are not written
    assert.is_true(
        !root.std.exists(root.std.path_join(dir, "o1.css"))
            && !root.std.exists(root.std.path_join(dir, "o2.css")),
    );
    assert.equal(read(dir, "o3.css"), GOOD_CSS());
    let r = sasso(dir, ["--no-source-map", "a.scss:o4.css", "a.scss:o5.css"]);
    assert.equal(r.code, EXIT_USAGE());
    // {r.stderr}
    assert.is_true(r.stderr.includes("Duplicate source \"a.scss\"."));
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "extensions_are_matched_case_sensitively_like_dart" {
    // dart's `Syntax.forPath` and `_isEntrypoint` look at exact lowercase
    // suffixes: `input.CSS` parses as SCSS (Sass constructs allowed), and
    // directory mode skips `UPPER.SCSS`.
    let dir = scratch("ext_case");
    write(dir, "input.CSS", GOOD());
    let r = sasso(dir, ["--no-source-map", "input.CSS"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.equal(r.stdout, GOOD_CSS());
    write(dir, "input.SASS", "a\n  b: c\n");
    let r = sasso(dir, ["--no-source-map", "input.SASS"]);
    // indented content parsed as SCSS fails, as in dart: {r.stderr}
    assert.equal(r.code, EXIT_COMPILE());
    write(dir, "dir/UPPER.SCSS", GOOD());
    write(dir, "dir/Mixed.Sass", "q\n  r: 1\n");
    write(dir, "dir/plain.CSS", "x { y: z }\n");
    write(dir, "dir/ok.scss", GOOD());
    let r = sasso(dir, ["--no-source-map", "dir:out"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    let produced: string[] = root.std.read_dir_names(root.std.path_join(dir, "out"));
    root.std.sort_strings(produced);
    assert.equal(produced, ["ok.css"]);
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "directory_expanded_files_coalesce_with_explicit_pairs" {
    // dart puts expanded files and explicit pairs in one path-keyed map: a
    // file named both ways compiles once, to the destination named last;
    // two spellings of one directory coalesce too; an exact repeat errors.
    let dir = scratch("dir_coalesce");
    write(dir, "src/a.scss", GOOD());
    write(dir, "src/b.scss", "q { r: 1 }\n");
    let r = sasso(dir, ["--no-source-map", "src:out1", "src/a.scss:out2.css"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    // a goes to the later destination only
    assert.is_true(!root.std.exists(root.std.path_join(dir, "out1/a.css")));
    assert.equal(read(dir, "out2.css"), GOOD_CSS());
    assert.is_true(root.std.exists(root.std.path_join(dir, "out1/b.css")));
    let _ = baml.fs.remove_dir_all(root.std.path_join(dir, "out1")) catch (e) {
        let _io: baml.errors.Io => null
    };
    let _ = root.std.remove_file(root.std.path_join(dir, "out2.css")) catch (e) {
        let _io: baml.errors.Io => null
    };
    let r = sasso(dir, ["--no-source-map", "src/a.scss:out2.css", "src:out1"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    // the directory expansion came later and wins
    assert.is_true(!root.std.exists(root.std.path_join(dir, "out2.css")));
    assert.equal(read(dir, "out1/a.css"), GOOD_CSS());
    let r = sasso(dir, ["--no-source-map", "src:out3", "./src:out4"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.is_true(
        !root.std.exists(root.std.path_join(dir, "out3"))
            && root.std.exists(root.std.path_join(dir, "out4/a.css")),
    );
    let r = sasso(dir, ["--no-source-map", "src:out5", "src:out6"]);
    assert.equal(r.code, EXIT_USAGE());
    // {r.stderr}
    assert.is_true(r.stderr.includes("Duplicate source \"src\"."));
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "directory_mode_skips_css_whose_destination_is_itself" {
    // dart: a `.css` inside an in-place directory compile (`sasso dir`, or
    // `dir:dir`) would only be rewritten onto itself, so it is skipped; the
    // same file compiled to ANOTHER directory is processed like any input.
    let dir = scratch("self_css");
    write(dir, "src/plain.css", "p{q:2}\n");
    write(dir, "src/x.scss", "x { y: z }\n");
    let r = sasso(dir, ["--no-source-map", "src"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    // left untouched
    assert.equal(read(dir, "src/plain.css"), "p{q:2}\n");
    assert.equal(read(dir, "src/x.css"), "x {\n  y: z;\n}\n");
    let r = sasso(dir, ["--no-source-map", "src:src"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.equal(read(dir, "src/plain.css"), "p{q:2}\n");
    let r = sasso(dir, ["--no-source-map", "src:out"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    // to another directory it compiles
    assert.equal(read(dir, "out/plain.css"), "p {\n  q: 2;\n}\n");
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "directory_mode_skips_sources_inside_a_nested_output" {
    // dart-sass 1.104.1: a many-to-many compile skips every source file that
    // lies INSIDE the output directory when that directory is nested in the
    // source tree — otherwise `.:css` run twice mirrors `css/` into
    // `css/css/`. Measured against dart-sass 1.104.1.
    let dir = scratch("nested_out");
    write(dir, "one.scss", "a { b: c }\n");
    write(dir, "css/stale.scss", "d { e: f }\n");
    write(dir, "css/deep/deeper.scss", "g { h: i }\n");
    let r = sasso(dir, ["--no-source-map", ".:css"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.equal(read(dir, "css/one.css"), "a {\n  b: c;\n}\n");
    // the output tree was mirrored into itself
    assert.is_true(!root.std.exists(root.std.path_join(dir, "css/css")));
    // The DESTINATION is what counts, not an intermediate directory: with the
    // output one level deeper, `css/stale.scss` is still a source.
    let r = sasso(dir, ["--no-source-map", ".:css/deep"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.equal(read(dir, "css/deep/css/stale.css"), "d {\n  e: f;\n}\n");
    // files under the destination are skipped
    assert.is_true(!root.std.exists(root.std.path_join(dir, "css/deep/css/deep")));
    // A destination EQUAL to the source is not nested: an in-place compile
    // still reaches every file.
    let flat = scratch("nested_out_flat");
    write(flat, "one.scss", "a { b: c }\n");
    write(flat, "sub/two.scss", "j { k: l }\n");
    let r = sasso(flat, ["--no-source-map", ".:."]);
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.equal(read(flat, "one.css"), "a {\n  b: c;\n}\n");
    assert.equal(read(flat, "sub/two.css"), "j {\n  k: l;\n}\n");
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    };
    baml.fs.remove_dir_all(flat) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "directory_mode_skips_only_the_output_directory_itself" {
    // The nested-output skip is a DESCENDANT test, not a string prefix: a
    // sibling whose name merely starts with the destination's (`css2` beside
    // `css`) is still a source. Measured against dart-sass 1.104.1.
    let dir = scratch("nested_sibling");
    write(dir, "one.scss", "a { b: c }\n");
    write(dir, "css/inside.scss", "d { e: f }\n");
    write(dir, "css2/sibling.scss", "g { h: i }\n");
    let r = sasso(dir, ["--no-source-map", ".:css"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.equal(read(dir, "css/one.css"), "a {\n  b: c;\n}\n");
    assert.equal(read(dir, "css/css2/sibling.css"), "g {\n  h: i;\n}\n");
    // the output directory itself is still skipped
    assert.is_true(!root.std.exists(root.std.path_join(dir, "css/css")));
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

test "source_map_sources_name_imported_files_by_path" {
    // dart writes each imported file's path relative to the map, so two
    // partials sharing a basename are two sources; an entry that emits nothing
    // of its own is not listed; a stylesheet with no output has `[]`.
    let dir = scratch("sm_sources");
    write(dir, "src/sub/_p.scss", "a{b:1}\n");
    write(dir, "src/other/_p.scss", "c{d:2}\n");
    write(dir, "src/two.scss", "@import \"sub/p\";\n@import \"other/p\";\n");
    let r = sasso(dir, ["-q", "src/two.scss", "out/two.css"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.equal(
        read(dir, "out/two.css.map"),
        "{\"version\":3,\"sourceRoot\":\"\",\"sources\":[\"../src/sub/_p.scss\",\"../src/other/_p.scss\"],\"names\":[],\"mappings\":\"AAAA;EAAE;;;ACAF;EAAE\",\"file\":\"two.css\"}",
    );
    let r = sasso(dir, ["-q", "--embed-sources", "src/two.scss", "out2/two.css"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    // {read(&dir, "out2/two.css.map")}
    assert.is_true(
        read(dir, "out2/two.css.map").ends_with(
            ",\"sourcesContent\":[\"a{b:1}\\n\",\"c{d:2}\\n\"]}",
        ),
    );
    write(dir, "empty.scss", "");
    let r = sasso(dir, ["empty.scss", "out/e.css"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    // {read(&dir, "out/e.css.map")}
    assert.is_true(read(dir, "out/e.css.map").includes("\"sources\":[],"));
    assert_dart_files_match(
        [
            root.std.Tuple2<string, string> { _0: "src/sub/_p.scss", _1: "a{b:1}\n" },
            root.std.Tuple2<string, string> { _0: "src/other/_p.scss", _1: "c{d:2}\n" },
            root.std.Tuple2<string, string> {
                _0: "src/two.scss",
                _1: "@import \"sub/p\";\n@import \"other/p\";\n",
            },
        ],
        ["-q", "--embed-sources", "src/two.scss", "out/two.css"],
        ["out/two.css", "out/two.css.map"],
    );
    assert_dart_files_match(
        [root.std.Tuple2<string, string> { _0: "empty.scss", _1: "" }],
        ["empty.scss", "out/e.css"],
        ["out/e.css", "out/e.css.map"],
    );
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

/// The `WARNING:` blocks of a stderr transcript (each with its stack frames),
/// leaving out deprecation warnings — for assertions that are about the
/// frames of runtime warnings only.
function warning_blocks(stderr: string) -> string[] {
    stderr.split("\n\n").filter((block) -> {
        block.starts_with("WARNING:")
    })
}

/// The `Error:` block of a stderr transcript: from the last `Error:` header
/// to the end (what a failing compile prints after any warnings).
function error_block(stderr: string) -> string {
    let i = stderr.last_index_of("\nError: ");
    if (i != null) {
        stderr.slice(i + 1, stderr.length())
    } else {
        stderr
    }
}

/// A POSIX-spelled expectation with every named FRAME path respelled the way the
/// platform does: dart renders each one through `p.prettyUri`, so on Windows it
/// is `\`-separated. That is true of the entry stylesheet's frame as much as a
/// loaded file's (#151) — the command line's spelling does not survive into a
/// diagnostic — but NOT of a source-map url, which is `/` on every platform, so
/// the paths are listed rather than replaced blanket.
///
/// `\` and `/` are the same width, so the frames' column alignment is unchanged
/// and one expectation serves both platforms.
function with_frame_paths(expected: string, frames: string[]) -> string {
    let out = expected;
    // PORT: `cfg!(windows)` — false on the macOS/Linux hosts this port targets.
    let windows = false;
    if (windows) {
        for (let p in frames) {
            out = out.replace_all(p, p.replace_all("/", "\\"));
        }
    }
    out
}

/// What part of stderr to compare with dart-sass.
enum Compare {
    /// Byte for byte.
    Full,
    /// Only the final `Error:` block (see [`error_block`]).
    Error,
}

/// Run the same `args` through dart-sass in a sibling scratch dir seeded with
/// the same `files` and assert stderr matches, as far as `what` says.
function assert_dart_stderr_matches(
    files: root.std.Tuple2<string, string>[],
    args: string[],
    what: Compare,
) -> void {
    let dart = dart_bin();
    if (dart == null) {
        return;
    }
    let ours = scratch("parity_err_ours");
    let theirs = scratch("parity_err_theirs");
    for (let file in files) {
        write(ours, file._0, file._1);
        write(theirs, file._0, file._1);
    }
    let a = sasso(ours, args);
    let b = run_bin(dart, theirs, args, null);
    // exit codes differ for {args:?}\nours: {a.stderr}\ndart: {b.stderr}
    assert.equal(a.code, b.code);
    match (what) {
        // stderr differs from dart-sass for {args:?}
        Compare.Full => assert.equal(a.stderr, b.stderr),
        // error block differs from dart-sass for {args:?}
        Compare.Error => assert.equal(error_block(a.stderr), error_block(b.stderr)),
    };
    let _ = baml.fs.remove_dir_all(ours) catch (e) {
        let _io: baml.errors.Io => null
    };
    let _ = baml.fs.remove_dir_all(theirs) catch (e) {
        let _io: baml.errors.Io => null
    };
}

test "stack_frames_show_loaded_files_relative_to_the_working_directory" {
    // dart's frames spell a loaded file as its path from the current
    // directory, whether it was reached relatively (`src/sub/_warnme.scss`)
    // or through a load path (`lp/_dep.scss`, and `lp/_leaf.scss` which that
    // file loads) — and the entry by the same rule, not as it was typed
    // (#151, and see `the_entry_frame_is_spelled_as_dart_spells_it`). Same
    // for `@use` and `@import`.
    let used: root.std.Tuple2<string, string>[] = [
        root.std.Tuple2<string, string> { _0: "src/sub/_warnme.scss", _1: "@warn \"a\";\n" },
        root.std.Tuple2<string, string> { _0: "lp/_dep.scss", _1: "@use \"leaf\";\n@warn \"b\";\n" },
        root.std.Tuple2<string, string> { _0: "lp/_leaf.scss", _1: "@warn \"d\";\n" },
        root.std.Tuple2<string, string> {
            _0: "src/rel.scss",
            _1: "@use \"sub/warnme\";\n@use \"dep\";\n",
        },
    ];
    let dir = scratch("frames_use");
    for (let file in used) {
        write(dir, file._0, file._1);
    }
    let r = sasso(dir, ["--no-source-map", "-I", "lp", "src/rel.scss"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    // PORT: the Rust `\`-continued literal is three concatenated pieces.
    assert.equal(
        r.stderr,
        with_frame_paths(
            "WARNING: a\n    src/sub/_warnme.scss 1:1  @use\n    src/rel.scss 1:1          root stylesheet\n\n"
                + "WARNING: d\n    lp/_leaf.scss 1:1  @use\n    lp/_dep.scss 1:1   @use\n    src/rel.scss 2:1   root stylesheet\n\n"
                + "WARNING: b\n    lp/_dep.scss 2:1  @use\n    src/rel.scss 2:1  root stylesheet\n\n",
            ["src/sub/_warnme.scss", "lp/_leaf.scss", "lp/_dep.scss", "src/rel.scss"],
        ),
    );
    assert_dart_stderr_matches(used, ["--no-source-map", "-I", "lp", "src/rel.scss"], Compare.Full);
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    };

    let imported: root.std.Tuple2<string, string>[] = [
        root.std.Tuple2<string, string> { _0: "src/sub/_warnme.scss", _1: "@warn \"a\";\n" },
        root.std.Tuple2<string, string> {
            _0: "lp/_dep.scss",
            _1: "@warn \"b\";\n@import \"leaf\";\n",
        },
        root.std.Tuple2<string, string> { _0: "lp/_leaf.scss", _1: "@warn \"d\";\n" },
        root.std.Tuple2<string, string> {
            _0: "src/rel.scss",
            _1: "@import \"sub/warnme\";\n@import \"dep\";\n",
        },
    ];
    let dir = scratch("frames_import");
    for (let file in imported) {
        write(dir, file._0, file._1);
    }
    let r = sasso(dir, ["--no-source-map", "-I", "lp", "src/rel.scss"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.equal(
        warning_blocks(r.stderr),
        [
            "WARNING: a\n    src/sub/_warnme.scss 1:1  @import\n    src/rel.scss 1:9          root stylesheet",
            "WARNING: b\n    lp/_dep.scss 1:1  @import\n    src/rel.scss 2:9  root stylesheet",
            "WARNING: d\n    lp/_leaf.scss 1:1  @import\n    lp/_dep.scss 2:9   @import\n    src/rel.scss 2:9   root stylesheet",
        ]
            .map((b) -> {
                with_frame_paths(b, ["src/sub/_warnme.scss", "lp/_leaf.scss", "lp/_dep.scss", "src/rel.scss"])
            }),
    );
    assert_dart_stderr_matches(imported, ["--no-source-map", "-I", "lp", "src/rel.scss"], Compare.Full);
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

/// A scratch directory as the compiled process will see its own working
/// directory: `getcwd` resolves symlinks, so an argument built from
/// `std::env::temp_dir()` (`/tmp` -> `/private/tmp`, `/var` -> `/private/var`
/// on macOS) names the same file by a path that shares no prefix with the cwd —
/// which relativises to an absolute path and hides whatever the test meant to
/// assert. Windows' verbatim prefix is dropped: `canonicalize` adds one,
/// nothing a user types has it, and it is not part of a root's identity.
///
/// `\\?\UNC\server\share` is unwrapped to `\\server\share` rather than cut at
/// the prefix, which would leave a RELATIVE `UNC\server\share` — the same
/// silent nothing-is-asserted failure this helper exists to prevent, for a
/// scratch directory that lives on a share.
function resolved(dir: string) -> string {
    let real = root.std.canonicalize(dir) catch (e) {
        let io: baml.errors.Io => root.std.panic(`canonicalize scratch dir: ${io.message}`)
    };
    let unwrapped = without_verbatim_prefix(real);
    unwrapped ?? real
}

/// `\\?\C:\x` -> `C:\x`, `\\?\UNC\server\share\x` -> `\\server\share\x`, and
/// `None` when there is no wrapper to remove — which is every path on a POSIX
/// host, where the original is kept byte for byte.
function without_verbatim_prefix(p: string) -> string? {
    let share = root.std.strip_prefix(p, "\\\\?\\UNC\\");
    if (share != null) {
        "\\\\" + share
    } else {
        root.std.strip_prefix(p, "\\\\?\\")
    }
}

/// The Windows-only half of [`resolved`], which a POSIX run would never reach:
/// the UNC form is not a `\\?\` with a usable path behind it, so cutting the
/// four characters off leaves something relative.
test "a_verbatim_prefix_unwraps_to_a_path_that_is_still_absolute" {
    // PORT: raw strings `r"\\?\C:\…"` → escaped `"\\\\?\\C:\\…"`.
    assert.equal(
        without_verbatim_prefix("\\\\?\\C:\\Users\\you\\scratch"),
        "C:\\Users\\you\\scratch",
    );
    assert.equal(
        without_verbatim_prefix("\\\\?\\UNC\\nas\\share\\scratch"),
        "\\\\nas\\share\\scratch",
    );
    // Nothing to unwrap: the caller keeps what `canonicalize` gave it.
    assert.equal(without_verbatim_prefix("C:\\Users\\you\\scratch"), null);
    assert.equal(without_verbatim_prefix("/private/tmp/scratch"), null)
}

test "the_entry_frame_is_spelled_as_dart_spells_it" {
    // dart renders EVERY frame through `p.prettyUri` — the entry stylesheet's
    // included — so the spelling on the command line does not reach the
    // transcript: a `./` prefix, a doubled separator, a `..` hop and an
    // absolute path all report the same normalized path from the working
    // directory. sasso used to echo the argument verbatim (#151), which also
    // left the entry `/`-separated on Windows beside `\`-separated
    // dependencies — one warning block, two spellings.
    let files: root.std.Tuple2<string, string>[] = [
        root.std.Tuple2<string, string> { _0: "src/_dep.scss", _1: "@warn \"dep\";\n" },
        root.std.Tuple2<string, string> { _0: "src/entry.scss", _1: "@use \"dep\";\n" },
    ];
    let dir = scratch("entry_spelling");
    for (let file in files) {
        write(dir, file._0, file._1);
    }
    let dir = resolved(dir);
    let expected = with_frame_paths(
        "WARNING: dep\n    src/_dep.scss 1:1   @use\n    src/entry.scss 1:1  root stylesheet\n\n",
        ["src/_dep.scss", "src/entry.scss"],
    );
    // Every one of these names the same file from the same directory.
    let typed = ["src/entry.scss", "./src/entry.scss", "src//entry.scss", "src/../src/entry.scss"];
    for (let arg in typed) {
        let r = sasso(dir, ["--no-source-map", arg]);
        // {r.stderr}
        assert.equal(r.code, 0);
        // entry spelled {arg:?}
        assert.equal(r.stderr, expected);
    }
    // An absolute argument, from the directory that contains it.
    let abs = root.std.path_join(root.std.path_join(dir, "src"), "entry.scss");
    // PORT: `abs.to_string_lossy().into_owned()` — a path is already a string.
    let r = sasso(dir, ["--no-source-map", abs]);
    // {r.stderr}
    assert.equal(r.code, 0);
    // entry spelled absolutely
    assert.equal(r.stderr, expected);
    // And from a sibling directory below it, where the relative spelling of
    // both frames walks up.
    root.std.create_dir_all(root.std.path_join(dir, "out")) catch (e) {
        let io: baml.errors.Io => root.std.panic(`mkdir out: ${io.message}`)
    };
    let r = sasso(root.std.path_join(dir, "out"), ["--no-source-map", abs]);
    // {r.stderr}
    assert.equal(r.code, 0);
    assert.equal(
        r.stderr,
        with_frame_paths(
            "WARNING: dep\n    ../src/_dep.scss 1:1   @use\n    ../src/entry.scss 1:1  root stylesheet\n\n",
            ["../src/_dep.scss", "../src/entry.scss"],
        ),
    );
    // A directory pair: the entry is not typed at all, it comes out of the
    // walk, and `./src` must not survive into the frame either.
    let r = sasso(dir, ["--no-source-map", "./src:out"]);
    // {r.stderr}
    assert.equal(r.code, 0);
    // entry from a directory pair
    assert.equal(r.stderr, expected);
    for (let arg in typed) {
        assert_dart_stderr_matches(files, ["--no-source-map", arg], Compare.Full);
    }
    assert_dart_stderr_matches(files, ["--no-source-map", "./src:out"], Compare.Full);
    baml.fs.remove_dir_all(dir) catch (e) {
        let _io: baml.errors.Io => null
    }
}

// `tests/cli_dart_compat.rs`, part 2 of 2 (Rust lines 1763–3486). The file
// header and the shared helpers (`scratch`, `sasso`, `run_bin`, `write`,
// `read`, `warning_blocks`, `error_block`, `with_frame_paths`, `Compare`,
// `assert_dart_stderr_matches`, `assert_dart_files_match`, the `EXIT_*`
// codes, `GOOD`/`GOOD_CSS`/`BAD`) live in part 1, `cli_dart_compat.baml`.

test "quiet_deps_survives_a_compile_error_with_error_css" {
    // `--quiet-deps` hands the compiler a `DependencySet` whose mutex used to
    // be allocated lazily on first lock — inside the compile's bump arena, which
    // the compile reset on the way out. The error-CSS re-render (a second
    // compile in the same process) then locked freed memory and aborted with
    // "failed to lock mutex" instead of reporting the error.
    let dir = scratch("quietdeps_err");
    let _ = write(dir, "in.scss", BAD());
    let r = sasso(dir, ["--quiet-deps", "in.scss", "out.css"]);
    // "{}", r.stderr
    assert.equal(r.code, EXIT_COMPILE());
    // "{}", r.stderr
    assert.is_true(r.stderr.starts_with("Error: Undefined variable.\n"));
    // "{}", r.stderr
    assert.is_true(!r.stderr.includes("panicked"));
    assert.is_true(read(dir, "out.css").starts_with("/* Error: Undefined variable."));
    // The same with a recorded dependency in the set: the entry loads a
    // load-path file, which then fails.
    let _ = write(dir, "lp/_dep.scss", "b { c: $y }\n");
    let _ = write(dir, "usedep.scss", "@use \"dep\";\n");
    let r = sasso(dir, ["--quiet-deps", "-I", "lp", "usedep.scss", "dep.css"]);
    // "{}", r.stderr
    assert.equal(r.code, EXIT_COMPILE());
    // "{}", r.stderr
    assert.is_true(r.stderr.starts_with("Error: Undefined variable.\n"));
    // "{}", r.stderr
    assert.is_true(
        r.stderr.includes(with_frame_paths("lp/_dep.scss 1:8  @use\n", ["lp/_dep.scss"])),
    );
    assert.is_true(read(dir, "dep.css").starts_with("/* Error: Undefined variable."));
    // And several units in one process, the failing one first.
    let _ = write(dir, "good.scss", GOOD());
    let r = sasso(dir, ["--quiet-deps", "-j", "1", "in.scss:o1.css", "good.scss:o2.css"]);
    // "{}", r.stderr
    assert.equal(r.code, EXIT_COMPILE());
    // "{}", r.stderr
    assert.is_true(!r.stderr.includes("panicked"));
    assert.equal(read(dir, "o2.css"), `${GOOD_CSS()}\n/*# sourceMappingURL=o2.css.map */\n`);
    baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    }
}

function ORIGIN_DEP() -> string {
    "@mixin m {\n  x: 1;\n  @content;\n  z: 3;\n}\n@function f($v) {\n  @warn \"in f\";\n  @return $v + 1;\n}\n@mixin undef {\n  q: $nope;\n}\n"
}

test "callables_and_content_blocks_run_against_their_defining_file" {
    // dart evaluates a mixin, function, or `@content` block where it was
    // written: the frames name that file (with dart's `@content` member for
    // the block and the `@content;` statement as a call site in the mixin),
    // the source map points into it, and an error inside it renders its
    // source. `@use` here, so stderr has no deprecations and compares whole.
    let used: root.std.Tuple2<string, string>[] = [
        root.std.Tuple2<string, string> { _0: "src/_dep.scss", _1: ORIGIN_DEP() },
        root.std.Tuple2<string, string> {
            _0: "src/use.scss",
            _1: "@use \"dep\";\n@mixin e {\n  @warn \"in e\";\n  y: 2;\n}\na {\n  @include dep.m {\n    @warn \"in content\";\n    y: dep.f(1);\n  }\n}\n",
        },
    ];
    let dir = scratch("origin_use");
    for (let f in used) {
        let _ = write(dir, f._0, f._1);
    }
    let r = sasso(dir, ["src/use.scss", "use.css"]);
    // "{}", r.stderr
    assert.equal(r.code, 0);
    assert.equal(
        r.stderr,
        with_frame_paths(
            "WARNING: in content\n    src/use.scss 8:5   @content\n    src/_dep.scss 3:3  m()\n    src/use.scss 7:3   root stylesheet\n\nWARNING: in f\n    src/_dep.scss 7:3  f()\n    src/use.scss 9:8   @content\n    src/_dep.scss 3:3  m()\n    src/use.scss 7:3   root stylesheet\n\n",
            ["src/_dep.scss", "src/use.scss"],
        ),
    );
    assert.equal(
        read(dir, "use.css"),
        "a {\n  x: 1;\n  y: 2;\n  z: 3;\n}\n\n/*# sourceMappingURL=use.css.map */\n",
    );
    assert.equal(
        read(dir, "use.css.map"),
        "{\"version\":3,\"sourceRoot\":\"\",\"sources\":[\"src/use.scss\",\"src/_dep.scss\"],\"names\":[],\"mappings\":\"AAKA;ECJE;EDOE;ECLF\",\"file\":\"use.css\"}",
    );
    assert_dart_stderr_matches(used, ["src/use.scss", "use.css"], Compare.Full);
    assert_dart_files_match(used, ["src/use.scss", "use.css"], ["use.css", "use.css.map"]);
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    };

    // The same through a textual `@import`: a mixin the import defined is
    // still evaluated in ITS file.
    let imported: root.std.Tuple2<string, string>[] = [
        root.std.Tuple2<string, string> { _0: "src/_dep.scss", _1: ORIGIN_DEP() },
        root.std.Tuple2<string, string> {
            _0: "src/imp.scss",
            _1: "@import \"dep\";\na {\n  @include m {\n    @warn \"in content\";\n    y: f(1);\n  }\n}\n",
        },
    ];
    let dir = scratch("origin_import");
    for (let f in imported) {
        let _ = write(dir, f._0, f._1);
    }
    let r = sasso(dir, ["src/imp.scss", "imp.css"]);
    // "{}", r.stderr
    assert.equal(r.code, 0);
    assert.equal(
        warning_blocks(r.stderr),
        [
            "WARNING: in content\n    src/imp.scss 4:5   @content\n    src/_dep.scss 3:3  m()\n    src/imp.scss 3:3   root stylesheet",
            "WARNING: in f\n    src/_dep.scss 7:3  f()\n    src/imp.scss 5:8   @content\n    src/_dep.scss 3:3  m()\n    src/imp.scss 3:3   root stylesheet",
        ]
            .map((b) -> {
                with_frame_paths(b, ["src/_dep.scss", "src/imp.scss"])
            }),
    );
    assert.equal(
        read(dir, "imp.css.map"),
        "{\"version\":3,\"sourceRoot\":\"\",\"sources\":[\"src/imp.scss\",\"src/_dep.scss\"],\"names\":[],\"mappings\":\"AACA;ECAE;EDGE;ECDF\",\"file\":\"imp.css\"}",
    );
    assert_dart_stderr_matches(imported, ["src/imp.scss", "imp.css"], Compare.Full);
    assert_dart_files_match(imported, ["src/imp.scss", "imp.css"], ["imp.css", "imp.css.map"]);
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    };

    // An error inside an imported mixin: the snippet is the mixin's file.
    let failing: root.std.Tuple2<string, string>[] = [
        root.std.Tuple2<string, string> { _0: "src/_dep.scss", _1: ORIGIN_DEP() },
        root.std.Tuple2<string, string> {
            _0: "src/undef.scss",
            _1: "@import \"dep\";\na {\n  @include undef;\n}\n",
        },
    ];
    let dir = scratch("origin_error");
    for (let f in failing) {
        let _ = write(dir, f._0, f._1);
    }
    let r = sasso(dir, ["--no-source-map", "src/undef.scss", "undef.css"]);
    // "{}", r.stderr
    assert.equal(r.code, EXIT_COMPILE());
    assert.equal(
        error_block(r.stderr),
        with_frame_paths(
            "Error: Undefined variable.\n   ╷\n11 │   q: $nope;\n   │      ^^^^^\n   ╵\n  src/_dep.scss 11:6  undef()\n  src/undef.scss 3:3  root stylesheet\n",
            ["src/_dep.scss", "src/undef.scss"],
        ),
    );
    assert.is_true(
        read(dir, "undef.css").includes(
            with_frame_paths(" *   src/_dep.scss 11:6  undef()\n", ["src/_dep.scss"]),
        ),
    );
    assert_dart_stderr_matches(failing, ["--no-source-map", "src/undef.scss", "undef.css"], Compare.Error);
    assert_dart_files_match(failing, ["--no-source-map", "src/undef.scss", "undef.css"], ["undef.css"]);
    baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    }
}

test "first_class_callables_are_traced_like_direct_ones" {
    // `meta.apply` and `meta.call`: frames inside the body name the callable
    // (`m()`, `f()`), the `meta.call(...)` expression is a call site, and the
    // content block goes back to the includer's file — as dart prints them.
    let files: root.std.Tuple2<string, string>[] = [
        root.std.Tuple2<string, string> { _0: "src/_dep.scss", _1: ORIGIN_DEP() },
        root.std.Tuple2<string, string> {
            _0: "src/apply.scss",
            _1: "@use \"sass:meta\";\n@use \"dep\";\na {\n  @include meta.apply(meta.get-mixin(\"m\", \"dep\")) {\n    @warn \"apply content\";\n    y: 2;\n  }\n  b: meta.call(meta.get-function(\"f\", $module: \"dep\"), 1);\n}\n",
        },
    ];
    let dir = scratch("origin_apply");
    for (let f in files) {
        let _ = write(dir, f._0, f._1);
    }
    let r = sasso(dir, ["src/apply.scss", "apply.css"]);
    // "{}", r.stderr
    assert.equal(r.code, 0);
    assert.equal(
        r.stderr,
        with_frame_paths(
            "WARNING: apply content\n    src/apply.scss 5:5  @content\n    src/_dep.scss 3:3   m()\n    src/apply.scss 4:3  root stylesheet\n\nWARNING: in f\n    src/_dep.scss 7:3   f()\n    src/apply.scss 8:6  root stylesheet\n\n",
            ["src/_dep.scss", "src/apply.scss"],
        ),
    );
    assert.equal(
        read(dir, "apply.css.map"),
        "{\"version\":3,\"sourceRoot\":\"\",\"sources\":[\"src/apply.scss\",\"src/_dep.scss\"],\"names\":[],\"mappings\":\"AAEA;ECDE;EDIE;ECFF;EDIA\",\"file\":\"apply.css\"}",
    );
    assert_dart_stderr_matches(files, ["src/apply.scss", "apply.css"], Compare.Full);
    assert_dart_files_match(files, ["src/apply.scss", "apply.css"], ["apply.css", "apply.css.map"]);
    baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    }
}

test "error_inside_a_meta_call_highlights_the_call_expression" {
    // An `@error` attaches at the nearest call boundary; for a function
    // invoked through `meta.call` that is the whole `meta.call(...)`
    // expression, as dart highlights it.
    let files: root.std.Tuple2<string, string>[] = [
        root.std.Tuple2<string, string> {
            _0: "call.scss",
            _1: "@use \"sass:meta\";\n@function f($v) {\n  @error \"boom\";\n}\na {\n  b: meta.call(meta.get-function(\"f\"), 1);\n}\n",
        },
    ];
    let dir = scratch("origin_call_error");
    let _ = write(dir, "call.scss", files[0]._1);
    let r = sasso(dir, ["--no-source-map", "call.scss"]);
    // "{}", r.stderr
    assert.equal(r.code, EXIT_COMPILE());
    assert.equal(
        r.stderr,
        "Error: \"boom\"\n  ╷\n6 │   b: meta.call(meta.get-function(\"f\"), 1);\n  │      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n  ╵\n  call.scss 6:6  root stylesheet\n",
    );
    assert_dart_stderr_matches(files, ["--no-source-map", "call.scss"], Compare.Full);
    baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    }
}

test "error_in_a_content_block_points_at_the_include" {
    // dart runs a content block as a callable invoked from the `@include`
    // that supplied it: an `@error` raised directly in the block carets that
    // `@include` (the name and arguments only — not the block), while the
    // trace still lists the mixin's `@content;` statement as the `m()` frame.
    // Here the mixin lives in another file; the snippet is the includer's.
    let files: root.std.Tuple2<string, string>[] = [
        root.std.Tuple2<string, string> {
            _0: "src/_cm.scss",
            _1: "@mixin m {\n  x: 1;\n  @content;\n}\n",
        },
        root.std.Tuple2<string, string> {
            _0: "src/cerr.scss",
            _1: "@use \"cm\";\na {\n  @include cm.m {\n    @error \"cross\";\n  }\n}\n",
        },
    ];
    let dir = scratch("origin_content_error");
    for (let f in files) {
        let _ = write(dir, f._0, f._1);
    }
    let r = sasso(dir, ["--no-source-map", "src/cerr.scss"]);
    // "{}", r.stderr
    assert.equal(r.code, EXIT_COMPILE());
    assert.equal(
        r.stderr,
        with_frame_paths(
            "Error: \"cross\"\n  ╷\n3 │   @include cm.m {\n  │   ^^^^^^^^^^^^^\n  ╵\n  src/_cm.scss 3:3   m()\n  src/cerr.scss 3:3  root stylesheet\n",
            ["src/_cm.scss", "src/cerr.scss"],
        ),
    );
    assert_dart_stderr_matches(files, ["--no-source-map", "src/cerr.scss"], Compare.Full);
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    };

    // Forwarded through a second mixin (`@include inner { @content; }`): the
    // boundary is the innermost `@include` whose mixin is running — `@include
    // inner` — and both `@content` invocations stay in the trace.
    let files: root.std.Tuple2<string, string>[] = [
        root.std.Tuple2<string, string> {
            _0: "err.scss",
            _1: "@mixin inner {\n  i: 1;\n  @content;\n}\n@mixin outer {\n  o: 1;\n  @include inner {\n    @content;\n  }\n}\na {\n  @include outer {\n    @error \"deep\";\n  }\n}\n",
        },
    ];
    let dir = scratch("origin_content_forward");
    let _ = write(dir, "err.scss", files[0]._1);
    let r = sasso(dir, ["--no-source-map", "err.scss"]);
    // "{}", r.stderr
    assert.equal(r.code, EXIT_COMPILE());
    assert.equal(
        r.stderr,
        "Error: \"deep\"\n  ╷\n7 │   @include inner {\n  │   ^^^^^^^^^^^^^^\n  ╵\n  err.scss 8:5   @content\n  err.scss 3:3   inner()\n  err.scss 7:3   outer()\n  err.scss 12:3  root stylesheet\n",
    );
    assert_dart_stderr_matches(files, ["--no-source-map", "err.scss"], Compare.Full);
    baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    }
}

test "members_forwarded_through_an_import_keep_their_defining_file" {
    // `@import "fwd"` where _fwd.scss `@forward`s _dep.scss: the members
    // become the importer's, but their bodies still belong to _dep.scss —
    // frames name it and the map points into it (dart: sources
    // [impfwd.scss, _dep.scss], mappings `AACA;ECCE;EDCA`).
    let files: root.std.Tuple2<string, string>[] = [
        root.std.Tuple2<string, string> {
            _0: "src/_dep.scss",
            _1: "@mixin m {\n  @warn \"in m\";\n  x: 1;\n}\n@function f($v) {\n  @warn \"in f\";\n  @return $v;\n}\n",
        },
        root.std.Tuple2<string, string> { _0: "src/_fwd.scss", _1: "@forward \"dep\";\n" },
        root.std.Tuple2<string, string> {
            _0: "src/impfwd.scss",
            _1: "@import \"fwd\";\na {\n  @include m;\n  b: f(1);\n}\n",
        },
    ];
    let dir = scratch("origin_import_forward");
    for (let f in files) {
        let _ = write(dir, f._0, f._1);
    }
    let r = sasso(dir, ["src/impfwd.scss", "impfwd.css"]);
    // "{}", r.stderr
    assert.equal(r.code, 0);
    assert.equal(
        warning_blocks(r.stderr),
        [
            "WARNING: in m\n    src/_dep.scss 2:3    m()\n    src/impfwd.scss 3:3  root stylesheet",
            "WARNING: in f\n    src/_dep.scss 6:3    f()\n    src/impfwd.scss 4:6  root stylesheet",
        ]
            .map((b) -> {
                with_frame_paths(b, ["src/_dep.scss", "src/impfwd.scss"])
            }),
    );
    assert.equal(
        read(dir, "impfwd.css.map"),
        "{\"version\":3,\"sourceRoot\":\"\",\"sources\":[\"src/impfwd.scss\",\"src/_dep.scss\"],\"names\":[],\"mappings\":\"AACA;ECCE;EDCA\",\"file\":\"impfwd.css\"}",
    );
    assert_dart_stderr_matches(files, ["src/impfwd.scss", "impfwd.css"], Compare.Full);
    assert_dart_files_match(files, ["src/impfwd.scss", "impfwd.css"], ["impfwd.css", "impfwd.css.map"]);
    baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    }
}

test "import_deprecations_fire_when_a_file_is_parsed" {
    // dart-sass warns about `@import` while PARSING a file, so all of a file's
    // import deprecations come before anything its body prints — the entry's
    // three (one nested in a style rule) before `WARNING: top`, `_dep.scss`'s
    // one right after its `@import` frame is entered and before `dep top` —
    // and a file the import cache already parsed warns once, however often it
    // is imported (`_dep.scss` twice here). `--quiet-deps` drops the
    // dependency's but keeps the entry's. A `@use`d module's own `@import`
    // warns under the `@use` frame, before the module body runs.
    let files: root.std.Tuple2<string, string>[] = [
        root.std.Tuple2<string, string> { _0: "lp/_leaf.scss", _1: "@warn \"leaf\";\nl { m: 1 }\n" },
        root.std.Tuple2<string, string> {
            _0: "lp/_dep.scss",
            _1: "@warn \"dep top\";\n@import \"leaf\";\n@warn \"dep bottom\";\n",
        },
        root.std.Tuple2<string, string> { _0: "lp/_x.scss", _1: "x { y: 1 }\n" },
        root.std.Tuple2<string, string> {
            _0: "lp/_mod.scss",
            _1: "@warn \"mod top\";\n@import \"x\";\n@warn \"mod bottom\";\nm { n: 1 }\n",
        },
        root.std.Tuple2<string, string> {
            _0: "src/main.scss",
            _1: "@warn \"top\";\n@import \"dep\";\n@warn \"middle\";\na {\n  b {\n    @import \"x\";\n  }\n}\n@import \"dep\";\n@warn \"end\";\n",
        },
        root.std.Tuple2<string, string> {
            _0: "src/usemod.scss",
            _1: "@use \"mod\";\n@warn \"entry\";\n@import \"dep\";\n",
        },
    ];
    let dir = scratch("import_dep_parse");
    for (let f in files) {
        let _ = write(dir, f._0, f._1);
    }
    // Every frame below names one of these.
    let frames = (s: string) -> string {
        with_frame_paths(s, ["lp/_dep.scss", "lp/_leaf.scss", "lp/_mod.scss", "src/main.scss", "src/usemod.scss"])
    };
    let r = sasso(dir, ["--no-source-map", "-I", "lp", "src/main.scss"]);
    // "{}", r.stderr
    assert.equal(r.code, 0);
    assert.equal(
        r.stderr,
        frames(
            "DEPRECATION WARNING [import]: Sass @import rules are deprecated and will be removed in Dart Sass 3.0.0.\n\nMore info and automated migrator: https://sass-lang.com/d/import\n\n  ╷\n2 │ @import \"dep\";\n  │         ^^^^^\n  ╵\n    src/main.scss 2:9  root stylesheet\n\nDEPRECATION WARNING [import]: Sass @import rules are deprecated and will be removed in Dart Sass 3.0.0.\n\nMore info and automated migrator: https://sass-lang.com/d/import\n\n  ╷\n6 │     @import \"x\";\n  │             ^^^\n  ╵\n    src/main.scss 6:13  root stylesheet\n\nDEPRECATION WARNING [import]: Sass @import rules are deprecated and will be removed in Dart Sass 3.0.0.\n\nMore info and automated migrator: https://sass-lang.com/d/import\n\n  ╷\n9 │ @import \"dep\";\n  │         ^^^^^\n  ╵\n    src/main.scss 9:9  root stylesheet\n\nWARNING: top\n    src/main.scss 1:1  root stylesheet\n\nDEPRECATION WARNING [import]: Sass @import rules are deprecated and will be removed in Dart Sass 3.0.0.\n\nMore info and automated migrator: https://sass-lang.com/d/import\n\n  ╷\n2 │ @import \"leaf\";\n  │         ^^^^^^\n  ╵\n    lp/_dep.scss 2:9   @import\n    src/main.scss 2:9  root stylesheet\n\nWARNING: dep top\n    lp/_dep.scss 1:1   @import\n    src/main.scss 2:9  root stylesheet\n\nWARNING: leaf\n    lp/_leaf.scss 1:1  @import\n    lp/_dep.scss 2:9   @import\n    src/main.scss 2:9  root stylesheet\n\nWARNING: dep bottom\n    lp/_dep.scss 3:1   @import\n    src/main.scss 2:9  root stylesheet\n\nWARNING: middle\n    src/main.scss 3:1  root stylesheet\n\nWARNING: dep top\n    lp/_dep.scss 1:1   @import\n    src/main.scss 9:9  root stylesheet\n\nWARNING: leaf\n    lp/_leaf.scss 1:1  @import\n    lp/_dep.scss 2:9   @import\n    src/main.scss 9:9  root stylesheet\n\nWARNING: dep bottom\n    lp/_dep.scss 3:1   @import\n    src/main.scss 9:9  root stylesheet\n\nWARNING: end\n    src/main.scss 10:1  root stylesheet\n\n",
        ),
    );
    assert.equal(r.stdout, "l {\n  m: 1;\n}\n\na b x {\n  y: 1;\n}\n\nl {\n  m: 1;\n}\n");
    let r = sasso(dir, ["--no-source-map", "-I", "lp", "--quiet-deps", "src/main.scss"]);
    // "{}", r.stderr
    assert.equal(r.code, 0);
    assert.equal(
        r.stderr,
        frames(
            "DEPRECATION WARNING [import]: Sass @import rules are deprecated and will be removed in Dart Sass 3.0.0.\n\nMore info and automated migrator: https://sass-lang.com/d/import\n\n  ╷\n2 │ @import \"dep\";\n  │         ^^^^^\n  ╵\n    src/main.scss 2:9  root stylesheet\n\nDEPRECATION WARNING [import]: Sass @import rules are deprecated and will be removed in Dart Sass 3.0.0.\n\nMore info and automated migrator: https://sass-lang.com/d/import\n\n  ╷\n6 │     @import \"x\";\n  │             ^^^\n  ╵\n    src/main.scss 6:13  root stylesheet\n\nDEPRECATION WARNING [import]: Sass @import rules are deprecated and will be removed in Dart Sass 3.0.0.\n\nMore info and automated migrator: https://sass-lang.com/d/import\n\n  ╷\n9 │ @import \"dep\";\n  │         ^^^^^\n  ╵\n    src/main.scss 9:9  root stylesheet\n\nWARNING: top\n    src/main.scss 1:1  root stylesheet\n\nWARNING: dep top\n    lp/_dep.scss 1:1   @import\n    src/main.scss 2:9  root stylesheet\n\nWARNING: leaf\n    lp/_leaf.scss 1:1  @import\n    lp/_dep.scss 2:9   @import\n    src/main.scss 2:9  root stylesheet\n\nWARNING: dep bottom\n    lp/_dep.scss 3:1   @import\n    src/main.scss 2:9  root stylesheet\n\nWARNING: middle\n    src/main.scss 3:1  root stylesheet\n\nWARNING: dep top\n    lp/_dep.scss 1:1   @import\n    src/main.scss 9:9  root stylesheet\n\nWARNING: leaf\n    lp/_leaf.scss 1:1  @import\n    lp/_dep.scss 2:9   @import\n    src/main.scss 9:9  root stylesheet\n\nWARNING: dep bottom\n    lp/_dep.scss 3:1   @import\n    src/main.scss 9:9  root stylesheet\n\nWARNING: end\n    src/main.scss 10:1  root stylesheet\n\n",
        ),
    );
    let r = sasso(dir, ["--no-source-map", "-I", "lp", "src/usemod.scss"]);
    // "{}", r.stderr
    assert.equal(r.code, 0);
    assert.equal(
        r.stderr,
        frames(
            "DEPRECATION WARNING [import]: Sass @import rules are deprecated and will be removed in Dart Sass 3.0.0.\n\nMore info and automated migrator: https://sass-lang.com/d/import\n\n  ╷\n3 │ @import \"dep\";\n  │         ^^^^^\n  ╵\n    src/usemod.scss 3:9  root stylesheet\n\nDEPRECATION WARNING [import]: Sass @import rules are deprecated and will be removed in Dart Sass 3.0.0.\n\nMore info and automated migrator: https://sass-lang.com/d/import\n\n  ╷\n2 │ @import \"x\";\n  │         ^^^\n  ╵\n    lp/_mod.scss 2:9     @use\n    src/usemod.scss 1:1  root stylesheet\n\nWARNING: mod top\n    lp/_mod.scss 1:1     @use\n    src/usemod.scss 1:1  root stylesheet\n\nWARNING: mod bottom\n    lp/_mod.scss 3:1     @use\n    src/usemod.scss 1:1  root stylesheet\n\nWARNING: entry\n    src/usemod.scss 2:1  root stylesheet\n\nDEPRECATION WARNING [import]: Sass @import rules are deprecated and will be removed in Dart Sass 3.0.0.\n\nMore info and automated migrator: https://sass-lang.com/d/import\n\n  ╷\n2 │ @import \"leaf\";\n  │         ^^^^^^\n  ╵\n    lp/_dep.scss 2:9     @import\n    src/usemod.scss 3:9  root stylesheet\n\nWARNING: dep top\n    lp/_dep.scss 1:1     @import\n    src/usemod.scss 3:9  root stylesheet\n\nWARNING: leaf\n    lp/_leaf.scss 1:1    @import\n    lp/_dep.scss 2:9     @import\n    src/usemod.scss 3:9  root stylesheet\n\nWARNING: dep bottom\n    lp/_dep.scss 3:1     @import\n    src/usemod.scss 3:9  root stylesheet\n\n",
        ),
    );
    assert.equal(r.stdout, "x {\n  y: 1;\n}\n\nm {\n  n: 1;\n}\n\nl {\n  m: 1;\n}\n");
    assert_dart_stderr_matches(files, ["--no-source-map", "-I", "lp", "src/main.scss"], Compare.Full);
    assert_dart_stderr_matches(files, ["--no-source-map", "-I", "lp", "--quiet-deps", "src/main.scss"], Compare.Full);
    assert_dart_stderr_matches(files, ["--no-source-map", "-I", "lp", "src/usemod.scss"], Compare.Full);
    baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    }
}

test "misplaced_import_is_rejected_like_dart" {
    // dart's parser rejects an `@import` inside a mixin body or a property
    // set — in the entry and in every loaded file — with "This at-rule is not
    // allowed here.", a snippet underlining the rule, and the loader chain
    // as frames (`lp/_hasmixin.scss 2:3  @use`). sasso used to accept it in
    // property sets and in loaded files' mixins, and reported the entry case
    // without position or frames.
    let files: root.std.Tuple2<string, string>[] = [
        root.std.Tuple2<string, string> { _0: "lp/_x.scss", _1: "x { y: 1 }\n" },
        root.std.Tuple2<string, string> {
            _0: "lp/_hasmixin.scss",
            _1: "@mixin m {\n  @import \"x\";\n}\n",
        },
        root.std.Tuple2<string, string> {
            _0: "propset.scss",
            _1: "a {\n  font: {\n    family: serif;\n    @import \"x\";\n  }\n}\n",
        },
        root.std.Tuple2<string, string> {
            _0: "mixinimp.scss",
            _1: "@mixin m {\n  @import \"x\";\n}\n",
        },
        root.std.Tuple2<string, string> {
            _0: "usemixin.scss",
            _1: "@use \"hasmixin\";\na {\n  @include hasmixin.m;\n}\n",
        },
        root.std.Tuple2<string, string> {
            _0: "impmixin.scss",
            _1: "@import \"hasmixin\";\na {\n  @include m;\n}\n",
        },
    ];
    let dir = scratch("misplaced_import");
    for (let f in files) {
        let _ = write(dir, f._0, f._1);
    }
    // The only loaded file any frame here names; the rest are entries.
    let frames = (s: string) -> string {
        with_frame_paths(s, ["lp/_hasmixin.scss"])
    };
    let r = sasso(dir, ["--no-source-map", "-I", "lp", "propset.scss"]);
    // "{}", r.stderr
    assert.equal(r.code, EXIT_COMPILE());
    assert.equal(
        r.stderr,
        "Error: This at-rule is not allowed here.\n  ╷\n4 │     @import \"x\";\n  │     ^^^^^^^^^^^\n  ╵\n  propset.scss 4:5  root stylesheet\n",
    );
    assert_dart_stderr_matches(files, ["--no-source-map", "-I", "lp", "propset.scss"], Compare.Full);
    let r = sasso(dir, ["--no-source-map", "-I", "lp", "mixinimp.scss"]);
    // "{}", r.stderr
    assert.equal(r.code, EXIT_COMPILE());
    assert.equal(
        r.stderr,
        "Error: This at-rule is not allowed here.\n  ╷\n2 │   @import \"x\";\n  │   ^^^^^^^^^^^\n  ╵\n  mixinimp.scss 2:3  root stylesheet\n",
    );
    assert_dart_stderr_matches(files, ["--no-source-map", "-I", "lp", "mixinimp.scss"], Compare.Full);
    let r = sasso(dir, ["--no-source-map", "-I", "lp", "usemixin.scss"]);
    // "{}", r.stderr
    assert.equal(r.code, EXIT_COMPILE());
    assert.equal(
        r.stderr,
        frames(
            "Error: This at-rule is not allowed here.\n  ╷\n2 │   @import \"x\";\n  │   ^^^^^^^^^^^\n  ╵\n  lp/_hasmixin.scss 2:3  @use\n  usemixin.scss 1:1      root stylesheet\n",
        ),
    );
    assert_dart_stderr_matches(files, ["--no-source-map", "-I", "lp", "usemixin.scss"], Compare.Full);
    let r = sasso(dir, ["--no-source-map", "-I", "lp", "impmixin.scss"]);
    // "{}", r.stderr
    assert.equal(r.code, EXIT_COMPILE());
    assert.equal(
        r.stderr,
        frames(
            "DEPRECATION WARNING [import]: Sass @import rules are deprecated and will be removed in Dart Sass 3.0.0.\n\nMore info and automated migrator: https://sass-lang.com/d/import\n\n  ╷\n1 │ @import \"hasmixin\";\n  │         ^^^^^^^^^^\n  ╵\n    impmixin.scss 1:9  root stylesheet\n\nError: This at-rule is not allowed here.\n  ╷\n2 │   @import \"x\";\n  │   ^^^^^^^^^^^\n  ╵\n  lp/_hasmixin.scss 2:3  @import\n  impmixin.scss 1:9      root stylesheet\n",
        ),
    );
    assert_dart_stderr_matches(files, ["--no-source-map", "-I", "lp", "impmixin.scss"], Compare.Full);
    baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    }
}

test "misplaced_import_in_a_function_or_interpolated_at_rule" {
    // Two more places dart's parser rejects an `@import`: a `@function` body
    // (the error keeps its snippet and frame, like the mixin case) and the
    // body of an interpolated at-rule (`@#{"media"} screen { … }`) inside a
    // mixin, which the static check walks like a plain at-rule.
    let files: root.std.Tuple2<string, string>[] = [
        root.std.Tuple2<string, string> { _0: "lp/_x.scss", _1: "x { y: 1 }\n" },
        root.std.Tuple2<string, string> {
            _0: "infn.scss",
            _1: "@function f() {\n  @import \"x\";\n  @return 1;\n}\na { b: f(); }\n",
        },
        root.std.Tuple2<string, string> {
            _0: "interp.scss",
            _1: "@mixin m {\n  @#{\"media\"} screen {\n    @import \"x\";\n  }\n}\na {\n  @include m;\n}\n",
        },
    ];
    let dir = scratch("misplaced_import2");
    for (let f in files) {
        let _ = write(dir, f._0, f._1);
    }
    let r = sasso(dir, ["--no-source-map", "-I", "lp", "infn.scss"]);
    // "{}", r.stderr
    assert.equal(r.code, EXIT_COMPILE());
    assert.equal(
        r.stderr,
        "Error: This at-rule is not allowed here.\n  ╷\n2 │   @import \"x\";\n  │   ^^^^^^^^^^^\n  ╵\n  infn.scss 2:3  root stylesheet\n",
    );
    assert_dart_stderr_matches(files, ["--no-source-map", "-I", "lp", "infn.scss"], Compare.Full);
    let r = sasso(dir, ["--no-source-map", "-I", "lp", "interp.scss"]);
    // "{}", r.stderr
    assert.equal(r.code, EXIT_COMPILE());
    assert.equal(
        r.stderr,
        "Error: This at-rule is not allowed here.\n  ╷\n3 │     @import \"x\";\n  │     ^^^^^^^^^^^\n  ╵\n  interp.scss 3:5  root stylesheet\n",
    );
    assert_dart_stderr_matches(files, ["--no-source-map", "-I", "lp", "interp.scss"], Compare.Full);
    baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    }
}

test "plain_css_entry_passes_its_imports_through" {
    // A `.css` entry is plain CSS: `@import "theme";` is a CSS import to emit
    // verbatim, not a Sass file to load (dart), and it carries no `[import]`
    // deprecation. (sasso used to run the Sass evaluator over it, warn, and
    // fail with "Can't find stylesheet to import".) A property set, on the
    // other hand, admits no `@import` of any kind — plain-CSS ones included,
    // even under a control directive.
    let files: root.std.Tuple2<string, string>[] = [
        root.std.Tuple2<string, string> { _0: "lp/_x.scss", _1: "x { y: 1 }\n" },
        root.std.Tuple2<string, string> {
            _0: "entry.css",
            _1: "@import \"theme\";\n@import url(other.css);\na { b: c }\n",
        },
        root.std.Tuple2<string, string> {
            _0: "propcss.scss",
            _1: "a {\n  font: {\n    family: serif;\n    @import url(x.css);\n  }\n}\n",
        },
        root.std.Tuple2<string, string> {
            _0: "propcss2.scss",
            _1: "a {\n  font: {\n    @if true {\n      @import \"x.css\";\n    }\n  }\n}\n",
        },
    ];
    let dir = scratch("plain_css_entry");
    for (let f in files) {
        let _ = write(dir, f._0, f._1);
    }
    let r = sasso(dir, ["--no-source-map", "-I", "lp", "entry.css"]);
    // "{}", r.stderr
    assert.equal(r.code, 0);
    assert.equal(r.stderr, "");
    assert.equal(r.stdout, "@import \"theme\";\n@import url(other.css);\na {\n  b: c;\n}\n");
    assert_dart_stderr_matches(files, ["--no-source-map", "-I", "lp", "entry.css"], Compare.Full);
    let r = sasso(dir, ["--no-source-map", "-I", "lp", "propcss.scss"]);
    // "{}", r.stderr
    assert.equal(r.code, EXIT_COMPILE());
    assert.equal(
        r.stderr,
        "Error: This at-rule is not allowed here.\n  ╷\n4 │     @import url(x.css);\n  │     ^^^^^^^^^^^^^^^^^^\n  ╵\n  propcss.scss 4:5  root stylesheet\n",
    );
    assert_dart_stderr_matches(files, ["--no-source-map", "-I", "lp", "propcss.scss"], Compare.Full);
    let r = sasso(dir, ["--no-source-map", "-I", "lp", "propcss2.scss"]);
    // "{}", r.stderr
    assert.equal(r.code, EXIT_COMPILE());
    assert.equal(
        r.stderr,
        "Error: This at-rule is not allowed here.\n  ╷\n4 │       @import \"x.css\";\n  │       ^^^^^^^^^^^^^^^\n  ╵\n  propcss2.scss 4:7  root stylesheet\n",
    );
    assert_dart_stderr_matches(files, ["--no-source-map", "-I", "lp", "propcss2.scss"], Compare.Full);
    baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    }
}

/// `--update` leaves an up-to-date output alone and rebuilds when anything it
/// imports changes (#86, the binary half of #133).
///
/// The partial is two levels down on purpose: one level can pass by accident,
/// and the first version of this passed the "nothing changed" half while
/// failing this one — `FsImporter`'s canonical form is the absolute PATH, not
/// a `file://` URL, so every dependency was dropped on the way to the stat and
/// the list arrived empty.
test "update_skips_a_fresh_output_and_rebuilds_on_a_deep_partial" {
    let dir = scratch("update-deps");
    let _ = write(dir, "_deep.scss", "$c: #111;\n");
    let _ = write(dir, "_base.scss", "@import \"deep\";\n.base { color: $c; }\n");
    let _ = write(dir, "entry.scss", "@import \"base\";\n");

    let first = sasso(dir, ["--no-source-map", "entry.scss:out.css"]);
    // "{}", first.stderr
    assert.equal(first.code, 0);
    // "first compile"
    assert.is_true(read(dir, "out.css").includes("#111"));

    // Nothing changed: the output keeps its mtime, which is what downstream
    // watchers key on and the reason the flag exists.
    let stamp = root.std.expect(root.std.mtime_nanos(root.std.path_join(dir, "out.css")), "stat out.css");
    root.std.sleep_ms(1100);
    let second = sasso(dir, ["--no-source-map", "--update", "entry.scss:out.css"]);
    // "{}", second.stderr
    assert.equal(second.code, 0);
    let after = root.std.expect(root.std.mtime_nanos(root.std.path_join(dir, "out.css")), "stat out.css");
    // "--update rewrote an already-current output"
    assert.equal(stamp, after);

    // A partial two levels down changes: the output is stale and must be built.
    let _ = write(dir, "_deep.scss", "$c: #444;\n");
    root.std.sleep_ms(1100);
    let third = sasso(dir, ["--no-source-map", "--update", "entry.scss:out.css"]);
    // "{}", third.stderr
    assert.equal(third.code, 0);
    // "--update ignored a transitively imported partial: {}", read(&dir, "out.css")
    assert.is_true(read(dir, "out.css").includes("#444"))
}

/// `--update` with `--stdin` is a usage error, as in dart-sass.
///
/// Standard input has no mtime, so "is the output newer than its input" has no
/// honest answer — and the silent answer is the dangerous one. Before this,
/// the freshness loop simply skipped a `None` input, so a stdin unit with no
/// imports had an EMPTY loop, reported fresh, and left the previous run's CSS
/// on disk.
test "update_with_stdin_is_a_usage_error" {
    let dir = scratch("update-stdin");
    let r = run_bin(BIN(), dir, ["--stdin", "--update", "out.css"], ".a { color: red }\n");
    // "dart exits 64 here: {}", r.stderr
    assert.equal(r.code, 64);
    // "dart's wording: {}", r.stderr
    assert.is_true(r.stderr.includes("--update is not allowed with --stdin."));
    // "nothing should have been written"
    assert.is_true(!root.std.exists(root.std.path_join(dir, "out.css")))
}

/// A `-` INPUT is standard input too, and `--update` accepts it. Only the
/// `--stdin` FLAG is refused.
///
/// That asymmetry looks arbitrary until it is measured: dart-sass 1.104.1
/// exits 64 on `--stdin --update out.css`, and exits 0 on both
/// `--update - out.css` and `--update -:out.css`, compiling standard input
/// each time (2026-09-19). So the answer for a `-` input is not a refusal —
/// it is that the output can never be called fresh, because there is no
/// input mtime to compare it against, so every run rewrites. What makes that
/// true is `output_is_fresh` returning false for a `None` input; a version
/// that skipped the missing input instead looped over an empty dependency
/// list and reported FRESH.
test "update_with_a_dash_input_compiles_stdin_every_run" {
    let cases: root.std.Tuple2<string, string[]>[] = [
        root.std.Tuple2<string, string[]> {
            _0: "positional",
            _1: ["--no-source-map", "--update", "-", "out.css"],
        },
        root.std.Tuple2<string, string[]> {
            _0: "pair",
            _1: ["--no-source-map", "--update", "-:out.css"],
        },
    ];
    for (let c in cases) {
        let tag = c._0;
        let args = c._1;
        let dir = scratch(`update-dash-${tag}`);
        let first = run_bin(BIN(), dir, args, ".a { color: #111; }\n");
        // "{tag}: dart accepts a `-` input: {}", first.stderr
        assert.equal(first.code, 0);
        // "{tag}: first compile"
        assert.is_true(read(dir, "out.css").includes("#111"));

        // No input mtime means no honest "fresh": the second run must write
        // again even though nothing on disk changed.
        let stamp = root.std.expect(root.std.mtime_nanos(root.std.path_join(dir, "out.css")), "stat out.css");
        root.std.sleep_ms(1100);
        let second = run_bin(BIN(), dir, args, ".a { color: #222; }\n");
        // "{tag}: {}", second.stderr
        assert.equal(second.code, 0);
        // "{tag}: --update kept stale CSS for a stdin input: {}", read(&dir, "out.css")
        assert.is_true(read(dir, "out.css").includes("#222"));
        let after = root.std.expect(root.std.mtime_nanos(root.std.path_join(dir, "out.css")), "stat out.css");
        // "{tag}: --update claimed a stdin-fed output was fresh"
        assert.is_true(stamp != after);
    }
}

/// An output that is an existing DIRECTORY: `--update` skips it silently
/// where a plain compile fails with 66, and that is dart's behaviour, not an
/// oversight in the freshness check.
///
/// Measured 2026-09-19 against dart-sass 1.104.1: `sass --update e.scss:od`
/// exits 0 and writes nothing when `od` is newer than `e.scss`, and exits 66
/// with "Error reading od: illegal operation on a directory." when `od` is
/// older. Both of ours match in both directions, so dart is running the same
/// mtime comparison on the directory that we are. Requiring a regular file
/// before trusting the mtime would be a nicer CLI and a divergence.
test "update_with_a_directory_output_matches_dart" {
    // Directory NEWER than the source: nothing is written and the run succeeds.
    let dir = scratch("update-dirout-new");
    let _ = write(dir, "e.scss", ".a { color: red; }\n");
    root.std.sleep_ms(1100);
    // .expect("mkdir od")
    root.std.create_dir_all(root.std.path_join(dir, "od"));
    let fresh = sasso(dir, ["--no-source-map", "--update", "e.scss:od"]);
    // "dart exits 0 here: {}", fresh.stderr
    assert.equal(fresh.code, 0);
    // "the directory should be untouched and empty"
    assert.is_true(
        root.std.is_dir(root.std.path_join(dir, "od"))
            && (
                root.std.read_dir_names(root.std.path_join(dir, "od")) catch (e) {
                    _ => {
                        let none: string[] = [];
                        none
                    }
                }
            )
                .length()
                == 0,
    );

    // Directory OLDER than the source: the write is attempted, and fails.
    let dir = scratch("update-dirout-old");
    // .expect("mkdir od")
    root.std.create_dir_all(root.std.path_join(dir, "od"));
    root.std.sleep_ms(1100);
    let _ = write(dir, "e.scss", ".a { color: red; }\n");
    let stale = sasso(dir, ["--no-source-map", "--update", "e.scss:od"]);
    // "dart exits 66 here: {}", stale.stderr
    assert.equal(stale.code, 66)
}

/// `--update` with nowhere to write is dart's OTHER usage error, and the one
/// this CLI shipped without: `--update is not allowed when printing to
/// stdout.`, exit 64.
///
/// Found by reading dart's own `test/cli/shared/update.dart`, which has it
/// right next to the `--stdin` case. A run with no destination has no
/// output mtime to compare, so the flag cannot do anything; dart refuses
/// rather than quietly compile to the terminal as if `--update` were absent.
///
/// The boundary matters more than the message. Measured 2026-09-19 against
/// dart-sass 1.104.1: every shape that HAS a destination is accepted —
/// `t.scss out.css`, `t.scss:out.css`, several pairs at once, and even
/// `t.scss:-`, which is a file named `-`. Only the lone positional is
/// refused. `-o` and a bare directory are this CLI's own spellings of a
/// destination, have no dart equivalent to copy, and must stay allowed.
test "update_without_a_destination_is_a_usage_error" {
    let dir = scratch("update-no-dest");
    let _ = write(dir, "t.scss", "a {b: c}\n");

    let r = sasso(dir, ["--no-source-map", "--update", "t.scss"]);
    // "dart exits 64 here: {}", r.stderr
    assert.equal(r.code, 64);
    // "dart's wording: {}", r.stderr
    assert.is_true(r.stderr.includes("--update is not allowed when printing to stdout."));
    // "nothing should have been compiled: {}", r.stdout
    assert.is_true(r.stdout == "");

    // Everything that names somewhere to write still works.
    for (
        let args in [
            ["--no-source-map", "--update", "t.scss", "out.css"],
            ["--no-source-map", "--update", "t.scss:out.css"],
            ["--no-source-map", "--update", "-o", "out.css", "t.scss"],
        ]
    ) {
        let _ = root.std.remove_file(root.std.path_join(dir, "out.css")) catch (e) {
            _ => null
        };
        let ok = sasso(dir, args);
        // "{args:?} names a destination: {}", ok.stderr
        assert.equal(ok.code, 0);
        // "{args:?} wrote no CSS"
        assert.is_true(read(dir, "out.css").includes("b: c"));
    }
}

/// `--update` narrates: one line per file WRITTEN, on stdout, stamped with
/// the local time to the minute.
///
/// Measured against dart-sass 1.104.1 on 2026-09-19. Everything in this
/// test is a row of that table, and each row is a way the first attempt
/// could have been wrong:
///
///   written          `[YYYY-MM-DD HH:MM:SS] Compiled <src> to <dest>.`
///   skipped          silent — so a no-op `--update` says nothing at all
///   failed           silent — the error is the output, not a compile line
///   --quiet          suppressed
///   several pairs    one line each, in COMMAND-LINE order, not finish order
///   stream           stdout, never stderr: a build script greps for it
///
/// The stamp itself comes from `src/localtime`, which is tested against the
/// whole tz database separately; here only its SHAPE is asserted, because a
/// test that recomputed the expected time would be testing itself.
test "update_narrates_each_written_file" {
    let dir = scratch("update-narrate");
    let _ = write(dir, "one.scss", "a {b: c}\n");
    let _ = write(dir, "two.scss", "x {y: z}\n");

    let stamp = regex_lite_stamp; // see the helper below

    // A written file is announced, on stdout.
    let first = sasso(dir, ["--no-source-map", "--update", "one.scss:one.css"]);
    // "{}", first.stderr
    assert.equal(first.code, 0);
    // "the line belongs on stdout: {}", first.stderr
    assert.is_true(!first.stderr.includes("Compiled"));
    let line = root.std.trim_end(first.stdout);
    // "dart's wording: {line:?}"
    assert.is_true(line.ends_with("Compiled one.scss to one.css."));
    // Whether there is a stamp is a RUNTIME question, not `cfg!(unix)`.
    // Windows has no tz database to read, and neither does a nix build
    // sandbox, a scratch container, or a distroless image — all Unix, all
    // without `/etc/localtime`. The first version of this asserted a stamp
    // on every unix and was failed by nix, correctly.
    //
    // So the contract is what gets asserted: the text is always dart's, and
    // a stamp is either absent or well-formed — never malformed, never
    // wrong-shaped, never swallowing the message.
    if (line.starts_with("[")) {
        // "a stamp must be [YYYY-MM-DD HH:MM:SS]: {line:?}"
        assert.is_true(stamp(line));
    } else {
        // "with no local offset the line drops its stamp, not its content: {line:?}"
        assert.is_true(line.starts_with("Compiled"));
    }

    // A skipped file is silent — this is what makes a no-op build quiet.
    root.std.sleep_ms(1100);
    let again = sasso(dir, ["--no-source-map", "--update", "one.scss:one.css"]);
    // "{}", again.stderr
    assert.equal(again.code, 0);
    // "a skip must say nothing: {:?}", again.stdout
    assert.equal(again.stdout, "");

    // Several pairs: one line each, in the order the arguments were given.
    // Jobs finish in whatever order threads finish them in, so this is a
    // real assertion and not a tautology.
    let _ = root.std.remove_file(root.std.path_join(dir, "one.css")) catch (e) {
        _ => null
    };
    let both = sasso(dir, ["--no-source-map", "--update", "one.scss:one.css", "two.scss:two.css"]);
    // "{}", both.stderr
    assert.equal(both.code, 0);
    let lines = both.stdout.lines();
    // "one line per file: {:?}", both.stdout
    assert.equal(lines.length(), 2);
    // "{:?}", lines[0]
    assert.is_true(lines[0].ends_with("Compiled one.scss to one.css."));
    // "{:?}", lines[1]
    assert.is_true(lines[1].ends_with("Compiled two.scss to two.css."));

    // --quiet suppresses it.
    let _ = root.std.remove_file(root.std.path_join(dir, "one.css")) catch (e) {
        _ => null
    };
    let quiet = sasso(dir, ["--no-source-map", "--quiet", "--update", "one.scss:one.css"]);
    // "{}", quiet.stderr
    assert.equal(quiet.code, 0);
    // "--quiet means quiet: {:?}", quiet.stdout
    assert.equal(quiet.stdout, "");
    // "but it still compiles"
    assert.is_true(read(dir, "one.css").includes("b: c"));

    // A failure is not announced as a compile.
    let _ = write(dir, "bad.scss", "@use \"nope\";\n");
    let failed = sasso(dir, ["--no-source-map", "--update", "bad.scss:bad.css"]);
    // "a missing module is an error"
    assert.is_true(failed.code != 0);
    // "a failed compile must not claim success: {:?}", failed.stdout
    assert.is_true(!failed.stdout.includes("Compiled"))
}

/// A stdin source is announced as `stdin`, not as `-`.
///
/// The `Compiled …` line names `unit.source_path()`, which is `None` for
/// standard input, and the `None` arm substitutes the word dart uses. The
/// dash tests either side of this one check CSS and mtimes, and the
/// narration test uses file inputs, so nothing here would have noticed the
/// line printing `-` — measured against dart-sass 1.104.1 on 2026-09-19,
/// which prints `Compiled stdin to o.css.`
test "update_narrates_a_stdin_source_as_stdin" {
    let dir = scratch("update-narrate-stdin");
    let r = run_bin(BIN(), dir, ["--no-source-map", "--update", "-:o.css"], "a {b: c}\n");
    // "{}", r.stderr
    assert.equal(r.code, 0);
    let line = root.std.trim_end(r.stdout);
    // "dart names standard input `stdin`, not `-`: {line:?}"
    assert.is_true(line.ends_with("Compiled stdin to o.css."));
    // "the source path leaked as a dash: {line:?}"
    assert.is_true(!line.includes("Compiled - to"))
}

/// `[YYYY-MM-DD HH:MM:SS] ` at the start of a line, without pulling in a
/// regex engine for one shape. A wrong-but-plausible stamp is caught by
/// `src/localtime`'s own tests against the tz database; what matters here is
/// that a stamp is present and correctly shaped.
///
/// Seconds included: dart's native build prints them and its dart2js build
/// truncates them away by accident (#190, and `local_stamp`'s docs).
function regex_lite_stamp(line: string) -> bool {
    let b = line.to_utf8();
    // `[2026-09-19 13:29:07] ` — the bracket closes at 20, the space follows.
    if (
        b.length() < 22
            || b[0] != root.std.ord("[")
            || b[20] != root.std.ord("]")
            || b[21] != root.std.ord(" ")
    ) {
        return false;
    }
    let digits = [1, 2, 3, 4, 6, 7, 9, 10, 12, 13, 15, 16, 18, 19];
    let punct: root.std.Tuple2<int, string>[] = [
        root.std.Tuple2<int, string> { _0: 5, _1: "-" },
        root.std.Tuple2<int, string> { _0: 8, _1: "-" },
        root.std.Tuple2<int, string> { _0: 11, _1: " " },
        root.std.Tuple2<int, string> { _0: 14, _1: ":" },
        root.std.Tuple2<int, string> { _0: 17, _1: ":" },
    ];
    // PORT: `u8::is_ascii_digit` on a byte → a range check on its value.
    digits.every((i) -> {
        b[i] >= root.std.ord("0") && b[i] <= root.std.ord("9")
    })
        && punct.every((p) -> {
            b[p._0] == root.std.ord(p._1)
        })
}

/// `--watch`'s three usage refusals, each measured against dart-sass 1.104.1
/// on 2026-09-20: same wording, same exit code as dart's, and the same shape
/// as `--update`'s two.
test "watch_refuses_what_dart_refuses" {
    let dir = scratch("watch_usage");
    let _ = write(dir, "a.scss", ".a { b: 1 }\n");
    let cases: root.std.Tuple2<string[], string>[] = [
        root.std.Tuple2<string[], string> {
            _0: ["--watch", "a.scss"],
            _1: "--watch is not allowed when printing to stdout.",
        },
        root.std.Tuple2<string[], string> {
            _0: ["--watch", "--stdin"],
            _1: "--watch is not allowed with --stdin.",
        },
        root.std.Tuple2<string[], string> {
            _0: ["--poll", "a.scss:a.css"],
            _1: "--poll may not be passed without --watch.",
        },
    ];
    for (let c in cases) {
        let args = c._0;
        let message = c._1;
        let r = sasso(dir, args);
        // "{args:?} should be a usage error: {}", r.stderr
        assert.equal(r.code, 64);
        // "{args:?}: wanted {message:?}, got {:?}", &r.stderr[..r.stderr.len().min(120)]
        assert.is_true(r.stderr.includes(message));
    }
    // `--poll` and `--no-poll` are accepted WITH `--watch` — they choose
    // between a native watcher and repeated stats, and we only have the
    // second, so both are no-ops rather than errors. Checked through the
    // usage layer alone (a real `--watch` never exits) by pairing them with
    // a second refusal: reaching the stdin message means `--poll` itself got
    // through.
    for (let flag in ["--poll", "--no-poll"]) {
        let r = sasso(dir, [flag, "--watch", "--stdin"]);
        // "{flag}: {}", r.stderr
        assert.equal(r.code, 64);
        // "{flag} should be accepted beside --watch, got {:?}", &r.stderr[..r.stderr.len().min(120)]
        assert.is_true(r.stderr.includes("--watch is not allowed with --stdin."));
    }
    baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    }
}

/// A real watch session: it compiles, it notices a dependency change, it
/// reports a break without dying, and it recovers.
///
/// Spawned rather than `sasso()`d because `--watch` never exits — the point
/// of the flag. Timeouts are generous: this asserts that the events HAPPEN,
/// not how fast, which is `bench/watch.md`'s job.
test "watch_recompiles_reports_and_recovers" {
    // PORT: `std::process::Command::spawn` → `baml.sys.start_process`. Its
    // stdout is always a pipe, so here and in the watch tests below
    // `Stdio::null()` for stdout is a pipe left unread (the output is a few
    // lines); `Stdio::null()` for stderr → `StderrMode.Discard`. `Instant` →
    // `root.std.now_nanos()`.
    let dir = scratch("watch_cycle");
    let _ = write(dir, "src/main.scss", "@use \"v\";\n.a { color: v.$c; }\n");
    let _ = write(dir, "src/_v.scss", "$c: red;\n");

    // .expect("spawn --watch")
    let child = baml.sys.start_process(
        BIN(),
        ["--no-source-map", "--watch", "src/main.scss", "out.css"],
        baml.sys.ProcessOptions {
            cwd: dir,
            env: null,
            timeout_ms: null,
            stdin: null,
            stderr: baml.sys.StderrMode.Pipe,
        },
    );

    let out = root.std.path_join(dir, "out.css");
    let css = () -> string {
        root.std.read_to_string(out) catch (e) {
            _ => ""
        }
    };
    let until = (pred: () -> bool throws unknown) -> bool {
        let deadline = root.std.now_nanos() + 20000000000n;
        while (root.std.now_nanos() < deadline) {
            if (pred()) {
                return true;
            }
            root.std.sleep_ms(20);
        }
        false
    };

    // A save's CSS arrives from the PROVISIONAL run and its narration from the
    // authoritative one a window later, so a step that waits on the file has
    // not waited for the line. Long enough for the catch-up, short enough to
    // keep the test quick.
    // PORT: 400 ms → 2000 ms. The port's `Stamp::of` runs `stat(1)` for every
    // followed path, so a sweep costs milliseconds rather than microseconds
    // and `next_interval` sits at its 500 ms ceiling: the authoritative
    // catch-up lands up to ~interval + compile after the provisional CSS
    // (measured 0.4–0.55 s idle, more with the suite running beside it),
    // where the Rust binary's lands ~60 ms after it.
    let settle = () -> void {
        root.std.sleep_ms(2000);
    };

    let stdout = "";
    // PORT: `catch_unwind` + cleanup + `resume_unwind` → a `defer` that runs
    // the same cleanup whether or not an assertion panics on the way out.
    {
        defer {
            let _ = child.kill() catch (e) {
                _ => null
            };
            stdout = root.std.from_utf8_lossy(child.stdout.bytes() catch (e) {
                _ => b""
            });
            let _ = child.wait() catch (e) {
                _ => null
            };
            let _ = baml.fs.remove_dir_all(dir) catch (e) {
                _ => null
            };
        }
        // "the first compile never landed"
        assert.is_true(
            until(() -> bool {
                css().includes("red")
            }),
        );
        settle();

        root.std.write_file(root.std.path_join(dir, "src/_v.scss"), "$c: navy;\n");
        // "a changed dependency was never noticed: {:?}", css()
        assert.is_true(
            until(() -> bool {
                css().includes("navy")
            }),
        );
        settle();

        // A break: error CSS replaces the output and the watch keeps running.
        root.std.write_file(root.std.path_join(dir, "src/_v.scss"), "$c: ;\n");
        // "a broken dependency produced no error CSS: {:?}", css()
        assert.is_true(
            until(() -> bool {
                css().starts_with("/* Error:")
            }),
        );
        settle();

        // Fixed back to EXACTLY what it was before the break. The npm CLI had
        // this bug (#159): a cache of the last good CSS matched, the write was
        // skipped, and the page stayed broken.
        root.std.write_file(root.std.path_join(dir, "src/_v.scss"), "$c: navy;\n");
        // "fixing it back to the same value left the error CSS: {:?}", css()
        assert.is_true(
            until(() -> bool {
                css().includes("navy")
            }),
        );
        settle();
    };

    // dart prints the banner before the first compile and one line per file
    // actually written; `--quiet` suppresses the lines but not the banner.
    // "banner missing: {stdout:?}"
    assert.is_true(stdout.starts_with("Sass is watching for changes. Press Ctrl-C to stop.\n\n"));
    let compiled = stdout.lines()
        .filter((l) -> {
            l.includes("Compiled")
        })
        .length();
    // "one line per successful write — first, change, recovery: {stdout:?}"
    assert.is_true(compiled >= 3);
    // …and a failed compile is silent on stdout, so the broken save added
    // none of them.
    // "a failed compile must not be narrated, and a provisional run must not
    // narrate a second time: {stdout:?}"
    assert.is_true(compiled <= 4)
}

/// The output written INTO a directory the watch follows, which is the
/// ordinary layout — `main.scss` and `main.css` side by side.
///
/// The poll follows the directories of everything it loaded, so that a
/// dependency which does not exist YET can arrive. That makes the output's
/// own write a candidate change: creating a file moves its directory's
/// mtime, and a compile that provokes the next compile never stops. The
/// npm CLI needs an explicit "these files are ours" set for the same reason.
///
/// It does not happen, and the reason is worth pinning: the snapshot is
/// taken AFTER the compile, so a write that has already landed is already
/// accounted for, and writing an existing file again does not touch its
/// directory. This checks the whole of that, including the churn that does
/// move a directory's mtime — `--no-error-css` deletes the output on a
/// failure and the next success recreates it.
test "watch_does_not_trigger_itself" {
    let dir = scratch("watch_selftrigger");
    let _ = write(dir, "main.scss", "@use \"v\";\n.a { color: v.$c; }\n");
    let _ = write(dir, "_v.scss", "$c: red;\n");

    // .expect("spawn --watch")
    let child = baml.sys.start_process(
        BIN(),
        ["--no-source-map", "--no-error-css", "--watch", "main.scss", "main.css"],
        baml.sys.ProcessOptions {
            cwd: dir,
            env: null,
            timeout_ms: null,
            stdin: null,
            stderr: baml.sys.StderrMode.Discard,
        },
    );

    let out = root.std.path_join(dir, "main.css");
    let css = () -> string {
        root.std.read_to_string(out) catch (e) {
            _ => ""
        }
    };
    let until = (pred: () -> bool throws unknown) -> bool {
        let deadline = root.std.now_nanos() + 20000000000n;
        while (root.std.now_nanos() < deadline) {
            if (pred()) {
                return true;
            }
            root.std.sleep_ms(20);
        }
        false
    };

    // PORT: `catch_unwind` + cleanup + `resume_unwind` → `defer`.
    {
        defer {
            let _ = child.kill() catch (e) {
                _ => null
            };
            let _ = child.wait() catch (e) {
                _ => null
            };
            let _ = baml.fs.remove_dir_all(dir) catch (e) {
                _ => null
            };
        }
        // "the first compile never landed"
        assert.is_true(
            until(() -> bool {
                css().includes("red")
            }),
        );
        // Break it, so the output is DELETED, then fix it, so it is created
        // again — the sequence that moves the directory's mtime twice.
        root.std.write_file(root.std.path_join(dir, "_v.scss"), "$c: ;\n");
        // "--no-error-css should remove the output"
        assert.is_true(
            until(() -> bool {
                css() == ""
            }),
        );
        root.std.write_file(root.std.path_join(dir, "_v.scss"), "$c: teal;\n");
        // "and put it back"
        assert.is_true(
            until(() -> bool {
                css().includes("teal")
            }),
        );
        // Now leave it alone. An mtime that moves after this one is the
        // watch answering itself.
        // PORT: 600 ms → 2000 ms, for the same reason as the `settle` in
        // `watch_recompiles_reports_and_recovers`: the port's poll interval
        // sits at its 500 ms ceiling, so the authoritative catch-up that
        // rewrites the provisional run's `main.css` can land later than
        // 600 ms after it — and that write is not the watch answering itself.
        root.std.sleep_ms(2000);
        let settled = root.std.mtime_nanos(out);
        root.std.sleep_ms(2000);
        let later = root.std.mtime_nanos(out);
        // "the watch recompiled with nothing to recompile"
        assert.equal(settled, later)
    }
}

/// A dependency that does not exist yet, in a SUBDIRECTORY.
///
/// Nothing in `sub/` was ever read, so `sub/` is in no compile's dependency
/// list and following the directories of what WAS loaded does not reach it.
/// Creating `sub/_new.scss` then changes a directory nobody is looking at and
/// the watch never recovers — measured before the fix: NEVER SEEN.
///
/// The urls that resolved to nothing are recorded now, and the directory each
/// of them names is followed even though it does not exist. Polling makes
/// that cheap: a missing path stamps as missing, compares equal to itself,
/// and becomes a change the moment it appears.
test "watch_recovers_when_a_missing_dependency_arrives_in_a_subdirectory" {
    let dir = scratch("watch_subdir");
    root.std.create_dir_all(root.std.path_join(dir, "sub"));
    let _ = write(dir, "main.scss", "@use \"sub/new\";\n.a { b: 1 }\n");

    // .expect("spawn --watch")
    let child = baml.sys.start_process(
        BIN(),
        ["--no-source-map", "--watch", "main.scss", "out.css"],
        baml.sys.ProcessOptions {
            cwd: dir,
            env: null,
            timeout_ms: null,
            stdin: null,
            stderr: baml.sys.StderrMode.Discard,
        },
    );

    let out = root.std.path_join(dir, "out.css");
    let css = () -> string {
        root.std.read_to_string(out) catch (e) {
            _ => ""
        }
    };
    let until = (pred: () -> bool throws unknown) -> bool {
        let deadline = root.std.now_nanos() + 20000000000n;
        while (root.std.now_nanos() < deadline) {
            if (pred()) {
                return true;
            }
            root.std.sleep_ms(20);
        }
        false
    };

    // PORT: `catch_unwind` + cleanup + `resume_unwind` → `defer`.
    {
        defer {
            let _ = child.kill() catch (e) {
                _ => null
            };
            let _ = child.wait() catch (e) {
                _ => null
            };
            let _ = baml.fs.remove_dir_all(dir) catch (e) {
                _ => null
            };
        }
        // "the unresolved @use should have produced error CSS: {:?}", css()
        assert.is_true(
            until(() -> bool {
                css().starts_with("/* Error:")
            }),
        );
        root.std.sleep_ms(300);
        root.std.write_file(root.std.path_join(dir, "sub/_new.scss"), "$x: 1;\n");
        // "the dependency arrived in a directory nothing was following: {:?}", css()
        assert.is_true(
            until(() -> bool {
                css().includes("b: 1")
            }),
        )
    }
}

/// `--watch --update`: the freshness check applies to the first compile and
/// never again.
///
/// After that, the output it compares against is one this session wrote — so
/// a provisional run that caught a save half-written, succeeded, and wrote
/// the wrong CSS makes its own output look up to date, and the authoritative
/// run behind it skips the write that would have fixed it. Measured before
/// this: writing `$c: bl` and finishing `ue;` 400 ms into a 680 ms compile
/// left 6 of 6 runs stuck on `color: bl` forever.
///
/// Reproducing that race needs a compile slow enough to write into and an
/// offset inside it, and neither survives a machine of a different speed. So
/// the test asserts the RULE instead, with no race and no clock in it.
///
/// Overwrite the OUTPUT, which makes it the newest file in the tree and so
/// exactly what a freshness check still in force reads as "nothing to do",
/// and then provoke a compile with something the check does not look at: a
/// new file in a watched directory. Nothing here needs a timestamp set by
/// hand — `File::set_modified` is 1.75 and this crate's MSRV is 1.74 — and
/// the two steps cannot race, because overwriting an existing file does not
/// move its directory's mtime and so provokes nothing on its own.
test "watch_stops_applying_update_after_the_first_compile" {
    let dir = scratch("watch_update");
    let _ = write(dir, "main.scss", "@use \"v\";\n.a { color: v.$c; }\n");
    let _ = write(dir, "_v.scss", "$c: red;\n");

    // .expect("spawn --watch --update")
    let child = baml.sys.start_process(
        BIN(),
        ["--no-source-map", "--watch", "--update", "main.scss", "out.css"],
        baml.sys.ProcessOptions {
            cwd: dir,
            env: null,
            timeout_ms: null,
            stdin: null,
            stderr: baml.sys.StderrMode.Discard,
        },
    );

    let out = root.std.path_join(dir, "out.css");
    let css = () -> string {
        root.std.read_to_string(out) catch (e) {
            _ => ""
        }
    };
    let until = (pred: () -> bool throws unknown) -> bool {
        let deadline = root.std.now_nanos() + 20000000000n;
        while (root.std.now_nanos() < deadline) {
            if (pred()) {
                return true;
            }
            root.std.sleep_ms(20);
        }
        false
    };

    // PORT: `catch_unwind` + cleanup + `resume_unwind` → `defer`.
    {
        defer {
            let _ = child.kill() catch (e) {
                _ => null
            };
            let _ = child.wait() catch (e) {
                _ => null
            };
            let _ = baml.fs.remove_dir_all(dir) catch (e) {
                _ => null
            };
        }
        // "the first compile never landed"
        assert.is_true(
            until(() -> bool {
                css().includes("red")
            }),
        );
        root.std.sleep_ms(300);

        // Junk, written LAST, so the output is now newer than every input —
        // the state a freshness check can only read as "up to date".
        root.std.write_file(out, "/* stale */\n");
        // …and a reason to compile that the freshness check does not look
        // at. A new file in a watched directory moves that directory's
        // mtime; overwriting `out.css` above moved nothing, so these two
        // steps cannot arrive in the wrong order.
        root.std.write_file(root.std.path_join(dir, "newcomer.scss"), "// hello\n");

        // "--update's freshness check is still deciding, against an output
        // this watch wrote itself: {:?}", css()
        assert.is_true(
            until(() -> bool {
                css().includes("red")
            }),
        )
    }
}

/// A watch whose entry cannot be READ still follows it, so the fix is
/// noticed. Nothing else is left to follow in that state: there are no
/// loaded dependencies, and a compile that never started recorded none.
test "watch_recovers_when_the_entry_itself_comes_back" {
    let dir = scratch("watch_entry_gone");
    let _ = write(dir, "main.scss", ".a { b: 1 }\n");

    // .expect("spawn --watch")
    let child = baml.sys.start_process(
        BIN(),
        ["--no-source-map", "--watch", "main.scss", "out.css"],
        baml.sys.ProcessOptions {
            cwd: dir,
            env: null,
            timeout_ms: null,
            stdin: null,
            stderr: baml.sys.StderrMode.Discard,
        },
    );

    let out = root.std.path_join(dir, "out.css");
    let css = () -> string {
        root.std.read_to_string(out) catch (e) {
            _ => ""
        }
    };
    let until = (pred: () -> bool throws unknown) -> bool {
        let deadline = root.std.now_nanos() + 20000000000n;
        while (root.std.now_nanos() < deadline) {
            if (pred()) {
                return true;
            }
            root.std.sleep_ms(20);
        }
        false
    };

    // PORT: `catch_unwind` + cleanup + `resume_unwind` → `defer`.
    {
        defer {
            let _ = child.kill() catch (e) {
                _ => null
            };
            let _ = child.wait() catch (e) {
                _ => null
            };
            let _ = baml.fs.remove_dir_all(dir) catch (e) {
                _ => null
            };
        }
        // "the first compile never landed"
        assert.is_true(
            until(() -> bool {
                css().includes("b: 1")
            }),
        );
        root.std.sleep_ms(300);
        root.std.remove_file(root.std.path_join(dir, "main.scss"));
        root.std.sleep_ms(500);
        root.std.write_file(root.std.path_join(dir, "main.scss"), ".a { b: 2 }\n");
        // "the entry came back and nothing noticed: {:?}", css()
        assert.is_true(
            until(() -> bool {
                css().includes("b: 2")
            }),
        )
    }
}

/// A watch whose OUTPUT is one of its own sources.
///
/// `sasso main.scss main.scss` replaces a stylesheet with its own CSS, and
/// dart does that too for a one-shot compile — so it is not ours to change
/// there. Under `--watch` dart declines, and why is visible the moment you
/// try it: the write is a change, the change is a compile, the compile
/// writes again. Measured before this, 2.5 seconds of
/// `--watch main.scss main.scss`:
///
///   dart     Compiled x0   sources untouched
///   npm      Compiled x0   sources untouched
///   binary   Compiled x24  sources DESTROYED
///
/// The same rule covers an output that is a DEPENDENCY rather than the
/// entry (`main.scss _v.scss`), which does not loop but does overwrite a
/// file the compile read.
test "watch_declines_to_write_over_a_source" {
    let cases: root.std.Tuple2<string, string>[] = [
        root.std.Tuple2<string, string> { _0: "main.scss", _1: "main.scss" },
        root.std.Tuple2<string, string> { _0: "main.scss", _1: "_v.scss" },
    ];
    for (let c in cases) {
        let entry = c._0;
        let output = c._1;
        let dir = scratch("watch_selfoutput");
        let SRC = "@use \"v\";\n.a { color: v.$c; }\n";
        let DEP = "$c: red;\n";
        let _ = write(dir, "main.scss", SRC);
        let _ = write(dir, "_v.scss", DEP);

        // .expect("spawn --watch")
        let child = baml.sys.start_process(
            BIN(),
            ["--no-source-map", "--watch", entry, output],
            baml.sys.ProcessOptions {
                cwd: dir,
                env: null,
                timeout_ms: null,
                stdin: null,
                stderr: baml.sys.StderrMode.Discard,
            },
        );

        root.std.sleep_ms(1500);
        let _ = child.kill() catch (e) {
            _ => null
        };
        let stdout = root.std.from_utf8_lossy(
            child.stdout.bytes() catch (e) {
                _ => b""
            },
        );
        let _ = child.wait() catch (e) {
            _ => null
        };

        let main_now = read(dir, "main.scss");
        let dep_now = read(dir, "_v.scss");
        let _ = baml.fs.remove_dir_all(dir) catch (e) {
            _ => null
        };

        // "{entry} {output}: the entry was overwritten"
        assert.equal(main_now, SRC);
        // "{entry} {output}: the dependency was overwritten"
        assert.equal(dep_now, DEP);
        let compiled = stdout.lines()
            .filter((l) -> {
                l.includes("Compiled")
            })
            .length();
        // "{entry} {output}: dart is silent here and writes nothing; we said {compiled} times"
        assert.equal(compiled, 0);
    }
}

/// The output is a SYMLINK to a source: two names, one file, and a lexical
/// comparison sees only the names.
///
/// This is a DELIBERATE divergence from dart, which is why it is here with
/// the measurement rather than folded into the case above.
/// `--watch main.scss out.css` with `out.css -> main.scss`:
///
///   dart     declines 26 times in 29, and DESTROYS the stylesheet 3
///   npm      declines                                          (#168)
///   binary   Compiled x23  the source is DESTROYED             (before)
///
/// The dart row said "Compiled x1, DESTROYED" here until 2026-09-22, from
/// a single run. It has a guard and the guard is RACY: 29 runs, three of
/// them lost the file. So the divergence is not that dart allows this and
/// we do not — it is that dart decides it by a coin toss and we decide it
/// every time. #168 carried the npm half.
test "watch_declines_to_write_over_a_source_reached_through_a_symlink" {
    let dir = scratch("watch_symlink_out");
    let SRC = "@use \"v\";\n.a { color: v.$c; }\n";
    let _ = write(dir, "main.scss", SRC);
    let _ = write(dir, "_v.scss", "$c: red;\n");
    // #[cfg(unix)] (the Windows `symlink_file` branch is not ported).
    baml.fs.symlink(root.std.path_join(dir, "main.scss"), root.std.path_join(dir, "out.css"));

    // .expect("spawn --watch")
    let child = baml.sys.start_process(
        BIN(),
        ["--no-source-map", "--watch", "main.scss", "out.css"],
        baml.sys.ProcessOptions {
            cwd: dir,
            env: null,
            timeout_ms: null,
            stdin: null,
            stderr: baml.sys.StderrMode.Discard,
        },
    );

    root.std.sleep_ms(1500);
    let _ = child.kill() catch (e) {
        _ => null
    };
    let stdout = root.std.from_utf8_lossy(
        child.stdout.bytes() catch (e) {
            _ => b""
        },
    );
    let _ = child.wait() catch (e) {
        _ => null
    };

    let now = read(dir, "main.scss");
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    };
    // "the stylesheet was overwritten through the symlink"
    assert.equal(now, SRC);
    let compiled = stdout.lines()
        .filter((l) -> {
            l.includes("Compiled")
        })
        .length();
    // "nothing was written, so nothing is narrated: {stdout:?}"
    assert.equal(compiled, 0)
}

/// The alias guard on the FAILURE path: a broken save when the output is
/// one of the sources.
///
/// The success arm declined to write there; `finish_compile_error` did not,
/// so the error stylesheet — or, under `--no-error-css`, a deletion — landed
/// on the entry. Measured before this: `--watch main.scss main.scss`, then
/// break a dependency, and the stylesheet is gone. Skipping the successful
/// write and then destroying the file on the next typo is worse than either
/// alone.
test "watch_declines_to_write_error_css_over_a_source" {
    let extras: (string?)[] = [null, "--no-error-css"];
    for (let extra in extras) {
        let dir = scratch("watch_errorcss_alias");
        let SRC = "@use \"v\";\n.a { color: v.$c; }\n";
        let _ = write(dir, "main.scss", SRC);
        let _ = write(dir, "_v.scss", "$c: red;\n");

        let args = ["--no-source-map"];
        if (extra != null) {
            args.push(extra);
        }
        root.std.extend(args, ["--watch", "main.scss", "main.scss"]);
        // .expect("spawn --watch")
        let child = baml.sys.start_process(
            BIN(),
            args,
            baml.sys.ProcessOptions {
                cwd: dir,
                env: null,
                timeout_ms: null,
                stdin: null,
                stderr: baml.sys.StderrMode.Discard,
            },
        );

        root.std.sleep_ms(700);
        // Break it: the compile now fails, and the failure path used to
        // write the error stylesheet at the output — which is the entry.
        root.std.write_file(root.std.path_join(dir, "_v.scss"), "$c: ;\n");
        root.std.sleep_ms(1200);

        let _ = child.kill() catch (e) {
            _ => null
        };
        let _ = child.wait() catch (e) {
            _ => null
        };
        let now = read(dir, "main.scss");
        let _ = baml.fs.remove_dir_all(dir) catch (e) {
            _ => null
        };
        // "{args:?}: the entry was overwritten by the failure path"
        assert.equal(now, SRC);
    }
}

/// A dependency that exists and cannot be READ, then can.
///
/// Two things had to be true for this to work and neither was. The importer
/// reports a permission failure as an error, and the `?` returned before the
/// file's stamp was taken — so nothing followed it. And `chmod` moves no
/// mtime, no length and no byte, so even once followed the stamp was
/// identical before and after. Measured before: the fix was NEVER SEEN, a
/// permanent dead end rather than a delay.
test "watch_recovers_when_a_dependency_becomes_readable" {
    // #[cfg(unix)]
    let dir = scratch("watch_unreadable");
    let _ = write(dir, "main.scss", "@use \"v\";\n.a { color: v.$c; }\n");
    let dep = write(dir, "_v.scss", "$c: red;\n");
    baml.fs.chmod(dep, 0o000);

    // .expect("spawn --watch")
    let child = baml.sys.start_process(
        BIN(),
        ["--no-source-map", "--watch", "main.scss", "out.css"],
        baml.sys.ProcessOptions {
            cwd: dir,
            env: null,
            timeout_ms: null,
            stdin: null,
            stderr: baml.sys.StderrMode.Discard,
        },
    );

    let out = root.std.path_join(dir, "out.css");
    let css = () -> string {
        root.std.read_to_string(out) catch (e) {
            _ => ""
        }
    };
    let until = (pred: () -> bool throws unknown) -> bool {
        let deadline = root.std.now_nanos() + 20000000000n;
        while (root.std.now_nanos() < deadline) {
            if (pred()) {
                return true;
            }
            root.std.sleep_ms(20);
        }
        false
    };

    // PORT: `catch_unwind` + cleanup + `resume_unwind` → `defer`.
    {
        defer {
            let _ = child.kill() catch (e) {
                _ => null
            };
            let _ = child.wait() catch (e) {
                _ => null
            };
            let _ = baml.fs.chmod(dep, 0o644) catch (e) {
                _ => null
            };
            let _ = baml.fs.remove_dir_all(dir) catch (e) {
                _ => null
            };
        }
        // "an unreadable dependency should fail the compile: {:?}", css()
        assert.is_true(
            until(() -> bool {
                css().starts_with("/* Error:")
            }),
        );
        root.std.sleep_ms(300);
        baml.fs.chmod(dep, 0o644);
        // "the dependency became readable and nothing noticed: {:?}", css()
        assert.is_true(
            until(() -> bool {
                css().includes("red")
            }),
        )
    }
}

/// The output aliases a dependency that FAILED to load.
///
/// The alias guard was given the successful loads only, and a dependency
/// that exists and cannot be parsed or read is not one of those — so the
/// failure path wrote the error stylesheet describing the problem on top of
/// the file that had it.
///
/// Invalid UTF-8 rather than a permission bit, because the file has to stay
/// writable for the bug to be reachable at all: a `chmod 000` dependency
/// cannot be overwritten either way, and would pass this test for the wrong
/// reason.
test "watch_declines_to_write_over_a_dependency_that_failed_to_load" {
    let dir = scratch("watch_alias_failed");
    let _ = write(dir, "main.scss", "@use \"v\";\n.a { color: v.$c; }\n");
    let dep = root.std.path_join(dir, "_v.scss");
    // Valid SCSS, invalid UTF-8: the importer reports an error rather than
    // a miss.
    let bytes = b"$c: \xff\xfe;\n";
    let f = baml.fs.open(dep, "w");
    let _ = f.write(bytes);
    let _ = f.close();

    // .expect("spawn --watch")
    let child = baml.sys.start_process(
        BIN(),
        ["--no-source-map", "--watch", "main.scss", "_v.scss"],
        baml.sys.ProcessOptions {
            cwd: dir,
            env: null,
            timeout_ms: null,
            stdin: null,
            stderr: baml.sys.StderrMode.Discard,
        },
    );

    root.std.sleep_ms(1200);
    let _ = child.kill() catch (e) {
        _ => null
    };
    let _ = child.wait() catch (e) {
        _ => null
    };

    let now = root.std.read_bytes(dep) catch (e) {
        _ => b""
    };
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    };
    // "the dependency was overwritten by the error stylesheet about it"
    assert.equal(now, bytes)
}

/// A file arriving at the OUTPUT's own path is still seen.
///
/// `--no-error-css` on a failing compile removes the output, and a removal
/// that really removed something is recorded so the watch does not answer
/// its own write. A removal of a file that was never there must NOT be:
/// `Snapshot::follow` puts a recorded name into the directory's `minus` set
/// and never takes it out, so one bogus record would hide that filename for
/// the rest of the run.
///
/// Reachable because `@use "out"` resolves to `out.css` as a plain CSS
/// module, so the arriving file is both a dependency and the output path.
/// The first unit then declines to write over a file that is its own source
/// — deliberately, and silently — which is why the recompile is observed
/// through a second unit's narration rather than through `out.css`.
test "watch_sees_a_file_arrive_at_the_output_path" {
    let dir = scratch("watch_arrival_at_output");
    let _ = write(dir, "main.scss", "@use \"out\";\n.a { color: red; }\n");
    let _ = write(dir, "other.scss", ".z { color: green; }\n");

    let log = root.std.path_join(dir, "log.txt");
    let log_file = baml.fs.open(log, "w");
    // .expect("spawn --watch")
    let child = baml.sys.start_process(
        BIN(),
        [
            "--no-source-map",
            "--no-error-css",
            "--watch",
            "main.scss:out.css",
            "other.scss:other.css",
        ],
        baml.sys.ProcessOptions {
            cwd: dir,
            env: null,
            timeout_ms: null,
            stdin: null,
            stderr: baml.sys.StderrMode.Discard,
        },
    );
    // PORT: `.stdout(Stdio::from(File::create(&log)))` — a BAML child's
    // stdout is always a pipe, so a task copies it into `log.txt` as it
    // arrives; it ends at the pipe's EOF, once the child is killed.
    let pump = spawn {
        while let chunk: uint8array = child.stdout.read(65536) catch (e) {
            _ => null
        } {
            let _ = log_file.write(chunk) catch (e) {
                _ => 0
            };
            let _ = log_file.flush() catch (e) {
                _ => null
            };
        }
        let _ = log_file.close() catch (e) {
            _ => null
        };
        null
    };

    let compiled = () -> int {
        (
            root.std.read_to_string(log) catch (e) {
                _ => ""
            }
        )
            .lines()
            .filter((l) -> {
                l.includes("Compiled other.scss")
            })
            .length()
    };
    let until = (pred: () -> bool throws unknown) -> bool {
        let deadline = root.std.now_nanos() + 20000000000n;
        while (root.std.now_nanos() < deadline) {
            if (pred()) {
                return true;
            }
            root.std.sleep_ms(20);
        }
        false
    };

    // PORT: `catch_unwind` + cleanup + `resume_unwind` → `defer`.
    {
        defer {
            let _ = child.kill() catch (e) {
                _ => null
            };
            let _ = child.wait() catch (e) {
                _ => null
            };
            let _ = await pump;
            let _ = baml.fs.remove_dir_all(dir) catch (e) {
                _ => null
            };
        }
        // main.scss fails — `out.css` does not exist — and `--no-error-css`
        // asks to remove an output that was never there. other.scss compiles.
        // "the first compile never landed"
        assert.is_true(
            until(() -> bool {
                compiled() >= 1
            }),
        );
        root.std.sleep_ms(400);

        // The missing dependency appears, at the output's own path. Nothing
        // else is touched: the only change on disk is that one file.
        root.std.write_file(root.std.path_join(dir, "out.css"), ".b { color: blue; }\n");
        // "the watch went blind to its own output's filename"
        assert.is_true(
            until(() -> bool {
                compiled() >= 2
            }),
        )
    }
}

/// `--no-error-css` could not remove the stale output: SAID, not adjudicated.
///
/// The exit code answers what went wrong. Under `--no-error-css` there is no
/// output to produce, so a cleanup that fails does not change the verdict on
/// the stylesheet — and dart agrees, twice over. Measured 2026-09-23 against
/// 1.104.1, a stale output whose holding directory is read-only:
///
///   dart     65   says nothing about the removal
///   binary   66   says it                          (before this)
///   npm      65   says it                          (#181)
///
/// dart does ATTEMPT the removal rather than skipping it — with a writable
/// directory all three delete the stale file and all three exit 65 — so this
/// was dart swallowing the failure, not declining to try.
///
/// The message stays. Telling someone their stale output is still there is
/// worth saying; it is making it the run's answer that diverged.
///
/// Read-only DIRECTORY rather than a read-only file: `unlink` asks the
/// directory for permission, not the file, so `chmod 000 out.css` removes
/// perfectly well and would pass this test for the wrong reason.
test "a_failed_no_error_css_removal_is_reported_but_not_the_verdict" {
    // #[cfg(unix)]
    let dir = scratch("no_error_css_removal");
    let _ = write(dir, "bad.scss", ".bad { a: 1px + #fff; }\n");
    root.std.create_dir_all(root.std.path_join(dir, "out"));
    root.std.write_file(root.std.path_join(dir, "out/o.css"), "/* stale */\n");
    baml.fs.chmod(root.std.path_join(dir, "out"), 0o555);

    let r = sasso(dir, ["--no-source-map", "--no-error-css", "bad.scss:out/o.css"]);

    // Everything the assertions need, taken before the tree goes. A
    // failing assertion must not leave a scratch directory behind — this
    // one measured six of them in `$TMPDIR` before the cleanup — and the
    // permissions have to be put back first or `remove_dir_all` cannot
    // get into `out/`.
    let survived = root.std.exists(root.std.path_join(dir, "out/o.css"));
    baml.fs.chmod(root.std.path_join(dir, "out"), 0o755);
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    };

    // "a cleanup that failed became the verdict: {}", r.stderr
    assert.equal(r.code, 65);
    // "the compile error is still the story: {}", r.stderr
    assert.is_true(r.stderr.includes("Undefined operation"));
    // "the removal failure is still reported: {}", r.stderr
    assert.is_true(r.stderr.includes("cannot remove"));
    // "the stale output is still there, which is the thing being reported"
    assert.is_true(survived)
}
