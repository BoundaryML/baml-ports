// Ported from sasso `src/localtime/sys.rs` (namespace `root.localtime.sys`).
//
// The only file here that touches the outside world, and the only one with
// a platform `cfg`. Everything else is bytes in, numbers out.
//
// Keeping the I/O in one small file is what makes the rest testable from
// vendored fixtures, and what makes adding a platform a one-file change.

/// Where the local offset comes from.
interface Source {}

/// A fixed zero offset, with no file to read.
class Source_Utc {
    implements Source {}
}

/// A TZif file to parse.
class Source_File {
    _0: string,
    implements Source {}
}

/// Resolve a `TZ` value to a source, exactly as the platform does.
///
/// Measured on 2026-09-19 against both `date` and dart-sass 1.104.1, which
/// agree because both go through libc:
///
/// ```text
/// unset          local time     -> /etc/localtime
/// TZ=            UTC            -> an EMPTY TZ is a request for UTC,
/// TZ=:           UTC               not a request for the default
/// TZ=UTC         UTC
/// TZ=Asia/Taipei that zone
/// TZ=nonsense    UTC            -> an unresolvable zone falls back to UTC,
///                                  not back to local time
/// ```
///
/// The empty case is the one worth stating twice, because the obvious
/// reading is wrong and the first version of this file got it wrong: `TZ=`
/// is not "TZ is unset". A process launched with `TZ=` is asking for UTC,
/// and we reported the host's local zone — with a test that codified it.
///
/// Split from the read so it can be tested without mutating the process
/// environment, which this crate's `unsafe_code = "deny"` would refuse
/// anyway (`set_var` is `unsafe` in the 2024 edition). Taking the value as
/// a parameter is the better shape regardless: the interesting logic is
/// the mapping, not the getenv.
///
/// `TZ` can also hold a POSIX rule directly (`EST5EDT,M3.2.0,M11.1.0`).
/// That form has no file behind it, so it resolves as unresolvable, i.e.
/// to UTC — which is what an unreadable zone gets from libc too. Reading
/// the rule properly is [`super::posix`]'s job already and would be a
/// small change; it is not this PR's.
function tz_source(tz: string?) -> Source {
    if (tz == null) {
        return Source_File { _0: "/etc/localtime" };
    }
    let name = root.std.strip_prefix(tz, ":") ?? tz;
    if (name == "") {
        return Source_Utc {  };
    }
    if (name.starts_with("/")) {
        return Source_File { _0: name };
    }
    // Refuse anything that could climb out of the zoneinfo directory. `TZ`
    // is an environment variable, and a build tool should not read an
    // arbitrary file because one was set. An unusable name is UTC, the
    // same answer libc gives for a zone it cannot find.
    if (
        name.split("/").some((c) -> {
            c == "" || c == "." || c == ".."
        })
    ) {
        return Source_Utc {  };
    }
    Source_File { _0: root.std.path_join("/usr/share/zoneinfo", name) }
}

/// What the machine has to offer.
///
/// `#[cfg(unix)]` along with the only function that builds one: on a
/// platform with no tz database there is nothing to distinguish, and a
/// three-variant enum where two are unreachable is dead code the build
/// rightly refuses (`-D warnings` caught exactly that on the first
/// Windows run after this type appeared).
interface Loaded {}

/// A fixed zero offset.
class Loaded_Utc {
    implements Loaded {}
}

/// TZif bytes to parse.
class Loaded_Tzif {
    _0: uint8array,
    implements Loaded {}
}

/// Nothing: no zone can be determined, so the caller reports no time
/// rather than a wrong one.
class Loaded_Nothing {
    implements Loaded {}
}

function load() -> Loaded {
    match (tz_source(root.std.env_var("TZ"))) {
        Source_Utc {} => Loaded_Utc {  },
        Source_File { _0: let path } => {
            let bytes = root.std.read_bytes(path) catch (e) {
                let _err: baml.errors.Io => {
                    // A NAMED zone that will not open is UTC, as it is for libc.
                    // An unset `TZ` whose `/etc/localtime` is missing is a
                    // different case — a scratch container or a nix build sandbox,
                    // where nothing has told us anything — and there this reports
                    // no time at all rather than asserting UTC it has not been
                    // told. Absent beats confidently wrong.
                    // PORT: `std::env::var_os("TZ").is_some()` → `env_var("TZ") != null`.
                    if (root.std.env_var("TZ") != null) {
                        return Loaded_Utc {  };
                    }
                    return Loaded_Nothing {  };
                }
            };
            Loaded_Tzif { _0: bytes }
        },
        _ => root.std.unreachable(),
    }
}
