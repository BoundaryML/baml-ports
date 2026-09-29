// Port of goldmark text/value.go.
//
// Go's value types (`Index`, `Segment`, `SingleLineValue`, ...) are structs
// copied on assignment. BAML classes are reference types, so these classes are
// treated as immutable: every "modifying" method returns a new instance.

/// An Index represents a position range in a source byte slice.
/// Unlike Segment, Index does not carry parsing metadata such as
/// Padding or ForceNewline.
class Index {
    start: int,
    stop: int,

    /// IsEmpty returns true if this index is empty, otherwise false.
    function is_empty(self) -> bool {
        self.start >= self.stop
    }
}

/// NewIndex returns a new Index.
function new_index(start: int, stop: int) -> Index {
    Index { start: start, stop: stop }
}

/// NewIndexFromSegment returns a new Index derived from the given Segment,
/// dropping any padding and ignoring ForceNewline.
function new_index_from_segment(seg: Segment) -> Index {
    Index { start: seg.start, stop: seg.stop }
}

/// A Value represents an inline value.
interface Value {
    /// Value returns the decoded string representation of this value.
    function value(self, source: uint8array) -> string throws never

    /// Bytes returns the source byte slice corresponding to this value.
    function bytes(self, source: uint8array) -> uint8array throws never

    /// Str returns the string representation of this value.
    function str(self, source: uint8array) -> string throws never

    /// IsOwned returns true if this value is an owned string not derived from the source byte slice.
    function is_owned(self) -> bool throws never

    /// IsEmpty returns true if this value is empty, otherwise false.
    function is_empty(self) -> bool throws never

    /// Index returns the source position of this value.
    ///
    /// The result is meaningful only when IsOwned() returns false.
    /// If Value is backed by multiple source positions, Index returns the first position.
    function index(self) -> Index throws never

    /// Indices returns the slice of Index values in this value.
    ///
    /// The result is meaningful only when IsOwned() returns false.
    function indices(self) -> Index[] throws never

    /// WriteTo writes the value to the given buffer, using the [Value].Value.
    function write_to(self, w: root.util.BufWriter, source: uint8array) -> int throws never
}

function decoder_or_default(d: Decoder?) -> Decoder {
    d ?? identity_decoder()
}

/// A SingleLineValue holds a single-line inline value that is either an owned string
/// or a position range within a source byte slice.
/// Use SingleLineValue for data that must not contain newlines per the CommonMark spec
/// (e.g. link destinations, fenced code block info strings).
class SingleLineValue {
    decoder: Decoder?,
    s: string,
    idx: Index,

    /// WithStop returns a new SingleLineValue with the same start index but a different stop index.
    /// This method panics if the value is owned.
    function with_stop(self, stop: int) -> SingleLineValue {
        if (self.is_owned()) {
            baml.sys.panic("cannot set stop on owned value");
        }
        SingleLineValue { decoder: self.decoder, s: "", idx: new_index(self.idx.start, stop) }
    }

    implements Value {
        function value(self, source: uint8array) -> string throws never {
            decoder_or_default(self.decoder).decode(self.bytes(source)).to_string()
        }

        function bytes(self, source: uint8array) -> uint8array throws never {
            if (self.is_owned()) {
                return self.s.to_utf8();
            }
            source.slice(self.idx.start, self.idx.stop)
        }

        function str(self, source: uint8array) -> string throws never {
            if (self.is_owned()) {
                return self.s;
            }
            source.slice(self.idx.start, self.idx.stop).to_string()
        }

        function is_owned(self) -> bool throws never {
            self.idx.start == 0 && self.idx.stop == 0
        }

        function is_empty(self) -> bool throws never {
            if (self.is_owned()) {
                return self.s == "";
            }
            self.idx.start >= self.idx.stop
        }

        function index(self) -> Index throws never {
            self.idx
        }

        function indices(self) -> Index[] throws never {
            [self.idx]
        }

        function write_to(self, w: root.util.BufWriter, source: uint8array) -> int throws never {
            decoder_or_default(self.decoder).decode_to(w, self.bytes(source))
        }
    }
}

/// NewSingleLineValueFromIndex returns a Value backed by a source position, bound to the
/// given Decoder.
function new_single_line_value_from_index(i: Index, decoder: Decoder?) -> SingleLineValue {
    SingleLineValue { decoder: decoder, s: "", idx: i }
}

