// Port of internal/toml-test/toml.go (namespace root.tomltest).
//
// CompareTOML compares the given arguments.
//
// The returned value is a copy of Test with Failure set to a (human-readable)
// description of the first element that is unequal. If both arguments are equal
// Test is returned unchanged.
//
// Reflect.DeepEqual could work here, but it won't tell us how the two
// structures are different.
function compare_toml(r: Test, want: root.Any?, have: root.Any?) -> Test {
    if (is_toml_value(want)) {
        if (!is_toml_value(have)) {
            return r.fail(`Type for key ${root.go.quote(r.key)} differs:\n  Expected:     ${fmt_val(want)} (${root.fmt_type(want)})\n  Your encoder: ${fmt_val(have)} (${root.fmt_type(have)})`);
        }

        if (!deep_equal(want, have)) {
            return r.fail(`Values for key ${root.go.quote(r.key)} differ:\n  Expected:     ${fmt_val(want)} (${root.fmt_type(want)})\n  Your encoder: ${fmt_val(have)} (${root.fmt_type(have)})`);
        }
        return r;
    }

    match (want) {
        let w: map<string, root.Any> => cmp_toml_map(r, w, have),
        let w: map<string, root.Any>[] => {
            let ww: root.Any[] = [];
            for (let v in w) {
                ww.push(v);
            }
            cmp_toml_arrays(r, ww, have)
        },
        let w: root.Any[] => cmp_toml_arrays(r, w, have),
        _ => r.fail(`Unrecognized TOML structure: ${root.fmt_type(want)}`),
    }
}

function cmp_toml_map(r: Test, want: map<string, root.Any>, have: root.Any?) -> Test {
    let have_map: map<string, root.Any> = match (have) {
        let m: map<string, root.Any> => m,
        _ => {
            return r.fail(`Key ${root.go.quote(r.key)} (type "table"):\n  Expected:     ${fmt_val(have)}\n  Your encoder: ${root.fmt_type(have)}`);
        },
    };

    let want_keys = map_keys(want.keys());
    let have_keys = map_keys(have_map.keys());

    // Check that the keys of each map are equivalent.
    for (let k in want_keys) {
        if (!have_map.has(k)) {
            let bunk = r.kjoin(k);
            return bunk.fail(`Could not find key ${root.go.quote(bunk.key)} in encoder output`);
        }
    }
    for (let k in have_keys) {
        if (!want.has(k)) {
            let bunk = r.kjoin(k);
            return bunk.fail(`Could not find key ${root.go.quote(bunk.key)} in expected output`);
        }
    }

    // Okay, now make sure that each value is equivalent.
    for (let k in want_keys) {
        let sub = compare_toml(r.kjoin(k), want[k], have_map[k]);
        if (sub.failed()) {
            return sub;
        }
    }
    r
}

function cmp_toml_arrays(r: Test, want: root.Any[], have: root.Any?) -> Test {
    // Slice can be decoded to []any for an array of primitives, or
    // []map[string]any for an array of tables.
    //
    // TODO: it would be nicer if it could always decode to []any?
    let have_slice: root.Any[] = match (have) {
        let a: root.Any[] => a,
        let tbl_array: map<string, root.Any>[] => {
            let tmp: root.Any[] = [];
            for (let t in tbl_array) {
                tmp.push(t);
            }
            tmp
        },
        _ => {
            return r.fail(`Key ${root.go.quote(r.key)} (type "array"):\n  Expected:     ${fmt_val(have)}\n  Your encoder: ${root.fmt_type(have)}`);
        },
    };

    if (want.length() != have_slice.length()) {
        return r.fail(`Array lengths differ for key ${root.go.quote(r.key)}  Expected:     (len=${want.length()})\n  Your encoder: (len=${have_slice.length()})`);
    }
    let i = 0;
    while (i < want.length()) {
        let sub = compare_toml(r, want[i], have_slice[i]);
        if (sub.failed()) {
            return sub;
        }
        i += 1;
    }
    r
}

// reflect.DeepEqual() that deals with NaN != NaN
function deep_equal(want: root.Any?, have: root.Any?) -> bool {
    match (want) {
        let wf: float => {
            match (have) {
                let hf: float => {
                    if (wf.is_nan() && hf.is_nan()) {
                        return true;
                    }
                    // reflect.DeepEqual uses ==, so 0.0 == -0.0.
                    return wf == hf || (wf == 0.0 && hf == 0.0);
                },
                _ => {
                    return false;
                },
            }
        },
        // Time.Equal deals with some edge-cases such as offset +0000 and Z being
        // identical.
        let wt: root.go.Time => {
            match (have) {
                let ht: root.go.Time => {
                    return wt.unix_nano_key() == ht.unix_nano_key();
                },
                _ => {
                    return false;
                },
            }
        },
        let ws: string => {
            match (have) {
                let hs: string => {
                    return ws == hs;
                },
                _ => {
                    return false;
                },
            }
        },
        let wi: bigint => {
            match (have) {
                let hi: bigint => {
                    return wi == hi;
                },
                _ => {
                    return false;
                },
            }
        },
        let wb: bool => {
            match (have) {
                let hb: bool => {
                    return wb == hb;
                },
                _ => {
                    return false;
                },
            }
        },
        _ => {},
    }
    false
}

function is_toml_value(v: root.Any?) -> bool {
    match (v) {
        let m: map<string, root.Any> => false,
        let m: map<string, root.Any>[] => false,
        let a: root.Any[] => false,
        _ => true,
    }
}

function fmt_val(v: root.Any?) -> string {
    match (v) {
        let f: float => root.go.format_float_g(f, 64),
        let s: string => s,
        let i: bigint => i.to_string(),
        let b: bool => root.go.format_bool(b),
        let t: root.go.Time => t.to_string(),
        null => "<nil>",
        _ => root.fmt_type(v),
    }
}
