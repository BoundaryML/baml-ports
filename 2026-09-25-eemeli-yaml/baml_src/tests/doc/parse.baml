// Port of tests/doc/parse.ts
//
// NOTE: BAML backtick literals are already dedented and have their leading and
// trailing newline trimmed, so `source(`…`)` lacks the trailing "\n" that the
// upstream template tag keeps; it is appended explicitly where it matters.
// Plain (non-`source`) template literals whose exact whitespace matters are
// written as ordinary "…\n…" strings instead.

function tpar_scalar(x: unknown) -> Scalar {
  match (x) {
    let s: Scalar => s,
    _ => fail("expected a Scalar, got " + t_show(x)),
  }
}

function tpar_map(x: unknown) -> YAMLMap {
  match (x) {
    let m: YAMLMap => m,
    _ => fail("expected a YAMLMap, got " + t_show(x)),
  }
}

/// `Object.keys(obj)`
function tpar_keys(v: unknown) -> string[] {
  let o = js_as_object(v);
  if (o == null) {
    return [];
  }
  o.keys()
}

/// `'x'.repeat(n)`
function tpar_repeat(s: string, n: int) -> string {
  s.repeat(n)
}

/// `Array.from(v)`: arrays are copied, Sets give their values, Maps their
/// `[key, value]` entries, and plain objects (no `length`) an empty array.
function tpar_array_from(v: unknown) -> unknown[] {
  match (v) {
    let s: JsSet => {
      let out: unknown[] = [];
      for (let x in s.values()) {
        out.push(x);
      }
      return out;
    },
    _ => {},
  }
  let ent = t_jsmap_entries(v);
  if (ent != null) {
    let out: unknown[] = [];
    let i = 0;
    while (i < ent.keys.length()) {
      let e: unknown[] = [ent.keys[i], ent.values[i]];
      out.push(e);
      i += 1;
    }
    return out;
  }
  let a = js_as_array(v);
  if (a != null) {
    let out: unknown[] = [];
    for (let x in a) {
      out.push(x);
    }
    return out;
  }
  return [];
}

/// `key % 2 === 0` for a string key (JS coerces it to a number)
function tpar_is_even_key(key: unknown) -> bool {
  match (key) {
    let s: string => {
      let n = baml.Int.parse(s) catch (e) { _ => 1 };
      n % 2 == 0
    },
    let i: int => i % 2 == 0,
    _ => false,
  }
}

/// `this[k] = v` on a reviver holder (plain object, array or Map)
function tpar_holder_set(holder: unknown, k: string, v: unknown) -> null {
  match (holder) {
    let o: map<string, unknown> => {
      o.set(k, v);
    },
    let m: JsMap<unknown> => {
      m.set(k, v);
    },
    _ => {},
  }
  null
}

/// `this['']` on the top-level reviver holder
function tpar_holder_root(holder: unknown) -> unknown {
  match (holder) {
    let o: map<string, unknown> => o.get(""),
    _ => null,
  }
}

