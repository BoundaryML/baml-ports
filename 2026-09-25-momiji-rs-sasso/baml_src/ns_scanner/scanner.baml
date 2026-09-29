// Ported from sasso `src/scanner.rs` (namespace `root.scanner`).
//
// A character cursor over the source with line/column tracking.
//
// SCSS's lexical grammar is context-sensitive (a `:` can begin a
// declaration value or a pseudo-class selector), so the parser scans
// characters directly rather than over a fixed token stream. This
// cursor is the shared primitive it builds on.

/// A 1-based source position.
class Pos {
    /// 1-based line.
    line: int,
    /// 1-based column.
    col: int,
    /// The "no position" sentinel. `line == 0` can never be a real 1-based
    /// line, so it reads unambiguously as "unknown" (the source map drops it).
    function NONE() -> Pos {
        Pos { line: 0, col: 0 }
    }

    /// Whether this is a real recorded position rather than [`Pos::NONE`].
    function is_known(self) -> bool {
        self.line != 0
    }
}

/// An immutable snapshot of the cursor, used for backtracking lookahead.
class Mark {
    pos: int,
    line: int,
    col: int,
    /// The 1-based line/column the cursor stood at when the mark was taken —
    /// the start of a diagnostic span whose length is measured by
    /// [`Scanner::byte_len_from`].
    function pos_(self) -> Pos {
        Pos { line: self.line, col: self.col }
    }
}

class Scanner {
    chars: string[],
    pos: int,
    line: int,
    col: int,
    function new(src: string) -> Scanner {
        // A leading UTF-8 byte-order mark is part of the encoding, not the
        // document; dart-sass strips it before parsing so it never reaches the
        // output (and never triggers a spurious `@charset`).
        let src = root.std.strip_prefix(src, root.std.chr_unchecked(0xFEFF)) ?? src;
        Scanner { chars: src.chars(), pos: 0, line: 1, col: 1 }
    }

    function position(self) -> Pos {
        Pos { line: self.line, col: self.col }
    }

    function mark(self) -> Mark {
        Mark { pos: self.pos, line: self.line, col: self.col }
    }

    /// The number of source **bytes** (UTF-8) consumed since `m` was taken.
    /// Used to size a diagnostic span's caret underline (dart-sass measures
    /// span lengths in bytes).
    function byte_len_from(self, m: Mark) -> int {
        let start = root.std.imin(m.pos, self.chars.length());
        let end = root.std.imin(self.pos, self.chars.length());
        // PORT: `.iter().map(|c| c.len_utf8()).sum()` as an index loop.
        let n = 0;
        let i = start;
        while (i < end) {
            n += root.std.len_utf8(self.chars[i]);
            i += 1;
        }
        n
    }

    function reset(self, m: Mark) -> void {
        self.pos = m.pos;
        self.line = m.line;
        self.col = m.col;
    }

    function peek(self) -> string? {
        self.chars.at(self.pos)
    }

    function peek_at(self, offset: int) -> string? {
        self.chars.at(self.pos + offset)
    }

    /// The remaining unconsumed characters, for non-consuming lookahead.
    // PORT: returns a copy of the tail (Rust borrows a sub-slice).
    function rest(self) -> string[] {
        let start = root.std.imin(self.pos, self.chars.length());
        self.chars.slice(start, self.chars.length())
    }

    function bump(self) -> string? {
        let c = self.chars.at(self.pos);
        if (c != null) {
            let ch = c;
            self.pos += 1;
            if (ch == "\n") {
                self.line += 1;
                self.col = 1;
            } else {
                self.col += 1;
            }
        }
        c
    }

    /// The source text consumed since `m` was taken (for verbatim capture,
    /// e.g. a plain CSS `@import` URL emitted unchanged).
    function slice_from(self, m: Mark) -> string {
        let start = root.std.imin(m.pos, self.chars.length());
        let end = root.std.imin(self.pos, self.chars.length());
        root.std.concat(self.chars.slice(start, end))
    }

    /// Consume `c` if it is next; report whether it was consumed.
    function eat(self, c: string) -> bool {
        if (self.peek() == c) {
            self.bump();
            true
        } else {
            false
        }
    }
}
