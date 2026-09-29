// Ported from sasso `src/host_fn.rs` (namespace `root.host_fn`).
//
// Host-defined (embedder) custom Sass functions — the engine side of the
// dart-sass `functions` option.
//
// An embedder registers a function via [`crate::Options::with_function`] with a
// signature (`"pow($base, $exponent)"`) and a **byte-protocol callback**
// `Fn(&[u8]) -> Result<Vec<u8>, String>`. At call time the evaluator binds the
// arguments, serializes them to the wire format below, invokes the callback,
// and deserializes its returned bytes back into a [`Value`]. Keeping the
// callback byte-oriented means the public API never exposes the internal
// `Value` type, while the (de)serializers here — which DO touch `Value`'s
// internals — stay crate-private. The wasm/FFI layers are then dumb pipes that
// forward the bytes to the real host (e.g. a JS function).
//
// ## Wire format
// A value is a tag byte followed by a payload; integers are little-endian, and
// a "str" is a `u32` byte length followed by UTF-8. `serialize_args` writes a
// `u32` count then that many values (the bound, ordered arguments).
//
// Supported value types: null, bool, number (with full unit lists), string,
// list (separator + brackets + an optional argument-list keyword map), map, and
// color (any CSS Color 4 space — serialized uniformly as a space name + three
// optional channels + optional alpha; legacy sRGB folds to the `rgb` space).
// Calculations and first-class function/mixin references are not yet
// representable across the boundary and surface a clear error (added
// incrementally); slash-divisions never reach here (call args are collapsed to
// plain numbers before binding).

/// An embedder's custom-function callback: it receives the bound arguments
/// serialized to sasso's host-value wire format and returns the result
/// serialized the same way (or an `Err(message)` that becomes a compile error).
type HostFunction = (uint8array) -> uint8array throws unknown;

// PORT: the callback's `Err(String)` is a thrown `root.std.StrError`.

/// A registered host function: the matched (normalized) name, its parsed
/// signature (or a parse error to surface when the function is called), and the
/// embedder's byte-protocol callback.
class HostFn {
    /// Hyphen-normalized function name used for call-site matching.
    name: string,
    /// The parsed parameter list, or an error message if the signature was
    /// malformed (surfaced as a compile error only if the function is called).
    params: root.std.Ok<root.ast.ParamList> | root.std.Err<string>,
    /// `Fn(serialized args) -> Ok(serialized return) | Err(message)`.
    callback: HostFunction,
}

/// Sass treats `_` and `-` as equivalent in identifiers.
function normalize_name(s: string) -> string {
    s.replace_all("_", "-")
}

/// Parse a `name($a, $b, $rest...)` signature into a normalized name plus its
/// parameter list. Default values (`$a: 1`) are not yet supported and yield an
/// error (kept with the name so calling the function reports it).
function parse_signature(
    sig: string,
) -> root.std.Tuple2<string, root.std.Ok<root.ast.ParamList> | root.std.Err<string>> {
    sig = root.std.trim(sig);
    let open = sig.index_of("(");
    let split: root.std.Tuple2<string, string> = match (open) {
        let i: int => {
            let rest = root.std.trim_end(sig.slice(i + 1, sig.length()));
            let inner = root.std.strip_suffix(rest, ")");
            match (inner) {
                let inner_s: string => {
                    root.std.Tuple2<string, string> { _0: sig.slice(0, i), _1: inner_s }
                },
                null => {
                    return root.std.Tuple2<string, root.std.Ok<root.ast.ParamList> | root.std.Err<string>> {
                        _0: normalize_name(root.std.trim(sig.slice(0, i))),
                        _1: root.std.Err<string> {
                            error: "sasso: function signature is missing its closing ')'",
                        },
                    };
                },
            }
        },
        // No parens: a zero-arg function.
        null => root.std.Tuple2<string, string> { _0: sig, _1: "" },
    };
    let raw_name = split._0;
    let args_src = split._1;
    let name = normalize_name(root.std.trim(raw_name));
    if (name == "") {
        return root.std.Tuple2<string, root.std.Ok<root.ast.ParamList> | root.std.Err<string>> {
            _0: name,
            _1: root.std.Err<string> { error: "sasso: function signature has no name" },
        };
    }

    let params: root.ast.Param[] = [];
    let rest: string? = null;
    for (let part in args_src.split(",")) {
        let part = root.std.trim(part);
        if (part == "") {
            continue;
        }
        let var = match (root.std.strip_prefix(part, "$")) {
            let v: string => root.std.trim(v),
            null => {
                return root.std.Tuple2<string, root.std.Ok<root.ast.ParamList> | root.std.Err<string>> {
                    _0: name,
                    _1: root.std.Err<string> {
                        error: `sasso: signature parameter "${part}" must start with $`,
                    },
                };
            },
        };
        let r = root.std.strip_suffix(var, "...");
        if (r != null) {
            rest = normalize_name(root.std.trim(r));
            // A rest parameter must be last; ignore anything after it.
            break;
        }
        if (var.includes(":")) {
            return root.std.Tuple2<string, root.std.Ok<root.ast.ParamList> | root.std.Err<string>> {
                _0: name,
                _1: root.std.Err<string> {
                    error: "sasso: default values in custom-function signatures are not yet supported",
                },
            };
        }
        params.push(
            root.ast.Param {
                name: var,
                default: null,
                // A host-function signature has no source text to point at.
                default_pos: root.scanner.Pos.NONE(),
            },
        );
    }
    root.std.Tuple2<string, root.std.Ok<root.ast.ParamList> | root.std.Err<string>> {
        _0: name,
        _1: root.std.Ok<root.ast.ParamList> { value: root.ast.ParamList { params: params, rest: rest } },
    }
}

