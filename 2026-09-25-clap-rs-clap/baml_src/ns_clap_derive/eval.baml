// No direct Rust counterpart.
//
// In Rust, `clap_derive` splices each attribute's expression into generated
// code (`quote!(.#name(#args))`) that the compiler then type-checks and runs.
// The BAML derive runs at runtime instead, so this module *evaluates* those
// `syn::Expr`s: literals, ranges, arrays, paths such as `ArgAction::Count`,
// `value_parser!(T)`, the clap value-parser constructors, and references to
// BAML functions in the user's namespace (a zero-argument function plays the
// role of a Rust `const`, e.g. `styles = CLAP_STYLING`; a one-argument function
// is a value parser, e.g. `value_parser = port_in_range`).
//
// It then applies each `Method` to the builder (`Arg`, `Command`, `ArgGroup`).

/// Where to resolve user identifiers
class EvalCtx {
    /// The user's namespace, e.g. `clap.examples.git_derive` (without `root.`)
    ns: string,
    pkg: reflect.Package,

    function for_type(t: reflect.Type) -> EvalCtx {
        let name = t.to_string();
        let parts = name.split(".");
        let ns = if (parts.length() > 1) { parts.slice(0, parts.length() - 1).join(".") } else { "" };
        EvalCtx { ns: ns, pkg: reflect.Package.current() }
    }

    /// Candidate fully-qualified names for a Rust path
    function candidates(self, segments: string[]) -> string[] {
        let joined = segments.join(".");
        let out: string[] = [];
        if (!self.ns.is_empty()) {
            out.push(`root.${self.ns}.${joined}`);
        }
        out.push(`root.${joined}`);
        out
    }

    function find_function(self, segments: string[]) -> string? {
        let fns = self.pkg.functions();
        let found = self.candidates(segments).find((c) -> { fns.has(c) });
        if let f: string = found {
            return f;
        }
        let suffix = `.${segments.join(".")}`;
        fns.keys().find((k) -> { k.ends_with(suffix) })
    }

    function find_enum(self, ident: string) -> reflect.enum.Type? {
        let enums = self.pkg.enums();
        for (let c in self.candidates([ident])) {
            if let e: reflect.enum.Type = enums.get(c) {
                return e;
            }
        }
        let suffix = `.${ident}`;
        let key = enums.keys().find((k) -> { k.ends_with(suffix) });
        if let k: string = key { enums.get(k) } else { null }
    }

    function find_class(self, ident: string) -> reflect.class.Type? {
        let classes = self.pkg.classes();
        for (let c in self.candidates([ident])) {
            if let cl: reflect.class.Type = classes.get(c) {
                return cl;
            }
        }
        let suffix = `.${ident}`;
        let key = classes.keys().find((k) -> { k.ends_with(suffix) });
        if let k: string = key { classes.get(k) } else { null }
    }
}

type ParseFn = (string) -> unknown throws unknown

/// Call a BAML function by its qualified name (`root.ns.f`) with positional arguments
function call_user_fn(ctx: EvalCtx, fname: string, args: unknown[]) -> unknown throws unknown {
    let sig = ctx.pkg.functions().get(fname) ?? abort(`unknown function ${fname}`);
    let f = ctx.pkg.get_function<reflect.AnyFunction>(fname.replace("root.", "")) catch_all (err) { _ => null };
    let func = f ?? abort(`cannot load function ${fname}`);
    let params = sig.params();
    let named: map<string, unknown> = {};
    for (let i in baml.iter.Range.new(0, args.length())) {
        let pname = params.at(i)?.name ?? `$arg${i}`;
        named.set(pname, args[i]);
    }
    reflect.call_any(func, named)
}

/// `start..end` / `start..=end`
class RangeValue {
    start: int?,
    end: int?,
    closed: bool,
}

/// A reference to a variant of a user `enum` (e.g. `ColorWhen::Auto`)
class EnumVariantRef {
    enum_type: reflect.enum.Type,
    variant: string,
}

/// A reference to a one-argument BAML function used as a value parser
class FnRef {
    name: string,
    func: ParseFn,
    return_type: reflect.Type,
}

function eval_arg(a: MethodArg, ctx: EvalCtx) -> unknown {
    match (a) {
        let c: Computed => c.value,
        let d: DefaultValueT => abort("`default_value_t` needs a field context"),
        let e: root.syn.Expr => eval_expr(e, ctx),
    }
}