/// NewSingleLineValueFromSegment returns a Value backed by a source position derived from the
/// given Segment, bound to the given Decoder.
function new_single_line_value_from_segment(seg: Segment, decoder: Decoder?) -> SingleLineValue {
    new_single_line_value_from_index(new_index_from_segment(seg), decoder)
}

/// NewSingleLineValueFromString returns a Value backed by an owned string, bound to the
/// given Decoder.
/// This function does not check whether the string contains newlines; it is
/// the caller's responsibility to ensure that the string is single-line.
function new_single_line_value_from_string(s: string, decoder: Decoder?) -> SingleLineValue {
    SingleLineValue { decoder: decoder, s: s, idx: new_index(0, 0) }
}

/// NewSingleLineValue from bytes (Go generic `NewSingleLineValue[[]byte]`).
function new_single_line_value_from_bytes(b: uint8array, decoder: Decoder?) -> SingleLineValue {
    new_single_line_value_from_string(b.to_string(), decoder)
}

/// Returns a zero SingleLineValue (Go: `text.SingleLineValue{}`).
function empty_single_line_value() -> SingleLineValue {
    SingleLineValue { decoder: null, s: "", idx: new_index(0, 0) }
}

/// A MultiLineValue holds a potentially multiline inline value that is
/// either an owned string or a set of source position ranges.
/// Use MultiLineValue for data that may span multiple lines per the CommonMark
/// spec (e.g. link labels).
///
/// When constructing the byte value from source positions, the ranges are
/// simply concatenated verbatim; no newline folding or other transformation
/// is applied.
class MultiLineValue {
    decoder: Decoder?,
    s: string,
    /// Go stores a single index inline (`index [1]Index`) and multiple
    /// indices in `indices`; `idx_list == null` mirrors a nil slice.
    idx: Index,
    idx_list: Index[]?,

    implements Value {
        function value(self, source: uint8array) -> string throws never {
            let d = decoder_or_default(self.decoder);
            if (self.is_owned()) {
                return d.decode(self.s.to_utf8()).to_string();
            }
            if (self.idx.start != 0 || self.idx.stop != 0) {
                return d.decode(source.slice(self.idx.start, self.idx.stop)).to_string();
            }
            let list = self.idx_list ?? [];
            if (list.length() == 0) {
                return "";
            }
            if (list.length() == 1) {
                return d.decode(source.slice(list[0].start, list[0].stop)).to_string();
            }
            let c = contiguous_indices(list);
            if (c != null) {
                return d.decode(source.slice(c.start, c.stop)).to_string();
            }
            let b = root.util.new_bytes();
            for (let idx in list) {
                root.util.append_bytes(b, d.decode(source.slice(idx.start, idx.stop)));
            }
            b.to_string()
        }

        function bytes(self, source: uint8array) -> uint8array throws never {
            if (self.is_owned()) {
                return self.s.to_utf8();
            }
            if (self.idx.start != 0 || self.idx.stop != 0) {
                return source.slice(self.idx.start, self.idx.stop);
            }
            let list = self.idx_list ?? [];
            if (list.length() == 0) {
                return root.util.new_bytes();
            }
            if (list.length() == 1) {
                return source.slice(list[0].start, list[0].stop);
            }
            let buf = root.util.new_bytes();
            for (let idx in list) {
                root.util.append_bytes(buf, source.slice(idx.start, idx.stop));
            }
            buf
        }

        function str(self, source: uint8array) -> string throws never {
            if (self.is_owned()) {
                return self.s;
            }
            self.bytes(source).to_string()
        }

        function is_owned(self) -> bool throws never {
            self.idx_list == null && self.idx.start == 0 && self.idx.stop == 0
        }

        function is_empty(self) -> bool throws never {
            if (self.is_owned()) {
                return self.s == "";
            }
            if (self.idx.start != 0 || self.idx.stop != 0) {
                return self.idx.start >= self.idx.stop;
            }
            for (let idx in self.idx_list ?? []) {
                if (idx.start < idx.stop) {
                    return false;
                }
            }
            true
        }

        function index(self) -> Index throws never {
            if (self.idx.start != 0 || self.idx.stop != 0) {
                return self.idx;
            }
            let list = self.idx_list ?? [];
            if (list.length() > 0) {
                return list[0];
            }
            new_index(0, 0)
        }

        function indices(self) -> Index[] throws never {
            if (self.idx.start != 0 || self.idx.stop != 0) {
                return [self.idx];
            }
            self.idx_list ?? []
        }

        function write_to(self, w: root.util.BufWriter, source: uint8array) -> int throws never {
            let d = decoder_or_default(self.decoder);
            if (self.is_owned()) {
                return d.decode_to(w, self.s.to_utf8());
            }
            if (self.idx.start != 0 || self.idx.stop != 0) {
                return d.decode_to(w, source.slice(self.idx.start, self.idx.stop));
            }
            let n = 0;
            for (let idx in self.idx_list ?? []) {
                n += d.decode_to(w, source.slice(idx.start, idx.stop));
            }
            n
        }
    }
}