/// Bind evaluated call arguments to a host function's parameters, producing the
/// ordered positional values (plus a trailing argument-list value for a `$rest`
/// parameter) that are handed to the callback — mirroring `bind_evaled` for the
/// no-default host-function case. Names compare hyphen/underscore-insensitively.
// PORT: `Result<Vec<Value>, String>` → the error is a thrown `root.std.StrError`.
function bind_host_args(
    param_names: string[],
    rest: string?,
    positional: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    rest_sep: root.value.ListSep,
    fn_name: string,
) -> root.value.Value[] {
    let keyword: map<string, root.value.Value> = {};
    let keyword_order: string[] = [];
    for (let nv in named) {
        let n = nv._0;
        let v = nv._1;
        let norm = normalize_name(n);
        if (!keyword.has(norm)) {
            keyword_order.push(norm);
        }
        let _ = keyword.set(norm, v);
    }
    let out: root.value.Value[] = [];
    // PORT: `positional.into_iter()` → an index cursor `pos_iter` into `positional`.
    let pos_iter = 0;
    for (let p in param_names) {
        let val = if (pos_iter < positional.length()) {
            let v = positional[pos_iter];
            pos_iter += 1;
            v
        } else {
            let kv = keyword.delete(normalize_name(p));
            if (kv != null) {
                kv
            } else {
                root.std.err_str("Missing argument $" + p + ".")
            }
        };
        out.push(val);
    }
    if (rest != null) {
        let rest_name = rest;
        let remaining: root.value.Value[] = positional.slice(pos_iter, positional.length());
        let kw: root.std.Tuple2<root.value.Value, root.value.Value>[] = keyword_order.filter_map((norm: string) -> root.std.Tuple2<root.value.Value, root.value.Value>? {
            let v = keyword.delete(norm);
            if (v != null) {
                root.std.Tuple2<root.value.Value, root.value.Value> {
                    _0: root.value.Value_Str { _0: root.value.SassStr { text: norm, quoted: false } },
                    _1: v,
                }
            } else {
                null
            }
        });
        let _ = rest_name;
        out.push(
            root.value.Value_List {
                _0: root.value.List { items: remaining, sep: rest_sep, bracketed: false, keywords: kw },
            },
        );
    } else if (pos_iter < positional.length()) {
        root.std.err_str(`${fn_name} was passed too many arguments.`);
    } else {
        let extra = keyword_order.find((k: string) -> bool {
            keyword.has(k)
        });
        if (extra != null) {
            root.std.err_str("No argument named $" + extra + ".");
        }
    }
    out
}

