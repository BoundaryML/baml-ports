// Port of decode_test.go.
//
// Go test types are anonymous structs declared inline; BAML needs named
// classes, declared at top level (prefixed with the test name). Go field names
// are kept verbatim (capitalised) so the case-insensitive key matching is
// exercised the same way.
//
// Cases that depend on Go features BAML does not have are kept as comments
// marked "UNPORTABLE:" (see PORTING_NOTES.md for the reasons).

// errorContains checks if the error message in have contains the text in
// want.
//
// This is safe when have is nil. Use an empty string for want if you want to
// test that err is nil.
function error_contains(have: TomlError?, want: string) -> bool {
    match (have) {
        null => want == "",
        let e: TomlError => {
            if (want == "") {
                return false;
            }
            e.error().includes(want)
        },
    }
}

class StructA_int {
    A: int,
}

test "TestDecodeReader" {
    let d = new_decoder(go.new_reader("a = 42")).decode<StructA_int>(null);
    let have = `${go.sprint_v(d.value)} ${go.sprint_v(d.meta.keys())} ${d.meta.type(["a"])}`;
    let want = "{42} [a] Integer";
    assert.equal(have, want)
}

// Go uses DecodeReader (deprecated.go).
test "TestDecodeReader_deprecated" {
    let d = decode_reader<StructA_int>(go.new_reader("a = 42"), null);
    let have = `${go.sprint_v(d.value)} ${go.sprint_v(d.meta.keys())} ${d.meta.type(["a"])}`;
    assert.equal(have, "{42} [a] Integer")
}

test "TestDecodeFile" {
    // os.CreateTemp: BAML has no temp-file API, so a fixed name under the
    // system temp dir is used.
    let name = "/tmp/toml-baml-test-decodefile.toml";
    let _ = baml.fs.write(name, "a = 42");

    let d = decode_file<StructA_int>(name);
    let _ = baml.fs.remove(name);

    let have = `${go.sprint_v(d.value)} ${go.sprint_v(d.meta.keys())} ${d.meta.type(["a"])}`;
    let want = "{42} [a] Integer";
    assert.equal(have, want)
}

test "TestDecodeFS" {
    let fsys: map<string, string> = { "test.toml": "a = 42" };

    let d = decode_fs<StructA_int>(fsys, "test.toml");
    let have = `${go.sprint_v(d.value)} ${go.sprint_v(d.meta.keys())} ${d.meta.type(["a"])}`;
    let want = "{42} [a] Integer";
    assert.equal(have, want)
}

class StructA_string {
    A: string,
}

testset "TestDecodeBOM" {
    let cases = [
        [255, 254, 97, 32, 61, 32, 34, 98, 34], // "\xff\xfea = \"b\""
        [254, 255, 97, 32, 61, 32, 34, 98, 34], // "\xfe\xffa = \"b\""
        [239, 187, 191, 97, 32, 61, 32, 34, 98, 34], // "\xef\xbb\xbfa = \"b\""
    ];
    let i = 0;
    for (let tt in cases) {
        test `#0${i}` {
            let s = unmarshal<StructA_string>(tt);
            if (s.A != "b") {
                throw `s.A is not "b" but ${go.quote(s.A)}`;
            }
        }
        i += 1;
    }
}

// ---- TestDecodeEmbedded ----

class Dog {
    Name: string,
}

class Cat {
    Name: string,
}

// struct{ Dog }
class EmbedDog {
    Dog: Dog @description("go:\"embed\""),
}

// struct{ *Dog }
class EmbedDogPtr {
    Dog: Dog? @description("go:\"embed\""),
}

// struct{ cat } (unexported embedded struct)
class EmbedCat {
    _cat: Cat @description("go:\"embed\""),
}

// struct{ Age } with type Age int
class EmbedAge {
    Age: int @description("go:\"embed\""),
}

test "TestDecodeEmbedded_embedded_struct" {
    let d = decode<EmbedDog>("Name = \"milton\"");
    assert.equal(go.sprint_v(d.value), go.sprint_v(EmbedDog { Dog: Dog { Name: "milton" } }))
}

test "TestDecodeEmbedded_embedded_non_nil_pointer_to_struct" {
    let d = decode<EmbedDogPtr>("Name = \"milton\"");
    assert.equal(go.sprint_v(d.value), go.sprint_v(EmbedDogPtr { Dog: Dog { Name: "milton" } }))
}

test "TestDecodeEmbedded_embedded_nil_pointer_to_struct" {
    let d = decode<EmbedDogPtr>("");
    assert.equal(go.sprint_v(d.value), go.sprint_v(EmbedDogPtr { Dog: null }))
}

test "TestDecodeEmbedded_unexported_embedded_struct" {
    let d = decode<EmbedCat>("Name = \"socks\"");
    assert.equal(go.sprint_v(d.value), go.sprint_v(EmbedCat { _cat: Cat { Name: "socks" } }))
}

test "TestDecodeEmbedded_embedded_int" {
    let d = decode<EmbedAge>("Age = -5");
    assert.equal(go.sprint_v(d.value), go.sprint_v(EmbedAge { Age: -5 }))
}

// ---- TestDecodeErrors ----

class DeInt8 {
    V: go.Int8,
}

class DeFloat32 {
    V: go.Float32,
}

class DeUint64 {
    V: go.Uint64,
}

class DeUint {
    V: go.Uint,
}

class DeString {
    V: string,
}

// interface{ ASD() }
interface ASD {
    function asd(self) -> null throws never;
}

class DeIface {
    V: ASD,
}

class VInt {
    V: int,
}

class DeStruct {
    V: VInt,
}

class NInt8 {
    N: go.Int8,
}

class DeNInt8 {
    V: NInt8,
}

class NFloat32 {
    N: go.Float32,
}

class DeNFloat32 {
    V: NFloat32,
}

class DeF64 {
    F: float,
}

class NString {
    N: string,
}

class DeNString {
    V: NString,
}

class NIface {
    N: ASD,
}

class DeNIface {
    V: NIface,
}

class NStruct {
    N: VInt,
}

class DeNStruct {
    V: NStruct,
}

class DeValueInt8 {
    Value: go.Int8,
}

class DeValueInt {
    Value: int,
}

class DeValueUint {
    Value: go.Uint,
}

function decode_errors_case(kind: string, toml: string) -> TomlError? {
    let err: TomlError? = null;
    let _ = decode_errors_run(kind, toml) catch (e) {
        let te: TomlError => {
            err = te;
            null
        },
    };
    err
}

