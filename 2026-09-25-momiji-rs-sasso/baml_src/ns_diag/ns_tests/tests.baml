// Ported from sasso `src/diag.rs` `#[cfg(test)] mod tests`
// (namespace `root.diag.tests`).
//
// PORT: Rust's line-continuation string literals (`"…\n\` + indented next
// line, `\x20` for a leading space) are written as `+`-joined one-line pieces;
// `concat!` likewise. `\u{…}` escapes are written as the literal glyphs
// (╷ U+2577, │ U+2502, ╵ U+2575, ┌ U+250C, ─ U+2500, └ U+2514).

// Every block below is dart-sass 1.103.1's own output, captured with
// `--no-unicode` (scratch `dartref/ds1..ds4.sh`).
test "labelled_spans_match_dart" {
    let ascii: root.diag.GlyphSet = root.diag.GlyphSet.Ascii;

    // Adjacent lines: one block, one underline row each.
    let src = "@mixin m($x) { a: $x; }\n.a { @include m; }\n";
    let got = root.diag.render_labelled_snippet(
        "t.scss",
        src,
        root.diag.Span { line: 2, col: 6, length: 10 },
        "invocation",
        [
            root.diag.Secondary {
                url: "t.scss",
                source: src,
                span: root.diag.Span { line: 1, col: 8, length: 5 },
                label: "declaration",
            },
        ],
        [],
        ascii,
    );
    assert.equal(
        got,
        "  ,\n"
            + "1 | @mixin m($x) { a: $x; }\n"
            + "  |        ===== declaration\n"
            + "2 | .a { @include m; }\n"
            + "  |      ^^^^^^^^^^ invocation\n"
            + "  '",
    );

    // Non-adjacent lines are elided, never filled in, and the gutter
    // widens to the `...` column with the numbers left-aligned in it.
    let far = "@mixin m($x) { a: $x; }\n";
    for (let i in baml.iter.Range.new(0, 8)) {
        far = far + `// ${i}\n`;
    }
    far = far + ".a { @include m; }\n";
    let got = root.diag.render_labelled_snippet(
        "t.scss",
        far,
        root.diag.Span { line: 10, col: 6, length: 10 },
        "invocation",
        [
            root.diag.Secondary {
                url: "t.scss",
                source: far,
                span: root.diag.Span { line: 1, col: 8, length: 5 },
                label: "declaration",
            },
        ],
        [],
        ascii,
    );
    assert.equal(
        got,
        "    ,\n"
            + "1   | @mixin m($x) { a: $x; }\n"
            + "    |        ===== declaration\n"
            + "... |\n"
            + "10  | .a { @include m; }\n"
            + "    |      ^^^^^^^^^^ invocation\n"
            + "    '",
    );

    // Several secondaries: one row each, in line order.
    let src = "@use \"_a\" as *;\n@use \"_b\" as *;\n.x { @include m; }\n";
    // PORT: `(1..=2).map(|line| …).collect()` → a loop over the range.
    let secs: root.diag.Secondary[] = [];
    for (let line in baml.iter.Range.new(1, 2 + 1)) {
        secs.push(
            root.diag.Secondary {
                url: "t.scss",
                source: src,
                span: root.diag.Span { line: line, col: 1, length: 14 },
                label: "includes mixin",
            },
        );
    }
    let got = root.diag.render_labelled_snippet(
        "t.scss",
        src,
        root.diag.Span { line: 3, col: 6, length: 10 },
        "mixin use",
        secs,
        [],
        ascii,
    );
    assert.equal(
        got,
        "  ,\n"
            + "1 | @use \"_a\" as *;\n"
            + "  | ============== includes mixin\n"
            + "2 | @use \"_b\" as *;\n"
            + "  | ============== includes mixin\n"
            + "3 | .x { @include m; }\n"
            + "  |      ^^^^^^^^^^ mixin use\n"
            + "  '",
    );

    // Another file gets its own block, introduced by its url.
    let entry = ".a { b: red(#abc, 1); }\n";
    let builtin = "@function red($color) {\n";
    let got = root.diag.render_labelled_snippet(
        "t.scss",
        entry,
        root.diag.Span { line: 1, col: 9, length: 12 },
        "invocation",
        [
            root.diag.Secondary {
                url: "sass:color",
                source: builtin,
                span: root.diag.Span { line: 1, col: 11, length: 11 },
                label: "declaration",
            },
        ],
        [],
        ascii,
    );
    assert.equal(
        got,
        "  ,--> t.scss\n"
            + "1 | .a { b: red(#abc, 1); }\n"
            + "  |         ^^^^^^^^^^^^ invocation\n"
            + "  '\n"
            + "  ,--> sass:color\n"
            + "1 | @function red($color) {\n"
            + "  |           =========== declaration\n"
            + "  '",
    );

    // Two spans on ONE line: the line once, then both rows, primary first.
    let src = ".a { b: get_((x: 1), x); }\n";
    let got = root.diag.render_labelled_snippet(
        "t.scss",
        src,
        root.diag.Span { line: 1, col: 14, length: 6 },
        "value",
        [
            root.diag.Secondary {
                url: "t.scss",
                source: src,
                span: root.diag.Span { line: 1, col: 9, length: 15 },
                label: "unknown function treated as plain CSS",
            },
        ],
        [],
        ascii,
    );
    assert.equal(
        got,
        "  ,\n"
            + "1 | .a { b: get_((x: 1), x); }\n"
            + "  |              ^^^^^^ value\n"
            + "  |         =============== unknown function treated as plain CSS\n"
            + "  '",
    )
}