// ---------------- value operations (engine-routed Value methods) ----------------
//
// dart-sass `Value` methods that need unit / color-space math (e.g.
// `SassNumber.convert`, `SassColor.toSpace`) route from JS back into the engine
// here, so the conversions reuse the exact Rust math instead of being
// reimplemented (and drifting) in JS. The JS side calls a wasm `sasso_value_op`
// export that forwards to [`host_value_op`]; both sides speak the same byte
// protocol as custom functions, on a value instance that is independent of any
// in-flight compile (so the methods also work standalone).
/// Convert/coerce a number to target units. dart-sass:
/// - **convert**: both unitless → ok; one unitless and the other not → error;
///   both have units → must be compatible.
/// - **coerce**: a unitless side is treated as compatible (factor 1).
function OP_NUMBER_CONVERT() -> int {
    1
}

/// Test whether a number is convertible to a single unit (`compatibleWithUnit`).
function OP_NUMBER_COMPATIBLE() -> int {
    2
}

/// `SassColor.toSpace(space)` — `[color, Str(space)]` -> color.
function OP_COLOR_TO_SPACE() -> int {
    3
}

/// `SassColor.isInGamut(space?)` — `[color, Str(space)]` -> bool.
function OP_COLOR_IN_GAMUT() -> int {
    4
}

/// `SassColor.toGamut(space, method)` — `[color, Str(space), Str(method)]` -> color.
function OP_COLOR_TO_GAMUT() -> int {
    5
}

/// `SassColor.isChannelPowerless(channel, space?)` — `[color, Str(channel), Str(space)]` -> bool.
function OP_COLOR_POWERLESS() -> int {
    6
}

/// `SassColor.interpolate(other, weight%, method)` — `[c1, c2, Number, Str(method)]` -> color.
function OP_COLOR_INTERPOLATE() -> int {
    7
}

/// Run a value operation: deserialize the operands, dispatch on `op`, and return
/// the serialized result (or an `Err(message)` surfaced to the JS caller).
// PORT: `Result<Vec<u8>, String>` → the error is a thrown `root.std.StrError`.
function host_value_op(op: int, input: uint8array) -> uint8array {
    let args = deserialize_args(input);
    let result: root.value.Value = match (op) {
        let o if o == OP_NUMBER_CONVERT() => number_convert(args),
        let o if o == OP_NUMBER_COMPATIBLE() => {
            let n = as_number(args.at(0));
            let unit = as_string(args.at(1));
            let from = root.std.Tuple2<string[], string[]> { _0: n.numer_units(), _1: n.denom_units() };
            let to_numer: string[] = if (unit == "") {
                []
            } else {
                [unit]
            };
            let ok = number_factor(from, root.std.Tuple2<string[], string[]> { _0: to_numer, _1: [] }, true)
                != null;
            root.value.Value_Bool { _0: ok }
        },
        let o if o == OP_COLOR_TO_SPACE() => {
            let space = unquoted(as_string(args.at(1)));
            call_color("to-space", [arg(args, 0), space], [])
        },
        let o if o == OP_COLOR_IN_GAMUT() => {
            let space = unquoted(as_string(args.at(1)));
            call_color(
                "is-in-gamut",
                [arg(args, 0)],
                [root.std.Tuple2<string, root.value.Value> { _0: "space", _1: space }],
            )
        },
        let o if o == OP_COLOR_TO_GAMUT() => {
            let space = unquoted(as_string(args.at(1)));
            let method = unquoted(as_string(args.at(2)));
            call_color(
                "to-gamut",
                [arg(args, 0)],
                [
                    root.std.Tuple2<string, root.value.Value> { _0: "space", _1: space },
                    root.std.Tuple2<string, root.value.Value> { _0: "method", _1: method },
                ],
            )
        },
        let o if o == OP_COLOR_POWERLESS() => {
            // `color.is-powerless($color, $channel, $space)` — channel is quoted.
            let channel = root.value.Value_Str {
                _0: root.value.SassStr { text: as_string(args.at(1)), quoted: true },
            };
            let space = unquoted(as_string(args.at(2)));
            call_color(
                "is-powerless",
                [arg(args, 0), channel],
                [root.std.Tuple2<string, root.value.Value> { _0: "space", _1: space }],
            )
        },
        let o if o == OP_COLOR_INTERPOLATE() => {
            // `color.mix($c1, $c2, $weight, $method)` — weight already a %, method a string.
            let method = unquoted(as_string(args.at(3)));
            call_color("mix", [arg(args, 0), arg(args, 1), arg(args, 2), method], [])
        },
        _ => root.std.err_str(`sasso: unknown value op ${op}`),
    };
    serialize_one(result)
}

