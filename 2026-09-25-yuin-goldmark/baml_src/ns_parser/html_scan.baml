// Port of goldmark parser/html_scan.go.

function is_alpha(c: int) -> bool {
    (c >= 97 && c <= 122) || (c >= 65 && c <= 90)
}

function has_prefix_fold(b: uint8array, s: string) -> bool {
    has_prefix_fold_at(b, 0, s)
}

/// Go: `hasPrefixFold(b[at:], s)` without copying.
function has_prefix_fold_at(b: uint8array, at: int, s: string) -> bool {
    let sb = s.to_utf8();
    if (b.length() - at < sb.length()) {
        return false;
    }
    let i = 0;
    while (i < sb.length()) {
        let c = b[at + i];
        let d = sb[i];
        if (c >= 65 && c <= 90) {
            c += 32;
        }
        if (d >= 65 && d <= 90) {
            d += 32;
        }
        if (c != d) {
            return false;
        }
        i += 1;
    }
    true
}

function contains_fold(b: uint8array, s: string) -> bool {
    let sl = s.to_utf8().length();
    if (sl == 0) {
        return true;
    }
    let i = 0;
    while (i + sl <= b.length()) {
        if (has_prefix_fold_at(b, i, s)) {
            return true;
        }
        i += 1;
    }
    false
}

function is_attr_separator(c: int) -> bool {
    c == 32 || c == 9 || c == 13 || c == 10
}

function is_attr_name_start_byte(c: int) -> bool {
    is_alpha(c) || c == 95 || c == 58
}

function is_attr_name_byte(c: int) -> bool {
    root.util.is_alpha_numeric(c) || c == 58 || c == 46 || c == 95 || c == 45
}

function is_unquoted_attr_value_byte(c: int) -> bool {
    c > 0x20 && c < 0xff && c != 34 && c != 39 && c != 61 && c != 60 && c != 62 && c != 96
}

/// Result of `scan_tag_name_bytes` / `scan_html_attributes_bytes`
/// (Go: `(end int, ok/hasAttr bool)`).
class ScanResult {
    end: int,
    ok: bool,
}

function scan_tag_name_bytes(line: uint8array, pos: int) -> ScanResult {
    if (pos >= line.length() || !is_alpha(line[pos])) {
        return ScanResult { end: pos, ok: false };
    }
    let end = pos + 1;
    while (end < line.length() && (root.util.is_alpha_numeric(line[end]) || line[end] == 45)) {
        end += 1;
    }
    ScanResult { end: end, ok: true }
}

function scan_html_attributes_bytes(line: uint8array, pos0: int) -> ScanResult {
    let pos = pos0;
    let has_attr = false;
    while (true) {
        let i = pos;
        while (i < line.length() && is_attr_separator(line[i])) {
            i += 1;
        }
        if (i == pos || i >= line.length() || !is_attr_name_start_byte(line[i])) {
            return ScanResult { end: pos, ok: has_attr };
        }
        i += 1;
        while (i < line.length() && is_attr_name_byte(line[i])) {
            i += 1;
        }
        let j = i;
        while (j < line.length() && is_attr_separator(line[j])) {
            j += 1;
        }
        if (j >= line.length() || line[j] != 61) {
            pos = i;
            has_attr = true;
            continue;
        }
        j += 1;
        while (j < line.length() && is_attr_separator(line[j])) {
            j += 1;
        }
        if (j >= line.length()) {
            // No value follows '=': the whole "=value" part is optional in
            // attributePattern, so back off to the attribute name only.
            return ScanResult { end: i, ok: true };
        }
        let q = line[j];
        if (q == 39 || q == 34) {
            let k = j + 1;
            while (k < line.length() && line[k] != q) {
                k += 1;
            }
            if (k >= line.length()) {
                return ScanResult { end: i, ok: true }; // unterminated quote: back off to name only.
            }
            pos = k + 1;
            has_attr = true;
        } else if (is_unquoted_attr_value_byte(q)) {
            let k = j + 1;
            while (k < line.length() && is_unquoted_attr_value_byte(line[k])) {
                k += 1;
            }
            pos = k;
            has_attr = true;
        } else {
            return ScanResult { end: i, ok: true }; // invalid value start: back off to name only.
        }
    }
    ScanResult { end: pos, ok: has_attr }
}

