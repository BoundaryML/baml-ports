// Port of goldmark extension/table.go.
//
// Porting notes:
// - Go's unexported types keep their names in CamelCase (`tableParagraphTransformer`
//   → `TableParagraphTransformer`, ...).
// - Package-level vars (`TableParser`, `TableHTMLRenderer`, attribute filters,
//   `escapedPipeCellListKey`) are zero-argument functions.
// - `TableHTMLRendererOption.applyTableHTMLRendererOption` →
//   `apply_table_html_renderer_option`; `WithXHTML` (extension.go) implements it.

/// Go: `escapedPipeCellListKey = parser.NewContextKey()`.
function escaped_pipe_cell_list_key() -> root.parser.ContextKey {
    "extension.escapedPipeCellList"
}

/// Go's unexported `escapedPipeCell`.
class EscapedPipeCell {
    cell: root.extension.ast.TableCell,
    pos: int[],
    transformed: bool,
}

/// TableCellAlignMethod indicates how table cells are aligned in HTML format.
enum TableCellAlignMethod {
    /// TableCellAlignDefault renders alignments by default method.
    /// With XHTML, alignments are rendered as an align attribute.
    /// With HTML5, alignments are rendered as a style attribute.
    TableCellAlignDefault
    /// TableCellAlignAttribute renders alignments as an align attribute.
    TableCellAlignAttribute
    /// TableCellAlignStyle renders alignments as a style attribute.
    TableCellAlignStyle
    /// TableCellAlignNone does not care about alignments.
    /// If you using classes or other styles, you can add these attributes
    /// in an ASTTransformer.
    TableCellAlignNone
}

/// Go's unexported `tableHTMLRendererConfig`.
class TableHTMLRendererConfig {
    xhtml: bool,
    table_cell_align_method: TableCellAlignMethod,
}

/// TableHTMLRendererOption is a functional option for the table HTML renderer extension.
interface TableHTMLRendererOption {
    function apply_table_html_renderer_option(self, c: TableHTMLRendererConfig) -> void throws never
}

/// Go's unexported `withTableCellAlignMethod`.
class WithTableCellAlignMethodOption {
    value: TableCellAlignMethod,

    implements TableHTMLRendererOption {
        function apply_table_html_renderer_option(self, c: TableHTMLRendererConfig) -> void {
            c.table_cell_align_method = self.value;
        }
    }
}

/// WithTableCellAlignMethod is a functional option that indicates how table cells are aligned in HTML format.
function with_table_cell_align_method(a: TableCellAlignMethod) -> TableHTMLRendererOption {
    WithTableCellAlignMethodOption { value: a }
}

function is_table_delim(bs: uint8array) -> bool {
    if (root.util.indent_width(bs, 0).width > 3) {
        return false;
    }
    let all_sep = true;
    for (let k = 0; k < bs.length(); k += 1) {
        let b = bs[k];
        if (b != 45) { // '-'
            all_sep = false;
        }
        if (!root.util.is_space(b) && b != 45 && b != 124 && b != 58) { // '-', '|', ':'
            return false;
        }
    }
    !all_sep
}

/// Go returns `(alignment ast.Alignment, ok bool)`; `null` means `!ok`.
function classify_table_delim(col0: uint8array) -> root.extension.ast.Alignment? {
    let col = root.util.trim_left_space(col0);
    col = root.util.trim_right_space(col);
    let left = false;
    if (col.length() > 0) {
        left = col[0] == 58; // ':'
    }
    if (left) {
        col = col.slice(1, col.length());
    }
    let right = false;
    if (col.length() > 0) {
        right = col[col.length() - 1] == 58; // ':'
    }
    if (right) {
        col = col.slice(0, col.length() - 1);
    }
    if (col.length() == 0) {
        return null;
    }
    for (let k = 0; k < col.length(); k += 1) {
        if (col[k] != 45) { // '-'
            return null;
        }
    }
    if (left && right) {
        return root.extension.ast.Alignment.AlignCenter;
    }
    if (left) {
        return root.extension.ast.Alignment.AlignLeft;
    }
    if (right) {
        return root.extension.ast.Alignment.AlignRight;
    }
    root.extension.ast.Alignment.AlignNone
}

