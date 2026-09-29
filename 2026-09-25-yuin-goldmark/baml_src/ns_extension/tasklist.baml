// Port of goldmark extension/tasklist.go.
//
// Porting notes:
// - Go's `type TaskStatus string` with constants becomes a string alias and
//   zero-argument functions (`task_status_active()`, ...).
// - `(value, end, ok)` / `(TaskStatus, bool)` results become nullable results.
// - Go's `TaskListItemHTMLRendererOption` has an unexported method; here it is
//   an interface with a public method so that options defined elsewhere (e.g.
//   `WithXHTML()` / `WithIsInTightBlockFunc()` in extension.go) can implement it.

/// TaskStatus represents the status of a task in a task list.
type TaskStatus = string

/// TaskStatusActive indicates that the task is active (not completed).
function task_status_active() -> TaskStatus {
    "active"
}

/// TaskStatusCompleted indicates that the task is completed.
function task_status_completed() -> TaskStatus {
    "completed"
}

function task_status_attribute_name() -> string {
    "task-status"
}

/// IsTask returns true if the given node is a task list item.
function is_task(node: root.ast.Node) -> bool {
    match (node) {
        let list_item: root.ast.ListItem => list_item.attribute(task_status_attribute_name()) != null,
        _ => false,
    }
}

/// TaskStatusOf returns the TaskStatus of the given node if it is a task list
/// item, otherwise null (Go: `(TaskStatus, bool)`).
function task_status_of(node: root.ast.Node) -> TaskStatus? {
    let list_item: root.ast.ListItem? = match (node) {
        let li: root.ast.ListItem => li,
        _ => null,
    };
    if (list_item == null) {
        return null;
    }
    let attr = list_item.attribute(task_status_attribute_name());
    if (attr == null) {
        return null;
    }
    // value is always an owned string, so this is safe
    attr.str(root.util.new_bytes())
}

/// Result of `scan_task_checkbox` (Go: `(value byte, end int, ok bool)`).
class TaskCheckbox {
    value: int,
    end: int,
}

function scan_task_checkbox(line: uint8array) -> TaskCheckbox? {
    if (line.length() < 3) {
        return null;
    }
    if (line[0] != 91) { // '['
        return null;
    }
    let value = line[1];
    if (!root.util.is_space(value) && value != 120 && value != 88) { // 'x', 'X'
        return null;
    }
    if (line[2] != 93) { // ']'
        return null;
    }
    let end = 3;
    while (end < line.length() && root.util.is_space(line[end])) {
        end += 1;
    }
    TaskCheckbox { value: value, end: end }
}

/// Go's unexported `taskListItemParser`.
class TaskListItemParser {
    implements root.parser.InlineParser {
        function trigger(self) -> uint8array {
            root.util.bytes_of([91]) // '['
        }

        function parse(self, parent: root.ast.Node, block: root.text.Reader, pc: root.parser.Context) -> root.ast.Node? {
            // Given AST structure must be like
            // - List
            //   - ListItem         : parent.Parent
            //     - Paragraph      : parent
            //       (current line)
            let gp = parent.parent();
            if (gp == null) {
                return null;
            }
            if (!root.ast.same_node(gp.first_child(), parent)) {
                return null;
            }

            if (parent.has_children()) {
                return null;
            }

            let list_item: root.ast.ListItem? = match (gp) {
                let li: root.ast.ListItem => li,
                _ => null,
            };
            if (list_item == null) {
                return null;
            }
            if (list_item.attribute(task_status_attribute_name()) != null) {
                return null;
            }
            let line = block.peek_line().line ?? root.util.new_bytes();
            let cb = scan_task_checkbox(line);
            if (cb == null) {
                return null;
            }
            block.advance(cb.end);
            let checked = cb.value == 120 || cb.value == 88; // 'x', 'X'
            if (checked) {
                list_item.set_attribute(task_status_attribute_name(),
                    root.text.new_multi_line_value_from_string(task_status_completed(), root.text.identity_decoder()));
            } else {
                list_item.set_attribute(task_status_attribute_name(),
                    root.text.new_multi_line_value_from_string(task_status_active(), root.text.identity_decoder()));
            }
            root.parser.nil_node()
        }
    }

    implements root.parser.CloseBlocker {
        function close_block(self, parent: root.ast.Node, block: root.text.Reader, pc: root.parser.Context) -> void {
            // nothing to do
        }
    }
}

/// newTaskListItemParser returns a new InlineParser that can parse
/// checkboxes in list items.
/// This parser must take precedence over the parser.LinkParser.
function new_task_list_item_parser_impl() -> root.parser.InlineParser {
    TaskListItemParser {}
}

/// Go's unexported `taskListItemHTMLRendererConfig`.
class TaskListItemHTMLRendererConfig {
    xhtml: bool,
    is_in_tight_block_func: root.renderer.html.IsInTightBlockFunc?,
}

