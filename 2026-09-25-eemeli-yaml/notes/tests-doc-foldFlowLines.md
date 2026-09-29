# tests/doc/foldFlowLines.ts → baml_src/tests/doc/foldFlowLines.baml

Testset `doc/foldFlowLines`, helper prefix `tffl_`.

## Results

`$B test -i "root::doc/foldFlowLines::*"`: **35 passed, 0 failed, 0 skipped** (35 total, same count and order as upstream).

## Porting notes

- `vi.fn()` `onFold` mocks → `MockCalls` recorder captured in the `FoldOptions.onFold` lambda (`() -> void { calls.record([]); }`); `toHaveBeenCalled()` / `toHaveBeenCalledTimes(n)` / `not.toHaveBeenCalled()` → assertions on `calls.count()`.
- `beforeEach` option reset → each test builds fresh options with `tffl_opts(calls)` and mutates fields (`options.lineWidth = 40;`).
- `doc.value.get('key')[0][0].value` → `tffl_map`/`tffl_seq`/`tffl_scalar` narrowing helpers + `YAMLSeq.at(i)`.
- Tricky JS escape strings (`\\\0`, runs of `\"`) were produced by evaluating the JS literals with node and re-encoding them as BAML string literals.

## Library fixes

None needed.

## BAML gaps / pain points

1. **pain-point — backtick (multi-line) strings are dedented and have their leading AND trailing newline trimmed.** Upstream's `source\`…\`` tag keeps the final newline, so every `source(\`…\`)` whose template ends in a newline needs `+ "\n"` appended (5 tests failed with a missing trailing `\n` / `>-` instead of `>` until this was done). Not documented in the guide.
   ```baml
   function f() -> string {
     `
       a
       b
     `
   }
   // returns "a\nb", not "a\nb\n"
   ```
   (Suggest adding this to TEST_PORTING_GUIDE.md next to the `source()` description.)
2. Seen once, not reproducible afterwards: `$B run -e 'root.json_quote(\`<newline>      a<newline>      b<newline>    \`)'` in the shared project aborted with `thread '<unknown>' has overflowed its stack` (twice in a row); the same command later printed `"\"a\\nb\""`. Possibly caused by transient state of the shared project (concurrently edited by other agents) rather than the expression.
