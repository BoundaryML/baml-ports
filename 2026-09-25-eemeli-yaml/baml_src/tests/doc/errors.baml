// Port of tests/doc/errors.ts

/// `expect(errors).toMatchObject(msgs.map(msg => ({ message: expect.stringContaining(msg) })))`
function terr_messages_contain(errors: YAMLError[], msgs: string[]) -> null {
  if (errors.length() != msgs.length()) {
    fail("expected " + msgs.length().to_string() + " errors, got " + t_show(errors));
  }
  let i = 0;
  while (i < msgs.length()) {
    if (!errors[i].message.includes(msgs[i])) {
      fail("expected error message " + json_quote(errors[i].message) + " to contain " + json_quote(msgs[i]));
    }
    i += 1;
  }
  null
}

/// `expect(str).toMatch(string)`: substring match
function terr_toMatch(actual: string, expected: string) -> null {
  if (!actual.includes(expected)) {
    fail("expected " + json_quote(actual) + " to include " + json_quote(expected));
  }
  null
}

function terr_long_comment_line() -> string {
  "  # large block of text, large block of text, large block of text, large block of text, large block of text,\n"
}

testset "doc/errors" {
  testset "tabs as indentation" {
    test "fail on map value indented with tab" {
      let src = "a:\n\t1\nb:\n\t2\n";
      let doc = parseDocument(src, null);
      expect_toMatchObject(doc.errors[0], { "code": "TAB_AS_INDENT" })
    }

    test "block sequence with leading tab" {
      let doc = parseDocument("\t- x", null);
      expect_toMatchObject(doc.errors, [{ "code": "TAB_AS_INDENT" }])
    }

    test "block map with leading tab" {
      let doc = parseDocument("\tx: y", null);
      expect_toMatchObject(doc.errors, [{ "code": "TAB_AS_INDENT" }])
    }
  }

  test "end with missing block map : indicator (#6)" {
    let src = "abc: 123\ndef";
    let doc = parseDocument(src, null);
    expect_toMatchObject(doc.errors, [{ "pos": [9, 12] }])
  }

  testset "multiple trailing commas (#7)" {
    test "map" {
      let src = "{ , }\n---\n{ 123,,, }\n";
      let docs = parseAllDocuments(src, null).docs;
      expect_toMatchObject(docs[0].errors, [{ "pos": [2, 3] }]);
      expect_toMatchObject(docs[1].errors, [{ "pos": [16, 17] }, { "pos": [17, 18] }])
    }

    test "seq" {
      let src = "[ , ]\n---\n[ 123,,, ]\n";
      let docs = parseAllDocuments(src, null).docs;
      expect_toMatchObject(docs[0].errors, [{ "pos": [2, 3] }]);
      expect_toMatchObject(docs[1].errors, [{ "pos": [16, 17] }, { "pos": [17, 18] }])
    }
  }

  testset "block scalars" {
    test "invalid header" {
      let doc = parseDocument(">99\n foo\n", null);
      terr_messages_contain(doc.errors, [
        "Block scalar header includes extra characters: >99",
        "Unexpected scalar at node end"
      ])
    }
    test "missing newline at header end" {
      let doc = parseDocument("> foo\n", null);
      expect_toHaveLength(doc.errors, 1);
      terr_toMatch(doc.errors[0].message, "Not a YAML token: foo")
    }
  }

  testset "flow scalars" {
    test "invalid hex escapes" {
      let doc = parseDocument("\"\\x0\"", null);
      expect_toMatchObject(doc.errors, [{ "code": "BAD_DQ_ESCAPE" }])
    }

    test "invalid unicode escapes" {
      let doc = parseDocument("\"\\U00110000\"", null);
      expect_toMatchObject(doc.errors, [{ "code": "BAD_DQ_ESCAPE" }])
    }
  }

  testset "block collections" {
    test "mapping with bad indentation" {
      let src = "foo: \"1\"\n bar: 2\n";
      let doc = parseDocument(src, null);
      expect_toHaveLength(doc.errors, 1);
      terr_toMatch(doc.errors[0].message, "All mapping items must start at the same column");
      expect_toMatchObject(doc.value, _map({ "foo": "1", "bar": 2 }, null))
    }

    test "sequence with bad indentation" {
      let src = "- \"foo\"\n - bar\n";
      let doc = parseDocument(src, null);
      expect_toHaveLength(doc.errors, 1);
      terr_toMatch(doc.errors[0].message, "All sequence items must start at the same column");
      expect_toMatchObject(doc.value, _seq(["foo", _seq(["bar"])]))
    }

    test "seq item in mapping" {
      let src = "foo: \"1\"\n- bar\n";
      let doc = parseDocument(src, null);
      expect_toMatchObject(doc.errors, [
        { "code": "MULTILINE_IMPLICIT_KEY" },
        { "code": "UNEXPECTED_TOKEN" },
        { "code": "MISSING_CHAR" }
      ]);
      let nullEntry: unknown[] = [null, { "key": { "value": null }, "value": null }];
      let fooEntry: unknown[] = ["foo", "1"];
      let entries: unknown[] = [fooEntry, nullEntry];
      expect_toMatchObject(doc.value, _map(entries, null))
    }

    test "doubled value indicator" {
      let doc = parseDocument("foo : : bar\n", null);
      expect_toMatchObject(doc.errors, [
        {
          "message": source(`
            Nested mappings are not allowed in compact mappings at line 1, column 7:

            foo : : bar
                  ^
          `) + "\n"
        }
      ])
    }

    test "excessively long key" {
      let doc = parseDocument("foo " + "x".repeat(1024) + " : bar\n", null);
      expect_toMatchObject(doc.errors, [
        {
          "message": source(`
            The : indicator must be at most 1024 chars after the start of an implicit block mapping key at line 1, column 1:

            foo xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx…
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
          `) + "\n"
        }
      ])
    }

    test "key after long comment on empty value (#413)" {
      let doc = parseDocument("one:\n" + terr_long_comment_line().repeat(10) + "two: b\n", null);
      expect_toMatchObject(doc.errors, [])
    }

    test "key after long comment on block map (#413)" {
      let doc = parseDocument("one:\n  sub: a\n" + terr_long_comment_line().repeat(10) + "two: b\n", null);
      expect_toMatchObject(doc.errors, [])
    }

    test "key after long comment on block seq (#413)" {
      let doc = parseDocument("one:\n  - a\n" + terr_long_comment_line().repeat(10) + "two: b\n", null);
      expect_toMatchObject(doc.errors, [])
    }

    test "sequence with compact mapping value on same line with mapping key (#603)" {
      let doc = parseDocument("abc: - foo: bar", null);
      expect_toMatchObject(doc.errors, [{ "code": "UNEXPECTED_TOKEN" }])
    }
  }

  testset "flow collections" {
    test "start only of flow map (#8)" {
      let doc = parseDocument("{", null);
      expect_toMatchObject(doc.errors, [{ "code": "MISSING_CHAR", "pos": [1, 2] }])
    }

    test "start only of flow sequence (#8)" {
      let doc = parseDocument("[", null);
      expect_toMatchObject(doc.errors, [{ "code": "MISSING_CHAR", "pos": [1, 2] }])
    }

    test "flow sequence without end" {
      let doc = parseDocument("[ foo, bar,", null);
      expect_toMatchObject(doc.errors, [{ "code": "MISSING_CHAR", "pos": [11, 12] }])
    }

    test "doc-end within flow sequence" {
      let doc = parseDocument("[ foo, bar,\n...\n]", Options { prettyErrors: false });
      expect_toMatchObject(doc.errors, [
        { "code": "MISSING_CHAR" },
        { "message": "Unexpected flow-seq-end token in YAML document: \"]\"" },
        {
          "message": "Source contains multiple documents; please use YAML.parseAllDocuments()"
        }
      ])
    }

    test "block scalar in flow collection" {
      let doc = parseDocument("{ |\n foo\n}", null);
      expect_toHaveLength(doc.errors, 1);
      terr_toMatch(doc.errors[0].message, "Plain value cannot start with block scalar indicator |")
    }

    test "block seq in flow collection" {
      let doc = parseDocument("{\n- foo\n}", null);
      expect_toMatchObject(doc.errors, [{ "code": "BLOCK_IN_FLOW" }])
    }

    test "anchor before explicit key indicator in block map" {
      let doc = parseDocument("&a ? A", null);
      expect_toMatchObject(doc.errors, [{ "code": "BAD_PROP_ORDER" }])
    }

    test "anchor before explicit key indicator in flow map" {
      let doc = parseDocument("{ &a ? A }", null);
      expect_toMatchObject(doc.errors, [{ "code": "BAD_PROP_ORDER" }])
    }

    test "flow map with doubled indicator" {
      let doc = parseDocument("{ foo: : bar }", null);
      expect_toMatchObject(doc.errors, [{ "code": "UNEXPECTED_TOKEN" }])
    }
  }

  testset "comments" {
    test "comment without whitespace after tag" {
      let doc = parseDocument("!<a>#cc\nA", null);
      expect_toHaveLength(doc.errors, 2);
      terr_toMatch(doc.errors[0].message, "Tags and anchors must be separated from the next token by white space");
      terr_toMatch(doc.errors[1].message, "Comments must be separated from other tokens by white space characters")
    }

    test "comment without whitespace after value" {
      let doc = parseDocument("foo: \"bar\"#cc", null);
      expect_toHaveLength(doc.errors, 1);
      terr_toMatch(doc.errors[0].message, "Comments must be separated from other tokens by white space characters")
    }
  }

  testset "pretty errors" {
    test "end with missing block map : indicator (#6)" {
      let src = "abc: 123\ndef";
      let doc = parseDocument(src, Options { prettyErrors: true });
      expect_toMatchObject(doc.errors, [
        {
          "message": source(`
            Implicit map keys need to be followed by map values at line 2, column 1:

            abc: 123
            def
            ^^^
          `) + "\n",
          "pos": [9, 12],
          "linePos": [
            { "line": 2, "col": 1 },
            { "line": 2, "col": 4 }
          ]
        }
      ]);
      expect_not_toHaveProperty(doc.errors[0], "source")
    }

    test "multiple trailing commas in mappings (#7)" {
      let src = "{ , }\n---\n{ 123,,, }\n";
      let docs = parseAllDocuments(src, Options { prettyErrors: true }).docs;
      expect_toMatchObject(docs[0].errors, [
        {
          "message": source(`
            Unexpected , in flow map at line 1, column 3:

            { , }
              ^
          `) + "\n",
          "pos": [2, 3],
          "linePos": [
            { "line": 1, "col": 3 },
            { "line": 1, "col": 4 }
          ]
        }
      ]);
      expect_not_toHaveProperty(docs[0].errors[0], "source");
      expect_toMatchObject(docs[1].errors, [
        {
          "code": "UNEXPECTED_TOKEN",
          "message": source(`
            Unexpected , in flow map at line 3, column 7:

            { 123,,, }
                  ^
          `) + "\n",
          "pos": [16, 17],
          "linePos": [
            { "line": 3, "col": 7 },
            { "line": 3, "col": 8 }
          ]
        },
        {
          "code": "UNEXPECTED_TOKEN",
          "message": source(`
            Unexpected , in flow map at line 3, column 8:

            { 123,,, }
                   ^
          `) + "\n",
          "pos": [17, 18],
          "linePos": [
            { "line": 3, "col": 8 },
            { "line": 3, "col": 9 }
          ]
        }
      ]);
      expect_not_toHaveProperty(docs[1].errors[0], "source");
      expect_not_toHaveProperty(docs[1].errors[1], "source")
    }

    test "pretty warnings" {
      let src = "%FOO\n---bar\n";
      let doc = parseDocument(src, Options { prettyErrors: true });
      expect_toMatchObject(doc.warnings, [{ "name": "YAMLWarning" }])
    }

    test "repeated CR" {
      let src = "[" + "\r".repeat(80);
      let doc = parseDocument(src, Options { prettyErrors: true });
      expect_not_toHaveProperty(doc.errors[0], "source")
    }
  }

  testset "tags on invalid nodes" {
    test "!!map on scalar" {
      let doc = parseDocument("!!map foo", null);
      expect_toHaveLength(doc.warnings, 1);
      terr_toMatch(doc.warnings[0].message, "Unresolved tag: tag:yaml.org,2002:map");
      expect_toBe(doc.toJS(null), "foo")
    }

    test "!!str on map" {
      let doc = parseDocument("!!str { answer: 42 }", null);
      expect_toHaveLength(doc.warnings, 1);
      terr_toMatch(doc.warnings[0].message, "Unresolved tag: tag:yaml.org,2002:str");
      expect_toMatchObject(doc.toJS(null), { "answer": 42 })
    }
  }

  testset "properties on block sequences without newline after props" {
    test "valid properties with newline" {
      let doc = parseDocument("! &a\n- b", null);
      expect_toMatchObject(doc.errors, [])
    }

    test "properties on sequence without newline" {
      let doc = parseDocument("!\n&a - b", null);
      expect_toMatchObject(doc.errors, [
        { "code": "MISSING_CHAR" },
        { "code": "UNEXPECTED_TOKEN" }
      ])
    }

    test "properties on empty sequence without newline" {
      let doc = parseDocument("&a\n! -", null);
      expect_toMatchObject(doc.errors, [{ "code": "MISSING_CHAR" }])
    }

    test "properties on sequence with newline after item indicator" {
      let doc = parseDocument("!\n&a -\n b", null);
      expect_toMatchObject(doc.errors, [{ "code": "MISSING_CHAR" }])
    }
  }

  testset "invalid options" {
    test "unknown schema" {
      expect_toThrow(() -> unknown { Document.new(null, null, Options { schema: "foo" }) }, "Unknown schema")
    }

    test "unknown custom tag" {
      expect_toThrow(() -> unknown { Document.new(null, null, Options { customTags: ["foo"] }) }, "Unknown custom tag")
    }
  }

  test "broken document with comment before first node" {
    let doc = parseDocument("#c\n*x\nfoo\n", Options { prettyErrors: false });
    expect_toMatchObject(doc.errors, [
      { "message": "Unexpected scalar at node end" }
    ])
  }

  test "multiple tags on one node" {
    let doc = parseDocument("!foo !bar baz\n", null);
    expect_toMatchObject(doc.value, { "value": "baz", "type": "PLAIN" });
    expect_toHaveLength(doc.errors, 1);
    expect_toHaveLength(doc.warnings, 1)
  }

  testset "logLevel" {
    test "by default, warn for tag fallback" {
      // UNPORTABLE: spies on `process.emitWarning` (vi.spyOn). The port's
      // `warn()` (src/log.baml) writes straight to stderr and there is no
      // way to intercept it from BAML (no global mutable state / monkey
      // patching). Only checks that the parse itself succeeds.
      expect_toBe(yaml_parse("!foo bar"), "bar")
    }

    test "silence warnings with logLevel: 'error'" {
      // UNPORTABLE: asserts that the `process.emitWarning` spy was not
      // called; see above.
      expect_toBe(parse("!foo bar", null, Options { logLevel: "error" }), "bar")
    }

    test "silence warnings with logLevel: 'silent'" {
      // UNPORTABLE: asserts that the `process.emitWarning` spy was not
      // called; see above.
      expect_toBe(parse("!foo bar", null, Options { logLevel: "silent" }), "bar")
    }

    test "silence errors with logLevel: 'silent'" {
      let res = parse("foo: bar: baz\n---\ndoc2\n", null, Options { logLevel: "silent" });
      expect_toMatchObject(res, { "foo": { "bar": "baz" } })
    }
  }

  testset "Invalid plain first characters" {
    test "," {
      let doc = parseDocument("- ,foo", null);
      expect_toMatchObject(doc.errors, [{ "code": "BAD_SCALAR_START" }])
    }
    test "%" {
      let doc = parseDocument("- %foo", null);
      expect_toMatchObject(doc.errors, [{ "code": "BAD_SCALAR_START" }])
    }
    test "@" {
      let doc = parseDocument("- @foo", null);
      expect_toMatchObject(doc.errors, [{ "code": "BAD_SCALAR_START" }])
    }
    test "`" {
      let doc = parseDocument("- `foo", null);
      expect_toMatchObject(doc.errors, [{ "code": "BAD_SCALAR_START" }])
    }
  }
}
