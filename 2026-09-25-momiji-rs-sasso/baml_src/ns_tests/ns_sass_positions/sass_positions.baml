// Ported from sasso `tests/sass_positions.rs` (namespace
// `root.tests.sass_positions`).
//
// Indented-syntax (`.sass`) positions: every line and column a diagnostic or
// a source map reports is a position in the `.sass` file itself.
//
// The front-end reconstructs SCSS from the indentation-structured source and
// hands it to the shared parser, so what it reconstructs decides what every
// `Pos` means. The reconstruction is position-preserving — one output line per
// source line, the source indentation kept, a block's `}` riding on its last
// line — and the two constructs that cannot be rewritten without moving
// columns (the `=`/`+` mixin shorthands, unquoted `@import` urls) are read by
// the parser in place instead.
//
// Every expectation here was taken from dart-sass 1.103.1 on the same input.

// PORT: `use sasso::{compile, compile_with_source_map, Options, OutputStyle,
// Syntax, WarnEvent};` — reached as `root.compile`,
// `root.compile_with_source_map`, `root.Options`, `root.OutputStyle`,
// `root.Syntax`, `root.WarnEvent`; `sasso::FsImporter` →
// `root.importer.FsImporter`, `sasso::Error` → `root.error.Error`.
// `PathBuf`/`Path` are `string`s; `std::env::temp_dir()` →
// `root.tests.support.temp_dir()`; `std::process::id()` → `baml.sys.pid()`;
// `Rc<RefCell<Vec<String>>>` → a shared `string[]`; `.unwrap()`/`.expect(..)`
// on a `Result` → the error propagates and fails the test;
// `std::fs::remove_dir_all(&dir).ok()` → `baml.fs.remove_dir_all` with its
// `Io` caught. Tuples are `root.std.Tuple2`/`Tuple3`. An assertion's message
// argument is kept as a `//` comment. `\u{2577}` / `\u{2502}` / `\u{2575}` /
// `\u{FFFD}` are written literally (`╷` / `│` / `╵` / `�`).

/// Compile indented source, with diagnostics enabled under `url`.
// PORT: `Result<String, sasso::Error>` → the `String`, the `Error` thrown.
function sass(src: string, url: string) -> string {
    root.compile(src, root.Options.default().with_syntax(root.Syntax.Sass).with_url(url))
}

/// PORT: `r.expect_err(msg)` on a `Result<String, sasso::Error>` — `f` is the
/// call producing the `Result`; its `Ok` panics with `msg`, its `Err` is
/// returned.
function expect_err(f: () -> string throws unknown, msg: string) -> root.error.Error {
    let found: root.error.Error? = null;
    let ok = f() catch (e) {
        let err: root.error.Error => {
            found = err;
            ""
        }
    };
    if let err: root.error.Error = found {
        return err;
    }
    root.std.panic(`${msg}: ${root.std.debug_str(ok)}`)
}

/// PORT: `r.is_err()` on a `Result<String, sasso::Error>` — `f` is the call
/// producing the `Result`.
function is_err(f: () -> string throws unknown) -> bool {
    let failed = false;
    let _ = f() catch (e) {
        let _err: root.error.Error => {
            failed = true;
            ""
        }
    };
    failed
}

/// The rendered diagnostic block of the error `src` raises.
function sass_err(src: string, url: string) -> string {
    expect_err(
        () -> string {
            sass(src, url)
        },
        "expected a compile error",
    )
        .to_string()
}

/// Every `formatted` warning block `src` produces.
function sass_warnings(src: string, url: string) -> string[] {
    let seen: string[] = [];
    let sink = seen;
    let opts = root.Options.default().with_syntax(root.Syntax.Sass).with_url(url).with_warn_handler((
        ev: root.WarnEvent,
    ) -> void {
        sink.push(ev.formatted);
    });
    // PORT: `.expect("compile")` — an `Err` propagates and fails the test.
    root.compile(src, opts);
    let out = root.std.clone_vec(seen);
    out
}

/// The `mappings` of an indented source compiled under `url`.
function sass_mappings(src: string, url: string) -> string {
    let opts = root.Options.default().with_syntax(root.Syntax.Sass).with_url(url);
    // PORT: `.expect("compile")` — an `Err` propagates and fails the test.
    root.compile_with_source_map(src, opts).source_map.mappings
}

/// PORT: `std::fs::remove_dir_all(&dir).ok()`.
function remove_dir_all_ok(dir: string) -> void {
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        let _e: baml.errors.Io => null
    };
}

test "an_error_points_at_its_sass_line_and_column" {
    // The column is the one in the `.sass` file: the reconstruction keeps each
    // statement's own indentation rather than re-indenting by nesting depth.
    // PORT: the Rust `\`-newline string continuation (which also drops the
    // next line's leading whitespace) is joined into one literal.
    assert.equal(
        sass_err(".a\n  .b\n    color: $undefined\n", "a.sass"),
        "Error: Undefined variable.\n  ╷\n3 │     color: $undefined\n  │            ^^^^^^^^^^\n  ╵\n  a.sass 3:12  root stylesheet",
    )
}

