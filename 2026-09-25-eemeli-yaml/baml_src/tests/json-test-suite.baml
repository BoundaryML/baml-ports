// Port of tests/json-test-suite.ts
//
// Upstream enumerates tests/json-test-suite/{test_parsing,test_transform}/*.json
// at runtime and generates one vitest test per file. BAML test blocks are
// static, so `tools/gen_json_test_suite.py` generates
// `json-test-suite.generated.baml` with one test per file (same names, same
// skip list, same order); each test calls one of the checkers below, which
// read the file at test time and run upstream's assertions.

/// `readFileSync(path, 'utf8')`: Node decodes invalid UTF-8 lossily (U+FFFD),
/// whereas `baml.fs.read` throws on it (28 of the files are not valid UTF-8),
/// so read raw bytes and decode lossily via `uint8array.to_string()`.
function tjts_read(rel: string) -> string {
  let path = tests_root() + "/json-test-suite/" + rel;
  let f = baml.fs.open(path, "r") catch (e) {
    _ => baml.sys.panic("cannot open " + path),
  };
  let bytes = f.bytes() catch (e) {
    _ => baml.sys.panic("cannot read " + path),
  };
  bytes.to_string()
}

/// `test.skip(name, () => {})` -- skipped upstream too.
function tjts_skipped(reason: string) -> null {
  null
}

/// testReject: if the document parses without errors, stringify + re-parse
/// must round-trip to the same JSON.
function tjts_testReject(rel: string) -> null {
  let src = tjts_read(rel);
  let doc = parseDocument(src, null);
  if (doc.errors.length() == 0) {
    let res = doc.toJS(null);
    let doc2 = parseDocument(doc.toString(null), null);
    let res2 = doc2.toJS(null);
    expect_toBe(json_stringify(res2), json_stringify(res));
  }
  null
}

/// testSuccess: no errors/warnings, and stringify + re-parse round-trips.
function tjts_testSuccess(rel: string) -> null {
  let src = tjts_read(rel);
  let doc = parseDocument(src, null);
  expect_toHaveLength(doc.errors, 0);
  expect_toHaveLength(doc.warnings, 0);
  let res = doc.toJS(null);

  let doc2 = parseDocument(doc.toString(null), null);
  expect_toHaveLength(doc2.errors, 0);
  expect_toHaveLength(doc2.warnings, 0);
  let res2 = doc2.toJS(null);

  expect_toBe(json_stringify(res2), json_stringify(res))
}
