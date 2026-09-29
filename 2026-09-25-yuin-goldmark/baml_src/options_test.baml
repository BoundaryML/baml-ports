// Port of goldmark options_test.go (`!goldmark_v1_attribute` build).

function attribute_and_auto_heading_id_failures() -> string[] {
    let markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(options = [root.parser.with_attribute(), root.parser.with_auto_heading_id()]),
        root.renderer.html.new(),
    );
    let t = root.testutil.new_recording_t();
    root.testutil.do_test_case_file(markdown, "testdata/options-auto-heading-id.txt", t, no = root.testutil.parse_cli_case_arg());
    t.errors
}

test "TestAttributeAndAutoHeadingID" {
    assert.equal(attribute_and_auto_heading_id_failures(), []);
}

function parse_delimiter_simple_failures() -> string[] {
    let markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(options = [root.parser.with_parse_delimiter_func(root.parser.parse_delimiter_simple)]),
        root.renderer.html.new(opts = [root.renderer.html.with_unsafe()]),
    );
    let t = root.testutil.new_recording_t();
    root.testutil.do_test_case_file(markdown, "testdata/options-parse-delimiter-simple.txt", t, no = root.testutil.parse_cli_case_arg());
    t.errors
}

test "TestParseDelimiterSimple" {
    assert.equal(parse_delimiter_simple_failures(), []);
}
