// JS runtime shim.
//
// Not a port of any single upstream file: eemeli/yaml leans on JavaScript
// built-ins (Error classes, Map/Set with arbitrary keys, Symbol, String(),
// JSON.stringify, Number formatting, object identity). BAML has none of these
// directly, so they are emulated here and used throughout the port.

// ─── Errors ─────────────────────────────────────────────────────────────────

/// Stand-in for JS `Error` and its subclasses (`TypeError`, `RangeError`,
/// `ReferenceError`, `SyntaxError`). `name` holds the constructor name.
class JsError {
  name: string
  message: string
  /// Extra properties attached with `Object.assign(new Error(), {...})`.
  extra: unknown?
}

function js_error(message: string) -> JsError {
  JsError { name: "Error", message: message }
}

function js_type_error(message: string) -> JsError {
  JsError { name: "TypeError", message: message }
}

function js_range_error(message: string) -> JsError {
  JsError { name: "RangeError", message: message }
}

function js_reference_error(message: string) -> JsError {
  JsError { name: "ReferenceError", message: message }
}

// ─── Object identity ────────────────────────────────────────────────────────

/// BAML `==` is structural and there is no reference-identity operator, so
/// every class whose identity matters in the original (nodes, pairs, tokens…)
/// carries an `_id` drawn from here. `a === b` becomes `a._id == b._id`.
function new_id() -> int {
  baml.random.SystemRandom.get().random_int()
}

// ─── Symbol ─────────────────────────────────────────────────────────────────

class JsSymbol {
  _id: int
  description: string
}

function js_symbol(description: string) -> JsSymbol {
  JsSymbol { _id: new_id(), description: description }
}

// ─── Raw JSON ───────────────────────────────────────────────────────────────

/// `JSON.rawJSON(text)`: an object whose `rawJSON` text is emitted verbatim
/// when stringified. (JS validates that `text` is a JSON primitive and throws
/// a SyntaxError otherwise; that validation is not modelled.)
class JsRawJSON {
  _id: int
  rawJSON: string
}

function js_raw_json(text: string) -> JsRawJSON {
  JsRawJSON { _id: new_id(), rawJSON: text }
}

/// `JSON.isRawJSON(value)`
function js_is_raw_json(value: unknown) -> bool {
  match (value) {
    JsRawJSON => true,
    _ => false,
  }
}

// ─── Dynamic views over `unknown` ───────────────────────────────────────────

/// `Array.isArray(v)` + a typed view: BAML generics are invariant, so an
/// `int[]` never matches `unknown[]` in a `match`. Reflect the element type
/// and re-bind it to copy into an `unknown[]`.
function js_as_array(v: unknown) -> unknown[]? {
  match (v) {
    let a: unknown[] => a,
    _ => {
      let t = reflect.Type.of_value(v).as_array();
      if (t == null) {
        return null;
      }
      type E = unreflect(t.element_type());
      match (v) {
        let a: E[] => {
          let out: unknown[] = [];
          for (let x in a) {
            out.push(x);
          }
          out
        },
        _ => null,
      }
    },
  }
}

/// A plain JS object (`{}`) is modelled as a `map<string, unknown>`.
function js_as_object(v: unknown) -> map<string, unknown>? {
  match (v) {
    let m: map<string, unknown> => m,
    _ => {
      let t = reflect.Type.of_value(v).as_map();
      if (t == null) {
        return null;
      }
      type V = unreflect(t.value_type());
      match (v) {
        let m: map<string, V> => {
          let out: map<string, unknown> = {};
          for (let k in m.keys()) {
            out.set(k, m[k]);
          }
          out
        },
        _ => null,
      }
    },
  }
}

function js_is_array(v: unknown) -> bool {
  match (v) {
    let a: unknown[] => true,
    _ => reflect.Type.of_value(v).as_array() != null,
  }
}

function js_is_plain_object(v: unknown) -> bool {
  match (v) {
    let m: map<string, unknown> => true,
    _ => reflect.Type.of_value(v).as_map() != null,
  }
}

/// JS `typeof`. BAML ints and floats are both `"number"`. Any class instance,
/// array or map is `"object"`, as is `null`.
function js_typeof(v: unknown) -> string {
  match (v) {
    null => "object",
    bool => "boolean",
    int => "number",
    float => "number",
    bigint => "bigint",
    string => "string",
    JsSymbol => "symbol",
    _ => "object",
  }
}

/// JS truthiness (`!!v`). BAML truthiness differs: empty arrays and maps are
/// falsy in BAML but truthy in JS.
function js_truthy(v: unknown) -> bool {
  match (v) {
    null => false,
    let b: bool => b,
    let i: int => i != 0,
    let f: float => !(f == 0.0 || f.is_nan()),
    let b: bigint => b != 0n,
    let s: string => s != "",
    _ => true,
  }
}

