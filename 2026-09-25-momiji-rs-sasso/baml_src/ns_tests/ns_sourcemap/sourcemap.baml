// Ported from sasso `tests/sourcemap.rs` (namespace `root.tests.sourcemap`).
//
// Verification harness for Source Map v3 output — built VERIFICATION-FIRST,
// before the emit/API phases produce maps, and committed so it runs in CI.
//
// Three layers (see the module fns):
//   1. `decode_mappings` — an independent Base64-VLQ + `mappings` decoder (the
//      inverse of `src/sourcemap.rs`), used as the oracle machinery.
//   2. `check_declaration_invariants` — asserts each declaration mapping points
//      at the SAME leading CSS identifier in the source as appears at the
//      generated position (a self-checking semantic invariant, no dart needed).
//   3. The dart-sass differential lives in `tests/parity.rs`-style gated tests
//      added as the feature lands; here we validate the MACHINERY itself against
//      a known-good dart-sass map fixture, so later phases can trust it.
//
// As Phase B/C/E land, the sasso-output tests call `check_declaration_invariants`
// on sasso's own (css, map) and decode-diff against dart.

// PORT: `const B64: &[u8; 64]` → a zero-arg function returning the bytes.
function B64() -> uint8array {
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".to_utf8()
}

function b64_val(c: int) -> int {
    root.std.expect(B64().index_of(c), "valid base64 digit")
}

/// Decode every Base64-VLQ value packed in one segment string.
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

/// One absolute mapping (all 0-based): generated (line,col) -> source (id,line,col).
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

/// Decode a v3 `mappings` string into absolute mappings (the inverse of
/// `sourcemap::Mappings::encode`). Segments with only a generated column (no
/// source) are skipped — they carry no source position to verify.
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

/// The text on `line` starting at column `col`. NOTE: for ASCII fixtures the
/// UTF-16 source-map column equals the byte column; non-ASCII verification needs
/// a UTF-16->byte conversion (added when those fixtures appear).
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

/// The leading CSS identifier (property name / keyword) at the start of `s`.
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

/// Self-checking invariant: for every mapping whose GENERATED position begins
/// with an identifier (a declaration name or at-rule keyword — not a selector,
/// which starts with `.`/`#`/`&`/etc.), the SOURCE position it points to must
/// begin with the same identifier. Selector mappings (non-ident start) are only
/// bounds-checked, since source flattening (`.a .b` <- `.b`) means the generated
/// token is not a literal prefix of the source. Returns the count of strictly
/// verified (identifier-matched) mappings.
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
            continue; // selector / symbol-leading token: bounds-checked only
        }
        // mapping {m:?}: generated {gen_id:?} != source {:?}
        assert.equal(gen_id, leading_ident(src));
        strict += 1;
    }
    strict
}

// --- The dart-sass fixture: ground truth that validates the machinery above. ---
// Produced by: dart-sass 1.101.0 `sass --source-map sm_in.scss sm_out.css`.
function DART_INPUT() -> string {
    ".a {\n  color: red;\n  .b { width: 10px; }\n}\n"
}

// The library API (`compile_with_source_map().css`) returns no trailing
// newline — matching dart-sass's library API.
function DART_OUTPUT_CSS() -> string {
    ".a {\n  color: red;\n}\n.a .b {\n  width: 10px;\n}"
}

function DART_MAPPINGS() -> string {
    "AAAA;EACE;;AACA;EAAK"
}

test "decoder_matches_known_dart_map" {
    // Hand-verified decode of dart's mappings for DART_INPUT.
    let got = decode_mappings(DART_MAPPINGS());
    let expect = [
        Mapping { gen_line: 0, gen_col: 0, src_id: 0, src_line: 0, src_col: 0 }, // `.a` selector
        Mapping { gen_line: 1, gen_col: 2, src_id: 0, src_line: 1, src_col: 2 }, // `color` decl name
        Mapping { gen_line: 3, gen_col: 0, src_id: 0, src_line: 2, src_col: 2 }, // flattened `.a .b` <- `.b`
        Mapping { gen_line: 4, gen_col: 2, src_id: 0, src_line: 2, src_col: 7 }, // `width` decl name
    ];
    assert.equal(got, expect)
}

test "invariant_checker_accepts_known_good_dart_map" {
    // The machinery must ACCEPT a known-correct map (and strictly verify the two
    // declaration names `color` and `width`).
    let strict = check_declaration_invariants(
        [root.std.Tuple2<string, string> { _0: "sm_in.scss", _1: DART_INPUT() }],
        DART_OUTPUT_CSS(),
        DART_MAPPINGS(),
    );
    // expected to strictly verify the 2 declaration-name mappings
    assert.equal(strict, 2)
}

test "invariant_checker_rejects_a_corrupted_map" {
    // Sanity: corrupting the source column of the `color` mapping (point it at
    // the wrong place) must make the checker FAIL — proving it actually checks.
    // "EACE" (gen+2,src0,line+1,col+2) -> change col delta so `color` maps to col 0.
    let bad = "AAAA;EACA;;AACA;EAAK"; // second segment col delta 2 -> 0
    // PORT: `std::panic::take_hook()` / `set_hook(Box::new(|_| {}))` /
    // `set_hook(prev)` dropped — a caught BAML panic prints nothing.
    // PORT: `std::panic::catch_unwind(|| …).is_err()` → a `catch` of
    // `baml.panics.Panic` (the failed `assert.equal` inside the checker).
    let result_is_err = {
        let _ = check_declaration_invariants(
            [root.std.Tuple2<string, string> { _0: "sm_in.scss", _1: DART_INPUT() }],
            DART_OUTPUT_CSS(),
            bad,
        );
        false
    } catch (e) {
        let _p: baml.panics.Panic => true
    };
    // checker must reject a map whose source column is wrong
    assert.is_true(result_is_err)
}

// =====================================================================
// sasso-output tests: compile fixtures with `compile_with_source_map`,
// then validate the produced map with the harness above.
// =====================================================================

// PORT: `use sasso::{compile, compile_with_source_map, CanonicalUrl, …}` —
// BAML has no imports; the items are `root.compile`, `root.importer.*`, ….

