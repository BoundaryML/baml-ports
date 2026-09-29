// A growable string: the port of a Rust `String` that is appended to in a
// loop, or passed around as `&mut String` (BAML strings are immutable values,
// so a callee cannot append to its caller's `string`).
//
// Offsets and lengths are in CHARACTERS (Unicode scalar values), consistent
// with BAML's `length()`/`slice()` — see PORTING_GUIDE.md "Strings". Use
// `byte_len()` where the Rust code needs the UTF-8 byte count.
//
// BAML's `a + b` builds a deferred rope node; a rope that is hundreds of
// thousands of nodes deep overflows the VM's native stack when it is measured.
// `StrBuf` flattens the rope every `FLATTEN_EVERY` appends so it stays shallow.

class StrBuf {
    s: string,
    /// Character count of `s`, tracked incrementally.
    n: int,
    /// Appends since the rope was last flattened.
    pending: int,

    function new() -> StrBuf {
        StrBuf { s: "", n: 0, pending: 0 }
    }

    function from(s: string) -> StrBuf {
        StrBuf { s: s, n: s.length(), pending: 0 }
    }

    /// `String::with_capacity(_)`.
    function with_capacity(capacity: int) -> StrBuf {
        StrBuf { s: "", n: 0, pending: 0 }
    }

    /// Collapse the rope into one flat buffer.
    function flatten(self) -> void {
        if (self.pending > 0) {
            let _ = self.s.ends_with("");
            self.pending = 0;
        }
    }

    function push_str(self, x: string) -> void {
        if (x == "") {
            return;
        }
        self.s = self.s + x;
        self.n += x.length();
        self.pending += 1;
        if (self.pending >= 1024) {
            self.flatten();
        }
    }

    /// `String::push(char)`; `c` is a one-character string.
    function push(self, c: string) -> void {
        self.push_str(c);
    }

    /// Character count (Rust `len()` is bytes; see the header).
    function len(self) -> int {
        self.n
    }

    /// UTF-8 byte count — Rust's `String::len()`.
    function byte_len(self) -> int {
        self.s.byte_length()
    }

    function is_empty(self) -> bool {
        self.n == 0
    }

    /// The contents, flattened.
    function as_str(self) -> string {
        self.flatten();
        self.s
    }

    implements baml.ToString {
        function to_string(self) -> string {
            self.as_str()
        }
    }

    /// Replace the whole contents.
    function set(self, s: string) -> void {
        self.s = s;
        self.n = s.length();
        self.pending = 0;
    }

    /// `std::mem::take(&mut s)`: return the contents and leave it empty.
    function take(self) -> string {
        let out = self.as_str();
        self.clear();
        out
    }

    function clear(self) -> void {
        self.s = "";
        self.n = 0;
        self.pending = 0;
    }

    /// Keep the first `new_len` characters.
    function truncate(self, new_len: int) -> void {
        if (new_len < self.n) {
            self.flatten();
            self.s = self.s.slice(0, new_len);
            self.n = new_len;
        }
    }

    /// Remove and return the last character.
    function pop(self) -> string? {
        if (self.n == 0) {
            return null;
        }
        self.flatten();
        let last = self.s.at(-1);
        self.s = self.s.slice(0, self.n - 1);
        self.n -= 1;
        last
    }

    /// The last character, if any (`s.chars().last()`).
    function last_char(self) -> string? {
        if (self.n == 0) {
            return null;
        }
        self.flatten();
        self.s.at(-1)
    }

    /// The character at char offset `i`.
    function char_at(self, i: int) -> string? {
        self.flatten();
        self.s.at(i)
    }

    function ends_with(self, suffix: string) -> bool {
        self.flatten();
        self.s.ends_with(suffix)
    }

    function starts_with(self, prefix: string) -> bool {
        self.flatten();
        self.s.starts_with(prefix)
    }

    function includes(self, needle: string) -> bool {
        self.flatten();
        self.s.includes(needle)
    }

    /// `&s[start..end]` in char offsets.
    function slice(self, start: int, end: int) -> string {
        self.flatten();
        self.s.slice(start, end)
    }

    /// `&s[start..]` in char offsets.
    function slice_from(self, start: int) -> string {
        self.flatten();
        self.s.slice(start, self.n)
    }

    /// `s.insert_str(idx, x)` at char offset `idx`.
    function insert_str(self, idx: int, x: string) -> void {
        self.flatten();
        self.set(self.s.slice(0, idx) + x + self.s.slice(idx, self.n));
    }

    /// `s.insert(idx, c)`.
    function insert(self, idx: int, c: string) -> void {
        self.insert_str(idx, c);
    }

    /// `s.remove(idx)`: remove and return the char at `idx`.
    function remove(self, idx: int) -> string {
        self.flatten();
        let c = self.s.at(idx) ?? baml.sys.panic("StrBuf.remove: index out of bounds");
        self.set(self.s.slice(0, idx) + self.s.slice(idx + 1, self.n));
        c
    }

    /// `s.replace_range(start..end, x)` in char offsets.
    function replace_range(self, start: int, end: int, x: string) -> void {
        self.flatten();
        self.set(self.s.slice(0, start) + x + self.s.slice(end, self.n));
    }
}
