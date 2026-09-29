// Ported from sasso `tests/diagnostics.rs` (integration test crate;
// namespace `root.tests.diagnostics`).
//
// Byte-exact stderr diagnostics parity against the dart-sass 1.100 fixtures.
//
// For each `tests/fixtures/diagnostics/<name>.scss` that ships a captured
// `<name>.ascii.stderr` (dart-sass `--no-unicode`), run the `sasso` binary
// from inside that directory with the bare basename and `--no-unicode` (the
// exact way the fixtures were captured) and assert sasso's stderr is
// byte-identical.
//
// The set of fixtures that currently match is gated by an allow-list so the
// test stays green while later sub-steps (deprecations, the multi-span
// renderer, `@import` source-swap) grow it. Each non-matching fixture is
// listed with the reason it is skipped.
//
// PORT: `use sasso::{compile, Options}` → `root.compile` / `root.Options`.
// Assertion messages (`assert!(c, "…")`) are kept as `//` comments above the
// assert. `\u{…}` escapes are written as the literal characters.

/// Fixtures whose `--no-unicode` stderr sasso reproduces byte-for-byte today.
function MATCHING() -> string[] {
    [
        // @debug — single line, no snippet/frames.
        "debug-string",
        "debug-values",
        // @warn — WARNING: + 4-space frame trace + blank line.
        "warn-plain",
        "warn-interpolated",
        "warn-in-mixin",
        // @error — snippet at the call site, 2-space frame trace.
        "error-plain",
        "error-interpolated",
        "error-in-mixin",
        "error-stack-nested",
        "error-in-function",
        "error-cross-file",
        // The nine members dart REMOVED from `sass:color` (#65): a three-part
        // message whose `Recommendation:` line is built from the call's own
        // arguments. Two fixtures because the paths differ in what they can get
        // wrong — the namespaced one is the message itself, and the one reached
        // through `@use "sass:color" as *` also locks the frame trace and the
        // caret, which spanned a single column for a starred member until #65.
        "error-color-removed-member",
        "error-color-removed-member-star",
        // Compile errors with a positioned span (undefined variable).
        "compile-undefined-variable",
        "compile-undefined-variable-stack",
        "compile-tab-expansion",
        "compile-gutter-alignment",
        // Deprecations (registry sub-step): the fully-static `@import` warning.
        "deprecation-import",
        // The global-built-in family, and the two that ride along with it.
        "deprecation-global-builtin",
        "deprecation-feature-exists",
        "deprecation-call-string",
        // The legacy `sass:color` members, whose suggestions are computed from the
        // call's own arguments.
        "deprecation-color-functions",
        "deprecation-darken",
        // The legacy `if()`, whose suggestion is the arguments written back out.
        "deprecation-if-function",
        // A dropped selector announcing itself: dart omits the rule from the CSS
        // and this warning is the only sign it did. sasso dropped it silently
        // until #119 — 45 rules disappeared from Lichess's build with no notice.
        // Its sibling fixture `deprecation-bogus-combinators` is dart's OTHER
        // message for a trailing combinator, which needs the two-span renderer and
        // stays out of this list.
        "deprecation-bogus-combinators-invalid",
        // The same warning behind a multi-byte selector: the span helper mixes
        // character columns with byte offsets by nature (dart's columns are
        // characters, our Span length is source bytes), and got it wrong the first
        // time — twelve columns late on a CJK selector.
        "deprecation-bogus-combinators-non-ascii",
        // The warning is delayed until after the rule body, so the error path is
        // its own question: dart drops it when that body fails, and keeps it when
        // a LATER rule fails. Both, because gating on success could otherwise be
        // over-broad with nothing to notice.
        "deprecation-bogus-combinators-body-error",
        "deprecation-bogus-combinators-later-error",
        // Four CSS filter calls that must stay silent beside one real Sass colour
        // call that must still warn (#122). Both halves in one fixture on purpose:
        // simply not warning would satisfy the first and fail the second.
        "deprecation-global-builtin-css-filter",
        // The same rule reached through a function reference: fixing only the
        // direct call left `meta.call(meta.get-function("grayscale"), 1)` warning.
        "deprecation-global-builtin-call-ref",
        // `color-module-compat`, which sasso never emitted before #124: all five
        // of dart's shapes in one fixture — a number to `color.grayscale` (through
        // `@use "sass:color" as *`), `color.invert` and `color.opacity`, and a
        // Microsoft filter argument to `color.alpha` in either overload. Two calls
        // that must stay silent ride along, because emitting nothing would satisfy
        // neither half. Byte parity includes dart's missing closing parenthesis in
        // the `opacity` message, which sass-spec locks.
        "deprecation-color-module-compat",
        // The same rule reached through a function reference, the path that stayed
        // silent when only the direct call was fixed for `global-builtin` above.
        "deprecation-color-module-compat-call-ref",
        // And through `@use "sass:color" as *`, where the MICROSOFT half is the one
        // at risk: the global spelling returns that call verbatim before dispatch
        // (dart deprecates nothing for it), and doing the same for the bare name a
        // star import binds skipped the module member this rule belongs to. The
        // star `grayscale` in the fixture above covers the numeric half.
        "deprecation-color-module-compat-star",
    ]
}

function fixtures_dir() -> string {
    root.std.path_join(root.tests.support.manifest_dir(), "tests/fixtures/diagnostics")
}

/// Run sasso from inside the fixtures dir with the bare basename + --no-unicode,
/// returning captured stderr verbatim.
function run_sasso_stderr(name: string) -> string {
    let bin = root.tests.support.sasso_bin();
    // PORT: `Command::output()` gives the child a closed stdin → `stdin: ""`.
    let out = baml.sys.exec(
        bin,
        ["--no-unicode", `${name}.scss`],
        baml.sys.ProcessOptions {
            cwd: fixtures_dir(),
            env: null,
            timeout_ms: null,
            stdin: "",
            stderr: null,
        },
    ) catch (e) {
        _ => root.std.panic("run sasso")
    };
    root.std.from_utf8_lossy(out.stderr)
}

test "diagnostics_match_dart_ascii_fixtures" {
    let dir = fixtures_dir();
    for (let name in MATCHING()) {
        let expected = root.std.read_to_string(root.std.path_join(dir, `${name}.ascii.stderr`)) catch (e) {
            let io: baml.errors.Io => root.std.panic(`read ${name}.ascii.stderr: ${io.message}`)
        };
        let got = run_sasso_stderr(name);
        // stderr mismatch for fixture {name}
        assert.equal(got, expected);
    }
}

/// Sanity: an `@error` exits 65 and a `@warn` exits 0, matching dart-sass.
test "diagnostics_exit_codes" {
    let bin = root.tests.support.sasso_bin();
    let dir = fixtures_dir();
    // PORT: `.status.code()` → `exit_code` (`Some(n)` → `n`).
    let error_code = (
        baml.sys.exec(
            bin,
            ["--no-unicode", "error-plain.scss"],
            baml.sys.ProcessOptions {
                cwd: dir,
                env: null,
                timeout_ms: null,
                stdin: "",
                stderr: null,
            },
        ) catch (e) {
            _ => root.std.panic("run")
        }
    ).exit_code;
    // @error must exit 65
    assert.equal(error_code, 65);

    let warn_code = (
        baml.sys.exec(
            bin,
            ["--no-unicode", "warn-plain.scss"],
            baml.sys.ProcessOptions {
                cwd: dir,
                env: null,
                timeout_ms: null,
                stdin: "",
                stderr: null,
            },
        ) catch (e) {
            _ => root.std.panic("run")
        }
    ).exit_code;
    // @warn must exit 0
    assert.equal(warn_code, 0)
}

test "invalid_utf8_input_exits_65" {
    let bin = root.tests.support.sasso_bin();
    let dir = root.std.path_join(root.tests.support.temp_dir(), `sasso_invalid_utf8_${baml.sys.pid()}`);
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    };
    root.std.create_dir_all(dir) catch (e) {
        _ => root.std.panic("create temp dir")
    };
    let input = root.std.path_join(dir, "input.scss");
    // PORT: the byte string `b"foo{;\xF6\xFC"`.
    root.std.write_file_bytes(
        input,
        baml.Uint8Array.from_array([0x66, 0x6F, 0x6F, 0x7B, 0x3B, 0xF6, 0xFC]),
    ) catch (e) {
        _ => root.std.panic("write invalid utf8")
    };

    let out = baml.sys.exec(
        bin,
        [input],
        baml.sys.ProcessOptions { cwd: null, env: null, timeout_ms: null, stdin: "", stderr: null },
    ) catch (e) {
        _ => root.std.panic("run")
    };
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    };

    assert.equal(out.exit_code, 65);
    assert.equal(root.std.from_utf8_lossy(out.stderr), "Error: Invalid UTF-8.\n")
}

/// PORT: `compile(src, opts).expect_err(msg)` — the `Err` of a compile that
/// must fail; a successful compile panics with `msg`, as `Result::expect_err`
/// does.
function compile_expect_err(src: string, opts: root.Options, msg: string) -> root.error.Error {
    let css = root.compile(src, opts) catch (e) {
        let err: root.error.Error => {
            return err;
        }
    };
    root.std.panic(`${msg}: ${root.std.debug_str(css)}`)
}

/// PORT: `compile(src, opts).unwrap_err()`.
function compile_unwrap_err(src: string, opts: root.Options) -> root.error.Error {
    compile_expect_err(src, opts, "called `Result::unwrap_err()` on an `Ok` value")
}

/// PORT: a Rust `Result<String, String>` kept as a value.
type StrResult = root.std.Ok<string> | root.std.Err<string>;

/// PORT: `compile(src, &opts).map_err(|e| e.to_string())`.
function compile_map_err(src: string, opts: root.Options) -> StrResult {
    let css = root.compile(src, opts) catch (e) {
        let err: root.error.Error => {
            return root.std.Err<string> { error: err.to_string() };
        }
    };
    root.std.Ok<string> { value: css }
}

/// PORT: `Result::<String, String>::unwrap_err()`.
function unwrap_err(r: StrResult) -> string {
    match (r) {
        let err: root.std.Err<string> => err.error,
        let ok: root.std.Ok<string> => {
            root.std.panic(
                `called \`Result::unwrap_err()\` on an \`Ok\` value: ${root.std.debug_str(ok.value)}`,
            )
        },
    }
}

/// PORT: `s.matches(pat).count()` — the non-overlapping occurrences of `pat`.
function count_matches(s: string, pat: string) -> int {
    s.split(pat).length() - 1
}

/// The rendered diagnostic block for `src`, compiled under `url` so snippets
/// and frames are produced.
function err_block(src: string, url: string) -> string {
    compile_expect_err(src, root.Options.default().with_url(url), "expected a compile error")
        .to_string()
}

/// The caret line of a rendered block, trimmed — so a span that is one
/// character too long fails instead of passing a substring check.
function caret_line(block: string) -> string {
    let l = block.lines().find((l) -> {
        l.includes("^")
    })
        ?? root.std.panic(`no caret line in:\n${block}`);
    // Drop the gutter (`  │ `) and the indentation before the run.
    // PORT: `.rsplit('│').next().unwrap_or_default()` → the last `split` part.
    root.std.trim(root.std.last(l.split("│")) ?? "")
}

test "a_module_diagnostic_carets_the_construct_it_is_about" {
    // dart spans the whole rule, call or reference a diagnostic is about;
    // sasso drew a single caret (or none at all, leaving the error with no
    // snippet). Every span below was measured against dart-sass 1.103.1.
    let cases: root.std.Tuple3<string, string, string>[] = [
        // a failed load carets the whole `@use`/`@forward`
        root.std.Tuple3<string, string, string> {
            _0: "@use \"nope\";\n",
            _1: "1 │ @use \"nope\";\n",
            _2: "^^^^^^^^^^^\n",
        },
        root.std.Tuple3<string, string, string> {
            _0: "@forward \"nope\";\n",
            _1: "1 │ @forward \"nope\";\n",
            _2: "^^^^^^^^^^^^^^^\n",
        },
        // a misplaced module rule carets all of itself, trailing space and all
        root.std.Tuple3<string, string, string> {
            _0: ".a { b: c }\n@use \"nope\"   ;\n",
            _1: "2 │ @use \"nope\"   ;\n",
            _2: "^^^^^^^^^^^^^^\n",
        },
        // an undefined mixin carets the `@include`, args and all
        root.std.Tuple3<string, string, string> {
            _0: ".a { @include nope; }\n",
            _1: "1 │ .a { @include nope; }\n",
            _2: "^^^^^^^^^^^^^\n",
        },
        root.std.Tuple3<string, string, string> {
            _0: ".a { @include nope(1); }\n",
            _1: "1 │ .a { @include nope(1); }\n",
            _2: "^^^^^^^^^^^^^^^^\n",
        },
        // an error about the RULE carets all of it — `using` clause and
        // content block included (dart's `span`, not `spanWithoutContent`)
        root.std.Tuple3<string, string, string> {
            _0: ".a { @include nope using ($x) { c: $x; } }\n",
            _1: "1 │ .a { @include nope using ($x) { c: $x; } }\n",
            _2: "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n",
        },
        root.std.Tuple3<string, string, string> {
            _0: ".a { @include nope { c: d; } }\n",
            _1: "1 │ .a { @include nope { c: d; } }\n",
            _2: "^^^^^^^^^^^^^^^^^^^^^^^\n",
        },
        // a module rule's span ends at the `;`, the whitespace before it
        // included, `with` clause or not
        root.std.Tuple3<string, string, string> {
            _0: "@use \"nope\" with ($x: 1)   ;\n",
            _1: "1 │ @use \"nope\" with ($x: 1)   ;\n",
            _2: "^^^^^^^^^^^^^^^^^^^^^^^^^^^\n",
        },
        root.std.Tuple3<string, string, string> {
            _0: "@forward \"nope\" with ($x: 1)   ;\n",
            _1: "1 │ @forward \"nope\" with ($x: 1)   ;\n",
            _2: "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n",
        },
        // a built-in namespace, and a namespace that is not bound at all
        root.std.Tuple3<string, string, string> {
            _0: "@use \"sass:math\";\n.a { b: math.nope(1); }\n",
            _1: "2 │ .a { b: math.nope(1); }\n",
            _2: "^^^^^^^^^^^^\n",
        },
        root.std.Tuple3<string, string, string> {
            _0: ".a { b: nope.foo(1); }\n",
            _1: "1 │ .a { b: nope.foo(1); }\n",
            _2: "^^^^^^^^^^^\n",
        },
        // an unbound namespace on an `@include` carets the whole rule
        root.std.Tuple3<string, string, string> {
            _0: ".a { @include nope.pub; }\n",
            _1: "1 │ .a { @include nope.pub; }\n",
            _2: "^^^^^^^^^^^^^^^^^\n",
        },
        // a built-in mixin's own failure carets the invocation
        root.std.Tuple3<string, string, string> {
            _0: "@use \"sass:meta\";\n.a { @include meta.load-css(\"nope\"); }\n",
            _1: "2 │ .a { @include meta.load-css(\"nope\"); }\n",
            _2: "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n",
        },
    ];
    for (let c in cases) {
        let src = c._0;
        let line = c._1;
        let caret = c._2;
        let block = err_block(src, "in.scss");
        // {src:?}\n{block}
        assert.is_true(block.includes(line));
        // {src:?}\n{block}
        assert.equal(caret_line(block), root.std.trim(caret));
    }
    // The mixin is not named in the message — the span says which one it is.
    // {}: err_block(".a { @include nope; }\n", "in.scss")
    assert.is_true(
        err_block(".a { @include nope; }\n", "in.scss").starts_with("Error: Undefined mixin.\n"),
    );
    // A missing stylesheet names no url either.
    // {}: err_block("@import \"nope\";\n", "in.scss")
    assert.is_true(
        err_block("@import \"nope\";\n", "in.scss").includes(
            "Error: Can't find stylesheet to import.\n",
        ),
    )
}

