# tests/doc/types.ts → baml_src/tests/doc/types.baml

## Results

`$B test -i "root::doc/types::*"`: **122 passed, 0 failed, 0 skipped** (122 total; same as upstream — the `for`-generated tests and the 4× `describe.for('!!merge with %o')` blocks are unrolled into individually named tests).

Adapted tests (pass, but do not exercise exactly what upstream does):

- `custom tags::!!binary::tag string in tag array` and `custom tags::array within customTags`: upstream passes a nested array (`customTags: [['binary']]`, `[[regexp, sharedSymbol]]`), relying on `Array#concat` flattening. `customTags` is typed `TagRef[]` in the port, so a nested array cannot be expressed; the tests pass the flattened array. Effectively these two check nothing beyond their neighbours — count them as skipped if counting strictly (→ 120 pass / 2 skipped).
- `schema changes::set version + custom tags`: upstream passes the number `1.2` as version (a TS type error coerced at runtime); BAML passes `"1.2"`.
- `custom tags::RegExp::*` / `schema from custom tags::*`: JS `RegExp` values are modelled by a test class `ttyp_RegExp { source, flags }`. Upstream's `regexp` tag has no `stringify` and relies on `String(regexp) === "/re/g"`; BAML class instances have no `toString()`, so the test tag supplies an explicit `stringify` that does the same via `stringifyString`.
- `custom tags::Symbol::*`: `Symbol.for(key)` / `Symbol.keyFor` are modelled by deriving the `JsSymbol._id` deterministically from the key (a global registry needs module-level state, which BAML lacks).
- `custom tags::null prototyped object`: `class YAMLNullObject extends YAMLMap` (overriding `toJS`) cannot be expressed (no inheritance); the tag creates a plain `YAMLMap`. The null-prototype object is a test class `ttyp_NullObject { entries }` so that `identify` can recognise it. `Object.getPrototypeOf(res) === null` is replaced by "res is a plain map".
- `YAML 1.1 schema::!!binary`: `String.fromCharCode` over the bytes is replaced by comparing the byte arrays (and the first 5 bytes against `GIF89`).

## Library fixes

- `src/stringify/stringifyNumber.baml`: `.NaN` (and any non-finite source that parses to NaN) was re-emitted verbatim instead of as `.nan`, because `parseFloat(source) === num` was ported as `pf == num`, and BAML's `NaN == NaN` is `true`. Added `&& !num.is_nan()`. Fixed `core schema::!!float` and `YAML 1.1 schema::!!float`.
- (The `!!omap parse` failures I first hit were the `t_class_name` "JsMap<unknown>" issue in `_expect.baml`, already fixed in the shared tree by another agent.)

## New BAML gaps / bugs

1. **wrong-result — `NaN == NaN` is `true`** (IEEE 754 / JS: `false`). A mechanical port of `x === y` on floats silently changes behaviour.
   ```baml
   test "nan" { expect_true(!(baml.Float.nan() == baml.Float.nan()), "NaN == NaN is true") }  // fails
   ```
2. **spurious-compile-error — `?.` does not see through a nested optional from `.at()`**: `Array<T?>.at(i)` has type `(T | null) | null`, and `?.field` only strips one level.
   ```baml
   class TtypG { text: string }
   function f(g: (TtypG | null)[]) -> string { g.at(1)?.text ?? "" }
   // error[E0007]: type `TtypG | null` has no member `text`
   ```
   (`g[1]?.text` compiles.) Hit with `baml.regex.Match.groups`, which is `(Group | null)[]`.
3. **pain-point — `baml run -e 'root.anything(...)'` overflows the stack** (`thread '<unknown>' has overflowed its stack`) in this project (even `root.js_typeof(1)`), so quick expression evaluation is unusable; probing had to go through scratch `test`s.
4. **pain-point — named-argument syntax**: the error for `Xoshiro256PlusPlus.new(u8)` says "defaulted parameter `seed` must be passed by name", but the obvious `new(seed: u8)` is a parse error; it must be `new(seed = u8)`.
5. **pain-point — `baml.Float.inf()`** (not `infinity()`), discoverable only via existing code.
