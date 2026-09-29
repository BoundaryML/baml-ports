// Port of decode.go.
//
// HOW THE PORT DECODES (vs. Go):
//
// Go's Decode(v any) takes a pointer and writes into it through reflect.Value
// setters. BAML reflection can *read* any value and describe any type, but it
// has no reflective setter and no way to construct a class instance from a
// runtime `reflect.Type`. The one runtime-typed constructor BAML offers is
// `baml.json.from_json<T>(j)`, where `T` may be bound at runtime through
// `type T = unreflect(t)`.
//
// So `unify` keeps Go's structure and error behaviour but, instead of setting
// fields in place, it *returns the JSON image* of the value the Go code would
// have written, given the JSON image of the value that was there before
// (`cur`). The top-level call then materialises the result with
// `from_json<T>`. Consequences (all logged in PORTING_NOTES.md):
//
//   * decode returns the new value instead of mutating its argument;
//     `decode_into` takes an initial value to emulate decoding into a
//     pre-populated struct/map/slice.
//   * float NaN/±Inf have no JSON form, so they cannot be decoded into a
//     `float` field of a class (they can into `Any`/maps at the top level,
//     which bypass JSON).
//   * Unmarshaler / TextUnmarshaler are instance methods returning a new
//     `Self` (value semantics) instead of mutating through a pointer.

// Unmarshaler is the interface implemented by objects that can unmarshal a
// TOML description of themselves.
//
// Go: UnmarshalTOML(any) error on a pointer receiver. BAML: called on a zero
// (or the existing) value, returns the decoded value.
interface Unmarshaler {
    function unmarshal_toml(self, data: Any?) -> Self throws TomlError;
}

// encoding.TextUnmarshaler.
interface TextUnmarshaler {
    function unmarshal_text(self, text: string) -> Self throws TomlError;
}

// The result of a decode: Go returns (MetaData, error) and writes the value
// through the pointer; BAML returns both.
class Decoded<T> {
    value: T,
    meta: MetaData,
}

// Unmarshal decodes the contents of data in TOML format into a value of T.
//
// See [Decoder] for a description of the decoding process.
function unmarshal<T>(data: int[]) -> T throws TomlError {
    new_decoder(root.go.new_bytes_reader(data)).decode<T>(null).value
}

// Decode the TOML data in to a value of T.
//
// See [Decoder] for a description of the decoding process.
function decode<T>(data: string) -> Decoded<T> throws TomlError {
    new_decoder(root.go.new_reader(data)).decode<T>(null)
}

// Decode the TOML data on top of the existing value v (Go: decoding into a
// pointer to an already-populated value).
function decode_into<T>(data: string, v: T) -> Decoded<T> throws TomlError {
    new_decoder(root.go.new_reader(data)).decode<T>(v)
}

// DecodeFile reads the contents of a file and decodes it with [Decode].
function decode_file<T>(path: string) -> Decoded<T> throws TomlError {
    let fp = baml.fs.open(path, "r") catch (e) {
        _ => {
            throw GoError { msg: `open ${path}: no such file or directory`, wrapped: null }
        },
    };
    let d = new_decoder(fp).decode<T>(null);
    let _ = fp.close() catch (e) {
        _ => null
    };
    d
}

// DecodeFS reads the contents of a file from [fs.FS] and decodes it with
// [Decode].
//
// Go's fs.FS is an interface over a file tree; the port's FS is a map from
// path to contents (the only implementation the tests need, fstest.MapFS).
function decode_fs<T>(fsys: map<string, string>, path: string) -> Decoded<T> throws TomlError {
    let data = fsys.get(path);
    if (data == null) {
        throw GoError { msg: `open ${path}: file does not exist`, wrapped: null };
    }
    new_decoder(root.go.new_reader(data)).decode<T>(null)
}

// Primitive is a TOML value that hasn't been decoded into a Go value.
//
// This type can be used for any value, which will cause decoding to be delayed.
// You can use [PrimitiveDecode] to "manually" decode these values.
//
// NOTE: The underlying representation of a `Primitive` value is subject to
// change. Do not rely on it.
//
// NOTE: Primitive values are still parsed, so using them will only avoid the
// overhead of reflection. They can be useful when you don't know the exact type
// of TOML data until runtime.
//
// The port stores the undecoded value in a lossless tagged JSON form so that
// the Primitive survives the from_json round trip that builds the enclosing
// value.
class Primitive {
    undecoded_json: baml.json.json,
    context: Key,

    function undecoded(self) -> Any? {
        any_from_tagged(self.undecoded_json)
    }
}

// The significand precision for float32 and float64 is 24 and 53 bits; this is
// the range a natural number can be stored in a float without loss of data.
function max_safe_float32_int() -> bigint {
    16777215n // 2^24-1
}