// ─── Map / Set with arbitrary keys ──────────────────────────────────────────

/// Key used to index a JS `Map`/`Set` by SameValueZero. Primitives get a
/// stable string; objects with an `_id` are keyed by identity. Anything else
/// (arrays, plain maps) is compared structurally by linear scan.
function js_key(k: unknown) -> string? {
  match (k) {
    null => "null",
    let b: bool => if (b) { "b:true" } else { "b:false" },
    let i: int => "n:" + js_number_to_string(i * 1.0),
    let f: float => "n:" + js_number_to_string(f),
    let b: bigint => "g:" + b.to_string(),
    let s: string => "s:" + s,
    let x: JsSymbol => "y:" + x._id.to_string(),
    _ => {
      let id = js_object_id(k);
      if (id == null) {
        null
      } else {
        "o:" + id.to_string()
      }
    },
  }
}

/// Registry of `_id`-carrying classes. Returns null for other values.
function js_object_id(k: unknown) -> int? {
  match (k) {
    let n: Scalar => n._id,
    let n: YAMLMap => n._id,
    let n: YAMLSeq => n._id,
    let n: YAMLSet => n._id,
    let n: Alias => n._id,
    let n: Pair => n._id,
    let n: Document => n._id,
    let n: JsMap<unknown> => n._id,
    let n: JsSet => n._id,
    let n: JsDate => n._id,
    let n: Token => n._id,
    let n: CollectionItem => n._id,
    _ => null,
  }
}

/// `a === b` for arbitrary values.
function js_same(a: unknown, b: unknown) -> bool {
  let ia = js_object_id(a);
  if (ia != null) {
    let ib = js_object_id(b);
    return ib != null && ia == ib;
  }
  match (a) {
    let x: int => match (b) {
      let y: int => x == y,
      let y: float => x * 1.0 == y,
      _ => false,
    },
    let x: float => match (b) {
      let y: int => x == y * 1.0,
      let y: float => x == y,
      _ => false,
    },
    _ => a == b,
  }
}

/// JS `Map`: insertion ordered, arbitrary keys (SameValueZero-ish: see
/// `js_key`). Generic over the value type so that internal maps
/// (e.g. `YAMLMap.values: Map<unknown, Pair>`) stay typed.
class JsMap<V> {
  _id: int
  _keys: unknown[]
  _vals: V[]
  _index: map<string, int>

  function size(self) -> int {
    self._keys.length()
  }

  function _find(self, k: unknown) -> int? {
    let key = js_key(k);
    if (key != null) {
      return self._index.get(key);
    }
    let i = 0;
    while (i < self._keys.length()) {
      if (js_same(self._keys[i], k) || self._keys[i] == k) {
        return i;
      }
      i += 1;
    }
    null
  }

  function has(self, k: unknown) -> bool {
    self._find(k) != null
  }

  function get(self, k: unknown) -> V? {
    let i = self._find(k);
    if (i == null) {
      null
    } else {
      self._vals[i]
    }
  }

  function set(self, k: unknown, v: V) -> JsMap<V> {
    let i = self._find(k);
    if (i != null) {
      self._vals[i] = v;
    } else {
      let key = js_key(k);
      if (key != null) {
        self._index.set(key, self._keys.length());
      }
      self._keys.push(k);
      self._vals.push(v);
    }
    self
  }

  function delete(self, k: unknown) -> bool {
    let i = self._find(k);
    if (i == null) {
      return false;
    }
    self._keys.remove_at(i);
    self._vals.remove_at(i);
    self._reindex();
    true
  }

  function clear(self) -> null {
    self._keys = [];
    self._vals = [];
    self._index = {};
    null
  }

  function _reindex(self) -> null {
    let idx: map<string, int> = {};
    let i = 0;
    while (i < self._keys.length()) {
      let key = js_key(self._keys[i]);
      if (key != null) {
        idx.set(key, i);
      }
      i += 1;
    }
    self._index = idx;
    null
  }

  function keys(self) -> unknown[] {
    self._keys.slice(0, self._keys.length())
  }

  function values(self) -> V[] {
    self._vals.slice(0, self._vals.length())
  }
}

function js_map() -> JsMap<unknown> {
  js_map_new()
}

/// `new Map()` with a typed value.
function js_map_new<V>() -> JsMap<V> {
  let keys: unknown[] = [];
  let vals: V[] = [];
  let index: map<string, int> = {};
  JsMap { _id: new_id(), _keys: keys, _vals: vals, _index: index }
}

