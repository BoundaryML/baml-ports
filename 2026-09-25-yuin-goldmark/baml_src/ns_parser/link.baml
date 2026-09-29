// Port of goldmark parser/link.go.

function link_label_state_key() -> ContextKey {
    "parser.linkLabelState"
}

/// Go's unexported `linkLabelState` (an inline node that marks a `[` / `![`).
class LinkLabelState {
    b: root.ast.BaseNode,

    value: root.text.Segment,

    is_image: bool,

    has_link_descendant: bool,

    prev: LinkLabelState?,

    next: LinkLabelState?,

    first: LinkLabelState?,

    last: LinkLabelState?,

    implements root.ast.Node {
        function base(self) -> root.ast.BaseNode {
            self.b
        }

        function kind(self) -> root.ast.NodeKind {
            kind_link_label_state()
        }

        function dump(self, source: uint8array) -> root.ast.NodeDump {
            root.ast.new_node_dump(self, { "IsImage": self.is_image })
        }
    }

    implements root.ast.InlineNode {}
}

function new_link_label_state(segment: root.text.Segment, is_image: bool) -> LinkLabelState {
    LinkLabelState {
        b: root.ast.new_base_node(),
        value: segment,
        is_image: is_image,
        has_link_descendant: false,
        prev: null,
        next: null,
        first: null,
        last: null,
    }
}

function kind_link_label_state() -> root.ast.NodeKind {
    "LinkLabelState"
}

function link_label_state_length(v: LinkLabelState?) -> int {
    if (v == null) {
        return 0;
    }
    let last = v.last;
    let first = v.first;
    if (last == null || first == null) {
        return 0;
    }
    last.value.stop - first.value.start
}

function get_link_label_state(pc: Context) -> LinkLabelState? {
    match (pc.get(link_label_state_key())) {
        let s: LinkLabelState => s,
        _ => null,
    }
}

function push_link_label_state(pc: Context, v: LinkLabelState) -> void {
    let list = get_link_label_state(pc);
    if (list == null) {
        v.first = v;
        v.last = v;
        pc.set(link_label_state_key(), v);
    } else {
        let l = list.last;
        list.last = v;
        if (l != null) {
            l.next = v;
        }
        v.prev = l;
    }
}

function remove_link_label_state(pc: Context, d: LinkLabelState) -> void {
    let list = get_link_label_state(pc);
    if (list == null) {
        return;
    }

    let dprev = d.prev;
    if (dprev == null) {
        list = d.next;
        if (list != null) {
            list.first = d;
            list.last = d.last;
            list.prev = null;
            pc.set(link_label_state_key(), list);
        } else {
            pc.set(link_label_state_key(), null);
        }
    } else {
        dprev.next = d.next;
        let dnext = d.next;
        if (dnext != null) {
            dnext.prev = dprev;
        }
    }
    if (list != null && d.next == null) {
        list.last = d.prev;
    }
    d.next = null;
    d.prev = null;
    d.first = null;
    d.last = null;
}

function link_bottom_key() -> ContextKey {
    "parser.linkBottom"
}

/// Go's `linkBottom` context value is nil, a single node, or a slice of
/// nodes; this port always stores a stack of (nullable) delimiters.
class LinkBottoms {
    items: (root.ast.Node?)[],
}

class LinkParser {
    function process_link_label(self, parent: root.ast.Node, link: root.ast.Link, last: LinkLabelState, pc: Context) -> void {
        let bottom = pop_link_bottom(pc);
        process_delimiters(bottom, pc);
        let c = last.next_sibling();
        while (c != null) {
            let next = c.next_sibling();
            parent.remove_child(c);
            link.append_child(c);
            c = next;
        }
        if (!last.is_image) {
            let st = get_link_label_state(pc);
            while (st != null) {
                st.has_link_descendant = true;
                st = st.next;
            }
        }
    }

