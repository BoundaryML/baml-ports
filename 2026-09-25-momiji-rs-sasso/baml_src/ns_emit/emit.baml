// Ported from sasso `src/emit.rs` (namespace `root.emit`).
//
// Serialize the flattened output tree to CSS.
//
// PORT: the output buffer is a `root.std.StrBuf`; every body offset (`from`,
// `before`, the source-map entries, `body_off`) is a CHARACTER offset
// (PORTING_GUIDE §8). The `&mut Option<SmCollector>` threaded everywhere is a
// `root.std.Cell<root.sourcemap.SmCollector?>`, and the `&mut SrcLines`
// previous-sibling state is a `root.std.Cell<root.ast.SrcLines>`.

function emit(nodes: root.eval.OutNode[], style: root.OutputStyle, charset: bool) -> string {
    // The default path collects nothing: `&mut None` makes every `record_*`
    // call inert, so the output is byte-for-byte the historical CSS.
    let none: root.std.Cell<root.sourcemap.SmCollector?> = root.std.Cell { value: null };
    emit_inner(nodes, style, none, charset)._0
}

/// Like [`emit`], but also records a source map. Returns the final CSS, the
/// byte length of the `@charset`/BOM prefix that shifts every body offset, and
/// the populated collector (raw body offsets, not yet resolved to lines).
function emit_with_map(
    nodes: root.eval.OutNode[],
    style: root.OutputStyle,
    charset: bool,
) -> root.std.Tuple3<string, int, root.sourcemap.SmCollector> {
    let collector: root.std.Cell<root.sourcemap.SmCollector?> = root.std.Cell { value: root.sourcemap.SmCollector.new(style == root.OutputStyle.Compressed) };
    let r = emit_inner(nodes, style, collector, charset);
    let css = r._0;
    let body_off = r._1;
    root.std.Tuple3 {
        _0: css,
        _1: body_off,
        _2: root.std.expect(collector.value, "collector present"),
    }
}

/// Shared serializer. `collector = Some` records mapped-token body offsets;
/// `None` records nothing (the default path). Returns `(css, body_off)` where
/// `body_off` is the length of the prepended `@charset`/BOM prefix (0 when the
/// body is pure ASCII).
function emit_inner(
    nodes: root.eval.OutNode[],
    style: root.OutputStyle,
    collector: root.std.Cell<root.sourcemap.SmCollector?>,
    charset: bool,
) -> root.std.Tuple2<string, int> {
    let body = match (style) {
        root.OutputStyle.Expanded => emit_expanded(nodes, collector),
        root.OutputStyle.Compressed => emit_compressed(nodes, collector),
    };
    // The library API (`compile`/`compile_with_source_map`, and thus the wasm
    // `compileString().css` and the Ruby gem) returns the serialized stylesheet
    // with NO trailing newline — byte-for-byte what dart-sass's library API
    // returns. The expanded emitter terminates each statement with "\n", which
    // leaves exactly one trailing newline; drop it. (Compressed never emits a
    // trailing newline, so this is a no-op there.) The CLI front-ends
    // (src/main.rs, wasm cli.mjs) re-append the single newline dart-sass's CLI
    // adds. Stripping after emit keeps every recorded source-map offset valid:
    // nothing maps to the final newline.
    if (body.ends_with("\n")) {
        body = body.slice(0, body.length() - 1);
    }
    // dart-sass declares UTF-8 when the output contains any non-ASCII code
    // point: expanded output gets a leading `@charset "UTF-8";`, compressed
    // output gets a UTF-8 byte-order mark instead. The prefix shifts every
    // recorded body offset by its byte length (reported as `body_off`).
    // `charset: false` (dart-sass `--no-charset`) suppresses it entirely.
    if (!charset || body.is_ascii()) {
        return root.std.Tuple2 { _0: body, _1: 0 };
    }
    // PORT: `body_off` is the prefix's CHARACTER length (the BOM is one char),
    // matching the character offsets the collector records.
    match (style) {
        root.OutputStyle.Expanded => {
            let PREFIX = "@charset \"UTF-8\";\n";
            root.std.Tuple2 { _0: PREFIX + body, _1: PREFIX.length() }
        },
        root.OutputStyle.Compressed => {
            let prefix = root.std.chr_unchecked(0xFEFF);
            root.std.Tuple2 { _0: prefix + body, _1: prefix.length() }
        },
    }
}

/// Record a mapped token at the current end of `out` if collecting. Reads only
/// `out.len()` and the SrcLines — never mutates the output. Returns whether a
/// source position was known (so the caller may [`continue_span`] over it).
// PORT: `out: &str` → the `StrBuf` itself, so the default (no-map) path never
// materializes the buffer.
function record(
    out: root.std.StrBuf,
    lines: root.ast.SrcLines,
    collector: root.std.Cell<root.sourcemap.SmCollector?>,
) -> bool {
    let c = collector.value;
    if (c != null) {
        // A bubbled-selector wrapper carries its mapping in the source-map-only
        // override fields (so `file`/`start` stay 0 and the trailing-comment
        // heuristic stays disabled); everything else maps from `file`/`start`.
        let file = if (lines.map_file != 0) {
            lines.map_file
        } else {
            lines.file
        };
        let line = lines.mapped_line();
        // `line` is the 1-based source line; 0 means "unknown" — skip it.
        if (line == 0 || file == 0) {
            return false;
        }
        c.record(out, file, line - 1, lines.start_col);
        return true;
    }
    false
}

/// dart keeps a span OPEN while it writes a construct's text: a newline inside
/// it maps the new generated line back to the same source position (see
/// [`SmCollector::span_newlines`]). Call after appending the span's text that
/// began at body offset `from`; `mapped` is what [`record`]/[`record_span`]
/// returned for it, so an unmapped construct adds nothing.
function continue_span(
    out: root.std.StrBuf,
    from: int,
    mapped: bool,
    collector: root.std.Cell<root.sourcemap.SmCollector?>,
) -> void {
    let c = collector.value;
    if (mapped) {
        if (c != null) {
            c.span_newlines(out, from);
        }
    }
}

