// Ported from sasso `tests/cli_sourcemap.rs` (namespace `root.tests.cli_sourcemap`).
//
// End-to-end CLI tests for `-o/--output` and `--source-map`, driving the REAL
// built `sasso` binary (`env!("CARGO_BIN_EXE_sasso")`) via `std::process::Command`.
//
// Each test writes its inputs into a unique subdir of `std::env::temp_dir()`,
// runs the binary, and asserts on the produced files. A small Base64-VLQ
// `mappings` decoder + declaration-invariant checker is duplicated here (cross-
// file reuse from `tests/sourcemap.rs` is awkward for integration tests) so the
// produced `.map` is semantically validated, not just byte-matched.
//
// A gated dart-sass differential (opt-in via `SASSO_PARITY=1` + a reachable
// `$SASS_BIN`) compares the produced `out.css` (incl footer) and the `.map`
// fields against dart-sass for the same `sass <in> <out>` invocation.

// PORT: `use std::path::{Path, PathBuf}; use std::process::Command;` — paths
// are strings, processes run through `baml.sys.exec`.

// PORT: `const BIN: &str = env!("CARGO_BIN_EXE_sasso")` → the `baml pack`ed CLI.
function BIN() -> string {
    root.tests.support.sasso_bin()
}

/// Create a fresh unique temp subdir for one test and return its path.
function scratch(tag: string) -> string {
    let dir = root.std.path_join(
        root.tests.support.temp_dir(),
        `sasso_cli_sm_${tag}_${baml.sys.pid()}_${unique()}`,
    );
    // create scratch dir
    root.std.create_dir_all(dir);
    dir
}

// PORT: `static N: AtomicU64` (inside `unique`) → a process-wide cell held by
// a top-level `client` declaration (PORTING_GUIDE §15). The increment is not
// atomic; a lost update between parallel tests cannot collide, because every
// `scratch` tag belongs to one test and each test calls `unique` sequentially.
client unique__N_CELL = root.std.Cell<int> { value: 0 };

/// A process-monotonic counter so concurrently-run tests get distinct dirs.
function unique() -> int {
    // PORT: `N.fetch_add(1, Ordering::Relaxed)`.
    let n = unique__N_CELL;
    let v = n.value;
    n.value = v + 1;
    v
}

/// Run the sasso binary in `cwd` with `args`; return (success, stdout, stderr).
function run(cwd: string, args: string[]) -> root.std.Tuple3<bool, string, string> {
    // PORT: `.expect("spawn sasso")` — a spawn failure propagates.
    let out = baml.sys.exec(
        BIN(),
        args,
        baml.sys.ProcessOptions { cwd: cwd, env: null, timeout_ms: null, stdin: null, stderr: null },
    );
    root.std.Tuple3<bool, string, string> {
        _0: out.ok(),
        _1: root.std.from_utf8_lossy(out.stdout),
        _2: root.std.from_utf8_lossy(out.stderr),
    }
}

function write(dir: string, name: string, contents: string) -> string {
    let p = root.std.path_join(dir, name);
    let parent = root.std.path_parent(p);
    if (parent != null) {
        // mkdir -p
        root.std.create_dir_all(parent);
    }
    // write input
    root.std.write_file(p, contents);
    p
}

// ---- minimal Base64-VLQ `mappings` decoder (mirror of tests/sourcemap.rs) ----

// PORT: `const B64: &[u8; 64]` → a zero-arg function returning the bytes.
function B64() -> uint8array {
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".to_utf8()
}

function b64_val(c: int) -> int {
    root.std.expect(B64().index_of(c), "valid base64 digit")
}

function vlq_decode_all(seg: string) -> int[] {
    let bytes = seg.to_utf8();
    let out: int[] = [];
    let i = 0;
    while (i < bytes.length()) {
        let result: int = 0;
        let shift = 0;
        while (true) {
            let d = b64_val(bytes[i]);
            i += 1;
            result = result | ((d & 0x1f) << shift);
            shift += 5;
            if ((d & 0x20) == 0) {
                break;
            }
        }
        let mag = result >> 1;
        out.push(
            if ((result & 1) == 1) {
                -mag
            } else {
                mag
            },
        );
    }
    out
}

