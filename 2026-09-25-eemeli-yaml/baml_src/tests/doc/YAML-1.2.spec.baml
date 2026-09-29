// Port of tests/doc/YAML-1.2.spec.ts
//
// Upstream is table-driven: a `spec` object of YAML 1.2 spec examples
// (`src`, `tgt`, optional `errors`/`warnings`/`jsWarnings`/`special`) and a
// loop generating one test per example. BAML `test` blocks are static, so the
// table is spelled out here as one `TspecCase` literal per test (generated
// mechanically from the upstream object by evaluating it in node), each
// passed to the shared checker `tspec_run` (the upstream loop body).
// `special(src)` callbacks are hand-ported as `tspec_sp_*` functions.
//
// Partial port: upstream spies on `process.emitWarning`/`console.warn`
// (`vi.spyOn`) and asserts it was not called unless `jsWarnings` is set. The
// BAML library's `warn()` writes to stderr and cannot be intercepted, so that
// assertion is omitted (the `jsWarnings` branch upstream asserts nothing, as
// its `expect(...)` has no matcher). `jsWarnings` is kept as table data only.

class TspecCase {
  src: string
  tgt: unknown[]
  errors: string[][]?
  warnings: string[][]?
  jsWarnings: bool?
  special: ((string) -> null throws unknown)?
}

function tspec_obj() -> map<string, unknown> {
  let o: map<string, unknown> = {};
  o
}

/// `new Set([...])`
function tspec_set<T>(values: T[]) -> JsSet {
  let s = js_set();
  for (let v in values) {
    s.add(v);
  }
  s
}

/// `new Map([[k, v], ...])`
function tspec_jsmap(entries: unknown[][]) -> JsMap<unknown> {
  let m = js_map();
  for (let e in entries) {
    m.set(e[0], e[1]);
  }
  m
}

/// `Buffer.from(data)` / `new Uint8Array(data)`
function tspec_bytes(data: int[]) -> uint8array {
  baml.Uint8Array.from_array(data) catch (e) {
    _ => baml.sys.panic("bad byte array"),
  }
}

/// `arr?.[i] ?? []`
function tspec_at(arr: string[][]?, i: int) -> string[] {
  match (arr) {
    let a: string[][] => if (i < a.length()) { a[i] } else { [] },
    _ => [],
  }
}

function tspec_messages(errs: YAMLError[]) -> string[] {
  errs.map((e: YAMLError) -> string { e.message })
}

function tspec_toJS(docs: Document[]) -> unknown[] {
  docs.map((doc: Document) -> unknown { doc.toJS(null) })
}

/// The body of upstream's generated `test(name, () => { ... })`.
function tspec_run(c: TspecCase) -> null {
  let documents = parseAllDocuments(c.src, Options { prettyErrors: false }).docs;
  let json = tspec_toJS(documents);
  expect_toMatchObject(json, c.tgt);
  let i = 0;
  for (let doc in documents) {
    expect_toMatchObject(tspec_messages(doc.errors), tspec_at(c.errors, i));
    expect_toMatchObject(tspec_set(tspec_messages(doc.warnings)), tspec_set(tspec_at(c.warnings, i)));
    for (let err in doc.errors.concat(doc.warnings)) {
      expect_toBeInstanceOf(err, "YAMLError");
    }
    // UNPORTABLE (see file header): `expect(mockWarn).not.toHaveBeenCalled()`
    i += 1;
  }
  let special = c.special;
  if (special != null) {
    special(c.src);
  }
  if (c.errors == null) {
    let src2 = documents.map((doc: Document) -> string { doc.toString(null) }).join("");
    let documents2 = parseAllDocuments(src2, Options { prettyErrors: false }).docs;
    let json2 = tspec_toJS(documents2);
    expect_toMatchObject(json2, c.tgt);
  }
  null
}

/// `{ tag, resolve: (str) => fn(str) }`
function tspec_tag(tag: string, fn: (string) -> string throws unknown) -> Tag {
  Tag {
    _id: new_id(),
    tag: tag,
    resolve: (str: string, onError: TagOnError, opts: Options) -> unknown { fn(str) },
  }
}

// ─── special(src) callbacks ────────────────────────────────────────────────

// Example 2.22. Timestamps
function tspec_sp_22(src: string) -> null {
  let obj = parse(src, null, Options { schema: "yaml-1.1" });
  expect_toHaveLength(js_as_object(obj)?.keys(), 4);
  for (let key in ["canonical", "iso8601", "spaced", "date"]) {
    let date = t_prop(obj, key);
    expect_toBeInstanceOf(date, "Date");
    // JS getFullYear()/getMonth() use local time; JsDate only knows UTC.
    // For these values the year/month agree in every time zone.
    let iso = match (date) {
      let d: JsDate => d.toISOString(),
      _ => "",
    };
    expect_toBe(iso.slice(0, 4), "2001");
    expect_toBe(iso.slice(5, 7), "12");
  }
  null
}

// Example 2.23. Various Explicit Tags
function tspec_sp_23(src: string) -> null {
  let doc = parseDocument(src, Options { schema: "yaml-1.1" });
  let data = t_prop(doc.get("picture"), "value");
  expect_toBeInstanceOf(data, "Uint8Array");
  let n = match (data) {
    let u: uint8array => u.length(),
    _ => -1,
  };
  expect_toBe(n, 65);
  null
}

// Example 5.5. Comment Indicator
function tspec_sp_31(src: string) -> null {
  let doc = parseDocument(src, null);
  expect_toBe(t_prop(doc.value, "commentBefore"), " Comment only.");
  null
}

// Example 5.6. Node Property Indicators
function tspec_sp_32(src: string) -> null {
  let tag = tspec_tag("!local", (str: string) -> string { "local:" + str });
  let res = parse(src, null, Options { customTags: [tag] });
  expect_toMatchObject(res, { "anchored": "local:value", "alias": "local:value" });
  null
}

function tspec_expect_yaml_directive(doc: Document, version: string, explicit: bool) -> null {
  expect_toMatchObject(doc.directives?.yaml, { "version": version, "explicit": explicit });
  null
}

// Example 5.9. Directive Indicator
function tspec_sp_35(src: string) -> null {
  tspec_expect_yaml_directive(parseDocument(src, null), "1.2", true)
}

// Example 6.10. Comment Lines
function tspec_sp_49(src: string) -> null {
  let doc = parseDocument(src, null);
  expect_toBe(doc.commentBefore, " Comment");
  null
}

// Example 6.14. “YAML” directive
function tspec_sp_53(src: string) -> null {
  tspec_expect_yaml_directive(parseDocument(src, null), "1.2", true)
}

// Example 6.15. Invalid Repeated YAML directive
function tspec_sp_54(src: string) -> null {
  tspec_expect_yaml_directive(parseDocument(src, null), "1.1", true)
}

// Example 6.17. Invalid Repeated TAG directive
function tspec_sp_56(src: string) -> null {
  let doc = parseDocument(src, null);
  expect_toMatchObject(doc.directives?.tags, { "!!": "tag:yaml.org,2002:", "!": "!foo" });
  null
}

// Example 6.18. Primary Tag Handle
function tspec_sp_57(src: string) -> null {
  let customTags: TagRef[] = [
    tspec_tag("!foo", (str: string) -> string { "private" }),
    tspec_tag("tag:example.com,2000:app/foo", (str: string) -> string { "global" }),
  ];
  let docs = parseAllDocuments(src, Options { customTags: customTags }).docs;
  expect_toMatchObject(tspec_toJS(docs), ["private", "global"]);
  null
}

// Example 6.19. Secondary Tag Handle
function tspec_sp_58(src: string) -> null {
  let tag = tspec_tag("tag:example.com,2000:app/int", (str: string) -> string { "interval" });
  let res = parse(src, null, Options { customTags: [tag] });
  expect_toBe(res, "interval");
  null
}

// Example 6.20. Tag Handles
function tspec_sp_59(src: string) -> null {
  let tag = tspec_tag("tag:example.com,2000:app/foo", (str: string) -> string { "foo" + str });
  let res = parse(src, null, Options { customTags: [tag] });
  expect_toBe(res, "foobar");
  null
}

