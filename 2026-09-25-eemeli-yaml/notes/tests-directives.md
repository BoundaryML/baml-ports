# tests/directives.ts → baml_src/tests/directives.baml

## Results

`$B test -i "root::directives::*"`: **8 passed, 0 failed, 0 skipped** (8 tests; the `for (const tag of ['%TAG', '%YAML'])` loop is unrolled into `incomplete %TAG directive` / `incomplete %YAML directive`).

## Library fixes

None needed.

## Notes / BAML gaps

- BAML backtick literals are auto-dedented and lose their trailing newline, so `source(`…`)` needs `+ "\n"` where upstream's template tag keeps the final newline (`create & stringify`). See tests-doc-parse.md, gap 3.
- `doc.directives` is nullable and `doc.get(i)` returns `SeqItem?`, so setting `.tag` / `.tags[...]` needs a narrowing helper (`tdir_scalar`) or `?? {}` binding; no `!` / `as Scalar`.