class Mapping {
    gen_line: int,
    gen_col: int,
    src_id: int,
    src_line: int,
    src_col: int,

    /// `derive(Debug)` — the `{:?}` rendering used in panic messages.
    function debug(self) -> string {
        `Mapping { gen_line: ${self.gen_line}, gen_col: ${self.gen_col}, src_id: ${self.src_id}, src_line: ${self.src_line}, src_col: ${self.src_col} }`
    }
}

function decode_mappings(mappings: string) -> Mapping[] {
    let out: Mapping[] = [];
    let s_id = 0;
    let s_line = 0;
    let s_col = 0;
    // PORT: `.enumerate()` → an explicit line counter.
    let gen_line = 0;
    for (let line in mappings.split(";")) {
        let gen_col = 0;
        for (let seg in line.split(",")) {
            if (seg == "") {
                continue;
            }
            let f = vlq_decode_all(seg);
            gen_col += f[0];
            if (f.length() >= 4) {
                s_id += f[1];
                s_line += f[2];
                s_col += f[3];
                out.push(
                    Mapping {
                        gen_line: root.std.as_u32(gen_line),
                        gen_col: root.std.as_u32(gen_col),
                        src_id: root.std.as_u32(s_id),
                        src_line: root.std.as_u32(s_line),
                        src_col: root.std.as_u32(s_col),
                    },
                );
            }
        }
        gen_line += 1;
    }
    out
}

function at(text: string, line: int, col: int) -> string? {
    let l = text.lines().at(line);
    if (l == null) {
        return null;
    }
    // PORT: `l.get(col..)` slices at a BYTE offset and is `None` past the end
    // or off a char boundary.
    if (!root.std.is_char_boundary(l, col)) {
        return null;
    }
    root.std.byte_slice(l, col, l.byte_length())
}

function leading_ident(s: string) -> string {
    // PORT: `take_while(..).collect()` → a loop that stops at the first miss.
    let out = "";
    for (let c in s.chars()) {
        if (!(c.is_ascii_alphanumeric() || c == "-" || c == "_")) {
            break;
        }
        out = out + c;
    }
    out
}

/// For every mapping whose generated position starts with an identifier (a
/// declaration name / at-rule keyword), assert the SOURCE position it points to
/// begins with the same identifier. Returns the count of strictly-verified maps.
// PORT: `&[(&str, &str)]` → `Tuple2<string, string>[]`.
function check_declaration_invariants(
    sources: root.std.Tuple2<string, string>[],
    output_css: string,
    mappings: string,
) -> int {
    let maps = decode_mappings(mappings);
    let strict = 0;
    for (let m in maps) {
        let src_text = (sources.at(m.src_id) ?? root.std.panic(`mapping references missing source id ${m.src_id}`))._1;
        let gen = at(output_css, m.gen_line, m.gen_col)
            ?? root.std.panic(`generated pos ${m.debug()} out of bounds`);
        let src = at(src_text, m.src_line, m.src_col)
            ?? root.std.panic(`source pos ${m.debug()} out of bounds`);
        let gen_id = leading_ident(gen);
        if (gen_id == "") {
            continue;
        }
        // mapping {m:?}: generated {gen_id:?} != source {:?}
        assert.equal(gen_id, leading_ident(src));
        strict += 1;
    }
    strict
}

/// Pull a top-level string field out of the (hand-built, flat) map JSON.
function json_field(json: string, key: string) -> string? {
    let needle = `"${key}":"`;
    let start = json.index_of(needle);
    if (start == null) {
        return null;
    }
    let start = start + needle.length();
    let rest = json.slice(start, json.length());
    // The map values we read here contain no escaped quotes, so this is safe.
    let end = rest.index_of("\"");
    if (end == null) {
        return null;
    }
    rest.slice(0, end)
}