// Example 6.21. Local Tag Prefix
function tspec_sp_60(src: string) -> null {
  let tag = tspec_tag("!my-light", (str: string) -> string { "light:" + str });
  let docs = parseAllDocuments(src, Options { customTags: [tag] }).docs;
  expect_toMatchObject(tspec_toJS(docs), ["light:fluorescent", "light:green"]);
  null
}

// Example 6.22. Global Tag Prefix
function tspec_sp_61(src: string) -> null {
  let tag = tspec_tag("tag:example.com,2000:app/foo", (str: string) -> string { "foo" + str });
  let res = parse(src, null, Options { customTags: [tag] });
  expect_toMatchObject(res, ["foobar"]);
  null
}

// Example 6.24. Verbatim Tags
function tspec_sp_63(src: string) -> null {
  let tag = tspec_tag("!bar", (str: string) -> string { "bar" + str });
  let res = parse(src, null, Options { customTags: [tag] });
  expect_toMatchObject(res, { "foo": "barbaz" });
  null
}

// Example 6.26. Tag Shorthands
function tspec_sp_65(src: string) -> null {
  let customTags: TagRef[] = [
    tspec_tag("!local", (str: string) -> string { "local:" + str }),
    tspec_tag("tag:example.com,2000:app/tag!", (str: string) -> string { "tag!" + str }),
  ];
  let res = parse(src, null, Options { customTags: customTags });
  expect_toMatchObject(res, ["local:foo", "bar", "tag!baz"]);
  null
}

// Example 8.21. Block Scalar Nodes
function tspec_sp_110(src: string) -> null {
  let tag = tspec_tag("!foo", (str: string) -> string { "foo" + str });
  let res = parse(src, null, Options { customTags: [tag] });
  expect_toMatchObject(res, { "literal": "value\n", "folded": "foovalue\n" });
  null
}

// Example 8.22. Block Collection Nodes
function tspec_sp_111(src: string) -> null {
  let doc = parseDocument(src, null);
  expect_toBeNull(t_prop(doc.value, "tag"));
  let seq = doc.get("sequence");
  expect_toBe(t_prop(seq, "tag"), "tag:yaml.org,2002:seq");
  // `seq[1]`: upstream YAMLSeq extends Array; here its elements are `items`.
  let second = match (seq) {
    let s: YAMLSeq => s.items[1],
    _ => null,
  };
  expect_toBe(t_prop(second, "tag"), "tag:yaml.org,2002:seq");
  expect_toBe(t_prop(doc.get("mapping"), "tag"), "tag:yaml.org,2002:map");
  null
}

// Example 9.2. Document Markers
function tspec_sp_113(src: string) -> null {
  tspec_expect_yaml_directive(parseDocument(src, null), "1.2", true)
}

function tspec_yaml_directives(src: string) -> unknown[] {
  parseAllDocuments(src, null).docs.map((doc: Document) -> unknown { doc.directives?.yaml })
}

// Example 9.5. Directives Documents
function tspec_sp_116(src: string) -> null {
  expect_toMatchObject(tspec_yaml_directives(src), [
    { "version": "1.2", "explicit": true },
    { "version": "1.2", "explicit": true },
  ]);
  null
}

// Example 9.6. Stream
function tspec_sp_117(src: string) -> null {
  expect_toMatchObject(tspec_yaml_directives(src), [
    { "version": "1.2", "explicit": false },
    { "version": "1.2", "explicit": false },
    { "version": "1.2", "explicit": true },
  ]);
  null
}