/// Go's `contiguousIndices`: returns the covering index when all indices are
/// contiguous, otherwise null.
function contiguous_indices(indices: Index[]) -> Index? {
    let start = indices[0].start;
    let stop = indices[0].stop;
    let i = 1;
    while (i < indices.length()) {
        let idx = indices[i];
        if (idx.start != stop) {
            return null;
        }
        stop = idx.stop;
        i += 1;
    }
    new_index(start, stop)
}

/// NewMultiLineValueFromIndex returns a MultiLineValue backed by a single source position,
/// bound to the given Decoder.
function new_multi_line_value_from_index(i: Index, decoder: Decoder?) -> MultiLineValue {
    MultiLineValue { decoder: decoder, s: "", idx: i, idx_list: null }
}

/// NewMultiLineValueFromIndices returns a MultiLineValue backed by source positions,
/// bound to the given Decoder.
function new_multi_line_value_from_indices(indices: Index[], decoder: Decoder?) -> MultiLineValue {
    if (indices.length() == 1) {
        return MultiLineValue { decoder: decoder, s: "", idx: indices[0], idx_list: null };
    }
    MultiLineValue { decoder: decoder, s: "", idx: new_index(0, 0), idx_list: indices }
}

/// NewMultiLineValueFromString returns a MultiLineValue backed by an owned string, bound to
/// the given Decoder.
function new_multi_line_value_from_string(s: string, decoder: Decoder?) -> MultiLineValue {
    MultiLineValue { decoder: decoder, s: s, idx: new_index(0, 0), idx_list: null }
}

/// NewMultiLineValue from bytes (Go generic `NewMultiLineValue[[]byte]`).
function new_multi_line_value_from_bytes(b: uint8array, decoder: Decoder?) -> MultiLineValue {
    new_multi_line_value_from_string(b.to_string(), decoder)
}

/// Returns a zero MultiLineValue (Go: `text.MultiLineValue{}`).
function empty_multi_line_value() -> MultiLineValue {
    MultiLineValue { decoder: null, s: "", idx: new_index(0, 0), idx_list: null }
}

/// ValueBuilder is a helper for building a [Value].
class ValueBuilder {
    dec: Decoder?,
    s: string,
    idx: Index,
    idx_list: Index[]?,

    /// AddIndex adds an Index to the builder.
    function add_index(self, i: Index) -> ValueBuilder {
        if (self.idx.start == 0 && self.idx.stop == 0 && self.idx_list == null) {
            self.idx = i;
            return self;
        }
        if (self.idx_list == null) {
            self.idx_list = [self.idx];
            self.idx = new_index(0, 0);
        }
        self.idx_list?.push(i);
        self
    }

    /// Decoder sets the Decoder to be bound to the Value produced by Build, BuildSingleLine,
    /// or BuildMultiLine. If not set, the produced Value is bound to [IdentityDecoder].
    function decoder(self, d: Decoder?) -> ValueBuilder {
        self.dec = d;
        self
    }

    /// AddSegment adds an Index derived from the given Segment to the builder.
    function add_segment(self, seg: Segment) -> ValueBuilder {
        self.add_index(new_index_from_segment(seg))
    }

    /// OwnedString sets an owned string value. When Build is called, the resulting
    /// Value will be backed by this string rather than any accumulated indices.
    function owned_string(self, s: string) -> ValueBuilder {
        self.s = s;
        self
    }

    /// OwnedBytes sets an owned string value from the given byte slice.
    function owned_bytes(self, bts: uint8array) -> ValueBuilder {
        self.s = bts.to_string();
        self
    }

    function is_single(self) -> bool {
        self.idx_list == null && self.s == ""
    }

    /// BuildMultiLine returns a MultiLineValue from the accumulated state.
    function build_multi_line(self) -> MultiLineValue {
        let d = decoder_or_default(self.dec);
        if (self.s != "") {
            return new_multi_line_value_from_string(self.s, d);
        }
        if (self.is_single()) {
            return new_multi_line_value_from_index(self.idx, d);
        }
        new_multi_line_value_from_indices(self.idx_list ?? [], d)
    }

