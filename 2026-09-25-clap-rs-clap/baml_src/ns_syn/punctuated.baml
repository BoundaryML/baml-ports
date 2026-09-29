// Port of syn-2.0.117/src/punctuated.rs
//
// `Punctuated<T, P>` is a sequence of `T` separated by `P`. Here it is an
// array; `parse_terminated` parses `T`s separated by commas with an optional
// trailing comma.

/// `Punctuated::<T, Token![,]>::parse_terminated` for a parser closure
function parse_terminated<T>(input: ParseBuffer, parser: (ParseBuffer) -> T throws Error) -> T[] throws Error {
    let out: T[] = [];
    while (!input.is_empty()) {
        out.push(parser(input));
        if (input.is_empty()) {
            break;
        }
        input.expect_punct(",");
    }
    out
}
