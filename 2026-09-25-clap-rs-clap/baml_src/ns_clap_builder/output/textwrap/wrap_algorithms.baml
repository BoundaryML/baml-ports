// Port of clap_builder/src/output/textwrap/wrap_algorithms.rs

class LineWrapper {
    _hard_width: int,
    _line_width: int,
    _indentation: string?,

    function new(hard_width: int) -> LineWrapper {
        LineWrapper { _hard_width: hard_width, _line_width: 0, _indentation: null }
    }

    function reset(self) -> void {
        self._line_width = 0;
        self._indentation = null;
    }

    function wrap(self, words_in: string[]) -> string[] {
        let words = words_in.slice(0, words_in.length());
        let first_word = false;
        if (self._indentation == null) {
            first_word = true;
            if let word: string = words.at(0) {
                if (word.trim().is_empty()) {
                    self._indentation = word;
                } else {
                    self._indentation = "";
                }
            }
        }

        let i = 0;
        while (i < words.length()) {
            let word = words[i];
            let trimmed = word.trim_end();
            let word_width = display_width(trimmed);
            let trimmed_delta = word.length() - trimmed.length();
            if (first_word && 0 < word_width) {
                // Never try to wrap the first word
                first_word = false;
            } else if (self._hard_width < self._line_width + word_width) {
                if (0 < i) {
                    let prev = i - 1;
                    words[prev] = words[prev].trim_end();
                }

                self._line_width = 0;
                words.insert("\n", i) catch_all (e) { _ => 0 };
                i += 1;
                if let indentation: string = self._indentation {
                    words.insert(indentation, i) catch_all (e) { _ => 0 };
                    self._line_width += indentation.length();
                    i += 1;
                }
            }
            self._line_width += word_width + trimmed_delta;

            i += 1;
        }
        words
    }
}

testset "wrap_algorithms" {
    test "no_wrap" {
        let w = LineWrapper.new(20);
        assert.equal(w.wrap(["foo ", "bar"]).join(""), "foo bar")
    }
    test "wrap_long" {
        let w = LineWrapper.new(5);
        assert.equal(w.wrap(["foo ", "bar ", "baz"]).join(""), "foo\nbar\nbaz")
    }
}
