// Ported from sasso `src/sourcemap.rs` (namespace `root.sourcemap`).
//
// Source Map v3 generation — Phase A: the encoding primitives + JSON model.
//
// Zero-dependency (std only): a Base64-VLQ encoder, a builder that accumulates
// `(generated → source)` position segments, and the standard v3 JSON renderer.
// This module is self-contained and not yet wired into the serializer; later
// phases feed it from `emit.rs` and surface it through the public API.
//
// Format reference: the Source Map v3 spec (ECMA-426). All positions are
// 0-based; the generated column is in UTF-16 code units (the serializer is
// responsible for counting in those units when it feeds `add`).
//
// PORT: body offsets (`RawEntry::byte_off`, `SmCollector::scanned`, the
// `from`/`body_off` arguments) are CHARACTER offsets here, consistently with
// the serializer's `StrBuf` (PORTING_GUIDE §8). They are internal: `finalize`
// resolves them against the final text into (line, UTF-16 column), which is
// the same pair either way.

/// The Base64 alphabet used by both VLQ digits and the inline-map data URI.
function B64() -> uint8array {
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".to_utf8()
}

/// Append the Base64-VLQ encoding of a signed value to `out`.
///
/// The value is first zig-zag folded (sign in the least-significant bit), then
/// emitted little-endian in 5-bit groups; every non-final group sets the
/// continuation bit (0x20).
function vlq_encode(value: int, out: root.std.StrBuf) -> void {
    // PORT: `u64` → `int`; every value fed here is a u32 delta, far below 2^62.
    let v: int = if (value < 0) {
        (value.abs() << 1) | 1
    } else {
        value << 1
    };
    while (true) {
        let digit = v & 0x1f;
        v = v >> 5;
        if (v != 0) {
            digit = digit | 0x20; // continuation bit: more groups follow
        }
        out.push(root.std.chr_unchecked(B64()[digit]));
        if (v == 0) {
            break;
        }
    }
}

/// Standard Base64 of a byte slice (RFC 4648, with `=` padding). Used for the
/// `--embed-source-map` `data:application/json;base64,…` URI — distinct from the
/// per-5-bit VLQ digit encoding above.
// Reserved for the CLI/wasm `--embed-source-map` data-URI surface (a later
// phase); already covered by unit tests in this module.
function base64_bytes(data: uint8array) -> string {
    let out = root.std.StrBuf.with_capacity((data.length() + 2) / 3 * 4);
    // PORT: `data.chunks(3)` → an index loop over 3-byte windows.
    let at = 0;
    while (at < data.length()) {
        let chunk = data.slice(at, root.std.imin(at + 3, data.length()));
        at += 3;
        let b0 = chunk[0];
        let b1 = chunk.at(1) ?? 0;
        let b2 = chunk.at(2) ?? 0;
        let n = (b0 << 16) | (b1 << 8) | b2;
        out.push(root.std.chr_unchecked(B64()[(n >> 18) & 63]));
        out.push(root.std.chr_unchecked(B64()[(n >> 12) & 63]));
        out.push(
            if (chunk.length() > 1) {
                root.std.chr_unchecked(B64()[(n >> 6) & 63])
            } else {
                "="
            },
        );
        out.push(
            if (chunk.length() > 2) {
                root.std.chr_unchecked(B64()[n & 63])
            } else {
                "="
            },
        );
    }
    out.as_str()
}

/// One generated→source mapping. Fields are 0-based; `gen_col` is a UTF-16
/// column on the generated line `gen_line`. Names are not used for CSS, so there
/// is no name index (dart-sass emits 4-field segments for stylesheets).
class Segment {
    gen_col: int,
    src_id: int,
    src_line: int,
    src_col: int,
}

