// Port of clap_derive-4.6.1/src/lib.rs
//
// This crate is custom derive for clap. It should not be used
// directly. See [clap documentation](https://docs.rs/clap)
// for the usage of `#[derive(Parser)]`.
//
// Rust implements `#[derive(Parser)]`, `#[derive(Args)]`,
// `#[derive(Subcommand)]` and `#[derive(ValueEnum)]` as procedural macros that
// generate trait impls at compile time. BAML has no macros; instead the traits
// in `clap_builder/derive.baml` have default method bodies that call into this
// namespace, which reflects over the type (`reflect.Type`) and interprets the
// `#[arg(...)]`/`#[command(...)]`/`#[value(...)]`/`#[group(...)]` attributes
// written in its doc comments.
//
//   src/lib.rs           -> lib.baml       (entry points)
//   src/attr.rs          -> attr.baml
//   src/item.rs          -> item.baml
//   src/macros.rs        -> macros.baml
//   src/dummies.rs       -> dummies.baml
//   src/derives/*.rs     -> derives/*.baml
//   src/utils/*.rs       -> utils/*.baml
//   (no counterpart)     -> eval.baml      (runs what Rust would have generated)
//
// Rust dependencies: `syn` (-> `root.syn`), `proc-macro2` (-> `root.proc_macro2`),
// `heck` (-> `root.heck`); `quote` is not needed since no code is generated.

/// `CommandFactory::command` for a `#[derive(Parser)]` class
function into_app<T>() -> root.clap_builder.Command {
    gen_for_struct(parser_struct_info(reflect.Type.of<T>()), false)
}

/// `CommandFactory::command_for_update` for a `#[derive(Parser)]` class
function into_app_for_update<T>() -> root.clap_builder.Command {
    gen_for_struct(parser_struct_info(reflect.Type.of<T>()), true)
}

/// `FromArgMatches::from_arg_matches` for a `#[derive(Parser)]` / `#[derive(Args)]` class
function from_arg_matches<T>(matches: root.clap_builder.ArgMatches) -> T throws root.clap_builder.Error {
    let t = reflect.Type.of<T>();
    let info = args_struct_info(t, null);
    let json: baml.json.json = gen_constructor(info, matches);
    baml.json.to<T>(json) catch (e) {
        let d: baml.json.DecodeError => abort(`cannot construct \`${t}\` from the parsed arguments: ${d.message} ${d.path}`),
    }
}

/// `FromArgMatches::update_from_arg_matches`
///
/// Rust's derive assigns each field in place (`self.field = ...`). BAML code
/// cannot assign a field chosen at runtime, so a derived update is not
/// available; implement `update_from_arg_matches` by hand for types that need it.
function update_from_arg_matches<T>(target: T, matches: root.clap_builder.ArgMatches) -> void throws root.clap_builder.Error {
    abort("`update_from_arg_matches` cannot be derived in BAML; implement `FromArgMatches.update_from_arg_matches` for this type")
}

/// `Args::group_id`
function args_group_id<T>() -> string? {
    gen_group_id(args_struct_info(reflect.Type.of<T>(), null))
}

/// `Args::augment_args`
function augment_args<T>(cmd: root.clap_builder.Command) -> root.clap_builder.Command {
    let info = args_struct_info(reflect.Type.of<T>(), null);
    gen_augment(info.fields, cmd, info.item, false)
}

/// `Args::augment_args_for_update`
function augment_args_for_update<T>(cmd: root.clap_builder.Command) -> root.clap_builder.Command {
    let info = args_struct_info(reflect.Type.of<T>(), null);
    gen_augment(info.fields, cmd, info.item, true)
}

/// `ValueEnum::value_variants` + `to_possible_value` for a BAML `enum`
function value_enum_variants<E>() -> root.clap_builder.EnumVariant[] {
    gen_value_enum_variants<E>()
}

/// `Subcommand::augment_subcommands` for a subcommand union type `U`
function augment_subcommands<U>(cmd: root.clap_builder.Command) -> root.clap_builder.Command {
    augment_subcommands_for(reflect.Type.of<U>(), cmd, false)
}

/// `Subcommand::has_subcommand` for a subcommand union type `U`
function has_subcommand<U>(name: string) -> bool {
    has_subcommand_for(reflect.Type.of<U>(), name)
}

/// `FromArgMatches::from_arg_matches` for a subcommand union type `U`
function subcommand_from_matches<U>(matches: root.clap_builder.ArgMatches) -> U throws root.clap_builder.Error {
    let json = subcommand_from_arg_matches(reflect.Type.of<U>(), matches);
    baml.json.to<U>(json) catch (e) {
        let d: baml.json.DecodeError => abort(`cannot construct subcommand: ${d.message}`),
    }
}
