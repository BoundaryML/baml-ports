// Port of clap_builder/src/macros.rs
//
// Rust macros become functions:
//   crate_version!()     -> crate_version()
//   crate_authors!(sep)  -> crate_authors(sep = ...)
//   crate_description!() -> crate_description()
//   crate_name!()        -> crate_name()
//   command!() / command!(name) -> command() / command(name = ...)
//   arg!(...)            -> arg("...")   (the macro's token syntax, parsed at runtime)
//   value_parser!(T)     -> value_parser<T>() (see builder/value_parser.baml)
//   debug!, ok!, some!   -> not needed (BAML has `throws` propagation and `?.`)
//
// `env!("CARGO_PKG_*")` is resolved at runtime: first from the `CARGO_PKG_*`
// environment variables, then from the `[package]` table of the nearest
// `baml.toml` (keys `name`, `version`, `authors`, `description`).

class PackageInfo {
    name: string,
    version: string,
    authors: string,
    description: string,
}

function package_info() -> PackageInfo {
    let info = PackageInfo { name: "", version: "", authors: "", description: "" };

    let toml = find_baml_toml();
    if let text: string = toml {
        info.name = toml_package_value(text, "name") ?? "";
        info.version = toml_package_value(text, "version") ?? "";
        info.authors = toml_package_value(text, "authors") ?? "";
        info.description = toml_package_value(text, "description") ?? "";
    }

    let env_or = (key: string, fallback: string) -> string {
        (baml.env.get(key) catch_all (e) { _ => null }) ?? fallback
    };
    PackageInfo {
        name: env_or("CARGO_PKG_NAME", info.name),
        version: env_or("CARGO_PKG_VERSION", info.version),
        authors: env_or("CARGO_PKG_AUTHORS", info.authors),
        description: env_or("CARGO_PKG_DESCRIPTION", info.description),
    }
}

/// Locate `baml.toml` from the working directory upwards
function find_baml_toml() -> string? {
    let dir = ".";
    for (let i in baml.iter.Range.new(0, 8)) {
        let path = `${dir}/baml.toml`;
        let exists = baml.fs.exists(path) catch_all (e) { _ => false };
        if (exists) {
            return baml.fs.read(path) catch_all (e) { _ => null };
        }
        dir = `${dir}/..`;
    }
    null
}

/// Extract `key = "value"` (or `key = ["a", "b"]`, joined with `:` like Cargo) from `[package]`
function toml_package_value(text: string, key: string) -> string? {
    let in_package = false;
    for (let raw in text.lines()) {
        let line = raw.trim();
        if (line.starts_with("[")) {
            in_package = line == "[package]";
            continue;
        }
        if (!in_package || line.starts_with("#")) {
            continue;
        }
        if let eq: int = line.index_of("=") {
            let k = line.slice(0, eq).trim();
            if (k != key) {
                continue;
            }
            let v = line.slice(eq + 1, line.length()).trim();
            if (v.starts_with("[")) {
                let inner = v.slice(1, v.length() - 1);
                return inner.split(",").map((s) -> { unquote(s.trim()) }).filter((s) -> { !s.is_empty() }).join(":");
            }
            return unquote(v);
        }
    }
    null
}

function unquote(s: string) -> string {
    if (s.length() >= 2 && (s.starts_with("\"") && s.ends_with("\"") || s.starts_with("'") && s.ends_with("'"))) {
        s.slice(1, s.length() - 1)
    } else {
        s
    }
}

/// Allows you to pull the version from your Cargo.toml at compile time as
/// `MAJOR.MINOR.PATCH_PKGVERSION_PRE`
function crate_version() -> string { package_info().version }

