# goldmark → BAML port notes

Port of [yuin/goldmark](https://github.com/yuin/goldmark) (v2 API, commit `7117ae6`; source clone in `~/work-repos/goldmark-baml-port-src`) to BAML, using the `baml-cli` built from the `port-yuin-goldmark` worktree of BoundaryML/baml (`baml_language/target/fasttest/baml-cli`, wrapped by `bin/b`). The BAML compiler/runtime was not modified.

## Final summary

- **Every Go source file and test file is ported** (86 Go/C files → 83 `.baml` files, ~26k lines of BAML incl. ~5.5k lines of generated tables, from ~18.5k lines of Go). The only non-ported file is `_benchmark/cmark/cmark_benchmark.c` (a C benchmark of the cmark library, not goldmark code). Doc-only Go files (`package.go`, `text/package.go`, `extension/package.go`) have nothing to port.
- **Tests: 56 BAML tests; 51 pass, 5 fail.** The 5 failures are goldmark's wall-clock performance tests ("finish in < 5 s"); run individually, 2 of those 5 pass too (see below). Every functional test passes:
  - CommonMark spec: **652/652** examples.
  - All goldmark test-case files: extra 74/74, auto-heading-id 8/8, parse-delimiter-simple 133/133, table 14/14, footnote 5/5, definition list 6/6, linkify 21/21, strikethrough 5/5, task list 4/4, typographer 19/19, CJK 23/23.
- **Differential fuzzing against Go goldmark: 29,500 randomly mutated documents (spec + extension test inputs, all extensions enabled) render byte-identically to Go**, as do the 200 KB benchmark document and goldmark's README (`tools/difffuzz`, driven by `ns_dev.fuzz_dump_file`). No crashes in a further 12,000-input fuzz run.
- **Performance:** ~250× slower than Go (0.47 s vs 0.0019 s per conversion of the 200 KB benchmark document). This is why the performance tests fail: several goldmark inner loops rely on O(1) byte-slice views and SIMD `bytes.Index`, which BAML lacks.
- **How far the language gets today:** a faithful, file-by-file port of a real-world, pointer-heavy, byte-oriented parser works and is behaviorally exact. The main costs were (1) no reference identity, (2) no byte slices/views, (3) several narrowing gaps, (4) a handful of runtime/compiler crashes and silent escape-sequence bugs — all worked around. Details and repros below.

How to run: `bin/b test` (from this directory; all tests, ~35 s, the perf tests dominate) or `bin/b test -x "root::*Performance"` (51 tests, ~4 s). `bin/b run --function spec_report -- spec_report --from 1 --to 700` prints a per-example spec summary. See `PORTING_CONVENTIONS.md` for the porting rules used.

## Decisions

- Resumed from an earlier, abandoned attempt that had ported `util/` and `text/value.go`, `text/decoder.go` into this directory. Because `~/work-repos/goldmark` already existed, a fresh clone of the source was made in `~/work-repos/goldmark-baml-port-src` (same commit).
- Four extension groups (table; footnote; definition list + strikethrough + task list; linkify + typographer) were ported by parallel sub-agents in separate git worktrees (since removed; their branches `ext-*` remain in this repo) following `PORTING_CONVENTIONS.md`, then merged; the coordinator ported everything else and `extension.go`/`gfm.go`/`extension/ast_test.go`.
- Go packages map to BAML namespaces: `util` → `ns_util`, `text` → `ns_text`, `ast` → `ns_ast`, `parser` → `ns_parser`, `renderer` → `ns_renderer`, `renderer/html` → `ns_renderer/ns_html` (`root.renderer.html`), `extension` → `ns_extension`, `extension/ast` → `ns_extension/ns_ast`, `testutil` → `ns_testutil`, `fuzz` → `ns_fuzz`, `_tools` → `ns_tools`, `_benchmark` → `ns_benchmark`, root package tests → top level. `ns_dev` holds porting helpers (not goldmark code).
- Go `[]byte` → `uint8array`; `byte`/`rune` → `int`. Slicing copies, so code that relied on aliasing either threads offsets or copies.
- Go value structs (`Segment`, `Index`, values) → classes (references) treated as immutable.
- Go embedding (`BaseNode`/`BaseBlock`/`BaseInline`) → a `BaseNode` field `b` plus interface default methods (`Node`, `BlockNode requires Node`, `InlineNode requires Node`). Node classes implement only `base`/`kind`/`dump` (+ overrides).
- Node identity → `ast.same_node(a, b)` (see gap M1). `NodeKind`/`ContextKey` → strings.
- Multi-value returns → result classes or `T?`; variadic `opts ...X` → `opts: X[] = []`; functional options implementing several interfaces → one class with several `implements` blocks.
- Renderer generics: `Renderer[W]`, `Helper[W, C]`, `Option[C]`, `Extension[C]` keep `C` generic (`Option<C>`, `Helper<C extends FormatConfig>`), with `W` fixed to `util.BufWriter`; Go's reflection-based `getConfig` becomes a `FormatConfig` interface.
- Render/walk errors are dropped (`(WalkStatus, error)` → `WalkStatus`): all writers are in-memory `BufWriter`s that cannot fail.
- `goldmark_v1_attribute` build tag: BAML has no build tags, so the v1 attribute variant is compiled alongside with `_v1` suffixes (`parse_attributes_v1`, `text.multi_line_value_any`).
- Tests: one BAML `test` per Go test function; a helper returns the list of failures and the test asserts it is empty. `testutil.RecordingT` stands in for `testing.T`.
- `util.bytes_index` delegates to native `string.index_of` / `uint8array.index_of` (with byte-offset conversion and a VM fallback for invalid UTF-8), and `BlockReader.peek_line` caches by position: performance-only deviations with identical results.

## File mapping and status

Status: ✅ ported, 🟡 ported with documented deviations, ⚪ nothing to port / not applicable.

| Go file | BAML file | Status | Notes |
|---|---|---|---|
| util/util.go | ns_util/util.baml | ✅ | `io.Writer`/`bufio.Writer` → `BufWriter` interface + in-memory `Buffer`; byte tables verified against Go (3 latent table bugs from the earlier attempt fixed: `IsSpace` must exclude `\v \f`, URL table `0x7F`, UTF-8 length of `0xC0/0xC1`) |
| util/util_cjk.go | ns_util/util_cjk.baml | ✅ | |
| util/util_safe.go, util_unsafe.go | ns_util/util.baml (`bytes_to_string`, `string_to_bytes`) | ✅ | no unsafe aliasing in BAML; both build variants collapse to copies |
| util/html5entities.go | ns_util/html5entities.baml | ✅ | lazy map → lookup in generated decision tree |
| util/html5entities.gen.go | ns_util/html5entities.gen.baml | ✅ | generated by `tools/gen` (Go) as `match` trees (no package-level map constants) |
| util/unicode_case_folding.go, .gen.go | ns_util/unicode_case_folding.gen.baml | ✅ | generated |
| (Go stdlib `unicode`, `unicode/utf8`) | ns_util/unicode_tables.gen.baml, ns_util/utf8.baml | ✅ | the stdlib pieces goldmark uses (`IsPunct`, `IsSpace`, Hangul, …) |
| text/value.go | ns_text/value.baml | ✅ | |
| text/value_v1.go | ns_text/value_v1.baml | 🟡 | build-tag variant compiled unconditionally; `MultiLineValue.Any` → free function `multi_line_value_any`; `any` → `unknown` |
| text/decoder.go | ns_text/decoder.baml | ✅ | |
| text/reader.go | ns_text/reader.baml | 🟡 | regexp fallback across lines matches the remaining source (no streaming regex API); `peek_line` caches bytes |
| text/package.go | — | ⚪ | doc comment only |
| ast/ast.go | ns_ast/ast.baml | 🟡 | embedding → `BaseNode` + interface defaults; identity via `same_node`; `Children()` iterator → array; walker errors dropped; `N(...any)` → `n(node, (Node \| string)[])` |
| ast/block.go | ns_ast/block.baml | ✅ | enums + `*_string` functions |
| ast/inline.go | ns_ast/inline.baml | ✅ | |
| parser/parser.go | ns_parser/parser.baml | 🟡 | `Continue` → `do_continue`; `goto retry` → loops; `[256][]BlockParser` → arrays; `sync.Once` → flag; one Go slice-aliasing dependency emulated (see B8) |
| parser/delimiter.go | ns_parser/delimiter.baml | ✅ | `openersBottom` array → lazily-filled map |
| parser/emphasis.go | ns_parser/emphasis.baml | ✅ | |
| parser/paragraph.go | ns_parser/paragraph.baml | ✅ | |
| parser/blockquote.go | ns_parser/blockquote.baml | ✅ | |
| parser/thematic_break.go | ns_parser/thematic_break.baml | ✅ | |
| parser/code_block.go | ns_parser/code_block.baml | ✅ | `preserveLeadingTabInCodeBlock(*Segment)` returns the new segment |
| parser/fcode_block.go | ns_parser/fcode_block.baml | ✅ | |
| parser/atx_heading.go | ns_parser/atx_heading.baml | ✅ | |
| parser/setext_headings.go | ns_parser/setext_headings.baml | ✅ | |
| parser/list.go | ns_parser/list.baml | ✅ | |
| parser/list_item.go | ns_parser/list_item.baml | ✅ | |
| parser/html_block.go | ns_parser/html_block.baml | ✅ | `allowedBlockTags` map → `match`; `fallthrough` → shared tail |
| parser/html_scan.go | ns_parser/html_scan.baml | ✅ | |
| parser/raw_html.go | ns_parser/raw_html.baml | ✅ | |
| parser/link.go | ns_parser/link.baml | ✅ | `linkBottom` (nil / node / slice) → a stack class |
| parser/link_ref.go | ns_parser/link_ref.baml | ✅ | |
| parser/code_span.go | ns_parser/code_span.baml | ✅ | both custom `text.Value` implementations |
| parser/auto_link.go | ns_parser/auto_link.baml | ✅ | `[256]uint8` tables generated as range checks; offset-taking scanners avoid copies |
| parser/attribute.go | ns_parser/attribute.baml | ✅ | |
| parser/attribute_v1.go | ns_parser/attribute_v1.baml | 🟡 | build-tag variant, `_v1` suffixed |
| renderer/renderer.go | ns_renderer/renderer.baml | 🟡 | `W` fixed to `BufWriter`, `C` generic; reflection → `FormatConfig`; no errors |
| renderer/html/html.go | ns_renderer/ns_html/html.baml | 🟡 | package-level filters/strategies → functions; `textWriter` always uses the short path (same output) |
| extension/ast/table.go | ns_extension/ns_ast/table.baml | ✅ | |
| extension/ast/footnote.go | ns_extension/ns_ast/footnote.baml | ✅ | |
| extension/ast/definition_list.go | ns_extension/ns_ast/definition_list.baml | ✅ | |
| extension/ast/strikethrough.go | ns_extension/ns_ast/strikethrough.baml | ✅ | |
| extension/table.go | ns_extension/table.baml | ✅ | reproduces a Go slice-sharing quirk (paragraph/table line lists share storage) explicitly |
| extension/footnote.go | ns_extension/footnote.baml | 🟡 | renames for snake_case collisions (`newFootnoteParser` → `new_footnote_inline_parser`, `footnotes` → `FootnotesImpl`, …); context maps wrapped in classes |
| extension/definition_list.go | ns_extension/definition_list.baml | 🟡 | private fields renamed to avoid method-name clashes |
| extension/strikethrough.go | ns_extension/strikethrough.baml | ✅ | |
| extension/tasklist.go | ns_extension/tasklist.baml | ✅ | nil `IsInTightBlockFunc` falls back to the default instead of panicking |
| extension/linkify.go | ns_extension/linkify.baml | 🟡 | Go `regexp` → `baml.regex` (see G9); `\d` spelled `[0-9]` to keep RE2's ASCII semantics |
| extension/typographer.go | ns_extension/typographer.baml | 🟡 | substitution map (int keys) → array of entries; `unicode.IsLetter/IsDigit` for non-ASCII via `\p{L}`/`\p{Nd}` regexps; Go's never-called `CloseBlock` kept as a plain method (upstream bug: wrong signature) |
| extension/extension.go | ns_extension/extension.baml | ✅ | |
| extension/gfm.go | ns_extension/gfm.baml | ✅ | |
| extension/package.go | — | ⚪ | doc comment only |
| testutil/testutil.go | ns_testutil/testutil.baml | 🟡 | `recover()`-based isolation impossible (panics are uncatchable); options carry over between cases exactly like Go's reused struct |
| package.go | — | ⚪ | doc comment only |
| _tools/main.go | ns_tools/main.baml | ✅ | args passed explicitly; minimal `flag` port |
| _tools/gen-emb-structs.go | ns_tools/gen_emb_structs.baml | ✅ | output identical to Go's (modulo Go's random map order) |
| _tools/gen-unicode-case-folding-map.go | ns_tools/gen_unicode_case_folding_map.baml | ✅ | fetched JSON equals the committed Go JSON |
| _tools/gen-oss-fuzz-corpus.go | ns_tools/gen_oss_fuzz_corpus.baml | 🟡 | own ZIP writer + CRC-32 (no `archive/zip`); stored instead of deflated entries; `unzip -t` clean |
| _benchmark/cmark/goldmark_benchmark.go | ns_benchmark/goldmark_benchmark.baml | 🟡 | no pprof |
| _benchmark/go/benchmark_test.go | ns_benchmark/benchmark_test.baml | 🟡 | only the goldmark/v2 sub-benchmark (others are third-party Go libraries); no `testing.B` |
| _benchmark/cmark/cmark_benchmark.c | — | ⚪ | C benchmark of the cmark library; not goldmark code |

