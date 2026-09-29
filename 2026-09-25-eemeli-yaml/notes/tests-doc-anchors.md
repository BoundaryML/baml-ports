# tests/doc/anchors.ts → baml_src/tests/doc/anchors.baml

## Results

`$B test -i "root::doc/anchors::*"`: 45 tests: **43 passed, 1 failed, 1 skipped** (the skipped test runs a trivially passing body, so the runner reports 44 passed).

- Skipped: `errors › set tag on alias`: UNPORTABLE. Upstream assigns `alias.tag = …` and expects the `Alias#tag` property setter to throw "Alias nodes cannot have tags". BAML has no property setters; `Alias.tag` is a plain field.
- Failing: `errors › circular reference` (`&A { <<: *A, B: b }`): `doc.toJS()` should throw "Excessive alias count…" once the alias count passes `maxAliasCount` (default 100). Upstream recurses about 100 merge levels deep before throwing, with about 4 BAML frames per level (YAMLMap.toJS → addPairToJSMap → merge addToJSMap → mergeValue → …). The BAML VM caps the call stack at `MAX_FRAMES = 256` (`bex_vm/src/vm.rs:118`), so it panics with `baml.panics.StackOverflow` first. The other assertions in this test pass: `maxAliasCount: 0/1/2` throw ReferenceError, `maxAliasCount: 40` throws the expected "Excessive alias count" error, and stringify round-trips. This is category (c), a toolchain limit.

## Library / test-helper fixes

- `tests/_expect.baml` `t_class_name`: strips generic arguments. Reflection reports a `JsMap<Pair>` as `"JsMap<Pair>"`, so a YAMLMap's `values` was not recognised as a Map by `toMatchObject`/`toEqual`. This fixed `repeated Array/Date in createNode`. Another agent made an equivalent `starts_with("JsMap")` fix at the same time; the two are compatible.
- `tests/_expect.baml` `t_equal`: added cycle handling. Identical objects now count as equal, and a pair already being compared further up the stack is assumed equal, as vitest's `equals` does. Before this, `toEqual` on circular values (`merge with circular reference`) recursed until stack overflow. The comparison now lives in `t_equal_rec`/`t_equal_body` with a `TEqSeen` stack; `t_equal`'s signature is unchanged.
- `src/js.baml` `js_identical`: see tests-doc-createNode.md. Typed maps/arrays used to fall back to structural `==`.

## New BAML gaps / pain points

1. **limit: the call stack is capped at 256 frames** (`MAX_FRAMES` in `bex_vm`), and this is not configurable. JS allows about 10k frames. Any faithful port of a recursive algorithm that JS runs a few hundred frames deep hits it: here the merge-key alias bomb guard, and deep `toEqual` recursion before the cycle fix. Repro:
   ```baml
   function rec(n: int) -> int { if (n == 0) { 0 } else { 1 + rec(n - 1) } }
   test t { rec(300) }   // baml.panics.StackOverflow (rec(200) is fine)
   ```
2. **pain-point:** reflection's `AnyClass.name()` includes generic arguments (`"JsMap<Pair>"`), so name-based dispatch on generic classes has to strip them.