/// JS `Set`: insertion ordered, arbitrary values.
class JsSet {
  _id: int
  _map: JsMap<unknown>

  function size(self) -> int {
    self._map.size()
  }

  function has(self, v: unknown) -> bool {
    self._map.has(v)
  }

  function add(self, v: unknown) -> JsSet {
    self._map.set(v, v);
    self
  }

  function delete(self, v: unknown) -> bool {
    self._map.delete(v)
  }

  function values(self) -> unknown[] {
    self._map.keys()
  }
}

function js_set() -> JsSet {
  JsSet { _id: new_id(), _map: js_map() }
}

/// JS `Date` (only what `!!timestamp` needs): milliseconds since the epoch.
class JsDate {
  _id: int
  time: int

  /// `Date.prototype.toISOString()`
  function toISOString(self) -> string {
    let ms = self.time;
    let days = ms / 86400000;
    let rem = ms % 86400000;
    if (rem < 0) {
      rem += 86400000;
      days -= 1;
    }
    let ymd = civil_from_days(days);
    let h = rem / 3600000;
    let mi = (rem / 60000) % 60;
    let s = (rem / 1000) % 60;
    let msec = rem % 1000;
    let y = ymd[0];
    let ys = if (y >= 0 && y <= 9999) {
      pad_int(y, 4)
    } else if (y < 0) {
      "-" + pad_int(0 - y, 6)
    } else {
      "+" + pad_int(y, 6)
    };
    ys + "-" + pad_int(ymd[1], 2) + "-" + pad_int(ymd[2], 2) + "T" + pad_int(h, 2) + ":" + pad_int(mi, 2) + ":" + pad_int(s, 2) + "." + pad_int(msec, 3) + "Z"
  }
}

function js_date(time: int) -> JsDate {
  JsDate { _id: new_id(), time: time }
}

function pad_int(n: int, width: int) -> string {
  let s = n.to_string();
  while (s.length() < width) {
    s = "0" + s;
  }
  s
}

/// Days since 1970-01-01 for a proleptic Gregorian date (H. Hinnant).
function days_from_civil(y0: int, m: int, d: int) -> int {
  let y = if (m <= 2) { y0 - 1 } else { y0 };
  let era = if (y >= 0) { y / 400 } else { (y - 399) / 400 };
  let yoe = y - era * 400;
  let mp = if (m > 2) { m - 3 } else { m + 9 };
  let doy = (153 * mp + 2) / 5 + d - 1;
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  era * 146097 + doe - 719468
}

/// [year, month, day] for days since 1970-01-01 (H. Hinnant).
function civil_from_days(z0: int) -> int[] {
  let z = z0 + 719468;
  let era = if (z >= 0) { z / 146097 } else { (z - 146096) / 146097 };
  let doe = z - era * 146097;
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
  let y = yoe + era * 400;
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
  let mp = (5 * doy + 2) / 153;
  let d = doy - (153 * mp + 2) / 5 + 1;
  let m = if (mp < 10) { mp + 3 } else { mp - 9 };
  [if (m <= 2) { y + 1 } else { y }, m, d]
}

/// `Date.UTC(year, monthIndex, day, hour, minute, second, ms)` with JS
/// overflow semantics for month/day/time fields.
function js_date_utc(year: int, month0: int, day: int, hour: int, minute: int, second: int, ms: int) -> int {
  let y = year + month0 / 12;
  let m = month0 % 12;
  if (m < 0) {
    m += 12;
    y -= 1;
  }
  let days = days_from_civil(y, m + 1, 1) + day - 1;
  days * 86400000 + hour * 3600000 + minute * 60000 + second * 1000 + ms
}

// ─── Numbers ────────────────────────────────────────────────────────────────

