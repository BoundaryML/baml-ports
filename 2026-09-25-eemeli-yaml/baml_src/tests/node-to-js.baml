// Port of tests/node-to-js.ts

/// `doc.get(k)!.toJS(doc)`: `get()` returns a `SeqItem?` (`Node | Pair`), so
/// narrow it to a `Node` first (the upstream `!` non-null assertion).
function tn2j_to_js(item: SeqItem?, doc: Document) -> unknown {
  match (item) {
    let s: Scalar => s.toJS(doc, null),
    let m: YAMLMap => m.toJS(doc, null),
    let q: YAMLSeq => q.toJS(doc, null),
    let t: YAMLSet => t.toJS(doc, null),
    let a: Alias => a.toJS(doc, null),
    _ => {
      throw js_type_error("Cannot read properties of undefined (reading 'toJS')");
    },
  }
}

testset "node-to-js" {
  testset "scalars" {
    test "plain" {
      let doc = parseDocument("42", null);
      expect_toBe(doc.value.toJS(doc, null), 42)
    }

    test "plain in map" {
      let doc = parseDocument("key: 42", null);
      expect_toBe(tn2j_to_js(doc.get("key"), doc), 42)
    }
  }

  testset "collections" {
    test "map" {
      let doc = parseDocument("key: 42", null);
      expect_toMatchObject(doc.value.toJS(doc, null), { "key": 42 })
    }

    test "map in seq" {
      let doc = parseDocument("- key: 42", null);
      expect_toMatchObject(tn2j_to_js(doc.get(0), doc), { "key": 42 })
    }
  }

  testset "alias" {
    test "simple" {
      let doc = parseDocument(source(`
        one: &a 42
        two: *a
      `), null);
      expect_toBe(tn2j_to_js(doc.get("two"), doc), 42)
    }

    test "repeated identifier" {
      let doc = parseDocument(source(`
        one: &a 13
        two: &a 42
        three: *a
        four: &a 99
      `), null);
      expect_toBe(tn2j_to_js(doc.get("three"), doc), 42)
    }

    test "nested aliases" {
      let doc = parseDocument(source(`
        one: &a 42
        two: &b { key: *a }
        three: *b
      `), null);
      expect_toMatchObject(tn2j_to_js(doc.get("three"), doc), { "key": 42 })
    }

    test "missing anchor" {
      let doc = parseDocument(source(`
        one: &a 42
        two: *b
      `), null);
      expect_toThrowNamed(() -> unknown { tn2j_to_js(doc.get("two"), doc) }, "ReferenceError")
    }
  }
}
