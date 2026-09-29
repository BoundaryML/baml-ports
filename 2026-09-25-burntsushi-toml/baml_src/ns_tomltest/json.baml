// Port of internal/toml-test/json.go (namespace root.tomltest).
//
// CompareJSON compares the given arguments.
//
// The returned value is a copy of Test with Failure set to a (human-readable)
// description of the first element that is unequal. If both arguments are
// equal, Test is returned unchanged.
//
// reflect.DeepEqual could work here, but it won't tell us how the two
// structures are different.
function compare_json(r: Test, want: baml.json.json, have: baml.json.json) -> Test {
    match (want) {
        let w: map<string, baml.json.json> => cmp_json_maps(r, w, have),
        let w: baml.json.json[] => cmp_json_arrays(r, w, have),
        _ => r.fail(`Key ${root.go.quote(r.key)} in expected output should be a map or a list of maps, but it's a ${json_fmt_type(want)}`),
    }
}

function cmp_json_maps(r: Test, want: map<string, baml.json.json>, have: baml.json.json) -> Test {
    let have_map: map<string, baml.json.json> = match (have) {
        let m: map<string, baml.json.json> => m,
        _ => {
            return mismatch(r, "table", have);
        },
    };

    // Check to make sure both or neither are values.
    if (is_value(want) && !is_value(have_map)) {
        return r.fail(`Key ${root.go.quote(r.key)} is supposed to be a value, but the parser reports it as a table`);
    }
    if (!is_value(want) && is_value(have_map)) {
        return r.fail(`Key ${root.go.quote(r.key)} is supposed to be a table, but the parser reports it as a value`);
    }
    if (is_value(want) && is_value(have_map)) {
        return cmp_json_values(r, want, have_map);
    }

    let want_keys = map_keys(want.keys());
    let have_keys = map_keys(have_map.keys());

    // Check that the keys of each map are equivalent.
    for (let k in want_keys) {
        if (!have_map.has(k)) {
            let bunk = r.kjoin(k);
            return bunk.fail(`Could not find key ${root.go.quote(bunk.key)} in parser output.`);
        }
    }
    for (let k in have_keys) {
        if (!want.has(k)) {
            let bunk = r.kjoin(k);
            return bunk.fail(`Could not find key ${root.go.quote(bunk.key)} in expected output.`);
        }
    }

    // Okay, now make sure that each value is equivalent.
    for (let k in want_keys) {
        let sub = compare_json(r.kjoin(k), want[k], have_map[k]);
        if (sub.failed()) {
            return sub;
        }
    }
    r
}

function cmp_json_arrays(r: Test, want: baml.json.json, have: baml.json.json) -> Test {
    let want_slice: baml.json.json[] = match (want) {
        let a: baml.json.json[] => a,
        _ => {
            return r.bug(`'value' should be a JSON array when 'type=array', but it is a ${json_fmt_type(want)}`);
        },
    };

    let have_slice: baml.json.json[] = match (have) {
        let a: baml.json.json[] => a,
        _ => {
            return r.fail(`Malformed output from your encoder: 'value' is not a JSON array: ${json_fmt_type(have)}`);
        },
    };

    if (want_slice.length() != have_slice.length()) {
        return r.fail(`Array lengths differ for key ${root.go.quote(r.key)}:\n  Expected:     ${want_slice.length()}\n  Your encoder: ${have_slice.length()}`);
    }
    let i = 0;
    while (i < want_slice.length()) {
        let sub = compare_json(r, want_slice[i], have_slice[i]);
        if (sub.failed()) {
            return sub;
        }
        i += 1;
    }
    r
}

function cmp_json_values(r: Test, want: map<string, baml.json.json>, have: map<string, baml.json.json>) -> Test {
    let want_type = match (want["type"]) {
        let s: string => s,
        _ => {
            return r.bug(`'type' should be a string, but it is a ${json_fmt_type(want["type"])}`);
        },
    };

    let have_type = match (have["type"]) {
        let s: string => s,
        _ => {
            return r.fail(`Malformed output from your encoder: 'type' is not a string: ${json_fmt_type(have["type"])}`);
        },
    };

    if (want_type == "integer" && r.int_as_float) {
        want_type = "float";
    }

    if (want_type != have_type) {
        return val_mismatch(r, want_type, have_type, want, have);
    }

    // If this is an array, then we've got to do some work to check equality.
    if (want_type == "array") {
        return cmp_json_arrays(r, want, have);
    }

    // Atomic values are always strings
    let want_val = match (want["value"]) {
        let s: string => s,
        _ => {
            return r.bug(`'value' should be a string, but it is a ${json_fmt_type(want["value"])}`);
        },
    };

    let have_val = match (have["value"]) {
        let s: string => s,
        _ => {
            return r.fail(`Malformed output from your encoder: ${json_fmt_type(have["value"])} is not a string`);
        },
    };

    // Excepting floats and datetimes, other values can be compared as strings.
    match (want_type) {
        "float" => cmp_floats(r, want_val, have_val),
        "datetime" | "datetime-local" | "date-local" | "time-local" => cmp_as_datetimes(r, want_type, want_val, have_val),
        _ => {
            if (want_type == "bool") {
                return cmp_as_strings(r, want_val.to_lower_case(), have_val.to_lower_case());
            }
            cmp_as_strings(r, want_val, have_val)
        },
    }
}

