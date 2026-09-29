// Port of goldmark ast/ast.go.
//
// Package ast defines AST nodes that represent markdown elements.
//
// Porting notes:
// - Go's `NodeKind` is an int handed out by a package-level counter
//   (`NewNodeKind`). BAML has no package-level mutable state, so a NodeKind is
//   the kind's name string; `new_node_kind(name)` just returns it.
// - Go embeds `BaseNode`/`BaseBlock`/`BaseInline` into every node struct and
//   gets the `Node` methods by promotion. BAML has no embedding, so every node
//   class holds a `BaseNode` (field `b`) and implements the `Node` interface
//   with just `base()`, `kind()` and `dump()`; all other `Node` methods are
//   interface default methods operating on `base()`. The block-only fields of
//   Go's `BaseBlock` (source segments and flags) also live in `BaseNode`.
// - Go compares nodes by pointer. BAML `==` on class instances is structural
//   (deep), so identity is checked with `same_node(a, b)` (see below).
// - Go's `iter.Seq[Node]` iterators return arrays (a snapshot, which also
//   tolerates removal during iteration, like Go's implementation).
// - Walker errors: Go walkers return `(WalkStatus, error)`. No goldmark code
//   in this port produces errors (writers are in-memory), so walkers return
//   just a WalkStatus.

/// NodeKind identifies the concrete type of a Node.
type NodeKind = string

/// NewNodeKind returns a new Kind value.
function new_node_kind(name: string) -> NodeKind {
    name
}

/// An Attribute is an attribute of the Node.
class Attribute {
    name: string,
    value: root.text.MultiLineValue,
}

/// A BaseNode struct implements the Node interface partially.
///
/// This also carries Go's `BaseBlock` fields (`source` and `flags`), which are
/// only used by block nodes.
class BaseNode {
    first_child: Node?,
    last_child: Node?,
    parent: Node?,
    next: Node?,
    prev: Node?,
    child_count: int,
    attributes: Attribute[]?,
    pos: int,
    // Not in Go: scratch slot used by `same_node` to test reference identity.
    mark: int,
    // Go BaseBlock.source (raw source text that will be parsed into inline nodes).
    source: root.text.Segment[],
    // Go BaseBlock.flags.
    flags: int,
}

/// Go: `BaseNode.Init(self)`; returns a fresh BaseNode with `pos == -1`.
function new_base_node() -> BaseNode {
    BaseNode {
        first_child: null,
        last_child: null,
        parent: null,
        next: null,
        prev: null,
        child_count: 0,
        attributes: null,
        pos: -1,
        mark: 0,
        source: [],
        flags: 0,
    }
}

/// Reference identity (Go: `a == b` on node pointers / interfaces).
///
/// BAML has no identity comparison, so this temporarily writes a sentinel into
/// `a`'s scratch slot and checks whether `b` observes it.
function same_node(a: Node?, b: Node?) -> bool {
    if (a == null) {
        return b == null;
    }
    if (b == null) {
        return false;
    }
    let ba = a.base();
    let bb = b.base();
    let old = ba.mark;
    ba.mark = -0x5EED;
    let r = bb.mark == -0x5EED;
    ba.mark = old;
    r
}

/// A Node interface defines basic AST node functionalities.
interface Node {
    /// Returns the embedded BaseNode (Go: struct embedding).
    function base(self) -> BaseNode throws never

    /// Kind returns a kind of this node.
    function kind(self) -> NodeKind throws never

    /// Dump dumps an AST node.
    function dump(self, source: uint8array) -> NodeDump throws never

    /// Pos returns a position of this node in a source.
    /// If this node position is not defined, Pos returns -1.
    function pos(self) -> int throws never {
        self.base().pos
    }

    /// SetPos sets a position of this node in a source.
    /// Some node may ignore this method. For example, Paragraph node ignores this method because
    /// it calculates its position from its lines.
    function set_pos(self, v: int) -> void throws never {
        self.base().pos = v;
    }

    /// NextSibling returns a next sibling node of this node.
    function next_sibling(self) -> Node? throws never {
        self.base().next
    }

    /// PreviousSibling returns a previous sibling node of this node.
    function previous_sibling(self) -> Node? throws never {
        self.base().prev
    }

    /// Parent returns a parent node of this node.
    function parent(self) -> Node? throws never {
        self.base().parent
    }

    /// SetParent sets a parent node to this node.
    function set_parent(self, v: Node?) -> void throws never {
        self.base().parent = v;
    }

    /// SetPreviousSibling sets a previous sibling node to this node.
    function set_previous_sibling(self, v: Node?) -> void throws never {
        self.base().prev = v;
    }

