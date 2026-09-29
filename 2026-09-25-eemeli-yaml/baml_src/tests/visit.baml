// Port of tests/visit.ts
//
// Upstream runs the same describe() body twice, for `visit` and `visitAsync`.
// Here the two testsets are written out separately (BAML has no way to
// abstract over the two functions' different visitor types). In the
// visitAsync() suite every visitor returns a `baml.future.Future` (created
// with `spawn`), which visitAsync awaits -- the BAML counterpart of an async
// visitor returning a Promise.
//
// `expect.any(Document|YAMLMap|YAMLSeq|Pair)` is expressed with the markers
// "DOC" / "MAP" / "SEQ" / "PAIR": recorded paths are converted to markers, and
// a node is converted to its marker when the expected value is a marker.

function tvis_kind(v: unknown) -> string {
  match (v) {
    Document => "DOC",
    YAMLMap => "MAP",
    YAMLSeq => "SEQ",
    Pair => "PAIR",
    _ => "?",
  }
}

/// `vi.fn()` recording `(key, node, path)`.
function tvis_rec(calls: MockCalls, key: VisitKey, node: Node | Pair | null, path: VisitPathItem[]) -> null {
  let p: string[] = [];
  for (let it in path) {
    p.push(tvis_kind(it));
  }
  calls.record([key, node, p])
}

function tvis_is_marker(v: unknown) -> bool {
  v == "DOC" || v == "MAP" || v == "SEQ" || v == "PAIR"
}

/// `expect(fn.mock.calls).toMatchObject(expected)`
function tvis_expect_calls(calls: MockCalls, expected: unknown[][]) -> null {
  let actual: unknown[][] = [];
  let i = 0;
  while (i < calls.calls.length()) {
    let c = calls.calls[i];
    if (i < expected.length() && tvis_is_marker(expected[i][1])) {
      actual.push([c[0], tvis_kind(c[1]), c[2]]);
    } else {
      actual.push(c);
    }
    i += 1;
  }
  expect_toMatchObject(actual, expected)
}

/// `{ Map: fn, Pair: fn, Seq: fn, Alias: fn, Scalar: fn }` (Alias only if `alias`)
function tvis_fns(f: VisitorFn, alias: bool) -> VisitorFns {
  VisitorFns {
    Map: (k: VisitKey, n: YAMLMap | YAMLSet, p: VisitPathItem[]) -> VisitResult throws unknown { f(k, n, p) },
    Pair: (k: VisitKey, n: Pair, p: VisitPathItem[]) -> VisitResult throws unknown { f(k, n, p) },
    Seq: (k: VisitKey, n: YAMLSeq, p: VisitPathItem[]) -> VisitResult throws unknown { f(k, n, p) },
    Alias: if (alias) { (k: VisitKey, n: Alias, p: VisitPathItem[]) -> VisitResult throws unknown { f(k, n, p) } } else { null },
    Scalar: (k: VisitKey, n: Scalar, p: VisitPathItem[]) -> VisitResult throws unknown { f(k, n, p) },
  }
}

function tvis_afns(f: AsyncVisitorFn, alias: bool) -> AsyncVisitorFns {
  AsyncVisitorFns {
    Map: (k: VisitKey, n: YAMLMap | YAMLSet, p: VisitPathItem[]) -> AsyncVisitResult throws unknown { f(k, n, p) },
    Pair: (k: VisitKey, n: Pair, p: VisitPathItem[]) -> AsyncVisitResult throws unknown { f(k, n, p) },
    Seq: (k: VisitKey, n: YAMLSeq, p: VisitPathItem[]) -> AsyncVisitResult throws unknown { f(k, n, p) },
    Alias: if (alias) { (k: VisitKey, n: Alias, p: VisitPathItem[]) -> AsyncVisitResult throws unknown { f(k, n, p) } } else { null },
    Scalar: (k: VisitKey, n: Scalar, p: VisitPathItem[]) -> AsyncVisitResult throws unknown { f(k, n, p) },
  }
}

/// Rethrows its argument if non-null. Used only to give a `spawn` block the
/// error type `unknown`: `Future<T, never>` is not assignable to
/// `Future<T, unknown>` (generic invariance), see notes/tests-visit.md.
function tvis_rethrow(e: unknown) -> null {
  if (e != null) {
    throw e;
  }
  null
}

