// Port of goldmark parser/atx_heading.go.

/// A HeadingConfig struct is a data structure that holds configuration of the parsers related to headings.
class HeadingConfig {
    auto_heading_id: bool,
    attribute: bool,
}

/// A HeadingOption interface sets options for heading parsers.
interface HeadingOption {
    function set_heading_option(self, p: HeadingConfig) -> void throws never
}

/// Go's `withAutoHeadingID`: an Option and a HeadingOption.
class WithAutoHeadingIDOption {
    implements Option {
        function set_parser_option(self, c: Config) -> void {
            c.auto_heading_id = true;
        }
    }

    implements HeadingOption {
        function set_heading_option(self, p: HeadingConfig) -> void {
            p.auto_heading_id = true;
        }
    }
}

/// WithAutoHeadingID is a functional option that enables custom heading ids and
/// auto generated heading ids.
/// It can be used as a parser Option and a HeadingOption.
function with_auto_heading_id() -> WithAutoHeadingIDOption {
    WithAutoHeadingIDOption {}
}

/// Go's `atxHeadingParser` (embeds HeadingConfig).
class ATXHeadingParser {
    config: HeadingConfig,

    implements BlockParser {
        function trigger(self) -> uint8array? {
            root.util.bytes_of([35])
        }

        function open(self, parent: root.ast.Node, reader: root.text.Reader, pc: Context) -> OpenResult {
            let pl = reader.peek_line();
            let line = pl.line ?? root.util.new_bytes();
            let segment = pl.segment;
            let pos = pc.block_offset();
            if (pos < 0) {
                return OpenResult { node: null, state: NO_CHILDREN() };
            }
            let i = pos;
            while (i < line.length() && line[i] == 35) {
                i += 1;
            }
            let level = i - pos;
            if (i == pos || level > 6) {
                return OpenResult { node: null, state: NO_CHILDREN() };
            }
            if (i == line.length()) { // alone '#' (without a new line character)
                return OpenResult { node: root.ast.new_heading(level, root.ast.HeadingKind.HeadingKindATX), state: NO_CHILDREN() };
            }
            let l = root.util.trim_left_space_length(line.slice(i, line.length()));
            if (l == 0) {
                return OpenResult { node: null, state: NO_CHILDREN() };
            }

            let start = if (i + l < line.length() - 1) { i + l } else { line.length() - 1 };
            let node = root.ast.new_heading(level, root.ast.HeadingKind.HeadingKindATX);
            let hl = root.text.new_segment(
                segment.start + start - segment.padding,
                segment.start + line.length() - segment.padding,
            );
            hl = hl.trim_right_space(reader.source());
            if (hl.len() == 0) {
                reader.advance_to_eol();
                return OpenResult { node: node, state: NO_CHILDREN() };
            }

            if (self.config.attribute) {
                node.append_source(hl);
                parse_last_line_attributes(node, reader, pc);
                hl = node.source()[0];
                node.set_source([]);
            }

            // handle closing sequence of '#' characters
            let hline = hl.bytes(reader.source());
            let stop = hline.length();
            if (stop == 0) { // empty headings like '##[space]'
                stop = 0;
            } else {
                let k = stop - 1;
                while (hline[k] == 35 && k > 0) {
                    k -= 1;
                }
                if (k == 0 && hline[0] == 35) { // empty headings like '### ###'
                    reader.advance_to_eol();
                    return OpenResult { node: node, state: NO_CHILDREN() };
                }
                if (k != stop - 1 && root.util.is_space(hline[k])) {
                    stop = k;
                    stop -= root.util.trim_right_space_length(hline.slice(0, stop));
                }
            }
            hl = hl.with_stop(hl.start + stop);
            node.append_source(hl);
            reader.advance_to_eol();

            OpenResult { node: node, state: NO_CHILDREN() }
        }

        function do_continue(self, node: root.ast.Node, reader: root.text.Reader, pc: Context) -> State {
            CLOSE()
        }

        function close(self, node: root.ast.Node, reader: root.text.Reader, pc: Context) -> void {
            if (self.config.auto_heading_id) {
                let id = node.attribute("id");
                if (id == null) {
                    match (node) {
                        let h: root.ast.Heading => {
                            generate_auto_heading_id(h, reader, pc);
                        }
                        _ => {}
                    }
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

/// NewATXHeadingParser return a new BlockParser that can parse ATX headings.
function new_atx_heading_parser(opts: HeadingOption[] = []) -> BlockParser {
    let p = ATXHeadingParser { config: HeadingConfig { auto_heading_id: false, attribute: false } };
    for (let o in opts) {
        o.set_heading_option(p.config);
    }
    p
}

function generate_auto_heading_id(node: root.ast.Heading, reader: root.text.Reader, pc: Context) -> void {
    let line = root.util.new_bytes();
    let last_index = node.source().length() - 1;
    if (last_index > -1) {
        let last_line = node.source()[last_index];
        line = last_line.bytes(reader.source());
    }
    let heading_id = pc.ids().generate(line, root.ast.kind_heading());
    node.set_attribute("id", root.text.new_multi_line_value_from_string(heading_id.to_string(), root.text.identity_decoder()));
}

function parse_last_line_attributes(node: root.ast.BlockNode, reader: root.text.Reader, pc: Context) -> void {
    let last_index = node.source().length() - 1;
    if (last_index < 0) { // empty headings
        return;
    }
    let last_line = node.source()[last_index];
    let lr = root.text.new_reader(reader.source(), reader.decoder());
    lr.set_position(0, last_line);

    while (true) {
        let c = lr.peek();
        if (c == root.text.EOF() || c == 10) {
            break;
        }
        if (c == 92) {
            lr.advance(1);
            if (root.util.is_punct(lr.peek())) {
                lr.advance(1);
            }
            continue;
        }
        if (c == 123) {
            let saved = lr.position();
            let attrs = parse_attributes(lr);
            if (attrs != null) {
                let nl = lr.peek_line().line;
                let ok = if (nl == null) { true } else { root.util.is_blank(nl) };
                if (ok) {
                    for (let attr in attrs) {
                        node.set_attribute(attr.name, attr.value);
                    }
                    let ll = last_line.with_stop(saved.segment.start);
                    ll = ll.trim_right_space(reader.source());
                    node.source()[last_index] = ll;
                    return;
                }
            }
            lr.set_position(saved.line, saved.segment);
        }
        lr.advance(1);
    }
}
