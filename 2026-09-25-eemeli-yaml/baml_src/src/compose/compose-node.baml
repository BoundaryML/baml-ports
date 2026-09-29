// Port of src/compose/compose-node.ts
//
// The original passes `{ composeNode, composeEmptyNode }` (the `ComposeNode`
// bundle `CN`) down into the collection resolvers to avoid an import cycle.
// BAML has no import cycles to break, so the resolvers call the functions
// directly.

class ComposeContext {
  atKey: bool
  atRoot: bool
  directives: Directives
  options: Options
  schema: Schema
}

function composeNode(ctx: ComposeContext, token: Token, props: ResolvedProps, onError: ComposeErrorHandler) -> Node {
  let atKey = ctx.atKey;
  let spaceBefore = props.spaceBefore;
  let comment = props.comment;
  let anchor = props.anchor;
  let tag = props.tag;
  let node: Node? = null;
  let isSrcToken = true;
  match (token.type) {
    "alias" => {
      node = composeAlias(ctx, token, onError);
      if (anchor != null || tag != null) {
        onError(token, "ALIAS_PROPS", "An alias node must not specify any properties", false);
      }
    },
    "scalar" => {
      node = composeNodeScalar(ctx, token, anchor, tag, onError);
    },
    "single-quoted-scalar" => {
      node = composeNodeScalar(ctx, token, anchor, tag, onError);
    },
    "double-quoted-scalar" => {
      node = composeNodeScalar(ctx, token, anchor, tag, onError);
    },
    "block-scalar" => {
      node = composeNodeScalar(ctx, token, anchor, tag, onError);
    },
    "block-map" => {
      node = composeNodeCollection(ctx, token, props, onError);
    },
    "block-seq" => {
      node = composeNodeCollection(ctx, token, props, onError);
    },
    "flow-collection" => {
      node = composeNodeCollection(ctx, token, props, onError);
    },
    _ => {
      let message = if (token.type == "error") {
        token.message ?? ""
      } else {
        "Unsupported token (type: " + token.type + ")"
      };
      onError(token, "UNEXPECTED_TOKEN", message, false);
      isSrcToken = false;
    },
  }
  let n: Node = node ?? composeEmptyNode(ctx, token.offset, null, null, props, onError);
  if (anchor != null && n.anchor == "") {
    onError(anchor, "BAD_ALIAS", "Anchor cannot be an empty string", false);
  }
  if (atKey && (ctx.options.stringKeys ?? false)) {
    let ok = match (n) {
      let s: Scalar => {
        let t = s.tag;
        js_typeof(s.value) == "string" && (t == null || t == "" || t == "tag:yaml.org,2002:str")
      },
      _ => false,
    };
    if (!ok) {
      let msg = "With stringKeys, all keys must be strings";
      let src_: ErrorSource = if (tag != null) { tag } else { token };
      onError(src_, "NON_STRING_KEY", msg, false);
    }
  }
  if (spaceBefore) {
    n.spaceBefore = true;
  }
  if (comment != "") {
    if (token.type == "scalar" && token.source == "") {
      n.comment = comment;
    } else {
      n.commentBefore = comment;
    }
  }
  if ((ctx.options.keepSourceTokens ?? false) && isSrcToken) {
    n.srcToken = token;
  }
  n
}

function composeNodeScalar(ctx: ComposeContext, token: Token, anchor: Token?, tag: Token?, onError: ComposeErrorHandler) -> Node {
  let node = composeScalar(ctx, token, tag, onError);
  if (anchor != null) {
    node.anchor = str_from(tsrc(anchor), 1);
  }
  node
}

function composeNodeCollection(ctx: ComposeContext, token: Token, props: ResolvedProps, onError: ComposeErrorHandler) -> Node? {
  let anchor = props.anchor;
  // `catch_all_panics`: a stack overflow is a BAML panic, which `catch_all`
  // does not catch (JS `catch` does catch the RangeError).
  let res = composeCollection(ctx, token, props, onError) catch_all_panics (error) {
    _ => {
      // Almost certainly here due to a stack overflow
      let message = match (error) {
        let p: baml.panics.StackOverflow => p.message,
        let j: JsError => j.message,
        _ => js_string(error),
      };
      onError(token, "RESOURCE_EXHAUSTION", message, false);
      return null;
    },
  };
  if (anchor != null) {
    res.anchor = str_from(tsrc(anchor), 1);
  }
  res
}

function composeEmptyNode(
  ctx: ComposeContext,
  offset: int,
  before: Token[]?,
  pos: int?,
  props: ResolvedProps,
  onError: ComposeErrorHandler,
) -> Scalar {
  let token = Token {
    _id: new_id(),
    type: "scalar",
    offset: emptyScalarPosition(offset, before, pos),
    indent: -1,
    source: "",
  };
  let node = composeScalar(ctx, token, props.tag, onError);
  let anchor = props.anchor;
  if (anchor != null) {
    node.anchor = str_from(tsrc(anchor), 1);
    if (node.anchor == "") {
      onError(anchor, "BAD_ALIAS", "Anchor cannot be an empty string", false);
    }
  }
  if (props.spaceBefore) {
    node.spaceBefore = true;
  }
  if (props.comment != "") {
    node.comment = props.comment;
    let r = node.range;
    if (r != null) {
      r[2] = props.end;
    }
  }
  node
}

function composeAlias(ctx: ComposeContext, token: Token, onError: ComposeErrorHandler) -> Alias {
  let offset = token.offset;
  let source = tsrc(token);
  let end = token.end;
  let alias = Alias.new(str_from(source, 1));
  if (alias.source == "") {
    onError(offset, "BAD_ALIAS", "Alias cannot be an empty string", false);
  }
  if (alias.source.ends_with(":")) {
    onError(offset + source.length() - 1, "BAD_ALIAS", "Alias ending in : is ambiguous", true);
  }
  let valueEnd = offset + source.length();
  let re_ = resolveEnd(end, valueEnd, ctx.options.strict ?? true, onError);
  alias.range = [offset, valueEnd, re_.offset];
  if (re_.comment != "") {
    alias.comment = re_.comment;
  }
  alias
}
