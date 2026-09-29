// Port of clap_builder/src/builder/resettable.rs
//
// Clearable builder value
//
// This allows a builder function to both accept any value that can [`Into::into`] `T` (like
// `&str` into `OsStr`) as well as `None` to reset to the default value.
//
// Rust: `enum Resettable<T> { Value(T), Reset }` plus the `IntoResettable<T>`
// conversion trait. In BAML this is simply `T?`: builder methods take a
// nullable argument and `null` means `Resettable::Reset`, e.g.
// `Arg.new("x").short("x")` sets and `Arg.new("x").short(null)` resets.