/// dart raises "Interpolation isn't allowed in plain CSS." at the END of
/// `singleInterpolation`, once the body has parsed and the `}` is consumed: the
/// caret spans the whole `#{…}`, and a body that is invalid on its own terms
/// reports ITSELF instead. sasso rejected the interpolation at its `#` before
/// reading it, which drew a one-column caret and pre-empted those messages.
/// Every span below was measured against dart-sass 1.104.1.
test "a_plain_css_interpolation_carets_all_of_itself" {
    let block = (src: string) -> string {
        compile_expect_err(
            src,
            root.Options.default().with_url("in.css").with_syntax(root.Syntax.Css),
            "expected a compile error",
        )
            .to_string()
    };
    let cases: root.std.Tuple2<string, string>[] = [
        // an at-rule's name, whole or in part
        root.std.Tuple2<string, string> {
            _0: "@#{\"media\"} (a: 1) { .x { y: z } }\n",
            _1: "^^^^^^^^^^",
        },
        root.std.Tuple2<string, string> {
            _0: "@med#{\"ia\"} (a: 1) { .x { y: z } }\n",
            _1: "^^^^^^^",
        },
        // a media query's type, and a raw operand after `and`
        root.std.Tuple2<string, string> {
            _0: "@media #{\"screen\"} { a { b: c } }\n",
            _1: "^^^^^^^^^^^",
        },
        root.std.Tuple2<string, string> {
            _0: "@media screen and #{\"(a: 1)\"} { a { b: c } }\n",
            _1: "^^^^^^^^^^^",
        },
        // a `@supports` function's arguments
        root.std.Tuple2<string, string> {
            _0: "@supports selector(#{\"a\"}) { a { b: c } }\n",
            _1: "^^^^^^",
        },
        // a loud comment's body
        root.std.Tuple2<string, string> { _0: "/* #{1} */\n", _1: "^^^^" },
        // a custom callable's body, and a custom property's, inside a string
        root.std.Tuple2<string, string> { _0: "@function --a() { result: \"#{1}\" }\n", _1: "^^^^" },
        root.std.Tuple2<string, string> { _0: "a { --x: \"#{1}\" }\n", _1: "^^^^" },
        // a special function's verbatim arguments, and the IE `progid:` form
        root.std.Tuple2<string, string> { _0: "a { b: element(#{1}) }\n", _1: "^^^^" },
        root.std.Tuple2<string, string> { _0: "a { b: element(\"#{1}\") }\n", _1: "^^^^" },
        root.std.Tuple2<string, string> {
            _0: "a { b: progid:DXImageTransform(#{1}) }\n",
            _1: "^^^^",
        },
        // the modern `if()`'s raw operands: in a condition, in its function
        // name, and in a clause value the raw grammar reached first
        root.std.Tuple2<string, string> {
            _0: "a { b: if(media(width > #{1}px): red; else: blue) }\n",
            _1: "^^^^",
        },
        root.std.Tuple2<string, string> {
            _0: "a { b: if(me#{\"dia\"}(width > 10px): red; else: blue) }\n",
            _1: "^^^^^^^^",
        },
        root.std.Tuple2<string, string> {
            _0: "a { b: if(supports(#{\"color: red\"}): red; else: blue) }\n",
            _1: "^^^^^^^^^^^^^^^",
        },
        root.std.Tuple2<string, string> {
            _0: "a { b: if(media(width > 10px): #{1}; else: blue) }\n",
            _1: "^^^^",
        },
        // and an ordinary value, which already erred but with one caret
        root.std.Tuple2<string, string> { _0: "a { b: #{1} }\n", _1: "^^^^" },
    ];
    for (let c in cases) {
        let src = c._0;
        let caret = c._1;
        let b = block(src);
        // {src:?}\n{b}
        assert.is_true(b.starts_with("Error: Interpolation isn't allowed in plain CSS.\n"));
        // {src:?}\n{b}
        assert.equal(caret_line(b), caret);
    }
    // The body reports itself first, so neither of these is the interpolation
    // error at all.
    // {}: block("a { b: #{$x} }\n")
    assert.is_true(
        block("a { b: #{$x} }\n").starts_with(
            "Error: Sass variables aren't allowed in plain CSS.\n",
        ),
    );
    // {}: block("a { b: #{ } }\n")
    assert.is_true(block("a { b: #{ } }\n").starts_with("Error: Expected expression.\n"))
}

test "a_namespaced_member_diagnostic_points_at_the_reference" {
    // `ns.$var` carried no position at all, so its "Undefined variable." was
    // reported against line 1 column 1 — the `@use` line, not the reference.
    let dir = root.std.path_join(root.tests.support.temp_dir(), `sasso_ns_diag_${baml.sys.pid()}`);
    root.std.create_dir_all(dir) catch (e) {
        _ => root.std.panic("mkdir")
    };
    root.std.write_file(
        root.std.path_join(dir, "_lib.scss"),
        "@mixin -priv { a: b; }\n$pub: 1;\n$-pv: 1;\n@mixin -pr\\69 v { a: b; }\n",
    ) catch (e) {
        _ => root.std.panic("write")
    };
    let entry = root.std.path_join(dir, "in.scss");
    let url = entry;
    let imp = root.importer.FsImporter.new([]);
    let run = (src: string) -> string {
        root.std.write_file(entry, src);
        compile_expect_err(src, root.Options.default().with_importer(imp).with_url(url), "expected a compile error")
            .to_string()
    };
    let block = run("@use \"lib\";\n.a { b: lib.$nope; }\n");
    // {block}
    assert.is_true(block.includes("2 │ .a { b: lib.$nope; }\n"));
    // {block}
    assert.equal(caret_line(block), "^^^^^^^^^");
    // {block}
    assert.is_true(block.includes("in.scss 2:9"));
    // A namespaced call spans the call; a private member spans its name.
    let block = run("@use \"lib\";\n.a { b: lib.nope(1); }\n");
    // {block}
    assert.equal(caret_line(block), "^^^^^^^^^^^");
    let block = run("@use \"lib\";\n.a { @include lib.-priv; }\n");
    // {block}
    assert.equal(caret_line(block), "^^^^^");
    // {block}
    assert.is_true(block.includes("in.scss 2:19"));
    // The caret covers the member AS WRITTEN, so an escape inside it counts
    // its source bytes rather than the decoded ones.
    let block = run("@use \"lib\";\n.a { @include lib.-pr\\69 v; }\n");
    // {block}
    assert.equal(caret_line(block), "^^^^^^^^");
    // A private VARIABLE reference carets the whole `ns.$name`.
    let block = run("@use \"lib\";\n.a { b: lib.$-pv; }\n");
    // {block}
    assert.equal(caret_line(block), "^^^^^^^^");
    // {block}
    assert.is_true(block.includes("in.scss 2:9"));
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    };
}

test "a_span_that_crosses_lines_ends_where_dart_ends_it" {
    // A CRLF terminator is two bytes; counting it as one walked the end of a
    // multi-line span a line too far. dart ends this one on the `}` line.
    let block = err_block(".a {\r\n  @include nope {\r\n    c: d;\r\n  }\r\n}\r\n", "in.scss");
    // {block}
    assert.is_true(block.includes("4 │ └   }\n"));
    // {block}
    assert.is_true(!block.includes("5 │"));
    // The same file with LF terminators ends in the same place.
    let lf = err_block(".a {\n  @include nope {\n    c: d;\n  }\n}\n", "in.scss");
    assert.equal(block.replace_all("\r", ""), lf)
}

test "an_indented_include_carets_its_own_line" {
    // The braces around an indented child block are written by the front end,
    // so the text they enclose is not a source span: the caret stays on the
    // call. (dart spans the children; that needs a reconstruction-to-source
    // mapping the front end does not have.)
    let block = compile_expect_err(
        ".a\n  @include nope\n    c: d\n",
        root.Options.default().with_syntax(root.Syntax.Sass).with_url("in.sass"),
        "expected a compile error",
    )
        .to_string();
    // {block}
    assert.equal(caret_line(block), "^^^^^^^^^^^^^");
    // {block}
    assert.is_true(block.includes("in.sass 2:3"))
}

test "an_escaped_member_name_is_not_private" {
    // dart reads privacy from the LITERAL spelling: `ns.-priv` is private,
    // `ns.\2d priv` is an ordinary member it then fails to find. A private
    // member is not in a module's public view, so the failure is "not found",
    // not "private".
    let dir = root.std.path_join(root.tests.support.temp_dir(), `sasso_esc_priv_${baml.sys.pid()}`);
    root.std.create_dir_all(dir) catch (e) {
        _ => root.std.panic("mkdir")
    };
    root.std.write_file(
        root.std.path_join(dir, "_lib.scss"),
        "@mixin -priv { a: b; }\n@function -pf() { @return 1; }\n$-pv: 1;\n",
    ) catch (e) {
        _ => root.std.panic("write")
    };
    let entry = root.std.path_join(dir, "in.scss");
    let url = entry;
    let imp = root.importer.FsImporter.new([]);
    let run = (src: string) -> string {
        root.std.write_file(entry, src);
        compile_expect_err(src, root.Options.default().with_importer(imp).with_url(url), "expected a compile error")
            .to_string()
    };
    let block = run("@use \"lib\";\n.a { @include lib.\\2d priv; }\n");
    // {block}
    assert.is_true(block.starts_with("Error: Undefined mixin.\n"));
    // {block}
    assert.equal(caret_line(block), "^^^^^^^^^^^^^^^^^^^^^");
    let block = run("@use \"lib\";\n.a { b: lib.$\\2d pv; }\n");
    // {block}
    assert.is_true(block.starts_with("Error: Undefined variable.\n"));
    // {block}
    assert.equal(caret_line(block), "^^^^^^^^^^^");
    let block = run("@use \"lib\";\n.a { b: lib.\\2d pf(); }\n");
    // {block}
    assert.is_true(block.starts_with("Error: Undefined function.\n"));
    // A LITERAL private member keeps dart's privacy error.
    let block = run("@use \"lib\";\n.a { @include lib.-priv; }\n");
    // {block}
    assert.is_true(
        block.starts_with("Error: Private members can't be accessed from outside their modules.\n"),
    );
    // The by-name API reports it missing, with the name it was asked for.
    let block = run(
        "@use \"sass:meta\";\n@use \"lib\";\n.a { b: meta.call(meta.get-function(\"-pf\", $module: \"lib\")); }\n",
    );
    // {block}
    assert.is_true(block.starts_with("Error: Function not found: \"-pf\"\n"));
    // {block}
    assert.equal(caret_line(block), "^".repeat(40));
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    };
}

test "a_missing_argument_points_at_the_invocation" {
    // dart reports a missing argument against the CALL — its primary span —
    // whichever path made the call, and reads the snippet from the CALLER's
    // file even though the callee's file is the current one by then.
    let dir = root.std.path_join(root.tests.support.temp_dir(), `sasso_missing_arg_${baml.sys.pid()}`);
    root.std.create_dir_all(dir) catch (e) {
        _ => root.std.panic("mkdir")
    };
    root.std.write_file(
        root.std.path_join(dir, "_lib.scss"),
        "@function f($x) { @return $x; }\n@mixin m($x) { a: $x; }\n",
    ) catch (e) {
        _ => root.std.panic("write")
    };
    let entry = root.std.path_join(dir, "in.scss");
    let url = entry;
    let imp = root.importer.FsImporter.new([]);
    let run = (src: string) -> string {
        root.std.write_file(entry, src);
        compile_expect_err(src, root.Options.default().with_importer(imp).with_url(url), "expected a compile error")
            .to_string()
    };
    // A function in the same file: the invocation IS the primary span, and
    // dart's second span points back at the declaration.
    let block = run("@function f($x) { @return $x; }\n.a { b: f(); }\n");
    // {block}
    assert.is_true(block.starts_with("Error: Missing argument $x.\n"));
    // {block}
    assert.is_true(block.includes("2 │ .a { b: f(); }\n"));
    // {block}
    assert.equal(caret_line(block), "^^^ invocation");
    // {block}
    assert.is_true(block.includes("1 │ @function f($x) { @return $x; }\n"));
    // {block}
    assert.is_true(block.includes("━━━━━ declaration"));
    // A function in ANOTHER file: the snippet is the caller's line, not the
    // definition's.
    let block = run("@use \"lib\";\n.a { b: lib.f(); }\n");
    // {block}
    assert.is_true(block.includes("2 │ .a { b: lib.f(); }\n"));
    // {block}
    assert.equal(caret_line(block), "^^^^^^^ invocation");
    // {block}
    assert.is_true(block.includes("in.scss 2:9  f()"));
    // The same for a mixin.
    let block = run("@use \"lib\";\n.a { @include lib.m; }\n");
    // {block}
    assert.is_true(block.includes("2 │ .a { @include lib.m; }\n"));
    // {block}
    assert.equal(caret_line(block), "^^^^^^^^^^^^^^ invocation");
    // And through `meta.call`, which invokes a reference.
    let block = run(
        "@use \"sass:meta\";\n@function f($x) { @return $x; }\n.a { b: meta.call(meta.get-function(\"f\")); }\n",
    );
    // {block}
    assert.equal(caret_line(block), "^".repeat(33) + " invocation");
    // A built-in re-exported through `@forward` reports like a direct one.
    // It keeps the single-span block: dart points back at a declaration in
    // `sass:math`, which has no source text here to point AT.
    root.std.write_file(root.std.path_join(dir, "_fwd.scss"), "@forward \"sass:math\";\n") catch (e) {
        _ => root.std.panic("write")
    };
    let block = run("@use \"fwd\";\n.a { b: fwd.div(1); }\n");
    // {block}
    assert.equal(caret_line(block), "^^^^^^^^^^");
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    };
}

test "a_multi_line_span_uses_the_gutter_at_a_line_edge" {
    // dart (source_span) writes the arm glyph in the GUTTER when the span
    // begins at its line's first non-whitespace character, and likewise when it
    // ends at its line's last; it draws an arrow row only for an end that
    // starts or stops mid-line. The two ends are decided separately.
    let both = err_block(".a {\n  @include nope {\n    c: d;\n  }\n}\n", "in.scss");
    // {both}
    assert.is_true(
        both.includes("2 │ ┌   @include nope {\n3 │ │     c: d;\n4 │ └   }\n"),
    );
    // {both}
    assert.is_true(!both.includes("^"));
    // Starts mid-line, ends at the line's last character: an opening arrow row
    // and a closing gutter glyph.
    let open = err_block(".a { @include nope {\n    c: d;\n  }\n}\n", "in.scss");
    // {open}
    assert.is_true(open.includes("│ ┌──────^\n"));
    // {open}
    assert.is_true(open.includes("3 │ └   }\n"));
    // Starts at the line's first character, ends mid-line: the mirror image.
    let close = err_block(".a {\n  @include nope {\n    c: d;\n  } x: y;\n}\n", "in.scss");
    // {close}
    assert.is_true(close.includes("2 │ ┌   @include nope {\n"));
    // {close}
    assert.is_true(close.includes("│ └───^\n"))
}

test "an_error_at_the_end_of_a_file_points_at_the_last_line_with_content" {
    // dart's scanner never advances into a file's trailing whitespace, so an
    // "expected …" at the end of one points at the end of the last line that
    // says something — trailing spaces on that line included.
    // PORT: the tuple array is bound to a typed local first (an inline
    // `Tuple3<string, int, int>` literal in the `for` header does not resolve).
    let cases: root.std.Tuple3<string, int, int>[] = [
        root.std.Tuple3<string, int, int> { _0: ".a { b: c\n", _1: 1, _2: 10 },
        root.std.Tuple3<string, int, int> { _0: ".a {\n", _1: 1, _2: 5 },
        root.std.Tuple3<string, int, int> { _0: "@media screen {\n  .a { b: c }\n", _1: 2, _2: 14 },
        root.std.Tuple3<string, int, int> { _0: ".a { b: c; \n\n\n", _1: 1, _2: 12 },
    ];
    for (let c in cases) {
        let src = c._0;
        let line = c._1;
        let caret_col = c._2;
        let block = err_block(src, "in.scss");
        // {src:?}\n{block}
        assert.is_true(block.starts_with("Error: expected \"}\".\n"));
        // {src:?}\n{block}
        assert.is_true(block.includes(`in.scss ${line}:${caret_col}`));
        // The snippet shows that line, not the blank one after it.
        // {src:?}\n{block}
        assert.is_true(block.includes(`${line} │ `));
    }
}

test "a_value_that_cannot_start_reports_what_was_expected" {
    // dart names what it WANTED — an expression — whatever it found there: a
    // character that cannot start one, or the end of the file.
    for (
        let src in [
            ".a { b: ; }\n",
            ".a { b: 1 + ; }\n",
            ".a { b: ) }\n",
            "@if  { a: b; }\n",
            ".a { b: \n",
            ".a { b: 1 +\n",
        ]
    ) {
        let block = err_block(src, "in.scss");
        // {src:?}\n{block}
        assert.is_true(block.starts_with("Error: Expected expression.\n"));
    }
}