/// The canonical url `FsImporter` keys a resolved file by: the absolute path
/// as it was reached, with the ASCII case folding `absolute_normalized` applies
/// on Windows (dart's `Style.windows` canonicalizes each part, and that
/// filesystem is case-insensitive).
function canon_key(p: string) -> string {
    // `PathBuf::push` does not respell `/` as the platform separator, so a
    // `join("src/sub/_p.scss")` keeps its `/` on Windows while the importer's
    // key, built from the real path, uses `\`. Re-collecting the components
    // respells it the way the platform does.
    let p = root.std.path_from_components(root.std.path_components(p));
    let s = p;
    // PORT: `#[cfg(windows)] let s = s.to_lowercase();` — not a Windows build.
    s
}

/// Compile `src` with a source map and return `(css, decoded_mappings, raw_json)`.
function sasso_map(
    src: string,
    options: root.Options,
) -> root.std.Tuple3<string, Mapping[], string> {
    // PORT: `.expect("compile_with_source_map failed")` — the error propagates.
    let r = root.compile_with_source_map(src, options);
    let json = r.source_map.to_json_();
    // The `mappings` is the last JSON string in our hand-built JSON.
    let mappings = r.source_map.mappings;
    root.std.Tuple3<string, Mapping[], string> {
        _0: r.css,
        _1: decode_mappings(mappings),
        _2: json,
    }
}

test "sasso_css_matches_plain_compile" {
    // The map is generated ALONGSIDE the CSS — the CSS must equal `compile`'s.
    for (
        let src in [
            DART_INPUT(),
            "a { color: red; b { x: 1px; } }\n",
            "@media screen { a { color: red; } }\n",
            "/* hi */\na { color: red; }\n",
        ]
    ) {
        let plain = root.compile(src, root.Options.default());
        let r = root.compile_with_source_map(src, root.Options.default());
        // css mismatch for {src:?}
        assert.equal(plain, r.css);
    }
}

test "sasso_nested_rule_map_is_valid" {
    // The DART_INPUT fixture: nested rule, two declarations, selector flattening.
    let t = sasso_map(DART_INPUT(), root.Options.default().with_url("sm_in.scss"));
    let css = t._0;
    let _maps = t._1;
    let json = t._2;
    // sasso css must match the dart fixture css
    assert.equal(css, DART_OUTPUT_CSS());
    let strict = check_declaration_invariants(
        [root.std.Tuple2<string, string> { _0: "sm_in.scss", _1: DART_INPUT() }],
        css,
        sasso_mappings(json),
    );
    // expected to strictly verify >=2 decl names, got {strict}
    assert.is_true(strict >= 2);
    assert.is_true(json.includes("\"version\":3"));
    assert.is_true(json.includes("\"sources\":[\"sm_in.scss\"]"));
    assert.is_true(json.includes("\"file\":\"sm_in.scss\""))
}

test "sasso_multiline_decl_block_map_is_valid" {
    // A rule whose declarations span several source lines.
    let src = ".card {
  color: red;
  background: blue;
  border: 1px solid green;
}
";
    let t = sasso_map(src, root.Options.default().with_url("in.scss"));
    let css = t._0;
    let _m = t._1;
    let json = t._2;
    let strict = check_declaration_invariants([root.std.Tuple2<string, string> { _0: "in.scss", _1: src }], css, sasso_mappings(json));
    // color, background, border — three strictly-verified declaration names.
    // expected >=3 strict decl mappings, got {strict}
    assert.is_true(strict >= 3)
}

test "sasso_media_block_map_is_valid" {
    let src = "@media screen {
  .a {
    color: red;
  }
}
";
    let t = sasso_map(src, root.Options.default().with_url("in.scss"));
    let css = t._0;
    let maps = t._1;
    let json = t._2;
    let strict = check_declaration_invariants([root.std.Tuple2<string, string> { _0: "in.scss", _1: src }], css, sasso_mappings(json));
    // expected the `color` decl mapped, got {strict}
    assert.is_true(strict >= 1);
    // The `@media` keyword should map to the source `@` (line 0, col 0).
    // expected a mapping at source 0:0 for the @media keyword
    assert.is_true(
        maps.some((m) -> {
            m.src_line == 0 && m.src_col == 0
        }),
    )
}

test "sasso_comment_map_is_valid" {
    let src = "/* a loud comment */\n.a {\n  color: red;\n}\n";
    let t = sasso_map(src, root.Options.default().with_url("in.scss"));
    let css = t._0;
    let maps = t._1;
    let json = t._2;
    // The comment's `/*` maps to source 0:0.
    // expected the comment `/*` mapped to source 0:0
    assert.is_true(
        maps.some((m) -> {
            m.src_line == 0 && m.src_col == 0
        }),
    );
    let strict = check_declaration_invariants([root.std.Tuple2<string, string> { _0: "in.scss", _1: src }], css, sasso_mappings(json));
    assert.is_true(strict >= 1)
}

test "sasso_compressed_map_is_valid" {
    let src = ".a {\n  color: red;\n  width: 10px;\n}\n";
    let opts = root.Options.default().with_style(root.OutputStyle.Compressed).with_url("in.scss");
    let t = sasso_map(src, opts);
    let css = t._0;
    let maps = t._1;
    let _json = t._2;
    // compressed css
    assert.equal(css, ".a{color:red;width:10px}");
    // The two declaration names map to their source columns (both at col 2).
    // both compressed decl names should map to source col 2: {maps:?}
    assert.equal(
        maps
            .filter((m) -> {
                m.src_col == 2
            })
            .length(),
        2,
    );
    // The selector maps to source 0:0.
    assert.is_true(
        maps.some((m) -> {
            m.gen_line == 0 && m.src_line == 0 && m.src_col == 0
        }),
    )
}

test "sasso_compressed_skips_consecutive_same_source_line" {
    // dart-sass compressed maps every selector/declaration token but SKIPS a
    // token whose source line repeats the IMMEDIATELY PRECEDING mapped token's
    // (compressed packs many tokens onto one output line). It is a consecutive-
    // run skip, NOT a global "one mapping per source line": a source line that
    // recurs non-consecutively (e.g. a bubbled parent selector) is mapped again
    // — see `sasso_compressed_bubbled_media_matches_dart`. These expected
    // strings are byte-exact dart-sass 1.101 output. (Expanded maps every token.)
    let opts = root.Options.default().with_style(root.OutputStyle.Compressed).with_url("in.scss");

    // Selector + both decls share source line 0 -> only the selector is mapped.
    let json = sasso_map(".a { color: red; width: 1px; }\n", opts)._2;
    assert.equal(sasso_mappings(json), "AAAA");

    // Nested: `.a` (l0), `color` (l1), `.a .b` (l2); the l2 width/height repeat
    // the `.b` source line and are dropped.
    let json = sasso_map(".a {\n  color: red;\n  .b { width: 1px; height: 2px; }\n}\n", opts)._2;
    assert.equal(sasso_mappings(json), "AAAA,GACE,UACA")
}

