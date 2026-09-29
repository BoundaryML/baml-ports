// Port of goldmark util/util.go.
//
// Package util provides utility functions for goldmark.
//
// Go's `[]byte` is represented as BAML's `uint8array`. Go slicing is O(1) and
// aliases the backing array; `uint8array.slice` copies. Functions that return
// sub-slices therefore return fresh arrays here.
//
// BAML has no char literals, so ASCII bytes are written as integer literals:
//   9 '\t'  10 '\n'  11 '\v'  12 '\f'  13 '\r'  32 ' '  35 '#'  37 '%'  38 '&'
//   39 '\''  45 '-'  48 '0'  57 '9'  65 'A'  70 'F'  90 'Z'  95 '_'  97 'a'
//   102 'f'  122 'z'

// ---------------------------------------------------------------------------
// Byte helpers (stand-ins for Go builtins / package bytes)
// ---------------------------------------------------------------------------

/// Returns a new empty byte array (Go: `[]byte{}` / nil).
function new_bytes() -> uint8array {
    "".to_utf8()
}

/// Appends every byte of `src` to `dst` in place (Go: `append(dst, src...)`).
/// BAML's `uint8array.concat` allocates a new array, so this loops `push`.
function append_bytes(dst: uint8array, src: uint8array) -> void {
    let n = src.length();
    let i = 0;
    while (i < n) {
        dst.push(src[i]);
        i += 1;
    }
}

/// Go: `b[start:stop]`. Copies (BAML has no slice views).
function sub(b: uint8array, start: int, stop: int) -> uint8array {
    b.slice(start, stop)
}

/// Go: `b[start:]`.
function sub_from(b: uint8array, start: int) -> uint8array {
    b.slice(start, b.length())
}

/// Go: `bytes.IndexByte(b, c)`; returns -1 when not found.
function index_byte(b: uint8array, c: int) -> int {
    b.index_of(c) ?? -1
}

/// Go: `bytes.IndexByte(b[from:], c)` translated back to an absolute index;
/// returns -1 when not found.
function index_byte_from(b: uint8array, from: int, c: int) -> int {
    let n = b.length();
    let i = from;
    while (i < n) {
        if (b[i] == c) {
            return i;
        }
        i += 1;
    }
    -1
}

/// Go: `bytes.Equal(a, b)`.
function bytes_equal(a: uint8array, b: uint8array) -> bool {
    a == b
}

/// Go: `bytes.HasPrefix(b, prefix)`.
function has_prefix(b: uint8array, prefix: uint8array) -> bool {
    let n = prefix.length();
    if (b.length() < n) {
        return false;
    }
    let i = 0;
    while (i < n) {
        if (b[i] != prefix[i]) {
            return false;
        }
        i += 1;
    }
    true
}

/// Go: `bytes.HasPrefix(b[at:], prefix)` without copying.
function has_prefix_at(b: uint8array, at: int, prefix: string) -> bool {
    let p = prefix.to_utf8();
    let n = p.length();
    if (b.length() - at < n || at < 0) {
        return false;
    }
    let i = 0;
    while (i < n) {
        if (b[at + i] != p[i]) {
            return false;
        }
        i += 1;
    }
    true
}

/// Go: `bytes.Contains(b, sub)`.
function bytes_contains(b: uint8array, s: uint8array) -> bool {
    bytes_index(b, s) >= 0
}

