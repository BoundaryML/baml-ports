// Ported from sasso `src/error.rs` (namespace `root.error`).
//
// The compiler error type.

/// A compilation error, carrying a human-readable message and a 1-based
/// source position (`line`/`col` are `0` when the position is unknown).
///
/// Implements [`std::error::Error`], so it composes with `?` and the
/// wider error ecosystem.
///
/// For byte-exact dart-sass diagnostics the evaluator attaches a span
/// `length` (in source bytes) and a [`rendered`](Error::rendered) snippet
/// block at the AST-node boundary. When `rendered` is present, [`Display`]
/// emits it verbatim (the full `Error: …` + source-span snippet + stack
/// trace); otherwise it falls back to the legacy `Error: <msg> (line:col)`
/// one-liner.
class Error {
    /// Human-readable description of what went wrong.
    message: string,
    /// 1-based line number, or `0` if unknown.
    line: int,
    /// 1-based column number, or `0` if unknown.
    col: int,
    /// Length of the offending span, in **bytes** of the source. `0` when the
    /// span length is unknown (the renderer still draws a single caret).
    length: int,
    /// The fully rendered diagnostic block (header + snippet + frames), set by
    /// the evaluator once the source/url/glyph context is known. `None` until
    /// then; [`Display`] falls back to the legacy one-liner.
    rendered: string?,
    function at(message: string, pos: root.scanner.Pos) -> Error {
        Error { message: message, line: pos.line, col: pos.col, length: 0, rendered: null }
    }

    function unpositioned(message: string) -> Error {
        Error { message: message, line: 0, col: 0, length: 0, rendered: null }
    }

    /// Attach a span length (in source bytes) if one is not already set. Used at
    /// AST-node boundaries to size the caret underline.
    // PORT: Rust takes `mut self` by value; this returns a shallow copy so an
    // aliased original is never modified.
    function with_length(self, length: int) -> Error {
        let e = Error { ...self };
        if (e.length == 0) {
            e.length = length;
        }
        e
    }

    /// Attach a span length to an error raised AT `pos` — a statement sizing
    /// the caret of a failure it reported itself, without touching one that
    /// came from somewhere else (a nested file, a member's own span).
    // PORT: returns a modified shallow copy (see `with_length`).
    function with_length_at(self, pos: root.scanner.Pos, length: int) -> Error {
        let e = Error { ...self };
        if (e.length == 0 && e.line == pos.line && e.col == pos.col) {
            e.length = length;
        }
        e
    }

    /// Whether a primary `line`/`col` position has been recorded.
    function has_position(self) -> bool {
        self.line > 0
    }

    implements baml.ToString {
        function to_string(self) -> string {
            if let r: string = self.rendered {
                return r;
            }
            if (self.line > 0) {
                `Error: ${self.message} (${self.line}:${self.col})`
            } else {
                `Error: ${self.message}`
            }
        }
    }

    // PORT: `impl std::error::Error` dropped (derive-like / not needed in BAML).
}
