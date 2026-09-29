// Port of goldmark renderer/html/html.go.
//
// Package html implements renderer that outputs HTMLs.
//
// Porting notes: see ns_renderer/renderer.baml for the generic-renderer
// mapping. Go's package-level attribute filters (`GlobalAttributeFilter`,
// ...) and line break strategies are zero-argument functions.

// Type aliases {{{

/// Renderer is a renderer that renders AST nodes as (X)HTML.
type Renderer = root.renderer.Renderer

/// NodeRenderer is a renderer that renders AST nodes as (X)HTML.
type NodeRenderer = root.renderer.NodeRenderer

/// NodeRendererDecorator is a decorator that decorates NodeRenderer.
type NodeRendererDecorator = root.renderer.NodeRendererDecorator

/// NodeRendererFunc adapts f into a NodeRenderer that renders AST nodes as (X)HTML.
function node_renderer_func(f: root.renderer.NodeRendererFuncType) -> NodeRenderer {
    root.renderer.node_renderer_func(f)
}

/// Extension is an extension that extends HTML based renderers.
type Extension = root.renderer.Extension<Config>

/// Option is a functional option for HTML based renderers.
type Option = root.renderer.Option<Config>

/// WithNodeRenderers sets a node renderer for the given node kind.
function with_node_renderers(node_renderers: map<string, NodeRenderer>) -> Option {
    root.renderer.with_node_renderers<Config>(node_renderers)
}

/// WithNodeRenderer sets a node renderer for the given node kind.
function with_node_renderer(kind: root.ast.NodeKind, node_renderer: NodeRenderer) -> Option {
    root.renderer.with_node_renderer<Config>(kind, node_renderer)
}

/// WithNodeRendererDecorators sets a node renderer decorator for the given node kind.
///
/// If a decorator is already set for a node kind, the new decorator will be applied to the existing one.
function with_node_renderer_decorators(decorators: map<string, NodeRendererDecorator>) -> Option {
    root.renderer.with_node_renderer_decorators<Config>(decorators)
}

/// WithNodeRendererDecorator sets a node renderer decorator for the given node kind.
///
/// If a decorator is already set for a node kind, the new decorator will be applied to the existing one.
function with_node_renderer_decorator(kind: root.ast.NodeKind, decorator: NodeRendererDecorator) -> Option {
    root.renderer.with_node_renderer_decorator<Config>(kind, decorator)
}

/// WithExtensions adds extensions.
function with_extensions(extensions: Extension[]) -> Option {
    root.renderer.with_extensions<Config>(extensions)
}

// }}} Type aliases

/// IsInTightBlockFunc determines whether a paragraph node is inside a tight block
/// and should be rendered without <p> tags.
type IsInTightBlockFunc = (n: root.ast.Node) -> bool throws never

/// IsInTightBlock returns true if the paragraph is a direct child of a
/// ListItem whose parent List is tight.
function is_in_tight_block(n: root.ast.Node) -> bool {
    let parent = n.parent();
    if (parent == null) {
        return false;
    }
    let gp = parent.parent();
    if (gp == null) {
        return false;
    }
    match (gp) {
        let list: root.ast.List => list.is_tight,
        _ => false,
    }
}

/// A ParagraphConfig struct has configurations for paragraph rendering.
class ParagraphConfig {
    /// IsInTightBlockFunc determines whether a paragraph should be rendered
    /// without <p> tags because it is inside a tight block.
    is_in_tight_block_func: IsInTightBlockFunc,
}

/// A Config struct has configurations for the HTML based renderers.
class Config {
    // Go: embedded `renderer.Config[io.Writer, Config]`.
    config: root.renderer.Config,
    hard_wraps: bool,
    line_break_strategy: LineBreakStrategy?,
    xhtml: bool,
    unsafe: bool,
    paragraph: ParagraphConfig,

    /// Go copies the Config struct by value (`thisConfig := *cfg`).
    function copy(self) -> Config {
        Config {
            config: self.config,
            hard_wraps: self.hard_wraps,
            line_break_strategy: self.line_break_strategy,
            xhtml: self.xhtml,
            unsafe: self.unsafe,
            paragraph: ParagraphConfig { is_in_tight_block_func: self.paragraph.is_in_tight_block_func },
        }
    }

    implements root.renderer.FormatConfig {
        function renderer_config(self) -> root.renderer.Config {
            self.config
        }
    }
}

