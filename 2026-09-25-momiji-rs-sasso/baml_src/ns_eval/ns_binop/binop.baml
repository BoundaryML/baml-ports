// Ported from sasso `src/eval/binop.rs` (namespace `root.eval.binop`).

/// Evaluate the `/` operator. When `slash` is set and both operands are
/// numbers, produce a slash-separated value that serializes as `a/b` but
/// behaves numerically as the quotient; otherwise perform real division.
function eval_div(
    l: root.value.Value,
    r: root.value.Value,
    slash: bool,
    pos: root.scanner.Pos,
) -> root.value.Value {
    let e = callable_value_error(l, r, pos);
    if (e != null) {
        throw e;
    }
    // The parser only sets `slash` when both operands are numeric literals
    // (or themselves slash divisions), so they are always numbers here. The
    // slash-separated value keeps the authored `a/b` spelling; the carried
    // numeric quotient — used if the slash is later forced into arithmetic —
    // is the real division with full unit cancellation (`1/1px` carries
    // `1px^-1`, so `math.unit(1/1px)` reports `"px^-1"`).
    // Fast path: plain `number / number` (the overwhelmingly common case) —
    // no slash carry, no clone. `without_slash` is a no-op on a plain Number,
    // so this is behavior-identical to the first match arm below.
    if (!slash) {
        if let root.value.Value_Number { _0: let a } = l {
            if let root.value.Value_Number { _0: let b } = r {
                return divide_numbers(a, b, pos);
            }
        }
    }
    // The clones below are only reached for the slash-carry and non-number
    // cases; guarding on `slash` keeps the common path from building the
    // tuple's clones eagerly.
    if (slash) {
        // PORT: `if let (Number(a), Number(b)) = (…, …)` → nested `if let`s.
        if let root.value.Value_Number { _0: let a } = l.without_slash() {
            if let root.value.Value_Number { _0: let b } = r.without_slash() {
                let repr = `${slash_repr(l)}/${slash_repr(r)}`;
                return root.value.Value_Slash { _0: a.div(b), _1: repr };
            }
        }
    }
    // PORT: `match (l.without_slash(), r.without_slash())` → an `if` chain on
    // the two collapsed operands.
    let lv = l.without_slash();
    let rv = r.without_slash();
    if let root.value.Value_Number { _0: let a } = lv {
        if let root.value.Value_Number { _0: let b } = rv {
            return divide_numbers(a, b, pos);
        }
    }
    // dart-sass: `SassColor.dividedBy` throws "Undefined operation" when
    // the right side is a number or another color; any other right side
    // (a string, `var()`, …) falls back to the slash join below
    // (`#AAA/#{itpl}` → `#AAA/itpl`).
    if (
        lv is root.value.Value_Color
            && (rv is root.value.Value_Number || rv is root.value.Value_Color)
    ) {
        throw undefined_op(lv, "/", rv, pos);
    }
    // Every other left/right pair (a calculation, `var()`, unquoted
    // string, list, `true`/`null`, or a number divided by a non-number)
    // forms a slash-separated unquoted string `left/right`, mirroring
    // dart-sass's default `Value.dividedBy`. This is what lets a `/` next
    // to a `calc()`/`var()` special value survive (and what carries the
    // alpha slash through `rgb(1 2 var(--x) / 0.4)`). A slash-division
    // operand keeps its chained spelling (`1/2/foo()`, not `0.5/foo()`).
    // A map or empty-list operand has no CSS serialization, so the slash
    // join itself errors (`() / 1` → `()`, `1 / (a: 1)` → `(a: 1)`).
    let se = serialize_pair_error(l, r, pos);
    if (se != null) {
        throw se;
    }
    root.value.Value_Str {
        _0: root.value.SassStr { text: `${slash_repr(l)}/${slash_repr(r)}`, quoted: false },
    }
}

/// Real division of two numbers with dart-sass unit semantics: division never
/// errors on units — convertible units cancel (scaling the value), and
/// whatever remains becomes the quotient's numerator/denominator lists
/// (`math.div(1, 1px)` -> `1px^-1`, `math.div(1px, 1s)` -> `1px/s`).
function divide_numbers(
    a: root.value.Number,
    b: root.value.Number,
    unused_pos: root.scanner.Pos,
) -> root.value.Value {
    root.value.Value_Number { _0: a.div(b) }
}

/// The slash-spelling text of an operand: a slash value keeps its chained
/// `a/b` text; any other value uses its plain CSS form.
function slash_repr(v: root.value.Value) -> string {
    match (v) {
        root.value.Value_Slash { _0: _, _1: let repr } => repr,
        let other => other.to_css(false),
    }
}

