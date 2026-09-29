// Ported from sasso `src/sass_parser.rs` `#[cfg(test)] mod line_scanner_parity`
// (namespace `root.sass_parser.line_scanner_parity`).
//
// Parity oracle for the `LineScanner` refactor (refactor round-2 T1.1).
//
// Each of the eight `.sass` line-analysis queries used to hand-roll its own
// quote / `#{…}` / `/* */` skipping loop; they were collapsed onto the one
// [`super::LineScanner`] cursor. To guarantee that collapse is byte-exact,
// the pre-refactor implementations are preserved verbatim below (suffixed
// `_ref`) and a differential test asserts the live functions agree with
// them over a broad corpus of tricky inputs (escapes, unterminated strings
// and comments, nested interpolation, multibyte chars). If a future change
// to `LineScanner` diverges from the original semantics, this fails.
//
// PORT: `super::*` is `root.sass_parser.*`; `crate::parser::is_url_function`
// is `root.parser.is_url_function`.
// PORT: the `_ref` twins keep Rust's UTF-8 BYTE bookkeeping (`byte +=
// c.len_utf8()`), so they stay an independent oracle for the multibyte
// corpus entries. The live scanners return CHAR offsets (guide §8), so a
// byte offset is converted where it leaves a `_ref` function: `s[..byte]` →
// `root.std.byte_slice(s, 0, byte)`, `Some(byte)` →
// `root.std.byte_to_char_offset(logical, byte)`.

function strip_silent_comment_ref(s: string) -> string {
    let cs = s.chars();
    let i = 0;
    let byte = 0;
    while (i < cs.length()) {
        let c = cs[i];
        match (c) {
            "\"" | "'" => {
                let q = c;
                byte += root.std.len_utf8(c);
                i += 1;
                while (i < cs.length() && cs[i] != q) {
                    if (cs[i] == "\\" && i + 1 < cs.length()) {
                        byte += root.std.len_utf8(cs[i]);
                        i += 1;
                    }
                    byte += root.std.len_utf8(cs[i]);
                    i += 1;
                }
                if (i < cs.length()) {
                    byte += root.std.len_utf8(cs[i]);
                    i += 1;
                }
                continue;
            },
            "/" if cs.at(i + 1) == "*" => {
                byte += 2;
                i += 2;
                while (i + 1 < cs.length() && !(cs[i] == "*" && cs[i + 1] == "/")) {
                    byte += root.std.len_utf8(cs[i]);
                    i += 1;
                }
                if (i + 1 < cs.length()) {
                    byte += 2;
                    i += 2;
                }
                continue;
            },
            "/" if cs.at(i + 1) == "/" => {
                return root.std.trim_end(root.std.byte_slice(s, 0, byte));
            },
            "#" if cs.at(i + 1) == "{" => {
                byte += root.std.len_utf8(c) + root.std.len_utf8("{");
                i += 2;
                let d = 1;
                while (i < cs.length() && d > 0) {
                    match (cs[i]) {
                        // A brace inside a string, or behind an escape, is
                        // text rather than a delimiter.
                        // PORT: `q @ ('"' | '\'')` → the quote bound separately.
                        "\"" | "'" => {
                            let q = cs[i];
                            byte += root.std.len_utf8(cs[i]);
                            i += 1;
                            while (i < cs.length() && cs[i] != q) {
                                if (cs[i] == "\\" && i + 1 < cs.length()) {
                                    byte += root.std.len_utf8(cs[i]);
                                    i += 1;
                                }
                                byte += root.std.len_utf8(cs[i]);
                                i += 1;
                            }
                            if (i < cs.length()) {
                                byte += root.std.len_utf8(cs[i]);
                                i += 1;
                            }
                            continue;
                        },
                        "\\" => {
                            byte += root.std.len_utf8(cs[i]);
                            i += 1;
                            if (i < cs.length()) {
                                byte += root.std.len_utf8(cs[i]);
                                i += 1;
                            }
                            continue;
                        },
                        "{" => {
                            d += 1;
                        },
                        "}" => {
                            d -= 1;
                        },
                        _ => {},
                    }
                    byte += root.std.len_utf8(cs[i]);
                    i += 1;
                }
                continue;
            },
            _ => {},
        }
        byte += root.std.len_utf8(c);
        i += 1;
    }
    root.std.trim_end(s)
}

