// Port of clap_builder/src/util/escape.rs

class Escape {
    _0: string,

    function new(s: string) -> Escape { Escape { _0: s } }

    function needs_escaping(self) -> bool {
        self._0.is_empty() || self._0.chars().some((c) -> { c.is_whitespace() })
    }

    /// `to_cow`: quote (Rust `{:?}`) when the value is empty or has whitespace
    function to_cow(self) -> string {
        if (self.needs_escaping()) { debug_str(self._0) } else { self._0 }
    }

    implements baml.ToString {
        function to_string(self) -> string throws never { self.to_cow() }
    }
}

/// Rust's `<str as Debug>::fmt`: a double-quoted string with escapes
function debug_str(s: string) -> string {
    let out: string[] = ["\""];
    for (let cp in s.to_code_points()) {
        let c = baml.String.from_code_points([cp]) catch_all (e) { _ => "" };
        if (c == "\"") {
            out.push("\\\"");
        } else if (c == "\\") {
            out.push("\\\\");
        } else if (cp == 10) {
            out.push("\\n");
        } else if (cp == 13) {
            out.push("\\r");
        } else if (cp == 9) {
            out.push("\\t");
        } else if (cp == 0) {
            out.push("\\0");
        } else if (cp < 0x20 || cp == 0x7f) {
            out.push(`\\u{${hex(cp)}}`);
        } else {
            out.push(c);
        }
    }
    out.push("\"");
    out.join("")
}

function hex(n: int) -> string {
    let digits = "0123456789abcdef";
    if (n == 0) {
        return "0";
    }
    let out = "";
    let v = n;
    while (v > 0) {
        out = (digits.at(v % 16) ?? "") + out;
        v = v / 16;
    }
    out
}

/// Rust's `Debug` for `Vec<String>`: `["a", "b"]`
function debug_str_list(items: string[]) -> string {
    `[${items.map((s) -> { debug_str(s) }).join(", ")}]`
}

/// Rust's `Debug` for `Option<String>`: `Some("a")` / `None`
function debug_opt_str(s: string?) -> string {
    if let v: string = s { `Some(${debug_str(v)})` } else { "None" }
}
