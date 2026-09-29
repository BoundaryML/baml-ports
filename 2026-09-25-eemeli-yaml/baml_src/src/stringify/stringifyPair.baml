// Port of src/stringify/stringifyPair.ts

function stringifyPair(pair: Pair, ctx0: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string {
  let key = pair.key;
  let value = pair.value;
  let indent = ctx0.indent;
  let indentStep = ctx0.indentStep;
  let commentString = ctx0.options.commentString;
  let indentSeq = ctx0.options.indentSeq;
  let simpleKeys = ctx0.options.simpleKeys;
  if (simpleKeys) {
    if (key.comment != null && key.comment != "") {
      throw js_error("With simple keys, key nodes cannot have comments");
    }
    if (isCollection(key)) {
      let msg = "With simple keys, collection cannot be used as a key value";
      throw js_error(msg);
    }
  }
  let explicitKey = !simpleKeys && match (key) {
    let s: Scalar => s.type == Scalar.BLOCK_FOLDED() || s.type == Scalar.BLOCK_LITERAL(),
    _ => true,
  };

  let ctx = StringifyContext {
    ...ctx0,
    implicitKey: !explicitKey,
    indent: indent + indentStep,
  };
  let keyComment = key.comment;
  let keyCommentDone = false;
  let chompKeep = false;
  let str = stringifyNode(
    key,
    ctx,
    () -> void { keyCommentDone = true; },
    () -> void { chompKeep = true; },
  );

  if (!explicitKey && !(ctx.inFlow ?? false) && str.length() > 1024) {
    if (simpleKeys) {
      throw js_error("With simple keys, single line scalar must not span more than 1024 characters");
    }
    explicitKey = true;
  }

  if (ctx.inFlow ?? false) {
    if (value == null) {
      if (keyCommentDone && onComment != null) {
        onComment();
      }
      return if (str == "") { "?" } else if (explicitKey) { "? " + str } else { str + ":" };
    }
  } else if (value == null && explicitKey) {
    str = "? " + str;
    if (keyComment != null && keyComment != "" && !keyCommentDone) {
      str += lineComment(str, ctx.indent, commentString(keyComment));
    } else if (chompKeep && onChompKeep != null) {
      onChompKeep();
    }
    return str;
  }

  if (keyCommentDone) {
    keyComment = null;
  }
  if (explicitKey) {
    if (keyComment != null && keyComment != "") {
      str += lineComment(str, ctx.indent, commentString(keyComment));
    }
    str = "? " + str + "\n" + indent + ":";
  } else {
    str = str + ":";
    if (keyComment != null && keyComment != "") {
      str += lineComment(str, ctx.indent, commentString(keyComment));
    }
  }

  let vsb = false;
  let vcb: string? = null;
  let valueComment: string? = null;
  if (value != null) {
    vsb = value.spaceBefore ?? false;
    vcb = value.commentBefore;
    valueComment = value.comment;
  }
  ctx.implicitKey = false;
  let valueIsScalar = match (value) {
    Scalar => true,
    _ => false,
  };
  if (!explicitKey && (keyComment == null || keyComment == "") && valueIsScalar) {
    ctx.indentAtStart = str.length() + 1;
  }
  chompKeep = false;
  match (value) {
    let vs: YAMLSeq => {
      if (
        !indentSeq &&
        indentStep.length() >= 2 &&
        !(ctx.inFlow ?? false) &&
        !explicitKey &&
        !(vs.flow ?? false) &&
        (vs.tag == null || vs.tag == "") &&
        (vs.anchor == null || vs.anchor == "")
      ) {
        // If indentSeq === false, consider '- ' as part of indentation where possible
        ctx.indent = str_from(ctx.indent, 2);
      }
    },
    _ => {},
  }

  let valueCommentDone = false;
  let valueStr = stringifyNode(
    value,
    ctx,
    () -> void { valueCommentDone = true; },
    () -> void { chompKeep = true; },
  );
  let ws = " ";
  let kc = keyComment;
  let vcb2 = vcb;
  if ((kc != null && kc != "") || vsb || (vcb2 != null && vcb2 != "")) {
    ws = if (vsb) { "\n" } else { "" };
    if (vcb2 != null && vcb2 != "") {
      let cs = commentString(vcb2);
      ws += "\n" + indentComment(cs, ctx.indent);
    }
    if (valueStr == "" && !(ctx.inFlow ?? false)) {
      if (ws == "\n" && valueComment != null && valueComment != "") {
        ws = "\n\n";
      }
    } else {
      ws += "\n" + ctx.indent;
    }
  } else if (!explicitKey && isCollection(value)) {
    let vs0 = valueStr.at(0) ?? "";
    let nl0 = valueStr.index_of("\n") ?? -1;
    let hasNewline = nl0 != -1;
    let vflow = match (value) {
      let m: YAMLMap => m.flow ?? (m.size() == 0),
      let s: YAMLSeq => s.flow ?? (s.size() == 0),
      let s: YAMLSet => s.flow ?? (s.size() == 0),
      _ => false,
    };
    let flow = ctx.inFlow ?? vflow;
    if (hasNewline || !flow) {
      let hasPropsLine = false;
      if (hasNewline && (vs0 == "&" || vs0 == "!")) {
        let sp0 = valueStr.index_of(" ") ?? -1;
        if (vs0 == "&" && sp0 != -1 && sp0 < nl0 && valueStr.at(sp0 + 1) == "!") {
          sp0 = str_index_of(valueStr, " ", sp0 + 1);
        }
        if (sp0 == -1 || nl0 < sp0) {
          hasPropsLine = true;
        }
      }
      if (!hasPropsLine) {
        ws = "\n" + ctx.indent;
      }
    }
  } else if (valueStr == "" || valueStr.at(0) == "\n") {
    ws = "";
  }
  str += ws + valueStr;

  if (ctx.inFlow ?? false) {
    if (valueCommentDone && onComment != null) {
      onComment();
    }
  } else if (valueComment != null && valueComment != "" && !valueCommentDone) {
    str += lineComment(str, ctx.indent, commentString(valueComment));
  } else if (chompKeep && onChompKeep != null) {
    onChompKeep();
  }

  str
}
