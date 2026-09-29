// Port of src/compose/resolve-flow-collection.ts

function blockMsg() -> string {
  "Block collections are not allowed within flow collections"
}

function isBlock(token: Token?) -> bool {
  token?.type == "block-map" || token?.type == "block-seq"
}

function resolveFlowCollection(ctx: ComposeContext, fc: Token, onError: ComposeErrorHandler, tag: Tag?) -> Node {
  let fcStart = fc.fcStart ?? source_token("flow-map-start", fc.offset, 0, "{");
  let isMap = tsrc(fcStart) == "{";
  let fcName = if (isMap) { "flow map" } else { "flow sequence" };
  let nodeClass = tag?.nodeClass;
  let coll: Node = if (nodeClass != null) {
    match (nodeClass) {
      "YAMLSet" => YAMLSet.new(ctx.schema),
      "YAMLOMap" => YAMLOMap(ctx.schema, null),
      "YAMLSeq" => YAMLSeq.new(ctx.schema, null),
      _ => YAMLMap.new(ctx.schema, null),
    }
  } else if (isMap) {
    YAMLMap.new(ctx.schema, null)
  } else {
    YAMLSeq.new(ctx.schema, null)
  };
  set_flow(coll, true);
  let atRoot = ctx.atRoot;
  if (atRoot) {
    ctx.atRoot = false;
  }
  if (ctx.atKey) {
    ctx.atKey = false;
  }

  let offset = fc.offset + tsrc(fcStart).length();
  let items = titems(fc);
  let i = 0;
  while (i < items.length()) {
    let collItem = items[i];
    let start = collItem.start;
    let key = collItem.key;
    let sep = collItem.sep;
    let value = collItem.value;

    let props = resolveProps(start, ResolvePropsArg {
      flow: fcName,
      indicator: "explicit-key-ind",
      next: key ?? sep?.at(0),
      offset: offset,
      parentIndent: tindent(fc),
      startOnNewline: false,
    }, onError);
    if (props.found == null) {
      if (props.anchor == null && props.tag == null && sep == null && value == null) {
        let comma = props.comma;
        if (i == 0 && comma != null) {
          onError(comma, "UNEXPECTED_TOKEN", "Unexpected , in " + fcName, false);
        } else if (i < items.length() - 1) {
          onError(props.start, "UNEXPECTED_TOKEN", "Unexpected empty item in " + fcName, false);
        }
        if (props.comment != "") {
          let cc = coll.comment;
          if (cc != null && cc != "") {
            coll.comment = cc + "\n" + props.comment;
          } else {
            coll.comment = props.comment;
          }
        }
        offset = props.end;
        i += 1;
        continue;
      }
      if (!isMap && (ctx.options.strict ?? true) && (containsNewline(key) ?? false)) {
        let k: Token = key ?? fc; // checked by containsNewline()
        onError(k, "MULTILINE_IMPLICIT_KEY", "Implicit keys of flow sequence pairs need to be on a single line", false);
      }
    }
    if (i == 0) {
      let comma = props.comma;
      if (comma != null) {
        onError(comma, "UNEXPECTED_TOKEN", "Unexpected , in " + fcName, false);
      }
    } else {
      if (props.comma == null) {
        onError(props.start, "MISSING_CHAR", "Missing , between " + fcName + " items", false);
      }
      if (props.comment != "") {
        let prevItemComment = "";
        for (let st in start) {
          if (st.type == "comma" || st.type == "space") {
            continue;
          }
          if (st.type == "comment") {
            prevItemComment = str_from(tsrc(st), 1);
          }
          break;
        }
        if (prevItemComment != "") {
          let prev: NodeBase? = match (coll) {
            let s: YAMLSeq => match (s.items.at(s.items.length() - 1)) {
              let p: Pair => p.value ?? p.key,
              let n: Node => n,
              null => null,
            },
            let m: YAMLMap => {
              let vals = m.values.values();
              let p = vals.at(vals.length() - 1);
              if (p != null) { p.value ?? p.key } else { null }
            },
            let s: YAMLSet => {
              let vals = s.values.values();
              vals.at(vals.length() - 1)
            },
            _ => null,
          };
          if (prev != null) {
            let pc = prev.comment;
            if (pc != null && pc != "") {
              prev.comment = pc + "\n" + prevItemComment;
            } else {
              prev.comment = prevItemComment;
            }
          }
          props.comment = str_from(props.comment, prevItemComment.length() + 1);
        }
      }
    }

    if (!isMap && sep == null && props.found == null) {
      // item is a value in a seq
      // → key & sep are empty, start does not include ? or :
      let valueNode: Node = if (value != null) {
        composeNode(ctx, value, props, onError)
      } else {
        composeEmptyNode(ctx, props.end, sep, null, props, onError)
      };
      match (coll) {
        let s: YAMLSeq => {
          s._push(valueNode);
        },
        _ => {},
      }
      offset = (valueNode.range ?? [0, 0, 0])[2];
      if (isBlock(value)) {
        onError(valueNode.range ?? [0, 0, 0], "BLOCK_IN_FLOW", blockMsg(), false);
      }
    } else {
      // item is a key+value pair

      // key value
      ctx.atKey = true;
      let keyStart = props.end;
      let keyNode: Node = if (key != null) {
        composeNode(ctx, key, props, onError)
      } else {
        composeEmptyNode(ctx, keyStart, start, null, props, onError)
      };
      if (isBlock(key)) {
        onError(keyNode.range ?? [0, 0, 0], "BLOCK_IN_FLOW", blockMsg(), false);
      }
      ctx.atKey = false;

      // value properties
      let valueProps = resolveProps(sep ?? [], ResolvePropsArg {
        flow: fcName,
        indicator: "map-value-ind",
        next: value,
        offset: (keyNode.range ?? [0, 0, 0])[2],
        parentIndent: tindent(fc),
        startOnNewline: false,
      }, onError);

      let vfound = valueProps.found;
      if (vfound != null) {
        if (!isMap && props.found == null && (ctx.options.strict ?? true)) {
          if (sep != null) {
            for (let st in sep) {
              if (st._id == vfound._id) {
                break;
              }
              if (st.type == "newline") {
                onError(st, "MULTILINE_IMPLICIT_KEY", "Implicit keys of flow sequence pairs need to be on a single line", false);
                break;
              }
            }
          }
          if (props.start < vfound.offset - 1024) {
            onError(vfound, "KEY_OVER_1024_CHARS", "The : indicator must be at most 1024 chars after the start of an implicit flow sequence key", false);
          }
        }
      } else if (value != null) {
        if (value.source != null && (value.source ?? "").at(0) == ":") {
          onError(value, "MISSING_CHAR", "Missing space after : in " + fcName, false);
        } else {
          onError(valueProps.start, "MISSING_CHAR", "Missing , or : between " + fcName + " items", false);
        }
      }

      // value value
      let valueNode: Node? = if (value != null) {
        composeNode(ctx, value, valueProps, onError)
      } else if (vfound != null) {
        composeEmptyNode(ctx, valueProps.end, sep, null, valueProps, onError)
      } else {
        null
      };
      if (valueNode != null) {
        if (isBlock(value)) {
          onError(valueNode.range ?? [0, 0, 0], "BLOCK_IN_FLOW", blockMsg(), false);
        }
      } else if (valueProps.comment != "") {
        let kc = keyNode.comment;
        if (kc != null && kc != "") {
          keyNode.comment = kc + "\n" + valueProps.comment;
        } else {
          keyNode.comment = valueProps.comment;
        }
      }

      let pair = Pair.new(keyNode, valueNode);
      if (ctx.options.keepSourceTokens ?? false) {
        pair.srcToken = collItem;
      }
      if (isMap) {
        match (coll) {
          let s: YAMLSet => {
            if (s.has(keyNode)) {
              onError(keyStart, "DUPLICATE_KEY", "Map keys must be unique", false);
            }
            s.add(keyNode);
          },
          let m: YAMLMap => {
            if (m.has(keyNode)) {
              onError(keyStart, "DUPLICATE_KEY", "Map keys must be unique", false);
            }
            m.set(pair, null);
          },
          _ => {},
        }
      } else {
        let map_ = YAMLMap.new(ctx.schema, null);
        map_.flow = true;
        map_.set(pair, null);
        let endRange = (valueNode ?? keyNode).range ?? [0, 0, 0];
        map_.range = [(keyNode.range ?? [0, 0, 0])[0], endRange[1], endRange[2]];
        match (coll) {
          let s: YAMLSeq => {
            s._push(map_);
          },
          _ => {},
        }
      }
      offset = if (valueNode != null) { (valueNode.range ?? [0, 0, 0])[2] } else { valueProps.end };
    }
    i += 1;
  }

  let expectedEnd = if (isMap) { "}" } else { "]" };
  let fcEnd = tend(fc);
  let ce = fcEnd.at(0);
  let ee: Token[] = fcEnd.slice(1, fcEnd.length());
  let cePos = offset;
  if (ce?.source == expectedEnd && ce != null) {
    let c: Token = ce ?? fc;
    cePos = c.offset + tsrc(c).length();
  } else {
    let name = fcName.slice(0, 1).to_upper_case() + str_from(fcName, 1);
    let msg = if (atRoot) {
      name + " must end with a " + expectedEnd
    } else {
      name + " in block collection must be sufficiently indented and end with a " + expectedEnd
    };
    onError(offset, if (atRoot) { "MISSING_CHAR" } else { "BAD_INDENT" }, msg, false);
    if (ce != null) {
      let c: Token = ce ?? fc;
      if (tsrc(c).length() != 1) {
        ee.unshift(c);
      }
    }
  }
  if (ee.length() > 0) {
    let end = resolveEnd(ee, cePos, ctx.options.strict ?? true, onError);
    if (end.comment != "") {
      let cc = coll.comment;
      if (cc != null && cc != "") {
        coll.comment = cc + "\n" + end.comment;
      } else {
        coll.comment = end.comment;
      }
    }
    coll.range = [fc.offset, cePos, end.offset];
  } else {
    coll.range = [fc.offset, cePos, cePos];
  }

  coll
}

function set_flow(n: Node, flow: bool) -> null {
  match (n) {
    let m: YAMLMap => {
      m.flow = flow;
    },
    let s: YAMLSeq => {
      s.flow = flow;
    },
    let s: YAMLSet => {
      s.flow = flow;
    },
    _ => {},
  }
  null
}
