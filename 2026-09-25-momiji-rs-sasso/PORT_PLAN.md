# sasso → BAML port: plan and checklist

Source: [momiji-rs/sasso @ `15c44de`](https://github.com/momiji-rs/sasso/tree/15c44de208f4fa6b4886d2b84d1db08af79851f6)
— a zero-dependency Rust SCSS→CSS compiler (library + CLI), ~67K lines in
`src/` (~59K non-test), plus ~30K lines of integration tests in `tests/`.

Rules for every porter: [`PORTING_GUIDE.md`](PORTING_GUIDE.md).

## Phases

- [x] **0. Foundation**
  - [x] `baml init`, `baml agent install` (skill in `.claude/skills/baml-core/`)
  - [x] Language survey (63-bit ints, no globals, no imports, 256-frame call
        limit, string escapes, rope strings, interface `throws` rules, …) → guide
  - [x] `root.std` shim for missing Rust std surface (`baml_src/ns_std/`):
        tuples, `Cell`, `StrBuf`, char/str helpers, f64 bits + Rust float
        formatting (verified against rustc output), wrapping ints, collections,
        `std::path`, `std::fs`/env/stdin/time
  - [x] `port/INVENTORY.md` (every Rust item + BAML target), enum registry
- [x] **1. Declaration skeleton** — `port/skeleton.py` generates every file
      with all types and signatures (bodies stubbed); the project compiles.
- [x] **2. Bodies** (all 35 units done; 0 stubs; 0 compile errors) — line-by-line port of every function body (36 work
      units below, run in parallel by subagents; `port/splice.py` +
      `port/errors_for.py` for shared files). Project compiles with 0 errors
      and 0 stubs left (`grep -r 'root.std.todo' baml_src` is empty).
- [x] **3. Unit tests** (274/274 Rust unit tests ported and passing; units T1–T9) — every `#[cfg(test)] mod …` → `ns_<mod>/…` test
      namespace; `baml test` passes.
- [x] **4. End to end** — corpus 982/982 byte-identical; Bootstrap 5.3 byte-identical (277 KB); CLI/error/sourcemap/.sass/@use comparisons identical (port/compare.sh) — `baml run main -- <args>` behaves like the Rust
      `sasso` CLI; CSS output compared byte-for-byte with the Rust build on a
      corpus; fix divergences.
- [x] **5. Integration tests & examples** (I01–I14: all 12 `tests/*.rs` crates incl. 465/465 parity cases; examples + benches runnable) — `tests/*.rs` → `baml_src/ns_tests/…`,
      `examples/*.rs` → `baml_src/ns_examples/…`; `benches/compile.rs` →
      a timing script.
- [x] **6. Packaging** — `baml pack main -o dist/sasso` (36 MB standalone executable); `README.md`; `baml fmt` applied.

Out of scope (not Rust library/CLI code, or FFI bindings BAML replaces with
`baml generate` SDKs): `wasm/`, `ffi/`, `napi/`, `nix/`, `spec/` (Python
harness), `bench/` (JS/shell harness), CI workflows.

## Checklist by directory (phase 2: bodies)

`src/` (namespace `root`)
- [x] `lib.rs` → `baml_src/lib.baml` — U34
- [x] `main.rs` → `baml_src/main.baml` — U18, U19
- [x] `arena.rs` → `ns_arena/arena.baml` — U35
- [x] `ast.rs` → `ns_ast/ast.baml` — U15
- [x] `ast_writer.rs` → `ns_ast_writer/ast_writer.baml` — U33
- [x] `deprecation.rs` → `ns_deprecation/deprecation.baml` — U10
- [x] `diag.rs` → `ns_diag/diag.baml` — U33
- [x] `emit.rs` → `ns_emit/emit.baml` — U32
- [x] `error.rs` → `ns_error/error.baml` — U10
- [x] `fxhash.rs` → `ns_fxhash/fxhash.baml` — U10
- [x] `host_fn.rs` → `ns_host_fn/host_fn.baml` — U28
- [x] `importer.rs` → `ns_importer/importer.baml` — U34
- [x] `musl_math.rs`, `musl_math_tables.rs` — U23
- [x] `pathstyle.rs` → `ns_pathstyle/pathstyle.baml` — U34
- [x] `ryu.rs`, `ryu_tables.rs` — U35
- [x] `sass_parser.rs` → `ns_sass_parser/sass_parser.baml` — U16
- [x] `scanner.rs` → `ns_scanner/scanner.baml` — U10
- [x] `sourcemap.rs` → `ns_sourcemap/sourcemap.baml` — U32
- [x] `value.rs` → `ns_value/value.baml` — U09, U10
- [x] `watch.rs` → `ns_watch/watch.baml` — U19

`src/builtins/` (namespace `root.builtins`)
- [x] `mod.rs`, `selector.rs` — U30
- [x] `list.rs`, `map.rs`, `meta.rs` — U31
- [x] `math.rs`, `string.rs` — U29
- [x] `color_ext.rs` — U22
- [x] `colorspace.rs`, `colorspace_matrices.rs` — U23
- [x] `color/mod.rs`, `color/deprecate.rs`, `color/removed.rs` — U22
- [x] `color/legacy.rs` — U20
- [x] `color/math.rs`, `color/modern.rs` — U21

`src/eval/` (namespace `root.eval`)
- [x] `mod.rs` — U01–U05
- [x] `scope.rs` — U05
- [x] `expr.rs` — U28
- [x] `binop.rs`, `meta.rs` — U26
- [x] `calc.rs`, `control_flow.rs` — U25
- [x] `at_rules.rs`, `plain_css.rs` — U27
- [x] `modules.rs` — U24

`src/parser/` (namespace `root.parser`)
- [x] `mod.rs` (+ `ast.rs`) — U15
- [x] `value.rs` — U13, U14
- [x] `at_rules.rs` — U11, U12
- [x] `control_flow.rs`, `statements.rs` — U12

`src/selector/` (namespace `root.selector`)
- [x] `mod.rs` — U06–U08
- [x] `parse.rs` — U08

`src/localtime/` (namespace `root.localtime`)
- [x] `mod.rs`, `civil.rs`, `posix.rs`, `sys.rs`, `tzif.rs` — U36

## Phase 2 work units

Rust line ranges are of the file in `$SASSO/src/`; a unit owns every item whose
definition starts in its range (test modules excluded — phase 3).

| unit | Rust | shared BAML file? |
|---|---|---|
| U01 | `eval/mod.rs` 1–2032 | yes |
| U02 | `eval/mod.rs` 2033–3735 | yes |
| U03 | `eval/mod.rs` 3736–5749 | yes |
| U04 | `eval/mod.rs` 5750–7688 | yes |
| U05 | `eval/mod.rs` 7689–8973, `eval/scope.rs` | yes / no |
| U06 | `selector/mod.rs` 1–1961 | yes |
| U07 | `selector/mod.rs` 1962–3953 | yes |
| U08 | `selector/mod.rs` 3954–5217, `selector/parse.rs` | yes / no |
| U09 | `value.rs` 1–1853 | yes |
| U10 | `value.rs` 1854–3347, `deprecation.rs`, `scanner.rs`, `error.rs`, `fxhash.rs` | yes / no |
| U11 | `parser/at_rules.rs` 1–1593 | yes |
| U12 | `parser/at_rules.rs` 1594–2870, `parser/control_flow.rs`, `parser/statements.rs` | yes / no |
| U13 | `parser/value.rs` 1–1461 | yes |
| U14 | `parser/value.rs` 1462–2543 | yes |
| U15 | `parser/mod.rs`, `ast.rs` | no |
| U16 | `sass_parser.rs` 1–1963 | no |
| U17 | *(merged into U16)* | |
| U18 | `main.rs` 1–1818 | yes |
| U19 | `main.rs` 1819–3420, `watch.rs` | yes / no |
| U20 | `builtins/color/legacy.rs` | no |
| U21 | `builtins/color/math.rs`, `builtins/color/modern.rs` | no |
| U22 | `builtins/color_ext.rs`, `builtins/color/{mod,deprecate,removed}.rs` | no |
| U23 | `builtins/colorspace.rs`, `builtins/colorspace_matrices.rs`, `musl_math.rs`, `musl_math_tables.rs` | no |
| U24 | `eval/modules.rs` | no |
| U25 | `eval/control_flow.rs`, `eval/calc.rs` | no |
| U26 | `eval/meta.rs`, `eval/binop.rs` | no |
| U27 | `eval/at_rules.rs`, `eval/plain_css.rs` | no |
| U28 | `eval/expr.rs`, `host_fn.rs` | no |
| U29 | `builtins/math.rs`, `builtins/string.rs` | no |
| U30 | `builtins/mod.rs`, `builtins/selector.rs` | no |
| U31 | `builtins/list.rs`, `builtins/map.rs`, `builtins/meta.rs` | no |
| U32 | `emit.rs`, `sourcemap.rs` | no |
| U33 | `diag.rs`, `ast_writer.rs` | no |
| U34 | `lib.rs`, `importer.rs`, `pathstyle.rs` | no |
| U35 | `arena.rs`, `ryu.rs`, `ryu_tables.rs` | no |
| U36 | `localtime/{mod,civil,posix,sys,tzif}.rs` | no |

## Known BAML constraints that shape the port

- `int` is 63-bit → u64 hashing / f64 bit patterns / ryu use `bigint`.
- No top-level mutable state → `thread_local!`/`static` caches dropped or
  moved into the evaluator.
- No `\u{…}` string escapes → literal characters or `root.std.chr_unchecked`.
- The VM caps call depth at 256 frames (`bex_vm/src/vm.rs` `MAX_FRAMES`) —
  deeply nested stylesheets / recursive Sass functions can hit it.
- `a + b` string concatenation builds ropes; `BexStr::char_count` recurses
  through unflattened ropes, so very deep ropes overflow the native stack →
  `root.std.StrBuf` flattens periodically.
- `s.at(i)` / `s.slice(…)` / `s.code_point_at(i)` are O(n) → per-char loops
  go through `s.chars()`.

## Phase 2 dispatch log

- Concurrency cap: 20 subagents.
- Running: (none — phase 2 complete)
- Queued: (none)
- Phase 3: done — T1 24, T2 30, T3 22, T4 32, T5 49, T6 36, T7 55, T8a 4, T8b 18, T9 4 (274 tests)
- Phase 5: done — I01 49, I02 57, I03 46, I04 43, I05 30, I06 40, I07 39, I08 21, I09 102, I10 59, I11 100, I12 96, I13 108 tests; I14 examples/benches. Multi-part files merged (parity.baml 465 tests).
- Done: U01–U36 (all)
- Session restart (2026-09-25 ~22:00): all 20 running porters were stopped and the
  scratchpad was wiped; upstream source re-cloned to `port/upstream/sasso`
  (durable), porters resumed from their transcripts.
- Perf notes for phase 4: source-map collection is O(n²) (SmCollector
  flattens + char-slices the StrBuf per record; StrBuf could track newline
  counts); ryu/musl tables of Tuple objects are rebuilt per call (~0.3ms);
  f64_to_bits/from_bits ~0.2ms each.
- Perf notes (cont.): `Scanner.rest()` copies the tail (7 call sites, one
  per statement in parser/statements) — potential O(n²) on large inputs.
