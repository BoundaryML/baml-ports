// Port of clap_derive/src/macros.rs
//
// `abort!` / `format_err!` report a compile error at a span. The BAML derive
// runs when the `Command` is built, so these become panics with the same
// messages.

/// `abort!(span, "...")`
function abort(message: string) -> never {
    baml.sys.panic(`clap_derive: ${message}`)
}