function max_safe_float64_int() -> bigint {
    9007199254740991n // 2^53-1
}

function max_float32() -> float {
    3.40282346638528859811704183484516925440e+38
}

// Decoder decodes TOML data.
//
// TOML tables correspond to Go structs or maps; they can be used
// interchangeably, but structs offer better type safety.
//
// TOML table arrays correspond to either a slice of structs or a slice of maps.
//
// TOML datetimes correspond to [time.Time]. Local datetimes are parsed in the
// local timezone.
//
// [time.Duration] types are treated as nanoseconds if the TOML value is an
// integer, or they're parsed with time.ParseDuration() if they're strings.
//
// All other TOML types (float, string, int, bool and array) correspond to the
// obvious Go types.
//
// An exception to the above rules is if a type implements the TextUnmarshaler
// interface, in which case any primitive TOML value (floats, strings, integers,
// booleans, datetimes) will be converted to a []byte and given to the value's
// UnmarshalText method. See the Unmarshaler example for a demonstration with
// email addresses.
//
// # Key mapping
//
// TOML keys can map to either keys in a Go map or field names in a Go struct.
// The special `toml` struct tag can be used to map TOML keys to struct fields
// that don't match the key name exactly (see the example). A case insensitive
// match to struct names will be tried if an exact match can't be found.
//
// The mapping between TOML values and Go values is loose. That is, there may
// exist TOML values that cannot be placed into your representation, and there
// may be parts of your representation that do not correspond to TOML values.
// This loose mapping can be made stricter by using the IsDefined and/or
// Undecoded methods on the MetaData returned.
//
// This decoder does not handle cyclic types. Decode will not terminate if a
// cyclic type is passed.
class Decoder {
    r: baml.io.Read,
    max_depth_: int,

    // MaxDepth sets the maximum table and array depth to prevent using an
    // inordinate amount of system resources on deeply nested objects.
    //
    // The default is 128. Set to <=0 to disable the limit.
    function max_depth(self, l: int) -> void {
        self.max_depth_ = l;
    }

    // Decode TOML data in to a value of type T. `v` is the value already
    // there (Go: what the pointer points to), or null for a zero value.
    function decode<T>(self, v: T?) -> Decoded<T> throws TomlError {
        let rt = reflect.Type.of<T>();

        // Check if this is a supported type: struct, map, any, or something that
        // implements UnmarshalTOML or UnmarshalText.
        let k = type_kind(rt);
        if (k != "struct" && k != "map" && k != "interface" && !implements_unmarshaler(rt)
            && !implements_text_unmarshaler(rt)) {
            throw GoError { msg: `toml: cannot decode to type ${go_type_string(rt)}`, wrapped: null };
        }

        // TODO: parser should read from io.Reader? Or at the very least, make it
        // read from []byte rather than string
        let data = self.r.bytes() catch (e) {
            _ => {
                throw GoError { msg: "read error", wrapped: null }
            },
        };

        let p = parse(data.to_array(), self.max_depth_) catch (e) {
            let pe: ParseError => {
                throw pe
            },
        };

        let md = MetaData {
            mapping: p.mapping,
            key_info: p.key_info,
            keys_list: p.ordered,
            decoded: {},
            context: new_key([]),
            data: data.to_array(),
        };
        let value = md_unify_into<T>(md, p.mapping, v);
        Decoded { value: value, meta: md }
    }
}

// NewDecoder creates a new Decoder.
function new_decoder(r: baml.io.Read) -> Decoder {
    Decoder { r: r, max_depth_: 128 }
}

// PrimitiveDecode is just like the other Decode* functions, except it decodes a
// TOML value that has already been parsed. Valid primitive values can *only* be
// obtained from values filled by the decoder functions, including this method.
// (i.e., v may contain more [Primitive] values.)
//
// Meta data for primitive values is included in the meta data returned by the
// Decode* functions with one exception: keys returned by the Undecoded method
// will only reflect keys that were decoded. Namely, any keys hidden behind a
// Primitive will be considered undecoded. Executing this method will update the
// undecoded keys in the meta data. (See the example.)
//
// (A method on MetaData in Go; BAML methods cannot be generic over a type
// parameter that is only used by the method *and* be called on a class from
// another file without … — kept as a free function taking md. See
// PORTING_NOTES.md.)
function primitive_decode<T>(md: MetaData, prim_value: Primitive, v: T?) -> T throws TomlError {
    md.context = prim_value.context;
    let out = md_unify_into<T>(md, prim_value.undecoded(), v) catch (e) {
        _ => {
            md.context = new_key([]);
            throw e
        },
    };
    md.context = new_key([]);
    out
}

