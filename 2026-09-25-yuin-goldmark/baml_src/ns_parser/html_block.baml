// Port of goldmark parser/html_block.go.

/// Go: `allowedBlockTags` (a package-level map; BAML has no package-level
/// values, so the set is a `match`).
function is_allowed_block_tag(tag: string) -> bool {
    match (tag) {
        "address" => true,
        "article" => true,
        "aside" => true,
        "base" => true,
        "basefont" => true,
        "blockquote" => true,
        "body" => true,
        "caption" => true,
        "center" => true,
        "col" => true,
        "colgroup" => true,
        "dd" => true,
        "details" => true,
        "dialog" => true,
        "dir" => true,
        "div" => true,
        "dl" => true,
        "dt" => true,
        "fieldset" => true,
        "figcaption" => true,
        "figure" => true,
        "footer" => true,
        "form" => true,
        "frame" => true,
        "frameset" => true,
        "h1" => true,
        "h2" => true,
        "h3" => true,
        "h4" => true,
        "h5" => true,
        "h6" => true,
        "head" => true,
        "header" => true,
        "hr" => true,
        "html" => true,
        "iframe" => true,
        "legend" => true,
        "li" => true,
        "link" => true,
        "main" => true,
        "menu" => true,
        "menuitem" => true,
        "meta" => true,
        "nav" => true,
        "noframes" => true,
        "ol" => true,
        "optgroup" => true,
        "option" => true,
        "p" => true,
        "param" => true,
        "search" => true,
        "section" => true,
        "summary" => true,
        "table" => true,
        "tbody" => true,
        "td" => true,
        "tfoot" => true,
        "th" => true,
        "thead" => true,
        "title" => true,
        "tr" => true,
        "track" => true,
        "ul" => true,
        _ => false,
    }
}

function html_block_type2_close() -> uint8array {
    "-->".to_utf8()
}

function html_block_type3_close() -> uint8array {
    "?>".to_utf8()
}

function html_block_type4_close() -> uint8array {
    ">".to_utf8()
}

function html_block_type5_close() -> uint8array {
    "]]>".to_utf8()
}

/// Go returns `(int, bool)`: the count and whether it is at most 3.
function count_leading_spaces(line: uint8array) -> int {
    let i = 0;
    while (i < line.length() && line[i] == 32) {
        i += 1;
    }
    i
}

function scan_html_block_open1(line: uint8array) -> bool {
    let i = count_leading_spaces(line);
    if (i > 3 || i >= line.length() || line[i] != 60) {
        return false;
    }
    let rest = i + 1;
    let n = 0;
    if (has_prefix_fold_at(line, rest, "textarea")) {
        n = 8;
    } else if (has_prefix_fold_at(line, rest, "script")) {
        n = 6;
    } else if (has_prefix_fold_at(line, rest, "style")) {
        n = 5;
    } else if (has_prefix_fold_at(line, rest, "pre")) {
        n = 3;
    } else {
        return false;
    }
    rest += n;
    if (rest >= line.length()) {
        return true;
    }
    let c = line[rest];
    root.util.is_space(c) || c == 62 || (c == 47 && line.length() - rest > 1 && line[rest + 1] == 62)
}

function scan_html_block_close1(line: uint8array) -> bool {
    contains_fold(line, "</script>") || contains_fold(line, "</pre>") || contains_fold(line, "</style>") || contains_fold(line, "</textarea>")
}

function scan_html_block_open2(line: uint8array) -> bool {
    let i = count_leading_spaces(line);
    i <= 3 && root.util.has_prefix_at(line, i, "<!--")
}

function scan_html_block_open3(line: uint8array) -> bool {
    let i = count_leading_spaces(line);
    i <= 3 && root.util.has_prefix_at(line, i, "<?")
}

function scan_html_block_open4(line: uint8array) -> bool {
    let i = count_leading_spaces(line);
    if (i > 3 || !root.util.has_prefix_at(line, i, "<!")) {
        return false;
    }
    i += 2;
    i < line.length() && line[i] >= 65 && line[i] <= 90
}

