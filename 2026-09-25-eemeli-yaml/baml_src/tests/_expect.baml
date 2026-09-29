// Test support: a small vitest-style `expect` library for the ported tests.
//
// Not a port of an upstream file (upstream uses vitest). Values are compared
// with JS semantics: numbers compare by value across int/float, `null` stands
// for both `null` and `undefined`, maps/arrays/Map/Set compare structurally.
// Class instances (nodes, pairs, tokens, …) are inspected via reflection, so
// `toMatchObject`-style partial matching works on them as it does on JS
// objects.

class ExpectationFailed {
  message: string
}

function fail(message: string) -> never {
  throw ExpectationFailed { message: message }
}

// ─── Dynamic property access ───────────────────────────────────────────────

/// Whether `v` is a class instance (reflect.AnyClass), and not one of the
/// JS-builtin emulations that have their own comparison rules.
function t_is_class_instance(v: unknown) -> bool {
  match (v) {
    reflect.AnyClass => true,
    _ => false,
  }
}

function t_class_name(v: unknown) -> string {
  match (v) {
    // Strip generic arguments: a `JsMap<Pair>` reports "JsMap<Pair>".
    let c: reflect.AnyClass => c.name().split("<")[0],
    _ => "",
  }
}

/// `obj[name]` for class instances (reflected fields plus the "virtual"
/// JS properties that the port models as methods), plain objects and arrays.
function t_prop(obj: unknown, name: string) -> unknown {
  match (obj) {
    let s: YAMLSeq => {
      if (name == "length" || name == "size") {
        return s.items.length();
      }
      let idx = baml.Int.parse(name) catch (e) { _ => -1 };
      if (idx >= 0) {
        return s.items.at(idx);
      }
    },
    let m: YAMLMap => {
      if (name == "size") {
        return m.size();
      }
      if (name == "items") {
        return m.values.values();
      }
    },
    let st: YAMLSet => {
      if (name == "size") {
        return st.size();
      }
    },
    let s: string => {
      if (name == "length") {
        return s.length();
      }
    },
    let m: JsMap<unknown> => {
      if (name == "size") {
        return m.size();
      }
    },
    _ => {},
  }
  match (obj) {
    let c: reflect.AnyClass => {
      if (c.has_field(name)) {
        return c.get<unknown>(name) catch (e) { _ => null };
      }
      null
    },
    _ => {
      let o = js_as_object(obj);
      if (o != null) {
        return o.get(name);
      }
      let a = js_as_array(obj);
      if (a != null) {
        if (name == "length") {
          return a.length();
        }
        let idx = baml.Int.parse(name) catch (e) { _ => -1 };
        if (idx >= 0) {
          return a.at(idx);
        }
      }
      null
    },
  }
}

/// `name in obj` / `toHaveProperty(name)` (for non-null values)
function t_has_prop(obj: unknown, name: string) -> bool {
  match (obj) {
    let c: reflect.AnyClass => c.has_field(name) && t_prop(obj, name) != null,
    _ => {
      let o = js_as_object(obj);
      if (o != null) {
        return o.has(name);
      }
      false
    },
  }
}

/// Array-like view: arrays, YAMLSeq items, Set values, uint8array bytes.
function t_arrayish(v: unknown) -> unknown[]? {
  match (v) {
    let s: YAMLSeq => {
      let out: unknown[] = [];
      for (let it in s.items) {
        out.push(it);
      }
      out
    },
    let u: uint8array => {
      let out: unknown[] = [];
      for (let b in u.to_array()) {
        out.push(b);
      }
      out
    },
    _ => js_as_array(v),
  }
}

/// A JsMap<V> of any V as parallel key/value arrays (via reflection).
function t_jsmap_entries(v: unknown) -> JsEntries? {
  if (!t_class_name(v).starts_with("JsMap")) {
    return null;
  }
  let keys = js_as_array(t_prop(v, "_keys")) ?? [];
  let vals = js_as_array(t_prop(v, "_vals")) ?? [];
  JsEntries { keys: keys, values: vals }
}

// ─── Equality ──────────────────────────────────────────────────────────────

/// `Object.is`-like primitive equality with JS number semantics.
function t_prim_eq(a: unknown, b: unknown) -> bool {
  let fa = js_to_float(a);
  let fb = js_to_float(b);
  if (fa != null && fb != null) {
    let x: float = fa;
    let y: float = fb;
    return (x.is_nan() && y.is_nan()) || x == y;
  }
  a == b
}

