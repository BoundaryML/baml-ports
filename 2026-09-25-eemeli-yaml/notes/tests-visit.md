# tests/visit.ts → baml_src/tests/visit.baml

## Results

`$B test -i "root::visit::*"`: **36 passed, 0 failed, 0 skipped** (36 total = 18 tests × {`visit()`, `visitAsync()`}), same names and order as upstream.

Port notes:
- Upstream loops one `describe` body over `[visit, visitAsync]`. BAML can't abstract over the two functions (different visitor types), so the file has two testsets `visit()` and `visitAsync()` with the same 18 tests. They were produced from one template by a throwaway script; the committed file is plain BAML.
- In the `visitAsync()` suite every visitor returns a `baml.future.Future` made with `spawn { … }` (helper `tvis_later`), which exercises visitAsync's await path. Upstream's `vi.fn()` visitors return `undefined` synchronously there.
- `expect.any(Document|YAMLMap|YAMLSeq|Pair)` becomes the markers `"DOC"/"MAP"/"SEQ"/"PAIR"`. Recorded paths are turned into markers, and a recorded node is turned into its marker when the expected value is a marker (`tvis_expect_calls`).
- `vi.fn()` becomes `mock_calls()` + `tvis_rec`. `{ Map: fn, Pair: fn, … }` becomes `tvis_fns(fn, alias)` / `tvis_afns(fn, alias)`, which wrap one generic visitor function into each typed field.
- `await expect(visitAsync(...)).rejects.toMatchObject({ message })` becomes `expect_toThrow` + `expect_toMatchObject(err, { "message": … })`.

## Library / helper fixes

- `src/visit.baml` `visitAsync`: only accepted a function visitor. Upstream also accepts the object form, so I added `class AsyncVisitorFns`, `type AsyncVisitor = AsyncVisitorFn | AsyncVisitorFns`, and `initAsyncVisitor`/`callAsyncVisitor`, which mirror `initVisitor`/`callVisitor`.
- `src/visit.baml` `replaceNode`: `path[path.length() - 1]` panicked with `IndexOutOfBounds(-1)` on an empty path, i.e. when replacing the root of a non-Document visit. In JS that index is `undefined`, which leads to the "Cannot replace node with scalar parent" error. It now binds `null` when the path is empty.
- `tests/_expect.baml` `t_match`: an empty expected object `{}` now matches any value, including `null`, which is what vitest does (its `subsetEquality` over zero keys is vacuously true). Upstream relies on this with `[1, { key: {}, value: {} }, …]` for a pair whose value is `null` (`{ one: 1, two }`).

## New BAML gaps / pain points

1. **spurious-compile-error (or missing-feature) — `Future<T, never>` is not assignable to `Future<T, unknown>`.** The error type parameter is invariant, so a `spawn` block that can't throw can't be returned where a `Future<T, unknown>` is expected. There is no cast either: annotating the let doesn't help.
   ```baml
   type R = int | null
   function f() -> baml.future.Future<R, unknown> {
     let fu: baml.future.Future<R, unknown> = spawn { let y: R = 1; y };
     fu
   }
   // error[E0001]: expected `baml.future.Future<R, unknown>`, found `baml.future.Future<R, never>`
   ```
   Workaround: make the spawn body *possibly* throw `unknown` by calling `function rethrow(e: unknown) -> null { if (e != null) { throw e; } null }` with `null`. The same invariance applies to the value type: `spawn { null }` is `Future<null, never>`, not `Future<R, …>`, so the value must be bound to an `R`-typed local first.
2. **pain-point — E0097 is an error, not a warning.** A lambda annotated `throws unknown` whose body can't throw fails to compile ("`throws unknown` is unnecessary"). An imprecise one fails as well ("only throws `string`"). This makes template/generated code brittle: the same lambda text is legal or illegal depending on whether its body happens to throw. It also blocks the obvious fix for gap 1 (`function thr() -> null throws unknown { … throw "x" … }` is rejected as imprecise).
