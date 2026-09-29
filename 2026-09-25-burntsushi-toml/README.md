# BurntSushi/toml → BAML

A port of the Go TOML library [BurntSushi/toml](https://github.com/BurntSushi/toml) to [BAML](https://github.com/BoundaryML/baml). It was an experiment to see how far the new BAML language gets today.

- **Ported from:** https://github.com/BurntSushi/toml
- **Upstream commit:** [`d733fc535e4a9f3c454e421a87b90ade5d49bf31`](https://github.com/BurntSushi/toml/commit/d733fc535e4a9f3c454e421a87b90ade5d49bf31) (`v1.6.0-17-gd733fc5`, "CONTRIBUTING.md with AI policy", 2026-08-18)
- **BAML toolchain:** `baml-cli` built from BoundaryML/baml at [`e215c3de2d`](https://github.com/BoundaryML/baml/commit/e215c3de2d4b90333244af12efde8c0cc5298d9f)

Every Go source and test file has a BAML counterpart. The toml-test conformance suite passes 928/928, and 1303 of 1308 BAML tests pass on a release build. The 5 failures come from BAML limitations: NaN/±Inf can't cross the JSON bridge, and the VM has a 256-frame call-depth limit.

- Library: `baml_src/*.baml` (`lex`, `parse`, `decode`, `encode`, `meta`, `error`, …) plus Go stdlib shims in `baml_src/ns_go/`
- Tests: `baml_src/*_test.baml`; conformance data in `testdata/`
- Example: `_example/`

See [PORTING_NOTES.md](PORTING_NOTES.md) for the file mapping, test results, design decisions, and the BAML gaps found along the way. Paths in the notes (`~/work-repos/...`, `.bin/b`) refer to the machine the port was done on.

License: MIT (see `COPYING`), same as the original.