    /// BuildSingleLine returns a SingleLineValue from the accumulated state.
    function build_single_line(self) -> SingleLineValue {
        let d = decoder_or_default(self.dec);
        if (self.s != "") {
            return new_single_line_value_from_string(self.s, d);
        }
        new_single_line_value_from_index(self.idx, d)
    }

    /// Build returns a Value from the accumulated state.
    function build(self) -> Value {
        if (self.s != "") {
            if (!self.s.includes("\n")) {
                return self.build_single_line();
            }
            return self.build_multi_line();
        }
        if (self.is_single()) {
            return self.build_single_line();
        }
        self.build_multi_line()
    }
}

/// Returns a new empty ValueBuilder (Go: `var builder ValueBuilder`).
function new_value_builder() -> ValueBuilder {
    ValueBuilder { dec: null, s: "", idx: new_index(0, 0), idx_list: null }
}

/// A Lines value holds the raw content of a block node.  It is either an
/// owned string or a sequence of Segment values copied from the parser's
/// source-segment list.
///
/// Lines is used for block nodes whose rendered content is taken directly from the
/// source (e.g. CodeBlock, FencedCodeBlock, HTMLBlock).
///
/// Lines is always 'raw'; it does not perform any decoding of the source content.
class Lines {
    s: string,
    /// null mirrors a nil segment slice (an owned Lines).
    segs: Segment[]?,

    /// Segments returns the internal segment slice.
    function segments(self) -> Segment[] {
        self.segs ?? []
    }

    /// AppendSegment appends a Segment to the internal segment list.
    function append_segment(self, seg: Segment) -> void {
        if (self.segs == null) {
            self.segs = [];
        }
        self.segs?.push(seg);
    }

    /// Bytes returns the concatenated byte content of all segments, or the
    /// owned string.
    function bytes(self, source: uint8array) -> uint8array {
        if (self.is_owned()) {
            return self.s.to_utf8();
        }
        let segs = self.segs ?? [];
        if (segs.length() == 0) {
            return root.util.new_bytes();
        }
        if (segs.length() == 1) {
            return segs[0].bytes(source);
        }
        // If all segments are contiguous in the source with no padding or
        // ForceNewline, return a single sub-slice.
        let first = segs[0];
        if (first.padding == 0 && !first.force_newline) {
            let contiguous = true;
            let prev = first;
            let i = 1;
            while (i < segs.length()) {
                let seg = segs[i];
                if (seg.padding != 0 || seg.force_newline || seg.start != prev.stop) {
                    contiguous = false;
                    break;
                }
                prev = seg;
                i += 1;
            }
            if (contiguous) {
                return source.slice(first.start, prev.stop);
            }
        }
        let result = root.util.new_bytes();
        for (let seg in segs) {
            root.util.append_bytes(result, seg.bytes(source));
        }
        result
    }

    /// Str returns the string representation of this value.
    function str(self, source: uint8array) -> string {
        if (self.is_owned()) {
            return self.s;
        }
        self.bytes(source).to_string()
    }

    /// WriteTo writes the value to the given buffer, using the [Lines].Bytes.
    function write_to(self, w: root.util.BufWriter, source: uint8array) -> int {
        if (self.is_owned()) {
            return w.write_string(self.s);
        }
        let segs = self.segs ?? [];
        if (segs.length() == 0) {
            return 0;
        }
        if (segs.length() == 1) {
            return w.write(segs[0].bytes(source));
        }
        let n = 0;
        for (let seg in segs) {
            let b = seg.bytes(source);
            n += w.write(b);
            if (seg.force_newline && (b.length() == 0 || b[b.length() - 1] != 10)) {
                n += w.write_string("\n");
            }
        }
        n
    }

    /// IsOwned returns true if this value is an owned string not derived from
    /// the source byte slice.
    function is_owned(self) -> bool {
        self.segs == null
    }
}

/// NewLinesFromSegments returns a Lines backed by source segments.
function new_lines_from_segments(segs: Segment[]) -> Lines {
    Lines { s: "", segs: segs }
}

/// NewLinesFromString returns a Lines backed by an owned string.
function new_lines_from_string(s: string) -> Lines {
    Lines { s: s, segs: null }
}

/// Returns a zero Lines (Go: `text.Lines{}`), which is owned and empty.
function empty_lines() -> Lines {
    Lines { s: "", segs: null }
}