    /// SetNextSibling sets a next sibling node to this node.
    function set_next_sibling(self, v: Node?) -> void throws never {
        self.base().next = v;
    }

    /// HasChildren returns true if this node has any children, otherwise false.
    function has_children(self) -> bool throws never {
        self.base().first_child != null
    }

    /// ChildCount returns a total number of children.
    function child_count(self) -> int throws never {
        self.base().child_count
    }

    /// Children returns the children of this node (Go: an iterator).
    function children(self) -> Node[] throws never {
        let out: Node[] = [];
        let c = self.base().first_child;
        while (c != null) {
            out.push(c);
            c = c.next_sibling();
        }
        out
    }

    /// FirstChild returns a first child of this node.
    function first_child(self) -> Node? throws never {
        self.base().first_child
    }

    /// LastChild returns a last child of this node.
    function last_child(self) -> Node? throws never {
        self.base().last_child
    }

    /// AppendChild append a node child to the tail of the children.
    function append_child(self, v: Node) -> void throws never {
        ensure_isolated(v);
        let b = self.base();
        let last = b.last_child;
        if (b.first_child == null || last == null) {
            b.first_child = v;
            v.set_next_sibling(null);
            v.set_previous_sibling(null);
        } else {
            last.set_next_sibling(v);
            v.set_previous_sibling(last);
        }
        v.set_parent(self);
        b.last_child = v;
        b.child_count += 1;
    }

    /// RemoveChild removes a node child from this node.
    /// If a node child is not children of this node, RemoveChild nothing to do.
    function remove_child(self, v: Node) -> void throws never {
        if (!same_node(v.parent(), self)) {
            return;
        }
        let b = self.base();
        b.child_count -= 1;
        let prev = v.previous_sibling();
        let next = v.next_sibling();
        if (prev != null) {
            prev.set_next_sibling(next);
        } else {
            b.first_child = next;
        }
        if (next != null) {
            next.set_previous_sibling(prev);
        } else {
            b.last_child = prev;
        }
        v.set_parent(null);
        v.set_previous_sibling(null);
        v.set_next_sibling(null);
    }

    /// RemoveChildren removes all children from this node.
    function remove_children(self) -> void throws never {
        let b = self.base();
        let c = b.first_child;
        while (c != null) {
            c.set_parent(null);
            c.set_previous_sibling(null);
            let next = c.next_sibling();
            c.set_next_sibling(null);
            c = next;
        }
        b.first_child = null;
        b.last_child = null;
        b.child_count = 0;
    }

    /// ReplaceChild replaces a node target with a node insertee.
    /// If target is not a child of this node, ReplaceChild appends insertee to the
    /// tail of the children.
    function replace_child(self, target: Node, insertee: Node) -> void throws never {
        self.insert_before(target, insertee);
        self.remove_child(target);
    }

    /// InsertAfter inserts a node insertee after a node target.
    /// If target is not a child of this node, InsertAfter appends insertee to the
    /// tail of the children.
    function insert_after(self, target: Node, insertee: Node) -> void throws never {
        self.insert_before(target.next_sibling(), insertee);
    }

    /// InsertBefore inserts a node insertee before a node target.
    /// If target is not a child of this node, InsertBefore appends insertee to the
    /// tail of the children.
    function insert_before(self, target: Node?, insertee: Node) -> void throws never {
        let b = self.base();
        b.child_count += 1;
        if (target == null) {
            // NOTE: Go increments childCount here and then AppendChild increments it
            // again; ported as-is.
            self.append_child(insertee);
            return;
        }
        ensure_isolated(insertee);
        if (same_node(target.parent(), self)) {
            let c = target;
            let prev = c.previous_sibling();
            if (prev != null) {
                prev.set_next_sibling(insertee);
                insertee.set_previous_sibling(prev);
            } else {
                b.first_child = insertee;
                insertee.set_previous_sibling(null);
            }
            insertee.set_next_sibling(c);
            c.set_previous_sibling(insertee);
            insertee.set_parent(self);
        }
    }

    /// OwnerDocument returns this node's owner document.
    /// If this node is not a child of the Document node, OwnerDocument
    /// returns nil.
    function owner_document(self) -> Document? throws never {
        let d0 = self.parent();
        if (d0 == null) {
            // Go dereferences a nil parent here (panics); a detached node has
            // no owner document.
            return null;
        }
        // BAML: a loop-carried `Node?` local is not re-narrowed, so keep a
        // non-optional local.
        let d: Node = d0;
        while (true) {
            let p = d.parent();
            if (p == null) {
                match (d) {
                    let doc: Document => {
                        return doc;
                    }
                    _ => {}
                }
                break;
            }
            d = p;
        }
        null
    }

