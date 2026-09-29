// Port of clap_builder/src/parser/matches/value_source.rs

/// Origin of the argument's value
enum ValueSource {
    /// Value came [`Arg::default_value`][crate::Arg::default_value]
    DefaultValue,
    /// Value came [`Arg::env`][crate::Arg::env]
    EnvVariable,
    /// Value was passed in on the command-line
    CommandLine,
}

function value_source_rank(s: ValueSource) -> int {
    match (s) {
        ValueSource.DefaultValue => 0,
        ValueSource.EnvVariable => 1,
        ValueSource.CommandLine => 2,
    }
}

function value_source_is_explicit(s: ValueSource) -> bool {
    s != ValueSource.DefaultValue
}

/// `Ord::max` for `ValueSource`
function value_source_max(a: ValueSource, b: ValueSource) -> ValueSource {
    if (value_source_rank(a) >= value_source_rank(b)) { a } else { b }
}

/// `Option<ValueSource>` ordering (`None` < `Some(_)`)
function value_source_opt_gt(a: ValueSource?, b: ValueSource?) -> bool {
    let ra = if let x: ValueSource = a { value_source_rank(x) } else { -1 };
    let rb = if let x: ValueSource = b { value_source_rank(x) } else { -1 };
    ra > rb
}
