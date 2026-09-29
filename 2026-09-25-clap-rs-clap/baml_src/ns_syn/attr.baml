// Port of syn-2.0.117/src/attr.rs

/// An attribute, like `#[repr(transparent)]`.
class Attribute {
    /// `arg` in `#[arg(short, long)]`
    path: Path,
    /// `short, long` in `#[arg(short, long)]`
    tokens: root.proc_macro2.TokenStream,
    /// `Meta::List` (`#[path(tokens)]`) vs `Meta::Path` (`#[path]`) vs `Meta::NameValue`
    style: "list" | "path" | "name_value",

    /// Parse the arguments to the attribute as a syntax tree.
    function parse_args(self) -> ParseBuffer {
        ParseBuffer.new(self.tokens)
    }
}

/// Parse one outer attribute, `#[...]`, from source text
function parse_outer_attribute(src: string) -> Attribute throws Error {
    let ts = root.proc_macro2.token_stream_from_str(src) catch (e) {
        let l: root.proc_macro2.LexError => throw Error.new(l.span, l.message),
    };
    let input = ParseBuffer.new(ts);
    input.expect_punct("#");
    let g = input.peek_group(root.proc_macro2.Delimiter.Bracket) ?? throw input.error("expected `[`");
    input._pos += 1;
    if (!input.is_empty()) {
        throw input.error("unexpected token after attribute");
    }
    let inner = ParseBuffer.new(g.stream);
    let path = inner.parse_path();
    if let args: root.proc_macro2.Group = inner.peek_group(root.proc_macro2.Delimiter.Parenthesis) {
        inner._pos += 1;
        Attribute { path: path, tokens: args.stream, style: "list" }
    } else if (inner.eat_punct("=")) {
        let rest = root.proc_macro2.TokenStream { trees: inner._trees.slice(inner._pos, inner._trees.length()) };
        Attribute { path: path, tokens: rest, style: "name_value" }
    } else {
        Attribute { path: path, tokens: root.proc_macro2.TokenStream.new(), style: "path" }
    }
}

test "parse_attribute" {
    let a = parse_outer_attribute("#[arg(short, long, value_name = \"FILE\")]") catch_all (e) { _ => baml.sys.panic(`${e}`) };
    assert.equal(a.path.joined(), "arg");
    assert.equal(a.style, "list");
    assert.equal(a.tokens.trees.length(), 7)
}
