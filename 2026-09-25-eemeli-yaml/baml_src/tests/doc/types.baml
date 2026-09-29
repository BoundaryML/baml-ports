// Port of tests/doc/types.ts

// ─── Helpers ────────────────────────────────────────────────────────────────

function ttyp_scalar(v: unknown) -> Scalar {
  match (v) {
    let s: Scalar => s,
    _ => fail("expected a Scalar, got " + t_show(v)),
  }
}

function ttyp_seq(v: unknown) -> YAMLSeq {
  match (v) {
    let s: YAMLSeq => s,
    _ => fail("expected a YAMLSeq, got " + t_show(v)),
  }
}

function ttyp_map(v: unknown) -> YAMLMap {
  match (v) {
    let m: YAMLMap => m,
    _ => fail("expected a YAMLMap, got " + t_show(v)),
  }
}

function ttyp_pair(v: unknown) -> Pair {
  match (v) {
    let p: Pair => p,
    _ => fail("expected a Pair, got " + t_show(v)),
  }
}

/// `node.constructor.name`
function ttyp_ctor_name(v: unknown) -> string {
  match (v) {
    let s: YAMLSeq => s._class,
    let s: Scalar => s._class,
    _ => t_class_name(v),
  }
}

/// `node.constructor.tagName`
function ttyp_ctor_tagName(v: unknown) -> string? {
  match (v) {
    let s: YAMLSeq => if (s._class == "YAMLOMap") { "tag:yaml.org,2002:omap" } else { YAMLSeq.tagName() },
    YAMLSet => YAMLSet.tagName(),
    YAMLMap => YAMLMap.tagName(),
    _ => null,
  }
}

/// `new Date(iso)` for a UTC timestamp
function ttyp_date(y: int, mo: int, d: int, h: int, mi: int, s: int, ms: int) -> JsDate {
  js_date(js_date_utc(y, mo - 1, d, h, mi, s, ms))
}

/// A JS `Map` built from `[key, value]` entries
function ttyp_jsmap(entries: unknown[][]) -> JsMap<unknown> {
  let m = js_map();
  for (let e in entries) {
    m.set(e[0], e[1]);
  }
  m
}

// A JS RegExp value (BAML has regexes, but no RegExp value with a
// `String(re) === "/src/flags"` representation).
class ttyp_RegExp {
  source: string
  flags: string
}

/// `Symbol.for(key)`: the global symbol registry is modelled by deriving the
/// symbol's identity (`_id`) deterministically from its key.
function ttyp_symbol_for(key: string) -> JsSymbol {
  JsSymbol { _id: ttyp_hash(key), description: key }
}

/// `Symbol.keyFor(sym)`
function ttyp_symbol_key_for(sym: JsSymbol) -> string? {
  if (sym._id == ttyp_hash(sym.description)) { sym.description } else { null }
}

function ttyp_hash(s: string) -> int {
  let h = 7;
  for (let c in s.to_code_points()) {
    h = (h * 31 + c) % 1000000000039;
  }
  0 - 1000 - h
}

// A null-prototype JS object (`Object.create(null)`). BAML maps have no
// prototype, so it is a wrapper class that `identify` can recognise.
class ttyp_NullObject {
  entries: map<string, unknown>
}

