// Port of clap_builder/src/builder/str.rs
//
// A UTF-8-encoded fixed string. Rust uses it to avoid allocations for
// `&'static str`; BAML strings are immutable values so `Str` is `string`.
type Str = string