/// Go: `bytes.Index(b, sub)`.
///
/// A byte-by-byte search in the BAML VM is ~100x slower than Go's SIMD
/// `bytes.Index`, which makes goldmark's (quadratic in the worst case) raw-HTML
/// scanning unusably slow. So large searches are delegated to native stdlib
/// code: `uint8array.index_of` for 1-byte needles, and `string.index_of` on the
/// UTF-8 decoded text otherwise (with a code point -> byte offset conversion).
/// Invalid UTF-8 falls back to the VM loop.
function bytes_index(b: uint8array, s: uint8array) -> int {
    let n = b.length();
    let m = s.length();
    if (m == 0) {
        return 0;
    }
    if (m == 1) {
        return b.index_of(s[0]) ?? -1;
    }
    if (n > 64) {
        let hs = baml.String.from_utf8(b) catch_all (e) { _ => null };
        let ns = baml.String.from_utf8(s) catch_all (e) { _ => null };
        if (hs != null && ns != null) {
            let cp = hs.index_of(ns);
            if (cp == null) {
                return -1;
            }
            if (hs.length() == n) {
                // ASCII: code point offsets are byte offsets.
                return cp;
            }
            return hs.slice(0, cp).byte_length();
        }
    }
    let i = 0;
    while (i + m <= n) {
        let j = 0;
        while (j < m && b[i + j] == s[j]) {
            j += 1;
        }
        if (j == m) {
            return i;
        }
        i += 1;
    }
    -1
}

/// Go: `bytes.ReplaceAll(b, old, new)`.
function bytes_replace_all(b: uint8array, old: uint8array, repl: uint8array) -> uint8array {
    let out = new_bytes();
    let n = b.length();
    let m = old.length();
    if (m == 0) {
        append_bytes(out, b);
        return out;
    }
    let i = 0;
    while (i < n) {
        if (i + m <= n) {
            let j = 0;
            while (j < m && b[i + j] == old[j]) {
                j += 1;
            }
            if (j == m) {
                append_bytes(out, repl);
                i += m;
                continue;
            }
        }
        out.push(b[i]);
        i += 1;
    }
    out
}

/// Go: `bytes.ToLower(b)` for ASCII letters.
function bytes_to_lower(b: uint8array) -> uint8array {
    let out = new_bytes();
    let n = b.length();
    let i = 0;
    while (i < n) {
        let c = b[i];
        if (c >= 65 && c <= 90) {
            out.push(c + 32);
        } else {
            out.push(c);
        }
        i += 1;
    }
    out
}

/// Go: `util.BytesToReadOnlyString(b)` / `string(b)`.
function bytes_to_string(b: uint8array) -> string {
    b.to_string()
}

/// Go: `util.StringToReadOnlyBytes(s)` / `[]byte(s)`.
function string_to_bytes(s: string) -> uint8array {
    s.to_utf8()
}

/// Returns a one-byte array holding `c`.
function byte_array(c: int) -> uint8array {
    let b = new_bytes();
    b.push(c);
    b
}

// ---------------------------------------------------------------------------
// CopyOnWriteBuffer
// ---------------------------------------------------------------------------

/// A CopyOnWriteBuffer is a byte buffer that copies buffer when
/// it need to be changed.
class CopyOnWriteBuffer {
    buffer: uint8array,
    copied: bool,

    /// Write writes given bytes to the buffer.
    /// Write allocate new buffer and clears it at the first time.
    function write(self, value: uint8array) -> void {
        if (!self.copied) {
            self.buffer = new_bytes();
            self.copied = true;
        }
        append_bytes(self.buffer, value);
    }

    /// WriteString writes given string to the buffer.
    function write_string(self, value: string) -> void {
        self.write(value.to_utf8());
    }

    /// Append appends given bytes to the buffer.
    /// Append copy buffer at the first time.
    function append(self, value: uint8array) -> void {
        if (!self.copied) {
            self.buffer = self.buffer.slice(0, self.buffer.length());
            self.copied = true;
        }
        append_bytes(self.buffer, value);
    }

    /// AppendString appends given string to the buffer.
    function append_string(self, value: string) -> void {
        self.append(value.to_utf8());
    }

    /// WriteByte writes the given byte to the buffer.
    function write_byte(self, c: int) -> void {
        if (!self.copied) {
            self.buffer = new_bytes();
            self.copied = true;
        }
        self.buffer.push(c);
    }

    /// AppendByte appends given bytes to the buffer.
    function append_byte(self, c: int) -> void {
        if (!self.copied) {
            self.buffer = self.buffer.slice(0, self.buffer.length());
            self.copied = true;
        }
        self.buffer.push(c);
    }

    /// Bytes returns bytes of this buffer.
    function bytes(self) -> uint8array {
        self.buffer
    }