testset "doc/YAML-1.2.spec" {
  testset "2.1. Collections" {
    test "Example 2.1. Sequence of Scalars" {
      tspec_run(TspecCase {
        src: "- Mark McGwire\r\n- Sammy Sosa\r\n- Ken Griffey\r\n",
        tgt: [["Mark McGwire", "Sammy Sosa", "Ken Griffey"]],
      })
    }

    test "Example 2.2. Mapping Scalars to Scalars" {
      tspec_run(TspecCase {
        src: "hr:  65    # Home runs\r\navg: 0.278 # Batting average\r\nrbi: 147   # Runs Batted In",
        tgt: [{ "hr": 65, "avg": 0.278, "rbi": 147 }],
      })
    }

    test "Example 2.3. Mapping Scalars to Sequences" {
      tspec_run(TspecCase {
        src: "american:\r\n  - Boston Red Sox\r\n  - Detroit Tigers\r\n  - New York Yankees\r\nnational:\r\n  - New York Mets\r\n  - Chicago Cubs\r\n  - Atlanta Braves",
        tgt: [
          {
            "american": ["Boston Red Sox", "Detroit Tigers", "New York Yankees"],
            "national": ["New York Mets", "Chicago Cubs", "Atlanta Braves"]
          }
        ],
      })
    }

    test "Example 2.4. Sequence of Mappings" {
      tspec_run(TspecCase {
        src: "-\n  name: Mark McGwire\n  hr:   65\n  avg:  0.278\n-\n  name: Sammy Sosa\n  hr:   63\n  avg:  0.288",
        tgt: [
          [
            { "name": "Mark McGwire", "hr": 65, "avg": 0.278 },
            { "name": "Sammy Sosa", "hr": 63, "avg": 0.288 }
          ]
        ],
      })
    }

    test "Example 2.5. Sequence of Sequences" {
      tspec_run(TspecCase {
        src: "- [name        , hr, avg  ]\n- [Mark McGwire, 65, 0.278]\n- [Sammy Sosa  , 63, 0.288]",
        tgt: [
          [["name", "hr", "avg"], ["Mark McGwire", 65, 0.278], ["Sammy Sosa", 63, 0.288]]
        ],
      })
    }

    test "Example 2.6. Mapping of Mappings" {
      tspec_run(TspecCase {
        src: "Mark McGwire: {hr: 65, avg: 0.278}\nSammy Sosa: {\n    hr: 63,\n    avg: 0.288\n  }",
        tgt: [
          {
            "Mark McGwire": { "hr": 65, "avg": 0.278 },
            "Sammy Sosa": { "hr": 63, "avg": 0.288 }
          }
        ],
      })
    }
  }

  testset "2.2. Structures" {
    test "Example 2.7. Two Documents in a Stream" {
      tspec_run(TspecCase {
        src: "# Ranking of 1998 home runs\n---\n- Mark McGwire\n- Sammy Sosa\n- Ken Griffey\n\n# Team ranking\n---\n- Chicago Cubs\n- St Louis Cardinals",
        tgt: [
          ["Mark McGwire", "Sammy Sosa", "Ken Griffey"],
          ["Chicago Cubs", "St Louis Cardinals"]
        ],
      })
    }

    test "Example 2.8. Play by Play Feed" {
      tspec_run(TspecCase {
        src: "---\ntime: 20:03:20\nplayer: Sammy Sosa\naction: strike (miss)\n...\n---\ntime: 20:03:47\nplayer: Sammy Sosa\naction: grand slam\n...",
        tgt: [
          { "time": "20:03:20", "player": "Sammy Sosa", "action": "strike (miss)" },
          { "time": "20:03:47", "player": "Sammy Sosa", "action": "grand slam" }
        ],
      })
    }

    test "Example 2.9. Single Document with Two Comments" {
      tspec_run(TspecCase {
        src: "---\nhr: # 1998 hr ranking\n  - Mark McGwire\n  - Sammy Sosa\nrbi:\n  # 1998 rbi ranking\n  - Sammy Sosa\n  - Ken Griffey",
        tgt: [
          { "hr": ["Mark McGwire", "Sammy Sosa"], "rbi": ["Sammy Sosa", "Ken Griffey"] }
        ],
      })
    }

    test "Example 2.10. Node for “Sammy Sosa” appears twice in this document" {
      tspec_run(TspecCase {
        src: "---\nhr:\n  - Mark McGwire\n  # Following node labeled SS\n  - &SS Sammy Sosa\nrbi:\n  - *SS # Subsequent occurrence\n  - Ken Griffey",
        tgt: [
          { "hr": ["Mark McGwire", "Sammy Sosa"], "rbi": ["Sammy Sosa", "Ken Griffey"] }
        ],
      })
    }

    test "Example 2.11. Mapping between Sequences" {
      tspec_run(TspecCase {
        src: "? - Detroit Tigers\n  - Chicago cubs\n:\n  - 2001-07-23\n\n? [ New York Yankees,\n    Atlanta Braves ]\n: [ 2001-07-02, 2001-08-12,\n    2001-08-14 ]",
        tgt: [
          {
            "[ Detroit Tigers, Chicago cubs ]": ["2001-07-23"],
            "[ New York Yankees, Atlanta Braves ]": ["2001-07-02", "2001-08-12", "2001-08-14"]
          }
        ],
        jsWarnings: true,
      })
    }

    test "Example 2.12. Compact Nested Mapping" {
      tspec_run(TspecCase {
        src: "---\n# Products purchased\n- item    : Super Hoop\n  quantity: 1\n- item    : Basketball\n  quantity: 4\n- item    : Big Shoes\n  quantity: 1",
        tgt: [
          [
            { "item": "Super Hoop", "quantity": 1 },
            { "item": "Basketball", "quantity": 4 },
            { "item": "Big Shoes", "quantity": 1 }
          ]
        ],
      })
    }
  }

  testset "2.3. Scalars" {
    test "Example 2.13. In literals, newlines are preserved" {
      tspec_run(TspecCase {
        src: "# ASCII Art\n--- |\n  \\//||\\/||\n  // ||  ||__",
        tgt: ["\\//||\\/||\n// ||  ||__\n"],
      })
    }

    test "Example 2.14. In the folded scalars, newlines become spaces" {
      tspec_run(TspecCase {
        src: "--- >\n  Mark McGwire's\n  year was crippled\n  by a knee injury.",
        tgt: ["Mark McGwire's year was crippled by a knee injury.\n"],
      })
    }

    test "Example 2.15. Folded newlines are preserved for \"more indented\" and blank lines" {
      tspec_run(TspecCase {
        src: ">\n Sammy Sosa completed another\n fine season with great stats.\n\n   63 Home Runs\n   0.288 Batting Average\n\n What a year!",
        tgt: [
          "Sammy Sosa completed another fine season with great stats.\n\n  63 Home Runs\n  0.288 Batting Average\n\nWhat a year!\n"
        ],
      })
    }

    test "Example 2.16. Indentation determines scope" {
      tspec_run(TspecCase {
        src: "name: Mark McGwire\naccomplishment: >\n  Mark set a major league\n  home run record in 1998.\nstats: |\n  65 Home Runs\n  0.278 Batting Average",
        tgt: [
          {
            "name": "Mark McGwire",
            "accomplishment": "Mark set a major league home run record in 1998.\n",
            "stats": "65 Home Runs\n0.278 Batting Average\n"
          }
        ],
      })
    }

    test "Example 2.17. Quoted Scalars" {
      tspec_run(TspecCase {
        src: "unicode: \"Sosa did fine.\\u263A\"\ncontrol: \"\\b1998\\t1999\\t2000\\n\"\nhex esc: \"\\x0d\\x0a is \\r\\n\"\n\nsingle: '\"Howdy!\" he cried.'\nquoted: ' # Not a ''comment''.'\ntie-fighter: '|\\-*-/|'",
        tgt: [
          {
            "unicode": "Sosa did fine.☺",
            "control": chr(8) + "1998\t1999\t2000\n",
            "hex esc": "\r\n is \r\n",
            "single": "\"Howdy!\" he cried.",
            "quoted": " # Not a 'comment'.",
            "tie-fighter": "|\\-*-/|"
          }
        ],
      })
    }

    test "Example 2.18. Multi-line Flow Scalars" {
      tspec_run(TspecCase {
        src: "plain:\n  This unquoted scalar\n  spans many lines.\n\nquoted: \"So does this\n  quoted scalar.\\n\"",
        tgt: [
          {
            "plain": "This unquoted scalar spans many lines.",
            "quoted": "So does this quoted scalar.\n"
          }
        ],
      })
    }
  }

  testset "2.4. Tags" {
    test "Example 2.19. Integers" {
      tspec_run(TspecCase {
        src: "canonical: 12345\ndecimal: +12345\noctal: 0o14\nhexadecimal: 0xC",
        tgt: [{ "canonical": 12345, "decimal": 12345, "octal": 12, "hexadecimal": 12 }],
      })
    }

    test "Example 2.20. Floating Point" {
      tspec_run(TspecCase {
        src: "canonical: 1.23015e+3\nexponential: 12.3015e+02\nfixed: 1230.15\nnegative infinity: -.inf\nnot a number: .NaN",
        tgt: [
          {
            "canonical": 1230.15,
            "exponential": 1230.15,
            "fixed": 1230.15,
            "negative infinity": (0.0 - baml.Float.inf()),
            "not a number": baml.Float.nan()
          }
        ],
      })
    }

    test "Example 2.21. Miscellaneous" {
      tspec_run(TspecCase {
        src: "null:\nbooleans: [ true, false ]\nstring: '012345'",
        tgt: [{ "": null, "booleans": [true, false], "string": "012345" }],
      })
    }

    test "Example 2.22. Timestamps" {
      tspec_run(TspecCase {
        src: "canonical: 2001-12-15T02:59:43.1Z\niso8601: 2001-12-14t21:59:43.10-05:00\nspaced: 2001-12-14 21:59:43.10 -5\ndate: 2001-12-14",
        tgt: [
          {
            "canonical": "2001-12-15T02:59:43.1Z",
            "iso8601": "2001-12-14t21:59:43.10-05:00",
            "spaced": "2001-12-14 21:59:43.10 -5",
            "date": "2001-12-14"
          }
        ],
        // special: special(src) {
        //         const obj = YAML.parse(src, { schema: 'yaml-1.1' })
        //         expect(Object.keys(obj)).toHaveLength(4)
        //         for (const key of ['canonical', 'iso8601', 'spaced', 'date']) {
        //           const date = obj[key]
        //           expect(date).toBeInstanceOf(Date)
        //           expect(date.getFullYear()).toBe(2001)
        //           expect(date.getMonth()).toBe(11)
        //         }
        //       }
        special: (src: string) -> null { tspec_sp_22(src) },
      })
    }

    test "Example 2.23. Various Explicit Tags" {
      tspec_run(TspecCase {
        src: "---\nnot-date: !!str 2002-04-28\n\npicture: !!binary |\n R0lGODlhDAAMAIQAAP//9/X\n 17unp5WZmZgAAAOfn515eXv\n Pz7Y6OjuDg4J+fn5OTk6enp\n 56enmleECcgggoBADs=\n\napplication specific tag: !something |\n The semantics of the tag\n above may be different for\n different documents.",
        tgt: [
          {
            "not-date": "2002-04-28",
            "picture": tspec_bytes([
              71,
              73,
              70,
              56,
              57,
              97,
              12,
              0,
              12,
              0,
              132,
              0,
              0,
              255,
              255,
              247,
              245,
              245,
              238,
              233,
              233,
              229,
              102,
              102,
              102,
              0,
              0,
              0,
              231,
              231,
              231,
              94,
              94,
              94,
              243,
              243,
              237,
              142,
              142,
              142,
              224,
              224,
              224,
              159,
              159,
              159,
              147,
              147,
              147,
              167,
              167,
              167,
              158,
              158,
              158,
              105,
              94,
              16,
              39,
              32,
              130,
              10,
              1,
              0,
              59
            ]),
            "application specific tag": "The semantics of the tag\nabove may be different for\ndifferent documents.\n"
          }
        ],
        warnings: [["Unresolved tag: !something"]],
        // special: special(src) {
        //         const doc = YAML.parseDocument(src, { schema: 'yaml-1.1' })
        //         const data = doc.get('picture').value
        //         expect(data).toBeInstanceOf(Uint8Array)
        //         expect(data.byteLength).toBe(65)
        //       }
        special: (src: string) -> null { tspec_sp_23(src) },
      })
    }

    test "Example 2.24. Global Tags" {
      tspec_run(TspecCase {
        src: "%TAG ! tag:clarkevans.com,2002:\n--- !shape\n  # Use the ! handle for presenting\n  # tag:clarkevans.com,2002:circle\n- !circle\n  center: &ORIGIN {x: 73, y: 129}\n  radius: 7\n- !line\n  start: *ORIGIN\n  finish: { x: 89, y: 102 }\n- !label\n  start: *ORIGIN\n  color: 0xFFEEBB\n  text: Pretty vector drawing.",
        tgt: [
          [
            { "center": { "x": 73, "y": 129 }, "radius": 7 },
            { "start": { "x": 73, "y": 129 }, "finish": { "x": 89, "y": 102 } },
            {
              "start": { "x": 73, "y": 129 },
              "color": 16772795,
              "text": "Pretty vector drawing."
            }
          ]
        ],
        warnings: [
          [
            "Unresolved tag: tag:clarkevans.com,2002:circle",
            "Unresolved tag: tag:clarkevans.com,2002:line",
            "Unresolved tag: tag:clarkevans.com,2002:label",
            "Unresolved tag: tag:clarkevans.com,2002:shape"
          ]
        ],
      })
    }

    test "Example 2.25. Unordered Sets" {
      tspec_run(TspecCase {
        src: "# Sets are represented as a\n# Mapping where each key is\n# associated with a null value\n--- !!set\n? Mark McGwire\n? Sammy Sosa\n? Ken Griff",
        tgt: [tspec_set(["Mark McGwire", "Sammy Sosa", "Ken Griff"])],
      })
    }

    test "Example 2.26. Ordered Mappings" {
      tspec_run(TspecCase {
        src: "# Ordered maps are represented as\n# A sequence of mappings, with\n# each mapping having one key\n--- !!omap\n- Mark McGwire: 65\n- Sammy Sosa: 63\n- Ken Griffy: 58\n\n",
        tgt: [tspec_jsmap([["Mark McGwire", 65], ["Sammy Sosa", 63], ["Ken Griffy", 58]])],
      })
    }
  }

  testset "2.5. Full Length Example" {
    test "Example 2.27. Invoice" {
      tspec_run(TspecCase {
        src: "--- !<tag:clarkevans.com,2002:invoice>\ninvoice: 34843\ndate   : 2001-01-23\nbill-to: &id001\n    given  : Chris\n    family : Dumars\n    address:\n        lines: |\n            458 Walkman Dr.\n            Suite #292\n        city    : Royal Oak\n        state   : MI\n        postal  : 48046\nship-to: *id001\nproduct:\n    - sku         : BL394D\n      quantity    : 4\n      description : Basketball\n      price       : 450.00\n    - sku         : BL4438H\n      quantity    : 1\n      description : Super Hoop\n      price       : 2392.00\ntax  : 251.42\ntotal: 4443.52\ncomments:\n    Late afternoon is best.\n    Backup contact is Nancy\n    Billsmer @ 338-4338.",
        tgt: [
          {
            "invoice": 34843,
            "date": "2001-01-23",
            "bill-to": {
              "given": "Chris",
              "family": "Dumars",
              "address": {
                "lines": "458 Walkman Dr.\nSuite #292\n",
                "city": "Royal Oak",
                "state": "MI",
                "postal": 48046
              }
            },
            "ship-to": {
              "given": "Chris",
              "family": "Dumars",
              "address": {
                "lines": "458 Walkman Dr.\nSuite #292\n",
                "city": "Royal Oak",
                "state": "MI",
                "postal": 48046
              }
            },
            "product": [
              { "sku": "BL394D", "quantity": 4, "description": "Basketball", "price": 450 },
              { "sku": "BL4438H", "quantity": 1, "description": "Super Hoop", "price": 2392 }
            ],
            "tax": 251.42,
            "total": 4443.52,
            "comments": "Late afternoon is best. Backup contact is Nancy Billsmer @ 338-4338."
          }
        ],
        warnings: [["Unresolved tag: tag:clarkevans.com,2002:invoice"]],
      })
    }

    test "Example 2.28. Log File" {
      tspec_run(TspecCase {
        src: "---\nTime: 2001-11-23 15:01:42 -5\nUser: ed\nWarning:\n  This is an error message\n  for the log file\n---\nTime: 2001-11-23 15:02:31 -5\nUser: ed\nWarning:\n  A slightly different error\n  message.\n---\nDate: 2001-11-23 15:03:17 -5\nUser: ed\nFatal:\n  Unknown variable \"bar\"\nStack:\n  - file: TopClass.py\n    line: 23\n    code: |\n      x = MoreObject(\"345\\n\")\n  - file: MoreClass.py\n    line: 58\n    code: |-\n      foo = bar\n",
        tgt: [
          {
            "Time": "2001-11-23 15:01:42 -5",
            "User": "ed",
            "Warning": "This is an error message for the log file"
          },
          {
            "Time": "2001-11-23 15:02:31 -5",
            "User": "ed",
            "Warning": "A slightly different error message."
          },
          {
            "Date": "2001-11-23 15:03:17 -5",
            "User": "ed",
            "Fatal": "Unknown variable \"bar\"",
            "Stack": [
              { "file": "TopClass.py", "line": 23, "code": "x = MoreObject(\"345\\n\")\n" },
              { "file": "MoreClass.py", "line": 58, "code": "foo = bar" }
            ]
          }
        ],
      })
    }
  }

  testset "5.3. Indicator Characters" {
    test "Example 5.3. Block Structure Indicators" {
      tspec_run(TspecCase {
        src: "sequence:\n- one\n- two\nmapping:\n  ? sky\n  : blue\n  sea : green",
        tgt: [{ "sequence": ["one", "two"], "mapping": { "sky": "blue", "sea": "green" } }],
      })
    }

    test "Example 5.4. Flow Collection Indicators" {
      tspec_run(TspecCase {
        src: "sequence: [ one, two, ]\nmapping: { sky: blue, sea: green }",
        tgt: [{ "sequence": ["one", "two"], "mapping": { "sky": "blue", "sea": "green" } }],
      })
    }

    test "Example 5.5. Comment Indicator" {
      tspec_run(TspecCase {
        src: "# Comment only.",
        tgt: [],
        // special: special(src) {
        //         const doc = YAML.parseDocument(src)
        //         expect(doc.value.commentBefore).toBe(' Comment only.')
        //       }
        special: (src: string) -> null { tspec_sp_31(src) },
      })
    }

    test "Example 5.6. Node Property Indicators" {
      tspec_run(TspecCase {
        src: "anchored: !local &anchor value\nalias: *anchor",
        tgt: [{ "anchored": "value", "alias": "value" }],
        warnings: [["Unresolved tag: !local"]],
        // special: special(src) {
        //         const tag = { tag: '!local', resolve: (str) => `local:${str}` }
        //         const res = YAML.parse(src, { customTags: [tag] })
        //         expect(res).toMatchObject({
        //           anchored: 'local:value',
        //           alias: 'local:value'
        //         })
        //       }
        special: (src: string) -> null { tspec_sp_32(src) },
      })
    }

    test "Example 5.7. Block Scalar Indicators" {
      tspec_run(TspecCase {
        src: "literal: |\n  some\n  text\nfolded: >\n  some\n  text\n",
        tgt: [{ "literal": "some\ntext\n", "folded": "some text\n" }],
      })
    }

    test "Example 5.8. Quoted Scalar Indicators" {
      tspec_run(TspecCase {
        src: "single: 'text'\ndouble: \"text\"",
        tgt: [{ "single": "text", "double": "text" }],
      })
    }

    test "Example 5.9. Directive Indicator" {
      tspec_run(TspecCase {
        src: "%YAML 1.2\n--- text",
        tgt: ["text"],
        // special: special(src) {
        //         const doc = YAML.parseDocument(src)
        //         expect(doc.directives.yaml).toMatchObject({
        //           version: '1.2',
        //           explicit: true
        //         })
        //       }
        special: (src: string) -> null { tspec_sp_35(src) },
      })
    }

    test "Example 5.10. Invalid use of Reserved Indicators" {
      tspec_run(TspecCase {
        src: "commercial-at: @text\ngrave-accent: `text",
        tgt: [{ "commercial-at": "@text", "grave-accent": "`text" }],
        errors: [
          [
            "Plain value cannot start with reserved character @",
            "Plain value cannot start with reserved character `"
          ]
        ],
      })
    }
  }

  testset "5.5. White Space Characters" {
    test "Example 5.12. Tabs and Spaces" {
      tspec_run(TspecCase {
        src: "# Tabs and spaces\nquoted: \"Quoted \t\"\nblock:\t|\n  void main() {\n  \tprintf(\"Hello, world!\\n\");\n  }",
        tgt: [
          {
            "quoted": "Quoted \t",
            "block": "void main() {\n\tprintf(\"Hello, world!\\n\");\n}\n"
          }
        ],
      })
    }
  }

  testset "5.7. Escaped Characters" {
    test "Example 5.13. Escaped Characters" {
      tspec_run(TspecCase {
        src: "\"Fun with \\\\\n\\\" \\a \\b \\e \\f \\\n\\n \\r \\t \\v \\0 \\\n\\  \\_ \\N \\L \\P \\\n\\x41 \\u0041 \\U00000041\"",
        tgt: [
          "Fun with \\ \" " + chr(7) + " " + chr(8) + " " + chr(27) + " " + chr(12) + " \n \r \t " + chr(11) + " " + chr(0) + "     " + chr(133) + " " + chr(8232) + " " + chr(8233) + " A A A"
        ],
      })
    }

    test "Example 5.14. Invalid Escaped Characters" {
      tspec_run(TspecCase {
        src: "Bad escapes:\n  \"\\c\n  \\xq-\"",
        tgt: [{ "Bad escapes": "\\c \\xq-" }],
        errors: [["Invalid escape sequence \\c", "Invalid escape sequence \\xq-"]],
      })
    }
  }

  testset "6.1. Indentation Spaces" {
    test "Example 6.1. Indentation Spaces" {
      tspec_run(TspecCase {
        src: "  # Leading comment line spaces are\n   # neither content nor indentation.\n\nNot indented:\n By one space: |\n    By four\n      spaces\n Flow style: [    # Leading spaces\n   By two,        # in flow style\n  Also by two,    # are neither\n  \tStill by two   # content nor\n    ]             # indentation.",
        tgt: [
          {
            "Not indented": {
              "By one space": "By four\n  spaces\n",
              "Flow style": ["By two", "Also by two", "Still by two"]
            }
          }
        ],
      })
    }

    test "Example 6.2. Indentation Indicators" {
      tspec_run(TspecCase {
        src: "? a\n: -\tb\n  -  -\tc\n     - d",
        tgt: [{ "a": ["b", ["c", "d"]] }],
      })
    }
  }

  testset "6.2. Separation Spaces" {
    test "Example 6.3. Separation Spaces" {
      tspec_run(TspecCase {
        src: "- foo:\t bar\n- - baz\n  -\tbaz",
        tgt: [[{ "foo": "bar" }, ["baz", "baz"]]],
      })
    }
  }

  testset "6.3. Line Prefixes" {
    test "Example 6.4. Line Prefixes" {
      tspec_run(TspecCase {
        src: "plain: text\n  lines\nquoted: \"text\n  \tlines\"\nblock: |\n  text\n   \tlines",
        tgt: [
          { "plain": "text lines", "quoted": "text lines", "block": "text\n \tlines\n" }
        ],
      })
    }
  }

  testset "6.4. Empty Lines" {
    test "Example 6.5. Empty Lines" {
      tspec_run(TspecCase {
        src: "Folding:\n  \"Empty line\n   \t\n  as a line feed\"\nChomping: |\n  Clipped empty lines\n ",
        tgt: [
          {
            "Folding": "Empty line\nas a line feed",
            "Chomping": "Clipped empty lines\n"
          }
        ],
      })
    }
  }

  testset "6.5. Line Folding" {
    test "Example 6.6. Line Folding" {
      tspec_run(TspecCase {
        src: ">-\n  trimmed\n  \n \n\n  as\n  space",
        tgt: ["trimmed\n\n\nas space"],
      })
    }

    test "Example 6.7. Block Folding" {
      tspec_run(TspecCase {
        src: ">\n  foo \n \n  \t bar\n\n  baz\n",
        tgt: ["foo \n\n\t bar\n\nbaz\n"],
      })
    }

    test "Example 6.8. Flow Folding" {
      tspec_run(TspecCase {
        src: "\"\n  foo\t\n\t\n  \t bar\n\n  baz\n\"",
        tgt: [" foo\nbar\nbaz "],
      })
    }
  }

  testset "6.6. Comments" {
    test "Example 6.9. Separated Comment" {
      tspec_run(TspecCase {
        src: "key:    # Comment\n  value",
        tgt: [{ "key": "value" }],
      })
    }

    test "Example 6.10. Comment Lines" {
      tspec_run(TspecCase {
        src: "  # Comment\n   \n\n",
        tgt: [],
        // special: special(src) {
        //         const doc = YAML.parseDocument(src)
        //         expect(doc.commentBefore).toBe(' Comment')
        //       }
        special: (src: string) -> null { tspec_sp_49(src) },
      })
    }

    test "Example 6.11. Multi-Line Comments" {
      tspec_run(TspecCase {
        src: "key:    # Comment\n        # lines\n  value\n",
        tgt: [{ "key": "value" }],
      })
    }
  }

  testset "6.7. Separation Lines" {
    test "Example 6.12. Separation Spaces" {
      tspec_run(TspecCase {
        src: "{ first: Sammy, last: Sosa }:\n# Statistics:\n  hr:  # Home runs\n     65\n  avg: # Average\n   0.278",
        tgt: [{ "{ first: Sammy, last: Sosa }": { "hr": 65, "avg": 0.278 } }],
        jsWarnings: true,
      })
    }
  }

  testset "6.8. Directives" {
    test "Example 6.13. Reserved Directives" {
      tspec_run(TspecCase {
        src: "%FOO  bar baz # Should be ignored\n# with a warning.\n--- \"foo\"",
        tgt: ["foo"],
        warnings: [["Unknown directive %FOO"]],
      })
    }
  }

  testset "6.8.1. “YAML” Directives" {
    test "Example 6.14. “YAML” directive" {
      tspec_run(TspecCase {
        src: "%YAML 1.3 # Attempt parsing\n           # with a warning\n---\n\"foo\"",
        tgt: ["foo"],
        warnings: [["Unsupported YAML version 1.3"]],
        // special: special(src) {
        //         const doc = YAML.parseDocument(src)
        //         expect(doc.directives.yaml).toMatchObject({
        //           version: '1.2',
        //           explicit: true
        //         })
        //       }
        special: (src: string) -> null { tspec_sp_53(src) },
      })
    }

    test "Example 6.15. Invalid Repeated YAML directive" {
      tspec_run(TspecCase {
        src: "%YAML 1.2\n%YAML 1.1\n---\nfoo",
        tgt: ["foo"],
        // special: special(src) {
        //         const doc = YAML.parseDocument(src)
        //         expect(doc.directives.yaml).toMatchObject({
        //           version: '1.1',
        //           explicit: true
        //         })
        //       }
        special: (src: string) -> null { tspec_sp_54(src) },
      })
    }
  }

  testset "6.8.2. “TAG” Directives" {
    test "Example 6.16. “TAG” directive" {
      tspec_run(TspecCase {
        src: "%TAG !yaml! tag:yaml.org,2002:\n---\n!yaml!str \"foo\"",
        tgt: ["foo"],
      })
    }

    test "Example 6.17. Invalid Repeated TAG directive" {
      tspec_run(TspecCase {
        src: "%TAG ! !foo\n%TAG ! !foo\n---\nbar",
        tgt: ["bar"],
        // special: special(src) {
        //         const doc = YAML.parseDocument(src)
        //         expect(doc.directives.tags).toMatchObject({
        //           '!!': 'tag:yaml.org,2002:',
        //           '!': '!foo'
        //         })
        //       }
        special: (src: string) -> null { tspec_sp_56(src) },
      })
    }

    test "Example 6.18. Primary Tag Handle" {
      tspec_run(TspecCase {
        src: "# Private\n!foo \"bar\"\n...\n# Global\n%TAG ! tag:example.com,2000:app/\n---\n!foo \"bar\"",
        tgt: ["bar", "bar"],
        warnings: [["Unresolved tag: !foo"], ["Unresolved tag: tag:example.com,2000:app/foo"]],
        // special: special(src) {
        //         const customTags = [
        //           {
        //             tag: '!foo',
        //             resolve: () => 'private'
        //           },
        //           {
        //             tag: 'tag:example.com,2000:app/foo',
        //             resolve: () => 'global'
        //           }
        //         ]
        //         const docs = YAML.parseAllDocuments(src, { customTags })
        //         expect(docs.map(d => d.toJS())).toMatchObject(['private', 'global'])
        //       }
        special: (src: string) -> null { tspec_sp_57(src) },
      })
    }

    test "Example 6.19. Secondary Tag Handle" {
      tspec_run(TspecCase {
        src: "%TAG !! tag:example.com,2000:app/\n---\n!!int 1 - 3 # Interval, not integer",
        tgt: ["1 - 3"],
        warnings: [["Unresolved tag: tag:example.com,2000:app/int"]],
        // special: special(src) {
        //         const tag = {
        //           tag: 'tag:example.com,2000:app/int',
        //           resolve: () => 'interval'
        //         }
        //         const res = YAML.parse(src, { customTags: [tag] })
        //         expect(res).toBe('interval')
        //       }
        special: (src: string) -> null { tspec_sp_58(src) },
      })
    }

    test "Example 6.20. Tag Handles" {
      tspec_run(TspecCase {
        src: "%TAG !e! tag:example.com,2000:app/\n---\n!e!foo \"bar\"",
        tgt: ["bar"],
        warnings: [["Unresolved tag: tag:example.com,2000:app/foo"]],
        // special: special(src) {
        //         const tag = {
        //           tag: 'tag:example.com,2000:app/foo',
        //           resolve: (str) => `foo${str}`
        //         }
        //         const res = YAML.parse(src, { customTags: [tag] })
        //         expect(res).toBe('foobar')
        //       }
        special: (src: string) -> null { tspec_sp_59(src) },
      })
    }

    test "Example 6.21. Local Tag Prefix" {
      tspec_run(TspecCase {
        src: "%TAG !m! !my-\n--- # Bulb here\n!m!light fluorescent\n...\n%TAG !m! !my-\n--- # Color here\n!m!light green",
        tgt: ["fluorescent", "green"],
        warnings: [["Unresolved tag: !my-light"], ["Unresolved tag: !my-light"]],
        // special: special(src) {
        //         const tag = {
        //           tag: '!my-light',
        //           resolve: (str) => `light:${str}`
        //         }
        //         const docs = YAML.parseAllDocuments(src, { customTags: [tag] })
        //         expect(docs.map(d => d.toJS())).toMatchObject([
        //           'light:fluorescent',
        //           'light:green'
        //         ])
        //       }
        special: (src: string) -> null { tspec_sp_60(src) },
      })
    }

    test "Example 6.22. Global Tag Prefix" {
      tspec_run(TspecCase {
        src: "%TAG !e! tag:example.com,2000:app/\n---\n- !e!foo \"bar\"",
        tgt: [["bar"]],
        warnings: [["Unresolved tag: tag:example.com,2000:app/foo"]],
        // special: special(src) {
        //         const tag = {
        //           tag: 'tag:example.com,2000:app/foo',
        //           resolve: (str) => `foo${str}`
        //         }
        //         const res = YAML.parse(src, { customTags: [tag] })
        //         expect(res).toMatchObject(['foobar'])
        //       }
        special: (src: string) -> null { tspec_sp_61(src) },
      })
    }
  }

  testset "6.9. Node Properties" {
    test "Example 6.23. Node Properties" {
      tspec_run(TspecCase {
        src: "!!str &a1 \"foo\":\n  !!str bar\n&a2 baz : *a1",
        tgt: [{ "foo": "bar", "baz": "foo" }],
      })
    }

    test "Example 6.24. Verbatim Tags" {
      tspec_run(TspecCase {
        src: "!<tag:yaml.org,2002:str> foo :\n  !<!bar> baz",
        tgt: [{ "foo": "baz" }],
        warnings: [["Unresolved tag: !bar"]],
        // special: special(src) {
        //         const tag = { tag: '!bar', resolve: (str) => `bar${str}` }
        //         const res = YAML.parse(src, { customTags: [tag] })
        //         expect(res).toMatchObject({ foo: 'barbaz' })
        //       }
        special: (src: string) -> null { tspec_sp_63(src) },
      })
    }

    test "Example 6.25. Invalid Verbatim Tags" {
      tspec_run(TspecCase {
        src: "- !<!> foo\n- !<$:?> bar",
        tgt: [["foo", "bar"]],
        errors: [["Verbatim tags aren't resolved, so !<!> is invalid."]],
        warnings: [["Unresolved tag: $:?"]],
      })
    }

    test "Example 6.26. Tag Shorthands" {
      tspec_run(TspecCase {
        src: "%TAG !e! tag:example.com,2000:app/\n---\n- !local foo\n- !!str bar\n- !e!tag%21 baz",
        tgt: [["foo", "bar", "baz"]],
        warnings: [["Unresolved tag: !local", "Unresolved tag: tag:example.com,2000:app/tag!"]],
        // special: special(src) {
        //         const customTags = [
        //           { tag: '!local', resolve: (str) => `local:${str}` },
        //           {
        //             tag: 'tag:example.com,2000:app/tag!',
        //             resolve: (str) => `tag!${str}`
        //           }
        //         ]
        //         const res = YAML.parse(src, { customTags })
        //         expect(res).toMatchObject(['local:foo', 'bar', 'tag!baz'])
        //       }
        special: (src: string) -> null { tspec_sp_65(src) },
      })
    }

    test "Example 6.27. Invalid Tag Shorthands" {
      tspec_run(TspecCase {
        src: "%TAG !e! tag:example,2000:app/\n---\n- !e! foo\n- !h!bar baz",
        tgt: [["foo", "baz"]],
        errors: [["The !e! tag has no suffix", "Could not resolve tag: !h!bar"]],
        warnings: [["Unresolved tag: tag:example,2000:app/"]],
      })
    }

    test "Example 6.28. Non-Specific Tags" {
      tspec_run(TspecCase {
        src: "# Assuming conventional resolution:\n- \"12\"\n- 12\n- ! 12",
        tgt: [["12", 12, "12"]],
      })
    }

    test "Example 6.29. Node Anchors" {
      tspec_run(TspecCase {
        src: "First occurrence: &anchor Value\nSecond occurrence: *anchor",
        tgt: [{ "First occurrence": "Value", "Second occurrence": "Value" }],
      })
    }
  }

  testset "7.1. Alias Nodes" {
    test "Example 7.1. Alias Nodes" {
      tspec_run(TspecCase {
        src: "First occurrence: &anchor Foo\nSecond occurrence: *anchor\nOverride anchor: &anchor Bar\nReuse anchor: *anchor",
        tgt: [
          {
            "First occurrence": "Foo",
            "Second occurrence": "Foo",
            "Override anchor": "Bar",
            "Reuse anchor": "Bar"
          }
        ],
      })
    }
  }

  testset "7.2. Empty Nodes" {
    test "Example 7.2. Empty Content" {
      tspec_run(TspecCase {
        src: "{\n  foo : !!str,\n  !!str : bar,\n}",
        tgt: [{ "foo": "", "": "bar" }],
      })
    }

    test "Example 7.3. Completely Empty Flow Nodes" {
      tspec_run(TspecCase {
        src: "{\n  ? foo :,\n  : bar,\n}",
        tgt: [{ "foo": null, "": "bar" }],
      })
    }
  }

  testset "7.3.1. Double-Quoted Style" {
    test "Example 7.4. Double Quoted Implicit Keys" {
      tspec_run(TspecCase {
        src: "\"implicit block key\" : [\n  \"implicit flow key\" : value,\n ]",
        tgt: [{ "implicit block key": [{ "implicit flow key": "value" }] }],
      })
    }

    test "Example 7.5. Double Quoted Line Breaks" {
      tspec_run(TspecCase {
        src: "\"folded\nto a space,\t\n\nto a line feed, or \t\\\n \\ \tnon-content\"",
        tgt: ["folded to a space,\nto a line feed, or \t \tnon-content"],
      })
    }

    test "Example 7.6. Double Quoted Lines" {
      tspec_run(TspecCase {
        src: "\" 1st non-empty\n\n 2nd non-empty\n\t3rd non-empty \"",
        tgt: [" 1st non-empty\n2nd non-empty 3rd non-empty "],
      })
    }
  }

  testset "7.3.2. Single-Quoted Style" {
    test "Example 7.7. Single Quoted Characters" {
      tspec_run(TspecCase {
        src: " 'here''s to \"quotes\"'",
        tgt: ["here's to \"quotes\""],
      })
    }

    test "Example 7.8. Single Quoted Implicit Keys" {
      tspec_run(TspecCase {
        src: "'implicit block key' : [\n  'implicit flow key' : value,\n ]",
        tgt: [{ "implicit block key": [{ "implicit flow key": "value" }] }],
      })
    }

    test "Example 7.9. Single Quoted Lines" {
      tspec_run(TspecCase {
        src: "' 1st non-empty\n\n 2nd non-empty\t\n\t3rd non-empty '",
        tgt: [" 1st non-empty\n2nd non-empty 3rd non-empty "],
      })
    }
  }

  testset "7.3.3. Plain Style" {
    test "Example 7.10. Plain Characters" {
      tspec_run(TspecCase {
        src: "# Outside flow collection:\n- ::vector\n- \": - ()\"\n- Up, up, and away!\n- -123\n- http://example.com/foo#bar\n# Inside flow collection:\n- [ ::vector,\n  \": - ()\",\n  \"Up, up and away!\",\n  -123,\n  http://example.com/foo#bar ]",
        tgt: [
          [
            "::vector",
            ": - ()",
            "Up, up, and away!",
            -123,
            "http://example.com/foo#bar",
            ["::vector", ": - ()", "Up, up and away!", -123, "http://example.com/foo#bar"]
          ]
        ],
      })
    }

    test "Example 7.11. Plain Implicit Keys" {
      tspec_run(TspecCase {
        src: "implicit block key : [\n  implicit flow key : value,\n ]",
        tgt: [{ "implicit block key": [{ "implicit flow key": "value" }] }],
      })
    }

    test "Example 7.12. Plain Lines" {
      tspec_run(TspecCase {
        src: "1st non-empty\n\n 2nd non-empty\n\t3rd non-empty",
        tgt: ["1st non-empty\n2nd non-empty 3rd non-empty"],
      })
    }
  }

  testset "7.4.1. Flow Sequences" {
    test "Example 7.13. Flow Sequence" {
      tspec_run(TspecCase {
        src: "- [ one, two, ]\n- [three ,four]",
        tgt: [[["one", "two"], ["three", "four"]]],
      })
    }

    test "Example 7.14. Flow Sequence Entries" {
      tspec_run(TspecCase {
        src: "[\n\"double\n quoted\", 'single\n           quoted',\nplain\n text, [ nested ],\nsingle: pair,\n]",
        tgt: [
          [
            "double quoted",
            "single quoted",
            "plain text",
            ["nested"],
            { "single": "pair" }
          ]
        ],
      })
    }
  }

  testset "7.4.2. Flow Mappings" {
    test "Example 7.15. Flow Mappings" {
      tspec_run(TspecCase {
        src: "- { one : two , three: four , }\n- {five: six,seven : eight}",
        tgt: [[{ "one": "two", "three": "four" }, { "five": "six", "seven": "eight" }]],
      })
    }

    test "Example 7.16. Flow Mapping Entries" {
      tspec_run(TspecCase {
        src: "{\n? explicit: entry,\nimplicit: entry,\n?\n}",
        tgt: [{ "explicit": "entry", "implicit": "entry", "": null }],
      })
    }

    test "Example 7.17. Flow Mapping Separate Values" {
      tspec_run(TspecCase {
        src: "{\nunquoted : \"separate\",\nhttp://foo.com,\nomitted value:,\n: omitted key,\n}",
        tgt: [
          {
            "unquoted": "separate",
            "http://foo.com": null,
            "omitted value": null,
            "": "omitted key"
          }
        ],
      })
    }

    test "Example 7.18. Flow Mapping Adjacent Values" {
      tspec_run(TspecCase {
        src: "{\n\"adjacent\":value,\n\"readable\": value,\n\"empty\":\n}",
        tgt: [{ "adjacent": "value", "readable": "value", "empty": null }],
      })
    }

    test "Example 7.19. Single Pair Flow Mappings" {
      tspec_run(TspecCase {
        src: "[\nfoo: bar\n]",
        tgt: [[{ "foo": "bar" }]],
      })
    }

    test "Example 7.20. Single Pair Explicit Entry" {
      tspec_run(TspecCase {
        src: "[\n? foo\n bar : baz\n]",
        tgt: [[{ "foo bar": "baz" }]],
      })
    }

    test "Example 7.21. Single Pair Implicit Entries" {
      tspec_run(TspecCase {
        src: "- [ YAML : separate ]\n- [ : empty key entry ]\n- [ {JSON: like}:adjacent ]",
        tgt: [
          [
            [{ "YAML": "separate" }],
            [{ "": "empty key entry" }],
            [{ "{ JSON: like }": "adjacent" }]
          ]
        ],
        jsWarnings: true,
      })
    }

    test "Example 7.22. Invalid Implicit Keys" {
      tspec_run(TspecCase {
        src: "[ foo\n bar: invalid,\n \"foo xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx bar\": invalid ]",
        tgt: [
          [
            { "foo bar": "invalid" },
            {
              "foo xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx bar": "invalid"
            }
          ]
        ],
        errors: [
          [
            "Implicit keys of flow sequence pairs need to be on a single line",
            "The : indicator must be at most 1024 chars after the start of an implicit flow sequence key"
          ]
        ],
      })
    }
  }

  testset "7.5. Flow Nodes" {
    test "Example 7.23. Flow Content" {
      tspec_run(TspecCase {
        src: "- [ a, b ]\n- { a: b }\n- \"a\"\n- 'b'\n- c",
        tgt: [[["a", "b"], { "a": "b" }, "a", "b", "c"]],
      })
    }

    test "Example 7.24. Flow Nodes" {
      tspec_run(TspecCase {
        src: "- !!str \"a\"\n- 'b'\n- &anchor \"c\"\n- *anchor\n- !!str",
        tgt: [["a", "b", "c", "c", ""]],
      })
    }
  }

  testset "8.1.1. Block Scalar Headers" {
    test "Example 8.1. Block Scalar Header" {
      tspec_run(TspecCase {
        src: "- | # Empty header\n literal\n- >1 # Indentation indicator\n  folded\n- |+ # Chomping indicator\n keep\n\n- >1- # Both indicators\n  strip",
        tgt: [["literal\n", " folded\n", "keep\n\n", " strip"]],
      })
    }

    test "Example 8.2. Block Indentation Indicator" {
      tspec_run(TspecCase {
        src: "- |\n detected\n- >\n \n  \n  # detected\n- |1\n  explicit\n- >\n \t\n detected",
        tgt: [["detected\n", "\n\n# detected\n", " explicit\n", "\t\ndetected\n"]],
      })
    }

    test "Example 8.3. Invalid Block Scalar Indentation Indicators" {
      tspec_run(TspecCase {
        src: "- |\n  \n text\n---\n- >\n  text\n text\n---\n- |2\n text",
        tgt: [[" \ntext\n"], ["text\n", "text"], ["", "text"]],
        errors: [
          [
            "Block scalars with more-indented leading empty lines must use an explicit indentation indicator"
          ],
          ["Sequence item without - indicator"],
          ["Sequence item without - indicator"]
        ],
      })
    }

    test "Example 8.4. Chomping Final Line Break" {
      tspec_run(TspecCase {
        src: "strip: |-\n  text\nclip: |\n  text\nkeep: |+\n  text\n",
        tgt: [{ "strip": "text", "clip": "text\n", "keep": "text\n" }],
      })
    }

    test "Example 8.5. Chomping Trailing Lines" {
      tspec_run(TspecCase {
        src: "\n # Strip\n  # Comments:\nstrip: |-\n  # text\n\n # Clip\n  # comments:\n\nclip: |\n  # text\n\n # Keep\n  # comments:\n\nkeep: |+\n  # text\n\n # Trail\n  # comments.",
        tgt: [{ "strip": "# text", "clip": "# text\n", "keep": "# text\n\n" }],
      })
    }

    test "Example 8.6. Empty Scalar Chomping" {
      tspec_run(TspecCase {
        src: "strip: >-\n\nclip: >\n\nkeep: |+\n\n",
        tgt: [{ "strip": "", "clip": "", "keep": "\n" }],
      })
    }
  }

  testset "8.1.2. Literal Style" {
    test "Example 8.7. Literal Scalar" {
      tspec_run(TspecCase {
        src: "|\n literal\n \ttext\n\n",
        tgt: ["literal\n\ttext\n"],
      })
    }

    test "Example 8.8. Literal Content" {
      tspec_run(TspecCase {
        src: "|\n \n  \n  literal\n   \n  \n  text\n\n # Comment",
        tgt: ["\n\nliteral\n \n\ntext\n"],
      })
    }
  }

  testset "8.1.3. Folded Style" {
    test "Example 8.9. Folded Scalar" {
      tspec_run(TspecCase {
        src: ">\n folded\n text\n\n",
        tgt: ["folded text\n"],
      })
    }

    test "Example 8.10. Folded Lines" {
      tspec_run(TspecCase {
        src: ">\n\n folded\n line\n\n next\n line\n   * bullet\n\n   * list\n   * lines\n\n last\n line\n\n# Comment",
        tgt: ["\nfolded line\nnext line\n  * bullet\n\n  * list\n  * lines\n\nlast line\n"],
      })
    }
  }

  testset "8.2.1. Block Sequences" {
    test "Example 8.14. Block Sequence" {
      tspec_run(TspecCase {
        src: "block sequence:\n  - one\n  - two : three\n",
        tgt: [{ "block sequence": ["one", { "two": "three" }] }],
      })
    }

    test "Example 8.15. Block Sequence Entry Types" {
      tspec_run(TspecCase {
        src: "- # Empty\n- |\n block node\n- - one # Compact\n  - two # sequence\n- one: two # Compact mapping",
        tgt: [[null, "block node\n", ["one", "two"], { "one": "two" }]],
      })
    }
  }

  testset "8.2.2. Block Mappings" {
    test "Example 8.16. Block Mappings" {
      tspec_run(TspecCase {
        src: "block mapping:\n key: value\n",
        tgt: [{ "block mapping": { "key": "value" } }],
      })
    }

    test "Example 8.17. Explicit Block Mapping Entries" {
      tspec_run(TspecCase {
        src: "? explicit key # Empty value\n? |\n  block key\n: - one # Explicit compact\n  - two # block value\n",
        tgt: [{ "explicit key": null, "block key\n": ["one", "two"] }],
      })
    }

    test "Example 8.18. Implicit Block Mapping Entries" {
      tspec_run(TspecCase {
        src: "plain key: in-line value\n: # Both empty\n\"quoted key\":\n- entry",
        tgt: [{ "plain key": "in-line value", "": null, "quoted key": ["entry"] }],
      })
    }

    test "Example 8.19. Compact Block Mappings" {
      tspec_run(TspecCase {
        src: "- sun: yellow\n- ? earth: blue\n  : moon: white\n",
        tgt: [[{ "sun": "yellow" }, { "{ earth: blue }": { "moon": "white" } }]],
        jsWarnings: true,
      })
    }
  }

  testset "8.2.3. Block Nodes" {
    test "Example 8.20. Block Types" {
      tspec_run(TspecCase {
        src: "-\n  \"flow in block\"\n- >\n Block scalar\n- !!map # Block collection\n  foo : bar\n",
        tgt: [["flow in block", "Block scalar\n", { "foo": "bar" }]],
      })
    }

    test "Example 8.21. Block Scalar Nodes" {
      tspec_run(TspecCase {
        src: "literal: |2\n  value\nfolded:\n   !foo\n  >1\n value",
        tgt: [{ "literal": "value\n", "folded": "value\n" }],
        warnings: [["Unresolved tag: !foo"]],
        // special: special(src) {
        //         const tag = { tag: '!foo', resolve: (str) => `foo${str}` }
        //         const res = YAML.parse(src, { customTags: [tag] })
        //         expect(res).toMatchObject({ literal: 'value\n', folded: 'foovalue\n' })
        //       }
        special: (src: string) -> null { tspec_sp_110(src) },
      })
    }

    test "Example 8.22. Block Collection Nodes" {
      tspec_run(TspecCase {
        src: "sequence: !!seq\n- entry\n- !!seq\n - nested\nmapping: !!map\n foo: bar",
        tgt: [{ "sequence": ["entry", ["nested"]], "mapping": { "foo": "bar" } }],
        // special: special(src) {
        //         const doc = YAML.parseDocument(src)
        //         expect(doc.value.tag).toBeUndefined()
        //         const seq = doc.get('sequence')
        //         expect(seq.tag).toBe('tag:yaml.org,2002:seq')
        //         expect(seq[1].tag).toBe('tag:yaml.org,2002:seq')
        //         expect(doc.get('mapping').tag).toBe('tag:yaml.org,2002:map')
        //       }
        special: (src: string) -> null { tspec_sp_111(src) },
      })
    }
  }

  testset "9.1. Documents" {
    test "Example 9.1. Document Prefix" {
      tspec_run(TspecCase {
        src: chr(65279) + "# Comment\n# lines\nDocument",
        tgt: ["Document"],
      })
    }

    test "Example 9.2. Document Markers" {
      tspec_run(TspecCase {
        src: "%YAML 1.2\n---\nDocument\n... # Suffix",
        tgt: ["Document"],
        // special: special(src) {
        //         expect(YAML.parseDocument(src).directives.yaml).toMatchObject({
        //           version: '1.2',
        //           explicit: true
        //         })
        //       }
        special: (src: string) -> null { tspec_sp_113(src) },
      })
    }

    test "Example 9.3. Bare Documents" {
      tspec_run(TspecCase {
        src: "Bare\ndocument\n...\n# No document\n...\n|\n%!PS-Adobe-2.0 # Not the first line",
        tgt: ["Bare document", null, "%!PS-Adobe-2.0 # Not the first line\n"],
      })
    }

    test "Example 9.4. Explicit Documents" {
      tspec_run(TspecCase {
        src: "---\n{ matches\n% : 20 }\n...\n---\n# Empty\n...",
        tgt: [{ "matches %": 20 }, null],
      })
    }

    test "Example 9.5. Directives Documents" {
      tspec_run(TspecCase {
        src: "%YAML 1.2\n--- |\n%!PS-Adobe-2.0\n...\n%YAML 1.2\n---\n# Empty\n...",
        tgt: ["%!PS-Adobe-2.0\n", null],
        // special: special(src) {
        //         expect(
        //           YAML.parseAllDocuments(src).map(doc => doc.directives.yaml)
        //         ).toMatchObject([
        //           { version: '1.2', explicit: true },
        //           { version: '1.2', explicit: true }
        //         ])
        //       }
        special: (src: string) -> null { tspec_sp_116(src) },
      })
    }
  }

  testset "9.2. Streams" {
    test "Example 9.6. Stream" {
      tspec_run(TspecCase {
        src: "Document\n---\n# Empty\n...\n%YAML 1.2\n---\nmatches %: 20",
        tgt: ["Document", null, { "matches %": 20 }],
        // special: special(src) {
        //         expect(
        //           YAML.parseAllDocuments(src).map(doc => doc.directives.yaml)
        //         ).toMatchObject([
        //           { version: '1.2', explicit: false },
        //           { version: '1.2', explicit: false },
        //           { version: '1.2', explicit: true }
        //         ])
        //       }
        special: (src: string) -> null { tspec_sp_117(src) },
      })
    }
  }
}
