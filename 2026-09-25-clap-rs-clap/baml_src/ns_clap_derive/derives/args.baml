// Port of clap_derive/src/derives/args.rs

/// `derive_args` / `Item::from_args_struct` + `collect_args_fields` for a reflected class
function args_struct_info(t: reflect.Type, name: Name?) -> StructInfo {
    let cls = t.as_class() ?? abort(`\`#[derive(Args)]\` only supports classes, got \`${t}\``);
    let ctx = EvalCtx.for_type(t);
    let ident = type_ident(t);
    let n = name ?? Name.derived_from(ident);
    let item = Item.from_args_struct(cls.meta().docstring, n, ident, ctx);
    let fields = collect_args_fields(item, cls, ctx);
    StructInfo { ty: t, cls: cls, ident: ident, item: item, fields: fields }
}

/// `impl Args::group_id`
function gen_group_id(info: StructInfo) -> string? {
    if (info.item.skip_group) { null } else { info.item.group_id_str() }
}

/// `gen_augment`: add the struct's arguments (and subcommands) to `app`
function gen_augment(fields: FieldItem[], app: root.clap_builder.Command, parent_item: Item, override_required: bool) -> root.clap_builder.Command {
    let cmd = app;
    let ctx = parent_item.ctx;

    // #initial_app_methods
    if let m: Method = parent_item.next_display_order { cmd = apply_command_method(cmd, m, ctx); }
    if let m: Method = parent_item.next_help_heading { cmd = apply_command_method(cmd, m, ctx); }

    // #group_app_methods
    if (!parent_item.skip_group) {
        let group_id = parent_item.group_id_str();
        let literal_group_members = fields
            .filter((f) -> { f.tag == null && f.item.kind.tag == KindTag.Arg })
            .map((f) -> { f.item.id() });

        // HACK: Validation isn't ready yet for nested arg groups, so just don't populate the group in
        // that situation
        let possible_group_members_len = fields.filter((f) -> { f.item.kind.tag == KindTag.Flatten }).length();
        if (0 < possible_group_members_len) {
            literal_group_members = [];
        }

        let group = root.clap_builder.ArgGroup.new(group_id).multiple(true);
        for (let m in parent_item.group_methods) {
            group = apply_group_method(group, m, ctx);
        }
        cmd = cmd.group(group.args(literal_group_members));
    }

    let subcommand_specified = false;
    for (let field in fields) {
        if (field.tag != null) {
            continue;
        }
        let item = field.item;
        let k = item.kind;
        match (k.tag) {
            KindTag.Subcommand => {
                if (subcommand_specified) {
                    abort("`#[command(subcommand)]` can only be used once per container");
                }
                subcommand_specified = true;

                let is_option = k.ty == Ty.Option;
                let subcmd_type = if (is_option) { sub_type(field.ty) ?? field.ty } else { field.ty };
                cmd = augment_subcommands_for(subcmd_type, cmd, override_required);
                if (!is_option) {
                    cmd = cmd.subcommand_required(true).arg_required_else_help(true);
                }
                if (override_required) {
                    cmd = cmd.subcommand_required(false).arg_required_else_help(false);
                }
            },
            KindTag.Flatten => {
                let is_option = k.ty == Ty.Option;
                let inner_type = if (is_option) { sub_type(field.ty) ?? field.ty } else { field.ty };
                if let m: Method = item.next_help_heading { cmd = apply_command_method(cmd, m, ctx); }
                if let m: Method = item.next_display_order { cmd = apply_command_method(cmd, m, ctx); }
                // `<#inner_type as clap::Args>::augment_args(#app_var)`
                let w = if (implements_args(inner_type)) { witness(inner_type) } else { null };
                match (w) {
                    let a: root.clap_builder.Args => {
                        if (is_option && a.group_id_dyn() == null) {
                            abort("cannot `#[flatten]` an `Option<Args>` with `#[group(skip)]`");
                        }
                        cmd = if (override_required) { a.augment_args_for_update_dyn(cmd) } else { a.augment_args_dyn(cmd) };
                    },
                    _ => {
                        let inner = args_struct_info(inner_type, null);
                        if (is_option && gen_group_id(inner) == null) {
                            abort("cannot `#[flatten]` an `Option<Args>` with `#[group(skip)]`");
                        }
                        cmd = gen_augment(inner.fields, cmd, inner.item, override_required);
                    },
                }
            },
            KindTag.Arg => {
                let value_name = item.value_name();
                let arg = root.clap_builder.Arg.new(item.id());
                let ty = k.ty ?? Ty.Other;
                let set_parser_and_action = (a: root.clap_builder.Arg) -> root.clap_builder.Arg {
                    a.value_parser(item.resolve_value_parser(field.ty)).action(item.resolve_action(field.ty))
                };
                arg = match (ty) {
                    Ty.Unit => arg.value_name(value_name).action(item.resolve_action(field.ty)),
                    Ty.Option => set_parser_and_action(arg.value_name(value_name)),
                    Ty.OptionOption => set_parser_and_action(arg.value_name(value_name).num_args(root.clap_builder.ValueRange.inclusive(0, 1))),
                    Ty.OptionVec | Ty.Vec => {
                        if (item.is_positional) {
                            // action won't be sufficient for getting multiple
                            set_parser_and_action(arg.value_name(value_name).num_args(root.clap_builder.ValueRange.from(1)))
                        } else {
                            set_parser_and_action(arg.value_name(value_name))
                        }
                    },
                    Ty.VecVec | Ty.OptionVecVec => set_parser_and_action(arg.value_name(value_name)),
                    Ty.Other => {
                        let required = item.find_default_method() == null;
                        // `ArgAction::takes_values` is assuming `ArgAction::default_value` will be
                        // set though that won't always be true but this should be good enough,
                        // otherwise we'll report an "arg required" error when unwrapping.
                        let action_value = item.resolve_action(field.ty);
                        set_parser_and_action(
                            arg.value_name(value_name)
                                .required(required && root.clap_builder.action_takes_values(action_value)),
                        )
                    },
                };

                // #explicit_methods (doc comment first, then attributes)
                for (let m in item.doc_comment) {
                    arg = apply_arg_method(arg, m, ctx, field.ty);
                }
                for (let m in item.methods) {
                    arg = apply_arg_method(arg, m, ctx, field.ty);
                }

                if (override_required) {
                    arg = arg.required(false);
                }

                cmd = cmd.arg(arg);
            },
            _ => {},
        }
    }

    // #final_app_methods
    for (let m in parent_item.doc_comment) {
        cmd = apply_command_method(cmd, m, ctx);
    }
    for (let m in parent_item.methods) {
        cmd = apply_command_method(cmd, m, ctx);
    }
    cmd
}

