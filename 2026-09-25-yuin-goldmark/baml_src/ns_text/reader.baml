// Port of goldmark text/reader.go.
//
// Porting notes:
// - Go's `Segment` is a value type; the reader mutates its `pos` field in
//   place. In this port `Segment` instances are treated as immutable: the
//   readers replace `self.pos` with a fresh Segment instead of mutating it, so
//   segments handed out by `position()` / `peek_line()` can never alias the
//   reader's internal state.
// - Go's multi-value returns (`PeekLine() ([]byte, Segment)` etc.) become small
//   result classes.
// - `io.RuneReader` is ported as `read_rune()` returning a `RuneResult`
//   (`size == 0` stands in for `io.EOF`).
// - `*regexp.Regexp` is ported as `baml.regex.Regex`, which matches on strings;
//   the line is decoded (lossily) to a string for matching and match offsets
//   are converted back from code points to bytes.

/// Go's unexported `invalidValue`.
function INVALID_VALUE() -> int {
    -1
}

/// EOF indicates the end of file (Go: `const EOF = byte(0xff)`).
function EOF() -> int {
    0xff
}

/// Result of `Reader.peek_line()` (Go: `([]byte, Segment)`).
/// `line` is null where Go returns a nil slice.
class PeekedLine {
    line: uint8array?,
    segment: Segment,
}

/// Result of `Reader.position()` (Go: `(int, Segment)`).
class ReaderPosition {
    line: int,
    segment: Segment,
}

/// Result of `skip_spaces` / `skip_blank_lines` (Go: `(Segment, int, bool)`).
class SkipResult {
    segment: Segment,
    count: int,
    ok: bool,
}

/// Result of `read_rune` (Go: `(rune, int, error)`); `size == 0` means EOF.
class RuneResult {
    r: int,
    size: int,
}

/// A Reader interface provides abstracted method for reading text.
interface Reader {
    /// ReadRune implements io.RuneReader.
    function read_rune(self) -> RuneResult throws never

    /// Source returns a source of the reader.
    function source(self) -> uint8array throws never

    /// ResetPosition resets positions.
    function reset_position(self) -> void throws never

    /// Peek returns a byte at current position without advancing the internal pointer.
    function peek(self) -> int throws never

    /// PeekLine returns the current line without advancing the internal pointer.
    function peek_line(self) -> PeekedLine throws never

    /// PrecedingCharacter returns a character just before current internal pointer.
    function preceding_character(self) -> int throws never

    /// ValueBetween returns a MultiLineValue covering the given [start, stop)
    /// byte range within the source.
    ///
    /// Value will be decoded using the Decoder bound to this reader.
    function value_between(self, start: int, stop: int) -> MultiLineValue throws never

    /// Decoder returns the Decoder bound to this reader. Values constructed
    /// from positions within this reader's source should be bound to this
    /// Decoder.
    function decoder(self) -> Decoder throws never

    /// LineOffset returns a distance from the line head to current position.
    function line_offset(self) -> int throws never

    /// Position returns current line number and position.
    function position(self) -> ReaderPosition throws never

    /// SetPosition sets current line number and position.
    function set_position(self, line: int, pos: Segment) -> void throws never

    /// SetPadding sets padding to the reader.
    function set_padding(self, v: int) -> void throws never

    /// Advance advances the internal pointer.
    function advance(self, n: int) -> void throws never

    /// AdvanceAndSetPadding advances the internal pointer and add padding to the
    /// reader.
    function advance_and_set_padding(self, n: int, padding: int) -> void throws never

    /// AdvanceToEOL advances the internal pointer to the end of line.
    /// If the line ends with a newline, it will be included in the segment.
    /// If the line ends with EOF, it will not be included in the segment.
    function advance_to_eol(self) -> void throws never

    /// AdvanceLine advances the internal pointer to the next line head.
    function advance_line(self) -> void throws never

    /// SkipSpaces skips space characters and returns a non-blank line.
    /// If it reaches EOF, returns false.
    function skip_spaces(self) -> SkipResult throws never

    /// SkipBlankLines skips blank lines and returns a non-blank line.
    /// If it reaches EOF, returns false.
    function skip_blank_lines(self) -> SkipResult throws never