/// Parse the `sources` JSON array of strings.
function json_sources(json: string) -> string[] {
    let key = "\"sources\":[";
    let s = root.std.expect(json.index_of(key), "sources field") + key.length();
    let rest = json.slice(s, json.length());
    let e = root.std.expect(rest.index_of("]"), "sources close");
    rest.slice(0, e)
        .split(",")
        .filter((t) -> {
            t != ""
        })
        .map((t) -> {
            root.std.trim_matches(root.std.trim(t), "\"")
        })
}

// =====================================================================
// (a) `-o out.css` with NO --source-map: plain CSS, no footer, no .map.
// =====================================================================

test "output_without_source_map_writes_plain_css" {
    // Like dart-sass, file output gets a source map by default; `--no-source-map`
    // opts out.
    let dir = scratch("plain");
    write(dir, "in.scss", ".a {\n  color: red;\n}\n");
    let r = run(dir, ["--no-source-map", "in.scss", "-o", "out.css"]);
    let ok = r._0;
    let _out = r._1;
    let err = r._2;
    // compile failed: {err}
    assert.is_true(ok);
    // out.css
    let css = root.std.read_to_string(root.std.path_join(dir, "out.css"));
    // plain CSS, no footer
    assert.equal(css, ".a {\n  color: red;\n}\n");
    // no footer expected
    assert.is_true(!css.includes("sourceMappingURL"));
    // no .map should be written
    assert.is_true(!root.std.exists(root.std.path_join(dir, "out.css.map")));
    baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    }
}

// =====================================================================
// (b) `-o out.css --source-map`: footer + out.css.map; the map decodes and
//     every declaration mapping points at the right source identifier.
// =====================================================================

test "source_map_writes_footer_and_sidecar" {
    let dir = scratch("sm");
    let src = ".a {\n  color: red;\n  width: 10px;\n}\n";
    write(dir, "in.scss", src);
    let r = run(dir, ["--source-map", "in.scss", "-o", "out.css"]);
    let ok = r._0;
    let err = r._2;
    // compile failed: {err}
    assert.is_true(ok);

    // out.css
    let css = root.std.read_to_string(root.std.path_join(dir, "out.css"));
    // dart EXPANDED footer: CSS ends in `\n`, footer = `\n/*# … */\n`.
    let expected = ".a {\n  color: red;\n  width: 10px;\n}\n\n/*# sourceMappingURL=out.css.map */\n";
    // expanded footer must match dart byte-for-byte
    assert.equal(css, expected);

    // out.css.map
    let map = root.std.read_to_string(root.std.path_join(dir, "out.css.map"));
    assert.is_true(map.includes("\"version\":3"));
    assert.equal(json_field(map, "file"), "out.css");
    assert.equal(json_sources(map), ["in.scss"]);
    // no embed by default
    assert.is_true(!map.includes("sourcesContent"));

    // The map's mappings (after the footer is stripped) validate against the CSS.
    let mappings = root.std.expect(json_field(map, "mappings"), "mappings");
    // Validate against the CSS WITHOUT the footer (the map describes the CSS body).
    let body = css.split("\n/*# sourceMappingURL")[0];
    let body = `${body}\n`;
    let strict = check_declaration_invariants([root.std.Tuple2<string, string> { _0: "in.scss", _1: src }], body, mappings);
    // expected color+width strictly verified, got {strict}
    assert.is_true(strict >= 2);
    baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    }
}

// =====================================================================
// (c) compressed footer has NO leading newline.
// =====================================================================

