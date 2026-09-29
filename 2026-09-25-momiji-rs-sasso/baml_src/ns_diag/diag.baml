// Ported from sasso `src/diag.rs` (namespace `root.diag`).
//
// Source-span diagnostic rendering — a hand-rolled, dependency-free
// re-implementation of dart-sass's `SourceSpanHighlighter` snippet block.
//
// This module is **pure**: every public entry point is a function over an
// explicit `(source, line, col, length, …)` description and returns a
// `String`. Nothing here touches the evaluator, the parser, or any global
// state, and there is no I/O — the integration step (which wires real
// [`crate::Error`] spans through here) lives elsewhere. Keeping it isolated
// makes it trivial to test against the real `dart-sass` binary byte-for-byte.
//
// # What dart-sass renders
//
// For a single-line span (`a {\n  b: $undefined;\n}` → the `$undefined`
// token), dart-sass emits this exact block to stderr (Unicode glyph set):
//
// ```text
//   ╷
// 2 │   b: $undefined;
//   │      ^^^^^^^^^^
//   ╵
//   path/to/input.scss 2:6  root stylesheet
// ```
//
// The structure is:
//
// * a *top* gutter line: right-aligned blank line-number column, a space, the
//   top glyph `╷` (`U+2577`);
// * one *source* line per spanned source line: the right-aligned line number,
//   a space, the mid glyph `│` (`U+2502`), a space, then the source text with
//   **every TAB expanded to exactly four spaces** (this is byte-load-bearing;
//   dart-sass does *not* use tab stops, each `\t` becomes `"    "`);
// * for a single-line span, a *caret* line: blank gutter, the mid glyph, a
//   space, padding equal to the display-column offset of the span start, then
//   `^` (`U+005E`) repeated for the display width of the spanned text (at
//   least one caret, even for a zero-length span);
// * a *bottom* gutter line: blank gutter, a space, the bottom glyph `╵`
//   (`U+2575`);
// * a *location* line: two spaces, the file URL, a space, `line:col`, two
//   spaces, then the frame name (the outermost frame is literally
//   `root stylesheet`).
//
// The line/column numbers in the location line are **1-based**, matching
// dart-sass and [`crate::Error`].
//
// With `--no-unicode`, dart-sass swaps the glyph set: `╷│╵` → `,|'`, and for
// a multi-line span `│─` → `|-`. Its two CORNERS have no single spelling:
// `┌└` are `,'` on the arrow rows that reach in to a span starting or ending
// mid-line, and `/\` where the arm begins or ends in the GUTTER instead.

/// The glyph set used to draw the gutter and span decorations.
///
/// dart-sass picks [`GlyphSet::Unicode`] by default and [`GlyphSet::Ascii`]
/// under `--no-unicode` (or a non-Unicode terminal). The two sets are
/// byte-for-byte what dart-sass writes.
enum GlyphSet {
    /// Box-drawing glyphs: `╷ │ ╵ ┌ └ ─` and the ASCII caret `^`.
    Unicode,
    /// Pure-ASCII fallback: `, | ' , ' / \ -` and the caret `^`.
    Ascii,
}

interface GlyphSetMethods {
    /// Top of a single-column gutter (`╷` / `,`).
    function top(self) -> string throws unknown;

    /// Vertical bar of a gutter (`│` / `|`).
    function vertical(self) -> string throws unknown;

    /// Bottom of a single-column gutter (`╵` / `'`).
    function bottom(self) -> string throws unknown;

    /// Top-left corner that opens a multi-line span (`┌` / `,`).
    function top_left(self) -> string throws unknown;

    /// Bottom-left corner that closes a multi-line span (`└` / `'`).
    function bottom_left(self) -> string throws unknown;

    /// Underline of a SECONDARY span (`━` / `=`) — the heavy rule dart draws
    /// under the `declaration` a `Missing argument` is measured against, so it
    /// reads differently from the primary's carets.
    function secondary(self) -> string throws unknown;

    /// The arm a multi-line span draws IN THE GUTTER when it starts at its
    /// line's first non-whitespace character (`┌` / `/`). dart's ASCII set
    /// spells this differently from the `,` that opens an arrow row, so the
    /// two corners cannot share a glyph.
    function arm_start(self) -> string throws unknown;

    /// The same for a span that ENDS at its line's last non-whitespace
    /// character (`└` / `\`).
    function arm_end(self) -> string throws unknown;

    /// Horizontal rule used by the multi-line span arms (`─` / `-`).
    function horizontal(self) -> string throws unknown;
}

