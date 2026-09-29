// Ported from sasso `src/selector/parse.rs` (namespace `root.selector.parse`).
//
// The selector-string parser: turns an already-resolved selector string (after
// `&`/interpolation substitution) into the structured [`Complex`]/[`Compound`]/
// [`Simple`] model the `@extend` engine in [`super`] operates on. Pure parsing,
// no extend logic.

// ---- parsing -----------------------------------------------------------
/// Parse a selector-list string (already `&`/interpolation-resolved) into
/// complex selectors. Returns `None` if anything is unparseable (the caller
/// then falls back to leaving the selector untouched).
function parse_list(sel: string) -> root.selector.Complex[]? {
    let out: root.selector.Complex[] = [];
    for (let part in split_top(sel, ",")) {
        let part = root.std.trim(part);
        if (part == "") {
            continue;
        }
        let complex = parse_complex(part);
        if (complex == null) {
            return null;
        }
        out.push(complex);
    }
    if (out.length() == 0) {
        return null;
    }
    out
}

/// Parse a single complex selector.
function parse_complex(s: string) -> root.selector.Complex? {
    let chars = s.chars();
    let components: root.selector.ComplexComponent[] = [];
    let i = root.std.Cell.new(0);
    // The run of combinators seen since the last compound. dart-sass preserves a
    // run of more than one (`c > > d`) and a leading run (`~ ~ c`).
    let pending: root.selector.Combinator[] = [];
    while (true) {
        skip_ws(chars, i);
        if (i.value >= chars.length()) {
            break;
        }
        // A combinator (a run of them is collected, not just the last).
        let combinator: root.selector.Combinator? = match (chars[i.value]) {
            ">" => root.selector.Combinator.Child,
            "+" => root.selector.Combinator.NextSibling,
            "~" => root.selector.Combinator.FollowingSibling,
            _ => null,
        };
        if (combinator != null) {
            pending.push(combinator);
            i.value += 1;
            continue;
        }
        let compound = parse_compound(chars, i);
        if (compound == null) {
            return null;
        }
        // PORT: `std::mem::take(&mut pending)`.
        let taken = pending;
        pending = [];
        components.push(root.selector.ComplexComponent { combinators: taken, compound: compound });
    }
    // A trailing combinator run (`c >`, `c + >`) or a combinator-only selector
    // (`>`) is preserved in `trailing`. A truly empty complex is unparseable.
    if (components.length() == 0 && pending.length() == 0) {
        return null;
    }
    root.selector.Complex { components: components, trailing: pending }
}

