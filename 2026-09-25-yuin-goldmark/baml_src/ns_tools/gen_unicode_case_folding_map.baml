// Port of goldmark _tools/gen-unicode-case-folding-map.go.
//
// Downloads CaseFolding.txt from unicode.org and writes the JSON input for the
// emb-structs subcommand. Go's `json.MarshalIndent` sorts map keys; this port
// builds the objects with their keys already in sorted order and uses
// `baml.json.stringify_pretty` (whose whitespace may differ from Go's).

function unicode_case_folding_map_usage() -> string {
    "Usage of unicode-case-folding-map:\n\n  Generate input JSON data for emb-structs subcommand from unicode.org\n\n  -o string\n    \toutput file path(required)\n  -u string\n    \tunicode version (default \"15.0.0\")\n"
}

class CaseFolding {
    class_byte: int,
    from: int,
    to: int[],
}

/// Go: `strconv.ParseInt(s, 16, 32)` ignoring errors (0 on failure).
function parse_hex(s: string) -> int {
    let b = s.to_utf8();
    let v = 0;
    for (let c in b.to_array()) {
        if (!root.util.is_hex_decimal(c)) {
            return 0;
        }
        v = v * 16 + (if (c >= 48 && c <= 57) { c - 48 } else if (c >= 97) { c - 87 } else { c - 55 });
    }
    v
}

/// Go: `fmt.Sprintf("0x%x", v)`.
function hex_lower(v: int) -> string {
    if (v == 0) {
        return "0x0";
    }
    let digits = "0123456789abcdef";
    let out = "";
    let x = v;
    while (x > 0) {
        out = (digits.at(x % 16) ?? "0") + out;
        x = x / 16;
    }
    "0x" + out
}

function unicode_case_folding_map_sub_command(args: string[]) -> int {
    let flags = parse_string_flags(args, { "o": "", "u": "15.0.0" });
    if (flags == null) {
        return usage(unicode_case_folding_map_usage(), "flag provided but not defined");
    }
    let output_path = flags["o"];
    let unicode_version = flags["u"];
    if (output_path.length() == 0) {
        return usage(unicode_case_folding_map_usage(), null);
    }

    let url = "http://www.unicode.org/Public/" + unicode_version + "/ucd/CaseFolding.txt";
    let resp = baml.http.fetch(url) catch_all (e) {
        _ => {
            baml.io.println("Failed to get CaseFolding.txt");
            return 1;
        }
    };
    let bs = resp.text() catch_all (e) {
        _ => {
            baml.io.println("Failed to get CaseFolding.txt");
            return 1;
        }
    };

    let data: baml.json.json[] = [];
    for (let line0 in root.testutil.scan_lines(bs)) {
        if (line0.starts_with("#") || line0.trim().length() == 0) {
            continue;
        }
        let line = line0.split("#")[0];
        let parts = line.split(";").map((p: string) -> string { p.trim() });
        let cf = CaseFolding { class_byte: parts[1].to_utf8()[0], from: parse_hex(parts[0]), to: [] };
        for (let v in parts[2].split(" ")) {
            cf.to.push(parse_hex(v));
        }
        if (cf.class_byte != 67 && cf.class_byte != 70) { // 'C', 'F'
            continue;
        }
        let tos: baml.json.json[] = [];
        for (let v in cf.to) {
            tos.push(v.to_string());
        }
        let entry: map<string, baml.json.json> = { "From": hex_lower(cf.from), "To": tos };
        data.push(entry);
    }
    let types: map<string, baml.json.json> = { "From": "rune", "To": "[]rune" };
    let embstructmap: map<string, baml.json.json> = { "data": data, "prefix": "unicodeCaseFolding", "types": types };
    let json_data = baml.json.stringify_pretty(embstructmap);
    baml.fs.write(output_path, json_data) catch_all (e) {
        _ => {
            baml.sys.panic("cannot write " + output_path);
            0
        }
    };
    0
}
