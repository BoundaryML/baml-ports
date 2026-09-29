// Port of src/nodes/types.ts

type Collection = YAMLMap | YAMLSeq | YAMLSet

type Node = Scalar | YAMLMap | YAMLSeq | YAMLSet | Alias

/// `boolean | number | bigint | string | null`
type Primitive = bool | int | float | bigint | string | null

/// `[start, valueEnd, nodeEnd]`
type Range = int[]

/// `MapLike = Map<any, any> | Record<string | number | symbol, any>`
type MapLike = JsMap<unknown> | map<string, unknown>

/// Callback signalling that a stringifier consumed a comment / used `|+`.
type Callback = () -> void throws never

interface NodeBase {
  /// A comment on or immediately after this
  comment: string?
  /// A comment before this
  commentBefore: string?
  /// The `[start, value-end, node-end]` character offsets for the part of the
  /// source parsed into this node (undefined if not parsed). The `value-end`
  /// and `node-end` positions are themselves not included in their
  /// respective ranges.
  range: int[]?
  /// A blank line before this node and its commentBefore
  spaceBefore: bool?
  /// The CST token that was composed into this node.
  srcToken: Token?
  /// A fully qualified tag, if required
  tag: string?
  /// An optional anchor on this node. Used by alias nodes.
  /// (Declared `never` on Alias in the original; always null there.)
  anchor: string?

  /// Create a copy of this node.
  ///
  /// @param schema - If defined, overwrites the original's schema for cloned
  ///   collections.
  /// (`clone(): this` in the original; each class also has a typed `clone`.)
  function cloneNode(self, schema: Schema?) -> Node throws unknown

  /// A plain JavaScript representation of this node.
  function toJS(self, doc: Document?, ctx: ToJSContext?) -> unknown throws unknown

  function toString(self, ctx: StringifyContext?, onComment: Callback?, onChompKeep: Callback?) -> string throws unknown
}

/// `CollectionBase extends NodeBase`: `schema`, `flow`, `size`.
interface CollectionBase {
  schema: Schema
  /// If true, stringify this and all child nodes using flow styles.
  flow: bool?
  /// The number of items in this collection.
  function size(self) -> int throws never
}

/// `NodeBase` view of a node, for reading/writing shared fields.
function nb(node: Node) -> NodeBase {
  node
}
