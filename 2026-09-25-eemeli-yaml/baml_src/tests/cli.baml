// Port of tests/cli.ts
//
// Upstream spies on console.log/dir/error and drives `cli(Readable, done,
// argv)`. The BAML `yaml_cli_run(stdin, argv, importVisitor)` returns what
// was written to stdout/stderr and the value passed to `done()` directly, so
// `ok()` / `fail()` below assert on that result instead of on spies. (The
// upstream Node-version guard `describe.skip` for Node < 20 does not apply.)

/// Stand-ins for the `--visit` modules `tests/artifacts/cli-unstyle.cjs` and
/// `tests/artifacts/cli-singlequote.js`: BAML cannot `import()` code at
/// runtime, so the cli takes a loader that maps the path to a visitor.
function tcli_import_visitor(path: string) -> Visitor {
  if (path == "./tests/artifacts/cli-unstyle.cjs") {
    return VisitorFns {
      Collection: (_k: VisitKey, node: YAMLMap | YAMLSeq | YAMLSet, _p: VisitPathItem[]) -> VisitResult {
        // delete node.flow
        match (node) {
          let m: YAMLMap => { m.flow = null; },
          let s: YAMLSeq => { s.flow = null; },
          let s: YAMLSet => { s.flow = null; },
        }
        null
      },
      Scalar: (_k: VisitKey, node: Scalar, _p: VisitPathItem[]) -> VisitResult {
        // delete node.format; delete node.type
        node.format = null;
        node.type = null;
        null
      },
    };
  }
  if (path == "./tests/artifacts/cli-singlequote.js") {
    return VisitorFns {
      Scalar: (_k: VisitKey, node: Scalar, _p: VisitPathItem[]) -> VisitResult {
        node.type = "QUOTE_SINGLE";
        null
      },
    };
  }
  throw js_error("Cannot find module '" + path + "'");
}

function tcli_run(input: string, args: string[]) -> CliResult {
  yaml_cli_run(input, args, tcli_import_visitor)
}

/// `ok(name, input, args, output, errors = [])`
function tcli_ok(input: string, args: string[], output: unknown[], errors: unknown[]) -> null {
  let res = tcli_run(input, args);
  expect_toMatchObject(res.stdout, output);
  expect_toMatchObject(res.stderr, errors);
  // the upstream promise only resolves once done() is called
  expect_true(res.done, "expected done() to be called");
  expect_toBeNull(res.error)
}

/// `fail(name, input, args, errors)`
function tcli_fail(input: string, args: string[], errors: unknown[]) -> null {
  let res = tcli_run(input, args);
  expect_toMatchObject(res.stderr, errors);
  expect_not_toBeNull(res.error)
}

