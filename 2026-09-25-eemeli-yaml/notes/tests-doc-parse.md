# tests/doc/parse.ts → baml_src/tests/doc/parse.baml

## Results

`$B test -i "root::doc/parse::*"`: **96 passed, 0 failed, 1 skipped** (97 tests; the runner reports 97 passed because the skipped test has a trivially-passing body).

- Skipped (unportable): `buffer as source (#459)` — passes a Node.js `Buffer` where a string is expected to exercise the runtime "source is not a string" check; in BAML that is a compile-time type error, so there is nothing to test.
- Partially ported (the `vi.spyOn(process, 'emitWarning')` / `console.warn` mock assertions are dropped, everything else is checked; counted as passed): `Work sensibly even with disabled limits › js-yaml case 1` and all 6 tests in `handling complex keys`. The port's `warn()` (`src/log.baml`) writes straight to stderr with no hook, so warning emission cannot be observed from a test.
- Parameterised upstream loops (`for (const tag …)`, `for (const [name, src] …)`, `maxAliasCount` loops, `keepSourceTokens` `[src, type]` loop) are unrolled with the same generated names and order.
- Reviver `this` is the 4th `holder` argument; `vi.fn` call/instance recording uses `mock_calls()` + a local array.

## Library fixes (baml_src/src)

- `src/doc/applyReviver.baml`: a reviver returning `undefined` for an array element dropped the element (shifting indices); upstream does `delete val[i]`, which leaves a hole that reads as `undefined`. Now sets the element to `null` and keeps the array length (fixes `reviver › sequence`).
- `src/compose/compose-node.baml`: `composeNodeCollection` used `catch_all`, which does not catch BAML panics, so a stack overflow on deeply nested input crashed instead of becoming a `RESOURCE_EXHAUSTION` error. Now uses `catch_all_panics` and takes the message from the `baml.panics.StackOverflow` (fixes `Excessive recursion`).

## Test-helper fixes (baml_src/tests/_expect.baml)

- `t_match` (toMatchObject) compared JS `Map` keys with strict equality; vitest compares Map keys with the same subset testers as values, so `_map([[_seq(), 'x']])` must match a map whose key is a `YAMLSeq`. Non-primitive expected keys now fall back to `t_match` (fixed 6 flow-collection-key tests).
- `t_match` recursed forever on circular structures (`!!merge recursion`, where `res[0].a === res[0]`); it now tracks the (actual, expected) pairs under comparison, like the existing `t_equal` cycle guard.

## BAML gaps / bugs hit (not already in PORTING_NOTES.md)

1. **missing-feature / wrong-result — call depth is capped at 256 frames.** `MAX_FRAMES = 256` in `bex_vm/src/vm.rs:118`. JS allows ~10k frames. Any recursive-descent code over moderately nested data overflows: the composer uses ~5 frames per nesting level, so ~50 levels of `[[[…]]]` already overflows (the upstream test uses 5000 and only expects the error to be `RESOURCE_EXHAUSTION`, which now holds; it would fail for far shallower documents too).
   ```baml
   function rec(n: int) -> int { if (n == 0) { return 0; } 1 + rec(n - 1) }
   // rec(260) -> baml.panics.StackOverflow { message: "stack overflow" }
   ```
2. **pain-point — `catch_all` does not catch panics** (`baml.panics.StackOverflow`); `catch_all_panics` (or naming the panic type in `catch`) is required. A mechanical port of JS `try { … } catch {}` — which does catch the `RangeError` from stack exhaustion — silently loses that behaviour. Also `js_string(panic)` gives `[object Object]`; read `.message` from the matched panic type.
   ```baml
   let r = rec(1000) catch_all (e) { _ => -1 };          // panics: not caught
   let r = rec(1000) catch_all_panics (e) { _ => -1 };   // -1
   ```
3. **pain-point — backtick string literals are auto-dedented and trimmed**, including the trailing newline before the closing backtick. The `source` test helper (upstream template tag) therefore returns text without the trailing `\n` upstream has; tests append `+ "\n"`. Plain upstream template literals whose leading newline/indentation matter must be rewritten as ordinary `"…\n…"` strings.
   ```baml
   json_quote(`
       a
       b
     `)   // "a\nb"  (JS would keep "\n    a\n    b\n  ")
   ```
4. **toolchain bug — `baml-cli run -e` aborts with a native stack overflow** in this project for any expression that calls into the library, e.g. `$B run -e 'root.yaml_parse("a: 1")'` → `thread '<unknown>' has overflowed its stack / fatal runtime error: stack overflow, aborting` (the same code works inside `$B test`). Debugging had to go through a throwaway testset.