function arg(args: root.value.Value[], i: int) -> root.value.Value {
    args.at(i) ?? root.std.err_str("sasso: value op missing an argument")
}

function unquoted(text: string) -> root.value.Value {
    root.value.Value_Str { _0: root.value.SassStr { text: text, quoted: false } }
}

/// Route a color value-op to the corresponding `color.*` builtin.
function call_color(
    member: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
) -> root.value.Value {
    let named = named.map((kv: root.std.Tuple2<string, root.value.Value>) -> root.std.Tuple2<string, root.value.Value> {
        root.std.Tuple2<string, root.value.Value> { _0: kv._0, _1: kv._1 }
    });
    root.builtins.call_module(
        "color",
        member,
        pos_args,
        named,
        root.scanner.Pos { line: 1, col: 1 },
    ) catch (e) {
        let err: root.error.Error => root.std.err_str(err.message)
    }
}

function as_number(v: root.value.Value?) -> root.value.Number {
    match (v) {
        root.value.Value_Number { _0: let n } => n,
        _ => root.std.err_str("sasso: value op expected a number"),
    }
}

function as_string(v: root.value.Value?) -> string {
    match (v) {
        root.value.Value_Str { _0: let s } => s.text,
        _ => root.std.err_str("sasso: value op expected a string"),
    }
}

/// Extract a unit list from a list (or single string / empty / null) value.
function as_string_list(v: root.value.Value?) -> string[] {
    match (v) {
        root.value.Value_List { _0: let l } => {
            l.items.filter_map((i: root.value.Value) -> string? {
                if let s: root.value.Value_Str = i {
                    s._0.text
                } else {
                    null
                }
            })
        },
        root.value.Value_Str { _0: let s } => [s.text],
        _ => [],
    }
}

/// The multiplier from `from` units to `to` units under convert/coerce rules,
/// or `None` if the conversion is illegal.
function number_factor(
    from: root.std.Tuple2<string[], string[]>,
    to: root.std.Tuple2<string[], string[]>,
    coerce: bool,
) -> float? {
    let from_unitless = from._0.length() == 0 && from._1.length() == 0;
    let to_unitless = to._0.length() == 0 && to._1.length() == 0;
    if (from_unitless || to_unitless) {
        if (coerce || (from_unitless && to_unitless)) {
            1.0
        } else {
            null // convert: can't cross the unitless boundary
        }
    } else {
        root.value.unit_lists_factor(from, to)
    }
}

function number_convert(args: root.value.Value[]) -> root.value.Value {
    let n = as_number(args.at(0));
    let numer = as_string_list(args.at(1));
    let denom = as_string_list(args.at(2));
    let coerce = match (args.at(3)) {
        root.value.Value_Bool { _0: true } => true,
        _ => false,
    };
    let from = root.std.Tuple2<string[], string[]> { _0: n.numer_units(), _1: n.denom_units() };
    match (number_factor(from, root.std.Tuple2<string[], string[]> { _0: numer, _1: denom }, coerce)) {
        let f: float => {
            root.value.Value_Number { _0: root.value.Number.with_units(n.value * f, numer, denom) }
        },
        null => {
            let to = if (numer.length() == 0 && denom.length() == 0) {
                "no units"
            } else {
                let s = root.std.join(numer, "*");
                if (denom.length() != 0) {
                    s = s + "/";
                    s = s + root.std.join(denom, "*");
                }
                s
            };
            let shown: root.value.Value = root.value.Value_Number { _0: n };
            root.std.err_str(`${shown.to_css(false)} can't be converted to ${to}.`)
        },
    }
}

// ---------------- serialization ----------------
function TAG_NULL() -> int {
    0
}

function TAG_BOOL() -> int {
    1
}

function TAG_NUMBER() -> int {
    2
}

function TAG_STRING() -> int {
    3
}

function TAG_LIST() -> int {
    4
}

function TAG_MAP() -> int {
    5
}

function TAG_COLOR() -> int {
    6
}

function TAG_CALC() -> int {
    7
}

function TAG_FUNCTION() -> int {
    8
}

function TAG_MIXIN() -> int {
    9
}

