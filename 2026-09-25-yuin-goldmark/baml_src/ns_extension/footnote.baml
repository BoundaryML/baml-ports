// Port of goldmark extension/footnote.go.
//
// Naming notes (Go identifiers whose snake_case/CamelCase forms collide):
// - Go `newFootnoteParser` (unexported inline-parser constructor) collides with
//   `NewFootnoteParser` (the parser.Extension); it is `new_footnote_inline_parser`.
// - Go types `footnotes` / `Footnotes` collide; the struct is `FootnotesImpl`.
// - Go `footnoteDefInfo` / `defInfo` would both become `FootnoteDefInfo`-ish;
//   `defInfo` is `FootnoteDefRenderInfo`, `defData` is `FootnoteDefData`.
// - Package-level vars (`FootnoteParser`, `FootnoteHTMLRenderer`, context keys)
//   are zero-argument functions.

// {{{ Data

/// A FootnoteReference interface represents a footnote reference data object.
interface FootnoteReference {
    /// Label returns the label of the footnote reference.
    function label(self) -> uint8array throws never

    /// Index returns the display index of the referenced footnote definition.
    function index(self) -> int throws never

    /// RefIndex returns the position of this reference among all references
    /// to the same footnote definition (0-based).
    function ref_index(self) -> int throws never
}

/// Go's unexported `footnoteRefInfo`.
class FootnoteRefInfo {
    lbl: uint8array,
    idx: int,
    ref_idx: int,

    implements FootnoteReference {
        function label(self) -> uint8array {
            self.lbl
        }

        function index(self) -> int {
            self.idx
        }

        function ref_index(self) -> int {
            self.ref_idx
        }
    }
}

function new_footnote_reference_from_node(node: root.extension.ast.FootnoteReference, src: uint8array) -> FootnoteReference {
    FootnoteRefInfo {
        lbl: node.label.bytes(src),
        idx: -1,
        ref_idx: -1,
    }
}

/// A FootnoteDefinition interface represents a footnote definition data object.
interface FootnoteDefinition {
    /// Label returns the label of the footnote definition.
    function label(self) -> uint8array throws never
}

/// Go's unexported `footnoteDefInfo`.
class FootnoteDefInfo {
    lbl: uint8array,

    implements FootnoteDefinition {
        function label(self) -> uint8array {
            self.lbl
        }
    }
}

function new_footnote_definition_from_node(node: root.extension.ast.FootnoteDefinition, src: uint8array) -> FootnoteDefinition {
    FootnoteDefInfo { lbl: node.label.bytes(src) }
}

/// Footnotes manages footnote definitions and references during parsing.
interface Footnotes {
    /// AddDefinition registers a footnote definition.
    function add_definition(self, def: FootnoteDefinition) -> void throws never

    /// AddReference registers a footnote reference.
    /// It returns false if no matching definition is found for the reference's label.
    function add_reference(self, ref: FootnoteReference) -> bool throws never

    /// FindByLabel returns the FootnoteDefinition matching the given label, or nil.
    function find_by_label(self, label: uint8array) -> FootnoteDefinition? throws never
}

/// Go's unexported `defData`.
class FootnoteDefData {
    def: FootnoteDefinition,
    index: int,
    references: int[],
}

/// Go's unexported `footnotes`.
class FootnotesImpl {
    definition_index: int,
    defs_by_label: map<string, FootnoteDefData>,

    implements Footnotes {
        function add_definition(self, def: FootnoteDefinition) -> void {
            let key = root.util.bytes_to_string(def.label());
            if (self.defs_by_label.has(key)) {
                return;
            }
            self.defs_by_label[key] = FootnoteDefData { def: def, index: -1, references: [] };
        }

        function add_reference(self, ref: FootnoteReference) -> bool {
            let key = root.util.bytes_to_string(ref.label());
            let dd = self.defs_by_label.get(key);
            if (dd == null) {
                return false;
            }
            if (dd.index < 0) {
                dd.index = self.definition_index;
                self.definition_index += 1;
            }
            match (ref) {
                let lr: FootnoteRefInfo => {
                    lr.idx = dd.index;
                    lr.ref_idx = dd.references.length();
                    dd.references.push(lr.ref_idx);
                }
                _ => {
                    // Go: `ref.(*footnoteRefInfo)` panics for other implementations.
                    baml.sys.panic("footnotes: unsupported FootnoteReference implementation");
                }
            }
            true
        }

        function find_by_label(self, label: uint8array) -> FootnoteDefinition? {
            let key = root.util.bytes_to_string(label);
            let dd = self.defs_by_label.get(key);
            if (dd == null) {
                return null;
            }
            dd.def
        }
    }
}

