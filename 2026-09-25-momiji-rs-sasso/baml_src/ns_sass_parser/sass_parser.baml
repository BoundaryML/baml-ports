// Ported from sasso `src/sass_parser.rs` (namespace `root.sass_parser`).
//
// The indented (`.sass`) syntax front-end.
//
// The indented syntax describes the *same* language as SCSS — the same
// statements, the same SassScript value grammar, the same AST — but block
// structure comes from indentation and statement boundaries from newlines,
// rather than from `{ … }` and `;`. dart-sass parses `.sass` into the very
// same tree as `.scss`, so the evaluator and emitter are shared verbatim.
//
// This module is a *front-end only*: it reads the indentation-structured
// source, recovers the block tree (handling multiline continuations, the
// `=`/`+` mixin shorthands, `//`/`/* */` comments and custom-property
// values), and reconstructs an equivalent brace/semicolon SCSS source which
// it hands to the SCSS parser ([`crate::parser::parse_indented`]). The whole
// SassScript value/prelude/selector grammar is therefore reused unchanged.
//
// The reconstruction is POSITION-PRESERVING: every statement is emitted on
// its own source line (blank lines pad the output up to it), with its source
// indentation kept, and a block's closing `}` rides on the last line of the
// block rather than on a line of its own. Every `Pos` the SCSS parser reports
// for a STATEMENT — diagnostics, deprecation spans, source-map entries — is
// therefore a position in the `.sass` file itself, as dart-sass reports them.
//
// One construct is deliberately excepted: a loud comment is SERIALIZED, not
// copied. dart drops blank lines between a bare `/*` and the comment's first
// text and renders that text on the `/*` line, so the reconstruction must do
// the same to emit dart's CSS — and a diagnostic inside interpolated comment
// text therefore reports against the rendered line rather than the `.sass`
// one. Matching dart's output wins over matching its span there.
//
// Nothing on
// a line is rewritten: the three constructs the SCSS grammar does not share —
// the `=name`/`+name` mixin shorthands, the legacy `\:hover` escaped-selector
// marker, and unquoted `@import` urls — are read by the parser itself in
// indented mode ([`crate::parser::parse_indented`]), because expanding or
// unquoting them would move every column after them.

/// Parse indented (`.sass`) source into the shared [`Stylesheet`] AST.
function parse(src: string) -> root.ast.Stylesheet {
    let scss = Transpiler.new(src).run();
    root.parser.parse_indented(scss)
}

/// One physical source line, split into its indentation and content.
class Raw {
    /// 1-based line number (for error positions).
    line: int,
    /// Indentation width in columns (tabs and spaces, with tab == 1 column —
    /// dart-sass measures indentation in characters, and forbids mixing).
    indent: int,
    /// The raw indentation characters (to detect tab/space mixing).
    indent_str: string,
    /// The line content with the leading indentation removed (trailing
    /// whitespace kept; it matters for continuation detection only after trim).
    content: string,
}

class Transpiler {
    lines: Raw[],
    /// Cursor into `lines`.
    idx: int,
    /// The assembled SCSS output.
    // PORT: `String` appended to throughout the transform -> `StrBuf`.
    out: root.std.StrBuf,
    /// Newlines already counted in `out[..scanned]` — the output line the end
    /// of `out` sits on is tracked incrementally by [`Transpiler::pad_to`].
    out_lines: int,
    scanned: int,
    /// Whether the current block is the body of a plain-CSS custom
    /// `@function --x()`/`@mixin --x()` (where a literal `result` declaration
    /// may not have an indented child block).
    in_css_callable: bool,

    function new(src: string) -> Transpiler {
        // Normalise line endings the way dart-sass does (it treats CR, CRLF and
        // form-feed as newlines for line-splitting purposes).
        // PORT: `.replace(['\r', '\u{c}'], "\n")` (a char-set pattern) -> one
        // `replace_all` per char.
        let normalized = src.replace_all("\r\n", "\n").replace_all("\r", "\n").replace_all("\f", "\n");
        let lines: Raw[] = [];
        let i = 0;
        for (let physical in normalized.split("\n")) {
            let indent = 0;
            let indent_str = "";
            let rest = physical;
            // PORT: `char_indices()` -> a char counter `b` (char offsets).
            let pcs = physical.chars();
            let b = 0;
            for (let ch in pcs) {
                if (ch == " " || ch == "\t") {
                    indent += 1;
                    indent_str = indent_str + ch;
                } else {
                    rest = physical.slice(b, pcs.length());
                    break;
                }
                rest = physical.slice(b + 1, pcs.length());
                b += 1;
            }
            lines.push(Raw { line: i + 1, indent: indent, indent_str: indent_str, content: rest });
            i += 1;
        }
        Transpiler {
            lines: lines,
            idx: 0,
            out: root.std.StrBuf.new(),
            out_lines: 0,
            scanned: 0,
            in_css_callable: false,
        }
    }

    /// Pad the output with blank lines until its current line is source line
    /// `line_no` (1-based), so the statement emitted next sits on the line it
    /// came from. Consumed source lines (silent comments, joined
    /// continuations) leave gaps that this fills; nothing ever gets AHEAD of
    /// its source line because every construct emits at most as many lines
    /// as it consumed.
    function pad_to(self, line_no: int) -> void {
        self.out_lines += self.out.slice_from(self.scanned).split("\n").length() - 1;
        self.scanned = self.out.len();
        while (self.out_lines + 1 < line_no) {
            self.out.push("\n");
            self.out_lines += 1;
        }
        self.scanned = self.out.len();
    }

    /// Whether the line at `i` is blank (only whitespace).
    function is_blank(self, i: int) -> bool {
        let l = self.lines.at(i);
        if (l != null) {
            root.std.trim(l.content) == ""
        } else {
            true
        }
    }

    function run(self) -> string {
        // The base indentation is whatever the first non-blank line uses.
        self.parse_block(0, 0);
        self.out.as_str()
    }

    /// Find the next non-blank line index at or after `from`.
    function next_nonblank(self, from: int) -> int? {
        let i = from;
        while (i < self.lines.length()) {
            if (!self.is_blank(i)) {
                return i;
            }
            i += 1;
        }
        null
    }

    /// Parse a block whose statements are indented at exactly `block_indent`
    /// (statements at a *greater* indent belong to a child block). `parent_indent`
    /// is the indentation of the line that opened this block (or 0 at the root),
    /// used only to validate that a deeper indent is consistent. Emits SCSS into
    /// `self.out`.
    function parse_block(self, block_indent: int, unused_parent_indent: int) -> void {
        while (true) {
            // Skip blank lines.
            let i = self.next_nonblank(self.idx);
            if (i == null) {
                self.idx = self.lines.length();
                break;
            }
            self.idx = i;
            let indent = self.lines[i].indent;
            if (indent < block_indent) {
                // Dedent: this line belongs to an outer block.
                break;
            }
            if (indent > block_indent) {
                // A deeper indent with no statement to attach to is an error.
                throw root.error.Error.at(
                    "This line was indented unexpectedly.",
                    root.scanner.Pos {
                        line: self.lines[i].line,
                        col: indent + 1,
                    },
                );
            }
            self.parse_statement(block_indent);
        }
    }

    /// Parse one statement starting at `self.idx` (indented at `indent`),
    /// consuming any continuation lines and its child block.
    function parse_statement(self, indent: int) -> void {
        let start = self.idx;
        let line_no = self.lines[start].line;
        self.pad_to(line_no);

        // --- comments -----------------------------------------------------
        let trimmed = root.std.trim_start(self.lines[start].content);
        if (trimmed.starts_with("//")) {
            // Silent comment: drop it and any deeper-indented continuation
            // block (which is also silent).
            self.idx += 1;
            self.consume_child_block(indent);
            return;
        }
        if (trimmed.starts_with("/*")) {
            self.parse_loud_comment(indent);
            return;
        }

        // A custom-property declaration (`--name: …`) takes its value verbatim
        // (a `//` is *not* a comment inside it), so handle it from the raw line
        // before the logical-line assembly strips silent comments.
        if (trimmed.starts_with("--")) {
            if (self.try_parse_custom_property_stmt(indent, line_no)) {
                return;
            }
        }

        // --- assemble the logical line (bracket / trailing-comma / `\`
        //     continuations) ---------------------------------------------
        let assembled = self.assemble_logical_line(indent);
        let logical = root.std.StrBuf.from(assembled._0);
        let child_indent = assembled._1;

        // (A leading `\` — the legacy `\:hover` form, which marks the line as a
        // SELECTOR rather than the old `:prop val` declaration syntax — stays
        // on the line for the parser to consume in indented mode, so the
        // selector keeps its own column. Dropping it here shifted every column
        // after it by one.)

        // The mixin shorthands (`=name` for `@mixin name`, `+name` for
        // `@include name`) are NOT rewritten: expanding them would shift every
        // column after the keyword, and the SCSS parser reads them directly in
        // indented mode. The line analysis below maps them to the directives
        // they stand for (see `directive_name`).

        // A directive whose prelude is grammatically incomplete at the end of
        // its line continues onto the next (deeper-indented) line(s) — the
        // newline acts as whitespace inside the prelude. The remaining
        // deeper-indented lines after the prelude completes are its body.
        self.extend_directive_prelude(logical, line_no);

        // (Unquoted `@import` URLs — `@import foo, sub/bar` — are accepted by
        // the SCSS parser in indented mode, so the line stays as written and
        // the URL's diagnostic span is the bare token's.)

        // The statement keyword decides whether a `;` or a `{ … }` block is
        // appropriate, and handles custom props.
        self.emit_statement(logical.as_str(), child_indent, indent, line_no)
    }