test "closed_blocks_and_comments_do_not_shift_later_lines" {
    // Each source line maps to one output line: a finished block, a blank line
    // and a multi-line comment all leave the lines after them where they were.
    let cases: root.std.Tuple2<string, root.std.Tuple2<int, int>>[] = [
        // A nested block, then a blank line, then the error.
        root.std.Tuple2<string, root.std.Tuple2<int, int>> {
            _0: ".a\n  color: red\n\n.b\n  .c\n    color: blue\n\n.d\n  color: $u\n",
            _1: root.std.Tuple2<int, int> { _0: 9, _1: 10 },
        },
        // A multi-line selector list.
        root.std.Tuple2<string, root.std.Tuple2<int, int>> {
            _0: ".a,\n.b\n  color: red\n.d\n  color: $u\n",
            _1: root.std.Tuple2<int, int> { _0: 5, _1: 10 },
        },
        // A multi-line loud comment.
        root.std.Tuple2<string, root.std.Tuple2<int, int>> {
            _0: "/* one\n   two\n   three */\n.d\n  color: $u\n",
            _1: root.std.Tuple2<int, int> { _0: 5, _1: 10 },
        },
        // The simplest shape of all.
        root.std.Tuple2<string, root.std.Tuple2<int, int>> {
            _0: ".a\n  color: red\n.d\n  color: $u\n",
            _1: root.std.Tuple2<int, int> { _0: 4, _1: 10 },
        },
        // A silent comment emits nothing, but still occupies its line —
        // including when it is a block's only child, or its last.
        root.std.Tuple2<string, root.std.Tuple2<int, int>> {
            _0: "a\n  // c\n.b\n  x: $u\n",
            _1: root.std.Tuple2<int, int> { _0: 4, _1: 6 },
        },
        root.std.Tuple2<string, root.std.Tuple2<int, int>> {
            _0: "a\n  // c\n\n.b\n  x: $u\n",
            _1: root.std.Tuple2<int, int> { _0: 5, _1: 6 },
        },
        root.std.Tuple2<string, root.std.Tuple2<int, int>> {
            _0: "a\n  b: c\n  // x\n.d\n  y: $u\n",
            _1: root.std.Tuple2<int, int> { _0: 5, _1: 6 },
        },
        root.std.Tuple2<string, root.std.Tuple2<int, int>> {
            _0: "a\n  // x\n  b: c\n.d\n  y: $u\n",
            _1: root.std.Tuple2<int, int> { _0: 5, _1: 6 },
        },
        root.std.Tuple2<string, root.std.Tuple2<int, int>> {
            _0: "a\n  // x\n  // y\n.d\n  z: $u\n",
            _1: root.std.Tuple2<int, int> { _0: 5, _1: 6 },
        },
        root.std.Tuple2<string, root.std.Tuple2<int, int>> {
            _0: "a\n  b: c\n    // deep\n.d\n  y: $u\n",
            _1: root.std.Tuple2<int, int> { _0: 5, _1: 6 },
        },
        root.std.Tuple2<string, root.std.Tuple2<int, int>> {
            _0: "// top\na\n  b: c\n.d\n  y: $u\n",
            _1: root.std.Tuple2<int, int> { _0: 5, _1: 6 },
        },
    ];
    for (let c in cases) {
        let src = c._0;
        let line = c._1._0;
        let col = c._1._1;
        let e = expect_err(
            () -> string {
                sass(src, "in.sass")
            },
            "expected an error",
        );
        // for {src:?}
        assert.equal(
            root.std.Tuple2<int, int> { _0: e.line, _1: e.col },
            root.std.Tuple2<int, int> { _0: line, _1: col },
        );
    }
}

test "a_warning_points_at_its_sass_column" {
    let w = sass_warnings(".a\n  .b\n    @warn \"hi\"\n", "b.sass");
    assert.equal(w.length(), 1);
    // {}  (w[0])
    assert.is_true(w[0].includes("b.sass 3:5"))
}

/// A scratch directory holding `_foo.sass`, for the import tests.
function scratch(tag: string) -> string {
    let dir = root.std.path_join(root.tests.support.temp_dir(), `sasso_sass_pos_${tag}_${baml.sys.pid()}`);
    // PORT: `.expect("mkdir")` / `.expect("write")` — the `Io` error propagates.
    root.std.create_dir_all(dir);
    root.std.write_file(root.std.path_join(dir, "_foo.sass"), "l\n  m: 1\n");
    dir
}

test "an_unquoted_import_url_carries_its_own_span" {
    // dart reads an unquoted url with the whole-value reader, so the
    // deprecation carets exactly the url token — `foo`, not the quoted
    // rewrite the front-end used to produce (two bytes longer).
    let dir = scratch("span");
    let src = "@import foo\n.a\n  color: red\n";
    let entry = root.std.path_join(dir, "c.sass");
    root.std.write_file(entry, src);
    let url = entry;
    let imp = root.importer.FsImporter.new([]);
    let seen: string[] = [];
    let sink = seen;
    let opts = root.Options.default()
        .with_syntax(root.Syntax.Sass)
        .with_importer(imp)
        .with_url(url)
        .with_warn_handler((ev: root.WarnEvent) -> void {
            sink.push(ev.formatted);
        });
    let css = root.compile(src, opts);
    assert.equal(css, "l {\n  m: 1;\n}\n\n.a {\n  color: red;\n}");
    let w = seen;
    assert.equal(w.length(), 1);
    // {}  (w[0])
    assert.is_true(w[0].includes("1 │ @import foo\n  │         ^^^\n"));
    // {}  (w[0])
    assert.is_true(w[0].includes("c.sass 1:9"));
    remove_dir_all_ok(dir)
}

