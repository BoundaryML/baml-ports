// Port of goldmark extension/ast/strikethrough.go.
//
// Package ast defines AST nodes that represents extension's elements

/// A Strikethrough struct represents a strikethrough of GFM text.
class Strikethrough {
    b: root.ast.BaseNode,

    implements root.ast.Node {
        function base(self) -> root.ast.BaseNode {
            self.b
        }

        /// Kind implements Node.Kind.
        function kind(self) -> root.ast.NodeKind {
            kind_strikethrough()
        }

        /// Dump implements Node.Dump.
        function dump(self, source: uint8array) -> root.ast.NodeDump {
            root.ast.new_node_dump(self, null)
        }
    }

    implements root.ast.InlineNode {}
}

/// KindStrikethrough is a NodeKind of the Strikethrough node.
function kind_strikethrough() -> root.ast.NodeKind {
    "Strikethrough"
}

/// NewStrikethrough returns a new Strikethrough node.
function new_strikethrough() -> Strikethrough {
    Strikethrough { b: root.ast.new_base_node() }
}
