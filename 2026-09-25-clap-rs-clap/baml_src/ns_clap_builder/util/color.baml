// Port of clap_builder/src/util/color.rs

/// Represents the color preferences for program output
enum ColorChoice {
    /// Enables colored output only when the output is going to a terminal or TTY.
    ///
    /// **NOTE:** This is the default behavior of `clap`.
    Auto,
    /// Enables colored output regardless of whether or not the output is going to a terminal/TTY.
    Always,
    /// Disables colored output no matter if the output is going to a terminal/TTY, or not.
    Never,
}

/// Report all `possible_values`
function color_choice_possible_values() -> PossibleValue[] {
    color_choice_value_variants().map((v) -> { color_choice_to_possible_value(v) })
}

/// `impl ValueEnum for ColorChoice`
function color_choice_value_variants() -> ColorChoice[] {
    [ColorChoice.Auto, ColorChoice.Always, ColorChoice.Never]
}

function color_choice_to_possible_value(c: ColorChoice) -> PossibleValue {
    match (c) {
        ColorChoice.Auto => PossibleValue.new("auto"),
        ColorChoice.Always => PossibleValue.new("always"),
        ColorChoice.Never => PossibleValue.new("never"),
    }
}

/// `impl Display for ColorChoice`
function color_choice_to_string(c: ColorChoice) -> string {
    color_choice_to_possible_value(c).get_name()
}

/// `impl FromStr for ColorChoice`
function color_choice_from_str(s: string) -> ColorChoice throws string {
    for (let variant in color_choice_value_variants()) {
        if (color_choice_to_possible_value(variant).matches(s, false)) {
            return variant;
        }
    }
    throw `invalid variant: ${s}`
}