test "an_unquoted_import_url_runs_to_the_comma" {
    // dart's `SassParser.importArgument` reads to the next top-level comma,
    // spaces included: `@import foo screen` is ONE url named `foo screen`
    // (dart carets all ten characters), not a url plus a media modifier.
    let dir = scratch("comma");
    let src = "@import foo screen\n";
    let entry = root.std.path_join(dir, "e.sass");
    root.std.write_file(entry, src);
    let url = entry;
    let imp = root.importer.FsImporter.new([]);
    let opts = root.Options.default()
        .with_syntax(root.Syntax.Sass)
        .with_importer(imp)
        .with_url(url)
        .with_warn_handler((_ev: root.WarnEvent) -> void {});
    let e = expect_err(
        () -> string {
            root.compile(src, opts)
        },
        "expected an error",
    );
    // The whole token is the url, so that is what cannot be found: dart carets
    // all ten characters at 1:9 and names none of them in the message.
    assert.equal(e.message, "Can't find stylesheet to import.");
    assert.equal(
        root.std.Tuple2<int, int> { _0: e.line, _1: e.col },
        root.std.Tuple2<int, int> { _0: 1, _1: 9 },
    );
    let block = e.to_string();
    // {block}
    assert.is_true(block.includes("│         ^^^^^^^^^^\n"));
    // An escaped `url(` is still a url FUNCTION, so the import is plain CSS —
    // and the name is re-emitted in dart's canonical lowercase spelling,
    // however it was written. (A vendor-prefixed name is NOT a url token here:
    // dart rejects `@import -c-url(…)`, unlike in a value position.)
    assert.equal(sass("@import u\\72l(//cdn/x.css)\n", "d.sass"), "@import url(//cdn/x.css);");
    assert.equal(sass("@import URL(//cdn/x.css)\n", "d.sass"), "@import url(//cdn/x.css);");
    // An escaped `)` inside an import's url is CONTENT, not the delimiter —
    // the url used to end there and lose its tail to comment stripping.
    assert.equal(
        sass("@import url(foo\\)//cdn/x.css)\n", "d.sass"),
        "@import url(foo\\)//cdn/x.css);",
    );
    assert.equal(
        sass("@import u\\72l(foo\\)//cdn/x.css)\n", "d.sass"),
        "@import url(foo\\)//cdn/x.css);",
    );
    // An ESCAPED `\\#{` is literal text, so the path is STATIC: dart reads the
    // whole `foo\\#{bar}.scss` as one url — its deprecation carets all fifteen
    // characters, and it then reports the url as not found. sasso used to
    // reject the line as a dynamic path instead.
    let src2 = "@import foo\\#{bar}.scss\n";
    root.std.write_file(entry, src2);
    let e = expect_err(
        () -> string {
            root.compile(src2, opts)
        },
        "expected an error",
    );
    // {}  (e.message)
    assert.is_true(e.message.includes("Can't find stylesheet to import"));
    // {}  (e.message)
    assert.is_true(!e.message.includes("dynamic"));
    // The at-rule KEYWORD may be escaped; the parser decodes it, so the line
    // analysis must too, or `@im\\70ort` is taken for an unknown at-rule and
    // its unquoted url is truncated at the `//`.
    assert.equal(sass("@im\\70ort http://x/y.css\n", "d.sass"), "@import \"http://x/y.css\";");
    // The keyword's escapes are decoded before the arguments are scanned, so a
    // quoted url is still seen as quoted and its trailing comment is dropped.
    root.std.write_file(entry, "@im\\70ort \"foo\" // c\n.a\n  b: c\n");
    let css = root.compile("@im\\70ort \"foo\" // c\n.a\n  b: c\n", opts);
    assert.equal(css, "l {\n  m: 1;\n}\n\n.a {\n  b: c;\n}");
    // An explicit `;` ends the url, so a trailing silent comment after it is
    // a comment — dart imports `foo` from `@import foo; // t`.
    root.std.write_file(entry, "@import foo; // t\n");
    let css = root.compile("@import foo; // t\n", opts);
    assert.equal(css, "l {\n  m: 1;\n}");
    // Two comma-separated urls are two imports.
    root.std.write_file(root.std.path_join(dir, "_bar.sass"), "n\n  o: 2\n");
    let src = "@import foo, bar\n";
    root.std.write_file(entry, src);
    let css = root.compile(src, opts);
    assert.equal(css, "l {\n  m: 1;\n}\n\nn {\n  o: 2;\n}");
    remove_dir_all_ok(dir)
}

test "a_css_import_url_is_written_back_quoted" {
    // A `.css`/protocol url is a plain-CSS import, emitted with its text
    // verbatim inside quotes, as dart emits it.
    assert.equal(sass("@import other.css\n", "c.sass"), "@import \"other.css\";");
    assert.equal(sass("@import http://x/y.css\n", "d.sass"), "@import \"http://x/y.css\";");
    assert.equal(sass("@import url(http://x/y.css)\n", "d.sass"), "@import url(http://x/y.css);")
}