    /// Go returns `(*ast.Link, bool)`.
    function parse_reference_link(self, parent: root.ast.Node, last: LinkLabelState, block: root.text.Reader, pc: Context) -> LinkResult {
        let orgpos = block.position().segment;
        block.advance(1); // skip '['
        let maybe_reference_value = find_closure(block, 91, 93);
        if (maybe_reference_value == null) {
            return LinkResult { link: null, has_value: false };
        }

        let ref_type: root.ast.ReferenceLinkKind = root.ast.ReferenceLinkKind.ReferenceLinkKindFull;
        let maybe_reference = maybe_reference_value.bytes(block.source());
        if (root.util.is_blank(maybe_reference)) { // collapsed reference link
            maybe_reference = block.value_between(last.value.stop, orgpos.start - 1).bytes(block.source());
            ref_type = root.ast.ReferenceLinkKind.ReferenceLinkKindCollapsed;
        }
        // CommonMark spec says:
        //  > A link label can have at most 999 characters inside the square brackets.
        if (maybe_reference.length() > 999) {
            return LinkResult { link: null, has_value: true };
        }

        let ref = pc.link_definition(root.util.to_link_reference(maybe_reference));
        if (ref == null) {
            return LinkResult { link: null, has_value: true };
        }
        let link = reference_link(ref, ref_type, maybe_reference_value, block.decoder());
        self.process_link_label(parent, link, last, pc);
        LinkResult { link: link, has_value: true }
    }

    function parse_link(self, parent: root.ast.Node, last: LinkLabelState, block: root.text.Reader, pc: Context) -> root.ast.Link? {
        block.advance(1); // skip '('
        block.skip_spaces();
        let title = root.text.empty_multi_line_value();
        let destination = root.text.empty_single_line_value();
        if (block.peek() == 41) { // empty link like '[link]()'
            block.advance(1);
        } else {
            let d = parse_link_destination(block);
            if (d == null) {
                return null;
            }
            destination = d;
            block.skip_spaces();
            if (block.peek() == 41) {
                block.advance(1);
            } else {
                let t = parse_link_title(block);
                if (t == null) {
                    return null;
                }
                title = t;
                block.skip_spaces();
                if (block.peek() == 41) {
                    block.advance(1);
                } else {
                    return null;
                }
            }
        }

        let link = root.ast.new_link(destination, opts = [root.ast.with_link_title(title)]);
        self.process_link_label(parent, link, last, pc);
        link
    }

