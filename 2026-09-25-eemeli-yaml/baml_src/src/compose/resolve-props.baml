// Port of src/compose/resolve-props.ts

class ResolvePropsArg {
  flow: string?
  indicator: string
  next: Token?
  offset: int
  parentIndent: int
  startOnNewline: bool
}

class ResolvedProps {
  comma: Token?
  found: Token?
  spaceBefore: bool
  comment: string
  hasNewline: bool
  anchor: Token?
  tag: Token?
  newlineAfterProp: Token?
  end: int
  start: int
}

function resolveProps(tokens: Token[], arg: ResolvePropsArg, onError: ComposeErrorHandler) -> ResolvedProps {
  let flow = arg.flow;
  let indicator = arg.indicator;
  let next = arg.next;
  let offset = arg.offset;
  let parentIndent = arg.parentIndent;
  let startOnNewline = arg.startOnNewline;
  let spaceBefore = false;
  let atNewline = startOnNewline;
  let hasSpace = startOnNewline;
  let comment = "";
  let commentSep = "";
  let hasNewline = false;
  let reqSpace = false;
  let tab: Token? = null;
  let anchor: Token? = null;
  let tag: Token? = null;
  let newlineAfterProp: Token? = null;
  let comma: Token? = null;
  let found: Token? = null;
  let start: int? = null;
  let token: Token? = null;
  for (let tk in tokens) {
    token = tk;
    if (reqSpace) {
      if (tk.type != "space" && tk.type != "newline" && tk.type != "comma") {
        onError(tk.offset, "MISSING_CHAR", "Tags and anchors must be separated from the next token by white space", false);
      }
      reqSpace = false;
    }
    let tb = tab;
    if (tb != null) {
      if (atNewline && tk.type != "comment" && tk.type != "newline") {
        onError(tb, "TAB_AS_INDENT", "Tabs are not allowed as indentation", false);
      }
      tab = null;
    }
    let tt = tk.type;
    if (tt == "space") {
      // At the doc level, tabs at line start may be parsed
      // as leading white space rather than indentation.
      // In a flow collection, only the parser handles indent.
      if (
        flow == null &&
        (indicator != "doc-start" || next?.type != "flow-collection") &&
        tsrc(tk).includes("\t")
      ) {
        tab = tk;
      }
      hasSpace = true;
    } else if (tt == "comment") {
      if (!hasSpace) {
        onError(tk, "MISSING_CHAR", "Comments must be separated from other tokens by white space characters", false);
      }
      let cb0 = str_from(tsrc(tk), 1);
      let cb = if (cb0 != "") { cb0 } else { " " };
      if (comment == "") {
        comment = cb;
      } else {
        comment += commentSep + cb;
      }
      commentSep = "";
      atNewline = false;
    } else if (tt == "newline") {
      if (atNewline) {
        if (comment != "") {
          comment += tsrc(tk);
        } else if (found == null || indicator != "seq-item-ind") {
          spaceBefore = true;
        }
      } else {
        commentSep += tsrc(tk);
      }
      atNewline = true;
      hasNewline = true;
      if (anchor != null || tag != null) {
        newlineAfterProp = tk;
      }
      hasSpace = true;
    } else if (tt == "anchor") {
      if (anchor != null) {
        onError(tk, "MULTIPLE_ANCHORS", "A node can have at most one anchor", false);
      }
      if (tsrc(tk).ends_with(":")) {
        onError(tk.offset + tsrc(tk).length() - 1, "BAD_ALIAS", "Anchor ending in : is ambiguous", true);
      }
      anchor = tk;
      start = start ?? tk.offset;
      atNewline = false;
      hasSpace = false;
      reqSpace = true;
    } else if (tt == "tag") {
      if (tag != null) {
        onError(tk, "MULTIPLE_TAGS", "A node can have at most one tag", false);
      }
      tag = tk;
      start = start ?? tk.offset;
      atNewline = false;
      hasSpace = false;
      reqSpace = true;
    } else if (tt == indicator) {
      // Could here handle preceding comments differently
      if (anchor != null || tag != null) {
        onError(tk, "BAD_PROP_ORDER", "Anchors and tags must be after the " + tsrc(tk) + " indicator", false);
      }
      if (found != null) {
        onError(tk, "UNEXPECTED_TOKEN", "Unexpected " + tsrc(tk) + " in " + (flow ?? "collection"), false);
      }
      found = tk;
      atNewline = indicator == "seq-item-ind" || indicator == "explicit-key-ind";
      hasSpace = false;
    } else if (tt == "comma" && flow != null) {
      if (comma != null) {
        onError(tk, "UNEXPECTED_TOKEN", "Unexpected , in " + (flow ?? ""), false);
      }
      comma = tk;
      atNewline = false;
      hasSpace = false;
    } else {
      onError(tk, "UNEXPECTED_TOKEN", "Unexpected " + tt + " token", false);
      atNewline = false;
      hasSpace = false;
    }
  }
  let last = token;
  let end = if (last != null) { last.offset + tsrc(last).length() } else { offset };
  if (
    reqSpace &&
    next != null &&
    next?.type != "space" &&
    next?.type != "newline" &&
    next?.type != "comma" &&
    (next?.type != "scalar" || next?.source != "")
  ) {
    let nx: Token = next ?? source_token("", 0, 0, "");
    onError(nx.offset, "MISSING_CHAR", "Tags and anchors must be separated from the next token by white space", false);
  }
  let tb2 = tab;
  if (tb2 != null) {
    if ((atNewline && tindent(tb2) <= parentIndent) || next?.type == "block-map" || next?.type == "block-seq") {
      onError(tb2, "TAB_AS_INDENT", "Tabs are not allowed as indentation", false);
    }
  }
  ResolvedProps {
    comma: comma,
    found: found,
    spaceBefore: spaceBefore,
    comment: comment,
    hasNewline: hasNewline,
    anchor: anchor,
    tag: tag,
    newlineAfterProp: newlineAfterProp,
    end: end,
    start: start ?? end,
  }
}
