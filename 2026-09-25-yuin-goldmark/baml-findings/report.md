# Post-mortem: porting yuin/goldmark to BAML

Report written 2026-09-27. Covers Orca run `run_3689c3c3cac4`. Task `task_29da4a1fa769` was the first, abandoned attempt; the port was finished by a separate session in the `port-yuin-goldmark` worktree.

- **Original:** yuin/goldmark v2 at `7117ae6` ("chore: change update-readme workflow interval"). It is a pure-Go CommonMark parser plus GFM and other extensions. The same commit is at `<local>/work-repos/goldmark` and at `<local>/work-repos/goldmark-baml-port-src`; the agent used the second.
- **Port:** `<local>/work-repos/goldmark-baml`, 27 commits from `0e6f50e` to `ad164b1`, working tree clean. Branches `ext-table`, `ext-footnote`, `ext-deflist-strike-tasklist` and `ext-linkify-typographer` are left over from the sub-agents and are already merged into `main`.
- **Toolchain:** `baml-cli` 0.20.1 (`fasttest` profile), built at the start of the session from `<local>/baml-worktrees/port-yuin-goldmark`. That worktree is on `sxlijin/port-yuin-goldmark` at `e215c3de2d`, with no local changes. `e215c3de2d` is also the current `origin/canary` (checked with `git ls-remote` today). **So nothing below has been fixed on canary since the port.** The compiler and runtime were not modified.
- **Agent sessions:**
  - The first attempt (`<local>/transcripts/port-goldmark/a2a5e9cc-….jsonl`) ran for 20 minutes on 2026-09-25, 17:07–17:28 PDT. It produced only commit `0e6f50e` (util + generated tables) and then stopped. Its worktree no longer exists.
  - The main session (`<local>/transcripts/port-yuin-goldmark/7d7ec6ac-e5f6-4378-a025-9b5da9b96bce.jsonl`) was launched with a standalone "fully autonomous" prompt. It resumed from the first attempt's directory. It is finished: terminal `term_9534f2ee…` is idle at "Brewed for 1h 2m 21s · done 1:17 PM".

Labels used below:
- **[measured]**: I re-ran it for this report, in copies under my scratchpad.
- **[agent claim]**: taken from `PORTING_NOTES.md` or the transcript without re-checking.

## 1. Summary

- **What was ported.** Every Go source and test file is ported file-by-file: the core packages (`util`, `text`, `ast`, `parser`, `renderer`, `renderer/html`), all seven extensions (table, strikethrough, linkify, task list, definition list, footnote, typographer), `testutil`, `fuzz`, `_tools` and the goldmark part of `_benchmark`. That is 83 Go files → 80 `.baml` files (`PORTING_NOTES.md`, "File mapping and status").
  - The only file not ported is `_benchmark/cmark/cmark_benchmark.c`, which benchmarks the C cmark library, not goldmark.
  - The three `package.go` files are doc-only.
  - The `goldmark_v1_attribute` build-tag variant is compiled next to the default one, with `_v1` suffixes.
- **Test functions.** Go has 56 `Test*`/`Fuzz*`/`Benchmark*` functions; the port has 56 BAML `test` blocks, one per Go function.
- **Test pass rate [measured].** `bin/b test` in a scratch copy: **51 passed, 5 failed, 56 total**, 39 s wall time.
  - 4 failures are goldmark's wall-clock performance tests (the "must finish in < 5 s" tests).
  - The fifth failure, `TestDoc`, is an artifact of my copy: it shells out to `go run` against `../goldmark-baml-port-src`. It passes (3.9 s) after I symlink that path.
  - So there are 51 functional passes out of 51, plus 5 perf tests that sit near or over the budget. The agent's own run gave the same 51/5 split.
  - Log: `…/scratchpad/goldmark-report/baml_test_full.txt`.