/// Parse one compound selector starting at `*i`, advancing `*i` past it.
function parse_compound(chars: string[], i: root.std.Cell<int>) -> root.selector.Compound? {
    let simples: root.selector.Simple[] = [];
    while (i.value < chars.length()) {
        let c = chars[i.value];
        match (c) {
            " " | "\t" | "\n" | "\r" | ">" | "+" | "~" | "," => {
                break;
            },
            "." => {
                i.value += 1;
                let name = read_ident(chars, i);
                if (name == null) {
                    return null;
                }
                simples.push(root.selector.Simple_Class { _0: name });
            },
            "#" => {
                i.value += 1;
                let name = read_ident(chars, i);
                if (name == null) {
                    return null;
                }
                simples.push(root.selector.Simple_Id { _0: name });
            },
            "%" => {
                i.value += 1;
                let name = read_ident(chars, i);
                if (name == null) {
                    return null;
                }
                simples.push(root.selector.Simple_Placeholder { _0: name });
            },
            "[" => {
                let text = read_bracketed(chars, i);
                if (text == null) {
                    return null;
                }
                simples.push(root.selector.Simple_Attribute { _0: normalize_attribute(text) });
            },
            ":" => {
                let text = read_pseudo(chars, i);
                if (text == null) {
                    return null;
                }
                // Canonicalize a `:nth-child`/`:nth-last-child` An+B argument so
                // comparisons and output match dart-sass (`2n + 1` → `2n+1`).
                let text = root.selector.normalize_nth(text) ?? text;
                // Re-serialize a selector-argument pseudo canonically (its
                // attributes/inner pseudos normalize recursively, so
                // `:not([a = b])` and `:not([a=b])` compare equal).
                let text = root.selector.normalize_pseudo_arg(text) ?? text;
                simples.push(root.selector.Simple_Pseudo { _0: text });
            },
            "*" => {
                i.value += 1;
                // `*|...` uses `*` as a namespace prefix.
                if (i.value < chars.length() && chars[i.value] == "|" && chars.at(i.value + 1) != "=") {
                    i.value += 1;
                    let after = read_type_after_ns(chars, i);
                    if (after == null) {
                        return null;
                    }
                    match (after) {
                        // `*|*`
                        let _u: root.selector.Simple_Universal => {
                            simples.push(root.selector.Simple_Universal { ns: "*" })
                        },
                        // `*|type`
                        let t: root.selector.Simple_Type => {
                            simples.push(root.selector.Simple_Type { _0: `*|${t._0}` })
                        },
                        _ => simples.push(after),
                    }
                } else {
                    simples.push(root.selector.Simple_Universal { ns: null });
                }
            },
            "|" => {
                // A leading `|` is the *empty* namespace: `|c`, `|*`.
                i.value += 1;
                let after = read_type_after_ns(chars, i);
                if (after == null) {
                    return null;
                }
                match (after) {
                    let _u: root.selector.Simple_Universal => {
                        simples.push(root.selector.Simple_Universal { ns: "" })
                    },
                    let t: root.selector.Simple_Type => {
                        simples.push(root.selector.Simple_Type { _0: `|${t._0}` })
                    },
                    _ => simples.push(after),
                }
            },
            _ if is_ident_start(c) || c == "\\" => {
                let pair = read_type_or_ns(chars, i);
                if (pair == null) {
                    return null;
                }
                let name = pair._0;
                let is_ns = pair._1;
                if (is_ns) {
                    let after = read_type_after_ns(chars, i);
                    if (after == null) {
                        return null;
                    }
                    // prepend namespace to the rendered text
                    match (after) {
                        let _u: root.selector.Simple_Universal => {
                            simples.push(root.selector.Simple_Universal { ns: name })
                        },
                        let t: root.selector.Simple_Type => {
                            simples.push(root.selector.Simple_Type { _0: `${name}|${t._0}` })
                        },
                        _ => simples.push(after),
                    }
                } else {
                    simples.push(root.selector.Simple_Type { _0: name });
                }
            },
            _ => {
                return null;
            },
        }
    }
    if (simples.length() == 0) {
        return null;
    }
    root.selector.Compound { simples: simples }
}

/// Read a type selector or a namespace prefix. Returns `(text, is_namespace)`
/// where `is_namespace` is true when the next char is `|` (not `|=`).
function read_type_or_ns(chars: string[], i: root.std.Cell<int>) -> root.std.Tuple2<string, bool>? {
    let name = read_ident(chars, i);
    if (name == null) {
        return null;
    }
    if (i.value < chars.length() && chars[i.value] == "|" && chars.at(i.value + 1) != "=") {
        i.value += 1; // consume '|'
        root.std.Tuple2 { _0: name, _1: true }
    } else {
        root.std.Tuple2 { _0: name, _1: false }
    }
}

/// After a namespace `ns|`, read either `*` or a type name.
function read_type_after_ns(chars: string[], i: root.std.Cell<int>) -> root.selector.Simple? {
    if (i.value < chars.length() && chars[i.value] == "*") {
        i.value += 1;
        return root.selector.Simple_Universal { ns: null };
    }
    let t = read_ident(chars, i);
    if (t == null) {
        return null;
    }
    root.selector.Simple_Type { _0: t }
}