function decode_errors_run(kind: string, toml: string) -> null throws TomlError {
    match (kind) {
        "int8" => {
            let _ = decode<DeInt8>(toml);
        },
        "float32" => {
            let _ = decode<DeFloat32>(toml);
        },
        "uint64" => {
            let _ = decode<DeUint64>(toml);
        },
        "uint" => {
            let _ = decode<DeUint>(toml);
        },
        "string" => {
            let _ = decode<DeString>(toml);
        },
        "iface" => {
            let _ = decode<DeIface>(toml);
        },
        "struct" => {
            let _ = decode<DeStruct>(toml);
        },
        "n_int8" => {
            let _ = decode<DeNInt8>(toml);
        },
        "n_float32" => {
            let _ = decode<DeNFloat32>(toml);
        },
        "f64" => {
            let _ = decode<DeF64>(toml);
        },
        "n_string" => {
            let _ = decode<DeNString>(toml);
        },
        "n_iface" => {
            let _ = decode<DeNIface>(toml);
        },
        "n_struct" => {
            let _ = decode<DeNStruct>(toml);
        },
        "value_int8" => {
            let _ = decode<DeValueInt8>(toml);
        },
        "value_int" => {
            let _ = decode<DeValueInt>(toml);
        },
        "value_uint" => {
            let _ = decode<DeValueUint>(toml);
        },
        _ => go_panic("unknown case"),
    }
    null
}

class DecodeErrorsCase {
    kind: string,
    toml: string,
    want_err: string,
}

testset "TestDecodeErrors" {
    // Go prints Go type syntax in these messages ("struct { V int }",
    // "interface { ASD() }"); the port prints the BAML type's name instead.
    let tests = [
        DecodeErrorsCase { kind: "int8", toml: "V = 999", want_err: "toml: line 1 (last key \"V\"): 999 is out of range for int8" },
        DecodeErrorsCase { kind: "float32", toml: "V = 999999999999999", want_err: "toml: line 1 (last key \"V\"): 999999999999999 is out of the safe float32 range" },
        DecodeErrorsCase { kind: "uint64", toml: "V = -1", want_err: "toml: line 1 (last key \"V\"): -1 is out of range for uint64" },
        DecodeErrorsCase { kind: "uint", toml: "V = -5", want_err: "toml: line 1 (last key \"V\"): -5 is out of range for uint" },
        DecodeErrorsCase { kind: "string", toml: "V = 5", want_err: "toml: line 1 (last key \"V\"): incompatible types: TOML value has type int64; destination has type string" },
        DecodeErrorsCase { kind: "iface", toml: "V = 999", want_err: "toml: line 1 (last key \"V\"): unsupported type ASD" },
        DecodeErrorsCase { kind: "struct", toml: "V = 999", want_err: "toml: line 1 (last key \"V\"): type mismatch for VInt: expected table but found int64" },
        // UNPORTABLE: &struct{ V [1]int }{} — BAML has no fixed-size arrays.
        DecodeErrorsCase { kind: "n_int8", toml: "V.N = 999", want_err: "toml: line 1 (last key \"V.N\"): 999 is out of range for int8" },
        DecodeErrorsCase { kind: "n_float32", toml: "V.N = 999999999999999", want_err: "toml: line 1 (last key \"V.N\"): 999999999999999 is out of the safe float32 range" },
        DecodeErrorsCase { kind: "f64", toml: "f = 999999e999999", want_err: "toml: line 1 (last key \"f\"): 999999e999999 is out of range for float64" },
        DecodeErrorsCase { kind: "n_string", toml: "V.N = 5", want_err: "toml: line 1 (last key \"V.N\"): incompatible types: TOML value has type int64; destination has type string" },
        DecodeErrorsCase { kind: "n_iface", toml: "V.N = 999", want_err: "toml: line 1 (last key \"V.N\"): unsupported type ASD" },
        DecodeErrorsCase { kind: "n_struct", toml: "V.N = 999", want_err: "toml: line 1 (last key \"V.N\"): type mismatch for VInt: expected table but found int64" },
        // UNPORTABLE: &struct{ V struct{ N [1]int } }{} — no fixed-size arrays.
        DecodeErrorsCase { kind: "value_int8", toml: "value = 500", want_err: "toml: line 1 (last key \"value\"): 500 is out of range for int8" },

        // Make sure int overflows on 32bit systems on >32bit values. Note this test
        // should only fail on 32bit systems. (BAML's int is 63-bit.)
        DecodeErrorsCase { kind: "value_int", toml: "value = 2147483648", want_err: "" },
        DecodeErrorsCase { kind: "value_uint", toml: "value = 4294967296", want_err: "" },
    ];

    let i = 0;
    for (let tt in tests) {
        let name = if (i < 10) { `#0${i}` } else { `#${i}` };
        test name {
            let err = decode_errors_case(tt.kind, tt.toml);
            if (err == null && tt.want_err != "") {
                throw "err is nil";
            }
            if (tt.want_err == "") {
                if (err != null) {
                    throw `unexpected error: ${err.error()}`;
                }
                return null;
            }
            let have = if (err != null) { err.error() } else { "" };
            if (have != tt.want_err) {
                throw `\nhave: ${go.quote(have)}\nwant: ${go.quote(tt.want_err)}`;
            }
        }
        i += 1;
    }
}

class IgnoreFields {
    Number: int @skip,
}

