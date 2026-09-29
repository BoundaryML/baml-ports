// Port of goldmark parser/list_item.go.

class ListItemParser {
    implements BlockParser {
        function trigger(self) -> uint8array? {
            root.util.bytes_of([45, 43, 42, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57])
        }

        function open(self, parent: root.ast.Node, reader: root.text.Reader, pc: Context) -> OpenResult {
            let list = match (parent) {
                let l: root.ast.List => l,
                _ => {
                    // list item must be a child of a list
                    return OpenResult { node: null, state: NO_CHILDREN() };
                }
            };
            let offset = last_offset(list);
            let line = reader.peek_line().line ?? root.util.new_bytes();
            let lm = parse_list_item(line);
            let m = lm.m;
            if (lm.typ == NOT_LIST()) {
                return OpenResult { node: null, state: NO_CHILDREN() };
            }
            if (m[1] - offset > 3) {
                return OpenResult { node: null, state: NO_CHILDREN() };
            }

            pc.set(empty_list_item_with_blank_lines_key(), null);

            let item_offset = calc_list_offset(line, m);
            let node = root.ast.new_list_item();
            node.set_offset(m[3] + item_offset);
            if (m[4] < 0 || root.util.is_blank(line.slice(m[4], m[5]))) {
                return OpenResult { node: node, state: NO_CHILDREN() };
            }

            let ip = root.util.indent_position(line.slice(m[4], line.length()), m[4], item_offset);
            let child = m[3] + ip.pos;
            reader.advance_and_set_padding(child, ip.padding);
            OpenResult { node: node, state: HAS_CHILDREN() }
        }

        function do_continue(self, node: root.ast.Node, reader: root.text.Reader, pc: Context) -> State {
            let line = reader.peek_line().line ?? root.util.new_bytes();
            if (root.util.is_blank(line)) {
                reader.advance_to_eol();
                return CONTINUE() | HAS_CHILDREN();
            }

            let np = node.parent();
            let offset = if (np == null) { 0 } else { last_offset(np) };
            let is_empty = node.child_count() == 0 && pc.get(empty_list_item_with_blank_lines_key()) != null;
            let indent = root.util.indent_width(line, reader.line_offset()).width;
            if ((is_empty || indent < offset) && indent < 4) {
                let lm = parse_list_item(line);
                // new list item found
                if (lm.typ != NOT_LIST()) {
                    pc.set(skip_list_parser_key(), list_item_flag_value());
                    return CLOSE();
                }
                if (!is_empty) {
                    return CLOSE();
                }
            }
            let ip = root.util.indent_position(line, reader.line_offset(), offset);
            reader.advance_and_set_padding(ip.pos, ip.padding);

            CONTINUE() | HAS_CHILDREN()
        }

        function close(self, node: root.ast.Node, reader: root.text.Reader, pc: Context) -> void {
            // nothing to do
        }

        function can_interrupt_paragraph(self) -> bool {
            true
        }

        function can_accept_indented_line(self) -> bool {
            false
        }
    }
}

/// NewListItemParser returns a new BlockParser that
/// parses list items.
function new_list_item_parser() -> BlockParser {
    ListItemParser {}
}
