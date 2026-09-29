# tomli → BAML porting notes

A port of [hukkin/tomli](https://github.com/hukkin/tomli) (Python TOML parser, commit `5a77b12`, v2.4.1) to the new BAML language, built from the BoundaryML/baml checkout at `e215c3de2d` (`baml_language/`, `cargo build -p baml_cli`). The compiler/runtime was not modified; this measures how far the language gets today.

## Final summary

- **Every source file and every test file is ported** (or documented as not portable). The parser is a line-by-line port of `_parser.py`/`_re.py`, not a stub: same function names, same control flow, same error messages, same positions.
- **Tests: 16/16 BAML tests pass** (debug and release `baml-cli`). That covers **744/744 data cases** (516 invalid, of which 11 are skipped for non-UTF-8 input exactly as in Python; 228 valid). 15 of the 18 original test methods are ported and pass. The other 3 cannot be expressed in BAML (they test Python's dynamic-typing `TypeError`s, or lazy imports), and 1 port-specific test was added.
- **Workarounds were needed for**: no module-level constants, no tuples, no varargs or positional defaults, no inheritance, no sets, a 63-bit `int`, a **256-frame VM call stack** (worked around by hopping to a fresh `spawn`ed task every 20 nesting levels, which keeps Python's 1000-level limit), and a number of type-narrowing gaps.
- **Performance**: the release build parses `benchmark/data.toml` (4 KB) in ~14 ms, about 50× slower than CPython tomli (0.3 ms) and ~150× slower than BAML's built-in Rust TOML parser. The debug build is another ~20–30× slower. Two VM/stdlib performance problems were found and worked around along the way (see "Performance").
- The categorized gap list below is the main deliverable. Minimal repros are in `repros/` (run `repros/run.sh`).

## How to build / run

```sh
# toolchain (from the baml checkout)
cd baml_language && cargo build -p baml_cli --bin baml-cli      # debug
cargo build --release -p baml_cli --bin baml-cli                # release (for benchmarks)

# this project keeps copies in .tools/ (gitignored) plus wrappers:
.tools/b  test            # debug baml-cli, sets BAML_AGENT_SKILL_CHECK=off
.tools/br test            # release baml-cli
.tools/br run benchmark.main
.tools/br run -e 'root.profiler.timings()'
repros/run.sh $PWD/.tools/baml-cli        # minimal language-gap repros
```

Run from the project root: the tests locate `tests/data` relative to the working directory (override with `TOMLI_TEST_DATA`).

## File mapping and status

| Original | BAML | Status |
|---|---|---|
| `src/tomli/__init__.py` | `baml_src/ns_tomli/__init__.baml` | ✅ `__version__()`; `__all__`/re-exports not needed (a namespace is shared by all its files) |
| `src/tomli/_parser.py` | `baml_src/ns_tomli/_parser.baml` | ✅ full port (all functions, `Flags`, `NestedDict`, `Output`, `TOMLDecodeError` incl. the deprecated free-form constructor) |
| `src/tomli/_re.py` | `baml_src/ns_tomli/_re.baml` | ✅ full port (regexes, `match_to_*`, `cached_tz` without the cache) |
| `src/tomli/_types.py` | `baml_src/ns_tomli/_types.baml` | ✅ plus an explicit `Value` union (Python: `Any`) |
| `src/tomli/py.typed` | — | N/A (PEP 561 marker; BAML is always typed) |
| *(Python builtins)* | `baml_src/ns_tomli/_compat.baml` | port-only: `ValueError`/`TypeError`/`KeyError`/`RecursionError`, `repr()`, `int(s, 0)`, `float(s)`, `str.find/count/rindex`, `chr`, `frozenset` (`CharSet`), `warnings.warn`, `sys.getrecursionlimit` |
| `tests/__init__.py` | `baml_src/ns_tests/__init__.baml` | ⚠️ not portable (the `import tomli as tomllib` alias); documented |
| `tests/burntsushi.py` | `baml_src/ns_tests/burntsushi.baml` | ✅ (`convert`, `normalize`, and Python `isoformat`/`str(date)` helpers) |
| `tests/test_data.py` | `baml_src/ns_tests/test_data.baml` | ✅ 2/2 tests; 744/744 subtests |
| `tests/test_error.py` | `baml_src/ns_tests/test_error.baml` | ✅ 6/7 tests pass; `test_type_error` not portable; `assertWarns` part of `test_deprecated_tomldecodeerror` not portable |
| `tests/test_misc.py` | `baml_src/ns_tests/test_misc.baml` | ✅ 7/9 tests pass; `test_incorrect_load` and `test_lazy_import` not portable; +1 port addition |
| `tests/data/**` | `tests/data/**` | copied verbatim |
| `benchmark/run.py` | `baml_src/ns_benchmark/run.baml` | ✅ competitor Python parsers replaced by BAML's builtin `baml.toml` as baseline; default run count lowered |
| `benchmark/data.toml`, `LICENSE` | `benchmark/` | copied |
| `profiler/profiler_script.py` | `baml_src/ns_profiler/profiler_script.baml` | ✅ workload only (no cProfile/tox hook in BAML) |
| — | `baml_src/ns_profiler/timings.baml` | port-only micro-timings used to find hotspots |
| `fuzzer/fuzz.py` | — | ❌ not portable: needs `atheris` (coverage-guided fuzzing engine) and `tomli_w` (TOML writer); no BAML equivalents |
| `scripts/use_setuptools.py`, `scripts/mypyc_tox` | — | ❌ N/A: Python packaging / mypyc build tooling |
| `setup.py`, `pyproject.toml`, `.bumpversion.cfg`, `.flake8`, `.pre-commit-config.yaml`, `.github/` | `baml.toml` | N/A: Python packaging/CI config |
| `README.md`, `CHANGELOG.md`, `tomllib.md` | `README.md` (port) | not ported (docs) |

## Test results

Run with the locally built `baml-cli test` (debug: ~11–18 s; release: ~1–2 s).

| BAML test | Original | Result |
|---|---|---|
| `TestData::test_invalid` | `test_data.py::test_invalid` | PASS: 516/516 (11 non-UTF-8 files skipped, as in Python) |
| `TestData::test_valid` | `test_data.py::test_valid` | PASS: 228/228 |
| `TestError::test_line_and_col` | same | PASS |
| `TestError::test_missing_value` | same | PASS |
| `TestError::test_invalid_char_quotes` | same | PASS |
| — | `TestError::test_type_error` | NOT PORTABLE (static types make `loads(b"...")` a compile error) |
| `TestError::test_invalid_parse_float` | same | PASS |
| `TestError::test_deprecated_tomldecodeerror` | same | PASS (the `args` checks; `assertWarns` cannot be observed) |
| `TestError::test_tomldecodeerror` | same | PASS |
| `TestMiscellaneous::test_load` | same | PASS |
| — | `TestMiscellaneous::test_incorrect_load` | NOT PORTABLE (`baml.fs.File` has no text mode) |
| `TestMiscellaneous::test_parse_float` | same | PASS (a minimal `D` class stands in for `decimal.Decimal`) |
| `TestMiscellaneous::test_deepcopy` | same | PASS (`baml.deep_copy`) |
| `TestMiscellaneous::test_inline_array_recursion_limit` | same | PASS (470 levels; 1002 → `RecursionError`) |
| `TestMiscellaneous::test_inline_table_recursion_limit` | same | PASS (310 levels; 1002 → `RecursionError`) |
| `TestMiscellaneous::test_key_recursion_limit` | same | PASS |
| `TestMiscellaneous::test_types_import` | same | PASS (adapted: the aliases resolve) |
| — | `TestMiscellaneous::test_lazy_import` | NOT PORTABLE (skipped by the original below Python 3.15 anyway) |
| `PortAdditions::inline_nesting_at_the_limit_parses` | — | PASS (port-only: exactly `MAX_INLINE_NESTING()` levels parse) |

Totals: **16 passed, 0 failed**. Of the 18 original test methods, 15 are ported (all pass) and 3 are not portable.

Before the stack workaround (next section), the two inline recursion-limit tests failed on their first step: 470 nested arrays and 310 nested tables overflowed the VM stack.

## Key design decisions

- **Value type.** Python returns `dict[str, Any]`. BAML containers are invariant and carry their element type at run time, so an `unknown`-typed tree cannot be matched on reliably. The port declares a closed recursive union `Value = string | bool | bigint | float | ZonedDateTime | PlainDateTime | PlainDate | PlainTime | CustomFloat | Value[] | map<string, Value>`.
- **Integers are `bigint`.** BAML's `int` is 63-bit (±2^62), which can't hold TOML's int64 range, and Python ints are unbounded anyway.
- **Dates/times** map to `baml.time`: an offset datetime is `ZonedDateTime` with a `TimeZoneOffset`, a local datetime is `PlainDateTime`, a local date is `PlainDate`, and a local time is `PlainTime`. Python's `datetime` rejects year 0 and `PlainDate` accepts it, so `match_to_datetime` checks the year explicitly.
- **`parse_float`** is `((string) -> Value)?` passed by name. `null` means Python's default `float`, because BAML can't compare function values for identity, which is how the original spots the default. Custom return types, like the test's `Decimal`, implement the `CustomFloat` interface.
- **`TOMLDecodeError`** is a class with `args`/`msg`/`doc`/`pos`/`lineno`/`colno` and a `to_string()` that mirrors `str(exc)`. `TOMLDecodeError.new(msg, doc, pos)` is the normal constructor. `TOMLDecodeError.from_args(unknown[])` reproduces Python's `__init__(*args)` dispatch, including the deprecated free-form path.
- **Exceptions**: Python's builtin exception classes are flattened into independent classes in `_compat.baml`. Anywhere Python catches `ValueError`, BAML must name both `ValueError | TOMLDecodeError` (`ValueErrorLike`).
- **Module constants** such as `ILLEGAL_BASIC_STR_CHARS` and `RE_NUMBER` become zero-argument functions, rebuilt on each call.
- **Tuples** become generic `Tuple2<A, B>`/`Tuple3<A, B, C>` classes.
- **Deep nesting**: `_nested()` in `_parser.baml` runs every 20th nesting level on a freshly `spawn`ed task. Each task gets a fresh 256-frame VM stack, and thrown errors propagate unchanged through `await`. With this, `MAX_INLINE_NESTING` can stay `getrecursionlimit()` (1000), as in the original.

## BAML language / toolchain gaps, bugs and pain points

Severity tags: **[crash]** > **[wrong-result]** > **[spurious-error]** (valid code rejected) > **[missing-error]** > **[perf]** > **[missing-feature]** > **[ergonomics]** / **[diagnostic]**. `rNN` refers to `repros/rNN_*.baml`.

### 1. Missing language features

1. **No module-level constants** [missing-feature] (`r07`). `const X = 1;` or `let X = 1;` at top level gives E0010 "top-level `let` bindings are not supported"; for `const`, the message wrongly says `let`, which is a [diagnostic] issue too. Every `Final` constant became a function that rebuilds its value, whether a character set, an escape map, or a regex, on every call. Regexes can't be compiled once and cached, which is the biggest remaining performance cost, and nothing can be memoized (`functools.lru_cache` on `cached_tz` was dropped).
2. **No tuple types** [missing-feature]. Worked around with generic `Tuple2`/`Tuple3` classes. Destructuring a generic class requires explicit type arguments and `let` per field (`let Tuple2<int, string> { first: let a, second: let b } = …`). It also can't assign into existing variables, which the Python idiom `pos, key = parse_key(src, pos)` needs, so the port uses `let r = …; pos = r.first;`.
3. **Defaulted parameters must be passed by name; no varargs** [missing-feature] (`r08`). Python's `TOMLDecodeError(msg=DEFAULT, doc=DEFAULT, pos=DEFAULT, *args)` can't be declared. Worked around with `new(msg, doc, pos)` plus `from_args(args: unknown[])`. On the upside, Python's keyword-only `*, parse_float=float` maps cleanly onto BAML's named-only defaults.
4. **No class inheritance** [missing-feature]. `TOMLDecodeError(ValueError)` can't be expressed, so catch sites must list both types.
5. **No set type, and map keys must be `string`** [missing-feature]. `frozenset[str]` is replaced by a string-backed `CharSet`. `set[int]` flags use an enum array with `includes`, and `set[tuple]` uses a class array deduplicated by structural `==`.
6. **No `\xNN` / `\uNNNN` / `\u{…}` string escapes** in either `"…"` or backtick strings (`r05`). They are **silently kept literally** instead of being rejected [missing-error]: `"\u{1b}".length()` is 6. Control characters have to be built with `baml.String.from_code_points`.
7. **No namespace alias / import**, so `tests/__init__.py`'s `import tomli as tomllib` is not portable.
8. **No `__file__` or source-location API**, so test data paths depend on the working directory.
9. **No warnings machinery**. `warnings.warn` becomes `log.warn`, and `assertWarns` can't be tested.
10. **`match` is a reserved word** [ergonomics / diagnostic] (`r06`). It can't be a parameter name (tomli uses `match` in `_re.py`). The error is a cascade of ~10 "unexpected token" errors instead of a single "`match` is a keyword".
11. **Test blocks can't be generated dynamically**, so `unittest.subTest` per data file becomes a loop that collects failures.

### 2. Type-checker bugs and limitations

1. **No narrowing across `||`** [spurious-error] (`r01`). `if (d == null || d >= base)` gives E0004 "cannot order `int | null` and `int`". The same happens with `best == null || secs < best`. Workaround: split into nested `if`s.
2. **A `never`-returning call used as a statement doesn't end the flow for narrowing** [spurious-error] (`r02`). After `if (idx == null) { baml.sys.panic("…"); }`, `idx` is still `int | null`. Workaround: an `if/else` expression.
3. **`?.` on a `map<string, T?>.get()` result is rejected** [spurious-error] (`r03`). `m.get(k)?.text` gives E0007 "type `G | null` has no member `text`": the doubly-optional result isn't flattened.
4. **Closures lose the flow-narrowing of captured variables** [spurious-error] (`r04`). After `if (f == null) { return …; }`, calling `f` inside a closure gives E0006 "`… | null` is not a function". Workaround: re-bind to a narrowed local first.
5. **Declared `throws` must be exact** [ergonomics] (`r09`). `(s: string) -> Value throws unknown { … }` gives E0097 "imprecise/unnecessary". You can't widen a closure's throws to document that it matches a `ParseFloat` alias. Omitting the clause works because throws are covariant.
6. **Explicit `throws` is required on interface methods (E0170) and inline function types (E0151)**, but not on ordinary functions [ergonomics].
7. **Generic classes are invariant** [by design, ergonomics]. `Tuple2<int, string>` isn't a `Tuple2<int, Value>`, so a copy (`_widen`) is needed. Arrays and maps need the same care when building `Value` literals: `let arr: Value[] = []`, not `[]`.
8. Positive observation: `!(x is string)` in an early-return `if` **does** narrow afterwards, and so does a guard after `if (x == null) { return …; }`.

### 3. Runtime / VM

1. **Call stack capped at 256 frames** (`bex_vm::vm::MAX_FRAMES`, not configurable, not queryable) [missing-feature]. **Overflow is an uncatchable panic**, and even `catch_all` doesn't catch it (`r10`). Python's default is 1000 frames. tomli's recursive descent uses 2–3 frames per nesting level, so it hit this at 83 nested inline tables / 123 nested arrays. Workaround: every spawned task has its own 256-frame stack, so the parser hops to `await spawn { … }` every 20 levels (`_nested`). This is cheap, and typed errors propagate through `await`.
2. **Panics are uncatchable**, so a panicking data file in a `subTest`-style loop would abort the whole test. No file panics, so this didn't bite in practice.
3. **Slow failing run-time type test against a recursive alias** [perf] (`r11`). `v is V[]` or a `match` arm `let a: V[]` costs ~13 µs when it *fails* for a 3-member alias, ~27 µs for 7 members, and **~170 µs** for tomli's 11-member `Value`, all in a release build. A succeeding test is ~0 µs. Before the workaround (scalar arms first, dict check before list check), this was 60% of total parse time. `is_dict_or_list(true)` took 345 µs.
4. **`Array.join` is slow** [perf] (`r12`). It's implemented in BAML and calls `string.from` per element: ~150–400 µs for 33 one-character strings in a release build, versus ~10 µs for a manual concatenation loop.
5. **Debug build is ~20–30× slower than release**: 4 KB parse is 2.3 s in debug vs 74 ms in release before tuning. `cargo build` defaults to debug, so casual timing is misleading.

### 4. Standard library gaps

1. `string.index_of` has **no start offset** (Python `str.find(sub, start)`). The port slices first, which is O(n) per call. `baml.regex._index_of_from` does exactly this but is private.
2. `baml.regex` has **no anchored "match at position"** (Python `pattern.match(s, pos)`) and **no accessor for a compiled regex's pattern**. The port keeps pattern *strings*, and on every call compiles `^(?:…)` against a slice. Rust-regex extended syntax (`(?P<name>…)`) does work.
3. `baml.Bigint.parse` / `baml.Int.parse` only take decimal: no radix and no `_` separators. `baml.Float.parse` rejects `_`. Python's `int(s, 0)` and `float(s)` were reimplemented.
4. `float.to_string()` doesn't follow Python's `repr` (`1e16` renders as `"10000000000000000.0"`, and infinity/NaN as `"Infinity"`/`"NaN"`). The tests normalize both sides the same way.
5. `PlainTime`/`PlainDateTime` have `millisecond()` but **no `microsecond()`/`nanosecond()` accessor**. The port reads the "private" `_nanoseconds` field, which works because BAML has **no field visibility**.
6. `PlainDate` accepts year 0 (ISO astronomical numbering). Python requires 1..9999.
7. `assert.is_true` takes **no message**, unlike Python's `assert cond, "msg"`.
8. No `tempfile`. `test_load` builds a directory from `TMPDIR` plus the pid.
9. `baml.fs.File` has no text mode.

### 5. Toolchain / CLI

1. **`baml-cli` refuses to run unless the "BAML agent skill" is installed** [ergonomics]: "error: the BAML agent skill is required but is not installed; run `baml agent install`…". Set `BAML_AGENT_SKILL_CHECK=off` or pass `--agent-skill-check off` to bypass. `baml agent install` writes into `.claude/skills` and `.agents/skills`, which I didn't want in someone's repo during an experiment.
2. **Every `baml check`/`test`/`run` prints ~11 `warning[E0146]: unreachable code` diagnostics from the *stdlib*** (`csv.baml`, `iter.baml`, `stream.baml`, `wire.baml`, `mcp.baml`) [diagnostic noise]. These likely come from `f603110e74` ("diagnose constant conditions and unreachable code").
3. `baml run` / `baml test` start in ~1–5 s with the debug build, which slows the edit-check loop.
4. `log.warn` output goes straight into `baml test` output. Fine, but nothing can capture it.
5. `TEST_INSTRUCTIONS.md`'s example bug ("a `let`-bound local inside a `test` block does not compare equal to a literal") **no longer reproduces**. The doc and several corpus comments are stale.
6. `baml fmt` works, but it moves trailing `//` comments on multi-line `+` chains to one space and re-indents continuation lines. Harmless.

### What worked well

- Recursive union aliases, `match` with typed bindings, `is`, `if let`, generic classes, closures, interfaces in unions (`CustomFloat`), `catch` with typed arms, `defer`, `baml.deep_copy`, structural `==` on nested maps/arrays/classes, and `baml.time`/`baml.regex`/`baml.glob`/`baml.fs`/`baml.json` all worked as documented.
- Typed errors propagate through `spawn`/`await`, which made the stack workaround a 10-line change.
- `baml describe` answered every stdlib question without reading the source.
- The whole parser compiled and passed all 744 data cases on its first successful compile. The only issues after that were in the test harness and performance.

## Performance

`benchmark/data.toml` (4 KB). Times are per `loads`:

| | time |
|---|---|
| CPython 3.13 + tomli (pure Python) | 0.30 ms |
| BAML builtin `baml.toml.Table.parse` (Rust), release | 0.10 ms |
| BAML port, release, first working version | 74 ms |
| BAML port, release, after workarounds for §3.3/§3.4 | 14 ms |
| BAML port, debug, first working version | 6.8 s |

The largest remaining cost is regex compilation. A value that reaches the regex path compiles up to three anchored regexes, because they can't be cached (§1.1). 100 `k = 12345` lines take ~20 ms, versus ~1 ms for 100 `k = true` lines. The O(n) tail slices used to emulate `startswith(…, pos)`/`find(…, start)` (§4.1) come next.
