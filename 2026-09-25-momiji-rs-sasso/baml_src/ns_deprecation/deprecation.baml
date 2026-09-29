// Ported from sasso `src/deprecation.rs` (namespace `root.deprecation`).
//
// The deprecation-warning registry.
//
// Each deprecation dart-sass 1.100 fires has a stable `[id]` tag, an optional
// `More info` URL line, and a (possibly multi-line, possibly dynamic) message
// body. This module models the ids the evaluator emits and renders the header
// block (everything above the snippet), byte-for-byte from the captured
// fixtures in `tests/fixtures/diagnostics/deprecation-*`.
//
// The snippet + 4-space-indented stack trace are appended by the evaluator
// (it owns the source/url/glyph context); this module only produces the
// `DEPRECATION WARNING [id]: …` header and any `More info` lines.

/// A single deprecation occurrence: its id tag, the message body (which may be
/// several lines and carry dynamic content), and the optional `More info` line.
class Deprecation {
    /// The `[id]` tag printed in the header.
    id: string,
    /// The message body, printed right after `DEPRECATION WARNING [id]: `. May
    /// contain embedded newlines for multi-line messages.
    message: string,
    /// The text of the trailing line, e.g.
    /// `More info and automated migrator: https://sass-lang.com/d/import` or
    /// `call-string`'s `Recommendation: …`, or `None` for the ids dart-sass
    /// prints without one.
    more_info: string?,
    /// The `@import` deprecation — a fully static message.
    function import() -> Deprecation {
        Deprecation {
            id: "import",
            message: "Sass @import rules are deprecated and will be removed in Dart Sass 3.0.0.",
            more_info: "More info and automated migrator: https://sass-lang.com/d/import",
        }
    }

    /// The `global-builtin` deprecation: a global function that has a
    /// `sass:*` module equivalent. `replacement` is the member dart names
    /// (`map.get`, `color.adjust`, `math.is-unitless`), and the info line is
    /// the migrator's — dart prints the `@import` URL here, not one of its own.
    function global_builtin(replacement: string) -> Deprecation {
        Deprecation {
            id: "global-builtin",
            message: `Global built-in functions are deprecated and will be removed in Dart Sass 3.0.0.\nUse ${replacement} instead.`,
            more_info: "More info and automated migrator: https://sass-lang.com/d/import",
        }
    }

    /// The `feature-exists` deprecation: the function itself is going away, in
    /// its global spelling and as `meta.feature-exists` alike.
    function feature_exists() -> Deprecation {
        Deprecation {
            id: "feature-exists",
            message: "The feature-exists() function is deprecated.",
            more_info: "More info: https://sass-lang.com/d/feature-exists",
        }
    }

    /// The `call-string` deprecation: `call("name")` looks a function up by
    /// name instead of taking a reference. The trailing line is a
    /// `Recommendation:` rather than a `More info:`, in the same slot.
    function call_string(name: string) -> Deprecation {
        Deprecation {
            id: "call-string",
            message: "Passing a string to call() is deprecated and will be illegal in Dart Sass 2.0.0.",
            // The name is a STRING in the suggested code, so it is serialized
            // as one — dart writes `call(get-function('a\\"b'))` for a name
            // that holds a quote.
            more_info: `Recommendation: call(get-function(${root.value.serialize_quoted(name)}))`,
        }
    }

    /// The `color-functions` deprecation: a legacy `sass:color` member that
    /// Color 4 replaced. `qualified` is the name dart prints — `red()` for the
    /// global spelling, `color.red()` for one reached through the module — and
    /// `suggestions` is the replacement code, one line each, computed from the
    /// call's own arguments. dart labels one "Suggestion" and several
    /// "Suggestions".
    function color_functions(qualified: string, suggestions: string[]) -> Deprecation {
        let label = if (suggestions.length() == 1) {
            "Suggestion"
        } else {
            "Suggestions"
        };
        Deprecation {
            id: "color-functions",
            message: `${qualified}() is deprecated. ${label}:\n\n${suggestions.join("\n")}`,
            more_info: "More info: https://sass-lang.com/d/color-functions",
        }
    }

