// Port of proc-macro2-1.0.106/src/parse.rs (the lexer behind `TokenStream::from_str`)

/// Error returned from `TokenStream::from_str`.
class LexError {
    message: string,
    span: Span,

    implements baml.ToString {
        function to_string(self) -> string throws never { self.message }
    }
}

/// `impl FromStr for TokenStream`
///
/// Attempts to break the string into tokens and parse those tokens into a token
/// stream.
function token_stream_from_str(src: string) -> TokenStream throws LexError {
    let chars = src.chars();
    let pos = Cursor { pos: 0 };
    let stream = lex_stream(chars, pos, null);
    stream
}

class Cursor {
    pos: int,
}

function is_ident_start(c: string) -> bool {
    c == "_" || c.is_alphabetic()
}

function is_ident_continue(c: string) -> bool {
    c == "_" || c.is_alphanumeric()
}

function lex_stream(chars: string[], cur: Cursor, close: string?) -> TokenStream throws LexError {
    let trees: TokenTree[] = [];
    let n = chars.length();
    while (cur.pos < n) {
        let c = chars[cur.pos];
        let start = cur.pos;

        // whitespace
        if (c == " " || c == "\t" || c == "\n" || c == "\r") {
            cur.pos += 1;
            continue;
        }

        // comments
        if (c == "/" && cur.pos + 1 < n && chars[cur.pos + 1] == "/") {
            while (cur.pos < n && chars[cur.pos] != "\n") { cur.pos += 1; }
            continue;
        }
        if (c == "/" && cur.pos + 1 < n && chars[cur.pos + 1] == "*") {
            cur.pos += 2;
            while (cur.pos + 1 < n && !(chars[cur.pos] == "*" && chars[cur.pos + 1] == "/")) { cur.pos += 1; }
            cur.pos += 2;
            continue;
        }

        // groups
        if (c == "(" || c == "[" || c == "{") {
            let closing = match (c) { "(" => ")", "[" => "]", _ => "}" };
            cur.pos += 1;
            let inner = lex_stream(chars, cur, closing);
            let delim: Delimiter = match (c) { "(" => Delimiter.Parenthesis, "[" => Delimiter.Bracket, _ => Delimiter.Brace };
            trees.push(Group { delimiter: delim, stream: inner, span: Span { lo: start, hi: cur.pos } });
            continue;
        }
        if (c == ")" || c == "]" || c == "}") {
            if (close == c) {
                cur.pos += 1;
                return TokenStream { trees: trees };
            }
            throw LexError { message: `unexpected closing delimiter \`${c}\``, span: Span { lo: start, hi: start + 1 } };
        }

        // string literals (incl. raw strings and byte strings)
        if (c == "\"" || ((c == "b" || c == "r") && cur.pos + 1 < n && (chars[cur.pos + 1] == "\"" || chars[cur.pos + 1] == "#"))) {
            let lit = lex_string(chars, cur);
            trees.push(Literal { repr: lit, span: Span { lo: start, hi: cur.pos } });
            continue;
        }

        // char literals / lifetimes
        if (c == "'") {
            if (cur.pos + 2 < n && chars[cur.pos + 2] == "'" ) {
                cur.pos += 3;
                trees.push(Literal { repr: chars.slice(start, cur.pos).join(""), span: Span { lo: start, hi: cur.pos } });
                continue;
            }
            if (cur.pos + 3 < n && chars[cur.pos + 1] == "\\") {
                let j = cur.pos + 2;
                while (j < n && chars[j] != "'") { j += 1; }
                cur.pos = j + 1;
                trees.push(Literal { repr: chars.slice(start, cur.pos).join(""), span: Span { lo: start, hi: cur.pos } });
                continue;
            }
            // lifetime: `'a`
            cur.pos += 1;
            trees.push(Punct { ch: "'", spacing: Spacing.Joint, span: Span { lo: start, hi: cur.pos } });
            continue;
        }

        // numbers
        if (c.is_ascii_numeric()) {
            let j = cur.pos;
            while (j < n && (chars[j].is_ascii_alphanumeric() || chars[j] == "_")) { j += 1; }
            // fractional part: `1.5` but not `1..2` nor `1.foo()`
            if (j + 1 < n && chars[j] == "." && chars[j + 1].is_ascii_numeric()) {
                j += 1;
                while (j < n && (chars[j].is_ascii_alphanumeric() || chars[j] == "_")) { j += 1; }
            }
            cur.pos = j;
            trees.push(Literal { repr: chars.slice(start, cur.pos).join(""), span: Span { lo: start, hi: cur.pos } });
            continue;
        }

        // identifiers (incl. raw identifiers `r#type`)
        if (is_ident_start(c)) {
            let j = cur.pos;
            if (c == "r" && j + 1 < n && chars[j + 1] == "#") {
                j += 2;
            }
            while (j < n && is_ident_continue(chars[j])) { j += 1; }
            cur.pos = j;
            let sym = chars.slice(start, cur.pos).join("");
            trees.push(Ident { sym: if (sym.starts_with("r#")) { sym.slice(2, sym.length()) } else { sym }, span: Span { lo: start, hi: cur.pos } });
            continue;
        }

        // punctuation
        let puncts = "~!@#$%^&*-=+|;:,<.>/?";
        if (puncts.includes(c)) {
            cur.pos += 1;
            let next_is_punct = cur.pos < n && puncts.includes(chars[cur.pos]) && chars[cur.pos] != "#";
            trees.push(Punct { ch: c, spacing: if (next_is_punct) { Spacing.Joint } else { Spacing.Alone }, span: Span { lo: start, hi: cur.pos } });
            continue;
        }

        throw LexError { message: `unexpected character \`${c}\``, span: Span { lo: start, hi: start + 1 } };
    }
    if let cl: string = close {
        throw LexError { message: `unclosed delimiter, expected \`${cl}\``, span: Span { lo: cur.pos, hi: cur.pos } };
    }
    TokenStream { trees: trees }
}