    /// Match performs regular expression matching to current line.
    function match_regexp(self, reg: baml.regex.Regex) -> bool throws never

    /// Match performs regular expression searching to current line.
    /// Returns null when there is no match (Go: nil).
    function find_sub_match(self, reg: baml.regex.Regex) -> uint8array[]? throws never
}

/// Go's unexported `reader`.
class BasicReader {
    src: uint8array,
    source_length: int,
    line: int,
    peeked_line: uint8array?,
    pos: Segment,
    head: int,
    line_offset_cache: int,
    dec: Decoder,

    implements Reader {
        function reset_position(self) -> void {
            self.line = -1;
            self.head = 0;
            self.line_offset_cache = -1;
            self.advance_line();
        }

        function source(self) -> uint8array {
            self.src
        }

        function value_between(self, start: int, stop: int) -> MultiLineValue {
            new_multi_line_value_from_index(new_index(start, stop), self.dec)
        }

        function decoder(self) -> Decoder {
            self.dec
        }

        function peek(self) -> int {
            if (self.pos.start >= 0 && self.pos.start < self.source_length) {
                if (self.pos.padding != 0) {
                    return 32;
                }
                return self.src[self.pos.start];
            }
            EOF()
        }

        function peek_line(self) -> PeekedLine {
            if (self.pos.start >= 0 && self.pos.start < self.source_length && self.pos.start < self.pos.stop) {
                let pl = self.peeked_line;
                if (pl == null) {
                    let b = self.pos.bytes(self.src);
                    self.peeked_line = b;
                    return PeekedLine { line: b, segment: self.pos };
                }
                return PeekedLine { line: pl, segment: self.pos };
            }
            PeekedLine { line: null, segment: self.pos }
        }

        function read_rune(self) -> RuneResult {
            read_rune_reader(self)
        }

        function line_offset(self) -> int {
            if (self.line_offset_cache < 0) {
                let v = 0;
                let i = self.head;
                while (i < self.pos.start) {
                    if (self.src[i] == 9) {
                        v += root.util.tab_width(v);
                    } else {
                        v += 1;
                    }
                    i += 1;
                }
                self.line_offset_cache = v - self.pos.padding;
            }
            self.line_offset_cache
        }

        function preceding_character(self) -> int {
            if (self.pos.start <= 0) {
                if (self.pos.padding != 0) {
                    return 32;
                }
                return 10;
            }
            let i = self.pos.start - 1;
            while (i >= 0) {
                if (root.util.utf8_rune_start(self.src[i])) {
                    break;
                }
                i -= 1;
            }
            root.util.utf8_decode_rune(self.src, i).r
        }

        function advance(self, n: int) -> void {
            if (n < self.pos.stop - self.pos.start && self.pos.padding == 0) {
                // The advanced range contains no tab, so lineOffset (if already
                // known) can be updated by exactly n instead of being invalidated
                // and recomputed from the line head on the next LineOffset call.
                if (self.line_offset_cache >= 0) {
                    if (root.util.index_byte_in_range(self.src, self.pos.start, self.pos.start + n, 9) == -1) {
                        self.line_offset_cache += n;
                    } else {
                        self.line_offset_cache = -1;
                    }
                }
                self.pos = pos_with_start(self.pos, self.pos.start + n);
                self.peeked_line = null;
                return;
            }
            self.line_offset_cache = -1;
            self.peeked_line = null;
            let l = self.source_length;
            let k = n;
            while (k > 0 && self.pos.start < l) {
                if (self.pos.padding != 0) {
                    self.pos = pos_with_padding(self.pos, self.pos.padding - 1);
                    k -= 1;
                    continue;
                }
                if (self.src[self.pos.start] == 10) {
                    self.advance_line();
                    k -= 1;
                    continue;
                }
                self.pos = pos_with_start(self.pos, self.pos.start + 1);
                k -= 1;
            }
        }

        function advance_and_set_padding(self, n: int, padding: int) -> void {
            self.advance(n);
            if (padding > self.pos.padding) {
                self.set_padding(padding);
            }
        }

        function advance_to_eol(self) -> void {
            if (self.pos.start >= self.source_length) {
                return;
            }
            self.line_offset_cache = -1;
            let i = -1;
            let start = self.pos.start;
            let pl = self.peeked_line;
            if (pl != null) {
                start += pl.length() - self.pos.padding - 1;
                if (self.src[start] == 10) {
                    i = 0;
                }
            }
            if (i == -1) {
                i = root.util.index_byte_from(self.src, start, 10);
                if (i != -1) {
                    i -= start;
                }
            }
            self.peeked_line = null;
            if (i != -1) {
                start += i;
            } else {
                start = self.source_length;
            }
            self.pos = Segment { start: start, stop: self.pos.stop, padding: 0, force_newline: self.pos.force_newline };
        }

        function advance_line(self) -> void {
            self.line_offset_cache = -1;
            self.peeked_line = null;
            let start = self.pos.stop;
            self.head = start;
            if (start < 0 || start >= self.source_length) {
                self.pos = Segment { start: start, stop: self.pos.stop, padding: self.pos.padding, force_newline: self.pos.force_newline };
                return;
            }
            let stop = self.source_length;
            let i = 0;
            if (self.src[start] != 10) {
                i = root.util.index_byte_from(self.src, start, 10);
                if (i != -1) {
                    i -= start;
                }
            }
            if (i != -1) {
                stop = start + i + 1;
            }
            self.line += 1;
            self.pos = Segment { start: start, stop: stop, padding: 0, force_newline: self.pos.force_newline };
        }

        function position(self) -> ReaderPosition {
            ReaderPosition { line: self.line, segment: self.pos }
        }

        function set_position(self, line: int, pos: Segment) -> void {
            self.line_offset_cache = -1;
            self.line = line;
            self.pos = pos;
            // Go keeps peekedLine here; since `pos` may differ, drop the cache
            // unless the position is unchanged (Go relies on callers only
            // restoring previously observed positions).
            self.peeked_line = null;
        }

        function set_padding(self, v: int) -> void {
            self.pos = pos_with_padding(self.pos, v);
            self.peeked_line = null;
        }

        function skip_spaces(self) -> SkipResult {
            skip_spaces_reader(self)
        }

        function skip_blank_lines(self) -> SkipResult {
            skip_blank_lines_reader(self)
        }

        function match_regexp(self, reg: baml.regex.Regex) -> bool {
            match_reader(self, reg)
        }

        function find_sub_match(self, reg: baml.regex.Regex) -> uint8array[]? {
            find_sub_match_reader(self, reg)
        }
    }
}