    /// Consume (discard) a child block deeper than `indent` — used for silent
    /// comments, whose nested lines are also part of the comment.
    function consume_child_block(self, indent: int) -> void {
        while let i: int = self.next_nonblank(self.idx) {
            if (self.lines[i].indent <= indent) {
                break;
            }
            self.idx = i + 1;
        }
    }

    /// A loud `/* … */` comment statement. It may close on the same line, or
    /// span a deeper-indented block (whose lines become comment text). dart-sass
    /// collapses such a block to ` <text>` joined by spaces.
    function parse_loud_comment(self, indent: int) -> void {
        let start = self.idx;
        let line_no = self.lines[start].line;
        let content = root.std.trim_start(self.lines[start].content);
        // An open `#{` interpolation spans lines as expression whitespace, not
        // comment-line structure: join continuation lines verbatim until it
        // closes (`/* #{a` + `+ b} */` is one comment containing `#{a\n+ b}`).
        let first_line_end = start + 1;
        while (interp_open_anywhere(content) && first_line_end < self.lines.length()) {
            content = content + "\n";
            content = content + self.lines[first_line_end].indent_str;
            content = content + self.lines[first_line_end].content;
            first_line_end += 1;
        }
        // Does the comment terminate on the same line?
        let end = content.index_of("*/");
        if (end != null) {
            // Anything after the close (besides whitespace / another comment) is
            // an error in `.sass`.
            let after = root.std.trim_start(content.slice(end + 2, content.length()));
            if (after != "" && !after.starts_with("//") && !after.starts_with("/*")) {
                throw root.error.Error.at(
                    "expected expression.",
                    root.scanner.Pos {
                        line: line_no,
                        // PORT: Rust adds the BYTE offset of `*/` to the column.
                        col: indent + root.std.char_to_byte_offset(content, end) + 3,
                    },
                );
            }
            self.out.push_str(self.lines[start].indent_str);
            self.out.push_str(content.slice(0, end + 2));
            self.out.push("\n");
            self.idx = first_line_end;
            // A deeper-indented block after a closed comment is an error.
            let i = self.next_nonblank(self.idx);
            if (i != null) {
                if (self.lines[i].indent > indent) {
                    throw root.error.Error.at(
                        "This line was indented unexpectedly.",
                        root.scanner.Pos {
                            line: self.lines[i].line,
                            col: self.lines[i].indent + 1,
                        },
                    );
                }
            }
            return;
        }
        // Unterminated on this line: gather the deeper-indented block as
        // comment body. dart's `_loudComment` builds the text as `/*` + the
        // first content line (joined with one space, extra indentation beyond
        // `comment_col + 3` preserved), then `\n * ` per continuation line
        // with the same padding rule; its serializer then strips
        // `min(1, comment_col)` columns. The transform emits the
        // POST-STRIP form directly (the transformed SCSS places comments at
        // column 0, so the SCSS-side dedent is a no-op): gutter `* ` when the
        // comment was indented, ` * ` at the top level. Blank lines inside
        // the block become a bare gutter; trailing blanks after the block are
        // not part of it. Each entry is `(source_column, text)`; a blank line
        // has no entry text — modelled as None.
        let content_lines: root.std.Tuple2<int, string>?[] = [];
        // Line 0 content after the `/*` marker stays glued VERBATIM (dart
        // keeps `/**` and `/*  spaced` exactly as written); the sentinel
        // column marks it so the renderer skips the source-column padding.
        // Dropped if only whitespace.
        let first = root.std.strip_prefix(content, "/*") ?? content;
        if (root.std.trim(first) != "") {
            content_lines.push(root.std.Tuple2 { _0: root.std.INT_MAX(), _1: first });
        }
        self.idx = first_line_end;
        let closed = false;
        let pending_blanks = 0;
        while (self.idx < self.lines.length()) {
            let l = self.lines[self.idx];
            if (root.std.trim(l.content) == "") {
                pending_blanks += 1;
                self.idx += 1;
                continue;
            }
            if (l.indent <= indent) {
                break;
            }
            // Flush blanks only between block lines (a blank run *inside* the
            // comment renders as ` *` lines).
            for (let _k in baml.iter.Range.new(0, pending_blanks)) {
                content_lines.push(null);
            }
            pending_blanks = 0;
            // Keep the line's trailing whitespace: dart-sass preserves it inside
            // a loud comment body (`/* \n  a \n  */` -> `/* a \n * */`, the space
            // after `a` is retained). Only leading indentation is normalized,
            // via the source-column padding below.
            let body = l.content;
            content_lines.push(root.std.Tuple2 { _0: l.indent, _1: body });
            self.idx += 1;
            if (body.includes("*/")) {
                closed = true;
                break;
            }
        }
        // dart drops blank lines between a BARE `/*` and the comment's first
        // text (`/*` + blank + `  a` renders as `/* a */`), while a blank
        // BETWEEN two body lines is kept. Without this the renderer's first
        // entry was a blank, so the `/*` opener was never emitted at all and
        // the reconstruction was not valid SCSS.
        while (content_lines.length() > 0 && content_lines[0] == null) {
            let _ = content_lines.remove_at(0);
        }
        if (content_lines.length() == 0) {
            content_lines.push(root.std.Tuple2 { _0: 3, _1: "" });
        }
        if (!closed) {
            // dart-sass auto-closes an unterminated loud comment at the end of
            // its block, appending ` */` to the last line.
            if let last: root.std.Tuple2<int, string> = content_lines.at(content_lines.length() - 1) {
                if (last._1 == "") {
                    last._1 = "*/";
                } else {
                    last._1 = last._1 + " */";
                }
            }
        }
        // Post-strip gutter: dart's raw text always uses ` * `, and its
        // serializer strips `min(1, comment_col)` — so an indented comment
        // loses the gutter's leading space while a top-level one keeps it.
        let gutter = if (indent == 0) {
            " * "
        } else {
            "* "
        };
        let i = 0;
        for (let line in content_lines) {
            if (i == 0) {
                // The comment opens at its source column (the SCSS-side
                // dedent of `min(1, comment_col)` then matches dart's).
                self.out.push_str(self.lines[start].indent_str);
            }
            match (line) {
                // The first-line remainder rides verbatim behind `/*`.
                let t: root.std.Tuple2<int, string> if t._0 == root.std.INT_MAX() => {
                    self.out.push_str("/*");
                    self.out.push_str(t._1);
                },
                let t: root.std.Tuple2<int, string> => {
                    // Extra indentation beyond `comment_col + 3` is content
                    // (dart pads for `3 .. current - parent`).
                    let pad = root.std.saturating_sub_u(root.std.saturating_sub_u(t._0, indent), 3);
                    if (i == 0) {
                        self.out.push_str("/* ");
                    } else {
                        self.out.push_str(gutter);
                    }
                    for (let _k in baml.iter.Range.new(0, pad)) {
                        self.out.push(" ");
                    }
                    self.out.push_str(t._1);
                },
                null => {
                    self.out.push_str(root.std.trim_end(gutter));
                },
            }
            self.out.push("\n");
            i += 1;
        }
    }

    /// Assemble a logical line from `self.idx`, consuming bracket / trailing
    /// comma / backslash continuations. Returns the joined content and the
    /// indentation a child block (if any) must exceed (always the statement's
    /// own `indent`). Leaves `self.idx` past the last consumed continuation
    /// line. Errors on tab/space indentation mixing within the continuation.
    function assemble_logical_line(self, indent: int) -> root.std.Tuple2<string, int> {
        let start = self.idx;
        let logical = strip_statement_comment(root.std.trim_start(self.lines[start].content));
        self.idx = start + 1;
        // A trailing `,` continues the line only in a selector context — a bare
        // declaration value (`b: c,`) does *not* wrap onto the next line in the
        // indented syntax. A directive prelude handles its own continuation
        // later, so a trailing comma there is also not consumed here.
        // A declaration colon is followed by whitespace; a selector pseudo's
        // colon is glued to its name — dart continues `&:active,`,
        // `a::-webkit-x,` and even `b:c,` as selector lists (quasar's
        // normalize.sass), so only a whitespace-followed colon blocks it.
        let comma_continues = !logical.starts_with("@")
            && !logical.starts_with("$")
            && (
                match (find_decl_colon(logical)) {
                    null => true,
                    let c: int => !root.std.is_whitespace(logical.at(c + 1)),
                }
            );
        // A *declaration value* mid-expression continues on a trailing binary
        // operator (`b: 3 %` + `2` is the modulo `3 % 2`).
        let op_continues = !logical.starts_with("@") && !logical.starts_with("$") && find_decl_colon(logical) != null;
        while (true) {
            if (
                continuation_pending(logical, comma_continues)
                    || (op_continues && ends_with_value_operator(logical))
            ) {
                // Need a following line to continue. Continuations join the
                // *immediate next physical line* (dart-sass does not skip blanks
                // here).
                if (self.idx >= self.lines.length()) {
                    break;
                }
                let next_content = self.lines[self.idx].content;
                let next_indent_str = self.lines[self.idx].indent_str;
                let st = scan_state(logical);
                // Inside an open interpolation, loud comment, string or
                // `url(…)`, the next line's text is captured verbatim (a `//`
                // there is not a comment).
                let verbatim = st.in_interp || st.in_loud_comment || st.in_string || st.in_url;
                if (root.std.trim(next_content) == "") {
                    if (st.bracket_depth > 0 || verbatim) {
                        // A blank line inside brackets/interp/comment joins as a
                        // newline.
                        logical = logical + "\n";
                        self.idx += 1;
                        continue;
                    }
                    break;
                }
                let joined = if (verbatim) {
                    next_content
                } else {
                    strip_silent_comment(next_content)
                };
                // A trailing backslash pulls the next line in, and the pair is
                // kept VERBATIM — backslash, line break and the next line's own
                // indentation. Inside a quoted string that is a CSS line
                // continuation, which means the same thing written either way
                // (both vanish, and the indentation stays content) while leaving
                // every token on the line it was written on. ANYWHERE ELSE dart
                // rejects it — `escape()` fails on a newline — so the pair has
                // to reach the parser for it to say so, at the column it is
                // written; collapsing the line into a space made `b: c\` +
                // `d` compile as `b: c d`.
                if (logical.ends_with("\\")) {
                    logical = logical + "\n";
                    logical = logical + next_indent_str;
                    logical = logical + joined;
                } else {
                    // Bracket / trailing-comma / interp / comment continuation:
                    // preserve the newline and the line's original indentation so
                    // the SCSS parser sees the same whitespace as dart-sass.
                    logical = logical + "\n";
                    logical = logical + next_indent_str;
                    logical = logical + joined;
                }
                self.idx += 1;
                continue;
            }
            break;
        }
        root.std.Tuple2 { _0: logical, _1: indent }
    }