    /// IsCopied returns true if buffer has been copied, otherwise false.
    function is_copied(self) -> bool {
        self.copied
    }
}

/// NewCopyOnWriteBuffer returns a new CopyOnWriteBuffer.
function new_copy_on_write_buffer(buffer: uint8array) -> CopyOnWriteBuffer {
    CopyOnWriteBuffer { buffer: buffer, copied: false }
}

// ---------------------------------------------------------------------------
// Scanning helpers
// ---------------------------------------------------------------------------

/// Result of `read_while` (Go returns `(int, bool)`).
class ReadWhileResult {
    pos: int,
    ok: bool,
}

/// ReadWhile read the given bytes while pred is true.
function read_while(bs: uint8array, start: int, stop: int, pred: (c: int) -> bool throws never) -> ReadWhileResult {
    let j = start;
    let ok = false;
    while (j < stop) {
        let c1 = bs[j];
        if (pred(c1)) {
            ok = true;
            j += 1;
            continue;
        }
        break;
    }
    ReadWhileResult { pos: j, ok: ok }
}

/// IsBlank returns true if the given string is all space characters.
function is_blank(bs: uint8array) -> bool {
    let n = bs.length();
    let i = 0;
    while (i < n) {
        if (!is_space(bs[i])) {
            return false;
        }
        i += 1;
    }
    true
}

/// VisualizeSpaces visualize invisible space characters.
function visualize_spaces(bs: uint8array) -> uint8array {
    let r = bytes_replace_all(bs, " ".to_utf8(), "[SPACE]".to_utf8());
    r = bytes_replace_all(r, "\t".to_utf8(), "[TAB]".to_utf8());
    r = bytes_replace_all(r, "\n".to_utf8(), "[NEWLINE]\n".to_utf8());
    r = bytes_replace_all(r, "\r".to_utf8(), "[CR]".to_utf8());
    r = bytes_replace_all(r, byte_array(11), "[VTAB]".to_utf8());
    r = bytes_replace_all(r, byte_array(0), "[NUL]".to_utf8());
    r = bytes_replace_all(r, baml.String.from_code_points([0xFFFD]).to_utf8(), "[U+FFFD]".to_utf8());
    r
}

/// TabWidth calculates actual width of a tab at the given position.
function tab_width(current_pos: int) -> int {
    4 - current_pos % 4
}

/// Result of indent computations (Go returns `(pos, padding int)`).
class IndentPos {
    pos: int,
    padding: int,
}

/// IndentPosition searches an indent position with the given width for the given line.
/// If the line contains tab characters, paddings may be not zero.
/// currentPos==0 and width==2:
///
///     position: 0    1
///               [TAB]aaaa
///     width:    1234 5678
///
/// width=2 is in the tab character. In this case, IndentPosition returns
/// (pos=1, padding=2).
function indent_position(bs: uint8array, current_pos: int, width: int) -> IndentPos {
    indent_position_padding(bs, current_pos, 0, width)
}

/// IndentPositionPadding searches an indent position with the given width for the given line.
/// This function is mostly same as IndentPosition except this function
/// takes account into additional paddings.
function indent_position_padding(bs: uint8array, current_pos: int, paddingv: int, width: int) -> IndentPos {
    if (width == 0) {
        return IndentPos { pos: 0, padding: paddingv };
    }
    let w = 0;
    let i = 0;
    let l = bs.length();
    let p = paddingv;
    while (i < l) {
        if (p > 0) {
            p -= 1;
            w += 1;
            i += 1;
            continue;
        }
        if (bs[i] == 9 && w < width) {
            w += tab_width(current_pos + w);
        } else if (bs[i] == 32 && w < width) {
            w += 1;
        } else {
            break;
        }
        i += 1;
    }
    if (w >= width) {
        return IndentPos { pos: i - paddingv, padding: w - width };
    }
    IndentPos { pos: -1, padding: -1 }
}

/// Result of `indent_width` (Go returns `(width, pos int)`).
class IndentWidthResult {
    width: int,
    pos: int,
}

