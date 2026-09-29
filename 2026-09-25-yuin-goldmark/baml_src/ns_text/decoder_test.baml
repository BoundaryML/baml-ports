// Port of goldmark text/decoder_test.go.

test "TestDecoder" {
    let s = "foo\\:\\) &amp;ab&#x3A; &#58;";
    let d = new_decoder([]);
    assert.equal(d.decode(s.to_utf8()).to_string(), "foo:) &ab: :");
}

class DecoderCase {
    name: string,
    input: string,
    want: string,
}

/// TestDecoderCursorInvalidation exercises Decode/DecodeTo's jump-based '&'/'\'
/// cursor tracking, where consuming one match can invalidate (and require
/// recomputing) the cached position of the other, or leave it untouched.
function decoder_cursor_invalidation_failures() -> string[] {
    let cases = [
        DecoderCase { name: "backslash escapes ampersand, entity not reprocessed", input: "\\&amp;", want: "&amp;" },
        DecoderCase { name: "failed entity immediately followed by real entity", input: "&&amp;", want: "&&" },
        DecoderCase { name: "backslash-escaped backslash leaves following entity intact", input: "\\\\&amp;", want: "\\&" },
        DecoderCase { name: "trailing lone backslash", input: "abc\\", want: "abc\\" },
        DecoderCase { name: "trailing bare ampersand", input: "abc&", want: "abc&" },
        DecoderCase { name: "hex entity followed immediately by escape", input: "&#x26;\\*", want: "&*" },
        DecoderCase { name: "consecutive entities", input: "&amp;&amp;&amp;", want: "&&&" },
        DecoderCase { name: "ampersand immediately followed by backslash escape", input: "&*\\*", want: "&**" },
        DecoderCase { name: "decimal entity then bare ampersand", input: "&#38;&", want: "&&" },
        DecoderCase { name: "named entity with no trailing semicolon", input: "&amp", want: "&amp" },
    ];
    let d = new_decoder([]);
    let failures: string[] = [];
    for (let c in cases) {
        let got = d.decode(c.input.to_utf8()).to_string();
        if (got != c.want) {
            failures.push(c.name + ": Decode = " + got);
        }
        let buf = root.util.new_buffer();
        d.decode_to(buf, c.input.to_utf8());
        if (buf.string() != c.want) {
            failures.push(c.name + ": DecodeTo = " + buf.string());
        }
    }
    failures
}

test "TestDecoderCursorInvalidation" {
    assert.equal(decoder_cursor_invalidation_failures(), []);
}

test "TestDecoderEscapedSpace" {
    let d = new_decoder([with_escaped_space()]);
    let input = "a\\ b\\&c";
    let want = "ab&c";
    assert.equal(d.decode(input.to_utf8()).to_string(), want);
    let buf = root.util.new_buffer();
    d.decode_to(buf, input.to_utf8());
    assert.equal(buf.string(), want);
}