// The kind of a type in Go terms.
function type_kind(t: reflect.Type) -> string {
    if (t == reflect.Type.of<unknown>() || t == reflect.Type.of<Any>() || t == reflect.Type.of<Any?>()) {
        return "interface";
    }
    if (t == reflect.Type.of<int>() || t == reflect.Type.of<bigint>()) {
        return "int";
    }
    if (t == reflect.Type.of<root.go.Int8>() || t == reflect.Type.of<root.go.Int16>() || t == reflect.Type.of<root.go.Int32>()
        || t == reflect.Type.of<root.go.Duration>()) {
        return "int";
    }
    if (t == reflect.Type.of<root.go.Uint>() || t == reflect.Type.of<root.go.Uint8>() || t == reflect.Type.of<root.go.Uint16>()
        || t == reflect.Type.of<root.go.Uint32>() || t == reflect.Type.of<root.go.Uint64>()) {
        return "uint";
    }
    if (t == reflect.Type.of<float>()) {
        return "float64";
    }
    if (t == reflect.Type.of<root.go.Float32>()) {
        return "float32";
    }
    if (t == reflect.Type.of<string>() || t == reflect.Type.of<root.go.Number>()) {
        return "string";
    }
    if (t == reflect.Type.of<bool>()) {
        return "bool";
    }
    if (t.as_array() != null) {
        return "slice";
    }
    if (t.as_map() != null) {
        return "map";
    }
    if (type_is_optional(t)) {
        return "ptr";
    }
    if (t.as_interface() != null) {
        return "interface_methods";
    }
    if (t.as_class() != null) {
        return "struct";
    }
    if (t.as_union() != null) {
        return "union";
    }
    t.to_string()
}

// Go's reflect.Type.String() for the port's types.
function go_type_string(t: reflect.Type) -> string {
    if (t == reflect.Type.of<int>()) {
        return "int";
    }
    if (t == reflect.Type.of<bigint>()) {
        return "int64";
    }
    if (t == reflect.Type.of<float>()) {
        return "float64";
    }
    if (t == reflect.Type.of<root.go.Int8>()) {
        return "int8";
    }
    if (t == reflect.Type.of<root.go.Int16>()) {
        return "int16";
    }
    if (t == reflect.Type.of<root.go.Int32>()) {
        return "int32";
    }
    if (t == reflect.Type.of<root.go.Uint>()) {
        return "uint";
    }
    if (t == reflect.Type.of<root.go.Uint8>()) {
        return "uint8";
    }
    if (t == reflect.Type.of<root.go.Uint16>()) {
        return "uint16";
    }
    if (t == reflect.Type.of<root.go.Uint32>()) {
        return "uint32";
    }
    if (t == reflect.Type.of<root.go.Uint64>()) {
        return "uint64";
    }
    if (t == reflect.Type.of<root.go.Float32>()) {
        return "float32";
    }
    if (t == reflect.Type.of<root.go.Duration>()) {
        return "time.Duration";
    }
    if (t == reflect.Type.of<root.go.Time>()) {
        return "time.Time";
    }
    let at = t.as_array();
    if (at != null) {
        return "[]" + go_type_string(at.element_type());
    }
    let mt = t.as_map();
    if (mt != null) {
        return "map[" + go_type_string(mt.key_type()) + "]" + go_type_string(mt.value_type());
    }
    if (type_is_optional(t)) {
        return "*" + go_type_string(deref_type(t));
    }
    t.to_string()
}

function implements_unmarshaler(t: reflect.Type) -> bool {
    t.implements(reflect.Type.of<Unmarshaler>())
}

function implements_text_unmarshaler(t: reflect.Type) -> bool {
    t.implements(reflect.Type.of<TextUnmarshaler>()) || t == reflect.Type.of<root.go.Time>()
}

// ---------------------------------------------------------------------------
// MetaData: the unify* methods.
// ---------------------------------------------------------------------------

