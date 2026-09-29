# tests/node-to-js.ts → baml_src/tests/node-to-js.baml

## Results

`$B test -i "root::node-to-js::*"`: **8 passed, 0 failed, 0 skipped** (8 total).

Porting notes:
- `doc.get(k)!.toJS(doc)`: `Document.get` returns `SeqItem?` (`Node | Pair | null`), and `Pair.toJS` needs a non-null ctx, so a helper `tn2j_to_js(item, doc)` matches on the node classes and calls `toJS(doc, null)` (throwing a TypeError for null, like JS would).
- `toThrow(ReferenceError)` → `expect_toThrowNamed(…, "ReferenceError")`.

## Fixes

None needed.

## BAML gaps

None new (same backtick note as tests-doc-comments.md applies, but these sources end in content so `source(...)` is equivalent here since only `parseDocument` consumes them).