function eval_binary(
    op: root.ast.BinOp,
    l: root.value.Value,
    r: root.value.Value,
    pos: root.scanner.Pos,
) -> root.value.Value {
    match (op) {
        root.ast.BinOp.Add => binary_add(l, r, pos),
        root.ast.BinOp.Sub => binary_sub(l, r, pos),
        root.ast.BinOp.Mod => {
            num_binop(l, r, pos, "%", (a: float, b: float) -> float {
                sass_modulo(a, b)
            })
        },
        root.ast.BinOp.Mul => binary_mul(l, r, pos),
        root.ast.BinOp.Eq => root.value.Value_Bool { _0: l.sass_eq(r) },
        root.ast.BinOp.Neq => root.value.Value_Bool { _0: !l.sass_eq(r) },
        // PORT: the comparison closures use the IEEE helpers (`a < b` is false
        // for NaN in Rust; BAML's float order is total).
        root.ast.BinOp.Lt => {
            num_compare(l, r, pos, "<", (a: float, b: float) -> bool {
                root.std.flt(a, b)
            })
        },
        root.ast.BinOp.Gt => {
            num_compare(l, r, pos, ">", (a: float, b: float) -> bool {
                root.std.fgt(a, b)
            })
        },
        root.ast.BinOp.Le => {
            num_compare(l, r, pos, "<=", (a: float, b: float) -> bool {
                root.std.fle(a, b)
            })
        },
        root.ast.BinOp.Ge => {
            num_compare(l, r, pos, ">=", (a: float, b: float) -> bool {
                root.std.fge(a, b)
            })
        },
        root.ast.BinOp.And | root.ast.BinOp.Or => {
            throw root.error.Error.unpositioned(
                "internal: and/or are short-circuited in eval_expr"
            );
        },
        // The single-`=` Microsoft-filter operator joins both evaluated sides
        // with `=` (no surrounding whitespace) into an unquoted string,
        // matching dart-sass (`alpha(opacity=80)` -> `alpha(opacity=80)`).
        root.ast.BinOp.SingleEq => {
            root.value.Value_Str {
                _0: root.value.SassStr { text: `${l.to_css(false)}=${r.to_css(false)}`, quoted: false },
            }
        },
    }
}

function num_compare(
    l: root.value.Value,
    r: root.value.Value,
    pos: root.scanner.Pos,
    sym: string,
    f: (float, float) -> bool throws unknown,
) -> root.value.Value {
    // PORT: `match (l, r)` → nested `if let`s; the fall-through is the `(l, r)` arm.
    if let root.value.Value_Number { _0: let a } = l {
        if let root.value.Value_Number { _0: let b } = r {
            let t = coerce_pair(a, b, pos);
            let av = t._0;
            let bv = t._1;
            return root.value.Value_Bool { _0: f(av, bv) };
        }
    }
    throw undefined_op(l, sym, r, pos);
}

function binary_add(
    l: root.value.Value,
    r: root.value.Value,
    pos: root.scanner.Pos,
) -> root.value.Value {
    if let root.value.Value_Number { _0: let a } = l {
        if let root.value.Value_Number { _0: let b } = r {
            let t = coerce_pair(a, b, pos);
            let av = t._0;
            let bv = t._1;
            let proto = t._2;
            return root.value.Value_Number { _0: proto.copy_units(av + bv) };
        }
    }
    // dart-sass removed color arithmetic: `color + color`/`color + number`
    // (either order) is "Undefined operation", not string concatenation.
    if (color_arith_undefined(l, r)) {
        throw undefined_op(l, "+", r, pos);
    }
    let e = callable_value_error(l, r, pos);
    if (e != null) {
        throw e;
    }
    // A calculation can only be `+`-concatenated with a string; against any
    // other operand (number, color, bool, list, another calculation) dart-sass
    // raises "Undefined operation" rather than string-concatenating.
    let calc_with_nonstring = (l is root.value.Value_Calc && !(r is root.value.Value_Str))
        || (r is root.value.Value_Calc && !(l is root.value.Value_Str));
    if (calc_with_nonstring) {
        throw undefined_op(l, "+", r, pos);
    }
    // A map or empty list cannot be serialized for string concatenation, so
    // `map + x` / `() + x` errors like dart-sass with "(…) isn't a valid CSS
    // value." (`1 + ()` → `()`, `1 + (a: 1)` → `(a: 1)`).
    let se = serialize_pair_error(l, r, pos);
    if (se != null) {
        throw se;
    }
    // String concatenation. When the left operand is a string the result keeps
    // the left string's quotedness; for any other left operand dart-sass's
    // default `Value.plus` quotes the result iff the right operand is a quoted
    // string (`1 + "x"` -> `"1x"`, `red + "x"` -> `"redx"`).
    let quoted = match (l) {
        root.value.Value_Str { _0: let s } => s.quoted,
        _ => match (r) {
            root.value.Value_Str { _0: let s } if s.quoted => true,
            _ => false,
        },
    };
    let text = `${concat_str(l)}${concat_str(r)}`;
    root.value.Value_Str { _0: root.value.SassStr { text: text, quoted: quoted } }
}