/// Returns a copy of `s` with a different start (keeps padding/force_newline).
function pos_with_start(s: Segment, start: int) -> Segment {
    Segment { start: start, stop: s.stop, padding: s.padding, force_newline: s.force_newline }
}

/// Returns a copy of `s` with a different padding.
function pos_with_padding(s: Segment, padding: int) -> Segment {
    Segment { start: s.start, stop: s.stop, padding: padding, force_newline: s.force_newline }
}

/// NewReader return a new Reader that can read UTF-8 bytes, decoding
/// constructed Values using the given Decoder.
/// b need not be a Markdown document's source; it may be any byte slice,
/// e.g. a substring extracted from a Value.
function new_reader(b: uint8array, decoder: Decoder) -> Reader {
    let r = BasicReader {
        src: b,
        source_length: b.length(),
        line: -1,
        peeked_line: null,
        pos: new_segment(0, 0),
        head: 0,
        line_offset_cache: -1,
        dec: decoder,
    };
    r.reset_position();
    r
}

/// A BlockReader interface is a reader that is optimized for Blocks.
interface BlockReader requires Reader {
    /// Reset resets current state and sets new segments to the reader.
    function reset(self, segs: Segment[]) -> void throws never
}

/// Go's unexported `blockReader`.
class BasicBlockReader {
    src: uint8array,
    segments: Segment[],
    line: int,
    pos: Segment,
    head: int,
    last: int,
    line_offset_cache: int,
    dec: Decoder,
    // Not in Go: caches the bytes of the current line, keyed by the position
    // they were computed for. Go's PeekLine returns an O(1) subslice; BAML
    // slices copy, so avoiding recomputation matters (e.g. every inline parser
    // tried at a position peeks the rest of the line, and the parser restores
    // the position between attempts).
    peeked_line: uint8array?,
    peeked_start: int,
    peeked_stop: int,
    peeked_padding: int,

