// Port of goldmark parser/raw_html.go.

function open_processing_instruction() -> uint8array {
    "<?".to_utf8()
}

function close_processing_instruction() -> uint8array {
    "?>".to_utf8()
}

function open_cdata() -> uint8array {
    "<![CDATA[".to_utf8()
}

function close_cdata() -> uint8array {
    "]]>".to_utf8()
}

function close_decl() -> uint8array {
    ">".to_utf8()
}

function empty_comment1() -> uint8array {
    "<!-->".to_utf8()
}

function empty_comment2() -> uint8array {
    "<!--->".to_utf8()
}

function open_comment() -> uint8array {
    "<!--".to_utf8()
}

function close_comment() -> uint8array {
    "-->".to_utf8()
}

type TagScanner = (r: root.text.Reader) -> bool throws never

function scan_open_tag(r: root.text.Reader) -> bool {
    let saved = r.position();
    if (r.peek() != 60) {
        return false;
    }
    r.advance(1);
    if (!scan_tag_name_reader(r)) {
        r.set_position(saved.line, saved.segment);
        return false;
    }
    scan_html_attributes_reader(r);
    skip_attr_separators_reader(r);
    if (r.peek() == 47) {
        r.advance(1);
    }
    if (r.peek() != 62) {
        r.set_position(saved.line, saved.segment);
        return false;
    }
    r.advance(1);
    true
}

function scan_close_tag(r: root.text.Reader) -> bool {
    let saved = r.position();
    if (r.peek() != 60) {
        return false;
    }
    r.advance(1);
    if (r.peek() != 47) {
        r.set_position(saved.line, saved.segment);
        return false;
    }
    r.advance(1);
    if (!scan_tag_name_reader(r)) {
        r.set_position(saved.line, saved.segment);
        return false;
    }
    skip_attr_separators_reader(r);
    if (r.peek() != 62) {
        r.set_position(saved.line, saved.segment);
        return false;
    }
    r.advance(1);
    true
}

class RawHTMLParser {
    function parse_comment(self, block: root.text.Reader, pc: Context) -> root.ast.Node? {
        let saved = block.position();
        let pl = block.peek_line();
        let line = pl.line ?? root.util.new_bytes();
        let segment = pl.segment;
        if (root.util.has_prefix(line, empty_comment1())) {
            let stop = segment.start + empty_comment1().length();
            block.advance(empty_comment1().length());
            return root.ast.new_raw_html(root.text.new_multi_line_value_from_index(root.text.new_index(segment.start, stop), root.text.identity_decoder()));
        }
        if (root.util.has_prefix(line, empty_comment2())) {
            let stop = segment.start + empty_comment2().length();
            block.advance(empty_comment2().length());
            return root.ast.new_raw_html(root.text.new_multi_line_value_from_index(root.text.new_index(segment.start, stop), root.text.identity_decoder()));
        }
        let offset = open_comment().length();
        let rest = line.slice(offset, line.length());
        let indices: root.text.Index[] = [];
        while (true) {
            let index = root.util.bytes_index(rest, close_comment());
            if (index > -1) {
                let stop = segment.start + offset + index + close_comment().length();
                indices.push(root.text.new_index(segment.start, stop));
                block.advance(offset + index + close_comment().length());
                return root.ast.new_raw_html(root.text.new_multi_line_value_from_indices(indices, root.text.identity_decoder()));
            }
            offset = 0;
            indices.push(root.text.new_index(segment.start, segment.stop));
            block.advance_line();
            let npl = block.peek_line();
            let nline = npl.line;
            segment = npl.segment;
            if (nline == null) {
                break;
            }
            rest = nline;
        }
        block.set_position(saved.line, saved.segment);
        null
    }

    function parse_until(self, block: root.text.Reader, closer: uint8array, pc: Context) -> root.ast.Node? {
        let saved = block.position();
        let indices: root.text.Index[] = [];
        while (true) {
            let pl = block.peek_line();
            let line = pl.line;
            let segment = pl.segment;
            if (line == null) {
                break;
            }
            let index = root.util.bytes_index(line, closer);
            if (index > -1) {
                let stop = segment.start + index + closer.length();
                indices.push(root.text.new_index(segment.start, stop));
                block.advance(index + closer.length());
                return root.ast.new_raw_html(root.text.new_multi_line_value_from_indices(indices, root.text.identity_decoder()));
            }
            indices.push(root.text.new_index(segment.start, segment.stop));
            block.advance_line();
        }
        block.set_position(saved.line, saved.segment);
        null
    }

    function parse_tag(self, scan: TagScanner, block: root.text.Reader, pc: Context) -> root.ast.Node? {
        let s = block.position();
        let sline = s.line;
        let ssegment = s.segment;
        if (scan(block)) {
            let e = block.position();
            let eline = e.line;
            let esegment = e.segment;
            block.set_position(sline, ssegment);
            let indices: root.text.Index[] = [];
            while (true) {
                let pl = block.peek_line();
                let line = pl.line;
                let segment = pl.segment;
                if (line == null) {
                    break;
                }
                let l = block.position().line;
                let start = segment.start;
                if (l == sline) {
                    start = ssegment.start;
                }
                let end = segment.stop;
                if (l == eline) {
                    end = esegment.start;
                }
                indices.push(root.text.new_index(start, end));
                if (l == eline) {
                    block.advance(end - start);
                    break;
                }
                block.advance_line();
            }
            return root.ast.new_raw_html(root.text.new_multi_line_value_from_indices(indices, root.text.identity_decoder()));
        }
        null
    }

    implements InlineParser {
        function trigger(self) -> uint8array {
            root.util.bytes_of([60])
        }

        function parse(self, parent: root.ast.Node, block: root.text.Reader, pc: Context) -> root.ast.Node? {
            let line = block.peek_line().line ?? root.util.new_bytes();
            if (line.length() > 1 && root.util.is_alpha_numeric(line[1])) {
                return self.parse_tag(scan_open_tag, block, pc);
            }
            if (line.length() > 2 && line[1] == 47 && root.util.is_alpha_numeric(line[2])) {
                return self.parse_tag(scan_close_tag, block, pc);
            }
            if (root.util.has_prefix(line, open_comment())) {
                return self.parse_comment(block, pc);
            }
            if (root.util.has_prefix(line, open_processing_instruction())) {
                return self.parse_until(block, close_processing_instruction(), pc);
            }
            if (line.length() > 2 && line[1] == 33 && line[2] >= 65 && line[2] <= 90) {
                return self.parse_until(block, close_decl(), pc);
            }
            if (root.util.has_prefix(line, open_cdata())) {
                return self.parse_until(block, close_cdata(), pc);
            }
            null
        }
    }
}

/// NewRawHTMLParser return a new InlineParser that can parse
/// inline htmls.
function new_raw_html_parser() -> InlineParser {
    RawHTMLParser {}
}