function t_is_primitive(v: unknown) -> bool {
  match (v) {
    null => true,
    bool => true,
    int => true,
    float => true,
    bigint => true,
    string => true,
    _ => false,
  }
}

/// `expect(a).toEqual(b)`: recursive structural equality.
function t_equal(a: unknown, b: unknown) -> bool {
  t_equal_rec(a, b, TEqSeen { a: [], b: [] })
}

/// Pairs of objects currently being compared (for circular structures).
class TEqSeen {
  a: unknown[]
  b: unknown[]
}

function t_equal_rec(a: unknown, b: unknown, seen: TEqSeen) -> bool {
  if (t_is_primitive(a) || t_is_primitive(b)) {
    return t_prim_eq(a, b);
  }
  // Identical objects are equal.
  if (js_identical(a, b)) {
    return true;
  }
  // A pair already under comparison further up is assumed equal (cycles).
  let si = 0;
  while (si < seen.a.length()) {
    if (js_identical(seen.a[si], a) && js_identical(seen.b[si], b)) {
      return true;
    }
    si += 1;
  }
  seen.a.push(a);
  seen.b.push(b);
  let r = t_equal_body(a, b, seen);
  seen.a.pop();
  seen.b.pop();
  r
}

function t_equal_body(a: unknown, b: unknown, seen: TEqSeen) -> bool {
  let aa = t_arrayish(a);
  let ba = t_arrayish(b);
  if (aa != null || ba != null) {
    if (aa == null || ba == null) {
      return false;
    }
    let xa: unknown[] = aa ?? [];
    let xb: unknown[] = ba ?? [];
    if (xa.length() != xb.length()) {
      return false;
    }
    let i = 0;
    while (i < xa.length()) {
      if (!t_equal_rec(xa[i], xb[i], seen)) {
        return false;
      }
      i += 1;
    }
    return true;
  }
  let ma = t_jsmap_entries(a);
  let mb = t_jsmap_entries(b);
  if (ma != null || mb != null) {
    if (ma == null || mb == null) {
      return false;
    }
    let ea: JsEntries = ma ?? JsEntries { keys: [], values: [] };
    let eb: JsEntries = mb ?? JsEntries { keys: [], values: [] };
    if (ea.keys.length() != eb.keys.length()) {
      return false;
    }
    let i = 0;
    while (i < ea.keys.length()) {
      let found = false;
      let j = 0;
      while (j < eb.keys.length()) {
        if (t_equal_rec(ea.keys[i], eb.keys[j], seen) && t_equal_rec(ea.values[i], eb.values[j], seen)) {
          found = true;
          break;
        }
        j += 1;
      }
      if (!found) {
        return false;
      }
      i += 1;
    }
    return true;
  }
  match (a) {
    let sa: JsSet => match (b) {
      let sb: JsSet => {
        let va = sa.values();
        let vb = sb.values();
        va.length() == vb.length() && va.every((x: unknown) -> bool { vb.some((y: unknown) -> bool { t_equal_rec(x, y, seen) }) })
      },
      _ => false,
    },
    let da: JsDate => match (b) {
      let db: JsDate => da.time == db.time,
      _ => false,
    },
    let sa: JsSymbol => match (b) {
      let sb: JsSymbol => sa.description == sb.description,
      _ => false,
    },
    _ => {
      let oa = js_as_object(a);
      let ob = js_as_object(b);
      if (oa != null && ob != null) {
        let xa: map<string, unknown> = oa ?? {};
        let xb: map<string, unknown> = ob ?? {};
        let ka = xa.keys().filter((k: string) -> bool { xa[k] != null });
        let kb = xb.keys().filter((k: string) -> bool { xb[k] != null });
        if (ka.length() != kb.length()) {
          return false;
        }
        for (let k in ka) {
          if (!t_equal_rec(xa[k], xb.get(k), seen)) {
            return false;
          }
        }
        return true;
      }
      if (t_is_class_instance(a) && t_is_class_instance(b)) {
        if (t_class_name(a) != t_class_name(b)) {
          return false;
        }
        let fields: string[] = match (a) {
          let c: reflect.AnyClass => c.list_fields().map((f: reflect.class.Field) -> string { f.name }),
          _ => [],
        };
        for (let f in fields) {
          if (f == "_id" || f == "schema" || f == "srcToken" || f == "_index") {
            continue;
          }
          if (!t_equal_rec(t_prop(a, f), t_prop(b, f), seen)) {
            return false;
          }
        }
        return true;
      }
      a == b
    },
  }
}

