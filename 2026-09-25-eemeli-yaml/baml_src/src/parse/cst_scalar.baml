// Port of src/parse/cst-scalar.ts

/// If `token` is a CST flow or block scalar, determine its string value and
/// a few other attributes. Otherwise, return `null`.
function resolveAsScalar(token: Token?, strict: bool, onError: ((int, string, string) -> void throws unknown)?) -> ResolvedScalar? {
  if (token == null) {
    return null;
  }
  let _onError = (pos: ErrorSource, code: string, message: string, warning: bool) -> void {
    let offset = match (pos) {
      let n: int => n,
      let arr: int[] => arr[0],
      let t: Token => t.offset,
    };
    let oe = onError;
    if (oe != null) {
      oe(offset, code, message);
    } else {
      throw YAMLParseError([offset, offset + 1], code, message);
    }
  };
  match (token.type) {
    "scalar" => resolveFlowScalar(token, strict, _onError),
    "single-quoted-scalar" => resolveFlowScalar(token, strict, _onError),
    "double-quoted-scalar" => resolveFlowScalar(token, strict, _onError),
    "block-scalar" => {
      let ctx = ComposeContext {
        atKey: false,
        atRoot: false,
        directives: Directives.new(null, null),
        options: Options { strict: strict },
        schema: Schema.new(Options {}),
      };
      resolveBlockScalar(ctx, token, _onError)
    },
    _ => null,
  }
}

class ScalarTokenContext {
  end: Token[]?
  implicitKey: bool?
  indent: int
  inFlow: bool?
  offset: int?
  type: string?
}

function cst_scalar_stringify_ctx(implicitKey: bool, indent: int, inFlow: bool) -> StringifyContext {
  let opts = defaultStringifyOptions();
  opts.blockQuote = true;
  opts.lineWidth = -1;
  StringifyContext {
    implicitKey: implicitKey,
    indent: if (indent > 0) { " ".repeat(indent) } else { "" },
    inFlow: inFlow,
    options: opts,
    anchors: js_set(),
    doc: Document.new(null, null, null),
    indentStep: "  ",
    flowCollectionPadding: " ",
  }
}

/// Create a new scalar token with `value`
///
/// Values that represent an actual string but may be parsed as a different
/// type should use a `type` other than `'PLAIN'`, as this function does not
/// support any schema operations and won't check for such conflicts.
///
/// @param value The string representation of the value, which will have its
///   content properly indented.
/// @param context.end Comments and whitespace after the end of the value, or
///   after the block scalar header. If undefined, a newline will be added.
/// @param context.implicitKey Being within an implicit key may affect the
///   resolved type of the token's value.
/// @param context.indent The indent level of the token.
/// @param context.inFlow Is this scalar within a flow collection? This may
///   affect the resolved type of the token's value.
/// @param context.offset The offset position of the token.
/// @param context.type The preferred type of the scalar token. If undefined,
///   the previous type of the `token` will be used, defaulting to `'PLAIN'`.
function createScalarToken(value: string, context: ScalarTokenContext) -> Token {
  let implicitKey = context.implicitKey ?? false;
  let indent = context.indent;
  let inFlow = context.inFlow ?? false;
  let offset = context.offset ?? -1;
  let type = context.type ?? "PLAIN";
  let source = stringifyString(
    StringifyScalar { type: type, value: value },
    cst_scalar_stringify_ctx(implicitKey, indent, inFlow),
    null,
    null,
  );
  let end = context.end ?? [source_token("newline", -1, indent, "\n")];
  match (source.at(0) ?? "") {
    "|" => createBlockScalarToken(source, offset, indent, end),
    ">" => createBlockScalarToken(source, offset, indent, end),
    "\"" => Token { _id: new_id(), type: "double-quoted-scalar", offset: offset, indent: indent, source: source, end: end },
    "'" => Token { _id: new_id(), type: "single-quoted-scalar", offset: offset, indent: indent, source: source, end: end },
    _ => Token { _id: new_id(), type: "scalar", offset: offset, indent: indent, source: source, end: end },
  }
}

function createBlockScalarToken(source: string, offset: int, indent: int, end: Token[]) -> Token {
  let he = source.index_of("\n") ?? -1;
  let head = source.slice(0, he);
  let body = str_from(source, he + 1) + "\n";
  let props: Token[] = [source_token("block-scalar-header", offset, indent, head)];
  if (!addEndtoBlockProps(props, end)) {
    props.push(source_token("newline", -1, indent, "\n"));
  }
  Token { _id: new_id(), type: "block-scalar", offset: offset, indent: indent, props: props, source: body }
}

class SetScalarValueContext {
  afterKey: bool?
  implicitKey: bool?
  inFlow: bool?
  type: string?
}

