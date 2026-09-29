# Post-mortem: porting momiji-rs/sasso to BAML

Report written 2026-09-29, by the same Claude Code session that ran the port. It is not an independent review; see section 7.

- **Original:** momiji-rs/sasso at `15c44de` (`npm-v0.18.0-180-g15c44de`, 2026-09-24). It is a zero-dependency Rust SCSS → CSS compiler (library + `sasso` CLI) that aims for byte-exact dart-sass 1.104.1 output. The port kept its checkout in `port/upstream/sasso`, which is not committed.
- **Port:** this directory. It was developed in `<local>/porting-project`; this copy leaves out the upstream clone, the packed binary, `.baml/` caches and the agent's orchestration state.
- **Toolchain:** the `baml` wrapper 0.2.5 selecting `0.20.2-nightly.20260923.a` (the `nightly` channel at the time). Every repro below was re-run on 2026-09-29 with `0.20.2-nightly.20260925.a`, which is now the pinned default on this machine.
- **Agent session:** one Claude Code session (Claude Opus 5.5), `<local>/transcripts/…/61fd2bb7-cc53-4101-a6ca-8cdb5e818bbf.jsonl`, plus 61 subagent transcripts. The port ran from 2026-09-25 16:57 to 23:02 PDT. Benchmarks and this write-up came later.

Labels used below:
- **[measured]**: re-run for this report (2026-09-29), or measured with a script that is in `port/`.
- **[agent claim]**: taken from a porter subagent's report or a `// PORT:` note without re-checking.

## 1. Summary

- **What was ported.** Everything in `src/`:
  - the library, the CLI, the `--watch` mode and the local-time/TZif code;
  - 60 Rust files → 61 BAML files, one namespace per Rust module, in the same order and with the same names.
  - All 274 `#[cfg(test)]` unit tests, all 12 integration-test crates (790 tests), `examples/compile.rs` and `benches/compile.rs`.
  - Not ported: the FFI/packaging wrappers (`wasm/`, `ffi/`, `napi/`, `nix/`) and the JS/Python harnesses (`spec/`, `bench/`).
- **Zero stubs, zero compile errors [measured].** `grep -r root.std.todo baml_src` is empty. `baml check` on 20260925.a reports 0 errors and 17 warnings:
  - 11 `E0146` warnings located in builtin stdlib files (W31);
  - 6 in the port: dead code after panics, and the forced `jobs = 1`.
- **Test pass rate [measured].** `baml test`: **1,107 passed, 0 failed**, 14 s wall time on 20260925.a. That is 274 unit + 790 integration + 43 tests of the port's own std shim.
  - The 465 `parity.rs` cases also pass in live-parity mode against the Rust binary [measured on 2026-09-25].
  - The CLI tests spawn the packed `dist/sasso`, and several tests read upstream's `tests/fixtures/`. Without those two, 86 tests fail with "No such file or directory" [measured].
- **Output parity with the Rust binary [measured].**
  - `port/corpus/`: 982 cases extracted from upstream's `parity.rs` and `integration.rs`, with the Rust binary's output as the expected result. **982/982 byte-identical.**
  - Bootstrap 5.3.3 (`bootstrap.scss`): 276,946 bytes of CSS plus 8,696 bytes of deprecation warnings on stderr. **Both byte-identical.**
  - On 2026-09-25 [measured then], `port/compare.sh` also showed identical stdout, stderr and exit code for error diagnostics, source maps, `.sass` input and `@use`/`@forward`/`@import` graphs.
- **Changes made while writing this report:**
  - 20260925.a removed `baml.id.new`, which the port used for identity tokens. It is replaced by `baml.random.SystemRandom` (one line in `ns_std/core.baml`).
  - Five color functions were switched from BAML's `Float.to_degrees` to the port's Rust-exact `f64_to_degrees` (W33).
  - Every number in this section was measured after both changes.
- **Bottom line.** A complete, behaviourally exact line-by-line port of a 93K-line Rust program is possible in today's BAML. It is 60–700× slower than native (section 3).
  - Of the bugs hit, the silent ones mattered most:
    - `-0.0` constant folding;
    - a miscompiled null check;
    - the `env` name capture;
    - NaN comparisons;
    - `includes` identity semantics;
    - panics escaping `catch_all`.
  - The crashes had easy workarounds, except the compiler's own stack overflow, which needed `RUST_MIN_STACK` during the port.
  - The biggest remaining fidelity gap is the VM's 256-frame limit (section 7).