    implements InlineParser {
        function trigger(self) -> uint8array {
            root.util.bytes_of([33, 91, 93])
        }

        function parse(self, parent: root.ast.Node, block: root.text.Reader, pc: Context) -> root.ast.Node? {
            let pl = block.peek_line();
            let line = pl.line ?? root.util.new_bytes();
            let segment = pl.segment;
            if (line[0] == 33) {
                if (line.length() > 1 && line[1] == 91) {
                    block.advance(1);
                    push_link_bottom(pc);
                    return process_link_label_open(block, segment.start + 1, true, pc);
                }
                return null;
            }
            if (line[0] == 91) {
                push_link_bottom(pc);
                return process_link_label_open(block, segment.start, false, pc);
            }

            // line[0] == ']'
            let tlist = get_link_label_state(pc);
            if (tlist == null) {
                return null;
            }
            let last0 = tlist.last;
            if (last0 == null) {
                pop_link_bottom(pc);
                return null;
            }
            let last: LinkLabelState = last0;
            block.advance(1);
            remove_link_label_state(pc, last);
            let last_parent = last.parent() ?? parent;
            // CommonMark spec says:
            //  > A link label can have at most 999 characters inside the square brackets.
            if (link_label_state_length(tlist) > 998) {
                merge_or_replace_text_segment(last_parent, last, last.value, block.decoder());
                pop_link_bottom(pc);
                return null;
            }

            if (!last.is_image && last.has_link_descendant) { // a link in a link text is not allowed
                merge_or_replace_text_segment(last_parent, last, last.value, block.decoder());
                pop_link_bottom(pc);
                return null;
            }

            let c = block.peek();
            let saved = block.position();
            let link: root.ast.Link? = null;
            if (c == 40) {
                link = self.parse_link(parent, last, block, pc);
            } else if (c == 91) {
                let lr = self.parse_reference_link(parent, last, block, pc);
                link = lr.link;
                if (link == null && lr.has_value) {
                    merge_or_replace_text_segment(last_parent, last, last.value, block.decoder());
                    pop_link_bottom(pc);
                    return null;
                }
            }

            if (link == null) {
                // maybe shortcut reference link
                block.set_position(saved.line, saved.segment);
                let ssegment = root.text.new_segment(last.value.stop, segment.start);
                let maybe_reference_value = block.value_between(ssegment.start, ssegment.stop);
                let maybe_reference = maybe_reference_value.bytes(block.source());
                // CommonMark spec says:
                //  > A link label can have at most 999 characters inside the square brackets.
                if (maybe_reference.length() > 999) {
                    merge_or_replace_text_segment(last_parent, last, last.value, block.decoder());
                    pop_link_bottom(pc);
                    return null;
                }

                let ref = pc.link_definition(root.util.to_link_reference(maybe_reference));
                if (ref == null) {
                    merge_or_replace_text_segment(last_parent, last, last.value, block.decoder());
                    pop_link_bottom(pc);
                    return null;
                }
                let rl = reference_link(ref, root.ast.ReferenceLinkKind.ReferenceLinkKindShortcut, maybe_reference_value, block.decoder());
                self.process_link_label(parent, rl, last, pc);
                link = rl;
            }
            let the_link: root.ast.Link = link ?? root.ast.new_link(root.text.empty_single_line_value());
            let n: root.ast.Node = the_link;
            if (last.is_image) {
                last_parent.remove_child(last);
                let img = root.ast.new_image(the_link.destination, opts = [root.ast.with_link_title(the_link.title)]);
                img.reference = the_link.reference;
                let ch = the_link.first_child();
                while (ch != null) {
                    let next = ch.next_sibling();
                    the_link.remove_child(ch);
                    img.append_child(ch);
                    ch = next;
                }
                n = img;
            } else {
                last_parent.remove_child(last);
                n = the_link;
            }
            n.set_pos(last.value.start);
            n
        }
    }

    implements CloseBlocker {
        function close_block(self, parent: root.ast.Node, reader: root.text.Reader, pc: Context) -> void {
            pc.set(link_bottom_key(), null);
            let s = get_link_label_state(pc);
            while (s != null) {
                let next = s.next;
                remove_link_label_state(pc, s);
                let sp = s.parent();
                if (sp != null) {
                    sp.replace_child(s, root.ast.new_text(root.text.new_single_line_value_from_segment(s.value, reader.decoder())));
                }
                s = next;
            }
        }
    }
}

/// Result of `parse_reference_link` (Go: `(*ast.Link, bool)`).
class LinkResult {
    link: root.ast.Link?,
    has_value: bool,
}

/// NewLinkParser return a new InlineParser that parses links.
function new_link_parser() -> InlineParser {
    LinkParser {}
}

function process_link_label_open(block: root.text.Reader, pos: int, is_image: bool, pc: Context) -> LinkLabelState {
    let start = pos;
    if (is_image) {
        start -= 1;
    }
    let state = new_link_label_state(root.text.new_segment(start, pos + 1), is_image);
    push_link_label_state(pc, state);
    block.advance(1);
    state
}

/// Go returns `(text.MultiLineValue, bool)`; null means not found.
function find_closure(r: root.text.Reader, opener: int, closer: int) -> root.text.MultiLineValue? {
    let org = r.position();
    let segs: root.text.Segment[] = [];
    while (true) {
        let pl = r.peek_line();
        let bs = pl.line;
        let seg = pl.segment;
        if (bs == null) {
            break;
        }
        let i = 0;
        while (i < bs.length()) {
            let c = bs[i];
            if (c == 92 && i < bs.length() - 1 && root.util.is_punct(bs[i + 1])) {
                i += 2;
                continue;
            }
            if (c == closer) {
                segs.push(seg.with_stop(seg.start + i - seg.padding));
                r.advance(i + 1);
                let b = root.text.new_value_builder();
                b.decoder(r.decoder());
                for (let s in segs) {
                    b.add_segment(s);
                }
                return b.build_multi_line();
            }
            if (c == opener) {
                r.set_position(org.line, org.segment);
                return null;
            }
            i += 1;
        }
        r.advance_line();
        segs.push(seg);
    }
    r.set_position(org.line, org.segment);
    null
}