/// JS `Number.prototype.toString()` for a float: shortest round-trip digits,
/// exponential notation outside [1e-7, 1e21), no trailing `.0`.
function js_number_to_string(f: float) -> string {
  if (f.is_nan()) {
    return "NaN";
  }
  if (f.is_infinite()) {
    return if (f > 0.0) { "Infinity" } else { "-Infinity" };
  }
  if (f == 0.0) {
    return "0";
  }
  let neg = f < 0.0;
  let s = f.abs().to_string();
  // BAML renders the shortest round-trip digits in positional notation
  // (e.g. "1000000000000000000000.0", "0.0000001"); recover digits + exponent.
  let int_part = s;
  let frac_part = "";
  let dot = s.index_of(".");
  if (dot != null) {
    int_part = s.slice(0, dot);
    frac_part = s.slice(dot + 1, s.length());
  }
  let e_pos = s.index_of("e");
  let digits = "";
  let exp = 0;
  if (e_pos != null) {
    // Fallback in case exponential rendering is used.
    let mant = s.slice(0, e_pos);
    exp = baml.Int.parse(s.slice(e_pos + 1, s.length())) catch (e) { _ => 0 };
    let md = mant.index_of(".");
    if (md != null) {
      digits = mant.slice(0, md) + mant.slice(md + 1, mant.length());
      exp = exp + md;
    } else {
      digits = mant;
      exp = exp + mant.length();
    }
  } else {
    digits = int_part + frac_part;
    exp = int_part.length();
  }
  // strip leading zeros (adjusting exponent) and trailing zeros
  let lead = 0;
  while (lead < digits.length() - 1 && digits.at(lead) == "0") {
    lead += 1;
  }
  digits = digits.slice(lead, digits.length());
  exp = exp - lead;
  let end = digits.length();
  while (end > 1 && digits.at(end - 1) == "0") {
    end -= 1;
  }
  digits = digits.slice(0, end);
  // Now value = 0.<digits> * 10^exp  ==  d1.d2d3… * 10^(exp-1)
  let k = digits.length();
  let n = exp;
  let res = "";
  if (k <= n && n <= 21) {
    res = digits + "0".repeat(n - k);
  } else if (0 < n && n <= 21) {
    res = digits.slice(0, n) + "." + digits.slice(n, k);
  } else if (-6 < n && n <= 0) {
    res = "0." + "0".repeat(0 - n) + digits;
  } else {
    let e = n - 1;
    let es = if (e >= 0) { "+" + e.to_string() } else { e.to_string() };
    if (k == 1) {
      res = digits + "e" + es;
    } else {
      res = digits.slice(0, 1) + "." + digits.slice(1, k) + "e" + es;
    }
  }
  if (neg) {
    "-" + res
  } else {
    res
  }
}

/// JS `String(v)`.
function js_string(v: unknown) -> string {
  match (v) {
    null => "null",
    let b: bool => if (b) { "true" } else { "false" },
    let i: int => i.to_string(),
    let f: float => js_number_to_string(f),
    let b: bigint => b.to_string(),
    let s: string => s,
    let x: JsSymbol => "Symbol(" + x.description + ")",
    let e: JsError => e.name + ": " + e.message,
    let n: Scalar => n.toString(null, null, null),
    let m: JsMap<unknown> => "[object Map]",
    let m: JsSet => "[object Set]",
    let d: JsDate => d.toISOString(),
    _ => {
      let arr = js_as_array(v);
      if (arr != null) {
        return arr.map((x: unknown) -> string {
          if (x == null) { "" } else { js_string(x) }
        }).join(",");
      }
      "[object Object]"
    },
  }
}

/// `Number.isInteger(v)`
function js_is_integer(v: unknown) -> bool {
  match (v) {
    int => true,
    let f: float => f.is_finite() && f.trunc() == f,
    _ => false,
  }
}

/// Numeric value of an int/float as float.
function js_to_float(v: unknown) -> float? {
  match (v) {
    let i: int => i * 1.0,
    let f: float => f,
    _ => null,
  }
}

// ─── Strings ────────────────────────────────────────────────────────────────

function hex_digit(n: int) -> string {
  "0123456789abcdef".at(n) ?? "0"
}

function to_hex(n: int, width: int) -> string {
  let s = "";
  let v = n;
  while (v > 0) {
    s = hex_digit(v % 16) + s;
    v = v / 16;
  }
  while (s.length() < width) {
    s = "0" + s;
  }
  s
}

/// `JSON.stringify(str)` for a string: quote and escape exactly as JS does.
function json_quote(s: string) -> string {
  let out: string[] = ["\""];
  for (let cp in s.to_code_points()) {
    if (cp == 34) {
      out.push("\\\"");
    } else if (cp == 92) {
      out.push("\\\\");
    } else if (cp == 8) {
      out.push("\\b");
    } else if (cp == 12) {
      out.push("\\f");
    } else if (cp == 10) {
      out.push("\\n");
    } else if (cp == 13) {
      out.push("\\r");
    } else if (cp == 9) {
      out.push("\\t");
    } else if (cp < 32 || (cp >= 0xd800 && cp <= 0xdfff)) {
      out.push("\\u" + to_hex(cp, 4));
    } else {
      out.push(baml.String.from_code_points([cp]) catch (e) { _ => "" });
    }
  }
  out.push("\"");
  out.join("")
}