## 2. Lines of code

**Method [measured].** `python3 port/loc.py`. Rust and BAML share `//` and `/* */` comments, so one classifier labels every line blank, comment or code. Rust `#[cfg(test)] mod … { … }` blocks in `src/` count as unit tests; BAML `ns_tests`/`ns_*_tests` namespaces under a module count as unit tests.

| Category | Rust files | Rust lines | Rust code | BAML files | BAML lines | BAML code | Code ratio |
|---|---|---|---|---|---|---|---|
| Library + CLI | 60 | 60,689 | 43,401 | 61 | 73,086 | 52,800 | **1.22×** |
| Unit tests | (30 with a test module) | 6,744 | 5,426 | 38 | 7,843 | 5,794 | **1.07×** |
| Integration tests | 12 | 25,558 | 19,551 | 13 | 27,552 | 20,206 | **1.03×** |
| Examples + benches | 3 | 439 | 222 | 3 | 826 | 495 | 2.23× |
| Rust std shim (`root.std`, incl. 43 tests) | n/a | n/a | n/a | 10 | 3,043 | 2,485 | n/a |
| Port-only corpus harness | n/a | n/a | n/a | 1 | 89 | 75 | n/a |
| **Total** | 105 | 93,430 | 68,600 | 126 | 112,439 | 81,855 | **1.19×** |

**Why the ratios come out this way.**
- **The logic maps nearly 1:1.** BAML classes, interfaces, closures and `match` cover what sasso uses from Rust.
- **What adds lines:**
  - 1,167 `// PORT:` notes (counted as comments, not code).
  - Data enums: each variant becomes its own class plus `implements` blocks.
  - Rust tuples become `root.std.TupleN` class literals (`root.std.Tuple2 { _0: a, _1: b }`).
  - Every cross-namespace name is fully qualified (`root.value.Value`); BAML has no imports.
  - `match` guards that need parenthesized sub-expressions are hoisted into `let`s before the `match` (W18).
  - Narrowing gaps force copies into locals.
  - Constants become zero-arg functions.
  - Split `impl` blocks become per-file interfaces with explicit `throws`.
- **What removes lines:** `?`, `.clone()`, `Rc::new`, `&`/`&mut` and lifetime noise disappear, and `Result<T, E>` plumbing becomes `throws`.
- **Examples + benches (2.23×).** Rust raw strings (`r#"…"#`) had to be spelled with escapes, one `+`-joined line per source line. BAML backtick strings dedent and trim, so they would change the input.
- **The std shim (2.5K code lines)** is what the Rust std gives for free:
  - tuples, `Cell`, and `StrBuf` (a rope-flattening string builder);
  - char classification;
  - f64 ↔ bits and Rust's float `Display` (verified against rustc output);
  - wrapping `u32`/`u64` arithmetic on `bigint`;
  - `std::path`, fs/env/process wrappers;
  - IEEE float comparisons.

## 3. Performance

**Runtime [measured 2026-09-26, `port/bench_runtime.py`].**
- Setup: Apple M5 Max; toolchain 20260923.a; Rust `cargo build --release` (`target/release/sasso`) vs the packed BAML `dist/sasso`.
- Same inputs, median wall time.
- Every output pair was checked to be identical.

| Input | Rust | BAML | Slower by |
|---|---|---|---|
| Startup (`--version`) | 2 ms | 134 ms | 62× |
| Tiny rule from stdin | 2 ms | 142 ms | 63× |
| `selector_lists.scss` (25 KB) | 3 ms | 659 ms | 209× |
| `extend_heavy.scss` (11 KB) | 6 ms | 1.20 s | 214× |
| Bootstrap 5.3.3 | 54 ms | 14.98 s | 279× |
| `large.scss` (9 KB, generated) | 9 ms | 3.49 s | 385× |
| `legacy_deprecations.scss` (0.8 KB) | 9 ms | 6.13 s | 669× |

- A single Bootstrap run on 2026-09-29 (20260925.a, load average ~9) took 12.1 s [measured].
- The ~130 ms floor is VM start-up plus loading the program.
- The worst ratio, `legacy_deprecations.scss`, is almost entirely diagnostic rendering: source snippets, line/column math and string building.