test "TestDecodeIgnoreFields" {
    let d = decode<IgnoreFields>("
		Number = 123
		- = 234
	 ");
    if (d.value.Number != 0) {
        throw `got: ${d.value.Number}; want 0`;
    }
}

// ---- TestDecodePointers ----

class PtrObject {
    Type: string,
    Description: string,
}

class PtrDict {
    NamedObject: map<string, PtrObject?>,
    BaseObject: PtrObject?,
    Strptr: string?,
    Strptrs: (string?)[],
}

test "TestDecodePointers" {
    let expected = PtrDict {
        Strptr: "blah",
        Strptrs: ["abc", "def"],
        NamedObject: {
            "foo": PtrObject { Type: "FOO", Description: "fooooo!!!" },
            "bar": PtrObject { Type: "BAR", Description: "ba-ba-ba-ba-barrrr!!!" },
        },
        BaseObject: PtrObject { Type: "BASE", Description: "da base" },
    };

    let d = decode<PtrDict>("
		Strptr = \"blah\"
		Strptrs = [\"abc\", \"def\"]

		[NamedObject.foo]
		Type = \"FOO\"
		Description = \"fooooo!!!\"

		[NamedObject.bar]
		Type = \"BAR\"
		Description = \"ba-ba-ba-ba-barrrr!!!\"

		[BaseObject]
		Type = \"BASE\"
		Description = \"da base\"
	");
    // reflect.DeepEqual -> compare the canonical JSON images.
    assert.equal(baml.json.to_string(d.value), baml.json.to_string(expected))
}

class BadDatetime {
    T: go.Time,
}

function decode_bad_datetime(input: string) -> bool {
    let _ = decode<BadDatetime>(input) catch (e) {
        _ => {
            return true;
        },
    };
    false
}

test "TestDecodeBadDatetime" {
    for (let s in ["123", "1230"]) {
        let input = "T = " + s;
        if (!decode_bad_datetime(input)) {
            throw `Expected invalid DateTime error for ${go.quote(s)}`;
        }
    }
}

// UNPORTABLE: TestDecodeArrayWrongSize — decodes into `Center [3]float64`;
// BAML has no fixed-size arrays, so there is no "wrong size".

// ---- TestDecodeFloatOverflow ----

class FloatTab {
    F32: go.Float32,
    F64: float,
}

class FloatOverflowCase {
    value: string,
    overflow: bool,
}

function float_overflow_err(value: string) -> TomlError? {
    let err: TomlError? = null;
    let _ = decode<FloatTab>(value) catch (e) {
        let te: TomlError => {
            err = te;
            null
        },
    };
    err
}

testset "TestDecodeFloatOverflow" {
    let max_f64 = float.max_finite();
    let max_f32 = 3.40282346638528859811704183484516925440e+38;
    let tests = [
        FloatOverflowCase { value: `F32 = ${go.format_float_f6(max_f64)}`, overflow: true },
        FloatOverflowCase { value: `F32 = ${go.format_float_f6(-max_f64)}`, overflow: true },
        FloatOverflowCase { value: `F32 = ${go.format_float_f6(max_f32 * 1.1)}`, overflow: true },
        FloatOverflowCase { value: `F32 = ${go.format_float_f6(-max_f32 * 1.1)}`, overflow: true },
        FloatOverflowCase { value: `F32 = ${max_safe_float32_int() + 1}`, overflow: true },
        FloatOverflowCase { value: `F32 = ${-max_safe_float32_int() - 1}`, overflow: true },
        FloatOverflowCase { value: `F64 = ${max_safe_float64_int() + 1}`, overflow: true },
        FloatOverflowCase { value: `F64 = ${-max_safe_float64_int() - 1}`, overflow: true },

        FloatOverflowCase { value: `F32 = ${go.format_float_f6(max_f32)}`, overflow: false },
        FloatOverflowCase { value: `F32 = ${go.format_float_f6(-max_f32)}`, overflow: false },
        FloatOverflowCase { value: `F32 = ${max_safe_float32_int()}`, overflow: false },
        FloatOverflowCase { value: `F32 = ${-max_safe_float32_int()}`, overflow: false },
        FloatOverflowCase { value: `F64 = ${go.format_float_f6(max_f64)}`, overflow: false },
        FloatOverflowCase { value: `F64 = ${go.format_float_f6(-max_f64)}`, overflow: false },
        FloatOverflowCase { value: `F64 = ${go.format_float_f6(max_f32)}`, overflow: false },
        FloatOverflowCase { value: `F64 = ${go.format_float_f6(-max_f32)}`, overflow: false },
        FloatOverflowCase { value: `F64 = ${max_safe_float64_int()}`, overflow: false },
        FloatOverflowCase { value: `F64 = ${-max_safe_float64_int()}`, overflow: false },
    ];

    let i = 0;
    for (let tt in tests) {
        let name = if (i < 10) { `#0${i}` } else { `#${i}` };
        test name {
            let err = float_overflow_err(tt.value);

            if (tt.overflow && err == null) {
                throw "expected error, but err is nil";
            }
            if ((tt.overflow && !error_contains(err, "out of the safe float") && !error_contains(err, "out of range"))
                || (!tt.overflow && err != null)) {
                throw `unexpected error:\n${go.sprint_v(err)}`;
            }
        }
        i += 1;
    }
}

// ---- TestDecodeSignbit ----

class Signbit {
    N1: float,
    N2: float,
    I1: float,
    I2: float,
    Z1: float,
    Z2: float,
    ZF1: float,
    ZF2: float,
}

// NOTE: this test is expected to fail in the port: NaN and ±Inf have no JSON
// representation, and the port can only build a class through
// baml.json.from_json (see decode.baml and PORTING_NOTES.md).
test "TestDecodeSignbit" {
    let d = decode<Signbit>("
n1 = nan
n2 = -nan
i1 = inf
i2 = -inf
z1 = 0
z2 = -0
zf1 = 0.0
zf2 = -0.0
");
    let m = d.value;

    let h = `${go.sprint_v(m.N1)} ${go.signbit(m.N1)}`;
    assert.equal(h, "NaN false");
    h = `${go.sprint_v(m.I1)} ${go.signbit(m.I1)}`;
    assert.equal(h, "+Inf false");
    h = `${go.sprint_v(m.Z1)} ${go.signbit(m.Z1)}`;
    assert.equal(h, "0 false");
    h = `${go.sprint_v(m.ZF1)} ${go.signbit(m.ZF1)}`;
    assert.equal(h, "0 false");
    h = `${go.sprint_v(m.N2)} ${go.signbit(m.N2)}`;
    assert.equal(h, "NaN true");
    h = `${go.sprint_v(m.I2)} ${go.signbit(m.I2)}`;
    assert.equal(h, "-Inf true");
    h = `${go.sprint_v(m.Z2)} ${go.signbit(m.Z2)}`;
    assert.equal(h, "0 false"); // Correct: -0 is same as 0
    h = `${go.sprint_v(m.ZF2)} ${go.signbit(m.ZF2)}`;
    assert.equal(h, "-0 true");

    let buf = go.new_buffer();
    new_encoder(buf).encode(m);

    let want = "N1 = nan
N2 = -nan
I1 = inf
I2 = -inf
Z1 = 0.0
Z2 = 0.0
ZF1 = 0.0
ZF2 = -0.0
";
    assert.equal(buf.string(), want)
}

// ---- TestDecodeSizedInts ----

class SizedTable {
    U8: go.Uint8,
    U16: go.Uint16,
    U32: go.Uint32,
    U64: go.Uint64,
    U: go.Uint,
    I8: go.Int8,
    I16: go.Int16,
    I32: go.Int32,
    I64: bigint,
    I: int,
}

test "TestDecodeSizedInts" {
    let answer = SizedTable {
        U8: go.Uint8 { v: 1 },
        U16: go.Uint16 { v: 1 },
        U32: go.Uint32 { v: 1 },
        U64: go.Uint64 { v: 1n },
        U: go.Uint { v: 1n },
        I8: go.Int8 { v: -1 },
        I16: go.Int16 { v: -1 },
        I32: go.Int32 { v: -1 },
        I64: -1n,
        I: -1,
    };
    let toml = "
	u8 = 1
	u16 = 1
	u32 = 1
	u64 = 1
	u = 1
	i8 = -1
	i16 = -1
	i32 = -1
	i64 = -1
	i = -1
	";
    let d = decode<SizedTable>(toml);
    assert.equal(go.sprint_v(d.value), go.sprint_v(answer))
}

// ---- TestDecodeTypes ----

// type NopUnmarshalTOML int
class NopUnmarshalTOML {
    v: int,
    implements Unmarshaler {
        function unmarshal_toml(self, p: Any?) -> NopUnmarshalTOML {
            NopUnmarshalTOML { v: 42 }
        }
    }
}

class TypesF {
    F: int,
}

function types_err(kind: string) -> string {
    let msg = "";
    let _ = types_run(kind) catch (e) {
        let te: TomlError => {
            msg = te.error();
            null
        },
    };
    msg
}

function types_run(kind: string) -> null throws TomlError {
    match (kind) {
        "struct_int" => {
            let _ = decode<TypesF>("F = true");
        },
        "map_int" => {
            let _ = decode<map<string, int>>("F = true");
        },
        "int" => {
            let _ = decode<int>("F = true");
        },
        "slice_int" => {
            let _ = decode<int[]>("F = true");
        },
        _ => {},
    }
    null
}

test "TestDecodeTypes_map_string_bool" {
    let d = decode<map<string, bool>>("F = true");
    assert.equal(go.sprint_v_ptr(d.value), "&map[F:true]")
}

// map[mystr]bool: a named string key type is still a string key; BAML type
// aliases are transparent, so this is the same as map<string, bool>.
test "TestDecodeTypes_map_mystr_bool" {
    let d = decode<map<string, bool>>("F = true");
    assert.equal(go.sprint_v_ptr(d.value), "&map[F:true]")
}

test "TestDecodeTypes_NopUnmarshalTOML" {
    let d = decode<NopUnmarshalTOML>("F = true");
    assert.equal(d.value.v.to_string(), "42")
}

// UNPORTABLE: map[any]bool / map[myiface]bool — BAML map keys must be strings.
// UNPORTABLE: decoding into non-pointers (3, map[string]any{}) and nil pointers
//   ((*int)(nil), (*Unmarshaler)(nil), nil) — BAML has no pointers; decode
//   returns the value instead.
// UNPORTABLE: new(map[int]string) — BAML map keys must be strings.

test "TestDecodeTypes_struct_F_int" {
    assert.is_true(types_err("struct_int").includes("toml: line 1 (last key \"F\"): incompatible types: TOML value has type bool; destination has type integer"))
}

test "TestDecodeTypes_map_string_int" {
    assert.is_true(types_err("map_int").includes("toml: line 1 (last key \"F\"): incompatible types: TOML value has type bool; destination has type integer"))
}

test "TestDecodeTypes_int" {
    assert.is_true(types_err("int").includes("toml: cannot decode to type int"))
}

test "TestDecodeTypes_slice_int" {
    assert.is_true(types_err("slice_int").includes("toml: cannot decode to type []int"))
}

// ---- TestUnmarshaler ----

class Ingredient {
    Name: string,
}

class Dish {
    Name: string,
    Price: go.Float32,
    Ingredients: Ingredient[]?,

    implements Unmarshaler {
        function unmarshal_toml(self, p: Any?) -> Dish {
            let d = Dish { Name: "", Price: go.Float32 { v: 0.0 }, Ingredients: null };
            let data: map<string, Any> = match (p) {
                let m: map<string, Any> => m,
                _ => {
                    let empty: map<string, Any> = {};
                    empty
                },
            };
            d.Name = match (data.get("name")) {
                let s: string => s,
                _ => "",
            };
            // Go: d.Price, _ = data["price"].(float32) -- the value is a float64,
            // so the assertion fails and Price stays 0.
            match (data.get("ingredients")) {
                let ingredients: map<string, Any>[] => {
                    let list: Ingredient[] = [];
                    for (let e in ingredients) {
                        let name = match (e.get("name")) {
                            let s: string => s,
                            _ => "",
                        };
                        list.push(Ingredient { Name: name });
                    }
                    d.Ingredients = list;
                },
                _ => {},
            }
            d
        }
    }
}

class Menu {
    Dishes: map<string, Dish>,

    implements Unmarshaler {
        function unmarshal_toml(self, p: Any?) -> Menu throws TomlError {
            let m = Menu { Dishes: {} };
            let data: map<string, Any> = match (p) {
                let mm: map<string, Any> => mm,
                _ => {
                    let empty: map<string, Any> = {};
                    empty
                },
            };
            let dishes: map<string, Any> = match (data.get("dishes")) {
                let mm: map<string, Any> => mm,
                _ => go_panic("interface conversion: interface {} is nil, not map[string]interface {}"),
            };
            for (let n in dishes.keys()) {
                match (dishes[n]) {
                    let d: map<string, Any> => {
                        let nd = Dish { Name: "", Price: go.Float32 { v: 0.0 }, Ingredients: null };
                        m.Dishes.set(n, nd.unmarshal_toml(d));
                    },
                    _ => {
                        throw GoError { msg: "not a dish", wrapped: null }
                    },
                }
            }
            m
        }
    }
}

test "TestUnmarshaler" {
    let toml_blob = "
[dishes.hamboogie]
name = \"Hamboogie with fries\"
price = 10.99

[[dishes.hamboogie.ingredients]]
name = \"Bread Bun\"

[[dishes.hamboogie.ingredients]]
name = \"Lettuce\"

[[dishes.hamboogie.ingredients]]
name = \"Real Beef Patty\"

[[dishes.hamboogie.ingredients]]
name = \"Tomato\"

[dishes.eggsalad]
name = \"Egg Salad with rice\"
price = 3.99

[[dishes.eggsalad.ingredients]]
name = \"Egg\"

[[dishes.eggsalad.ingredients]]
name = \"Mayo\"

[[dishes.eggsalad.ingredients]]
name = \"Rice\"
";
    let m = decode<Menu>(toml_blob).value;

    if (m.Dishes.length() != 2) {
        throw `two dishes should be loaded with UnmarshalTOML(): expected 2 but got ${m.Dishes.length()}`;
    }

    let egg_salad = m.Dishes["eggsalad"];

    if (egg_salad.Name != "Egg Salad with rice") {
        throw "expected the dish to be named 'Egg Salad with rice'";
    }

    let ingredients = egg_salad.Ingredients ?? [];
    if (ingredients.length() != 3) {
        throw `dish should be loaded with UnmarshalTOML(): expected 3 but got ${ingredients.length()}`;
    }

    let found = false;
    for (let i in ingredients) {
        if (i.Name == "Rice") {
            found = true;
            break;
        }
    }
    if (!found) {
        throw "Rice was not loaded in UnmarshalTOML()";
    }

    // test on a value - must be passed as *
    let _ = decode<Menu>(toml_blob);
}

// ---- TestDecodePrimitive ----

class PrimS {
    P: Primitive,
}

class PrimT {
    S: int[]?,
}

function prim_decode_slice(input: string, v: int[]?) -> int[]? {
    let d = decode<PrimS>(input);
    primitive_decode<int[]?>(d.meta, d.value.P, v)
}

function prim_decode_map(input: string, v: map<string, int>?) -> map<string, int>? {
    let d = decode<PrimS>(input);
    primitive_decode<map<string, int>?>(d.meta, d.value.P, v)
}

function prim_decode_struct(input: string, v: PrimT) -> PrimT {
    let d = decode<PrimS>(input);
    primitive_decode<PrimT>(d.meta, d.value.P, v)
}

// %#v-ish rendering that distinguishes a nil slice/map from an empty one.
function show_opt(v: unknown) -> string {
    match (v) {
        null => "nil",
        _ => go.sprint_v(v),
    }
}

class PrimSliceCase {
    v: int[]?,
    input: string,
    want: int[]?,
}

class PrimMapCase {
    v: map<string, int>?,
    input: string,
    want: map<string, int>?,
}

class PrimStructCase {
    v: PrimT,
    input: string,
    want: PrimT,
}

testset "TestDecodePrimitive" {
    // slices
    let slices = [
        PrimSliceCase { v: null, input: "", want: null },
        PrimSliceCase { v: [], input: "", want: [] },
        PrimSliceCase { v: [1, 2, 3], input: "", want: [1, 2, 3] },
        PrimSliceCase { v: null, input: "P = [1,2]", want: [1, 2] },
        PrimSliceCase { v: [], input: "P = [1,2]", want: [1, 2] },
        PrimSliceCase { v: [1, 2, 3], input: "P = [1,2]", want: [1, 2] },
    ];
    let i = 0;
    for (let tt in slices) {
        test `slices#${i}` {
            let have = prim_decode_slice(tt.input, tt.v);
            assert.equal(show_opt(have), show_opt(tt.want))
        }
        i += 1;
    }

    // UNPORTABLE: arrays ([2]int) — BAML has no fixed-size arrays.

    // maps
    let maps = [
        PrimMapCase { v: null, input: "", want: null },
        PrimMapCase { v: {}, input: "", want: {} },
        PrimMapCase { v: { "a": 1 }, input: "", want: { "a": 1 } },
        PrimMapCase { v: null, input: "[P]\na = 2", want: { "a": 2 } },
        PrimMapCase { v: {}, input: "[P]\na = 2", want: { "a": 2 } },
        PrimMapCase { v: { "a": 1, "b": 3 }, input: "[P]\na = 2", want: { "a": 2, "b": 3 } },
    ];
    let j = 0;
    for (let tt in maps) {
        test `maps#${j}` {
            let have = prim_decode_map(tt.input, tt.v);
            assert.equal(show_opt(have), show_opt(tt.want))
        }
        j += 1;
    }

    // structs
    let structs = [
        PrimStructCase { v: PrimT { S: null }, input: "[P]", want: PrimT { S: null } },
        PrimStructCase { v: PrimT { S: [] }, input: "[P]", want: PrimT { S: [] } },
        PrimStructCase { v: PrimT { S: [1, 2, 3] }, input: "[P]", want: PrimT { S: [1, 2, 3] } },
        PrimStructCase { v: PrimT { S: null }, input: "[P]\nS = [1,2]", want: PrimT { S: [1, 2] } },
        PrimStructCase { v: PrimT { S: [] }, input: "[P]\nS = [1,2]", want: PrimT { S: [1, 2] } },
        PrimStructCase { v: PrimT { S: [1, 2, 3] }, input: "[P]\nS = [1,2]", want: PrimT { S: [1, 2] } },
    ];
    let k = 0;
    for (let tt in structs) {
        test `structs#${k}` {
            let have = prim_decode_struct(tt.input, tt.v);
            assert.equal(show_opt(have.S), show_opt(tt.want.S))
        }
        k += 1;
    }
}

// ---- TestDecodeDatetime ----

class DatetimeD {
    D: go.Time,
}

class DatetimeCase {
    in_: string,
    want: go.Time,
}

testset "TestDecodeDatetime" {
    // Test here in addition to toml-test to ensure the TZs are correct.
    let tz7 = go.fixed_zone("", -3600 * 7);
    let tests = [
        // Offset datetime
        DatetimeCase { in_: "1979-05-27T07:32:00Z", want: go.date(1979, 5, 27, 7, 32, 0, 0, go.utc()) },
        DatetimeCase { in_: "1979-05-27T07:32:00.999999Z", want: go.date(1979, 5, 27, 7, 32, 0, 999999000, go.utc()) },
        DatetimeCase { in_: "1979-05-27T00:32:00-07:00", want: go.date(1979, 5, 27, 0, 32, 0, 0, tz7) },
        DatetimeCase { in_: "1979-05-27T00:32:00.999999-07:00", want: go.date(1979, 5, 27, 0, 32, 0, 999999000, tz7) },
        DatetimeCase { in_: "1979-05-27T00:32:00.24-07:00", want: go.date(1979, 5, 27, 0, 32, 0, 240000000, tz7) },
        DatetimeCase { in_: "1979-05-27 07:32:00Z", want: go.date(1979, 5, 27, 7, 32, 0, 0, go.utc()) },
        DatetimeCase { in_: "1979-05-27t07:32:00z", want: go.date(1979, 5, 27, 7, 32, 0, 0, go.utc()) },

        // Make sure the space between the datetime and "#" isn't lexed.
        DatetimeCase { in_: "1979-05-27T07:32:12-07:00  # c", want: go.date(1979, 5, 27, 7, 32, 12, 0, tz7) },

        // Local times.
        DatetimeCase { in_: "1979-05-27T07:32:00", want: go.date(1979, 5, 27, 7, 32, 0, 0, local_datetime()) },
        DatetimeCase { in_: "1979-05-27T07:32:00.999999", want: go.date(1979, 5, 27, 7, 32, 0, 999999000, local_datetime()) },
        DatetimeCase { in_: "1979-05-27T07:32:00.25", want: go.date(1979, 5, 27, 7, 32, 0, 250000000, local_datetime()) },
        DatetimeCase { in_: "1979-05-27", want: go.date(1979, 5, 27, 0, 0, 0, 0, local_date()) },
        DatetimeCase { in_: "07:32:00", want: go.date(0, 1, 1, 7, 32, 0, 0, local_time()) },
        DatetimeCase { in_: "07:32:00.999999", want: go.date(0, 1, 1, 7, 32, 0, 999999000, local_time()) },
    ];
    for (let tt in tests) {
        test tt.in_ {
            let input = "d = " + tt.in_;
            let d = decode<DatetimeD>(input);

            let h = d.value.D.format(go.rfc3339_nano());
            let w = tt.want.format(go.rfc3339_nano());
            if (h != w) {
                throw `\nhave: ${h}\nwant: ${w}`;
            }
        }
    }
}

// ---- TestDecodeTextUnmarshaler ----

class TuCase {
    name: string,
    toml: string,
    want: string,
}

testset "TestDecodeTextUnmarshaler" {
    // In Go the destination is `&tt.t` where tt.t is an `any` holding a struct
    // value, so Decode sees an empty interface and stores the raw map.
    let tests = [
        TuCase { name: "time.Time", toml: "Time = 1987-07-05T05:45:00Z", want: "map[Time:1987-07-05 05:45:00 +0000 UTC]" },
        TuCase { name: "*time.Time", toml: "Time = 1988-07-05T05:45:00Z", want: "map[Time:1988-07-05 05:45:00 +0000 UTC]" },
        TuCase {
            name: "map[string]time.Time",
            toml: "Times.one = 1989-07-05T05:45:00Z\nTimes.two = 1990-07-05T05:45:00Z",
            want: "map[Times:map[one:1989-07-05 05:45:00 +0000 UTC two:1990-07-05 05:45:00 +0000 UTC]]",
        },
        TuCase {
            name: "map[string]*time.Time",
            toml: "Times.one = 1989-07-05T05:45:00Z\nTimes.two = 1990-07-05T05:45:00Z",
            want: "map[Times:map[one:1989-07-05 05:45:00 +0000 UTC two:1990-07-05 05:45:00 +0000 UTC]]",
        },
    ];

    for (let tt in tests) {
        test tt.name {
            let d = decode<Any>(tt.toml);
            let have = go.sprint_v(d.value);
            assert.equal(have, tt.want)
        }
    }
}

// recordText is a TextUnmarshaler that keeps the exact bytes it was handed.
class RecordText {
    text: string,
    implements TextUnmarshaler {
        function unmarshal_text(self, b: string) -> RecordText {
            RecordText { text: b }
        }
    }
}

class RecordTextS {
    V: RecordText,
}

class TuFloatCase {
    toml: string,
    want: string,
}

testset "TestDecodeTextUnmarshalerFloat" {
    let tests = [
        TuFloatCase { toml: "v = 3.141592653589793", want: "3.141592653589793" },
        TuFloatCase { toml: "v = 1e-10", want: "1e-10" },
        TuFloatCase { toml: "v = 1.5e300", want: "1.5e+300" },
        TuFloatCase { toml: "v = 0.1", want: "0.1" },
    ];

    let i = 0;
    for (let tt in tests) {
        test `#0${i}` {
            let d = decode<RecordTextS>(tt.toml);
            if (d.value.V.text != tt.want) {
                throw `\nhave: ${d.value.V.text}\nwant: ${tt.want}`;
            }
        }
        i += 1;
    }
}

// ---- TestDecodeDuration ----

class DurT {
    T: go.Duration,
}

class DurTPtr {
    T: go.Duration?,
}

class DurTMap {
    T: map<string, go.Duration>,
}

class DurTMapPtr {
    T: map<string, go.Duration?>,
}

class DurTSlice {
    T: go.Duration[],
}

class DurTSlicePtr {
    T: (go.Duration?)[],
}

class DurationCase {
    kind: string,
    toml: string,
    want: string,
    want_err: string,
}

function duration_case(kind: string, toml: string) -> string[] {
    let err: TomlError? = null;
    let have = duration_run(kind, toml) catch (e) {
        let te: TomlError => {
            err = te;
            // The Go value is left at its zero value.
            duration_zero(kind)
        },
    };
    [have, if (err != null) { err.error() } else { "" }]
}

function duration_zero(kind: string) -> string {
    match (kind) {
        "ptr" => go.sprint_v_ptr(DurTPtr { T: null }),
        _ => go.sprint_v_ptr(DurT { T: go.Duration { ns: 0 } }),
    }
}

function duration_run(kind: string, toml: string) -> string throws TomlError {
    match (kind) {
        "val" => go.sprint_v_ptr(decode<DurT>(toml).value),
        "ptr" => go.sprint_v_ptr(decode<DurTPtr>(toml).value),
        "map" => go.sprint_v_ptr(decode<DurTMap>(toml).value),
        "mapptr" => go.sprint_v_ptr(decode<DurTMapPtr>(toml).value),
        "slice" => go.sprint_v_ptr(decode<DurTSlice>(toml).value),
        "sliceptr" => go.sprint_v_ptr(decode<DurTSlicePtr>(toml).value),
        _ => "",
    }
}

testset "TestDecodeDuration" {
    let tests = [
        DurationCase { kind: "val", toml: "t = \"0s\"", want: "&{0s}", want_err: "" },
        DurationCase { kind: "val", toml: "t = \"5m4s\"", want: "&{5m4s}", want_err: "" },
        DurationCase { kind: "val", toml: "t = \"4.000000002s\"", want: "&{4.000000002s}", want_err: "" },

        DurationCase { kind: "val", toml: "t = 0", want: "&{0s}", want_err: "" },
        DurationCase { kind: "val", toml: "t = 12345678", want: "&{12.345678ms}", want_err: "" },

        DurationCase { kind: "ptr", toml: "T = \"5s\"", want: "&{5s}", want_err: "" },
        DurationCase { kind: "ptr", toml: "T = 5", want: "&{5ns}", want_err: "" },

        DurationCase { kind: "map", toml: "T.dur = \"5s\"", want: "&{map[dur:5s]}", want_err: "" },
        DurationCase { kind: "mapptr", toml: "T.dur = \"5s\"", want: "&{map[dur:5s]}", want_err: "" },

        DurationCase { kind: "slice", toml: "T = [\"5s\"]", want: "&{[5s]}", want_err: "" },
        DurationCase { kind: "sliceptr", toml: "T = [\"5s\"]", want: "&{[5s]}", want_err: "" },

        DurationCase { kind: "val", toml: "t = \"99 bottles of beer\"", want: "&{0s}", want_err: "invalid duration: \"99 bottles of beer\"" },
        DurationCase { kind: "val", toml: "t = \"one bottle of beer\"", want: "&{0s}", want_err: "invalid duration: \"one bottle of beer\"" },
        DurationCase { kind: "val", toml: "t = 1.2", want: "&{0s}", want_err: "incompatible types:" },
        DurationCase { kind: "val", toml: "t = {}", want: "&{0s}", want_err: "incompatible types:" },
        DurationCase { kind: "val", toml: "t = []", want: "&{0s}", want_err: "incompatible types:" },
    ];

    let i = 0;
    for (let tt in tests) {
        let name = if (i < 10) { `#0${i}` } else { `#${i}` };
        test name {
            let r = duration_case(tt.kind, tt.toml);
            let have = r[0];
            let err = r[1];
            if (!(if (err == "") { tt.want_err == "" } else { tt.want_err != "" && err.includes(tt.want_err) })) {
                throw `unexpected error: ${err}`;
            }

            if (have != tt.want) {
                throw `\nhave: ${have}\nwant: ${tt.want}`;
            }
        }
        i += 1;
    }
}

// ---- TestDecodeJSONNumber ----

class JnD {
    D: go.Number,
}

class JnDPtr {
    D: go.Number?,
}

class JnDSlice {
    D: go.Number[],
}

class JnDSlicePtr {
    D: (go.Number?)[],
}

class JnDMap {
    D: map<string, go.Number>,
}

class JnDMapPtr {
    D: map<string, go.Number?>,
}

function json_number_run(kind: string, toml: string) -> string throws TomlError {
    match (kind) {
        "val" => go.sprint_v_ptr(decode<JnD>(toml).value),
        "ptr" => go.sprint_v_ptr(decode<JnDPtr>(toml).value),
        "slice" => go.sprint_v_ptr(decode<JnDSlice>(toml).value),
        "sliceptr" => go.sprint_v_ptr(decode<JnDSlicePtr>(toml).value),
        "map" => go.sprint_v_ptr(decode<JnDMap>(toml).value),
        "mapptr" => go.sprint_v_ptr(decode<JnDMapPtr>(toml).value),
        _ => "",
    }
}

function json_number_case(kind: string, toml: string) -> string[] {
    let err: TomlError? = null;
    let have = json_number_run(kind, toml) catch (e) {
        let te: TomlError => {
            err = te;
            go.sprint_v_ptr(JnD { D: go.Number { s: "" } })
        },
    };
    [have, if (err != null) { err.error() } else { "" }]
}

testset "TestDecodeJSONNumber" {
    let tests = [
        DurationCase { kind: "val", toml: "D = 2", want: "&{2}", want_err: "" },
        DurationCase { kind: "val", toml: "D = 2.002", want: "&{2.002}", want_err: "" },
        DurationCase { kind: "ptr", toml: "D = 2", want: "&{2}", want_err: "" },
        DurationCase { kind: "ptr", toml: "D = 2.002", want: "&{2.002}", want_err: "" },
        DurationCase { kind: "slice", toml: "D = [2, 3.03]", want: "&{[2 3.03]}", want_err: "" },
        DurationCase { kind: "sliceptr", toml: "D = [2, 3.03]", want: "&{[2 3.03]}", want_err: "" },
        DurationCase { kind: "map", toml: "D = {a=2, b=3.03}", want: "&{map[a:2 b:3.03]}", want_err: "" },
        DurationCase { kind: "mapptr", toml: "D = {a=2, b=3.03}", want: "&{map[a:2 b:3.03]}", want_err: "" },

        DurationCase { kind: "val", toml: "D = {}", want: "&{}", want_err: "incompatible types" },
        DurationCase { kind: "val", toml: "D = []", want: "&{}", want_err: "incompatible types" },
        DurationCase { kind: "val", toml: "D = \"2\"", want: "&{}", want_err: "incompatible types" },
    ];

    let i = 0;
    for (let tt in tests) {
        let name = if (i < 10) { `#0${i}` } else { `#${i}` };
        test name {
            let r = json_number_case(tt.kind, tt.toml);
            let have = r[0];
            let err = r[1];
            if (!(if (err == "") { tt.want_err == "" } else { tt.want_err != "" && err.includes(tt.want_err) })) {
                throw `unexpected error: ${err}`;
            }
            if (have != tt.want) {
                throw `\nhave: ${have}\nwant: ${tt.want}`;
            }
        }
        i += 1;
    }
}

test "TestMetaDotConflict" {
    let d = decode<map<string, Any>>("
		\"a.b\" = \"str\"
		a.b   = 1
		\"\"    = 2
	");

    let want = "\"a.b\"=String; a.b=Integer; \"\"=Integer";
    let have = "";
    let i = 0;
    for (let k in d.meta.keys()) {
        if (i > 0) {
            have += "; ";
        }
        have += k.to_string() + "=" + d.meta.type(k.parts);
        i += 1;
    }
    assert.equal(have, want)
}

// ---- TestCustomEncode / TestCustomDecode (#341) ----

// type Enum int, with NoValue = 0 and OtherValue = 1.
class Enum {
    v: int,

    function value(self) -> string {
        match (self.v) {
            1 => "OTHER_VALUE",
            _ => "",
        }
    }

    implements Marshaler {
        function marshal_toml(self) -> string? {
            "\"" + self.value() + "\""
        }
    }

    implements Unmarshaler {
        function unmarshal_toml(self, value: Any?) -> Enum throws TomlError {
            let s_value = match (value) {
                let s: string => s,
                _ => {
                    throw GoError { msg: `value ${go.sprint_v(value)} is not a string type`, wrapped: null }
                },
            };
            for (let e in [Enum { v: 0 }, Enum { v: 1 }]) {
                if (e.value() == s_value) {
                    return e;
                }
            }
            throw GoError { msg: "invalid enum value", wrapped: null }
        }
    }
}

class InnerInt {
    _value: int,

    implements Marshaler {
        function marshal_toml(self) -> string? {
            self._value.to_string()
        }
    }

    implements Unmarshaler {
        function unmarshal_toml(self, value: Any?) -> InnerInt throws TomlError {
            let i_value = match (value) {
                let i: bigint => i,
                _ => {
                    throw GoError { msg: `value ${go.sprint_v(value)} is not a int type`, wrapped: null }
                },
            };
            InnerInt { _value: i_value.to_int() catch (e) { _ => 0 } }
        }
    }
}

class InnerArrayString {
    _value: string[],

    implements Marshaler {
        function marshal_toml(self) -> string? {
            "[\"" + self._value.join("\", \"") + "\"]"
        }
    }

    implements Unmarshaler {
        function unmarshal_toml(self, value: Any?) -> InnerArrayString throws TomlError {
            let out = InnerArrayString { _value: [] };
            if (value != null) {
                let as_value: Any[] = match (value) {
                    let a: Any[] => a,
                    _ => {
                        throw GoError { msg: `value ${go.sprint_v(value)} is not a [] type`, wrapped: null }
                    },
                };
                for (let v in as_value) {
                    match (v) {
                        let s: string => out._value.push(s),
                        _ => go_panic("interface conversion: interface {} is not string"),
                    }
                }
            }
            out
        }
    }
}

class Outer {
    Int: InnerInt?,
    Enum: Enum?,
    Slice: InnerArrayString?,
}

test "TestCustomEncode" {
    let enum_ = Enum { v: 1 };
    let outer = Outer {
        Int: InnerInt { _value: 10 },
        Enum: enum_,
        Slice: InnerArrayString { _value: ["text1", "text2"] },
    };

    let buf = go.new_buffer();
    new_encoder(buf).encode(outer);

    let have = buf.string().trim();
    let want = "Int = 10
Enum = \"OTHER_VALUE\"
Slice = [\"text1\", \"text2\"]";
    assert.equal(have, want)
}

test "TestCustomDecode" {
    let d = decode<Outer>("
		Int = 10
		Enum = \"OTHER_VALUE\"
		Slice = [\"text1\", \"text2\"]
	");
    let outer = d.value;

    let int_ = outer.Int ?? go_panic("Int is nil");
    if (int_._value != 10) {
        throw `\nhave:\n${int_._value}\nwant:\n10\n`;
    }
    let enum_ = outer.Enum ?? go_panic("Enum is nil");
    if (enum_.v != 1) {
        throw `\nhave:\n${enum_.v}\nwant:\n1\n`;
    }
    let slice = outer.Slice ?? go_panic("Slice is nil");
    if (go.sprint_v(slice._value) != go.sprint_v(["text1", "text2"])) {
        throw `\nhave:\n${go.sprint_v(slice._value)}\nwant:\n[text1 text2]\n`;
    }
    if (d.meta.undecoded().length() > 0) {
        throw `\ncustom decode leaves unencoded fields: ${go.sprint_v(d.meta.undecoded())}\n`;
    }
}

// TODO: this should be improved for v2:
// https://github.com/BurntSushi/toml/issues/384
class DoubleTags {
    A: int @description("toml:\"a\""),
    B: int @description("toml:\"a\""),
    C: int @description("toml:\"c\""),
}

test "TestDecodeDoubleTags" {
    let d = decode<DoubleTags>("
		a = 1
		b = 2
		c = 3
	");
    let want = "{0 0 3}";
    let have = go.sprint_v(d.value);
    assert.equal(have, want)
}

class MetaKeysCase {
    in_: string,
    want: string[][],
}

testset "TestMetaKeys" {
    let tests = [
        MetaKeysCase { in_: "", want: [] },
        MetaKeysCase { in_: "b=1\na=1", want: [["b"], ["a"]] },
        MetaKeysCase { in_: "a.b=1\na.a=1", want: [["a", "b"], ["a", "a"]] }, // TODO: should include "a"
        MetaKeysCase { in_: "[tbl]\na=1", want: [["tbl"], ["tbl", "a"]] },
        MetaKeysCase { in_: "[tbl]\na.a=1", want: [["tbl"], ["tbl", "a", "a"]] }, // TODO: should include "a.a"
        MetaKeysCase { in_: "tbl={a=1}", want: [["tbl"], ["tbl", "a"]] },
        MetaKeysCase { in_: "tbl={a={b=1}}", want: [["tbl"], ["tbl", "a"], ["tbl", "a", "b"]] },
    ];

    let i = 0;
    for (let tt in tests) {
        test `#0${i}` {
            let d = decode<Any>(tt.in_);

            let have: string[][] = [];
            for (let k in d.meta.keys()) {
                have.push(k.parts);
            }
            assert.equal(baml.json.to_string(have), baml.json.to_string(tt.want))
        }
        i += 1;
    }
}

// Go starts 10 goroutines that each decode testdata/Cargo.toml. The port
// uses `spawn` for the same concurrency.
function decode_cargo(doc: int[]) -> bool {
    let _ = unmarshal<map<string, Any>>(doc) catch (e) {
        let te: TomlError => go_panic(te.error()),
    };
    true
}

test "TestDecodeParallel" {
    let f = baml.fs.open("testdata/Cargo.toml", "r");
    let doc = f.bytes().to_array();
    let _ = f.close();

    let futures = [];
    let i = 0;
    while (i < 10) {
        futures.push(spawn { decode_cargo(doc) });
        i += 1;
    }
    for (let fut in futures) {
        assert.is_true(await fut);
    }
}

class UnmarshalTOMLNoop {
    implements Unmarshaler {
        function unmarshal_toml(self, data: Any?) -> UnmarshalTOMLNoop {
            UnmarshalTOMLNoop {}
        }
    }
}

class CustomStructMarkedDecoded {
    Str: UnmarshalTOMLNoop @description("toml:\"str\""),
    Int: UnmarshalTOMLNoop @description("toml:\"int\""),
    Arr: UnmarshalTOMLNoop @description("toml:\"arr\""),
    Tbl: UnmarshalTOMLNoop @description("toml:\"tbl\""),
    Aot: UnmarshalTOMLNoop @description("toml:\"aot\""),
    Nested: UnmarshalTOMLNoop @description("toml:\"nested\""),
}

test "TestDecodeCustomStructMarkedDecoded" {
    let d = decode<CustomStructMarkedDecoded>("
		str = \"bar\"
		int   = 1
		arr = [2]

		[tbl]
		b = 3
		inline = {c = 4}

		[[aot]]
		a = 1
		[[aot]]
		a = 1

		[[nested.a]]
		e = 5
		[[nested.a]]
		f = 6
	");

    // Note that even though the custom unmarshaller did not decode all fields
    // as far as the metadata is concerned they are handled. It is the job of
    // the unmarshaller to ensure this or we would need a more powerful
    // interface like UnmarshalTOML(data any, md *MetaData)
    if (d.meta.undecoded().length() > 0) {
        throw `\ncustom decode leaves undecoded fields: ${go.sprint_v(d.meta.undecoded())}\n`;
    }
}

function tbl_n(n: int) -> string {
    ".a".repeat(n).slice(1, n * 2) + "=1"
}

function arr_n(n: int) -> string {
    "a=" + "[".repeat(n) + "1" + "]".repeat(n)
}

class MaxDepthCase {
    doc: string,
    max_nest: int,
    want_err: string,
}

function max_depth_err(doc: string, max_nest: int) -> TomlError? {
    let d = new_decoder(go.new_reader(doc));
    if (max_nest != -99) {
        d.max_depth(max_nest);
    }
    let err: TomlError? = null;
    let _ = d.decode<map<string, Any>>(null) catch (e) {
        let te: TomlError => {
            err = te;
            null
        },
    };
    err
}

testset "TestMaxDepth" {
    let tests = [
        MaxDepthCase { doc: "\n\n" + tbl_n(128), max_nest: -99, want_err: "" },
        MaxDepthCase { doc: "\n\n" + tbl_n(129), max_nest: -99, want_err: "toml: line 3: exceeds maximum table depth of 128" },
        MaxDepthCase { doc: "\n\n" + tbl_n(300), max_nest: 0, want_err: "" },
        MaxDepthCase { doc: "\n\n" + tbl_n(5), max_nest: 5, want_err: "" },
        MaxDepthCase { doc: "\n\n" + tbl_n(6), max_nest: 5, want_err: "toml: line 3: exceeds maximum table depth of 5" },

        MaxDepthCase { doc: arr_n(128), max_nest: -99, want_err: "" },
        MaxDepthCase { doc: arr_n(129), max_nest: -99, want_err: "toml: line 1 (last key \"a\"): exceeds maximum array depth of 128" },
        MaxDepthCase { doc: "x=1\n" + arr_n(129), max_nest: -99, want_err: "toml: line 2 (last key \"a\"): exceeds maximum array depth of 128" },
        MaxDepthCase { doc: arr_n(300), max_nest: 0, want_err: "" },
        MaxDepthCase { doc: arr_n(5), max_nest: 5, want_err: "" },
        MaxDepthCase { doc: arr_n(6), max_nest: 5, want_err: "toml: line 1 (last key \"a\"): exceeds maximum array depth of 5" },
    ];

    let i = 0;
    for (let tt in tests) {
        let name = if (i < 10) { `#0${i}` } else { `#${i}` };
        test name {
            let err = max_depth_err(tt.doc, tt.max_nest);
            if (!error_contains(err, tt.want_err)) {
                throw `wrong error\nhave: ${go.quote(go.sprint_v(err))}\nwant: ${go.quote(tt.want_err)}`;
            }
        }
        i += 1;
    }
}