### Tests

| Go test file | BAML test file | Tests | Pass | Fail | Sub-cases |
|---|---|---|---|---|---|
| commonmark_test.go | commonmark_test.baml | 1 | 1 | 0 | 652/652 spec examples |
| ast_test.go | ast_test.baml | 6 | 6 | 0 | |
| cjk_test.go | cjk_test.baml | 2 | 2 | 0 | 23/23 cases |
| extra_test.go | extra_test.baml | 14 | 9 | 5 | extra.txt 74/74; the 5 failures are the performance tests |
| options_test.go | options_test.baml | 2 | 2 | 0 | 8/8, 133/133 |
| doc_test.go | doc_test.baml | 1 | 1 | 0 | README Go snippets run with `go run` |
| ast/ast_test.go | ns_ast/ast_test.baml | 1 | 1 | 0 | |
| text/reader_test.go | ns_text/reader_test.baml | 1 | 1 | 0 | |
| text/decoder_test.go | ns_text/decoder_test.baml | 3 | 3 | 0 | |
| parser/attribute_test.go | ns_parser/attribute_test.baml | 4 | 4 | 0 | |
| parser/attribute_v1_test.go | ns_parser/attribute_v1_test.baml | 1 | 1 | 0 | |
| extension/ast_test.go | ns_extension/ast_test.baml | 2 | 2 | 0 | |
| extension/table_test.go | ns_extension/table_test.baml | 6 | 6 | 0 | table.txt 14/14 |
| extension/footnote_test.go | ns_extension/footnote_test.baml | 2 | 2 | 0 | 5/5, 2/2 |
| extension/definition_list_test.go | ns_extension/definition_list_test.baml | 1 | 1 | 0 | 6/6 |
| extension/strikethrough_test.go | ns_extension/strikethrough_test.baml | 1 | 1 | 0 | 5/5 |
| extension/tasklist_test.go | ns_extension/tasklist_test.baml | 1 | 1 | 0 | 4/4 |
| extension/linkify_test.go | ns_extension/linkify_test.baml | 4 | 4 | 0 | 21/21 |
| extension/typographer_test.go | ns_extension/typographer_test.baml | 1 | 1 | 0 | 19/19 |
| fuzz/fuzz_test.go | ns_fuzz/fuzz_test.baml | 1 | 1 | 0 | spec seed corpus + 300 deterministic mutations |
| fuzz/oss_fuzz_test.go | ns_fuzz/oss_fuzz_test.baml | 1 | 1 | 0 | 200 mutations |
| testutil/testutil_test.go | ns_testutil/testutil_test.baml | — | — | — | compile-time conformance check (no test function in Go either) |
| _benchmark/go/benchmark_test.go | ns_benchmark/benchmark_test.baml | 1 | 1 | 0 | one iteration |
| **Total** | | **56** | **51** | **5** | |