**Where the time goes [measured 2026-09-26, `baml run` profile of Bootstrap, ~32 s CPU under the profiler].**
- The expression evaluator itself: ~4.8 s.
- `String.from`, the generic value-to-string conversion: ~4.8 s. `Array.join` calls it for every element, even on `string[]`; the port now joins with native `+`, flattening every 2,048 pieces.
- `for (let x in arr)` loops: ~3.3 s. Each one allocates an iterator object and makes one call per element.
- `root.std.StrBuf`: ~1.5 s over 3.2M calls.
- `==` and `.length()`: 5.4M and 4.9M calls.

Structural costs of a faithful port:
- **Lookup tables are rebuilt on every call.** There are no globals, so constant tables (ryu, musl `pow`) are rebuilt per call. Formatting one number costs ~0.7 ms, of which ~0.4 ms is rebuilding the table.
- **`bigint` for 64-bit math.** FxHash, ryu and f64 bit patterns all go through it.
- **Copying Sass maps.** A Sass map insert copies the entry list: Rust's `Rc::make_mut` copies only when shared, while BAML has no refcount to check. This was measured as negligible, 42 ms on Bootstrap.

**Toolchain timings [measured 2026-09-26, `port/bench_toolchains.py`, `port/bench_baml_cache.py`].**
- Setup: rustc 1.95 with cargo-nextest 0.9 vs BAML 0.20.2-nightly; medians of 3–5 runs.
- "1 test" is `fxhash::tests::basic_map_roundtrips` in both.

| | Rust | BAML |
|---|---|---|
| check, cold | 1.45 s (`--all-targets`: 5.48 s) | 1.58 s |
| check, warm, no change | 0.03 s | 0.18 s |
| check, warm + one-line edit | 0.30 s (`--all-targets`: 0.42 s) | 2.27 s |
| 1 test, cold (build + run) | 7.88 s | 1.90 s |
| 1 test, warm, no change | 0.13 s | 0.41 s |
| 1 test, warm + one-line edit | 1.02 s | 2.62 s |
| `cargo build --release` / `baml pack`, cold | ~28 s, 2.4 MB binary | 1.94 s, 40 MB binary (49 MB on 20260925.a) |

- Cold, BAML is competitive, and it wins on "build one test binary", which has no LLVM step.
- Warm, BAML loses badly after any edit. `.baml/cache` is whole-project, so a one-line edit recompiles all 112K lines. A warm run after an edit is ~0.7 s *slower* than a cold one while it writes a new ~17 MB cache entry.
- Nothing is evicted. After the porting session, the project's `.baml/` held 1.5 GB of cache and 1.9 GB of run profiles.

**Caveats.**
- The machine was shared with up to 20 porter subagents during development. The 2026-09-26 measurements ran after porting had finished, and the 2026-09-29 run overlapped two verification agents.
- Memory was not measured.

## 4. Bugs in the BAML language, compiler, runtime and stdlib found during the migration