/// The `-` (minus) operator. Two numbers subtract numerically (coercing to a
/// common unit); for any other operand pair dart-sass falls back to its
/// default `Value.minus`, an *unquoted* string join `<left>-<right>` where each
/// side keeps its own serialization (so quoted strings keep their quotes:
/// `"q" - 1` -> `"q"-1`). A `calc()` value has no `minus` overload and errors,
/// and a map cannot serialize as a CSS value.
function binary_sub(
    l: root.value.Value,
    r: root.value.Value,
    pos: root.scanner.Pos,
) -> root.value.Value {
    if let root.value.Value_Number { _0: let a } = l {
        if let root.value.Value_Number { _0: let b } = r {
            let t = coerce_pair(a, b, pos);
            let av = t._0;
            let bv = t._1;
            let proto = t._2;
            return root.value.Value_Number { _0: proto.copy_units(av - bv) };
        }
    }
    // Removed color arithmetic: `color - color`/`color - number` (either
    // order) is "Undefined operation", not a string join.
    if (color_arith_undefined(l, r)) {
        throw undefined_op(l, "-", r, pos);
    }
    let e = callable_value_error(l, r, pos);
    if (e != null) {
        throw e;
    }
    if (l is root.value.Value_Calc || r is root.value.Value_Calc) {
        throw undefined_op(l, "-", r, pos);
    }
    let se = serialize_pair_error(l, r, pos);
    if (se != null) {
        throw se;
    }
    let text = `${l.to_css(false)}-${r.to_css(false)}`;
    root.value.Value_Str { _0: root.value.SassStr { text: text, quoted: false } }
}

function binary_mul(
    l: root.value.Value,
    r: root.value.Value,
    pos: root.scanner.Pos,
) -> root.value.Value {
    // PORT: `match (l, r)` → nested `if let`s; the fall-through is the `(l, r)` arm.
    // Units multiply per dart-sass: convertible numerator/denominator
    // pairs cancel, the rest concatenate (`1px * 1em` -> `1px*em`,
    // serialized as `calc(1px * 1em)`).
    if let root.value.Value_Number { _0: let a } = l {
        if let root.value.Value_Number { _0: let b } = r {
            return root.value.Value_Number { _0: a.mul(b) };
        }
    }
    throw undefined_op(l, "*", r, pos);
}

/// Sass modulo (dart `moduloLikeSass`): a floored modulo whose result takes
/// the divisor's sign. `1.2 % -4.7 == -3.5`, `-1.2 % 4.7 == 3.5`. An
/// infinite dividend (or a zero divisor) yields NaN; an infinite DIVISOR
/// returns the dividend when their signs agree (`1px % infinity*1px == 1px`,
/// signed zeros included) and NaN otherwise.
function sass_modulo(a: float, b: float) -> float {
    if (a.is_infinite()) {
        return root.std.F64_NAN();
    }
    if (b.is_infinite()) {
        // dart compares signIncludingZero, so `-0.0 % -infinity` is `-0.0`.
        return if (root.std.is_sign_negative(a) == root.std.is_sign_negative(b)) {
            a
        } else {
            root.std.F64_NAN()
        };
    }
    if (root.std.feq(b, 0.0)) {
        return root.std.F64_NAN();
    }
    a - b * (a / b).floor()
}

function num_binop(
    l: root.value.Value,
    r: root.value.Value,
    pos: root.scanner.Pos,
    sym: string,
    f: (float, float) -> float throws unknown,
) -> root.value.Value {
    // PORT: `match (l, r)` → nested `if let`s; the fall-through is the `(l, r)` arm.
    if let root.value.Value_Number { _0: let a } = l {
        if let root.value.Value_Number { _0: let b } = r {
            let t = coerce_pair(a, b, pos);
            let av = t._0;
            let bv = t._1;
            let proto = t._2;
            return root.value.Value_Number { _0: proto.copy_units(f(av, bv)) };
        }
    }
    throw undefined_op(l, sym, r, pos);
}

