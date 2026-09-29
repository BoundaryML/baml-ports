// Port of src/index.ts
//
// The original is the package's export barrel. BAML has no module exports:
// everything in the root namespace is public. The mapping of exported names:
//
//   Composer, Document, Schema, YAMLError/YAMLParseError/YAMLWarning,
//   Alias, isCollection, isNode, Pair, Scalar, YAMLMap, YAMLSeq, YAMLSet,
//   CST (cst_* functions + Token/CollectionItem), lex, LineCounter, Parser
//   (new_parser), parse, parseAllDocuments, parseDocument, stringify,
//   visit, visitAsync
//
// Type-only exports (DocValue, ErrorCode, Node, Range, KeyArg, the option
// types, TagId, Tags, CollectionTag/ScalarTag (= Tag), YAMLOMap, visitor
// types) are type aliases or classes of the same names.
//
// `src/rawjson.d.ts` declares the `JSON.rawJSON` / `JSON.isRawJSON` globals
// used by the library for raw JSON values; they are modelled by the
// `JsRawJSON` class (`js_raw_json(text)` / `js_is_raw_json(v)` in js.baml).

/// The package version this port is based on.
function yaml_version() -> string {
  "3.0.0-dev (eemeli/yaml@528ef30)"
}
