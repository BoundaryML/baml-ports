# tests/compat.ts → baml_src/tests/compat.baml

## Results

`$B test -i "root::compat::*"`: **9 passed, 0 failed, 0 skipped** (9 tests).

## Library fixes

None needed.

## Notes / BAML gaps

None new; straightforward mapping (`parseDocument(src, Options { compat: …, schema: …, version: … })`, `stringify(v, null, Options {…})`).