/// Strip crate prefixes such as `clap::`, `clap::builder::`, `std::path::`
function strip_path(segments: string[]) -> string[] {
    let prefixes = ["clap", "clap_builder", "builder", "styling", "error", "parser", "std", "ffi", "path", "anstyle", "crate", "self", "super", "string", "num"];
    let s = segments.slice(0, segments.length());
    while (s.length() > 1 && prefixes.includes(s[0])) {
        s.shift();
    }
    s
}

function eval_expr(e: root.syn.Expr, ctx: EvalCtx) -> unknown {
    match (e) {
        let l: root.syn.ExprLit => match (l.lit) {
            let s: root.syn.LitStr => s.value(),
            let c: root.syn.LitChar => c.value(),
            let i: root.syn.LitInt => i.base10_parse() catch (err) { let x: root.syn.Error => abort(x.message) },
            let f: root.syn.LitFloat => f.base10_parse() catch (err) { let x: root.syn.Error => abort(x.message) },
            let b: root.syn.LitBool => b.value,
        },
        let u: root.syn.ExprUnary => {
            let v = eval_expr(u.expr, ctx);
            match (u.op) {
                "-" => match (v) {
                    let i: int => 0 - i,
                    let f: float => 0.0 - f,
                    _ => abort(`cannot negate \`${root.syn.expr_to_string(u.expr)}\``),
                },
                "!" => !as_bool(v),
                _ => v,
            }
        },
        let p: root.syn.ExprParen => eval_expr(p.expr, ctx),
        let r: root.syn.ExprReference => eval_expr(r.expr, ctx),
        let a: root.syn.ExprArray => a.elems.map((x) -> { eval_expr(x, ctx) }),
        let t: root.syn.ExprTuple => t.elems.map((x) -> { eval_expr(x, ctx) }),
        let r: root.syn.ExprRange => RangeValue {
            start: if let s: root.syn.Expr = r.start { as_int(eval_expr(s, ctx)) } else { null },
            end: if let en: root.syn.Expr = r.end { as_int(eval_expr(en, ctx)) } else { null },
            closed: r.closed,
        },
        let b: root.syn.ExprBinary => {
            let l = as_int(eval_expr(b.left, ctx));
            let r = as_int(eval_expr(b.right, ctx));
            match (b.op) {
                "+" => l + r,
                "-" => l - r,
                "*" => l * r,
                "/" => l / r,
                _ => abort(`unsupported operator \`${b.op}\``),
            }
        },
        let p: root.syn.ExprPath => eval_path(p.path, ctx),
        let m: root.syn.ExprMacro => eval_macro(m, ctx),
        let c: root.syn.ExprCall => eval_call(c, ctx),
        let m: root.syn.ExprMethodCall => eval_method_call(m, ctx),
        let c: root.syn.ExprClosure => abort(`closures are not supported in BAML attributes (\`${root.syn.expr_to_string(c)}\`); name a BAML function instead`),
        let f: root.syn.ExprField => abort(`field access is not supported in attributes (\`${root.syn.expr_to_string(f)}\`)`),
    }
}

function eval_path(path: root.syn.Path, ctx: EvalCtx) -> unknown {
    let segs = strip_path(path.segments.map((s) -> { s.ident }));
    let joined = segs.join("::");
    match (joined) {
        "None" => { return null; },
        "true" => { return true; },
        "false" => { return false; },
        "usize::MAX" | "u64::MAX" => { return root.clap_builder.USIZE_MAX(); },
        _ => {},
    }
    if (segs.length() >= 2) {
        let variant = segs[segs.length() - 1];
        match (segs[segs.length() - 2]) {
            "ArgAction" => { return arg_action_from_name(variant); },
            "ValueHint" => { return root.clap_builder.value_hint_from_str(variant) catch (err) { let s: string => abort(s) }; },
            "ColorChoice" => {
                return match (variant) {
                    "Auto" => root.clap_builder.ColorChoice.Auto,
                    "Always" => root.clap_builder.ColorChoice.Always,
                    "Never" => root.clap_builder.ColorChoice.Never,
                    _ => abort(`unknown ColorChoice::${variant}`),
                };
            },
            "ErrorKind" => { return abort("`ErrorKind` values are not supported in attributes"); },
            "AnsiColor" => {
                let idx = ["Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White", "BrightBlack", "BrightRed", "BrightGreen", "BrightYellow", "BrightBlue", "BrightMagenta", "BrightCyan", "BrightWhite"].index_of(variant);
                if let i: int = idx {
                    return root.anstyle.ansi_from_index(i);
                }
            },
            _ => {},
        }
        // A user enum variant, e.g. `ColorWhen::Auto` or `foreign_crate::LogLevel::Info`
        // (Rust modules within one example share a BAML namespace)
        if let et: reflect.enum.Type = ctx.find_enum(segs[segs.length() - 2]) {
            return EnumVariantRef { enum_type: et, variant: variant };
        }
    }
    // A BAML function standing in for a Rust `const`/`static` or `fn`
    if let fname: string = ctx.find_function(segs) {
        let ft = ctx.pkg.functions().get(fname) ?? abort(`unknown function ${fname}`);
        let params = ft.params();
        if (params.length() == 0) {
            return call_user_fn(ctx, fname, []) catch_all (err) { _ => abort(`calling \`${fname}\` failed: ${err}`) };
        } else if (params.length() == 1) {
            let pf: ParseFn = (s) -> { call_user_fn(ctx, fname, [s]) };
            return FnRef { name: fname, func: pf, return_type: ft.return_type() };
        }
        abort(`function \`${fname}\` has an unsupported signature for an attribute value`)
    }
    abort(`cannot resolve \`${root.syn.path_to_string(path)}\` (define a BAML function with that name in namespace \`${ctx.ns}\`)`)
}

