// Port of tests/clone.ts
//
// NOTE: multiline backtick literals drop their boundary newlines, so
// upstream's source`...` (which keeps the final newline) is `source(`...`) + "\n"`.

/// Visitor `Node(_, it) { if (it.anchor === 'foo') it.anchor = 'x' }`:
/// `anchor` lives on each node class, so narrow before assigning.
function tclo_rename_anchor(it: Node, from: string, to: string) -> null {
  match (it) {
    let s: Scalar => {
      if (s.anchor == from) { s.anchor = to; }
    },
    let m: YAMLMap => {
      if (m.anchor == from) { m.anchor = to; }
    },
    let q: YAMLSeq => {
      if (q.anchor == from) { q.anchor = to; }
    },
    let t: YAMLSet => {
      if (t.anchor == from) { t.anchor = to; }
    },
    let a: Alias => {
      if (a.anchor == from) { a.anchor = to; }
    },
  }
  null
}

testset "clone" {
  testset "doc.clone()" {
    test "has expected members" {
      let doc = parseDocument("foo: bar", null);
      let copy = doc.clone();
      expect_toMatchObject(copy, {
        "comment": null,
        "commentBefore": null,
        "errors": [],
        "warnings": []
      })
    }

    test "has expected methods" {
      let doc = parseDocument("foo: bar", null);
      let copy = doc.clone();
      expect_toBe(copy.toString(null), "foo: bar\n");
      expect_toEqual(copy.toJS(null), { "foo": "bar" });

      let node = copy.createNode(42, null, null);
      expect_toBeInstanceOf(node, "Scalar");
      expect_toMatchObject(node, { "value": 42 });

      let alias = copy.createAlias(node, "foo");
      expect_toBeInstanceOf(alias, "Alias");
      expect_toMatchObject(alias, { "source": "foo" })
    }

    test "has separate value from original" {
      let doc = parseDocument("foo: bar", null);
      let copy = doc.clone();
      copy.set("foo", "fizz");
      expect_toMatchObject(doc.get("foo"), Scalar.new("bar"));
      expect_toMatchObject(copy.get("foo"), Scalar.new("fizz"))
    }

    test "has separate directives from original" {
      let doc = parseDocument("foo: bar", null);
      let copy = doc.clone();
      let dirs = copy.directives;
      if (dirs != null) {
        dirs.yaml.explicit = true;
      }
      expect_toBe(copy.toString(null), source(`
        %YAML 1.2
        ---
        foo: bar
      `) + "\n");
      expect_toBe(doc.toString(null), "foo: bar\n")
    }

    test "handles anchors & aliases" {
      let src_ = source(`
        foo: &foo FOO
        bar: *foo
      `) + "\n";
      let doc = parseDocument(src_, null);
      let copy = doc.clone();
      expect_toBe(copy.toString(null), src_);

      visit(doc, VisitorFns {
        Alias: (_k: VisitKey, it: Alias, _p: VisitPathItem[]) -> VisitResult {
          if (it.source == "foo") { it.source = "x"; }
          null
        },
        Node: (_k: VisitKey, it: Node, _p: VisitPathItem[]) -> VisitResult {
          tclo_rename_anchor(it, "foo", "x");
          null
        }
      });
      expect_toBe(doc.toString(null), source(`
        foo: &x FOO
        bar: *x
      `) + "\n");
      expect_toBe(copy.toString(null), src_)
    }
  }
}
