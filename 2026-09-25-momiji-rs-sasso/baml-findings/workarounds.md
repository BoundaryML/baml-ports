# momiji-rs/sasso → BAML: every BAML bug and limitation the port worked around

Written 2026-09-29. This is a companion to [report.md](report.md) (the post-mortem). Every item below was re-derived from the port's code and notes and then re-run as a minimal repro.

## Scope and method

- **Sources swept:**
  - The main session transcript, `MAIN` = `<local>/transcripts/…/61fd2bb7-cc53-4101-a6ca-8cdb5e818bbf.jsonl`, and its 61 subagent transcripts (`…/subagents/agent-*.jsonl`).
  - `PORTING_GUIDE.md` §15 ("Findings from porters", append-only during the port).
  - The 1,167 `// PORT:` notes in `baml_src/`.
  - `port/errors_for.py` and `port/fix_throws.py`.
- **Re-verification.** Two fresh subagents re-ran each candidate as a minimal standalone project on 2026-09-29, with the following setup:
  - Toolchain: the `baml` wrapper 0.2.5 selecting **0.20.2-nightly.20260925.a**, which is newer than the port's 20260923.a.
  - Anything that did not reproduce was re-run on 20260923.a (`~/.baml/toolchains/0.20.2-nightly.20260923.a/bin/baml-cli`) to rule out a fix between the two nightlies.
  - Scratch projects ran with `BAML_AGENT_SKILL_CHECK=off` (see #30).
  - `RUST_MIN_STACK` was unset except where noted.
  - Repro projects are in `<local>/scratchpad/findings/repro/{A,B}/<name>/`.
  - Port-level checks ran on a copy of this directory.
- **Status labels:**
  - **VERIFIED**: reproduced on 2026-09-29.
  - **NOT REPRODUCED**: the minimal repro did not trigger it (a porter's error, or narrower than claimed).
  - **FIXED**: reproduces on 20260923.a but not on 20260925.a.
  - **(documented)**: `baml describe` states this behaviour. It is still listed when it is a porting hazard.
- **Issue search:** `gh issue list -R BoundaryML/baml --state all --search …`, with 2–6 queries per item (error text, codes, feature names). "none" means no matching issue. No issues were filed.

## Summary table

Categories: **a** = compiler/checker, **b** = runtime/VM, **c** = stdlib, **d** = missing language feature, **e** = performance, **f** = CLI/tooling, **g** = docs.
Severity:
- **high**: a crash, a silent wrong result, or port fidelity loss.
- **med**: a frequent spurious error, or a large ergonomic or performance cost.
- **low**: occasional friction, or behaviour that is documented but surprising.

| # | Title | Cat | Sev | Verified? | Issue | Workaround in port |
|---|---|---|---|---|---|---|
| 1 | `0.0` and `-0.0` literals in one function collapse into one constant | a | high | VERIFIED | #4750 (open) | `root.std.NEG_ZERO()` built from bits |
| 2 | An always-throwing `catch` arm inside a null-narrowed branch makes a later null check fold to "always true": miscompile | a | high | VERIFIED (smaller trigger than reported) | none | Store the error in a local; `throw` after the statement |
| 3 | `env.<field>` on a parameter/local named `env` reads BAML's `env` reference; can compile and return `Ref { name: … }` | a | high | VERIFIED (worse than reported) | none | Rename to `env_` |
| 4 | Measuring a deep rope string (`.length()` after ~102K `+` appends) aborts the process with a native stack overflow | b | high | VERIFIED | none | `root.std.StrBuf` flattens periodically; `join` flattens every 2,048 parts |
| 5 | `baml check`/`run` abort with a native stack overflow (no diagnostics) on ~131-function call chains, ~114-function cycles, ~208 nested `if`s | a | high | VERIFIED (synthetic); hit during the port; the finished port no longer triggers it | none | `RUST_MIN_STACK=1073741824` while porting |
| 6 | Codegen panic "indirect calls require an explicit caller layout" (`x ?? Generic { … }` then a method call on a field) | a | high | VERIFIED (narrower than reported) | none (related #4506) | Spell type arguments: `root.std.Tuple2<A, B> { … }` |
| 7 | `.to_string()` on an interface-typed value passes `check`, then "VM internal error" | a/b | high | VERIFIED | none | Call on the concrete class / an interface method |
| 8 | `baml.sys.exec` with ≥ ~147 KB of `stdin` to a child that echoes it hangs forever; `timeout_ms` doesn't fire | c | high | VERIFIED | none | Redirect through temp files with `/bin/sh -c` |
| 9 | VM call stack capped at 256 frames: the port fails at 114 nested rules / 39-deep Sass recursion (Rust: ~2,100 / ~1,370) | b | high | VERIFIED | none | None; limit kept |
| 10 | `obj.f = obj.f ^ x` (bigint bitwise op assigned to a field) → "VM internal error: cannot apply binary operation" | b | high | FIXED in 20260925.a (VERIFIED on 20260923.a) | #4813 (open, same root cause) | Temp local / `(a \| b) - (a & b)` |
| 11 | `baml.id` removed between two nightlies (20260923.a → 20260925.a) with no replacement | c/f | high | VERIFIED | none | `baml.random.SystemRandom` token |
| 12 | Unknown escapes (`\u{…}`, `\uXXXX`, `\x..`, `\q`) kept verbatim with no diagnostic | a | high | VERIFIED | #4765 (open) | Literal characters / `root.std.chr_unchecked(cp)` |
| 13 | A class literal whose string field contains `{` or `}` inside a `for (… in [ … ])` header → E0003 "unresolved name" | a | med | VERIFIED (real trigger found; reported as "Tuple3 unresolved") | none | Bind the array to a local first |
| 14 | Float comparisons are a total order: `NaN == NaN`, `NaN > 1.0` are `true` | c/g | med | VERIFIED (documented) | none | `root.std.feq/fne/flt/fle/fgt/fge` |
| 15 | `Array.includes`/`index_of` compare classes and arrays by identity; `==` is structural; not documented | c/g | med | VERIFIED | none | `root.std.contains/position` |
| 16 | `catch_all` / `_` arms don't catch panics | b/g | med | VERIFIED (documented in `describe`, not in the skill) | #4967 (open) | `catch (e) { let p: baml.panics.Panic => … }` |
| 17 | `baml.fs.read` on non-UTF-8 throws `Io`, not the documented `ParseError` | c | med | VERIFIED | none | Catch `Io` |
| 18 | Any `(` inside a `match` guard starts a lambda parameter list: `(b && c)`, `!(…)`, `(v is A)`, `(self.m())`, `(match …)` | a | med | VERIFIED | none | Hoist into a `let` before the `match` |
| 19 | Statement-initial `[` after an `if`/`match` block continues it as indexing (E0010/E0008) | a | med | VERIFIED | none | `;` after the `}` |
| 20 | Narrowing gaps: right operand of `&&`/`\|\|`; a closure capture removes narrowing in the whole region; `-> never` calls don't narrow | a | med | VERIFIED (3 of 5 sub-claims) | none | Nested `if`, copy to a local, `x ?? baml.sys.panic(…)` |
| 21 | `let s = E.A;` infers literal type `E.A`, which has no methods; `E.A.m()` is E0003 | a | med | VERIFIED | related #4422 | `let s: E = E.A;` |
| 22 | Interface default methods: E0170 requires `throws`, E0097 rejects `throws unknown` on a non-throwing body, `throws never` blocks throwing overrides | a | med | VERIFIED | none | `port/fix_throws.py` widens to `throws unknown` |
| 23 | `spawn` runs tasks on real threads with no mutex/atomic; shared counters lose updates; docs say "green threads" | d/g | med | VERIFIED | none | `--jobs` forced to 1 |
| 24 | `baml test` runs tests concurrently in one process; `client` state is shared between tests | f | med | VERIFIED | none | Unique temp dirs per test (`testing.Sequential()` would also work) |
| 25 | No top-level `let`/`const`/`static`/thread-local; `client X = expr` works as an undocumented process-wide singleton; `CLIENT.field.to_string()` is E0007 | d/a | med | VERIFIED | none | `client X_CELL = root.std.Cell<T> { … }` + accessor function |
| 26 | 63-bit `int`; no f64 `to_bits`/`from_bits`; `~` exists but is undocumented | d/g | med | VERIFIED | none | `bigint`; hand-written IEEE bit casts in `ns_std/num.baml` |
| 27 | `String.at/slice/code_point_at` are O(i); `Array.join` ~8.5× slower than a loop; `for … in` ~5.8× slower than indexing | e | med | VERIFIED | none | `s.chars()` arrays, native `+` join; hot loops kept as ported |
| 28 | `.baml/cache` is whole-project: +17 MB per edit, never evicted; first run after an edit is slower than cold; `baml clean` unavailable | f/e | med | VERIFIED | #5013 (open, profiles half) | Delete `.baml/` by hand |
| 29 | `baml.sys.argv()` has the entry-function name in `argv[1]` (both `baml run` and `baml pack`) | c | low | VERIFIED | none | `root.std.args()` drops it |
| 30 | In an agent environment, every CLI command refuses to run without a matching installed agent skill (after any toolchain switch) | f | med | VERIFIED | none | `baml agent install` / `--agent-skill-check off` |
| 31 | 20260925.a prints 11 E0146 warnings from builtin stdlib files on every `baml check` | f | low | VERIFIED | none | Ignore |
| 32 | `float.signum(NaN)` is `1.0` (Rust: NaN); its doc contradicts itself | c/g | low | VERIFIED (documented) | none | Not needed at the port's call sites |
| 33 | `Float.to_degrees` = `x * 180 / π`, differs from Rust's `x * (180/π)` in the last bit | c | low | VERIFIED | none | `root.builtins.math.f64_to_degrees` |
| 34 | No imports; namespaces don't see root names | d | low | VERIFIED (documented) | none | Fully qualified `root.x.Y` everywhere |
| 35 | Map keys must be `string`; no set, tuple types or generic type aliases | d | low | VERIFIED (documented) | none (#267 closed, 2024) | String keys (`render()`), `root.std.TupleN` classes |
| 36 | No reference-identity operator | d | med | VERIFIED | none | `_id` token field (#11) |
| 37 | `uint8array` not iterable with `for … in`; `at(-1)` counts from the end; `ProcessOptions.stdin` is string-only | c/d | low | VERIFIED (`at` documented) | none | Index loops; guard computed indices |
| 38 | `baml.fs` has no stat/mtime, realpath/canonicalize, or cwd | c | low | VERIFIED | none | Shell out to `stat`, `realpath`, `pwd` |
| 39 | Destructuring a generic class in a pattern requires type arguments | a | low | VERIFIED (by design) | none | `Tuple2<A, B> { _0: let a, _1: let b }` |
| 40 | An empty class pattern `T {}` matches any field values; undocumented | g | low | VERIFIED (by design) | none | List fields to constrain |
| 41 | A narrowed scrutinee makes a later `_` arm an error (E0063) | a | low | VERIFIED (by design, documented) | none | Drop the `_` arm |
| 42 | A field and a method can't share a name (E0012); `to_string`/`to_json` must go in `implements baml.ToString`/`ToJson` | a | low | VERIFIED (by design) | none | Rename (`len_`), implement the interface |
| 43 | `catch` arms can't take `if` guards | a | low | VERIFIED | none | Test inside the arm |
| 44 | Function-typed class fields must declare `throws` (E0151) | a | low | VERIFIED (by design) | none | 200+ explicit `throws` |
| 45 | `baml run`/`test` refuse to run on any compile error anywhere; `baml test` exits 4 without saying why | f | low | VERIFIED | none | Fix or stub first |
| 46 | `baml pack -o dir/x` fails with a bare "No such file or directory" when `dir/` doesn't exist | f | low | VERIFIED | none | `mkdir -p dist` |

Porter mistakes and claims that did not hold (details in the last section):
- P1. "A syntax error hides every type error project-wide" (NOT REPRODUCED). `port/errors_for.py` was built on this belief.
- P2. "Multi-line match guards are rejected" (NOT REPRODUCED).
- P3. "Or-patterns can't bind a field across variant classes" (NOT REPRODUCED).
- P4. "Generic `T?` doesn't narrow on `== null`" (NOT REPRODUCED, except with `panic`; see #20).
- P5. "BAML has no bitwise-not" (wrong: `~x` works).
- P6. "`root.std.Tuple3` unresolved in a `for` header" (real trigger is #13).
- P7. A salsa "dependency graph cycle" compiler panic (NOT REPRODUCED).
- P8. "`(match …)` misparses in `let` initialisers and after `&&`" (only inside guards; see #18).
- P9. "The project needs `RUST_MIN_STACK`" (only while it was half-ported; see #5).
- P10. "`Array.join` of 100K strings dies" (the join completes; measuring the result dies; see #4).

---

## Detailed entries

### 1. `0.0` and `-0.0` literals in one function collapse into one constant

**Severity:** high (silent wrong result). **Status:** VERIFIED on 20260925.a and 20260923.a. **Issue:** #4750 (open), "`0.0` and `-0.0` literals in the same function body alias to whichever is written first", filed against 0.17.0.

```baml
function neg_first(c: bool) -> float { if (c) { -0.0 } else { 0.0 } }
function pos_first(c: bool) -> float { if (c) { 0.0 } else { -0.0 } }
function main() -> string {
  (1.0 / neg_first(true)).to_string() + " " + (1.0 / pos_first(false)).to_string()
}
```
```
"Infinity -Infinity"     (expected "-Infinity -Infinity")
```
- In straight-line code the first literal wins: `(0.0).to_string() + "," + (-0.0).to_string()` → `"0.0,0.0"`.
- In the if/else form above, the else-branch literal wins.
- **Why it matters:** sasso's number formatting and `math.div`/`round` distinguish `-0` from `0` (Sass prints `-0` in some places).
- **Workaround:** `root.std.NEG_ZERO()` (`ns_std/num.baml:740`) builds −0.0 from its bit pattern (`f64_from_bits(0x8000000000000000n)`), so no `-0.0` literal appears next to a `0.0`.

### 2. An always-throwing `catch` arm in a null-narrowed branch makes a later null check fold to "always true"

**Severity:** high (miscompile: the wrong branch runs). **Status:** VERIFIED on both nightlies. The trigger is smaller than the porter reported. **Issue:** none.

```baml
function ld() -> int { 1 }
function h(cached: string?) -> string {
  if (cached == null) {
    let _y = ld() catch (e) { baml.errors.Io => { throw e; } };
  }
  if (cached != null) { return "cached"; }
  "not cached"
}
function main() -> string { h(null) }
```
```
main.baml:9:7-9:21 warning[E0004]: `string` and `null` share no value, so this comparison is always true
main.baml:10:3-10:15 warning[E0146]: unreachable code: 1 statement(s) after diverging statement
$ baml run main
"cached"            (expected "not cached")
```
- The flow analysis treats the whole `if` branch as diverging because the `catch` arm always throws, even though the callee can't throw at all. After the `if`, `cached` is then narrowed to non-null and the compiler emits the wrong branch.
- A non-throwing arm (`baml.errors.Io => { 5 }`) behaves correctly.
- A porter hit this in a map-cache lookup of the shape `let loaded = if (cached != null) { null } else { … catch … throw … }`, where a later `if (cached != null)` then ran for uncached entries.
- **Workaround:** inside the arm, store the error in a local, then `throw` it after the statement.

### 3. `env.<field>` on a binding named `env` reads BAML's builtin `env` reference

**Severity:** high (can compile cleanly and return a wrong value). **Status:** VERIFIED, and worse than the porter reported. **Issue:** none.

```baml
class Env { depth int }
function f(env: Env) -> int { env.depth }
function g(env: Env) -> string { let r = env.depth; `${r}` }
function main() -> string { g(Env { depth: 7 }) }
```
```
f: error[E0001]: mismatched types   primary: expected `int`, found `baml.env.Ref`
g: compiles with no diagnostic;  baml run main → "Ref { name: \"depth\" }"
```
- The same happens with a local, `let env = Env {…}; env.depth`.
- Method calls (`env.d()`) and passing `env` as a value do resolve to the binding. Only `env.<field>` is hijacked.
- The compiler should either reject `env` as a binding name or let the binding shadow the builtin.
- **Workaround:** rename the binding to `env_` (`ns_eval/ns_modules/modules.baml:650`, "a bare `env.x` is BAML's `env` reference").

### 4. Measuring a deep rope string aborts the process

**Severity:** high (process abort, not a catchable panic). **Status:** VERIFIED on both nightlies. **Issue:** none.

```baml
function build(n: int) -> string { let s = ""; for (let i = 0; i < n; i += 1) { s = s + "ab"; } s }
function main(n: int) -> int { build(n).length() }
```
```
n=100000 (20260925.a): 200000
n=200000:             thread 'main' has overflowed its stack
                      fatal runtime error: stack overflow, aborting   (exit 134)
bisected on 20260925.a: ok at 101,562 appends, abort at 103,125 (20260923.a aborts below 100K)
```
- Building the rope is fine: 400K appends without measuring completes. The abort happens in the first operation that walks the rope (`length`, which by the porter's reading of `bex_str.rs` is a recursive `char_count`).
- `self.s = self.s + x` on a field behaves the same way.
- `Array.join` is written in BAML with `+` (#27), so `parts.join("")` over 200K parts completes, and then `.length()` on the result aborts.
- **Workaround:**
  - `root.std.StrBuf` (`ns_std/strbuf.baml`) is the port's `String` builder. It keeps pieces in an array and flattens periodically.
  - `root.std.join` uses native `+` and flattens every 2,048 parts.
  - Bootstrap's output (277 KB, built from ~10⁶ pieces) would otherwise abort.

### 5. The compiler overflows its native stack on long call chains

**Severity:** high while it happens (abort with no diagnostics, exit 134). **Status:** VERIFIED with a synthetic repro. It was hit repeatedly during the port (125 times in the transcripts, all between 22:00 and 23:00 PDT on 2026-09-25, while function bodies were partly stubbed). **The finished port no longer triggers it**: `baml check` and all 1,107 tests pass with `RUST_MIN_STACK` unset on both nightlies [measured]. **Issue:** none.

```python
# gen.py N → baml_src/main.baml: a chain f0 → f1 → … → fN-1, no cycle
for i in range(n-1): print(f"function f{i}(x: int) -> int {{ f{i+1}(x) }}")
print(f"function f{n-1}(x: int) -> int {{ x }}")
print("function main() -> int { f0(1) }")
```
```
$ baml check        # N = 131
thread '<unknown>' has overflowed its stack
fatal runtime error: stack overflow, aborting        (exit 134)
```

| shape | 20260925.a: ok / aborts | 20260923.a: ok / aborts |
|---|---|---|
| call chain `f0→…→fN-1` | 128 / 131 | 138 / 141 |
| call cycle `f0→…→fN-1→f0` | 110 / 114 | 119 / 123 |
| nested parens `(1 + (1 + (… 0)))` | 306 / 310 | 294 / 297 |
| nested `if (true) { … } else { 1 }` | 205 / 208 | 212 / 215 |

- The crashing thread is a spawned thread with Rust's 2 MiB default stack. The threshold scales with `RUST_MIN_STACK`, at roughly 15 KB of native stack per function in the chain.
- Declaring `throws never` on every function in the chain avoids it (5,000 functions check fine). So the recursion is `throws` inference along the call graph (`callable_throws` → `infer_function_body` → `callable_throws` …, as seen in a porter's salsa query-stack dump).
- That fits the porters' observation that stubbing one function in the cycle made the crash go away.
- Nested expressions and nested `if`s are a separate, ordinary AST recursion.
- **Workaround:** `export RUST_MIN_STACK=1073741824` for every `baml` command.

### 6. Codegen panic: "indirect calls require an explicit caller layout"

**Severity:** high (compiler crash, exit 101). **Status:** VERIFIED on both nightlies (`emit.rs:2328` on 25.a, `emit.rs:2342` on 23.a). The trigger is narrower than reported. **Issue:** none; related #4506 (open, an ICE on inferred generic arguments with a different crash site).

```baml
class Box<T> { v: T }
function f(o: Box<string>?) -> int {
  let t = o ?? Box { v: "abc" };
  t.v.length()
}
function main() -> int { f(null) }
```
```
thread '<unnamed>' panicked at crates/baml_compiler2_emit/src/emit.rs:2328:21:
indirect calls require an explicit caller layout
```
- It needs two things:
  - a local whose type joins a declared `Box<string>` with an inferred-type-argument generic literal, via `??` or an if/else;
  - a method call on one of that local's fields.
- It does not panic with explicit `Box<string> { … }`, with an annotated local, without the join, or without the method call.
- **Workaround:** always spell type arguments on `root.std.TupleN` literals that are joined with an existing value.

### 7. `.to_string()` on an interface-typed value

**Severity:** high (type-checks, then crashes). **Status:** VERIFIED on both nightlies. **Issue:** none.

```baml
interface Named { function label(self) -> string throws never }
class Dog { name: string  implements Named { function label(self) -> string throws never { self.name } } }
function show(n: Named) -> string { n.to_string() }
function main() -> string { show(Dog { name: "rex" }) }
```
```
$ baml check → Finished (no diagnostics)
$ baml run main
VM internal error: interface `user.Named` declares no method `to_string`
```
- **Workaround:** call `to_string` on a concrete class type, or add a rendering method to the interface and call that.

### 8. `baml.sys.exec` with a large `stdin` hangs

**Severity:** high (hang with no error; the timeout doesn't help). **Status:** VERIFIED on 20260925.a. **Issue:** none.

```baml
function main(n: int) -> int {
  let out = baml.sys.exec("/bin/cat", null, baml.sys.ProcessOptions {
    cwd: null, env: null, timeout_ms: null, stdin: "x".repeat(n), stderr: null });
  out.stdout.length()
}
```
```
n=70000:  70000
n=200000: (no output; killed by a 20 s alarm)      bisected: ok at 147,187 bytes, hangs at 147,694
timeout_ms: 2000 → still hangs
/usr/bin/wc -c with 5,000,000 bytes of stdin → 5000000 (fine)
```
- A child that echoes its input hangs once stdin exceeds roughly both pipe buffers. This fits the parent writing all of stdin before it drains stdout.
- **Workaround:** redirect through temp files. The musl `pow` oracle test (`ns_musl_math/ns_tests/tests.baml:95`) runs `baml.sys.exec("/bin/sh", ["-c", "exec \"$0\" <\"$1\" >\"$2\"", oracle, in_path, out_path], null)`.

### 9. The VM call stack is capped at 256 frames

**Severity:** high for this port (fidelity loss on deep inputs). **Status:** VERIFIED. **Issue:** none.

```baml
function depth(n: int) -> int { if (n == 0) { 0 } else { 1 + depth(n - 1) } }
```
```
depth(254): 254
depth(255): uncaught throw: baml.panics.StackOverflow {message: "stack overflow"}   (catchable)
```
Port-level effect [measured, packed binary on 20260925.a]:

| Input | BAML port | Rust `sasso` |
|---|---|---|
| Nested style rules `.a0 { .a1 { … b: c; } }` | ok at 113 levels, fails at 114 | ok up to ~2,100 (then a native stack overflow abort) |
| `@function f($n) { @if $n == 0 { @return 0; } @return f($n - 1) + 1; }` | ok at `f(38)`, fails at `f(39)` | ok up to ~1,370 |

- Each Sass nesting level or call costs several BAML frames (`exec` → `eval_style_rule` → … → `eval_expr` → `call_function` → `run_fn_body` → …).
- `baml describe baml.panics.StackOverflow` doesn't state the limit.
- No upstream test hits it, but real-world Sass libraries with recursive helpers could.
- **Workaround:** none. The port keeps the limit.

### 10. A `bigint` bitwise op assigned back to a field → VM internal error

**Severity:** high on 20260923.a. **Status:** VERIFIED on 20260923.a, **FIXED on 20260925.a**. **Issue:** #4813 (open), "Nightly VM rejects bigint subtraction assigned to a field; temporary local works". Same root cause; it can probably be re-tested and closed.

```baml
class R { state: bigint  function next(self) -> bigint { self.state = self.state ^ 3n; self.state } }
function main() -> string { let r = R { state: 5n }; r.state = r.state | 8n; r.state.to_string() + " " + r.next().to_string() }
```
```
20260925.a: "13 14"
20260923.a: VM internal error: cannot apply binary operation: bigint | bigint
```
- The porter reported "`bigint ^ bigint` inside a class method". The actual trigger is `obj.f = obj.f <op> x` for bigint bitwise ops, in any function.
- **Workaround** (`PORTING_GUIDE.md` §15): `(a | b) - (a & b)` for xor, or compute into a temp local before assigning to the field.

### 11. `baml.id` removed between two nightlies

**Severity:** high for existing code (the port stopped compiling). **Status:** VERIFIED. **Issue:** none.
- 20260923.a had `baml.id.current`/`new`/`set`, documented as a runtime-ID override API. The port used `baml.id.new()` as a process-unique identity token (#36).
- 20260925.a (two days later) has no `baml.id`, no deprecation notice, and no replacement found in `baml describe --search`.
- An unmodified port fails with exactly one error: `ns_std/core.baml:140:5-140:16 error[E0003]: unresolved name: baml.id.new`.
- **Workaround:** `root.std.fresh_id()` now returns `` `${baml.random.SystemRandom.get().random_int()}` `` (63 random bits). After that one-line change, all 1,107 tests and the 982-case corpus pass on 20260925.a.

### 12. Unknown string escapes are kept verbatim, silently

**Severity:** high (silent wrong strings). **Status:** VERIFIED. The file was written from Python and checked with `od -c`, because some tool layers decode `\u` before the file reaches disk. **Issue:** #4765 (open), "String literals do not decode `\xHH` / `\uHHHH` escapes". It doesn't mention `\u{…}` or the missing diagnostic.

```baml
function lens() -> string {
  "\u{e9}".length().to_string() + " " + "\x41".length().to_string() + " " + "é".length().to_string()
}
function unknown() -> string { "\q" }
```
```
baml check → no diagnostics
lens → "6 4 6"      unknown → "\\q"
```
- Only `\n \t \r \0 \\ \"` (and a few more) decode. Backtick strings behave the same way.
- `baml describe` has no documentation of escapes.
- **Workaround:** the skeleton generator and porters wrote the literal characters into the source, or used `root.std.chr_unchecked(0x2215)` for invisible or combining characters.

### 13. Braces inside a string break a class literal in a `for … in` header

**Severity:** med (spurious, misleading error). **Status:** VERIFIED on both nightlies. It was originally reported as "`root.std.Tuple3` unresolved". **Issue:** none.

```baml
class P { s: string }
function ok() -> int { let n = 0; for (let c in [P { s: "a" }]) { n += c.s.length(); } n }
function bad() -> int { let n = 0; for (let c in [P { s: "a {" }]) { n += c.s.length(); } n }
```
```
main.baml:15:18-15:19 error[E0003]: unresolved name: `P`
```
- `"a }"` fails the same way.
- All of these pass: binding the array to a local first; `for (let c in ["a {", "b"])` (no class literal); the same literal in an `if`, a `match` scrutinee or a C-style `for` initializer.
- This looks like a brace-counting lookahead in the `for … in` header that doesn't skip string literals.
- Reverting the port's workaround in `ns_tests/ns_diagnostics/diagnostics.baml` (SCSS snippets like `".a {\n"` inside `root.std.Tuple3 { … }`) brings the error back.
- **Workaround:** `let cases = [ … ]; for (let c in cases) { … }`.

### 14. Float comparisons are a total order

**Severity:** med for ports (Rust code that relies on IEEE NaN comparisons silently changes behaviour). **Status:** VERIFIED. **(documented, intended):** `baml describe Float` says NaN is "a single value ordered above every number". **Issue:** none.

```
NaN==NaN:true  NaN!=NaN:false  NaN>1.0:true  NaN>=NaN:true  NaN<1.0:false  inf<NaN:true
```
- **Workaround:** `root.std.feq/fne/flt/fle/fgt/fge(a, b)` (`ns_std/num.baml:750…`) implement IEEE semantics. They are used wherever a NaN can reach a comparison (Sass `math.div(0, 0)`, `min`/`max`, color channels). `root.std.fmax`/`fmin` follow Rust.

### 15. `Array.includes`/`index_of` use identity; `==` is structural

**Severity:** med (silent wrong result for ported `contains`). **Status:** VERIFIED. The docs don't say which equality these use. **Issue:** none exact (#4422 mentions the "classes are reference types" wording).

```baml
class T { a: int }
// [T { a: 1 }] == …   includes / index_of / nested arrays
```
```
"==:true includes:false index_of:null includes(same ref):true nested ==:true nested includes:false"
```
- **Workaround:** `root.std.contains(v, x)` and `root.std.position(v, x)` (`ns_std/collections.baml:190`) loop with `==`.
- As a side effect, `[x].includes(y)` is the only reference-identity test in the language (#36). The port doesn't rely on it.

### 16. `catch_all` and `_` don't catch panics

**Severity:** med. **Status:** VERIFIED. `baml describe catch_all` documents it ("the bare `_` never catches panics"), but the agent skill presents `catch_all (e) { _ => … }` as exhaustive. **Issue:** #4967 (open), "`catch_all` does not catch an `assert.*` failure".

```
boom() catch_all (e) { _ => -1 }              → uncaught throw: baml.panics.UserPanic {message: "boom"}
boom() catch (e) { let p: baml.panics.Panic => -1 } → -1
```
- **Workaround:** Rust `#[should_panic]` tests and `catch_unwind` sites use `catch (e) { let _p: baml.panics.Panic => … }` (e.g. `ns_tests/ns_sourcemap/sourcemap.baml:227`).
- Index-out-of-bounds, overflow and stack overflow are all `baml.panics.*`.

### 17. `baml.fs.read` reports invalid UTF-8 as `Io`

**Severity:** med (the documented error type is wrong). **Status:** VERIFIED. **Issue:** none.
```
$ printf 'a\377b' > bad.txt; baml run main -- --path bad.txt
"Io: Failed to read file '…/bad.txt': stream did not contain valid UTF-8"
```
- `baml describe baml.fs.read`: "Throws `ParseError` if the file's bytes are not valid UTF-8".
- **Workaround:** `read_source` (`main.baml:1591`) catches `Io` and tests `is_invalid_utf8(io)` on the message to produce sasso's `Error: Invalid UTF-8.`.

### 18. Any `(` inside a `match` guard starts a lambda parameter list

**Severity:** med (frequent spurious errors in ported Rust guards). **Status:** VERIFIED on both nightlies. **Issue:** none.

| Guard | Result |
|---|---|
| `let n if n == 0 \|\| (b && c) =>` | E0010 expected `')'`, found `'&&'` |
| `let n if !(n > 5) =>` / `let n if (n > 0) =>` | E0010 expected `')'`, found `'>'` |
| `let n if n > 0 && (v is A) =>` | E0010 expected `')'`, found `'is'` (bare `v is A` works) |
| `let n if n > 0 && (self.ok()) =>` | E0010 expected `')'`, found `'.'` (works without parens) |
| `let n if (match (n) { 1 => true, _ => false }) =>` | E0107 parameter in function `lambda` is missing a name |
| `let n if n > (1 + 2) =>` | E0107 |

- Parentheses work in every other expression position, including `(match …)` in `let` initializers and after `&&` (see P8). `baml describe patterns` documents guards as `<pattern> if cond` with no restriction.
- **Workaround:** hoist the sub-expression into a `let` before the `match`, or rewrite without parentheses (`!(a > b)` → `a <= b`). This accounts for a large share of the "hoisted guard" `// PORT:` notes.

### 19. A statement-initial `[` after an `if`/`match` block is parsed as indexing

**Severity:** med (confusing errors). **Status:** VERIFIED. **Issue:** none.

```baml
function f(x: int) -> int[] {
  let y = x;
  if (x < 0) { y = 0; }
  [y, 1]
}
```
```
error[E0010]: unexpected token  primary: expected `']'`, found `','`
(one-element `[y]`: error[E0008]: cannot index into type `void`)
```
- The same happens after a `match` statement. A `( … )` on the next line is *not* treated as a call, so the grammar is inconsistent.
- **Workaround:** `;` after the `if`'s closing `}`.

### 20. Narrowing gaps

**Severity:** med (frequent spurious E0007/E0001, each forcing a local or a nested `if`). **Status:** mixed; see below. **Issue:** none.
- **20a. VERIFIED.** No narrowing into the right operand of `&&`: `x != null && x.f > 0` gives E0007 "type `P | null` has no member `f`". The `if` body *is* narrowed.
- **20b. VERIFIED, narrower than claimed.** No narrowing into the right operand of `||`: `x == null || x.f > 0` gives E0007. The else branch and code after an early return are narrowed.
- **20c. VERIFIED, broader than claimed.** Any closure capture of a narrowed optional removes the narrowing in the *whole* region, including uses *before* the closure:
  ```baml
  function a(x: P?) -> int {
    if (x == null) { return 0; }
    let before = x.f;                   // E0007 here too
    let g = () -> bool { x != null };
    x.f + before                        // E0007
  }
  ```
- **20d. VERIFIED.** A `-> never` call doesn't narrow: after `if (x == null) { baml.sys.panic("none") }`, `x` is still `int | null` (E0001). `throw` does narrow, and the checker already knows the call diverges (it warns E0146 for code after it).
- **20e. NOT REPRODUCED** (P4). Generic `T?` narrows fine on `== null`, except combined with 20d.
- **Workarounds:**
  - Nested `if`, or `x?.f`.
  - Copy to a non-optional local before capturing (`let p = x;`).
  - `let y = x ?? baml.sys.panic("…");` (sasso's `.expect()` → `root.std.expect`).

### 21. `let s = E.A;` gets the literal type `E.A`

**Severity:** med. **Status:** VERIFIED. **Issue:** none exact; related #4422 point 4 (a literal type inferred for a `reduce` seed).
```
let s = ListSep.Space; s.sep()    → error[E0007]: type `ListSep.Space` has no member `sep`
let s = ListSep.Space; s = ListSep.Comma; → error[E0001]: expected `ListSep.Space`, found `ListSep.Comma`
ListSep.Space.sep()               → error[E0003]: unresolved name: `Space`
```
- `int`, `string` and `bool` literals widen on `let`; enum variants don't.
- **Workaround:** `let s: ListSep = ListSep.Space;`. The port's C-like enums carry methods through an `<Enum>Methods` interface, so this came up often.

### 22. `throws` rules on interface default methods conflict

**Severity:** med. **Status:** VERIFIED. **Issue:** none.
- E0170: every interface method, abstract or default, "must declare an explicit `throws` clause".
- E0097: a default body declared `throws unknown` that can't throw is an **error** ("`throws unknown` is unnecessary … Remove the declaration"), which E0170 forbids.
- `throws never` then rejects throwing overrides (E0120). A concrete `throws E` on the same body is only a warning.
- `throws never` defaults break as soon as a callee (e.g. a function-typed parameter declared `throws unknown`) can throw (E0096).
- So there is no way to say "overrides may throw anything" on a default method whose own body can't throw.
- **Workaround:** `port/fix_throws.py` widened every E0096-failing interface default to `throws unknown`. Bodies that couldn't throw were kept abstract or given `throws E`.

### 23. `spawn` runs on real threads with no synchronisation primitives

**Severity:** med (data races; docs mislead). **Status:** VERIFIED. **Issue:** none.
```
4 × spawn { for 100K: c.n = c.n + 1 }  →  "expected 400000, got 82015"   (3 runs: 82015, 82214, 82284)
CPU-bound: 1 task real 0.65 s / user 0.58 s;  4 tasks real 0.72 s / user 2.44 s
```
- The agent skill says "Concurrency = green threads". There is no mutex, lock or atomic in `baml describe`.
- **Workaround:** sasso's `--jobs N` worker pool (`compile_all`, `main.baml:1532`) is forced to `jobs = 1`. Rust's per-thread compiler state became process-wide `client` cells (#25), and the work-claim counter is not atomic.

### 24. `baml test` runs tests concurrently in one process

**Severity:** med. **Status:** VERIFIED. **Issue:** none.
- Four tests that each set a shared `client` slot and sleep 300 ms finish in 0.41 s, and 3 of 4 fail (`left = "d", right = "a"`).
- `baml help test` has no jobs or serial flag.
- **Workaround:**
  - The port's tests keep all state local and give each test a unique temp dir (`sasso-modtest-<pid>-<fresh_id>`).
  - `testset "…" with testing.Sequential() { … }` (documented in `baml describe testing.Sequential`) runs children one at a time.

### 25. No globals; `client X = <expr>` is an undocumented process-wide singleton

**Severity:** med. **Status:** VERIFIED. **Issue:** none.
```
let COUNTER = 0;   → error[E0010]: top-level `let` bindings are not supported (same message for `const`)
client COUNTER = Cell { value: 0 };   → persists across calls and is shared by spawned tasks ("after 2 calls: 2, after 3 spawned: 5")
COUNTER.value.to_string()            → error[E0007]: type int has no member to_string   (bug; `let v = COUNTER.value; v.to_string()` works)
```
- `baml describe client` documents only the LLM-client form.
- **Workaround:** Rust `static` atomics, `thread_local!` and `OnceLock` became `client X_CELL = root.std.Cell<T> { value: … }` plus a zero-arg accessor function (`PORTING_GUIDE.md` §15). Pure caches were dropped instead.
- Because the cells are process-wide, the CLI compiles sequentially (#23).

### 26. 63-bit `int`, no f64 bit casts, undocumented `~`

**Severity:** med. **Status:** VERIFIED. **Issue:** none.
- `4611686018427387903 + 1` → `baml.panics.IntegerOverflow`, and `18446744073709551615` is E0152 (documented: 63-bit).
- `(1.5).to_bits()` → E0007. There are no `f64::to_bits`/`from_bits`.
- `~x` works on `int` and `bigint` (`~5` → `-6`), but `baml describe` doesn't list it and `baml.ops` has no `BitNot` (see P5).
- **Workaround:**
  - FxHash, ryu and musl math do u64 arithmetic on `bigint` through `root.std.u64_*` wrapping helpers (`u64_wrapping_mul`, `u64_rotate_left`, …) that mask to 64 bits.
  - `root.std.f64_to_bits`/`f64_from_bits` decompose floats arithmetically (verified against rustc for subnormals, ±0, ±inf, NaN).
  - ryu float formatting was ported on top of them.

### 27. Performance of common string and array operations

**Severity:** med. **Status:** VERIFIED by timing on 20260925.a. **Issue:** none.

| Operation | Measurement |
|---|---|
| `s.at(n-1)` on a 1M-char ASCII string | ~45 µs per call (`at(0)` is flat): O(i) |
| `s.slice(n-2, n-1)` | ~95 µs per call |
| `s.code_point_at(n-1)` | ~27 µs per call |
| `parts.join(",")` on 50K strings | ~2.9 µs/element vs 0.34 µs for a hand-written `+` loop (8.5×); `join` is written in BAML and calls `string.from` per element |
| `for (let x in a)` over `int[]` | 176 ns/element vs 30 ns for an index loop (5.8×) |

- **Workaround:**
  - Scanners work on `s.chars()` arrays and char offsets, never `at(i)` in loops.
  - `root.std.join` uses native `+` (flattening every 2,048 parts).
  - Hot `for … in` loops were left as ported, for fidelity. That is one of the main reasons for the 60–700× slowdown (report §3).

### 28. `.baml/cache` recompiles the whole project on every edit and never evicts

**Severity:** med. **Status:** VERIFIED on a copy of the port. **Issue:** #5013 (open) covers the `profiles-v1` half (unbounded profile files).
```
cold (no .baml)   run 1.52 s   .baml = 34.2 MB
warm, no edit     run 0.28 s
after edit 1      run 2.05 s   .baml = 51.6 MB
after edit 5      run 2.05 s   .baml = 121.0 MB   (+17.4 MB per one-line edit)
```
- The first run after an edit is ~0.5 s *slower* than a cold run with no cache.
- `baml clean`: "error: profiling cleanup is unavailable: the old runtime tracing pipeline has been removed", exit 0.
- After the 6-hour porting session, the project's `.baml/` held 1.5 GB of cache plus 1.9 GB of profiles.
- **Workaround:** `rm -rf .baml` by hand.

### 29. `argv[1]` is the entry-function name

**Severity:** low. **Status:** VERIFIED. **Issue:** none.
```
$ baml run main --           → "<…>/0.20.2-nightly.20260925.a/bin/baml-cli | main"
$ ./argvbin foo bar          → "<…>/argvbin | main | foo | bar"      (baml pack main -o argvbin)
```
- **Workaround:** `root.std.args()` (`ns_std/os.baml:8`) drops `argv[1]` and maps the toolchain binary to `sasso` in `argv[0]`.
- Before that fix, the packed binary treated `main` as an input path.

### 30. The agent-skill check blocks every command in agent environments

**Severity:** med for agent-driven work. **Status:** VERIFIED. **Issue:** none about the refusal (#4422 is about skill *content*).
```
error: the installed BAML agent skill does not match this toolchain; run `baml agent install`, restart the agent, then retry; set BAML_AGENT_SKILL_CHECK=off to bypass this check     (exit 4)
error: the BAML agent skill is required but is not installed; …                                                                                                                (exit 4)
```
- It fires on agent environment variables (`CLAUDECODE=1`, `AI_AGENT=…`). `env -i … baml check` works.
- It blocks `check`, `run`, `test`, `pack` and `describe`, none of which need the skill.
- It hit the port when the user switched toolchains mid-session, and it hits every scratch repro project.
- **Workaround:** `baml agent install` in the project, or `--agent-skill-check off` / `BAML_AGENT_SKILL_CHECK=off` in scratch dirs.

### 31. Builtin stdlib warnings on every `baml check` (20260925.a)

**Severity:** low (noise). **Status:** VERIFIED; 20260923.a prints none. **Issue:** none.
- A one-function project prints 11 `warning[E0146]: unreachable code` lines located in builtin `csv.baml`, `iter.baml`, `stream.baml`, `ns_internal/wire.baml` and `ns_mcp/mcp.baml`. They look like project paths.
- The port's own `check` prints 17 warnings: those 11 plus 6 real ones in the port (dead code after panics, and the forced `jobs = 1`).
- **Workaround:** ignore them.

### 32. `float.signum(NaN)` is `1.0`

**Severity:** low. **Status:** VERIFIED. **(documented)**: "NaN returns `1.0`, matching the total order". The same doc also calls it "a sign-bit test … where the sign of ±0.0 and of NaN counts", which contradicts that (`(-NaN).signum()` is also `1.0`). **Issue:** none.
- **Workaround:** none needed in this port. Every `signum()` call site multiplies a value that is already NaN when the input is NaN, so the product stays NaN (`ns_builtins/ns_colorspace/colorspace.baml:154`).

### 33. `Float.to_degrees` differs from Rust in the last bit

**Severity:** low (breaks byte-exact output). **Status:** VERIFIED. **Issue:** none.
```
to_degrees(0.1) = 5.729577951308232     0.1 * 57.29577951308232 = 5.729577951308233
```
- BAML computes `self * 180.0 / float.pi()`; Rust multiplies by the precomputed constant.
- **Workaround:** `root.builtins.math.f64_to_degrees(x)` = `x * (180.0 / π)`. The math-module porter added it for `math.acos/asin/atan/atan2`. Five color call sites (`"rad"` hue units in `color_ext`, `deprecate`, `legacy` ×2 and `color/math`) still called BAML's `to_degrees()`; they were switched while writing this report. The 982-case corpus had not caught them, because output rounds to 10 decimals.

### 34. No imports; namespaces don't see root names

**Severity:** low (verbosity). **Status:** VERIFIED. **(documented)**: "no imports needed". **Issue:** none relevant.
- Inside `ns_geo/`, `Point` is E0002 ("Did you mean `root.Point`?"). An unresolved *function* gets no hint. `import …` is a syntax error.
- **Workaround:** every cross-module reference is fully qualified (`root.value.Value`, `root.std.Tuple2`). This is one reason BAML is 1.44× more bytes than Rust for 1.22× more lines.

### 35. Map keys must be `string`; no set, tuple types or generic aliases

**Severity:** low. **Status:** VERIFIED. **(documented** for map keys). **Issue:** none current (#267, a tuple request, closed 2024).
```
map<int, string>       → error[E0067]: map keys must be `string`
set<string>            → error[E0002]: unresolved type: set
(int, string)          → error[E0010]
type Pairs<T> = map<string, T>; → error[E0108]
```
- **Workaround:**
  - `root.std.Tuple2..Tuple5` generic classes.
  - Maps keyed by `s.render()` / `to_string()` (e.g. selector `Simple` keys).
  - `HashSet<T>` → `map<string, bool>` keyed by a rendered form (e.g. `main.baml:646`).

### 36. No reference-identity operator

**Severity:** med (sasso compares modules and selectors with `Rc::ptr_eq`). **Status:** VERIFIED (`x === y` is E0010; `==` is structural). **Issue:** none exact (#2220, a UUID type, is open).
- **Workaround:** classes that Rust compares by pointer carry an `_id: string` set from `root.std.fresh_id()` (#11). For example, `root.eval.Module._id` stands in for `Rc::ptr_eq` on modules, and `""` plays the null pointer.

### 37. `uint8array` gaps; negative `at`; string-only `stdin`

**Severity:** low. **Status:** VERIFIED. **Issue:** none.
- `for (let x in b)` over a `uint8array` is E0006.
- `b.at(-1)` and `arr.at(-1)` return the last element (documented, JS-style), so a computed index that goes negative silently reads from the end.
- `ProcessOptions.stdin` is `string | null`.
- **Workaround:** index loops, explicit `i >= 0` guards, and temp files for binary stdin.

### 38. `baml.fs` has no stat, mtime, realpath or cwd

**Severity:** low. **Status:** VERIFIED (`baml describe baml.fs`, `baml.sys`). **Issue:** none; #4379 (closed) added `symlink`/`chmod` after a similar request.
- **Workaround:** `ns_std/os.baml` shells out:
  - `stat -f %Fm` (BSD) or `stat -c %.9Y` (GNU) for mtimes (`--watch`, `--update`);
  - `/bin/realpath` for `fs::canonicalize`;
  - `/bin/pwd -P` for `env::current_dir`.

### 39–44. Checker rules that are by design but cost ported code

**Status:** all VERIFIED on 20260925.a; all by design; **Issue:** none.

| # | Rule | Example diagnostic | Workaround |
|---|---|---|---|
| 39 | Generic class destructure needs type arguments, although the scrutinee fixes them | E0001 "generic class destructure `Tuple2 { ... }` must specify type arguments" | `root.std.Tuple2<string, string> { _0: let a, _1: let b }` |
| 40 | `T {}` matches a `T` with any field values; a later `T { a: 1 }` is E0063. Undocumented. | none | List the fields to constrain |
| 41 | A narrowed scrutinee, `self` included, makes a later `_` arm an error | E0063 "unreachable arm" | Drop the `_` arm |
| 42 | A field and a method can't share a name; `to_string`/`to_json` can't be plain methods | E0012; E0140/E0142 "implement the `baml.ToString` interface instead" | `len_` fields; `implements baml.ToString` |
| 43 | `catch` arms can't take `if` guards (`match` arms can) | E0010 "expected `'=>' after catch pattern`, found `if`" | Test inside the arm |
| 44 | Function-typed class fields and interface methods must spell out `throws` | E0151, E0170 | Explicit `throws never`/`throws unknown` |

### 45. `baml run`/`test` refuse to run with any compile error anywhere

**Severity:** low. **Status:** VERIFIED. **Issue:** none.
- `baml run` prints "cannot run: compilation errors found" (exit 4).
- `baml test` exits 4 after the diagnostics without saying why.
- With 35 units editing 8K-line shared files in parallel, one porter's mid-edit error blocked every other porter's test runs.
- **Workaround:** porters used `port/errors_for.py` to filter diagnostics to their own functions, and waited or stubbed before testing.

### 46. `baml pack -o dir/x` needs `dir/` to exist

**Severity:** low. **Status:** VERIFIED. **Issue:** none.
```
$ baml pack main -o nodir/x
error: failed to create nodir/x
caused by:
    0: No such file or directory (os error 2)
```
- **Workaround:** `mkdir -p dist`.

---

## Porter mistakes and claims that did not hold

- **P1. "A syntax error anywhere hides every type error project-wide."** NOT REPRODUCED on either nightly.
  - Tried: six kinds of syntax error, in other files and other namespaces.
  - Type errors elsewhere (E0001, E0063, E0096, E0097, E0170) were always reported. Only diagnostics later in the *same function* are dropped, which is ordinary parser recovery.
  - `port/errors_for.py` exits 3 ("type checking did not run") whenever any E0010/E0107 exists. That made porters wait unnecessarily.
- **P2. "Multi-line match guards are rejected."** NOT REPRODUCED. `&&` at line start or end and `=>` on its own line all compile. The real restriction is parentheses (#18).
- **P3. "An or-pattern can't bind a field across different variant classes."** NOT REPRODUCED. `Value_Number { _0: let n } | Value_Slash { _0: let n } => …` works. Only conflicting binding *types* are rejected (by design).
- **P4. "Generic `T?` doesn't narrow on `== null`."** NOT REPRODUCED except in combination with `panic` (#20d).
- **P5. "BAML has no bitwise-not."** Wrong: `~x` works on `int` and `bigint`. The port uses `sum & -align` where Rust has `!(align - 1)`. It gives the same result for powers of two, but the premise was wrong.
- **P6. "`root.std.Tuple3` is unresolved in a `for` header."** The real trigger is `{`/`}` inside a string literal in the header (#13).
- **P7. A salsa panic, "dependency graph cycle when querying package_interface".** Seen once while a porter's unit had many stubs and a broken `implements` block. NOT REPRODUCED in 5 targeted attempts.
- **P8. "`(match …)` misparses in `let` initialisers and after `&&`."** Only true inside match guards (#18).
- **P9. "This project needs `RUST_MIN_STACK=1073741824`."** It was needed during the port (#5). The finished port checks, runs and passes all tests without it on both nightlies [measured]. The README and code comments inherited the instruction.
- **P10. "`Array.join` of 100K strings dies."** The join completes; the first `.length()` on the result aborts (#4).
