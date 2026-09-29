// Stand-ins for the parts of Python's builtins that tomli relies on and that
// BAML does not provide. This file has no counterpart in the original source
// tree; everything here is Python *runtime* behaviour that the original gets
// for free.
//
// Exceptions: BAML errors are plain values of any type (there is no class
// inheritance), so Python's exception hierarchy is flattened into independent
// classes. `TOMLDecodeError` (a `ValueError` subclass in Python) lives in
// `_parser.baml`; code that wants "any ValueError" must catch
// `ValueError | TOMLDecodeError` -- see `ValueErrorLike`.

/// Python's builtin `ValueError`.
class ValueError {
    message: string,
    implements baml.ToString {
        function to_string(self) -> string throws never {
            self.message
        }
    }
}

/// Python's builtin `TypeError`.
class TypeError {
    message: string,
    implements baml.ToString {
        function to_string(self) -> string throws never {
            self.message
        }
    }
}

/// Python's builtin `KeyError` (only used internally, like in the original).
class KeyError {
    message: string,
    implements baml.ToString {
        function to_string(self) -> string throws never {
            self.message
        }
    }
}

/// Python's builtin `RecursionError`.
class RecursionError {
    message: string,
    implements baml.ToString {
        function to_string(self) -> string throws never {
            self.message
        }
    }
}

/// Python's `except ValueError:` also catches `TOMLDecodeError`, its subclass.
type ValueErrorLike = ValueError | TOMLDecodeError;

/// Python's `sys.getrecursionlimit()` counterpart.
///
/// BAML has no configurable recursion limit, so this returns CPython's
/// default (1000). It is used, as in the original, to bound the number of
/// parts in a dotted key -- which the parser handles iteratively, so the
/// value is safe in BAML too. The *inline nesting* limit cannot use it; see
/// `vm_max_frames()` and `MAX_INLINE_NESTING()`.
function getrecursionlimit() -> int {
    1000
}

/// The BAML VM's hard call-stack limit (`bex_vm::vm::MAX_FRAMES`, not
/// configurable, not queryable from BAML). Overflowing it is an *uncatchable*
/// `baml.panics.StackOverflow` panic.
function vm_max_frames() -> int {
    256
}

/// Python's `repr()` for `str` values (used in error messages such as
/// `f"Found invalid character {src[pos]!r}"`).
function py_repr_str(s: string) -> string {
    let quote = if (s.includes("'") && !s.includes("\"")) {
        "\""
    } else {
        "'"
    };
    let out = quote;
    for (let cp in s.to_code_points()) {
        let ch = baml.String.from_code_points([cp]) catch (e) {
            _ => "?"
        };
        if (ch == quote || ch == "\\") {
            out = out + "\\" + ch;
        } else if (cp == 9) {
            out = out + "\\t";
        } else if (cp == 10) {
            out = out + "\\n";
        } else if (cp == 13) {
            out = out + "\\r";
        } else if (cp < 32 || cp == 127) {
            out = out + "\\x" + _hex_pad(cp, 2);
        } else if (cp >= 128 && cp < 160) {
            out = out + "\\x" + _hex_pad(cp, 2);
        } else {
            out = out + ch;
        }
    }
    out + quote
}

/// Python's `repr()` for a `tuple[str, ...]`, e.g. `('a',)` or `('a', 'b')`.
function py_repr_key(key: string[]) -> string {
    if (key.length() == 1) {
        return "(" + py_repr_str(key[0]) + ",)";
    }
    "("
        + key
            .map((k) -> {
                py_repr_str(k)
            })
            .join(", ")
        + ")"
}

function _hex_pad(n: int, width: int) -> string {
    let digits = "0123456789abcdef";
    let out = "";
    let v = n;
    while (v > 0) {
        out = (digits.at(v % 16) ?? "0") + out;
        v = v / 16;
    }
    while (out.length() < width) {
        out = "0" + out;
    }
    out
}

/// Python's `int(s, base)` for bases 2..16 (no prefix, no sign, underscores
/// between digits allowed). Result is a `bigint` because Python ints are
/// unbounded.
function py_int_digits(s: string, base: int) -> bigint throws ValueError {
    let digits = "0123456789abcdef";
    let acc = 0n;
    let seen = false;
    for (let ch in s.to_lower_case().chars()) {
        if (ch == "_") {
            continue;
        }
        let d = digits.index_of(ch);
        // NOTE: `d == null || d >= base` does not narrow `d` on the right of
        // `||` (E0004), hence the split checks.
        if (d == null) {
            throw ValueError { message: "invalid literal for int() with base " + base.to_string() + ": " + py_repr_str(s) };
        }
        if (d >= base) {
            throw ValueError { message: "invalid literal for int() with base " + base.to_string() + ": " + py_repr_str(s) };
        }
        acc = acc * base + d;
        seen = true;
    }
    if (!seen) {
        throw ValueError { message: "invalid literal for int() with base " + base.to_string() + ": " + py_repr_str(s) };
    }
    acc
}

/// Python's `int(s, 0)`: an optional sign followed by a decimal literal or a
/// `0x`/`0o`/`0b`-prefixed literal, with single underscores between digits.
function py_int_base0(s: string) -> bigint throws ValueError {
    let body = s;
    let negative = false;
    if (body.starts_with("+") || body.starts_with("-")) {
        negative = body.starts_with("-");
        body = body.slice(1, body.length());
    }
    let lower = body.to_lower_case();
    let value = if (lower.starts_with("0x")) {
        py_int_digits(body.slice(2, body.length()), 16)
    } else if (lower.starts_with("0o")) {
        py_int_digits(body.slice(2, body.length()), 8)
    } else if (lower.starts_with("0b")) {
        py_int_digits(body.slice(2, body.length()), 2)
    } else {
        py_int_digits(body, 10)
    };
    if (negative) {
        -value
    } else {
        value
    }
}

