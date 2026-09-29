// Port of goldmark parser/attribute_v1.go (`goldmark_v1_attribute` build tag).
//
// BAML has no build tags, so both attribute syntaxes are compiled; the v1
// variant's functions carry a `_v1` suffix. Use `parse_attributes_v1` where Go
// would be built with `-tags goldmark_v1_attribute`.

function attr_name_id() -> string {
    "id"
}

function attr_name_class() -> string {
    "class"
}

/// ParseAttributes parses attributes into a slice of ast.Attribute.
/// ParseAttributes returns a parsed attributes if could parse
/// attributes, otherwise null (Go: `(nil, false)`).
function parse_attributes_v1(reader: root.text.Reader) -> root.ast.Attribute[]? {
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
        let attr = parse_attribute_v1(reader);
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
                    a.value = root.text.new_multi_line_value_from_string(existing + " " + new_val, root.text.identity_decoder());
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
        if (reader.peek() == 44) {
            reader.advance(1);
            reader.skip_spaces();
        }
    }
    null
}

function parse_attribute_v1(reader: root.text.Reader) -> root.ast.Attribute? {
    reader.skip_spaces();
    let c = reader.peek();
    if (c == 35 || c == 46) {
        reader.advance(1);
        let line = reader.peek_line().line ?? root.util.new_bytes();
        let i = 0;
        // HTML5 allows any kind of characters as id, but XHTML restricts characters for id.
        // CommonMark is basically defined for XHTML(even though it is legacy).
        // So we restrict id characters.
        while (i < line.length() && !root.util.is_space(line[i]) && (!root.util.is_punct(line[i]) || line[i] == 95 || line[i] == 45 || line[i] == 58 || line[i] == 46)) {
            i += 1;
        }
        let name = if (c == 35) { attr_name_id() } else { attr_name_class() };
        reader.advance(i);
        return root.ast.Attribute {
            name: name,
            value: root.text.new_multi_line_value_from_bytes(line.slice(0, i), root.text.identity_decoder()),
        };
    }
    let line = reader.peek_line().line ?? root.util.new_bytes();
    if (line.length() == 0) {
        return null;
    }
    c = line[0];
    if (!((c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 95 || c == 58)) {
        return null;
    }
    let i = 0;
    while (i < line.length()) {
        c = line[i];
        if (!((c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57) || c == 95 || c == 58 || c == 46 || c == 45)) {
            break;
        }
        i += 1;
    }
    let name = line.slice(0, i);
    reader.advance(i);
    reader.skip_spaces();
    c = reader.peek();
    if (c != 61) {
        return null;
    }
    reader.advance(1);
    reader.skip_spaces();
    let pos1 = reader.position().segment;
    let r = root.text.parse_attribute_value(reader);
    if (!r.ok) {
        return null;
    }
    let pos2 = reader.position().segment;
    let value = reader.value_between(pos1.start, pos2.start);

    root.ast.Attribute { name: name.to_string(), value: value }
}