/// `JSON.stringify(v)` for JSON-like values.
function json_stringify(v: unknown) -> string {
  match (v) {
    null => "null",
    let b: bool => if (b) { "true" } else { "false" },
    let i: int => i.to_string(),
    let f: float => if (f.is_finite()) { js_number_to_string(f) } else { "null" },
    let s: string => json_quote(s),
    let m: JsMap<unknown> => "{}",
    let m: JsSet => "{}",
    let d: JsDate => json_quote(d.toISOString()),
    _ => {
      let arr = js_as_array(v);
      if (arr != null) {
        return "[" + arr.map((x: unknown) -> string { json_stringify(x) }).join(",") + "]";
      }
      let obj = js_as_object(v);
      if (obj != null) {
        let parts: string[] = [];
        for (let k in obj.keys()) {
          parts.push(json_quote(k) + ":" + json_stringify(obj[k]));
        }
        return "{" + parts.join(",") + "}";
      }
      json_quote(js_string(v))
    },
  }
}

/// `JSON.stringify(v, null, space)` for JSON-like values, where `space` is
/// JS's numeric indent argument: clamped to 10, and anything below 1 (or NaN,
/// e.g. `Number(undefined)`) means no pretty-printing.
function json_stringify_indent(v: unknown, space: float) -> string {
  if (space.is_nan() || space < 1.0) {
    return json_stringify(v);
  }
  let n = space.ifloor() catch (e) { _ => 10 };
  let gap = " ".repeat(if (n > 10) { 10 } else { n });
  json_stringify_gap(v, gap, "")
}

/// `SerializeJSONProperty` with a non-empty `gap`.
function json_stringify_gap(v: unknown, gap: string, indent: string) -> string {
  match (v) {
    null => "null",
    let b: bool => json_stringify(b),
    let i: int => json_stringify(i),
    let f: float => json_stringify(f),
    let s: string => json_quote(s),
    let m: JsMap<unknown> => "{}",
    let m: JsSet => "{}",
    let d: JsDate => json_stringify(d),
    _ => {
      let inner = indent + gap;
      let arr = js_as_array(v);
      if (arr != null) {
        if (arr.length() == 0) {
          return "[]";
        }
        let parts = arr.map((x: unknown) -> string { json_stringify_gap(x, gap, inner) });
        return "[\n" + inner + parts.join(",\n" + inner) + "\n" + indent + "]";
      }
      let obj = js_as_object(v);
      if (obj != null) {
        let parts: string[] = [];
        for (let k in obj.keys()) {
          parts.push(json_quote(k) + ": " + json_stringify_gap(obj[k], gap, inner));
        }
        if (parts.length() == 0) {
          return "{}";
        }
        return "{\n" + inner + parts.join(",\n" + inner) + "\n" + indent + "}";
      }
      json_stringify(v)
    },
  }
}

/// A JS source string with O(1) character access. BAML's `string.at` and
/// `string.slice` are codepoint-indexed over UTF-8 and cost O(index), so
/// scanning code works over a pre-split character array instead.
class Src {
  s: string
  chars: string[]
  codes: int[]

  function len(self) -> int {
    self.codes.length()
  }

  /// `str[i]`, or null (JS `undefined`) when out of range.
  function ch(self, i: int) -> string? {
    if (i < 0 || i >= self.codes.length()) {
      null
    } else {
      self.chars[i]
    }
  }

  /// `str.charCodeAt(i)`, or -1 (JS `NaN`) when out of range.
  function code(self, i: int) -> int {
    if (i < 0 || i >= self.codes.length()) {
      -1
    } else {
      self.codes[i]
    }
  }

  /// `str.slice(a, b)` with JS clamping for non-negative arguments.
  function slice(self, a: int, b: int) -> string {
    let n = self.codes.length();
    let lo = if (a < 0) { 0 } else if (a > n) { n } else { a };
    let hi = if (b < 0) { 0 } else if (b > n) { n } else { b };
    if (hi <= lo) {
      ""
    } else {
      self.chars.slice(lo, hi).join("")
    }
  }

  /// `str.indexOf(search, from)` for a single-character search.
  function index_of_char(self, c: string, from: int) -> int {
    let i = if (from < 0) { 0 } else { from };
    let n = self.codes.length();
    while (i < n) {
      if (self.chars[i] == c) {
        return i;
      }
      i += 1;
    }
    -1
  }
}

function src(s: string) -> Src {
  Src { s: s, chars: s.chars(), codes: s.to_code_points() }
}

/// JS `str.indexOf(search, from)` returning -1 when absent.
function str_index_of(s: string, search: string, from: int) -> int {
  if (from <= 0) {
    return s.index_of(search) ?? -1;
  }
  let rest = s.slice(from, s.length());
  let i = rest.index_of(search);
  if (i == null) {
    -1
  } else {
    i + from
  }
}

