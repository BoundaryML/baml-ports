# T8b (phase 3: unit tests)

Read `port/PORTER_BRIEF.md`, `PORTING_GUIDE.md` §13 and `port/TEST_BRIEF.md` first.

- `src/builtins/color/deprecate.rs` L147–245: `mod tests` (2 tests) → `baml_src/ns_builtins/ns_color/ns_deprecate/ns_tests/tests.baml` (namespace `root.builtins.color.deprecate.tests`)
- `src/builtins/color/removed.rs` L106–162: `mod tests` (2 tests) → `baml_src/ns_builtins/ns_color/ns_removed/ns_tests/tests.baml` (namespace `root.builtins.color.removed.tests`)
- `src/builtins/color_ext.rs` L1134–1221: `mod tests` (6 tests) → `baml_src/ns_builtins/ns_color_ext/ns_tests/tests.baml` (namespace `root.builtins.color_ext.tests`)
- `src/host_fn.rs` L830–1037: `mod tests` (8 tests) → `baml_src/ns_host_fn/ns_tests/tests.baml` (namespace `root.host_fn.tests`)
