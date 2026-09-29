// Port of colorchoice-1.0.5/src/lib.rs
//
// Global override of color control. `colorchoice` is a dependency of `anstream`.

/// Selection for overriding color output
enum ColorChoice {
    /// Use colors if the output device appears to support them
    Auto,
    /// Like `Always`, except it never tries to use anything other than emitting ANSI
    /// color codes.
    AlwaysAnsi,
    /// Try very hard to emit colors.
    ///
    /// This includes emitting ANSI colors on Windows if the console API is unavailable.
    Always,
    /// Never emit colors.
    Never,
}

/// `ColorChoice::global()`: get the current `ColorChoice` state.
///
/// Rust keeps this in a `static AtomicUsize`. BAML has no process-global
/// mutable statics, so the global is read from the `BAML_COLORCHOICE`
/// environment variable (`auto`, `always-ansi`, `always`, `never`),
/// defaulting to `Auto`.
function global() -> ColorChoice {
    let v = (baml.env.get("BAML_COLORCHOICE") catch_all (e) { _ => null }) ?? "auto";
    to_choice(v) ?? ColorChoice.Auto
}

function from_choice(choice: ColorChoice) -> int {
    match (choice) {
        ColorChoice.Auto => 0,
        ColorChoice.AlwaysAnsi => 1,
        ColorChoice.Always => 2,
        ColorChoice.Never => 3,
    }
}

function to_choice(s: string) -> ColorChoice? {
    match (s) {
        "auto" | "0" => ColorChoice.Auto,
        "always-ansi" | "1" => ColorChoice.AlwaysAnsi,
        "always" | "2" => ColorChoice.Always,
        "never" | "3" => ColorChoice.Never,
        _ => null,
    }
}

test "colorchoice_serialization" {
    let expected = [ColorChoice.Auto, ColorChoice.AlwaysAnsi, ColorChoice.Always, ColorChoice.Never];
    let values = expected.map((c) -> { `${from_choice(c)}` });
    let actual = values.map((v) -> { to_choice(v) });
    assert.equal(actual, expected)
}
