// Port of tests/doc/anchors.ts

/// `x as Node` (non-null assertion + cast)
function tanc_node(x: unknown) -> Node {
  let n = as_node(x);
  if (n == null) {
    fail("expected a Node, got " + t_show(x));
  }
  n ?? Scalar.new(null)
}

function tanc_map(x: unknown) -> YAMLMap {
  match (x) {
    let m: YAMLMap => m,
    _ => fail("expected a YAMLMap, got " + t_show(x)),
  }
}

function tanc_seq(x: unknown) -> YAMLSeq {
  match (x) {
    let s: YAMLSeq => s,
    _ => fail("expected a YAMLSeq, got " + t_show(x)),
  }
}

function tanc_alias(x: unknown) -> Alias {
  match (x) {
    let a: Alias => a,
    _ => fail("expected an Alias, got " + t_show(x)),
  }
}

/// `node.anchor = anchor`
function tanc_set_anchor(x: unknown, anchor: string) -> null {
  match (x) {
    let s: Scalar => {
      s.anchor = anchor;
    },
    let m: YAMLMap => {
      m.anchor = anchor;
    },
    let q: YAMLSeq => {
      q.anchor = anchor;
    },
    let t: YAMLSet => {
      t.anchor = anchor;
    },
    _ => {
      fail("cannot set anchor on " + t_show(x));
    },
  }
  null
}

/// `res[i]` for a JS array value
function tanc_at(res: unknown, i: int) -> unknown {
  let arr = js_as_array(res);
  if (arr == null) {
    fail("expected an array, got " + t_show(res));
  }
  (arr ?? [])[i]
}

function tanc_merge_src() -> string {
  "---
- &CENTER { x: 1, y: 2 }
- &LEFT { x: 0, y: 2 }
- &BIG { r: 10 }
- &SMALL { r: 1 }

# All the following maps are equal:

- # Explicit keys
  x: 1
  y: 2
  r: 10
  label: center/big

- # Merge one map
  << : *CENTER
  r: 10
  label: center/big

- # Merge multiple maps
  << : [ *CENTER, *BIG ]
  label: center/big

- # Override with explicit tag
  !!merge << : [ *BIG, *LEFT, *SMALL ]
  x: 1
  label: center/big"
}

function tanc_exp_map() -> JsMap<unknown> {
  let m1 = js_map();
  m1.set("k0", "v1");
  m1.set("k1", "v1");
  let m2 = js_map();
  m2.set("k1", "v2");
  m2.set("k2", "v2");
  let y = js_map();
  y.set("k0", "v0");
  y.set("k1", "v1");
  y.set("k2", "v2");
  let res = js_map();
  let x: unknown[] = [m1, m2];
  res.set("x", x);
  res.set("y", y);
  res
}