- **CommonMark spec [measured]:** `spec_report` prints `passed=652 failed=0`, the full CommonMark 0.31.2 example set that goldmark ships in `testdata/spec.json`.
- **Extension and option case files [agent claim, consistent with the passing tests]:**

  | Case file | Passed |
  |---|---|
  | extra | 74/74 |
  | auto-heading-id | 8/8 |
  | parse-delimiter-simple | 133/133 |
  | table | 14/14 |
  | footnote | 5/5 |
  | definition list | 6/6 |
  | linkify | 21/21 |
  | strikethrough | 5/5 |
  | task list | 4/4 |
  | typographer | 19/19 |
  | CJK | 23/23 |

  Each ported test asserts that its failure list is empty, and those tests pass. A sub-agent also broke the strikethrough output on purpose and confirmed its test failed (negative control, in the `agent-a2e4cfe7…` transcript).
- **Output matches Go [measured].** The agent built a differential harness, `tools/difffuzz` (Go) plus `ns_dev.fuzz_dump_file` (BAML). It renders randomly mutated spec and extension inputs, with every extension on, through both implementations and compares the bytes.
  - The agent reports 29,500 documents byte-identical [agent claim].
  - I re-ran it with a fresh seed (`987654`, 3,000 documents): `total=3000 mismatches=0`.
  - Negative control: after I corrupted 2 of the BAML outputs, the harness reported `mismatches=2`.
  - Caveat: the fuzz inputs are short, averaging 36 bytes.
  - The agent also reports that the 200 KB benchmark document and goldmark's README render byte-identical [agent claim].
- **Bottom line.** Behaviourally this is a complete, exact port. It is about 250× slower than Go (section 3).

## 2. Lines of code

**Method [measured].** `tokei`, `scc` and `cloc` are not installed, so I used a small Python counter. It applies the same rules to both languages: a line is blank, a comment (`//` or `///` lines, `/* … */` blocks) or code. Only code lines are compared. Go is measured at `<local>/work-repos/goldmark-baml-port-src`; BAML at `<local>/work-repos/goldmark-baml/baml_src`. The per-file script is in `…/scratchpad/goldmark-report/loc_per_file.py`.

| Category | Go files | Go code lines | BAML files | BAML code lines | Ratio | Go bytes → BAML bytes |
|---|---|---|---|---|---|---|
| Library (non-test, non-generated) | 52 | 11,788 | 47 | 12,949 | **1.10×** | 397 KB → 573 KB (1.44×) |
| Generated tables (entities, case folding, Unicode categories) | 2 | 11 | 3 | 5,662 | n/a | 97 KB → 227 KB |
| Tests + `testutil` + `fuzz` | 23 | 2,599 | 23 | 2,519 | **0.97×** | 74 KB → 106 KB |
| Tooling (`_tools`, `_benchmark`) | 6 | 457 | 6 | 497 | 1.09× | 11 KB → 20 KB |
| Port-only dev helpers (`ns_dev`) | n/a | n/a | 1 | 199 | n/a | n/a |
| Port-only Go helpers (`tools/gen`, `tools/difffuzz`) | n/a | n/a | 2 (Go) | 287 | n/a | n/a |
| Excluded: `cmark_benchmark.c` | 1 | 76 | n/a | n/a | n/a | n/a |

Selected per-file code-line ratios (BAML ÷ Go):

| File | Ratio | File | Ratio |
|---|---|---|---|
| `parser/parser.go` (1,070 → 1,354) | 1.27 | `renderer/html/html.go` (848 → 852) | 1.00 |
| `util/util.go` | 1.18 | `ast/ast.go` | 1.00 |
| `text/reader.go` | 1.21 | `extension/table.go` | 1.22 |
| `parser/auto_link.go` | 1.60 | `extension/linkify.go` | 1.29 |
| `text/value.go` | 0.85 | `text/decoder.go` | 0.64 |
| `util/util_cjk.go` | 0.84 | `extra_test.go` | 0.64 |

