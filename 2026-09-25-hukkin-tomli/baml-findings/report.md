# Post-mortem: porting hukkin/tomli to BAML

Report written 2026-09-27. Covers Orca run `run_3689c3c3cac4` / task `task_d20052dcd418`.

- Original: `<local>/work-repos/tomli` at `5a77b12` (tomli 2.4.1, pure Python, about 700 code lines).
- Port: `<local>/work-repos/tomli-baml`, 9 commits, `86cd9a6`..`fe320c8`, clean tree.
- Toolchain: `baml-cli` 0.20.1, built from `<local>/baml-worktrees/port-hukkin-tomli` at `e215c3de2d`. That worktree has no local changes, and the compiler was not modified.
- Porting agent's session: `<local>/transcripts/port-hukkin-tomli/510db4c0-732b-4c8a-ba77-6a47a79eca23.jsonl`. The agent is finished and its terminal `term_1fe4c56d…` is idle: "Crunched for 45m 51s · done 12:58 PM".

Labels used in this report:
- **[measured]**: I re-ran it for this report.
- **[agent claim]**: taken from `PORTING_NOTES.md` or the transcript without re-checking.

## 1. Summary

- **What was ported.** All four library modules are ported line by line, with the same function names, control flow, error messages and error positions. The modules are `__init__`, `_parser`, `_re` and `_types`, and they live in `baml_src/ns_tomli/`. A new `_compat.baml` (253 code lines) supplies the Python builtins the original relies on: `ValueError`/`TypeError`/`KeyError`/`RecursionError`, `repr`, `int(s, 0)`, `float(s)`, `str.find`/`count`/`rindex`, `chr`, `frozenset` and `warnings.warn`.
- **Tests.** All test modules are ported (`baml_src/ns_tests/`). So are `benchmark/run.py` and `profiler/profiler_script.py`. `fuzzer/fuzz.py` is not ported because it needs `atheris` and `tomli_w`. The packaging scripts don't apply.
- **Test pass rate [measured].** `baml-cli test` (release) reports **16 passed, 0 failed** in 0.7 s wall time. That includes **744/744 toml-test data cases**: 516 invalid, of which 11 non-UTF-8 files are skipped as in Python, and 228 valid. `tests/data` is byte-identical to upstream (`diff -rq` is clean).
- **Against upstream.** Upstream's `python3 -m unittest` runs 18 tests: 17 pass and `test_lazy_import` is skipped on Python < 3.15. Of those 18 methods, 15 are ported and pass. The other 3 are documented as not portable:
  - `test_type_error`: passing bytes to `loads` is a compile error in BAML.
  - `test_incorrect_load`: `baml.fs.File` has no text mode.
  - `test_lazy_import`.
  One port-only test was added. The `assertWarns` half of `test_deprecated_tomldecodeerror` can't be observed in BAML.
- **The tests can actually fail [measured].** I mutated one expected message in a copy, and `test_line_and_col` failed (15 passed, 1 failed). The porting agent ran a similar check at 19:31:59, after all 744 cases passed on the first try.
- **Effort.** The whole job took one autonomous 46-minute session.

## 2. Lines of code

**Method.** `tokei`, `scc` and `cloc` aren't installed, so I used a small Python counter. It counts code lines only, excluding blank lines and comment-only lines (`#`, `//`, `/* */`). Python docstrings (found via `ast`) count as comments. The script is `loc.py` in my scratchpad. Raw `wc -l` is 3,185 for the BAML sources.

| Category | Original (Python) | BAML port | Ratio |
|---|---|---|---|
| Library (`__init__`, `_parser`, `_re`, `_types`) | 695 | 1,156 | 1.66× |
| Python-builtin shims (`_compat.baml`, port-only) | — | 253 | — |
| **Library total** | **695** | **1,409** | **2.03×** |
| Tests (`tests/*.py` → `ns_tests/*.baml`) | 342 | 626 | 1.83× |
| Tooling (`benchmark/run.py`, `profiler_script.py`) | 54 | 141 | 2.6× |
| Port-only profiling (`ns_profiler/timings.baml`) | — | 256 | — |
| Language-gap repros (`repros/*.baml`) | — | 70 | — |
| Not ported (`fuzz.py`, `use_setuptools.py`) | 68 | — | — |

