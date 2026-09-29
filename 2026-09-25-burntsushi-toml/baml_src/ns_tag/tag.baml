// Port of internal/tag/add.go and internal/tag/rm.go (namespace root.tag).
//
// Go returns `any` built from map[string]any / []any that is later passed to
// encoding/json. The port builds the JSON value (baml.json.json) directly.

// Add JSON tags to a data structure as expected by toml-test.
function add(key: string, toml_data: root.Any?) -> baml.json.json {
    // Switch on the data type.
    match (toml_data) {
        // A table: we don't need to add any tags, just recurse for every table
        // entry.
        let orig: map<string, root.Any> => {
            let typed: map<string, baml.json.json> = {};
            for (let k in orig.keys()) {
                typed.set(k, add(k, orig[k]));
            }
            typed
        },
        // An array: we don't need to add any tags, just recurse for every table
        // entry.
        let orig: map<string, root.Any>[] => {
            let typed: baml.json.json[] = [];
            for (let v in orig) {
                typed.push(add("", v));
            }
            typed
        },
        let orig: root.Any[] => {
            let typed: baml.json.json[] = [];
            for (let v in orig) {
                typed.push(add("", v));
            }
            typed
        },
        // Datetime: tag as datetime.
        let orig: root.go.Time => {
            let loc = orig.location();
            if (root.go.same_location(loc, root.local_datetime())) {
                tag("datetime-local", orig.format("2006-01-02T15:04:05.999999999"))
            } else if (root.go.same_location(loc, root.local_date())) {
                tag("date-local", orig.format("2006-01-02"))
            } else if (root.go.same_location(loc, root.local_time())) {
                tag("time-local", orig.format("15:04:05.999999999"))
            } else {
                tag("datetime", orig.format("2006-01-02T15:04:05.999999999Z07:00"))
            }
        },
        // Tag primitive values: bool, string, int, and float64.
        let orig: bool => tag("bool", root.go.format_bool(orig)),
        let orig: string => tag("string", orig),
        let orig: bigint => tag("integer", orig.to_string()),
        let orig: float => {
            if (orig.is_nan()) {
                tag("float", "nan")
            } else if (orig.is_infinite() && orig > 0.0) {
                tag("float", "inf")
            } else if (orig.is_infinite()) {
                tag("float", "-inf")
            } else {
                tag("float", root.go.format_float_g(orig, 64))
            }
        },
        null => root.go_panic("Unknown type: <nil>"),
    }
}

function tag(type_name: string, data: string) -> baml.json.json {
    { "type": type_name, "value": data }
}

// Remove JSON tags to a data structure as returned by toml-test.
function remove(typed_json: baml.json.json) -> root.Any {
    // Switch on the data type.
    match (typed_json) {
        // Object: this can either be a TOML table or a primitive with tags.
        let v: map<string, baml.json.json> => {
            // This value represents a primitive: remove the tags and return just
            // the primitive value.
            if (v.length() == 2 && v.has("type") && v.has("value")) {
                let ut = untag(v) catch (err) {
                    let e: root.GoError => {
                        throw root.GoError { msg: `tag.Remove: ${e.msg}`, wrapped: e }
                    },
                };
                return ut;
            }

            // Table: remove tags on all children.
            let m: map<string, root.Any> = {};
            for (let k in v.keys()) {
                m.set(k, remove(v[k]));
            }
            m
        },
        // Array: remove tags from all items.
        let v: baml.json.json[] => {
            let a: root.Any[] = [];
            for (let x in v) {
                a.push(remove(x));
            }
            a
        },
        // The top level must be an object or array.
        _ => {
            throw root.GoError { msg: `tag.Remove: unrecognized JSON format '${json_type_name(typed_json)}'`, wrapped: null }
        },
    }
}

function json_type_name(j: baml.json.json) -> string {
    match (j) {
        null => "<nil>",
        let b: bool => "bool",
        let s: string => "string",
        let i: int => "float64",
        let i: bigint => "float64",
        let f: float => "float64",
        _ => "unknown",
    }
}

// Return a primitive: read the "type" and convert the "value" to that.
function untag(typed: map<string, baml.json.json>) -> root.Any {
    let t = match (typed["type"]) {
        let s: string => s,
        _ => root.go_panic("interface conversion: type is not a string"),
    };
    let v = match (typed["value"]) {
        let s: string => s,
        _ => root.go_panic("interface conversion: value is not a string"),
    };
    match (t) {
        "string" => v,
        "integer" => {
            let n = root.go.parse_int(v, 10, 64);
            if (n.err != "") {
                throw root.GoError { msg: `untag: strconv.ParseInt: parsing ${root.go.quote(v)}: invalid syntax`, wrapped: null };
            }
            n.value
        },
        "float" => {
            let f = root.go.parse_float(v);
            if (f.err != "") {
                throw root.GoError { msg: `untag: strconv.ParseFloat: parsing ${root.go.quote(v)}: invalid syntax`, wrapped: null };
            }
            f.value
        },
        "datetime" => parse_time(v, "2006-01-02T15:04:05.999999999Z07:00", null),
        "datetime-local" => parse_time(v, "2006-01-02T15:04:05.999999999", root.local_datetime()),
        "date-local" => parse_time(v, "2006-01-02", root.local_date()),
        "time-local" => parse_time(v, "15:04:05.999999999", root.local_time()),
        "bool" => {
            match (v) {
                "true" => true,
                "false" => false,
                _ => {
                    throw root.GoError { msg: `untag: could not parse ${root.go.quote(v)} as a boolean`, wrapped: null }
                },
            }
        },
        _ => {
            throw root.GoError { msg: `untag: unrecognized tag type ${root.go.quote(t)}`, wrapped: null }
        },
    }
}

function parse_time(v: string, format: string, l0: root.go.Location?) -> root.go.Time {
    let l = l0 ?? root.go.utc();
    // Parse the wall-clock value directly into the target location, matching
    // how the decoder builds local datetimes/dates/times. Using time.Parse and
    // then .In(l) would instead shift the value by l's offset.
    let t = root.go.parse_in_location(format, v, l);
    match (t) {
        null => {
            throw root.GoError { msg: `could not parse ${root.go.quote(v)} as a datetime`, wrapped: null }
        },
        let tt: root.go.Time => tt,
    }
}