/// Decode a CSS identifier's `\` escapes to their literal characters, then
/// re-serialize it in dart-sass's canonical escape form (its `_writeIdentifier`).
/// A plain ASCII identifier with no escapes round-trips unchanged.
function canonicalize_ident(raw: string) -> string {
    if (!raw.includes("\\")) {
        return raw;
    }
    // ---- decode ----
    let chars = raw.chars();
    let decoded: string[] = [];
    let i = 0;
    while (i < chars.length()) {
        if (chars[i] == "\\") {
            i += 1;
            if (i >= chars.length()) {
                // A trailing lone backslash decodes to U+FFFD per CSS.
                decoded.push("�");
                break;
            }
            if (chars[i].is_ascii_hex()) {
                let hex = "";
                let digits = 0;
                while (digits < 6 && i < chars.length() && chars[i].is_ascii_hex()) {
                    hex = hex + chars[i];
                    i += 1;
                    digits += 1;
                }
                // One optional trailing whitespace terminates the escape.
                if (i < chars.length() && chars[i].is_whitespace()) {
                    i += 1;
                }
                let cp = from_str_radix_16(hex) ?? 0;
                // U+0000 and out-of-range/surrogate code points map to U+FFFD.
                let ch = if (cp == 0) {
                    "�"
                } else {
                    root.std.chr(cp) ?? "�"
                };
                decoded.push(ch);
            } else {
                decoded.push(chars[i]);
                i += 1;
            }
        } else {
            decoded.push(chars[i]);
            i += 1;
        }
    }
    // ---- re-serialize (dart-sass `_writeIdentifier`) ----
    let out = root.std.StrBuf.new();
    let first_is_hyphen = decoded.at(0) == "-";
    let idx = 0;
    for (let c in decoded) {
        let cu = root.std.ord(c);
        let needs_hex = cu < 0x20
            || cu == 0x7F
            || (idx == 0 && c.is_ascii_numeric())
            || (idx == 1 && c.is_ascii_numeric() && first_is_hyphen);
        if (needs_hex) {
            out.push("\\");
            out.push_str(root.std.hex_lower(cu));
            // dart-sass always terminates a numeric escape with a single space
            // so it can never be misread as continuing into the next character.
            out.push(" ");
        } else if (c == "_" || c == "-" || c.is_ascii_alphanumeric() || cu >= 0x80) {
            out.push(c);
        } else {
            out.push("\\");
            out.push(c);
        }
        idx += 1;
    }
    out.as_str()
}

function read_ident(chars: string[], i: root.std.Cell<int>) -> string? {
    let start = i.value;
    let s = root.std.StrBuf.new();
    let saw_escape = false;
    while (i.value < chars.length()) {
        let c = chars[i.value];
        if (c == "\\") {
            // A hex escape consumes up to six digits PLUS one optional
            // trailing whitespace — `\02e foo` is the single identifier
            // `\.foo`, not two compounds.
            saw_escape = true;
            s.push(c);
            i.value += 1;
            if (i.value < chars.length() && chars[i.value].is_ascii_hex()) {
                let digits = 0;
                while (digits < 6 && i.value < chars.length() && chars[i.value].is_ascii_hex()) {
                    s.push(chars[i.value]);
                    i.value += 1;
                    digits += 1;
                }
                if (i.value < chars.length() && chars[i.value].is_whitespace()) {
                    s.push(chars[i.value]);
                    i.value += 1;
                }
            } else if (i.value < chars.length()) {
                s.push(chars[i.value]);
                i.value += 1;
            }
            continue;
        }
        if (is_ident_char(c)) {
            s.push(c);
            i.value += 1;
        } else {
            break;
        }
    }
    if (i.value == start) {
        return null;
    }
    // Canonicalize the escape spelling so `\2E foo`, `\02e foo`, and `\.foo`
    // all compare (and extend-match) equal.
    if (saw_escape) {
        return canonicalize_ident(s.as_str());
    }
    s.as_str()
}

/// Whether `c` is CSS whitespace — the five code points CSS counts, which is
/// NOT `char::is_whitespace()`: that also matches NBSP and the other Unicode
/// spaces, and eating one of those as an escape's delimiter would delete a
/// character the value is supposed to keep.
function is_css_whitespace(c: string) -> bool {
    c == " " || c == "\t" || c == "\n" || c == "\r" || c == "\f"
}