/// `expect(actual).toMatchObject(expected)`: `expected` is a (possibly
/// partial) description of `actual`.
function t_match(actual: unknown, expected: unknown) -> bool {
  t_match_rec(actual, expected, TEqSeen { a: [], b: [] })
}

/// `t_match` with the (actual, expected) pairs currently being matched, so
/// that circular structures terminate (as vitest's subset equality does).
function t_match_rec(actual: unknown, expected: unknown, seen: TEqSeen) -> bool {
  if (t_is_primitive(expected)) {
    return t_prim_eq(actual, expected);
  }
  let si = 0;
  while (si < seen.a.length()) {
    if (js_identical(seen.a[si], actual) && js_identical(seen.b[si], expected)) {
      return true;
    }
    si += 1;
  }
  seen.a.push(actual);
  seen.b.push(expected);
  let r = t_match_body(actual, expected, seen);
  seen.a.pop();
  seen.b.pop();
  r
}

function t_match_body(actual: unknown, expected: unknown, seen: TEqSeen) -> bool {
  if (t_is_primitive(expected)) {
    return t_prim_eq(actual, expected);
  }
  let ea = t_arrayish(expected);
  if (ea != null) {
    let aa = t_arrayish(actual);
    if (aa == null) {
      return false;
    }
    let xa: unknown[] = aa ?? [];
    let xe: unknown[] = ea ?? [];
    if (xa.length() != xe.length()) {
      return false;
    }
    let i = 0;
    while (i < xe.length()) {
      if (!t_match_rec(xa[i], xe[i], seen)) {
        return false;
      }
      i += 1;
    }
    return true;
  }
  let me = t_jsmap_entries(expected);
  if (me != null) {
    // Maps are compared with equality semantics, but values may be partial.
    let ma = t_jsmap_entries(actual);
    if (ma == null) {
      return false;
    }
    let ee: JsEntries = me ?? JsEntries { keys: [], values: [] };
    let aa: JsEntries = ma ?? JsEntries { keys: [], values: [] };
    if (ee.keys.length() != aa.keys.length()) {
      return false;
    }
    let i = 0;
    while (i < ee.keys.length()) {
      let found = false;
      let j = 0;
      while (j < aa.keys.length()) {
        // vitest compares Map keys with the same (subset) testers as values,
        // so `_map([[_seq(), 'x']])` matches a YAMLSeq key.
        let km = t_equal(aa.keys[j], ee.keys[i]) || (!t_is_primitive(ee.keys[i]) && t_match_rec(aa.keys[j], ee.keys[i], seen));
        if (km && t_match_rec(aa.values[j], ee.values[i], seen)) {
          found = true;
          break;
        }
        j += 1;
      }
      if (!found) {
        return false;
      }
      i += 1;
    }
    return true;
  }
  match (expected) {
    JsSet => t_equal(actual, expected),
    JsDate => t_equal(actual, expected),
    JsSymbol => t_equal(actual, expected),
    _ => {
      let oe = js_as_object(expected);
      if (oe != null) {
        // vitest: an empty expected object matches any value (even null).
        if (oe.keys().length() == 0) {
          return true;
        }
        if (t_is_primitive(actual)) {
          return false;
        }
        for (let k in oe.keys()) {
          let ev = oe[k];
          let av = t_prop(actual, k);
          if (!t_match_rec(av, ev, seen)) {
            return false;
          }
        }
        return true;
      }
      if (t_is_class_instance(expected)) {
        // Like Jest: only the expected instance's own (non-undefined)
        // properties are compared, recursively with subset semantics.
        if (t_class_name(actual) != t_class_name(expected)) {
          return false;
        }
        let fields: string[] = match (expected) {
          let c: reflect.AnyClass => c.list_fields().map((f: reflect.class.Field) -> string { f.name }),
          _ => [],
        };
        for (let f in fields) {
          if (f == "_id" || f == "schema" || f == "srcToken" || f == "_index") {
            continue;
          }
          let ev = t_prop(expected, f);
          if (ev == null) {
            continue;
          }
          if (!t_match_rec(t_prop(actual, f), ev, seen)) {
            return false;
          }
        }
        return true;
      }
      actual == expected
    },
  }
}

