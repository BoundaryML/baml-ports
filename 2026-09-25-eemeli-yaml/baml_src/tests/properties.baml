// Port of tests/properties.ts
//
// Upstream uses fast-check (`fc.assert(fc.property(...))`, 100 random runs
// with shrinking). BAML has no property-testing library, so this port writes
// small generators over `baml.random.Xoshiro256PlusPlus` with a FIXED seed
// (deterministic, reproducible runs) that mimic the upstream arbitraries:
//
// - `key = fc.fullUnicodeString()`: strings of 0-10 code points, biased like
//   fast-check towards ASCII (incl. control chars) but covering the BMP and
//   astral planes (surrogates excluded: BAML strings are UTF-8).
// - `values`: key strings, `fc.lorem` words / sentences, booleans,
//   `fc.integer()` (32-bit), `fc.double()` (special values incl. -0, NaN,
//   ±Infinity, MIN/MAX_VALUE, plus random magnitudes), and
//   `null | -Infinity | +Infinity`.
// - `fc.anything(...)`: nested arrays and plain objects of those values
//   (fast-check's defaults: no Map/Set/Date/boxed/null-prototype values).
// - options: `fc.record({ mapAsMap: false, merge: bool, schema: 'core' | 'yaml-1.1' },
//   { withDeletedKeys: true })`.
//
// Differences: no shrinking (a failure reports the run index and the
// generated value instead of a minimal counterexample); `toStrictEqual` is
// approximated by `expect_toEqual` (which, unlike toStrictEqual, does not
// distinguish -0 from 0 nor `{ a: undefined }` from `{}`).

class tprop_Gen {
  rng: baml.random.Xoshiro256PlusPlus

  /// Uniform int in [0, n)
  function below(self, n: int) -> int {
    let x = self.rng.random_int() % n;
    if (x < 0) { x + n } else { x }
  }

  /// Uniform int in [lo, hi]
  function between(self, lo: int, hi: int) -> int {
    lo + self.below(hi - lo + 1)
  }

  function bool(self) -> bool {
    self.below(2) == 1
  }
}

function tprop_gen(seed: int) -> tprop_Gen {
  let bytes: int[] = [];
  let i = 0;
  while (i < 32) {
    bytes.push((seed * 31 + i * 17) % 256);
    i += 1;
  }
  let u8 = baml.Uint8Array.from_array(bytes) catch (e) {
    _ => baml.sys.panic("bad seed"),
  };
  tprop_Gen { rng: baml.random.Xoshiro256PlusPlus.new(seed = u8) }
}

/// `fc.fullUnicodeString()`
function tprop_unicode_string(g: tprop_Gen) -> string {
  let len = if (g.below(4) == 0) { 0 } else { g.between(1, 10) };
  let out = "";
  let i = 0;
  while (i < len) {
    let kind = g.below(8);
    let cp = if (kind < 5) {
      g.below(128)
    } else if (kind < 7) {
      let c = g.between(128, 0xFFFF - 2048);
      if (c >= 0xD800) { c + 2048 } else { c }
    } else {
      g.between(0x10000, 0x10FFFF)
    };
    out += chr(cp);
    i += 1;
  }
  out
}

function tprop_lorem_words() -> string[] {
  ["lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit", "sed", "do", "eiusmod", "tempor", "incididunt", "ut", "labore", "et", "dolore", "magna", "aliqua", "enim", "ad", "minim", "veniam", "quis", "nostrud", "exercitation", "ullamco", "laboris", "nisi", "aliquip", "ex", "ea", "commodo", "consequat"]
}

/// `fc.lorem({ maxCount, mode: 'words' })` (count capped to keep runs fast)
function tprop_lorem_words_value(g: tprop_Gen) -> string {
  let words = tprop_lorem_words();
  let n = g.between(1, 40);
  let out: string[] = [];
  let i = 0;
  while (i < n) {
    out.push(words[g.below(words.length())]);
    i += 1;
  }
  out.join(" ")
}

