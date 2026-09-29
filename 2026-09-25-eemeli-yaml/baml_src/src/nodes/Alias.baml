// Port of src/nodes/Alias.ts

class Alias {
  _id: int
  source: string
  /// `anchor?: never` in the original; always null.
  anchor: string?
  /// A comment on or immediately after this node.
  comment: string?
  /// A comment before this node.
  commentBefore: string?
  /// The `[start, value-end, node-end]` character offsets for
  /// the part of the source parsed into this node (undefined if not parsed).
  range: int[]?
  /// A blank line before this node and its commentBefore
  spaceBefore: bool?
  /// The CST token that was composed into this node.
  srcToken: Token?
  /// `tag?: never` in the original, with a setter that throws
  /// "Alias nodes cannot have tags". BAML has no property setters, so this
  /// is a plain field that is expected to stay null.
  tag: string?

  /// `new Alias(source)`
  function new(source: string) -> Alias {
    Alias { _id: new_id(), source: source }
  }

  /// Create a copy of this node.
  function clone(self) -> Alias {
    let copy = Alias { ...self, _id: new_id() };
    let r = self.range;
    if (r != null) {
      copy.range = r.slice(0, r.length());
    }
    copy
  }

  /// Resolve the value of this alias within `doc`, finding the last
  /// instance of the `source` anchor before this node.
  function resolve(self, doc: Document, ctx: ToJSContext?) -> Node? {
    if (ctx?.maxAliasCount == 0) {
      throw js_reference_error("Alias resolution is disabled");
    }

    let nodes: Node[] = [];
    let cached = ctx?.aliasResolveCache;
    if (cached != null) {
      nodes = cached;
    } else {
      let found_nodes: Node[] = [];
      visit(doc, visitor_fns(VisitorFns {
        Node: (key: VisitKey, node: Node, path: VisitPathItem[]) -> VisitResult {
          match (node) {
            Alias => {
              found_nodes.push(node);
            },
            _ => {
              if (nb(node).anchor != null && nb(node).anchor != "") {
                found_nodes.push(node);
              }
            },
          }
          null
        },
      }));
      nodes = found_nodes;
      if (ctx != null) {
        ctx.aliasResolveCache = nodes;
      }
    }

    let found: Node? = null;
    for (let node in nodes) {
      if (js_same(node, self)) {
        break;
      }
      if (nb(node).anchor == self.source) {
        found = node;
      }
    }

    found
  }

  implements NodeBase {
    function cloneNode(self, schema: Schema?) -> Node {
      self.clone()
    }

    /// A plain JavaScript representation of the resolved value of this alias.
    function toJS(self, doc: Document?, ctx: ToJSContext?) -> unknown {
      if (doc == null) {
        throw js_type_error("A document argument is required");
      }
      let ctx_ = ctx ?? ToJSContext.new(null);

      let source = self.resolve(doc, ctx_);
      if (source == null) {
        let msg = "Unresolved alias (the anchor must be set before the alias): " + self.source;
        throw js_reference_error(msg);
      }

      ctx_.resolveAlias(doc, source)
    }

    function toString(self, ctx: StringifyContext?, onComment: Callback?, onChompKeep: Callback?) -> string {
      let src_ = "*" + self.source;
      if (ctx != null) {
        anchorIsValid(self.source);
        if (ctx.options.verifyAliasOrder && !ctx.anchors.has(self.source)) {
          let msg = "Unresolved alias (the anchor must be set before the alias): " + self.source;
          throw js_error(msg);
        }
        if (ctx.implicitKey ?? false) {
          return src_ + " ";
        }
      }
      src_
    }
  }
}