// Go: `md_unify(md, data, rvalue(v))` followed by nothing (the value is already in
// place). Here: compute the JSON image and materialise it as a T.
function md_unify_into<T>(md: MetaData, data: Any?, v: T?) -> T throws TomlError {
    let rt = reflect.Type.of<T>();

    // Fast path for untyped targets (Go: `var x any` or map[string]any): the
    // parsed data *is* the result, with no JSON round trip.
    if (rt == reflect.Type.of<Any>() || rt == reflect.Type.of<Any?>() || rt == reflect.Type.of<unknown>()
        || rt == reflect.Type.of<map<string, Any>>()) {
        let direct: T = data else {
            throw GoError { msg: "toml: internal error: untyped decode", wrapped: null };
        };
        return direct;
    }

    // A top-level Unmarshaler is called directly and its result returned as
    // is: a JSON round trip would lose fields whose type has no JSON decoding
    // (e.g. an interface-typed field, as in Example_unmarshalTOML).
    if (implements_unmarshaler(rt)) {
        let target: unknown = if (v != null) { v } else { materialize_or_zero(rt, null) };
        let u: Unmarshaler = target else {
            throw GoError { msg: "toml: internal error: not an Unmarshaler", wrapped: null };
        };
        let out = u.unmarshal_toml(data) catch (err) {
            _ => {
                throw md_parse_err(md, err)
            },
        };
        match (data) {
            let tmap: map<string, Any> => mark_decoded_recursive(md, tmap),
            _ => {},
        }
        let typed: T = out else {
            throw GoError { msg: "toml: internal error: UnmarshalTOML returned the wrong type", wrapped: null };
        };
        return typed;
    }

    let cur: baml.json.json = null;
    if (v != null) {
        cur = baml.json.from(v) catch (e) {
            _ => null
        };
    }
    let j = md_unify(md, data, rt, cur);
    baml.json.from_json<T>(j) catch (e) {
        let de: baml.json.DecodeError => {
            throw GoError { msg: `toml: internal error: cannot build ${go_type_string(rt)}: ${de.message} at ${de.path}`, wrapped: null }
        },
    }
}

// markDecodedRecursive is a helper to mark any key under the given tmap as
// decoded, recursing as needed
function mark_decoded_recursive(md: MetaData, tmap: map<string, Any>) -> void {
    for (let key in tmap.keys()) {
        md.decoded.set(md.context.add(key).to_string(), true);
        match (tmap[key]) {
            let sub: map<string, Any> => {
                md.context = md.context.add(key);
                mark_decoded_recursive(md, sub);
                md.context = md.context.parent();
            },
            let tarr: map<string, Any>[] => {
                for (let elm in tarr) {
                    md.context = md.context.add(key);
                    mark_decoded_recursive(md, elm);
                    md.context = md.context.parent();
                }
            },
            _ => {},
        }
    }
}

// unify performs a sort of type unification based on the structure of `rv`,
// which is the client representation.
//
// Any type mismatch produces an error. Finding a type that we don't know
// how to handle produces an unsupported type error.
//
// Port: `rt` is the destination type, `cur` the JSON image of the value
// currently there (null = zero value); the return is the new JSON image.
function md_unify(md: MetaData, data: Any?, rt: reflect.Type, cur: baml.json.json) -> baml.json.json throws TomlError {
    // Special case. Look for a `Primitive` value.
    // TODO: #76 would make this superfluous after implemented.
    if (rt == reflect.Type.of<Primitive>()) {
        // Save the undecoded data and the key context into the primitive
        // value.
        let prim = Primitive { undecoded_json: any_to_tagged(data), context: md.context };
        return baml.json.from(prim) catch (e) {
            _ => null
        };
    }

    if (implements_unmarshaler(rt)) {
        let target = materialize_or_zero(rt, cur);
        let u: Unmarshaler = target else {
            throw GoError { msg: "toml: internal error: not an Unmarshaler", wrapped: null };
        };
        let out = u.unmarshal_toml(data) catch (err) {
            _ => {
                throw md_parse_err(md, err)
            },
        };
        // Assume the Unmarshaler decoded everything, so mark all keys under
        // this table as decoded.
        match (data) {
            let tmap: map<string, Any> => mark_decoded_recursive(md, tmap),
            let aot: map<string, Any>[] => {
                for (let tmap in aot) {
                    mark_decoded_recursive(md, tmap);
                }
            },
            _ => {},
        }
        return baml.json.from(out) catch (e) {
            _ => null
        };
    }
    if (implements_text_unmarshaler(rt)) {
        return md_unify_text(md, data, rt, cur);
    }

    // TODO:
    // The behavior here is incorrect whenever a Go type satisfies the
    // encoding.TextUnmarshaler interface but also corresponds to a TOML hash or
    // array. In particular, the unmarshaler should only be applied to primitive
    // TOML values. But at this point, it will be applied to all kinds of values
    // and produce an incorrect error whenever those values are hashes or arrays
    // (including arrays of tables).

    let k = type_kind(rt);

    if (k == "int" || k == "uint") {
        return md_unify_int(md, data, rt);
    }
    match (k) {
        "struct" => md_unify_struct(md, data, rt, cur),
        "map" => md_unify_map(md, data, rt, cur),
        "slice" => md_unify_slice(md, data, rt, cur),
        "string" => md_unify_string(md, data, rt),
        "bool" => md_unify_bool(md, data),
        "interface" => md_unify_anything(md, data),
        "interface_methods" => {
            /// Only empty interfaces are supported.
            throw md_e(md, `unsupported type ${go_type_string(rt)}`)
        },
        "float32" | "float64" => md_unify_float64(md, data, rt),
        "ptr" => {
            // Go: indirect() allocates a new value for a nil pointer.
            md_unify(md, data, deref_type(rt), cur)
        },
        _ => {
            throw md_e(md, `unsupported type ${k}`)
        },
    }
}

