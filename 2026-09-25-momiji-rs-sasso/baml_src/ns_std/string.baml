// `char` and `str` helpers. A Rust `char` is a one-character BAML `string`.
// Offsets are CHARACTER offsets unless a function says `byte`.

/// `c as u32` — the code point of the (first) character.
function ord(c: string) -> int {
    c.code_point_at(0) ?? baml.sys.panic("std.ord: empty string")
}

/// `char::from_u32(cp)` — `null` for a surrogate or out-of-range value.
function chr(cp: int) -> string? {
    if (cp < 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) {
        return null;
    }
    string.from_code_points([cp]) catch (e) {
        _ => null
    }
}

/// `char::from_u32(cp).unwrap()` / `cp as u8 as char`.
function chr_unchecked(cp: int) -> string {
    chr(cp) ?? baml.sys.panic(`std.chr_unchecked: invalid code point ${cp}`)
}

/// `c.len_utf8()`.
function len_utf8(c: string) -> int {
    c.byte_length()
}

/// `c.to_digit(radix)`.
function to_digit(c: string, radix: int) -> int? {
    let cp = ord(c);
    let d = if (cp >= 48 && cp <= 57) {
        cp - 48
    } else if (cp >= 97 && cp <= 122) {
        cp - 97 + 10
    } else if (cp >= 65 && cp <= 90) {
        cp - 65 + 10
    } else {
        99
    };
    if (d < radix) {
        d
    } else {
        null
    }
}

/// `char::from_digit(d, radix)` (lowercase letters).
function from_digit(d: int, radix: int) -> string? {
    if (d < 0 || d >= radix) {
        return null;
    }
    if (d < 10) {
        chr_unchecked(48 + d)
    } else {
        chr_unchecked(97 + d - 10)
    }
}

/// `c.is_ascii_digit()` that tolerates `None` (`false`).
function is_ascii_digit(c: string?) -> bool {
    if (c == null || c == "") {
        return false;
    }
    let cp = ord(c);
    cp >= 48 && cp <= 57
}

/// `c.is_ascii_hexdigit()` that tolerates `None`.
function is_ascii_hexdigit(c: string?) -> bool {
    if (c == null || c == "") {
        return false;
    }
    let cp = ord(c);
    (cp >= 48 && cp <= 57) || (cp >= 97 && cp <= 102) || (cp >= 65 && cp <= 70)
}

/// `c.is_ascii_alphabetic()` that tolerates `None`.
function is_ascii_alphabetic(c: string?) -> bool {
    if (c == null || c == "") {
        return false;
    }
    let cp = ord(c);
    (cp >= 97 && cp <= 122) || (cp >= 65 && cp <= 90)
}

/// `c.is_ascii_alphanumeric()` that tolerates `None`.
function is_ascii_alphanumeric(c: string?) -> bool {
    is_ascii_alphabetic(c) || is_ascii_digit(c)
}

/// `c.is_ascii_whitespace()` (space, \t, \n, \x0C, \r) that tolerates `None`.
function is_ascii_whitespace(c: string?) -> bool {
    c == " " || c == "\t" || c == "\n" || c == "\r" || c == "\f"
}

/// `c.is_ascii()` for one char.
function is_ascii_char(c: string?) -> bool {
    if (c == null || c == "") {
        return false;
    }
    ord(c) < 128
}

/// `c.is_whitespace()` (Unicode White_Space) that tolerates `None`.
function is_whitespace(c: string?) -> bool {
    if (c == null || c == "") {
        return false;
    }
    c.is_whitespace()
}

/// `s.to_ascii_lowercase()` (only A-Z change).
function ascii_lower(s: string) -> string {
    if (s.is_ascii()) {
        return s.to_lower_case();
    }
    let out = StrBuf.new();
    for (let c in s.chars()) {
        let cp = ord(c);
        if (cp >= 65 && cp <= 90) {
            out.push(chr_unchecked(cp + 32));
        } else {
            out.push(c);
        }
    }
    out.as_str()
}

/// `s.to_ascii_uppercase()` (only a-z change).
function ascii_upper(s: string) -> string {
    if (s.is_ascii()) {
        return s.to_upper_case();
    }
    let out = StrBuf.new();
    for (let c in s.chars()) {
        let cp = ord(c);
        if (cp >= 97 && cp <= 122) {
            out.push(chr_unchecked(cp - 32));
        } else {
            out.push(c);
        }
    }
    out.as_str()
}

/// `a.eq_ignore_ascii_case(b)`.
function eq_ignore_ascii_case(a: string, b: string) -> bool {
    if (a == b) {
        return true;
    }
    if (a.byte_length() != b.byte_length()) {
        return false;
    }
    ascii_lower(a) == ascii_lower(b)
}

