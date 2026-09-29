// Port of goldmark extension/ast/table.go.
//
// Go's `Alignment int` with iota constants becomes a BAML enum; its
// `String()` method becomes `alignment_string(a)`.

/// Alignment is a text alignment of table cells.
enum Alignment {
    /// AlignLeft indicates text should be left justified.
    AlignLeft
    /// AlignRight indicates text should be right justified.
    AlignRight
    /// AlignCenter indicates text should be centered.
    AlignCenter
    /// AlignNone indicates text should be aligned by default manner.
    AlignNone
}

/// String returns a string representation of the alignment (Go: `Alignment.String`).
function alignment_string(a: Alignment) -> string {
    match (a) {
        Alignment.AlignLeft => "left",
        Alignment.AlignRight => "right",
        Alignment.AlignCenter => "center",
        Alignment.AlignNone => "none",
    }
}

/// A Table struct represents a table of Markdown(GFM) text.
class Table {
    b: root.ast.BaseNode,

    implements root.ast.Node {
        function base(self) -> root.ast.BaseNode {
            self.b
        }

        /// Kind implements Node.Kind.
        function kind(self) -> root.ast.NodeKind {
            kind_table()
        }

        /// Dump implements Node.Dump.
        function dump(self, source: uint8array) -> root.ast.NodeDump {
            root.ast.new_node_dump(self, null)
        }
    }

    implements root.ast.BlockNode {}
}

/// KindTable is a NodeKind of the Table node.
function kind_table() -> root.ast.NodeKind {
    "Table"
}

/// NewTable returns a new Table node.
function new_table() -> Table {
    Table { b: root.ast.new_base_node() }
}

/// A TableRow struct represents a table row of Markdown(GFM) text.
class TableRow {
    b: root.ast.BaseNode,

    implements root.ast.Node {
        function base(self) -> root.ast.BaseNode {
            self.b
        }

        /// Kind implements Node.Kind.
        function kind(self) -> root.ast.NodeKind {
            kind_table_row()
        }

        /// Dump implements Node.Dump.
        function dump(self, source: uint8array) -> root.ast.NodeDump {
            root.ast.new_node_dump(self, null)
        }
    }

    implements root.ast.BlockNode {}
}

/// KindTableRow is a NodeKind of the TableRow node.
function kind_table_row() -> root.ast.NodeKind {
    "TableRow"
}

/// NewTableRow returns a new TableRow node.
function new_table_row() -> TableRow {
    TableRow { b: root.ast.new_base_node() }
}

/// A TableHeader struct represents a table header of Markdown(GFM) text.
class TableHeader {
    b: root.ast.BaseNode,

    implements root.ast.Node {
        function base(self) -> root.ast.BaseNode {
            self.b
        }

        /// Kind implements Node.Kind.
        function kind(self) -> root.ast.NodeKind {
            kind_table_header()
        }

        /// Dump implements Node.Dump.
        function dump(self, source: uint8array) -> root.ast.NodeDump {
            root.ast.new_node_dump(self, null)
        }
    }

    implements root.ast.BlockNode {}
}

/// KindTableHeader is a NodeKind of the TableHeader node.
function kind_table_header() -> root.ast.NodeKind {
    "TableHeader"
}

/// NewTableHeader returns a new TableHeader node.
function new_table_header() -> TableHeader {
    TableHeader { b: root.ast.new_base_node() }
}

/// A TableCell struct represents a table cell of Markdown(GFM) text.
class TableCell {
    b: root.ast.BaseNode,
    alignment: Alignment,

    implements root.ast.Node {
        function base(self) -> root.ast.BaseNode {
            self.b
        }

        /// Kind implements Node.Kind.
        function kind(self) -> root.ast.NodeKind {
            kind_table_cell()
        }

        /// Dump implements Node.Dump.
        function dump(self, source: uint8array) -> root.ast.NodeDump {
            root.ast.new_node_dump(self, { "Alignment": alignment_string(self.alignment) })
        }
    }

    implements root.ast.BlockNode {}
}

/// KindTableCell is a NodeKind of the TableCell node.
function kind_table_cell() -> root.ast.NodeKind {
    "TableCell"
}

/// NewTableCell returns a new TableCell node with the given alignment.
function new_table_cell(alignment: Alignment) -> TableCell {
    TableCell { b: root.ast.new_base_node(), alignment: alignment }
}

/// A TableBody struct represents a table body of Markdown(GFM) text.
class TableBody {
    b: root.ast.BaseNode,

    implements root.ast.Node {
        function base(self) -> root.ast.BaseNode {
            self.b
        }

        /// Kind implements Node.Kind.
        function kind(self) -> root.ast.NodeKind {
            kind_table_body()
        }

        /// Dump implements Node.Dump.
        function dump(self, source: uint8array) -> root.ast.NodeDump {
            root.ast.new_node_dump(self, null)
        }
    }

    implements root.ast.BlockNode {}
}

/// KindTableBody is a NodeKind of the TableBody node.
function kind_table_body() -> root.ast.NodeKind {
    "TableBody"
}

/// NewTableBody returns a new TableBody node.
function new_table_body() -> TableBody {
    TableBody { b: root.ast.new_base_node() }
}