function custom_value_open_ref(s: string) -> bool {
    let cs = s.chars();
    // PORT: `cs.iter().rev().take_while(|&&c| c == '\\').count()` → a
    // backwards index loop.
    let trailing = 0;
    let j = cs.length() - 1;
    while (j >= 0 && cs[j] == "\\") {
        trailing += 1;
        j -= 1;
    }
    if (trailing % 2 == 1) {
        return true;
    }
    let brackets: string[] = [];
    let i = 0;
    while (i < cs.length()) {
        match (cs[i]) {
            "\"" | "'" => {
                let q = cs[i];
                i += 1;
                while (i < cs.length() && cs[i] != q) {
                    if (cs[i] == "\\") {
                        i += 1;
                    }
                    i += 1;
                }
            },
            "\\" => {
                i += 1;
            },
            "(" => {
                brackets.push(")");
            },
            "[" => {
                brackets.push("]");
            },
            "{" => {
                brackets.push("}");
            },
            ")" | "]" | "}" => {
                match (root.std.last(brackets)) {
                    null => {
                        return false;
                    },
                    let expected: string if expected != cs[i] => {
                        return true;
                    },
                    _ => {
                        let _ = brackets.pop();
                    },
                }
            },
            _ => {},
        }
        i += 1;
    }
    brackets.length() != 0
}

function interp_open_anywhere_ref(s: string) -> bool {
    let cs = s.chars();
    let interp = 0;
    let i = 0;
    while (i < cs.length()) {
        match (cs[i]) {
            "\"" | "'" if interp > 0 => {
                let q = cs[i];
                i += 1;
                while (i < cs.length() && cs[i] != q) {
                    if (cs[i] == "\\") {
                        i += 1;
                    }
                    i += 1;
                }
            },
            "#" if cs.at(i + 1) == "{" => {
                interp += 1;
                i += 2;
                continue;
            },
            "{" if interp > 0 => {
                interp += 1;
            },
            "}" if interp > 0 => {
                interp -= 1;
            },
            _ => {},
        }
        i += 1;
    }
    interp > 0
}

/// Whether `cs[i..]` starts a `url(` FUNCTION token (the exact name, not
/// preceded by an identifier character) — the reference twin of
/// [`LineScanner::url_func_open`].
function at_url_func_ref(cs: string[], i: int) -> bool {
    let want = ["u", "r", "l", "("];
    // PORT: `(0..4).all(|k| cs.get(i + k).is_some_and(…))` → a loop that
    // stops at the first mismatch.
    let all = true;
    for (let k in baml.iter.Range.new(0, 4)) {
        let c = cs.at(i + k);
        let ok = if (c != null) {
            root.std.eq_ignore_ascii_case(c, want[k])
        } else {
            false
        };
        if (!ok) {
            all = false;
            break;
        }
    }
    if (!all) {
        return false;
    }
    let start = i;
    while (start > 0 && root.sass_parser.is_ident_char(cs[start - 1])) {
        start -= 1;
    }
    if (start == i) {
        return true;
    }
    let name = root.std.concat(cs.slice(start, i + 3));
    root.parser.is_url_function(name)
}

/// Skip a `url(…)` token from `i` (which must be at its `u`), returning the
/// index just past its closing `)` — the reference twin of
/// [`LineScanner::skip_url`].
function skip_url_ref(cs: string[], i: int) -> root.std.Tuple2<int, bool> {
    i += 4;
    let depth = 1;
    while (i < cs.length()) {
        match (cs[i]) {
            "\"" | "'" => {
                let q = cs[i];
                i += 1;
                while (i < cs.length()) {
                    if (cs[i] == "\\") {
                        i += 2;
                        continue;
                    }
                    if (cs[i] == q) {
                        i += 1;
                        break;
                    }
                    i += 1;
                }
            },
            "\\" => {
                i += 2;
            },
            "(" => {
                depth += 1;
                i += 1;
            },
            ")" => {
                depth -= 1;
                i += 1;
                if (depth == 0) {
                    return root.std.Tuple2<int, bool> { _0: i, _1: true };
                }
            },
            _ => {
                i += 1;
            },
        }
    }
    root.std.Tuple2<int, bool> { _0: i, _1: false }
}