    /// The `color-module-compat` deprecation for a `sass:color` member reached
    /// in its plain-CSS *filter* sense: `color.grayscale(1)` is going away as a
    /// way to write `filter: grayscale(1)`. `number` is the argument as Sass
    /// writes it and `filter` the plain-CSS call dart recommends instead —
    /// which is also the value the call returns, so both come from
    /// `plain_filter_text`.
    ///
    /// The GLOBAL spelling carries no deprecation at all: `grayscale(1)` IS the
    /// CSS filter there, and warning about it was #122.
    ///
    /// ⚠ dart's `opacity` message is missing the closing parenthesis after the
    /// number — `Passing a number (1 to color.opacity()` — where `grayscale`
    /// and `invert` have it (its string constant starts at `" to "`). That is
    /// not a transcription slip here: sass-spec locks the typo
    /// (`spec/core_functions/modules/color/css_overloads.hrx`), so byte parity
    /// means reproducing it.
    function color_module_compat_number(
        member: string,
        number: string,
        filter: string,
    ) -> Deprecation {
        let close = if (member == "opacity") {
            ""
        } else {
            ")"
        };
        Deprecation {
            id: "color-module-compat",
            message: `Passing a number (${number}${close} to color.${member}() is deprecated.`,
            more_info: `Recommendation: ${filter}`,
        }
    }

    /// The same id for the other shape it has: `color.alpha()` used as the
    /// proprietary Microsoft filter (`color.alpha(opacity=20)`), in either of
    /// dart's two overloads. `filter` is the passed-through CSS call.
    function color_module_compat_ms_filter(filter: string) -> Deprecation {
        Deprecation {
            id: "color-module-compat",
            message: "Using color.alpha() for a Microsoft filter is deprecated.",
            more_info: `Recommendation: ${filter}`,
        }
    }

    /// The `bogus-combinators` deprecation for a selector dart-sass drops:
    /// a repeated combinator run (`a > + b`) or a leading one outside a
    /// relative context. The rule is omitted from the CSS, and this warning is
    /// the only sign that it was — sasso dropped these silently until now
    /// (#119), which on Lichess's tree was 45 rules vanishing with no notice.
    ///
    /// `selector` is the RESOLVED selector, parents included, because that is
    /// what dart names: `.tview2 .inaccuracy > + lines`, not the `.#{$name} >
    /// + lines` that produced it.
    ///
    /// dart's other `bogus-combinators` message — a TRAILING combinator on a
    /// rule that has declarations of its own ("is only valid for nesting and
    /// shouldn't have children other than style rules") — carries a second
    /// span labelling the offending child, which this renderer has no way to
    /// produce yet. Trailing combinators stay silent for now.
    function bogus_combinators(selector: string) -> Deprecation {
        Deprecation {
            id: "bogus-combinators",
            message: `The selector "${selector}" is invalid CSS. It will be omitted from the generated CSS.\nThis will be an error in Dart Sass 2.0.0.`,
            more_info: "More info: https://sass-lang.com/d/bogus-combinators",
        }
    }

    /// The `if-function` deprecation: the legacy `if($c, $t, $f)` in favour of
    /// the modern CSS `if()`. `suggestion` is the rewritten call, present only
    /// when the arguments are the three positional ones the rewrite needs —
    /// dart omits the line entirely for a named, splatted or wrong-arity call
    /// and still deprecates it.
    function if_function(suggestion: string?) -> Deprecation {
        let message = "The Sass if() syntax is deprecated in favor of the modern CSS syntax.";
        if (suggestion != null) {
            let s = suggestion;
            message = message + "\n\nSuggestion: ";
            message = message + s;
        }
        Deprecation {
            id: "if-function",
            message: message,
            more_info: "More info: https://sass-lang.com/d/if-function",
        }
    }

    /// Render the header block: `DEPRECATION WARNING [id]: <message>` followed
    /// by a blank line and the `More info` line (when present), then a blank
    /// line and the top snippet-gutter is left to the caller. Returns the lines
    /// from the header down to (and including) the blank line that precedes the
    /// snippet — i.e. everything before the `  ,` gutter row.
    function render_header(self) -> string {
        let out = `DEPRECATION WARNING [${self.id}]: ${self.message}\n`;
        if let info: string = self.more_info {
            out = out + "\n";
            out = out + info;
            out = out + "\n";
        }
        out = out + "\n";
        out
    }
}
