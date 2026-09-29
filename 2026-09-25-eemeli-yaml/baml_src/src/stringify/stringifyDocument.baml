// Port of src/stringify/stringifyDocument.ts

function stringifyDocument(doc: Document, options: ToStringOptions) -> string {
  let lines: string[] = [];
  let hasDirectives = options.directives == true;
  let dirs = doc.directives;
  if (options.directives != false && dirs != null) {
    let dir = dirs.toString(doc);
    if (dir != "") {
      lines.push(dir);
      hasDirectives = true;
    } else if (dirs.docStart ?? false) {
      hasDirectives = true;
    }
  }
  if (hasDirectives) {
    lines.push("---");
  }

  let ctx = createStringifyContext(doc, options);
  let commentString = ctx.options.commentString;

  let dcb = doc.commentBefore;
  if (dcb != null && dcb != "") {
    if (lines.length() != 1) {
      lines.unshift("");
    }
    let cs = commentString(dcb);
    lines.unshift(indentComment(cs, ""));
  }

  let chompKeep = false;
  if ((doc.value.spaceBefore ?? false) && hasDirectives) {
    lines.push("");
  }
  let vcb = doc.value.commentBefore;
  if (vcb != null && vcb != "") {
    let cs = commentString(vcb);
    lines.push(indentComment(cs, ""));
  }
  // top-level block scalars need to be indented if followed by a comment
  ctx.forceBlockIndent = doc.comment != null && doc.comment != "";
  let contentComment = doc.value.comment;
  let hasContentComment = contentComment != null && contentComment != "";
  let onChompKeep: Callback? = if (hasContentComment) { null } else { () -> void { chompKeep = true; } };
  let body = stringifyNode(
    doc.value,
    ctx,
    () -> void { contentComment = null; },
    onChompKeep,
  );
  let cc = contentComment;
  if (cc != null && cc != "") {
    body += lineComment(body, "", commentString(cc));
  }
  if ((body.at(0) == "|" || body.at(0) == ">") && lines.at(lines.length() - 1) == "---") {
    // Top-level block scalars with a preceding doc marker ought to use the
    // same line for their header.
    lines[lines.length() - 1] = "--- " + body;
  } else {
    lines.push(body);
  }
  if (dirs?.docEnd ?? false) {
    let dc = doc.comment;
    if (dc != null && dc != "") {
      let cs = commentString(dc);
      if (cs.includes("\n")) {
        lines.push("...");
        lines.push(indentComment(cs, ""));
      } else {
        lines.push("... " + cs);
      }
    } else {
      lines.push("...");
    }
  } else {
    let dc = doc.comment;
    if (dc != null && dc != "" && chompKeep) {
      dc = dc.replace(re("^\\n+"), "");
    }
    if (dc != null && dc != "") {
      let cc2 = contentComment;
      if ((!chompKeep || (cc2 != null && cc2 != "")) && lines.at(lines.length() - 1) != "") {
        lines.push("");
      }
      lines.push(indentComment(commentString(dc), ""));
    }
  }
  lines.join("\n") + "\n"
}