    /// While the directive prelude in `logical` is grammatically incomplete,
    /// pull in the next deeper-indented line(s) as prelude continuation. A
    /// newline acts as whitespace inside a directive prelude, so a directive may
    /// span several indented lines before its body block (which is whatever
    /// deeper-indented lines remain afterwards).
    function extend_directive_prelude(self, logical: root.std.StrBuf, start_line: int) -> void {
        if (!prelude_can_span(logical.as_str())) {
            return;
        }
        while (prelude_incomplete(logical.as_str())) {
            // An incomplete prelude consumes the next non-blank line regardless
            // of its indentation: a newline acts as whitespace inside a prelude,
            // so the expression/clause grammar keeps reading until satisfied.
            let i = self.next_nonblank(self.idx);
            if (i == null) {
                break;
            }
            let piece = strip_silent_comment(root.std.trim_start(self.lines[i].content));
            let line = self.lines[i].line;
            let indent_str = self.lines[i].indent_str;
            self.idx = i + 1;
            if (piece == "") {
                continue;
            }
            join_continuation(logical, start_line, line, indent_str, piece);
            // Pull in any bracket continuations of this new line too (a
            // trailing comma only continues a `@use`/`@forward` member list).
            let comma_continues = match (directive_name(logical.as_str())) {
                "use" | "forward" => true,
                _ => false,
            };
            while (continuation_pending(logical.as_str(), comma_continues)) {
                let j = self.next_nonblank(self.idx);
                if (j == null) {
                    break;
                }
                let cont = strip_silent_comment(root.std.trim_start(self.lines[j].content));
                let line = self.lines[j].line;
                let indent_str = self.lines[j].indent_str;
                self.idx = j + 1;
                join_continuation(logical, start_line, line, indent_str, cont);
            }
        }
    }

    /// Parse the child block of the statement that begins at `self.idx`'s
    /// previous position; statements indented strictly deeper than `indent`
    /// form the block. Returns whether a block was found.
    function parse_child_into_braces(self, indent: int) -> bool {
        let i = self.next_nonblank(self.idx);
        if (i == null) {
            return false;
        }
        let child_indent = self.lines[i].indent;
        if (child_indent <= indent) {
            return false;
        }
        self.out.push_str(" {\n");
        self.idx = i;
        self.parse_block(child_indent, indent);
        // The `}` rides on the block's last output line: a `.sass` block has
        // no closing line of its own, and dart's rule span ends with its last
        // child. (An all-silent block leaves ` {` alone: `a { }`.)
        if (self.out.ends_with("\n")) {
            let _ = self.out.pop();
            // That newline may already have been counted by `pad_to` — it is,
            // whenever the block's last statement emitted nothing (a silent
            // comment). Un-count it, or every following statement lands a line
            // early.
            if (self.scanned > self.out.len()) {
                self.out_lines -= 1;
                self.scanned = self.out.len();
            }
        }
        self.out.push_str(" }\n");
        true
    }

    /// The indentation characters of source line `line_no` (1-based).
    function indent_str_for(self, line_no: int) -> string {
        let l = self.lines.at(root.std.saturating_sub_u(line_no, 1));
        if (l != null) {
            l.indent_str
        } else {
            ""
        }
    }

    /// Emit one statement (already assembled into `logical`), attaching its
    /// child block if present.
    function emit_statement(
        self,
        logical: string,
        unused_child_indent: int,
        indent: int,
        line_no: int,
    ) -> void {
        logical = root.std.trim(logical);

        // A single trailing `;` ends a statement and is tolerated; a `;` with
        // further (non-comment) content after it means two statements share a
        // line, which the indented syntax forbids. An explicit trailing `;`
        // also means "no block" — even an otherwise block-owning directive
        // (`@a b;`) is then a leaf statement.
        let explicit_semicolon = false;
        let semi = find_top_level_semicolon(logical);
        if (semi != null) {
            // A trailing loud comment after the `;` is tolerated and dropped
            // (`b: c; /* f */`); anything else is two statements on a line.
            let rest = logical.slice(semi + 1, logical.length());
            let after = trim_trailing_loud_comments(root.std.trim(rest));
            if (after != "") {
                // dart carets the SECOND statement — the first character after
                // the `;` and the whitespace following it — not the `;` itself.
                // A logical line can span several source lines (a bracket
                // continuation keeps its line breaks), so the position is
                // counted from the last one, whose own indentation is already
                // part of `logical`.
                let skipped = rest.length() - root.std.trim_start(rest).length();
                let prefix = logical.slice(0, semi + 1 + skipped);
                let line_col = match (prefix.last_index_of("\n")) {
                    let nl: int => {
                        root.std.Tuple2 {
                            _0: line_no + (prefix.split("\n").length() - 1),
                            _1: prefix.slice(nl + 1, prefix.length()).length() + 1,
                        }
                    },
                    null => root.std.Tuple2 { _0: line_no, _1: indent + prefix.length() + 1 },
                };
                throw root.error.Error.at(
                    "multiple statements on one line are not supported in the indented syntax.",
                    root.scanner.Pos { line: line_col._0, col: line_col._1 },
                );
            }
            // Drop the harmless trailing `;` (the transform re-adds the right
            // terminator).
            logical = root.std.trim_end(logical.slice(0, semi));
            explicit_semicolon = true;
        }

        // A leaf directive (e.g. `@import`, `@return`, `@extend`, `@charset`)
        // may not have anything indented beneath it.
        let name = forbids_indented_child(logical);
        if (name != null) {
            let i = self.next_nonblank(self.idx);
            if (i != null) {
                if (self.lines[i].indent > indent) {
                    throw root.error.Error.at(
                        `Nothing may be indented beneath a @${name} rule.`,
                        root.scanner.Pos {
                            line: self.lines[i].line,
                            col: self.lines[i].indent + 1,
                        },
                    );
                }
            }
        }

        // Whether this logical line wants a brace block (a rule / directive) or
        // a `;` terminator (a declaration / leaf directive) is decided after we
        // know whether a child block follows. We emit the prelude, then either a
        // block or — when no child block follows — the empty form appropriate to
        // the statement kind (an empty `{}` for block constructs, `;` otherwise).
        // A declaration WITH a value whose child block contains a line that
        // is not itself a `prop: value` declaration is dart-sass's
        // "expected \":\"." error (nested properties only) — e.g.
        // `b: c,` followed by a deeper-indented bare `d`.
        let is_decl_with_value = !logical.starts_with("@")
            && !logical.starts_with("$")
            && !logical.starts_with("--")
            && (
                match (find_decl_colon(logical)) {
                    let c: int => {
                        let after = logical.slice(c + 1, logical.length());
                        root.std.is_whitespace(after.at(0)) && root.std.trim(after) != ""
                    },
                    null => false,
                }
            );
        if (is_decl_with_value) {
            let i = self.next_nonblank(self.idx);
            if (i != null) {
                if (self.lines[i].indent > indent) {
                    let child_indent = self.lines[i].indent;
                    let j = i;
                    while (j < self.lines.length()) {
                        let l = self.lines[j];
                        if (root.std.trim(l.content) == "") {
                            j += 1;
                            continue;
                        }
                        if (l.indent < child_indent) {
                            break;
                        }
                        if (l.indent == child_indent) {
                            let t = root.std.trim_start(l.content);
                            if (
                                !t.starts_with("//")
                                    && !t.starts_with("/*")
                                    && find_decl_colon(t) == null
                            ) {
                                throw root.error.Error.at(
                                    "expected \":\".",
                                    root.scanner.Pos {
                                        line: l.line,
                                        col: root.std.trim_end(l.content).length() + 1,
                                    },
                                );
                            }
                        }
                        j += 1;
                    }
                }
            }
        }
        // Inside a plain-CSS custom callable body, a literal `result`
        // declaration may not have an indented child block (an interpolated
        // `#{result}:` follows the ordinary nested-property rules instead).
        if (self.in_css_callable && !logical.includes("#{")) {
            let colon = find_decl_colon(logical);
            if (colon != null) {
                if (root.std.eq_ignore_ascii_case(root.std.trim(logical.slice(0, colon)), "result")) {
                    let i = self.next_nonblank(self.idx);
                    if (i != null) {
                        if (self.lines[i].indent > indent) {
                            throw root.error.Error.at(
                                "Nothing may be indented beneath a @function result.",
                                root.scanner.Pos {
                                    line: self.lines[i].line,
                                    col: self.lines[i].indent + 1,
                                },
                            );
                        }
                    }
                }
            }
        }
        // Keep the source indentation so every column the SCSS parser
        // reports is the `.sass` column.
        self.out.push_str(self.indent_str_for(line_no));
        self.out.push_str(logical);
        // A `@function --x()`/`@mixin --x()` body is a plain-CSS custom
        // callable; flag it for the `result` child check above.
        // The keyword may be escaped (`@fu\6e ction`), so the name after it is
        // found with the same decoder `directive_name` uses — a raw
        // identifier-character strip would stop at the backslash and miss the
        // `--`, letting a `result:` child through that dart rejects.
        let is_callable_kw = match (directive_name(logical)) {
            "function" | "mixin" => true,
            _ => false,
        };
        // PORT: `a && { block }` -> `if (a) { block } else { false }`.
        let css_callable = if (is_callable_kw) {
            let after_sigil = root.std
                .trim_start_by(root.std.trim_start(logical), (c: string) -> bool {
                    c == "@" || c == "="
                })
                .chars();
            let decoded = root.parser.decode_ident(after_sigil, 0);
            let end = decoded._1;
            root.std.trim_start(root.std.concat(after_sigil.slice(end, after_sigil.length())))
                .starts_with("--")
        } else {
            false
        };
        let saved_callable = self.in_css_callable;
        if (css_callable) {
            self.in_css_callable = true;
        }
        let had_block = self.parse_child_into_braces(indent);
        self.in_css_callable = saved_callable;
        if (!had_block) {
            let form: EmptyForm = if (explicit_semicolon) {
                EmptyForm.Semicolon
            } else {
                empty_form(logical)
            };
            match (form) {
                EmptyForm.Braces => self.out.push_str(" {}\n"),
                EmptyForm.Semicolon => self.out.push_str(";\n"),
            }
        }
    }

