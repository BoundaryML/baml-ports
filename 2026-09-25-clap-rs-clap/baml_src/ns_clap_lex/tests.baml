// Port of clap_lex-1.1.0/tests/testsuite/{lexer,parsed,shorts}.rs

testset "clap_lex" {
    test "insert" {
        let raw = RawArgs.new(["bin", "a", "b", "c"]);
        let cursor = raw.cursor();
        assert.equal(raw.next_os(cursor), "bin");
        assert.equal(raw.next_os(cursor), "a");
        raw.insert(cursor, ["1", "2", "3"]);
        assert.equal(raw.next_os(cursor), "1");
        assert.equal(raw.next_os(cursor), "2");
        assert.equal(raw.next_os(cursor), "3");
        assert.equal(raw.next_os(cursor), "b");
        assert.equal(raw.next_os(cursor), "c");
        let cursor2 = raw.cursor();
        let rest = raw.remaining(cursor2);
        assert.equal(rest, ["bin", "a", "1", "2", "3", "b", "c"])
    }
    test "seek" {
        let raw = RawArgs.new(["bin", "a", "b"]);
        let cursor = raw.cursor();
        raw.seek(cursor, SeekFromEnd { pos: -1 });
        assert.equal(raw.next_os(cursor), "b");
        raw.seek(cursor, SeekFromStart { pos: 0 });
        assert.equal(raw.next_os(cursor), "bin");
        raw.seek(cursor, SeekFromCurrent { pos: 1 });
        assert.equal(raw.next_os(cursor), "b");
        assert.is_true(raw.is_end(cursor))
    }
    test "to_long_no_escape" {
        let next = ParsedArg.new("--");
        assert.is_true(next.is_escape());
        assert.is_true(!next.is_long());
        assert.equal(next.to_long(), null)
    }
    test "to_long_no_value" {
        let next = ParsedArg.new("--long");
        assert.is_true(next.is_long());
        let long = next.to_long();
        assert.equal(long?.flag, "long");
        assert.equal(long?.value, null)
    }
    test "to_long_with_empty_value" {
        let long = ParsedArg.new("--long=").to_long();
        assert.equal(long?.flag, "long");
        assert.equal(long?.value, "")
    }
    test "to_long_with_value" {
        let long = ParsedArg.new("--long=hello").to_long();
        assert.equal(long?.flag, "long");
        assert.equal(long?.value, "hello")
    }
    test "to_short_stdio" {
        let next = ParsedArg.new("-");
        assert.is_true(next.is_stdio());
        assert.is_true(!next.is_short());
        assert.equal(next.to_short(), null)
    }
    test "to_short_escape" {
        let next = ParsedArg.new("--");
        assert.is_true(!next.is_short());
        assert.equal(next.to_short(), null)
    }
    test "to_short_long" {
        let next = ParsedArg.new("--long");
        assert.is_true(!next.is_short());
        assert.equal(next.to_short(), null)
    }
    test "to_short" {
        let next = ParsedArg.new("-short");
        assert.is_true(next.is_short());
        let shorts = next.to_short();
        let collected: string[] = [];
        if let s: ShortFlags = shorts {
            while let c: string = s.next_flag() { collected.push(c); }
        }
        assert.equal(collected, ["s", "h", "o", "r", "t"])
    }
    test "is_negative_number" {
        for (let s in ["-10.0", "-1", "-100", "-3.5", "-1e10", "-1.3e10", "-1E10"]) {
            assert.is_true(ParsedArg.new(s).is_negative_number());
        }
        for (let s in ["-10.0.0", "-1e", "--", "-a", "-1a", "1"]) {
            assert.is_true(!ParsedArg.new(s).is_negative_number());
        }
    }
    test "is_positional" {
        let next = ParsedArg.new("hello");
        assert.is_true(!next.is_long());
        assert.is_true(!next.is_short());
        assert.is_true(!next.is_stdio());
        assert.is_true(!next.is_escape())
    }
    test "next_value_os" {
        let s = ParsedArg.new("-short").to_short();
        if let shorts: ShortFlags = s {
            assert.equal(shorts.next_flag(), "s");
            assert.equal(shorts.next_value_os(), "hort");
            assert.equal(shorts.next_value_os(), null);
            assert.is_true(shorts.is_empty())
        } else {
            assert.is_true(false)
        }
    }
    test "advance_by" {
        let s = ParsedArg.new("-abc").to_short();
        if let shorts: ShortFlags = s {
            assert.equal(shorts.advance_by(2), null);
            assert.equal(shorts.next_flag(), "c");
            assert.equal(shorts.advance_by(2), 0)
        } else {
            assert.is_true(false)
        }
    }
    test "short_negative_number" {
        let s = ParsedArg.new("-12").to_short();
        assert.is_true(s?.is_negative_number() ?? false)
    }
}