test "a_double_slash_inside_a_url_is_not_a_comment" {
    // dart scans `url(` and its contents as one token; only the exact `url`
    // function qualifies, so `my-url(//y)` really does start a comment.
    assert.equal(sass(".a\n  b: url(http://x/y)\n", "a.sass"), ".a {\n  b: url(http://x/y);\n}");
    assert.equal(
        sass(".a\n  background: url(//cdn/x.png)\n", "a.sass"),
        ".a {\n  background: url(//cdn/x.png);\n}",
    );
    assert.equal(sass(".a\n  b: URL(//y)\n", "a.sass"), ".a {\n  b: url(//y);\n}");
    assert.is_true(
        is_err(() -> string {
            sass(".a\n  b: my-url(//y)\n", "a.sass")
        }),
    );
    // A VENDOR-PREFIXED url is a url token too — the shared value parser reads
    // `-c-url(` as one and emits it bare — while `my-url(` above is not.
    assert.equal(
        sass("a\n  b: -c-url(//cdn/x)\n  d: red\n", "a.sass"),
        "a {\n  b: url(//cdn/x);\n  d: red;\n}",
    );
    // The name is matched the way the value parser matches it, escapes and
    // all: `u\\72l(` is `url(`, so its `//` is url text too.
    assert.equal(
        sass("a\n  b: u\\72l(//cdn/x)\n  c: red\n", "a.sass"),
        "a {\n  b: url(//cdn/x);\n  c: red;\n}",
    );
    // An escaped `)` is url CONTENT and does not close the token.
    assert.equal(sass("a\n  b: url(foo\\)//cdn)\n", "a.sass"), "a {\n  b: url(foo\\)//cdn);\n}");
    // A declaration AFTER one is still its own statement: the line scanners
    // that decide where a logical line ends must skip the url token too, or
    // `url(http://x/y)` reads as an unterminated paren and swallows the next
    // line (`b: url(http://x/y) c;` / `: red;`).
    assert.equal(
        sass(".a\n  b: url(http://x/y)\n  c: red\n", "a.sass"),
        ".a {\n  b: url(http://x/y);\n  c: red;\n}",
    );
    assert.equal(
        sass(".a\n  b: url(//x/y)\n  c: red\n", "a.sass"),
        ".a {\n  b: url(//x/y);\n  c: red;\n}",
    );
    // A `url(` may be left OPEN at the end of its line — the indented syntax
    // continues it — and its contents stay verbatim across the join, so the
    // `//` in a protocol url is still not a comment (four sass-spec cases).
    assert.equal(sass("a\n  b: url(\n    c)\n", "a.sass"), "a {\n  b: url(c);\n}");
    assert.equal(sass("a\n  b: url(c\n    )\n", "a.sass"), "a {\n  b: url(c);\n}");
    assert.equal(
        sass("a\n  b: url(\n    http://x/y)\n  d: red\n", "a.sass"),
        "a {\n  b: url(http://x/y);\n  d: red;\n}",
    );
    // A `\\`+newline inside a quoted string is a CSS line continuation, which
    // SCSS spells the same way — so it is kept rather than collapsed, and a
    // diagnostic on the continuation line reports THERE (dart: 3:5).
    assert.equal(sass(".a\n  b: \"foo\\\n  bar\"\n", "b.sass"), ".a {\n  b: \"foo  bar\";\n}");
    let e = expect_err(
        () -> string {
            sass(".a\n  b: \"foo\\\n  #{$undef}\"\n", "b.sass")
        },
        "expected an error",
    );
    assert.equal(
        root.std.Tuple2<int, int> { _0: e.line, _1: e.col },
        root.std.Tuple2<int, int> { _0: 3, _1: 5 },
    );
    // A trailing `//` is still a comment, inside and outside a string.
    assert.equal(sass(".a\n  b: c // t\n", "a.sass"), ".a {\n  b: c;\n}");
    assert.equal(sass(".a\n  b: \"http://x\" // t\n", "a.sass"), ".a {\n  b: \"http://x\";\n}");
    assert.equal(sass(".a\n  b: url(x) // t\n", "a.sass"), ".a {\n  b: url(x);\n}")
}

