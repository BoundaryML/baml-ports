// Port of goldmark text/reader_test.go.

test "TestFindSubMatchReader" {
    let s = "微笑";
    let r = new_reader((":" + s + ":").to_utf8(), new_decoder([]));
    let reg = baml.regex.new(":(\\p{L}+):");
    let m = r.find_sub_match(reg);
    assert.not_null(m);
    let mm = m ?? [];
    assert.equal(mm.length(), 2);
    assert.equal(mm[1].to_string(), s);
}
