// Port of clap_derive/src/derives/value_enum.rs

/// `impl ValueEnum::value_variants` + `to_possible_value` for a BAML `enum`
function gen_value_enum_variants<E>() -> root.clap_builder.EnumVariant[] {
    let t = reflect.Type.of<E>();
    let et = t.as_enum() ?? abort(`\`#[derive(ValueEnum)]\` only supports enums, got \`${t}\``);
    let ctx = EvalCtx.for_type(t);
    let ident = type_ident(t);
    let item = Item.from_value_enum(et.meta().docstring, Name.derived_from(ident), ident, ctx);

    let out: root.clap_builder.EnumVariant[] = [];
    for (let v in et.values()) {
        let vitem = Item.from_value_enum_variant(v.meta.docstring, v.name, item.casing, item.env_casing, ctx);
        if (vitem.kind.tag == KindTag.Skip) {
            continue;
        }
        let name = vitem.cased_name();
        let pv = root.clap_builder.PossibleValue.new(name);
        for (let m in vitem.doc_comment.concat(vitem.methods)) {
            pv = apply_possible_value_method(pv, m, ctx);
        }
        let json_name: baml.json.json = v.name;
        let value = baml.json.to<E>(json_name) catch_all (e) { _ => abort(`cannot construct ${ident}.${v.name}`) };
        out.push(root.clap_builder.EnumVariant { value: value, possible_value: pv });
    }
    out
}

/// The possible value name of `E::variant` (for `default_value_t` with `value_enum`)
function value_enum_possible_value_name(et: reflect.enum.Type, variant: string, ctx: EvalCtx) -> string {
    let item = Item.from_value_enum(et.meta().docstring, Name.derived_from(variant), variant, ctx);
    let v = et.values().find((x) -> { x.name == variant }) ?? abort(`unknown variant \`${variant}\``);
    let vitem = Item.from_value_enum_variant(v.meta.docstring, v.name, item.casing, item.env_casing, ctx);
    vitem.cased_name()
}

function apply_possible_value_method(pv: root.clap_builder.PossibleValue, m: Method, ctx: EvalCtx) -> root.clap_builder.PossibleValue {
    let a = m.args.map((x) -> { eval_arg(x, ctx) });
    let a0: unknown = a.at(0);
    match (m.name) {
        "help" => pv.help(as_styled(a0)),
        "hide" => pv.hide(as_bool(a0)),
        "alias" => pv.alias(as_opt_string(a0)),
        "aliases" => pv.aliases(as_string_list(a0)),
        _ => abort(`unknown \`PossibleValue\` method \`${m.name}\``),
    }
}
