# eemeli/yaml → BAML: every workaround, bug and limitation

Written 2026-09-28. Companion to [report.md](report.md) (the post-mortem), which I used as a starting checklist. This file lists every BAML bug or limitation the porting agents had to work around, re-checks each bug-class item against a release `baml-cli`, and records the cases where an agent blamed BAML for its own mistake.

## Sources and method

- **C** (coordinator): `<local>/transcripts/port-eemeli-yaml/9e8d82d5-bffe-4c7b-b704-36d8072cbe66.jsonl`, 2026-09-26 19:13–20:14 UTC. It wrote the whole library itself, then fanned tests out to sub-agents.
- **Sub-agents** (all in `…/9e8d82d5-…/subagents/`, 19:56–20:10 UTC):
  - **S-spec** `agent-a0051f98df51ebce1` (YAML-1.2/1.1 spec tests)
  - **S-str** `agent-a15ae868452120a62` (doc/stringify)
  - **S-ca** `agent-a18fef485971877f0` (collection-access, a fork)
  - **S-typ** `agent-a1ef6a769747ba63e` (doc/types, properties, rawJSON)
  - **S-cst** `agent-a3310d363ab4534d4` (cst, a fork)
  - **S-anc** `agent-a898629679ba64b72` (doc/anchors, doc/errors, doc/createNode)
  - **S-misc** `agent-a8eaa7e264013b9fc` (json-test-suite, cli, `src/cli.baml`; parent of the forks)
  - **S-com** `agent-aba999d8e061392fc` (doc/comments, clone, node-to-js)
  - **S-vis** `agent-ac9c5de98a8ec65e7` (visit, a fork)
  - **S-par** `agent-ae44699c28422893e` (doc/parse, directives, compat)
  - **S-ffl** `agent-af35a9913b212539a` (doc/foldFlowLines, a fork)
