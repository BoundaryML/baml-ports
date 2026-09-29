// Port of clap/examples/typed-derive/implicit.rs
//
// Rust picks each parser implicitly from the field type (`FromStr`,
// `ValueEnum`, `ValueParserFactory`). The BAML derive reflects on built-in
// types and enums the same way, but cannot call a static `from_str` on an
// arbitrary class, so class-typed fields name their parser explicitly.

class ImplicitParsers {
    kind: "implicit",

    /// Implicitly using `std::str::FromStr`
    /// #[arg(short = 'O')]
    optimization: int?,

    /// Allow invalid UTF-8 paths
    /// #[arg(short = 'I', value_name = "DIR", value_hint = clap::ValueHint::DirPath)]
    include: root.clap.PathBuf?,

    /// Handle IP addresses
    /// #[arg(long, value_parser = ip_addr_from_str)]
    bind: IpAddr?,

    /// Allow human-readable durations
    /// #[arg(long, value_parser = signed_duration_from_str)]
    sleep: root.jiff.SignedDuration?,

    /// Custom enums
    /// #[arg(long)]
    bump_level: BumpLevel?,

    function debug(self) -> string {
        let include = if let p: string = self.include { root.clap.debug_str(p) } else { null };
        let bind = if let b: IpAddr = self.bind { b.to_string() } else { null };
        let sleep = if let s: root.jiff.SignedDuration = self.sleep { s.to_string() } else { null };
        let bump = if let b: BumpLevel = self.bump_level { `${b}` } else { null };
        let opt = if let o: int = self.optimization { `${o}` } else { null };
        `ImplicitParsers { optimization: ${debug_opt(opt)}, include: ${debug_opt(include)}, bind: ${debug_opt(bind)}, sleep: ${debug_opt(sleep)}, bump_level: ${debug_opt(bump)} }`
    }
}

/// #[value(rename_all = "kebab-case")]
enum BumpLevel {
    /// Increase the major version (x.0.0)
    Major,
    /// Increase the minor version (x.y.0)
    Minor,
    /// Increase the patch version (x.y.z)
    Patch,
}

/// `impl std::fmt::Display for BumpLevel`
function bump_level_to_string(b: BumpLevel) -> string {
    root.clap_derive.value_enum_variants<BumpLevel>()
        .find((v) -> { v.value == b })?.possible_value?.get_name() ?? baml.sys.panic("no values are skipped")
}

/// `impl std::str::FromStr for BumpLevel`
function bump_level_from_str(s: string) -> BumpLevel throws string {
    for (let variant in root.clap_derive.value_enum_variants<BumpLevel>()) {
        if (variant.possible_value.matches(s, false)) {
            match (variant.value) {
                let b: BumpLevel => { return b; },
                _ => {},
            }
        }
    }
    throw `Invalid variant: ${s}`
}

/// `std::net::IpAddr`
class IpAddr {
    text: string,

    implements baml.ToString {
        function to_string(self) -> string throws never { self.text }
    }
}

/// `<std::net::IpAddr as FromStr>::from_str`
function ip_addr_from_str(s: string) -> IpAddr throws string {
    if (is_ipv4(s) || is_ipv6(s)) {
        IpAddr { text: s }
    } else {
        throw "invalid IP address syntax"
    }
}

function is_ipv4(s: string) -> bool {
    let parts = s.split(".");
    parts.length() == 4 && parts.every((p) -> {
        !p.is_empty() && p.length() <= 3 && p.is_ascii_numeric() && (p == "0" || !p.starts_with("0")) && ((baml.Int.parse(p) catch_all (e) { _ => 999 }) <= 255)
    })
}

function is_ipv6(s: string) -> bool {
    if (!s.includes(":")) {
        return false;
    }
    let halves = s.split("::");
    if (halves.length() > 2) {
        return false;
    }
    let groups = halves.flat_map((h) -> { if (h.is_empty()) { [] } else { h.split(":") } });
    let valid = groups.every((g) -> { !g.is_empty() && g.length() <= 4 && g.is_ascii_hex() });
    valid && (if (halves.length() == 2) { groups.length() < 8 } else { groups.length() == 8 })
}

/// `<jiff::SignedDuration as FromStr>::from_str`
function signed_duration_from_str(s: string) -> root.jiff.SignedDuration throws string {
    root.jiff.SignedDuration.parse(s) catch (e) {
        let err: root.jiff.Error => throw err.message,
    }
}