function new_footnotes() -> FootnotesImpl {
    FootnotesImpl { definition_index: 1, defs_by_label: {} }
}

function footnote_context_key() -> root.parser.ContextKey {
    root.parser.new_context_key("extension.footnotes")
}

/// ContextFootnotes returns the Footnotes stored in the given parser.Context.
/// If no Footnotes have been created yet, it creates one and stores it.
function context_footnotes(pc: root.parser.Context) -> Footnotes {
    let v = pc.compute_if_absent(footnote_context_key(), () -> unknown {
        new_footnotes()
    });
    match (v) {
        let f: Footnotes => f,
        _ => {
            baml.sys.panic("extension.footnotes: context value is not Footnotes");
            new_footnotes()
        }
    }
}

// }}}

// {{{ Renderer context helpers

function footnote_defs_key() -> root.renderer.ContextKey {
    root.renderer.new_context_key("extension.footnoteDefs")
}

function footnote_defs_info_key() -> root.renderer.ContextKey {
    root.renderer.new_context_key("extension.footnoteDefsInfo")
}

/// Go's unexported `defInfo`.
class FootnoteDefRenderInfo {
    index: int,
    references: int[],
}

/// Holder for Go's `map[string]*ast.FootnoteDefinition` stored in the render
/// context (BAML: wrapped in a class so it can be recovered from `unknown`
/// with a `match` on a class type).
class FootnoteDefsMap {
    m: map<string, root.extension.ast.FootnoteDefinition>,
}

/// Holder for Go's `map[string]*defInfo` stored in the render context.
class FootnoteDefsInfoMap {
    m: map<string, FootnoteDefRenderInfo>,
}

// }}}

// {{{ Block parser

/// Go's unexported `footnoteBlockParser`.
class FootnoteBlockParser {
    implements root.parser.BlockParser {
        function trigger(self) -> uint8array? {
            root.util.bytes_of([91]) // '['
        }

        function open(self, parent: root.ast.Node, reader: root.text.Reader, pc: root.parser.Context) -> root.parser.OpenResult {
            let pl = reader.peek_line();
            let line = pl.line ?? root.util.new_bytes();
            let segment = pl.segment;
            let pos = pc.block_offset();
            // Go indexes `line[pos]` unchecked; guard the bounds instead of panicking.
            if (pos < 0 || pos >= line.length()) {
                return root.parser.OpenResult { node: null, state: root.parser.NO_CHILDREN() };
            }
            if (line[pos] != 91) { // '['
                return root.parser.OpenResult { node: null, state: root.parser.NO_CHILDREN() };
            }
            pos += 1;
            if (pos > line.length() - 1) {
                return root.parser.OpenResult { node: null, state: root.parser.NO_CHILDREN() };
            }
            if (line[pos] != 94) { // '^'
                return root.parser.OpenResult { node: null, state: root.parser.NO_CHILDREN() };
            }
            let open = pos + 1;
            let closure = find_label_closure(line.slice(pos + 1, line.length()));
            let closes = pos + 1 + closure;
            let next = closes + 1;
            if (closure > -1) {
                if (next >= line.length()) {
                    return root.parser.OpenResult { node: null, state: root.parser.NO_CHILDREN() };
                }
                if (line[next] != 58) { // ':'
                    return root.parser.OpenResult { node: null, state: root.parser.NO_CHILDREN() };
                }
            } else {
                return root.parser.OpenResult { node: null, state: root.parser.NO_CHILDREN() };
            }
            let padding = segment.padding;
            let label_start = segment.start + open - padding;
            let label_stop = segment.start + closes - padding;
            let label = root.text.new_single_line_value_from_index(root.text.new_index(label_start, label_stop), reader.decoder());
            if (root.util.is_blank(label.bytes(reader.source()))) {
                return root.parser.OpenResult { node: null, state: root.parser.NO_CHILDREN() };
            }
            let item = root.extension.ast.new_footnote_definition(label);

            pos = next + 1 - padding;
            if (pos >= line.length()) {
                reader.advance(pos);
                return root.parser.OpenResult { node: item, state: root.parser.NO_CHILDREN() };
            }
            reader.advance_and_set_padding(pos, padding);
            root.parser.OpenResult { node: item, state: root.parser.HAS_CHILDREN() }
        }

        function do_continue(self, node: root.ast.Node, reader: root.text.Reader, pc: root.parser.Context) -> root.parser.State {
            let line = reader.peek_line().line ?? root.util.new_bytes();
            if (root.util.is_blank(line)) {
                return root.parser.CONTINUE() | root.parser.HAS_CHILDREN();
            }
            let ip = root.util.indent_position(line, reader.line_offset(), 4);
            if (ip.pos < 0) {
                return root.parser.CLOSE();
            }
            reader.advance_and_set_padding(ip.pos, ip.padding);
            root.parser.CONTINUE() | root.parser.HAS_CHILDREN()
        }

        function close(self, node: root.ast.Node, reader: root.text.Reader, pc: root.parser.Context) -> void {
            match (node) {
                let fn: root.extension.ast.FootnoteDefinition => {
                    let fns = context_footnotes(pc);
                    fns.add_definition(new_footnote_definition_from_node(fn, reader.source()));
                }
                _ => {}
            }
        }

        function can_interrupt_paragraph(self) -> bool {
            true
        }

        function can_accept_indented_line(self) -> bool {
            false
        }
    }
}

