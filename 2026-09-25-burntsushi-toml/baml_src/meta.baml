// Port of meta.go.

// MetaData allows access to meta information about TOML data that's not
// accessible otherwise.
//
// It allows checking if a key is defined in the TOML data, whether any keys
// were undecoded, and the TOML type of a key.
class MetaData {
    context: Key, // Used only during decoding.

    key_info: map<string, KeyInfo>,
    mapping: map<string, Any>,
    keys_list: Key[],
    decoded: map<string, bool>,
    data: int[], // Input file; for errors.

    // IsDefined reports if the key exists in the TOML data.
    //
    // The key should be specified hierarchically, for example to access the TOML
    // key "a.b.c" you would use IsDefined(["a", "b", "c"]). Keys are case
    // sensitive.
    //
    // Returns false for an empty key.
    //
    // (Go takes `key ...string`; BAML has no variadics, so it is a list.)
    function is_defined(self, key: string[]) -> bool {
        if (key.length() == 0) {
            return false;
        }

        let hash_or_val: Any = self.mapping;
        for (let k in key) {
            match (hash_or_val) {
                let hash: map<string, Any> => {
                    let v = hash.get(k);
                    if (!hash.has(k)) {
                        return false;
                    }
                    match (v) {
                        null => {
                            return false;
                        },
                        let vv: Any => {
                            hash_or_val = vv;
                        },
                    }
                },
                _ => {
                    return false;
                },
            }
        }
        true
    }

    // Type returns a string representation of the type of the key specified.
    //
    // Type will return the empty string if given an empty key or a key that does
    // not exist. Keys are case sensitive.
    function type(self, key: string[]) -> string {
        let ki = self.key_info.get(new_key(key).to_string());
        if (ki != null) {
            let t = ki.toml_type;
            if (t != null) {
                return t.type_string();
            }
        }
        ""
    }

    // Keys returns a slice of every key in the TOML data, including key groups.
    //
    // Each key is itself a slice, where the first element is the top of the
    // hierarchy and the last is the most specific. The list will have the same
    // order as the keys appeared in the TOML data.
    //
    // All keys returned are non-empty.
    function keys(self) -> Key[] {
        self.keys_list
    }

    // Undecoded returns all keys that have not been decoded in the order in which
    // they appear in the original TOML document.
    //
    // This includes keys that haven't been decoded because of a [Primitive] value.
    // Once the Primitive value is decoded, the keys will be considered decoded.
    //
    // Also note that decoding into an empty interface will result in no decoding,
    // and so no keys will be considered decoded.
    //
    // In this sense, the Undecoded keys correspond to keys in the TOML document
    // that do not have a concrete type in your representation.
    function undecoded(self) -> Key[] {
        let undecoded: Key[] = [];
        for (let key in self.keys_list) {
            if (!self.decoded.has(key.to_string())) {
                undecoded.push(key);
            }
        }
        undecoded
    }
}

// Key represents any TOML key, including key groups. Use [MetaData.Keys] to get
// values of this type.
//
// Go: `type Key []string`. BAML cannot attach methods to an array type, so the
// port wraps the slice in a class. Every operation that Go performs on the
// slice (append, [:len-1]) returns a fresh Key here.
class Key {
    parts: string[],

    implements baml.ToString {
        function to_string(self) -> string throws never {
            key_string_of(self.parts)
        }
    }

    function maybe_quoted(self, i: int) -> string {
        let k = self.parts[i];
        if (k == "") {
            return "\"\"";
        }
        for (let r in root.go.runes_of(k)) {
            if ((r >= 65 && r <= 90) || (r >= 97 && r <= 122) || (r >= 48 && r <= 57) || r == 95 || r == 45) {
                continue;
            }
            return "\"" + dbl_quoted_replace(k) + "\"";
        }
        k
    }

    // Like append(), but only increase the cap by 1.
    function add(self, piece: string) -> Key {
        let new_parts = self.parts.slice(0, self.parts.length());
        new_parts.push(piece);
        Key { parts: new_parts }
    }

    function parent(self) -> Key { // all except the last piece.
        Key { parts: self.parts.slice(0, self.parts.length() - 1) }
    }

    function last(self) -> string { // last piece of this key.
        self.parts[self.parts.length() - 1]
    }

    function len(self) -> int {
        self.parts.length()
    }
}

function new_key(parts: string[]) -> Key {
    Key { parts: parts }
}

// func (k Key) String() string
function key_string_of(k: string[]) -> string throws never {
    let b = "";
    let i = 0;
    for (let kk in k) {
        if (i > 0) {
            b += ".";
        }
        i += 1;
        if (kk == "") {
            b += "\"\"";
            continue;
        }
        let bare = true;
        for (let r in root.go.runes_of(kk)) {
            // "Inline" isBareKeyChar
            if (!((r >= 65 && r <= 90) || (r >= 97 && r <= 122) || (r >= 48 && r <= 57) || r == 95 || r == 45)) {
                bare = false;
                break;
            }
        }
        if (bare) {
            b += kk;
        } else {
            b += "\"" + dbl_quoted_replace(kk) + "\"";
        }
    }
    b
}
