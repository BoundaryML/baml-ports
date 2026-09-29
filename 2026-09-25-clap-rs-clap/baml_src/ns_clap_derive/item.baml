// Port of clap_derive/src/item.rs

function DEFAULT_CASING() -> CasingStyle { CasingStyle.Kebab }
function DEFAULT_ENV_CASING() -> CasingStyle { CasingStyle.ScreamingSnake }

/// Defines the casing for the attributes long representation.
enum CasingStyle {
    /// Indicate word boundaries with uppercase letter, excluding the first word.
    Camel,
    /// Keep all letters lowercase and indicate word boundaries with hyphens.
    Kebab,
    /// Indicate word boundaries with uppercase letter, including the first word.
    Pascal,
    /// Keep all letters uppercase and indicate word boundaries with underscores.
    ScreamingSnake,
    /// Keep all letters lowercase and indicate word boundaries with underscores.
    Snake,
    /// Keep all letters lowercase and remove word boundaries.
    Lower,
    /// Keep all letters uppercase and remove word boundaries.
    Upper,
    /// Use the original attribute name defined in the code.
    Verbatim,
}

function casing_from_lit(name: string) -> CasingStyle {
    let normalized = root.heck.to_upper_camel_case(name).to_lower_case();
    match (normalized) {
        "camel" | "camelcase" => CasingStyle.Camel,
        "kebab" | "kebabcase" => CasingStyle.Kebab,
        "pascal" | "pascalcase" => CasingStyle.Pascal,
        "screamingsnake" | "screamingsnakecase" => CasingStyle.ScreamingSnake,
        "snake" | "snakecase" => CasingStyle.Snake,
        "lower" | "lowercase" => CasingStyle.Lower,
        "upper" | "uppercase" => CasingStyle.Upper,
        "verbatim" | "verbatimcase" => CasingStyle.Verbatim,
        let s => abort(`unsupported casing: \`${s}\``),
    }
}

function translate_casing(s: string, style: CasingStyle) -> string {
    match (style) {
        CasingStyle.Pascal => root.heck.to_upper_camel_case(s),
        CasingStyle.Kebab => root.heck.to_kebab_case(s),
        CasingStyle.Camel => root.heck.to_lower_camel_case(s),
        CasingStyle.ScreamingSnake => root.heck.to_shouty_snake_case(s),
        CasingStyle.Snake => root.heck.to_snake_case(s),
        CasingStyle.Lower => root.heck.to_snake_case(s).replace_all("_", ""),
        CasingStyle.Upper => root.heck.to_shouty_snake_case(s).replace_all("_", ""),
        CasingStyle.Verbatim => s,
    }
}

/// `enum Name { Derived(Ident), Assigned(TokenStream) }`
class Name {
    derived: string?,
    assigned: MethodArg?,

    function derived_from(ident: string) -> Name { Name { derived: ident, assigned: null } }
    function assigned_to(value: MethodArg) -> Name { Name { derived: null, assigned: value } }

    function translate(self, style: CasingStyle, ctx: EvalCtx) -> string {
        if let a: MethodArg = self.assigned {
            as_string(eval_arg(a, ctx), "name")
        } else {
            translate_casing(self.derived ?? "", style)
        }
    }

    function translate_char(self, style: CasingStyle, ctx: EvalCtx) -> string {
        let s = self.translate(style, ctx);
        s.slice(0, 1)
    }

    /// `quote!(#name)`: the name as written (an assigned name is evaluated)
    function raw(self, ctx: EvalCtx) -> string {
        if let a: MethodArg = self.assigned {
            as_string(eval_arg(a, ctx), "name")
        } else {
            self.derived ?? ""
        }
    }

    function is_assigned(self) -> bool { self.assigned != null }
}

/// A method call argument: a parsed expression or a value computed by the derive
type MethodArg = root.syn.Expr | Computed | DefaultValueT

/// A value the derive computed itself (Rust: a literal spliced by `quote!`)
class Computed {
    value: unknown,
}

class Method {
    name: string,
    args: MethodArg[],

