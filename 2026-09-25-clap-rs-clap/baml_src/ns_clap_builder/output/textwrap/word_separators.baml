// Port of clap_builder/src/output/textwrap/word_separators.rs

/// Split on ASCII spaces, keeping each run of trailing spaces with its word
function find_words_ascii_space(line: string) -> string[] {
    let words: string[] = [];
    let chars = line.chars();
    let start = 0;
    let in_whitespace = false;
    for (let idx in baml.iter.Range.new(0, chars.length())) {
        let next_whitespace = chars[idx] == " ";
        if (in_whitespace && !next_whitespace) {
            words.push(chars.slice(start, idx).join(""));
            start = idx;
        }
        in_whitespace = next_whitespace;
    }

    if (start < chars.length()) {
        words.push(chars.slice(start, chars.length()).join(""));
    }

    words
}

testset "word_separators" {
    test "ascii_multiple_words" {
        assert.equal(find_words_ascii_space("foo bar"), ["foo ", "bar"])
    }
    test "ascii_only_whitespace" {
        assert.equal(find_words_ascii_space("  "), ["  "])
    }
    test "ascii_inter_word_whitespace" {
        assert.equal(find_words_ascii_space("foo   bar"), ["foo   ", "bar"])
    }
    test "ascii_trailing_whitespace" {
        assert.equal(find_words_ascii_space("foo   "), ["foo   "])
    }
    test "ascii_leading_whitespace" {
        assert.equal(find_words_ascii_space("   foo"), ["   ", "foo"])
    }
    test "ascii_multi_column_char" {
        assert.equal(find_words_ascii_space("🤠"), ["🤠"])
    }
}