**Why the ratios come out this way.**
- **The core logic is nearly 1:1.** BAML's syntax (classes with methods, interfaces, closures, `match`) maps closely onto Go, and the agent kept the Go structure deliberately.
- **What adds lines:**
  - Go multi-value returns become result classes or `T?`.
  - No `&&`/`||` narrowing (N1 below) means nested `if`s or helper `let`s.
  - Fields must be copied into locals before narrowing (N2).
  - Go's `nil`-vs-empty slices become `uint8array?` plus `?? root.util.new_bytes()`, which appears 48 times.
  - There are no char literals, so byte values carry trailing comments like `// '|'` (78 times).
  - The `[256]uint8` lookup tables in `auto_link.go` are regenerated as range checks, hence 1.60×.
  - 200 `throws never` annotations and 60 `catch_all` blocks come from interface-method throw rules and regex constructors that can throw.
  - Go `goto retry` becomes loops.
- **What removes lines:**
  - Go `if err != nil` plumbing disappears. Render and walk errors are dropped because all writers are in-memory.
  - Go's `io.Writer` and `bufio` handling collapses to one `BufWriter`.
  - `Stringer` boilerplate becomes small functions.
  - Test tables are written more compactly (`extra_test` 0.64×, `table_test` 0.76×).
- **Bytes grow more than lines (1.44× vs 1.10×).** Every cross-namespace reference must be fully qualified (`root.util.is_space`, `root.ast.Node`, `root.parser.Context`). The conventions forbid short aliases because a bare `ast` is ambiguous inside `ns_extension`. snake_case names are also a little longer.
- **Generated tables explode.** Go keeps the HTML5 entity table as packed strings on a few very long lines (`util/html5entities.gen.go`: 11 code lines, 68 KB). BAML has no package-level constants (M3), so `tools/gen` emits `match` decision trees (2,500 lines).
  - `unicode_tables.gen.baml` (940 lines) reimplements Go stdlib `unicode.IsPunct`/`IsSymbol` and friends, which the Go code gets for free.
  - `utf8.baml` (154 lines) does the same for `unicode/utf8`.

## 3. Performance

**Benchmark [measured].** This is goldmark's own `_benchmark/cmark/goldmark_benchmark.go` and its 1:1 BAML port, `ns_benchmark/goldmark_benchmark.baml`.
- Both parse and render the 202,662-byte `_benchmark/cmark/_data.md` with `html.WithXHTML(), html.WithUnsafe()`, reuse a single parser, renderer and buffer, and time each iteration.
- Go was compiled with `go build`, Go 1.24.0.
- BAML was run via `bin/b run --function goldmark_benchmark` on the `fasttest` build, which is the bytecode VM.
- Go ran 200 iterations and BAML ran 10, alternating over 3 rounds (`…/scratchpad/goldmark-report/bench.sh`, output in `bench_run1.txt`).
- Hardware: Apple M3 Max, 14 cores, 96 GB RAM, macOS (Darwin 25.6.0).
- Load average was 15–17 during the run: other port agents and `rustc` builds were running.

| Round | Go avg / conversion | BAML avg / conversion | Ratio |
|---|---|---|---|
| 1 | 1.93 ms | 480 ms | 248× |
| 2 | 1.88 ms | 477 ms | 253× |
| 3 | 2.17 ms | 480 ms | 221× |

This matches the agent's claim of 0.47 s vs 0.0019 s, about 250×.
- An earlier run of mine under heavier load (load average 23–43) gave Go 4.8–5.8 ms and BAML 0.94–1.06 s, still about 200×. Treat about 250× as the steady-state figure and ±15% as noise.
- Throughput: Go about 100 MB/s, BAML about 0.42 MB/s.

**goldmark's pathological-input perf tests [measured]** (n = 50,000 repetitions; the budget is 5 s × `GOLDMARK_TEST_TIMEOUT_MULTIPLIER`):

| Test | Go | BAML (alone) | BAML (full parallel `bin/b test`, high load) | Agent's run (alone) |
|---|---|---|---|---|
| DeepNestedLabel | 0.01 s | 5.66 s ✗ | 7.8 s ✗ | 4.9 s ✓ |
| ManyProcessingInstruction | 0.70 s | 2.96 s ✓ | 4.4 s ✓ | 2.7 s ✓ |
| ManyCDATA | 0.21 s | 24.7 s ✗ | 38.6 s ✗ | 22.1 s ✗ |
| ManyDecl | 0.09 s | 6.19 s ✗ | 17.0 s ✗ | 6.1 s ✗ |
| ManyComment | 3.31 s | 8.27 s ✗ | 22.6 s ✗ | 8.0 s ✗ |