test "compressed_footer_has_no_leading_newline" {
    let dir = scratch("comp");
    write(dir, "in.scss", ".a {\n  color: red;\n}\n");
    let r = run(dir, ["--style=compressed", "--source-map", "in.scss", "-o", "out.css"]);
    let ok = r._0;
    let err = r._2;
    // compile failed: {err}
    assert.is_true(ok);
    // out.css
    let css = root.std.read_to_string(root.std.path_join(dir, "out.css"));
    // compressed footer must have NO leading newline
    assert.equal(css, ".a{color:red}/*# sourceMappingURL=out.css.map */\n");
    assert.is_true(root.std.exists(root.std.path_join(dir, "out.css.map")));
    baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    }
}

// =====================================================================
// (d) --embed-sources populates sourcesContent.
// =====================================================================

test "embed_sources_populates_sources_content" {
    let dir = scratch("embed");
    let src = ".a {\n  color: red;\n}\n";
    write(dir, "in.scss", src);
    let r = run(dir, ["--source-map", "--embed-sources", "in.scss", "-o", "out.css"]);
    let ok = r._0;
    let err = r._2;
    // compile failed: {err}
    assert.is_true(ok);
    // out.css.map
    let map = root.std.read_to_string(root.std.path_join(dir, "out.css.map"));
    // expected sourcesContent
    assert.is_true(map.includes("\"sourcesContent\":["));
    // The embedded content is the entry source verbatim (newlines escaped).
    let escaped = src.replace_all("\n", "\\n");
    // sourcesContent must hold the entry source.\nmap: {map}
    assert.is_true(map.includes(escaped));
    baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    }
}

// =====================================================================
// (e) --source-map to stdout is an error unless the map is embedded (dart).
// =====================================================================

test "source_map_without_output_errors" {
    let dir = scratch("err");
    write(dir, "in.scss", ".a { x: 1px; }\n");
    let r = run(dir, ["--source-map", "in.scss"]);
    let ok = r._0;
    let err = r._2;
    // expected a non-zero exit
    assert.is_true(!ok);
    // expected dart's stdout/source-map error, got: {err}
    assert.is_true(
        err.includes("When printing to stdout, --source-map requires --embed-source-map."),
    );
    baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    }
}

test "output_requires_single_input" {
    let dir = scratch("multi");
    write(dir, "a.scss", ".a { x: 1px; }\n");
    write(dir, "b.scss", ".b { y: 2px; }\n");
    let r = run(dir, ["a.scss", "b.scss", "-o", "out.css"]);
    let ok = r._0;
    let err = r._2;
    // expected a non-zero exit
    assert.is_true(!ok);
    // got: {err}
    assert.is_true(err.includes("--output requires a single input"));
    baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    }
}

// =====================================================================
// (f) the existing stdout path (no -o) is unchanged.
// =====================================================================

test "stdout_path_unchanged_with_no_output" {
    let dir = scratch("stdout");
    write(dir, "in.scss", ".a {\n  color: red;\n}\n");
    let r = run(dir, ["in.scss"]);
    let ok = r._0;
    let out = r._1;
    let err = r._2;
    // compile failed: {err}
    assert.is_true(ok);
    // stdout CSS unchanged
    assert.equal(out, ".a {\n  color: red;\n}\n");
    // no file should be written
    assert.is_true(!root.std.exists(root.std.path_join(dir, "in.css")));
    baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    }
}

// =====================================================================
// (g) the CLI appends dart-sass's single trailing newline in BOTH styles —
//     to stdout and to a `-o` file. The library API omits it (pinned by
//     `library_api_omits_trailing_newline` in tests/integration.rs); these
//     guard that the CLI front-end re-adds exactly one, matching dart-sass.
// =====================================================================

