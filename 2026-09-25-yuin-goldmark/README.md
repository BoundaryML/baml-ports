# yuin/goldmark → BAML

A port of the Go CommonMark/Markdown parser [yuin/goldmark](https://github.com/yuin/goldmark) to [BAML](https://github.com/BoundaryML/baml). It was an experiment to see how far the new BAML language gets today.

- **Ported from:** https://github.com/yuin/goldmark
- **Upstream commit:** [`7117ae6fc004749f20de6fb36fb691716495958d`](https://github.com/yuin/goldmark/commit/7117ae6fc004749f20de6fb36fb691716495958d) (`v2.1.5-4-g7117ae6`, "chore: change update-readme workflow interval", 2026-09-21)
- **BAML toolchain:** `baml-cli` built from BoundaryML/baml at [`e215c3de2d`](https://github.com/BoundaryML/baml/commit/e215c3de2d4b90333244af12efde8c0cc5298d9f)

Every Go source and test file is ported, including all extensions. It passes CommonMark 652/652 and renders byte-identically to Go goldmark under differential fuzzing. 51 of 56 tests pass; the failures are goldmark's wall-clock performance tests, because the port is about 250× slower than Go.

- Library: `baml_src/` (Go packages map to `ns_*` namespaces, e.g. `parser` → `ns_parser`)
- Test data: `testdata/`; benchmark: `_benchmark/`; tools: `tools/`
- Run: `bin/b test`. `bin/b` wraps a locally built `baml-cli`; edit its path for your machine.

See [PORTING_NOTES.md](PORTING_NOTES.md) for results, decisions and BAML gaps, and [PORTING_CONVENTIONS.md](PORTING_CONVENTIONS.md) for the porting rules.

License: MIT (see `LICENSE`), same as the original.