/// `fc.lorem({ maxCount, mode: 'sentences' })`
function tprop_lorem_sentences_value(g: tprop_Gen) -> string {
  let n = g.between(1, 8);
  let out: string[] = [];
  let i = 0;
  while (i < n) {
    let s = tprop_lorem_words_value(g);
    out.push(s.slice(0, 1).to_upper_case() + s.slice(1, s.length()) + ".");
    i += 1;
  }
  out.join(" ")
}

/// `fc.double()`
function tprop_double(g: tprop_Gen) -> float {
  let k = g.below(12);
  if (k == 0) {
    let specials: float[] = [0.0, -0.0, 1.0, -1.0, 5e-324, -5e-324, 1.7976931348623157e308, -1.7976931348623157e308, 2.220446049250313e-16, 0.5, -0.5];
    return specials[g.below(specials.length())];
  }
  if (k == 1) {
    return match (g.below(3)) {
      0 => baml.Float.nan(),
      1 => baml.Float.inf(),
      _ => 0.0 - baml.Float.inf(),
    };
  }
  // a random 53-bit mantissa scaled by a random power of ten
  let m = g.below(9007199254740992) * 1.0;
  let e = g.between(-320, 300);
  let f = m;
  let i = 0;
  if (e >= 0) {
    while (i < e) {
      f = f * 10.0;
      i += 1;
    }
  } else {
    while (i < 0 - e) {
      f = f / 10.0;
      i += 1;
    }
  }
  if (g.bool()) { 0.0 - f } else { f }
}

/// One of the upstream `values` arbitraries
function tprop_value(g: tprop_Gen) -> unknown {
  match (g.below(7)) {
    0 => tprop_unicode_string(g),
    1 => tprop_lorem_words_value(g),
    2 => tprop_lorem_sentences_value(g),
    3 => g.bool(),
    4 => g.between(-2147483648, 2147483647),
    5 => tprop_double(g),
    _ => match (g.below(3)) {
      0 => null,
      1 => 0.0 - baml.Float.inf(),
      _ => baml.Float.inf(),
    },
  }
}

/// `fc.anything({ key, values })`
function tprop_anything(g: tprop_Gen, depth: int) -> unknown {
  let k = if (depth >= 3) { 0 } else { g.below(3) };
  if (k == 0) {
    return tprop_value(g);
  }
  let n = g.below(5);
  if (k == 1) {
    let arr: unknown[] = [];
    let i = 0;
    while (i < n) {
      arr.push(tprop_anything(g, depth + 1));
      i += 1;
    }
    return arr;
  }
  let obj: map<string, unknown> = {};
  let i = 0;
  while (i < n) {
    obj[tprop_unicode_string(g)] = tprop_anything(g, depth + 1);
    i += 1;
  }
  obj
}

/// `fc.record({ mapAsMap, merge, schema }, { withDeletedKeys: true })`
function tprop_options(g: tprop_Gen) -> Options {
  let opts = Options {};
  if (g.bool()) {
    opts.mapAsMap = false;
  }
  if (g.bool()) {
    opts.merge = g.bool();
  }
  if (g.bool()) {
    opts.schema = if (g.bool()) { "core" } else { "yaml-1.1" };
  }
  opts
}

function tprop_show_opts(o: Options) -> string {
  "{ mapAsMap: " + js_string(o.mapAsMap) + ", merge: " + js_string(o.merge) + ", schema: " + js_string(o.schema) + " }"
}

testset "properties" {
  testset "properties" {
    test "parse stringified object" {
      let g = tprop_gen(20240926);
      let run = 0;
      while (run < 100) {
        let obj = tprop_anything(g, 0);
        let opts = tprop_options(g);
        let str = stringify(obj, null, opts) ?? "";
        let res = parse(str, null, opts);
        if (!t_equal(res, obj)) {
          fail("run " + run.to_string() + " with " + tprop_show_opts(opts) + ": " + t_show(obj) + " stringified as " + json_quote(str) + " parsed back as " + t_show(res));
        }
        run += 1;
      }
    }
  }
}
