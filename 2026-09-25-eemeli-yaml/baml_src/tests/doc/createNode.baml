// Port of tests/doc/createNode.ts

function tcn_map(x: unknown) -> YAMLMap {
  match (x) {
    let m: YAMLMap => m,
    _ => fail("expected a YAMLMap, got " + t_show(x)),
  }
}

function tcn_seq(x: unknown) -> YAMLSeq {
  match (x) {
    let s: YAMLSeq => s,
    _ => fail("expected a YAMLSeq, got " + t_show(x)),
  }
}

function tcn_scalar(x: unknown) -> Scalar {
  match (x) {
    let s: Scalar => s,
    _ => fail("expected a Scalar, got " + t_show(x)),
  }
}

function tcn_alias(x: unknown) -> Alias {
  match (x) {
    let a: Alias => a,
    _ => fail("expected an Alias, got " + t_show(x)),
  }
}

/// `node.anchor`
function tcn_anchor(x: unknown) -> string? {
  match (x) {
    let n: Scalar => n.anchor,
    let n: YAMLMap => n.anchor,
    let n: YAMLSeq => n.anchor,
    let n: YAMLSet => n.anchor,
    _ => null,
  }
}

/// `node.constructor.tagName`
function tcn_class_tagName(x: unknown) -> string? {
  match (x) {
    YAMLSet => YAMLSet.tagName(),
    let s: YAMLSeq => if (s._class == "YAMLOMap") { "tag:yaml.org,2002:omap" } else { YAMLSeq.tagName() },
    YAMLMap => YAMLMap.tagName(),
    _ => null,
  }
}

/// `new Set(values)`
function tcn_set(values: unknown[]) -> JsSet {
  let s = js_set();
  for (let v in values) {
    s.add(v);
  }
  s
}

