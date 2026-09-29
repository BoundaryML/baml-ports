# tests/properties.ts → baml_src/tests/properties.baml

## Results

`$B test -i "root::properties::*"`: **1 passed, 0 failed, 0 skipped** (1 total, ~12 s).

## How fast-check was replaced

Upstream: `fc.assert(fc.property(fc.anything({ key: fc.fullUnicodeString(), values: [...] }), optionsRecord, (obj, opts) => expect(parse(stringify(obj, opts), opts)).toStrictEqual(obj)))` — 100 random runs with shrinking.

BAML has no property-testing library, so the port has hand-written generators (`tprop_*`) over `baml.random.Xoshiro256PlusPlus` with a **fixed seed**, running 100 cases:

- `fullUnicodeString`: 0–10 code points, biased towards ASCII (incl. control characters), plus BMP (no surrogates — BAML strings are UTF-8) and astral code points (built with `chr()`).
- values: unicode strings, lorem words / sentences (word count capped at 40 / 8 sentences to keep runtime reasonable; upstream allows up to 1000 words / 100 sentences), booleans, 32-bit ints, doubles (specials: ±0, ±1, ±MIN_VALUE, ±MAX_VALUE, EPSILON, ±0.5, NaN, ±Infinity, plus random 53-bit mantissas scaled by 10^[-320, 300]), and `null | ±Infinity`.
- `anything`: nested arrays / plain objects up to depth 3 (fast-check defaults: no Map/Set/Date/boxed/null-prototype values).
- options: `{ mapAsMap: false, merge: bool, schema: 'core' | 'yaml-1.1' }` with each key independently omitted (`withDeletedKeys`).

Differences: deterministic (fixed seed) rather than random per run; no shrinking (a failure reports run index, options, value, YAML text and parse result); `toStrictEqual` approximated by `expect_toEqual`'s `t_equal`, which does not distinguish `-0`/`0` or `{a: undefined}`/`{}`.

Additionally (not kept in the file) I ran the same property with seeds 1–6 × 100 runs (600 cases, ~86 s): all passed — no library bugs found.

## Library fixes

None needed.

## New BAML gaps / pain points

- No property-testing / generator library; `baml.random` only offers raw bytes and `random_int()` (no ranges, floats, choice or shrinking), so every arbitrary had to be written by hand.
- No way to build a float from bits or a `pow()`; random doubles are made by repeated `* 10.0`.
- `Xoshiro256PlusPlus.new(seed = u8)` — named-arg syntax is `=`, while the error message only says "must be passed by name".
