// Ported from sasso `src/builtins/math.rs` (namespace `root.builtins.math`).
//
// Math built-in functions.
//
// Unary unit-preserving ops (`abs`, `ceil`, `floor`, `round`), the
// variadic bounds functions (`min`, `max`, `clamp`), powers/roots/logs
// (`pow`, `sqrt`, `exp`, `log`), trigonometry (`sin`, `cos`, `tan`,
// `asin`, `acos`, `atan`, `atan2`), `hypot`, `sign`, and the stepped
// remainders (`rem`, `mod`). Each is unit-checked and byte-matched to
// dart-sass.
//
// `min`/`max`/`clamp` reduce to a single number only when every argument
// is a compatible-unit number; otherwise they fall back to a preserved CSS
// `min()`/`max()`/`clamp()` call (so `min(1px, 2vw)` round-trips).
//
// Shared argument helpers live in the parent module. Return
// `Some(Ok(..))`/`Some(Err(..))` for a name this family owns, or `None`
// to let the next family try.

/// The names the math family owns (the single source of truth, mirroring the
/// `unary_op` set plus the `try_call` match arms below). The math family
/// lowercases the name before dispatch (so `SiN` folds to `sin`), so these are
/// the *lowercase* names; `is_builtin` lowercases before testing membership.
function NAMES() -> string[] {
    [
        // `unary_op`
        "abs",
        "ceil",
        "floor", // `try_call` match arms
        "round",
        "min",
        "max",
        "clamp",
        "sign",
        "pow",
        "sqrt",
        "exp",
        "log",
        "hypot",
        "sin",
        "cos",
        "tan",
        "asin",
        "acos",
        "atan",
        "atan2",
        "rem",
        "mod",
        "random",
    ]
}