/// `gen_constructor`: build the JSON value `baml.json.to<T>` decodes into the struct
function gen_constructor(info: StructInfo, matches: root.clap_builder.ArgMatches) -> map<string, baml.json.json> throws root.clap_builder.Error {
    let out: map<string, baml.json.json> = {};
    for (let field in info.fields) {
        if let tag: string = field.tag {
            out.set(field.name, tag);
            continue;
        }
        let item = field.item;
        let k = item.kind;
        let value: baml.json.json = match (k.tag) {
            KindTag.Subcommand => {
                let is_option = k.ty == Ty.Option;
                let subcmd_type = if (is_option) { sub_type(field.ty) ?? field.ty } else { field.ty };
                if (is_option) {
                    let name = matches.subcommand_name();
                    if (name != null && has_subcommand_for(subcmd_type, name ?? "")) {
                        subcommand_from_arg_matches(subcmd_type, matches)
                    } else {
                        null
                    }
                } else {
                    subcommand_from_arg_matches(subcmd_type, matches)
                }
            },
            KindTag.Flatten => {
                let is_option = k.ty == Ty.Option;
                let inner_type = if (is_option) { sub_type(field.ty) ?? field.ty } else { field.ty };
                // `<#inner_type as clap::FromArgMatches>::from_arg_matches_mut(#arg_matches)?`
                let w = if (implements_args(inner_type)) { witness(inner_type) } else { null };
                match (w) {
                    let a: root.clap_builder.Args => {
                        let present = if (is_option) {
                            let group_id = a.group_id_dyn() ?? abort("asserted during `Arg` creation");
                            matches.contains_id(group_id)
                        } else {
                            true
                        };
                        if (present) { to_json(a.from_arg_matches_dyn(matches)) } else { null }
                    },
                    _ => {
                        let inner = args_struct_info(inner_type, null);
                        if (is_option) {
                            let group_id = gen_group_id(inner) ?? abort("asserted during `Arg` creation");
                            if (matches.contains_id(group_id)) {
                                gen_constructor(inner, matches)
                            } else {
                                null
                            }
                        } else {
                            gen_constructor(inner, matches)
                        }
                    },
                }
            },
            KindTag.Skip => {
                if let v: AttrValue = k.skip_value {
                    to_json(eval_expr(attr_value_expr(v), item.ctx))
                } else {
                    default_json_for(field.ty)
                }
            },
            KindTag.Arg | KindTag.FromGlobal => gen_parsers(item, k.ty ?? Ty.Other, matches),
            _ => abort(`\`${k.name()}\` cannot be used with \`#[arg]\``),
        };
        out.set(field.name, value);
    }
    out
}