/// Every `formatted` warning a compile of `src` produces.
function warnings(src: string, url: string) -> string[] {
    // PORT: the `Rc<RefCell<Vec<String>>>` the handler shares is one array
    // (arrays are reference types); `sink` aliases `seen`.
    let seen: string[] = [];
    let sink = seen;
    let opts = root.Options.default().with_url(url).with_warn_handler((ev: root.WarnEvent) -> void {
        sink.push(ev.formatted);
    });
    let _ = root.compile(src, opts) catch (e) {
        let _e: root.error.Error => ""
    };
    let out = root.std.clone_vec(seen);
    out
}

test "a_global_builtin_with_a_module_form_is_deprecated" {
    // dart names the member to use and carets the whole call. The mapping is
    // not mechanical — every entry below was measured against dart-sass
    // 1.103.1 — so the table is checked, not just the machinery.
    for (
        let c in [
            root.std.Tuple3<string, string, string> {
                _0: ".a { b: map-get((x: 1), x); }\n",
                _1: "map.get",
                _2: "^^^^^^^^^^^^^^^^^^",
            },
            root.std.Tuple3<string, string, string> {
                _0: ".a { b: nth(1 2 3, 1); }\n",
                _1: "list.nth",
                _2: "^^^^^^^^^^^^^",
            },
            root.std.Tuple3<string, string, string> {
                _0: ".a { b: percentage(0.5); }\n",
                _1: "math.percentage",
                _2: "^^^^^^^^^^^^^^^",
            },
            root.std.Tuple3<string, string, string> {
                _0: ".a { b: lighten(#fff, 10%); }\n",
                _1: "color.adjust",
                _2: "^^^^^^^^^^^^^^^^^^",
            },
            root.std.Tuple3<string, string, string> {
                _0: ".a { b: unitless(1); }\n",
                _1: "math.is-unitless",
                _2: "^^^^^^^^^^^",
            },
            root.std.Tuple3<string, string, string> {
                _0: ".a { b: comparable(1px, 2px); }\n",
                _1: "math.compatible",
                _2: "^^^^^^^^^^^^^^^^^^^^",
            },
            root.std.Tuple3<string, string, string> {
                _0: ".a { b: list-separator(1 2); }\n",
                _1: "list.separator",
                _2: "^^^^^^^^^^^^^^^^^^^",
            },
            root.std.Tuple3<string, string, string> {
                _0: ".a { b: str-length(\"abc\"); }\n",
                _1: "string.length",
                _2: "^^^^^^^^^^^^^^^^^",
            },
            root.std.Tuple3<string, string, string> {
                _0: ".a { b: type-of(1); }\n",
                _1: "meta.type-of",
                _2: "^^^^^^^^^^",
            },
            root.std.Tuple3<string, string, string> {
                _0: ".a { b: selector-parse(\"a\"); }\n",
                _1: "selector.parse",
                _2: "^^^^^^^^^^^^^^^^^^",
            },
        ]
    ) {
        let src = c._0;
        let replacement = c._1;
        let caret = c._2;
        // A legacy colour function carries its own `[color-functions]`
        // deprecation as well; this is about the global one.
        let w: string[] = warnings(src, "in.scss").filter((x) -> {
            x.includes("[global-builtin]")
        });
        // {src:?} -> {w:?}
        assert.equal(w.length(), 1);
        // {src:?}\n{}: w[0]
        assert.is_true(
            w[0].starts_with(
                `DEPRECATION WARNING [global-builtin]: Global built-in functions are deprecated and will be removed in Dart Sass 3.0.0.\nUse ${replacement} instead.\n\nMore info and automated migrator: https://sass-lang.com/d/import\n`,
            ),
        );
        // {src:?}\n{}: w[0]
        assert.is_true(w[0].includes(caret));
    }
    // A global dart KEEPS is not deprecated: a CSS function it shares a name
    // with, or one with no module form.
    for (
        let src in [
            ".a { b: abs(-1); }\n",
            ".a { b: round(1.5); }\n",
            ".a { b: min(1, 2); }\n",
            ".a { b: rgba(0, 0, 0, 0.5); }\n",
            ".a { b: ie-hex-str(#fff); }\n",
        ]
    ) {
        // {src:?}
        assert.is_true(warnings(src, "in.scss").length() == 0);
    }
    // The module form itself is never deprecated.
    assert.is_true(
        warnings("@use \"sass:math\";\n.a { b: math.percentage(0.5); }\n", "in.scss").length() == 0,
    );
    // The `sass:meta` predicates resolve against evaluator state and return
    // before the generic built-in dispatch: they are deprecated too.
    for (
        let c in [
            root.std.Tuple2<string, string> {
                _0: "$x: 1;\n.a { b: variable-exists(\"x\"); }\n",
                _1: "meta.variable-exists",
            },
            root.std.Tuple2<string, string> {
                _0: "$x: 1;\n.a { b: global-variable-exists(\"x\"); }\n",
                _1: "meta.global-variable-exists",
            },
            root.std.Tuple2<string, string> {
                _0: "@mixin m {}\n.a { b: mixin-exists(\"m\"); }\n",
                _1: "meta.mixin-exists",
            },
            root.std.Tuple2<string, string> {
                _0: ".a { b: function-exists(\"percentage\"); }\n",
                _1: "meta.function-exists",
            },
        ]
    ) {
        let src = c._0;
        let replacement = c._1;
        let w = warnings(src, "in.scss");
        // {src:?}\n{w:?}
        assert.is_true(
            w.some((x) -> {
                x.includes(`Use ${replacement} instead.`)
            }),
        );
    }
    // The name is matched EXACTLY: dart resolves these case-sensitively, so an
    // upper-case spelling is plain CSS to it and carries no warning.
    for (
        let src in [
            ".a { b: MAP-GET((x: 1), x); }\n",
            ".a { b: Lighten(#fff, 10%); }\n",
            ".a { b: PERCENTAGE(0.5); }\n",
        ]
    ) {
        // {src:?}
        assert.is_true(warnings(src, "in.scss").length() == 0);
    }
    // The indented syntax reports it too, at its own position.
    let seen: string[] = [];
    let sink = seen;
    let opts = root.Options.default().with_syntax(root.Syntax.Sass).with_url("in.sass").with_warn_handler((
        ev: root.WarnEvent,
    ) -> void {
        sink.push(ev.formatted);
    });
    let _ = root.compile(".a\n  b: nth(1 2, 1)\n", opts) catch (e) {
        let _e: root.error.Error => ""
    };
    let w = root.std.clone_vec(seen);
    // {w:?}
    assert.equal(w.length(), 1);
    // {}: w[0]
    assert.is_true(w[0].includes("in.sass 2:6"))
}

test "a_deprecated_function_reached_indirectly_still_warns" {
    // dart reports the global built-in a `call()` reaches — by name or through
    // a reference — against the INVOCATION, on top of the warnings for `call`
    // and `get-function` themselves. Two `[global-builtin]` warnings can
    // therefore share one span, saying different things.
    let w = warnings(".a { b: call(get-function(\"percentage\"), 0.5); }\n", "in.scss");
    // {w:?}
    assert.equal(w.length(), 3);
    // {}: w[0]
    assert.is_true(w[0].includes("Use meta.get-function instead."));
    // {}: w[1]
    assert.is_true(w[1].includes("Use meta.call instead."));
    // {}: w[2]
    assert.is_true(w[2].includes("Use math.percentage instead."));
    // {w:?}
    assert.is_true(w[1].includes("in.scss 1:9") && w[2].includes("in.scss 1:9"));
    // The string form adds `[call-string]`, with the name it was given.
    let w = warnings("@function foo() { @return 1; }\n.a { b: call(\"foo\"); }\n", "in.scss");
    // {w:?}
    assert.equal(w.length(), 2);
    // {}: w[0]
    assert.is_true(w[0].includes("Use meta.call instead."));
    // {}: w[1]
    assert.is_true(
        w[1].starts_with(
            "DEPRECATION WARNING [call-string]: Passing a string to call() is deprecated and will be illegal in Dart Sass 2.0.0.\n\nRecommendation: call(get-function(\"foo\"))\n",
        ),
    );
    // `feature-exists` is deprecated whichever way it is spelled.
    let w = warnings(".a { b: feature-exists(\"at-error\"); }\n", "in.scss");
    // {w:?}
    assert.equal(w.length(), 2);
    // {}: w[1]
    assert.is_true(
        w[1].starts_with(
            "DEPRECATION WARNING [feature-exists]: The feature-exists() function is deprecated.\n\nMore info: https://sass-lang.com/d/feature-exists\n",
        ),
    );
    let w = warnings("@use \"sass:meta\";\n.a { b: meta.feature-exists(\"at-error\"); }\n", "in.scss");
    // {w:?}
    assert.equal(w.length(), 1);
    // {}: w[0]
    assert.is_true(w[0].includes("[feature-exists]"))
}

test "a_deprecation_follows_the_call_that_is_actually_made" {
    // Whether a call is deprecated depends on what it RESOLVES to, not on how
    // it is spelled. Every expectation here was measured against dart-sass
    // 1.103.1.
    let dir = root.std.path_join(root.tests.support.temp_dir(), `sasso_dep_resolve_${baml.sys.pid()}`);
    root.std.create_dir_all(dir) catch (e) {
        _ => root.std.panic("mkdir")
    };
    root.std.write_file(root.std.path_join(dir, "_fwdmeta.scss"), "@forward \"sass:meta\";\n") catch (e) {
        _ => root.std.panic("write")
    };
    let entry = root.std.path_join(dir, "in.scss");
    let url = entry;
    let imp = root.importer.FsImporter.new([]);
    let run = (src: string) -> string[] {
        root.std.write_file(entry, src);
        let seen: string[] = [];
        let sink = seen;
        let opts = root.Options.default().with_importer(imp).with_url(url).with_warn_handler((
            ev: root.WarnEvent,
        ) -> void {
            sink.push(ev.formatted);
        });
        let _ = root.compile(src, opts) catch (e) {
            let _e: root.error.Error => ""
        };
        let out = root.std.clone_vec(seen);
        out
    };
    // A built-in module bound to an alias is still that module.
    let w = run("@use \"sass:meta\" as m;\n.a { b: m.feature-exists(\"at-error\"); }\n");
    // {w:?}
    assert.equal(w.length(), 1);
    // {}: w[0]
    assert.is_true(w[0].includes("[feature-exists]"));
    // So is one reached through a `@forward`.
    let w = run("@use \"fwdmeta\" as m;\n.a { b: m.feature-exists(\"at-error\"); }\n");
    // {w:?}
    assert.equal(w.length(), 1);
    // {}: w[0]
    assert.is_true(w[0].includes("[feature-exists]"));
    // A member exposed by `@use … as *` is that module's, not a global: the
    // function's own deprecation fires, the global-built-in one does not.
    let w = run("@use \"sass:meta\" as *;\n.a { b: feature-exists(\"at-error\"); }\n");
    // {w:?}
    assert.equal(w.length(), 1);
    // {}: w[0]
    assert.is_true(w[0].includes("[feature-exists]"));
    // A user `@function` wins over the global, so nothing is deprecated.
    assert.is_true(
        run("@function type-of($x) { @return 1; }\n.a { b: type-of(2); }\n").length() == 0,
    );
    // A deprecated call INSIDE a deprecated one is reported first, as dart
    // reports it.
    let w = run("@use \"sass:meta\";\n.a { b: meta.feature-exists(inspect(\"at-error\")); }\n");
    // {w:?}
    assert.equal(w.length(), 2);
    // {}: w[0]
    assert.is_true(w[0].includes("Use meta.inspect instead."));
    // {}: w[1]
    assert.is_true(w[1].includes("[feature-exists]"));
    // A plain-CSS reference invokes no Sass built-in.
    assert.is_true(
        run(
            "@use \"sass:meta\";\n.a { b: meta.call(meta.get-function(\"percentage\", $css: true), 1); }\n",
        )
            .length()
            == 0,
    );
    // `call()`'s recommendation quotes the name as Sass would write it.
    let w = run("@function a\\\"b() { @return 1; }\n.a { b: call(\"a\\\\\\\"b\"); }\n");
    // {w:?}
    assert.is_true(
        w.some((x) -> {
            x.includes("Recommendation: call(get-function('a\\\\\"b'))")
        }),
    );
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    };
}

test "what_a_call_resolves_to_decides_what_is_deprecated" {
    // The underscore spelling reaches the same built-in, so it carries the same
    // deprecation; a reference taken from a module is not the global. Every
    // expectation measured against dart-sass 1.103.1.
    let w = warnings("a { b: map_get((x: 1), x); }\n", "in.scss");
    // {w:?}
    assert.equal(w.length(), 1);
    // {}: w[0]
    assert.is_true(w[0].includes("Use map.get instead."));
    // The caret covers the call as written, underscore and all.
    // {}: w[0]
    assert.is_true(w[0].includes("^^^^^^^^^^^^^^^^^^"));
    let w = warnings("@use \"sass:meta\";\na { b: meta.feature_exists(\"at-error\"); }\n", "in.scss");
    // {w:?}
    assert.equal(w.length(), 1);
    // {}: w[0]
    assert.is_true(w[0].includes("[feature-exists]"));
    let w = warnings("@use \"sass:meta\" as *;\na { b: feature_exists(\"at-error\"); }\n", "in.scss");
    // {w:?}
    assert.equal(w.length(), 1);
    // {}: w[0]
    assert.is_true(w[0].includes("[feature-exists]"));
    // A reference taken THROUGH a module is that module's member: the global
    // spelling is what is deprecated, and this is not it.
    assert.is_true(
        warnings(
            "@use \"sass:meta\"; @use \"sass:math\";\na { b: meta.call(meta.get-function(\"percentage\", $module: \"math\"), 1); }\n",
            "in.scss",
        )
            .length()
            == 0,
    );
    // The function's OWN deprecation still fires for a module-derived one.
    let w = warnings(
        "@use \"sass:meta\";\na { b: meta.call(meta.get-function(\"feature-exists\", $module: \"meta\"), \"at-error\"); }\n",
        "in.scss",
    );
    // {w:?}
    assert.equal(w.length(), 1);
    // {}: w[0]
    assert.is_true(w[0].includes("[feature-exists]"));
    // Taken globally, it is deprecated for being global.
    let w = warnings("@use \"sass:meta\";\na { b: meta.call(meta.get-function(\"percentage\"), 1); }\n", "in.scss");
    // {w:?}
    assert.equal(w.length(), 1);
    // {}: w[0]
    assert.is_true(w[0].includes("Use math.percentage instead."))
}

test "a_host_function_does_not_exempt_a_global_builtin" {
    // dart's `functions` do not shadow a built-in global at all: the built-in
    // runs and still warns (measured against 1.103.1's JS API with a
    // `type-of($v)` host function, which never runs).
    // PORT: `Ok(Vec::new())` → an empty `uint8array`.
    let cb: root.host_fn.HostFunction = (_args: uint8array) -> uint8array {
        baml.Uint8Array.zeroes(0)
    };
    let seen: string[] = [];
    let sink = seen;
    let opts = root.Options.default().with_url("in.scss").with_function("type-of($v)", cb).with_warn_handler((
        ev: root.WarnEvent,
    ) -> void {
        sink.push(ev.formatted);
    });
    let _ = root.compile(".a { b: type-of(1); }\n", opts) catch (e) {
        let _e: root.error.Error => ""
    };
    let w = root.std.clone_vec(seen);
    // {w:?}
    assert.equal(w.length(), 1);
    // {}: w[0]
    assert.is_true(w[0].includes("Use meta.type-of instead."))
}