/// Record a mapped token from an already-0-based [`VarSpan`] (a declaration
/// VALUE's span, resolved at eval time). `file == 0` means "unknown" and is
/// skipped. Like [`record`], reads the output but never mutates it.
function record_span(
    out: root.std.StrBuf,
    span: root.eval.VarSpan,
    collector: root.std.Cell<root.sourcemap.SmCollector?>,
) -> bool {
    let c = collector.value;
    if (c != null) {
        if (span.file == 0) {
            return false;
        }
        c.record(out, span.file, span.line, span.col);
        return true;
    }
    false
}

function emit_expanded(
    nodes: root.eval.OutNode[],
    collector: root.std.Cell<root.sourcemap.SmCollector?>,
) -> string {
    let out = root.std.StrBuf.new();
    let prev: root.std.Cell<root.ast.SrcLines> = root.std.Cell { value: root.ast.SrcLines.default() };
    for (let node in nodes) {
        let _ = emit_node_expanded(out, node, 0, prev, collector);
    }
    out.as_str()
}

/// dart `_isTrailingComment` (expanded style only): a comment joins the
/// previous line when it starts on the line the previous construct ended —
/// or, for a block's first child, on the parent's opening-brace line — and
/// both come from the same source file. `prev.end` always holds the
/// comparison line; a zero file id disables the rule.
///
/// A `previous` whose span is IDENTICAL to the comment's is a clone of the
/// same comment (the same file imported twice): dart's span-containment
/// branch then walks back for a `{`, finds `searchFrom < 0`, and rejects it.
function is_trailing(comment: root.ast.SrcLines, prev: root.ast.SrcLines) -> bool {
    comment.file != 0 && comment.file == prev.file && comment.start == prev.end && comment != prev
}

/// The previous-sibling seed for a block's children: the first child compares
/// against the block's opening-brace line (dart walks back to the `{`).
function block_start(lines: root.ast.SrcLines) -> root.ast.SrcLines {
    root.ast.SrcLines {
        file: lines.file,
        start: lines.start,
        end: lines.start,
        col: 0,
        start_col: 0,
        // The trailing-comment seed never feeds source-map output; map overrides
        // are irrelevant here.
        map_file: 0,
        map_line: 0,
    }
}

/// Append a trailing comment to the line already in `out`: drop the pending
/// newline(s) — at the root a group blank line may sit between — then write
/// ` /*…*/` with continuation lines at indentation 0 (dart saves and zeroes
/// `_indentation` for trailing comments).
function push_trailing_comment(
    out: root.std.StrBuf,
    text: string,
    lines: root.ast.SrcLines,
    collector: root.std.Cell<root.sourcemap.SmCollector?>,
) -> void {
    while (out.ends_with("\n")) {
        let _ = out.pop();
    }
    out.push(" ");
    // Source-map: the joined comment's `/*`.
    let mapped = record(out, lines, collector);
    let from = out.len();
    out.push_str("/*");
    push_comment_text(out, text, "", lines.start_col);
    out.push_str("*/");
    continue_span(out, from, mapped, collector);
    out.push("\n");
}

/// Close an expanded block opened with `" {\n"`. When its only child was a
/// trailing comment the whole block stays on one line (dart: ` }`, e.g.
/// `@font-face { /**/ }`); otherwise the `}` gets its own indented line.
function close_block(
    out: root.std.StrBuf,
    indent: string,
    children: int,
    last_joined: bool,
) -> void {
    if (children == 1 && last_joined) {
        let _ = out.pop(); // the trailing comment's newline
        out.push_str(" }\n");
    } else {
        out.push_str(indent);
        out.push_str("}\n");
    }
}

/// Indentation for a nesting depth (two spaces per level) without allocating:
/// `"  ".repeat(depth)` ran once per emitted node/item, which is tens of
/// thousands of short-lived Strings on a large output. Depths beyond the
/// precomputed pad (rare) fall back to an owned String.
// PORT: `Cow<'static, str>` → `string`.
function indent_for(depth: int) -> string {
    let PAD = "                                                                "; // 32 levels
    if (depth * 2 <= PAD.length()) {
        PAD.slice(0, depth * 2)
    } else {
        "  ".repeat(depth)
    }
}

