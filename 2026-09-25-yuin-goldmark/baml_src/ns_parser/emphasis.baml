// Port of goldmark parser/emphasis.go.

class EmphasisDelimiterProcessor {
    implements DelimiterProcessor {
        function is_delimiter(self, b: int) -> bool {
            b == 42 || b == 95
        }

        function can_open_closer(self, opener: Delimiter, closer: Delimiter) -> bool {
            opener.char == closer.char
        }

        function on_match(self, consumes: int) -> root.ast.Node {
            if (consumes == 1) {
                return root.ast.new_emphasis();
            }
            root.ast.new_strong()
        }
    }
}

function default_emphasis_delimiter_processor() -> DelimiterProcessor {
    EmphasisDelimiterProcessor {}
}

/// EmphasisConfig struct is a data structure that holds configuration of the parsers related to emphasis.
class EmphasisConfig {
    f: ParseDelimiterFunc,
}

/// A EmphasisOption interface sets options for emphasis parsers.
interface EmphasisOption {
    function set_emphasis_option(self, p: EmphasisConfig) -> void throws never
}

class EmphasisParser {
    f: ParseDelimiterFunc,

    implements InlineParser {
        function trigger(self) -> uint8array {
            root.util.bytes_of([42, 95])
        }

        function parse(self, parent: root.ast.Node, block: root.text.Reader, pc: Context) -> root.ast.Node? {
            let f = self.f;
            f(block, 1, default_emphasis_delimiter_processor(), pc)
        }
    }
}

/// NewEmphasisParser return a new InlineParser that parses emphasises.
function new_emphasis_parser(opts: EmphasisOption[] = []) -> InlineParser {
    let config = EmphasisConfig { f: parse_delimiter };
    for (let o in opts) {
        o.set_emphasis_option(config);
    }
    EmphasisParser { f: config.f }
}
