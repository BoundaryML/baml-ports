// Port of src/compose/util-flow-indent-check.ts

function flowIndentCheck(indent: int, fc: Token?, onError: ComposeErrorHandler) -> null {
  if (fc?.type == "flow-collection") {
    let f: Token = fc ?? source_token("", 0, 0, "");
    let end = tend(f)[0];
    if (end.indent == indent && (end.source == "]" || end.source == "}") && (containsNewline(f) ?? false)) {
      let msg = "Flow end indicator should be more indented than parent";
      onError(end, "BAD_INDENT", msg, true);
    }
  }
  null
}
