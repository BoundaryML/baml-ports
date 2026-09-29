// Port of goldmark extension/footnote_test.go.

function test_footnote() -> string[] {
    let markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(options = [
            root.parser.with_extensions([new_footnote_parser()]),
        ]),
        root.renderer.html.new(opts = [
            root.renderer.html.with_unsafe(),
            root.renderer.html.with_extensions([new_footnote_html_renderer()]),
        ]),
    );
    let t = root.testutil.new_recording_t();
    root.testutil.do_test_case_file(markdown, "extension/testdata/footnote.txt", t, no = root.testutil.parse_cli_case_arg());
    t.errors
}

test "TestFootnote" {
    let errors = test_footnote();
    assert.equal(errors, []);
}

/// Go's test-local `footnoteID` AST transformer.
class FootnoteID {
    implements root.parser.ASTTransformer {
        function transform(self, node: root.ast.Document, reader: root.text.Reader, pc: root.parser.Context) -> void {
            node.metadata()["footnote-prefix"] = "article12-";
        }
    }
}

function footnote_options_markdown() -> string {
    // BAML backtick strings drop the trailing newline; Go's literal has one.
    `That's some text with a footnote.[^1]

Same footnote.[^1]

Another one.[^2]

[^1]: And that's the footnote.
[^2]: Another footnote.` + "\n"
}

function footnote_options_expected() -> string {
    `<p>That's some text with a footnote.<sup id="article12-fnref:1"><a href="#article12-fn:1" class="link-class" title="link-title-2-1" role="doc-noteref">1</a></sup></p>
<p>Same footnote.<sup id="article12-fnref1:1"><a href="#article12-fn:1" class="link-class" title="link-title-2-1" role="doc-noteref">1</a></sup></p>
<p>Another one.<sup id="article12-fnref:2"><a href="#article12-fn:2" class="link-class" title="link-title-1-2" role="doc-noteref">2</a></sup></p>
<div class="footnotes" role="doc-endnotes">
<hr>
<ol>
<li id="article12-fn:1">
<p>And that's the footnote.&#160;<a href="#article12-fnref:1" class="backlink-class" title="backlink-title" role="doc-backlink">^</a>&#160;<a href="#article12-fnref1:1" class="backlink-class" title="backlink-title" role="doc-backlink">^</a></p>
</li>
<li id="article12-fn:2">
<p>Another footnote.&#160;<a href="#article12-fnref:2" class="backlink-class" title="backlink-title" role="doc-backlink">^</a></p>
</li>
</ol>
</div>`
}

function footnote_id_prefix_from_metadata(n: root.ast.Node) -> uint8array? {
    let doc = n.owner_document();
    if (doc == null) {
        return null;
    }
    match (doc.metadata().get("footnote-prefix")) {
        let s: string => root.util.string_to_bytes(s),
        _ => null,
    }
}

function test_footnote_options() -> string[] {
    let markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(options = [
            root.parser.with_extensions([new_footnote_parser()]),
        ]),
        root.renderer.html.new(opts = [
            root.renderer.html.with_unsafe(),
            root.renderer.html.with_extensions([new_footnote_html_renderer(opts = [
                with_id_prefix("article12-"),
                with_link_class("link-class"),
                with_backlink_class("backlink-class"),
                with_link_title("link-title-%%-^^"),
                with_backlink_title("backlink-title"),
                with_backlink_html("^"),
            ])]),
        ]),
    );

    let t = root.testutil.new_recording_t();
    root.testutil.do_test_case(
        markdown,
        root.testutil.MarkdownTestCase {
            no: 1,
            description: "Footnote with options",
            options: root.testutil.empty_options(),
            markdown: footnote_options_markdown(),
            expected: footnote_options_expected(),
        },
        t,
    );

    let prefix_fn: FootnoteIDPrefixFunction = footnote_id_prefix_from_metadata;
    let transformer: root.parser.ASTTransformer = FootnoteID {};
    markdown = root.testutil.new_markdown_to_string_func(
        root.parser.new(options = [
            root.parser.with_ast_transformers([
                root.util.prioritized(transformer, 100),
            ]),
            root.parser.with_extensions([new_footnote_parser()]),
        ]),
        root.renderer.html.new(opts = [
            root.renderer.html.with_unsafe(),
            root.renderer.html.with_extensions([new_footnote_html_renderer(opts = [
                with_id_prefix_function(prefix_fn),
                with_link_class("link-class"),
                with_backlink_class("backlink-class"),
                with_link_title("link-title-%%-^^"),
                with_backlink_title("backlink-title"),
                with_backlink_html("^"),
            ])]),
        ]),
    );

    root.testutil.do_test_case(
        markdown,
        root.testutil.MarkdownTestCase {
            no: 2,
            description: "Footnote with an id prefix function",
            options: root.testutil.empty_options(),
            markdown: footnote_options_markdown(),
            expected: footnote_options_expected(),
        },
        t,
    );
    t.errors
}

test "TestFootnoteOptions" {
    let errors = test_footnote_options();
    assert.equal(errors, []);
}
