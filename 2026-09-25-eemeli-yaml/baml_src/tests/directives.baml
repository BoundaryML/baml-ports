// Port of tests/directives.ts

function tdir_scalar(item: SeqItem?) -> Scalar {
  match (item) {
    let s: Scalar => s,
    _ => fail("expected a Scalar"),
  }
}

// NOTE: BAML backtick literals are already dedented and have their leading and
// trailing newline trimmed, so `source(`…`)` lacks the trailing "\n" that the
// upstream template tag keeps; it is appended explicitly where it matters.

testset "directives" {
  testset "%TAG" {
    test "parse local tags" {
      let doc = parseDocument(source(`
        %TAG ! !foo:
        %TAG !bar! !bar:
        ---
        - !bar v1
        - !bar!foo v2
      `), null);
      expect_toHaveLength(doc.errors, 0);
      expect_toMatchObject(doc.directives?.tags, {
        "!!": "tag:yaml.org,2002:",
        "!": "!foo:",
        "!bar!": "!bar:",
      });
      expect_toMatchObject(doc.value, [
        { "value": "v1", "tag": "!foo:bar" },
        { "value": "v2", "tag": "!bar:foo" },
      ])
    }

    test "parse global tags" {
      let doc = parseDocument(source(`
        %TAG ! foo:
        %TAG !bar! bar:bar#bar? #comment
        ---
        - !bar v1
        - !bar!foo v2
      `), null);
      expect_toHaveLength(doc.errors, 0);
      expect_toMatchObject(doc.directives?.tags, {
        "!!": "tag:yaml.org,2002:",
        "!": "foo:",
        "!bar!": "bar:bar#bar?",
      });
      expect_toMatchObject(doc.value, [
        { "value": "v1", "tag": "foo:bar" },
        { "value": "v2", "tag": "bar:bar#bar?foo" },
      ])
    }

    test "create & stringify" {
      let doc = parseDocument("[ v1, v2 ]\n", null);
      tdir_scalar(doc.get(0)).tag = "!foo:foo";
      tdir_scalar(doc.get(1)).tag = "!bar:bar";
      let tags = doc.directives?.tags ?? {};
      tags["!"] = "!foo:";
      tags["!bar!"] = "!bar:";
      expect_toBe(doc.toString(null), source(`
        %TAG ! !foo:
        %TAG !bar! !bar:
        ---
        [ !foo v1, !bar!bar v2 ]
      `) + "\n")
    }
  }

  testset "broken directives" {
    // for (const tag of ['%TAG', '%YAML']) test(`incomplete ${tag} directive`, …)
    test "incomplete %TAG directive" {
      let tag = "%TAG";
      let doc = parseDocument(tag + "\n---\n", null);
      expect_toMatchObject(doc.errors, [{ "pos": [0, tag.length()] }])
    }

    test "incomplete %YAML directive" {
      let tag = "%YAML";
      let doc = parseDocument(tag + "\n---\n", null);
      expect_toMatchObject(doc.errors, [{ "pos": [0, tag.length()] }])
    }

    test "missing separator at end of stream" {
      let doc = parseDocument("%YAML 1.2\n", null);
      expect_toMatchObject(doc.errors, [{ "pos": [10, 11] }])
    }

    test "missing separator before doc value" {
      let doc = parseDocument("%YAML 1.2\nfoo\n", null);
      expect_toMatchObject(doc.errors, [{ "pos": [10, 11] }])
    }

    test "lone %" {
      let doc = parseDocument("%", null);
      expect_toMatchObject(doc, {
        "errors": [{ "code": "MISSING_CHAR", "pos": [1, 2] }],
        "warnings": [{ "code": "BAD_DIRECTIVE", "pos": [0, 1] }],
      })
    }
  }
}
