// Port of _example/example.go (namespace root.example).
//
// Run with: baml run example   (see [scripts] in baml.toml)

class Server {
    IP: string,
    Hostname: string,
    Enabled: bool,
}

class Distro {
    Name: string,
    Packages: string,
}

class Character {
    Name: string,
    Rank: string,
}

// fmtTime struct{ time.Time }. Go promotes time.Time's UnmarshalText through
// the embedded field; BAML has no method promotion, so it is forwarded
// explicitly.
class FmtTime {
    Time: root.go.Time @description("go:\"embed\""),

    implements root.TextUnmarshaler {
        function unmarshal_text(self, text: string) -> FmtTime throws root.TomlError {
            // (*time.Time).UnmarshalText: RFC 3339.
            let t = root.go.parse_in_location(root.go.rfc3339(), text, root.go.local());
            match (t) {
                null => {
                    throw root.GoError { msg: `parsing time ${root.go.quote(text)} as "2006-01-02T15:04:05Z07:00"`, wrapped: null }
                },
                let tt: root.go.Time => FmtTime { Time: tt },
            }
        }
    }

    implements baml.ToString {
        function to_string(self) -> string throws never {
            let f = "2006-01-02 15:04:05.999999999";
            if (self.Time.hour == 0) {
                f = "2006-01-02";
            }
            if (self.Time.year == 0) {
                f = "15:04:05.999999999";
            }
            if (root.go.same_location(self.Time.location(), root.go.utc())) {
                f += " UTC";
            } else {
                f += " -0700";
            }
            self.Time.format("\"" + f + "\"")
        }
    }
}

class Example {
    Title: string,
    Desc: string,
    Integers: int[],
    Floats: float[],
    Times: FmtTime[],
    Duration: root.go.Duration[],
    Distros: Distro[],
    Servers: map<string, Server>,
    Characters: map<string, Character[]>,
}

// fmt's %-11s: left-justify in a field of n characters.
function pad_right(s: string, n: int) -> string {
    if (s.length() >= n) {
        return s;
    }
    s + " ".repeat(n - s.length())
}

function main() -> null {
    let f = "example.toml";
    let exists = baml.fs.exists(f) catch (e) {
        _ => false
    };
    if (!exists) {
        f = "_example/example.toml";
    }

    let d = root.decode_file<Example>(f) catch (err) {
        let e: root.TomlError => {
            baml.io.eprintln(e.error());
            baml.sys.exit(1)
        },
    };
    let config = d.value;
    let meta = d.meta;

    let indent = " ".repeat(14);

    baml.io.print("Decoded");
    let i = 0;
    for (let field in root.go_struct_fields(config)) {
        let ind = if (i == 0) { " ".repeat(7) } else { indent };
        baml.io.print(`${ind}${pad_right(field.name, 11)} → ${root.go.sprint_v(field.value)}\n`);
        i += 1;
    }

    baml.io.print("\nKeys");
    let keys = meta.keys().sort_by((a: root.Key, b: root.Key) -> baml.ops.Ordering { a.to_string().cmp(b.to_string()) });
    i = 0;
    for (let k in keys) {
        let ind = if (i == 0) { " ".repeat(10) } else { indent };
        baml.io.print(`${ind}${pad_right(meta.type(k.parts), 10)} ${k.to_string()}\n`);
        i += 1;
    }

    baml.io.print("\nUndecoded");
    keys = meta.undecoded().sort_by((a: root.Key, b: root.Key) -> baml.ops.Ordering { a.to_string().cmp(b.to_string()) });
    i = 0;
    for (let k in keys) {
        let ind = if (i == 0) { " ".repeat(5) } else { indent };
        baml.io.print(`${ind}${pad_right(meta.type(k.parts), 10)} ${k.to_string()}\n`);
        i += 1;
    }
    null
}