/// TaskListItemHTMLRendererOption represents an option for configuring the task list item HTML renderer.
interface TaskListItemHTMLRendererOption {
    function apply_task_list_item_html_renderer_option(self, c: TaskListItemHTMLRendererConfig) -> void throws never
}

/// Go's unexported `taskListItemHTMLRendererExtension`.
class TaskListItemHTMLRendererExtension {
    config: TaskListItemHTMLRendererConfig,

    function render_input_tag(self, w: root.util.BufWriter, status: TaskStatus) -> void {
        if (status == task_status_completed()) {
            w.write_string("<input checked=\"\" disabled=\"\" type=\"checkbox\"");
        } else {
            w.write_string("<input disabled=\"\" type=\"checkbox\"");
        }
        if (self.config.xhtml) {
            w.write_string(" /> ");
        } else {
            w.write_string("> ");
        }
    }

    function render_paragraph(self, w: root.util.BufWriter, source: uint8array, n: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus {
        // Determine whether this paragraph belongs to a task list item.
        let status: TaskStatus? = null;
        let parent = n.parent();
        if (parent != null) {
            if (root.ast.same_node(parent.first_child(), n)) {
                status = task_status_of(parent);
            }
        }

        // Go calls the (always set) func directly; a nil func would panic.
        let f = self.config.is_in_tight_block_func ?? root.renderer.html.is_in_tight_block;
        let in_tight = f(n);

        if (status == null) {
            // Standard paragraph rendering.
            if (in_tight) {
                if (!entering && n.next_sibling() != null && n.first_child() != null) {
                    w.write_byte(10); // '\n'
                }
                return root.ast.WalkStatus.WalkContinue;
            }
            if (entering) {
                if (n.attributes() != null) {
                    w.write_string("<p");
                    root.renderer.html.render_attributes(w, source, n, root.renderer.html.paragraph_attribute_filter(), rc);
                    w.write_byte(62); // '>'
                } else {
                    w.write_string("<p>");
                }
            } else {
                w.write_string("</p>\n");
            }
            return root.ast.WalkStatus.WalkContinue;
        }

        // Task paragraph rendering.
        if (in_tight) {
            if (entering) {
                self.render_input_tag(w, status);
            } else if (n.next_sibling() != null && n.first_child() != null) {
                w.write_byte(10); // '\n'
            }
            return root.ast.WalkStatus.WalkContinue;
        }
        if (entering) {
            if (n.attributes() != null) {
                w.write_string("<p");
                root.renderer.html.render_attributes(w, source, n, root.renderer.html.paragraph_attribute_filter(), rc);
                w.write_byte(62); // '>'
            } else {
                w.write_string("<p>");
            }
            self.render_input_tag(w, status);
        } else {
            w.write_string("</p>\n");
        }
        root.ast.WalkStatus.WalkContinue
    }

    implements root.renderer.Extension<root.renderer.html.Config> {
        function renderer_options(self, c: root.renderer.html.Config) -> root.renderer.html.Option[] {
            if (c.xhtml) {
                self.config.xhtml = true;
            }
            self.config.is_in_tight_block_func = c.paragraph.is_in_tight_block_func;
            let r: root.renderer.NodeRendererFuncType = self.render_paragraph;
            let nrs: map<string, root.renderer.html.NodeRenderer> = {};
            nrs[root.ast.kind_paragraph()] = root.renderer.html.node_renderer_func(r);
            let opts: root.renderer.html.Option[] = [root.renderer.html.with_node_renderers(nrs)];
            opts
        }
    }
}

/// NewTaskListItemHTMLRenderer returns a new html.Extension for rendering task list items.
function new_task_list_item_html_renderer(opts: TaskListItemHTMLRendererOption[] = []) -> root.renderer.html.Extension {
    let config = TaskListItemHTMLRendererConfig { xhtml: false, is_in_tight_block_func: null };
    for (let opt in opts) {
        opt.apply_task_list_item_html_renderer_option(config);
    }
    TaskListItemHTMLRendererExtension { config: config }
}

/// Go's unexported `taskListItemParserExtension`.
class TaskListItemParserExtension {
    implements root.parser.Extension {
        function parser_options(self, cfg: root.parser.Config) -> root.parser.Option[] {
            let ips: root.util.PrioritizedValue<root.parser.InlineParser>[] = [
                root.util.prioritized(new_task_list_item_parser_impl(), 0),
            ];
            let opts: root.parser.Option[] = [root.parser.with_inline_parsers(ips)];
            opts
        }
    }
}

/// NewTaskListItemParser returns a new parser.Extension for parsing task list item checkboxes.
function new_task_list_item_parser() -> root.parser.Extension {
    TaskListItemParserExtension {}
}

/// TaskListItemParser is a default [parser.Extension] for parsing task list item checkboxes.
function task_list_item_parser() -> root.parser.Extension {
    new_task_list_item_parser()
}

/// TaskListItemHTMLRenderer is a default [html.Extension] for rendering task list items.
function task_list_item_html_renderer() -> root.renderer.html.Extension {
    new_task_list_item_html_renderer()
}
