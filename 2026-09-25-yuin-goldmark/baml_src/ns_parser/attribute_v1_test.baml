// Port of goldmark parser/attribute_v1_test.go (`goldmark_v1_attribute`
// build; uses the `_v1` functions).

function attr_v1_of(source: uint8array) -> root.ast.Attribute[]? {
    parse_attributes_v1(root.text.new_reader(source, root.text.new_decoder([])))
}

/// Go `v != float64(x)` on an `any`.
function is_float(v: unknown, x: float) -> bool {
    match (v) {
        let f: float => f == x,
        _ => false,
    }
}

function attribute_v1_failures() -> string[] {
    let source = "{key=[1,2,3]}".to_utf8();
    let attrs = attr_v1_of(source);
    if (attrs == null) {
        return ["failed to parse attributes"];
    }
    if (attrs.length() != 1) {
        return ["expected 1 attribute, got " + attrs.length().to_string()];
    }
    if (attrs[0].name != "key") {
        return ["expected attribute name 'key', got '" + attrs[0].name + "'"];
    }
    let v = root.text.multi_line_value_any(attrs[0].value, source);
    let a = match (v) {
        let arr: unknown[] => arr,
        _ => {
            return ["expected attribute value to be []any"];
        }
    };
    if (a.length() != 3) {
        return ["expected attribute value to have length 3, got " + a.length().to_string()];
    }
    if (!is_float(a[0], 1.0) || !is_float(a[1], 2.0) || !is_float(a[2], 3.0)) {
        return ["expected attribute value to be [1,2,3]"];
    }

    let source2 = "{key=1, key2=\"value with spaces\"}".to_utf8();
    let attrs2 = attr_v1_of(source2);
    if (attrs2 == null) {
        return ["failed to parse attributes"];
    }
    if (attrs2.length() != 2) {
        return ["expected 2 attributes, got " + attrs2.length().to_string()];
    }
    if (attrs2[0].name != "key") {
        return ["expected first attribute name 'key', got '" + attrs2[0].name + "'"];
    }
    if (attrs2[1].name != "key2") {
        return ["expected second attribute name 'key2', got '" + attrs2[1].name + "'"];
    }
    let v1 = root.text.multi_line_value_any(attrs2[0].value, source2);
    if (!is_float(v1, 1.0)) {
        return ["expected first attribute value to be float64 1"];
    }
    let v2 = root.text.multi_line_value_any(attrs2[1].value, source2);
    let b = match (v2) {
        let bs: uint8array => bs,
        _ => {
            return ["expected second attribute value to be []byte"];
        }
    };
    if (b.to_string() != "value with spaces") {
        return ["expected second attribute value to be 'value with spaces', got " + b.to_string()];
    }

    let source3 = "{key={\"nested\":[1,2,3], \"another\"=true}}".to_utf8();
    let attrs3 = attr_v1_of(source3);
    if (attrs3 == null) {
        return ["failed to parse attributes"];
    }
    if (attrs3.length() != 1) {
        return ["expected 1 attribute, got " + attrs3.length().to_string()];
    }
    if (attrs3[0].name != "key") {
        return ["expected attribute name 'key', got '" + attrs3[0].name + "'"];
    }
    let v3 = root.text.multi_line_value_any(attrs3[0].value, source3);
    let m = match (v3) {
        let mm: map<string, unknown> => mm,
        _ => {
            return ["expected attribute value to be map[string]any"];
        }
    };
    if (m.keys().length() != 2) {
        return ["expected attribute value to have length 2, got " + m.keys().length().to_string()];
    }
    let nested = match (m.get("nested")) {
        let arr: unknown[] => arr,
        _ => {
            return ["expected nested attribute value to be []any"];
        }
    };
    if (nested.length() != 3 || !is_float(nested[0], 1.0) || !is_float(nested[1], 2.0) || !is_float(nested[2], 3.0)) {
        return ["expected nested attribute value to be [1,2,3]"];
    }
    let another = match (m.get("another")) {
        let bv: bool => bv,
        _ => false,
    };
    if (!another) {
        return ["expected another attribute value to be true"];
    }
    let none: string[] = [];
    none
}

test "TestAttributeV1" {
    assert.equal(attribute_v1_failures(), []);
}