/// Go's `bytes.Split(s, []byte{sep})` for a single separator byte.
function split_bytes(s: uint8array, sep: int) -> uint8array[] {
    let out: uint8array[] = [];
    let start = 0;
    let i = 0;
    while (i < s.length()) {
        if (s[i] == sep) {
            out.push(s.slice(start, i));
            start = i + 1;
        }
        i += 1;
    }
    out.push(s.slice(start, s.length()));
    out
}

/// Go's unexported `tableParagraphTransformer`.
class TableParagraphTransformer {
    function parse_row(self, segment0: root.text.Segment, alignments: root.extension.ast.Alignment[], is_header: bool, reader: root.text.Reader, pc: root.parser.Context) -> root.extension.ast.TableRow {
        let npos = segment0;
        let source = reader.source();
        let segment = segment0.trim_left_space(source);
        segment = segment.trim_right_space(source);
        let line = segment.bytes(source);
        let pos = 0;
        let limit = line.length();
        let row = root.extension.ast.new_table_row();
        row.set_pos(npos.start);
        if (line.length() > 0) {
            if (line[pos] == 124) { // '|'
                pos += 1;
            }
        }
        if (line.length() > 0) {
            if (line[limit - 1] == 124) { // '|'
                limit -= 1;
            }
        }
        let i = 0;
        while (pos < limit) {
            let alignment: root.extension.ast.Alignment = root.extension.ast.Alignment.AlignNone;
            if (i >= alignments.length()) {
                if (!is_header) {
                    return row;
                }
            } else {
                alignment = alignments[i];
            }

            let node = root.extension.ast.new_table_cell(alignment);
            // BAML: Go's `var escapedCell *escapedPipeCell` (lazily created) is
            // an eagerly built cell plus a `registered` flag (loop-carried
            // optionals lose narrowing).
            let escaped_cell = EscapedPipeCell { cell: node, pos: [], transformed: false };
            let registered = false;
            node.set_pos(npos.start + pos - npos.padding);
            let has_backtick = false;
            let closure = pos;
            while (closure < limit) {
                if (line[closure] == 96) { // '`'
                    has_backtick = true;
                }
                if (line[closure] == 124) { // '|'
                    let escaped = false;
                    if (closure != 0) {
                        escaped = line[closure - 1] == 92; // '\\'
                    }
                    if (!escaped) {
                        break;
                    } else if (has_backtick) {
                        if (!registered) {
                            registered = true;
                            let u = pc.compute_if_absent(escaped_pipe_cell_list_key(), () -> unknown {
                                let empty: EscapedPipeCell[] = [];
                                empty
                            });
                            let escaped_list: EscapedPipeCell[] = match (u) {
                                let l: EscapedPipeCell[] => l,
                                _ => [],
                            };
                            escaped_list.push(escaped_cell);
                            pc.set(escaped_pipe_cell_list_key(), escaped_list);
                        }
                        escaped_cell.pos.push(segment.start + closure - 1);
                    }
                }
                closure += 1;
            }
            let seg = root.text.new_segment(segment.start + pos, segment.start + closure);
            seg = seg.trim_left_space(source);
            seg = seg.trim_right_space(source);
            node.append_source(seg);
            row.append_child(node);
            pos = closure + 1;
            i += 1;
        }
        while (i < alignments.length()) {
            row.append_child(root.extension.ast.new_table_cell(alignments[i]));
            i += 1;
        }
        row
    }