test "a_forwarded_builtin_is_reachable_by_call_and_by_reference" {
    // A `@forward "sass:…"` re-exports a built-in module under the forward's
    // own name, and `_`/`-` are interchangeable in BOTH the member and the
    // prefix. Every expectation measured against dart-sass 1.103.1.
    let dir = root.std.path_join(root.tests.support.temp_dir(), `sasso_fwd_builtin_${baml.sys.pid()}`);
    root.std.create_dir_all(dir) catch (e) {
        _ => root.std.panic("mkdir")
    };
    root.std.write_file(root.std.path_join(dir, "_plain.scss"), "@forward \"sass:map\";\n") catch (e) {
        _ => root.std.panic("write")
    };
    root.std.write_file(root.std.path_join(dir, "_pref.scss"), "@forward \"sass:map\" as p-*;\n") catch (e) {
        _ => root.std.panic("write")
    };
    root.std.write_file(root.std.path_join(dir, "_upref.scss"), "@forward \"sass:map\" as p_*;\n") catch (e) {
        _ => root.std.panic("write")
    };
    root.std.write_file(
        root.std.path_join(dir, "_shown.scss"),
        "@forward \"sass:string\" show to_upper_case;\n",
    ) catch (e) {
        _ => root.std.panic("write")
    };
    let entry = root.std.path_join(dir, "in.scss");
    let url = entry;
    let imp = root.importer.FsImporter.new([]);
    let run = (src: string) -> StrResult {
        root.std.write_file(entry, src);
        let opts = root.Options.default().with_importer(imp).with_url(url);
        compile_map_err(src, opts)
    };
    // The prefix and the member are both read canonically.
    for (
        let src in [
            "@use \"pref\" as p; a { b: p.p-get((x: 1), x); }",
            "@use \"pref\" as p; a { b: p.p_get((x: 1), x); }",
            "@use \"upref\" as p; a { b: p.p-get((x: 1), x); }",
            "@use \"upref\" as p; a { b: p.p_get((x: 1), x); }",
        ]
    ) {
        // {src}
        assert.equal(run(src), root.std.Ok<string> { value: "a {\n  b: 1;\n}" });
    }
    // A `show` list written with underscores accepts either spelling.
    for (
        let src in [
            "@use \"shown\" as s; a { b: s.to-upper-case(\"a\"); }",
            "@use \"shown\" as s; a { b: s.to_upper_case(\"a\"); }",
        ]
    ) {
        // {src}
        assert.equal(run(src), root.std.Ok<string> { value: "a {\n  b: \"A\";\n}" });
    }
    // `get-function($module:)` reaches a forwarded built-in, under the name the
    // forward gives it, and inspects as the MEMBER it is.
    assert.equal(
        run(
            "@use \"plain\" as f; @use \"sass:meta\";\na { b: meta.inspect(meta.get-function(\"get\", $module: \"f\")); }",
        ),
        root.std.Ok<string> { value: "a {\n  b: get-function(\"get\");\n}" },
    );
    assert.equal(
        run(
            "@use \"plain\" as f; @use \"sass:meta\";\na { b: meta.call(meta.get-function(\"get\", $module: \"f\"), (x: 1), x); }",
        ),
        root.std.Ok<string> { value: "a {\n  b: 1;\n}" },
    );
    assert.equal(
        run(
            "@use \"pref\" as p; @use \"sass:meta\";\na { b: meta.inspect(meta.get-function(\"p-get\", $module: \"p\")); }",
        ),
        root.std.Ok<string> { value: "a {\n  b: get-function(\"get\");\n}" },
    );
    // The global alias is not a member of the module, prefixed or not.
    assert.is_true(
        unwrap_err(
            run(
                "@use \"plain\" as f; @use \"sass:meta\";\na { b: meta.get-function(\"map-get\", $module: \"f\"); }",
            ),
        )
            .includes("Function not found: \"map-get\""),
    );
    assert.is_true(
        unwrap_err(
            run(
                "@use \"pref\" as p; @use \"sass:meta\";\na { b: meta.get-function(\"get\", $module: \"p\"); }",
            ),
        )
            .includes("Function not found: \"get\""),
    );
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    };
}

test "a_forward_carries_a_builtin_through_every_rule_it_passes" {
    // A `@forward "sass:…"` survives being forwarded again, its `show`/`hide`
    // match the name AS THAT RULE EXPORTS IT, and the members it exposes answer
    // to calls, references and existence queries alike. Every expectation
    // measured against dart-sass 1.103.1.
    let dir = root.std.path_join(root.tests.support.temp_dir(), `sasso_fwd_chain_${baml.sys.pid()}`);
    root.std.create_dir_all(dir) catch (e) {
        _ => root.std.panic("mkdir")
    };
    root.std.write_file(root.std.path_join(dir, "_inner.scss"), "@forward \"sass:map\";\n") catch (e) {
        _ => root.std.panic("write")
    };
    root.std.write_file(root.std.path_join(dir, "_outer.scss"), "@forward \"inner\";\n") catch (e) {
        _ => root.std.panic("write")
    };
    root.std.write_file(root.std.path_join(dir, "_outerq.scss"), "@forward \"inner\" as q-*;\n") catch (e) {
        _ => root.std.panic("write")
    };
    root.std.write_file(root.std.path_join(dir, "_fmeta.scss"), "@forward \"sass:meta\";\n") catch (e) {
        _ => root.std.panic("write")
    };
    root.std.write_file(
        root.std.path_join(dir, "_hidepre.scss"),
        "@forward \"sass:map\" as p-* hide p-get;\n",
    ) catch (e) {
        _ => root.std.panic("write")
    };
    root.std.write_file(
        root.std.path_join(dir, "_hidebare.scss"),
        "@forward \"sass:map\" as p-* hide get;\n",
    ) catch (e) {
        _ => root.std.panic("write")
    };
    let entry = root.std.path_join(dir, "in.scss");
    let url = entry;
    let imp = root.importer.FsImporter.new([]);
    let run = (src: string) -> StrResult {
        root.std.write_file(entry, src);
        let opts = root.Options.default().with_importer(imp).with_url(url);
        compile_map_err(src, opts)
    };
    // A built-in forwarded through another module is still public, prefix and
    // all, by call and by reference.
    assert.equal(
        run("@use \"outer\" as o; a { b: o.get((x: 1), x); }"),
        root.std.Ok<string> { value: "a {\n  b: 1;\n}" },
    );
    assert.equal(
        run("@use \"outerq\" as o; a { b: o.q-get((x: 1), x); }"),
        root.std.Ok<string> { value: "a {\n  b: 1;\n}" },
    );
    assert.equal(
        run(
            "@use \"outer\" as o; @use \"sass:meta\";\na { b: meta.inspect(meta.get-function(\"get\", $module: \"o\")); }",
        ),
        root.std.Ok<string> { value: "a {\n  b: get-function(\"get\");\n}" },
    );
    // `show`/`hide` name the member as the rule that wrote them exports it.
    assert.is_true(
        unwrap_err(run("@use \"hidepre\" as p; a { b: p.p-get((x: 1), x); }")).includes(
            "Undefined function.",
        ),
    );
    assert.equal(
        run("@use \"hidebare\" as p; a { b: p.p-get((x: 1), x); }"),
        root.std.Ok<string> { value: "a {\n  b: 1;\n}" },
    );
    // A forwarded `sass:meta` member that resolves against the evaluator still
    // reaches the evaluator.
    assert.equal(
        run("$x: 1;\n@use \"fmeta\" as f; a { b: f.variable-exists(\"x\"); }"),
        root.std.Ok<string> { value: "a {\n  b: true;\n}" },
    );
    assert.equal(
        run("@use \"fmeta\" as f; a { b: f.call(f.get-function(\"rgb\"), 1, 2, 3); }"),
        root.std.Ok<string> { value: "a {\n  b: rgb(1, 2, 3);\n}" },
    );
    // Existence queries see exactly what the call and reference paths see.
    assert.equal(
        run(
            "@use \"inner\" as f; @use \"sass:meta\";\na { b: meta.function-exists(\"get\", $module: \"f\"); }",
        ),
        root.std.Ok<string> { value: "a {\n  b: true;\n}" },
    );
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    };
}

test "a_forwarded_builtin_brings_its_whole_public_face" {
    // A `@forward "sass:…"` re-exports variables and mixins, not only
    // functions; an inner `show`/`hide` names the member in ITS OWN namespace
    // whatever an outer rule renames it to; and a starred user module exposes
    // what it forwards. Measured against dart-sass 1.103.1.
    let dir = root.std.path_join(root.tests.support.temp_dir(), `sasso_fwd_face_${baml.sys.pid()}`);
    root.std.create_dir_all(dir) catch (e) {
        _ => root.std.panic("mkdir")
    };
    root.std.write_file(root.std.path_join(dir, "_fmath.scss"), "@forward \"sass:math\";\n") catch (e) {
        _ => root.std.panic("write")
    };
    root.std.write_file(root.std.path_join(dir, "_fmap.scss"), "@forward \"sass:map\";\n") catch (e) {
        _ => root.std.panic("write")
    };
    root.std.write_file(
        root.std.path_join(dir, "_ishow.scss"),
        "@forward \"sass:map\" as p-* show p-get;\n",
    ) catch (e) {
        _ => root.std.panic("write")
    };
    root.std.write_file(
        root.std.path_join(dir, "_ihide.scss"),
        "@forward \"sass:map\" as p-* hide p-get;\n",
    ) catch (e) {
        _ => root.std.panic("write")
    };
    root.std.write_file(root.std.path_join(dir, "_oshow.scss"), "@forward \"ishow\" as q-*;\n") catch (e) {
        _ => root.std.panic("write")
    };
    root.std.write_file(root.std.path_join(dir, "_ohide.scss"), "@forward \"ihide\" as q-*;\n") catch (e) {
        _ => root.std.panic("write")
    };
    root.std.write_file(
        root.std.path_join(dir, "_novar.scss"),
        "@forward \"sass:math\" hide $pi;\n",
    ) catch (e) {
        _ => root.std.panic("write")
    };
    root.std.write_file(
        root.std.path_join(dir, "_onlyvar.scss"),
        "@forward \"sass:math\" show $pi;\n",
    ) catch (e) {
        _ => root.std.panic("write")
    };
    let entry = root.std.path_join(dir, "in.scss");
    let url = entry;
    let imp = root.importer.FsImporter.new([]);
    let run = (src: string) -> StrResult {
        root.std.write_file(entry, src);
        let opts = root.Options.default().with_importer(imp).with_url(url);
        compile_map_err(src, opts)
    };
    // Variables travel with the forward, namespaced and starred alike, and a
    // `hide $pi` stops them.
    assert.equal(
        run("@use \"fmath\" as f; a { b: f.$pi; }"),
        root.std.Ok<string> { value: "a {\n  b: 3.1415926536;\n}" },
    );
    assert.equal(
        run("@use \"fmath\" as *; a { b: $pi; }"),
        root.std.Ok<string> { value: "a {\n  b: 3.1415926536;\n}" },
    );
    assert.is_true(
        unwrap_err(run("@use \"novar\" as f; a { b: f.$pi; }")).includes("Undefined variable."),
    );
    assert.equal(
        run("@use \"novar\" as f; a { b: f.floor(1.5); }"),
        root.std.Ok<string> { value: "a {\n  b: 1;\n}" },
    );
    // A `show` that names only variables hides every function.
    assert.equal(
        run("@use \"onlyvar\" as f; a { b: f.$pi; }"),
        root.std.Ok<string> { value: "a {\n  b: 3.1415926536;\n}" },
    );
    assert.is_true(
        unwrap_err(run("@use \"onlyvar\" as f; a { b: f.floor(1.5); }")).includes(
            "Undefined function.",
        ),
    );
    // So do mixins: `@forward "sass:meta"` re-exports `load-css`, which then
    // fails on the STYLESHEET, not on the mixin name.
    root.std.write_file(root.std.path_join(dir, "_fmeta.scss"), "@forward \"sass:meta\";\n") catch (e) {
        _ => root.std.panic("write")
    };
    assert.is_true(
        unwrap_err(run("@use \"fmeta\" as f; a { @include f.load-css(\"nope.css\"); }")).includes(
            "Can't find stylesheet to import.",
        ),
    );
    // An inner `show`/`hide` keeps naming the member as the INNER rule exports
    // it, even after an outer rule renames it again.
    assert.equal(
        run("@use \"oshow\" as o; a { b: o.q-p-get((x: 1), x); }"),
        root.std.Ok<string> { value: "a {\n  b: 1;\n}" },
    );
    assert.is_true(
        unwrap_err(run("@use \"ohide\" as o; a { b: o.q-p-get((x: 1), x); }")).includes(
            "Undefined function.",
        ),
    );
    // A starred user module exposes what it forwards, to calls and to
    // introspection alike.
    assert.equal(
        run("@use \"fmap\" as *; a { b: get((x: 1), x); }"),
        root.std.Ok<string> { value: "a {\n  b: 1;\n}" },
    );
    assert.equal(
        run(
            "@use \"fmap\" as *; @use \"sass:meta\";\na { b: meta.inspect(meta.get-function(\"get\")); }",
        ),
        root.std.Ok<string> { value: "a {\n  b: get-function(\"get\");\n}" },
    );
    assert.equal(
        run("@use \"fmap\" as *; @use \"sass:meta\";\na { b: meta.function-exists(\"get\"); }"),
        root.std.Ok<string> { value: "a {\n  b: true;\n}" },
    );
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    };
}

test "every_kind_of_starred_member_competes_for_the_bare_name" {
    // `@use … as *` puts user members and built-in members (direct, or
    // forwarded by a starred user module) in ONE namespace: they shadow the
    // global, two DIFFERENT ones under a name is an error, and the same one
    // reached twice is not. Measured against dart-sass 1.103.1.
    let dir = root.std.path_join(root.tests.support.temp_dir(), `sasso_star_share_${baml.sys.pid()}`);
    root.std.create_dir_all(dir) catch (e) {
        _ => root.std.panic("mkdir")
    };
    root.std.write_file(root.std.path_join(dir, "_fmath.scss"), "@forward \"sass:math\";\n") catch (e) {
        _ => root.std.panic("write")
    };
    root.std.write_file(root.std.path_join(dir, "_fmap.scss"), "@forward \"sass:map\";\n") catch (e) {
        _ => root.std.panic("write")
    };
    root.std.write_file(root.std.path_join(dir, "_fmeta.scss"), "@forward \"sass:meta\";\n") catch (e) {
        _ => root.std.panic("write")
    };
    root.std.write_file(root.std.path_join(dir, "_fstr.scss"), "@forward \"sass:string\";\n") catch (e) {
        _ => root.std.panic("write")
    };
    root.std.write_file(root.std.path_join(dir, "_upi.scss"), "$pi: USERPI;\n") catch (e) {
        _ => root.std.panic("write")
    };
    root.std.write_file(
        root.std.path_join(dir, "_uindex.scss"),
        "@function index($a, $b) { @return USER; }\n",
    ) catch (e) {
        _ => root.std.panic("write")
    };
    root.std.write_file(root.std.path_join(dir, "_umix.scss"), "@mixin load-css($x) { u: 1; }\n") catch (e) {
        _ => root.std.panic("write")
    };
    let entry = root.std.path_join(dir, "in.scss");
    let url = entry;
    let imp = root.importer.FsImporter.new([]);
    let run = (src: string) -> StrResult {
        root.std.write_file(entry, src);
        let opts = root.Options.default().with_importer(imp).with_url(url);
        compile_map_err(src, opts)
    };
    // The SAME member reached two ways is one member, not an ambiguity.
    assert.equal(
        run("@use \"fmap\" as *; @use \"sass:map\" as *; a { b: get((x: 1), x); }"),
        root.std.Ok<string> { value: "a {\n  b: 1;\n}" },
    );
    assert.equal(
        run("@use \"fmath\" as *; @use \"sass:math\" as *; a { b: $pi; }"),
        root.std.Ok<string> { value: "a {\n  b: 3.1415926536;\n}" },
    );
    // A user member and a built-in one under the same name are two members.
    for (
        let c in [
            root.std.Tuple2<string, string> {
                _0: "@use \"uindex\" as *; @use \"sass:string\" as *; a { b: index(\"abc\", \"b\"); }",
                _1: "function",
            },
            root.std.Tuple2<string, string> {
                _0: "@use \"upi\" as *; @use \"sass:math\" as *; a { b: $pi; }",
                _1: "variable",
            },
            root.std.Tuple2<string, string> {
                _0: "@use \"umix\" as *; @use \"sass:meta\" as *; a { @include load-css(\"nope.css\"); }",
                _1: "mixin",
            },
        ]
    ) {
        let src = c._0;
        let what = c._1;
        let err = unwrap_err(run(src));
        // {src}: {err}
        assert.is_true(err.includes(`This ${what} is available from multiple global modules.`));
    }
    // And the introspection predicates see exactly what resolution sees.
    for (
        let c in [
            root.std.Tuple2<string, string> {
                _0: "@use \"sass:math\" as *; @use \"sass:meta\";\na { b: meta.global-variable-exists(\"pi\"); }",
                _1: "true",
            },
            root.std.Tuple2<string, string> {
                _0: "@use \"fmath\" as *; @use \"sass:meta\";\na { b: meta.variable-exists(\"pi\"); }",
                _1: "true",
            },
            root.std.Tuple2<string, string> {
                _0: "@use \"sass:meta\" as *; @use \"sass:meta\" as m;\na { b: m.mixin-exists(\"load-css\"); }",
                _1: "true",
            },
            root.std.Tuple2<string, string> {
                _0: "@use \"fmeta\" as *; @use \"sass:meta\" as m;\na { b: m.mixin-exists(\"load-css\"); }",
                _1: "true",
            },
        ]
    ) {
        let src = c._0;
        let want = c._1;
        // {src}
        assert.equal(run(src), root.std.Ok<string> { value: `a {\n  b: ${want};\n}` });
    }
    // A starred built-in mixin is includable and referenceable.
    assert.is_true(
        unwrap_err(run("@use \"sass:meta\" as *; a { @include load-css(\"nope.css\"); }")).includes(
            "Can't find stylesheet to import.",
        ),
    );
    assert.equal(
        run("@use \"sass:meta\" as *; a { b: inspect(get-mixin(\"load-css\")); }"),
        root.std.Ok<string> { value: "a {\n  b: get-mixin(\"load-css\");\n}" },
    );
    assert.equal(
        run(
            "@use \"fmeta\" as f; @use \"sass:meta\";\na { b: meta.inspect(meta.get-mixin(\"load-css\", $module: \"f\")); }",
        ),
        root.std.Ok<string> { value: "a {\n  b: get-mixin(\"load-css\");\n}" },
    );
    // An evaluator-owned `sass:meta` member reached unprefixed still reaches
    // the evaluator.
    assert.is_true(
        unwrap_err(run("@use \"sass:meta\" as *; a { b: inspect(module-functions(\"meta\")); }"))
            .includes("There is no module with namespace \"meta\"."),
    );
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    };
}

