// Port of goldmark parser/delimiter.go.

/// A DelimiterProcessor interface provides a set of functions about
/// Delimiter nodes.
interface DelimiterProcessor {
    /// IsDelimiter returns true if given character is a delimiter, otherwise false.
    function is_delimiter(self, b: int) -> bool throws never

    /// CanOpenCloser returns true if given opener can be matched with given closer to
    /// open a span that the closer ends, otherwise false.
    function can_open_closer(self, opener: Delimiter, closer: Delimiter) -> bool throws never

    /// OnMatch will be called when new matched delimiter found.
    /// OnMatch should return a new Node correspond to the matched delimiter.
    function on_match(self, consumes: int) -> root.ast.Node throws never
}

/// A Delimiter struct represents a delimiter like '*' of the Markdown text.
class Delimiter {
    b: root.ast.BaseNode,

    value: root.text.Segment,

    decoder: root.text.Decoder?,

    /// CanOpen is set true if this delimiter can open a span for a new node.
    /// See https://spec.commonmark.org/0.30/#can-open-emphasis for details.
    can_open: bool,

    /// CanClose is set true if this delimiter can close a span for a new node.
    /// See https://spec.commonmark.org/0.30/#can-open-emphasis for details.
    can_close: bool,

    /// Length is a remaining length of this delimiter.
    length: int,

    /// OriginalLength is a original length of this delimiter.
    original_length: int,

    /// Char is a character of this delimiter.
    char: int,

    /// PreviousDelimiter is a previous sibling delimiter node of this delimiter.
    previous_delimiter: Delimiter?,

    /// NextDelimiter is a next sibling delimiter node of this delimiter.
    next_delimiter: Delimiter?,

    /// Processor is a DelimiterProcessor associated with this delimiter.
    processor: DelimiterProcessor,

    /// ConsumeCharacters consumes delimiters.
    function consume_characters(self, n: int) -> void {
        self.length -= n;
        self.value = self.value.with_stop(self.value.start + self.length);
    }

    /// CalcConsumption calculates how many characters should be used for opening
    /// a new span correspond to given closer.
    function calc_consumption(self, closer: Delimiter) -> int {
        if ((self.can_close || closer.can_open) && (self.original_length + closer.original_length) % 3 == 0 && closer.original_length % 3 != 0) {
            return 0;
        }
        if (self.length >= 2 && closer.length >= 2) {
            return 2;
        }
        1
    }

    implements root.ast.Node {
        function base(self) -> root.ast.BaseNode {
            self.b
        }

        function kind(self) -> root.ast.NodeKind {
            kind_delimiter()
        }

        function dump(self, source: uint8array) -> root.ast.NodeDump {
            root.ast.new_node_dump(self, {
                "CanOpen": self.can_open,
                "CanClose": self.can_close,
                "OriginalLength": self.original_length,
                "Char": root.util.byte_array(self.char).to_string(),
            })
        }
    }

    implements root.ast.InlineNode {}
}

function kind_delimiter() -> root.ast.NodeKind {
    "Delimiter"
}

/// NewDelimiter returns a new Delimiter node.
function new_delimiter(can_open: bool, can_close: bool, length: int, char: int, processor: DelimiterProcessor) -> Delimiter {
    Delimiter {
        b: root.ast.new_base_node(),
        value: root.text.new_segment(0, 0),
        decoder: null,
        can_open: can_open,
        can_close: can_close,
        length: length,
        original_length: length,
        char: char,
        previous_delimiter: null,
        next_delimiter: null,
        processor: processor,
    }
}

/// IsLeftFlankingDelimiterRun returns true if the position represents a
/// left-flanking delimiter run as defined by the CommonMark spec.
/// before is the character preceding the delimiter run and after is the
/// character immediately following it.
function is_left_flanking_delimiter_run(before: int, after: int) -> bool {
    let after_is_whitespace = root.util.is_space_rune(after);
    let after_is_punctuation = root.util.is_punct_rune(after);
    let before_is_whitespace = root.util.is_space_rune(before);
    let before_is_punctuation = root.util.is_punct_rune(before);
    !after_is_whitespace && (!after_is_punctuation || before_is_whitespace || before_is_punctuation)
}