/// IndentWidth calculate an indent width for the given line.
function indent_width(bs: uint8array, current_pos: int) -> IndentWidthResult {
    let width = 0;
    let pos = 0;
    let n = bs.length();
    let i = 0;
    while (i < n) {
        let c = bs[i];
        if (c == 32) {
            width += 1;
            pos += 1;
        } else if (c == 9) {
            width += tab_width(current_pos + width);
            pos += 1;
        } else {
            break;
        }
        i += 1;
    }
    IndentWidthResult { width: width, pos: pos }
}

/// FirstNonSpacePosition returns a position line that is a first nonspace
/// character.
function first_non_space_position(bs: uint8array) -> int {
    let n = bs.length();
    let i = 0;
    while (i < n) {
        let c = bs[i];
        if (c == 32 || c == 9) {
            i += 1;
            continue;
        }
        if (c == 10) {
            return -1;
        }
        return i;
    }
    -1
}

function contains_byte(b: uint8array, c: int) -> bool {
    b.includes(c)
}

/// TrimLeft trims characters in the given b from head of the bs.
function trim_left(bs: uint8array, b: uint8array) -> uint8array {
    let i = 0;
    let n = bs.length();
    while (i < n && b.includes(bs[i])) {
        i += 1;
    }
    bs.slice(i, n)
}

/// TrimRight trims characters in the given b from tail of the bs.
function trim_right(bs: uint8array, b: uint8array) -> uint8array {
    let i = bs.length() - 1;
    while (i >= 0 && b.includes(bs[i])) {
        i -= 1;
    }
    bs.slice(0, i + 1)
}

/// TrimLeftLength returns a length of leading specified characters.
function trim_left_length(bs: uint8array, b: uint8array) -> int {
    bs.length() - trim_left(bs, b).length()
}

/// TrimRightLength returns a length of trailing specified characters.
function trim_right_length(bs: uint8array, b: uint8array) -> int {
    bs.length() - trim_right(bs, b).length()
}

/// TrimLeftSpaceLength returns a length of leading space characters.
function trim_left_space_length(bs: uint8array) -> int {
    let i = 0;
    let n = bs.length();
    while (i < n && is_space(bs[i])) {
        i += 1;
    }
    i
}

/// TrimRightSpaceLength returns a length of trailing space characters.
function trim_right_space_length(bs: uint8array) -> int {
    let l = bs.length();
    let i = l - 1;
    while (i >= 0 && is_space(bs[i])) {
        i -= 1;
    }
    if (i < 0) {
        return l;
    }
    l - 1 - i
}

/// TrimLeftSpace returns a subslice of the given bytes by slicing off all leading
/// space characters.
function trim_left_space(bs: uint8array) -> uint8array {
    bs.slice(trim_left_space_length(bs), bs.length())
}

/// TrimRightSpace returns a subslice of the given bytes by slicing off all trailing
/// space characters.
function trim_right_space(bs: uint8array) -> uint8array {
    bs.slice(0, bs.length() - trim_right_space_length(bs))
}

/// DoFullUnicodeCaseFolding performs full unicode case folding to given bytes.
function do_full_unicode_case_folding(v: uint8array) -> uint8array {
    let cob = new_copy_on_write_buffer(v);
    let n = 0;
    let i = 0;
    let l = v.length();
    while (i < l) {
        let c = v[i];
        if (c < 0xb5) {
            if (c >= 0x41 && c <= 0x5a) {
                // A-Z to a-z
                cob.write(v.slice(n, i));
                cob.write_byte(c + 32);
                n = i + 1;
            }
            i += 1;
            continue;
        }
        if (!utf8_rune_start(c)) {
            i += 1;
            continue;
        }
        let d = utf8_decode_rune(v, i);
        if (d.r == UTF8_RUNE_ERROR()) {
            i += 1;
            continue;
        }
        let folded = unicode_case_folding(d.r);
        if (folded == null) {
            i += 1;
            continue;
        }
        cob.write(v.slice(n, i));
        for (let f in folded) {
            cob.write(utf8_encode_rune(f));
        }
        i += d.size - 1;
        n = i + 1;
        i += 1;
    }
    if (cob.is_copied()) {
        cob.write(v.slice(n, l));
    }
    cob.bytes()
}

