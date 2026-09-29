// Port of encode.go.
//
// Go's encoder is driven by package reflect. The port is driven by BAML's
// runtime reflection: `reflect.Type.of_value` for the concrete runtime type of
// a value, `type E = unreflect(t)` plus a narrowing `let` to view an array or
// map whose element type is only known at runtime, and `reflect.AnyClass` to
// enumerate class fields (see `go_value.baml`). Go concepts are mapped as:
//
//   Go                         BAML
//   ------------------------   ---------------------------------------------
//   struct                     class (fields starting with `_` = unexported)
//   `toml:"name,opts"` tag     field `@description("toml:\"name,opts\"")`,
//                              or `@alias("name")`, or `@skip` for "-"
//   anonymous (embedded) field `@description("go:\"embed\"")` on the field
//   pointer / interface        optional type `T?` (null = nil)
//   slice / array              `T[]`
//   map[string]T               `map<string, T>`
//   int8..uint64, float32      root.go.Int8 … root.go.Float32 wrapper classes
//   int / int64                `int` (63-bit) / `bigint`
//   time.Time, time.Duration   root.go.Time, root.go.Duration
//   json.Number                root.go.Number
//   Marshaler, TextMarshaler   the Marshaler / TextMarshaler interfaces below

// tomlEncodeError is the panic payload used to unwind the encoder.
class TomlEncodeError {
    err: TomlError,
}

function err_array_nil_element() -> GoError {
    GoError { msg: "toml: cannot encode array with nil element", wrapped: null }
}

function err_non_string() -> GoError {
    GoError { msg: "toml: cannot encode a map with non-string key type", wrapped: null }
}

function err_no_key() -> GoError {
    GoError { msg: "toml: top-level values must be Go maps or structs", wrapped: null }
}

// var dblQuotedReplacer = strings.NewReplacer(...)
function dbl_quoted_replace(s: string) -> string throws never {
    let out = "";
    for (let r in s.to_code_points()) {
        if (r == 34) {
            out += "\\\"";
        } else if (r == 92) {
            out += "\\\\";
        } else if (r == 8) {
            out += "\\b";
        } else if (r == 9) {
            out += "\\t";
        } else if (r == 10) {
            out += "\\n";
        } else if (r == 12) {
            out += "\\f";
        } else if (r == 13) {
            out += "\\r";
        } else if (r < 32 || r == 127) {
            out += "\\u" + root.go.hex_pad(r, 4);
        } else {
            out += root.go.rune_string(r);
        }
    }
    out
}

// Marshaler is the interface implemented by types that can marshal themselves
// into valid TOML.
//
// Go: MarshalTOML() ([]byte, error). A nil []byte is modelled as `null`.
interface Marshaler {
    function marshal_toml(self) -> string? throws TomlError;
}

// encoding.TextMarshaler.
interface TextMarshaler {
    function marshal_text(self) -> string? throws TomlError;
}

// Marshal returns a TOML representation of the Go value.
//
// See [Encoder] for a description of the encoding process.
function marshal(v: unknown) -> string throws TomlError {
    let buff = root.go.new_buffer();
    new_encoder(buff).encode(v);
    buff.string()
}

// Encoder encodes a Go to a TOML document.
//
// The mapping between Go values and TOML values should be precisely the same as
// for [Decode].
//
// time.Time is encoded as a RFC 3339 string, and time.Duration as its string
// representation.
//
// The [Marshaler] and [encoding.TextMarshaler] interfaces are supported to
// encoding the value as custom TOML.
//
// If you want to write arbitrary binary data then you will need to use
// something like base64 since TOML does not have any binary types.
//
// When encoding TOML hashes (Go maps or structs), keys without any sub-hashes
// are encoded first.
//
// Go maps will be sorted alphabetically by key for deterministic output.
//
// The toml struct tag can be used to provide the key name; if omitted the
// struct field name will be used. If the "omitempty" option is present the
// following value will be skipped:
//
//   - arrays, slices, maps, and string with len of 0
//   - struct with all zero values
//   - bool false
//
// If omitzero is given all int and float types with a value of 0 will be
// skipped.
//
// Encoding Go values without a corresponding TOML representation will return an
// error. Examples of this includes maps with non-string keys, slices with nil
// elements, embedded non-struct types, and nested slices containing maps or
// structs. (e.g. [][]map[string]string is not allowed but []map[string]string
// is okay, as is []map[string][]string).
//
// NOTE: only exported keys are encoded due to the use of reflection. Unexported
// keys are silently discarded.
class Encoder {
    indent: string, // string for a single indentation level; default is two spaces.
    has_written: bool, // written any output to w yet?
    // Go wraps w in a bufio.Writer that is only flushed when Encode succeeds;
    // `buf` plays that role.
    buf: string,
    w: baml.io.Write,

