// Port of goldmark extension/extension.go.

/// Go's unexported `withXHTML`: a TableHTMLRendererOption, a
/// TaskListItemHTMLRendererOption and a FootnoteHTMLRendererOption.
class WithXHTMLOption {
    value: bool,

    implements TableHTMLRendererOption {
        function apply_table_html_renderer_option(self, c: TableHTMLRendererConfig) -> void {
            c.xhtml = self.value;
        }
    }

    implements TaskListItemHTMLRendererOption {
        function apply_task_list_item_html_renderer_option(self, c: TaskListItemHTMLRendererConfig) -> void {
            c.xhtml = self.value;
        }
    }

    implements FootnoteHTMLRendererOption {
        function apply_footnote_html_renderer_option(self, c: FootnoteHTMLRendererConfig) -> void {
            // (Go sets `true` here rather than `o.value`; ported as-is.)
            c.xhtml = true;
        }
    }
}

/// WithXHTML is a functional option that indicates that table, task list, and
/// footnote elements should be rendered as XHTML.
function with_xhtml() -> WithXHTMLOption {
    WithXHTMLOption { value: true }
}

/// Go's unexported `withIsInTightBlockFunc`.
class WithIsInTightBlockFuncOption {
    is_in_tight_block_func: root.renderer.html.IsInTightBlockFunc,

    implements TaskListItemHTMLRendererOption {
        function apply_task_list_item_html_renderer_option(self, c: TaskListItemHTMLRendererConfig) -> void {
            c.is_in_tight_block_func = self.is_in_tight_block_func;
        }
    }
}

/// WithIsInTightBlockFunc is a functional option that sets the function to determine
/// whether the list item is in a tight block.
function with_is_in_tight_block_func(f: root.renderer.html.IsInTightBlockFunc) -> WithIsInTightBlockFuncOption {
    WithIsInTightBlockFuncOption { is_in_tight_block_func: f }
}