    /// SetAttribute sets the given value to the attributes.
    function set_attribute(self, name: string, value: root.text.MultiLineValue) -> void throws never {
        let b = self.base();
        let attrs = b.attributes;
        if (attrs == null) {
            b.attributes = [Attribute { name: name, value: value }];
            return;
        }
        for (let a in attrs) {
            if (a.name == name) {
                a.value = value;
                return;
            }
        }
        attrs.push(Attribute { name: name, value: value });
    }

    /// Attribute returns an attribute value if an attribute associated with the
    /// given name is found, otherwise null (Go: `(zero MultiLineValue, false)`).
    function attribute(self, name: string) -> root.text.MultiLineValue? throws never {
        let attrs = self.base().attributes;
        if (attrs == null) {
            return null;
        }
        for (let a in attrs) {
            if (a.name == name) {
                return a.value;
            }
        }
        null
    }

    /// Attributes returns a list of attributes.
    /// This may be a nil if there are no attributes.
    function attributes(self) -> Attribute[]? throws never {
        self.base().attributes
    }

    /// RemoveAttributes removes all attributes from this node.
    function remove_attributes(self) -> void throws never {
        self.base().attributes = null;
    }
}

function ensure_isolated(v: Node) -> void {
    let p = v.parent();
    if (p != null) {
        p.remove_child(v);
    }
}

/// NodeDump is a struct that holds information for dumping a node.
class NodeDump {
    /// Node is the node to be dumped.
    node: Node,

    /// Properties is a map of additional properties to be dumped.
    /// Property names should be PascalCase.
    properties: map<string, unknown>?,

    /// Children returns the dumps of the children of this node dump.
    function children(self, source: uint8array) -> NodeDump[] {
        let out: NodeDump[] = [];
        let c = self.node.first_child();
        while (c != null) {
            out.push(c.dump(source));
            c = c.next_sibling();
        }
        out
    }

    /// PrettyPrint pretty prints this node dump to the given writer.
    ///
    /// PrettyPrint format may change in the future. Do not rely on the format.
    /// This method is intended for debugging purpose only.
    function pretty_print(self, w: root.util.BufWriter, source: uint8array, opts: PrettyPrintOption[] = []) -> void {
        let cfg = PpCfg { level: 0, include_source: false };
        for (let opt in opts) {
            opt(cfg);
        }
        let ww = w;
        let l = cfg.level;
        let n = self.node;
        let name = n.kind();
        let indent = "    ".repeat(l);
        ww.write_string(indent + name + " {\n");
        let indent2 = "    ".repeat(l + 1);
        let p: map<string, unknown> = {};
        let props = self.properties;
        if (props != null) {
            for (let k in props.keys()) {
                p[k] = props[k];
            }
        }
        if (n.pos() > -1) {
            p["Pos"] = n.pos();
        }
        match (n) {
            let b: BlockNode => {
                if (cfg.include_source) {
                    if (b.source().length() != 0) {
                        p["Source"] = root.text.new_lines_from_segments(b.source()).str(source);
                    }
                }
                p["HasBlankPreviousLines"] = b.has_blank_previous_lines();
            }
            _ => {}
        }
        for (let k in p.keys()) {
            ww.write_string(indent2 + k + ": ");
            dump_value(ww, p[k], source, l + 1);
        }
        let attrs = n.attributes();
        let has_attrs = if (attrs == null) { false } else { attrs.length() > 0 };
        if (has_attrs && attrs != null) {
            let ats: unknown[] = [];
            for (let attr in attrs) {
                let m: map<string, unknown> = { "Name": attr.name, "Value": attr.value.value(source) };
                ats.push(m);
            }
            ww.write_string(indent2 + "Attributes: ");
            dump_value(ww, ats, source, l + 1);
        }
        if (n.has_children()) {
            ww.write_string(indent2 + "Children: [\n");
            for (let cd in self.children(source)) {
                let copts: PrettyPrintOption[] = opts.slice(0, opts.length());
                copts.push(with_level(l + 2));
                cd.pretty_print(ww, source, opts = copts);
            }
            ww.write_string(indent2 + "]\n");
        }
        ww.write_string(indent + "}\n");
        ww.flush();
    }
}

/// NewNodeDump returns a new NodeDump.
function new_node_dump(node: Node, properties: map<string, unknown>?) -> NodeDump {
    NodeDump { node: node, properties: properties }
}

class PpCfg {
    level: int,
    include_source: bool,
}

/// PrettyPrintOption is a function that modifies the configuration of PrettyPrint.
type PrettyPrintOption = (cfg: PpCfg) -> void throws never

