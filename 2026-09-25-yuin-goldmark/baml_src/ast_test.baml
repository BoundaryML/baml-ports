// Port of goldmark ast_test.go.

class BlankPrevCase {
    name: string,
    src: string,
    node: (n: root.ast.Node) -> root.ast.Node? throws never,
    expected: bool,
}

function has_blank_previous_lines_failures() -> string[] {
    let cases = [
        BlankPrevCase {
            name: "nesting paragraphs in blockquotes",
            src: "\n> a\n> \n> b\n",
            node: (n: root.ast.Node) -> root.ast.Node? { n.first_child()?.first_child()?.next_sibling() },
            expected: true,
        },
        BlankPrevCase {
            name: "nesting HTML blocks in blockquotes",
            src: "\n> <!-- a -->\n> \n> <!-- b -->\n",
            node: (n: root.ast.Node) -> root.ast.Node? { n.first_child()?.first_child()?.next_sibling() },
            expected: true,
        },
        BlankPrevCase {
            name: "nesting HTML blocks in blockquotes",
            src: "\n> <!-- a -->\n> <!-- b -->\n",
            node: (n: root.ast.Node) -> root.ast.Node? { n.first_child()?.first_child()?.next_sibling() },
            expected: false,
        },
        BlankPrevCase {
            name: "nesting loose lists in blockquotes",
            src: "\n> - a\n> \n> - b\n",
            node: (n: root.ast.Node) -> root.ast.Node? { n.first_child()?.first_child()?.first_child()?.next_sibling() },
            expected: true,
        },
        BlankPrevCase {
            name: "nesting tight lists in blockquotes",
            src: "\n> - a\n> - b\n",
            node: (n: root.ast.Node) -> root.ast.Node? { n.first_child()?.first_child()?.first_child()?.next_sibling() },
            expected: false,
        },
        BlankPrevCase {
            name: "nesting paragraphs in lists",
            src: "\n- a\n\n  b\n",
            node: (n: root.ast.Node) -> root.ast.Node? { n.first_child()?.first_child()?.first_child()?.next_sibling() },
            expected: true,
        },
    ];
    let failures: string[] = [];
    for (let cs in cases) {
        let n = root.parser.new().parse(cs.src.to_utf8(), []);
        let f = cs.node;
        let target = f(n);
        let got = if (target == null) { !cs.expected } else { root.parser.has_blank_previous_lines(target) };
        if (got != cs.expected) {
            failures.push(cs.name + ": expected " + cs.expected.to_string());
        }
    }
    failures
}

test "TestHasBlankPreviousLines" {
    assert.equal(has_blank_previous_lines_failures(), []);
}

function pos_of(n: root.ast.Node?) -> int {
    if (n == null) {
        return -999;
    }
    n.pos()
}

function inline_pos_failures() -> string[] {
    let source = "[bar][]\n\n[foo][bar]\n\n[bar]\n\n[foo](http://example.com)\n\naaaa **b** \n\n![aaa](http://example.com/foo.png \"title\")\n\n[bar]: \n  /url \"ti\n  tle\"\n".to_utf8();
    let n = root.parser.new().parse(source, []);
    let failures: string[] = [];
    if (pos_of(n.first_child()?.first_child()) != 0) {
        failures.push("unexpected position for 1st link reference");
    }
    if (pos_of(n.first_child()?.next_sibling()?.first_child()) != 9) {
        failures.push("unexpected position for 2nd link reference");
    }
    if (pos_of(n.first_child()?.next_sibling()?.next_sibling()?.first_child()) != 21) {
        failures.push("unexpected position for 3rd link reference");
    }
    if (pos_of(n.first_child()?.next_sibling()?.next_sibling()?.next_sibling()?.first_child()) != 28) {
        failures.push("unexpected position for 1st inline link ");
    }
    if (pos_of(n.first_child()?.next_sibling()?.next_sibling()?.next_sibling()?.next_sibling()?.first_child()?.next_sibling()) != 60) {
        failures.push("unexpected position for 1st emphasis");
    }
    if (pos_of(n.first_child()?.next_sibling()?.next_sibling()?.next_sibling()?.next_sibling()?.next_sibling()?.first_child()) != 68) {
        failures.push("unexpected position for 1st image");
    }
    failures
}

test "TestInlinePos" {
    assert.equal(inline_pos_failures(), []);
}

