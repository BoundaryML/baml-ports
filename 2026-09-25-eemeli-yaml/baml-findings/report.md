# Post-mortem: porting eemeli/yaml to BAML

Report written 2026-09-27. Covers Orca run `run_3689c3c3cac4`, terminal `term_74ee531f-0ed8-48b8-863c-3fe89f2d5b21` ("eemeli/yaml to BAML port").

- **Original:** eemeli/yaml at `528ef30` ("feat: Include context arg in reviver calls + serialize raw JSON values (#726)"). The agent cloned it to `<local>/work-repos/yaml-baml-port-src` because `<local>/work-repos/yaml` already existed. Both are at the same commit.
- **Port:** `<local>/work-repos/yaml-baml`, 6 commits from `fa3a74c` to `3e3c1bb`, clean tree.
  - `<local>/tmp/yaml-baml-main` is an older rsync'd snapshot the coordinator used as a staging copy. It is not a git repo; it has a `baml_src/scratch` dir and no `src/cli.baml`. Ignore it.
- **Toolchain:** `baml-cli` 0.20.1, a **debug** build from `<local>/baml-worktrees/port-eemeli-yaml` (branch `sxlijin/port-eemeli-yaml`) at `e215c3de2d`. It was copied to the agent's scratchpad (`env.sh`). That worktree has no local changes; the compiler was not modified. `origin/canary` is still at `e215c3de2d` today, so nothing has been fixed upstream since the port.
- **Porting agent's session:** `<local>/transcripts/port-eemeli-yaml/9e8d82d5-bffe-4c7b-b704-36d8072cbe66.jsonl`, plus 11 sub-agent transcripts in `…/subagents/`.
  - The agent is finished ("Baked for 1h 1m 33s · done 1:14 PM").
  - The prompt "file BAML issues for the top gaps" is sitting **unsent** in the terminal's input box (`draft:` in `orca terminal read --screen`). No issues were filed (see §4).
