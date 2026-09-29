# tests/collection-access.ts → baml_src/tests/collection-access.baml

## Results

`$B test -i "root::collection-access::*"`: **29 passed, 3 failed, 0 skipped** (32 total, same count/order/names as upstream).

`beforeEach` is ported as per-test factory functions (`tca_mapDoc()`, `tca_seqDoc()`, `tca_setDoc()`, `tca_omapDoc()`), since a testset-level `let` is shared state and these tests mutate it. `map.size` → `map.size()`, `seq[i]` → `seq.items[i]` / `seq.at(i)` (out-of-range `seq[2]` uses `at()` since BAML array indexing panics), `map.has()` → `map.has(null)`, `doc.createNode()` → `doc.createNode(null, null, null)`.

Failing tests (all category (b), unavoidable JS/BAML semantic differences):

- `Map › object key equality` — `doc.get([1])` must NOT find the entry keyed by a *different* array instance `a1 = [1]`. BAML has no reference identity for arrays, so `JsMap` compares array keys structurally and the lookup succeeds.
- `Set › get` — same cause: `set.get([3])` finds the `[3]` entry structurally.
- `OMap › set` — `omap.set(3, …)` on a 2-item seq creates a JS array hole at index 2 and `toMatchObject` expects `undefined` there. BAML arrays have no holes and `SeqItem` is non-nullable, so the hole is now filled with a `Scalar(null)` (see fix below). The size (4) and the stringified output (`- null`) match upstream; only the `toMatchObject` hole check fails.

## Library / helper fixes

- `baml_src/src/nodes/YAMLSeq.baml` `_setIndex`: setting an index past the end used to *append* the value (so `doc.set(3, 6)` on `[2, 3]` put it at index 2). It now fills the gap with `Scalar.new(null)` before pushing, so the value lands at the requested index, `size()` matches JS, and the gap stringifies as `null` like a JS hole. Fixes `Document › set with seq value` (and most of `OMap › set`).
- `baml_src/tests/_expect.baml` `t_jsmap_entries` and the `toBeInstanceOf("Map")` branch: they compared `t_class_name(v) == "JsMap"`, but reflection reports the instantiated generic name (`JsMap<Pair>`, `JsMap<unknown>`), so **no `JsMap` was ever recognised** — every `_map(...)`/`_set(...)` `toMatchObject` failed. Now uses `.starts_with("JsMap")`. Fixed `Map › create`, `Set › create`, `OMap › create` (and likely tests in other files using `_map`/`_set`).

## BAML gaps / pain points

- **pain-point — `reflect.AnyClass.name()` includes generic arguments** (`JsMap<Pair>`), which makes "is this an instance of generic class X" checks by name fragile; there is no way to ask for the unapplied class name.
- Extension of PORTING_NOTES #10 (no reference identity): it also affects arrays/maps used as JS `Map` keys. Arrays carry no `_id`, so there is no way to distinguish two structurally equal array instances:
  ```baml
  function f() -> bool { let a: int[] = [1]; let b: int[] = [1]; a == b }  // true; no identity test exists
  ```
- **pain-point — `$B run -e 'root.t_class_name(root.js_map())'` crashes with a stack overflow** ("thread '<unknown>' has overflowed its stack"), while the same code inside a `test` block works. (Not reduced further.)