    // Encode writes a TOML representation of the Go value to the [Encoder]'s writer.
    //
    // An error is returned if the value given cannot be encoded to a valid TOML
    // document.
    function encode(self, v: unknown) -> void throws TomlError {
        let rv = eindirect(v);
        let err = self.safe_encode(new_key([]), rv);
        if (err != null) {
            throw err;
        }
        let _ = self.w.write(self.buf) catch (e) {
            _ => {
                throw GoError { msg: "write error", wrapped: null }
            },
        };
        self.buf = "";
    }

    function safe_encode(self, key: Key, rv: unknown) -> TomlError? {
        self.encode_value(key, rv) catch (e) {
            let terr: TomlEncodeError => {
                return terr.err;
            },
        };
        null
    }

    function encode_value(self, key: Key, rv: unknown) -> void {
        // If we can marshal the type to text, then we use that. This prevents the
        // encoder for handling these types as generic structs (or whatever the
        // underlying type of a TextMarshaler is).
        if (is_marshaler(rv)) {
            self.write_key_value(key, rv, false);
            return;
        }
        match (rv) {
            let p: Primitive => { // TODO: #76 would make this superfluous after implemented.
                self.encode_value(key, p.undecoded());
                return;
            },
            _ => {},
        }

        let k = go_kind(rv);
        match (k) {
            "int" | "uint" | "float32" | "float64" | "string" | "bool" => {
                self.write_key_value(key, rv, false);
            },
            "slice" => {
                if (type_equal(toml_array_hash(), toml_type_of_go(rv))) {
                    self.e_array_of_tables(key, rv);
                } else {
                    self.write_key_value(key, rv, false);
                }
            },
            "nil" => {
                return;
            },
            "map" => {
                self.e_table(key, rv);
            },
            "struct" => {
                self.e_table(key, rv);
            },
            _ => enc_panic(GoError { msg: `unsupported type for key '${key.to_string()}': ${k}`, wrapped: null }),
        }
    }

    // eElement encodes any value that can be an array element.
    function e_element(self, rv: unknown) -> void {
        match (rv) {
            let v: root.go.Time => { // Using TextMarshaler adds extra quotes, which we don't want.
                let format = root.go.rfc3339_nano();
                if (root.go.same_location(v.location(), local_datetime())) {
                    format = "2006-01-02T15:04:05.999999999";
                } else if (root.go.same_location(v.location(), local_date())) {
                    format = "2006-01-02";
                } else if (root.go.same_location(v.location(), local_time())) {
                    format = "15:04:05.999999999";
                }
                self.write(v.format(format));
                return;
            },
            _ => {},
        }
        let m: Marshaler? = as_marshaler(rv);
        if (m != null) {
            let s = m.marshal_toml() catch (e) {
                _ => enc_panic(e),
            };
            if (s == null) {
                throw TomlEncodeError { err: GoError { msg: "MarshalTOML returned nil and no error", wrapped: null } };
            }
            self.write(s);
            return;
        }
        let tm: TextMarshaler? = as_text_marshaler(rv);
        if (tm != null) {
            let s = tm.marshal_text() catch (e) {
                _ => enc_panic(e),
            };
            if (s == null) {
                throw TomlEncodeError { err: GoError { msg: "MarshalText returned nil and no error", wrapped: null } };
            }
            self.write_quoted(s);
            return;
        }
        match (rv) {
            let d: root.go.Duration => {
                self.write_quoted(d.to_string());
                return;
            },
            let n: root.go.Number => {
                if (n.s == "") { /// Useful zero value.
                    self.write("0");
                    return;
                }
                let iv = root.go.parse_int(n.s, 10, 64);
                if (iv.err == "") {
                    self.e_element(iv.value);
                    return;
                }
                let fv = root.go.parse_float(n.s);
                if (fv.err == "") {
                    self.e_element(fv.value);
                    return;
                }
                enc_panic(GoError { msg: `unable to convert ${root.go.quote(n.s)} to int64 or float64`, wrapped: null });
            },
            _ => {},
        }

        let k = go_kind(rv);
        match (k) {
            "string" => self.write_quoted(go_string(rv)),
            "bool" => self.write(root.go.format_bool(go_bool(rv))),
            "int" | "uint" => self.write(go_int(rv).to_string()),
            "float32" | "float64" => {
                let f = go_float(rv);
                if (f.is_nan()) {
                    if (root.go.signbit(f)) {
                        self.write("-");
                    }
                    self.write("nan");
                } else if (f.is_infinite()) {
                    if (root.go.signbit(f)) {
                        self.write("-");
                    }
                    self.write("inf");
                } else {
                    let bits = if (k == "float32") { 32 } else { 64 };
                    self.write(float_add_decimal(root.go.format_float_g(f, bits)));
                }
            },
            "slice" => self.e_array_or_slice_element(rv),
            "struct" => self.e_struct(null, rv, true),
            "map" => self.e_map(null, rv, true),
            _ => enc_panic(GoError { msg: `unexpected type: ${fmt_type(rv)}`, wrapped: null }),
        }
    }

