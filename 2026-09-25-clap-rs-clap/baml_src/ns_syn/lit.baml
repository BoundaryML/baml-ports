// Port of syn-2.0.117/src/lit.rs

/// A Rust literal such as a string or integer or boolean.
type Lit = LitStr | LitChar | LitInt | LitFloat | LitBool

/// A UTF-8 string literal: `"foo"`.
class LitStr {
    repr: string,

    /// The (unescaped) string value
    function value(self) -> string { unescape_str(self.repr) }
}

/// A character literal: `'a'`.
class LitChar {
    repr: string,

    function value(self) -> string {
        let inner = self.repr.slice(1, self.repr.length() - 1);
        unescape_body(inner)
    }
}

/// An integer literal: `1` or `1u16`.
class LitInt {
    repr: string,

    /// The digits, without suffix or `_` separators
    function base10_digits(self) -> string {
        let digits = self.repr.chars().filter((c) -> { c.is_ascii_numeric() || c == "-" }).join("");
        digits
    }

    /// The type suffix, e.g. `u16` in `1u16`
    function suffix(self) -> string {
        let chars = self.repr.chars();
        let i = chars.find_index((c) -> { c.is_alphabetic() && c != "_" });
        if let idx: int = i { chars.slice(idx, chars.length()).join("") } else { "" }
    }

    function base10_parse(self) -> int throws Error {
        baml.Int.parse(self.base10_digits()) catch_all (e) { _ => throw Error.new(root.proc_macro2.Span.call_site(), `invalid integer literal ${self.repr}`) }
    }
}

/// A floating point literal: `1f64` or `1.0e10f64`.
class LitFloat {
    repr: string,

    function base10_parse(self) -> float throws Error {
        let digits = self.repr.chars().filter((c) -> { c != "_" }).join("").replace("f64", "").replace("f32", "");
        baml.Float.parse(digits) catch_all (e) { _ => throw Error.new(root.proc_macro2.Span.call_site(), `invalid float literal ${self.repr}`) }
    }
}

/// A boolean literal: `true` or `false`.
class LitBool {
    value: bool,
}

/// `Lit::new(literal)`: interpret a `proc_macro2::Literal`
function lit_from_literal(l: root.proc_macro2.Literal) -> Lit {
    let r = l.repr;
    if (r.starts_with("\"") || r.starts_with("r\"") || r.starts_with("r#")) {
        LitStr { repr: r }
    } else if (r.starts_with("'")) {
        LitChar { repr: r }
    } else if (r.includes(".") || (r.includes("e") && !r.starts_with("0x")) || r.ends_with("f64") || r.ends_with("f32")) {
        LitFloat { repr: r }
    } else {
        LitInt { repr: r }
    }
}

/// Unescape the body of a (possibly raw) string literal
function unescape_str(repr: string) -> string {
    if (repr.starts_with("r")) {
        let first = repr.index_of("\"") ?? 0;
        let last = repr.last_index_of("\"") ?? repr.length();
        return repr.slice(first + 1, last);
    }
    unescape_body(repr.slice(1, repr.length() - 1))
}

function unescape_body(s: string) -> string {
    let out = "";
    let chars = s.chars();
    let i = 0;
    while (i < chars.length()) {
        let c = chars[i];
        if (c == "\\" && i + 1 < chars.length()) {
            let n = chars[i + 1];
            i += 2;
            if (n == "n") {
                out = out + "\n";
            } else if (n == "t") {
                out = out + "\t";
            } else if (n == "r") {
                out = out + "\r";
            } else if (n == "0") {
                out = out + (baml.String.from_code_points([0]) catch_all (e) { _ => "" });
            } else if (n == "\n") {
                // line continuation: skip leading whitespace on the next line
                while (i < chars.length() && (chars[i] == " " || chars[i] == "\t" || chars[i] == "\n")) { i += 1; }
            } else {
                out = out + n;
            }
        } else {
            out = out + c;
            i += 1;
        }
    }
    out
}