testset "doc/createNode" {
  testset "createNode(value)" {
    test "boolean" {
      let s = Document.new(null, null, null).createNode(false, null, null);
      expect_toBeInstanceOf(s, "Scalar");
      expect_toBe(tcn_scalar(s).value, false)
    }
    test "null" {
      let s = Document.new(null, null, null).createNode(null, null, null);
      expect_toBeInstanceOf(s, "Scalar");
      expect_toBe(tcn_scalar(s).value, null)
    }
    test "undefined" {
      // `undefined` is `null` in BAML
      let s = Document.new(null, null, null).createNode(null, null, null);
      expect_toBeInstanceOf(s, "Scalar");
      expect_toBe(tcn_scalar(s).value, null)
    }
    test "number" {
      let s = Document.new(null, null, null).createNode(3, null, null);
      expect_toBeInstanceOf(s, "Scalar");
      expect_toBe(tcn_scalar(s).value, 3)
    }
    test "string" {
      let s = Document.new(null, null, null).createNode("test", null, null);
      expect_toBeInstanceOf(s, "Scalar");
      expect_toBe(tcn_scalar(s).value, "test")
    }
  }

  testset "explicit tags" {
    test "default tag" {
      let s = Document.new(null, null, null).createNode(3, null, Options { tag: "!!str" });
      expect_toBeInstanceOf(s, "Scalar");
      expect_toMatchObject(s, { "value": 3, "tag": "tag:yaml.org,2002:str" })
    }

    test "unknown tag" {
      expect_toThrow(() -> unknown { Document.new(null, null, null).createNode("3", null, Options { tag: "!foo" }) }, "Tag !foo not found")
    }
  }

  testset "arrays" {
    test "createNode([])" {
      let s = Document.new(null, null, null).createNode([], null, null);
      expect_toBeInstanceOf(s, "YAMLSeq");
      expect_toHaveLength(s, 0)
    }

    test "createNode([true])" {
      let doc = Document.new(null, null, null);
      let s = doc.createNode([true], null, null);
      expect_toBeInstanceOf(s, "YAMLSeq");
      expect_toMatchObject(s, [{ "value": true }]);
      doc.value = s;
      expect_toBe(doc.toString(null), "- true\n")
    }

    test "flow: true" {
      let doc = Document.new(null, null, null);
      let s = doc.createNode([true], null, Options { flow: true });
      expect_toBeInstanceOf(s, "YAMLSeq");
      expect_toMatchObject(s, [{ "value": true }]);
      doc.value = s;
      expect_toBe(doc.toString(null), "[ true ]\n")
    }

    testset "[3, [\"four\", 5]]" {
      let inner: unknown[] = ["four", 5];
      let array: unknown[] = [3, inner];
      test "createNode(value)" {
        let s = tcn_seq(Document.new(null, null, null).createNode(array, null, null));
        expect_toBeInstanceOf(s, "YAMLSeq");
        expect_toHaveLength(s, 2);
        expect_toBe(tcn_scalar(s.items[0]).value, 3);
        expect_toBeInstanceOf(s.items[1], "YAMLSeq");
        let s1 = tcn_seq(s.items[1]);
        expect_toHaveLength(s1, 2);
        expect_toBe(tcn_scalar(s1.items[0]).value, "four");
        expect_toBe(tcn_scalar(s1.items[1]).value, 5)
      }
      test "set doc value" {
        let res = "- 3\n- - four\n  - 5\n";
        let doc = Document.new(array, null, null);
        expect_toBe(doc.toString(null), res);
        doc.value = doc.createNode(array, null, null);
        expect_toBe(doc.toString(null), res)
      }
    }
  }

  testset "objects" {
    test "createNode({})" {
      let s = Document.new(null, null, null).createNode({}, null, null);
      expect_toBeInstanceOf(s, "YAMLMap");
      expect_toBe(tcn_map(s).size(), 0)
    }

    test "createNode({ x: true })" {
      let doc = Document.new(null, null, null);
      let s = doc.createNode({ "x": true }, null, null);
      expect_toBeInstanceOf(s, "YAMLMap");
      expect_toMatchObject(s, _map({ "x": true }, null));
      doc.value = s;
      expect_toBe(doc.toString(null), "x: true\n")
    }

    test "flow: true" {
      let doc = Document.new(null, null, null);
      let s = doc.createNode({ "x": true }, null, Options { flow: true });
      expect_toBeInstanceOf(s, "YAMLMap");
      expect_toMatchObject(s, _map({ "x": true }, { "flow": true }));
      doc.value = s;
      expect_toBe(doc.toString(null), "{ x: true }\n")
    }

    test "createNode({ x: true, y: undefined })" {
      // JS `undefined` is modelled by the `js_undefined()` sentinel.
      let s = Document.new(null, null, null).createNode({ "x": true, "y": js_undefined() }, null, null);
      expect_toBeInstanceOf(s, "YAMLMap");
      expect_toMatchObject(s, _map({ "x": true }, null))
    }

    test "createNode({ x: true, y: undefined }, { keepUndefined: true })" {
      let s = Document.new(null, null, null).createNode(
        { "x": true, "y": js_undefined() },
        null,
        Options { keepUndefined: true }
      );
      expect_toBeInstanceOf(s, "YAMLMap");
      expect_toMatchObject(s, _map({ "x": true, "y": null }, null))
    }

    test "createNode(pair)" {
      let pair = Document.new(null, null, null).createPair("x", true, null);
      let s = Document.new(null, null, null).createNode(pair, null, null);
      expect_toBeInstanceOf(s, "YAMLMap");
      expect_toMatchObject(s, _map({ "x": true }, null))
    }

    testset "{ x: 3, y: [4], z: { w: \"five\", v: 6 } }" {
      let object = { "x": 3, "y": [4], "z": { "w": "five", "v": 6 } };
      test "createNode(value)" {
        let s = Document.new(null, null, null).createNode(object, null, null);
        expect_toBeInstanceOf(s, "YAMLMap");
        expect_toBe(tcn_map(s).size(), 3);
        expect_toMatchObject(s, _map({ "x": 3, "y": _seq([4]), "z": _map({ "w": "five", "v": 6 }, null) }, null))
      }
      test "set doc value" {
        let res = "x: 3
y:
  - 4
z:
  w: five
  v: 6\n";
        let doc = Document.new(object, null, null);
        expect_toBe(doc.toString(null), res);
        doc.value = doc.createNode(object, null, null);
        expect_toBe(doc.toString(null), res)
      }
    }
  }

  testset "Set" {
    test "createNode(new Set)" {
      let s = Document.new(null, null, null).createNode(js_set(), null, null);
      expect_toBeInstanceOf(s, "YAMLSeq");
      expect_toHaveLength(s, 0)
    }

    test "createNode(new Set([true]))" {
      let s = Document.new(null, null, null).createNode(tcn_set([true]), null, null);
      expect_toBeInstanceOf(s, "YAMLSeq");
      expect_toMatchObject(s, [{ "value": true }])
    }

    testset "Set { 3, Set { 'four', 5 } }" {
      let set = tcn_set([3, tcn_set(["four", 5])]);

      test "createNode(set)" {
        let s = tcn_seq(Document.new(null, null, null).createNode(set, null, null));
        expect_toBeInstanceOf(s, "YAMLSeq");
        expect_toHaveLength(s, 2);
        expect_toBe(tcn_scalar(s.items[0]).value, 3);
        expect_toBeInstanceOf(s.items[1], "YAMLSeq");
        let s1 = tcn_seq(s.items[1]);
        expect_toHaveLength(s1, 2);
        expect_toBe(tcn_scalar(s1.items[0]).value, "four");
        expect_toBe(tcn_scalar(s1.items[1]).value, 5)
      }

      test "set doc value" {
        let res = "- 3\n- - four\n  - 5\n";
        let doc = Document.new(set, null, null);
        expect_toBe(doc.toString(null), res);
        doc.value = doc.createNode(set, null, null);
        expect_toBe(doc.toString(null), res)
      }

      test "Schema#createNode() - YAML 1.2" {
        let doc = Document.new(null, null, null);
        let s = doc.createNode(set, null, null);
        expect_toBeInstanceOf(s, "YAMLSeq");
        expect_toMatchObject(s, [{ "value": 3 }, [{ "value": "four" }, { "value": 5 }]])
      }

      test "Schema#createNode() - YAML 1.1" {
        let doc = Document.new(null, null, Options { version: "1.1" });
        let s = doc.createNode(set, null, null);
        expect_toBe(tcn_class_tagName(s), "tag:yaml.org,2002:set");
        let innerEntry: unknown[] = [tcn_set(["four", 5]), _set(["four", 5], null)];
        expect_toMatchObject(s, _set([3, innerEntry], null))
      }
    }
  }

  testset "Map" {
    test "createNode(new Map)" {
      let s = Document.new(null, null, null).createNode(js_map(), null, null);
      expect_toBeInstanceOf(s, "YAMLMap");
      expect_toBe(tcn_map(s).size(), 0)
    }
    test "createNode(new Map([[\"x\", true]]))" {
      let m = js_map();
      m.set("x", true);
      let s = Document.new(null, null, null).createNode(m, null, null);
      expect_toBeInstanceOf(s, "YAMLMap");
      expect_toMatchObject(s, _map({ "x": true }, null))
    }
    testset "Map { 'x' => 3, 'y' => Set { 4 }, Map { 'w' => 'five', 'v' => 6 } => 'z' }" {
      let mapKey = js_map();
      mapKey.set("w", "five");
      mapKey.set("v", 6);
      let map_ = js_map();
      map_.set("x", 3);
      map_.set("y", tcn_set([4]));
      map_.set(mapKey, "z");

      test "createNode(map)" {
        let s = Document.new(null, null, null).createNode(map_, null, null);
        expect_toBeInstanceOf(s, "YAMLMap");
        expect_toBe(tcn_map(s).size(), 3);
        let e1: unknown[] = ["x", 3];
        let e2: unknown[] = ["y", _seq([4])];
        let e3: unknown[] = [mapKey, _pair(_map({ "w": "five", "v": 6 }, null), "z")];
        let entries: unknown[] = [e1, e2, e3];
        expect_toMatchObject(s, _map(entries, null))
      }

      test "set doc value" {
        let res = "x: 3
y:
  - 4
? w: five
  v: 6
: z\n";
        let doc = Document.new(map_, null, null);
        expect_toBe(doc.toString(null), res);
        doc.value = doc.createNode(map_, null, null);
        expect_toBe(doc.toString(null), res)
      }
    }
  }

  testset "toJSON()" {
    test "Date" {
      let date = js_date(js_date_utc(2018, 11, 22, 8, 2, 52, 0));
      let node = Document.new(null, null, null).createNode(date, null, null);
      expect_toBe(tcn_scalar(node).value, date.toISOString())
    }
  }

  testset "strictly equal objects" {
    test "createNode([foo, foo])" {
      let foo = { "foo": "FOO" };
      let s = Document.new(null, null, null).createNode([foo, foo], null, null);
      expect_toBeInstanceOf(s, "YAMLSeq");
      expect_toMatchObject(s, _seq([_map({ "foo": "FOO" }, null), { "source": "a1" }]));
      expect_toBe(tcn_anchor(tcn_seq(s).items[0]), "a1")
    }

    test "createNode([foo, foo], { aliasDuplicateObjects: false })" {
      let foo = { "foo": "FOO" };
      let s = Document.new(null, null, null).createNode([foo, foo], null, Options {
        aliasDuplicateObjects: false
      });
      expect_toBeInstanceOf(s, "YAMLSeq");
      expect_toMatchObject(s, _seq([_map({ "foo": "FOO" }, null), _map({ "foo": "FOO" }, null)]))
    }
  }

  testset "circular references" {
    test "parent at root" {
      let map_: map<string, unknown> = { "foo": "bar" };
      map_.set("map", map_);
      let doc = Document.new(map_, null, null);
      expect_toMatchObject(doc.value, _map({ "foo": "bar", "map": { "source": "a1" } }, { "anchor": "a1" }));
      expect_toBe(doc.toString(null), source(`
        &a1
        foo: bar
        map: *a1
      `) + "\n")
    }

    test "ancestor at root" {
      let baz: map<string, unknown> = {};
      let map_ = { "foo": { "bar": { "baz": baz } } };
      baz.set("map", map_);
      let doc = Document.new(map_, null, null);
      expect_toMatchObject(tcn_map(tcn_map(tcn_map(tcn_map(doc.value).get("foo")).get("bar")).get("baz")).get("map"), {
        "source": "a1"
      });
      expect_toBe(doc.toString(null), source(`
        &a1
        foo:
          bar:
            baz:
              map: *a1
      `) + "\n")
    }

    test "sibling sequences" {
      let one = ["one"];
      let two = ["two"];
      let seq = [one, two, one, one, two];
      let doc = Document.new(seq, null, null);
      expect_toMatchObject(doc.value, [
        [{ "value": "one" }],
        [{ "value": "two" }],
        { "source": "a1" },
        { "source": "a1" },
        { "source": "a2" }
      ]);
      expect_toBe(doc.toString(null), source(`
        - &a1
          - one
        - &a2
          - two
        - *a1
        - *a1
        - *a2
      `) + "\n")
    }

    test "further relatives" {
      let baz = { "a": 1 };
      let seq = [{ "foo": { "bar": { "baz": baz } } }, { "fe": { "fi": { "fo": { "baz": baz } } } }];
      let doc = Document.new(null, null, null);
      let node = tcn_seq(doc.createNode(seq, null, null));
      let src_ = tcn_map(tcn_map(tcn_map(node.items[0]).get("foo")).get("bar")).get("baz");
      let alias = tcn_alias(tcn_map(tcn_map(tcn_map(tcn_map(node.items[1]).get("fe")).get("fi")).get("fo")).get("baz"));
      expect_toMatchObject(src_, _map({ "a": 1 }, null));
      expect_toBe(alias.source, tcn_anchor(src_))
    }
  }
}
