// Port of goldmark extension/table_test.go.
//
// Each Go test becomes a helper returning the recorded failures plus a `test`
// block asserting it is empty. The Go test cases repeat the same markdown and
// expected HTML literally; here they are shared through small helpers.

function table_align_markdown() -> string {
    "\n| abc | defghi |\n:-: | -----------:\nbar | baz\n"
}

/// Expected output for the alignment tests; `th`/`td` attribute strings are
/// given per column (`c` = center column, `r` = right column).
function table_align_expected(th_c: string, th_r: string, td_c: string, td_r: string) -> string {
    "<table>\n<thead>\n<tr>\n<th" + th_c + ">abc</th>\n<th" + th_r + ">defghi</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td" + td_c + ">bar</td>\n<td" + td_r + ">baz</td>\n</tr>\n</tbody>\n</table>"
}

function table_test_case(no: int, description: string, markdown: string, expected: string) -> root.testutil.MarkdownTestCase {
    root.testutil.MarkdownTestCase {
        no: no,
        description: description,
        options: root.testutil.empty_options(),
        markdown: markdown,
        expected: expected,
    }
}

function test_table() -> string[] {
    let markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(options = [root.parser.with_extensions([new_table_parser()])]),
        root.renderer.html.new(opts = [
            root.renderer.html.with_unsafe(),
            root.renderer.html.with_xhtml(),
            root.renderer.html.with_extensions([new_table_html_renderer()]),
        ]),
    );
    let t = root.testutil.new_recording_t();
    root.testutil.do_test_case_file(markdown, "extension/testdata/table.txt", t, no = root.testutil.parse_cli_case_arg());
    t.errors
}

test "TestTable" {
    let errors = test_table();
    assert.equal(errors.length(), 0);
}

function test_table_with_align_default() -> string[] {
    let t = root.testutil.new_recording_t();
    let markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(options = [root.parser.with_extensions([new_table_parser()])]),
        root.renderer.html.new(opts = [
            root.renderer.html.with_xhtml(),
            root.renderer.html.with_unsafe(),
            root.renderer.html.with_extensions([new_table_html_renderer(opts = [
                with_table_cell_align_method(TableCellAlignMethod.TableCellAlignDefault),
            ])]),
        ]),
    );
    root.testutil.do_test_case(
        markdown,
        table_test_case(
            1,
            "Cell with TableCellAlignDefault and XHTML should be rendered as an align attribute",
            table_align_markdown(),
            table_align_expected(" align=\"center\"", " align=\"right\"", " align=\"center\"", " align=\"right\""),
        ),
        t,
    );

    markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(options = [root.parser.with_extensions([new_table_parser()])]),
        root.renderer.html.new(opts = [
            root.renderer.html.with_unsafe(),
            root.renderer.html.with_extensions([new_table_html_renderer(opts = [
                with_table_cell_align_method(TableCellAlignMethod.TableCellAlignDefault),
            ])]),
        ]),
    );
    root.testutil.do_test_case(
        markdown,
        table_test_case(
            2,
            "Cell with TableCellAlignDefault and HTML5 should be rendered as a style attribute",
            table_align_markdown(),
            table_align_expected(" style=\"text-align:center\"", " style=\"text-align:right\"", " style=\"text-align:center\"", " style=\"text-align:right\""),
        ),
        t,
    );
    t.errors
}

test "TestTableWithAlignDefault" {
    let errors = test_table_with_align_default();
    assert.equal(errors.length(), 0);
}

function test_table_with_align_attribute() -> string[] {
    let t = root.testutil.new_recording_t();
    let markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(options = [root.parser.with_extensions([new_table_parser()])]),
        root.renderer.html.new(opts = [
            root.renderer.html.with_xhtml(),
            root.renderer.html.with_unsafe(),
            root.renderer.html.with_extensions([new_table_html_renderer(opts = [
                with_table_cell_align_method(TableCellAlignMethod.TableCellAlignAttribute),
            ])]),
        ]),
    );
    root.testutil.do_test_case(
        markdown,
        table_test_case(
            1,
            "Cell with TableCellAlignAttribute and XHTML should be rendered as an align attribute",
            table_align_markdown(),
            table_align_expected(" align=\"center\"", " align=\"right\"", " align=\"center\"", " align=\"right\""),
        ),
        t,
    );

    markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(options = [root.parser.with_extensions([new_table_parser()])]),
        root.renderer.html.new(opts = [
            root.renderer.html.with_unsafe(),
            root.renderer.html.with_extensions([new_table_html_renderer(opts = [
                with_table_cell_align_method(TableCellAlignMethod.TableCellAlignAttribute),
            ])]),
        ]),
    );
    root.testutil.do_test_case(
        markdown,
        table_test_case(
            2,
            "Cell with TableCellAlignAttribute and HTML5 should be rendered as an align attribute",
            table_align_markdown(),
            table_align_expected(" align=\"center\"", " align=\"right\"", " align=\"center\"", " align=\"right\""),
        ),
        t,
    );
    t.errors
}

test "TestTableWithAlignAttribute" {
    let errors = test_table_with_align_attribute();
    assert.equal(errors.length(), 0);
}

/// Go's test-local `tableStyleTransformer`.
class TableStyleTransformer {
    implements root.parser.ASTTransformer {
        function transform(self, node: root.ast.Document, reader: root.text.Reader, pc: root.parser.Context) -> void {
            let c1 = node.first_child();
            if (c1 == null) {
                return;
            }
            let c2 = c1.first_child();
            if (c2 == null) {
                return;
            }
            let c3 = c2.first_child();
            match (c3) {
                let cell: root.extension.ast.TableCell => {
                    cell.set_attribute("style", root.text.new_multi_line_value_from_string("font-size:1em", root.text.identity_decoder()));
                }
                _ => {}
            }
        }
    }
}