// ─── Rendering (for failure messages) ──────────────────────────────────────

function t_show(v: unknown) -> string {
  match (v) {
    let s: string => json_quote(s),
    let n: Scalar => "Scalar(" + t_show(n.value) + ")",
    let a: Alias => "Alias(*" + a.source + ")",
    let p: Pair => "Pair(" + t_show(p.key) + ": " + t_show(p.value) + ")",
    let m: YAMLMap => "YAMLMap{" + m.values.values().map((p: Pair) -> string { t_show(p.key) + ": " + t_show(p.value) }).join(", ") + "}",
    let s: YAMLSeq => "YAMLSeq[" + s.items.map((it: SeqItem) -> string { t_show(it) }).join(", ") + "]",
    let s: YAMLSet => "YAMLSet{" + s.values.values().map((it: Node) -> string { t_show(it) }).join(", ") + "}",
    let e: JsError => e.name + ": " + e.message,
    let e: YAMLError => e.name + "(" + e.code + "): " + e.message,
    let t: Token => "Token(" + t.type + ", " + json_quote(t.source ?? "") + ")",
    _ => {
      let me = t_jsmap_entries(v);
      if (me != null) {
        let parts: string[] = [];
        let i = 0;
        while (i < me.keys.length()) {
          parts.push(t_show(me.keys[i]) + " => " + t_show(me.values[i]));
          i += 1;
        }
        return "Map{" + parts.join(", ") + "}";
      }
      match (v) {
        let st: JsSet => "Set{" + st.values().map((x: unknown) -> string { t_show(x) }).join(", ") + "}",
        _ => {
          let arr = t_arrayish(v);
          if (arr != null) {
            return "[" + arr.map((x: unknown) -> string { t_show(x) }).join(", ") + "]";
          }
          let o0 = js_as_object(v);
          if (o0 != null) {
            let o: map<string, unknown> = o0;
            return "{" + o.keys().map((k: string) -> string { k + ": " + t_show(o[k]) }).join(", ") + "}";
          }
          if (t_is_class_instance(v)) {
            return t_class_name(v) + "{…}";
          }
          js_string(v)
        },
      }
    },
  }
}

// ─── Matchers ──────────────────────────────────────────────────────────────

/// `expect(actual).toBe(expected)` for primitives (identity for objects)
function expect_toBe(actual: unknown, expected: unknown) -> null {
  let ok = if (t_is_primitive(expected) || t_is_primitive(actual)) {
    t_prim_eq(actual, expected)
  } else {
    js_identical(actual, expected)
  };
  if (!ok) {
    fail("expected " + t_show(actual) + " to be " + t_show(expected));
  }
  null
}

function expect_not_toBe(actual: unknown, expected: unknown) -> null {
  let same = if (t_is_primitive(expected) || t_is_primitive(actual)) {
    t_prim_eq(actual, expected)
  } else {
    js_identical(actual, expected)
  };
  if (same) {
    fail("expected " + t_show(actual) + " not to be " + t_show(expected));
  }
  null
}

function expect_toEqual(actual: unknown, expected: unknown) -> null {
  if (!t_equal(actual, expected)) {
    fail("expected " + t_show(actual) + " to equal " + t_show(expected));
  }
  null
}

function expect_toMatchObject(actual: unknown, expected: unknown) -> null {
  if (!t_match(actual, expected)) {
    fail("expected " + t_show(actual) + " to match " + t_show(expected));
  }
  null
}

function expect_toHaveLength(actual: unknown, n: int) -> null {
  let len = t_prop(actual, "length");
  if (!t_prim_eq(len, n)) {
    fail("expected length " + js_string(len) + " to be " + n.to_string() + " for " + t_show(actual));
  }
  null
}

function expect_toBeNull(actual: unknown) -> null {
  if (actual != null) {
    fail("expected " + t_show(actual) + " to be null/undefined");
  }
  null
}

function expect_not_toBeNull(actual: unknown) -> null {
  if (actual == null) {
    fail("expected value not to be null/undefined");
  }
  null
}