// First-class function/mixin references can't be reconstructed on the JS side, so
// they cross the boundary as OPAQUE HANDLES: serialization stores the `Value` here
// and emits its index; the JS side holds an opaque object and, when it passes the
// reference back, sends the index, which deserialization looks up. The table is
// per custom-function dispatch (expr.rs swaps a fresh one in, restoring the outer
// one afterwards, so a nested custom-function call is safe).
// PORT: `thread_local! { static HANDLES: RefCell<Vec<Value>> }` → BAML has no
// globals or thread-locals; a top-level `client` declaration is evaluated once
// and shared, so it holds the mutable cell and `HANDLES()` hands it out:
// `HANDLES.with(|h| … h.borrow() …)` → `HANDLES().value`. The state is
// process-wide rather than per-thread (the port is single-threaded here).
client HANDLES_CELL = root.std.Cell<root.value.Value[]> { value: [] };

function HANDLES() -> root.std.Cell<root.value.Value[]> {
    HANDLES_CELL
}

/// Install a fresh handle table and return the previous one (to restore). Called
/// by the evaluator around each custom-function call.
function swap_handles(next: root.value.Value[]) -> root.value.Value[] {
    HANDLES().replace(next)
}

function push_handle(v: root.value.Value) -> int {
    let b = HANDLES().value;
    b.push(v);
    b.length() - 1
}

// PORT: `Result<Value, String>` → the error is a thrown `root.std.StrError`.
function get_handle(i: int) -> root.value.Value {
    HANDLES().value.at(i)
        ?? root.std.err_str("sasso: stale function/mixin reference from a custom function")
}

/// PORT: `Vec::new()` for a byte buffer (`uint8array` has no literal).
function new_bytes() -> uint8array {
    baml.Uint8Array.zeroes(0) catch (e) {
        _ => root.std.unreachable()
    }
}

/// PORT: `out.extend_from_slice(bytes)` for a byte buffer.
function extend_bytes(out: uint8array, bytes: uint8array) -> void {
    let i = 0;
    while (i < bytes.length()) {
        out.push(bytes[i]);
        i += 1;
    }
}

/// Write an optional channel: a present flag then (if present) the f64.
function put_opt_f64(out: uint8array, v: float?) -> void {
    match (v) {
        let n: float => {
            out.push(1);
            put_f64(out, n);
        },
        null => {
            out.push(0);
        },
    }
}

// PORT: `(n as u32).to_le_bytes()` → the four little-endian bytes by hand.
function put_u32(out: uint8array, n: int) -> void {
    let x = root.std.as_u32(n);
    out.push(x & 0xFF);
    out.push((x >> 8) & 0xFF);
    out.push((x >> 16) & 0xFF);
    out.push((x >> 24) & 0xFF);
}

// PORT: `s.len()` is the UTF-8 byte length (the wire format counts bytes).
function put_str(out: uint8array, s: string) -> void {
    put_u32(out, s.byte_length());
    extend_bytes(out, s.to_utf8());
}

// PORT: `n.to_le_bytes()` → the f64 bit pattern's eight little-endian bytes.
function put_f64(out: uint8array, n: float) -> void {
    let bits = root.std.f64_to_bits(n);
    let i = 0;
    while (i < 8) {
        out.push(root.std.int_of((bits >> (i * 8)) & 0xFFn));
        i += 1;
    }
}

/// Serialize the ordered, bound arguments: a `u32` count then each value.
// PORT: `Result<Vec<u8>, String>` → the error is a thrown `root.std.StrError`.
function serialize_args(args: root.value.Value[]) -> uint8array {
    let out = new_bytes();
    put_u32(out, args.length());
    for (let a in args) {
        serialize_value(out, a);
    }
    out
}

/// Serialize a single value (the host side serializing a function's return).
///
/// Host-side helper: the wasm path encodes in JS (not Rust), so this is used by
/// the in-crate tests now and the FFI host-function bridge later.
function serialize_one(v: root.value.Value) -> uint8array {
    let out = new_bytes();
    serialize_value(out, v);
    out
}