test "a_modules_own_member_shadows_the_builtin_it_forwards" {
    // A module that defines a member AND forwards a built-in exporting that
    // name exposes ONE member — its own — namespaced and starred alike; it is
    // not two members competing for the name. And a starred user mixin beside a
    // starred built-in one IS two. Measured against dart-sass 1.103.1.
    let dir = root.std.path_join(root.tests.support.temp_dir(), `sasso_own_shadow_${baml.sys.pid()}`);
    root.std.create_dir_all(dir) catch (e) {
        _ => root.std.panic("mkdir")
    };
    root.std.write_file(
        root.std.path_join(dir, "_ownfn.scss"),
        "@forward \"sass:string\";\n@function index($a, $b) { @return OWN; }\n",
    ) catch (e) {
        _ => root.std.panic("write")
    };
    root.std.write_file(
        root.std.path_join(dir, "_ownvar.scss"),
        "@forward \"sass:math\";\n$pi: OWNPI;\n",
    ) catch (e) {
        _ => root.std.panic("write")
    };
    root.std.write_file(
        root.std.path_join(dir, "_ownmix.scss"),
        "@forward \"sass:meta\";\n@mixin load-css($x) { own: 1; }\n",
    ) catch (e) {
        _ => root.std.panic("write")
    };
    root.std.write_file(root.std.path_join(dir, "_umix.scss"), "@mixin load-css($x) { u: 1; }\n") catch (e) {
        _ => root.std.panic("write")
    };
    let entry = root.std.path_join(dir, "in.scss");
    let url = entry;
    let imp = root.importer.FsImporter.new([]);
    let run = (src: string) -> StrResult {
        root.std.write_file(entry, src);
        let opts = root.Options.default().with_importer(imp).with_url(url);
        compile_map_err(src, opts)
    };
    for (
        let c in [
            root.std.Tuple2<string, string> {
                _0: "@use \"ownfn\" as f; a { b: f.index(\"abc\", \"b\"); }",
                _1: "OWN",
            },
            root.std.Tuple2<string, string> {
                _0: "@use \"ownfn\" as *; a { b: index(\"abc\", \"b\"); }",
                _1: "OWN",
            },
            root.std.Tuple2<string, string> {
                _0: "@use \"ownvar\" as f; a { b: f.$pi; }",
                _1: "OWNPI",
            },
            root.std.Tuple2<string, string> {
                _0: "@use \"ownvar\" as *; a { b: $pi; }",
                _1: "OWNPI",
            },
        ]
    ) {
        let src = c._0;
        let want = c._1;
        // {src}
        assert.equal(run(src), root.std.Ok<string> { value: `a {\n  b: ${want};\n}` });
    }
    for (
        let src in [
            "@use \"ownmix\" as f; a { @include f.load-css(\"x\"); }",
            "@use \"ownmix\" as *; a { @include load-css(\"x\"); }",
        ]
    ) {
        // {src}
        assert.equal(run(src), root.std.Ok<string> { value: "a {\n  own: 1;\n}" });
    }
    // Introspection agrees: one member, and it is the module's own.
    assert.equal(
        run("@use \"ownfn\" as *; @use \"sass:meta\";\na { b: meta.function-exists(\"index\"); }"),
        root.std.Ok<string> { value: "a {\n  b: true;\n}" },
    );
    // Two starred sources for one mixin name ARE two members, whichever asks.
    assert.is_true(
        unwrap_err(
            run(
                "@use \"umix\" as *; @use \"sass:meta\" as *;\na { b: inspect(get-mixin(\"load-css\")); }",
            ),
        )
            .includes("This mixin is available from multiple global modules."),
    );
    // One star and one namespace is one member, so it resolves.
    assert.equal(
        run(
            "@use \"umix\" as *; @use \"sass:meta\" as m;\na { b: m.inspect(m.get-mixin(\"load-css\")); }",
        ),
        root.std.Ok<string> { value: "a {\n  b: get-mixin(\"load-css\");\n}" },
    );
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    };
}

test "a_builtin_mixin_reference_can_be_taken_and_invoked" {
    // `meta.get-mixin` reaches `load-css`/`apply` through whatever namespace
    // is bound — an alias included — and `meta.apply` then INVOKES the
    // reference it returns. Measured against dart-sass 1.103.1.
    let dir = root.std.path_join(root.tests.support.temp_dir(), `sasso_builtin_mixin_${baml.sys.pid()}`);
    root.std.create_dir_all(dir) catch (e) {
        _ => root.std.panic("mkdir")
    };
    root.std.write_file(root.std.path_join(dir, "_fmeta.scss"), "@forward \"sass:meta\";\n") catch (e) {
        _ => root.std.panic("write")
    };
    root.std.write_file(root.std.path_join(dir, "real.css"), "x { loaded: 1; }\n") catch (e) {
        _ => root.std.panic("write")
    };
    let entry = root.std.path_join(dir, "in.scss");
    let url = entry;
    let imp = root.importer.FsImporter.new([]);
    let run = (src: string) -> StrResult {
        root.std.write_file(entry, src);
        let opts = root.Options.default().with_importer(imp).with_url(url);
        compile_map_err(src, opts)
    };
    // An ALIASED built-in namespace is still that module.
    for (
        let src in [
            "@use \"sass:meta\" as m; a { b: m.inspect(m.get-mixin(\"load-css\", $module: \"m\")); }",
            "@use \"sass:meta\"; a { b: meta.inspect(meta.get-mixin(\"load-css\", $module: \"meta\")); }",
        ]
    ) {
        // {src}
        assert.equal(
            run(src),
            root.std.Ok<string> { value: "a {\n  b: get-mixin(\"load-css\");\n}" },
        );
    }
    // And the reference is invocable, however it was obtained.
    for (
        let src in [
            "@use \"sass:meta\";\na { @include meta.apply(meta.get-mixin(\"load-css\", $module: \"meta\"), \"real\"); }",
            "@use \"fmeta\" as f;\na { @include f.apply(f.get-mixin(\"load-css\", $module: \"f\"), \"real\"); }",
            "@use \"sass:meta\" as *;\na { @include apply(get-mixin(\"load-css\"), \"real\"); }",
        ]
    ) {
        // {src}
        assert.equal(run(src), root.std.Ok<string> { value: "a x {\n  loaded: 1;\n}" });
    }
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    };
}

test "a_mixin_reached_through_a_reference_reports_where_it_was_included" {
    // An error raised inside a first-class `load-css` carets the `@include`
    // that reached it, exactly as a direct one does — and a bare `@include`
    // that two starred modules both answer carets the same statement.
    // Measured against dart-sass 1.103.1.
    let dir = root.std.path_join(root.tests.support.temp_dir(), `sasso_ref_span_${baml.sys.pid()}`);
    root.std.create_dir_all(dir) catch (e) {
        _ => root.std.panic("mkdir")
    };
    root.std.write_file(root.std.path_join(dir, "_umix.scss"), "@mixin load-css($x) { u: 1; }\n") catch (e) {
        _ => root.std.panic("write")
    };
    let entry = root.std.path_join(dir, "in.scss");
    let url = entry;
    let imp = root.importer.FsImporter.new([]);
    let run = (src: string) -> string {
        root.std.write_file(entry, src);
        let opts = root.Options.default().with_importer(imp).with_url(url);
        compile_expect_err(src, opts, "expected a compile error").to_string()
    };
    // The reference and the direct call caret the same statement, `;` included.
    let via_ref = run(
        "@use \"sass:meta\";\na {\n  @include meta.apply(meta.get-mixin(\"load-css\", $module: \"meta\"), \"nope\");\n}\n",
    );
    // {via_ref}
    assert.is_true(via_ref.starts_with("Error: Can't find stylesheet to import."));
    // PORT: `str::len` counts bytes.
    // {via_ref}
    assert.equal(caret_line(via_ref).byte_length(), 72);
    let direct = run("@use \"sass:meta\";\na {\n  @include meta.load-css(\"nope\");\n}\n");
    // {direct}
    assert.equal(caret_line(direct).byte_length(), 30);
    // An argument error from the reference reports the same way.
    let bad_arg = run(
        "@use \"sass:meta\";\na {\n  @include meta.apply(meta.get-mixin(\"load-css\", $module: \"meta\"), 1);\n}\n",
    );
    // {bad_arg}
    assert.is_true(bad_arg.starts_with("Error: $url: 1 is not a string."));
    // {bad_arg}
    assert.equal(caret_line(bad_arg).byte_length(), 67);
    // Two starred modules answering one `@include` caret the include. (dart
    // adds a secondary row per `@use`, which this renderer cannot draw yet.)
    let ambiguous = run("@use \"umix\" as *;\n@use \"sass:meta\" as *;\na {\n  @include load-css(\"nope\");\n}\n");
    // {ambiguous}
    assert.is_true(
        ambiguous.starts_with("Error: This mixin is available from multiple global modules."),
    );
    // {ambiguous}
    assert.equal(caret_line(ambiguous).byte_length(), 25);
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    };
}

test "a_builtin_mixin_answers_to_its_underscore_spelling" {
    // `_` and `-` are one character in a Sass identifier, for `sass:meta`'s
    // mixins as for everything else — by call, by reference, and by existence
    // query. Measured against dart-sass 1.103.1.
    let dir = root.std.path_join(root.tests.support.temp_dir(), `sasso_mixin_under_${baml.sys.pid()}`);
    root.std.create_dir_all(dir) catch (e) {
        _ => root.std.panic("mkdir")
    };
    root.std.write_file(root.std.path_join(dir, "_fmeta.scss"), "@forward \"sass:meta\";\n") catch (e) {
        _ => root.std.panic("write")
    };
    root.std.write_file(root.std.path_join(dir, "real.css"), "x { loaded: 1; }\n") catch (e) {
        _ => root.std.panic("write")
    };
    let entry = root.std.path_join(dir, "in.scss");
    let url = entry;
    let imp = root.importer.FsImporter.new([]);
    let run = (src: string) -> StrResult {
        root.std.write_file(entry, src);
        let opts = root.Options.default().with_importer(imp).with_url(url);
        compile_map_err(src, opts)
    };
    // Every route to the mixin takes either spelling.
    for (
        let src in [
            "@use \"sass:meta\"; a { @include meta.load_css(\"real\"); }",
            "@use \"sass:meta\"; a { @include meta.load-css(\"real\"); }",
            "@use \"sass:meta\" as m; a { @include m.load_css(\"real\"); }",
            "@use \"sass:meta\" as *; a { @include load_css(\"real\"); }",
            "@use \"fmeta\" as f; a { @include f.load_css(\"real\"); }",
        ]
    ) {
        // {src}
        assert.equal(run(src), root.std.Ok<string> { value: "a x {\n  loaded: 1;\n}" });
    }
    // A reference is stored canonically, so it inspects and compares as one.
    assert.equal(
        run(
            "@use \"sass:meta\";\na { b: meta.inspect(meta.get-mixin(\"load_css\", $module: \"meta\")); }",
        ),
        root.std.Ok<string> { value: "a {\n  b: get-mixin(\"load-css\");\n}" },
    );
    assert.equal(
        run(
            "@use \"sass:meta\";\na { b: meta.get-mixin(\"load_css\", $module: \"meta\") == meta.get-mixin(\"load-css\", $module: \"meta\"); }",
        ),
        root.std.Ok<string> { value: "a {\n  b: true;\n}" },
    );
    // And the existence query agrees with both.
    assert.equal(
        run("@use \"sass:meta\";\na { b: meta.mixin-exists(\"load_css\", $module: \"meta\"); }"),
        root.std.Ok<string> { value: "a {\n  b: true;\n}" },
    );
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    };
}

test "call_by_name_resolves_what_the_name_would_have" {
    // `call("name")` looks the name up exactly as writing it would: a user
    // `@function`, then a member a `@use … as *` exposes (user or built-in),
    // then the global — ambiguity included. Measured against dart-sass 1.103.1.
    let dir = root.std.path_join(root.tests.support.temp_dir(), `sasso_call_name_${baml.sys.pid()}`);
    root.std.create_dir_all(dir) catch (e) {
        _ => root.std.panic("mkdir")
    };
    root.std.write_file(root.std.path_join(dir, "_fmap.scss"), "@forward \"sass:map\";\n") catch (e) {
        _ => root.std.panic("write")
    };
    root.std.write_file(
        root.std.path_join(dir, "_own.scss"),
        "@function own($x) { @return OWN; }\n",
    ) catch (e) {
        _ => root.std.panic("write")
    };
    root.std.write_file(
        root.std.path_join(dir, "_uindex.scss"),
        "@function index($a, $b) { @return USER; }\n",
    ) catch (e) {
        _ => root.std.panic("write")
    };
    let entry = root.std.path_join(dir, "in.scss");
    let url = entry;
    let imp = root.importer.FsImporter.new([]);
    let run = (src: string) -> StrResult {
        root.std.write_file(entry, src);
        let opts = root.Options.default().with_importer(imp).with_url(url);
        compile_map_err(src, opts)
    };
    for (
        let c in [
            root.std.Tuple2<string, string> {
                _0: "@use \"sass:map\" as *; @use \"sass:meta\";\na { b: meta.call(\"get\", (x: 1), x); }",
                _1: "1",
            },
            root.std.Tuple2<string, string> {
                _0: "@use \"fmap\" as *; @use \"sass:meta\";\na { b: meta.call(\"get\", (x: 1), x); }",
                _1: "1",
            },
            root.std.Tuple2<string, string> {
                _0: "@use \"own\" as *; @use \"sass:meta\";\na { b: meta.call(\"own\", 1); }",
                _1: "OWN",
            },
            root.std.Tuple2<string, string> {
                _0: "@use \"sass:string\" as *; @use \"sass:meta\";\na { b: meta.call(\"index\", \"abc\", \"b\"); }",
                _1: "2",
            },
        ]
    ) {
        let src = c._0;
        let want = c._1;
        // {src}
        assert.equal(run(src), root.std.Ok<string> { value: `a {\n  b: ${want};\n}` });
    }
    // Two starred sources for the name is the same error it would be written.
    assert.is_true(
        unwrap_err(
            run(
                "@use \"uindex\" as *; @use \"sass:string\" as *; @use \"sass:meta\";\na { b: meta.call(\"index\", \"abc\", \"b\"); }",
            ),
        )
            .includes("This function is available from multiple global modules."),
    );
    // A name nothing owns is still left to the plain-CSS dispatcher.
    assert.equal(
        run("@use \"sass:meta\"; a { b: meta.call(\"nope\", 1); }"),
        root.std.Ok<string> { value: "a {\n  b: nope(1);\n}" },
    );
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    };
}

