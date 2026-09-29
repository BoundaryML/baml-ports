// Port of encode_test.go.
//
// Anonymous Go structs become named top-level classes; `toml:"..."` tags are
// written as `@description("toml:\"...\"")`, anonymous (embedded) fields as
// `@description("go:\"embed\"")` (see encode.baml). Cases relying on Go-only
// features are marked "UNPORTABLE:" or "ADAPTED:".

// net.IP, as far as the test needs it: a TextMarshaler/TextUnmarshaler.
class IP {
    b: int[],

    implements TextMarshaler {
        function marshal_text(self) -> string? {
            let parts: string[] = [];
            for (let x in self.b) {
                parts.push(x.to_string());
            }
            parts.join(".")
        }
    }

    implements TextUnmarshaler {
        function unmarshal_text(self, text: string) -> IP throws TomlError {
            let out: int[] = [];
            for (let p in text.split(".")) {
                out.push(int.parse(p) catch (e) {
                    _ => {
                        throw GoError { msg: `invalid IP address: ${text}`, wrapped: null }
                    },
                });
            }
            IP { b: out }
        }
    }
}

class Scan {
    Age: int @description("toml:\"age\""),
    Cats: string[] @description("toml:\"cats\""),
    Pi: float @description("toml:\"pi\""),
    Perfection: int[] @description("toml:\"perfection\""),
    DOB: go.Time @description("toml:\"dob\""),
    IP: IP @description("toml:\"ip\""),
    LargeFloat: float @description("toml:\"large_float\""),
}

// strings.ReplaceAll(`...`[1:], "\t", "") for the test documents below.
function untab(s: string) -> string {
    s.replace_all("\t", "")
}

