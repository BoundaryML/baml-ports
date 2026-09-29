// Port of goldmark parser/blockquote.go.

class BlockquoteParser {
    function process(self, reader: root.text.Reader) -> bool {
        let line = reader.peek_line().line ?? root.util.new_bytes();
        let iw = root.util.indent_width(line, reader.line_offset());
        let w = iw.width;
        let pos = iw.pos;
        if (w > 3 || pos >= line.length() || line[pos] != 62) {
            return false;
        }
        pos += 1;
        if (pos >= line.length() || line[pos] == 10) {
            reader.advance(pos);
            return true;
        }
        reader.advance(pos);
        if (line[pos] == 32 || line[pos] == 9) {
            let padding = 0;
            if (line[pos] == 9) {
                padding = root.util.tab_width(reader.line_offset()) - 1;
            }
            reader.advance_and_set_padding(1, padding);
        }
        true
    }

    implements BlockParser {
        function trigger(self) -> uint8array? {
            root.util.bytes_of([62])
        }

        function open(self, parent: root.ast.Node, reader: root.text.Reader, pc: Context) -> OpenResult {
            if (self.process(reader)) {
                return OpenResult { node: root.ast.new_blockquote(), state: HAS_CHILDREN() };
            }
            OpenResult { node: null, state: NO_CHILDREN() }
        }

        function do_continue(self, node: root.ast.Node, reader: root.text.Reader, pc: Context) -> State {
            if (self.process(reader)) {
                return CONTINUE() | HAS_CHILDREN();
            }
            CLOSE()
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

/// NewBlockquoteParser returns a new BlockParser that
/// parses blockquotes.
function new_blockquote_parser() -> BlockParser {
    BlockquoteParser {}
}
