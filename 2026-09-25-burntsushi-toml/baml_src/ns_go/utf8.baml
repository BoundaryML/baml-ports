// Shim: the subset of Go's `unicode/utf8` (and a little of `unicode`) that the
// toml package relies on.
//
// Go strings are byte strings that may hold invalid UTF-8; BAML strings are
// always valid Unicode. The lexer therefore works on the raw UTF-8 bytes of
// the document (an `int[]` of values 0..255), exactly like Go indexes a
// string, and these helpers decode/encode runes on that representation.

/// utf8.RuneError, the replacement character U+FFFD.
function rune_error() -> int {
    65533
}

/// utf8.MaxRune.
function max_rune() -> int {
    1114111
}

/// Result of decoding one rune: the rune and its width in bytes.
class DecodedRune {
    r: int,
    size: int,
}

/// utf8.DecodeRuneInString(s[pos:]) on a byte array. Returns
/// (RuneError, 1) for an invalid encoding and (RuneError, 0) for empty input.
function decode_rune(b: int[], pos: int) -> DecodedRune {
    let n = b.length() - pos;
    if (n < 1) {
        return DecodedRune { r: rune_error(), size: 0 };
    }
    let p0 = b[pos];
    if (p0 < 128) {
        return DecodedRune { r: p0, size: 1 };
    }
    // Determine the expected length and the valid range of the second byte
    // (this mirrors the `first`/`acceptRanges` tables in Go's utf8 package).
    let size = first_size(p0);
    if (size == 0) {
        return DecodedRune { r: rune_error(), size: 1 };
    }
    let lo = accept_lo(p0);
    let hi = accept_hi(p0);
    if (n < size) {
        return DecodedRune { r: rune_error(), size: 1 };
    }
    let b1 = b[pos + 1];
    if (b1 < lo || hi < b1) {
        return DecodedRune { r: rune_error(), size: 1 };
    }
    if (size == 2) {
        return DecodedRune { r: ((p0 & 31) << 6) | (b1 & 63), size: 2 };
    }
    let b2 = b[pos + 2];
    if (b2 < 128 || 191 < b2) {
        return DecodedRune { r: rune_error(), size: 1 };
    }
    if (size == 3) {
        return DecodedRune { r: ((p0 & 15) << 12) | ((b1 & 63) << 6) | (b2 & 63), size: 3 };
    }
    let b3 = b[pos + 3];
    if (b3 < 128 || 191 < b3) {
        return DecodedRune { r: rune_error(), size: 1 };
    }
    DecodedRune {
        r: ((p0 & 7) << 18) | ((b1 & 63) << 12) | ((b2 & 63) << 6) | (b3 & 63),
        size: 4,
    }
}

// The sequence length implied by a leading byte (0 = invalid leading byte).
function first_size(p0: int) -> int {
    if (p0 >= 194 && p0 <= 223) {
        return 2;
    }
    if (p0 >= 224 && p0 <= 239) {
        return 3;
    }
    if (p0 >= 240 && p0 <= 244) {
        return 4;
    }
    0
}

function accept_lo(p0: int) -> int {
    if (p0 == 224) {
        return 160;
    }
    if (p0 == 240) {
        return 144;
    }
    128
}

function accept_hi(p0: int) -> int {
    if (p0 == 237) {
        return 159;
    }
    if (p0 == 244) {
        return 143;
    }
    191
}

/// utf8.ValidRune.
function valid_rune(r: int) -> bool {
    if (0 <= r && r < 55296) {
        return true;
    }
    if (57343 < r && r <= max_rune()) {
        return true;
    }
    false
}

/// utf8.AppendRune: append the UTF-8 encoding of r to buf. Invalid runes are
/// encoded as RuneError, as in Go.
function append_rune(buf: int[], r0: int) -> void {
    let r = r0;
    if (!valid_rune(r)) {
        r = rune_error();
    }
    if (r < 128) {
        buf.push(r);
    } else if (r < 2048) {
        buf.push(192 | (r >> 6));
        buf.push(128 | (r & 63));
    } else if (r < 65536) {
        buf.push(224 | (r >> 12));
        buf.push(128 | ((r >> 6) & 63));
        buf.push(128 | (r & 63));
    } else {
        buf.push(240 | (r >> 18));
        buf.push(128 | ((r >> 12) & 63));
        buf.push(128 | ((r >> 6) & 63));
        buf.push(128 | (r & 63));
    }
}

/// The UTF-8 bytes of a (valid) BAML string, as Go's `[]byte(s)`.
function bytes_of(s: string) -> int[] {
    s.to_utf8().to_array()
}

/// string(b) for a byte slice that may contain invalid UTF-8. BAML strings
/// cannot hold invalid UTF-8, so every invalid byte is replaced by U+FFFD
/// (what Go would print with `%s` of `[]rune(string(b))`).
function string_of(b: int[]) -> string {
    if (b.length() == 0) {
        return "";
    }
    let arr = baml.Uint8Array.from_array(b) catch (e) {
        _ => {
            return string_of_lossy(b);
        },
    };
    string.from_utf8(arr) catch (e) {
        _ => string_of_lossy(b)
    }
}

function string_of_lossy(b: int[]) -> string {
    let out: int[] = [];
    let pos = 0;
    while (pos < b.length()) {
        let d = decode_rune(b, pos);
        append_rune(out, d.r);
        pos += d.size;
    }
    string.from_utf8(baml.Uint8Array.from_array(out)) catch_all (e) {
        _ => ""
    }
}

/// string(b[start:end]).
function string_slice(b: int[], start: int, end: int) -> string {
    string_of(b.slice(start, end))
}

/// string(rune): the one-character string for a rune.
function rune_string(r: int) -> string {
    let out: int[] = [];
    append_rune(out, r);
    string.from_utf8(baml.Uint8Array.from_array(out)) catch_all (e) {
        _ => "�"
    }
}

/// unicode.IsLetter for the rune r.
function is_letter(r: int) -> bool {
    if (r < 128) {
        return (r >= 65 && r <= 90) || (r >= 97 && r <= 122);
    }
    if (!valid_rune(r)) {
        return false;
    }
    rune_string(r).is_alphabetic()
}