    /// Parse a custom-property declaration (`--name: value`) from the raw lines
    /// starting at `self.idx`. The value is captured verbatim — a `//` is not a
    /// comment inside it, and a deeper-indented child block continues the value
    /// — and emitted as an SCSS custom declaration. Returns `Some(())` when the
    /// line really is a custom property; otherwise leaves `self.idx` untouched
    /// and returns `None` so normal statement handling proceeds.
    // PORT: `Result<Option<()>, Error>` -> `bool` (`Some(())` is `true`).
    function try_parse_custom_property_stmt(self, indent: int, unused_line_no: int) -> bool {
        let start = self.idx;
        let raw = root.std.trim_start(self.lines[start].content);
        // Confirm a top-level colon follows the `--name` token.
        let colon = find_decl_colon(raw);
        if (colon == null) {
            return false;
        }
        let name = root.std.trim_end(raw.slice(0, colon));
        if (
            !name.starts_with("--")
                || name.length() < 2
                || root.std.any_char(name, (c: string) -> bool {
                    c.is_whitespace()
                })
        ) {
            return false;
        }
        self.idx = start + 1;
        // The text after the colon is kept VERBATIM, leading whitespace and
        // all: a custom property's value is not re-serialized, so `--v:1px`
        // must stay `--v:1px` (dart emits no space there, while it collapses a
        // run of them to one — the rule the shared parser already applies).
        let value = raw.slice(colon + 1, raw.length());
        // Only an *open* bracket (`(`/`[`/`{`) or `#{` interpolation continues
        // the value onto following lines (verbatim, preserving each line's
        // source indentation); otherwise nothing may be indented beneath a
        // custom property (dart-sass error).
        while (custom_value_open(value) && self.idx < self.lines.length()) {
            let l = self.lines[self.idx];
            value = value + "\n";
            value = value + l.indent_str;
            value = value + l.content;
            self.idx += 1;
        }
        let i = self.next_nonblank(self.idx);
        if (i != null) {
            if (self.lines[i].indent > indent) {
                throw root.error.Error.at(
                    "Nothing may be indented beneath a custom property.",
                    root.scanner.Pos {
                        line: self.lines[i].line,
                        col: self.lines[i].indent + 1,
                    },
                );
            }
        }
        // Keep the original indentation in the transpiled line: the name's
        // source column caps the re-indentation strip of a multi-line value
        // (dart _writeReindentedValue), so it must survive the SCSS re-parse.
        self.out.push_str(self.lines[start].indent_str);
        // Everything up to the colon is emitted as written — whitespace BEFORE
        // it included, or the value would start a column early (`--v : 1px`).
        self.out.push_str(raw.slice(0, colon));
        self.out.push(":");
        self.out.push_str(root.std.trim_end(value));
        self.out.push_str(";\n");
        true
    }
}

/// Whether `c` may appear in an identifier (mirrors the SCSS parser; any
/// non-ASCII code point is a valid identifier char like dart `isName`).
function is_ident_char(c: string) -> bool {
    c.is_ascii_alphanumeric() || c == "-" || c == "_" || root.std.ord(c) >= 0x80
}

/// Append a prelude continuation line to `logical` at the position it occupies
/// in the source: one newline per source line crossed (so a blank line between
/// them survives), then the line's own indentation, then its text.
///
/// A newline is whitespace inside a directive prelude, so the grammar reads the
/// same text either way — but joining with a SPACE would put every token of the
/// continuation on the statement's first line, and an error in one
/// (`@each $a in` / `  $undef`) would be reported there rather than on its own
/// line, where dart reports it.
function join_continuation(
    logical: root.std.StrBuf,
    start_line: int,
    line: int,
    indent_str: string,
    piece: string,
) -> void {
    let end_line = start_line + (logical.as_str().split("\n").length() - 1);
    if (line > end_line) {
        for (let _k in baml.iter.Range.new(end_line, line)) {
            logical.push("\n");
        }
        logical.push_str(indent_str);
    } else if (!logical.is_empty() && !root.std.is_whitespace(logical.last_char())) {
        // A continuation that does not advance a line (it never should) still
        // needs the whitespace the newline would have provided.
        logical.push(" ");
    }
    logical.push_str(piece);
}

/// The number of backslashes a line ends with: an odd count means the last one
/// escapes whatever comes next, which is the line break.
function trailing_backslashes(s: string) -> int {
    // PORT: `chars().rev().take_while(..).count()` -> a backwards index loop.
    let cs = s.chars();
    let n = 0;
    let j = cs.length() - 1;
    while (j >= 0 && cs[j] == "\\") {
        n += 1;
        j -= 1;
    }
    n
}

/// Whether an UNESCAPED identifier is a `url` function name — `url` itself or
/// a vendor-prefixed `-x-url` — compared in place, without building a `String`
/// (the allocation-free twin of [`crate::parser::is_url_function`], which the
/// escaped path still uses).
function plain_name_is_url(cs: string[]) -> bool {
    if (plain_name_is_url__is_url(cs)) {
        return true;
    }
    // `-x-url`: a leading `-`, at least one inner character, then a second `-`.
    if (cs.at(0) == "-") {
        let rel = cs.slice(1, cs.length()).find_index((c: string) -> bool {
            c == "-"
        });
        if (rel != null) {
            if (rel >= 1) {
                return plain_name_is_url__is_url(cs.slice(1 + rel + 1, cs.length()));
            }
        }
    }
    false
}

/// Nested `fn is_url` of [`plain_name_is_url`].
function plain_name_is_url__is_url(cs: string[]) -> bool {
    cs.length() == 3
        && root.std.eq_ignore_ascii_case(cs[0], "u")
        && root.std.eq_ignore_ascii_case(cs[1], "r")
        && root.std.eq_ignore_ascii_case(cs[2], "l")
}

/// The lowercased directive keyword of a logical line (`@for` -> `"for"`), or
/// `None` if the line is not an at-rule.
///
/// The indented syntax's mixin shorthands answer with the directive they stand
/// for: `=name` is `@mixin name` and `+name` is `@include name`. They keep
/// their own spelling in the transpiled SCSS — rewriting them would shift the
/// columns of everything after the keyword, and a mixin's arguments must keep
/// their `.sass` positions — so this is where the rest of the line analysis
/// learns what they are. A bare `=` still reads as `@mixin` (it continues onto
/// the next line like the directive it stands for); a bare `+` does NOT, since
/// `+ a` is the next-sibling combinator, a selector.
function directive_name(logical: string) -> string? {
    let t = root.std.trim_start(logical);
    if (t.starts_with("=")) {
        return "mixin";
    }
    if let after: string = root.std.strip_prefix(t, "+") {
        let c = root.std.first_char(after);
        let starts_ident = if (c != null) {
            is_ident_char(c) || c == "#" || c == "\\"
        } else {
            false
        };
        return if (starts_ident) {
            "include"
        } else {
            null
        };
    }
    let rest = root.std.strip_prefix(t, "@");
    if (rest == null) {
        return null;
    }
    // The keyword may be spelled with CSS escapes — the parser decodes them
    // (`@im\70ort` IS `@import`), so the line analysis has to as well, or a
    // directive would be taken for an unknown at-rule.
    let cs = rest.chars();
    let name = root.parser.decode_ident(cs, 0)._0;
    if (name == "") {
        null
    } else {
        root.std.ascii_lower(name)
    }
}