/// Accumulates mapping segments grouped by generated line, then renders the
/// delta-encoded `mappings` string.
class Mappings {
    /// `lines[g]` holds the segments on generated line `g`, in column order.
    lines: Segment[][],
    /// The evaluator's file ids in the order the mappings first reference
    /// them: `source_ids[i]` is the file behind `sources[i]`. Only files that
    /// actually produced a mapping appear (dart-sass lists no others).
    source_ids: int[],
    /// `source_slot[file_id]` is that file's `sources[]` index, or `NO_SOURCE`
    /// until the file's first mapping (file ids are dense, assigned 1,2,3,…).
    source_slot: int[],

    /// derive(Default)
    function default() -> Mappings {
        Mappings { lines: [], source_ids: [], source_slot: [] }
    }

    function new() -> Mappings {
        Mappings.default()
    }

    /// The file ids behind `sources[]`, in `sources` order.
    function source_ids_(self) -> int[] {
        self.source_ids
    }

    /// The `sources[]` index for an evaluator file id, assigning the next one
    /// on first sight. O(1): a dense slot table indexed by file id.
    function source_index(self, file_id: int) -> int {
        let slot = file_id;
        if (slot >= self.source_slot.length()) {
            // PORT: `resize(slot + 1, NO_SOURCE)`.
            while (self.source_slot.length() < slot + 1) {
                self.source_slot.push(NO_SOURCE());
            }
        }
        if (self.source_slot[slot] == NO_SOURCE()) {
            self.source_slot[slot] = self.source_ids.length();
            self.source_ids.push(file_id);
        }
        self.source_slot[slot]
    }

    /// Record a mapping at generated `(gen_line, gen_col)` back to source
    /// `(src_id, src_line, src_col)`. Callers add segments in generated order.
    function add(
        self,
        gen_line: int,
        gen_col: int,
        src_id: int,
        src_line: int,
        src_col: int,
    ) -> void {
        let g = gen_line;
        if (self.lines.length() <= g) {
            // PORT: `resize_with(g + 1, Vec::new)`.
            while (self.lines.length() < g + 1) {
                let empty: Segment[] = [];
                self.lines.push(empty);
            }
        }
        self.lines[g].push(
            Segment { gen_col: gen_col, src_id: src_id, src_line: src_line, src_col: src_col },
        );
    }

    /// Render the standard `mappings` field: generated lines separated by `;`,
    /// segments by `,`. `gen_col` resets to absolute at each line; `src_id`/
    /// `src_line`/`src_col` are deltas that persist across lines.
    function encode(self) -> string {
        let out = root.std.StrBuf.new();
        let p_id = 0;
        let p_line = 0;
        let p_col = 0;
        let i = 0;
        for (let line in self.lines) {
            if (i > 0) {
                out.push(";");
            }
            let p_gen = 0;
            let j = 0;
            for (let s in line) {
                if (j > 0) {
                    out.push(",");
                }
                vlq_encode(s.gen_col - p_gen, out);
                p_gen = s.gen_col;
                vlq_encode(s.src_id - p_id, out);
                p_id = s.src_id;
                vlq_encode(s.src_line - p_line, out);
                p_line = s.src_line;
                vlq_encode(s.src_col - p_col, out);
                p_col = s.src_col;
                j += 1;
            }
            i += 1;
        }
        out.as_str()
    }
}

function NO_SOURCE() -> int {
    4294967295
}

/// One raw mapped token recorded by the serializer: a byte offset into the
/// emitted CSS *body* (before any `@charset`/BOM prefix) and the 0-based source
/// position it came from. The body offset is resolved to a `(gen_line,
/// gen_col_utf16)` pair by [`SmCollector::finalize`] once the whole body — and
/// thus the prefix — is known.
class RawEntry {
    /// Byte offset into the CSS body where the mapped token begins.
    /// PORT: a CHARACTER offset (see the file header).
    byte_off: int,
    /// Evaluator-interned source file id (1-based; 0 = unknown, dropped).
    file_id: int,
    /// 0-based source line.
    src_line: int,
    /// 0-based source column.
    src_col: int,
}

