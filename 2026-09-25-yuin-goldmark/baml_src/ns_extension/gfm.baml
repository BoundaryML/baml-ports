// Port of goldmark extension/gfm.go.

/// Go's unexported `gfmParserExtension`.
class GFMParserExtension {
    implements root.parser.Extension {
        function parser_options(self, c: root.parser.Config) -> root.parser.Option[] {
            let opts: root.parser.Option[] = [];
            opts = opts.concat(new_linkify_parser().parser_options(c));
            opts = opts.concat(new_table_parser().parser_options(c));
            opts = opts.concat(new_strikethrough_parser().parser_options(c));
            opts = opts.concat(new_task_list_item_parser().parser_options(c));
            opts
        }
    }
}

/// NewGFMParser returns a new parser extension that enables GitHub Flavored
/// Markdown parsing (linkify, table, strikethrough and task list).
function new_gfm_parser() -> root.parser.Extension {
    GFMParserExtension {}
}

/// Go's unexported `gfmHTMLRendererExtension`.
class GFMHTMLRendererExtension {
    implements root.renderer.Extension<root.renderer.html.Config> {
        function renderer_options(self, c: root.renderer.html.Config) -> root.renderer.html.Option[] {
            let opts: root.renderer.html.Option[] = [];
            opts = opts.concat(new_table_html_renderer().renderer_options(c));
            opts = opts.concat(new_strikethrough_html_renderer().renderer_options(c));
            opts = opts.concat(new_task_list_item_html_renderer().renderer_options(c));
            opts
        }
    }
}

/// NewGFMHTMLRenderer returns a new HTML renderer extension for GitHub Flavored
/// Markdown elements.
function new_gfm_html_renderer() -> root.renderer.html.Extension {
    GFMHTMLRendererExtension {}
}

/// GFMParser is a parser extension that enables GitHub Flavored Markdown.
/// (Go: package-level var.)
function gfm_parser() -> root.parser.Extension {
    new_gfm_parser()
}

/// GFMHTMLRenderer is an HTML renderer extension for GitHub Flavored Markdown.
/// (Go: package-level var.)
function gfm_html_renderer() -> root.renderer.html.Extension {
    new_gfm_html_renderer()
}
