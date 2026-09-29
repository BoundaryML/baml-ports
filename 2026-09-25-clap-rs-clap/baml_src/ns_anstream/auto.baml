// Port of anstream-1.0.0/src/auto.rs

/// Which OS stream an `AutoStream` writes to (`std::io::Stdout` / `std::io::Stderr`)
enum RawStream {
    Stdout,
    Stderr,
}

enum StreamInner {
    PassThrough,
    Strip,
}

/// [`std::io::Write`] that adapts ANSI escape codes to the underlying `Write`s capabilities
///
/// This includes
/// - Stripping colors for non-terminals
/// - Respecting env variables like [NO_COLOR](https://no-color.org/) or [CLICOLOR](https://bixense.com/clicolors/)
class AutoStream {
    _raw: RawStream,
    _inner: StreamInner,

    /// Runtime control over styling behavior
    function new(raw: RawStream, choice: root.colorchoice.ColorChoice) -> AutoStream {
        match (choice) {
            root.colorchoice.ColorChoice.Auto => AutoStream.auto(raw),
            root.colorchoice.ColorChoice.AlwaysAnsi => AutoStream.always_ansi(raw),
            root.colorchoice.ColorChoice.Always => AutoStream.always(raw),
            root.colorchoice.ColorChoice.Never => AutoStream.never(raw),
        }
    }

    /// Auto-adapt for the stream's capabilities
    function auto(raw: RawStream) -> AutoStream {
        let c = choice(raw);
        AutoStream.new(raw, c)
    }

    /// Report the desired choice for the given stream
    function choice(raw: RawStream) -> root.colorchoice.ColorChoice { choice(raw) }

    /// Force ANSI escape codes to be passed through as-is, no matter what the inner `Write`
    /// supports.
    function always_ansi(raw: RawStream) -> AutoStream {
        AutoStream { _raw: raw, _inner: StreamInner.PassThrough }
    }

    /// Force color, no matter what the inner `Write` supports.
    function always(raw: RawStream) -> AutoStream { AutoStream.always_ansi(raw) }

    /// Only pass printable data to the inner `Write`.
    function never(raw: RawStream) -> AutoStream {
        AutoStream { _raw: raw, _inner: StreamInner.Strip }
    }

    /// Returns `true` if the descriptor/handle refers to a terminal/tty.
    function is_terminal(self) -> bool { is_terminal(self._raw) }

    /// Prefer [`AutoStream::choice`]
    ///
    /// This doesn't report what is requested but what is currently active.
    function current_choice(self) -> root.colorchoice.ColorChoice {
        match (self._inner) {
            StreamInner.PassThrough => root.colorchoice.ColorChoice.AlwaysAnsi,
            StreamInner.Strip => root.colorchoice.ColorChoice.Never,
        }
    }

    /// `impl std::io::Write for AutoStream`
    function write_str(self, s: string) -> void {
        let data = match (self._inner) {
            StreamInner.PassThrough => s,
            StreamInner.Strip => root.anstream.strip_str(s),
        };
        match (self._raw) {
            RawStream.Stdout => baml.io.print(data),
            RawStream.Stderr => baml.io.eprint(data),
        }
    }

    function flush(self) -> void {}
}

function choice(raw: RawStream) -> root.colorchoice.ColorChoice {
    let c = root.colorchoice.global();
    match (c) {
        root.colorchoice.ColorChoice.Auto => {
            let clicolor = root.anstyle_query.clicolor();
            let clicolor_enabled = clicolor ?? false;
            let clicolor_disabled = !(clicolor ?? true);
            if (root.anstyle_query.no_color()) {
                root.colorchoice.ColorChoice.Never
            } else if (root.anstyle_query.clicolor_force()) {
                root.colorchoice.ColorChoice.Always
            } else if (clicolor_disabled) {
                root.colorchoice.ColorChoice.Never
            } else if (is_terminal(raw)
                && (root.anstyle_query.term_supports_color()
                    || clicolor_enabled
                    || root.anstyle_query.is_ci())) {
                root.colorchoice.ColorChoice.Always
            } else {
                root.colorchoice.ColorChoice.Never
            }
        },
        _ => c,
    }
}

/// `std::io::IsTerminal`
///
/// BAML cannot query whether its own stdout/stderr is a tty, so the stream is
/// assumed not to be one (the conservative choice: styling is stripped unless
/// forced via `CLICOLOR_FORCE` or `ColorChoice::Always`). Set
/// `BAML_IS_TERMINAL=1` to declare the streams as terminals.
function is_terminal(raw: RawStream) -> bool {
    root.anstyle_query.non_empty(root.anstyle_query.env_var("BAML_IS_TERMINAL"))
}
