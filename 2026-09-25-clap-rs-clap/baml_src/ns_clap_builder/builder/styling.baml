// Port of clap_builder/src/builder/styling.rs
//
// Terminal [`Styles`] for help and error output
//
// `pub use anstyle::*;` -- the anstyle types live in `root.anstyle` and are
// aliased here for `clap::builder::styling::*` parity.

type Style = root.anstyle.Style
type Color = root.anstyle.Color
type AnsiColor = root.anstyle.AnsiColor
type Ansi256Color = root.anstyle.Ansi256Color
type RgbColor = root.anstyle.RgbColor
type Effects = root.anstyle.Effects
type Reset = root.anstyle.Reset

/// Terminal styling definitions
///
/// See also [`Command::styles`][crate::Command::styles].
///
/// # Example
///
/// clap v3 styling
/// ```baml
/// let styles = Styles.styled()
///     .header(root.anstyle.AnsiColor.Yellow.on_default())
///     .usage(root.anstyle.AnsiColor.Green.on_default())
///     .literal(root.anstyle.AnsiColor.Green.on_default())
///     .placeholder(root.anstyle.AnsiColor.Green.on_default());
/// ```
class Styles {
    _header: Style,
    _error: Style,
    _usage: Style,
    _literal: Style,
    _placeholder: Style,
    _valid: Style,
    _invalid: Style,
    _context: Style,
    _context_value: Style?,

    /// No terminal styling
    function plain() -> Styles {
        Styles {
            _header: Style.new(),
            _error: Style.new(),
            _usage: Style.new(),
            _literal: Style.new(),
            _placeholder: Style.new(),
            _valid: Style.new(),
            _invalid: Style.new(),
            _context: Style.new(),
            _context_value: null,
        }
    }

    /// Default terminal styling
    function styled() -> Styles {
        if (!features().color) {
            return Styles.plain();
        }
        Styles {
            _header: Style.new().bold().underline(),
            _error: Style.new().fg_color(root.anstyle.AnsiColor.Red).bold(),
            _usage: Style.new().bold().underline(),
            _literal: Style.new().bold(),
            _placeholder: Style.new(),
            _valid: Style.new().fg_color(root.anstyle.AnsiColor.Green),
            _invalid: Style.new().fg_color(root.anstyle.AnsiColor.Yellow),
            _context: Style.new(),
            _context_value: null,
        }
    }

    /// General Heading style, e.g. [`help_heading`][crate::Arg::help_heading]
    function header(self, style: Style) -> Styles { Styles { ...self, _header: style } }

    /// Error heading
    function error(self, style: Style) -> Styles { Styles { ...self, _error: style } }

    /// Usage heading
    function usage(self, style: Style) -> Styles { Styles { ...self, _usage: style } }

    /// Literal command-line syntax, e.g. `--help`
    function literal(self, style: Style) -> Styles { Styles { ...self, _literal: style } }

    /// Descriptions within command-line syntax, e.g. [`value_name`][crate::Arg::value_name]
    function placeholder(self, style: Style) -> Styles { Styles { ...self, _placeholder: style } }

    /// Highlight suggested usage
    function valid(self, style: Style) -> Styles { Styles { ...self, _valid: style } }

    /// Highlight invalid usage
    function invalid(self, style: Style) -> Styles { Styles { ...self, _invalid: style } }

    /// Highlight all specified contexts, e.g. `[default: false]`
    ///
    /// To specialize the style of the value within the context, see [`Styles::context_value`]
    function context(self, style: Style) -> Styles { Styles { ...self, _context: style } }

    /// Highlight values within all of the context, e.g. the `false` in `[default: false]`
    ///
    /// If not explicitly set, falls back to `context`'s style.
    function context_value(self, style: Style) -> Styles { Styles { ...self, _context_value: style } }

    function get_header(self) -> Style { self._header }
    function get_error(self) -> Style { self._error }
    function get_usage(self) -> Style { self._usage }
    function get_literal(self) -> Style { self._literal }
    function get_placeholder(self) -> Style { self._placeholder }
    function get_valid(self) -> Style { self._valid }
    function get_invalid(self) -> Style { self._invalid }
    function get_context(self) -> Style { self._context }

    /// Highlight values within all of the context, e.g. the `false` in `[default: false]`
    ///
    /// If not explicitly set, falls back to `context`'s style.
    function get_context_value(self) -> Style { self._context_value ?? self._context }
}

/// `impl Default for Styles`
function default_styles() -> Styles { Styles.styled() }