Performance tests (goldmark requires < 5 s × `GOLDMARK_TEST_TIMEOUT_MULTIPLIER`, n = 50,000), measured one at a time: deep nested labels 4.9 s (pass), processing instructions 2.7 s (pass), declarations 6.1 s, comments 8.0 s, CDATA 22.1 s (fail). In a full parallel `bin/b test` run all five exceed 5 s. They pass with `GOLDMARK_TEST_TIMEOUT_MULTIPLIER=5` (all but CDATA) — the knob Go's CI uses for slow runners.

## BAML language / toolchain gaps, bugs and pain points

Severity: **crash** (compiler/VM internal error) > **wrong-result** > **spurious-compile-error** > **missing-error** > **missing-feature** > **pain-point**. Repros were run with the `port-yuin-goldmark` build of `baml-cli`.

### Bugs

B1. **crash (runtime) — `is`-narrowing to an interface dispatches through the wrong interface.**
```baml
interface Node { function kind(self) -> string throws never }
interface BlockNode requires Node { function has_blank(self) -> bool throws never }
function f(n: Node) -> bool {
    if (n is BlockNode) { return n.has_blank(); }   // type-checks
    false
}
```
Runtime: `VM internal error: interface 'user.Node' declares no method 'has_blank'`. Workaround: `match (n) { let b: BlockNode => b.has_blank(), _ => false }`.