test "cli_appends_single_trailing_newline_both_styles" {
    let dir = scratch("nl");
    write(dir, "in.scss", ".a {\n  color: red;\n}\n");

    // Expanded + compressed, to stdout.
    let r = run(dir, ["in.scss"]);
    let ok = r._0;
    let exp = r._1;
    let err = r._2;
    // expanded compile failed: {err}
    assert.is_true(ok);
    // expanded stdout ends with one \n
    assert.equal(exp, ".a {\n  color: red;\n}\n");

    let r = run(dir, ["--style=compressed", "in.scss"]);
    let ok = r._0;
    let comp = r._1;
    let err = r._2;
    // compressed compile failed: {err}
    assert.is_true(ok);
    // compressed stdout ends with one \n
    assert.equal(comp, ".a{color:red}\n");

    // Compressed to a `-o` file (no source map): same single trailing newline.
    let r = run(dir, ["--style=compressed", "--no-source-map", "in.scss", "-o", "out.css"]);
    let ok = r._0;
    let err = r._2;
    // compressed -o failed: {err}
    assert.is_true(ok);
    // out.css
    let file = root.std.read_to_string(root.std.path_join(dir, "out.css"));
    // compressed file ends with one \n
    assert.equal(file, ".a{color:red}\n");

    baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    }
}

// =====================================================================
// Source map url forms: relative (output in a subdir) + absolute.
// =====================================================================

test "relative_source_url_when_output_in_subdir" {
    let dir = scratch("relurl");
    write(dir, "src/in.scss", ".a {\n  color: red;\n}\n");
    root.std.create_dir_all(root.std.path_join(dir, "out"));
    let r = run(dir, ["--source-map", "src/in.scss", "-o", "out/r.css"]);
    let ok = r._0;
    let err = r._2;
    // compile failed: {err}
    assert.is_true(ok);
    // map
    let map = root.std.read_to_string(root.std.path_join(dir, "out/r.css.map"));
    // source must be relative to the .map dir
    assert.equal(json_sources(map), ["../src/in.scss"]);
    assert.equal(json_field(map, "file"), "r.css");
    // Footer url is the basename of the sidecar.
    let css = root.std.read_to_string(root.std.path_join(dir, "out/r.css"));
    // footer url is sidecar basename
    assert.is_true(css.includes("sourceMappingURL=r.css.map "));
    baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    }
}

test "absolute_source_url_is_file_scheme" {
    let dir = scratch("absurl");
    write(dir, "in.scss", ".a {\n  color: red;\n}\n");
    let r = run(dir, ["--source-map", "--source-map-urls=absolute", "in.scss", "-o", "out.css"]);
    let ok = r._0;
    let err = r._2;
    // compile failed: {err}
    assert.is_true(ok);
    // map
    let map = root.std.read_to_string(root.std.path_join(dir, "out.css.map"));
    let sources = json_sources(map);
    assert.equal(sources.length(), 1);
    // absolute source must be a file:// URL: {:?}
    assert.is_true(sources[0].starts_with("file:///") && sources[0].ends_with("/in.scss"));
    baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    }
}

// =====================================================================
// Gated dart-sass differential (opt-in: SASSO_PARITY=1 + reachable $SASS_BIN).
// Runs sasso and dart-sass for the SAME `<in> <out>` invocation and asserts the
// out.css (incl footer) is byte-identical and the .map version/file/sources
// agree. The `mappings` SOURCE positions are checked as a superset (dart omits
// some closing-token columns sasso maps in compressed mode — a known, pre-
// existing library granularity difference, not a CLI concern).
// =====================================================================

function dart_enabled() -> bool {
    let v = root.std.env_var("SASSO_PARITY");
    if (v != null) {
        v != "0"
    } else {
        false
    }
}

// PORT: `BTreeSet<(u32, u32, u32)>` → `map<string, bool>`.
// key: `"{src_id}\t{src_line}\t{src_col}"`
function source_positions(maps: Mapping[]) -> map<string, bool> {
    root.std.set_of(
        maps.map((m) -> {
            `${m.src_id}\t${m.src_line}\t${m.src_col}`
        }),
    )
}

