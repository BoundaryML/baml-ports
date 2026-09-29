# tests/json-test-suite.ts → baml_src/tests/json-test-suite.baml (+ .generated.baml)

## Results

`$B test -i "root::json-test-suite::*"` (shared tree): **330 passed, 3 failed, 7 skipped** (340 tests). The runner reports 337 passed because the 7 skipped tests are stubs that pass trivially.

- Upstream builds one vitest test per file in `tests/json-test-suite/{test_parsing,test_transform}/*.json` at runtime. BAML test blocks are static, so `tools/gen_json_test_suite.py` generates `baml_src/tests/json-test-suite.generated.baml`. It emits one test per file (sorted, same names, same two `describe`s) that calls `tjts_testSuccess` or `tjts_testReject` from `json-test-suite.baml`. Those checkers read the file at test time and run upstream's assertions, with `JSON.stringify` mapped to `json_stringify`.
- Upstream uses `JSON.stringify`, not `JSON.parse`, so the checkers don't use `baml.json.parse`.
- **Skipped (7):** the same skip list as upstream (`test.skip`): the 2 "Maximum call stack size exceeded" files and the 5 "Map keys must be unique" files. Their stubs call `tjts_skipped(reason)`.
- **Reading the files:** `readFileSync(path, 'utf8')` decodes invalid UTF-8 lossily. `baml.fs.read` throws `ParseError` instead, and 28 of the files are not valid UTF-8. `tjts_read` therefore uses `baml.fs.open(path, "r").bytes().to_string()` (a lossy decode).

### Failing tests

- `test_transform/string_1_escaped_invalid_codepoint`, `string_2_escaped_invalid_codepoints`, `string_3_escaped_invalid_codepoints`: the input contains `"\uD800"`, a lone surrogate escape. A JS string can hold a lone surrogate, but a BAML string is UTF-8 and cannot (`baml.String.from_code_points([0xD800])` throws). The ported flow-scalar resolver therefore reports `BAD_DQ_ESCAPE` errors, while the test expects none. This is an unavoidable JS/BAML semantic difference.

## Library fixes

- `src/js.baml` `js_parse_int`: an integer scalar beyond the BAML int range panicked with `baml.panics.IntegerOverflow` (for example `-1231231231231231231231`, `9223372036854775807`, `10000000000000000999`). JS `parseInt` returns a (float) Number in that case, and now the port does too. Decimal strings go through `baml.Float.parse`, so they are correctly rounded like JS. This fixed 8 tests.
- `i_structure_500_nested_arrays` hit `baml.panics.StackOverflow` at first (see below). It passes now because of another agent's change to `src/compose/compose-node.baml`, which catches the stack-overflow panic (`catch_all_panics`) and turns it into an error. For a `testReject` file an error is acceptable. JS itself handles 500 levels of nesting without overflowing.

## New BAML gaps / pain points

1. **wrong-result/limitation: the call stack is very shallow, about 255 frames.** JS allows around 10k frames. Composing 500 nested flow sequences needs about 5 frames per level, so it overflows.
   ```baml
   function zz_rec(n: int) -> int { if (n == 0) { 0 } else { 1 + zz_rec(n - 1) } }
   // zz_rec(250) == 250; zz_rec(256) → uncaught baml.panics.StackOverflow
   ```
2. **surprise: `int` is 63-bit, holding -2^62 to 2^62-1.** `9223372036854775807` is a compile error: "integer literal … is out of range for `int` (which holds -4611686018427387904 to 4611686018427387903)". So values that fit an i64, and 64-bit literals from other languages, do not fit a BAML int.
3. **pain-point: `baml.fs.read` has no lossy mode.** Reading a file that is not valid UTF-8 needs `baml.fs.open(p, "r").bytes().to_string()`.
4. **missing-feature: strings cannot hold lone surrogates.** This matters when porting JS code that handles `\uD800`-style escapes, and is expected given UTF-8 strings.
5. **crash: `$B run -e 'root.js_parse_int("12", 10)'`, and even `root.json_stringify(root.yaml_parse("[1, 2]"))`, abort with "thread '<unknown>' has overflowed its stack".** The same expression inside a named function run with `$B run fn` works. Other agents saw this too; it looks like an issue with the `-e` evaluation path on a large project.
