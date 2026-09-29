// Port of src/compose/resolve-block-seq.ts

function resolveBlockSeq(ctx: ComposeContext, bs: Token, onError: ComposeErrorHandler, tag: Tag?) -> Node {
  let seq = if (tag?.nodeClass == "YAMLOMap") { YAMLOMap(ctx.schema, null) } else { YAMLSeq.new(ctx.schema, null) };

  if (ctx.atRoot) {
    ctx.atRoot = false;
  }
  if (ctx.atKey) {
    ctx.atKey = false;
  }
  let offset = bs.offset;
  let commentEnd: int? = null;
  for (let item in titems(bs)) {
    let start = item.start;
    let value = item.value;
    let props = resolveProps(start, ResolvePropsArg {
      indicator: "seq-item-ind",
      next: value,
      offset: offset,
      parentIndent: tindent(bs),
      startOnNewline: true,
    }, onError);
    if (props.found == null) {
      if (props.anchor != null || props.tag != null || value != null) {
        if (value?.type == "block-seq") {
          onError(props.end, "BAD_INDENT", "All sequence items must start at the same column", false);
        } else {
          onError(offset, "MISSING_CHAR", "Sequence item without - indicator", false);
        }
      } else {
        commentEnd = props.end;
        if (props.comment != "") {
          seq.comment = props.comment;
        }
        continue;
      }
    }
    let node: Node = if (value != null) {
      composeNode(ctx, value, props, onError)
    } else {
      composeEmptyNode(ctx, props.end, start, null, props, onError)
    };
    if (ctx.schema.compat != null) {
      flowIndentCheck(tindent(bs), value, onError);
    }
    offset = (node.range ?? [0, 0, 0])[2];
    seq._push(node);
  }
  seq.range = [bs.offset, offset, commentEnd ?? offset];
  seq
}