/// A Segment struct holds information about source positions.
class Segment {
    /// Start is a start position of the segment.
    start: int,

    /// Stop is a stop position of the segment.
    /// This value should be excluded.
    stop: int,

    /// Padding is a padding length of the segment.
    padding: int,

    /// ForceNewline is true if the segment should be ended with a newline.
    /// Some elements(i.e. CodeBlock, FencedCodeBlock) does not trim trailing
    /// newlines. Spec defines that EOF is treated as a newline, so we need to
    /// add a newline to the end of the segment if it is not empty.
    force_newline: bool,

    /// Bytes returns bytes of the segment.
    function bytes(self, source: uint8array) -> uint8array {
        let result = if (self.padding == 0) {
            source.slice(self.start, self.stop)
        } else {
            let r = " ".repeat(self.padding).to_utf8();
            root.util.append_bytes(r, source.slice(self.start, self.stop));
            r
        };
        if (self.force_newline && result.length() > 0 && result[result.length() - 1] != 10) {
            result.push(10);
        }
        result
    }

    /// Str returns a string of the segment.
    function str(self, source: uint8array) -> string {
        self.bytes(source).to_string()
    }

    /// Len returns a length of the segment.
    function len(self) -> int {
        self.stop - self.start + self.padding
    }

    /// Between returns a segment between this segment and the given segment.
    function between(self, other: Segment) -> Segment {
        if (self.stop != other.stop) {
            baml.sys.panic("invalid state");
        }
        new_segment_padding(self.start, other.start, self.padding - other.padding)
    }

    /// IsEmpty returns true if this segment is empty, otherwise false.
    function is_empty(self) -> bool {
        self.start >= self.stop && self.padding == 0
    }

    /// TrimRightSpace returns a new segment by slicing off all trailing
    /// space characters.
    function trim_right_space(self, source: uint8array) -> Segment {
        let v = source.slice(self.start, self.stop);
        let l = root.util.trim_right_space_length(v);
        if (l == v.length()) {
            return new_segment(self.start, self.start);
        }
        new_segment_padding(self.start, self.stop - l, self.padding)
    }

    /// TrimLeftSpace returns a new segment by slicing off all leading
    /// space characters including padding.
    function trim_left_space(self, source: uint8array) -> Segment {
        let v = source.slice(self.start, self.stop);
        let l = root.util.trim_left_space_length(v);
        new_segment(self.start + l, self.stop)
    }

    /// TrimLeftSpaceWidth returns a new segment by slicing off leading space
    /// characters until the given width.
    ///
    /// Deprecated: This method does not handle tabs correctly.
    function trim_left_space_width(self, width: int, source: uint8array) -> Segment {
        let w = width;
        let padding = self.padding;
        while (w > 0) {
            if (padding == 0) {
                break;
            }
            padding -= 1;
            w -= 1;
        }
        if (w == 0) {
            return new_segment_padding(self.start, self.stop, padding);
        }
        let start = self.start;
        let i = self.start;
        while (i < self.stop) {
            let c = source[i];
            if (start >= self.stop - 1 || w <= 0) {
                break;
            }
            if (c == 32) {
                w -= 1;
            } else if (c == 9) {
                w -= 4;
            } else {
                break;
            }
            start += 1;
            i += 1;
        }
        if (w < 0) {
            padding = w * -1;
        }
        new_segment_padding(start, self.stop, padding)
    }

    /// WithStart returns a new Segment with the given Start and the same Stop.
    /// Padding and ForceNewline are reset to their zero values, since Padding
    /// describes space that precedes the original Start position.
    function with_start(self, v: int) -> Segment {
        new_segment_padding(v, self.stop, 0)
    }

    /// WithStop returns a new Segment with the given Stop and the same Start and
    /// Padding. ForceNewline is reset to false.
    function with_stop(self, v: int) -> Segment {
        new_segment_padding(self.start, v, self.padding)
    }

    /// Returns a copy of this segment (Go struct copy).
    function copy(self) -> Segment {
        Segment { start: self.start, stop: self.stop, padding: self.padding, force_newline: self.force_newline }
    }
}

/// NewSegment return a new Segment.
function new_segment(start: int, stop: int) -> Segment {
    Segment { start: start, stop: stop, padding: 0, force_newline: false }
}

/// NewSegmentPadding returns a new Segment with the given padding.
function new_segment_padding(start: int, stop: int, padding: int) -> Segment {
    Segment { start: start, stop: stop, padding: padding, force_newline: false }
}
