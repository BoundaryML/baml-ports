// Port of tests/compat.ts

function tcmp_xy() -> map<string, unknown> {
  { "x": true, "y": "off" }
}

testset "compat" {
  testset "composer compatibility warnings" {
    test "disabled by default" {
      let doc = parseDocument("x: true\ny: off\n", null);
      expect_toHaveLength(doc.errors, 0);
      expect_toHaveLength(doc.warnings, 0);
      expect_toEqual(doc.toJS(null), { "x": true, "y": "off" });

      doc = parseDocument("x: true\ny: off\n", Options { version: "1.1" });
      expect_toHaveLength(doc.errors, 0);
      expect_toHaveLength(doc.warnings, 0);
      expect_toEqual(doc.toJS(null), { "x": true, "true": false })
    }

    test "schema: 'core', compat: 'yaml-1.1'" {
      let doc = parseDocument("x: true\ny: off\n", Options { compat: "yaml-1.1" });
      expect_toHaveLength(doc.errors, 0);
      expect_toMatchObject(doc.warnings, [
        { "code": "TAG_RESOLVE_FAILED", "pos": [8, 9] },
        { "code": "TAG_RESOLVE_FAILED", "pos": [11, 14] },
      ]);
      expect_toEqual(doc.toJS(null), { "x": true, "y": "off" })
    }

    test "schema: 'yaml-1.1', compat: 'core'" {
      let doc = parseDocument("x: true\ny: off\n", Options { schema: "yaml-1.1", compat: "core" });
      expect_toHaveLength(doc.errors, 0);
      expect_toMatchObject(doc.warnings, [
        { "code": "TAG_RESOLVE_FAILED", "pos": [8, 9] },
        { "code": "TAG_RESOLVE_FAILED", "pos": [11, 14] },
      ]);
      expect_toEqual(doc.toJS(null), { "x": true, "true": false })
    }

    test "single-line flow collection" {
      let doc = parseDocument("foo: { x: 42 }\n", Options { compat: "core" });
      expect_toHaveLength(doc.errors, 0);
      expect_toHaveLength(doc.warnings, 0)
    }

    test "flow collection with end at parent map indent" {
      let doc = parseDocument("x: {\n  y: 42\n}", Options { compat: "core" });
      expect_toHaveLength(doc.errors, 0);
      expect_toMatchObject(doc.warnings, [{ "code": "BAD_INDENT", "pos": [13, 14] }]);

      doc = parseDocument("x:\n {\n  y: 42\n }", Options { compat: "core" });
      expect_toHaveLength(doc.errors, 0);
      expect_toHaveLength(doc.warnings, 0)
    }

    test "flow collection with end at parent seq indent" {
      let doc = parseDocument("- {\n  y: 42\n}", Options { compat: "core" });
      expect_toHaveLength(doc.errors, 0);
      expect_toMatchObject(doc.warnings, [{ "code": "BAD_INDENT", "pos": [12, 13] }]);

      doc = parseDocument("- {\n  y: 42\n }", Options { compat: "core" });
      expect_toHaveLength(doc.errors, 0);
      expect_toHaveLength(doc.warnings, 0)
    }
  }

  testset "stringify compatible values" {
    test "disabled by default" {
      let res = stringify(tcmp_xy(), null, null);
      expect_toBe(res, "x: true\ny: off\n");

      res = stringify(tcmp_xy(), null, Options { version: "1.1" });
      expect_toBe(res, "x: true\n\"y\": \"off\"\n")
    }

    test "schema: 'core', compat: 'yaml-1.1'" {
      let res = stringify(tcmp_xy(), null, Options { compat: "yaml-1.1" });
      expect_toBe(res, "x: true\n\"y\": \"off\"\n")
    }

    test "schema: 'yaml-1.1', compat: 'json'" {
      let res = stringify(tcmp_xy(), null, Options { schema: "yaml-1.1", compat: "json" });
      expect_toBe(res, "\"x\": true\n\"y\": \"off\"\n")
    }
  }
}
