# yuin/goldmark → BAML: every BAML bug and limitation the porting agent worked around

Written 2026-09-28. This is a companion to [report.md](report.md) (the post-mortem). That report was used as a checklist, but every item below was re-derived from the transcripts, the port's code and commits, and fresh repros.

## Scope and method

- **Sources swept:**
  - Main session `MAIN` = `<local>/transcripts/port-yuin-goldmark/7d7ec6ac-e5f6-4378-a025-9b5da9b96bce.jsonl`.
  - Its four sub-agents under `…/7d7ec6ac…/subagents/`: `SUB-TABLE` = `agent-add7a241e38b90ffd`, `SUB-FOOT` = `agent-a801f55051aa46ba0`, `SUB-DEFL` = `agent-a2e4cfe7e9a276950` (deflist/strikethrough/tasklist), `SUB-LINK` = `agent-a98bfc1df9a228fbc` (linkify/typographer).
  - The abandoned first attempt `FIRST` = `<local>/transcripts/port-goldmark/a2a5e9cc-ea46-4f07-a294-3f9a05a45792.jsonl`.
  - The only other transcripts that mention `work-repos/goldmark-baml` (`<local>/transcripts/coordinator/1c8504f4…`, `port-eemeli-yaml/9e8d82d5…`, `port-burntsushi-toml/d7293e96…`) only contain the dispatch prompt, so they add nothing.
  - The agent's probes in `<local>/port-yuin-goldmark-scratch/probe{,2..6}` and `tables.baml`.
  - The port `<local>/work-repos/goldmark-baml`: `PORTING_NOTES.md`, `PORTING_CONVENTIONS.md`, `git log -p`, and a grep of `baml_src` for workaround comments (250 hits).
- **Evidence format:** `MAIN L1170` is the line number in the jsonl file; timestamps are the transcript's UTC times (subtract 7 h for PDT).
- **Re-verification toolchain:** release `baml-cli` 0.20.1 at `<local>/baml-worktrees/port-hukkin-tomli/baml_language/target/release/baml-cli`. That worktree is clean at `e215c3de2d`, the same commit the port used, and still `origin/canary` per the post-mortem. No build was needed.
  - All repro projects are in `<local>/report-scratch/gm.k3dr/r/<name>/`.
  - Port-level checks ran in a `git archive` copy at `…/gm.k3dr/port/`.
- **Status labels:**
  - **VERIFIED**: reproduced today on the release CLI.
  - **NOT REPRODUCED**: my repro did not trigger it (agent error, or narrower than claimed).
  - **UNVERIFIED**: not re-run.
- **Issue search:** `gh issue list -R BoundaryML/baml --search … --state all`, with 60+ queries (error strings, feature names, codes). "none" means no matching issue was found.

## Summary table

Severity: **high** = crash, silent wrong result, or port fidelity loss; **med** = a frequent spurious error or a large ergonomic cost; **low** = occasional friction.

