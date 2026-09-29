// Port of tests/_utils.ts

/// Trim leading whitespace from each line.
///
/// (The original is a template-literal tag; BAML backtick strings already
/// interpolate, so this takes the finished string.)
function source(str: string) -> string {
  // remove trailing whitespace + initial newline
  let res = str.replace_all(re("(?m)[^\\S\\n]+$"), "").replace(re("^\\n"), "");

  // remove the shortest leading indentation from each line
  let matches = re("(?m)^[^\\S\\n]*(?=\\S)").match_all(res);
  if (matches.length() == 0) {
    return res;
  }
  let indent = matches.map((m: baml.regex.Match) -> int { m.text.length() }).reduce((a: int, b: int) -> int { if (a < b) { a } else { b } }, 1000000);
  if (indent != 0) {
    res.replace_all(re("(?m)^.{" + indent.to_string() + "}"), "")
  } else {
    res
  }
}

/// Test shorthand for `expect(YAMLMap).toMatchObject()`
function _map(input: unknown, props: map<string, unknown>?) -> map<string, unknown> {
  let entries = js_as_array(input);
  let values = js_map();
  if (entries != null) {
    for (let e in entries) {
      let kv = js_as_array(e) ?? [];
      values.set(kv[0], _pair(kv[0], kv[1]));
    }
  } else {
    let o = js_as_object(input) ?? {};
    for (let k in o.keys()) {
      values.set(k, _pair(k, o[k]));
    }
  }
  let res: map<string, unknown> = { "values": values };
  if (props != null) {
    for (let k in props.keys()) {
      res.set(k, props[k]);
    }
  }
  res
}

/// Test shorthand for `expect(Pair).toMatchObject()`
function _pair(key: unknown, value: unknown) -> unknown {
  let o = js_as_object(value);
  if (o?.has("key") == true && o?.has("value") == true) {
    return value;
  }
  let res: map<string, unknown> = { "key": _node(key), "value": _node(value) };
  res
}

/// Test shorthand for `expect(YAMLSeq).toMatchObject()`
function _seq(inputs: unknown[]) -> unknown[] {
  inputs.map((i: unknown) -> unknown { _node(i) })
}

/// Test shorthand for `expect(YAMLSet).toMatchObject()`
function _set(input: unknown[], props: map<string, unknown>?) -> map<string, unknown> {
  let values = js_map();
  for (let e in input) {
    let kv = js_as_array(e);
    if (kv != null) {
      values.set(kv[0], _node(kv[1]));
    } else {
      values.set(e, _node(e));
    }
  }
  let res: map<string, unknown> = { "values": values };
  if (props != null) {
    for (let k in props.keys()) {
      res.set(k, props[k]);
    }
  }
  res
}

function _node(value: unknown) -> unknown {
  match (value) {
    bigint => {
      let r: map<string, unknown> = { "value": value };
      r
    },
    bool => {
      let r: map<string, unknown> = { "value": value };
      r
    },
    int => {
      let r: map<string, unknown> = { "value": value };
      r
    },
    float => {
      let r: map<string, unknown> = { "value": value };
      r
    },
    string => {
      let r: map<string, unknown> = { "value": value };
      r
    },
    _ => value,
  }
}

/// `readFile(resolve(__dirname, 'artifacts', path), 'utf8')`
function readArtifact(path: string) -> string {
  baml.fs.read(tests_root() + "/artifacts/" + path) catch (e) {
    _ => baml.sys.panic("cannot read artifact " + path),
  }
}

/// Absolute path of the upstream `tests/` directory (test data lives there).
function tests_root() -> string {
  "/Users/sam/work-repos/yaml-baml-port-src/tests"
}