test "one_span_can_carry_two_call_string_recommendations" {
    // The dedup identity is everything the warning SAYS: `[call-string]`'s
    // message is static and its `Recommendation:` carries the name, so one
    // `call($n)` invoked with two names warns twice. dart prints both.
    let w = warnings(
        "@use \"sass:meta\";\n@function pick($n) { @return meta.call($n, 1); }\n@function a($x) { @return A; }\n@function b($x) { @return B; }\n.x { p: pick(\"a\"); q: pick(\"b\"); }\n",
        "in.scss",
    );
    let recs: string[] = w.filter((x) -> {
        x.includes("[call-string]")
    });
    // {w:?}
    assert.equal(recs.length(), 2);
    // {}: recs[0]
    assert.is_true(recs[0].includes("Recommendation: call(get-function(\"a\"))"));
    // {}: recs[1]
    assert.is_true(recs[1].includes("Recommendation: call(get-function(\"b\"))"))
}

test "a_legacy_color_function_suggests_its_replacement" {
    // dart computes the suggestion from the call's OWN arguments: a channel
    // getter names the channel and its space, an adjuster offers the relative
    // `color.scale` (whose percentage depends on where the colour already is)
    // and the absolute `color.adjust`. Every expectation measured against
    // dart-sass 1.103.1.
    let sug = (src: string) -> string[] {
        warnings(src, "in.scss").filter((w) -> {
            w.includes("[color-functions]")
        })
    };
    let one = (src: string) -> string {
        let w = sug(src);
        // {src}: {w:?}
        assert.equal(w.length(), 1);
        // PORT: `w.into_iter().next().unwrap()`.
        root.std.unwrap(w.at(0))
    };
    // Channel getters name the space, because `color.channel` would otherwise
    // default to the colour's own.
    for (
        let c in [
            root.std.Tuple2<string, string> { _0: "red", _1: "rgb" },
            root.std.Tuple2<string, string> { _0: "green", _1: "rgb" },
            root.std.Tuple2<string, string> { _0: "blue", _1: "rgb" },
            root.std.Tuple2<string, string> { _0: "hue", _1: "hsl" },
            root.std.Tuple2<string, string> { _0: "saturation", _1: "hsl" },
            root.std.Tuple2<string, string> { _0: "lightness", _1: "hsl" },
        ]
    ) {
        let name = c._0;
        let space = c._1;
        let w = one(`a { b: ${name}(#abcdef); }\n`);
        // {w}
        assert.is_true(w.includes(`${name}() is deprecated. Suggestion:`));
        // {w}
        assert.is_true(w.includes(`color.channel($color, "${name}", $space: ${space})`));
    }
    // Through the module it names itself `color.<fn>`, under any namespace.
    for (
        let src in [
            "@use \"sass:color\";\na { b: color.whiteness(#abcdef); }\n",
            "@use \"sass:color\" as c;\na { b: c.whiteness(#abcdef); }\n",
            "@use \"sass:color\" as *;\na { b: whiteness(#abcdef); }\n",
        ]
    ) {
        let w = one(src);
        // {src}: {w}
        assert.is_true(w.includes("color.whiteness() is deprecated."));
        // {src}: {w}
        assert.is_true(w.includes("color.channel($color, \"whiteness\", $space: hwb)"));
    }
    // The adjusters: the scale percentage is the move over the room left in
    // that direction, clamped, and omitted when the move is zero.
    for (
        let c in [
            root.std.Tuple3<string, string?, string> {
                _0: "a { b: lighten(#abcdef, 10%); }\n",
                _1: "51%",
                _2: "$lightness: 10%",
            },
            root.std.Tuple3<string, string?, string> {
                _0: "a { b: darken(#abcdef, 10%); }\n",
                _1: "-12.4390243902%",
                _2: "$lightness: -10%",
            },
            root.std.Tuple3<string, string?, string> {
                _0: "a { b: saturate(#abcdef, 10%); }\n",
                _1: "31.25%",
                _2: "$saturation: 10%",
            },
            root.std.Tuple3<string, string?, string> {
                _0: "a { b: desaturate(#abcdef, 10%); }\n",
                _1: "-14.7058823529%",
                _2: "$saturation: -10%",
            },
            root.std.Tuple3<string, string?, string> {
                _0: "a { b: opacify(rgba(1, 2, 3, 0.5), 0.1); }\n",
                _1: "$alpha: 20%",
                _2: "$alpha: 0.1",
            },
            root.std.Tuple3<string, string?, string> {
                _0: "a { b: transparentize(rgba(1, 2, 3, 0.5), 0.1); }\n",
                _1: "$alpha: -20%",
                _2: "$alpha: -0.1",
            },
            // Already at the bound: all the way, however much was asked.
            root.std.Tuple3<string, string?, string> {
                _0: "a { b: lighten(#fff, 10%); }\n",
                _1: "100%",
                _2: "$lightness: 10%",
            },
            root.std.Tuple3<string, string?, string> {
                _0: "a { b: darken(#000, 10%); }\n",
                _1: "-100%",
                _2: "$lightness: -10%",
            },
            // Past the bound clamps rather than exceeding 100%.
            root.std.Tuple3<string, string?, string> {
                _0: "a { b: lighten(#ccc, 50%); }\n",
                _1: "100%",
                _2: "$lightness: 50%",
            },
            // A hue is an angle with no bound, so it never scales.
            root.std.Tuple3<string, string?, string> {
                _0: "a { b: adjust-hue(#abcdef, 10deg); }\n",
                _1: null,
                _2: "$hue: 10deg",
            },
            root.std.Tuple3<string, string?, string> {
                _0: "a { b: adjust-hue(#abcdef, 0.25turn); }\n",
                _1: null,
                _2: "$hue: 90deg",
            },
            // Moving by nothing drops the scale line entirely.
            root.std.Tuple3<string, string?, string> {
                _0: "a { b: saturate(#abcdef, 0%); }\n",
                _1: null,
                _2: "$saturation: 0%",
            },
            // A MISSING alpha is 0, not the opaque 1 the color carries for
            // serialization, so the room left is the whole range: opacifying by
            // 0.2 is 20% of the way up, and transparentizing is all the way down.
            root.std.Tuple3<string, string?, string> {
                _0: "a { b: opacify(hsl(240 100% 50% / none), 0.2); }\n",
                _1: "$alpha: 20%",
                _2: "$alpha: 0.2",
            },
            root.std.Tuple3<string, string?, string> {
                _0: "a { b: transparentize(hsl(240 100% 50% / none), 0.2); }\n",
                _1: "$alpha: -100%",
                _2: "$alpha: -0.2",
            },
        ]
    ) {
        let src = c._0;
        let scale = c._1;
        let adjust = c._2;
        let w = one(src);
        match (scale) {
            let s: string => {
                // {src}: {w}
                assert.is_true(w.includes("Suggestions:"));
                // {src}: {w}
                assert.is_true(w.includes("color.scale($color, "));
                // {src}: {w}
                assert.is_true(w.includes(s));
            },
            null => {
                // {src}: {w}
                assert.is_true(w.includes("Suggestion:"));
                // {src}: {w}
                assert.is_true(!w.includes("color.scale"));
            },
        }
        // {src}: {w}
        assert.is_true(w.includes(`color.adjust($color, ${adjust})`));
    }
    // The amount is read as a value, so a unitless one still suggests `%`.
    assert.is_true(one("a { b: lighten(#abcdef, 10); }\n").includes("$lightness: 10%"));
    // Named arguments are read under the parameter name the FUNCTION uses,
    // which is not uniform: `adjust-hue` binds `$degrees`, the rest `$amount`.
    assert.is_true(
        one("a { b: lighten($color: #abcdef, $amount: 10%); }\n").includes("$lightness: 10%"),
    );
    assert.is_true(
        one("a { b: adjust-hue($color: #abcdef, $degrees: 10deg); }\n").includes(
            "color.adjust($color, $hue: 10deg)",
        ),
    );
    // `whiteness`/`blackness` are `sass:color`-ONLY, so the bare spelling is a
    // plain CSS function that deprecates nothing — however it is reached.
    assert.is_true(sug("a { b: whiteness(#abcdef); }\n").length() == 0);
    assert.is_true(sug("a { b: blackness(#abcdef); }\n").length() == 0);
    assert.is_true(
        sug("@use \"sass:meta\"; a { b: meta.call(\"whiteness\", #abcdef); }\n").length() == 0,
    );
    // A user `@function` of a deprecated name is the one that runs.
    assert.is_true(
        sug("@function lighten($c, $n) { @return MINE; }\na { b: lighten(#abcdef, 10%); }\n")
            .length()
            == 0,
    );
    // Members that were NOT deprecated stay quiet.
    for (
        let src in [
            "a { b: alpha(rgba(1, 2, 3, 0.5)); }\n",
            "a { b: mix(#abcdef, #123456); }\n",
            "a { b: grayscale(#abcdef); }\n",
            "a { b: complement(#abcdef); }\n",
            "a { b: invert(#abcdef); }\n",
        ]
    ) {
        // {src}
        assert.is_true(sug(src).length() == 0);
    }
    // A call whose arguments are rejected warns about nothing: dart raises
    // this from INSIDE the function, after they are validated.
    assert.is_true(sug("a { b: lighten(3, 10%); }\n").length() == 0);
    assert.is_true(sug("a { b: lighten(#abcdef, 150%); }\n").length() == 0);
    // A first-class reference reaches the same function, so it carries the
    // same deprecation — computed suggestion and all — reported against the
    // INVOCATION.
    let w = one("@use \"sass:meta\";\na { b: meta.call(meta.get-function(\"lighten\"), #abcdef, 10%); }\n");
    // {w}
    assert.is_true(w.includes("lighten() is deprecated. Suggestions:"));
    // {w}
    assert.is_true(w.includes("color.scale($color, $lightness: 51%)"));
    let w = one("a { b: call(\"darken\", #abcdef, 10%); }\n");
    // {w}
    assert.is_true(w.includes("color.scale($color, $lightness: -12.4390243902%)"));
    // Taken from the MODULE it names itself that way — and `color.whiteness`
    // is reachable only that way.
    let w = one(
        "@use \"sass:meta\"; @use \"sass:color\";\na { b: meta.call(meta.get-function(\"whiteness\", $module: \"color\"), #abcdef); }\n",
    );
    // {w}
    assert.is_true(w.includes("color.whiteness() is deprecated."));
    // {w}
    assert.is_true(w.includes("color.channel($color, \"whiteness\", $space: hwb)"));
    // An `hsl()` colour keeps its channels, and the scale percentage divides
    // by the room left in one — so it is read from the colour, not re-derived.
    let w = one("a { b: saturate(hsl(20, 99.9999%, 50%), 0.00001%); }\n");
    // {w}
    assert.is_true(w.includes("$saturation: 9.9999999997%"));
    // And the suggestion follows the VALUE, so one call site can warn twice.
    let w = sug(
        "@mixin m($c) { b: lighten($c, 10%); }\na { @include m(#abcdef); }\nd { @include m(#123456); }\n",
    );
    // {w:?}
    assert.equal(w.length(), 2);
    // {}: w[0]
    assert.is_true(w[0].includes("$lightness: 51%"));
    // {}: w[1]
    assert.is_true(w[1].includes("$lightness: 12.5615763547%"))
}

test "the_legacy_if_suggests_the_modern_syntax" {
    // dart raises `[if-function]` when the file is PARSED: for an `if()` nobody
    // runs, once however many times it does run, innermost first, and with no
    // call stack. The suggestion is the three arguments written back out — the
    // AST, not the source text. Measured against dart-sass 1.103.1.
    let sug = (src: string) -> string[] {
        warnings(src, "in.scss")
    };
    let one = (src: string) -> string {
        let w = sug(src);
        // {src}: {w:?}
        assert.equal(w.length(), 1);
        // PORT: `w.into_iter().next().unwrap()`.
        root.std.unwrap(w.at(0))
    };
    assert.is_true(
        one("a { b: if(true, 1, 2); }\n").includes("Suggestion: if(sass(true): 1; else: 2)"),
    );
    // The AST is written back out, so the text is normalized, not copied.
    for (
        let c in [
            root.std.Tuple2<string, string> {
                _0: "a { b: if(true,1+2,3); }\n",
                _1: "if(sass(true): 1 + 2; else: 3)",
            },
            root.std.Tuple2<string, string> {
                _0: "a { b: if( true , 1 , 2 ); }\n",
                _1: "if(sass(true): 1; else: 2)",
            },
            root.std.Tuple2<string, string> {
                _0: "a { b: if(true, 1e3, 2); }\n",
                _1: "if(sass(true): 1000; else: 2)",
            },
            root.std.Tuple2<string, string> {
                _0: "a { b: if(true, 1px*2, 3); }\n",
                _1: "if(sass(true): 1px * 2; else: 3)",
            },
            root.std.Tuple2<string, string> {
                _0: "a { b: if(true, #ABCDEF, 3); }\n",
                _1: "if(sass(true): #ABCDEF; else: 3)",
            },
            root.std.Tuple2<string, string> {
                _0: "a { b: if(true, \"a\\41 b\", 3); }\n",
                _1: "if(sass(true): \"aAb\"; else: 3)",
            },
            root.std.Tuple2<string, string> {
                _0: "a { b: if(true, 'he said \"hi\"', 3); }\n",
                _1: "if(sass(true): 'he said \"hi\"'; else: 3)",
            },
            root.std.Tuple2<string, string> {
                _0: "$v: 1;\na { b: if(true, \"x#{$v}y\", 3); }\n",
                _1: "if(sass(true): \"x#{$v}y\"; else: 3)",
            },
            root.std.Tuple2<string, string> {
                _0: "a { b: if(true, (1 2), 3); }\n",
                _1: "if(sass(true): (1 2); else: 3)",
            },
            root.std.Tuple2<string, string> {
                _0: "a { b: if(true, (a: 1), 2); }\n",
                _1: "if(sass(true): (a: 1); else: 2)",
            },
            root.std.Tuple2<string, string> {
                _0: "a { b: if(true, [], 2); }\n",
                _1: "if(sass(true): []; else: 2)",
            },
            root.std.Tuple2<string, string> {
                _0: "a { b: if(true, (), 2); }\n",
                _1: "if(sass(true): (); else: 2)",
            },
            // A one-element comma list needs the parens that make it a list, and
            // the trailing comma with them — but inside brackets it needs neither.
            root.std.Tuple2<string, string> {
                _0: "a { b: if(true, (1,), 2); }\n",
                _1: "if(sass(true): ((1,)); else: 2)",
            },
            root.std.Tuple2<string, string> {
                _0: "a { b: if(true, [1,], 2); }\n",
                _1: "if(sass(true): [1]; else: 2)",
            },
            root.std.Tuple2<string, string> {
                _0: "a { b: if(true, (1, 2), 3); }\n",
                _1: "if(sass(true): (1, 2); else: 3)",
            },
            root.std.Tuple2<string, string> {
                _0: "a { b: if(not true, 1, 2); }\n",
                _1: "if(sass(not true): 1; else: 2)",
            },
            root.std.Tuple2<string, string> {
                _0: "$v: 1;\na { b: if($v > 1, 1, 2); }\n",
                _1: "if(sass($v > 1): 1; else: 2)",
            },
            // A `null` branch is dropped, and a null THEN flips the condition.
            root.std.Tuple2<string, string> {
                _0: "a { b: if(true, 1, null); }\n",
                _1: "if(sass(true): 1)",
            },
            root.std.Tuple2<string, string> {
                _0: "$v: 1;\na { b: if($v, null, 2); }\n",
                _1: "if(not sass($v): 2)",
            },
            root.std.Tuple2<string, string> {
                _0: "a { b: if(true, null, null); }\n",
                _1: "if(sass(true): null)",
            },
        ]
    ) {
        let src = c._0;
        let want = c._1;
        let w = one(src);
        // {src}: {w}
        assert.is_true(w.includes(`Suggestion: ${want}`));
    }
    // No suggestion for a shape the rewrite cannot express — the deprecation
    // still fires.
    for (
        let src in [
            "a { b: if($condition: true, $if-true: 1, $if-false: 2); }\n",
            "$a: (true, 1, 2);\na { b: if($a...); }\n",
        ]
    ) {
        let w = one(src);
        // {src}: {w}
        assert.is_true(w.includes("[if-function]"));
        // {src}: {w}
        assert.is_true(!w.includes("Suggestion:"));
    }
    // Innermost first, because dart builds the expression bottom up.
    let w = sug("a { b: if(true, if(false, 1, 2), 3); }\n");
    // {w:?}
    assert.equal(w.length(), 2);
    // {}: w[0]
    assert.is_true(w[0].includes("if(sass(false): 1; else: 2)"));
    // {}: w[1]
    assert.is_true(w[1].includes("if(sass(true): if(false, 1, 2); else: 3)"));
    // PARSE time: it fires for code that never runs, and once for code that
    // runs repeatedly.
    assert.equal(sug("@mixin m { z: if(true, 1, 2); }\na { q: 1; }\n").length(), 1);
    assert.equal(sug("@if false { a { z: if(true, 1, 2); } }\nb { q: 1; }\n").length(), 1);
    assert.equal(
        sug("@mixin m($x) { z: if($x, 1, 2); }\na { @include m(true); }\nb { @include m(false); }\n")
            .length(),
        1,
    );
    assert.equal(sug("@for $i from 1 through 3 { a#{$i} { z: if(true, 1, 2); } }\n").length(), 1);
    // And it has no call stack: the frame is the file, not the mixin.
    let w = one("@mixin m($x) { z: if($x, 1, 2); }\na { @include m(true); }\n");
    // {w}
    assert.equal(count_matches(w, "root stylesheet"), 1);
    // {w}
    assert.is_true(!w.includes("m()"));
    // An interpolated string escapes its literal text like any other, so a
    // newline in the source is `\a` in the suggestion rather than a newline in
    // the middle of the diagnostic.
    assert.is_true(
        one("$x: 1;\na { b: if(true, \"a\\a #{$x}\", 3); }\n").includes(
            "Suggestion: if(sass(true): \"a\\a#{$x}\"; else: 3)",
        ),
    );
    // The single-`=` filter operator is written with spaces, as dart writes it.
    assert.is_true(
        one("a { b: if(true, alpha(opacity=80), 3); }\n").includes(
            "Suggestion: if(sass(true): alpha(opacity = 80); else: 3)",
        ),
    );
    // A user `@function if` does not take the form over, in dart or here.
    assert.equal(
        sug("@function if($c, $t, $f) { @return 9; }\na { b: if(true, 1, 2); }\n").length(),
        1,
    );
    // It is found wherever an expression can be written.
    for (
        let src in [
            "a { z: #{if(true, 1, 2)}; }\n",
            "a#{if(true, x, y)} { q: 1; }\n",
            "@media (min-width: if(true, 1px, 2px)) { a { q: 1; } }\n",
            "@supports (a: if(true, 1, 2)) { b { q: 1; } }\n",
            "@each $i in if(true, 1 2, 3) { a { q: $i; } }\n",
            "@mixin m($p: if(true, 1, 2)) { q: $p; }\na { @include m; }\n",
            "@warn if(true, \"w\", \"v\");\na { q: 1; }\n",
            "/* c #{if(true, 1, 2)} */\n",
            "@import url(if(true, a, b));\n",
            "@mixin m { @content(if(true, 1, 2)); }\na { @include m using ($x) { q: $x; } }\n",
            "%p { q: 1; }\na { @extend #{if(true, \"%p\", \"%p\")}; }\n",
            // A custom at-rule's INTERPOLATED property and its value are
            // SassScript; a literal property's value is verbatim text here (dart
            // parses that one as SassScript too — a separate gap, in the CSS).
            "@function --foo() { #{if(true, x, y)}: 1; }\n",
            "@keyframes #{if(true, fade, none)} { from { o: 0; } }\n",
        ]
    ) {
        // `@warn` adds its own output; this is about the deprecation.
        let found: string[] = sug(src).filter((w) -> {
            w.includes("[if-function]")
        });
        // {src}: {found:?}
        assert.equal(found.length(), 1);
    }
}