    function new(name: string, args: MethodArg[]) -> Method { Method { name: name, args: args } }
}

enum KindTag {
    Arg,
    Command,
    Value,
    FromGlobal,
    Subcommand,
    Flatten,
    Skip,
    ExternalSubcommand,
}

class Kind {
    tag: KindTag,
    ty: Ty?,
    skip_value: AttrValue?,
    skip_attr_kind: AttrKind?,

    function name(self) -> string {
        match (self.tag) {
            KindTag.Arg => "arg",
            KindTag.Command => "command",
            KindTag.Value => "value",
            KindTag.FromGlobal => "from_global",
            KindTag.Subcommand => "subcommand",
            KindTag.Flatten => "flatten",
            KindTag.Skip => "skip",
            KindTag.ExternalSubcommand => "external_subcommand",
        }
    }

    function attr_kind(self) -> AttrKind {
        match (self.tag) {
            KindTag.Arg => AttrKind.Arg,
            KindTag.Command => AttrKind.Command,
            KindTag.Value => AttrKind.Value,
            KindTag.FromGlobal => AttrKind.Arg,
            KindTag.Subcommand => AttrKind.Command,
            KindTag.Flatten => AttrKind.Command,
            KindTag.Skip => self.skip_attr_kind ?? AttrKind.Arg,
            KindTag.ExternalSubcommand => AttrKind.Command,
        }
    }
}

function kind(tag: KindTag, ty: Ty?) -> Kind {
    Kind { tag: tag, ty: ty, skip_value: null, skip_attr_kind: null }
}

class Item {
    name: Name,
    casing: CasingStyle,
    env_casing: CasingStyle,
    ty: reflect.Type?,
    doc_comment: Method[],
    methods: Method[],
    value_parser: MethodArg?,
    value_parser_implicit: bool,
    action: MethodArg?,
    action_implicit: bool,
    verbatim_doc_comment: bool,
    force_long_help: bool,
    next_display_order: Method?,
    next_help_heading: Method?,
    is_enum: bool,
    is_positional: bool,
    skip_group: bool,
    group_id: Name,
    group_methods: Method[],
    kind: Kind,
    ctx: EvalCtx,

    function from_args_struct(doc: string?, name: Name, ident: string, ctx: EvalCtx) -> Item {
        let res = Item.new(name, ident, null, DEFAULT_CASING(), DEFAULT_ENV_CASING(), kind(KindTag.Command, Ty.Other), ctx);
        let d = split_docstring(doc);
        let parsed_attrs = parse_all(d.attrs);
        res.infer_kind(parsed_attrs);
        res.push_attrs(parsed_attrs);
        res.push_doc_comment(d.lines, "about", "long_about");

        res
    }

    function from_subcommand_enum(doc: string?, name: Name, ident: string, ctx: EvalCtx) -> Item {
        Item.from_args_struct(doc, name, ident, ctx)
    }

    function from_value_enum(doc: string?, name: Name, ident: string, ctx: EvalCtx) -> Item {
        let res = Item.new(name, ident, null, DEFAULT_CASING(), DEFAULT_ENV_CASING(), kind(KindTag.Value, null), ctx);
        let d = split_docstring(doc);
        let parsed_attrs = parse_all(d.attrs);
        res.infer_kind(parsed_attrs);
        res.push_attrs(parsed_attrs);
        // Ignoring `push_doc_comment` as there is no top-level clap builder to add documentation
        // to

        if (res.has_explicit_methods()) {
            abort(`${res.methods[0].name} doesn't exist for \`ValueEnum\` enums`);
        }

        res
    }

    function from_subcommand_variant(doc: string?, ident: string, ty: Ty, struct_casing: CasingStyle, env_casing: CasingStyle, ctx: EvalCtx) -> Item {
        let res = Item.new(Name.derived_from(ident), ident, null, struct_casing, env_casing, kind(KindTag.Command, ty), ctx);
        let d = split_docstring(doc);
        let parsed_attrs = parse_all(d.attrs);
        res.infer_kind(parsed_attrs);
        res.push_attrs(parsed_attrs);
        if (res.kind.tag == KindTag.Command || res.kind.tag == KindTag.Subcommand) {
            res.push_doc_comment(d.lines, "about", "long_about");
        }

        if (res.kind.tag == KindTag.Flatten && res.has_explicit_methods()) {
            abort("methods are not allowed for flattened entry");
        }

        res
    }

