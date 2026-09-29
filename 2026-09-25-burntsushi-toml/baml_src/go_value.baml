// Reflection adapter: a small stand-in for the parts of Go's reflect.Value /
// reflect.Type API that encode.go, decode.go and type_fields.go use, built on
// BAML's runtime reflection.
//
// There is no Go file for this; it replaces `import "reflect"`. See the
// mapping table at the top of encode.baml.

// Go's reflect.Kind of a value, as the string Go's Kind.String() returns
// (collapsed: every sized int is "int", every sized uint is "uint").
function go_kind(v: unknown) -> string {
    match (v) {
        null => "nil",
        let b: bool => "bool",
        let i: int => "int",
        let i: bigint => "int",
        let f: float => "float64",
        let s: string => "string",
        let x: root.go.Int8 => "int",
        let x: root.go.Int16 => "int",
        let x: root.go.Int32 => "int",
        let x: root.go.Uint => "uint",
        let x: root.go.Uint8 => "uint",
        let x: root.go.Uint16 => "uint",
        let x: root.go.Uint32 => "uint",
        let x: root.go.Uint64 => "uint",
        let x: root.go.Float32 => "float32",
        let x: root.go.Number => "string", // json.Number is a named string type
        let x: root.go.Duration => "int", // time.Duration is a named int64 type
        _ => {
            let t = reflect.Type.of_value(v);
            if (t.as_array() != null) {
                return "slice";
            }
            if (t.as_map() != null) {
                return "map";
            }
            if (t.as_class() != null) {
                return "struct";
            }
            if (t.as_enum() != null) {
                return "string";
            }
            if (t.as_function() != null) {
                return "func";
            }
            t.to_string()
        },
    }
}

// The type's name as Go's %T would print it (BAML spelling).
function go_type_name(v: unknown) -> string {
    match (v) {
        null => "<nil>",
        let i: bigint => "int64",
        let f: float => "float64",
        let m: map<string, Any> => "map[string]interface {}",
        let a: map<string, Any>[] => "[]map[string]interface {}",
        let a: Any[] => "[]interface {}",
        let t: root.go.Time => "time.Time",
        _ => reflect.Type.of_value(v).to_string(),
    }
}

function go_string(v: unknown) -> string {
    match (v) {
        let s: string => s,
        let n: root.go.Number => n.s,
        _ => {
            let t = reflect.Type.of_value(v);
            if (t.as_enum() != null) {
                return reflect.enum.get_value(v) catch (e) {
                    _ => ""
                };
            }
            ""
        },
    }
}

function go_bool(v: unknown) -> bool {
    match (v) {
        let b: bool => b,
        _ => false,
    }
}

// rv.Int() / rv.Uint(), widened to bigint.
function go_int(v: unknown) -> bigint {
    match (v) {
        let i: int => int_to_bigint(i),
        let i: bigint => i,
        let x: root.go.Int8 => int_to_bigint(x.v),
        let x: root.go.Int16 => int_to_bigint(x.v),
        let x: root.go.Int32 => int_to_bigint(x.v),
        let x: root.go.Uint => x.v,
        let x: root.go.Uint8 => int_to_bigint(x.v),
        let x: root.go.Uint16 => int_to_bigint(x.v),
        let x: root.go.Uint32 => int_to_bigint(x.v),
        let x: root.go.Uint64 => x.v,
        let x: root.go.Duration => int_to_bigint(x.ns),
        _ => 0n,
    }
}

function int_to_bigint(i: int) -> bigint {
    // No direct int → bigint conversion exists; `0n + i` uses Add<int> for bigint.
    0n + i
}

function go_float(v: unknown) -> float {
    match (v) {
        let f: float => f,
        let x: root.go.Float32 => x.v,
        _ => 0.0,
    }
}

// The elements of a slice/array value, whatever its element type.
function go_slice(v: unknown) -> unknown[] {
    let out: unknown[] = [];
    let at = reflect.Type.of_value(v).as_array();
    if (at == null) {
        return out;
    }
    type E = unreflect(at.element_type());
    let arr: E[] = v else {
        return out;
    };
    for (let x in arr) {
        out.push(x);
    }
    out
}