/// IsRightFlankingDelimiterRun returns true if the position represents a
/// right-flanking delimiter run as defined by the CommonMark spec.
/// before is the character preceding the delimiter run and after is the
/// character immediately following it.
function is_right_flanking_delimiter_run(before: int, after: int) -> bool {
    let after_is_whitespace = root.util.is_space_rune(after);
    let after_is_punctuation = root.util.is_punct_rune(after);
    let before_is_whitespace = root.util.is_space_rune(before);
    let before_is_punctuation = root.util.is_punct_rune(before);
    !before_is_whitespace && (!before_is_punctuation || after_is_whitespace || after_is_punctuation)
}

/// ParseDelimiterFunc scans a delimiter from block, and if found sets its segment,
/// advances the reader, pushes it onto the delimiter list, and returns it.
type ParseDelimiterFunc = (block: root.text.Reader, minimum: int, processor: DelimiterProcessor, pc: Context) -> Delimiter? throws never

/// ParseDelimiter is a default implementation of [ParseDelimiterFunc] that follows the CommonMark spec.
function parse_delimiter(block: root.text.Reader, minimum: int, processor: DelimiterProcessor, pc: Context) -> Delimiter? {
    let before = block.preceding_character();
    let pl = block.peek_line();
    let line = pl.line ?? root.util.new_bytes();
    let segment = pl.segment;
    if (line.length() == 0) {
        return null;
    }
    let c = line[0];
    if (!processor.is_delimiter(c)) {
        return null;
    }
    let j = 0;
    while (j < line.length() && line[j] == c) {
        j += 1;
    }
    if (j < minimum) {
        return null;
    }
    let after = 32;
    if (j < line.length()) {
        after = root.util.to_rune(line, j);
    }
    let is_left = is_left_flanking_delimiter_run(before, after);
    let is_right = is_right_flanking_delimiter_run(before, after);
    let can_open = false;
    let can_close = false;
    if (c == 95) {
        let before_is_punctuation = root.util.is_punct_rune(before);
        let after_is_punctuation = root.util.is_punct_rune(after);
        can_open = is_left && (!is_right || before_is_punctuation);
        can_close = is_right && (!is_left || after_is_punctuation);
    } else {
        can_open = is_left;
        can_close = is_right;
    }
    let node = new_delimiter(can_open, can_close, j, c, processor);
    node.value = segment.with_stop(segment.start + j);
    node.decoder = block.decoder();
    block.advance(j);
    pc.push_delimiter(node);
    node
}

/// ParseDelimiterSimple is a simpler implementation of [ParseDelimiterFunc].
///
/// This function determines flankings based on original Markdown like simple rules:
///
///   - If the character after the delimiter is a space, the delimiter cannot open a span.
///   - If the character before the delimiter is a space, the delimiter cannot close a span.
///
/// These rules are easy to understand even for non-engineer writers.
/// While CommonMark rules do not work well with CJK, these rules often work well with CJK.
function parse_delimiter_simple(block: root.text.Reader, minimum: int, processor: DelimiterProcessor, pc: Context) -> Delimiter? {
    let before = block.preceding_character();
    let pl = block.peek_line();
    let line = pl.line ?? root.util.new_bytes();
    let segment = pl.segment;
    if (line.length() == 0) {
        return null;
    }
    let c = line[0];
    if (!processor.is_delimiter(c)) {
        return null;
    }
    let j = 0;
    while (j < line.length() && line[j] == c) {
        j += 1;
    }
    if (j < minimum) {
        return null;
    }
    let after = 32;
    if (j < line.length()) {
        after = root.util.to_rune(line, j);
    }

    let last = pc.last_delimiter();
    let before_is_delimiter = false;
    if (last != null) {
        if (last.value.stop == segment.start) {
            before_is_delimiter = true;
            last.can_close = true;
        }
    }
    let is_left = !root.util.is_space_rune(after);
    let is_right = !root.util.is_space_rune(before) || before_is_delimiter;
    let can_open = false;
    let can_close = false;
    if (c == 95) {
        can_open = is_left && (!is_right || before_is_delimiter);
        can_close = is_right && !is_left;
    } else {
        can_open = is_left;
        can_close = is_right;
    }

    let node = new_delimiter(can_open, can_close, j, c, processor);
    node.value = segment.with_stop(segment.start + j);
    node.decoder = block.decoder();
    block.advance(j);
    pc.push_delimiter(node);
    node
}

