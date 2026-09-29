# Porting notes: BurntSushi/toml (Go) → BAML

## Setup

- Source: https://github.com/BurntSushi/toml @ `d733fc5` ("CONTRIBUTING.md with AI policy"), cloned to `~/work-repos/toml-baml-port-src`.
- Toolchain: `baml-cli` built from the BoundaryML/baml worktree `port-burntsushi-toml` (`baml_language/`, `cargo build -p baml_cli`, debug profile), copied to `.bin/baml-cli`; the baml commit is recorded in `.bin/BAML_COMMIT` (not checked in).
- Wrapper `.bin/b`: sets `BAML_AGENT_SKILL_CHECK=off` (the CLI otherwise refuses to run unless the "BAML agent skill" is installed) and filters the "internal toolchain binary" warning.
- Run the tests from the project root (the toml-test runner reads `testdata/toml-test` relative to the cwd): `cd ~/work-repos/toml-baml && .bin/b test`. One test: `.bin/b test -i TestDecodeDuration` (prefix match).
- Run the commands: `.bin/b run toml-test-decoder < x.toml`, `.bin/b run toml-test-encoder < x.json`, `.bin/b run tomlv -- tomlv --json-args '{"files":["a.toml"],"types":true,"time":false,"json":false}'`, `.bin/b run example` (aliases in `baml.toml` `[scripts]`).
- A previous (abandoned, uncommitted) session had started this port; its `lex.baml`, `error.baml`, `type_toml.baml`, `ns_go/utf8.baml`, `ns_go/fmt.baml` were reviewed and kept (with fixes); everything else was written in this session.

## File mapping and status

Every Go file in the repository has a BAML counterpart. "Faithful" means the same algorithm/structure, statement by statement where possible; deviations are documented in the file header and below.

### Library

| Go file | BAML file | Status |
|---|---|---|
| `lex.go` | `baml_src/lex.baml` | Faithful. State functions are an enum (`StateFn`) dispatched by `run_state` (a function type that returns its own type would need a recursive function-type alias). Lexes raw UTF-8 bytes (`int[]`) because BAML strings cannot hold invalid UTF-8 and Go positions are byte offsets. |
| `parse.go` | `baml_src/parse.baml` | Faithful. `any` values are the closed recursive union `Any = string \| bigint \| float \| bool \| go.Time \| Any[] \| map<string, Any> \| map<string, Any>[]`; runtime element types keep `[]map[string]any` vs `[]any` distinguishable exactly like Go's type switch. panic/recover → `throw ParseError` + `catch` in `parse`. |
| `decode.go` | `baml_src/decode.baml` | Ported with a different mechanism: see "Decoding without reflective setters" below. All `unify*` functions kept with Go's error behaviour. |
| `encode.go` | `baml_src/encode.baml` | Faithful, driven by BAML runtime reflection (`reflect.Type.of_value`, `unreflect`, `reflect.AnyClass`). |
| `meta.go` | `baml_src/meta.baml` | Faithful. `Key` is a class wrapping `string[]` (no methods on array types). Variadic `IsDefined(key ...string)` takes a list. |
| `error.go` | `baml_src/error.baml` | Faithful. Go's `error` interface + optional `Usage()` → interface `TomlError` with a default `usage()`. |
| `type_fields.go` | `baml_src/type_fields.baml` | Faithful BFS + dominance rules over the `go:"embed"` pseudo-anonymous fields. No cache (no package-level mutable state). |
| `type_toml.go` | `baml_src/type_toml.baml` | Faithful (the single-method interface collapses into a class). |
| `deprecated.go` | `baml_src/deprecated.baml` | `DecodeReader`, `PrimitiveDecode` ported; the `TextMarshaler`/`TextUnmarshaler` aliases are the interfaces themselves. |
| `doc.go` | `baml_src/doc.baml` | Package comment only. |
| `internal/tz.go` | `baml_src/internal.baml` | Package vars → functions. Local offset is 0 (see gaps). |
| (Go stdlib: `reflect`) | `baml_src/go_value.baml` | New: Go-`reflect`-like views (kind, slice/map/struct field access, struct tags, zero/comparable checks) over BAML reflection. |
| (Go stdlib: `unicode/utf8`, `strconv`, `strings`, `math`, `fmt`, `time`, `bytes`, `encoding/json.Number`, sized ints) | `baml_src/ns_go/{utf8,strconv,fmt,time,types}.baml` (namespace `go`) | New shims: UTF-8 codec, ParseInt/ParseFloat/FormatFloat('g'), Quote, `%v` printer, time.Time/Location/ParseInLocation/Format/Duration/ParseDuration, Int8…Uint64/Float32 wrapper classes, json.Number, bytes.Buffer implementing `baml.io.Read`/`Write`. |

