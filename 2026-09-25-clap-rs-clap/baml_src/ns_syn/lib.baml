// Port of syn-2.0.117 (the subset clap_derive relies on)
//
// Syn is a parsing library for parsing a stream of Rust tokens into a syntax
// tree of Rust source code. `clap_derive` uses it to parse `#[arg(...)]`,
// `#[command(...)]`, `#[value(...)]` and `#[group(...)]` attributes, whose
// values are arbitrary Rust expressions.
//
// The BAML derive reads those attributes from doc comments at runtime and
// interprets the expressions, so this namespace ports the parts of syn needed
// for that:
//
//   src/attr.rs        -> attr.baml        (Attribute, parse_args)
//   src/error.rs       -> error.baml       (Error)
//   src/expr.rs        -> expr.baml        (Expr and its variants)
//   src/lit.rs         -> lit.baml         (Lit, LitStr, LitInt, ...)
//   src/parse.rs       -> parse.baml       (ParseBuffer)
//   src/path.rs        -> path.baml        (Path, PathSegment)
//   src/punctuated.rs  -> punctuated.baml  (parse_terminated)
//
// Type syntax (`syn::Type`) is not needed: field types come from BAML
// reflection (`reflect.Type`) instead of from source tokens.