/// delimiterClassCount is the size of the openersBottom table in
/// ProcessDelimiters: one slot per (Char, CanOpen, Length%3) combination.
function DELIMITER_CLASS_COUNT() -> int {
    256 * 2 * 3
}

function delimiter_class_index(char: int, can_open: bool, length_mod3: int) -> int {
    let idx = char * 6;
    if (can_open) {
        idx += 3;
    }
    idx + length_mod3
}

/// ProcessDelimiters processes the delimiter list in the context.
/// Processing will be stop when reaching the bottom.
///
/// If you implement an inline parser that can have other inline nodes as
/// children, you should call this function when nesting span has closed.
function process_delimiters(bottom: root.ast.Node?, pc: Context) -> void {
    let last_delimiter = pc.last_delimiter();
    if (last_delimiter == null) {
        return;
    }

    let closer: Delimiter? = null;
    let bottom_delim: Delimiter? = null;
    if (bottom != null) {
        match (bottom) {
            let b: Delimiter => {
                bottom_delim = b;
            }
            _ => {}
        }
    }
    if (bottom_delim != null) {
        closer = bottom_delim.next_delimiter;
    } else {
        closer = pc.first_delimiter();
    }
    if (closer == null) {
        pc.clear_delimiters(bottom);
        return;
    }

    // Go lazily allocates `*[delimiterClassCount]int`; a map keyed by class
    // index avoids allocating 1536 slots up front.
    let openers_bottom: map<string, int> = {};

    while (closer != null) {
        let cl: Delimiter = closer;
        if (!cl.can_close) {
            closer = cl.next_delimiter;
            continue;
        }
        let idx = delimiter_class_index(cl.char, cl.can_open, cl.length % 3).to_string();
        let has_lower_bound = false;
        let lower_bound = 0;
        let ob = openers_bottom.get(idx);
        if (ob != null) {
            if (ob != 0) {
                has_lower_bound = true;
                lower_bound = ob - 1;
            }
        }

        let consume = 0;
        let found = false;
        let maybe_opener = false;
        let opener = cl.previous_delimiter;
        while (opener != null) {
            if (root.ast.same_node(opener, bottom)) {
                break;
            }
            if (has_lower_bound && opener.value.start < lower_bound) {
                break;
            }
            if (opener.can_open && opener.processor.can_open_closer(opener, cl)) {
                maybe_opener = true;
                consume = opener.calc_consumption(cl);
                if (consume > 0) {
                    found = true;
                    break;
                }
            }
            opener = opener.previous_delimiter;
        }
        if (!found || opener == null) {
            let next = cl.next_delimiter;
            if (!maybe_opener && !cl.can_open) {
                pc.remove_delimiter(cl);
            }
            openers_bottom[idx] = cl.value.start + 1;
            closer = next;
            continue;
        }
        let op: Delimiter = opener;
        op.consume_characters(consume);
        cl.consume_characters(consume);

        let node = op.processor.on_match(consume);
        node.set_pos(op.value.start);

        let parent = op.parent();
        let child = op.next_sibling();

        while (child != null && !root.ast.same_node(child, cl)) {
            let next = child.next_sibling();
            node.append_child(child);
            child = next;
        }
        if (parent != null) {
            parent.insert_after(op, node);
        }

        let c = op.next_delimiter;
        while (c != null && !same_delimiter(c, cl)) {
            let next = c.next_delimiter;
            pc.remove_delimiter(c);
            c = next;
        }

        if (op.length == 0) {
            pc.remove_delimiter(op);
        }

        if (cl.length == 0) {
            let next = cl.next_delimiter;
            pc.remove_delimiter(cl);
            closer = next;
        }
    }
    pc.clear_delimiters(bottom);
}