    function from_value_enum_variant(doc: string?, ident: string, argument_casing: CasingStyle, env_casing: CasingStyle, ctx: EvalCtx) -> Item {
        let res = Item.new(Name.derived_from(ident), ident, null, argument_casing, env_casing, kind(KindTag.Value, null), ctx);
        let d = split_docstring(doc);
        let parsed_attrs = parse_all(d.attrs);
        res.infer_kind(parsed_attrs);
        res.push_attrs(parsed_attrs);
        if (res.kind.tag == KindTag.Value) {
            res.push_doc_comment(d.lines, "help", null);
        }

        res
    }

    function from_args_field(field_name: string, field_ty: reflect.Type, doc: string?, struct_casing: CasingStyle, env_casing: CasingStyle, ctx: EvalCtx) -> Item {
        let ty = ty_from_type(field_ty);
        let res = Item.new(Name.derived_from(field_name), field_name, field_ty, struct_casing, env_casing, kind(KindTag.Arg, ty), ctx);

        let d = split_docstring(doc);
        let parsed_attrs = parse_all(d.attrs);
        res.infer_kind(parsed_attrs);
        res.push_attrs(parsed_attrs);
        if (res.kind.tag == KindTag.Arg) {
            res.push_doc_comment(d.lines, "help", "long_help");
        }

        match (res.kind.tag) {
            KindTag.Flatten => {
                if (res.has_explicit_methods()) {
                    abort("methods are not allowed for flattened entry");
                }
            },
            KindTag.Subcommand => {
                if (res.has_explicit_methods()) {
                    abort("methods in attributes are not allowed for subcommand");
                }
            },
            _ => {},
        }

        res
    }

    function new(name: Name, ident: string, ty: reflect.Type?, casing: CasingStyle, env_casing: CasingStyle, k: Kind, ctx: EvalCtx) -> Item {
        let group_id = Name.derived_from(ident);
        Item {
            name: name,
            casing: casing,
            env_casing: env_casing,
            ty: ty,
            doc_comment: [],
            methods: [],
            value_parser: null,
            value_parser_implicit: false,
            action: null,
            action_implicit: false,
            verbatim_doc_comment: false,
            force_long_help: false,
            next_display_order: null,
            next_help_heading: null,
            is_enum: false,
            is_positional: true,
            skip_group: false,
            group_id: group_id,
            group_methods: [],
            kind: k,
            ctx: ctx,
        }
    }

    function push_method(self, attr_kind: AttrKind, name: string, args: MethodArg[]) -> void {
        if (name == "id") {
            match (attr_kind) {
                AttrKind.Command | AttrKind.Value => {
                    self.name = Name.assigned_to(args[0]);
                },
                AttrKind.Group => {
                    self.group_id = Name.assigned_to(args[0]);
                },
                _ => {
                    self.name = Name.assigned_to(args[0]);
                },
            }
        } else if (name == "name") {
            match (attr_kind) {
                AttrKind.Arg => {
                    self.name = Name.assigned_to(args[0]);
                },
                AttrKind.Group => self.group_methods.push(Method.new(name, args)),
                _ => {
                    self.name = Name.assigned_to(args[0]);
                },
            }
        } else if (name == "value_parser") {
            self.value_parser = args[0];
        } else if (name == "action") {
            self.action = args[0];
        } else {
            if (name == "short" || name == "long") {
                self.is_positional = false;
            }
            match (attr_kind) {
                AttrKind.Group => self.group_methods.push(Method.new(name, args)),
                _ => self.methods.push(Method.new(name, args)),
            }
        }
    }