/// Accumulates [`RawEntry`] records during emit. The serializer holds this in an
/// `Option`: `None` (the default `compile` path) records nothing and reads only
/// `out.len()`, so the CSS bytes are untouched.
class SmCollector {
    entries: RawEntry[],
    /// Whether the output is compressed — i.e. whether every token lands on
    /// generated line 0. See [`SmCollector::record`]: this is what decides
    /// whether two consecutive tokens share a GENERATED line.
    compressed: bool,
    /// The `(src_line, gen_line)` of the last recorded entry, for dart's
    /// redundancy rule. Generated lines are counted here (rather than resolved
    /// later in `finalize`) only for the comparison; the entry itself still
    /// stores a byte offset.
    last: root.std.Tuple2<int, int>?,
    /// Generated line of the last `record` call, advanced incrementally by
    /// counting the newlines the serializer appended since `scanned`.
    gen_line: int,
    /// Body length already scanned for newlines, so the walk is O(body) overall
    /// rather than O(body) per recorded token.
    scanned: int,

    /// derive(Default)
    function default() -> SmCollector {
        SmCollector { entries: [], compressed: false, last: null, gen_line: 0, scanned: 0 }
    }

    function new(compressed: bool) -> SmCollector {
        SmCollector { ...SmCollector.default(), compressed: compressed }
    }

    /// Record a mapped token at body byte offset `byte_off` whose source
    /// position is `(file_id, src_line, src_col)` (all 0-based; `file_id` is the
    /// 1-based interned id, 0 = unknown).
    ///
    /// dart's `SourceMapBuffer._addEntry` (util/source_map_buffer.dart:64)
    /// DROPS an entry that is redundant with the previous one:
    ///
    /// > Browsers don't care about the position of a value within a line, so
    /// > it's redundant to have two entries on the same target line that both
    /// > point to the same source line, even if they point to different
    /// > columns in that line.
    ///
    /// Note what that comparison does NOT include: the source FILE. Two tokens
    /// on the same generated line whose source lines happen to be equal collapse
    /// even when they come from different files — verified against dart 1.101.6,
    /// where `.q1 { }` (file A line 0) followed by an `@import`ed `.p1 { }`
    /// (file B line 0) emits a single segment in compressed output.
    ///
    /// This subsumes the old compressed-only heuristic: compressed output puts
    /// everything on generated line 0, so "same generated line" is always true
    /// there and the rule degenerates to "same source line as the previous
    /// token". In expanded output it only fires WITHIN a line — which is
    /// exactly where it matters now that a declaration emits a second entry for
    /// its value.
    /// `body` is the output written so far; only the slice appended since the
    /// previous call is scanned (for newlines), so the whole emit stays linear.
    // PORT: `body: &str` → the serializer's `StrBuf` itself, so the caller
    // never materializes the output just to hand it over; offsets are chars.
    function record(
        self,
        body: root.std.StrBuf,
        file_id: int,
        src_line: int,
        src_col: int,
    ) -> void {
        let byte_off = body.len();
        // A token with no known source file carries no usable mapping.
        if (file_id == 0) {
            return;
        }
        let gen_line = self.gen_line_at(body);
        let last = self.last;
        if (last != null) {
            if (last._0 == src_line && last._1 == gen_line) {
                return;
            }
        }
        self.last = root.std.Tuple2 { _0: src_line, _1: gen_line };
        self.entries.push(
            RawEntry { byte_off: byte_off, file_id: file_id, src_line: src_line, src_col: src_col },
        );
    }