test "an_argument_error_shows_the_declaration_it_failed_against" {
    // dart points at TWO places for the argument-binding family: where the
    // call is, and the parameter list it was measured against. Every block
    // below was measured against dart-sass 1.103.1.
    let dir = root.std.path_join(root.tests.support.temp_dir(), `sasso_decl_span_${baml.sys.pid()}`);
    root.std.create_dir_all(dir) catch (e) {
        _ => root.std.panic("mkdir")
    };
    root.std.write_file(root.std.path_join(dir, "_lib.scss"), "@mixin m($x) { a: $x; }\n") catch (e) {
        _ => root.std.panic("write")
    };
    let entry = root.std.path_join(dir, "in.scss");
    let url = entry;
    let imp = root.importer.FsImporter.new([]);
    let run = (src: string) -> string {
        root.std.write_file(entry, src);
        compile_expect_err(src, root.Options.default().with_importer(imp).with_url(url), "expected a compile error")
            .to_string()
    };
    // The arity message counts what was declared against what was passed, and
    // agrees with itself about the verb.
    for (
        let c in [
            root.std.Tuple2<string, string> {
                _0: "@function f() { @return 1; }\n.a { b: f(1); }\n",
                _1: "Only 0 arguments allowed, but 1 was passed.",
            },
            root.std.Tuple2<string, string> {
                _0: "@function f($x) { @return 1; }\n.a { b: f(1, 2); }\n",
                _1: "Only 1 argument allowed, but 2 were passed.",
            },
            root.std.Tuple2<string, string> {
                _0: "@function f($x, $y) { @return 1; }\n.a { b: f(1, 2, 3); }\n",
                _1: "Only 2 arguments allowed, but 3 were passed.",
            },
        ]
    ) {
        let src = c._0;
        let message = c._1;
        let block = run(src);
        // {block}
        assert.is_true(block.starts_with(`Error: ${message}\n`));
        // {block}
        assert.is_true(block.includes(" declaration\n"));
        // {block}
        assert.is_true(caret_line(block).ends_with(" invocation"));
    }
    // `No parameter named` carries it too.
    let block = run("@function f($x) { @return 1; }\n.a { b: f(1, $z: 2); }\n");
    // {block}
    assert.is_true(block.starts_with("Error: No parameter named $z.\n"));
    // {block}
    assert.is_true(block.includes("━━━━━ declaration"));
    // A content block a mixin does not take: the call is the primary span,
    // the mixin NAME the secondary — and the trace starts at the caller,
    // because the mixin is never entered.
    let block = run("@mixin m { a: 1; }\n.a { @include m { b: 2; } }\n");
    // {block}
    assert.is_true(block.starts_with("Error: Mixin doesn't accept a content block.\n"));
    // {block}
    assert.is_true(block.includes("━ declaration"));
    // {block}
    assert.equal(caret_line(block), "^^^^^^^^^^ invocation");
    // {block}
    assert.is_true(!block.includes("m()"));
    // A declaration in ANOTHER file gets its own block, headed by its url.
    let block = run("@use \"lib\";\n.a { @include lib.m; }\n");
    // {block}
    assert.is_true(block.includes("┌──> "));
    // {block}
    assert.is_true(block.includes("_lib.scss"));
    // {block}
    assert.is_true(block.includes("━━━━━ declaration"));
    let _ = baml.fs.remove_dir_all(dir) catch (e) {
        _ => null
    };
}

/// Everything up to and including the block's closing gutter glyph — the part
/// that does not name a temporary directory.
function snippet(block: string) -> string {
    let lines: string[] = block.lines();
    // PORT: `.iter().rposition(|l| l.trim() == "╵")` → a descending index loop.
    let found: int? = null;
    let i = lines.length() - 1;
    while (i >= 0) {
        if (root.std.trim(lines[i]) == "╵") {
            found = i;
            break;
        }
        i -= 1;
    }
    let end = found ?? root.std.panic(`no closing glyph in:\n${block}`);
    lines.slice(0, end + 1).join("\n")
}

test "a_span_that_crosses_lines_draws_an_arm_down_to_its_label" {
    // dart draws an arm beside every line a span covers and hangs the label on
    // the row that closes it — and one such span anywhere indents EVERY line of
    // the diagnostic by the arm column, blank arm included. Each block below is
    // dart-sass 1.103.1's, byte for byte.
    let run = (src: string) -> string {
        snippet(
            compile_expect_err(src, root.Options.default().with_url("t.scss"), "expected a compile error")
                .to_string(),
        )
    };
    // A call that starts mid-line opens with an arrow row; the closing row
    // points at the last spanned character.
    // PORT: the Rust string's `\`-newline continuations → `+` concatenation.
    assert.equal(
        run("@mixin m($x) { a: $x; }\n.a { @include m(\n); }\n"),
        "Error: Missing argument $x.\n  ╷\n"
            + "1 │   @mixin m($x) { a: $x; }\n  │          ━━━━━ declaration\n"
            + "2 │   .a { @include m(\n  │ ┌──────^\n"
            + "3 │ │ ); }\n  │ └─^ invocation\n  ╵",
    );
    // A call that starts its line puts the arm in the gutter instead; one that
    // also ENDS its line has nothing to point at, so dart draws a flat arm.
    assert.equal(
        run("@mixin m($x) { a: $x; }\n@include m(\n)\n;\n"),
        "Error: Missing argument $x.\n  ╷\n"
            + "1 │   @mixin m($x) { a: $x; }\n  │          ━━━━━ declaration\n"
            + "2 │ ┌ @include m(\n"
            + "3 │ │ )\n  │ └─── invocation\n  ╵",
    );
    // The DECLARATION crossing lines is the same shape — it just comes first.
    assert.equal(
        run("@mixin m(\n  $x: 1\n) { a: $x; }\n.a { @include m(1, 2); }\n"),
        "Error: Only 1 argument allowed, but 2 were passed.\n  ╷\n"
            + "1 │   @mixin m(\n  │ ┌────────^\n"
            + "2 │ │   $x: 1\n"
            + "3 │ │ ) { a: $x; }\n  │ └─^ declaration\n"
            + "4 │   .a { @include m(1, 2); }\n  │        ^^^^^^^^^^^^^^^^ invocation\n  ╵",
    );
    // Both crossing lines: two arms, one after the other.
    assert.equal(
        run("@mixin m(\n  $x: 1\n) { a: $x; }\n.a { @include m(\n  1, 2\n); }\n"),
        "Error: Only 1 argument allowed, but 2 were passed.\n  ╷\n"
            + "1 │   @mixin m(\n  │ ┌────────^\n"
            + "2 │ │   $x: 1\n"
            + "3 │ │ ) { a: $x; }\n  │ └─^ declaration\n"
            + "4 │   .a { @include m(\n  │ ┌──────^\n"
            + "5 │ │   1, 2\n"
            + "6 │ │ ); }\n  │ └─^ invocation\n  ╵",
    );
    // An elision and an arm at once: the gutter widens and left-aligns, and the
    // `...` row carries no arm.
    assert.equal(
        run("@mixin m($x) { a: $x; }\n// pad\n// pad\n.a { @include m(\n); }\n"),
        "Error: Missing argument $x.\n    ╷\n"
            + "1   │   @mixin m($x) { a: $x; }\n    │          ━━━━━ declaration\n"
            + "... │\n"
            + "4   │   .a { @include m(\n    │ ┌──────^\n"
            + "5   │ │ ); }\n    │ └─^ invocation\n    ╵",
    )
}

test "a_first_class_mixin_reference_carries_the_declaration_too" {
    // `@include meta.apply(…)` reaches the same binding code by another road,
    // and dart gives it the same two spans: the whole `meta.apply` call as the
    // invocation (its content block excluded), the mixin as the declaration.
    let run = (src: string) -> string {
        compile_expect_err(src, root.Options.default().with_url("t.scss"), "expected a compile error")
            .to_string()
    };
    let block = run(
        "@use \"sass:meta\";\n@mixin m { a: 1; }\n.a { @include meta.apply(meta.get-mixin(\"m\")) { b: 2; } }\n",
    );
    assert.equal(
        snippet(block),
        "Error: Mixin doesn't accept a content block.\n  ╷\n"
            + "2 │ @mixin m { a: 1; }\n  │        ━ declaration\n"
            + "3 │ .a { @include meta.apply(meta.get-mixin(\"m\")) { b: 2; } }\n  │      "
            + "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ invocation\n  ╵",
    );
    // The mixin is never entered, so the trace starts at the caller.
    // {block}
    assert.is_true(!block.includes("  m()"));
    // The argument-binding errors carry it as well.
    for (
        let c in [
            root.std.Tuple2<string, string> {
                _0: "@use \"sass:meta\";\n@mixin m($x) { a: $x; }\n.a { @include meta.apply(meta.get-mixin(\"m\")); }\n",
                _1: "Missing argument $x.",
            },
            root.std.Tuple2<string, string> {
                _0: "@use \"sass:meta\";\n@mixin m() { a: 1; }\n.a { @include meta.apply(meta.get-mixin(\"m\"), 1); }\n",
                _1: "Only 0 arguments allowed, but 1 was passed.",
            },
            root.std.Tuple2<string, string> {
                _0: "@use \"sass:meta\";\n@mixin m($x: 1) { a: $x; }\n.a { @include meta.apply(meta.get-mixin(\"m\"), $z: 1); }\n",
                _1: "No parameter named $z.",
            },
        ]
    ) {
        let src = c._0;
        let message = c._1;
        let block = run(src);
        // {block}
        assert.is_true(block.starts_with(`Error: ${message}\n`));
        // {block}
        assert.is_true(block.includes(" declaration\n"));
        // {block}
        assert.is_true(caret_line(block).ends_with(" invocation"));
    }
}

test "two_spans_on_one_line_stack_their_rows" {
    // A stylesheet written on ONE line puts the call and the declaration it was
    // measured against on that same line. dart prints the line once and stacks
    // the underlines, the primary first — wherever the two sit relative to each
    // other. Both blocks are dart-sass 1.103.1's.
    let run = (src: string) -> string {
        snippet(
            compile_expect_err(src, root.Options.default().with_url("t.scss"), "expected a compile error")
                .to_string(),
        )
    };
    assert.equal(
        run("@function f($x) { @return 1; } .a { b: f(1, 2); }\n"),
        "Error: Only 1 argument allowed, but 2 were passed.\n  ╷\n1 │ "
            + "@function f($x) { @return 1; } .a { b: f(1, 2); }\n  │                                        "
            + "^^^^^^^ invocation\n  │           "
            + "━━━━━ declaration\n  ╵",
    );
    // The declaration can come AFTER the call on that line; the primary row is
    // still written first.
    assert.equal(
        run("@mixin caller { @include m; } @mixin m($x) { a: $x; } .a { @include caller; }\n"),
        "Error: Missing argument $x.\n  ╷\n1 │ "
            + "@mixin caller { @include m; } @mixin m($x) { a: $x; } .a { @include caller; }\n  │                 "
            + "^^^^^^^^^^ invocation\n  │                                      "
            + "━━━━━ declaration\n  ╵",
    )
}

test "a_span_inside_an_arms_range_writes_its_row_under_its_own_line" {
    // A span that stays within its line can sit INSIDE the lines another span's
    // arm covers. dart writes its row under its own line — before the arm's own
    // rows — with the arm running down the column beside it. Both blocks are
    // dart-sass 1.103.1's.
    let run = (src: string) -> string {
        snippet(
            compile_expect_err(src, root.Options.default().with_url("t.scss"), "expected a compile error")
                .to_string(),
        )
    };
    // The call on the arm's LAST line: its row comes first, then the row that
    // closes the arm and carries `declaration`.
    assert.equal(
        run("@mixin m(\n  $x: 1\n) { a: $x; } .b { @include m { c: 1; } }\n"),
        "Error: Mixin doesn't accept a content block.\n  ╷\n"
            + "1 │   @mixin m(\n  │ ┌────────^\n"
            + "2 │ │   $x: 1\n"
            + "3 │ │ ) { a: $x; } .b { @include m { c: 1; } }\n  │ │                   "
            + "^^^^^^^^^^ invocation\n  │ └─^ declaration\n  ╵",
    );
    // On the arm's FIRST line the arm has not reached in yet — the `,-…-^` row
    // comes after this one — so the column beside it is still blank.
    assert.equal(
        run(
            "@mixin caller { @include m { c: 1; } } @mixin m(\n  $x: 1\n) { a: $x; }\n.b { @include caller; }\n",
        ),
        "Error: Mixin doesn't accept a content block.\n  ╷\n"
            + "1 │   @mixin caller { @include m { c: 1; } } @mixin m(\n  │                   "
            + "^^^^^^^^^^ invocation\n  │ ┌"
            + "───────────────────────────────────────────────^\n"
            + "2 │ │   $x: 1\n"
            + "3 │ │ ) { a: $x; }\n  │ └─^ declaration\n  ╵",
    )
}

