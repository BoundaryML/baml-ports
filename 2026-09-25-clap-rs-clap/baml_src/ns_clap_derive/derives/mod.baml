// Port of clap_derive/src/derives/mod.rs
//
//   mod args;       -> args.baml       (derive_args: gen_augment, gen_constructor)
//   mod into_app;   -> into_app.baml   (CommandFactory: gen_for_struct, gen_for_enum)
//   mod parser;     -> parser.baml     (derive_parser)
//   mod subcommand; -> subcommand.baml (derive_subcommand)
//   mod value_enum; -> value_enum.baml (derive_value_enum)
//
// Rust generates the trait impls as code; here each `gen_*` function *runs*
// the equivalent logic against the reflected type (`reflect.Type`).

/// A reflected struct field and its derive metadata (`(&Field, Item)`)
class FieldItem {
    name: string,
    ty: reflect.Type,
    item: Item,
    /// A literal-typed discriminator field (e.g. `kind: "push"`), filled in automatically
    tag: string?,
}

/// A reflected struct and its derive metadata
class StructInfo {
    ty: reflect.Type,
    cls: reflect.class.Type,
    ident: string,
    item: Item,
    fields: FieldItem[],
}

/// The identifier of a reflected type (`clap.examples.git.Cli` => `Cli`)
function type_ident(t: reflect.Type) -> string {
    t.to_string().split(".").at(-1) ?? t.to_string()
}

/// If the field type is a string literal type, its value
function literal_string(t: reflect.Type) -> string? {
    if let l: reflect.literal.Type = t.as_literal() {
        match (l.value()) {
            let s: string => s,
            _ => null,
        }
    } else {
        null
    }
}

/// `collect_args_fields`
function collect_args_fields(item: Item, cls: reflect.class.Type, ctx: EvalCtx) -> FieldItem[] {
    let out: FieldItem[] = [];
    for (let f in cls.fields()) {
        let fty = f.type ?? abort(`field ${f.name} has no type`);
        if let tag: string = literal_string(fty) {
            // A discriminator: not an argument
            out.push(FieldItem { name: f.name, ty: fty, item: Item.from_args_field(f.name, fty, null, item.casing, item.env_casing, ctx), tag: tag });
            continue;
        }
        let fi = Item.from_args_field(f.name, fty, f.meta.docstring, item.casing, item.env_casing, ctx);
        out.push(FieldItem { name: f.name, ty: fty, item: fi, tag: null });
    }
    out
}

/// A "witness" instance of `t`, used to dispatch the static methods of a
/// hand-written `Args`/`Subcommand`/`FromArgMatches` impl at runtime
/// (see `FromArgMatches.from_arg_matches_dyn`). `null` if no default instance
/// can be built.
function witness(t: reflect.Type) -> unknown {
    if (t.as_class() == null) {
        return null;
    }
    type T = unreflect(t);
    let j = default_json_for(t);
    baml.json.to<T>(j) catch_all (e) { _ => null }
}

/// Does the class hand-implement (or explicitly derive) `Args`?
function implements_args(t: reflect.Type) -> bool {
    t.implements(reflect.Type.of<root.clap_builder.Args>())
}

/// Does the class hand-implement `Subcommand`?
function implements_subcommand(t: reflect.Type) -> bool {
    t.implements(reflect.Type.of<root.clap_builder.Subcommand>())
}
