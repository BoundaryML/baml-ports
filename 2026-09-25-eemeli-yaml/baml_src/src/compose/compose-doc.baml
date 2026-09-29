// Port of src/compose/compose-doc.ts

function composeDoc(options: Options, directives: Directives, docToken: Token, onError: ComposeErrorHandler) -> Document {
  let offset = docToken.offset;
  let start = tstart(docToken);
  let value = docToken.value;
  let end = docToken.end;
  let opts = options_assign(Options { _directives: directives }, options);
  let doc = Document.new(null, null, opts);
  let ctx = ComposeContext {
    atKey: false,
    atRoot: true,
    directives: doc.directives ?? directives,
    options: doc.options,
    schema: doc.schema,
  };
  let props = resolveProps(start, ResolvePropsArg {
    indicator: "doc-start",
    next: value ?? end?.at(0),
    offset: offset,
    parentIndent: 0,
    startOnNewline: true,
  }, onError);
  if (props.found != null) {
    let dd = doc.directives;
    if (dd != null) {
      dd.docStart = true;
    }
    if ((value?.type == "block-map" || value?.type == "block-seq") && !props.hasNewline) {
      onError(props.end, "MISSING_CHAR", "Block collection cannot start on same line with directives-end marker", false);
    }
  }
  doc.value = if (value != null) {
    composeNode(ctx, value, props, onError)
  } else {
    composeEmptyNode(ctx, props.end, start, null, props, onError)
  };

  let contentEnd = (doc.value.range ?? [0, 0, 0])[2];
  let re_ = resolveEnd(end, contentEnd, false, onError);
  if (re_.comment != "") {
    doc.comment = re_.comment;
  }
  doc.range = [offset, contentEnd, re_.offset];
  doc
}
