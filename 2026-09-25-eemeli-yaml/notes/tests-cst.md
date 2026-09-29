# tests/cst.ts → baml_src/tests/cst.baml

## Results

`$B test -i "root::cst::*"`: **9 passed, 0 failed, 0 skipped** (9 total, same as upstream).

All tests ported 1:1 (same names, order, assertions). Mapping notes:

- `Array.from(new Parser().parse(src))` → `new_parser(null).parse(src)` (already returns `Token[]`).
- `CST.visit` paths are `CstPathItem { field, index }[]`; the "Visit paths in order" test converts them to `[field, index]` tuples (`tcst_path_tuples`) before `toMatchObject`, so the expected literal is identical to upstream.
- `CST.resolveAsScalar(tok)` → `resolveAsScalar(tok, true, null)` (upstream default `strict = true`).
- `parent.items.splice(idx, 0, {...})` → `titems(parent).insert(ci, idx)` with `ci = collection_item(item.start.slice(...))`.
- `{ afterKey: !!item.key }` → `SetScalarValueContext { afterKey: item.key != null }`.

## Library fixes

None needed.

## New BAML gaps / pain points

- pain-point: `array.insert(value, index)` takes the value first (opposite of most languages' `insert(index, value)`); with a `CollectionItem[]` the wrong order gives two confusing E0001 "mismatched types" errors rather than a hint about argument order. No `splice`.