    function write_quoted(self, s: string) -> void {
        self.write("\"" + dbl_quoted_replace(s) + "\"");
    }

    function e_array_or_slice_element(self, rv: unknown) -> void {
        let elems = go_slice(rv);
        let length = elems.length();
        self.write("[");
        let i = 0;
        while (i < length) {
            let elem = eindirect(elems[i]);
            self.e_element(elem);
            if (i != length - 1) {
                self.write(", ");
            }
            i += 1;
        }
        self.write("]");
    }

    function e_array_of_tables(self, key: Key, rv: unknown) -> void {
        if (key.len() == 0) {
            enc_panic(err_no_key());
        }
        for (let e in go_slice(rv)) {
            let trv = eindirect(e);
            if (trv == null) {
                continue;
            }
            self.newline();
            self.write(`${self.indent_str(key)}[[${key.to_string()}]]`);
            self.newline();
            self.e_map_or_struct(key, trv, false);
        }
    }

    function e_table(self, key: Key, rv: unknown) -> void {
        if (key.len() == 1) {
            // Output an extra newline between top-level tables.
            // (The newline isn't written if nothing else has been written though.)
            self.newline();
        }
        if (key.len() > 0) {
            self.write(`${self.indent_str(key)}[${key.to_string()}]`);
            self.newline();
        }
        self.e_map_or_struct(key, rv, false);
    }

    function e_map_or_struct(self, key: Key?, rv: unknown, inline: bool) -> void {
        match (go_kind(rv)) {
            "map" => self.e_map(key, rv, inline),
            "struct" => self.e_struct(key, rv, inline),
            // Should never happen?
            _ => go_panic("eTable: unhandled reflect.Value Kind: " + go_kind(rv)),
        }
    }

    function e_map(self, key0: Key?, rv: unknown, inline: bool) -> void {
        let key = key0 ?? new_key([]);
        let entries = go_map(rv);
        if (entries == null) {
            throw TomlEncodeError { err: err_non_string() };
        }

        // Sort keys so that we have deterministic output. And write keys directly
        // underneath this key first, before writing sub-structs or sub-maps.
        let map_keys_direct: string[] = [];
        let map_keys_sub: string[] = [];
        for (let map_key in entries.keys()) {
            if (type_is_table(toml_type_of_go(eindirect(entries[map_key])))) {
                map_keys_sub.push(map_key);
            } else {
                map_keys_direct.push(map_key);
            }
        }

        if (inline) {
            self.write("{");
        }
        self.write_map_keys(key, entries, map_keys_direct, map_keys_sub.length() > 0, inline);
        self.write_map_keys(key, entries, map_keys_sub, false, inline);
        if (inline) {
            self.write("}");
        }
    }

    function write_map_keys(self, key: Key, entries: map<string, unknown>, map_keys0: string[], trail_c: bool, inline: bool) -> void {
        let map_keys = map_keys0.sort_by((a: string, b: string) -> baml.ops.Ordering { a.cmp(b) });
        let i = 0;
        for (let map_key in map_keys) {
            let val = eindirect(entries[map_key]);
            if (val == null) {
                i += 1;
                continue;
            }

            if (inline) {
                self.write_key_value(new_key([map_key]), val, true);
                if (trail_c || i != map_keys.length() - 1) {
                    self.write(", ");
                }
            } else {
                self.encode_value(key.add(map_key), val);
            }
            i += 1;
        }
    }

    function e_struct(self, key0: Key?, rv: unknown, inline: bool) -> void {
        let key = key0 ?? new_key([]);
        // Write keys for fields directly under this key first, because if we write
        // a field that creates a new table then all keys under it will be in that
        // table (not the one we're writing here).
        //
        // Go collects [][]int field index paths and resolves them later with
        // FieldByIndex; BAML has no index-based field access, so the port
        // collects the resolved (field, value) pairs directly.
        let fields_direct: StructField[] = [];
        let fields_sub: StructField[] = [];
        add_fields(rv, [], fields_direct, fields_sub);

        if (inline) {
            self.write("{");
        }

        let l = fields_direct.length() + fields_sub.length();
        self.write_fields(key, fields_direct, l, inline);
        self.write_fields(key, fields_sub, l, inline);
        if (inline) {
            self.write("}");
        }
    }

