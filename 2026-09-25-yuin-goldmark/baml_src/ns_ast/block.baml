// Port of goldmark ast/block.go.
//
// Go's `BaseBlock` fields live in `BaseNode` (see ast.baml); the `BlockNode`
// interface's methods are default methods over them. Go's unexported
// `blockNode()` marker method is replaced by `implements BlockNode {}`.

function FLAG_BLANK_PREVIOUS_LINES() -> int {
    1
}

/// A BlockNode interface is a Node that represents a block element.
/// Some block nodes (e.g. Paragraph, Heading) hold source text segments that are
/// later parsed into inline nodes; others (e.g. CodeBlock, HTMLBlock) do not use
/// this mechanism and leave Source empty.
interface BlockNode requires Node {
    /// HasBlankPreviousLines returns true if the row before this node is blank,
    /// otherwise false.
    function has_blank_previous_lines(self) -> bool throws never {
        (self.base().flags & FLAG_BLANK_PREVIOUS_LINES()) != 0
    }

    /// SetBlankPreviousLines sets whether the row before this node is blank.
    function set_blank_previous_lines(self, v: bool) -> void throws never {
        let b = self.base();
        if (v) {
            b.flags = b.flags | FLAG_BLANK_PREVIOUS_LINES();
        } else {
            b.flags = b.flags & ~FLAG_BLANK_PREVIOUS_LINES();
        }
    }

    /// Source returns text segments that hold positions in a source.
    /// For nodes whose content is parsed into inline nodes, this holds the raw
    /// source text used as the input for inline parsing. Nodes that do not parse
    /// their content as inline elements return an empty slice.
    function source(self) -> root.text.Segment[] throws never {
        self.base().source
    }

    /// SetSource sets text segments that hold positions in a source.
    function set_source(self, v: root.text.Segment[]) -> void throws never {
        self.base().source = v;
    }

    /// AppendSource appends a text segment to the source.
    function append_source(self, seg: root.text.Segment) -> void throws never {
        self.base().source.push(seg);
    }
}

/// A Document struct is a root node of Markdown text.
class Document {
    b: BaseNode,
    meta: map<string, unknown>?,

    /// Metadata returns metadata of this document.
    function metadata(self) -> map<string, unknown> {
        let m = self.meta;
        if (m == null) {
            let fresh: map<string, unknown> = {};
            self.meta = fresh;
            return fresh;
        }
        m
    }

    /// SetMetadata sets given metadata to this document.
    function set_metadata(self, meta: map<string, unknown>) -> void {
        let m = self.metadata();
        for (let k in meta.keys()) {
            m[k] = meta[k];
        }
    }

    /// AddMeta adds given metadata to this document.
    function add_meta(self, key: string, value: unknown) -> void {
        let m = self.metadata();
        m[key] = value;
    }

    implements Node {
        function base(self) -> BaseNode {
            self.b
        }

        function kind(self) -> NodeKind {
            kind_document()
        }

        function dump(self, source: uint8array) -> NodeDump {
            new_node_dump(self, null)
        }

        function pos(self) -> int {
            0
        }

        function owner_document(self) -> Document? {
            self
        }
    }

    implements BlockNode {}
}

/// KindDocument is a NodeKind of the Document node.
function kind_document() -> NodeKind {
    "Document"
}

/// NewDocument returns a new Document node.
function new_document() -> Document {
    let n = Document { b: new_base_node(), meta: null };
    n.set_blank_previous_lines(true);
    n
}

/// A Paragraph struct represents a paragraph of Markdown text.
class Paragraph {
    b: BaseNode,

    implements Node {
        function base(self) -> BaseNode {
            self.b
        }

        function kind(self) -> NodeKind {
            kind_paragraph()
        }

        function dump(self, source: uint8array) -> NodeDump {
            new_node_dump(self, null)
        }

        function pos(self) -> int {
            let src = self.b.source;
            if (src.length() == 0) {
                return -1;
            }
            src[0].start
        }
    }

    implements BlockNode {}
}

/// KindParagraph is a NodeKind of the Paragraph node.
function kind_paragraph() -> NodeKind {
    "Paragraph"
}

/// NewParagraph returns a new Paragraph node.
function new_paragraph() -> Paragraph {
    Paragraph { b: new_base_node() }
}

/// IsParagraph returns true if the given node is a Paragraph node, otherwise false.
function is_paragraph(node: Node?) -> bool {
    if (node == null) {
        return false;
    }
    node.kind() == kind_paragraph()
}

