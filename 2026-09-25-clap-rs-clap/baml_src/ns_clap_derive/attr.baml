// Port of clap_derive/src/attr.rs

enum AttrKind {
    Clap,
    StructOpt,
    Command,
    Group,
    Arg,
    Value,
}

function attr_kind_as_str(k: AttrKind) -> string {
    match (k) {
        AttrKind.Clap => "clap",
        AttrKind.StructOpt => "structopt",
        AttrKind.Command => "command",
        AttrKind.Group => "group",
        AttrKind.Arg => "arg",
        AttrKind.Value => "value",
    }
}

enum MagicAttrName {
    Short,
    Long,
    ValueParser,
    Action,
    Env,
    Flatten,
    ValueEnum,
    FromGlobal,
    Subcommand,
    VerbatimDocComment,
    ExternalSubcommand,
    About,
    LongAbout,
    LongHelp,
    Author,
    Version,
    RenameAllEnv,
    RenameAll,
    Skip,
    DefaultValueT,
    DefaultValuesT,
    DefaultValueOsT,
    DefaultValuesOsT,
    NextDisplayOrder,
    NextHelpHeading,
}

/// `enum AttrValue { LitStr(LitStr), Expr(Expr), Call(Vec<Expr>) }`
type AttrValue = AttrValueLitStr | AttrValueExpr | AttrValueCall

class AttrValueLitStr { lit: root.syn.LitStr }
class AttrValueExpr { expr: root.syn.Expr }
class AttrValueCall { args: root.syn.Expr[] }

class ClapAttr {
    kind: AttrKind,
    name: string,
    magic: MagicAttrName?,
    value: AttrValue?,

    function value_or_abort(self) -> AttrValue {
        self.value ?? abort(`attribute \`${self.name}\` requires a value`)
    }

    function lit_str_or_abort(self) -> root.syn.LitStr {
        match (self.value_or_abort()) {
            let l: AttrValueLitStr => l.lit,
            _ => abort(`attribute \`${self.name}\` can only accept string literals`),
        }
    }
}

/// `ClapAttr::parse_all`
function parse_all(all_attrs: root.syn.Attribute[]) -> ClapAttr[] {
    let parsed: ClapAttr[] = [];
    for (let attr in all_attrs) {
        let kind: AttrKind? = match (attr.path.joined()) {
            "clap" => AttrKind.Clap,
            "structopt" => AttrKind.StructOpt,
            "command" => AttrKind.Command,
            "group" => AttrKind.Group,
            "arg" => AttrKind.Arg,
            "value" => AttrKind.Value,
            _ => null,
        };
        if let k: AttrKind = kind {
            let input = attr.parse_args();
            let attrs = root.syn.parse_terminated<ClapAttr>(input, (i) -> { parse_clap_attr(i) }) catch (e) {
                let err: root.syn.Error => abort(err.message),
            };
            for (let a in attrs) {
                a.kind = k;
                parsed.push(a);
            }
        }
    }
    parsed
}

/// `impl Parse for ClapAttr`
function parse_clap_attr(input: root.syn.ParseBuffer) -> ClapAttr throws root.syn.Error {
    let name = input.parse_ident();

    let magic: MagicAttrName? = match (name) {
        "rename_all" => MagicAttrName.RenameAll,
        "rename_all_env" => MagicAttrName.RenameAllEnv,
        "skip" => MagicAttrName.Skip,
        "next_display_order" => MagicAttrName.NextDisplayOrder,
        "next_help_heading" => MagicAttrName.NextHelpHeading,
        "default_value_t" => MagicAttrName.DefaultValueT,
        "default_values_t" => MagicAttrName.DefaultValuesT,
        "default_value_os_t" => MagicAttrName.DefaultValueOsT,
        "default_values_os_t" => MagicAttrName.DefaultValuesOsT,
        "long" => MagicAttrName.Long,
        "short" => MagicAttrName.Short,
        "value_parser" => MagicAttrName.ValueParser,
        "action" => MagicAttrName.Action,
        "env" => MagicAttrName.Env,
        "flatten" => MagicAttrName.Flatten,
        "value_enum" => MagicAttrName.ValueEnum,
        "from_global" => MagicAttrName.FromGlobal,
        "subcommand" => MagicAttrName.Subcommand,
        "external_subcommand" => MagicAttrName.ExternalSubcommand,
        "verbatim_doc_comment" => MagicAttrName.VerbatimDocComment,
        "about" => MagicAttrName.About,
        "long_about" => MagicAttrName.LongAbout,
        "long_help" => MagicAttrName.LongHelp,
        "author" => MagicAttrName.Author,
        "version" => MagicAttrName.Version,
        _ => null,
    };

    let value: AttrValue? = if (input.eat_punct("=")) {
        // `name = value` attributes.
        if (input.peek_lit_str() && next_is_separator(input, 1)) {
            AttrValueLitStr { lit: input.parse_lit_str() }
        } else {
            AttrValueExpr { expr: input.parse_expr() }
        }
    } else if let g: root.proc_macro2.Group = input.peek_group(root.proc_macro2.Delimiter.Parenthesis) {
        // `name(...)` attributes.
        input._pos += 1;
        AttrValueCall { args: root.syn.parse_comma_exprs(g.stream) }
    } else {
        null
    };

    ClapAttr { kind: AttrKind.Clap, name: name, magic: magic, value: value }
}

/// Is the token `offset` ahead a `,` or the end of the input?
function next_is_separator(input: root.syn.ParseBuffer, offset: int) -> bool {
    match (input.peek_tree(offset)) {
        null => true,
        let p: root.proc_macro2.Punct => p.ch == ",",
        _ => false,
    }
}
