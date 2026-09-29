// Port of goldmark cjk_test.go.
//
// Converted from the Go source by a one-off script: each Go test function
// becomes a helper that returns the recorded failures.

function cjk_escaped_space_failures() -> string[] {
    let t = root.testutil.new_recording_t();
    let markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(),
        root.renderer.html.new(opts = [root.renderer.html.with_xhtml(), root.renderer.html.with_unsafe()]),
    );
    root.testutil.do_test_case(
        markdown,
        root.testutil.MarkdownTestCase {
            no: 1,
            description: "Without spaces around an emphasis started with east asian punctuations, it is not interpreted as an emphasis(as defined in CommonMark spec)",
            options: root.testutil.empty_options(),
            markdown: "太郎は**「こんにちわ」**と言った\nんです",
            expected: "<p>太郎は**「こんにちわ」**と言った\nんです</p>",
        },
        t,
    );
    root.testutil.do_test_case(
        markdown,
        root.testutil.MarkdownTestCase {
            no: 2,
            description: "With spaces around an emphasis started with east asian punctuations, it is interpreted as an emphasis(but remains unnecessary spaces)",
            options: root.testutil.empty_options(),
            markdown: "太郎は **「こんにちわ」** と言った\nんです",
            expected: "<p>太郎は <strong>「こんにちわ」</strong> と言った\nんです</p>",
        },
        t,
    );
    // EscapedSpace
    markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(options = [root.parser.with_escaped_space()]),
        root.renderer.html.new(opts = [root.renderer.html.with_xhtml(), root.renderer.html.with_unsafe(), root.renderer.html.with_line_break_strategy(root.renderer.html.simple_east_asian_line_break_strategy())]),
    );
    root.testutil.do_test_case(
        markdown,
        root.testutil.MarkdownTestCase {
            no: 3,
            description: "With spaces around an emphasis started with east asian punctuations,it is interpreted as an emphasis",
            options: root.testutil.empty_options(),
            markdown: "太郎は\\ **「こんにちわ」**\\ と言った\nんです",
            expected: "<p>太郎は<strong>「こんにちわ」</strong>と言ったんです</p>",
        },
        t,
    );
    // ' ' triggers Linkify extension inline parser.
    // Escaped spaces should not trigger the inline parser.
    markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(options = [root.parser.with_extensions([root.extension.new_linkify_parser()]), root.parser.with_escaped_space()]),
        root.renderer.html.new(opts = [root.renderer.html.with_xhtml(), root.renderer.html.with_unsafe(), root.renderer.html.with_line_break_strategy(root.renderer.html.simple_east_asian_line_break_strategy())]),
    );
    root.testutil.do_test_case(
        markdown,
        root.testutil.MarkdownTestCase {
            no: 4,
            description: "Escaped space and linkfy extension",
            options: root.testutil.empty_options(),
            markdown: "太郎は\\ **「こんにちわ」**\\ と言った\nんです",
            expected: "<p>太郎は<strong>「こんにちわ」</strong>と言ったんです</p>",
        },
        t,
    );
    t.errors
}

test "TestEscapedSpace" {
    assert.equal(cjk_escaped_space_failures(), []);
}

