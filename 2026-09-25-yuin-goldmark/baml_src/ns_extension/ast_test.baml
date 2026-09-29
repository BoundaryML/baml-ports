// Port of goldmark extension/ast_test.go (package extension_test).

function new_extension_parser() -> root.parser.Parser {
    root.parser.new(options = [
        root.parser.with_extensions([
            new_strikethrough_parser(),
            new_table_parser(),
            new_footnote_parser(),
            new_definition_list_parser(),
        ]),
    ])
}

function ext_ast_test_source() -> uint8array {
    "~~strike~~\n\n| a | b |\n|---|---|\n| c | d |\n\n[^fn]: footnote\n\nterm\n: definition\n\ntext [^fn] end\n".to_utf8()
}

function ext_pos(n: root.ast.Node?) -> int {
    if (n == null) {
        return -999;
    }
    n.pos()
}

function ext_inline_pos_failures() -> string[] {
    let n = new_extension_parser().parse(ext_ast_test_source(), []);
    let failures: string[] = [];
    // Strikethrough starts at the first character of the source
    if (ext_pos(n.first_child()?.first_child()) != 0) {
        failures.push("unexpected position for strikethrough");
    }
    // FootnoteReference is the 2nd child of the last paragraph
    if (ext_pos(n.last_child()?.first_child()?.next_sibling()) != 84) {
        failures.push("unexpected position for footnote reference");
    }
    failures
}

test "TestInlinePos" {
    assert.equal(ext_inline_pos_failures(), []);
}

function ext_block_pos_failures() -> string[] {
    let n = new_extension_parser().parse(ext_ast_test_source(), []);
    let failures: string[] = [];
    let table = n.first_child()?.next_sibling();
    if (ext_pos(table) != 12) {
        failures.push("unexpected position for table");
    }
    let table_header = table?.first_child();
    if (ext_pos(table_header) != 12) {
        failures.push("unexpected position for table header");
    }
    if (ext_pos(table_header?.first_child()) != 13) {
        failures.push("unexpected position for 1st table header cell");
    }
    if (ext_pos(table_header?.first_child()?.next_sibling()) != 17) {
        failures.push("unexpected position for 2nd table header cell");
    }
    let table_body = table?.last_child();
    if (ext_pos(table_body) != 32) {
        failures.push("unexpected position for table body");
    }
    let table_row = table_body?.first_child();
    if (ext_pos(table_row) != 32) {
        failures.push("unexpected position for table row");
    }
    if (ext_pos(table_row?.first_child()) != 33) {
        failures.push("unexpected position for 1st table body cell");
    }
    if (ext_pos(table_row?.first_child()?.next_sibling()) != 37) {
        failures.push("unexpected position for 2nd table body cell");
    }
    let footnotedef = table?.next_sibling();
    if (ext_pos(footnotedef) != 43) {
        failures.push("unexpected position for footnote definition");
    }
    let def_list = footnotedef?.next_sibling();
    if (ext_pos(def_list) != 60) {
        failures.push("unexpected position for definition list");
    }
    if (ext_pos(def_list?.first_child()) != 60) {
        failures.push("unexpected position for definition term");
    }
    if (ext_pos(def_list?.last_child()) != 65) {
        failures.push("unexpected position for definition description");
    }
    failures
}

test "TestBlockPos" {
    assert.equal(ext_block_pos_failures(), []);
}