/// Allows you to pull the authors for the command from your Cargo.toml at
/// compile time in the form:
/// `"author1 lastname <author1@example.com>:author2 lastname <author2@example.com>"`
///
/// You can replace the colons with a custom separator by supplying a
/// replacement string, so, for example,
/// `crate_authors(sep = ",\n")` would become
/// `"author1 lastname <author1@example.com>,\nauthor2 lastname <author2@example.com>,\nauthor3 lastname <author3@example.com>"`
function crate_authors(sep: string? = null) -> string {
    let authors = package_info().authors;
    if let s: string = sep {
        if (authors.includes(":")) {
            return authors.replace_all(":", s);
        }
    }
    authors
}

/// Allows you to pull the description from your Cargo.toml at compile time.
function crate_description() -> string { package_info().description }

/// Allows you to pull the name from your Cargo.toml at compile time.
///
/// **NOTE:** This macro extracts the name from an environment variable `CARGO_PKG_NAME`.
/// When the crate name is set to something different from the package name,
/// use environment variables `CARGO_CRATE_NAME` or `CARGO_BIN_NAME`.
function crate_name() -> string { package_info().name }

/// Allows you to build the `Command` instance from your Cargo.toml at compile time.
///
/// **NOTE:** Changing the values in your `Cargo.toml` does not trigger a re-build automatically,
/// and therefore won't change the generated output until you recompile.
function command(name: string? = null) -> Command {
    let info = package_info();
    let cmd = Command.new(name ?? info.name).version(info.version);
    let author = info.authors;
    if (!author.is_empty()) {
        cmd = cmd.author(author);
    }
    let about = info.description;
    if (!about.is_empty()) {
        cmd = cmd.about(about);
    }
    cmd
}

