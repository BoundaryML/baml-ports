// Port of clap_builder/src/builder/styled_str.rs

/// Terminal-styling container
///
/// Styling may be encoded as [ANSI Escape Code](https://en.wikipedia.org/wiki/ANSI_escape_code)
///
/// # Examples
///
/// ```baml
/// // `cstr!` converts tags to ANSI codes
/// let after_help = StyledStr.from(`${style.render()}Examples${style.render_reset()}...`);
/// let cmd = Command.new("mybin").after_help(after_help);
/// ```
class StyledStr {
    _0: string,

    /// Create an empty buffer
    function new() -> StyledStr { StyledStr { _0: "" } }

    /// `impl From<String> for StyledStr`
    function from(s: string) -> StyledStr { StyledStr { _0: s } }

    /// Display using [ANSI Escape Code](https://en.wikipedia.org/wiki/ANSI_escape_code) styling
    function ansi(self) -> string { self._0 }

    /// May allow the compiler to consolidate the `Drop`s for `msg`, reducing code size compared to
    /// `styled.push_str(&msg)`
    function push_string(self, msg: string) -> void { self._0 = self._0 + msg; }

    /// Appends a given string slice onto the end of this `StyledStr`.
    function push_str(self, msg: string) -> void { self._0 = self._0 + msg; }

    /// `write!(styled, "{}{}{}", style.render(), msg, style.render_reset())`
    function push_styled_str(self, style: root.anstyle.Style, msg: string) -> void {
        self._0 = self._0 + style.render() + msg + style.render_reset();
    }

    function trim_start_lines(self) -> void {
        if let pos: int = self._0.index_of("\n") {
            let leading = self._0.slice(0, pos + 1);
            if (leading.trim().is_empty()) {
                self._0 = self._0.slice(pos + 1, self._0.length());
            }
        }
    }

    function trim_end(self) -> void { self._0 = self._0.trim_end(); }

    function replace_newline_var(self) -> void {
        self._0 = self._0.replace_all("{n}", "\n");
    }

    function indent(self, initial: string, trailing: string) -> void {
        self._0 = initial + self._0;
        self._0 = self._0.replace_all("\n", "\n" + trailing);
    }

    /// `#[cfg(feature = "wrap_help")] fn wrap`; without the feature this is a no-op.
    function wrap(self, hard_width: int) -> void {
        if (!features().wrap_help) {
            return;
        }
        // Styling escapes are zero-width for the wrapper: wrap the text and
        // re-insert escapes at the same printable offsets.
        let wrapper = LineWrapper.new(hard_width);
        let segments = split_ansi(self._0);
        let out: string[] = [];
        for (let seg in segments) {
            if (seg.is_escape) {
                out.push(seg.text);
                continue;
            }
            let lines = split_inclusive(seg.text, "\n");
            for (let i in baml.iter.Range.new(0, lines.length())) {
                if (0 < i) {
                    // reset char count on newline, skipping the start as we might have carried
                    // over from a prior block of styled text
                    wrapper.reset();
                }
                let words = find_words_ascii_space(lines[i]);
                out.push(wrapper.wrap(words).join(""));
            }
        }
        self._0 = out.join("").trim_end();
    }

    function display_width(self) -> int {
        display_width(root.anstream.strip_str(self._0))
    }

    function is_empty(self) -> bool { self._0.is_empty() }

    function as_styled_str(self) -> string { self._0 }

    /// The printable text, with styling stripped (`iter_text().collect()`)
    function iter_text(self) -> string {
        if (features().color) { root.anstream.strip_str(self._0) } else { self._0 }
    }

    function push_styled(self, other: StyledStr) -> void { self._0 = self._0 + other._0; }

    /// `impl Clone for StyledStr`
    function clone(self) -> StyledStr { StyledStr { _0: self._0 } }

    /// `impl Display for StyledStr` (prints with styling stripped)
    implements baml.ToString {
        function to_string(self) -> string throws never { self.iter_text() }
    }
}

/// `IntoResettable<StyledStr>` for `&str`, `String`, `StyledStr`, `None`
function into_styled_opt(v: StyledStr | string | null) -> StyledStr? {
    match (v) {
        null => null,
        let s: string => StyledStr.from(s),
        let st: StyledStr => st,
    }
}

function into_styled(v: StyledStr | string) -> StyledStr {
    match (v) {
        let s: string => StyledStr.from(s),
        let st: StyledStr => st,
    }
}

/// A run of text that is either an ANSI escape or plain text
class AnsiSegment {
    text: string,
    is_escape: bool,
}

/// Split into escape and text runs (`iter_text` with position tracking)
function split_ansi(s: string) -> AnsiSegment[] {
    let out: AnsiSegment[] = [];
    let cps = s.to_code_points();
    let i = 0;
    let buf: int[] = [];
    while (i < cps.length()) {
        if (cps[i] == 27) {
            if (buf.length() > 0) {
                out.push(AnsiSegment { text: from_cps(buf), is_escape: false });
                buf = [];
            }
            let start = i;
            i += 1;
            if (i < cps.length() && cps[i] == 0x5b) {
                i += 1;
                while (i < cps.length() && !(cps[i] >= 0x40 && cps[i] <= 0x7e)) { i += 1; }
                i += 1;
            } else {
                i += 1;
            }
            let end = if (i < cps.length()) { i } else { cps.length() };
            out.push(AnsiSegment { text: from_cps(cps.slice(start, end)), is_escape: true });
        } else {
            buf.push(cps[i]);
            i += 1;
        }
    }
    if (buf.length() > 0) {
        out.push(AnsiSegment { text: from_cps(buf), is_escape: false });
    }
    out
}

function from_cps(cps: int[]) -> string {
    baml.String.from_code_points(cps) catch_all (e) { _ => "" }
}

/// `str::split_inclusive`
function split_inclusive(s: string, sep: string) -> string[] {
    let parts = s.split(sep);
    let out: string[] = [];
    for (let i in baml.iter.Range.new(0, parts.length())) {
        if (i < parts.length() - 1) {
            out.push(parts[i] + sep);
        } else if (!parts[i].is_empty()) {
            out.push(parts[i]);
        }
    }
    out
}