function block_pos_failures() -> string[] {
    let source = ("paragraph text\n\n## heading\n\n---\n\n> blockquote\n\n- list item\n\n1. ordered\n\n    indented code\n\n" + "```go\nfenced code\n```" + "\n\n<!-- html block -->\n\n[bar]: /url").to_utf8();
    let n = root.parser.new().parse(source, []);
    let paragraph = n.first_child();
    let heading = paragraph?.next_sibling();
    let thematic_break = heading?.next_sibling();
    let blockquote = thematic_break?.next_sibling();
    let unordered_list = blockquote?.next_sibling();
    let ordered_list = unordered_list?.next_sibling();
    let code_block = ordered_list?.next_sibling();
    let html_block = code_block?.next_sibling();
    let link_ref_def = html_block?.next_sibling();
    let failures: string[] = [];
    if (pos_of(paragraph) != 0) {
        failures.push("unexpected position for paragraph");
    }
    if (pos_of(heading) != 16) {
        failures.push("unexpected position for heading");
    }
    if (pos_of(thematic_break) != 28) {
        failures.push("unexpected position for thematic break");
    }
    if (pos_of(blockquote) != 33) {
        failures.push("unexpected position for blockquote");
    }
    if (pos_of(unordered_list) != 47) {
        failures.push("unexpected position for unordered list");
    }
    if (pos_of(ordered_list) != 60) {
        failures.push("unexpected position for ordered list");
    }
    if (pos_of(code_block) != 91) {
        failures.push("unexpected position for fenced code block");
    }
    if (pos_of(html_block) != 114) {
        failures.push("unexpected position for html block");
    }
    if (pos_of(link_ref_def) != 135) {
        failures.push("unexpected position for link reference definition");
    }
    failures
}

test "TestBlockPos" {
    assert.equal(block_pos_failures(), []);
}

function block_pos_with_tabs_failures() -> string[] {
    let n = root.parser.new().parse(">\t# x\n".to_utf8(), []);
    let blockquote = n.first_child();
    let failures: string[] = [];
    if (pos_of(blockquote) != 0) {
        failures.push("unexpected position for blockquote");
    }
    if (pos_of(blockquote?.first_child()) != 2) {
        failures.push("unexpected position for heading");
    }
    failures
}

test "TestBlockPosWithTabs" {
    assert.equal(block_pos_with_tabs_failures(), []);
}

function raw_text_failures() -> string[] {
    let source = "`inline &amp; value` inline &amp; value <code class=\"&AElig;\">inline &AElig; value</code><http://www.example.com/&AElig;>[aaa](http://www.example.com/&AElig;)".to_utf8();
    let ctx = root.parser.new_context();
    let n = root.parser.new().parse(source, [root.parser.with_context(ctx)]);
    let failures: string[] = [];
    let c1 = n.first_child()?.first_child();
    // Go uses unchecked type assertions (`.(*ast.CodeSpan)`), which panic on mismatch.
    let code1 = match (c1) {
        let c: root.ast.CodeSpan => c,
        _ => {
            return ["1st child is not a code span"];
        }
    };
    // inline code value is a raw text
    if (code1.value.value(source) != "inline &amp; value") {
        failures.push("unexpected value for 1st code span");
    }
    // inline text is a normal text
    let text = match (code1.next_sibling()) {
        let t: root.ast.Text => t,
        _ => {
            return ["expected a text"];
        }
    };
    if (text.value.value(source) != " inline & value ") {
        failures.push("unexpected value for text");
    }
    // opening raw html is a raw text
    let code2 = match (text.next_sibling()) {
        let r: root.ast.RawHTML => r,
        _ => {
            return ["expected a raw html"];
        }
    };
    if (code2.value.value(source) != "<code class=\"&AElig;\">") {
        failures.push("unexpected value for raw html");
    }
    // text inside raw html is a text
    let text2 = match (code2.next_sibling()) {
        let t: root.ast.Text => t,
        _ => {
            return ["expected a text"];
        }
    };
    if (text2.value.value(source) != "inline Æ value") {
        failures.push("unexpected value for text");
    }
    // closing raw html is a raw text
    let code3 = match (text2.next_sibling()) {
        let r: root.ast.RawHTML => r,
        _ => {
            return ["expected a raw html"];
        }
    };
    if (code3.value.value(source) != "</code>") {
        failures.push("unexpected value for raw html");
    }
    // autolink text, label, destination are raw texts
    let autolink = match (code3.next_sibling()) {
        let a: root.ast.AutoLink => a,
        _ => {
            return ["expected an autolink"];
        }
    };
    if (autolink.destination.value(source) != "http://www.example.com/&AElig;") {
        failures.push("unexpected value for autolink");
    }
    if (autolink.label.value(source) != "http://www.example.com/&AElig;") {
        failures.push("unexpected value for autolink");
    }
    if (autolink.text.value(source) != "<http://www.example.com/&AElig;>") {
        failures.push("unexpected value for autolink");
    }
    // link destination is a text
    let link = match (autolink.next_sibling()) {
        let l: root.ast.Link => l,
        _ => {
            return ["expected a link"];
        }
    };
    if (link.destination.value(source) != "http://www.example.com/Æ") {
        failures.push("unexpected value for link destination");
    }
    failures
}

test "TestRawText" {
    assert.equal(raw_text_failures(), []);
}

function test_pp() -> bool {
    let source = "`inline &amp; value` inline &amp; value <code class=\"&AElig;\">inline &AElig; value</code><http://www.example.com/&AElig;>[aaa](http://www.example.com/&AElig; \"\\.&AElig;\")".to_utf8();
    root.parser.new().parse(source, [root.parser.with_pretty_print(opts = [root.ast.with_source(false)])]);
    true
}

test "TestPP" {
    assert.is_true(test_pp());
}
