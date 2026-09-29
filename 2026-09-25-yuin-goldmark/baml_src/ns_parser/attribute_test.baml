// Port of goldmark parser/attribute_test.go (`!goldmark_v1_attribute` build).

function parse_attrs_of(source: uint8array) -> root.ast.Attribute[]? {
    parse_attributes(root.text.new_reader(source, root.text.new_decoder([])))
}

function unquoted_attribute_failures() -> string[] {
    let source = "{key=value&quot;}".to_utf8();
    let attrs = parse_attrs_of(source);
    if (attrs == null) {
        return ["failed to parse attributes"];
    }
    // if value contains entity reference, it must be an instance of StringMultiLineValue
    if (attrs.length() != 1) {
        return ["expected 1 attribute, got " + attrs.length().to_string()];
    }
    if (attrs[0].name != "key") {
        return ["expected attribute name 'key', got '" + attrs[0].name + "'"];
    }
    if (attrs[0].value.value(source) != "value\"") {
        return ["expected attribute value 'value\"', got '" + attrs[0].value.value(source) + "'"];
    }
    if (attrs[0].value.str(source) != "value&quot;") {
        return ["expected attribute value 'value&quot;', got '" + attrs[0].value.str(source) + "'"];
    }
    if (attrs[0].value.is_owned()) {
        return ["expected attribute value to be not owned, but it is"];
    }

    let source2 = "{key=value}".to_utf8();
    let attrs2 = parse_attrs_of(source2);
    if (attrs2 == null) {
        return ["failed to parse attributes"];
    }
    // if value does not contain entity reference, it must be an instance of IndexMultiLineValue
    if (attrs2.length() != 1) {
        return ["expected 1 attribute, got " + attrs2.length().to_string()];
    }
    if (attrs2[0].name != "key") {
        return ["expected attribute name 'key', got '" + attrs2[0].name + "'"];
    }
    if (attrs2[0].value.str(source2) != "value") {
        return ["expected attribute value 'value', got '" + attrs2[0].value.str(source2) + "'"];
    }
    if (attrs2[0].value.is_owned()) {
        return ["expected attribute value to be not owned, but it is"];
    }
    let none: string[] = [];
    none
}

test "TestUnquotedAttribute" {
    assert.equal(unquoted_attribute_failures(), []);
}

function quoted_attribute_failures() -> string[] {
    let source = "{key=\"value\"}".to_utf8();
    let attrs = parse_attrs_of(source);
    if (attrs == null) {
        return ["failed to parse attributes"];
    }
    if (attrs.length() != 1) {
        return ["expected 1 attribute, got " + attrs.length().to_string()];
    }
    if (attrs[0].name != "key") {
        return ["expected attribute name 'key', got '" + attrs[0].name + "'"];
    }
    if (attrs[0].value.str(source) != "value") {
        return ["expected attribute value 'value', got '" + attrs[0].value.str(source) + "'"];
    }
    if (attrs[0].value.is_owned()) {
        return ["expected attribute value to be not owned, but it is"];
    }
    let none: string[] = [];
    none
}

test "TestQuotedAttribute" {
    assert.equal(quoted_attribute_failures(), []);
}

function id_and_class_attributes_failures() -> string[] {
    let source = "{#id .class1 .class2}".to_utf8();
    let attrs = parse_attrs_of(source);
    if (attrs == null) {
        return ["failed to parse attributes"];
    }
    if (attrs.length() != 2) {
        return ["expected 2 attributes, got " + attrs.length().to_string()];
    }
    if (attrs[0].name != "id") {
        return ["expected attribute name 'id', got '" + attrs[0].name + "'"];
    }
    if (attrs[0].value.str(source) != "id") {
        return ["expected attribute value 'id', got '" + attrs[0].value.str(source) + "'"];
    }
    if (attrs[1].name != "class") {
        return ["expected attribute name 'class', got '" + attrs[1].name + "'"];
    }
    if (attrs[1].value.str(source) != "class1 class2") {
        return ["expected attribute value 'class1 class2', got '" + attrs[1].value.str(source) + "'"];
    }
    let none: string[] = [];
    none
}

test "TestIdAndClassAttributes" {
    assert.equal(id_and_class_attributes_failures(), []);
}

function multi_line_attributes_failures() -> string[] {
    let source = "{value=\"aaa\n   bbb\"}".to_utf8();
    let attrs = parse_attrs_of(source);
    if (attrs == null) {
        return ["failed to parse attributes"];
    }
    if (attrs.length() != 1) {
        return ["expected 1 attribute, got " + attrs.length().to_string()];
    }
    if (attrs[0].name != "value") {
        return ["expected attribute name 'value', got '" + attrs[0].name + "'"];
    }
    if (attrs[0].value.str(source) != "aaa\n   bbb") {
        return ["expected attribute value 'aaa\\nbbb', got '" + attrs[0].value.str(source) + "'"];
    }
    if (attrs[0].value.is_owned()) {
        return ["expected attribute value to be not owned, but it is"];
    }
    let none: string[] = [];
    none
}

test "TestMultiLineAttributes" {
    assert.equal(multi_line_attributes_failures(), []);
}
