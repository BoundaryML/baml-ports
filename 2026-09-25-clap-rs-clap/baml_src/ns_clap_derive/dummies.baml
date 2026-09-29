// Port of clap_derive/src/dummies.rs
//
// Rust emits dummy trait impls after a derive error so that the compiler
// reports only the original error. BAML panics on derive errors instead
// (see `macros.baml`), so there is nothing to generate.