/// `s.strip_prefix(p)`.
function strip_prefix(s: string, prefix: string) -> string? {
    if (s.starts_with(prefix)) {
        s.slice(prefix.length(), s.length())
    } else {
        null
    }
}

/// `s.strip_suffix(p)`.
function strip_suffix(s: string, suffix: string) -> string? {
    if (s.ends_with(suffix)) {
        s.slice(0, s.length() - suffix.length())
    } else {
        null
    }
}

/// `s.trim_start_matches(pat)` for a string pattern.
function trim_start_matches(s: string, pat: string) -> string {
    if (pat == "") {
        return s;
    }
    let out = s;
    while (out.starts_with(pat)) {
        out = out.slice(pat.length(), out.length());
    }
    out
}

/// `s.trim_end_matches(pat)` for a string pattern.
function trim_end_matches(s: string, pat: string) -> string {
    if (pat == "") {
        return s;
    }
    let out = s;
    while (out.ends_with(pat)) {
        out = out.slice(0, out.length() - pat.length());
    }
    out
}

/// `s.trim_matches(pat)`.
function trim_matches(s: string, pat: string) -> string {
    trim_end_matches(trim_start_matches(s, pat), pat)
}

/// `s.trim_start_matches(|c| pred(c))`.
function trim_start_by(s: string, pred: (string) -> bool) -> string {
    let cs = s.chars();
    let i = 0;
    while (i < cs.length() && pred(cs[i])) {
        i += 1;
    }
    s.slice(i, cs.length())
}

/// `s.trim_end_matches(|c| pred(c))`.
function trim_end_by(s: string, pred: (string) -> bool) -> string {
    let cs = s.chars();
    let j = cs.length();
    while (j > 0 && pred(cs[j - 1])) {
        j -= 1;
    }
    s.slice(0, j)
}

/// `s.trim_matches(|c| pred(c))`.
function trim_by(s: string, pred: (string) -> bool) -> string {
    trim_end_by(trim_start_by(s, pred), pred)
}

/// Rust `str::trim()` — Unicode White_Space at both ends.
function trim(s: string) -> string {
    trim_by(s, (c: string) -> bool {
        c.is_whitespace()
    })
}

/// Rust `str::trim_start()`.
function trim_start(s: string) -> string {
    trim_start_by(s, (c: string) -> bool {
        c.is_whitespace()
    })
}

/// Rust `str::trim_end()`.
function trim_end(s: string) -> string {
    trim_end_by(s, (c: string) -> bool {
        c.is_whitespace()
    })
}

/// `s.trim_matches(|c: char| c.is_ascii_whitespace())`.
function trim_ascii(s: string) -> string {
    trim_by(s, (c: string) -> bool {
        is_ascii_whitespace(c)
    })
}

/// `s.split_once(pat)`.
function split_once(s: string, pat: string) -> Tuple2<string, string>? {
    let i = s.index_of(pat);
    if (i == null) {
        return null;
    }
    Tuple2 { _0: s.slice(0, i), _1: s.slice(i + pat.length(), s.length()) }
}

/// `s.rsplit_once(pat)`.
function rsplit_once(s: string, pat: string) -> Tuple2<string, string>? {
    let i = s.last_index_of(pat);
    if (i == null) {
        return null;
    }
    Tuple2 { _0: s.slice(0, i), _1: s.slice(i + pat.length(), s.length()) }
}

/// `s.splitn(n, pat)`.
function splitn(s: string, n: int, pat: string) -> string[] {
    let out: string[] = [];
    if (n <= 0) {
        return out;
    }
    let rest = s;
    while (out.length() < n - 1) {
        let i = rest.index_of(pat);
        if (i == null) {
            break;
        }
        out.push(rest.slice(0, i));
        rest = rest.slice(i + pat.length(), rest.length());
    }
    out.push(rest);
    out
}

/// `s.find(pat)` from char offset `from` (`s[from..].find(pat).map(|i| i + from)`).
function find_from(s: string, pat: string, from: int) -> int? {
    let i = s.slice(from, s.length()).index_of(pat);
    if (i == null) {
        null
    } else {
        i + from
    }
}

/// `s.find(|c| pred(c))` — char offset of the first match.
function find_by(s: string, pred: (string) -> bool) -> int? {
    let cs = s.chars();
    let i = 0;
    while (i < cs.length()) {
        if (pred(cs[i])) {
            return i;
        }
        i += 1;
    }
    null
}

/// `s.rfind(|c| pred(c))` — char offset of the last match.
function rfind_by(s: string, pred: (string) -> bool) -> int? {
    let cs = s.chars();
    let i = cs.length() - 1;
    while (i >= 0) {
        if (pred(cs[i])) {
            return i;
        }
        i -= 1;
    }
    null
}