/// Whether a statement's prelude may span multiple lines (the prelude is an
/// expression / structured clause that the indented parser reads with the real
/// grammar, treating newlines as whitespace). True for the expression-bearing
/// directives and for `$variable` declarations.
function prelude_can_span(logical: string) -> bool {
    if (root.std.trim_start(logical).starts_with("$")) {
        return true;
    }
    match (directive_name(logical)) {
        "for"
            | "each"
            | "if"
            | "else"
            | "while"
            | "function"
            | "mixin"
            | "include"
            | "return"
            | "warn"
            | "debug"
            | "error"
            | "extend"
            | "use"
            | "forward"
            | "at-root"
            | "content" =>
        {
            true
        },
        _ => false,
    }
}

/// If `logical` is a leaf directive that forbids anything indented beneath it,
/// return its keyword (without the `@`). dart-sass: `@import`, `@charset`,
/// `@return`, `@extend`, `@error`, `@warn`, `@debug` and `@content` take no
/// child block. (`@use`/`@forward` permit a continued prelude, handled
/// separately, but no body either.)
function forbids_indented_child(logical: string) -> string? {
    match (directive_name(logical)) {
        let name: string
            if name == "import"
            || name == "charset"
            || name == "return"
            || name == "extend"
            || name == "error"
            || name == "warn"
            || name == "debug"
            || name == "content"
            || name == "use"
            || name == "forward" => name,
        _ => null,
    }
}

/// Whether `c` is an operator/structural character that, when it ends a prelude
/// line, demands a following operand (so the prelude continues).
function ends_with_pending_operator(t: string) -> bool {
    t = root.std.trim_end(t);
    // A trailing comma does NOT continue a directive prelude or variable
    // declaration in the indented syntax (`@each $a in b,` iterates the
    // single-element list `(b,)`; `$a: 1,` + indented line is "Nothing may
    // be indented beneath a variable declaration."). Only selector lists
    // continue on a comma, handled in `assemble_logical_line`.
    if (t.ends_with("\\")) {
        return true;
    }
    // `@use "x" as *` / `@forward "x" as *`: the wildcard namespace ends the
    // directive — this `*` is not a pending multiplication (vuetify's
    // `@use '../settings' as *` must not swallow the next line).
    if (t.ends_with("as *")) {
        return false;
    }
    // Trailing binary/relational/arithmetic operators.
    for (let op in ["+", "-", "*", "/", "%", "<", ">", "=", ":"]) {
        if (t.ends_with(op)) {
            return true;
        }
    }
    // Trailing keyword that requires more (case-insensitive whole word).
    // PORT: `chars().rev().take_while(is_ident_char)` reversed back -> the
    // suffix after a backwards index scan.
    let tcs = t.chars();
    let k = tcs.length();
    while (k > 0 && is_ident_char(tcs[k - 1])) {
        k -= 1;
    }
    let last_word = t.slice(k, tcs.length());
    match (root.std.ascii_lower(last_word)) {
        "from"
            | "through"
            | "to"
            | "in"
            | "and"
            | "or"
            | "not"
            | "using"
            | "as"
            | "with"
            | "show"
            | "hide"
            | "if" =>
        {
            true
        },
        _ => false,
    }
}

/// Whether a directive prelude (the whole logical line so far) is grammatically
/// incomplete and therefore continues onto the next indented line.
function prelude_incomplete(logical: string) -> bool {
    // An unbalanced bracket always continues.
    if (bracket_depth(logical) > 0) {
        return true;
    }
    // A `$variable` declaration continues until it has `$name: <value>` with a
    // non-empty value (`$a:` and `$a` both continue; `$a: b` is complete).
    let t = root.std.trim_start(logical);
    if (t.starts_with("$")) {
        if (ends_with_pending_operator(t)) {
            return true;
        }
        return match (find_decl_colon(t)) {
            let colon: int => root.std.trim(t.slice(colon + 1, t.length())) == "",
            null => true,
        };
    }
    let name = directive_name(logical);
    if (name == null) {
        return false;
    }
    // The prelude text after the directive keyword. A shorthand has no
    // keyword to strip — everything after `=`/`+` is the prelude, so a mixin
    // named `mixin` (`=mixin`) keeps its name rather than reading as empty.
    let t = root.std.trim_start(logical);
    let after_sigil = t.slice(1, t.length()); // skip `@`, `=` or `+`
    let prelude = if (t.starts_with("=") || t.starts_with("+")) {
        root.std.trim(after_sigil)
    } else {
        // The keyword may be ESCAPED, in which case the raw spelling does not
        // start with the decoded name — `@us\65` would leave `us\65` as the
        // prelude, so `@use` spanning lines (`@use` + an indented url, which
        // dart accepts) looked complete and the url was rejected as an
        // indented child. Take the text after the decoded identifier instead.
        let cs = after_sigil.chars();
        let end = root.parser.decode_ident(cs, 0)._1;
        let owned = root.std.concat(cs.slice(end, cs.length()));
        root.std.trim(owned)
    };
    if (ends_with_pending_operator(prelude)) {
        return true;
    }
    // A prelude that spans lines carries newlines and indentation between its
    // tokens; the keyword tests below look for ` in `, ` from `, ` if ` with
    // single spaces, so compare against a whitespace-normalized copy.
    prelude
        = if (prelude.includes("\n")) {
            root.std.split_whitespace(prelude).join(" ")
        } else {
            prelude
        };
    match (name) {
        // `@for $i from <a> (through|to) <b>` — incomplete until both the
        // `from`/`through`/`to` keywords and operands are present.
        "for" => {
            let lower = root.std.ascii_lower(prelude);
            // Need the variable, `from`, an operand, `through`/`to`, an operand.
            if (!lower.includes(" from ") && !lower.ends_with(" from")) {
                // No `from` yet — but `@for $i` alone should continue.
                return !lower.includes("from");
            }
            // Have `from`; need `through`/`to` with an operand after it.
            let has_bound = lower.includes(" through ") || lower.includes(" to ");
            !has_bound
        },
        // `@each $v[, $k] in <list>` — incomplete until ` in ` appears.
        "each" => {
            let lower = root.std.ascii_lower(prelude);
            !(lower.includes(" in ") || lower.ends_with(" in"))
        },
        // `@if`/`@while`/`@else if` need a non-empty condition.
        "if" | "while" => prelude == "",
        "else" => {
            // `@else` is complete; `@else if` (no condition yet) needs more.
            let lower = root.std.ascii_lower(prelude);
            lower == "if" || lower.ends_with(" if")
        },
        // `@function`/`@mixin` need a name (and balanced parens if any).
        "function" | "mixin" => prelude == "",
        // `@return`/`@warn`/`@debug`/`@error`/`@extend` need an expression.
        "return" | "warn" | "debug" | "error" | "extend" => prelude == "",
        // `@include` needs a name.
        "include" => prelude == "",
        // `@use`/`@forward` member lists (`show a,`) continue on a comma —
        // their preludes treat newlines as whitespace throughout.
        "use" | "forward" if prelude.ends_with(",") => true,
        // `@use`/`@forward`/`@import` need a URL.
        "use" | "forward" | "import" => prelude == "",
        _ => false,
    }
}

/// Which empty form a child-less statement takes in the reconstructed SCSS.
enum EmptyForm {
    /// A block construct with no body: append ` {}` (style rules, `@function`,
    /// `@mixin`, `@if`/`@else`, `@each`/`@for`/`@while`, `@media`, `@supports`,
    /// `@at-root`, `@keyframes`, generic block at-rules).
    Braces,
    /// A leaf statement: append `;` (declarations, variables, `@return`,
    /// `@include` without content, `@import`/`@use`/`@forward`/`@extend`,
    /// `@content`, `@warn`/`@debug`/`@error`, `@charset`, …).
    Semicolon,
}

