// Shim: the pieces of Go's `fmt` and `strconv` quoting that the toml package
// uses to build error messages (%q, %x, %d, padding).

function max(a: int, b: int) -> int {
    if (a > b) { a } else { b }
}

function min(a: int, b: int) -> int {
    if (a < b) { a } else { b }
}

// fmt.Sprintf("%*s", width, s): right-align s in a field of `width` bytes.
function pad_left(s: string, width: int) -> string {
    let n = bytes_of(s).length();
    if (n >= width) {
        return s;
    }
    " ".repeat(width - n) + s
}

function pad_right(s: string, width: int) -> string {
    let n = s.length();
    if (n >= width) {
        return s;
    }
    s + " ".repeat(width - n)
}

function hex_digit(d: int) -> string {
    "0123456789abcdef".at(d) ?? "?"
}

// fmt.Sprintf("%02x", n) for 0 <= n.
function hex2(n: int) -> string {
    hex_pad(n, 2)
}

// fmt.Sprintf("%0*x", width, n) for 0 <= n.
function hex_pad(n: int, width: int) -> string {
    let s = "";
    let v = n;
    if (v == 0) {
        s = "0";
    }
    while (v > 0) {
        s = hex_digit(v % 16) + s;
        v = v / 16;
    }
    while (s.length() < width) {
        s = "0" + s;
    }
    s
}

// unicode.IsPrint, approximated for non-ASCII runes (see PORTING.md).
function is_print(r: int) -> bool {
    if (r < 128) {
        return r >= 32 && r < 127;
    }
    if (r < 160 || r == 173) {
        return false;
    }
    if (r == 160 || r == 5760 || (r >= 8192 && r <= 8207) || (r >= 8232 && r <= 8239) || r == 8287) {
        return false;
    }
    if ((r >= 8288 && r <= 8303) || r == 12288 || r == 65279 || (r >= 65529 && r <= 65531)) {
        return false;
    }
    if (r >= 55296 && r <= 57343) {
        return false;
    }
    if (r >= 57344 && r <= 63743) { // private use
        return false;
    }
    if (r > max_rune()) {
        return false;
    }
    true
}

// The escape for rune r inside a Go quoted literal with the given quote
// character (strconv.appendEscapedRune).
function escape_rune(r: int, quote_char: int) -> string {
    if (r == quote_char || r == 92) {
        return "\\" + rune_string(r);
    }
    if (is_print(r)) {
        return rune_string(r);
    }
    match (r) {
        7 => "\\a",
        8 => "\\b",
        12 => "\\f",
        10 => "\\n",
        13 => "\\r",
        9 => "\\t",
        11 => "\\v",
        _ => {
            if (r < 32 || r == 127) {
                "\\x" + hex2(r)
            } else if (!valid_rune(r)) {
                "\\ufffd"
            } else if (r < 65536) {
                "\\u" + hex_pad(r, 4)
            } else {
                "\\U" + hex_pad(r, 8)
            }
        },
    }
}

// strconv.Quote / fmt's %q for strings.
function quote(s: string) -> string {
    quote_bytes(bytes_of(s))
}

// strconv.Quote on a Go string that may contain invalid UTF-8 (given as bytes).
function quote_bytes(b: int[]) -> string {
    let out = "\"";
    let pos = 0;
    while (pos < b.length()) {
        let d = decode_rune(b, pos);
        if (d.size == 1 && d.r == rune_error()) {
            out += "\\x" + hex2(b[pos]);
        } else {
            out += escape_rune(d.r, 34);
        }
        pos += d.size;
    }
    out + "\""
}

// strconv.QuoteRune / fmt's %q for runes.
function quote_rune(r: int) -> string {
    "'" + escape_rune(r, 39) + "'"
}

// fmt.Sprintf("%v", v) for the values the tests print: error and Stringer
// (baml.ToString) implementors print through their method; slices as
// "[a b]", maps as "map[k:v ...]" with sorted keys, structs as "{f1 f2}".
function sprint_v(v: unknown) -> string {
    sprint_v_depth(v, 0)
}

// fmt.Sprintf("%v", &x) for a pointer to a struct/map/slice: "&" + %v.
function sprint_v_ptr(v: unknown) -> string {
    "&" + sprint_v(v)
}

function sprint_v_depth(v: unknown, depth: int) -> string {
    if (depth > 32) {
        return "...";
    }
    match (v) {
        null => {
            return "<nil>";
        },
        let s: string => {
            return s;
        },
        let b: bool => {
            return format_bool(b);
        },
        let i: int => {
            return i.to_string();
        },
        let i: bigint => {
            return i.to_string();
        },
        let f: float => {
            return format_float_g(f, 64);
        },
        let e: root.TomlError => {
            return e.error();
        },
        let s: baml.ToString => {
            return s.to_string();
        },
        _ => {},
    }
    let t = reflect.Type.of_value(v);
    if (t.as_array() != null) {
        let parts: string[] = [];
        for (let x in root.go_slice(v)) {
            parts.push(sprint_v_depth(x, depth + 1));
        }
        return "[" + parts.join(" ") + "]";
    }
    if (t.as_map() != null) {
        let m = root.go_map(v) ?? {};
        let keys = m.keys().sort_by((a: string, b: string) -> baml.ops.Ordering { a.cmp(b) });
        let parts: string[] = [];
        for (let k in keys) {
            parts.push(k + ":" + sprint_v_depth(m[k], depth + 1));
        }
        return "map[" + parts.join(" ") + "]";
    }
    if (t.as_class() != null) {
        let parts: string[] = [];
        for (let f in root.go_struct_fields(v)) {
            parts.push(sprint_v_depth(f.value, depth + 1));
        }
        return "{" + parts.join(" ") + "}";
    }
    if (t.as_enum() != null) {
        return root.go_string(v);
    }
    t.to_string()
}