/// Go's unexported `newFootnoteBlockParser`.
function new_footnote_block_parser() -> root.parser.BlockParser {
    FootnoteBlockParser {}
}

// }}}

// {{{ Inline parser

/// Go's unexported `footnoteParser` (the inline parser).
class FootnoteParser {
    implements root.parser.InlineParser {
        function trigger(self) -> uint8array {
            root.util.bytes_of([33, 91]) // '!', '['
        }

        function parse(self, parent: root.ast.Node, block: root.text.Reader, pc: root.parser.Context) -> root.ast.Node? {
            let pl = block.peek_line();
            let line = pl.line ?? root.util.new_bytes();
            let segment = pl.segment;
            let pos = 1;
            if (line.length() > 0) {
                if (line[0] == 33) { // '!'
                    pos += 1;
                }
            }
            if (pos >= line.length()) {
                return null;
            }
            if (line[pos] != 94) { // '^'
                return null;
            }
            pos += 1;
            if (pos >= line.length()) {
                return null;
            }
            let open = pos;
            let closure = find_label_closure(line.slice(pos, line.length()));
            if (closure < 0) {
                return null;
            }
            let closes = pos + closure;
            let label = root.text.new_single_line_value_from_index(root.text.new_index(segment.start + open, segment.start + closes), block.decoder());
            block.advance(closes + 1);

            let fns = context_footnotes(pc);
            let ref = root.extension.ast.new_footnote_reference(label);
            let lr = new_footnote_reference_from_node(ref, block.source());
            if (!fns.add_reference(lr)) {
                return null;
            }
            ref.index = lr.index();
            ref.ref_index = lr.ref_index();

            if (line[0] == 33) { // '!'
                parent.append_child(root.ast.new_text(root.text.new_single_line_value_from_index(
                    root.text.new_index(segment.start, segment.start + 1), block.decoder())));
            }

            ref
        }
    }
}

/// Go's unexported `newFootnoteParser` (renamed: collides with NewFootnoteParser).
function new_footnote_inline_parser() -> root.parser.InlineParser {
    FootnoteParser {}
}

function find_label_closure(bs: uint8array) -> int {
    let i = 0;
    let n = bs.length();
    while (i < n) {
        let c = bs[i];
        if (c == 92 && i + 1 < n) { // '\\'
            if (bs[i + 1] == 93) { // ']'
                i += 2;
                continue;
            }
        }
        if (c == 93) { // ']'
            return i;
        }
        i += 1;
    }
    -1
}

// }}}

// {{{ Renderer config and options

/// Signature of Go's `IDPrefixFunction func(gast.Node) []byte` (null = Go nil).
type FootnoteIDPrefixFunction = (n: root.ast.Node) -> uint8array? throws never

/// Go's unexported `footnoteHTMLRendererConfig`.
class FootnoteHTMLRendererConfig {
    xhtml: bool,

    /// Go `IDPrefix []byte`; null is Go nil.
    id_prefix: uint8array?,

    id_prefix_function: FootnoteIDPrefixFunction?,

