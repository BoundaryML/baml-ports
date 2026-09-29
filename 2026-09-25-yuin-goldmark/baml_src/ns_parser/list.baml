// Port of goldmark parser/list.go.

// listItemType
function NOT_LIST() -> int {
    0
}

function BULLET_LIST() -> int {
    1
}

function ORDERED_LIST() -> int {
    2
}

function skip_list_parser_key() -> ContextKey {
    "parser.skipListParser"
}

function empty_list_item_with_blank_lines_key() -> ContextKey {
    "parser.emptyListItemWithBlankLines"
}

function list_item_flag_value() -> unknown {
    true
}

function last_offset(node: root.ast.Node) -> int {
    let last_child = node.last_child();
    if (last_child != null) {
        match (last_child) {
            let li: root.ast.ListItem => {
                return li.offset();
            }
            _ => {}
        }
    }
    0
}

/// Result of `parse_list_item` (Go: `([6]int, listItemType)`).
class ListItemMatch {
    m: int[],
    typ: int,
}

/// Equivalent to `^(([ ]*)([\-\*\+]))(\s+.*)?\n?$`.FindSubmatchIndex or
/// `^(([ ]*)(\d{1,9}[\.\)]))(\s+.*)?\n?$`.FindSubmatchIndex.
function parse_list_item(line: uint8array) -> ListItemMatch {
    let i = 0;
    let l = line.length();
    let ret = [0, 0, 0, 0, 0, 0];
    while (i < l && line[i] == 32) {
        // (Go checks for '\t' inside this loop, which can never be true.)
        i += 1;
    }
    if (i > 3) {
        return ListItemMatch { m: ret, typ: NOT_LIST() };
    }
    ret[0] = 0;
    ret[1] = i;
    ret[2] = i;
    let typ = NOT_LIST();
    if (i < l && (line[i] == 45 || line[i] == 42 || line[i] == 43)) {
        i += 1;
        ret[3] = i;
        typ = BULLET_LIST();
    } else if (i < l) {
        while (i < l && root.util.is_numeric(line[i])) {
            i += 1;
        }
        ret[3] = i;
        if (ret[3] == ret[2] || ret[3] - ret[2] > 9) {
            return ListItemMatch { m: ret, typ: NOT_LIST() };
        }
        if (i < l && (line[i] == 46 || line[i] == 41)) {
            i += 1;
            ret[3] = i;
        } else {
            return ListItemMatch { m: ret, typ: NOT_LIST() };
        }
        typ = ORDERED_LIST();
    } else {
        return ListItemMatch { m: ret, typ: NOT_LIST() };
    }
    if (i < l && line[i] != 10) {
        let iw = root.util.indent_width(line.slice(i, l), 0);
        if (iw.width == 0) {
            return ListItemMatch { m: ret, typ: NOT_LIST() };
        }
    }
    if (i >= l) {
        ret[4] = -1;
        ret[5] = -1;
        return ListItemMatch { m: ret, typ: typ };
    }
    ret[4] = i;
    ret[5] = l;
    if (line[ret[5] - 1] == 10 && line[i] != 10) {
        ret[5] = ret[5] - 1;
    }
    ListItemMatch { m: ret, typ: typ }
}

function calc_list_offset(line: uint8array, m: int[]) -> int {
    let offset = 0;
    if (m[4] < 0 || root.util.is_blank(line.slice(m[4], line.length()))) { // list item starts with a blank line
        offset = 1;
    } else {
        offset = root.util.indent_width(line.slice(m[4], line.length()), m[4]).width;
        if (offset > 4) { // offseted codeblock
            offset = 1;
        }
    }
    offset
}

/// Go: `strconv.Atoi` for a validated run of at most 9 ASCII digits.
function atoi_digits(b: uint8array) -> int {
    let v = 0;
    for (let c in b.to_array()) {
        v = v * 10 + (c - 48);
    }
    v
}

