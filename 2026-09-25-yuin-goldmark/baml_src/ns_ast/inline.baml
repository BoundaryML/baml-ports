// Port of goldmark ast/inline.go.
//
// Go's `BaseInline` promotes `FirstRune`/`LastRune` into every inline node and
// has an unexported `inlineNode()` marker; here `InlineNode` carries them as
// default methods, and inline classes opt in with `implements InlineNode {}`.

/// An InlineNode interface is a Node that represents an inline element.
interface InlineNode requires Node {
    /// FirstRune returns the first visible rune of this node's value, or null
    /// if the node has no visible rune (Go: `(rune, bool)`).
    function first_rune(self, source: uint8array) -> int? throws never {
        base_inline_first_rune(self, source)
    }

    /// LastRune returns the last visible rune of this node's value, or null
    /// if the node has no visible rune (Go: `(rune, bool)`).
    function last_rune(self, source: uint8array) -> int? throws never {
        base_inline_last_rune(self, source)
    }
}

/// Go's `fourByteWriter`: collects at most the first four bytes written.
class FourByteWriter {
    buf: uint8array,

    implements root.util.BufWriter {
        function write(self, p: uint8array) -> int {
            let written = 0;
            for (let b in p.to_array()) {
                if (self.buf.length() >= 4) {
                    // Go returns an error ("buffer overflow") here.
                    return written;
                }
                self.buf.push(b);
                written += 1;
            }
            written
        }

        function write_byte(self, c: int) -> void {
            if (self.buf.length() < 4) {
                self.buf.push(c);
            }
        }

        function write_rune(self, r: int) -> int {
            self.write(root.util.utf8_encode_rune(r))
        }

        function write_string(self, s: string) -> int {
            self.write(s.to_utf8())
        }

        function flush(self) -> void {
        }
    }
}

/// FirstRune implements InlineNode.FirstRune (Go: `BaseInline.FirstRune`).
function base_inline_first_rune(self_node: Node, source: uint8array) -> int? {
    let cur: Node? = self_node;
    while (cur != null) {
        match (cur) {
            let t: Text => {
                let fbw = FourByteWriter { buf: root.util.new_bytes() };
                t.value.write_to(fbw, source);
                if (fbw.buf.length() == 0) {
                    return null;
                }
                return root.util.to_rune(fbw.buf, 0);
            }
            _ => {}
        }
        cur = cur.first_child();
    }
    null
}

/// LastRune implements InlineNode.LastRune (Go: `BaseInline.LastRune`).
function base_inline_last_rune(self_node: Node, source: uint8array) -> int? {
    let cur: Node? = self_node;
    while (cur != null) {
        match (cur) {
            let t: Text => {
                let v = t.value.value(source).to_utf8();
                if (v.length() == 0) {
                    return null;
                }
                return root.util.to_rune(v, v.length() - 1);
            }
            _ => {}
        }
        cur = cur.last_child();
    }
    null
}

function TEXT_SOFT_LINE_BREAK() -> int {
    1
}

function TEXT_HARD_LINE_BREAK() -> int {
    2
}

function text_flags_string(flags: int) -> string {
    let buf: string[] = [];
    if ((flags & TEXT_SOFT_LINE_BREAK()) != 0) {
        buf.push("SoftLineBreak");
    }
    if ((flags & TEXT_HARD_LINE_BREAK()) != 0) {
        buf.push("HardLineBreak");
    }
    buf.join(", ")
}

/// A Text struct represents a textual content of the Markdown text.
class Text {
    b: BaseNode,

    /// Value is a value of this text.
    value: root.text.SingleLineValue,

    flags: int,

    /// SoftLineBreak returns true if this node ends with a new line,
    /// otherwise false.
    function soft_line_break(self) -> bool {
        (self.flags & TEXT_SOFT_LINE_BREAK()) != 0
    }

    /// SetSoftLineBreak sets whether this node ends with a new line.
    function set_soft_line_break(self, v: bool) -> void {
        if (v) {
            self.flags = self.flags | TEXT_SOFT_LINE_BREAK();
        } else {
            self.flags = self.flags & ~TEXT_SOFT_LINE_BREAK();
        }
    }

    /// HardLineBreak returns true if this node ends with a hard line break.
    /// See https://spec.commonmark.org/0.30/#hard-line-breaks for details.
    function hard_line_break(self) -> bool {
        (self.flags & TEXT_HARD_LINE_BREAK()) != 0
    }

