// Port of goldmark parser/setext_headings.go.

function temporary_paragraph_key() -> ContextKey {
    "parser.temporaryParagraph"
}

/// Go returns `(byte, bool)`; here null means "not a setext heading bar".
function matches_setext_heading_bar(line: uint8array) -> int? {
    let start = 0;
    let end = line.length();
    let space = root.util.trim_left_length(line, root.util.bytes_of([32]));
    if (space > 3) {
        return null;
    }
    start += space;
    let level1 = root.util.trim_left_length(line.slice(start, end), root.util.bytes_of([61]));
    let c = 61;
    let level2 = 0;
    if (level1 == 0) {
        level2 = root.util.trim_left_length(line.slice(start, end), root.util.bytes_of([45]));
        c = 45;
    }
    if (root.util.is_space(line[end - 1])) {
        end -= root.util.trim_right_space_length(line.slice(start, end));
    }
    if ((level1 <= 0 || start + level1 != end) && (level2 <= 0 || start + level2 != end)) {
        return null;
    }
    c
}

/// Go's `setextHeadingParser` (embeds HeadingConfig).
class SetextHeadingParser {
    config: HeadingConfig,

    implements BlockParser {
        function trigger(self) -> uint8array? {
            root.util.bytes_of([45, 61])
        }

        function open(self, parent: root.ast.Node, reader: root.text.Reader, pc: Context) -> OpenResult {
            let last = pc.last_opened_block().node;
            if (last == null) {
                return OpenResult { node: null, state: NO_CHILDREN() };
            }
            let is_para = match (last) {
                let p: root.ast.Paragraph => root.ast.same_node(p.parent(), parent),
                _ => false,
            };
            if (!is_para) {
                return OpenResult { node: null, state: NO_CHILDREN() };
            }
            let pl = reader.peek_line();
            let line = pl.line ?? root.util.new_bytes();
            let segment = pl.segment;
            let c = matches_setext_heading_bar(line);
            if (c == null) {
                return OpenResult { node: null, state: NO_CHILDREN() };
            }
            let level = 1;
            if (c == 45) {
                level = 2;
            }
            let node = root.ast.new_heading(level, root.ast.HeadingKind.HeadingKindSetext);
            node.append_source(segment);
            pc.set(temporary_paragraph_key(), last);
            OpenResult { node: node, state: NO_CHILDREN() | REQUIRE_PARAGRAPH() }
        }

        function do_continue(self, node: root.ast.Node, reader: root.text.Reader, pc: Context) -> State {
            CLOSE()
        }

        function close(self, node: root.ast.Node, reader: root.text.Reader, pc: Context) -> void {
            let heading = match (node) {
                let h: root.ast.Heading => h,
                _ => {
                    return;
                }
            };
            let segment = heading.source()[0];
            heading.set_source([]);
            let tmp_any = pc.get(temporary_paragraph_key());
            pc.set(temporary_paragraph_key(), null);
            let tmp = match (tmp_any) {
                let p: root.ast.Paragraph => p,
                _ => {
                    return;
                }
            };
            if (tmp.source().length() == 0) {
                let next = heading.next_sibling();
                segment = segment.trim_left_space(reader.source());
                let hp = heading.parent();
                let next_para: root.ast.Paragraph? = null;
                if (next != null) {
                    match (next) {
                        let np: root.ast.Paragraph => {
                            next_para = np;
                        }
                        _ => {}
                    }
                }
                if (next_para == null) {
                    let para = root.ast.new_paragraph();
                    para.append_source(segment);
                    if (hp != null) {
                        hp.insert_after(heading, para);
                    }
                } else {
                    let segs: root.text.Segment[] = [segment];
                    next_para.set_source(segs.concat(next_para.source()));
                }
                if (hp != null) {
                    hp.remove_child(heading);
                }
            } else {
                heading.set_pos(tmp.source()[0].start);
                heading.set_source(tmp.source());
                heading.set_blank_previous_lines(tmp.has_blank_previous_lines());
                let tp = tmp.parent();
                if (tp != null) {
                    tp.remove_child(tmp);
                }
            }

            if (self.config.attribute) {
                parse_last_line_attributes(heading, reader, pc);
            }

            if (self.config.auto_heading_id) {
                let id = node.attribute("id");
                if (id == null) {
                    generate_auto_heading_id(heading, reader, pc);
                } else {
                    pc.ids().put(id.bytes(reader.source()));
                }
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

/// NewSetextHeadingParser return a new BlockParser that can parse Setext headings.
function new_setext_heading_parser(opts: HeadingOption[] = []) -> BlockParser {
    let p = SetextHeadingParser { config: HeadingConfig { auto_heading_id: false, attribute: false } };
    for (let o in opts) {
        o.set_heading_option(p.config);
    }
    p
}