B2. **crash (runtime) — reading an interface-declared field through an interface-typed value.**
```baml
interface Node { base: BaseNode }
class BaseNode { parent: Node? }
class H { base: BaseNode, implements Node {} }
// let n: Node = h; n.base.parent = p;
```
Runtime: `VM internal error: type error: expected map, got instance`. Workaround: expose the field via a method (`function base(self) -> BaseNode`).

B3. **crash (compiler panic) — assigning a bound method directly into a field.**
```baml
class Holder { f: ((x: int) -> int throws never)?, }
class G { function twice(self, x: int) -> int { x * 2 } }
function main() -> int { let g = G {}; let h = Holder { f: null }; h.f = g.twice; 0 }
```
`internal error: entered unreachable code: MakeBoundMethod must be handled in emit_rvalue_pull` (crates/baml_compiler2_emit/src/pull_semantics.rs:482). `let t = g.twice; h.f = t;` works.

B4. **wrong-result / missing-error — `\u` and `\x` escapes are silently kept verbatim.** `"�"`, `"\u{FFFD}"` and `"\x41"` evaluate to the literal backslash sequences (`5c7546464644`), with no diagnostic; only `\n \t \r \0 \\ \"` are escapes. This silently produced wrong HTML (NUL → `�` text) until caught by goldmark's tests. Workaround: put the literal character in the source.