implements GlyphSetMethods for GlyphSet {
    /// Top of a single-column gutter (`╷` / `,`).
    function top(self) -> string {
        match (self) {
            GlyphSet.Unicode => "╷",
            GlyphSet.Ascii => ",",
        }
    }

    /// Vertical bar of a gutter (`│` / `|`).
    function vertical(self) -> string {
        match (self) {
            GlyphSet.Unicode => "│",
            GlyphSet.Ascii => "|",
        }
    }

    /// Bottom of a single-column gutter (`╵` / `'`).
    function bottom(self) -> string {
        match (self) {
            GlyphSet.Unicode => "╵",
            GlyphSet.Ascii => "'",
        }
    }

    /// Top-left corner that opens a multi-line span (`┌` / `,`).
    function top_left(self) -> string {
        match (self) {
            GlyphSet.Unicode => "┌",
            GlyphSet.Ascii => ",",
        }
    }

    /// Bottom-left corner that closes a multi-line span (`└` / `'`).
    function bottom_left(self) -> string {
        match (self) {
            GlyphSet.Unicode => "└",
            GlyphSet.Ascii => "'",
        }
    }

    /// Underline of a SECONDARY span (`━` / `=`) — the heavy rule dart draws
    /// under the `declaration` a `Missing argument` is measured against, so it
    /// reads differently from the primary's carets.
    function secondary(self) -> string {
        match (self) {
            GlyphSet.Unicode => "━",
            GlyphSet.Ascii => "=",
        }
    }

    /// The arm a multi-line span draws IN THE GUTTER when it starts at its
    /// line's first non-whitespace character (`┌` / `/`). dart's ASCII set
    /// spells this differently from the `,` that opens an arrow row, so the
    /// two corners cannot share a glyph.
    function arm_start(self) -> string {
        match (self) {
            GlyphSet.Unicode => "┌",
            GlyphSet.Ascii => "/",
        }
    }

    /// The same for a span that ENDS at its line's last non-whitespace
    /// character (`└` / `\`).
    function arm_end(self) -> string {
        match (self) {
            GlyphSet.Unicode => "└",
            GlyphSet.Ascii => "\\",
        }
    }

    /// Horizontal rule used by the multi-line span arms (`─` / `-`).
    function horizontal(self) -> string {
        match (self) {
            GlyphSet.Unicode => "─",
            GlyphSet.Ascii => "-",
        }
    }
}

/// dart-sass expands a literal TAB to exactly this many spaces when rendering a
/// source line (it is **not** tab-stop alignment — every `\t` is four spaces,
/// wherever it sits on the line).
function TAB_WIDTH() -> int {
    4
}

/// The caret glyph that underlines a span (`^`, `U+005E`) — identical in both
/// glyph sets.
function CARET() -> string {
    "^"
}

/// A located span to highlight, described in dart-sass / [`crate::Error`]
/// terms: 1-based `line`/`col` of the span start and a byte `length`.
///
/// `length` is measured in **bytes of the original source** (UTF-8); the
/// renderer slices the affected source text out and measures its *display*
/// width (with tabs expanded) to size the caret underline. A `length` of `0`
/// describes a point span and still draws a single caret, exactly as
/// dart-sass does.
class Span {
    /// 1-based line of the span start.
    line: int,
    /// 1-based column of the span start, counted in source characters (a TAB
    /// counts as one column, matching dart-sass's reported position).
    col: int,
    /// Length of the span in **bytes** of the original source text.
    length: int,
}

/// One frame of the rendered stack trace.
///
/// The location line under the snippet is a single [`Frame`]; deeper traces
/// (e.g. a function invocation) stack several, outermost last and literally
/// named `root stylesheet`.
class Frame {
    /// The file URL/path as dart-sass prints it (e.g. the absolute path, or
    /// `-` for stdin).
    url: string,
    /// 1-based line of this frame's span.
    line: int,
    /// 1-based column of this frame's span.
    col: int,
    /// The member name for this frame, or `root stylesheet` for the outermost.
    name: string,

    /// Render a single frame line: `<url> <line>:<col>  <name>` (two spaces
    /// before the name), with no leading indentation. Callers that emit a full
    /// trace prepend two spaces per line; see [`render_frames`].
    function render_inner(self) -> string {
        `${self.url} ${self.line}:${self.col}  ${self.name}`
    }
}

/// Render a stack trace exactly as dart-sass appends it under the snippet:
/// each frame on its own line, prefixed with two spaces.
///
/// ```text
///   path 2:6  some-mixin
///   path 9:3  root stylesheet
/// ```
function render_frames(frames: Frame[]) -> string {
    let out = root.std.StrBuf.new();
    let i = 0;
    for (let f in frames) {
        if (i > 0) {
            out.push("\n");
        }
        out.push_str("  ");
        out.push_str(f.render_inner());
        i += 1;
    }
    out.as_str()
}

/// Split `source` into lines the way dart-sass's `SourceFile` does: on `\n`,
/// `\r\n`, and bare `\r`, *dropping* the terminator. A trailing newline yields
/// a final empty line index that is simply never addressed by a 1-based line
/// number, so we do not special-case it.
function split_lines(source: string) -> string[] {
    let lines: string[] = [];
    // PORT: scans the CHARS once (char offsets, per the guide); the
    // terminators are ASCII, so the lines are the same substrings.
    let bytes = source.chars();
    let start = 0;
    let i = 0;
    while (i < bytes.length()) {
        match (bytes[i]) {
            "\n" => {
                lines.push(root.std.concat(bytes.slice(start, i)));
                i += 1;
                start = i;
            },
            "\r" => {
                lines.push(root.std.concat(bytes.slice(start, i)));
                i += 1;
                if (i < bytes.length() && bytes[i] == "\n") {
                    i += 1;
                }
                start = i;
            },
            _ => {
                i += 1;
            },
        }
    }
    lines.push(root.std.concat(bytes.slice(start, bytes.length())));
    lines
}

/// PORT: helper replacing Rust's pointer arithmetic on the slices
/// `split_lines` returns (`line.as_ptr() - source.as_ptr()`): the CHAR offset
/// in `source` at which each of those lines starts, computed by the same scan.
function line_starts(source: string) -> int[] {
    let starts: int[] = [0];
    let bytes = source.chars();
    let i = 0;
    while (i < bytes.length()) {
        match (bytes[i]) {
            "\n" => {
                i += 1;
                starts.push(i);
            },
            "\r" => {
                i += 1;
                if (i < bytes.length() && bytes[i] == "\n") {
                    i += 1;
                }
                starts.push(i);
            },
            _ => {
                i += 1;
            },
        }
    }
    starts
}

