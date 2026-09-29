// Port of src/compose/compose-collection.ts

/// `Coll.tagName` for the class of a composed collection
function collection_tag_name(coll: Node) -> string {
  match (coll) {
    let s: YAMLSeq => if (s._class == "YAMLOMap") { "tag:yaml.org,2002:omap" } else { YAMLSeq.tagName() },
    YAMLSet => YAMLSet.tagName(),
    _ => YAMLMap.tagName(),
  }
}

function resolveCollection(
  ctx: ComposeContext,
  token: Token,
  onError: ComposeErrorHandler,
  tagName: string?,
  tag: Tag?,
) -> Node {
  let coll: Node = if (token.type == "block-map") {
    resolveBlockMap(ctx, token, onError, tag)
  } else if (token.type == "block-seq") {
    resolveBlockSeq(ctx, token, onError, tag)
  } else {
    resolveFlowCollection(ctx, token, onError, tag)
  };

  let collTagName = collection_tag_name(coll);

  // If we got a tagName matching the class, or the tag name is '!',
  // then use the tagName from the node class used to create it.
  if (tagName == "!" || tagName == collTagName) {
    coll.tag = collTagName;
    return coll;
  }
  if (tagName != null && tagName != "") {
    coll.tag = tagName;
  }
  coll
}

function composeCollection(ctx: ComposeContext, token: Token, props: ResolvedProps, onError: ComposeErrorHandler) -> Node {
  let tagToken = props.tag;
  let tagName: string? = null;
  if (tagToken != null) {
    let tt: Token = tagToken;
    tagName = ctx.directives.tagName(tsrc(tt), (msg: string) -> void {
      onError(tt, "TAG_RESOLVE_FAILED", msg, false);
    });
  }

  if (token.type == "block-seq") {
    let anchor = props.anchor;
    let nl = props.newlineAfterProp;
    let lastProp: Token? = null;
    if (anchor != null && tagToken != null) {
      lastProp = if (anchor.offset > tagToken.offset) { anchor } else { tagToken };
    } else {
      lastProp = anchor ?? tagToken;
    }
    if (lastProp != null) {
      let lp: Token = lastProp;
      if (nl == null || (nl?.offset ?? 0) < lp.offset) {
        let message = "Missing newline after block sequence props";
        onError(lp, "MISSING_CHAR", message, false);
      }
    }
  }

  let expType = if (token.type == "block-map") {
    "map"
  } else if (token.type == "block-seq") {
    "seq"
  } else if (tsrc(token.fcStart ?? token) == "{") {
    "map"
  } else {
    "seq"
  };

  // shortcut: check if it's a generic YAMLMap or YAMLSeq
  // before jumping into the custom tag logic.
  if (
    tagToken == null ||
    tagName == null ||
    tagName == "" ||
    tagName == "!" ||
    (tagName == YAMLMap.tagName() && expType == "map") ||
    (tagName == YAMLSeq.tagName() && expType == "seq")
  ) {
    return resolveCollection(ctx, token, onError, tagName, null);
  }
  let tn: string = tagName ?? "";
  let tt: Token = tagToken ?? token;

  let tag = ctx.schema.tags.find((t: Tag) -> bool { t.tag == tn && t.collection == expType });

  if (tag == null) {
    let kt = ctx.schema.knownTags.get(tn);
    if (kt?.collection == expType && kt != null) {
      ctx.schema.tags.push(Tag { ...kt, default: false });
      tag = kt;
    } else {
      if (kt != null) {
        onError(tt, "BAD_COLLECTION_TYPE", kt.tag + " used for " + expType + " collection, but expects " + (kt.collection ?? "scalar"), true);
      } else {
        onError(tt, "TAG_RESOLVE_FAILED", "Unresolved tag: " + tn, true);
      }
      return resolveCollection(ctx, token, onError, tn, null);
    }
  }
  let tg: Tag = tag ?? ctx.schema.mapTag();

  let coll = resolveCollection(ctx, token, onError, tn, tg);

  let rc = tg.resolveCollection;
  let res: unknown = if (rc != null) {
    rc(coll, (msg: string) -> void {
      onError(tt, "TAG_RESOLVE_FAILED", msg, false);
    }, ctx.options) ?? coll
  } else {
    coll
  };

  let rn = as_node(res);
  let node: Node = if (rn != null) { rn } else { Scalar.new(res) };
  node.range = coll.range;
  node.tag = tn;
  let fmt = tg.format;
  if (fmt != null) {
    match (node) {
      let s: Scalar => {
        s.format = fmt;
      },
      _ => {},
    }
  }
  node
}