    implements BlockReader {
        function reset(self, segs: Segment[]) -> void {
            self.segments = segs;
            self.reset_position();
        }
    }

    implements Reader {
        function reset_position(self) -> void {
            self.line = -1;
            self.head = 0;
            self.last = 0;
            self.line_offset_cache = -1;
            self.pos = new_segment(-1, -1);
            self.peeked_line = null;
            let n = self.segments.length();
            if (n > 0) {
                self.last = self.segments[n - 1].stop;
            }
            self.advance_line();
        }

        function source(self) -> uint8array {
            self.src
        }

        function value_between(self, start: int, stop: int) -> MultiLineValue {
            let builder = new_value_builder();
            builder.decoder(self.dec);
            for (let s in self.segments) {
                if (s.stop <= start) {
                    continue;
                }
                if (s.start >= stop) {
                    break;
                }
                let seg = s;
                if (seg.start < start) {
                    seg = Segment { start: start, stop: seg.stop, padding: 0, force_newline: seg.force_newline };
                }
                if (seg.stop > stop) {
                    seg = Segment { start: seg.start, stop: stop, padding: seg.padding, force_newline: seg.force_newline };
                }
                builder.add_segment(seg);
            }
            builder.build_multi_line()
        }

        function decoder(self) -> Decoder {
            self.dec
        }

        function read_rune(self) -> RuneResult {
            read_rune_reader(self)
        }

        function preceding_character(self) -> int {
            if (self.pos.padding != 0) {
                return 32;
            }
            if (self.segments.length() < 1) {
                return 10;
            }
            let first_segment = self.segments[0];
            if (self.line == 0 && self.pos.start <= first_segment.start) {
                return 10;
            }
            let l = self.src.length();
            let i = self.pos.start - 1;
            while (i < l && i >= 0) {
                if (root.util.utf8_rune_start(self.src[i])) {
                    break;
                }
                i -= 1;
            }
            if (i < 0 || i >= l) {
                return 10;
            }
            root.util.utf8_decode_rune(self.src, i).r
        }

        function line_offset(self) -> int {
            if (self.line_offset_cache < 0) {
                let v = 0;
                let i = self.head;
                while (i < self.pos.start) {
                    if (self.src[i] == 9) {
                        v += root.util.tab_width(v);
                    } else {
                        v += 1;
                    }
                    i += 1;
                }
                self.line_offset_cache = v - self.pos.padding;
            }
            self.line_offset_cache
        }

        function peek(self) -> int {
            if (self.line < self.segments.length() && self.pos.start >= 0 && self.pos.start < self.last) {
                if (self.pos.padding != 0) {
                    return 32;
                }
                return self.src[self.pos.start];
            }
            EOF()
        }

        function peek_line(self) -> PeekedLine {
            if (self.line < self.segments.length() && self.pos.start >= 0 && self.pos.start < self.last) {
                let pl = self.peeked_line;
                if (pl != null) {
                    if (self.peeked_start == self.pos.start && self.peeked_stop == self.pos.stop && self.peeked_padding == self.pos.padding && !self.pos.force_newline) {
                        return PeekedLine { line: pl, segment: self.pos };
                    }
                }
                let b = self.pos.bytes(self.src);
                self.peeked_line = b;
                self.peeked_start = self.pos.start;
                self.peeked_stop = self.pos.stop;
                self.peeked_padding = self.pos.padding;
                return PeekedLine { line: b, segment: self.pos };
            }
            PeekedLine { line: null, segment: self.pos }
        }

        function advance(self, n: int) -> void {
            self.peeked_line = null;
            if (n < self.pos.stop - self.pos.start && self.pos.padding == 0) {
                // The advanced range contains no tab, so lineOffset (if already
                // known) can be updated by exactly n instead of being invalidated
                // and recomputed from the line head on the next LineOffset call.
                if (self.line_offset_cache >= 0) {
                    if (root.util.index_byte_in_range(self.src, self.pos.start, self.pos.start + n, 9) == -1) {
                        self.line_offset_cache += n;
                    } else {
                        self.line_offset_cache = -1;
                    }
                }
                self.pos = pos_with_start(self.pos, self.pos.start + n);
                return;
            }

            self.line_offset_cache = -1;
            let k = n;
            while (k > 0) {
                if (self.pos.padding != 0) {
                    self.pos = pos_with_padding(self.pos, self.pos.padding - 1);
                    k -= 1;
                    continue;
                }
                if (self.pos.start >= self.pos.stop - 1 && self.pos.stop < self.last) {
                    self.advance_line();
                    k -= 1;
                    continue;
                }
                self.pos = pos_with_start(self.pos, self.pos.start + 1);
                k -= 1;
            }
        }

        function advance_and_set_padding(self, n: int, padding: int) -> void {
            self.advance(n);
            if (padding > self.pos.padding) {
                self.set_padding(padding);
            }
        }

        function advance_to_eol(self) -> void {
            self.line_offset_cache = -1;
            self.peeked_line = null;
            let c = self.src[self.pos.stop - 1];
            let start = if (c == 10) { self.pos.stop - 1 } else { self.pos.stop };
            self.pos = Segment { start: start, stop: self.pos.stop, padding: 0, force_newline: self.pos.force_newline };
        }

        function advance_line(self) -> void {
            self.set_position(self.line + 1, new_segment(INVALID_VALUE(), INVALID_VALUE()));
            self.head = self.pos.start;
        }

        function position(self) -> ReaderPosition {
            ReaderPosition { line: self.line, segment: self.pos }
        }

        function set_position(self, line: int, pos: Segment) -> void {
            self.line_offset_cache = -1;
            self.peeked_line = null;
            self.line = line;
            if (pos.start == INVALID_VALUE()) {
                if (self.line < self.segments.length()) {
                    let s = self.segments[line];
                    self.head = s.start;
                    self.pos = s;
                }
            } else {
                self.pos = pos;
                if (self.line < self.segments.length()) {
                    let s = self.segments[line];
                    self.head = s.start;
                }
            }
        }

        function set_padding(self, v: int) -> void {
            self.line_offset_cache = -1;
            self.peeked_line = null;
            self.pos = pos_with_padding(self.pos, v);
        }

        function skip_spaces(self) -> SkipResult {
            skip_spaces_reader(self)
        }

        function skip_blank_lines(self) -> SkipResult {
            skip_blank_lines_reader(self)
        }

        function match_regexp(self, reg: baml.regex.Regex) -> bool {
            match_reader(self, reg)
        }

        function find_sub_match(self, reg: baml.regex.Regex) -> uint8array[]? {
            find_sub_match_reader(self, reg)
        }
    }
}

