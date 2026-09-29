// Ported from sasso `src/deprecation.rs` `#[cfg(test)] mod tests`
// (namespace `root.deprecation.tests`).

test "import_header_matches_fixture_prefix" {
    let d = root.deprecation.Deprecation.import();
    let expected = "DEPRECATION WARNING [import]: Sass @import rules are deprecated and will be removed in Dart Sass 3.0.0.

More info and automated migrator: https://sass-lang.com/d/import

";
    assert.equal(d.render_header(), expected)
}
