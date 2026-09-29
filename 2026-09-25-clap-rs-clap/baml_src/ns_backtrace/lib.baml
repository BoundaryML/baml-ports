// Port of backtrace-0.3 (the subset used by clap_builder)
//
// `clap_builder` only uses `backtrace::Backtrace::new()` and its `Debug`
// rendering, behind the `debug` feature, to attach a backtrace to `Error`s.
//
// BAML exposes stack traces only on caught errors (`baml.errors.StackTrace`),
// not on demand, so a `Backtrace` records the frames of a stack trace handed to
// it, if any.

/// Representation of an owned and self-contained backtrace.
class Backtrace {
    _frames: string[],

    /// Captures a backtrace at the callsite of this function, returning an owned representation.
    function new() -> Backtrace { Backtrace { _frames: [] } }

    /// Build from a BAML stack trace captured by a `catch (e, ctx)` handler.
    function from_frames(frames: string[]) -> Backtrace { Backtrace { _frames: frames } }

    /// Returns the frames from when this backtrace was captured.
    function frames(self) -> string[] { self._frames }

    /// `impl Debug for Backtrace`
    function debug(self) -> string {
        let lines: string[] = ["stack backtrace:"];
        for (let i in baml.iter.Range.new(0, self._frames.length())) {
            lines.push(`  ${i}: ${self._frames[i]}`);
        }
        lines.join("\n")
    }
}
