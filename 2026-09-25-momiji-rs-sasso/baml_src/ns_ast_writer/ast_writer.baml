// Ported from sasso `src/ast_writer.rs` (namespace `root.ast_writer`).
//
// Writing an [`Expr`] back out as Sass source.
//
// dart-sass embeds expression text in one diagnostic: the `[if-function]`
// deprecation quotes the three arguments of a legacy `if()` inside the modern
// syntax it suggests. It does that by writing the parsed AST back out, NOT by
// slicing the source — `if(true,1+2,3)` suggests `1 + 2`, `1e3` becomes
// `1000`, and `"a\41 b"` becomes `"aAb"` — so this mirrors
// `Expression.toString()` rather than remembering spans. Every shape here was
// measured against dart-sass 1.103.1 (scratch `dartref/if3..if7.sh`).

function write_into(out: root.std.StrBuf, e: root.ast.Expr) -> void {
    match (e) {
        // A number is written as its VALUE, not as it was typed: `1e3` is
        // `1000` and `.5` is `0.5`.
        let n: root.ast.Expr_Number => {
            out.push_str(
                root.value.Value_Number { _0: root.value.Number.with_unit(n._0, n._1) }.to_css(
                    false,
                ),
            );
        },
        // A colour keeps the spelling it was authored with (`#ABCDEF`, `red`).
        let c: root.ast.Expr_Color => {
            out.push_str(root.value.Value_Color { _0: c._0 }.to_css(false));
        },
        let q: root.ast.Expr_QuotedString => {
            write_quoted(out, q._0);
        },
        let i: root.ast.Expr_Ident => {
            write_template(out, i._0);
        },
        let b: root.ast.Expr_Bool => {
            out.push_str(
                if (b._0) {
                    "true"
                } else {
                    "false"
                },
            );
        },
        let _n: root.ast.Expr_Null => {
            out.push_str("null");
        },
        let v: root.ast.Expr_Var => {
            out.push("$");
            out.push_str(v.name);
        },
        let v: root.ast.Expr_NsVar => {
            out.push_str(v.module);
            out.push_str(".$");
            out.push_str(v.name);
        },
        let _p: root.ast.Expr_Parent => {
            out.push("&");
        },
        let bin: root.ast.Expr_Binary => {
            write_into(out, bin.lhs);
            out.push(" ");
            out.push_str(binop(bin.op));
            out.push(" ");
            write_into(out, bin.rhs);
        },
        let d: root.ast.Expr_Div => {
            write_into(out, d.lhs);
            out.push_str(" / ");
            write_into(out, d.rhs);
        },
        let c: root.ast.Expr_Calc => {
            out.push_str("calc(");
            write_into(out, c.inner);
            out.push(")");
        },
        let u: root.ast.Expr_Unary => {
            write_unary(out, u.op, u.operand);
        },
        let f: root.ast.Expr_Func => {
            if let m: string = f.module {
                out.push_str(m);
                out.push(".");
            }
            out.push_str(f.name);
            write_args(out, f.args);
        },
        let f: root.ast.Expr_InterpFunc => {
            write_template(out, f.name);
            write_args(out, f.args);
        },
        let l: root.ast.Expr_List => {
            write_list(out, l.items, l.sep, l.bracketed);
        },
        let p: root.ast.Expr_Paren => {
            out.push("(");
            write_into(out, p._0);
            out.push(")");
        },
        let m: root.ast.Expr_Map => {
            out.push("(");
            let i = 0;
            for (let pair in m._0) {
                if (i > 0) {
                    out.push_str(", ");
                }
                write_into(out, pair._0);
                out.push_str(": ");
                write_into(out, pair._1);
                i += 1;
            }
            out.push(")");
        },
        let inner: root.ast.Expr_Interp => {
            out.push_str("#{");
            write_into(out, inner._0);
            out.push("}");
        },
        let mi: root.ast.Expr_ModernIf => {
            write_modern_if(out, mi._0);
        },
        _ => root.std.unreachable(),
    }
}

/// A unary operation. dart parenthesises an operand that is ITSELF a unary
/// operation — and writes the parentheses' CHARACTER CODES rather than the
/// characters, so `not not true` really is `not 40not true41` in dart-sass
/// 1.103.1 (`buffer.write($lparen)` where `writeCharCode` was meant). Mirrored
/// deliberately: this crate's output is compared to dart's byte for byte, and
/// the shape is unreachable without a doubled unary operator.
function write_unary(out: root.std.StrBuf, op: root.ast.UnOp, operand: root.ast.Expr) -> void {
    out.push_str(
        match (op) {
            root.ast.UnOp.Neg => "-",
            root.ast.UnOp.Plus => "+",
            root.ast.UnOp.Not => "not ",
        },
    );
    if (operand is root.ast.Expr_Unary) {
        out.push_str("40");
        write_into(out, operand);
        out.push_str("41");
    } else {
        write_into(out, operand);
    }
}