/// Expand every TAB in `text` to [`TAB_WIDTH`] spaces. Returns the displayable
/// string. This is the exact transform dart-sass applies before measuring
/// column widths, so it is shared by both the source line and the caret math.
function expand_tabs(text: string) -> string {
    let out = root.std.StrBuf.with_capacity(text.byte_length());
    for (let ch in text.chars()) {
        if (ch == "\t") {
            for (let _k in baml.iter.Range.new(0, TAB_WIDTH())) {
                out.push(" ");
            }
        } else {
            out.push(ch);
        }
    }
    out.as_str()
}

/// Display width of the first `cols` *source columns* of `line`, where each TAB
/// counts as [`TAB_WIDTH`] and every other character counts as one. `cols` is a
/// 0-based character count from the start of the line.
function display_width_of_prefix(line: string, cols: int) -> int {
    let width = 0;
    for (let ch in line.chars().slice(0, cols)) {
        width
            += if (ch == "\t") {
                TAB_WIDTH()
            } else {
                1
            };
    }
    width
}

/// Number of decimal digits in `n` (at least 1, so `0` → 1).
function digit_count(n: int) -> int {
    // PORT: `let mut n = n;` — the parameter is reassigned directly.
    let digits = 1;
    while (n >= 10) {
        n /= 10;
        digits += 1;
    }
    digits
}

/// Build the blank gutter prefix used by decoration lines: `width` spaces (for
/// the line-number column) plus one trailing space, e.g. `"  "` for a
/// single-digit file or `"   "` once line numbers reach 10.
function blank_gutter(width: int) -> string {
    let s = root.std.StrBuf.with_capacity(width + 1);
    for (let _k in baml.iter.Range.new(0, width + 1)) {
        s.push(" ");
    }
    s.as_str()
}

/// Build the numbered gutter prefix for a source line: the right-aligned line
/// number padded to `width`, then a space, e.g. `"2 "` or `" 2 "`.
function numbered_gutter(line_no: int, width: int) -> string {
    let digits = digit_count(line_no);
    let s = root.std.StrBuf.with_capacity(width + 1);
    for (let _k in baml.iter.Range.new(0, root.std.saturating_sub_u(width, digits))) {
        s.push(" ");
    }
    push_usize(s, line_no);
    s.push(" ");
    s.as_str()
}

/// Append the decimal rendering of `n` to `out` without allocating.
function push_usize(out: root.std.StrBuf, n: int) -> void {
    if (n >= 10) {
        push_usize(out, n / 10);
    }
    // 0..=9 always maps to a valid ASCII digit.
    let digit = (n % 10) + 48; // b'0'
    out.push(root.std.chr_unchecked(digit));
}

/// Render the snippet block (gutter + source + caret/arms + location frames)
/// for a span, byte-for-byte like dart-sass.
///
/// This does **not** emit the `Error: <message>` header — the caller owns the
/// message line — but it does emit everything from the top gutter glyph down to
/// (and including) the trailing frame lines, with no trailing newline.
///
/// `source` is the full text of the file the span points into; `span` is the
/// 1-based start position and byte length; `frames` is the stack trace to print
/// under the snippet (use a single [`Frame`] named `root stylesheet` for the
/// common case). `glyphs` selects the Unicode or ASCII decoration set.
///
/// The function is total: out-of-range line numbers, a `length` that runs past
/// the file, and empty sources all degrade gracefully (clamping rather than
/// panicking), so it satisfies the crate's panic-free discipline.
/// Render dart-sass's dual-span "error in interpolated output" block: the
/// original line with the interpolation's expression underlined, then the
/// interpolated output with a marker at the failing column.
///
/// ```text
///   ,--> input.scss
/// 1 | .test31#{'\@baz'} { content: '3.1'; }
///   |          ^^^^^^^
///   '
///   ,
/// 1 | .test31@baz
///   |        = error in interpolated output
///   '
/// ```
function render_interp_error_snippet(
    source: string,
    line: int,
    col_start: int,
    col_end: int,
    resolved: string,
    resolved_col: int,
    url: string,
    glyphs: GlyphSet,
) -> string {
    let lines = split_lines(source);
    let src_line = lines.at(root.std.saturating_sub_u(line, 1)) ?? "";
    let width = digit_count(line);
    let pad = blank_gutter(width);
    let marker = match (glyphs) {
        GlyphSet.Unicode => "━",
        GlyphSet.Ascii => "=",
    };
    let arrow = match (glyphs) {
        GlyphSet.Unicode => "┌──>",
        GlyphSet.Ascii => ",-->",
    };
    let out = root.std.StrBuf.new();
    // First box: the original source with the interpolation underlined.
    out.push_str(pad);
    out.push_str(arrow);
    out.push(" ");
    out.push_str(url);
    out.push("\n");
    out.push_str(`${root.std.pad_left(line.to_string(), width)} ${glyphs.vertical()} ${src_line}\n`);
    out.push_str(pad);
    out.push_str(glyphs.vertical());
    out.push(" ");
    for (let _k in baml.iter.Range.new(1, col_start)) {
        out.push(" ");
    }
    for (let _k in baml.iter.Range.new(col_start, col_end)) {
        out.push("^");
    }
    out.push_str(" \n");
    out.push_str(pad);
    out.push_str(glyphs.bottom());
    out.push("\n");
    // Second box: the interpolated output (always line 1 of a virtual file).
    out.push_str(pad);
    out.push_str(glyphs.top());
    out.push("\n");
    out.push_str(`${root.std.pad_left("1", width)} ${glyphs.vertical()} ${resolved}\n`);
    out.push_str(pad);
    out.push_str(glyphs.vertical());
    out.push(" ");
    for (let _k in baml.iter.Range.new(1, resolved_col)) {
        out.push(" ");
    }
    out.push_str(marker);
    out.push_str(" error in interpolated output\n");
    out.push_str(pad);
    out.push_str(glyphs.bottom());
    out.as_str()
}