### Internal test helpers and commands

| Go file | BAML file | Status |
|---|---|---|
| `internal/tag/add.go`, `internal/tag/rm.go` | `baml_src/ns_tag/tag.baml` | Faithful; builds `baml.json.json` directly. |
| `internal/toml-test/runner.go` | `baml_src/ns_tomltest/runner.baml` | Faithful except: files read from disk (`testdata/toml-test`, a copy of the embedded `internal/toml-test/tests`) instead of `//go:embed`; sequential instead of goroutines; no per-test timeout. `Runner.run_one` exposes the per-test goroutine body so each case is its own BAML test. |
| `internal/toml-test/json.go` | `baml_src/ns_tomltest/json.baml` | Faithful. |
| `internal/toml-test/toml.go` | `baml_src/ns_tomltest/toml.baml` | Faithful. |
| `internal/toml-test/version.go` | `baml_src/ns_tomltest/version.baml` | Faithful. |
| `internal/toml-test/tests/**` | `testdata/toml-test/**` | Data copied verbatim. |
| `cmd/toml-test-decoder/main.go` | `baml_src/ns_cmd/toml_test_decoder.baml` (+ `ns_cmd/common.baml`) | Works (`baml run toml-test-decoder < f.toml`). Prints a trailing `null` (the CLI echoes the return value). |
| `cmd/toml-test-encoder/main.go` | `baml_src/ns_cmd/toml_test_encoder.baml` | Works; same caveat. |
| `cmd/tomlv/main.go` | `baml_src/ns_cmd/tomlv.baml` | Works; flags become typed function parameters, file list via `--json-args`. `text/tabwriter` hand-rolled. |
| `_example/example.go` (+ `example.toml`) | `baml_src/ns_example/example.baml` (+ `_example/example.toml`) | Works; output identical to `TZ=UTC go run .`. |
| `ossfuzz/fuzz.go` | `baml_src/ns_ossfuzz/fuzz.baml` | Faithful; driven by `fuzz_test.baml`. |
| `cmd/*/README.md`, `COPYING`, `.github/*`, `go.mod`, `README.md`, `CONTRIBUTING.md` | — | Not code; not ported. |

### Tests

| Go file | BAML file | Status |
|---|---|---|
| `toml_test.go` | `baml_src/toml_test.baml` | Full toml-test suite (valid, encoder round-trip, invalid), metadata tests and error-message tests; one BAML test per toml-test case via a dynamic `testset`. |
| `decode_test.go` | `baml_src/decode_test.baml` | All tests ported; individual cases needing fixed-size arrays, non-string map keys or non-pointer/nil-pointer destinations are commented as `UNPORTABLE`. |
| `encode_test.go` | `baml_src/encode_test.baml` | All tests ported; chan/complex128/`[N]T` cases `ADAPTED` to BAML equivalents (function values, classes, slices). |
| `error_test.go` | `baml_src/error_test.baml` | All tests ported. |
| `lex_test.go` | `baml_src/lex_test.baml` | All tests ported. |
| `example_test.go` | `baml_src/example_test.baml` | All examples ported as tests asserting the `// Output:` block (plus an assertion for `Example_unmarshalTOML`, which has none in Go). |
| `bench_test.go` (+ `BenchmarkEscapes`/`BenchmarkKey` from `decode_test.go`) | `baml_src/bench_test.baml` | Benchmark bodies ported as functions taking `n`; tests run them with a tiny `n` and print ns/op (no benchmark harness). |
| `fuzz_test.go` | `baml_src/fuzz_test.baml` | Fuzz body ported; run on the seed corpus plus 40 deterministic PRNG mutations (no fuzzing engine). Also drives `ossfuzz.fuzz_toml`. |
| — | `baml_src/smoke_test.baml` | Extra smoke test. |

## Test results

Final full run (`.bin/b test`, 2026-09-26, debug `baml-cli`): **1301 passed, 7 failed, 1308 total.**