| # | Title | Cat | Sev | Verified? | Issue | Workaround used |
|---|---|---|---|---|---|---|
| 1 | `is`-narrowing to an interface, then a method call → VM internal error | b | high | VERIFIED | none | `match (n) { let b: BlockNode => … }` |
| 2 | Nested field write through an interface-declared field (`n.base.pos = 5`) → VM internal error | b | high | VERIFIED (reads work; only writes crash) | none (#4813 is a similar "field write fails, temp local works" VM bug) | Interface exposes `base()` method; write via local |
| 3 | Bound method assigned into a field or map slot → compiler panic `MakeBoundMethod must be handled in emit_rvalue_pull` | a | high | VERIFIED (field and `m[k] =`) | none | `let r: FnType = self.m; x.f = r;` (29 sites) |
| 4 | `\x..`, `\u....` and `\u{..}` escapes kept verbatim, no diagnostic | a | high | VERIFIED | #4765 (CLOSED "does not reproduce", wrongly) | Literal U+FFFD written into source from a script |
| 5 | Statement-initial `[`, `-` or `(` after an `if`/`match` block continues the expression | a | med | VERIFIED (plus a new `(` variant) | none | `let none: T[] = []; none`, `return -1;` |
| 6 | `match` of an interface value against an unrelated interface is rejected (E0001), though `is` accepts it | a | med | VERIFIED | none | `let u: unknown = ip; match (u) {…}` |
| 7 | `let k = E.A;` infers the literal type `E.A` | a | low | VERIFIED | none | `let k: E = E.A;` |
| 8 | No narrowing into the right operand of `&&`/`\|\|` | a | med | VERIFIED | none | Nested `if`, helper fns (`succeeded(r)`) |
| 9 | No narrowing of fields (`c.s != null` → `c.s.length()`) | a/d | med | VERIFIED | none | Copy the field into a local |
| 10 | A loop-carried optional local loses narrowing after reassignment | a | med | VERIFIED | none | Non-optional shadow local, eager init + flag |
| 11 | `[]` in a `catch_all` arm of an unannotated `let` → E0155 "type annotations needed" | a | low | VERIFIED | none | `let empty: T[] = []` |
| 12 | **VM call stack capped at 256 frames**: the port crashes (`StackOverflow`) on 400 nested blockquotes or 200 nested lists; Go handles 10,000 | b/e | high | VERIFIED (new, never noticed by the agent) | none | None; the port silently has this limit |
| 13 | ~210–250× slower than Go; 3 of 5 goldmark perf tests fail | e | high | VERIFIED (release: 0.40 s/iter vs Go ~1.9 ms) | none | Native `index_of` search, offset scanners, `peek_line` cache |
| 14 | Reserved words as identifiers: misleading E0017 ("generator block is ignored") plus a cascade of E0010s | a/f | low | VERIFIED | none | Rename (`gen`, `istr`, `do_continue`) |
| 15 | Every command prints 45 stdlib `E0146 unreachable code` warnings plus `code is unformatted` | f | med | VERIFIED | none | `grep -v E0146` on all 133+ invocations |
| 16 | A bare boolean in a `test` block is not an assertion (always passes) | f | med | VERIFIED | caused #4765's wrong closure | Agent used `assert.equal` (not hit directly) |
| 17 | The internal `baml-cli` refuses to run without the agent skill (`BAML_AGENT_SKILL_CHECK`) | f | low | VERIFIED | none | `export BAML_AGENT_SKILL_CHECK=off` in `bin/b` |
| 18 | `baml.regex.new` with a constant, compile-checked pattern still `throws` | c | low | VERIFIED | none | `catch_all` + panic at 6 sites |
| 19 | Regex dialect differs from RE2 (`\d`/`\w` Unicode, `&&`/`--`/`~~` set ops, `[[]` rejected) | c/g | low | VERIFIED | none | `[0-9]` instead of `\d` |
| 20 | Regex works on strings only (code-point offsets); no bytes or streaming API | d | med | VERIFIED (API) | none | `cp_offset_to_byte`, rest-of-source fallback |
| 21 | `String.from_code_points` throws, so `throws never` interface impls can't call it | c | low | VERIFIED | none | `catch_all` fallback |
| 22 | `Uint8Array.zeroes(0)` throws; no infallible empty-bytes constructor | c | low | VERIFIED | none | `"".to_utf8()` |
| 23 | `Xoshiro256PlusPlus.new` is `throws never` but panics on a seed shorter than 32 bytes | c/g | low | VERIFIED | none | Generate a 32-byte seed |
| 24 | `@alias` ignored by `baml.json.from_string`/`deserialize`; field matching is case-sensitive | c/d | low | VERIFIED | none | Name the BAML field `enableEscape` |
| 25 | Numeric conversions: no `int.to_float`, no `float.to_int`; `Duration.to_milliseconds()` returns bigint | c | low | VERIFIED | none | Mixed arithmetic, `itrunc() catch_all`, `.to_int() catch_all` |
| 26 | `baml.json.stringify(unknown)` rejected (wants `json`) | c | low | VERIFIED (by design; `to_string` works) | none | `baml.String.from(v)` |
| 27 | `uint8array` gaps: no `for…in`, no `index_of` offset, no multi-byte `index_of`, no in-place extend, `slice` copies | c/d | med | VERIFIED | none | Index loops, `to_array()`, `append_bytes` push loop, offset-taking scanners |
| 28 | No reference-identity operator (`==` is deep structural) | d | med | VERIFIED (but see agent mistake A1) | none | `mark` sentinel field + `same_node` (17 sites) |
| 29 | No package-level `let`/`const` | d | med | VERIFIED | none | Zero-arg fns, generated `match` trees |
| 30 | Map keys must be `string` (no int/enum); map-literal keys must be literals | d | med | VERIFIED | none | String keys, `{}` then `m[k()] = v` |
| 31 | Panics (incl. index OOB, stack overflow) are uncatchable | d | med | VERIFIED | none | None (no per-case isolation in testutil) |
| 32 | No raw strings (`#"…"#` → E0098); backtick strings dedent and drop the trailing newline | d | med | VERIFIED | #4591 (open) | Doubled backslashes; `` `…` + "\n" `` |
| 33 | No char literals, tuples, class-field defaults, string indexing (`s[i]`), `as` casts, variadics, build tags | d | med | VERIFIED (build tags/variadics by design) | #267 (tuple, closed 2023) | Ints with comments, result classes, `_v1` suffixes, `opts: X[] = []` |
| 34 | Defaulted params must be passed by name (E0005); function types can't have defaults | d | low | VERIFIED | none | `new(options = […])`, explicit `[]` |
| 35 | Interface methods and function types must spell out `throws` (E0170/E0151) | d | low | VERIFIED (by design) | none | 200 `throws never` |
| 36 | A field and a method can't share a name (E0012) | d | low | VERIFIED | none | `list_offset`/`temporary_paragraph_node` |
| 37 | Missing stdlib: temp dirs, `archive/zip`, profiler, `unicode` categories, UTF-8 decode helpers | c | med | VERIFIED (absent from `describe`) | none | `mktemp` via exec, own ZIP+CRC32, generated tables, `utf8.baml` |

Agent mistakes (details in the last section):

- A1. It claimed `includes`/`index_of` are structural. In fact they compare class instances by reference, so a cheap identity check existed.
- A2. It claimed `baml run` can't emit JSON; `--output-format json` exists.
- A3. It concluded `"�"` works, a false positive caused by the tool layer decoding escapes, and then spent about 6 minutes delta-debugging a phantom "namespace-dependent lexer bug".
- A4. It wrote a dummy `baml.regex.new("x")` and `panic(); value` boilerplate that isn't needed, because `panic` is `never`.
- A5. It wrapped context maps in classes, which was unnecessary.
- A6. Its own call-arity error.
- A7. The first attempt's hand-transcribed byte tables had 3 bugs.
- A8. A sub-agent left a broken `zz_diff_test.go` in the shared Go clone.
- A9. It moved `.baml/cache` aside on a false stale-cache suspicion.
- A10. The "test-block local `is` misreport" item it copied as a known bug is NOT REPRODUCED in simple form.

## Detailed entries

### 1. `is`-narrowing to an interface dispatches through the wrong interface (VM crash)

- **Category:** b, runtime/VM. **Severity:** high. **VERIFIED** (`r/b1`). **Issue:** none.
- **Observed:** `VM internal error: interface \`user.Node\` declares no method \`has_blank\``. Evidence: MAIN L527–L534 (19:22:29), in the agent's AST-design probe.
- **Repro:**
  ```baml
  interface Node { function kind(self) -> string throws never }
  interface BlockNode requires Node { function has_blank(self) -> bool throws never }
  class P {
    implements Node { function kind(self) -> string throws never { "P" } }
    implements BlockNode { function has_blank(self) -> bool throws never { true } }
  }
  function f(n: Node) -> bool { if (n is BlockNode) { return n.has_blank(); } false }
  function main() -> bool { f(P {}) }
  ```
- **Workaround:** `match (n) { let bn: BlockNode => bn.has_blank(), _ => false }`. The conventions forbid `if (x is Interface)` (`PORTING_CONVENTIONS.md:28`). Examples: `ns_parser/parser.baml:1380`, `:1525`.
- **Cost:** small per site (the `match` adds 2–3 lines), but every Go `if x, ok := n.(I); ok` has to use it. There is a correctness hazard because the crashing form type-checks.

### 2. Writing a nested field through an interface-declared field (VM crash)

- **Category:** b. **Severity:** high. **VERIFIED** (`r/b2w`, `r/b2s`, `r/b2r`). **Issue:** none. #4813 (open) is a sibling bug with the same "direct field write fails, temporary local works" shape, for bigint arithmetic.
- **Observed:** `VM internal error: type error: expected map, got instance`. Evidence: MAIN L381–L388 (19:20:47–19:20:51), the very first AST probe.
- **Refined today:** *reading* `n.base.pos` through `n: Node` works (returns 1). The crash needs an *assignment* through the path.
  ```baml
  interface Node { base: BaseNode }
  class BaseNode { pos: int }
  class H { base: BaseNode, implements Node {} }
  function main() -> int {
    let h = H { base: BaseNode { pos: 1 } };
    let n: Node = h;
    n.base.pos = 5;        // VM internal error
    h.base.pos
  }
  ```
  `let b = n.base; b.pos = 5;` works.
- **Workaround:** interface fields were dropped altogether. `Node` declares `function base(self) -> BaseNode` (`ns_ast/ast.baml:98`), and every node class implements it (`b: BaseNode` field plus a `base()` method).
- **Cost:** one boilerplate method per node class (~40 classes) and a method call on every `base()` access (28 call sites in core code). No fidelity loss.

### 3. Bound method stored into a field or map slot panics the compiler

- **Category:** a. **Severity:** high (compiler crash). **VERIFIED** (`r/b3` field, `r/b3map` map slot). **Issue:** none.
- **Observed:** `thread '<unnamed>' panicked at crates/baml_compiler2_emit/src/pull_semantics.rs:482:13: internal error: entered unreachable code: MakeBoundMethod must be handled in emit_rvalue_pull`. Evidence: MAIN L1161–L1187 (19:40:43–19:41:04); workaround commit `0ba923d`.
- **Repro:**
  ```baml
  class Holder { f: ((x: int) -> int throws never)?, }
  class G { function twice(self, x: int) -> int { x * 2 } }
  function main() -> int { let g = G {}; let h = Holder { f: null }; h.f = g.twice; 0 }
  ```
  - `m["a"] = g.twice` (map index assignment) panics the same way.
  - Passing `g.twice` as an argument or in a class literal (`Holder { f: g.twice }`) works (`r/b3arg`, `r/b3lit`).
- **Workaround:** bind to a typed local first. Examples: `ns_renderer/renderer.baml:377` (`let rf: RenderFunc = self.render_fn;`), `ns_extension/footnote.baml:614`, `ns_renderer/ns_html/html.baml:736`. There are 30 such locals.
- **Cost:** one extra line per registered render function, and the conventions doc had to teach it to every sub-agent.

### 4. Unsupported string escapes (`\x41`, `A`, `\u{41}`) are silently kept verbatim

- **Category:** a. **Severity:** high: silent wrong output, and the port emitted wrong HTML for NUL bytes until goldmark's `extra.txt` case 26 caught it. **VERIFIED** (`r/b4`, `r/escapes`, `r/escapes_bt`). **Issue:** #4765, **CLOSED** on 2026-09-06 as "does not reproduce". Per the post-mortem, the closer used bare booleans in a `test` block, which never fail (item 16). It should be reopened.
- **Exact decode set today:**
  - Quoted strings decode `\n \t \r \0 \b \f \v \\ \"`.
  - Backtick strings additionally decode `` \` `` and `\$`.
  - Everything else, `\x.. \u.... \u{..} \' \a \e \/ \q`, is kept with the backslash and **no diagnostic**. For example `"\x41".length() == 4`, `"\u{41}".length() == 6`.
  - Minor correction to the agent's note (`PORTING_CONVENTIONS.md` pitfall 7 says only `\n \t \r \0 \\ \"` decode): `\b \f \v` do decode as well.
- **Evidence:**
  - FIRST L569–L605 (00:23:47–00:24:06): the first attempt read `unescape_string_literal_preserves_unknown_sequences` in `baml_compiler2_ast/src/lib.rs`, so the behaviour is intentionally tested. It then made its table generator panic on control characters instead of emitting `\u{..}`.
  - MAIN L1215–L1236 (19:42:52–19:43:12): see agent mistake A3.
  - MAIN L1559–L1817 (19:52:32–19:58:40); fix commit `7387085` ("U+FFFD literals").
- **Workaround:** literal U+FFFD characters in source, written from Python because tool layers decode `\u` (`ns_util/util.baml:629`, `:642`; `ns_renderer/ns_html/html.baml:898`). Generated tables use literal characters or `\n`/`\t`/`\r` only (`tools/gen/main.go`).
- **Cost:** about 20 minutes of agent time across the two sessions. Invisible characters in source are hard to review, and there was a latent wrong-output bug until tests caught it.

### 5. Statement-initial `[`, `-` or `(` after an `if`/`match` block is parsed as a continuation

- **Category:** a, parser. **Severity:** medium. **VERIFIED** (`r/b5`, `r/b5paren`, `r/b5while`). **Issue:** none.
- **Observed errors:**
  - `[`: E0010 `expected \`expression\`, found \`']'\``.
  - `-`: E0004 `operator \`-\` cannot be applied to \`void\` and \`1\``.
  - `(` (new today): E0006 `` `void` is not a function and cannot be called ``.
  - A `while` block followed by `-y` is fine; `match (x) {…}` followed by `-1` fails like `if`.
- **Repro:**
  ```baml
  function a(x: int?) -> int[] { if (x != null) { return [x]; } [] }
  function b(x: int?) -> int  { if (x != null) { return x; } -1 }
  function c(x: int?) -> int  { if (x != null) { return x; } (1 + 2) }
  ```
- **Evidence:** MAIN L960 (19:33:59, `[` in `parser.baml`), MAIN L1476–L1480 (19:48:43, `extra_test.baml`), SUB-DEFL L121–L129 (`-1` in `definition_list.baml`), MAIN L2489–L2491 (20:14:29, reconfirmed).
- **Workaround:** `let none: string[] = []; none` (13 sites, e.g. `extra_test.baml:84`, `ns_parser/parser.baml:1766`) and `return -1;` (`ns_extension/ns_ast/definition_list.baml:57`, `:98`).
- **Cost:** 1–2 extra lines per site. The error messages are misleading, so each first hit cost a debugging round-trip.

### 6. `match` of an interface value against an unrelated interface is rejected

- **Category:** a, type checker. **Severity:** medium. **VERIFIED** (`r/b6`, `r/b6w`). **Issue:** none.
- **Observed:** `parser.baml:1105:21 error[E0001]: mismatched types — expected \`InlineParser\`, found \`CloseBlocker\``. Evidence: MAIN L938 (19:33:42); fix in `f6954af`.
- **Inconsistency found today:** `ip is CloseBlocker` on the same value type-checks and returns `true` at runtime. Only the `match` arm pattern is rejected.
- **Workaround:** `let any_ip: unknown = ip; match (any_ip) { let cb: CloseBlocker => … }` (`ns_parser/parser.baml:1104–1111`).
- **Cost:** 1 line, one site. Without it the port of Go's `ip.(CloseBlocker)` would be impossible.

### 7. `let k = E.A;` infers the singleton type `E.A`

- **Category:** a. **Severity:** low. **VERIFIED** (`r/b7`). **Issue:** none.
- **Observed:** `error[E0001]: expected \`root.ast.ReferenceLinkKind.ReferenceLinkKindFull\`, found \`…Collapsed\``. Evidence: MAIN L1060 (19:38:34).
- **Workaround:** annotate the let: `let ref_type: root.ast.ReferenceLinkKind = …` (`ns_parser/link.baml:166`).
- **Cost:** trivial.

### 8–10. Narrowing gaps

- **Category:** a/d. **Severity:** medium, because this pattern is everywhere in Go code. All three are **VERIFIED** (`r/n1`, `r/n2`, `r/n3`). **Issue:** none.
- **N1: no narrowing across `&&`/`||`.**
  - `x != null && x.length() > 0`, `x == null || x.length() == 0`, and the condition of `if (x != null && x.length() > 0)` all fail with E0007 `type \`string | null\` has no member \`length\``.
  - Evidence: MAIN L593–L641 (19:24:29–19:24:51, `reader.baml`), L2200–L2206 (`doc_test.baml`), L750 (`block.baml`).
  - Workarounds: nested `if`s (`ns_text/reader.baml:735`), `let has_attrs = if (attrs == null) { false } else { … }` (`ns_ast/ast.baml`), a helper `succeeded(r)` (`doc_test.baml:30–35`).
- **N2: no narrowing of fields.**
  - `if (c.s != null) { return c.s.length(); }` fails with E0007.
  - Evidence: MAIN L360 (19:20:35), where the first attempt's `decoder.baml` didn't compile.
  - Workaround: copy into locals (`ns_text/decoder.baml:41–42`), or `self.segs?.push(seg)` after an assignment.
- **N3: loop-carried optional locals lose narrowing.** After `if (d == null) { return …; }`, a `while` loop that does `d = p` (with `p` narrowed) makes `d` be `N | null` again, even at the top of the loop.
  - Evidence: MAIN L750–L756 (19:28:32–19:28:42).
  - Workarounds: `let d: Node = d0;` (`ns_ast/ast.baml:293–295`); an eagerly built cell plus a `registered` flag in place of Go's lazily created pointer (`ns_extension/table.baml:171–175`).
- **Cost:** by far the most frequent friction. An estimated 40–60 sites were restructured, since no single marker exists. Each nested `if` adds 2–4 lines, and it contributes to the 1.10× line ratio.

### 11. Empty `[]` in a `catch_all` arm of an unannotated `let` needs an annotation

- **Category:** a, inference. **Severity:** low. **VERIFIED** (`r/e155b`); not reproduced when the enclosing function's return type provides the expected type (`r/e155`). **Issue:** none.
- **Observed:** `error[E0155]: type annotations needed — full type: \`unknown[]\``. Evidence: MAIN L1308 (19:44:39).
- **Repro:**
  ```baml
  class Case { n: int }
  function load(s: string) -> int {
    let cases = baml.json.from_string<Case[]>(s) catch_all (e) { _ => [] };
    cases.length()
  }
  ```
- **Workaround:** `let empty: CommonmarkSpecTestCase[] = []; empty` (`commonmark_test.baml`, `ns_tools/gen_emb_structs.baml:27`, `:38`).

### 12. VM call stack is capped at 256 frames, so the port crashes on deeply nested Markdown (new finding)

- **Category:** b/e. **Severity:** high: a fidelity loss and a DoS vector for a parser; goldmark is used on untrusted input. **VERIFIED** today. **Issue:** none.
- **Observed:**
  - `MAX_FRAMES = 256` in `crates/bex_vm/src/vm.rs:118`. The first attempt found this (FIRST L442–L467, 00:21:37–00:22:04: "VM call stack capped at 256 frames … deep recursion must be avoided").
  - The finding never made it into `PORTING_NOTES.md` or the conventions, and the port was never tested for it. The fuzz inputs average 36 bytes.
- **Port-level repro** (in `…/gm.k3dr/port`, helper `ns_dev/zz_probe.baml: deep_probe`), with `root.spec_markdown()` (`parser.New()` + `html.New(WithXHTML, WithUnsafe)`):

  | Input | BAML port | Go goldmark (same commit) |
  |---|---|---|
  | `">" * 200 + " x"` | ok | ok |
  | `">" * 400 + " x"` | `uncaught throw: baml.panics.StackOverflow` | ok (up to 10,000 tested) |
  | 100 nested `- a` list items | ok | ok |
  | 200 nested `- a` list items | `StackOverflow` | ok (up to 2,000 tested) |

- **Minimal repro:** `function depth(n: int) -> int { if (n == 0) { 0 } else { 1 + depth(n - 1) } }`. `depth(250)` works, `depth(260)` throws `StackOverflow`, which is uncatchable (item 31). The traceback prints about 250 frame lines.
- **Workaround used:** none. The limit is baked into the port; the parser's recursive walks (`walk`, block/inline processing) inherit it.
- **Cost:** port output diverges from Go (crash vs HTML) at nesting depths of roughly 100–400, depending on construct.

### 13. Performance: about 210–250× slower than Go

- **Category:** e. **Severity:** high. **VERIFIED** today on the release build (load average 3.5–4.4):
  - `benchmark.goldmark_benchmark --n 5` gives an average of 0.3998 s per conversion of the 202 KB `_data.md`. Go measured 1.88–2.17 ms in the post-mortem, so about 210×. The agent measured 0.47 s on `fasttest`.
  - A 2M-iteration `while` loop takes 53 ms, about 26 ns per iteration.
  - goldmark's perf tests (n = 50,000, 5 s budget), run individually on release: DeepNestedLabel 3.9 s PASS, ProcessingInstruction 2.2 s PASS, CDATA 19.1 s FAIL, Decl 5.5 s FAIL, Comment 7.3 s FAIL.
- **Evidence:** MAIN L1499–L1507 (19:50:56–19:51:38, perf probe), L1915–L1971 (19:59:50–20:01:57, native-search experiment and micro-benchmarks), L2034–L2036, L2458–L2479, L2537–L2539.
- **Root causes, as reasoned by the agent (unprofiled, since no profiler exists):**
  - VM loop overhead versus Go's SIMD `bytes.Index`.
  - `PeekLine` returns an O(1) subslice in Go, but in BAML every inline-parser attempt copies the rest of the line (item 27).
- **Workarounds (performance-only deviations):**
  - `util.bytes_index` delegates to native `uint8array.index_of` / `string.index_of` with code-point→byte conversion (`ns_util/util.baml:107–140`, commit `54c71a9`).
  - Offset-taking autolink scanners `find_url_index_at` / `find_email_index_at` (`ns_parser/auto_link.baml:54`, `:124`).
  - A position-keyed `peek_line` cache (`ns_text/reader.baml:132`, `:170`, commit `687709d`). It gave only a small gain (decl −12 %, comment −16 %).
- **Cost:** about 30 lines of non-Go code, plus a decode-to-string round-trip that falls back to the VM loop on invalid UTF-8.

### 14. Reserved words used as identifiers give misleading diagnostics

- **Category:** a/f. **Severity:** low. **VERIFIED** (`r/reserved`). **Issue:** none; #4059 is the codegen analogue.
- **Observed:**
  - A field named `generator` yields `warning[E0017]: this \`generator\` block is ignored: code generators are configured in \`baml.toml\` now…`, which is wrong advice, followed by 4+ `E0010 unexpected token … expected top-level declaration` errors (MAIN L926, 19:33:38).
  - A parameter named `is` gives `E0107 parameter … is missing a name` plus a cascade (MAIN L938; SUB-FOOT L135 shows 10 cascaded errors for `let is = …`).
- **Workaround:** renames: `gen` (`ns_parser/parser.baml:92`), `istr` (`ns_extension/footnote.baml:560`), `do_continue`, `ps`.

### 15. Toolchain warning noise on every command

- **Category:** f. **Severity:** medium, because it degrades every agent turn. **VERIFIED:** `baml-cli check` on the port prints **45** `warning[E0146]: unreachable code` lines, all in the stdlib (`csv.baml`, `iter.baml`, `stream.baml`, `ns_mcp/mcp.baml`, …), plus `warning: code is unformatted; run \`baml fmt\`` on every `run`/`test`. A bare project prints 11 E0146 lines. **Issue:** none.
- **Origin:** E0146 was added by `f603110e74` (#4995), one commit before the port's base.
- **Workaround:** `2>&1 | grep -v E0146` baked into every command in `PORTING_CONVENTIONS.md`.

### 16. A bare boolean expression in a `test` block is not an assertion

- **Category:** f. **Severity:** medium (a silent false pass). **VERIFIED** (`r/testbare`): `test "bare" { "abc".length() == 99 }` PASSES, and `assert.equal(…)` fails.
- **Issue:** none; this behaviour is what got #4765 wrongly closed. The porting agent did not hit it, because it always asserted on helper-returned failure lists.

### 17. Internal `baml-cli` refuses to run without the agent skill

- **Category:** f. **Severity:** low. **VERIFIED:** `error: the BAML agent skill is required but is not installed; run \`baml agent install\`… set BAML_AGENT_SKILL_CHECK=off to bypass this check`, plus `warning: using the internal BAML toolchain binary directly is not recommended`. Evidence: FIRST L201 (00:18:42).
- **Workaround:** the `bin/b` wrapper exports `BAML_AGENT_SKILL_CHECK=off` and greps out the warning.

### 18–20. Regex

- **18. Constant patterns still throw** (c, low, **VERIFIED** `r/regexconst`).
  - `function r() -> baml.regex.Regex throws never { baml.regex.new("a+") }` fails with E0096 `may also throw \`baml.regex.Error\``, even though the compiler validates constant patterns (`baml.regex.new("[[]")` gives E0174 at compile time).
  - Workaround: `catch_all (e) { _ => { baml.sys.panic(…); baml.regex.new("x") catch_all … } }` at 6 sites (e.g. `ns_extension/linkify.baml:22–26`, `ns_testutil/testutil.baml:136–139`). Part of that boilerplate is unnecessary; see A4.
  - Evidence: SUB-LINK final report.
- **19. Dialect differences from Go RE2** (c/g, low, **VERIFIED** `r/regex`):
  - `^\d$` matches `٣`, and `^\w$` matches `é` (Unicode-aware; RE2 is ASCII).
  - `[a&&b]` does not match `&` (set intersection).
  - `[[]` is rejected with "unclosed character class".
  - Evidence: SUB-LINK L101–L109, L204–L206.
  - Workaround: `[0-9]` instead of `\d` in the linkify URL regexp (`ns_extension/linkify.baml:33–34`); test regexps are copied verbatim, with a comment.
- **20. String-only API, code-point offsets, no streaming** (d, medium, **VERIFIED** from the API: `Match`/`Group` offsets are code points).
  - Workaround: `regexp_find_submatch_index` converts bytes → string → code-point offsets → byte offsets (`ns_text/reader.baml:702–726`). Go's `FindReaderSubmatchIndex` fallback across lines becomes a match against the rest of the source (`ns_text/reader.baml:742` `TODO(port)`).
  - Cost: lossy for invalid UTF-8, and a small semantic deviation for multi-line regex fallback.

### 21. Throw-set propagation from stdlib calls breaks `throws never` conformance

- **Category:** c (arguably d). **Severity:** low. **VERIFIED** (`r/fp`): calling `baml.String.from_code_points([r])` inside a `throws never` method gives E0096 `may also throw \`baml.errors.InvalidArgument\``.
- **Evidence:** FIRST L641 (00:26:09); MAIN L1206 (19:42:46), where four E0120 non-conformance errors for `TextWriter` against `BufWriter` cascaded from one helper.
- **Workaround:** `catch_all (e) { _ => "" }` / `"�"` fallbacks (`ns_util/util.baml:895`, `:902`), and replacing `from_code_points([0xFFFD])` with a literal (item 4).

### 22. `Uint8Array.zeroes(0)` throws; no infallible empty constructor

- **Category:** c. **Severity:** low. **VERIFIED** (`r/nums`): `function j() -> uint8array throws never { baml.Uint8Array.zeroes(0) }` gives E0096.
- **Evidence:** FIRST L657 (00:26:17).
- **Workaround:** `new_bytes() { "".to_utf8() }` (`ns_util/util.baml:19`), used everywhere (48 `?? root.util.new_bytes()` sites).

### 23. `Xoshiro256PlusPlus.new(seed)` is declared `throws never` but panics on short seeds

- **Category:** c/g. **Severity:** low. **VERIFIED** (`r/xoshiro`, `r/xoshiro2`): `uncaught throw: baml.panics.UserPanic {message: "Rng seed must be at least 32 bytes, got 4"}`, and `catch_all` can't catch it.
- The source doc comment does say `# Panics`, but `baml describe baml.random.Xoshiro256PlusPlus` shows only `new(seed?: uint8array) … throws never`.
- **Evidence:** MAIN L2229–L2244 (20:06:58–20:07:09).
- **Workaround:** build a 32-byte seed (`ns_fuzz/fuzz_test.baml:84`).

### 24. `baml.json` ignores `@alias` and matches field names case-sensitively

- **Category:** c/d. **Severity:** low. **VERIFIED** (`r/alias`, `r/alias2`): with `enable_escape: bool? @alias("enableEscape")`, `from_string` and `deserialize` both ignore `{"enableEscape": true}` but accept `{"enable_escape": true}`.
- **Evidence:** MAIN L1293 (19:44:24). The agent first wrote `#[alias(…)]`, then switched field names.
- **Workaround:** name the field in camelCase, `enableEscape: bool?` (`ns_testutil/testutil.baml:92–97`). It breaks snake_case naming.

### 25. Numeric conversion gaps

- **Category:** c. **Severity:** low. **VERIFIED** (`r/nums`): `int.to_float` and `float.to_int` don't exist (E0007). `float.itrunc()` throws `InvalidArgument`, `Duration.to_milliseconds()` returns `bigint`, `bigint.to_int()` throws, and `baml.Bigint.from` does not exist.
- **Evidence:** MAIN L1482–L1497 (19:48:49–19:48:56), L2355–L2369.
- **Workarounds:**
  - `(sum_ns / n) / 1000000000.0` (mixed arithmetic; `ns_benchmark/goldmark_benchmark.baml:29`).
  - `.itrunc() catch_all (e) { _ => 5000 }` and `.to_milliseconds().to_int() catch_all (e) { _ => 0 }` (`extra_test.baml:79–80`).

### 26. `baml.json.stringify` rejects `unknown`

- **Category:** c (by design; `stringify` takes `json`). **Severity:** low. **VERIFIED** (`r/json_unknown`): E0001 `expected \`baml.json.json\`, found \`unknown\``. `baml.json.to_string(v)` accepts it.
- **Evidence:** MAIN L750–L754.
- **Workaround:** `baml.String.from(v)` in the node dumper (`ns_ast/ast.baml:484`). BAML's display format is not JSON, but it matches Go's `%v`-style dump well enough for goldmark's tests.

### 27. `uint8array` API gaps

- **Category:** c/d/e. **Severity:** medium. **VERIFIED** (`r/forin`; `describe baml.Uint8Array`):
  - `for (let b in bs)` fails with E0006 `cannot iterate over type \`uint8array\`` (SUB-TABLE L95, MAIN L2491).
  - `index_of(item: int)` has no `from` offset, and there is no subsequence `index_of`.
  - `concat` allocates, and there is no in-place `extend`/`push_all`.
  - `slice` copies.
- **Workarounds:**
  - Index loops (`ns_extension/table.baml`), or `for (let tc in tcs.to_array())` (`ns_parser/parser.baml:1095`).
  - `append_bytes` as a `push` loop (`ns_util/util.baml:23–31`).
  - `index_byte_from` / `index_byte_in_range` VM loops.
  - Offset-threading helpers (`has_prefix_at`, `find_url_index_at`).
- **Cost:** the main driver of item 13, plus 10+ helper functions.

### 28. No reference identity

- **Category:** d. **Severity:** medium. **VERIFIED** (`r/ident`): two distinct `N { v: 1 }` compare `==` as `true`, and so do two interface-typed values (`r/ident2`).
- **Evidence:** MAIN L399–L410 (19:20:59–19:21:08).
- **Workaround:** a scratch `mark: int` field on `BaseNode` (`ns_ast/ast.baml:51`). `same_node(a, b)` writes a sentinel into `a` and checks `b` (`ns_ast/ast.baml:79–95`); there are 17 call sites.
- **Correction:** `Array.includes`/`index_of` compare class instances **by reference** (documented in `containers.baml:479–489`, and verified: `[a].includes(b)` is `false`, `[a].includes(a)` is `true`). The agent's notes and the post-mortem say the opposite. See A1.

### 29. No package-level `let`/`const`

- **Category:** d. **Severity:** medium. **VERIFIED** (`r/misc3`): E0010 `top-level \`let\` bindings are not supported`. Evidence: FIRST L264 (00:19:38).
- **Workaround:** zero-arg functions for constants, singletons and context keys (e.g. `FLAG_BLANK_PREVIOUS_LINES()`, `identity_decoder()`, `link_label_state_key()`).
- **Generated tables:** `tools/gen` emits `match` decision trees, about 5,500 lines (`html5entities.gen.baml`, `unicode_case_folding.gen.baml`, `unicode_tables.gen.baml`). The `[256]uint8` URL/email tables in `auto_link.go` become range checks (`ns_parser/auto_link.baml:151`).
- **Cost:** re-evaluation on every call (a `global_attribute_filter()` rebuild per render call), 5.5k generated lines, and Go's `NewNodeKind` counters become strings.

### 30. Map key restrictions

- **Category:** d. **Severity:** medium. **VERIFIED** (`r/mapkeys`):
  - `map<int, string>` and `map<E, string>` give E0067 `map keys must be \`string\``.
  - `{ k(): 1 }` gives E0010.
  - `{1: "a"}` and `{1 => "a"}` don't parse.
- **Evidence:** FIRST L419, SUB-LINK L157–L169, SUB-TABLE L95.
- **Workarounds:**
  - String keys: `NodeKind`/`ContextKey` become strings; `BytesFilter` slots use `map<string, string[]>` (`ns_util/util.baml:968`).
  - The typographer's int-keyed substitution map becomes an array of entries (`ns_extension/typographer.baml:140`).
  - `{}` then `nrs[kind()] = …` (13 sites, `ns_extension/table.baml:492–498`).

### 31. Panics are uncatchable

> **Correction (2026-09-28):** this item is wrong. Re-verified on the same release `baml-cli`: `StackOverflow`, `UserPanic`, `IndexOutOfBounds` and `Panic` are all catchable by naming them in a `catch` arm, e.g. `deep(300) catch (e) { baml.panics.StackOverflow => -1 }` returns `-1`. Only `catch_all`'s `_` arm skips panics (by design). goldmark's `recover()`-based per-case test isolation could therefore have been ported. The 256-frame limit itself (item 12) is real.

- **Category:** d (design). **Severity:** medium. **VERIFIED** (`r/panic_catch`, `r/panic_catch2`): `catch_all` does not catch `UserPanic` or `IndexOutOfBounds`, and `StackOverflow` is uncatchable too (item 12).
- **Workaround:** none possible. goldmark's `recover()`-based per-case isolation in `testutil` is dropped (`ns_testutil/testutil.baml:8–11`, `:329`), so one panicking case aborts a whole case file.

### 32. Raw strings removed; backtick strings dedent and drop the trailing newline

- **Category:** d. **Severity:** medium. **VERIFIED** (`r/hashstr`, `r/bt`):
  - `#"a\b"#` gives E0098 `Hash string literals like \`#"..."#\` are no longer supported`.
  - `` `a⏎b⏎` `` evaluates to `a\nb` (trailing newline dropped).
  - `` `  x⏎  y` `` evaluates to `x\ny` (dedented).
  - Backticks still process escapes, so every regex backslash must be doubled.
- **Issue:** #4591 (open), about hash-string removal without a render-preserving migration path.
- **Evidence:** SUB-FOOT L164–L172; SUB-LINK L101–L109; MAIN L2494–L2496.
- **Diagnostic nit:** a `#"…"#` literal containing `"#` (HTML with `href="#…"`) produces a cascade of E0010s rather than the E0098 hint (SUB-FOOT L166).
- **Workaround:** `` `…` + "\n" `` (`ns_extension/footnote_test.baml:33`, `:41`); doubled backslashes in every regexp (`ns_extension/linkify.baml:22`, `:34`, `:346`).

### 33. Assorted missing syntax

All in category d; all **VERIFIED** unless noted.

- **Char literals:** `let x = 'a'` gives E0010 `found \`error\``. Bytes are written as ints with comments, 78 times (`124 // '|'`).
- **Tuples:** `-> (int, string)` gives E0010. Go multi-returns become result classes (`ReadWhileResult`, `IndentPos`, `DecodedRune`, `OpenResult`, `PeekedLine`, …). Old closed issue #267.
- **Class-field defaults:** `v: int = 3` gives E0010 `Unexpected token in class body`. All constructors spell every field.
- **String indexing:** `"abc"[0]` gives E0008 `cannot index into type \`string\``. The port uses `code_point_at`/`at`.
- **`as` casts:**
  - `(a as I)` gives the confusing E0002 `unresolved type: a`, or, in the agent's original, E0010 `expected ')'` (MAIN L383).
  - Workaround: typed lets (`let pn: Node = p;`).
- **Variadics and build tags (by design):**
  - `opts ...X` becomes `opts: X[] = []`.
  - The `goldmark_v1_attribute` variant is compiled alongside with `_v1` suffixes (`ns_parser/attribute_v1.baml`, `ns_text/value_v1.baml`).
- **Struct embedding:** it doesn't exist. It is modeled as a `b: BaseNode` field plus interface default methods and `requires` super-interfaces.

### 34. Defaulted parameters must be passed by name

- **Category:** d. **Severity:** low. **VERIFIED** (`r/e0005`): `new([1])` against `new(opts: int[] = [])` gives E0005 `defaulted parameter \`opts\` must be passed by name`.
- **Evidence:** MAIN L750, L979.
- **Workaround:** `root.parser.new(options = […])`, `html.new(opts = […])` everywhere. A related trap: function-typed values can't have defaults, so `MarkdownToStringFunc` callers must pass `[]` explicitly (the SUB-DEFL L189 own error).

### 35. Interface methods and function types must spell out `throws`

- **Category:** d (by design). **Severity:** low. **VERIFIED** (`r/e0170`): E0170 / E0151.
- **Evidence:** FIRST L264, L293.
- **Cost:** 200 `throws never` annotations and 60 `catch_all` blocks across the port.

### 36. A field and a method can't share a name

- **Category:** d. **Severity:** low. **VERIFIED** (`r/fieldmeth`): `class D { offset: int, function offset(self) -> int {…} }` gives E0012 `name \`D.offset\` defined 2 times as: field, method`.
- **Workaround:** renamed fields `list_offset` and `temporary_paragraph_node` (`ns_extension/ns_ast/definition_list.baml:3–6`, `:12`).
- **Related:** Go export-case pairs collide in snake_case (`NewX`/`newX`, `footnotes`/`Footnotes`) and need ad-hoc renames (`new_*_inline_parser`, `FootnotesImpl`). That is inherent to the name mapping, not a BAML bug.

### 37. Missing stdlib pieces

- **Category:** c. **Severity:** medium in aggregate. **VERIFIED** as absent from `baml describe baml`.
- **Temp directories:** `mktemp -d` via `baml.sys.exec` (`doc_test.baml:114`).
- **`archive/zip`:** a hand-written stored-entry ZIP writer and CRC-32 (`ns_tools/gen_oss_fuzz_corpus.baml:70–120`).
- **Profiler:** none; the Go benchmark's pprof argument was dropped (`ns_benchmark/goldmark_benchmark.baml:4–5`), and hotspot attribution in item 13 is guesswork.
- **`unicode` category predicates:** generated range tables (`unicode_tables.gen.baml`, 940 lines), plus `\p{L}`/`\p{Nd}` regexps for typographer letters and digits (`ns_extension/typographer.baml:364–379`).
- **UTF-8 decode helpers:** `ns_util/utf8.baml` (154 lines).
- **`fmt.Sprintf`:** template strings cover it.

### Not reproduced / known-from-repo

- **"`is`/reflection on a boxed test-block local misreports":** copied into the conventions from the BAML repo's own `ns_is_operator` test comment (MAIN L263–L265). My minimal test (`r/testis`, `let v: unknown = User{…}; assert.is_true(v is User)` inside a `test`) **passes**, so it is **NOT REPRODUCED** in simple form. The port avoided it anyway by always asserting on helper results.

## Agent mistakes (things treated as BAML limitations that were not)

- **A1. Reference identity was available.**
  - `PORTING_NOTES.md` M1 and the post-mortem say "`array.includes/index_of` on class instances are also structural". They are not: the stdlib docs (`containers.baml:479–489`) and my test (`r/ident2`) show class instances, arrays and maps compare **by reference** in `includes`/`index_of`.
  - `[a].includes(b)` is therefore a correct, if allocating, identity test.
  - The `mark`-sentinel `same_node` hack, which mutates shared state and would be wrong under concurrency, was unnecessary. M1 should read "no identity *operator*".
  - The first attempt printed evidence of this at FIRST L298 but misread it, because its probe class overrode `Equals`.
- **A2. `baml run` can emit JSON.**
  - P4 says `baml run` prints values in a debug format "rather than JSON, so data exchange … had to go through files" (MAIN L2266–L2301).
  - `--output-format json` exists (`baml run --help`), and I verified it prints valid JSON for the `FuzzPair[]` dump.
  - The agent also used `run --function f -- f --arg …`, but `run f -- --arg …` works.
  - The debug default (`\u{a0}` escapes) is still a reasonable nit.
- **A3. The `�` false positive and phantom lexer bug.**
  - At MAIN L1226–L1233 (19:42:59) the agent concluded "`\u{FFFD}` and `\x41` escapes are silently kept … `�` works".
  - The Bash tool had decoded `�` into a literal U+FFFD before it reached disk. The agent then `sed`-replaced every `\u{fffd}` with `�`, which broke the NUL→U+FFFD escape (a latent wrong-HTML bug).
  - When `extra.txt` case 26 failed, it spent 19:52:53–19:58:37 (MAIN L1593–L1814) bisecting files and namespaces for "identical literals decode differently depending on the file". The probe files contained the literal character while the real files contained `�`.
  - It eventually diagnosed this correctly. The root BAML issue (item 4) is real; the "namespace-dependent" behaviour was not.
- **A4. Unnecessary regex boilerplate.**
  - Every must-regexp has `{ baml.sys.panic(…); baml.regex.new("x") catch_all (e2) { _ => baml.sys.panic("unreachable") } }`, and several catch arms use `panic(…); ""`.
  - `baml.sys.panic` returns `never`: `baml.regex.new("a+") catch_all (e) { _ => baml.sys.panic("bad") }` and `from_string<T[]>(s) catch_all (e) { _ => baml.sys.panic("bad") }` both compile (`r/e155` `load3`, `re`).
  - The regex "constant pattern throws" complaint (item 18) stands, but the dummy regex does not need to.
- **A5. Unnecessary class-wrapping of maps.**
  - SUB-FOOT wrapped `map<string, FootnoteDefinition>` context values in `FootnoteDefsMap` "as an untested precaution" (`ns_extension/footnote.baml:185–190`).
  - `match (u) { let m: map<string, C> => … }` on an `unknown` works and distinguishes value types (`r/unkmap`).
- **A6. Call arity.** SUB-DEFL L189's `E0005 expected 2 argument(s), got 1` was its own missing `opts` argument to a function-typed value.
- **A7. Hand-transcribed tables.** The first attempt's hand-written `is_space` (included `\v \f`), URL-safe table (`0x7F`) and UTF-8 length table (`0xC0/0xC1`) were wrong; they were fixed in `7387085` after goldmark's tests failed (MAIN L1851–L1899).
- **A8. Shared-clone pollution.** SUB-TABLE copied `zz_diff_test.go` into the shared Go clone `<local>/work-repos/goldmark-baml-port-src/extension/` to compare outputs, and a failed build left it there. SUB-DEFL reported that it broke `go test ./extension` for others.
- **A9. Stale-cache suspicion.** At MAIN L1648 the agent moved `.baml/cache` aside, suspecting a stale bytecode cache. There was none; the cause was A3.
- **A10. Test-block `is` misreport.** It adopted the "test-block `is` misreport" as a known VM bug without re-checking (see "Not reproduced").
