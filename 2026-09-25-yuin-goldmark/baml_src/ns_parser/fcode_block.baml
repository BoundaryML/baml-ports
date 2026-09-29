// Port of goldmark parser/fcode_block.go.

class FenceData {
    char: int,
    indent: int,
    length: int,
    node: root.ast.Node,
}

function fenced_code_block_info_key() -> ContextKey {
    "parser.fencedCodeBlockInfo"
}

class FencedCodeBlockParser {
    implements BlockParser {
        function trigger(self) -> uint8array? {
            root.util.bytes_of([126, 96])
        }

        function open(self, parent: root.ast.Node, reader: root.text.Reader, pc: Context) -> OpenResult {
            let pl = reader.peek_line();
            let line = pl.line ?? root.util.new_bytes();
            let segment = pl.segment;
            let pos = pc.block_offset();
            if (pos < 0) {
                return OpenResult { node: null, state: NO_CHILDREN() };
            }
            if (line[pos] != 96 && line[pos] != 126) {
                return OpenResult { node: null, state: NO_CHILDREN() };
            }
            let findent = pos;
            let fence_char = line[pos];
            let i = pos;
            while (i < line.length() && line[i] == fence_char) {
                i += 1;
            }
            let o_fence_length = i - pos;
            if (o_fence_length < 3) {
                return OpenResult { node: null, state: NO_CHILDREN() };
            }
            let info = root.text.empty_single_line_value();
            if (i < line.length() - 1) {
                let rest = line.slice(i, line.length());
                let left = root.util.trim_left_space_length(rest);
                let right = root.util.trim_right_space_length(rest);
                if (left < rest.length() - right) {
                    let info_start = segment.start - segment.padding + i + left;
                    let info_stop = segment.stop - right;
                    let value = rest.slice(left, rest.length() - right);
                    if (fence_char == 96 && root.util.index_byte(value, 96) > -1) {
                        return OpenResult { node: null, state: NO_CHILDREN() };
                    } else if (info_start != info_stop) {
                        info = root.text.new_single_line_value_from_index(root.text.new_index(info_start, info_stop), reader.decoder());
                    }
                }
            }
            let node = root.ast.new_code_block(root.ast.CodeBlockKind.CodeBlockKindFenced, root.text.empty_lines(), opts = [root.ast.with_code_block_info(info)]);
            pc.set(fenced_code_block_info_key(), FenceData { char: fence_char, indent: findent, length: o_fence_length, node: node });
            OpenResult { node: node, state: NO_CHILDREN() }
        }

        function do_continue(self, node: root.ast.Node, reader: root.text.Reader, pc: Context) -> State {
            let pl = reader.peek_line();
            let line = pl.line ?? root.util.new_bytes();
            let segment = pl.segment;
            let fdata = match (pc.get(fenced_code_block_info_key())) {
                let f: FenceData => f,
                _ => {
                    return CLOSE();
                }
            };

            let iw = root.util.indent_width(line, reader.line_offset());
            if (iw.width < 4) {
                let i = iw.pos;
                while (i < line.length() && line[i] == fdata.char) {
                    i += 1;
                }
                let length = i - iw.pos;
                if (length >= fdata.length && root.util.is_blank(line.slice(i, line.length()))) {
                    reader.advance_to_eol();
                    return CLOSE();
                }
            }
            let ip = root.util.indent_position_padding(line, reader.line_offset(), segment.padding, fdata.indent);
            let pos = ip.pos;
            let padding = ip.padding;
            if (pos < 0) {
                let fnsp = root.util.first_non_space_position(line);
                pos = (if (fnsp > 0) { fnsp } else { 0 }) - segment.padding;
                padding = 0;
            }
            let seg = root.text.new_segment_padding(segment.start + pos, segment.stop, padding);
            // if code block line starts with a tab, keep a tab as it is.
            if (padding != 0) {
                seg = preserve_leading_tab_in_code_block(seg, reader, fdata.indent);
            }
            seg = with_force_newline(seg); // EOF as newline
            match (node) {
                let cb: root.ast.CodeBlock => {
                    cb.value.append_segment(seg);
                }
                _ => {}
            }
            reader.advance_to_eol();
            CONTINUE() | NO_CHILDREN()
        }

        function close(self, node: root.ast.Node, reader: root.text.Reader, pc: Context) -> void {
            match (pc.get(fenced_code_block_info_key())) {
                let fdata: FenceData => {
                    if (root.ast.same_node(fdata.node, node)) {
                        pc.set(fenced_code_block_info_key(), null);
                    }
                }
                _ => {}
            }
        }

        function can_interrupt_paragraph(self) -> bool {
            true
        }

        function can_accept_indented_line(self) -> bool {
            false
        }
    }
}

/// NewFencedCodeBlockParser returns a new BlockParser that
/// parses fenced code blocks.
function new_fenced_code_block_parser() -> BlockParser {
    FencedCodeBlockParser {}
}
