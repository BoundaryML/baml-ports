// Port of goldmark extension/typographer_test.go.

function test_typographer() -> string[] {
    let markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(options = [
            root.parser.with_extensions([new_typographer_parser()]),
        ]),
        root.renderer.html.new(opts = [
            root.renderer.html.with_unsafe(),
        ]),
    );
    let t = root.testutil.new_recording_t();
    root.testutil.do_test_case_file(markdown, "extension/testdata/typographer.txt", t, no = root.testutil.parse_cli_case_arg());
    t.errors
}

test "TestTypographer" {
    let errors = test_typographer();
    assert.equal(errors, []);
}