testset "doc/parse" {
  testset "scalars" {
    test "empty block scalar at end of document" {
      let docs = parseAllDocuments("|\n---\nfoo", null).docs;
      expect_toMatchObject(docs.map((doc: Document) -> unknown { doc.toJS(null) }), ["", "foo"])
    }

    test "carriage returns in double-quotes" {
      let src_ = "\"a\nb\n\rc\n\r\nd\n\r\n\re\n\r\n\r\nf\"";
      expect_toBe(yaml_parse(src_), "a b \rc\nd\n\re\n\nf")
    }
  }

  testset "indented block sequence (#10)" {
    test "reported" {
      let src_ = "\naliases:\n  - restore_cache:\n      - v1-yarn-cache\n  - save_cache:\n      paths:\n        - ~/.cache/yarn\n  - &restore_deps_cache\n    keys:\n      - v1-deps-cache-{{ checksum \"yarn.lock\" }}\n";
      let docs = parseAllDocuments(src_, null).docs;
      expect_toHaveLength(docs, 1);
      expect_toHaveLength(docs[0].errors, 0)
    }

    test "complete file" {
      let src_ = readArtifact("prettier-circleci-config.yml");
      let doc = parseDocument(src_, null);
      let dockerNode9: map<string, unknown> = {
        "docker": [{ "image": "circleci/node:9" }],
        "working_directory": "~/prettier",
      };
      expect_toMatchObject(doc.toJS(null), {
        "aliases": [
          { "restore_cache": { "keys": ["v1-yarn-cache"] } },
          { "save_cache": { "key": "v1-yarn-cache", "paths": ["~/.cache/yarn"] } },
          { "restore_cache": { "keys": ["v1-deps-cache-{{ checksum \"yarn.lock\" }}"] } },
          {
            "save_cache": {
              "key": "v1-yarn-deps-{{ checksum \"yarn.lock\" }}",
              "paths": ["node_modules"],
            },
          },
          dockerNode9,
        ],
        "jobs": {
          "build_prod": {
            "<<": dockerNode9,
            "environment": { "NODE_ENV": "production" },
            "steps": [
              { "attach_workspace": { "at": "~/prettier" } },
              { "run": "yarn build" },
              { "persist_to_workspace": { "paths": ["dist"], "root": "." } },
              { "store_artifacts": { "path": "~/prettier/dist" } },
            ],
          },
          "checkout_code": {
            "<<": dockerNode9,
            "steps": [
              "checkout",
              { "restore_cache": { "keys": ["v1-yarn-cache"] } },
              { "restore_cache": { "keys": ["v1-deps-cache-{{ checksum \"yarn.lock\" }}"] } },
              { "run": "yarn install" },
              { "run": "yarn check-deps" },
              {
                "save_cache": {
                  "key": "v1-yarn-deps-{{ checksum \"yarn.lock\" }}",
                  "paths": ["node_modules"],
                },
              },
              { "save_cache": { "key": "v1-yarn-cache", "paths": ["~/.cache/yarn"] } },
              { "persist_to_workspace": { "paths": ["."], "root": "." } },
            ],
          },
          "test_prod_node4": {
            "<<": dockerNode9,
            "docker": [{ "image": "circleci/node:4" }],
            "steps": [
              { "attach_workspace": { "at": "~/prettier" } },
              { "run": "yarn test:dist" },
            ],
          },
          "test_prod_node9": {
            "<<": dockerNode9,
            "steps": [
              { "attach_workspace": { "at": "~/prettier" } },
              { "run": "yarn test:dist" },
            ],
          },
        },
        "version": 2,
        "workflows": {
          "prod": {
            "jobs": [
              "checkout_code",
              { "build_prod": { "requires": ["checkout_code"] } },
              { "test_prod_node4": { "requires": ["build_prod"] } },
              { "test_prod_node9": { "requires": ["build_prod"] } },
            ],
          },
          "version": 2,
        },
      });
      let exp = src_.replace_all(re("\\r\\n"), "\n"); // To account for git core.autocrlf true on Windows
      expect_toBe(doc.toString(null), exp)
    }

    test "minimal" {
      let src_ = "\n  - a\n  - b:\n    - c\n  - d";
      let docs = parseAllDocuments(src_, null).docs;
      expect_toHaveLength(docs[0].errors, 0);
      expect_toMatchObject(docs[0].toJS(null), ["a", { "b": ["c"] }, "d"])
    }
  }

  test "buffer as source (#459)" {
    // UNPORTABLE: passes a Node.js Buffer (readFile without an encoding) where
    // a string is expected, to check the runtime "source is not a string"
    // TypeError. BAML's static types make `parseDocument(buffer)` a compile
    // error, so the runtime check cannot be exercised.
    null
  }

  test "long scalar value in flow map (#36)" {
    expect_not_toThrow(() -> unknown { yaml_parse("{ x: " + tpar_repeat("x", 1024) + " }") })
  }

  testset "flow collection keys" {
    test "block map with flow collection key as explicit key" {
      let doc = parseDocument("? []: x", null);
      expect_toHaveLength(doc.errors, 0);
      expect_toMatchObject(doc.value, _map([[_map([[_seq([]), "x"]], null), null]], null));
      for (let outer in tpar_map(doc.value).pairs()) {
        for (let inner in tpar_map(outer.key).pairs()) {
          expect_toMatchObject(inner.key, { "flow": true });
        }
      }
    }

    test "flow collection as first block map key (redhat-developer/vscode-yaml#712)" {
      let doc = parseDocument(source(`
        a:
          []: b
          c: d
      `) + "\n", null);
      expect_toHaveLength(doc.errors, 0);
      expect_toMatchObject(doc.value, _map({
        "a": _map([
          [_seq([]), "b"],
          ["c", "d"],
        ], null),
      }, null))
    }

    test "flow collection as second block map key (redhat-developer/vscode-yaml#712)" {
      let doc = parseDocument(source(`
        x: y
        a:
          []: b
          c: d
      `) + "\n", null);
      expect_toHaveLength(doc.errors, 0);
      expect_toMatchObject(doc.value, _map({
        "x": "y",
        "a": _map([
          [_seq([]), "b"],
          ["c", "d"],
        ], null),
      }, null))
    }

    test "flow collection key after a blank line (#646)" {
      let doc = parseDocument("1: 2\n\n[3]: 4", null);
      expect_toHaveLength(doc.errors, 0);
      expect_toMatchObject(doc.value, _map([
        [1, 2],
        [_seq([3]), 4],
      ], null))
    }

    test "flow collection key after a comment line (#646)" {
      let doc = parseDocument("1: 2\n# c\n[3]: 4", null);
      expect_toHaveLength(doc.errors, 0);
      expect_toMatchObject(doc.value, _map([
        [1, 2],
        [_seq([3]), 4],
      ], null))
    }

    test "flow collection key after an empty explicit key (#646)" {
      let doc = parseDocument("?\n[3]: 4", null);
      expect_toHaveLength(doc.errors, 0);
      expect_toMatchObject(doc.value, _map([
        [null, { "key": { "value": null }, "value": null }],
        [_seq([3]), 4],
      ], null))
    }

    test "empty scalar as last flow collection value (#550)" {
      let doc = parseDocument("{c:}", null);
      expect_toMatchObject(doc.value, _map({ "c": { "value": null } }, null))
    }

    test "plain key with no space before flow collection value (#550)" {
      let doc = parseDocument("{c:[]}", null);
      expect_toMatchObject(doc.value, _map({ "c": _seq([]) }, null))
    }
  }

  test "indented block sequnce with inner block sequence (#38)" {
    let src_ = "\n  content:\n    arrayOfArray:\n    -\n      - first: John\n        last: Black\n      - first: Brian\n        last: Green\n    -\n      - first: Mark\n        last: Orange\n    -\n      - first: Adam\n        last: Grey\n  ";
    expect_toEqual(yaml_parse(src_), {
      "content": {
        "arrayOfArray": [
          [
            { "first": "John", "last": "Black" },
            { "first": "Brian", "last": "Green" },
          ],
          [{ "first": "Mark", "last": "Orange" }],
          [{ "first": "Adam", "last": "Grey" }],
        ],
      },
    })
  }

  test "stream end after : indicator (#120)" {
    let src_ = "test:\n    - test1: test1\n      test2:";
    expect_toEqual(yaml_parse(src_), {
      "test": [{ "test1": "test1", "test2": null }],
    })
  }

  test "comment between key & : in flow collection (#149)" {
    let src1 = "{\"a\"\n#c\n:1}";
    expect_toEqual(yaml_parse(src1), { "a": 1 });

    let src2 = "{a\n#c\n:1}";
    let doc = parseDocument(src2, null);
    expect_toMatchObject(doc.errors, [{ "code": "MISSING_CHAR" }])
  }

  testset "indented key with anchor (#378)" {
    test "followed by value" {
      let src1 = "&a foo: 1\n&b bar: 2";
      expect_toEqual(yaml_parse(src1), { "foo": 1, "bar": 2 });

      let src2 = " &a foo: 3\n &b bar: 4";
      expect_toEqual(yaml_parse(src2), { "foo": 3, "bar": 4 })
    }

    test "with : on separate line" {
      let src1 = "a: 1\n&b\nc: 2";
      let doc1 = parseDocument(src1, null);
      expect_toMatchObject(doc1.errors, [{ "code": "MULTILINE_IMPLICIT_KEY" }]);

      let src2 = " a: 1\n &b\n : 2";
      let doc2 = parseDocument(src2, null);
      expect_toMatchObject(doc2.errors, [{ "code": "MULTILINE_IMPLICIT_KEY" }])
    }
  }

  testset "empty(ish) nodes" {
    test "empty explicit key (#3)" {
      let src_ = "{ ? : 123 }";
      let doc = parseDocument(src_, null);
      expect_toHaveLength(doc.errors, 0);
      expect_toMatchObject(doc.getPair(null), {
        "key": { "value": null },
        "value": { "value": 123 },
      })
    }

    testset "comment on empty pair value (#19)" {
      test "map" {
        let src_ = "a:\n  # 123";
        let doc = parseDocument(src_, null);
        expect_toBe(doc.toString(null), "a: # 123\n")
      }

      test "seq" {
        let src_ = "- a: # 123";
        let doc = parseDocument(src_, null);
        expect_toBe(doc.toString(null), "- a: # 123\n")
      }
    }

    test "explicit key with empty value (#32)" {
      expect_toEqual(yaml_parse("[ ? ]"), [{ "": null }]);
      expect_toEqual(yaml_parse("[? 123]"), [{ "123": null }]);
      expect_toEqual(yaml_parse("[ 123, ? ]"), [123, { "": null }]);
      expect_toEqual(yaml_parse("[ 123, ? 456 ]"), [123, { "456": null }])
    }

    testset "empty block scalars" {
      test "no body (#34)" {
        expect_toEqual(yaml_parse("|"), "")
      }

      test "whitespace with indents (#313)" {
        expect_toEqual(yaml_parse("|+\n   \n\n     \n"), "\n\n\n")
      }
    }

    test "empty node position" {
      let doc = parseDocument("\r\na: # 123\r\n", null);
      let empty = doc.get("a");
      expect_toEqual(t_prop(empty, "range"), [5, 5, 12])
    }

    test "parse an empty string as null" {
      let value = yaml_parse("");
      expect_toBeNull(value)
    }

    test "parse a non-space WS char as itself" {
      let src_ = chr(0x2002); // en space
      let value = yaml_parse(src_);
      expect_toBe(value, src_)
    }
  }

  test "comment on single-line value in flow map" {
    let src_ = "{a: 1 #c\n}";
    let doc = parseDocument(src_, null);
    expect_toBe(doc.toString(null), "{\n  a: 1 #c\n}\n")
  }

  testset "maps with no values" {
    test "block map" {
      let src_ = "a: null\n? b #c";
      let doc = parseDocument(src_, null);
      expect_toBe(doc.toString(null), "a: null\nb: #c\n  null\n");
      doc.set("b", "x");
      expect_toBe(doc.toString(null), "a: null\nb: #c\n  x\n")
    }

    test "flow map" {
      let src_ = "{\na: null,\n? b\n}";
      let doc = parseDocument(src_, null);
      expect_toBe(doc.toString(null), "{ a: null, b: }\n");
      let pair = doc.getPair("b");
      if (pair == null) {
        fail("missing pair b");
      } else {
        tpar_scalar(pair.key).comment = "c";
      }
      expect_toBe(doc.toString(null), "{\n  a: null,\n  b: #c\n}\n");
      doc.set("b", "x");
      expect_toBe(doc.toString(null), "{\n  a: null,\n  b: #c\n    x\n}\n")
    }

    test "flow map has correct range" {
      let doc = parseDocument("{  }", null);
      expect_toEqual(doc.range, [0, 4, 4])
    }

    test "pair in flow seq has correct range (#573)" {
      let doc = parseDocument("[a:]", null);
      expect_toEqual(doc.range, [0, 4, 4]);
      expect_toEqual(t_prop(doc.get(0), "range"), [1, 3, 3])
    }

    test "implicit scalar key after explicit key with no value" {
      let doc = parseDocument("? - 1\nx:\n", null);
      expect_toMatchObject(doc.value, _map([
        [_seq([1]), null],
        ["x", { "value": null }],
      ], null))
    }

    test "implicit flow collection key after explicit key with no value" {
      let doc = parseDocument("? - 1\n[x]: y\n", null);
      expect_toMatchObject(doc.value, _map([
        [_seq([1]), null],
        [_seq(["x"]), "y"],
      ], null))
    }
  }

  testset "odd indentations" {
    test "Block map with empty explicit key (#551)" {
      let doc = parseDocument("?\n? a", null);
      expect_toHaveLength(doc.errors, 0);
      expect_toMatchObject(doc.value, _map([
        [null, _pair({ "value": null }, null)],
        ["a", null],
      ], null))
    }

    test "Block map with unindented !!null explicit key" {
      let doc = parseDocument("?\n!!null", null);
      expect_true(doc.errors.length() != 0, "expected errors")
    }

    test "unindented block scalar header in mapping value (#553)" {
      let doc = parseDocument("a:\n|\n x", null);
      expect_true(doc.errors.length() != 0, "expected errors")
    }

    test "unindented flow collection in mapping value" {
      let doc = parseDocument("a:\n{x}", null);
      expect_true(doc.errors.length() != 0, "expected errors")
    }

    test "comment after top-level block scalar with indentation indicator (#547)" {
      let doc = parseDocument("|1\n x\n#c", null);
      expect_toHaveLength(doc.errors, 0);
      expect_toMatchObject(doc.value, { "value": "x\n" })
    }

    test "tab after indent spaces for flow-in-block (#604)" {
      let doc = parseDocument("foo:\n \tbar", null);
      expect_toHaveLength(doc.errors, 0);
      expect_toMatchObject(doc.toJS(null), { "foo": "bar" })
    }
  }

  testset "Resource exhaustion attacks" {
    test "Excessive recursion" {
      let depth = 5000;
      let src_ = tpar_repeat("[", depth) + "1" + tpar_repeat("]", depth);
      let doc = parseDocument(src_, null);
      for (let error in doc.errors) {
        expect_toMatchObject(error, { "code": "RESOURCE_EXHAUSTION" });
      }
    }

    testset "Excessive entity expansion attacks" {
      let src1 = readArtifact("pr104/case1.yml");
      let src2 = readArtifact("pr104/case2.yml");
      let srcB = readArtifact("pr104/billion-laughs.yml");
      let srcQ = readArtifact("pr104/quadratic.yml");

      testset "Limit count by default" {
        // for (const [name, src] of [...]) test(name, …)
        test "js-yaml case 1" {
          expect_toThrow(() -> unknown { parse(src1, null, Options { logLevel: "error" }) }, "Excessive alias count")
        }

        test "js-yaml case 2" {
          expect_toThrow(() -> unknown { parse(src2, null, Options { logLevel: "error" }) }, "Excessive alias count")
        }

        test "billion laughs" {
          expect_toThrow(() -> unknown { parse(srcB, null, Options { logLevel: "error" }) }, "Excessive alias count")
        }

        test "quadratic expansion" {
          expect_toThrow(() -> unknown { parse(srcQ, null, Options { logLevel: "error" }) }, "Excessive alias count")
        }
      }

      testset "Work sensibly even with disabled limits" {
        test "js-yaml case 1" {
          // PARTIAL: upstream also spies on process.emitWarning and expects it
          // to have been called; the port's `warn()` writes to stderr and
          // cannot be intercepted, so that assertion is dropped.
          let obj = parse(src1, null, Options { maxAliasCount: -1 });
          expect_toMatchObject(obj, {});
          let key = tpar_keys(obj)[0];
          expect_true(key.length() > 2000, "expected key.length > 2000");
          expect_true(key.length() < 8000, "expected key.length < 8000")
        }

        test "js-yaml case 2" {
          let arr = parse(src2, null, Options { logLevel: "error", maxAliasCount: -1 });
          expect_toHaveLength(arr, 2);
          let key = tpar_keys(t_prop(arr, "1"))[0];
          expect_toBe(key, "*id057")
        }

        test "billion laughs" {
          let obj = parse(srcB, null, Options { maxAliasCount: -1 });
          expect_toHaveLength(tpar_keys(obj), 9)
        }

        test "quadratic expansion" {
          let obj = parse(srcQ, null, Options { maxAliasCount: -1 });
          expect_toHaveLength(tpar_keys(obj), 11)
        }
      }

      testset "maxAliasCount limits" {
        let rows = [
          "a: &a [lol, lol, lol, lol, lol, lol, lol, lol, lol]",
          "b: &b [*a, *a, *a, *a, *a, *a, *a, *a, *a]",
          "c: &c [*b, *b, *b, *b]",
          "d: &d [*c, *c]",
          "e: [*d]",
        ];

        // for (const maxAliasCount of [0, 1]) { … }
        test "depth 0: maxAliasCount 0 passes" {
          expect_not_toThrow(() -> unknown { parse(rows[0], null, Options { maxAliasCount: 0 }) })
        }

        test "depth 1: maxAliasCount 0 fails on first alias" {
          let src_ = rows[0] + "\nb: *a";
          expect_toThrowNamed(() -> unknown { parse(src_, null, Options { maxAliasCount: 0 }) }, "ReferenceError")
        }

        test "depth 0: maxAliasCount 1 passes" {
          expect_not_toThrow(() -> unknown { parse(rows[0], null, Options { maxAliasCount: 1 }) })
        }

        test "depth 1: maxAliasCount 1 fails on first alias" {
          let src_ = rows[0] + "\nb: *a";
          expect_toThrowNamed(() -> unknown { parse(src_, null, Options { maxAliasCount: 1 }) }, "ReferenceError")
        }

        // const limits = [10, 50, 150, 300]
        // for (let i = 0; i < 4; ++i) { const src = rows.slice(0, i + 2).join('\n'); … }
        test "depth 1: maxAliasCount 9 fails" {
          let src_ = rows.slice(0, 2).join("\n");
          expect_toThrowNamed(() -> unknown { parse(src_, null, Options { maxAliasCount: 9 }) }, "ReferenceError")
        }

        test "depth 1: maxAliasCount 10 passes" {
          let src_ = rows.slice(0, 2).join("\n");
          expect_not_toThrow(() -> unknown { parse(src_, null, Options { maxAliasCount: 10 }) })
        }

        test "depth 2: maxAliasCount 49 fails" {
          let src_ = rows.slice(0, 3).join("\n");
          expect_toThrowNamed(() -> unknown { parse(src_, null, Options { maxAliasCount: 49 }) }, "ReferenceError")
        }

        test "depth 2: maxAliasCount 50 passes" {
          let src_ = rows.slice(0, 3).join("\n");
          expect_not_toThrow(() -> unknown { parse(src_, null, Options { maxAliasCount: 50 }) })
        }

        test "depth 3: maxAliasCount 149 fails" {
          let src_ = rows.slice(0, 4).join("\n");
          expect_toThrowNamed(() -> unknown { parse(src_, null, Options { maxAliasCount: 149 }) }, "ReferenceError")
        }

        test "depth 3: maxAliasCount 150 passes" {
          let src_ = rows.slice(0, 4).join("\n");
          expect_not_toThrow(() -> unknown { parse(src_, null, Options { maxAliasCount: 150 }) })
        }

        test "depth 4: maxAliasCount 299 fails" {
          let src_ = rows.slice(0, 5).join("\n");
          expect_toThrowNamed(() -> unknown { parse(src_, null, Options { maxAliasCount: 299 }) }, "ReferenceError")
        }

        test "depth 4: maxAliasCount 300 passes" {
          let src_ = rows.slice(0, 5).join("\n");
          expect_not_toThrow(() -> unknown { parse(src_, null, Options { maxAliasCount: 300 }) })
        }
      }
    }
  }

  test "Anchor for empty node (6KGN)" {
    let src_ = "a: &anchor\nb: *anchor";
    expect_toMatchObject(yaml_parse(src_), { "a": null, "b": null })
  }

  testset "duplicate keys" {
    test "block collection scalars" {
      let doc = parseDocument("foo: 1\nbar: 2\nfoo: 3\n", null);
      expect_toMatchObject(doc.errors, [{ "code": "DUPLICATE_KEY" }])
    }

    test "flow collection scalars" {
      let doc = parseDocument("{ foo: 1, bar: 2, foo: 3 }\n", null);
      expect_toMatchObject(doc.errors, [{ "code": "DUPLICATE_KEY" }])
    }

    test "merge key (disabled)" {
      let doc = parseDocument("<<: 1\nbar: 2\n<<: 3\n", Options { merge: false });
      expect_toMatchObject(doc.errors, [{ "code": "DUPLICATE_KEY" }])
    }

    test "disable with option" {
      let doc = parseDocument("foo: 1\nbar: 2\nfoo: 3\n", Options {
        mapKey: (k: unknown) -> unknown { js_symbol("") },
      });
      expect_toMatchObject(doc.errors, [])
    }

    test "customise with option" {
      let doc = parseDocument("foo: 1\nbar: 2\nfoo: 3\n", Options {
        mapKey: (k: unknown) -> unknown { true },
      });
      expect_toMatchObject(doc.errors, [
        { "code": "DUPLICATE_KEY" },
        { "code": "DUPLICATE_KEY" },
      ])
    }
  }

  // PARTIAL: upstream spies on process.emitWarning / console.warn (vi.spyOn)
  // and asserts whether it was called. The port's `warn()` (src/log.baml)
  // writes to stderr and has no hook, so the mock assertions are dropped; the
  // remaining observable behaviour is still checked.
  testset "handling complex keys" {
    test "emit warning when casting key in collection to string as JS Object key" {
      let doc = parseDocument("[foo]: bar", Options { prettyErrors: false });
      expect_toHaveLength(doc.warnings, 0);
      // expect(mockWarn).not.toHaveBeenCalled()
      doc.toJS(null);
      // expect(mockWarn).toHaveBeenCalledTimes(1)
      // expect(mockWarn.mock.calls[0][0]).toMatch(/^Keys with collection values will be stringified due to JS Object restrictions/)
      null
    }

    test "do not add warning when using mapIsMap: true" {
      let doc = parseDocument("[foo]: bar", null);
      doc.toJS(Options { mapAsMap: true });
      expect_toMatchObject(doc.warnings, [])
      // expect(mockWarn).not.toHaveBeenCalled()
    }

    test "warn when casting key in collection to string" {
      let obj = yaml_parse("[foo]: bar");
      expect_toMatchObject(tpar_keys(obj), ["[ foo ]"])
      // expect(mockWarn).toHaveBeenCalled()
    }

    test "warn when casting key in sequence to string" {
      let obj = yaml_parse("[ [foo]: bar ]");
      expect_toMatchObject(obj, [{ "[ foo ]": "bar" }])
      // expect(mockWarn).toHaveBeenCalled()
    }

    test "Error on unresolved !!binary node with mapAsMap: false (#610)" {
      let doc = parseDocument("? ? !!binary ? !!binary", null);
      expect_toMatchObject(doc.warnings, [{ "code": "BAD_COLLECTION_TYPE" }]);
      doc.toJS(null);
      // expect(mockWarn).toHaveBeenCalled()
      null
    }

    test "Error on unresolved !!timestamp node with mapAsMap: false (#610)" {
      let doc = parseDocument("? ? !!timestamp ? !!timestamp 2025-03-15T15:35:58.586Z", null);
      expect_toMatchObject(doc.warnings, [{ "code": "BAD_COLLECTION_TYPE" }]);
      doc.toJS(null);
      // expect(mockWarn).toHaveBeenCalled()
      null
    }
  }

  test "Document.toJS({ onAnchor })" {
    let src_ = "foo: &a [&v foo]\nbar: *a\nbaz: *a\n";
    let doc = parseDocument(src_, null);
    let onAnchor = mock_calls();
    let res = doc.toJS(Options {
      onAnchor: (value: unknown, count: int) -> void { onAnchor.record([value, count]); },
    });
    expect_toMatchObject(onAnchor.calls, [
      [t_prop(res, "foo"), 3],
      ["foo", 1],
    ])
  }

  testset "__proto__ as mapping key" {
    test "plain object" {
      let src_ = "{ __proto__: [42] }";
      let obj = yaml_parse(src_);
      expect_toBe(js_is_array(obj), false);
      expect_toBe(js_as_object(obj)?.has("__proto__"), true);
      expect_not_toHaveProperty(obj, "length");
      expect_toBe(json_stringify(obj), "{\"__proto__\":[42]}")
    }

    test "with merge key" {
      let src_ = "- &A { __proto__: [42] }\n- { <<: *A }\n";
      let obj = parse(src_, null, Options { merge: true });
      expect_toBe(js_as_object(t_prop(obj, "0"))?.has("__proto__"), true);
      expect_toBe(js_as_object(t_prop(obj, "1"))?.has("__proto__"), true);
      expect_toBe(json_stringify(obj), "[{\"__proto__\":[42]},{\"__proto__\":[42]}]")
    }
  }

  testset "keepSourceTokens" {
    // for (const [src, type] of [['foo: bar', 'block-map'], ['{ foo: bar }', 'flow-collection']]) { … }
    test "block-map: default false" {
      let doc = parseDocument("foo: bar", null);
      expect_not_toHaveProperty(doc.value, "srcToken");
      expect_not_toHaveProperty(doc.getPair("foo"), "srcToken");
      expect_not_toHaveProperty(doc.get("foo"), "srcToken")
    }

    test "block-map: included when set" {
      let doc = parseDocument("foo: bar", Options { keepSourceTokens: true });
      expect_toMatchObject(t_prop(doc.value, "srcToken"), { "type": "block-map" });
      expect_toMatchObject(t_prop(doc.getPair("foo"), "srcToken"), {
        "key": { "type": "scalar" },
        "value": { "type": "scalar" },
      });
      expect_toMatchObject(t_prop(doc.get("foo"), "srcToken"), { "type": "scalar" })
    }

    test "flow-collection: default false" {
      let doc = parseDocument("{ foo: bar }", null);
      expect_not_toHaveProperty(doc.value, "srcToken");
      expect_not_toHaveProperty(doc.getPair("foo"), "srcToken");
      expect_not_toHaveProperty(doc.get("foo"), "srcToken")
    }

    test "flow-collection: included when set" {
      let doc = parseDocument("{ foo: bar }", Options { keepSourceTokens: true });
      expect_toMatchObject(t_prop(doc.value, "srcToken"), { "type": "flow-collection" });
      expect_toMatchObject(t_prop(doc.getPair("foo"), "srcToken"), {
        "key": { "type": "scalar" },
        "value": { "type": "scalar" },
      });
      expect_toMatchObject(t_prop(doc.get("foo"), "srcToken"), { "type": "scalar" })
    }

    test "allow for CST modifications (#903)" {
      let src_ = "foo:\n  [ 42 ]";
      let tokens = new_parser(null).parse(src_);
      let docs = Composer.new(Options { keepSourceTokens: true }).compose(tokens, false, -1);
      let doc = docs[0];
      let node = doc.get("foo");
      let tok = t_prop(node, "srcToken");
      match (tok) {
        let t: Token => {
          setScalarValue(t, "eek", null);
        },
        _ => fail("expected srcToken"),
      }
      let res = tokens.map((t: Token) -> string { cst_stringify(t) }).join("");
      expect_toBe(res, "foo:\n  eek")
    }
  }

  testset "reviver" {
    test "MDN example" {
      let calls = mock_calls();
      let instances: unknown[] = [];
      let reviver = (_key: unknown, value: unknown, ctx: ReviverContext, holder: unknown) -> unknown {
        calls.record([_key, value, ctx]);
        instances.push(holder);
        value
      };
      let src_ = "{\"1\": 1, \"2\": 2, \"3\": {\"4\": 4, \"5\": {\"6\": 6}}}";
      let obj: map<string, unknown> = { "1": 1, "2": 2, "3": { "4": 4, "5": { "6": 6 } } };
      let obj3: map<string, unknown> = { "4": 4, "5": { "6": 6 } };
      let obj35: map<string, unknown> = { "6": 6 };
      parse(src_, reviver, null);
      expect_toMatchObject(calls.calls, [
        ["1", 1, { "source": "1" }],
        ["2", 2, { "source": "2" }],
        ["4", 4, { "source": "4" }],
        ["6", 6, { "source": "6" }],
        ["5", { "6": 6 }, {}],
        ["3", obj3, {}],
        ["", obj, {}],
      ]);
      expect_toMatchObject(instances, [
        obj,
        obj,
        obj3,
        obj35,
        obj3,
        obj,
        { "": obj },
      ])
    }

    test "modify values" {
      let reviver = (_key: unknown, value: unknown, ctx: ReviverContext, holder: unknown) -> unknown {
        match (value) {
          let i: int => 2 * i,
          let f: float => 2.0 * f,
          _ => value,
        }
      };
      let src_ = "{\"1\": 1, \"2\": 2, \"3\": {\"4\": 4, \"5\": {\"6\": 6}}}";
      expect_toMatchObject(parse(src_, reviver, null), {
        "1": 2,
        "2": 4,
        "3": { "4": 8, "5": { "6": 12 } },
      })
    }

    test "remove values" {
      let reviver = (key: unknown, value: unknown, ctx: ReviverContext, holder: unknown) -> unknown {
        if (key != "" && tpar_is_even_key(key)) { js_undefined() } else { value }
      };
      let src_ = "{\"1\": 1, \"2\": 2, \"3\": {\"4\": 4, \"5\": {\"6\": 6}}}";
      expect_toMatchObject(parse(src_, reviver, null), {
        "1": 1,
        "3": { "5": {} },
      })
    }

    test "add values to this" {
      let reviver = (key: unknown, value: unknown, ctx: ReviverContext, holder: unknown) -> unknown {
        expect_not_toBe(key, "9");
        tpar_holder_set(holder, "9", 9);
        value
      };
      let src_ = "{\"1\": 1, \"2\": 2, \"3\": {\"4\": 4, \"5\": {\"6\": 6}}}";
      expect_toMatchObject(parse(src_, reviver, null), {
        "1": 1,
        "2": 2,
        "3": { "4": 4, "5": { "6": 6, "9": 9 }, "9": 9 },
        "9": 9,
      })
    }

    test "sequence" {
      let these: unknown[][] = [];
      let calls = mock_calls();
      let reviver = (key: unknown, value: unknown, ctx: ReviverContext, holder: unknown) -> unknown {
        calls.record([key, value, ctx]);
        these.push(tpar_array_from(if (key == "") { tpar_holder_root(holder) } else { holder }));
        if (key == "0") {
          return js_undefined();
        }
        if (key == "3") {
          return 10;
        }
        value
      };
      let src_ = "[ 2, 4, 6, 8 ]";
      let seq = parse(src_, reviver, null);
      expect_toBeInstanceOf(seq, "Array");
      expect_toMatchObject(seq, [null, 4, 6, 10]);
      expect_toMatchObject(calls.calls, [
        ["0", 2, { "source": "2" }],
        ["1", 4, { "source": "4" }],
        ["2", 6, { "source": "6" }],
        ["3", 8, { "source": "8" }],
        ["", {}, {}],
      ]);
      expect_toMatchObject(these, [
        [2, 4, 6, 8],
        [null, 4, 6, 8],
        [null, 4, 6, 8],
        [null, 4, 6, 8],
        [null, 4, 6, 10],
      ])
    }

    test "!!set" {
      let these: unknown[][] = [];
      let calls = mock_calls();
      let reviver = (key: unknown, value: unknown, ctx: ReviverContext, holder: unknown) -> unknown {
        calls.record([key, value, ctx]);
        these.push(tpar_array_from(if (key == "") { tpar_holder_root(holder) } else { holder }));
        if (js_same(key, 2)) {
          return js_undefined();
        }
        if (js_same(key, 8)) {
          return 10;
        }
        value
      };
      let src_ = "!!set { 2, 4, 6, 8 }";
      let set = parse(src_, reviver, null);
      expect_toBeInstanceOf(set, "Set");
      expect_toMatchObject(tpar_array_from(set), [4, 6, 10]);
      expect_toMatchObject(calls.calls, [
        [2, 2, { "source": "2" }],
        [4, 4, { "source": "4" }],
        [6, 6, { "source": "6" }],
        [8, 8, { "source": "8" }],
        ["", {}, {}],
      ]);
      expect_toMatchObject(these, [
        [2, 4, 6, 8],
        [4, 6, 8],
        [4, 6, 8],
        [4, 6, 8],
        [4, 6, 10],
      ])
    }

    test "!!omap" {
      let these: unknown[][] = [];
      let calls = mock_calls();
      let reviver = (key: unknown, value: unknown, ctx: ReviverContext, holder: unknown) -> unknown {
        calls.record([key, value, ctx]);
        these.push(tpar_array_from(if (key == "") { tpar_holder_root(holder) } else { holder }));
        if (js_same(key, 2)) {
          return js_undefined();
        }
        if (js_same(key, 8)) {
          return 10;
        }
        value
      };
      let src_ = "!!omap [ 2: 3, 4: 5, 6: 7, 8: 9 ]";
      let map_ = parse(src_, reviver, null);
      expect_toBeInstanceOf(map_, "Map");
      expect_toMatchObject(tpar_array_from(map_), [
        [4, 5],
        [6, 7],
        [8, 10],
      ]);
      expect_toMatchObject(calls.calls, [
        [2, 3, { "source": "3" }],
        [4, 5, { "source": "5" }],
        [6, 7, { "source": "7" }],
        [8, 9, { "source": "9" }],
        ["", map_, {}],
      ]);
      expect_toMatchObject(these, [
        [
          [2, 3],
          [4, 5],
          [6, 7],
          [8, 9],
        ],
        [
          [4, 5],
          [6, 7],
          [8, 9],
        ],
        [
          [4, 5],
          [6, 7],
          [8, 9],
        ],
        [
          [4, 5],
          [6, 7],
          [8, 9],
        ],
        [
          [4, 5],
          [6, 7],
          [8, 10],
        ],
      ])
    }

    test "!!merge simple" {
      let calls = mock_calls();
      let reviver = (_key: unknown, value: unknown, ctx: ReviverContext, holder: unknown) -> unknown {
        calls.record([_key, value, ctx]);
        value
      };
      let src_ = "- &a { a: A, b: B }\n- { <<: *a, b: X }\n";
      parse(src_, null, Options { merge: true, reviver: reviver });
      expect_toMatchObject(calls.calls, [
        ["a", "A", { "source": "A" }],
        ["b", "B", { "source": "B" }],
        ["0", { "a": "A", "b": "B" }, {}],
        ["a", "A", { "source": "A" }],
        ["b", "X", { "source": "X" }],
        ["1", { "a": "A", "b": "X" }, {}],
        [
          "",
          [
            { "a": "A", "b": "B" },
            { "a": "A", "b": "X" },
          ],
          {},
        ],
      ])
    }

    test "!!merge recursion" {
      let calls = mock_calls();
      let reviver = (_key: unknown, value: unknown, ctx: ReviverContext, holder: unknown) -> unknown {
        calls.record([_key, value, ctx]);
        value
      };
      let src_ = "- &a { a: *a, b: B }\n- { <<: *a, b: X }\n";
      let res = parse(src_, null, Options { merge: true, reviver: reviver });
      let aRef = t_prop(res, "0");
      expect_toMatchObject(calls.calls, [
        ["b", "B", { "source": "B" }],
        ["0", { "a": aRef, "b": "B" }, {}],
        ["b", "B", { "source": "B" }],
        ["a", { "a": aRef, "b": "B" }, {}],
        ["b", "X", { "source": "X" }],
        ["1", { "a": { "a": aRef, "b": "B" }, "b": "X" }, {}],
        ["", res, {}],
      ])
    }
  }

  testset "CRLF line endings" {
    test "trailing space in double-quoted scalar" {
      let res = yaml_parse("\"foo \r\nbar\"");
      expect_toBe(res, "foo bar")
    }

    test "escaped newline in double-quoted scalar" {
      let res = yaml_parse("\"foo \\\r\nbar\"");
      expect_toBe(res, "foo bar")
    }
  }

  testset "stringKeys" {
    test "success" {
      let doc = parseDocument(source(`
          x: x
          !!str y: y
          42: 42
          true: true
          null: null
          ~: ~
          :
        `) + "\n", Options { stringKeys: true });
      expect_toMatchObject(doc.value, _map({
        "x": "x",
        "y": "y",
        "42": 42,
        "true": true,
        "null": { "value": null },
        "~": { "value": null },
        "": { "value": null },
      }, null))
    }

    test "explicit non-string tag" {
      let doc = parseDocument("!!int 42: 42", Options { stringKeys: true });
      expect_toMatchObject(doc.errors, [{ "code": "NON_STRING_KEY" }])
    }

    test "collection key" {
      let doc = parseDocument("{ x, y }: 42", Options { stringKeys: true });
      expect_toMatchObject(doc.errors, [{ "code": "NON_STRING_KEY" }])
    }
  }
}