/// Where dart-sass reports an EMPTY span that sits in a file's trailing
/// whitespace: at the end of the last line with content, not on the blank line
/// after it. dart's scanner never advances into that whitespace, so its
/// "expected …" at the end of a file points at the last thing the file says;
/// sasso's parsers do advance, so the position is walked back here — for the
/// snippet and for the frame line alike.
function trim_empty_span_to_content(source: string, span: Span) -> Span {
    if (span.length > 0) {
        return span;
    }
    let lines = split_lines(source);
    // PORT: `source.as_ptr()` / `line.as_ptr()` arithmetic → the explicit char
    // offsets from `line_starts`; offsets below are CHAR offsets.
    let starts = line_starts(source);
    let idx = root.std.imin(
        root.std.saturating_sub_u(span.line, 1),
        root.std.saturating_sub_u(lines.length(), 1),
    );
    let line = lines[idx];
    let col0 = root.std.saturating_sub_u(span.col, 1);
    // The byte offset of the span, and the text from there to the end.
    let line_start = starts[idx];
    let offset = line_start
        + (
            if (col0 < line.length()) {
                col0
            } else {
                line.length()
            }
        );
    if (offset > source.length() || root.std.trim(source.slice(offset, source.length())) != "") {
        return span;
    }
    // Land at the END of the last line that has content — trailing spaces on
    // that line included, which is where dart's scanner stopped (`.a { b: c; `
    // reports past the space, not after the `;`).
    let found: int? = null;
    let i = lines.length();
    while (i > 0) {
        i -= 1;
        if (root.std.trim(lines[i]) != "") {
            found = i;
            break;
        }
    }
    if (found == null) {
        return span;
    }
    let l = lines[found];
    Span { line: found + 1, col: l.length() + 1, length: 0 }
}

function render_snippet(source: string, span: Span, frames: Frame[], glyphs: GlyphSet) -> string {
    let lines = split_lines(source);

    // Resolve the 0-based start line, clamped into range.
    let start_idx = root.std.imin(
        root.std.saturating_sub_u(span.line, 1),
        root.std.saturating_sub_u(lines.length(), 1),
    );
    let start_col0 = root.std.saturating_sub_u(span.col, 1);

    // Walk the byte length across lines to find the end line/col. dart-sass
    // counts the terminator between lines as one byte; we mirror that so a
    // span that crosses a newline lands on the right line.
    let end = resolve_end(source, lines, start_idx, start_col0, span.length);
    let end_idx = end._0;
    let end_col0 = end._1;

    // Gutter width is sized to the widest line number we will print.
    let max_line_no = end_idx + 1;
    let width = digit_count(max_line_no);

    let out = root.std.StrBuf.new();

    if (start_idx == end_idx) {
        render_single_line(out, lines, start_idx, start_col0, end_col0, width, glyphs);
    } else {
        render_multi_line(out, lines, start_idx, start_col0, end_idx, end_col0, width, glyphs);
    }

    // Bottom gutter glyph.
    out.push("\n");
    out.push_str(blank_gutter(width));
    out.push_str(glyphs.bottom());

    // Location / stack-trace lines.
    if (frames.length() != 0) {
        out.push("\n");
        out.push_str(render_frames(frames));
    }

    out.as_str()
}

/// One span drawn alongside the primary one, with the label dart-sass writes
/// after its underline.
///
/// A secondary span can live in ANOTHER FILE — the `@mixin` a `Missing
/// argument` points back to, or `sass:color` for a built-in — so it carries
/// its own url and source text.
class Secondary {
    /// The file the span is in, as the location line spells it.
    url: string,
    /// That file's text. It is also half the identity of the block this span
    /// is drawn in: a display url is a NAME two files can share (see
    /// `MixinOrigin::source`), the canonical url is the identity — so spans
    /// join one block only when their TEXT matches too, or one of them would
    /// be rendered against the other's lines.
    source: string,
    span: Span,
    /// The words after the underline (`declaration`, `includes mixin`, …).
    label: string,
}

