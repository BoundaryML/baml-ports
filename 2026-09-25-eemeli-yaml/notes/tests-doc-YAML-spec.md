# tests/doc/YAML-1.2.spec.ts and tests/doc/YAML-1.1.spec.ts

## Results

| File | Testset | Pass | Fail | Skipped |
|---|---|---|---|---|
| `baml_src/tests/doc/YAML-1.2.spec.baml` | `doc/YAML-1.2.spec` | 117 | 0 | 0 |
| `baml_src/tests/doc/YAML-1.1.spec.baml` | `doc/YAML-1.1.spec` | 1 | 0 | 0 |

All 117 upstream generated tests (one per spec example, nested in one `testset` per section, same names) are ported. The checker was sanity-checked by mutating expected values (tgt, warnings, errors, directives, special results), which made the corresponding tests fail as expected.

## How it's structured

- The upstream `spec` table is kept as data: each test builds one `TspecCase { src, tgt, errors, warnings, jsWarnings, special }` literal and calls the shared checker `tspec_run` (the body of upstream's loop: `parseAllDocuments` → `toJS` → `toMatchObject(tgt)`, per-document error messages, warning-message sets, `YAMLError` instance check, `special(src)`, and the stringify/re-parse round trip when no errors are expected).
- The case literals were generated mechanically by `tools/gen_yaml12_spec.cjs`, which evaluates the upstream object in node and prints BAML literals. `NaN`/`-Infinity` become `baml.Float.nan()`/`0.0 - baml.Float.inf()`, `new Set`/`new Map`/`Buffer.from` become `tspec_set`/`tspec_jsmap`/`tspec_bytes`, and control characters become `chr(n)` (BAML string literals have no `\uXXXX`/`\xNN` escapes, see PORTING_NOTES #15).
- The 21 `special(src)` callbacks are hand-ported as `tspec_sp_<n>` functions and passed as lambdas.

## Partial / semantic differences (not counted as skips)

- **The `mockWarn` assertion is omitted.** Upstream uses `vi.spyOn(process, 'emitWarning')` and asserts `expect(mockWarn).not.toHaveBeenCalled()` for cases without `jsWarnings`. The BAML library's `warn()` prints to stderr and can't be intercepted. The `jsWarnings` branch upstream asserts nothing (`expect(...)` with no matcher), so only the negative check is lost. `jsWarnings` is kept as table data.
- Example 2.22 `date.getFullYear()`/`getMonth()` are local-time getters in JS. `JsDate` only has UTC, so the check reads year and month from `toISOString()`. For these values the result is the same in every time zone.
- Example 8.22 `seq[1]`: upstream `YAMLSeq extends Array`. The port uses `seq.items[1]`.

## Library fixes

None needed.

## New BAML gaps / pain points

1. **spurious-compile-error: `throws unknown` on a function that happens to throw only a narrower type is a hard error (E0097)**, not a warning:
   ```baml
   function f() -> null throws unknown { expect_true(false, "x") }
   // error[E0097]: `throws unknown` is imprecise: this function only throws `ExpectationFailed`. ... remove the declaration
   ```
   This is annoying when writing helpers whose contract is "may throw anything" (JS-style test callbacks). The workaround is to drop the annotation and let inference do it.
2. **pain-point: invariance also bites helper parameters.** `function tspec_set(values: unknown[])` can't be called with a `string[]` (E0001 "expected `unknown[]`, found `string[]`"). You have to make the helper generic (`function tspec_set<T>(values: T[])`). This is related to PORTING_NOTES #9 but affects simple call sites, not just `match`.
3. **pain-point: no data-driven test generation.** A table-driven vitest file (a `for` loop calling `test()`) needs an external generator script so that each case gets a static `test` block. The table then lives as generated literals in the `.baml` file rather than as one data structure. The alternative is a single function returning the whole table, which every test would rebuild.