function serialize_value(out: uint8array, v: root.value.Value) -> void {
    match (v) {
        root.value.Value_Null {} => {
            out.push(TAG_NULL());
        },
        root.value.Value_Bool { _0: let b } => {
            out.push(TAG_BOOL());
            out.push(
                if (b) {
                    1
                } else {
                    0
                },
            );
        },
        root.value.Value_Number { _0: let n } => {
            out.push(TAG_NUMBER());
            write_number_body(out, n);
        },
        root.value.Value_Str { _0: let s } => {
            out.push(TAG_STRING());
            out.push(
                if (s.quoted) {
                    1
                } else {
                    0
                },
            );
            put_str(out, s.text);
        },
        root.value.Value_List { _0: let l } => {
            out.push(TAG_LIST());
            out.push(sep_code(l.sep));
            out.push(
                if (l.bracketed) {
                    1
                } else {
                    0
                },
            );
            put_u32(out, l.items.length());
            for (let it in l.items) {
                serialize_value(out, it);
            }
            match (l.keywords) {
                let kw: root.std.Tuple2<root.value.Value, root.value.Value>[] => {
                    out.push(1);
                    put_u32(out, kw.length());
                    for (let entry in kw) {
                        let k = entry._0;
                        let val = entry._1;
                        serialize_value(out, k);
                        serialize_value(out, val);
                    }
                },
                null => {
                    out.push(0);
                },
            }
        },
        root.value.Value_Map { _0: let m } => {
            out.push(TAG_MAP());
            put_u32(out, m.entries.length());
            for (let entry in m.entries) {
                let k = entry._0;
                let val = entry._1;
                serialize_value(out, k);
                serialize_value(out, val);
            }
        },
        root.value.Value_Color { _0: let c } => {
            // Represent every color uniformly as a space + 3 channels + alpha
            // (legacy sRGB folds to the "rgb" space). Missing channels (`none`)
            // round-trip via the present flag.
            out.push(TAG_COLOR());
            let mc = root.builtins.color.math.legacy_to_modern(c);
            put_str(out, mc.space.name());
            for (let ch in mc.channels) {
                put_opt_f64(out, ch);
            }
            put_opt_f64(out, mc.alpha);
        },
        root.value.Value_Calc { _0: let node } => {
            out.push(TAG_CALC());
            write_calc_node(out, node);
        },
        root.value.Value_Slash {} => {
            // A slash-division never reaches here (call args are slash-collapsed
            // before binding, and JS can't construct one).
            root.std.err_str(
                "sasso: slash-division values are not supported as custom-function values",
            );
        },
        root.value.Value_Function {} => {
            out.push(TAG_FUNCTION());
            put_u32(out, push_handle(v));
        },
        root.value.Value_Mixin {} => {
            out.push(TAG_MIXIN());
            put_u32(out, push_handle(v));
        },
        _ => root.std.unreachable(),
    }
}

/// The `[f64 value][numer units][denom units]` body of a number (shared by the
/// `TAG_NUMBER` value and a calc `Number` node).
function write_number_body(out: uint8array, n: root.value.Number) -> void {
    put_f64(out, n.value);
    put_u32(out, n.numer_units().length());
    for (let u in n.numer_units()) {
        put_str(out, u);
    }
    put_u32(out, n.denom_units().length());
    for (let u in n.denom_units()) {
        put_str(out, u);
    }
}

function calc_op_code(op: root.value.CalcOp) -> int {
    match (op) {
        root.value.CalcOp.Add => 0,
        root.value.CalcOp.Sub => 1,
        root.value.CalcOp.Mul => 2,
        root.value.CalcOp.Div => 3,
    }
}

/// Serialize a `CalcNode` tree: tag byte (0 Number, 1 Str, 2 Op, 3 Func) + payload.
function write_calc_node(out: uint8array, node: root.value.CalcNode) -> void {
    match (node) {
        root.value.CalcNode_Number { _0: let n } => {
            out.push(0);
            write_number_body(out, n);
        },
        root.value.CalcNode_Str { _0: let s } => {
            out.push(1);
            put_str(out, s);
        },
        root.value.CalcNode_Op { op: let op, left: let left, right: let right } => {
            out.push(2);
            out.push(calc_op_code(op));
            write_calc_node(out, left);
            write_calc_node(out, right);
        },
        root.value.CalcNode_Func { name: let name, args: let args } => {
            out.push(3);
            put_str(out, name);
            put_u32(out, args.length());
            for (let a in args) {
                write_calc_node(out, a);
            }
        },
        _ => root.std.unreachable(),
    }
}

function sep_code(sep: root.value.ListSep) -> int {
    match (sep) {
        root.value.ListSep.Space => 0,
        root.value.ListSep.Comma => 1,
        root.value.ListSep.Slash => 2,
        root.value.ListSep.Undecided => 3,
    }
}