/// Render a snippet with LABELLED spans: the primary one underlined with
/// carets, each secondary with `━`, every underline followed by its label.
///
/// dart draws this whenever a diagnostic has something to point at besides the
/// place it failed — the parameter list behind `Missing argument $x.`, the
/// `@use` rules that both expose a mixin. The shapes it uses, all measured:
///
/// * spans in one file share a block; each printed line is followed by one
///   underline row per span on it, the primary first;
/// * a span that CROSSES LINES draws an arm down the left of every line it
///   covers, and the row that closes the arm carries the label;
/// * one such span anywhere indents EVERY block by the arm column, blank arm
///   included — dart sizes that column once for the whole diagnostic;
/// * lines that are not adjacent are ELIDED with a `... |` row — dart never
///   prints the lines in between — and the gutter then widens to at least
///   three columns with the numbers LEFT-aligned in it;
/// * spans in different files get one block each, introduced by `,--> <url>`
///   and closed by the usual bottom glyph, the primary's file first.
///
/// A span that stays within its line can sit INSIDE an arm's range — its row
/// is written under its own line, before the arm's, and carries the arm in the
/// column. Two spans that BOTH cross lines and overlap are the one shape this
/// cannot draw: dart nests a second arm column and crosses them with `+`.
/// Callers keep that pair apart — see `Evaluator::spans_share_a_block`.
function render_labelled_snippet(
    url: string,
    source: string,
    span: Span,
    label: string,
    secondaries: Secondary[],
    frames: Frame[],
    glyphs: GlyphSet,
) -> string {
    // Group by file, primary first, each file keeping first-appearance order.
    let groups: root.std.Tuple3<string, string, Entry[]>[] = [
        root.std.Tuple3<string, string, Entry[]> {
            _0: url,
            _1: source,
            _2: [Entry { span: span, label: label, primary: true }],
        },
    ];
    for (let sec in secondaries) {
        let entry = Entry { span: sec.span, label: sec.label, primary: false };
        // The TEXT is part of the key: a display url is a name two files can
        // share, so matching on it alone would draw one file's span against
        // the other's lines.
        let found = groups.find((g) -> {
            g._0 == sec.url && g._1 == sec.source
        });
        if (found != null) {
            found._2.push(entry);
        } else {
            groups.push(
                root.std.Tuple3<string, string, Entry[]> {
                    _0: sec.url,
                    _1: sec.source,
                    _2: [entry],
                },
            );
        }
    }

    let multi_file = groups.length() > 1;
    // The arm column is sized ONCE for the whole diagnostic: a span crossing
    // lines in any block indents them all.
    let arm = groups.some((g) -> {
        g._2.some((e) -> {
            span_crosses_lines(g._1, e.span)
        })
    });
    let out = root.std.StrBuf.new();
    let i = 0;
    for (let g in groups) {
        let group_url = g._0;
        let group_source = g._1;
        let entries = g._2;
        if (i > 0) {
            out.push("\n");
        }
        // PORT: `sort_by_key(|e| (e.span.line, !e.primary))` → a comparator on
        // the same key (stable, like Rust's).
        let _ = entries.sort_by((a: Entry, b: Entry) -> baml.ops.Ordering {
            if (a.span.line != b.span.line) {
                a.span.line.cmp(b.span.line)
            } else {
                let ka = if (a.primary) {
                    0
                } else {
                    1
                };
                let kb = if (b.primary) {
                    0
                } else {
                    1
                };
                ka.cmp(kb)
            }
        });
        render_group(
            out,
            if (multi_file) {
                group_url
            } else {
                null
            },
            group_source,
            entries,
            arm,
            glyphs,
        );
        i += 1;
    }
    if (frames.length() != 0) {
        out.push("\n");
        out.push_str(render_frames(frames));
    }
    out.as_str()
}

/// One labelled span inside a file's block.
class Entry {
    span: Span,
    label: string,
    primary: bool,
}

/// An [`Entry`] resolved to the lines and columns it actually covers.
class Placed {
    label: string,
    primary: bool,
    start_idx: int,
    start_col0: int,
    end_idx: int,
    end_col0: int,
    /// Whether the span starts at its line's first non-whitespace character,
    /// which decides whether an arm opens in the gutter or behind an arrow row.
    starts_at_edge: bool,

    function crosses_lines(self) -> bool {
        self.start_idx != self.end_idx
    }
}