/// A list. An empty one, or a single-element comma-separated one, is written
/// parenthesised — without that it would not parse back as a list.
function write_list(
    out: root.std.StrBuf,
    items: root.ast.Expr[],
    sep: root.value.ListSep,
    bracketed: bool,
) -> void {
    let comma = sep == root.value.ListSep.Comma;
    let needs_parens = !bracketed && (items.length() == 0 || (items.length() == 1 && comma));
    if (bracketed) {
        out.push("[");
    } else if (needs_parens) {
        out.push("(");
    }
    let joiner = match (sep) {
        root.value.ListSep.Comma => ", ",
        root.value.ListSep.Slash => " / ",
        _ => " ",
    };
    let i = 0;
    for (let item in items) {
        if (i > 0) {
            out.push_str(joiner);
        }
        write_into(out, item);
        i += 1;
    }
    // A one-element comma list keeps its trailing comma only when the
    // parentheses are what make it a list: inside brackets the brackets
    // already do, and dart writes `[1]` for `[1,]`.
    if (needs_parens && comma && items.length() != 0) {
        out.push(",");
    }
    if (bracketed) {
        out.push("]");
    } else if (needs_parens) {
        out.push(")");
    }
}

function write_args(out: root.std.StrBuf, args: root.ast.CallArg[]) -> void {
    out.push("(");
    let i = 0;
    for (let a in args) {
        if (i > 0) {
            out.push_str(", ");
        }
        if let n: string = a.name {
            out.push("$");
            out.push_str(n);
            out.push_str(": ");
        }
        write_into(out, a.value);
        if (a.splat) {
            out.push_str("...");
        }
        i += 1;
    }
    out.push(")");
}

/// A quoted string. With no interpolation it is the STRING's serialization
/// (escapes decoded, best quote chosen), which is why `"a\41 b"` comes back as
/// `"aAb"` and `"he said \"hi\""` as `'he said "hi"'`. With interpolation the
/// pieces are written between quotes chosen the same way.
function write_quoted(out: root.std.StrBuf, pieces: root.ast.TplPiece[]) -> void {
    let literal: string = root.std.concat(
        pieces.map((p: root.ast.TplPiece) -> string {
            match (p) {
                let l: root.ast.TplPiece_Lit => l._0,
                let _i: root.ast.TplPiece_Interp => "",
                _ => root.std.unreachable(),
            }
        }),
    );
    if (
        pieces.every((p: root.ast.TplPiece) -> bool {
            p is root.ast.TplPiece_Lit
        })
    ) {
        out.push_str(root.value.serialize_quoted(literal));
        return;
    }
    // `serialize_quoted` picks the quote from the literal text alone; an
    // interpolation cannot change it, since its value is not known here.
    let quote = if (literal.includes("\"") && !literal.includes("'")) {
        "'"
    } else {
        "\""
    };
    out.push(quote);
    for (let p in pieces) {
        match (p) {
            // Escaped exactly as a quote-less string would be — a literal
            // newline in the source is `\a` in the suggestion, not a newline
            // in the middle of the diagnostic.
            let l: root.ast.TplPiece_Lit => {
                let quoted = root.value.serialize_quoted_with(l._0, quote);
                out.push_str(quoted.slice(1, quoted.length() - 1));
            },
            let i: root.ast.TplPiece_Interp => {
                out.push_str("#{");
                write_into(out, i._0);
                out.push("}");
            },
            _ => root.std.unreachable(),
        }
    }
    out.push(quote);
}

/// An unquoted identifier or a raw interpolated sequence: literal text
/// verbatim, interpolations as `#{…}`.
function write_template(out: root.std.StrBuf, pieces: root.ast.TplPiece[]) -> void {
    for (let p in pieces) {
        match (p) {
            let l: root.ast.TplPiece_Lit => {
                out.push_str(l._0);
            },
            let i: root.ast.TplPiece_Interp => {
                out.push_str("#{");
                write_into(out, i._0);
                out.push("}");
            },
            _ => root.std.unreachable(),
        }
    }
}