/// Default returns a Config with default values.
function default_config() -> Config {
    Config {
        config: root.renderer.new_config(),
        hard_wraps: false,
        line_break_strategy: null,
        xhtml: false,
        unsafe: false,
        paragraph: ParagraphConfig { is_in_tight_block_func: is_in_tight_block },
    }
}

/// WithHardWraps is a functional option that indicates whether softline breaks
/// should be rendered as '<br>'.
function with_hard_wraps() -> Option {
    root.renderer.new_option_func<Config>((c: Config) -> void {
        c.hard_wraps = true;
    })
}

/// LineBreakStrategy is an interface that defines a strategy for determining whether a line break
/// should be rendered as a new line.
interface LineBreakStrategy {
    /// SoftLineBreak returns true if a soft line break should be rendered as a new line.
    function soft_line_break(self, this_last_rune: int, sibling_first_rune: int) -> bool throws never
}

/// WithLineBreakStrategy is a functional option that sets a custom line break strategy.
function with_line_break_strategy(strategy: LineBreakStrategy) -> Option {
    root.renderer.new_option_func<Config>((c: Config) -> void {
        c.line_break_strategy = strategy;
    })
}

class SimpleEastAsianLineBreakStrategyImpl {
    implements LineBreakStrategy {
        function soft_line_break(self, this_last_rune: int, sibling_first_rune: int) -> bool {
            !root.util.is_east_asian_wide_rune(this_last_rune) || !root.util.is_east_asian_wide_rune(sibling_first_rune)
        }
    }
}

/// SimpleEastAsianLineBreakStrategy follows east_asian_line_breaks in Pandoc.
function simple_east_asian_line_break_strategy() -> LineBreakStrategy {
    SimpleEastAsianLineBreakStrategyImpl {}
}

class CSSText3LineBreakStrategyImpl {
    implements LineBreakStrategy {
        function soft_line_break(self, this_last_rune: int, sibling_first_rune: int) -> bool {
            // Implements CSS text level3 Segment Break Transformation Rules with some enhancements.
            // References:
            //   - https://www.w3.org/TR/2020/WD-css-text-3-20200429/#line-break-transform
            //   - https://github.com/w3c/csswg-drafts/issues/5086

            // Rule1:
            //   If the character immediately before or immediately after the segment break is
            //   the zero-width space character (U+200B), then the break is removed, leaving behind the zero-width space.
            if (this_last_rune == 0x200B || sibling_first_rune == 0x200B) {
                return false;
            }

            // Rule2:
            //   Otherwise, if the East Asian Width property of both the character before and after the segment break is
            //   F, W, or H (not A), and neither side is Hangul, then the segment break is removed.
            let a = root.util.east_asian_width(this_last_rune);
            let b = root.util.east_asian_width(sibling_first_rune);
            if ((a == "F" || a == "W" || a == "H") && (b == "F" || b == "W" || b == "H")) {
                return root.util.is_unicode_hangul(this_last_rune) || root.util.is_unicode_hangul(sibling_first_rune);
            }

            // Rule3:
            //   Otherwise, if either the character before or after the segment break belongs to
            //   the space-discarding character set and it is a Unicode Punctuation (P*) or U+3000,
            //   then the segment break is removed.
            if (root.util.is_space_discarding_unicode_rune(this_last_rune) || root.util.is_unicode_punct(this_last_rune) || this_last_rune == 0x3000 || root.util.is_space_discarding_unicode_rune(sibling_first_rune) || root.util.is_unicode_punct(sibling_first_rune) || sibling_first_rune == 0x3000) {
                return false;
            }

            // Rule4:
            //   Otherwise, the segment break is converted to a space (U+0020).
            true
        }
    }
}

/// CSSText3LineBreakStrategy follows CSS Text Module Level 3 with some enhancements for CJK.
function css_text3_line_break_strategy() -> LineBreakStrategy {
    CSSText3LineBreakStrategyImpl {}
}

/// WithXHTML is a functional option indicates that nodes should be rendered in
/// xhtml instead of HTML5.
function with_xhtml() -> Option {
    root.renderer.new_option_func<Config>((c: Config) -> void {
        c.xhtml = true;
    })
}

/// WithUnsafe is a functional option that renders dangerous contents
/// (raw htmls and potentially dangerous links) as it is.
function with_unsafe() -> Option {
    root.renderer.new_option_func<Config>((c: Config) -> void {
        c.unsafe = true;
    })
}

/// WithIsInTightBlockFunc is a functional option that sets a custom function to
/// determine whether a paragraph node is inside a tight block and should be
/// rendered without <p> tags.
function with_is_in_tight_block_func(f: IsInTightBlockFunc) -> Option {
    root.renderer.new_option_func<Config>((c: Config) -> void {
        c.paragraph.is_in_tight_block_func = f;
    })
}

