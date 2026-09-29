// Port of goldmark extension/strikethrough_test.go.

function test_strikethrough() -> string[] {
    let markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(options = [
            root.parser.with_extensions([new_strikethrough_parser()]),
        ]),
        root.renderer.html.new(opts = [
            root.renderer.html.with_unsafe(),
            root.renderer.html.with_extensions([new_strikethrough_html_renderer()]),
        ]),
    );
    let t = root.testutil.new_recording_t();
    root.testutil.do_test_case_file(markdown, "extension/testdata/strikethrough.txt", t, no = root.testutil.parse_cli_case_arg());
    t.errors
}

test "TestStrikethrough" {
    let errors = test_strikethrough();
    assert.equal(errors, []);
}
