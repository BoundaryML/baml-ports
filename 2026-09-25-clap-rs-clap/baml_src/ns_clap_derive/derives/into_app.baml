// Port of clap_derive/src/derives/into_app.rs

/// `gen_for_struct`: `CommandFactory::command` / `command_for_update` for a struct
function gen_for_struct(info: StructInfo, override_required: bool) -> root.clap_builder.Command {
    let name = info.item.cased_name();
    let app = root.clap_builder.Command.new(name);
    gen_augment(info.fields, app, info.item, override_required)
}

/// `gen_for_enum`: `CommandFactory::command` for a subcommand enum
function gen_for_enum(name: string, t: reflect.Type, override_required: bool) -> root.clap_builder.Command {
    if (override_required) {
        augment_subcommands_for(t, root.clap_builder.Command.new(name), true)
            .subcommand_required(false)
            .arg_required_else_help(false)
    } else {
        let app = root.clap_builder.Command.new(name)
            .subcommand_required(true)
            .arg_required_else_help(true);
        augment_subcommands_for(t, app, false)
    }
}