function expect_true(cond: bool, message: string) -> null {
  if (!cond) {
    fail(message);
  }
  null
}

/// `expect(str).toMatch(/re/)`
function expect_toMatch(actual: unknown, pattern: string) -> null {
  let s = js_string(actual);
  if (!re(pattern).has_match(s)) {
    fail("expected " + json_quote(s) + " to match /" + pattern + "/");
  }
  null
}

/// `expect(obj).toHaveProperty(name)`
function expect_toHaveProperty(actual: unknown, name: string) -> null {
  if (!t_has_prop(actual, name)) {
    fail("expected " + t_show(actual) + " to have property " + name);
  }
  null
}

function expect_not_toHaveProperty(actual: unknown, name: string) -> null {
  if (t_has_prop(actual, name)) {
    fail("expected " + t_show(actual) + " not to have property " + name);
  }
  null
}

/// `expect(x).toBeInstanceOf(Class)`, by class name.
function expect_toBeInstanceOf(actual: unknown, className: string) -> null {
  let name = match (actual) {
    let s: YAMLSeq => if (s._class == "YAMLOMap" && className == "YAMLOMap") { "YAMLOMap" } else { "YAMLSeq" },
    let s: Scalar => if (s._class == "MergeKey" && className == "MergeKey") { "MergeKey" } else { "Scalar" },
    let e: YAMLError => if (className == "YAMLError") { "YAMLError" } else { e.name },
    let e: JsError => if (className == "Error") { "Error" } else { e.name },
    JsSet => "Set",
    JsDate => "Date",
    uint8array => "Uint8Array",
    _ => {
      if (t_class_name(actual).starts_with("JsMap")) {
        "Map"
      } else if (js_is_array(actual)) {
        "Array"
      } else if (js_is_plain_object(actual)) {
        "Object"
      } else {
        t_class_name(actual)
      }
    },
  };
  if (name != className && !(className == "Array" && name == "YAMLSeq")) {
    fail("expected " + t_show(actual) + " to be an instance of " + className + " (got " + name + ")");
  }
  null
}

/// The message of any thrown value.
function t_error_message(e: unknown) -> string {
  match (e) {
    let j: JsError => j.message,
    let y: YAMLError => y.message,
    let x: ExpectationFailed => x.message,
    let s: string => s,
    _ => {
      let m = t_prop(e, "message");
      match (m) {
        let s: string => s,
        _ => js_string(e),
      }
    },
  }
}

/// `expect(fn).toThrow(msg?)`: `msg` must be a substring of the message.
/// Returns the thrown value.
function expect_toThrow(fn: () -> unknown throws unknown, msg: string?) -> unknown {
  let threw = true;
  let err: unknown = null;
  fn() catch_all (e) {
    _ => {
      err = e;
      null
    },
  };
  if (err == null) {
    threw = false;
  }
  if (!threw) {
    fail("expected function to throw" + (if (msg != null) { " " + json_quote(msg ?? "") } else { "" }));
  }
  if (msg != null) {
    let m = t_error_message(err);
    if (!m.includes(msg ?? "")) {
      fail("expected thrown message " + json_quote(m) + " to include " + json_quote(msg ?? ""));
    }
  }
  err
}

/// `expect(fn).toThrow(ErrorClass)`: checks the error's `name`.
function expect_toThrowNamed(fn: () -> unknown throws unknown, name: string) -> unknown {
  let err = expect_toThrow(fn, null);
  let n = match (err) {
    let j: JsError => j.name,
    let y: YAMLError => y.name,
    _ => t_class_name(err),
  };
  if (n != name && !(name == "Error" || name == "YAMLError")) {
    fail("expected thrown error to be a " + name + ", got " + n);
  }
  err
}

function expect_not_toThrow(fn: () -> unknown throws unknown) -> unknown {
  fn() catch_all (e) {
    _ => {
      fail("expected function not to throw, but it threw " + json_quote(t_error_message(e)));
    },
  }
}

// ─── Mocks (vi.fn / vi.spyOn replacements) ─────────────────────────────────

/// Records the arguments of each call.
class MockCalls {
  calls: unknown[][]

  function record(self, args: unknown[]) -> null {
    self.calls.push(args);
    null
  }

  function count(self) -> int {
    self.calls.length()
  }
}

function mock_calls() -> MockCalls {
  MockCalls { calls: [] }
}
