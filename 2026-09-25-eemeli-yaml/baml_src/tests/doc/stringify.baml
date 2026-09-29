// Port of tests/doc/stringify.ts
//
// The upstream `for (const [name, version] of …) describe(name, …)` loops
// and the `for … of` loops generating parameterised tests are unrolled.

function tstr_scalar(n: unknown) -> Scalar {
  match (n) {
    let s: Scalar => s,
    _ => baml.sys.panic("expected a Scalar"),
  }
}

function tstr_map(n: unknown) -> YAMLMap {
  match (n) {
    let m: YAMLMap => m,
    _ => baml.sys.panic("expected a YAMLMap"),
  }
}

function tstr_seq(n: unknown) -> YAMLSeq {
  match (n) {
    let s: YAMLSeq => s,
    _ => baml.sys.panic("expected a YAMLSeq"),
  }
}

function tstr_pair(p: Pair?) -> Pair {
  match (p) {
    let q: Pair => q,
    _ => baml.sys.panic("expected a Pair"),
  }
}

/// upstream's `source` template tag. BAML backtick literals drop their
/// boundary newlines, so the final "\n" that `source` keeps is re-added.
function tstr_src(s: string) -> string {
  source(s) + "\n"
}

/// `str.repeat(n)`
function tstr_repeat(s: string, n: int) -> string {
  let out = "";
  let i = 0;
  while (i < n) {
    out = out + s;
    i += 1;
  }
  out
}

/// `str.split('\n').map(line => line.length)`
function tstr_line_lengths(s: string) -> int[] {
  s.split("\n").map((line: string) -> int { line.length() })
}

function tstr_min_fraction_digits(n: unknown, version: string, exp: string) -> null {
  let doc = Document.new(n, null, Options { version: version });
  tstr_scalar(doc.value).minFractionDigits = 2;
  expect_toBe(doc.toString(null), exp)
}

function tstr_timestamp_like(str: string) -> null {
  let res = stringify(str, null, Options { version: "1.1" });
  expect_toBe(res, "\"" + str + "\"\n");
  expect_toBe(parse(res ?? "", null, Options { version: "1.1" }), str)
}

/// `vi.fn((_key, value) => value)` used as a replacer: records the call
/// arguments in `calls` and the `this` value (holder) in `instances`.
class TstrReplacerSpy {
  calls: MockCalls
  instances: unknown[]
}

function tstr_replacer_spy() -> TstrReplacerSpy {
  TstrReplacerSpy { calls: mock_calls(), instances: [] }
}

/// The objects built in `custom indent`'s `beforeEach`.
function tstr_custom_indent_obj() -> unknown {
  let doc = Document.new(null, null, null);
  let seq = tstr_seq(doc.createNode(["a"], null, null));
  seq.commentBefore = "sc";
  let map = tstr_map(doc.createNode({ "foo": "bar", "seq": seq }, null, null));
  map.commentBefore = "mc";
  let obj: map<string, unknown> = { "array": [{ "a": 1, "b": 2 }], "map": map };
  obj
}

/// The objects built in `indentSeq: false`'s `beforeEach`.
function tstr_indent_seq_obj() -> unknown {
  let seq = tstr_seq(Document.new(null, null, null).createNode(["a"], null, null));
  seq.commentBefore = "sc";
  let obj: map<string, unknown> = { "array": [{ "a": 1, "b": 2 }], "map": { "seq": seq } };
  obj
}

/// `new YAML.Document({ foo: ['bar'] })` for the collectionStyle tests.
function tstr_foo_bar_doc() -> Document {
  Document.new({ "foo": ["bar"] }, null, null)
}