// PORT: `Result<ListSep, String>` → the error is a thrown `root.std.StrError`.
function sep_from(code: int) -> root.value.ListSep {
    match (code) {
        0 => root.value.ListSep.Space,
        1 => root.value.ListSep.Comma,
        2 => root.value.ListSep.Slash,
        3 => root.value.ListSep.Undecided,
        _ => root.std.err_str("sasso: bad list separator in custom-function result"),
    }
}

// ---------------- deserialization ----------------
// PORT: every `Result<_, String>` reader method throws `root.std.StrError`.
class Reader {
    buf: uint8array,
    pos: int,
    function u8(self) -> int {
        let b = self.buf.at(self.pos) ?? root.std.err_str("sasso: truncated custom-function result");
        self.pos += 1;
        b
    }

    // PORT: `checked_add` cannot overflow a 63-bit `int` for a buffer offset;
    // `buf.get(pos..end)` is `None` exactly when `end` passes the buffer's end.
    function u32(self) -> int {
        let end = self.pos + 4;
        if (end > self.buf.length()) {
            root.std.err_str("sasso: truncated custom-function result");
        }
        let b = self.buf.slice(self.pos, end);
        self.pos = end;
        b[0] | (b[1] << 8) | (b[2] << 16) | (b[3] << 24)
    }

    function f64(self) -> float {
        let end = self.pos + 8;
        if (end > self.buf.length()) {
            root.std.err_str("sasso: truncated custom-function result");
        }
        let b = self.buf.slice(self.pos, end);
        self.pos = end;
        // PORT: `f64::from_le_bytes` → assemble the bit pattern, high byte first.
        let a = 0n;
        let i = 7;
        while (i >= 0) {
            a = (a << 8) | root.std.bigint_of(b[i]);
            i -= 1;
        }
        root.std.f64_from_bits(a)
    }

    function opt_f64(self) -> float? {
        if (self.u8() != 0) {
            self.f64()
        } else {
            null
        }
    }

    function str(self) -> string {
        let len = self.u32();
        let end = self.pos + len;
        if (end > self.buf.length()) {
            root.std.err_str("sasso: truncated custom-function result");
        }
        let b = self.buf.slice(self.pos, end);
        self.pos = end;
        baml.String.from_utf8(b) catch (e) {
            let _e: baml.errors.InvalidArgument => {
                root.std.err_str("sasso: invalid UTF-8 in custom-function result")
            }
        }
    }
}

/// Deserialize a single value (the function's return) from the wire format.
// PORT: `Result<Value, String>` → the error is a thrown `root.std.StrError`.
function deserialize_value(buf: uint8array) -> root.value.Value {
    let r = Reader { buf: buf, pos: 0 };
    let v = read_value(r);
    v
}

/// Deserialize the argument vector (the host side reading what `serialize_args`
/// produced): a `u32` count then that many values.
///
/// Host-side helper (see [`serialize_one`]): used by the in-crate tests now and
/// the FFI host-function bridge later; the wasm path decodes in JS.
function deserialize_args(buf: uint8array) -> root.value.Value[] {
    let r = Reader { buf: buf, pos: 0 };
    let n = r.u32();
    let args: root.value.Value[] = [];
    let i = 0;
    while (i < n) {
        args.push(read_value(r));
        i += 1;
    }
    args
}