// ----- Offline, hard-coded expectations (always run) -----

test "split_lines_handles_all_terminators" {
    assert.equal(root.diag.split_lines("a\nb\r\nc\rd"), ["a", "b", "c", "d"]);
    assert.equal(root.diag.split_lines(""), [""]);
    assert.equal(root.diag.split_lines("a\n"), ["a", ""])
}

test "tabs_expand_to_four_spaces_everywhere" {
    assert.equal(root.diag.expand_tabs("\tb"), "    b");
    assert.equal(root.diag.expand_tabs("a\tb"), "a    b");
    assert.equal(root.diag.expand_tabs("\t\tb"), "        b");
    assert.equal(root.diag.expand_tabs(" \tb"), "     b")
}

test "digit_count_basic" {
    assert.equal(root.diag.digit_count(0), 1);
    assert.equal(root.diag.digit_count(9), 1);
    assert.equal(root.diag.digit_count(10), 2);
    assert.equal(root.diag.digit_count(123), 3)
}

// dart-sass 1.100.0, `a {\n  b: $undefined;\n}\n`, span at 2:6 len 10.
test "undefined_variable_unicode" {
    let src = "a {\n  b: $undefined;\n}\n";
    let span = root.diag.Span { line: 2, col: 6, length: "$undefined".byte_length() };
    let got = root.diag.render_error(
        "Undefined variable.",
        src,
        "/tmp/input.scss",
        span,
        root.diag.GlyphSet.Unicode,
    );
    let expected = "Error: Undefined variable.
  ╷
2 │   b: $undefined;
  │      ^^^^^^^^^^
  ╵
  /tmp/input.scss 2:6  root stylesheet";
    assert.equal(got, expected)
}

// Same input, ASCII glyph set (dart-sass `--no-unicode`).
test "undefined_variable_ascii" {
    let src = "a {\n  b: $undefined;\n}\n";
    let span = root.diag.Span { line: 2, col: 6, length: "$undefined".byte_length() };
    let got = root.diag.render_error(
        "Undefined variable.",
        src,
        "/tmp/input.scss",
        span,
        root.diag.GlyphSet.Ascii,
    );
    let expected = "Error: Undefined variable.
  ,
2 |   b: $undefined;
  |      ^^^^^^^^^^
  '
  /tmp/input.scss 2:6  root stylesheet";
    assert.equal(got, expected)
}