testset "cli" {
  testset "CLI" {
    testset "Bad arguments" {
      test "command" { tcli_fail("42", ["nonesuch"], []) }
      test "option" { tcli_fail("42", ["--nonesuch"], []) }
    }

    testset "Stream processing" {
      test "empty" { tcli_ok("", [], [], []) }
      test "basic" { tcli_ok("hello: world", [], ["hello: world"], []) }
      test "valid ok" { tcli_ok("hello: world", ["valid"], [], []) }
      test "valid fail" { tcli_fail("hello: world: 2", ["valid"], []) }
      test "multiple" {
        tcli_ok("hello: world\n---\n42", [], ["hello: world", "...", "---\n42"], [])
      }
      test "warn" {
        tcli_ok("hello: !foo world", [], ["hello: !foo world"], [{ "name": "YAMLWarning" }])
      }
      test "error" { tcli_fail("hello: world: 2", [], [{ "name": "YAMLParseError" }]) }
      test "--single + empty" { tcli_fail("", ["--single"], []) }
      test "--single + multiple" { tcli_fail("hello: world\n---\n42", ["--single"], []) }

      testset "--json" {
        test "basic" { tcli_ok("hello: world", ["--json"], ["[{\"hello\":\"world\"}]"], []) }
        test "--single" {
          tcli_ok("hello: world", ["--json", "--single"], ["{\"hello\":\"world\"}"], [])
        }
        test "multiple" {
          tcli_ok("hello: world\n---\n42", ["--json"], ["[{\"hello\":\"world\"},42]"], [])
        }
      }

      testset "--indent" {
        test "basic" {
          tcli_ok("hello:\n  world: 2", ["--indent", "3"], ["hello:\n   world: 2"], [])
        }
        test "--json" {
          tcli_ok("hello: world", ["--json", "--indent", "2"], ["[\n  {\n    \"hello\": \"world\"\n  }\n]"], [])
        }
        test "--single" {
          tcli_ok("hello: world", ["--json", "--indent", "2", "--single"], ["{\n  \"hello\": \"world\"\n}"], [])
        }
        test "multiple" {
          tcli_ok("hello: world\n---\n42", ["--json", "--indent", "2"], ["[\n  {\n    \"hello\": \"world\"\n  },\n  42\n]"], [])
        }
        test "Lexer" {
          tcli_ok(
            "hello: world",
            ["lex", "--json", "--indent", "2"],
            ["[\n  \"\\u0002\",\n  \"\\u001f\",\n  \"hello\",\n  \":\",\n  \" \",\n  \"\\u001f\",\n  \"world\"\n]"],
            []
          )
        }
        test "CST parser" {
          let expected: unknown[] = [
            {
              "type": "document",
              "offset": 0,
              "start": [],
              "value": {
                "type": "block-map",
                "offset": 0,
                "indent": 0,
                "items": [
                  {
                    "start": [],
                    "key": { "type": "scalar", "offset": 0, "indent": 0, "source": "hello" },
                    "sep": [
                      { "type": "map-value-ind", "offset": 5, "indent": 0, "source": ":" },
                      { "type": "space", "offset": 6, "indent": 0, "source": " " },
                    ],
                    "value": {
                      "type": "scalar",
                      "offset": 7,
                      "indent": 0,
                      "source": "world",
                      "end": [{ "type": "newline", "offset": 12, "indent": 0, "source": "\n" }],
                    },
                  },
                ],
              },
            },
          ];
          tcli_ok("hello: world\n", ["cst", "--json", "--indent", "2"], [json_stringify_indent(expected, 2.0)], [])
        }
      }

      testset "--merge" {
        test "can be set" {
          tcli_ok("hello:\n  world: 2\nfoo:\n  world: 2", ["--merge", "--json"], ["[{\"hello\":{\"world\":2},\"foo\":{\"world\":2}}]"], [])
        }
        test "basic" {
          tcli_ok("hello: &a\n  world: 2\nfoo:\n  <<: *a", ["--merge", "--json"], ["[{\"hello\":{\"world\":2},\"foo\":{\"world\":2}}]"], [])
        }
        test "also enabled with --yaml=1.1" {
          tcli_ok("hello: &a\n  world: 2\nfoo:\n  <<: *a", ["--yaml=1.1", "--json"], ["[{\"hello\":{\"world\":2},\"foo\":{\"world\":2}}]"], [])
        }
        test "not enabled by default" {
          tcli_ok("hello: &a\n  world: 2\nfoo:\n  <<: *a", ["--json"], ["[{\"hello\":{\"world\":2},\"foo\":{\"<<\":{\"world\":2}}}]"], [])
        }
      }

      testset "--doc" {
        test "basic" {
          tcli_ok("hello: world", ["--doc"], [{ "value": _map({ "hello": "world" }, null) }], [])
        }
        test "multiple" {
          tcli_ok("hello: world\n---\n42", ["--doc"], [{ "value": _map({ "hello": "world" }, null) }, { "value": { "value": 42 } }], [])
        }
        test "error" {
          tcli_ok(
            "hello: world: 2",
            ["--doc"],
            [{ "value": _map({ "hello": _map({ "world": 2 }, null) }, null) }],
            [{ "name": "YAMLParseError" }]
          )
        }
      }

      testset "--visit" {
        // The visitor modules are provided through the cli's injected
        // module loader (tcli_import_visitor), see top of file.
        test "unstyle" {
          tcli_ok("{\"hello\":\"world\"}", ["--visit", "./tests/artifacts/cli-unstyle.cjs"], ["hello: world"], [])
        }
        test "singlequote" {
          tcli_ok("{\"hello\":\"world\"}", ["--visit", "./tests/artifacts/cli-singlequote.js"], ["{ 'hello': 'world' }"], [])
        }
      }
    }

    testset "CST parser" {
      test "basic" { tcli_ok("hello: world", ["cst"], [{ "type": "document" }], []) }
      test "multiple" {
        tcli_ok("hello: world\n---\n42", ["cst"], [{ "type": "document" }, { "type": "document" }], [])
      }
    }

    testset "Lexer" {
      test "basic" {
        tcli_ok("hello: world", ["lex"], ["<DOC>", "<SCALAR>", "\"hello\"", "\":\"", "\" \"", "<SCALAR>", "\"world\""], [])
      }
      test "--json" {
        tcli_ok("hello: world", ["lex", "--json"], ["[\"\\u0002\",\"\\u001f\",\"hello\",\":\",\" \",\"\\u001f\",\"world\"]"], [])
      }
    }
  }
}