/// Decode the CSS escapes in an attribute selector's quoted value, the way
/// dart's parser does before the serializer re-escapes it: `\22 ` is a `"`,
/// `\61 bc` is `abc`, and `\<char>` is that character.
///
/// Two details the spec is picky about. A hex escape takes up to six digits and
/// then swallows ONE trailing whitespace as its delimiter — a CRLF counting as
/// that one, not as two. And a backslash before a newline is a line
/// continuation inside a string, contributing nothing, where "newline" again
/// means LF, CR, CRLF or form feed.
function decode_css_escapes(raw: string) -> string {
    if (!raw.includes("\\")) {
        return raw;
    }
    let cs = raw.chars();
    let out = root.std.StrBuf.with_capacity(raw.byte_length());
    let i = 0;
    while (i < cs.length()) {
        if (cs[i] != "\\" || i + 1 >= cs.length()) {
            out.push(cs[i]);
            i += 1;
            continue;
        }
        i += 1; // the backslash
        if (!cs[i].is_ascii_hex()) {
            // `\<char>` is that character, EXCEPT a newline: that is a line
            // continuation inside a string and contributes nothing. CRLF is
            // one newline, so it consumes both.
            match (cs[i]) {
                "\r" if cs.at(i + 1) == "\n" => {
                    i += 2;
                },
                "\n" | "\r" | "\f" => {
                    i += 1;
                },
                let c => {
                    out.push(c);
                    i += 1;
                },
            }
            continue;
        }
        let start = i;
        while (i < cs.length() && i - start < 6 && cs[i].is_ascii_hex()) {
            i += 1;
        }
        let hex = root.std.join(cs.slice(start, i), "");
        // Exactly one whitespace may follow as the escape's delimiter, and a
        // CRLF is that one whitespace rather than two.
        if (i < cs.length() && is_css_whitespace(cs[i])) {
            if (cs[i] == "\r" && cs.at(i + 1) == "\n") {
                i += 2;
            } else {
                i += 1;
            }
        }
        let cp = from_str_radix_16(hex) ?? 0xFFFD;
        // NUL, a surrogate and an out-of-range code point all become U+FFFD,
        // as CSS requires.
        out.push(
            (
                if (cp != 0) {
                    root.std.chr(cp)
                } else {
                    null
                }
            )
                ?? "�",
        );
    }
    out.as_str()
}

/// Whether an attribute value can be written without quotes — a CSS
/// identifier. dart allows ONE leading `-` before the name-start character
/// (`[a="-leading"]` is `[a=-leading]`) but not two (`--two` stays quoted),
/// and a leading digit keeps its quotes.
function is_attr_identifier(v: string) -> bool {
    let body = root.std.strip_prefix(v, "-") ?? v;
    // PORT: the `chars` iterator becomes an array plus a cursor.
    let chars = body.chars();
    let first = chars.at(0);
    let starts = if (first != null) {
        first.is_ascii_alphabetic() || first == "_" || root.std.ord(first) >= 0x80
    } else {
        false
    };
    starts
        && chars.slice(1, chars.length()).every((c: string) -> bool {
            c.is_ascii_alphanumeric() || c == "-" || c == "_" || root.std.ord(c) >= 0x80
        })
}

