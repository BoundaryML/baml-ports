# Test porter brief (phase 3: Rust unit tests → BAML tests)

All non-test code is ported (phase 2). Your unit (`port/units/TX.md`) lists
Rust `#[cfg(test)] mod …` blocks; port each one line by line into its own
file at the listed path (a new file you create), as described in
`PORTING_GUIDE.md` §13:

* The module becomes a namespace (`ns_<mod>/<mod>.baml`). `use super::*` means
  the parent's items are reached as `root.<parent>.<item>`.
* `#[test] fn name() { … }` → `test "name" { … }` (keep the Rust name).
  Helper `fn`s / structs / consts in the test module → ordinary BAML items in
  that namespace (consts → zero-arg functions).
* Assertions: `assert_eq!(a, b)` → `assert.equal(a, b);`, `assert!(c)` →
  `assert.is_true(c);`, `assert_ne!` → `assert.is_true(a != b);`, float
  closeness → `assert.approx_equal`. Assertion messages (`assert!(c, "…")`)
  → keep as a `//` comment above the assert. The last statement of a test
  has no `;`.
* `#[should_panic]` → wrap the body: `… catch (e) { let _p: baml.panics.Panic => true }` (`catch_all`/`_` do not catch panics)
  and assert it; a `Result`-returning test → assert the call does not throw.
* Tests that exercise Rust-only machinery (raw allocator pointers, threads,
  `Send`/`Sync`) still get ported as far as their observable behavior
  goes; where there is genuinely nothing to observe in BAML, keep the test
  with a `// PORT:` note and assert what the BAML port does instead. Never
  delete a test silently.

Run them: `baml test --list | grep <namespace>` shows the ids (format
`root.value.tests::name`); `baml test -i '<id or glob>'` runs them.

**The tests must pass.** A failing test is either a porting mistake in the
test or a bug in the ported code under test — find out which by comparing
with the Rust source (`port/upstream/sasso/src/`). You may fix bugs in any
ported (non-test) BAML file: other test porters may be editing too, so edit
non-test files ONLY via `python3 port/splice.py` (function replace or
`--replace-text`), keep fixes minimal and line-by-line faithful to the Rust,
and list every such fix in your report. Your own new test files you edit
freely.

Final report: tests ported / passing / failing (with the reason for any
failure you could not fix), and every non-test fix you made (file, item, what).