function render_group(
    out: root.std.StrBuf,
    url: string?,
    source: string,
    entries: Entry[],
    arm: bool,
    glyphs: GlyphSet,
) -> void {
    let lines = split_lines(source);
    let v = glyphs.vertical();
    let h = glyphs.horizontal();
    let last_line = root.std.saturating_sub_u(lines.length(), 1);
    let placed: Placed[] = entries.map((e: Entry) -> Placed {
        let start_idx = root.std.imin(root.std.saturating_sub_u(e.span.line, 1), last_line);
        let start_col0 = root.std.saturating_sub_u(e.span.col, 1);
        let end = resolve_end(source, lines, start_idx, start_col0, e.span.length);
        let end_idx = end._0;
        let end_col0 = end._1;
        let first = lines.at(start_idx) ?? "";
        Placed {
            label: e.label,
            primary: e.primary,
            start_idx: start_idx,
            start_col0: start_col0,
            end_idx: end_idx,
            end_col0: end_col0,
            starts_at_edge: first.chars().slice(0, start_col0).every((c: string) -> bool {
                c.is_whitespace()
            }),
        }
    });

    // Every line any span touches, each printed once, in order.
    let line_nos: int[] = [];
    for (let p in placed) {
        for (let li in baml.iter.Range.new(p.start_idx, p.end_idx + 1)) {
            if (!line_nos.includes(li)) {
                line_nos.push(li);
            }
        }
    }
    root.std.sort_ints(line_nos);

    let max_line_no = (root.std.last(line_nos) ?? 0) + 1;
    // A gap between printed lines is elided, never filled in — and the `...`
    // row is three columns wide, which widens the gutter and left-aligns the
    // numbers in it.
    let elides = false;
    let w = 1;
    while (w < line_nos.length()) {
        if (line_nos[w] > line_nos[w - 1] + 1) {
            elides = true;
            break;
        }
        w += 1;
    }
    let width = if (elides) {
        root.std.imax(digit_count(max_line_no), 3)
    } else {
        digit_count(max_line_no)
    };

    out.push_str(blank_gutter(width));
    // A block introduced by its file name opens with the CORNER glyph the
    // arrow grows out of, not the plain gutter tick.
    out.push_str(
        if (url != null) {
            glyphs.top_left()
        } else {
            glyphs.top()
        },
    );
    if (url != null) {
        out.push_str(h);
        out.push_str(h);
        out.push(">");
        out.push(" ");
        out.push_str(url);
    }

    let prev: int? = null;
    for (let li in line_nos) {
        if (prev != null) {
            if (li > prev + 1) {
                out.push("\n");
                out.push_str(elision_gutter(width));
                out.push_str(v);
            }
        }
        prev = li;
        // Spans that cross lines never overlap each other here (the caller
        // keeps that pair apart), so at most one arm reaches this line, and
        // every row on it — the source line and the underlines under it —
        // carries that arm in the column.
        let armed = placed.find((p: Placed) -> bool {
            p.crosses_lines() && p.start_idx <= li && li <= p.end_idx
        });
        let slot = match (armed) {
            // The arm opens IN THE GUTTER on the line it starts, when the span
            // starts that line; otherwise the `,-…-^` row below reaches in for
            // it and the column stays blank until then.
            let a: Placed if a.start_idx == li => {
                if (a.starts_at_edge) {
                    glyphs.arm_start()
                } else {
                    " "
                }
            },
            let _a: Placed => v,
            _ => " ",
        };
        push_source_line(
            out,
            lines,
            li,
            width,
            elides,
            if (arm) {
                slot
            } else {
                null
            },
            glyphs,
        );
        // The underline rows of the spans that stay WITHIN this line, in the
        // order the entries were sorted into: the primary first.
        for (
            let p in placed.filter((p: Placed) -> bool {
                !p.crosses_lines() && p.start_idx == li
            })
        ) {
            let line = lines.at(li) ?? "";
            out.push("\n");
            out.push_str(blank_gutter(width));
            out.push_str(v);
            out.push(" ");
            // The arm is only OPEN below this row once it has reached in:
            // on the line where it starts mid-line, the `,-…-^` row comes
            // after this one, so the column is still blank here.
            let row_slot = match (armed) {
                let a: Placed if a.start_idx == li && !a.starts_at_edge => " ",
                let _a: Placed => v,
                _ => " ",
            };
            push_arm(
                out,
                if (arm) {
                    row_slot
                } else {
                    null
                },
            );
            for (let _k in baml.iter.Range.new(0, display_width_of_prefix(line, p.start_col0))) {
                out.push(" ");
            }
            let mark = if (p.primary) {
                CARET()
            } else {
                glyphs.secondary()
            };
            for (
                let _k in baml.iter.Range.new(
                    0,
                    display_width_of_prefix_range(line, p.start_col0, p.end_col0),
                )
            ) {
                out.push(mark);
            }
            push_label(out, p.label);
        }
        if (armed == null) {
            continue;
        }
        let a = armed;
        // Then the arm's own rows: the `,-…-^` that reaches in to a span
        // starting mid-line, and the row that closes the arm and carries the
        // label.
        if (a.start_idx == li && !a.starts_at_edge) {
            let first = lines.at(li) ?? "";
            out.push("\n");
            out.push_str(blank_gutter(width));
            out.push_str(v);
            out.push(" ");
            out.push_str(glyphs.top_left());
            for (let _k in baml.iter.Range.new(0, display_width_of_prefix(first, a.start_col0) + 1)) {
                out.push_str(h);
            }
            out.push(CARET());
        }
        if (a.end_idx == li) {
            // The closing row points at the last spanned character — unless the
            // span runs to the end of its line, where dart has nothing to point
            // at and draws a flat three-rule arm instead.
            let last = lines.at(li) ?? "";
            out.push("\n");
            out.push_str(blank_gutter(width));
            out.push_str(v);
            out.push(" ");
            out.push_str(glyphs.bottom_left());
            let last_cs = last.chars();
            if (
                last_cs.slice(a.end_col0, last_cs.length()).every((c: string) -> bool {
                    c.is_whitespace()
                })
            ) {
                for (let _k in baml.iter.Range.new(0, 3)) {
                    out.push_str(h);
                }
            } else {
                for (let _k in baml.iter.Range.new(0, display_width_of_prefix(last, a.end_col0))) {
                    out.push_str(h);
                }
                out.push(CARET());
            }
            push_label(out, a.label);
        }
    }

    out.push("\n");
    out.push_str(blank_gutter(width));
    out.push_str(glyphs.bottom());
}

/// Write one numbered source line of a labelled block: gutter, `│`, the arm
/// column when the diagnostic has one (`Some(slot)`), then the text.
function push_source_line(
    out: root.std.StrBuf,
    lines: string[],
    idx: int,
    width: int,
    elides: bool,
    slot: string?,
    glyphs: GlyphSet,
) -> void {
    out.push("\n");
    out.push_str(aligned_gutter(idx + 1, width, elides));
    out.push_str(glyphs.vertical());
    out.push(" ");
    push_arm(out, slot);
    out.push_str(expand_tabs(lines.at(idx) ?? ""));
}

