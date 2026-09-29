// Port of goldmark extension/definition_list.go.
//
// Porting notes:
// - Go's package-level singletons (`defaultDefinitionListParser`, ...,
//   `DefinitionListParser`, `DefinitionListHTMLRenderer`) and attribute
//   filter variables are zero-argument functions.

/// Go's unexported `definitionListParser`.
class DefinitionListParser {
    implements root.parser.BlockParser {
        function trigger(self) -> uint8array? {
            root.util.bytes_of([58]) // ':'
        }

        function open(self, parent: root.ast.Node, reader: root.text.Reader, pc: root.parser.Context) -> root.parser.OpenResult {
            let none = root.parser.OpenResult { node: null, state: root.parser.NO_CHILDREN() };
            match (parent) {
                let _dl: root.extension.ast.DefinitionList => {
                    return none;
                }
                _ => {}
            }
            let line = reader.peek_line().line ?? root.util.new_bytes();
            let pos = pc.block_offset();
            let indent = pc.block_indent();
            if (pos < 0) {
                return none;
            }
            if (line[pos] != 58 || indent != 0) { // ':'
                return none;
            }

            let last = parent.last_child();
            // need 1 or more spaces after ':'
            let w = root.util.indent_width(line.slice(pos + 1, line.length()), pos + 1).width;
            if (w < 1) {
                return none;
            }
            if (w >= 8) { // starts with indented code
                w = 5;
            }
            w += pos + 1; /* 1 = ':' */

            if (last == null) {
                return none;
            }
            let status = root.parser.HAS_CHILDREN();
            match (last) {
                let para: root.ast.Paragraph => {
                    let prev = last.previous_sibling();
                    let existing: root.extension.ast.DefinitionList? = null;
                    if (prev != null) {
                        match (prev) {
                            let dl: root.extension.ast.DefinitionList => {
                                existing = dl;
                            }
                            _ => {}
                        }
                    }
                    if (existing != null) { // is not first item
                        existing.set_offset(w);
                        existing.set_temporary_paragraph(para);
                        return root.parser.OpenResult { node: existing, state: status };
                    }
                    // is first item
                    let list = root.extension.ast.new_definition_list();
                    list.set_offset(w);
                    list.set_temporary_paragraph(para);
                    status = status | root.parser.REQUIRE_PARAGRAPH();
                    return root.parser.OpenResult { node: list, state: status };
                }
                let list: root.extension.ast.DefinitionList => { // multiple description
                    list.set_offset(w);
                    list.set_temporary_paragraph(null);
                    return root.parser.OpenResult { node: list, state: status };
                }
                _ => {
                    return none;
                }
            }
        }

        function do_continue(self, node: root.ast.Node, reader: root.text.Reader, pc: root.parser.Context) -> root.parser.State {
            let line = reader.peek_line().line ?? root.util.new_bytes();
            if (root.util.is_blank(line)) {
                return root.parser.CONTINUE() | root.parser.HAS_CHILDREN();
            }
            let offset = match (node) {
                let list: root.extension.ast.DefinitionList => list.offset(),
                _ => 0,
            };
            let w = root.util.indent_width(line, reader.line_offset()).width;
            if (w < offset) {
                return root.parser.CLOSE();
            }
            let ip = root.util.indent_position(line, reader.line_offset(), offset);
            reader.advance_and_set_padding(ip.pos, ip.padding);
            root.parser.CONTINUE() | root.parser.HAS_CHILDREN()
        }

        function close(self, node: root.ast.Node, reader: root.text.Reader, pc: root.parser.Context) -> void {
            // nothing to do
        }

        function can_interrupt_paragraph(self) -> bool {
            true
        }

        function can_accept_indented_line(self) -> bool {
            false
        }
    }
}

function new_definition_list_parser_impl() -> root.parser.BlockParser {
    DefinitionListParser {}
}