/// NewBlockReader returns a new BlockReader, decoding constructed Values
/// using the given Decoder. Go accepts a nil `segs`; here pass null.
function new_block_reader(source: uint8array, segs: Segment[]?, decoder: Decoder) -> BlockReader {
    let r = BasicBlockReader {
        src: source,
        segments: [],
        line: -1,
        pos: new_segment(-1, -1),
        head: 0,
        last: 0,
        line_offset_cache: -1,
        dec: decoder,
        peeked_line: null,
        peeked_start: -1,
        peeked_stop: -1,
        peeked_padding: -1,
    };
    if (segs != null) {
        r.reset(segs);
    }
    r
}

function skip_blank_lines_reader(r: Reader) -> SkipResult {
    let lines = 0;
    while (true) {
        let pl = r.peek_line();
        let line = pl.line;
        if (line == null) {
            return SkipResult { segment: pl.segment, count: lines, ok: false };
        }
        if (root.util.is_blank(line)) {
            lines += 1;
            r.advance_line();
        } else {
            return SkipResult { segment: pl.segment, count: lines, ok: true };
        }
    }
    SkipResult { segment: new_segment(0, 0), count: lines, ok: false }
}

function skip_spaces_reader(r: Reader) -> SkipResult {
    let chars = 0;
    while (true) {
        let pl = r.peek_line();
        let line = pl.line;
        if (line == null) {
            return SkipResult { segment: pl.segment, count: chars, ok: false };
        }
        let segment = pl.segment;
        let i = 0;
        let n = line.length();
        while (i < n && root.util.is_space(line[i])) {
            i += 1;
        }
        if (i > 0) {
            r.advance(i);
            chars += i;
        }
        if (i < n) {
            return SkipResult { segment: segment.with_start(segment.start + i + 1), count: chars, ok: true };
        }
    }
    SkipResult { segment: new_segment(0, 0), count: chars, ok: false }
}