/// HeadingKind represents the kind of a Heading: ATX or Setext.
enum HeadingKind {
    /// HeadingKindATX represents an ATX heading (e.g. ## heading).
    HeadingKindATX
    /// HeadingKindSetext represents a Setext heading (underline style).
    HeadingKindSetext
}

/// String returns a human-readable name of the HeadingKind.
function heading_kind_string(k: HeadingKind) -> string {
    match (k) {
        HeadingKind.HeadingKindATX => "ATX",
        HeadingKind.HeadingKindSetext => "Setext",
    }
}

/// A Heading struct represents headings like SetextHeading and ATXHeading.
class Heading {
    b: BaseNode,
    /// Level is the level of this heading.
    /// This value is between 1 and 6.
    level: int,
    /// HeadingKind indicates whether this is an ATX or Setext heading.
    heading_kind: HeadingKind,

    implements Node {
        function base(self) -> BaseNode {
            self.b
        }

        function kind(self) -> NodeKind {
            kind_heading()
        }

        function dump(self, source: uint8array) -> NodeDump {
            new_node_dump(self, { "Level": self.level, "HeadingKind": heading_kind_string(self.heading_kind) })
        }
    }

    implements BlockNode {}
}

/// KindHeading is a NodeKind of the Heading node.
function kind_heading() -> NodeKind {
    "Heading"
}

/// NewHeading returns a new Heading node.
function new_heading(level: int, kind: HeadingKind) -> Heading {
    Heading { b: new_base_node(), level: level, heading_kind: kind }
}

/// A ThematicBreak struct represents a thematic break of Markdown text.
class ThematicBreak {
    b: BaseNode,

    implements Node {
        function base(self) -> BaseNode {
            self.b
        }

        function kind(self) -> NodeKind {
            kind_thematic_break()
        }

        function dump(self, source: uint8array) -> NodeDump {
            new_node_dump(self, null)
        }
    }

    implements BlockNode {}
}

/// KindThematicBreak is a NodeKind of the ThematicBreak node.
function kind_thematic_break() -> NodeKind {
    "ThematicBreak"
}

/// NewThematicBreak returns a new ThematicBreak node.
function new_thematic_break() -> ThematicBreak {
    ThematicBreak { b: new_base_node() }
}

/// CodeBlockKind represents the kind of a CodeBlock: indented or fenced.
enum CodeBlockKind {
    /// CodeBlockKindIndented indicates an indented code block (4-space or tab indent).
    CodeBlockKindIndented
    /// CodeBlockKindFenced indicates a fenced code block (``` or ~~~).
    CodeBlockKindFenced
}

/// String returns a human-readable name of the CodeBlockKind.
function code_block_kind_string(k: CodeBlockKind) -> string {
    match (k) {
        CodeBlockKind.CodeBlockKindIndented => "Indented",
        CodeBlockKind.CodeBlockKindFenced => "Fenced",
    }
}

/// A CodeBlock struct represents a code block of Markdown text.
class CodeBlock {
    b: BaseNode,

    /// CodeBlockKind indicates whether this is an indented or fenced code block.
    code_block_kind: CodeBlockKind,

    /// Info is the info string of a fenced code block (e.g. language identifier).
    /// It is empty for indented code blocks.
    info: root.text.SingleLineValue,

    /// Value holds the raw content of this code block for rendering.
    value: root.text.Lines,

    /// Language returns the language extracted from the info string.
    /// Language returns null if there is no info string (Go: `("", false)`).
    function language(self, source: uint8array) -> string? {
        let v = self.info.value(source);
        if (v == "") {
            return null;
        }
        let b = v.to_utf8();
        let i = root.util.index_byte(b, 32);
        if (i < 0) {
            return v;
        }
        b.slice(0, i).to_string()
    }

    implements Node {
        function base(self) -> BaseNode {
            self.b
        }

        function kind(self) -> NodeKind {
            kind_code_block()
        }

        function dump(self, source: uint8array) -> NodeDump {
            let m: map<string, unknown> = {
                "CodeBlockKind": code_block_kind_string(self.code_block_kind),
                "Value": self.value,
            };
            if (!self.info.is_empty()) {
                m["Info"] = self.info;
            }
            new_node_dump(self, m)
        }
    }

    implements BlockNode {}
}

/// KindCodeBlock is a NodeKind of the CodeBlock node.
function kind_code_block() -> NodeKind {
    "CodeBlock"
}

