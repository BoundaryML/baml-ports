// Port of goldmark parser/code_span.go.

class CodeSpanParser {
    implements InlineParser {
        function trigger(self) -> uint8array {
            root.util.bytes_of([96])
        }

        function parse(self, parent: root.ast.Node, block: root.text.Reader, pc: Context) -> root.ast.Node? {
            let spl = block.peek_line();
            let line0 = spl.line ?? root.util.new_bytes();
            let start_segment = spl.segment;
            let opener = 0;
            while (opener < line0.length() && line0[opener] == 96) {
                opener += 1;
            }
            block.advance(opener);
            let saved = block.position();
            let builder = root.text.new_value_builder();
            builder.decoder(null);
            // firstLine is true while no line has been skipped yet (i.e. we are still
            // looking at the line right after the opener). The overwhelmingly common
            // case is a closer found on this very line, e.g. `code`; that case is
            // handled without ever touching the ValueBuilder.
            let first_line = true;
            let found = false;
            while (!found) {
                let pl = block.peek_line();
                let line = pl.line;
                let segment = pl.segment;
                if (line == null) {
                    block.set_position(saved.line, saved.segment);
                    return root.ast.new_text(root.text.new_single_line_value_from_segment(
                        start_segment.with_stop(start_segment.start + opener), block.decoder()));
                }
                let i = 0;
                while (i < line.length()) {
                    let c = line[i];
                    if (c == 96) {
                        let oldi = i;
                        while (i < line.length() && line[i] == 96) {
                            i += 1;
                        }
                        let closure = i - oldi;
                        if (closure == opener && (i >= line.length() || line[i] != 96)) {
                            block.advance(i);
                            if (first_line) {
                                return root.ast.new_code_span(SingleLineCodeSpanValue { start: segment.start, stop: segment.start + i - closure });
                            }
                            let index = root.text.new_index(segment.start, segment.start + i - closure);
                            if (!index.is_empty()) {
                                builder.add_index(index);
                            }
                            found = true;
                            break;
                        }
                        continue;
                    }
                    i += 1;
                }
                if (found) {
                    break;
                }
                builder.add_segment(segment);
                block.advance_line();
                first_line = false;
            }
            // end:
            let value = builder.build_multi_line();
            let indices = value.indices();
            if (indices.length() == 1) {
                return root.ast.new_code_span(SingleLineCodeSpanValue { start: indices[0].start, stop: indices[0].stop });
            }
            root.ast.new_code_span(MultiLineCodeSpanValue { idx_list: indices })
        }
    }
}

/// NewCodeSpanParser return a new InlineParser that parses inline codes
/// surrounded by '`' .
function new_code_span_parser() -> InlineParser {
    CodeSpanParser {}
}

/// singleLineCodeSpanValue is a [text.Value] implementation for inline code spans.
///
/// this [text.Value] normalizes the value of inline code spans by trimming leading and trailing spaces and
/// replacing newlines with spaces, as per the CommonMark specification.
class SingleLineCodeSpanValue {
    start: int,
    stop: int,

    function should_trim_spaces(self, source: uint8array) -> bool {
        let b = source.slice(self.start, self.stop);
        if (b.length() < 2) {
            return false;
        }
        if (root.util.is_blank(b)) {
            return false;
        }
        is_space_or_newline(b[0]) && is_space_or_newline(b[b.length() - 1])
    }

    function trimmed_index(self, source: uint8array) -> root.text.Index {
        if (self.should_trim_spaces(source)) {
            let start = self.start + 1;
            let stop = self.stop;
            if (self.stop > self.start) {
                stop -= 1;
            }
            return root.text.new_index(start, stop);
        }
        root.text.new_index(self.start, self.stop)
    }

    implements root.text.Value {
        function index(self) -> root.text.Index {
            root.text.new_index(self.start, self.stop)
        }

        function indices(self) -> root.text.Index[] {
            [self.index()]
        }

        function is_empty(self) -> bool {
            self.start >= self.stop
        }

        function is_owned(self) -> bool {
            false
        }

        function value(self, source: uint8array) -> string {
            self.str(source)
        }

        function write_to(self, w: root.util.BufWriter, source: uint8array) -> int {
            let i = self.trimmed_index(source);
            let b = source.slice(i.start, i.stop);
            if (b.length() == 0) {
                return 0;
            }
            write_newlines_with_spaces(w, b)
        }

        function bytes(self, source: uint8array) -> uint8array {
            let i = self.trimmed_index(source);
            let b = source.slice(i.start, i.stop);
            if (b.length() == 0) {
                return b;
            }
            replace_newlines_with_spaces(b)
        }

        function str(self, source: uint8array) -> string {
            self.bytes(source).to_string()
        }
    }
}