/// `gen_parsers`: read one field's value(s) from the matches
function gen_parsers(item: Item, ty: Ty, matches: root.clap_builder.ArgMatches) -> baml.json.json throws root.clap_builder.Error {
    let id = item.id();
    match (ty) {
        Ty.Unit => null,
        Ty.Option => to_json(matches.get_one<unknown>(id)),
        Ty.OptionOption => {
            if (matches.contains_id(id)) { to_json(matches.get_one<unknown>(id)) } else { null }
        },
        Ty.OptionVec => {
            if (matches.contains_id(id)) {
                to_json(matches.get_many<unknown>(id) ?? [])
            } else {
                null
            }
        },
        Ty.Vec => to_json(matches.get_many<unknown>(id) ?? []),
        Ty.VecVec => to_json(matches.get_occurrences<unknown>(id) ?? []),
        Ty.OptionVecVec => to_json(matches.get_occurrences<unknown>(id)),
        Ty.Other => {
            let v = matches.get_one<unknown>(id);
            if (v == null) {
                throw root.clap_builder.Error.raw(root.clap_builder.ErrorKind.MissingRequiredArgument, `the following required argument was not provided: ${id}`);
            }
            to_json(v)
        },
    }
}

/// Serialize a parsed value for `baml.json.to<T>`
function to_json(v: unknown) -> baml.json.json {
    baml.json.to_json(v) catch_all (e) { _ => abort(`cannot convert value to a struct field: ${v}`) }
}

/// `Default::default()` for a skipped field
function default_json_for(t: reflect.Type) -> baml.json.json {
    let ty = ty_from_type(t);
    match (ty) {
        Ty.Option | Ty.OptionOption | Ty.OptionVec | Ty.OptionVecVec | Ty.Unit => null,
        Ty.Vec | Ty.VecVec => [],
        Ty.Other => {
            match (t.to_string()) {
                "string" => "",
                "int" => 0,
                "float" => 0.0,
                "bool" => false,
                _ => {
                    if let l: reflect.literal.Type = t.as_literal() {
                        to_json(l.value())
                    } else if let u: reflect.union.Type = t.as_union() {
                        let members = u.member_types();
                        if let m: reflect.Type = members.at(0) { default_json_for(m) } else { null }
                    } else if let e: reflect.enum.Type = t.as_enum() {
                        e.values()[0].name
                    } else if let c: reflect.class.Type = t.as_class() {
                        let m: map<string, baml.json.json> = {};
                        for (let f in c.fields()) {
                            m.set(f.name, default_json_for(f.type ?? reflect.Type.of<string>()));
                        }
                        m
                    } else {
                        null
                    }
                },
            }
        },
    }
}
