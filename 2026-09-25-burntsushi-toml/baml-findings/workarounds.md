# BurntSushi/toml → BAML: every BAML bug, limitation and workaround the porting agent hit

Written 2026-09-28. This is a companion to [report.md](report.md) (the post-mortem). That report's section 4 was used as a starting checklist; everything here was re-derived from the sources below, and every bug-class item was re-run.

**Sources swept**
- Main session: `<local>/transcripts/port-burntsushi-toml/d7293e96-66bd-4d4e-a5d8-dea701c02644.jsonl` (2026-09-26 19:13–21:24 UTC; no subagent transcripts exist). It is cited below as **T2 `[jsonl line, UTC time]`**.
- Aborted first attempt: `<local>/transcripts/port-toml-rs/e1a3c08f-2446-490d-a3c1-04749bd61001.jsonl` (2026-09-26 00:07–00:31 UTC). It is cited as **T1 `[line, time]`**. The other transcripts that mention `work-repos/toml-baml` (the Orca launcher session in `<local>/transcripts/coordinator/1c8504f4…`, and the tomli and yaml port sessions) only name the path, so they have nothing port-specific.
- Port: `<local>/work-repos/toml-baml` (9 commits `06eef27`..`be6de94`), its `PORTING_NOTES.md`, the `GAPS.scratch.md` left by T1 (deleted in `98294c3`), a grep of every `.baml` source for workaround comments, and every `python3 -`/`sed -i` edit script the agent ran (28 scripts, most applied before the first commit, so they appear only in the transcript and not in `git log -p`).

**Verification**
- Binary: the **release** `baml-cli` at `e215c3de2d` (`<local>/baml-worktrees/port-hukkin-tomli/baml_language/target/release/baml-cli`, the only release build; `canary` is still `e215c3de2d`), run with `BAML_AGENT_SKILL_CHECK=off`.
- Repro projects: `<local>/report-scratch/toml-RUhS/rp/rNN_*`. Each has its own `baml.toml`, and `rp/b` is the wrapper. Sources that need backslash escapes are written by `rp/mk.py`, which expands `@BS@` to a real backslash, because the tool harness rewrites a literal backslash-u sequence in command text before it reaches the shell (see W10).
- **VERIFIED** means it still reproduces on the release CLI. **NOT REPRODUCED** means the agent got it wrong. **UNVERIFIED** means it was not re-run (feature gaps mostly).

**GitHub issues:** `gh issue list -R BoundaryML/baml --search … --state all` was run for every item with several phrasings. The only related issue found is **#4765**, and it was wrongly closed (see W10/W11). Nothing else is filed.

## Summary table

Severity: **High** = wrong behavior or blocked tests; **Med** = frequent friction or silent hazard; **Low** = cosmetic or rare.
Categories: (a) compiler/type-checker; (b) runtime/VM; (c) stdlib; (d) missing language feature; (e) performance; (f) tooling/CLI/test runner; (g) docs.

