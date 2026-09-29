// Port of tests/collection-access.ts
//
// `beforeEach` is ported as a per-test factory function (a testset-level
// `let` would be shared, like `beforeAll`, and these tests mutate it).
// `map.size` / `seq.length` are method calls; `seq[i]` is `seq.at(i)`.

function tca_mapDoc() -> Document {
  Document.new({ "a": 1, "b": { "c": 3, "d": 4 } }, null, null)
}

function tca_map(doc: Document) -> YAMLMap {
  match (doc.value) {
    let m: YAMLMap => m,
    _ => fail("doc.value is not a YAMLMap"),
  }
}

function tca_seq(doc: Document) -> YAMLSeq {
  match (doc.value) {
    let s: YAMLSeq => s,
    _ => fail("doc.value is not a YAMLSeq"),
  }
}

function tca_set(doc: Document) -> YAMLSet {
  match (doc.value) {
    let s: YAMLSet => s,
    _ => fail("doc.value is not a YAMLSet"),
  }
}

function tca_seqDoc() -> Document {
  Document.new([1, [2, 3]], null, null)
}

function tca_setDoc() -> Document {
  Document.new([1, 2, [3]], null, Options { tag: "!!set", version: "1.1" })
}

function tca_omapDoc() -> Document {
  let v: unknown[] = [{ "a": 1 }, { "b": { "c": 3, "d": 4 } }];
  Document.new(v, null, Options { tag: "!!omap", version: "1.1" })
}

/// `subMap!.toJS(doc)` on a `Node | Pair | null` lookup result.
function tca_toJS(n: SeqItem?, doc: Document) -> unknown {
  match (n) {
    let x: Node => x.toJS(doc, null),
    let p: Pair => p.toJS(doc, ToJSContext.new(null)),
    _ => fail("value is undefined"),
  }
}