function arg_action_from_name(name: string) -> root.clap_builder.ArgAction {
    match (name) {
        "Set" => root.clap_builder.ArgAction.Set,
        "Append" => root.clap_builder.ArgAction.Append,
        "SetTrue" => root.clap_builder.ArgAction.SetTrue,
        "SetFalse" => root.clap_builder.ArgAction.SetFalse,
        "Count" => root.clap_builder.ArgAction.Count,
        "Help" => root.clap_builder.ArgAction.Help,
        "HelpShort" => root.clap_builder.ArgAction.HelpShort,
        "HelpLong" => root.clap_builder.ArgAction.HelpLong,
        "Version" => root.clap_builder.ArgAction.Version,
        _ => abort(`unknown ArgAction::${name}`),
    }
}

function eval_macro(m: root.syn.ExprMacro, ctx: EvalCtx) -> unknown {
    let name = strip_path(m.path.segments.map((s) -> { s.ident })).join("::");
    match (name) {
        "value_parser" => value_parser_for_type_name(m.tokens.to_string().replace_all(" ", ""), ctx),
        "vec" => {
            let elems = root.syn.parse_comma_exprs(m.tokens) catch (err) { let x: root.syn.Error => abort(x.message) };
            elems.map((x) -> { eval_expr(x, ctx) })
        },
        "crate_version" => root.clap_builder.crate_version(),
        "crate_name" => root.clap_builder.crate_name(),
        "crate_description" => root.clap_builder.crate_description(),
        "crate_authors" => root.clap_builder.crate_authors(),
        "env" => {
            let key = m.tokens.to_string().replace_all("\"", "").trim();
            let info = root.clap_builder.package_info();
            match (key) {
                "CARGO_PKG_NAME" | "CARGO_CRATE_NAME" | "CARGO_BIN_NAME" => info.name,
                "CARGO_PKG_VERSION" => info.version,
                "CARGO_PKG_DESCRIPTION" => info.description,
                "CARGO_PKG_AUTHORS" => info.authors,
                _ => (baml.env.get(key) catch_all (err) { _ => null }) ?? "",
            }
        },
        _ => abort(`unsupported macro \`${name}!\` in attribute`),
    }
}

/// `value_parser!(T)` by Rust type name
function value_parser_for_type_name(t: string, ctx: EvalCtx) -> unknown {
    let name = t.split("::").at(-1) ?? t;
    match (name) {
        "String" | "str" => root.clap_builder.ValueParser.string(),
        "OsString" | "OsStr" => root.clap_builder.ValueParser.os_string(),
        "PathBuf" | "Path" => root.clap_builder.ValueParser.path_buf(),
        "bool" => root.clap_builder.ValueParser.bool(),
        "u8" => root.clap_builder.value_parser_u8(),
        "i8" => root.clap_builder.value_parser_i8(),
        "u16" => root.clap_builder.value_parser_u16(),
        "i16" => root.clap_builder.value_parser_i16(),
        "u32" => root.clap_builder.value_parser_u32(),
        "i32" => root.clap_builder.value_parser_i32(),
        "i64" | "isize" => root.clap_builder.value_parser_i64(),
        "u64" | "usize" => root.clap_builder.value_parser_u64(),
        "f32" | "f64" => root.clap_builder.value_parser_f64(),
        _ => {
            if let et: reflect.enum.Type = ctx.find_enum(name) {
                return default_value_parser(et.as_type(), true);
            }
            if let ct: reflect.class.Type = ctx.find_class(name) {
                return default_value_parser(ct.as_type(), false);
            }
            abort(`value_parser!(${t}): unknown type`)
        },
    }
}

