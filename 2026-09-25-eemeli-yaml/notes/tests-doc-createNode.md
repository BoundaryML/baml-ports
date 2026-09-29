# tests/doc/createNode.ts → baml_src/tests/doc/createNode.baml

## Results

`$B test -i "root::doc/createNode::*"`: 37 tests: **36 passed, 1 failed, 0 skipped**.

- Failing: `objects › createNode({ x: true, y: undefined })`. This is a JS/BAML semantic difference (b). BAML has no `undefined` distinct from `null`, so `{ y: undefined }` is `{ y: null }`. `YAMLMap.create` keeps the pair (upstream drops `undefined` values unless `keepUndefined`), so the map has 2 entries instead of 1. `createNode(undefined)` is ported as `createNode(null)`, which gives the same result.

## Library fixes

- `src/js.baml` `js_identical`: typed maps and arrays (e.g. the literal `{ "baz": baz }`, whose type is `map<string, map<string, int>>`) do not match `map<string, unknown>` in a `match`, because generics are invariant. They fell through to `js_same`, i.e. structural `==`. Two distinct but equal literals were therefore treated as the same object, and `NodeCreator` emitted a spurious alias (`further relatives` produced `bar: &a1` … `fo: *a1`). The fix probes typed containers through their reflected element type: it re-inserts an existing element under a probe key, or pushes a copy of the last element, then undoes the change. Empty typed containers cannot be probed and are treated as distinct.

## New BAML gaps / pain points

1. **wrong-result hazard: invariant generics make "catch-all" `match` arms silently wrong.** `match (v) { let m: map<string, unknown> => …, _ => fallback }` sends a `map<string, map<string, int>>` value to the fallback without any warning. Here the fallback was structural equality, which gives the opposite of identity. Minimal repro:
   ```baml
   let baz = { "a": 1 };
   let x = { "baz": baz };
   let y = { "baz": baz };
   match (x) { let m: map<string, unknown> => "object", _ => "other" }  // "other"
   ```
   This extends PORTING_NOTES #9. The consequence here was a wrong result, not only boilerplate.
2. **pain-point:** identity probing needs a value of the element type, so an empty `int[]`/`map<string, int>` cannot be identity-tested at all (PORTING_NOTES #10).
