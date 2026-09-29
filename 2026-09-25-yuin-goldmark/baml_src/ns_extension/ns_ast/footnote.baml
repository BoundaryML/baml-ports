// Port of goldmark extension/ast/footnote.go.

/// A FootnoteReference struct represents a reference to a footnote definition
/// in Markdown (PHP Markdown Extra) text.
class FootnoteReference {
    b: root.ast.BaseNode,

    /// Label is the label of the footnote reference (e.g. "1" for [^1]).
    label: root.text.SingleLineValue,

    /// Index is the display index of the referenced FootnoteDefinition.
    /// This is set by the footnote inline parser after the reference is
    /// registered via Footnotes.AddReference.
    index: int,

    /// RefIndex is the position of this reference among all references
    /// to the same FootnoteDefinition (0-based).
    ref_index: int,

    implements root.ast.Node {
        function base(self) -> root.ast.BaseNode {
            self.b
        }

        /// Kind implements Node.Kind.
        function kind(self) -> root.ast.NodeKind {
            kind_footnote_reference()
        }

        /// Dump implements Node.Dump.
        function dump(self, source: uint8array) -> root.ast.NodeDump {
            root.ast.new_node_dump(self, {
                "Label": self.label,
                "Index": self.index,
                "RefIndex": self.ref_index,
            })
        }
    }

    implements root.ast.InlineNode {}
}

/// KindFootnoteReference is a NodeKind of the FootnoteReference node.
function kind_footnote_reference() -> root.ast.NodeKind {
    "FootnoteReference"
}

/// NewFootnoteReference returns a new FootnoteReference node.
function new_footnote_reference(label: root.text.SingleLineValue) -> FootnoteReference {
    FootnoteReference {
        b: root.ast.new_base_node(),
        label: label,
        index: -1,
        ref_index: -1,
    }
}

/// A FootnoteDefinition struct represents a footnote definition
/// in Markdown (PHP Markdown Extra) text.
class FootnoteDefinition {
    b: root.ast.BaseNode,

    /// Label is the label of the footnote definition (e.g. "1" for [^1]: ...).
    label: root.text.SingleLineValue,

    implements root.ast.Node {
        function base(self) -> root.ast.BaseNode {
            self.b
        }

        /// Kind implements Node.Kind.
        function kind(self) -> root.ast.NodeKind {
            kind_footnote_definition()
        }

        /// Dump implements Node.Dump.
        function dump(self, source: uint8array) -> root.ast.NodeDump {
            root.ast.new_node_dump(self, { "Label": self.label })
        }
    }

    implements root.ast.BlockNode {}
}

/// KindFootnoteDefinition is a NodeKind of the FootnoteDefinition node.
function kind_footnote_definition() -> root.ast.NodeKind {
    "FootnoteDefinition"
}

/// NewFootnoteDefinition returns a new FootnoteDefinition node.
function new_footnote_definition(label: root.text.SingleLineValue) -> FootnoteDefinition {
    FootnoteDefinition {
        b: root.ast.new_base_node(),
        label: label,
    }
}
