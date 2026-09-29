// Port of goldmark parser/thematic_break.go.

function is_thematic_break(line: uint8array, offset: int) -> bool {
    let iw = root.util.indent_width(line, offset);
    if (iw.width > 3) {
        return false;
    }
    let mark = 0;
    let count = 0;
    let i = iw.pos;
    while (i < line.length()) {
        let c = line[i];
        i += 1;
        if (root.util.is_space(c)) {
            continue;
        }
        if (mark == 0) {
            mark = c;
            count = 1;
            if (mark == 42 || mark == 45 || mark == 95) {
                continue;
            }
            return false;
        }
        if (c != mark) {
            return false;
        }
        count += 1;
    }
    count > 2
}

class ThematicBreakParser {
    implements BlockParser {
        function trigger(self) -> uint8array? {
            root.util.bytes_of([45, 42, 95])
        }

        function open(self, parent: root.ast.Node, reader: root.text.Reader, pc: Context) -> OpenResult {
            let line = reader.peek_line().line ?? root.util.new_bytes();
            if (is_thematic_break(line, reader.line_offset())) {
                reader.advance_to_eol();
                return OpenResult { node: root.ast.new_thematic_break(), state: NO_CHILDREN() };
            }
            OpenResult { node: null, state: NO_CHILDREN() }
        }

        function do_continue(self, node: root.ast.Node, reader: root.text.Reader, pc: Context) -> State {
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

/// NewThematicBreakParser returns a new BlockParser that
/// parses thematic breaks.
function new_thematic_break_parser() -> BlockParser {
    ThematicBreakParser {}
}