| # | Title | Cat. | Severity | Verified? | Issue | Workaround in port |
|---|---|---|---|---|---|---|
| W1 | `self.m()` inside `implements I { function m… }` calls the interface impl itself → infinite recursion | a/b | High | VERIFIED | none | Renamed inherent method to `error_string` (`error.baml:66`) |
| W2 | Type-pattern `match` against a container of a recursive alias costs ~0.37 ms per test | e | High | VERIFIED | none | None (post-mortem finding, not hit consciously) |
| W3 | VM hard call-depth limit `MAX_FRAMES = 256` | b | High | VERIFIED | none | None; 4 `TestMaxDepth` cases fail |
| W4 | `&&` does not narrow its right operand | a | Med | VERIFIED | none | Nested `if`s (≥6 sites) |
| W5 | Calling a `-> never` function doesn't narrow; `{ die(); }` is typed `void` | a | Med | VERIFIED | none | `x ?? go_panic(..)`, `throw` inline, bare-expression catch arms |
| W6 | Matching a `string` against literal patterns narrows it to a literal union with no `string` methods | a | Med | VERIFIED | none | Hoist `v.length()` above the `match` (`ns_go/time.baml:232`) |
| W7 | Flow narrowing to literal types ignores an explicit `let x: int` annotation → `E0004 cannot order int and 2 \| 3` | a | Med | VERIFIED | none | Helper functions `first_size`/`accept_lo`/`accept_hi` (`ns_go/utf8.baml:72–95`) |
| W8 | `self.field != null` does not narrow `self.field` | a | Low | VERIFIED | none | Local copy (`error.baml:121`) |
| W9 | Bound method used without `()` type-checks as a value into `unknown`, fails at runtime | a | Med | VERIFIED | none | Fixed the call site (`encode.baml:173`) |
| W10 | `\xNN`, `\uNNNN`, `\u{…}` escapes kept literally, silently (in files and `run -e`) | a | High | VERIFIED | #4765 (closed in error) | String concatenation, pasted literal `�`, `string.from_code_points([127])` |
| W11 | A `test` whose body evaluates to `false` passes (discovered while checking #4765) | f | High | VERIFIED | none | n/a (not hit by agent) |
| W12 | `testset` collector that panics reports only `(failed to expand)`, even with `-vv`/`--log debug` | f | Med | VERIFIED | none | Re-ran the collector expression with `baml run -e` |
| W13 | `float.to_string()` never uses exponent notation (`1e300` → 303 chars); ±Inf prints `Infinity` | c | Low | VERIFIED | none | Hand-written Go `FormatFloat('g')` (`ns_go/strconv.baml:187`) |
| W14 | Map literal as a `match` arm body parses as a block (E0010 cascade); `_ => {}` in value position is `void` | a/f | Med | VERIFIED | none | Parenthesize `({ … })`; typed empty-map temp |
| W15 | Bad diagnostics for `test` or `self` as a parameter name (cascade of `E0010 unexpected token`) | f | Low | VERIFIED | none | Renamed to `tt`, `md` |
| W16 | Methods only inside the class body; `function M.f(self)` gives a misleading "`M` defined 2 times"; field and method can't share a name (E0012) | d/f | Med | VERIFIED | none | ~14 `md_*` free functions in `decode.baml`; field renamed `keys_list` |
| W17 | `throws` rules are asymmetric and inconsistent (E0151/E0170 must declare; E0097 *error* for restating the interface's `throws unknown` but *warning* elsewhere; E0120 can't widen) | a | Med | VERIFIED | none | `throws never` on every function type; widened interface to `throws root.Panic`; dropped declared throws |
| W18 | `to_string` cannot be a plain method (E0140) | d | Low | VERIFIED | none | ~20 `implements baml.ToString` blocks |
| W19 | `int` is 63-bit; no sized/unsigned ints, no float32 | d | Med | VERIFIED (E0150) | none | TOML ints as `bigint`; `go.Int8…Uint64/Float32` wrapper classes |
| W20 | No `bigint → float` (or explicit `int → float`) conversion; `0.0 + 5n` is E0004 (reported twice) | c | Low | VERIFIED | none | `float.parse(b.to_string())` (`ns_cmd/tomlv.baml:40`) |
| W21 | NaN sign unobservable; `signum` docs say NaN's sign counts but `(-nan).signum()` is `1.0`; no `to_bits`/`signbit` | c/g | Low | VERIFIED | none | `go.signbit` returns false for NaN; `-nan` round-trips as `nan` |
| W22 | No reflective construction/setters; `from_json<T>` can't put NaN/±Inf into a class `float` field | d/c | High | VERIFIED (NaN part) | none | Whole decoder builds a JSON image; `TestDecodeSignbit` fails |
| W23 | Container type patterns are invariant: `let a: unknown[]` doesn't match `int[]` | d | Med | VERIFIED | none | `unreflect` + copy into `unknown[]` (`go_value.baml:120`) |
| W24 | No struct tags / user attributes (`reflect.Meta.other` only for runtime classes) | d | Med | UNVERIFIED | none | Tags stuffed into `@description("toml:\"…\"")` |
| W25 | Assorted Go features absent: embedded fields, methods on non-class types, pointers, `[N]T`, non-string map keys, package vars, varargs/printf, labelled `continue` (VERIFIED parse error), `goto` | d | Med | partly | none | Wrapper classes, pseudo-tags, zero-arg functions, flags; 10 test cases `UNPORTABLE` |
| W26 | Strings are Unicode-only (no invalid UTF-8; `from_utf8` throws, no lossy mode) | d/c | Med | VERIFIED (no lossy API) | none | Lexer on `int[]` bytes + hand-written UTF-8 codec (`ns_go/utf8.baml`, 198 lines) |
| W27 | No stdin read-all; `baml.io.input` can't tell EOF from an empty line | c | Low | VERIFIED | none | `baml.fs.open("/dev/stdin")` (`ns_cmd/common.baml:5`) |
| W28 | No temp-file API, no file embedding | c/d | Low | VERIFIED (describe) | none | Fixed `/tmp` path; tests read `testdata/` relative to cwd |
| W29 | CLI refuses to run without the "agent skill" | f | Low | VERIFIED | none | `BAML_AGENT_SKILL_CHECK=off` in `.bin/b` |
| W30 | `baml run` always prints the return value (`-q` doesn't suppress it); list params only via `--json-args` | f | Low | VERIFIED | none | CLI ports print a trailing `null` |
| W31 | Test runner prints PASS/FAIL lines only at the end of the run (non-TTY) | f | Med | VERIFIED | none | Bisecting by running groups one at a time |
| W32 | Test selector semantics: plain = substring, `*` = glob anchored at `root::`; "no tests selected" gives no hint | f | Low | VERIFIED (behavior as documented) | none | Agent concluded globs don't exist (see M4) |
| W33 | `baml check` on any project prints 11 `E0146 unreachable code` warnings from the builtin stdlib, with no `<builtin>` prefix | f | Low | VERIFIED | none | Agent grepped them out |
| W34 | General slowness (interpreter, debug compile, O(n³) key bookkeeping) | e | High | VERIFIED (via post-mortem numbers) | none | Fast-path glob matcher; accepted timeouts |
| W35 | `baml run --function cmd.x -- cmd.x` → "unrecognized subcommand"; bare-name form required | f | Low | VERIFIED | none | `[scripts]` with `--function cmd.x -- x` |
| W36 | `Xoshiro256PlusPlus.new(seed?)` is `throws never` but panics on a seed of fewer than 32 bytes | c | Low | VERIFIED | none | 32-byte seed literal (`fuzz_test.baml:131`) |
| W37 | No package dependencies between user packages | d | Low | UNVERIFIED | none | `cmd/*`, `_example` as namespaces inside the library |
| W38 | No benchmark, fuzz or example-test harness | d | Low | n/a | none | `bench_*(n)` functions, seeded PRNG mutations, output asserts |
| W39 | Defaulted parameters must be passed by name (E0005) | d | Low | VERIFIED | none | `new(seed = …)` |

Agent mistakes (details in the last section):
- M1: "`\u` works under `run -e`" was a harness artifact.
- M2: "panics are uncatchable" is false.
- M3: "no `defer`" is false.
- M4: "no glob in selectors" is false.
- M5: a phantom "hang" (an agent timeout wrapper and a non-matching `-x`).
- M6: "generic methods can't be called from another file" is false.
- M7: trailing spaces were stripped by the Write tool, not BAML.
- M8: minor syntax/API guesses.

## Detailed entries

### W1. Interface impl calling a same-named inherent method recurses into itself — (a/b) High

- **Observed:** the first full test run had 454 passed and 476 failed; every invalid-TOML test died with `baml.panics.StackOverflow { message: "stack overflow" }`, with a traceback repeating `File "baml_src/error.baml", line 136, in user.<(user.ParseError as user.TomlError)>.error` (T2 [1130, 19:38:35]).
- **Repro** (`rp/r01_iface_self`):
  ```baml
  interface Err { function error(self) -> string throws never; }
  class E {
      msg: string,
      function error(self) -> string { self.msg }
      implements Err { function error(self) -> string throws never { self.error() } }
  }
  function main() -> string { let e: Err = E { msg: "hi" }; e.error() }  // StackOverflow
  ```
- **Workaround:** renamed the inherent method to `error_string` (`error.baml:66`, callers at `:82`), commit `951540c`. That is Go's `func (pe ParseError) Error()` split into two names.
- **Cost:** 3 lines, but about 2.5 minutes of diagnosis and one wasted full-suite run. Without the rename, every error path in the library would loop forever. The compiler gives no hint that `self.error()` is ambiguous.
- **Status:** VERIFIED on release. No issue.

### W2. Pathologically slow `match` against a recursive-alias container — (e) High

- **Observed:** not diagnosed by the agent. It only saw that decode and encode tests took 10–17 s each on debug (T2 [1198, 19:41:11]). The post-mortem traced about 97% of decode time to `Parser.set_value`, which runs `match (ctx) { let t: map<string, Any>[] => …, let t: map<string, Any> => … }` for every key (`parse.baml:515/518`, alias at `parse.baml:14`).
- **Repro** (`rp/r24_match_perf`, release): `type J = string | int | J[] | map<string, J> | map<string, J>[]`. Testing a `J` value against `let m: map<string, J>[]` costs **366,795 ns** per test. The 4-arm alias `K` against `K[]` costs **14,584 ns**. A non-recursive `int | string` against `int` costs **26 ns**.
- **Workaround:** none in the port. Swapping the two arms gives a 5–13× speedup on parse (post-mortem, section 3).
- **Cost:** most of the ~2,000× decode slowdown versus Go.
- **Status:** VERIFIED. No issue.

### W3. VM `MAX_FRAMES = 256` — (b) High

- **Observed:** `TestMaxDepth::#05–#08` fail with `baml.panics.StackOverflow`. The agent found `bex_vm/src/vm.rs:118: pub const MAX_FRAMES: usize = 256` (T2 [1483, 20:19:01]).
- **Repro** (`rp/r09_frames`): `function depth(n: int) -> int { if (n == 0) { return 0; } 1 + depth(n - 1) }`. `depth(250)` returns 250; `depth(260)` gives `StackOverflow`.
- **Workaround:** none. The recursive-descent parser uses about 2–3 frames per nesting level, so Go's default `MaxDepth(128)` is unreachable. The panic *is* catchable (`catch (e) { baml.panics.StackOverflow => … }`, verified in `rp/r34_panic_catch`), which could at least turn it into an error, but the agent believed panics were uncatchable (M2).
- **Cost:** 4 failing tests; fidelity lost for deeply nested documents.
- **Status:** VERIFIED. No issue.

### W4. `&&` does not narrow its right-hand side — (a) Med

- **Observed:** `E0007: type 'KeyInfo | null' has no member 'pos'` (T2 [865, 19:31:17]). The same bug later showed a different message, `E0004: cannot order 'int | null' and 'int' with '<'` (`runner.baml:706`, T2 [1290, 19:47:46]).
- **Repro** (`rp/r02_and_narrow`): `function f(s: string?) -> bool { s != null && s.length() > 0 }` gives `E0007 type 'string | null' has no member 'length'`.
- **Workaround:** nested `if`s, as in:
  - `go_value.baml:384`
  - `ns_tomltest/runner.baml:706`
  - the `ki != null && ki.pos.line > 0` and `d != null && d.includes(…)` sites (edit scripts T2 [881] and [889])
  - `value_kind_is_struct: if (vt == null) { false } else { … }`
- **Cost:** about 6 sites, each +3 lines; Go's short-circuit idiom is lost.
- **Status:** VERIFIED. No issue.

### W5. `never`-returning calls don't narrow; a block ending in one is `void` — (a) Med

- **Observed:** `E0001 mismatched types` and `E0007` after `if (x == null) { go_panic(…) }` and `enc_panic(…)` (T2 [881, 19:31:46], [1034, 19:36:46]). There was also `E0007: type 'void | baml.fs.File' has no member 'bytes'` from a catch arm `_ => { log_fatal("…"); }` (T2 [1581, 20:21:18]).
- **Repro** (`rp/r03_never_narrow`, `rp/r03b_never_block`):
  ```baml
  function die() -> never { throw "x" }
  function f(s: string?) -> int { if (s == null) { die(); } s.length() }   // E0007
  function g(s: string?) -> int { if (s == null) { die() } s.length() }    // E0007 even without ';'
  function h(s: string?) -> int { if (s == null) { throw "x" } s.length() } // OK
  let t: string = s ?? { die(); };                                           // E0001 (block is void)
  ```
- **Workaround:**
  - `x ?? go_panic("…")` (`error_test.baml:95,216`, `example_test.baml:178`, `decode_test.baml:1410,1414`)
  - an inline `throw TomlEncodeError { … }` replacing `enc_panic(…)` in `encode.baml`
  - expression-bodied catch arms `_ => log_fatal("…")` (`ns_cmd/common.baml:7,10`)
- **Cost:** Go's `panicf` helpers can't be used as statements. The inconsistency with `throw` (which does narrow) is surprising.
- **Status:** VERIFIED. No issue.

### W6. Literal-pattern `match` narrows the scrutinee to a literal union without `string` methods — (a) Med

- **Observed:** `time.baml:259: E0007 type '".999" | ".999999" | ".999999999"' has no member 'length'` (T2 [734, 19:24:00]).
- **Repro** (`rp/r04_literal_match`): `match (v) { "a" | "bb" => v.length(), _ => 0 }` gives `E0007 type '"a" | "bb"' has no member 'length'`.
- **Workaround:** compute `let vlen = v.length();` before the `match` (`ns_go/time.baml:232,260`).
- **Cost:** small, but literal types should inherit their base type's methods.
- **Status:** VERIFIED. No issue.

### W7. Flow narrowing to literal types overrides an explicit `: int` annotation — (a) Med

- **Observed:** T1 [740, 00:24:58]: `utf8.baml:64: E0004 cannot order 'int' and '2 | 3 | 4' with '<'`. T1's rejected edit was the workaround, which is why T1 ended.
- **Repro** (`rp/r05_literal_flow`):
  ```baml
  function f(n: int, p: int) -> bool {
    let size: int = 0;
    if (p == 1) { size = 2; } else { size = 3; }
    n < size   // E0004 cannot order `int` and `2 | 3`
  }
  ```
  `n == size` compiles; `<` and `>` don't.
- **Workaround:** Go's `first`/`acceptRanges` tables became helper functions returning `int` (`ns_go/utf8.baml:38–42, 72, 85`).
- **Cost:** about 40 lines; the code diverges from Go's structure.
- **Status:** VERIFIED. No issue.

### W8. Field narrowing — (a) Low

- **Observed:** `E0007 type 'TomlError | null' has no member 'usage'` (T1 [732, 00:24:04]).
- **Repro** (`rp/r06_field_narrow`): `if (self.err != null) { return self.err.x; }` gives E0007.
- **Workaround:** `let e = self.err;` (`error.baml:121`).
- **Status:** VERIFIED. Possibly intentional because fields are mutable, but there's no diagnostic hint.

### W9. Bound method silently used as a value — (a) Med

- **Observed:** `TestEncodePrimitive` failed at runtime with `GoError { msg: "unsupported type for key 'Data': func" }` (T2 [1476, 20:18:54]). The cause was `self.encode_value(key, p.undecoded)` missing its `()`.
- **Repro** (`rp/r07_method_ref`): `take(p.get)` where `take(v: unknown)` compiles cleanly, and `baml.json.to_string(v)` then fails with `value has no json representation`.
- **Workaround:** fixed the call site (`encode.baml:173`, commit `6b6111c`).
- **Status:** VERIFIED. A lint for a bound-method reference flowing into `unknown` would catch this.

### W10. String escapes `\xNN`, `\uNNNN`, `\u{…}` kept literally, with no diagnostic — (a) High

- **Observed, in three steps:**
  - Two `TestErrorPosition` expectations needed a trailing space. The agent wrote the escape `\u{20}` (T2 [1219, 19:41:24]) and the tests kept failing.
  - It switched to ` `, based on a `run -e` probe that looked like it worked (T2 [1510–1516, 19:53]).
  - It kept failing. At T2 [1797, 20:44:23] the agent found `"\t\r\0\x41A\u{41}\a\e".to_code_points()` in a file gives `[9, 13, 0, 92, 120, 52, 49, 92, 117, …]`.
- **Repro** (`rp/r08_escapes`, written via `mk.py`): the source `"\x41A\u{41}\q".to_code_points()` gives `[92, 120, 52, 49, 92, 117, 48, 48, 52, 49, 92, 117, 123, 52, 49, 125, 92, 113]`. That is 18 raw code points; the unknown escape `\q` is also kept without complaint. The same literal passed through `run -e` (built with `printf`, so the backslash is real) gives the same raw result. The "`-e` differs" claim is M1.
- **Workaround** (commit `f264452`):
  - `"      7 | " + "\n…"` concatenation (`error_test.baml:38,72`)
  - a literal `�` pasted into the source (`ns_go/utf8.baml:185`)
  - `string.from_code_points([127]) catch (e) { _ => "" }` for DEL (`go_value.baml:322`)
- **Cost:** 2 test failures that survived 3 full-suite runs (about 1 h wall time, from 19:41 to 20:44). Two shim constants (U+FFFD, DEL) were silently wrong in library code for about 25 minutes: `"\u{FFFD}"` was really the 8-character string `\u{FFFD}`.
- **Status:** VERIFIED. Issue **#4765** ("String literals do not decode \xHH / \uHHHH escapes (kept raw)") was closed 2026-09-06 as not reproducible. Its withdrawal probe was `test "esc_probe_unicode" { "aAb".length() == 3 }`, and that probe passes for two independent wrong reasons: the harness rewrite (M1) and W11. **Reopen #4765.**

### W11. A `test` whose body evaluates to `false` passes — (f) High (found during verification)

- **Repro** (`rp/r35_bool_test`):
  ```baml
  test "false_expr" { 1 == 2 }                                  // PASS
  test "esc_probe_unicode" { "aAb".length() == 3 }         // PASS (length is really 8)
  test "esc_len" { assert.equal("aAb".length(), 3) }        // FAIL
  ```
- **Why it matters:** there is no warning that a test body's value is discarded, and this is exactly the form used to withdraw #4765. The porting agent always used `assert.*`, so it was not affected.
- **Status:** VERIFIED. No issue.

### W12. `testset` expansion failures swallow the panic — (f) Med

- **Observed:** `FAIL root::FuzzToml_ossfuzz_mutations::(failed to expand)` with `AGGREGATE FAIL [outcome=error]` and no message (T2 [1747, 20:43:49]). The agent guessed the cause after two 4-minute reruns, then confirmed it with `baml run -e 'baml.random.Xoshiro256PlusPlus.new(seed = b"abc")…'`, which gives `baml.panics.UserPanic {message: "Rng seed must be at least 32 bytes, got 3"}` (T2 [1850, 21:00:39]).
- **Repro** (`rp/r10_testset`): a `testset` whose `for` collection calls `Xoshiro256PlusPlus.new(seed = b"short")` reports only `(failed to expand)`, also with `-vv` and `--log debug`.
- **Workaround:** the seed became 32 bytes (`fuzz_test.baml:131`). See also W36.
- **Cost:** about 17 minutes.
- **Status:** VERIFIED. No issue.

### W13. `float.to_string()` never uses exponent notation — (c) Low

- **Observed** in T2 [690, 19:21]: `(5e-324).to_string()` is a 327-character string, `(1.7976931348623157e308).to_string().length()` is 311, and `(1.0/(-0.0)).to_string()` is `"-Infinity"`.
- **Repro** (`rp/r11_float_fmt`): `(1e300).to_string().length()` is 303, and `(1.0/0.0).to_string()` is `Infinity`. The `baml run` value display prints `inf`, and `float.parse` accepts both.
- **Workaround:** Go's `FormatFloat(f, 'g', -1, 64)` rebuilt from the shortest digits (`ns_go/strconv.baml:154–240`, part of a 390-line strconv shim).
- **Status:** VERIFIED. No issue.

### W14. Map literal in a `match` arm; `_ => {}` in value position — (a/f) Med

- **Observed:** a wall of `decode.baml:974:31 error[E0010]: unexpected token … expected 'expression', found ':'` (T2 [865–871, 19:31]), plus `E0001 expected 'map<string, …>', found 'void'` at `decode.baml:851` and `decode_test.baml:719,754` (T2 [1290, 19:47:46]).
- **Repro** (`rp/r12_match_maplit`, `rp/r12c_match_void`):
  ```baml
  match (v) { let s: string => { "t": "s", "v": s }, … }   // E0010 ×3 per arm
  match (v) { let i: int => ({ "a": i }), _ => {} }        // E0001 expected map, found void
  ```
- **Workaround:**
  - `({ … })` (`decode.baml:1002–1004`)
  - `_ => { let empty: map<string, baml.json.json> = {}; empty }` (`decode.baml:876–879`, `decode_test.baml`)
- **Cost:** mostly diagnostic quality. The parse errors don't say "wrap the map literal in parentheses".
- **Status:** VERIFIED. No issue.

### W15. Diagnostics for `test` or `self` as parameter names — (f) Low

- **Observed:** `toml_test.baml:346:20 error[E0107]: parameter in function 'test_meta' is missing a name` plus 3 `E0010` (T2 [1029, 19:36:38]). Separately, `function md_unify_into<T>(self: MetaData, …)` gave eight `E0010 unexpected token` errors (T2 [852, 19:31:03]).
- **Repro:** `rp/r13_test_kw` (`function f(test: int)`) and `rp/r14_self_param` (`function helper(self: M)`). Both produce a cascade with no "reserved word" message.
- **Workaround:** renamed to `tt` (`toml_test.baml:346,383`) and to `md` (every `md_*` in `decode.baml`, via regex, T2 [858]).
- **Status:** VERIFIED. No issue.

### W16. Methods must be declared in the class body; field and method names collide — (d/f) Med

- **Observed:** the agent's first `decode.baml` used `function MetaData.unify(...)` for Go methods spread across files. That was rewritten to free functions (T2 [849–858, 19:30:52]). There was also `meta.baml:78 error[E0012]: name 'MetaData.keys' defined 2 times as: field, method` (T2 [684, 19:20:28]); Go has the field `keys` and the method `Keys()`, which snake-case into the same name.
- **Repro:** in `rp/r15_method_outside`, `function M.get(self) -> int` gives `E0011 name 'M' defined 2 times as: class, function` plus an E0010 cascade, which is misleading. In `rp/r21_field_method`, a field `keys` plus a method `keys()` gives E0012.
- **Workaround:**
  - 14 `MetaData` methods became `md_*(md: MetaData, …)` free functions (`decode.baml:375–855`, `primitive_decode` at `:242`)
  - the field was renamed `keys_list` (`meta.baml:13`)
- **Status:** VERIFIED. This is a language design choice, but the diagnostic for the attempted syntax is poor.

### W17. `throws` clause rules — (a) Med

- **Observed, all in T2 unless noted:**
  - T1 [644]: `E0151 function type must declare an explicit 'throws' clause` and `E0170 interface method 'error' on 'Err' must declare an explicit 'throws' clause`.
  - [774, 19:24:56]: `E0097 'throws unknown' is unnecessary …`, on an *implementation* of an interface method that itself declares `throws unknown`.
  - [684], [1029]: `E0096 declared throws is 'ParseError', but this function may also throw 'baml.errors.InvalidArgument | Panic | ParseError'`, and the same for `GoError`/`Panic` in `tag.baml` and `runner.baml`.
  - [1036, 19:36:54]: `E0120 method 'run' has signature … throws Panic, which does not conform to interface 'tomltest.Parser''s declared … throws never`.
  - [1358, 20:02:03]: nine `E0151` in `encode_test.baml`.
- **Repro** (`rp/r17_throws_fn_type`, `rp/r18_throws_impl`, `rp/r19_throws_iface_never`): every message above reproduces. The inconsistency: `throws unknown` restated on an impl is an **error** (E0097), while `function g() -> int throws Oops { 1 }` gets only a **warning** (`warning[E0097]: extraneous throws declaration`).
- **Workaround:**
  - `throws never` added to every function type (`encode_test.baml:507,511,587`, …)
  - `throws` removed from impls (`Pt.marshal_toml`)
  - the `Parser.run` interface widened to `throws root.Panic`, with a `catch` in the runner (`ns_tomltest/runner.baml:119`)
  - declared throws dropped from `parse()`, `parse_loop()`, `tag.baml` and `runner.baml`, losing documented contracts (T2 [732], [1034])
- **Cost:** repeated compile-fix cycles. Turning one helper into a thrower rippled E0096 up the call graph.
- **Status:** VERIFIED. No issue.

### W18. `to_string` cannot be a plain method — (d) Low

- **Observed:** T1 [732]: `E0140 'to_string' cannot be defined as a method on class 'Position'; implement the 'baml.ToString' interface instead`.
- **Repro:** `rp/r20_tostring`.
- **Workaround:** `implements baml.ToString { function to_string(self) -> string throws never { … } }`, about 20 times (e.g. every wrapper in `ns_go/types.baml`, `type_toml.baml:20`, `meta.baml:113`).
- **Status:** VERIFIED. Design choice.

### W19. 63-bit `int`; no fixed-width ints or float32 — (d) Med

- **Observed:** T2 [638, 19:19:55]: `E0150 integer literal '9223372036854775807' is out of range for 'int' (which holds -4611686018427387904 to 4611686018427387903)`.
- **Repro:** re-run on release; identical.
- **Workaround:**
  - TOML integers are `bigint` restricted to the int64 range (`parse.baml:12`)
  - `go.Int8…Uint64/Float32` single-field wrapper classes (`ns_go/types.baml`, 176 lines), since type aliases are transparent
  - float32 `FormatFloat(…, 32)` can't be reproduced (`ns_go/strconv.baml:185`)
- **Status:** VERIFIED. Design.

### W20. Numeric conversions — (c) Low

- **Observed:** `tomlv.baml:40: E0004 operator '+' cannot be applied to '0.0' and 'bigint'` (T2 [1581]).
- **Repro:** `rp/r22_int_range`. `0.0 + 5n` gives E0004, and the diagnostic is printed twice. `Bigint` has `to_int` but no `to_float`; `Int` has no `to_float` (`0.0 + i` works via operator overloads).
- **Workaround:** `float.parse(ns.to_string()) catch (e) { _ => 0.0 }` (`ns_cmd/tomlv.baml:40`).
- **Status:** VERIFIED.

### W21. NaN sign unobservable; `signum` docs misleading — (c/g) Low

- **Observed:** `(-float.nan()).to_string()` is `"NaN"` (T2 [690]). `TestDecodeSignbit` can't be faithful.
- **Repro** (`rp/r23_nan`):
  - `(-float.nan()).signum()` and `(0.0 - float.nan()).signum()` are both `1.0`.
  - `float.baml:93` says `signum` is "a sign-bit test … where the sign of `±0.0` and of NaN counts", then that "NaN returns `1.0`". The two statements contradict each other.
  - There is no `to_bits`, `from_bits` or `is_sign_negative`.
- **Workaround:** `go.signbit` returns false for NaN (`ns_go/strconv.baml:134`); `-nan` round-trips as `nan`.
- **Status:** VERIFIED. No issue. (Related open issue #4750, "`0.0` and `-0.0` literals in the same function body alias", was not hit.)

### W22. No reflective construction; NaN/±Inf can't go through `from_json` — (d/c) High

- **Observed:** `toml: internal error: cannot build ProbeF: expected number at ` (T2 [1379, 20:02:38]). `TestDecodeSignbit` fails in every run.
- **Repro** (`rp/r23_nan`): `baml.json.to_string(F { n: float.nan() })` gives `{"n":null}` silently, and `baml.json.from_json<F>({ "n": float.nan() })` throws.
- **Workaround:** the entire decoder builds a JSON image of the destination and materializes it with `from_json<T>` (`decode.baml:1–40` header; `md_unify*` return `baml.json.json`). Go's in-place `Decode(&v)` became `decode<T>() -> Decoded<T>`. Consequences:
  - missing fields need `zero_json` defaults (`decode.baml:897`)
  - top-level `Unmarshaler` targets bypass JSON (`decode.baml:385–409`, commit `6b6111c`)
  - `Primitive` needs a tagged-JSON encoding (`decode.baml:999–1110`)
  - interface-typed fields can't be decoded
- **Cost:** the largest design deviation (about 1,100-line decoder); 1 failing test; lost Go API shape.
- **Status:** VERIFIED (NaN part). The lack of setters is a feature gap.

### W23. Container type patterns are invariant — (d) Med

- **Observed:** T2 [755, 19:24:46] probe: `describe([1, 2])` with arm `let a: unknown[]` fell through to `other: int[]`.
- **Repro** (`rp/r31_unknown_arr`): the `unknown[]` arm matches neither `[1, 2]` nor `{"a": 1}` (`other: int[] / other: map<string, int>`).
- **Workaround:** `type E = unreflect(at.element_type()); let arr: E[] = v else …` plus a copy into `unknown[]` (`go_value.baml:120–134`, used by the encoder and `%v` printer).
- **Cost:** an O(n) copy per slice access; about 60 lines of reflection glue.
- **Status:** VERIFIED. Probably by design (mutable containers), but there's no read-only covariant view.

### W24. No struct tags or custom attributes — (d) Med

- **Observed:** T2 [415–454, 19:15]: the agent read `baml_compiler2_hir/src/attrs.rs` ("Attributes are a fixed vocabulary") and found `Meta.other` only set in `runtime_class_builder.rs`.
- **Workaround:** Go tags are stored as `@description("toml:\"name,omitempty\"")` and parsed by a port of `reflect.StructTag.Get` (`go_value.baml:182`).
- **Cost:** `@description` is polluted (it also feeds LLM prompts).
- **Status:** UNVERIFIED (feature gap).

### W25. Other Go features with no BAML counterpart — (d) Med

Each is a feature gap, not a bug:

| Missing feature | Workaround | Where |
|---|---|---|
| Embedded fields and method promotion | `go:"embed"` pseudo-tag plus hand-forwarded methods | `type_fields.baml:9`, `ns_example/example.baml:22` |
| Methods on non-class types | Wrapper classes | `meta.baml:107` (`Key`), `encode_test.baml:649` (func type) |
| Pointers and addressability | `T?` | `encode.baml:746`, `encode_test.baml:703` |
| `[N]T` | 5 cases `UNPORTABLE` | `decode_test.baml:324,445,915` |
| Non-string map keys | 5 cases `UNPORTABLE` | `decode_test.baml:681,685`, `encode_test.baml:1416` |
| Package-level variables | Zero-arg functions; the `cachedTypeFields` cache is dropped | `type_fields.baml:231`, `internal.baml:11` |
| Varargs and printf | Template strings plus a hand-written `%q/%v/%x` | `ns_go/fmt.baml` |
| Labelled `continue outer` | Flags | VERIFIED as `E0010`, `rp/r33_label` |
| `goto` | Rewritten | — |
| Complex numbers, channels | `ADAPTED` test cases | `encode_test.baml:601,660` |

### W26. Strings are Unicode-only; no lossy UTF-8 decode — (d/c) Med

- **Observed:** `GAPS.scratch.md` (T1): "string.from_utf8 throws InvalidArgument; no lossy decode -> manual."
- **Verified:** `baml describe String` shows only `from_utf8(...) throws InvalidArgument` and `from_code_points`.
- **Workaround:** the lexer works on `int[]` bytes so Go byte offsets match; a hand-written UTF-8 decoder and a lossy `string_of` live in `ns_go/utf8.baml` (198 lines). Invalid-UTF-8 test inputs travel as bytes end to end.
- **Status:** VERIFIED (API absence).

### W27. No stdin read-all; `input()` EOF is ambiguous — (c) Low

- **Observed:** T2 [1563, 20:20:16]: `input` docs say "end-of-input reads as `""`".
- **Repro** (`rp/r25_tooling`): input `x\n\n` and input `x\n` both yield `[x][][]`.
- **Workaround:** `baml.fs.open("/dev/stdin", "r").bytes()` (`ns_cmd/common.baml:5–13`). This isn't portable to Windows.
- **Status:** VERIFIED.

### W28. No temp-file API, no embedding — (c/d) Low

- **Workarounds:**
  - `/tmp/toml-baml-test-decodefile.toml` (`decode_test.baml:47–53`)
  - the `//go:embed` toml-test corpus copied to `testdata/` and read relative to the cwd, so the suite must run from the project root
- **Status:** VERIFIED by `baml describe baml.fs` (no temp or tmp functions).

### W29. Agent-skill gate — (f) Low

- **Observed:** T1 [628] and T2 [626]: `error: the BAML agent skill is required but is not installed; run 'baml agent install' … set BAML_AGENT_SKILL_CHECK=off to bypass this check`.
- **Workaround:** the `.bin/b` wrapper.
- **Status:** VERIFIED on release. Every `run` also prints `warning: code is unformatted; run 'baml fmt'` and "using the internal BAML toolchain binary directly is not recommended".

### W30. `baml run` output and argument handling — (f) Low

- **Observed:** T2 [1611–1620, 20:21:52]: trailing `null`; `error: unexpected argument '--files' found`, with the hint `JSON-only parameters (pass via --json-args): files: string[]`.
- **Repro** (`rp/r25_tooling`):
  - `run main` prints `hello` then `null`, and `-q`/`-qq` don't remove the `null`
  - `--output-format` offers only `debug|json`
  - `bool` parameters are `--types true`, not switches
- **Workaround:** documented; the CLI ports print a trailing `null`.
- **Status:** VERIFIED.

### W31. Test runner withholds results until the run ends — (f) Med

- **Observed:** a 10-minute run looked hung (T2 [1311, 19:58:14]), which cost bisection time. Full runs were 10–40 minutes with no progress.
- **Repro** (`rp/r26_buffer`, non-TTY): `baml.io.println` output inside a test streams immediately, but `PASS root::a_fast` is printed only when the 2 s `b_slow` finishes (both PASS lines carry the same timestamp).
- **Workaround:** the agent ran groups separately with `timeout`.
- **Status:** VERIFIED for piped output (the agent always piped). On a TTY the progress UI may differ; not checked.

### W32. Test selector semantics — (f) Low (mostly an agent mistake, M4)

- **Observed:** `-i "TestToml::valid/array*"` gives `Finished no tests selected` (T2 [1056]), and `-i "TestDecodeEmbedded*"` does the same (T2 [1315]). The agent concluded "glob `*` is not supported in selectors", and `-i probe_x` also ran `probe_x2`.
- **Actual behavior** (`rp/r16_select`, and `baml help test` → SELECTORS): plain selectors are substring matches; a selector containing `*` is an anchored full-ID glob, so it needs a `root::` prefix or a leading `*`. `*TestX::valid/array*` and `root::TestX::valid/array*` both work.
- **Remaining UX problems:** the concise `--help` doesn't mention globs, "no tests selected" gives no hint, and an exact match needs the full `root::name` ID.
- **Consequence:** at T2 [1305, 19:48:11] the agent ran `test -x "TestToml*"` to skip the 930-case suite. The exclude matched nothing, so the whole suite ran, including `TestMaxDepth#02`'s 300 s timeout. That is the ">10 min hang" at 19:58 (see M5).
- **Status:** behavior VERIFIED, as documented.

### W33. Builtin-stdlib warnings in every `baml check` — (f) Low

- **Observed:** every `check` in T1 and T2 starts with `csv.baml:402:13 warning[E0146]: unreachable code …` and similar lines from `iter.baml`, `stream.baml`, `ns_internal/wire.baml` and `ns_mcp/mcp.baml`.
- **Repro:** any project (e.g. `rp/r02_and_narrow`) prints 11 `warning[E0146]` from the stdlib with bare file names (no `<builtin>/` prefix), so they look like user files. This is likely introduced by `f603110e74` ("diagnose constant conditions and unreachable code"), the commit just before the tested HEAD.
- **Workaround:** the agent grepped them out.
- **Status:** VERIFIED. No issue.

### W34. General performance — (e) High

- **Observed** (T2):
  - debug CLI about 10 s per invocation (T1 [672]: "~10s startup")
  - 1M-iteration loop about 14 s on debug (T1 [661])
  - full suite 10–40 minutes versus Go's 0.35 s
  - `TestMaxDepth#00/#02` hit the 300 s timeout
  - listing the suite with a naive glob matcher "took seconds" (T2 [1268])
  - `FuzzToml_ossfuzz_mutations` took 4 minutes for 20 cases (T2 [1839])
- **Release numbers** (from [report.md](report.md) section 3, spot-checked here via W2):
  - `fib(25)` is about 50× Go, and the geomean port slowdown is about 2,900×
  - `TestMaxDepth#00` 17 s and `#02` 83 s; Go's O(n³) key bookkeeping is kept verbatim
- **Workaround:** a fast path in `match_glob` (`ns_tomltest/runner.baml:698–715`, commit `6b6111c`); otherwise accepted.
- **Status:** VERIFIED (numbers from the post-mortem, W2 re-measured). No issue.

### W35. `baml run --function` subcommand naming — (f) Low

- **Observed:** `baml run --function cmd.toml_test_decoder -- cmd.toml_test_decoder` gives `error: unrecognized subcommand 'cmd.toml_test_decoder' … tip: a similar subcommand exists: 'toml_test_decoder'` (T2 [1597, 20:21:47]).
- **Repro:** `rp/r25_tooling/baml_src/ns_cmd/c.baml`. `baml run cmd.hi` works directly, so the `--function X -- X` form is unnecessary; its usage line `baml run -f cmd.hi -- <COMMAND>` is confusing.
- **Workaround:** `[scripts]` entries like `"--function cmd.tomlv -- tomlv"` (`baml.toml`).
- **Status:** VERIFIED.

### W36. `Xoshiro256PlusPlus.new` panics on a short seed despite `throws never` — (c) Low

- **Repro:** `baml describe` shows `function new(seed?: uint8array) -> Xoshiro256PlusPlus throws never`, yet `new(seed = b"x")` raises `UserPanic "Rng seed must be at least 32 bytes, got 1"`. Panics aren't part of `throws`, so this is legal, but a length precondition that only surfaces at runtime (and inside a testset, invisibly; see W12) is a trap.
- **Workaround:** a 32-byte seed literal.
- **Status:** VERIFIED.

### W37–W39. Minor gaps

- **W37: no dependencies between user packages.** `cmd/*` and `_example` became namespaces `ns_cmd` and `ns_example` in the library package (PORTING_NOTES #31). UNVERIFIED.
- **W38: no benchmark, fuzz or example-test harness.**
  - `bench_*(n)` functions run with a tiny n (`bench_test.baml:4`)
  - 40 seeded PRNG mutations (`fuzz_test.baml:3`)
  - example `// Output:` blocks asserted by hand (`example_test.baml:4`)
- **W39: defaulted parameters are keyword-only.** `E0005 defaulted parameter 'seed' must be passed by name` (T2 [1644, 20:23:24]; VERIFIED). Design; trivial.

## Agent mistakes (reported or treated as BAML problems, but not BAML bugs)

- **M1. "String escapes differ between `.baml` files and `baml run -e`" (PORTING_NOTES #22).** This is a tool-harness artifact. The Claude Code tool rewrites a backslash-u-hex sequence in the *command text* into the literal character before the shell sees it: the agent's command at T2 [1795] shows `-e '"…\x41A\u{41}…"'` with `A` already turned into `A`. During verification a `printf '%s'` of that string also came out as `A` under `od -c`. Built with a real backslash, `run -e` behaves exactly like a file (all escapes kept raw).
- **M2. "BAML panics are not catchable, so panic/recover must be emulated with throws" (PORTING_NOTES #15; `toml_test.baml:414`).** False. `expr catch (e) { baml.panics.StackOverflow => -1 }` and `… { baml.panics.UserPanic => -2 }` both work (`rp/r34_panic_catch`). There is also `catch_all_panics` (`baml_tests/…/ns_exceptions/exceptions.baml:1969`) and `baml.sys.panic(message) -> never`. T1 had even printed the `catch_all` docs saying "To intercept a panic, name its type explicitly in an arm". A faithful `recover` was possible, and W3's StackOverflow could have been turned into an error.
- **M3. "No `defer`" (PORTING_NOTES #16).** False: BEP-042 `defer { … }` exists and runs at block exit (`rp/r32_defer` gives `start;body;A;`). It is block-scoped rather than function-scoped like Go's, which might still need restructuring. Labelled `continue`/`break` really are missing (VERIFIED).
- **M4. "Glob `*` is not supported in selectors" (PORTING_NOTES #34).** False; globs are anchored full-ID (see W32).
- **M5. "TestDecodeSignbit hangs" and the 10-minute "hang" (T2 [1311–1400]).** The per-test loop printed `TIMEOUT` via `r=$(timeout 90 … | grep Finished); echo "${r:-TIMEOUT}"`, which prints TIMEOUT whenever no `Finished` line appears, for example while the half-written `encode_test.baml` broke compilation. `baml test` on a compile error actually fails fast (exit 4 in 0.3 s; `rp/r27_compile_err_test`). The earlier 10-minute stall of `test -x "TestToml*"` was the full suite running because the exclude matched nothing (W32). The existing post-mortem's "10-minute 'hang' … turned out to be a half-written file" conflates the two.
- **M6. `decode.baml:238` comment: "BAML methods cannot be generic over a type parameter that is only used by the method and be called on a class from another file".** False: a generic method `function prim<T>(self, j) -> T` on a class in one file, called as `md.prim<int>(5)` from another file, works (`rp/r28_generic_method`). The real reason `primitive_decode` is a free function is W16.
- **M7. "The Write tool stripped trailing spaces in my literals" (T2 [1218]).** That is Claude Code tool behavior, not BAML. It is what set off the whole W10 escape saga.
- **M8. Minor guesses the compiler correctly rejected:**
  - `s.lower()` (it's `to_lower_case()`)
  - a nonexistent pipe operator `… catch_all (e) { … } |> truncate_float` (`|>` is a parse error; `rp/r29_pipe`)
  - `E0063 unreachable arm` for a `_` after an exhaustive `let x: Err` arm (T1 [644]; correct behavior)
  - T1's probe test expected `perf(10) == 25` when the right answer is 23
  - a preemptive `slice(0, min(len, 1500))`, although `slice` already clamps (T2 [1826])
  - a regex rename that produced `E0005 expected 1 argument(s), got 3` (T2 [852])
  - the `.bin/b` wrapper returns grep's exit status, so test failures are invisible to `$?`

## Notes for filing

In priority order:
1. W1
2. W10 (reopen #4765, citing M1 and W11)
3. W11
4. W2
5. W3
6. W12
7. W4–W7 as a "narrowing" bundle
8. W9
9. W17
10. W14 and W15 as a "diagnostics" bundle
11. W33

Every repro above is a standalone project under `rp/` and runs as-is with the release CLI.
