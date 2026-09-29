// Port of clap_builder/src/output/textwrap/mod.rs
//
// Fork of `textwrap` crate
//
// Benefits of forking:
// - Pull in only what we need rather than relying on the compiler to remove what we don't need
// - `LineWrapper` is able to incrementally wrap which will help with `StyledStr`
//
//   pub(crate) mod core;             -> core.baml
//   pub(crate) mod word_separators;  -> word_separators.baml
//   pub(crate) mod wrap_algorithms;  -> wrap_algorithms.baml

/// Wrap text (`#[cfg(feature = "wrap_help")]`); without the feature the text is returned as-is
function wrap(content: string, hard_width: int) -> string {
    if (!features().wrap_help) {
        return content;
    }
    let wrapper = LineWrapper.new(hard_width);
    let total: string[] = [];
    for (let line in split_inclusive(content, "\n")) {
        wrapper.reset();
        let words = find_words_ascii_space(line);
        for (let w in wrapper.wrap(words)) { total.push(w); }
    }
    total.join("")
}