    function infer_kind(self, attrs: ClapAttr[]) -> void {
        for (let attr in attrs) {
            if (attr.value is AttrValueCall) {
                continue;
            }

            let actual_attr_kind = attr.kind;
            let ty = self.kind.ty ?? Ty.Other;
            let k: Kind? = match (attr.magic) {
                MagicAttrName.FromGlobal => {
                    if (attr.value != null) {
                        abort(`attribute \`${attr.name}\` does not accept a value`);
                    }
                    kind(KindTag.FromGlobal, ty)
                },
                MagicAttrName.Subcommand => if (attr.value == null) { kind(KindTag.Subcommand, ty) } else { null },
                MagicAttrName.ExternalSubcommand => if (attr.value == null) { kind(KindTag.ExternalSubcommand, null) } else { null },
                MagicAttrName.Flatten => if (attr.value == null) { kind(KindTag.Flatten, ty) } else { null },
                MagicAttrName.Skip => {
                    if (actual_attr_kind != AttrKind.Group) {
                        Kind { tag: KindTag.Skip, ty: null, skip_value: attr.value, skip_attr_kind: self.kind.attr_kind() }
                    } else {
                        null
                    }
                },
                _ => null,
            };

            if let kk: Kind = k {
                self.set_kind(kk);
            }
        }
    }