function html_writer_key() -> root.renderer.ContextKey {
    "html.htmlWriter"
}

function text_writer_key() -> root.renderer.ContextKey {
    "html.textWriter"
}

function link_url_writer_key() -> root.renderer.ContextKey {
    "html.linkURLWriter"
}

/// Go's unexported `htmlRenderer` (embeds `*renderer.Helper[io.Writer, Config]`).
class HTMLRenderer {
    helper: root.renderer.Helper<Config>,

    implements root.renderer.Renderer {
        /// Render renders the given AST node to the given writer.
        function render(self, w: root.util.BufWriter, source: uint8array, n: root.ast.Node, opts: root.renderer.RenderOption[]) -> void {
            self.helper.render(w, source, n, opts = opts);
        }

        /// RenderStringSource renders the given AST node to the given writer.
        function render_string_source(self, w: root.util.BufWriter, source: string, n: root.ast.Node, opts: root.renderer.RenderOption[]) -> void {
            self.render(w, source.to_utf8(), n, opts);
        }
    }
}

/// New returns a new Renderer with given options.
function new(opts: Option[] = []) -> Renderer {
    let cm = new_common_mark();
    let all_opts: Option[] = [with_extensions([cm])];
    for (let o in opts) {
        all_opts.push(o);
    }
    let hb = root.renderer.new_helper_builder<Config>(default_config());
    let helper = hb.add_options(all_opts).set_on_before_render(
        (w: root.util.BufWriter, source: uint8array, n: root.ast.Node, rc: root.renderer.Context) -> void {
            let hw: root.util.BufWriter = HTMLWriter { w: w };
            let tw: root.util.BufWriter = TextWriter { w: w };
            let lw: root.util.BufWriter = LinkURLWriter { w: w };
            rc.set(html_writer_key(), hw);
            rc.set(text_writer_key(), tw);
            rc.set(link_url_writer_key(), lw);
        },
    ).build();
    HTMLRenderer { helper: helper }
}

function context_writer(rc: root.renderer.Context, key: root.renderer.ContextKey, what: string) -> root.util.BufWriter {
    match (rc.get(key)) {
        let w: root.util.BufWriter => w,
        _ => {
            baml.sys.panic(what + " not found in context");
            root.util.new_buffer()
        }
    }
}

/// ContextHTMLWriter returns a writer that writes HTML content.
function context_html_writer(rc: root.renderer.Context) -> root.util.BufWriter {
    context_writer(rc, html_writer_key(), "HTMLWriter")
}

/// ContextTextWriter returns a writer that writes text content.
function context_text_writer(rc: root.renderer.Context) -> root.util.BufWriter {
    context_writer(rc, text_writer_key(), "TextWriter")
}

/// ContextLinkURLWriter returns a writer that writes link URL content.
function context_link_url_writer(rc: root.renderer.Context) -> root.util.BufWriter {
    context_writer(rc, link_url_writer_key(), "LinkURLWriter")
}

/// Go's unexported `commonMark` HTML renderer extension.
class CommonMarkRenderer {
    opts: Option[],
    config: Config?,

    function cfg(self) -> Config {
        self.config ?? default_config()
    }