function md_unify_struct(md: MetaData, mapping: Any?, rt: reflect.Type, cur: baml.json.json) -> baml.json.json throws TomlError {
    let tmap: map<string, Any> = match (mapping) {
        let m: map<string, Any> => m,
        null => {
            return cur ?? zero_json(rt, 0);
        },
        _ => {
            throw md_e(md, `type mismatch for ${go_type_string(rt)}: expected table but found ${fmt_type(mapping)}`)
        },
    };

    let obj = json_object(cur ?? zero_json(rt, 0));

    for (let key in tmap.keys()) {
        let datum = tmap[key];
        let f: Field? = null;
        let fields = cached_type_fields(rt);
        for (let ff in fields) {
            if (ff.name == key) {
                f = ff;
                break;
            }
            if (f == null && root.go.equal_fold(ff.name, key)) {
                f = ff;
            }
        }
        if (f != null) {
            // Every field on the index path is settable in the port (BAML has
            // no unexported fields that reflection cannot write), so the
            // isUnifiable/"cannot write unexported field" branch never fires.
            md.decoded.set(md.context.add(key).to_string(), true);
            md.context = md.context.add(key);

            obj = set_by_index(md, obj, rt, f.index, datum, 0);
            md.context = md.context.parent();
        }
    }
    obj
}

// Follow Go's `for _, i := range f.index { subv = indirect(subv.Field(i)) }`
// through the JSON image and unify the leaf.
function set_by_index(md: MetaData, obj: map<string, baml.json.json>, rt: reflect.Type, index: int[], datum: Any, depth: int) -> map<string, baml.json.json> throws TomlError {
    let tfs = go_type_fields(deref_type(rt));
    let tf = tfs[index[depth]];
    let ft = tf.typ ?? reflect.Type.of<unknown>();
    if (depth == index.length() - 1) {
        let nv = md_unify(md, datum, ft, obj.get(tf.name) ?? null);
        obj.set(tf.name, nv);
        return obj;
    }
    // An embedded struct (or pointer to one): allocate if nil.
    let inner_t = deref_type(ft);
    let inner = obj.get(tf.name) ?? null;
    let inner_obj = json_object(inner ?? zero_json(inner_t, 0));
    obj.set(tf.name, set_by_index(md, inner_obj, inner_t, index, datum, depth + 1));
    obj
}

function md_unify_map(md: MetaData, mapping: Any?, rt: reflect.Type, cur: baml.json.json) -> baml.json.json throws TomlError {
    let mt = rt.as_map();
    if (mt == null) {
        throw md_e(md, "internal: not a map");
    }
    if (mt.key_type() != reflect.Type.of<string>()) {
        throw GoError {
            msg: `toml: cannot decode to a map with non-string key type (${go_type_string(mt.key_type())} in ${root.go.quote(go_type_string(rt))})`,
            wrapped: null,
        };
    }

    let tmap: map<string, Any> = match (mapping) {
        let m: map<string, Any> => m,
        _ => {
            // Go: `if tmap == nil { return nil }` — tmap is always nil here, so
            // a non-table value is silently ignored.
            return cur;
        },
    };
    let out = json_object(cur ?? {});
    for (let k in tmap.keys()) {
        let v = tmap[k];
        md.decoded.set(md.context.add(k).to_string(), true);
        md.context = md.context.add(k);

        // Go: rvval := reflect.Indirect(reflect.New(rv.Type().Elem())) — always a
        // fresh zero value, not the existing map entry.
        let rvval = md_unify(md, v, mt.value_type(), null);
        md.context = md.context.parent();

        out.set(k, rvval);
    }
    out
}