// dart-sass `@error "boom #{1 + 1}";` → message `"boom 2"`, span 1:1 len 22.
test "at_error_span_at_line_one" {
    let src = "@error \"boom #{1 + 1}\";\n";
    let span = root.diag.Span { line: 1, col: 1, length: "@error \"boom #{1 + 1}\"".byte_length() };
    let got = root.diag.render_error("\"boom 2\"", src, "/tmp/input.scss", span, root.diag.GlyphSet.Unicode);
    let expected = "Error: \"boom 2\"
  ╷
1 │ @error \"boom #{1 + 1}\";
  │ ^^^^^^^^^^^^^^^^^^^^^^
  ╵
  /tmp/input.scss 1:1  root stylesheet";
    assert.equal(got, expected)
}

// Gutter widens once the line number reaches double digits (dart-sass:
// 11 blank lines then `a { b: $x; }`, span 12:8 len 2).
test "wide_gutter_double_digit_line" {
    let src = "";
    for (let _k in baml.iter.Range.new(0, 11)) {
        src = src + "\n";
    }
    src = src + "a { b: $x; }\n";
    let span = root.diag.Span { line: 12, col: 8, length: "$x".byte_length() };
    let got = root.diag.render_error(
        "Undefined variable.",
        src,
        "/tmp/input.scss",
        span,
        root.diag.GlyphSet.Unicode,
    );
    let expected = "Error: Undefined variable.
   ╷
12 │ a { b: $x; }
   │        ^^
   ╵
  /tmp/input.scss 12:8  root stylesheet";
    assert.equal(got, expected)
}

// TAB expansion is byte-load-bearing: dart-sass renders `a {\n\tb: $x;\n}`
// with the leading tab as four spaces, span at 2:5 len 2.
test "tab_indent_expands_in_source_and_caret" {
    let src = "a {\n\tb: $x;\n}\n";
    let span = root.diag.Span { line: 2, col: 5, length: "$x".byte_length() };
    let got = root.diag.render_error(
        "Undefined variable.",
        src,
        "/tmp/input.scss",
        span,
        root.diag.GlyphSet.Unicode,
    );
    // Source: `\tb: $x;` → `    b: $x;`. `$` is source col 5 → display col 8
    // (4 for the tab + `b`,`:`,` ` = 3 → 7? dart reports col 5, display pad 7).
    let expected = "Error: Undefined variable.
  ╷
2 │     b: $x;
  │        ^^
  ╵
  /tmp/input.scss 2:5  root stylesheet";
    assert.equal(got, expected)
}

// Multi-line single span (dart-sass `a{b: (1px +\n2s)}` →
// "incompatible units", span 1:7 across two lines). This is a clean
// single span (no secondary labels), captured verbatim from dart-sass
// 1.100.0:
// ```text
//   ╷
// 1 │   a{b: (1px +
//   │ ┌───────^
// 2 │ │ 2s)}
//   │ └──^
//   ╵
// ```
test "multi_line_span_unicode_arms" {
    let src = "a{b: (1px +\n2s)}\n";
    // Span starts at the `1` of `1px` (1:7) and runs through `2s` on line 2.
    let start_byte = byte_index(src, 1, 7);
    let end_byte = byte_index(src, 2, 3); // just past `2s`
    let span = root.diag.Span { line: 1, col: 7, length: end_byte - start_byte };
    let frame = root.diag.Frame { url: "/tmp/input.scss", line: 1, col: 7, name: "root stylesheet" };
    let got = root.diag.render_snippet(src, span, [frame], root.diag.GlyphSet.Unicode);
    let expected = "  ╷\n"
        + "1 │   a{b: (1px +\n"
        + "  │ ┌───────^\n"
        + "2 │ │ 2s)}\n"
        + "  │ └──^\n"
        + "  ╵\n"
        + "  /tmp/input.scss 1:7  root stylesheet";
    assert.equal(got, expected)
}

