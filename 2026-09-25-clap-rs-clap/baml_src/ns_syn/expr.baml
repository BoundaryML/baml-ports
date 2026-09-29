// Port of syn-2.0.117/src/expr.rs (the expression forms used in clap attributes)

/// A Rust expression.
type Expr = ExprLit
    | ExprPath
    | ExprCall
    | ExprMethodCall
    | ExprMacro
    | ExprRange
    | ExprArray
    | ExprUnary
    | ExprTuple
    | ExprReference
    | ExprClosure
    | ExprParen
    | ExprField
    | ExprBinary

/// A literal in place of an expression: `1`, `"foo"`.
class ExprLit { lit: Lit }

/// A path like `std::mem::replace` possibly containing generic
/// parameters and a qualified self-type.
class ExprPath { path: Path }

/// A function call expression: `invoke(a, b)`.
class ExprCall {
    func: Expr,
    args: Expr[],
}

/// A method call expression: `x.foo::<T>(a, b)`.
class ExprMethodCall {
    receiver: Expr,
    method: string,
    turbofish: string[],
    args: Expr[],
}

/// A macro invocation expression: `format!("{}", q)`.
class ExprMacro {
    path: Path,
    tokens: root.proc_macro2.TokenStream,
}

/// A range expression: `1..2`, `1..`, `..2`, `1..=2`, `..=2`.
class ExprRange {
    start: Expr?,
    end: Expr?,
    closed: bool,
}

/// A slice literal expression: `[a, b, c, d]`.
class ExprArray { elems: Expr[] }

/// A unary operation: `!x`, `*x`, `-x`.
class ExprUnary {
    op: "!" | "-" | "*",
    expr: Expr,
}

/// A tuple expression: `(a, b, c, d)`.
class ExprTuple { elems: Expr[] }

/// A referencing operation: `&a` or `&mut a`.
class ExprReference { expr: Expr }

/// A closure expression: `|a, b| a + b`.
class ExprClosure {
    inputs: string[],
    body: Expr,
}

/// A parenthesized expression: `(a + b)`.
class ExprParen { expr: Expr }

/// Access of a named struct field (`obj.k`) or unnamed tuple struct
/// field (`obj.0`).
class ExprField {
    base: Expr,
    member: string,
}

/// A binary operation: `a + b`, `a * b`.
class ExprBinary {
    left: Expr,
    op: string,
    right: Expr,
}

/// `quote!(#expr)`: render an expression back to source form
function expr_to_string(e: Expr) -> string {
    match (e) {
        let l: ExprLit => match (l.lit) {
            let s: LitStr => s.repr,
            let c: LitChar => c.repr,
            let i: LitInt => i.repr,
            let f: LitFloat => f.repr,
            let b: LitBool => `${b.value}`,
        },
        let p: ExprPath => path_to_string(p.path),
        let c: ExprCall => `${expr_to_string(c.func)}(${c.args.map((a) -> { expr_to_string(a) }).join(", ")})`,
        let m: ExprMethodCall => {
            let tf = if (m.turbofish.length() > 0) { `::<${m.turbofish.join(", ")}>` } else { "" };
            `${expr_to_string(m.receiver)}.${m.method}${tf}(${m.args.map((a) -> { expr_to_string(a) }).join(", ")})`
        },
        let m: ExprMacro => `${path_to_string(m.path)}!(${m.tokens.to_string()})`,
        let r: ExprRange => {
            let s = if let st: Expr = r.start { expr_to_string(st) } else { "" };
            let en = if let ee: Expr = r.end { expr_to_string(ee) } else { "" };
            `${s}${if (r.closed) { "..=" } else { ".." }}${en}`
        },
        let a: ExprArray => `[${a.elems.map((x) -> { expr_to_string(x) }).join(", ")}]`,
        let u: ExprUnary => `${u.op}${expr_to_string(u.expr)}`,
        let t: ExprTuple => `(${t.elems.map((x) -> { expr_to_string(x) }).join(", ")})`,
        let r: ExprReference => `&${expr_to_string(r.expr)}`,
        let c: ExprClosure => `|${c.inputs.join(", ")}| ${expr_to_string(c.body)}`,
        let p: ExprParen => `(${expr_to_string(p.expr)})`,
        let f: ExprField => `${expr_to_string(f.base)}.${f.member}`,
        let b: ExprBinary => `${expr_to_string(b.left)} ${b.op} ${expr_to_string(b.right)}`,
    }
}

function path_to_string(p: Path) -> string {
    let segs = p.segments.map((s) -> {
        if (s.arguments.length() > 0) { `${s.ident}::<${s.arguments.join(", ")}>` } else { s.ident }
    });
    (if (p.leading_colon) { "::" } else { "" }) + segs.join("::")
}

/// `syn::parse_str::<Expr>(s)`
function parse_expr_str(s: string) -> Expr throws Error {
    let ts = root.proc_macro2.token_stream_from_str(s) catch (e) {
        let l: root.proc_macro2.LexError => throw Error.new(l.span, l.message),
    };
    let input = ParseBuffer.new(ts);
    let e = input.parse_expr();
    if (!input.is_empty()) {
        throw input.error("unexpected token");
    }
    e
}

testset "syn_expr" {
    test "parse_paths_and_calls" {
        let e = parse_expr_str("clap::value_parser!(u16).range(1..)") catch_all (err) { _ => ExprTuple { elems: [] } };
        assert.equal(expr_to_string(e), "clap::value_parser!(u16).range(1..)")
    }
    test "parse_range" {
        let e = parse_expr_str("0..=1") catch_all (err) { _ => ExprTuple { elems: [] } };
        assert.equal(expr_to_string(e), "0..=1")
    }
    test "parse_turbofish" {
        let e = parse_expr_str("parse_key_val::<String, i32>") catch_all (err) { _ => ExprTuple { elems: [] } };
        assert.equal(expr_to_string(e), "parse_key_val::<String, i32>")
    }
    test "parse_closure_chain" {
        let e = parse_expr_str("PossibleValuesParser::new([\"22\", \"80\"]).map(|s| s.parse::<usize>().unwrap())") catch_all (err) { _ => ExprTuple { elems: [] } };
        assert.equal(expr_to_string(e), "PossibleValuesParser::new([\"22\", \"80\"]).map(|s| s.parse::<usize>().unwrap())")
    }
    test "parse_negative" {
        let e = parse_expr_str("-5") catch_all (err) { _ => ExprTuple { elems: [] } };
        assert.equal(expr_to_string(e), "-5")
    }
}