    /// SetHardLineBreak sets whether this node ends with a hard line break.
    function set_hard_line_break(self, v: bool) -> void {
        if (v) {
            self.flags = self.flags | TEXT_HARD_LINE_BREAK();
        } else {
            self.flags = self.flags & ~TEXT_HARD_LINE_BREAK();
        }
    }

    implements Node {
        function base(self) -> BaseNode {
            self.b
        }

        function kind(self) -> NodeKind {
            kind_text()
        }

        function dump(self, source: uint8array) -> NodeDump {
            let m: map<string, unknown> = { "Value": self.value };
            let fs = text_flags_string(self.flags);
            if (fs.length() != 0) {
                m["Flags"] = fs;
            }
            new_node_dump(self, m)
        }

        /// Pos returns the start position of the text value, or -1 if the value is owned.
        function pos(self) -> int {
            if (self.value.is_owned()) {
                return -1;
            }
            self.value.index().start
        }
    }

    implements InlineNode {}
}

/// KindText is a NodeKind of the Text node.
function kind_text() -> NodeKind {
    "Text"
}

/// NewText returns a new Text node.
function new_text(value: root.text.SingleLineValue) -> Text {
    Text { b: new_base_node(), value: value, flags: 0 }
}

/// A CodeSpan struct represents a code span of Markdown text.
class CodeSpan {
    b: BaseNode,

    /// Value is the content of this code span.
    value: root.text.Value,

    /// IsBlank returns true if this node consists of spaces, otherwise false.
    function is_blank(self, source: uint8array) -> bool {
        root.util.is_blank(self.value.bytes(source))
    }

    implements Node {
        function base(self) -> BaseNode {
            self.b
        }

        function kind(self) -> NodeKind {
            kind_code_span()
        }

        function dump(self, source: uint8array) -> NodeDump {
            new_node_dump(self, { "Value": self.value })
        }
    }

    implements InlineNode {
        /// FirstRune implements InlineNode.FirstRune.
        function first_rune(self, source: uint8array) -> int? {
            let fbw = FourByteWriter { buf: root.util.new_bytes() };
            self.value.write_to(fbw, source);
            if (fbw.buf.length() == 0) {
                return null;
            }
            root.util.to_rune(fbw.buf, 0)
        }

        /// LastRune implements InlineNode.LastRune.
        function last_rune(self, source: uint8array) -> int? {
            let v = self.value.value(source).to_utf8();
            if (v.length() == 0) {
                return null;
            }
            root.util.to_rune(v, v.length() - 1)
        }
    }
}

/// KindCodeSpan is a NodeKind of the CodeSpan node.
function kind_code_span() -> NodeKind {
    "CodeSpan"
}

/// NewCodeSpan returns a new CodeSpan node.
function new_code_span(value: root.text.Value) -> CodeSpan {
    CodeSpan { b: new_base_node(), value: value }
}

/// An Emphasis struct represents an emphasis of Markdown text.
class Emphasis {
    b: BaseNode,

    implements Node {
        function base(self) -> BaseNode {
            self.b
        }

        function kind(self) -> NodeKind {
            kind_emphasis()
        }

        function dump(self, source: uint8array) -> NodeDump {
            new_node_dump(self, null)
        }
    }

    implements InlineNode {}
}

/// KindEmphasis is a NodeKind of the Emphasis node.
function kind_emphasis() -> NodeKind {
    "Emphasis"
}

/// NewEmphasis returns a new Emphasis node.
function new_emphasis() -> Emphasis {
    Emphasis { b: new_base_node() }
}

/// A Strong struct represents a strong emphasis of Markdown text.
class Strong {
    b: BaseNode,

    implements Node {
        function base(self) -> BaseNode {
            self.b
        }

        function kind(self) -> NodeKind {
            kind_strong()
        }

        function dump(self, source: uint8array) -> NodeDump {
            new_node_dump(self, null)
        }
    }

    implements InlineNode {}
}

/// KindStrong is a NodeKind of the Strong node.
function kind_strong() -> NodeKind {
    "Strong"
}

/// NewStrong returns a new Strong node.
function new_strong() -> Strong {
    Strong { b: new_base_node() }
}

/// LinkOption is an option for Link nodes.
interface LinkOption {
    function set_link_option(self, n: Link) -> void throws never
}