Per file: `_parser` goes from 594 to 918 lines, `_re` from 94 to 218, `burntsushi` from 76 to 227, `test_misc` from 148 to 189, and `test_error` from 82 to 94. There are also more comments: 253 comment lines in the library versus 100, mostly `NOTE:` comments explaining workarounds.

**Why the port is about 2× larger:**
- **No module-level constants.** Every `Final` constant becomes a zero-argument function. `ASCII_CTRL` goes from a one-line `frozenset(...)` to a 6-line loop. The regexes in `_re.baml` are built with `+` concatenation, one fragment per line, which accounts for most of `_re`'s 2.3×.
- **No tuples.** 56 uses of `Tuple2`/`Tuple3` in `_parser.baml`. Python's `pos, key = parse_key(src, pos)` becomes `let r = parse_key(...); pos = r.first; key = r.second;`.
- **Missing builtins.** Things Python gives for free have to be hand-written in `_compat.baml`: radix/underscore integer parsing, `float()` with `_`, `repr()`, `str.find(sub, start)`, sets and exception classes. `burntsushi.baml` also has to implement Python's `isoformat`/`str(date)`, which is why it tripled.
- **Narrowing gaps** force nested `if`s where Python uses `a or b` (§4).
- **`baml fmt` style.** Multi-line call arguments with trailing commas, and `catch (e) { _ => … }` blocks.
- **Where BAML is shorter.** `match` with typed arms replaces `isinstance` chains. Named-only defaults map directly onto Python's `*, parse_float=float`. `test_error`/`test_misc` stayed close to 1× because `assert.equal` is as terse as `self.assertEqual`.
- **Tooling ratio.** Inflated by reimplementing `timeit.repeat` and the f-string formats `{:.3g}`/`{:.2%}` by hand in `run.baml`.

## 3. Performance

**Hardware.** Apple M3 Max, 96 GB RAM, macOS 26.6.2. Python 3.13.5.

**Method.** The workload is upstream's `benchmark/data.toml` (4,021 bytes). The BAML side is the port's `baml_src/ns_benchmark/run.baml`, which mirrors `benchmark/run.py`: `min` over 5 repeats of N parses, with N = 20. I ran it 3 times from a copy in my scratchpad. The Python side is the same `min(timeit.repeat(..., repeat=5))` with N = 20 and N = 5000, run from a copy of the upstream `src/`. The `baml.toml` row is BAML's built-in Rust parser (`baml.toml.Table.parse`), which the port uses as its baseline.

| Parser | ms per parse [measured] | vs CPython tomli |
|---|---|---|
| BAML builtin `baml.toml.Table.parse` (Rust), release CLI | 0.062–0.074 | ~3.5× faster |
| CPython 3.13 `tomllib` (stdlib) | 0.24–0.25 | 1× |
| CPython 3.13 tomli, pure Python, upstream `src/` | 0.23–0.25 | 1× (reference) |
| **BAML port, release `baml-cli`** | **13.2–13.4** | **~55× slower** |
| BAML port, debug `baml-cli` (N = 2) | ~185 | ~750× slower (~14× slower than release) |

**Per value type** [measured, release, 100 `kN = <value>` lines]:

| Value type | BAML | CPython | Ratio |
|---|---|---|---|
| integers (`= 12345`) | 15.8 ms | 0.18 ms | ~87× |
| strings (`= "abc"`) | 3.2 ms | 0.12 ms | ~27× |
| bools (`= true`) | 1.1 ms | 0.10 ms | ~11× |

This matches the agent's diagnosis: any value that reaches the regex path (numbers, dates) recompiles up to three anchored regexes on every call. The regexes can't be hoisted because there are no module-level constants, and there's no `regex.match(s, pos)`. The agent's own figures were ~20 ms versus ~1 ms.

**Dev-loop timings [measured]:**

| | debug | release |
|---|---|---|
| `baml check` | 8.9 s | 0.27 s |
| full `baml test` | 8.2 s wall | 0.7 s wall |

**Tuning history [agent claim, consistent with the final measurement]:**
- The first working version took 74 ms per parse (release).
- Two workarounds (§4, bugs 7 and 8) brought it to 14 ms.

