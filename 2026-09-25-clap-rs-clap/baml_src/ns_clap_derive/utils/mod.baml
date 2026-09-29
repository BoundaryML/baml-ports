// Port of clap_derive/src/utils/mod.rs
//
//   mod doc_comments; -> doc_comments.baml (extract_doc_comment, format_doc_comment)
//   mod spanned;      -> not needed (spans are only used for compiler diagnostics)
//   mod ty;           -> ty.baml           (Ty, inner_type, sub_type, is_simple_ty)
//   mod error;        -> not needed (errors panic via `abort`)