function md_unify_slice(md: MetaData, data: Any?, rt: reflect.Type, cur: baml.json.json) -> baml.json.json throws TomlError {
    let at = rt.as_array();
    if (at == null) {
        throw md_e(md, "internal: not a slice");
    }
    let datav: Any[] = match (data) {
        let a: Any[] => a,
        let aot: map<string, Any>[] => {
            let tmp: Any[] = [];
            for (let t in aot) {
                tmp.push(t);
            }
            tmp
        },
        null => {
            return cur;
        },
        _ => {
            throw md_badtype(md, "slice", data)
        },
    };
    let n = datav.length();
    // Go: if rv.IsNil() || rv.Cap() < n { rv.Set(reflect.MakeSlice(rv.Type(), n, n)) }; rv.SetLen(n)
    let existing: baml.json.json[] = match (cur) {
        let a: baml.json.json[] => a,
        _ => [],
    };
    let reuse = existing.length() >= n;
    let out: baml.json.json[] = [];
    let i = 0;
    while (i < n) {
        let prev: baml.json.json = if (reuse) { existing[i] } else { null };
        out.push(md_unify(md, datav[i], at.element_type(), prev));
        i += 1;
    }
    out
}

function md_unify_string(md: MetaData, data: Any?, rt: reflect.Type) -> baml.json.json throws TomlError {
    if (rt == reflect.Type.of<root.go.Number>()) {
        let s = match (data) {
            let i: bigint => i.to_string(),
            let f: float => root.go.format_float_g(f, 64),
            _ => {
                throw md_badtype(md, "string", data)
            },
        };
        return { "s": s };
    }

    match (data) {
        let s: string => s,
        _ => {
            throw md_badtype(md, "string", data)
        },
    }
}

function md_unify_float64(md: MetaData, data: Any?, rt: reflect.Type) -> baml.json.json throws TomlError {
    let is32 = rt == reflect.Type.of<root.go.Float32>();
    let size = if (is32) { "float32" } else { "float64" };

    match (data) {
        let num: float => {
            if (is32) {
                if (num < -max_float32() || num > max_float32()) {
                    throw md_parse_err(md, ErrParseRange { i: root.go.format_float_g(num, 64), size: size });
                }
                return { "v": num };
            }
            return num;
        },
        let num: bigint => {
            if ((is32 && (num < -max_safe_float32_int() || num > max_safe_float32_int()))
                || (!is32 && (num < -max_safe_float64_int() || num > max_safe_float64_int()))) {
                throw md_parse_err(md, ErrUnsafeFloat { i: num.to_string(), size: size });
            }
            let f = float.parse(num.to_string()) catch (e) {
                _ => 0.0
            };
            if (is32) {
                return { "v": f };
            }
            return f;
        },
        _ => {
            throw md_badtype(md, "float", data)
        },
    }
}

function md_unify_int(md: MetaData, data: Any?, rt: reflect.Type) -> baml.json.json throws TomlError {
    if (rt == reflect.Type.of<root.go.Duration>()) {
        // Parse as string duration, and fall back to regular integer parsing
        // (as nanosecond) if this is not a string.
        match (data) {
            let s: string => {
                let dur = root.go.parse_duration(s);
                if (dur == null) {
                    throw md_parse_err(md, ErrParseDuration { d: s });
                }
                return { "ns": dur.ns };
            },
            _ => {},
        }
    }

    let num: bigint = match (data) {
        let n: bigint => n,
        _ => {
            throw md_badtype(md, "integer", data)
        },
    };

    let kind = go_type_string(rt);
    if (kind == "time.Duration") {
        kind = "int64";
    }
    let r = root.go.int_range(kind);
    if (num < r.lo || num > r.hi) {
        throw md_parse_err(md, ErrParseRange { i: num.to_string(), size: kind });
    }
    if (rt == reflect.Type.of<int>()) {
        return num.to_int() catch (e) {
            _ => 0
        };
    }
    if (rt == reflect.Type.of<bigint>()) {
        return num;
    }
    if (rt == reflect.Type.of<root.go.Duration>()) {
        return { "ns": num.to_int() catch (e) { _ => 0 } };
    }
    if (rt == reflect.Type.of<root.go.Uint>() || rt == reflect.Type.of<root.go.Uint64>()) {
        return { "v": num };
    }
    { "v": num.to_int() catch (e) { _ => 0 } }
}

function md_unify_bool(md: MetaData, data: Any?) -> baml.json.json throws TomlError {
    match (data) {
        let b: bool => b,
        _ => {
            throw md_badtype(md, "boolean", data)
        },
    }
}

function md_unify_anything(md: MetaData, data: Any?) -> baml.json.json throws TomlError {
    any_to_json(data)
}