function eval_call(c: root.syn.ExprCall, ctx: EvalCtx) -> unknown {
    let args = c.args.map((a) -> { eval_expr(a, ctx) });
    let fpath = match (c.func) {
        let p: root.syn.ExprPath => p.path,
        _ => abort(`unsupported call \`${root.syn.expr_to_string(c.func)}\``),
    };
    let segs = strip_path(fpath.segments.map((s) -> { s.ident }));
    let joined = segs.join("::");
    match (joined) {
        "Some" => args[0],
        "String::from" | "Str::from" | "OsStr::new" | "OsString::from" | "PathBuf::from" | "Id::from" => args[0],
        "PossibleValuesParser::new" => root.clap_builder.PossibleValuesParser.new(as_string_list(args[0])),
        "NonEmptyStringValueParser::new" => root.clap_builder.NonEmptyStringValueParser.new(),
        "BoolishValueParser::new" => root.clap_builder.BoolishValueParser.new(),
        "FalseyValueParser::new" => root.clap_builder.FalseyValueParser.new(),
        "BoolValueParser::new" => root.clap_builder.BoolValueParser.new(),
        "StringValueParser::new" => root.clap_builder.StringValueParser.new(),
        "OsStringValueParser::new" => root.clap_builder.OsStringValueParser.new(),
        "PathBufValueParser::new" => root.clap_builder.PathBufValueParser.new(),
        "RangedI64ValueParser::new" => {
            let ty = fpath.segments.flat_map((s) -> { s.arguments }).at(0) ?? "i64";
            value_parser_for_type_name(ty, ctx)
        },
        "RangedU64ValueParser::new" => root.clap_builder.RangedU64ValueParser.new(),
        "EnumValueParser::new" => {
            let ty = fpath.segments.flat_map((s) -> { s.arguments }).at(0) ?? abort("EnumValueParser::<E>::new() needs a type");
            value_parser_for_type_name(ty, ctx)
        },
        "ValueParser::new" => as_value_parser(args[0], "ValueParser::new"),
        "ValueParser::string" => root.clap_builder.ValueParser.string(),
        "ValueParser::os_string" => root.clap_builder.ValueParser.os_string(),
        "ValueParser::path_buf" => root.clap_builder.ValueParser.path_buf(),
        "ValueParser::bool" => root.clap_builder.ValueParser.bool(),
        "ValueRange::new" => as_value_range(args[0]),
        "Styles::styled" => root.clap_builder.Styles.styled(),
        "Styles::plain" => root.clap_builder.Styles.plain(),
        "PossibleValue::new" => root.clap_builder.PossibleValue.new(as_string(args[0], "PossibleValue::new")),
        "ArgGroup::new" => root.clap_builder.ArgGroup.new(as_string(args[0], "ArgGroup::new")),
        _ => {
            // A call of a user BAML function
            if let fname: string = ctx.find_function(segs) {
                return call_user_fn(ctx, fname, args) catch_all (err) { _ => abort(`calling \`${fname}\` failed: ${err}`) };
            }
            abort(`unsupported call \`${root.syn.expr_to_string(c)}\``)
        },
    }
}

function eval_method_call(m: root.syn.ExprMethodCall, ctx: EvalCtx) -> unknown {
    let recv = eval_expr(m.receiver, ctx);
    let args = m.args.map((a) -> { eval_expr(a, ctx) });
    match (m.method) {
        "into" | "to_owned" | "to_string" | "clone" => recv,
        "range" => {
            let r = match (args[0]) {
                let rv: RangeValue => rv,
                _ => abort("`.range()` expects a range"),
            };
            let lo = r.start;
            let hi = if let e: int = r.end { if (r.closed) { e } else { e - 1 } } else { null };
            match (recv) {
                let p: root.clap_builder.RangedI64ValueParser => p.range(lo, hi),
                let p: root.clap_builder.RangedU64ValueParser => p.range(lo, hi),
                _ => abort("`.range()` is only supported on integer value parsers"),
            }
        },
        "map" | "try_map" => abort(`closures are not supported in BAML attributes (\`.${m.method}(...)\`); write a BAML function returning the parser instead`),
        "help" => match (recv) {
            let p: root.clap_builder.PossibleValue => p.help(as_opt_string(args[0])),
            _ => abort("`.help()` is only supported on PossibleValue"),
        },
        _ => abort(`unsupported method call \`.${m.method}(...)\` in attribute`),
    }
}