/// Python's builtin `float(s)` for the inputs tomli hands it: decimal floats
/// (possibly with underscores between digits), and `inf`/`nan` with an
/// optional sign. `baml.Float.parse` rejects underscores, so strip them first.
function py_float(s: string) -> float throws ValueError {
    baml.Float.parse(s.replace_all("_", "")) catch (e) {
        baml.errors.ParseError => {
            throw ValueError { message: "could not convert string to float: " + py_repr_str(s) }
        },
    }
}

/// Python's `str.find(sub, start)` (returns `null` instead of -1).
///
/// `string.index_of` has no start offset, so this slices first, which copies
/// the tail of `s` (O(len(s)) per call). The stdlib has an internal
/// `baml.regex._index_of_from` that does exactly this without the copy, but it
/// is private API.
function str_find(s: string, sub: string, start: int) -> int? {
    let idx = s.slice(start, s.length()).index_of(sub);
    if (idx == null) {
        return null;
    }
    idx + start
}

/// Python's `chr(i)`.
function chr(cp: int) -> string {
    baml.String.from_code_points([cp]) catch (e) {
        baml.errors.InvalidArgument => baml.sys.panic("chr() arg not in range: " + cp.to_string())
    }
}

/// `bigint` -> `int` for values known to fit.
function bigint_to_int(n: bigint) -> int {
    n.to_int() catch (e) {
        baml.errors.InvalidArgument => {
            baml.sys.panic("bigint does not fit in int: " + n.to_string())
        }
    }
}

/// Python's `str.count(sub, start, end)`.
function str_count(s: string, sub: string, start: int, end: int) -> int {
    s.slice(start, end).split(sub).length() - 1
}

/// Python's `str.rindex(sub, start, end)`.
function str_rindex(s: string, sub: string, start: int, end: int) -> int {
    let idx = s.slice(start, end).last_index_of(sub);
    // NOTE: a bare `baml.sys.panic(...)` statement (return type `never`)
    // inside `if (idx == null) { ... }` does not narrow `idx` afterwards, so
    // use an if/else expression.
    if (idx == null) {
        baml.sys.panic("ValueError: substring not found")
    } else {
        idx + start
    }
}

/// Python's `repr()` for the handful of value kinds that show up in exception
/// `args` in this code base.
function py_repr(v: unknown) -> string {
    match (v) {
        let s: string => py_repr_str(s),
        null => "None",
        true => "True",
        false => "False",
        let i: int => i.to_string(),
        let o: unknown => `${o}`,
    }
}

/// Python's `BaseException.__str__`.
function py_exception_str(args: unknown[]) -> string {
    if (args.length() == 0) {
        return "";
    }
    if (args.length() == 1) {
        return match (args[0]) {
            let s: string => s,
            let o: unknown => py_repr(o),
        };
    }
    "("
        + args
            .map((a) -> {
                py_repr(a)
            })
            .join(", ")
        + ")"
}

/// Python's `warnings.warn(message, category)`.
///
/// BAML has no warnings machinery; the warning is logged instead, which means
/// tests cannot observe it (`assertWarns` is not portable).
function warnings_warn(message: string, category: string) -> void {
    log.warn(category + ": " + message);
}

/// A `frozenset[str]` of single characters.
///
/// BAML has no set type (and no module-level constants to build one once), so
/// the set is re-created on every use. It is backed by a plain string of its
/// members, which is far cheaper to build than a `map<string, bool>`, and
/// membership is a substring test (the sets hold at most ~70 characters).
class CharSet {
    _chars: string,

    function from_string(chars: string) -> CharSet {
        CharSet { _chars: chars }
    }

    function from_code_points(cps: int[]) -> CharSet {
        let chars = baml.String.from_code_points(cps) catch (e) {
            baml.errors.InvalidArgument => baml.sys.panic("invalid code point in CharSet")
        };
        CharSet { _chars: chars }
    }

    /// `char in charset`, where `char` may be `None` (never a member).
    function contains(self, ch: string?) -> bool {
        if (ch == null) {
            return false;
        }
        ch.length() == 1 && self._chars.includes(ch)
    }

    /// `self | other`
    function union(self, other: CharSet) -> CharSet {
        CharSet { _chars: self._chars + other._chars }
    }

    /// `self - other`
    function minus(self, other: CharSet) -> CharSet {
        // NOTE (performance): not `.filter(...).join("")` -- `Array.join`
        // renders every element through `string.from` and costs ~13us per
        // element in a release build.
        let out = "";
        for (let c in self._chars.chars()) {
            if (!other._chars.includes(c)) {
                out = out + c;
            }
        }
        CharSet { _chars: out }
    }

    /// `self.isdisjoint(s)` for a string `s` (an iterable of characters).
    function isdisjoint(self, s: string) -> bool {
        for (let c in s.chars()) {
            if (self._chars.includes(c)) {
                return false;
            }
        }
        true
    }

    /// `self.issuperset(s)` for a string `s` (an iterable of characters).
    function issuperset(self, s: string) -> bool {
        for (let c in s.chars()) {
            if (!self._chars.includes(c)) {
                return false;
            }
        }
        true
    }
}
