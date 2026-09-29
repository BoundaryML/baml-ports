// Port of anstyle/src/color.rs

/// Any ANSI color code scheme
///
/// Rust: `enum Color { Ansi(AnsiColor), Ansi256(Ansi256Color), Rgb(RgbColor) }`
type Color = AnsiColor | Ansi256Color | RgbColor

/// Create a `Style` with this as the foreground and `background` as the background
function color_on(fg: Color, background: Color) -> Style {
    Style.new().fg_color(fg).bg_color(background)
}

/// Create a `Style` with this as the foreground
function on_default(fg: Color) -> Style {
    Style.new().fg_color(fg)
}

/// Render the ANSI code for a foreground color
function render_fg(c: Color) -> string {
    match (c) {
        let a: AnsiColor => ansi_as_fg_str(a),
        let x: Ansi256Color => x.render_fg(),
        let r: RgbColor => r.render_fg(),
    }
}

/// Render the ANSI code for a background color
function render_bg(c: Color) -> string {
    match (c) {
        let a: AnsiColor => ansi_as_bg_str(a),
        let x: Ansi256Color => x.render_bg(),
        let r: RgbColor => r.render_bg(),
    }
}

function render_underline(c: Color) -> string {
    match (c) {
        let a: AnsiColor => Ansi256Color.from_ansi(a).render_underline(),
        let x: Ansi256Color => x.render_underline(),
        let r: RgbColor => r.render_underline(),
    }
}

/// Available 4-bit ANSI color palette codes
///
/// The user's terminal defines the meaning of the each palette code.
enum AnsiColor {
    Black,
    Red,
    Green,
    Yellow,
    Blue,
    Magenta,
    Cyan,
    White,
    BrightBlack,
    BrightRed,
    BrightGreen,
    BrightYellow,
    BrightBlue,
    BrightMagenta,
    BrightCyan,
    BrightWhite,
}

function ansi_index(c: AnsiColor) -> int {
    match (c) {
        AnsiColor.Black => 0,
        AnsiColor.Red => 1,
        AnsiColor.Green => 2,
        AnsiColor.Yellow => 3,
        AnsiColor.Blue => 4,
        AnsiColor.Magenta => 5,
        AnsiColor.Cyan => 6,
        AnsiColor.White => 7,
        AnsiColor.BrightBlack => 8,
        AnsiColor.BrightRed => 9,
        AnsiColor.BrightGreen => 10,
        AnsiColor.BrightYellow => 11,
        AnsiColor.BrightBlue => 12,
        AnsiColor.BrightMagenta => 13,
        AnsiColor.BrightCyan => 14,
        AnsiColor.BrightWhite => 15,
    }
}

function ansi_from_index(i: int) -> AnsiColor? {
    match (i) {
        0 => AnsiColor.Black,
        1 => AnsiColor.Red,
        2 => AnsiColor.Green,
        3 => AnsiColor.Yellow,
        4 => AnsiColor.Blue,
        5 => AnsiColor.Magenta,
        6 => AnsiColor.Cyan,
        7 => AnsiColor.White,
        8 => AnsiColor.BrightBlack,
        9 => AnsiColor.BrightRed,
        10 => AnsiColor.BrightGreen,
        11 => AnsiColor.BrightYellow,
        12 => AnsiColor.BrightBlue,
        13 => AnsiColor.BrightMagenta,
        14 => AnsiColor.BrightCyan,
        15 => AnsiColor.BrightWhite,
        _ => null,
    }
}

function ansi_as_fg_str(c: AnsiColor) -> string {
    let i = ansi_index(c);
    if (i < 8) { escape(["3", `${i}`]) } else { escape(["9", `${i - 8}`]) }
}

function ansi_as_bg_str(c: AnsiColor) -> string {
    let i = ansi_index(c);
    if (i < 8) { escape(["4", `${i}`]) } else { escape(["10", `${i - 8}`]) }
}

/// Change the color to/from bright
function ansi_bright(c: AnsiColor, yes: bool) -> AnsiColor {
    let i = ansi_index(c);
    let j = if (yes) { if (i < 8) { i + 8 } else { i } } else { if (i >= 8) { i - 8 } else { i } };
    ansi_from_index(j) ?? c
}

/// Report whether the color is bright
function ansi_is_bright(c: AnsiColor) -> bool { ansi_index(c) >= 8 }

/// 256 (8-bit) color support
///
/// - `0..16` are `AnsiColor` palette codes
/// - `0..232` map to `RgbColor` color values
/// - `232..` map to `RgbColor` gray-scale values
class Ansi256Color {
    index: int,

    function new(index: int) -> Ansi256Color { Ansi256Color { index: index } }

    function on(self, background: Color) -> Style { color_on(self, background) }
    function on_default(self) -> Style { on_default(self) }

    /// Convert to `AnsiColor` when there is a 1:1 mapping
    function into_ansi(self) -> AnsiColor? { ansi_from_index(self.index) }

    /// Losslessly convert from `AnsiColor`
    function from_ansi(color: AnsiColor) -> Ansi256Color { Ansi256Color { index: ansi_index(color) } }

    function render_fg(self) -> string { `${esc()}[38;5;${self.index}m` }
    function render_bg(self) -> string { `${esc()}[48;5;${self.index}m` }
    function render_underline(self) -> string { `${esc()}[58;5;${self.index}m` }
}

/// 24-bit ANSI RGB color codes
class RgbColor {
    r: int,
    g: int,
    b: int,

    function new(r: int, g: int, b: int) -> RgbColor { RgbColor { r: r, g: g, b: b } }

    function on(self, background: Color) -> Style { color_on(self, background) }
    function on_default(self) -> Style { on_default(self) }

    function render_fg(self) -> string { `${esc()}[38;2;${self.r};${self.g};${self.b}m` }
    function render_bg(self) -> string { `${esc()}[48;2;${self.r};${self.g};${self.b}m` }
    function render_underline(self) -> string { `${esc()}[58;2;${self.r};${self.g};${self.b}m` }
}