function try_call(
    name: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> (root.std.Ok<root.value.Value> | root.std.Err<root.error.Error>)? {
    // The math functions double as CSS calculation functions, which dart-sass
    // matches case-insensitively (`SiN(1deg)` folds to `sin(1deg)`). Lowercase
    // the name once and dispatch on that; every name this family owns is
    // unambiguous, so this can never steal a name from another family.
    let lname = root.std.ascii_lower(name);
    let name = lname;
    // Simple unit-preserving unary ops.
    let op = unary_op(name);
    if (op != null) {
        let op_fn: (float) -> float throws unknown = op;
        return result_of(() -> {
            unary(pos_args, named, pos, op_fn)
        });
    }
    // PORT: each `Some(f(..))` arm keeps the `Result` as a value via
    // `result_of` (see below).
    match (name) {
        "round" => {
            result_of(() -> {
                round(pos_args, named, pos)
            })
        },
        "min" => {
            result_of(() -> {
                min_max(name, pos_args, named, pos, true)
            })
        },
        "max" => {
            result_of(() -> {
                min_max(name, pos_args, named, pos, false)
            })
        },
        "clamp" => {
            result_of(() -> {
                clamp(pos_args, named, pos)
            })
        },
        "sign" => {
            result_of(() -> {
                sign(pos_args, named, pos)
            })
        },
        "pow" => {
            result_of(() -> {
                pow(pos_args, named, pos)
            })
        },
        "sqrt" => {
            result_of(() -> {
                unitless_unary("number", pos_args, named, pos, (v: float) -> float {
                    v.sqrt()
                })
            })
        },
        "exp" => {
            result_of(() -> {
                unitless_unary("number", pos_args, named, pos, (v: float) -> float {
                    v.exp()
                })
            })
        },
        "log" => {
            result_of(() -> {
                log(pos_args, named, pos)
            })
        },
        "hypot" => {
            result_of(() -> {
                hypot(pos_args, named, pos)
            })
        },
        "sin" => {
            result_of(() -> {
                trig(pos_args, named, pos, (v: float) -> float {
                    v.sin()
                })
            })
        },
        "cos" => {
            result_of(() -> {
                trig(pos_args, named, pos, (v: float) -> float {
                    v.cos()
                })
            })
        },
        "tan" => {
            result_of(() -> {
                trig(pos_args, named, pos, (v: float) -> float {
                    v.tan()
                })
            })
        },
        "asin" => {
            result_of(() -> {
                inverse_trig(pos_args, named, pos, (v: float) -> float {
                    v.asin()
                })
            })
        },
        "acos" => {
            result_of(() -> {
                inverse_trig(pos_args, named, pos, (v: float) -> float {
                    v.acos()
                })
            })
        },
        "atan" => {
            result_of(() -> {
                inverse_trig(pos_args, named, pos, (v: float) -> float {
                    v.atan()
                })
            })
        },
        "atan2" => {
            result_of(() -> {
                atan2(pos_args, named, pos)
            })
        },
        "rem" => {
            result_of(() -> {
                remainder("rem", pos_args, named, pos, true)
            })
        },
        "mod" => {
            result_of(() -> {
                remainder("mod", pos_args, named, pos, false)
            })
        },
        "random" => {
            result_of(() -> {
                random(pos_args, named, pos)
            })
        },
        _ => null,
    }
}

/// PORT: helper for `try_call`'s `Some(f(..))`: runs a `Result`-returning
/// builtin and keeps the outcome as a value (`Ok(v)` / `Err(e)`), catching only
/// the compiler `Error` the Rust `Result` carries.
function result_of(
    f: () -> root.value.Value throws unknown,
) -> root.std.Ok<root.value.Value> | root.std.Err<root.error.Error> {
    let v = f() catch (e) {
        let err: root.error.Error => {
            return root.std.Err<root.error.Error> { error: err };
        }
    };
    root.std.Ok<root.value.Value> { value: v }
}

function unary_op(name: string) -> ((float) -> float throws unknown)? {
    let f: (float) -> float throws unknown = match (name) {
        "abs" => {
            (v: float) -> float {
                v.abs()
            }
        },
        "ceil" => {
            (v: float) -> float {
                ceil_int(v)
            }
        },
        "floor" => {
            (v: float) -> float {
                floor_int(v)
            }
        },
        _ => {
            return null;
        },
    };
    f
}

/// A rounding RESULT is an int in dart, so it is never a negative zero:
/// `math.round(-0.4)`, `math.ceil(-0.4)` and `round(to-zero, -0.4, 1)` are all
/// `0`, where IEEE rounding gives `-0`. Two neighbours are NOT covered by
/// that: `math.abs(-0)` is `0` because IEEE `abs` clears the sign of its own
/// accord (dart's answer too), while `round()` with an INFINITE step returns
/// the input's sign unrounded, so `round(to-zero, -0.4, infinity)` IS `-0` —
/// it never reaches the multiply below. Everything else keeps the sign:
/// `math.div(0, -1)` and `math.sqrt(-0)` are negative zeros.
function int_result(v: float) -> float {
    if (v == 0.0) {
        0.0
    } else {
        v
    }
}

function ceil_int(v: float) -> float {
    int_result(v.ceil())
}

function floor_int(v: float) -> float {
    int_result(v.floor())
}

/// `math.div($number1, $number2)`: true division. Unlike the `/` operator it
/// always divides (never produces a slash-separated value for two numbers),
/// reusing the evaluator's division so unit handling matches exactly.
function module_div(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["number1", "number2"];
    check_max_args(pos_args, named, 2, pos);
    let a = root.builtins.require(params, pos_args, named, 0, pos);
    let b = root.builtins.require(params, pos_args, named, 1, pos);
    // PORT: `crate::eval::eval_div` is the re-export of `eval::binop::eval_div`.
    root.eval.binop.eval_div(a, b, false, pos)
}

/// Reject a call with more POSITIONAL arguments than a fixed-arity function
/// accepts; named ones do not count toward the limit. `max_args` is the
/// function's declared arity. See [`super::check_arity`] for the wording rules
/// (singular/plural, and "positional" once a named argument is in play).
function check_max_args(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    max_args: int,
    pos: root.scanner.Pos,
) -> void {
    root.builtins.check_arity(max_args, pos_args, named, pos)
}

/// The rounding strategy keyword of a `round()` call's first argument.
enum RoundStrategy {
    Nearest,
    Up,
    Down,
    ToZero,
}

function RoundStrategy_from_str(s: string) -> RoundStrategy? {
    match (s) {
        "nearest" => RoundStrategy.Nearest,
        "up" => RoundStrategy.Up,
        "down" => RoundStrategy.Down,
        "to-zero" => RoundStrategy.ToZero,
        _ => null,
    }
}

/// `round()` as dart-sass's CSS `round()` calculation:
/// - `round(number)` — nearest, no step (half away from zero);
/// - `round(number, step)` — nearest with a step;
/// - `round(strategy, number, step)` — explicit strategy with a step.
///
/// Step is converted into the number's unit; non-finite operands and a zero
/// step follow the CSS spec (see `round_with_step`). Genuinely unsimplifiable
/// arguments (a `var()`, an unknown/incompatible unit pair, etc.) fall back to
/// a preserved `round(...)` form.
function round(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    // A named argument (`round($number: …)`) forces the legacy one-argument
    // `math.round`, which requires an actual number rather than the CSS
    // `round()` calculation's preserve-on-unsimplifiable behaviour. Any other
    // named-argument shape falls through to the positional handling below,
    // which reports the arity/name error.
    if (pos_args.length() == 0 && named.length() == 1 && named[0]._0 == "number") {
        let n = as_num(named[0]._1, pos);
        return num_value(n.copy_units(int_result(n.value.round())));
    }
    let args = all_args(pos_args, named);
    match (args.length()) {
        0 => {
            throw root.error.Error.at("Missing argument.", pos);
        },
        1 => {
            // One-argument form: nearest, unit preserved. An unsimplifiable
            // argument (a `var()`, interpolation, …) preserves the call.
            match (round_operand(args[0], pos)) {
                let n: root.value.Number => num_value(n.copy_units(int_result(n.value.round()))),
                null => preserved_round(args),
            }
        },
        2 => {
            // A bare strategy keyword as the first of two args means the step
            // is missing: that errors when the value is a real number, but an
            // unsimplifiable value (`round(up, var(--c))`) preserves the call
            // verbatim, matching dart-sass.
            if let s: root.value.Value_Str = args[0] {
                if (!s._0.quoted && RoundStrategy_from_str(root.std.ascii_lower(s._0.text)) != null) {
                    return match (round_operand(args[1], pos)) {
                        let _n: root.value.Number => {
                            throw root.error.Error.at("If strategy is not null, step is required.", pos);
                        },
                        null => preserved_round(args),
                    };
                }
            }
            if (
                args.some((a) -> {
                    is_quoted_str(a)
                })
            ) {
                throw root.error.Error.at("Only 1 argument allowed, but 2 were passed.", pos);
            }
            // `round(number, step)`: nearest with a step.
            let number = round_operand(args[0], pos);
            let step = round_operand(args[1], pos);
            // PORT: `match (number, step)` → nested `if let`s.
            if let number: root.value.Number = number {
                if let step: root.value.Number = step {
                    return round_with_step(RoundStrategy.Nearest, number, step, false, pos);
                }
            }
            preserved_round(args)
        },
        3 => {
            // The first argument must be a strategy keyword. A quoted string
            // can't be used in a calculation; any other non-strategy value is
            // a "must be either nearest, up, down or to-zero" error.
            let strategy: RoundStrategy = match (args[0]) {
                root.value.Value_Str { _0: let s } if !s.quoted => {
                    let st = RoundStrategy_from_str(root.std.ascii_lower(s.text));
                    if (st == null) {
                        // A non-strategy unquoted string (e.g. `var()`) leaves
                        // the whole call unsimplified.
                        return preserved_round(args);
                    }
                    st
                },
                root.value.Value_Str { _0: let s } => {
                    throw root.error.Error.at(`Value "${s.text}" can't be used in a calculation.`, pos);
                },
                let other => {
                    throw root.error.Error.at(`${other.to_css(false)} must be either nearest, up, down or to-zero.`, pos);
                },
            };
            let number = round_operand(args[1], pos);
            let step = round_operand(args[2], pos);
            // PORT: `match (number, step)` → nested `if let`s.
            if let number: root.value.Number = number {
                if let step: root.value.Number = step {
                    return round_with_step(strategy, number, step, true, pos);
                }
            }
            preserved_round(args)
        },
        let n => {
            throw root.error.Error.at(`Only 3 arguments allowed, but ${n} were passed.`, pos);
        },
    }
}

/// Whether a value is a quoted string (which can never be a calc operand).
function is_quoted_str(v: root.value.Value) -> bool {
    match (v) {
        root.value.Value_Str { _0: let s } if s.quoted => true,
        _ => false,
    }
}

/// Interpret a `round()` number/step operand. A plain number (or one of the
/// bare `infinity`/`-infinity`/`NaN`/`pi`/`e` constants, or a folded calc
/// number) yields `Some(n)`. An unquoted non-constant string — a `var()`, an
/// interpolation, a bare identifier — or a preserved calc yields `Ok(None)`,
/// meaning the call should be preserved verbatim. A quoted string can't be
/// used in a calculation and is an error.
function round_operand(v: root.value.Value, pos: root.scanner.Pos) -> root.value.Number? {
    match (v) {
        root.value.Value_Number { _0: let n } => n,
        root.value.Value_Calc { _0: root.value.CalcNode_Number { _0: let n } } => n,
        root.value.Value_Str { _0: let s } if !s.quoted => const_number(s.text),
        root.value.Value_Calc {} => null,
        root.value.Value_Str { _0: let s } => {
            throw root.error.Error.at(`Value "${s.text}" can't be used in a calculation.`, pos);
        },
        let other => {
            throw root.error.Error.at(`Value ${other.to_css(false)} can't be used in a calculation.`, pos);
        },
    }
}

/// dart-sass's `_roundWithStep`: round `number` to a multiple of `step`
/// (converted into `number`'s unit) under `strategy`, handling non-finite
/// operands and a zero step exactly as the CSS spec requires.
function round_with_step(
    strategy: RoundStrategy,
    number: root.value.Number,
    step: root.value.Number,
    explicit: bool,
    pos: root.scanner.Pos,
) -> root.value.Value {
    let unit = number.unit();
    let with_unit = (value: float) -> root.value.Value {
        num_value(root.value.Number.with_unit(value, unit))
    };
    // Coerce the step into the number's unit; an incompatible pair preserves
    // the call (a real/unitless or known cross-dimension mix errors, matching
    // the two-argument unit rules).
    let step_v = match (coerce_step(step, number, pos)) {
        StepCoercion_Value { _0: let v } => v,
        StepCoercion_Preserve {} => {
            return preserved_round_nums(strategy, number, step, explicit);
        },
        StepCoercion_Error { _0: let e } => {
            throw e;
        },
        _ => root.std.unreachable(),
    };

    let nv = number.value;
    // NaN when number and step are both infinite, or step is 0, or either is
    // NaN.
    if ((nv.is_infinite() && step_v.is_infinite()) || step_v == 0.0 || nv.is_nan() || step_v.is_nan()) {
        return with_unit(root.std.F64_NAN());
    }
    // An infinite number rounds to itself.
    if (nv.is_infinite()) {
        return with_unit(nv);
    }
    // An infinite step collapses to a signed zero / signed infinity by
    // strategy and sign.
    if (step_v.is_infinite()) {
        if (nv == 0.0) {
            return with_unit(nv);
        }
        // PORT: `-0.0` literals → `root.std.NEG_ZERO()` (BAML merges `-0.0`
        // and `0.0` constants within one function).
        let value = match (strategy) {
            RoundStrategy.Nearest | RoundStrategy.ToZero => {
                if (nv > 0.0) {
                    0.0
                } else {
                    root.std.NEG_ZERO()
                }
            },
            RoundStrategy.Up => {
                if (nv > 0.0) {
                    root.std.F64_INFINITY()
                } else {
                    root.std.NEG_ZERO()
                }
            },
            RoundStrategy.Down => {
                if (nv < 0.0) {
                    root.std.F64_NEG_INFINITY()
                } else {
                    0.0
                }
            },
        };
        return with_unit(value);
    }

    let q = nv / step_v;
    let rounded = match (strategy) {
        RoundStrategy.Nearest => q.round(),
        RoundStrategy.Up => {
            if (step_v < 0.0) {
                q.floor()
            } else {
                q.ceil()
            }
        },
        RoundStrategy.Down => {
            if (step_v < 0.0) {
                q.ceil()
            } else {
                q.floor()
            }
        },
        RoundStrategy.ToZero => {
            if (nv < 0.0) {
                q.ceil()
            } else {
                q.floor()
            }
        },
    };
    with_unit(int_result(rounded * step_v))
}

/// The outcome of coercing a `round()` step into the number's unit.
interface StepCoercion {}

class StepCoercion_Value {
    _0: float,
    implements StepCoercion {}
}

class StepCoercion_Preserve {
    implements StepCoercion {}
}

class StepCoercion_Error {
    _0: root.error.Error,
    implements StepCoercion {}
}

/// dart-sass `_verifyCompatibleNumbers`: a number with complex units cannot
/// ride into a preserved (unsimplified) CSS calculation — it is rejected with
/// its calc-form spelling ("Number calc(2px * 1px) isn't compatible with CSS
/// calculations.").
function verify_no_complex_units(numbers: root.value.Number[], pos: root.scanner.Pos) -> void {
    for (let n in numbers) {
        if (n.has_complex_units()) {
            throw root.error.Error.at(`Number ${n.to_css(false)} isn't compatible with CSS calculations.`, pos);
        }
    }
}

/// [`verify_no_complex_units`] over a `Value` slice (only numbers checked).
function verify_no_complex_args(args: root.value.Value[], pos: root.scanner.Pos) -> void {
    for (let v in args) {
        if let n: root.value.Value_Number = v {
            verify_no_complex_units([n._0], pos);
        }
    }
}

/// Coerce `step` into `number`'s unit for `round()`. Equal/convertible units
/// combine; a relative/unknown unit pair preserves the call; a real-vs-unitless
/// or known cross-dimension mix is an error (matching dart-sass). A multi-unit
/// operand combines only with convertible unit lists; otherwise it is the
/// "isn't compatible with CSS calculations." rejection.
function coerce_step(
    step: root.value.Number,
    number: root.value.Number,
    pos: root.scanner.Pos,
) -> StepCoercion {
    if (step.has_complex_units() || number.has_complex_units()) {
        let factor = root.value.unit_lists_factor(
            root.std.Tuple2<string[], string[]> { _0: step.numer_units(), _1: step.denom_units() },
            root.std.Tuple2<string[], string[]> {
                _0: number.numer_units(),
                _1: number.denom_units(),
            },
        );
        if (factor != null) {
            return StepCoercion_Value { _0: step.value * factor };
        }
        // PORT: `match verify_no_complex_units(..) { Err(e) => .., Ok(()) => .. }`
        // → catch the `Error` as a value.
        verify_no_complex_units([number, step], pos) catch (e) {
            let err: root.error.Error => {
                return StepCoercion_Error { _0: err };
            }
        };
        // Unreachable: one operand is known complex.
        return StepCoercion_Preserve {  };
    }
    if (root.std.eq_ignore_ascii_case(step.unit(), number.unit())) {
        return StepCoercion_Value { _0: step.value };
    }
    if (step.is_unitless() && number.is_unitless()) {
        return StepCoercion_Value { _0: step.value };
    }
    // A unitless operand mixed with a real unit is incompatible.
    if (step.is_unitless() != number.is_unitless()) {
        return StepCoercion_Error { _0: incompatible(number, step, pos) };
    }
    let factor = root.value.convert_factor(step.unit(), number.unit());
    if (factor != null) {
        return StepCoercion_Value { _0: step.value * factor };
    }
    if (root.value.calc_units_incompatible(number.unit(), step.unit())) {
        return StepCoercion_Error { _0: incompatible(number, step, pos) };
    }
    StepCoercion_Preserve {  }
}

/// Coerce `n` into `target`'s unit for the binary/variadic math functions
/// (`atan2`, `hypot`, `mod`, `rem`), which behave like `calc()`:
/// equal/convertible units combine; a real-vs-unitless or known
/// cross-dimension mix is an error; any pair involving an unknown/relative
/// unit (`%`, `foo`, `vw`) that can't be converted preserves the whole call.
/// (Identical rules to [`coerce_step`], reused via the same outcome enum.)
function combine_into(
    n: root.value.Number,
    target: root.value.Number,
    pos: root.scanner.Pos,
) -> StepCoercion {
    coerce_step(n, target, pos)
}

/// Build the preserved `round(...)` form over the original arguments (for an
/// argument that cannot be simplified to a number, e.g. a `var()`).
function preserved_round(args: root.value.Value[]) -> root.value.Value {
    preserved_call("round", args)
}

/// Build the preserved `round(strategy, number, step)` form when the operands
/// are numbers but their units keep the call from simplifying. The strategy
/// keyword is emitted whenever it was authored explicitly (the three-argument
/// form), or for any non-`nearest` strategy; the implicit-`nearest`
/// two-argument form preserves as `round(number, step)`, matching dart-sass.
///
/// The result is a CALCULATION, like every other preserved call: `[measured]`
/// against dart-sass 1.104.1, `meta.type-of(round(1px, 2bar))` is
/// `calculation`, and compressed output drops the space after each comma
/// (`round(1px,2bar)`) — which a preserved unquoted string could not do,
/// because it carries one spelling for both styles.
function preserved_round_nums(
    strategy: RoundStrategy,
    number: root.value.Number,
    step: root.value.Number,
    explicit: bool,
) -> root.value.Value {
    let kw = match (strategy) {
        RoundStrategy.Nearest => "nearest",
        RoundStrategy.Up => "up",
        RoundStrategy.Down => "down",
        RoundStrategy.ToZero => "to-zero",
    };
    let args: root.value.CalcNode[] = [];
    if (strategy != RoundStrategy.Nearest || explicit) {
        args.push(root.value.CalcNode_Str { _0: kw });
    }
    args.push(root.value.CalcNode_Number { _0: number });
    args.push(root.value.CalcNode_Number { _0: step });
    root.value.Value_Calc { _0: root.value.CalcNode_Func { name: "round", args: args } }
}

/// Apply a unit-preserving unary numeric operation, requiring a number.
function unary(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
    op: (float) -> float throws unknown,
) -> root.value.Value {
    check_max_args(pos_args, named, 1, pos);
    let n = require_num(["number"], pos_args, named, 0, pos);
    num_value(n.copy_units(op(n.value)))
}

/// `sign(x)`: -1, 0, or 1, with the operand's full units (also for zero) —
/// dart-sass `SassNumber(value.sign).coerceToMatch(arg)`. `±0`/NaN pass
/// through as themselves (`1 / sign(-0.0)` is `-infinity`); a `%` operand
/// can't simplify (its sign could flip after resolution against the unknown
/// reference value), so the call is preserved.
function sign(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    check_max_args(pos_args, named, 1, pos);
    let n = require_num(["number"], pos_args, named, 0, pos);
    if (
        n.numer_units().some((u) -> {
            u == "%"
        })
    ) {
        return preserved_call("sign", all_args(pos_args, named));
    }
    // PORT: IEEE comparisons (`root.std.fgt/flt`) so a NaN falls through to
    // itself as in Rust.
    let s = if (root.std.fgt(n.value, 0.0)) {
        1.0
    } else if (root.std.flt(n.value, 0.0)) {
        -1.0
    } else {
        n.value
    };
    num_value(n.copy_units(s))
}

/// `pow(base, exp)`: both operands must be unitless; result is unitless.
function pow(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    check_max_args(pos_args, named, 2, pos);
    let base = require_num(["base", "exponent"], pos_args, named, 0, pos);
    let exp = require_num(["base", "exponent"], pos_args, named, 1, pos);
    no_unit(base, pos);
    no_unit(exp, pos);
    unitless(base.value.pow(exp.value))
}

/// A unitless unary op (`sqrt`, `exp`): the argument must have no units and
/// the result is unitless.
function unitless_unary(
    param: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
    op: (float) -> float throws unknown,
) -> root.value.Value {
    check_max_args(pos_args, named, 1, pos);
    let n = require_num([param], pos_args, named, 0, pos);
    no_unit(n, pos);
    unitless(op(n.value))
}

/// `log(x)` (natural) or `log(x, base)`. Both operands must be unitless.
function log(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    check_max_args(pos_args, named, 2, pos);
    let params = ["number", "base"];
    let x = require_num(params, pos_args, named, 0, pos);
    no_unit(x, pos);
    // PORT: `Some(b) if !matches!(b, Value::Null) => …, _ => …` → the explicit
    // `null` arm first (a guard cannot hold an `is` test).
    match (root.builtins.arg(params, pos_args, named, 1)) {
        // An explicit `null` base means the natural logarithm (dart-sass).
        root.value.Value_Null {} => unitless(x.value.ln()),
        let b: root.value.Value => {
            let b = as_num(b, pos);
            no_unit(b, pos);
            unitless(x.value.ln() / b.value.ln())
        },
        _ => unitless(x.value.ln()),
    }
}

/// `hypot(a, b, ...)`: sqrt of the sum of squares, with unit coercion onto
/// the first argument's unit (`hypot(3px, 4cm)` converts cm to px). Coercion
/// follows the `calc()` rules: a real-vs-unitless or known cross-dimension mix
/// is an error, while an unknown/relative-unit pair that can't be converted
/// preserves the whole call verbatim (`hypot(1%, 2%)`).
function hypot(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let nums = collect_nums(pos_args, named, pos);
    let first = match (nums.at(0)) {
        let n: root.value.Number => n,
        null => {
            throw root.error.Error.at("At least one argument must be passed.", pos);
        },
    };
    // A complex-unit operand is rejected even alone (`hypot(-7px / 4em)` ->
    // "Number calc(-1.75px / 1em) isn't compatible with CSS calculations.").
    verify_no_complex_units(nums, pos);
    // A `%` operand makes the result context-dependent, so dart-sass preserves
    // the call rather than folding (`hypot(1%, 2%)`, `hypot(1%, 2px)`).
    if (
        nums.some((n) -> {
            is_percent(n)
        })
    ) {
        let args: root.value.Value[] = nums.map((n) -> root.value.Value {
            root.value.Value_Number { _0: n }
        });
        return preserved_call("hypot", args);
    }
    let sum = 0.0;
    for (let n in nums) {
        match (combine_into(n, first, pos)) {
            StepCoercion_Value { _0: let v } => {
                sum += v * v;
            },
            StepCoercion_Preserve {} => {
                let args: root.value.Value[] = nums.map((n) -> root.value.Value {
                    root.value.Value_Number { _0: n }
                });
                return preserved_call("hypot", args);
            },
            StepCoercion_Error { _0: let e } => {
                throw e;
            },
            _ => root.std.unreachable(),
        };
    }
    num_value(first.copy_units(sum.sqrt()))
}

/// `sin`/`cos`/`tan`: accept an angle (`deg`/`grad`/`rad`/`turn`) or a
/// unitless number treated as radians; return a unitless number.
function trig(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
    op: (float) -> float throws unknown,
) -> root.value.Value {
    check_max_args(pos_args, named, 1, pos);
    let n = require_num(["number"], pos_args, named, 0, pos);
    let radians = angle_to_radians(n, pos);
    unitless(op(radians))
}

/// `asin`/`acos`/`atan`: the argument must be unitless; the result is in
/// degrees.
function inverse_trig(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
    op: (float) -> float throws unknown,
) -> root.value.Value {
    check_max_args(pos_args, named, 1, pos);
    let n = require_num(["number"], pos_args, named, 0, pos);
    no_unit(n, pos);
    degrees(f64_to_degrees(op(n.value)))
}

/// PORT: Rust's `f64::to_degrees` (`x * (180 / π)`); BAML's `Float.to_degrees`
/// computes `x * 180 / π`, which can differ in the last bit.
function f64_to_degrees(x: float) -> float {
    x * (180.0 / root.std.F64_PI())
}

/// `atan2(y, x)`: the two-argument arctangent, returned in degrees. The
/// operands are coerced together like `calc()`: a real-vs-unitless or known
/// cross-dimension mix is an error, while an unknown/relative-unit pair that
/// can't be converted preserves the call verbatim (`atan2(1%, 2%)`).
function atan2(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    check_max_args(pos_args, named, 2, pos);
    let params = ["y", "x"];
    let y = require_num(params, pos_args, named, 0, pos);
    let x = require_num(params, pos_args, named, 1, pos);
    // A complex-unit operand is rejected before the `%` preserve below.
    verify_no_complex_units([y, x], pos);
    // A `%` operand would produce a context-dependent result, so dart-sass
    // preserves the call rather than folding (`atan2(1%, 2%)`).
    if (is_percent(y) || is_percent(x)) {
        let args: root.value.Value[] = [root.value.Value_Number { _0: y }, root.value.Value_Number { _0: x }];
        return preserved_call("atan2", args);
    }
    let xv = match (combine_into(x, y, pos)) {
        StepCoercion_Value { _0: let v } => v,
        StepCoercion_Preserve {} => {
            let args: root.value.Value[] = [root.value.Value_Number { _0: y }, root.value.Value_Number { _0: x }];
            return preserved_call("atan2", args);
        },
        StepCoercion_Error { _0: let e } => {
            throw e;
        },
        _ => root.std.unreachable(),
    };
    degrees(f64_to_degrees(y.value.atan2(xv)))
}

/// Whether a number's unit is `%` (case-insensitive). The geometric functions
/// (`atan2`, `hypot`) preserve their call when any operand is a percentage,
/// since the result would be context-dependent.
function is_percent(n: root.value.Number) -> bool {
    n.unit() == "%"
}

/// `rem(a, b)` (truncated, sign of dividend) or `mod(a, b)` (floored, sign
/// of divisor). The divisor is coerced into the dividend's unit under the
/// `calc()` rules: a real-vs-unitless or known cross-dimension mix is an
/// error, while an unknown/relative-unit pair that can't be converted
/// preserves the call verbatim (`mod(1px, 2bar)`).
function remainder(
    fname: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
    truncated: bool,
) -> root.value.Value {
    check_max_args(pos_args, named, 2, pos);
    let params = ["dividend", "modulus"];
    let a = require_num(params, pos_args, named, 0, pos);
    let b = require_num(params, pos_args, named, 1, pos);
    let bv = match (combine_into(b, a, pos)) {
        StepCoercion_Value { _0: let v } => v,
        StepCoercion_Preserve {} => {
            let args: root.value.Value[] = [root.value.Value_Number { _0: a }, root.value.Value_Number { _0: b }];
            return preserved_call(fname, args);
        },
        StepCoercion_Error { _0: let e } => {
            throw e;
        },
        _ => root.std.unreachable(),
    };
    let value = if (bv == 0.0) {
        root.std.F64_NAN()
    } else if (truncated) {
        a.value % bv
    } else {
        a.value - bv * (a.value / bv).floor()
    };
    num_value(a.copy_units(value))
}

/// `min`/`max`: reduce all-numeric, compatible-unit arguments to the
/// smallest/largest (keeping the winning argument's own unit). If any
/// argument is a non-number or any pair of units is incompatible, fall back
/// to a preserved CSS `min()`/`max()` call over the evaluated arguments.
function min_max(
    fname: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
    is_min: bool,
) -> root.value.Value {
    let args: root.value.Value[] = all_args(pos_args, named).map((v) -> {
        normalize_const(v)
    });
    if (args.length() == 0) {
        throw root.error.Error.at("Missing argument.", pos);
    }
    match (reduce_min_max(args, is_min, pos)) {
        let n: root.value.Number => num_value(n),
        null => {
            verify_no_complex_args(args, pos);
            // The BUILTIN min/max (reached via a splat or meta.call — the
            // direct spelling parses as a CSS calculation upstream) requires
            // numbers: dart's math.min asserts every argument
            // ("blah is not a number."). Only calc-style substitutions
            // (var()/calc strings) keep the call preserved.
            let bad = args.find((v) -> {
                !(v is root.value.Value_Number) && !value_is_calc_substitution(v)
            });
            if (bad != null) {
                throw root.error.Error.at(`${bad.to_css(false)} is not a number.`, pos);
            }
            preserved_call(fname, args)
        },
    }
}

/// Whether a non-number min/max argument is a calc-style substitution that
/// keeps the call preserved (a `var()`/`calc()`/`env()` string or a nested
/// calculation) rather than a plain value dart's builtin rejects.
function value_is_calc_substitution(v: root.value.Value) -> bool {
    match (v) {
        root.value.Value_Calc {} => true,
        root.value.Value_Str { _0: let s } => {
            let t = root.std.ascii_lower(root.std.trim_start(s.text));
            t.starts_with("var(")
                || t.starts_with("calc(")
                || t.starts_with("env(")
                || t.starts_with("min(")
                || t.starts_with("max(")
                || t.starts_with("clamp(")
        },
        _ => false,
    }
}

/// `clamp(min, value, max)`. A single non-number argument is a preserved CSS
/// calculation (`clamp(var(--c))`); any other arity is an error. With three
/// numbers, dart-sass clamps `value` against `min`/`max` checking `min` first
/// (`value < min` → `min`; else `value > max` → `max`; else `value`), keeping
/// the winning argument's own unit. A known cross-dimension pair errors; an
/// unconvertible-but-not-incompatible pair (`clamp(1px, 2vw, 3px)`) preserves.
function clamp(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let args: root.value.Value[] = all_args(pos_args, named).map((v) -> {
        normalize_const(v)
    });
    if (args.length() == 1 && !(args[0] is root.value.Value_Number)) {
        // A lone `var()`, interpolation, or bare identifier is a preserved
        // CSS `clamp()` calculation rather than an arity error.
        return preserved_call("clamp", args);
    }
    if (args.length() != 3) {
        throw root.error.Error.at(`3 arguments required, but ${args.length()} were passed.`, pos);
    }
    // PORT: the tuple match `(Number(a), Number(b), Number(c))` → nested
    // matches producing a `Tuple3` (null for the `_` arm).
    let three: root.std.Tuple3<root.value.Number, root.value.Number, root.value.Number>? = match (args[0]) {
        root.value.Value_Number { _0: let a } => match (args[1]) {
            root.value.Value_Number { _0: let b } => match (args[2]) {
                root.value.Value_Number { _0: let c } => {
                    root.std.Tuple3<root.value.Number, root.value.Number, root.value.Number> {
                        _0: a,
                        _1: b,
                        _2: c,
                    }
                },
                _ => null,
            },
            _ => null,
        },
        _ => null,
    };
    if (three == null) {
        verify_no_complex_args(args, pos);
        return preserved_call("clamp", args);
    }
    let lo = three._0;
    let val = three._1;
    let hi = three._2;
    // Multi-unit arguments must be mutually convertible (dart
    // `isComparableTo`): the values compare in `min`'s units and the winning
    // argument is returned as-is (`clamp(1px*1px, 2px*2px, 3px*3px)` ->
    // `calc(4px * 1px)`); a non-convertible complex operand is rejected.
    if (lo.has_complex_units() || val.has_complex_units() || hi.has_complex_units()) {
        let coerce = (n: root.value.Number) -> float? {
            let f = root.value.unit_lists_factor(
                root.std.Tuple2<string[], string[]> { _0: n.numer_units(), _1: n.denom_units() },
                root.std.Tuple2<string[], string[]> { _0: lo.numer_units(), _1: lo.denom_units() },
            );
            if (f != null) {
                n.value * f
            } else {
                null
            }
        };
        // PORT: `match (coerce(val), coerce(hi))` → nested `if let`s.
        if let val_v: float = coerce(val) {
            if let hi_v: float = coerce(hi) {
                // PORT: IEEE comparisons (`root.std.flt/fgt`): a NaN operand
                // compares false as in Rust.
                let winner = if (root.std.flt(val_v, lo.value)) {
                    lo
                } else if (root.std.fgt(val_v, hi_v)) {
                    hi
                } else {
                    val
                };
                return num_value(winner);
            }
        }
        verify_no_complex_units([lo, val, hi], pos);
        // Unreachable: one operand is known complex.
        return preserved_call("clamp", args);
    }
    // A known cross-dimension pair (against `min`) is an error, matching
    // dart-sass; an unconvertible relative/unknown unit preserves the call.
    if (root.value.calc_units_incompatible(lo.unit(), val.unit())) {
        throw incompatible(lo, val, pos);
    }
    if (root.value.calc_units_incompatible(lo.unit(), hi.unit())) {
        throw incompatible(lo, hi, pos);
    }
    // Coerce `value` and `hi` into `lo`'s unit; preserve if any pair is not
    // convertible (but not a hard incompatibility, e.g. `1px`/`2vw`).
    let val_v = try_coerce(val, lo);
    if (val_v == null) {
        return preserved_call("clamp", args);
    }
    let hi_v = try_coerce(hi, lo);
    if (hi_v == null) {
        return preserved_call("clamp", args);
    }
    // dart-sass checks `min` before `max` (so `clamp(3, 5, 1)` is `1`, not the
    // CSS `max(min, min(value, max))` result), keeping the winner's own unit.
    // PORT: IEEE comparisons (`root.std.flt/fgt`): a NaN operand compares
    // false as in Rust.
    let winner = if (root.std.flt(val_v, lo.value)) {
        lo
    } else if (root.std.fgt(val_v, hi_v)) {
        hi
    } else {
        val
    };
    num_value(winner)
}

/// `math.round($number)`: the legacy single-argument numeric round (nearest,
/// unit preserved). dart-sass requires exactly one number; a non-number or
/// extra arguments are an error (unlike the global CSS `round()` calculation,
/// which accepts a rounding strategy and step and preserves unknown args).
function module_round(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    root.builtins.check_arity(1, pos_args, named, pos);
    let v = root.builtins.require(["number"], pos_args, named, 0, pos);
    let n = as_num(v, pos);
    num_value(n.copy_units(int_result(n.value.round())))
}

/// `math.min(...)` / `math.max(...)`: the numeric (not CSS-calc) reductions.
/// Every argument must be a number with a compatible unit; a non-number or a
/// non-convertible unit pair is an error (unlike the global `min`/`max`, which
/// preserve such calls as CSS calculations).
function module_min_max(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
    is_min: bool,
) -> root.value.Value {
    let args = all_args(pos_args, named);
    if (args.length() == 0) {
        throw root.error.Error.at("At least one argument must be passed.", pos);
    }
    // Every argument must be a number (dart-sass: "<v> is not a number.").
    for (let v in args) {
        if (!(v is root.value.Value_Number)) {
            throw root.error.Error.at(`${v.to_css(false)} is not a number.`, pos);
        }
    }
    match (reduce_min_max(args, is_min, pos)) {
        let n: root.value.Number => num_value(n),
        // All numbers but >1 cluster: a non-convertible unit pair is an error
        // for the numeric form. Find a representative incompatible pair.
        null => {
            let nums: root.value.Number[] = args.filter_map((v) -> {
                match (v) {
                    root.value.Value_Number { _0: let n } => n,
                    _ => null,
                }
            });
            let i = 0;
            while (i < nums.length()) {
                let a = nums[i];
                for (let b in nums.slice(i + 1, nums.length())) {
                    if (try_coerce(b, a) == null) {
                        throw incompatible(a, b, pos);
                    }
                }
                i += 1;
            }
            // Should be unreachable (a single cluster would have returned
            // `Some`); fall back to the first value.
            num_value(nums[0])
        },
    }
}

/// `math.clamp($min, $number, $max)`: the numeric (not CSS-calc) clamp. All
/// three arguments must be numbers with compatible units (mixing a unitless
/// value with a real unit is an error). dart-sass: `min >= max` → `min`;
/// `number <= min` → `min`; `number >= max` → `max`; otherwise `number`,
/// keeping the winning argument's own unit.
function module_clamp(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["min", "number", "max"];
    root.builtins.check_arity(params.length(), pos_args, named, pos);
    let want = (i: int, label: string) -> root.value.Number {
        let v = root.builtins.require(params, pos_args, named, i, pos);
        match (v) {
            root.value.Value_Number { _0: let n } => n,
            let other => {
                throw root.error.Error.at(`$${label}: ${other.to_css(false)} is not a number.`, pos);
            },
        }
    };
    let min = want(0, "min");
    let number = want(1, "number");
    let max = want(2, "max");
    // Coerce `number` and `max` into `min`'s unit; mixing unitless with a real
    // unit (or a hard cross-dimension pair) is an error.
    let number_v = coerce_for_clamp(min, number, "min", "number", pos);
    let max_v = coerce_for_clamp(min, max, "min", "max", pos);
    // dart-sass precedence: an inverted range or a value at/below `min` yields
    // `min`; a value at/above `max` yields `max`; otherwise the value itself.
    // Both boundary checks are inclusive.
    // PORT: IEEE comparisons (`root.std.fge/fle`): a NaN operand compares
    // false as in Rust.
    let winner = if (root.std.fge(min.value, max_v) || root.std.fle(number_v, min.value)) {
        min
    } else if (root.std.fge(number_v, max_v)) {
        max
    } else {
        number
    };
    num_value(winner)
}

/// Coerce `n` into `base`'s unit for `math.clamp`, raising dart-sass's
/// "incompatible units" error when one side is unitless and the other is not,
/// or when the units are a hard cross-dimension mismatch.
function coerce_for_clamp(
    base: root.value.Number,
    n: root.value.Number,
    base_label: string,
    n_label: string,
    pos: root.scanner.Pos,
) -> float {
    let unitless_mix = base.is_unitless() != n.is_unitless();
    if (unitless_mix) {
        throw root.error.Error.at(
            `$${n_label}: ${n.to_css(false)} and $${base_label}: ${base.to_css(false)} have incompatible units (one has units and the other doesn't).`,
            pos,
        );
    }
    match (try_coerce(n, base)) {
        let v: float => v,
        null => {
            throw incompatible(base, n, pos);
        },
    }
}

/// `random()` — a pseudo-random float in `[0, 1)` — or `random($limit)` — a
/// pseudo-random integer in `[1, $limit]`. `$limit` must be a positive
/// integer (its unit is ignored, matching dart-sass's legacy behaviour); a
/// non-number / non-integer / non-positive limit errors.
function random(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    check_max_args(pos_args, named, 1, pos);
    let r = next_random();
    match (root.builtins.arg(["limit"], pos_args, named, 0)) {
        null => unitless(round_to_precision(r)),
        root.value.Value_Null {} => unitless(round_to_precision(r)),
        let v: root.value.Value => {
            let n = as_num(v, pos);
            // dart-sass treats a value within the 1e-11 precision of an
            // integer as that integer.
            let rounded = n.value.round();
            // PORT: IEEE comparisons (`root.std.fge/flt`): a NaN compares false
            // as in Rust.
            if (root.std.fge((n.value - rounded).abs(), 1e-11)) {
                throw root.error.Error.at(`$limit: ${n.to_css(false)} is not an int.`, pos);
            }
            if (root.std.flt(rounded, 1.0)) {
                throw root.error.Error.at(`$limit: Must be greater than 0, was ${n.to_css(false)}.`, pos);
            }
            // floor(r * limit) + 1 lands in [1, limit].
            let pick = (r * rounded).floor() + 1.0;
            unitless(root.std.fmin(pick, rounded))
        },
    }
}

/// Round a `[0,1)` random draw to sasso's 10-digit output precision so its
/// serialization is stable (dart-sass emits e.g. `0.8820566029`).
function round_to_precision(x: float) -> float {
    (x * 1e10).round() / 1e10
}

/// A pseudo-random `f64` in `[0, 1)` from a process-wide xorshift64* state,
/// seeded once from the system clock. Pure Rust, no external dependency.
function next_random() -> float {
    // PORT: `use std::cell::Cell; use std::time::{SystemTime, UNIX_EPOCH};` —
    // the `thread_local!` `STATE` is hoisted to `next_random__STATE()` (a
    // process-wide cell; see below).
    let s = next_random__STATE();
    let x = s.get();
    if (x == 0n) {
        // Seed from the clock; fall back to a fixed nonzero constant if
        // the clock is unavailable (never zero, which would stick).
        // PORT: `root.std.now_nanos()` cannot fail, so the
        // `0x9E37_79B9_7F4A_7C15` fallback is never taken.
        let seed = root.std.now_nanos() & root.std.U64_MASK();
        x = seed | 1n;
    }
    // xorshift64*
    x = x ^ (x >> 12);
    x = (x ^ (x << 25)) & root.std.U64_MASK();
    x = x ^ (x >> 27);
    s.set(x);
    let v = root.std.u64_wrapping_mul(x, 0x2545F4914F6CDD1Dn);
    // Take the top 53 bits for a uniform double in [0, 1).
    root.std.int_to_f64(root.std.int_of(v >> 11)) / root.std.int_to_f64(root.std.int_of(1n << 53))
}

/// `thread_local! { static STATE: Cell<u64> = const { Cell::new(0) }; }` inside
/// `next_random`.
// PORT: a top-level `client` holds the mutable cell (evaluated once, shared
// process-wide rather than per-thread).
client next_random__STATE_CELL = root.std.Cell<bigint> { value: 0n };

function next_random__STATE() -> root.std.Cell<bigint> {
    next_random__STATE_CELL
}

// ---- shared helpers --------------------------------------------------
/// All positional arguments followed by all named-argument values, in order.
function all_args(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
) -> root.value.Value[] {
    let v: root.value.Value[] = root.std.clone_vec(pos_args);
    root.std.extend(
        v,
        named.map((t) -> {
            t._1
        }),
    );
    v
}

/// Replace a bare calc-constant string (`infinity`/`-infinity`/`NaN`/`pi`/`e`)
/// with its numeric value; pass any other value through unchanged. Used by
/// `min`/`max`/`clamp`, which accept the constants while still preserving a
/// genuine non-number argument as a CSS call.
function normalize_const(v: root.value.Value) -> root.value.Value {
    if let s: root.value.Value_Str = v {
        if (!s._0.quoted) {
            let n = const_number(s._0.text);
            if (n != null) {
                return root.value.Value_Number { _0: n };
            }
        }
    }
    v
}

/// Reduce a list of values to the min/max number under dart-sass's calc
/// `min()`/`max()` simplification:
///
/// - `Ok(Some(n))` — every argument folds into one number; the result keeps
///   the winning argument's own unit (`min(1in, 2cm)` → `2cm`).
/// - `Ok(None)` — two or more mutually-incomparable clusters remain
///   (`min(1px, 2vw)`, `min(1c, 2d)`), so the call is preserved.
/// - `Err` — a known cross-dimension pair is genuinely incompatible
///   (`min(1s, 2px)`), matching dart-sass's "<a> and <b> are incompatible."
///
/// Each new value is folded into the first existing cluster it is comparable
/// to (equal/convertible units, or a unitless operand against anything);
/// otherwise it starts a new cluster. (The unitless-vs-multiple-cluster
/// "potentially incompatible" error case is left preserved rather than
/// errored — a strict subset of dart's behaviour that never folds wrongly.)
function reduce_min_max(
    args: root.value.Value[],
    is_min: bool,
    pos: root.scanner.Pos,
) -> root.value.Number? {
    // dart-sass `SassCalculation.min`/`max`: a sequential fold where a
    // unitless operand is comparable to anything (the legacy rule, so
    // `min(1c, 2)` computes `1c`); the first incomparable pair stops the
    // simplification.
    let best: root.value.Number? = null;
    let simplified = true;
    for (let v in args) {
        let n = match (v) {
            root.value.Value_Number { _0: let n } => n,
            _ => {
                simplified = false;
                break;
            },
        };
        if let b: root.value.Number = best {
            match (try_coerce(n, b)) {
                let nv: float => {
                    // Pick the winner, keeping its own authored unit.
                    // PORT: IEEE comparisons (`root.std.flt/fgt`): a NaN
                    // compares false as in Rust.
                    let pick_n = if (is_min) {
                        root.std.flt(nv, b.value)
                    } else {
                        root.std.fgt(nv, b.value)
                    };
                    if (pick_n) {
                        best = n;
                    }
                },
                null => {
                    simplified = false;
                    break;
                },
            }
        } else {
            best = n;
        }
    }
    if (simplified) {
        return best;
    }
    // Preserve path: every number pair must be at least *potentially*
    // compatible (dart `_verifyCompatibleNumbers`) — a unitless operand can
    // never combine with a unit in a real calculation, and two known units
    // must share a dimension; an unknown unit is potentially anything.
    let nums: root.value.Number[] = args.filter_map((v) -> {
        match (v) {
            root.value.Value_Number { _0: let n } => n,
            _ => null,
        }
    });
    let i = 0;
    while (i < nums.length()) {
        let j = i + 1;
        while (j < nums.length()) {
            let a = nums[i];
            let b = nums[j];
            if (a.has_complex_units() || b.has_complex_units()) {
                j += 1;
                continue; // rejected separately by verify_no_complex_args
            }
            let ua = a.unit();
            let ub = b.unit();
            if (a.is_unitless() != b.is_unitless() || root.value.calc_units_incompatible(ua, ub)) {
                throw incompatible(a, b, pos);
            }
            j += 1;
        }
        i += 1;
    }
    null
}

/// Convert `n` into `target`'s unit, returning the converted scalar, or
/// `None` if their units are incompatible. A unitless operand keeps its
/// value and adopts the comparison silently.
function try_coerce(n: root.value.Number, target: root.value.Number) -> float? {
    if (n.has_complex_units() || target.has_complex_units()) {
        let f = root.value.unit_lists_factor(
            root.std.Tuple2<string[], string[]> { _0: n.numer_units(), _1: n.denom_units() },
            root.std.Tuple2<string[], string[]> {
                _0: target.numer_units(),
                _1: target.denom_units(),
            },
        );
        return if (f != null) {
            n.value * f
        } else {
            null
        };
    }
    if (
        root.std.eq_ignore_ascii_case(n.unit(), target.unit())
            || n.is_unitless()
            || target.is_unitless()
    ) {
        return n.value;
    }
    let f = root.value.convert_factor(n.unit(), target.unit());
    if (f != null) {
        n.value * f
    } else {
        null
    }
}

/// Convert an angle number to radians, accepting `deg`/`grad`/`rad`/`turn`
/// or a unitless value (already radians). Errors on any other unit.
function angle_to_radians(n: root.value.Number, pos: root.scanner.Pos) -> float {
    let deg = match (root.std.ascii_lower(n.unit())) {
        // unitless and radians are already in radians.
        "" | "rad" => {
            return n.value;
        },
        "deg" => n.value,
        "grad" => n.value * 9.0 / 10.0,
        "turn" => n.value * 360.0,
        _ => {
            throw root.error.Error.at(`$number: Expected ${n.to_css(false)} to have an angle unit (deg, grad, rad, turn).`, pos);
        },
    };
    deg * root.std.F64_PI() / 180.0
}

/// Collect every argument as a number, erroring on the first non-number.
function collect_nums(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Number[] {
    let args = all_args(pos_args, named);
    if (args.length() == 0) {
        // A variadic member names no parameter to be missing.
        throw root.error.Error.at("At least one argument must be passed.", pos);
    }
    let out: root.value.Number[] = [];
    for (let v in args) {
        out.push(as_num(v, pos));
    }
    out
}

/// Interpret an unquoted-string calc constant (`infinity`, `-infinity`,
/// `nan`, `pi`, `e`, case-insensitive) as the matching unitless number. These
/// are the same constants `calc()` recognizes; dart-sass's math functions
/// accept them as numeric inputs too.
function const_number(text: string) -> root.value.Number? {
    let value = match (root.std.ascii_lower(text)) {
        "infinity" => root.std.F64_INFINITY(),
        "-infinity" => root.std.F64_NEG_INFINITY(),
        "nan" => root.std.F64_NAN(),
        "pi" => root.std.F64_PI(),
        "e" => root.std.F64_E(),
        _ => {
            return null;
        },
    };
    root.value.Number.unitless(value)
}

/// Convert a value to a `Number`, also accepting the bare calc constants
/// (`infinity`/`-infinity`/`NaN`/`pi`/`e`); erroring on any other non-number.
function as_num(v: root.value.Value, pos: root.scanner.Pos) -> root.value.Number {
    match (v) {
        root.value.Value_Number { _0: let n } => n,
        root.value.Value_Str { _0: let s } if !s.quoted => {
            match (const_number(s.text)) {
                let n: root.value.Number => n,
                null => {
                    throw root.error.Error.at(`${s.text} is not a number.`, pos);
                },
            }
        },
        let other => {
            throw root.error.Error.at(`${other.to_css(false)} is not a number.`, pos);
        },
    }
}

/// Fetch the argument at `i` as a `Number`, erroring on a missing or
/// non-number argument.
function require_num(
    params: string[],
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    i: int,
    pos: root.scanner.Pos,
) -> root.value.Number {
    let v = root.builtins.require(params, pos_args, named, i, pos);
    as_num(v, pos)
}

/// Wrap a result number as a value: a finite number stays a plain `Number`,
/// while a non-finite result (infinity/NaN) becomes a `calc()` so it
/// serializes as `calc(infinity)` / `calc(NaN)` / `calc(-infinity)`, matching
/// dart-sass.
function num_value(n: root.value.Number) -> root.value.Value {
    if (n.value.is_finite()) {
        root.value.Value_Number { _0: n }
    } else {
        root.value.Value_Calc { _0: root.value.CalcNode_Number { _0: n } }
    }
}

/// Ensure a number is unitless, erroring with dart-sass's wording.
function no_unit(n: root.value.Number, pos: root.scanner.Pos) -> void {
    if (n.is_unitless()) {
        return;
    } else {
        throw root.error.Error.at(`Expected ${n.to_css(false)} to have no units.`, pos);
    }
}

function unitless(value: float) -> root.value.Value {
    num_value(root.value.Number.unitless(value))
}

function degrees(value: float) -> root.value.Value {
    num_value(root.value.Number.with_unit(value, "deg"))
}

function incompatible(
    a: root.value.Number,
    b: root.value.Number,
    pos: root.scanner.Pos,
) -> root.error.Error {
    root.error.Error.at(`${a.to_css(false)} and ${b.to_css(false)} are incompatible.`, pos)
}

/// Build the preserved CSS form `name(arg, arg, ...)` over evaluated
/// arguments, matching dart-sass's serialization (comma + space separated).
/// An unreduced CSS math function (`min`/`max`/`clamp`/`hypot`/…) becomes a
/// calculation value, so `meta.type-of` reports `calculation` and
/// `meta.calc-name`/`meta.calc-args` can inspect it. Each argument keeps its
/// kind: a number stays a number node, a nested calculation is inlined, and any
/// other operand is its verbatim serialization.
function preserved_call(name: string, args: root.value.Value[]) -> root.value.Value {
    root.value.Value_Calc {
        _0: root.value.CalcNode_Func {
            name: name,
            args: args.map((v) -> {
                value_to_calc_node(v)
            }),
        },
    }
}

function value_to_calc_node(v: root.value.Value) -> root.value.CalcNode {
    match (v) {
        root.value.Value_Number { _0: let n } => root.value.CalcNode_Number { _0: n },
        root.value.Value_Calc { _0: let node } => node,
        let other => root.value.CalcNode_Str { _0: other.to_css(false) },
    }
}