test "source_maps_point_into_the_sass_file" {
    // Every `mappings` string here is dart-sass 1.103.1's for the same input.
    let cases: root.std.Tuple2<string, string>[] = [
        root.std.Tuple2<string, string> { _0: ".a\n  color: red\n", _1: "AAAA;EACE" },
        // A silent comment, a blank line, a multi-line selector list and a
        // loud comment — none of them shift a later mapping.
        root.std.Tuple2<string, string> {
            _0: "// silent\n.a\n  color: red\n\n  .b,\n  .c\n    /* loud */\n    width: 1px\n",
            _1: "AACA;EACE;;AAEA;AAAA;AAEE;EACA",
        },
        // The mixin shorthands: `+mx(1)`'s ARGUMENT maps to its own column,
        // which rewriting `+mx` to `@include mx` would have moved by eight.
        root.std.Tuple2<string, string> {
            _0: "=mx($x)\n  m: $x\n.d\n  +mx(1)\n",
            _1: "AAEA;EADE,GAEI",
        },
        // A parent reference and a bubbled `@media`.
        root.std.Tuple2<string, string> {
            _0: ".a\n  &:hover\n    x: 1\n@media screen\n  .b\n    y: 2\n",
            _1: "AACE;EACE;;;AACJ;EACE;IACE",
        },
        // A custom property.
        root.std.Tuple2<string, string> { _0: ".a\n  --v: 1px\n  b: c\n", _1: "AAAA;EACE;EACA" },
        // A top-level multi-line comment.
        root.std.Tuple2<string, string> {
            _0: "/* one\n   two */\n.a\n  b: c\n",
            _1: "AAAA;AAAA;AAEA;EACE",
        },
        // The legacy escaped-selector marker is not part of the selector:
        // dart maps `\:hover` to the `:`, one column past the `\`.
        root.std.Tuple2<string, string> { _0: ".a\n  \\:hover\n    b: c\n", _1: "AACG;EACC" },
        root.std.Tuple2<string, string> { _0: ".a\n  :hover\n    b: c\n", _1: "AACE;EACE" },
    ];
    for (let c in cases) {
        let src = c._0;
        let expected = c._1;
        // for {src:?}
        assert.equal(sass_mappings(src, "in.sass"), expected);
    }
}

test "the_shorthands_still_compile_to_what_they_stand_for" {
    // Reading `=`/`+` in the parser rather than rewriting them upstream must
    // not change what they mean.
    assert.equal(sass("=a\n  b: c\nd\n  +a\n", "x.sass"), "d {\n  b: c;\n}");
    assert.equal(sass("=a($x)\n  b: $x\nd\n  +a(1)\n", "x.sass"), "d {\n  b: 1;\n}");
    assert.equal(sass("=a\n  @content\nd\n  +a\n    e: f\n", "x.sass"), "d {\n  e: f;\n}");
    // A bare `+` is the next-sibling combinator, not an include.
    assert.equal(sass("d\n  +\n    a\n      x: y\n", "x.sass"), "d + a {\n  x: y;\n}");
    // A `+name` include with `using`, and a namespaced one.
    assert.equal(
        sass("=a\n  @content(1)\nd\n  +a using ($v)\n    e: $v\n", "x.sass"),
        "d {\n  e: 1;\n}",
    )
}

test "the_shorthand_keeps_the_rules_the_keyword_has" {
    // `=--name` is the plain-CSS mixin spelling dart reserves: rejected here
    // exactly as `@mixin --name` is, pointing at the name (dart: 1:2).
    let e = expect_err(
        () -> string {
            sass("=--a\n  b: c\n", "b.sass")
        },
        "expected an error",
    );
    assert.equal(
        root.std.Tuple2<int, int> { _0: e.line, _1: e.col },
        root.std.Tuple2<int, int> { _0: 1, _1: 2 },
    );
    // {}  (e.message)
    assert.is_true(e.message.includes("beginning with -- are forbidden"));
    // A mixin whose NAME is the keyword the shorthand stands for still works:
    // the prelude is everything after the sigil, with no keyword to strip.
    assert.equal(sass("=mixin\n  b: c\n.d\n  +mixin\n", "x.sass"), ".d {\n  b: c;\n}");
    assert.equal(sass("=include\n  b: c\n.d\n  +include\n", "x.sass"), ".d {\n  b: c;\n}")
}

test "an_escaped_keyword_is_the_keyword_it_spells" {
    // The parser decodes an escaped at-rule keyword, so the line analysis must
    // too: `@fu\\6e ction --a()` is a plain-CSS custom function, whose
    // `result:` may not have anything indented beneath it. Reading the name
    // with a raw identifier scan stopped at the backslash, missed the `--`,
    // and emitted `result: 1 { nested: 2; } ;` — invalid CSS.
    let e = expect_err(
        () -> string {
            sass("@fu\\6e ction --a()\n  result: 1\n    nested: 2\n", "b.sass")
        },
        "expected an error",
    );
    assert.equal(
        root.std.Tuple2<int, int> { _0: e.line, _1: e.col },
        root.std.Tuple2<int, int> { _0: 3, _1: 5 },
    );
    // {}  (e.message)
    assert.is_true(e.message.includes("Nothing may be indented beneath a @function result"))
}

test "a_comment_opening_on_a_bare_line_still_opens" {
    // dart drops blank lines between a BARE `/*` and the comment's first text,
    // while a blank BETWEEN two body lines is kept. The renderer's first entry
    // used to be that blank, so the `/*` was never emitted and the whole
    // reconstruction stopped being valid SCSS.
    assert.equal(sass("/*\n\n  a\n", "c.sass"), "/* a */");
    assert.equal(sass("/*\n\n\n  a\n", "c.sass"), "/* a */");
    assert.equal(sass("/*\n\n  a\n  b\n", "c.sass"), "/* a\n * b */");
    assert.equal(sass("/*\n\n  a\n  */\n.z\n  y: 1\n", "c.sass"), "/* a\n * */\n.z {\n  y: 1;\n}");
    // A blank AFTER content is still part of the comment.
    assert.equal(sass("/*\n  a\n\n  b\n", "c.sass"), "/* a\n *\n * b */");
    assert.equal(sass("/* x\n\n  a\n", "c.sass"), "/* x\n *\n * a */")
}