// ASCII multi-line arms (`--no-unicode`), same `1px + 2s` input.
test "multi_line_span_ascii_arms" {
    let src = "a{b: (1px +\n2s)}\n";
    let start_byte = byte_index(src, 1, 7);
    let end_byte = byte_index(src, 2, 3);
    let span = root.diag.Span { line: 1, col: 7, length: end_byte - start_byte };
    let frame = root.diag.Frame { url: "/tmp/input.scss", line: 1, col: 7, name: "root stylesheet" };
    let got = root.diag.render_snippet(src, span, [frame], root.diag.GlyphSet.Ascii);
    let expected = "  ,\n"
        + "1 |   a{b: (1px +\n"
        + "  | ,-------^\n"
        + "2 | | 2s)}\n"
        + "  | '--^\n"
        + "  '\n"
        + "  /tmp/input.scss 1:7  root stylesheet";
    assert.equal(got, expected)
}

// A point (zero-length) span still draws exactly one caret.
test "zero_length_span_one_caret" {
    let src = "a {\n  b: 1 +\n";
    let span = root.diag.Span { line: 2, col: 9, length: 0 };
    let got = root.diag.render_error(
        "Expected expression.",
        src,
        "/tmp/input.scss",
        span,
        root.diag.GlyphSet.Unicode,
    );
    let expected = "Error: Expected expression.
  ╷
2 │   b: 1 +
  │         ^
  ╵
  /tmp/input.scss 2:9  root stylesheet";
    assert.equal(got, expected)
}

test "frames_stack_outermost_root" {
    let frames = [
        root.diag.Frame { url: "/tmp/input.scss", line: 2, col: 7, name: "f()" },
        root.diag.Frame { url: "/tmp/input.scss", line: 2, col: 7, name: "root stylesheet" },
    ];
    let got = root.diag.render_frames(frames);
    let expected = "  /tmp/input.scss 2:7  f()\n  /tmp/input.scss 2:7  root stylesheet";
    assert.equal(got, expected)
}

test "out_of_range_does_not_panic" {
    let src = "a {}\n";
    let span = root.diag.Span { line: 99, col: 99, length: 99 };
    // Just assert it produces *something* without panicking.
    let got = root.diag.render_error("x", src, "-", span, root.diag.GlyphSet.Unicode);
    assert.is_true(got.starts_with("Error: x"))
}

/// Test-only: byte offset of 1-based (line, col) in `src`.
function byte_index(src: string, line: int, col: int) -> int {
    let cur_line = 1;
    let cur_col = 1;
    // PORT: `src.char_indices()` → `root.std.char_indices_bytes` (byte offsets).
    for (let ic in root.std.char_indices_bytes(src)) {
        let i = ic._0;
        let ch = ic._1;
        if (cur_line == line && cur_col == col) {
            return i;
        }
        if (ch == "\n") {
            cur_line += 1;
            cur_col = 1;
        } else {
            cur_col += 1;
        }
    }
    src.byte_length()
}

// ----- Live dart-sass parity (gated behind SASSO_DIAG_LIVE) -----

