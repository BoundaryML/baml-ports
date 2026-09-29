// Port of goldmark extension/definition_list_test.go.

function test_definition_list() -> string[] {
    let markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(options = [
            root.parser.with_extensions([new_definition_list_parser()]),
        ]),
        root.renderer.html.new(opts = [
            root.renderer.html.with_unsafe(),
            root.renderer.html.with_extensions([new_definition_list_html_renderer()]),
        ]),
    );
    let t = root.testutil.new_recording_t();
    root.testutil.do_test_case_file(markdown, "extension/testdata/definition_list.txt", t, no = root.testutil.parse_cli_case_arg());
    t.errors
}

test "TestDefinitionList" {
    let errors = test_definition_list();
    assert.equal(errors, []);
}
