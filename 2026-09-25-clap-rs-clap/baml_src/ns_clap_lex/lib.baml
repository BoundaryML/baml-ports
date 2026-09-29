// Port of clap_lex-1.1.0/src/lib.rs
//
// Minimal, flexible command-line parser
//
// As opposed to a declarative parser, this processes arguments as a stream of tokens.  As lexing
// a command-line is not exactly straightforward, we break it down into steps:
// - `RawArgs` to get an iterator of `ParsedArg`s
// - `ParsedArg` to classify the arg (`is_long`, `to_short`, ...)
//
// OS strings: Rust works on `OsStr` so that non-UTF-8 arguments survive. BAML
// strings are always valid UTF-8, so every `OsStr` here is a `string`, and the
// `Result<&str, &OsStr>` return types collapse to `string`.
//
//   mod ext;           -> ext.baml  (OsStrExt)
//   pub use std::io::SeekFrom;

/// `std::io::SeekFrom`
type SeekFrom = SeekFromStart | SeekFromEnd | SeekFromCurrent

/// `SeekFrom::Start(u64)`
class SeekFromStart { pos: int }

/// `SeekFrom::End(i64)`
class SeekFromEnd { pos: int }

/// `SeekFrom::Current(i64)`
class SeekFromCurrent { pos: int }

/// Command-line arguments
class RawArgs {
    _items: string[],

    /// **NOTE:** The argument returned will be the current binary.
    ///
    /// Rust: `std::env::args_os()`. Under `baml run <target> -- ...` (and a
    /// `baml pack`ed binary) `baml.sys.argv()` is `[runtime, target, ...args]`,
    /// so the target name stands in for the binary name.
    function from_args() -> RawArgs {
        RawArgs.new(args_os())
    }

    /// # Example
    ///
    /// ```baml
    /// let raw = root.clap_lex.RawArgs.new(["bin", "foo.txt"]);
    /// let cursor = raw.cursor();
    /// let _bin = raw.next_os(cursor);
    /// let arg = raw.next(cursor)?.to_value();
    /// ```
    function new(iter: string[]) -> RawArgs {
        RawArgs { _items: iter.slice(0, iter.length()) }
    }

    /// Create a cursor for walking the arguments
    function cursor(self) -> ArgCursor {
        ArgCursor.new()
    }

    /// Advance the cursor, returning the next `ParsedArg`
    function next(self, cursor: ArgCursor) -> ParsedArg? {
        let next = self.next_os(cursor);
        if let s: string = next { ParsedArg.new(s) } else { null }
    }

    /// Advance the cursor, returning a raw argument value.
    function next_os(self, cursor: ArgCursor) -> string? {
        let next = self._items.at(cursor.cursor);
        cursor.cursor = cursor.cursor + 1;
        next
    }

    /// Return the next `ParsedArg`
    function peek(self, cursor: ArgCursor) -> ParsedArg? {
        let next = self.peek_os(cursor);
        if let s: string = next { ParsedArg.new(s) } else { null }
    }

    /// Return a raw argument value.
    function peek_os(self, cursor: ArgCursor) -> string? {
        self._items.at(cursor.cursor)
    }

    /// Return all remaining raw arguments, advancing the cursor to the end
    function remaining(self, cursor: ArgCursor) -> string[] {
        let start = if (cursor.cursor < self._items.length()) { cursor.cursor } else { self._items.length() };
        let remaining = self._items.slice(start, self._items.length());
        cursor.cursor = self._items.length();
        remaining
    }

    /// Adjust the cursor's position
    function seek(self, cursor: ArgCursor, pos: SeekFrom) -> void {
        let len = self._items.length();
        let p = match (pos) {
            let s: SeekFromStart => s.pos,
            let e: SeekFromEnd => max_int(len + e.pos, 0),
            let c: SeekFromCurrent => max_int(cursor.cursor + c.pos, 0),
        };
        cursor.cursor = min_int(p, len);
    }

    /// Inject arguments before the `RawArgs::next`
    function insert(self, cursor: ArgCursor, insert_items: string[]) -> void {
        let at = min_int(cursor.cursor, self._items.length());
        self._items.splice(at, 0, insert_items) catch_all (e) { _ => null };
    }

    /// Any remaining args?
    function is_end(self, cursor: ArgCursor) -> bool {
        self.peek_os(cursor) == null
    }
}

/// `std::env::args_os()`
///
/// `baml.sys.argv()` is `[runtime, target, ...args]` both under `baml run` and
/// for a `baml pack`ed executable. The first element returned plays the role of
/// Rust's `argv[0]`:
/// - for a packed executable it is the executable's path;
/// - under `baml run <target>` it is derived from the target the way Cargo names
///   example binaries: `examples.git.main` => `git` (a trailing `main` segment is
///   dropped and the last remaining segment is used).
function args_os() -> string[] {
    let argv = baml.sys.argv();
    if (argv.length() < 2) {
        return argv;
    }
    let runtime = argv[0].split("/").at(-1) ?? argv[0];
    let bin = argv[0];
    if (runtime == "baml-cli" || runtime == "baml") {
        let segments = argv[1].split(".");
        if (segments.length() > 1 && segments[segments.length() - 1] == "main") {
            segments = segments.slice(0, segments.length() - 1);
        }
        bin = segments.at(-1) ?? argv[1];
    }
    let args = [bin].concat(argv.slice(2, argv.length()));
    args
}

/// Position within `RawArgs`
class ArgCursor {
    cursor: int,