    /// Returns null when the line is not a delimiter row (Go: nil slice).
    function parse_delimiter(self, segment: root.text.Segment, reader: root.text.Reader) -> root.extension.ast.Alignment[]? {
        let line = segment.bytes(reader.source());
        if (!is_table_delim(line)) {
            return null;
        }
        let cols = split_bytes(line, 124); // '|'
        if (root.util.is_blank(cols[0])) {
            cols = cols.slice(1, cols.length());
        }
        if (cols.length() > 0) {
            if (root.util.is_blank(cols[cols.length() - 1])) {
                cols = cols.slice(0, cols.length() - 1);
            }
        }

        let alignments: root.extension.ast.Alignment[] = [];
        for (let col in cols) {
            let alignment = classify_table_delim(col);
            if (alignment == null) {
                return null;
            }
            alignments.push(alignment);
        }
        // Go: appending nothing to a nil slice leaves it nil.
        if (alignments.length() == 0) {
            return null;
        }
        alignments
    }

    implements root.parser.ParagraphTransformer {
        function transform(self, node: root.ast.Paragraph, reader: root.text.Reader, pc: root.parser.Context) -> void {
            let ppos = node.pos();
            let lines = node.source();
            if (lines.length() < 2) {
                return;
            }
            let i = 1;
            while (i < lines.length()) {
                let alignments0 = self.parse_delimiter(lines[i], reader);
                if (alignments0 == null) {
                    i += 1;
                    continue;
                }
                let alignments: root.extension.ast.Alignment[] = alignments0;
                let header = self.parse_row(lines[i - 1], alignments, true, reader, pc);
                if (alignments.length() != header.child_count()) {
                    return;
                }
                let table = root.extension.ast.new_table();
                table.set_pos(ppos);
                let table_header = root.extension.ast.new_table_header();
                table_header.set_pos(header.pos());
                let c = header.first_child();
                while (c != null) {
                    let next = c.next_sibling();
                    header.remove_child(c);
                    table_header.append_child(c);
                    c = next;
                }
                table.append_child(table_header);
                let body: root.extension.ast.TableBody? = null;
                let j = i + 1;
                while (j < lines.length()) {
                    let bd = match (body) {
                        let existing: root.extension.ast.TableBody => existing,
                        _ => {
                            let fresh = root.extension.ast.new_table_body();
                            fresh.set_pos(lines[j].start);
                            table.append_child(fresh);
                            body = fresh;
                            fresh
                        }
                    };
                    bd.append_child(self.parse_row(lines[j], alignments, false, reader, pc));
                    j += 1;
                }
                node.set_source(lines.slice(0, i - 1));
                let np = node.parent();
                if (np != null) {
                    np.insert_after(node, table);
                }
                let src = node.source();
                if (src.length() == 0) {
                    let np2 = node.parent();
                    if (np2 != null) {
                        np2.remove_child(node);
                    }
                    break;
                }
                let last = src[i - 2].copy();
                last.stop = last.stop - 1; // trim last newline(\n)
                src[i - 2] = last;
                // Go: node.Source() aliases `lines`' backing array.
                lines[i - 2] = last;
                i += 1;
            }
        }
    }
}

function new_table_paragraph_transformer() -> root.parser.ParagraphTransformer {
    TableParagraphTransformer {}
}

/// Go's unexported `tableASTTransformer`.
class TableASTTransformer {
    implements root.parser.ASTTransformer {
        function transform(self, doc: root.ast.Document, reader: root.text.Reader, pc: root.parser.Context) -> void {
            let lst: EscapedPipeCell[] = match (pc.get(escaped_pipe_cell_list_key())) {
                let l: EscapedPipeCell[] => l,
                _ => {
                    return;
                }
            };
            pc.set(escaped_pipe_cell_list_key(), null);
            for (let v in lst) {
                if (v.transformed) {
                    continue;
                }
                root.ast.walk(v.cell, (n: root.ast.Node, entering: bool) -> root.ast.WalkStatus {
                    if (!entering || n.kind() != root.ast.kind_code_span()) {
                        return root.ast.WalkStatus.WalkContinue;
                    }
                    match (n) {
                        let cs: root.ast.CodeSpan => {
                            let raw = cs.value.bytes(reader.source());
                            let fixed = root.util.bytes_replace_all(raw, "\\|".to_utf8(), "|".to_utf8());
                            cs.value = root.text.new_multi_line_value_from_string(fixed.to_string(), root.text.identity_decoder());
                            v.transformed = true;
                        }
                        _ => {}
                    }
                    root.ast.WalkStatus.WalkContinue
                });
            }
        }
    }
}