test "sasso_compressed_bubbled_media_matches_dart" {
    // A `@media` nested in a style rule bubbles a COPY of the parent selector
    // out (`@media screen{.a{...}}`); that copy must map back to the ORIGINAL
    // `.a {` selector's source position (source line 0), NOT the @media's line.
    // Because its source line (0) differs from the neighbouring @media (line 2),
    // the consecutive-same-line skip keeps it AND the following `width` decl, so
    // compressed regains the two segments a naive same-line dedup would drop.
    // Regression guard for the bubbled-selector source-map fix. Expected strings
    // are byte-exact dart-sass 1.101 (`sass in.scss out --style=compressed
    // --source-map`).
    let src = ".a {\n  color: red;\n  @media screen { width: 1px; }\n  height: 2px;\n}\n";

    let t = sasso_map(src, root.Options.default().with_style(root.OutputStyle.Compressed).with_url("in.scss"));
    let css = t._0;
    let json = t._2;
    assert.equal(css, ".a{color:red}@media screen{.a{width:1px}}.a{height:2px}");
    // 7 segments: .a(l0), color(l1), @media(l2), bubbled .a(l0), width(l2),
    // trailing .a(l0), height(l3) — none consecutive-same-line, so none dropped.
    assert.equal(sasso_mappings(json), "AAAA,GACE,UACA,cAFF,GAEkB,WAFlB,GAGE");

    // Expanded maps the bubbled selector too (dart parity): the `EAFF` segment
    // at generated line 4 is the bubbled `.a` mapping back to source 0:0.
    let json = sasso_map(src, root.Options.default().with_url("in.scss"))._2;
    assert.equal(sasso_mappings(json), "AAAA;EACE;;AACA;EAFF;IAEkB;;;AAFlB;EAGE")
}

test "sasso_supports_header_maps_to_keyword" {
    // dart-sass maps the bubbled `@supports` at-rule HEADER back to the
    // `@supports` keyword's source position; sasso historically emitted the
    // node with `SrcLines::default()` (file 0), dropping that mapping. Regression
    // guard. `.a { @supports (display: grid) { d: grid; } }` -> dart 1.101
    // expanded `AAAK;EAAL;IAAiC` (genline0 = `@supports`@src0:5, genline1 = the
    // bubbled `.a`@src0:0, genline2 = `d:grid`).
    let src = ".a { @supports (display: grid) { d: grid; } }\n";
    let json = sasso_map(src, root.Options.default().with_url("in.scss"))._2;
    assert.equal(sasso_mappings(json), "AAAK;EAAL;IAAiC");

    // Compressed: the header is the only mapping (everything else coalesces onto
    // its source line) -> `AAAK`.
    let json = sasso_map(src, root.Options.default().with_style(root.OutputStyle.Compressed).with_url("in.scss"))._2;
    assert.equal(sasso_mappings(json), "AAAK")
}

test "sasso_bare_variable_value_maps_to_its_definition" {
    // A declaration whose value is a BARE `$name` gets a SECOND mapping segment,
    // pointing at where that variable was DECLARED — dart serializes the value
    // inside `_buffer.forSpan(node.valueSpanForMap, …)` (serialize.dart:389),
    // and `valueSpanForMap` runs the value expression through `_expressionNode`
    // (evaluate.dart:1414 -> 4538), which resolves a `VariableExpression` to
    // `Environment.getVariableNode` — the node stored when the variable was set.
    // sasso previously emitted no value segment at all, which both lost the
    // mapping AND renumbered every following segment.
    //
    // All expected strings here were produced by RUNNING dart-sass 1.101.6
    // (`sass.compileToResult(path, sourceMap: true)`), not by copying sasso's
    // own output.
    let opts = root.Options.default().with_url("in.scss");

    // `color: $c` (src 2:9) maps back to the `red` in `$c: red` at src 0:4.
    // Without the fix sasso emitted `AACA;EACE;;AACA;EAAK` — the `,OAFE` segment
    // missing and the two trailing segments shifted.
    let src = "$c: red;\n.a {\n  color: $c;\n  .b { top: 1px; }\n}\n";
    let json = sasso_map(src, opts)._2;
    assert.equal(sasso_mappings(json), "AACA;EACE,OAFE;;AAGF;EAAK");

    // Compressed takes the same extra segment (`MAFE`).
    let json = sasso_map(src, root.Options.default().with_style(root.OutputStyle.Compressed).with_url("in.scss"))._2;
    assert.equal(sasso_mappings(json), "AACA,GACE,MAFE,IAGF");

    // The resolution is TRANSITIVE: `$b: $a` stores `$a`'s node, so `c: $b`
    // reaches the original `red` (src 0:4), not the `$b` declaration.
    let json = sasso_map("$a: red;\n$b: $a;\n.x { c: $b; }\n", opts)._2;
    assert.equal(sasso_mappings(json), "AAEA;EAAK,GAFD");

    // A mixin/function PARAMETER resolves too — to the ARGUMENT at the call
    // site, because `getVariableNode` returns the CURRENT binding: `pad: $p`
    // maps back to the `4px` in `@include m(4px)` (src 1:16).
    let json = sasso_map("@mixin m($p) { pad: $p; }\n.a { @include m(4px); }\n", opts)._2;
    assert.equal(sasso_mappings(json), "AACA;EADe,KACC");

    // An argument passed BY NAME resolves the same way — to the `4px` in
    // `@include m($p: 4px)` (src 1:20).
    let json = sasso_map("@mixin m($p) { pad: $p; }\n.a { @include m($p: 4px); }\n", opts)._2;
    assert.equal(sasso_mappings(json), "AACA;EADe,KACK");

    // So does one spread from a `...` splat, which carries the SPLAT
    // EXPRESSION's node: `$args` is a bare variable, so `pad: $p` reaches the
    // `(4px,)` its list was declared from (src 1:7), not the `@include`.
    let json = sasso_map("@mixin m($p) { pad: $p; }\n$args: (4px,);\n.a { @include m($args...); }\n", opts)._2;
    assert.equal(sasso_mappings(json), "AAEA;EAFe,KACR");

    // ONLY a bare variable resolves. Every other expression shape keeps its own
    // span, which sits on the declaration's own source line and is therefore
    // dropped as redundant — so `a: $c` is the only one of these six to gain a
    // segment (`,GAJE`). This is the boundary that makes the rule falsifiable:
    // arithmetic, calls, interpolation, lists and literals must NOT resolve.
    // PORT: `concat!(…)` → `root.std.concat([…])`.
    let src = root.std.concat(
        [
            "$c: red;\n",
            "$n: 2;\n",
            "@function f($x) { @return $x; }\n",
            ".a {\n",
            "  a: $c;\n", // bare variable   -> EXTRA segment
            "  b: $n * 3;\n", // arithmetic      -> none
            "  c: f($n);\n", // call            -> none
            "  d: #{$c};\n", // interpolation   -> none
            "  e: $c $c;\n", // list            -> none
            "  g: red;\n", // literal         -> none
            "}\n",
        ],
    );
    let json = sasso_map(src, opts)._2;
    assert.equal(sasso_mappings(json), "AAGA;EACE,GAJE;EAKF;EACA;EACA;EACA;EACA")
}