B5. **spurious-compile-error — statement-initial `[` or unary `-` after a `}` continues the previous expression.**
```baml
function a(x: int?) -> int[] { if (x != null) { return [x]; } [] }   // `}[]` parsed as indexing → E0010
function b(x: int?) -> int { if (x != null) { return x; } -1 }        // parsed as `{…} - 1` → E0004 void - int
```
Workaround: `let none: int[] = []; none` / `return -1;`.

B6. **spurious-compile-error — matching an interface-typed value against an unrelated interface is rejected.** `match (ip) { let cb: CloseBlocker => … }` where `ip: InlineParser` → E0001 "expected InlineParser, found CloseBlocker" (Go's `ip.(CloseBlocker)`). Widening first works at runtime: `let u: unknown = ip; match (u) { let cb: CloseBlocker => … }`.

B7. **spurious-compile-error — `let` of an enum variant infers the literal type.** `let k = E.A; k = E.B;` → E0001. Needs `let k: E = E.A;`.

B8. **(port hazard, not a BAML bug) — Go slice aliasing is load-bearing.** goldmark's block loop reads `openedBlocks[lastIndex]` through a stale slice whose backing array was overwritten by a later `append` (this is how it detects that a paragraph was replaced). BAML arrays don't alias like that; spec example 216 failed until the port consulted the current list instead. The table extension has a similar dependency (emulated explicitly).

### Missing features

M1. **No reference identity.** `==` on class instances is deep structural equality (even cycle-aware), and there is no `===`/`same_instance`/object id. goldmark compares node pointers everywhere (`c != closer`, `last == parent.LastChild()`, `n == Nil`). Workaround: a scratch `mark` field on every node and `same_node(a, b)` that writes a sentinel into `a` and checks whether `b` sees it. `array.includes/index_of` on class instances are also structural.

M2. **No slices/views of `uint8array` (or strings).** `slice` copies. goldmark's `PeekLine` returns an O(1) subslice of the rest of the line and every inline parser attempt calls it, so the BAML port does O(line length) copying per attempt; this is the dominant cost in the failing performance tests. Related: `uint8array.index_of` has no `from` offset; there is no multi-byte `index_of` on `uint8array`; `for (let b in bytes)` is not supported (E0006) — index loops only.

M3. **No package-level `const`/`var` values.** Tables (`[256]uint8`), singletons (`IdentityDecoder`, `CommonMark`, `Nil`), attribute filters and kind/context-key counters become zero-argument functions (re-evaluated on every call) or generated `match`/range-check trees.

M4. **No char/byte literals.** Byte-level code is written with integer literals (`92 // '\\'`).

M5. **Map keys must be `string`** (no `int`/enum keys, E0067), and map-literal keys must be literals (`{ kind_table(): r }` does not parse). Workarounds: stringified keys, arrays of entries, assignment after `{}`.

M6. **Panics cannot be caught.** Go's test harness uses `recover()` to report a panicking case and continue; in BAML one panic aborts the whole test, so large case files can't isolate failures.

M7. **No raw string literals** (`#"…"#` now errors with E0098), backtick literals process escapes and dedent/trim (a trailing newline is dropped: `` `a\nb\n` `` → `"a\nb"`). Porting Go raw strings (regexps, expected HTML) needs escaping and care.

M8. **No build tags / conditional compilation** (goldmark's `goldmark_v1_attribute`).

M9. **Regex gaps:** no byte-slice API (strings only, code-point offsets → manual byte-offset conversion, lossy for invalid UTF-8); no streaming/reader matching; `baml.regex.new` with a constant pattern still `throws` (boilerplate `catch_all` + dummy regex); semantic differences from RE2: `\d \w \s` are Unicode-aware, `&&`/`--`/`~~` are set operators inside classes, `[[]` is rejected.

M10. **No `int.to_float()`** (only implicit conversion via mixed arithmetic); `float.to_int` is `itrunc()` and throws.

M11. **Missing stdlib pieces** hit during the port: temp directories (used `mktemp -d` via `baml.sys.exec`), `archive/zip` (wrote a stored-entry ZIP writer + CRC-32), profiling (no `pprof`/`--profile`), `fmt.Sprintf`-style formatting (template strings cover most uses), `unicode` category predicates (generated tables).

M12. **No variadic parameters**; defaulted parameters must be passed **by name** (`root.parser.new(options = [...])`, E0005), which makes Go's ubiquitous `New(opts...)` calls noisy.

M13. **JSON decoding matches field names exactly** (Go's `encoding/json` is case-insensitive); `@alias` doesn't apply to `baml.json`. The test harness names its fields `enableEscape`/`trim` to match the data.

### Narrowing gaps (spurious compile errors)

N1. **Narrowing doesn't flow into the right operand of `&&`/`||`:** `x != null && x.len() > 0` and `x == null || !x.ok()` fail (E0007/E0008). Extremely common in Go-style code; needs nested `if`s or helper functions. (Narrowing *inside the body* of `if (a && x != null)` works.)

N2. **No narrowing on fields:** `if (self.cob != null) { self.cob.write(b) }` fails; copy to a local first.

N3. **Loop-carried optional locals** lose narrowing after reassignment in the loop (`let d = self.parent(); … d = p;`).

### Pain points

P1. **Performance:** ~100 ns per simple VM loop iteration; the full parser is ~250× slower than Go. Native stdlib calls are fast (≈3–10 GB/s for `slice`/`index_of`/`from_utf8`), so the practical optimization is pushing work into stdlib calls — which requires string/byte conversions and offset bookkeeping.

P2. **Every interface method must declare `throws`**, and inferred throw sets propagate surprisingly (e.g. `String.from_code_points` throws, so a `BufWriter` implementation using it no longer conforms to `throws never`).

P3. **Reserved words** (`generator`, `is`, `continue`, `match`, `type`, …) can't be identifiers, and using one produces a cascade of unrelated "unexpected token" errors rather than one "reserved word" diagnostic.

P4. **Toolchain noise:** every `check`/`test`/`run` prints dozens of stdlib `E0146 unreachable code` warnings and `warning: code is unformatted; run baml fmt`; `baml run` prints values in a debug format (`\u{a0}` escapes, `user.dev.FuzzPair {…}`) rather than JSON, so data exchange with other tools had to go through files.

P5. **Nil-slice idiom:** Go's `nil`-vs-empty slice distinction and `len(nil) == 0` become `uint8array?` plus `?? root.util.new_bytes()` at many call sites.

P6. **snake_case collisions:** Go names that differ only in export case (`NewX`/`newX`, `footnotes`/`Footnotes`) collide after conversion to BAML naming and need ad-hoc renames.

P7. **A generic `Option<C>`-style functional-option API works**, but function types stored in fields, maps, arrays or aliases must spell out `throws` (e.g. `type ParseOption = (c: ParseConfig) -> void throws never`), which is noisy for callback-heavy Go APIs.

### Things that worked well

Interfaces with default methods and `requires` supertraits, generic classes/interfaces with bounds, closures capturing mutable locals, `match` on class/interface/union types, `unknown` + `match` as a stand-in for Go's `any`, optional chaining (`a?.b()?.c()`), bitwise ops, `baml.json`/`baml.fs`/`baml.sys.exec`/`baml.http.fetch`/`baml.regex`, seeded RNG, and fast native string/byte primitives. The compiler's diagnostics were generally precise, and the test runner (`-i`/`-x` selectors, per-test timing) was pleasant to use.
