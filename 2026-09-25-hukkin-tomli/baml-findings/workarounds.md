# hukkin/tomli → BAML: every workaround, bug and limitation

Written 2026-09-28. Companion to [report.md](report.md) (the post-mortem). This file lists every BAML bug or limitation the porting agent had to work around, checks each one against the release `baml-cli`, and adds a few things that turned up during that re-check.

## Sources and method

- **H**: the main port session, `<local>/transcripts/port-hukkin-tomli/510db4c0-732b-4c8a-ba77-6a47a79eca23.jsonl`, 2026-09-26 19:12–19:58 UTC. It has no subagent transcripts.
- **E**: an earlier attempt that the user interrupted, `<local>/transcripts/port-tomli/b0cc49ff-568e-4d7d-a472-36f40de47521.jsonl`, 2026-09-26 00:07–00:21 UTC. It used the same Orca task id and the `port-tomli` worktree, also at `e215c3de2d`. It stopped before writing any port code, but it found 2 things that H didn't: the `join`-on-alias VM crash and O(n) `String.at`.
- Other transcripts that mention `work-repos/tomli-baml` (the burntsushi-toml, eemeli-yaml and coordinator sessions) only reference the path or `PORTING_NOTES.md`. They contain no tomli work.
- **Port**: `<local>/work-repos/tomli-baml`, 9 commits `86cd9a6..fe320c8`, plus `PORTING_NOTES.md` and `repros/r01–r12`.
- Transcript references use the form `H[506 19:24:37]`: jsonl line index (0-based) and UTC time.
- **How I verified.** I used the release binary `<local>/baml-worktrees/port-hukkin-tomli/baml_language/target/release/baml-cli`, built at `e215c3de2d` (= `origin/canary` for this run), with `BAML_AGENT_SKILL_CHECK=off`. Each repro ran in its own throwaway project under `<local>/report-scratch/tomli.MDoJ/` (sources in `src/`, projects in `v/`, driver `rr.sh`). Perf numbers come from the release build.
- **GitHub.** I searched `gh issue list -R BoundaryML/baml --state all` for each item's keywords. There are no matches except where the table notes one. The porting agent filed nothing.
- **Tool-layer caveat.** The harness decodes printable `\uXXXX` in tool-call text before bash sees it. So a heredoc containing `"é"` reaches the file as `"é"`. I wrote the escape repros with Python `chr(92)` to avoid this. The post-mortem's "correction" that `\uNNNN` works for non-control characters was caused by this artifact and is wrong (see C1).

Severity scale, same as the post-mortem: **Crash > Wrong result > Spurious error > Missing error > Perf > Missing feature > Ergonomics/Diagnostic**.

## Summary table