    /// dart `SourceMapBuffer.writeCharCode` (util/source_map_buffer.dart):
    /// while a span is open, every newline written adds an entry at the start
    /// of the new generated line that points at the LAST entry's source — "so
    /// that source map consumers can identify the line-spanning mappings". A
    /// multi-line selector list, a multi-line comment or a re-indented custom
    /// property value thus maps every one of its output lines back to the
    /// construct's start. `from` is the body offset where the span's text
    /// began (just after its [`SmCollector::record`]); the caller has already
    /// appended the whole span. No-op with nothing recorded yet.
    function span_newlines(self, body: root.std.StrBuf, from: int) -> void {
        let last = root.std.last(self.entries);
        if (last == null) {
            return;
        }
        let added = false;
        let i = 0;
        for (let b in body.slice_from(from).chars()) {
            if (b == "\n") {
                self.entries.push(RawEntry { ...last, byte_off: from + i + 1 });
                added = true;
            }
            i += 1;
        }
        if (added) {
            // The redundancy rule now compares against the continuation
            // entry: the same source line on the new generated line.
            let gen_line = self.gen_line_at(body);
            self.last = root.std.Tuple2 { _0: last.src_line, _1: gen_line };
        }
    }

    /// The generated line the end of `body` falls on. Compressed output is a
    /// single line; expanded output advances by the newlines appended since the
    /// last call (the serializer only ever appends, so the walk is monotonic).
    function gen_line_at(self, body: root.std.StrBuf) -> int {
        if (self.compressed) {
            return 0;
        }
        // debug_assert!(body.len() >= self.scanned, "the body is only ever appended to");
        // PORT: skip the (flattening) slice when nothing was appended since.
        if (body.len() > self.scanned) {
            self.gen_line += body.slice_from(self.scanned).split("\n").length() - 1;
        }
        self.scanned = body.len();
        self.gen_line
    }

    /// Convert the recorded body offsets into delta-encoded `mappings`.
    ///
    /// `output` is the FINAL CSS string (already including any `@charset`/BOM
    /// prefix); `body_off` is the byte length of that prefix, which shifts every
    /// recorded body offset. Generated lines are counted by `\n`; the generated
    /// column is in UTF-16 code units (not bytes). File ids become `sources[]`
    /// indices in order of first appearance (see [`Mappings::source_ids`]), so
    /// a file that produced no mapping — an entry that only imports or only
    /// declares variables — is not a source, as in dart-sass.
    function finalize(self, output: string, body_off: int) -> Mappings {
        let m = Mappings.new();
        if (self.entries.length() == 0) {
            return m;
        }
        // Sort by generated byte offset so segments are added in generated
        // order (the encoder requires column-ascending segments per line).
        let _ = self.entries.sort_by_key((e) -> {
            e.byte_off
        });

        // A cursor that walks the output once, translating an absolute byte
        // offset into (line, utf16-col). Offsets arrive sorted, so the walk is
        // monotonic and O(output length) overall.
        // PORT: offsets are char offsets; the output is split into chars once
        // so each `skipped` slice costs only its own length.
        let output_chars = output.chars();
        let cur_byte = 0;
        let gen_line = 0;
        let gen_col16 = 0; // UTF-16 code units since the last '\n'

        for (let e in self.entries) {
            let target = body_off + e.byte_off;
            // Advance the cursor to `target` in one bulk step, rather than one
            // decoded `char` at a time. Only three facts about the skipped text
            // matter: how many newlines it holds, where the last one is, and how
            // many UTF-16 units follow it. Searching for a single ASCII `char`
            // goes through core's byte searcher instead of the UTF-8 decoder,
            // and `utf16_units` costs one vectorized `is_ascii` on the slices
            // that hold no non-ASCII text — which is nearly all of them.
            // debug_assert!(cur_byte <= target, "offsets are sorted ascending");
            // Offsets always land on a token start, i.e. a char boundary; the
            // decoding loop this replaced assumed the same thing (it walked
            // whole chars and asserted it had landed exactly on `target`).
            // debug_assert!(output.is_char_boundary(target), "offset on a char boundary");
            let skipped = root.std.join(output_chars.slice(cur_byte, target), "");
            let last_nl = skipped.last_index_of("\n");
            if (last_nl != null) {
                // Past a newline the column restarts, so only the text after
                // the LAST one contributes to it.
                gen_line += skipped.split("\n").length() - 1;
                gen_col16 = utf16_units(skipped.slice(last_nl + 1, skipped.length()));
            } else {
                gen_col16 += utf16_units(skipped);
            }
            cur_byte = target;
            let src = m.source_index(e.file_id);
            m.add(gen_line, gen_col16, src, e.src_line, e.src_col);
        }
        m
    }
}