function skip_attr_name_bytes_reader(r: root.text.Reader) -> void {
    let line = r.peek_line().line ?? root.util.new_bytes();
    let i = 0;
    while (i < line.length() && is_attr_name_byte(line[i])) {
        i += 1;
    }
    if (i > 0) {
        r.advance(i);
    }
}

function skip_unquoted_attr_value_bytes_reader(r: root.text.Reader) -> void {
    let line = r.peek_line().line ?? root.util.new_bytes();
    let i = 0;
    while (i < line.length() && is_unquoted_attr_value_byte(line[i])) {
        i += 1;
    }
    if (i > 0) {
        r.advance(i);
    }
}

function skip_attr_separator_bytes_reader(r: root.text.Reader) -> bool {
    let consumed = false;
    while (true) {
        let line = r.peek_line().line;
        if (line == null) {
            return consumed;
        }
        let i = 0;
        while (i < line.length() && is_attr_separator(line[i])) {
            i += 1;
        }
        if (i > 0) {
            r.advance(i);
            consumed = true;
        }
        if (i < line.length()) {
            return consumed;
        }
    }
    consumed
}

function skip_to_closing_quote_bytes_reader(r: root.text.Reader, q: int) -> bool {
    while (true) {
        let line = r.peek_line().line;
        if (line == null) {
            return false;
        }
        let i = root.util.index_byte(line, q);
        if (i >= 0) {
            r.advance(i);
            return true;
        }
        r.advance(line.length());
    }
    false
}

function scan_tag_name_reader(r: root.text.Reader) -> bool {
    let line = r.peek_line().line ?? root.util.new_bytes();
    let sr = scan_tag_name_bytes(line, 0);
    if (!sr.ok) {
        return false;
    }
    r.advance(sr.end);
    true
}

function skip_attr_separators_reader(r: root.text.Reader) -> void {
    while (true) {
        let line = r.peek_line().line;
        if (line == null) {
            return;
        }
        let i = 0;
        while (i < line.length()) {
            let c = line[i];
            if (c != 32 && c != 9 && c != 10) {
                break;
            }
            i += 1;
        }
        if (i > 0) {
            r.advance(i);
        }
        if (i >= line.length()) {
            continue;
        }
        if (line[i] != 13) {
            return;
        }
        let saved = r.position();
        r.advance(1);
        if (r.peek() != 10) {
            r.set_position(saved.line, saved.segment);
            return;
        }
        r.advance(1);
    }
}

function scan_html_attributes_reader(r: root.text.Reader) -> void {
    while (true) {
        let has_sep = skip_attr_separator_bytes_reader(r);
        if (!has_sep || !is_attr_name_start_byte(r.peek())) {
            return;
        }
        r.advance(1);
        skip_attr_name_bytes_reader(r);
        let name_end = r.position();
        skip_attr_separator_bytes_reader(r);
        if (r.peek() != 61) {
            r.set_position(name_end.line, name_end.segment);
            continue;
        }
        r.advance(1);
        skip_attr_separator_bytes_reader(r);
        let q = r.peek();
        if (q == 39 || q == 34) {
            r.advance(1);
            if (!skip_to_closing_quote_bytes_reader(r, q)) {
                r.set_position(name_end.line, name_end.segment);
                continue;
            }
            r.advance(1);
        } else if (is_unquoted_attr_value_byte(q)) {
            r.advance(1);
            skip_unquoted_attr_value_bytes_reader(r);
        } else {
            r.set_position(name_end.line, name_end.segment);
        }
    }
}