class ListParser {
    implements BlockParser {
        function trigger(self) -> uint8array? {
            root.util.bytes_of([45, 43, 42, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57])
        }

        function open(self, parent: root.ast.Node, reader: root.text.Reader, pc: Context) -> OpenResult {
            let last = pc.last_opened_block().node;
            let last_is_list = if (last == null) { false } else {
                match (last) {
                    let x: root.ast.List => true,
                    _ => false,
                }
            };
            if (last_is_list || pc.get(skip_list_parser_key()) != null) {
                pc.set(skip_list_parser_key(), null);
                return OpenResult { node: null, state: NO_CHILDREN() };
            }
            let line = reader.peek_line().line ?? root.util.new_bytes();
            let lm = parse_list_item(line);
            let m = lm.m;
            let typ = lm.typ;
            if (typ == NOT_LIST()) {
                return OpenResult { node: null, state: NO_CHILDREN() };
            }
            let start = -1;
            if (typ == ORDERED_LIST()) {
                let number = line.slice(m[2], m[3] - 1);
                start = atoi_digits(number);
            }

            if (root.ast.is_paragraph(last)) {
                let lp = if (last == null) { null } else { last.parent() };
                if (root.ast.same_node(lp, parent)) {
                    // we allow only lists starting with 1 to interrupt paragraphs.
                    if (typ == ORDERED_LIST() && start != 1) {
                        return OpenResult { node: null, state: NO_CHILDREN() };
                    }
                    //an empty list item cannot interrupt a paragraph:
                    if (m[4] < 0 || root.util.is_blank(line.slice(m[4], m[5]))) {
                        return OpenResult { node: null, state: NO_CHILDREN() };
                    }
                }
            }

            let marker = line[m[3] - 1];
            let node = root.ast.new_list(marker);
            if (start > -1) {
                node.start = start;
            }
            pc.set(empty_list_item_with_blank_lines_key(), null);
            OpenResult { node: node, state: HAS_CHILDREN() }
        }

        function do_continue(self, node: root.ast.Node, reader: root.text.Reader, pc: Context) -> State {
            let list = match (node) {
                let l: root.ast.List => l,
                _ => {
                    return CLOSE();
                }
            };
            let line = reader.peek_line().line ?? root.util.new_bytes();
            let last_child = node.last_child();
            let last_child_count = if (last_child == null) { 0 } else { last_child.child_count() };
            if (root.util.is_blank(line)) {
                if (last_child_count == 0) {
                    pc.set(empty_list_item_with_blank_lines_key(), list_item_flag_value());
                }
                return CONTINUE() | HAS_CHILDREN();
            }

            // "offset" means a width that bar indicates.
            //    -  aaaaaaaa
            // |----|
            //
            // If the indent is less than the last offset like
            // - a
            //  - b          <--- current line
            // it maybe a new child of the list.
            //
            // Empty list items can have multiple blanklines
            //
            // -             <--- 1st item is an empty thus "offset" is unknown
            //
            //
            //   -           <--- current line
            //
            // -> 1 list with 2 blank items
            //
            // So if the last item is an empty, it maybe a new child of the list.
            //
            let offset = last_offset(node);
            let last_is_empty = last_child_count == 0;
            let indent = root.util.indent_width(line, reader.line_offset()).width;

            if (indent < offset || last_is_empty) {
                if (indent < 4) {
                    let lm = parse_list_item(line);
                    let m = lm.m;
                    if (lm.typ != NOT_LIST() && m[1] - offset < 4) {
                        let marker = line[m[3] - 1];
                        if (!list.can_continue(marker, lm.typ == ORDERED_LIST())) {
                            return CLOSE();
                        }
                        // Thematic Breaks take precedence over lists
                        let rest = line.slice(m[3] - 1, line.length());
                        if (is_thematic_break(rest, 0)) {
                            let is_heading = false;
                            let last = pc.last_opened_block().node;
                            if (root.ast.is_paragraph(last)) {
                                let c = matches_setext_heading_bar(rest);
                                if (c != null) {
                                    if (c == 45) {
                                        is_heading = true;
                                    }
                                }
                            }
                            if (!is_heading) {
                                return CLOSE();
                            }
                        }
                        return CONTINUE() | HAS_CHILDREN();
                    }
                }
                if (!last_is_empty) {
                    return CLOSE();
                }
            }

            if (last_is_empty && indent < offset) {
                return CLOSE();
            }

            // Non empty items can not exist next to an empty list item
            // with blank lines. So we need to close the current list
            //
            // -
            //
            //   foo
            //
            // -> 1 list with 1 blank items and 1 paragraph
            if (pc.get(empty_list_item_with_blank_lines_key()) != null) {
                return CLOSE();
            }
            CONTINUE() | HAS_CHILDREN()
        }

        function close(self, node: root.ast.Node, reader: root.text.Reader, pc: Context) -> void {
            let list = match (node) {
                let l: root.ast.List => l,
                _ => {
                    return;
                }
            };

            let c = node.first_child();
            while (c != null && list.is_tight) {
                let fc = c.first_child();
                if (fc != null && !root.ast.same_node(fc, c.last_child())) {
                    let c1 = fc.next_sibling();
                    while (c1 != null) {
                        if (has_blank_previous_lines(c1)) {
                            list.is_tight = false;
                            break;
                        }
                        c1 = c1.next_sibling();
                    }
                }
                if (!root.ast.same_node(c, node.first_child())) {
                    if (has_blank_previous_lines(c)) {
                        list.is_tight = false;
                    }
                }
                c = c.next_sibling();
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

/// Go: `n.(ast.BlockNode).HasBlankPreviousLines()`.
function has_blank_previous_lines(n: root.ast.Node) -> bool {
    match (n) {
        let b: root.ast.BlockNode => b.has_blank_previous_lines(),
        _ => false,
    }
}

/// NewListParser returns a new BlockParser that
/// parses lists.
/// This parser must take precedence over the ListItemParser.
function new_list_parser() -> BlockParser {
    ListParser {}
}
