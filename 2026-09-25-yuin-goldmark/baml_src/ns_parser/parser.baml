// Port of goldmark parser/parser.go.
//
// Package parser contains stuff that are related to parsing a Markdown text.
//
// Porting notes:
// - `ContextKey` values are handed out by a package-level counter in Go
//   (`NewContextKey`). BAML has no package-level state, so a ContextKey is a
//   unique string and the context store is a `map<string, unknown>`.
// - Go functional options that implement several option interfaces at once
//   (e.g. `WithAttribute()` is both an `Option` and a `HeadingOption`) are
//   classes implementing several BAML interfaces.
// - Go's `BlockParser.Continue` is `do_continue` here (`continue` is a
//   keyword); `(ast.Node, State)` results are `OpenResult`.
// - `State` is an int bit set; its constants are zero-argument functions.
// - Go's `[256][]BlockParser` tables use empty arrays for nil entries.
// - `sync.Once` initialization becomes an `initialized` flag.
// - Node identity comparisons use `root.ast.same_node`.

// ---------------------------------------------------------------------------
// LinkDefinition
// ---------------------------------------------------------------------------

/// A LinkDefinition interface represents a link definition in Markdown text.
interface LinkDefinition {
    /// String implements Stringer.
    function string(self) -> string throws never

    /// Label returns a label of the link definition.
    function label(self) -> uint8array throws never

    /// Destination returns a destination(URL) of the link definition.
    function destination(self) -> uint8array throws never

    /// Title returns a title of the link definition.
    function title(self) -> uint8array throws never
}

/// Go's unexported `linkDefinition`.
class LinkDefinitionImpl {
    node: root.ast.LinkReferenceDefinition?,
    label_bytes: uint8array,
    destination_bytes: uint8array,
    title_bytes: uint8array,

    implements LinkDefinition {
        function label(self) -> uint8array {
            self.label_bytes
        }

        function destination(self) -> uint8array {
            self.destination_bytes
        }

        function title(self) -> uint8array {
            self.title_bytes
        }

        function string(self) -> string {
            "LinkDefinition{Label:" + self.label_bytes.to_string() + ", Destination:" + self.destination_bytes.to_string() + ", Title:" + self.title_bytes.to_string() + "}"
        }
    }
}

/// NewLinkDefinition returns a new LinkDefinition.
function new_link_definition(label: uint8array, destination: uint8array, title: uint8array) -> LinkDefinition {
    LinkDefinitionImpl { node: null, label_bytes: label, destination_bytes: destination, title_bytes: title }
}

function new_link_definition_from_node(v: root.ast.LinkReferenceDefinition, src: uint8array) -> LinkDefinition {
    LinkDefinitionImpl {
        node: v,
        label_bytes: v.label.bytes(src),
        destination_bytes: v.destination.bytes(src),
        title_bytes: v.title.bytes(src),
    }
}

// ---------------------------------------------------------------------------
// IDs
// ---------------------------------------------------------------------------

/// An IDGenerator generates element IDs from a value and node kind.
/// Implementations should return a base ID; uniqueness is handled by IDs.
interface IDGenerator {
    /// Generate generates a base element id for the given value and node kind.
    function generate(self, value: uint8array, kind: root.ast.NodeKind) -> uint8array throws never
}

/// IDs is a collection of element ids, tracking uniqueness across a parse.
class IDs {
    values: map<string, bool>,
    gen: IDGenerator,

    /// Generate generates a unique element id for the given value and node kind.
    /// If the base id from the generator is already used, a numeric suffix is appended.
    function generate(self, value: uint8array, kind: root.ast.NodeKind) -> uint8array {
        let result = self.gen.generate(value, kind);
        let key = result.to_string();
        if (!self.values.has(key)) {
            self.values[key] = true;
            return result;
        }
        let i = 1;
        while (true) {
            let new_result = key + "-" + i.to_string();
            if (!self.values.has(new_result)) {
                self.values[new_result] = true;
                return new_result.to_utf8();
            }
            i += 1;
        }
        result
    }

    /// Put marks the given element id as used.
    function put(self, value: uint8array) -> void {
        self.values[value.to_string()] = true;
    }
}

class IdsConfig {
    id_generator: IDGenerator,
}

/// An IDsOption is an interface for options that can be passed to NewIDs.
interface IDsOption {
    function set_ids_option(self, c: IdsConfig) -> void throws never
}

/// NewIDs returns a new IDs.
/// By default, the default IDGenerator is used.
/// Use WithIDGenerator as an IDsOption to customize ID generation.
function new_ids(opts: IDsOption[] = []) -> IDs {
    let c = IdsConfig { id_generator: DefaultIDGenerator {} };
    for (let opt in opts) {
        opt.set_ids_option(c);
    }
    IDs { values: {}, gen: c.id_generator }
}

/// Go's unexported `defaultIDGenerator`.
class DefaultIDGenerator {
    implements IDGenerator {
        function generate(self, value: uint8array, kind: root.ast.NodeKind) -> uint8array {
            let v = root.util.trim_right_space(root.util.trim_left_space(value));
            let result = root.util.new_bytes();
            let i = 0;
            let n = v.length();
            while (i < n) {
                let c = v[i];
                let l = root.util.utf8_len(c);
                i += l;
                if (l != 1) {
                    continue;
                }
                if (root.util.is_alpha_numeric(c)) {
                    if (65 <= c && c <= 90) {
                        c += 32;
                    }
                    result.push(c);
                } else if (root.util.is_space(c) || c == 45 || c == 95) {
                    result.push(45);
                }
            }
            if (result.length() == 0) {
                if (kind == root.ast.kind_heading()) {
                    return "heading".to_utf8();
                }
                return "id".to_utf8();
            }
            result
        }
    }
}

// ---------------------------------------------------------------------------
// Context
// ---------------------------------------------------------------------------

/// ContextKey is a key that is used to set arbitrary values to the context.
type ContextKey = string

/// NewContextKey return a new ContextKey value (Go hands out increasing ints;
/// here the caller supplies a unique name).
function new_context_key(name: string) -> ContextKey {
    name
}

/// A Context interface holds a information that are necessary to parse
/// Markdown text.
interface Context {
    /// String implements Stringer.
    function string(self) -> string throws never

    /// Get returns a value associated with the given key.
    function get(self, key: ContextKey) -> unknown throws never

    /// ComputeIfAbsent computes a value if a value associated with the given key is absent and returns the value.
    function compute_if_absent(self, key: ContextKey, f: () -> unknown throws never) -> unknown throws never

    /// Set sets the given value to the context.
    function set(self, key: ContextKey, value: unknown) -> void throws never

    /// AddLinkDefinition adds the given link definition to this context.
    function add_link_definition(self, ref: LinkDefinition) -> void throws never

    /// LinkDefinition returns a link definition associated with the given
    /// label if it exists, otherwise null (Go: `(nil, false)`).
    function link_definition(self, label: string) -> LinkDefinition? throws never

    /// LinkDefinitions returns a list of link definitions.
    function link_definitions(self) -> LinkDefinition[] throws never

    /// IDs returns a collection of the element ids.
    function ids(self) -> IDs throws never

