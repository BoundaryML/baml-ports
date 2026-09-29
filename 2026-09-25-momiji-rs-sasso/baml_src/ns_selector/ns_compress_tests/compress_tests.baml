// Ported from sasso `src/selector/mod.rs` `#[cfg(test)] mod compress_tests`
// (namespace `root.selector.compress_tests`; `use super::{compress_selector,
// escape_end}` → `root.selector.compress_selector` / `root.selector.escape_end`).

test "an_escape_is_one_token" {
    // `\` plus up to six hex digits plus the one whitespace that closes
    // them; anything else is `\` plus exactly one character.
    let chars = (s: string) -> string[] {
        s.chars()
    };
    assert.equal(root.selector.escape_end(chars("\\31 a"), 0), 4); // digits + terminator
    assert.equal(root.selector.escape_end(chars("\\31a"), 0), 4); // three hex digits
    assert.equal(root.selector.escape_end(chars("\\100000 x"), 0), 8); // six, then the space
    assert.equal(root.selector.escape_end(chars("\\1000000"), 0), 7); // seven digits: six taken
    assert.equal(root.selector.escape_end(chars("\\,b"), 0), 2); // not hex: one character
    assert.equal(root.selector.escape_end(chars("\\ b"), 0), 2); // an escaped space
    assert.equal(root.selector.escape_end(chars("\\"), 0), 1); // nothing follows
    assert.equal(root.selector.escape_end(chars("\\31\r\nx"), 0), 5) // CRLF is one terminator
}

test "only_structural_whitespace_goes" {
    let c = (s: string) -> string {
        root.selector.compress_selector(s)
    };
    assert.equal(c(".a > .b"), ".a>.b");
    assert.equal(c(".a  >  .b"), ".a>.b");
    assert.equal(c(".a .b"), ".a .b");
    assert.equal(c(":has(+ .b)"), ":has(+.b)");
    assert.equal(c(":not(.b, .c)"), ":not(.b,.c)");
    assert.equal(c(":lang(en, fr)"), ":lang(en, fr)");
    assert.equal(c(".\\31  > .b"), ".\\31 >.b");
    assert.equal(c(":not(.\\31 , .b)"), ":not(.\\31 ,.b)");
    assert.equal(c("[a=\"x > y\"]"), "[a=\"x > y\"]");
    // A selector with nothing to compress is borrowed, not rebuilt.
    // PORT: `compress_selector` returns a plain `string` (no `Cow`), so there is
    // no borrowed/owned distinction to observe; what the port does on that
    // early-return path is hand back the input unchanged.
    assert.equal(root.selector.compress_selector(".a .b"), ".a .b")
}