/// `s.contains(|c| pred(c))` / `s.chars().any(pred)`.
function any_char(s: string, pred: (string) -> bool) -> bool {
    find_by(s, pred) != null
}

/// `s.chars().all(pred)`.
function all_chars(s: string, pred: (string) -> bool) -> bool {
    for (let c in s.chars()) {
        if (!pred(c)) {
            return false;
        }
    }
    true
}

/// `s.chars().next()`.
function first_char(s: string) -> string? {
    s.at(0)
}

/// `s.chars().last()` / `s.chars().next_back()`.
function last_char(s: string) -> string? {
    s.at(-1)
}

/// `s.chars().count()` — alias of `length()`, kept for readability.
function char_count(s: string) -> int {
    s.length()
}

/// `s.char_indices()` -> list of (BYTE offset, char), exactly as Rust.
function char_indices_bytes(s: string) -> Tuple2<int, string>[] {
    let out: Tuple2<int, string>[] = [];
    let b = 0;
    for (let c in s.chars()) {
        out.push(Tuple2 { _0: b, _1: c });
        b += c.byte_length();
    }
    out
}

/// Convert a char offset into `s` to its UTF-8 byte offset.
function char_to_byte_offset(s: string, char_offset: int) -> int {
    s.slice(0, char_offset).byte_length()
}

/// Convert a UTF-8 byte offset into `s` to a char offset. `byte_offset` must
/// sit on a char boundary (as Rust's slicing requires).
function byte_to_char_offset(s: string, byte_offset: int) -> int {
    if (s.is_ascii()) {
        return byte_offset;
    }
    let b = 0;
    let i = 0;
    for (let c in s.chars()) {
        if (b >= byte_offset) {
            return i;
        }
        b += c.byte_length();
        i += 1;
    }
    i
}

/// `&s[start..end]` with BYTE offsets, exactly as Rust.
function byte_slice(s: string, start: int, end: int) -> string {
    if (s.is_ascii()) {
        return s.slice(start, end);
    }
    string.from_utf8(s.to_utf8().slice(start, end)) catch (e) {
        _ => baml.sys.panic(`std.byte_slice: byte index ${start}..${end} is not a char boundary`)
    }
}

/// `s.find(pat)` returning a BYTE offset, exactly as Rust.
function byte_find(s: string, pat: string) -> int? {
    let i = s.index_of(pat);
    if (i == null) {
        null
    } else {
        char_to_byte_offset(s, i)
    }
}

/// `s.rfind(pat)` returning a BYTE offset.
function byte_rfind(s: string, pat: string) -> int? {
    let i = s.last_index_of(pat);
    if (i == null) {
        null
    } else {
        char_to_byte_offset(s, i)
    }
}

/// `s.is_char_boundary(byte_offset)`.
function is_char_boundary(s: string, byte_offset: int) -> bool {
    let bytes = s.to_utf8();
    if (byte_offset == 0 || byte_offset == bytes.length()) {
        return true;
    }
    if (byte_offset < 0 || byte_offset > bytes.length()) {
        return false;
    }
    let b = bytes[byte_offset];
    (b & 0xC0) != 0x80
}

/// `String::from_utf8_lossy(bytes)`.
function from_utf8_lossy(bytes: uint8array) -> string {
    let direct = string.from_utf8(bytes) catch (e) {
        _ => null
    };
    if (direct != null) {
        return direct;
    }
    let out = StrBuf.new();
    let i = 0;
    let n = bytes.length();
    while (i < n) {
        let b0 = bytes[i];
        let need = if (b0 < 0x80) {
            1
        } else if (b0 >= 0xC2 && b0 <= 0xDF) {
            2
        } else if (b0 >= 0xE0 && b0 <= 0xEF) {
            3
        } else if (b0 >= 0xF0 && b0 <= 0xF4) {
            4
        } else {
            0
        };
        if (need == 0) {
            out.push("�");
            i += 1;
            continue;
        }
        if (need == 1) {
            out.push(chr_unchecked(b0));
            i += 1;
            continue;
        }
        // Validate continuation bytes (with the tighter second-byte ranges of
        // E0/ED/F0/F4 that UTF-8 requires); a maximal invalid prefix is one
        // replacement character, as Rust's lossy decoder does.
        let j = 1;
        let ok = true;
        while (j < need) {
            if (i + j >= n) {
                ok = false;
                break;
            }
            let b = bytes[i + j];
            let lo = 0x80;
            let hi = 0xBF;
            if (j == 1) {
                if (b0 == 0xE0) {
                    lo = 0xA0;
                }
                if (b0 == 0xED) {
                    hi = 0x9F;
                }
                if (b0 == 0xF0) {
                    lo = 0x90;
                }
                if (b0 == 0xF4) {
                    hi = 0x8F;
                }
            }
            if (b < lo || b > hi) {
                ok = false;
                break;
            }
            j += 1;
        }
        if (!ok) {
            out.push("�");
            i += j;
            continue;
        }
        let chunk = string.from_utf8(bytes.slice(i, i + need)) catch (e) {
            _ => "�"
        };
        out.push(chunk);
        i += need;
    }
    out.as_str()
}

