# momiji-rs/sasso → BAML

A line-by-line port of the Rust SCSS → CSS compiler [momiji-rs/sasso](https://github.com/momiji-rs/sasso) to [BAML](https://github.com/BoundaryML/baml). It was an experiment to see how far the new BAML language gets today on a large (~93K-line) program.

- **Ported from:** https://github.com/momiji-rs/sasso
- **Upstream commit:** [`15c44de208f4fa6b4886d2b84d1db08af79851f6`](https://github.com/momiji-rs/sasso/commit/15c44de208f4fa6b4886d2b84d1db08af79851f6) (`npm-v0.18.0-180-g15c44de`, "Merge pull request #193 from momiji-rs/fix/one-file-url-decoder-for-real", 2026-09-24)
- **BAML toolchain:** ported with `baml` 0.20.2-nightly.20260923.a; also checks and passes its tests on 0.20.2-nightly.20260925.a

The library, CLI, all 274 unit tests, all 790 integration tests, the examples and the benchmark are ported, and every test passes. Output is byte-identical to the Rust `sasso` on a 982-case corpus and on Bootstrap 5.3.3. The port is about 60–700× slower than the native build.

```baml
let css = root.compile(".a { b: 1px + 2px; }", root.Options.default().with_style(root.OutputStyle.Compressed));
// ".a{b:3px}"
```

- Library + CLI: `baml_src/` (one Rust module = one `ns_*` namespace; `src/eval/expr.rs` → `baml_src/ns_eval/ns_expr/expr.baml`)
- Rust std surface BAML lacks: `baml_src/ns_std/` (`root.std`)
- Tests: unit tests next to each module (`ns_<mod>/ns_tests/`), integration tests in `baml_src/ns_tests/`
- Porting tools, briefs and the comparison corpus: `port/`

## Running

```bash
printf '.a { b: 1px + 2px; }' | baml run main -- --stdin --style=compressed
```

The integration tests run the packed CLI and read fixtures from the upstream checkout, so set those up first:

```bash
git clone https://github.com/momiji-rs/sasso port/upstream/sasso
git -C port/upstream/sasso checkout 15c44de208f4fa6b4886d2b84d1db08af79851f6
mkdir -p dist && baml pack main -o dist/sasso
baml test
```

`cargo build --release` in `port/upstream/sasso` builds the Rust reference binary used by `port/compare.sh`, the corpus and the opt-in parity mode.

See [PORTING_NOTES.md](PORTING_NOTES.md) for results, layout and how the port was made, [PORTING_GUIDE.md](PORTING_GUIDE.md) for the translation rules, and [baml-findings/](baml-findings/) for the BAML bugs and limitations found.

License: MIT OR Apache-2.0 (see `LICENSE-MIT`, `LICENSE-APACHE`), same as the original.
