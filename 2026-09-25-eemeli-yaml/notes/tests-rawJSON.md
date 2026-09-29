# tests/rawJSON.ts → baml_src/tests/rawJSON.baml

## Results

`$B test -i "root::rawJSON::*"`: **4 passed, 0 failed, 0 skipped** (4 total).

Upstream runs these only when the JS runtime has `JSON.rawJSON` (`describe.runIf(JSON.rawJSON)`); the port always runs them.

## Library changes

Raw JSON values were not modelled by the port. Rather than skipping, I added a small, faithful model of the upstream `JSON.isRawJSON` hooks:

- `src/js.baml`: new `class JsRawJSON { _id, rawJSON }`, `js_raw_json(text)` (`JSON.rawJSON`) and `js_is_raw_json(v)` (`JSON.isRawJSON`). JS's validation that `text` is a JSON primitive (SyntaxError otherwise) is not modelled.
- `src/schema/common/string.baml`: string tag `identify` also accepts raw JSON (as upstream).
- `src/doc/NodeCreator.baml`: raw JSON values become `Scalar`s (as upstream).
- `src/stringify/stringifyString.baml`: a raw JSON scalar value is emitted verbatim (as upstream).
- `src/index.baml`: updated the comment that said raw JSON is unsupported.

## New BAML gaps

None specific to this file (BAML has no `JSON.rawJSON`, but a class models it adequately).
