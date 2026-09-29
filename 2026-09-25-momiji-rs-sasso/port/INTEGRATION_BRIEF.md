# Integration-test porter brief (phase 5: `tests/`, `examples/`, `benches/`)

The whole `src/` crate is ported to BAML and verified: all 982 corpus cases,
Bootstrap 5.3, error diagnostics and source maps come out byte-identical to
the Rust `sasso`. Your job is to port one of the Rust **integration test
crates** (`tests/*.rs`) — or the examples/benches — line by line, and make
the tests pass. Your assignment: `port/units/<UNIT>.md`.

Read first: `port/TEST_BRIEF.md` (test conventions — they apply here too),
`PORTING_GUIDE.md` §13 and §15, the BAML skill `.claude/skills/baml-core/SKILL.md`.
Sources: `port/upstream/sasso/`.

## Mapping
* `tests/<name>.rs` → `baml_src/ns_tests/ns_<name>/<name>.baml`, namespace
  `root.tests.<name>`. A file split between several units: part 1 writes
  `<name>.baml`, part k writes `<name>_p<k>.baml` in the same directory (same
  namespace — they are concatenated later). Only touch your own file.
* `examples/<name>.rs` → `baml_src/ns_examples/ns_<name>/<name>.baml`
  (`root.examples.<name>`), its `fn main()` a BAML `function main()` runnable
  with `baml run examples.<name>.main`. `benches/compile.rs` →
  `baml_src/ns_benches/ns_compile/compile.baml`: the divan benchmarks become
  plain functions that time `root.compile` with `root.std.now_nanos()` and a
  `main()` that prints a table; keep the corpus list and names.
* The crate under test is `sasso::…` = the ported library: `sasso::compile`
  → `root.compile`, `Options` → `root.Options`, `FsImporter` →
  `root.importer.FsImporter`, etc. (see `baml_src/lib.baml`).
* `env!("CARGO_BIN_EXE_sasso")` → `root.tests.support.sasso_bin()` (the
  `baml pack`ed CLI at `dist/sasso`); `env!("CARGO_MANIFEST_DIR")` →
  `root.tests.support.manifest_dir()`; `std::env::temp_dir()` →
  `root.tests.support.temp_dir()`. Spawning the CLI: `Command::new(bin)
  .args(..).current_dir(d).env(..).stdin(..).output()` →
  `baml.sys.exec(bin, args, baml.sys.ProcessOptions { cwd: d, env: …, stdin: …, timeout_ms: null, stderr: null })`
  (`ShellOutput.stdout/stderr` are `uint8array` → `root.std.from_utf8_lossy`).
  The packed CLI does not need `RUST_MIN_STACK`.
* Opt-in tests (`SASSO_PARITY=1`, `SASSO_DIAG_LIVE=1`, …) keep their gates.
  `tests/parity.rs` compares against dart-sass via `$SASS_BIN`; the Rust
  `sasso` binary is a faithful stand-in, so also run them with
  `SASSO_PARITY=1 SASS_BIN=port/upstream/sasso/target/release/sasso`
  and make them pass that way too.
* Byte vs char: Rust tests that slice CSS or compare `len()` count bytes;
  mind guide §8.

## Running
`RUST_MIN_STACK=1073741824 baml test -i 'root.tests.<name>::*'` (list ids with
`baml test --list | grep tests.<name>`). `baml test` compiles the whole
project, so a type error in any file blocks every test run — keep your file
compiling (`python3 port/errors_for.py <your file>`), and if another file
blocks you, wait and retry.

**The tests must pass.** A failure is either a porting mistake in your test
or a real bug in the port. Compare with the Rust; for a suspected port bug,
check what the Rust binary does on the same input
(`port/upstream/sasso/target/release/sasso`). You may fix bugs in non-test
BAML files — via `python3 port/splice.py` only (other agents are active),
minimal, line-by-line faithful to the Rust — and must list every such fix in
your report. If you change non-test code, rebuild the CLI package
(`RUST_MIN_STACK=1073741824 baml pack main -o dist/sasso`) before re-running
CLI tests.

Final report: tests ported / passing / failing (reason for any failure),
every non-test fix (file, function, what), notable `// PORT:` deviations.
