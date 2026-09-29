// Port of goldmark extension/tasklist_test.go.

function test_task_list() -> string[] {
    let markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(options = [
            root.parser.with_extensions([new_task_list_item_parser()]),
        ]),
        root.renderer.html.new(opts = [
            root.renderer.html.with_unsafe(),
            root.renderer.html.with_extensions([new_task_list_item_html_renderer()]),
        ]),
    );
    let t = root.testutil.new_recording_t();
    root.testutil.do_test_case_file(markdown, "extension/testdata/tasklist.txt", t, no = root.testutil.parse_cli_case_arg());
    t.errors
}

test "TestTaskList" {
    let errors = test_task_list();
    assert.equal(errors, []);
}
