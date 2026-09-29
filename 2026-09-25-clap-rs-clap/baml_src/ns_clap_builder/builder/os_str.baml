// Port of clap_builder/src/builder/os_str.rs
//
// A UTF-8-encoded fixed string. Rust's `OsStr` may hold non-UTF-8 platform
// strings; BAML only has UTF-8 strings, so `OsStr` is `string`.
type OsStr = string