- The label test is borderline and flaky around the 5 s line.
- The ratio is much worse on some inputs (CDATA about 120×, labels about 500×) than on others (comments 2.5×). The agent attributes this to goldmark's `PeekLine` returning an O(1) sub-slice: in BAML every inline-parser attempt copies the rest of the line (missing feature M2), which makes some scans quadratic.
- The agent reports that `GOLDMARK_TEST_TIMEOUT_MULTIPLIER=5` makes all but CDATA pass [agent claim; the agent re-verified it in-session].

**Compile time and dev loop [measured].**
- `bin/b check` on the whole 26k-line project: 0.84 s cold, 0.09 s warm (cached).
- A 1-iteration `bin/b run` takes 0.71 s end to end, of which 0.52 s is the conversion. So compile and startup overhead is under 0.2 s.
- Full test suite: BAML about 35–39 s, dominated by the perf tests; about 4 s with `-x "root::*Performance"` [agent claim]. Go's `go test -count=1 ./...` takes 12.7 s including compilation.

**Caveats.**
- BAML runs on a bytecode VM and Go compiles to native code. The agent measured about 100 ns per simple VM loop iteration, and 3–10 GB/s for native stdlib calls such as `slice`, `index_of` and `from_utf8` [agent claim, `PORTING_NOTES.md` P1].
- Two performance-only deviations are already in the port, and both give identical results:
  - `util.bytes_index` delegates to native `string.index_of`/`uint8array.index_of`.
  - `BlockReader.peek_line` caches by position (commit `687709d`).
  So the ratio is not a pure transliteration ratio.
- No profiler exists (M11), so hotspot attribution is the agent's reasoning, not profiled.

## 4. Bugs in the BAML language, compiler, runtime and stdlib found during the migration

I re-ran every repro below against the port's `baml-cli` (0.20.1 @ `e215c3de2d` = current canary). They are in `…/scratchpad/goldmark-report/repro1/` and `repro2/`.
- **No issue or PR was filed by the porting agent.** Its transcript has no `gh issue`/`gh pr`/Linear commands, and the final message says "there's no PR."
- `gh search` on BoundaryML/baml found no existing issue for B1–B3 or B5–B7.

### 4a. Bugs

**B1. Runtime crash: after `is`-narrowing to an interface, a method call dispatches through the wrong interface.** Severity: high. It is a VM internal error on code that type-checks, and Go-style `if x, ok := n.(I)` ports naturally hit it.
```baml
interface Node { function kind(self) -> string throws never }
interface BlockNode requires Node { function has_blank(self) -> bool throws never }
class P { implements Node { function kind(self) -> string throws never { "P" } }
          implements BlockNode { function has_blank(self) -> bool throws never { true } } }
function f(n: Node) -> bool { if (n is BlockNode) { return n.has_blank(); } false }
function main() -> bool { f(P {}) }
```
- [measured] Fails with `VM internal error: interface 'user.Node' declares no method 'has_blank'`.
- Workaround used: `match (n) { let b: BlockNode => b.has_blank(), _ => false }`. Conventions pitfall "Do NOT use `if (x is SomeInterface)`".
- Evidence: `PORTING_NOTES.md` B1.

**B2. Runtime crash: reading or writing an interface-declared field through an interface-typed value.** Severity: high (VM internal error).
```baml
interface Node { base: BaseNode }
class BaseNode { parent: Node? }
class H { base: BaseNode, implements Node {} }
function main() -> int { let h = H { base: BaseNode { parent: null } }; let p = H { base: BaseNode { parent: null } };
  let n: Node = h; n.base.parent = p; 1 }
```
- [measured] Fails with `VM internal error: type error: expected map, got instance`.
- Workaround used: expose the field via a method (`function base(self) -> BaseNode`) on every node class.
- Evidence: `PORTING_NOTES.md` B2; `baml_src/ns_ast/ast.baml`.