/// ImageOption is an option for Image nodes.
interface ImageOption {
    function set_image_option(self, n: Image) -> void throws never
}

/// Go's `linkTitle` option; implements LinkOption, ImageOption and
/// LinkReferenceDefinitionOption.
class LinkTitle {
    value: root.text.MultiLineValue,

    implements LinkOption {
        function set_link_option(self, n: Link) -> void {
            n.title = self.value;
        }
    }

    implements ImageOption {
        function set_image_option(self, n: Image) -> void {
            n.title = self.value;
        }
    }

    implements LinkReferenceDefinitionOption {
        function set_link_reference_definition_option(self, n: LinkReferenceDefinition) -> void {
            n.title = self.value;
        }
    }
}

/// WithLinkTitle returns an option that sets the title of a Link, an Image,
/// or a LinkReferenceDefinition node.
function with_link_title(title: root.text.MultiLineValue) -> LinkTitle {
    LinkTitle { value: title }
}

/// Go's `linkReference` option; implements LinkOption and ImageOption.
class LinkReferenceOption {
    kind: ReferenceLinkKind,
    value: root.text.MultiLineValue,

    implements LinkOption {
        function set_link_option(self, n: Link) -> void {
            n.reference = ReferenceLink { reference_link_kind: self.kind, value: self.value };
        }
    }

    implements ImageOption {
        function set_image_option(self, n: Image) -> void {
            n.reference = ReferenceLink { reference_link_kind: self.kind, value: self.value };
        }
    }
}

/// WithLinkReference returns an option that sets the reference of a Link or an Image node.
function with_link_reference(kind: ReferenceLinkKind, value: root.text.MultiLineValue) -> LinkReferenceOption {
    LinkReferenceOption { kind: kind, value: value }
}

/// Go's `autoLinkText` option.
class AutoLinkTextOption {
    value: root.text.SingleLineValue,

    implements AutoLinkOption {
        function set_auto_link_option(self, n: AutoLink) -> void {
            n.text = self.value;
        }
    }
}

/// WithAutoLinkText returns an option that sets the text of an AutoLink node.
function with_auto_link_text(t: root.text.SingleLineValue) -> AutoLinkOption {
    AutoLinkTextOption { value: t }
}

/// ReferenceLinkKind represents the kind of a reference link.
enum ReferenceLinkKind {
    /// ReferenceLinkKindFull represents a full reference link like `[text][label]`.
    ReferenceLinkKindFull
    /// ReferenceLinkKindCollapsed represents a collapsed reference link like `[label][]`.
    ReferenceLinkKindCollapsed
    /// ReferenceLinkKindShortcut represents a shortcut reference link like `[label]`.
    ReferenceLinkKindShortcut
}

/// String returns a human-readable name of the ReferenceLinkKind.
function reference_link_kind_string(t: ReferenceLinkKind) -> string {
    match (t) {
        ReferenceLinkKind.ReferenceLinkKindFull => "Full",
        ReferenceLinkKind.ReferenceLinkKindCollapsed => "Collapsed",
        ReferenceLinkKind.ReferenceLinkKindShortcut => "Shortcut",
    }
}

/// A ReferenceLink struct represents a reference of a link.
class ReferenceLink {
    /// ReferenceLinkKind is a kind of the reference link.
    reference_link_kind: ReferenceLinkKind,

    /// Value is the reference label value.
    value: root.text.MultiLineValue,
}

/// NewReferenceLink returns a new ReferenceLink.
function new_reference_link(kind: ReferenceLinkKind, value: root.text.MultiLineValue) -> ReferenceLink {
    ReferenceLink { reference_link_kind: kind, value: value }
}

function dump_link_like(n: Node, destination: root.text.SingleLineValue, title: root.text.MultiLineValue, reference: ReferenceLink?) -> NodeDump {
    let m: map<string, unknown> = { "Destination": destination };
    if (!title.is_empty()) {
        m["Title"] = title;
    }
    if (reference != null) {
        let r: map<string, unknown> = {
            "Kind": reference_link_kind_string(reference.reference_link_kind),
            "Value": reference.value,
        };
        m["Reference"] = r;
    }
    new_node_dump(n, m)
}

/// A Link struct represents a link of the Markdown text.
class Link {
    b: BaseNode,

    /// Destination is a destination(URL) of this link.
    destination: root.text.SingleLineValue,