// PORT: `struct TwoFile;` + `impl Importer for TwoFile`, declared inside
// `sasso_redundant_entry_dropped_across_source_files`, hoisted to the namespace.
class TwoFile {
    implements root.importer.Importer {
        function canonicalize(
            self,
            url: string,
            ctx: root.importer.CanonicalizeContext,
        ) -> root.importer.CanonicalUrl? {
            root.importer.CanonicalUrl.new(`u:${url}`)
        }
        function load(
            self,
            canonical: root.importer.CanonicalUrl,
        ) -> root.importer.ImporterResult? {
            assert.equal(canonical.as_str(), "u:p");
            root.importer.ImporterResult {
                contents: ".p1 { a: 1px; }\n.p2 { b: 2px; }\n",
                syntax: root.Syntax.Scss,
                source_map_url: null,
            }
        }
    }
}

test "sasso_redundant_entry_dropped_across_source_files" {
    // dart's `SourceMapBuffer._addEntry` (util/source_map_buffer.dart:64) drops
    // an entry whose SOURCE LINE and TARGET LINE both repeat the previous
    // entry's. Crucially it compares neither the source FILE nor the column, so
    // two tokens on one generated line collapse even when they come from
    // different files. Verified by running dart-sass 1.101.6 on a two-file
    // compressed fixture: `.q1` (in.scss line 0) then an imported `.p1`
    // (_p.scss line 0) emit ONE segment, not two.
    //
    // sasso used to key this on `(file_id, src_line)`, which kept the second
    // entry. The fix matters here because a declaration now emits a value
    // segment on the SAME generated line as its property name.
    let src = ".q1 { c: 3px; }\n@import \"p\";\n.q2 { d: 4px; }\n";
    let t = sasso_map(
        src,
        root.Options.default()
            .with_style(root.OutputStyle.Compressed)
            .with_url("in.scss")
            .with_importer(TwoFile {  }),
    );
    let css = t._0;
    let json = t._2;
    assert.equal(css, ".q1{c:3px}.p1{a:1px}.p2{b:2px}.q2{d:4px}");
    // 3 segments, not 4: `.p1` (file 1, line 0) is dropped as redundant with
    // `.q1` (file 0, line 0) — same source line, same generated line.
    assert.equal(sasso_mappings(json), "AAAA,oBCCA,UDCA")
}

test "sasso_sources_content_round_trips" {
    let src = ".a { color: red; }\n";
    let opts = root.Options.default().with_url("in.scss").with_source_map_include_sources(true);
    let r = root.compile_with_source_map(src, opts);
    assert.equal(r.source_map.sources, ["in.scss"]);
    // sourcesContent must hold the entry source
    assert.equal(r.source_map.sources_content, [src]);
    // Default: no sourcesContent.
    let r2 = root.compile_with_source_map(src, root.Options.default().with_url("in.scss"));
    assert.is_true(r2.source_map.sources_content == null);
    assert.is_true(!r2.source_map.to_json_().includes("sourcesContent"))
}

test "sasso_stdin_file_name" {
    // No URL -> the `file` field is "stdin" and the single source is "stdin".
    let r = root.compile_with_source_map(".a { x: 1px; }\n", root.Options.default());
    assert.equal(r.source_map.file, "stdin");
    assert.equal(r.source_map.sources, ["stdin"])
}

/// Extract the `mappings` JSON string value from sasso's hand-built map JSON.
function sasso_mappings(json: string) -> string {
    let key = "\"mappings\":\"";
    let start = root.std.expect(json.index_of(key), "mappings field") + key.length();
    let rest = json.slice(start, json.length());
    let end = root.std.expect(rest.index_of("\""), "mappings close quote");
    rest.slice(0, end)
}

// =====================================================================
// Gated dart-sass differential: compare sasso's map to dart's for the
// SAME input. Opt-in via SASSO_PARITY=1 + a reachable SASS_BIN dart-sass
// (mirrors tests/parity.rs). Decodes BOTH maps and asserts the declaration
// and selector SOURCE positions agree (semantic, not byte, comparison).
// =====================================================================

function dart_enabled() -> bool {
    let v = root.std.env_var("SASSO_PARITY");
    if (v != null) {
        v != "0"
    } else {
        false
    }
}

