// Port of goldmark text/value_v1.go (`goldmark_v1_attribute` build tag).
//
// BAML has no build tags, so this variant is always compiled; its entry points
// are free functions (Go adds an `Any` method to MultiLineValue under the tag).
// Go's `any` results map to BAML `unknown`: `map[string]any` ->
// `map<string, unknown>`, `[]any` -> `unknown[]`, `[]byte` -> `uint8array`,
// `float64` -> `float`, `bool`, and `nil` -> `null`.

/// Result of `parse_attribute_value` (Go: `(any, bool)`).
class AttributeValueResult {
    value: unknown,
    ok: bool,
}

function attr_fail() -> AttributeValueResult {
    AttributeValueResult { value: null, ok: false }
}

/// Any parses an attribute value and returns the parsed value if could parse
/// an attribute value, otherwise nil. (Go: `MultiLineValue.Any`.)
function multi_line_value_any(v: MultiLineValue, source: uint8array) -> unknown {
    let b = v.bytes(source);
    let r = new_reader(b, identity_decoder());
    let a = parse_attribute_value(r);
    if (!a.ok) {
        return null;
    }
    a.value
}

/// ParseAttributeValue parses an attribute value and returns the parsed value and true if could parse
/// an attribute value, otherwise nil and false.
function parse_attribute_value(reader: Reader) -> AttributeValueResult {
    reader.skip_spaces();
    let c = reader.peek();
    let r = if (c == EOF()) {
        return attr_fail();
    } else if (c == 123) {
        parse_attribute_map(reader)
    } else if (c == 91) {
        parse_attribute_array(reader)
    } else if (c == 34) {
        let s = parse_attribute_string(reader);
        if (s == null) { attr_fail() } else { AttributeValueResult { value: s, ok: true } }
    } else if (c == 45 || c == 43 || root.util.is_numeric(c)) {
        parse_attribute_number(reader)
    } else {
        parse_attribute_others(reader)
    };
    if (!r.ok) {
        return attr_fail();
    }
    r
}

function parse_attribute_map(reder: Reader) -> AttributeValueResult {
    reder.advance(1); // skip {
    let ret: map<string, unknown> = {};
    let i = 0;
    while (true) {
        let c = reder.peek();
        let comma = false;
        if (i != 0 && c == 44) {
            reder.advance(1);
            comma = true;
        }
        if (c == 125) {
            if (!comma) {
                reder.advance(1);
                return AttributeValueResult { value: ret, ok: true };
            }
            return attr_fail();
        }
        reder.skip_spaces();
        let key = parse_attribute_string(reder);
        if (key == null) {
            return attr_fail();
        }
        reder.skip_spaces();
        if (reder.peek() != 58 && reder.peek() != 61) {
            return attr_fail();
        }
        reder.advance(1);
        reder.skip_spaces();
        let value = parse_attribute_value(reder);
        if (!value.ok) {
            return attr_fail();
        }
        ret[key.to_string()] = value.value;
        reder.skip_spaces();
        i += 1;
    }
    attr_fail()
}

function parse_attribute_array(reader: Reader) -> AttributeValueResult {
    reader.advance(1); // skip [
    let ret: unknown[] = [];
    let i = 0;
    while (true) {
        let c = reader.peek();
        let comma = false;
        if (i != 0 && c == 44) {
            reader.advance(1);
            comma = true;
        }
        if (c == 93) {
            if (!comma) {
                reader.advance(1);
                return AttributeValueResult { value: ret, ok: true };
            }
            return attr_fail();
        }
        reader.skip_spaces();
        let value = parse_attribute_value(reader);
        if (!value.ok) {
            return attr_fail();
        }
        ret.push(value.value);
        reader.skip_spaces();
        i += 1;
    }
    attr_fail()
}

/// Go returns `([]byte, bool)`; null means not ok.
function parse_attribute_string(reader: Reader) -> uint8array? {
    reader.advance(1); // skip "
    let line = reader.peek_line().line ?? root.util.new_bytes();
    let i = 0;
    let l = line.length();
    let buf = root.util.new_bytes();
    while (i < l) {
        let c = line[i];
        if (c == 92 && i != l - 1) {
            let n = line[i + 1];
            if (n == 34 || n == 47 || n == 92) {
                buf.push(n);
                i += 2;
            } else if (n == 98) {
                buf.push(8);
                i += 2;
            } else if (n == 102) {
                buf.push(12);
                i += 2;
            } else if (n == 110) {
                buf.push(10);
                i += 2;
            } else if (n == 114) {
                buf.push(13);
                i += 2;
            } else if (n == 116) {
                buf.push(9);
                i += 2;
            } else {
                buf.push(92);
                i += 1;
            }
            continue;
        }
        if (c == 34) {
            reader.advance(i + 1);
            return buf;
        }
        buf.push(c);
        i += 1;
    }
    null
}

function scan_attribute_decimal(reader: Reader, w: uint8array) -> void {
    while (true) {
        let c = reader.peek();
        if (root.util.is_numeric(c)) {
            w.push(c);
        } else {
            return;
        }
        reader.advance(1);
    }
}

function parse_attribute_number(reader: Reader) -> AttributeValueResult {
    let sign = 1.0;
    let c = reader.peek();
    if (c == 45) {
        sign = -1.0;
        reader.advance(1);
    } else if (c == 43) {
        reader.advance(1);
    }
    let buf = root.util.new_bytes();
    if (!root.util.is_numeric(reader.peek())) {
        return attr_fail();
    }
    scan_attribute_decimal(reader, buf);
    if (buf.length() == 0) {
        return attr_fail();
    }
    c = reader.peek();
    if (c == 46) {
        buf.push(c);
        reader.advance(1);
        scan_attribute_decimal(reader, buf);
    }
    c = reader.peek();
    if (c == 101 || c == 69) {
        buf.push(c);
        reader.advance(1);
        c = reader.peek();
        if (c == 45 || c == 43) {
            buf.push(c);
            reader.advance(1);
        }
        scan_attribute_decimal(reader, buf);
    }
    let f = baml.Float.parse(buf.to_string()) catch_all (e) { _ => null };
    if (f == null) {
        return attr_fail();
    }
    AttributeValueResult { value: sign * f, ok: true }
}

function parse_attribute_others(reader: Reader) -> AttributeValueResult {
    let line = reader.peek_line().line ?? root.util.new_bytes();
    if (line.length() == 0) {
        // Go indexes line[0] unconditionally (and would panic here).
        return attr_fail();
    }
    let c = line[0];
    if (!((c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 95 || c == 58)) {
        return attr_fail();
    }
    let i = 0;
    while (i < line.length()) {
        let d = line[i];
        if (!((d >= 97 && d <= 122) || (d >= 65 && d <= 90) || (d >= 48 && d <= 57) || d == 95 || d == 58 || d == 46 || d == 45)) {
            break;
        }
        i += 1;
    }
    let value = line.slice(0, i);
    reader.advance(i);
    let vs = value.to_string();
    if (vs == "true") {
        return AttributeValueResult { value: true, ok: true };
    }
    if (vs == "false") {
        return AttributeValueResult { value: false, ok: true };
    }
    if (vs == "null") {
        return AttributeValueResult { value: null, ok: true };
    }
    AttributeValueResult { value: value, ok: true }
}