/// Render one node at the given nesting `depth` (0 = document root). Each
/// extra level adds two spaces of indentation. `prev` carries the previous
/// sibling's source lines for the trailing-comment rule (its `end` is the
/// comparison line); returns whether THIS node was emitted as a trailing
/// comment joined onto the previous line.
function emit_node_expanded(
    out: root.std.StrBuf,
    node: root.eval.OutNode,
    depth: int,
    prev: root.std.Cell<root.ast.SrcLines>,
    collector: root.std.Cell<root.sourcemap.SmCollector?>,
) -> bool {
    let indent = indent_for(depth);
    match (node) {
        // A module-scope wrapper is transparent: emit its contents in place
        // (the previous-sibling line state flows through the boundary).
        let scope: root.eval.OutNode_ModuleScope => {
            let nodes = scope.nodes;
            let joined = false;
            for (let n in nodes) {
                joined = emit_node_expanded(out, n, depth, prev, collector);
            }
            return joined;
        },
        let rule: root.eval.OutNode_Rule => {
            let linebreaks = rule.linebreaks;
            let items = rule.items;
            let lines = rule.lines;
            // `Parsed` selectors render to their final strings here (byte-
            // identical to the strings the extend engine used to materialize);
            // `Raw` selectors borrow directly.
            let selectors = rule.selectors.to_strings();
            out.push_str(indent);
            // Source-map: the selector list's first character; a selector
            // list written over several lines maps each line (dart
            // `_for(node.selector, …)` spans the whole list).
            let mapped = record(out, lines, collector);
            let from = out.len();
            write_selector_list(out, selectors, linebreaks, indent);
            continue_span(out, from, mapped, collector);
            out.push_str(" {\n");
            let inner: root.std.Cell<root.ast.SrcLines> = root.std.Cell { value: block_start(lines) };
            let joined = false;
            for (let item in items) {
                joined = emit_item_expanded(out, item, depth + 1, inner, collector);
            }
            close_block(out, indent, items.length(), joined);
            prev.value = lines;
        },
        let comment: root.eval.OutNode_Comment => {
            let text = comment._0;
            let lines = comment._1;
            if (is_trailing(lines, prev.value)) {
                // Source-map: the joined `/*` (after the dropped newline + space).
                push_trailing_comment(out, text, lines, collector);
                prev.value = lines;
                return true;
            }
            // Source-map: dart opens the comment's span BEFORE writing its
            // indentation (`visitCssComment` indents inside `_for(node, …)`),
            // so a nested comment maps from column 0 of its line; each further
            // line of a multi-line comment maps there too.
            let mapped = record(out, lines, collector);
            let from = out.len();
            out.push_str(indent);
            out.push_str("/*");
            push_comment_text(out, text, indent, lines.start_col);
            out.push_str("*/");
            continue_span(out, from, mapped, collector);
            out.push("\n");
            prev.value = lines;
        },
        let raw: root.eval.OutNode_Raw => {
            let s = raw._0;
            let lines = raw._1;
            out.push_str(indent);
            // Source-map: a passed-through `@import` maps to its URL token
            // (dart `visitCssImport`); other raw lines carry no position.
            let _ = record(out, lines, collector);
            out.push_str(s);
            out.push("\n");
            prev.value = root.ast.SrcLines.default();
        },
        // Control-only hoist markers (consumed by the bubbling passes) never
        // reach the output and don't disturb the previous-sibling line state.
        let _m: root.eval.OutNode_GroupEnd
            | root.eval.OutNode_MediaHoist
            | root.eval.OutNode_AtRootHoist
            | root.eval.OutNode_AtRootPackTight =>
        {
            return false;
        },
        let _b: root.eval.OutNode_Blank => {
            // A synthetic group separator: dart has no such node, so it leaves
            // the previous-sibling line state alone (a trailing comment after
            // it joins across, swallowing the blank like dart does).
            out.push("\n");
        },
        let decl: root.eval.OutNode_AtDecl => {
            let prop = decl.prop;
            let value = decl.value;
            let important = decl.important;
            let custom = decl.custom;
            let lines = decl.lines;
            let value_span = decl.value_span;
            out.push_str(indent);
            // Source-map: the declaration property name.
            let _ = record(out, lines, collector);
            out.push_str(prop);
            emit_decl_value_expanded(out, value, important, custom, lines.col, indent, value_span, collector);
            out.push_str(";\n");
            prev.value = lines;
        },
        let at_rule: root.eval.OutNode_AtRule => {
            let name = at_rule.name;
            let prelude = at_rule.prelude;
            let body = at_rule.body;
            let has_block = at_rule.has_block;
            let lines = at_rule.lines;
            out.push_str(indent);
            // Source-map: the at-rule's `@` keyword; the span covers the
            // whole header (dart `_for(node, …)`), so a multi-line prelude
            // maps each of its lines.
            let mapped = record(out, lines, collector);
            let from = out.len();
            out.push("@");
            out.push_str(name);
            if (prelude != "") {
                out.push(" ");
                out.push_str(prelude);
            }
            continue_span(out, from, mapped, collector);
            prev.value = lines;
            if (!has_block) {
                out.push_str(";\n");
                return false;
            }
            if (body.length() == 0) {
                out.push_str(" {}\n");
                return false;
            }
            out.push_str(" {\n");
            let inner: root.std.Cell<root.ast.SrcLines> = root.std.Cell { value: block_start(lines) };
            let children = 0;
            let joined = false;
            for (let child in body) {
                let before = out.len();
                let j = emit_node_expanded(out, child, depth + 1, inner, collector);
                // Sentinels emit nothing and don't count as children.
                if (out.len() > before) {
                    children += 1;
                    joined = j;
                }
            }
            close_block(out, indent, children, joined);
        },
        _ => root.std.unreachable(),
    }
    false
}

