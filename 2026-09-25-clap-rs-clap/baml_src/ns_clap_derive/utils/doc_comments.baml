// Port of clap_derive/src/utils/doc_comments.rs
//
// The BAML derive receives a declaration's doc comment as one string (BAML
// strips `///` and one following space, like `#[doc = "..."]` in Rust). Lines
// starting with `#[` hold the derive attributes (`#[arg(...)]`, ...), since
// BAML has no custom attributes; everything else is the doc comment proper.

/// A doc comment split into attributes and documentation lines
class DocAndAttrs {
    attrs: root.syn.Attribute[],
    lines: string[],
}

/// Split a BAML docstring into `#[...]` attributes and doc lines
/// (`extract_doc_comment` + the attribute half of `ClapAttr::parse_all`)
function split_docstring(doc: string?) -> DocAndAttrs {
    let attrs: root.syn.Attribute[] = [];
    let lines: string[] = [];
    let src = doc ?? "";
    if (src.is_empty()) {
        return DocAndAttrs { attrs: attrs, lines: lines };
    }
    let raw = src.split("\n");
    let i = 0;
    while (i < raw.length()) {
        let line = raw[i];
        if (line.trim().starts_with("#[")) {
            // Accumulate until brackets balance
            let text = line.trim();
            let depth = bracket_depth(text);
            while (depth > 0 && i + 1 < raw.length()) {
                i += 1;
                text = text + "\n" + raw[i];
                depth = bracket_depth(text);
            }
            let attr = root.syn.parse_outer_attribute(text) catch (e) {
                let err: root.syn.Error => abort(`invalid attribute \`${text}\`: ${err.message}`),
            };
            attrs.push(attr);
        } else {
            lines.push(line);
        }
        i += 1;
    }
    DocAndAttrs { attrs: attrs, lines: extract_doc_comment(lines) }
}

/// `[`/`]` nesting depth outside of string literals
function bracket_depth(s: string) -> int {
    let depth = 0;
    let in_str = false;
    let prev = "";
    for (let c in s.chars()) {
        if (in_str) {
            if (c == "\"" && prev != "\\") { in_str = false; }
        } else if (c == "\"") {
            in_str = true;
        } else if (c == "[" || c == "(" || c == "{") {
            depth += 1;
        } else if (c == "]" || c == ")" || c == "}") {
            depth -= 1;
        }
        prev = c;
    }
    depth
}

/// Remove leading and trailing blank lines
function extract_doc_comment(raw_lines: string[]) -> string[] {
    // multiline comments (`/** ... */`) may have LFs (`\n`) in them,
    // we need to split so we could handle the lines correctly
    //
    // we also need to remove leading and trailing blank lines
    let lines = raw_lines.slice(0, raw_lines.length());
    while (lines.length() > 0 && is_blank(lines[0])) {
        lines.shift();
    }
    while (lines.length() > 0 && is_blank(lines[-1])) {
        lines.pop();
    }
    lines
}

/// `(Option<String>, Option<String>)`: short and long help
class FormattedDoc {
    short: string?,
    long: string?,
}

function format_doc_comment(lines: string[], preprocess: bool, force_long: bool) -> FormattedDoc {
    if (preprocess) {
        let parsed = parse_markdown(lines);
        let long = parsed.long ?? (if (force_long) { parsed.short } else { null });

        FormattedDoc { short: remove_period(parsed.short ?? ""), long: long }
    } else if let first_blank: int = lines.find_index((s) -> { is_blank(s) }) {
        let short = lines.slice(0, first_blank).join("\n");
        let long = lines.join("\n");

        FormattedDoc { short: short, long: long }
    } else {
        let short = lines.join("\n");
        let long = if (force_long) { short } else { null };

        FormattedDoc { short: short, long: long }
    }
}

function split_paragraphs(lines: string[]) -> string[] {
    let out: string[] = [];
    let current: string[] = [];
    for (let line in lines) {
        if (is_blank(line)) {
            if (current.length() > 0) {
                out.push(merge_lines(current));
                current = [];
            }
        } else {
            current.push(line);
        }
    }
    if (current.length() > 0) {
        out.push(merge_lines(current));
    }
    out
}

function remove_period(s: string) -> string {
    if (s.ends_with(".") && !s.ends_with("..")) {
        s.slice(0, s.length() - 1)
    } else {
        s
    }
}

function is_blank(s: string) -> bool {
    s.trim().is_empty()
}

function merge_lines(lines: string[]) -> string {
    lines.map((s) -> { s.trim() }).join(" ")
}

/// `#[cfg(not(feature = "unstable-markdown"))] fn parse_markdown`
function parse_markdown(lines: string[]) -> FormattedDoc {
    if (lines.some((s) -> { is_blank(s) })) {
        let paragraphs = split_paragraphs(lines);
        let short = paragraphs[0];
        let long = paragraphs.join("\n\n");
        FormattedDoc { short: short, long: long }
    } else {
        let short = merge_lines(lines);
        FormattedDoc { short: short, long: null }
    }
}

testset "doc_comments" {
    test "split_docstring" {
        let d = split_docstring("A simple program\n\nMore text\n#[command(version, about)]");
        assert.equal(d.lines, ["A simple program", "", "More text"]);
        assert.equal(d.attrs.length(), 1)
    }
    test "multiline_attribute" {
        let d = split_docstring("Help\n#[arg(\n    long,\n    num_args = 0..=1,\n)]");
        assert.equal(d.lines, ["Help"]);
        // `long` `,` `num_args` `=` `0` `.` `.` `=` `1` `,` (each Punct is one char)
        assert.equal(d.attrs[0].tokens.trees.length(), 10)
    }
    test "format_doc" {
        let f = format_doc_comment(["Short help.", "", "Long", "help"], true, false);
        assert.equal(f.short, "Short help");
        assert.equal(f.long, "Short help.\n\nLong help")
    }
}