/// ReplaceSpaces replaces sequence of spaces with the given repl.
function replace_spaces(bs: uint8array, repl: int) -> uint8array {
    let ret: uint8array? = null;
    let start = -1;
    let n = bs.length();
    let i = 0;
    while (i < n) {
        let c = bs[i];
        let iss = is_space(c);
        if (start < 0 && iss) {
            start = i;
            i += 1;
            continue;
        } else if (start >= 0 && iss) {
            i += 1;
            continue;
        } else if (start >= 0) {
            if (ret == null) {
                ret = bs.slice(0, start);
            }
            ret?.push(repl);
            start = -1;
        }
        if (ret != null) {
            ret.push(c);
        }
        i += 1;
    }
    if (start >= 0 && ret != null) {
        ret.push(repl);
    }
    ret ?? bs
}

/// ToRune decode given bytes start at pos and returns a rune.
function to_rune(bs: uint8array, pos: int) -> int {
    let i = pos;
    while (i >= 0) {
        if (utf8_rune_start(bs[i])) {
            break;
        }
        i -= 1;
    }
    utf8_decode_rune(bs, i).r
}

/// ToValidRune returns 0xFFFD if the given rune is invalid, otherwise v.
function to_valid_rune(v: int) -> int {
    if (v == 0 || !utf8_valid_rune(v)) {
        return 0xFFFD;
    }
    v
}

/// ToLinkReference converts given bytes into a valid link reference string.
/// ToLinkReference trims leading and trailing spaces, performs unicode case
/// folding, and replaces sequences of spaces with a single space character.
function to_link_reference(v: uint8array) -> string {
    let r = trim_left_space(v);
    r = trim_right_space(r);
    r = do_full_unicode_case_folding(r);
    replace_spaces(r, 32).to_string()
}

// ---------------------------------------------------------------------------
// HTML / URL escaping
// ---------------------------------------------------------------------------

/// Port of `htmlEscapeTable`: returns the escaped form of `c`, or null.
function html_escape_for(c: int) -> string? {
    match (c) {
        0 => "�",
        34 => "&quot;",
        38 => "&amp;",
        60 => "&lt;",
        62 => "&gt;",
        _ => null,
    }
}

/// EscapeHTMLByte returns HTML escaped bytes if the given byte should be escaped,
/// otherwise nil.
function escape_html_byte(b: int) -> uint8array? {
    if (b == 0) {
        return "�".to_utf8();
    }
    let v = html_escape_for(b);
    if (v == null) {
        return null;
    }
    v.to_utf8()
}

/// Returns true when `c` has an entry in `htmlEscapeTable`.
function needs_html_escape(c: int) -> bool {
    c == 34 || c == 38 || c == 60 || c == 62 || c == 0
}

/// EscapeHTML escapes characters that should be escaped in HTML text.
function escape_html(v: uint8array) -> uint8array {
    let cob = new_copy_on_write_buffer(v);
    let n = 0;
    let l = v.length();
    let i = 0;
    while (i < l) {
        let c = v[i];
        if (needs_html_escape(c)) {
            cob.write(v.slice(n, i));
            cob.write(escape_html_byte(c) ?? new_bytes());
            n = i + 1;
        }
        i += 1;
    }
    if (cob.is_copied()) {
        cob.write(v.slice(n, l));
    }
    cob.bytes()
}

/// Port of `urlEscapeTable`: 1 when `c` may appear unescaped in a URL.
function url_safe_byte(c: int) -> bool {
    if (c >= 0x7F || c < 0x21) {
        return false;
    }
    // unescaped: ! # $ % & ( ) * + , - . / 0-9 : ; = ? @ A-Z _ a-z ~
    // escaped: " ' < > [ \ ] ^ ` { | }
    !(c == 34 || c == 39 || c == 60 || c == 62 || c == 91 || c == 92 || c == 93 || c == 94 || c == 96 || c == 123 || c == 124 || c == 125)
}

function hex_upper(v: int) -> string {
    let digits = "0123456789ABCDEF";
    `${digits.at(v / 16) ?? "0"}${digits.at(v % 16) ?? "0"}`
}