    function push_attrs(self, attrs: ClapAttr[]) -> void {
        for (let attr in attrs) {
            let actual_attr_kind = attr.kind;
            let expected_attr_kind = self.kind.attr_kind();
            if (actual_attr_kind == AttrKind.Clap || actual_attr_kind == AttrKind.StructOpt) {
                // deprecated spellings, accepted
            } else if (actual_attr_kind == AttrKind.Group && expected_attr_kind == AttrKind.Command) {
            } else if (actual_attr_kind != expected_attr_kind) {
                abort(`expected \`${attr_kind_as_str(expected_attr_kind)}\` attribute instead of \`${attr_kind_as_str(actual_attr_kind)}\``);
            }

            if let call: AttrValueCall = attr.value {
                // Force raw mode with method call syntax
                self.push_method(attr.kind, attr.name, call.args.map((x) -> { let arg: MethodArg = x; arg }));
                continue;
            }

            let has_value = attr.value != null;
            match (attr.magic) {
                MagicAttrName.Short => {
                    if (!has_value) {
                        assert_attr_kind(attr, [AttrKind.Arg]);
                        self.push_method(attr.kind, attr.name, [Computed { value: self.name.translate_char(self.casing, self.ctx) }]);
                    } else {
                        self.push_method(attr.kind, attr.name, [attr_value_expr(attr.value_or_abort())]);
                    }
                },
                MagicAttrName.Long => {
                    if (!has_value) {
                        assert_attr_kind(attr, [AttrKind.Arg]);
                        self.push_method(attr.kind, attr.name, [Computed { value: self.name.translate(self.casing, self.ctx) }]);
                    } else {
                        self.push_method(attr.kind, attr.name, [attr_value_expr(attr.value_or_abort())]);
                    }
                },
                MagicAttrName.ValueParser => {
                    if (!has_value) {
                        assert_attr_kind(attr, [AttrKind.Arg]);
                        self.value_parser_implicit = true;
                    } else {
                        self.push_method(attr.kind, attr.name, [attr_value_expr(attr.value_or_abort())]);
                    }
                },
                MagicAttrName.Action => {
                    if (!has_value) {
                        assert_attr_kind(attr, [AttrKind.Arg]);
                        self.action_implicit = true;
                    } else {
                        self.push_method(attr.kind, attr.name, [attr_value_expr(attr.value_or_abort())]);
                    }
                },
                MagicAttrName.Env => {
                    if (!has_value) {
                        assert_attr_kind(attr, [AttrKind.Arg]);
                        self.push_method(attr.kind, attr.name, [Computed { value: self.name.translate(self.env_casing, self.ctx) }]);
                    } else {
                        self.push_method(attr.kind, attr.name, [attr_value_expr(attr.value_or_abort())]);
                    }
                },
                MagicAttrName.ValueEnum => {
                    if (has_value) {
                        abort(`attribute \`${attr.name}\` does not accept a value`);
                    }
                    assert_attr_kind(attr, [AttrKind.Arg]);
                    self.is_enum = true;
                },
                MagicAttrName.VerbatimDocComment => {
                    if (has_value) {
                        abort(`attribute \`${attr.name}\` does not accept a value`);
                    }
                    self.verbatim_doc_comment = true;
                },
                MagicAttrName.About => {
                    if (!has_value) {
                        assert_attr_kind(attr, [AttrKind.Command]);
                        if let m: Method = method_from_env(attr.name, "description") {
                            self.methods.push(m);
                        }
                    } else {
                        self.push_method(attr.kind, attr.name, [attr_value_expr(attr.value_or_abort())]);
                    }
                },
                MagicAttrName.LongAbout => {
                    if (!has_value) {
                        assert_attr_kind(attr, [AttrKind.Command]);
                        self.force_long_help = true;
                    } else {
                        self.push_method(attr.kind, attr.name, [attr_value_expr(attr.value_or_abort())]);
                    }
                },
                MagicAttrName.LongHelp => {
                    if (!has_value) {
                        assert_attr_kind(attr, [AttrKind.Arg]);
                        self.force_long_help = true;
                    } else {
                        self.push_method(attr.kind, attr.name, [attr_value_expr(attr.value_or_abort())]);
                    }
                },
                MagicAttrName.Author => {
                    if (!has_value) {
                        assert_attr_kind(attr, [AttrKind.Command]);
                        if let m: Method = method_from_env(attr.name, "authors") {
                            self.methods.push(m);
                        }
                    } else {
                        self.push_method(attr.kind, attr.name, [attr_value_expr(attr.value_or_abort())]);
                    }
                },
                MagicAttrName.Version => {
                    if (!has_value) {
                        assert_attr_kind(attr, [AttrKind.Command]);
                        if let m: Method = method_from_env(attr.name, "version") {
                            self.methods.push(m);
                        }
                    } else {
                        self.push_method(attr.kind, attr.name, [attr_value_expr(attr.value_or_abort())]);
                    }
                },
                MagicAttrName.DefaultValueT => {
                    assert_attr_kind(attr, [AttrKind.Arg]);
                    if (self.ty == null) {
                        abort("#[arg(default_value_t)] (without an argument) can be used only on field level");
                    }
                    let is_value_enum = attrs.some((a) -> { a.magic == MagicAttrName.ValueEnum });
                    let arg: MethodArg = DefaultValueT {
                        expr: if let v: AttrValue = attr.value { attr_value_expr(v) } else { null },
                        value_enum: is_value_enum,
                        ty: inner_type(self.ty ?? reflect.Type.of<string>()),
                        many: false,
                    };
                    self.methods.push(Method.new("default_value", [arg]));
                },
                MagicAttrName.DefaultValuesT => {
                    assert_attr_kind(attr, [AttrKind.Arg]);
                    let t = self.ty ?? abort("#[arg(default_values_t)] (without an argument) can be used only on field level");
                    if (ty_from_type(t) != Ty.Vec) {
                        abort("#[arg(default_values_t)] can be used only on Vec types");
                    }
                    let is_value_enum = attrs.some((a) -> { a.magic == MagicAttrName.ValueEnum });
                    let arg: MethodArg = DefaultValueT {
                        expr: attr_value_expr(attr.value_or_abort()),
                        value_enum: is_value_enum,
                        ty: inner_type(t),
                        many: true,
                    };
                    self.methods.push(Method.new("default_values", [arg]));
                },
                MagicAttrName.DefaultValueOsT => {
                    assert_attr_kind(attr, [AttrKind.Arg]);
                    let is_value_enum = attrs.some((a) -> { a.magic == MagicAttrName.ValueEnum });
                    let arg: MethodArg = DefaultValueT {
                        expr: if let v: AttrValue = attr.value { attr_value_expr(v) } else { null },
                        value_enum: is_value_enum,
                        ty: inner_type(self.ty ?? reflect.Type.of<string>()),
                        many: false,
                    };
                    self.methods.push(Method.new("default_value", [arg]));
                },
                MagicAttrName.DefaultValuesOsT => {
                    assert_attr_kind(attr, [AttrKind.Arg]);
                    let is_value_enum = attrs.some((a) -> { a.magic == MagicAttrName.ValueEnum });
                    let arg: MethodArg = DefaultValueT {
                        expr: attr_value_expr(attr.value_or_abort()),
                        value_enum: is_value_enum,
                        ty: inner_type(self.ty ?? reflect.Type.of<string>()),
                        many: true,
                    };
                    self.methods.push(Method.new("default_values", [arg]));
                },
                MagicAttrName.NextDisplayOrder => {
                    assert_attr_kind(attr, [AttrKind.Command]);
                    self.next_display_order = Method.new(attr.name, [attr_value_expr(attr.value_or_abort())]);
                },
                MagicAttrName.NextHelpHeading => {
                    assert_attr_kind(attr, [AttrKind.Command]);
                    self.next_help_heading = Method.new(attr.name, [attr_value_expr(attr.value_or_abort())]);
                },
                MagicAttrName.RenameAll => {
                    let lit = attr.lit_str_or_abort();
                    self.casing = casing_from_lit(lit.value());
                },
                MagicAttrName.RenameAllEnv => {
                    assert_attr_kind(attr, [AttrKind.Command, AttrKind.Arg]);
                    let lit = attr.lit_str_or_abort();
                    self.env_casing = casing_from_lit(lit.value());
                },
                MagicAttrName.Skip => {
                    if (actual_attr_kind == AttrKind.Group) {
                        self.skip_group = true;
                    }
                },
                MagicAttrName.FromGlobal | MagicAttrName.Subcommand | MagicAttrName.ExternalSubcommand | MagicAttrName.Flatten => {
                    // Kinds
                },
                null => {
                    let expr = attr.value_or_abort();
                    self.push_method(attr.kind, attr.name, [attr_value_expr(expr)]);
                },
            }
        }

        if (self.has_explicit_methods()) {
            if (self.kind.tag == KindTag.Skip) {
                abort(`\`${self.methods[0].name}\` cannot be used with \`#[${attr_kind_as_str(self.kind.skip_attr_kind ?? AttrKind.Arg)}(skip)]\``);
            }
            if (self.kind.tag == KindTag.FromGlobal) {
                abort(`\`${self.methods[0].name}\` cannot be used with \`#[arg(from_global)]\``);
            }
        }
    }