function cjk_east_asian_line_breaks_failures() -> string[] {
    let t = root.testutil.new_recording_t();
    let markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(),
        root.renderer.html.new(opts = [root.renderer.html.with_xhtml(), root.renderer.html.with_unsafe()]),
    );
    root.testutil.do_test_case(
        markdown,
        root.testutil.MarkdownTestCase {
            no: 1,
            description: "Soft line breaks are rendered as a newline, so some asian users will see it as an unnecessary space",
            options: root.testutil.empty_options(),
            markdown: "太郎は\\ **「こんにちわ」**\\ と言った\nんです",
            expected: "<p>太郎は\\ <strong>「こんにちわ」</strong>\\ と言った\nんです</p>",
        },
        t,
    );
    // Enables EastAsianLineBreaks
    markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(options = [root.parser.with_escaped_space()]),
        root.renderer.html.new(opts = [root.renderer.html.with_xhtml(), root.renderer.html.with_unsafe(), root.renderer.html.with_line_break_strategy(root.renderer.html.simple_east_asian_line_break_strategy())]),
    );
    root.testutil.do_test_case(
        markdown,
        root.testutil.MarkdownTestCase {
            no: 2,
            description: "Soft line breaks between east asian wide characters are ignored",
            options: root.testutil.empty_options(),
            markdown: "太郎は\\ **「こんにちわ」**\\ と言った\nんです",
            expected: "<p>太郎は<strong>「こんにちわ」</strong>と言ったんです</p>",
        },
        t,
    );
    root.testutil.do_test_case(
        markdown,
        root.testutil.MarkdownTestCase {
            no: 3,
            description: "Soft line breaks between east asian wide characters(w/ strong) are ignored",
            options: root.testutil.empty_options(),
            markdown: "太郎は\\ **「こんにちわ」**\\ と言った\n**ん**です",
            expected: "<p>太郎は<strong>「こんにちわ」</strong>と言った<strong>ん</strong>です</p>",
        },
        t,
    );
    root.testutil.do_test_case(
        markdown,
        root.testutil.MarkdownTestCase {
            no: 4,
            description: "Soft line breaks between east asian wide characters(w/ link) are ignored",
            options: root.testutil.empty_options(),
            markdown: "太郎は\\ **「こんにちわ」**\\ と言った\n[ん](./test)です",
            expected: "<p>太郎は<strong>「こんにちわ」</strong>と言った<a href=\"./test\">ん</a>です</p>",
        },
        t,
    );
    root.testutil.do_test_case(
        markdown,
        root.testutil.MarkdownTestCase {
            no: 5,
            description: "Soft line breaks between east asian wide characters(w/ leading spaces) are ignored",
            options: root.testutil.empty_options(),
            markdown: "太郎は\\ **「こんにちわ」**\\ と言った\n んです",
            expected: "<p>太郎は<strong>「こんにちわ」</strong>と言ったんです</p>",
        },
        t,
    );
    root.testutil.do_test_case(
        markdown,
        root.testutil.MarkdownTestCase {
            no: 6,
            description: "Soft line breaks between east asian wide characters(w/ codespan) are ignored",
            options: root.testutil.empty_options(),
            markdown: "太郎は\\ **「こんにちわ」**\\ と言った\n`ん`です",
            expected: "<p>太郎は<strong>「こんにちわ」</strong>と言った<code>ん</code>です</p>",
        },
        t,
    );
    root.testutil.do_test_case(
        markdown,
        root.testutil.MarkdownTestCase {
            no: 7,
            description: "Soft line breaks between east asian wide characters(w/ codespans) are ignored",
            options: root.testutil.empty_options(),
            markdown: "太郎は\\ **「こんにちわ」**\\ と言a`た`\n`ん`です",
            expected: "<p>太郎は<strong>「こんにちわ」</strong>と言a<code>た</code><code>ん</code>です</p>",
        },
        t,
    );
    root.testutil.do_test_case(
        markdown,
        root.testutil.MarkdownTestCase {
            no: 8,
            description: "Soft line breaks between ascii characters(w/ codespan) are not ignored",
            options: root.testutil.empty_options(),
            markdown: "Access is enforced in\n`internal/app/server.go`.",
            expected: "<p>Access is enforced in\n<code>internal/app/server.go</code>.</p>",
        },
        t,
    );
    root.testutil.do_test_case(
        markdown,
        root.testutil.MarkdownTestCase {
            no: 9,
            description: "Soft line breaks between east asian wide characters(w/ numeric references) are ignored",
            options: root.testutil.empty_options(),
            markdown: "&#x65e5;\n&#x672c;",
            expected: "<p>日本</p>",
        },
        t,
    );
    root.testutil.do_test_case(
        markdown,
        root.testutil.MarkdownTestCase {
            no: 10,
            description: "Soft line breaks between western characters are rendered as a newline",
            options: root.testutil.empty_options(),
            markdown: "太郎は\\ **「こんにちわ」**\\ と言ったa\nbんです",
            expected: "<p>太郎は<strong>「こんにちわ」</strong>と言ったa\nbんです</p>",
        },
        t,
    );
    root.testutil.do_test_case(
        markdown,
        root.testutil.MarkdownTestCase {
            no: 11,
            description: "Soft line breaks between a western character and an east asian wide character are rendered as a newline",
            options: root.testutil.empty_options(),
            markdown: "太郎は\\ **「こんにちわ」**\\ と言ったa\nんです",
            expected: "<p>太郎は<strong>「こんにちわ」</strong>と言ったa\nんです</p>",
        },
        t,
    );
    root.testutil.do_test_case(
        markdown,
        root.testutil.MarkdownTestCase {
            no: 12,
            description: "Soft line breaks between an east asian wide character and a western character are rendered as a newline",
            options: root.testutil.empty_options(),
            markdown: "太郎は\\ **「こんにちわ」**\\ と言った\nbんです",
            expected: "<p>太郎は<strong>「こんにちわ」</strong>と言った\nbんです</p>",
        },
        t,
    );
    // WithHardWraps take precedence over WithEastAsianLineBreaks
    markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(options = [root.parser.with_escaped_space()]),
        root.renderer.html.new(opts = [root.renderer.html.with_xhtml(), root.renderer.html.with_unsafe(), root.renderer.html.with_hard_wraps(), root.renderer.html.with_line_break_strategy(root.renderer.html.simple_east_asian_line_break_strategy())]),
    );
    root.testutil.do_test_case(
        markdown,
        root.testutil.MarkdownTestCase {
            no: 13,
            description: "WithHardWraps take precedence over WithEastAsianLineBreaks",
            options: root.testutil.empty_options(),
            markdown: "太郎は\\ **「こんにちわ」**\\ と言った\nんです",
            expected: "<p>太郎は<strong>「こんにちわ」</strong>と言った<br />\nんです</p>",
        },
        t,
    );
    markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(options = [root.parser.with_extensions([root.extension.new_linkify_parser()])]),
        root.renderer.html.new(opts = [root.renderer.html.with_xhtml(), root.renderer.html.with_unsafe(), root.renderer.html.with_line_break_strategy(root.renderer.html.simple_east_asian_line_break_strategy())]),
    );
    root.testutil.do_test_case(
        markdown,
        root.testutil.MarkdownTestCase {
            no: 14,
            description: "WithEastAsianLineBreaks and linkfy extension",
            options: root.testutil.empty_options(),
            markdown: "太郎は\\ **「こんにちわ」**\\ と言った\r\nんです",
            expected: "<p>太郎は\\ <strong>「こんにちわ」</strong>\\ と言ったんです</p>",
        },
        t,
    );
    root.testutil.do_test_case(
        markdown,
        root.testutil.MarkdownTestCase {
            no: 15,
            description: "Soft line breaks between east asian wide characters or punctuations are ignored",
            options: root.testutil.empty_options(),
            markdown: "太郎は\\ **「こんにちわ」**\\ と、\r\n言った\r\nんです",
            expected: "<p>太郎は\\ <strong>「こんにちわ」</strong>\\ と、言ったんです</p>",
        },
        t,
    );
    root.testutil.do_test_case(
        markdown,
        root.testutil.MarkdownTestCase {
            no: 16,
            description: "Soft line breaks between an east asian wide character and a western character are ignored",
            options: root.testutil.empty_options(),
            markdown: "私はプログラマーです。\n東京の会社に勤めています。\nGoでWebアプリケーションを開発しています。",
            expected: "<p>私はプログラマーです。東京の会社に勤めています。\nGoでWebアプリケーションを開発しています。</p>",
        },
        t,
    );
    // Tests with EastAsianLineBreaksCSS3Draft
    markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(),
        root.renderer.html.new(opts = [root.renderer.html.with_xhtml(), root.renderer.html.with_unsafe(), root.renderer.html.with_line_break_strategy(root.renderer.html.css_text3_line_break_strategy())]),
    );
    root.testutil.do_test_case(
        markdown,
        root.testutil.MarkdownTestCase {
            no: 17,
            description: "Soft line breaks between a western character and an east asian wide character are ignored",
            options: root.testutil.empty_options(),
            markdown: "太郎は\\ **「こんにちわ」**\\ と言ったa\nんです",
            expected: "<p>太郎は\\ <strong>「こんにちわ」</strong>\\ と言ったaんです</p>",
        },
        t,
    );
    root.testutil.do_test_case(
        markdown,
        root.testutil.MarkdownTestCase {
            no: 18,
            description: "Soft line breaks between an east asian wide character and a western character are ignored",
            options: root.testutil.empty_options(),
            markdown: "太郎は\\ **「こんにちわ」**\\ と言った\nbんです",
            expected: "<p>太郎は\\ <strong>「こんにちわ」</strong>\\ と言ったbんです</p>",
        },
        t,
    );
    root.testutil.do_test_case(
        markdown,
        root.testutil.MarkdownTestCase {
            no: 19,
            description: "Soft line breaks between an east asian wide character and a western character are ignored",
            options: root.testutil.empty_options(),
            markdown: "私はプログラマーです。\n東京の会社に勤めています。\nGoでWebアプリケーションを開発しています。",
            expected: "<p>私はプログラマーです。東京の会社に勤めています。GoでWebアプリケーションを開発しています。</p>",
        },
        t,
    );
    t.errors
}

test "TestEastAsianLineBreaks" {
    assert.equal(cjk_east_asian_line_breaks_failures(), []);
}
