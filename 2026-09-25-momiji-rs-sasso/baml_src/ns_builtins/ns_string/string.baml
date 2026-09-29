// Ported from sasso `src/builtins/string.rs` (namespace `root.builtins.string`).
//
// String built-in functions (`unquote`, `quote`, `str-length`, …).
//
// Shared argument helpers live in the parent module:
// `super::{arg, require, num, as_color, channel, clamp01}`. Return
// `Some(Ok(..))`/`Some(Err(..))` for a name this family owns, or `None`
// to let the next family try.
//
// Sass counts Unicode characters (not bytes) and indexes strings 1-based,
// with negative indices counting back from the end.

/// The names the string family owns by name (the single source of truth,
/// mirroring the `try_call` match arms below).
function NAMES() -> string[] {
    [
        "quote",
        "unquote",
        "to-upper-case",
        "to-lower-case",
        "str-length",
        "str-index",
        "str-slice",
        "str-insert",
        "unique-id",
    ]
}

function try_call(
    name: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> (root.std.Ok<root.value.Value> | root.std.Err<root.error.Error>)? {
    // Maximum positional arity per function; passing more is an error.
    // PORT: `usize::MAX` → `root.std.INT_MAX()`.
    let max = match (name) {
        "unique-id" => 0,
        "quote" | "unquote" | "to-upper-case" | "to-lower-case" | "str-length" => 1,
        "str-index" => 2,
        "str-slice" | "str-insert" => 3,
        _ => root.std.INT_MAX(),
    };
    // PORT: `if let Err(e) = check_arity(..)` → catch the `Error` as a value.
    let arity_err: root.error.Error? = null;
    check_arity(pos_args, named, max, pos) catch (e) {
        let err: root.error.Error => {
            arity_err = err;
        }
    };
    if (arity_err != null) {
        // Only enforce for names this family actually owns.
        if (max != root.std.INT_MAX()) {
            return root.std.Err<root.error.Error> { error: arity_err };
        }
    }
    // PORT: each `Some(f(..))` arm keeps the `Result` as a value via
    // `result_of` (see below).
    match (name) {
        "quote" => {
            result_of(() -> {
                fn_set_quoted(pos_args, named, pos, true)
            })
        },
        "unquote" => {
            result_of(() -> {
                fn_set_quoted(pos_args, named, pos, false)
            })
        },
        "to-upper-case" => {
            result_of(() -> {
                fn_change_case(pos_args, named, pos, true)
            })
        },
        "to-lower-case" => {
            result_of(() -> {
                fn_change_case(pos_args, named, pos, false)
            })
        },
        "str-length" => {
            result_of(() -> {
                fn_str_length(pos_args, named, pos)
            })
        },
        "str-index" => {
            result_of(() -> {
                fn_str_index(pos_args, named, pos)
            })
        },
        "str-slice" => {
            result_of(() -> {
                fn_str_slice(pos_args, named, pos)
            })
        },
        "str-insert" => {
            result_of(() -> {
                fn_str_insert(pos_args, named, pos)
            })
        },
        "unique-id" => root.std.Ok<root.value.Value> { value: fn_unique_id() },
        _ => null,
    }
}

/// PORT: helper for `Some(f(..))` over a `Result`-returning builtin: runs it
/// and keeps the outcome as a value (`Ok(v)` / `Err(e)`), catching only the
/// compiler `Error` the Rust `Result` carries.
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

/// Dispatch a `sass:string` member that has no global alias (`split`). Returns
/// `None` for any other member so the caller can report it as undefined.
function call_module_member(
    member: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> (root.std.Ok<root.value.Value> | root.std.Err<root.error.Error>)? {
    match (member) {
        "split" => {
            result_of(() -> {
                fn_split(pos_args, named, pos)
            })
        },
        _ => null,
    }
}

/// Reject more positional arguments than `max` (dart-sass "Only N argument(s)
/// allowed, but M were passed.").
function check_arity(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    max: int,
    pos: root.scanner.Pos,
) -> void {
    root.builtins.check_arity(max, pos_args, named, pos)
}

/// Extract `(text, quoted)` from a required string argument, erroring with
/// dart-sass's `$<param>: <value> is not a string.` message otherwise.
function require_string(
    params: string[],
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    i: int,
    pos: root.scanner.Pos,
) -> root.std.Tuple2<string, bool> {
    let v = root.builtins.require(params, pos_args, named, i, pos);
    match (v) {
        root.value.Value_Str { _0: root.value.SassStr { text: let text, quoted: let quoted } } => {
            root.std.Tuple2<string, bool> { _0: text, _1: quoted }
        },
        let other => {
            throw root.error.Error.at(`$${params.at(i) ?? ""}: ${other.to_css(false)} is not a string.`, pos);
        },
    }
}

/// Extract a unitless integer index, matching dart-sass which rejects any
/// unit on string indices.
function require_index(
    params: string[],
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    i: int,
    pos: root.scanner.Pos,
) -> int {
    let v = root.builtins.require(params, pos_args, named, i, pos);
    let pname = params.at(i) ?? "";
    match (v) {
        root.value.Value_Number { _0: let n } => {
            let value = n.value;
            if (!n.is_unitless()) {
                throw root.error.Error.at(`$${pname}: Expected ${v.to_css(false)} to have no units.`, pos);
            }
            // dart-sass requires an integer index (it rounds within a tiny
            // tolerance, but a genuine fraction like `0.5` is an error).
            // PORT: IEEE comparison (`root.std.fgt`): a NaN compares false as
            // in Rust.
            if (root.std.fgt((value - value.round()).abs(), 1e-11)) {
                throw root.error.Error.at(`$${pname}: ${root.value.fmt_num(value, false)} is not an int.`, pos);
            }
            root.std.f64_to_int(value.round())
        },
        let other => {
            throw root.error.Error.at(`$${pname}: ${other.to_css(false)} is not a number.`, pos);
        },
    }
}

function quoted_str(text: string, quoted: bool) -> root.value.Value {
    root.value.Value_Str { _0: root.value.SassStr { text: text, quoted: quoted } }
}

/// `quote($string)` / `unquote($string)`. dart-sass 1.x rejects non-string
/// arguments for both with `$string: ... is not a string.`.
function fn_set_quoted(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
    quoted: bool,
) -> root.value.Value {
    let text = require_string(["string"], pos_args, named, 0, pos)._0;
    quoted_str(text, quoted)
}

/// `to-upper-case` / `to-lower-case`: ASCII-only case change, preserving the
/// argument's quotedness.
function fn_change_case(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
    upper: bool,
) -> root.value.Value {
    let t = require_string(["string"], pos_args, named, 0, pos);
    let text = t._0;
    let quoted = t._1;
    let mapped: string = if (upper) {
        root.std.ascii_upper(text)
    } else {
        root.std.ascii_lower(text)
    };
    quoted_str(mapped, quoted)
}

/// `str-length($string)`: unitless character count.
function fn_str_length(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let text = require_string(["string"], pos_args, named, 0, pos)._0;
    root.value.Value_Number { _0: root.value.Number.unitless(root.std.int_to_f64(text.length())) }
}

/// `str-index($string, $substring)`: 1-based char index of the first
/// occurrence, or `null` when absent.
function fn_str_index(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["string", "substring"];
    let text = require_string(params, pos_args, named, 0, pos)._0;
    let sub = require_string(params, pos_args, named, 1, pos)._0;
    match (text.index_of(sub)) {
        // `find` gives a byte offset; convert to a 1-based char index.
        // PORT: `index_of` already gives the char offset.
        let idx: int => {
            root.value.Value_Number { _0: root.value.Number.unitless(root.std.int_to_f64(idx + 1)) }
        },
        null => root.value.Value_Null {  },
    }
}

/// Normalize a 1-based (possibly negative) index into a 1-based position used
/// for slicing. Index `0` stays `0`; negatives count from the end.
function normalize_index(index: int, len: int) -> int {
    if (index > 0) {
        index
    } else if (index == 0) {
        0
    } else {
        len + index + 1
    }
}

/// `str-slice($string, $start-at, $end-at: -1)`: 1-based inclusive slice with
/// negative indices counting from the end; preserves quotedness.
function fn_str_slice(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["string", "start-at", "end-at"];
    let t = require_string(params, pos_args, named, 0, pos);
    let text = t._0;
    let quoted = t._1;
    let chars = text.chars();
    let len = chars.length();

    let start_at = require_index(params, pos_args, named, 1, pos);
    let end_at = match (root.builtins.arg(params, pos_args, named, 2)) {
        let _v: root.value.Value => require_index(params, pos_args, named, 2, pos),
        null => -1,
    };

    // Resolve to 1-based positions, then clamp into range.
    let start = root.std.imax(normalize_index(start_at, len), 1);
    let end = root.std.imin(normalize_index(end_at, len), len);

    if (start > end || start > len || end < 1) {
        return quoted_str("", quoted);
    }
    // Indices are valid 1..=len here; convert to 0-based slice bounds.
    let lo = start - 1;
    let hi = end;
    let slice: string = root.std.join(chars.slice(lo, hi), "");
    quoted_str(slice, quoted)
}

/// `str-insert($string, $insert, $index)`: insert at a 1-based index
/// (negative counts from the end); preserves the host string's quotedness.
function fn_str_insert(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["string", "insert", "index"];
    let t = require_string(params, pos_args, named, 0, pos);
    let text = t._0;
    let quoted = t._1;
    let insert = require_string(params, pos_args, named, 1, pos)._0;
    let chars = text.chars();
    let len = chars.length();
    let index = require_index(params, pos_args, named, 2, pos);

    // Compute the 0-based offset at which `insert` is placed.
    let offset: int = if (index > 0) {
        root.std.imax(root.std.imin(index - 1, len), 0)
    } else if (index == 0) {
        0
    } else {
        root.std.iclamp(len + index + 1, 0, len)
    };

    let out = "";
    out = out + root.std.join(chars.slice(0, offset), "");
    out = out + insert;
    out = out + root.std.join(chars.slice(offset, len), "");
    quoted_str(out, quoted)
}

/// `unique-id()`: a randomly-generated unquoted string that is a valid CSS
/// identifier (`u` + base-36 digits) and differs on every call. dart-sass
/// exposes this both globally (deprecated) and as `string.unique-id`.
function fn_unique_id() -> root.value.Value {
    // PORT: `use std::cell::Cell; use std::time::{SystemTime, UNIX_EPOCH};` —
    // the `thread_local!` `STATE` is hoisted to `fn_unique_id__STATE()` (a
    // process-wide cell; see below), and the `STATE.with(|s| …)` closure body
    // is inlined as a block.
    let x = {
        let s = fn_unique_id__STATE();
        let x = s.get();
        if (x == 0n) {
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
        root.std.u64_wrapping_mul(x, 0x2545F4914F6CDD1Dn)
    };
    // dart-sass picks a value in [36^5, 36^6); render base-36 after a `u`.
    let range = (36).pow(6) - (36).pow(5);
    let n = (36).pow(5) + root.std.int_of(x % root.std.bigint_of(range));
    root.value.Value_Str { _0: root.value.SassStr { text: `u${to_base36(n)}`, quoted: false } }
}

/// `thread_local! { static STATE: Cell<u64> = const { Cell::new(0) }; }` inside
/// `fn_unique_id`.
// PORT: a top-level `client` holds the mutable cell (evaluated once, shared
// process-wide rather than per-thread).
client fn_unique_id__STATE_CELL = root.std.Cell<bigint> { value: 0n };

function fn_unique_id__STATE() -> root.std.Cell<bigint> {
    fn_unique_id__STATE_CELL
}

/// Render `n` in lowercase base-36.
function to_base36(n: int) -> string {
    // PORT: `const DIGITS: &[u8; 36]` → a local array of one-char strings.
    let DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz".chars();
    if (n == 0) {
        return "0";
    }
    let buf: string[] = [];
    while (n > 0) {
        buf.push(DIGITS[n % 36]);
        n = n / 36;
    }
    // PORT: in-place `buf.reverse()` → BAML's copying `reverse()`.
    buf = buf.reverse();
    root.std.join(buf, "")
}

/// `string.split($string, $separator, $limit: null)`: split `$string` on each
/// occurrence of `$separator`, returning a bracketed comma list of quoted
/// substrings. An empty `$separator` splits into individual characters. A
/// positive `$limit` caps the number of splits (so at most `limit + 1` parts).
function fn_split(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["string", "separator", "limit"];
    check_arity(pos_args, named, 3, pos);
    let t = require_string(params, pos_args, named, 0, pos);
    let text = t._0;
    let text_quoted = t._1;
    let sep = require_string(params, pos_args, named, 1, pos)._0;
    // `$limit` is the maximum number of splits (not parts). `null`/absent means
    // unlimited; it must be a positive integer otherwise.
    let limit: int? = match (root.builtins.arg(params, pos_args, named, 2)) {
        null => null,
        root.value.Value_Null {} => null,
        root.value.Value_Number { _0: let num } => {
            // PORT: IEEE comparison (`root.std.fgt`): a NaN compares false as
            // in Rust.
            if (!num.is_unitless() || root.std.fgt((num.value - num.value.round()).abs(), 1e-11)) {
                throw root.error.Error.at(`$limit: ${root.value.fmt_num(num.value, false)} is not an int.`, pos);
            }
            let l = root.std.f64_to_int(num.value.round());
            if (l < 1) {
                throw root.error.Error.at(`$limit: Must be 1 or greater, was ${l}.`, pos);
            }
            l
        },
        let other: root.value.Value => {
            throw root.error.Error.at(`$limit: ${other.to_css(false)} is not a number.`, pos);
        },
    };

    let parts = split_string(text, sep, limit);
    // Each part inherits the input string's quotedness (dart-sass).
    let items: root.value.Value[] = parts.map((p) -> root.value.Value {
        root.value.Value_Str { _0: root.value.SassStr { text: p, quoted: text_quoted } }
    });
    root.value.Value_List {
        _0: root.value.List {
            items: items,
            sep: root.value.ListSep.Comma,
            bracketed: true,
            keywords: null,
        },
    }
}

/// Split `text` on `sep`, honouring an optional cap on the number of splits.
/// An empty separator yields each character; an empty string yields no parts.
function split_string(text: string, sep: string, limit: int?) -> string[] {
    if (text == "") {
        return [];
    }
    if (sep == "") {
        // Split into individual characters (capped by `limit` splits, so the
        // tail beyond the cap stays joined).
        let chars = text.chars();
        return match (limit) {
            let n: int if n < chars.length() => {
                let out: string[] = chars.slice(0, n);
                out.push(root.std.join(chars.slice(n, chars.length()), ""));
                out
            },
            _ => chars,
        };
    }
    let out: string[] = [];
    let rest = text;
    let splits = 0;
    // PORT: `while let Some(idx) = rest.find(sep)` → `while let` over the
    // char-offset `index_of`.
    while let idx: int = rest.index_of(sep) {
        if (limit != null) {
            let max = limit;
            if (splits >= max) {
                break;
            }
        }
        out.push(rest.slice(0, idx));
        rest = rest.slice(idx + sep.length(), rest.length());
        splits += 1;
    }
    out.push(rest);
    out
}
