// Port of src/util.ts
//
// The original is a re-export barrel for the `yaml/util` entry point:
// NodeCreator, debug, warn, ToJSContext, mapTag, seqTag, stringTag,
// foldFlowLines, FoldOptions, StringifyContext, stringifyNumber,
// stringifyString. All of these are already top-level in the root
// namespace; the tag constants are exposed as functions:

function mapTag() -> Tag {
  map_tag()
}

function seqTag() -> Tag {
  seq_tag()
}

function stringTag() -> Tag {
  string_tag()
}