Every item was re-run as a minimal repro on 2026-09-29 on **0.20.2-nightly.20260925.a**, and on the port's 20260923.a where relevant. The full list, with 46 items, workarounds, issue searches and the porter claims that did not hold, is in [workarounds.md](workarounds.md); `W#` below refers to its numbering.
- **No issue or PR was filed.**
- Existing issues match only W1 (#4750), W10 (#4813), W12 (#4765) and W16 (#4967).

### 4a. Bugs

**B1. Silent wrong result: `0.0` and `-0.0` literals in one function collapse into one constant (W1).** Severity: high.
```baml
function neg_first(c: bool) -> float { if (c) { -0.0 } else { 0.0 } }
// 1.0 / neg_first(true) → Infinity   (expected -Infinity)
```
- [measured] Both nightlies.
- Existing issue: #4750 (open since 0.17.0).
- The port builds −0.0 from its bit pattern (`root.std.NEG_ZERO()`).

**B2. Miscompile: an always-throwing `catch` arm inside a null-narrowed branch makes a later null check fold to "always true" (W2).** Severity: high. The wrong branch runs.
```baml
function ld() -> int { 1 }
function h(cached: string?) -> string {
  if (cached == null) { let _y = ld() catch (e) { baml.errors.Io => { throw e; } }; }
  if (cached != null) { return "cached"; }     // warning[E0004] … always true
  "not cached"
}
// h(null) → "cached"
```
- [measured] Both nightlies. The callee doesn't even need to be able to throw.
- No existing issue.

**B3. Silent wrong result: `env.<field>` on a parameter or local named `env` reads BAML's builtin `env` reference (W3).** Severity: high.
- `function g(env: Env) -> string { let r = env.depth; `${r}` }` compiles with no diagnostic and returns `"Ref { name: \"depth\" }"` [measured].
- With a typed use, you get E0001 "found `baml.env.Ref`" instead.
- No existing issue.

**B4. Process abort: measuring a deep rope string overflows the native stack (W4).** Severity: high.
- `s = s + "ab"` ~102K times, then `s.length()`, gives `thread 'main' has overflowed its stack` and exit 134 [measured].
- Building the rope is fine; the first walk of it crashes. The walk is uncatchable.
- The port's `root.std.StrBuf` and `root.std.join` flatten periodically. Without that, Bootstrap's output would crash.

**B5. Compiler abort: `baml check`/`run` overflow the native stack on long call chains (W5).** Severity: high while it happens (no diagnostics, exit 134).
- Thresholds [measured]: a 131-function call chain, a 114-function cycle, 208 nested `if`s or 310 nested parentheses.
- The deep recursion is `throws` inference along the call graph: `throws never` everywhere avoids it.
- The port hit it 125 times while bodies were half-filled, and every porter then ran with `RUST_MIN_STACK=1073741824`.
- **The finished port no longer triggers it** [measured: check, run and all 1,107 tests pass with the variable unset].
- No existing issue.

**B6. Compiler panic "indirect calls require an explicit caller layout" (W6).** Severity: high (exit 101). An easy workaround exists.
```baml
class Box<T> { v: T }
function f(o: Box<string>?) -> int { let t = o ?? Box { v: "abc" }; t.v.length() }
```
- [measured] It panics at `crates/baml_compiler2_emit/src/emit.rs:2328` on both nightlies.
- It needs the join (via `??` or if/else) with an inferred-type-argument generic literal *and* a method call on a field.
- Workaround: spell the type arguments.
- No exact issue; related #4506.

**B7. Runtime crash: `.to_string()` on an interface-typed value type-checks, then fails with "VM internal error: interface … declares no method `to_string`" (W7).** Severity: high. [measured] Both nightlies. No existing issue.

**B8. Hang: `baml.sys.exec` with more than ~147 KB of `stdin` to a child that echoes it never returns, and `timeout_ms` doesn't fire (W8).** Severity: high. [measured] It is consistent with stdin being written in full before stdout is drained. No existing issue.

**B9. `baml.id` removed between two nightlies two days apart, with no replacement (W11).** Severity: high for existing code. It was the port's only compile error on 20260925.a. No existing issue.

**B10. String escapes: `\u{…}`, `\uXXXX`, `\x..` and unknown escapes like `\q` are kept verbatim with no diagnostic (W12).** Severity: high.
- `"\u{e9}".length()` is 6 [measured].
- #4765 (open) covers `\x`/`\u`, but not `\u{}` or the missing diagnostic.

**B11. Spurious E0003: a class literal with `{` or `}` inside a string field, in a `for (let x in [ … ])` header, is "unresolved" (W13).** Severity: medium.
- The porter reported it as "`root.std.Tuple3` unresolved". Minimising showed the trigger is the brace in the string [measured].
- No existing issue.

**B12. `obj.f = obj.f ^ x` on `bigint` fields gives "VM internal error: cannot apply binary operation" (W10).** Severity: high on 20260923.a. **Fixed on 20260925.a** [measured]. #4813 (open) is the same root cause and can probably be closed.

**B13. Parser and checker bugs with cheap workarounds:**
- Any `(` inside a `match` guard starts a lambda parameter list (W18).
- A statement-initial `[` after an `if`/`match` block is parsed as indexing (W19).
- `let s = E.A` gets a literal type without the enum's methods, and `E.A.m()` is E0003 (W21).
- `CLIENT.field.to_string()` is E0007 (W25).
- Interface default-method `throws` rules contradict each other: E0170 vs E0097 (W22).
- Narrowing gaps (W20):
  - no narrowing into the right operand of `&&`/`||`;
  - any closure capture drops narrowing for the whole region, including *before* the closure;
  - `-> never` calls such as `baml.sys.panic` don't narrow.
  Each one cost a local or a nested `if` at dozens of sites.

**B14. Stdlib and doc mismatches:**
- `baml.fs.read` reports invalid UTF-8 as `Io`, not the documented `ParseError` (W17).
- `Float.to_degrees` differs from Rust in the last bit (W33).
- `float.signum(NaN)`'s doc contradicts itself (W32).
- Every `baml check` on 20260925.a prints 11 E0146 warnings from builtin stdlib files (W31).

### 4b. Missing features that forced workarounds

- **VM call stack capped at 256 frames (W9).** This is the biggest remaining fidelity gap.
  - The port fails at 114 nested style rules and at 39 levels of Sass `@function` recursion. Rust manages ~2,100 and ~1,370 [measured].
  - The error is a catchable `baml.panics.StackOverflow`.
- **No globals (W25).**
  - `static`/`thread_local!` became a top-level `client X = root.std.Cell<T> { … }`, which works but is undocumented and process-wide.
  - `spawn` runs on real OS threads with no mutex or atomics, and shared counters lose updates (W23). As a result, `--jobs N` compiles sequentially.
  - `baml test` runs tests concurrently in one process, sharing that state (W24).
- **63-bit `int`, no f64 `to_bits`/`from_bits` (W26).** u64 hashing, ryu formatting and musl math run on `bigint` through `root.std.u64_*` helpers. IEEE bit casts are hand-written.
- **No reference identity (W36).** Replaced by `_id` tokens.
- **Float total order (W14)**, identity-based `includes`/`index_of` (W15) and panics escaping `catch_all` (W16). These are documented or intended, but each silently changes the meaning of line-by-line ported Rust. The port routes them through `root.std.feq/…`, `root.std.contains/position` and `catch (e) { let p: baml.panics.Panic => … }`.
- **Other gaps:**
  - No imports (W34).
  - No tuples, sets or non-string map keys (W35).
  - `uint8array` isn't iterable (W37).
  - No stat, realpath or cwd in `baml.fs` (W38).
  - `argv[1]` is the entry-function name (W29).
- **Performance primitives (W27):**
  - O(i) `String.at`/`slice`/`code_point_at`.
  - `Array.join` is 8.5× slower than a loop.
  - `for … in` is 5.8× slower than indexing.
- **Tooling:**
  - The `.baml/cache` is whole-project and never evicts (W28).
  - The agent-skill check blocks every command in agent environments after a toolchain switch (W30).
  - `baml pack -o dir/x` needs `dir/` to exist (W46).

## 5. Bugs in the original library (sasso)

**S1. `.sass` indented syntax: `has_top_level_using` skips a byte count over a char array, so a non-ASCII identifier starting with `u`/`U` in an `@include`/`+` line panics.** Severity: medium (a crash on valid input).
- `src/sass_parser.rs:1908` computes `for _ in 0..word.len().max(1) { sc.bump(); }`. `word.len()` is the UTF-8 byte length, but `sc` walks a `Vec<char>`.
- **[measured]** With the Rust release binary, `printf '=uñx\n  a: b\n.x\n  +uñx\n' > a.sass; sasso a.sass` fails with `thread 'main' panicked at src/sass_parser.rs:1278:33: index out of bounds: the len is 4 but the index is 4` (exit 134). So does `+m uñx`.
- The SCSS equivalent (`@include uñx;`) compiles fine.
- Mid-line, the same bug silently skips one extra character per extra UTF-8 byte. That could swallow a quote or parenthesis and misjudge whether `using` is at top level.
- The port keeps the bug on purpose (line-by-line). The BAML binary fails at the same spot with `uncaught throw: baml.panics.IndexOutOfBounds {index: 4, length: 4}` (exit 1).
- Found by the `.sass` parser subagent [agent claim, re-verified today]. `gh issue list -R momiji-rs/sasso` finds no existing issue. Not reported upstream.

No other upstream bugs were found. Every divergence found during verification was a porting error, and all were fixed.

## 6. Other comparisons

- **Agent effort [measured from transcripts].**
  - One orchestrating session plus 61 subagents, all Claude Opus 5.5. At most 20 subagents ran concurrently.
  - Units: 35 body-porting units, 10 unit-test units, 14 integration/examples units, and 2 verification agents for this report.
  - The port took about 6 hours of wall time (2026-09-25, 16:57–23:02 PDT).
  - Around 22:00 PDT, a session restart killed all 20 running subagents and wiped the scratchpad, including the upstream clone. The clone was moved into the project (`port/upstream/`), and the subagents were resumed from their transcripts with `SendMessage`.
- **Process that worked.**
  - **Declarations first, mechanically.** `port/skeleton.py` translated every Rust declaration into BAML before any body was written, with stub bodies. The project compiled from the start, so parallel porters could rely on each other's names and signatures without coordinating.
  - **One written contract.** `PORTING_GUIDE.md` fixed the mapping rules. Its append-only §15 collected every BAML surprise a porter hit, and later porters read it before starting.
  - **Fine-grained tooling for shared files.** Porters edited shared 8K-line files through `port/splice.py`, which replaces one function under a lock. `port/errors_for.py` filtered `baml check` output to the functions a unit owns.
  - **An oracle.** The Rust binary produced the expected outputs for the 982-case corpus and for every `compare.sh` run. The last porting bugs were found this way; they were not type errors.
- **Modelling Rust in BAML.**
  - Data enums map onto interface + variant classes and `match` class patterns.
  - Traits map onto interfaces.
  - Generics work, including generic classes in the std shim (`Tuple2<A, B>`, `Cell<T>`).
  - The hard parts were identity, globals and 64-bit integers:
    - `Rc::ptr_eq` → identity tokens.
    - `static`/`thread_local!` → a top-level `client` holding a `Cell`. It is process-wide, which forced `--jobs` to run sequentially.
    - `u64` → `bigint`.
- **Error handling.** `Result` + `?` maps well onto inferred `throws`, but there were three frictions:
  - Interface methods must spell out `throws`.
  - Default methods declared `throws never` break as soon as a callee can throw; `port/fix_throws.py` widened them.
  - Panics are only catchable as `baml.panics.Panic`, not by `catch_all`.
- **Strings.** Rust byte offsets became char offsets everywhere. `s.at(i)`, `slice` and `code_point_at` are O(i), so per-char loops go through `s.chars()`. `a + b` builds a rope that can overflow the native stack when measured (section 4), which is why the port has `StrBuf`.
- **Dev loop.**
  - `baml check` on 112K lines is 1.6 s cold.
  - `baml describe` answered most stdlib questions.
  - Two things cost real time: a syntax error anywhere hides every type error, and every CLI command refuses to run after a toolchain switch until `baml agent install`.
- **Compared with the sibling ports** (tomli, TOML, YAML, goldmark; same week, on a `baml-cli` 0.20.1 source build):
  - sasso is the largest (93K Rust lines vs goldmark's 18.5K Go lines) and ran on a newer nightly.
  - Several limitations also appear in the goldmark report: no escapes beyond the basic set, no globals, `&&`/`||` narrowing, 256-frame VM stack, the `let x = E.A` literal type, statement-initial `[` after a block, and identity-based `includes`.
  - Some bugs are new here:
    - catch-arm null-check folding;
    - the `env` capture;
    - the `??` generic-literal codegen panic;
    - `to_string` on interfaces;
    - the rope stack overflow;
    - the compiler's own stack overflow;
    - braces in `for` headers;
    - the `exec` stdin hang.

## 7. Open questions and caveats

- **Not an independent review.** The agent that ported the code wrote this report. The bug list was re-verified by two fresh subagents with minimal repros on 20260925.a (see `workarounds.md`), and that pass overturned 10 of the porters' claims (P1–P10 there). The port-level numbers come from the same session's scripts.
- **The 982-case corpus is extracted from upstream's own tests.** It shares their blind spots. Bootstrap is the only large real-world input that was compared, and no fuzzing was done.
- **Performance was measured once per configuration** (medians of 3–5 runs) on a machine that was sometimes loaded. Treat the ratios as ±20%. Memory was not measured.
- **Behavioural deviations kept on purpose.**
  - `--jobs N` runs one compile at a time, because process-wide `client` cells replace per-thread state.
  - **The 256-frame VM limit makes the port fail far earlier than Rust on deep inputs [measured, packed binary on 20260925.a].** No upstream test hits it, but real inputs could.
    - Nested style rules (`.a0 { .a1 { … b: c; } }`): the port handles 113 levels and fails at 114. Rust handles ~2,100 before its native stack overflows (abort, exit 134).
    - A recursive `@function f($n) { @if $n == 0 { @return 0; } @return f($n - 1) + 1; }`: the port handles `f(38)` and fails at `f(39)`. Rust handles ~1,370.
    - The failure is `uncaught throw: baml.panics.StackOverflow {message: "stack overflow"}` with a 256-frame traceback. Rust reports a native stack overflow instead, not a Sass error.
- **None of the BAML bugs are filed.** Issue searches are listed per item in `workarounds.md`. S1 is not reported upstream either.
- **`baml.id.new` disappeared between two nightlies two days apart** without a deprecation period. Ports pinned to a nightly should expect this kind of churn.
