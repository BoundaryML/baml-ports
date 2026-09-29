// Port of clap_builder/src/output/fmt.rs

enum Stream {
    Stdout,
    Stderr,
}

class Colorizer {
    _stream: Stream,
    _color_when: ColorChoice,
    _content: StyledStr,

    function new(stream: Stream, color_when: ColorChoice) -> Colorizer {
        Colorizer { _stream: stream, _color_when: color_when, _content: StyledStr.new() }
    }

    function with_content(self, content: StyledStr) -> Colorizer {
        self._content = content;
        self
    }

    /// Writes the content to the stream, adapting ANSI styling to the stream's
    /// capabilities through `anstream` (`#[cfg(feature = "color")]`), or writing
    /// it as-is otherwise.
    function print(self) -> void {
        if (features().color) {
            let color_when = match (self._color_when) {
                ColorChoice.Always => root.colorchoice.ColorChoice.Always,
                ColorChoice.Auto => root.colorchoice.ColorChoice.Auto,
                ColorChoice.Never => root.colorchoice.ColorChoice.Never,
            };

            let writer = match (self._stream) {
                Stream.Stderr => root.anstream.AutoStream.new(root.anstream.RawStream.Stderr, color_when),
                Stream.Stdout => root.anstream.AutoStream.new(root.anstream.RawStream.Stdout, color_when),
            };
            writer.write_str(self._content.ansi());
        } else {
            // [e]println can't be used here because it panics
            // if something went wrong. We don't want that.
            match (self._stream) {
                Stream.Stdout => baml.io.print(self._content.ansi()),
                Stream.Stderr => baml.io.eprint(self._content.ansi()),
            }
        }
    }

    /// Color-unaware printing. Never uses coloring.
    implements baml.ToString {
        function to_string(self) -> string throws never { self._content.to_string() }
    }
}