function scan_state_ref(s: string) -> root.std.Tuple4<int, bool, bool, bool> {
    let cs = s.chars();
    let depth = 0;
    let interp_depth = 0;
    let i = 0;
    while (i < cs.length()) {
        let c = cs[i];
        if ((c == "u" || c == "U") && at_url_func_ref(cs, i)) {
            let r = skip_url_ref(cs, i);
            let next = r._0;
            let closed = r._1;
            i = next;
            if (!closed) {
                depth += 1;
            }
            continue;
        }
        match (c) {
            "\"" | "'" => {
                let q = c;
                i += 1;
                while (i < cs.length() && cs[i] != q) {
                    if (cs[i] == "\\") {
                        i += 1;
                    }
                    i += 1;
                }
                if (i >= cs.length()) {
                    return root.std.Tuple4<int, bool, bool, bool> {
                        _0: depth,
                        _1: interp_depth > 0,
                        _2: false,
                        _3: true,
                    };
                }
            },
            "/" if cs.at(i + 1) == "/" => {
                break;
            },
            "/" if cs.at(i + 1) == "*" => {
                i += 2;
                while (i + 1 < cs.length() && !(cs[i] == "*" && cs[i + 1] == "/")) {
                    i += 1;
                }
                if (i + 1 >= cs.length() && !(cs.at(i) == "*" && cs.at(i + 1) == "/")) {
                    return root.std.Tuple4<int, bool, bool, bool> {
                        _0: depth,
                        _1: interp_depth > 0,
                        _2: true,
                        _3: false,
                    };
                }
                i += 2;
                continue;
            },
            "#" if cs.at(i + 1) == "{" => {
                i += 2;
                interp_depth += 1;
                continue;
            },
            "{" if interp_depth > 0 => {
                interp_depth += 1;
            },
            "}" if interp_depth > 0 => {
                interp_depth -= 1;
            },
            "(" | "[" => {
                depth += 1;
            },
            ")" | "]" => {
                depth -= 1;
            },
            _ => {},
        }
        i += 1;
    }
    root.std.Tuple4<int, bool, bool, bool> { _0: depth, _1: interp_depth > 0, _2: false, _3: false }
}

