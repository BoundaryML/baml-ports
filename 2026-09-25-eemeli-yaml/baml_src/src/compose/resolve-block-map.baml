// Port of src/compose/resolve-block-map.ts

function startColMsg() -> string {
  "All mapping items must start at the same column"
}

function resolveBlockMap(ctx: ComposeContext, bm: Token, onError: ComposeErrorHandler, tag: Tag?) -> Node {
  let isSet = tag?.nodeClass == "YAMLSet";
  let map_ = YAMLMap.new(ctx.schema, null);
  let set_ = YAMLSet.new(ctx.schema);
  let coll: NodeBase = if (isSet) { set_ } else { map_ };

  if (ctx.atRoot) {
    ctx.atRoot = false;
  }
  let offset = bm.offset;
  let commentEnd: int? = null;
  for (let collItem in titems(bm)) {
    let start = collItem.start;
    let key = collItem.key;
    let sep = collItem.sep;
    let value = collItem.value;

    // key properties
    let keyProps = resolveProps(start, ResolvePropsArg {
      indicator: "explicit-key-ind",
      next: key ?? sep?.at(0),
      offset: offset,
      parentIndent: tindent(bm),
      startOnNewline: true,
    }, onError);
    let implicitKey = keyProps.found == null;
    if (implicitKey) {
      if (key != null) {
        if (key.type == "block-seq") {
          onError(offset, "BLOCK_AS_IMPLICIT_KEY", "A block sequence may not be used as an implicit map key", false);
        } else if (key.indent != null && key.indent != bm.indent) {
          onError(offset, "BAD_INDENT", startColMsg(), false);
        }
      }
      if (keyProps.anchor == null && keyProps.tag == null && sep == null) {
        commentEnd = keyProps.end;
        if (keyProps.comment != "") {
          let mc = coll.comment;
          if (mc != null && mc != "") {
            coll.comment = mc + "\n" + keyProps.comment;
          } else {
            coll.comment = keyProps.comment;
          }
        }
        continue;
      }
      if (keyProps.newlineAfterProp != null || (containsNewline(key) ?? false)) {
        let src_: ErrorSource = if (key != null) { key } else { start[start.length() - 1] };
        onError(src_, "MULTILINE_IMPLICIT_KEY", "Implicit keys need to be on a single line", false);
      }
    } else if (keyProps.found?.indent != bm.indent) {
      onError(offset, "BAD_INDENT", startColMsg(), false);
    }

    // key value
    ctx.atKey = true;
    let keyStart = keyProps.end;
    let keyNode: Node = if (key != null) {
      composeNode(ctx, key, keyProps, onError)
    } else {
      composeEmptyNode(ctx, keyStart, start, null, keyProps, onError)
    };
    if (ctx.schema.compat != null) {
      flowIndentCheck(tindent(bm), key, onError);
    }
    ctx.atKey = false;

    let hasKey = if (isSet) { set_.has(keyNode) } else { map_.has(keyNode) };
    if (hasKey) {
      onError(keyStart, "DUPLICATE_KEY", "Map keys must be unique", false);
    }

    // value properties
    let valueProps = resolveProps(sep ?? [], ResolvePropsArg {
      indicator: "map-value-ind",
      next: value,
      offset: (keyNode.range ?? [0, 0, 0])[2],
      parentIndent: tindent(bm),
      startOnNewline: key == null || key?.type == "block-scalar",
    }, onError);
    offset = valueProps.end;

    let vfound = valueProps.found;
    if (vfound != null) {
      if (implicitKey) {
        if (value?.type == "block-map" && !valueProps.hasNewline) {
          onError(offset, "BLOCK_AS_IMPLICIT_KEY", "Nested mappings are not allowed in compact mappings", false);
        }
        if ((ctx.options.strict ?? true) && keyProps.start < vfound.offset - 1024) {
          onError(keyNode.range ?? [0, 0, 0], "KEY_OVER_1024_CHARS", "The : indicator must be at most 1024 chars after the start of an implicit block mapping key", false);
        }
      }
      // value value
      let valueNode: Node = if (value != null) {
        composeNode(ctx, value, valueProps, onError)
      } else {
        composeEmptyNode(ctx, offset, sep, null, valueProps, onError)
      };
      if (ctx.schema.compat != null) {
        flowIndentCheck(tindent(bm), value, onError);
      }
      offset = (valueNode.range ?? [0, 0, 0])[2];
      if (isSet) {
        if (value != null || valueProps.anchor != null || valueProps.tag != null) {
          let msg = "Set items must not have non-empty values";
          onError(valueNode.range ?? [0, 0, 0], "BAD_COLLECTION_TYPE", msg, false);
        }
        if (valueProps.comment != "") {
          let kc = keyNode.comment;
          if (kc != null && kc != "") {
            keyNode.comment = kc + "\n" + valueProps.comment;
          } else {
            keyNode.comment = valueProps.comment;
          }
          let kr = keyNode.range;
          if (kr != null) {
            kr[2] = valueProps.end;
          }
        }
        set_.add(keyNode);
      } else {
        let pair = Pair.new(keyNode, valueNode);
        if (ctx.options.keepSourceTokens ?? false) {
          pair.srcToken = collItem;
        }
        map_.set(pair, null);
      }
    } else {
      // key with no value
      if (implicitKey) {
        onError(keyNode.range ?? [0, 0, 0], "MISSING_CHAR", "Implicit map keys need to be followed by map values", false);
      }
      if (valueProps.comment != "") {
        let kc = keyNode.comment;
        if (kc != null && kc != "") {
          keyNode.comment = kc + "\n" + valueProps.comment;
        } else {
          keyNode.comment = valueProps.comment;
        }
      }
      if (isSet) {
        set_.add(keyNode);
      } else {
        let pair = Pair.new(keyNode, null);
        if (ctx.options.keepSourceTokens ?? false) {
          pair.srcToken = collItem;
        }
        map_.set(pair, null);
      }
    }
  }

  let ce = commentEnd;
  if (ce != null && ce != 0 && (ce ?? 0) < offset) {
    onError(ce, "IMPOSSIBLE", "Map comment with trailing content", false);
  }
  coll.range = [bm.offset, offset, commentEnd ?? offset];
  if (isSet) { set_ } else { map_ }
}
