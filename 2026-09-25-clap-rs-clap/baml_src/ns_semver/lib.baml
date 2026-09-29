// Port of semver-1.x (the `Version` subset)
//
// Parser and evaluator for Cargo's flavor of Semantic Versioning. `semver` is
// a dev-dependency of `clap`, used by `examples/typed-derive/custom.rs`.
//
//   src/lib.rs      -> lib.baml    (Version, Prerelease, BuildMetadata)
//   src/parse.rs    -> parse.baml  (Version::parse)
//   src/error.rs    -> error.baml  (Error, Position)
//   src/display.rs  -> lib.baml    (`impl Display for Version`)

/// **SemVer version** as defined by <https://semver.org>.
class Version {
    major: int,
    minor: int,
    patch: int,
    pre: string,
    build: string,

    /// Create `Version` with an empty pre-release and build metadata.
    function new(major: int, minor: int, patch: int) -> Version {
        Version { major: major, minor: minor, patch: patch, pre: "", build: "" }
    }

    /// Create `Version` by parsing from string representation.
    ///
    /// # Errors
    ///
    /// Possible reasons for the parse to fail include:
    ///
    /// - `1.0` &mdash; too few numeric components. A SemVer version must have
    ///   exactly three. If you are looking at something that has fewer than
    ///   three numbers in it, it's possible it is a `VersionReq` instead (with
    ///   an implicit default `^` comparison operator).
    ///
    /// - `1.0.01` &mdash; a numeric component has a leading zero.
    ///
    /// - `1.0.unknown` &mdash; unexpected character in one of the components.
    ///
    /// - `1.0.0-` or `1.0.0+` &mdash; the pre-release or build metadata are
    ///   indicated present but empty.
    ///
    /// - `1.0.0-alpha_123` &mdash; pre-release or build metadata have something
    ///   outside the allowed characters, which are `0-9`, `A-Z`, `a-z`, `-`,
    ///   and `.` (dot).
    ///
    /// - `23456789999999999999.0.0` &mdash; overflow of a u64.
    function parse(text: string) -> Version throws Error {
        parse_version(text)
    }

    /// `impl Debug for Version`
    function debug(self) -> string {
        let out = `Version { major: ${self.major}, minor: ${self.minor}, patch: ${self.patch}`;
        if (!self.pre.is_empty()) {
            out = out + `, pre: Prerelease("${self.pre}")`;
        }
        if (!self.build.is_empty()) {
            out = out + `, build: BuildMetadata("${self.build}")`;
        }
        out + " }"
    }

    /// `impl Display for Version`
    implements baml.ToString {
        function to_string(self) -> string throws never {
            let out = `${self.major}.${self.minor}.${self.patch}`;
            if (!self.pre.is_empty()) {
                out = out + "-" + self.pre;
            }
            if (!self.build.is_empty()) {
                out = out + "+" + self.build;
            }
            out
        }
    }
}