/// Canonicalize an attribute selector the way dart-sass serializes one:
/// whitespace around the operator is dropped (`[a = b]` -> `[a=b]`), and the
/// value is decoded and re-serialized — a plain identifier loses its quotes
/// (`[a="b"]` -> `[a=b]`), anything else takes whichever quote needs fewer
/// escapes. Anything that doesn't fit the simple `[name op value modifier?]`
/// grammar is returned verbatim.
function normalize_attribute(text: string) -> string {
    // PORT: `text.strip_prefix('[').and_then(|t| t.strip_suffix(']'))` spelled out.
    let without_open = root.std.strip_prefix(text, "[");
    let stripped: string? = if (without_open != null) {
        root.std.strip_suffix(without_open, "]")
    } else {
        null
    };
    if (stripped == null) {
        return text;
    }
    let inner = root.std.trim(stripped);
    let cs = inner.chars();
    let i = 0;
    let is_name_char = (c: string) -> bool {
        c.is_ascii_alphanumeric() || c == "-" || c == "_" || c == "\\" || root.std.ord(c) >= 0x80
    };
    // Optional namespace + name. A `|` is part of the name unless followed
    // by `=` (the `|=` operator).
    let name_start = i;
    while (i < cs.length()) {
        let c = cs[i];
        if (is_name_char(c) || c == "*" || (c == "|" && cs.at(i + 1) != "=")) {
            i += 1;
        } else {
            break;
        }
    }
    if (i == name_start) {
        return text;
    }
    let name = root.std.join(cs.slice(name_start, i), "");
    let j = i;
    while (j < cs.length() && cs[j].is_whitespace()) {
        j += 1;
    }
    if (j >= cs.length()) {
        return `[${name}]`;
    }
    // Operator: `=` or one of `~|^$*` followed by `=`.
    let op: string = "";
    if (cs[j] == "=") {
        j += 1;
        op = "=";
    } else if (
        (cs[j] == "~" || cs[j] == "|" || cs[j] == "^" || cs[j] == "$" || cs[j] == "*")
            && cs.at(j + 1) == "="
    ) {
        let o = `${cs[j]}=`;
        j += 2;
        op = o;
    } else {
        return text;
    }
    while (j < cs.length() && cs[j].is_whitespace()) {
        j += 1;
    }
    // Value: quoted or an identifier run.
    // PORT: Rust's late-initialized `let value: String;` starts as "".
    let value: string = "";
    if (j < cs.length() && (cs[j] == "\"" || cs[j] == "'")) {
        let q = cs[j];
        j += 1;
        let vstart = j;
        while (j < cs.length() && cs[j] != q) {
            if (cs[j] == "\\") {
                j += 1;
            }
            j += 1;
        }
        if (j >= cs.length()) {
            return text;
        }
        let raw = root.std.join(cs.slice(vstart, j), "");
        j += 1; // closing quote
        // dart DECODES the escapes and re-serializes, rather than
        // echoing the source text: a plain-identifier value loses its
        // quotes, and everything else is re-quoted with whichever quote
        // needs fewer escapes. Echoing `raw` between double quotes —
        // which is what this did — turns `[a='b"c']` into `[a="b"c"]`,
        // CSS a browser reads as `[a="b"` plus garbage.
        let decoded = decode_css_escapes(raw);
        value
            = if (is_attr_identifier(decoded)) {
                decoded
            } else {
                root.value.serialize_quoted(decoded)
            };
    } else {
        let vstart = j;
        while (j < cs.length() && !cs[j].is_whitespace() && cs[j] != "]") {
            if (cs[j] == "\\") {
                j += 1;
            }
            j += 1;
        }
        if (j == vstart) {
            return text;
        }
        value = root.std.join(cs.slice(vstart, j), "");
    }
    while (j < cs.length() && cs[j].is_whitespace()) {
        j += 1;
    }
    // Optional single-letter modifier (`i`/`s`).
    if (j < cs.length()) {
        let m_raw = root.std.join(cs.slice(j, cs.length()), "");
        let m = root.std.trim(m_raw);
        if (m.byte_length() == 1 && root.std.is_ascii_alphabetic(root.std.first_char(m))) {
            return `[${name}${op}${value} ${m}]`;
        }
        return text;
    }
    `[${name}${op}${value}]`
}

/// Read a `[...]` attribute selector verbatim, returning the full text.
function read_bracketed(chars: string[], i: root.std.Cell<int>) -> string? {
    let start = i.value;
    i.value += 1; // '['
    let depth = 1;
    while (i.value < chars.length()) {
        match (chars[i.value]) {
            "\\" => {
                i.value += 2;
                continue;
            },
            "\"" | "'" => {
                let q = chars[i.value];
                i.value += 1;
                while (i.value < chars.length() && chars[i.value] != q) {
                    if (chars[i.value] == "\\") {
                        i.value += 1;
                    }
                    i.value += 1;
                }
                i.value += 1;
                continue;
            },
            "[" => {
                depth += 1;
            },
            "]" => {
                depth -= 1;
                if (depth == 0) {
                    i.value += 1;
                    return root.std.join(chars.slice(start, i.value), "");
                }
            },
            _ => {},
        }
        i.value += 1;
    }
    null
}

