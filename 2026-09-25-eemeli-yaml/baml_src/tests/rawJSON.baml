// Port of tests/rawJSON.ts
//
// `JSON.rawJSON(text)` / `JSON.isRawJSON(v)` are modelled by the library's
// `js_raw_json(text)` / `js_is_raw_json(v)` (class `JsRawJSON`). Upstream
// only runs these when the JS runtime supports `JSON.rawJSON`
// (`describe.runIf(JSON.rawJSON)`); here they always run.

function traw_repeat(s: string, n: int) -> string {
  let out = "";
  let i = 0;
  while (i < n) {
    out += s;
    i += 1;
  }
  out
}

testset "rawJSON" {
  testset "stringify raw JSON" {
    test "quoted string" {
      let raw = "\"Foo\\n bar\"";
      let res = yaml_stringify(js_raw_json(raw));
      expect_toBe(res, raw + "\n")
    }

    test "long number in array" {
      let raw = traw_repeat("9", 99);
      let res = yaml_stringify([js_raw_json(raw)]);
      expect_toBe(res, "- " + raw + "\n")
    }
  }

  testset "node creation" {
    test "quoted string in constructor" {
      let raw = "\"Foo\\n bar\"";
      let doc = Document.new(js_raw_json(raw), null, null);
      expect_toBeInstanceOf(doc.value, "Scalar");
      expect_toBe(js_is_raw_json(t_prop(doc.value, "value")), true);
      expect_toBe(doc.toString(null), raw + "\n")
    }

    test "long number added to sequence" {
      let raw = traw_repeat("9", 99);
      let doc = Document.new([], null, null);
      match (doc.value) {
        let s: YAMLSeq => {
          s.push(js_raw_json(raw));
        },
        _ => {
          fail("expected a YAMLSeq");
        },
      }
      expect_toBeInstanceOf(t_prop(doc.value, "0"), "Scalar");
      expect_toBe(doc.toString(null), "- " + raw + "\n")
    }
  }
}