function md_unify_text(md: MetaData, data: Any?, rt: reflect.Type, cur: baml.json.json) -> baml.json.json throws TomlError {
    let s = "";
    match (data) {
        let t: root.go.Time => {
            // time.Time implements encoding.TextMarshaler.
            s = t.format(root.go.rfc3339_nano());
        },
        let str: string => {
            s = str;
        },
        let b: bool => {
            s = root.go.format_bool(b);
        },
        let i: bigint => {
            s = i.to_string();
        },
        let f: float => {
            s = root.go.format_float_g(f, 64);
        },
        _ => {
            throw md_badtype(md, "primitive (string-like)", data)
        },
    }
    if (rt == reflect.Type.of<root.go.Time>()) {
        // (*time.Time).UnmarshalText: RFC 3339.
        let t = root.go.parse_in_location(root.go.rfc3339(), s, root.go.utc());
        if (t == null) {
            throw md_parse_err(md, GoError {
                msg: `parsing time ${root.go.quote(s)} as ${root.go.quote(root.go.rfc3339())}: cannot parse ${root.go.quote(s)} as "2006"`,
                wrapped: null,
            });
        }
        // Go keeps a matching Local zone as Local, and UTC for "Z".
        match (data) {
            let orig: root.go.Time => {
                t = orig;
            },
            _ => {},
        }
        return baml.json.from(t) catch (e) {
            _ => null
        };
    }
    let target = materialize_or_zero(rt, cur);
    let u: TextUnmarshaler = target else {
        throw GoError { msg: "toml: internal error: not a TextUnmarshaler", wrapped: null };
    };
    let out = u.unmarshal_text(s) catch (err) {
        _ => {
            throw md_parse_err(md, err)
        },
    };
    baml.json.from(out) catch (e) {
        _ => null
    }
}

function md_badtype(md: MetaData, dst: string, data: Any?) -> TomlError {
    md_e(md, `incompatible types: TOML value has type ${fmt_type(data)}; destination has type ${dst}`)
}

function md_parse_err(md: MetaData, err: TomlError) -> TomlError {
    let k = md.context.to_string();
    let ki = md.key_info.get(k);
    let pos = if (ki != null) { ki.pos } else { Position { line: 0, col: 0, start: 0, len: 0 } };
    ParseError {
        message: err.error(),
        usage: "",
        err: err,
        last_key: k,
        position: pos.with_col(md.data),
        line: pos.line,
        input: md.data,
    }
}

function md_e(md: MetaData, msg: string) -> TomlError {
    let f = "toml: ";
    if (md.context.len() > 0) {
        f = `toml: (last key ${root.go.quote(md.context.to_string())}): `;
        let ki = md.key_info.get(md.context.to_string());
        if (ki != null) {
            if (ki.pos.line > 0) {
                f = `toml: line ${ki.pos.line} (last key ${root.go.quote(md.context.to_string())}): `;
            }
        }
    }
    GoError { msg: f + msg, wrapped: null }
}

// ---------------------------------------------------------------------------
// JSON-image helpers (no Go counterpart; see the comment at the top).
// ---------------------------------------------------------------------------

function json_object(j: baml.json.json) -> map<string, baml.json.json> {
    match (j) {
        let m: map<string, baml.json.json> => m,
        _ => {
            let empty: map<string, baml.json.json> = {};
            empty
        },
    }
}

// Build a value of runtime type `rt` from its JSON image (or its zero value),
// so an interface method can be called on it.
function materialize_or_zero(rt: reflect.Type, cur: baml.json.json) -> unknown throws TomlError {
    type T = unreflect(rt);
    let j = cur ?? zero_json(rt, 0);
    let v = baml.json.from_json<T>(j) catch (e) {
        let de: baml.json.DecodeError => {
            throw GoError { msg: `toml: internal error: cannot build ${go_type_string(rt)}: ${de.message}`, wrapped: null }
        },
    };
    v
}

// The JSON image of Go's zero value of a type.
function zero_json(t: reflect.Type, depth: int) -> baml.json.json {
    if (depth > 32 || type_is_optional(t)) {
        return null;
    }
    if (t == reflect.Type.of<int>() || t == reflect.Type.of<bigint>()) {
        return 0;
    }
    if (t == reflect.Type.of<float>()) {
        return 0.0;
    }
    if (t == reflect.Type.of<string>()) {
        return "";
    }
    if (t == reflect.Type.of<bool>()) {
        return false;
    }
    if (t == reflect.Type.of<root.go.Time>()) {
        return baml.json.from(root.go.zero_time()) catch (e) {
            _ => null
        };
    }
    if (t.as_array() != null) {
        return [];
    }
    if (t.as_map() != null) {
        return {};
    }
    let et = t.as_enum();
    if (et != null) {
        let vs = et.values();
        if (vs.length() > 0) {
            return vs[0].name;
        }
        return "";
    }
    let ct = t.as_class();
    if (ct != null) {
        let obj: map<string, baml.json.json> = {};
        for (let f in ct.fields()) {
            let ft = f.type;
            obj.set(f.name, if (ft == null) { null } else { zero_json(ft, depth + 1) });
        }
        return obj;
    }
    let lt = t.as_literal();
    if (lt != null) {
        let v = lt.value();
        return match (v) {
            let s: string => s,
            let i: int => i,
            let b: bool => b,
            _ => null,
        };
    }
    let ut = t.as_union();
    if (ut != null) {
        let ms = ut.member_types();
        if (ms.length() > 0) {
            return zero_json(ms[0], depth + 1);
        }
    }
    null
}