**Caveats:**
- The BAML port is a pure interpreter (bytecode VM) running tree-heavy code, while CPython tomli is interpreted Python. So 55× reflects VM and stdlib overhead, not a native-versus-interpreted gap.
- The Python numbers exclude interpreter start-up. The BAML numbers exclude compile time: roughly 0.3 s for release `check`, and run start-up is dominated by compiling the project and stdlib.
- `PORTING_NOTES.md` contradicts itself on the debug number. Its table says "6.8 s" for the first version, but §3.5 says "2.3 s in debug vs 74 ms in release". The "20–30× slower" claim fits the first version (2.3 s / 74 ms ≈ 31×). I measured the final version at ~14×.
- N = 20 for BAML versus N = 5000 for upstream's default. Python's result is the same at N = 20 and N = 5000 (0.23 vs 0.25 ms).

## 4. Bugs and gaps in the BAML language, compiler, runtime and stdlib

**Status for all of these.** The porting agent filed **no GitHub or Linear issues**: there are no `gh`/issue commands in the transcript and no issue URLs. It used workarounds and wrote repros instead. `origin/canary` is still `e215c3de2d` (fetched 2026-09-27), the commit the toolchain was built from. So "reproduces on canary" below means I re-ran `repros/run.sh` with that release binary on 2026-09-27. Repro files are in `<local>/work-repos/tomli-baml/repros/`.

**Severity scale:** Crash > Wrong result > Spurious error > Missing error > Perf > Missing feature > Ergonomics/diagnostic.

### 4a. Bugs

1. **Bare-boolean `test` bodies always pass.** Severity: **High** (wrong result: silent false-pass).
   - **Found by:** me, while writing this report. The porting agent did not find it.
   - **What happens:** `test "x" { 1 == 2 }` reports **PASS**, and so does `test "hex" { "a\x1bb".length() == 3 }`, even though that length is 6. `test "y" { assert.is_true(1 == 2) }` correctly fails.
   - **Why it matters:** GitHub #4765 ("String literals do not decode \xHH / \uHHHH escapes") was closed as COMPLETED on 2026-09-06. The withdrawal comment says the bug "does not reproduce" and cites exactly this kind of bare-expression test passing. That evidence is invalid.
   - **The port is not affected:** its tests all use `assert.*` (33 calls).
   - **Status:** not filed; reproduces at `e215c3de2d`.
   - **Evidence:** my probe project `scratchpad/esc/`.
2. **String escapes are decoded inconsistently and unknown escapes are silently kept.** Severity: **Missing error / wrong result.**
   - **Repro** (`r05`, plus my extended probe):

     | Literal | `.length()` | Decoded? |
     |---|---|---|
     | `"\x1b"` | 4 | no |
     | `"\u{1b}"` | 6 | no |
     | `` `\u001b` `` | 6 | no |
     | `"\u001b"` | 6 | no (control character) |
     | `"A"` / `"é"` | 1 | yes |
     | `"\q"` | 2 | kept as-is, no error |

   - **Correction to the agent's notes:** they say `\uNNNN` isn't supported. In fact it works in `"…"` for non-control code points.
   - **Workaround:** `baml.String.from_code_points`.
   - **Status:** #4765 was closed on the flawed evidence described in bug 1. The bug still reproduces, so the issue should be reopened.