Go baseline for comparison: `TZ=UTC go test -count=1 -v .` in the source repo — all 1245 Go tests/subtests pass in 0.35 s.

| BAML test file (Go file) | pass | fail |
|---|---|---|
| `toml_test.baml` (`toml_test.go`) | 929 | 0 |
| `lex_test.baml` (`lex_test.go`) | 5 | 0 |
| `error_test.baml` (`error_test.go`) | 17 | 0 |
| `decode_test.baml` (`decode_test.go`) | 143 | 7 |
| `encode_test.baml` (`encode_test.go`) | 108 | 0 |
| `example_test.baml` (`example_test.go`) | 6 | 0 |
| `bench_test.baml` (`bench_test.go`) | 30 | 0 |
| `fuzz_test.baml` (`fuzz_test.go` + `ossfuzz/fuzz.go`) | 62 | 0 |
| `smoke_test.baml` (extra) | 1 | 0 |

toml-test suite (TOML 1.1.0, via the ported runner): valid 218/218, encoder round-trip 218/218, invalid 492/492, plus the meta/error-list existence check. As in Go, the ~20 cases on the skip list run with `SkipMustError` semantics (they must fail, and they do).

The 7 failures, all explained by language/runtime gaps (not port bugs):

| Test | Cause |
|---|---|
| `TestDecodeSignbit` | NaN/±Inf cannot be materialised into a class's `float` field (no JSON form; no reflective setter) — gap 3. |
| `TestMaxDepth::#05` (`a=[[…128…]]`) | VM `MAX_FRAMES = 256` → `StackOverflow` before depth 128 — gap 28. |
| `TestMaxDepth::#06`, `#07` (129-deep, expect "exceeds maximum array depth") | same: overflows before the depth check fires. |
| `TestMaxDepth::#08` (300-deep, no limit) | same. |
| `TestMaxDepth::#00` (128-part dotted key), `#02` (300-part) | exceed the 300 s default test timeout: Go's O(n³) key bookkeeping is milliseconds in Go but minutes in the (debug-build) VM — pain 29. (`#00` passed in an earlier, less loaded run.) |

Not run / unportable individual cases (commented `UNPORTABLE` in the test files): fixed-size-array destinations (`TestDecodeArrayWrongSize`, 2 `TestDecodeErrors` cases, 2 `TestDecodePrimitive` cases), non-string map keys (`TestDecodeTypes` ×3, `TestEncode` ×2), non-pointer / nil-pointer destinations (`TestDecodeTypes` ×5). Cases marked `ADAPTED` (chan/complex128/`[N]T` → function values/classes/slices) are run.

## Decoding without reflective setters (the biggest design deviation)

Go's `Decode(data, &v)` walks `v` with `reflect.Value` and sets fields in place. BAML reflection can read everything (`reflect.Type.of<T>()`, `.as_class().fields()`, `reflect.AnyClass.list_fields()`, `unreflect(t)`), but there is no reflective setter and no way to construct a class instance from a runtime `reflect.Type`. The only runtime-typed constructor is `baml.json.from_json<T>(j)` (with `T` possibly bound at runtime via `type T = unreflect(t)`).

So the port keeps Go's `unify*` structure and error semantics but each `unify*` *returns the JSON image* of the value Go would have written, given the JSON image of the value already there, and the top level materialises it with `from_json<T>`. API consequences:

- `decode<T>(s) -> Decoded<T> { value, meta }` returns the value; `decode_into<T>(s, v)` emulates decoding into a pre-populated value; `primitive_decode<T>(md, prim, v)`.
- Go's `Unmarshaler.UnmarshalTOML(any) error` (pointer receiver, mutates) becomes `unmarshal_toml(self, data: Any?) -> Self throws TomlError`, called on the zero/existing value; same for `TextUnmarshaler`.
- Missing fields keep Go zero values (`zero_json(type)`), because `from_json` requires every non-optional field.
- Values with no JSON form cannot be decoded into a class field: NaN/±Inf floats (TestDecodeSignbit fails), and interface-typed fields (worked around for a top-level `Unmarshaler`, which is returned directly).
- `Primitive` stores its undecoded value in a lossless tagged JSON form so it survives the round trip.
- Untyped destinations (`Any`, `unknown`, `map<string, Any>`) bypass JSON entirely.

## BAML language / toolchain gaps, bugs and pain points