- **E** (early attempt): `<local>/transcripts/port-yaml-js/bb55325e-03f2-4d0e-b438-33a454e6720d.jsonl`, 2026-09-26 00:07–00:28 UTC. This is Orca task `task_d56748431644` in the `port-yaml-js` worktree. It spent 20 minutes probing the language, wrote no port code and was abandoned, but it found several things the main run didn't (E0063 on literal scrutinees, class field defaults, `map<unknown, …>`, union member access).
- Other transcripts that mention `work-repos/yaml-baml` (`<local>/transcripts/coordinator/1c8504f4…`, the burntsushi-toml session, and this report session's siblings) only reference the path or `PORTING_NOTES.md`; none contain yaml porting work.
- **Port**: `<local>/work-repos/yaml-baml`, 6 commits `fa3a74c..3e3c1bb`; `PORTING_NOTES.md` (32 numbered gaps), `TEST_PORTING_GUIDE.md`, `notes/*.md` (21 files). The agents' private copies are `<local>/tmp/yaml-baml-{main,tca,tcli,tcom,tdoc,tffl,tpar,tspec,tstr,ttyp,tvis}`. Probes: `…/port-eemeli-yaml/9e8d82d5-…/scratchpad/{probe,bisect,vis}`. `bt.baml` is empty.
- **Transcript references** use the form `C[L1786 19:57]`: the jsonl line (1-based) and UTC time. I condensed every transcript with a script and read the coordinator log myself. Four helper agents read the 11 sub-agent logs and E in full, and I spot-checked their claims against the logs and the release binary.
- **Verification.** I used the release binary `<local>/baml-worktrees/port-hukkin-tomli/baml_language/target/release/baml-cli` (0.20.1, built at `e215c3de2d`, clean tree; `e215c3de2d` is still `origin/canary`), with `BAML_AGENT_SKILL_CHECK=off`. Each repro ran in its own throwaway project under `<local>/report-scratch/yamlbugs.hNgJ/r/` (driver `rp.sh`). For the compiler stack overflow I also used the agents' own **debug** binary (`…/port-eemeli-yaml/9e8d82d5-…/scratchpad/baml-cli`).
  - **VERIFIED**: reproduces on the release binary today.
  - **NOT REPRODUCED**: doesn't reproduce; usually an agent error (see "Agent mistakes").
  - **UNVERIFIED**: not re-run. That applies mostly to design gaps (category d), which I didn't try to verify.
- **GitHub.** I ran `gh issue list -R BoundaryML/baml --state all --search …` for each item's keywords. The only hits were **#4765** (escapes; closed as COMPLETED on 2026-09-06 on vacuous evidence, see B1) and **#4591** (open; about backtick dedent breaking `#"…"#` migration, related to F14). No porting agent filed anything.

Categories: **a** compiler/type-checker, **b** runtime/VM, **c** stdlib, **d** missing language feature, **e** performance, **f** tooling/CLI/test runner/LSP, **g** docs.

Severity: **Crash > Wrong result > Spurious error > Perf > Missing feature > Ergonomics/Diagnostic**.

## Summary table

### Bugs and toolchain problems (a, b, c, e, f, g)

| # | Title | Cat | Severity | Verified? | Issue | Workaround in port |
|---|---|---|---|---|---|---|
| B1 | String literals keep `\xNN`, `\uNNNN`, `\u{…}` and unknown escapes (`\q`) verbatim, with no diagnostic | a | **Wrong result (silent)** | VERIFIED | #4765 (closed wrongly) | `chr(cp)` via `baml.String.from_code_points` (`src/js.baml:1190`), 26 call sites; commit `33f9222` |
| B2 | `NaN == NaN` is `true` (and `NaN != NaN` is `false`) | b | **Wrong result** | VERIFIED | none | `&& !num.is_nan()` (`src/stringify/stringifyNumber.baml:25`) |
| B3 | Invariant generics: `match` arms `unknown[]` / `map<string, unknown>` silently miss `int[]`, nested maps, etc.; `string[]` can't be passed as `unknown[]` | a | **Wrong result (hazard)** | VERIFIED | none | Reflect the element type, `unreflect`, re-`match` (`js_as_array`/`js_as_object`/`js_identical`, `src/js.baml:79–130, 836–880`); generic helpers (`tspec_set<T>`) |
| B4 | A `test` block whose last expression is `false` passes | f | **Wrong result (hazard)** | VERIFIED | related: #4765 was closed on this | Not hit: all assertions throw via `_expect.baml` |
| B5 | VM call stack capped at 256 frames (`MAX_FRAMES`, `bex_vm/src/vm.rs:118`) | b | Crash / limit | VERIFIED | none | `catch_all_panics` turns the overflow into `RESOURCE_EXHAUSTION` (`src/compose/compose-node.baml:106–112`); 1 test left failing |
| B6 | `catch_all` doesn't catch panics (`StackOverflow`), so a literal port of `try {} catch {}` loses behaviour | b/g | Wrong result (hazard); by design, documented | VERIFIED | none | `catch_all_panics`, or `catch (e) { baml.panics.StackOverflow => … }` |
| B7 | Debug-build compiler aborts with a native stack overflow (`thread '<unknown>' has overflowed its stack`) in `run -e`, `run` and `check` on some project trees | a/f | Crash (debug build only) | VERIFIED on the agents' debug binary; NOT REPRODUCED on release | none | Agents probed through scratch `test`s; works with `RUST_MIN_STACK=64MB` |
| A1 | `&&` and `\|\|` don't narrow their right operand (E0007, E0004 "cannot order `int \| null`") | a | Spurious error | VERIFIED | none | `x?.f == …`, nested `if`, `?? default` (e.g. `src/parse/parser.baml:85, 595`, `src/cli.baml` `next?.starts_with("-") ?? true`) |
| A2 | A local captured by any lambda loses narrowing in the whole function | a | Spurious error | VERIFIED | none | Rebind `let tok: Token = token;` (`src/parse/parser.baml:320`) |
| A3 | Field accesses never narrow, including nullable function-typed fields (E0006 "is not a function") | a | Spurious error | VERIFIED | none | Local copies and accessor helpers `titems/tend/tstart/tsrc/tindent/tprops` (`src/parse/cst.baml:66–80`, 135 calls) |
| A4 | `?.` strips only one level of null: `g.at(1)?.text` on `(T \| null)[]` is E0007 | a | Spurious error | VERIFIED | none | `g[1]?.text` (`tests/doc/types.baml:111`) |
| A5 | A redundant `?.` is a hard error (E0004 "`g?.text` is unnecessary") | a | Spurious error | VERIFIED | none | Drop the `?` (`src/compose/resolve-block-scalar.baml:246`) |
| A6 | An unreachable `match` arm is a hard error (E0063), e.g. `_` after a literal scrutinee, or after `reflect.AnyClass` on a known class | a | Spurious error | VERIFIED | none | Make the scrutinee non-constant (E); drop the arm |
| A7 | `throws unknown` that is "imprecise" or "unnecessary" is a hard error (E0097), including on lambdas | a | Spurious error | VERIFIED | none | Drop the clause; S-vis's generator removed it from ~20 lambdas |
| A8 | `Future<T, never>` is not assignable to `Future<T, unknown>`, even with an annotated `let` | a | Spurious error | VERIFIED | none | Force the spawn body to "maybe throw": `tvis_rethrow(null)` (`tests/visit.baml:77, 87`) |
| A9 | Function types must declare `throws` (E0151) | a | Ergonomics | VERIFIED | none | `throws unknown` / `throws never` on every function type and alias (`src/options.baml`, `src/schema/types.baml`, …) |
| A10 | An `unknown` field is required in class literals although `unknown` includes `null` | a | Ergonomics | VERIFIED | none | Declare it `unknown?` (`src/js.baml:16`) |
| A11 | `let x = match (v) { …, _ => [] }` → E0155 "type annotations needed" (while printing `full type: unknown[]`) | a | Ergonomics | VERIFIED | none | Annotate: `let fields: string[] = match …` (`tests/_expect.baml`) |
| A12 | `test` can't be a field or local name, `enum` can't be a field name, and `self` can't be a free-function parameter; errors cascade | a | Ergonomics / Diagnostic | VERIFIED | none | `testFn` (`src/schema/types.baml`), `om` (`src/schema/yaml-1.1/omap.baml:20`), `enum_` |
| A13 | A statement starting with `[` after a block is parsed as an index expression | a | Spurious error | VERIFIED | none | `return [ … ];` (`src/parse/lexer.baml:166, 208`; `tests/doc/parse.baml` `tpar_array_from`) |
| A14 | Class field defaults (`mark: int = 0`) are unsupported, and the error says "expected \`Unexpected token in class body\`" | a/d | Missing feature + bad diagnostic | VERIFIED | none | Spell every field in every literal; optional fields default to `null` |
| C1 | `reflect.AnyClass.name()` includes generic arguments (`"Box<int>"`, `"JsMap<Pair>"`) | c | Wrong result (hazard) | VERIFIED | none | `c.name().split("<")[0]` and `starts_with("JsMap")` (`tests/_expect.baml:32, 139, 604`); silently broke 13+ `_map` assertions |
| C2 | `int` is 63-bit; `*` overflow panics (`IntegerOverflow`), 64-bit literals are compile errors | b/c | Crash (in a literal port) | VERIFIED | none | Overflow guard with float fallback in `js_parse_int` (`src/js.baml:1023`); fixed 8 json-test-suite tests |
| C3 | `baml.fs.read` has no lossy UTF-8 mode | c | Missing feature | VERIFIED | none | `baml.fs.open(p, "r").bytes().to_string()` (`tests/json-test-suite.baml` `tjts_read`) |
| C4 | No "read all of stdin"; `baml.io.input` reads one line and returns `""` both at EOF and for an empty line | c | Missing feature | VERIFIED (per its docs) | none | `baml.fs.open("/dev/stdin", "r").text()` (`src/cli.baml:475`) |
| C5 | `array.insert(item, idx)` takes the item first; the wrong order gives two unhelpful E0001s | c/f | Ergonomics | VERIFIED | none | `insert(ci, idx)` (`tests/cst.baml:127`) |
| C6 | `int` has no `to_float()` | c | Ergonomics | VERIFIED | none | `v * 1.0` (`src/js.baml`, `js_parse_int`) |
| C7 | Out-of-range array indexing panics (`IndexOutOfBounds`), where JS gives `undefined` | b | Crash (in a literal port); by design | VERIFIED | none | Length guard (`src/visit.baml:376`); `seq.at(i)` in tests |
| C8 | Float `to_string` is not JS-compatible (`1.0`, `1000000000000000000000.0`, `0.0000001`, `-0.0`) | c | Ergonomics; by design | VERIFIED | none | `js_number_to_string` (`src/js.baml:463`, ~100 lines) |
| C9 | No `decodeURIComponent` / percent-decoding | c | Missing feature | UNVERIFIED (`describe baml` has nothing) | none | Hand-written decoder (`src/doc/directives.baml` ~240–285) |
| E1 | `string.at(i)` and `string.slice(i, j)` cost O(i), ASCII or not | e | Perf (high) | VERIFIED | none | `Src` class pre-splits into `chars()`/`to_code_points()` (`src/js.baml:714`); hand-written lexer scanners |
| E2 | Overall interpreter throughput ~100–200× slower than V8; `stringify(value)` ~945× on 144 KB because of the O(n²) identity association list (see F1) | e | Perf | VERIFIED in the post-mortem (§3) | none | None |
| F-t1 | One compile error anywhere blocks every test, `run` and `run -e` in the project | f | Ergonomics (high with parallel agents) | VERIFIED | none | Each agent worked in a private rsync copy |
| F-t2 | Deliberate stdlib warnings (`csv.baml:402 warning[E0146]: unreachable code`, 11 of them) are printed on every user `check`/`run` | f | Diagnostic noise | VERIFIED (new since #4995, `f603110e74`) | none | `check.sh` greps them out |
| F-t3 | Panic tracebacks print every frame (~256 identical lines for a stack overflow) | f | Diagnostic | VERIFIED | none | `grep -v`/`awk '!seen[$0]++'` |
| F-t4 | `baml run fn` can't take `string[]` as flags; `--json-args` must be a JSON object; `baml.sys.argv()` returns the `baml-cli` invocation | f/c | Ergonomics | VERIFIED | none | `baml run yaml_cli -- --json-args '{"args": […]}'` (`src/cli.baml:11`) |
| F-t5 | Error for a positional defaulted argument says "must be passed by name" but not how; `name: v` is a parse error, `name = v` works | f | Diagnostic | VERIFIED | none | `Xoshiro256PlusPlus.new(seed = u8)` (`tests/properties.baml:54`) |
| F-t6 | `baml test` doesn't print results while a long test is still running (with stdout redirected) | f | Ergonomics | VERIFIED (partly) | none | None; C thought the first yaml-test-suite run had hung |
| F-t7 | No way to mark a test as skipped | f | Ergonomics | VERIFIED (no such syntax) | none | 17 `// UNPORTABLE` bodies that trivially pass, so the counts overstate passes |
| F-t8 | Docs steer to a debug build (`cargo build -p baml_cli`), ~11× slower than release and the only build with B7 | f/g | Perf of the dev loop | VERIFIED (post-mortem measured 8.4 s vs 0.96 s `check`) | none | None; the agents used debug throughout |
| F-t9 | Nullable values can't be interpolated (hard E0001) | a | Ergonomics | VERIFIED | none | `?? "…"` everywhere |

### Missing language features and semantic gaps (d)

| # | Title | Cat | Severity | Verified? | Issue | Workaround in port |
|---|---|---|---|---|---|---|
| F1 | No reference identity (`===`) for class instances, arrays or maps | d | Missing feature (high) | VERIFIED (`[1] == [1]` structural) | none | Random `_id` on 16 classes; mutate-and-observe `js_identical` (`src/js.baml:803`); 2 tests fail; O(n²) `NodeCreator` |
| F2 | Map keys must be `string` (E0067) | d | Missing feature | VERIFIED | none | `class JsMap<V>` with `_keys/_vals/_index` and linear fallback (`src/js.baml`) |
| F3 | No sticky/positional regex matching | d/c | Missing feature | UNVERIFIED | none | Five hand-written scanners (`src/parse/lexer.baml:3–6`); lexer 1.64× TS |
| F4 | No module-level constants (top-level `let` rejected) | d | Missing feature | VERIFIED (E) | none | Zero-arg functions (`BOM()`, `DOCUMENT()`, `UserError_ARGS()`) |
| F5 | No optional positional parameters | d | Missing feature (high boilerplate) | UNVERIFIED | none | Explicit `null`s (~1,100 `, null)`-style args; 261 `toString(null`), split `set`/`setWithOptions` |
| F6 | No non-null assertion `x!` and no checked downcast `as T` | d | Missing feature | UNVERIFIED | none | Match-or-throw helpers (`tcom_scalar`, `tn2j_to_js`, …) |
| F7 | No inheritance; a union of classes exposes no shared fields without an interface | d | Missing feature | VERIFIED (E0007 on `A \| B`.comment) | none | `interface NodeBase` + `nb()`; `_class` discriminator for `YAMLOMap`/`MergeKey` |
| F8 | No `undefined` distinct from `null` | d | Missing feature | n/a | none | `js_undefined()` sentinel (`src/doc/applyReviver.baml:19`), commit `3e3c1bb` |
| F9 | Truthiness differs from JS (`[]`, `{}` falsy) | d | Wrong result (hazard); by design | VERIFIED | none | `js_truthy` and `!= null` rewrites |
| F10 | No property setters, boxed primitives, array holes or lone surrogates | d | Missing feature | n/a | none | 10 UNPORTABLE tests, 4 failing tests |
| F11 | No dynamic import | d | Missing feature | n/a | none | Injected `importVisitor` loader (`src/cli.baml`) |
| F12 | Static `test` blocks: no table-driven tests, no `beforeEach` | d/f | Missing feature | n/a | none | Python/Node generators (3,241 generated lines); per-test factory functions |
| F13 | No way to capture or intercept stderr/stdout or mock a function in tests | d/f | Missing feature | n/a | none | 3 UNPORTABLE tests, 8 dropped `emitWarning` assertions |
| F14 | Multiline backtick strings are dedented and lose leading/trailing newlines (by design since #4914) | d | Ergonomics | VERIFIED | #4591 (related) | `source(…) + "\n"` at 86 sites |
| F15 | One flat namespace per directory tree; no tuples; no intersection types; no `this`; no constructor reflection | d | Ergonomics | n/a | none | Renames (`stringifyNode`, `cst_visit`); `int[]` for ranges; one `Options` class; holder as 4th arg |
| F16 | `baml.random` has no choice/shrinking/property-testing support | c/d | Missing feature | VERIFIED (only `Int.random`, `Float.random`) | none | Hand-written `tprop_*` generators |

### Agent mistakes (thought to be BAML problems, weren't)

| # | Claim | Reality |
|---|---|---|
| M1 | `run -e` "crashes on any library call" (5 agents) | Only the **debug** build aborts, and only on some trees (B7). Release never did. |
| M2 | `run -e` "is slow" (~5–25 s per call) | Debug build plus a loaded machine. Release: ~1.2 s on the full 107-file port. |
| M3 | `const`, `then`, `not`, `type`, `default` are reserved field names (C renamed them in `json-schema.baml`) | All five are fine as field names. Only `enum` and `test` are rejected. |
| M4 | "Test names must be unique within their testset" (guide; S-str renamed 3 tests) | The runner accepts duplicates and suffixes them `#2`. |
| M5 | `Regex.split` drops capture groups (C wrote `splitLines` around it) | It includes them like JS; the workaround caused the bug. |
| M6 | BAML silently accepts duplicate function names (C) | E0011 is reported; C's filtered view hid it. |
| M7 | "No `splice`" (S-cst notes) | `Array.splice(start, count, replace)` exists. |
| M8 | "No `pow`, no float/range random" (S-typ notes; PORTING_NOTES #32) | `Float.pow`, `Int.pow`, `Float.random(rng)` and `Int.random(lower, upper, rng)` exist. |
| M9 | `baml.BigInt.parse` doesn't exist (S-typ) | It's `baml.Bigint.parse`. |
| M10 | Backtick strings don't decode `\t` (S-cst) | They do; `json_quote` re-escaped the tab. |
| M11 | Every diagnostic is printed twice (S-typ) | The agent ran `./check.sh && $B test`, which each print the same errors. |
| M12 | `catch_all_panics` is "effectively undocumented" (S-par) | `baml describe catch_all_panics` and `book/errors.mdx` both cover it. |
| M13 | `match` and `is` disagree (E) | They agree; the probe compared an `unknown[]` arm with `is J[]`. |
| M14 | Other small ones | `baml.sys.print` (it's `baml.io.print`); `Float.infinity()` (it's `inf()`); lambdas "can't mutate captured locals" (they can); `YAMLOMap.tagName()` (a port-side alias, not a class); a "hang" that was just unstreamed output (F-t6); zsh `echo`/glob artifacts; a sibling's half-written file breaking everyone's `run -e` (F-t1). Several "failures" were port or test-helper bugs: `applyReviver` holes, `t_equal`/`t_match` cycles, `toMatchObject` subset semantics, `_setIndex` gaps. |

## Detailed entries

### B1. String escapes `\xNN`, `\uNNNN`, `\u{…}` and unknown escapes are kept verbatim

- **Category / severity:** a, wrong result (silent).
- **Observed.** yaml-test-suite G4RS failed with `control: "\\u{8}1998…"` expected to equal `"\b1998…"` (C[L1782 19:57]). The agent probed at C[L1787 19:57]: `[ "\u{8}".length(), "\u0008".length(), "\x08".length(), "\u{FEFF}".length(), "\u{1b}".length(), "\t".length(), "\u{2028}".length() ]` → `[5, 6, 4, 8, 6, 1, 8]`. It then read `baml_base/src/escape.rs` and found that only `\n \t \r \0 \b \v \f \\ \"` are decoded (C[L1833 19:58]). S-spec, S-str and E hit it independently (E: `"a\x02b\u{FEFF}c\t\0".chars().length()` is 17).
- **Repro (release, today):** `baml-cli run -e '[ "\u{8}".length(), "\u0008".length(), "\x08".length(), "\u{FEFF}".length(), "\q".length() ]'` → `[5, 6, 4, 8, 2]`. Expected `[1, 1, 1, 1]` and an error for `\q`.
- **Workaround.** `chr(cp)` = `baml.String.from_code_points([cp])` with a panic on failure (`src/js.baml:1190–1197`). The BOM and marker constants (`src/parse/cst.baml:110–125`), the YAML `\e \a \N \_ \L \P` escape table (`src/compose/resolve-flow-scalar.baml:256–268`), `test-events.baml:160–168` and the `Symbol` sentinels were rewritten. The spec-test generator emits `chr(n)` (`tools/gen_yaml12_spec.cjs`). A guide note was added for the sub-agents.
- **Cost.** 26 `chr(` calls; one silent wrong result that only yaml-test-suite caught; every `"\u{…}"` must be audited.
- **Evidence.** C[L1782–L1849 19:57–19:58]; commit `33f9222`; PORTING_NOTES #15.
- **Verified:** VERIFIED. **Issue:** #4765, closed as COMPLETED on 2026-09-06 after a vacuous `test "…" { "a\x1bb".length() == 3 }` probe (see B4). It should be reopened.

### B2. `NaN == NaN` is `true`

- **Category / severity:** b, wrong result.
- **Observed.** `core schema::!!float` and `YAML 1.1 schema::!!float` wrote `.NaN` back as `.NaN` instead of `.nan`, because upstream's `parseFloat(source) === num` became `pf == num` (S-typ[L220–L238 20:03]). C confirmed it with `let n = baml.Float.nan(); [n == n, n != n, n < n]` → `[true, false, false]` (C[L2187 20:13]).
- **Repro:** the same expression gives `[true, false, false]` on release. IEEE 754 and JS give `[false, true, false]`.
- **Workaround.** `if (pf == num && !num.is_nan())` (`src/stringify/stringifyNumber.baml:25`).
- **Cost.** One line here, but every ported float `===`/`!==` is suspect.
- **Verified:** VERIFIED. **Issue:** none.

### B3. Invariant generics make `match` arms silently miss, and reject `string[]` for `unknown[]`

- **Category / severity:** a, wrong-result hazard. The type rule is by design; the lack of any warning when an arm can never match a narrower runtime value is the bug.
- **Observed.**
  - C's first probe, `match (v) { let a: unknown[] => "array", _ => "object" }`, returned `object` for `[1, 2]` (C[L540–L548 19:17]). C then built `js_as_array`/`js_as_object` on `reflect.Type.of_value(v).as_array()` + `type E = unreflect(…)` (C[L564–L577 19:17]).
  - `js_identical` still fell through to structural `==` for nested literals. `createNode` then emitted spurious aliases (`bar: &a1 … fo: *a1`). S-anc (S-anc[L355–L383 20:04–20:05]) and S-str (S-str[L257–L298 20:04–20:05]) each found and fixed it separately, in parallel.
  - S-spec: `YAML-1.2.spec.baml:80:36-80:64 error[E0001]: mismatched types / expected unknown[], found string[]` (S-spec[L161–L169 20:00]).
  - E reached the same conclusion at E[L419 00:23] and redesigned around it.
- **Repro (release):**
  ```baml
  function which(v: unknown) -> string { match (v) { let m: map<string, unknown> => "map", let a: unknown[] => "array", _ => "fallback" } }
  // which({"baz": {"a": 1}}), which(<int[]>[1]), which({"a": 1}), which([true]) → all "fallback"
  function takes(v: unknown[]) -> int { v.length() }
  function f() -> int { let s: string[] = ["a"]; takes(s) }   // E0001 expected `unknown[]`, found `string[]`
  ```
- **Workaround.** `js_as_array`/`js_as_object` (`src/js.baml:79–130`) and a typed probe branch in `js_identical` (`src/js.baml:836–880`). The probe mutates a container with a reflected element value and undoes the change. Empty typed containers can't be probed and count as distinct. Helpers were made generic (`tests/doc/YAML-1.2.spec.baml:32`).
- **Cost.** About 100 lines of reflection code; a residual correctness hole for empty typed containers; one wrong result that reached two test files.
- **Verified:** VERIFIED. **Issue:** none.

### B4. A `test` whose trailing expression is `false` passes

- **Category / severity:** f, wrong-result hazard.
- **Repro (release):** `test "falsy trailing" { 1 == 2 }` → `PASS root::falsy trailing`.
- **Impact.** The port is safe because every assertion throws (`tests/_expect.baml`). But this is exactly how #4765 was "verified" and closed.
- **Verified:** VERIFIED. **Issue:** none.

### B5. VM call stack capped at 256 frames

- **Category / severity:** b, crash/limit.
- **Observed.**
  - `i_structure_500_nested_arrays` → `baml.panics.StackOverflow { message: "stack overflow" }` (S-misc[L181 20:00]); S-misc bisected 250 OK / 256 overflow (S-misc[L241–L248 20:01]).
  - The doc/parse `Excessive recursion` tests crashed (S-par[L270–L326 20:03–20:05]); the agent found `pub const MAX_FRAMES: usize = 256;` in `bex_vm/src/vm.rs:118`.
  - The anchors `circular reference` alias bomb overflows before upstream's own `maxAliasCount` guard fires (S-anc[L118–L249 19:59–20:01]).
  - The composer uses about 5 frames per nesting level, so about 50 levels of `[[[…]]]` overflow; upstream on Node goes to about 688.
- **Repro (release):** `function rec(n: int) -> int { if (n == 0) { 0 } else { 1 + rec(n - 1) } }`: `rec(200)` works; `rec(300)` → `uncaught throw: baml.panics.StackOverflow {message: "stack overflow"}`.
- **Workaround.** `composeNodeCollection` uses `catch_all_panics` and matches `let p: baml.panics.StackOverflow => p.message` to produce `RESOURCE_EXHAUSTION` (`src/compose/compose-node.baml:106–112`). `t_equal`/`t_match` gained cycle guards so `toEqual` on circular values doesn't recurse.
- **Cost.** 1 test still fails (`doc/anchors › errors › circular reference`); a nesting limit about 14× lower than upstream's.
- **Verified:** VERIFIED. **Issue:** none.

### B6. `catch_all` doesn't catch panics

- **Category / severity:** b/g, wrong-result hazard. By design, and documented in `baml describe catch_all`.
- **Observed.** `tpar_dbg_rec(1000000) catch_all (e) { _ => … }` still died with StackOverflow. `catch (e) { baml.panics.StackOverflow => … }` and `catch_all_panics` both caught it (S-par[L276–L338 20:04–20:05]). Before the fix, `composeNodeCollection` used `catch_all`, so deep input crashed instead of producing an error.
- **Repro (release):** `rec(300) catch_all (e) { _ => -2 }` → uncaught StackOverflow; `rec(1000) catch (e) { baml.panics.StackOverflow => -1 }` → `-1`; `catch_all_panics` → caught.
- **Workaround.** `catch_all_panics` (`src/compose/compose-node.baml:108`).
- **Verified:** VERIFIED (behaviour). **Issue:** none.

### B7. Debug-build compiler overflows the native stack on some project trees

- **Category / severity:** a/f, crash, debug build only.
- **Observed.** Five sub-agents saw `thread '<unknown>' (NNN) has overflowed its stack / fatal runtime error: stack overflow, aborting` from `$B run -e 'root.…'`. Examples:
  - `root.js_typeof(1)`, `root.yaml_parse("a: 1")` (S-par[L189 20:02]; S-typ[L155–L184 19:59])
  - `root.re("a")` (S-str[L204 20:03])
  - `root.t_class_name(root.js_map())` (S-ca[L100 19:59])
  - `root.json_quote(\`…\`)` (S-ffl[L82 19:59]; S-com[L105 19:58])
  - `root.js_parse_int("12", 10)` (S-misc[L204–L225 20:00])

  The same code worked in `test` blocks or in `run <fn>`. C couldn't reproduce it on the final tree (C[L2175–L2182 20:13]) and logged it as "intermittent".
- **Re-check.** In the agents' own private copies with the agents' own debug binary, `run -e 'root.js_typeof(1)'` aborts deterministically in `yaml-baml-ttyp` and `yaml-baml-tca`, and works in `yaml-baml-tpar` and `yaml-baml-tstr`. On the `tca` tree, `check` and `run smoke1` also abort, so this is a compiler problem, not something specific to `-e`. Adding or removing any single `.baml` file (even an empty one) makes it go away, which points to deep recursion whose depth depends on the project layout. `RUST_MIN_STACK=67108864` fixes it. The release binary never aborts on any of these trees. I didn't minimise it further; the repro trees are copied at `…/yamlbugs.hNgJ/copy-tca` and `copy-ttyp`.
- **Workaround.** Debug through scratch `test` blocks or named functions (`baml_src/tests/zz_tpar_debug.baml`, `baml_src/zz_tmp.baml`).
- **Cost.** It made quick probing unreliable for the whole sub-agent phase, and 5 agents recorded it as a BAML bug.
- **Verified:** VERIFIED on the debug build; NOT REPRODUCED on release. **Issue:** none.

### A1. `&&` / `||` don't narrow their right operand

- **Category / severity:** a, spurious error. The single most frequent compile error in C's library port: about 30 sites across `parser.baml`, `cst_visit.baml`, `compose-*.baml`, `resolve-*.baml`, `stringify.baml`, `directives.baml`, `bool.baml`, `cst_scalar.baml` and `_expect.baml` (C[L817–L960 19:26–19:28], C[L1403–L1480 19:49–19:50]); later in `src/cli.baml` (S-misc[L331 20:04]).
- **Repro (release):**
  ```baml
  class T { type: string }
  function a1(t: T?) -> bool { t != null && t.type == "x" }                         // E0007 `T | null` has no member `type`
  function a2(t: T?) -> bool { if (t == null || t.type == "x") { true } else { false } }  // E0007
  function o1(ce: int?, offset: int) -> bool { ce != null && ce < offset }         // E0004 cannot order `int | null` and `int`
  ```
- **Workaround.** `fc.fcStart?.type == "flow-seq-start"` (`src/parse/parser.baml:85`); `last?.type == "comment"` (`:595, :896`); `kt?.collection == expType && kt != null` (`src/compose/compose-collection.baml:98`); `(nl?.offset ?? 0) < lp.offset`; `next?.starts_with("-") ?? true` (`src/cli.baml`); a sentinel `let itx = it ?? collection_item([])` in the parser's flow-collection code; nested `if`s.
- **Cost.** 85 `?.` uses in `src`, several `?? dummy` sentinels that change the code's shape, and readability losses where `?.` stands in for a null check.
- **Verified:** VERIFIED. **Issue:** none.

### A2. A lambda-captured local loses narrowing everywhere in the function

- **Category / severity:** a, spurious error.
- **Observed.** C bisected an E0007 inside `Parser.pop` (C[L874–L888 19:27]): a local narrowed by an early `return` lost narrowing *before* the lambda too, once any lambda captured it.
- **Repro (release):**
  ```baml
  class T { type: string }
  function c1(e: T?, xs: T[]) -> bool {
    let token = e;
    if (token == null) { return false; }
    let a = token.type;                                  // E0007
    xs.every((st: T) -> bool { st.type == token.type })  // E0007
  }
  ```
- **Workaround.** `let tok: Token = token;`, capturing `tok` (`src/parse/parser.baml:320`); 12 such rebinds in `src`.
- **Verified:** VERIFIED. **Issue:** none.

### A3. Field accesses never narrow (including nullable function fields)

- **Category / severity:** a, spurious error. This was the largest source of boilerplate.
- **Observed.** C's probe `if (t.resolve != null) { t.resolve("abc") }` → `error[E0006]: ((string) -> unknown throws never) | null is not a function and cannot be called` (C[L542 19:17]); `if (t.items != null) { t.items.push(1) }` → E0007 (C[L636 19:19]). E hit the same thing with `if (h.cb) { h.cb(2, "a") }`.
- **Repro (release):** both still fail (E0007, E0006).
- **Workaround.** Local copies (`let oe = onError; if (oe != null) { oe(…) }` in `src/parse/cst_scalar.baml:15`; `let t = boolObj.testFn;` in `src/schema/yaml-1.1/bool.baml:7`). Accessor helpers `titems/tend/tstart/tsrc/tindent/tprops` (`src/parse/cst.baml:66–80`) return `?? []` / `?? ""` defaults. They are called 135 times.
- **Cost.** The main reason `parser.baml` and `YAMLMap.baml` are about 1.45× the TS line count (post-mortem §2).
- **Verified:** VERIFIED. **Issue:** none.

### A4. `?.` strips only one level of optional

- **Category / severity:** a, spurious error.
- **Observed.** `doc/types.baml:111:29-111:42 error[E0007]: type baml.regex.Group | null has no member text` on `m.groups.at(1)?.text` (S-typ[L196–L244 20:02–20:03]).
- **Repro (release):** `function q1(g: (T | null)[]) -> string { g.at(1)?.type ?? "" }` → E0007; `g[1]?.type` compiles.
- **Workaround.** `g[1]?.text` (`tests/doc/types.baml:111`); `m?.groups?.at(1)` plus a null check in `splitLines`.
- **Verified:** VERIFIED. **Issue:** none.

### A5. An unnecessary `?.` is a hard error

- **Category / severity:** a, spurious error.
- **Observed.** `resolve-block-scalar.baml:256:32-256:40 error[E0004]: did you mean g1.text? g1?.text is unnecessary, because g1 cannot be null` (C[L1403 19:49]).
- **Repro (release):** `function u1(g: T?) -> string { if (g != null) { g?.type ?? "" } else { "" } }` → E0004.
- **Why it matters.** Together with A1–A3, agents reach for `?.` defensively, and code that was fine before a refactor becomes an error after it. Like A6 and A7, this is a lint that is a hard error.
- **Workaround.** `let lead = if (g1 != null) { g1.text } else { "" };` (`src/compose/resolve-block-scalar.baml:246`).
- **Verified:** VERIFIED. **Issue:** none.

### A6. An unreachable `match` arm is a hard error (E0063)

- **Category / severity:** a, spurious error.
- **Observed.** E: `let sw = match ("|") { "|" | ">" => "block", _ => "other" };` → `error[E0063]: unreachable arm` on the `_` arm. The agent first suspected a different `match`, isolated three variants, then made the scrutinee non-constant with `match (s.slice(0,1))` (E[L574–L597 00:27]).
- **Repro (release):**
  - `function f() -> string { match ("|") { "|" | ">" => "block", _ => "other" } }` → E0063.
  - While verifying C1, I hit it again: `match (b) { let c: reflect.AnyClass => c.name(), _ => "?" }` on a value of known class type → E0063. Generated and templated code is fragile here.
- **Verified:** VERIFIED. **Issue:** none.

### A7. `throws unknown` "imprecise"/"unnecessary" is a hard error (E0097)

- **Category / severity:** a, spurious error.
- **Observed.**
  - C's interface probe: ``error[E0097]: `throws unknown` is imprecise: this function only throws `JsError`…`` (C[L1020 19:29]).
  - S-spec: `function f() -> null throws unknown { expect_true(false, "x") }` (S-spec[L163 20:00]).
  - S-vis: about 20 E0097s in generated `visit.baml` lambdas; the generator was changed to drop the clause (S-vis[L123–L129 20:00]).
  - S-vis's attempt to fix A8 with `function thr() -> null throws unknown { … throw "x" … }` was rejected as imprecise (S-vis[L76 19:58]).
- **Repro (release):** `function f() -> null throws unknown { throw E1 { m: "x" } }` → imprecise; `function g() -> int throws unknown { 1 }` → unnecessary; the same on a lambda.
- **Verified:** VERIFIED. **Issue:** none.

### A8. `Future<T, never>` is not assignable to `Future<T, unknown>`

- **Category / severity:** a, spurious error.
- **Observed.** S-vis[L63–L82 19:58]: `expected baml.future.Future<R, unknown>, found baml.future.Future<R, never>`, even with `let fu: baml.future.Future<R, unknown> = spawn {…}`. The value type is invariant too: `spawn { null }` is `Future<null, never>`, not `Future<R, …>`.
- **Repro (release):**
  ```baml
  type R = int | null
  function f() -> baml.future.Future<R, unknown> { let fu: baml.future.Future<R, unknown> = spawn { let y: R = 1; y }; fu }  // E0001
  ```
- **Workaround.** `function tvis_rethrow(e: unknown) -> null { if (e != null) { throw e; } null }`, called as `tvis_rethrow(null)` inside every `spawn` so the body "may throw unknown" (`tests/visit.baml:77, 87`; probe `…/scratchpad/vis/baml_src/a.baml`).
- **Verified:** VERIFIED. **Issue:** none.

### A9. Function types must declare `throws` (E0151)

- **Category / severity:** a, ergonomics.
- **Observed.** `function mk() -> () -> int {…}` → `error[E0151]: function type must declare an explicit throws clause; add throws never if calling it cannot throw` (C[L596 19:18]; E[L338 00:18]).
- **Repro (release):** same → E0151.
- **Workaround.** Every function-typed field and alias carries `throws unknown` or `throws never` (`type Reviver = (…) -> unknown throws unknown`, `type Callback = () -> void throws never`, all `VisitorFns` fields). Combined with A7, the author must pick the exact clause for aliases but must not over-declare on implementations.
- **Verified:** VERIFIED. **Issue:** none.

### A10. `unknown` class fields are required in literals

- **Category / severity:** a, ergonomics.
- **Observed.** ``js.baml:20:3-20:46 error[E0001]: class `JsError` is missing required field: `extra` `` ×4 (C[L763 19:21]).
- **Repro (release):** `class U { a: int, extra: unknown }  function f() -> U { U { a: 1 } }` → E0001.
- **Workaround.** `extra: unknown?` (`src/js.baml:16`).
- **Verified:** VERIFIED. **Issue:** none.

### A11. `match` with an empty-array arm needs an annotation (E0155)

- **Category / severity:** a, ergonomics.
- **Observed.** `_expect.baml:265:16-265:18 error[E0155]: type annotations needed` (C[L1571 19:53]).
- **Repro (release):** `let fields = match (a) { let s: string => [s], _ => [] };` → `E0155 type annotations needed / full type: unknown[]`. The message states the full type it claims not to know.
- **Workaround.** `let fields: string[] = match (a) {…}`.
- **Verified:** VERIFIED. **Issue:** none.

### A12. Keywords as identifiers: `test`, `enum`, `self`

- **Category / severity:** a, ergonomics and diagnostics.
- **Observed.**
  - `class Tag { test: ((string) -> bool throws never)? }` → 5 cascading E0010s ending in "expected `test body`" (C[L664 19:19]).
  - A local named `test` in `stringifyString` (C[L1471 19:50]).
  - `function yamlOMap_toJS(self: YAMLSeq, …)` → `expected ')' found ':'` plus a cascade (C[L1445 19:50]).
- **Repro (release):**
  - `class Tag { test: string? }` → 5 errors.
  - `let test = 1;` → 7 errors, including "test blocks are only allowed at the top level".
  - `function f(self: S)` → 10 errors.
  - `class J { enum: int? }` → `E0107 enum is missing a name` plus a cascade.
  - `match`, `if` and `let` are also rejected as field names. `const`, `then`, `not`, `type` and `default` are **accepted** (see M3).
- **Workaround.** `testFn` (`src/schema/types.baml`); `om` (`src/schema/yaml-1.1/omap.baml:20, 48`); `enum_` (plus unnecessary renames of the others) in `src/schema/json-schema.baml`.
- **Verified:** VERIFIED. **Issue:** none.

### A13. A statement starting with `[` after a block is parsed as an index expression

- **Category / severity:** a, spurious error.
- **Observed.** `lexer.baml:166:20-166:21 error[E0010]: unexpected token primary: expected ']', found ','`, at 5 sites (C[L817 19:26]); `parse.baml:69:4 … expected expression, found ']'` (S-par[L154 20:02]).
- **Repro (release):**
  ```baml
  function f(c: bool) -> int[] { let i = 0; if (c) { i += 1; } [i, 2, 3] }   // E0010 ×3
  ```
- **Workaround.** `return [s.slice(at, i), spaces, comment];` (`src/parse/lexer.baml:166, 208` and 3 more); `return [];` in `tests/doc/parse.baml` `tpar_array_from`.
- **Verified:** VERIFIED. **Issue:** none.

### A14. No class field defaults, and a garbled parse error

- **Category / severity:** a/d, missing feature plus a bad diagnostic.
- **Observed.** E[L320 00:18]: `class Node { value: unknown, mark: int = 0, tag: string? = null }` → ``expected `Unexpected token in class body`, found `'='` `` and `field 'null' is missing a type annotation`.
- **Repro (release):** `class N { mark: int = 0 }` → ``error[E0010]: unexpected token primary: expected `Unexpected token in class body`, found `'='` ``. The error text is inserted where the expected-token name should be.
- **Workaround.** Optional fields plus explicit values in every literal; `Options` has ~40 nullable fields resolved with `?? default` at each use.
- **Verified:** VERIFIED. **Issue:** none.

### C1. `reflect.AnyClass.name()` includes generic arguments

- **Category / severity:** c, wrong-result hazard.
- **Observed.** `t_class_name(v) == "JsMap"` never matched, because the name was `JsMap<Pair>`/`JsMap<unknown>`. Every `_map(...)`/`_set(...)` `toMatchObject` failed (13 in comments alone). S-ca, S-anc, S-com and S-par all hit it; S-ca and S-anc fixed it concurrently (S-ca[L79–L143 19:59–20:00]; S-anc[L118–L163 19:59–20:00]).
- **Repro (release):**
  ```baml
  class Box<V> { v: V }
  function nm(u: unknown) -> string { match (u) { let c: reflect.AnyClass => c.name(), _ => "?" } }
  // nm(Box { v: 1 }) → "Box<int>"; nm(Box<string> { v: "a" }) → "Box<string>"
  ```
- **Workaround.** `c.name().split("<")[0]` (`tests/_expect.baml:32`) and `starts_with("JsMap")` (`:139, :604`). There's no API for the unapplied name.
- **Verified:** VERIFIED. **Issue:** none.

### C2. 63-bit `int`; overflow panics

- **Category / severity:** b/c, crash in a literal port.
- **Observed.** `baml.panics.IntegerOverflow { message: "1231231231231231231 * 10 overflows int" }` from `js_parse_int` on 8 json-test-suite files. Also ``error[E0150]: integer literal `9223372036854775807` is out of range for `int` (which holds -4611686018427387904 to 4611686018427387903)`` (S-misc[L181–L237 20:00–20:01]).
- **Repro (release):** `let x = 922337203685477580; x * 10` → IntegerOverflow panic; the literal → E0150.
- **Workaround.** Guard `v > (4611686018427387903 - d) / radix`, then fall back to `baml.Float.parse` (`src/js.baml:1023`).
- **Verified:** VERIFIED. **Issue:** none.

### C3. `baml.fs.read` has no lossy UTF-8 mode

- **Category / severity:** c, missing feature.
- **Observed.** 28 json-test-suite files are not valid UTF-8; `readFileSync(p, 'utf8')` in JS decodes them lossily (S-misc[L73–L94 19:58]).
- **Repro (release):** `baml.fs.read` on a file starting `\xff\xfe` throws (`ParseError`); `describe baml.fs.read` confirms.
- **Workaround.** `baml.fs.open(path, "r").bytes().to_string()` in `tjts_read` (`tests/json-test-suite.baml`).
- **Verified:** VERIFIED. **Issue:** none.

### C4. No "read all of stdin"

- **Category / severity:** c, missing feature.
- **Observed.** `baml.io.input` reads one line and "end-of-input reads as `""`" (its docstring), so an empty line can't be told apart from EOF (S-misc[L67 19:58], L264).
- **Workaround.** `baml.fs.open("/dev/stdin", "r").text()` (`src/cli.baml:475`), which is Unix-only.
- **Verified:** VERIFIED (from `describe`). **Issue:** none.

### C5. `array.insert(item, idx)` argument order

- **Category / severity:** c/f, ergonomics.
- **Observed.** `tests/cst.baml:127:35 error[E0001]: expected CollectionItem, found int` plus the mirror error (S-cst[L63 19:58]).
- **Repro (release):** `xs.insert(0, c)` → two E0001s with no hint about order.
- **Workaround.** `insert(ci, idx)` (`tests/cst.baml:127`).
- **Verified:** VERIFIED. **Issue:** none.

### C6. `int` has no `to_float()`

- **Category / severity:** c, ergonomics.
- **Observed.** ``js.baml:905:12 error[E0007]: type `int` has no member `to_float` `` ×3 (S-misc[L204–L218 20:00]).
- **Repro (release):** `function f(i: int) -> float { i.to_float() }` → E0007.
- **Workaround.** `i * 1.0` everywhere (`src/js.baml`).
- **Verified:** VERIFIED. **Issue:** none.

### C7. Out-of-range indexing panics

- **Category / severity:** b, crash in a literal port. By design.
- **Observed.** `path[path.length() - 1]` on an empty path → `IndexOutOfBounds(-1)` in `replaceNode` (S-vis[L138–L146 20:01]); collection-access used `seq.at(i)` (S-ca).
- **Repro (release):** `let a: int[] = []; a[a.length() - 1]` → `uncaught throw: baml.panics.IndexOutOfBounds {index: -1, length: 0}`.
- **Workaround.** `let parent: VisitPathItem? = if (path.length() > 0) { … } else { null };` (`src/visit.baml:376`).
- **Verified:** VERIFIED. **Issue:** none.

### C8. Float formatting isn't JS's

- **Category / severity:** c, ergonomics. Expected for a non-JS language.
- **Repro (release):** `[1.0.to_string(), 1e21.to_string(), 1e-7.to_string(), (-0.0).to_string()]` → `["1.0", "1000000000000000000000.0", "0.0000001", "-0.0"]` (C[L724 19:20]; E[L327 00:18]).
- **Workaround.** `js_number_to_string` (`src/js.baml:463`, about 100 lines).
- **Verified:** VERIFIED. **Issue:** none.

### C9. No percent-decoding

- **Category / severity:** c, missing feature.
- **Workaround.** A hand-written `decodeURIComponent` that throws `URIError` (`src/doc/directives.baml` ~240–285).
- **Verified:** UNVERIFIED (nothing in `describe baml`). **Issue:** none.

### E1. `string.at(i)` / `string.slice(i, j)` are O(i)

- **Category / severity:** e, perf (high).
- **Observed.** C's debug-build probe: `.at(i)` loop 1.16 s → 3.18 s for 10k → 40k chars; `.slice(i, i+5)` 0.59 s → 6.50 s; `to_code_points()` + index 0.23 s → 0.29 s (C[L581–L593 19:18]). E's debug build: `perf_at` 17.9 s → 128.9 s for 1k → 10k.
- **Re-check (release, one loop over the whole string):**

| n | `.at(i)` ASCII | `.at(i)` with a leading `é` | `.slice(i, i+5)` ASCII | `to_code_points()` + index |
|---|---|---|---|---|
| 40k | 0.15 s | 0.16 s | 0.20 s | 0.10 s |
| 80k | 0.31 s | 0.32 s | 0.51 s | 0.10 s |
| 160k | 0.95 s | 0.95 s | 1.79 s | 0.10 s |

  Both grow superlinearly even on pure ASCII (the post-mortem's "ASCII fast path" for `.at` isn't visible at these sizes).
- **Workaround.** `class Src { chars, codes }` (`src/js.baml:714`), with the lexer's scanners working over it; the five sticky regexes were hand-written partly for this reason (F3).
- **Verified:** VERIFIED. **Issue:** none.

### E2. Interpreter throughput

- **Category / severity:** e.
- **What's known.** The post-mortem (§3) measured release BAML at ~100–200× Node for `parse`/`stringify`, and ~945× for `stringify(value)` on 144 KB, which is quadratic because of F1's association list in `NodeCreator`. S-typ found property tests slow: 100 round trips took 12 s and 600 took 86 s (debug), so the port keeps 100 fixed-seed cases (S-typ[L273–L279 20:05–20:06]).
- **Verified:** VERIFIED by the post-mortem, not re-run here. **Issue:** none.

### F-t1. One compile error blocks every test and every `run`

- **Category / severity:** f, ergonomics. Severity is high for parallel work.
- **Observed.** A sibling's half-written `collection-access.baml` (`expected ToJSContext, found null`) and `json-test-suite.generated.baml` (``unresolved name: `tjts_testSuccess` ``) broke `$B test` and `run -e` for everyone (C[L1864–L1870 19:58]; S-spec[L94 19:58]; S-str[L116 19:58]; S-par[L97 19:58]). C added a "work in a private copy" protocol mid-run (C[L1882 19:59]).
- **Repro (release):** a project with `bad.baml` (`function bad() -> int { "x" }`) plus a passing test: `baml-cli test -i "root::good"` prints the error and runs nothing.
- **Workaround.** 11 private rsync copies; files only synced back once they compiled.
- **Verified:** VERIFIED. **Issue:** none.

### F-t2. Stdlib warnings leak into every user check

- **Category / severity:** f, diagnostic noise.
- **Observed.** From C's first `check` on (C[L763 19:21]) and in E: `csv.baml:402:13-402:66 warning[E0146]: unreachable code: 1 statement(s) after diverging statement`, plus 10 more in `csv`, `iter`, `stream`, `ns_internal/wire` and `ns_mcp`. Commit `f603110e74` (#4995, the commit right before this run's base) says "Eleven unreachable-code warnings are deliberate standard-library fallbacks", but they still reach users.
- **Repro (release):** `baml-cli check` on a one-function project prints all 11.
- **Workaround.** `check.sh` greps out `^(csv|iter|stream|ns_internal|ns_mcp)`.
- **Verified:** VERIFIED. **Issue:** none.

### F-t3. Panic tracebacks aren't elided

- **Category / severity:** f, diagnostic.
- **Observed.** S-anc and S-par had to filter about 250 identical `File "…", line 255, in user.t_equal` lines (S-anc[L113–L169 19:59–20:00]; S-par[L276–L293 20:04]).
- **Repro (release):** `rec(300)` prints ~256 identical `in user.rec` lines before `uncaught throw: baml.panics.StackOverflow`.
- **Verified:** VERIFIED. **Issue:** none.

### F-t4. Function entry points and argv

- **Category / severity:** f/c, ergonomics.
- **Observed.** S-misc[L264–L272 20:01–20:02]:
  - `baml run tmp_argv -- --args x --args y` → `error: unexpected argument '--args' found`.
  - `--json-args '["x"]'` → `error: --json-args must be a JSON object`.
  - `baml.sys.argv()` → `["…/baml-cli", "tmp_argv", "--json-args", "{…}"]`.
- **Repro (release):** identical output.
- **Workaround.** `yaml_cli(args: string[])` invoked as `baml run yaml_cli -- --json-args '{"args": [...]}'` (`src/cli.baml:11`).
- **Verified:** VERIFIED. **Issue:** none.

### F-t5. Named-argument error doesn't show the syntax

- **Category / severity:** f, diagnostic.
- **Observed.** `Xoshiro256PlusPlus.new(u8)` → ``error[E0005]: defaulted parameter `seed` must be passed by name``; the agent's `new(seed: u8)` → `E0010 expected ')' found ':'`; `new(seed = u8)` works (S-typ[L262–L273 20:04–20:05]).
- **Verified:** VERIFIED. **Issue:** none.

### F-t6. Test results aren't streamed

- **Category / severity:** f, ergonomics.
- **Observed.** C's first full yaml-test-suite run printed nothing after 4 CPU-minutes, and C assumed an infinite loop (C[L1662–L1675 19:55]). The later run took 39 s wall with the debug build.
- **Re-check (release).** With a `fast` (0 ms) and a `slow` (6.5 s) test and stdout redirected to a file, nothing but the startup warning had appeared after 3 s; both lines appeared at the end. I didn't test a real TTY.
- **Verified:** VERIFIED (redirected output). **Issue:** none.

### F-t7. No test skip

- **Category / severity:** f.
- **Workaround.** 17 `// UNPORTABLE` bodies that pass trivially, so the runner overstates passes (e.g. "the runner reports 44 passed" for 43 + 1 skipped). This is why the post-mortem's 3,413 includes 23 placeholders.
- **Verified:** VERIFIED (no syntax found). **Issue:** none.

### F-t8. The documented dev build is a debug build

- **Category / severity:** f/g.
- **What happened.** `TEST_INSTRUCTIONS.md` says `cargo build -p baml_cli  # produces target/debug/baml-cli`, and the task prompt said the same. All agents used a 364 MB debug binary. It is ~11× slower (`check` 8.4 s vs 0.96 s; the suite ~99 s vs ~19 s, post-mortem §3), and it is the only build with B7. Several "BAML is slow" and "`run -e` crashes" notes come from this.
- **Verified:** VERIFIED (via the post-mortem's measurements and B7). **Issue:** none.

### F-t9. Nullable interpolation is a hard error

- **Category / severity:** a, ergonomics. Arguably intended.
- **Repro (release):** ``function f(s: string?) -> string { `x ${s}` }`` → `E0001 cannot interpolate a value of type string | null`.
- **Workaround.** `?? "…"` everywhere (C[L571 19:17]; E[L320–L353 00:18]).
- **Verified:** VERIFIED. **Issue:** none.

### F1. No reference identity

- **Category / severity:** d, missing feature (high).
- **Observed.** Upstream uses `===`, `Map<object, …>` and `WeakMap` everywhere (anchors, `NodeCreator.#sourceObjects`, `ToJSContext.anchors`, `reviverSources`, `Alias.resolve`).
- **Workaround.**
  - `_id: int` from `SystemRandom` on 16 classes; `js_same` compares ids.
  - Maps and arrays are probed by mutation (`js_identical`, `src/js.baml:803`).
  - `NodeCreator` and `ToJSContext.reviverSources` use association lists searched linearly (`src/doc/NodeCreator.baml:29`, `src/nodes/toJS.baml:19`).
- **Cost.**
  - 2 tests still fail (`collection-access › Map › object key equality`, `Set › get`).
  - `createNode` is O(n²) (E2).
  - Empty typed containers can't be told apart (B3).
- **Verified:** VERIFIED (`let a: int[] = [1]; let b: int[] = [1]; a == b` is `true` with no identity operator). **Issue:** none.

### F2. Map keys must be `string`

- **Category / severity:** d, missing feature.
- **Repro (release):** `let mp: map<unknown, int> = {};` → ``error[E0067]: map keys must be `string`; got `unknown` `` (E[L320 00:18]).
- **Workaround.** `class JsMap<V>` with `_keys: unknown[]`, `_vals: V[]`, `_index: map<string, int>` keyed by `js_key`, and a linear scan otherwise (`src/js.baml`); `JsSet` wraps it.
- **Verified:** VERIFIED. **Issue:** none.

### F3. No sticky or positional regex matching

- **Category / severity:** d/c, missing feature.
- **Workaround.** The five `/…/y` regexes in `lexer.ts` became hand-written scanners, with the pattern quoted above each (`src/parse/lexer.baml:3–6`). Anchoring against a slice would be O(n) per call (E1).
- **Cost.** The lexer is 1.64× the TS line count.
- **Verified:** UNVERIFIED. **Issue:** none.

### F4. No module-level constants

- **Category / severity:** d.
- **Observed.** E[L320]: ``error[E0010]: top-level `let` bindings are not supported``.
- **Workaround.** Zero-argument functions: `BOM()`, `DOCUMENT()` (`src/parse/cst.baml:109–125`), `UserError_ARGS()` (`src/cli.baml:31`), `Scalar.PLAIN()`, `visit_BREAK()`. Built-in tags get fixed `_id`s, since a shared instance can't exist. `Symbol.for` derives its `_id` from a hash of the key.
- **Verified:** VERIFIED (E). **Issue:** none.

### F5. No optional positional parameters

- **Category / severity:** d, missing feature with high boilerplate.
- **Workaround.**
  - Explicit `null`s: about 1,100 `, null)`/`(null` patterns across src+tests, including 261 `toString(null…`.
  - Split APIs: `set` / `setWithOptions` (`src/nodes/YAMLMap.baml:198`); `NodeCreator.new` / `fromSchema`.
  - The guide's API map documents a `null`-argument convention.
- **Verified:** UNVERIFIED. **Issue:** none.

### F6. No `x!` and no checked downcast

- **Category / severity:** d.
- **Workaround.** Match-or-throw helpers: `tcom_scalar`/`tcom_seq`/`tcom_map`/`tcom_pair` (`tests/doc/comments.baml`), `tn2j_to_js` (`tests/node-to-js.baml`), `tdir_scalar`, `tffl_*`.
- **Verified:** UNVERIFIED. **Issue:** none.

### F7. No inheritance; unions expose no shared members

- **Category / severity:** d.
- **Repro (release):** `type N = A | B` where both classes have `comment: string?`; `n.comment` → ``E0007 type `A | B` has no member `comment` `` (E[L468 00:25]). It works through an interface: `let b: NB = n; b.comment = …`.
- **Workaround.**
  - `interface NodeBase` with fields plus `nb(node)` (`src/nodes/types.baml`).
  - A `_class` discriminator for `YAMLOMap extends YAMLSeq` and `MergeKey extends Scalar` (`src/nodes/Scalar.baml:4`, `src/schema/yaml-1.1/omap.baml:4`).
  - `cloneMapOrSet` dispatches by hand instead of `new coll.constructor()`.
  - Tests can't express `class YAMLNullObject extends YAMLMap`.
- **Verified:** VERIFIED. **Issue:** none.

### F8. No `undefined`

- **Category / severity:** d.
- **Workaround.** A `js_undefined()` sentinel `JsSymbol` (`src/doc/applyReviver.baml:19`), used where upstream behaviour depends on it: `keepUndefined`, `stringify(undefined)`, replacer filtering and reviver deletion. Everywhere else it collapses to `null` (commit `3e3c1bb`).
- **Cost.** It fixed 8 tests at the end of the run.
- **Issue:** none.

### F9. Truthiness differs from JS

- **Category / severity:** d, wrong-result hazard. By design.
- **Repro (release):** `if ([])`, `if ({})` and `if ("")` are all falsy.
- **Workaround.** `js_truthy` (`src/js.baml:160`), and every upstream `if (it.sep)` was rewritten as `!= null`.
- **Verified:** VERIFIED. **Issue:** none.

### F10. JS value-model gaps

- **Category / severity:** d.
- **Gaps.** No property setters (`Alias#tag`), no boxed primitives, no array holes, no lone UTF-16 surrogates.
- **Cost.** 10 UNPORTABLE stringify tests, 1 anchors test and 4 failures: `OMap › set` hole plus 3 json-test-suite surrogate cases.
- `YAMLSeq._setIndex` fills gaps with `Scalar(null)` (`src/nodes/YAMLSeq.baml:213`).

### F11. No dynamic import

- **Workaround.** `--visit` uses an injected `importVisitor` (`src/cli.baml`); the tests supply BAML ports of the two visitor modules.

### F12. Static tests; no `beforeEach`

- **Workaround.**
  - `tools/gen_yaml_test_suite.py`, `gen_json_test_suite.py` and `gen_yaml12_spec.cjs` (3,241 generated lines).
  - Hand-unrolled loops.
  - A throwaway template produced two copies of the 18 visit tests, because `visit`/`visitAsync` have different visitor types.
  - Per-test factories (`tca_mapDoc()`) instead of `beforeEach`.

### F13. No output capture or mocking in tests

- **Workaround.** `warn()` writes via `baml.io.eprintln` (`src/log.baml:17`). Three `logLevel` tests are UNPORTABLE, and 8 `emitWarning` assertions were dropped (spec tests, doc/parse).

### F14. Backtick strings are dedented and trimmed

- **Category / severity:** d. By design since #4914.
- **Repro (release):** a backtick literal containing `\n    a\n    b\n  ` → `"a\nb"`.
- **Workaround.** `source(…) + "\n"` or a `tcom_src`/`tstr_src` wrapper at 86 sites; plain `"…"` strings where leading or trailing blank lines matter. 5–20 tests per file failed until this was found; four agents found it independently.
- **Verified:** VERIFIED. **Issue:** #4591 (related, open).

### F15. Namespace and type-system shape

- **Flat namespace.** Collisions were renamed: `stringify` → `stringifyNode`, `CST.visit` → `cst_visit`. `ns_` directories would need `root.ns.` qualification everywhere.
- **No tuple types.** `Range = int[]`.
- **No intersection or object-literal types.** A single `Options` class with six aliases.
- **No `this`.** The reviver's holder is a 4th argument.
- **No constructor reflection.**

### F16. `baml.random` is minimal for property testing

- **What exists.** `Int.random(lower, upper, rng)`, `Float.random(rng)` and `Float.pow`, which the agent missed (M8).
- **What's missing.** Choice, generators and shrinking.
- **Workaround.** Hand-written `tprop_*` generators seeded with `Xoshiro256PlusPlus`, 100 fixed cases (`tests/properties.baml`).

## Agent mistakes (details)

- **M1/M2 (`run -e` crashes and slowness).** See B7 and F-t8. On release, `run -e 'root.js_typeof(1)'` etc. take ~1.2 s on the full port and never crash.
- **M3.** C ran `sed` over `json-schema.baml` renaming `const/enum/then/not/default/type` → `*_` preemptively (C[L1438 19:49]). Release accepts all of these as field names except `enum`. PORTING_NOTES #17 overstates the problem.
- **M4.** `TEST_PORTING_GUIDE.md` says "Test names must be unique within their testset". S-str renamed three upstream tests (`number (-0) …`, two surrogate names, a second `default`). The release runner accepts duplicates (`PASS root::s::same`, `PASS root::s::same#2`).
- **M5.** C assumed `Regex.split` omits capture groups and wrote `splitLines` to re-extract them. That broke every block scalar and made all 6 yaml-test-suite checks for 229Q fail with `BAD_INDENT`. It probed at C[L1702 19:56] and simplified.
- **M6.** C thought BAML "silently picked one" of two `stringify` functions (C[L1407 19:49]); a probe showed E0011 is reported and its filtered view had hidden it (C[L1437]).
- **M7–M13.** See the table. They are all discoverability mistakes (`describe` would have answered them) or measurement artifacts.
- **Port and helper bugs the agents fixed.** These were never BAML bugs:
  - `applyReviver` removing array elements instead of leaving holes
  - `_setIndex` appending instead of filling gaps
  - `visitAsync` lacking the object-visitor form
  - `replaceNode` on an empty path
  - `toMatchObject` class-instance, Map-key and `{}` semantics
  - `t_equal`/`t_match` cycle handling