// The entries of a map value, or null if its key type is not string (Go:
// errNonString). BAML map keys are always strings today, so the null case is
// unreachable in practice.
function go_map(v: unknown) -> map<string, unknown>? {
    let mt = reflect.Type.of_value(v).as_map();
    if (mt == null) {
        return null;
    }
    if (mt.key_type() != reflect.Type.of<string>()) {
        return null;
    }
    type V = unreflect(mt.value_type());
    let m: map<string, V> = v else {
        return null;
    };
    let out: map<string, unknown> = {};
    for (let k in m.keys()) {
        out.set(k, m[k]);
    }
    out
}

// One field of a class value (reflect.StructField plus its reflect.Value).
class GoField {
    name: string,
    tag: string, // Go struct tag syntax, e.g. `toml:"name,omitempty"`
    value: unknown,
    typ: reflect.Type?,
    anonymous: bool,
    unexported: bool,
    is_pointer: bool,
    // pointerTo(f.Type).Kind() == reflect.Struct
    value_kind_is_struct: bool,
}

// A field of a class *type* (reflect.StructField, no value).
class GoTypeField {
    name: string,
    tag: string,
    typ: reflect.Type?,
    anonymous: bool,
    unexported: bool,
    is_pointer: bool,
    value_kind_is_struct: bool,
}

// The Go struct tag for a BAML field's metadata. `@description` holding a
// Go-style tag (`toml:"..."`) is used verbatim; `@skip` adds `toml:"-"` and
// `@alias("x")` adds `toml:"x"` when no toml tag was given.
function go_tag_of(meta: reflect.Meta) -> string {
    let tag = "";
    let d = meta.description;
    if (d != null) {
        if (d.includes(":\"")) {
            tag = d;
        }
    }
    if (meta.skip) {
        return tag + " toml:\"-\"";
    }
    let alias = meta.alias;
    if (alias != null && struct_tag_get(tag, "toml") == "") {
        tag = tag + " toml:\"" + alias + "\"";
    }
    tag
}

// Strip `null` from an optional type: the pointer's element type.
function deref_type(t: reflect.Type) -> reflect.Type {
    let u = t.as_union();
    if (u == null) {
        return t;
    }
    let members: reflect.Type[] = [];
    for (let m in u.member_types()) {
        if (m != reflect.Type.of<null>()) {
            members.push(m);
        }
    }
    if (members.length() == 1) {
        return members[0];
    }
    t
}

function type_is_optional(t: reflect.Type?) -> bool {
    if (t == null) {
        return false;
    }
    let u = t.as_union();
    if (u == null) {
        return false;
    }
    for (let m in u.member_types()) {
        if (m == reflect.Type.of<null>()) {
            return true;
        }
    }
    false
}

// Is `t` a "struct" in Go terms: a class that is not one of the port's
// value-like wrapper classes.
function type_is_struct(t: reflect.Type) -> bool {
    if (t.as_class() == null) {
        return false;
    }
    !is_scalar_class_type(t)
}

function is_scalar_class_type(t: reflect.Type) -> bool {
    t == reflect.Type.of<root.go.Int8>() || t == reflect.Type.of<root.go.Int16>() || t == reflect.Type.of<root.go.Int32>()
        || t == reflect.Type.of<root.go.Uint>() || t == reflect.Type.of<root.go.Uint8>()
        || t == reflect.Type.of<root.go.Uint16>() || t == reflect.Type.of<root.go.Uint32>()
        || t == reflect.Type.of<root.go.Uint64>() || t == reflect.Type.of<root.go.Float32>()
        || t == reflect.Type.of<root.go.Number>() || t == reflect.Type.of<root.go.Duration>()
}

function go_type_fields(t: reflect.Type) -> GoTypeField[] {
    let out: GoTypeField[] = [];
    let ct = t.as_class();
    if (ct == null) {
        return out;
    }
    for (let f in ct.fields()) {
        let tag = go_tag_of(f.meta);
        let ft = f.type;
        let vt = if (ft == null) { null } else { deref_type(ft) };
        out.push(GoTypeField {
            name: f.name,
            tag: tag,
            typ: ft,
            anonymous: struct_tag_get(tag, "go") == "embed",
            unexported: f.name.starts_with("_"),
            is_pointer: type_is_optional(ft),
            value_kind_is_struct: if (vt == null) { false } else { type_is_struct(vt) },
        });
    }
    out
}