/// The arm column: one glyph and a space, or nothing when the diagnostic has
/// no multi-line span to draw an arm for.
function push_arm(out: root.std.StrBuf, slot: string?) -> void {
    if (slot != null) {
        out.push_str(slot);
        out.push(" ");
    }
}

/// The words dart writes after an underline, when there are any.
function push_label(out: root.std.StrBuf, label: string) -> void {
    if (label != "") {
        out.push(" ");
        out.push_str(label);
    }
}

/// The gutter for a numbered source line: right-aligned normally, LEFT-aligned
/// once an elision row is in play (dart pads them all to the `...` column).
function aligned_gutter(line_no: int, width: int, elides: bool) -> string {
    if (!elides) {
        return numbered_gutter(line_no, width);
    }
    let s = line_no.to_string();
    while (s.length() < width) {
        s = s + " ";
    }
    s = s + " ";
    s
}

/// The `... ` gutter of an elision row.
function elision_gutter(width: int) -> string {
    let s = "...";
    while (s.length() < width) {
        s = s + " ";
    }
    s = s + " ";
    s
}

/// The 1-based line range a span covers, both ends inclusive.
function span_line_range(source: string, span: Span) -> root.std.Tuple2<int, int> {
    let lines = split_lines(source);
    let start_idx = root.std.imin(
        root.std.saturating_sub_u(span.line, 1),
        root.std.saturating_sub_u(lines.length(), 1),
    );
    let end = resolve_end(source, lines, start_idx, root.std.saturating_sub_u(span.col, 1), span.length);
    let end_idx = end._0;
    root.std.Tuple2<int, int> { _0: start_idx + 1, _1: end_idx + 1 }
}

/// Whether a span reaches past the end of the line it starts on.
function span_crosses_lines(source: string, span: Span) -> bool {
    let lines = split_lines(source);
    let start_idx = root.std.imin(
        root.std.saturating_sub_u(span.line, 1),
        root.std.saturating_sub_u(lines.length(), 1),
    );
    let start_col0 = root.std.saturating_sub_u(span.col, 1);
    let end = resolve_end(source, lines, start_idx, start_col0, span.length);
    let end_idx = end._0;
    end_idx != start_idx
}

/// The byte width of the terminator after `lines[idx]` — 1 for `\n` or a lone
/// `\r`, 2 for a `\r\n`. The lines are slices of `source`, so the gap between
/// one line's end and the next line's start IS the terminator.
function terminator_len(source: string, lines: string[], idx: int) -> int {
    // PORT: fast path — without a `\r` every terminator is a lone `\n` (the
    // result below is then always 1); avoids rescanning `source` per line.
    if (!source.includes("\r")) {
        return 1;
    }
    // PORT: `as_ptr` arithmetic → char offsets from `line_starts` (the
    // terminators are ASCII, so the char gap equals the byte gap).
    let base = line_starts(source);
    let cur = lines.at(idx);
    let next = lines.at(idx + 1);
    if (cur != null && next != null) {
        let cur_end = base[idx] + cur.length();
        root.std.imax(root.std.saturating_sub_u(base[idx + 1], cur_end), 1)
    } else {
        1
    }
}

/// Resolve the (0-based line, 0-based col) just past the end of a byte span,
/// starting from `(start_idx, start_col0)`. Tabs and multibyte characters are
/// handled by walking characters and decrementing the remaining byte budget by
/// each character's UTF-8 length; the inter-line terminator costs one byte.
function resolve_end(
    source: string,
    lines: string[],
    start_idx: int,
    start_col0: int,
    length: int,
) -> root.std.Tuple2<int, int> {
    let idx = start_idx;
    let col = start_col0;
    let remaining = length;

    while (true) {
        let line = lines.at(idx) ?? "";
        // Characters available from `col` to end of this line.
        let consumed_cols = 0;
        let cs = line.chars();
        for (let ch in cs.slice(col, cs.length())) {
            let blen = root.std.len_utf8(ch);
            if (remaining < blen) {
                return root.std.Tuple2<int, int> { _0: idx, _1: col + consumed_cols };
            }
            remaining -= blen;
            consumed_cols += 1;
        }
        // Reached end of this line. The terminator costs one byte if there is
        // a following line.
        if (remaining == 0 || idx + 1 >= lines.length()) {
            return root.std.Tuple2<int, int> { _0: idx, _1: col + consumed_cols };
        }
        // Spend the terminator and move on — TWO bytes for a CRLF, which the
        // line list has already stripped.
        remaining = root.std.saturating_sub_u(remaining, terminator_len(source, lines, idx));
        idx += 1;
        col = 0;
        if (remaining == 0) {
            return root.std.Tuple2<int, int> { _0: idx, _1: 0 };
        }
    }
    root.std.unreachable()
}

/// Render the top gutter line and the (single) source + caret lines.
function render_single_line(
    out: root.std.StrBuf,
    lines: string[],
    idx: int,
    start_col0: int,
    end_col0: int,
    width: int,
    glyphs: GlyphSet,
) -> void {
    let line = lines.at(idx) ?? "";
    let v = glyphs.vertical();

    // Top gutter glyph.
    out.push_str(blank_gutter(width));
    out.push_str(glyphs.top());

    // Source line.
    out.push("\n");
    out.push_str(numbered_gutter(idx + 1, width));
    out.push_str(v);
    out.push(" ");
    out.push_str(expand_tabs(line));

    // Caret line.
    out.push("\n");
    out.push_str(blank_gutter(width));
    out.push_str(v);
    out.push(" ");
    let pad = display_width_of_prefix(line, start_col0);
    for (let _k in baml.iter.Range.new(0, pad)) {
        out.push(" ");
    }
    // At least one caret, even for a zero-length (point) span — matching
    // dart-sass; `display_width_of_prefix_range` already clamps to >= 1.
    let caret_w = display_width_of_prefix_range(line, start_col0, end_col0);
    for (let _k in baml.iter.Range.new(0, caret_w)) {
        out.push(CARET());
    }
}