    link_title: uint8array,

    backlink_title: uint8array,

    link_class: uint8array,

    backlink_class: uint8array,

    backlink_html: uint8array,
}

/// FootnoteHTMLRendererOption interface is a functional option interface for the extension.
interface FootnoteHTMLRendererOption {
    function apply_footnote_html_renderer_option(self, c: FootnoteHTMLRendererConfig) -> void throws never
}

/// Go's `[T []byte | string]` generic string-or-bytes option argument.
function footnote_option_bytes(a: uint8array | string) -> uint8array {
    match (a) {
        let s: string => s.to_utf8(),
        let b: uint8array => b,
    }
}

class WithFootnoteIDPrefix {
    value: uint8array,

    implements FootnoteHTMLRendererOption {
        function apply_footnote_html_renderer_option(self, c: FootnoteHTMLRendererConfig) -> void {
            c.id_prefix = self.value;
        }
    }
}

/// WithIDPrefix is a functional option that is a prefix for the id attributes generated by footnotes.
function with_id_prefix(a: uint8array | string) -> FootnoteHTMLRendererOption {
    WithFootnoteIDPrefix { value: footnote_option_bytes(a) }
}

class WithFootnoteIDPrefixFunction {
    value: FootnoteIDPrefixFunction,

    implements FootnoteHTMLRendererOption {
        function apply_footnote_html_renderer_option(self, c: FootnoteHTMLRendererConfig) -> void {
            c.id_prefix_function = self.value;
        }
    }
}

/// WithIDPrefixFunction is a functional option that is a prefix for the id attributes
/// generated by footnotes.
function with_id_prefix_function(a: FootnoteIDPrefixFunction) -> FootnoteHTMLRendererOption {
    WithFootnoteIDPrefixFunction { value: a }
}

class WithFootnoteLinkTitle {
    value: uint8array,

    implements FootnoteHTMLRendererOption {
        function apply_footnote_html_renderer_option(self, c: FootnoteHTMLRendererConfig) -> void {
            c.link_title = self.value;
        }
    }
}

/// WithLinkTitle is a functional option that is an optional title attribute for footnote links.
function with_link_title(a: uint8array | string) -> FootnoteHTMLRendererOption {
    WithFootnoteLinkTitle { value: footnote_option_bytes(a) }
}

class WithFootnoteBacklinkTitle {
    value: uint8array,

    implements FootnoteHTMLRendererOption {
        function apply_footnote_html_renderer_option(self, c: FootnoteHTMLRendererConfig) -> void {
            c.backlink_title = self.value;
        }
    }
}

/// WithBacklinkTitle is a functional option that is an optional title attribute
/// for footnote backlinks.
function with_backlink_title(a: uint8array | string) -> FootnoteHTMLRendererOption {
    WithFootnoteBacklinkTitle { value: footnote_option_bytes(a) }
}

class WithFootnoteLinkClass {
    value: uint8array,

    implements FootnoteHTMLRendererOption {
        function apply_footnote_html_renderer_option(self, c: FootnoteHTMLRendererConfig) -> void {
            c.link_class = self.value;
        }
    }
}

/// WithLinkClass is a functional option that is a class for footnote links.
function with_link_class(a: uint8array | string) -> FootnoteHTMLRendererOption {
    WithFootnoteLinkClass { value: footnote_option_bytes(a) }
}

class WithFootnoteBacklinkClass {
    value: uint8array,

    implements FootnoteHTMLRendererOption {
        function apply_footnote_html_renderer_option(self, c: FootnoteHTMLRendererConfig) -> void {
            c.backlink_class = self.value;
        }
    }
}

/// WithBacklinkClass is a functional option that is a class for footnote backlinks.
function with_backlink_class(a: uint8array | string) -> FootnoteHTMLRendererOption {
    WithFootnoteBacklinkClass { value: footnote_option_bytes(a) }
}

class WithFootnoteBacklinkHTML {
    value: uint8array,

    implements FootnoteHTMLRendererOption {
        function apply_footnote_html_renderer_option(self, c: FootnoteHTMLRendererConfig) -> void {
            c.backlink_html = self.value;
        }
    }
}

/// WithBacklinkHTML is an HTML content for footnote backlinks.
function with_backlink_html(a: uint8array | string) -> FootnoteHTMLRendererOption {
    WithFootnoteBacklinkHTML { value: footnote_option_bytes(a) }
}