testset "collection-access" {
  testset "Map" {
    test "create" {
      let doc = tca_mapDoc();
      let map = tca_map(doc);
      expect_toMatchObject(map, _map({ "a": 1, "b": _map({ "c": 3, "d": 4 }, null) }, null))
    }

    test "set" {
      let doc = tca_mapDoc();
      let map = tca_map(doc);
      map.set(doc.createPair("c", "x", null), null);
      expect_toMatchObject(map.get("c"), { "value": "x" });
      map.set("c", "y");
      expect_toMatchObject(map.get("c"), { "value": "y" });
      expect_toBe(map.size(), 3)
    }

    test "delete" {
      let doc = tca_mapDoc();
      let map = tca_map(doc);
      expect_toBe(map.delete("a"), true);
      expect_toBeNull(map.get("a"));
      expect_toBe(map.delete("c"), false);
      expect_toMatchObject(map.get("b"), { "size": 2 });
      expect_toBe(map.size(), 1)
    }

    test "get with value" {
      let doc = tca_mapDoc();
      let map = tca_map(doc);
      expect_toMatchObject(map.get("a"), { "value": 1 });
      let subMap = map.get("b");
      expect_toBeInstanceOf(subMap, "YAMLMap");
      expect_toMatchObject(tca_toJS(subMap, doc), { "c": 3, "d": 4 });
      expect_toBeNull(map.get("c"))
    }

    test "get with node" {
      let doc = tca_mapDoc();
      let map = tca_map(doc);
      expect_toMatchObject(map.get(doc.createNode("a", null, null)), { "value": 1 });
      let subMap = map.get(doc.createNode("b", null, null));
      expect_toBeInstanceOf(subMap, "YAMLMap");
      expect_toMatchObject(tca_toJS(subMap, doc), { "c": 3, "d": 4 });
      expect_toBeNull(map.get(doc.createNode("c", null, null)))
    }

    test "has with value" {
      let doc = tca_mapDoc();
      let map = tca_map(doc);
      expect_toBe(map.has("a"), true);
      expect_toBe(map.has("b"), true);
      expect_toBe(map.has("c"), false);
      expect_toBe(map.has(""), false);
      // `map.has()` (no argument) → `map.has(undefined)`
      expect_toBe(map.has(null), false)
    }

    test "has with node" {
      let doc = tca_mapDoc();
      let map = tca_map(doc);
      expect_toBe(map.has(doc.createNode("a", null, null)), true);
      expect_toBe(map.has(doc.createNode("b", null, null)), true);
      expect_toBe(map.has(doc.createNode("c", null, null)), false);
      // `doc.createNode()` → `doc.createNode(undefined)`
      expect_toBe(map.has(doc.createNode(null, null, null)), false)
    }

    test "set with value" {
      let doc = tca_mapDoc();
      let map = tca_map(doc);
      map.set("a", 2);
      expect_toMatchObject(map.get("a"), { "value": 2 });
      map.set("b", 5);
      expect_toMatchObject(map.get("b"), { "value": 5 });
      map.set("c", 6);
      expect_toMatchObject(map.get("c"), { "value": 6 });
      expect_toBe(map.size(), 3)
    }

    test "set with node" {
      let doc = tca_mapDoc();
      let map = tca_map(doc);
      map.set(doc.createNode("a", null, null), 2);
      expect_toMatchObject(map.get("a"), { "value": 2 });
      map.set(doc.createNode("b", null, null), 5);
      expect_toMatchObject(map.get("b"), { "value": 5 });
      map.set(doc.createNode("c", null, null), 6);
      expect_toMatchObject(map.get("c"), { "value": 6 });
      expect_toBe(map.size(), 3)
    }

    test "set scalar node with anchor" {
      let doc = parseDocument("a: &A value\nb: *A\n", null);
      doc.set("a", "foo");
      expect_toMatchObject(doc.get("a"), { "value": "foo" });
      expect_toBe(doc.toString(null), "a: &A foo\nb: *A\n")
    }

    test "object key equality" {
      let a1: unknown[] = [1];
      let m = js_map();
      m.set(1, 2);
      m.set("1", "2");
      let v2: unknown[] = [2];
      m.set(a1, v2);
      let doc = Document.new(m, null, null);
      expect_toMatchObject(doc.get(1), { "value": 2 });
      expect_toMatchObject(doc.get("1"), { "value": "2" });
      let other: unknown[] = [1];
      expect_toBeNull(doc.get(other));
      expect_toMatchObject(doc.get(a1), [{ "value": 2 }])
    }
  }

  testset "Seq" {
    test "create" {
      let doc = tca_seqDoc();
      let seq = tca_seq(doc);
      expect_toMatchObject(seq, [{ "value": 1 }, [{ "value": 2 }, { "value": 3 }]])
    }

    test "push" {
      let doc = tca_seqDoc();
      let seq = tca_seq(doc);
      seq.push(9);
      expect_toMatchObject(seq.at(2), { "value": 9 });
      seq.push(1);
      expect_toHaveLength(seq, 4)
    }

    test "index access" {
      let doc = tca_seqDoc();
      let seq = tca_seq(doc);
      expect_toMatchObject(seq.items[0], { "value": 1 });
      let subSeq = seq.items[1];
      expect_toBeInstanceOf(subSeq, "YAMLSeq");
      expect_toMatchObject(tca_toJS(subSeq, doc), [2, 3]);
      // `seq[2]` out of bounds is `undefined` in JS; a BAML array index
      // would panic, so this uses the bounds-checked `at()`.
      expect_toBeNull(seq.at(2))
    }

    test "at() with integer" {
      let doc = tca_seqDoc();
      let seq = tca_seq(doc);
      expect_toMatchObject(seq.at(0), { "value": 1 });
      let subSeq = seq.at(1);
      expect_toBeInstanceOf(subSeq, "YAMLSeq");
      expect_toMatchObject(tca_toJS(subSeq, doc), [2, 3]);
      expect_toBeNull(seq.at(2))
    }

    test "set with integer" {
      let doc = tca_seqDoc();
      let seq = tca_seq(doc);
      seq.set(0, 2);
      expect_toMatchObject(seq.at(0), { "value": 2 });
      seq.set(-1, 5);
      expect_toMatchObject(seq.at(1), { "value": 5 });
      seq.set(2, 6);
      expect_toMatchObject(seq.at(2), { "value": 6 });
      expect_toHaveLength(seq, 3)
    }

    test "set with non-integer" {
      let doc = tca_seqDoc();
      let seq = tca_seq(doc);
      expect_toThrowNamed(() -> unknown { seq.set(0.5, 2) }, "TypeError");
      expect_toThrowNamed(() -> unknown { seq.set(doc.createNode(0, null, null), 2) }, "TypeError")
    }
  }

  testset "Set" {
    test "create" {
      let doc = tca_setDoc();
      let set = tca_set(doc);
      let three: unknown[] = [3];
      let entry: unknown[] = [three, _seq([3])];
      expect_toMatchObject(set, _set([1, 2, entry], null))
    }

    test "add" {
      let doc = tca_setDoc();
      let set = tca_set(doc);
      set.add("x");
      expect_toMatchObject(set.get("x"), { "value": "x" });
      set.add("x");
      let y0 = Scalar.new("y");
      set.add(y0);
      set.add(Scalar.new("y"));
      expect_toBe(set.get("y"), y0);
      expect_toBe(set.size(), 5)
    }

    test "get" {
      let doc = tca_setDoc();
      let set = tca_set(doc);
      expect_toMatchObject(set.get(1), { "value": 1 });
      expect_toBeNull(set.get(0));
      expect_toBeNull(set.get("1"));
      let three: unknown[] = [3];
      expect_toBeNull(set.get(three))
    }

    test "has" {
      let doc = tca_setDoc();
      let set = tca_set(doc);
      expect_toBe(set.has(0), false);
      expect_toBe(set.has(1), true);
      expect_toBe(set.has(Scalar.new(1)), true);
      let seq = set.values.values().at(-1);
      expect_toBe(set.has(seq), true)
    }

    test "delete" {
      let doc = tca_setDoc();
      let set = tca_set(doc);
      expect_toBe(set.delete(0), false);
      expect_toBe(set.delete(1), true);
      expect_toBe(set.has(1), false);
      expect_toBe(set.size(), 2)
    }
  }

  testset "OMap" {
    test "create" {
      let doc = tca_omapDoc();
      let omap = tca_seq(doc);
      expect_toMatchObject(omap, [_pair("a", 1), _pair("b", _map({ "c": 3, "d": 4 }, null))])
    }

    test "push" {
      let doc = tca_omapDoc();
      let omap = tca_seq(doc);
      omap.push(doc.createPair("c", "x", null));
      expect_toMatchObject(omap.at(-1), { "value": { "value": "x" } });
      omap.push(doc.createPair("c", "y", null));
      expect_toThrow(() -> unknown { omap.toString(null, null, null) }, null);
      expect_toThrow(() -> unknown { omap.push("d") }, null);
      expect_toBe(omap.size(), 4)
    }

    test "set" {
      let doc = tca_omapDoc();
      let omap = tca_seq(doc);
      omap.set(0, doc.createPair("a", 2, null));
      omap.set(1, doc.createPair("b", 5, null));
      omap.set(3, doc.createPair("d", 6, null));
      let expected: unknown[] = [_pair("a", 2), _pair("b", 5), null, _pair("d", 6)];
      expect_toMatchObject(omap, expected);
      expect_toBe(omap.size(), 4);
      expect_toBe(doc.toString(null), "!!omap\n- a: 2\n- b: 5\n- null\n- d: 6\n")
    }

    test "toString" {
      let doc = tca_omapDoc();
      expect_toBe(doc.toString(null), "!!omap\n- a: 1\n- b:\n    c: 3\n    d: 4\n")
    }
  }

  testset "Document" {
    test "get with map value" {
      let v: unknown[] = [2, 3];
      let doc = Document.new({ "a": 1, "b": v }, null, null);
      expect_toMatchObject(doc.get("a"), { "value": 1 });
      expect_toBeNull(doc.get("c"))
    }

    test "get with seq value" {
      let doc = Document.new([2, 3], null, null);
      expect_toMatchObject(doc.get(0), { "value": 2 });
      expect_toMatchObject(doc.get(-1), { "value": 3 });
      expect_toThrow(() -> unknown { doc.get("a") }, null)
    }

    test "get with scalar value" {
      let doc = Document.new("s", null, null);
      expect_toBeNull(doc.get("a"))
    }

    test "set with map value" {
      let v: unknown[] = [2, 3];
      let doc = Document.new({ "a": 1, "b": v }, null, null);
      doc.set("a", 2);
      expect_toMatchObject(doc.get("a"), { "value": 2 });
      doc.set("c", 6);
      expect_toMatchObject(doc.get("c"), { "value": 6 });
      expect_toBe(tca_map(doc).size(), 3)
    }

    test "set with seq value" {
      let doc = Document.new([2, 3], null, null);
      doc.set(0, 4);
      expect_toMatchObject(doc.get(0), { "value": 4 });
      doc.set(3, 6);
      expect_toMatchObject(doc.get(3), { "value": 6 });
      expect_toThrowNamed(() -> unknown { doc.set("a", 1) }, "TypeError");
      expect_toBe(tca_seq(doc).size(), 4)
    }

    test "set with scalar value" {
      let doc = Document.new("s", null, null);
      expect_toThrow(() -> unknown { doc.set("a", 1) }, "document value")
    }
  }
}
