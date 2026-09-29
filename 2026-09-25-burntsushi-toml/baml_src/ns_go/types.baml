// Shim: Go value types that BAML has no counterpart for.
//
// BAML has exactly one fixed-width integer type (`int`, 63-bit), `bigint`,
// and one float type (64-bit). Go's sized numeric types matter to the toml
// package (range checks on decode, formatting on encode), so they are modelled
// as single-field wrapper classes. BAML type aliases are transparent
// (`type int8 = int` would just be `int`), so a nominal class is the only way
// to make the size visible to reflection.

class Int8 {
    v: int,
    implements baml.ToString {
        function to_string(self) -> string throws never {
            self.v.to_string()
        }
    }
}

class Int16 {
    v: int,
    implements baml.ToString {
        function to_string(self) -> string throws never {
            self.v.to_string()
        }
    }
}

class Int32 {
    v: int,
    implements baml.ToString {
        function to_string(self) -> string throws never {
            self.v.to_string()
        }
    }
}

class Uint {
    v: bigint,
    implements baml.ToString {
        function to_string(self) -> string throws never {
            self.v.to_string()
        }
    }
}

class Uint8 {
    v: int,
    implements baml.ToString {
        function to_string(self) -> string throws never {
            self.v.to_string()
        }
    }
}

class Uint16 {
    v: int,
    implements baml.ToString {
        function to_string(self) -> string throws never {
            self.v.to_string()
        }
    }
}

class Uint32 {
    v: int,
    implements baml.ToString {
        function to_string(self) -> string throws never {
            self.v.to_string()
        }
    }
}

class Uint64 {
    v: bigint,
    implements baml.ToString {
        function to_string(self) -> string throws never {
            self.v.to_string()
        }
    }
}

class Float32 {
    v: float,
    implements baml.ToString {
        function to_string(self) -> string throws never {
            format_float_g(self.v, 32)
        }
    }
}

// encoding/json.Number: a string holding a JSON number literal.
class Number {
    s: string,
    implements baml.ToString {
        function to_string(self) -> string throws never {
            self.s
        }
    }
}

// Range of a sized integer kind, by Go kind name.
class IntRange {
    lo: bigint,
    hi: bigint,
}

function int_range(kind: string) -> IntRange {
    match (kind) {
        "int8" => IntRange { lo: -128n, hi: 127n },
        "int16" => IntRange { lo: -32768n, hi: 32767n },
        "int32" => IntRange { lo: -2147483648n, hi: 2147483647n },
        // BAML's `int` is 63 bits wide; this is the port's "int".
        "int" => IntRange { lo: -4611686018427387904n, hi: 4611686018427387903n },
        "int64" => IntRange { lo: -9223372036854775808n, hi: 9223372036854775807n },
        "uint8" => IntRange { lo: 0n, hi: 255n },
        "uint16" => IntRange { lo: 0n, hi: 65535n },
        "uint32" => IntRange { lo: 0n, hi: 4294967295n },
        "uint" | "uint64" => IntRange { lo: 0n, hi: 18446744073709551615n },
        _ => IntRange { lo: -9223372036854775808n, hi: 9223372036854775807n },
    }
}

// bytes.Buffer / strings.Builder: an in-memory byte sink and source,
// implementing BAML's io.Write and io.Read.
class Buffer {
    data: int[],
    read_pos: int,

    implements baml.io.Write {
        function write_some(self, data: uint8array) -> int {
            for (let b in data.to_array()) {
                self.data.push(b);
            }
            data.length()
        }

        function flush(self) -> void {
        }
    }

    implements baml.io.Read {
        function read(self, limit: int) -> uint8array? {
            if (self.read_pos >= self.data.length()) {
                return null;
            }
            let end = min(self.data.length(), self.read_pos + limit);
            let chunk = self.data.slice(self.read_pos, end);
            self.read_pos = end;
            baml.Uint8Array.from_array(chunk) catch (e) {
                _ => b""
            }
        }
    }

    // func (b *Buffer) String() string
    function string(self) -> string {
        string_of(self.data)
    }

    function len(self) -> int {
        self.data.length()
    }
}

function new_buffer() -> Buffer {
    Buffer { data: [], read_pos: 0 }
}

// bytes.NewReader / strings.NewReader.
function new_reader(s: string) -> Buffer {
    Buffer { data: bytes_of(s), read_pos: 0 }
}

function new_bytes_reader(b: int[]) -> Buffer {
    Buffer { data: b, read_pos: 0 }
}
