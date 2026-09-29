// Port of src/compose/compose-scalar.ts

/// Result of resolveBlockScalar / resolveFlowScalar
class ResolvedScalar {
  value: string
  type: string?
  comment: string
  range: int[]
}

function composeScalar(ctx: ComposeContext, token: Token, tagToken: Token?, onError: ComposeErrorHandler) -> Scalar {
  let rs = if (token.type == "block-scalar") {
    resolveBlockScalar(ctx, token, onError)
  } else {
    resolveFlowScalar(token, ctx.options.strict ?? true, onError)
  };
  let value = rs.value;
  let type = rs.type;
  let comment = rs.comment;
  let range = rs.range;

  let tagName: string? = null;
  if (tagToken != null) {
    let tt: Token = tagToken;
    tagName = ctx.directives.tagName(tsrc(tt), (msg: string) -> void {
      onError(tt, "TAG_RESOLVE_FAILED", msg, false);
    });
  }

  let tag: Tag = ctx.schema.scalarTag();
  if ((ctx.options.stringKeys ?? false) && ctx.atKey) {
    tag = ctx.schema.scalarTag();
  } else if (tagName != null && tagName != "" && tagToken != null) {
    tag = findScalarTagByName(ctx.schema, value, tagName ?? "", tagToken, onError);
  } else if (token.type == "scalar") {
    tag = findScalarTagByTest(ctx, value, token, onError);
  } else {
    tag = ctx.schema.scalarTag();
  }

  let errSrc: ErrorSource = if (tagToken != null) { tagToken } else { token };
  let resolve = tag.resolve;
  let scalar = if (resolve != null) {
    let res = resolve(value, (msg: string) -> void {
      onError(errSrc, "TAG_RESOLVE_FAILED", msg, false);
    }, ctx.options) catch_all (error) {
      _ => {
        let msg = match (error) {
          let e: JsError => e.message,
          _ => js_string(error),
        };
        onError(errSrc, "TAG_RESOLVE_FAILED", msg, false);
        Scalar.new(value)
      },
    };
    match (res) {
      let s: Scalar => s,
      _ => Scalar.new(res),
    }
  } else {
    Scalar.new(value)
  };
  scalar.range = range;
  scalar.source = value;
  if (type != null && type != "") {
    scalar.type = type;
  }
  if (tagName != null && tagName != "") {
    scalar.tag = tagName;
  }
  if (tag.format != null && tag.format != "") {
    scalar.format = tag.format;
  }
  if (comment != "") {
    scalar.comment = comment;
  }

  scalar
}

function findScalarTagByName(schema: Schema, value: string, tagName: string, tagToken: Token, onError: ComposeErrorHandler) -> Tag {
  if (tagName == "!") {
    return schema.scalarTag(); // non-specific tag
  }
  let matchWithTest: Tag[] = [];
  for (let tag in schema.tags) {
    if (tag.collection == null && tag.tag == tagName) {
      if (tag_default_truthy(tag) && tag.testFn != null) {
        matchWithTest.push(tag);
      } else {
        return tag;
      }
    }
  }
  for (let tag in matchWithTest) {
    let t = tag.testFn;
    if (t != null) {
      if (t(value)) {
        return tag;
      }
    }
  }
  let kt = schema.knownTags.get(tagName);
  if (kt != null) {
    if (kt.collection == null) {
    // Ensure that the known tag is available for stringifying,
    // but does not get used by default.
    schema.tags.push(Tag { ...kt, default: false, testFn: null });
    return kt;
    }
  }
  onError(tagToken, "TAG_RESOLVE_FAILED", "Unresolved tag: " + tagName, tagName != "tag:yaml.org,2002:str");
  schema.scalarTag()
}

function findScalarTagByTest(ctx: ComposeContext, value: string, token: Token, onError: ComposeErrorHandler) -> Tag {
  let atKey = ctx.atKey;
  let directives = ctx.directives;
  let schema = ctx.schema;
  // (The original caches the filtered tags per schema in a WeakMap.)
  let schemaTags = schema.tags.filter((t: Tag) -> bool { t.testFn != null && tag_default_truthy(t) });
  let tag: Tag = schema.scalarTag();
  for (let t in schemaTags) {
    let d = tag_default_true(t) || (atKey && t.default == "key");
    let tf = t.testFn;
    if (d && tf != null) {
      if (tf(value)) {
        tag = t;
        break;
      }
    }
  }

  let compat_ = schema.compat;
  if (compat_ != null) {
    let compat: Tag = schema.scalarTag();
    for (let ct in compat_) {
      let tf = ct.testFn;
      if (tag_default_truthy(ct) && tf != null) {
        if (tf(value)) {
          compat = ct;
          break;
        }
      }
    }
    if (tag.tag != compat.tag) {
      let ts = directives.tagString(tag.tag);
      let cs = directives.tagString(compat.tag);
      let msg = "Value may be parsed as either " + ts + " or " + cs;
      onError(token, "TAG_RESOLVE_FAILED", msg, true);
    }
  }

  tag
}