/// JS `str[i]` returning "" (instead of undefined) when out of range.
function char_at(s: string, i: int) -> string {
  s.at(i) ?? ""
}

/// JS `str.substring(a)` / `str.slice(a)`.
function str_from(s: string, a: int) -> string {
  s.slice(a, s.length())
}

/// Compile a regex that is known-good at authoring time (panics otherwise).
/// Uses the backtracking engine, since the original patterns use lookaround.
function re(pattern: string) -> baml.regex.Regex {
  baml.regex.new(pattern, backtracking = true) catch (e) {
    _ => baml.sys.panic("bad regex: " + pattern),
  }
}

/// Reference identity for any value, including BAML maps and arrays, which
/// have no identity operator. Maps and arrays are mutable references, so
/// identity is detected by mutating `a` with a unique probe and checking
/// whether `b` observes it (then undoing the mutation).
function js_identical(a: unknown, b: unknown) -> bool {
  let ia = js_object_id(a);
  if (ia != null) {
    return js_same(a, b);
  }
  match (a) {
    let ma: map<string, unknown> => match (b) {
      let mb: map<string, unknown> => {
        let probe = "\0probe:" + new_id().to_string();
        ma.set(probe, null);
        let same = mb.has(probe);
        ma.delete(probe);
        same
      },
      _ => false,
    },
    let aa: unknown[] => match (b) {
      let ab: unknown[] => {
        let sym = js_symbol("probe");
        aa.push(sym);
        let n = ab.length();
        let same = if (n > 0) { js_same(ab[n - 1], sym) } else { false };
        aa.pop();
        same
      },
      _ => false,
    },
    _ => {
      // Typed maps/arrays (e.g. `map<string, map<string, int>>`) do not match
      // `map<string, unknown>` (invariant generics): probe them via their
      // reflected element type, reusing an existing element as the probe
      // value. Empty typed containers cannot be probed and count as distinct.
      let tm = reflect.Type.of_value(a).as_map();
      if (tm != null) {
        type V = unreflect(tm.value_type());
        return match (a) {
          let ma: map<string, V> => match (b) {
            let mb: map<string, V> => {
              let ks = ma.keys();
              if (ks.length() == 0) {
                false
              } else {
                let probe = "\0probe:" + new_id().to_string();
                ma.set(probe, ma[ks[0]]);
                let same = mb.has(probe);
                ma.delete(probe);
                same
              }
            },
            _ => false,
          },
          _ => false,
        };
      }
      let ta = reflect.Type.of_value(a).as_array();
      if (ta != null) {
        type E = unreflect(ta.element_type());
        return match (a) {
          let xa: E[] => match (b) {
            let xb: E[] => {
              let n = xa.length();
              if (n == 0) {
                false
              } else {
                let nb0 = xb.length();
                xa.push(xa[n - 1]);
                let same = xb.length() == nb0 + 1;
                xa.pop();
                same
              }
            },
            _ => false,
          },
          _ => false,
        };
      }
      js_same(a, b)
    },
  }
}

/// Stable merge sort with a JS-style comparator (negative / 0 / positive).
function js_sort<T>(items: T[], cmp: (T, T) -> int throws unknown) -> T[] throws unknown {
  let n = items.length();
  if (n <= 1) {
    return items.slice(0, n);
  }
  let mid = n / 2;
  let left = js_sort(items.slice(0, mid), cmp);
  let right = js_sort(items.slice(mid, n), cmp);
  let out: T[] = [];
  let i = 0;
  let j = 0;
  while (i < left.length() && j < right.length()) {
    if (cmp(right[j], left[i]) < 0) {
      out.push(right[j]);
      j += 1;
    } else {
      out.push(left[i]);
      i += 1;
    }
  }
  while (i < left.length()) {
    out.push(left[i]);
    i += 1;
  }
  while (j < right.length()) {
    out.push(right[j]);
    j += 1;
  }
  out
}