function scan_html_block_open5(line: uint8array) -> bool {
    let i = count_leading_spaces(line);
    i <= 3 && root.util.has_prefix_at(line, i, "<![CDATA[")
}

/// Go returns `(tagName []byte, ok bool)`; null means not ok.
function scan_html_block_open6(line: uint8array) -> uint8array? {
    let i = count_leading_spaces(line);
    if (i > 3 || i >= line.length() || line[i] != 60) {
        return null;
    }
    i += 1;
    if (i < line.length() && line[i] == 47) {
        i += 1;
        while (i < line.length() && line[i] == 32) {
            i += 1;
        }
    }
    let start = i;
    let sr = scan_tag_name_bytes(line, i);
    if (!sr.ok) {
        return null;
    }
    let end = sr.end;
    if (end < line.length()) {
        let c = line[end];
        if (c != 32 && c != 62 && (c != 47 || end + 1 >= line.length() || line[end + 1] != 62)) {
            return null;
        }
    }
    line.slice(start, end)
}

/// Result of `scan_html_block_open7` (Go: `(tagName, isCloseTag, hasAttr, ok)`).
class HTMLBlockOpen7 {
    tag_name: uint8array,
    is_close_tag: bool,
    has_attr: bool,
    ok: bool,
}

function scan_html_block_open7(line: uint8array) -> HTMLBlockOpen7 {
    let fail = HTMLBlockOpen7 { tag_name: root.util.new_bytes(), is_close_tag: false, has_attr: false, ok: false };
    let i = count_leading_spaces(line);
    if (i > 3 || i >= line.length() || line[i] != 60) {
        return fail;
    }
    i += 1;
    let is_close_tag = false;
    if (i < line.length() && line[i] == 47) {
        is_close_tag = true;
        i += 1;
        while (i < line.length() && line[i] == 32) {
            i += 1;
        }
    }
    let start = i;
    let sr = scan_tag_name_bytes(line, i);
    if (!sr.ok) {
        return fail;
    }
    let tag_name = line.slice(start, sr.end);
    let ar = scan_html_attributes_bytes(line, sr.end);
    let end = ar.end;
    let has_attr = ar.ok;
    while (end < line.length() && line[end] == 32) {
        end += 1;
    }
    if (end >= line.length()) {
        return HTMLBlockOpen7 { tag_name: tag_name, is_close_tag: is_close_tag, has_attr: has_attr, ok: false };
    }
    if (line[end] == 47) {
        if (end + 1 >= line.length() || line[end + 1] != 62) {
            return HTMLBlockOpen7 { tag_name: tag_name, is_close_tag: is_close_tag, has_attr: has_attr, ok: false };
        }
        end += 2;
    } else if (line[end] == 62) {
        end += 1;
    } else {
        return HTMLBlockOpen7 { tag_name: tag_name, is_close_tag: is_close_tag, has_attr: has_attr, ok: false };
    }
    while (end < line.length() && line[end] == 32) {
        end += 1;
    }
    if (end < line.length() && line[end] == 13 && end + 1 < line.length() && line[end + 1] == 10) {
        end += 2;
    } else if (end < line.length() && line[end] == 10) {
        end += 1;
    }
    HTMLBlockOpen7 { tag_name: tag_name, is_close_tag: is_close_tag, has_attr: has_attr, ok: end == line.length() }
}