/// Port of Go's `url.QueryEscape` for the byte sequences URLEscape passes it.
function query_escape(b: uint8array) -> uint8array {
    let out = new_bytes();
    let n = b.length();
    let i = 0;
    while (i < n) {
        let c = b[i];
        if (is_alpha_numeric(c) || c == 45 || c == 95 || c == 46 || c == 126) {
            out.push(c);
        } else if (c == 32) {
            out.push(43);
        } else {
            out.push(37);
            append_bytes(out, hex_upper(c).to_utf8());
        }
        i += 1;
    }
    out
}

/// URLEscape escape the given URL.
///
/// URL encoded values (%xx) are kept as is.
function url_escape(v: uint8array) -> uint8array {
    let cob = new_copy_on_write_buffer(v);
    let limit = v.length();
    let n = 0;
    let i = 0;
    while (i < limit) {
        let c = v[i];
        if (url_safe_byte(c) && c != 37 && c != 38 && c != 39) {
            i += 1;
            continue;
        }
        if (c == 37 && i + 2 < limit && is_hex_decimal(v[i + 1]) && is_hex_decimal(v[i + 2])) {
            i += 3;
            continue;
        }
        if (c == 37) {
            // '%' is in the unescaped set of urlEscapeTable
            i += 1;
            continue;
        }
        let u8len = utf8_len(c);
        if (u8len == 99) {
            // invalid utf8 leading byte, skip it
            i += 1;
            continue;
        }
        if (c == 32) {
            cob.write(v.slice(n, i));
            cob.write("%20".to_utf8());
            i += 1;
            n = i;
            continue;
        }
        if (c == 38) {
            cob.write(v.slice(n, i));
            cob.write("&amp;".to_utf8());
            i += 1;
            n = i;
            continue;
        }
        if (c == 39) {
            cob.write(v.slice(n, i));
            cob.write_byte(39);
            i += 1;
            n = i;
            continue;
        }
        if (u8len > limit) {
            u8len = limit - 1;
        }
        if (u8len == 0) {
            i += 1;
            n = i;
            continue;
        }
        cob.write(v.slice(n, i));
        let stop = i + u8len;
        if (stop > limit) {
            i += 1;
            n = i;
            continue;
        }
        cob.write(query_escape(v.slice(i, stop)));
        i += u8len;
        n = i;
    }
    if (cob.is_copied() && n < limit) {
        cob.write(v.slice(n, limit));
    }
    cob.bytes()
}

// ---------------------------------------------------------------------------
// Character classes
// ---------------------------------------------------------------------------

/// UTF8Len returns a byte length of the utf-8 character (99 for an invalid
/// leading byte, 0 for 0xF5..0xFF). Port of `utf8lenTable`.
function utf8_len(b: int) -> int {
    if (b < 0x80) {
        1
    } else if (b < 0xC2) {
        // 0x80-0xBF continuation bytes and 0xC0/0xC1 (overlong) are invalid.
        99
    } else if (b < 0xE0) {
        2
    } else if (b < 0xF0) {
        3
    } else if (b < 0xF8) {
        4
    } else {
        99
    }
}

/// IsPunct returns true if the given character is a punctuation, otherwise false.
/// Port of `punctTable`: ASCII punctuation characters.
function is_punct(c: int) -> bool {
    (c >= 33 && c <= 47) || (c >= 58 && c <= 64) || (c >= 91 && c <= 96) || (c >= 123 && c <= 126)
}

/// IsPunctRune returns true if the given rune is a punctuation, otherwise false.
function is_punct_rune(r: int) -> bool {
    is_unicode_punct_or_symbol(r)
}

/// IsSpace returns true if the given character is a space, otherwise false.
/// Port of `spaceTable`: `\t` `\n` `\r` and space (NOT `\v`/`\f`).
function is_space(c: int) -> bool {
    c == 32 || c == 9 || c == 10 || c == 13
}

/// IsSpaceRune returns true if the given rune is a space, otherwise false.
function is_space_rune(r: int) -> bool {
    is_unicode_space(r)
}