    function write_fields(self, key: Key, fields: StructField[], total_fields: int, inline: bool) -> void {
        for (let f in fields) {
            let opts = f.opts;
            if (opts.skip) {
                continue;
            }
            if (opts.omitempty && is_empty(f.value, f.is_pointer)) {
                continue;
            }

            let field_val = eindirect(f.value);

            if (field_val == null) { /// Don't write anything for nil fields.
                continue;
            }

            let key_name = f.name;
            if (opts.name != "") {
                key_name = opts.name;
            }

            if (opts.omitzero && is_zero(field_val)) {
                continue;
            }

            if (inline) {
                self.write_key_value(new_key([key_name]), field_val, true);
                if (f.index[0] != total_fields - 1) {
                    self.write(", ");
                }
            } else {
                self.encode_value(key.add(key_name), field_val);
            }
        }
    }

    function newline(self) -> void {
        if (self.has_written) {
            self.write("\n");
        }
    }

    // Write a key/value pair:
    //
    //	key = <any value>
    //
    // This is also used for "k = v" in inline tables; so something like this will
    // be written in three calls:
    //
    //	┌───────────────────┐
    //	│      ┌───┐  ┌────┐│
    //	v      v   v  v    vv
    //	key = {k = 1, k2 = 2}
    function write_key_value(self, key: Key, val: unknown, inline: bool) -> void {
        /// Marshaler used on top-level document; call eElement() to just call
        /// Marshal{TOML,Text}.
        if (key.len() == 0) {
            self.e_element(val);
            return;
        }
        self.write(`${self.indent_str(key)}${key.maybe_quoted(key.len() - 1)} = `);
        self.e_element(val);
        if (!inline) {
            self.newline();
        }
    }

    function write(self, s: string) -> void {
        self.buf += s;
        self.has_written = true;
    }

    function indent_str(self, key: Key) -> string {
        self.indent.repeat(key.len() - 1)
    }
}

// NewEncoder create a new Encoder.
function new_encoder(w: baml.io.Write) -> Encoder {
    Encoder { indent: "  ", has_written: false, buf: "", w: w }
}

// By the TOML spec, all floats must have a decimal with at least one number on
// either side.
function float_add_decimal(fstr: string) -> string {
    for (let c in fstr.chars()) {
        if (c == "e") { // Exponent syntax
            return fstr;
        }
        if (c == ".") {
            return fstr;
        }
    }
    fstr + ".0"
}

// A struct field found by addFields (Go: the []int index plus FieldByIndex).
class StructField {
    name: string, // Go field name
    opts: TagOptions,
    value: unknown,
    is_pointer: bool, // declared as `T?` (Go pointer/interface)
    index: int[],
}

// addFields from eStruct: splits the fields into those written directly and
// those that open a sub-table, flattening embedded structs.
function add_fields(rv: unknown, start: int[], fields_direct: StructField[], fields_sub: StructField[]) -> void {
    let i = 0;
    for (let f in go_struct_fields(rv)) {
        let idx = start.concat([i]);
        i += 1;
        let is_embed = f.anonymous && f.value_kind_is_struct;
        if (f.unexported && !is_embed) { /// Skip unexported fields.
            continue;
        }
        let opts = get_options(f.tag);
        if (opts.skip) {
            continue;
        }

        let frv = eindirect(f.value);

        // Treat anonymous struct fields with tag names as though they are
        // not anonymous, like encoding/json does.
        //
        // Non-struct anonymous fields use the normal encoding logic.
        if (is_embed) {
            if (opts.name == "" && go_kind(frv) == "struct") {
                add_fields(frv, idx, fields_direct, fields_sub);
                continue;
            }
        }

        let sf = StructField { name: f.name, opts: opts, value: f.value, is_pointer: f.is_pointer, index: idx };
        if (type_is_table(toml_type_of_go(frv))) {
            fields_sub.push(sf);
        } else {
            fields_direct.push(sf);
        }
    }
}

