// Port of anstyle/src/macros.rs
//
// Rust's `escape!` macro concatenates `"\x1B[" ... "m"` at compile time. BAML
// string literals have no `\x1B` escape, so the ESC byte is built from its code
// point instead.

/// The ASCII escape character (`\x1B`).
function esc() -> string {
    baml.String.from_code_points([27]) catch_all (e) { _ => "" }
}

/// `escape!("3", "1")` => `"\x1B[31m"`
function escape(parts: string[]) -> string {
    `${esc()}[${parts.join("")}m`
}