**B3. Compiler panic: assigning a bound method directly into a field.** Severity: high (compiler crash); an easy workaround exists.
```baml
class Holder { f: ((x: int) -> int throws never)?, }
class G { function twice(self, x: int) -> int { x * 2 } }
function main() -> int { let g = G {}; let h = Holder { f: null }; h.f = g.twice; 0 }
```
- [measured] `thread panicked at crates/baml_compiler2_emit/src/pull_semantics.rs:482:13: internal error: entered unreachable code: MakeBoundMethod must be handled in emit_rvalue_pull`.
- Workaround: `let t = g.twice; h.f = t;`. goldmark's renderer registers bound methods everywhere, so this pattern appears throughout the renderer code.
- Evidence: `PORTING_NOTES.md` B3; the transcript shows the panic when it was first hit.

**B4. Silent wrong result: `\x..` and `\u....` / `\u{....}` escapes in string literals are kept verbatim (backslash included), with no diagnostic.** Severity: high. The strings are silently wrong, and this produced wrong HTML (NUL → U+FFFD handling) until goldmark's tests caught it.
- [measured], with the file written byte-exactly from Python: in a function body, `"�"` has length 6, `"a\x1bb"` has length 6 and `"aAb"` has length 8. They should be 1, 3 and 3. Only `\n \t \r \0 \\ \"` decode.
- **Related tracker item:** BoundaryML/baml#4765 ("String literals do not decode \xHH / \uHHHH escapes") was **closed on 2026-09-06 as "does not reproduce"**. The withdrawal used bare boolean expressions in a `test` block (`"aAb".length() == 3`).
  - I confirmed today that **a bare expression in a `test` block is not an assertion**: `test "x" { "abc".length() == 99 }` PASSES, while `assert.equal("abc".length(), 99)` fails.
  - So #4765 was closed on a false negative, and the bug still exists on canary. It is worth reopening #4765 with the `assert.equal` repro. The silently-passing bare expression may deserve its own lint too.
- Extra hazard [measured]: some tool layers decode `�` before the file hits disk. Both the porting agent (conventions pitfall 7) and I (my first repro attempt, when the heredoc was written through the Bash tool) got a literal U+FFFD in the file instead of the escape.
- Workaround used: put the literal character in the source, written from a script.
- Evidence: `PORTING_NOTES.md` B4; commit `7387085` ("U+FFFD literals").

**B5. Spurious compile error: a statement-initial `[` or unary `-` right after `}` continues the previous expression.** Severity: medium. The error messages are confusing (`E0010`, and `E0004 void - int`).
```baml
function a(x: int?) -> int[] { if (x != null) { return [x]; } [] }   // E0010 unexpected token
function b(x: int?) -> int  { if (x != null) { return x; } -1 }      // E0004 `-` on `void` and `1`
```
- [measured] Both reproduce.
- Workaround: `let none: int[] = []; none` / `return -1;`.
- Evidence: `PORTING_NOTES.md` B5. Found independently by the main agent (`[`) and the deflist sub-agent (`-`).

**B6. Spurious compile error: `match` on an interface-typed value against an unrelated interface is rejected.** Severity: medium. It blocks the idiomatic port of Go's `ip.(CloseBlocker)`.
```baml
function f(ip: InlineParser) -> int { match (ip) { let cb: CloseBlocker => cb.close_block(), _ => 0 } }
```
- [measured] `E0001 mismatched types: expected InlineParser, found CloseBlocker`, even though a class implementing both interfaces exists.
- Workaround: widen first, `let u: unknown = ip; match (u) { … }`.
- Evidence: `PORTING_NOTES.md` B6.

**B7. Spurious compile error: `let k = E.A;` infers the singleton literal type `E.A`.** Severity: low.
- [measured] `k = E.B` then fails with `E0001 expected E.A, found E.B`.
- Workaround: annotate the type, `let k: E = E.A;`.
- Evidence: `PORTING_NOTES.md` B7.