/// Render one rule-block item; same `prev`/return contract as
/// [`emit_node_expanded`].
function emit_item_expanded(
    out: root.std.StrBuf,
    item: root.eval.OutItem,
    depth: int,
    prev: root.std.Cell<root.ast.SrcLines>,
    collector: root.std.Cell<root.sourcemap.SmCollector?>,
) -> bool {
    let indent = indent_for(depth);
    match (item) {
        let decl: root.eval.OutItem_Decl => {
            let prop = decl.prop;
            let value = decl.value;
            let important = decl.important;
            let custom = decl.custom;
            let lines = decl.lines;
            let value_span = decl.value_span;
            out.push_str(indent);
            // Source-map: the declaration property name.
            let _ = record(out, lines, collector);
            out.push_str(prop);
            emit_decl_value_expanded(out, value, important, custom, lines.col, indent, value_span, collector);
            out.push_str(";\n");
            prev.value = lines;
        },
        let comment: root.eval.OutItem_Comment => {
            let text = comment._0;
            let lines = comment._1;
            if (is_trailing(lines, prev.value)) {
                push_trailing_comment(out, text, lines, collector);
                prev.value = lines;
                return true;
            }
            // Source-map: column 0 of the line, before the indentation (see
            // the `OutNode::Comment` arm), then every further line.
            let mapped = record(out, lines, collector);
            let from = out.len();
            out.push_str(indent);
            out.push_str("/*");
            push_comment_text(out, text, indent, lines.start_col);
            out.push_str("*/");
            continue_span(out, from, mapped, collector);
            out.push("\n");
            prev.value = lines;
        },
        let at_rule: root.eval.OutItem_ChildlessAtRule => {
            let name = at_rule.name;
            let prelude = at_rule.prelude;
            let lines = at_rule.lines;
            out.push_str(indent);
            // Source-map: the at-rule's `@` keyword, spanning the header.
            let mapped = record(out, lines, collector);
            let from = out.len();
            out.push("@");
            out.push_str(name);
            if (prelude != "") {
                out.push(" ");
                out.push_str(prelude);
            }
            continue_span(out, from, mapped, collector);
            out.push_str(";\n");
            prev.value = lines;
        },
        let rule: root.eval.OutItem_NestedRule => {
            let selectors = rule.selectors;
            let linebreaks = rule.linebreaks;
            let items = rule.items;
            let lines = rule.lines;
            out.push_str(indent);
            // Source-map: the selector list's first character, and each
            // further line of a multi-line list.
            let mapped = record(out, lines, collector);
            let from = out.len();
            write_selector_list(out, selectors, linebreaks, indent);
            continue_span(out, from, mapped, collector);
            out.push_str(" {\n");
            let inner: root.std.Cell<root.ast.SrcLines> = root.std.Cell { value: root.ast.SrcLines.default() };
            let joined = false;
            for (let child in items) {
                joined = emit_item_expanded(out, child, depth + 1, inner, collector);
            }
            close_block(out, indent, items.length(), joined);
            prev.value = root.ast.SrcLines.default();
        },
        let at_rule: root.eval.OutItem_NestedAtRule => {
            let name = at_rule.name;
            let prelude = at_rule.prelude;
            let items = at_rule.items;
            let lines = at_rule.lines;
            out.push_str(indent);
            // Source-map: the at-rule's `@` keyword, spanning the header (so a
            // prelude written over several lines maps each of its lines).
            let mapped = record(out, lines, collector);
            let from = out.len();
            out.push("@");
            out.push_str(name);
            if (prelude != "") {
                out.push(" ");
                out.push_str(prelude);
            }
            continue_span(out, from, mapped, collector);
            // An empty block goes on one line, as a top-level at-rule's does.
            if (items.length() == 0) {
                out.push_str(" {}\n");
                prev.value = root.ast.SrcLines.default();
                return false;
            }
            out.push_str(" {\n");
            let inner: root.std.Cell<root.ast.SrcLines> = root.std.Cell { value: root.ast.SrcLines.default() };
            let joined = false;
            for (let child in items) {
                joined = emit_item_expanded(out, child, depth + 1, inner, collector);
            }
            close_block(out, indent, items.length(), joined);
            prev.value = root.ast.SrcLines.default();
        },
        _ => root.std.unreachable(),
    }
    false
}

/// Append the `: value [!important]` portion of an expanded declaration. A
/// custom property emits its value verbatim right after the colon (its leading
/// whitespace is part of `value`, dart-sass adds no space) and never appends an
/// `!important` flag; a normal declaration uses the canonical `: ` separator.
/// A multi-line custom value is re-indented (dart `_writeReindentedValue`):
/// `name_col` is the declaration name's 0-based source column and `indent`
/// the current output indentation.
function emit_decl_value_expanded(
    out: root.std.StrBuf,
    value: string,
    important: bool,
    custom: bool,
    name_col: int,
    indent: string,
    value_span: root.eval.VarSpan,
    collector: root.std.Cell<root.sourcemap.SmCollector?>,
) -> void {
    if (custom) {
        out.push(":");
        // dart wraps a custom property's value in `_for(node.value, …)`
        // (serialize.dart:379): the span opens at the value's own text, which
        // begins immediately after the colon, and stays open over a
        // re-indented multi-line value, mapping each of its lines.
        let mapped = record_span(out, value_span, collector);
        let from = out.len();
        match (minimum_indentation(value)) {
            let _s: MinIndent_SingleLine => out.push_str(value),
            let _t: MinIndent_Trailing => {
                out.push_str(trim_ascii_right_exclude_escape(value));
                out.push(" ");
            },
            MinIndent_Min { _0: let m } => {
                write_with_indent(out, value, root.std.imin(m, name_col), indent)
            },
            _ => root.std.unreachable(),
        }
        continue_span(out, from, mapped, collector);
        return;
    }
    out.push_str(": ");
    // dart wraps a SassScript value in `_buffer.forSpan(node.valueSpanForMap,
    // …)` (serialize.dart:389), so the mapping opens at the first byte of the
    // serialized value — after the `: `, not at the property name. For a bare
    // `$name` value this points at the variable's DEFINITION, which is the
    // whole reason this second entry is not redundant with the property one.
    let _ = record_span(out, value_span, collector);
    out.push_str(value);
    if (important) {
        out.push_str(" !important");
    }
}

/// dart `_minimumIndentation`: the minimum indentation of `text`'s
/// continuation lines, skipping blank lines.
interface MinIndent {}

/// `text` has no newline — emit verbatim.
class MinIndent_SingleLine {
    implements MinIndent {}
}

/// Every continuation line is blank (dart's `-1`) — trim right + space.
class MinIndent_Trailing {
    implements MinIndent {}
}

/// The least indented non-blank continuation line starts at this column.
class MinIndent_Min {
    _0: int,
    implements MinIndent {}
}

function minimum_indentation(text: string) -> MinIndent {
    // PORT: `text.as_bytes()` → the chars array; every byte tested here is
    // ASCII, so char and byte counts agree.
    let bytes = text.chars();
    let p = text.index_of("\n");
    if (p == null) {
        return MinIndent_SingleLine {  };
    }
    let i = p + 1;
    if (i >= bytes.length()) {
        return MinIndent_Trailing {  };
    }
    let min: int? = null;
    while (i < bytes.length()) {
        let start = i;
        while (i < bytes.length() && (bytes[i] == " " || bytes[i] == "\t")) {
            i += 1;
        }
        if (i >= bytes.length()) {
            break; // a trailing all-whitespace line is not counted
        }
        if (bytes[i] == "\n") {
            i += 1; // blank line: not counted
            continue;
        }
        let col = i - start;
        min
            = if (min == null) {
                col
            } else {
                root.std.imin(min, col)
            };
        while (i < bytes.length() && bytes[i] != "\n") {
            i += 1;
        }
        i += 1;
    }
    if (min == null) {
        MinIndent_Trailing {  }
    } else {
        MinIndent_Min { _0: min }
    }
}

