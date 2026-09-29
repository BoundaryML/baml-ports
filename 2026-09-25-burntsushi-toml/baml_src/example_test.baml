// Port of example_test.go.
//
// Go examples print to stdout and are checked against their "// Output:"
// comment. BAML has no example tests, so each example builds its output as a
// string and asserts it equals the Output block.

test "ExampleEncoder_Encode" {
    // time.Parse(time.RFC822, "14 Mar 10 18:00 UTC")
    let date = go.date(2010, 3, 14, 18, 0, 0, 0, go.utc());
    let buf = go.new_buffer();
    let hash: map<string, string> = { "key1": "val1", "key2": "val2" };
    let doc: map<string, unknown> = {};
    doc.set("date", date);
    doc.set("counts", [1, 1, 2, 3, 5, 8]);
    doc.set("hash", hash);
    new_encoder(buf).encode(doc);
    let out = buf.string() + "\n"; // fmt.Println

    assert.equal(out, "counts = [1, 1, 2, 3, 5, 8]
date = 2010-03-14T18:00:00Z

[hash]
  key1 = \"val1\"
  key2 = \"val2\"

")
}

class Band {
    Started: int,
    Albums: string[],
}

class Classics {
    Ranking: string[],
    Bands: map<string, Primitive>,
}

test "ExampleMetaData_PrimitiveDecode" {
    let toml_blob = "
		ranking = [\"Springsteen\", \"J Geils\"]

		[bands.Springsteen]
		started = 1973
		albums = [\"Greetings\", \"WIESS\", \"Born to Run\", \"Darkness\"]

		[bands.\"J Geils\"]
		started = 1970
		albums = [\"The J. Geils Band\", \"Full House\", \"Blow Your Face Out\"]
		";

    // Do the initial decode; reflection is delayed on Primitive values.
    let d = decode<Classics>(toml_blob);
    let music = d.value;
    let md = d.meta;

    let out = "";
    // MetaData still includes information on Primitive values.
    out += `Is \`bands.Springsteen\` defined? ${md.is_defined(["bands", "Springsteen"])}\n`;

    // Decode primitive data into Go values.
    for (let artist in music.Ranking) {
        // A band is a primitive value, so we need to decode it to get a real
        // `band` value.
        let prim_value = music.Bands[artist];

        let a_band = primitive_decode<Band>(md, prim_value, null);
        out += `${artist} started in ${a_band.Started}.\n`;
    }

    // Check to see if there were any fields left undecoded. Note that this
    // won't be empty before decoding the Primitive value!
    let quoted: string[] = [];
    for (let k in md.undecoded()) {
        quoted.push(go.quote(k.to_string()));
    }
    out += `Undecoded: [${quoted.join(" ")}]\n`;

    assert.equal(out, "Is `bands.Springsteen` defined? true
Springsteen started in 1973.
J Geils started in 1970.
Undecoded: []
")
}

class ServerConfig {
    Ports: int[],
    Location: string,
    Created: go.Time,
}

class Server {
    IP: string @description("toml:\"ip,omitempty\""),
    Config: ServerConfig @description("toml:\"config\""),
}

test "ExampleDecode" {
    let toml_blob = "
		# Some comments.
		[alpha]
		ip = \"10.0.0.1\"

			[alpha.config]
			Ports = [ 8001, 8002 ]
			Location = \"Toronto\"
			Created = 1987-07-05T05:45:00Z

		[beta]
		ip = \"10.0.0.2\"

			[beta.config]
			Ports = [ 9001, 9002 ]
			Location = \"New Jersey\"
			Created = 1887-01-05T05:55:00Z
	";

    // type servers map[string]server
    let config = decode<map<string, Server>>(toml_blob).value;

    let out = "";
    for (let name in ["alpha", "beta"]) {
        let s = config[name];
        out += `Server: ${name} (ip: ${s.IP}) in ${s.Config.Location} created on ${s.Config.Created.format("2006-01-02")}\n`;
        out += `Ports: ${go.sprint_v(s.Config.Ports)}\n`;
    }

    assert.equal(out, "Server: alpha (ip: 10.0.0.1) in Toronto created on 1987-07-05
Ports: [8001 8002]
Server: beta (ip: 10.0.0.2) in New Jersey created on 1887-01-05
Ports: [9001 9002]
")
}

// net/mail.Address, and a minimal mail.ParseAddress for "Name <addr>".
class MailAddress {
    Name: string,
    Address: string,
}

function parse_address(s: string) -> MailAddress throws TomlError {
    let lt = s.index_of("<");
    let gt = s.index_of(">");
    if (lt == null || gt == null) {
        throw GoError { msg: "mail: missing @ in addr-spec", wrapped: null };
    }
    MailAddress { Name: s.slice(0, lt).trim(), Address: s.slice(lt + 1, gt) }
}

// type address struct{ *mail.Address }
class Address {
    Address: MailAddress? @description("go:\"embed\""),

    implements TextUnmarshaler {
        function unmarshal_text(self, text: string) -> Address throws TomlError {
            Address { Address: parse_address(text) }
        }
    }
}

class Contacts {
    Contacts: Address[],
}

// Example Unmarshaler shows how to decode TOML strings into your own
// custom data type.
test "Example_unmarshaler" {
    let blob = "
		contacts = [
			\"Donald Duck <donald@duckburg.com>\",
			\"Scrooge McDuck <scrooge@duckburg.com>\",
		]
	";

    let contacts = decode<Contacts>(blob).value;

    let out = "";
    for (let c in contacts.Contacts) {
        let a = c.Address ?? go_panic("nil address");
        // fmt %#v
        out += `&mail.Address{Name:${go.quote(a.Name)}, Address:${go.quote(a.Address)}}\n`;
    }

    assert.equal(out, "&mail.Address{Name:\"Donald Duck\", Address:\"donald@duckburg.com\"}
&mail.Address{Name:\"Scrooge McDuck\", Address:\"scrooge@duckburg.com\"}
")
}

class StrictConf {
    Key1: string,
    Key3: string,
}

// Example StrictDecoding shows how to detect if there are keys in the TOML
// document that weren't decoded into the value given. This is useful for
// returning an error to the user if they've included extraneous fields in their
// configuration.
test "Example_strictDecoding" {
    let blob = "
		key1 = \"value1\"
		key2 = \"value2\"
		key3 = \"value3\"
	";

    let md = decode<StrictConf>(blob).meta;

    let quoted: string[] = [];
    for (let k in md.undecoded()) {
        quoted.push(go.quote(k.to_string()));
    }
    assert.equal(`Undecoded keys: [${quoted.join(" ")}]\n`, "Undecoded keys: [\"key2\"]\n")
}

interface Part {
    function name(self) -> string throws never;
}

class Valve {
    Type: string,
    ID: string,
    Size: go.Float32,
    Rating: int,
    implements Part {
        function name(self) -> string {
            `VALVE: ${self.ID}`
        }
    }
}

class Pipe {
    Type: string,
    ID: string,
    Length: go.Float32,
    Diameter: int,
    implements Part {
        function name(self) -> string {
            `PIPE: ${self.ID}`
        }
    }
}

class Cable {
    Type: string,
    ID: string,
    Length: int,
    Rating: go.Float32,
    implements Part {
        function name(self) -> string {
            `CABLE: ${self.ID}`
        }
    }
}

function as_float(v: Any?) -> float {
    match (v) {
        let f: float => f,
        _ => go_panic("interface conversion: interface {} is not float64"),
    }
}

function as_int(v: Any?) -> int {
    match (v) {
        let i: bigint => i.to_int() catch (e) {
            _ => 0
        },
        _ => go_panic("interface conversion: interface {} is not int64"),
    }
}

function as_string(v: Any?) -> string {
    match (v) {
        let s: string => s,
        _ => "",
    }
}

class Order {
    // NOTE `order.parts` is a private slice of type `part` which is an
    // interface and may only be loaded from toml using the UnmarshalTOML()
    // method of the Unmarshaler interface.
    _parts: Part[],

    implements Unmarshaler {
        function unmarshal_toml(self, data: Any?) -> Order {
            let o = Order { _parts: [] };
            let d: map<string, Any> = match (data) {
                let m: map<string, Any> => m,
                _ => {
                    let empty: map<string, Any> = {};
                    empty
                },
            };
            let parts: map<string, Any>[] = match (d.get("parts")) {
                let a: map<string, Any>[] => a,
                _ => [],
            };

            for (let p in parts) {
                let typ = as_string(p.get("type"));
                let id = as_string(p.get("id"));

                // detect the type of part and handle each case
                match (typ) {
                    "valve" => {
                        o._parts.push(Valve {
                            Type: typ,
                            ID: id,
                            Size: go.Float32 { v: as_float(p.get("size")) },
                            Rating: as_int(p.get("rating")),
                        });
                    },
                    "pipe" => {
                        o._parts.push(Pipe {
                            Type: typ,
                            ID: id,
                            Length: go.Float32 { v: as_float(p.get("length")) },
                            Diameter: as_int(p.get("diameter")),
                        });
                    },
                    "cable" => {
                        o._parts.push(Cable {
                            Type: typ,
                            ID: id,
                            Length: as_int(p.get("length")),
                            Rating: go.Float32 { v: as_float(p.get("rating")) },
                        });
                    },
                    _ => {},
                }
            }
            o
        }
    }
}

// Example UnmarshalTOML shows how to implement a struct type that knows how to
// unmarshal itself. The struct must take full responsibility for mapping the
// values passed into the struct. The method may be used with interfaces in a
// struct in cases where the actual type is not known until the data is
// examined.
test "Example_unmarshalTOML" {
    let blob = "
		[[parts]]
		type = \"valve\"
		id = \"valve-1\"
		size = 1.2
		rating = 4

		[[parts]]
		type = \"valve\"
		id = \"valve-2\"
		size = 2.1
		rating = 5

		[[parts]]
		type = \"pipe\"
		id = \"pipe-1\"
		length = 2.1
		diameter = 12

		[[parts]]
		type = \"cable\"
		id = \"cable-1\"
		length = 12
		rating = 3.1
	";

    // See example_test.go in the source for the implementation of the order
    // type.
    let o = unmarshal<Order>(go.bytes_of(blob));

    // The Go example has no Output block; the port checks what it prints.
    let out = `${o._parts.length()}\n`;
    for (let part in o._parts) {
        out += part.name() + "\n";
    }
    assert.equal(out, "4\nVALVE: valve-1\nVALVE: valve-2\nPIPE: pipe-1\nCABLE: cable-1\n")
}