/// Evaluate a `value_parser = ...` expression (a bare range is an `i64` range parser)
function eval_value_parser(a: MethodArg, ctx: EvalCtx, inner: reflect.Type) -> unknown {
    eval_arg(a, ctx)
}

// ===== conversions =====

function as_string(v: unknown, what: string) -> string {
    match (v) {
        let s: string => s,
        let i: int => `${i}`,
        let f: float => `${f}`,
        let b: bool => `${b}`,
        let e: EnumVariantRef => e.variant,
        _ => abort(`\`${what}\` expects a string, got ${v}`),
    }
}

function as_opt_string(v: unknown) -> string? {
    match (v) {
        null => null,
        _ => as_string(v, "value"),
    }
}

function as_bool(v: unknown) -> bool {
    match (v) {
        let b: bool => b,
        null => false,
        _ => abort(`expected a bool, got ${v}`),
    }
}

function as_int(v: unknown) -> int {
    match (v) {
        let i: int => i,
        _ => abort(`expected an integer, got ${v}`),
    }
}

function as_opt_int(v: unknown) -> int? {
    match (v) {
        null => null,
        _ => as_int(v),
    }
}

function as_string_list(v: unknown) -> string[] {
    match (v) {
        let items: unknown[] => items.map((x) -> { as_string(x, "list item") }),
        let s: string => [s],
        _ => abort(`expected a list of strings, got ${v}`),
    }
}

function as_value_range(v: unknown) -> root.clap_builder.ValueRange {
    match (v) {
        let r: root.clap_builder.ValueRange => r,
        let i: int => root.clap_builder.ValueRange.new(i),
        let rv: RangeValue => {
            let start = rv.start ?? 0;
            if let e: int = rv.end {
                if (rv.closed) {
                    root.clap_builder.ValueRange.inclusive(start, e)
                } else {
                    root.clap_builder.ValueRange.range(start, e)
                }
            } else {
                root.clap_builder.ValueRange.from(start)
            }
        },
        _ => abort(`expected a number of values, got ${v}`),
    }
}

function as_value_parser(v: unknown, what: string) -> root.clap_builder.ValueParser {
    match (v) {
        let vp: root.clap_builder.ValueParser => vp,
        let t: root.clap_builder.TypedValueParser => root.clap_builder.ValueParser.new(t),
        let items: unknown[] => root.clap_builder.ValueParser.new(root.clap_builder.PossibleValuesParser.new(as_string_list(items))),
        let rv: RangeValue => {
            let hi = if let e: int = rv.end { if (rv.closed) { e } else { e - 1 } } else { null };
            root.clap_builder.ValueParser.new(root.clap_builder.RangedI64ValueParser.new().range(rv.start, hi))
        },
        let f: FnRef => {
            let func = f.func;
            let parser = root.clap_builder.FnValueParser { _func: func, _type_id: root.clap_builder.AnyValueId { type_name: fn_value_type_name(f.return_type) } };
            root.clap_builder.ValueParser.new(parser)
        },
        _ => abort(`\`${what}\` expects a value parser, got ${v}`),
    }
}

/// The `AnyValueId` of a parser function's return type
function fn_value_type_name(t: reflect.Type) -> string {
    t.to_string()
}

function as_action(v: unknown) -> root.clap_builder.ArgAction {
    match (v) {
        let a: root.clap_builder.ArgAction => a,
        _ => abort(`expected an ArgAction, got ${v}`),
    }
}

function as_styled(v: unknown) -> root.clap_builder.StyledStr | string | null {
    match (v) {
        null => null,
        let s: string => s,
        let st: root.clap_builder.StyledStr => st,
        _ => as_string(v, "text"),
    }
}

// ===== applying methods to builders =====