3. **Stack overflow is uncatchable, even by `catch_all`.** Severity: **High** for any recursive-descent code. The limit is 256 frames (Python's is 1000).
   - **Repro** (`r10`): `r10(300) catch_all (e) { _ => -1 }` gives "uncaught throw: baml.panics.StackOverflow".
   - **Source:** `MAX_FRAMES = 256` is hard-coded in `baml_language/crates/bex_vm/src/vm.rs:118`. It can't be configured or queried.
   - **Impact on tomli:** it failed at 83 nested inline tables and 123 nested arrays, so the two recursion-limit tests failed.
   - **Workaround:** `_nested()` in `_parser.baml:68` does `await spawn { f() }` every 20 levels, because each task gets a fresh stack. That restores the 1000-level limit, and typed errors still propagate. The agent found and implemented this in about one minute (19:35:39 to 19:36:34).
   - **Status:** not filed. Related to open #4967 (`catch_all` doesn't catch `assert.*` failures).
4. **No narrowing across `||`.** Severity: Spurious error (`r01`).
   - **Repro:** `if (d == null || d >= base)` gives E0004 "cannot order `int | null` and `int`".
   - **Workaround:** nested `if`s.
   - **Status:** not filed; reproduces.
5. **A `never`-returning call used as a statement doesn't end the flow for narrowing.** Severity: Spurious error (`r02`).
   - **Repro:** after `if (idx == null) { baml.sys.panic("…"); }`, `idx + 1` gives E0004.
   - **Status:** not filed; reproduces.
6. **Closures lose the narrowing of captured variables.** Severity: Spurious error (`r04`).
   - **Repro:** calling `f(s)` in a closure after an `f == null` early return gives E0006.
   - **Note:** the repro also triggers an unrelated E0151 (an inline function type needs `throws`), so it isn't perfectly minimal.
   - **Workaround:** rebind to a narrowed local first.
   - **Status:** not filed; reproduces.
7. **`?.` on `map<string, G?>.get()` is rejected.** Severity: Spurious error (`r03`).
   - **Repro:** gives E0007 "type `G | null` has no member `text`". The `T??` result isn't flattened.
   - **Status:** not filed; reproduces.
8. **Failing run-time type tests against a recursive-alias container are slow.** Severity: **Perf**, severe (`r11`).
   - **Numbers [measured, release]:** `true is V[]` takes 12 µs for a 3-member alias and 27 µs for a 7-member alias. A succeeding test takes 0 µs. The agent measured ~170 µs for tomli's 11-member `Value`.
   - **Impact:** 60% of parse time before the workaround [agent claim].
   - **Workaround:** order `match` arms with scalars first, and check for dicts before lists.
   - **Status:** not filed.
9. **`Array.join` is slow.** Severity: Perf (`r12`).
   - **Numbers [measured]:** 137 µs for 33 one-character strings, versus 10 µs for a concatenation loop. The cause is a BAML-level implementation that calls `string.from` per element.
   - **Status:** not filed.
10. **Wrong or unhelpful diagnostics.** Severity: Diagnostic.
    - `const X = 1;` at top level says "top-level `let` bindings are not supported" (`r07`).
    - Using `match` as a parameter name produces 10 cascading "unexpected token" errors instead of "reserved keyword" (`r06`).
    - Every `check`/`test`/`run` prints about 11 E0146 "unreachable code" warnings from the **stdlib** (csv, iter, stream, wire, mcp). These are probably from `f603110e74`, which landed just before the port's base commit.
    - `E0097`: `throws unknown` on a closure is rejected as "unnecessary", so you can't widen a closure's `throws` to match a type alias (`r09`).
11. **`baml-cli` refuses to run without the "BAML agent skill" installed.** Severity: Ergonomics. Needs `BAML_AGENT_SKILL_CHECK=off` [agent claim; the port's `.tools/b` wrapper sets it].

### 4b. Missing features that forced workarounds

These aren't bugs, but they drove most of the code growth and the performance cost:

- No module-level `const`/`let` (`r07`), so nothing can be cached. This is the biggest performance cost.
- No tuples.
- Defaulted parameters must be passed by name, and there are no varargs (`r08`).
- No inheritance, so `TOMLDecodeError(ValueError)` doesn't work and catch sites list `ValueError | TOMLDecodeError`.
- No sets, and map keys must be `string`.
- `int` is 63-bit, so the port uses `bigint`.
- No namespace alias/import.
- No `__file__`.
- No warnings module.
- Tests can't be generated dynamically, so there's no `subTest`.
- Stdlib:
  - no `index_of(sub, start)`
  - no anchored `regex.match(s, pos)` or pattern accessor
  - `Int.parse`/`Float.parse` take only decimal and reject `_`
  - `float.to_string` differs from Python's `repr`
  - no `microsecond()` on `PlainTime` (the port reads the private `_nanoseconds`, since BAML has no field visibility)
  - `PlainDate` accepts year 0
  - `assert.is_true` takes no message
  - no `tempfile`

Full list: `PORTING_NOTES.md` §1–§5.

### 4c. Stale docs [agent claim, plausible]

`baml_language/TEST_INSTRUCTIONS.md:373` describes a bug where "a `let`-bound local inside a `test` block does not compare equal to a literal". It no longer reproduces: the agent tested `test "x" { let r = "x"; assert.equal(r, "x") }`, which passes, and that test uses an explicit `assert` so it's valid.

## 5. Bugs in the original library

**None found.** The transcript and notes don't report any upstream defect. Every divergence from upstream is a BAML-side adaptation:
- The explicit year-0 check, because `PlainDate` accepts year 0 and Python's `datetime` doesn't.
- The dropped `lru_cache` on `cached_tz`.

## 6. Other comparisons

**Agent time and effort [measured from the transcript]:**
- One autonomous turn of **45 min 51 s** (19:12:57 to 19:58:47 UTC, 2026-09-26).
- 284 model calls (Opus 5.5), 137 Bash and 6 Write tool calls, no subagents.
- About 280k output tokens and 54.6M cache-read tokens.

**Timeline:**

| Time (UTC) | Phase |
|---|---|
| ~19:13–19:19 | Building `baml-cli` (debug), reading docs meanwhile |
| 19:19–19:22 | Language probing |
| 19:22–19:30 | Writing the parser (~1,700 lines in one commit, `86cd9a6`), compiled at 19:29:55 |
| 19:30–19:37 | Tests; 16/16 at 19:37:10 |
| 19:37–19:56 | Benchmark, profiling, perf workarounds, repros (release build ran ~10 min in the background) |
| 19:56–19:58 | Writing up |

**Things that went surprisingly well:**
- The parser passed all 744 data cases on its first successful compile.
- Recursive union aliases, typed `match`, `catch` with typed arms, and structural `==` on nested maps and arrays all worked.
- `baml.deep_copy`, `baml.time`, `baml.regex` (including `(?P<name>…)`), `baml.fs` and `baml.json` worked as documented.
- `baml describe` answered stdlib questions without reading source.
- Typed errors propagating through `spawn`/`await` made the stack-depth workaround about 10 lines.

**Error handling.** Python's exception hierarchy flattens into independent classes. The upside is that `throws` is inferred and checked. The downside is that exact `throws` declarations are required on interface methods and inline function types but rejected when "unnecessary" on closures, and panics (stack overflow, assert) bypass `catch_all`.

**Type-system impact.** Python's `dict[str, Any]` result becomes a closed recursive `Value` union. That is safer, but it causes invariance friction: a `_widen` copy is needed for `Tuple2<int, string>` to become `Tuple2<int, Value>`, and empty literals need annotations (`let arr: Value[] = []`).

**Dev loop.** The debug CLI is about 30× slower to `check` than release (8.9 s vs 0.27 s) and about 14× slower to run. `cargo build` defaults to debug, so casual timing and the edit loop both suffer. Building release costs about 10 minutes.

## 7. Open questions and caveats

- **Unverified agent claims:**
  - The ~170 µs failing type test for the 11-member `Value`.
  - The 74 ms → 14 ms history. The final ~13 ms is confirmed.
  - That debug and release give identical test results. I confirmed debug `baml test`: 16 passed in 8 s.
  - The CLI agent-skill gate.
- **Contradiction:** the debug-build figure in `PORTING_NOTES.md` (6.8 s vs 2.3 s).
- **Action item:** #4765 should probably be reopened, and the bare-boolean `test` false-pass (bug 1) filed. I didn't file either, because this task was read-only.
- **Nothing filed:** none of the other bugs in §4 have issues. The repros in `repros/` are ready to file as-is (except r04's E0151 noise).
- **Performance scope:** measured on one input file (4 KB) plus three synthetic 100-line files. No large-document or pathological-input benchmarks. The fuzzer isn't ported, so there's no fuzz parity.
- **Unported tests:** 3 upstream tests (plus the `assertWarns` half of one) have no BAML equivalent. The 15/18 ported-methods figure should be read with that in mind.
- **Scratchpad note:** my scratch directory was also used by concurrent agents (yaml and goldmark ports). One directory (`mut/`) got mixed contents, so I redid my mutation check in `tomli-hukkin-mutcheck/`. No source repos were modified.