/// Create an [`Arg`] from a usage string.
///
/// Allows creation of basic settings for the [`Arg`].
///
/// **NOTE**: Not all settings may be set using the usage string method. Some properties are
/// only available via the builder pattern.
///
/// # Syntax
///
/// Usage strings typically following the form:
///
/// ```notrust
/// [explicit name] [short] [long] [value names] [...] [help string]
/// ```
///
/// ### Explicit Name
///
/// The name may be either a bare-word or a string, followed by a `:`, like `name:` or
/// `"name":`.
///
/// *Note:* This is an optional field, if it's omitted the argument will use one of the additional
/// fields as the name using the following priority order:
///
///  1. Explicit Name
///  2. Long
///  3. Value Name
///
/// See [`Arg::id`][crate::Arg::id].
///
/// ### Short
///
/// A short flag is a `-` followed by either a bare-character or quoted character, like `-f` or
/// `-'f'`.
///
/// See [`Arg::short`][crate::Arg::short].
///
/// ### Long
///
/// A long flag is a `--` followed by either a bare-word or a string, like `--foo` or
/// `--"foo"`.
///
/// **NOTE:** Dashes in the long name (e.g. `--foo-bar`) are not supported and quoting is required
/// (e.g. `--"foo-bar"`).
///
/// See [`Arg::long`][crate::Arg::long].
///
/// ### Values (Value Notation)
///
/// This is set by placing bare-word between:
/// - `[]` like `[FOO]`
///   - Positional argument: optional
///   - Named argument: optional value
/// - `<>` like `<FOO>`: required
///
/// See [`Arg::value_name`][crate::Arg::value_name].
///
/// ### `...`
///
/// `...` (three consecutive dots/periods) specifies that this argument may occur multiple
/// times (not to be confused with multiple values per occurrence).
///
/// See [`ArgAction::Count`][crate::ArgAction::Count] and [`ArgAction::Append`][crate::ArgAction::Append].
///
/// ### Help String
///
/// The help string is denoted between a pair of double quotes `""` and may contain any
/// characters.
///
/// # Examples
///
/// ```baml
/// let cmd = Command.new("prog")
///     .args([
///         arg("--config <FILE> \"a required file for the configuration and no short\""),
///         arg("-d --debug ... \"turns on debugging information and allows multiples\""),
///         arg("[input] \"an optional input file to use\""),
///     ]);
/// ```
function arg(spec: string) -> Arg {
    let tokens = arg_tokens(spec);
    let arg = Arg.default();
    let i = 0;

    // `$name:ident: $($tail:tt)+` / `$name:literal: $($tail:tt)+`
    if (tokens.length() > 1 && tokens[1].kind == "colon") {
        arg = Arg.new(tokens[0].text);
        i = 2;
    }

    while (i < tokens.length()) {
        let t = tokens[i];
        i += 1;
        match (t.kind) {
            "long" => {
                if (arg.get_value_names() != null) {
                    baml.sys.panic("Flags should precede values");
                }
                if (arg.get_action() == ArgAction.Append && arg._action != null) {
                    baml.sys.panic("Flags should precede `...`");
                }
                if (arg.get_id() == "") {
                    arg = arg.id(t.text);
                }
                arg = arg.long(t.text).action(ArgAction.SetTrue);
            },
            "short" => {
                if (arg.get_long() != null) {
                    baml.sys.panic("Short flags should precede long flags");
                }
                if (arg.get_value_names() != null) {
                    baml.sys.panic("Flags should precede values");
                }
                if (t.text.length() != 1) {
                    baml.sys.panic(`Single-letter identifier expected, got ${t.text}`);
                }
                arg = arg.short(t.text).action(ArgAction.SetTrue);
            },
            "required_value" => {
                if (arg.get_value_names() != null) {
                    baml.sys.panic("Multiple values not yet supported");
                }
                if (arg.get_long() == null && arg.get_short() == null) {
                    arg = arg.required(true);
                }
                if (arg.get_id() == "") {
                    arg = arg.id(t.text);
                }
                arg = arg.value_name(t.text).action(ArgAction.Set);
            },
            "optional_value" => {
                if (arg.get_value_names() != null) {
                    baml.sys.panic("Multiple values not yet supported");
                }
                if (arg.get_long() == null && arg.get_short() == null) {
                    arg = arg.required(false);
                } else {
                    arg = arg.num_args(ValueRange.inclusive(0, 1));
                }
                if (arg.get_id() == "") {
                    arg = arg.id(t.text);
                }
                arg = arg.value_name(t.text).action(ArgAction.Set);
            },
            "ellipsis" => {
                let action = arg.get_action();
                arg = match (action) {
                    ArgAction.Set => {
                        if (arg.get_long() == null && arg.get_short() == null) {
                            arg.num_args(ValueRange.from(1))
                                // Allow collecting arguments interleaved with flags
                                .action(ArgAction.Append)
                        } else {
                            arg.action(ArgAction.Append)
                        }
                    },
                    ArgAction.SetTrue | ArgAction.Help | ArgAction.Version => {
                        arg.action(ArgAction.Count)
                    },
                    _ => baml.sys.panic(`Unexpected action ${action}`),
                };
            },
            "help" => {
                arg = arg.help(t.text);
            },
            _ => baml.sys.panic(`arg!: unexpected token ${debug_str(t.text)} in ${debug_str(spec)}`),
        }
    }

    if (arg.get_id() == "") {
        baml.sys.panic("Without a value or long flag, the `name:` prefix is required");
    }
    arg
}

class ArgToken {
    kind: "name" | "colon" | "long" | "short" | "required_value" | "optional_value" | "ellipsis" | "help",
    text: string,
}

