// Ported from sasso `src/sourcemap.rs` `#[cfg(test)] mod tests`
// (namespace `root.sourcemap.tests`).

/// Decode one Base64-VLQ value starting at `bytes[*i]`, advancing `*i`.
/// Test-only inverse of `vlq_encode`, for round-trip checking.
// PORT: `i: &mut usize` → `root.std.Cell<int>`; `u64` → `int` (every value
// decoded here fits in 36 bits).
function vlq_decode(bytes: uint8array, i: root.std.Cell<int>) -> int {
    let result: int = 0;
    let shift = 0;
    while (true) {
        let digit = root.std.unwrap(root.sourcemap.B64().index_of(bytes[i.value]));
        i.value += 1;
        result = result | ((digit & 0x1f) << shift);
        shift += 5;
        if ((digit & 0x20) == 0) {
            break;
        }
    }
    let mag = result >> 1;
    if ((result & 1) == 1) {
        -mag
    } else {
        mag
    }
}

test "vlq_known_vectors" {
    let enc = (v: int) -> string {
        let s = root.std.StrBuf.new();
        root.sourcemap.vlq_encode(v, s);
        s.as_str()
    };
    assert.equal(enc(0), "A");
    assert.equal(enc(1), "C");
    assert.equal(enc(-1), "D");
    assert.equal(enc(2), "E");
    assert.equal(enc(-2), "F");
    assert.equal(enc(16), "gB");
    assert.equal(enc(123), "2H")
}

test "vlq_roundtrips_over_a_wide_range" {
    // PORT: `(-100_000..=100_000).step_by(37)` → a stepped `Range`.
    for (let v in baml.iter.Range.new(-100000, 100000 + 1, step = 37)) {
        let s = root.std.StrBuf.new();
        root.sourcemap.vlq_encode(v, s);
        let i = root.std.Cell.new(0);
        // roundtrip {v}
        assert.equal(vlq_decode(s.as_str().to_utf8(), i), v);
        // consumed all bytes for {v}
        assert.equal(i.value, s.byte_len());
    }
    // boundary magnitudes
    for (let v in [2147483647, -2147483648, 0, 15, 16, 31, 32, 1023, 1024]) {
        let s = root.std.StrBuf.new();
        root.sourcemap.vlq_encode(v, s);
        let i = root.std.Cell.new(0);
        assert.equal(vlq_decode(s.as_str().to_utf8(), i), v);
    }
}

test "mappings_delta_encoding" {
    let m = root.sourcemap.Mappings.new();
    // line 0: one segment at the origin -> all zero deltas -> "AAAA"
    m.add(0, 0, 0, 0, 0);
    assert.equal(m.encode(), "AAAA");

    let m = root.sourcemap.Mappings.new();
    // line 0: col 0 -> src0 line0 col0; then col 5 -> src0 line0 col10
    m.add(0, 0, 0, 0, 0);
    m.add(0, 5, 0, 0, 10);
    // line 1 (empty), line 2: col 2 -> src0 line1 col0
    m.add(2, 2, 0, 1, 0);
    let s = m.encode();
    // groups separated by ';' ; empty line 1 is just an extra ';'
    let groups: string[] = s.split(";");
    assert.equal(groups.length(), 3);
    // empty generated line is an empty group
    assert.equal(groups[1], "");
    // first group: [0,0,0,0]=AAAA then delta gen_col +5, src_col +10 -> "KAAU"
    assert.equal(groups[0], "AAAA,KAAU");
    // decode the whole thing and confirm the absolute positions reconstruct
    // PORT: byte literals `b';'` / `b','` → 59 / 44.
    assert.is_true(
        s.to_utf8().to_array().every((b) -> {
            root.sourcemap.B64().includes(b) || b == 59 || b == 44
        }),
    )
}

test "mappings_matches_legacy_charset_regex" {
    // The legacy sass source-map test pins mappings to this shape.
    let m = root.sourcemap.Mappings.new();
    m.add(0, 0, 0, 0, 0);
    m.add(0, 7, 1, 3, 2);
    m.add(1, 0, 0, 5, 0);
    let s = m.encode();
    // PORT: `b.is_ascii_alphanumeric()` on a byte → on `b as char`; byte
    // literals `b'+' | b'/' | b'=' | b',' | b';'` → 43 / 47 / 61 / 44 / 59.
    let ok = s.to_utf8().to_array().every((b) -> {
        root.std.chr_unchecked(b).is_ascii_alphanumeric()
            || b == 43
            || b == 47
            || b == 61
            || b == 44
            || b == 59
    });
    // mappings {s:?} must match /^([A-Za-z0-9+/=]*[,;]?)*$/
    assert.is_true(ok)
}

test "base64_known_vectors" {
    assert.equal(root.sourcemap.base64_bytes("".to_utf8()), "");
    assert.equal(root.sourcemap.base64_bytes("f".to_utf8()), "Zg==");
    assert.equal(root.sourcemap.base64_bytes("fo".to_utf8()), "Zm8=");
    assert.equal(root.sourcemap.base64_bytes("foo".to_utf8()), "Zm9v");
    assert.equal(root.sourcemap.base64_bytes("foob".to_utf8()), "Zm9vYg==");
    assert.equal(root.sourcemap.base64_bytes("fooba".to_utf8()), "Zm9vYmE=");
    assert.equal(root.sourcemap.base64_bytes("foobar".to_utf8()), "Zm9vYmFy")
}

test "json_shape_and_escaping" {
    let map = root.sourcemap.SourceMap {
        file: "out.css",
        sources: ["a.scss", "dir/b.scss"],
        sources_content: [".a{b:1}", "x:\"q\"\n\\z"],
        mappings: "AAAA,KAAU",
    };
    let j = map.to_json_();
    assert.is_true(j.starts_with("{\"version\":3,\"file\":\"out.css\""));
    assert.is_true(j.includes("\"sources\":[\"a.scss\",\"dir/b.scss\"]"));
    assert.is_true(j.includes("\"names\":[]"));
    assert.is_true(j.includes("\"mappings\":\"AAAA,KAAU\""));
    // escaping: the embedded quote, newline and backslash must be escaped
    assert.is_true(j.includes("x:\\\"q\\\"\\n\\\\z"));
    // omitting sourcesContent drops the field entirely
    let map2 = root.sourcemap.SourceMap { ...map_with_no_content(), sources_content: null };
    assert.is_true(!map2.to_json_().includes("sourcesContent"))
}

function map_with_no_content() -> root.sourcemap.SourceMap {
    root.sourcemap.SourceMap {
        file: null,
        sources: ["a.scss"],
        sources_content: null,
        mappings: "",
    }
}