/// WithLevel returns an option that sets the indentation level for PrettyPrint.
function with_level(level: int) -> PrettyPrintOption {
    (cfg: PpCfg) -> void {
        cfg.level = level;
    }
}

/// WithSource returns an option that sets whether to include the source text in the PrettyPrint output.
function with_source(include: bool) -> PrettyPrintOption {
    (cfg: PpCfg) -> void {
        cfg.include_source = include;
    }
}

/// Go's `fmt.Sprintf("%v", v)` for the scalar values goldmark dumps.
function format_any(v: unknown) -> string {
    match (v) {
        let s: string => s,
        let i: int => i.to_string(),
        let f: float => f.to_string(),
        let b: bool => if (b) { "true" } else { "false" },
        null => "<nil>",
        _ => baml.String.from(v),
    }
}

function dump_value(ww: root.util.BufWriter, v: unknown, source: uint8array, level: int) -> void {
    let indent = "    ".repeat(level);
    let indent2 = "    ".repeat(level + 1);
    match (v) {
        let m: map<string, unknown> => {
            ww.write_string("{\n");
            for (let k in m.keys()) {
                ww.write_string(indent2 + k + ": ");
                dump_value(ww, m[k], source, level + 1);
            }
            ww.write_string(indent + "}\n");
        }
        let a: unknown[] => {
            ww.write_string("[\n");
            for (let x in a) {
                ww.write_string(indent2);
                dump_value(ww, x, source, level + 1);
            }
            ww.write_string(indent + "]\n");
        }
        // Go: `interface{ Value([]byte) string }`
        let tv: root.text.Value => {
            ww.write_string(tv.value(source) + "\n");
        }
        // Go: `interface{ Str([]byte) string }`
        let ls: root.text.Lines => {
            ww.write_string(ls.str(source) + "\n");
        }
        let sg: root.text.Segment => {
            ww.write_string(sg.str(source) + "\n");
        }
        _ => {
            ww.write_string(format_any(v) + "\n");
        }
    }
}

/// WalkStatus represents a current status of the Walk function.
enum WalkStatus {
    /// WalkStop indicates no more walking needed.
    WalkStop
    /// WalkSkipChildren indicates that Walk will not walk on children of the current
    /// node.
    WalkSkipChildren
    /// WalkContinue indicates that Walk can continue to walk.
    WalkContinue
}

/// Walker is a function that will be called when Walk find a
/// new node.
/// entering is set true before walks children, false after walked children.
type Walker = (n: Node, entering: bool) -> WalkStatus throws never

/// Walk walks a AST tree by the depth first search algorithm.
function walk(n: Node, walker: Walker) -> void {
    walk_helper(n, walker);
}

function walk_helper(n: Node, walker: Walker) -> WalkStatus {
    let status = walker(n, true);
    if (status == WalkStatus.WalkStop) {
        return status;
    }
    if (status != WalkStatus.WalkSkipChildren) {
        let c = n.first_child();
        while (c != null) {
            let st = walk_helper(c, walker);
            if (st == WalkStatus.WalkStop) {
                return WalkStatus.WalkStop;
            }
            c = c.next_sibling();
        }
    }
    let status2 = walker(n, false);
    if (status2 == WalkStatus.WalkStop) {
        return WalkStatus.WalkStop;
    }
    WalkStatus.WalkContinue
}

/// N is a helper function to create a new node with children.
///
/// Children must be a Node or a string. If a child is a string,
/// N creates a Text node with the string and append it to the children.
/// Given string must be a decoded string:
///
/// - Good: `N(NewParagraph(), "Hello, World!")`
/// - Bad: `N(NewParagraph(), "Hello, World&#33;")`
///
/// (Go takes variadic `...any` and panics on other types; BAML takes a typed
/// array of `Node | string`.)
function n(node: Node, children: (Node | string)[]) -> Node {
    for (let c in children) {
        match (c) {
            let s: string => {
                if (!s.includes("\n")) {
                    let t = new_text(root.text.new_single_line_value_from_string(s, null));
                    node.append_child(t);
                } else {
                    let b = s.to_utf8();
                    let k = 0;
                    let i = 0;
                    while (i < b.length()) {
                        if (b[i] == 10) {
                            if (k <= i) {
                                let t = new_text(root.text.new_single_line_value_from_index(root.text.new_index(k, i + 1), null));
                                node.append_child(t);
                                k = i + 1;
                            }
                        }
                        i += 1;
                    }
                    if (k < b.length()) {
                        let t = new_text(root.text.new_single_line_value_from_index(root.text.new_index(k, b.length()), null));
                        node.append_child(t);
                    }
                }
            }
            let nd: Node => {
                node.append_child(nd);
            }
        }
    }
    node
}
