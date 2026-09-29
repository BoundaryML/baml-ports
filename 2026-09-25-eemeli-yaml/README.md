# eemeli/yaml → BAML

A port of the JavaScript/TypeScript YAML library [eemeli/yaml](https://github.com/eemeli/yaml) to [BAML](https://github.com/BoundaryML/baml). It was an experiment to see how far the new BAML language gets today.

- **Ported from:** https://github.com/eemeli/yaml
- **Upstream commit:** [`528ef30d6ded4bd9f2c3521b670eb2b29d503c5c`](https://github.com/eemeli/yaml/commit/528ef30d6ded4bd9f2c3521b670eb2b29d503c5c) (`v3.0.0-2-7-g528ef30`, "feat: Include context arg in reviver calls + serialize raw JSON values (#726)", 2026-09-23)
- **BAML toolchain:** `baml-cli` built from BoundaryML/baml at [`e215c3de2d`](https://github.com/BoundaryML/baml/commit/e215c3de2d4b90333244af12efde8c0cc5298d9f)

All 79 upstream source files and 23 test files are ported. 3413 of 3420 tests pass, including all 2089 yaml-test-suite checks. The 7 failures are JS/BAML semantic differences (reference identity, array holes, lone UTF-16 surrogates) or the VM's 256-frame call-depth limit.

- Library: `baml_src/src/` (one file per upstream file); JS runtime shim in `baml_src/src/js.baml`
- Tests: `baml_src/tests/`; test generators in `tools/`
- Run: `source env.sh && $B test`. `env.sh` points at a locally built `baml-cli`; edit it for your machine.

See [PORTING_NOTES.md](PORTING_NOTES.md) for results, decisions and BAML gaps, [TEST_PORTING_GUIDE.md](TEST_PORTING_GUIDE.md) for the test conventions, and `notes/` for per-file porting reports.

License: ISC (see `LICENSE`), same as the original.
