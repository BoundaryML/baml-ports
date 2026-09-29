// Port of goldmark parser/auto_link.go.

class AutoLinkParser {
    implements InlineParser {
        function trigger(self) -> uint8array {
            root.util.bytes_of([60])
        }

        function parse(self, parent: root.ast.Node, block: root.text.Reader, pc: Context) -> root.ast.Node? {
            let pl = block.peek_line();
            let line = pl.line ?? root.util.new_bytes();
            let segment = pl.segment;
            // Go passes the subslice `line[1:]` (O(1)); BAML slices copy, so
            // the scanners take an offset instead.
            let stop = find_email_index_at(line, 1);
            let is_email = true;
            if (stop < 0) {
                stop = find_url_index_at(line, 1);
                is_email = false;
            }
            if (stop < 0) {
                return null;
            }
            stop += 1;
            if (stop >= line.length() || line[stop] != 62) {
                return null;
            }
            let text_val = root.text.new_single_line_value_from_index(root.text.new_index(segment.start, segment.start + stop + 1), root.text.identity_decoder());
            let label_val = root.text.new_single_line_value_from_index(root.text.new_index(segment.start + 1, segment.start + stop), root.text.identity_decoder());
            block.advance(stop + 1);
            let dest = if (is_email) {
                root.text.new_single_line_value_from_string("mailto:" + line.slice(1, stop).to_string(), root.text.identity_decoder())
            } else {
                root.text.new_single_line_value_from_index(root.text.new_index(segment.start + 1, segment.start + stop), root.text.identity_decoder())
            };
            root.ast.new_auto_link(dest, label_val, opts = [root.ast.with_auto_link_text(text_val)])
        }
    }
}

/// NewAutoLinkParser returns a new InlineParser that parses autolinks
/// surrounded by '<' and '>' .
function new_auto_link_parser() -> InlineParser {
    AutoLinkParser {}
}

/// findURLIndex returns a stop index value if the given bytes seem an URL.
/// This function is equivalent to [A-Za-z][A-Za-z0-9.+-]{1,31}:[^<>\x00-\x20]* .
function find_url_index(b: uint8array) -> int {
    find_url_index_at(b, 0)
}

/// `find_url_index(b[at:])` without copying; the result is relative to `at`.
function find_url_index_at(b: uint8array, at: int) -> int {
    let n = b.length() - at;
    let i = 0;
    if (n <= 0 || (url_table(b[at + i]) & 7) != 7) {
        return -1;
    }
    i += 1;
    while (i < n) {
        let c = b[at + i];
        if ((url_table(c) & 4) != 4) {
            break;
        }
        i += 1;
    }
    if (i == 1 || i > 33 || i >= n) {
        return -1;
    }
    if (b[at + i] != 58) {
        return -1;
    }
    i += 1;
    while (i < n) {
        let c = b[at + i];
        if ((url_table(c) & 1) != 1) {
            break;
        }
        i += 1;
    }
    i
}

/// Go: `scanDomainLabel(b[at:])` without copying.
function scan_domain_label(b: uint8array, at: int) -> int {
    let n = b.length() - at;
    if (n <= 0 || !root.util.is_alpha_numeric(b[at])) {
        return 0;
    }
    let limit = if (n < 63) { n } else { 63 }; // 1 + 61 + 1
    let i = 1;
    while (i < limit && (root.util.is_alpha_numeric(b[at + i]) || b[at + i] == 45)) {
        i += 1;
    }
    while (i > 1 && b[at + i - 1] == 45) {
        i -= 1;
    }
    i
}

/// Go: `scanEmailDomain(b[at:])` without copying.
function scan_email_domain(b: uint8array, at: int) -> int {
    let n = scan_domain_label(b, at);
    if (n == 0) {
        return 0;
    }
    while (at + n < b.length() && b[at + n] == 46) {
        let m = scan_domain_label(b, at + n + 1);
        if (m == 0) {
            break;
        }
        n += 1 + m;
    }
    n
}

/// findEmailIndex returns a stop index value if the given bytes seem an email address.
function find_email_index(b: uint8array) -> int {
    find_email_index_at(b, 0)
}

/// `find_email_index(b[at:])` without copying; the result is relative to `at`.
function find_email_index_at(b: uint8array, at: int) -> int {
    let n = b.length() - at;
    let i = 0;
    while (i < n) {
        let c = b[at + i];
        if ((email_table(c) & 1) != 1) {
            break;
        }
        i += 1;
    }
    if (i == 0) {
        return -1;
    }
    if (i >= n || b[at + i] != 64) {
        return -1;
    }
    i += 1;
    if (i >= n) {
        return -1;
    }
    let m = scan_email_domain(b, at + i);
    if (m == 0) {
        return -1;
    }
    i + m
}

// Go: `urlTable` / `emailTable` are package-level [256]uint8 arrays. BAML has
// no package-level values, so they are generated as range checks.
function url_table(c: int) -> int {
    if (c >= 33 && c <= 42) {
        return 1;
    }
    if (c == 43) {
        return 5;
    }
    if (c == 44) {
        return 1;
    }
    if (c >= 45 && c <= 46) {
        return 5;
    }
    if (c == 47) {
        return 1;
    }
    if (c >= 48 && c <= 57) {
        return 5;
    }
    if (c >= 58 && c <= 59) {
        return 1;
    }
    if (c == 61) {
        return 1;
    }
    if (c >= 63 && c <= 64) {
        return 1;
    }
    if (c >= 65 && c <= 90) {
        return 7;
    }
    if (c >= 91 && c <= 96) {
        return 1;
    }
    if (c >= 97 && c <= 122) {
        return 7;
    }
    if (c >= 123 && c <= 255) {
        return 1;
    }
    0
}

function email_table(c: int) -> int {
    if (c == 33) {
        return 1;
    }
    if (c >= 35 && c <= 39) {
        return 1;
    }
    if (c >= 42 && c <= 43) {
        return 1;
    }
    if (c >= 45 && c <= 57) {
        return 1;
    }
    if (c == 61) {
        return 1;
    }
    if (c == 63) {
        return 1;
    }
    if (c >= 65 && c <= 90) {
        return 1;
    }
    if (c >= 94 && c <= 126) {
        return 1;
    }
    0
}