/// Length of `s` in UTF-16 code units, which is what a source map's generated
/// column counts (`Mappings::add`). ASCII is one unit per byte and `is_ascii`
/// vectorizes, so the per-`char` decode only runs on the slices that really do
/// carry non-ASCII text — a stylesheet is otherwise ASCII from end to end.
function utf16_units(s: string) -> int {
    if (s.is_ascii()) {
        return s.byte_length();
    }
    // `c.len_utf16()`: two units for a code point beyond the BMP.
    s.chars()
        .map((c) -> {
            if (root.std.ord(c) > 0xFFFF) {
                2
            } else {
                1
            }
        })
        .reduce(
            (a, b) -> {
                a + b
            },
            0,
        )
}

/// A finished [Source Map v3](https://tc39.es/ecma426/), ready to serialize as
/// JSON via [`SourceMap::to_json`].
class SourceMap {
    /// Name of the generated file (the `file` field), if known.
    file: string?,
    /// Source URLs: exactly the files the mappings reference, in order of
    /// first reference in the generated CSS (as dart-sass). A file that
    /// produced no mapping — an entry that only imports, or only declares
    /// variables — is not listed, so an empty stylesheet has no sources and
    /// the entry is not necessarily `sources[0]`. Each entry is the file's
    /// canonical URL (the entry's [`Options::url`](crate::Options::url) as
    /// given; the resolved absolute path for a file
    /// [`FsImporter`](crate::FsImporter) loaded), or the importer's
    /// `source_map_url` override.
    sources: string[],
    /// Full source text per `sources` entry (parallel array), or `None` to omit
    /// the `sourcesContent` field entirely (controlled by
    /// `Options::with_source_map_include_sources`).
    sources_content: string[]?,
    /// The pre-encoded `mappings` string.
    mappings: string,

    /// Render the v3 JSON. Built by hand (zero-dep) with correct string escaping.
    function to_json_(self) -> string {
        let s = root.std.StrBuf.from("{\"version\":3");
        let file = self.file;
        if (file != null) {
            s.push_str(",\"file\":");
            json_str(file, s);
        }
        s.push_str(",\"sources\":[");
        let i = 0;
        for (let src in self.sources) {
            if (i > 0) {
                s.push(",");
            }
            json_str(src, s);
            i += 1;
        }
        s.push("]");
        let contents = self.sources_content;
        if (contents != null) {
            s.push_str(",\"sourcesContent\":[");
            let i = 0;
            for (let c in contents) {
                if (i > 0) {
                    s.push(",");
                }
                json_str(c, s);
                i += 1;
            }
            s.push("]");
        }
        s.push_str(",\"names\":[],\"mappings\":");
        json_str(self.mappings, s);
        s.push("}");
        s.as_str()
    }
}

/// Append `value` as a JSON string literal (quotes + escaping) to `out`.
function json_str(value: string, out: root.std.StrBuf) -> void {
    out.push("\"");
    for (let c in value.chars()) {
        match (c) {
            "\"" => out.push_str("\\\""),
            "\\" => out.push_str("\\\\"),
            "\n" => out.push_str("\\n"),
            "\r" => out.push_str("\\r"),
            "\t" => out.push_str("\\t"),
            "\b" => out.push_str("\\b"),
            "\f" => out.push_str("\\f"),
            let cc if root.std.ord(cc) < 0x20 => {
                let h = root.std.hex_lower(root.std.ord(cc));
                out.push_str("\\u" + "0".repeat(4 - h.length()) + h);
            },
            let cc => out.push(cc),
        }
    }
    out.push("\"");
}