/// CodeBlockOption is an option for CodeBlock nodes.
interface CodeBlockOption {
    function set_code_block_option(self, n: CodeBlock) -> void throws never
}

/// NewCodeBlock returns a new CodeBlock node with the given kind and value.
function new_code_block(kind: CodeBlockKind, value: root.text.Lines, opts: CodeBlockOption[] = []) -> CodeBlock {
    let n = CodeBlock {
        b: new_base_node(),
        code_block_kind: kind,
        info: root.text.empty_single_line_value(),
        value: value,
    };
    for (let opt in opts) {
        opt.set_code_block_option(n);
    }
    n
}

class CodeBlockInfo {
    value: root.text.SingleLineValue,

    implements CodeBlockOption {
        function set_code_block_option(self, n: CodeBlock) -> void {
            n.info = self.value;
        }
    }
}

/// WithCodeBlockInfo returns a CodeBlockOption that sets the info string of a fenced code block.
function with_code_block_info(info: root.text.SingleLineValue) -> CodeBlockOption {
    CodeBlockInfo { value: info }
}

/// A Blockquote struct represents an blockquote block of Markdown text.
class Blockquote {
    b: BaseNode,

    implements Node {
        function base(self) -> BaseNode {
            self.b
        }

        function kind(self) -> NodeKind {
            kind_blockquote()
        }

        function dump(self, source: uint8array) -> NodeDump {
            new_node_dump(self, null)
        }
    }

    implements BlockNode {}
}

/// KindBlockquote is a NodeKind of the Blockquote node.
function kind_blockquote() -> NodeKind {
    "Blockquote"
}

/// NewBlockquote returns a new Blockquote node.
function new_blockquote() -> Blockquote {
    Blockquote { b: new_base_node() }
}

/// A List struct represents a list of Markdown text.
class List {
    b: BaseNode,

    /// Marker is a marker character like '-', '+', ')' and '.'.
    marker: int,

    /// IsTight is a true if this list is a 'tight' list.
    /// See https://spec.commonmark.org/0.30/#loose for details.
    is_tight: bool,

    /// Start is an initial number of this ordered list.
    /// If this list is not an ordered list, Start is 0.
    start: int,

    /// IsOrdered returns true if this list is an ordered list, otherwise false.
    function is_ordered(self) -> bool {
        self.marker == 46 || self.marker == 41
    }

    /// CanContinue returns true if this list can continue with
    /// the given marker character and orderedness, otherwise false.
    function can_continue(self, marker: int, is_ordered: bool) -> bool {
        marker == self.marker && is_ordered == self.is_ordered()
    }

    implements Node {
        function base(self) -> BaseNode {
            self.b
        }

        function kind(self) -> NodeKind {
            kind_list()
        }

        function dump(self, source: uint8array) -> NodeDump {
            let m: map<string, unknown> = {
                "Ordered": self.is_ordered(),
                "Marker": root.util.byte_array(self.marker).to_string(),
                "Tight": self.is_tight,
            };
            if (self.is_ordered()) {
                m["Start"] = self.start;
            }
            new_node_dump(self, m)
        }
    }

    implements BlockNode {}
}

/// KindList is a NodeKind of the List node.
function kind_list() -> NodeKind {
    "List"
}

/// NewList returns a new List node.
function new_list(marker: int) -> List {
    List { b: new_base_node(), marker: marker, is_tight: true, start: 0 }
}

/// A ListItem struct represents a list item of Markdown text.
class ListItem {
    b: BaseNode,

    // offset is the content indentation offset used by the parser to continue
    // parsing subsequent lines of this list item. It is set by the list parser
    // and is not meaningful when constructing an AST programmatically.
    item_offset: int,

    /// Offset returns the content indentation offset used during parsing.
    /// This is set by the list parser and is not meaningful for programmatic construction.
    function offset(self) -> int {
        self.item_offset
    }

    /// SetOffset sets the content indentation offset.
    /// This is called by the list parser during parsing.
    function set_offset(self, v: int) -> void {
        self.item_offset = v;
    }

    implements Node {
        function base(self) -> BaseNode {
            self.b
        }

        function kind(self) -> NodeKind {
            kind_list_item()
        }

        function dump(self, source: uint8array) -> NodeDump {
            new_node_dump(self, null)
        }
    }

    implements BlockNode {}
}

/// KindListItem is a NodeKind of the ListItem node.
function kind_list_item() -> NodeKind {
    "ListItem"
}