/// Display width of the characters in `line` from 0-based column `from` up to
/// (not including) 0-based column `to`. Used to size a single-line caret run.
function display_width_of_prefix_range(line: string, from: int, to: int) -> int {
    if (to <= from) {
        return 1;
    }
    let width = 0;
    for (let ch in line.chars().slice(from, to)) {
        width
            += if (ch == "\t") {
                TAB_WIDTH()
            } else {
                1
            };
    }
    root.std.imax(width, 1)
}

/// Render a multi-line span: the opening arm under the first line, each
/// intermediate source line prefixed with the vertical arm, and the closing arm
/// under the last line. Mirrors dart-sass's `┌─…^` / `│` / `└─^` decorations.
function render_multi_line(
    out: root.std.StrBuf,
    lines: string[],
    start_idx: int,
    start_col0: int,
    end_idx: int,
    end_col0: int,
    width: int,
    glyphs: GlyphSet,
) -> void {
    let v = glyphs.vertical();
    let h = glyphs.horizontal();
    let first = lines.at(start_idx) ?? "";
    let last = lines.at(end_idx) ?? "";
    // dart-sass (source_span) writes the arm glyph in the GUTTER when the span
    // begins at its line's first non-whitespace character, and likewise when it
    // ends at its line's last; it draws an `┌─…─^` / `└─…─^` arrow row only for
    // an end that starts or stops mid-line. The two ends are decided
    // separately: `.a { @include m {` … `  }` opens with an arrow and closes in
    // the gutter.
    let start_at_edge = first.chars().slice(0, start_col0).every((c: string) -> bool {
        c.is_whitespace()
    });
    let last_cs = last.chars();
    let end_at_edge = last_cs.slice(end_col0, last_cs.length()).every((c: string) -> bool {
        c.is_whitespace()
    });

    // Top gutter glyph.
    out.push_str(blank_gutter(width));
    out.push_str(glyphs.top());

    // First source line: the arm slot holds `┌` when the span starts the line,
    // and is blank when an arrow row follows. The layout after the gutter `│`
    // is `<space><arm-slot><space><content>`.
    out.push("\n");
    out.push_str(numbered_gutter(start_idx + 1, width));
    out.push_str(v);
    out.push(" ");
    if (start_at_edge) {
        out.push_str(glyphs.arm_start());
    } else {
        out.push(" ");
    }
    out.push(" ");
    out.push_str(expand_tabs(first));

    // Opening arm: `┌─…─^` whose caret sits under the span start. The `┌`
    // occupies the arm slot; the content baseline is two columns to its right,
    // so the caret offset is the span-start display column + 1.
    if (!start_at_edge) {
        out.push("\n");
        out.push_str(blank_gutter(width));
        out.push_str(v);
        out.push(" ");
        out.push_str(glyphs.top_left());
        let lead = display_width_of_prefix(first, start_col0) + 1;
        for (let _k in baml.iter.Range.new(0, lead)) {
            out.push_str(h);
        }
        out.push(CARET());
    }

    // Intermediate + final source lines, each carrying a `│` arm — except the
    // last, which carries `└` when the span ends the line.
    for (let li in baml.iter.Range.new(start_idx + 1, end_idx + 1)) {
        let text = lines.at(li) ?? "";
        out.push("\n");
        out.push_str(numbered_gutter(li + 1, width));
        out.push_str(v);
        out.push(" ");
        if (li == end_idx && end_at_edge) {
            out.push_str(glyphs.arm_end());
        } else {
            out.push_str(v);
        }
        out.push(" ");
        out.push_str(expand_tabs(text));
    }

    // Closing arm: `└─…─^` whose caret sits under the last spanned character
    // (one column left of the span end), with the same +1 arm offset.
    if (!end_at_edge) {
        out.push("\n");
        out.push_str(blank_gutter(width));
        out.push_str(v);
        out.push(" ");
        out.push_str(glyphs.bottom_left());
        let tail = display_width_of_prefix(last, end_col0);
        for (let _k in baml.iter.Range.new(0, tail)) {
            out.push_str(h);
        }
        out.push(CARET());
    }
}

/// Convenience: render a full diagnostic (`Error:` header + snippet) for the
/// common single-frame `root stylesheet` case. Returns the complete block with
/// no trailing newline, exactly as dart-sass would write it to stderr.
///
/// The evaluator renders its own header + column-aligned frame trace for
/// runtime/`@error` diagnostics (multi-frame stacks); this single-frame
/// convenience renders parse errors (always a lone `root stylesheet` frame).
function render_error(
    message: string,
    source: string,
    url: string,
    span: Span,
    glyphs: GlyphSet,
) -> string {
    let frame = Frame { url: url, line: span.line, col: span.col, name: "root stylesheet" };
    let out = `Error: ${message}\n`;
    out = out + render_snippet(source, span, [frame], glyphs);
    out
}
