// Port of clap_builder/src/output/textwrap/core.rs

/// Compute the display width of `text`
///
/// # Examples
///
/// **Note:** When the `unicode` Cargo feature is disabled, all characters are presumed to take up
/// 1 width.  With the feature enabled, function will correctly deal with [emoji] and other
/// characters outside the Latin script.
///
/// This function ignores [ANSI escape sequences] (terminated by `m`).
function display_width(text: string) -> int {
    let width = 0;

    let control_sequence = false;
    let control_terminate = "m";

    for (let ch in text.chars()) {
        if (ch.is_ascii_control()) {
            control_sequence = true;
        } else if (control_sequence && ch == control_terminate) {
            control_sequence = false;
            continue;
        }

        if (!control_sequence) {
            width += ch_width(ch);
        }
    }
    width
}

/// `#[cfg(feature = "unicode")]` uses `unicode_width`; otherwise every character is 1 wide
function ch_width(ch: string) -> int {
    if (features().unicode) {
        root.unicode_width.char_width(ch) ?? 0
    } else {
        1
    }
}

testset "textwrap_core" {
    test "display_width_works" {
        assert.equal(display_width("Café Plain"), 10)
    }
    test "display_width_ansi" {
        let esc = baml.String.from_code_points([27]);
        assert.equal(display_width(`${esc}[1mbold${esc}[0m`), 4)
    }
}
