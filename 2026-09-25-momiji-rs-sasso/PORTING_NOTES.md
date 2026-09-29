# Porting notes: momiji-rs/sasso (Rust) → BAML

## Setup

- **Source:** [momiji-rs/sasso @ `15c44de`](https://github.com/momiji-rs/sasso/tree/15c44de208f4fa6b4886d2b84d1db08af79851f6). It is a zero-dependency Rust SCSS → CSS compiler (library + `sasso` CLI) that targets byte-exact dart-sass 1.104.1 output. It has 60 files and ~61K lines in `src/`, plus ~26K lines of integration tests in `tests/`.
- **Toolchain:** `baml` wrapper 0.2.5, which selects toolchain `0.20.2-nightly.20260923.a`. The port was re-checked on 2026-09-29 with `0.20.2-nightly.20260925.a` (see *Results*).
- **How:** one Claude Code session (Claude Opus 5.5) planned the port and ran about 60 subagents in parallel, at most 20 at a time. The work took about 6 hours on 2026-09-25, including one session restart that stopped all running subagents; they were resumed from their transcripts.
- **Rules:** port line by line, keep the same file structure, and don't stop until it compiles and runs. Missing Rust dependencies (here, only the Rust std surface) go in as namespaces.
- **Reference:** the upstream checkout in `port/upstream/sasso` (not committed; see `README.md`) and its release build are the oracle for every comparison.

## Results

| | |
|---|---|
| Library + CLI (`src/`, 60 Rust files) | fully ported, 61 BAML files, 0 stubs, 0 compile errors |
| Rust unit tests (`#[cfg(test)]`) | **274/274 pass** |
| Rust integration tests (`tests/*.rs`, 12 crates) | **790/790 pass**, including all 465 `parity.rs` dart-sass cases. Those also pass in live-parity mode against the Rust binary. |
| Tests of the std shim (port-only) | 43/43 pass |
| Whole suite (`baml test`) | **1,107 passed, 0 failed**, 14 s wall time on 0.20.2-nightly.20260925.a |
| Examples / benches | ported and runnable |
| Output parity with the Rust `sasso` | **byte-identical** on the 982-case corpus (`port/corpus/`), on Bootstrap 5.3.3 (277 KB of CSS plus 8.7 KB of warnings), and on error diagnostics, source maps, `.sass` input and `@use`/`@forward`/`@import` graphs (`port/compare.sh`) |
| Standalone executable | `baml pack main -o dist/sasso` works; 49 MB on 20260925.a |

Re-checked on 2026-09-29 against 0.20.2-nightly.20260925.a:
- `baml check`: 0 errors and 17 warnings. 11 of them are located in builtin stdlib files; 6 are real but harmless warnings in the port.
- `baml test`: 1,107/1,107.
- `run_corpus`: 982/982.
- Packed `dist/sasso` on Bootstrap: CSS and stderr byte-identical to Rust.

Two source changes were made while writing up:
- That toolchain removed `baml.id.new`, so `root.std.fresh_id` now draws 63 random bits from `baml.random.SystemRandom` (one line).
- Five color functions still called BAML's `Float.to_degrees`, which differs from Rust's in the last bit. They now use the port's `f64_to_degrees`, which the math module already used.

All the checks above were re-run after both changes.

Not ported:
- The FFI and packaging wrappers (`wasm/`, `ffi/`, `napi/`, `nix/`): BAML generates its own Python/TypeScript SDKs (`baml generate`) instead.
- The JS/Python conformance and benchmark harnesses (`spec/`, `bench/`).
- CI workflows.

## Running

While the port was half-finished, `baml check` aborted with a native stack overflow unless `RUST_MIN_STACK=1073741824` was set. Some `// PORT:` comments and scripts still set it. The finished port needs no special settings on either nightly (see `baml-findings/workarounds.md` #5).

```bash
baml run main -- input.scss output.css
```

```bash
printf '.a { b: 1px + 2px; }' | baml run main -- --stdin --style=compressed
```

```bash
mkdir -p dist && baml pack main -o dist/sasso
```

`baml test` needs `dist/sasso` (the CLI tests spawn it) and `port/upstream/sasso` (the diagnostics and fixture tests read upstream's `tests/fixtures/`).

Opt-in parity mode, against dart-sass or the Rust binary:

```bash
SASSO_PARITY=1 SASS_BIN=port/upstream/sasso/target/release/sasso baml test -i 'root.tests.parity::*'
```

Other entry points:
- Corpus check: `baml run port_harness.run_corpus -- --dir port/corpus --limit 0 --verbose false`.
- Examples: `baml run examples.compile.main`.
- Benchmark: `baml run benches.compile.main`.
- CLI diff against Rust: `port/compare.sh <dir> <sasso args…>`.

## Layout

One Rust module = one BAML namespace = one `ns_*` directory:

| Rust | BAML |
|---|---|
| `src/lib.rs`, `src/main.rs` | `baml_src/lib.baml`, `baml_src/main.baml` (namespace `root`) |
| `src/value.rs` | `baml_src/ns_value/value.baml` (`root.value`) |
| `src/eval/mod.rs`, `src/eval/expr.rs` | `baml_src/ns_eval/mod.baml`, `baml_src/ns_eval/ns_expr/expr.baml` |
| `mod tests` in `src/value.rs` | `baml_src/ns_value/ns_tests/tests.baml` |
| `tests/parity.rs` | `baml_src/ns_tests/ns_parity/parity.baml` |
| `examples/compile.rs`, `benches/compile.rs` | `baml_src/ns_examples/ns_compile/…`, `baml_src/ns_benches/ns_compile/…` |
| *(Rust std)* | `baml_src/ns_std/` (`root.std`) |

`root.std` holds the Rust std surface that BAML lacks:
- tuples, `Cell`, and a rope-safe `StrBuf`;
- char/str helpers;
- f64 bit casts and Rust float formatting;
- wrapping integer arithmetic;
- `std::path`;
- fs, env and process shims.

Every Rust item, function body, comment and test has a counterpart in the same place, with the same name, in the same order. Wherever BAML forced a different spelling, a `// PORT:` note says so; there are 1,167 of them.

## How the port was made

The plan and checklist are in `PORT_PLAN.md`. `PORTING_GUIDE.md` is the translation contract every subagent followed; its §15 lists the BAML behaviours discovered along the way.

1. **Foundation.** `baml init` and `baml agent install`. A language survey (63-bit ints, no globals, no imports, the 256-frame call limit, string escapes, rope strings, interface `throws` rules). The `root.std` shim. `port/INVENTORY.md`, which lists every Rust item with its BAML target.
2. **Declaration skeleton.** `port/skeleton.py` mechanically translated every Rust item's declaration, with bodies stubbed, so that modules written in parallel agree on names, types and signatures:
   - types;
   - enums → interface plus one class per variant;
   - traits → interfaces;
   - split `impl` blocks → per-file interfaces;
   - signatures.
3. **Bodies.** 35 work units (`port/units/U*.md`) filled in the bodies line by line, in parallel. `port/splice.py` handled locked function replacement in shared files, and `port/errors_for.py` gave per-function diagnostics.
4. **Tests.** 10 units ported the 274 unit tests. 14 units ported the 12 integration-test crates, the examples and the benchmark.
5. **Verification against the Rust binary.** `port/make_corpus.py` extracted 982 cases from upstream's tests, with the Rust binary's output as the expected result. `port_harness.run_corpus` runs them in-process, and `port/compare.sh` diffs whole CLI runs (stdout, stderr and exit code).

Key translation decisions (full rules in `PORTING_GUIDE.md`):

- **Enums.**
  - C-like enums → BAML `enum` plus an `<Enum>Methods` interface.
  - Data enums → an interface plus one `<Enum>_<Variant>` class per variant.
  - `match` on variants → class patterns.
- **Split `impl` blocks** → a `<Type><Module>` interface per file, implemented by the type.
- **Errors.** `Result<T, E>` → `T` with `throws E`. `?` → propagation. `panic!` → `baml.sys.panic`.
- **Integers.** Rust `u64`/`i64` math that can exceed 63 bits (FxHash, ryu, f64 bit patterns) → `bigint`.
- **Strings.** Byte offsets → char offsets; per-char loops go through `s.chars()`. Rust `String` building → `root.std.StrBuf`, which flattens the rope periodically.
- **Constants** → zero-arg functions.
- **Mutable statics and `thread_local!`** → a top-level `client X = root.std.Cell<T> { … }`, which serves as a process-wide cell. Because of this, the CLI's `--jobs` worker pool runs one compile at a time (`// PORT:` in `compile_all`).
- **`Rc::ptr_eq`** → an identity token field (`root.std.fresh_id()`).
- **RAII guards** → explicit `drop()` in a `defer`.

## Lines of code

Measured with `python3 port/loc.py`. Both languages share `//` and `/* */` comment syntax, so the same rules classify every line as blank, comment or code.

| Category | Rust files | Rust lines | Rust code | BAML files | BAML lines | BAML code | Code ratio |
|---|---|---|---|---|---|---|---|
| Library + CLI | 60 | 60,689 | 43,401 | 61 | 73,086 | 52,800 | 1.22× |
| Unit tests | (30 files with a test module) | 6,744 | 5,426 | 38 | 7,843 | 5,794 | 1.07× |
| Integration tests | 12 | 25,558 | 19,551 | 13 | 27,552 | 20,206 | 1.03× |
| Examples + benches | 3 | 439 | 222 | 3 | 826 | 495 | 2.23× |
| Rust std shim (`root.std`) | n/a | n/a | n/a | 10 | 3,043 | 2,485 | n/a |
| Port-only harness | n/a | n/a | n/a | 1 | 89 | 75 | n/a |
| **Total** | 105 | 93,430 | 68,600 | 126 | 112,439 | 81,855 | 1.19× |

## Performance

The port is interpreted bytecode; Rust is optimized native code. Measured on 2026-09-26 with `port/bench_runtime.py`:
- Hardware and toolchain: Apple M5 Max, 0.20.2-nightly.20260923.a.
- Rust `target/release/sasso` vs the packed `dist/sasso`, on the same inputs.
- Median wall time; every output was checked to be identical.

| Input | Rust | BAML | Slower by |
|---|---|---|---|
| Startup (`--version`) | 2 ms | 134 ms | 62× |
| Tiny rule from stdin | 2 ms | 142 ms | 63× |
| `selector_lists.scss` (25 KB) | 3 ms | 659 ms | 209× |
| `extend_heavy.scss` (11 KB) | 6 ms | 1.20 s | 214× |
| Bootstrap 5.3.3 | 54 ms | 14.98 s | 279× |
| `large.scss` (9 KB, generated) | 9 ms | 3.49 s | 385× |
| `legacy_deprecations.scss` (0.8 KB) | 9 ms | 6.13 s | 669× |

A single Bootstrap run on 2026-09-29 with 0.20.2-nightly.20260925.a took 12.1 s, under load average ~9.

Where the time goes, from `baml run` profiles of Bootstrap (~32 s CPU under the profiler):
- the expression evaluator itself: ~4.8 s;
- generic `String.from` value-to-string conversion, which `Array.join` calls per element, even for `string[]`: ~4.8 s;
- `for (let x in arr)` iterator objects: ~3.3 s;
- `StrBuf`, a BAML-level string builder: ~1.5 s.

Also contributing:
- O(n) `String.at`/`slice`/`code_point_at`.
- Lookup tables (ryu, musl math) rebuilt on every call, because there are no globals.
- `bigint` for 64-bit math.

## Toolchain timings: `cargo` vs `baml`

Same machine; rustc 1.95 with cargo-nextest 0.9 vs BAML 0.20.2-nightly. Medians of 3–5 runs, from `port/bench_toolchains.py` and `port/bench_baml_cache.py`.

"1 test" means `fxhash::tests::basic_map_roundtrips` in both:
- Rust: `cargo nextest run --lib`, a debug LLVM build of the unit-test binary.
- BAML: `baml test -i root.fxhash.tests::basic_map_roundtrips`.

| | Rust | BAML |
|---|---|---|
| check, cold (no `target/`, no `.baml/`) | 1.45 s (`--all-targets`: 5.48 s) | 1.58 s |
| check, warm, nothing changed | 0.03 s | 0.18 s |
| check, warm + one-line edit | 0.30 s (`--all-targets`: 0.42 s) | 2.27 s |
| 1 test, cold (build + run) | 7.88 s | 1.90 s |
| 1 test, warm, nothing changed | 0.13 s | 0.41 s |
| 1 test, warm + one-line edit | 1.02 s | 2.62 s |
| release binary / `baml pack`, cold | ~28 s, 2.4 MB | 1.94 s, 40 MB |

- `baml check` covers the whole project (tests, examples and benches included), so `cargo check --all-targets` is the closer comparison.
- The BAML cache (`.baml/cache/`) is whole-project. Any content change recompiles everything.
- After an edit, a warm run is ~0.7 s *slower* than a cold one while it writes a new ~17 MB cache entry.
- Nothing in `.baml/` is evicted. After the porting session the project's `.baml/` held 1.5 GB of cache and 1.9 GB of profiles.

## BAML bugs and limitations

See [baml-findings/report.md](baml-findings/report.md) (post-mortem) and [baml-findings/workarounds.md](baml-findings/workarounds.md) (every workaround, with repros re-verified on 0.20.2-nightly.20260925.a).