/// Go's unexported `definitionDescriptionParser`.
class DefinitionDescriptionParser {
    implements root.parser.BlockParser {
        function trigger(self) -> uint8array? {
            root.util.bytes_of([58]) // ':'
        }

        function open(self, parent: root.ast.Node, reader: root.text.Reader, pc: root.parser.Context) -> root.parser.OpenResult {
            let none = root.parser.OpenResult { node: null, state: root.parser.NO_CHILDREN() };
            let line = reader.peek_line().line ?? root.util.new_bytes();
            let pos = pc.block_offset();
            let indent = pc.block_indent();
            if (pos < 0) {
                return none;
            }
            if (line[pos] != 58 || indent != 0) { // ':'
                return none;
            }
            let list: root.extension.ast.DefinitionList? = match (parent) {
                let dl: root.extension.ast.DefinitionList => dl,
                _ => null,
            };
            if (list == null) {
                return none;
            }
            let para = list.temporary_paragraph();
            list.set_temporary_paragraph(null);
            if (para != null) {
                let lines = para.source();
                let l = lines.length();
                let i = 0;
                while (i < l) {
                    let term = root.extension.ast.new_definition_term();
                    term.append_source(lines[i].trim_right_space(reader.source()));
                    list.append_child(term);
                    i += 1;
                }
                let pp = para.parent();
                if (pp != null) {
                    pp.remove_child(para);
                }
            }
            let ip = root.util.indent_position(line.slice(pos + 1, line.length()), pos + 1, list.offset() - pos - 1);
            reader.advance_and_set_padding(ip.pos + 1, ip.padding);

            root.parser.OpenResult { node: root.extension.ast.new_definition_description(), state: root.parser.HAS_CHILDREN() }
        }

        function do_continue(self, node: root.ast.Node, reader: root.text.Reader, pc: root.parser.Context) -> root.parser.State {
            // definitionListParser detects end of the description.
            // so this method will never be called.
            root.parser.CONTINUE() | root.parser.HAS_CHILDREN()
        }

        function close(self, node: root.ast.Node, reader: root.text.Reader, pc: root.parser.Context) -> void {
            match (node) {
                let desc: root.extension.ast.DefinitionDescription => {
                    desc.is_tight = !desc.has_blank_previous_lines();
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

function new_definition_description_parser_impl() -> root.parser.BlockParser {
    DefinitionDescriptionParser {}
}

/// Go's unexported `definitionListHTMLRendererExtension`.
class DefinitionListHTMLRendererExtension {
    function render_definition_list(self, w: root.util.BufWriter, source: uint8array, n: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus {
        if (entering) {
            if (n.attributes() != null) {
                w.write_string("<dl");
                root.renderer.html.render_attributes(w, source, n, definition_list_attribute_filter(), rc);
                w.write_string(">\n");
            } else {
                w.write_string("<dl>\n");
            }
        } else {
            w.write_string("</dl>\n");
        }
        root.ast.WalkStatus.WalkContinue
    }

    function render_definition_term(self, w: root.util.BufWriter, source: uint8array, n: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus {
        if (entering) {
            if (n.attributes() != null) {
                w.write_string("<dt");
                root.renderer.html.render_attributes(w, source, n, definition_term_attribute_filter(), rc);
                w.write_byte(62); // '>'
            } else {
                w.write_string("<dt>");
            }
        } else {
            w.write_string("</dt>\n");
        }
        root.ast.WalkStatus.WalkContinue
    }

    function render_definition_description(self, w: root.util.BufWriter, source: uint8array, node: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus {
        if (entering) {
            let is_tight = match (node) {
                let d: root.extension.ast.DefinitionDescription => d.is_tight,
                _ => false,
            };
            w.write_string("<dd");
            if (node.attributes() != null) {
                root.renderer.html.render_attributes(w, source, node, definition_description_attribute_filter(), rc);
            }
            if (is_tight) {
                w.write_string(">");
            } else {
                w.write_string(">\n");
            }
        } else {
            w.write_string("</dd>\n");
        }
        root.ast.WalkStatus.WalkContinue
    }

    implements root.renderer.Extension<root.renderer.html.Config> {
        function renderer_options(self, cfg: root.renderer.html.Config) -> root.renderer.html.Option[] {
            let r_list: root.renderer.NodeRendererFuncType = self.render_definition_list;
            let r_term: root.renderer.NodeRendererFuncType = self.render_definition_term;
            let r_desc: root.renderer.NodeRendererFuncType = self.render_definition_description;
            let nrs: map<string, root.renderer.html.NodeRenderer> = {};
            nrs[root.extension.ast.kind_definition_list()] = root.renderer.html.node_renderer_func(r_list);
            nrs[root.extension.ast.kind_definition_term()] = root.renderer.html.node_renderer_func(r_term);
            nrs[root.extension.ast.kind_definition_description()] = root.renderer.html.node_renderer_func(r_desc);
            let opts: root.renderer.html.Option[] = [
                root.renderer.html.with_node_renderers(nrs),
                root.renderer.html.with_is_in_tight_block_func(definition_list_is_in_tight_block),
            ];
            opts
        }
    }
}

/// NewDefinitionListHTMLRenderer returns a new html.Extension for rendering DefinitionList nodes.
function new_definition_list_html_renderer() -> root.renderer.html.Extension {
    DefinitionListHTMLRendererExtension {}
}

/// DefinitionListAttributeFilter defines attribute names which dl elements can have.
function definition_list_attribute_filter() -> root.util.BytesFilter {
    root.renderer.html.global_attribute_filter()
}

/// DefinitionTermAttributeFilter defines attribute names which dt elements can have.
function definition_term_attribute_filter() -> root.util.BytesFilter {
    root.renderer.html.global_attribute_filter()
}

/// DefinitionDescriptionAttributeFilter defines attribute names which dd elements can have.
function definition_description_attribute_filter() -> root.util.BytesFilter {
    root.renderer.html.global_attribute_filter()
}

/// Go's unexported `definitionListParserExtension`.
class DefinitionListParserExtension {
    implements root.parser.Extension {
        function parser_options(self, cfg: root.parser.Config) -> root.parser.Option[] {
            let bps: root.util.PrioritizedValue<root.parser.BlockParser>[] = [
                root.util.prioritized(new_definition_list_parser_impl(), 101),
                root.util.prioritized(new_definition_description_parser_impl(), 102),
            ];
            let opts: root.parser.Option[] = [root.parser.with_block_parsers(bps)];
            opts
        }
    }
}

/// NewDefinitionListParser returns a new parser.Extension for parsing PHP Markdown Extra Definition lists.
function new_definition_list_parser() -> root.parser.Extension {
    DefinitionListParserExtension {}
}

function definition_list_is_in_tight_block(n: root.ast.Node) -> bool {
    let parent = n.parent();
    if (parent == null) {
        return false;
    }
    match (parent) {
        let desc: root.extension.ast.DefinitionDescription => {
            return desc.is_tight;
        }
        _ => {}
    }
    let gp = parent.parent();
    if (gp != null) {
        match (gp) {
            let list: root.ast.List => {
                return list.is_tight;
            }
            _ => {}
        }
    }
    false
}

/// DefinitionListParser is a default [parser.Extension] for PHP Markdown Extra Definition lists.
function definition_list_parser() -> root.parser.Extension {
    new_definition_list_parser()
}

/// DefinitionListHTMLRenderer is a default [html.Extension] for PHP Markdown Extra Definition lists.
function definition_list_html_renderer() -> root.renderer.html.Extension {
    new_definition_list_html_renderer()
}