/// dart `trimAsciiRight(value, excludeEscape: true)`: strip trailing ASCII
/// whitespace, but keep one character after a terminating backslash so an
/// escaped trailing space survives.
function trim_ascii_right_exclude_escape(s: string) -> string {
    // PORT: `s.as_bytes()` → the chars array (all tested chars are ASCII).
    let bytes = s.chars();
    let end = bytes.length();
    while (
        end > 0
            && (
                bytes[end - 1] == " "
                    || bytes[end - 1] == "\t"
                    || bytes[end - 1] == "\n"
                    || bytes[end - 1] == "\r"
                    || bytes[end - 1] == "\f"
            )
    ) {
        end -= 1;
    }
    if (end != 0 && end != bytes.length() && bytes[end - 1] == "\\") {
        end += 1;
    }
    s.slice(0, end)
}

/// dart `_writeWithIndent`: write the first line verbatim, then each
/// continuation line stripped of `min_indent` characters and prefixed with
/// the current output indentation. Blank lines stay blank; a trailing
/// all-whitespace line folds to a single space.
function write_with_indent(
    out: root.std.StrBuf,
    text: string,
    min_indent: int,
    indent: string,
) -> void {
    // PORT: `text.as_bytes()[i]` → a chars array built once.
    let text_chars = text.chars();
    let text_len = text_chars.length();
    let first_end = text.index_of("\n") ?? text_len;
    out.push_str(text.slice(0, first_end));
    if (first_end == text_len) {
        return;
    }
    let i = first_end + 1;
    while (true) {
        let line_start = i;
        let newlines = 1;
        // Scan the whitespace run, counting blank lines; `i` settles on the
        // first non-whitespace character (the run's indentation is ASCII, so
        // byte stepping stays on char boundaries).
        while (true) {
            if (i >= text_len) {
                out.push(" ");
                return;
            }
            let b = text_chars[i];
            if (b == " " || b == "\t") {
                i += 1;
            } else if (b == "\n") {
                i += 1;
                line_start = i;
                newlines += 1;
            } else {
                break;
            }
        }
        let k = 0;
        while (k < newlines) {
            out.push("\n");
            k += 1;
        }
        out.push_str(indent);
        let line_end = root.std.find_from(text, "\n", i) ?? text_len;
        out.push_str(text.slice(line_start + min_indent, line_end));
        if (line_end == text_len) {
            return;
        }
        i = line_end + 1;
    }
}

function emit_compressed(
    nodes: root.eval.OutNode[],
    collector: root.std.Cell<root.sourcemap.SmCollector?>,
) -> string {
    let out = root.std.StrBuf.new();
    let last: root.eval.OutNode? = null;
    for (let node in nodes) {
        let before = out.len();
        emit_node_compressed(out, node, collector);
        if (out.len() != before) {
            last = node;
        }
    }
    drop_trailing_semicolon(out, last);
    out.as_str()
}

/// dart writes a statement's `;` as a SEPARATOR, so compressed output never
/// ends with one — not at the end of the stylesheet and not before a `}`. Every
/// node here is separated that way except a verbatim line (a passed-through
/// `@import`), which carries its own `;`; that one is dropped when the line
/// comes last.
///
/// The test is which NODE wrote the final byte, never the byte itself: a
/// declaration's value is verbatim text and can end in a `;` of its own
/// (`--x: #{";"}`), which dart keeps.
function drop_trailing_semicolon(out: root.std.StrBuf, last: root.eval.OutNode?) -> void {
    let own = if (last != null) {
        ends_with_own_semicolon(last)
    } else {
        false
    };
    if (own && out.ends_with(";")) {
        let _ = out.pop();
    }
}

/// Whether this node's compressed output ends with a `;` the node itself wrote
/// — true for a verbatim line, and for a wrapper whose last VISIBLE child is
/// one.
function ends_with_own_semicolon(node: root.eval.OutNode) -> bool {
    match (node) {
        let raw: root.eval.OutNode_Raw => raw._0.ends_with(";"),
        // A childless at-rule (`@namespace "x";`) writes its own terminator.
        let at_rule: root.eval.OutNode_AtRule => !at_rule.has_block,
        let scope: root.eval.OutNode_ModuleScope => {
            let found = scope.nodes.reverse().find((n) -> {
                writes_compressed_output(n)
            });
            if (found != null) {
                ends_with_own_semicolon(found)
            } else {
                false
            }
        },
        _ => false,
    }
}

/// Whether a node writes anything at all in compressed output. A blank, a
/// control-only marker, a comment that is not loud, a rule holding nothing but
/// dropped comments, and a module whose whole CSS is one of those all write
/// nothing — so none of them can be the node that wrote the last byte.
function writes_compressed_output(node: root.eval.OutNode) -> bool {
    match (node) {
        let _b: root.eval.OutNode_Blank => false,
        let comment: root.eval.OutNode_Comment => is_loud_comment(comment._0),
        let rule: root.eval.OutNode_Rule => {
            rule.items.some((i) -> {
                item_writes_compressed(i)
            })
        },
        // A module splices in transparently, so it is only as visible as its
        // contents — `meta.load-css` of a stylesheet that is all comments
        // writes nothing and must not hide the node before it.
        let scope: root.eval.OutNode_ModuleScope => {
            scope.nodes.some((n) -> {
                writes_compressed_output(n)
            })
        },
        // A childless at-rule (`@namespace "x";`) is always written, and so is
        // a generic one with a block, empty or not; only the conditional group
        // rules are as visible as their contents.
        let at_rule: root.eval.OutNode_AtRule => {
            !at_rule.has_block
                || !at_rule_drops_when_empty(at_rule.kind)
                || at_rule.body.some((n) -> {
                    writes_compressed_output(n)
                })
        },
        let n => !n.is_inert_marker(),
    }
}