function cmp_as_strings(r: Test, want: string, have: string) -> Test {
    if (want != have) {
        return r.fail(`Values for key ${root.go.quote(r.key)} don't match:\n  Expected:     ${want}\n  Your encoder: ${have}`);
    }
    r
}

function trim_left_signs(s: string) -> string {
    let out = s;
    while (out.starts_with("-") || out.starts_with("+")) {
        out = out.slice(1, out.length());
    }
    out
}

function cmp_floats(r: Test, want0: string, have0: string) -> Test {
    // Special case for NaN, since NaN != NaN.
    let want = want0.to_lower_case();
    let have = have0.to_lower_case();
    if (want.ends_with("nan") || have.ends_with("nan")) {
        let w = trim_left_signs(want);
        let h = trim_left_signs(have);
        if (w != h) {
            return r.fail(`Values for key ${root.go.quote(r.key)} don't match:\n  Expected:     ${w}\n  Your encoder: ${h}`);
        }
        return r;
    }

    let want_f = root.go.parse_float(want);
    if (want_f.err != "") {
        return r.bug(`Could not read ${root.go.quote(want)} as a float value for key ${root.go.quote(r.key)}`);
    }

    let have_f = root.go.parse_float(have);
    if (have_f.err != "") {
        return r.fail(`Malformed output from your encoder: key ${root.go.quote(r.key)} is not a float: ${root.go.quote(have)}`);
    }

    if (want_f.value != have_f.value) {
        return r.fail(`Values for key ${root.go.quote(r.key)} don't match:\n  Expected:     ${root.go.format_float_g(want_f.value, 64)}\n  Your encoder: ${root.go.format_float_g(have_f.value, 64)}`);
    }
    r
}

// var datetimeRepl = strings.NewReplacer(" ", "T", "t", "T", "z", "Z")
function datetime_repl(s: string) -> string {
    s.replace_all(" ", "T").replace_all("t", "T").replace_all("z", "Z")
}

function layouts() -> map<string, string> {
    {
        "datetime": root.go.rfc3339_nano(),
        "datetime-local": "2006-01-02T15:04:05.999999999",
        "date-local": "2006-01-02",
        "time-local": "15:04:05",
    }
}

function cmp_as_datetimes(r: Test, kind: string, want: string, have: string) -> Test {
    let layout = layouts().get(kind) ?? root.go_panic("should never happen");

    let want_t = root.go.parse_in_location(layout, datetime_repl(want), root.go.utc());
    if (want_t == null) {
        return r.bug(`Could not read ${root.go.quote(want)} as a datetime value for key ${root.go.quote(r.key)}`);
    }
    let have_t = root.go.parse_in_location(layout, datetime_repl(have), root.go.utc());
    if (have_t == null) {
        return r.fail(`Malformed output from your encoder: key ${root.go.quote(r.key)} is not a datetime: ${root.go.quote(have)}`);
    }

    if (want_t.unix_nano_key() != have_t.unix_nano_key()) {
        return r.fail(`Values for key ${root.go.quote(r.key)} don't match:\n  Expected:     ${want_t.to_string()}\n  Your encoder: ${have_t.to_string()}`);
    }
    r
}

function is_value(m: map<string, baml.json.json>) -> bool {
    if (m.length() != 2) {
        return false;
    }
    if (!m.has("type")) {
        return false;
    }
    if (!m.has("value")) {
        return false;
    }
    true
}

function mismatch(r: Test, want_type: string, have: baml.json.json) -> Test {
    r.fail(`Key ${root.go.quote(r.key)} (type ${root.go.quote(want_type)}):\n  Expected:     ${baml.json.stringify(have)}\n  Your encoder: ${json_fmt_type(have)}`)
}

function val_mismatch(r: Test, want_type: string, have_type: string, want: baml.json.json, have: baml.json.json) -> Test {
    r.fail(`Key ${root.go.quote(r.key)} is not ${root.go.quote(want_type)} but ${root.go.quote(have_type)}:\n  Expected:     ${baml.json.stringify(want)}\n  Your encoder: ${baml.json.stringify(have)}`)
}

// fmt %T of a decoded JSON value, with "interface {}" replaced with "any".
function json_fmt_type(j: baml.json.json) -> string {
    match (j) {
        null => "<nil>",
        let b: bool => "bool",
        let s: string => "string",
        let i: int => "float64",
        let i: bigint => "float64",
        let f: float => "float64",
        let a: baml.json.json[] => "[]any",
        let m: map<string, baml.json.json> => "map[string]any",
    }
}

function map_keys(keys: string[]) -> string[] {
    keys.sort_by((a: string, b: string) -> baml.ops.Ordering { a.cmp(b) })
}