/// IsNumeric returns true if the given character is a numeric, otherwise false.
function is_numeric(c: int) -> bool {
    c >= 48 && c <= 57
}

/// IsHexDecimal returns true if the given character is a hexdecimal, otherwise false.
function is_hex_decimal(c: int) -> bool {
    (c >= 48 && c <= 57) || (c >= 97 && c <= 102) || (c >= 65 && c <= 70)
}

/// IsAlphaNumeric returns true if the given character is a alphabet or a numeric, otherwise false.
function is_alpha_numeric(c: int) -> bool {
    (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57)
}

// ---------------------------------------------------------------------------
// BufWriter
// ---------------------------------------------------------------------------

/// A BufWriter is a subset of the bufio.Writer. Go's `io.Writer` has no BAML
/// equivalent; renderers write to this interface instead.
interface BufWriter {
    function write(self, p: uint8array) -> int throws never
    function write_byte(self, c: int) -> void throws never
    function write_rune(self, r: int) -> int throws never
    function write_string(self, s: string) -> int throws never
    function flush(self) -> void throws never
}

/// Port of `bytes.Buffer` used as the in-memory BufWriter (Go `bw`).
/// Chunks are stored as strings and joined on demand; every write in goldmark
/// is split on ASCII boundaries so decoding chunk-by-chunk is lossless.
class Buffer {
    parts: string[],

    function string(self) -> string {
        if (self.parts.length() > 1) {
            let joined = self.parts.join("");
            self.parts = [joined];
        }
        self.parts.at(0) ?? ""
    }

    function bytes(self) -> uint8array {
        self.string().to_utf8()
    }

    function reset(self) -> void {
        self.parts = [];
    }

    function len(self) -> int {
        self.string().byte_length()
    }

    implements BufWriter {
        function write(self, p: uint8array) -> int throws never {
            self.parts.push(p.to_string());
            p.length()
        }

        function write_byte(self, c: int) -> void throws never {
            if (c < 0x80) {
                self.parts.push(baml.String.from_code_points([c]) catch_all (e) { _ => "" });
            } else {
                self.parts.push(byte_array(c).to_string());
            }
        }

        function write_rune(self, r: int) -> int throws never {
            let s = baml.String.from_code_points([r]) catch_all (e) { _ => "�" };
            self.parts.push(s);
            s.byte_length()
        }

        function write_string(self, s: string) -> int throws never {
            self.parts.push(s);
            s.byte_length()
        }

        function flush(self) -> void throws never {
        }
    }
}

/// Returns a new empty in-memory buffer.
function new_buffer() -> Buffer {
    Buffer { parts: [] }
}

// ---------------------------------------------------------------------------
// PrioritizedValue
// ---------------------------------------------------------------------------

/// A PrioritizedValue struct holds pair of an arbitrary value and a priority.
class PrioritizedValue<T> {
    /// Value is an arbitrary value that you want to prioritize.
    value: T,
    /// Priority is a priority of the value.
    priority: int,
}

/// Sort sorts the PrioritizedValues in ascending order (stable).
function sort_prioritized<T>(s: PrioritizedValue<T>[]) -> PrioritizedValue<T>[] {
    s.sort_by_key((v) -> { v.priority })
}

/// Prioritized returns a new PrioritizedValue.
function prioritized<T>(v: T, priority: int) -> PrioritizedValue<T> {
    PrioritizedValue<T> { value: v, priority: priority }
}

// ---------------------------------------------------------------------------
// BytesFilter
// ---------------------------------------------------------------------------

function bytes_hash(b: uint8array) -> int {
    let hash = 5381;
    let n = b.length();
    let i = 0;
    while (i < n) {
        // keep the hash within 32 bits to avoid 63-bit overflow panics
        hash = ((hash * 33) + b[i]) % 4294967296;
        i += 1;
    }
    hash
}

/// BytesFilter is a efficient data structure for checking whether bytes exist or not.
///
/// Go's implementation is a bloom-ish filter over 64 hash slots guarded by
/// per-position byte masks. This port keeps the per-position masks and hash
/// slots, but stores slot keys as strings (BAML maps only take string keys).
class BytesFilter {
    chars: int[],
    threshold: int,
    slots: map<string, string[]>,

