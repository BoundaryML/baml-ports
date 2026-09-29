// Port of clap/examples/typed-derive/builtin.rs
//
// Rust writes the parsers inline with closures
// (`PossibleValuesParser::new([...]).map(|s| ...)`); BAML attributes cannot
// contain closures, so they are named functions.

class BuiltInParsers {
    kind: "builtin",

    /// Support for discrete numbers
    /// #[arg(
    ///     long,
    ///     default_value_t = 22,
    ///     value_parser = port_parser,
    /// )]
    port: int,

    /// Support enums from a foreign crate that don't implement `ValueEnum`
    /// #[arg(
    ///     long,
    ///     default_value_t = foreign_crate::LogLevel::Info,
    ///     value_parser = log_level_parser,
    /// )]
    log_level: LogLevel,

    function debug(self) -> string {
        `BuiltInParsers { port: ${self.port}, log_level: ${self.log_level} }`
    }
}

/// `clap::builder::PossibleValuesParser::new(["22", "80"]).map(|s| s.parse::<usize>().unwrap())`
function port_parser() -> root.clap.TypedValueParser {
    root.clap.PossibleValuesParser.new(["22", "80"])
        .map((s) -> { baml.Int.parse(`${s}`) catch_all (e) { _ => baml.sys.panic("unwrap") } })
}

/// `clap::builder::PossibleValuesParser::new(["trace", ...]).map(|s| s.parse::<foreign_crate::LogLevel>().unwrap())`
function log_level_parser() -> root.clap.TypedValueParser {
    root.clap.PossibleValuesParser.new(["trace", "debug", "info", "warn", "error"])
        .map((s) -> { log_level_from_str(`${s}`) catch_all (e) { _ => baml.sys.panic("unwrap") } })
}