class HTMLBlockParser {
    implements BlockParser {
        function trigger(self) -> uint8array? {
            root.util.bytes_of([60])
        }

        function open(self, parent: root.ast.Node, reader: root.text.Reader, pc: Context) -> OpenResult {
            let node: root.ast.HTMLBlock? = null;
            let pl = reader.peek_line();
            let line = pl.line ?? root.util.new_bytes();
            let segment = pl.segment;
            let last = pc.last_opened_block().node;

            if (scan_html_block_open1(line)) {
                node = root.ast.new_html_block(root.ast.HTMLBlockKind.HTMLBlockKind1);
            } else if (scan_html_block_open2(line)) {
                node = root.ast.new_html_block(root.ast.HTMLBlockKind.HTMLBlockKind2);
            } else if (scan_html_block_open3(line)) {
                node = root.ast.new_html_block(root.ast.HTMLBlockKind.HTMLBlockKind3);
            } else if (scan_html_block_open4(line)) {
                node = root.ast.new_html_block(root.ast.HTMLBlockKind.HTMLBlockKind4);
            } else if (scan_html_block_open5(line)) {
                node = root.ast.new_html_block(root.ast.HTMLBlockKind.HTMLBlockKind5);
            } else {
                let o7 = scan_html_block_open7(line);
                if (o7.ok) {
                    let tag_name = o7.tag_name.to_string().to_lower_case();
                    if (is_allowed_block_tag(tag_name)) {
                        node = root.ast.new_html_block(root.ast.HTMLBlockKind.HTMLBlockKind6);
                    } else if (tag_name != "script" && tag_name != "style" && tag_name != "pre" && !root.ast.is_paragraph(last) && (!o7.is_close_tag || !o7.has_attr)) { // type 7 can not interrupt paragraph
                        node = root.ast.new_html_block(root.ast.HTMLBlockKind.HTMLBlockKind7);
                    }
                }
            }
            if (node == null) {
                let tag_name = scan_html_block_open6(line);
                if (tag_name != null) {
                    if (is_allowed_block_tag(tag_name.to_string().to_lower_case())) {
                        node = root.ast.new_html_block(root.ast.HTMLBlockKind.HTMLBlockKind6);
                    }
                }
            }
            if (node != null) {
                reader.advance_to_eol();
                node.value.append_segment(segment);
                return OpenResult { node: node, state: NO_CHILDREN() };
            }
            OpenResult { node: null, state: NO_CHILDREN() }
        }

        function do_continue(self, node: root.ast.Node, reader: root.text.Reader, pc: Context) -> State {
            let html_block = match (node) {
                let h: root.ast.HTMLBlock => h,
                _ => {
                    return CLOSE();
                }
            };
            let pl = reader.peek_line();
            let line = pl.line ?? root.util.new_bytes();
            let segment = pl.segment;
            let closure_pattern: uint8array? = null;

            match (html_block.html_block_kind) {
                root.ast.HTMLBlockKind.HTMLBlockKind1 => {
                    if (html_block.value.segments().length() == 1) {
                        let first_line = html_block.value.segments()[0];
                        if (scan_html_block_close1(first_line.bytes(reader.source()))) {
                            return CLOSE();
                        }
                    }
                    if (scan_html_block_close1(line)) {
                        html_block.value.append_segment(segment);
                        reader.advance_to_eol();
                        return CLOSE();
                    }
                }
                root.ast.HTMLBlockKind.HTMLBlockKind2 => {
                    closure_pattern = html_block_type2_close();
                }
                root.ast.HTMLBlockKind.HTMLBlockKind3 => {
                    closure_pattern = html_block_type3_close();
                }
                root.ast.HTMLBlockKind.HTMLBlockKind4 => {
                    closure_pattern = html_block_type4_close();
                }
                root.ast.HTMLBlockKind.HTMLBlockKind5 => {
                    closure_pattern = html_block_type5_close();
                }
                _ => {
                    // HTMLBlockKind6, HTMLBlockKind7
                    if (root.util.is_blank(line)) {
                        return CLOSE();
                    }
                }
            }
            // Go uses `fallthrough` from kinds 2-4 into kind 5's body.
            if (closure_pattern != null) {
                if (html_block.value.segments().length() == 1) {
                    let first_line = html_block.value.segments()[0];
                    if (root.util.bytes_contains(first_line.bytes(reader.source()), closure_pattern)) {
                        return CLOSE();
                    }
                }
                if (root.util.bytes_contains(line, closure_pattern)) {
                    html_block.value.append_segment(segment);
                    reader.advance_to_eol();
                    return CLOSE();
                }
            }
            html_block.value.append_segment(segment);
            reader.advance_to_eol();
            CONTINUE() | NO_CHILDREN()
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

/// NewHTMLBlockParser return a new BlockParser that can parse html
/// blocks.
function new_html_block_parser() -> BlockParser {
    HTMLBlockParser {}
}
