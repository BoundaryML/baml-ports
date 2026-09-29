// Port of clap_derive/src/derives/parser.rs

/// `derive_parser`: a `Parser` struct is named after the package
/// (`CARGO_PKG_NAME`) unless `#[command(name = ...)]` says otherwise.
function parser_struct_info(t: reflect.Type) -> StructInfo {
    let pkg_name = root.clap_builder.package_info().name;
    args_struct_info(t, Name.assigned_to(Computed { value: pkg_name }))
}