/// Run dart-sass with `--source-map` over a temp input file and return its
/// decoded mappings + sources, or `None` if dart is unavailable.
function dart_map(src: string) -> root.std.Tuple2<Mapping[], string[]>? {
    let bin = root.std.env_var("SASS_BIN");
    if (bin == null) {
        return null;
    }
    let dir = root.tests.support.temp_dir();
    let stem = `sasso_dartdiff_${baml.sys.pid()}`;
    let in_path = root.std.path_join(dir, `${stem}.scss`);
    let out_path = root.std.path_join(dir, `${stem}.css`);
    let map_path = root.std.path_join(dir, `${stem}.css.map`);
    // PORT: `File::create(..).ok()?.write_all(..).ok()?` → one write.
    root.std.write_file(in_path, src) catch (e) {
        let _e: baml.errors.Io => {
            return null;
        }
    };
    // PORT: `Command::status()` → `baml.sys.exec` (the child's output is
    // captured instead of inherited).
    let status = baml.sys.exec(bin, ["--source-map", in_path, out_path], null) catch (e) {
        _ => {
            return null;
        }
    };
    if (!status.ok()) {
        return null;
    }
    let map_json = root.std.read_to_string(map_path) catch (e) {
        let _e: baml.errors.Io => {
            return null;
        }
    };
    let mappings = sasso_mappings(map_json);
    // sources: parse the simple JSON array of strings.
    let sources = {
        let key = "\"sources\":[";
        let s = map_json.index_of(key);
        if (s == null) {
            return null;
        }
        let s = s + key.length();
        let rest = map_json.slice(s, map_json.length());
        let e = rest.index_of("]");
        if (e == null) {
            return null;
        }
        rest.slice(0, e)
            .split(",")
            .filter((t) -> {
                t != ""
            })
            .map((t) -> {
                root.std.trim_matches(root.std.trim(t), "\"")
            })
    };
    // Best-effort cleanup.
    root.std.remove_file(in_path) catch (e) {
        let _e: baml.errors.Io => null
    };
    root.std.remove_file(out_path) catch (e) {
        let _e: baml.errors.Io => null
    };
    root.std.remove_file(map_path) catch (e) {
        let _e: baml.errors.Io => null
    };
    root.std.Tuple2<Mapping[], string[]> { _0: decode_mappings(mappings), _1: sources }
}

/// The set of SOURCE positions a map points at (id,line,col) — order- and
/// generated-position-independent. Selector flattening means the GENERATED side
/// differs between impls, but the SOURCE side a declaration/selector points to
/// should agree.
// PORT: `BTreeSet<(u32, u32, u32)>` → `map<string, bool>`.
// key: `"{src_id}\t{src_line}\t{src_col}"`
function source_positions(maps: Mapping[]) -> map<string, bool> {
    root.std.set_of(
        maps.map((m) -> {
            `${m.src_id}\t${m.src_line}\t${m.src_col}`
        }),
    )
}

test "dart_differential_source_positions_agree" {
    if (!dart_enabled()) {
        return;
    }
    // Each case exercises a different construct.
    let cases = [
        ".a {\n  color: red;\n  .b { width: 10px; }\n}\n",
        "a {\n  color: red;\n}\nb {\n  width: 10px;\n}\n",
        "@media screen {\n  .a {\n    color: red;\n  }\n}\n",
        ".card {\n  color: red;\n  background: blue;\n}\n",
    ];
    for (let src in cases) {
        let dm = dart_map(src);
        if (dm == null) {
            baml.io.eprintln("skipping dart-diff: dart-sass unavailable");
            return;
        }
        let dart = dm._0;
        let _dsrc = dm._1;
        // sasso: name the entry the same as dart (the temp file's basename is
        // arbitrary, but both maps use src_id 0 for the single entry file).
        let opts = root.Options.default().with_url("in.scss");
        let r = root.compile_with_source_map(src, opts);
        let ours = decode_mappings(r.source_map.mappings);
        let dart_pos = source_positions(dart);
        let our_pos = source_positions(ours);
        // Every source position dart maps to, sasso must also map to (sasso may
        // additionally map the closing-token columns dart omits, so this is a
        // superset check on dart's positions).
        for (let p in root.std.sorted_keys(dart_pos)) {
            // dart maps source {p:?} that sasso does not.\nsrc:\n{src}\nours: {our_pos:?}\ndart: {dart_pos:?}
            assert.is_true(our_pos.has(p));
        }
    }
}

test "sasso_charset_prefix_and_utf16_columns" {
    // Non-ASCII content makes the serializer prepend `@charset "UTF-8";\n`,
    // which shifts every generated line down by one (the leading empty group
    // in `mappings`). The astral `𝕏` is 2 UTF-16 code units, so the following
    // line's columns must still be counted in UTF-16 units. This map is
    // byte-identical to dart-sass 1.x for the same input.
    let src = ".a {\n  content: \"héllo 𝕏\";\n  color: red;\n}\n";
    let r = root.compile_with_source_map(src, root.Options.default().with_url("u_in.scss"));
    // expected a charset prefix
    assert.is_true(r.css.starts_with("@charset \"UTF-8\";\n"));
    // charset-shifted + UTF-16 map
    assert.equal(r.source_map.mappings, ";AAAA;EACE;EACA");
    // The selector is now on generated line 1 (after the @charset line).
    let maps = decode_mappings(r.source_map.mappings);
    assert.is_true(
        maps.some((m) -> {
            m.gen_line == 1 && m.src_line == 0 && m.src_col == 0
        }),
    )
}

test "sasso_compressed_astral_char_shifts_the_generated_column_like_dart" {
    // The expanded case above puts the astral char at the end of its line, so
    // every later column is measured from a fresh line. Compressed packs the
    // whole sheet onto generated line 0, which is where the UTF-16 unit count
    // has to be carried ACROSS the 4-byte char: `color` sits 13 units past
    // `content` (`content:"` = 9, `𝕏` = 2, `";` = 2), not 15 bytes past it.
    // Compressed also prefixes a BOM rather than `@charset`, and that BOM is
    // itself one unit, which is why the first segment starts at column 1.
    //
    // Both expected strings are dart-sass 1.104.1's own bytes for this input.
    let src = ".a {\n  content: \"𝕏\";\n  color: red;\n}\n";
    let opts = root.Options.default().with_style(root.OutputStyle.Compressed).with_url("in.scss");
    let t = sasso_map(src, opts);
    let css = t._0;
    let maps = t._1;
    let json = t._2;
    // expected a BOM: {css:?}
    assert.is_true(css.starts_with(root.std.chr_unchecked(0xFEFF)));
    // generated columns in UTF-16 units: {maps:?}
    assert.equal(
        maps.map((m) -> {
            m.gen_col
        }),
        [1, 4, 17],
    );
    // dart-sass 1.104.1 map
    assert.equal(sasso_mappings(json), "CAAA,GACE,aACA")
}