Severity tags: **bug** (wrong behaviour / crash), **gap** (missing feature that forced a workaround or made something unportable), **pain** (works, but costly or surprising). Repros are minimal and were confirmed with the local build.

### Type system and values

1. **gap — `int` is 63-bit, no fixed-width or unsigned integers, no float32.** TOML/Go need int64: `9223372036854775807` is a compile error (`E0150 … holds -4611686018427387904 to 4611686018427387903`). Workaround: TOML integers are `bigint` restricted to the int64 range; Go's `int8…uint64`/`float32` are wrapper classes (`go.Int8 { v: int }` …) because type aliases are transparent and can't carry a size. float32 formatting (`FormatFloat(f,'g',-1,32)`) can't be reproduced.
2. **gap — no pointers / addressability / pointer receivers.** `T?` stands in for `*T`; decoding returns values; Go tests whose behaviour depends on addressability (e.g. `TestEncodeTOMLMarshaler`'s non-addressable `sound2`) had to be modelled explicitly.
3. **gap — no reflective construction or field setters** (see above). This is the one missing reflection capability that shaped the whole decoder, and it is why NaN/Inf floats can't be decoded into class fields.
4. **gap — no struct tags / user-defined attributes.** The attribute vocabulary is fixed (`@alias`, `@description`, `@skip`, …; unknown attributes are errors), and `reflect.Meta.other` is only populated for runtime-built classes. Workaround: Go tag strings are written into `@description("toml:\"name,omitempty\"")` and parsed with a port of `reflect.StructTag.Get`; `@alias`/`@skip` are also honoured.
5. **gap — no embedded (anonymous) fields and no method promotion.** Emulated with a pseudo tag `@description("go:\"embed\"")` + the original dominance rules; promoted methods (e.g. `fmtTime` getting `time.Time.UnmarshalText`) are forwarded by hand.
6. **gap — no fixed-size arrays (`[N]T`).** `TestDecodeArrayWrongSize` and the `[1]int`/`[2]int` cases of `TestDecodeErrors`/`TestDecodePrimitive` are unportable.
7. **gap — map keys must be strings.** `map[int]string` / `map[any]bool` cases unportable.
8. **gap — no methods on non-class types** (`type Enum int`, `type ints []int`, `type fun func()` with methods). Each becomes a wrapper class.
9. **gap — no package-level variables.** Go `var` tables (`dtTypes`, `versions`, `errorTests`, `internal.LocalDatetime`, …) become zero-arg functions; `cachedTypeFields`' cache is dropped. Location identity (`loc == internal.LocalDatetime`) becomes structural comparison.
10. **gap — methods must be declared inside the class body.** Go spreads `MetaData`'s methods over `meta.go` and `decode.go`; `function MetaData.unify(...)` is a syntax error, so the decode methods are free functions `md_unify(md, …)`. Also `self` cannot be used as a free function's parameter name.
11. **gap — no varargs, no printf.** Every `fmt.Sprintf`/`errorf` became a template string; `%q`, `%v`, `%f`, `%x`, `%-11s` and `strconv.FormatFloat` were hand-written (`ns_go/fmt.baml`, `ns_go/strconv.baml`). `float.to_string()` never uses exponent notation (`1e300` prints 301 digits), so Go's `'g'` format is rebuilt from the shortest digits.
12. **gap — Go strings are bytes; BAML strings are Unicode.** `string.length()`/`slice()` count code points, strings cannot hold invalid UTF-8, `string.from_utf8` throws instead of replacing. The lexer therefore works on `int[]` bytes with a hand-written UTF-8 decoder, and invalid-UTF-8 test inputs are carried as bytes end to end.
13. **gap — NaN sign is unobservable** (no `Float64bits`/`Signbit`; `-nan` prints `NaN`). `math.Signbit(NaN)` always false; `-nan` round-trips as `nan`.
14. **pain — numeric conversions:** no `int → bigint` or `int → float` conversion functions (use `0n + i`, `0.0 + i`), `bigint → float` only via `float.parse(b.to_string())`.
15. **pain — `panic`s are not catchable**, so Go's `panic`/`recover` (parser errors, `encPanic`, the toml-test decoder's `recover`) are emulated with thrown values (`ParseError`, `TomlEncodeError`, a `Panic` class).
16. **pain — no `defer`, no labelled `continue`/`break`** (`continue outer` in `Key.String`), no `goto`; rewritten with flags/explicit cleanup.

