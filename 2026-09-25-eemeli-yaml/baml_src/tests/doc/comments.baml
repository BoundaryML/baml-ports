// Port of tests/doc/comments.ts
//
// NOTE: multiline backtick literals drop their boundary line breaks (leading
// and trailing blank lines), while upstream's source`...` tag keeps the final
// newline. So `source`...`` ending in a newline becomes `tcom_src(`...`)`
// (= `source(…) + "\n"`), and the few sources that start with blank lines are
// written as plain double-quoted strings.

/// `source`...`` for a template literal ending with a newline.
function tcom_src(str: string) -> string {
  source(str) + "\n"
}

/// `doc.value as Scalar` (TS generic `parseDocument<YAML.Scalar>` / `!`).
function tcom_scalar(x: unknown) -> Scalar {
  match (x) {
    let s: Scalar => s,
    _ => {
      throw js_type_error("expected a Scalar, got " + t_show(x));
    },
  }
}

function tcom_seq(x: unknown) -> YAMLSeq {
  match (x) {
    let s: YAMLSeq => s,
    _ => {
      throw js_type_error("expected a YAMLSeq, got " + t_show(x));
    },
  }
}

function tcom_map(x: unknown) -> YAMLMap {
  match (x) {
    let m: YAMLMap => m,
    _ => {
      throw js_type_error("expected a YAMLMap, got " + t_show(x));
    },
  }
}

function tcom_pair(x: unknown) -> Pair {
  match (x) {
    let p: Pair => p,
    _ => {
      throw js_type_error("expected a Pair, got " + t_show(x));
    },
  }
}