function go_struct_fields(v: unknown) -> GoField[] {
    let out: GoField[] = [];
    let c: reflect.AnyClass = v else {
        return out;
    };
    let tfs = go_type_fields(reflect.Type.of_value(v));
    let i = 0;
    for (let f in c.list_fields()) {
        let val = f.value<unknown>() catch (e) {
            _ => null
        };
        let tf = tfs[i];
        i += 1;
        out.push(GoField {
            name: tf.name,
            tag: tf.tag,
            value: val,
            typ: tf.typ,
            anonymous: tf.anonymous,
            unexported: tf.unexported,
            is_pointer: tf.is_pointer,
            value_kind_is_struct: tf.value_kind_is_struct,
        });
    }
    out
}

// reflect.StructTag.Get(key): the value for `key` in a Go struct tag, "" if
// absent.
function struct_tag_get(tag0: string, key: string) -> string {
    let tag = tag0;
    while (tag != "") {
        // Skip leading space.
        let i = 0;
        while (i < tag.length() && tag.at(i) == " ") {
            i += 1;
        }
        tag = tag.slice(i, tag.length());
        if (tag == "") {
            break;
        }
        // Scan to colon.
        i = 0;
        while (i < tag.length()) {
            let c = tag.at(i) ?? "";
            if (c <= " " || c == ":" || c == "\"" || c == string.from_code_points([127]) catch (e) { _ => "" }) {
                break;
            }
            i += 1;
        }
        if (i == 0 || i + 1 >= tag.length() || tag.at(i) != ":" || tag.at(i + 1) != "\"") {
            break;
        }
        let name = tag.slice(0, i);
        tag = tag.slice(i + 1, tag.length());

        // Scan quoted string to find value.
        i = 1;
        while (i < tag.length() && tag.at(i) != "\"") {
            if (tag.at(i) == "\\") {
                i += 1;
            }
            i += 1;
        }
        if (i >= tag.length()) {
            break;
        }
        let qvalue = tag.slice(1, i);
        tag = tag.slice(i + 1, tag.length());

        if (key == name) {
            return qvalue.replace_all("\\\"", "\"").replace_all("\\\\", "\\");
        }
    }
    ""
}

// Would Go consider the struct type of `v` comparable (no slice/map/func
// fields, recursively)?
function is_comparable_struct(v: unknown) -> bool {
    type_is_comparable(reflect.Type.of_value(v), 0)
}

function type_is_comparable(t: reflect.Type, depth: int) -> bool {
    if (depth > 20) {
        return true;
    }
    if (t.as_array() != null || t.as_map() != null || t.as_function() != null) {
        return false;
    }
    let u = t.as_union();
    if (u != null) {
        // A pointer is comparable (by address).
        if (type_is_optional(t)) {
            return true;
        }
        for (let m in u.member_types()) {
            if (!type_is_comparable(m, depth + 1)) {
                return false;
            }
        }
        return true;
    }
    let ct = t.as_class();
    if (ct != null) {
        for (let f in ct.fields()) {
            let ft = f.type;
            if (ft != null) {
                if (!type_is_comparable(ft, depth + 1)) {
                    return false;
                }
            }
        }
    }
    true
}

// reflect.Zero(t).Interface() == v, for comparable values.
function is_zero_value(v: unknown) -> bool {
    match (v) {
        null => true,
        let b: bool => !b,
        let i: int => i == 0,
        let i: bigint => i == 0n,
        let f: float => f == 0.0,
        let s: string => s == "",
        let t: root.go.Time => t.is_zero(),
        _ => {
            match (go_kind(v)) {
                "int" | "uint" => {
                    return go_int(v) == 0n;
                },
                "float32" | "float64" => {
                    return go_float(v) == 0.0;
                },
                "string" => {
                    return go_string(v) == "";
                },
                _ => {},
            }
            let c: reflect.AnyClass = v else {
                return false;
            };
            for (let f in c.list_fields()) {
                let fv = f.value<unknown>() catch (e) {
                    _ => null
                };
                if (!is_zero_value(fv)) {
                    return false;
                }
            }
            true
        },
    }
}
