// Port of clap/examples/typed-derive/fn_parser.rs

class FnParser {
    kind: "fn-parser",

    /// Hand-written parser for tuples
    /// #[arg(short = 'D', value_name = "KEY=VALUE", value_parser = parse_key_val)]
    defines: KeyVal[],

    function debug(self) -> string {
        `FnParser { defines: [${self.defines.map((d) -> { `(${root.clap.debug_str(d.key)}, ${d.value})` }).join(", ")}] }`
    }
}

/// `(String, i32)`
class KeyVal {
    key: string,
    value: int,
}

/// Parse a single key-value pair
///
/// Rust is generic over the key and value types (`parse_key_val::<String, i32>`).
function parse_key_val(s: string) -> KeyVal throws string {
    let pos = s.index_of("=") ?? throw `invalid KEY=value: no \`=\` found in \`${s}\``;
    let value = root.clap_builder.parse_i64(s.slice(pos + 1, s.length()));
    KeyVal { key: s.slice(0, pos), value: value }
}