function find_decl_colon_ref(logical: string) -> int? {
    let cs = logical.chars();
    let byte = 0;
    let paren = 0;
    let bracket = 0;
    let i = 0;
    while (i < cs.length()) {
        let c = cs[i];
        match (c) {
            "\"" | "'" => {
                let q = c;
                byte += root.std.len_utf8(c);
                i += 1;
                while (i < cs.length() && cs[i] != q) {
                    if (cs[i] == "\\") {
                        byte += root.std.len_utf8(cs[i]);
                        i += 1;
                    }
                    if (i < cs.length()) {
                        byte += root.std.len_utf8(cs[i]);
                        i += 1;
                    }
                }
                if (i < cs.length()) {
                    byte += root.std.len_utf8(cs[i]);
                    i += 1;
                }
                continue;
            },
            "#" if cs.at(i + 1) == "{" => {
                byte += root.std.len_utf8(c) + root.std.len_utf8("{");
                i += 2;
                let d = 1;
                while (i < cs.length() && d > 0) {
                    match (cs[i]) {
                        // A brace inside a string, or behind an escape, is
                        // text rather than a delimiter.
                        // PORT: `q @ ('"' | '\'')` → the quote bound separately.
                        "\"" | "'" => {
                            let q = cs[i];
                            byte += root.std.len_utf8(cs[i]);
                            i += 1;
                            while (i < cs.length() && cs[i] != q) {
                                if (cs[i] == "\\" && i + 1 < cs.length()) {
                                    byte += root.std.len_utf8(cs[i]);
                                    i += 1;
                                }
                                byte += root.std.len_utf8(cs[i]);
                                i += 1;
                            }
                            if (i < cs.length()) {
                                byte += root.std.len_utf8(cs[i]);
                                i += 1;
                            }
                            continue;
                        },
                        "\\" => {
                            byte += root.std.len_utf8(cs[i]);
                            i += 1;
                            if (i < cs.length()) {
                                byte += root.std.len_utf8(cs[i]);
                                i += 1;
                            }
                            continue;
                        },
                        "{" => {
                            d += 1;
                        },
                        "}" => {
                            d -= 1;
                        },
                        _ => {},
                    }
                    byte += root.std.len_utf8(cs[i]);
                    i += 1;
                }
                continue;
            },
            "(" => {
                paren += 1;
            },
            ")" => {
                paren -= 1;
            },
            "[" => {
                bracket += 1;
            },
            "]" => {
                bracket -= 1;
            },
            ":" if paren == 0 && bracket == 0 => {
                // PORT: the byte offset as a CHAR offset (see the file header).
                return root.std.byte_to_char_offset(logical, byte);
            },
            _ => {},
        }
        byte += root.std.len_utf8(c);
        i += 1;
    }
    null
}

function has_top_level_using_ref(logical: string) -> bool {
    let cs = logical.chars();
    let depth = 0;
    let i = 0;
    while (i < cs.length()) {
        match (cs[i]) {
            "\"" | "'" => {
                let q = cs[i];
                i += 1;
                while (i < cs.length() && cs[i] != q) {
                    if (cs[i] == "\\") {
                        i += 1;
                    }
                    i += 1;
                }
            },
            "(" | "[" => {
                depth += 1;
            },
            ")" | "]" => {
                depth -= 1;
            },
            "u" | "U" if depth == 0 => {
                let prev_ident = i > 0 && root.sass_parser.is_ident_char(cs[i - 1]);
                // PORT: `cs[i..].iter().take_while(is_ident_char).collect()` →
                // an index scan.
                let wk = i;
                while (wk < cs.length() && root.sass_parser.is_ident_char(cs[wk])) {
                    wk += 1;
                }
                let word = root.std.concat(cs.slice(i, wk));
                if (!prev_ident && root.std.eq_ignore_ascii_case(word, "using")) {
                    return true;
                }
                // PORT: Rust's `word.len()` is the BYTE length; kept as such.
                i += root.std.imax(word.byte_length(), 1);
                continue;
            },
            _ => {},
        }
        i += 1;
    }
    false
}