    function new() -> ArgCursor { ArgCursor { cursor: 0 } }
}

/// Command-line Argument
class ParsedArg {
    _inner: string,

    function new(inner: string) -> ParsedArg { ParsedArg { _inner: inner } }

    /// Argument is length of 0
    function is_empty(self) -> bool { self._inner.is_empty() }

    /// Does the argument look like a stdio argument (`-`)
    function is_stdio(self) -> bool { self._inner == "-" }

    /// Does the argument look like an argument escape (`--`)
    function is_escape(self) -> bool { self._inner == "--" }

    /// Does the argument look like a negative number?
    ///
    /// This won't parse the number in full but attempts to see if this looks
    /// like something along the lines of `-3`, `-0.3`, or `-33.03`
    function is_negative_number(self) -> bool {
        if (self._inner.starts_with("-")) {
            is_number(self._inner.slice(1, self._inner.length()))
        } else {
            false
        }
    }

    /// Treat as a long-flag
    ///
    /// Returns `(flag, value)`: `--flag=value` => `("flag", "value")`
    function to_long(self) -> LongFlag? {
        let raw = self._inner;
        if (!raw.starts_with("--")) {
            return null;
        }
        let remainder = raw.slice(2, raw.length());
        if (remainder.is_empty()) {
            return null;
        }

        if let idx: int = remainder.index_of("=") {
            LongFlag { flag: remainder.slice(0, idx), value: remainder.slice(idx + 1, remainder.length()) }
        } else {
            LongFlag { flag: remainder, value: null }
        }
    }

    /// Can treat as a long-flag
    function is_long(self) -> bool {
        self._inner.starts_with("--") && !self.is_escape()
    }

    /// Treat as a short-flag
    function to_short(self) -> ShortFlags? {
        if (self._inner.starts_with("-")) {
            let remainder = self._inner.slice(1, self._inner.length());
            if (remainder.starts_with("-")) {
                null
            } else if (remainder.is_empty()) {
                null
            } else {
                ShortFlags.new(remainder)
            }
        } else {
            null
        }
    }

    /// Can treat as a short-flag
    function is_short(self) -> bool {
        self._inner.starts_with("-") && !self.is_stdio() && !self._inner.starts_with("--")
    }

    /// Treat as a value
    ///
    /// **NOTE:** May return a flag or an escape.
    function to_value_os(self) -> string { self._inner }

    /// Treat as a value
    ///
    /// **NOTE:** May return a flag or an escape.
    function to_value(self) -> string { self._inner }

    /// Safely print an argument that may contain non-UTF8 content
    function display(self) -> string { self._inner }
}

/// `(Result<&str, &OsStr>, Option<&OsStr>)` returned by `ParsedArg::to_long`
class LongFlag {
    flag: string,
    value: string?,
}

/// Walk through short flags within a `ParsedArg`
class ShortFlags {
    _inner: string,
    _chars: string[],
    _pos: int,

    function new(inner: string) -> ShortFlags {
        ShortFlags { _inner: inner, _chars: inner.chars(), _pos: 0 }
    }

    /// Move the iterator forward by `n` short flags
    ///
    /// Returns the number of flags actually advanced when fewer than `n` remain.
    function advance_by(self, n: int) -> int? {
        for (let i in baml.iter.Range.new(0, n)) {
            if (self.next_flag() == null) {
                return i;
            }
        }
        null
    }

    /// No short flags left
    function is_empty(self) -> bool { self._pos >= self._chars.length() }

    /// Does the short flag look like a number
    ///
    /// Ideally call this before doing any iterator
    function is_negative_number(self) -> bool {
        is_number(self._chars.slice(self._pos, self._chars.length()).join(""))
    }

    /// Advance the iterator, returning the next short flag on success
    function next_flag(self) -> string? {
        let c = self._chars.at(self._pos);
        if (c != null) {
            self._pos = self._pos + 1;
        }
        c
    }

    /// Advance the iterator, returning everything left as a value
    function next_value_os(self) -> string? {
        if (self._pos < self._chars.length()) {
            let remainder = self._chars.slice(self._pos, self._chars.length()).join("");
            self._pos = self._chars.length();
            remainder
        } else {
            null
        }
    }

    /// `impl Iterator for ShortFlags`
    function next(self) -> string? { self.next_flag() }
}

function is_number(arg: string) -> bool {
    // Return true if this looks like an integer or a float where it's all
    // digits plus an optional single dot after some digits.
    //
    // For floats allow forms such as `1.`, `1.2`, `1.2e10`, etc.
    let seen_dot = false;
    let position_of_e: int? = null;
    let chars = arg.chars();
    for (let i in baml.iter.Range.new(0, chars.length())) {
        let c = chars[i];
        if (c.is_ascii_numeric()) {
            // Digits are always valid
        } else if (c == "." && !seen_dot && position_of_e == null && i > 0) {
            // Allow a `.`, but only one, only if it comes before an
            // optional exponent, and only if it's not the first character.
            seen_dot = true;
        } else if ((c == "e" || c == "E") && position_of_e == null && i > 0) {
            // Allow an exponent `e`/`E` but only at most one after the first
            // character.
            position_of_e = i;
        } else {
            return false;
        }
    }

    // Disallow `-1e` which isn't a valid float since it doesn't actually have
    // an exponent.
    match (position_of_e) {
        let i: int => i != chars.length() - 1,
        null => true,
    }
}

function min_int(a: int, b: int) -> int { if (a < b) { a } else { b } }
function max_int(a: int, b: int) -> int { if (a > b) { a } else { b } }