| # | Title | Cat | Severity | Verified? | Issue | Workaround in port |
|---|---|---|---|---|---|---|
| B1 | `Array.join` on a value typed through an alias (`type Key = string[]`) → `VM internal error: could not realize type template` | b | **Crash** | VERIFIED | none | Joins only happen on plain `string[]` or fresh arrays (`py_repr_key(key: string[])`). E was interrupted while isolating it. |
| A5 | Destructuring assignment `P { a: a, b: b } = mk();` / `[x, y] = [1, 2];` compiles and silently does nothing | a | **Wrong result** | VERIFIED (found in re-check) | none | Agent never tried it and used `let r = …; pos = r.first; key = r.second;` everywhere |
| B5 | `test` whose body is a bare boolean (`test "x" { 1 == 2 }`) passes | f | **Wrong result** | VERIFIED | related to #4765 (closed on this invalid evidence) | Not hit: every test uses `assert.*` |
| B4 | `String.at(i)` and `slice(i, j)` are O(i), even on ASCII, so index-based scanners are O(n²) | b/e | **Perf (high)** | VERIFIED (found in re-check; E saw it in debug) | none | **None.** The port indexes with `src.at(pos)` and `src.slice(pos, len)` everywhere, and parse time grows ~10× per 4× input. |
| B3 | A *failing* runtime type test against a recursive-alias container is slow (14 µs / 27 µs / 66 µs for 3 / 7 / 11-member aliases) | b/e | Perf | VERIFIED | none | Scalar arms first in `is_dict_or_list`, and a dict check before the list check (`_parser.baml:487, 704`) |
| C2 | `Array.join` is slow: 121 µs vs 11 µs for a concat loop over 33 chars | c/e | Perf | VERIFIED | none | Manual concat loop in `CharSet.minus` (`_compat.baml:323`) |
| C4 | No anchored `regex.match(s, pos)`, no `Regex.pattern()`, no module state to cache a compiled regex (~110 µs per `regex.new`) | c/d/e | Perf / Missing feature | VERIFIED | none (#4968 is unrelated) | Store pattern strings; compile `^(?:…)` on each call against a line slice (`_re.baml:96`) |
| B2 | VM call stack fixed at 256 frames (`bex_vm/src/vm.rs:118`), not configurable or queryable | b/d | Missing feature (high impact) | VERIFIED | none | `_nested()` runs the parse on a fresh `spawn`ed task every 20 levels (`_parser.baml:68`, commit `f813a92`) |
| A1 | No narrowing across `\|\|` (`d == null \|\| d >= base` → E0004) | a | Spurious error | VERIFIED | none | Nested `if`s (`_compat.baml:145`, `run.baml:36`) |
| A2 | A `never`-returning call used as a statement doesn't end the flow for narrowing | a | Spurious error | VERIFIED | none | `if/else` expression (`_compat.baml:237`) |
| A3 | `?.` on `map<string, T?>.get()` → E0007 (`T \| null \| null` isn't flattened) | a | Spurious error | VERIFIED | none | `?? null`, then an explicit null check (`_re.baml:107`) |
| A4 | Closures lose the flow narrowing of captured variables (E0006) | a | Spurious error | VERIFIED | none | Rebind to a narrowed local (`_parser.baml:1176`) |
| C1 | No `\xHH`, `\uXXXX` or `\u{…}` escapes (none of them, in `"…"` or backticks), and unknown escapes are silently kept | c/a | Missing error | VERIFIED | #4765 (closed 2026-09-06, wrongly) | `chr()` via `baml.String.from_code_points` (`_parser.baml:137`) |
| A8 | Top-level `const X = 1;` → "top-level `let` bindings are not supported"; `describe const` says "compile-time constant" | a/g | Diagnostic / Docs | VERIFIED | none | Each `Final` becomes a zero-arg function |
| A7 | `match` as a parameter name → ~10 cascading "unexpected token" errors | a | Diagnostic | VERIFIED | none | Renamed the parameter to `m` (`_re.baml:136`) |
| A6 | Destructuring a generic class without type args → E0001 + E0111 + "unresolved type: p" cascade | a | Diagnostic | VERIFIED | none | `let Tuple2<int, string> { first: let p, … }`. The port ended up not destructuring at all. |
| A9 | `throws unknown` on a closure is rejected as "unnecessary/imprecise" (E0097) | a | Ergonomics | VERIFIED | none | Drop the clause (`_parser.baml:1168, 1177`) |
| A10 | Explicit `throws` is required on interface methods (E0170) and function types (E0151). The E0006 text leaks `throws callback`. | a | Ergonomics / Diagnostic | VERIFIED | none | `throws never` / `throws unknown` added (`_types.baml`) |
| C5 | `Int/Bigint.parse` accept decimal only and reject `_`; `Float.parse` rejects `_` | c | Missing feature | VERIFIED | none | `py_int_digits` / `py_int_base0` / `py_float` (`_compat.baml:136–197`, ~60 lines) |
| C3 | No `index_of(sub, start)` and no `starts_with` at an offset | c | Missing feature (a perf multiplier with B4) | VERIFIED | none | `str_find` slices the tail (`_compat.baml:205`); `src.slice(p, len).starts_with(…)` ×12 |
| C7 | `PlainTime`/`PlainDateTime` have no `microsecond()`/`nanosecond()` | c | Missing feature | VERIFIED | none | Reads the private `t._nanoseconds` (`burntsushi.baml:253`) |
| C9 | `PlainDate.year()/month()/day()` declare `throws InvalidArgument` | c | Ergonomics | VERIFIED | none | `catch (e) { _ => 0 }` boilerplate (`burntsushi.baml` `str_date`) |
| C11 | No `bigint → float` conversion | c | Missing feature | VERIFIED | none | `baml.Float.parse(ns.to_string())` (`run.baml:31`) |
| C6 | `float.to_string()` isn't Python `repr` (`1e16` → `"10000000000000000.0"`, `inf` → `"Infinity"`) | c | Ergonomics (by design) | VERIFIED | none | `py_float_str` normalizes both sides (`burntsushi.baml:211`) |
| C8 | `PlainDate` accepts year 0 (ISO astronomical numbering) | c | By design | VERIFIED | none | Explicit `year < 1` check (`_re.baml:154`) |
| C10 | `assert.is_true` takes no message | c | Ergonomics | VERIFIED | none | `if (…) { baml.sys.panic("…") }` (`test_data.baml:34, 43`) |
| C12 | No string padding (`ljust`/`rjust`/`zfill`) and no numeric format specs | c | Missing feature | VERIFIED | none | `_ljust`, `_pad`, `_rjust`, `_fmt_3g`, `_fmt_percent` hand-written |
| C13 | No `tempfile`, no text-mode `fs.File`, no warnings machinery | c/d | Missing feature | UNVERIFIED (feature gaps) | none | `TMPDIR` + pid dir; 2 tests declared not portable; `warnings.warn` → `log.warn` |
| D1 | No module-level `const`/`let`, so nothing can be cached or memoized | d | Missing feature (biggest perf cost) | VERIFIED | none | ~25 zero-arg functions; `lru_cache` dropped |
| D2 | No tuples | d | Missing feature | n/a | #267 (2023, closed, old BAML) | `Tuple2`/`Tuple3` generic classes and a `_widen` copy |
| D3 | Defaulted params must be passed by name; no varargs (E0005) | d | Missing feature | VERIFIED | none | `TOMLDecodeError.new` + `from_args(unknown[])` (`_parser.baml:181–256`) |
| D4 | No inheritance | d | Missing feature | n/a | none | `type ValueErrorLike = ValueError \| TOMLDecodeError` |
| D5 | No set type; map keys must be `string` | d | Missing feature | n/a | none | String-backed `CharSet`; `Flag[]` + `includes`; `PendingFlag[]` deduplicated by `==` |
| D6 | `int` is 63-bit | d | Missing feature | VERIFIED (E0150) | none | `bigint` for all TOML ints |
| D7 | Generic invariance; empty `{}` inferred from first `set` | d | By design / Ergonomics | VERIFIED | none | `_widen`; annotate `let m: map<string, Value> = {}` |
| D8 | No namespace alias/import, `__file__`, dynamic tests/`subTest`, function identity, class-as-value, or visibility | d | Missing feature | n/a | none | Documented as not portable; `parse_float: ParseFloat? = null`; `DEPRECATED_DEFAULT {}` instance; loop plus a failure list |
| F1 | CLI refuses to run until the "BAML agent skill" is installed | f | Ergonomics | VERIFIED | none | `BAML_AGENT_SKILL_CHECK=off` in `.tools/b` |
| F2 | 11 `E0146 unreachable code` warnings from the **stdlib** on every command | f | Diagnostic noise (masked real warnings) | VERIFIED | none | `grep -v E0146`, which also hid 5 real warnings in `_parser.baml` |
| F3 | "using the internal BAML toolchain binary directly is not recommended" on every call | f | Noise | VERIFIED | none | `grep -v` in the wrapper |
| F4 | Debug CLI ~12× slower to `check` (5.9 s vs 0.48 s) and ~14–90× slower to run; the release build takes ~12 min | f/e | Perf (dev loop) | VERIFIED (check); run ratio from the agent and the post-mortem | none | Built release in the background; `.tools/br` |
| F5 | `baml describe` has nothing on string-literal syntax or escapes (`no symbol found: backtick`) | f/g | Docs gap | VERIFIED | none | Agent read the `ns_backtick_strings` corpus test |
| G1 | `TEST_INSTRUCTIONS.md:371–374` and corpus comments describe a test-local "VM boxing bug" that no longer reproduces | g | Docs wrong | VERIFIED | none | Agent checked it (H[1218]). Port tests still wrap everything in `check_*()` helpers. |
| F6 | `baml fmt` collapses aligned trailing `//` comments | f | Cosmetic | UNVERIFIED | none | none |

## Detailed entries

### Crashes and wrong results

#### B1. `Array.join` on an alias-typed array crashes the VM — (b) runtime, **Crash**

- **Observed** (E[270 00:21:21], isolated at E[277 00:21:32]):
  ```text
  File "<builtin>/baml/containers.baml", line 347, in baml.Array.join
  VM internal error: could not realize type template: template references frame type-arg slot 0 but the frame has 0 type args
  ```
- **Repro:**
  ```baml
  type Key = string[]
  function j(k: Key) -> string { k.join(".") }        // run: root.j(["a","b"]) → VM internal error
  function jj(k: Key) -> string { let s: string[] = k; s.join(".") }   // "a.b"
  ```
  I also checked `map`, `includes` and `Map.keys()` on alias-typed values: all of them work. Only `join` crashes. Its body destructures `self` with `[let first, ..let rest]` and calls `string.from`, so the rest-pattern type template is the likely cause.
- **Workaround.** E was interrupted by the user 13 s after isolating it. H never saw E's transcript and never hit the crash, probably by luck. The only `join` calls in the port are on fresh `map(...)` results, or on a `string[]`-typed parameter (`_compat.baml:106 py_repr_key(key: string[])`, `:261 py_exception_str`). `Key` is a `string[]` alias in `_types.baml`, so any `key.join` would have crashed.
- **Cost:** none in the final port, but it is a latent trap.
- **Verified:** VERIFIED on the release build. No issue filed. The closest issues, #4813 and #4814 ("VM internal error" with bigint), are different bugs.

#### A5. Assignment to a class or array literal compiles and does nothing — (a) compiler, **Wrong result / missing error** (found during the re-check)

- **Context.** The agent wanted Python's `pos, key = parse_key(src, pos)`. It found out that `let` destructuring can't assign to existing variables (PORTING_NOTES §1.2) and didn't try an assignment form. I did:
  ```baml
  class P { a: int, b: string }
  function t1() -> string { let a = 0; let b = ""; P { a: a, b: b } = mk(); b + a.to_string() }  // "0", expected "x3"
  function t2() -> string { let x = 0; let y = 0; [x, y] = [1, 2]; x.to_string() + y.to_string() } // "00", expected "12"
  ```
  `baml check` is clean and the run is a silent no-op. The assignment probably targets a temporary literal. It should either be rejected ("invalid assignment target") or implemented.
- **Port impact.** The workaround is `let r = …; pos = r.first; key = r.second;` about 56 times (`Tuple2`/`Tuple3` uses in `_parser.baml`). That adds roughly 2 lines per call site.
- **Verified:** VERIFIED. No issue filed.

#### B5. `test` with a bare boolean body always passes — (f) test runner, **Wrong result**

- **Repro:** `test "bare_false" { 1 == 2 }` → `PASS`. `test "x" { assert.is_true(1 == 2) }` → `FAIL`.
- **Relevance.** The porting agent didn't hit this: all 33 of the port's assertions use `assert.*`. The post-mortem found it. It matters because #4765 (escapes) was closed with a comment citing this kind of bare-expression test as proof the bug doesn't reproduce.
- **Verified:** VERIFIED. No issue filed.

### Performance

#### B4. `String.at` and `String.slice` are O(index) → quadratic scanning — (b)/(e), **Perf, high**. The agent missed this.

- **Measurements** [release, 1 M-char ASCII string]:

  | Call | Time |
  |---|---|
  | `at(10)` | 335 ns |
  | `at(100000)` | 6.6 µs |
  | `at(900000)` | 56 µs |
  | `slice(10, 11)` | 0.2 µs |
  | `slice(900000, 900001)` | 112 µs |
  | `length()` | 185 ns |

  Scanning 100 k chars with `at(i)` takes 330 ms (ASCII) or 404 ms (non-ASCII), about 3.3 µs per character.
- **Source.** `bex_vm/src/package_baml/string.rs:110-142`: `at` and `slice` resolve code-point indices by scanning (`char_at_codepoint`, `substring_by_char`), and `code_point_at` uses `chars().nth(i)`.
- **Effect on the port** [release, measured with a copy of the port]:

  | Document | Parse time |
  |---|---|
  | 100 bool lines | 1 ms |
  | 400 bool lines | 5 ms |
  | 1600 bool lines | 43 ms |
  | 6400 bool lines (82 KB) | **502 ms** |
  | 6400 lines of `k = "é"` | 706 ms |

  That is ~10× per 4× input. Where it comes from:
  - `parse_value` does `let rest = src.slice(pos, src.length())` for every value (`_parser.baml:1065`).
  - `skip_chars` and friends use `src.at(p)`.
  - There are 12 `src.slice(p, src.length()).starts_with(…)` calls.
- **Agent evidence:**
  - E[195–197 00:18:12] saw `perf_at` take 46 s vs 245 ms for `chars()`, in debug on a 200 k-char non-ASCII string, then moved on.
  - H[322 19:20:52] timed a 20 k-char scan in debug, where startup dominated, and saw no difference.
  - H's `timings()` measured `src.at(i)` only on the 4 KB benchmark ("0us").
  - So the port has **no workaround**, and the benchmark (4 KB) is too small to show the problem.
- **Possible workaround** (not applied): iterate `chars()` / `to_code_points()` once into an array and index that. That is O(1) per index but costs memory, and every `slice` would need the same treatment.
- **Verified:** VERIFIED. No issue filed.

#### B3. A failing runtime type test against a recursive-alias container is slow — (b)/(e), Perf

- **Repro:** `repros/r11`.
  - Re-check [release]:
    - 3-member alias: `true is V[]` takes 14 µs.
    - 7-member alias: `true is W[]` takes 27 µs.
    - tomli's 11-member `Value`: `true is Value[]` takes **66 µs**, and `"x" is map<string, Value>` takes 60 µs.
    - The original two-arm `is_dict_or_list(true)` takes 118 µs.
    - A succeeding test takes 0 µs.
  - The agent measured 170 µs and 345 µs (H[1101 19:54:00], H[1113]).
- **Impact:** 74 → 32 ms per parse after the fix, i.e. ~55% of the parse time at that point (H[1120]).
- **Workaround:**
  - `is_dict_or_list` lists all 8 scalar arms before the container arms (`_parser.baml:704`).
  - `get_or_create_nest` checks `!(next is map<string, Value>)` before `if let lst: Value[]` (`_parser.baml:487`).
  - Commit `af0adb4`.
- **Cost:** +10 lines. Arm order is now load-bearing for performance, and that isn't visible from the code's meaning.
- **Verified:** VERIFIED. No issue filed.

#### C2. `Array.join` is slow — (c)/(e), Perf

- **Measurements:** `repros/r12`: 121 µs vs 11 µs [re-check], agent 149–424 µs. `join` is BAML-level and calls `string.from` on every element (`containers.baml:343-354`).
- **Impact:** after B3, 32 → 14 ms per parse (H[1168]). `ILLEGAL_BASIC_STR_CHARS()` went from 163 µs to 17 µs.
- **Workaround:** manual concat loop in `CharSet.minus` (`_compat.baml:323`). `CharSet.from_code_points` also switched from `cps.map(chr).join("")` to `baml.String.from_code_points(cps)`.
- **Verified:** VERIFIED.

#### C4 / D1. Regexes can't be compiled once — (c)/(d)/(e)

- **Why:**
  - There are no module-level constants (`r07`).
  - There is no `Regex.pattern()` accessor (E0007 "type `baml.regex.Regex` has no member `pattern`", H[530 19:25:44]).
  - There is no anchored `match(s, pos)`.
- **Cost:** `re_match_at` rebuilds `^(?:…)` and calls `baml.regex.new` for every number or date value (`_re.baml:96`). `regex.new(RE_DATETIME)` takes 111 µs [re-check]. 100 `k = 12345` lines take 16.5 ms vs 1.2 ms for 100 `k = true` lines [re-check]. This is most of the remaining 14 ms per parse.
- **Verified:** VERIFIED. No issue filed (#4968 is a closed regex feature request from a different user and unrelated).

### Runtime limits

#### B2. 256-frame VM stack — (b)/(d), Missing feature, high impact

- **Observed:**
  - `recurse(255)` from a test gives `baml.panics.StackOverflow { message: "stack overflow" }` (H[431 19:22:58]; E[249–254 00:20:18–38]).
  - Inline tables overflowed at 83 levels and arrays at 123 (H[823 19:35:06]). So `test_inline_array_recursion_limit` (470 levels) and `test_inline_table_recursion_limit` (310 levels) failed.
- **Source:** `pub const MAX_FRAMES: usize = 256;` in `bex_vm/src/vm.rs:118`.
- **Workaround history:**
  1. Lowered `MAX_INLINE_NESTING` to 100, then to `(256 - 56) / 2`, then to `(256 - 40) / 3` (commit `01b9f86`, H[780–840]). The original tests still failed.
  2. Then found that every `spawn` gets a fresh frame stack (H[853 19:35:43]) and that typed errors propagate through `await` (H[865]).
  3. Final version: `_nested<T, E>(nest_lvl, f)` does `await spawn { f() }` every 20 levels (`_parser.baml:57-74`, commit `f813a92`).
- **Cost:** ~20 lines. The limit stays at Python's 1000.
- **Correction to the agent's notes and the post-mortem.** Stack overflow is *not* uncatchable. `catch_all`'s `_` arm deliberately excludes panics; `baml describe catch_all` says so. But naming the panic works:
  - `deep(300) catch (e) { baml.panics.StackOverflow => -1 }` → `-1`.
  - `catch (e) { baml.panics.Panic => … }` also works, and so do `UserPanic` and `AssertionFailed` (VERIFIED).
  - That means the notes' claim that "a panicking data file would abort the whole subTest loop" is also wrong.
  - The frame limit itself is real and still needs the spawn hop to pass the 310/470-level tests.
- **Verified:** VERIFIED (limit plus workaround). No issue filed. #4967 (`catch_all` vs `assert.*`) is the same by-design behavior.

### Type-checker bugs (spurious errors)

#### A1. No narrowing across `||` — (a), Spurious error

- **Repro** (`r01`):
  ```baml
  function r01(d: int?, base: int) -> bool { if (d == null || d >= base) { return false; } true }
  ```
  → `E0004 cannot order int | null and int with >=`.
- **Hit at:** H[506 19:24:37] (`py_int_digits`) and H[929 19:37:49] (`best == null || secs < best` in `run.baml`).
- **Workaround:** split into two `if`s (`_compat.baml:145–152`, `run.baml:36–41`). Costs ~4 lines each and duplicates the `throw`.
- **Note.** An early return on `args.length() > 0 || !(msg is string) || …` *does* narrow afterwards (see agent mistake M2). So the gap is specifically narrowing of the right-hand operand inside the condition.
- **Verified:** VERIFIED.

#### A2. A `never` call used as a statement doesn't end the flow — (a), Spurious error

- **Repro** (`r02`):
  ```baml
  if (idx == null) { baml.sys.panic("missing"); }
  idx + 1
  ```
  → `E0004 operator + cannot be applied to int | null and 1`.
- **Hit at:** H[589 19:29:00], in `str_rindex`.
- **Workaround:** use an `if/else` expression (`_compat.baml:237`).
- **Verified:** VERIFIED.

#### A3. `?.` on `map<string, T?>.get()` — (a), Spurious error

- **Repro** (`r03`): `m.get("k")?.text` with `m: map<string, G?>` → `E0007 type G | null has no member text`.
- **Hit at:** H[530–553 19:25:44–19:26:12].
- **Workaround:** `let grp = m.named.get(name) ?? null;` followed by `if (grp == null) { null } else { grp.text }` (`_re.baml:107–119`). Costs +8 lines.
- **Verified:** VERIFIED.

#### A4. Closures lose narrowing of captured variables — (a), Spurious error

- **Repro** (clean version of `r04`, without the E0151 noise):
  ```baml
  function r04(f: ((string) -> int throws never)?) -> (string) -> int throws never {
      if (f == null) { return (s: string) -> int { 0 }; }
      (s: string) -> int { f(s) }
  }
  ```
  → `E0006 ((string) -> int throws never) | null is not a function`.
- **Diagnostic oddity.** In the original `r04` without an explicit `throws`, the message reads `((string) -> int throws callback) | null`, which leaks an internal effect name.
- **Hit at:** H[606 19:29:32].
- **Workaround:** `let inner: ParseFloat = parse_float;` (`_parser.baml:1176`).
- **Verified:** VERIFIED.

#### A9 / A10. `throws` declaration strictness — (a), Ergonomics

- **E0097.** `(s: string) -> int throws unknown { 1 }` is rejected as "`throws unknown` is unnecessary" (`r09`), or as "imprecise: this function only throws `tomli.ValueError`" (H[606]). A closure therefore can't be declared to match a wider `ParseFloat` alias.
  - Workaround: omit the clause (`_parser.baml:1168, 1177`).
- **E0170 / E0151.** Interface methods and function types must declare `throws` (H[405 19:22:42], E[265 00:21:12]).
  - Workaround: `throws never` on `CustomFloat.repr`, and `throws unknown` on `type ParseFloat` (`_types.baml`).
- **Verified:** VERIFIED (`misc` repro).

#### A6, A7, A8. Diagnostics

- **A6: generic destructure** (H[564 19:26:54]). `let Tuple2 { first: p, second: s } = mk(3);` produces:
  - `E0001` (must specify type arguments), which is the real error
  - `E0111` (refutable pattern)
  - `E0002 unresolved type: p` / `unresolved type: s`, because the shorthand is parsed as a type
  - `E0003 unresolved name`

  The fix needs both `Tuple2<int, string>` and `let p`. VERIFIED.
- **A7: `match` as a parameter** (`r06`, H[530]). It produces one E0107 plus ~10 E0010 "expected top-level declaration" errors that run to the end of the file. The workaround renamed `match` to `m` in `_re.baml`. VERIFIED.
- **A8: top-level `const`** (`r07`, H[385 19:22:33], E[231]):
  - The message says "top-level **`let`** bindings are not supported".
  - `baml describe const` says "Declares a compile-time constant binding", with the example `const DEFAULT_LIMIT = 100`. Inside a function body, `const x = 1; x = 2;` compiles with only the warning "`const` is currently treated like `let`; BAML does not enforce immutability yet".

  VERIFIED. The docs part is category (g).

### Stdlib

#### C1. String escapes — (c)/(a), Missing error

- **Re-check** (files written with Python to avoid the tool-layer decoding). Every one of these is kept raw, in both `"…"` and backtick strings:

  | Escape | `.length()` |
  |---|---|
  | `A` | 6 |
  | `é` | 6 |
  | `\u001b` | 6 |
  | `\u{41}` | 6 |
  | `\x41` | 4 |
  | `\e` | 2 |
  | `\q` | 2 |

  Only `\n \t \r \0 \b \v \f \\ \"` (plus `` \` `` and `\$` in backticks) decode. `baml_base/src/escape.rs:6-14` says "Unknown escapes preserve the backslash" and has no `u` or `x` arm.
- **Correction.** Both `PORTING_NOTES.md` and the post-mortem are partly wrong. The post-mortem said `"A"`/`"é"` decode. They don't: the harness had already rewritten them to `A`/`é`. The agent's own H[1096] output `"a {1F600}b"` shows the same tool-layer mangling.
- **Hit at:** H[471 19:23:40] and H[963 19:41:18].
- **Workaround:** `chr(n)` = `baml.String.from_code_points([n])` for `BASIC_STR_ESCAPE_REPLACEMENTS` and the control-character sets (`_parser.baml:85–148`, `_compat.baml:214`).
- **Verified:** VERIFIED. #4765 was closed 2026-09-06 as not reproducing, and should be reopened.

#### C3, C5, C7, C9, C10, C11, C12. Missing stdlib pieces

All verified via `baml describe` method lists and `run -e` on the release build.

- **C3.**
  - Missing: `String.index_of(search)` with a start offset (`"abc".index_of("c", 1)` → E0005) and `starts_with` at an offset.
  - Workaround: `str_find` (`_compat.baml:205`) and `src.slice(p, src.length()).starts_with(…)`. Each costs O(n), and O(i) more from B4.
  - `baml.regex._index_of_from` exists and works (H[519]), but the underscore name marks it as private.
- **C5.**
  - Current behavior: `Bigint.parse("-123_4")` and `Int.parse("0x10")` throw `ParseError`, and so does `Float.parse("1_0.0")` (H[318 19:20:46]).
  - Workaround: `py_int_digits`, `py_int_base0` and `py_float`, about 60 lines.
- **C7.**
  - Missing: `PlainTime` has `millisecond()` but no `microsecond()` or `nanosecond()`.
  - Workaround: `t._nanoseconds % 1000000000 / 1000` (`burntsushi.baml:253`). This only works because BAML has no field visibility.
  - Related: `from_components(microsecond=…)` takes only the sub-millisecond part `[0, 999]`, as in Temporal. That's why the port passes `millisecond = micros / 1000, microsecond = micros % 1000` (`_re.baml:186`).
- **C9.** `PlainDate.year()/month()/day()` declare `throws InvalidArgument`. The stdlib's own TODO in `plaindate.baml` admits this. Workaround: three `catch (e) { _ => 0 }` blocks in `str_date`.
- **C10.**
  - Current behavior: `assert.is_true(cond, message = "…")` → `E0005 unknown named argument message` (H[734 19:31:42]).
  - Workaround: `if (…) { baml.sys.panic("…") }`.
- **C11.**
  - Current behavior: `3n + 0.5` → E0004, and `(3n).to_float()` doesn't exist.
  - Workaround: `baml.Float.parse(ns.to_string())` (`run.baml:31`).
- **C12.** There's no padding function or format mini-language. Workaround: `_ljust`, `_pad`, `_rjust`, `_fmt_3g` and `_fmt_percent`, about 45 lines across `_re.baml`, `burntsushi.baml` and `run.baml`.

#### C6, C8. By-design differences that needed code

- **C6.** `(1e16).to_string()` gives `"10000000000000000.0"`, `inf` gives `"Infinity"`, and `(1.5e-7)` gives `"0.00000015"`. Workaround: `py_float_str` normalizes both sides of the comparison.
- **C8.** `PlainDate.from_components(0,1,1)` gives `"0000-01-01"`. Workaround: an explicit `year < 1` check.

Both VERIFIED.

### Missing language features (d)

These weren't re-verified as bugs. The workarounds are visible in the code.

- **D1: no module-level `const`/`let`.**
  - The port has about 25 zero-argument "constant" functions (`MAX_INLINE_NESTING`, `ASCII_CTRL`, `TOML_WS`, the `RE_*` functions, `__version__`), rebuilt on every call.
  - The `lru_cache` on `cached_tz` was dropped.
  - This drives C4 and part of C2.
- **D2: no tuples.** `Tuple2`/`Tuple3` classes are used 56 times, and `_widen` is needed because generic classes are invariant (`_parser.baml:1151`). See also A5.
- **D3: defaulted parameters must be passed by name, and there are no varargs** (`r08`, H[589]: 12 `E0005` errors on `TOMLDecodeError(msg, doc, pos)`). Workaround: `new(msg, doc, pos)` plus `from_args(all_args: unknown[])`.
  - Checked in the re-check: a function with a defaulted parameter *can* be used as a value of the shorter function type. So the closure wrapper at `_parser.baml:1008` wasn't needed.
- **D4: no inheritance.** Workaround: `ValueErrorLike` union.
- **D5: no set type; map keys must be strings.** Workarounds:
  - `CharSet`, first `map<string, bool>` and then a string (`44b4908`)
  - `Flag[]` with `_set_add`
  - `PendingFlag[]` deduplicated by structural `==`
- **D6: 63-bit `int`** (`E0150 integer literal … out of range`, H[272]). All TOML ints are `bigint`.
- **D7: container typing.** Empty containers need annotations. `let m = {}; m.set("a", true)` is inferred as `map<string, bool>` and rejected where a `Value` is expected (VERIFIED).
- **D8: smaller gaps.**
  - No namespace alias (`import tomli as tomllib`).
  - No `__file__`, so test data is resolved relative to the cwd.
  - No dynamic `test` generation (`subTest`), so the tests use a loop that collects failures.
  - No function-identity comparison, so `parse_float: ParseFloat? = null` means "the default float".
  - Classes aren't values, so `DEPRECATED_DEFAULT {}` is an instance matched with `is`.
  - No field visibility (C7 relies on this).

### Tooling and docs

- **F1: agent-skill gate.** Every command fails with "error: the BAML agent skill is required but is not installed; run `baml agent install`…" unless `BAML_AGENT_SKILL_CHECK=off` is set (H[263 19:19:28], E[126]). VERIFIED.
- **F2: stdlib `E0146` warnings.**
  - Every `check`/`test`/`run` prints 11 `warning[E0146]: unreachable code` lines from `csv.baml`, `iter.baml`, `stream.baml`, `ns_internal/wire.baml` and `ns_mcp/mcp.baml` (H[502 19:24:32]). They probably come from `f603110e74`.
  - **Side effect:** the agent piped everything through `grep -v E0146`, which also hid 5 real warnings in its own code (`_parser.baml:588, 765, 824, 881, 1046`: dead trailing expressions after `while (true)` loops). I checked that `while (true)` without a trailing expression type-checks, so those lines are removable.
  - VERIFIED.
- **F3:** "warning: using the internal BAML toolchain binary directly is not recommended" is printed on every invocation. The `.tools/b` and `.tools/br` wrappers filter it. VERIFIED.
- **F4: debug vs release** [re-check, port project]:
  - `check` takes 5.9 s (debug) vs 0.48 s (release).
  - The agent measured a 4 KB parse at 6.8 s (debug) vs 74 ms (release) before tuning, i.e. ~90× (H[947], H[1060]). The post-mortem measured ~14× after tuning.
  - The release build took 11 m 56 s (H[1048]), and `cargo build` defaults to debug.
  - VERIFIED for `check`; the rest comes from the transcript.
- **F5:** `baml describe backtick`/`escapes`/`strings` → "no symbol found". There's no discoverable reference for literal syntax or escapes. The agent read `crates/baml_tests/baml_src/ns_backtick_strings/backtick_strings.baml` instead (H[449–471]). VERIFIED.
- **G1:**
  - `TEST_INSTRUCTIONS.md:371-374` presents "a `let`-bound local inside a `test` block does not compare equal to a literal" as a real defect.
  - `ns_backtick_strings/backtick_strings.baml` and `ns_const_bindings/const_bindings.baml` repeat it as a convention ("VM boxing bug").
  - Re-check: `test "x" { let r = "x"; assert.equal(r, "x") }`, list push and `+=` variants all pass. So the doc is stale.
  - The port still followed the convention of putting everything in `check_*() -> bool` helpers wrapped in `assert.is_true(...)`, which loses assertion detail at the test level.
  - VERIFIED.
- **F6:** `baml fmt` turns aligned trailing comments into single-space comments (commit `2f9aed4`). Cosmetic. UNVERIFIED.
- **Also noted, not a workaround:** `log.warn` output goes straight into `baml test` output (the DeprecationWarning lines) and can't be captured, so `assertWarns` isn't portable. UNVERIFIED.

## Agent mistakes (not BAML bugs)

- **M1: "Stack overflow is uncatchable, even by `catch_all`" (PORTING_NOTES §3.1–3.2; repeated in the post-mortem).**
  - `catch_all`'s `_` deliberately excludes panics (`baml describe catch_all`).
  - `catch (e) { baml.panics.StackOverflow => … }` and `baml.panics.Panic => …` both catch it (VERIFIED).
  - The spawn workaround is still needed, but for the 256-frame depth, not for catchability.
- **M2: expected no narrowing after the `from_args` early return.**
  - The first `_parser.baml` re-narrowed `msg`/`doc`/`pos` with `match`.
  - The compiler answered with `E0063 unreachable arm` at `_parser.baml:196-198` (H[589 19:29:00]): the narrowing through `||` plus `!(x is T)` in an early return *does* work.
  - The agent removed the extra matches. Its notes record this correctly as a positive observation.
- **M3: blamed the wrong expression for E0007.**
  - At H[530–553] it annotated the `m.groups.map((g) -> { g?.text })` lambda as the cause.
  - The error was actually on line 107, `m.named.get(name)?.text` (A3). It reverted the lambda annotation afterwards.
- **M4:** `_compat.baml: unresolved type TOMLDecodeError` (H[502–553]) came from writing `_compat` before `_parser`. It went away once `_parser.baml` existed.
- **M5 (E):** `catch_all (e) { _ => "caught ${e}" }` printed the literal text `caught ${e}` (E[186]). Only backtick strings interpolate. `baml check` gives no hint about `${` inside `"…"`, and a lint would help.
- **M6 (E):** `PlainTime.from_components(7, microsecond = 999990)` → `microsecond 999990 is out of range [0, 999]` (E[203]). The parameter is the sub-millisecond component, as in Temporal. The agent fixed it by splitting into `millisecond` and `microsecond`.
- **M7:** the first `r11` measured 0 µs because the `is` tests were on locals and got constant-folded. The agent fixed that by moving the checks into functions (H[1236–1247]).
- **M8:** the `grep -v E0146` filter hid its own dead-code warnings (see F2).
- **M9:** an unnecessary closure wrapper around `parse_basic_str_escape` at `_parser.baml:1008` (see D3).
- **M10:** `r04` also triggers E0151, so it isn't minimal (clean version in A4).
- **M11: `\u` escapes.** `PORTING_NOTES` says `\uNNNN` isn't supported, which is correct. The post-mortem's "correction" that it works for non-control code points is wrong: that was tool-layer decoding (C1).
- **M12: the agent never tested at scale.** It benchmarked only the 4 KB `data.toml` and 100–400-line synthetic files, so it missed the O(n²) behavior from B4, even though E had seen `at()` take 46 s vs 245 ms in debug.

## Suggested filing order

1. **B1: `join` on an alias crashes the VM.** Crash; tiny repro.
2. **A5: literal-pattern assignment is a silent no-op.** Wrong result; tiny repro.
3. **B5: a bare-boolean `test` passes.** Also reopen #4765 (C1) with a correct repro. Use `assert.equal("a\x1bb".length(), 3)`, and write the file without tool-layer escape decoding.
4. **B4: O(i) `String.at`/`slice`.** This silently makes idiomatic parsers quadratic.
5. **B3 and C2: perf.** Repros r11 and r12 as-is.
6. **A1–A4: narrowing gaps.** Repros r01–r03, and the clean A4.
7. **Diagnostics and tooling:** A6, A7, A8, F2 (stdlib E0146), F5, G1.