/// JS `parseFloat(str)`: parse the longest valid decimal prefix (after
/// leading whitespace); NaN if there is none. Handles `Infinity`.
function js_parse_float(str: string) -> float {
  let s = str.trim_start();
  let cps = s.to_code_points();
  let n = cps.length();
  let i = 0;
  if (i < n && (cps[i] == 43 || cps[i] == 45)) {
    i += 1;
  }
  if (s.slice(i, i + 8) == "Infinity") {
    return if (cps.at(0) == 45) { 0.0 - baml.Float.inf() } else { baml.Float.inf() };
  }
  let digits = 0;
  while (i < n && cps[i] >= 48 && cps[i] <= 57) {
    i += 1;
    digits += 1;
  }
  if (i < n && cps[i] == 46) {
    i += 1;
    while (i < n && cps[i] >= 48 && cps[i] <= 57) {
      i += 1;
      digits += 1;
    }
  }
  if (digits == 0) {
    return baml.Float.nan();
  }
  let end = i;
  if (i < n && (cps[i] == 101 || cps[i] == 69)) {
    let j = i + 1;
    if (j < n && (cps[j] == 43 || cps[j] == 45)) {
      j += 1;
    }
    let ed = 0;
    while (j < n && cps[j] >= 48 && cps[j] <= 57) {
      j += 1;
      ed += 1;
    }
    if (ed > 0) {
      end = j;
    }
  }
  let t = s.slice(0, end);
  // Rust's float parser rejects a trailing "." after digits in some
  // positions and a leading "+"; normalise.
  if (t.starts_with("+")) {
    t = t.slice(1, t.length());
  }
  if (t.ends_with(".")) {
    t = t + "0";
  }
  if (t.starts_with(".")) {
    t = "0" + t;
  }
  if (t.starts_with("-.")) {
    t = "-0" + t.slice(1, t.length());
  }
  let dotE = t.index_of(".e") ?? t.index_of(".E");
  if (dotE != null) {
    t = t.slice(0, dotE + 1) + "0" + t.slice(dotE + 1, t.length());
  }
  baml.Float.parse(t) catch (e) { _ => baml.Float.nan() }
}

function js_digit_value(c: int) -> int {
  if (c >= 48 && c <= 57) {
    c - 48
  } else if (c >= 97 && c <= 122) {
    c - 97 + 10
  } else if (c >= 65 && c <= 90) {
    c - 65 + 10
  } else {
    99
  }
}

/// JS `parseInt(str, radix)` for the radixes YAML uses. Returns a float NaN
/// when there are no digits (as JS does), else an int. Values beyond the
/// 63-bit int range are not handled (JS would lose precision instead).
function js_parse_int(str: string, radix: int) -> int | float {
  let s = str.trim_start();
  let cps = s.to_code_points();
  let n = cps.length();
  let i = 0;
  let neg = false;
  if (i < n && (cps[i] == 43 || cps[i] == 45)) {
    neg = cps[i] == 45;
    i += 1;
  }
  if (radix == 16 && i + 1 < n && cps[i] == 48 && (cps[i + 1] == 120 || cps[i + 1] == 88)) {
    i += 2;
  }
  let v = 0;
  let fv = 0.0;
  let big = false;
  let start = i;
  let digits = 0;
  while (i < n) {
    let d = js_digit_value(cps[i]);
    if (d >= radix) {
      break;
    }
    if (!big && v > (4611686018427387903 - d) / radix) {
      // Beyond the int range: continue as a JS number (float), as JS does.
      big = true;
      fv = v * 1.0;
    }
    if (big) {
      fv = fv * (radix * 1.0) + d * 1.0;
    } else {
      v = v * radix + d;
    }
    digits += 1;
    i += 1;
  }
  if (digits == 0) {
    return baml.Float.nan();
  }
  if (big) {
    if (radix == 10) {
      // correctly rounded, like JS parseInt for decimal strings
      fv = baml.Float.parse(baml.String.from_code_points(cps.slice(start, i)) catch (e) { _ => "" }) catch (e) { _ => fv };
    }
    return if (neg) { 0.0 - fv } else { fv };
  }
  if (neg) { 0 - v } else { v }
}

/// JS `BigInt(str)`: decimal, or `0x`/`0o`/`0b`-prefixed. Throws a
/// SyntaxError-like JsError for invalid input.
function js_parse_bigint(str0: string) -> bigint {
  let str = str0.trim();
  let radix = 10;
  let body = str;
  let neg = false;
  if (str.starts_with("0x") || str.starts_with("0X")) {
    radix = 16;
    body = str.slice(2, str.length());
  } else if (str.starts_with("0o") || str.starts_with("0O")) {
    radix = 8;
    body = str.slice(2, str.length());
  } else if (str.starts_with("0b") || str.starts_with("0B")) {
    radix = 2;
    body = str.slice(2, str.length());
  } else if (str.starts_with("-")) {
    neg = true;
    body = str.slice(1, str.length());
  } else if (str.starts_with("+")) {
    body = str.slice(1, str.length());
  }
  if (body == "") {
    throw JsError { name: "SyntaxError", message: "Cannot convert " + str0 + " to a BigInt" };
  }
  let v = 0n;
  let r = if (radix == 16) { 16n } else if (radix == 8) { 8n } else if (radix == 2) { 2n } else { 10n };
  for (let c in body.to_code_points()) {
    let d = js_digit_value(c);
    if (d >= radix) {
      throw JsError { name: "SyntaxError", message: "Cannot convert " + str0 + " to a BigInt" };
    }
    v = v * r + (baml.Bigint.parse(d.to_string()) catch (e) { _ => 0n });
  }
  if (neg) { 0n - v } else { v }
}