### Compiler bugs and surprising diagnostics

17. **bug — an interface implementation calling a same-named inherent method recurses forever.** Inside `implements Err { function error(self) … { self.error() } }`, `self.error()` resolves to the interface method itself, not the class's own `error()`; runtime `StackOverflow`. This made all ~500 invalid-TOML tests overflow until the inherent method was renamed.
    ```baml
    interface Err { function error(self) -> string throws never; }
    class E {
        msg: string,
        function error(self) -> string { self.msg }
        implements Err { function error(self) -> string throws never { self.error() } }
    }
    function main() -> string { let e: Err = E { msg: "hi" }; e.error() }  // StackOverflow
    ```
18. **bug — `&&` does not narrow its right-hand side.** `function f(s: string?) -> bool { s != null && s.length() > 0 }` → `E0007 type string | null has no member length`. Needed nested `if`s in ~8 places.
19. **bug — calling a `-> never` function does not narrow afterwards**, and a block `{ die(); }` is typed `void`, not `never`:
    ```baml
    function die() -> never { throw "x" }
    function f(s: string?) -> int { if (s == null) { die(); } s.length() }  // E0007
    ```
    (`throw` directly does narrow; `x ?? die()` works.)
20. **bug — matching a string against literal patterns narrows to a literal union that has lost `string`'s methods:** `match (v) { "a" | "bb" => v.length(), _ => 0 }` → `E0007 type "a" | "bb" has no member length`.
21. **bug — a bound method used without parentheses silently becomes a value.** `encode_value(key, p.undecoded)` (meant `p.undecoded()`) type-checked against an `unknown` parameter and failed at runtime with "unsupported type … func". A lint for passing a method reference where a value of type `unknown` is expected would have caught it.
22. **bug — string escapes differ between `.baml` files and `baml run -e`, and unknown escapes are silently kept.** In a `.baml` file only `\n \t \r \0 \\ \"` are processed; `\xNN`, `\uNNNN` and `\u{…}` are kept *literally* (no diagnostic). The same literal passed to `baml run -e` does process `\uNNNN`:
    ```baml
    function main() -> int[] { "\x41\u0041\u{41}".to_code_points() }
    // file:  [92, 120, 52, 49, 92, 117, 48, 48, 52, 49, 92, 117, 123, 52, 49, 125]   (all literal)
    // run -e '"\x41\u0041\u{41}".to_code_points()' -> [92, 120, 52, 49, 65, 92, 117, 123, 52, 49, 125]
    ```
    This silently broke two expected strings and two shim constants (U+FFFD, DEL) in the port; they were rewritten with concatenation / `string.from_code_points`.
