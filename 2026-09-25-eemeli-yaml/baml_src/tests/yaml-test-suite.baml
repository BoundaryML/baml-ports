// Port of tests/yaml-test-suite.ts
//
// The upstream file generates vitest `describe`/`test` blocks at runtime by
// reading `tests/yaml-test-suite/src/*.yaml` (parsed with this library).
// BAML test blocks are static, so `tools/gen_yaml_test_suite.py` generates
// `yaml-test-suite.generated.baml` with one test per (case, check); each test
// calls into the runner functions below, which read and parse the case file
// with the ported library at test time, exactly as upstream does.

class YtsCase {
  name: string
  yaml: string
  fail: bool
  tree: string?
  json: string?
  emit: string?
}

function yts_unescape(text: string) -> string {
  text
    .replace_all("␣", " ")
    .replace_all(re("—*»"), "\t")
    .replace_all("←", "\r")
    .replace_all("⇔", "x{FEFF}")
    .replace_all("↵", "")
    .replace_all("∎\n", "")
}

function yts_str(o: map<string, unknown>, key: string) -> string? {
  match (o.get(key)) {
    let s: string => s,
    _ => null,
  }
}

/// Load case `idx` of test file `id`. As upstream, later cases inherit
/// unspecified keys? No: each case stands alone except for `name`.
function yts_load(id: string, idx: int) -> YtsCase {
  let path = tests_root() + "/yaml-test-suite/src/" + id + ".yaml";
  let file = baml.fs.read(path) catch (e) {
    _ => baml.sys.panic("cannot read " + path),
  };
  let testData = js_as_array(parse(file, null, null));
  if (testData == null) {
    throw js_error("Unsupported test file: " + id);
  }
  let td: unknown[] = testData ?? [];
  let first = js_as_object(td[0]) ?? {};
  let c = js_as_object(td[idx]) ?? {};
  YtsCase {
    name: yts_str(first, "name") ?? "",
    yaml: yts_unescape(yts_str(c, "yaml") ?? ""),
    fail: c.get("fail") == true,
    tree: yts_str(c, "tree"),
    json: yts_str(c, "json"),
    emit: yts_str(c, "emit"),
  }
}

function yts_testJsonMatch(docs: Document[], json: string) -> null {
  if (json == "") {
    return null;
  }
  let received: unknown = if (docs.length() > 0) {
    docs.map((doc: Document) -> unknown { doc.toJS(null) })
  } else {
    null
  };
  let expected: unknown[] = [];
  if (docs.length() > 1) {
    for (let line in json.replace(re("\\n$"), "").split("\n")) {
      expected.push(baml.json.parse(line) catch (e) { _ => fail("bad json: " + line) });
    }
  } else {
    expected.push(baml.json.parse(json) catch (e) { _ => fail("bad json: " + json) });
  }
  expect_toEqual(received, expected)
}

/// test('lexer completes')
function yts_lexer(id: string, idx: int) -> null {
  let c = yts_load(id, idx);
  let tokens = lex(c.yaml.replace_all(re("(?<!\\r)\\n"), "\r\n"));
  expect_true(tokens.length() < 9000, "expected fewer than 9000 tokens")
}

/// test('cst stringify')
function yts_cst(id: string, idx: int) -> null {
  let c = yts_load(id, idx);
  let res = "";
  for (let tok in new_parser(null).parse(c.yaml)) {
    res += cst_stringify(tok);
  }
  expect_toBe(res, c.yaml)
}

/// test('test.event')
function yts_event(id: string, idx: int) -> null {
  let c = yts_load(id, idx);
  let res = testEvents(c.yaml);
  let exp = yts_unescape(c.tree ?? "").replace_all(re("(?m)^\\s+"), "");
  expect_toBe(res.events.join("\n") + "\n", exp);
  expect_toBeNull(res.error)
}

function yts_docs(c: YtsCase) -> Document[] {
  parseAllDocuments(c.yaml, Options { resolveKnownTags: false }).docs
}

/// test('errors')
function yts_errors(id: string, idx: int) -> null {
  let c = yts_load(id, idx);
  let docs = yts_docs(c);
  let errors: YAMLError[] = [];
  for (let doc in docs) {
    for (let e in doc.errors) {
      errors.push(e);
    }
  }
  if (c.fail) {
    expect_true(errors.length() != 0, "expected errors")
  } else {
    if (errors.length() != 0) {
      fail("expected no errors, got: " + errors.map((e: YAMLError) -> string { e.code + " " + e.message }).join("; "));
    }
    null
  }
}

/// test('in.json')
function yts_in_json(id: string, idx: int) -> null {
  let c = yts_load(id, idx);
  yts_testJsonMatch(yts_docs(c), c.json ?? "")
}

/// test('stringfy+re-parse')
function yts_reparse(id: string, idx: int) -> null {
  let c = yts_load(id, idx);
  let docs = yts_docs(c);
  let src2 = docs.map((doc: Document) -> string { doc.toString(null) }).join("");
  let docs2 = parseAllDocuments(src2, Options { resolveKnownTags: false }).docs;
  yts_testJsonMatch(docs2, c.json ?? "")
}

/// test('out.yaml')
function yts_out_yaml(id: string, idx: int) -> null {
  let c = yts_load(id, idx);
  let resDocs = parseAllDocuments(c.yaml, null).docs;
  let resJson = resDocs.map((doc: Document) -> unknown { doc.toJS(Options { mapAsMap: true }) });
  let expDocs = parseAllDocuments(yts_unescape(c.emit ?? ""), null).docs;
  let expJson = expDocs.map((doc: Document) -> unknown { doc.toJS(Options { mapAsMap: true }) });
  expect_toEqual(resJson, expJson)
}