/// A custom importer that resolves one virtual module and reports a custom
/// `source_map_url` for it (dart-sass `ImporterResult.sourceMapUrl`).
class SourceMapUrlImporter {
    implements root.importer.Importer {
        function canonicalize(
            self,
            url: string,
            ctx: root.importer.CanonicalizeContext,
        ) -> root.importer.CanonicalUrl? {
            // PORT: `(url == "mod").then(|| CanonicalUrl::new("mod"))`.
            if (url == "mod") {
                root.importer.CanonicalUrl.new("mod")
            } else {
                null
            }
        }

        function load(
            self,
            canonical: root.importer.CanonicalUrl,
        ) -> root.importer.ImporterResult? {
            if (canonical.as_str() == "mod") {
                root.importer.ImporterResult {
                    // Emit a rule so the module's source position is mapped (and thus
                    // appears in the source map's `sources[]`).
                    contents: ".m { x: 1px; }",
                    syntax: root.Syntax.Scss,
                    source_map_url: "custom://virtual/mod.scss",
                }
            } else {
                null
            }
        }
    }
}

test "importer_source_map_url_override_appears_in_sources" {
    // The loaded module's `sources[]` entry uses the importer's source_map_url
    // (not its canonical key), while the entry file keeps its own URL.
    let imp = SourceMapUrlImporter {  };
    let opts = root.Options.default().with_importer(imp).with_url("entry.scss");
    // Both the entry and the module emit a rule, so both are mapped sources.
    let r = root.compile_with_source_map("@use \"mod\";\n.a { y: 2px; }\n", opts);
    // sources should carry the importer's source_map_url override, got {:?}
    assert.is_true(r.source_map.sources.includes("custom://virtual/mod.scss"));
    // the entry file keeps its own URL, got {:?}
    assert.is_true(r.source_map.sources.includes("entry.scss"))
}

test "importer_source_map_url_override_applies_to_import_too" {
    // dart's `ImporterResult.sourceMapUrl` names the loaded file whether it
    // was reached by `@use` or by `@import`.
    let imp = SourceMapUrlImporter {  };
    let opts = root.Options.default().with_importer(imp).with_url("entry.scss");
    let r = root.compile_with_source_map("@import \"mod\";\n.a { y: 2px; }\n", opts);
    // the imported file is named by the importer's source_map_url
    assert.equal(r.source_map.sources, ["custom://virtual/mod.scss", "entry.scss"])
}

/// A plain-CSS `@import` (a `.css` file reached through `@import "lib"`) is
/// its own source, with its mappings pointing into it: dart-sass writes
/// `sources: [main.scss, lib.css]`, mappings `AAAA;EAAI;;;ACAJ;EACE;;;ADCF;EAAI`.
test "plain_css_import_is_its_own_source" {
    let dir = root.std.path_join(root.tests.support.temp_dir(), `sasso_sm_cssimp_${baml.sys.pid()}`);
    // mkdir
    root.std.create_dir_all(dir);
    root.std.write_file(root.std.path_join(dir, "lib.css"), "q {\n  r: 1;\n}\n");
    let entry = root.std.path_join(dir, "main.scss");
    let src = "a { b: c }\n@import \"lib\";\nd { e: f }\n";
    root.std.write_file(entry, src);
    let url = entry;
    let imp = root.importer.FsImporter.new([]);
    let opts = root.Options.default().with_importer(imp).with_url(url);
    let r = root.compile_with_source_map(src, opts);
    let lib = canon_key(root.std.path_join(dir, "lib.css"));
    // the css file is a distinct source
    assert.equal(r.source_map.sources, [url, lib]);
    assert.equal(r.source_map.mappings, "AAAA;EAAI;;;ACAJ;EACE;;;ADCF;EAAI");
    baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    }
}

/// Sources are keyed by the file's CANONICAL URL — the absolute path for the
/// filesystem importer — not by its display basename, so two partials that
/// share a basename are two distinct sources, each with its own text, and the
/// mappings point at the right one (dart-sass: `../src/sub/_p.scss`,
/// `../src/other/_p.scss`, mappings `AAAA;EAAE;;;ACAF;EAAE`).
test "imports_sharing_a_basename_are_distinct_sources" {
    let dir = root.std.path_join(root.tests.support.temp_dir(), `sasso_sm_basename_${baml.sys.pid()}`);
    root.std.create_dir_all(root.std.path_join(dir, "src/sub"));
    root.std.create_dir_all(root.std.path_join(dir, "src/other"));
    root.std.write_file(root.std.path_join(dir, "src/sub/_p.scss"), "a{b:1}\n");
    root.std.write_file(root.std.path_join(dir, "src/other/_p.scss"), "c{d:2}\n");
    let entry = root.std.path_join(dir, "src/two.scss");
    let url = entry;
    let importer = root.importer.FsImporter.new([]);
    let opts = root.Options.default()
        .with_importer(importer)
        .with_url(url)
        .with_source_map_include_sources(true)
        .with_warn_handler((_w: root.WarnEvent) -> void {});
    // compile
    let r = root.compile_with_source_map("@import \"sub/p\";\n@import \"other/p\";\n", opts);
    let canon = (rel: string) -> string {
        canon_key(root.std.path_join(dir, rel))
    };
    // The entry emitted nothing of its own, so — as in dart — it is not a source.
    assert.equal(r.source_map.sources, [canon("src/sub/_p.scss"), canon("src/other/_p.scss")]);
    assert.equal(r.source_map.sources_content, ["a{b:1}\n", "c{d:2}\n"]);
    assert.equal(r.source_map.mappings, "AAAA;EAAE;;;ACAF;EAAE");
    baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    }
}

/// A stylesheet with no output has no sources at all (dart-sass writes
/// `"sources":[]`), rather than a forced entry.
test "empty_stylesheet_has_no_sources" {
    // compile
    let r = root.compile_with_source_map("", root.Options.default().with_url("e.scss"));
    let no_sources: string[] = [];
    assert.equal(r.source_map.sources, no_sources);
    assert.equal(r.source_map.mappings, "");
    // compile
    let r = root.compile_with_source_map("// nothing\n$x: 1;\n", root.Options.default().with_url("e.scss"));
    assert.equal(r.source_map.sources, no_sources)
}