    /// BlockOffset returns a first non-space character position on current line.
    /// This value is valid only for BlockParser.Open.
    /// BlockOffset returns -1 if there is no current line (EOF).
    function block_offset(self) -> int throws never

    /// SetBlockOffset sets a first non-space character position on current line.
    /// This value is valid only for BlockParser.Open.
    function set_block_offset(self, v: int) -> void throws never

    /// BlockIndent returns an indent width on current line.
    /// This value is valid only for BlockParser.Open.
    /// BlockIndent returns -1 if there is no current line (EOF).
    function block_indent(self) -> int throws never

    /// SetBlockIndent sets an indent width on current line.
    /// This value is valid only for BlockParser.Open.
    function set_block_indent(self, v: int) -> void throws never

    /// FirstDelimiter returns a first delimiter of the current delimiter list.
    function first_delimiter(self) -> Delimiter? throws never

    /// LastDelimiter returns a last delimiter of the current delimiter list.
    function last_delimiter(self) -> Delimiter? throws never

    /// PushDelimiter appends the given delimiter to the tail of the current
    /// delimiter list.
    function push_delimiter(self, delimiter: Delimiter) -> void throws never

    /// RemoveDelimiter removes the given delimiter from the current delimiter list.
    function remove_delimiter(self, d: Delimiter) -> void throws never

    /// ClearDelimiters clears the current delimiter list.
    function clear_delimiters(self, bottom: root.ast.Node?) -> void throws never

    /// OpenedBlocks returns a list of nodes that are currently in parsing.
    function opened_blocks(self) -> Block[] throws never

    /// SetOpenedBlocks sets a list of nodes that are currently in parsing.
    function set_opened_blocks(self, v: Block[]) -> void throws never

    /// LastOpenedBlock returns a last node that is currently in parsing.
    function last_opened_block(self) -> Block throws never

    /// IsInLinkLabel returns true if current position seems to be in link label.
    function is_in_link_label(self) -> bool throws never
}

class ContextConfig {
    id_generator: IDGenerator?,
}

/// A ContextOption is an interface for options that can be passed to NewContext.
interface ContextOption {
    function set_context_option(self, c: ContextConfig) -> void throws never
}

/// Go's unexported `parseContext`.
class ParseContext {
    store: map<string, unknown>,
    id_set: IDs,
    has_id_generator: bool,
    link_defs: map<string, LinkDefinition>,
    // Go iterates `linkDefs` (a map) in random order; insertion order is kept here.
    offset_value: int,
    indent_value: int,
    delimiters: Delimiter?,
    last_delim: Delimiter?,
    blocks: Block[],

    implements Context {
        function get(self, key: ContextKey) -> unknown {
            self.store.get(key)
        }

        function compute_if_absent(self, key: ContextKey, f: () -> unknown throws never) -> unknown {
            let v = self.store.get(key);
            if (v == null) {
                let nv = f();
                self.store[key] = nv;
                return nv;
            }
            v
        }

        function set(self, key: ContextKey, value: unknown) -> void {
            self.store[key] = value;
        }

        function ids(self) -> IDs {
            self.id_set
        }

        function block_offset(self) -> int {
            self.offset_value
        }

        function set_block_offset(self, v: int) -> void {
            self.offset_value = v;
        }

        function block_indent(self) -> int {
            self.indent_value
        }

        function set_block_indent(self, v: int) -> void {
            self.indent_value = v;
        }

        function last_delimiter(self) -> Delimiter? {
            self.last_delim
        }

        function first_delimiter(self) -> Delimiter? {
            self.delimiters
        }

        function push_delimiter(self, d: Delimiter) -> void {
            let l = self.last_delim;
            if (self.delimiters == null || l == null) {
                self.delimiters = d;
                self.last_delim = d;
            } else {
                self.last_delim = d;
                l.next_delimiter = d;
                d.previous_delimiter = l;
            }
        }

        function remove_delimiter(self, d: Delimiter) -> void {
            let prev = d.previous_delimiter;
            let next = d.next_delimiter;
            if (prev == null) {
                self.delimiters = next;
            } else {
                prev.next_delimiter = next;
                if (next != null) {
                    next.previous_delimiter = prev;
                }
            }
            if (next == null) {
                self.last_delim = prev;
            }
            let first = self.delimiters;
            if (first != null) {
                first.previous_delimiter = null;
            }
            let last = self.last_delim;
            if (last != null) {
                last.next_delimiter = null;
            }
            d.next_delimiter = null;
            d.previous_delimiter = null;
            let parent = d.parent();
            if (parent != null) {
                if (d.length != 0) {
                    merge_or_replace_text_segment(parent, d, d.value, d.decoder);
                } else {
                    parent.remove_child(d);
                }
            }
        }

        function clear_delimiters(self, bottom: root.ast.Node?) -> void {
            if (self.last_delim == null) {
                return;
            }
            let bottom_delim: Delimiter? = null;
            if (bottom != null) {
                match (bottom) {
                    let bd: Delimiter => {
                        bottom_delim = bd;
                    }
                    _ => {}
                }
            }
            let c = self.last_delim;
            while (c != null && !same_delimiter(c, bottom_delim)) {
                let prev = c.previous_delimiter;
                self.remove_delimiter(c);
                c = prev;
            }
        }

        function add_link_definition(self, ref: LinkDefinition) -> void {
            let key = root.util.to_link_reference(ref.label());
            if (!self.link_defs.has(key)) {
                self.link_defs[key] = ref;
            }
        }

        function link_definition(self, label: string) -> LinkDefinition? {
            self.link_defs.get(label)
        }

        function link_definitions(self) -> LinkDefinition[] {
            let ret: LinkDefinition[] = [];
            for (let k in self.link_defs.keys()) {
                ret.push(self.link_defs[k]);
            }
            ret
        }

        function string(self) -> string {
            let refs: string[] = [];
            for (let k in self.link_defs.keys()) {
                refs.push(self.link_defs[k].string());
            }
            "Context{Store:" + self.store.keys().join(",") + ", LinkDefinitions:" + refs.join(",") + "}"
        }

        function opened_blocks(self) -> Block[] {
            self.blocks
        }

        function set_opened_blocks(self, v: Block[]) -> void {
            self.blocks = v;
        }

        function last_opened_block(self) -> Block {
            let l = self.blocks.length();
            if (l != 0) {
                return self.blocks[l - 1];
            }
            Block { node: null, parser: null }
        }

        function is_in_link_label(self) -> bool {
            let tlist = self.get(link_label_state_key());
            tlist != null
        }
    }
}

/// Delimiter identity (Go compares `*Delimiter` pointers).
function same_delimiter(a: Delimiter?, b: Delimiter?) -> bool {
    root.ast.same_node(a, b)
}