/// Converts a code-point offset within `s` to a UTF-8 byte offset.
function cp_offset_to_byte(s: string, cp: int) -> int {
    s.slice(0, cp).byte_length()
}

/// A regexp match translated to byte offsets (Go: `FindSubmatchIndex` result).
/// `loc` holds start/stop byte offsets pairs; -1 for non-participating groups.
function regexp_find_submatch_index(reg: baml.regex.Regex, line: uint8array) -> int[]? {
    let s = line.to_string();
    let m = reg.match_once(s);
    if (m == null) {
        return null;
    }
    // groups[0] is the whole match, like Go's loc[0:2].
    let loc: int[] = [];
    for (let g in m.groups) {
        if (g == null) {
            loc.push(-1);
            loc.push(-1);
        } else {
            loc.push(cp_offset_to_byte(s, g.start));
            loc.push(cp_offset_to_byte(s, g.end));
        }
    }
    loc
}

function match_reader(r: Reader, reg: baml.regex.Regex) -> bool {
    let pl = r.peek_line();
    let line = pl.line;
    if (line == null) {
        return false;
    }
    let loc = regexp_find_submatch_index(reg, line);
    // BAML: `loc != null && loc[1] ...` does not narrow `loc`; nest instead.
    if (loc != null) {
        if (loc[1] < line.length()) {
            r.advance(loc[1] - loc[0]);
            return true;
        }
    }
    // TODO(port): Go falls back to `reg.FindReaderSubmatchIndex(r)`, matching
    // across line boundaries through io.RuneReader. baml.regex has no
    // streaming/reader API, so the fallback matches against the rest of the
    // source from the current position instead.
    let rest = remaining_bytes(r);
    let loc2 = regexp_find_submatch_index(reg, rest);
    if (loc2 == null) {
        return false;
    }
    r.advance(loc2[1] - loc2[0]);
    true
}

/// Bytes from the current position to the end of the reader's content.
function remaining_bytes(r: Reader) -> uint8array {
    let old = r.position();
    let out = root.util.new_bytes();
    while (true) {
        let pl = r.peek_line();
        let line = pl.line;
        if (line == null) {
            break;
        }
        root.util.append_bytes(out, line);
        r.advance_line();
    }
    r.set_position(old.line, old.segment);
    out
}

function find_sub_match_reader(r: Reader, reg: baml.regex.Regex) -> uint8array[]? {
    let pl = r.peek_line();
    let line = pl.line;
    if (line == null) {
        return null;
    }
    let loc0 = regexp_find_submatch_index(reg, line);
    let src = line;
    let within = false;
    if (loc0 != null) {
        within = loc0[1] < line.length();
    }
    let loc = if (within) { loc0 } else {
        // See match_reader for the fallback caveat.
        src = remaining_bytes(r);
        regexp_find_submatch_index(reg, src)
    };
    if (loc == null) {
        return null;
    }
    let result: uint8array[] = [];
    let i = 0;
    while (i < loc.length() - 1) {
        if (loc[i] < 0) {
            result.push(root.util.new_bytes());
        } else {
            result.push(src.slice(loc[i], loc[i + 1]));
        }
        i += 2;
    }
    r.advance(loc[1] - loc[0]);
    result
}

function read_rune_reader(r: Reader) -> RuneResult {
    let pl = r.peek_line();
    let line = pl.line;
    if (line == null) {
        return RuneResult { r: 0, size: 0 };
    }
    let d = root.util.utf8_decode_rune(line, 0);
    if (d.r == 0xFFFD) {
        return RuneResult { r: 0, size: 0 };
    }
    r.advance(d.size);
    RuneResult { r: d.r, size: d.size }
}