/// Read a pseudo-class/element selector verbatim (with any `(...)` argument).
function read_pseudo(chars: string[], i: root.std.Cell<int>) -> string? {
    let start = i.value;
    i.value += 1; // first ':'
    if (i.value < chars.length() && chars[i.value] == ":") {
        i.value += 1; // '::'
    }
    // name
    if (read_ident(chars, i) == null) {
        return null;
    }
    // optional argument
    if (i.value < chars.length() && chars[i.value] == "(") {
        let depth = 0;
        while (i.value < chars.length()) {
            match (chars[i.value]) {
                "\\" => {
                    i.value += 2;
                    continue;
                },
                "\"" | "'" => {
                    let q = chars[i.value];
                    i.value += 1;
                    while (i.value < chars.length() && chars[i.value] != q) {
                        if (chars[i.value] == "\\") {
                            i.value += 1;
                        }
                        i.value += 1;
                    }
                    i.value += 1;
                    continue;
                },
                "(" => {
                    depth += 1;
                },
                ")" => {
                    depth -= 1;
                    if (depth == 0) {
                        i.value += 1;
                        break;
                    }
                },
                _ => {},
            }
            i.value += 1;
        }
    }
    // PORT: Rust's `chars[start..*i]` would panic if an escape/quote skip ran
    // past the end; BAML's `slice` clamps instead.
    root.std.join(chars.slice(start, i.value), "")
}

function skip_ws(chars: string[], i: root.std.Cell<int>) -> void {
    while (i.value < chars.length() && chars[i.value].is_whitespace()) {
        i.value += 1;
    }
}

function is_ident_start(c: string) -> bool {
    c.is_ascii_alphabetic() || c == "_" || c == "-" || !c.is_ascii()
}

function is_ident_char(c: string) -> bool {
    c.is_ascii_alphanumeric() || c == "_" || c == "-" || !c.is_ascii()
}

/// Split `s` on the top-level (paren/bracket depth 0) occurrences of `sep`.
function split_top(s: string, sep: string) -> string[] {
    let out: string[] = [];
    let cur = root.std.StrBuf.new();
    let paren = 0;
    let bracket = 0;
    // PORT: the peekable `chars` iterator becomes an array plus a cursor `k`.
    let chars = s.chars();
    let k = 0;
    while (k < chars.length()) {
        let c = chars[k];
        k += 1;
        match (c) {
            "\\" => {
                cur.push(c);
                if (k < chars.length()) {
                    cur.push(chars[k]);
                    k += 1;
                }
            },
            "(" => {
                paren += 1;
                cur.push(c);
            },
            ")" => {
                paren -= 1;
                cur.push(c);
            },
            "[" => {
                bracket += 1;
                cur.push(c);
            },
            "]" => {
                bracket -= 1;
                cur.push(c);
            },
            _ if c == sep && paren == 0 && bracket == 0 => {
                out.push(cur.take());
            },
            _ => {
                cur.push(c);
            },
        }
    }
    out.push(cur.take());
    out
}

/// Parse a single complex selector (one comma-free selector). Returns `None`
/// on any parse failure.
function parse_complex_one(s: string) -> root.selector.Complex? {
    parse_complex(root.std.trim(s))
}

/// PORT: local helper for `u32::from_str_radix(hex, 16).ok()` (BAML's
/// `Int.parse` takes no radix). `None` for an empty string, a non-hex digit or
/// a value above `u32::MAX`.
function from_str_radix_16(hex: string) -> int? {
    if (hex == "") {
        return null;
    }
    let v = 0;
    for (let c in hex.chars()) {
        let d = root.std.to_digit(c, 16);
        if (d == null) {
            return null;
        }
        v = v * 16 + d;
        if (v > 4294967295) {
            return null;
        }
    }
    v
}