testset "doc/comments" {
  testset "parse comments" {
    testset "body" {
      test "directives" {
        let src_ = "#comment\n%YAML 1.2 #comment\n---\nstring\n";
        let doc = parseDocument(src_, null);
        expect_toBe(doc.commentBefore, "comment\ncomment");
        expect_toBe(doc.toString(null), "#comment\n#comment\n\n%YAML 1.2\n---\nstring\n")
      }

      test "body start comments" {
        let src_ = tcom_src(`
          ---
          #comment
          #comment
          string
        `);
        let doc = parseDocument(src_, null);
        expect_toBe(tcom_scalar(doc.value).commentBefore, "comment\ncomment");
        expect_toBe(doc.toString(null), src_)
      }

      test "body start comments with empty comment line" {
        let src_ = tcom_src(`
          ---
          #comment
          #
          #comment
          string
        `);
        let doc = parseDocument(src_, null);
        expect_toBe(tcom_scalar(doc.value).commentBefore, "comment\n \ncomment");
        expect_toBe(doc.toString(null), tcom_src(`
          ---
          #comment
          #
          #comment
          string
        `))
      }

      test "body end comments" {
        let src_ = "\nstring\n#comment\n#comment\n";
        let doc = parseDocument(src_, null);
        expect_toBe(doc.comment, "comment\ncomment");
        expect_toBe(doc.toString(null), "string\n\n#comment\n#comment\n")
      }
    }

    testset "top-level scalar comments" {
      test "plain" {
        let src_ = "#c0\nvalue #c1\n#c2";
        let doc = parseDocument(src_, null);
        let v = tcom_scalar(doc.value);
        expect_toBe(v.commentBefore, "c0");
        expect_toBe(v.comment, "c1");
        expect_toBe(doc.comment, "c2");
        expect_toBe(v.value, "value");
        expect_toMatchObject(v.range, [4, 9, 14])
      }

      test "\"quoted\"" {
        let src_ = "#c0\n\"value\" #c1\n#c2";
        let doc = parseDocument(src_, null);
        let v = tcom_scalar(doc.value);
        expect_toBe(v.commentBefore, "c0");
        expect_toBe(v.comment, "c1");
        expect_toBe(doc.comment, "c2");
        expect_toBe(v.value, "value");
        expect_toMatchObject(v.range, [4, 11, 16])
      }

      test "block" {
        let src_ = "#c0\n>- #c1\n value\n#c2\n";
        let doc = parseDocument(src_, null);
        let v = tcom_scalar(doc.value);
        expect_toBe(v.commentBefore, "c0");
        expect_toBe(v.comment, "c1");
        expect_toBe(doc.comment, "c2");
        expect_toBe(v.value, "value");
        expect_toMatchObject(v.range, [4, 18, 18])
      }
    }

    testset "seq entry comments" {
      test "plain" {
        let src_ = tcom_src(`
          #c0
          - value 1
            #c1

          - value 2

          #c2
        `);
        let doc = parseDocument(src_, null);
        expect_toMatchObject(doc, {
          "value": [
            { "commentBefore": "c0", "value": "value 1", "comment": "c1" },
            { "value": "value 2" }
          ],
          "comment": "c2"
        });
        expect_toMatchObject(tcom_seq(doc.value).range, [4, 31, 31])
      }

      test "multiline" {
        let src_ = tcom_src(`
          - value 1
            #c0
          #c1

          #c2
          - value 2

          #c3
          #c4
        `);
        let doc = parseDocument(src_, null);
        expect_toMatchObject(doc, {
          "value": [{ "comment": "c0" }, { "commentBefore": "c1\n\nc2" }],
          "comment": "c3\nc4"
        })
      }
    }

    testset "map entry comments" {
      test "plain" {
        let src_ = tcom_src(`
          #c0
          key1: value 1
            #c1

          key2: value 2

          #c2
        `);
        let doc = parseDocument(src_, null);
        expect_toMatchObject(doc, {
          "value": _map({
            "key1": _pair({ "commentBefore": "c0" }, { "comment": "c1" }),
            "key2": "value 2"
          }, null),
          "comment": "c2"
        })
      }

      test "multiline" {
        let src_ = tcom_src(`
          key1: value 1
            #c0
          #c1

          #c2
          key2: value 2

          #c3
          #c4
        `);
        let doc = parseDocument(src_, null);
        expect_toMatchObject(doc, {
          "value": _map({
            "key1": { "comment": "c0" },
            "key2": { "key": { "commentBefore": "c1\n\nc2" }, "value": {} }
          }, null),
          "comment": "c3\nc4"
        })
      }
    }

    testset "map-in-seq comments" {
      test "plain" {
        let src_ = tcom_src(`
          #c0
          - #c1
            k1: v1
            #c2
            k2: v2 #c3
          #c4
            k3: v3
          #c5
        `);
        let doc = parseDocument(src_, null);
        expect_toMatchObject(doc, {
          "value": [
            _map({
              "k1": "v1",
              "k2": _pair({ "commentBefore": "c2" }, { "comment": "c3" }),
              "k3": _pair({ "commentBefore": "c4" }, "v3")
            }, null)
          ],
          "comment": "c5"
        });
        expect_toBe(tcom_map(tcom_seq(doc.value).items[0]).commentBefore, "c0\nc1");
        expect_toBe(doc.toString(null), tcom_src(`
          #c0
          #c1
          - k1: v1
            #c2
            k2: v2 #c3
            #c4
            k3: v3

          #c5
        `))
      }
    }

    testset "seq-in-map comments" {
      test "plain" {
        let src_ = tcom_src(`
          #c0
          k1: #c1
            - v1
          #c2
            - v2
            #c3
          k2:
            - v3 #c4
          #c5
        `);
        let doc = parseDocument(src_, null);
        expect_toMatchObject(doc, {
          "value": _map({
            "k1": _pair(
              { "commentBefore": "c0", "value": "k1" },
              _seq(["v1", { "commentBefore": "c2", "value": "v2" }])
            ),
            "k2": _pair({ "value": "k2" }, _seq([{ "value": "v3", "comment": "c4" }]))
          }, null),
          "comment": "c5"
        });
        expect_toMatchObject(doc.get("k1"), {
          "commentBefore": "c1",
          "comment": "c3"
        });
        expect_toBe(doc.toString(null), tcom_src(`
          #c0
          k1:
            #c1
            - v1
            #c2
            - v2
            #c3
          k2:
            - v3 #c4

          #c5
        `))
      }
    }

    testset "flow collection comments" {
      test "line comment after , in seq" {
        let doc = parseDocument(source(`
          [ a, #c0
            b #c1
          ]`), null);
        expect_toMatchObject(doc.value, [
          { "value": "a", "comment": "c0" },
          { "value": "b", "comment": "c1" }
        ])
      }

      test "line comment after , in map" {
        let doc = parseDocument(source(`
          { a, #c0
            b: c, #c1
            d #c2
          }`), null);
        expect_toMatchObject(doc.value, _map({
          "a": _pair({ "value": "a", "comment": "c0" }, null),
          "b": { "value": "c", "comment": "c1" },
          "d": _pair({ "value": "d", "comment": "c2" }, null)
        }, null))
      }

      test "multi-line comments" {
        let doc = parseDocument("{ a,\n#c0\n#c1\nb }", null);
        expect_toMatchObject(doc.value, _map({
          "a": { "key": { "value": "a" }, "value": {} },
          "b": { "key": { "commentBefore": "c0\nc1", "value": "b" }, "value": {} }
        }, null))
      }
    }

    // Upstream generates these four tests with a `for` loop over
    // `{ name, src }` cases; BAML testsets can't be generated, so they are
    // unrolled here (same names and order).
    testset "line comments with leading tabs (#548)" {
      test "after scalar" {
        let doc = parseDocument("foo\n\t#c", null);
        expect_toHaveLength(doc.errors, 0)
      }

      test "in seq" {
        let doc = parseDocument("- x\n\t#c\n- y\n\t #d\n- z", null);
        expect_toHaveLength(doc.errors, 0)
      }

      test "in map value" {
        let doc = parseDocument("x:\n\t#c\ny:", null);
        expect_toHaveLength(doc.errors, 0)
      }

      test "in map" {
        let doc = parseDocument("x: 1\n\t#c\ny: 2", null);
        expect_toHaveLength(doc.errors, 0)
      }
    }
  }

  testset "stringify comments" {
    testset "single-line comments" {
      test "plain" {
        let src_ = "string";
        let doc = parseDocument(src_, null);
        tcom_scalar(doc.value).comment = "comment";
        expect_toBe(doc.toString(null), "string #comment\n")
      }

      test "\"quoted\"" {
        let src_ = "\"string\\u0000\"";
        let doc = parseDocument(src_, null);
        tcom_scalar(doc.value).comment = "comment";
        expect_toBe(doc.toString(null), "\"string\\0\" #comment\n")
      }

      test "block" {
        let src_ = ">\nstring\n";
        let doc = parseDocument(src_, null);
        tcom_scalar(doc.value).comment = "comment";
        expect_toBe(doc.toString(null), "> #comment\nstring\n")
      }
    }

    testset "multi-line comments" {
      test "plain" {
        let src_ = "string";
        let doc = parseDocument(src_, null);
        tcom_scalar(doc.value).comment = "comment\nlines";
        expect_toBe(doc.toString(null), "string\n#comment\n#lines\n")
      }

      test "\"quoted\"" {
        let src_ = "\"string\\u0000\"";
        let doc = parseDocument(src_, null);
        tcom_scalar(doc.value).comment = "comment\nlines";
        expect_toBe(doc.toString(null), "\"string\\0\"\n#comment\n#lines\n")
      }

      test "block" {
        let src_ = ">\nstring\n";
        let doc = parseDocument(src_, null);
        tcom_scalar(doc.value).comment = "comment\nlines";
        expect_toBe(doc.toString(null), "> #comment lines\nstring\n")
      }
    }

    testset "document comments" {
      test "directive" {
        let src_ = tcom_src(`
          #c0
          ---
          string
        `);
        let doc = parseDocument(src_, null);
        expect_toBe(doc.commentBefore, "c0");
        doc.commentBefore = (doc.commentBefore ?? "null") + "\nc1";
        expect_toBe(doc.toString(null), tcom_src(`
          #c0
          #c1
          ---
          string
        `))
      }
    }

    testset "seq comments" {
      test "plain" {
        let src_ = "- value 1\n- value 2\n";
        let doc = parseDocument(src_, null);
        let seq = tcom_seq(doc.value);
        seq.commentBefore = "c0";
        tcom_scalar(seq.items[0]).commentBefore = "c1";
        tcom_scalar(seq.items[1]).commentBefore = "c2";
        seq.comment = "c3";
        expect_toBe(doc.toString(null), tcom_src(`
          #c0
          #c1
          - value 1
          #c2
          - value 2
          #c3
        `))
      }

      test "multiline" {
        let src_ = "- value 1\n- value 2\n";
        let doc = parseDocument(src_, null);
        let seq = tcom_seq(doc.value);
        tcom_scalar(seq.items[0]).commentBefore = "c0\nc1";
        tcom_scalar(seq.items[1]).commentBefore = " \nc2\n\nc3";
        seq.comment = "c4\nc5";
        expect_toBe(doc.toString(null), tcom_src(`
          #c0
          #c1
          - value 1
          #
          #c2

          #c3
          - value 2
          #c4
          #c5
        `))
      }

      test "seq-in-map" {
        let src_ = "map:\n  - value 1\n  - value 2\n";
        let doc = parseDocument(src_, null);
        let pair = tcom_pair(tcom_map(doc.value).getPair("map"));
        let key = tcom_scalar(pair.key);
        let seq = tcom_seq(pair.value);
        key.commentBefore = "c0";
        key.comment = "c1";
        seq.commentBefore = "c2";
        tcom_scalar(seq.items[0]).commentBefore = "c3";
        tcom_scalar(seq.items[1]).commentBefore = "c4";
        seq.comment = "c5";
        expect_toBe(doc.toString(null), tcom_src(`
          #c0
          map: #c1
            #c2
            #c3
            - value 1
            #c4
            - value 2
            #c5
          `))
      }

      test "custom stringifier" {
        let doc = parseDocument("- a\n- b\n", null);
        let seq = tcom_seq(doc.value);
        seq.commentBefore = "c0";
        tcom_scalar(seq.items[0]).commentBefore = "c1";
        tcom_scalar(seq.items[1]).commentBefore = "c2\nc3";
        expect_toBe(
          doc.toString(Options { commentString: (str: string) -> string { str.replace_all(re("(?m)^"), "// ") } }),
          tcom_src(`
            // c0
            // c1
            - a
            // c2
            // c3
            - b
          `)
        )
      }
    }

    testset "map entry comments" {
      test "plain" {
        let src_ = "key1: value 1\nkey2: value 2\n";
        let doc = parseDocument(src_, null);
        let p1 = tcom_pair(doc.getPair("key1"));
        tcom_scalar(p1.key).commentBefore = "c0";
        let p2 = tcom_pair(doc.getPair("key2"));
        tcom_scalar(p2.key).commentBefore = "c1";
        tcom_scalar(p2.key).comment = "c2";
        tcom_scalar(p2.value).spaceBefore = true;
        tcom_map(doc.value).comment = "c3";
        expect_toBe(doc.toString(null), tcom_src(`
          #c0
          key1: value 1
          #c1
          key2: #c2

            value 2
          #c3
        `))
      }

      test "multiline" {
        let src_ = "key1: value 1\nkey2: value 2\n";
        let doc = parseDocument(src_, null);
        let p1 = tcom_pair(doc.getPair("key1"));
        tcom_scalar(p1.key).commentBefore = "c0\nc1";
        let p2 = tcom_pair(doc.getPair("key2"));
        tcom_scalar(p2.key).commentBefore = " \nc2\n\nc3";
        tcom_scalar(p2.key).comment = "c4\nc5";
        tcom_scalar(p2.value).spaceBefore = true;
        tcom_scalar(p2.value).commentBefore = "c6";
        tcom_map(doc.value).comment = "c7\nc8";
        expect_toBe(doc.toString(null), tcom_src(`
          #c0
          #c1
          key1: value 1
          #
          #c2

          #c3
          key2:
            #c4
            #c5

            #c6
            value 2
          #c7
          #c8
        `))
      }

      test "indented comment on empty value with spaceBefore" {
        let src_ = tcom_src(`
          key1:

            # comment
          key2: x
        `);
        let doc = parseDocument(src_, null);
        expect_toBe(doc.toString(null), src_)
      }

      test "comment after empty value with spaceBefore" {
        let src_ = tcom_src(`
          key1:

          # comment
          key2: x
        `);
        let doc = parseDocument(src_, null);
        expect_toBe(doc.toString(null), src_)
      }
    }

    testset "flow collection comments" {
      test "line comment after , in seq" {
        let doc = parseDocument(source(`
          [ a, #c0
            b #c1
          ]`), null);
        expect_toBe(doc.toString(null), tcom_src(`
          [
            a, #c0
            b #c1
          ]
        `))
      }

      test "line comment after [], in seq" {
        let doc = parseDocument(source(`
          [ [a], #c0
            [b] #c1
          ]`), null);
        expect_toBe(doc.toString(null), tcom_src(`
          [
            [ a ], #c0
            [ b ] #c1
          ]
        `))
      }

      test "line comment after , in map" {
        let doc = parseDocument(source(`
          { a, #c0
            b: c, #c1
            d #c2
          }`), null);
        expect_toBe(doc.toString(null), tcom_src(`
          {
            a:, #c0
            b: c, #c1
            d: #c2
          }
        `))
      }

      test "line comment after {}, in map" {
        let doc = parseDocument(source(`
          { {a: 1}, #c0
            b: {c: 2}, #c1
            d #c2
          }`), null);
        expect_toBe(doc.toString(null), tcom_src(`
          {
            ? { a: 1 }, #c0
            b: { c: 2 }, #c1
            d: #c2
          }
        `))
      }

      test "line comment after flow collection (#443)" {
        let doc = parseDocument(tcom_src(`
          [ value1, value2 ] # comment
        `), null);
        expect_toBe(doc.toString(null), tcom_src(`
          [ value1, value2 ] # comment
        `))
      }
    }
  }

  testset "blank lines" {
    testset "drop leading blank lines" {
      test "content" {
        let src_ = "\n\nstr\n";
        let doc = parseDocument(src_, null);
        expect_toBe(doc.toString(null), "str\n")
      }

      test "content comment" {
        let src_ = "\n\n#cc\n \nstr\n";
        let doc = parseDocument(src_, null);
        expect_toBe(doc.toString(null), "#cc\n\nstr\n")
      }

      test "directive" {
        let src_ = "\n\n%YAML 1.2\n---\nstr\n";
        let doc = parseDocument(src_, null);
        expect_toBe(doc.toString(null), "%YAML 1.2\n---\nstr\n")
      }

      test "directive comment" {
        let src_ = "\n\n#cc\n%YAML 1.2\n---\nstr\n";
        let doc = parseDocument(src_, null);
        expect_toBe(doc.toString(null), "#cc\n\n%YAML 1.2\n---\nstr\n")
      }
    }

    testset "drop trailing blank lines" {
      test "empty value" {
        let src_ = "\n\n\n";
        let doc = parseDocument(src_, null);
        expect_toBe(doc.toString(null), "null\n")
      }

      test "scalar value" {
        let src_ = "str\n\n\n";
        let doc = parseDocument(src_, null);
        expect_toBe(doc.toString(null), "str\n")
      }

      test "seq value" {
        let src_ = "- a\n- b\n\n\n";
        let doc = parseDocument(src_, null);
        expect_toBe(doc.toString(null), "- a\n- b\n")
      }

      test "empty/comment value" {
        let src_ = "#cc\n\n\n";
        let doc = parseDocument(src_, null);
        expect_toBe(doc.toString(null), "#cc\n\nnull\n")
      }
    }

    test "between directive comment & directive" {
      let src_ = "#cc\n\n\n%YAML 1.2\n---\nstr\n";
      let doc = parseDocument(src_, null);
      expect_toBe(doc.toString(null), "#cc\n\n%YAML 1.2\n---\nstr\n")
    }

    test "after leading comment" {
      let src_ = "#cc\n\n\nstr\n";
      let doc = parseDocument(src_, null);
      expect_toBe(doc.toString(null), "#cc\n\nstr\n")
    }

    test "before first node in document with directives" {
      let doc = parseDocument("str\n", null);
      tcom_scalar(doc.value).spaceBefore = true;
      expect_toBe(doc.toString(Options { directives: true }), "---\n\nstr\n")
    }

    test "between seq items" {
      let src_ = "- a\n\n- b\n\n\n- c\n";
      let doc = parseDocument(src_, null);
      expect_toBe(doc.toString(null), "- a\n\n- b\n\n- c\n")
    }

    test "between seq indicator and value (#590)" {
      let src_ = tcom_src(`
        key:
          -
          - a

          -
          -
            b
      `);
      let doc = parseDocument(src_, null);
      expect_toBe(
        doc.toString(null),
        tcom_src(`
          key:
            -·
            - a

            -·
            - b
        `).replace_all(re("·"), " ")
      )
    }

    test "between seq items with leading comments" {
      let src_ = tcom_src(`
        #A
        - a

        #B
        - b


        #C

        - c
      `);
      let doc = parseDocument(src_, null);
      expect_toBe(doc.toString(null), tcom_src(`
        #A
        - a

        #B
        - b

        #C

        - c
      `))
    }

    testset "not after block scalar with keep chomping" {
      test "in seq" {
        let src_ = "- |+\n  a\n\n- b\n";
        let doc = parseDocument(src_, null);
        expect_toBe(doc.toString(null), src_);
        let it = tcom_scalar(tcom_seq(doc.value).items[1]);
        // expect(it).not.toHaveProperty('spaceBefore', true)
        expect_true(it.spaceBefore != true, "expected spaceBefore not to be true");
        it.spaceBefore = true;
        expect_toBe(doc.toString(null), src_);
        it.commentBefore = "\n\n";
        expect_toBe(doc.toString(null), src_)
      }

      test "in map" {
        let src_ = "a: |+\n  A\n\nb: B\n";
        let doc = parseDocument(src_, null);
        expect_toBe(doc.toString(null), src_);
        let it = tcom_scalar(tcom_pair(doc.getPair("b")).key);
        expect_true(it.spaceBefore != true, "expected spaceBefore not to be true");
        it.spaceBefore = true;
        expect_toBe(doc.toString(null), src_);
        it.commentBefore = "\n\n";
        expect_toBe(doc.toString(null), src_)
      }

      test "in seq in map" {
        let src_ = "a:\n  - |+\n    A\n\nb: B\n";
        let doc = parseDocument(src_, null);
        expect_toBe(doc.toString(null), src_);
        let it = tcom_scalar(tcom_pair(doc.getPair("b")).key);
        expect_true(it.spaceBefore != true, "expected spaceBefore not to be true");
        it.spaceBefore = true;
        expect_toBe(doc.toString(null), src_);
        it.commentBefore = "\n\n";
        expect_toBe(doc.toString(null), src_)
      }

      test "as value" {
        let src_ = "|+\n  a\n\n#c\n";
        let doc = parseDocument(src_, null);
        expect_toMatchObject(doc, {
          "comment": "c",
          "value": { "value": "a\n\n" }
        });
        expect_toBe(doc.toString(null), src_);
        doc.comment = "\n\nc";
        expect_toBe(doc.toString(null), src_)
      }
    }

    test "before block map values" {
      let src_ = "a:\n\n  1\nb:\n\n  #c\n  2\n";
      let doc = parseDocument(src_, null);
      expect_toMatchObject(doc.value, _map({
        "a": { "value": 1, "spaceBefore": true },
        "b": { "value": 2, "commentBefore": "c", "spaceBefore": true }
      }, null));
      expect_toBe(doc.toString(null), src_)
    }

    testset "after block value" {
      test "in seq" {
        let src_ = "- |\n a\n\n- >-\n b\n\n- |+\n c\n\n- d\n";
        let doc = parseDocument(src_, null);
        expect_toBe(doc.toString(null), "- |\n  a\n\n- >-\n  b\n\n- |+\n  c\n\n- d\n")
      }

      test "in map" {
        let src_ = "A: |\n a\n\nB: >-\n b\n\nC: |+\n c\n\nD: d\n";
        let doc = parseDocument(src_, null);
        expect_toBe(doc.toString(null), "A: |\n  a\n\nB: >-\n  b\n\nC: |+\n  c\n\nD: d\n")
      }
    }

    testset "flow collections" {
      test "flow seq" {
        let src_ = "[1,\n\n2,\n3,\n\n4\n\n]";
        let doc = parseDocument(src_, null);
        expect_toMatchObject(doc.value, _seq([1, { "value": 2, "spaceBefore": true }, 3, {
          "value": 4,
          "spaceBefore": true
        }]));
        expect_toBe(doc.toString(null), "[\n  1,\n\n  2,\n  3,\n\n  4\n]\n")
      }

      test "flow map" {
        let src_ = "{\n\na: 1,\n\nb: 2 }";
        let doc = parseDocument(src_, null);
        expect_toMatchObject(doc.value, _map(
          {
            "a": _pair({ "value": "a", "spaceBefore": true }, 1),
            "b": _pair({ "value": "b", "spaceBefore": true }, 2)
          },
          { "flow": true }
        ))
      }

      test "flow map value comments & spaces" {
        let src_ = "{\n  a:\n    #c\n    1,\n  b:\n\n    #d\n    2\n}\n";
        let doc = parseDocument(src_, null);
        expect_toMatchObject(doc.value, _map(
          {
            "a": { "value": 1, "commentBefore": "c" },
            "b": { "value": 2, "commentBefore": "d", "spaceBefore": true }
          },
          { "flow": true }
        ));
        expect_toBe(doc.toString(null), src_)
      }
    }

    test "blank line after less-indented comment (#91)" {
      let src_ = "\nmap:\n  foo0:\n    key2: value2\n\n#   foo1:\n#     key0: value0\n#     key1: value1\n\n  foo2:\n    key3: value3";
      let doc = parseDocument(src_, null);
      expect_toHaveLength(doc.errors, 0);
      expect_toMatchObject(doc.toJS(null), {
        "map": { "foo0": { "key2": "value2" }, "foo2": { "key3": "value3" } }
      })
    }

    testset "commented empty lines" {
      test "document comments with #" {
        let src_ = tcom_src(`
          # c1
          #
          # c2

          value

          # c3
          #
          # c4
        `);
        let doc = parseDocument(src_, null);
        expect_toMatchObject(doc, {
          "commentBefore": " c1\n \n c2",
          "comment": " c3\n \n c4"
        });
        expect_toBe(doc.toString(null), tcom_src(`
          # c1
          #
          # c2

          value

          # c3
          #
          # c4
        `))
      }

      test "document comments without #" {
        let src_ = tcom_src(`
          # c1

          # c2

          value

          # c3

          # c4
        `);
        let doc = parseDocument(src_, null);
        expect_toMatchObject(doc, {
          "commentBefore": " c1\n\n c2",
          "comment": " c3\n\n c4"
        });
        expect_toBe(doc.toString(null), src_)
      }

      test "map comments with #" {
        let src_ = tcom_src(`
          key:
            # c1
            #
            # c2

            value

            # c3
            #
            # c4
        `);
        let doc = parseDocument(src_, null);
        expect_toMatchObject(doc.get("key"), {
          "commentBefore": " c1\n \n c2\n",
          "comment": " c3\n \n c4"
        });
        expect_toBe(doc.toString(null), tcom_src(`
          key:
            # c1
            #
            # c2

            value
            # c3
            #
            # c4
        `))
      }

      test "map comments without #" {
        let src_ = tcom_src(`
          key:
            # c1

            # c2

            value

            # c3

            # c4
        `);
        let doc = parseDocument(src_, null);
        expect_toMatchObject(doc.get("key"), {
          "commentBefore": " c1\n\n c2\n",
          "comment": " c3\n\n c4"
        });
        expect_toBe(doc.toString(null), tcom_src(`
          key:
            # c1

            # c2

            value
            # c3

            # c4
        `))
      }

      test "seq comments with #" {
        let src_ = tcom_src(`
          # c1
          #
          # c2
          - v1
            # c3
            #
          # c4
          - v2
        `);
        let doc = parseDocument(src_, null);
        expect_toMatchObject(doc.value, [
          { "commentBefore": " c1\n \n c2", "comment": " c3\n " },
          { "commentBefore": " c4" }
        ]);
        expect_toBe(doc.toString(null), tcom_src(`
          # c1
          #
          # c2
          - v1
            # c3
            #
          # c4
          - v2
        `))
      }

      test "seq comments without #" {
        let src_ = tcom_src(`
          # c1

          # c2
          - v1
            # c3

          # c4
          - v2
        `);
        let doc = parseDocument(src_, null);
        expect_toMatchObject(doc.value, [
          { "commentBefore": " c1\n\n c2", "comment": " c3" },
          { "commentBefore": " c4", "spaceBefore": true }
        ]);
        expect_toBe(doc.toString(null), tcom_src(`
          # c1

          # c2
          - v1 # c3

          # c4
          - v2
        `))
      }
    }

    testset "newlines as comments" {
      test "seq" {
        let doc = parseDocument("- v1\n- v2\n", null);
        let seq = tcom_seq(doc.value);
        let v1 = tcom_scalar(seq.items[0]);
        let v2 = tcom_scalar(seq.items[1]);
        v1.commentBefore = "\n";
        v1.comment = "\n";
        v2.commentBefore = "\n";
        v2.comment = "\n";
        // source`` with leading/trailing blank lines (see file header)
        expect_toBe(doc.toString(null), "\n- v1\n\n\n- v2\n\n")
      }

      test "map" {
        let doc = parseDocument("k1: v1\nk2: v2", null);
        let p1 = tcom_pair(doc.getPair("k1"));
        tcom_scalar(p1.key).commentBefore = "\n";
        tcom_scalar(p1.value).commentBefore = "\n";
        tcom_scalar(p1.value).comment = "\n";
        let p2 = tcom_pair(doc.getPair("k2"));
        tcom_scalar(p2.key).commentBefore = "\n";
        tcom_scalar(p2.value).commentBefore = "\n";
        tcom_scalar(p2.value).comment = "\n";
        // source`` with leading/trailing blank lines (see file header)
        expect_toBe(doc.toString(null), "\nk1:\n\n  v1\n\n\nk2:\n\n  v2\n\n")
      }
    }

    test "trailing comment with trailing empty line (#277)" {
      // source`` ending with a blank line keeps "\n\n" (see file header)
      let src_ = source(`
        environment:
          ### SESSION START ###
          A: "true"
          B: "true"
          ### SESSION END ###

          ### ANOTHER SESSION START ###
          C: "true"
          D: "true"
          ### ANOTHER SESSION END ###
      `) + "\n\n";
      let doc = parseDocument(src_, null);
      expect_toBe(doc.toString(null), src_)
    }
  }

  testset "comment after mapping key (#18)" {
    test "reported" {
      let src_ = "test1:\n  foo:\n    #123\n    bar: 1\n";
      let doc = parseDocument(src_, null);
      expect_toBe(doc.toString(null), src_)
    }

    test "minimal" {
      let src_ = "foo:\n  #123\n  bar: baz\n";
      let doc = parseDocument(src_, null);
      expect_toBe(doc.toString(null), src_)
    }
  }

  testset "trailing comments on collection (#28)" {
    test "reported" {
      let src_ = "# This comment is ok\nentryA:\n  - foo\n\nentryB:\n  - bar # bar comment\n\n# Ending comment\n# Ending comment 2\n";
      let doc = parseDocument(src_, null);
      expect_toBe(doc.toString(null), "# This comment is ok\nentryA:\n  - foo\n\nentryB:\n  - bar # bar comment\n\n# Ending comment\n# Ending comment 2\n")
    }

    test "collection end comment" {
      let src_ = "a: b #c\n#d\n";
      let doc = parseDocument(src_, null);
      expect_toBe(doc.toString(null), "a: b #c\n\n#d\n")
    }

    test "blank line after seq in map" {
      let src_ = "a:\n  - aa\n\nb:\n  - bb\n\nc: cc\n";
      let doc = parseDocument(src_, null);
      expect_toBe(doc.toString(null), src_)
    }

    test "blank line after map in seq" {
      let src_ = "- a: aa\n\n- b: bb\n  c: cc\n\n- d: dd\n";
      let doc = parseDocument(src_, null);
      expect_toBe(doc.toString(null), src_)
    }
  }

  testset "collection end comments" {
    test "seq in seq" {
      let src_ = tcom_src(`
        #0
        - - a
          - b
          #1

        #2
        - d
      `);
      let doc = parseDocument(src_, null);
      expect_toMatchObject(doc.value, [
        [{ "value": "a" }, { "value": "b" }],
        { "value": "d" }
      ]);
      expect_toBe(tcom_seq(tcom_seq(doc.value).items[0]).comment, "1\n\n2");
      expect_toBe(doc.toString(null), tcom_src(`
        #0
        - - a
          - b
          #1

          #2
        - d
      `))
    }

    test "map in seq" {
      let src_ = tcom_src(`
        #0
        - a: 1
          b: 2
          #1

        #2
        - d
      `);
      let doc = parseDocument(src_, null);
      expect_toMatchObject(doc.value, _seq([_map({ "a": 1, "b": 2 }, { "comment": "1\n\n2" }), "d"]));
      expect_toBe(doc.toString(null), tcom_src(`
        #0
        - a: 1
          b: 2
          #1

          #2
        - d
      `))
    }

    test "seq in map" {
      let src_ = tcom_src(`
        #0
        a:
          - b
          - c
          #1

        #2
        d: 1
      `);
      let doc = parseDocument(src_, null);
      expect_toMatchObject(doc.value, _map({ "a": _seq(["b", "c"]), "d": 1 }, null));
      expect_toMatchObject(doc.get("a"), { "comment": "1\n\n2" });
      expect_toBe(doc.toString(null), tcom_src(`
        #0
        a:
          - b
          - c
          #1

          #2
        d: 1
      `))
    }

    test "map in map" {
      let src_ = tcom_src(`
        #0
        a:
          b: 1
          c: 2
          #1

        #2
        d: 1
      `);
      let doc = parseDocument(src_, null);
      expect_toMatchObject(doc.value, _map({ "a": _map({ "b": 1, "c": 2 }, { "comment": "1\n\n2" }), "d": 1 }, null));
      expect_toBe(doc.toString(null), tcom_src(`
        #0
        a:
          b: 1
          c: 2
          #1

          #2
        d: 1
      `))
    }

    test "indented seq in map in seq" {
      let src_ = "#0\na:\n  #1\n  - b:\n      - c\n\n  #2\n  - e\n";
      let doc = parseDocument(src_, null);
      expect_toMatchObject(doc.value, _map({
        "a": _seq([_map({ "b": _seq(["c"]) }, null), {
          "spaceBefore": true,
          "commentBefore": "2",
          "value": "e"
        }])
      }, null));
      expect_toMatchObject(doc.get("a"), { "commentBefore": "1" });
      expect_toBe(doc.toString(null), src_)
    }
  }
}