/// The modern `if()` — the syntax the deprecation suggests, and a legal
/// expression in its own right.
function write_modern_if(out: root.std.StrBuf, clauses: root.ast.IfClause[]) -> void {
    out.push_str("if(");
    let i = 0;
    for (let c in clauses) {
        if (i > 0) {
            out.push_str("; ");
        }
        if let cond: root.ast.IfCond = c.condition {
            write_cond(out, cond);
            out.push_str(": ");
        } else {
            out.push_str("else: ");
        }
        write_into(out, c.value);
        i += 1;
    }
    out.push(")");
}

function write_cond(out: root.std.StrBuf, c: root.ast.IfCond) -> void {
    match (c) {
        let s: root.ast.IfCond_Sass => {
            out.push_str("sass(");
            write_into(out, s._0);
            out.push(")");
        },
        let r: root.ast.IfCond_Raw => {
            write_template(out, r.pieces);
        },
        let n: root.ast.IfCond_Not => {
            out.push_str("not ");
            write_cond(out, n._0);
        },
        let a: root.ast.IfCond_And => {
            write_cond_chain(out, a._0, " and ");
        },
        let o: root.ast.IfCond_Or => {
            write_cond_chain(out, o._0, " or ");
        },
        let p: root.ast.IfCond_Paren => {
            out.push("(");
            write_cond(out, p._0);
            out.push(")");
        },
        _ => root.std.unreachable(),
    }
}

function write_cond_chain(out: root.std.StrBuf, parts: root.ast.IfCond[], joiner: string) -> void {
    let i = 0;
    for (let p in parts) {
        if (i > 0) {
            out.push_str(joiner);
        }
        write_cond(out, p);
        i += 1;
    }
}

function binop(op: root.ast.BinOp) -> string {
    match (op) {
        root.ast.BinOp.Add => "+",
        root.ast.BinOp.Sub => "-",
        root.ast.BinOp.Mul => "*",
        root.ast.BinOp.Mod => "%",
        root.ast.BinOp.Eq => "==",
        root.ast.BinOp.Neq => "!=",
        root.ast.BinOp.Lt => "<",
        root.ast.BinOp.Gt => ">",
        root.ast.BinOp.Le => "<=",
        root.ast.BinOp.Ge => ">=",
        root.ast.BinOp.And => "and",
        root.ast.BinOp.Or => "or",
        root.ast.BinOp.SingleEq => "=",
    }
}

/// The modern `if()` that replaces a legacy `if($c, $t, $f)`, or `None` when
/// the call is not the three plain positional arguments the rewrite needs —
/// dart omits the suggestion for a named, splatted or wrong-arity call and
/// deprecates it all the same.
///
/// A literal `null` branch is dropped rather than written: dart suggests
/// `if(sass($c): $t)` when the else branch is `null`, and flips the condition
/// to `if(not sass($c): $f)` when the then branch is.
function legacy_if_suggestion(args: root.ast.CallArg[]) -> string? {
    if (
        args.length() != 3
            || args.some((a: root.ast.CallArg) -> bool {
                a.name != null || a.splat
            })
    ) {
        return null;
    }
    let cond = args[0].value;
    let when_true = args[1].value;
    let when_false = args[2].value;
    let out = root.std.StrBuf.from("if(");
    if (when_false is root.ast.Expr_Null) {
        out.push_str("sass(");
        write_into(out, cond);
        out.push_str("): ");
        write_into(out, when_true);
    } else if (when_true is root.ast.Expr_Null) {
        out.push_str("not sass(");
        write_into(out, cond);
        out.push_str("): ");
        write_into(out, when_false);
    } else {
        out.push_str("sass(");
        write_into(out, cond);
        out.push_str("): ");
        write_into(out, when_true);
        out.push_str("; else: ");
        write_into(out, when_false);
    }
    out.push(")");
    out.as_str()
}

/// A deprecation dart raises when a file is PARSED rather than when its code
/// runs — so it fires for a mixin nobody includes and an `@if false` branch,
/// exactly once however many times the code executes, with the load site as its
/// only stack frame.
interface ParseTimeDeprecation {}

/// A Sass `@import` rule.
class ParseTimeDeprecation_Import {
    pos: root.scanner.Pos,
    length: int,
    implements ParseTimeDeprecation {}
}

/// A legacy `if($c, $t, $f)`, with the modern rewrite dart suggests (absent
/// for a named, splatted or wrong-arity call).
class ParseTimeDeprecation_LegacyIf {
    pos: root.scanner.Pos,
    length: int,
    suggestion: string?,
    implements ParseTimeDeprecation {}
}

