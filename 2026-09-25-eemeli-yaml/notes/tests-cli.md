# tests/cli.ts → baml_src/tests/cli.baml

## Results

`$B test -i "root::cli::*"` (shared tree): **33 passed, 0 failed, 0 skipped** (33 tests, same names, nesting and order as upstream).

- Upstream spies on `console.log`/`console.dir`/`console.error` and drives `cli(Readable.from([input]), done, argv)`. The ported library function `yaml_cli_run(stdin, argv, importVisitor)` returns a `CliResult { stdout, stderr, done, error }`, so `tcli_ok`/`tcli_fail` assert on that result: `toMatchObject` on stdout and stderr, then error is null or not null.
  - `tcli_ok` also checks `done == true`. Upstream's promise only resolves once `done()` has been called.
- `console.dir(tok)` and `console.dir(doc)` push the `Token`/`Document` object itself, so `[{ type: 'document' }]` and `[{ value: _map(...) }]` are matched with `expect_toMatchObject` via reflection, exactly as upstream.
- **`--visit`:** upstream imports `tests/artifacts/cli-unstyle.cjs` and `cli-singlequote.js` at runtime. BAML cannot import code dynamically, so the cli takes an injected module loader. The test file's `tcli_import_visitor(path)` maps those two paths to BAML ports of the visitors: `delete node.flow` becomes `node.flow = null`, and `delete node.format` / `delete node.type` become `= null`. The tests are otherwise unchanged and pass.
- **"CST parser" (`--indent`):** the expected value is built from the same object literal as upstream and serialized with the new `json_stringify_indent(expected, 2.0)`, just as upstream calls `JSON.stringify(literal, null, 2)`. The literal output format of the writer is covered by the other `--indent` tests, which compare against hard-coded strings.
- The upstream `describe.skip` guard for Node < 20 is not applicable.

## Library fixes

- See `notes/src-cli.md`. New: `src/cli.baml`. Added `json_stringify_indent` and `json_stringify_gap` (for `JSON.stringify(v, null, indent)`) to `src/js.baml`.
- `tests/_expect.baml`: another agent's fix (JsMap class name `JsMap<…>`) was needed for the `--doc` tests' `_map(...)` matching.

## New BAML gaps / pain points

- `||` does not narrow its right operand either (same as the `&&` gap, PORTING_NOTES #1): `if (next == null || next.starts_with("-"))` → E0007 `string | null has no member starts_with`. The workaround is `next?.starts_with("-") ?? true`.