// }}}

// {{{ Renderer extension

/// Go's `idPrefix` method, shared by the renderer extension and the decorator.
function footnote_id_prefix(config: FootnoteHTMLRendererConfig, node: root.ast.Node) -> uint8array {
    let prefix = config.id_prefix;
    if (prefix != null) {
        return prefix;
    }
    let f = config.id_prefix_function;
    if (f != null) {
        return f(node) ?? root.util.new_bytes();
    }
    root.util.new_bytes()
}

/// Go's unexported `footnoteHTMLRendererExtension`.
class FootnoteHTMLRendererExtension {
    config: FootnoteHTMLRendererConfig,

    function render_footnote_reference(self, w: root.util.BufWriter, source: uint8array, node: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus {
        if (!entering) {
            return root.ast.WalkStatus.WalkContinue;
        }
        let n = match (node) {
            let r: root.extension.ast.FootnoteReference => r,
            _ => {
                return root.ast.WalkStatus.WalkContinue;
            }
        };
        let istr = n.index.to_string();

        let ref_count = 0;
        match (rc.get(footnote_defs_info_key())) {
            let defs_info: FootnoteDefsInfoMap => {
                let info = defs_info.m.get(n.label.str(source));
                if (info != null) {
                    ref_count = info.references.length();
                }
            }
            _ => {}
        }

        w.write_string("<sup id=\"");
        w.write(self.id_prefix(node));
        w.write_string("fnref");
        if (n.ref_index > 0) {
            w.write_string(n.ref_index.to_string());
        }
        w.write_byte(58); // ':'
        w.write_string(istr);
        w.write_string("\"><a href=\"#");
        w.write(self.id_prefix(node));
        w.write_string("fn:");
        w.write_string(istr);
        w.write_string("\" class=\"");
        w.write(apply_footnote_template(self.config.link_class, n.index, ref_count));
        if (self.config.link_title.length() > 0) {
            w.write_string("\" title=\"");
            w.write(root.util.escape_html(apply_footnote_template(self.config.link_title, n.index, ref_count)));
        }
        w.write_string("\" role=\"doc-noteref\">");
        w.write_string(istr);
        w.write_string("</a></sup>");

        root.ast.WalkStatus.WalkContinue
    }

    function render_footnote_definition(self, w: root.util.BufWriter, source: uint8array, node: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus {
        root.ast.WalkStatus.WalkSkipChildren
    }

    function id_prefix(self, node: root.ast.Node) -> uint8array {
        footnote_id_prefix(self.config, node)
    }

    implements root.renderer.Extension<root.renderer.html.Config> {
        function renderer_options(self, c: root.renderer.html.Config) -> root.renderer.html.Option[] {
            if (c.xhtml) {
                self.config.xhtml = true;
            }

            let decorator = FootnoteDecorator { config: self.config };
            // BAML: bound methods are bound to typed locals first (see renderer.baml).
            let r_ref: root.renderer.NodeRendererFuncType = self.render_footnote_reference;
            let r_def: root.renderer.NodeRendererFuncType = self.render_footnote_definition;
            let dec: root.renderer.NodeRendererDecorator = decorator.decorate;
            let nrs: map<string, root.renderer.html.NodeRenderer> = {
                "FootnoteReference": root.renderer.html.node_renderer_func(r_ref),
                "FootnoteDefinition": root.renderer.html.node_renderer_func(r_def),
            };
            let result: root.renderer.html.Option[] = [
                root.renderer.html.with_node_renderers(nrs),
                root.renderer.html.with_node_renderer_decorator(root.ast.kind_document(), dec),
            ];
            result
        }
    }
}

/// NewFootnoteHTMLRenderer returns a new html.Extension for footnotes.
function new_footnote_html_renderer(opts: FootnoteHTMLRendererOption[] = []) -> root.renderer.html.Extension {
    let cfg = FootnoteHTMLRendererConfig {
        xhtml: false,
        id_prefix: null,
        id_prefix_function: null,
        link_title: "".to_utf8(),
        backlink_title: "".to_utf8(),
        link_class: "footnote-ref".to_utf8(),
        backlink_class: "footnote-backref".to_utf8(),
        backlink_html: "&#x21a9;&#xfe0e;".to_utf8(),
    };
    for (let opt in opts) {
        opt.apply_footnote_html_renderer_option(cfg);
    }
    FootnoteHTMLRendererExtension { config: cfg }
}

/// FootnoteHTMLRenderer is a default [html.Extension] for footnotes.
function footnote_html_renderer() -> root.renderer.html.Extension {
    new_footnote_html_renderer()
}

// }}}

// {{{ PostRender hook

/// Go's unexported `footnoteDecorator`.
class FootnoteDecorator {
    config: FootnoteHTMLRendererConfig,

    function decorate(self, next: root.renderer.NodeRenderer) -> root.renderer.NodeRenderer {
        // Go returns a closure; here a small class holds (decorator, next).
        FootnoteDecoratedRenderer { d: self, next: next }
    }

    function render_definition(self, w: root.util.BufWriter, source: uint8array, def: root.extension.ast.FootnoteDefinition, info: FootnoteDefRenderInfo, rc: root.renderer.Context) -> void {
        let istr = info.index.to_string();
        w.write_string("<li id=\"");
        w.write(self.id_prefix(def));
        w.write_string("fn:");
        w.write_string(istr);
        w.write_string("\"");
        if (def.attributes() != null) {
            root.renderer.html.render_attributes(w, source, def, root.renderer.html.list_item_attribute_filter(), rc);
        }
        w.write_string(">\n");

        let last_para: root.ast.Node? = null;
        let lc = def.last_child();
        if (lc != null) {
            if (root.ast.is_paragraph(lc)) {
                last_para = lc;
            }
        }

        let child = def.first_child();
        while (child != null) {
            if (last_para != null && root.ast.same_node(child, last_para)) {
                self.render_paragraph_with_backlinks(w, source, child, info, rc);
            } else {
                rc.render(w, source, child);
            }
            child = child.next_sibling();
        }

        if (last_para == null && info.references.length() > 0) {
            self.render_backlinks(w, def, info);
        }

        w.write_string("</li>\n");
    }

    function render_paragraph_with_backlinks(self, w: root.util.BufWriter, source: uint8array, para: root.ast.Node, info: FootnoteDefRenderInfo, rc: root.renderer.Context) -> void {
        w.write_string("<p>");
        let child = para.first_child();
        while (child != null) {
            rc.render(w, source, child);
            child = child.next_sibling();
        }
        self.render_backlinks(w, para, info);
        w.write_string("</p>\n");
    }

    function render_backlinks(self, w: root.util.BufWriter, node: root.ast.Node, info: FootnoteDefRenderInfo) -> void {
        let istr = info.index.to_string();
        let ref_count = info.references.length();
        for (let ref_idx in info.references) {
            w.write_string("&#160;<a href=\"#");
            w.write(self.id_prefix(node));
            w.write_string("fnref");
            if (ref_idx > 0) {
                w.write_string(ref_idx.to_string());
            }
            w.write_byte(58); // ':'
            w.write_string(istr);
            w.write_string("\" class=\"");
            w.write(apply_footnote_template(self.config.backlink_class, info.index, ref_count));
            if (self.config.backlink_title.length() > 0) {
                w.write_string("\" title=\"");
                w.write(root.util.escape_html(apply_footnote_template(self.config.backlink_title, info.index, ref_count)));
            }
            w.write_string("\" role=\"doc-backlink\">");
            w.write(apply_footnote_template(self.config.backlink_html, info.index, ref_count));
            w.write_string("</a>");
        }
    }

    function id_prefix(self, node: root.ast.Node) -> uint8array {
        footnote_id_prefix(self.config, node)
    }
}

/// Go's `defEntry` (local type inside Decorate).
class FootnoteDefEntry {
    node: root.extension.ast.FootnoteDefinition,
    info: FootnoteDefRenderInfo,
}

/// The NodeRenderer returned by Go's `footnoteDecorator.Decorate` closure.
class FootnoteDecoratedRenderer {
    d: FootnoteDecorator,
    next: root.renderer.NodeRenderer,

    function collect(self, node: root.ast.Node, source: uint8array, rc: root.renderer.Context) -> void {
        let defs_map: map<string, root.extension.ast.FootnoteDefinition> = {};
        let infos: map<string, FootnoteDefRenderInfo> = {};
        root.ast.walk(node, (nd: root.ast.Node, entering: bool) -> root.ast.WalkStatus {
            if (!entering) {
                return root.ast.WalkStatus.WalkContinue;
            }
            match (nd) {
                let def: root.extension.ast.FootnoteDefinition => {
                    let label = def.label.str(source);
                    defs_map[label] = def;
                    if (!infos.has(label)) {
                        infos[label] = FootnoteDefRenderInfo { index: -1, references: [] };
                    }
                    return root.ast.WalkStatus.WalkSkipChildren;
                }
                let ref: root.extension.ast.FootnoteReference => {
                    let label = ref.label.str(source);
                    let info = infos.get(label);
                    if (info == null) {
                        let fresh = FootnoteDefRenderInfo { index: -1, references: [] };
                        infos[label] = fresh;
                        info = fresh;
                    }
                    if (info.index < 0) {
                        info.index = ref.index;
                    }
                    info.references.push(ref.ref_index);
                }
                _ => {}
            }
            root.ast.WalkStatus.WalkContinue
        });
        rc.set(footnote_defs_key(), FootnoteDefsMap { m: defs_map });
        rc.set(footnote_defs_info_key(), FootnoteDefsInfoMap { m: infos });
    }

    implements root.renderer.NodeRenderer {
        function render(self, w: root.util.BufWriter, source: uint8array, node: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus {
            if (entering) {
                self.collect(node, source, rc);
                return self.next.render(w, source, node, entering, rc);
            }

            let defs_map = match (rc.get(footnote_defs_key())) {
                let m: FootnoteDefsMap => m.m,
                _ => {
                    return self.next.render(w, source, node, entering, rc);
                }
            };
            let infos = match (rc.get(footnote_defs_info_key())) {
                let m: FootnoteDefsInfoMap => m.m,
                _ => {
                    return self.next.render(w, source, node, entering, rc);
                }
            };

            let referenced: FootnoteDefEntry[] = [];
            for (let label in infos.keys()) {
                let info = infos[label];
                if (info.references.length() > 0) {
                    let def = defs_map.get(label);
                    if (def != null) {
                        referenced.push(FootnoteDefEntry { node: def, info: info });
                    }
                }
            }
            if (referenced.length() == 0) {
                return self.next.render(w, source, node, entering, rc);
            }

            referenced.sort_by_key((e: FootnoteDefEntry) -> int { e.info.index });

            w.write_string("<div class=\"footnotes\" role=\"doc-endnotes\">\n");
            if (self.d.config.xhtml) {
                w.write_string("<hr />\n");
            } else {
                w.write_string("<hr>\n");
            }
            w.write_string("<ol>\n");

            for (let entry in referenced) {
                self.d.render_definition(w, source, entry.node, entry.info, rc);
            }

            w.write_string("</ol>\n");
            w.write_string("</div>\n");

            self.next.render(w, source, node, entering, rc)
        }
    }
}

// }}}

// {{{ Parser extension

/// Go's unexported `footnoteParserExtension`.
class FootnoteParserExtension {
    implements root.parser.Extension {
        function parser_options(self, cfg: root.parser.Config) -> root.parser.Option[] {
            let result: root.parser.Option[] = [
                root.parser.with_block_parsers([
                    root.util.prioritized(new_footnote_block_parser(), 999),
                ]),
                root.parser.with_inline_parsers([
                    root.util.prioritized(new_footnote_inline_parser(), 101),
                ]),
            ];
            result
        }
    }
}

/// NewFootnoteParser returns a new parser.Extension for parsing PHP Markdown Extra footnotes.
function new_footnote_parser() -> root.parser.Extension {
    FootnoteParserExtension {}
}

/// FootnoteParser is a default [parser.Extension] for footnotes.
function footnote_parser() -> root.parser.Extension {
    new_footnote_parser()
}

// }}}

function apply_footnote_template(b: uint8array, index: int, ref_count: int) -> uint8array {
    let fast = true;
    let i = 1;
    let n = b.length();
    while (i < n) {
        let c = b[i];
        if (b[i - 1] == 94 && c == 94) { // '^'
            fast = false;
            break;
        }
        if (b[i - 1] == 37 && c == 37) { // '%'
            fast = false;
            break;
        }
        i += 1;
    }
    if (fast) {
        return b;
    }
    let istr = index.to_string().to_utf8();
    let rs = ref_count.to_string().to_utf8();
    let ret = root.util.bytes_replace_all(b, "^^".to_utf8(), istr);
    root.util.bytes_replace_all(ret, "%%".to_utf8(), rs)
}
