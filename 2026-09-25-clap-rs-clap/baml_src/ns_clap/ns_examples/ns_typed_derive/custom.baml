// Port of clap/examples/typed-derive/custom.rs

class CustomParser {
    kind: "custom",

    // Rust selects `TargetVersionParser` through `impl ValueParserFactory for TargetVersion`.

    /// Hand-implement `TypedValueParser`
    /// #[arg(long, value_parser = target_version_parser)]
    target_version: TargetVersion?,

    function debug(self) -> string {
        let tv = if let t: TargetVersion = self.target_version { target_version_debug(t) } else { null };
        `CustomParser { target_version: ${debug_opt(tv)} }`
    }
}

/// Enum or custom value
///
/// Rust: `enum TargetVersion { Relative(BumpLevel), Absolute(semver::Version) }`
type TargetVersion = BumpLevel | root.semver.Version

function target_version_debug(t: TargetVersion) -> string {
    match (t) {
        let b: BumpLevel => `Relative(${b})`,
        let v: root.semver.Version => `Absolute(${v.debug()})`,
    }
}

/// `impl std::fmt::Display for TargetVersion`
function target_version_to_string(t: TargetVersion) -> string {
    match (t) {
        let b: BumpLevel => bump_level_to_string(b),
        let v: root.semver.Version => `${v}`,
    }
}

/// `impl std::str::FromStr for TargetVersion`
function target_version_from_str(s: string) -> TargetVersion throws string {
    let bump = bump_level_from_str(s) catch_all (e) { _ => null };
    if let b: BumpLevel = bump {
        b
    } else {
        root.semver.Version.parse(s) catch (e) {
            let err: root.semver.Error => throw err.message,
        }
    }
}

/// Default to `TargetVersionParser` for `TargetVersion`, instead of `FromStr`
function target_version_parser() -> root.clap.TypedValueParser {
    TargetVersionParser {}
}

class TargetVersionParser {
    implements root.clap_builder.TypedValueParser {
        function parse_ref(self, cmd: root.clap.Command, arg: root.clap.Arg?, value: string) -> unknown throws root.clap.Error {
            let inner_parser = root.clap.FnValueParser.new<TargetVersion>((s) -> { target_version_from_str(s) });
            inner_parser.parse_ref(cmd, arg, value)
        }

        function type_id(self) -> root.clap_builder.AnyValueId {
            root.clap_builder.AnyValueId.of<TargetVersion>()
        }

        function possible_values(self) -> root.clap.PossibleValue[]? {
            let inner_parser = root.clap.EnumValueParser.new<BumpLevel>();
            inner_parser.possible_values()
        }
    }
}