/// Classify the empty (child-less) form of a statement from its logical line.
///
/// dart-sass: directives that own a block always parse a block (even an empty
/// one) in `.sass`; leaf directives and declarations end at the newline. A line
/// without a directive keyword is a style rule (`{}`) unless it is a declaration
/// (`prop: value`), in which case it is a leaf (`;`).
function empty_form(logical: string) -> EmptyForm {
    let t = root.std.trim_start(logical);
    // An at-rule — or a mixin shorthand, which stands for one. An `@` whose
    // name is interpolated (`@#{$x} foo`) has no keyword and falls to the
    // generic arm, as before.
    if (t.starts_with("@") || directive_name(t) != null) {
        let name = directive_name(t) ?? "";
        return match (name) {
            // Block-owning directives.
            "function"
                | "mixin"
                | "if"
                | "else"
                | "each"
                | "for"
                | "while"
                | "media"
                | "supports"
                | "at-root"
                | "keyframes"
                | "-webkit-keyframes"
                | "-moz-keyframes"
                | "-o-keyframes"
                | "-ms-keyframes" =>
            {
                EmptyForm.Braces
            },
            // Leaf directives. `@include` without a child content block ends at
            // the newline (a child block, if present, is its content) — unless
            // it carries a `using (…)` clause, which always takes a content
            // block (empty here), since SCSS `@include a() using ();` is
            // 'expected "{".'.
            "include" if has_top_level_using(t) => EmptyForm.Braces,
            "include"
                | "return"
                | "import"
                | "use"
                | "forward"
                | "extend"
                | "content"
                | "warn"
                | "debug"
                | "error"
                | "charset" =>
            {
                EmptyForm.Semicolon
            },
            // Unknown / generic at-rules (`@font-face`, `@page`, `@namespace`,
            // vendor `@-foo`, …) are statements when nothing is indented beneath
            // them (`@namespace url(x)` -> `@namespace url(x);`); a child block,
            // when present, is handled before this point.
            _ => EmptyForm.Semicolon,
        };
    }
    // A `$variable: …` declaration is a leaf.
    if (t.starts_with("$")) {
        return EmptyForm.Semicolon;
    }
    // Otherwise: a declaration (`prop: value`) is a leaf; a bare selector is a
    // style rule. A top-level `:` with a non-empty value -> declaration.
    let colon = find_decl_colon(t);
    if (colon != null) {
        let value = root.std.trim(t.slice(colon + 1, t.length()));
        // `prop:` with empty value is a nested property set (a block); `prop: v`
        // is a declaration (leaf). `a:hover` (no whitespace, has a value) reads
        // as a selector in SCSS but here we have no child block, so it is a
        // child-less rule -> braces. Distinguish by whitespace after the colon.
        let after = t.slice(colon + 1, t.length());
        let ws_after = root.std.is_whitespace(after.at(0)) || after == "";
        if (value == "") {
            // `prop:` alone with no block is an empty declaration value.
            return EmptyForm.Semicolon;
        }
        if (ws_after) {
            return EmptyForm.Semicolon;
        }
        // `a:hover` style with no block -> style rule.
        return EmptyForm.Braces;
    }
    EmptyForm.Braces
}

/// Whether a logical line, as assembled so far, needs another physical line to
/// continue: an unbalanced bracket, an unterminated `#{…}` interpolation or
/// `/* … */` loud comment, or a trailing `,` or `\`.
function continuation_pending(s: string, comma_continues: bool) -> bool {
    let st = scan_state(s);
    if (st.bracket_depth > 0 || st.in_interp || st.in_loud_comment) {
        return true;
    }
    // Trailing complete loud comments are invisible to continuation
    // detection (`a, /* c */` still continues the selector list).
    let t = trim_trailing_loud_comments(s);
    if (t.ends_with("\\")) {
        return true;
    }
    // A trailing `!` awaits its `important` keyword on the next line
    // (`b: c!` + `important` joins; dart errors `Expected "important".`
    // when the next line is something else, which the joined SCSS parse
    // reproduces).
    if (t.ends_with("!")) {
        return true;
    }
    comma_continues && t.ends_with(",")
}

/// A single-pass cursor over a `.sass` logical line's chars.
///
/// The indented-syntax line analysis needs to scan a line while *skipping over*
/// quoted strings, `#{…}` interpolation and `/* … */` loud comments in eight
/// slightly different queries (top-level comma split, declaration `:`, statement
/// `;`, bracket depth, `@include … using`, …). The top-level dispatch differs
/// per query, but the three skip sub-loops — the byte-accounting,
/// escape-handling, brace-matching parts where bugs hide — are identical. This
/// cursor owns the one `Vec<char>` allocation and centralises those three
/// primitives. It tracks both a char index (`i`) and the matching byte offset
/// (`byte`) so byte-indexing callers (`find_decl_colon`,
/// `find_top_level_semicolon`, `strip_silent_comment`) and char-only callers
/// share one implementation.
class LineScanner {
    cs: string[],
    /// Char index of the cursor.
    i: int,
    /// Byte offset corresponding to `i` — maintained only for non-ASCII input
    /// (see [`LineScanner::offset`]); left at 0 on the common all-ASCII path,
    /// where the byte offset equals the char index.
    byte: int,
    /// Whether the line is pure ASCII (byte offset == char index, so the
    /// per-char `len_utf8` bookkeeping in [`bump`](Self::bump) is skippable).
    ascii: bool,

    function new(s: string) -> LineScanner {
        LineScanner { cs: s.chars(), i: 0, byte: 0, ascii: s.is_ascii() }
    }

    function done(self) -> bool {
        self.i >= self.cs.length()
    }

    /// The char under the cursor. Caller must ensure `!done()`.
    function cur(self) -> string {
        self.cs[self.i]
    }

    /// The char `k` positions ahead, or `None` past the end.
    function peek(self, k: int) -> string? {
        self.cs.at(self.i + k)
    }

    /// The byte offset of the cursor into the original `&str`. On all-ASCII
    /// input this is just the char index; otherwise it is the tracked sum.
    // PORT: offsets into a `str` are CHAR offsets in the port (guide §8) — the
    // callers slice with `string.slice` — so the offset is the char index on
    // every input. `byte` is still maintained by `bump`, as in Rust.
    function offset(self) -> int {
        self.i
    }

    /// Advance one char, keeping the byte offset in step (skipped on the
    /// all-ASCII fast path, where `offset()` reads the char index directly).
    function bump(self) -> void {
        if (!self.ascii) {
            self.byte += root.std.len_utf8(self.cs[self.i]);
        }
        self.i += 1;
    }

    /// At an opening quote: advance past the matching closing quote (honouring
    /// `\`-escapes), or to end-of-line if the string is unterminated. Returns
    /// `true` iff the string was terminated on this line.
    function skip_quoted(self) -> bool {
        let q = self.cur();
        self.bump(); // opening quote
        while (self.i < self.cs.length() && self.cs[self.i] != q) {
            // A backslash escapes the next char (which may be the quote).
            if (self.cs[self.i] == "\\" && self.i + 1 < self.cs.length()) {
                self.bump();
            }
            self.bump();
        }
        if (self.i < self.cs.length()) {
            self.bump(); // closing quote
            true
        } else {
            false
        }
    }

    /// At `#{`: advance past the brace-matched closing `}` (or to end-of-line).
    function skip_interp(self) -> void {
        self.bump(); // '#'
        self.bump(); // '{'
        let depth = 1;
        while (self.i < self.cs.length() && depth > 0) {
            match (self.cs[self.i]) {
                // A brace inside a STRING or behind an escape is not a
                // delimiter: `#{"} // not a comment"}` closes at its last
                // brace, and the `//` inside the string is value text. The
                // shared expression parser reads it that way, and so does dart.
                "\"" | "'" => {
                    let _ = self.skip_quoted();
                    continue;
                },
                "\\" => {
                    self.bump();
                    if (!self.done()) {
                        self.bump();
                    }
                    continue;
                },
                "{" => {
                    depth += 1;
                },
                "}" => {
                    depth -= 1;
                },
                _ => {},
            }
            self.bump();
        }
    }

    /// Whether a `url(` FUNCTION token's identifier covers the cursor, and if
    /// so how many characters from the cursor through its `(`.
    ///
    /// dart scans `url(` and its contents as one token, so `//` inside it is
    /// part of the url rather than a comment (`url(//cdn/x.png)`,
    /// `url(http://x/y)`). The name is matched the way the shared value parser
    /// matches it ([`crate::parser::is_url_function`]): `url` itself, a
    /// VENDOR-PREFIXED `-c-url`, and either spelled with CSS escapes
    /// (`u\72l(`) — but not `my-url(`, an ordinary function where the `//`
    /// really does start a comment.
    ///
    /// Called at every character, and cheap: it returns immediately unless the
    /// cursor is at the first character of an identifier, so each identifier on
    /// a line is scanned at most once.
    function url_func_open(self) -> int? {
        // Only at the START of an identifier, so each one is scanned once as
        // the cursor passes it and the walk stays linear in the line's length.
        let cur = self.cs.at(self.i);
        if (cur == null) {
            return null;
        }
        if (!(is_ident_char(cur) || cur == "\\")) {
            return null;
        }
        if (self.i > 0 && (is_ident_char(self.cs[self.i - 1]) || self.cs[self.i - 1] == "\\")) {
            return null;
        }
        // Walk the identifier WITHOUT allocating first: most of them are
        // ordinary names, and one that is not followed by `(` cannot be a url
        // however it is spelled.
        let k = self.i;
        let escaped = false;
        while let c: string = self.cs.at(k) {
            if (c == "\\") {
                escaped = true;
                break;
            }
            if (is_ident_char(c)) {
                k += 1;
                continue;
            }
            break;
        }
        if (!escaped) {
            return if (self.cs.at(k) == "(" && plain_name_is_url(self.cs.slice(self.i, k))) {
                k + 1 - self.i
            } else {
                null
            };
        }
        // Only an escaped name needs decoding.
        let decoded = root.parser.decode_ident(self.cs, self.i);
        let name = decoded._0;
        let k = decoded._1;
        if (self.cs.at(k) != "(") {
            return null;
        }
        if (root.parser.is_url_function(name)) {
            k + 1 - self.i
        } else {
            null
        }
    }

    /// Consume a `url(...)` token, contents included, through its closing `)`.
    /// Quoted contents are skipped as strings, so `url("a)b")` ends at the
    /// right paren.
    ///
    /// Returns whether the token CLOSED on this line. An unclosed one — the
    /// indented syntax allows `b: url(` to continue onto the next line — leaves
    /// its open paren unaccounted for, so a caller that tracks bracket depth
    /// must count it, or the logical line would end here.
    function skip_url(self, open: int) -> bool {
        for (let _k in baml.iter.Range.new(0, open)) {
            self.bump(); // through the `(`
        }
        let depth = 1;
        while (!self.done()) {
            match (self.cur()) {
                "\"" | "'" => {
                    let _ = self.skip_quoted();
                },
                // A CSS escape: the next character is url CONTENT, so an
                // escaped paren does not close the token (`url(foo\)//cdn)`),
                // as the shared value parser reads it.
                "\\" => {
                    self.bump();
                    if (!self.done()) {
                        self.bump();
                    }
                },
                "(" => {
                    depth += 1;
                    self.bump();
                },
                ")" => {
                    depth -= 1;
                    self.bump();
                    if (depth == 0) {
                        return true;
                    }
                },
                _ => {
                    self.bump();
                },
            }
        }
        false
    }