/// Apply `.name(args)` to an `Arg`
function apply_arg_method(arg: root.clap_builder.Arg, m: Method, ctx: EvalCtx, field_ty: reflect.Type?) -> root.clap_builder.Arg {
    let n = m.name;
    if (n == "default_value" || n == "default_values") {
        if let d: DefaultValueT = m.args.at(0) {
            let vals = render_default_value_t(d, ctx);
            return if (n == "default_value") { arg.default_value(vals.at(0)) } else { arg.default_values(vals) };
        }
    }
    let a = m.args.map((x) -> { eval_arg(x, ctx) });
    let a0: unknown = a.at(0);
    match (n) {
        "id" => arg.id(as_string(a0, n)),
        "short" => arg.short(as_opt_string(a0)),
        "long" => arg.long(as_opt_string(a0)),
        "alias" => arg.alias(as_opt_string(a0)),
        "short_alias" => arg.short_alias(as_opt_string(a0)),
        "aliases" => arg.aliases(as_string_list(a0)),
        "short_aliases" => arg.short_aliases(as_string_list(a0)),
        "visible_alias" => arg.visible_alias(as_opt_string(a0)),
        "visible_short_alias" => arg.visible_short_alias(as_opt_string(a0)),
        "visible_aliases" => arg.visible_aliases(as_string_list(a0)),
        "visible_short_aliases" => arg.visible_short_aliases(as_string_list(a0)),
        "index" => arg.index(as_opt_int(a0)),
        "trailing_var_arg" => arg.trailing_var_arg(as_bool(a0)),
        "last" => arg.last(as_bool(a0)),
        "required" => arg.required(as_bool(a0)),
        "requires" => arg.requires(as_opt_string(a0)),
        "exclusive" => arg.exclusive(as_bool(a0)),
        "global" => arg.global(as_bool(a0)),
        "action" => arg.action(as_action(a0)),
        "value_parser" => arg.value_parser(as_value_parser(a0, n)),
        "num_args" => arg.num_args(if (a0 == null) { null } else { as_value_range(a0) }),
        "value_name" => arg.value_name(as_opt_string(a0)),
        "value_names" => arg.value_names(as_string_list(a0)),
        "value_hint" => match (a0) {
            let h: root.clap_builder.ValueHint => arg.value_hint(h),
            _ => arg.value_hint(null),
        },
        "ignore_case" => arg.ignore_case(as_bool(a0)),
        "allow_hyphen_values" => arg.allow_hyphen_values(as_bool(a0)),
        "allow_negative_numbers" => arg.allow_negative_numbers(as_bool(a0)),
        "require_equals" => arg.require_equals(as_bool(a0)),
        "value_delimiter" => arg.value_delimiter(as_opt_string(a0)),
        "value_terminator" => arg.value_terminator(as_opt_string(a0)),
        "raw" => arg.raw(as_bool(a0)),
        "default_value" => arg.default_value(as_opt_string(a0)),
        "default_values" => arg.default_values(as_string_list(a0)),
        "default_missing_value" => arg.default_missing_value(as_opt_string(a0)),
        "default_missing_values" => arg.default_missing_values(as_string_list(a0)),
        "env" => arg.env(as_opt_string(a0)),
        "help" => arg.help(as_styled(a0)),
        "long_help" => arg.long_help(as_styled(a0)),
        "display_order" => arg.display_order(as_opt_int(a0)),
        "help_heading" => arg.help_heading(as_opt_string(a0)),
        "next_line_help" => arg.next_line_help(as_bool(a0)),
        "hide" => arg.hide(as_bool(a0)),
        "hide_possible_values" => arg.hide_possible_values(as_bool(a0)),
        "hide_default_value" => arg.hide_default_value(as_bool(a0)),
        "hide_env" => arg.hide_env(as_bool(a0)),
        "hide_env_values" => arg.hide_env_values(as_bool(a0)),
        "hide_short_help" => arg.hide_short_help(as_bool(a0)),
        "hide_long_help" => arg.hide_long_help(as_bool(a0)),
        "group" => arg.group(as_opt_string(a0)),
        "groups" => arg.groups(as_string_list(a0)),
        "default_value_if" => arg.default_value_if(as_string(a0, n), root.clap_builder.into_arg_predicate(predicate_value(a.at(1))), as_opt_string(a.at(2))),
        "required_unless_present" => arg.required_unless_present(as_opt_string(a0)),
        "required_unless_present_all" => arg.required_unless_present_all(as_string_list(a0)),
        "required_unless_present_any" => arg.required_unless_present_any(as_string_list(a0)),
        "required_if_eq" => arg.required_if_eq(as_string(a0, n), as_string(a.at(1), n)),
        "requires_if" => arg.requires_if(root.clap_builder.into_arg_predicate(predicate_value(a0)), as_string(a.at(1), n)),
        "conflicts_with" => arg.conflicts_with(as_opt_string(a0)),
        "conflicts_with_all" => arg.conflicts_with_all(as_string_list(a0)),
        "overrides_with" => arg.overrides_with(as_opt_string(a0)),
        "overrides_with_all" => arg.overrides_with_all(as_string_list(a0)),
        _ => abort(`unknown \`Arg\` method \`${n}\``),
    }
}

