// Port of anstyle/src/style.rs

/// ANSI Text styling
///
/// Rust's `Style` is `Copy`, so every builder method here returns a new value
/// instead of mutating the receiver.
class Style {
    _fg: Color?,
    _bg: Color?,
    _underline: Color?,
    _effects: Effects,

    /// No effects enabled
    function new() -> Style { Style { _fg: null, _bg: null, _underline: null, _effects: Effects.new() } }

    /// Set foreground color
    function fg_color(self, fg: Color?) -> Style { Style { ...self, _fg: fg } }

    /// Set background color
    function bg_color(self, bg: Color?) -> Style { Style { ...self, _bg: bg } }

    /// Set underline color
    function underline_color(self, underline: Color?) -> Style { Style { ...self, _underline: underline } }

    /// Set text effects
    function effects(self, effects: Effects) -> Style { Style { ...self, _effects: effects } }

    /// Render the ANSI code
    function render(self) -> string {
        let out = self._effects.render();
        if let fg: Color = self._fg { out = out + render_fg(fg); }
        if let bg: Color = self._bg { out = out + render_bg(bg); }
        if let ul: Color = self._underline { out = out + render_underline(ul); }
        out
    }

    /// Renders the relevant `Reset` code
    ///
    /// Unlike `Reset.render`, this will elide the code if there is nothing to reset.
    function render_reset(self) -> string {
        if (self.is_plain()) { "" } else { reset_str() }
    }

    function bold(self) -> Style { self.effects(self._effects.insert(Effects.BOLD())) }
    function dimmed(self) -> Style { self.effects(self._effects.insert(Effects.DIMMED())) }
    function italic(self) -> Style { self.effects(self._effects.insert(Effects.ITALIC())) }
    function underline(self) -> Style { self.effects(self._effects.insert(Effects.UNDERLINE())) }
    function blink(self) -> Style { self.effects(self._effects.insert(Effects.BLINK())) }
    function invert(self) -> Style { self.effects(self._effects.insert(Effects.INVERT())) }
    function hidden(self) -> Style { self.effects(self._effects.insert(Effects.HIDDEN())) }
    function strikethrough(self) -> Style { self.effects(self._effects.insert(Effects.STRIKETHROUGH())) }

    function get_fg_color(self) -> Color? { self._fg }
    function get_bg_color(self) -> Color? { self._bg }
    function get_underline_color(self) -> Color? { self._underline }
    function get_effects(self) -> Effects { self._effects }

    /// Check if no styling is enabled
    function is_plain(self) -> bool {
        self._fg == null && self._bg == null && self._underline == null && self._effects.is_plain()
    }

    /// `impl BitOr<Effects> for Style`
    function or(self, rhs: Effects) -> Style { self.effects(self._effects.insert(rhs)) }

    /// `impl Sub<Effects> for Style`
    function sub(self, rhs: Effects) -> Style { self.effects(self._effects.remove(rhs)) }
}

/// `impl From<Effects> for Style`
function style_from_effects(effects: Effects) -> Style { Style.new().effects(effects) }