/// NewContext returns a new Context.
/// By default, a new IDs with the default IDGenerator is used.
/// Use WithIDGenerator as a ContextOption to customize ID generation.
function new_context(opts: ContextOption[] = []) -> Context {
    let cc = ContextConfig { id_generator: null };
    for (let opt in opts) {
        opt.set_context_option(cc);
    }
    let given = cc.id_generator;
    let id_generator: IDGenerator = if (given == null) { DefaultIDGenerator {} } else { given };
    ParseContext {
        store: {},
        link_defs: {},
        id_set: new_ids(opts = [with_id_generator(id_generator)]),
        has_id_generator: given != null,
        offset_value: -1,
        indent_value: -1,
        delimiters: null,
        last_delim: null,
        blocks: [],
    }
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// State represents parser's state.
/// State is designed to use as a bit flag.
type State = int

/// None is the zero value of [State], indicating that no flags are set.
function NONE() -> State {
    0
}

/// Continue indicates parser can continue parsing.
function CONTINUE() -> State {
    2
}

/// Close indicates parser cannot parse anymore.
function CLOSE() -> State {
    4
}

/// HasChildren indicates parser may have child blocks.
function HAS_CHILDREN() -> State {
    8
}

/// NoChildren indicates parser does not have child blocks.
function NO_CHILDREN() -> State {
    16
}

/// RequireParagraph indicates parser requires that the last node
/// must be a paragraph and is not converted to other nodes by
/// ParagraphTransformers.
function REQUIRE_PARAGRAPH() -> State {
    32
}

// ---------------------------------------------------------------------------
// Config and options
// ---------------------------------------------------------------------------

/// A Config struct is a data structure that holds configuration of the Parser.
class Config {
    /// IDGenerator is a custom IDGenerator for element id generation.
    id_generator: IDGenerator?,

    /// EscapedSpace indicates that a '\' escaped half-space(0x20) should not trigger parsers.
    /// This defaults to false unless enabled via [WithEscapedSpace] passed to [New].
    escaped_space: bool,

    /// Attribute indicates that custom attributes are enabled.
    /// This defaults to false unless enabled via [WithAttribute] passed to [New].
    attribute: bool,

    /// ParseDelimiterFunc is a custom function for parsing delimiters.
    parse_delimiter_func: ParseDelimiterFunc?,

    without_default_parsers: bool,

    auto_heading_id: bool,

    block_parsers: root.util.PrioritizedValue<BlockParser>[],
    inline_parsers: root.util.PrioritizedValue<InlineParser>[],
    paragraph_transformers: root.util.PrioritizedValue<ParagraphTransformer>[],
    ast_transformers: root.util.PrioritizedValue<ASTTransformer>[],
    extensions: Extension[],

    /// Go copies the Config struct by value (`thisConfig := *cfg`).
    function copy(self) -> Config {
        Config {
            id_generator: self.id_generator,
            escaped_space: self.escaped_space,
            attribute: self.attribute,
            parse_delimiter_func: self.parse_delimiter_func,
            without_default_parsers: self.without_default_parsers,
            auto_heading_id: self.auto_heading_id,
            block_parsers: self.block_parsers,
            inline_parsers: self.inline_parsers,
            paragraph_transformers: self.paragraph_transformers,
            ast_transformers: self.ast_transformers,
            extensions: self.extensions,
        }
    }
}

function new_config() -> Config {
    Config {
        id_generator: null,
        escaped_space: false,
        attribute: false,
        parse_delimiter_func: null,
        without_default_parsers: false,
        auto_heading_id: false,
        block_parsers: [],
        inline_parsers: [],
        paragraph_transformers: [],
        ast_transformers: [],
        extensions: [],
    }
}

/// An Option interface is a functional option type for the Parser.
interface Option {
    function set_parser_option(self, c: Config) -> void throws never
}

/// Go's `withAttribute`: an Option and a HeadingOption.
class WithAttributeOption {
    implements Option {
        function set_parser_option(self, c: Config) -> void {
            c.attribute = true;
        }
    }

    implements HeadingOption {
        function set_heading_option(self, p: HeadingConfig) -> void {
            p.attribute = true;
        }
    }
}

/// WithAttribute is a functional option that enables custom attributes.
/// It can be used as a parser Option and a HeadingOption.
function with_attribute() -> WithAttributeOption {
    WithAttributeOption {}
}

class WithDefaultParsersOption {
    v: bool,

    implements Option {
        function set_parser_option(self, c: Config) -> void {
            c.without_default_parsers = !self.v;
        }
    }
}

/// WithDefaultParsers is a functional option that indicates whether default parsers should be used.
function with_default_parsers(v: bool) -> Option {
    WithDefaultParsersOption { v: v }
}

class WithExtensionsOption {
    value: Extension[],

    implements Option {
        function set_parser_option(self, c: Config) -> void {
            for (let e in self.value) {
                c.extensions.push(e);
            }
        }
    }
}

/// WithExtensions is a functional option that allows you to add extensions to the parser.
function with_extensions(ext: Extension[]) -> Option {
    WithExtensionsOption { value: ext }
}

/// Go's `withParseDelimiterFunc`: an Option and an EmphasisOption.
class WithParseDelimiterFuncOption {
    f: ParseDelimiterFunc,

    implements Option {
        function set_parser_option(self, c: Config) -> void {
            c.parse_delimiter_func = self.f;
        }
    }

    implements EmphasisOption {
        function set_emphasis_option(self, p: EmphasisConfig) -> void {
            p.f = self.f;
        }
    }
}

/// WithParseDelimiterFunc is a functional option that allows you to set a custom function for parsing delimiters.
function with_parse_delimiter_func(f: ParseDelimiterFunc) -> WithParseDelimiterFuncOption {
    WithParseDelimiterFuncOption { f: f }
}

// ---------------------------------------------------------------------------
// Nil node
// ---------------------------------------------------------------------------

/// Go's unexported `nilNode`: a special node every tree operation of which is
/// a no-op.
class NilNode {
    b: root.ast.BaseNode,

    implements root.ast.Node {
        function base(self) -> root.ast.BaseNode {
            self.b
        }

        function kind(self) -> root.ast.NodeKind {
            root.ast.kind_text()
        }

        function dump(self, source: uint8array) -> root.ast.NodeDump {
            root.ast.new_node_dump(self, null)
        }

        function pos(self) -> int {
            -1
        }

        function set_pos(self, v: int) -> void {
        }

        function next_sibling(self) -> root.ast.Node? {
            null
        }

        function previous_sibling(self) -> root.ast.Node? {
            null
        }

        function parent(self) -> root.ast.Node? {
            null
        }

        function set_parent(self, v: root.ast.Node?) -> void {
        }

        function set_previous_sibling(self, v: root.ast.Node?) -> void {
        }

        function set_next_sibling(self, v: root.ast.Node?) -> void {
        }

        function has_children(self) -> bool {
            false
        }

        function child_count(self) -> int {
            0
        }

        function children(self) -> root.ast.Node[] {
            []
        }

        function first_child(self) -> root.ast.Node? {
            null
        }

        function last_child(self) -> root.ast.Node? {
            null
        }

        function append_child(self, v: root.ast.Node) -> void {
        }

        function remove_child(self, v: root.ast.Node) -> void {
        }

        function remove_children(self) -> void {
        }

        function replace_child(self, target: root.ast.Node, insertee: root.ast.Node) -> void {
        }

        function insert_before(self, target: root.ast.Node?, insertee: root.ast.Node) -> void {
        }

        function insert_after(self, target: root.ast.Node, insertee: root.ast.Node) -> void {
        }

        function owner_document(self) -> root.ast.Document? {
            null
        }

        function set_attribute(self, name: string, value: root.text.MultiLineValue) -> void {
        }

        function attribute(self, name: string) -> root.text.MultiLineValue? {
            null
        }

        function attributes(self) -> root.ast.Attribute[]? {
            null
        }

        function remove_attributes(self) -> void {
        }
    }
}

/// Nil is a special AST node that represents an empty node.
/// If a parser returns Nil, the parser is considered as successful but does not add any node to the AST tree.
/// (Go: package-level `var Nil`; compare with `is_nil_node`.)
function nil_node() -> root.ast.Node {
    NilNode { b: root.ast.new_base_node() }
}

/// Returns true if `n` is the special Nil node (Go: `n == Nil`).
function is_nil_node(n: root.ast.Node?) -> bool {
    if (n == null) {
        return false;
    }
    match (n) {
        let x: NilNode => true,
        _ => false,
    }
}

// ---------------------------------------------------------------------------
// Parser interfaces
// ---------------------------------------------------------------------------

/// A Parser interface parses Markdown text into AST nodes.
interface Parser {
    /// Parse parses the given Markdown text into AST nodes.
    function parse(self, source: uint8array, opts: ParseOption[]) -> root.ast.Node throws never

    /// ParseStringSource is a helper function that parses a string source into AST nodes using the given parser.
    function parse_string_source(self, source: string, opts: ParseOption[]) -> root.ast.Node throws never
}

/// Result of `BlockParser.open` (Go: `(ast.Node, State)`).
class OpenResult {
    node: root.ast.Node?,
    state: State,
}

/// A BlockParser interface parses a block level element like Paragraph, List,
/// Blockquote etc.
interface BlockParser {
    /// Trigger returns a list of characters that triggers the Open method of
    /// this parser.
    /// If Trigger returns null, Open will be called with any lines.
    function trigger(self) -> uint8array? throws never

    /// Open parses the current line and returns a result of parsing.
    ///
    /// Open must not parse beyond the current line.
    /// If Open has been able to parse the current line, Open must advance a reader
    /// position by consumed byte length.
    ///
    /// If Open has not been able to parse the current line, Open should returns
    /// (nil, NoChildren). If Open has been able to parse the current line, Open
    /// should returns a new Block node and returns HasChildren or NoChildren.
    function open(self, parent: root.ast.Node, reader: root.text.Reader, pc: Context) -> OpenResult throws never

    /// Continue parses the current line and returns a result of parsing.
    ///
    /// Continue must not parse beyond the current line.
    /// If Continue has been able to parse the current line, Continue must advance
    /// a reader position by consumed byte length.
    ///
    /// If Continue has not been able to parse the current line, Continue should
    /// returns Close. If Continue has been able to parse the current line,
    /// Continue should returns (Continue | NoChildren) or
    /// (Continue | HasChildren)
    function do_continue(self, node: root.ast.Node, reader: root.text.Reader, pc: Context) -> State throws never

    /// Close will be called when the parser returns Close.
    function close(self, node: root.ast.Node, reader: root.text.Reader, pc: Context) -> void throws never

    /// CanInterruptParagraph returns true if the parser can interrupt paragraphs,
    /// otherwise false.
    function can_interrupt_paragraph(self) -> bool throws never

    /// CanAcceptIndentedLine returns true if the parser can open new node when
    /// the given line is being indented more than 3 spaces.
    function can_accept_indented_line(self) -> bool throws never
}

/// An InlineParser interface parses an inline level element like CodeSpan, Link etc.
interface InlineParser {
    /// Trigger returns a list of characters that triggers Parse method of
    /// this parser.
    /// Trigger characters must be a punctuation or a halfspace.
    /// Halfspaces triggers this parser when character is any spaces characters or
    /// a head of line
    function trigger(self) -> uint8array throws never

    /// Parse parse the given block into an inline node.
    ///
    /// Parse can parse beyond the current line.
    /// If Parse has been able to parse the current line, it must advance a reader
    /// position by consumed byte length.
    function parse(self, parent: root.ast.Node, block: root.text.Reader, pc: Context) -> root.ast.Node? throws never
}

/// A CloseBlocker interface is a callback function that will be
/// called when block is closed in the inline parsing.
interface CloseBlocker {
    /// CloseBlock will be called when a block is closed.
    function close_block(self, parent: root.ast.Node, block: root.text.Reader, pc: Context) -> void throws never
}

/// A ParagraphTransformer transforms parsed Paragraph nodes.
/// For example, link references are searched in parsed Paragraphs.
interface ParagraphTransformer {
    /// Transform transforms the given paragraph.
    function transform(self, node: root.ast.Paragraph, reader: root.text.Reader, pc: Context) -> void throws never
}

/// ASTTransformer transforms entire Markdown document AST tree.
interface ASTTransformer {
    /// Transform transforms the given AST tree.
    function transform(self, node: root.ast.Document, reader: root.text.Reader, pc: Context) -> void throws never
}

/// A Block struct holds a node and correspond parser pair.
class Block {
    /// Node is a BlockNode.
    node: root.ast.Node?,
    /// Parser is a BlockParser.
    parser: BlockParser?,
}

// ---------------------------------------------------------------------------
// More options
// ---------------------------------------------------------------------------

class WithBlockParsersOption {
    value: root.util.PrioritizedValue<BlockParser>[],

    implements Option {
        function set_parser_option(self, c: Config) -> void {
            for (let v in self.value) {
                c.block_parsers.push(v);
            }
        }
    }
}

/// WithBlockParsers is a functional option that allow you to add
/// BlockParsers to the parser.
function with_block_parsers(bs: root.util.PrioritizedValue<BlockParser>[]) -> Option {
    WithBlockParsersOption { value: bs }
}

class WithInlineParsersOption {
    value: root.util.PrioritizedValue<InlineParser>[],

    implements Option {
        function set_parser_option(self, c: Config) -> void {
            for (let v in self.value) {
                c.inline_parsers.push(v);
            }
        }
    }
}

/// WithInlineParsers is a functional option that allow you to add
/// InlineParsers to the parser.
function with_inline_parsers(ps: root.util.PrioritizedValue<InlineParser>[]) -> Option {
    WithInlineParsersOption { value: ps }
}

class WithParagraphTransformersOption {
    value: root.util.PrioritizedValue<ParagraphTransformer>[],

    implements Option {
        function set_parser_option(self, c: Config) -> void {
            for (let v in self.value) {
                c.paragraph_transformers.push(v);
            }
        }
    }
}

/// WithParagraphTransformers is a functional option that allow you to add
/// ParagraphTransformers to the parser.
function with_paragraph_transformers(ps: root.util.PrioritizedValue<ParagraphTransformer>[]) -> Option {
    WithParagraphTransformersOption { value: ps }
}

class WithASTTransformersOption {
    value: root.util.PrioritizedValue<ASTTransformer>[],

    implements Option {
        function set_parser_option(self, c: Config) -> void {
            for (let v in self.value) {
                c.ast_transformers.push(v);
            }
        }
    }
}

/// WithASTTransformers is a functional option that allow you to add
/// ASTTransformers to the parser.
function with_ast_transformers(ps: root.util.PrioritizedValue<ASTTransformer>[]) -> Option {
    WithASTTransformersOption { value: ps }
}

class WithEscapedSpaceOption {
    implements Option {
        function set_parser_option(self, c: Config) -> void {
            c.escaped_space = true;
        }
    }
}

/// WithEscapedSpace is a functional option indicates that a '\' escaped half-space(0x20) should not trigger parsers.
function with_escaped_space() -> Option {
    WithEscapedSpaceOption {}
}

/// Go's `withIDGenerator`: an Option, a ContextOption and an IDsOption.
class WithIDGeneratorOption {
    gen: IDGenerator,

    implements Option {
        function set_parser_option(self, c: Config) -> void {
            c.id_generator = self.gen;
        }
    }

    implements ContextOption {
        function set_context_option(self, c: ContextConfig) -> void {
            c.id_generator = self.gen;
        }
    }

    implements IDsOption {
        function set_ids_option(self, c: IdsConfig) -> void {
            c.id_generator = self.gen;
        }
    }
}

/// WithIDGenerator is a functional option that sets a custom IDGenerator for element id generation.
/// It can be used as a parser Option, a parser ContextOption, and a parser IDsOption.
function with_id_generator(gen: IDGenerator) -> WithIDGeneratorOption {
    WithIDGeneratorOption { gen: gen }
}

// ---------------------------------------------------------------------------
// The parser
// ---------------------------------------------------------------------------

/// New returns a new Parser with given options.
function new(options: Option[] = []) -> Parser {
    let config = new_config();
    for (let opt in options) {
        opt.set_parser_option(config);
    }
    if (!config.without_default_parsers) {
        for (let opt in common_mark().parser_options(config)) {
            opt.set_parser_option(config);
        }
    }
    // Go ranges over `config.extensions` evaluated once; extensions added by
    // extensions are not visited.
    let exts = config.extensions.slice(0, config.extensions.length());
    for (let ext in exts) {
        let ext_options = ext.parser_options(config);
        for (let opt in ext_options) {
            opt.set_parser_option(config);
        }
    }
    let empty_bp: BlockParser[][] = [];
    let empty_ip: InlineParser[][] = [];
    let trig: bool[] = [];
    let i = 0;
    while (i < 256) {
        empty_bp.push([]);
        empty_ip.push([]);
        trig.push(false);
        i += 1;
    }
    GoldmarkParser {
        block_parsers: empty_bp,
        free_block_parsers: [],
        inline_parsers: empty_ip,
        close_blockers: [],
        paragraph_transformers: [],
        ast_transformers: [],
        escaped_space: false,
        id_generator: null,
        decoder: null,
        config: config,
        initialized: false,
        triggerable: trig,
    }
}

/// Go's unexported `parser`.
class GoldmarkParser {
    block_parsers: BlockParser[][],
    free_block_parsers: BlockParser[],
    inline_parsers: InlineParser[][],
    close_blockers: CloseBlocker[],
    paragraph_transformers: ParagraphTransformer[],
    ast_transformers: ASTTransformer[],
    escaped_space: bool,
    id_generator: IDGenerator?,
    decoder: root.text.Decoder?,
    config: Config?,
    initialized: bool,
    triggerable: bool[],

    /// AddOptions applies additional options to the parser configuration.
    function add_options(self, opts: Option[]) -> void {
        let config = self.config;
        if (config == null) {
            return;
        }
        for (let opt in opts) {
            opt.set_parser_option(config);
        }
    }

    function add_block_parser(self, v: root.util.PrioritizedValue<BlockParser>) -> void {
        let bp = v.value;
        let tcs = bp.trigger();
        if (tcs == null) {
            self.free_block_parsers.push(bp);
        } else {
            for (let tc in tcs.to_array()) {
                self.block_parsers[tc].push(bp);
            }
        }
    }

    function add_inline_parser(self, v: root.util.PrioritizedValue<InlineParser>) -> void {
        let ip = v.value;
        let tcs = ip.trigger();
        // Go: `ip.(CloseBlocker)`. BAML rejects matching an interface-typed
        // value against an unrelated interface, so widen to `unknown` first.
        let any_ip: unknown = ip;
        match (any_ip) {
            let cb: CloseBlocker => {
                self.close_blockers.push(cb);
            }
            _ => {}
        }
        for (let tc in tcs.to_array()) {
            self.inline_parsers[tc].push(ip);
        }
    }

    function add_paragraph_transformer(self, v: root.util.PrioritizedValue<ParagraphTransformer>) -> void {
        self.paragraph_transformers.push(v.value);
    }

    function add_ast_transformer(self, v: root.util.PrioritizedValue<ASTTransformer>) -> void {
        self.ast_transformers.push(v.value);
    }

    /// Go's `initSync.Do(...)` body.
    function init_once(self) -> void {
        if (self.initialized) {
            return;
        }
        self.initialized = true;
        let config = self.config;
        if (config == null) {
            return;
        }
        for (let v in root.util.sort_prioritized(config.block_parsers)) {
            self.add_block_parser(v);
        }
        let i = 0;
        while (i < 256) {
            if (self.block_parsers[i].length() != 0) {
                for (let fbp in self.free_block_parsers) {
                    self.block_parsers[i].push(fbp);
                }
            }
            i += 1;
        }

        for (let v in root.util.sort_prioritized(config.inline_parsers)) {
            self.add_inline_parser(v);
        }
        let has_space_parser = self.inline_parsers[32].length() != 0;
        let c = 0;
        while (c < 256) {
            if (root.util.is_punct(c) && self.inline_parsers[c].length() != 0) {
                self.triggerable[c] = true;
            } else if (char_is_space_flag(c) && has_space_parser) {
                self.triggerable[c] = true;
            }
            c += 1;
        }
        for (let v in root.util.sort_prioritized(config.paragraph_transformers)) {
            self.add_paragraph_transformer(v);
        }
        for (let v in root.util.sort_prioritized(config.ast_transformers)) {
            self.add_ast_transformer(v);
        }
        self.escaped_space = config.escaped_space;
        self.id_generator = config.id_generator;
        if (self.id_generator == null) {
            self.id_generator = DefaultIDGenerator {};
        }
        if (config.escaped_space) {
            self.decoder = root.text.new_decoder([root.text.with_escaped_space()]);
        } else {
            self.decoder = root.text.new_decoder([]);
        }
        self.config = null;
    }

    function get_decoder(self) -> root.text.Decoder {
        let d = self.decoder;
        if (d == null) {
            return root.text.new_decoder([]);
        }
        d
    }

    function get_id_generator(self) -> IDGenerator {
        let g = self.id_generator;
        if (g == null) {
            return DefaultIDGenerator {};
        }
        g
    }

    implements Parser {
        function parse(self, source: uint8array, opts: ParseOption[]) -> root.ast.Node {
            self.init_once();
            let decoder = self.get_decoder();
            let reader = root.text.new_reader(source, decoder);
            let pc: Context? = null;
            let cfg = ParseConfig { context: null, do_pp: false, pp_opts: [] };
            if (opts.length() > 0) {
                for (let opt in opts) {
                    opt(cfg);
                }
                let ctx = cfg.context;
                if (ctx != null) {
                    match (ctx) {
                        let c: ParseContext => {
                            if (!c.has_id_generator) {
                                c.id_set = new_ids(opts = [with_id_generator(self.get_id_generator())]);
                            }
                            pc = ctx;
                        }
                        _ => {}
                    }
                }
            }
            let the_pc: Context = if (pc == null) { new_context(opts = [with_id_generator(self.get_id_generator())]) } else { pc };
            let root_node = root.ast.new_document();
            self.parse_blocks(root_node, reader, the_pc);

            let block_reader = root.text.new_block_reader(reader.source(), null, decoder);
            self.walk_block(root_node, block_reader, the_pc);
            for (let at in self.ast_transformers) {
                at.transform(root_node, reader, the_pc);
            }
            if (cfg.do_pp) {
                let dump = root_node.dump(reader.source());
                let buf = root.util.new_buffer();
                dump.pretty_print(buf, reader.source(), opts = cfg.pp_opts);
                baml.io.print(buf.string());
            }
            root_node
        }

        function parse_string_source(self, source: string, opts: ParseOption[]) -> root.ast.Node {
            self.parse(source.to_utf8(), opts)
        }
    }

    function transform_paragraph(self, node: root.ast.Paragraph, reader: root.text.Reader, pc: Context) -> bool {
        for (let pt in self.paragraph_transformers) {
            pt.transform(node, reader, pc);
            if (node.parent() == null) {
                return true;
            }
        }
        false
    }

    function close_blocks(self, from: int, to: int, reader: root.text.Reader, pc: Context) -> void {
        let blocks = pc.opened_blocks();
        let i = from;
        while (i >= to) {
            let blk = blocks[i];
            let node = blk.node;
            let bp = blk.parser;
            if (node != null && bp != null) {
                bp.close(node, reader, pc);
                match (node) {
                    let paragraph: root.ast.Paragraph => {
                        if (node.parent() != null) {
                            self.transform_paragraph(paragraph, reader, pc);
                        }
                    }
                    _ => {}
                }
            }
            i -= 1;
        }
        let new_blocks: Block[] = [];
        if (from == blocks.length() - 1) {
            new_blocks = blocks.slice(0, to);
        } else {
            new_blocks = blocks.slice(0, to).concat(blocks.slice(from + 1, blocks.length()));
        }
        pc.set_opened_blocks(new_blocks);
    }

    function open_blocks(self, parent0: root.ast.Node, blank_line: bool, reader: root.text.Reader, pc: Context) -> int {
        let parent = parent0;
        let result = NO_BLOCKS_OPENED();
        let continuable = false;
        let last_block = pc.last_opened_block();
        let lbn = last_block.node;
        if (lbn != null) {
            continuable = root.ast.is_paragraph(lbn);
        }
        // Go uses `goto retry`; the loop below re-runs the body on `retry`.
        let retry = true;
        while (retry) {
            retry = false;
            let pl = reader.peek_line();
            let line0 = pl.line;
            let line = line0 ?? root.util.new_bytes();
            let seg = pl.segment;
            let iw = root.util.indent_width(line, reader.line_offset());
            let w = iw.width;
            let pos = iw.pos;
            if (line.length() == 0) {
                pc.set_block_offset(-1);
                pc.set_block_indent(-1);
            } else {
                pc.set_block_offset(pos);
                pc.set_block_indent(w);
            }

            if (line0 == null || line[0] == 10) {
                break;
            }
            let bps = self.free_block_parsers;
            if (pos < line.length()) {
                bps = self.block_parsers[line[pos]];
                if (bps.length() == 0) {
                    bps = self.free_block_parsers;
                }
            }
            if (bps.length() == 0) {
                break;
            }

            for (let bp in bps) {
                if (continuable && result == NO_BLOCKS_OPENED() && !bp.can_interrupt_paragraph()) {
                    continue;
                }

                if (w > 3 && !bp.can_accept_indented_line()) {
                    continue;
                }
                last_block = pc.last_opened_block();
                let last = last_block.node;
                let block_pos = reader.position().segment;
                let opened = bp.open(parent, reader, pc);
                let node = opened.node;
                let state = opened.state;
                if (node != null) {
                    let off = pc.block_offset() - seg.padding;
                    node.set_pos(block_pos.start + if (off > 0) { off } else { 0 });

                    // Parser requires last node to be a paragraph.
                    // With table extension:
                    //
                    //     0
                    //     -:
                    //     -
                    //
                    // '-' on 3rd line seems a Setext heading because 1st and 2nd lines
                    // are being paragraph when the Setext heading parser tries to parse the 3rd
                    // line.
                    // But 1st line and 2nd line are a table. Thus this paragraph will be transformed
                    // by a paragraph transformer. So this text should be converted to a table and
                    // an empty list.
                    if ((state & REQUIRE_PARAGRAPH()) != 0) {
                        if (last != null && root.ast.same_node(last, parent.last_child())) {
                            // Opened paragraph may be transformed by ParagraphTransformers in
                            // closeBlocks().
                            let lbp = last_block.parser;
                            if (lbp != null) {
                                lbp.close(last, reader, pc);
                            }
                            let blocks = pc.opened_blocks();
                            pc.set_opened_blocks(blocks.slice(0, blocks.length() - 1));
                            let transformed = match (last) {
                                let lp: root.ast.Paragraph => self.transform_paragraph(lp, reader, pc),
                                _ => false,
                            };
                            if (transformed) {
                                // Paragraph has been transformed.
                                // So this parser is considered as failing.
                                continuable = false;
                                retry = true;
                                break;
                            }
                        }
                    }
                    match (node) {
                        let bn: root.ast.BlockNode => {
                            bn.set_blank_previous_lines(blank_line);
                        }
                        _ => {}
                    }
                    if (last != null) {
                        if (last.parent() == null) {
                            let last_pos = pc.opened_blocks().length() - 1;
                            self.close_blocks(last_pos, last_pos, reader, pc);
                        }
                    }
                    parent.append_child(node);
                    result = NEW_BLOCKS_OPENED();
                    let be = Block { node: node, parser: bp };
                    let ob = pc.opened_blocks();
                    ob.push(be);
                    pc.set_opened_blocks(ob);
                    if ((state & HAS_CHILDREN()) != 0) {
                        parent = node;
                        retry = true; // try child block
                    }
                    break; // no children, can not open more blocks on this line
                }
            }
        }

        // continuable:
        if (result == NO_BLOCKS_OPENED() && continuable) {
            let lnode = last_block.node;
            let lparser = last_block.parser;
            if (lnode != null && lparser != null) {
                let state = lparser.do_continue(lnode, reader, pc);
                if ((state & CONTINUE()) != 0) {
                    result = PARAGRAPH_CONTINUATION();
                }
            }
        }
        result
    }

    function parse_blocks(self, parent: root.ast.Node, reader: root.text.Reader, pc: Context) -> void {
        pc.set_opened_blocks([]);
        let prev_line_blank: bool[] = [];
        let cur_line_blank: bool[] = [];
        while (true) { // process blocks separated by blank lines
            let sr = reader.skip_blank_lines();
            if (!sr.ok) {
                return;
            }
            // first, we try to open blocks
            if (self.open_blocks(parent, true, reader, pc) != NEW_BLOCKS_OPENED()) {
                return;
            }
            reader.advance_line();
            prev_line_blank = [];
            while (true) { // process opened blocks line by line
                let opened_blocks = pc.opened_blocks();
                let l = opened_blocks.length();
                if (l == 0) {
                    break;
                }
                let last_index = l - 1;
                cur_line_blank = [];
                let i = 0;
                while (i < l) {
                    let be = opened_blocks[i];
                    let pl = reader.peek_line();
                    let line = pl.line;
                    if (line == null) {
                        self.close_blocks(last_index, 0, reader, pc);
                        reader.advance_line();
                        return;
                    }
                    cur_line_blank.push(root.util.is_blank(line));
                    let be_node = be.node;
                    let be_parser = be.parser;
                    // If node is a paragraph, p.openBlocks determines whether it is continuable.
                    // So we do not process paragraphs here.
                    if (be_node != null && be_parser != null && !root.ast.is_paragraph(be_node)) {
                        let state = be_parser.do_continue(be_node, reader, pc);
                        if ((state & CONTINUE()) != 0) {
                            // When current node is a container block and has no children,
                            // we try to open new child nodes
                            if ((state & HAS_CHILDREN()) != 0 && i == last_index) {
                                let is_blank = is_blank_line(i + 1, prev_line_blank);
                                self.open_blocks(be_node, is_blank, reader, pc);
                                break;
                            }
                            i += 1;
                            continue;
                        }
                    }
                    // current node may be closed or lazy continuation
                    let is_blank = is_blank_line(i, prev_line_blank);
                    let this_parent = parent;
                    if (i != 0) {
                        let pn = opened_blocks[i - 1].node;
                        if (pn != null) {
                            this_parent = pn;
                        }
                    }
                    let last_node = opened_blocks[last_index].node;
                    let result = self.open_blocks(this_parent, is_blank, reader, pc);
                    if (result != PARAGRAPH_CONTINUATION()) {
                        // lastNode is a paragraph and was transformed by the paragraph
                        // transformers.
                        //
                        // Go reads `openedBlocks[lastIndex]` through the stale
                        // slice header, whose backing array was overwritten in
                        // place by the append in openBlocks. BAML arrays do not
                        // alias like that, so consult the current list instead.
                        let cur_blocks = pc.opened_blocks();
                        let replaced = if (last_index < cur_blocks.length()) {
                            !root.ast.same_node(cur_blocks[last_index].node, last_node)
                        } else {
                            true
                        };
                        if (replaced) {
                            last_index -= 1;
                        }
                        self.close_blocks(last_index, i, reader, pc);
                    }
                    break;
                }

                reader.advance_line();
                let tmp = prev_line_blank;
                prev_line_blank = cur_line_blank;
                cur_line_blank = tmp;
            }
        }
    }

    /// Go's `walkBlock(block, cb)` with the `parseBlock` callback inlined.
    function walk_block(self, block: root.ast.Node, block_reader: root.text.BlockReader, pc: Context) -> void {
        let c = block.first_child();
        while (c != null) {
            self.walk_block(c, block_reader, pc);
            c = c.next_sibling();
        }
        self.parse_block(block_reader, block, pc);
    }

    function parse_block(self, block: root.text.BlockReader, parent: root.ast.Node, pc: Context) -> void {
        let parent_source: root.text.Segment[] = match (parent) {
            let bn: root.ast.BlockNode => bn.source(),
            _ => [],
        };
        if (parent_source.length() == 0) {
            return;
        }
        let escaped = false;
        let source = block.source();
        let decoder = block.decoder();
        block.reset(parent_source);
        while (true) {
            // retry:
            let pl = block.peek_line();
            let line = pl.line ?? root.util.new_bytes();
            if (line.length() == 0) {
                break;
            }
            let line_length = line.length();
            let line_break_flags = 0;
            if (line[line_length - 1] == 10) {
                // end is the length of the line's content, excluding the
                // trailing newline sequence ("\n" or "\r\n").
                let end = line_length - 1;
                if (end > 0 && line[end - 1] == 13) {
                    end -= 1;
                }
                if (end > 0 && line[end - 1] == 92 && (end < 2 || line[end - 2] != 92)) {
                    // ends with an unescaped backslash: a hard, visible line break.
                    line_length = end - 1;
                    line_break_flags = LINE_BREAK_HARD() | LINE_BREAK_VISIBLE();
                } else if (end > 1 && line[end - 1] == 32 && line[end - 2] == 32) {
                    // ends with two or more trailing spaces: a hard line break.
                    line_length = end - 2;
                    line_break_flags = LINE_BREAK_HARD();
                } else {
                    // See https://spec.commonmark.org/0.30/#soft-line-breaks
                    line_break_flags = LINE_BREAK_SOFT();
                }
            }

            let start_pos0 = block.position();
            let l = start_pos0.line;
            let start_position = start_pos0.segment;
            let n = 0;
            let did_retry = false;
            let i = 0;
            while (i < line_length) {
                let c = line[i];
                if (c == 10) {
                    break;
                }
                if (i == 0 || self.triggerable[c]) {
                    let is_space = char_is_space_flag(c);
                    let is_punct = root.util.is_punct(c);
                    if ((is_punct && !escaped) || (is_space && (!escaped || !self.escaped_space)) || i == 0) {
                        let parser_char = c;
                        if (is_space || (i == 0 && !is_punct)) {
                            parser_char = 32;
                        }
                        let ips = self.inline_parsers[parser_char];
                        if (ips.length() != 0) {
                            block.advance(n);
                            n = 0;
                            let saved = block.position();
                            if (i != 0) {
                                let current_position = block.position().segment;
                                merge_or_append_text_segment(parent, start_position.between(current_position), decoder);
                                start_position = block.position().segment;
                            }
                            let inline_node: root.ast.Node? = null;
                            for (let ip in ips) {
                                let parsed = ip.parse(parent, block, pc);
                                if (parsed != null) {
                                    if (parsed.pos() < 0) {
                                        parsed.set_pos(start_position.start);
                                    }
                                    inline_node = parsed;
                                    break;
                                }
                                block.set_position(saved.line, saved.segment);
                            }
                            if (inline_node != null) {
                                if (!is_nil_node(inline_node)) {
                                    parent.append_child(inline_node);
                                }
                                did_retry = true;
                                break;
                            }
                        }
                    }
                }
                if (escaped) {
                    escaped = false;
                    n += 1;
                    i += 1;
                    continue;
                }

                if (c == 92) {
                    escaped = true;
                    n += 1;
                    i += 1;
                    continue;
                }

                escaped = false;
                n += 1;
                i += 1;
            }
            if (did_retry) {
                continue;
            }
            if (n != 0) {
                block.advance(n);
            }
            let cur = block.position();
            if (l != cur.line) {
                continue;
            }
            let diff = start_position.between(cur.segment);
            let t = if ((line_break_flags & (LINE_BREAK_HARD() | LINE_BREAK_VISIBLE())) == (LINE_BREAK_HARD() | LINE_BREAK_VISIBLE())) {
                root.ast.new_text(root.text.new_single_line_value_from_segment(diff, decoder))
            } else {
                root.ast.new_text(root.text.new_single_line_value_from_segment(diff.trim_right_space(source), decoder))
            };
            t.set_soft_line_break((line_break_flags & LINE_BREAK_SOFT()) != 0);
            t.set_hard_line_break((line_break_flags & LINE_BREAK_HARD()) != 0);
            parent.append_child(t);
            block.advance_line();
        }

        process_delimiters(null, pc);
        for (let ip in self.close_blockers) {
            ip.close_block(parent, block, pc);
        }
    }
}

class ParseConfig {
    context: Context?,
    do_pp: bool,
    pp_opts: root.ast.PrettyPrintOption[],
}

/// ParseOption is a functional option type for the Parse method.
type ParseOption = (c: ParseConfig) -> void throws never

/// WithContext is a functional option that sets a custom Context for the Parse method.
function with_context(ctx: Context) -> ParseOption {
    (c: ParseConfig) -> void {
        c.context = ctx;
    }
}

/// WithPrettyPrint is a functional option that prints the AST tree to stdout for debugging purposes.
function with_pretty_print(opts: root.ast.PrettyPrintOption[] = []) -> ParseOption {
    (c: ParseConfig) -> void {
        c.do_pp = true;
        c.pp_opts = opts;
    }
}

// blockOpenResult
function PARAGRAPH_CONTINUATION() -> int {
    1
}

function NEW_BLOCKS_OPENED() -> int {
    2
}

function NO_BLOCKS_OPENED() -> int {
    3
}

function is_blank_line(level: int, prev_line_blank: bool[]) -> bool {
    let n = prev_line_blank.length();
    if (n == 0) {
        return false;
    }
    let lv = level;
    if (lv >= n) {
        lv = n - 1;
    }
    prev_line_blank[lv]
}

function LINE_BREAK_HARD() -> int {
    1
}

function LINE_BREAK_SOFT() -> int {
    2
}

function LINE_BREAK_VISIBLE() -> int {
    4
}

/// Go's `charFlags[c] & charFlagSpace`: a space other than '\r' and '\n'.
function char_is_space_flag(c: int) -> bool {
    root.util.is_space(c) && c != 13 && c != 10
}

// ---------------------------------------------------------------------------
// Extension / CommonMark
// ---------------------------------------------------------------------------

/// Extension is an interface that represents an extension for the parser.
interface Extension {
    /// ParserOptions returns a list of parser options to be applied to the parser.
    function parser_options(self, cfg: Config) -> Option[] throws never
}

/// Go's unexported `commonMark` extension.
class CommonMarkExtension {
    opts: Option[],

    implements Extension {
        function parser_options(self, cfg0: Config) -> Option[] {
            let cfg = cfg0;
            if (self.opts.length() != 0) {
                let this_config = cfg0.copy();
                for (let opt in self.opts) {
                    opt.set_parser_option(this_config);
                }
                cfg = this_config;
            }

            let hopts: HeadingOption[] = [];
            if (cfg.attribute) {
                hopts.push(with_attribute());
            }
            if (cfg.auto_heading_id) {
                hopts.push(with_auto_heading_id());
            }
            let eopts: EmphasisOption[] = [];
            let pdf = cfg.parse_delimiter_func;
            if (pdf != null) {
                eopts.push(with_parse_delimiter_func(pdf));
            }
            // BAML: a statement-initial `[` after a `}` parses as an index
            // expression, so bind the result first.
            let result: Option[] = [
                with_block_parsers([
                    root.util.prioritized(new_setext_heading_parser(opts = hopts), 100),
                    root.util.prioritized(new_thematic_break_parser(), 200),
                    root.util.prioritized(new_list_parser(), 300),
                    root.util.prioritized(new_list_item_parser(), 400),
                    root.util.prioritized(new_code_block_parser(), 500),
                    root.util.prioritized(new_atx_heading_parser(opts = hopts), 600),
                    root.util.prioritized(new_fenced_code_block_parser(), 700),
                    root.util.prioritized(new_blockquote_parser(), 800),
                    root.util.prioritized(new_html_block_parser(), 900),
                    root.util.prioritized(new_paragraph_parser(), 1000),
                ]),
                with_inline_parsers([
                    root.util.prioritized(new_code_span_parser(), 100),
                    root.util.prioritized(new_link_parser(), 200),
                    root.util.prioritized(new_auto_link_parser(), 300),
                    root.util.prioritized(new_raw_html_parser(), 400),
                    root.util.prioritized(new_emphasis_parser(opts = eopts), 500),
                ]),
                with_paragraph_transformers([
                    root.util.prioritized(link_reference_paragraph_transformer(), 100),
                ]),
            ];
            result
        }
    }
}

/// NewCommonMark returns a new CommonMark extension.
function new_common_mark(opts: Option[] = []) -> Extension {
    CommonMarkExtension { opts: opts }
}

function merge_or_replace_text_segment(parent: root.ast.Node, n: root.ast.Node, s: root.text.Segment, decoder: root.text.Decoder?) -> void {
    let prev = n.previous_sibling();
    let merged = false;
    if (prev != null) {
        match (prev) {
            let t: root.ast.Text => {
                if (!t.value.is_owned() && t.value.index().stop == s.start && !t.soft_line_break()) {
                    t.value = t.value.with_stop(s.stop);
                    parent.remove_child(n);
                    merged = true;
                }
            }
            _ => {}
        }
    }
    if (!merged) {
        parent.replace_child(n, root.ast.new_text(root.text.new_single_line_value_from_segment(s, decoder)));
    }
}

function merge_or_append_text_segment(parent: root.ast.Node, s: root.text.Segment, decoder: root.text.Decoder?) -> void {
    let last = parent.last_child();
    if (last != null) {
        match (last) {
            let t: root.ast.Text => {
                if (!t.value.is_owned() && t.value.index().stop == s.start && !t.soft_line_break()) {
                    t.value = t.value.with_stop(s.stop);
                    return;
                }
            }
            _ => {}
        }
    }
    parent.append_child(root.ast.new_text(root.text.new_single_line_value_from_segment(s, decoder)));
}

/// CommonMark is a commonmark compliant extension.
/// This extension adds default block parsers, inline parsers, and paragraph transformers to the parser.
///
/// Block parsers:
///
///   - SetextHeadingParser, 100
///   - ThematicBreakParser, 200
///   - ListParser, 300
///   - ListItemParser, 400
///   - CodeBlockParser, 500
///   - ATXHeadingParser, 600
///   - FencedCodeBlockParser, 700
///   - BlockquoteParser, 800
///   - HTMLBlockParser, 900
///   - ParagraphParser, 1000
///
/// Inline parsers:
///
///   - CodeSpanParser, 100
///   - LinkParser, 200
///   - AutoLinkParser, 300
///   - RawHTMLParser, 400
///   - EmphasisParser, 500
///
/// Paragraph transformers:
///
///   - LinkReferenceParagraphTransformer, 100
function common_mark() -> Extension {
    CommonMarkExtension { opts: [] }
}