testset "doc/stringify" {
  testset "YAML 1.1" {
    let version = "1.1";

    test "undefined" {
      // JS `undefined` is modelled by the `js_undefined()` sentinel.
      expect_toBeNull(stringify(js_undefined(), null, Options { version: version }))
    }

    test "null" {
      expect_toBe(stringify(null, null, Options { version: version }), "null\n")
    }

    testset "boolean" {
      test "true" {
        expect_toBe(stringify(true, null, Options { version: version }), "true\n")
      }
      test "false" {
        expect_toBe(stringify(false, null, Options { version: version }), "false\n")
      }
      test "Boolean" {
        // UNPORTABLE: `new Boolean(true)` (boxed primitive) has no BAML equivalent.
        expect_true(true, "skipped")
      }
    }

    testset "number" {
      test "integer" {
        expect_toBe(stringify(3, null, Options { version: version }), "3\n")
      }
      test "float" {
        expect_toBe(stringify(3.141, null, Options { version: version }), "3.141\n")
      }
      test "zero" {
        expect_toBe(stringify(0, null, Options { version: version }), "0\n")
      }
      test "NaN" {
        expect_toBe(stringify(baml.Float.nan(), null, Options { version: version }), ".nan\n")
      }
      test "Number" {
        // UNPORTABLE: `new Number(3.141)` (boxed primitive) has no BAML equivalent.
        expect_true(true, "skipped")
      }
      test "negative zero" {
        expect_toBe(stringify(-0.0, null, Options { version: version }), "-0\n")
      }

      testset "minFractionDigits" {
        test "number (3) with trailing zeros" {
          tstr_min_fraction_digits(3, version, "3.00\n")
        }
        test "number (-3) with trailing zeros" {
          tstr_min_fraction_digits(-3, version, "-3.00\n")
        }
        test "number (4.2) with trailing zeros" {
          tstr_min_fraction_digits(4.2, version, "4.20\n")
        }
        test "number (4.21) with trailing zeros" {
          tstr_min_fraction_digits(4.21, version, "4.21\n")
        }
        test "number (4.215) with trailing zeros" {
          tstr_min_fraction_digits(4.215, version, "4.215\n")
        }
        test "number (0) with trailing zeros" {
          tstr_min_fraction_digits(0, version, "0.00\n")
        }
        // upstream name is also "number (0) with trailing zeros" (`${-0}` is
        // "0"); BAML test names must be unique.
        test "number (-0) with trailing zeros" {
          tstr_min_fraction_digits(-0.0, version, "-0.00\n")
        }
        test "number (1e+32) with trailing zeros" {
          tstr_min_fraction_digits(1e32, version, "1e+32\n")
        }

        test "scientific float ignores minFractionDigits" {
          let doc = Document.new(3, null, Options { version: version });
          let s = tstr_scalar(doc.value);
          s.format = "EXP";
          s.minFractionDigits = 2;
          expect_toBe(doc.toString(null), "3e+0\n")
        }
      }

      test "integer with HEX format" {
        let doc = Document.new(42, null, Options { version: version });
        tstr_scalar(doc.value).format = "HEX";
        expect_toBe(doc.toString(null), "0x2a\n")
      }
      test "float with HEX format" {
        let doc = Document.new(4.2, null, Options { version: version });
        tstr_scalar(doc.value).format = "HEX";
        expect_toBe(doc.toString(null), "4.2\n")
      }
      test "negative integer with HEX format" {
        let doc = Document.new(-42, null, Options { version: version });
        tstr_scalar(doc.value).format = "HEX";
        let exp = if (version == "1.2") { "-42\n" } else { "-0x2a\n" };
        expect_toBe(doc.toString(null), exp)
      }

      test "bigint" {
        expect_toBe(stringify(js_parse_bigint("-42"), null, Options { version: version }), "-42\n")
      }
      test "BigInt" {
        // UNPORTABLE: `Object(BigInt('-42'))` (boxed primitive) has no BAML equivalent.
        expect_true(true, "skipped")
      }
      test "BigInt with HEX format" {
        let doc = Document.new(js_parse_bigint("42"), null, Options { version: version });
        tstr_scalar(doc.value).format = "HEX";
        expect_toBe(doc.toString(null), "0x2a\n")
      }
      test "BigInt with OCT format" {
        let doc = Document.new(js_parse_bigint("42"), null, Options { version: version });
        tstr_scalar(doc.value).format = "OCT";
        let exp = if (version == "1.2") { "0o52\n" } else { "052\n" };
        expect_toBe(doc.toString(null), exp)
      }
      test "negative BigInt with OCT format" {
        let doc = Document.new(js_parse_bigint("-42"), null, Options { version: version });
        tstr_scalar(doc.value).format = "OCT";
        let exp = if (version == "1.2") { "-42\n" } else { "-052\n" };
        expect_toBe(doc.toString(null), exp)
      }
    }

    testset "string" {
      let opt = Options { lineWidth: 20, minContentWidth: 0, version: version };

      test "plain" {
        expect_toBe(stringify("STR", null, opt), "STR\n")
      }
      test "double-quoted" {
        expect_toBe(stringify("\"x\"", null, opt), "'\"x\"'\n")
      }
      test "single-quoted" {
        expect_toBe(stringify("'x'", null, opt), "\"'x'\"\n")
      }
      test "escaped" {
        expect_toBe(stringify("null: \0", null, opt), "\"null: \\0\"\n")
      }
      test "short multiline" {
        expect_toBe(stringify("blah\nblah\nblah", null, opt), "|-\nblah\nblah\nblah\n")
      }
      test "long multiline" {
        expect_toBe(
          stringify("blah blah\nblah blah blah blah blah blah blah blah blah blah\n", null, opt),
          ">\nblah blah\n\nblah blah blah blah\nblah blah blah blah\nblah blah\n"
        )
      }
      test "String" {
        // UNPORTABLE: `new String('STR')` (boxed primitive) has no BAML equivalent.
        expect_true(true, "skipped")
      }

      test "long line in map" {
        let foo = tstr_repeat("fuzz", 16);
        let doc = Document.new({ "foo": foo }, null, Options { version: version });
        for (let pair in tstr_map(doc.value).values.values()) {
          tstr_scalar(pair.value).type = Scalar.QUOTE_DOUBLE();
        }
        expect_toMatchObject(tstr_line_lengths(doc.toString(opt)), [20, 20, 20, 20, 0])
      }

      test "long line in sequence" {
        let foo = tstr_repeat("fuzz", 16);
        let doc = Document.new([foo], null, Options { version: version });
        for (let node in tstr_seq(doc.value).items) {
          tstr_scalar(node).type = Scalar.QUOTE_DOUBLE();
        }
        expect_toMatchObject(tstr_line_lengths(doc.toString(opt)), [20, 20, 20, 17, 0])
      }

      test "long line in sequence in map" {
        let foo = tstr_repeat("fuzz", 16);
        let doc = Document.new({ "foo": [foo] }, null, Options { version: version });
        let seq = tstr_seq(tstr_map(doc.value).get("foo"));
        for (let node in seq.items) {
          tstr_scalar(node).type = Scalar.QUOTE_DOUBLE();
        }
        expect_toMatchObject(tstr_line_lengths(doc.toString(opt)), [4, 20, 20, 20, 20, 10, 0])
      }

      test "Keep pipe when empty block literal is given" {
        let doc = parseDocument("|-", null);
        expect_toBe(doc.toString(null), "|\n\n")
      }

      test "Keep pipe when pipe is provided" {
        let doc = parseDocument("|", null);
        expect_toBe(doc.toString(null), "|\n\n")
      }
    }
  }

  testset "YAML 1.2" {
    let version = "1.2";

    test "undefined" {
      // JS `undefined` is modelled by the `js_undefined()` sentinel.
      expect_toBeNull(stringify(js_undefined(), null, Options { version: version }))
    }

    test "null" {
      expect_toBe(stringify(null, null, Options { version: version }), "null\n")
    }

    testset "boolean" {
      test "true" {
        expect_toBe(stringify(true, null, Options { version: version }), "true\n")
      }
      test "false" {
        expect_toBe(stringify(false, null, Options { version: version }), "false\n")
      }
      test "Boolean" {
        // UNPORTABLE: `new Boolean(true)` (boxed primitive) has no BAML equivalent.
        expect_true(true, "skipped")
      }
    }

    testset "number" {
      test "integer" {
        expect_toBe(stringify(3, null, Options { version: version }), "3\n")
      }
      test "float" {
        expect_toBe(stringify(3.141, null, Options { version: version }), "3.141\n")
      }
      test "zero" {
        expect_toBe(stringify(0, null, Options { version: version }), "0\n")
      }
      test "NaN" {
        expect_toBe(stringify(baml.Float.nan(), null, Options { version: version }), ".nan\n")
      }
      test "Number" {
        // UNPORTABLE: `new Number(3.141)` (boxed primitive) has no BAML equivalent.
        expect_true(true, "skipped")
      }
      test "negative zero" {
        expect_toBe(stringify(-0.0, null, Options { version: version }), "-0\n")
      }

      testset "minFractionDigits" {
        test "number (3) with trailing zeros" {
          tstr_min_fraction_digits(3, version, "3.00\n")
        }
        test "number (-3) with trailing zeros" {
          tstr_min_fraction_digits(-3, version, "-3.00\n")
        }
        test "number (4.2) with trailing zeros" {
          tstr_min_fraction_digits(4.2, version, "4.20\n")
        }
        test "number (4.21) with trailing zeros" {
          tstr_min_fraction_digits(4.21, version, "4.21\n")
        }
        test "number (4.215) with trailing zeros" {
          tstr_min_fraction_digits(4.215, version, "4.215\n")
        }
        test "number (0) with trailing zeros" {
          tstr_min_fraction_digits(0, version, "0.00\n")
        }
        // upstream name is also "number (0) with trailing zeros" (`${-0}` is
        // "0"); BAML test names must be unique.
        test "number (-0) with trailing zeros" {
          tstr_min_fraction_digits(-0.0, version, "-0.00\n")
        }
        test "number (1e+32) with trailing zeros" {
          tstr_min_fraction_digits(1e32, version, "1e+32\n")
        }

        test "scientific float ignores minFractionDigits" {
          let doc = Document.new(3, null, Options { version: version });
          let s = tstr_scalar(doc.value);
          s.format = "EXP";
          s.minFractionDigits = 2;
          expect_toBe(doc.toString(null), "3e+0\n")
        }
      }

      test "integer with HEX format" {
        let doc = Document.new(42, null, Options { version: version });
        tstr_scalar(doc.value).format = "HEX";
        expect_toBe(doc.toString(null), "0x2a\n")
      }
      test "float with HEX format" {
        let doc = Document.new(4.2, null, Options { version: version });
        tstr_scalar(doc.value).format = "HEX";
        expect_toBe(doc.toString(null), "4.2\n")
      }
      test "negative integer with HEX format" {
        let doc = Document.new(-42, null, Options { version: version });
        tstr_scalar(doc.value).format = "HEX";
        let exp = if (version == "1.2") { "-42\n" } else { "-0x2a\n" };
        expect_toBe(doc.toString(null), exp)
      }

      test "bigint" {
        expect_toBe(stringify(js_parse_bigint("-42"), null, Options { version: version }), "-42\n")
      }
      test "BigInt" {
        // UNPORTABLE: `Object(BigInt('-42'))` (boxed primitive) has no BAML equivalent.
        expect_true(true, "skipped")
      }
      test "BigInt with HEX format" {
        let doc = Document.new(js_parse_bigint("42"), null, Options { version: version });
        tstr_scalar(doc.value).format = "HEX";
        expect_toBe(doc.toString(null), "0x2a\n")
      }
      test "BigInt with OCT format" {
        let doc = Document.new(js_parse_bigint("42"), null, Options { version: version });
        tstr_scalar(doc.value).format = "OCT";
        let exp = if (version == "1.2") { "0o52\n" } else { "052\n" };
        expect_toBe(doc.toString(null), exp)
      }
      test "negative BigInt with OCT format" {
        let doc = Document.new(js_parse_bigint("-42"), null, Options { version: version });
        tstr_scalar(doc.value).format = "OCT";
        let exp = if (version == "1.2") { "-42\n" } else { "-052\n" };
        expect_toBe(doc.toString(null), exp)
      }
    }

    testset "string" {
      let opt = Options { lineWidth: 20, minContentWidth: 0, version: version };

      test "plain" {
        expect_toBe(stringify("STR", null, opt), "STR\n")
      }
      test "double-quoted" {
        expect_toBe(stringify("\"x\"", null, opt), "'\"x\"'\n")
      }
      test "single-quoted" {
        expect_toBe(stringify("'x'", null, opt), "\"'x'\"\n")
      }
      test "escaped" {
        expect_toBe(stringify("null: \0", null, opt), "\"null: \\0\"\n")
      }
      test "short multiline" {
        expect_toBe(stringify("blah\nblah\nblah", null, opt), "|-\nblah\nblah\nblah\n")
      }
      test "long multiline" {
        expect_toBe(
          stringify("blah blah\nblah blah blah blah blah blah blah blah blah blah\n", null, opt),
          ">\nblah blah\n\nblah blah blah blah\nblah blah blah blah\nblah blah\n"
        )
      }
      test "String" {
        // UNPORTABLE: `new String('STR')` (boxed primitive) has no BAML equivalent.
        expect_true(true, "skipped")
      }

      test "long line in map" {
        let foo = tstr_repeat("fuzz", 16);
        let doc = Document.new({ "foo": foo }, null, Options { version: version });
        for (let pair in tstr_map(doc.value).values.values()) {
          tstr_scalar(pair.value).type = Scalar.QUOTE_DOUBLE();
        }
        expect_toMatchObject(tstr_line_lengths(doc.toString(opt)), [20, 20, 20, 20, 0])
      }

      test "long line in sequence" {
        let foo = tstr_repeat("fuzz", 16);
        let doc = Document.new([foo], null, Options { version: version });
        for (let node in tstr_seq(doc.value).items) {
          tstr_scalar(node).type = Scalar.QUOTE_DOUBLE();
        }
        expect_toMatchObject(tstr_line_lengths(doc.toString(opt)), [20, 20, 20, 17, 0])
      }

      test "long line in sequence in map" {
        let foo = tstr_repeat("fuzz", 16);
        let doc = Document.new({ "foo": [foo] }, null, Options { version: version });
        let seq = tstr_seq(tstr_map(doc.value).get("foo"));
        for (let node in seq.items) {
          tstr_scalar(node).type = Scalar.QUOTE_DOUBLE();
        }
        expect_toMatchObject(tstr_line_lengths(doc.toString(opt)), [4, 20, 20, 20, 20, 10, 0])
      }

      test "Keep pipe when empty block literal is given" {
        let doc = parseDocument("|-", null);
        expect_toBe(doc.toString(null), "|\n\n")
      }

      test "Keep pipe when pipe is provided" {
        let doc = parseDocument("|", null);
        expect_toBe(doc.toString(null), "|\n\n")
      }
    }
  }

  testset "timestamp-like string (YAML 1.1)" {
    test "canonical" {
      tstr_timestamp_like("2001-12-15T02:59:43.1Z")
    }
    test "validIso8601" {
      tstr_timestamp_like("2001-12-14t21:59:43.10-05:00")
    }
    test "spaceSeparated" {
      tstr_timestamp_like("2001-12-14 21:59:43.10 -5")
    }
    test "noTimeZone" {
      tstr_timestamp_like("2001-12-15 2:59:43.10")
    }
  }

  // https://github.com/tc39/proposal-well-formed-stringify
  testset "unpaired surrogate pairs of Unicode code points" {
    test "𝌆" {
      expect_toBe(yaml_stringify("𝌆"), "𝌆\n")
    }
    // upstream name is the JS string '\uD834\uDF06', i.e. the same as the
    // previous test's name; BAML test names must be unique and BAML strings
    // cannot spell surrogate escapes, so the name is spelled out. The value
    // (a well-formed surrogate pair) is the single code point U+1D306.
    test "\\uD834\\uDF06" {
      expect_toBe(yaml_stringify("𝌆"), "𝌆\n")
    }
    test "😀" {
      expect_toBe(yaml_stringify("😀"), "😀\n")
    }
    test "\\uD83D\\uDE00" {
      expect_toBe(yaml_stringify("😀"), "😀\n")
    }
    test "\\uDF06\\uD834" {
      // UNPORTABLE: lone UTF-16 surrogates cannot be represented in a BAML
      // (UTF-8) string.
      expect_true(true, "skipped")
    }
    test "\\uDEAD" {
      // UNPORTABLE: lone UTF-16 surrogates cannot be represented in a BAML
      // (UTF-8) string.
      expect_true(true, "skipped")
    }
  }

  testset "circular references" {
    test "parent at root" {
      let map: map<string, unknown> = { "foo": "bar" };
      map["map"] = map;
      expect_toBe(yaml_stringify(map), "&a1\nfoo: bar\nmap: *a1\n")
    }

    test "ancestor at root" {
      let baz: map<string, unknown> = {};
      let map: map<string, unknown> = { "foo": { "bar": { "baz": baz } } };
      baz["map"] = map;
      expect_toBe(yaml_stringify(map), "&a1\nfoo:\n  bar:\n    baz:\n      map: *a1\n")
    }

    test "sibling sequences" {
      let one = ["one"];
      let two = ["two"];
      let seq = [one, two, one, one, two];
      expect_toBe(yaml_stringify(seq), "- &a1\n  - one\n- &a2\n  - two\n- *a1\n- *a1\n- *a2\n")
    }

    test "further relatives" {
      let baz: map<string, unknown> = { "a": 1 };
      let seq = [{ "foo": { "bar": { "baz": baz } } }, { "fe": { "fi": { "fo": { "baz": baz } } } }];
      expect_toBe(yaml_stringify(seq), "- foo:\n    bar:\n      baz: &a1\n        a: 1\n- fe:\n    fi:\n      fo:\n        baz: *a1\n")
    }

    test "only match objects" {
      let date = js_date(js_date_utc(2001, 11, 15, 2, 59, 43, 100));
      let seq: unknown[] = ["a", "a", 1, 1, true, true, date, date];
      expect_toBe(
        stringify(seq, null, Options { anchorPrefix: "foo", version: "1.1" }),
        "- a\n- a\n- 1\n- 1\n- true\n- true\n- &foo1 2001-12-15T02:59:43.100Z\n- *foo1\n"
      )
    }

    test "do not match nulls" {
      let set: map<string, unknown> = { "a": null, "b": null };
      expect_toBe(yaml_stringify(set), "a: null\nb: null\n")
    }
  }

  test "array" {
    let array: unknown[] = [3, ["four", 5]];
    let str = yaml_stringify(array);
    expect_toBe(str, "- 3\n- - four\n  - 5\n")
  }

  testset "maps" {
    test "JS Object" {
      let object: map<string, unknown> = { "x": 3, "y": [4], "z": { "w": "five", "v": 6 } };
      let str = yaml_stringify(object);
      expect_toBe(str, "x: 3\ny:\n  - 4\nz:\n  w: five\n  v: 6\n")
    }

    test "pushing non-Pair item" {
      let doc = Document.new({ "x": 3, "y": 4 }, null, null);
      expect_toBe(doc.toString(null), "x: 3\ny: 4\n");
      // UNPORTABLE (second assertion): `doc.value.push('TEST')` calls a
      // method YAMLMap does not have (a `@ts-expect-error` in upstream, a
      // TypeError at runtime). In BAML this is a compile-time error, so it
      // cannot be written.
    }

    test "Keep block scalar types for keys" {
      let doc = parseDocument("? >+ #comment\n foo\n\n: bar", null);
      expect_toBe(doc.toString(null), "? >+ #comment\n  foo\n\n: bar\n")
    }

    test "Document as key" {
      let doc = Document.new({ "a": 1 }, null, null);
      doc.set(Document.new({ "b": 2, "c": 3 }, null, null), null);
      expect_toBe(doc.toString(null), "a: 1\n? b: 2\n  c: 3\n")
    }

    test "plain key containing flow indicators" {
      let doc = parseDocument("foo[{}]: bar", null);
      expect_toBe(doc.toString(null), "foo[{}]: bar\n")
    }

    testset "No extra whitespace for empty values" {
      test "Block map, no comments" {
        expect_toBe(tstr_null_doc().toString(Options { nullStr: "" }), "a:\nb:\n")
      }

      test "Block map, with key.comment" {
        let doc = tstr_null_doc();
        doc.set("a", Scalar.new(null));
        tstr_scalar(tstr_pair(doc.getPair("a")).key).comment = "c";
        expect_toBe(doc.toString(Options { nullStr: "" }), "a: #c\nb:\n")
      }

      test "Block map, with value.commentBefore" {
        let doc = tstr_null_doc();
        doc.set("a", Scalar.new(null));
        tstr_scalar(doc.get("a")).commentBefore = "c";
        expect_toBe(doc.toString(Options { nullStr: "" }), "a:\n  #c\nb:\n")
      }

      test "Flow map, no comments" {
        let doc = tstr_null_doc();
        tstr_map(doc.value).flow = true;
        expect_toBe(doc.toString(Options { nullStr: "" }), "{ a:, b: }\n")
      }

      test "Flow map, with key.comment" {
        let doc = tstr_null_doc();
        tstr_map(doc.value).flow = true;
        tstr_scalar(tstr_pair(doc.getPair("a")).key).comment = "c";
        expect_toBe(doc.toString(Options { nullStr: "" }), "{\n  a:, #c\n  b:\n}\n")
      }

      test "Flow map, with value.commentBefore" {
        let doc = tstr_null_doc();
        tstr_map(doc.value).flow = true;
        doc.set("a", Scalar.new(null));
        tstr_scalar(doc.get("a")).commentBefore = "c";
        expect_toBe(doc.toString(Options { nullStr: "" }), "{\n  a:\n    #c\n    ,\n  b:\n}\n")
      }

      test "Single newline after key with empty value" {
        let src_ = "map:\n  item:\n\nanothermap:\n  anotheritem:\n\n";
        let doc = parseDocument(src_, null);
        expect_toBe(doc.toString(null), src_)
      }
    }

    testset "properties on collections in block mapping" {
      test "explicit tag on block sequence" {
        let src_ = tstr_src(`
        key: !tag
          - one
          - two
      `);
        let doc = parseDocument(src_, null);
        expect_toBe(doc.toString(null), src_)
      }
      test "explicit tag on block mapping" {
        let src_ = tstr_src(`
        key: !tag
          one: 1
          two: 2
      `);
        let doc = parseDocument(src_, null);
        expect_toBe(doc.toString(null), src_)
      }
      test "single-line comment on block sequence" {
        let src_ = tstr_src(`
        key: #comment
          - one
          - two
      `);
        let doc = parseDocument(src_, null);
        expect_toBe(doc.toString(null), tstr_src(`
        key:
          #comment
          - one
          - two
      `))
      }
      test "single-line comment and explicit tag on block sequence" {
        let src_ = tstr_src(`
        key: #comment
          !tag
          - one
          - two
      `);
        let doc = parseDocument(src_, null);
        expect_toBe(doc.toString(null), tstr_src(`
        key:
          #comment
          !tag
          - one
          - two
      `))
      }
      test "explicit tag and comment on block sequence" {
        let src_ = tstr_src(`
        key: !tag
          #comment
          - one
          - two
      `);
        let doc = parseDocument(src_, null);
        expect_toBe(doc.toString(null), tstr_src(`
        key:
          #comment
          !tag
          - one
          - two
      `))
      }
      test "anchor on block sequence" {
        let src_ = tstr_src(`
        key: &anchor
          - one
          - two
      `);
        let doc = parseDocument(src_, null);
        expect_toBe(doc.toString(null), src_)
      }
      test "anchor and explicit tag on block sequence" {
        let src_ = tstr_src(`
        key: &anchor !tag
          - one
          - two
      `);
        let doc = parseDocument(src_, null);
        expect_toBe(doc.toString(null), src_)
      }
      test "explicit tag on empty mapping" {
        let empty: map<string, unknown> = {};
        let doc = Document.new({ "key": empty }, null, null);
        tstr_map(doc.get("key")).tag = "!tag";
        expect_toBe(doc.toString(null), tstr_src(`
        key: !tag {}
      `))
      }
      test "explicit tag on single-line flow mapping" {
        let src_ = tstr_src(`
        key: !tag { one: 1, two: 2 }
      `);
        let doc = parseDocument(src_, null);
        expect_toBe(doc.toString(null), src_)
      }
      test "explicit tag on multi-line flow mapping" {
        let src_ = tstr_src(`
        key: !tag {
          one: aaaaaaaaaa,
          two: bbbbbbbbbb,
          three: cccccccccc,
          four: dddddddddd,
          five: eeeeeeeeee
        }
      `);
        let doc = parseDocument(src_, null);
        expect_toBe(doc.toString(null), tstr_src(`
        key:
          !tag {
            one: aaaaaaaaaa,
            two: bbbbbbbbbb,
            three: cccccccccc,
            four: dddddddddd,
            five: eeeeeeeeee
          }
      `))
      }
      test "explicit tag on explicit-value block sequence" {
        let src_ = tstr_src(`
        ? [ key ]
        : !tag
          - one
          - two
      `);
        let doc = parseDocument(src_, null);
        expect_toBe(doc.toString(null), src_)
      }
    }

    testset "trailing comma (maps)" {
      test "no trailing comma is added when the flow map is shorter than the word wrap length" {
        let doc = parseDocument(tstr_src(`
        {
          a: aaa,
          b: bbb,
          c: ccc
        }
        `), null);
        expect_toBe(doc.toString(Options { trailingComma: true, lineWidth: 40 }), "{ a: aaa, b: bbb, c: ccc }\n")
      }
      test "no trailing comma is added when the flow map is exactly the word wrap length" {
        let doc = parseDocument(tstr_src(`
        {
          a: aaa,
          b: bbb,
          c: ccc,
          d: dddddd
        }
        `), null);
        expect_toBe(doc.toString(Options { trailingComma: true, lineWidth: 40 }), "{ a: aaa, b: bbb, c: ccc, d: dddddd }\n")
      }
      test "a trailing comma is added when the flow map is exactly one more than the word wrap length" {
        let doc = parseDocument(tstr_src(`
        {
          a: aaa,
          b: bbb,
          c: ccc,
          d: ddddddd
        }
        `), null);
        expect_toBe(doc.toString(Options { trailingComma: true, lineWidth: 40 }), "{\n  a: aaa,\n  b: bbb,\n  c: ccc,\n  d: ddddddd,\n}\n")
      }
      test "no trailing comma is added when the word wrap length is 0" {
        let doc = parseDocument(tstr_src(`
        {
          a: aaa,
          b: bbb,
          c: ccc
        }
        `), null);
        expect_toBe(doc.toString(Options { trailingComma: true, lineWidth: 0 }), "{ a: aaa, b: bbb, c: ccc }\n")
      }
      test "a trailing comma is added when a comment is present in the flow map" {
        let doc = parseDocument(tstr_src(`
        {
          a: aaa, # my cool comment
          b: bbb,
          c: ccc
        }
        `), null);
        expect_toBe(doc.toString(Options { trailingComma: true }), "{\n  a: aaa, # my cool comment\n  b: bbb,\n  c: ccc,\n}\n")
      }
      test "a trailing comma is added when a newline is present in the flow map" {
        let doc = parseDocument(tstr_src(`
        {
          a: aaa,

          b: bbb
        }
        `), null);
        expect_toBe(doc.toString(Options { trailingComma: true }), "{\n  a: aaa,\n\n  b: bbb,\n}\n")
      }
      test "a trailing comma is added when one of the entries includes a newline" {
        let doc = parseDocument(tstr_src(`
        {
          a: {
            a: a # a
          },
          b: bbb
        }
        `), null);
        expect_toBe(doc.toString(Options { trailingComma: true }), "{\n  a:\n    {\n      a: a, # a\n    },\n  b: bbb,\n}\n")
      }
    }

    testset "trailing comma (arrays)" {
      test "no trailing comma is added when the flow array is shorter than the word wrap length" {
        let doc = parseDocument(tstr_src(`
        [
          aaa,
          bbb,
          ccc
        ]
        `), null);
        expect_toBe(doc.toString(Options { trailingComma: true, lineWidth: 40 }), "[ aaa, bbb, ccc ]\n")
      }
      test "no trailing comma is added when the flow array is exactly the word wrap length" {
        let doc = parseDocument(tstr_src(`
        [
          aaaaaa,
          bbbbbb,
          cccccc,
          ddddddddd
        ]
        `), null);
        expect_toBe(doc.toString(Options { trailingComma: true, lineWidth: 40 }), "[ aaaaaa, bbbbbb, cccccc, ddddddddd ]\n")
      }
      test "a trailing comma is added when the flow array is exactly one more than the word wrap length" {
        let doc = parseDocument(tstr_src(`
        [
          aaaaaa,
          bbbbbb,
          cccccc,
          dddddddddd
        ]
        `), null);
        expect_toBe(doc.toString(Options { trailingComma: true, lineWidth: 40 }), "[\n  aaaaaa,\n  bbbbbb,\n  cccccc,\n  dddddddddd,\n]\n")
      }
      test "no trailing comma is added when the word wrap length is 0" {
        let doc = parseDocument(tstr_src(`
        [
          aaa,
          bbb,
          ccc
        ]
        `), null);
        expect_toBe(doc.toString(Options { trailingComma: true, lineWidth: 0 }), "[ aaa, bbb, ccc ]\n")
      }
      test "a trailing comma is added when a comment is present in the flow array" {
        let doc = parseDocument(tstr_src(`
        [
          aaa, # my cool comment
          bbb,
          ccc
        ]
        `), null);
        expect_toBe(doc.toString(Options { trailingComma: true }), "[\n  aaa, # my cool comment\n  bbb,\n  ccc,\n]\n")
      }
      test "a trailing comma is added when a newline is present in the flow array" {
        let doc = parseDocument(tstr_src(`
        [
          aaa,

          bbb
        ]
        `), null);
        expect_toBe(doc.toString(Options { trailingComma: true }), "[\n  aaa,\n\n  bbb,\n]\n")
      }
      test "a trailing comma is added when one of the entries includes a newline" {
        let doc = parseDocument(tstr_src(`
        [
          {
            a: a # a
          },
          bbb
        ]
        `), null);
        expect_toBe(doc.toString(Options { trailingComma: true }), "[\n  {\n      a: a, # a\n    },\n  bbb,\n]\n")
      }
    }
  }

  test "Quoting colons (#43)" {
    let doc = Document.new({ "key": ":" }, null, null);
    let str = doc.toString(null);
    expect_not_toThrow(() -> unknown { yaml_parse(str) });
    expect_toBe(str, "key: \":\"\n")
  }

  test "Quoting item markers (#52)" {
    let doc = Document.new({ "key": "-" }, null, null);
    let str = doc.toString(null);
    expect_not_toThrow(() -> unknown { yaml_parse(str) });
    expect_toBe(str, "key: \"-\"\n");
    doc.value = doc.createNode({ "key": "?" }, null, null);
    let str2 = doc.toString(null);
    expect_not_toThrow(() -> unknown { yaml_parse(str2) });
    expect_toBe(str2, "key: \"?\"\n")
  }

  test "reserved names" {
    let str = yaml_stringify({ "comment": "foo" });
    expect_toBe(str, "comment: foo\n")
  }

  testset "Collection pairs with single-line flow collections (#85)" {
    test "reported" {
      let str = "testArray: []\ntestObject: {}\ntestArray2: [ \"hello\" ]\n";
      let doc = parseDocument(str, null);
      expect_toBe(doc.toString(null), str)
    }

    test "multiline flow collection" {
      let str = "foo: [ bar, bar, bar, bar, bar, bar, bar, bar, bar, bar, bar, bar, bar, bar, bar, bar, bar, bar ]";
      let doc = parseDocument(str, null);
      let str2 = doc.toString(null);
      expect_toMatch(str2, "^foo:\\n {2}\\[\\n {4}bar");
      expect_toMatchObject(yaml_parse(str2), doc.toJS(null))
    }
  }

  test "set(object) in collection (#87)" {
    let doc = parseDocument("test: x", null);
    doc.set("test", { "a": "test" });
    expect_toBe(doc.toString(null), "test:\n  a: test\n")
  }

  testset "Custom null/bool string representations" {
    test "tilde null" {
      let doc = yaml_parse("a: null");
      let str = stringify(doc, null, Options { nullStr: "~", simpleKeys: true });
      expect_toBe(str, "a: ~\n");
      expect_toEqual(yaml_parse(str ?? ""), { "a": null })
    }

    test "empty string null" {
      let doc = yaml_parse("a: null");
      let str = stringify(doc, null, Options { nullStr: "", simpleKeys: true });
      expect_toBe(str, "a:\n");
      expect_toEqual(yaml_parse(str ?? ""), { "a": null })
    }

    test "empty string camelBool" {
      let doc = yaml_parse("[true, false]");
      let str = stringify(doc, null, Options { trueStr: "True", falseStr: "False" });
      expect_toBe(str, "- True\n- False\n");
      expect_toEqual(yaml_parse(str ?? ""), [true, false])
    }

    test "empty string upperBool" {
      let doc = yaml_parse("[true, false]");
      let str = stringify(doc, null, Options { trueStr: "TRUE", falseStr: "FALSE" });
      expect_toBe(str, "- TRUE\n- FALSE\n");
      expect_toEqual(yaml_parse(str ?? ""), [true, false])
    }
  }

  testset "scalar styles" {
    test "null Scalar styles" {
      let doc = parseDocument("[ null, Null, NULL, ~ ]", null);
      expect_toBe(doc.toString(null), "[ null, Null, NULL, ~ ]\n")
    }

    test "bool Scalar styles on core" {
      let doc = parseDocument("[ true, false, True, False, TRUE, FALSE, on, off, y, n ]", null);
      let str = "[\n  true,\n  false,\n  True,\n  False,\n  TRUE,\n  FALSE,\n  on,\n  off,\n  y,\n  n\n]\n";
      expect_toBe(doc.toString(Options { lineWidth: 1 }), str);
      let exp: unknown[] = [true, false, true, false, true, false, "on", "off", "y", "n"];
      expect_toEqual(yaml_parse(str), exp)
    }

    test "bool Scalar styles on YAML1.1" {
      let doc = parseDocument(
        "[ n, N, NO, no, No, False, false, FALSE, FALse, Off, off, OFF, OfF, y, Y, Yes, yes, YES, true, True, TRUE, ON, on, On ]",
        Options { schema: "yaml-1.1" }
      );
      let str = "[\n  n,\n  N,\n  NO,\n  no,\n  No,\n  False,\n  false,\n  FALSE,\n  FALse,\n  Off,\n  off,\n  OFF,\n  OfF,\n  y,\n  Y,\n  Yes,\n  yes,\n  YES,\n  true,\n  True,\n  TRUE,\n  ON,\n  on,\n  On\n]\n";
      expect_toBe(doc.toString(null), str);
      let exp: unknown[] = [false, false, false, false, false, false, false, false, "FALse", false, false, false, "OfF", true, true, true, true, true, true, true, true, true, true, true];
      expect_toEqual(parse(str, null, Options { schema: "yaml-1.1" }), exp)
    }
  }

  testset "simple keys" {
    test "key with no value" {
      let doc = parseDocument("? ~", null);
      expect_toBe(doc.toString(null), "~: null\n");
      expect_toBe(doc.toString(Options { simpleKeys: true }), "~: null\n")
    }

    test "key with block scalar value" {
      let doc = parseDocument("foo: bar", null);
      tstr_scalar(tstr_pair(tstr_map(doc.value).getPair("foo")).key).type = "BLOCK_LITERAL";
      expect_toBe(doc.toString(null), "? |-\n  foo\n: bar\n");
      expect_toBe(doc.toString(Options { simpleKeys: true }), "\"foo\": bar\n")
    }

    test "key with comment" {
      let doc = parseDocument("foo: bar", null);
      tstr_scalar(tstr_pair(tstr_map(doc.value).getPair("foo")).key).comment = "FOO";
      expect_toBe(doc.toString(null), "foo: #FOO\n  bar\n");
      expect_toThrow(() -> unknown { doc.toString(Options { simpleKeys: true }) }, "With simple keys, key nodes cannot have comments")
    }

    test "key with collection value" {
      let doc = parseDocument("[foo]: bar", null);
      expect_toBe(doc.toString(null), "? [ foo ]\n: bar\n");
      expect_toThrow(() -> unknown { doc.toString(Options { simpleKeys: true }) }, "With simple keys, collection cannot be used as a key value")
    }

    test "key value length > 1024" {
      let str = "\n    ? " + tstr_repeat("a", 1025) + "\n    : longkey";
      let doc = parseDocument(str, null);
      expect_toBe(doc.toString(null), "? " + tstr_repeat("a", 1025) + "\n: longkey\n");
      expect_toThrow(() -> unknown { doc.toString(Options { simpleKeys: true }) }, "With simple keys, single line scalar must not span more than 1024 characters")
    }
  }

  test "YAML node inside object (#128)" {
    let doc = Document.new(null, null, null);
    let seq = tstr_seq(doc.createNode(["a"], null, null));
    seq.commentBefore = "sc";
    let map = tstr_map(doc.createNode({ "foo": "bar", "seq": seq }, null, null));
    map.commentBefore = "mc";
    let obj: map<string, unknown> = { "array": [1], "map": map };
    expect_toBe(yaml_stringify(obj), tstr_src(`
    array:
      - 1
    map:
      #mc
      foo: bar
      seq:
        #sc
        - a
  `))
  }

  testset "sortMapEntries" {
    let obj: map<string, unknown> = { "b": 2, "a": 1, "c": 3 };
    test "sortMapEntries: undefined" {
      expect_toBe(yaml_stringify(obj), "b: 2\na: 1\nc: 3\n")
    }
    test "sortMapEntries: true" {
      expect_toBe(stringify(obj, null, Options { sortMapEntries: true }), "a: 1\nb: 2\nc: 3\n")
    }
    test "sortMapEntries: function" {
      // `a.key < b.key` compares the key Scalars via their toString(), i.e.
      // String(value).
      let sortMapEntries = (a: Pair, b: Pair) -> int {
        let ak = js_string(tstr_scalar(a.key).value);
        let bk = js_string(tstr_scalar(b.key).value);
        if (ak < bk) { 1 } else if (ak > bk) { -1 } else { 0 }
      };
      expect_toBe(stringify(obj, null, Options { sortMapEntries: sortMapEntries }), "c: 3\nb: 2\na: 1\n")
    }
    test "map.set" {
      let doc = Document.new(obj, null, null);
      tstr_map(doc.value).set(doc.createPair("bb", 4, null), null);
      expect_toBe(doc.toString(Options { sortMapEntries: true }), "a: 1\nb: 2\nbb: 4\nc: 3\n")
    }
    test "doc.set with toStringDefaults" {
      let doc = Document.new(obj, null, Options { toStringDefaults: Options { sortMapEntries: true } });
      doc.set("bb", 4);
      expect_toBe(doc.toString(null), "a: 1\nb: 2\nbb: 4\nc: 3\n")
    }
  }

  testset "custom indent" {
    test "indent: 0" {
      let obj = tstr_custom_indent_obj();
      expect_toThrow(() -> unknown { stringify(obj, null, Options { indent: 0 }) }, "must be a positive integer")
    }

    test "indent: 1" {
      let obj = tstr_custom_indent_obj();
      expect_toBe(stringify(obj, null, Options { indent: 1 }), tstr_src(`
      array:
       - a: 1
         b: 2
      map:
       #mc
       foo: bar
       seq:
        #sc
        - a
    `))
    }

    test "indent: 4" {
      let obj = tstr_custom_indent_obj();
      expect_toBe(stringify(obj, null, Options { indent: 4 }), tstr_src(`
      array:
          - a: 1
            b: 2
      map:
          #mc
          foo: bar
          seq:
              #sc
              - a
    `))
    }
  }

  testset "indentSeq: false" {
    test "indent: 1" {
      let obj = tstr_indent_seq_obj();
      expect_toBe(stringify(obj, null, Options { indent: 1, indentSeq: false }), tstr_src(`
      array:
       - a: 1
         b: 2
      map:
       seq:
        #sc
        - a
    `))
    }

    test "indent: 2" {
      let obj = tstr_indent_seq_obj();
      expect_toBe(stringify(obj, null, Options { indent: 2, indentSeq: false }), tstr_src(`
      array:
      - a: 1
        b: 2
      map:
        seq:
        #sc
        - a
    `))
    }

    test "indent: 4" {
      let obj = tstr_indent_seq_obj();
      expect_toBe(stringify(obj, null, Options { indent: 4, indentSeq: false }), tstr_src(`
      array:
        - a: 1
          b: 2
      map:
          seq:
            #sc
            - a
    `))
    }
  }

  testset "lineWidth" {
    let doc = parseDocument(
      "[ 'Sed', 'ut', 'perspiciatis', 'unde', 'omnis', 'iste', 'natus', 'error', 'sit', 'voluptatem', 'accusantium', 'doloremque', 'laudantium,', 'totam' ]",
      null
    );

    test "limit to 80 with overlong flow collection" {
      expect_toBe(
        doc.toString(Options { lineWidth: 80 }),
        "[\n  'Sed',\n  'ut',\n  'perspiciatis',\n  'unde',\n  'omnis',\n  'iste',\n  'natus',\n  'error',\n  'sit',\n  'voluptatem',\n  'accusantium',\n  'doloremque',\n  'laudantium,',\n  'totam'\n]\n"
      )
    }

    test "limit > flow collection length" {
      expect_toBe(
        doc.toString(Options { lineWidth: 162 }),
        "[ 'Sed', 'ut', 'perspiciatis', 'unde', 'omnis', 'iste', 'natus', 'error', 'sit', 'voluptatem', 'accusantium', 'doloremque', 'laudantium,', 'totam' ]\n"
      )
    }

    test "less than minContentWidth (#562)" {
      let doc2 = parseDocument(">\ntest test test test test", null);
      expect_toBe(doc2.toString(Options { lineWidth: 18, minContentWidth: 20 }), ">\ntest test test\ntest test\n")
    }
  }

  testset "collectionStyle" {
    test "collectionStyle: undefined" {
      let doc = tstr_foo_bar_doc();
      expect_toBe(doc.toString(null), "foo:\n  - bar\n");

      tstr_map(doc.value).flow = false;
      tstr_seq(doc.get("foo")).flow = true;
      expect_toBe(doc.toString(null), "foo: [ bar ]\n");

      tstr_map(doc.value).flow = true;
      tstr_seq(doc.get("foo")).flow = false;
      expect_toBe(doc.toString(null), "{ foo: [ bar ] }\n")
    }

    test "collectionStyle: 'any'" {
      let doc = tstr_foo_bar_doc();
      expect_toBe(doc.toString(Options { collectionStyle: "any" }), "foo:\n  - bar\n");

      tstr_map(doc.value).flow = false;
      tstr_seq(doc.get("foo")).flow = true;
      expect_toBe(doc.toString(Options { collectionStyle: "any" }), "foo: [ bar ]\n");

      tstr_map(doc.value).flow = true;
      tstr_seq(doc.get("foo")).flow = false;
      expect_toBe(doc.toString(Options { collectionStyle: "any" }), "{ foo: [ bar ] }\n")
    }

    test "collectionStyle: 'block'" {
      let doc = tstr_foo_bar_doc();
      expect_toBe(doc.toString(Options { collectionStyle: "block" }), "foo:\n  - bar\n");

      tstr_map(doc.value).flow = false;
      tstr_seq(doc.get("foo")).flow = true;
      expect_toBe(doc.toString(Options { collectionStyle: "block" }), "foo:\n  - bar\n");

      tstr_map(doc.value).flow = true;
      tstr_seq(doc.get("foo")).flow = false;
      expect_toBe(doc.toString(Options { collectionStyle: "block" }), "foo:\n  - bar\n")
    }

    test "collectionStyle: 'flow'" {
      let doc = tstr_foo_bar_doc();
      expect_toBe(doc.toString(Options { collectionStyle: "flow" }), "{ foo: [ bar ] }\n");

      tstr_seq(doc.get("foo")).flow = true;
      expect_toBe(doc.toString(Options { collectionStyle: "flow" }), "{ foo: [ bar ] }\n");

      tstr_map(doc.value).flow = true;
      tstr_seq(doc.get("foo")).flow = false;
      expect_toBe(doc.toString(Options { collectionStyle: "flow" }), "{ foo: [ bar ] }\n")
    }
  }

  testset "Scalar options" {
    testset "defaultStringType & defaultKeyType" {
      test "PLAIN, PLAIN" {
        let opt = Options { defaultStringType: Scalar.PLAIN(), defaultKeyType: Scalar.PLAIN() };
        expect_toBe(stringify({ "foo": "bar" }, null, opt), "foo: bar\n")
      }

      test "BLOCK_FOLDED, BLOCK_FOLDED" {
        let opt = Options { defaultStringType: Scalar.BLOCK_FOLDED(), defaultKeyType: Scalar.BLOCK_FOLDED() };
        expect_toBe(stringify({ "foo": "bar" }, null, opt), "\"foo\": |-\n  bar\n")
      }

      test "QUOTE_DOUBLE, PLAIN" {
        let opt = Options { defaultStringType: Scalar.QUOTE_DOUBLE(), defaultKeyType: Scalar.PLAIN() };
        expect_toBe(stringify({ "foo": "bar" }, null, opt), "foo: \"bar\"\n")
      }

      test "QUOTE_DOUBLE, QUOTE_SINGLE" {
        let opt = Options { defaultStringType: Scalar.QUOTE_DOUBLE(), defaultKeyType: Scalar.QUOTE_SINGLE() };
        expect_toBe(stringify({ "foo": "bar" }, null, opt), "'foo': \"bar\"\n")
      }

      test "QUOTE_DOUBLE, null" {
        let opt = Options { defaultStringType: Scalar.QUOTE_DOUBLE(), defaultKeyType: null };
        expect_toBe(stringify({ "foo": "bar" }, null, opt), "\"foo\": \"bar\"\n")
      }

      test "Use defaultStringType for explicit keys" {
        let opt = Options { blockQuote: false, defaultStringType: Scalar.QUOTE_DOUBLE(), defaultKeyType: Scalar.QUOTE_SINGLE() };
        let doc = Document.new({ "foo": null }, null, null);
        let key = tstr_scalar(tstr_pair(doc.getPair("foo")).key);
        key.type = Scalar.BLOCK_LITERAL();
        expect_toBe(doc.toString(opt), "? \"foo\"\n")
      }
    }

    testset "singleQuote: null" {
      let opt = Options { singleQuote: null };

      test "plain" {
        expect_toBe(stringify("foo bar", null, opt), "foo bar\n")
      }
      test "contains double-quote" {
        expect_toBe(stringify("foo: \"bar\"", null, opt), "'foo: \"bar\"'\n")
      }
      test "contains single-quote" {
        expect_toBe(stringify("foo: 'bar'", null, opt), "\"foo: 'bar'\"\n")
      }
      test "numerical string" {
        expect_toBe(stringify("123", null, opt), "\"123\"\n")
      }
      test "upgrade from plain" {
        expect_toBe(stringify("foo #bar", null, opt), "\"foo #bar\"\n")
      }
      test "parsed node" {
        let doc = parseDocument("'foo'", null);
        expect_toBe(doc.toString(opt), "'foo'\n")
      }
    }

    testset "singleQuote: false" {
      let opt = Options { singleQuote: false };

      test "plain" {
        expect_toBe(stringify("foo bar", null, opt), "foo bar\n")
      }
      test "contains double-quote" {
        expect_toBe(stringify("foo: \"bar\"", null, opt), "\"foo: \\\"bar\\\"\"\n")
      }
      test "contains single-quote" {
        expect_toBe(stringify("foo: 'bar'", null, opt), "\"foo: 'bar'\"\n")
      }
      test "numerical string" {
        expect_toBe(stringify("123", null, opt), "\"123\"\n")
      }
      test "upgrade from plain" {
        expect_toBe(stringify("foo #bar", null, opt), "\"foo #bar\"\n")
      }
      test "parsed node" {
        let doc = parseDocument("'foo'", null);
        expect_toBe(doc.toString(opt), "\"foo\"\n")
      }
    }

    testset "singleQuote: true" {
      let opt = Options { singleQuote: true };

      test "plain" {
        expect_toBe(stringify("foo bar", null, opt), "foo bar\n")
      }
      test "contains double-quote" {
        expect_toBe(stringify("foo: \"bar\"", null, opt), "'foo: \"bar\"'\n")
      }
      test "contains single-quote" {
        expect_toBe(stringify("foo: 'bar'", null, opt), "\"foo: 'bar'\"\n")
      }
      test "numerical string" {
        expect_toBe(stringify("123", null, opt), "'123'\n")
      }
      test "upgrade from plain" {
        expect_toBe(stringify("foo #bar", null, opt), "'foo #bar'\n")
      }
      test "parsed node" {
        let doc = parseDocument("'foo'", null);
        expect_toBe(doc.toString(opt), "'foo'\n")
      }
    }

    testset "blockQuote: false" {
      test "doc-marker" {
        expect_toBe(stringify("---", null, Options { blockQuote: false }), "\"---\"\n")
      }
      test "map with value" {
        expect_toBe(stringify({ "foo": "bar\nfuzz\n" }, null, Options { blockQuote: false }), "foo: \"bar\\nfuzz\\n\"\n")
      }
      test "override parsed type" {
        let doc = parseDocument(">\n  foo\n", null);
        expect_toBe(doc.toString(Options { blockQuote: false }), "\"foo\\n\"\n")
      }
    }

    testset "blockQuote: true" {
      test "doc-marker" {
        expect_toBe(stringify("---", null, Options { blockQuote: true }), "|-\n  ---\n")
      }
      test "map with value" {
        expect_toBe(stringify({ "foo": "bar\nfuzz\n" }, null, Options { blockQuote: true }), "foo: |\n  bar\n  fuzz\n")
      }
      test "override parsed type" {
        let doc = parseDocument(">\n  foo\n", null);
        expect_toBe(doc.toString(Options { blockQuote: true }), ">\nfoo\n")
      }
    }

    testset "blockQuote: literal" {
      test "doc-marker" {
        expect_toBe(stringify("---", null, Options { blockQuote: "literal" }), "|-\n  ---\n")
      }
      test "map with value" {
        expect_toBe(stringify({ "foo": "bar\nfuzz\n" }, null, Options { blockQuote: "literal" }), "foo: |\n  bar\n  fuzz\n")
      }
      test "override parsed type" {
        let doc = parseDocument(">\n  foo\n", null);
        expect_toBe(doc.toString(Options { blockQuote: "literal" }), "|\nfoo\n")
      }
    }

    testset "blockQuote: folded" {
      test "doc-marker" {
        expect_toBe(stringify("---", null, Options { blockQuote: "folded" }), ">-\n  ---\n")
      }
      test "map with value" {
        expect_toBe(stringify({ "foo": "bar\nfuzz\n" }, null, Options { blockQuote: "folded" }), "foo: >\n  bar\n\n  fuzz\n")
      }
      test "override parsed type" {
        let doc = parseDocument(">\n  foo\n", null);
        expect_toBe(doc.toString(Options { blockQuote: "folded" }), ">\nfoo\n")
      }
    }
  }

  testset "toStringDefaults" {
    test "Set on Document creation" {
      let doc = Document.new({ "foo": null }, null, Options { toStringDefaults: Options { nullStr: "~" } });
      expect_toBe(doc.toString(null), "foo: ~\n")
    }

    test "Override in toString()" {
      let doc = Document.new({ "foo": null }, null, Options { toStringDefaults: Options { nullStr: "~" } });
      expect_toBe(doc.toString(Options { nullStr: "" }), "foo:\n")
    }
  }

  testset "Document markers in top-level scalars" {
    test "---" {
      let str = yaml_stringify("---");
      expect_toBe(str, "|-\n  ---\n");
      expect_toBe(yaml_parse(str), "---")
    }

    test "..." {
      let str = yaml_stringify("...");
      expect_toBe(str, "|-\n  ...\n");
      expect_toBe(yaml_parse(str), "...")
    }

    test "foo\\n...\\n" {
      let str = yaml_stringify("foo\n...\n");
      expect_toBe(str, "|\n  foo\n  ...\n");
      expect_toBe(yaml_parse(str), "foo\n...\n")
    }

    test "'foo\\n...'" {
      let doc = Document.new("foo\n...", null, null);
      tstr_scalar(doc.value).type = Scalar.QUOTE_SINGLE();
      let str = doc.toString(null);
      expect_toBe(str, "'foo\n\n  ...'\n");
      expect_toBe(yaml_parse(str), "foo\n...")
    }

    test "\"foo\\n...\"" {
      let doc = Document.new("foo\n...", null, null);
      tstr_scalar(doc.value).type = Scalar.QUOTE_DOUBLE();
      let str = doc.toString(Options { doubleQuotedMinMultiLineLength: 0 });
      expect_toBe(str, "\"foo\n\n  ...\"\n");
      expect_toBe(yaml_parse(str), "foo\n...")
    }

    test "foo\\n%bar\\n" {
      let str = yaml_stringify("foo\n%bar\n");
      expect_toBe(str, "|\n  foo\n  %bar\n");
      expect_toBe(yaml_parse(str), "foo\n%bar\n")
    }

    test "use marker line for block scalar header" {
      let doc = parseDocument("|\nfoo\n", null);
      expect_toBe(doc.toString(Options { directives: true }), "--- |\nfoo\n")
    }
  }

  testset "Document markers in top-level map keys (#431)" {
    test "---" {
      let str = yaml_stringify({ "--- x": 42 });
      expect_toBe(str, "\"--- x\": 42\n");
      expect_toEqual(yaml_parse(str), { "--- x": 42 })
    }

    test "..." {
      let str = yaml_stringify({ "... x": 42 });
      expect_toBe(str, "\"... x\": 42\n");
      expect_toEqual(yaml_parse(str), { "... x": 42 })
    }
  }

  // BAML has no `undefined`: it is ported as `null` throughout this block, so
  // tests whose expectations depend on undefined ≠ null fail (see notes).
  testset "undefined values" {
    test "undefined" {
      expect_toBeNull(stringify(js_undefined(), null, null))
    }

    test "[1, undefined, 2]" {
      let arr: unknown[] = [1, js_undefined(), 2];
      expect_toBe(yaml_stringify(arr), "- 1\n- null\n- 2\n")
    }

    test "{ a: 'A', b: undefined, c: 'C' }" {
      let obj: map<string, unknown> = { "a": "A", "b": js_undefined(), "c": "C" };
      expect_toBe(yaml_stringify(obj), "a: A\nc: C\n")
    }

    test "{ a: 'A', b: null, c: 'C' }" {
      let obj: map<string, unknown> = { "a": "A", "b": null, "c": "C" };
      expect_toBe(yaml_stringify(obj), "a: A\nb: null\nc: C\n")
    }

    test "{ a: 'A', b: Scalar(undefined), c: 'C' }" {
      let obj: map<string, unknown> = { "a": "A", "b": Scalar.new(null), "c": "C" };
      expect_toBe(yaml_stringify(obj), "a: A\nb: null\nc: C\n")
    }

    test "Map { 'a' => 'A', 'b' => undefined, 'c' => 'C' }" {
      let map = js_map();
      map.set("a", "A");
      map.set("b", js_undefined());
      map.set("c", "C");
      expect_toBe(yaml_stringify(map), "a: A\nc: C\n")
    }

    testset "keepUndefined: true" {
      test "undefined" {
        expect_toBe(stringify(js_undefined(), null, Options { keepUndefined: true }), "null\n")
      }

      test "{ a: 'A', b: undefined, c: 'C' }" {
        let obj: map<string, unknown> = { "a": "A", "b": js_undefined(), "c": "C" };
        expect_toBe(stringify(obj, null, Options { keepUndefined: true }), "a: A\nb: null\nc: C\n")
      }
    }
  }

  testset "replacer" {
    test "empty array" {
      let arr: unknown[] = [{ "a": 1, "b": 2 }, { "a": 4, "b": 5 }];
      let rep: unknown[] = [];
      expect_toBe(stringify(arr, rep, null), "- {}\n- {}\n")
    }

    test "Object, array of string" {
      let arr: unknown[] = [{ "a": 1, "b": 2 }, { "a": 4, "b": 5 }];
      let rep: unknown[] = ["a"];
      expect_toBe(stringify(arr, rep, null), "- a: 1\n- a: 4\n")
    }

    test "Map, array of string" {
      let map = js_map();
      map.set("a", 1);
      map.set("b", 2);
      map.set(3, 4);
      let rep: unknown[] = ["a", "3"];
      expect_toBe(stringify(map, rep, null), "a: 1\n")
    }

    test "Object, array of number" {
      // JS orders integer-like keys first: { a, b, 3, 5 } iterates 3, 5, a, b
      let obj: map<string, unknown> = { "3": 4, "5": 6, "a": 1, "b": 2 };
      let rep: unknown[] = [3, 5];
      expect_toBe(stringify(obj, rep, null), "\"3\": 4\n\"5\": 6\n")
    }

    test "Map, array of number" {
      let map = js_map();
      map.set("a", 1);
      map.set("3", 2);
      map.set(3, 4);
      let rep: unknown[] = [3];
      expect_toBe(stringify(map, rep, null), "\"3\": 2\n3: 4\n")
    }

    test "function as logger" {
      let spy = tstr_replacer_spy();
      // JS orders integer-like keys first
      let obj: map<string, unknown> = { "1": 1, "b": 2, "c": [4] };
      stringify(obj, (key: unknown, value: unknown, holder: unknown) -> unknown {
        spy.calls.record([key, value]);
        spy.instances.push(holder);
        value
      }, null);
      expect_toMatchObject(spy.calls.calls, [["", obj], ["1", 1], ["b", 2], ["c", [4]], ["0", 4]]);
      expect_toMatchObject(spy.instances, [{ "": obj }, obj, obj, obj, obj["c"]])
    }

    test "function as filter of Object entries" {
      let obj: map<string, unknown> = { "1": 1, "b": 2, "c": [4] };
      let fn = (_key: unknown, value: unknown, _holder: unknown) -> unknown {
        if (js_typeof(value) == "number") { js_undefined() } else { value }
      };
      expect_toBe(stringify(obj, fn, null), "c:\n  - null\n")
    }

    test "function as filter of Map entries" {
      let map = js_map();
      map.set(1, 1);
      map.set("b", 2);
      map.set("c", [4]);
      let fn = (_key: unknown, value: unknown, _holder: unknown) -> unknown {
        if (js_typeof(value) == "number") { js_undefined() } else { value }
      };
      expect_toBe(stringify(map, fn, null), "c:\n  - null\n")
    }

    test "function as transformer" {
      let obj: map<string, unknown> = { "a": 1, "b": 2, "c": [3, 4] };
      let fn = (_key: unknown, value: unknown, _holder: unknown) -> unknown {
        match (value) {
          let i: int => 2 * i,
          let f: float => 2.0 * f,
          _ => value,
        }
      };
      expect_toBe(stringify(obj, fn, null), "a: 2\nb: 4\nc:\n  - 6\n  - 8\n")
    }

    test "createNode, !!set" {
      let spy = tstr_replacer_spy();
      let doc = Document.new(null, null, Options { customTags: ["set"] });
      let two: unknown[] = [2];
      let set = js_set();
      set.add("a");
      set.add("b");
      set.add(1);
      set.add(two);
      doc.createNode(set, (key: unknown, value: unknown, holder: unknown) -> unknown {
        spy.calls.record([key, value]);
        spy.instances.push(holder);
        value
      }, null);
      expect_toMatchObject(spy.calls.calls, [["", set], ["a", "a"], ["b", "b"], [1, 1], [[2], [2]], ["0", 2]]);
      expect_toMatchObject(spy.instances, [{ "": set }, set, set, set, set, [2]])
    }

    test "createNode, !!omap" {
      let spy = tstr_replacer_spy();
      let doc = Document.new(null, null, Options { customTags: ["omap"] });
      let omap: unknown[] = [["a", 1], [1, "a"]];
      doc.createNode(omap, (key: unknown, value: unknown, holder: unknown) -> unknown {
        spy.calls.record([key, value]);
        spy.instances.push(holder);
        value
      }, Options { tag: "!!omap" });
      expect_toMatchObject(spy.calls.calls, [["", omap], ["0", omap[0]], ["1", omap[1]]]);
      expect_toMatchObject(spy.instances, [{ "": omap }, omap, omap])
    }
  }

  testset "YAML.stringify options as scalar" {
    test "number" {
      expect_toBe(stringify_indent({ "foo": "bar\nfuzz" }, null, 1), "foo: |-\n bar\n fuzz\n")
    }
    test "string" {
      expect_toBe(stringify_indent({ "foo": "bar\nfuzz" }, null, "123"), "foo: |-\n   bar\n   fuzz\n")
    }
  }

  testset "YAML.stringify on ast Document" {
    test "null document" {
      let doc = parseDocument("null", null);
      expect_toBe(yaml_stringify(doc), "null\n")
    }

    test "Document with comments" {
      let src_ = "a: 1\n\n# c\n";
      let doc = parseDocument(src_, null);
      expect_toBe(yaml_stringify(doc), src_)
    }
  }

  testset "flow collection padding" {
    let doc = tstr_flow_padding_doc();

    test "default" {
      expect_toBe(doc.toString(null), "[ 1, 2 ]\n")
    }
    // upstream has two tests named 'default'; BAML test names must be unique.
    test "default (flowCollectionPadding: false)" {
      expect_toBe(doc.toString(Options { flowCollectionPadding: false }), "[1, 2]\n")
    }
  }
}

/// `getDoc()` in `No extra whitespace for empty values`
function tstr_null_doc() -> Document {
  Document.new({ "a": null, "b": null }, null, null)
}

function tstr_flow_padding_doc() -> Document {
  let doc = Document.new(null, null, null);
  let seq = YAMLSeq.new(doc.schema, [Scalar.new(1), Scalar.new(2)]);
  seq.flow = true;
  doc.value = seq;
  doc
}
