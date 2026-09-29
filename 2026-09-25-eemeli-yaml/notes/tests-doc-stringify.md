# tests/doc/stringify.ts → baml_src/tests/doc/stringify.baml

## Counts

`$B test -i "root::doc/stringify::*"`: **236 passed, 7 failed, 243 total**. Of the 236 passing tests, **10 are skipped** (bodies are `// UNPORTABLE` placeholders), so there are **226 real passes**. One more test is ported only in part (see below).

The upstream loops are unrolled: the `YAML 1.1` / `YAML 1.2` describe loop is generated twice from one template, and the loops for `minFractionDigits`, `timestamp-like`, `singleQuote` and `blockQuote` are written out by hand. Upstream uses some test names twice, and BAML needs unique names, so three tests were renamed:
- `number (-0) with trailing zeros`: upstream calls it `number (0) …`, because `${-0}` is `"0"`.
- `\\uD834\\uDF06` / `\\uD83D\\uDE00`: upstream's names are the JS strings, which equal the emoji names of the tests before them.
- `default (flowCollectionPadding: false)`: upstream has two tests named `default`.

### Skipped (unportable)
- `YAML 1.x › boolean › Boolean`, `number › Number`, `number › BigInt`, `string › String` (×2 versions, 8 tests): these use boxed primitives (`new Boolean`, `new Number`, `new String`, `Object(BigInt)`). BAML has nothing like them.
- `unpaired surrogate pairs › \uDF06\uD834`, `› \uDEAD`: a BAML string is UTF-8 and can't hold a lone UTF-16 surrogate.
- `maps › pushing non-Pair item` (partial): the first assertion is ported and passes. The second, `doc.value.push('TEST')` throwing a TypeError, calls a method that `YAMLMap` doesn't have. In BAML that is a compile error, so it can't be written.

### Failing: all are (b), JS `undefined` vs BAML `null`
BAML has no `undefined`, so these tests pass `null` instead. The library can't tell "absent" from `null`.
- `YAML 1.1 › undefined`, `YAML 1.2 › undefined`, `undefined values › undefined`: `stringify(undefined)` should return `undefined`. `stringify(null)` returns `"null\n"`.
- `undefined values › { a: 'A', b: undefined, c: 'C' }`: in JS, undefined map values are dropped. With `null` the output contains `b: null`.
- `undefined values › Map { … 'b' => undefined … }`: same cause, for a JS Map.
- `replacer › function as filter of Object entries` / `… of Map entries`: a replacer that returns `undefined` should drop the entry. Returning `null` keeps it as `null`.

## Library fixes
None were needed from me in the end. One test (`circular references › further relatives`) exposed a bug in `js_identical` (`src/js.baml`). Two distinct maps whose type was not `map<string, unknown>` (for example `map<string, map<string, unknown>>` from nested literals) didn't match the probe arms, because generics are invariant. The code then fell back to `==`, which compares structurally, so the two maps were aliased by mistake. Another agent had already fixed this in the shared tree (by probing with the reflected element type) by the time I synced, and my fix was essentially the same, so I kept theirs.

## BAML gaps / pain points
Nothing new beyond what is already recorded:
- Backtick literals drop their leading and trailing newlines (see tests-doc-comments.md). I worked around it with `tstr_src(s) = source(s) + "\n"`. For the one source that ends in a blank line, I used a plain string.
- `\uXXXX` escapes aren't decoded (see the guide). Here only `\0` was needed, and that works.
- This is a variant of PORTING_NOTES #9 worth recording: **wrong-result**. Because generics are invariant, `match (v) { let m: map<string, unknown> => … , _ => a == b }` silently takes the structural-equality path for nested map or array literals. Repro:
  ```baml
  let baz: map<string, unknown> = { "a": 1 };
  let seq = [{ "k": { "baz": baz } }, { "k": { "baz": baz } }];
  // seq[0]["k"] is a map<string, map<string, unknown>> and does not match
  // `let m: map<string, unknown>`; any identity check that falls back to `==` reports them identical.
  ```
- Once, `$B run -e 'root.re("a")'` (and `root.source(...)`) crashed the CLI with `thread '<unknown>' has overflowed its stack`. After I re-synced the project I couldn't reproduce it, so treat it as unconfirmed.