/// multiLineCodeSpanValue is a text.Value implementation for inline code spans.
///
/// this [text.Value] normalizes the value of inline code spans by trimming leading and trailing spaces and
/// replacing newlines with spaces, as per the CommonMark specification.
class MultiLineCodeSpanValue {
    idx_list: root.text.Index[],

    function should_trim_spaces(self, source: uint8array) -> bool {
        let indices = self.idx_list;
        if (indices.length() == 0) {
            return false;
        }
        if (indices.length() == 1) {
            let b = source.slice(indices[0].start, indices[0].stop);
            if (b.length() < 2) {
                return false;
            }
            if (root.util.is_blank(b)) {
                return false;
            }
            return is_space_or_newline(b[0]) && is_space_or_newline(b[b.length() - 1]);
        }
        let first = source.slice(indices[0].start, indices[0].stop);
        let lasti = indices[indices.length() - 1];
        let last = source.slice(lasti.start, lasti.stop);
        if (first.length() < 1 || last.length() < 1) {
            return false;
        }
        let has_non_blank = false;
        for (let index in indices) {
            let b = source.slice(index.start, index.stop);
            if (!root.util.is_blank(b)) {
                has_non_blank = true;
                break;
            }
        }
        if (!has_non_blank) {
            return false;
        }
        is_space_or_newline(first[0]) && is_space_or_newline(last[last.length() - 1])
    }

    function trimmed_indices(self, source: uint8array) -> root.text.Index[] {
        if (self.should_trim_spaces(source)) {
            let indices: root.text.Index[] = self.idx_list.map((ix: root.text.Index) -> root.text.Index { root.text.new_index(ix.start, ix.stop) });
            let n = indices.length();
            if (n == 1) {
                let s = indices[0].start + 1;
                let e = indices[0].stop;
                if (e > s) {
                    e -= 1;
                }
                indices[0] = root.text.new_index(s, e);
            } else if (n > 1) {
                indices[0] = root.text.new_index(indices[0].start + 1, indices[0].stop);
                let l = indices[n - 1];
                if (l.stop > l.start) {
                    indices[n - 1] = root.text.new_index(l.start, l.stop - 1);
                }
            }
            return indices;
        }
        self.idx_list
    }

    implements root.text.Value {
        function index(self) -> root.text.Index {
            if (self.idx_list.length() > 0) {
                return self.idx_list[0];
            }
            root.text.new_index(0, 0)
        }

        function indices(self) -> root.text.Index[] {
            self.idx_list
        }

        function is_empty(self) -> bool {
            for (let idx in self.idx_list) {
                if (idx.start < idx.stop) {
                    return false;
                }
            }
            true
        }

        function is_owned(self) -> bool {
            false
        }

        function value(self, source: uint8array) -> string {
            self.str(source)
        }

        function write_to(self, w: root.util.BufWriter, source: uint8array) -> int {
            let indices = self.trimmed_indices(source);
            if (indices.length() == 0) {
                return 0;
            }
            let n = 0;
            for (let idx in indices) {
                n += write_newlines_with_spaces(w, source.slice(idx.start, idx.stop));
            }
            n
        }

        function bytes(self, source: uint8array) -> uint8array {
            let indices = self.trimmed_indices(source);
            let buf = root.util.new_bytes();
            for (let idx in indices) {
                root.util.append_bytes(buf, replace_newlines_with_spaces(source.slice(idx.start, idx.stop)));
            }
            buf
        }

        function str(self, source: uint8array) -> string {
            self.bytes(source).to_string()
        }
    }
}

function is_space_or_newline(c: int) -> bool {
    c == 32 || c == 10
}

function replace_newlines_with_spaces(b: uint8array) -> uint8array {
    root.util.bytes_replace_all(b, root.util.bytes_of([10]), root.util.bytes_of([32]))
}

function write_newlines_with_spaces(w: root.util.BufWriter, b0: uint8array) -> int {
    let b = b0;
    if (root.util.index_byte(b, 10) == -1) {
        return w.write(b);
    }
    let written = 0;
    while (true) {
        let i = root.util.index_byte(b, 10);
        if (i == -1) {
            written += w.write(b);
            return written;
        }
        written += w.write(b.slice(0, i));
        written += w.write(root.util.bytes_of([32]));
        b = b.slice(i + 1, b.length());
    }
    written
}