test "an_escaped_keyword_still_spans_its_prelude" {
    // `@use` may put its url on the next indented line, and dart accepts that.
    // The prelude was derived by stripping the DECODED name from the RAW
    // spelling, so an escaped keyword left `us\\65` as the prelude, the
    // directive looked complete, and the url was rejected as an indented
    // child. (`@import` is the opposite case — dart rejects a continuation
    // there — which is why only `@use` shows the bug.)
    let dir = scratch("usecont");
    let entry = root.std.path_join(dir, "c.sass");
    let url = entry;
    let imp = root.importer.FsImporter.new([]);
    let opts = root.Options.default()
        .with_syntax(root.Syntax.Sass)
        .with_importer(imp)
        .with_url(url)
        .with_warn_handler((_ev: root.WarnEvent) -> void {});
    for (let src in ["@use\n  \"foo\"\n", "@us\\65\n  \"foo\"\n", "@use \"foo\"\n"]) {
        root.std.write_file(entry, src);
        // for {src:?}
        assert.equal(root.compile(src, opts), "l {\n  m: 1;\n}");
    }
    remove_dir_all_ok(dir)
}

test "an_invalid_escape_resolves_like_the_parser_resolves_it" {
    // A surrogate escape becomes U+FFFD, so `@import\\D800` is NOT `@import`:
    // it is a generic at-rule, which may own a block. Stopping the decode at
    // the invalid code point reported the name's prefix and applied
    // `@import`'s "nothing may be indented" rule to it.
    assert.equal(
        sass("@import\\D800 foo\n  a: b\n", "f.sass"),
        "@charset \"UTF-8\";\n@import�foo {\n  a: b;\n}",
    )
}

test "a_multi_line_directive_prelude_keeps_its_own_lines" {
    // A prelude continuation is joined ON ITS OWN LINE, not with a space, so a
    // diagnostic inside it points at the line it was written on, as dart does.
    let cases = [
        "@each $a in\n  $undef\n  .x\n    y: 1\n",
        "$v:\n  $undef\n",
        "@if 1 ==\n  $undef\n  .x\n    y: 1\n",
    ];
    for (let src in cases) {
        let e = expect_err(
            () -> string {
                sass(src, "in.sass")
            },
            "expected an error",
        );
        // for {src:?}
        assert.equal(
            root.std.Tuple2<int, int> { _0: e.line, _1: e.col },
            root.std.Tuple2<int, int> { _0: 2, _1: 3 },
        );
        // {}  (e.message)
        assert.is_true(e.message.includes("Undefined variable"));
    }
    // The prelude still reads the same text: a trailing comma does NOT
    // continue it (`@each $a in b,` iterates the one-element list `(b,)` and
    // the deeper lines are its body), exactly as dart-sass 1.103.1 reads it.
    assert.equal(sass("@each $a in b,\n c\n  .#{$a}\n    d: $a\n", "in.sass"), "c .b {\n  d: b;\n}")
}

test "a_custom_property_keeps_its_own_spacing" {
    // A custom property's value is emitted verbatim, so the whitespace after
    // the colon is part of it: dart writes `--v:1px` with no space, and
    // collapses a run of them to one. The front-end used to normalize every
    // spelling to `: `, which changed the CSS.
    assert.equal(sass(".a\n  --v:1px\n", "a.sass"), ".a {\n  --v:1px;\n}");
    assert.equal(sass(".a\n  --v: 1px\n", "a.sass"), ".a {\n  --v: 1px;\n}");
    assert.equal(sass(".a\n  --v:  1px\n", "a.sass"), ".a {\n  --v: 1px;\n}");
    assert.equal(sass(".a\n  --v:   1px\n", "a.sass"), ".a {\n  --v: 1px;\n}");
    assert.equal(sass(".a\n  --v:1px 2px\n", "a.sass"), ".a {\n  --v:1px 2px;\n}");
    assert.equal(sass(".a\n  --v:#{1 + 1}\n", "a.sass"), ".a {\n  --v:2;\n}");
    // Whitespace BEFORE the colon is part of the line too: trimming it moved
    // the value a column left (dart reports 2:10 here, not 2:9).
    assert.equal(sass(".a\n  --v : 1px\n", "a.sass"), ".a {\n  --v: 1px;\n}");
    let e = expect_err(
        () -> string {
            sass(".a\n  --v :#{$undef}\n", "f.sass")
        },
        "expected an error",
    );
    assert.equal(
        root.std.Tuple2<int, int> { _0: e.line, _1: e.col },
        root.std.Tuple2<int, int> { _0: 2, _1: 10 },
    )
}

test "compressed_output_is_unaffected_by_the_line_padding" {
    // The reconstruction pads with blank lines; compressed output has none.
    let opts = root.Options.default()
        .with_syntax(root.Syntax.Sass)
        .with_style(root.OutputStyle.Compressed)
        .with_url("in.sass");
    let css = root.compile("// c\n.a\n  b: c\n\n.d\n  e: f\n", opts);
    assert.equal(css, ".a{b:c}.d{e:f}")
}