/// Render `nodes` joined for compressed output. A declaration is terminated by
/// `;` before whatever follows it, but a preceding rule/at-rule `}` is its own
/// separator, so no `;` is inserted after it (matching dart-sass).
function emit_compressed_body(
    out: root.std.StrBuf,
    nodes: root.eval.OutNode[],
    collector: root.std.Cell<root.sourcemap.SmCollector?>,
) -> void {
    let prev_was_decl = false;
    let last: root.eval.OutNode? = null;
    for (let node in nodes) {
        // A blank, and a comment that is not LOUD, produce no compressed
        // output; don't let them reset the separator state. A loud comment is
        // written, takes the pending separator, and needs none of its own.
        if let comment: root.eval.OutNode_Comment = node {
            let text = comment._0;
            let lines = comment._1;
            if (is_loud_comment(text)) {
                if (prev_was_decl) {
                    out.push(";");
                    prev_was_decl = false;
                }
                write_comment_compressed(out, text, lines, collector);
                last = node;
            }
            continue;
        }
        // A node that writes nothing neither emits nor takes the separator.
        if (!writes_compressed_output(node)) {
            continue;
        }
        if (prev_was_decl) {
            out.push(";");
        }
        let before = out.len();
        emit_node_compressed(out, node, collector);
        if (out.len() != before) {
            last = node;
        }
        prev_was_decl = node is root.eval.OutNode_AtDecl;
    }
    drop_trailing_semicolon(out, last);
}

/// dart `_writeFoldedValue` (compressed custom properties): each newline
/// becomes a single space and the whitespace run following it is dropped.
/// Non-custom values pass through untouched.
// PORT: `Cow<'v, str>` → `string`.
function fold_value_compressed(value: string, custom: bool) -> string {
    if (!custom || !value.includes("\n")) {
        return value;
    }
    let out = root.std.StrBuf.with_capacity(value.length());
    // PORT: `chars().peekable()` → the chars array with an index cursor.
    let chars = value.chars();
    let k = 0;
    while (k < chars.length()) {
        let c = chars[k];
        k += 1;
        if (c != "\n") {
            out.push(c);
            continue;
        }
        out.push(" ");
        while (
            k < chars.length()
                && (
                    chars[k] == " "
                        || chars[k] == "\t"
                        || chars[k] == "\n"
                        || chars[k] == "\r"
                        || chars[k] == "\f"
                )
        ) {
            k += 1;
        }
    }
    out.as_str()
}

/// dart-sass omits the space between the at-rule name and a prelude that begins
/// with `(` in compressed output, but ONLY in `visitCssMediaRule` and
/// `visitCssSupportsRule` — the serializers the two conditional group rules have
/// of their own. Every other at-rule keeps the space even before `(`, e.g.
/// `@container (min-width:1px)` and, because the class is what counts,
/// `@#{"media"} (a: 1)`.
function compressed_at_rule_omits_space(kind: root.eval.AtRuleKind, prelude: string) -> bool {
    kind.is_conditional() && prelude.starts_with("(")
}

/// Write a rule block's items for compressed output, recording each item's
/// source-map entry.
///
/// dart `_visitChildren` separates two children with `;` only when the first
/// `_requiresSemicolon` — a childless node (a declaration, an `@import`). A
/// nested rule or at-rule ends in `}`, which is its own separator, so no `;`
/// follows it.
function write_items_compressed(
    out: root.std.StrBuf,
    items: root.eval.OutItem[],
    collector: root.std.Cell<root.sourcemap.SmCollector?>,
) -> void {
    let pending_semicolon = false;
    for (let item in items) {
        // An item that writes nothing — a dropped comment, a rule or at-rule
        // holding only those — neither emits nor takes the pending separator.
        if (!item_writes_compressed(item)) {
            continue;
        }
        if let comment: root.eval.OutItem_Comment = item {
            let text = comment._0;
            let lines = comment._1;
            // A LOUD comment is how a stylesheet keeps its licence header. It
            // takes the pending separator (`b:1;/*! c */`) but needs none of
            // its own.
            if (pending_semicolon) {
                out.push(";");
                pending_semicolon = false;
            }
            write_comment_compressed(out, text, lines, collector);
            continue;
        }
        if (pending_semicolon) {
            out.push(";");
        }
        pending_semicolon = write_item_compressed(out, item, collector);
    }
}

/// Whether a comment survives compressed output: dart keeps the ones that open
/// `/*!`, the convention for "this is a licence, do not strip me".
function is_loud_comment(text: string) -> bool {
    text.starts_with("!")
}

/// Whether an item writes anything at all in compressed output. A dropped
/// comment writes nothing, and so does a nested RULE holding only such items —
/// however deep that goes, a plain-CSS `.a { .b { /* c */ } }` leaves dart with
/// nothing to print at either level. A nested at-rule follows
/// [`at_rule_drops_when_empty`].
function item_writes_compressed(item: root.eval.OutItem) -> bool {
    match (item) {
        let comment: root.eval.OutItem_Comment => is_loud_comment(comment._0),
        let rule: root.eval.OutItem_NestedRule => {
            rule.items.some((i) -> {
                item_writes_compressed(i)
            })
        },
        let at_rule: root.eval.OutItem_NestedAtRule => {
            !at_rule_drops_when_empty(at_rule.kind)
                || at_rule.items.some((i) -> {
                    item_writes_compressed(i)
                })
        },
        _ => true,
    }
}