/// Every parse-time deprecation in a sheet, in the order dart reports them:
/// source order across statements — the two kinds interleave — and INNERMOST
/// FIRST within one expression, which falls out of dart building the
/// expression bottom up.
function collect_parse_time_deprecations(stmts: root.ast.Stmt[]) -> ParseTimeDeprecation[] {
    let out: ParseTimeDeprecation[] = [];
    walk_stmts(stmts, out);
    out
}

type Found = ParseTimeDeprecation[];

function walk_stmts(stmts: root.ast.Stmt[], out: Found) -> void {
    for (let stmt in stmts) {
        walk_stmt(stmt, out);
    }
}

function walk_stmt(stmt: root.ast.Stmt, out: Found) -> void {
    match (stmt) {
        let v: root.ast.Stmt_VarDecl => {
            walk_expr(v._0.value, out);
        },
        let r: root.ast.Stmt_Rule => {
            walk_template(r._0.selector, out);
            walk_stmts(r._0.body, out);
        },
        let d: root.ast.Stmt_Decl => {
            walk_template(d._0.property, out);
            walk_expr(d._0.value, out);
        },
        let p: root.ast.Stmt_PropertySet => {
            walk_template(p._0.property, out);
            if let v: root.ast.Expr = p._0.value {
                walk_expr(v, out);
            }
            walk_stmts(p._0.body, out);
        },
        let c: root.ast.Stmt_CustomDecl => {
            walk_template(c._0.property, out);
            walk_template(c._0.value, out);
        },
        let imp: root.ast.Stmt_Import => {
            for (let arg in imp.args) {
                match (arg) {
                    let s: root.ast.ImportArg_Sass => {
                        if (!root.eval.is_css_import(s.path)) {
                            out.push(ParseTimeDeprecation_Import { pos: s.pos, length: s.length });
                        }
                    },
                    // A plain-CSS import still holds parsed expressions: its
                    // url's interpolations (`@import url(if(…))`) and its
                    // `supports()`/media modifiers.
                    let css: root.ast.ImportArg_Css => {
                        walk_template(css.url, out);
                        for (let m in css.modifiers) {
                            match (m) {
                                let raw: root.ast.ImportModifier_Raw => walk_template(raw._0, out),
                                let sup: root.ast.ImportModifier_Supports => {
                                    walk_supports(sup.condition, out)
                                },
                                let med: root.ast.ImportModifier_Media => walk_media(med.list, out),
                                _ => root.std.unreachable(),
                            }
                        }
                    },
                    _ => root.std.unreachable(),
                }
            }
        },
        let c: root.ast.Stmt_Content => {
            walk_args(c.args, out);
        },
        let x: root.ast.Stmt_Extend => {
            walk_template(x.selector, out);
        },
        // PORT: the or-pattern `Stmt::Use { config, .. } | Stmt::Forward { config, .. }`
        // is split into one arm per variant.
        let u: root.ast.Stmt_Use => {
            for (let entry in u.config) {
                walk_expr(entry.value, out);
            }
        },
        let f: root.ast.Stmt_Forward => {
            for (let entry in f.config) {
                walk_expr(entry.value, out);
            }
        },
        let c: root.ast.Stmt_Comment => {
            walk_template(c._0, out);
        },
        let branches: root.ast.Stmt_If => {
            for (let b in branches._0) {
                if let c: root.ast.Expr = b.cond {
                    walk_expr(c, out);
                }
                walk_stmts(b.body, out);
            }
        },
        let f: root.ast.Stmt_For => {
            walk_expr(f.from, out);
            walk_expr(f.to, out);
            walk_stmts(f.body, out);
        },
        let e: root.ast.Stmt_Each => {
            walk_expr(e.list, out);
            walk_stmts(e.body, out);
        },
        let w: root.ast.Stmt_While => {
            walk_expr(w.cond, out);
            walk_stmts(w.body, out);
        },
        // PORT: `Stmt::FunctionDef(c) | Stmt::MixinDef(c)` split into two arms.
        let fd: root.ast.Stmt_FunctionDef => {
            walk_params(fd._0.params, out);
            walk_stmts(fd._0.body, out);
        },
        let md: root.ast.Stmt_MixinDef => {
            walk_params(md._0.params, out);
            walk_stmts(md._0.body, out);
        },
        let r: root.ast.Stmt_Return => {
            walk_expr(r._0, out);
        },
        let inc: root.ast.Stmt_Include => {
            walk_args(inc.args, out);
            if let p: root.ast.ParamList = inc.content_params {
                walk_params(p, out);
            }
            if let body: root.ast.Stmt[] = inc.content {
                walk_stmts(body, out);
            }
        },
        let a: root.ast.Stmt_AtRule => {
            walk_template(a.prelude, out);
            if let b: root.ast.Stmt[] = a.body {
                walk_stmts(b, out);
            }
        },
        let a: root.ast.Stmt_InterpAtRule => {
            walk_template(a.name, out);
            walk_template(a.prelude, out);
            if let b: root.ast.Stmt[] = a.body {
                walk_stmts(b, out);
            }
        },
        let a: root.ast.Stmt_CssCustomAtRule => {
            walk_template(a.prelude, out);
            for (let item in a.body) {
                walk_template(item.property, out);
                match (item.value) {
                    let raw: root.ast.CssCustomValue_Raw => walk_template(raw._0, out),
                    let script: root.ast.CssCustomValue_Script => walk_expr(script._0, out),
                    let set: root.ast.CssCustomValue_Set => {
                        for (let child in set._0) {
                            let suffix = child._0;
                            let value = child._1;
                            walk_template(suffix, out);
                            walk_expr(value, out);
                        }
                    },
                    _ => root.std.unreachable(),
                }
            }
        },
        let m: root.ast.Stmt_Media => {
            walk_media(m.query, out);
            walk_stmts(m.body, out);
        },
        let s: root.ast.Stmt_Supports => {
            walk_supports(s.condition, out);
            walk_stmts(s.body, out);
        },
        let k: root.ast.Stmt_Keyframes => {
            walk_template(k.prelude, out);
            walk_stmts(k.body, out);
        },
        let a: root.ast.Stmt_AtRoot => {
            if let q: root.ast.TplPiece[] = a.query {
                walk_template(q, out);
            }
            walk_stmts(a.body, out);
        },
        // PORT: `Stmt::Warn { value, .. } | Stmt::Debug { .. } | Stmt::Error { .. }`
        // split into one arm per variant.
        let w: root.ast.Stmt_Warn => {
            walk_expr(w.value, out);
        },
        let d: root.ast.Stmt_Debug => {
            walk_expr(d.value, out);
        },
        let e: root.ast.Stmt_Error => {
            walk_expr(e.value, out);
        },
        _ => root.std.unreachable(),
    }
}

