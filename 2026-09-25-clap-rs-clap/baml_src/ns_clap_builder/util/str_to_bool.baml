// Port of clap_builder/src/util/str_to_bool.rs

/// True values are `y`, `yes`, `t`, `true`, `on`, and `1`.
function TRUE_LITERALS() -> string[] { ["y", "yes", "t", "true", "on", "1"] }

/// False values are `n`, `no`, `f`, `false`, `off`, and `0`.
function FALSE_LITERALS() -> string[] { ["n", "no", "f", "false", "off", "0"] }

/// Converts a string literal representation of truth to true or false.
///
/// `false` values are `n`, `no`, `f`, `false`, `off`, and `0` (case insensitive).
///
/// Any other value will be considered as `true`.
function str_to_bool(val: string) -> bool? {
    let pat = val.to_lower_case();
    if (TRUE_LITERALS().includes(pat)) {
        true
    } else if (FALSE_LITERALS().includes(pat)) {
        false
    } else {
        null
    }
}