function read_value(r: Reader) -> root.value.Value {
    let tag = r.u8();
    match (tag) {
        let t if t == TAG_NULL() => root.value.Value_Null {  },
        let t if t == TAG_BOOL() => root.value.Value_Bool { _0: r.u8() != 0 },
        let t if t == TAG_NUMBER() => root.value.Value_Number { _0: read_number_body(r) },
        let t if t == TAG_STRING() => {
            let quoted = r.u8() != 0;
            let text = r.str();
            root.value.Value_Str { _0: root.value.SassStr { text: text, quoted: quoted } }
        },
        let t if t == TAG_LIST() => {
            let sep = sep_from(r.u8());
            let bracketed = r.u8() != 0;
            let n = r.u32();
            let items: root.value.Value[] = [];
            let i = 0;
            while (i < n) {
                items.push(read_value(r));
                i += 1;
            }
            let keywords: root.std.Tuple2<root.value.Value, root.value.Value>[]? = if (r.u8() != 0) {
                let kn = r.u32();
                let kw: root.std.Tuple2<root.value.Value, root.value.Value>[] = [];
                let j = 0;
                while (j < kn) {
                    let k = read_value(r);
                    let v = read_value(r);
                    kw.push(root.std.Tuple2<root.value.Value, root.value.Value> { _0: k, _1: v });
                    j += 1;
                }
                kw
            } else {
                null
            };
            root.value.Value_List {
                _0: root.value.List { items: items, sep: sep, bracketed: bracketed, keywords: keywords },
            }
        },
        let t if t == TAG_MAP() => {
            let n = r.u32();
            let entries: root.std.Tuple2<root.value.Value, root.value.Value>[] = [];
            let i = 0;
            while (i < n) {
                let k = read_value(r);
                let v = read_value(r);
                entries.push(root.std.Tuple2<root.value.Value, root.value.Value> { _0: k, _1: v });
                i += 1;
            }
            root.value.Value_Map { _0: root.value.Map.new(entries) }
        },
        let t if t == TAG_COLOR() => {
            let space_name = r.str();
            let space = root.value.ColorSpace_from_name(space_name)
                ?? root.std.err_str(
                    `sasso: unknown color space "${space_name}" from a custom function`,
                );
            let channels: (float?)[] = [r.opt_f64(), r.opt_f64(), r.opt_f64()];
            let alpha = r.opt_f64();
            if (space == root.value.ColorSpace.Rgb) {
                // The legacy sRGB space: reconstruct a plain legacy color so it
                // serializes via the legacy (hex / rgb()) path, like dart-sass.
                root.value.Value_Color {
                    _0: root.value.Color.rgb(
                        channels[0] ?? 0.0,
                        channels[1] ?? 0.0,
                        channels[2] ?? 0.0,
                        alpha ?? 1.0,
                    ),
                }
            } else {
                let mc = root.value.ModernColor { space: space, channels: channels, alpha: alpha };
                root.value.Value_Color { _0: root.builtins.color.math.make_modern_in(mc, space) }
            }
        },
        let t if t == TAG_CALC() => root.value.Value_Calc { _0: read_calc_node(r) },
        // Opaque handles: look the original Value back up in the per-dispatch table.
        let t if t == TAG_FUNCTION() || t == TAG_MIXIN() => get_handle(r.u32()),
        let other => root.std.err_str(`sasso: unknown value tag ${other} in custom-function result`),
    }
}

/// Read a number body written by [`write_number_body`].
function read_number_body(r: Reader) -> root.value.Number {
    let value = r.f64();
    let nn = r.u32();
    let numer: string[] = [];
    let i = 0;
    while (i < nn) {
        numer.push(r.str());
        i += 1;
    }
    let dn = r.u32();
    let denom: string[] = [];
    let j = 0;
    while (j < dn) {
        denom.push(r.str());
        j += 1;
    }
    root.value.Number.with_units(value, numer, denom)
}

// PORT: `Result<CalcOp, String>` → the error is a thrown `root.std.StrError`.
function calc_op_from(code: int) -> root.value.CalcOp {
    match (code) {
        0 => root.value.CalcOp.Add,
        1 => root.value.CalcOp.Sub,
        2 => root.value.CalcOp.Mul,
        3 => root.value.CalcOp.Div,
        _ => root.std.err_str("sasso: bad calc operator in custom-function result"),
    }
}

/// Read a `CalcNode` tree written by [`write_calc_node`].
function read_calc_node(r: Reader) -> root.value.CalcNode {
    match (r.u8()) {
        0 => root.value.CalcNode_Number { _0: read_number_body(r) },
        1 => root.value.CalcNode_Str { _0: r.str() },
        2 => {
            let op = calc_op_from(r.u8());
            let left = read_calc_node(r);
            let right = read_calc_node(r);
            root.value.CalcNode_Op { op: op, left: left, right: right }
        },
        3 => {
            let name = r.str();
            let n = r.u32();
            let args: root.value.CalcNode[] = [];
            let i = 0;
            while (i < n) {
                args.push(read_calc_node(r));
                i += 1;
            }
            root.value.CalcNode_Func { name: name, args: args }
        },
        let other => root.std.err_str(`sasso: bad calc node tag ${other} in custom-function result`),
    }
}