/// `n.toString(radix)` for a non-negative or negative int.
function js_int_to_radix(n: int, radix: int) -> string {
  if (n == 0) {
    return "0";
  }
  let neg = n < 0;
  let v = if (neg) { 0 - n } else { n };
  let s = "";
  while (v > 0) {
    s = ("0123456789abcdefghijklmnopqrstuvwxyz".at(v % radix) ?? "") + s;
    v = v / radix;
  }
  if (neg) { "-" + s } else { s }
}

/// `n.toString(radix)` for a bigint.
function js_bigint_to_radix(n: bigint, radix: int) -> string {
  if (radix == 10) {
    return n.to_string();
  }
  if (n == 0n) {
    return "0";
  }
  let neg = n < 0n;
  let v = if (neg) { 0n - n } else { n };
  let r = baml.Bigint.parse(radix.to_string()) catch (e) { _ => 10n };
  let s = "";
  while (v > 0n) {
    let d = (v % r).to_int() catch (e) { _ => 0 };
    s = ("0123456789abcdefghijklmnopqrstuvwxyz".at(d) ?? "") + s;
    v = v / r;
  }
  if (neg) { "-" + s } else { s }
}

/// JS `Number.prototype.toExponential()` (no fraction-digits argument).
function js_to_exponential(f: float) -> string {
  if (f.is_nan()) {
    return "NaN";
  }
  if (f.is_infinite()) {
    return if (f > 0.0) { "Infinity" } else { "-Infinity" };
  }
  if (f == 0.0) {
    return "0e+0";
  }
  let s = js_number_to_string(f);
  let neg = s.starts_with("-");
  if (neg) {
    s = s.slice(1, s.length());
  }
  let mant = s;
  let exp = 0;
  let ei = s.index_of("e");
  if (ei != null) {
    mant = s.slice(0, ei);
    exp = baml.Int.parse(s.slice(ei + 1, s.length()).replace("+", "")) catch (e) { _ => 0 };
  }
  let dot = mant.index_of(".");
  let intPart = if (dot != null) { mant.slice(0, dot) } else { mant };
  let fracPart = if (dot != null) { mant.slice(dot + 1, mant.length()) } else { "" };
  let digits = intPart + fracPart;
  exp = exp + intPart.length() - 1;
  let lead = 0;
  while (lead < digits.length() - 1 && digits.at(lead) == "0") {
    lead += 1;
    exp -= 1;
  }
  digits = digits.slice(lead, digits.length());
  let end = digits.length();
  while (end > 1 && digits.at(end - 1) == "0") {
    end -= 1;
  }
  digits = digits.slice(0, end);
  let m = if (digits.length() > 1) { digits.slice(0, 1) + "." + digits.slice(1, digits.length()) } else { digits };
  let es = if (exp >= 0) { "+" + exp.to_string() } else { exp.to_string() };
  (if (neg) { "-" } else { "" }) + m + "e" + es
}

/// JS `Number(v)` for strings and numbers (enough for this library).
function js_to_number(v: unknown) -> float {
  match (v) {
    null => 0.0,
    let b: bool => if (b) { 1.0 } else { 0.0 },
    let i: int => i * 1.0,
    let f: float => f,
    let g: bigint => js_parse_float(g.to_string()),
    let s: string => {
      let t = s.trim();
      if (t == "") {
        return 0.0;
      }
      let f = js_parse_float(t);
      // Number() requires the whole string to be numeric
      if (js_number_to_string(f) == t || re("^[-+]?(\\d+\\.?\\d*|\\.\\d+)([eE][-+]?\\d+)?$").has_match(t)) {
        f
      } else {
        baml.Float.nan()
      }
    },
    _ => baml.Float.nan(),
  }
}

/// `String.fromCodePoint(cp)`. BAML string literals only decode `\n \t \r
/// \0 \b \v \f \\ \"`; `\xNN` / `\uNNNN` / `\u{…}` are kept verbatim
/// (silently), so other characters must be built from code points.
function chr(cp: int) -> string {
  baml.String.from_code_points([cp]) catch (e) {
    _ => baml.sys.panic("invalid code point " + cp.to_string()),
  }
}
