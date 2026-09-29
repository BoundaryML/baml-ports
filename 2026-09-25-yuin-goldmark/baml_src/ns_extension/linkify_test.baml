// Port of goldmark extension/linkify_test.go.

function linkify_must_regexp(pattern: string) -> baml.regex.Regex {
    baml.regex.new(pattern) catch_all (e) {
        _ => {
            baml.sys.panic("invalid regexp: " + pattern);
            baml.regex.new("x") catch_all (e2) { _ => baml.sys.panic("unreachable") }
        }
    }
}

function test_linkify() -> string[] {
    let markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(options = [
            root.parser.with_extensions([new_linkify_parser()]),
        ]),
        root.renderer.html.new(opts = [
            root.renderer.html.with_unsafe(),
        ]),
    );
    let t = root.testutil.new_recording_t();
    root.testutil.do_test_case_file(markdown, "extension/testdata/linkify.txt", t, no = root.testutil.parse_cli_case_arg());
    t.errors
}

test "TestLinkify" {
    let errors = test_linkify();
    assert.equal(errors, []);
}

function test_linkify_with_allowed_protocols() -> string[] {
    let markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(options = [
            root.parser.with_extensions([new_linkify_parser(opts = [
                with_allowed_protocols(["ssh:"]),
                // Go: regexp.MustCompile(`\w+://[^\s]+`). Note Go's `\w`/`\s`
                // are ASCII-only; the BAML engine's are Unicode-aware (same
                // result for this input).
                with_url_regexp(linkify_must_regexp("\\w+://[^\\s]+")),
            ])]),
        ]),
        root.renderer.html.new(opts = [
            root.renderer.html.with_xhtml(),
            root.renderer.html.with_unsafe(),
        ]),
    );
    let t = root.testutil.new_recording_t();
    root.testutil.do_test_case(markdown, root.testutil.MarkdownTestCase {
        no: 1,
        description: "",
        options: root.testutil.empty_options(),
        markdown: "hoge ssh://user@hoge.com. http://example.com/",
        expected: "<p>hoge <a href=\"ssh://user@hoge.com\">ssh://user@hoge.com</a>. http://example.com/</p>",
    }, t);
    t.errors
}

test "TestLinkifyWithAllowedProtocols" {
    let errors = test_linkify_with_allowed_protocols();
    assert.equal(errors, []);
}

function test_linkify_with_www_regexp() -> string[] {
    let markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(options = [
            root.parser.with_extensions([new_linkify_parser(opts = [
                with_www_regexp(linkify_must_regexp("www\\.example\\.com")),
            ])]),
        ]),
        root.renderer.html.new(opts = [
            root.renderer.html.with_xhtml(),
            root.renderer.html.with_unsafe(),
        ]),
    );
    let t = root.testutil.new_recording_t();
    root.testutil.do_test_case(markdown, root.testutil.MarkdownTestCase {
        no: 1,
        description: "",
        options: root.testutil.empty_options(),
        markdown: "www.google.com www.example.com",
        expected: "<p>www.google.com <a href=\"http://www.example.com\">www.example.com</a></p>",
    }, t);
    t.errors
}

test "TestLinkifyWithWWWRegexp" {
    let errors = test_linkify_with_www_regexp();
    assert.equal(errors, []);
}

function test_linkify_with_email_regexp() -> string[] {
    let markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(options = [
            root.parser.with_extensions([new_linkify_parser(opts = [
                with_email_regexp(linkify_must_regexp("user@example\\.com")),
            ])]),
        ]),
        root.renderer.html.new(opts = [
            root.renderer.html.with_xhtml(),
            root.renderer.html.with_unsafe(),
        ]),
    );
    let t = root.testutil.new_recording_t();
    root.testutil.do_test_case(markdown, root.testutil.MarkdownTestCase {
        no: 1,
        description: "",
        options: root.testutil.empty_options(),
        markdown: "hoge@example.com user@example.com",
        expected: "<p>hoge@example.com <a href=\"mailto:user@example.com\">user@example.com</a></p>",
    }, t);
    t.errors
}

test "TestLinkifyWithEmailRegexp" {
    let errors = test_linkify_with_email_regexp();
    assert.equal(errors, []);
}
