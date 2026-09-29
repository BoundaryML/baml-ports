// Port of tests/cst.ts

function tcst_cstDoc(src: string) -> Token {
  let tokens = new_parser(null).parse(src);
  expect_toHaveLength(tokens, 1);
  expect_toBe(tokens[0].type, "document");
  tokens[0]
}

/// `path` as the upstream `[['value', 0], ...]` tuples, for toMatchObject.
function tcst_path_tuples(path: CstPathItem[]) -> unknown[] {
  path.map((p: CstPathItem) -> unknown { [p.field, p.index] })
}

testset "cst" {
  testset "CST.visit" {
    test "Visit paths in order" {
      let doc = tcst_cstDoc(source(`
        foo:
          - baz
          - [ bar: 42 ]
        ? { fuzz, ball }
        : fii
      `));
      let paths: unknown[] = [];
      cst_visit(doc, (_item: CollectionItem, path: CstPathItem[]) -> CstVisitResult {
        paths.push(tcst_path_tuples(path));
        null
      });
      expect_toMatchObject(paths, [
        [],
        [["value", 0]],
        [["value", 0], ["value", 0]],
        [["value", 0], ["value", 1]],
        [["value", 0], ["value", 1], ["value", 0]],
        [["value", 1]],
        [["value", 1], ["key", 0]],
        [["value", 1], ["key", 1]],
      ])
    }

    test "break visit" {
      let doc = tcst_cstDoc(source(`
        - " foo"
        - "foo"
        - "bar"
      `));
      let visits = 0;
      cst_visit(doc, (item: CollectionItem, path: CstPathItem[]) -> CstVisitResult {
        visits += 1;
        let scalar = resolveAsScalar(item.value, true, null);
        if (scalar?.value == "foo") {
          return cst_visit_BREAK();
        }
        null
      });
      expect_toBe(visits, 3)
    }

    test "remove item" {
      let doc = tcst_cstDoc(source(`
        -  " foo"
        - "foo"
        - "bar"
      `));
      let visits = 0;
      cst_visit(doc, (item: CollectionItem, path: CstPathItem[]) -> CstVisitResult {
        visits += 1;
        let scalar = resolveAsScalar(item.value, true, null);
        if (scalar?.value == "foo") {
          return cst_visit_REMOVE();
        }
        null
      });
      expect_toBe(visits, 4);
      expect_toBe(cst_stringify(doc), source(`
        -  " foo"
        - "bar"
      `))
    }

    test "replace value with block scalar in seq" {
      let doc = tcst_cstDoc(source(`
        -  " foo"
        - "foo"
        - "bar"
      `));
      let visits = 0;
      cst_visit(doc, (item: CollectionItem, path: CstPathItem[]) -> CstVisitResult {
        visits += 1;
        let value = item.value;
        if (value != null) {
          let scalar = resolveAsScalar(value, true, null);
          if (scalar?.value == "foo") {
            setScalarValue(value, "foo", SetScalarValueContext { type: "BLOCK_LITERAL" });
          }
        }
        null
      });
      expect_toBe(visits, 4);
      expect_toBe(cst_stringify(doc), source(`
        -  " foo"
        - |-
          foo
        - "bar"
      `))
    }

    test "add item" {
      let doc = tcst_cstDoc(source(`
        -  " foo"
        - "foo"
        - "bar"
      `));
      let visits = 0;
      cst_visit(doc, (item: CollectionItem, path: CstPathItem[]) -> CstVisitResult {
        visits += 1;
        let value = item.value;
        if (value != null && cst_is_scalar(value)) {
          let scalar = resolveAsScalar(value, true, null);
          if (scalar?.value == "foo") {
            let parent = cst_visit_parentCollection(doc, path);
            let idx = path[path.length() - 1].index;
            let indent = value.indent ?? 0;
            let ci = collection_item(item.start.slice(0, item.start.length()));
            ci.value = createScalarToken("hip", ScalarTokenContext { indent: indent });
            titems(parent).insert(ci, idx);
            return idx + 2;
          }
        }
        null
      });
      expect_toBe(visits, 4);
      expect_toBe(cst_stringify(doc), source(`
        -  " foo"
        - hip
        - "foo"
        - "bar"
      `))
    }

    test "replace value with flow scalar in map" {
      let doc = tcst_cstDoc(source(`
        - a:  A
          b: B\t#comment
          c: C
      `));
      let visits = 0;
      cst_visit(doc, (item: CollectionItem, path: CstPathItem[]) -> CstVisitResult {
        visits += 1;
        let value = item.value;
        if (value != null) {
          let scalar = resolveAsScalar(value, true, null);
          if (scalar?.value == "B") {
            setScalarValue(value, "foo\n\nbar", SetScalarValueContext { afterKey: item.key != null });
          }
        }
        null
      });
      expect_toBe(visits, 5);
      expect_toBe(cst_stringify(doc), source(`
        - a:  A
          b: foo


            bar\t#comment
          c: C
      `))
    }

    test "skip children" {
      let doc = tcst_cstDoc(source(`
        - " foo"
        - [ foo, 13, 42 ]
        - "bar"
      `));
      let visits = 0;
      cst_visit(doc, (item: CollectionItem, path: CstPathItem[]) -> CstVisitResult {
        visits += 1;
        if (item.value?.type == "flow-collection") {
          return cst_visit_SKIP();
        }
        null
      });
      expect_toBe(visits, 4)
    }

    test "set next index" {
      let doc = tcst_cstDoc(source(`
        - "foo"
        - [ foo, 13, 42 ]
        - "bar"
      `));
      let visits = 0;
      cst_visit(doc, (item: CollectionItem, path: CstPathItem[]) -> CstVisitResult {
        visits += 1;
        let scalar = resolveAsScalar(item.value, true, null);
        if (scalar?.value == "foo") {
          return 2;
        }
        null
      });
      expect_toBe(visits, 3)
    }
  }

  test "Line comment before unindented block-seq in block-map (#525)" {
    let src = "a:\n#\n- b";
    let docs = new_parser(null).parse(src);
    expect_toBe(cst_stringify(docs[0]), src)
  }
}