test "a_brace_inside_a_string_does_not_close_an_interpolation" {
    // The front-end scans a line to decide where a value ends. A `}` inside a
    // STRING is value text, not the end of the interpolation around it — and
    // the `//` that follows is inside the string too, not a comment. dart-sass
    // reads `.a` / `  b: #{"} // not a comment"}` as one declaration whose
    // value is `} // not a comment`.
    // PORT: `.expect("compile")` — an `Err` propagates and fails the test.
    assert.equal(
        sass(".a\n  b: #{\"} // not a comment\"}\n", "a.sass"),
        ".a {\n  b: } // not a comment;\n}",
    );
    // The same in a custom property, whose value is captured verbatim.
    assert.equal(sass(".a\n  --x: #{\"}\"}y\n", "a.sass"), ".a {\n  --x: }y;\n}")
    // (A `}` interpolated into a SELECTOR is an error in dart too — "expected
    // selector", against the interpolated output — so there is nothing to
    // preserve there.)
}

test "an_escaped_delimiter_in_a_custom_value_is_literal_text" {
    // `\{` is an escaped brace — a complete custom-property value, not an open
    // block. Counting it as a bracket left the value "open", so every later
    // line was swallowed into it and the file ended mid-declaration.
    assert.equal(
        sass(".a\n  --x: \\{\n.b\n  c: d\n", "a.sass"),
        ".a {\n  --x: \\{;\n}\n\n.b {\n  c: d;\n}",
    );
    // An escaped quote does not open a string either, and an escaped `;` is
    // part of the value rather than its terminator.
    assert.equal(
        sass(".a\n  --x: \\\"\n.b\n  c: d\n", "a.sass"),
        ".a {\n  --x: \\\";\n}\n\n.b {\n  c: d;\n}",
    );
    assert.equal(
        sass(".a\n  --x: a\\;b\n.b\n  c: d\n", "a.sass"),
        ".a {\n  --x: a\\;b;\n}\n\n.b {\n  c: d;\n}",
    );
    // A hex escape is one token however long it is, and dart re-serializes it
    // canonically: `\61 b` is the identifier `ab`.
    assert.equal(sass(".a\n  --x: \\61 b\n", "a.sass"), ".a {\n  --x: ab;\n}")
}

test "a_mismatched_closer_in_a_custom_value_reaches_the_parser" {
    // `(]` is an error in dart, reported at the `]`. The front-end decides
    // where a custom value ENDS, and a net-depth count made `(]` look closed,
    // so an indented line under it was reported as a stray child instead.
    let e = expect_err(
        () -> string {
            sass(".a\n  --x: (]\n    b: c\n", "a.sass")
        },
        "expected an error",
    );
    assert.equal(
        root.std.Tuple2<int, int> { _0: e.line, _1: e.col },
        root.std.Tuple2<int, int> { _0: 2, _1: 9 },
    );
    // {}  (e.message)
    assert.is_true(e.message.includes("expected \")\"."));
    // The same line with nothing under it reports identically.
    let e = expect_err(
        () -> string {
            sass(".a\n  --x: (]\n", "a.sass")
        },
        "expected an error",
    );
    assert.equal(
        root.std.Tuple2<int, int> { _0: e.line, _1: e.col },
        root.std.Tuple2<int, int> { _0: 2, _1: 9 },
    );
    // A closer with NO opener ends the value where it stands, so the next line
    // is its own statement rather than a continuation.
    let e = expect_err(
        () -> string {
            sass(".a\n  --x: ]\n  b: c\n", "a.sass")
        },
        "expected an error",
    );
    assert.equal(
        root.std.Tuple2<int, int> { _0: e.line, _1: e.col },
        root.std.Tuple2<int, int> { _0: 2, _1: 8 },
    );
    // A balanced multi-line value still joins.
    assert.equal(sass(".a\n  --x: (1,\n    2)\n", "a.sass"), ".a {\n  --x: (1,\n    2);\n}")
}

test "an_import_url_spanning_lines_keeps_its_url" {
    // The url token's padding is not part of the url, so a `url(` opened on
    // one line and closed on another is the same import dart emits.
    assert.equal(
        sass("@import url(\n  http://x/y.css\n)\n", "a.sass"),
        "@import url(http://x/y.css);",
    )
}

