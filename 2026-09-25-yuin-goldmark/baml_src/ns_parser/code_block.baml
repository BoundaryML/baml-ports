// Port of goldmark parser/code_block.go.

class CodeBlockParser {
    implements BlockParser {
        function trigger(self) -> uint8array? {
            null
        }

        function open(self, parent: root.ast.Node, reader: root.text.Reader, pc: Context) -> OpenResult {
            let pl = reader.peek_line();
            let line = pl.line ?? root.util.new_bytes();
            let segment = pl.segment;
            let ip = root.util.indent_position_padding(line, reader.line_offset(), segment.padding, 4);
            if (ip.pos < 0 || root.util.is_blank(line)) {
                return OpenResult { node: null, state: NO_CHILDREN() };
            }
            let node = root.ast.new_code_block(root.ast.CodeBlockKind.CodeBlockKindIndented, root.text.empty_lines());
            let seg = root.text.new_segment_padding(segment.start + ip.pos, segment.stop, ip.padding);
            // if code block line starts with a tab, keep a tab as it is.
            if (seg.padding != 0) {
                seg = preserve_leading_tab_in_code_block(seg, reader, 0);
            }
            seg = with_force_newline(seg);
            node.value.append_segment(seg);
            reader.advance_to_eol();
            OpenResult { node: node, state: NO_CHILDREN() }
        }

        function do_continue(self, node: root.ast.Node, reader: root.text.Reader, pc: Context) -> State {
            let cb = match (node) {
                let c: root.ast.CodeBlock => c,
                _ => {
                    return CLOSE();
                }
            };
            let pl = reader.peek_line();
            let line = pl.line ?? root.util.new_bytes();
            let segment = pl.segment;
            let ip = root.util.indent_position_padding(line, reader.line_offset(), segment.padding, 4);

            if (root.util.is_blank(line) && ip.pos < 0) {
                segment = root.text.new_segment(segment.stop - 1, segment.stop);
            } else if (ip.pos < 0) {
                return CLOSE();
            } else {
                segment = with_force_newline(root.text.new_segment_padding(segment.start + ip.pos, segment.stop, ip.padding));
                // if code block line starts with a tab, keep a tab as it is.
                if (segment.padding != 0) {
                    segment = preserve_leading_tab_in_code_block(segment, reader, 0);
                }
            }
            cb.value.append_segment(segment);
            reader.advance_to_eol();
            CONTINUE() | NO_CHILDREN()
        }

        function close(self, node: root.ast.Node, reader: root.text.Reader, pc: Context) -> void {
            // trim trailing blank lines
            match (node) {
                let cb: root.ast.CodeBlock => {
                    let segs0 = cb.value.segments();
                    let length = segs0.length() - 1;
                    let source = reader.source();
                    while (length >= 0) {
                        let line = segs0[length];
                        if (root.util.is_blank(line.bytes(source))) {
                            length -= 1;
                        } else {
                            break;
                        }
                    }
                    // rebuild Lines with only [0, length+1) segments
                    if (length < 0) {
                        // Go: NewLinesFromSegments(nil) is an owned, empty Lines.
                        cb.value = root.text.empty_lines();
                    } else {
                        cb.value = root.text.new_lines_from_segments(segs0.slice(0, length + 1));
                    }
                }
                _ => {}
            }
        }

        function can_interrupt_paragraph(self) -> bool {
            false
        }

        function can_accept_indented_line(self) -> bool {
            true
        }
    }
}

/// NewCodeBlockParser returns a new BlockParser that
/// parses code blocks.
function new_code_block_parser() -> BlockParser {
    CodeBlockParser {}
}

/// Go sets `segment.ForceNewline = true` on a local copy.
function with_force_newline(s: root.text.Segment) -> root.text.Segment {
    root.text.Segment { start: s.start, stop: s.stop, padding: s.padding, force_newline: true }
}

/// Go mutates `*segment` in place; here the (possibly) updated segment is returned.
function preserve_leading_tab_in_code_block(segment: root.text.Segment, reader: root.text.Reader, indent: int) -> root.text.Segment {
    let offset_with_padding = reader.line_offset() + indent;
    let p = reader.position();
    let sl = p.line;
    let ss = p.segment;
    reader.set_position(sl, root.text.new_segment(ss.start - 1, ss.stop));
    let result = segment;
    if (offset_with_padding == reader.line_offset()) {
        result = root.text.Segment { start: segment.start - 1, stop: segment.stop, padding: 0, force_newline: segment.force_newline };
    }
    reader.set_position(sl, ss);
    result
}