/// Go returns `(text.SingleLineValue, bool)`; null means not ok.
function parse_link_destination(block: root.text.Reader) -> root.text.SingleLineValue? {
    block.skip_spaces();
    let pl = block.peek_line();
    let line = pl.line ?? root.util.new_bytes();
    let segment = pl.segment;
    if (block.peek() == 60) {
        let i = 1;
        while (i < line.length()) {
            let c = line[i];
            if (c == 92 && i < line.length() - 1 && root.util.is_punct(line[i + 1])) {
                i += 2;
                continue;
            } else if (c == 62) {
                block.advance(i + 1);
                return root.text.new_single_line_value_from_index(root.text.new_index(segment.start + 1, segment.start + i), block.decoder());
            }
            i += 1;
        }
        return null;
    }
    let opened = 0;
    let i = 0;
    while (i < line.length()) {
        let c = line[i];
        if (c == 92 && i < line.length() - 1 && root.util.is_punct(line[i + 1])) {
            i += 2;
            continue;
        } else if (c == 40) {
            opened += 1;
        } else if (c == 41) {
            opened -= 1;
            if (opened < 0) {
                break;
            }
        } else if (root.util.is_space(c)) {
            break;
        }
        i += 1;
    }
    block.advance(i);
    if (i == 0) {
        return null;
    }
    root.text.new_single_line_value_from_index(root.text.new_index(segment.start, segment.start + i), block.decoder())
}

/// Go returns `(text.MultiLineValue, bool)`; null means not ok.
function parse_link_title(block: root.text.Reader) -> root.text.MultiLineValue? {
    block.skip_spaces();
    let opener = block.peek();
    if (opener != 34 && opener != 39 && opener != 40) {
        return null;
    }
    let closer = opener;
    if (opener == 40) {
        closer = 41;
    }
    block.advance(1);
    find_closure(block, opener, closer)
}

function get_link_bottoms(pc: Context) -> LinkBottoms? {
    match (pc.get(link_bottom_key())) {
        let b: LinkBottoms => b,
        _ => null,
    }
}

function push_link_bottom(pc: Context) -> void {
    let b: root.ast.Node? = pc.last_delimiter();
    let bottoms = get_link_bottoms(pc);
    if (bottoms == null) {
        pc.set(link_bottom_key(), LinkBottoms { items: [b] });
        return;
    }
    bottoms.items.push(b);
}

function pop_link_bottom(pc: Context) -> root.ast.Node? {
    let bottoms = get_link_bottoms(pc);
    if (bottoms == null) {
        return null;
    }
    let n = bottoms.items.length();
    if (n == 0) {
        pc.set(link_bottom_key(), null);
        return null;
    }
    let v = bottoms.items[n - 1];
    bottoms.items = bottoms.items.slice(0, n - 1);
    if (n - 1 == 0) {
        pc.set(link_bottom_key(), null);
    }
    v
}

function reference_link(def: LinkDefinition, kind: root.ast.ReferenceLinkKind, refvalue: root.text.MultiLineValue, decoder: root.text.Decoder) -> root.ast.Link {
    let ldnode: root.ast.LinkReferenceDefinition? = match (def) {
        let ld: LinkDefinitionImpl => ld.node,
        _ => null,
    };
    if (ldnode != null) {
        return root.ast.new_link(
            ldnode.destination,
            opts = [
                root.ast.with_link_title(ldnode.title),
                root.ast.with_link_reference(kind, refvalue),
            ],
        );
    }
    root.ast.new_link(
        root.text.new_single_line_value_from_string(def.destination().to_string(), decoder),
        opts = [
            root.ast.with_link_title(root.text.new_multi_line_value_from_string(def.title().to_string(), decoder)),
            root.ast.with_link_reference(kind, refvalue),
        ],
    )
}