    function push_doc_comment(self, lines: string[], short_name: string, long_name: string?) -> void {
        if (lines.length() > 0) {
            let formatted = format_doc_comment(lines, !self.verbatim_doc_comment, self.force_long_help);
            let is_value_kind = self.kind.tag == KindTag.Value;
            let short_value: string? = if (is_value_kind && root.clap_builder.features().unstable_v5) {
                formatted.long ?? formatted.short
            } else {
                formatted.short
            };
            self.doc_comment.push(Method.new(short_name, [Computed { value: short_value }]));

            if let ln: string = long_name {
                self.doc_comment.push(Method.new(ln, [Computed { value: formatted.long }]));
            }
        }
    }

    function set_kind(self, k: Kind) -> void {
        let ok = match (self.kind.tag) {
            KindTag.Arg => k.tag == KindTag.FromGlobal || k.tag == KindTag.Subcommand || k.tag == KindTag.Flatten || k.tag == KindTag.Skip,
            KindTag.Command => k.tag == KindTag.Subcommand || k.tag == KindTag.Flatten || k.tag == KindTag.Skip || k.tag == KindTag.ExternalSubcommand,
            KindTag.Value => k.tag == KindTag.Skip,
            _ => false,
        };
        if (!ok) {
            abort(`\`${k.name()}\` cannot be used with \`${self.kind.name()}\``);
        }
        self.kind = k;
    }

    function find_default_method(self) -> Method? {
        self.methods.find((m) -> { m.name == "default_value" || m.name == "default_value_os" })
    }