// tomlTypeOfGo returns the TOML type name of the Go value's type.
//
// It is used to determine whether the types of array elements are mixed (which
// is forbidden). If the Go value is nil, then it is illegal for it to be an
// array element, and valueIsNil is returned as true.
//
// The type may be `nil`, which means no concrete TOML type could be found.
function toml_type_of_go(rv: unknown) -> TomlType? {
    if (rv == null) {
        return null;
    }

    let k = go_kind(rv);
    if (k == "struct") {
        match (rv) {
            let t: root.go.Time => {
                return toml_datetime();
            },
            _ => {},
        }
        if (is_marshaler(rv)) {
            return toml_string();
        }
        return toml_hash();
    }

    if (is_marshaler(rv)) {
        return toml_string();
    }

    match (k) {
        "bool" => toml_bool(),
        "int" | "uint" => toml_integer(),
        "float32" | "float64" => toml_float(),
        "slice" => {
            if (is_table_array(rv)) {
                toml_array_hash()
            } else {
                toml_array()
            }
        },
        "string" => toml_string(),
        "map" => toml_hash(),
        _ => enc_panic(GoError { msg: "unsupported type: " + k, wrapped: null }),
    }
}

function is_marshaler(rv: unknown) -> bool {
    match (rv) {
        let t: root.go.Time => {
            return true; // time.Time implements encoding.TextMarshaler
        },
        _ => {},
    }
    as_marshaler(rv) != null || as_text_marshaler(rv) != null
}

function as_marshaler(rv: unknown) -> Marshaler? {
    let m: Marshaler = rv else {
        return null;
    };
    m
}

function as_text_marshaler(rv: unknown) -> TextMarshaler? {
    let m: TextMarshaler = rv else {
        return null;
    };
    m
}

// isTableArray reports if all entries in the array or slice are a table.
function is_table_array(arr: unknown) -> bool {
    if (arr == null) {
        return false;
    }
    let elems = go_slice(arr);
    if (elems.length() == 0) {
        return false;
    }

    let ret = true;
    for (let e in elems) {
        let tt = toml_type_of_go(eindirect(e));
        // Don't allow nil.
        if (tt == null) {
            enc_panic(err_array_nil_element());
        }

        if (ret && !type_equal(toml_hash(), tt)) {
            ret = false;
        }
    }
    ret
}

class TagOptions {
    skip: bool, // "-"
    name: string,
    omitempty: bool,
    omitzero: bool,
}

function get_options(tag: string) -> TagOptions {
    let t = struct_tag_get(tag, "toml");
    if (t == "-") {
        return TagOptions { skip: true, name: "", omitempty: false, omitzero: false };
    }
    let opts = TagOptions { skip: false, name: "", omitempty: false, omitzero: false };
    let parts = t.split(",");
    opts.name = parts[0];
    for (let s in parts.slice(1, parts.length())) {
        match (s) {
            "omitempty" => {
                opts.omitempty = true;
            },
            "omitzero" => {
                opts.omitzero = true;
            },
            _ => {},
        }
    }
    opts
}

function is_zero(rv: unknown) -> bool {
    match (go_kind(rv)) {
        "int" | "uint" => go_int(rv) == 0n,
        "float32" | "float64" => go_float(rv) == 0.0,
        _ => false,
    }
}

// Go's isEmpty. `is_pointer` says the value was declared as a pointer (`T?`),
// in which case only nil counts as empty.
function is_empty(rv: unknown, is_pointer: bool) -> bool {
    if (is_pointer) {
        return rv == null;
    }
    match (go_kind(rv)) {
        "slice" => go_slice(rv).length() == 0,
        "map" => (go_map(rv) ?? {}).length() == 0,
        "string" => go_string(rv) == "",
        "struct" => {
            if (is_comparable_struct(rv)) {
                return is_zero_value(rv);
            }
            // Need to also check if all the fields are empty, otherwise something
            // like this with uncomparable types will always return true:
            //
            //   type a struct{ field b }
            //   type b struct{ s []string }
            //   s := a{field: b{s: []string{"AAA"}}}
            for (let f in go_struct_fields(rv)) {
                if (!is_empty(f.value, f.is_pointer)) {
                    return false;
                }
            }
            true
        },
        "bool" => !go_bool(rv),
        "nil" => true,
        _ => false,
    }
}

function enc_panic(err: TomlError) -> never {
    throw TomlEncodeError { err: err }
}

// Resolve any level of pointers to the actual value (e.g. **string → string).
//
// BAML has no pointers: an optional value is either the value or null, so this
// is the identity. Kept so the call sites mirror Go.
function eindirect(v: unknown) -> unknown {
    v
}

// fmt %T with "interface {}" replaced with "any", which is far more readable.
function fmt_type(t: unknown) -> string {
    go_type_name(t).replace_all("interface {}", "any")
}