    /// Add adds given bytes to this set.
    function add(self, b: uint8array) -> void {
        let l = b.length();
        let m = if (l < self.threshold) { l } else { self.threshold };
        let i = 0;
        while (i < m) {
            self.chars[b[i]] = self.chars[b[i]] | (1 << i);
            i += 1;
        }
        let h = (bytes_hash(b) % 64).to_string();
        let slot = self.slots.get(h) ?? [];
        slot.push(b.to_string());
        self.slots[h] = slot;
    }

    /// AddString adds given string to this set.
    function add_string(self, st: string) -> void {
        self.add(st.to_utf8());
    }

    /// Contains return true if this set contains given bytes, otherwise false.
    function contains(self, b: uint8array) -> bool {
        let l = b.length();
        let m = if (l < self.threshold) { l } else { self.threshold };
        let i = 0;
        while (i < m) {
            if ((self.chars[b[i]] & (1 << i)) == 0) {
                return false;
            }
            i += 1;
        }
        let h = (bytes_hash(b) % 64).to_string();
        let slot = self.slots.get(h);
        if (slot == null) {
            return false;
        }
        slot.includes(b.to_string())
    }

    /// ContainsString return true if this set contains given string, otherwise false.
    function contains_string(self, st: string) -> bool {
        self.contains(st.to_utf8())
    }

    /// Extend copies this filter and adds given bytes to new filter.
    function extend(self, bs: uint8array[]) -> BytesFilter {
        let nf = self.copy();
        for (let b in bs) {
            nf.add(b);
        }
        nf
    }

    /// ExtendString copies this filter and adds given string to new filter.
    /// Given string must be separated by a comma.
    function extend_string(self, elements: string) -> BytesFilter {
        let nf = self.copy();
        nf.add_comma_separated(elements);
        nf
    }

    function copy(self) -> BytesFilter {
        let slots: map<string, string[]> = {};
        for (let k in self.slots.keys()) {
            slots[k] = (self.slots.get(k) ?? []).slice(0, (self.slots.get(k) ?? []).length());
        }
        BytesFilter { chars: self.chars.slice(0, 256), threshold: self.threshold, slots: slots }
    }

    function add_comma_separated(self, elements: string) -> void {
        for (let e in elements.split(",")) {
            if (e != "") {
                self.add_string(e);
            }
        }
    }
}

/// NewBytesFilter returns a new BytesFilter.
function new_bytes_filter(elements: uint8array[]) -> BytesFilter {
    let chars: int[] = [];
    let i = 0;
    while (i < 256) {
        chars.push(0);
        i += 1;
    }
    let s = BytesFilter { chars: chars, threshold: 3, slots: {} };
    for (let e in elements) {
        s.add(e);
    }
    s
}

/// NewBytesFilterString returns a new BytesFilter.
/// Given string must be separated by a comma.
function new_bytes_filter_string(elements: string) -> BytesFilter {
    let s = new_bytes_filter([]);
    s.add_comma_separated(elements);
    s
}

/// Go: `bytes.IndexByte(b[start:stop], c)` translated back to an absolute
/// index; returns -1 when not found.
function index_byte_in_range(b: uint8array, start: int, stop: int, c: int) -> int {
    let i = start;
    while (i < stop) {
        if (b[i] == c) {
            return i;
        }
        i += 1;
    }
    -1
}

/// Go: `[]byte{...}` literal from ASCII byte values.
function bytes_of(values: int[]) -> uint8array {
    let b = new_bytes();
    for (let v in values) {
        b.push(v);
    }
    b
}

/// Go: `bytes.TrimSpace(b)` (ASCII whitespace).
function trim_space(b: uint8array) -> uint8array {
    let start = 0;
    let stop = b.length();
    while (start < stop && is_space(b[start])) {
        start += 1;
    }
    while (stop > start && is_space(b[stop - 1])) {
        stop -= 1;
    }
    b.slice(start, stop)
}