/// Coerce two numbers onto common units for `+`, `-`, `%`, and comparison.
/// The result keeps the LEFT operand's units; the right operand is converted
/// into them (`1in + 1cm` → both in inches, result `in`). When exactly one
/// operand is unitless the other's units are adopted with no rescaling
/// (`5 + 1px` → `6px`). Incompatible units error, matching dart-sass's
/// `<a> and <b> have incompatible units.` (a multi-unit operand prints in its
/// calc form there).
///
/// Returns `(left_value, right_value, prototype)` with both values expressed
/// in the prototype's units (build the result via `prototype.copy_units(..)`).
function coerce_pair(
    a: root.value.Number,
    b: root.value.Number,
    pos: root.scanner.Pos,
) -> root.std.Tuple3<float, float, root.value.Number> {
    // PORT: the `incompatible` closure returns the error; call sites `throw` it.
    let incompatible = () -> root.error.Error {
        root.error.Error.at(
            `${a.to_css(false)} and ${b.to_css(false)} have incompatible units.`,
            pos,
        )
    };
    // A multi-unit operand coerces via full unit-list matching.
    if (a.has_complex_units() || b.has_complex_units()) {
        if (b.is_unitless()) {
            return root.std.Tuple3 { _0: a.value, _1: b.value, _2: a };
        }
        if (a.is_unitless()) {
            return root.std.Tuple3 { _0: a.value, _1: b.value, _2: b };
        }
        let lists_factor = root.value.unit_lists_factor(
            root.std.Tuple2 { _0: b.numer_units(), _1: b.denom_units() },
            root.std.Tuple2 { _0: a.numer_units(), _1: a.denom_units() },
        );
        return match (lists_factor) {
            let factor: float => root.std.Tuple3 { _0: a.value, _1: b.value * factor, _2: a },
            null => {
                throw incompatible();
            },
        };
    }
    // Identical units (exact strings, like dart) or a unitless operand never
    // need a numeric conversion.
    if (a.unit() == b.unit() || b.is_unitless()) {
        return root.std.Tuple3 { _0: a.value, _1: b.value, _2: a };
    }
    if (a.is_unitless()) {
        return root.std.Tuple3 { _0: a.value, _1: b.value, _2: b };
    }
    // Two distinct real units: convert the right into the left's unit.
    match (root.value.convert_factor(b.unit(), a.unit())) {
        let factor: float => root.std.Tuple3 { _0: a.value, _1: b.value * factor, _2: a },
        null => {
            throw incompatible();
        },
    }
}

function concat_str(v: root.value.Value) -> string {
    match (v) {
        root.value.Value_Str { _0: let s } => s.text,
        let other => other.to_css(false),
    }
}

/// Whether a `+`/`-` operation is the removed color arithmetic that dart-sass
/// rejects with "Undefined operation": a color combined with another color or a
/// number. A color with a string (or other type) still string-concatenates via
/// the default `Value.plus`/`Value.minus`.
function color_arith_undefined(l: root.value.Value, r: root.value.Value) -> bool {
    let numeric = (v: root.value.Value) -> bool {
        v is root.value.Value_Color || v is root.value.Value_Number
    };
    (l is root.value.Value_Color && numeric(r)) || (r is root.value.Value_Color && numeric(l))
}

/// A map or empty list cannot be serialized into the unquoted `left<op>right`
/// string that dart-sass's default `Value.plus`/`minus`/`dividedBy` build, so
/// such an operand makes the whole `+`/`-`/`/` join an error — checking the
/// left operand before the right, exactly as dart's left-then-right
/// serialization order surfaces it (`() / 1` → `()`, `1 / (a: 1)` → `(a: 1)`).
function serialize_pair_error(
    l: root.value.Value,
    r: root.value.Value,
    pos: root.scanner.Pos,
) -> root.error.Error? {
    let msg = root.eval.css_value_error_msg(l) ?? root.eval.css_value_error_msg(r);
    if (msg != null) {
        root.error.Error.at(msg, pos)
    } else {
        null
    }
}

/// A first-class function or mixin reference is not a valid CSS value, so it
/// cannot appear in arithmetic or a slash: dart-sass errors "<inspect> isn't a
/// valid CSS value." for the first such operand (left before right).
function callable_value_error(
    l: root.value.Value,
    r: root.value.Value,
    pos: root.scanner.Pos,
) -> root.error.Error? {
    for (let v in [l, r]) {
        let inspect: string? = match (v) {
            root.value.Value_Function { _0: let f } => f.inspect(),
            root.value.Value_Mixin { _0: let m } => m.inspect(),
            _ => null,
        };
        if (inspect != null) {
            return root.error.Error.at(`${inspect} isn't a valid CSS value.`, pos);
        }
    }
    null
}

function undefined_op(
    l: root.value.Value,
    sym: string,
    r: root.value.Value,
    pos: root.scanner.Pos,
) -> root.error.Error {
    root.error.Error.at(`Undefined operation "${l.to_css(false)} ${sym} ${r.to_css(false)}".`, pos)
}
