// Port of goldmark extension/strikethrough.go.
//
// Porting notes:
// - Go's `StrikethroughParserOption` is a function type
//   (`func(*strikethroughParserConfig)`); it is a BAML function type here.
// - Package-level singletons are zero-argument functions.

/// Go's unexported `strikethroughDelimiterProcessor`.
class StrikethroughDelimiterProcessor {
    implements root.parser.DelimiterProcessor {
        function is_delimiter(self, b: int) -> bool {
            b == 126 // '~'
        }

        function can_open_closer(self, opener: root.parser.Delimiter, closer: root.parser.Delimiter) -> bool {
            opener.char == closer.char
        }

        function on_match(self, consumes: int) -> root.ast.Node {
            root.extension.ast.new_strikethrough()
        }
    }
}

function default_strikethrough_delimiter_processor() -> root.parser.DelimiterProcessor {
    StrikethroughDelimiterProcessor {}
}

/// Go's unexported `strikethroughParserConfig`.
class StrikethroughParserConfig {
    f: root.parser.ParseDelimiterFunc,
}

/// StrikethroughParserOption is an option for strikethrough extension.
type StrikethroughParserOption = (c: StrikethroughParserConfig) -> void throws never

/// WithParseDelimiterFunc sets a custom ParseDelimiterFunc for strikethrough extension.
function with_parse_delimiter_func(f: root.parser.ParseDelimiterFunc) -> StrikethroughParserOption {
    (c: StrikethroughParserConfig) -> void {
        c.f = f;
    }
}

/// Go's unexported `strikethroughParser`.
class StrikethroughParser {
    f: root.parser.ParseDelimiterFunc,

    implements root.parser.InlineParser {
        function trigger(self) -> uint8array {
            root.util.bytes_of([126]) // '~'
        }

        function parse(self, parent: root.ast.Node, block: root.text.Reader, pc: root.parser.Context) -> root.ast.Node? {
            let before = block.preceding_character();
            if (before == 126) { // '~'
                return null;
            }
            let line = block.peek_line().line ?? root.util.new_bytes();
            let n = 0;
            while (n < line.length() && line[n] == 126) {
                n += 1;
            }
            if (n > 2) {
                return null;
            }
            // Go calls `parser.ParseDelimiter` here, not `s.f` (kept as is).
            root.parser.parse_delimiter(block, 1, default_strikethrough_delimiter_processor(), pc)
        }
    }

    implements root.parser.CloseBlocker {
        function close_block(self, parent: root.ast.Node, block: root.text.Reader, pc: root.parser.Context) -> void {
            // nothing to do
        }
    }
}

function new_strikethrough_parser_impl(opts: StrikethroughParserOption[] = []) -> root.parser.InlineParser {
    let config = StrikethroughParserConfig { f: root.parser.parse_delimiter };
    for (let opt in opts) {
        opt(config);
    }
    StrikethroughParser { f: config.f }
}

/// Go's unexported `strikethroughHTMLRendererExtension`.
class StrikethroughHTMLRendererExtension {
    function render_strikethrough(self, w: root.util.BufWriter, source: uint8array, n: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus {
        if (entering) {
            if (n.attributes() != null) {
                w.write_string("<del");
                root.renderer.html.render_attributes(w, source, n, strikethrough_attribute_filter(), rc);
                w.write_byte(62); // '>'
            } else {
                w.write_string("<del>");
            }
        } else {
            w.write_string("</del>");
        }
        root.ast.WalkStatus.WalkContinue
    }

    implements root.renderer.Extension<root.renderer.html.Config> {
        function renderer_options(self, cfg: root.renderer.html.Config) -> root.renderer.html.Option[] {
            let r: root.renderer.NodeRendererFuncType = self.render_strikethrough;
            let nrs: map<string, root.renderer.html.NodeRenderer> = {};
            nrs[root.extension.ast.kind_strikethrough()] = root.renderer.html.node_renderer_func(r);
            let opts: root.renderer.html.Option[] = [root.renderer.html.with_node_renderers(nrs)];
            opts
        }
    }
}

/// NewStrikethroughHTMLRenderer returns a new html.Extension for rendering Strikethrough nodes.
function new_strikethrough_html_renderer() -> root.renderer.html.Extension {
    StrikethroughHTMLRendererExtension {}
}

/// StrikethroughAttributeFilter defines attribute names which del elements can have.
function strikethrough_attribute_filter() -> root.util.BytesFilter {
    root.renderer.html.global_attribute_filter()
}

/// Go's unexported `strikethroughParserExtension`.
class StrikethroughParserExtension {
    opts: StrikethroughParserOption[],

    implements root.parser.Extension {
        function parser_options(self, c: root.parser.Config) -> root.parser.Option[] {
            let opts: StrikethroughParserOption[] = [];
            for (let o in self.opts) {
                opts.push(o);
            }
            let pdf = c.parse_delimiter_func;
            if (pdf != null) {
                opts.push(with_parse_delimiter_func(pdf));
            }
            let ips: root.util.PrioritizedValue<root.parser.InlineParser>[] = [
                root.util.prioritized(new_strikethrough_parser_impl(opts = opts), 500),
            ];
            let res: root.parser.Option[] = [root.parser.with_inline_parsers(ips)];
            res
        }
    }
}

/// NewStrikethroughParser returns a new parser.Extension for parsing strikethrough expressions.
function new_strikethrough_parser(opts: StrikethroughParserOption[] = []) -> root.parser.Extension {
    StrikethroughParserExtension { opts: opts }
}

/// StrikethroughParser is a default [parser.Extension] for parsing strikethrough expressions.
function strikethrough_parser() -> root.parser.Extension {
    new_strikethrough_parser()
}

/// StrikethroughHTMLRenderer is a default [html.Extension] for rendering Strikethrough nodes.
function strikethrough_html_renderer() -> root.renderer.html.Extension {
    new_strikethrough_html_renderer()
}
