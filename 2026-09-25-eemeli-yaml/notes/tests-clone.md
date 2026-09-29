# tests/clone.ts → baml_src/tests/clone.baml

## Results

`$B test -i "root::clone::*"`: **5 passed, 0 failed, 0 skipped** (5 total).

Porting notes:
- `copy.directives.yaml.explicit = true`: `directives` is `Directives?`, so it's narrowed via a local first.
- The `visit` visitor's `Node(_, it) { if (it.anchor === 'foo') it.anchor = 'x' }` needs a `match` over the `Node` union to assign `anchor` (`tclo_rename_anchor`).
- `source`…`` results get `+ "\n"` (backtick literals drop the trailing newline; see tests-doc-comments.md).

## Fixes

No library fixes. Initially 3 failures, all test-side:
- "has separate value from original": `expect_toMatchObject(x, Scalar.new("bar"))` used full equality for class-instance expectations, so a parsed scalar (with `range`, `source`, `type`…) never matched. Fixed `t_match` in `baml_src/tests/_expect.baml` to compare only the expected instance's non-null fields (Jest's `toMatchObject` semantics).
- "has separate directives from original", "handles anchors & aliases": trailing-newline loss from backtick literals (fixed in the test).

## BAML gaps

Only the backtick-boundary-newline pain point, described in tests-doc-comments.md.