function lex_string(chars: string[], cur: Cursor) -> string throws LexError {
    let start = cur.pos;
    let n = chars.length();
    let j = cur.pos;
    if (chars[j] == "b") { j += 1; }
    if (j < n && chars[j] == "r") {
        // raw string: r"..." / r#"..."#
        j += 1;
        let hashes = 0;
        while (j < n && chars[j] == "#") { hashes += 1; j += 1; }
        if (j >= n || chars[j] != "\"") {
            throw LexError { message: "invalid raw string literal", span: Span { lo: start, hi: j } };
        }
        j += 1;
        let terminator = "\"" + "#".repeat(hashes);
        while (j < n) {
            if (chars.slice(j, j + terminator.length()).join("") == terminator) {
                j += terminator.length();
                cur.pos = j;
                return chars.slice(start, j).join("");
            }
            j += 1;
        }
        throw LexError { message: "unterminated raw string", span: Span { lo: start, hi: j } };
    }
    j += 1;
    while (j < n && chars[j] != "\"") {
        if (chars[j] == "\\") { j += 1; }
        j += 1;
    }
    if (j >= n) {
        throw LexError { message: "unterminated double quote string", span: Span { lo: start, hi: j } };
    }
    j += 1;
    cur.pos = j;
    chars.slice(start, j).join("")
}

testset "proc_macro2" {
    test "lex_attribute_args" {
        let ts = token_stream_from_str("short, long, value_name = \"FILE\", num_args = 0..=1") catch_all (e) { _ => TokenStream.new() };
        assert.equal(ts.trees.length(), 15);
        assert.equal(ts.to_string(), "short , long , value_name = \"FILE\" , num_args = 0 ..= 1")
    }
    test "lex_groups" {
        let ts = token_stream_from_str("clap::value_parser!(u16).range(1..)") catch_all (e) { _ => TokenStream.new() };
        assert.equal(ts.to_string(), "clap :: value_parser ! (u16) . range (1 ..)")
    }
    test "lex_error" {
        let msg = token_stream_from_str("foo(") catch (e) { let l: LexError => { l.message } };
        assert.equal(`${msg}`, "unclosed delimiter, expected `)`")
    }
}