function predicate_value(v: unknown) -> root.clap_builder.ArgPredicate | string {
    match (v) {
        let p: root.clap_builder.ArgPredicate => p,
        _ => as_string(v, "predicate"),
    }
}

/// Render a `default_value_t` / `default_values_t` to the string(s) clap stores
function render_default_value_t(d: DefaultValueT, ctx: EvalCtx) -> string[] {
    let raw: unknown = if let e: root.syn.Expr = d.expr {
        eval_expr(e, ctx)
    } else {
        // `<T as Default>::default()`
        default_for_type(d.ty)
    };
    let items: unknown[] = if (d.many) {
        match (raw) {
            let xs: unknown[] => xs,
            _ => [raw],
        }
    } else {
        [raw]
    };
    items.map((v) -> {
        match (v) {
            let e: EnumVariantRef => {
                if (d.value_enum) {
                    // `ValueEnum::to_possible_value(&val).unwrap().get_name()`
                    value_enum_possible_value_name(e.enum_type, e.variant, ctx)
                } else {
                    // `ToString::to_string(&val)`: BAML enums cannot implement `ToString`,
                    // so `impl Display for E` is written as a free `e_to_string(e: E)` function
                    enum_display(e, ctx)
                }
            },
            let b: bool => `${b}`,
            let i: int => `${i}`,
            let f: float => float_display(f),
            let s: string => s,
            _ => `${v}`,
        }
    })
}

function enum_display(e: EnumVariantRef, ctx: EvalCtx) -> string {
    let ident = type_ident(e.enum_type.as_type());
    let fname = ctx.find_function([`${root.heck.to_snake_case(ident)}_to_string`]);
    if let f: string = fname {
        type E = unreflect(e.enum_type.as_type());
        let j: baml.json.json = e.variant;
        let value = baml.json.to<E>(j) catch_all (err) { _ => abort(`unknown variant ${e.variant}`) };
        let r = call_user_fn(ctx, f, [value]) catch_all (err) { _ => abort(`calling \`${f}\` failed: ${err}`) };
        as_string(r, f)
    } else {
        e.variant
    }
}

/// Rust's `f64` `Display` (no trailing `.0` elision beyond what Rust does)
function float_display(f: float) -> string {
    let s = `${f}`;
    if (s.ends_with(".0")) { s.slice(0, s.length() - 2) } else { s }
}

function default_for_type(t: reflect.Type) -> unknown {
    match (t.to_string()) {
        "string" => "",
        "int" => 0,
        "float" => 0.0,
        "bool" => false,
        _ => {
            if let e: reflect.enum.Type = t.as_enum() {
                EnumVariantRef { enum_type: e, variant: e.values()[0].name }
            } else {
                abort(`no default value for type ${t}`)
            }
        },
    }
}