**Narrowing gaps (spurious compile errors).** Severity: medium, because they are extremely frequent in Go-style code.
- **N1.** Narrowing does not flow into the right operand of `&&`/`||`. [measured] `x != null && x.length() > 0` fails with `E0007: type string | null has no member length`.
- **N2.** Fields are not narrowed. [measured] `if (c.s != null) { return c.s.length(); }` fails with the same `E0007`.
- **N3.** A loop-carried optional local loses narrowing after reassignment [agent claim].
- Workarounds: nested `if`s, copies into locals, non-optional locals.
- Evidence: `PORTING_NOTES.md` N1–N3, conventions pitfalls 1–3.

**Toolchain noise (pain point, P4).** [measured] Every `check`/`run`/`test` prints about 45 stdlib `E0146` "unreachable code" warnings plus `warning: code is unformatted`. The agent had to `grep -v E0146` on every command (133 `bin/b` invocations in the main transcript). The E0146 diagnostic was added by `f603110e74` ("feat: diagnose constant conditions and unreachable code", #4995) one day before the port, and it fires on the stdlib itself.

**Already known, not new:** `is` or reflection on a boxed **test-block local** misreports. This is documented in the BAML repo's own converted `is_operator` tests, and the agent copied it into its conventions as a "known VM bug". The port worked around it by putting all logic in helper functions.

### 4b. Missing features that forced workarounds

Each item was confirmed where marked [measured]; the rest are [agent claim] from `PORTING_NOTES.md` M1–M13.

- **M1. No reference identity.** `==` on class instances is deep structural equality. [measured] Two distinct `N { v: 1 }` compare `==` as true. goldmark compares node pointers everywhere.
  - Workaround: a scratch `mark` field on every node, and `same_node(a, b)` in `ns_ast/ast.baml:79`. It writes a sentinel into `a` and checks whether `b` sees it (19 call sites).
  - `array.includes`/`index_of` are also structural.
- **M2. No slices or views of `uint8array` or strings.** `slice` copies. This is the root cause of the perf-test failures. Also:
  - No `from` offset on `uint8array.index_of`.
  - No multi-byte `index_of`.
  - [measured] `for (let b in bytes)` fails with `E0006 cannot iterate over type uint8array`.
- **M3. No package-level `const`/`var`.** Tables, singletons and counters become zero-arg functions (re-evaluated on every call) or generated `match` trees. This is why the generated code is large.
- **M4. No char/byte literals.**
- **M5. Map keys must be `string`.** [measured] `map<int, string>` fails with `E0067`. Map-literal keys must also be literals (`{ kind_table(): r }` doesn't parse).
- **M6. Panics can't be caught.** goldmark's `recover()`-based per-case isolation in `testutil` is impossible, so one panic aborts a whole case file.
- **M7. No raw strings.** [measured] `#"…"#` fails with `E0098 removed language feature`. Backtick strings process escapes and dedent or trim, so Go regexps and expected-HTML literals need careful escaping.
- **M8. No build tags or conditional compilation.**
- **M9. Regex gaps:**
  - Strings only (no byte API), with code-point offsets.
  - A constant pattern still `throws`.
  - `\d \w \s` are Unicode-aware where Go's RE2 is ASCII.
  - `&& -- ~~` are set operators inside character classes.
  - `[[]` is rejected.
- **M10.** No `int.to_float()`.
- **M11.** Missing stdlib pieces: temp directories, `archive/zip` (the agent wrote a stored-entry ZIP writer plus CRC-32), a profiler, and `unicode` category predicates.
- **M12.** No variadics, and defaulted parameters must be passed by name (`E0005`).
- **M13.** `baml.json` decoding matches field names exactly (Go's is case-insensitive), and `@alias` is ignored there.
- **P2.** Every interface method must declare `throws`. Inferred throw sets propagate, so a `BufWriter` implementation that calls `String.from_code_points` stops conforming to `throws never`.
- **P3.** Reserved words used as identifiers produce a cascade of unrelated "unexpected token" errors instead of one reserved-word diagnostic.
- **P6.** Go names that differ only in export case (`NewX`/`newX`, `footnotes`/`Footnotes`) collide in snake_case.

## 5. Bugs in the original library (goldmark) found during the migration

**G1. The typographer's `CloseBlock` has the wrong signature, so it never runs and the unclosed-quote counter leaks across blocks.** Severity: low to medium (wrong typographic output across paragraph boundaries).
- `extension/typographer.go:280` declares `func (s *typographerParser) CloseBlock(_ gast.Node, pc parser.Context)`.
- The `parser.CloseBlocker` interface needs `CloseBlock(parent ast.Node, block text.Reader, pc Context)` (`parser/parser.go:668`).
- The `ip.(CloseBlocker)` assertion at `parser.go:851` therefore never matches, and `getUnclosedCounter(pc).Reset()` is never called.
- The porting agent noticed this and kept it as an uncalled plain method, "upstream bug: wrong signature" (`PORTING_NOTES.md`, typographer row). It did not test for observable impact.
- **I confirmed the impact [measured]** by patching the signature in a scratch copy (`…/scratchpad/gm-go-patched`) and running `…/scratchpad/typo/main.go`:
  - Input `He said "hello\n\nx" y`, stock goldmark: `<p>He said “hello</p>\n<p>x” y</p>`. The unmatched `"` from paragraph 1 lets paragraph 2's `"` close it.
  - With the fix: `<p>x&quot; y</p>`, which is what the `Reset` was written to produce.
- The same bug is on goldmark's v1 `master` branch (`typographer.go:326`, checked via the GitHub API). `gh search` found no upstream issue or PR. Not reported upstream.

**G2 (nit). Copy-pasted failure messages in the perf tests.** `TestManyCDATAPerformance`, `TestManyDeclPerformance` and `TestManyCommentPerformance` in `extra_test.go` all report "Parsing processing instructions took too long". The BAML port faithfully reproduces this [measured, visible in the failure output].

**Load-bearing slice aliasing (port hazard; possibly unintended upstream behavior).**
- goldmark's block loop reads `openedBlocks[lastIndex]` through a stale slice header whose backing array was overwritten by a later `append`. This is how it detects that a paragraph was replaced.
- The port failed CommonMark example 216 until it consulted the current list instead (`ns_parser/parser.baml:1487`).
- The table extension's paragraph-splitting similarly depends on `node.Source()` aliasing `lines`. The port reproduces the resulting "odd Go output" explicitly for inputs with two delimiter rows in one paragraph (`ns_extension/table.baml:318`, table sub-agent report).
- These are not demonstrated bugs, but they are fragile, undocumented dependencies on Go slice semantics [agent claim, not independently analysed].

**Robustness edges the port hardened [agent claim]:**
- A nil `IsInTightBlockFunc` panics in Go's task-list renderer.
- A custom linkify email regexp that matches without `@` panics in Go.
- The footnote block parser indexes `line[pos]` without a bounds check.

These are API misuse or unreachable paths rather than confirmed bugs.

## 6. Other comparisons

- **Agent effort [measured from transcripts]:**
  - Main session: one autonomous turn of 62 min (`turn_duration` 3,741,302 ms), 593 assistant messages, about 861k output tokens, and 264 Bash / 14 Write / 4 Agent tool calls, all on `claude-opus-5-5`.
  - Four background sub-agents ported the extension groups in separate git worktrees: table; footnote; definition list + strikethrough + task list; linkify + typographer. Each took about 5 minutes and 27–31k output tokens.
  - The first, abandoned attempt added 20 min and about 129k output tokens.
  - Total: about 1.4 hours of agent wall time for a 12k-line library and all of its tests.
  - Commit timestamps are compressed (most of the 27 commits land between 12:21 and 13:17 PDT), consistent with that.
- **Process that worked.**
  - The coordinator ported the core first (`util` → `text` → `ast` → `parser` → `renderer`), reaching 652/652 spec examples at `0ba923d`.
  - It then wrote `PORTING_CONVENTIONS.md`, a list of mapping rules plus known pitfalls, and fanned out the extensions. The sub-agents each reported only 1–5 new issues, which suggests the conventions document saved a lot of rediscovery.
  - The differential fuzzer against real Go goldmark gives much stronger evidence than the unit tests alone.
- **The earlier attempt's tables were wrong.** It had three latent table bugs (`IsSpace` must exclude `\v \f`, URL table `0x7F`, UTF-8 length of `0xC0/0xC1`), which goldmark's tests caught (commit `7387085`). This is a reminder that "compiles" is far from "correct" when tables are hand-transcribed.
- **Modelling Go in BAML:**
  - Struct embedding (`BaseNode`/`BaseBlock`/`BaseInline`) maps onto a `b: BaseNode` field plus interface default methods and `requires` super-interfaces.
  - Generic `Renderer[W]`/`Option[C]` maps onto bounded generics (`Helper<C extends FormatConfig>`), and Go reflection becomes an interface.
  - Go's `any` becomes `unknown` + `match`.
  - The agent listed interfaces with default methods, generics with bounds, closures capturing mutable locals, `match` on class/interface/union types, optional chaining, and the fast native string and byte primitives as things that "worked well".
- **Error handling.** Go's `(T, error)` returns for rendering and walking were dropped entirely, because every writer is an in-memory buffer. BAML's checked `throws` forced 200 `throws never` annotations and 60 `catch_all` blocks. This is more ceremony than Go for code that cannot fail, but no errors were silently lost.
- **Byte-oriented code is the weak spot.** No slices or views, no char literals, no `for … in` over `uint8array`, and a regex engine that works only on strings. Together these make up most of the friction and all of the performance gap.
- **Dev loop.** Type-checking the 26k-line project takes under 1 s, and test selectors (`-i`, `-x`) with per-test timing were pleasant. The noisy warning stream and debug-format `baml run` output (not JSON) forced data exchange with the Go harness to go through files.
- **Compared with the sibling tomli port** ([`hukkin-tomli` report](../../2026-09-25-hukkin-tomli/baml-findings/report.md), same run and toolchain): goldmark is about 17× larger and pointer- and byte-heavy, and it surfaced more serious runtime bugs (B1, B2, B3 are VM or compiler crashes). The recurring themes are the same: narrowing gaps, silent escape handling, and missing byte and identity primitives.

## 7. Open questions and caveats

- **Performance numbers were taken on a shared, loaded machine** (load average 10–43, from concurrent port agents and `rustc`). The ratio held at about 220–255× across runs, but absolute numbers vary by ±2×. I did not measure memory. I also accidentally ran `go clean -cache` in my scratch Go copy, which clears the shared Go build cache; that affects only build speed, not any results.
- **Most of the extension sub-case counts and the 29,500-document fuzz figure are agent claims.** I independently verified the 652/652 spec result, the 51/56 test outcome, one 3,000-document differential fuzz run (0 mismatches, with a working negative control), and the benchmark ratio.
- **The fuzz inputs are small** (about 36 bytes average, mutations of spec and extension inputs), so large-document edge cases are covered only by the benchmark document and the README comparison.
- **`TestDoc` depends on a sibling Go checkout at `../goldmark-baml-port-src` and on `go run`,** so it is not self-contained.
- **None of the BAML bugs are filed.** Candidates to file: B1, B2, B3, B5, B6, B7, N1/N2, and reopening #4765 (B4) with the `assert.equal` repro. The bare-expression-in-`test`-block behaviour that caused #4765 to be closed wrongly may deserve its own issue or lint.
- **G1 is not reported upstream to yuin/goldmark.**
- **The claim that the port is "250× slower because of slice copying" is plausible but unprofiled.** No profiler exists for BAML. The agent's cached-`peek_line` optimisation (`687709d`) was its only targeted fix, and its effect was not separately quantified.
- **The perf tests are inherently flaky** near the 5 s budget (DeepNestedLabel passed for the agent at 4.9 s and failed for me at 5.7 s).