function default_table_ast_transformer() -> root.parser.ASTTransformer {
    TableASTTransformer {}
}

/// Go's unexported `tableHTMLRendererExtension`.
class TableHTMLRendererExtension {
    config: TableHTMLRendererConfig,

    function render_table(self, w: root.util.BufWriter, source: uint8array, n: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus {
        if (entering) {
            w.write_string("<table");
            if (n.attributes() != null) {
                root.renderer.html.render_attributes(w, source, n, table_attribute_filter(), rc);
            }
            w.write_string(">\n");
        } else {
            w.write_string("</table>\n");
        }
        root.ast.WalkStatus.WalkContinue
    }

    function render_table_header(self, w: root.util.BufWriter, source: uint8array, n: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus {
        if (entering) {
            w.write_string("<thead");
            if (n.attributes() != null) {
                root.renderer.html.render_attributes(w, source, n, table_header_attribute_filter(), rc);
            }
            w.write_string(">\n");
            w.write_string("<tr>\n"); // Header <tr> has no separate handle
        } else {
            w.write_string("</tr>\n");
            w.write_string("</thead>\n");
        }
        root.ast.WalkStatus.WalkContinue
    }

    function render_table_body(self, w: root.util.BufWriter, source: uint8array, n: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus {
        if (entering) {
            w.write_string("<tbody>\n");
        } else {
            w.write_string("</tbody>\n");
        }
        root.ast.WalkStatus.WalkContinue
    }

    function render_table_row(self, w: root.util.BufWriter, source: uint8array, n: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus {
        if (entering) {
            w.write_string("<tr");
            if (n.attributes() != null) {
                root.renderer.html.render_attributes(w, source, n, table_row_attribute_filter(), rc);
            }
            w.write_string(">\n");
        } else {
            w.write_string("</tr>\n");
        }
        root.ast.WalkStatus.WalkContinue
    }

    function render_table_cell(self, w: root.util.BufWriter, source: uint8array, node: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus {
        let n = match (node) {
            let c: root.extension.ast.TableCell => c,
            _ => {
                return root.ast.WalkStatus.WalkContinue;
            }
        };
        let tag = "td";
        let parent = n.parent();
        if (parent != null) {
            if (parent.kind() == root.extension.ast.kind_table_header()) {
                tag = "th";
            }
        }
        if (entering) {
            w.write_string("<" + tag);
            if (n.alignment != root.extension.ast.Alignment.AlignNone) {
                let amethod: TableCellAlignMethod = self.config.table_cell_align_method;
                if (amethod == TableCellAlignMethod.TableCellAlignDefault) {
                    if (self.config.xhtml) {
                        amethod = TableCellAlignMethod.TableCellAlignAttribute;
                    } else {
                        amethod = TableCellAlignMethod.TableCellAlignStyle;
                    }
                }
                match (amethod) {
                    TableCellAlignMethod.TableCellAlignAttribute => {
                        if (n.attribute("align") == null) { // Skip align render if overridden
                            w.write_string(" align=\"" + root.extension.ast.alignment_string(n.alignment) + "\"");
                        }
                    }
                    TableCellAlignMethod.TableCellAlignStyle => {
                        let v = n.attribute("style");
                        let cob = root.util.new_copy_on_write_buffer(root.util.new_bytes());
                        if (v != null) {
                            cob = root.util.new_copy_on_write_buffer(v.bytes(root.util.new_bytes()));
                            cob.append_byte(59); // ';'
                        }
                        let style = "text-align:" + root.extension.ast.alignment_string(n.alignment);
                        cob.append_string(style);
                        n.set_attribute("style", root.text.new_multi_line_value_from_string(cob.bytes().to_string(), root.text.identity_decoder()));
                    }
                    _ => {}
                }
            }
            if (n.attributes() != null) {
                if (tag == "td") {
                    root.renderer.html.render_attributes(w, source, n, table_td_cell_attribute_filter(), rc); // <td>
                } else {
                    root.renderer.html.render_attributes(w, source, n, table_th_cell_attribute_filter(), rc); // <th>
                }
            }
            w.write_byte(62); // '>'
        } else {
            w.write_string("</" + tag + ">\n");
        }
        root.ast.WalkStatus.WalkContinue
    }

    implements root.renderer.Extension<root.renderer.html.Config> {
        function renderer_options(self, c: root.renderer.html.Config) -> root.renderer.html.Option[] {
            if (c.xhtml) {
                self.config.xhtml = true;
            }
            let r_table: root.renderer.NodeRendererFuncType = self.render_table;
            let r_table_header: root.renderer.NodeRendererFuncType = self.render_table_header;
            let r_table_body: root.renderer.NodeRendererFuncType = self.render_table_body;
            let r_table_row: root.renderer.NodeRendererFuncType = self.render_table_row;
            let r_table_cell: root.renderer.NodeRendererFuncType = self.render_table_cell;
            // BAML: map literal keys must be literals; insert computed kinds.
            let nrs: map<string, root.renderer.html.NodeRenderer> = {};
            nrs[root.extension.ast.kind_table()] = root.renderer.html.node_renderer_func(r_table);
            nrs[root.extension.ast.kind_table_header()] = root.renderer.html.node_renderer_func(r_table_header);
            nrs[root.extension.ast.kind_table_body()] = root.renderer.html.node_renderer_func(r_table_body);
            nrs[root.extension.ast.kind_table_row()] = root.renderer.html.node_renderer_func(r_table_row);
            nrs[root.extension.ast.kind_table_cell()] = root.renderer.html.node_renderer_func(r_table_cell);
            let result: root.renderer.html.Option[] = [root.renderer.html.with_node_renderers(nrs)];
            result
        }
    }
}

/// NewTableHTMLRenderer returns a new html.Extension for rendering Table nodes.
function new_table_html_renderer(opts: TableHTMLRendererOption[] = []) -> root.renderer.html.Extension {
    let cfg = TableHTMLRendererConfig {
        xhtml: false,
        table_cell_align_method: TableCellAlignMethod.TableCellAlignDefault,
    };
    for (let opt in opts) {
        opt.apply_table_html_renderer_option(cfg);
    }
    TableHTMLRendererExtension { config: cfg }
}

/// TableAttributeFilter defines attribute names which table elements can have.
///
///   - align: Deprecated
///   - bgcolor: Deprecated
///   - border: Deprecated
///   - cellpadding: Deprecated
///   - cellspacing: Deprecated
///   - frame: Deprecated
///   - rules: Deprecated
///   - summary: Deprecated
///   - width: Deprecated.
function table_attribute_filter() -> root.util.BytesFilter {
    root.renderer.html.global_attribute_filter().extend_string("align,bgcolor,border,cellpadding,cellspacing,frame,rules,summary,width")
}

/// TableHeaderAttributeFilter defines attribute names which <thead> elements can have.
///
///   - align: Deprecated since HTML4, Obsolete since HTML5
///   - bgcolor: Not Standardized
///   - char: Deprecated since HTML4, Obsolete since HTML5
///   - charoff: Deprecated since HTML4, Obsolete since HTML5
///   - valign: Deprecated since HTML4, Obsolete since HTML5.
function table_header_attribute_filter() -> root.util.BytesFilter {
    root.renderer.html.global_attribute_filter().extend_string("align,bgcolor,char,charoff,valign")
}

/// TableBodyAttributeFilter defines attribute names which <tbody> elements can have.
///
///   - align: Deprecated since HTML4, Obsolete since HTML5
///   - bgcolor: Not Standardized
///   - char: Deprecated since HTML4, Obsolete since HTML5
///   - charoff: Deprecated since HTML4, Obsolete since HTML5
///   - valign: Deprecated since HTML4, Obsolete since HTML5.
function table_body_attribute_filter() -> root.util.BytesFilter {
    root.renderer.html.global_attribute_filter().extend_string("align,bgcolor,char,charoff,valign")
}

/// TableRowAttributeFilter defines attribute names which <tr> elements can have.
///
///   - align: Obsolete since HTML5
///   - bgcolor: Obsolete since HTML5
///   - char: Obsolete since HTML5
///   - charoff: Obsolete since HTML5
///   - valign: Obsolete since HTML5.
function table_row_attribute_filter() -> root.util.BytesFilter {
    root.renderer.html.global_attribute_filter().extend_string("align,bgcolor,char,charoff,valign")
}

/// TableThCellAttributeFilter defines attribute names which table <th> cells can have.
///
///   - abbr:  [OK] Contains a short abbreviated description of the cell's content [NOT OK in <td>]
///   - align:  Obsolete since HTML5
///   - axis:  Obsolete since HTML5
///   - bgcolor:  Not Standardized
///   - char:  Obsolete since HTML5
///   - charoff:  Obsolete since HTML5
///   - colspan:  [OK] Number of columns that the cell is to span
///   - headers:  [OK] This attribute contains a list of space-separated strings,
///     each corresponding to the id attribute of the <th> elements that apply to this element
///   - height:  Deprecated since HTML4. Obsolete since HTML5
///   - rowspan:  [OK] Number of rows that the cell is to span
///   - scope:  [OK] This enumerated attribute defines the cells that the header
///     (defined in the <th>) element relates to [NOT OK in <td>]
///   - valign:  Obsolete since HTML5
///   - width:  Deprecated since HTML4. Obsolete since HTML5.
function table_th_cell_attribute_filter() -> root.util.BytesFilter {
    root.renderer.html.global_attribute_filter().extend_string("abbr,align,axis,bgcolor,char,charoff,colspan,headers,height,rowspan,scope,valign,width")
}

/// TableTdCellAttributeFilter defines attribute names which table <td> cells can have.
///
///   - abbr:  Obsolete since HTML5. [OK in <th>]
///   - align:  Obsolete since HTML5
///   - axis:  Obsolete since HTML5
///   - bgcolor:  Not Standardized
///   - char:  Obsolete since HTML5
///   - charoff:  Obsolete since HTML5
///   - colspan:  [OK] Number of columns that the cell is to span
///   - headers:  [OK] This attribute contains a list of space-separated strings, each corresponding
///     to the id attribute of the <th> elements that apply to this element
///   - height:  Deprecated since HTML4. Obsolete since HTML5
///   - rowspan:  [OK] Number of rows that the cell is to span
///   - scope:  Obsolete since HTML5. [OK in <th>]
///   - valign:  Obsolete since HTML5
///   - width:  Deprecated since HTML4. Obsolete since HTML5.
function table_td_cell_attribute_filter() -> root.util.BytesFilter {
    root.renderer.html.global_attribute_filter().extend_string("abbr,align,axis,bgcolor,char,charoff,colspan,headers,height,rowspan,scope,valign,width")
}

/// Go's unexported `tableParserExtension`.
class TableParserExtension {
    implements root.parser.Extension {
        function parser_options(self, cfg: root.parser.Config) -> root.parser.Option[] {
            let result: root.parser.Option[] = [
                root.parser.with_paragraph_transformers([
                    root.util.prioritized(new_table_paragraph_transformer(), 200),
                ]),
                root.parser.with_ast_transformers([
                    root.util.prioritized(default_table_ast_transformer(), 0),
                ]),
            ];
            result
        }
    }
}

/// NewTableParser returns a new parser.Extension for parsing GFM tables.
function new_table_parser() -> root.parser.Extension {
    TableParserExtension {}
}

/// TableParser is a default [parser.Extension] for parsing GFM tables.
function table_parser() -> root.parser.Extension {
    new_table_parser()
}

/// TableHTMLRenderer is a default [html.Extension] for rendering Table nodes.
function table_html_renderer() -> root.renderer.html.Extension {
    new_table_html_renderer()
}