- **Orca bookkeeping mismatch:** Orca task `task_d56748431644` ("Port eemeli/yaml to BAML") is still `status: ready`, has no result, and its spec names a different worktree (`port-yaml-js`, which doesn't exist) and `PORTING.md`. The actual work ran in the `port-eemeli-yaml` terminal from a separate, slightly different prompt that asked for `PORTING_NOTES.md`.

Labels used in this report:
- **[measured]**: I re-ran it for this report, from copies in my scratchpad.
- **[agent claim]**: taken from `PORTING_NOTES.md`, `notes/*.md` or the transcripts without re-checking.

## 1. Summary

- **What was ported.** All 79 files under upstream `src/` [agent claim; mapping table in `PORTING_NOTES.md`, spot-checked]. That covers:
  - the lexer, the CST parser, the CST stringify and visit code, and the line counter;
  - the composer, including every `resolve-*` module;
  - the Document, Alias, Pair, Scalar, YAMLMap, YAMLSeq and YAMLSet nodes;
  - the schemas: core, json, yaml-1.1 and failsafe, plus custom tags, `!!binary`, `!!omap`, `!!pairs`, `!!set`, `!!timestamp` and merge keys;
  - stringify, including `foldFlowLines`;
  - `visit`, the public API (`parse`, `parseDocument`, `parseAllDocuments`, `stringify`), `test-events`, and the CLI (`src/cli.baml`).

  Pure type and export-barrel files (`index.ts`, `util.ts`, `json-schema.ts`) are documented or reduced to type declarations. A 1,006-line JS runtime shim, `baml_src/src/js.baml`, supplies `JsMap`, `JsSet`, `JsError`, JS number formatting, `JSON.stringify`, `parseInt`, identity probes and an `undefined` sentinel. There are no TODOs left in `baml_src/src` [measured, `grep TODO`].
- **Output fidelity [measured].** For both benchmark inputs (upstream's `prettier-circleci-config.yml` artifact and a 39 KB synthetic document), `stringify(parse(x))` from the BAML port is byte-for-byte identical to upstream's output under Node.
- **Test pass rate [measured].**

| Suite | Upstream (vitest 4.1.11, Node 22.23.2) | BAML port (`baml-cli test`) |
|---|---|---|
| All 24 test files | 3,413 passed, 11 skipped (3,424 total) | **3,413 passed, 7 failed (3,420 total)** |
| yaml-test-suite | 2,089 passed, 4 skipped | 2,089 / 2,089 (the 4 upstream-skipped cases are not generated) |
| json-test-suite | 333 passed, 7 skipped | 337 passed (includes 7 placeholders for the upstream skips), 3 failed |
| doc/anchors | 45 | 44 passed, 1 failed |
| collection-access | 32 | 29 passed, 3 failed |
| Every other file | same count as port | same count, all pass |

- **Caveat on "3,413 passed".** The BAML figure includes **23 placeholder tests**: tests with the upstream name whose body only documents why it can't be ported, and which pass trivially.
  - 16 are marked `// UNPORTABLE`: 10 in doc/stringify (boxed primitives, lone surrogates), 3 in doc/errors (spying on `process.emitWarning`), 1 in doc/parse (Buffer input) and 1 in doc/anchors (property setter). One further `UNPORTABLE` marker in the YAML-1.2 spec is a dropped assertion inside a test that otherwise runs.
  - 7 are `tjts_skipped` json-test-suite cases that upstream also skips.

  So of the 3,413 tests upstream actually runs and passes, the port **really runs and passes about 3,390 (99.3%)**, **fails 7 (0.2%)**, and **stubs about 16 (0.5%)**.
- **The 7 failures [measured list; agent's explanation].** All come from language or runtime limits, not from porting mistakes:
  - `collection-access › Map › object key equality` and `Set › get` use arrays as map or set keys by reference identity; BAML has no reference identity.
  - `collection-access › OMap › set` depends on JS array holes.
  - `doc/anchors › errors › circular reference`: the alias bomb overflows BAML's 256-frame VM stack before upstream's own alias-count guard fires (§4, bug 4).
  - 3 json-test-suite `string_*_escaped_invalid_codepoint(s)` cases need lone UTF-16 surrogates, which UTF-8 BAML strings can't hold.
- **The tests can fail.** The YAML-spec sub-agent did mutation testing: it changed expected values in a private copy and confirmed each test failed [agent claim, `notes/tests-doc-YAML-spec.md`]. The yaml-test-suite runner also caught a real porting bug, case G4RS (the string-escape bug, §4 bug 1). All BAML assertions go through `_expect.baml` helpers that throw, and none of the port's tests rely on a trailing boolean expression. That matters because of §4 bug 6.
- **Effort.** One autonomous session from 19:13Z to 20:14Z on 2026-09-26: **61 minutes wall-clock**.
  - The coordinator wrote the entire library itself in about 40 minutes: parse layer at `fa3a74c`, 12:28 PDT; the rest at `4ad55dc`, 12:51 PDT.
  - It then fanned the test files out to 7 background sub-agents, 4 of which forked further (11 transcripts in total). Those ran from 19:56Z to 20:10Z.
  - Output tokens: about 336k in the coordinator and about 370k across sub-agents (deduplicated by message id; the forks may double-count some shared context). The model was `claude-opus-5-5` throughout.

## 2. Lines of code

**Method.** `tokei`, `scc` and `cloc` aren't installed, so I used a small Python counter: `loc_eemeli.py` in my scratchpad (`…/scratchpad/eemeli-yaml/`). It counts non-blank lines that are not `//` or `/* */` comments. The same rules apply to `.ts` and `.baml`. For the tooling row I used `wc -l`.

| Category | Original (TypeScript) | BAML port | Ratio |
|---|---|---|---|
| Library (`src/**`, 79 files → 78 files) | 8,905 | 11,186 | 1.26× |
| JS runtime shim (`src/js.baml`, port-only) | — | 1,006 | — |
| **Library total** | **8,905** | **12,192** | **1.37×** |
| Tests, hand-written (`tests/**/*.ts`, 26 files → 26 `.baml`) | 9,817 | 10,540 | 1.07× |
| Tests, generated (`*.generated.baml` for yaml-test-suite and json-test-suite) | — (data-driven at runtime) | 3,241 | — |
| Tooling (generators `tools/*.py`, `tools/*.cjs`; `wc -l`) | — | 212 | — |
| Comments in library | 1,205 | 1,340 (incl. shim) | |

Raw `wc -l` for the BAML library is 14,373. That is the "14.4k" in `PORTING_NOTES.md`. Its "about 7k lines of TypeScript" undercounts upstream, which is 8.9k code lines or 10.9k by `wc -l`.

Per-file code lines, TS → BAML:

| File | TS | BAML | Ratio |
|---|---|---|---|
| `parse/parser` | 871 | 1,255 | 1.44× |
| `parse/lexer` | 517 | 847 | 1.64× |
| `nodes/YAMLMap` | 287 | 421 | 1.47× |
| `stringify/stringify` | 179 | 273 | 1.53× |
| `schema/yaml-1.1/timestamp` | 104 | 192 | 1.85× |
| `compose/resolve-block-map` | 145 | 150 | 1.03× |
| `compose/composer` | 232 | 254 | 1.09× |
| `doc/Document` | 289 | 276 | 0.95× |

**What inflated the port:**
- **Null narrowing on fields.** Field accesses never narrow, `&&` and `||` don't narrow their right-hand side, and there is no `!` non-null operator (§4, bugs 7–9). Every `if (token.items) token.items.push(x)` in the CST parser becomes a local binding plus a check, or a helper such as `titems(t)` or `tend(t)` in `parse/cst.baml`. The agent called this "the single biggest source of boilerplate". It is the main reason `parser` and `YAMLMap` are about 1.45×.
- **No sticky regex.** The lexer's five `/…/y` regexes are hand-written character scanners, which is why the lexer is 1.64×.
- **The JS built-ins model.** `Map` with object keys, `Set`, `Symbol`, `Date`, `Number#toString`, `JSON.stringify`, `parseInt` and `BigInt` all had to be written from scratch in `js.baml` (1,006 lines). Timestamps (1.85×) need hand-written date math.
- **No module-level constants, and no optional positional parameters.** Constants become zero-argument functions. Every `doc.toString()` becomes `doc.toString(null)`, and some APIs were split, such as `set` versus `setWithOptions`.
- **No inheritance.** `YAMLOMap extends YAMLSeq` and `MergeKey extends Scalar` are modelled with a `_class` discriminator plus per-class `cloneNode`, `toJS` and `toString` dispatch.
- **Generated tests.** `test` blocks are static, so the two data-driven suites need an external generator that emits one `test` per case (3,241 generated lines).

**What kept it close to 1×.** The composer and `Document` port almost line for line. Interfaces over a `Node` union, closures that capture by reference, `match` and nested `testset`s map well onto the TS and vitest structure. Hand-written tests stay near 1.07× because the `expect_*` helpers mirror vitest one to one.

## 3. Performance

No credible benchmark existed. The port has no benchmark code, and the transcripts contain only one string-indexing microbenchmark (§4, bug 10). So I ran my own.

**Setup.**
- Hardware: Apple M3 Max, 96 GB RAM, macOS (Darwin 25.6.0).
- The machine was shared with other agents during the runs. Load average was 4–12 for the benchmarks and about 27 for the first test-suite run. Repeated runs agreed within ±3%.
- **JS:** upstream `528ef30` built with `npm run build` (rolldown) and run as `dist/index.js` on Node 22.23.2.
- **BAML:** the port at `3e3c1bb`, run with `baml-cli run -e`.
  - I built a **release** `baml-cli` from `e215c3de2d` (the same commit): `cargo build --release -p baml_cli` with `lto="thin"` and `codegen-units=16` overridden via `--config`, so no files were modified. The build took 4 minutes.
  - For comparison I also used the agent's own **debug** binary.
- **Harness:** `bench.mjs` for Node and `baml_src/zbench/bench.baml` for BAML, which times with `baml.time.Instant`. Both are in `…/scratchpad/eemeli-yaml/`.
  - Per operation: 20 warm-up iterations on Node, then the median of 5 batches of 20. BAML: batches of 20 for the small file and 3 for the big one, 3 process runs.
  - "Cold" is the first `parse` call in the process.
- **Inputs:**
  - `prettier-circleci-config.yml`: 1.9 KB, from upstream `tests/artifacts`.
  - `synthetic.yaml`: 144 KB, 500 records mixing flow and block collections, block scalars, quoted strings, floats and an alias. Generated with a fixed seed.

**Results (ms per operation):**

| Workload | Node / V8 | BAML (release) | Ratio | BAML (agent's debug build) |
|---|---|---|---|---|
| small: `parse` | 0.20 | 20.1 | ~100× | 224 |
| small: `stringify(value)` | 0.18 | 35.6 | ~200× | 556 |
| small: `parseDocument(...).toString()` | 0.22 | 47.3 | ~210× | 642 |
| small: cold first `parse` | 5.3 | 20.5 | ~4× | |
| 144 KB: `parse` | 14.9 | 2,630 | ~175× | |
| 144 KB: `stringify(value)` | 11.9 | 11,260 | **~945×** | |
| 144 KB: `parseDocument(...).toString()` | 21.9 | 5,190 | ~237× | |
| 144 KB: cold first `parse` | 45 | 2,590 | ~57× | |

**Scaling [measured].** Using the first 125, 250 and 500 records of the synthetic file:

| Records | `parse` | `stringify(value)` |
|---|---|---|
| 125 | 0.47 s | 1.25 s |
| 250 | 1.07 s | 3.64 s |
| 500 | 2.63 s | 11.26 s |

- **`stringify(value)` is superlinear**, growing about 3× per doubling. The cause is in the port, driven by a language gap. Upstream `NodeCreator` keeps `#sourceObjects: Map<unknown, …>`, keyed by object identity. BAML has no reference identity, so the port uses an association list searched linearly with `js_identical`, which probes by mutating the object (`NodeCreator._getRef`, `baml_src/src/doc/NodeCreator.baml:67`). That makes `createNode` O(n²) in the number of objects.
- **`parse` is mildly superlinear** (about 2.3× per doubling). I did not profile it. Candidate causes are the O(n) `string.slice` and non-ASCII `string.at` (§4, bug 10).

**Test suite and dev loop [measured]:**

| | Time |
|---|---|
| Upstream `vitest run` | 2.8 s reported (5.5 s wall) |
| Port, release `baml-cli test` | 18.7 s wall (158 s CPU, parallel) |
| Port, agent's debug build | 99 s wall under load average 27 (the agent reported about 40 s) |
| `baml-cli check`, release, no cache | 0.96 s |
| `baml-cli check`, release, cached | 0.06 s |
| `baml-cli check`, debug | 8.4 s |
| `baml-cli run -e '1'` startup | 0.38 s |

**Caveats.**
- BAML is a bytecode interpreter; V8 JITs. The small-file cold numbers (~4×) show the gap is mostly steady-state throughput, not startup.
- **The agent developed with a debug build that is about 11× slower than release.** Its "about 40 s" test runs would take about 4 s of CPU per core in release. None of the agent's timing observations should be read as release performance.
- My release build used thin LTO and codegen-units=16 instead of the shipped profile (fat LTO, codegen-units=1). A shipped binary could be a little faster.
- Both workloads are small and single-threaded. I didn't benchmark lexer-only or CST-only paths.

## 4. Bugs in the BAML language, compiler, runtime and stdlib found during the migration

**Status for all of these.**
- **No GitHub or Linear issues were filed.** The user's "file BAML issues for the top gaps" message was never submitted (it is still a draft in the terminal).
- `gh issue list --search` on BoundaryML/baml found nothing relevant, except #4765 (bug 1).
- Canary has not moved since `e215c3de2d`, so **nothing is fixed on canary**.

I re-ran every repro marked [measured] against a release build of `e215c3de2d`. The repros are in `…/scratchpad/eemeli-yaml/repros/` and `…/crepro/`.

Severity key, from the agent's notes: **crash** > **wrong-result** > **spurious-compile-error** > **missing-feature** > **pain-point**.

### 4a. Bugs

**1. String literals silently keep `\xNN`, `\uNNNN` and `\u{…}` escapes verbatim, with no diagnostic.** Severity: **wrong-result (silent)**. [measured]
```baml
function esc() -> int[] { [ "\u{8}".length(), "\u0008".length(), "\x08".length(), "\u{FEFF}".length(), "\q".length() ] }
// baml-cli run -e 'root.esc()'  →  [5, 6, 4, 8, 2]   (expected [1, 1, 1, 1] and an error for "\q")
```
- **Impact.** It silently broke the port's BOM and control-character constants and the YAML `\e \a \N \_ \L \P` escape table. yaml-test-suite case G4RS caught it.
- **Workaround.** `chr(cp)`, built on `baml.String.from_code_points`, in commit `33f9222`.
- **Status: an issue exists but was closed wrongly.** GitHub **#4765**, "String literals do not decode \xHH / \uHHHH escapes", was closed as COMPLETED on 2026-09-06. The reporter withdrew it after a probe written as `test "…" { "a\x1bb".length() == 3 }` passed. That probe is vacuous: a `test` whose last expression is `false` also passes (bug 6). I re-ran the same probe with `assert.is_true(...)`, and it **fails**. **#4765 should be reopened.**
- Evidence: `PORTING_NOTES.md` #15; `baml_base/src/escape.rs` per the agent.

**2. `NaN == NaN` is `true`.** Severity: **wrong-result**. [measured]
```baml
let n = baml.Float.nan(); [n == n, n != n]   // → [true, false]; IEEE 754 and JS give [false, true]
```
- **Impact.** A straight port of `parseFloat(source) === num` in `stringifyNumber` re-emitted `.NaN` instead of `.nan`.
- **Workaround.** `&& !num.is_nan()`.
- Not filed. Evidence: `PORTING_NOTES.md` #22; `notes/tests-doc-types.md`.

**3. Invariant generics make catch-all `match` arms silently wrong.** Severity: **wrong-result hazard**. [measured]
```baml
function which(v: unknown) -> string { match (v) { let m: map<string, unknown> => "map", let a: unknown[] => "array", _ => "fallback" } }
// which(<map<string, map<string,int>>>) → "fallback";  which(<int[]>) → "fallback"
```
- This is working as designed for the type system, but no warning is given for an arm that can never match a runtime value of a narrower element type.
- **Impact.** It caused a real wrong result: `js_identical` fell through to structural `==`, so `createNode` emitted spurious YAML aliases (`bar: &a1 … fo: *a1`). Two sub-agents found this independently.
- **Workaround.** Reflect the element type with `reflect.Type.of_value(v).as_array()`, `unreflect`, and a second `match`. See `js_as_array` and `js_identical` in `src/js.baml`.
- Evidence: `PORTING_NOTES.md` #9 and #23; `notes/tests-doc-createNode.md`; `notes/tests-doc-stringify.md`.

**4. The VM call stack is capped at 256 frames and can't be configured.** Severity: **limit / crash**. [measured]
- `rec(200)` works; `rec(300)` gives `uncaught throw: baml.panics.StackOverflow`.
- In the port, nested flow collections fail with `RESOURCE_EXHAUSTION: stack overflow at line 1, column 49` at depth 60, while depth 40 works. Upstream on Node only fails at about **688** levels.
- **Impact.** One test failure (the anchors alias bomb), and a nesting limit about 14× lower than upstream's.
- **Workaround.** `catch_all_panics` in `compose-node.baml` turns the panic into a YAML error, as upstream does.
- Evidence: `PORTING_NOTES.md` #21; `MAX_FRAMES` in `bex_vm/src/vm.rs` per the agent.

**5. `catch_all` does not catch panics such as `StackOverflow`; you need `catch_all_panics`.** Severity: **pain-point** (probably by design). [agent claim]
- A straight port of `try {} catch {}` loses behaviour. Here the crash on deep nesting should have become an error.
- Evidence: `PORTING_NOTES.md` #24; `notes/tests-doc-parse.md`.

**6. New, found while writing this report: a `test` block's trailing boolean is ignored.** Severity: **wrong-result hazard in tooling**. [measured]
- `test "x" { 1 == 2 }` **passes**. Only a thrown error or a failed `assert.*` fails a test.
- This may be intended, but it is an easy trap: it is exactly how #4765 (bug 1) got closed by mistake.
- The port's tests don't depend on it, because all its assertions go through throwing `expect_*` helpers.
- Not filed.

**7. `&&` and `||` don't narrow their right operand.** Severity: **spurious-compile-error**. [measured]
```baml
class T { type: string }
function a1(t: T?) -> bool { t != null && t.type == "x" }   // error[E0007]: type `T | null` has no member `type`
function h(x: T?) -> bool { if (x == null || x.f) { ... } }  // same, E0007
```
- **Workaround.** Nested `if`, or `?.`.
- Evidence: `PORTING_NOTES.md` #1 and #25.

**8. A local captured by any lambda loses null-narrowing everywhere in the function**, even before the lambda and even though it is never reassigned. Severity: **spurious-compile-error**. [measured]
```baml
function c1(e: T?, xs: T[]) -> bool {
  let token = e; if (token == null) { return false; }
  let a = token.type;                                  // E0007 here too
  xs.every((st: T) -> bool { st.type == token.type })  // and here
}
```
- **Workaround.** Re-bind to a fresh non-null local (`let tok: T = token;`).
- Evidence: `PORTING_NOTES.md` #3.

**9. Field accesses are never narrowed** (`if (t.items != null) { t.items.push(1) }` → E0007). The same applies to nullable function-typed fields (E0006). Severity: **missing-feature**; it was the largest source of boilerplate. [measured]
- `?.` also strips only one level of optional: `g.at(1)?.text` on `(T | null)[]` is E0007, while `g[1]?.text` compiles. [measured]
- Evidence: `PORTING_NOTES.md` #2 and #26.

**10. `string.slice` is O(index), and so is `string.at` on non-ASCII strings.** Severity: **performance**. [partly measured]
- The agent measured with its debug build: 3.2 s for an `.at(i)` loop and 6.5 s for a `.slice(i, i+5)` loop over 40k characters, against 0.3 s via `to_code_points()`.
- My release measurements:
  - `.at(i)` over an **ASCII** string is linear (80k characters in 0.2 s net), so there appears to be an ASCII fast path.
  - With one leading `é`, `.at` scales about 3.6× per doubling (40k: 0.23 s; 80k: 0.84 s).
  - `.slice(i, i+5)` on ASCII scales about 3.7× per doubling (0.11 s → 0.41 s).
- **Workaround.** A `Src` class in `js.baml` that pre-splits the input into code points.
- Evidence: `PORTING_NOTES.md` #12.

**11. `test` is a reserved word and can't be a class field or local name. `self` can't be a free-function parameter name.** Severity: **spurious-compile-error / pain-point**. [measured]
- `class Tag { test: string? }` → E0010 "unexpected token".
- The YAML `ScalarTag.test` field became `testFn`. JSON-schema fields such as `enum`, `const`, `then` and `not` were renamed too.
- Evidence: `PORTING_NOTES.md` #5, #16, #17.

**12. A statement starting with `[` after a block is parsed as an index expression.** Severity: **pain-point**. [measured]
- `if (c) { i += 1; }` followed by `[i, 2, 3]` on the next line → E0010.
- Evidence: `PORTING_NOTES.md` #6.

**13. E0097 is a hard error for `throws unknown` on a function that throws something narrower or nothing.** Severity: **pain-point**. [measured]
- It makes generated code and "may throw anything" test callbacks brittle.
- Related: `Future<T, never>` is not assignable to `Future<T, unknown>` [agent claim].
- Evidence: `PORTING_NOTES.md` #27 and #28.

**14. `unknown`-typed class fields are required in class literals**, even though `unknown` includes `null`. `U { a: 1 }` → E0001 "missing required field: `extra`". Severity: **pain-point**. [measured]
- Evidence: `PORTING_NOTES.md` #7.

**15. Not reproduced: `baml-cli run -e` aborting with a native stack overflow** ("thread '<unknown>' has overflowed its stack").
- Several sub-agents reported it while the project was being edited concurrently. The coordinator couldn't reproduce it on the final tree, and neither could I (clean copy, debug and release builds).
- I did hit exactly this native abort, in both `check` and `test`, from the debug binary on a directory where I had accidentally merged the yaml port with another port's `ns_*` sources. With `RUST_MIN_STACK=64MB` the same tree checks cleanly. So there **is** a compiler path that recurses deeply enough to overflow a default-sized thread stack on some inputs.
- I didn't minimise it. Worth a follow-up.
- Evidence: `PORTING_NOTES.md` #31.

**16. `reflect.AnyClass.name()` includes generic arguments** (`"JsMap<Pair>"`), and there is no way to get the unapplied name. Severity: **pain-point**. [agent claim]
- It broke 13 `_map(...)` assertions until the test helper stripped `<…>`.
- Evidence: `PORTING_NOTES.md` #30; `notes/tests-doc-comments.md`.

**17. Integer overflow panics** (`baml.panics.IntegerOverflow`) where JS silently becomes a float. Severity: **pain-point**. [agent claim]
- `int` is 63-bit (±2^62), so 64-bit literals are compile errors. `js_parse_int` now falls back to float, which fixed 8 json-test-suite tests.
- Evidence: `notes/tests-json-test-suite.md`; `PORTING_NOTES.md` #32.

### 4b. Missing features that forced workarounds (not bugs)

These are from `PORTING_NOTES.md`; I measured the truthiness one.
- **No reference identity / `===`** (#10). Worked around with a random `_id` on every node and token class, plus a mutate-and-observe probe for maps and arrays. It also causes the O(n²) `createNode` (§3) and 2 test failures.
- **No sticky or positional regex matching** (#13). The lexer uses hand-written scanners instead.
- **No module-level constants** (#8). **No optional positional parameters** (#18). **No non-null assertion** (#4). **No dynamic import**: the CLI's `--visit` needs an injected loader. **No "read all of stdin"**. **`baml.fs.read` has no lossy UTF-8 mode.**
- **Truthiness differs from JS** (#11) [measured]: `[]`, `{}` and `""` are all falsy in BAML, but `[]` and `{}` are truthy in JS. A mechanical port of `if (it.sep)` compiles and is wrong, so every such check was rewritten as `!= null`.
- **Float formatting is not JS-compatible** (#14): `1.0.to_string()` is `"1.0"`. JS `Number#toString` had to be reimplemented.
- **Multiline backtick strings are dedented and lose their leading and trailing newline** since #4914 (#29), so they can't stand in for upstream's `source\`…\`` template tag.
- **One compile error anywhere blocks every test in the project** (#20). With 7 parallel agents in one tree this was painful, and each agent ended up working in a private copy.
- **Static `test` blocks.** Table-driven test files need an external generator (§2).
- **One flat namespace per directory tree** (#19). Name clashes were fixed by renaming: `stringify` → `stringifyNode`, `visit` → `cst_visit`.

## 5. Bugs in the original library (eemeli/yaml)

**None were found.**
- Every "Library fixes" section in `notes/*.md` fixes the *port*: `js_identical`, `applyReviver` holes, `catch_all_panics`, `NaN`, `js_parse_int` overflow, and the `\u` escapes.
- None reports an upstream defect.
- The property-test port ran 600 extra seeded cases and found no library bugs [agent claim, `notes/tests-properties.md`].
- Upstream's own suite passes cleanly on Node 22 [measured].

## 6. Other comparisons

- **Dynamic typing and `undefined`.** This was the hardest modelling problem.
  - JS `undefined` versus `null` is modelled with a `js_undefined()` sentinel, but only where upstream behaviour depends on it: `keepUndefined`, and `stringify(undefined)` returning `undefined`. Everywhere else it collapses to `null` (`3e3c1bb`).
  - "Is this any array or object?" needs reflection because generics are invariant (§4, bug 3).
- **Classes and inheritance.** A union `type Node = Scalar | YAMLMap | YAMLSeq | YAMLSet | Alias` plus an `interface NodeBase` with fields and dispatching methods worked well. JS subclasses became a `_class` discriminator. The CST is one "fat" `Token` class with optional fields, because the parser mutates token types in place. That design is what makes bug 9 (fields never narrow) so costly.
- **Error handling.** `JsError` classes plus `throw` and `catch` port cleanly. Differences:
  - `catch_all` versus `catch_all_panics` (§4, bug 5).
  - `warn()` goes to stderr and can't be intercepted, so 3 tests that spy on `process.emitWarning` are placeholders.
- **What went surprisingly well:**
  - `reflect.AnyClass` with `list_fields()` and `get<unknown>(name)` made a Jest-compatible `toMatchObject` possible.
  - Closures capture by reference, so JS `() => (comment = null)` callbacks port directly.
  - `Regex.split` includes capture groups the way JS does, and the fancy-regex backtracking engine handles upstream's lookaround patterns.
  - Nested `testset`s with shared `let` state map onto `describe`.
  - The composer and `Document` ported at about 1×.
  - All 2,089 yaml-test-suite checks passed once the escape bug was fixed.
- **Agent workflow.**
  - The coordinator ported the entire library serially itself, about 12k code lines in roughly 40 minutes. It found the narrowing gaps early by bisecting a failure inside `parser.pop`.
  - It then wrote a `TEST_PORTING_GUIDE.md` (JS→BAML API map and the `expect_*` helper table) and dispatched 7 sub-agents. Four of them forked again, for 11 transcripts in total.
  - Shared-tree compile breakage (§4b) forced each sub-agent into a private copy. Two agents fixed the same `js_identical` and `JsMap<…>` bugs independently and concurrently.
  - The whole thing, including library, tests, the notes and 32 catalogued gaps, took **61 minutes wall-clock**.
- **Dev loop.** The agent's debug build made `check` take about 8 s and the full suite about 40–100 s. A release build would give about 1 s and about 19 s.

## 7. Open questions and caveats

- **No BAML issues filed.** "File BAML issues for the top gaps" was never sent. #4765 (escapes) should be reopened rather than duplicated.
- **Bug 15** (the native stack overflow in the compiler) is real on at least one input but not minimised.
- **`parse` scaling** is mildly superlinear, and I didn't profile why (§3). `stringify(value)` superlinearity is explained by the association-list `NodeCreator`, but I didn't confirm it with a profiler.
- **Placeholders.** 23 of the "passed" tests are placeholders. The headline "3,413 passed" figure matches upstream's pass count by coincidence of accounting, not by equivalence.
- **Items not re-checked** (claims taken from the transcripts): `Future` error-type invariance, `catch_all` versus panics, backtick dedent, `reflect` class names, integer overflow, and the per-file notes.
- **My benchmark** used a thin-LTO release build on a machine loaded by other agents. The ratios (100–200× typical, up to about 945× on `stringify` of large values) are robust to that; the absolute numbers are approximate.
- **Scratch-directory incident.** My scratchpad is shared with sibling report agents. I accidentally rsync'd the yaml port into a sibling's `scratchpad/port` copy of `tomli-baml`, then restored it: I removed the added files and restored `.gitignore`, `baml.toml` and `PORTING_NOTES.md` from `<local>/work-repos/tomli-baml`, and `diff -rq` against `<local>/work-repos/tomli-baml` is now clean, apart from `.baml/` cache files. I also briefly moved a sibling's `scratchpad/loc.py` and then put it back. None of the source repos were touched.