// When `SASSO_DIAG_LIVE=1` and a `sass` binary is reachable
// (`SASS_BIN=/path/to/sass`, else `sass` on PATH), drive the real
// compiler and assert our snippet block is byte-identical to dart's.
test "live_dart_parity" {
    if (root.std.env_var("SASSO_DIAG_LIVE") != "1") {
        return;
    }
    let bin = root.std.env_var("SASS_BIN") ?? "sass";

    // (source, message, span, glyphs, no_unicode_flag). The `length` for
    // the multi-line case is computed from `byte_index` so the fixture
    // stays readable.
    let ml_src = "a{b: (1px +\n2s)}\n";
    let ml_len = byte_index(ml_src, 2, 3) - byte_index(ml_src, 1, 7);
    let cases: root.std.Tuple5<string, string, root.diag.Span, root.diag.GlyphSet, bool>[] = [
        root.std.Tuple5<string, string, root.diag.Span, root.diag.GlyphSet, bool> {
            _0: "a {\n  b: $undefined;\n}\n",
            _1: "Undefined variable.",
            _2: root.diag.Span { line: 2, col: 6, length: 10 },
            _3: root.diag.GlyphSet.Unicode,
            _4: false,
        },
        root.std.Tuple5<string, string, root.diag.Span, root.diag.GlyphSet, bool> {
            _0: "a {\n  b: $undefined;\n}\n",
            _1: "Undefined variable.",
            _2: root.diag.Span { line: 2, col: 6, length: 10 },
            _3: root.diag.GlyphSet.Ascii,
            _4: true,
        },
        root.std.Tuple5<string, string, root.diag.Span, root.diag.GlyphSet, bool> {
            _0: "@error \"x\";\n",
            _1: "\"x\"",
            _2: root.diag.Span { line: 1, col: 1, length: 10 },
            _3: root.diag.GlyphSet.Unicode,
            _4: false,
        },
        root.std.Tuple5<string, string, root.diag.Span, root.diag.GlyphSet, bool> {
            _0: "a {\n\tb: $x;\n}\n",
            _1: "Undefined variable.",
            _2: root.diag.Span { line: 2, col: 5, length: 2 },
            _3: root.diag.GlyphSet.Unicode,
            _4: false,
        },
        root.std.Tuple5<string, string, root.diag.Span, root.diag.GlyphSet, bool> {
            _0: ml_src,
            _1: "1px and 2s have incompatible units.",
            _2: root.diag.Span { line: 1, col: 7, length: ml_len },
            _3: root.diag.GlyphSet.Unicode,
            _4: false,
        },
        root.std.Tuple5<string, string, root.diag.Span, root.diag.GlyphSet, bool> {
            _0: ml_src,
            _1: "1px and 2s have incompatible units.",
            _2: root.diag.Span { line: 1, col: 7, length: ml_len },
            _3: root.diag.GlyphSet.Ascii,
            _4: true,
        },
    ];

    // PORT: `.iter().enumerate()` → an index counter.
    let i = 0;
    for (let c in cases) {
        let src = c._0;
        let msg = c._1;
        let span = c._2;
        let glyphs = c._3;
        let no_unicode = c._4;
        // PORT: `std::env::temp_dir()` → `$TMPDIR`, else `/tmp` (its Unix
        // definition); `std::process::id()` → `baml.sys.pid()`.
        let dir = root.std.path_join(
            root.std.env_var("TMPDIR") ?? "/tmp",
            `sasso-diag-${baml.sys.pid()}-${i}`,
        );
        let _ = root.std.create_dir_all(dir) catch (e) {
            let _io: baml.errors.Io => null
        };
        let path = root.std.path_join(dir, "input.scss");
        root.std.write_file(path, src) catch (e) {
            let _io: baml.errors.Io => root.std.panic("write fixture")
        };

        // PORT: `Command::new(&bin).arg(&path).arg("--no-color")…output()`
        // → `baml.sys.exec(bin, args, null)`.
        let args: string[] = [path, "--no-color"];
        if (no_unicode) {
            args.push("--no-unicode");
        }
        let output = baml.sys.exec(bin, args, null) catch (e) {
            _ => {
                return; // sass not runnable; skip silently.
            }
        };
        let stderr = output.stderr.to_string();
        let path_str = path;

        let ours = root.diag.render_error(msg, src, path_str, span, glyphs);

        // Compare the snippet block: from `Error:` through the location line.
        // dart-sass appends a trailing newline; trim a single one.
        let dart = root.std.trim_end_matches(stderr, "\n");
        // \n--- ours ---\n{ours}\n--- dart ---\n{dart}\n
        assert.equal(ours, dart);
        i += 1;
    }
}
