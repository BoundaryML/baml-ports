// Port of anstream-1.0.0/src/lib.rs
//
// **Auto-adapting [`stdout`] / [`stderr`] streams**
//
// *A portable, auto-adapting stream*
//
// Modules:
//   pub mod adapter;  -> adapter/
//   mod auto;         -> auto.baml   (AutoStream)
//   mod strip;        -> covered by adapter/strip.baml
//   mod wincon;       -> not ported (Windows console API)
//
// Re-exports `colorchoice::ColorChoice` (see `root.colorchoice`).

/// Create an ANSI escape code compatible stdout
function stdout() -> AutoStream {
    AutoStream.auto(RawStream.Stdout)
}

/// Create an ANSI escape code compatible stderr
function stderr() -> AutoStream {
    AutoStream.auto(RawStream.Stderr)
}

/// `anstream::print!`
function print(s: string) -> void { stdout().write_str(s) }

/// `anstream::println!`
function println(s: string) -> void { stdout().write_str(s + "\n") }

/// `anstream::eprint!`
function eprint(s: string) -> void { stderr().write_str(s) }

/// `anstream::eprintln!`
function eprintln(s: string) -> void { stderr().write_str(s + "\n") }