/// Tokenize the `arg!` usage syntax
function arg_tokens(spec: string) -> ArgToken[] {
    let chars = spec.chars();
    let out: ArgToken[] = [];
    let i = 0;
    let n = chars.length();

    let read_quoted = (start: int) -> string {
        let q = chars[start];
        let j = start + 1;
        let s = "";
        while (j < n && chars[j] != q) {
            if (chars[j] == "\\" && j + 1 < n) {
                j += 1;
            }
            s = s + chars[j];
            j += 1;
        }
        s
    };
    let quoted_len = (start: int) -> int {
        let q = chars[start];
        let j = start + 1;
        while (j < n && chars[j] != q) {
            if (chars[j] == "\\") { j += 1; }
            j += 1;
        }
        j - start + 1
    };
    let is_word = (c: string) -> bool { c.is_alphanumeric() || c == "_" || c == "-" };

    while (i < n) {
        let c = chars[i];
        if (c == " " || c == "\t" || c == "\n") {
            i += 1;
        } else if (c == "\"" || c == "'") {
            let text = read_quoted(i);
            i += quoted_len(i);
            if (i < n && chars[i] == ":") {
                out.push(ArgToken { kind: "name", text: text });
                out.push(ArgToken { kind: "colon", text: ":" });
                i += 1;
            } else {
                out.push(ArgToken { kind: "help", text: text });
            }
        } else if (c == "." && i + 2 < n && chars[i + 1] == "." && chars[i + 2] == ".") {
            out.push(ArgToken { kind: "ellipsis", text: "..." });
            i += 3;
        } else if (c == "<" || c == "[") {
            let close = if (c == "<") { ">" } else { "]" };
            let j = i + 1;
            let s = "";
            while (j < n && chars[j] != close) {
                if (chars[j] != "\"") { s = s + chars[j]; }
                j += 1;
            }
            out.push(ArgToken { kind: if (c == "<") { "required_value" } else { "optional_value" }, text: s.trim() });
            i = j + 1;
        } else if (c == "-") {
            let long = i + 1 < n && chars[i + 1] == "-";
            let j = if (long) { i + 2 } else { i + 1 };
            let s = "";
            if (j < n && (chars[j] == "\"" || chars[j] == "'")) {
                s = read_quoted(j);
                j += quoted_len(j);
            } else if (!long) {
                s = chars[j];
                j += 1;
            } else {
                while (j < n && is_word(chars[j])) {
                    s = s + chars[j];
                    j += 1;
                }
            }
            out.push(ArgToken { kind: if (long) { "long" } else { "short" }, text: s });
            i = j;
        } else {
            let j = i;
            let s = "";
            while (j < n && is_word(chars[j])) {
                s = s + chars[j];
                j += 1;
            }
            if (s.is_empty()) {
                baml.sys.panic(`arg!: unexpected character ${debug_str(c)} in ${debug_str(spec)}`);
            }
            if (j < n && chars[j] == ":") {
                out.push(ArgToken { kind: "name", text: s });
                out.push(ArgToken { kind: "colon", text: ":" });
                j += 1;
            } else {
                baml.sys.panic(`arg!: unexpected identifier ${debug_str(s)} in ${debug_str(spec)}`);
            }
            i = j;
        }
    }
    out
}

testset "macros" {
    test "arg_short_long_value_help" {
        let a = arg("-c --config <FILE> \"Sets a custom config file\"");
        assert.equal(a.get_id(), "config");
        assert.equal(a.get_short(), "c");
        assert.equal(a.get_long(), "config");
        assert.equal(a.get_value_names(), ["FILE"]);
        assert.equal(a.get_help()?.to_string(), "Sets a custom config file")
    }
    test "arg_positional_required" {
        let a = arg("<REMOTE> \"The remote to clone\"");
        assert.equal(a.get_id(), "REMOTE");
        assert.is_true(a.is_required_set());
        assert.equal(a.get_action(), ArgAction.Set)
    }
    test "arg_named_optional" {
        let a = arg("base: [COMMIT]");
        assert.equal(a.get_id(), "base");
        assert.is_true(!a.is_required_set());
        assert.equal(a.get_value_names(), ["COMMIT"])
    }
    test "arg_count" {
        let a = arg("-d --debug ... \"Turn debugging information on\"");
        assert.equal(a.get_action(), ArgAction.Count)
    }
    test "arg_positional_multiple" {
        let a = arg("<PATH> ... \"Stuff to add\"");
        assert.equal(a.get_action(), ArgAction.Append);
        let b = arg("<PATH>... \"Stuff to add\"");
        assert.equal(b.get_action(), ArgAction.Append)
    }
    test "arg_optional_option_value" {
        let a = arg("--color [WHEN]");
        assert.equal(a.get_num_args(), ValueRange.inclusive(0, 1))
    }
}