/// NewListItem returns a new ListItem node.
function new_list_item() -> ListItem {
    ListItem { b: new_base_node(), item_offset: 0 }
}

/// HTMLBlockKind represents the kind of an HTMLBlock.
/// See https://spec.commonmark.org/0.30/#html-blocks
enum HTMLBlockKind {
    /// HTMLBlockKind1 represents type 1 html blocks.
    HTMLBlockKind1
    /// HTMLBlockKind2 represents type 2 html blocks.
    HTMLBlockKind2
    /// HTMLBlockKind3 represents type 3 html blocks.
    HTMLBlockKind3
    /// HTMLBlockKind4 represents type 4 html blocks.
    HTMLBlockKind4
    /// HTMLBlockKind5 represents type 5 html blocks.
    HTMLBlockKind5
    /// HTMLBlockKind6 represents type 6 html blocks.
    HTMLBlockKind6
    /// HTMLBlockKind7 represents type 7 html blocks.
    HTMLBlockKind7
}

/// String returns a human-readable name of the HTMLBlockKind.
function html_block_kind_string(k: HTMLBlockKind) -> string {
    match (k) {
        HTMLBlockKind.HTMLBlockKind1 => "Kind1",
        HTMLBlockKind.HTMLBlockKind2 => "Kind2",
        HTMLBlockKind.HTMLBlockKind3 => "Kind3",
        HTMLBlockKind.HTMLBlockKind4 => "Kind4",
        HTMLBlockKind.HTMLBlockKind5 => "Kind5",
        HTMLBlockKind.HTMLBlockKind6 => "Kind6",
        HTMLBlockKind.HTMLBlockKind7 => "Kind7",
    }
}

/// An HTMLBlock struct represents an html block of Markdown text.
class HTMLBlock {
    b: BaseNode,

    /// HTMLBlockKind is the kind of this html block.
    html_block_kind: HTMLBlockKind,

    /// Value holds the raw HTML content of this block for rendering.
    value: root.text.Lines,

    implements Node {
        function base(self) -> BaseNode {
            self.b
        }

        function kind(self) -> NodeKind {
            kind_html_block()
        }

        function dump(self, source: uint8array) -> NodeDump {
            new_node_dump(self, { "HTMLBlockKind": html_block_kind_string(self.html_block_kind), "Value": self.value })
        }
    }

    implements BlockNode {}
}

/// KindHTMLBlock is a NodeKind of the HTMLBlock node.
function kind_html_block() -> NodeKind {
    "HTMLBlock"
}

/// NewHTMLBlock returns a new HTMLBlock node.
function new_html_block(kind: HTMLBlockKind) -> HTMLBlock {
    HTMLBlock { b: new_base_node(), html_block_kind: kind, value: root.text.empty_lines() }
}

/// A LinkReferenceDefinition struct represents a list of Markdown text.
class LinkReferenceDefinition {
    b: BaseNode,

    /// Label is a label of this link reference definition.
    label: root.text.MultiLineValue,

    /// Destination is a destination of this link reference definition.
    destination: root.text.SingleLineValue,

    /// Title is a title of this link reference definition.
    title: root.text.MultiLineValue,

    implements Node {
        function base(self) -> BaseNode {
            self.b
        }

        function kind(self) -> NodeKind {
            kind_link_reference_definition()
        }

        function dump(self, source: uint8array) -> NodeDump {
            new_node_dump(self, { "Label": self.label, "Destination": self.destination, "Title": self.title })
        }
    }

    implements BlockNode {}
}

/// LinkReferenceDefinitionOption is an option for LinkReferenceDefinition nodes.
interface LinkReferenceDefinitionOption {
    function set_link_reference_definition_option(self, n: LinkReferenceDefinition) -> void throws never
}

/// KindLinkReferenceDefinition is a NodeKind of the LinkReferenceDefinition node.
function kind_link_reference_definition() -> NodeKind {
    "LinkReferenceDefinition"
}

/// NewLinkReferenceDefinition returns a new LinkReferenceDefinition node.
function new_link_reference_definition(
    label: root.text.MultiLineValue,
    destination: root.text.SingleLineValue,
    opts: LinkReferenceDefinitionOption[] = [],
) -> LinkReferenceDefinition {
    let n = LinkReferenceDefinition {
        b: new_base_node(),
        label: label,
        destination: destination,
        title: root.text.empty_multi_line_value(),
    };
    for (let opt in opts) {
        opt.set_link_reference_definition_option(n);
    }
    n
}