23. **pain — flow-narrowed literal types** (from the earlier session): `let size: int = 0; if (c) { size = 2 } else { size = 3 }; n < size` → `E0004 cannot order int and 2|3`.
24. **pain — field narrowing:** `if (self.err != null) { self.err.usage() }` does not narrow; a local copy is needed.
25. **pain — `throws` rules are asymmetric.** Interface methods and *every function type* (`() -> null` in a field or a closure type) must declare `throws` (`E0151`), but an implementation may not declare an unnecessary one (`E0097 throws unknown is unnecessary`). Changing a helper to call `go_panic` ripples `E0096` errors through every declared `throws` up the call graph.
26. **pain — a match arm whose body is a map literal** (`let s: string => { "t": "s", "v": s }`) parses as a block; needs parentheses. A `match` arm `_ => {}` in a value position silently yields `void` (reported only as a type mismatch elsewhere).
27. **pain — `test` is a keyword** (can't name a parameter `test`, as Go code does).

### Runtime

28. **bug/limit — the VM has a hard `MAX_FRAMES = 256` call-depth limit** (`bex_vm/src/vm.rs`). `depth(300)` of a trivial recursive function overflows. The parser's (faithful) recursion uses ~2–3 frames per nesting level, so Go's default `MaxDepth(128)` can never be reached: 4 `TestMaxDepth` cases fail with `StackOverflow` instead of the expected result/error.
29. **pain — speed.** The whole Go suite runs in 0.35 s; the BAML suite takes minutes (debug build of the CLI, shared machine). `TestMaxDepth#02` (Go's O(n³) key bookkeeping for a 300-part dotted key) does not finish within the 300 s default test timeout. Every CLI invocation spends ~4–10 s compiling before running anything.

### Toolchain / CLI / test runner

30. **pain — `baml` refuses to run without the "agent skill"** unless `BAML_AGENT_SKILL_CHECK=off`.
31. **gap — no package dependencies for user packages**, so `cmd/*` and `_example` can't be separate programs importing the library; they live as namespaces (`ns_cmd`, `ns_example`) inside the library package and are exposed via `[scripts]`.
32. **pain — `baml run` always prints the function's return value** (a trailing `null` after the command's own output), so ports of CLI tools cannot reproduce exact stdout. `bool` parameters are `--flag true|false` (not switches) and list parameters can only be passed via `--json-args`.
33. **gap — no file embedding** (`//go:embed`): tests read `testdata/` relative to the cwd, so the suite must be run from the project root. No temp-file API (`os.CreateTemp`); a fixed `/tmp` path is used.
34. **pain — the test runner buffers all output until the end.** A hanging test gives no progress indication; bisecting required running groups separately. `-i` is a prefix match (so `-i probe_x` also runs `probe_x2`); glob `*` is not supported in selectors.
35. **pain — a `testset` whose collector body throws/panics reports only `(failed to expand)`**, without the panic message. (Cause here: `baml.random.Xoshiro256PlusPlus.new(seed = …)` panics with "Rng seed must be at least 32 bytes" — a 31-byte seed; found only by re-running the expression with `baml run -e`.)
36. **pain — no stdin "read all" API**; `baml.io.input` is line-based and can't distinguish an empty line from EOF. Workaround: `baml.fs.open("/dev/stdin", "r").bytes()`.
37. **pain — no benchmark or fuzz harness** (`testing.B`, `testing.F`); both are emulated (fixed `n`, seeded PRNG mutations).

### Things that worked well

- **Dynamic testsets** (`testset "X" { for (…) { test name { … } } }`) map one-to-one onto Go's table-driven `t.Run` subtests, including the ~930-case toml-test suite.
- **Runtime reflection** is rich enough for a reflection-driven encoder: `reflect.Type.of_value`, `unreflect(t)` + narrowing `let x: E[] = v else { … }` to view containers with runtime element types, `reflect.AnyClass` field iteration, `Type.implements`, and interface narrowing of `unknown` values (`let m: Marshaler = v else …`).
- Runtime types on containers make `[]map[string]any` vs `[]any` distinguishable by `match`, exactly what the Go parser relies on.
- `baml.io.Read`/`Write` interfaces are a good fit for `io.Reader`/`io.Writer`; `spawn`/`await` handled `TestDecodeParallel`.
- `baml describe` made the stdlib discoverable.

## Final summary

- **Every Go source and test file has a BAML counterpart** (table above): the full library (lexer, parser, decoder, encoder, metadata, errors, struct-field resolution), the internal toml-test runner and tag helpers, the three commands, the example program, the OSS-Fuzz target, and all test files including benchmarks and the fuzz test. ~14k lines of BAML in `baml_src/`, including ~1.7k lines of Go-stdlib shims (`ns_go`) that BAML's stdlib doesn't cover in Go-compatible form.
- **1301 of 1308 tests pass**, including the entire toml-test conformance suite (valid, invalid and encoder round-trips) with the error messages and error positions that the Go tests check matching exactly.
- **Faithfulness:** lexer/parser/encoder/metadata/errors are statement-by-statement ports. The decoder keeps Go's structure and error semantics but, lacking reflective setters/constructors, builds a JSON image and materialises it with `baml.json.from_json<T>` (see above). Go-only features are emulated: struct tags via `@description`, embedded fields via a `go:"embed"` pseudo-tag, pointers via optionals, sized ints via wrapper classes, `panic`/`recover` via thrown values.
- **Most impactful gaps:** (1) no reflective construction/setters, (2) 63-bit `int` and no sized/unsigned ints or float32, (3) no struct tags / custom attributes, (4) 256-frame VM call-depth limit, (5) string escapes silently not processed in files, and the interface-method self-recursion bug. The narrowing gaps (`&&`, `never` calls, literal unions) were the most frequent day-to-day friction.
- **What worked well:** dynamic testsets, runtime reflection for reading values and types (`unreflect`, `AnyClass`, interface narrowing of `unknown`), runtime-typed containers, `io.Read`/`Write`, `spawn`.