/// dart-sass keeps a source-map span open while it writes a construct, and every
/// newline inside adds an entry at the start of the new generated line pointing
/// at the same source position (`SourceMapBuffer.writeCharCode`: "so that
/// source map consumers can identify the line-spanning mappings"). A rule maps
/// to its selector's FIRST line (`node.selector.span.start`), not its brace
/// line, and a comment's span opens before its indentation (column 0). Every
/// `mappings` here is byte-identical to dart-sass 1.103.1's for the same input.
test "line_spanning_constructs_map_every_generated_line_like_dart" {
    let cases: root.std.Tuple2<string, string>[] = [
        // A multi-line selector list: both lines map to the selector's start.
        root.std.Tuple2<string, string> { _0: "a,\nb {\n  color: red;\n}\n", _1: "AAAA;AAAA;EAEE" },
        // The brace on its own line: the rule still maps to the selector line.
        root.std.Tuple2<string, string> { _0: "a,\nb\n{\n  color: red;\n}\n", _1: "AAAA;AAAA;EAGE" },
        // A nested multi-line comment maps from column 0, each line.
        root.std.Tuple2<string, string> {
            _0: ".x {\n  /* one\n     two */\n  color: red;\n}\n",
            _1: "AAAA;AACE;AAAA;EAEA",
        },
        root.std.Tuple2<string, string> {
            _0: "/* top\n   two */\n.a {\n  color: red;\n}\n",
            _1: "AAAA;AAAA;AAEA;EACE",
        },
        // A re-indented multi-line custom property value.
        root.std.Tuple2<string, string> {
            _0: ".x {\n  --v:\n    1px\n    2px;\n}\n",
            _1: "AAAA;EACE;AAAA;AAAA",
        },
        // A trailing comment maps after the joining space.
        root.std.Tuple2<string, string> { _0: ".x {\n  a: 1; /* trailing */\n}\n", _1: "AAAA;EACE" },
        // A comment nested two levels deep.
        root.std.Tuple2<string, string> {
            _0: "@media screen {\n  .a {\n    /* c */\n    color: red;\n  }\n}\n",
            _1: "AAAA;EACE;AACE;IACA",
        },
        // A nested rule's multi-line selector.
        root.std.Tuple2<string, string> {
            _0: ".p {\n  a,\n  b {\n    color: red;\n  }\n}\n",
            _1: "AACE;AAAA;EAEE",
        },
        // A bubbled `@media` re-emits the multi-line selector, mapped to the
        // original rule's selector.
        root.std.Tuple2<string, string> {
            _0: "a,\nb {\n  @media screen {\n    color: red;\n  }\n}\n",
            _1: "AAEE;EAFF;AAAA;IAGI",
        },
        // A block at-rule whose prelude spans lines maps to its `@` line, not
        // its brace line — also when bubbled out of a rule.
        root.std.Tuple2<string, string> {
            _0: "@media screen,\n  print {\n  a {\n    b: c;\n  }\n}\n",
            _1: "AAAA;EAEE;IACE",
        },
        root.std.Tuple2<string, string> {
            _0: "@media screen,\n  print\n{\n  a {\n    b: c;\n  }\n}\n",
            _1: "AAAA;EAGE;IACE",
        },
        root.std.Tuple2<string, string> {
            _0: "@supports (display: grid) and\n  (gap: 1px) {\n  a {\n    b: c;\n  }\n}\n",
            _1: "AAAA;EAEE;IACE",
        },
        root.std.Tuple2<string, string> {
            _0: ".x {\n  @media screen,\n    print {\n    b: c;\n  }\n}\n",
            _1: "AACE;EADF;IAGI",
        },
        // An interpolated at-rule NAME changes nothing: the rule carries its
        // own span and maps exactly like the plain spelling.
        root.std.Tuple2<string, string> {
            _0: "@media screen {\n  a {\n    b: c;\n  }\n}\n",
            _1: "AAAA;EACE;IACE",
        },
        root.std.Tuple2<string, string> {
            _0: "@#{\"media\"} screen {\n  a {\n    b: c;\n  }\n}\n",
            _1: "AAAA;EACE;IACE",
        },
        root.std.Tuple2<string, string> {
            _0: "$n: media;\n@#{$n} screen {\n  a {\n    b: c;\n  }\n}\n",
            _1: "AACA;EACE;IACE",
        },
    ];
    for (let c in cases) {
        let src = c._0;
        let expected = c._1;
        // compile
        let r = root.compile_with_source_map(src, root.Options.default().with_url("in.scss"));
        // mappings for {src:?}\ncss:\n{}
        assert.equal(r.source_map.mappings, expected);
    }
}

/// A passed-through plain-CSS `@import` maps to its URL token — `url(` or the
/// opening quote — at the start of the emitted rule (dart `visitCssImport`);
/// nested in a rule it maps after the indentation. Byte-identical to dart-sass
/// 1.103.1.
test "css_import_passthrough_maps_to_its_url" {
    let cases: root.std.Tuple2<string, string>[] = [
        root.std.Tuple2<string, string> { _0: "@import \"k.css\";\n", _1: "AAAQ" },
        root.std.Tuple2<string, string> { _0: "@import url(k.css);\n", _1: "AAAQ" },
        root.std.Tuple2<string, string> { _0: "@import   \"k.css\";\n", _1: "AAAU" },
        root.std.Tuple2<string, string> { _0: "@import \"k.css\" screen;\n", _1: "AAAQ" },
        root.std.Tuple2<string, string> { _0: "@import \"k.css\", \"m.css\";\n", _1: "AAAQ;AAAS" },
        root.std.Tuple2<string, string> { _0: ".x {\n  @import \"k.css\";\n}\n", _1: "AAAA;EACU" },
        // Hoisted above the rules that preceded it, and mapped from there.
        root.std.Tuple2<string, string> {
            _0: ".x {\n  a: 1;\n}\n@import \"k.css\";\n.y {\n  b: 2;\n}\n",
            _1: "AAGQ;AAHR;EACE;;;AAGF;EACE",
        },
    ];
    for (let c in cases) {
        let src = c._0;
        let expected = c._1;
        // compile
        let r = root.compile_with_source_map(src, root.Options.default().with_url("in.scss"));
        // mappings for {src:?}\ncss:\n{}
        assert.equal(r.source_map.mappings, expected);
    }
}