/// Apply `.name(args)` to a `Command`
function apply_command_method(cmd: root.clap_builder.Command, m: Method, ctx: EvalCtx) -> root.clap_builder.Command {
    let n = m.name;
    let a = m.args.map((x) -> { eval_arg(x, ctx) });
    let a0: unknown = a.at(0);
    match (n) {
        "name" => cmd.name(as_string(a0, n)),
        "bin_name" => cmd.bin_name(as_opt_string(a0)),
        "display_name" => cmd.display_name(as_opt_string(a0)),
        "author" => cmd.author(as_opt_string(a0)),
        "about" => cmd.about(as_styled(a0)),
        "long_about" => cmd.long_about(as_styled(a0)),
        "after_help" => cmd.after_help(as_styled(a0)),
        "after_long_help" => cmd.after_long_help(as_styled(a0)),
        "before_help" => cmd.before_help(as_styled(a0)),
        "before_long_help" => cmd.before_long_help(as_styled(a0)),
        "version" => cmd.version(as_opt_string(a0)),
        "long_version" => cmd.long_version(as_opt_string(a0)),
        "override_usage" => cmd.override_usage(as_styled(a0)),
        "override_help" => cmd.override_help(as_styled(a0)),
        "help_template" => cmd.help_template(as_styled(a0)),
        "flatten_help" => cmd.flatten_help(as_bool(a0)),
        "next_help_heading" => cmd.next_help_heading(as_opt_string(a0)),
        "next_display_order" => cmd.next_display_order(as_opt_int(a0)),
        "arg_required_else_help" => cmd.arg_required_else_help(as_bool(a0)),
        "allow_missing_positional" => cmd.allow_missing_positional(as_bool(a0)),
        "short_flag" => cmd.short_flag(as_opt_string(a0)),
        "long_flag" => cmd.long_flag(as_string(a0, n)),
        "alias" => cmd.alias(as_opt_string(a0)),
        "aliases" => cmd.aliases(as_string_list(a0)),
        "visible_alias" => cmd.visible_alias(as_opt_string(a0)),
        "visible_aliases" => cmd.visible_aliases(as_string_list(a0)),
        "short_flag_alias" => cmd.short_flag_alias(as_opt_string(a0)),
        "long_flag_alias" => cmd.long_flag_alias(as_opt_string(a0)),
        "visible_short_flag_alias" => cmd.visible_short_flag_alias(as_opt_string(a0)),
        "visible_long_flag_alias" => cmd.visible_long_flag_alias(as_opt_string(a0)),
        "display_order" => cmd.display_order(as_opt_int(a0)),
        "hide" => cmd.hide(as_bool(a0)),
        "subcommand_required" => cmd.subcommand_required(as_bool(a0)),
        "allow_external_subcommands" => cmd.allow_external_subcommands(as_bool(a0)),
        "args_conflicts_with_subcommands" => cmd.args_conflicts_with_subcommands(as_bool(a0)),
        "subcommand_precedence_over_arg" => cmd.subcommand_precedence_over_arg(as_bool(a0)),
        "subcommand_negates_reqs" => cmd.subcommand_negates_reqs(as_bool(a0)),
        "multicall" => cmd.multicall(as_bool(a0)),
        "subcommand_value_name" => cmd.subcommand_value_name(as_opt_string(a0)),
        "subcommand_help_heading" => cmd.subcommand_help_heading(as_opt_string(a0)),
        "no_binary_name" => cmd.no_binary_name(as_bool(a0)),
        "ignore_errors" => cmd.ignore_errors(as_bool(a0)),
        "args_override_self" => cmd.args_override_self(as_bool(a0)),
        "dont_delimit_trailing_values" => cmd.dont_delimit_trailing_values(as_bool(a0)),
        "color" => match (a0) {
            let c: root.clap_builder.ColorChoice => cmd.color(c),
            _ => abort("`color` expects a ColorChoice"),
        },
        "styles" => match (a0) {
            let s: root.clap_builder.Styles => cmd.styles(s),
            _ => abort("`styles` expects Styles"),
        },
        "term_width" => cmd.term_width(as_int(a0)),
        "max_term_width" => cmd.max_term_width(as_int(a0)),
        "disable_version_flag" => cmd.disable_version_flag(as_bool(a0)),
        "propagate_version" => cmd.propagate_version(as_bool(a0)),
        "next_line_help" => cmd.next_line_help(as_bool(a0)),
        "disable_help_flag" => cmd.disable_help_flag(as_bool(a0)),
        "disable_help_subcommand" => cmd.disable_help_subcommand(as_bool(a0)),
        "disable_colored_help" => cmd.disable_colored_help(as_bool(a0)),
        "help_expected" => cmd.help_expected(as_bool(a0)),
        "hide_possible_values" => cmd.hide_possible_values(as_bool(a0)),
        "infer_long_args" => cmd.infer_long_args(as_bool(a0)),
        "infer_subcommands" => cmd.infer_subcommands(as_bool(a0)),
        "allow_hyphen_values" => cmd.allow_hyphen_values(as_bool(a0)),
        "allow_negative_numbers" => cmd.allow_negative_numbers(as_bool(a0)),
        "trailing_var_arg" => cmd.trailing_var_arg(as_bool(a0)),
        _ => abort(`unknown \`Command\` method \`${n}\``),
    }
}

/// Apply `.name(args)` to an `ArgGroup`
function apply_group_method(g: root.clap_builder.ArgGroup, m: Method, ctx: EvalCtx) -> root.clap_builder.ArgGroup {
    let n = m.name;
    let a = m.args.map((x) -> { eval_arg(x, ctx) });
    let a0: unknown = a.at(0);
    match (n) {
        "id" | "name" => g.id(as_string(a0, n)),
        "arg" => g.arg(as_opt_string(a0)),
        "args" => g.args(as_string_list(a0)),
        "multiple" => g.multiple(as_bool(a0)),
        "required" => g.required(as_bool(a0)),
        "requires" => g.requires(as_opt_string(a0)),
        "requires_all" => g.requires_all(as_string_list(a0)),
        "conflicts_with" => g.conflicts_with(as_opt_string(a0)),
        "conflicts_with_all" => g.conflicts_with_all(as_string_list(a0)),
        _ => abort(`unknown \`ArgGroup\` method \`${n}\``),
    }
}