test "TestRoundtrip" {
    let doc = untab("age = 13
		cats = [\"one\", \"two\", \"three\"]
		pi = 3.145
		perfection = [11, 2, 3, 4]
		dob = 2012-01-02T15:16:17Z
		ip = \"192.168.59.254\"
		large_float = 5e+22
	");

    let want = Scan {
        Age: 13,
        Cats: ["one", "two", "three"],
        Pi: 3.145,
        Perfection: [11, 2, 3, 4],
        DOB: go.date(2012, 1, 2, 15, 16, 17, 0, go.utc()),
        IP: IP { b: [192, 168, 59, 254] },
        LargeFloat: 5e+22,
    };

    let s = decode<Scan>(doc).value;
    assert.equal(baml.json.to_string(s), baml.json.to_string(want));

    let out = marshal(s);
    assert.equal(out, doc)
}

// local date types have no offset – encoding must emit the wall clock value as
// present in the time.Time.
testset "TestEncodeRoundtripLocalDatetime" {
    let docs = [
        "d = 1987-07-05T17:45:00\n",
        "d = 1977-12-21T10:32:00.555\n",
        "d = 1987-07-05\n",
        "d = 17:45:00\n",
        "d = 10:32:00.555\n",
        "d = 2024-03-10T23:30:00\n", // Near a day boundary, a UTC shift could even roll the date over.
        "d = 23:30:00\n",
    ];
    let i = 0;
    for (let doc in docs) {
        test `#0${i}` {
            let m = decode<map<string, Any>>(doc).value;

            let buf = go.new_buffer();
            new_encoder(buf).encode(m);

            if (buf.string() != doc) {
                throw `\nhave: ${go.quote(buf.string())}\nwant: ${go.quote(doc)}`;
            }
        }
        i += 1;
    }
}

// encodeExpected: run the encoder and compare the trimmed output, or the error.
function encode_expected(val: unknown, want: string, want_err: TomlError?) -> null {
    let buf = go.new_buffer();
    let err: TomlError? = null;
    new_encoder(buf).encode(val) catch (e) {
        let te: TomlError => {
            err = te;
        },
    };
    match (want_err) {
        null => {
            if (err != null) {
                throw `Encode failed: ${err.error()}`;
            }
        },
        let we: TomlError => {
            match (err) {
                null => {
                    throw `wrong error:\nwant: ${we.error()}\nhave: <nil>`;
                },
                let e: TomlError => {
                    if (e.error() != we.error()) {
                        throw `wrong error:\nwant: ${we.error()}\nhave: ${e.error()}`;
                    }
                    return null;
                },
            }
        },
    }

    let have = buf.string().trim();
    let w = want.trim();
    if (w != have) {
        throw `\nhave:\n\t${have.replace_all("\n", "\n\t")}\nwant:\n\t${w.replace_all("\n", "\n\t")}\n`;
    }
    null
}

class Alpha {
    V: int,
}

class Beta {
    V: int,
}

class Conf {
    V: int,
    A: Alpha,
    B: Beta[],
}

test "TestEncodeArrayHashWithNormalHashOrder" {
    let val = Conf { V: 1, A: Alpha { V: 2 }, B: [Beta { V: 3 }] };
    let expected = "V = 1\n\n[A]\n  V = 2\n\n[[B]]\n  V = 3\n";
    encode_expected(val, expected, null)
}

// ---- TestEncodeOmitEmptyStruct ----

class OesT {
    Int: int,
}

class OesTpriv {
    Int: int,
    _private: int,
}

class OesTtime {
    Time: go.Time,
}

class OesF_T {
    F: OesT @description("toml:\"f,omitempty\""),
}

class OesF_Tpriv {
    F: OesTpriv @description("toml:\"f,omitempty\""),
}

class OesF_Ttime {
    F: OesTtime @description("toml:\"t,omitempty\""),
}

testset "TestEncodeOmitEmptyStruct" {
    test "#00" {
        encode_expected(OesF_T { F: OesT { Int: 0 } }, "", null)
    }
    test "#01" {
        encode_expected(OesF_T { F: OesT { Int: 1 } }, "[f]\n  Int = 1", null)
    }
    test "#02" {
        encode_expected(OesF_Tpriv { F: OesTpriv { Int: 0, _private: 0 } }, "", null)
    }
    test "#03" {
        encode_expected(OesF_Tpriv { F: OesTpriv { Int: 1, _private: 0 } }, "[f]\n  Int = 1", null)
    }
    // Private field being set also counts as "not empty".
    test "#04" {
        encode_expected(OesF_Tpriv { F: OesTpriv { Int: 0, _private: 1 } }, "[f]\n  Int = 0", null)
    }
    // time.Time is common use case, so test that explicitly.
    test "#05" {
        encode_expected(OesF_Ttime { F: OesTtime { Time: go.zero_time() } }, "", null)
    }
    test "#06" {
        encode_expected(
            OesF_Ttime { F: OesTtime { Time: go.zero_time().add(go.Duration { ns: 1 }) } },
            "[t]\n  Time = 0001-01-01T00:00:00.000000001Z",
            null,
        )
    }
}

// ---- TestEncodeOmitEmpty ----

class OeComparable {
    Bool: bool @description("toml:\"bool,omitempty\""),
}

class OeUncomparable {
    Field: string[] @description("toml:\"field,omitempty\""),
}

class OeNestedUncomparable {
    Field: OeUncomparable @description("toml:\"uncomparable,omitempty\""),
    Bool: bool @description("toml:\"bool,omitempty\""),
}

class OeSimple {
    Bool: bool @description("toml:\"bool,omitempty\""),
    String: string @description("toml:\"string,omitempty\""),
    // ADAPTED: Go's `[0]byte`; BAML has no fixed-size arrays, an always-empty
    // slice behaves the same here.
    Array: int[] @description("toml:\"array,omitempty\""),
    Slice: int[] @description("toml:\"slice,omitempty\""),
    Map: map<string, string> @description("toml:\"map,omitempty\""),
    Time: go.Time @description("toml:\"time,omitempty\""),
    Comparable1: OeComparable @description("toml:\"comparable1,omitempty\""),
    Comparable2: OeComparable @description("toml:\"comparable2,omitempty\""),
    Uncomparable1: OeUncomparable @description("toml:\"uncomparable1,omitempty\""),
    Uncomparable2: OeUncomparable @description("toml:\"uncomparable2,omitempty\""),
    NestedUncomparable1: OeNestedUncomparable @description("toml:\"nesteduncomparable1,omitempty\""),
    NestedUncomparable2: OeNestedUncomparable @description("toml:\"nesteduncomparable2,omitempty\""),
}

function oe_zero() -> OeSimple {
    OeSimple {
        Bool: false,
        String: "",
        Array: [],
        Slice: [],
        Map: {},
        Time: go.zero_time(),
        Comparable1: OeComparable { Bool: false },
        Comparable2: OeComparable { Bool: false },
        Uncomparable1: OeUncomparable { Field: [] },
        Uncomparable2: OeUncomparable { Field: [] },
        NestedUncomparable1: OeNestedUncomparable { Field: OeUncomparable { Field: [] }, Bool: false },
        NestedUncomparable2: OeNestedUncomparable { Field: OeUncomparable { Field: [] }, Bool: false },
    }
}

testset "TestEncodeOmitEmpty" {
    test "fields with omitempty are omitted when empty" {
        encode_expected(oe_zero(), "", null)
    }
    test "fields with omitempty are not omitted when non-empty" {
        let v = OeSimple {
            Bool: true,
            String: " ",
            Array: [],
            Slice: [2, 3, 4],
            Map: { "foo": "bar" },
            Time: go.date(1985, 6, 18, 15, 16, 17, 0, go.utc()),
            Comparable1: OeComparable { Bool: false },
            Comparable2: OeComparable { Bool: true },
            Uncomparable1: OeUncomparable { Field: [] },
            Uncomparable2: OeUncomparable { Field: ["XXX"] },
            NestedUncomparable1: OeNestedUncomparable { Field: OeUncomparable { Field: ["XXX"] }, Bool: false },
            NestedUncomparable2: OeNestedUncomparable { Field: OeUncomparable { Field: [] }, Bool: true },
        };
        let expected = "bool = true
string = \" \"
slice = [2, 3, 4]
time = 1985-06-18T15:16:17Z

[map]
  foo = \"bar\"

[comparable2]
  bool = true

[uncomparable2]
  field = [\"XXX\"]

[nesteduncomparable1]
  [nesteduncomparable1.uncomparable]
    field = [\"XXX\"]

[nesteduncomparable2]
  bool = true
";
        encode_expected(v, expected, null)
    }
}

// ---- TestEncodeOmitEmptyPointer ----

class OepS {
    String: string? @description("toml:\"string,omitempty\""),
}

class OepV {
    String: string? @description("toml:\"string,omitempty\""),
    Slice: string[]? @description("toml:\"slice,omitempty\""),
    Map: map<string, string>? @description("toml:\"map,omitempty\""),
    Struct: OepS? @description("toml:\"struct,omitempty\""),
}

testset "TestEncodeOmitEmptyPointer" {
    test "nil pointers" {
        encode_expected(OepV { String: null, Slice: null, Map: null, Struct: null }, "", null)
    }

    test "zero values" {
        let str = "";
        let v = OepV { String: str, Slice: [], Map: {}, Struct: OepS { String: str } };
        let want = "string = \"\"
slice = []

[map]

[struct]
  string = \"\"
";
        encode_expected(v, want, null)
    }

    test "with values" {
        let str = "XXX";
        let v = OepV { String: str, Slice: ["XXX"], Map: { "XXX": "XXX" }, Struct: OepS { String: str } };
        let want = "string = \"XXX\"
slice = [\"XXX\"]

[map]
  XXX = \"XXX\"

[struct]
  string = \"XXX\"
";
        encode_expected(v, want, null)
    }
}

class OzSimple {
    Number: int @description("toml:\"number,omitzero\""),
    Real: float @description("toml:\"real,omitzero\""),
    Unsigned: go.Uint @description("toml:\"unsigned,omitzero\""),
}

test "TestEncodeOmitZero" {
    let value = OzSimple { Number: 0, Real: 0.0, Unsigned: go.Uint { v: 0n } };
    encode_expected(value, "", null);

    value.Number = 10;
    value.Real = 20.0;
    value.Unsigned = go.Uint { v: 5n };
    let expected = "number = 10
real = 20.0
unsigned = 5
";
    encode_expected(value, expected, null)
}

class OeenSimple {
    S: int[] @description("toml:\",omitempty\""),
}

test "TestEncodeOmitemptyEmptyName" {
    let v = OeenSimple { S: [1, 2, 3] };
    encode_expected(v, "S = [1, 2, 3]\n", null)
}

// ---- TestEncodeAnonymousStruct ----

class AnonInner {
    N: int,
}

class AnonInnerLower {
    B: int,
}

class AnonEmbedded {
    Inner1: AnonInner,
    Inner2: AnonInner,
}

class AnonOuter0 {
    Inner: AnonInner @description("go:\"embed\""),
    _inner: AnonInnerLower @description("go:\"embed\""),
}

class AnonOuter1 {
    Inner: AnonInner @description("go:\"embed\" toml:\"inner\""),
    _inner: AnonInnerLower @description("go:\"embed\" toml:\"innerb\""),
}

class AnonOuter3 {
    Embedded: AnonEmbedded @description("go:\"embed\""),
}

testset "TestEncodeAnonymousStruct" {
    test "embedded anonymous untagged struct" {
        encode_expected(AnonOuter0 { Inner: AnonInner { N: 3 }, _inner: AnonInnerLower { B: 4 } }, "N = 3\nB = 4\n", null)
    }
    test "embedded anonymous tagged struct" {
        encode_expected(
            AnonOuter1 { Inner: AnonInner { N: 3 }, _inner: AnonInnerLower { B: 4 } },
            "[inner]\n  N = 3\n\n[innerb]\n  B = 4\n",
            null,
        )
    }
    test "embedded anonymous multiple fields" {
        encode_expected(
            AnonOuter3 { Embedded: AnonEmbedded { Inner1: AnonInner { N: 3 }, Inner2: AnonInner { N: 4 } } },
            "[Inner1]\n  N = 3\n\n[Inner2]\n  N = 4\n",
            null,
        )
    }
}

class AnonPtrOuter0 {
    Inner: AnonInner? @description("go:\"embed\""),
}

class AnonPtrOuter1 {
    Inner: AnonInner? @description("go:\"embed\" toml:\"inner\""),
}

testset "TestEncodeAnonymousStructPointerField" {
    test "nil anonymous untagged struct pointer field" {
        encode_expected(AnonPtrOuter0 { Inner: null }, "", null)
    }
    test "non-nil anonymous untagged struct pointer field" {
        encode_expected(AnonPtrOuter0 { Inner: AnonInner { N: 3 } }, "N = 3\n", null)
    }
    test "nil anonymous tagged struct pointer field" {
        encode_expected(AnonPtrOuter1 { Inner: null }, "", null)
    }
    test "non-nil anonymous tagged struct pointer field" {
        encode_expected(AnonPtrOuter1 { Inner: AnonInner { N: 3 } }, "[inner]\n  N = 3\n", null)
    }
}

class NestA {
    A: string,
}

class NestB {
    B: string,
}

class NestC {
    C: string,
}

class NestBC {
    B: NestB @description("go:\"embed\""),
    C: NestC @description("go:\"embed\""),
}

class NestOuter {
    A: NestA @description("go:\"embed\""),
    BC: NestBC @description("go:\"embed\""),
}

test "TestEncodeNestedAnonymousStructs" {
    let v = NestOuter { A: NestA { A: "a" }, BC: NestBC { B: NestB { B: "b" }, C: NestC { C: "c" } } };
    let expected = "A = \"a\"\nB = \"b\"\nC = \"c\"\n";
    encode_expected(v, expected, null)
}

class InnerForNextTest {
    N: int,
    implements IfaceF {
        function f(self) -> null {
            null
        }
    }
    implements IfaceG {
        function g(self) -> null {
            null
        }
    }
}

interface IfaceF {
    function f(self) -> null throws never;
}

interface IfaceG {
    function g(self) -> null throws never;
}

class AnonNoStructOuter0 {
    Inner: IfaceF @description("go:\"embed\""),
    _inner: IfaceG @description("go:\"embed\""),
    IntS: int[] @description("go:\"embed\""),
    _intS: int[] @description("go:\"embed\""),
}

test "TestEncodeAnonymousNoStructField" {
    let v0 = AnonNoStructOuter0 {
        Inner: InnerForNextTest { N: 3 },
        _inner: InnerForNextTest { N: 4 },
        IntS: [5, 6],
        _intS: [7, 8],
    };
    let expected = "IntS = [5, 6]\n\n[Inner]\n  N = 3\n";
    encode_expected(v0, expected, null)
}

class IgnoredSimple {
    Number: int @description("toml:\"-\""),
}

test "TestEncodeIgnoredFields" {
    encode_expected(IgnoredSimple { Number: 0 }, "", null)
}

class NaN64 {
    Nan: float @description("toml:\"nan\""),
    Inf: float @description("toml:\"inf\""),
}

class NaN32 {
    Nan: go.Float32 @description("toml:\"nan\""),
    Inf: go.Float32 @description("toml:\"inf\""),
}

testset "TestEncodeNaN" {
    test "#00" {
        encode_expected(NaN64 { Nan: float.nan(), Inf: float.inf() }, "nan = nan\ninf = inf\n", null)
    }
    test "#01" {
        encode_expected(NaN32 { Nan: go.Float32 { v: float.nan() }, Inf: go.Float32 { v: -float.inf() } }, "nan = nan\ninf = -inf\n", null)
    }
}

class MyStruct {
    Data: Primitive,
    DataA: int,
    DataB: string,
}

function decode_and_encode(toml: string) -> string {
    let s = decode<MyStruct>(toml).value;
    let buf = go.new_buffer();
    new_encoder(buf).encode(s);
    buf.string()
}

test "TestEncodePrimitive" {
    let original = "DataA = 1
DataB = \"bbb\"
Data = [\"Foo\", \"Bar\"]
";
    let re_encoded = decode_and_encode(decode_and_encode(original));

    if (re_encoded != original) {
        throw `re-encoded not the same as original\noriginal:   ${go.quote(original)}\nre-encoded: ${go.quote(re_encoded)}`;
    }
}

// ---- TestEncodeError ----

class ErrFuncField {
    C: () -> null throws never,
}

function encode_err(v: unknown) -> string {
    let msg = "";
    new_encoder(go.new_buffer()).encode(v) catch (e) {
        let te: TomlError => {
            msg = te.error();
        },
    };
    msg
}

testset "TestEncodeError" {
    // ADAPTED: Go uses a chan and complex128, neither of which exists in BAML;
    // a function value is the BAML value with no TOML representation.
    test "#00" {
        let f = () -> null { null };
        let err = encode_err(f);
        if (err == "") {
            throw "err is nil";
        }
        if (!err.includes("unsupported type for key '': func")) {
            throw `wrong error\nhave: ${go.quote(err)}\nwant: ${go.quote("unsupported type for key '': func")}`;
        }
    }
    test "#01" {
        let err = encode_err(ErrFuncField { C: () -> null { null } });
        if (!err.includes("unsupported type: func")) {
            throw `wrong error\nhave: ${go.quote(err)}\nwant: ${go.quote("unsupported type: func")}`;
        }
    }
    test "#02" {
        let fs: (() -> null throws never)[] = [() -> null { null }];
        let err = encode_err(fs);
        if (!err.includes("unsupported type: func")) {
            throw `wrong error\nhave: ${go.quote(err)}\nwant: ${go.quote("unsupported type: func")}`;
        }
    }
}

// ---- TestEncodeTextMarshaler / TestEncodeTOMLMarshaler ----

// This is intentionally wrong (pointer receiver)
class Sound {
    S: string,
    implements TextMarshaler {
        function marshal_text(self) -> string? {
            self.S
        }
    }
}

class Food {
    F: string[],
    implements TextMarshaler {
        function marshal_text(self) -> string? {
            self.F.join(", ")
        }
    }
}

// type fun func() — BAML cannot attach methods to a function type, so the
// function is wrapped in a class.
class Fun {
    f: () -> null throws unknown,
    implements TextMarshaler {
        function marshal_text(self) -> string? {
            "why would you do this?"
        }
    }
}

// type cplx complex128 — BAML has no complex numbers; (re, im) floats.
class Cplx {
    re: float,
    im: float,
    implements TextMarshaler {
        function marshal_text(self) -> string? {
            `(${go.format_float_f6(self.re)}+${go.format_float_f6(self.im)}i)`
        }
    }
}

function ints_value(is_: int[]) -> string {
    let buf = "<";
    let i = 0;
    for (let v in is_) {
        if (i > 0) {
            buf += ",";
        }
        buf += v.to_string();
        i += 1;
    }
    buf + ">"
}

// type ints []int
class Ints {
    v: int[],
    implements TextMarshaler {
        function marshal_text(self) -> string? {
            ints_value(self.v)
        }
    }
}

class Sound2 {
    S: string,
    implements Marshaler {
        function marshal_toml(self) -> string? {
            "\"" + self.S + "\""
        }
    }
}

// A non-addressable sound2: Go cannot call the pointer-receiver MarshalTOML
// on a struct field of a value passed to Encode, so it is encoded as a
// table. BAML has no pointer receivers or addressability; the port models
// "sound2 seen without its method set" as a class without the method.
class Sound2Value {
    S: string,
}

class Food2 {
    F: string[],
    implements Marshaler {
        function marshal_toml(self) -> string? {
            "[\"" + self.F.join("\", \"") + "\"]"
        }
    }
}

class Fun2 {
    f: () -> null throws unknown,
    implements Marshaler {
        function marshal_toml(self) -> string? {
            "\"why would you do this?\""
        }
    }
}

class Cplx2 {
    re: float,
    im: float,
    implements Marshaler {
        function marshal_toml(self) -> string? {
            `"(${go.format_float_f6(self.re)}+${go.format_float_f6(self.im)}i)"`
        }
    }
}

class Ints2 {
    v: int[],
    implements Marshaler {
        function marshal_toml(self) -> string? {
            // MarshalTOML must quote by self
            `"${ints_value(self.v)}"`
        }
    }
}

class TextMarshalerX {
    Name: string,
    Labels: map<string, string>,
    Sound: Sound,
    Sound2: Sound?,
    Food: Food,
    Food2: Food?,
    Complex: Cplx,
    Fun: Fun,
    Ints: Ints,
    Ints2: Ints2?,
}

test "TestEncodeTextMarshaler" {
    let x = TextMarshalerX {
        Name: "Goblok",
        Sound: Sound { S: "miauw" },
        Sound2: Sound { S: "miauw" },
        Labels: { "type": "cat", "color": "black" },
        Food: Food { F: ["chicken", "fish"] },
        Food2: Food { F: ["chicken", "fish"] },
        Complex: Cplx { re: 42.0, im: 666.0 },
        Fun: Fun { f: () -> null { go_panic("x") } },
        Ints: Ints { v: [1, 2, 3, 4] },
        Ints2: Ints2 { v: [1, 2, 3, 4] },
    };

    let buf = go.new_buffer();
    new_encoder(buf).encode(x);

    let want = "Name = \"Goblok\"
Sound = \"miauw\"
Sound2 = \"miauw\"
Food = \"chicken, fish\"
Food2 = \"chicken, fish\"
Complex = \"(42.000000+666.000000i)\"
Fun = \"why would you do this?\"
Ints = \"<1,2,3,4>\"
Ints2 = \"<1,2,3,4>\"

[Labels]
  color = \"black\"
  type = \"cat\"
";
    assert.equal(buf.string(), want)
}

class TomlMarshalerX {
    Name: string,
    Labels: map<string, string>,
    Sound: Sound2Value,
    Sound2: Sound2?,
    Food: Food2,
    Food2: Food2?,
    Complex: Cplx2,
    Fun: Fun2,
}

test "TestEncodeTOMLMarshaler" {
    let x = TomlMarshalerX {
        Name: "Goblok",
        Sound: Sound2Value { S: "miauw" },
        Sound2: Sound2 { S: "miauw" },
        Labels: { "type": "cat", "color": "black" },
        Food: Food2 { F: ["chicken", "fish"] },
        Food2: Food2 { F: ["chicken", "fish"] },
        Complex: Cplx2 { re: 42.0, im: 666.0 },
        Fun: Fun2 { f: () -> null { go_panic("x") } },
    };

    let buf = go.new_buffer();
    new_encoder(buf).encode(x);

    let want = "Name = \"Goblok\"
Sound2 = \"miauw\"
Food = [\"chicken\", \"fish\"]
Food2 = [\"chicken\", \"fish\"]
Complex = \"(42.000000+666.000000i)\"
Fun = \"why would you do this?\"

[Labels]
  color = \"black\"
  type = \"cat\"

[Sound]
  S = \"miauw\"
";
    assert.equal(buf.string(), want)
}

class RetNil1 {
    s: string,
    implements TextMarshaler {
        function marshal_text(self) -> string? {
            null
        }
    }
}

class RetNil2 {
    s: string,
    implements Marshaler {
        function marshal_toml(self) -> string? {
            null
        }
    }
}

class EmptyText {
    Text: RetNil1,
}

class EmptyToml {
    Text: RetNil2,
}

testset "TestEncodeEmpty" {
    test "text" {
        let buf = go.new_buffer();
        let failed = false;
        new_encoder(buf).encode(EmptyText { Text: RetNil1 { s: "" } }) catch (e) {
            _ => {
                failed = true;
            },
        };
        if (!failed) {
            throw `no error, but expected an error; output:\n${buf.string()}`;
        }
        assert.equal(buf.string(), "")
    }
    test "toml" {
        let buf = go.new_buffer();
        let failed = false;
        new_encoder(buf).encode(EmptyToml { Text: RetNil2 { s: "" } }) catch (e) {
            _ => {
                failed = true;
            },
        };
        if (!failed) {
            throw `no error, but expected an error; output:\n${buf.string()}`;
        }
        assert.equal(buf.string(), "")
    }
}

class B32Inner {
    A: string,
    B: string,
    C: string,
}

class B32Outer {
    Inner: B32Inner @description("go:\"embed\""),
}

// Would previously fail on 32bit architectures.
test "TestEncode32bit" {
    encode_expected(B32Outer { Inner: B32Inner { A: "a", B: "b", C: "c" } }, "A = \"a\"\nB = \"b\"\nC = \"c\"\n", null)
}

// Skip invalid types if it has toml:"-"
//
// https://github.com/BurntSushi/toml/issues/345
class SkipInvalid {
    Str: string @description("toml:\"str\""),
    Arr: (() -> null throws never)[] @description("toml:\"-\""),
    Map: map<string, () -> null throws never> @description("toml:\"-\""),
    Func: () -> null throws never @description("toml:\"-\""),
}

test "TestEncodeSkipInvalidType" {
    let buf = go.new_buffer();
    new_encoder(buf).encode(SkipInvalid {
        Str: "a",
        Arr: [() -> null { null }],
        Map: { "f": () -> null { null } },
        Func: () -> null { null },
    });

    let have = buf.string();
    let want = "str = \"a\"\n";
    assert.equal(have, want)
}

class DurStruct {
    Dur: go.Duration,
}

testset "TestEncodeDuration" {
    let tests = [
        0,
        go.second(),
        go.minute(),
        go.hour(),
        248 * go.hour() + 45 * go.minute() + 24 * go.second(),
        12345678 * go.nanosecond(),
        12345678 * go.second(),
        4 * go.second() + 2 * go.nanosecond(),
    ];

    for (let tt in tests) {
        let d = go.Duration { ns: tt };
        test d.to_string() {
            encode_expected(DurStruct { Dur: d }, `Dur = ${go.quote(d.to_string())}`, null)
        }
    }
}

class JsonT {
    Num: go.Number,
    NumP: go.Number?,
    Arr: go.Number[]?,
    ArrP: (go.Number?)[]?,
    Tbl: map<string, go.Number>?,
    TblP: map<string, go.Number?>?,
}

testset "TestEncodeJSONNumber" {
    test "#00" {
        let v = JsonT { Num: go.Number { s: "" }, NumP: null, Arr: null, ArrP: null, Tbl: null, TblP: null };
        let buf = go.new_buffer();
        new_encoder(buf).encode(v);
        assert.equal(buf.string().trim(), "Num = 0")
    }
    test "#01" {
        let v = JsonT {
            Num: go.Number { s: "1" },
            NumP: go.Number { s: "2" },
            Arr: [go.Number { s: "3" }],
            ArrP: [go.Number { s: "4" }],
            Tbl: { "k1": go.Number { s: "5" } },
            TblP: { "k2": go.Number { s: "6" } },
        };
        let buf = go.new_buffer();
        new_encoder(buf).encode(v);
        let want = "Num = 1
NumP = 2
Arr = [3]
ArrP = [4]

[Tbl]
  k1 = 5

[TblP]
  k2 = 6";
        assert.equal(buf.string().trim(), want)
    }
    test "#02" {
        let v = JsonT {
            Num: go.Number { s: "1.1" },
            NumP: go.Number { s: "2.2" },
            Arr: [go.Number { s: "3.3" }],
            ArrP: [go.Number { s: "4.4" }],
            Tbl: { "k1": go.Number { s: "5.5" } },
            TblP: { "k2": go.Number { s: "6.6" } },
        };
        let buf = go.new_buffer();
        new_encoder(buf).encode(v);
        let want = "Num = 1.1
NumP = 2.2
Arr = [3.3]
ArrP = [4.4]

[Tbl]
  k1 = 5.5

[TblP]
  k2 = 6.6";
        assert.equal(buf.string().trim(), want)
    }
}

// ---- TestEncode ----

class StructD {
    FieldD1: string,
    FieldD2: string,
    FieldD3: string,
}

class StructC {
    StructD: StructD @description("go:\"embed\""),
}

class StructB {
    StructC: StructC @description("go:\"embed\""),
}

class StructA {
    StructB: StructB @description("go:\"embed\""),
}

class EncEmbedded {
    Int: int @description("toml:\"_int\""),
}

class EncIntAndMap {
    I: int,
    M: map<string, int>,
}

class EncBoolField {
    BoolTrue: bool,
    BoolFalse: bool,
}

class EncIntFields {
    Int: int,
    Int8: go.Int8,
    Int16: go.Int16,
    Int32: go.Int32,
    Int64: bigint,
}

class EncUintFields {
    Uint: go.Uint,
    Uint8: go.Uint8,
    Uint16: go.Uint16,
    Uint32: go.Uint32,
    Uint64: go.Uint64,
}

class EncFloatFields {
    Float32: go.Float32,
    Float64: float,
}

class EncString {
    String: string,
}

class EncStringUnexported {
    String: string,
    _unexported: int,
}

class EncDate {
    Date: go.Time,
}

class EncArrayFields {
    IntArray0: int[],
    IntArray3: int[],
}

class EncSliceFields {
    IntSliceNil: int[]?,
    IntSlice0: int[]?,
    IntSlice3: int[]?,
}

class EncDatetimeSlice {
    DatetimeSlice: go.Time[],
}

class EncNestedArrays {
    SliceOfArrays: int[][],
    ArrayOfSlices: int[][],
    SliceOfArraysOfSlices: int[][][],
    ArrayOfSlicesOfArrays: int[][][],
    SliceOfMixedArrays: unknown[][],
    ArrayOfMixedSlices: unknown[][],
}

class EncEmptySlice {
    Empty: unknown[],
}

class EncMixed {
    Mixed: unknown[],
}

class EncMixedIntsFloats {
    MixedInts: unknown[],
    MixedFloats: unknown[],
}

class EncNilElement1 {
    NilElement1: unknown[],
}

class EncNilElement {
    NilElement: unknown[],
}

class EncStructInt {
    Int: int,
}

class EncNestedStruct {
    Struct: EncStructInt,
}

class EncNestedStructAndBool {
    Struct: EncStructInt,
    Bool: bool,
}

class Enc2NestedStructs {
    Struct1: EncStructInt,
    Struct2: EncStructInt,
}

class EncStruct3 {
    Struct3: EncStructInt?,
}

class EncDeeplyNested {
    Struct1: EncStruct3,
    Struct2: EncStruct3,
}

class EncInnerPtr {
    Inner: EncStructInt?,
}

class EncNestedNil {
    Struct: EncInnerPtr,
}

class EncEmptyStruct {
}

class EncInnerEmpty {
    Inner: EncEmptyStruct,
}

class EncNestedNoFields {
    Struct: EncInnerEmpty,
}

class EncTaggedInner {
    Int: int @description("toml:\"_int\""),
}

class EncWithTags {
    Struct: EncTaggedInner @description("toml:\"_struct\""),
    Bool: bool @description("toml:\"_bool\""),
}

class EncEmbeddedStruct {
    Embedded: EncEmbedded @description("go:\"embed\""),
}

class EncEmbeddedPtr {
    Embedded: EncEmbedded? @description("go:\"embed\""),
}

class EncNestedEmbedded {
    Struct: EncEmbeddedStruct @description("toml:\"_struct\""),
}

class EncNestedEmbeddedPtr {
    Struct: EncEmbeddedPtr @description("toml:\"_struct\""),
}

class EncEmbeddedNonStruct {
    NonStruct: int @description("go:\"embed\""),
}

class EncArrayOfTables {
    Structs: (EncStructInt?)[] @description("toml:\"struct\""),
}

class EncABC {
    A: int,
    B: int,
    C: int,
}

class EncTblInArrStruct {
    Arr: EncABC[][],
}

class EncAB {
    A: int,
    B: int,
}

class EncSliceOfSlice {
    Slices: EncStructInt[][],
}

class EncTableInArray {
    A: EncIntAndMap[],
}

class EncTableInDoubleArray {
    A: EncIntAndMap[][],
}

class EncodeCase {
    label: string,
    input: unknown,
    want_output: string,
    want_error: TomlError?,
}

function encode_cases() -> EncodeCase[] {
    let date = go.date(2014, 5, 11, 19, 30, 40, 0, go.utc());
    let date_str = "2014-05-11T19:30:40Z";

    [
        EncodeCase { label: "bool field", input: EncBoolField { BoolTrue: true, BoolFalse: false }, want_output: "BoolTrue = true\nBoolFalse = false\n", want_error: null },
        EncodeCase {
            label: "int fields",
            input: EncIntFields { Int: 1, Int8: go.Int8 { v: 2 }, Int16: go.Int16 { v: 3 }, Int32: go.Int32 { v: 4 }, Int64: 5n },
            want_output: "Int = 1\nInt8 = 2\nInt16 = 3\nInt32 = 4\nInt64 = 5\n",
            want_error: null,
        },
        EncodeCase {
            label: "uint fields",
            input: EncUintFields { Uint: go.Uint { v: 1n }, Uint8: go.Uint8 { v: 2 }, Uint16: go.Uint16 { v: 3 }, Uint32: go.Uint32 { v: 4 }, Uint64: go.Uint64 { v: 5n } },
            want_output: "Uint = 1\nUint8 = 2\nUint16 = 3\nUint32 = 4" + "\nUint64 = 5\n",
            want_error: null,
        },
        EncodeCase { label: "float fields", input: EncFloatFields { Float32: go.Float32 { v: 1.5 }, Float64: 2.5 }, want_output: "Float32 = 1.5\nFloat64 = 2.5\n", want_error: null },
        EncodeCase { label: "string field", input: EncString { String: "foo" }, want_output: "String = \"foo\"\n", want_error: null },
        EncodeCase { label: "string field with \\n escape", input: EncString { String: "foo\n" }, want_output: "String = \"foo\\n\"\n", want_error: null },
        EncodeCase { label: "string field and unexported field", input: EncStringUnexported { String: "foo", _unexported: 0 }, want_output: "String = \"foo\"\n", want_error: null },
        EncodeCase { label: "datetime field in UTC", input: EncDate { Date: date }, want_output: `Date = ${date_str}\n`, want_error: null },
        EncodeCase {
            label: "datetime field as primitive",
            // Using a map here to fail if isStructOrMap() returns true for
            // time.Time.
            input: primitive_date_map(date),
            want_output: `Date = ${date_str}\nInt = 1\n`,
            want_error: null,
        },
        // ADAPTED: [0]int / [3]int are slices in BAML.
        EncodeCase { label: "array fields", input: EncArrayFields { IntArray0: [], IntArray3: [1, 2, 3] }, want_output: "IntArray0 = []\nIntArray3 = [1, 2, 3]\n", want_error: null },
        EncodeCase { label: "slice fields", input: EncSliceFields { IntSliceNil: null, IntSlice0: [], IntSlice3: [1, 2, 3] }, want_output: "IntSlice0 = []\nIntSlice3 = [1, 2, 3]\n", want_error: null },
        EncodeCase { label: "datetime slices", input: EncDatetimeSlice { DatetimeSlice: [date, date] }, want_output: `DatetimeSlice = [${date_str}, ${date_str}]\n`, want_error: null },
        EncodeCase {
            label: "nested arrays and slices",
            input: nested_arrays_input(),
            want_output: "SliceOfArrays = [[1, 2], [3, 4]]
ArrayOfSlices = [[1, 2], [3, 4]]
SliceOfArraysOfSlices = [[[1, 2], [3, 4]], [[5, 6], [7, 8]]]
ArrayOfSlicesOfArrays = [[[1, 2], [3, 4]], [[5, 6], [7, 8]]]
SliceOfMixedArrays = [[1, 2], [\"a\", \"b\"]]
ArrayOfMixedSlices = [[1, 2], [\"a\", \"b\"]]
",
            want_error: null,
        },
        EncodeCase { label: "empty slice", input: EncEmptySlice { Empty: [] }, want_output: "Empty = []\n", want_error: null },
        EncodeCase { label: "(error) slice with element type mismatch (string and integer)", input: EncMixed { Mixed: mixed([1, "a"]) }, want_output: "Mixed = [1, \"a\"]\n", want_error: null },
        EncodeCase { label: "(error) slice with element type mismatch (integer and float)", input: EncMixed { Mixed: mixed([1, 2.5]) }, want_output: "Mixed = [1, 2.5]\n", want_error: null },
        EncodeCase {
            label: "slice with elems of differing Go types, same TOML types",
            input: EncMixedIntsFloats {
                MixedInts: mixed([
                    1, go.Int8 { v: 2 }, go.Int16 { v: 3 }, go.Int32 { v: 4 }, 5n,
                    go.Uint { v: 1n }, go.Uint8 { v: 2 }, go.Uint16 { v: 3 }, go.Uint32 { v: 4 }, go.Uint64 { v: 5n },
                ]),
                MixedFloats: mixed([go.Float32 { v: 1.5 }, 2.5]),
            },
            want_output: "MixedInts = [1, 2, 3, 4, 5, 1, 2, 3, 4, 5]\n" + "MixedFloats = [1.5, 2.5]\n",
            want_error: null,
        },
        EncodeCase {
            label: "(error) slice w/ element type mismatch (one is nested array)",
            input: EncMixed { Mixed: mixed([1, mixed([2])]) },
            want_output: "Mixed = [1, [2]]\n",
            want_error: null,
        },
        EncodeCase { label: "(error) slice with 1 nil element", input: EncNilElement1 { NilElement1: mixed([null]) }, want_output: "", want_error: err_array_nil_element() },
        EncodeCase {
            label: "(error) slice with 1 nil element (and other non-nil elements)",
            input: EncNilElement { NilElement: mixed([1, null]) },
            want_output: "",
            want_error: err_array_nil_element(),
        },
        EncodeCase { label: "simple map", input: string_int_map({ "a": 1, "b": 2 }), want_output: "a = 1\nb = 2\n", want_error: null },
        EncodeCase { label: "map with any value type", input: any_map2("a", 1, "b", "c"), want_output: "a = 1\nb = \"c\"\n", want_error: null },
        EncodeCase {
            label: "map with any value type, some of which are structs",
            input: any_map2("a", EncStructInt { Int: 2 }, "b", 1),
            want_output: "b = 1\n\n[a]\n  Int = 2\n",
            want_error: null,
        },
        EncodeCase {
            label: "nested map",
            input: nested_map(),
            want_output: "[a]\n  b = 1\n\n[c]\n  d = 2\n",
            want_error: null,
        },
        EncodeCase { label: "nested struct", input: EncNestedStruct { Struct: EncStructInt { Int: 1 } }, want_output: "[Struct]\n  Int = 1\n", want_error: null },
        EncodeCase {
            label: "nested struct and non-struct field",
            input: EncNestedStructAndBool { Struct: EncStructInt { Int: 1 }, Bool: true },
            want_output: "Bool = true\n\n[Struct]\n  Int = 1\n",
            want_error: null,
        },
        EncodeCase {
            label: "2 nested structs",
            input: Enc2NestedStructs { Struct1: EncStructInt { Int: 1 }, Struct2: EncStructInt { Int: 2 } },
            want_output: "[Struct1]\n  Int = 1\n\n[Struct2]\n  Int = 2\n",
            want_error: null,
        },
        EncodeCase {
            label: "deeply nested structs",
            input: EncDeeplyNested { Struct1: EncStruct3 { Struct3: EncStructInt { Int: 1 } }, Struct2: EncStruct3 { Struct3: null } },
            want_output: "[Struct1]\n  [Struct1.Struct3]\n    Int = 1" + "\n\n[Struct2]\n",
            want_error: null,
        },
        EncodeCase {
            label: "nested struct with nil struct elem",
            input: EncNestedNil { Struct: EncInnerPtr { Inner: null } },
            want_output: "[Struct]\n",
            want_error: null,
        },
        EncodeCase {
            label: "nested struct with no fields",
            input: EncNestedNoFields { Struct: EncInnerEmpty { Inner: EncEmptyStruct {} } },
            want_output: "[Struct]\n  [Struct.Inner]\n",
            want_error: null,
        },
        EncodeCase {
            label: "struct with tags",
            input: EncWithTags { Struct: EncTaggedInner { Int: 1 }, Bool: true },
            want_output: "_bool = true\n\n[_struct]\n  _int = 1\n",
            want_error: null,
        },
        EncodeCase { label: "embedded struct", input: EncEmbeddedStruct { Embedded: EncEmbedded { Int: 1 } }, want_output: "_int = 1\n", want_error: null },
        EncodeCase { label: "embedded *struct", input: EncEmbeddedPtr { Embedded: EncEmbedded { Int: 1 } }, want_output: "_int = 1\n", want_error: null },
        EncodeCase {
            label: "nested embedded struct",
            input: EncNestedEmbedded { Struct: EncEmbeddedStruct { Embedded: EncEmbedded { Int: 1 } } },
            want_output: "[_struct]\n  _int = 1\n",
            want_error: null,
        },
        EncodeCase {
            label: "deeply nested embedded struct", // #430
            input: StructA { StructB: StructB { StructC: StructC { StructD: StructD { FieldD1: "V1", FieldD2: "V2", FieldD3: "V3" } } } },
            want_output: "FieldD1 = \"V1\"\nFieldD2 = \"V2\"\nFieldD3 = \"V3\"\n",
            want_error: null,
        },
        EncodeCase {
            label: "nested embedded *struct",
            input: EncNestedEmbeddedPtr { Struct: EncEmbeddedPtr { Embedded: EncEmbedded { Int: 1 } } },
            want_output: "[_struct]\n  _int = 1\n",
            want_error: null,
        },
        EncodeCase { label: "embedded non-struct", input: EncEmbeddedNonStruct { NonStruct: 5 }, want_output: "NonStruct = 5\n", want_error: null },
        EncodeCase {
            label: "array of tables",
            input: EncArrayOfTables { Structs: [EncStructInt { Int: 1 }, EncStructInt { Int: 3 }] },
            want_output: "[[struct]]\n  Int = 1\n\n[[struct]]\n  Int = 3\n",
            want_error: null,
        },
        EncodeCase {
            label: "array of tables order",
            input: aot_order_input(),
            want_output: "[map]\n  zero = 5\n\n  [[map.arr]]\n    friend = 5\n",
            want_error: null,
        },
        EncodeCase { label: "empty key name", input: string_int_map({ "": 1 }), want_output: "\"\" = 1" + "\n", want_error: null },
        EncodeCase { label: "key with \\n escape", input: string_string_map({ "\n": "\n" }), want_output: "\"\\n\" = \"\\n\"" + "\n", want_error: null },

        EncodeCase { label: "empty map name", input: empty_map_name_input(), want_output: "[\"\"]\n  v = 1\n", want_error: null },
        EncodeCase {
            label: "(error) top-level slice",
            input: [EncStructInt { Int: 1 }, EncStructInt { Int: 2 }, EncStructInt { Int: 3 }],
            want_output: "",
            want_error: err_no_key(),
        },
        // UNPORTABLE: "(error) map no string key" and "... indirect" — BAML
        // map keys must be strings, so such a map cannot be constructed.

        EncodeCase {
            label: "tbl-in-arr-struct",
            input: EncTblInArrStruct { Arr: [[EncABC { A: 1, B: 2, C: 3 }, EncABC { A: 4, B: 5, C: 6 }]] },
            want_output: "Arr = [[{A = 1, B = 2, C = 3}, {A = 4, B = 5, C = 6}]]",
            want_error: null,
        },

        EncodeCase {
            label: "tbl-in-arr-map",
            input: tbl_in_arr_map_input(),
            want_output: "arr = [[{a = [\"hello\", \"world\"], b = [1.12, 4.1], c = 1, d = {e = \"E\"}, f = {A = 1, B = 2}, g = [{A = 3, B = 4}, {A = 5, B = 6}]}]]",
            want_error: null,
        },

        EncodeCase {
            label: "slice of slice",
            input: EncSliceOfSlice { Slices: [[EncStructInt { Int: 1 }], [EncStructInt { Int: 2 }], [EncStructInt { Int: 3 }]] },
            want_output: "Slices = [[{Int = 1}], [{Int = 2}], [{Int = 3}]]",
            want_error: null,
        },

        EncodeCase {
            label: "table in array",
            input: EncTableInArray { A: [EncIntAndMap { I: 1, M: { "c": 2 } }] },
            want_output: "[[A]]\n  I = 1\n  [A.M]\n    c = 2",
            want_error: null,
        },

        EncodeCase {
            label: "table in double array",
            input: EncTableInDoubleArray { A: [[EncIntAndMap { I: 1, M: { "c": 2 } }]] },
            want_output: "A = [[{I = 1, M = {c = 2}}]]",
            want_error: null,
        },
    ]
}

// Helpers building `any`-typed containers (Go's []any / map[string]any).
function mixed(xs: unknown[]) -> unknown[] {
    xs
}

function string_int_map(m: map<string, int>) -> map<string, int> {
    m
}

function string_string_map(m: map<string, string>) -> map<string, string> {
    m
}

function any_map2(k1: string, v1: unknown, k2: string, v2: unknown) -> map<string, unknown> {
    let m: map<string, unknown> = {};
    m.set(k1, v1);
    m.set(k2, v2);
    m
}

function primitive_date_map(date: go.Time) -> map<string, unknown> {
    any_map2("Date", date, "Int", 1)
}

function nested_map() -> map<string, map<string, int>> {
    { "a": { "b": 1 }, "c": { "d": 2 } }
}

function nested_arrays_input() -> EncNestedArrays {
    EncNestedArrays {
        SliceOfArrays: [[1, 2], [3, 4]],
        ArrayOfSlices: [[1, 2], [3, 4]],
        SliceOfArraysOfSlices: [[[1, 2], [3, 4]], [[5, 6], [7, 8]]],
        ArrayOfSlicesOfArrays: [[[1, 2], [3, 4]], [[5, 6], [7, 8]]],
        SliceOfMixedArrays: [mixed([1, 2]), mixed(["a", "b"])],
        ArrayOfMixedSlices: [mixed([1, 2]), mixed(["a", "b"])],
    }
}

function aot_order_input() -> map<string, unknown> {
    let arr: map<string, int>[] = [{ "friend": 5 }];
    let inner: map<string, unknown> = {};
    inner.set("zero", 5);
    inner.set("arr", arr);
    let outer: map<string, unknown> = {};
    outer.set("map", inner);
    outer
}

function empty_map_name_input() -> map<string, unknown> {
    let inner: map<string, int> = { "v": 1 };
    let outer: map<string, unknown> = {};
    outer.set("", inner);
    outer
}

function tbl_in_arr_map_input() -> map<string, unknown> {
    let d: map<string, unknown> = {};
    d.set("e", "E");
    let m: map<string, unknown> = {};
    m.set("a", mixed(["hello", "world"]));
    m.set("b", mixed([1.12, 4.1]));
    m.set("c", 1);
    m.set("d", d);
    m.set("f", EncAB { A: 1, B: 2 });
    m.set("g", [EncAB { A: 3, B: 4 }, EncAB { A: 5, B: 6 }]);
    let outer: map<string, unknown> = {};
    outer.set("arr", mixed([mixed([m])]));
    outer
}

testset "TestEncode" {
    for (let tt in encode_cases()) {
        test tt.label {
            encode_expected(tt.input, tt.want_output, tt.want_error)
        }
    }
}

class DoubleTagsS {
    A: int @description("toml:\"a\""),
    B: int @description("toml:\"a\""),
    C: int @description("toml:\"c\""),
}

test "TestEncodeDoubleTags" {
    // This writes two "a" keys to the TOML doc, which isn't valid. I don't
    // think it's worth spending effort preventing this: best we can do is issue
    // an error, and should be clear what the problem is anyway. Not even worth
    // documenting really.
    //
    // The json package silently skips these fields, which is worse behaviour
    // IMO.
    let s = DoubleTagsS { A: 1, B: 2, C: 3 };
    let buf = go.new_buffer();
    new_encoder(buf).encode(s);

    let want = "a = 1
a = 2
c = 3
";
    assert.equal(buf.string(), want)
}

class Doc1 {
    N: string,
    implements Marshaler {
        function marshal_toml(self) -> string? {
            "marshal_toml = \"" + self.N + "\""
        }
    }
}

class Doc2 {
    N: string,
    implements TextMarshaler {
        function marshal_text(self) -> string? {
            "marshal_text = \"" + self.N + "\""
        }
    }
}

// MarshalTOML and MarshalText on the top level type, rather than a field.
testset "TestMarshalDoc" {
    test "toml" {
        let buf = go.new_buffer();
        new_encoder(buf).encode(Doc1 { N: "asd" });
        assert.equal(buf.string(), "marshal_toml = \"asd\"")
    }

    test "text" {
        let buf = go.new_buffer();
        new_encoder(buf).encode(Doc2 { N: "asd" });
        assert.equal(buf.string(), "\"marshal_text = \\\"asd\\\"\"")
    }
}

test "TestMapCustomKeytype" {
    // type MyString string; type MyMap map[MyString]any — BAML type aliases
    // are transparent, so this is map<string, unknown>.
    let nested: map<string, unknown> = {};
    nested.set("k2", "b");
    let m: map<string, unknown> = {};
    m.set("k1", "a");
    m.set("nested", nested);

    let have = go.new_buffer();
    new_encoder(have).encode(m);

    let want = "k1 = \"a\"

[nested]
  k2 = \"b\"
";
    assert.equal(have.string(), want);

    let m2 = decode<map<string, Any>>(have.string()).value;
    let h = go.sprint_v(m2);
    let w = go.sprint_v(m);
    assert.equal(h, w)
}