function walk_params(params: root.ast.ParamList, out: Found) -> void {
    for (let p in params.params) {
        if let d: root.ast.Expr = p.default {
            walk_expr(d, out);
        }
    }
}

function walk_args(args: root.ast.CallArg[], out: Found) -> void {
    for (let a in args) {
        walk_expr(a.value, out);
    }
}

function walk_template(pieces: root.ast.TplPiece[], out: Found) -> void {
    for (let p in pieces) {
        if let e: root.ast.TplPiece_Interp = p {
            walk_expr(e._0, out);
        }
    }
}

function walk_expr(e: root.ast.Expr, out: Found) -> void {
    match (e) {
        root.ast.Expr_Number {}
            | root.ast.Expr_Color {}
            | root.ast.Expr_Bool {}
            | root.ast.Expr_Null {}
            | root.ast.Expr_Var {}
            | root.ast.Expr_NsVar {}
            | root.ast.Expr_Parent {} =>
        {},
        // PORT: or-patterns that bind a field are split into one arm per variant.
        let q: root.ast.Expr_QuotedString => walk_template(q._0, out),
        let i: root.ast.Expr_Ident => walk_template(i._0, out),
        let b: root.ast.Expr_Binary => {
            walk_expr(b.lhs, out);
            walk_expr(b.rhs, out);
        },
        let d: root.ast.Expr_Div => {
            walk_expr(d.lhs, out);
            walk_expr(d.rhs, out);
        },
        let c: root.ast.Expr_Calc => walk_expr(c.inner, out),
        let p: root.ast.Expr_Paren => walk_expr(p._0, out),
        let i: root.ast.Expr_Interp => walk_expr(i._0, out),
        let u: root.ast.Expr_Unary => walk_expr(u.operand, out),
        let f: root.ast.Expr_Func => {
            // The arguments first: dart builds the expression bottom up, so a
            // nested `if()` is reported before the one holding it.
            walk_args(f.args, out);
            if (f.module == null && f.name == "if") {
                out.push(
                    ParseTimeDeprecation_LegacyIf {
                        pos: f.pos,
                        length: f.length,
                        suggestion: legacy_if_suggestion(f.args),
                    },
                );
            }
        },
        let f: root.ast.Expr_InterpFunc => {
            walk_template(f.name, out);
            walk_args(f.args, out);
        },
        let l: root.ast.Expr_List => {
            for (let item in l.items) {
                walk_expr(item, out);
            }
        },
        let m: root.ast.Expr_Map => {
            for (let pair in m._0) {
                walk_expr(pair._0, out);
                walk_expr(pair._1, out);
            }
        },
        let mi: root.ast.Expr_ModernIf => {
            for (let c in mi._0) {
                if let cond: root.ast.IfCond = c.condition {
                    walk_cond(cond, out);
                }
                walk_expr(c.value, out);
            }
        },
        _ => root.std.unreachable(),
    }
}