/// `grayscale(1, 2)` is an arity error, and dart raises ONLY that — no
/// `global-builtin` warning ahead of it.
///
/// Not a byte-exact fixture: dart renders this one as a two-span error
/// (the invocation, plus the declaration inside `sass:color`), which this
/// renderer cannot draw yet. The captured dart output is checked in beside the
/// input for reference; what is asserted here is the narrower property the
/// #122 fix turns on.
///
/// It is asserted because the review of #122 proposed requiring one argument
/// in `is_plain_css_filter_call`, and doing so makes this call miss the
/// plain-CSS branch, be deprecated as a global built-in, and print a warning
/// dart never prints. Measured, not assumed.
test "an_arity_error_on_a_css_filter_does_not_also_deprecate" {
    let stderr = run_sasso_stderr("deprecation-global-builtin-filter-arity");
    // `DEPRECATION WARNING`, not `global-builtin`: the fixture's own FILENAME
    // contains that id and appears in the stack trace, so the obvious
    // assertion passes for the wrong reason — it failed here first.
    // grayscale(1, 2) must report its arity error alone, got:\n{stderr}
    assert.is_true(!stderr.includes("DEPRECATION WARNING"));
    // …and it must still be an error, got:\n{stderr}
    assert.is_true(stderr.includes("Error:"))
}

/// A registered host function is the implementation sasso selects, so a call
/// to it is not the plain-CSS filter overload and must still be deprecated.
///
/// The #122 suppression runs before host dispatch, which is exactly where it
/// could go wrong: `grayscale(1)` looks like the CSS filter right up until you
/// notice a callback is registered under that name and is what actually runs.
/// `with_function`'s contract (src/lib.rs) is that writing a deprecated
/// global's name warns whether or not a custom function of that name exists —
/// the callback taking precedence is sasso's deliberate divergence from dart,
/// and the warning is not part of that divergence.
///
/// The sibling test above covers the same contract for a name with no CSS
/// overload (`type-of`); this one covers a name that has one.
test "a_host_override_of_a_filter_name_still_warns" {
    let called: root.std.Cell<bool> = root.std.Cell<bool> { value: false };
    let flag = called;
    // PORT: `Ok(Vec::new())` → an empty `uint8array`.
    let cb: root.host_fn.HostFunction = (_args: uint8array) -> uint8array {
        flag.set(true);
        baml.Uint8Array.zeroes(0)
    };
    let seen: string[] = [];
    let sink = seen;
    let opts = root.Options.default().with_url("in.scss").with_function("grayscale($x)", cb).with_warn_handler((
        ev: root.WarnEvent,
    ) -> void {
        sink.push(ev.formatted);
    });
    let _ = root.compile(".a { filter: grayscale(1); }\n", opts) catch (e) {
        let _e: root.error.Error => ""
    };
    let w = root.std.clone_vec(seen);
    // the registered callback is the implementation that runs
    assert.is_true(called.get());
    // the deprecated global name still warns: {w:?}
    assert.equal(w.length(), 1);
    // {}: w[0]
    assert.is_true(w[0].includes("global-builtin"))
}

/// PORT: `cfg!(windows)` — the port runs on a macOS/Linux host.
function cfg_windows() -> bool {
    false
}

/// A frame path spelled the way the platform spells it.
///
/// dart writes every frame with the PLATFORM's separator, the entry's
/// included (#151), and so do we — so `src/main.scss` is the right answer on
/// POSIX and `src\main.scss` on Windows. Four tests here hard-coded the
/// POSIX one and passed everywhere except the platform half of this rule
/// exists for.
function frame_path(rel: string) -> string {
    if (cfg_windows()) {
        rel.replace_all("/", "\\")
    } else {
        rel
    }
}

/// A frame names a file the same way whichever spelling the host handed over.
///
/// The binary passes a path and the JS API passes a `file://` URL — it has to,
/// because its importer bridge resolves relative `@use` against the entry URL —
/// and for three releases the URL went straight into the frame, scheme and all
/// (#153). The two front ends printed different things for the same error, and
/// `file:///Users/…/src/a.scss` is neither pasteable into an editor nor
/// meaningful on anyone else's machine.
///
/// `cwd` is passed explicitly rather than leaning on the process's: this is
/// what the JS bridges do, because `wasm32-unknown-unknown` has no `getcwd` and
/// nothing to relativise against otherwise.
test "a_frame_names_a_file_the_same_way_from_either_front_end" {
    let cwd = if (cfg_windows()) {
        "C:\\work\\proj"
    } else {
        "/work/proj"
    };
    let as_url = "file:///work/proj/src/a.scss";
    let as_path = if (cfg_windows()) {
        "C:\\work\\proj\\src\\a.scss"
    } else {
        "/work/proj/src/a.scss"
    };
    let expected = if (cfg_windows()) {
        "src\\a.scss 1:8"
    } else {
        "src/a.scss 1:8"
    };

    // On Windows the URL names the C: drive, so both spellings are the same
    // file and the comparison is the point of the test.
    let url = if (cfg_windows()) {
        "file:///C:/work/proj/src/a.scss"
    } else {
        as_url
    };

    let from_url = compile_unwrap_err("a { b: $x }", root.Options.new().with_url(url).with_cwd(cwd));
    let from_path = compile_unwrap_err("a { b: $x }", root.Options.new().with_url(as_path).with_cwd(cwd));

    // `Display` prints the rendered block when there is one.
    let rendered = (e: root.error.Error) -> string {
        e.to_string()
    };
    // a file:// url should name a path: {}: rendered(&from_url)
    assert.is_true(rendered(from_url).includes(expected));
    // the two front ends' spellings must render identically
    assert.equal(rendered(from_url), rendered(from_path));
    // no frame should show a scheme: {}: rendered(&from_url)
    assert.is_true(!rendered(from_url).includes("file://"))
}

/// Without a `cwd` the host knows of, a frame still shows a PATH — just not a
/// relative one. That is the wasm case before the bridges were taught to pass
/// one, and it must degrade to "absolute" rather than back to a URL.
test "a_file_url_without_a_cwd_degrades_to_an_absolute_path" {
    let e = compile_unwrap_err("a { b: $x }", root.Options.new().with_url("file:///nowhere/deep/a.scss"));
    let rendered = e.to_string();
    // still a URL: {rendered}
    assert.is_true(!rendered.includes("file://"));
    let expected = if (cfg_windows()) {
        "\\nowhere\\deep\\a.scss"
    } else {
        "/nowhere/deep/a.scss"
    };
    // not the path: {rendered}
    assert.is_true(rendered.includes(expected))
}

/// A custom importer's key is not a filesystem path and is not ours to
/// rewrite: dart shows it as it is.
test "a_non_file_url_keeps_its_own_spelling" {
    let e = compile_unwrap_err("a { b: $x }", root.Options.new().with_url("data:;charset=utf-8,a").with_cwd("/work"));
    let rendered = e.to_string();
    // {rendered}
    assert.is_true(rendered.includes("data:;charset=utf-8,a 1:8"))
}

/// `struct Virtual` of `a_custom_importers_relative_key_shows_its_last_segment`
/// (a type local to the test fn, hoisted as `<outer>__<inner>`).
class a_custom_importers_relative_key_shows_its_last_segment__Virtual {
    implements root.importer.Importer {
        function canonicalize(
            self,
            url: string,
            ctx: root.importer.CanonicalizeContext,
        ) -> root.importer.CanonicalUrl? {
            root.importer.CanonicalUrl.new(`virtual/${url}.scss`)
        }

        function load(
            self,
            canonical: root.importer.CanonicalUrl,
        ) -> root.importer.ImporterResult? {
            root.importer.ImporterResult {
                contents: "@mixin m {\n  a: $nope;\n}\n",
                syntax: root.Syntax.Scss,
                source_map_url: null,
            }
        }
    }
}

/// A custom importer's canonical key is its own identity, not a path. dart
/// shows its last segment, and so did this — until the frame-naming rule was
/// applied to every key rather than to the ones that name a file.
///
/// A RELATIVE key is the case that slipped through: `virtual/foo.scss` has no
/// scheme to decline it by and no root to relativise, so handing it back
/// whole looked like a no-op and was a changed frame.
test "a_custom_importers_relative_key_shows_its_last_segment" {
    let importer = a_custom_importers_relative_key_shows_its_last_segment__Virtual {  };
    let opts = root.Options.new()
        .with_url("file:///work/proj/src/main.scss")
        .with_cwd("/work/proj")
        .with_importer(importer);
    let e = compile_unwrap_err("@use \"foo\";\n.a { @include foo.m; }\n", opts);
    let rendered = e.to_string();
    // the key's last segment, as dart shows it: {rendered}
    assert.is_true(rendered.includes(frame_path("foo.scss 2:6")));
    // the whole key is not a frame name: {rendered}
    assert.is_true(!rendered.includes(frame_path("virtual/foo.scss")));
    // …and the entry is still relativised beside it.
    // {rendered}
    assert.is_true(rendered.includes(frame_path("src/main.scss")))
}

/// The "error in interpolated output" block prints the file in a header of
/// its OWN, so it is a second place a frame becomes text. Left out of the
/// rule, one message contradicted itself: a `file://` URL in the header above
/// the path in the trace below.
test "the_interpolated_output_header_names_the_file_like_the_trace" {
    let opts = root.Options.new().with_url("file:///work/proj/src/main.scss").with_cwd("/work/proj");
    let e = compile_unwrap_err("$x: \"y@z\";\n.a#{$x} { c: d; }\n", opts);
    let rendered = e.to_string();
    // not the dual-span block: {rendered}
    assert.is_true(rendered.includes("error in interpolated output"));
    // a URL survived: {rendered}
    assert.is_true(!rendered.includes("file://"));
    // the header and the trace should both name it: {rendered}
    assert.equal(count_matches(rendered, frame_path("src/main.scss")), 2)
}

/// The Windows rule, exercised from whatever host runs this.
///
/// The wasm module is built for `wasm32-unknown-unknown`, so the compile-time
/// host style is POSIX in it no matter where node is running — and on Windows
/// node it is handed `C:\work\proj` and `file:///C:/work/proj/…`. Reading
/// those by POSIX rules leaves `/C:/work/proj/src/main.scss` in the frame:
/// not the path, and not what the addon on the same machine prints.
///
/// Nothing on a POSIX developer machine can reach that through the CLI, which
/// is exactly the blind spot `pathstyle` exists for (#146). Here the
/// Windows spelling is handed to the compiler directly, so the rule is
/// checked wherever this test runs.
test "a_windows_spelling_is_read_by_windows_rules_on_any_host" {
    let opts = root.Options.new().with_url("file:///C:/work/proj/src/main.scss").with_cwd("C:\\work\\proj");
    let e = compile_unwrap_err("a { b: $x }", opts);
    let rendered = e.to_string();
    // a Windows cwd and a Windows file URL should give a Windows path: {rendered}
    assert.is_true(rendered.includes("src\\main.scss 1:8"));
    // read as a POSIX path: {rendered}
    assert.is_true(!rendered.includes("/C:/"));
    // a URL survived: {rendered}
    assert.is_true(!rendered.includes("file://"))
}

/// `struct Dep` of `a_labelled_snippets_headers_name_files_like_the_trace`
/// (a type local to the test fn, hoisted as `<outer>__<inner>`).
class a_labelled_snippets_headers_name_files_like_the_trace__Dep {
    implements root.importer.Importer {
        function canonicalize(
            self,
            url: string,
            ctx: root.importer.CanonicalizeContext,
        ) -> root.importer.CanonicalUrl? {
            root.importer.CanonicalUrl.new("file:///work/proj/src/_dep.scss")
        }

        function load(
            self,
            canonical: root.importer.CanonicalUrl,
        ) -> root.importer.ImporterResult? {
            root.importer.ImporterResult {
                contents: "@mixin m($a) {\n  width: $a;\n}\n",
                syntax: root.Syntax.Scss,
                source_map_url: null,
            }
        }
    }
}

/// A cross-file `invocation`/`declaration` error draws one header PER FILE,
/// through a third snippet function. Left out of the rule, a single message
/// named the same kind of thing three ways: a URL in the first header, a path
/// in the second, and paths in the trace.
test "a_labelled_snippets_headers_name_files_like_the_trace" {
    let importer = a_labelled_snippets_headers_name_files_like_the_trace__Dep {  };
    let opts = root.Options.new()
        .with_url("file:///work/proj/src/main.scss")
        .with_cwd("/work/proj")
        .with_importer(importer);
    let e = compile_unwrap_err("@use \"dep\";\n.a { @include dep.m(1, 2); }\n", opts);
    let rendered = e.to_string();
    // not the labelled block: {rendered}
    assert.is_true(rendered.includes("invocation") && rendered.includes("declaration"));
    // a URL survived: {rendered}
    assert.is_true(!rendered.includes("file://"));
    // {rendered}
    assert.is_true(rendered.includes(frame_path("src/main.scss")));
    // {rendered}
    assert.is_true(rendered.includes(frame_path("src/_dep.scss")))
}

/// `struct Dep` of `the_pre_entry_declaration_block_names_files_like_the_trace`
/// (a type local to the test fn, hoisted as `<outer>__<inner>`).
class the_pre_entry_declaration_block_names_files_like_the_trace__Dep {
    implements root.importer.Importer {
        function canonicalize(
            self,
            url: string,
            ctx: root.importer.CanonicalizeContext,
        ) -> root.importer.CanonicalUrl? {
            root.importer.CanonicalUrl.new("file:///work/proj/src/_dep.scss")
        }

        function load(
            self,
            canonical: root.importer.CanonicalUrl,
        ) -> root.importer.ImporterResult? {
            root.importer.ImporterResult {
                contents: "@mixin plain {\n  width: 1px;\n}\n",
                syntax: root.Syntax.Scss,
                source_map_url: null,
            }
        }
    }
}

/// The same block, reached through the OTHER of the two call sites.
///
/// `error_with_declaration_at` renders before the callable is entered — a
/// content block handed to a mixin that has no `@content` — so it builds its
/// own two-span block rather than going through `error_at_call`. One test
/// could not cover both: reverting only this site left the first case green.
test "the_pre_entry_declaration_block_names_files_like_the_trace" {
    let importer = the_pre_entry_declaration_block_names_files_like_the_trace__Dep {  };
    let opts = root.Options.new()
        .with_url("file:///work/proj/src/main.scss")
        .with_cwd("/work/proj")
        .with_importer(importer);
    let e = compile_unwrap_err("@use \"dep\";\n.a { @include dep.plain { color: red; } }\n", opts);
    let rendered = e.to_string();
    // not the pre-entry two-span block: {rendered}
    assert.is_true(rendered.includes("content block") && rendered.includes("declaration"));
    // a URL survived: {rendered}
    assert.is_true(!rendered.includes("file://"));
    // {rendered}
    assert.is_true(rendered.includes(frame_path("src/main.scss")));
    // {rendered}
    assert.is_true(rendered.includes(frame_path("src/_dep.scss")))
}

/// Both spans in the ENTRY file, where the declaration has no module of its
/// own and falls back to the frame's url — the raw one the host passed.
///
/// `render_labelled_snippet` groups by `(url, source)`, so naming the primary
/// group and not the secondary splits one file into two groups and prints its
/// header twice. The rule has to reach both sides of the pair or neither.
test "one_file_gets_one_header_when_both_spans_are_the_entrys" {
    let opts = root.Options.new().with_url("file:///work/proj/src/main.scss").with_cwd("/work/proj");
    let e = compile_unwrap_err("@mixin plain {\n  width: 1px;\n}\n.a { @include plain { color: red; } }\n", opts);
    let rendered = e.to_string();
    // not the expected error: {rendered}
    assert.is_true(rendered.includes("content block"));
    // a URL survived: {rendered}
    assert.is_true(!rendered.includes("file://"));
    // One file, one header. The frame trace names it too, so count headers
    // rather than mentions.
    let headers = count_matches(rendered, "┌──>") + count_matches(rendered, ",-->");
    // one file should get one header, got {headers}: {rendered}
    assert.is_true(headers <= 1)
}
