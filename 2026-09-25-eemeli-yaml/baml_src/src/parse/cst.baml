// Port of src/parse/cst.ts
//
// The original declares the CST as a discriminated union of plain object
// shapes (SourceToken | ErrorToken | Directive | Document | DocumentEnd |
// FlowScalar | BlockScalar | BlockMap | BlockSequence | FlowCollection), and
// the parser and `setScalarValue` mutate tokens in place, including changing
// their `type` and adding/deleting properties. A single class with optional
// fields models that faithfully; `null` stands for an absent property.
//
// Re-exports of cst-scalar / cst-stringify / cst-visit live in their own files
// (`cst_*` functions), since everything shares the root namespace.

class Token {
  _id: int
  type: string
  offset: int
  /// Absent (null) on document, directive, error and doc-end tokens.
  indent: int?
  /// Absent (null) on document and collection tokens.
  source: string?
  /// Error tokens only.
  message: string?
  /// `Document.start`: the tokens before the document value.
  start: Token[]?
  /// `FlowCollection.start`: the opening `{` or `[` source token.
  /// (Renamed: in the original both are called `start`.)
  fcStart: Token?
  /// `Document.value`
  value: Token?
  end: Token[]?
  /// `BlockScalar.props`
  props: Token[]?
  /// `BlockMap.items`, `BlockSequence.items`, `FlowCollection.items`
  items: CollectionItem[]?
}

class CollectionItem {
  _id: int
  start: Token[]
  explicitKey: bool?
  key: Token?
  sep: Token[]?
  value: Token?
}

/// A `SourceToken`: `{ type, offset, indent, source }`
function source_token(type: string, offset: int, indent: int, source: string) -> Token {
  Token { _id: new_id(), type: type, offset: offset, indent: indent, source: source }
}

function collection_item(start: Token[]) -> CollectionItem {
  CollectionItem { _id: new_id(), start: start }
}

/// Access `token.source` for tokens that always have one.
function tsrc(t: Token) -> string {
  t.source ?? ""
}

/// Access `token.indent` for tokens that always have one.
function tindent(t: Token) -> int {
  t.indent ?? 0
}

/// Access `token.items` for collection tokens.
function titems(t: Token) -> CollectionItem[] {
  let items = t.items;
  if (items == null) {
    let empty: CollectionItem[] = [];
    t.items = empty;
    return empty;
  }
  items
}

/// Access `token.end` for tokens where it has been ensured.
function tend(t: Token) -> Token[] {
  let end = t.end;
  if (end == null) {
    let empty: Token[] = [];
    return empty;
  }
  end
}

/// Access `token.props` for block scalars.
function tprops(t: Token) -> Token[] {
  let props = t.props;
  if (props == null) {
    let empty: Token[] = [];
    t.props = empty;
    return empty;
  }
  props
}

/// Access `token.start` for documents.
function tstart(t: Token) -> Token[] {
  let start = t.start;
  if (start == null) {
    let empty: Token[] = [];
    t.start = empty;
    return empty;
  }
  start
}

/// The byte order mark
function BOM() -> string {
  chr(0xfeff)
}

/// Start of doc-mode
function DOCUMENT() -> string {
  chr(0x02)
}

/// Unexpected end of flow-mode
function FLOW_END() -> string {
  chr(0x18)
}

/// Next token is a scalar value
function SCALAR() -> string {
  chr(0x1f)
}

/// @returns `true` if `token` is a flow or block collection
function cst_is_collection(token: Token?) -> bool {
  if (token == null) {
    return false;
  }
  token.items != null
}

/// @returns `true` if `token` is a flow or block scalar; not an alias
function cst_is_scalar(token: Token?) -> bool {
  if (token == null) {
    return false;
  }
  token.type == "scalar" || token.type == "single-quoted-scalar" || token.type == "double-quoted-scalar" || token.type == "block-scalar"
}

/// Get a printable representation of a lexer token
function pretty_token(token: string) -> string {
  if (token == BOM()) {
    "<BOM>"
  } else if (token == DOCUMENT()) {
    "<DOC>"
  } else if (token == FLOW_END()) {
    "<FLOW_END>"
  } else if (token == SCALAR()) {
    "<SCALAR>"
  } else {
    json_quote(token)
  }
}

/// Identify the type of a lexer token. May return `null` for unknown tokens.
function token_type(source: string) -> string? {
  if (source == BOM()) {
    return "byte-order-mark";
  }
  if (source == DOCUMENT()) {
    return "doc-mode";
  }
  if (source == FLOW_END()) {
    return "flow-error-end";
  }
  if (source == SCALAR()) {
    return "scalar";
  }
  match (source) {
    "---" => { return "doc-start"; },
    "..." => { return "doc-end"; },
    "" => { return "newline"; },
    "\n" => { return "newline"; },
    "\r\n" => { return "newline"; },
    "-" => { return "seq-item-ind"; },
    "?" => { return "explicit-key-ind"; },
    ":" => { return "map-value-ind"; },
    "{" => { return "flow-map-start"; },
    "}" => { return "flow-map-end"; },
    "[" => { return "flow-seq-start"; },
    "]" => { return "flow-seq-end"; },
    "," => { return "comma"; },
    _ => {},
  }
  match (source.at(0) ?? "") {
    " " => "space",
    "\t" => "space",
    "#" => "comment",
    "%" => "directive-line",
    "*" => "alias",
    "&" => "anchor",
    "!" => "tag",
    "'" => "single-quoted-scalar",
    "\"" => "double-quoted-scalar",
    "|" => "block-scalar-header",
    ">" => "block-scalar-header",
    _ => null,
  }
}