test "dart_differential_output_and_map_match" {
    if (!dart_enabled()) {
        return;
    }
    let dart = root.std.env_var("SASS_BIN");
    if (dart == null) {
        baml.io.eprintln("skipping dart-diff: SASS_BIN unset");
        return;
    }

    // (case, extra flags). Each runs through both binaries with the SAME output
    // path so the footer url + `file` are directly comparable.
    let cases: root.std.Tuple2<string, string[]>[] = [
        root.std.Tuple2<string, string[]> { _0: ".a {\n  color: red;\n}\n", _1: [] },
        root.std.Tuple2<string, string[]> {
            _0: ".a {\n  color: red;\n  width: 10px;\n}\n",
            _1: ["--style=compressed"],
        },
        root.std.Tuple2<string, string[]> {
            _0: ".card {\n  color: red;\n  background: blue;\n}\n",
            _1: ["--embed-sources"],
        },
        root.std.Tuple2<string, string[]> {
            _0: ".a {\n  color: red;\n}\n",
            _1: ["--source-map-urls=absolute"],
        },
    ];

    for (let c in cases) {
        let src = c._0;
        let extra = c._1;
        let dir = scratch("diff");
        write(dir, "in.scss", src);

        // sasso: `--source-map <extra> in.scss -o s.css`
        let sargs: string[] = ["--source-map"];
        root.std.extend(sargs, extra);
        root.std.extend(sargs, ["in.scss", "-o", "s.css"]);
        let sr = run(dir, sargs);
        let sok = sr._0;
        let serr = sr._2;
        // sasso failed for {src:?}: {serr}
        assert.is_true(sok);

        // dart: `--source-map <extra> in.scss d.css`
        let dargs: string[] = ["--source-map"];
        root.std.extend(dargs, extra);
        root.std.extend(dargs, ["in.scss", "d.css"]);
        // PORT: `Command::status()` → `baml.sys.exec` (output captured, not
        // inherited); `.expect("spawn dart")` — a spawn failure propagates.
        let dstatus = baml.sys.exec(
            dart,
            dargs,
            baml.sys.ProcessOptions {
                cwd: dir,
                env: null,
                timeout_ms: null,
                stdin: null,
                stderr: null,
            },
        );
        if (!dstatus.ok()) {
            baml.io.eprintln(`skipping dart-diff case (dart failed): ${root.std.debug_str(src)}`);
            baml.fs.remove_dir_all(dir) catch (e) {
                let _e: baml.errors.Io => null
            };
            continue;
        }

        let s_css = root.std.read_bytes(root.std.path_join(dir, "s.css"));
        let d_css = root.std.read_bytes(root.std.path_join(dir, "d.css"));
        // The footer urls differ only by the output basename (s.css.map vs
        // d.css.map); normalize that one token before comparing the bytes.
        let s_css_n = root.std.from_utf8_lossy(s_css).replace_all("s.css.map", "OUT.map");
        let d_css_n = root.std.from_utf8_lossy(d_css).replace_all("d.css.map", "OUT.map");
        // out.css bytes differ for {src:?} {extra:?}
        assert.equal(s_css_n, d_css_n);

        let s_map = root.std.read_to_string(root.std.path_join(dir, "s.css.map"));
        let d_map = root.std.read_to_string(root.std.path_join(dir, "d.css.map"));
        assert.is_true(s_map.includes("\"version\":3") && d_map.includes("\"version\":3"));
        // `file` differs by basename only; `sources` + sourcesContent must match.
        assert.equal(json_field(s_map, "file"), "s.css");
        assert.equal(json_field(d_map, "file"), "d.css");
        // sources differ for {src:?} {extra:?}
        assert.equal(json_sources(s_map), json_sources(d_map));
        // Every source position dart maps, sasso must also map (superset).
        let s_pos = source_positions(decode_mappings(root.std.unwrap(json_field(s_map, "mappings"))));
        let d_pos = source_positions(decode_mappings(root.std.unwrap(json_field(d_map, "mappings"))));
        for (let p in root.std.sorted_keys(d_pos)) {
            // dart maps source {p:?} that sasso does not, {src:?} {extra:?}
            assert.is_true(s_pos.has(p));
        }
        baml.fs.remove_dir_all(dir) catch (e) {
            let _e: baml.errors.Io => null
        };
    }
}