/// A loaded plain-CSS file that uses CSS nesting keeps its rules nested, and
/// each nested rule maps to its selector — every line of a multi-line list —
/// with the declarations inside mapped too (dart-sass 1.103.1:
/// `AAAA;EACE;AAAA;IAEE;;EAEF;IACE`, sources `[nest.css]`).
test "nested_plain_css_rules_map_to_their_selectors" {
    let dir = root.std.path_join(root.tests.support.temp_dir(), `sasso_sm_cssnest_${baml.sys.pid()}`);
    // mkdir
    root.std.create_dir_all(dir);
    root.std.write_file(
        root.std.path_join(dir, "nest.css"),
        ".a {\n  > .b,\n  .c {\n    x: 1;\n  }\n  &:hover {\n    y: 2;\n  }\n}\n",
    );
    let entry = root.std.path_join(dir, "main.scss");
    let url = entry;
    let imp = root.importer.FsImporter.new([]);
    let opts = root.Options.default().with_importer(imp).with_url(url).with_warn_handler((_w: root.WarnEvent) -> void {});
    // compile
    let r = root.compile_with_source_map("@import \"nest\";\n", opts);
    assert.equal(r.css, ".a {\n  > .b,\n  .c {\n    x: 1;\n  }\n  &:hover {\n    y: 2;\n  }\n}");
    // {:?}
    assert.equal(r.source_map.sources.length(), 1);
    assert.is_true(r.source_map.sources[0].ends_with("nest.css"));
    assert.equal(r.source_map.mappings, "AAAA;EACE;AAAA;IAEE;;EAEF;IACE");

    // Compressed output maps the nested rule's CHILDREN too: dart visits them
    // like any other rule's (`.a{.b{x:1;y:2}z:3}`, mappings
    // `AAAA,GACE,GACE,IACA,IAEF`), and a nested block's `}` is its own
    // separator — no `;` follows it.
    root.std.write_file(
        root.std.path_join(dir, "nest2.css"),
        ".a {\n  .b {\n    x: 1;\n    y: 2;\n  }\n  z: 3;\n}\n",
    );
    let opts = root.Options.default()
        .with_importer(imp)
        .with_url(url)
        .with_style(root.OutputStyle.Compressed)
        .with_warn_handler((_w: root.WarnEvent) -> void {});
    // compile
    let r = root.compile_with_source_map("@import \"nest2\";\n", opts);
    assert.equal(r.css, ".a{.b{x:1;y:2}z:3}");
    assert.equal(r.source_map.mappings, "AAAA,GACE,GACE,IACA,IAEF");
    baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    }
}

/// A block at-rule nested inside an ALREADY-NESTED plain-CSS rule stays where
/// it is (dart `_hasCssNesting`: once the user opts into CSS nesting, at-rules
/// are not bubbled), and it maps to its `@` keyword like any other at-rule —
/// in compressed output too, where its children are serialized through the
/// same mapping-aware path. Both `mappings` below are dart-sass 1.103.1's.
test "nested_plain_css_at_rules_map_to_their_keyword" {
    let dir = root.std.path_join(root.tests.support.temp_dir(), `sasso_sm_cssnestat_${baml.sys.pid()}`);
    baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    };
    // mkdir
    root.std.create_dir_all(dir);
    let entry = root.std.path_join(dir, "main.scss");
    let url = entry;
    let imp = root.importer.FsImporter.new([]);
    let check = (css_src: string, name: string, css: string, expanded: string, compressed: string) -> void {
        root.std.write_file(root.std.path_join(dir, `${name}.css`), css_src);
        let src = `@import "${name}";\n`;
        let opts = root.Options.default().with_importer(imp).with_url(url).with_warn_handler((
            _w: root.WarnEvent,
        ) -> void {});
        // compile
        let r = root.compile_with_source_map(src, opts);
        // expanded css for {name}
        assert.equal(r.css, css);
        // expanded mappings for {name}
        assert.equal(r.source_map.mappings, expanded);
        let opts = opts.with_style(root.OutputStyle.Compressed);
        // compile
        let r = root.compile_with_source_map(src, opts);
        // compressed mappings for {name}
        assert.equal(r.source_map.mappings, compressed);
    };
    check(
        ".a {\n  .b {\n    @media screen {\n      x: 1;\n    }\n    y: 2;\n  }\n}\n",
        "nest3",
        ".a {\n  .b {\n    @media screen {\n      x: 1;\n    }\n    y: 2;\n  }\n}",
        "AAAA;EACE;IACE;MACE;;IAEF",
        "AAAA,GACE,GACE,cACE,IAEF",
    );
    // A prelude written over several lines maps from its `@` line.
    check(
        ".a {\n  .b {\n    @media screen,\n    print {\n      x: 1;\n    }\n  }\n}\n",
        "nest4",
        ".a {\n  .b {\n    @media screen, print {\n      x: 1;\n    }\n  }\n}",
        "AAAA;EACE;IACE;MAEE",
        "AAAA,GACE,GACE,oBAEE",
    );
    baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    }
}

/// The filesystem importer's canonical URL is the absolute, lexically
/// normalized path — dart `p.canonicalize` — with symlinks left unresolved, so
/// a file reached through a linked directory (a pnpm `node_modules/<pkg>`
/// link) is named by the link path in `sources`, as dart-sass 1.103.1 names it
/// (`../link/_lib.scss`, never the `real/` target).
// PORT: `#[cfg(unix)]` — active on a macOS/Linux host.
test "sources_keep_a_symlinked_load_path_unresolved" {
    let dir = root.std.path_join(root.tests.support.temp_dir(), `sasso_sm_symlink_${baml.sys.pid()}`);
    baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    };
    // mkdir
    root.std.create_dir_all(root.std.path_join(dir, "real"));
    root.std.write_file(root.std.path_join(dir, "real/_lib.scss"), "l {\n  m: 1;\n}\n");
    // symlink
    baml.fs.symlink("real", root.std.path_join(dir, "link"));
    let entry = root.std.path_join(dir, "sym.scss");
    let url = entry;
    let imp = root.importer.FsImporter.new([root.std.path_join(dir, "link")]);
    let opts = root.Options.default().with_importer(imp).with_url(url).with_warn_handler((_w: root.WarnEvent) -> void {});
    // compile
    let r = root.compile_with_source_map("@import \"lib\";\n", opts);
    assert.equal(r.source_map.sources, [root.std.path_join(dir, "link/_lib.scss")]);
    assert.equal(r.source_map.mappings, "AAAA;EACE");
    baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    }
}