/// `format!("{:?}", s)` for a `&str`: Rust's debug quoting.
function debug_str(s: string) -> string {
    let out = StrBuf.from("\"");
    for (let c in s.chars()) {
        let cp = ord(c);
        if (c == "\"") {
            out.push_str("\\\"");
        } else if (c == "\\") {
            out.push_str("\\\\");
        } else if (c == "\n") {
            out.push_str("\\n");
        } else if (c == "\r") {
            out.push_str("\\r");
        } else if (c == "\t") {
            out.push_str("\\t");
        } else if (cp == 0) {
            out.push_str("\\0");
        } else if (cp < 0x20 || cp == 0x7F) {
            out.push_str(`\\u{${hex_lower(cp)}}`);
        } else {
            out.push(c);
        }
    }
    out.push("\"");
    out.as_str()
}

/// `format!("{:x}", n)` for a non-negative int.
function hex_lower(n: int) -> string {
    if (n == 0) {
        return "0";
    }
    let digits = "0123456789abcdef".chars();
    let out = "";
    let v = n;
    while (v > 0) {
        out = digits[v % 16] + out;
        v = v / 16;
    }
    out
}

/// `format!("{:X}", n)` for a non-negative int.
function hex_upper(n: int) -> string {
    hex_lower(n).to_upper_case()
}

/// `format!("{:>width$}", s)`.
function pad_left(s: string, width: int) -> string {
    let n = s.length();
    if (n >= width) {
        s
    } else {
        " ".repeat(width - n) + s
    }
}

/// `format!("{:<width$}", s)`.
function pad_right(s: string, width: int) -> string {
    let n = s.length();
    if (n >= width) {
        s
    } else {
        s + " ".repeat(width - n)
    }
}

/// `format!("{:0width$}", n)` for an int.
function zero_pad(n: int, width: int) -> string {
    let neg = n < 0;
    let digits = if (neg) {
        (0 - n).to_string()
    } else {
        n.to_string()
    };
    let body_width = if (neg) {
        width - 1
    } else {
        width
    };
    let padded = if (digits.length() >= body_width) {
        digits
    } else {
        "0".repeat(body_width - digits.length()) + digits
    };
    if (neg) {
        "-" + padded
    } else {
        padded
    }
}

/// Concatenate string pieces (`[a, b, c].concat()`).
function concat(parts: string[]) -> string {
    join(parts, "")
}

/// `parts.join(sep)` for strings. BAML's builtin `Array.join` renders every
/// element through the generic `string.from`; this uses native `+` (a rope
/// node per append) and flattens every 2048 appends so the rope stays shallow.
function join(parts: string[], sep: string) -> string {
    let n = parts.length();
    if (n == 0) {
        return "";
    }
    let out = parts[0];
    let i = 1;
    let pending = 0;
    while (i < n) {
        if (sep == "") {
            out = out + parts[i];
        } else {
            out = out + sep + parts[i];
        }
        i += 1;
        pending += 1;
        if (pending >= 2048) {
            let _ = out.ends_with("");
            pending = 0;
        }
    }
    out
}

/// `s.split_whitespace()` — split on runs of Unicode White_Space, dropping
/// empty pieces.
function split_whitespace(s: string) -> string[] {
    let out: string[] = [];
    let cur = StrBuf.new();
    for (let c in s.chars()) {
        if (c.is_whitespace()) {
            if (!cur.is_empty()) {
                out.push(cur.take());
            }
        } else {
            cur.push(c);
        }
    }
    if (!cur.is_empty()) {
        out.push(cur.take());
    }
    out
}

/// `s.split_ascii_whitespace()`.
function split_ascii_whitespace(s: string) -> string[] {
    let out: string[] = [];
    let cur = StrBuf.new();
    for (let c in s.chars()) {
        if (is_ascii_whitespace(c)) {
            if (!cur.is_empty()) {
                out.push(cur.take());
            }
        } else {
            cur.push(c);
        }
    }
    if (!cur.is_empty()) {
        out.push(cur.take());
    }
    out
}