/// Whether an at-rule goes away when its block writes nothing.
///
/// Only the two conditional group rules do. dart-sass keeps every other
/// at-rule, deliberately: `_isInvisible` short-circuits on `CssAtRule` with the
/// comment "an unknown at-rule is never invisible. Because we don't know the
/// semantics of unknown rules, we can't guarantee that (for example) `@foo {}`
/// isn't meaningful." `CssMediaRule` and `CssSupportsRule` fall through to
/// "invisible when every child is", which is why
/// `@media print { a { /* c */ } }` compresses to nothing while
/// `@keyframes k { 10% { /* c */ } }` compresses to `@keyframes k{}`.
///
/// `[measured]` against dart-sass 1.104.1, the test is the PARSED rule, not the
/// spelling: `@MEDIA screen { /* c */ }` and `@#{"media"} screen { /* c */ }`
/// are both generic at-rules there and both survive. That is what
/// [`AtRuleKind`] records, so both survive here too — in either style.
function at_rule_drops_when_empty(kind: root.eval.AtRuleKind) -> bool {
    kind.is_conditional()
}

/// Write a loud comment for compressed output — verbatim, newlines and all,
/// with no separator of its own.
function write_comment_compressed(
    out: root.std.StrBuf,
    text: string,
    lines: root.ast.SrcLines,
    collector: root.std.Cell<root.sourcemap.SmCollector?>,
) -> void {
    let mapped = record(out, lines, collector);
    let from = out.len();
    out.push_str("/*");
    out.push_str(text);
    out.push_str("*/");
    continue_span(out, from, mapped, collector);
}

/// Write one rule-block item for compressed output. Returns whether a `;` must
/// separate it from whatever follows (see [`write_items_compressed`]).
function write_item_compressed(
    out: root.std.StrBuf,
    item: root.eval.OutItem,
    collector: root.std.Cell<root.sourcemap.SmCollector?>,
) -> bool {
    match (item) {
        let decl: root.eval.OutItem_Decl => {
            let prop = decl.prop;
            let value = decl.value;
            let important = decl.important;
            let custom = decl.custom;
            let lines = decl.lines;
            let value_span = decl.value_span;
            // A custom property emits its value verbatim (its leading
            // whitespace is part of `value`) and never gains an `!important`.
            let imp = if (important && !custom) {
                "!important"
            } else {
                ""
            };
            // Source-map: the declaration property name.
            let _ = record(out, lines, collector);
            out.push_str(prop);
            out.push(":");
            // Source-map: the value, which for a bare `$name` points at the
            // variable's definition rather than at this line.
            let _ = record_span(out, value_span, collector);
            out.push_str(fold_value_compressed(value, custom));
            out.push_str(imp);
            true
        },
        let _c: root.eval.OutItem_Comment => false,
        let at_rule: root.eval.OutItem_ChildlessAtRule => {
            let name = at_rule.name;
            let prelude = at_rule.prelude;
            let css_import = at_rule.css_import;
            let lines = at_rule.lines;
            // Source-map: the at-rule's `@` keyword.
            let _ = record(out, lines, collector);
            out.push("@");
            out.push_str(name);
            if (prelude != "") {
                // A CSS `@import` writes no space before its url when
                // compressing. That belongs to the IMPORT, not to the name: an
                // at-rule whose name is interpolated (`@#{"import"} "x"`) is
                // generic in dart and keeps its gap. Nothing else can drop it
                // here: a conditional group rule always has a block, so it is
                // never childless.
                if (!css_import) {
                    out.push(" ");
                }
                out.push_str(prelude);
            }
            true
        },
        // A plain-CSS nested rule (a loaded `.css` file that uses CSS nesting):
        // dart visits its children like any other rule's, so they carry their
        // own mappings.
        let rule: root.eval.OutItem_NestedRule => {
            let selectors = rule.selectors;
            let items = rule.items;
            let lines = rule.lines;
            // Source-map: the nested selector list's first character.
            let _ = record(out, lines, collector);
            write_selectors_compressed(out, selectors);
            out.push("{");
            write_items_compressed(out, items, collector);
            out.push("}");
            false
        },
        let at_rule: root.eval.OutItem_NestedAtRule => {
            let name = at_rule.name;
            let prelude = at_rule.prelude;
            let items = at_rule.items;
            let kind = at_rule.kind;
            let lines = at_rule.lines;
            // Source-map: the at-rule's `@` keyword.
            let _ = record(out, lines, collector);
            out.push("@");
            out.push_str(name);
            if (prelude != "") {
                if (!compressed_at_rule_omits_space(kind, prelude)) {
                    out.push(" ");
                }
                out.push_str(prelude);
            }
            out.push("{");
            write_items_compressed(out, items, collector);
            out.push("}");
            false
        },
        _ => root.std.unreachable(),
    }
}

/// Write a selector list for compressed output: a bare comma between the
/// complexes, each one written the way dart compresses a selector (no space
/// around a combinator, none after a selector-list comma).
function write_selectors_compressed(out: root.std.StrBuf, selectors: string[]) -> void {
    let i = 0;
    for (let sel in selectors) {
        if (i > 0) {
            out.push(",");
        }
        out.push_str(root.selector.compress_selector(sel));
        i += 1;
    }
}