function walk_cond(c: root.ast.IfCond, out: Found) -> void {
    match (c) {
        let s: root.ast.IfCond_Sass => walk_expr(s._0, out),
        let r: root.ast.IfCond_Raw => walk_template(r.pieces, out),
        // PORT: or-patterns that bind a field are split into one arm per variant.
        let n: root.ast.IfCond_Not => walk_cond(n._0, out),
        let p: root.ast.IfCond_Paren => walk_cond(p._0, out),
        let a: root.ast.IfCond_And => {
            for (let p in a._0) {
                walk_cond(p, out);
            }
        },
        let o: root.ast.IfCond_Or => {
            for (let p in o._0) {
                walk_cond(p, out);
            }
        },
        _ => root.std.unreachable(),
    }
}

/// A `@media` prelude: its feature values are SassScript, so an `if()` can hide
/// in one.
function walk_media(list: root.ast.MediaQueryList, out: Found) -> void {
    for (let q in list.queries) {
        match (q) {
            let t: root.ast.MediaQuery_Type => {
                if let m: root.ast.TplPiece[] = t.modifier {
                    walk_template(m, out);
                }
                walk_template(t.mtype, out);
                for (let c in t.conditions) {
                    walk_media_in_parens(c, out);
                }
            },
            let cq: root.ast.MediaQuery_Condition => {
                for (let c in cq.conditions) {
                    walk_media_in_parens(c, out);
                }
            },
            _ => root.std.unreachable(),
        }
    }
}

function walk_media_in_parens(c: root.ast.MediaInParens, out: Found) -> void {
    match (c) {
        let feat: root.ast.MediaInParens_Feature => match (feat._0) {
            let d: root.ast.MediaFeature_Decl => {
                walk_expr(d.name, out);
                if let v: root.ast.Expr = d.value {
                    walk_expr(v, out);
                }
            },
            let r: root.ast.MediaFeature_Range => {
                walk_expr(r.first, out);
                walk_expr(r.second, out);
                if let rest: root.std.Tuple2<string, root.ast.Expr> = r.rest {
                    let third = rest._1;
                    walk_expr(third, out);
                }
            },
            _ => root.std.unreachable(),
        },
        let n: root.ast.MediaInParens_Not => walk_media_in_parens(n._0, out),
        let g: root.ast.MediaInParens_Group => {
            for (let inner in g.conditions) {
                walk_media_in_parens(inner, out);
            }
        },
        let i: root.ast.MediaInParens_Interp => walk_expr(i._0, out),
        _ => root.std.unreachable(),
    }
}

/// A `@supports` condition: a declaration's value is SassScript too.
function walk_supports(c: root.ast.SupportsCondition, out: Found) -> void {
    match (c) {
        let d: root.ast.SupportsCondition_Declaration => {
            walk_expr(d.name, out);
            match (d.value) {
                let e: root.ast.SupportsValue_Expr => walk_expr(e._0, out),
                let r: root.ast.SupportsValue_Raw => walk_template(r._0, out),
                _ => root.std.unreachable(),
            }
        },
        let n: root.ast.SupportsCondition_Negation => walk_supports(n._0, out),
        let o: root.ast.SupportsCondition_Operation => {
            walk_supports(o.left, out);
            walk_supports(o.right, out);
        },
        let i: root.ast.SupportsCondition_Interpolation => walk_expr(i._0, out),
        let f: root.ast.SupportsCondition_Function => {
            walk_template(f.name, out);
            walk_template(f.arguments, out);
        },
        let a: root.ast.SupportsCondition_Anything => walk_template(a._0, out),
        _ => root.std.unreachable(),
    }
}
