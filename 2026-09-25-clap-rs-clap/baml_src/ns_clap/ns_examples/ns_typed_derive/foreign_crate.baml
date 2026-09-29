// Port of clap/examples/typed-derive/foreign_crate.rs

enum LogLevel {
    Trace,
    Debug,
    Info,
    Warn,
    Error,
}

/// `impl std::fmt::Display for LogLevel`
function log_level_to_string(l: LogLevel) -> string {
    match (l) {
        LogLevel.Trace => "trace",
        LogLevel.Debug => "debug",
        LogLevel.Info => "info",
        LogLevel.Warn => "warn",
        LogLevel.Error => "error",
    }
}

/// `impl std::str::FromStr for LogLevel`
function log_level_from_str(s: string) -> LogLevel throws string {
    match (s) {
        "trace" => LogLevel.Trace,
        "debug" => LogLevel.Debug,
        "info" => LogLevel.Info,
        "warn" => LogLevel.Warn,
        "error" => LogLevel.Error,
        _ => throw `Unknown log level: ${s}`,
    }
}
