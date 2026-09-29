// Port of the parts of Go's `unicode/utf8` package that goldmark uses.
//
// BAML strings are indexed by code point and its `uint8array` has no UTF-8
// decoding helpers, so byte-level UTF-8 handling is implemented here.

/// Go: `utf8.RuneError` (U+FFFD).
function UTF8_RUNE_ERROR() -> int {
    0xFFFD
}

/// Result of decoding one rune (Go returns `(rune, size int)`).
class DecodedRune {
    r: int,
    size: int,
}

/// Go: `utf8.RuneStart(b)`.
function utf8_rune_start(b: int) -> bool {
    (b & 0xC0) != 0x80
}

/// Go: `utf8.ValidRune(r)`.
function utf8_valid_rune(r: int) -> bool {
    (r >= 0 && r < 0xD800) || (r > 0xDFFF && r <= 0x10FFFF)
}

/// Go: `utf8.DecodeRune(b[at:])`. Returns (RuneError, 1) for invalid input and
/// (RuneError, 0) at the end of input.
function utf8_decode_rune(b: uint8array, at: int) -> DecodedRune {
    let n = b.length();
    if (at >= n || at < 0) {
        return DecodedRune { r: 0xFFFD, size: 0 };
    }
    let c0 = b[at];
    if (c0 < 0x80) {
        return DecodedRune { r: c0, size: 1 };
    }
    let err = DecodedRune { r: 0xFFFD, size: 1 };
    if (c0 < 0xC2 || c0 > 0xF4) {
        return err;
    }
    if (at + 1 >= n) {
        return err;
    }
    let c1 = b[at + 1];
    if (c0 < 0xE0) {
        if ((c1 & 0xC0) != 0x80) {
            return err;
        }
        return DecodedRune { r: ((c0 & 0x1F) << 6) | (c1 & 0x3F), size: 2 };
    }
    let lo = 0x80;
    let hi = 0xBF;
    if (c0 == 0xE0) {
        lo = 0xA0;
    } else if (c0 == 0xED) {
        hi = 0x9F;
    } else if (c0 == 0xF0) {
        lo = 0x90;
    } else if (c0 == 0xF4) {
        hi = 0x8F;
    }
    if (c1 < lo || c1 > hi) {
        return err;
    }
    if (at + 2 >= n) {
        return err;
    }
    let c2 = b[at + 2];
    if ((c2 & 0xC0) != 0x80) {
        return err;
    }
    if (c0 < 0xF0) {
        return DecodedRune { r: ((c0 & 0x0F) << 12) | ((c1 & 0x3F) << 6) | (c2 & 0x3F), size: 3 };
    }
    if (at + 3 >= n) {
        return err;
    }
    let c3 = b[at + 3];
    if ((c3 & 0xC0) != 0x80) {
        return err;
    }
    DecodedRune { r: ((c0 & 0x07) << 18) | ((c1 & 0x3F) << 12) | ((c2 & 0x3F) << 6) | (c3 & 0x3F), size: 4 }
}

/// Go: `utf8.DecodeLastRune(b[:end])`.
function utf8_decode_last_rune(b: uint8array, end: int) -> DecodedRune {
    if (end <= 0) {
        return DecodedRune { r: 0xFFFD, size: 0 };
    }
    let start = end - 1;
    let lim = end - 4;
    if (lim < 0) {
        lim = 0;
    }
    while (start >= lim) {
        if (utf8_rune_start(b[start])) {
            break;
        }
        start -= 1;
    }
    if (start < 0) {
        start = 0;
    }
    let d = utf8_decode_rune(b, start);
    if (start + d.size != end) {
        return DecodedRune { r: 0xFFFD, size: 1 };
    }
    d
}

/// Go: `utf8.EncodeRune`; returns the encoded bytes.
function utf8_encode_rune(r: int) -> uint8array {
    let out = "".to_utf8();
    let v = r;
    if (!utf8_valid_rune(v)) {
        v = 0xFFFD;
    }
    if (v < 0x80) {
        out.push(v);
    } else if (v < 0x800) {
        out.push(0xC0 | (v >> 6));
        out.push(0x80 | (v & 0x3F));
    } else if (v < 0x10000) {
        out.push(0xE0 | (v >> 12));
        out.push(0x80 | ((v >> 6) & 0x3F));
        out.push(0x80 | (v & 0x3F));
    } else {
        out.push(0xF0 | (v >> 18));
        out.push(0x80 | ((v >> 12) & 0x3F));
        out.push(0x80 | ((v >> 6) & 0x3F));
        out.push(0x80 | (v & 0x3F));
    }
    out
}

/// Go: `utf8.RuneLen(r)`.
function utf8_rune_len(r: int) -> int {
    if (r < 0) {
        -1
    } else if (r < 0x80) {
        1
    } else if (r < 0x800) {
        2
    } else if (r >= 0xD800 && r <= 0xDFFF) {
        -1
    } else if (r < 0x10000) {
        3
    } else if (r <= 0x10FFFF) {
        4
    } else {
        -1
    }
}