testset "doc/anchors" {
  test "basic" {
    let src = "- &a 1\n- *a\n";
    let doc = parseDocument(src, null);
    expect_toHaveLength(doc.errors, 0);
    expect_toMatchObject(doc.value, [{ "anchor": "a", "value": 1 }, { "source": "a" }]);
    expect_toBe(doc.toString(null), src);
    expect_toBe(tanc_alias(doc.get(1)).resolve(doc, null), doc.get(0))
  }

  test "re-defined anchor" {
    let src = "- &a 1\n- &a 2\n- *a\n";
    let doc = parseDocument(src, null);
    expect_toHaveLength(doc.errors, 0);
    expect_toMatchObject(doc.value, [
      { "anchor": "a", "value": 1 },
      { "anchor": "a", "value": 2 },
      { "source": "a" }
    ]);
    expect_toMatchObject(doc.toJS(null), [1, 2, 2]);
    expect_toBe(doc.toString(null), "- &a 1\n- &a 2\n- *a\n")
  }

  test "circular reference" {
    let src = "&a [ 1, *a ]\n";
    let doc = parseDocument(src, null);
    expect_toHaveLength(doc.errors, 0);
    expect_toHaveLength(doc.warnings, 0);
    expect_toMatchObject(doc.value, [{ "value": 1 }, { "source": "a" }]);
    expect_toBe(tanc_seq(doc.value).anchor, "a");
    let res = doc.toJS(null);
    expect_toBe(tanc_at(res, 1), res);
    expect_toBe(doc.toString(null), src);
    expect_toBe(tanc_alias(doc.get(1)).resolve(doc, null), doc.value)
  }

  testset "anchor on tagged collection" {
    test "!!set" {
      let res = parse("- &a !!set { 1, 2 }\n- *a\n", null, null);
      let exp = js_set();
      exp.add(1);
      exp.add(2);
      expect_toMatchObject(tanc_at(res, 0), exp);
      expect_toBe(tanc_at(res, 1), tanc_at(res, 0))
    }

    test "!!omap" {
      let res = parse("- &a !!omap [ 1: 1, 2: 2 ]\n- *a\n", null, null);
      let exp = js_map();
      exp.set(1, 1);
      exp.set(2, 2);
      expect_toMatchObject(tanc_at(res, 0), exp);
      expect_toBe(tanc_at(res, 1), tanc_at(res, 0))
    }
  }

  testset "create" {
    test "node.anchor" {
      let doc = parseDocument("[{ a: A }, { b: B }]", null);
      tanc_set_anchor(doc.get(0), "AA");
      tanc_set_anchor(tanc_map(doc.get(0)).get("a"), "a");
      tanc_set_anchor(tanc_map(doc.get(0)).get("a"), "");
      tanc_set_anchor(tanc_map(doc.get(1)).get("b"), "BB");
      expect_toBe(doc.toString(null), "[ &AA { a: A }, { b: &BB B } ]\n")
    }

    test "doc.createAlias" {
      let doc = parseDocument("[{ a: A }, { b: B }]", null);
      let alias = doc.createAlias(tanc_node(doc.get(0)), "AA");
      tanc_seq(doc.value).push(alias);
      expect_toMatchObject(doc.toJS(null), [{ "a": "A" }, { "b": "B" }, { "a": "A" }]);
      let alias2 = doc.createAlias(tanc_node(doc.get(1)), "AA");
      expect_toBe(tanc_map(doc.get(1)).anchor, "AA1");
      expect_toBe(alias2.source, "AA1");
      // toMatch with a string argument is a substring match
      expect_true(doc.toString(null).includes("[ &AA { a: A }, &AA1 { b: B }, *AA ]\n"), "toMatch")
    }

    test "repeated Array in createNode" {
      let doc = Document.new(null, null, null);
      let ref_: unknown[] = [];
      let node = tanc_map(doc.createNode({ "src": ref_, "ref": ref_ }, null, null));
      expect_toMatchObject(node, _map({ "src": [], "ref": { "source": "a1" } }, null));
      expect_toBe(tanc_seq(node.get("src")).anchor, "a1")
    }

    test "repeated Date in createNode" {
      let doc = Document.new(null, null, null);
      // `new Date()`: a fixed timestamp instead of the current time
      let date = js_date(1545465772000);
      let value = date.toISOString();
      let node = doc.createNode({ "src": date, "ref": date }, null, null);
      expect_toMatchObject(node, _map({ "src": { "value": value, "anchor": "a1" }, "ref": { "source": "a1" } }, null))
    }
  }

  testset "errors" {
    test "invalid anchor characters" {
      let doc = parseDocument("[{ a: A }, { b: B }]", null);
      tanc_set_anchor(doc.get(0), "A A");
      expect_toThrow(() -> unknown { doc.toString(null) }, "Anchor must not contain whitespace or control characters: \"A A\"")
    }

    test "set tag on alias" {
      // UNPORTABLE: upstream assigns `alias.tag = ...` and relies on the
      // `Alias#tag` property setter throwing "Alias nodes cannot have tags".
      // BAML has no property setters; `Alias.tag` is a plain field.
      let doc = parseDocument("[{ a: A }, { b: B }]", null);
      let node = tanc_seq(doc.value).items[0];
      let alias = doc.createAlias(tanc_node(node), "AA");
      expect_toBe(alias.source, "AA")
    }

    test "alias before anchor" {
      let doc = parseDocument("[{ a: A }, { b: B }]", null);
      let alias = doc.createAlias(tanc_node(doc.get(0)), "AA");
      tanc_seq(doc.value).unshift([alias]);
      expect_toThrow(() -> unknown { doc.toString(null) }, "Unresolved alias (the anchor must be set before the alias): AA")
    }

    test "empty alias" {
      let doc = parseDocument("- *\n", null);
      expect_toMatchObject(doc.errors, [{ "code": "BAD_ALIAS" }])
    }

    test "empty anchor on value" {
      let doc = parseDocument("- & foo\n", null);
      expect_toMatchObject(doc.errors, [{ "code": "BAD_ALIAS" }])
    }

    test "empty anchor at end" {
      let doc = parseDocument("- &\n", null);
      expect_toMatchObject(doc.errors, [{ "code": "BAD_ALIAS" }])
    }

    test "resolution with maxAliasCount:0" {
      let src = "- &a 1\n- *a\n";
      let doc = parseDocument(src, null);
      expect_toHaveLength(doc.errors, 0);
      let alias = tanc_alias(doc.get(1));
      expect_toThrowNamed(() -> unknown { alias.resolve(doc, ToJSContext.new(Options { maxAliasCount: 0 })) }, "ReferenceError")
    }

    test "circular reference" {
      let src = "&A { <<: *A, B: b }\n";
      let doc = parseDocument(src, Options { merge: true });
      expect_toHaveLength(doc.errors, 0);
      expect_toHaveLength(doc.warnings, 0);
      expect_toThrow(() -> unknown { doc.toJS(null) }, "Excessive alias count indicates a resource exhaustion attack");
      expect_toThrowNamed(() -> unknown { doc.toJS(Options { maxAliasCount: 0 }) }, "ReferenceError");
      expect_toThrowNamed(() -> unknown { doc.toJS(Options { maxAliasCount: 1 }) }, "ReferenceError");
      expect_toThrowNamed(() -> unknown { doc.toJS(Options { maxAliasCount: 2 }) }, "ReferenceError");
      expect_toBe(doc.toString(null), src)
    }
  }

  testset "warnings" {
    test "anchor ending in colon" {
      let doc = parseDocument("- &x:\n", null);
      expect_toHaveLength(doc.errors, 0);
      expect_toMatchObject(doc.warnings, [{ "code": "BAD_ALIAS" }])
    }

    test "alias ending in colon" {
      let doc = parseDocument("- *x:\n", null);
      expect_toHaveLength(doc.errors, 0);
      expect_toMatchObject(doc.warnings, [{ "code": "BAD_ALIAS" }])
    }
  }

  testset "__proto__ as anchor name" {
    test "parse" {
      let src = "- &__proto__ 1\n- *__proto__\n";
      let doc = parseDocument(src, null);
      expect_toHaveLength(doc.errors, 0);
      expect_toMatchObject(doc.value, [
        { "anchor": "__proto__", "value": 1 },
        { "source": "__proto__" }
      ]);
      expect_toMatchObject(doc.toJS(null), [1, 1]);
      expect_toBe(doc.toString(null), src)
    }

    test "create/stringify" {
      let doc = parseDocument("[{ a: A }, { b: B }]", null);
      let alias = doc.createAlias(tanc_node(tanc_seq(doc.value).items[0]), "__proto__");
      tanc_seq(doc.value).push(alias);
      expect_toMatchObject(doc.toJS(null), [{ "a": "A" }, { "b": "B" }, { "a": "A" }]);
      expect_true(doc.toString(null).includes("[ &__proto__ { a: A }, { b: B }, *__proto__ ]\n"), "toMatch")
    }
  }

  testset "merge <<" {
    let src = tanc_merge_src();

    test "YAML.parse with merge:true" {
      let res = parse(src, null, Options { merge: true });
      expect_toHaveLength(res, 8);
      let arr = js_as_array(res) ?? [];
      let i = 4;
      while (i < arr.length()) {
        expect_toMatchObject(arr[i], { "x": 1, "y": 2, "r": 10, "label": "center/big" });
        i += 1;
      }
    }

    test "YAML.parse with customTags:[\"merge\"]" {
      let res = parse(src, null, Options { customTags: ["merge"] });
      expect_toHaveLength(res, 8);
      let arr = js_as_array(res) ?? [];
      let i = 4;
      while (i < arr.length()) {
        expect_toMatchObject(arr[i], { "x": 1, "y": 2, "r": 10, "label": "center/big" });
        i += 1;
      }
    }

    test "YAML.parse with merge:false" {
      let res = parse(src, null, null);
      expect_toHaveLength(res, 8);
      let arr = js_as_array(res) ?? [];
      let i = 5;
      while (i < arr.length() - 1) {
        expect_toHaveProperty(arr[i], "<<");
        i += 1;
      }
      expect_toMatchObject(arr[arr.length() - 1], {
        "x": 1,
        "y": 2,
        "r": 10,
        "label": "center/big"
      })
    }

    test "YAML.parseDocument" {
      let doc = parseDocument(src, Options { merge: true });
      let items = tanc_seq(doc.value).items;
      let firstValues = items.slice(5, items.length()).map((it: SeqItem) -> unknown {
        tanc_map(it).values.values()[0].value
      });
      expect_toMatchObject(firstValues, [
        { "source": "CENTER" },
        [{ "source": "CENTER" }, { "source": "BIG" }],
        [{ "source": "BIG" }, { "source": "LEFT" }, { "source": "SMALL" }]
      ])
    }

    test "alias is associated with a sequence" {
      let res = parse("- &items [{ a: A }, { b: B }]\n- { <<: *items, c: C }", null, Options { merge: true });
      expect_toEqual(tanc_at(res, 1), { "a": "A", "b": "B", "c": "C" })
    }

    testset "non-alias merges" {
      test "single map" {
        let res = parse("{ <<: { a: A }, b: B }", null, Options { merge: true });
        expect_toEqual(res, { "a": "A", "b": "B" })
      }

      test "multiple maps" {
        let res = parse("{ <<: [{ a: A }, { b: B }], c: C }", null, Options { merge: true });
        expect_toEqual(res, { "a": "A", "b": "B", "c": "C" })
      }

      test "mixed refs & maps" {
        let res = parse("{ <<: [{ a: &a { A: 1 } }, *a], b: B }", null, Options { merge: true });
        expect_toEqual(res, { "a": { "A": 1 }, "A": 1, "b": "B" })
      }
    }

    testset "create" {
      test "simple case" {
        let doc = parseDocument("[{ a: A }, { b: B }]", Options { merge: true });
        let merge = doc.createMergePair({ "c": "C" }, null);
        tanc_map(tanc_seq(doc.value).items[1]).set(merge, null);
        expect_toMatchObject(doc.toJS(null), [{ "a": "A" }, { "b": "B", "c": "C" }]);
        expect_toBe(doc.toString(null), "[ { a: A }, { b: B, <<: { c: C } } ]\n")
      }

      test "using customTags:[\"merge\"]" {
        let doc = parseDocument("[{ a: A }, { b: B }]", Options { customTags: ["merge"] });
        let items = tanc_seq(doc.value).items;
        let a = tanc_map(items[0]);
        let b = tanc_map(items[1]);
        let merge = doc.createMergePair(doc.createAlias(a, null), null);
        b.set(merge, null);
        expect_toMatchObject(doc.toJS(null), [{ "a": "A" }, { "a": "A", "b": "B" }]);
        expect_toBe(doc.toString(null), "[ &a1 { a: A }, { b: B, <<: *a1 } ]\n")
      }

      test "merge pair of an alias" {
        let doc = parseDocument("[{ a: A }, { b: B }]", Options { merge: true });
        let items = tanc_seq(doc.value).items;
        let a = tanc_map(items[0]);
        let b = tanc_map(items[1]);
        let alias = doc.createAlias(a, "AA");
        let merge = doc.createMergePair(alias, null);
        b.set(merge, null);
        expect_toMatchObject(doc.toJS(null), [{ "a": "A" }, { "a": "A", "b": "B" }]);
        expect_toThrowNamed(() -> unknown { doc.toJS(Options { maxAliasCount: 0 }) }, "ReferenceError");
        expect_toBe(doc.toString(null), "[ &AA { a: A }, { b: B, <<: *AA } ]\n")
      }

      test "merge pair of an alias to a sequence" {
        let doc = parseDocument("[{ a: A }, [], { b: B }]", Options { merge: true });
        let a = tanc_map(doc.get(0));
        let seq = tanc_seq(doc.get(1));
        let b = tanc_map(doc.get(2));
        seq.anchor = "SEQ";
        seq.push(doc.createAlias(a, "AA"));
        b.set(doc.createMergePair(doc.createAlias(seq, null), null), null);

        expect_toMatchObject(doc.toJS(null), [
          { "a": "A" },
          [{ "a": "A" }],
          { "a": "A", "b": "B" }
        ]);
        expect_toThrowNamed(() -> unknown { doc.toJS(Options { maxAliasCount: 0 }) }, "ReferenceError");
        expect_toBe(doc.toString(null), "[ &AA { a: A }, &SEQ [ *AA ], { b: B, <<: *SEQ } ]\n")
      }

      test "require map node" {
        let doc = parseDocument("[{ a: A }, { b: B }]", Options { merge: true });
        let alias = doc.createAlias(tanc_node(tanc_map(doc.get(0)).get("a")), null);
        tanc_map(doc.get(1)).set(doc.createMergePair(alias, null), null);
        expect_toBe(doc.toString(null), "[ { a: &a1 A }, { b: B, <<: *a1 } ]\n");
        expect_toThrow(() -> unknown { doc.toJS(null) }, "Merge sources must be maps or map aliases")
      }
    }

    testset "merge multiple times" {
      let srcKeys = "
x:
  - &a
    k0: v1
    k1: v1
  - &b
    k1: v2
    k2: v2
y:
  k0: v0
  <<: *a
  <<: *b";

      let srcSeq = "
x:
  - &a
    k0: v1
    k1: v1
  - &b
    k1: v2
    k2: v2
y:
  k0: v0
  <<: [ *a, *b ]";

      let expObj = {
        "x": [
          { "k0": "v1", "k1": "v1" },
          { "k1": "v2", "k2": "v2" }
        ],
        "y": { "k0": "v0", "k1": "v1", "k2": "v2" }
      };

      let expMap = tanc_exp_map();

      test "multiple merge keys, masAsMap: false" {
        let res = parse(srcKeys, null, Options { merge: true });
        expect_toEqual(res, expObj)
      }

      test "multiple merge keys, masAsMap: true" {
        let res = parse(srcKeys, null, Options { merge: true, mapAsMap: true });
        expect_toEqual(res, expMap)
      }

      test "sequence of anchors, masAsMap: false" {
        let res = parse(srcSeq, null, Options { merge: true });
        expect_toEqual(res, expObj)
      }

      test "sequence of anchors, masAsMap: true" {
        let res = parse(srcSeq, null, Options { merge: true, mapAsMap: true });
        expect_toEqual(res, expMap)
      }
    }

    test "do not throw error when key is null" {
      let src2 = ": 123";
      expect_not_toThrow(() -> unknown { parse(src2, null, Options { merge: true }) })
    }

    test "merge with circular reference" {
      let src2 = "- &a { a: *a, b: B }\n- { <<: *a, b: X }\n";
      let res = parse(src2, null, Options { merge: true });
      let res0 = tanc_at(res, 0);
      let res1a = t_prop(tanc_at(res, 1), "a");
      expect_toBe(t_class_name(res1a) == "JsMap", false);
      let exp: unknown[] = [
        { "a": res0, "b": "B" },
        { "a": res0, "b": "X" }
      ];
      expect_toEqual(res, exp)
    }

    testset "parse errors" {
      test "non-alias merge value" {
        let src2 = "{ <<: A, B: b }";
        expect_toThrow(() -> unknown { parse(src2, null, Options { merge: true }) }, "Merge sources must be maps or map aliases")
      }

      test "non-map alias" {
        let src2 = "- &A a\n- { <<: *A, B: b }";
        expect_toThrow(() -> unknown { parse(src2, null, Options { merge: true }) }, "Merge sources must be maps or map aliases")
      }

      test "immediate non-map merge value" {
        let src2 = "{ <<: [ [42] ], a: A }";
        expect_toThrow(() -> unknown { parse(src2, null, Options { merge: true }) }, "Merge sources must be maps or map aliases")
      }

      test "missing whitespace" {
        expect_toThrow(() -> unknown { parse("&a{}", null, null) }, "Tags and anchors must be separated from the next token by white space")
      }
    }

    testset "stringify" {
      test "example" {
        let doc = parseDocument(src, Options { merge: true });
        expect_toMatchObject(parse(doc.toString(null), null, Options { merge: true }), [
          { "x": 1, "y": 2 },
          { "x": 0, "y": 2 },
          { "r": 10 },
          { "r": 1 },
          { "label": "center/big", "r": 10, "x": 1, "y": 2 },
          { "label": "center/big", "r": 10, "x": 1, "y": 2 },
          { "label": "center/big", "r": 10, "x": 1, "y": 2 },
          { "label": "center/big", "r": 10, "x": 1, "y": 2 }
        ])
      }
    }
  }
}