function find_top_level_semicolon_ref(logical: string) -> int? {
    let cs = logical.chars();
    let paren = 0;
    let bracket = 0;
    let byte = 0;
    let i = 0;
    while (i < cs.length()) {
        let c = cs[i];
        match (c) {
            "\"" | "'" => {
                let q = c;
                byte += root.std.len_utf8(c);
                i += 1;
                while (i < cs.length() && cs[i] != q) {
                    if (cs[i] == "\\" && i + 1 < cs.length()) {
                        byte += root.std.len_utf8(cs[i]);
                        i += 1;
                    }
                    byte += root.std.len_utf8(cs[i]);
                    i += 1;
                }
                if (i < cs.length()) {
                    byte += root.std.len_utf8(cs[i]);
                    i += 1;
                }
                continue;
            },
            "/" if cs.at(i + 1) == "/" => {
                break;
            },
            "/" if cs.at(i + 1) == "*" => {
                byte += 2;
                i += 2;
                while (i + 1 < cs.length() && !(cs[i] == "*" && cs[i + 1] == "/")) {
                    byte += root.std.len_utf8(cs[i]);
                    i += 1;
                }
                if (i + 1 < cs.length()) {
                    byte += 2;
                    i += 2;
                }
                continue;
            },
            "#" if cs.at(i + 1) == "{" => {
                byte += root.std.len_utf8(c) + root.std.len_utf8("{");
                i += 2;
                let d = 1;
                while (i < cs.length() && d > 0) {
                    match (cs[i]) {
                        // A brace inside a string, or behind an escape, is
                        // text rather than a delimiter.
                        // PORT: `q @ ('"' | '\'')` → the quote bound separately.
                        "\"" | "'" => {
                            let q = cs[i];
                            byte += root.std.len_utf8(cs[i]);
                            i += 1;
                            while (i < cs.length() && cs[i] != q) {
                                if (cs[i] == "\\" && i + 1 < cs.length()) {
                                    byte += root.std.len_utf8(cs[i]);
                                    i += 1;
                                }
                                byte += root.std.len_utf8(cs[i]);
                                i += 1;
                            }
                            if (i < cs.length()) {
                                byte += root.std.len_utf8(cs[i]);
                                i += 1;
                            }
                            continue;
                        },
                        "\\" => {
                            byte += root.std.len_utf8(cs[i]);
                            i += 1;
                            if (i < cs.length()) {
                                byte += root.std.len_utf8(cs[i]);
                                i += 1;
                            }
                            continue;
                        },
                        "{" => {
                            d += 1;
                        },
                        "}" => {
                            d -= 1;
                        },
                        _ => {},
                    }
                    byte += root.std.len_utf8(cs[i]);
                    i += 1;
                }
                continue;
            },
            "(" => {
                paren += 1;
            },
            ")" => {
                paren -= 1;
            },
            "[" => {
                bracket += 1;
            },
            "]" => {
                bracket -= 1;
            },
            ";" if paren == 0 && bracket == 0 => {
                // PORT: the byte offset as a CHAR offset (see the file header).
                return root.std.byte_to_char_offset(logical, byte);
            },
            _ => {},
        }
        byte += root.std.len_utf8(c);
        i += 1;
    }
    null
}

/// A broad corpus exercising every branch + edge case of the eight scanners.
function corpus() -> string[] {
    let fragments = [
        "",
        "a, b, c",
        "color: red",
        "foo: bar; baz: qux",
        "@include thing($a, $b) using ($c)",
        "@include thing(using: 1)",
        "url(a, b)",
        "\"a, b\", c",
        "'a; b': c",
        "a: \"unterminated",
        "a: 'half \\' quote'",
        "a: \"esc \\\" still in\", b",
        "trailing backslash \\",
        "trailing backslash in str \"x\\",
        "map: (a: 1, b: 2)",
        "list: [1, 2, 3]",
        "nested: (a: (b: c), d: [e, f])",
        "interp: #{1 + 2}px",
        "interp colon #{$a: b}",
        "unclosed interp #{1 + 2",
        "nested interp #{ #{x} }",
        "interp with brace #{ {a} }",
        "interp with quoted brace #{ \"}\" }",
        "interp with quoted comment #{\"} // no\"}",
        "interp with quoted semicolon #{\"; \"}: v",
        "interp with escaped brace #{ \\} }",
        "custom escaped brace --x: \\{",
        "custom escaped quote --x: \\\"",
        "custom escaped semicolon --x: a\\;b",
        "interp in comment /* #{x} */",
        "// just a comment",
        "value // trailing comment",
        "value /* loud */ more",
        "value /* unclosed loud",
        "a: b /* c */ // d",
        "/* #{x} */ : y",
        "weird: a:b:c",
        "深: 値; другой: значение",
        "emoji 😀: 🎉, x",
        "multi 字\\符 byte",
        "semi inside (a; b); real",
        "colon inside [a:b]: outside",
        "@media screen",
        "$var: value",
        "url(\"x; y\")",
        "a\\:escaped colon: v",
        "#{} : after empty interp",
        "} stray close",
        ") stray paren",
        "using",
        "  using  ",
        "foousing: 1",
        "x using y",
        "\"\"",
        "''",
        "()",
        "#{",
        "/*",
        "*/",
        "//",
    ];
    // PORT: `.iter().map(|s| s.to_string()).collect()` → the array itself.
    fragments
}

