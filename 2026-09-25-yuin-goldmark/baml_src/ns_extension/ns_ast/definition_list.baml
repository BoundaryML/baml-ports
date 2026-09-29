// Port of goldmark extension/ast/definition_list.go.
//
// Porting notes:
// - Go's unexported `offset` / `temporaryParagraph` fields are `list_offset` /
//   `temporary_paragraph_node` here (a field cannot share its name with the
//   `offset()` / `temporary_paragraph()` accessor methods).

/// A DefinitionList struct represents a definition list of Markdown
/// (PHPMarkdownExtra) text.
class DefinitionList {
    b: root.ast.BaseNode,
    list_offset: int,
    temporary_paragraph_node: root.ast.Paragraph?,

    /// Offset returns the indentation offset of this definition list (parser-internal).
    function offset(self) -> int {
        self.list_offset
    }

    /// SetOffset sets the indentation offset of this definition list (parser-internal).
    function set_offset(self, v: int) -> void {
        self.list_offset = v;
    }

    /// TemporaryParagraph returns the temporary paragraph associated with this definition list (parser-internal).
    function temporary_paragraph(self) -> root.ast.Paragraph? {
        self.temporary_paragraph_node
    }

    /// SetTemporaryParagraph sets the temporary paragraph for this definition list (parser-internal).
    function set_temporary_paragraph(self, p: root.ast.Paragraph?) -> void {
        self.temporary_paragraph_node = p;
    }

    implements root.ast.Node {
        function base(self) -> root.ast.BaseNode {
            self.b
        }

        /// Kind implements Node.Kind.
        function kind(self) -> root.ast.NodeKind {
            kind_definition_list()
        }

        /// Dump implements Node.Dump.
        function dump(self, source: uint8array) -> root.ast.NodeDump {
            root.ast.new_node_dump(self, null)
        }

        /// Pos implements Node.Pos.
        function pos(self) -> int {
            let fc = self.b.first_child;
            if (fc != null) {
                return fc.pos();
            }
            // BAML: a bare `-1` right after `}` parses as `if {..} - 1`.
            return -1;
        }
    }

    implements root.ast.BlockNode {}
}

/// KindDefinitionList is a NodeKind of the DefinitionList node.
function kind_definition_list() -> root.ast.NodeKind {
    "DefinitionList"
}

/// NewDefinitionList returns a new DefinitionList node.
function new_definition_list() -> DefinitionList {
    DefinitionList { b: root.ast.new_base_node(), list_offset: 0, temporary_paragraph_node: null }
}

/// A DefinitionTerm struct represents a definition list term of Markdown
/// (PHPMarkdownExtra) text.
class DefinitionTerm {
    b: root.ast.BaseNode,

    implements root.ast.Node {
        function base(self) -> root.ast.BaseNode {
            self.b
        }

        /// Kind implements Node.Kind.
        function kind(self) -> root.ast.NodeKind {
            kind_definition_term()
        }

        /// Dump implements Node.Dump.
        function dump(self, source: uint8array) -> root.ast.NodeDump {
            root.ast.new_node_dump(self, null)
        }

        /// Pos implements Node.Pos.
        function pos(self) -> int {
            let src = self.b.source;
            if (src.length() == 0) {
                return -1;
            }
            src[0].start
        }
    }

    implements root.ast.BlockNode {}
}

/// KindDefinitionTerm is a NodeKind of the DefinitionTerm node.
function kind_definition_term() -> root.ast.NodeKind {
    "DefinitionTerm"
}

/// NewDefinitionTerm returns a new DefinitionTerm node.
function new_definition_term() -> DefinitionTerm {
    DefinitionTerm { b: root.ast.new_base_node() }
}

/// A DefinitionDescription struct represents a definition list description of Markdown
/// (PHPMarkdownExtra) text.
class DefinitionDescription {
    b: root.ast.BaseNode,
    is_tight: bool,

    implements root.ast.Node {
        function base(self) -> root.ast.BaseNode {
            self.b
        }

        /// Kind implements Node.Kind.
        function kind(self) -> root.ast.NodeKind {
            kind_definition_description()
        }

        /// Dump implements Node.Dump.
        function dump(self, source: uint8array) -> root.ast.NodeDump {
            root.ast.new_node_dump(self, null)
        }
    }

    implements root.ast.BlockNode {}
}

/// KindDefinitionDescription is a NodeKind of the DefinitionDescription node.
function kind_definition_description() -> root.ast.NodeKind {
    "DefinitionDescription"
}

/// NewDefinitionDescription returns a new DefinitionDescription node.
function new_definition_description() -> DefinitionDescription {
    DefinitionDescription { b: root.ast.new_base_node(), is_tight: false }
}
