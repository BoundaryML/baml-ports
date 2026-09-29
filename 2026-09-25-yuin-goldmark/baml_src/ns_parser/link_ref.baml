// Port of goldmark parser/link_ref.go.

class LinkReferenceParagraphTransformerImpl {
    implements ParagraphTransformer {
        function transform(self, node: root.ast.Paragraph, reader: root.text.Reader, pc: Context) -> void {
            let lines = node.source();
            let block = root.text.new_block_reader(reader.source(), lines, reader.decoder());
            let removes: int[][] = [];
            while (true) {
                let r = parse_link_reference_definition(block, pc);
                let ref = r.node;
                if (r.start > -1 && ref != null) {
                    if (r.start == 0) {
                        ref.set_blank_previous_lines(node.has_blank_previous_lines());
                    }
                    ref.set_pos(lines[r.start].start);
                    let np = node.parent();
                    if (np != null) {
                        np.insert_before(node, ref);
                    }
                    let end = r.end;
                    if (r.start == end) {
                        end += 1;
                    }
                    removes.push([r.start, end]);
                    continue;
                }
                break;
            }

            let offset = 0;
            for (let remove in removes) {
                if (lines.length() == 0) {
                    break;
                }
                let s = lines.slice(remove[1] - offset, lines.length());
                lines = lines.slice(0, remove[0] - offset);
                lines = lines.concat(s);
                offset = remove[1];
            }

            if (lines.length() == 0) {
                let np = node.parent();
                if (np != null) {
                    np.remove_child(node);
                }
                return;
            }

            node.set_source(lines);
        }
    }
}

/// LinkReferenceParagraphTransformer is a ParagraphTransformer implementation
/// that parses and extracts link reference from paragraphs.
function link_reference_paragraph_transformer() -> ParagraphTransformer {
    LinkReferenceParagraphTransformerImpl {}
}

/// Result of `parse_link_reference_definition` (Go: `(ast.BlockNode, int, int)`).
class LinkRefResult {
    node: root.ast.LinkReferenceDefinition?,
    start: int,
    end: int,
}

function no_link_ref() -> LinkRefResult {
    LinkRefResult { node: null, start: -1, end: -1 }
}

function parse_link_reference_definition(block: root.text.Reader, pc: Context) -> LinkRefResult {
    block.skip_spaces();
    let line0 = block.peek_line().line;
    if (line0 == null) {
        return no_link_ref();
    }
    let line: uint8array = line0;
    let start_line = block.position().line;
    let iw = root.util.indent_width(line, 0);
    let width = iw.width;
    let pos = iw.pos;
    if (width > 3) {
        return no_link_ref();
    }
    if (width != 0) {
        pos += 1;
    }
    if (line[pos] != 91) {
        return no_link_ref();
    }
    block.advance(pos + 1);
    let label_val = find_closure(block, 91, 93);
    if (label_val == null) {
        return no_link_ref();
    }
    if (root.util.is_blank(label_val.bytes(block.source()))) {
        return no_link_ref();
    }
    if (block.peek() != 58) {
        return no_link_ref();
    }
    block.advance(1);
    block.skip_spaces();
    let destination = parse_link_destination(block);
    if (destination == null) {
        return no_link_ref();
    }
    let nl = block.peek_line().line;
    let is_new_line = if (nl == null) { true } else { root.util.is_blank(nl) };

    let end_line = block.position().line;
    let spaces = block.skip_spaces().count;
    let opener = block.peek();
    if (opener != 34 && opener != 39 && opener != 40) {
        if (!is_new_line) {
            return no_link_ref();
        }
        let ref = root.ast.new_link_reference_definition(label_val, destination);
        pc.add_link_definition(new_link_definition_from_node(ref, block.source()));
        return LinkRefResult { node: ref, start: start_line, end: end_line + 1 };
    }
    if (spaces == 0) {
        return no_link_ref();
    }
    block.advance(1);
    let closer = opener;
    if (opener == 40) {
        closer = 41;
    }
    let saved = block.position();
    let title_val = find_closure(block, opener, closer);
    if (title_val == null) {
        if (!is_new_line) {
            return no_link_ref();
        }
        let ref = root.ast.new_link_reference_definition(label_val, destination);
        pc.add_link_definition(new_link_definition_from_node(ref, block.source()));
        block.advance_line();
        return LinkRefResult { node: ref, start: start_line, end: end_line + 1 };
    }

    let tl = block.peek_line().line;
    let trailing = if (tl == null) { false } else { !root.util.is_blank(tl) };
    if (trailing) {
        if (!is_new_line) {
            return no_link_ref();
        }
        block.set_position(saved.line, saved.segment);
        let ref = root.ast.new_link_reference_definition(label_val, destination, opts = [root.ast.with_link_title(title_val)]);
        pc.add_link_definition(new_link_definition_from_node(ref, block.source()));
        return LinkRefResult { node: ref, start: start_line, end: end_line + 1 };
    }

    let end_line2 = block.position().line;
    let ref = root.ast.new_link_reference_definition(label_val, destination, opts = [root.ast.with_link_title(title_val)]);
    pc.add_link_definition(new_link_definition_from_node(ref, block.source()));
    LinkRefResult { node: ref, start: start_line, end: end_line2 + 1 }
}