test "line_scanner_matches_reference_implementations" {
    for (let s in corpus()) {
        // strip_silent_comment diverged on {s:?}
        assert.equal(root.sass_parser.strip_silent_comment(s), strip_silent_comment_ref(s));
        // custom_value_open diverged on {s:?}
        assert.equal(root.sass_parser.custom_value_open(s), custom_value_open_ref(s));
        // interp_open_anywhere diverged on {s:?}
        assert.equal(root.sass_parser.interp_open_anywhere(s), interp_open_anywhere_ref(s));
        let st = root.sass_parser.scan_state(s);
        // scan_state diverged on {s:?}
        assert.equal(
            root.std.Tuple4<int, bool, bool, bool> {
                _0: st.bracket_depth,
                _1: st.in_interp,
                _2: st.in_loud_comment,
                _3: st.in_string,
            },
            scan_state_ref(s),
        );
        // find_decl_colon diverged on {s:?}
        assert.equal(root.sass_parser.find_decl_colon(s), find_decl_colon_ref(s));
        // has_top_level_using diverged on {s:?}
        assert.equal(root.sass_parser.has_top_level_using(s), has_top_level_using_ref(s));
        // find_top_level_semicolon diverged on {s:?}
        assert.equal(root.sass_parser.find_top_level_semicolon(s), find_top_level_semicolon_ref(s));
    }
}

// Any byte offset the scanners return must land on a UTF-8 char boundary of
// the input (a guard against the byte/char-index bookkeeping drifting).
//
// PORT: the scanners return CHAR offsets (guide §8), so the BAML check is that
// the offset is a valid char index into `s` (`0..=s.length()`) and that its
// UTF-8 byte equivalent is a char boundary.
test "returned_byte_offsets_are_char_boundaries" {
    for (let s in corpus()) {
        if let b: int = root.sass_parser.find_decl_colon(s) {
            // find_decl_colon offset {b} not a boundary in {s:?}
            assert.is_true(
                b >= 0
                    && b <= s.length()
                    && root.std.is_char_boundary(s, root.std.char_to_byte_offset(s, b)),
            );
        }
        if let b: int = root.sass_parser.find_top_level_semicolon(s) {
            // find_top_level_semicolon offset {b} not a boundary in {s:?}
            assert.is_true(
                b >= 0
                    && b <= s.length()
                    && root.std.is_char_boundary(s, root.std.char_to_byte_offset(s, b)),
            );
        }
    }
}

// An overlapping `/*/` — where the opening `/*` and the closing `*/` share
// their `*` — is not a completed comment. It used to panic here
// ("byte range starts at 5 but ends at 4"), reachable from any malformed
// stylesheet: `Parser::parse` on `0"0/*/` aborted the process.
test "overlapping_slash_star_slash_does_not_panic" {
    // PORT: `"\u{e9}"` is written literally (`é`), guide §8.
    for (let s in ["/*/", "a /*/", "0\"0/*/", "é__ '%/*/", ", in %+as *\t@\n'*/*/"]) {
        // The contract is only that this returns; the exact trim is
        // incidental for an unterminated comment.
        let _ = root.sass_parser.trim_trailing_loud_comments(s);
    }
}

// The overlap guard must not stop a well-formed trailing comment from
// being trimmed.
test "well_formed_trailing_comments_still_trim" {
    assert.equal(root.sass_parser.trim_trailing_loud_comments("a /* c */"), "a");
    assert.equal(root.sass_parser.trim_trailing_loud_comments("a /* c */ /* d */"), "a");
    assert.equal(root.sass_parser.trim_trailing_loud_comments("a /**/"), "a");
    assert.equal(root.sass_parser.trim_trailing_loud_comments("a"), "a");
    // Unterminated: nothing to trim.
    assert.equal(root.sass_parser.trim_trailing_loud_comments("a /* c"), "a /* c");
    // Overlapping: left as written.
    assert.equal(root.sass_parser.trim_trailing_loud_comments("a /*/"), "a /*/")
}
