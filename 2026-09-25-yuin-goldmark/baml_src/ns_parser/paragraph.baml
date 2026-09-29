// Port of goldmark parser/paragraph.go.

class ParagraphParser {
    implements BlockParser {
        function trigger(self) -> uint8array? {
            null
        }

        function open(self, parent: root.ast.Node, reader: root.text.Reader, pc: Context) -> OpenResult {
            let pl = reader.peek_line();
            let line = pl.line ?? root.util.new_bytes();
            let segment = pl.segment;
            if (root.util.is_blank(line)) {
                return OpenResult { node: null, state: NO_CHILDREN() };
            }
            let node = root.ast.new_paragraph();
            node.append_source(segment.trim_left_space(reader.source()));
            reader.advance_to_eol();
            OpenResult { node: node, state: NO_CHILDREN() }
        }

        function do_continue(self, node: root.ast.Node, reader: root.text.Reader, pc: Context) -> State {
            let pl = reader.peek_line();
            let line = pl.line ?? root.util.new_bytes();
            let segment = pl.segment;
            if (root.util.is_blank(line)) {
                return CLOSE();
            }
            match (node) {
                let para: root.ast.Paragraph => {
                    para.append_source(segment.trim_left_space(reader.source()));
                }
                _ => {}
            }
            reader.advance_to_eol();
            CONTINUE() | NO_CHILDREN()
        }

        function close(self, node: root.ast.Node, reader: root.text.Reader, pc: Context) -> void {
            match (node) {
                let para: root.ast.Paragraph => {
                    let lines = para.source();
                    let length = lines.length();
                    if (length != 0) {
                        // trim trailing spaces
                        lines[length - 1] = lines[length - 1].trim_right_space(reader.source());
                    }
                    if (length == 0) {
                        let p = node.parent();
                        if (p != null) {
                            p.remove_child(node);
                        }
                        return;
                    }
                }
                _ => {}
            }
        }

        function can_interrupt_paragraph(self) -> bool {
            false
        }

        function can_accept_indented_line(self) -> bool {
            false
        }
    }
}

/// NewParagraphParser returns a new BlockParser that
/// parses paragraphs.
function new_paragraph_parser() -> BlockParser {
    ParagraphParser {}
}