    /// At `/*`: advance past the closing `*/` (or to end-of-line). Returns
    /// `true` iff the comment closed on this line.
    function skip_loud_comment(self) -> bool {
        self.bump(); // '/'
        self.bump(); // '*'
        while (self.i + 1 < self.cs.length() && !(self.cs[self.i] == "*" && self.cs[self.i + 1] == "/")) {
            self.bump();
        }
        if (self.i + 1 < self.cs.length()) {
            self.bump(); // '*'
            self.bump(); // '/'
            true
        } else {
            false
        }
    }
}

/// Whether a declaration value ends mid-expression with a binary operator
/// awaiting its right operand on the next line (`3 %`, `3 +`, `true and`,
/// `3 /`, `c -`). A `-` directly attached to an identifier character is part
/// of the identifier (`c-` does not continue); `=` only continues as part of
/// a comparison (`==`, `<=`, `>=`, `!=`).
function ends_with_value_operator(s: string) -> bool {
    let t = trim_trailing_loud_comments(s);
    if (t.ends_with("==") || t.ends_with("<=") || t.ends_with(">=") || t.ends_with("!=")) {
        return true;
    }
    if let rest: string = root.std.strip_suffix(t, "-") {
        let prev = root.std.last_char(rest);
        return !(
            if (prev != null) {
                is_ident_char(prev)
            } else {
                false
            }
        );
    }
    if let rest: string = root.std.strip_suffix(t, "%") {
        // `3%` is a percent unit (complete); only a detached `%` is the
        // modulo operator awaiting its right operand.
        let prev = root.std.last_char(rest);
        return if (prev != null) {
            prev.is_whitespace()
        } else {
            false
        };
    }
    let c = root.std.last_char(t);
    if (c != null) {
        if (c == "+" || c == "*" || c == "/" || c == "<" || c == ">") {
            return true;
        }
    }
    // Trailing keyword operator (whole word, case-insensitive).
    // PORT: `chars().rev().take_while(is_ident_char)` reversed back -> the
    // suffix after a backwards index scan.
    let tcs = t.chars();
    let k = tcs.length();
    while (k > 0 && is_ident_char(tcs[k - 1])) {
        k -= 1;
    }
    let last_word = t.slice(k, tcs.length());
    if (last_word.length() < root.std.trim_end(t).length()) {
        // Must be preceded by whitespace/boundary to be the operator word.
        let before = t.slice(0, t.length() - last_word.length());
        if (!root.std.is_whitespace(root.std.last_char(before))) {
            return false;
        }
    }
    match (root.std.ascii_lower(last_word)) {
        "and" | "or" | "not" => true,
        _ => false,
    }
}

/// Strip any run of complete trailing `/* … */` comments (and the whitespace
/// before them) from `s`.
function trim_trailing_loud_comments(s: string) -> string {
    let t = root.std.trim_end(s);
    while (t.ends_with("*/")) {
        let open = t.last_index_of("/*");
        if (open == null) {
            break;
        }
        // Only a comment that closes at the very end qualifies (the `*/` we
        // saw must belong to this `/*`).
        //
        // The length check comes first and is load-bearing: in `/*/` the opening
        // `/*` and the closing `*/` OVERLAP on the shared `*`, so `open + 2`
        // runs past `t.len() - 2` and the interior slice panics with
        // "byte range starts at N but ends at N-1". An overlapping pair is not a
        // completed comment, so stop trimming and let the parser report on the
        // text as written (dart-sass emits a normal parse error here).
        if (open + 2 > t.length() - 2) {
            break;
        }
        if (
            !t.slice(open, t.length()).ends_with("*/")
                || t.slice(open + 2, t.length() - 2).includes("/*")
        ) {
            break;
        }
        t = root.std.trim_end(t.slice(0, open));
    }
    t
}

/// Strip a trailing `//` silent comment from a single line, respecting quoted
/// strings, `#{…}` interpolation and `/* */` loud comments (a `//` inside a
/// loud comment is not a silent comment). Returns the line with the comment (if
/// any) removed and trailing whitespace trimmed.
function strip_silent_comment(s: string) -> string {
    let sc = LineScanner.new(s);
    while (!sc.done()) {
        // `url(…)` is one token: `//` inside it is part of the url.
        if let open: int = sc.url_func_open() {
            let _closed = sc.skip_url(open);
            continue;
        }
        match (sc.cur()) {
            "\"" | "'" => {
                let _ = sc.skip_quoted();
            },
            // A loud comment: skip to its close (it may not close on this line,
            // in which case the rest is comment body — leave it).
            "/" if sc.peek(1) == "*" => {
                let _ = sc.skip_loud_comment();
            },
            "/" if sc.peek(1) == "/" => {
                return root.std.trim_end(s.slice(0, sc.offset()));
            },
            "#" if sc.peek(1) == "{" => {
                sc.skip_interp();
            },
            _ => {
                sc.bump();
            },
        }
    }
    root.std.trim_end(s)
}

/// [`strip_silent_comment`] for a STATEMENT's first line, honouring the
/// indented syntax's unquoted `@import` urls.
///
/// dart's `SassParser.importArgument` reads an unquoted url with
/// `almostAnyValue`, so it runs to the next top-level comma and swallows
/// whatever is in the way: `@import foo // c` imports the url `foo // c`
/// (dart carets all eight characters), and `@import http://x/y.css` is one
/// protocol url, not `http:` followed by a comment. A QUOTED url ends at its
/// closing quote, so the `// c` after `@import "foo" // c` is an ordinary
/// comment, dropped as everywhere else.
function strip_statement_comment(s: string) -> string {
    if (directive_name(s) != "import") {
        return strip_silent_comment(s);
    }
    let sc = LineScanner.new(s);
    // Past `@import` itself — through the DECODED keyword, since it may be
    // escaped (`@im\70ort`). Advancing over raw identifier characters left the
    // cursor inside the escape, so the first argument was not seen as quoted
    // and a trailing comment was kept on the line.
    sc.bump();
    let end = root.parser.decode_ident(sc.cs, sc.i)._1;
    while (sc.i < end) {
        sc.bump();
    }
    while (true) {
        while (!sc.done() && sc.cur().is_whitespace()) {
            sc.bump();
        }
        if (sc.done()) {
            break;
        }
        // A bare url is literal to the next top-level comma; after a quoted
        // one, the modifier region scans for comments as usual.
        let quoted = match (sc.cur()) {
            "\"" | "'" => true,
            _ => false,
        };
        if (quoted) {
            let _ = sc.skip_quoted();
        }
        let depth = 0;
        while (!sc.done()) {
            if let open: int = sc.url_func_open() {
                let _closed = sc.skip_url(open);
                continue;
            }
            match (sc.cur()) {
                "\"" | "'" => {
                    let _ = sc.skip_quoted();
                },
                "#" if sc.peek(1) == "{" => {
                    sc.skip_interp();
                },
                "/" if quoted && sc.peek(1) == "*" => {
                    let _ = sc.skip_loud_comment();
                },
                "/" if quoted && sc.peek(1) == "/" => {
                    return root.std.trim_end(s.slice(0, sc.offset()));
                },
                "(" | "[" => {
                    depth += 1;
                    sc.bump();
                },
                ")" | "]" => {
                    depth -= 1;
                    sc.bump();
                },
                // The STATEMENT ends here, so the url does: anything after it
                // is ordinary text, and a trailing `// t` is a comment (dart
                // imports `foo` from `@import foo; // t`).
                ";" if depth == 0 => {
                    let head = s.slice(0, sc.offset());
                    let tail = strip_silent_comment(s.slice(sc.offset(), s.length()));
                    let out = head + tail;
                    return root.std.trim_end(out);
                },
                "," if depth == 0 => {
                    sc.bump();
                    break;
                },
                _ => {
                    sc.bump();
                },
            }
        }
    }
    root.std.trim_end(s)
}

/// Net bracket depth of `s` ignoring strings, `//`/`/* */` comments and `#{}`
/// interpolation.
function bracket_depth(s: string) -> int {
    scan_state(s).bracket_depth
}

/// The "openness" of a logical line: how many brackets remain open, whether the
/// line ends inside an unterminated `#{…}` interpolation, and whether it ends
/// inside an unterminated `/* … */` loud comment.
class ScanState {
    bracket_depth: int,
    in_interp: bool,
    in_loud_comment: bool,
    /// The line ends inside an unterminated quoted string.
    in_string: bool,
    /// The line ends inside an unterminated `url(…)` token. Its contents are
    /// not Sass: the continuation line joins VERBATIM, so a `//` in
    /// `url(` + `  http://x/y)` is part of the url, not a comment.
    in_url: bool,
}

