// Port of clap_derive/src/derives/subcommand.rs
//
// A Rust `#[derive(Subcommand)] enum` is a BAML union type whose members are
// the variants:
//
//   Rust                                  BAML
//   ------------------------------------  ------------------------------------------
//   Add { name: String }                  class Add { name: string }
//   Add(AddArgs)                          class AddArgs { ... }  (+ `#[command(name = "add")]`)
//   Stop                                  "stop"   (a string literal member)
//   #[command(external_subcommand)]       string[]
//   External(Vec<String>)
//
// The subcommand name is the kebab-cased class name, or the value of a
// literal-typed discriminator field (`kind: "push"`), or `#[command(name)]`.
// Because `baml.json.to` decodes a union as its first member that fits,
// structurally identical variants need a discriminator; the derive checks this
// when building the `Command` (Rust reports such problems at compile time too).

enum VariantKind {
    Class,
    Literal,
    External,
}

class VariantInfo {
    kind: VariantKind,
    name: string,
    ty: reflect.Type,
    item: Item?,
    info: StructInfo?,
}

/// The members of a subcommand type (a union, or a single class)
function subcommand_variants(t: reflect.Type) -> VariantInfo[] {
    let members: reflect.Type[] = if let u: reflect.union.Type = t.as_union() { u.member_types() } else { [t] };
    let ctx = EvalCtx.for_type(t);
    let out: VariantInfo[] = [];
    for (let m in members) {
        if let lit: string = literal_string(m) {
            out.push(VariantInfo { kind: VariantKind.Literal, name: lit, ty: m, item: null, info: null });
            continue;
        }
        if (m.as_array() != null) {
            out.push(VariantInfo { kind: VariantKind.External, name: "", ty: m, item: null, info: null });
            continue;
        }
        let cls = m.as_class() ?? abort(`subcommand variant \`${m}\` must be a class, a string literal or \`string[]\``);
        let vctx = EvalCtx.for_type(m);
        let ident = type_ident(m);
        let item = Item.from_subcommand_variant(cls.meta().docstring, ident, Ty.Other, DEFAULT_CASING(), DEFAULT_ENV_CASING(), vctx);
        let info = StructInfo { ty: m, cls: cls, ident: ident, item: item, fields: collect_args_fields(item, cls, vctx) };
        let tag = info.fields.find((f) -> { f.tag != null });
        let name = if (item.name.is_assigned()) {
            item.cased_name()
        } else if let a: string = cls.meta().alias {
            a
        } else if let tf: FieldItem = tag {
            tf.tag ?? item.cased_name()
        } else {
            item.cased_name()
        };
        out.push(VariantInfo { kind: VariantKind.Class, name: name, ty: m, item: item, info: info });
    }
    check_unambiguous(out);
    out
}

/// Would `baml.json.to` decode `later`'s JSON as `earlier`? (union members are tried in order)
function accepts(earlier: StructInfo, later: StructInfo) -> bool {
    for (let f in earlier.fields) {
        let optional = option_inner(f.ty) != null;
        if (optional) {
            continue;
        }
        let other = later.fields.find((g) -> { g.name == f.name });
        if let g: FieldItem = other {
            if (f.tag != null || g.tag != null) {
                if (f.tag != g.tag) {
                    return false;
                }
            } else if (f.ty.to_string() != g.ty.to_string()) {
                return false;
            }
        } else {
            return false;
        }
    }
    true
}

function check_unambiguous(variants: VariantInfo[]) -> void {
    let classes = variants.filter((v) -> { v.kind == VariantKind.Class });
    for (let k in baml.iter.Range.new(0, classes.length())) {
        for (let i in baml.iter.Range.new(0, k)) {
            let earlier = classes[i].info ?? abort("unreachable");
            let later = classes[k].info ?? abort("unreachable");
            if (accepts(earlier, later)) {
                abort(`subcommand variants \`${earlier.ident}\` and \`${later.ident}\` have the same shape, so \`${later.ident}\` cannot be told apart when decoding; add a discriminator field, e.g. \`kind: "${classes[k].name}"\` (and \`kind: "${classes[i].name}"\` on \`${earlier.ident}\`)`);
            }
        }
    }
}

/// A witness for a hand-written `Subcommand` impl, if `t` is one
function subcommand_witness(t: reflect.Type) -> root.clap_builder.Subcommand? {
    if (!implements_subcommand(t)) {
        return null;
    }
    match (witness(t)) {
        let s: root.clap_builder.Subcommand => s,
        _ => null,
    }
}

/// `impl Subcommand::augment_subcommands` for a derived subcommand type
function augment_subcommands_for(t: reflect.Type, app: root.clap_builder.Command, override_required: bool) -> root.clap_builder.Command {
    if let hand: root.clap_builder.Subcommand = subcommand_witness(t) {
        return if (override_required) { hand.augment_subcommands_for_update_dyn(app) } else { hand.augment_subcommands_dyn(app) };
    }
    let cmd = app;
    for (let v in subcommand_variants(t)) {
        match (v.kind) {
            VariantKind.External => {
                let elem = vec_inner(v.ty) ?? reflect.Type.of<string>();
                cmd = cmd.external_subcommand_value_parser(default_value_parser(elem, false));
            },
            VariantKind.Literal => {
                cmd = cmd.subcommand(root.clap_builder.Command.new(v.name));
            },
            VariantKind.Class => {
                let info = v.info ?? abort("unreachable");
                let sub = root.clap_builder.Command.new(v.name);
                sub = gen_augment(info.fields, sub, info.item, override_required);
                cmd = cmd.subcommand(sub);
            },
        }
    }
    cmd
}

/// `impl Subcommand::has_subcommand`
function has_subcommand_for(t: reflect.Type, name: string) -> bool {
    if let hand: root.clap_builder.Subcommand = subcommand_witness(t) {
        return hand.has_subcommand_dyn(name);
    }
    let variants = subcommand_variants(t);
    if (variants.some((v) -> { v.kind == VariantKind.External })) {
        return true;
    }
    variants.some((v) -> { v.name == name })
}

/// `impl FromArgMatches::from_arg_matches_mut` for a derived subcommand type
function subcommand_from_arg_matches(t: reflect.Type, matches: root.clap_builder.ArgMatches) -> baml.json.json throws root.clap_builder.Error {
    if let hand: root.clap_builder.Subcommand = subcommand_witness(t) {
        return to_json(hand.from_arg_matches_dyn(matches));
    }
    let sub = matches.subcommand();
    if let s: root.clap_builder.SubcommandMatch = sub {
        let variants = subcommand_variants(t);
        for (let v in variants) {
            if (v.kind == VariantKind.External || v.name != s.name) {
                continue;
            }
            match (v.kind) {
                VariantKind.Literal => {
                    return v.name;
                },
                VariantKind.Class => {
                    return gen_constructor(v.info ?? abort("unreachable"), s.matches);
                },
                _ => {},
            }
        }
        if (variants.some((v) -> { v.kind == VariantKind.External })) {
            let args = s.matches.get_many<unknown>("") ?? [];
            let out: baml.json.json[] = [s.name];
            for (let a in args) { out.push(to_json(a)); }
            return out;
        }
        throw root.clap_builder.Error.raw(root.clap_builder.ErrorKind.InvalidSubcommand, `the subcommand '${s.name}' wasn't recognized`)
    }
    throw root.clap_builder.Error.raw(root.clap_builder.ErrorKind.MissingSubcommand, "a subcommand is required but one was not provided")
}