    /// Title is a title of this link.
    title: root.text.MultiLineValue,

    /// Reference is a reference of this link.
    reference: ReferenceLink?,

    implements Node {
        function base(self) -> BaseNode {
            self.b
        }

        function kind(self) -> NodeKind {
            kind_link()
        }

        function dump(self, source: uint8array) -> NodeDump {
            dump_link_like(self, self.destination, self.title, self.reference)
        }
    }

    implements InlineNode {}
}

/// KindLink is a NodeKind of the Link node.
function kind_link() -> NodeKind {
    "Link"
}

/// NewLink returns a new Link node.
function new_link(destination: root.text.SingleLineValue, opts: LinkOption[] = []) -> Link {
    let n = Link {
        b: new_base_node(),
        destination: destination,
        title: root.text.empty_multi_line_value(),
        reference: null,
    };
    for (let opt in opts) {
        opt.set_link_option(n);
    }
    n
}

/// An Image struct represents an image of the Markdown text.
class Image {
    b: BaseNode,

    /// Destination is a destination(URL) of this image.
    destination: root.text.SingleLineValue,

    /// Title is a title of this image.
    title: root.text.MultiLineValue,

    /// Reference is a reference of this image.
    reference: ReferenceLink?,

    implements Node {
        function base(self) -> BaseNode {
            self.b
        }

        function kind(self) -> NodeKind {
            kind_image()
        }

        function dump(self, source: uint8array) -> NodeDump {
            dump_link_like(self, self.destination, self.title, self.reference)
        }
    }

    implements InlineNode {}
}

/// KindImage is a NodeKind of the Image node.
function kind_image() -> NodeKind {
    "Image"
}

/// NewImage returns a new Image node.
function new_image(destination: root.text.SingleLineValue, opts: ImageOption[] = []) -> Image {
    let n = Image {
        b: new_base_node(),
        destination: destination,
        title: root.text.empty_multi_line_value(),
        reference: null,
    };
    for (let opt in opts) {
        opt.set_image_option(n);
    }
    n
}

/// An AutoLink struct represents an autolink of the Markdown text.
class AutoLink {
    b: BaseNode,

    /// Destination is a destination(URL) of this autolink.
    destination: root.text.SingleLineValue,

    /// Label is a label of this autolink.
    label: root.text.SingleLineValue,

    /// Text is a text of this autolink.
    /// If empty, Label is used as a text.
    text: root.text.SingleLineValue,

    implements Node {
        function base(self) -> BaseNode {
            self.b
        }

        function kind(self) -> NodeKind {
            kind_auto_link()
        }

        function dump(self, source: uint8array) -> NodeDump {
            new_node_dump(self, { "Destination": self.destination, "Label": self.label, "Text": self.text })
        }
    }

    implements InlineNode {}
}

/// AutoLinkOption is an option for AutoLink nodes.
interface AutoLinkOption {
    function set_auto_link_option(self, n: AutoLink) -> void throws never
}

/// KindAutoLink is a NodeKind of the AutoLink node.
function kind_auto_link() -> NodeKind {
    "AutoLink"
}

/// NewAutoLink returns a new AutoLink node.
function new_auto_link(destination: root.text.SingleLineValue, label: root.text.SingleLineValue, opts: AutoLinkOption[] = []) -> AutoLink {
    let n = AutoLink {
        b: new_base_node(),
        destination: destination,
        label: label,
        text: root.text.empty_single_line_value(),
    };
    for (let opt in opts) {
        opt.set_auto_link_option(n);
    }
    n
}

/// A RawHTML struct represents an inline raw HTML of the Markdown text.
class RawHTML {
    b: BaseNode,

    /// Value is the raw HTML value.
    value: root.text.MultiLineValue,

    implements Node {
        function base(self) -> BaseNode {
            self.b
        }

        function kind(self) -> NodeKind {
            kind_raw_html()
        }

        function dump(self, source: uint8array) -> NodeDump {
            new_node_dump(self, { "Value": self.value })
        }
    }

    implements InlineNode {}
}

/// KindRawHTML is a NodeKind of the RawHTML node.
function kind_raw_html() -> NodeKind {
    "RawHTML"
}

/// NewRawHTML returns a new RawHTML node.
function new_raw_html(value: root.text.MultiLineValue) -> RawHTML {
    RawHTML { b: new_base_node(), value: value }
}