test "a_backslash_continuation_is_not_a_line_wrap" {
    // The front-end used to drop a trailing backslash and join the next line
    // with a space, so `b: c\` + `d` compiled as `b: c d`. dart has no such
    // wrap: the backslash is an escape, and a newline is not something it can
    // escape, so the pair has to reach the parser for it to say so.
    let cases: root.std.Tuple3<string, int, int>[] = [
        root.std.Tuple3<string, int, int> { _0: ".a\n  b: c\\\n  d\n", _1: 2, _2: 8 },
        root.std.Tuple3<string, int, int> { _0: ".a\n  b: c\\\n    d\n", _1: 2, _2: 8 },
        root.std.Tuple3<string, int, int> {
            _0: "@each $a in 1,\\\n  2\n  .x\n    y: $a\n",
            _1: 1,
            _2: 16,
        },
        root.std.Tuple3<string, int, int> { _0: "@import url(foo\\\nbar.css)\n", _1: 1, _2: 17 },
    ];
    for (let c in cases) {
        let src = c._0;
        let line = c._1;
        let col = c._2;
        let e = expect_err(
            () -> string {
                sass(src, "a.sass")
            },
            "expected an error",
        );
        // for {src:?}
        assert.equal(
            root.std.Tuple2<int, int> { _0: e.line, _1: e.col },
            root.std.Tuple2<int, int> { _0: line, _1: col },
        );
        // {}  (e.message)
        assert.is_true(e.message.includes("Expected escape sequence."));
    }
    // Inside a quoted string it stays a CSS line continuation, and the next
    // line's indentation is part of the string.
    assert.equal(sass(".a\n  b: \"x\\\n  y\"\n", "a.sass"), ".a {\n  b: \"x  y\";\n}")
}

test "two_statements_on_one_line_point_at_the_second" {
    // dart carets the statement that should not be there — the first character
    // after the `;` — where sasso pointed at the `;` itself.
    let cases: root.std.Tuple3<string, int, int>[] = [
        root.std.Tuple3<string, int, int> { _0: ".a\n  b: c; d: e\n", _1: 2, _2: 9 },
        root.std.Tuple3<string, int, int> { _0: ".a\n  b: c;d: e\n", _1: 2, _2: 8 },
        root.std.Tuple3<string, int, int> { _0: ".a\n  b: c ; d: e\n", _1: 2, _2: 10 },
        root.std.Tuple3<string, int, int> { _0: ".a\n  b: \"x;y\"; d: e\n", _1: 2, _2: 13 },
        root.std.Tuple3<string, int, int> { _0: "@import foo;bar\n", _1: 1, _2: 13 },
        // An escaped `;` separates statements for dart too — the escape does
        // not hide it from the indented syntax's one-statement-per-line rule.
        root.std.Tuple3<string, int, int> { _0: "@import foo\\;bar\n", _1: 1, _2: 14 },
    ];
    for (let c in cases) {
        let src = c._0;
        let line = c._1;
        let col = c._2;
        let e = expect_err(
            () -> string {
                sass(src, "a.sass")
            },
            "expected an error",
        );
        // for {src:?}
        assert.equal(
            root.std.Tuple2<int, int> { _0: e.line, _1: e.col },
            root.std.Tuple2<int, int> { _0: line, _1: col },
        );
        // {}  (e.message)
        assert.is_true(e.message.includes("multiple statements on one line"));
    }
    // A `;` with only whitespace or a loud comment after it is still one
    // statement.
    assert.equal(sass(".a\n  b: c;\n", "a.sass"), ".a {\n  b: c;\n}");
    assert.equal(sass(".a\n  b: c;  \n", "a.sass"), ".a {\n  b: c;\n}")
}

test "a_custom_value_continues_past_a_trailing_backslash" {
    // The front-end decides where a custom-property value ends. A line ending
    // in an unpaired backslash always continues: inside a string that is a
    // legal CSS line continuation, and anywhere else it is the error dart
    // reports for one — either way the pair belongs to the parser, not to a
    // front-end that cut the value off at the line break.
    assert.equal(sass(".a\n  --x: \"a\\\n    b\"\n", "a.sass"), ".a {\n  --x: \"a\\\n    b\";\n}");
    let e = expect_err(
        () -> string {
            sass(".a\n  --x: c\\\n    d\n", "a.sass")
        },
        "expected an error",
    );
    assert.equal(
        root.std.Tuple2<int, int> { _0: e.line, _1: e.col },
        root.std.Tuple2<int, int> { _0: 2, _1: 10 },
    );
    // {}  (e.message)
    assert.is_true(e.message.includes("Expected escape sequence."));
    // An EVEN number of backslashes is a complete value: the last one is
    // escaped, not an escape.
    let e = expect_err(
        () -> string {
            sass(".a\n  --x: c\\\\\n    d\n", "a.sass")
        },
        "expected an error",
    );
    // {}  (e.message)
    assert.is_true(e.message.includes("Nothing may be indented beneath a custom property"))
}

test "a_second_statement_after_a_continuation_reports_its_own_line" {
    // A logical line can span several source lines — a bracket continuation
    // keeps its line breaks — so the `;` that splits it can be far below the
    // line the statement started on. It used to report the statement's first
    // line with a column counting every character before the `;`.
    let e = expect_err(
        () -> string {
            sass(".a\n  b: (\n    c\n  ); d: e\n", "a.sass")
        },
        "expected an error",
    );
    assert.equal(
        root.std.Tuple2<int, int> { _0: e.line, _1: e.col },
        root.std.Tuple2<int, int> { _0: 4, _1: 6 },
    );
    // {}  (e.message)
    assert.is_true(e.message.includes("multiple statements on one line"));
    // A statement that occupies one line is unchanged.
    let e = expect_err(
        () -> string {
            sass(".a\n  b: c; d: e\n", "a.sass")
        },
        "expected an error",
    );
    assert.equal(
        root.std.Tuple2<int, int> { _0: e.line, _1: e.col },
        root.std.Tuple2<int, int> { _0: 2, _1: 9 },
    )
}