/// Run `f` in a spawned task: an async visitor result.
function tvis_later(f: () -> VisitResult throws unknown) -> baml.future.Future<VisitResult, unknown> {
  spawn {
    tvis_rethrow(null);
    f()
  }
}

testset "visit" {
  testset "visit()" {
    test "Map" {
      let doc = parseDocument("{ one: 1, two }", null);
      let calls = mock_calls();
      let fn_ = (k: VisitKey, n: Node | Pair | null, p: VisitPathItem[]) -> VisitResult { tvis_rec(calls, k, n, p) };
      visit(doc, tvis_fns(fn_, true));
      tvis_expect_calls(calls, [
        [null, "MAP", ["DOC"]],
        [0, { "key": {}, "value": {} }, ["DOC", "MAP"]],
        ["key", { "type": "PLAIN", "value": "one" }, ["DOC", "MAP", "PAIR"]],
        ["value", { "type": "PLAIN", "value": 1 }, ["DOC", "MAP", "PAIR"]],
        [1, { "key": {}, "value": {} }, ["DOC", "MAP"]],
        ["key", { "type": "PLAIN", "value": "two" }, ["DOC", "MAP", "PAIR"]],
      ])
    }

    test "Seq" {
      let doc = parseDocument("- 1\n- two\n", null);
      let calls = mock_calls();
      let fn_ = (k: VisitKey, n: Node | Pair | null, p: VisitPathItem[]) -> VisitResult { tvis_rec(calls, k, n, p) };
      visit(doc, tvis_fns(fn_, true));
      tvis_expect_calls(calls, [
        [null, "SEQ", ["DOC"]],
        [0, { "type": "PLAIN", "value": 1 }, ["DOC", "SEQ"]],
        [1, { "type": "PLAIN", "value": "two" }, ["DOC", "SEQ"]],
      ])
    }

    test "Alias" {
      let doc = parseDocument("- &a 1\n- *a\n", null);
      let calls = mock_calls();
      let fn_ = (k: VisitKey, n: Node | Pair | null, p: VisitPathItem[]) -> VisitResult { tvis_rec(calls, k, n, p) };
      visit(doc, tvis_fns(fn_, true));
      tvis_expect_calls(calls, [
        [null, "SEQ", ["DOC"]],
        [0, { "type": "PLAIN", "value": 1, "anchor": "a" }, ["DOC", "SEQ"]],
        [1, { "source": "a" }, ["DOC", "SEQ"]],
      ])
    }

    test "Seq in Map" {
      let doc = parseDocument("foo:\n  - \"one\"\n  - 'two'\n", null);
      let calls = mock_calls();
      let fn_ = (k: VisitKey, n: Node | Pair | null, p: VisitPathItem[]) -> VisitResult { tvis_rec(calls, k, n, p) };
      visit(doc, tvis_fns(fn_, true));
      tvis_expect_calls(calls, [
        [null, "MAP", ["DOC"]],
        [0, { "key": {}, "value": {} }, ["DOC", "MAP"]],
        ["key", { "type": "PLAIN", "value": "foo" }, ["DOC", "MAP", "PAIR"]],
        ["value", "SEQ", ["DOC", "MAP", "PAIR"]],
        [0, { "type": "QUOTE_DOUBLE", "value": "one" }, ["DOC", "MAP", "PAIR", "SEQ"]],
        [1, { "type": "QUOTE_SINGLE", "value": "two" }, ["DOC", "MAP", "PAIR", "SEQ"]],
      ])
    }

    test "Visit called with non-Document root" {
      let doc = parseDocument("foo:\n  - \"one\"\n  - 'two'\n", null);
      let calls = mock_calls();
      let fn_ = (k: VisitKey, n: Node | Pair | null, p: VisitPathItem[]) -> VisitResult { tvis_rec(calls, k, n, p) };
      let root = match (doc.get("foo")) {
        let n: Node => n,
        _ => fail("expected a node"),
      };
      visit(root, fn_);
      tvis_expect_calls(calls, [
        [null, "SEQ", []],
        [0, { "type": "QUOTE_DOUBLE", "value": "one" }, ["SEQ"]],
        [1, { "type": "QUOTE_SINGLE", "value": "two" }, ["SEQ"]],
      ])
    }

    test "Visiting a constructed document" {
      let doc = Document.new([1, "two"], null, null);
      let calls = mock_calls();
      let fn_ = (k: VisitKey, n: Node | Pair | null, p: VisitPathItem[]) -> VisitResult { tvis_rec(calls, k, n, p) };
      visit(doc, tvis_fns(fn_, true));
      tvis_expect_calls(calls, [
        [null, "SEQ", ["DOC"]],
        [0, { "value": 1 }, ["DOC", "SEQ"]],
        [1, { "value": "two" }, ["DOC", "SEQ"]],
      ]);
      expect_toBe(doc.toString(null), "- 1\n- two\n")
    }

    test "Only Scalar defined" {
      let doc = parseDocument("foo:\n  - \"one\"\n  - 'two'\n", null);
      let calls = mock_calls();
      visit(doc, VisitorFns {
        Scalar: (k: VisitKey, n: Scalar, p: VisitPathItem[]) -> VisitResult { tvis_rec(calls, k, n, p) },
      });
      tvis_expect_calls(calls, [
        ["key", { "type": "PLAIN", "value": "foo" }, ["DOC", "MAP", "PAIR"]],
        [0, { "type": "QUOTE_DOUBLE", "value": "one" }, ["DOC", "MAP", "PAIR", "SEQ"]],
        [1, { "type": "QUOTE_SINGLE", "value": "two" }, ["DOC", "MAP", "PAIR", "SEQ"]],
      ])
    }

    test "Function as visitor" {
      let doc = parseDocument("{ one: 1, two }", null);
      let calls = mock_calls();
      let fn_ = (k: VisitKey, n: Node | Pair | null, p: VisitPathItem[]) -> VisitResult { tvis_rec(calls, k, n, p) };
      visit(doc, fn_);
      tvis_expect_calls(calls, [
        [null, "MAP", ["DOC"]],
        [0, { "key": {}, "value": {} }, ["DOC", "MAP"]],
        ["key", { "type": "PLAIN", "value": "one" }, ["DOC", "MAP", "PAIR"]],
        ["value", { "type": "PLAIN", "value": 1 }, ["DOC", "MAP", "PAIR"]],
        [1, { "key": {}, "value": {} }, ["DOC", "MAP"]],
        ["key", { "type": "PLAIN", "value": "two" }, ["DOC", "MAP", "PAIR"]],
        ["value", null, ["DOC", "MAP", "PAIR"]],
      ])
    }

    test "Change key value within Pair" {
      let doc = parseDocument("foo:\n  - \"one\"\n  - 'two'\n", null);
      visit(doc, VisitorFns {
        Pair: (_k: VisitKey, pair: Pair, _p: VisitPathItem[]) -> VisitResult {
          {
            match (pair.key) {
              let sc: Scalar => {
                if (sc.value == "foo") {
                  sc.value = "bar";
                }
              },
              _ => {},
            }
            null
          }
        },
      });
      expect_toBe(doc.toString(null), "bar:\n  - \"one\"\n  - 'two'\n")
    }

    test "Change key value within Scalar" {
      let doc = parseDocument("foo:\n  - \"one\"\n  - 'two'\n", null);
      visit(doc, VisitorFns {
        Scalar: (key: VisitKey, node: Scalar, _p: VisitPathItem[]) -> VisitResult {
          {
            if (key == "key" && node.value == "foo") {
              node.value = "bar";
            }
            null
          }
        },
      });
      expect_toBe(doc.toString(null), "bar:\n  - \"one\"\n  - 'two'\n")
    }

    test "Add item to Seq" {
      let doc = parseDocument("- one\n- two\n", null);
      let calls = mock_calls();
      visit(doc, VisitorFns {
        Seq: (_k: VisitKey, seq: YAMLSeq, _p: VisitPathItem[]) -> VisitResult {
          {
            seq.push(doc.createNode("three", null, null));
            null
          }
        },
        Scalar: (k: VisitKey, n: Scalar, p: VisitPathItem[]) -> VisitResult { tvis_rec(calls, k, n, p) },
      });
      tvis_expect_calls(calls, [
        [0, { "type": "PLAIN", "value": "one" }, ["DOC", "SEQ"]],
        [1, { "type": "PLAIN", "value": "two" }, ["DOC", "SEQ"]],
        [2, { "value": "three" }, ["DOC", "SEQ"]],
      ]);
      expect_toBe(doc.toString(null), "- one\n- two\n- three\n")
    }

    test "Do not visit block seq items" {
      let doc = parseDocument("foo:\n  - one\n  - two\nbar:\n", null);
      let calls = mock_calls();
      let fn_ = (k: VisitKey, n: Node | Pair | null, p: VisitPathItem[]) -> VisitResult {
        {
          tvis_rec(calls, k, n, p);
          let r: VisitResult = match (n) {
            YAMLSeq => visit_SKIP(),
            _ => null,
          };
          r
        }
      };
      visit(doc, tvis_fns(fn_, false));
      tvis_expect_calls(calls, [
        [null, "MAP", ["DOC"]],
        [0, { "key": {}, "value": {} }, ["DOC", "MAP"]],
        ["key", { "type": "PLAIN", "value": "foo" }, ["DOC", "MAP", "PAIR"]],
        ["value", "SEQ", ["DOC", "MAP", "PAIR"]],
        [1, { "key": {}, "value": {} }, ["DOC", "MAP"]],
        ["key", { "type": "PLAIN", "value": "bar" }, ["DOC", "MAP", "PAIR"]],
        ["value", { "type": "PLAIN", "value": null }, ["DOC", "MAP", "PAIR"]],
      ])
    }

    test "Break visit on command" {
      let doc = parseDocument("- one\n- two\n- three\n", null);
      let calls = mock_calls();
      visit(doc, VisitorFns {
        Scalar: (k: VisitKey, node: Scalar, p: VisitPathItem[]) -> VisitResult {
          {
            tvis_rec(calls, k, node, p);
            let r: VisitResult = if (node.value == "two") { visit_BREAK() } else { null };
            r
          }
        },
      });
      tvis_expect_calls(calls, [
        [0, { "type": "PLAIN", "value": "one" }, ["DOC", "SEQ"]],
        [1, { "type": "PLAIN", "value": "two" }, ["DOC", "SEQ"]],
      ])
    }

    test "Modify seq item" {
      let doc = parseDocument("- one\n- two\n- three\n", null);
      let calls = mock_calls();
      visit(doc, VisitorFns {
        Scalar: (k: VisitKey, node: Scalar, p: VisitPathItem[]) -> VisitResult {
          {
            tvis_rec(calls, k, node, p);
            let r: VisitResult = if (node.value == "two") { doc.createNode(42, null, null) } else { null };
            r
          }
        },
      });
      tvis_expect_calls(calls, [
        [0, { "type": "PLAIN", "value": "one" }, ["DOC", "SEQ"]],
        [1, { "type": "PLAIN", "value": "two" }, ["DOC", "SEQ"]],
        [1, { "value": 42 }, ["DOC", "SEQ"]],
        [2, { "type": "PLAIN", "value": "three" }, ["DOC", "SEQ"]],
      ]);
      expect_toBe(doc.toString(null), "- one\n- 42\n- three\n")
    }

    test "Skip seq item" {
      let doc = parseDocument("- one\n- two\n- three\n", null);
      let calls = mock_calls();
      visit(doc, VisitorFns {
        Scalar: (key: VisitKey, n: Scalar, p: VisitPathItem[]) -> VisitResult {
          {
            tvis_rec(calls, key, n, p);
            let r: VisitResult = if (key == 0) { 2 } else { null };
            r
          }
        },
      });
      tvis_expect_calls(calls, [
        [0, { "type": "PLAIN", "value": "one" }, ["DOC", "SEQ"]],
        [2, { "type": "PLAIN", "value": "three" }, ["DOC", "SEQ"]],
      ])
    }

    test "Remove seq item" {
      let doc = parseDocument("- one\n- two\n- three\n", null);
      let calls = mock_calls();
      visit(doc, VisitorFns {
        Scalar: (k: VisitKey, node: Scalar, p: VisitPathItem[]) -> VisitResult {
          {
            tvis_rec(calls, k, node, p);
            let r: VisitResult = if (node.value == "two") { visit_REMOVE() } else { null };
            r
          }
        },
      });
      tvis_expect_calls(calls, [
        [0, { "type": "PLAIN", "value": "one" }, ["DOC", "SEQ"]],
        [1, { "type": "PLAIN", "value": "two" }, ["DOC", "SEQ"]],
        [1, { "type": "PLAIN", "value": "three" }, ["DOC", "SEQ"]],
      ]);
      expect_toBe(doc.toString(null), "- one\n- three\n")
    }

    test "Remove map value" {
      let doc = parseDocument("one: 1\ntwo: 2\n", null);
      let calls = mock_calls();
      visit(doc, VisitorFns {
        Scalar: (key: VisitKey, node: Scalar, p: VisitPathItem[]) -> VisitResult {
          {
            tvis_rec(calls, key, node, p);
            let r: VisitResult = if (key == "value" && node.value == 2) { visit_REMOVE() } else { null };
            r
          }
        },
      });
      tvis_expect_calls(calls, [
        ["key", { "type": "PLAIN", "value": "one" }, ["DOC", "MAP", "PAIR"]],
        ["value", { "type": "PLAIN", "value": 1 }, ["DOC", "MAP", "PAIR"]],
        ["key", { "type": "PLAIN", "value": "two" }, ["DOC", "MAP", "PAIR"]],
        ["value", { "type": "PLAIN", "value": 2 }, ["DOC", "MAP", "PAIR"]],
      ]);
      expect_toBe(doc.toString(null), "one: 1\ntwo: null\n")
    }

    test "Fail to replace root node" {
      let doc = parseDocument("- one\n- two\n- three\n", null);
      let root: Node = doc.value;
      let seqFn = VisitorFns {
        Seq: (_k: VisitKey, _n: YAMLSeq, _p: VisitPathItem[]) -> VisitResult {
          {
            let r: VisitResult = doc.createNode(42, null, null);
            r
          }
        },
      };
      expect_toThrow(() -> unknown { visit(root, seqFn) }, "Cannot replace node with scalar parent")
    }
  }

  testset "visitAsync()" {
    test "Map" {
      let doc = parseDocument("{ one: 1, two }", null);
      let calls = mock_calls();
      let fn_ = (k: VisitKey, n: Node | Pair | null, p: VisitPathItem[]) -> AsyncVisitResult { tvis_later(() -> VisitResult { tvis_rec(calls, k, n, p) }) };
      visitAsync(doc, tvis_afns(fn_, true));
      tvis_expect_calls(calls, [
        [null, "MAP", ["DOC"]],
        [0, { "key": {}, "value": {} }, ["DOC", "MAP"]],
        ["key", { "type": "PLAIN", "value": "one" }, ["DOC", "MAP", "PAIR"]],
        ["value", { "type": "PLAIN", "value": 1 }, ["DOC", "MAP", "PAIR"]],
        [1, { "key": {}, "value": {} }, ["DOC", "MAP"]],
        ["key", { "type": "PLAIN", "value": "two" }, ["DOC", "MAP", "PAIR"]],
      ])
    }

    test "Seq" {
      let doc = parseDocument("- 1\n- two\n", null);
      let calls = mock_calls();
      let fn_ = (k: VisitKey, n: Node | Pair | null, p: VisitPathItem[]) -> AsyncVisitResult { tvis_later(() -> VisitResult { tvis_rec(calls, k, n, p) }) };
      visitAsync(doc, tvis_afns(fn_, true));
      tvis_expect_calls(calls, [
        [null, "SEQ", ["DOC"]],
        [0, { "type": "PLAIN", "value": 1 }, ["DOC", "SEQ"]],
        [1, { "type": "PLAIN", "value": "two" }, ["DOC", "SEQ"]],
      ])
    }

    test "Alias" {
      let doc = parseDocument("- &a 1\n- *a\n", null);
      let calls = mock_calls();
      let fn_ = (k: VisitKey, n: Node | Pair | null, p: VisitPathItem[]) -> AsyncVisitResult { tvis_later(() -> VisitResult { tvis_rec(calls, k, n, p) }) };
      visitAsync(doc, tvis_afns(fn_, true));
      tvis_expect_calls(calls, [
        [null, "SEQ", ["DOC"]],
        [0, { "type": "PLAIN", "value": 1, "anchor": "a" }, ["DOC", "SEQ"]],
        [1, { "source": "a" }, ["DOC", "SEQ"]],
      ])
    }

    test "Seq in Map" {
      let doc = parseDocument("foo:\n  - \"one\"\n  - 'two'\n", null);
      let calls = mock_calls();
      let fn_ = (k: VisitKey, n: Node | Pair | null, p: VisitPathItem[]) -> AsyncVisitResult { tvis_later(() -> VisitResult { tvis_rec(calls, k, n, p) }) };
      visitAsync(doc, tvis_afns(fn_, true));
      tvis_expect_calls(calls, [
        [null, "MAP", ["DOC"]],
        [0, { "key": {}, "value": {} }, ["DOC", "MAP"]],
        ["key", { "type": "PLAIN", "value": "foo" }, ["DOC", "MAP", "PAIR"]],
        ["value", "SEQ", ["DOC", "MAP", "PAIR"]],
        [0, { "type": "QUOTE_DOUBLE", "value": "one" }, ["DOC", "MAP", "PAIR", "SEQ"]],
        [1, { "type": "QUOTE_SINGLE", "value": "two" }, ["DOC", "MAP", "PAIR", "SEQ"]],
      ])
    }

    test "Visit called with non-Document root" {
      let doc = parseDocument("foo:\n  - \"one\"\n  - 'two'\n", null);
      let calls = mock_calls();
      let fn_ = (k: VisitKey, n: Node | Pair | null, p: VisitPathItem[]) -> AsyncVisitResult { tvis_later(() -> VisitResult { tvis_rec(calls, k, n, p) }) };
      let root = match (doc.get("foo")) {
        let n: Node => n,
        _ => fail("expected a node"),
      };
      visitAsync(root, fn_);
      tvis_expect_calls(calls, [
        [null, "SEQ", []],
        [0, { "type": "QUOTE_DOUBLE", "value": "one" }, ["SEQ"]],
        [1, { "type": "QUOTE_SINGLE", "value": "two" }, ["SEQ"]],
      ])
    }

    test "Visiting a constructed document" {
      let doc = Document.new([1, "two"], null, null);
      let calls = mock_calls();
      let fn_ = (k: VisitKey, n: Node | Pair | null, p: VisitPathItem[]) -> AsyncVisitResult { tvis_later(() -> VisitResult { tvis_rec(calls, k, n, p) }) };
      visitAsync(doc, tvis_afns(fn_, true));
      tvis_expect_calls(calls, [
        [null, "SEQ", ["DOC"]],
        [0, { "value": 1 }, ["DOC", "SEQ"]],
        [1, { "value": "two" }, ["DOC", "SEQ"]],
      ]);
      expect_toBe(doc.toString(null), "- 1\n- two\n")
    }

    test "Only Scalar defined" {
      let doc = parseDocument("foo:\n  - \"one\"\n  - 'two'\n", null);
      let calls = mock_calls();
      visitAsync(doc, AsyncVisitorFns {
        Scalar: (k: VisitKey, n: Scalar, p: VisitPathItem[]) -> AsyncVisitResult { tvis_later(() -> VisitResult { tvis_rec(calls, k, n, p) }) },
      });
      tvis_expect_calls(calls, [
        ["key", { "type": "PLAIN", "value": "foo" }, ["DOC", "MAP", "PAIR"]],
        [0, { "type": "QUOTE_DOUBLE", "value": "one" }, ["DOC", "MAP", "PAIR", "SEQ"]],
        [1, { "type": "QUOTE_SINGLE", "value": "two" }, ["DOC", "MAP", "PAIR", "SEQ"]],
      ])
    }

    test "Function as visitor" {
      let doc = parseDocument("{ one: 1, two }", null);
      let calls = mock_calls();
      let fn_ = (k: VisitKey, n: Node | Pair | null, p: VisitPathItem[]) -> AsyncVisitResult { tvis_later(() -> VisitResult { tvis_rec(calls, k, n, p) }) };
      visitAsync(doc, fn_);
      tvis_expect_calls(calls, [
        [null, "MAP", ["DOC"]],
        [0, { "key": {}, "value": {} }, ["DOC", "MAP"]],
        ["key", { "type": "PLAIN", "value": "one" }, ["DOC", "MAP", "PAIR"]],
        ["value", { "type": "PLAIN", "value": 1 }, ["DOC", "MAP", "PAIR"]],
        [1, { "key": {}, "value": {} }, ["DOC", "MAP"]],
        ["key", { "type": "PLAIN", "value": "two" }, ["DOC", "MAP", "PAIR"]],
        ["value", null, ["DOC", "MAP", "PAIR"]],
      ])
    }

    test "Change key value within Pair" {
      let doc = parseDocument("foo:\n  - \"one\"\n  - 'two'\n", null);
      visitAsync(doc, AsyncVisitorFns {
        Pair: (_k: VisitKey, pair: Pair, _p: VisitPathItem[]) -> AsyncVisitResult {
          tvis_later(() -> VisitResult { {
            match (pair.key) {
              let sc: Scalar => {
                if (sc.value == "foo") {
                  sc.value = "bar";
                }
              },
              _ => {},
            }
            null
          } })
        },
      });
      expect_toBe(doc.toString(null), "bar:\n  - \"one\"\n  - 'two'\n")
    }

    test "Change key value within Scalar" {
      let doc = parseDocument("foo:\n  - \"one\"\n  - 'two'\n", null);
      visitAsync(doc, AsyncVisitorFns {
        Scalar: (key: VisitKey, node: Scalar, _p: VisitPathItem[]) -> AsyncVisitResult {
          tvis_later(() -> VisitResult { {
            if (key == "key" && node.value == "foo") {
              node.value = "bar";
            }
            null
          } })
        },
      });
      expect_toBe(doc.toString(null), "bar:\n  - \"one\"\n  - 'two'\n")
    }

    test "Add item to Seq" {
      let doc = parseDocument("- one\n- two\n", null);
      let calls = mock_calls();
      visitAsync(doc, AsyncVisitorFns {
        Seq: (_k: VisitKey, seq: YAMLSeq, _p: VisitPathItem[]) -> AsyncVisitResult {
          tvis_later(() -> VisitResult { {
            seq.push(doc.createNode("three", null, null));
            null
          } })
        },
        Scalar: (k: VisitKey, n: Scalar, p: VisitPathItem[]) -> AsyncVisitResult { tvis_later(() -> VisitResult { tvis_rec(calls, k, n, p) }) },
      });
      tvis_expect_calls(calls, [
        [0, { "type": "PLAIN", "value": "one" }, ["DOC", "SEQ"]],
        [1, { "type": "PLAIN", "value": "two" }, ["DOC", "SEQ"]],
        [2, { "value": "three" }, ["DOC", "SEQ"]],
      ]);
      expect_toBe(doc.toString(null), "- one\n- two\n- three\n")
    }

    test "Do not visit block seq items" {
      let doc = parseDocument("foo:\n  - one\n  - two\nbar:\n", null);
      let calls = mock_calls();
      let fn_ = (k: VisitKey, n: Node | Pair | null, p: VisitPathItem[]) -> AsyncVisitResult {
        tvis_later(() -> VisitResult { {
          tvis_rec(calls, k, n, p);
          let r: VisitResult = match (n) {
            YAMLSeq => visit_SKIP(),
            _ => null,
          };
          r
        } })
      };
      visitAsync(doc, tvis_afns(fn_, false));
      tvis_expect_calls(calls, [
        [null, "MAP", ["DOC"]],
        [0, { "key": {}, "value": {} }, ["DOC", "MAP"]],
        ["key", { "type": "PLAIN", "value": "foo" }, ["DOC", "MAP", "PAIR"]],
        ["value", "SEQ", ["DOC", "MAP", "PAIR"]],
        [1, { "key": {}, "value": {} }, ["DOC", "MAP"]],
        ["key", { "type": "PLAIN", "value": "bar" }, ["DOC", "MAP", "PAIR"]],
        ["value", { "type": "PLAIN", "value": null }, ["DOC", "MAP", "PAIR"]],
      ])
    }

    test "Break visit on command" {
      let doc = parseDocument("- one\n- two\n- three\n", null);
      let calls = mock_calls();
      visitAsync(doc, AsyncVisitorFns {
        Scalar: (k: VisitKey, node: Scalar, p: VisitPathItem[]) -> AsyncVisitResult {
          tvis_later(() -> VisitResult { {
            tvis_rec(calls, k, node, p);
            let r: VisitResult = if (node.value == "two") { visit_BREAK() } else { null };
            r
          } })
        },
      });
      tvis_expect_calls(calls, [
        [0, { "type": "PLAIN", "value": "one" }, ["DOC", "SEQ"]],
        [1, { "type": "PLAIN", "value": "two" }, ["DOC", "SEQ"]],
      ])
    }

    test "Modify seq item" {
      let doc = parseDocument("- one\n- two\n- three\n", null);
      let calls = mock_calls();
      visitAsync(doc, AsyncVisitorFns {
        Scalar: (k: VisitKey, node: Scalar, p: VisitPathItem[]) -> AsyncVisitResult {
          tvis_later(() -> VisitResult { {
            tvis_rec(calls, k, node, p);
            let r: VisitResult = if (node.value == "two") { doc.createNode(42, null, null) } else { null };
            r
          } })
        },
      });
      tvis_expect_calls(calls, [
        [0, { "type": "PLAIN", "value": "one" }, ["DOC", "SEQ"]],
        [1, { "type": "PLAIN", "value": "two" }, ["DOC", "SEQ"]],
        [1, { "value": 42 }, ["DOC", "SEQ"]],
        [2, { "type": "PLAIN", "value": "three" }, ["DOC", "SEQ"]],
      ]);
      expect_toBe(doc.toString(null), "- one\n- 42\n- three\n")
    }

    test "Skip seq item" {
      let doc = parseDocument("- one\n- two\n- three\n", null);
      let calls = mock_calls();
      visitAsync(doc, AsyncVisitorFns {
        Scalar: (key: VisitKey, n: Scalar, p: VisitPathItem[]) -> AsyncVisitResult {
          tvis_later(() -> VisitResult { {
            tvis_rec(calls, key, n, p);
            let r: VisitResult = if (key == 0) { 2 } else { null };
            r
          } })
        },
      });
      tvis_expect_calls(calls, [
        [0, { "type": "PLAIN", "value": "one" }, ["DOC", "SEQ"]],
        [2, { "type": "PLAIN", "value": "three" }, ["DOC", "SEQ"]],
      ])
    }

    test "Remove seq item" {
      let doc = parseDocument("- one\n- two\n- three\n", null);
      let calls = mock_calls();
      visitAsync(doc, AsyncVisitorFns {
        Scalar: (k: VisitKey, node: Scalar, p: VisitPathItem[]) -> AsyncVisitResult {
          tvis_later(() -> VisitResult { {
            tvis_rec(calls, k, node, p);
            let r: VisitResult = if (node.value == "two") { visit_REMOVE() } else { null };
            r
          } })
        },
      });
      tvis_expect_calls(calls, [
        [0, { "type": "PLAIN", "value": "one" }, ["DOC", "SEQ"]],
        [1, { "type": "PLAIN", "value": "two" }, ["DOC", "SEQ"]],
        [1, { "type": "PLAIN", "value": "three" }, ["DOC", "SEQ"]],
      ]);
      expect_toBe(doc.toString(null), "- one\n- three\n")
    }

    test "Remove map value" {
      let doc = parseDocument("one: 1\ntwo: 2\n", null);
      let calls = mock_calls();
      visitAsync(doc, AsyncVisitorFns {
        Scalar: (key: VisitKey, node: Scalar, p: VisitPathItem[]) -> AsyncVisitResult {
          tvis_later(() -> VisitResult { {
            tvis_rec(calls, key, node, p);
            let r: VisitResult = if (key == "value" && node.value == 2) { visit_REMOVE() } else { null };
            r
          } })
        },
      });
      tvis_expect_calls(calls, [
        ["key", { "type": "PLAIN", "value": "one" }, ["DOC", "MAP", "PAIR"]],
        ["value", { "type": "PLAIN", "value": 1 }, ["DOC", "MAP", "PAIR"]],
        ["key", { "type": "PLAIN", "value": "two" }, ["DOC", "MAP", "PAIR"]],
        ["value", { "type": "PLAIN", "value": 2 }, ["DOC", "MAP", "PAIR"]],
      ]);
      expect_toBe(doc.toString(null), "one: 1\ntwo: null\n")
    }

    test "Fail to replace root node" {
      let doc = parseDocument("- one\n- two\n- three\n", null);
      let root: Node = doc.value;
      let seqFn = AsyncVisitorFns {
        Seq: (_k: VisitKey, _n: YAMLSeq, _p: VisitPathItem[]) -> AsyncVisitResult {
          tvis_later(() -> VisitResult { {
            let r: VisitResult = doc.createNode(42, null, null);
            r
          } })
        },
      };
      // `await expect(promise).rejects.toMatchObject({ message })`: the error
      // surfaces when visitAsync's internal await re-raises it.
      let err = expect_toThrow(() -> unknown { visitAsync(root, seqFn) }, null);
      expect_toMatchObject(err, { "message": "Cannot replace node with scalar parent" })
    }
  }
}