// The JSON image of a parsed TOML value, for an `Any`-typed destination.
// from_json<Any> tries the union members in declaration order.
function any_to_json(data: Any?) -> baml.json.json {
    match (data) {
        null => null,
        let s: string => s,
        let i: bigint => i,
        let f: float => f,
        let b: bool => b,
        let t: root.go.Time => baml.json.from(t) catch (e) {
            _ => null
        },
        let aot: map<string, Any>[] => {
            let out: baml.json.json[] = [];
            for (let m in aot) {
                out.push(any_to_json(m));
            }
            out
        },
        let a: Any[] => {
            let out: baml.json.json[] = [];
            for (let x in a) {
                out.push(any_to_json(x));
            }
            out
        },
        let m: map<string, Any> => {
            let out: map<string, baml.json.json> = {};
            for (let k in m.keys()) {
                out.set(k, any_to_json(m[k]));
            }
            out
        },
    }
}

// A lossless, md-describing JSON encoding of a parsed TOML value (used to
// carry Primitive values through from_json).
function any_to_tagged(data: Any?) -> baml.json.json {
    match (data) {
        null => null,
        let s: string => ({ "t": "s", "v": s }),
        let i: bigint => ({ "t": "i", "v": i.to_string() }),
        let f: float => {
            let s = if (f.is_nan()) { "nan" } else if (f.is_infinite()) { if (f > 0.0) { "inf" } else { "-inf" } } else if (f == 0.0 && root.go.signbit(f)) { "-0" } else { f.to_string() };
            { "t": "f", "v": s }
        },
        let b: bool => ({ "t": "b", "v": b }),
        let t: root.go.Time => {
            { "t": "d", "v": baml.json.from(t) catch (e) { _ => null } }
        },
        let aot: map<string, Any>[] => {
            let out: baml.json.json[] = [];
            for (let m in aot) {
                out.push(any_to_tagged(m));
            }
            { "t": "A", "v": out }
        },
        let a: Any[] => {
            let out: baml.json.json[] = [];
            for (let x in a) {
                out.push(any_to_tagged(x));
            }
            { "t": "a", "v": out }
        },
        let m: map<string, Any> => {
            let out: map<string, baml.json.json> = {};
            for (let k in m.keys()) {
                out.set(k, any_to_tagged(m[k]));
            }
            { "t": "m", "v": out }
        },
    }
}

function any_from_tagged(j: baml.json.json) -> Any? {
    let o: map<string, baml.json.json> = match (j) {
        let m: map<string, baml.json.json> => m,
        _ => {
            return null;
        },
    };
    let t = o.get("t") ?? null;
    let v = o.get("v") ?? null;
    match (t) {
        "s" => match (v) {
            let s: string => s,
            _ => "",
        },
        "i" => match (v) {
            let s: string => bigint.parse(s) catch (e) { _ => 0n },
            _ => 0n,
        },
        "f" => match (v) {
            "nan" => float.nan(),
            "inf" => float.inf(),
            "-inf" => -float.inf(),
            "-0" => -0.0,
            let s: string => float.parse(s) catch (e) { _ => 0.0 },
            _ => 0.0,
        },
        "b" => match (v) {
            let b: bool => b,
            _ => false,
        },
        "d" => baml.json.from_json<root.go.Time>(v) catch (e) {
            _ => root.go.zero_time()
        },
        "A" => {
            let out: map<string, Any>[] = [];
            match (v) {
                let arr: baml.json.json[] => {
                    for (let x in arr) {
                        match (any_from_tagged(x)) {
                            let m: map<string, Any> => out.push(m),
                            _ => {},
                        }
                    }
                },
                _ => {},
            }
            out
        },
        "a" => {
            let out: Any[] = [];
            match (v) {
                let arr: baml.json.json[] => {
                    for (let x in arr) {
                        let e = any_from_tagged(x);
                        if (e != null) {
                            out.push(e);
                        }
                    }
                },
                _ => {},
            }
            out
        },
        "m" => {
            let out: map<string, Any> = {};
            match (v) {
                let mm: map<string, baml.json.json> => {
                    for (let k in mm.keys()) {
                        let e = any_from_tagged(mm[k]);
                        if (e != null) {
                            out.set(k, e);
                        }
                    }
                },
                _ => {},
            }
            out
        },
        _ => null,
    }
}
