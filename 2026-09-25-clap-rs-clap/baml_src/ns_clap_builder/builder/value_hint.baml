// Port of clap_builder/src/builder/value_hint.rs

/// Provide shell with hint on how to complete an argument.
///
/// See [`Arg::value_hint`][crate::Arg::value_hint] to set this on an argument.
///
/// See the `clap_complete` crate for completion script generation.
///
/// Overview of which hints are supported by which shell:
///
/// | Hint                   | zsh | fish[^1] | dynamic |
/// | ---------------------- | --- | ---------|---------|
/// | `AnyPath`              | Yes | Yes      | Yes     |
/// | `FilePath`             | Yes | Yes      | Yes     |
/// | `DirPath`              | Yes | Yes      | Yes     |
/// | `ExecutablePath`       | Yes | Partial  | Yes     |
/// | `CommandName`          | Yes | Yes      | No      |
/// | `CommandString`        | Yes | Partial  | No      |
/// | `CommandWithArguments` | Yes |          | No      |
/// | `Username`             | Yes | Yes      | No      |
/// | `Hostname`             | Yes | Yes      | No      |
/// | `Url`                  | Yes |          | No      |
/// | `EmailAddress`         | Yes |          | No      |
enum ValueHint {
    /// Default value if hint is not specified. Follows shell default behavior, which is usually
    /// auto-completing filenames.
    Unknown,
    /// None of the hints below apply. Disables shell completion for this argument.
    Other,
    /// Any existing path.
    AnyPath,
    /// Path to a file.
    FilePath,
    /// Path to a directory.
    DirPath,
    /// Path to an executable file.
    ExecutablePath,
    /// Name of a command, without arguments. May be relative to PATH, or full path to executable.
    CommandName,
    /// A single string containing a command and its arguments.
    CommandString,
    /// Capture the remaining arguments as a command name and arguments for that command. This is
    /// common when writing shell wrappers that execute anther command, for example `sudo` or `env`.
    CommandWithArguments,
    /// Name of a local operating system user.
    Username,
    /// Host name of a computer.
    /// Shells usually parse `/etc/hosts` and `.ssh/known_hosts` to complete hostnames.
    Hostname,
    /// Complete web address.
    Url,
    /// Email address.
    EmailAddress,
}

/// `impl FromStr for ValueHint`
function value_hint_from_str(s: string) -> ValueHint throws string {
    match (s.to_lower_case()) {
        "unknown" => ValueHint.Unknown,
        "other" => ValueHint.Other,
        "anypath" => ValueHint.AnyPath,
        "filepath" => ValueHint.FilePath,
        "dirpath" => ValueHint.DirPath,
        "executablepath" => ValueHint.ExecutablePath,
        "commandname" => ValueHint.CommandName,
        "commandstring" => ValueHint.CommandString,
        "commandwitharguments" => ValueHint.CommandWithArguments,
        "username" => ValueHint.Username,
        "hostname" => ValueHint.Hostname,
        "url" => ValueHint.Url,
        "emailaddress" => ValueHint.EmailAddress,
        _ => throw `unknown ValueHint: \`${s}\``,
    }
}
