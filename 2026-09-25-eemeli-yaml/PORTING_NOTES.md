# eemeli/yaml → BAML porting notes

Source: https://github.com/eemeli/yaml @ `528ef30` (cloned to `~/work-repos/yaml-baml-port-src`, since `~/work-repos/yaml` already existed).
Toolchain: `baml-cli` built from the Orca worktree `/Users/sam/baml-worktrees/baml/port-eemeli-yaml` (BoundaryML/baml @ `e215c3de2d`), see `env.sh`.

## Final summary

**Status: complete.** All 79 upstream source files under `src/` are ported (or, for pure type/export files, documented), and all 23 upstream test files are ported. The full suite runs with the locally built `baml-cli`: **3413 of 3420 tests pass, 7 fail** (`$B test`, about 40 s wall). Around 24 of the passing tests are placeholders for tests that can't be ported (listed below).

- The library is about 14.4k lines of BAML, from about 7k lines of TypeScript. The whole library type-checks, and parse, compose, toJS, stringify, CST, visit, the schemas (core/json/yaml-1.1/failsafe, custom tags), anchors/aliases/merge keys, the reviver/replacer, and the CLI all work.
- All 2089 generated checks from the official yaml-test-suite pass. The generator is `tools/gen_yaml_test_suite.py`; the runner loads and parses the case files with the ported library itself, as upstream does.
- The 7 remaining failures are all JS/BAML semantic differences or runtime limits, not library bugs:
  - `collection-access` × 2: using arrays as map/set keys relies on reference identity, and plain BAML arrays have none (#10).
  - `collection-access` × 1: JS arrays can have holes and BAML arrays can't.
  - `doc/anchors` × 1: BAML's 256-frame call-stack cap is hit before upstream's alias-count guard fires (#21).
  - `json-test-suite` × 3: the tests expect lone UTF-16 surrogates in strings, which UTF-8 BAML strings can't hold.
- The work was done by one coordinator plus seven parallel sub-agents for the test files. Per-file porting reports are in `notes/`. The testing conventions and the JS→BAML API mapping are in `TEST_PORTING_GUIDE.md`.

### Design decisions
- **One namespace:** the library and tests all live in the root namespace, with file-per-upstream-file under `baml_src/src/…` and `baml_src/tests/…`. Name clashes were resolved by renaming, e.g. `stringify` (stringify.ts) → `stringifyNode`, and `CST.visit` → `cst_visit`.
- **JS runtime shim (`src/js.baml`):**
  - `JsError`, `JsMap<V>` (arbitrary keys), `JsSet`, `JsSymbol`, `JsDate` and `JsRawJSON` stand in for the JS built-ins.
  - JS number formatting and parseInt/parseFloat/BigInt are reimplemented, as are `String()` and `JSON.stringify` (plus an indented variant).
  - `Src` gives O(1) character access (BAML string indexing is O(n)).
  - `js_identical` checks reference identity by mutating one value with a probe and seeing whether the other observes it; every node/token class also carries a random `_id`.
  - `js_undefined()` is a sentinel for JS `undefined` where upstream behaviour depends on it.
- **CST:** the CST is one "fat" `Token` class with optional fields, because the parser changes token types in place.
- **Nodes:** `type Node = Scalar | YAMLMap | YAMLSeq | YAMLSet | Alias`, with a `NodeBase` interface that has fields plus dispatching methods (`toJS`, `toString`, `cloneNode`).
  - JS subclasses (`YAMLOMap extends YAMLSeq`, `MergeKey extends Scalar`) are modelled with a `_class` discriminator field.
  - `YAMLSeq` is not an Array; its elements are in `items`.
- **Options:** the option bags are one `Options` class, with the six upstream type names as aliases. Optional positional parameters became explicit `null` arguments.
- **Tags:** a tag is a `Tag` class with function-typed fields (`test` → `testFn`, and `resolve` split into scalar/collection variants). Built-in tags have fixed ids so they can be compared by identity.
- **Lexer:** the lexer's sticky regexes are hand-written scanners. Everything else uses `baml.regex` with the backtracking engine, which is needed for lookaround.

## File mapping

### Source

| Upstream | BAML | Status |
|---|---|---|
| `src/cli.ts` | `baml_src/src/cli.baml` | ported; `--visit` module import replaced by injected loader |
| `src/compose/compose-collection.ts` | `baml_src/src/compose/compose-collection.baml` | ported |
| `src/compose/compose-doc.ts` | `baml_src/src/compose/compose-doc.baml` | ported |
| `src/compose/compose-node.ts` | `baml_src/src/compose/compose-node.baml` | ported |
| `src/compose/compose-scalar.ts` | `baml_src/src/compose/compose-scalar.baml` | ported |
| `src/compose/composer.ts` | `baml_src/src/compose/composer.baml` | ported |
| `src/compose/resolve-block-map.ts` | `baml_src/src/compose/resolve-block-map.baml` | ported |
| `src/compose/resolve-block-scalar.ts` | `baml_src/src/compose/resolve-block-scalar.baml` | ported |
| `src/compose/resolve-block-seq.ts` | `baml_src/src/compose/resolve-block-seq.baml` | ported |
| `src/compose/resolve-end.ts` | `baml_src/src/compose/resolve-end.baml` | ported |
| `src/compose/resolve-flow-collection.ts` | `baml_src/src/compose/resolve-flow-collection.baml` | ported |
| `src/compose/resolve-flow-scalar.ts` | `baml_src/src/compose/resolve-flow-scalar.baml` | ported |
| `src/compose/resolve-props.ts` | `baml_src/src/compose/resolve-props.baml` | ported |
| `src/compose/util-contains-newline.ts` | `baml_src/src/compose/util-contains-newline.baml` | ported |
| `src/compose/util-empty-scalar-position.ts` | `baml_src/src/compose/util-empty-scalar-position.baml` | ported |
| `src/compose/util-flow-indent-check.ts` | `baml_src/src/compose/util-flow-indent-check.baml` | ported |
| `src/doc/Document.ts` | `baml_src/src/doc/Document.baml` | ported |
| `src/doc/NodeCreator.ts` | `baml_src/src/doc/NodeCreator.baml` | ported |
| `src/doc/anchors.ts` | `baml_src/src/doc/anchors.baml` | ported |
| `src/doc/applyReviver.ts` | `baml_src/src/doc/applyReviver.baml` | ported |
| `src/doc/directives.ts` | `baml_src/src/doc/directives.baml` | ported |
| `src/errors.ts` | `baml_src/src/errors.baml` | ported |
| `src/index.ts` | `baml_src/src/index.baml` | export barrel; documented (no module exports in BAML) |
| `src/log.ts` | `baml_src/src/log.baml` | ported (warnings go to stderr; not interceptable) |
| `src/nodes/Alias.ts` | `baml_src/src/nodes/Alias.baml` | ported |
| `src/nodes/Pair.ts` | `baml_src/src/nodes/Pair.baml` | ported |
| `src/nodes/Scalar.ts` | `baml_src/src/nodes/Scalar.baml` | ported |
| `src/nodes/YAMLMap.ts` | `baml_src/src/nodes/YAMLMap.baml` | ported |
| `src/nodes/YAMLSeq.ts` | `baml_src/src/nodes/YAMLSeq.baml` | ported |
| `src/nodes/YAMLSet.ts` | `baml_src/src/nodes/YAMLSet.baml` | ported |
| `src/nodes/addPairToJSMap.ts` | `baml_src/src/nodes/addPairToJSMap.baml` | ported |
| `src/nodes/identity.ts` | `baml_src/src/nodes/identity.baml` | ported |
| `src/nodes/toJS.ts` | `baml_src/src/nodes/toJS.baml` | ported |
| `src/nodes/types.ts` | `baml_src/src/nodes/types.baml` | ported |
| `src/nodes/util-clone-map-or-set.ts` | `baml_src/src/nodes/util-clone-map-or-set.baml` | ported (clone logic lives in each class) |
| `src/options.ts` | `baml_src/src/options.baml` | ported |
| `src/parse/cst-scalar.ts` | `baml_src/src/parse/cst_scalar.baml` | ported |
| `src/parse/cst-stringify.ts` | `baml_src/src/parse/cst_stringify.baml` | ported |
| `src/parse/cst-visit.ts` | `baml_src/src/parse/cst_visit.baml` | ported |
| `src/parse/cst.ts` | `baml_src/src/parse/cst.baml` | ported |
| `src/parse/lexer.ts` | `baml_src/src/parse/lexer.baml` | ported |
| `src/parse/line-counter.ts` | `baml_src/src/parse/line_counter.baml` | ported |
| `src/parse/parser.ts` | `baml_src/src/parse/parser.baml` | ported |
| `src/public-api.ts` | `baml_src/src/public-api.baml` | ported |
| `src/rawjson.d.ts` | `baml_src/src/js.baml (JsRawJSON) + note in src/index.baml` | ported (type decl → class model) |
| `src/schema/Schema.ts` | `baml_src/src/schema/Schema.baml` | ported |
| `src/schema/common/map.ts` | `baml_src/src/schema/common/map.baml` | ported |
| `src/schema/common/null.ts` | `baml_src/src/schema/common/null.baml` | ported |
| `src/schema/common/seq.ts` | `baml_src/src/schema/common/seq.baml` | ported |
| `src/schema/common/string.ts` | `baml_src/src/schema/common/string.baml` | ported |
| `src/schema/core/bool.ts` | `baml_src/src/schema/core/bool.baml` | ported |
| `src/schema/core/float.ts` | `baml_src/src/schema/core/float.baml` | ported |
| `src/schema/core/int.ts` | `baml_src/src/schema/core/int.baml` | ported |
| `src/schema/core/schema.ts` | `baml_src/src/schema/core/schema.baml` | ported |
| `src/schema/json-schema.ts` | `baml_src/src/schema/json-schema.baml` | types only (unused upstream); keyword fields renamed |
| `src/schema/json/schema.ts` | `baml_src/src/schema/json/schema.baml` | ported |
| `src/schema/tags.ts` | `baml_src/src/schema/tags.baml` | ported |
| `src/schema/types.ts` | `baml_src/src/schema/types.baml` | ported |
| `src/schema/util-primitive-key.ts` | `baml_src/src/schema/util-primitive-key.baml` | ported |
| `src/schema/yaml-1.1/binary.ts` | `baml_src/src/schema/yaml-1.1/binary.baml` | ported |
| `src/schema/yaml-1.1/bool.ts` | `baml_src/src/schema/yaml-1.1/bool.baml` | ported |
| `src/schema/yaml-1.1/float.ts` | `baml_src/src/schema/yaml-1.1/float.baml` | ported |
| `src/schema/yaml-1.1/int.ts` | `baml_src/src/schema/yaml-1.1/int.baml` | ported |
| `src/schema/yaml-1.1/merge.ts` | `baml_src/src/schema/yaml-1.1/merge.baml` | ported |
| `src/schema/yaml-1.1/omap.ts` | `baml_src/src/schema/yaml-1.1/omap.baml` | ported |
| `src/schema/yaml-1.1/pairs.ts` | `baml_src/src/schema/yaml-1.1/pairs.baml` | ported |
| `src/schema/yaml-1.1/schema.ts` | `baml_src/src/schema/yaml-1.1/schema.baml` | ported |
| `src/schema/yaml-1.1/set.ts` | `baml_src/src/schema/yaml-1.1/set.baml` | ported |
| `src/schema/yaml-1.1/timestamp.ts` | `baml_src/src/schema/yaml-1.1/timestamp.baml` | ported |
| `src/stringify/foldFlowLines.ts` | `baml_src/src/stringify/foldFlowLines.baml` | ported |
| `src/stringify/stringify.ts` | `baml_src/src/stringify/stringify.baml` | ported |
| `src/stringify/stringifyComment.ts` | `baml_src/src/stringify/stringifyComment.baml` | ported |
| `src/stringify/stringifyDocument.ts` | `baml_src/src/stringify/stringifyDocument.baml` | ported |
| `src/stringify/stringifyNumber.ts` | `baml_src/src/stringify/stringifyNumber.baml` | ported |
| `src/stringify/stringifyPair.ts` | `baml_src/src/stringify/stringifyPair.baml` | ported |
| `src/stringify/stringifyString.ts` | `baml_src/src/stringify/stringifyString.baml` | ported |
| `src/test-events.ts` | `baml_src/src/test-events.baml` | ported |
| `src/util.ts` | `baml_src/src/util.baml` | re-export barrel; tag aliases |
| `src/visit.ts` | `baml_src/src/visit.baml` | ported |

### Tests

| Upstream | BAML | Pass | Fail | Unportable placeholders |
|---|---|---|---|---|
| `tests/yaml-test-suite.ts` | `baml_src/tests/yaml-test-suite.baml` + generated | 2089 | 0 | 0 (3 skipped upstream too) |
| `tests/json-test-suite.ts` | `baml_src/tests/json-test-suite.baml` + generated | 337 | 3 | 7 (skipped upstream too) |
| `tests/doc/stringify.ts` | `baml_src/tests/doc/stringify.baml` | 243 | 0 | 10 (boxed primitives, lone surrogates) |
| `tests/doc/types.ts` | `baml_src/tests/doc/types.baml` | 122 | 0 | 2 (nested customTags arrays, adapted) |
| `tests/doc/YAML-1.2.spec.ts` | `baml_src/tests/doc/YAML-1.2.spec.baml` | 117 | 0 | 0 |
| `tests/doc/YAML-1.1.spec.ts` | `baml_src/tests/doc/YAML-1.1.spec.baml` | 1 | 0 | 0 |
| `tests/doc/parse.ts` | `baml_src/tests/doc/parse.baml` | 97 | 0 | 1 (Buffer as source) |
| `tests/doc/comments.ts` | `baml_src/tests/doc/comments.baml` | 85 | 0 | 0 |
| `tests/doc/errors.ts` | `baml_src/tests/doc/errors.baml` | 52 | 0 | 3 (spy on process.emitWarning) |
| `tests/doc/anchors.ts` | `baml_src/tests/doc/anchors.baml` | 44 | 1 | 1 (property setter) |
| `tests/doc/createNode.ts` | `baml_src/tests/doc/createNode.baml` | 37 | 0 | 0 |
| `tests/doc/foldFlowLines.ts` | `baml_src/tests/doc/foldFlowLines.baml` | 35 | 0 | 0 |
| `tests/visit.ts` | `baml_src/tests/visit.baml` | 36 | 0 | 0 |
| `tests/cli.ts` | `baml_src/tests/cli.baml` | 33 | 0 | 0 |
| `tests/collection-access.ts` | `baml_src/tests/collection-access.baml` | 29 | 3 | 0 |
| `tests/cst.ts` | `baml_src/tests/cst.baml` | 9 | 0 | 0 |
| `tests/compat.ts` | `baml_src/tests/compat.baml` | 9 | 0 | 0 |
| `tests/directives.ts` | `baml_src/tests/directives.baml` | 8 | 0 | 0 |
| `tests/lexer.ts` | `baml_src/tests/lexer.baml` | 8 | 0 | 0 |
| `tests/node-to-js.ts` | `baml_src/tests/node-to-js.baml` | 8 | 0 | 0 |
| `tests/clone.ts` | `baml_src/tests/clone.baml` | 5 | 0 | 0 |
| `tests/line-counter.ts` | `baml_src/tests/line-counter.baml` | 4 | 0 | 0 |
| `tests/rawJSON.ts` | `baml_src/tests/rawJSON.baml` | 4 | 0 | 0 |
| `tests/properties.ts` | `baml_src/tests/properties.baml` | 1 | 0 | 0 (fast-check → seeded hand-written generators) |
| `tests/_utils.ts` | `baml_src/tests/_utils.baml` | – | – | helper |
| `tests/_setup.ts` | `baml_src/tests/_expect.baml` | – | – | vitest equality setup → own expect library |
| `tests/artifacts/**` | read in place via `readArtifact()` | – | – | data |

Pass counts include the placeholders. A placeholder is a test with the upstream name whose body documents why the upstream test can't be ported.

## BAML language / toolchain gaps, bugs and pain points

Severity key: **crash** > **wrong-result** > **spurious-compile-error** > **missing-feature** > **pain-point**.

### Flow typing / narrowing

1. **spurious-compile-error — `&&` does not narrow its right operand.**
   ```baml
   class T { type: string }
   function a1(t: T?) -> bool { t != null && t.type == "x" }
   // error[E0007]: type `T | null` has no member `type`
   ```
   Same inside `if (t != null && t.type == "x") { … }`. Workaround: nested `if`, or `t?.type == "x"`.

2. **missing-feature — field accesses are never narrowed.**
   ```baml
   class T { items: int[]? }
   function f(t: T) -> null { if (t.items != null) { t.items.push(1); } null }
   // error[E0007]: type `int[] | null` has no member `push`
   ```
   Also applies to calling a nullable function-typed field (`if (t.resolve != null) { t.resolve(x) }` → E0006 "is not a function"). Workaround: copy to a local first (`let items = t.items; if (items != null) …`) or `t.items?.push(1)`. This is the single biggest source of boilerplate in this port: the YAML CST and node classes are full of optional fields.

3. **spurious-compile-error — a local captured by a lambda loses null-narrowing everywhere in the function**, even before the lambda and even though it is never reassigned.
   ```baml
   class T { type: string }
   function c1(e: T?, xs: T[]) -> bool {
     let token = e;
     if (token == null) { return false; }
     let a = token.type;                                // error E0007 here too
     xs.every((st: T) -> bool { st.type == token.type }) // and here
   }
   ```
   Workaround: re-bind to a fresh non-null local (`let tok: T = token;`) and capture that.

4. **missing-feature — no non-null assertion (`x!`).** Combined with 1–3 this forces many `let x = y.z; if (x == null) { … }` dances or helper accessors (`titems(t)`, `tend(t)` in `cst.baml`).

### Syntax

5. **spurious-compile-error — `test` is reserved and cannot be a class field name.** `class Tag { test: ((string) -> bool throws never)? }` fails to parse (`expected '}', found test`). The YAML `ScalarTag.test` field is renamed `testFn`.

6. **pain-point — ASI-style hazard: a statement starting with `[` after a block is parsed as an index expression.**
   ```baml
   if (c) { i += 1; }
   [a, b, c]          // parsed as `{ … }[a, b, c]` → "expected ']' found ','"
   ```
   Workaround: `return [a, b, c];` or bind to a local first.

7. **pain-point — `unknown`-typed class fields are required in class literals** (a `T?` field defaults to `null` when omitted, but `extra: unknown` must be spelled out even though `unknown` includes `null`). Declaring it as `unknown?` works around it.

8. **missing-feature — no module-level constants.** JS `const FOO = …` at module scope becomes a zero-argument function (`function BOM() -> string { … }`).

### Types / runtime model

9. **pain-point — invariant generics make "is this any array?" impossible with `match`.** `match (v) { let a: unknown[] => … }` does not match an `int[]` value (by design: `int[]` is not a subtype of `unknown[]`). A JS-style dynamic value model (`Array.isArray`, iterating any array/object) needs `reflect.Type.of_value(v).as_array()` + a scoped `type E = unreflect(…)` binding + a second `match` — see `js_as_array` in `src/js.baml`. It works, but is heavy for what JS does with `Array.isArray`.

10. **missing-feature — no reference identity (`===`).** BAML `==` is structural; there is no `same(a, b)` / pointer equality. The original relies on identity everywhere (`node === this` in `Alias.resolve`, `Map<Node, …>` anchors, `st === valueProps.found`, `WeakMap`s). Workaround: every identity-bearing class carries an `_id: int` drawn from `baml.random.SystemRandom` at construction, and `js_same()` compares ids.

11. **pain-point — BAML truthiness differs from JS in a way that silently changes behaviour:** empty arrays/maps are falsy in BAML, truthy in JS. The YAML parser constantly does `if (it.sep)` where `sep` may be `[]`; a mechanical port of those checks compiles fine but is wrong. Every such check had to be rewritten as `!= null`.

### Stdlib

12. **pain-point (performance) — `string.at(i)` and `string.slice(a, b)` are O(index)** (codepoint indexing over UTF-8, no index cache). A character-by-character lexer over a 40k-char string: `.at(i)` loop ~3.2s, `.slice(i, i+5)` loop ~6.5s (quadratic), `to_code_points()` + `int[]` indexing ~0.3s. The lexer works over a pre-split `chars()`/`to_code_points()` array (`Src` class in `src/js.baml`).

13. **missing-feature — no sticky / positional regex matching** (no `lastIndex`, no `match_at(haystack, pos)`). The lexer's five `/…/y` regexes were re-implemented as hand-written scanners. (Matching an anchored regex against `haystack.slice(pos)` would be O(n) per call, see 12.)

14. **pain-point — float formatting is not JS-compatible** (expected, but worth noting for ports): `1.0.to_string()` is `"1.0"`, `1e21` renders as `"1000000000000000000000.0"`, `1e-7` as `"0.0000001"`. `js_number_to_string` in `src/js.baml` re-derives JS `Number#toString` output.

15. **wrong-result (silent) — string literals do not support `\xNN`, `\uNNNN` or `\u{…}` escapes, and unknown escapes are kept verbatim without any diagnostic.** Only `\n \t \r \0 \b \v \f \\ \"` are decoded (`baml_base/src/escape.rs`).
    ```baml
    // baml-cli run -e '[ "\u{8}".length(), "\u0008".length(), "\x08".length(), "\u{FEFF}".length() ]'
    // → [5, 6, 4, 8]   (expected [1, 1, 1, 1])
    ```
    This silently broke the port's BOM / control-character token constants and the YAML `\e \a \N \_ \L \P` escape table until caught by yaml-test-suite case G4RS. Workaround: `chr(cp)` = `baml.String.from_code_points([cp])` (fallible, so it needs a `catch`). At minimum an unknown escape should be a compile error.

16. **pain-point — `self` cannot be used as a parameter name of a free function** (`function f(self: YAMLSeq)` → parse error). Harmless, but ports of "method moved to a free function" code trip over it.

17. **pain-point — keywords as identifiers:** besides `test`, JSON-Schema-style field names `enum`, `const`, `then`, `not`, `type`, `default`(?) etc. needed renaming in the `json-schema.ts` type port; a local variable named `test` is also rejected.

18. **pain-point — no optional positional parameters.** A defaulted parameter must be passed by name (`f(1, b = 2)`), so JS APIs like `map.set(key, value, options?)` / `doc.toString(options?)` became explicit-`null` arguments at every call site (`doc.toString(null)`) or split methods (`set` / `setWithOptions`).

19. **pain-point — one flat namespace per directory tree means name collisions between modules** (`stringify` in `public-api.ts` vs `stringify/stringify.ts`, `visit` vs `cst-visit`'s `visit`). BAML does report duplicates (E0011), but namespaces require `ns_` directories and fully qualified `root.ns.name` references across them, so this port keeps everything in the root namespace and renames (`stringifyNode`, `cst_visit`, …).

20. **toolchain — one compile error anywhere blocks every test in the project.** With several agents porting test files in parallel into one project, any half-written file made `baml-cli test -i <other tests>` fail. Per-test-file (or per-namespace) isolation of compile errors, or a `--keep-going` mode, would help large ports. Workaround: each worker develops in a private copy of the project.

### Things that worked well

- `reflect.AnyClass` (every class instance matches it) with `list_fields()` / `get<unknown>(name)` made generic `toMatchObject`-style test helpers possible.
- Interface fields (`interface NodeBase { comment: string? … }`) readable/writable through a union of implementing classes (`type Node = Scalar | YAMLMap | …`), and interface methods declared `throws unknown` with implementations that infer narrower throws.
- `Regex.split` includes capture groups (JS-compatible); fancy-regex backtracking engine handles the library's lookahead/lookbehind patterns.
- Closures capture locals by reference (JS-like `() => (comment = null)` callbacks port directly).
- Nested `testset`s with shared `let` state map cleanly onto vitest `describe`.
- Test execution is fast and parallel (2089 generated yaml-test-suite tests in ~40 s wall).

### Found while porting the tests (sub-agent reports in `notes/`)

21. **limit / crash — the VM call stack is capped at 256 frames** (`MAX_FRAMES` in `bex_vm/src/vm.rs`), and this can't be configured. JS allows about 10k. The composer uses about 5 frames per nesting level, so input nested about 50 levels deep (`[[[…]]]`) overflows. Upstream's alias-bomb test also overflows before upstream's own guard triggers. Repro: `function rec(n: int) -> int { if (n == 0) { 0 } else { 1 + rec(n - 1) } }` — `rec(200)` is fine, `rec(300)` gives `baml.panics.StackOverflow`.

22. **wrong-result — `NaN == NaN` is `true`** (IEEE 754 and JS give `false`); verified with `let n = baml.Float.nan(); [n == n, n != n]` → `[true, false]`. A mechanical port of `x === y` changes behaviour: `stringifyNumber` wrote `.NaN` back as `.NaN` instead of `.nan` until this was worked around.

23. **wrong-result hazard — invariant generics make catch-all `match` arms silently wrong** (see #9). `match (v) { let m: map<string, unknown> => …, _ => fallback }` sends a `map<string, map<string, int>>` value to `fallback` with no warning. In this port the fallback was structural `==`, so the identity check came out wrong (spurious YAML aliases in `createNode`). A related case: a `string[]` can't be passed to an `unknown[]` parameter, so helpers have to be generic.

24. **pain-point — `catch_all` does not catch panics** (`StackOverflow`, …); you need `catch_all_panics`. A straight port of JS `try { … } catch {}` silently loses behaviour: here, turning deep nesting into a `RESOURCE_EXHAUSTION` error.

25. **pain-point — `||` does not narrow its right operand either** (same as #1): `if (x == null || x.f)` is E0007.

26. **spurious-compile-error — `?.` strips only one level of optional:** `g.at(1)?.text` on a `(T | null)[]` is E0007, while `g[1]?.text` compiles. This is hit with `baml.regex.Match.groups`.

27. **spurious-compile-error — `Future<T, never>` is not assignable to `Future<T, unknown>`** (the error parameter is invariant), and there is no cast. A `spawn` block that can't throw can't be returned where `Future<T, unknown>` is expected. Workaround: make the body *possibly* throw.

28. **pain-point — E0097 is an error, not a warning:** annotating `throws unknown` on a function or lambda that throws something narrower, or nothing, fails to compile. That makes generated or templated code brittle, and helpers meant to "throw anything" (test callbacks) can't declare it.

29. **pain-point — multiline backtick strings are dedented and lose their leading and trailing newline** (since #4914). They therefore can't stand in for JS template literals with a `source` tag, and every ported `source\`…\`` needs `+ "\n"`.

30. **pain-point — `reflect.AnyClass.name()` includes generic arguments** (`"JsMap<Pair>"`), and there is no way to ask for the unapplied class name.

31. **toolchain — `baml-cli run -e 'root.…'` intermittently aborted with a native stack overflow** (`thread '<unknown>' has overflowed its stack`). Several agents saw it while the project was being edited concurrently. It doesn't reproduce on the final tree (`root.json_stringify(root.yaml_parse("[1, 2]"))` works), so treat it as unconfirmed.

32. **misc pain-points:**
    - `int` is 63-bit (±2^62), so 64-bit literals are compile errors.
    - `baml.fs.read` has no lossy UTF-8 mode.
    - There's no "read all of stdin".
    - `array.insert(value, index)` takes its arguments in the reverse of the usual order, and the mismatch errors give no hint.
    - Named arguments use `=`, but the "must be passed by name" error doesn't say so.
    - `baml.random` has no ranges, floats, choice or property-testing support.
    - No dynamic imports (the CLI's `--visit` needs an injected loader).
    - Static `test` blocks mean table-driven test files need an external generator script.
    - Strings can't hold lone surrogates (expected for UTF-8, but it's a porting difference from JS).