function emit_node_compressed(
    out: root.std.StrBuf,
    node: root.eval.OutNode,
    collector: root.std.Cell<root.sourcemap.SmCollector?>,
) -> void {
    match (node) {
        let scope: root.eval.OutNode_ModuleScope => {
            for (let n in scope.nodes) {
                emit_node_compressed(out, n, collector);
            }
        },
        let rule: root.eval.OutNode_Rule => {
            let selectors = rule.selectors;
            let items = rule.items;
            let lines = rule.lines;
            // A rule that writes nothing produces nothing in compressed
            // output, so it is not emitted at all — a dropped comment writes
            // nothing, and neither does a nested rule holding only those.
            if (
                !items.some((i) -> {
                    item_writes_compressed(i)
                })
            ) {
                return;
            }
            // Source-map: the selector list's first character.
            let _ = record(out, lines, collector);
            write_selectors_compressed(out, selectors.to_strings());
            out.push("{");
            write_items_compressed(out, items, collector);
            out.push("}");
        },
        let comment: root.eval.OutNode_Comment => {
            let text = comment._0;
            let lines = comment._1;
            if (is_loud_comment(text)) {
                write_comment_compressed(out, text, lines, collector);
            }
        },
        let raw: root.eval.OutNode_Raw => {
            let s = raw._0;
            let lines = raw._1;
            // Source-map: a passed-through `@import` maps to its URL token.
            let _ = record(out, lines, collector);
            out.push_str(s);
        },
        let _b: root.eval.OutNode_Blank => {},
        // Control-only hoist markers never reach the output.
        let _m: root.eval.OutNode_GroupEnd
            | root.eval.OutNode_MediaHoist
            | root.eval.OutNode_AtRootHoist
            | root.eval.OutNode_AtRootPackTight =>
        {},
        let decl: root.eval.OutNode_AtDecl => {
            let prop = decl.prop;
            let value = decl.value;
            let important = decl.important;
            let custom = decl.custom;
            let lines = decl.lines;
            let value_span = decl.value_span;
            let imp = if (important && !custom) {
                "!important"
            } else {
                ""
            };
            // Source-map: the declaration property name.
            let _ = record(out, lines, collector);
            out.push_str(prop);
            out.push(":");
            // Source-map: the value (dart's `forSpan(valueSpanForMap)`).
            let _ = record_span(out, value_span, collector);
            out.push_str(fold_value_compressed(value, custom));
            out.push_str(imp);
        },
        let at_rule: root.eval.OutNode_AtRule => {
            let name = at_rule.name;
            let prelude = at_rule.prelude;
            let body = at_rule.body;
            let has_block = at_rule.has_block;
            let kind = at_rule.kind;
            let lines = at_rule.lines;
            // A `@media`/`@supports` block that writes nothing leaves dart
            // nothing to print: the at-rule goes with it, exactly as a rule of
            // dropped comments does. Every other at-rule stays — see
            // `at_rule_drops_when_empty`.
            if (
                has_block
                    && at_rule_drops_when_empty(kind)
                    && !body.some((n) -> {
                        writes_compressed_output(n)
                    })
            ) {
                return;
            }
            // Source-map: the at-rule's `@` keyword.
            let _ = record(out, lines, collector);
            out.push("@");
            out.push_str(name);
            if (prelude != "") {
                // Compressed `@media`/`@supports` omit the space before a prelude
                // that begins with `(` (dart `visitCssMediaRule`/`visitCssSupportsRule`).
                if (!compressed_at_rule_omits_space(kind, prelude)) {
                    out.push(" ");
                }
                out.push_str(prelude);
            }
            if (!has_block) {
                out.push(";");
                return;
            }
            out.push("{");
            emit_compressed_body(out, body, collector);
            out.push("}");
        },
        _ => root.std.unreachable(),
    }
}

/// Write a loud comment's text with dart's continuation-line handling
/// (`_minimumIndentation` + `_writeWithIndent`, run on the EVALUATED text so
/// interpolated comments dedent too): continuation lines lose
/// `min(<minimum indentation across them>, <the comment's own source start
/// column>)` leading whitespace and gain the CURRENT output indentation;
/// whitespace-only interior lines collapse to bare newlines. The final line
/// always counts as content — the `*/` closer follows this text.
function push_comment_text(
    out: root.std.StrBuf,
    text: string,
    indent: string,
    start_col: int,
) -> void {
    if (!text.includes("\n")) {
        out.push_str(text);
        return;
    }
    let lines = text.split("\n");
    let min: int? = null;
    for (let i in baml.iter.Range.new(1, lines.length())) {
        let line = lines[i];
        if (i + 1 != lines.length() && root.std.trim(line) == "") {
            continue;
        }
        let ind = line.length()
            - root.std
                .trim_start_by(line, (c) -> {
                    c == " " || c == "\t"
                })
                .length();
        min
            = if (min == null) {
                ind
            } else {
                root.std.imin(min, ind)
            };
    }
    let strip = if (min == null) {
        0
    } else {
        root.std.imin(min, start_col)
    };
    out.push_str(lines[0]);
    for (let i in baml.iter.Range.new(1, lines.length())) {
        let line = lines[i];
        out.push("\n");
        if (i + 1 != lines.length() && root.std.trim(line) == "") {
            continue;
        }
        let ind = line.length()
            - root.std
                .trim_start_by(line, (c) -> {
                    c == " " || c == "\t"
                })
                .length();
        out.push_str(indent);
        out.push_str(line.slice(root.std.imin(strip, ind), line.length()));
    }
}

/// Write a rule's selector list in expanded style: a complex selector flagged
/// with a source line break starts on its own line (aligned to the rule's
/// indent), the others are `, `-joined; a line break INSIDE a selector (a
/// pseudo arg's preserved source line) continues at the rule's indent, like
/// dart's `_writeIndentation` after every line feed.
function write_selector_list(
    out: root.std.StrBuf,
    selectors: string[],
    linebreaks: bool[],
    indent: string,
) -> void {
    let i = 0;
    for (let sel in selectors) {
        if (i > 0) {
            out.push(",");
            if (linebreaks.at(i) ?? false) {
                out.push("\n");
                out.push_str(indent);
            } else {
                out.push(" ");
            }
        }
        if (sel.includes("\n") && indent != "") {
            let first = true;
            for (let line in sel.split("\n")) {
                if (!first) {
                    out.push("\n");
                    out.push_str(indent);
                }
                out.push_str(line);
                first = false;
            }
        } else {
            out.push_str(sel);
        }
        i += 1;
    }
}
