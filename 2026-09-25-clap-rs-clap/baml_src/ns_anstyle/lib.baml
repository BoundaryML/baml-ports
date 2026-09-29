// Port of anstyle/src/lib.rs
//
// ANSI Text Styling
//
// *A portable format for sharing ANSI text styles*
//
// `anstyle` is a dependency of `clap_builder` (via `clap_builder::builder::styling`).
// In this port every Rust crate is a BAML namespace (`ns_anstyle/` => `root.anstyle`)
// and every Rust module is a file (`src/style.rs` => `style.baml`).
//
// Rust re-exports:
//   pub use color::*;   -> color.baml
//   pub use effect::*;  -> effect.baml
//   pub use reset::*;   -> reset.baml
//   pub use style::*;   -> style.baml