    function has_explicit_methods(self) -> bool {
        self.methods.some((m) -> { m.name != "help" && m.name != "long_help" })
    }

    function id(self) -> string { self.name.raw(self.ctx) }

    function cased_name(self) -> string { self.name.translate(self.casing, self.ctx) }

    function value_name(self) -> string { self.name.translate(CasingStyle.ScreamingSnake, self.ctx) }

    function group_id_str(self) -> string { self.group_id.raw(self.ctx) }

    /// The `value_parser` for this field: explicit, or `value_parser!(inner_type)`
    function resolve_value_parser(self, field_type: reflect.Type) -> root.clap_builder.ValueParser {
        if let vp: MethodArg = self.value_parser {
            as_value_parser(eval_value_parser(vp, self.ctx, inner_type(field_type)), "value_parser")
        } else {
            default_value_parser(inner_type(field_type), self.is_enum)
        }
    }

    /// The `action` for this field: explicit, or the default for its type
    function resolve_action(self, field_type: reflect.Type) -> root.clap_builder.ArgAction {
        if let a: MethodArg = self.action {
            as_action(eval_arg(a, self.ctx))
        } else {
            default_action(field_type)
        }
    }
}

/// A `default_value_t` / `default_values_t` argument, rendered to strings when applied
class DefaultValueT {
    expr: root.syn.Expr?,
    value_enum: bool,
    ty: reflect.Type,
    many: bool,
}

function attr_value_expr(v: AttrValue) -> root.syn.Expr {
    match (v) {
        let l: AttrValueLitStr => root.syn.ExprLit { lit: l.lit },
        let e: AttrValueExpr => e.expr,
        let c: AttrValueCall => root.syn.ExprTuple { elems: c.args },
    }
}

/// `Method::from_env`: `version`/`about`/`author` read from the package metadata
function method_from_env(name: string, key: "version" | "description" | "authors") -> Method? {
    let info = root.clap_builder.package_info();
    let value = match (key) {
        "version" => info.version,
        "description" => info.description,
        "authors" => process_author_str(info.authors),
    };
    if (value.is_empty()) {
        return null;
    }
    Method.new(name, [Computed { value: value }])
}

function default_value_parser(inner: reflect.Type, is_enum: bool) -> root.clap_builder.ValueParser {
    type T = unreflect(inner);
    root.clap_builder.value_parser<T>()
}

function default_action(field_type: reflect.Type) -> root.clap_builder.ArgAction {
    let ty = ty_from_type(field_type);
    match (ty) {
        Ty.Vec | Ty.OptionVec | Ty.VecVec | Ty.OptionVecVec => root.clap_builder.ArgAction.Append,
        Ty.Option | Ty.OptionOption => root.clap_builder.ArgAction.Set,
        _ => {
            if (is_simple_ty(field_type, "bool")) {
                root.clap_builder.ArgAction.SetTrue
            } else {
                root.clap_builder.ArgAction.Set
            }
        },
    }
}

function assert_attr_kind(attr: ClapAttr, possible_kind: AttrKind[]) -> void {
    if (attr.kind == AttrKind.Clap || attr.kind == AttrKind.StructOpt) {
        // deprecated
    } else if (!possible_kind.includes(attr.kind)) {
        let options = possible_kind.map((k) -> { `\`#[${attr_kind_as_str(k)}(${attr.name})]\`` });
        abort(`unknown \`#[${attr_kind_as_str(attr.kind)}(${attr.name})]\` attribute (${options.join(", ")} exists)`);
    }
}

function process_author_str(author: string) -> string {
    let res = "";
    let inside_angle_braces = 0;

    for (let ch in author.chars()) {
        if (inside_angle_braces > 0 && ch == ">") {
            inside_angle_braces -= 1;
            res = res + ch;
        } else if (ch == "<") {
            inside_angle_braces += 1;
            res = res + ch;
        } else if (inside_angle_braces == 0 && ch == ":") {
            res = res + ", ";
        } else {
            res = res + ch;
        }
    }

    res
}