/// Scan `s` once, tracking strings, `//`/`/* */` comments and `#{…}`
/// interpolation, to report its closing state.
/// Whether a custom-property value ends with an open `(`/`[`/`{` bracket or
/// `#{` interpolation (so the next line continues it verbatim). Quoted
/// strings are skipped; a custom value's braces count as brackets.
function custom_value_open(s: string) -> bool {
    // A line ending in an UNPAIRED backslash always continues: the escape
    // needs the next character, whether that makes a string continuation
    // (`--x: "a\` — legal, the pair vanishes) or the error dart reports for
    // one anywhere else (`--x: c\`). Either way the pair has to reach the
    // parser rather than being cut off at the line end.
    if (trailing_backslashes(s) % 2 == 1) {
        return true;
    }
    let sc = LineScanner.new(s);
    let brackets: string[] = [];
    while (!sc.done()) {
        match (sc.cur()) {
            "\"" | "'" => {
                let _ = sc.skip_quoted();
            },
            // An ESCAPED delimiter is literal text, not a bracket: `--x: \{`
            // is a complete value, and counting it left the value "open" so
            // every following line was swallowed into it.
            "\\" => {
                sc.bump();
                if (!sc.done()) {
                    sc.bump();
                }
            },
            // A custom value's braces count as brackets (so an `#{` is just an
            // open brace here, not interpolation).
            "(" | "[" | "{" => {
                brackets.push(
                    match (sc.cur()) {
                        "(" => ")",
                        "[" => "]",
                        _ => "}",
                    },
                );
                sc.bump();
            },
            ")" | "]" | "}" => {
                match (root.std.last(brackets)) {
                    // A closer with no opener ends the value, as it does in the
                    // shared parser.
                    null => {
                        return false;
                    },
                    // A MISMATCHED closer is an error there, so the value stays
                    // open and the next line joins it: the shared parser then
                    // reports dart's `expected ")".` at the closer, rather than
                    // the front-end reporting a stray indented child.
                    let expected: string if expected != sc.cur() => {
                        return true;
                    },
                    _ => {
                        let _ = brackets.pop();
                    },
                }
                sc.bump();
            },
            _ => {
                sc.bump();
            },
        }
    }
    brackets.length() != 0
}

/// Whether `s` ends inside an open `#{` interpolation, scanning *inside*
/// loud-comment text too (unlike [`scan_state`], which skips comment bodies):
/// a `#{` opens interpolation even within `/* … */`.
function interp_open_anywhere(s: string) -> bool {
    let sc = LineScanner.new(s);
    let interp = 0;
    while (!sc.done()) {
        match (sc.cur()) {
            // Quoted strings only have meaning inside interpolation here.
            "\"" | "'" if interp > 0 => {
                let _ = sc.skip_quoted();
            },
            // Counted (not skipped-to-close) so an *unclosed* `#{` is detected.
            "#" if sc.peek(1) == "{" => {
                interp += 1;
                sc.bump();
                sc.bump();
            },
            "{" if interp > 0 => {
                interp += 1;
                sc.bump();
            },
            "}" if interp > 0 => {
                interp -= 1;
                sc.bump();
            },
            _ => {
                sc.bump();
            },
        }
    }
    interp > 0
}

function scan_state(s: string) -> ScanState {
    let sc = LineScanner.new(s);
    let depth = 0;
    // Stack of `#{` interpolation brace depths still open.
    let interp_depth = 0;
    while (!sc.done()) {
        // `url(…)` is one token (dart scans it whole), so neither the `//`
        // inside `url(http://x/y)` nor its parens are structure — unless the
        // token never closes on this line (`b: url(` + `    c)`), whose open
        // paren still continues the logical line.
        if let open: int = sc.url_func_open() {
            if (!sc.skip_url(open)) {
                // Unclosed on this line: its `(` is still open, and its
                // contents continue verbatim onto the next line.
                depth += 1;
                return ScanState {
                    bracket_depth: depth,
                    in_interp: interp_depth > 0,
                    in_loud_comment: false,
                    in_string: false,
                    in_url: true,
                };
            }
            continue;
        }
        match (sc.cur()) {
            "\"" | "'" => {
                if (!sc.skip_quoted()) {
                    // Unterminated quoted string at end of line.
                    return ScanState {
                        bracket_depth: depth,
                        in_interp: interp_depth > 0,
                        in_loud_comment: false,
                        in_string: true,
                        in_url: false,
                    };
                }
            },
            "/" if sc.peek(1) == "/" => {
                break;
            },
            "/" if sc.peek(1) == "*" => {
                if (!sc.skip_loud_comment()) {
                    // Reached end of line without closing the loud comment.
                    return ScanState {
                        bracket_depth: depth,
                        in_interp: interp_depth > 0,
                        in_loud_comment: true,
                        in_string: false,
                        in_url: false,
                    };
                }
            },
            // Counted (not skipped-to-close) so an *unclosed* `#{` is reported.
            "#" if sc.peek(1) == "{" => {
                interp_depth += 1;
                sc.bump();
                sc.bump();
            },
            "{" if interp_depth > 0 => {
                interp_depth += 1;
                sc.bump();
            },
            "}" if interp_depth > 0 => {
                interp_depth -= 1;
                sc.bump();
            },
            "(" | "[" => {
                depth += 1;
                sc.bump();
            },
            ")" | "]" => {
                depth -= 1;
                sc.bump();
            },
            _ => {
                sc.bump();
            },
        }
    }
    ScanState {
        bracket_depth: depth,
        in_interp: interp_depth > 0,
        in_loud_comment: false,
        in_string: false,
        in_url: false,
    }
}

/// Find the byte index of the top-level declaration colon in `logical` (the
/// `:` separating a property/custom-property name from its value), skipping
/// strings, brackets, comments and interpolation. Returns `None` if absent.
// PORT: a CHAR index (guide §8).
function find_decl_colon(logical: string) -> int? {
    let sc = LineScanner.new(logical);
    let paren = 0;
    let bracket = 0;
    while (!sc.done()) {
        match (sc.cur()) {
            "\"" | "'" => {
                let _ = sc.skip_quoted();
            },
            "#" if sc.peek(1) == "{" => {
                sc.skip_interp();
            },
            "(" => {
                paren += 1;
                sc.bump();
            },
            ")" => {
                paren -= 1;
                sc.bump();
            },
            "[" => {
                bracket += 1;
                sc.bump();
            },
            "]" => {
                bracket -= 1;
                sc.bump();
            },
            ":" if paren == 0 && bracket == 0 => {
                return sc.offset();
            },
            _ => {
                sc.bump();
            },
        }
    }
    null
}

/// Byte index of the first top-level `;` in `logical` (outside strings,
/// brackets, `#{…}` interpolation and `/* */` comments), or `None`. A single
/// trailing `;` ends a statement; a `;` with further content is "multiple
/// statements on one line", which the indented syntax forbids.
/// Whether an `@include` logical line carries a top-level `using` keyword
/// (outside brackets and strings) — i.e. a content-block parameter clause.
function has_top_level_using(logical: string) -> bool {
    let sc = LineScanner.new(logical);
    let depth = 0;
    while (!sc.done()) {
        match (sc.cur()) {
            "\"" | "'" => {
                let _ = sc.skip_quoted();
            },
            "(" | "[" => {
                depth += 1;
                sc.bump();
            },
            ")" | "]" => {
                depth -= 1;
                sc.bump();
            },
            "u" | "U" if depth == 0 => {
                let prev_ident = sc.i > 0 && is_ident_char(sc.cs[sc.i - 1]);
                // PORT: `cs[i..].iter().take_while(is_ident_char).collect()` -> an
                // index scan.
                let wk = sc.i;
                while (wk < sc.cs.length() && is_ident_char(sc.cs[wk])) {
                    wk += 1;
                }
                let word = root.std.concat(sc.cs.slice(sc.i, wk));
                if (!prev_ident && root.std.eq_ignore_ascii_case(word, "using")) {
                    return true;
                }
                // Skip the whole identifier run (at least one char, since the
                // cursor is on `u`/`U`).
                // PORT: Rust's `word.len()` is the BYTE length; kept as such.
                for (let _k in baml.iter.Range.new(0, root.std.imax(word.byte_length(), 1))) {
                    sc.bump();
                }
            },
            _ => {
                sc.bump();
            },
        }
    }
    false
}

// PORT: a CHAR index (guide §8).
function find_top_level_semicolon(logical: string) -> int? {
    let sc = LineScanner.new(logical);
    let paren = 0;
    let bracket = 0;
    while (!sc.done()) {
        // `url(…)` is one token (dart scans it whole), so neither the `//`
        // inside `url(http://x/y)` nor its parens are structure. An unclosed
        // one runs to the end of the line, where this scan would stop anyway.
        if let open: int = sc.url_func_open() {
            let _closed = sc.skip_url(open);
            continue;
        }
        match (sc.cur()) {
            "\"" | "'" => {
                let _ = sc.skip_quoted();
            },
            "/" if sc.peek(1) == "/" => {
                break;
            },
            "/" if sc.peek(1) == "*" => {
                let _ = sc.skip_loud_comment();
            },
            "#" if sc.peek(1) == "{" => {
                sc.skip_interp();
            },
            "(" => {
                paren += 1;
                sc.bump();
            },
            ")" => {
                paren -= 1;
                sc.bump();
            },
            "[" => {
                bracket += 1;
                sc.bump();
            },
            "]" => {
                bracket -= 1;
                sc.bump();
            },
            ";" if paren == 0 && bracket == 0 => {
                return sc.offset();
            },
            _ => {
                sc.bump();
            },
        }
    }
    null
}
