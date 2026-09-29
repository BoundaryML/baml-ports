# Post-mortem: porting BurntSushi/toml (Go) to BAML

Written 2026-09-27 by a follow-up agent. Everything below is either **measured** (by me, re-run on 2026-09-27) or **agent-claimed** (taken from the porting agent's `PORTING_NOTES.md` / transcript and not independently re-run); each claim is labeled.

Key locations:

- Original: `<local>/work-repos/toml-baml-port-src` (clone of `github.com/BurntSushi/toml` @ `d733fc5`; `<local>/work-repos/toml` is the same commit)
- Port: `<local>/work-repos/toml-baml` (9 commits, `06eef27`..`be6de94`, all on 2026-09-26 12:32–14:20 PDT), notes in `<local>/work-repos/toml-baml/PORTING_NOTES.md`
- BAML toolchain: `baml-cli` debug build of BoundaryML/baml `e215c3de2d` (recorded in `<local>/work-repos/toml-baml/.bin/BAML_COMMIT`). The porting worktree `<local>/baml-worktrees/port-burntsushi-toml` is clean and on that commit, so the compiler was not modified and no PR was opened. `canary` is still `e215c3de2d` (checked via `gh api` on 2026-09-27), so **nothing below has been fixed on canary since**.
- Transcripts: main session `<local>/transcripts/port-burntsushi-toml/d7293e96-66bd-4d4e-a5d8-dea701c02644.jsonl`, plus an earlier aborted attempt `<local>/transcripts/port-toml-rs/e1a3c08f-2446-490d-a3c1-04749bd61001.jsonl` (same Orca task `task_34767a883843`, run `run_3689c3c3cac4`). Agent scratchpad: `<local>/port-burntsushi-toml-scratch/` (test run logs `run1..5.txt`, `final.txt`, Go baseline `go_test.txt`).
- My benchmark and repro material: `<local>/report-scratch/{bench,repros,suite,suite_release.txt}`.

## 1. Summary

The whole library was ported: every Go source and test file has a BAML counterpart. That covers the lexer, parser, decoder, encoder, metadata, errors, struct-field resolution, `internal/toml-test` runner, `internal/tag`, the 3 `cmd/*` tools, `_example` and `ossfuzz`, plus all 8 `_test.go` files, including benchmarks and the fuzz test. The lexer, parser, encoder, metadata and error code are close statement-by-statement ports. The decoder keeps Go's `unify*` structure and error messages but works differently underneath, because BAML reflection cannot set fields or construct instances. It builds a JSON image of the result and materialises it with `baml.json.from_json<T>`.

Test results:

| Run | Pass | Fail | Total | Notes |
|---|---|---|---|---|
| Go upstream, `TZ=UTC go test -count=1 -v .` (agent's baseline, `go_test.txt`) | 1245 | 0 | 1245 | 0.35 s |
| BAML, debug `baml-cli`, loaded machine (agent-claimed, `final.txt`) | 1301 | 7 | 1308 | ~40 min wall; 2 `TestMaxDepth` cases hit the 300 s test timeout |
| **BAML, release `baml-cli` at the same commit (measured by me)** | **1303** | **5** | **1308** | **1 min 57 s wall**; the two timeouts pass (`TestMaxDepth#00` takes 17 s, `#02` takes 83 s) |

- **toml-test conformance** (TOML 1.1.0 corpus copied from `internal/toml-test/tests`): valid 218/218, encoder round-trip 218/218, invalid 492/492. These are the same 928 subtests Go runs. The error messages and positions that the Go tests assert also match.
- **The 5 real failures** are all BAML limitations, not port bugs:
  - `TestDecodeSignbit`: NaN/±Inf cannot pass through the JSON bridge into a class `float` field.
  - `TestMaxDepth#05–#08`: the VM has a hard `MAX_FRAMES = 256`. The parser recurses about 2–3 frames per nesting level, so Go's default `MaxDepth(128)` can never be reached.
- **Test counts are not 1:1 with Go.** BAML has one test per toml-test case, just like Go's subtests. It also adds a smoke test, 62 fuzz-corpus/mutation tests, and 30 benchmark-as-test entries.
- **Individual cases commented out as `UNPORTABLE`:** 8 in `decode_test.baml` and 2 in `encode_test.baml`. They need fixed-size arrays, non-string map keys, or decoding into non-pointer/nil-pointer destinations.
- **Other deviations:**
  - `baml run` always echoes the return value, so the CLI ports print a trailing `null`.
  - Local time zone offset is hard-coded to 0.
  - The toml-test runner is sequential with no per-test timeout.

Verdict: functionally complete and faithful. The weak points are performance (section 3) and the handful of language gaps above.

## 2. Lines of code

**Method (measured):** `tokei`, `scc` and `cloc` are not installed. I used a small Python counter (`scratchpad/loc.py`) that applies the same rule to both languages: a code line is any non-blank line that is not a comment-only line (`//…` or inside `/* … */`). Both Go and BAML use C-style comments, so the rule is symmetric. Data under `testdata/` is excluded.

| Category | Go files | Go code | BAML files | BAML code | Ratio |
|---|---|---|---|---|---|
| Library (lex, parse, decode, encode, meta, error, type_fields, type_toml, deprecated, doc, internal/tz) | 11 | 3,302 | 11 | 3,815 | 1.16× |
| Go-stdlib shims (`ns_go/`: utf8, strconv, fmt, time, sized ints/json.Number/bytes.Buffer) | — | 0 | 5 | 1,461 | new |
| Go-`reflect` adapter (`go_value.baml`) | — | 0 | 1 | 374 | new |
| Tests (`*_test.*`) | 8 | 3,818 | 9 | 4,267 | 1.12× |
| Tooling (cmd/*, _example, ossfuzz, internal/tag, internal/toml-test) | 11 | 1,358 | 11 | 1,435 | 1.06× |
| **Total** | 30 | **8,478** | 37 | **11,352** | **1.34×** |

Comment lines: Go 985, BAML 1,515. The port keeps Go's doc comments and adds rationale for each deviation. Raw `wc -l` totals are 10,513 Go vs 14,199 BAML.

Per-file code lines for the core pairs:

| Go | code | BAML | code | ratio |
|---|---|---|---|---|
| `lex.go` | 997 | `lex.baml` | 1,074 | 1.08 |
| `parse.go` | 663 | `parse.baml` | 704 | 1.06 |
| `decode.go` | 478 | `decode.baml` | 859 | **1.80** |
| `encode.go` | 615 | `encode.baml` | 556 | **0.90** |
| `meta.go` | 94 | `meta.baml` | 123 | 1.31 |
| `error.go` | 224 | `error.baml` | 269 | 1.20 |
| `type_fields.go` | 162 | `type_fields.baml` | 154 | 0.95 |
| `internal/toml-test/runner.go` | 544 | `ns_tomltest/runner.baml` | 611 | 1.12 |
| `decode_test.go` | 1,132 | `decode_test.baml` | 1,303 | 1.15 |
| `encode_test.go` | 1,271 | `encode_test.baml` | 1,350 | 1.06 |

Why the ratio is what it is:

- **Most growth is the ~1.8k lines of glue for things Go gets from its stdlib or the language.**
  - `ns_go/time.baml` (766 raw lines) reimplements `time.Time`/`ParseInLocation`/`Format`/`Duration`.
  - `strconv.baml` reimplements `ParseInt`/`ParseFloat` and `FormatFloat('g')`, because `float.to_string()` never uses exponent notation: `1e300` prints 301 digits (verified).
  - `utf8.baml` is a byte-level UTF-8 codec. The lexer runs on `int[]` bytes because BAML strings can't hold invalid UTF-8.
  - `fmt.baml` provides `%q`/`%v`/`%x`, because there's no printf.
  - `go_value.baml` is a Go-`reflect`-shaped view over BAML reflection.

  Without these, the library is only 1.16× Go.
- **`decode.go` → 1.80×.** No reflective setters or constructors, so each `unify*` returns a JSON image and threads the "current value" image through. Missing fields also need a `zero_json(type)` pass (`from_json` requires every non-optional field), and Unmarshaler/TextUnmarshaler need special paths.
- **Code-shrinking features:**
  - `encode.go` is 0.90×: no pointer/interface indirection to unwrap, `T?` for nil, and `match` over runtime types is terser than `reflect.Kind` switches.
  - The test ports stay close to 1:1 because BAML dynamic `testset { for … { test name { … } } }` maps directly onto Go's table-driven `t.Run`.
- **Code-inflating language gaps:** no methods outside the class body, no varargs or `defer`, no labelled `continue`. Narrowing gaps (`&&`, `never`) forced nested `if`s. Wrapper classes stand in for sized ints and methods on non-class types. Package vars had to become functions.

## 3. Performance

### Existing numbers (agent-claimed, not credible as a comparison)

The agent's `bench_test.baml` runs each benchmark with n=1 inside the test runner, using a **debug** `baml-cli` while 4 other port sessions were compiling (load average 12–16). Examples: `BenchmarkDecode/large-doc` 15.9 s/op, `BenchmarkEncode/inline-table` 50 s/op (`final.txt`). The agent never ran Go benchmarks; its only Go number is "whole suite 0.35 s vs. BAML suite ~40 min". I re-measured.

### My measurement

- **Hardware:** Apple M3 Max (14 cores), 96 GB, macOS (Darwin 25.6.0). This is a shared machine with other agents running: load average during runs ranged from ~4 to a spike of ~38. Expect ±2× noise on individual numbers; the ratios are orders of magnitude, so the noise doesn't change the conclusions.
- **Go:** go1.24.0. `go test -run '^$' -bench 'Benchmark(Decode|Encode|Example|Escapes|Key)' -benchmem -count 3` on a scratch copy of the Go repo. Raw output: `scratchpad/bench/go_bench.txt`.
- **BAML binary:** a **release** `baml-cli` at the same commit, `e215c3de2d` (fat LTO), copied from the clean `port-hukkin-tomli` worktree's `target/release`.
- **BAML harness:** a scratch copy of the port (`scratchpad/bench/toml-baml`) plus one driver file, `zz_bench_main.baml`. It calls the port's own `bench_*` functions with n=3 and runs via `baml-cli run -e 'bench_main(3)'`, 3 times. Numbers are from `baml.time.Instant` around the loop, so compile time is excluded. Raw output: `scratchpad/bench/baml_release_run{1,2,3}.txt`.
- Medians of 3:

| Benchmark | Go | BAML (release) | BAML/Go |
|---|---|---|---|
| Decode/large-doc (6.7 KB Cargo.toml) | 446 µs | 923 ms | ~2,100× |
| Decode/spec-1.1.0 | 818 µs | 883 ms | ~1,100× |
| Decode/table | 126 µs | 509 ms | ~4,000× |
| Decode/string | 442 µs | 359 ms | ~800× |
| Example/decode | 152 µs | 102 ms | ~670× |
| Example/encode | 70 µs | 5.8 ms | ~80× |
| Encode/spec-1.1.0 | 270 µs | 2,529 ms | ~9,400× |
| Encode/inline-table | 103 µs | 3,691 ms | ~36,000× |
| Encode/array | 48 µs | 2,100 ms | ~44,000× |
| **Geomean over all 29 Decode/Encode/Example benchmarks** | | | **~2,900×** |

**Calibration (measured).** How slow is the VM itself?

| Microbenchmark | Go | BAML release | BAML/Go |
|---|---|---|---|
| `fib(25)` (recursive calls) | 0.23 ms | 11.5–13 ms | ~50× |
| 1M-iteration integer `while` loop | 0.28 ms | 19–23 ms | ~70–80× |

A baseline interpreter penalty would therefore be about 50–100×. The port is 30–500× worse than that.

**Root cause of most of the decode gap (measured, new finding).** A `match` arm that tests a value against a container of a *recursive type alias*, such as `let t: map<string, Any>[] => …`, costs **~0.35–0.9 ms per evaluation when it doesn't match**, whatever the value's size. I broke `Decode/large-doc` down by phase with `scratchpad/bench/toml-baml/baml_src/zz_bench_phases.baml`:

| Phase | Time | Share |
|---|---|---|
| `bytes_of` | 4 µs | — |
| lex | 27 ms | ~3% |
| parse | 925 ms | ~97% |

Parse time is linear in the number of keys: 800 keys under `[t]` take 853 ms, versus 65 ms at top level. The cost comes from `Parser.set_value` in `parse.baml:513–522`. For every key inside a table, it matches the context table against `map<string, Any>[]` before `map<string, Any>`.

In a scratch copy, I swapped those two arms: nothing else changed and the semantics are identical. Results:

- parse of large-doc: 925 ms → 168 ms (5.5×)
- the 800-key table: 853 ms → 67 ms (13×)

A standalone repro with no toml code:

```baml
type J = string | int | J[] | map<string, J> | map<string, J>[];
function now_ns() -> bigint { baml.time.Instant.now().to_timestamp_nanoseconds() }
function bench(n: int) -> bigint {
    let s: J = "x";
    let t0 = now_ns(); let i = 0;
    while (i < n) { match (s) { let m: map<string, J>[] => {}, _ => {} } i += 1; }
    (now_ns() - t0) / (0n + n)   // ≈ 357,000 ns per iteration (release build)
}
// Same loop with `type K = string | int | K[] | map<string, K>` and arm `K[]`: ≈ 15,700 ns.
// Non-recursive `int | string` matched against `int`: ≈ 40 ns.
```

(`scratchpad/bench/repro/`.) The encoder's 10,000–40,000× gaps probably have the same cause or a related one: `go_value.baml` and `encode.baml` do a lot of `match`/`unreflect` narrowing against `Any` and runtime types. I have not profiled that, so treat it as a hypothesis.

### Compile time / dev loop (measured, same machine, `baml check` on the full 11k-LOC project)

| Build | Cold `check` | Cached `check` (`.baml/cache`) | `run -e '1'` |
|---|---|---|---|
| debug `baml-cli` | 14.0 s | 0.18 s | 1.7 s |
| release `baml-cli` | 1.6 s | 0.04 s | 0.36 s |

For comparison, Go takes ~1.7 s for a clean `go build .` and ~1.5 s for `go test -count=1 .` end to end. The agent used the debug build throughout. Its notes say every CLI invocation spent "~4–10 s compiling", which matches a loaded machine.

**Full test suite:** Go 0.35 s. BAML release 117 s, single-threaded (the runner sat at 100% CPU), and dominated by the three deep `TestMaxDepth` cases (17 s, 83 s and 92 s). BAML debug on the loaded machine took ~40 min (agent-claimed).

### Caveats

- BAML is an interpreted bytecode VM and Go is native, so a ~50–100× floor is expected.
- The port preserves Go's algorithms verbatim, including one the notes call "Go's O(n³) key bookkeeping". That is cheap in Go and very expensive in the VM.
- Nobody tried to optimise the BAML port. A single `match`-arm reorder buys 5× on decode, so the numbers above say more about VM pathologies than about the language's ceiling.

## 4. Bugs in the BAML language / compiler / runtime / stdlib

No GitHub or Linear issues were filed by the porting agent: its transcript has no `gh issue` or Linear calls, and its final message says "decide which bugs to file upstream" is the next step. I searched `BoundaryML/baml` issues for each item below. The only related hit is #4765, discussed under B5. Status "open / unfiled" means not fixed on canary (`e215c3de2d`) and no issue found. I re-ran every repro marked "verified" on 2026-09-27 with the release CLI (`scratchpad/repros/*`).

| # | Bug | Severity | Verified? | Workaround in port |
|---|---|---|---|---|
| B1 | Interface impl calling the same-named inherent method recurses into itself | **High**: silent wrong dispatch, infinite recursion | Yes (`r17_iface_self_recursion`) | Renamed the inherent method to `error_string` (commit `951540c`) |
| B2 | Pathologically slow type-pattern `match` on recursive-alias containers (0.35–0.9 ms per test) | **High** (perf): ~5–13× of the port's decode time | Yes, new finding by me (`bench/repro`) | None in port |
| B3 | VM hard call-depth limit `MAX_FRAMES = 256` (`bex_vm/src/vm.rs:118`) | Medium–High: ordinary recursive-descent parsers can't meet common depth limits | Yes (`r28_max_frames`: `depth(250)` ok, `depth(260)` → `StackOverflow`) | None; 4 `TestMaxDepth` cases fail |
| B4 | Bound method used without `()` silently becomes a value | Medium: type-checks when passed to `unknown`, fails at runtime | Yes (`r21_method_ref`) | Fixed the call site (`p.undecoded()`) |
| B5 | `\xNN`, `\uNNNN`, `\u{…}` string escapes are kept literally, with no diagnostic | Medium: silent wrong strings | Yes, but the agent's "file vs `-e` differ" detail is **wrong**; see below | Concatenation / `string.from_code_points` (commit `f264452`) |
| B6 | `&&` does not narrow its right-hand side | Medium (ergonomics; frequent, ~8 sites) | Yes (`r18_and_narrowing`, E0007) | Nested `if`s |
| B7 | Calling a `-> never` function doesn't narrow afterwards | Low–Medium | Yes (`r19_never_narrowing`) | `throw` directly, or `x ?? die()` |
| B8 | Matching a `string` against literal patterns narrows to a literal union that has no `string` methods | Low–Medium | Yes (`r20_literal_match`) | Restructured |
| B9 | Flow-narrowed literal type breaks comparison (`int` vs `2 \| 3`, E0004) | Low–Medium | Yes (`r23_literal_flow`) | Helper functions |
| B10 | Field narrowing: `if (self.err != null) { self.err.x() }` doesn't narrow | Low (known design limitation?) | Yes (`r24_field_narrowing`) | Local copy |
| B11 | A `testset` whose collector throws reports only `(failed to expand)`, with no message | Medium (DX): cost the agent ~15 min | Yes (`r35_testset`) | Re-ran the expression via `baml run -e` |
| B12 | `float.to_string()` never uses exponent notation (`1e300` → 301 digits) | Low | Yes (`r11_float_fmt`) | Hand-written `FormatFloat('g')` |

Details:

- **B1 (interface self-recursion).** Minimal repro (from `PORTING_NOTES.md` #17, verified):

  ```baml
  interface Err { function error(self) -> string throws never; }
  class E {
      msg: string,
      function error(self) -> string { self.msg }
      implements Err { function error(self) -> string throws never { self.error() } }
  }
  function main() -> string { let e: Err = E { msg: "hi" }; e.error() }  // StackOverflow
  ```

  This made all ~500 invalid-TOML tests stack-overflow until it was diagnosed (transcript 19:38–19:40 UTC). Either `self.error()` inside an `implements` block should resolve to the inherent method, or the compiler should reject or warn about the ambiguity.
- **B2 (slow recursive-alias match).** See section 3. The cost grows with the alias's structure: a 4-variant alias costs 15 µs, a 5-variant alias with `map<string,J>[]` costs 357 µs, and the port's 8-variant `Any` (which includes a class) costs ~890 µs. It looks like the runtime type check re-expands the recursive alias on every test. I found no existing issue. This is the single biggest performance finding and is worth filing.
- **B3 (MAX_FRAMES).** 256 frames is very low. CPython's default is 1000, and Go stacks grow dynamically. It was verified as a hard constant, not a configurable limit.
- **B4 (method reference as value).** Repro: `class P { x: int, function get(self) -> int { self.x } }`, then `take(p.get)` where `take(v: unknown)` compiles and silently passes a function. A lint for a bound-method reference flowing into `unknown` would have caught it.
- **B5 (string escapes). The agent's diagnosis is partly wrong.**
  - What `PORTING_NOTES.md` #22 claims: in a `.baml` file only `\n \t \r \0 \\ \"` are processed. The same literal passed to `baml run -e` does process `\uNNNN`.
  - What I found: the first half is correct, and I verified it with files generated through Python `chr(92)`. `"\x41A\u{41}"` yields the 16 raw code points in a file **and** via `run -e`. The "differs under `-e`" half is a **tool-harness artifact**: the agent's shell command text had `A` pre-decoded to a literal `A` before it reached `baml`. The transcript at 20:44:23 UTC shows the `-e` argument as `"…\x41A\u{41}…"`. I hit the same artifact myself: a heredoc containing `A` was written to disk as `A`.
  - Why it matters beyond this port: GitHub issue **#4765** ("String literals do not decode \xHH / \uHHHH escapes (kept raw)") was **closed on 2026-09-06 as "not reproducible"**. The withdrawer's probe `"aAb".length() == 3` would pass for exactly this reason if their tooling also rewrote `A` to `A`. The bug is real on `e215c3de2d`. **#4765 should be reopened.** For future agents, write repros containing backslash-u sequences via a script that builds the backslash explicitly.
- **B6–B10 (narrowing).** These were the most frequent day-to-day friction, per the agent. B6 and B7 look like genuine checker gaps. B10 may be intentional (fields are mutable), but it has no diagnostic hint.
- **B11 (testset expand errors).** The root cause here was `baml.random.Xoshiro256PlusPlus.new(seed=…)` panicking with "Rng seed must be at least 32 bytes" on a 31-byte seed. The runner swallows the panic message.
- **Toolchain pain (agent-claimed, not bugs per se):**
  - `baml` refuses to run without the "agent skill" unless `BAML_AGENT_SKILL_CHECK=off` is set.
  - `baml run` always prints the return value (a trailing `null`).
  - `bool` params are `--flag true|false`, and list params only work through `--json-args`.
  - The test runner buffers output until the end, `-i` is a prefix match, and there's no glob.
  - There's no stdin read-all API (worked around with `baml.fs.open("/dev/stdin")`), no `//go:embed`, no temp-file API, and no package dependencies between user packages, so `cmd/*` live inside the library package.
  - There's no benchmark or fuzz harness.
  - The debug CLI costs ~14 s per cold compile.
- **Not a BAML bug:** the agent reported that "the Write tool stripped trailing spaces" in expected-output literals (19:41 UTC). That is Claude Code tool behavior, not BAML.
- **Also not a BAML bug:** the agent's `.bin/b` wrapper pipes `baml-cli` through `grep -v`, so its exit status is grep's, not the CLI's. That's harmless for this run, but test failures can't be detected from the exit code.

## 5. Bugs in the original library

**None found.** The transcript has no mention of an upstream bug. Every Go test passed in the agent's baseline, and every BAML failure traces to a BAML limitation. The port does carry over the upstream's own known-issue TODOs verbatim, for example:

- `toml_test.go`: "we allow appending to tables, but shouldn't"
- `decode_test.go`: `MetaData.Keys()` "should include \"a\"", and the `TestMetaKeys` cases
- `lex.go`: several "never reached?" branches

These are pre-existing, acknowledged upstream behaviors, not discoveries of this migration.

## 6. Other comparisons

- **Reflection and struct decoding (the defining gap).** Go's `Decode(data, &v)` walks `reflect.Value` and sets fields in place. BAML can *read* everything, via:
  - `reflect.Type.of_value`
  - `reflect.AnyClass.list_fields()`
  - `type T = unreflect(t)` plus a narrowing `let`, which binds a runtime type to a local static type. The agent called this discovery the key unlock (transcript 19:17 UTC).

  But BAML has no setter and no constructor from a runtime type. The workaround — JSON image plus `from_json<T>` — works for everything except values with no JSON form (NaN/Inf, interface-typed fields). The encoder, which only reads, ported naturally.
- **Go-only features emulated:**
  - struct tags → `@description("toml:\"name,omitempty\"")` parsed by a port of `StructTag.Get`, because custom attributes are rejected and `reflect.Meta.other` is only set for runtime-built classes
  - embedded fields → a `go:"embed"` pseudo-tag, with Go's dominance rules and hand-forwarded promoted methods
  - pointers → `T?`
  - `int8…uint64` / `float32` → wrapper classes, since `int` is 63-bit (`9223372036854775807` is a compile error) and there's no float32
  - `panic`/`recover` → thrown values, since BAML panics are uncatchable
  - package vars → zero-arg functions, so the `cachedTypeFields` cache was dropped
- **Error handling.** Go's `(T, error)` returns became `throws`. BAML's checked `throws` clauses are asymmetric: function types and interface methods *must* declare them, while implementations *must not* over-declare. Turning one helper into a thrower rippled E0096 errors up the call graph. On the plus side, `TomlError` as an interface with a default `usage()` mapped Go's `error` plus optional `Usage()` cleanly.
- **Strings vs bytes.** Go strings are bytes and BAML strings are Unicode, so the lexer works on `int[]` and needs a hand-written UTF-8 decoder. Positions are byte offsets, and invalid-UTF-8 test inputs travel as bytes end to end.
- **What went surprisingly well:**
  - Dynamic testsets reproduced the ~930-case toml-test table one-to-one.
  - Runtime-typed containers keep `[]map[string]any` and `[]any` distinguishable, exactly as the Go parser's type switch needs.
  - `baml.io.Read`/`Write` fit `io.Reader`/`Writer`.
  - `spawn`/`await` handled `TestDecodeParallel`.
  - `baml describe` made the stdlib discoverable.
  - The parser worked end-to-end on its first smoke test (19:33 UTC).
  - The toml-test suite reached 950/952 about 6 minutes after the runner port was written. It took two runs: the first hit B1.
- **Agent time and effort (measured from transcripts):**

  | Session | Wall time | Output tokens | Activity |
  |---|---|---|---|
  | Attempt 1 (`e1a3c08f`, 2026-09-25 17:07–17:31 PDT) | ~24 min | ~148k | Cloned, built the CLI, drafted `lex`/`error`/`type_toml`/`utf8`/`fmt`. Stopped when the user rejected an edit, without sending `worker_done`. Left uncommitted files and `GAPS.scratch.md`, which attempt 2 reviewed and kept. |
  | Attempt 2 (`d7293e96`, 2026-09-26 12:13–14:21 PDT) | 2 h 08 min (`turn_duration` 7,679 s) | ~719k | Fully autonomous, no human input. 431 assistant messages: 185 Bash, 22 Write, 1 Edit, 1 Monitor. ~163M cache-read input tokens. Model `claude-opus-5-5`. |

  How attempt 2's wall time broke down:
  - The first ~6 min were waiting for the debug `cargo build` (contended by 4 other port sessions). The agent read all the Go source meanwhile.
  - All library source compiled by 12:32 PDT (~20 min in).
  - The toml-test suite was passing by 12:41.
  - **Roughly half of the session was spent waiting on full test runs** of 10–20 min each on the debug build under load. That included one 10-minute "hang" that turned out to be a half-written file breaking compilation.
- **Accuracy of the agent's own claims:** mostly accurate and carefully hedged. Two slips:
  - The final message says "committed in 13 commits"; the repo has **9**.
  - The B5 escape claim is partially wrong (a harness artifact).

  The "~1.7k lines of shims" claim matches my count: 1,461 code lines, or 1,739 raw.

## 7. Open questions / caveats

- **Benchmark noise.** The machine was shared, and the load spiked to ~38 during the first BAML benchmark run. Go numbers vary up to 2× across the 3 samples. Ratios are robust at the order-of-magnitude level only.
- **The encoder's slowness is not root-caused.** I only showed that the recursive-alias `match` explains most of the decode cost. A proper profile of `encode.baml`/`go_value.baml` is still needed.
- **Release vs debug.** The agent's 1301/1308 comes from the debug CLI; my 1303/1308 comes from a release CLI at the same commit, copied from another worktree. It builds the same source, but I did not rebuild it myself.
- **Unverified agent claims:** example output identical to `TZ=UTC go run .` (the agent diffed `go_ex.txt` against `baml_ex.txt`, and both files are 1,918 bytes); the CLI ports' behavior; and all "pain" items not listed in the table in section 4.
- **Nothing was filed upstream.** Candidates:
  - B1 (interface dispatch)
  - B2 (match perf)
  - B3 (frame limit)
  - B4 (method-ref lint)
  - B5 (reopen #4765)
  - B6/B7 (narrowing)
  - B11 (testset expand message)
- **The Orca task never reported completion.** Task `task_34767a883843` shows only "alive" messages in the inbox. Attempt 2 set the worktree card comment to "DONE: … 1301/1308 tests pass" but did not send `worker_done`: its prompt came directly rather than through Orca dispatch.
- **Nothing is still in progress.** The porting session is idle at its final summary (Orca terminal `term_7be42372…`).
