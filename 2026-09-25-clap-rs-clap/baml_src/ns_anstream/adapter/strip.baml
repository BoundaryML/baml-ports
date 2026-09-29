// Port of anstream-1.0.0/src/adapter/strip.rs
//
// The Rust implementation drives the `anstyle-parse` VTE state machine over
// bytes. This port runs an equivalent (reduced) state machine over code points:
// it recognizes ESC sequences, CSI sequences, and OSC/DCS/SOS/PM/APC strings,
// and keeps printable text plus ASCII whitespace control characters.

enum StripState {
    Ground,
    Escape,
    EscapeIntermediate,
    CsiEntry,
    String,
    StringEscape,
}

/// Strip ANSI escapes from a `&str`, returning the printable content
///
/// This can be used to take output from a program that includes escape sequences and write it
/// somewhere that does not easily support them, such as a log file.
function strip_str(data: string) -> string {
    let out: string[] = [];
    let state: StripState = StripState.Ground;
    for (let cp in data.to_code_points()) {
        match (state) {
            StripState.Ground => {
                if (cp == 0x1b) {
                    state = StripState.Escape;
                } else if (cp == 0x9b) {
                    state = StripState.CsiEntry;
                } else if (cp == 0x9d || cp == 0x90 || cp == 0x98 || cp == 0x9e || cp == 0x9f) {
                    state = StripState.String;
                } else if (is_printable(cp)) {
                    out.push(baml.String.from_code_points([cp]) catch_all (e) { _ => "" });
                }
            },
            StripState.Escape => {
                if (cp == 0x5b) {
                    // `[`
                    state = StripState.CsiEntry;
                } else if (cp == 0x5d || cp == 0x50 || cp == 0x58 || cp == 0x5e || cp == 0x5f) {
                    // `]` OSC, `P` DCS, `X` SOS, `^` PM, `_` APC
                    state = StripState.String;
                } else if (cp >= 0x20 && cp <= 0x2f) {
                    state = StripState.EscapeIntermediate;
                } else if (cp == 0x1b) {
                    state = StripState.Escape;
                } else {
                    state = StripState.Ground;
                }
            },
            StripState.EscapeIntermediate => {
                if (cp >= 0x30 && cp <= 0x7e) { state = StripState.Ground; }
            },
            StripState.CsiEntry => {
                if (cp >= 0x40 && cp <= 0x7e) {
                    state = StripState.Ground;
                } else if (cp == 0x1b) {
                    state = StripState.Escape;
                }
            },
            StripState.String => {
                if (cp == 0x07 || cp == 0x9c) {
                    state = StripState.Ground;
                } else if (cp == 0x1b) {
                    state = StripState.StringEscape;
                }
            },
            StripState.StringEscape => {
                // `ESC \` (ST) terminates, anything else re-enters escape handling
                if (cp == 0x5c) { state = StripState.Ground; } else { state = StripState.Escape; }
            },
        }
    }
    out.join("")
}

/// Incrementally strip non-contiguous data
class StripStr {
    _state: string,

    function new() -> StripStr { StripStr { _state: "" } }

    /// Strip the next segment of data
    ///
    /// Escape sequences that straddle segments are buffered until complete.
    function strip_next(self, data: string) -> string {
        let combined = self._state + data;
        let esc = baml.String.from_code_points([27]) catch_all (e) { _ => "" };
        // Hold back a trailing, unterminated escape sequence
        let idx = combined.last_index_of(esc);
        if let i: int = idx {
            let tail = combined.slice(i, combined.length());
            if (strip_str(tail + "m") == "" && strip_str(tail) == "" && !is_complete_escape(tail)) {
                self._state = tail;
                return strip_str(combined.slice(0, i));
            }
        }
        self._state = "";
        strip_str(combined)
    }
}

function is_complete_escape(s: string) -> bool {
    let cps = s.to_code_points();
    if (cps.length() < 2) { return false; }
    if (cps[1] == 0x5b) {
        let last = cps[cps.length() - 1];
        return cps.length() > 2 && last >= 0x40 && last <= 0x7e;
    }
    true
}

/// Is the code point printable (or ASCII whitespace)?
///
/// VT320 considered 0x7f to be `Print`able but we expect to be working in UTF-8 systems and not
/// ISO Latin-1, making it DEL and non-printable
function is_printable(cp: int) -> bool {
    if (cp == 0x09 || cp == 0x0a || cp == 0x0c || cp == 0x0d) {
        return true;
    }
    if (cp < 0x20 || cp == 0x7f) {
        return false;
    }
    if (cp >= 0x80 && cp < 0xa0) {
        return false;
    }
    true
}

testset "strip" {
    test "strip_str_basic" {
        let esc = baml.String.from_code_points([27]);
        assert.equal(strip_str(`${esc}[32mfoo${esc}[m bar`), "foo bar")
    }
    test "strip_osc" {
        let esc = baml.String.from_code_points([27]);
        assert.equal(strip_str(`a${esc}]8;;http://example.com${esc}\\link${esc}]8;;${esc}\\b`), "alinkb")
    }
    test "strip_keeps_whitespace" {
        assert.equal(strip_str("a\tb\nc"), "a\tb\nc")
    }
    test "strip_incremental" {
        let esc = baml.String.from_code_points([27]);
        let s = StripStr.new();
        let a = s.strip_next(`foo${esc}[3`);
        let b = s.strip_next(`2mbar`);
        assert.equal(a + b, "foobar")
    }
}