/// Set the value of `token` to the given string `value`, overwriting any
/// previous contents and type that it may have.
///
/// Best efforts are made to retain any comments previously associated with
/// the `token`, though all contents within a collection's `items` will be
/// overwritten.
///
/// Values that represent an actual string but may be parsed as a different
/// type should use a `type` other than `'PLAIN'`, as this function does not
/// support any schema operations and won't check for such conflicts.
function setScalarValue(token: Token, value: string, context0: SetScalarValueContext?) -> null {
  let context = context0 ?? SetScalarValueContext {};
  let afterKey = context.afterKey ?? false;
  let implicitKey = context.implicitKey ?? false;
  let inFlow = context.inFlow ?? false;
  let type = context.type;
  let indent = token.indent;
  if (afterKey && indent != null) {
    indent = (indent ?? 0) + 2;
  }
  if (type == null || type == "") {
    match (token.type) {
      "single-quoted-scalar" => {
        type = "QUOTE_SINGLE";
      },
      "double-quoted-scalar" => {
        type = "QUOTE_DOUBLE";
      },
      "block-scalar" => {
        let header = tprops(token)[0];
        if (header.type != "block-scalar-header") {
          throw js_error("Invalid block scalar header");
        }
        type = if (tsrc(header).at(0) == ">") { "BLOCK_FOLDED" } else { "BLOCK_LITERAL" };
      },
      _ => {
        type = "PLAIN";
      },
    }
  }
  let ind = indent;
  let source = stringifyString(
    StringifyScalar { type: type, value: value },
    cst_scalar_stringify_ctx(implicitKey || ind == null, (if ((ind ?? 0) > 0) { ind ?? 0 } else { 0 }), inFlow),
    null,
    null,
  );
  match (source.at(0) ?? "") {
    "|" => {
      setBlockScalarValue(token, source);
    },
    ">" => {
      setBlockScalarValue(token, source);
    },
    "\"" => {
      setFlowScalarValue(token, source, "double-quoted-scalar");
    },
    "'" => {
      setFlowScalarValue(token, source, "single-quoted-scalar");
    },
    _ => {
      setFlowScalarValue(token, source, "scalar");
    },
  }
  null
}

function setBlockScalarValue(token: Token, source: string) -> null {
  let he = source.index_of("\n") ?? -1;
  let head = source.slice(0, he);
  let body = str_from(source, he + 1) + "\n";
  if (token.type == "block-scalar") {
    let header = tprops(token)[0];
    if (header.type != "block-scalar-header") {
      throw js_error("Invalid block scalar header");
    }
    header.source = head;
    token.source = body;
  } else {
    let offset = token.offset;
    let indent = token.indent ?? -1;
    let props: Token[] = [source_token("block-scalar-header", offset, indent, head)];
    if (!addEndtoBlockProps(props, token.end)) {
      props.push(source_token("newline", -1, indent, "\n"));
    }

    // for (const key of Object.keys(token)) if (key !== 'type' && key !== 'offset') delete token[key]
    clear_token(token);
    token.type = "block-scalar";
    token.indent = indent;
    token.props = props;
    token.source = body;
  }
  null
}

/// Delete every property except `type` and `offset` (and the identity).
function clear_token(token: Token) -> null {
  token.indent = null;
  token.source = null;
  token.message = null;
  token.start = null;
  token.fcStart = null;
  token.value = null;
  token.end = null;
  token.props = null;
  token.items = null;
  null
}

function addEndtoBlockProps(props: Token[], end: Token[]?) -> bool {
  if (end != null) {
    for (let st in end) {
      match (st.type) {
        "space" => {
          props.push(st);
        },
        "comment" => {
          props.push(st);
        },
        "newline" => {
          props.push(st);
          return true;
        },
        _ => {},
      }
    }
  }
  false
}

function setFlowScalarValue(token: Token, source: string, type: string) -> null {
  match (token.type) {
    "scalar" => {
      token.type = type;
      token.source = source;
    },
    "double-quoted-scalar" => {
      token.type = type;
      token.source = source;
    },
    "single-quoted-scalar" => {
      token.type = type;
      token.source = source;
    },
    "block-scalar" => {
      let props = tprops(token);
      let end = props.slice(1, props.length());
      let oa = source.length();
      if (props[0].type == "block-scalar-header") {
        oa -= tsrc(props[0]).length();
      }
      for (let tok in end) {
        tok.offset += oa;
      }
      token.props = null;
      token.type = type;
      token.source = source;
      token.end = end;
    },
    "block-map" => {
      setFlowScalarValueCollection(token, source, type);
    },
    "block-seq" => {
      setFlowScalarValueCollection(token, source, type);
    },
    _ => {
      let indent = token.indent ?? -1;
      let oldEnd = token.end;
      let end: Token[] = if (oldEnd != null) {
        oldEnd.filter((st: Token) -> bool { st.type == "space" || st.type == "comment" || st.type == "newline" })
      } else {
        []
      };
      clear_token(token);
      token.type = type;
      token.indent = indent;
      token.source = source;
      token.end = end;
    },
  }
  null
}

function setFlowScalarValueCollection(token: Token, source: string, type: string) -> null {
  let offset = token.offset + source.length();
  let nl = source_token("newline", offset, token.indent ?? 0, "\n");
  token.items = null;
  token.type = type;
  token.source = source;
  token.end = [nl];
  null
}
