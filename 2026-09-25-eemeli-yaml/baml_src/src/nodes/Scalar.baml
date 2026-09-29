// Port of src/nodes/Scalar.ts
//
// `class MergeKey extends Scalar<symbol>` (schema/yaml-1.1/merge.ts) is
// represented as a Scalar with `_class == "MergeKey"`: BAML has no
// inheritance.

/// `Scalar.Type = 'BLOCK_FOLDED' | 'BLOCK_LITERAL' | 'PLAIN' | 'QUOTE_DOUBLE' | 'QUOTE_SINGLE'`
type ScalarType = string

/// `(doc, ctx, map, value) => void`
type AddToJSMap = (Document?, ToJSContext, MapLike, unknown) -> void throws unknown

class Scalar {
  _id: int
  /// "Scalar" or "MergeKey"
  _class: string
  value: unknown?
  /// An optional anchor on this node. Used by alias nodes.
  anchor: string?
  /// A comment on or immediately after this node.
  comment: string?
  /// A comment before this node.
  commentBefore: string?
  /// By default (undefined), numbers use decimal notation.
  /// The YAML 1.2 core schema only supports 'HEX' and 'OCT'.
  /// The YAML 1.1 schema also supports 'BIN' and 'TIME'
  format: string?
  /// If `value` is a number that is serialized as a decimal string
  /// (i.e. not using exponential notation),
  /// use this value when stringifying this node.
  minFractionDigits: int?
  /// The `[start, value-end, node-end]` character offsets for
  /// the part of the source parsed into this node (undefined if not parsed).
  range: int[]?
  /// A blank line before this node and its commentBefore
  spaceBefore: bool?
  /// The CST token that was composed into this node.
  srcToken: Token?
  /// Set during parsing to the source string value
  source: string?
  /// A fully qualified tag, if required
  tag: string?
  /// The scalar style used for the node's string representation
  type: string?
  /// Customize the way that a key-value pair is resolved.
  /// Used for YAML 1.1 !!merge << handling.
  addToJSMap: AddToJSMap?

  function BLOCK_FOLDED() -> string {
    "BLOCK_FOLDED"
  }

  function BLOCK_LITERAL() -> string {
    "BLOCK_LITERAL"
  }

  function PLAIN() -> string {
    "PLAIN"
  }

  function QUOTE_DOUBLE() -> string {
    "QUOTE_DOUBLE"
  }

  function QUOTE_SINGLE() -> string {
    "QUOTE_SINGLE"
  }

  /// `new Scalar(value)`
  function new(value: unknown) -> Scalar {
    Scalar { _id: new_id(), _class: "Scalar", value: value }
  }

  /// Create a copy of this node.
  function clone(self) -> Scalar {
    let copy = Scalar { ...self, _id: new_id() };
    let r = self.range;
    if (r != null) {
      copy.range = r.slice(0, r.length());
    }
    copy
  }

  implements NodeBase {
    function cloneNode(self, schema: Schema?) -> Node {
      self.clone()
    }

    /// A plain JavaScript representation of this node.
    function toJS(self, doc: Document?, ctx: ToJSContext?) -> unknown {
      if (ctx != null && self.anchor != null) {
        ctx.anchors.set(self, AnchorData { node: self, aliasCount: 0, count: 1, res: self.value });
      }
      self.value
    }

    function toString(self, ctx: StringifyContext?, onComment: Callback?, onChompKeep: Callback?) -> string {
      js_string(self.value)
    }
  }
}
