// Port of goldmark parser/attribute.go (the default, `!goldmark_v1_attribute`
// build). The `goldmark_v1_attribute` build-tag variant is ported separately
// in attribute_v1.baml with `_v1`-suffixed names, since BAML has no build tags.

/// ParseAttributes parses attributes into a slice of ast.Attribute.
/// ParseAttributes returns parsed attributes if could parse
/// attributes, otherwise null (Go: `(nil, false)`).
function parse_attributes(reader: root.text.Reader) -> root.ast.Attribute[]? {
    let saved = reader.position();
    reader.skip_spaces();
    if (reader.peek() != 123) {
        reader.set_position(saved.line, saved.segment);
        return null;
    }
    reader.advance(1);
    let attrs: root.ast.Attribute[] = [];
    while (true) {
        if (reader.peek() == 125) {
            reader.advance(1);
            return attrs;
        }
        if (reader.peek() == root.text.EOF()) {
            return null;
        }
        let attr = parse_attribute(reader);
        if (attr == null) {
            reader.set_position(saved.line, saved.segment);
            return null;
        }
        if (attr.name == "class") {
            let updated = false;
            for (let a in attrs) {
                if (a.name == "class") {
                    let existing = a.value.str(reader.source());
                    let new_val = attr.value.str(reader.source());
                    a.value = root.text.new_multi_line_value_from_string(existing + " " + new_val, reader.decoder());
                    updated = true;
                    break;
                }
            }
            if (!updated) {
                attrs.push(attr);
            }
        } else {
            attrs.push(attr);
        }
        reader.skip_spaces();
    }
    null
}

function parse_attribute(reader: root.text.Reader) -> root.ast.Attribute? {
    reader.skip_spaces();
    let c = reader.peek();
    if (c == 35 || c == 46) {
        reader.advance(1);
        let pl = reader.peek_line();
        let line = pl.line ?? root.util.new_bytes();
        let seg = pl.segment;
        let i = 0;
        while (i < line.length() && !root.util.is_space(line[i]) && (!root.util.is_punct(line[i]) || line[i] == 95 || line[i] == 45 || line[i] == 58 || line[i] == 46)) {
            i += 1;
        }
        if (i == 0) {
            return null;
        }
        let name = if (c == 35) { "id" } else { "class" };
        reader.advance(i);
        return root.ast.Attribute {
            name: name,
            value: root.text.new_multi_line_value_from_index(root.text.new_index(seg.start, seg.start + i), reader.decoder()),
        };
    }
    let pl = reader.peek_line();
    let line = pl.line ?? root.util.new_bytes();
    let seg = pl.segment;
    if (line.length() == 0) {
        return null;
    }
    c = line[0];
    if (invalid_html_attribute_name_byte(c)) {
        return null;
    }
    let i = 0;
    while (i < line.length()) {
        c = line[i];
        if (invalid_html_attribute_name_byte(c)) {
            break;
        }
        i += 1;
    }
    let name = line.slice(0, i);
    reader.advance(i);
    reader.skip_spaces();
    c = reader.peek();
    if (c != 61) {
        return root.ast.Attribute {
            name: name.to_string(),
            value: root.text.new_multi_line_value_from_index(root.text.new_index(seg.start, seg.start + i), reader.decoder()),
        };
    }
    reader.advance(1);
    reader.skip_spaces();
    let value = parse_attribute_value(reader);
    if (value == null) {
        return null;
    }
    root.ast.Attribute { name: name.to_string(), value: value }
}

function parse_attribute_value(reader: root.text.Reader) -> root.text.MultiLineValue? {
    reader.skip_spaces();
    let c = reader.peek();
    if (c == root.text.EOF()) {
        return null;
    }
    if (c == 34) {
        return parse_attribute_quoted(reader, 34);
    }
    if (c == 39) {
        return parse_attribute_quoted(reader, 39);
    }
    parse_attribute_unquoted(reader)
}

function parse_attribute_quoted(reader: root.text.Reader, q: int) -> root.text.MultiLineValue? {
    reader.advance(1); // skip "/'
    let lines: root.text.Segment[] = [];
    while (true) {
        let pl = reader.peek_line();
        let line = pl.line ?? root.util.new_bytes();
        let seg = pl.segment;
        if (line.length() == 0) {
            break;
        }

        let i = 0;
        let offset = 0;
        while (i < line.length()) {
            let c = line[i];
            if (c == q) {
                offset = 1;
                break;
            }
            i += 1;
        }

        reader.advance(i + offset);
        lines.push(seg.with_stop(seg.start + i));
        if (offset == 1) {
            let b = root.text.new_value_builder();
            b.decoder(reader.decoder());
            for (let l in lines) {
                b.add_segment(l);
            }
            return b.build_multi_line();
        }
    }
    null
}

function parse_attribute_unquoted(reader: root.text.Reader) -> root.text.MultiLineValue? {
    let pl = reader.peek_line();
    let line = pl.line ?? root.util.new_bytes();
    let seg = pl.segment;
    let i = 0;
    while (i < line.length()) {
        let c = line[i];
        if (root.util.is_space(c) || c == 125) {
            break;
        }
        // ", \, >, <, =, `, and ' are not allowed in unquoted HTML attribute values.
        // But most of implementations ignore this rule, so we also ignore it.
        i += 1;
    }
    reader.advance(i);
    root.text.new_multi_line_value_from_index(root.text.new_index(seg.start, seg.start + i), reader.decoder())
}

/// Go: `invalidHTMLAttributeNameByte` (a package-level [256]bool table).
function invalid_html_attribute_name_byte(c: int) -> bool {
    // ASCII whitespace / control characters.
    if (c <= 0x20 || c == 0x7f) {
        return true;
    }
    // Forbidden characters.
    c == 34 || c == 39 || c == 60 || c == 62 || c == 47 || c == 61 || c == 125
}
