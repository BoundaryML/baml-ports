# tomli-baml

A port of [tomli](https://github.com/hukkin/tomli) (a TOML 1.1 parser for Python) to [BAML](https://github.com/BoundaryML/baml). It was an experiment to see how far the new BAML language gets today.

- **Ported from:** https://github.com/hukkin/tomli
- **Upstream commit:** [`5a77b12a7a9f052ce5a20c335d2825658f6aea52`](https://github.com/hukkin/tomli/commit/5a77b12a7a9f052ce5a20c335d2825658f6aea52) (`2.4.1-4-g5a77b12`, "Use frozendict on Python 3.15", 2026-04-14)
- **BAML toolchain:** `baml-cli` built from BoundaryML/baml at [`e215c3de2d`](https://github.com/BoundaryML/baml/commit/e215c3de2d4b90333244af12efde8c0cc5298d9f)

```baml
let doc = root.tomli.loads("answer = 42\n[table]\nkey = 'value'");
// {"answer": 42, "table": {"key": "value"}}   (42 is a bigint)
```

- Library: `baml_src/ns_tomli/` (`loads`, `load`, `TOMLDecodeError`, `Value`)
- Tests: `baml_src/ns_tests/` (`baml test`, run from the repo root)
- Benchmark and profiler workloads: `baml_src/ns_benchmark/`, `baml_src/ns_profiler/`

See [PORTING_NOTES.md](PORTING_NOTES.md) for the file mapping, test results, design decisions, and the list of BAML gaps found along the way.

License: MIT (see `LICENSE`), same as the original.