function test_table_with_align_style() -> string[] {
    let t = root.testutil.new_recording_t();
    let markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(options = [root.parser.with_extensions([new_table_parser()])]),
        root.renderer.html.new(opts = [
            root.renderer.html.with_xhtml(),
            root.renderer.html.with_unsafe(),
            root.renderer.html.with_extensions([new_table_html_renderer(opts = [
                with_table_cell_align_method(TableCellAlignMethod.TableCellAlignStyle),
            ])]),
        ]),
    );
    root.testutil.do_test_case(
        markdown,
        table_test_case(
            1,
            "Cell with TableCellAlignStyle and XHTML should be rendered as a style attribute",
            table_align_markdown(),
            table_align_expected(" style=\"text-align:center\"", " style=\"text-align:right\"", " style=\"text-align:center\"", " style=\"text-align:right\""),
        ),
        t,
    );

    markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(options = [root.parser.with_extensions([new_table_parser()])]),
        root.renderer.html.new(opts = [
            root.renderer.html.with_unsafe(),
            root.renderer.html.with_extensions([new_table_html_renderer(opts = [
                with_table_cell_align_method(TableCellAlignMethod.TableCellAlignStyle),
            ])]),
        ]),
    );
    root.testutil.do_test_case(
        markdown,
        table_test_case(
            2,
            "Cell with TableCellAlignStyle and HTML5 should be rendered as a style attribute",
            table_align_markdown(),
            table_align_expected(" style=\"text-align:center\"", " style=\"text-align:right\"", " style=\"text-align:center\"", " style=\"text-align:right\""),
        ),
        t,
    );

    let style_transformer: root.parser.ASTTransformer = TableStyleTransformer {};
    markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(options = [
            root.parser.with_ast_transformers([root.util.prioritized(style_transformer, 0)]),
            root.parser.with_extensions([new_table_parser()]),
        ]),
        root.renderer.html.new(opts = [
            root.renderer.html.with_unsafe(),
            root.renderer.html.with_extensions([new_table_html_renderer(opts = [
                with_table_cell_align_method(TableCellAlignMethod.TableCellAlignStyle),
            ])]),
        ]),
    );
    root.testutil.do_test_case(
        markdown,
        table_test_case(
            3,
            "Styled cell should not be broken the style by the alignments",
            table_align_markdown(),
            table_align_expected(" style=\"font-size:1em;text-align:center\"", " style=\"text-align:right\"", " style=\"text-align:center\"", " style=\"text-align:right\""),
        ),
        t,
    );
    t.errors
}

test "TestTableWithAlignStyle" {
    let errors = test_table_with_align_style();
    assert.equal(errors.length(), 0);
}

function test_table_with_align_none() -> string[] {
    let t = root.testutil.new_recording_t();
    let markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(options = [root.parser.with_extensions([new_table_parser()])]),
        root.renderer.html.new(opts = [
            root.renderer.html.with_xhtml(),
            root.renderer.html.with_unsafe(),
            root.renderer.html.with_extensions([new_table_html_renderer(opts = [
                with_table_cell_align_method(TableCellAlignMethod.TableCellAlignNone),
            ])]),
        ]),
    );
    root.testutil.do_test_case(
        markdown,
        table_test_case(
            1,
            "Cell with TableCellAlignStyle and XHTML should not be rendered",
            table_align_markdown(),
            table_align_expected("", "", "", ""),
        ),
        t,
    );
    t.errors
}

test "TestTableWithAlignNone" {
    let errors = test_table_with_align_none();
    assert.equal(errors.length(), 0);
}

function test_table_fuzzed_panics() -> string[] {
    let t = root.testutil.new_recording_t();
    let markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(options = [root.parser.with_extensions([new_table_parser()])]),
        root.renderer.html.new(opts = [
            root.renderer.html.with_xhtml(),
            root.renderer.html.with_unsafe(),
            root.renderer.html.with_extensions([new_table_html_renderer()]),
        ]),
    );
    root.testutil.do_test_case(
        markdown,
        table_test_case(
            1,
            "This should not panic",
            "* 0\n-|\n\t0",
            "<ul>\n<li>\n<table>\n<thead>\n<tr>\n<th>0</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>0</td>\n</tr>\n</tbody>\n</table>\n</li>\n</ul>",
        ),
        t,
    );
    t.errors
}

test "TestTableFuzzedPanics" {
    let errors = test_table_fuzzed_panics();
    assert.equal(errors.length(), 0);
}

/// Developer helper (not in Go): runs table.txt cases and returns a summary.
function table_report() -> string {
    let markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(options = [root.parser.with_extensions([new_table_parser()])]),
        root.renderer.html.new(opts = [
            root.renderer.html.with_unsafe(),
            root.renderer.html.with_xhtml(),
            root.renderer.html.with_extensions([new_table_html_renderer()]),
        ]),
    );
    let passed = 0;
    let failed: string[] = [];
    for (let c in root.testutil.parse_test_case_file("extension/testdata/table.txt")) {
        let t = root.testutil.new_recording_t();
        root.testutil.do_test_case(markdown, c, t);
        if (t.errors.length() == 0) {
            passed += 1;
        } else {
            failed.push(c.no.to_string());
        }
    }
    "passed=" + passed.to_string() + " failed=" + failed.length().to_string() + " [" + failed.join(",") + "]"
}
