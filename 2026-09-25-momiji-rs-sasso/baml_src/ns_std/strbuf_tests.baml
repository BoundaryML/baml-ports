// `StrBuf` must survive very long append sequences (a plain `s = s + x`
// rope overflows the VM's native stack when measured) and track char counts.

testset "strbuf" {
    test "many_appends" {
        let b = StrBuf.new();
        let i = 0;
        while (i < 200000) {
            b.push_str("ab");
            i += 1;
        }
        assert.equal(b.len(), 400000);
        assert.equal(b.as_str().length(), 400000);
        assert.is_true(b.ends_with("abab"))
    }

    test "edits" {
        let b = StrBuf.from("héllo");
        b.push("!");
        assert.equal(b.len(), 6);
        assert.equal(b.byte_len(), 7);
        assert.equal(b.pop(), "!");
        b.truncate(2);
        assert.equal(b.as_str(), "hé");
        b.insert_str(1, "XY");
        assert.equal(b.as_str(), "hXYé");
        assert.equal(b.remove(0), "h");
        assert.equal(b.take(), "XYé");
        assert.is_true(b.is_empty())
    }
}