    function render_document(self, w: root.util.BufWriter, source: uint8array, node: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus {
        root.ast.WalkStatus.WalkContinue
    }

    function render_heading(self, w: root.util.BufWriter, source: uint8array, node: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus {
        let level = match (node) {
            let h: root.ast.Heading => h.level,
            _ => 1,
        };
        if (entering) {
            w.write_string("<h");
            w.write_byte(48 + level);
            if (node.attributes() != null) {
                render_attributes(w, source, node, heading_attribute_filter(), rc);
            }
            w.write_byte(62);
        } else {
            w.write_string("</h");
            w.write_byte(48 + level);
            w.write_string(">\n");
        }
        root.ast.WalkStatus.WalkContinue
    }

    function render_blockquote(self, w: root.util.BufWriter, source: uint8array, n: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus {
        if (entering) {
            if (n.attributes() != null) {
                w.write_string("<blockquote");
                render_attributes(w, source, n, blockquote_attribute_filter(), rc);
                w.write_byte(62);
            } else {
                w.write_string("<blockquote>\n");
            }
        } else {
            w.write_string("</blockquote>\n");
        }
        root.ast.WalkStatus.WalkContinue
    }

    function render_code_block(self, w: root.util.BufWriter, source: uint8array, node: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus {
        let n = match (node) {
            let cb: root.ast.CodeBlock => cb,
            _ => {
                return root.ast.WalkStatus.WalkContinue;
            }
        };
        if (entering) {
            let tw = context_text_writer(rc);
            w.write_string("<pre><code");
            let language = n.language(source);
            if (language != null) {
                w.write_string(" class=\"language-");
                tw.write_string(language);
                w.write_byte(34);
            }
            w.write_byte(62);
            n.value.write_to(tw, source);
        } else {
            w.write_string("</code></pre>\n");
        }
        root.ast.WalkStatus.WalkContinue
    }

    function render_html_block(self, w: root.util.BufWriter, source: uint8array, node: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus {
        let hw = context_html_writer(rc);
        if (entering) {
            match (node) {
                let n: root.ast.HTMLBlock => {
                    if (self.cfg().unsafe) {
                        n.value.write_to(hw, source);
                    } else {
                        w.write_string("<!-- raw HTML omitted -->\n");
                    }
                }
                _ => {}
            }
        }
        root.ast.WalkStatus.WalkContinue
    }

    function render_list(self, w: root.util.BufWriter, source: uint8array, node: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus {
        let n = match (node) {
            let l: root.ast.List => l,
            _ => {
                return root.ast.WalkStatus.WalkContinue;
            }
        };
        let tag = if (n.is_ordered()) { "ol" } else { "ul" };
        if (entering) {
            w.write_byte(60);
            w.write_string(tag);
            if (n.is_ordered() && n.start != 1) {
                w.write_string(" start=\"");
                w.write_string(n.start.to_string());
                w.write_byte(34);
            }
            if (n.attributes() != null) {
                render_attributes(w, source, n, list_attribute_filter(), rc);
            }
            w.write_string(">\n");
        } else {
            w.write_string("</");
            w.write_string(tag);
            w.write_string(">\n");
        }
        root.ast.WalkStatus.WalkContinue
    }

    function render_list_item(self, w: root.util.BufWriter, source: uint8array, n: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus {
        if (entering) {
            if (n.attributes() != null) {
                w.write_string("<li");
                render_attributes(w, source, n, list_item_attribute_filter(), rc);
                w.write_byte(62);
            } else {
                w.write_string("<li>");
            }
            let fc = n.first_child();
            if (fc != null) {
                let tight_para = match (fc) {
                    let paragraph: root.ast.Paragraph => {
                        let f = self.cfg().paragraph.is_in_tight_block_func;
                        f(paragraph)
                    }
                    _ => false,
                };
                if (!tight_para) {
                    w.write_byte(10);
                }
            }
        } else {
            w.write_string("</li>\n");
        }
        root.ast.WalkStatus.WalkContinue
    }

    function render_paragraph(self, w: root.util.BufWriter, source: uint8array, n: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus {
        let f = self.cfg().paragraph.is_in_tight_block_func;
        if (f(n)) {
            if (!entering && n.next_sibling() != null && n.first_child() != null) {
                w.write_byte(10);
            }
            return root.ast.WalkStatus.WalkContinue;
        }
        if (entering) {
            if (n.attributes() != null) {
                w.write_string("<p");
                render_attributes(w, source, n, paragraph_attribute_filter(), rc);
                w.write_byte(62);
            } else {
                w.write_string("<p>");
            }
        } else {
            w.write_string("</p>\n");
        }
        root.ast.WalkStatus.WalkContinue
    }

    function render_thematic_break(self, w: root.util.BufWriter, source: uint8array, n: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus {
        if (!entering) {
            return root.ast.WalkStatus.WalkContinue;
        }
        w.write_string("<hr");
        if (n.attributes() != null) {
            render_attributes(w, source, n, thematic_attribute_filter(), rc);
        }
        if (self.cfg().xhtml) {
            w.write_string(" />\n");
        } else {
            w.write_string(">\n");
        }
        root.ast.WalkStatus.WalkContinue
    }

    function render_auto_link(self, w: root.util.BufWriter, source: uint8array, node: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus {
        let n = match (node) {
            let a: root.ast.AutoLink => a,
            _ => {
                return root.ast.WalkStatus.WalkContinue;
            }
        };
        if (!entering) {
            return root.ast.WalkStatus.WalkContinue;
        }
        w.write_string("<a href=\"");
        let dest = n.destination.value(source);
        if (self.cfg().unsafe || !is_dangerous_url(dest)) {
            context_link_url_writer(rc).write_string(dest);
        }
        if (n.attributes() != null) {
            w.write_byte(34);
            render_attributes(w, source, n, link_attribute_filter(), rc);
            w.write_byte(62);
        } else {
            w.write_string("\">");
        }
        n.label.write_to(context_text_writer(rc), source);
        w.write_string("</a>");
        root.ast.WalkStatus.WalkContinue
    }

    function render_code_span(self, w: root.util.BufWriter, source: uint8array, n: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus {
        let tw = context_text_writer(rc);
        if (entering) {
            if (n.attributes() != null) {
                w.write_string("<code");
                render_attributes(w, source, n, code_attribute_filter(), rc);
                w.write_byte(62);
            } else {
                w.write_string("<code>");
            }
            match (n) {
                let cs: root.ast.CodeSpan => {
                    cs.value.write_to(tw, source);
                }
                _ => {}
            }
            return root.ast.WalkStatus.WalkSkipChildren;
        }
        w.write_string("</code>");
        root.ast.WalkStatus.WalkContinue
    }

    function render_emphasis(self, w: root.util.BufWriter, source: uint8array, node: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus {
        if (entering) {
            w.write_byte(60);
            w.write_string("em");
            if (node.attributes() != null) {
                render_attributes(w, source, node, emphasis_attribute_filter(), rc);
            }
            w.write_byte(62);
        } else {
            w.write_string("</em>");
        }
        root.ast.WalkStatus.WalkContinue
    }

    function render_strong(self, w: root.util.BufWriter, source: uint8array, node: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus {
        if (entering) {
            w.write_byte(60);
            w.write_string("strong");
            if (node.attributes() != null) {
                render_attributes(w, source, node, strong_attribute_filter(), rc);
            }
            w.write_byte(62);
        } else {
            w.write_string("</strong>");
        }
        root.ast.WalkStatus.WalkContinue
    }

    function render_link(self, w: root.util.BufWriter, source: uint8array, node: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus {
        let n = match (node) {
            let l: root.ast.Link => l,
            _ => {
                return root.ast.WalkStatus.WalkContinue;
            }
        };
        if (entering) {
            w.write_string("<a href=\"");
            let dest = n.destination.value(source);
            if (self.cfg().unsafe || !is_dangerous_url(dest)) {
                context_link_url_writer(rc).write_string(dest);
            }
            w.write_byte(34);
            if (!n.title.is_empty()) {
                w.write_string(" title=\"");
                n.title.write_to(context_text_writer(rc), source);
                w.write_byte(34);
            }
            if (n.attributes() != null) {
                render_attributes(w, source, n, link_attribute_filter(), rc);
            }
            w.write_byte(62);
        } else {
            w.write_string("</a>");
        }
        root.ast.WalkStatus.WalkContinue
    }

    function render_image(self, w: root.util.BufWriter, source: uint8array, node: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus {
        if (!entering) {
            return root.ast.WalkStatus.WalkContinue;
        }
        let n = match (node) {
            let i: root.ast.Image => i,
            _ => {
                return root.ast.WalkStatus.WalkContinue;
            }
        };
        w.write_string("<img src=\"");
        let dest = n.destination.value(source);
        if (self.cfg().unsafe || !is_dangerous_url(dest)) {
            context_link_url_writer(rc).write_string(dest);
        }
        w.write_string("\" alt=\"");
        self.render_texts(w, source, n, rc);
        w.write_byte(34);
        if (!n.title.is_empty()) {
            w.write_string(" title=\"");
            n.title.write_to(context_text_writer(rc), source);
            w.write_byte(34);
        }
        if (n.attributes() != null) {
            render_attributes(w, source, n, image_attribute_filter(), rc);
        }
        if (self.cfg().xhtml) {
            w.write_string(" />");
        } else {
            w.write_string(">");
        }
        root.ast.WalkStatus.WalkSkipChildren
    }

    function render_raw_html(self, w: root.util.BufWriter, source: uint8array, node: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus {
        if (!entering) {
            return root.ast.WalkStatus.WalkSkipChildren;
        }
        if (self.cfg().unsafe) {
            match (node) {
                let n: root.ast.RawHTML => {
                    let hw = context_html_writer(rc);
                    n.value.write_to(hw, source);
                }
                _ => {}
            }
            return root.ast.WalkStatus.WalkSkipChildren;
        }
        w.write_string("<!-- raw HTML omitted -->");
        root.ast.WalkStatus.WalkSkipChildren
    }

    function render_text(self, w: root.util.BufWriter, source: uint8array, node: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus {
        if (!entering) {
            return root.ast.WalkStatus.WalkContinue;
        }
        let tw = context_text_writer(rc);
        let n = match (node) {
            let t: root.ast.Text => t,
            _ => {
                return root.ast.WalkStatus.WalkContinue;
            }
        };
        let config = self.cfg();
        if (n.hard_line_break() || (n.soft_line_break() && config.hard_wraps)) {
            n.value.write_to(tw, source);
            if (config.xhtml) {
                w.write_string("<br />\n");
            } else {
                w.write_string("<br>\n");
            }
        } else if (n.soft_line_break()) {
            let lbs = config.line_break_strategy;
            if (lbs != null) {
                let sv = n.value.value(source);
                tw.write_string(sv);

                let last = 0;
                // fast path: avoid double-decoding
                let b = sv.to_utf8();
                let i = b.length() - 1;
                while (i >= 0 && root.util.is_space(b[i])) {
                    i -= 1;
                }
                if (i >= 0) {
                    last = root.util.to_rune(b, i);
                }
                // slow path
                if (last == 0) {
                    last = last_rune(n, source) ?? 0;
                }

                // firstRune is optimzed to avoid decoding the whole string of the next sibling node.
                let first = first_rune(n.next_sibling(), source) ?? 0;
                if (lbs.soft_line_break(last, first)) {
                    w.write_byte(10);
                }
            } else {
                n.value.write_to(tw, source);
                w.write_byte(10);
            }
        } else {
            n.value.write_to(tw, source);
        }
        root.ast.WalkStatus.WalkContinue
    }

    function render_texts(self, w: root.util.BufWriter, source: uint8array, n: root.ast.Node, rc: root.renderer.Context) -> void {
        let c = n.first_child();
        while (c != null) {
            match (c) {
                let t: root.ast.Text => {
                    self.render_text(w, source, t, true, rc);
                }
                _ => {
                    self.render_texts(w, source, c, rc);
                }
            }
            c = c.next_sibling();
        }
    }

    implements root.renderer.Extension<Config> {
        function renderer_options(self, cfg0: Config) -> Option[] {
            let cfg = cfg0;
            if (self.opts.length() != 0) {
                let this_config = cfg0.copy();
                for (let opt in self.opts) {
                    opt.set_format_option(this_config);
                }
                cfg = this_config;
            }
            self.config = cfg;
            let noop = node_renderer_func((w: root.util.BufWriter, source: uint8array, n: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus {
                root.ast.WalkStatus.WalkSkipChildren
            });

            // BAML: bound methods are bound to locals first (see renderer.baml).
            let r_document: root.renderer.NodeRendererFuncType = self.render_document;
            let r_heading: root.renderer.NodeRendererFuncType = self.render_heading;
            let r_blockquote: root.renderer.NodeRendererFuncType = self.render_blockquote;
            let r_code_block: root.renderer.NodeRendererFuncType = self.render_code_block;
            let r_html_block: root.renderer.NodeRendererFuncType = self.render_html_block;
            let r_list: root.renderer.NodeRendererFuncType = self.render_list;
            let r_list_item: root.renderer.NodeRendererFuncType = self.render_list_item;
            let r_paragraph: root.renderer.NodeRendererFuncType = self.render_paragraph;
            let r_thematic_break: root.renderer.NodeRendererFuncType = self.render_thematic_break;
            let r_auto_link: root.renderer.NodeRendererFuncType = self.render_auto_link;
            let r_code_span: root.renderer.NodeRendererFuncType = self.render_code_span;
            let r_emphasis: root.renderer.NodeRendererFuncType = self.render_emphasis;
            let r_strong: root.renderer.NodeRendererFuncType = self.render_strong;
            let r_image: root.renderer.NodeRendererFuncType = self.render_image;
            let r_link: root.renderer.NodeRendererFuncType = self.render_link;
            let r_raw_html: root.renderer.NodeRendererFuncType = self.render_raw_html;
            let r_text: root.renderer.NodeRendererFuncType = self.render_text;
            let nrs: map<string, NodeRenderer> = {
                "Document": node_renderer_func(r_document),
                "Heading": node_renderer_func(r_heading),
                "Blockquote": node_renderer_func(r_blockquote),
                "CodeBlock": node_renderer_func(r_code_block),
                "HTMLBlock": node_renderer_func(r_html_block),
                "List": node_renderer_func(r_list),
                "ListItem": node_renderer_func(r_list_item),
                "Paragraph": node_renderer_func(r_paragraph),
                "ThematicBreak": node_renderer_func(r_thematic_break),
                "LinkReferenceDefinition": noop,
                "AutoLink": node_renderer_func(r_auto_link),
                "CodeSpan": node_renderer_func(r_code_span),
                "Emphasis": node_renderer_func(r_emphasis),
                "Strong": node_renderer_func(r_strong),
                "Image": node_renderer_func(r_image),
                "Link": node_renderer_func(r_link),
                "RawHTML": node_renderer_func(r_raw_html),
                "Text": node_renderer_func(r_text),
            };
            [with_node_renderers(nrs)]
        }
    }
}

/// NewCommonMark returns a new Extension that renders CommonMark compliant HTML.
function new_common_mark(opts: Option[] = []) -> Extension {
    CommonMarkRenderer { opts: opts, config: null }
}

function last_rune(n: root.ast.Node, source: uint8array) -> int? {
    let cur: root.ast.Node? = n;
    while (cur != null) {
        let r = match (cur) {
            let inline: root.ast.InlineNode => inline.last_rune(source),
            _ => {
                return null;
            }
        };
        if (r != null) {
            return r;
        }
        cur = cur.previous_sibling();
    }
    null
}

function first_rune(n: root.ast.Node?, source: uint8array) -> int? {
    let cur = n;
    while (cur != null) {
        let r = match (cur) {
            let inline: root.ast.InlineNode => inline.first_rune(source),
            _ => {
                return null;
            }
        };
        if (r != null) {
            return r;
        }
        cur = cur.next_sibling();
    }
    null
}

/// GlobalAttributeFilter defines attribute names which any elements can have.
function global_attribute_filter() -> root.util.BytesFilter {
    root.util.new_bytes_filter_string("accesskey,autocapitalize,autofocus,class,contenteditable,dir,draggable,enterkeyhint,hidden,id,inert,inputmode,is,itemid,itemprop,itemref,itemscope,itemtype,lang,part,role,slot,spellcheck,style,tabindex,title,translate")
}

/// HeadingAttributeFilter defines attribute names which heading elements can have.
function heading_attribute_filter() -> root.util.BytesFilter {
    global_attribute_filter()
}

/// BlockquoteAttributeFilter defines attribute names which blockquote elements can have.
function blockquote_attribute_filter() -> root.util.BytesFilter {
    global_attribute_filter().extend_string("cite")
}

/// ListAttributeFilter defines attribute names which list elements can have.
function list_attribute_filter() -> root.util.BytesFilter {
    global_attribute_filter().extend_string("start,reversed,type")
}

/// ListItemAttributeFilter defines attribute names which list item elements can have.
function list_item_attribute_filter() -> root.util.BytesFilter {
    global_attribute_filter().extend_string("value")
}

/// ParagraphAttributeFilter defines attribute names which paragraph elements can have.
function paragraph_attribute_filter() -> root.util.BytesFilter {
    global_attribute_filter()
}

/// ThematicAttributeFilter defines attribute names which hr elements can have.
function thematic_attribute_filter() -> root.util.BytesFilter {
    global_attribute_filter().extend_string("align,color,noshade,size,width")
}

/// LinkAttributeFilter defines attribute names which link elements can have.
function link_attribute_filter() -> root.util.BytesFilter {
    global_attribute_filter().extend_string("download,href,lang,media,ping,referrerpolicy,rel,shape,target")
}

/// CodeAttributeFilter defines attribute names which code elements can have.
function code_attribute_filter() -> root.util.BytesFilter {
    global_attribute_filter()
}

/// EmphasisAttributeFilter defines attribute names which emphasis elements can have.
function emphasis_attribute_filter() -> root.util.BytesFilter {
    global_attribute_filter()
}

/// StrongAttributeFilter defines attribute names which strong elements can have.
function strong_attribute_filter() -> root.util.BytesFilter {
    global_attribute_filter()
}

/// ImageAttributeFilter defines attribute names which image elements can have.
function image_attribute_filter() -> root.util.BytesFilter {
    global_attribute_filter().extend_string("align,border,crossorigin,decoding,height,importance,intrinsicsize,ismap,loading,referrerpolicy,sizes,srcset,usemap,width")
}

/// RenderAttributes renders the attributes of the given node to the given writer.
function render_attributes(w: root.util.BufWriter, source: uint8array, node: root.ast.Node, filter: root.util.BytesFilter?, rc: root.renderer.Context) -> void {
    let tw = TextWriter { w: w };
    for (let attr in node.attributes() ?? []) {
        if (filter != null) {
            if (!filter.contains_string(attr.name)) {
                if (!attr.name.starts_with("data-")) {
                    continue;
                }
            }
        }
        w.write_string(" ");
        w.write_string(attr.name);
        w.write_string("=\"");
        attr.value.write_to(tw, source);
        w.write_byte(34);
    }
}

function replacement_character() -> uint8array {
    "�".to_utf8()
}

/// Go's unexported `htmlWriter`: replaces NUL bytes with U+FFFD.
class HTMLWriter {
    w: root.util.BufWriter,

    implements root.util.BufWriter {
        function write(self, p0: uint8array) -> int {
            let p = p0;
            let written = 0;
            while (p.length() > 0) {
                let i = root.util.index_byte(p, 0);
                if (i < 0) {
                    written += self.w.write(p);
                    return written;
                }
                if (i > 0) {
                    written += self.w.write(p.slice(0, i));
                }
                written += self.w.write(replacement_character());
                p = p.slice(i + 1, p.length());
            }
            written
        }

        function write_byte(self, c: int) -> void {
            self.write(root.util.byte_array(c));
        }

        function write_rune(self, r: int) -> int {
            self.write(root.util.utf8_encode_rune(r))
        }

        function write_string(self, s: string) -> int {
            self.write(s.to_utf8())
        }

        function flush(self) -> void {
            self.w.flush();
        }
    }
}

/// Go's unexported `textWriter`: escapes HTML special characters.
class TextWriter {
    w: root.util.BufWriter,

    /// Go's `writeShort`; this port uses it for all lengths (Go's jump-table
    /// path for long inputs produces the same output).
    function write_short(self, p: uint8array) -> int {
        let written = 0;
        let n = 0;
        let l = p.length();
        let i = 0;
        while (i < l) {
            let v = root.util.escape_html_byte(p[i]);
            if (v != null) {
                if (n > 0) {
                    written += self.w.write(p.slice(i - n, i));
                }
                n = 0;
                written += self.w.write(v);
                i += 1;
                continue;
            }
            n += 1;
            i += 1;
        }
        if (n != 0) {
            written += self.w.write(p.slice(l - n, l));
        }
        written
    }

    implements root.util.BufWriter {
        function write(self, p: uint8array) -> int {
            self.write_short(p)
        }

        function write_byte(self, c: int) -> void {
            self.write(root.util.byte_array(c));
        }

        function write_rune(self, r: int) -> int {
            self.write(root.util.utf8_encode_rune(r))
        }

        function write_string(self, s: string) -> int {
            self.write(s.to_utf8())
        }

        function flush(self) -> void {
            self.w.flush();
        }
    }
}

/// Go's unexported `linkURLWriter`: URL-escapes what is written.
class LinkURLWriter {
    w: root.util.BufWriter,

    implements root.util.BufWriter {
        function write(self, p: uint8array) -> int {
            let b = root.util.url_escape(p);
            self.w.write(b)
        }

        function write_byte(self, c: int) -> void {
            self.write(root.util.byte_array(c));
        }

        function write_rune(self, r: int) -> int {
            self.write(root.util.utf8_encode_rune(r))
        }

        function write_string(self, s: string) -> int {
            self.write(s.to_utf8())
        }

        function flush(self) -> void {
            self.w.flush();
        }
    }
}

/// Go: `len(s) >= len(prefix) && bytes.EqualFold(s[0:len(prefix)], prefix)`
/// (prefixes here are ASCII).
function has_prefix_fold(s: uint8array, at: int, prefix: string) -> bool {
    let p = prefix.to_utf8();
    if (s.length() - at < p.length()) {
        return false;
    }
    let i = 0;
    while (i < p.length()) {
        let c = s[at + i];
        let d = p[i];
        if (c >= 65 && c <= 90) {
            c += 32;
        }
        if (d >= 65 && d <= 90) {
            d += 32;
        }
        if (c != d) {
            return false;
        }
        i += 1;
    }
    true
}

/// IsDangerousURL returns true if the given url seems a potentially dangerous url,
/// otherwise false.
function is_dangerous_url(url: string) -> bool {
    let s = url.to_utf8();
    if (has_prefix_fold(s, 0, "data:image/") && s.length() >= 11) {
        if (has_prefix_fold(s, 11, "png;") || has_prefix_fold(s, 11, "gif;") || has_prefix_fold(s, 11, "jpeg;") || has_prefix_fold(s, 11, "webp;")) {
            return false;
        }
        return true;
    }
    has_prefix_fold(s, 0, "javascript:") || has_prefix_fold(s, 0, "vbscript:") || has_prefix_fold(s, 0, "file:") || has_prefix_fold(s, 0, "data:")
}
