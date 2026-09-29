// Port of proc-macro2-1.0.106 (the subset clap_derive relies on)
//
// A wrapper around the procedural macro API of the compiler's `proc_macro`
// crate. `clap_derive` receives its input as a `TokenStream`.
//
// BAML has no compiler plugin interface. The derive reads `#[...]` attributes
// out of doc comments at runtime (see `root.clap_derive`), so this namespace
// provides the part that matters there: `TokenStream::from_str` (the lexer in
// `src/parse.rs`) and the token tree data model (`src/lib.rs`).
//
//   src/lib.rs    -> lib.baml    (TokenStream, TokenTree, Group, Ident, Punct, Literal, Span)
//   src/parse.rs  -> parse.baml  (token_stream_from_str)

/// A region of source code (byte offsets into the lexed string).
class Span {
    lo: int,
    hi: int,

    /// The span of the invocation of the current procedural macro.
    function call_site() -> Span { Span { lo: 0, hi: 0 } }

    /// Create a new span encompassing `self` and `other`.
    function join(self, other: Span) -> Span {
        Span { lo: if (self.lo < other.lo) { self.lo } else { other.lo }, hi: if (self.hi > other.hi) { self.hi } else { other.hi } }
    }
}

/// Describes how a sequence of token trees is delimited.
enum Delimiter {
    /// `( ... )`
    Parenthesis,
    /// `{ ... }`
    Brace,
    /// `[ ... ]`
    Bracket,
    /// `∅ ... ∅` (an invisible delimiter)
    None,
}

/// Whether a `Punct` is followed immediately by another `Punct` or followed by
/// another token or whitespace.
enum Spacing {
    /// E.g. `+` is `Alone` in `+ =`, `+ident` or `+()`.
    Alone,
    /// E.g. `+` is `Joint` in `+=` or `'` is `Joint` in `'#`.
    Joint,
}

/// A delimited token stream.
class Group {
    delimiter: Delimiter,
    stream: TokenStream,
    span: Span,
}

/// A word of Rust code, which may be a keyword or legal variable name.
class Ident {
    sym: string,
    span: Span,

    implements baml.ToString {
        function to_string(self) -> string throws never { self.sym }
    }
}

/// A `Punct` is a single punctuation character like `+`, `-` or `#`.
class Punct {
    ch: string,
    spacing: Spacing,
    span: Span,
}

/// A literal string (`"hello"`), byte string (`b"hello"`), character (`'a'`),
/// byte character (`b'a'`), an integer or floating point number with or
/// without a suffix (`1`, `1u8`, `2.3`, `2.3f32`).
class Literal {
    /// The literal exactly as written in the source
    repr: string,
    span: Span,

    implements baml.ToString {
        function to_string(self) -> string throws never { self.repr }
    }
}

/// A single token or a delimited sequence of token trees (e.g. `[1, (), ..]`).
type TokenTree = Group | Ident | Punct | Literal

/// An abstract stream of tokens, or more concretely a sequence of token trees.
class TokenStream {
    trees: TokenTree[],

    /// Returns an empty `TokenStream` containing no token trees.
    function new() -> TokenStream { TokenStream { trees: [] } }

    /// Checks if this `TokenStream` is empty.
    function is_empty(self) -> bool { self.trees.length() == 0 }

    /// `impl Display for TokenStream`: prints the tokens back as source
    implements baml.ToString {
        function to_string(self) -> string throws never {
            let out = "";
            for (let i in baml.iter.Range.new(0, self.trees.length())) {
                let t = self.trees[i];
                let s = token_tree_to_string(t);
                let joint = match (t) {
                    let p: Punct => p.spacing == Spacing.Joint,
                    _ => false,
                };
                out = out + s;
                if (!joint && i + 1 < self.trees.length()) {
                    out = out + " ";
                }
            }
            out
        }
    }
}

function token_tree_to_string(t: TokenTree) -> string {
    match (t) {
        let g: Group => {
            let inner = g.stream.to_string();
            match (g.delimiter) {
                Delimiter.Parenthesis => `(${inner})`,
                Delimiter.Brace => `{ ${inner} }`,
                Delimiter.Bracket => `[${inner}]`,
                Delimiter.None => inner,
            }
        },
        let i: Ident => i.sym,
        let p: Punct => p.ch,
        let l: Literal => l.repr,
    }
}

function token_tree_span(t: TokenTree) -> Span {
    match (t) {
        let g: Group => g.span,
        let i: Ident => i.span,
        let p: Punct => p.span,
        let l: Literal => l.span,
    }
}