function ttyp_regexp_tag() -> Tag {
  Tag {
    _id: 91001,
    identify: (value: unknown) -> bool {
      match (value) {
        ttyp_RegExp => true,
        _ => false,
      }
    },
    tag: "!re",
    resolve: (str: string, onError: TagOnError, opts: Options) -> unknown {
      let m = re("^/([\\s\\S]+)/([gimuy]*)$").match_once(str);
      let g = m?.groups ?? [];
      ttyp_RegExp { source: g[1]?.text ?? "", flags: g[2]?.text ?? "" }
    },
    // Upstream has no `stringify` here: the default stringifier uses
    // `String(value)`, which for a RegExp is `/source/flags`. BAML class
    // instances have no toString(), so do the same explicitly.
    stringify: (item: Scalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string {
      let v = item.value;
      let str = match (v) {
        let r: ttyp_RegExp => "/" + r.source + "/" + r.flags,
        _ => js_string(v),
      };
      stringifyString(StringifyScalar { value: str, comment: item.comment, type: item.type }, ctx, onComment, onChompKeep)
    },
  }
}

function ttyp_shared_symbol_tag() -> Tag {
  Tag {
    _id: 91002,
    identify: (value: unknown) -> bool {
      match (value) {
        JsSymbol => true,
        _ => false,
      }
    },
    tag: "!symbol/shared",
    resolve: (str: string, onError: TagOnError, opts: Options) -> unknown { ttyp_symbol_for(str) },
    stringify: (item: Scalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string {
      let v = item.value;
      let key = match (v) {
        let s: JsSymbol => ttyp_symbol_key_for(s),
        _ => null,
      };
      if (key == null) {
        throw js_error("Only shared symbols are supported");
      }
      stringifyString(StringifyScalar { value: key ?? "" }, ctx, onComment, onChompKeep)
    },
  }
}

// `class YAMLNullObject extends YAMLMap` cannot be expressed (no
// inheritance): the tag creates a plain YAMLMap, whose toJS() is a plain
// (prototype-less in BAML anyway) map.
function ttyp_null_object_tag() -> Tag {
  Tag {
    _id: 91003,
    tag: "!nullobject",
    collection: "map",
    createNode: (nc: NodeCreator, value: unknown) -> Node {
      let entries = match (value) {
        let o: ttyp_NullObject => o.entries,
        _ => value,
      };
      let m = YAMLMap.create(nc, entries);
      m.tag = "!nullobject";
      m
    },
    identify: (value: unknown) -> bool {
      match (value) {
        ttyp_NullObject => true,
        _ => false,
      }
    },
    nodeClass: "YAMLMap",
  }
}

// ─── !!merge test bodies (describe.for) ─────────────────────────────────────

function ttyp_merge_opts(i: int) -> Options {
  match (i) {
    0 => Options { merge: true },
    1 => Options { merge: true, resolveKnownTags: false },
    2 => Options { schema: "yaml-1.1" },
    _ => Options { version: "1.1" },
  }
}

function ttyp_merge_alias(options: Options) -> null {
  let src_ = "- &a { a: A, b: B }\n- { <<: *a, b: X }\n";
  let doc = parseDocument(src_, options);
  expect_toMatchObject(doc.toJS(null), [
    { "a": "A", "b": "B" },
    { "a": "A", "b": "X" },
  ]);
  expect_toBe(doc.toString(null), src_)
}

function ttyp_merge_alias_sequence(options: Options) -> null {
  let src_ = "- &a { a: A, b: B, c: C }\n- &b { a: X }\n- { <<: [ *b, *a ], b: X }\n";
  let doc = parseDocument(src_, options);
  expect_toMatchObject(doc.toJS(null), [
    { "a": "A", "b": "B" },
    { "a": "X" },
    { "a": "X", "b": "X", "c": "C" },
  ]);
  expect_toBe(doc.toString(null), src_)
}

function ttyp_merge_explicit_creation(options: Options) -> null {
  let src_ = "- { a: A, b: B }\n- { b: X }\n";
  let doc = parseDocument(src_, options);
  let alias = doc.createAlias(ttyp_map(doc.get(0)), "a");
  ttyp_map(doc.get(1)).set(doc.createMergePair(alias, null), null);
  expect_toBe(doc.toString(null), "- &a { a: A, b: B }\n- { b: X, <<: *a }\n");
  expect_toMatchObject(doc.toJS(null), [
    { "a": "A", "b": "B" },
    { "a": "A", "b": "X" },
  ])
}

function ttyp_merge_duck_typing(options: Options) -> null {
  let src_ = "- { a: A, b: B }\n- { b: X }\n";
  let doc = parseDocument(src_, options);
  let alias = doc.createAlias(ttyp_map(doc.get(0)), "a");
  ttyp_map(doc.get(1)).set(doc.createPair("<<", alias, null), null);
  expect_toBe(doc.toString(null), "- &a { a: A, b: B }\n- { b: X, \"<<\": *a }\n");
  expect_toMatchObject(doc.toJS(null), [
    { "a": "A", "b": "B" },
    { "b": "X", "<<": { "a": "A" } },
  ])
}

function ttyp_merge_str_tag(options: Options) -> null {
  let src_ = "!!str <<: { x: 1 }";
  let doc = parseDocument(src_, options);
  expect_toMatchObject(doc.toJS(null), { "<<": { "x": 1 } });
  expect_toBe(doc.toString(null), "!!str \"<<\": { x: 1 }\n")
}

function ttyp_merge_merge_tag(options: Options) -> null {
  let src_ = "!!merge <<: { x: 1 }";
  let doc = parseDocument(src_, options);
  expect_toMatchObject(doc.toJS(null), { "x": 1 });
  expect_toBe(doc.toString(null), "!!merge <<: { x: 1 }\n")
}

// ─── Other shared test bodies ───────────────────────────────────────────────

function ttyp_invalid_tag(tag: string) -> null {
  let doc = parseDocument(tag, null);
  expect_true(doc.errors.length() != 0, "expected errors not to have length 0");
  expect_toBe(doc.errors[0].code, "MISSING_CHAR")
}

function ttyp_pairs_parse(src_: string) -> null {
  let doc = parseDocument(src_, Options { version: "1.1" });
  expect_toBeInstanceOf(doc.value, "YAMLSeq");
  expect_toMatchObject(doc.value, [
    { "key": { "value": "a" }, "value": { "value": 1 } },
    { "key": { "value": "b" }, "value": { "value": 2 } },
    { "key": { "value": "a" }, "value": { "value": 3 } },
  ]);
  expect_toBeInstanceOf(doc.toJS(null), "Array");
  expect_toMatchObject(doc.toJS(null), [{ "a": 1 }, { "b": 2 }, { "a": 3 }]);
  expect_toBe(doc.toString(null), src_)
}

function ttyp_omap_parse(src_: string) -> null {
  let doc = parseDocument(src_, Options { version: "1.1" });
  expect_toBe(ttyp_ctor_name(doc.value), "YAMLOMap");
  expect_toBeInstanceOf(doc.toJS(null), "Map");
  expect_toMatchObject(doc.toJS(null), ttyp_jsmap([["a", 1], ["b", 2], ["c", 3]]));
  expect_toBe(doc.toString(null), src_)
}

function ttyp_set_parse(src_: string) -> null {
  let doc = parseDocument(src_, Options { version: "1.1" });
  expect_toBe(ttyp_ctor_tagName(doc.value), "tag:yaml.org,2002:set");
  expect_toBeInstanceOf(doc.toJS(null), "Set");
  let s = js_set();
  s.add("a");
  s.add("b");
  s.add("c");
  expect_toMatchObject(doc.toJS(null), s);
  expect_toBe(doc.toString(null), src_)
}

function ttyp_binary_src() -> string {
  "!!binary |\n      R0lGODlhDAAMAIQAAP//9/X17unp5WZmZgAAAOfn515eXvPz7Y6OjuDg4J+fn5\n      OTk6enp56enmlpaWNjY6Ojo4SEhP/++f/++f/++f/++f/++f/++f/++f/++f/+\n      +f/++f/++f/++f/++f/++SH+Dk1hZGUgd2l0aCBHSU1QACwAAAAADAAMAAAFLC\n      AgjoEwnuNAFOhpEMTRiggcz4BNJHrv/zCFcLiwMWYNG84BwwEeECcgggoBADs="
}

function ttyp_local_src() -> string {
  "%TAG !e! tag:example.com,2000:test/\n---\n!e!x\n- !y 2\n- !e!z 3\n- !<tag:example.com,2000:other/w> 4\n- '5'\n"
}

// ─── Tests ──────────────────────────────────────────────────────────────────

testset "doc/types" {
  testset "tags" {
    testset "implicit tags" {
      test "plain string" {
        let doc = parseDocument("foo", null);
        expect_toBeNull(t_prop(doc.value, "tag"));
        expect_toBe(t_prop(doc.value, "value"), "foo")
      }
      test "quoted string" {
        let doc = parseDocument("\"foo\"", null);
        expect_toBeNull(t_prop(doc.value, "tag"));
        expect_toBe(t_prop(doc.value, "value"), "foo")
      }
      test "flow map" {
        let doc = parseDocument("{ foo }", null);
        expect_toBeNull(t_prop(doc.value, "tag"));
        expect_toMatchObject(doc.toJS(null), { "foo": null });
        expect_toMatchObject(doc.toJSON(), { "foo": null })
      }
      test "flow seq" {
        let doc = parseDocument("[ foo ]", null);
        expect_toBeNull(t_prop(doc.value, "tag"));
        expect_toMatchObject(doc.toJS(null), ["foo"]);
        expect_toMatchObject(doc.toJSON(), ["foo"])
      }
      test "block map" {
        let doc = parseDocument("foo:\n", null);
        expect_toBeNull(t_prop(doc.value, "tag"));
        expect_toMatchObject(doc.toJS(null), { "foo": null });
        expect_toMatchObject(doc.toJSON(), { "foo": null })
      }
      test "block seq" {
        let doc = parseDocument("- foo", null);
        expect_toBeNull(t_prop(doc.value, "tag"));
        expect_toMatchObject(doc.toJS(null), ["foo"]);
        expect_toMatchObject(doc.toJSON(), ["foo"])
      }
    }

    testset "explicit tags" {
      test "plain string" {
        let doc = parseDocument("!!str foo", null);
        expect_toBe(t_prop(doc.value, "tag"), "tag:yaml.org,2002:str");
        expect_toBe(t_prop(doc.value, "value"), "foo")
      }
      test "quoted string" {
        let doc = parseDocument("!!str \"foo\"", null);
        expect_toBe(t_prop(doc.value, "tag"), "tag:yaml.org,2002:str");
        expect_toBe(t_prop(doc.value, "value"), "foo")
      }
      test "flow map" {
        let doc = parseDocument("!!map { foo }", null);
        expect_toBe(t_prop(doc.value, "tag"), "tag:yaml.org,2002:map");
        expect_toMatchObject(doc.toJS(null), { "foo": null })
      }
      test "flow seq" {
        let doc = parseDocument("!!seq [ foo ]", null);
        expect_toBe(t_prop(doc.value, "tag"), "tag:yaml.org,2002:seq");
        expect_toMatchObject(doc.toJS(null), ["foo"])
      }
      test "block map" {
        let doc = parseDocument("!!map\nfoo:\n", null);
        expect_toBe(t_prop(doc.value, "tag"), "tag:yaml.org,2002:map");
        expect_toMatchObject(doc.toJS(null), { "foo": null })
      }
      test "block seq" {
        let doc = parseDocument("!!seq\n- foo", null);
        expect_toBe(t_prop(doc.value, "tag"), "tag:yaml.org,2002:seq");
        expect_toMatchObject(doc.toJS(null), ["foo"])
      }
    }

    testset "invalid tags" {
      // upstream generates these with a `for` loop over the tags
      test "invalid tag: !t`ag x" {
        ttyp_invalid_tag("!t`ag x")
      }
      test "invalid tag: !t^ag x" {
        ttyp_invalid_tag("!t^ag x")
      }
      test "invalid tag: !t\\ag x" {
        ttyp_invalid_tag("!t\\ag x")
      }
      test "invalid tag: !t<ag x" {
        ttyp_invalid_tag("!t<ag x")
      }
      test "invalid tag: !t>ag x" {
        ttyp_invalid_tag("!t>ag x")
      }
      test "invalid tag: !t,ag x" {
        ttyp_invalid_tag("!t,ag x")
      }
      test "invalid tag: !t\"ag x" {
        ttyp_invalid_tag("!t\"ag x")
      }

      test "malformed URI (#498)" {
        let doc = parseDocument("!!%ee 0", null);
        expect_toHaveLength(doc.errors, 1);
        expect_toMatch(doc.errors[0].message, "URIError")
      }

      test "CR in tag shorthand (#501)" {
        let doc = parseDocument(": | !\r!", null);
        let err = doc.errors.find((e: YAMLError) -> bool { e.code == "TAG_RESOLVE_FAILED" });
        expect_not_toBeNull(err)
      }
    }

    test "float with fraction digits (#97)" {
      let doc = parseDocument("foo: !!float 3.0", null);
      expect_toBe(doc.toString(null), "foo: !!float 3.0\n")
    }
  }

  testset "number types" {
    testset "intAsBigInt: false" {
      test "Version 1.1" {
        let src_ = "\n- 0b10_10\n- 0123\n- -00\n- 123_456\n- 3.1e+2\n- 5.1_2_3E-1\n- 4.02\n- 4.20\n- .42\n- 00.4";
        let doc = parseDocument(src_, Options { intAsBigInt: false, version: "1.1" });
        expect_toMatchObject(doc.value, [
          { "value": 10, "format": "BIN" },
          { "value": 83, "format": "OCT" },
          { "value": -0.0, "format": "OCT" },
          { "value": 123456 },
          { "value": 310, "format": "EXP" },
          { "value": 0.5123, "format": "EXP" },
          { "value": 4.02 },
          { "value": 4.2, "minFractionDigits": 2 },
          { "value": 0.42 },
          { "value": 0.4 },
        ]);
        expect_not_toHaveProperty(t_prop(doc.value, "3"), "format");
        expect_not_toHaveProperty(t_prop(doc.value, "6"), "format");
        expect_not_toHaveProperty(t_prop(doc.value, "6"), "minFractionDigits");
        expect_not_toHaveProperty(t_prop(doc.value, "7"), "format")
      }

      test "Version 1.2" {
        let src_ = "\n- 0o123\n- 0o0\n- 123456\n- 3.1e+2\n- 5.123E-1\n- 4.02\n- 4.20\n- .42\n- 00.4";
        let doc = parseDocument(src_, Options { intAsBigInt: false, version: "1.2" });
        expect_toMatchObject(doc.value, [
          { "value": 83, "format": "OCT" },
          { "value": 0, "format": "OCT" },
          { "value": 123456 },
          { "value": 310, "format": "EXP" },
          { "value": 0.5123, "format": "EXP" },
          { "value": 4.02 },
          { "value": 4.2, "minFractionDigits": 2 },
          { "value": 0.42 },
          { "value": 0.4 },
        ]);
        expect_not_toHaveProperty(t_prop(doc.value, "2"), "format");
        expect_not_toHaveProperty(t_prop(doc.value, "5"), "format");
        expect_not_toHaveProperty(t_prop(doc.value, "5"), "minFractionDigits");
        expect_not_toHaveProperty(t_prop(doc.value, "6"), "format")
      }
    }

    testset "intAsBigInt: true" {
      test "Version 1.1" {
        let src_ = "\n- 0b10_10\n- 0123\n- -00\n- 123_456\n- 3.1e+2\n- 5.1_2_3E-1\n- 4.02";
        let doc = parseDocument(src_, Options { intAsBigInt: true, version: "1.1" });
        expect_toMatchObject(doc.value, [
          { "value": 10n, "format": "BIN" },
          { "value": 83n, "format": "OCT" },
          { "value": 0n, "format": "OCT" },
          { "value": 123456n },
          { "value": 310, "format": "EXP" },
          { "value": 0.5123, "format": "EXP" },
          { "value": 4.02 },
        ]);
        expect_not_toHaveProperty(t_prop(doc.value, "3"), "format");
        expect_not_toHaveProperty(t_prop(doc.value, "6"), "format");
        expect_not_toHaveProperty(t_prop(doc.value, "6"), "minFractionDigits");
        expect_toEqual(doc.toJS(null), [10n, 83n, 0n, 123456n, 310, 0.5123, 4.02]);
        expect_toEqual(doc.value.toJS(doc, null), [10n, 83n, 0n, 123456n, 310, 0.5123, 4.02]);
        let first = ttyp_scalar(doc.get(0));
        expect_toBe(first.toJS(null, null), 10n)
      }

      test "Version 1.2" {
        let src_ = "\n- 0o123\n- 0o0\n- 123456\n- 3.1e+2\n- 5.123E-1\n- 4.02";
        let doc = parseDocument(src_, Options { intAsBigInt: true, version: "1.2" });
        expect_toMatchObject(doc.value, [
          { "value": 83n, "format": "OCT" },
          { "value": 0n, "format": "OCT" },
          { "value": 123456n },
          { "value": 310, "format": "EXP" },
          { "value": 0.5123, "format": "EXP" },
          { "value": 4.02 },
        ]);
        expect_not_toHaveProperty(t_prop(doc.value, "2"), "format");
        expect_not_toHaveProperty(t_prop(doc.value, "5"), "format");
        expect_not_toHaveProperty(t_prop(doc.value, "5"), "minFractionDigits")
      }
    }

    testset "overflowing values keep their source (#660)" {
      test "float overflowing to Infinity round-trips via its source" {
        expect_toBe(parseDocument("gitsha: 61e9540", null).toString(null), "gitsha: 61e9540\n")
      }

      test "negative overflow keeps its source" {
        expect_toBe(parseDocument("n: -61e9540", null).toString(null), "n: -61e9540\n")
      }

      test "literal .inf / .nan are still emitted as such" {
        expect_toBe(parseDocument("n: .inf", null).toString(null), "n: .inf\n");
        expect_toBe(parseDocument("n: -.inf", null).toString(null), "n: -.inf\n");
        expect_toBe(parseDocument("n: .nan", null).toString(null), "n: .nan\n")
      }

      test "a programmatic Infinity with finite source is emitted as .inf" {
        let doc = parseDocument("n: 1", null);
        doc.set("n", baml.Float.inf());
        expect_toBe(doc.toString(null), "n: .inf\n")
      }

      test "editing the value of a node parsed from a non-finite source is reflected" {
        let doc = parseDocument("n: 61e9540", null);
        let node = ttyp_scalar(doc.get("n"));
        node.value = 0.0 - baml.Float.inf();
        expect_toBe(doc.toString(null), "n: -.inf\n")
      }

      test "the source is used only while it still resolves to the value" {
        let node = Scalar.new(baml.Float.inf());
        node.source = "61e9540";
        expect_toBe(stringifyNumber(node, "1.2"), "61e9540");
        node.source = "5";
        expect_toBe(stringifyNumber(node, "1.2"), ".inf")
      }

      test "a YAML 1.1 float with underscores that overflows keeps its source" {
        let doc = parseDocument("n: 6_1e9540", Options { version: "1.1" });
        expect_toBe(doc.toString(null), "n: 6_1e9540\n")
      }
    }
  }

  test "Indented sequence with sequence values (#2)" {
    let src_ = "\naliases:\n  - docker:\n      - image: circleci/node:8.11.2\n  - key: repository-{{ .Revision }}\n";
    expect_toMatchObject(yaml_parse(src_), {
      "aliases": [
        { "docker": [{ "image": "circleci/node:8.11.2" }] },
        { "key": "repository-{{ .Revision }}" },
      ],
    })
  }

  testset "failsafe schema" {
    test "empty scalars (#616)" {
      let doc = parseDocument("empty:\n", Options { schema: "failsafe" });
      expect_toMatchObject(doc.errors, []);
      expect_toMatchObject(doc.get("empty"), { "value": "" });
      expect_toMatchObject(doc.toJS(null), { "empty": "" });
      expect_toEqual(doc.toString(null), "empty:\n")
    }
  }

  testset "json schema" {
    test "!!bool" {
      let src_ = "\"canonical\": true\n\"answer\": false\n\"logical\": True\n\"option\": TruE";
      let doc = parseDocument(src_, Options { schema: "json" });
      expect_toMatchObject(doc.toJS(null), {
        "canonical": true,
        "answer": false,
        "logical": "True",
        "option": "TruE",
      });
      expect_toHaveLength(doc.errors, 2);
      doc.errors = [];
      expect_toBe(doc.toString(null), "\"canonical\": true\n\"answer\": false\n\"logical\": \"True\"\n\"option\": \"TruE\"\n")
    }

    test "!!bool: js-regex-missing-regexp-anchor" {
      let src_ = "\"canonical\": truea\n\"answer\": ffalse\n\"logical\": Truea\n\"option\": TruEp";
      let doc = parseDocument(src_, Options { schema: "json" });
      expect_toMatchObject(doc.toJS(null), {
        "canonical": "truea",
        "answer": "ffalse",
        "logical": "Truea",
        "option": "TruEp",
      });
      expect_toHaveLength(doc.errors, 4);
      doc.errors = [];
      expect_toBe(doc.toString(null), "\"canonical\": \"truea\"\n\"answer\": \"ffalse\"\n\"logical\": \"Truea\"\n\"option\": \"TruEp\"\n")
    }

    test "!!float" {
      let src_ = "\"canonical\": 6.8523015e+5\n\"fixed\": 685230.15\n\"negative infinity\": -.inf\n\"not a number\": .NaN";
      let doc = parseDocument(src_, Options { schema: "json" });
      expect_toMatchObject(doc.toJS(null), {
        "canonical": 685230.15,
        "fixed": 685230.15,
        "negative infinity": "-.inf",
        "not a number": ".NaN",
      });
      expect_toHaveLength(doc.errors, 2);
      doc.errors = [];
      ttyp_scalar(doc.get("fixed")).tag = "tag:yaml.org,2002:float";
      expect_toBe(doc.toString(null), "\"canonical\": 685230.15\n\"fixed\": !!float 685230.15\n\"negative infinity\": \"-.inf\"\n\"not a number\": \".NaN\"\n")
    }

    test "!!int" {
      let src_ = "\"canonical\": 685230\n\"decimal\": -685230\n\"octal\": 0o2472256\n\"hexadecimal\": 0x0A74AE";
      let doc = parseDocument(src_, Options { schema: "json" });
      expect_toMatchObject(doc.toJS(null), {
        "canonical": 685230,
        "decimal": -685230,
        "octal": "0o2472256",
        "hexadecimal": "0x0A74AE",
      });
      expect_toHaveLength(doc.errors, 2);
      doc.errors = [];
      doc.set("bigint", 42n);
      expect_toBe(doc.toString(null), "\"canonical\": 685230\n\"decimal\": -685230\n\"octal\": \"0o2472256\"\n\"hexadecimal\": \"0x0A74AE\"\n\"bigint\": 42\n")
    }

    test "!!null" {
      let src_ = "\"empty\":\n\"canonical\": ~\n\"english\": null\n~: 'null key'";
      let doc = parseDocument(src_, Options { schema: "json" });
      expect_toMatchObject(doc.toJS(null), {
        "empty": "",
        "canonical": "~",
        "english": null,
        "~": "null key",
      });
      expect_toHaveLength(doc.errors, 3);
      doc.errors = [];
      expect_toBe(doc.toString(null), "\"empty\": \"\"\n\"canonical\": \"~\"\n\"english\": null\n\"~\": \"null key\"\n")
    }
  }

  testset "core schema" {
    test "!!bool" {
      let src_ = "canonical: true\nanswer: FALSE\nlogical: True\noption: TruE\n";
      let doc = parseDocument(src_, null);
      expect_toMatchObject(doc.toJS(null), {
        "canonical": true,
        "answer": false,
        "logical": true,
        "option": "TruE",
      });
      expect_toBe(doc.toString(null), "canonical: true\nanswer: FALSE\nlogical: True\noption: TruE\n")
    }

    test "!!float" {
      let src_ = "canonical: 6.8523015e+5\nfixed: 685230.15\nnegative infinity: -.inf\nnot a number: .NaN\nnot a NaN: -.NaN";
      let doc = parseDocument(src_, null);
      expect_toMatchObject(doc.toJS(null), {
        "canonical": 685230.15,
        "fixed": 685230.15,
        "negative infinity": 0.0 - baml.Float.inf(),
        "not a number": baml.Float.nan(),
        "not a NaN": "-.NaN",
      });
      expect_toBe(doc.toString(null), "canonical: 6.8523015e+5\nfixed: 685230.15\nnegative infinity: -.inf\nnot a number: .nan\nnot a NaN: -.NaN\n")
    }

    test "!!int" {
      let src_ = "canonical: 685230\ndecimal: +685230\noctal: 0o2472256\nhexadecimal: 0x0A74AE";
      let doc = parseDocument(src_, null);
      expect_toMatchObject(doc.toJS(null), {
        "canonical": 685230,
        "decimal": 685230,
        "octal": 685230,
        "hexadecimal": 685230,
      });
      expect_toBe(doc.toString(null), "canonical: 685230\ndecimal: 685230\noctal: 0o2472256\nhexadecimal: 0xa74ae\n")
    }

    test "!!null" {
      let src_ = "empty:\ncanonical: ~\nenglish: null\n~: null key";
      let doc = parseDocument(src_, null);
      expect_toMatchObject(doc.toJS(null), {
        "empty": null,
        "canonical": null,
        "english": null,
        "": "null key",
      });
      expect_toBe(doc.toString(null), "empty:\ncanonical: ~\nenglish: null\n~: null key\n")
    }

    testset "!!map" {
      test "mapAsMap: false" {
        let src_ = "\none: 1\n2: two\n{ 3: 4 }: many\n";
        let doc = parseDocument(src_, Options { logLevel: "error" });
        expect_toMatchObject(doc.toJS(null), {
          "one": 1,
          "2": "two",
          "{ 3: 4 }": "many",
        });
        expect_toHaveLength(doc.errors, 0);
        let pairs = ttyp_map(doc.value).values.values();
        let last = pairs[pairs.length() - 1];
        last.key = doc.createNode({ "3": 4 }, null, null);
        expect_toMatchObject(doc.toJS(null), {
          "one": 1,
          "2": "two",
          "{ \"3\": 4 }": "many",
        })
      }

      test "mapAsMap: true" {
        let src_ = "\none: 1\n2: two\n{ 3: 4 }: many\n";
        let doc = parseDocument(src_, null);
        expect_toMatchObject(doc.toJS(Options { mapAsMap: true }), ttyp_jsmap([
          ["one", 1],
          [2, "two"],
          [ttyp_jsmap([[3, 4]]), "many"],
        ]));
        expect_toHaveLength(doc.errors, 0);
        let pairs = ttyp_map(doc.value).values.values();
        let last = pairs[pairs.length() - 1];
        last.key = doc.createNode({ "5": 6 }, null, null);
        expect_toMatchObject(doc.toJS(Options { mapAsMap: true }), ttyp_jsmap([
          ["one", 1],
          [2, "two"],
          [ttyp_jsmap([["5", 6]]), "many"],
        ]))
      }
    }
  }

  testset "YAML 1.1 schema" {
    test "!!binary" {
      let src_ = "canonical: !!binary \"\\\n R0lGODlhDAAMAIQAAP//9/X17unp5WZmZgAAAOfn515eXvPz7Y6OjuDg4J+fn5\\\n OTk6enp56enmlpaWNjY6Ojo4SEhP/++f/++f/++f/++f/++f/++f/++f/++f/+\\\n +f/++f/++f/++f/++f/++SH+Dk1hZGUgd2l0aCBHSU1QACwAAAAADAAMAAAFLC\\\n AgjoEwnuNAFOhpEMTRiggcz4BNJHrv/zCFcLiwMWYNG84BwwEeECcgggoBADs=\"\ngeneric: !!binary |\n R0lGODlhDAAMAIQAAP//9/X17unp5WZmZgAAAOfn515eXvPz7Y6OjuDg4J+fn5\n OTk6enp56enmlpaWNjY6Ojo4SEhP/++f/++f/++f/++f/++f/++f/++f/++f/+\n +f/++f/++f/++f/++f/++SH+Dk1hZGUgd2l0aCBHSU1QACwAAAAADAAMAAAFLC\n AgjoEwnuNAFOhpEMTRiggcz4BNJHrv/zCFcLiwMWYNG84BwwEeECcgggoBADs=\ndescription:\n The binary value above is a tiny arrow encoded as a gif image.";
      let doc = parseDocument(src_, Options { schema: "yaml-1.1" });
      let m = ttyp_map(doc.value);
      let canonical = ttyp_scalar(m.get("canonical")).value;
      let generic = ttyp_scalar(m.get("generic")).value;
      expect_toBeInstanceOf(canonical, "Uint8Array");
      expect_toBeInstanceOf(generic, "Uint8Array");
      let cb: int[] = match (canonical) {
        let u: uint8array => u.to_array(),
        _ => [],
      };
      let gb: int[] = match (generic) {
        let u: uint8array => u.to_array(),
        _ => [],
      };
      expect_toHaveLength(cb, 185);
      expect_toHaveLength(gb, 185);
      // `String.fromCharCode(...)` over the bytes: compare the byte arrays
      expect_toEqual(cb, gb);
      expect_toEqual(cb.slice(0, 5), [71, 73, 70, 56, 57]); // 'GIF89'
      expect_toBe(doc.toString(null), "canonical: !!binary \"R0lGODlhDAAMAIQAAP//9/X17unp5WZmZgAAAOfn515eXvPz7Y6OjuDg4J\\\n  +fn5OTk6enp56enmlpaWNjY6Ojo4SEhP/++f/++f/++f/++f/++f/++f/++f/++f/++f/++f/++f/\\\n  ++f/++f/++SH+Dk1hZGUgd2l0aCBHSU1QACwAAAAADAAMAAAFLCAgjoEwnuNAFOhpEMTRiggcz4BN\\\n  JHrv/zCFcLiwMWYNG84BwwEeECcgggoBADs=\"\ngeneric: !!binary |-\n  R0lGODlhDAAMAIQAAP//9/X17unp5WZmZgAAAOfn515eXvPz7Y6OjuDg4J+fn5OTk6enp56enmlpaW\n  NjY6Ojo4SEhP/++f/++f/++f/++f/++f/++f/++f/++f/++f/++f/++f/++f/++f/++SH+Dk1hZGUg\n  d2l0aCBHSU1QACwAAAAADAAMAAAFLCAgjoEwnuNAFOhpEMTRiggcz4BNJHrv/zCFcLiwMWYNG84Bww\n  EeECcgggoBADs=\ndescription: The binary value above is a tiny arrow encoded as a gif image.\n")
    }

    test "!!bool" {
      let src_ = "\ncanonical: y\nanswer: NO\nlogical: True\noption: on";
      let doc = parseDocument(src_, Options { version: "1.1" });
      expect_toMatchObject(doc.toJS(null), {
        "canonical": true,
        "answer": false,
        "logical": true,
        "option": true,
      });
      expect_toBe(doc.toString(null), "canonical: y\nanswer: NO\nlogical: True\noption: on\n")
    }

    test "!!float" {
      let src_ = "%YAML 1.1\n---\ncanonical: 6.8523015e+5\nexponential: 685.230_15e+03\nfixed: 685_230.15\nsexagesimal: 190:20:30.15\nnegative infinity: -.inf\nnot a number: .NaN\nnot a NaN: -.NaN";
      let doc = parseDocument(src_, null);
      expect_toMatchObject(doc.toJS(null), {
        "canonical": 685230.15,
        "exponential": 685230.15,
        "fixed": 685230.15,
        "sexagesimal": 685230.15,
        "negative infinity": 0.0 - baml.Float.inf(),
        "not a number": baml.Float.nan(),
        "not a NaN": "-.NaN",
      });
      expect_toBe(doc.toString(null), "%YAML 1.1\n---\ncanonical: 6.8523015e+5\nexponential: 6.8523015e+5\nfixed: 685230.15\nsexagesimal: 190:20:30.15\nnegative infinity: -.inf\nnot a number: .nan\nnot a NaN: -.NaN\n")
    }

    test "!!int" {
      let src_ = "%YAML 1.1\n---\ncanonical: 685230\ndecimal: +685_230\noctal: 02472256\nhexadecimal: 0x_0A_74_AE\nbinary: 0b1010_0111_0100_1010_1110\nsexagesimal: 190:20:30";
      let doc = parseDocument(src_, null);
      expect_toMatchObject(doc.toJS(null), {
        "canonical": 685230,
        "decimal": 685230,
        "octal": 685230,
        "hexadecimal": 685230,
        "binary": 685230,
        "sexagesimal": 685230,
      });
      expect_toBe(doc.toString(null), "%YAML 1.1\n---\ncanonical: 685230\ndecimal: 685230\noctal: 02472256\nhexadecimal: 0xa74ae\nbinary: 0b10100111010010101110\nsexagesimal: 190:20:30\n")
    }

    test "!!int, asBigInt" {
      let src_ = "%YAML 1.1\n---\ncanonical: 685230\ndecimal: +685_230\noctal: 02472256\nhexadecimal: 0x_0A_74_AE\nbinary: 0b1010_0111_0100_1010_1110\nsexagesimal: 190:20:30";
      let doc = parseDocument(src_, Options { intAsBigInt: true });
      expect_toMatchObject(doc.toJS(null), {
        "canonical": 685230n,
        "decimal": 685230n,
        "octal": 685230n,
        "hexadecimal": 685230n,
        "binary": 685230n,
        "sexagesimal": 685230n,
      });
      expect_toBe(doc.toString(null), "%YAML 1.1\n---\ncanonical: 685230\ndecimal: 685230\noctal: 02472256\nhexadecimal: 0xa74ae\nbinary: 0b10100111010010101110\nsexagesimal: 190:20:30\n")
    }

    test "!!null" {
      let src_ = "%YAML 1.1\n---\nempty:\ncanonical: ~\nenglish: null\n~: null key";
      let doc = parseDocument(src_, null);
      expect_toMatchObject(doc.toJS(null), {
        "empty": null,
        "canonical": null,
        "english": null,
        "": "null key",
      });
      expect_toBe(doc.toString(null), "%YAML 1.1\n---\nempty:\ncanonical: ~\nenglish: null\n~: null key\n")
    }

    testset "!!timestamp" {
      test "parse & document" {
        let src_ = "%YAML 1.1\n---\ncanonical:        2001-12-15T02:59:43.1Z\nvalid iso8601:    2001-12-14t21:59:43.10-05:00\nno secs:          2001-12-15T02:59:00\nspace separated:  2001-12-14 21:59:43.10 -5\nno time zone (Z): 2001-12-15 2:59:43.10\ndate (00:00:00Z): 2002-12-14";
        let doc = parseDocument(src_, null);
        for (let pair in ttyp_map(doc.value).values.values()) {
          expect_toBeInstanceOf(t_prop(pair.value, "value"), "Date");
        }
        expect_toMatchObject(doc.toJS(null), {
          "canonical": ttyp_date(2001, 12, 15, 2, 59, 43, 100),
          "valid iso8601": ttyp_date(2001, 12, 15, 2, 59, 43, 100),
          "no secs": ttyp_date(2001, 12, 15, 2, 59, 0, 0),
          "space separated": ttyp_date(2001, 12, 15, 2, 59, 43, 100),
          "no time zone (Z)": ttyp_date(2001, 12, 15, 2, 59, 43, 100),
          "date (00:00:00Z)": ttyp_date(2002, 12, 14, 0, 0, 0, 0),
        });
        expect_toBe(doc.toString(null), "%YAML 1.1\n---\ncanonical: 2001-12-15T02:59:43.100Z\nvalid iso8601: 2001-12-15T02:59:43.100Z\nno secs: 2001-12-15T02:59:00\nspace separated: 2001-12-15T02:59:43.100Z\nno time zone (Z): 2001-12-15T02:59:43.100Z\ndate (00:00:00Z): 2002-12-14\n")
      }

      test "stringify" {
        let date = ttyp_date(2018, 12, 22, 8, 2, 52, 0);
        let str = yaml_stringify(date); // stringified as !!str
        expect_toBe(str, "2018-12-22T08:02:52.000Z\n");
        let str2 = stringify(date, null, Options { version: "1.1" });
        expect_toBe(str2, "2018-12-22T08:02:52\n")
      }
    }

    testset "!!pairs" {
      // upstream generates these two with a `for` loop
      test "parse block seq" {
        ttyp_pairs_parse("!!pairs\n- a: 1\n- b: 2\n- a: 3\n")
      }
      test "parse flow seq" {
        ttyp_pairs_parse("!!pairs [ a: 1, b: 2, a: 3 ]\n")
      }

      test "stringify" {
        let doc = Document.new(null, null, Options { version: "1.1" });
        doc.value = doc.createNode([["a", 1], ["b", 2], ["a", 3]], null, Options { tag: "!!pairs" });
        expect_toBe(t_prop(doc.value, "tag"), "tag:yaml.org,2002:pairs");
        expect_toBe(doc.toString(null), "!!pairs\n- a: 1\n- b: 2\n- a: 3\n")
      }
    }

    testset "!!omap" {
      test "parse block seq" {
        ttyp_omap_parse("!!omap\n- a: 1\n- b: 2\n- c: 3\n")
      }
      test "parse flow seq" {
        ttyp_omap_parse("!!omap [ a: 1, b: 2, c: 3 ]\n")
      }

      test "require unique keys" {
        let src_ = "!!omap\n- a: 1\n- b: 2\n- b: 9\n";
        let doc = parseDocument(src_, Options { prettyErrors: false, version: "1.1" });
        expect_toMatchObject(doc.errors, [
          {
            "name": "YAMLParseError",
            "message": "Ordered maps must not include duplicate keys: b",
          },
        ])
      }

      test "stringify Map" {
        let m = ttyp_jsmap([["a", 1], ["b", 2], ["c", 3]]);
        let str = stringify(m, null, Options { version: "1.1" });
        expect_toBe(str, "!!omap\n- a: 1\n- b: 2\n- c: 3\n");
        let str2 = yaml_stringify(m);
        expect_toBe(str2, "a: 1\nb: 2\nc: 3\n")
      }

      test "stringify Array" {
        let doc = Document.new(null, null, Options { version: "1.1" });
        doc.value = doc.createNode([["a", 1], ["b", 2], ["a", 3]], null, Options { tag: "!!omap" });
        expect_toBe(ttyp_ctor_name(doc.value), "YAMLOMap");
        expect_toThrow(() -> unknown { doc.toString(null) }, null);
        let p = ttyp_pair(ttyp_seq(doc.value).items[2]);
        ttyp_scalar(p.key).value = "c";
        expect_toBe(doc.toString(null), "!!omap\n- a: 1\n- b: 2\n- c: 3\n")
      }
    }

    testset "!!set" {
      test "parse block map" {
        ttyp_set_parse("!!set\n? a\n? b\n? c\n")
      }
      test "parse flow map" {
        ttyp_set_parse("!!set { a, b, c }\n")
      }

      test "require null values" {
        let src_ = "!!set\n? a\n? b\nc: d\n";
        let doc = parseDocument(src_, Options { prettyErrors: false, version: "1.1" });
        expect_toMatchObject(doc.errors, [
          {
            "name": "YAMLParseError",
            "message": "Set items must not have non-empty values",
          },
        ])
      }

      test "stringify" {
        let s = js_set();
        s.add("a");
        s.add("b");
        s.add("c");
        let str = stringify(s, null, Options { version: "1.1" });
        expect_toBe(str, "!!set\n? a\n? b\n? c\n");
        let str2 = yaml_stringify(s);
        expect_toBe(str2, "- a\n- b\n- c\n")
      }

      test "stringify in collection (#78)" {
        let s = js_set();
        s.add("a");
        s.add("b");
        s.add("c");
        let str = stringify({ "set": s }, null, Options { version: "1.1" });
        expect_toBe(str, "set: !!set\n  ? a\n  ? b\n  ? c\n")
      }
    }

    // describe.for([...])('!!merge with %o', ...)
    testset "!!merge with { merge: true }" {
      test "alias" {
        ttyp_merge_alias(ttyp_merge_opts(0))
      }
      test "alias sequence" {
        ttyp_merge_alias_sequence(ttyp_merge_opts(0))
      }
      test "explicit creation" {
        ttyp_merge_explicit_creation(ttyp_merge_opts(0))
      }
      test "Creation by duck typing results in quoted \"<<\" key" {
        ttyp_merge_duck_typing(ttyp_merge_opts(0))
      }
      test "Using an explicit !!str tag on << makes it not a merge key" {
        ttyp_merge_str_tag(ttyp_merge_opts(0))
      }
      test "An explicit !!merge tag is retained" {
        ttyp_merge_merge_tag(ttyp_merge_opts(0))
      }
    }

    testset "!!merge with { merge: true, resolveKnownTags: false }" {
      test "alias" {
        ttyp_merge_alias(ttyp_merge_opts(1))
      }
      test "alias sequence" {
        ttyp_merge_alias_sequence(ttyp_merge_opts(1))
      }
      test "explicit creation" {
        ttyp_merge_explicit_creation(ttyp_merge_opts(1))
      }
      test "Creation by duck typing results in quoted \"<<\" key" {
        ttyp_merge_duck_typing(ttyp_merge_opts(1))
      }
      test "Using an explicit !!str tag on << makes it not a merge key" {
        ttyp_merge_str_tag(ttyp_merge_opts(1))
      }
      test "An explicit !!merge tag is retained" {
        ttyp_merge_merge_tag(ttyp_merge_opts(1))
      }
    }

    testset "!!merge with { schema: 'yaml-1.1' }" {
      test "alias" {
        ttyp_merge_alias(ttyp_merge_opts(2))
      }
      test "alias sequence" {
        ttyp_merge_alias_sequence(ttyp_merge_opts(2))
      }
      test "explicit creation" {
        ttyp_merge_explicit_creation(ttyp_merge_opts(2))
      }
      test "Creation by duck typing results in quoted \"<<\" key" {
        ttyp_merge_duck_typing(ttyp_merge_opts(2))
      }
      test "Using an explicit !!str tag on << makes it not a merge key" {
        ttyp_merge_str_tag(ttyp_merge_opts(2))
      }
      test "An explicit !!merge tag is retained" {
        ttyp_merge_merge_tag(ttyp_merge_opts(2))
      }
    }

    testset "!!merge with { version: '1.1' }" {
      test "alias" {
        ttyp_merge_alias(ttyp_merge_opts(3))
      }
      test "alias sequence" {
        ttyp_merge_alias_sequence(ttyp_merge_opts(3))
      }
      test "explicit creation" {
        ttyp_merge_explicit_creation(ttyp_merge_opts(3))
      }
      test "Creation by duck typing results in quoted \"<<\" key" {
        ttyp_merge_duck_typing(ttyp_merge_opts(3))
      }
      test "Using an explicit !!str tag on << makes it not a merge key" {
        ttyp_merge_str_tag(ttyp_merge_opts(3))
      }
      test "An explicit !!merge tag is retained" {
        ttyp_merge_merge_tag(ttyp_merge_opts(3))
      }
    }
  }

  testset "custom tags" {
    testset "local" {
      test "parse" {
        let doc = parseDocument(ttyp_local_src(), null);
        expect_toBeInstanceOf(doc.value, "YAMLSeq");
        expect_toBe(t_prop(doc.value, "tag"), "tag:example.com,2000:test/x");
        expect_toHaveLength(doc.value, 4);
        for (let item in ttyp_seq(doc.value).items) {
          expect_toBe(js_typeof(t_prop(item, "value")), "string");
        }
        expect_toBe(t_prop(t_prop(doc.value, "0"), "tag"), "!y");
        expect_toBe(t_prop(t_prop(doc.value, "1"), "tag"), "tag:example.com,2000:test/z");
        expect_toBe(t_prop(t_prop(doc.value, "2"), "tag"), "tag:example.com,2000:other/w")
      }

      test "stringify" {
        let doc = parseDocument(ttyp_local_src(), null);
        expect_toBe(doc.toString(null), "%TAG !e! tag:example.com,2000:test/\n---\n!e!x\n- !y \"2\"\n- !e!z \"3\"\n- !<tag:example.com,2000:other/w> \"4\"\n- '5'\n")
      }

      test "modify" {
        let doc = parseDocument(ttyp_local_src(), null);
        let prefix = "tag:example.com,2000:other/";
        let dir = doc.directives;
        if (dir != null) {
          dir.tags["!f!"] = prefix;
        }
        expect_toMatchObject(doc.directives?.tags, {
          "!!": "tag:yaml.org,2002:",
          "!e!": "tag:example.com,2000:test/",
          "!f!": prefix,
        });

        let seq = ttyp_seq(doc.value);
        seq.commentBefore = "c";
        ttyp_scalar(seq.items[3]).comment = "cc";
        let s = Scalar.new(6);
        s.tag = "!g";
        seq.splice(1, 1, [s, Scalar.new("7")]);
        expect_toBe(doc.toString(null), "%TAG !e! tag:example.com,2000:test/\n%TAG !f! tag:example.com,2000:other/\n---\n#c\n!e!x\n- !y \"2\"\n- !g 6\n- \"7\"\n- !f!w \"4\"\n- '5' #cc\n")
      }
    }

    testset "!!binary" {
      test "tag string in tags" {
        let bin = parse(ttyp_binary_src(), null, Options { customTags: ["binary"] });
        expect_toBeInstanceOf(bin, "Uint8Array")
      }

      test "tag string in tag array" {
        // ADAPTED: upstream passes a nested array `customTags: [['binary']]`
        // (flattened by Array#concat). `TagRef[]` cannot hold a nested array
        // in BAML, so this passes the flattened form.
        let bin = parse(ttyp_binary_src(), null, Options { customTags: ["binary"] });
        expect_toBeInstanceOf(bin, "Uint8Array")
      }

      test "custom tags from function" {
        let bin = parse(ttyp_binary_src(), null, Options {
          customTags: (tags: TagRef[]) -> TagRef[] {
            let out: TagRef[] = tags.slice(0, tags.length());
            out.push("binary");
            out
          },
        });
        expect_toBeInstanceOf(bin, "Uint8Array")
      }

      test "no custom tag object" {
        let bin = parse(ttyp_binary_src(), null, null);
        expect_toBeInstanceOf(bin, "Uint8Array")
      }
    }

    testset "RegExp" {
      test "stringify as plain scalar" {
        let str = stringify(ttyp_RegExp { source: "re", flags: "g" }, null, Options { customTags: [ttyp_regexp_tag()] });
        expect_toBe(str, "!re /re/g\n");
        let res = parse(str ?? "", null, Options { customTags: [ttyp_regexp_tag()] });
        expect_toBeInstanceOf(res, "ttyp_RegExp")
      }

      test "stringify as quoted scalar" {
        let str = stringify(ttyp_RegExp { source: "re: ", flags: "g" }, null, Options { customTags: [ttyp_regexp_tag()] });
        expect_toBe(str, "!re \"/re: /g\"\n");
        let res = parse(str ?? "", null, Options { customTags: [ttyp_regexp_tag()] });
        expect_toBeInstanceOf(res, "ttyp_RegExp")
      }

      test "parse plain string as string" {
        let res = parse("/re/g", null, Options { customTags: [ttyp_regexp_tag()] });
        expect_toBe(res, "/re/g")
      }

      test "parse quoted string as string" {
        let res = parse("\"/re/g\"", null, Options { customTags: [ttyp_regexp_tag()] });
        expect_toBe(res, "/re/g")
      }
    }

    testset "Symbol" {
      test "stringify as plain scalar" {
        let symbol = ttyp_symbol_for("foo");
        let str = stringify(symbol, null, Options { customTags: [ttyp_shared_symbol_tag()] });
        expect_toBe(str, "!symbol/shared foo\n");
        let res = parse(str ?? "", null, Options { customTags: [ttyp_shared_symbol_tag()] });
        expect_toBe(res, symbol)
      }

      test "stringify as block scalar" {
        let symbol = ttyp_symbol_for("foo\nbar");
        let str = stringify(symbol, null, Options { customTags: [ttyp_shared_symbol_tag()] });
        expect_toBe(str, "!symbol/shared |-\nfoo\nbar\n");
        let res = parse(str ?? "", null, Options { customTags: [ttyp_shared_symbol_tag()] });
        expect_toBe(res, symbol)
      }
    }

    test "null prototyped object" {
      let obj = ttyp_NullObject { entries: { "x": "y", "z": 1 } };
      let str = stringify(obj, null, Options { customTags: [ttyp_null_object_tag()] });
      expect_toBe(str, "!nullobject\nx: y\nz: 1\n");
      let res = parse(str ?? "", null, Options { customTags: [ttyp_null_object_tag()] });
      // `Object.getPrototypeOf(res) === null`: BAML maps have no prototype;
      // the closest check is that a plain map (not a class instance) results.
      expect_true(js_is_plain_object(res), "expected a plain object");
      expect_toMatchObject(res, obj.entries)
    }

    test "cannot parse sequence as nullobject" {
      let str = "!nullobject\n- y\n- 1\n";
      let doc = parseDocument(str, null);
      expect_toMatchObject(doc.warnings, [{ "code": "TAG_RESOLVE_FAILED" }])
    }

    test "array within customTags" {
      // ADAPTED: upstream passes a nested array `customTags: [[regexp, sharedSymbol]]`;
      // `TagRef[]` cannot hold a nested array in BAML, so this is flattened.
      let obj = { "re": ttyp_RegExp { source: "re", flags: "g" }, "symbol": ttyp_symbol_for("foo") };
      let str = stringify(obj, null, Options { customTags: [ttyp_regexp_tag(), ttyp_shared_symbol_tag()] });
      expect_toBe(str, "re: !re /re/g\nsymbol: !symbol/shared foo\n")
    }

    testset "schema from custom tags" {
      test "customTags is required" {
        expect_toThrow(() -> unknown { parseDocument("foo", Options { schema: "custom-test" }) }, "Unknown schema \"custom-test\"")
      }

      test "parse success" {
        let src_ = "- foo\n- !re /bar/\n";
        let doc = parseDocument(src_, Options {
          customTags: [seq_tag(), string_tag(), ttyp_regexp_tag()],
          schema: "custom-test",
        });
        expect_toEqual(doc.errors, []);
        expect_toEqual(doc.warnings, []);
        expect_toBe(doc.schema.name, "custom-test");
        expect_toEqual(doc.toJS(null), ["foo", ttyp_RegExp { source: "bar", flags: "" }])
      }

      test "parse fail" {
        // map, seq & string are always parsed, even if not included
        let src_ = "- foo\n- !re /bar/\n";
        let doc = parseDocument(src_, Options { customTags: [], schema: "custom-test" });
        expect_toEqual(doc.errors, []);
        expect_toHaveLength(doc.warnings, 1);
        expect_toMatch(doc.warnings[0].message, "Unresolved tag: !re")
      }

      test "stringify success" {
        let src_ = "- foo\n";
        let doc = parseDocument(src_, Options {
          customTags: [seq_tag(), string_tag()],
          schema: "custom-test",
        });
        expect_toBe(doc.toString(null), src_);

        src_ = "- foo\n- !re /bar/\n";
        doc = parseDocument(src_, Options {
          customTags: [seq_tag(), string_tag(), ttyp_regexp_tag()],
          schema: "custom-test",
        });
        expect_toBe(doc.toString(null), src_)
      }

      test "stringify fail" {
        let src_ = "- foo\n";
        let doc = parseDocument(src_, Options { customTags: [], schema: "custom-test" });
        let d1 = doc;
        expect_toThrow(() -> unknown { d1.toString(null) }, "Tag not resolved for YAMLSeq value");

        let d2 = parseDocument(src_, Options { customTags: [seq_tag()], schema: "custom-test" });
        expect_toThrow(() -> unknown { d2.toString(null) }, "Tag not resolved for String value")
      }

      test "setSchema" {
        let src_ = "- foo\n";
        let doc = parseDocument(src_, null);

        doc.setSchema("1.2", Options {
          customTags: [seq_tag(), string_tag()],
          schema: "custom-test-1",
        });
        expect_toBe(doc.toString(null), src_);

        doc.setSchema("1.2", Options {
          customTags: [string_tag()],
          schema: "custom-test-2",
        });
        expect_toThrow(() -> unknown { doc.toString(null) }, "Tag not resolved for YAMLSeq value")
      }
    }
  }

  testset "schema changes" {
    test "write as json" {
      let doc = parseDocument("foo: bar", Options { schema: "core" });
      expect_toBe(doc.schema.name, "core");
      doc.setSchema("1.2", Options { schema: "json" });
      expect_toBe(doc.schema.name, "json");
      expect_toBe(doc.toString(null), "\"foo\": \"bar\"\n")
    }

    test "fail for missing type" {
      let doc = parseDocument("foo: 1971-02-03T12:13:14", Options { version: "1.1" });
      expect_toMatchObject(doc.directives?.yaml, { "version": "1.1", "explicit": false });
      doc.setSchema("1.2", null);
      expect_toMatchObject(doc.directives?.yaml, { "version": "1.2", "explicit": false });
      expect_toBe(doc.schema.name, "core");
      expect_toThrow(() -> unknown { doc.toString(null) }, "Tag not resolved for Date value")
    }

    test "fail for missing null type (#616)" {
      let doc = parseDocument("foo:", null);
      doc.setSchema("1.2", Options { schema: "failsafe" });
      expect_toThrow(() -> unknown { doc.toString(null) }, "Tag not resolved for null value")
    }

    test "set schema + custom tags" {
      let doc = parseDocument("foo: 1971-02-03T12:13:14", Options { version: "1.1" });
      doc.setSchema("1.1", Options { customTags: ["timestamp"], schema: "json" });
      expect_toBe(doc.toString(null), "\"foo\": 1971-02-03T12:13:14\n")
    }

    test "set version + custom tags" {
      let doc = parseDocument("foo: 1971-02-03T12:13:14", Options { version: "1.1" });
      // ADAPTED: upstream passes the number `1.2` (a type error in TS, coerced
      // at runtime); `version` is `string?` in BAML.
      doc.setSchema("1.2", Options { customTags: ["timestamp"] });
      expect_toBe(doc.toString(null), "foo: 1971-02-03T12:13:14\n")
    }

    test "schema changes on bool" {
      let doc = parseDocument("[y, yes, on, n, no, off]", Options { version: "1.1" });
      doc.setSchema("1.1", Options { schema: "core" });
      expect_toBe(doc.toString(null), "[ true, true, true, false, false, false ]\n");
      doc.setSchema("1.1", null);
      expect_toBe(doc.toString(null), "[ y, yes, on, n, no, off ]\n")
    }

    test "set bool + re-stringified" {
      let doc = parseDocument("a: True", Options { version: "1.2" });
      doc.set("a", false);
      expect_toBe(doc.toString(null), "a: false\n");

      doc = parseDocument("a: on", Options { version: "1.1" });
      doc.set("a", false);
      expect_toBe(doc.toString(null), "a: false\n")
    }

    test "custom schema instance" {
      let src_ = "[ !!bool yes, &foo no, *foo ]";
      let doc = parseDocument(src_, Options { version: "1.1" });

      let core = Schema.new(Options { schema: "core" });
      doc.setSchema("1.2", Options { schema: core });
      expect_toBe(doc.toString(null), "[ !!bool true, &foo false, *foo ]\n");

      let yaml11 = Schema.new(Options { schema: "yaml-1.1" });
      // `Object.assign({}, yaml11)`: a shallow copy
      doc.setSchema("1.1", Options { schema: Schema { ...yaml11, _id: new_id() } });
      expect_toBe(doc.toString(null), "[ !!bool yes, &foo no, *foo ]\n");

      doc.setSchema(null, Options { schema: core });
      expect_toBe(doc.toString(null), "[ true, false, false ]\n")
    }

    test "null version requires Schema instance" {
      let doc = parseDocument("foo: bar", null);
      let msg = "With a null YAML version, the { schema: Schema } option is required";
      expect_toThrow(() -> unknown { doc.setSchema(null, null) }, msg);
      expect_toThrow(() -> unknown { doc.setSchema(null, Options { schema: "core" }) }, msg);
      doc.setSchema(null, Options { schema: doc.schema });
      expect_toBe(doc.toString(null), "foo: bar\n")
    }
  }
}
