// Port of type_fields.go.
//
// Struct field handling is adapted from code in encoding/json:
//
// Copyright 2010 The Go Authors.  All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the Go distribution.
//
// BAML classes have no anonymous (embedded) fields; the port marks a field as
// embedded with the pseudo struct tag `go:"embed"` (see encode.baml), so the
// breadth-first search and the dominance rules below are kept intact.

// A field represents a single field found in a struct.
class Field {
    name: string, // the name of the field (`toml` tag included)
    tag: bool, // whether field has a `toml` tag
    index: int[], // represents the depth of an anonymous field
    typ: reflect.Type, // the type of the field
}

// byName sorts field by name, breaking ties with depth,
// then breaking ties with "name came from toml tag", then
// breaking ties with index sequence.
function by_name_less(a: Field, b: Field) -> bool {
    if (a.name != b.name) {
        return a.name < b.name;
    }
    if (a.index.length() != b.index.length()) {
        return a.index.length() < b.index.length();
    }
    if (a.tag != b.tag) {
        return a.tag;
    }
    by_index_less(a, b)
}

// byIndex sorts field by index sequence.
function by_index_less(a: Field, b: Field) -> bool {
    let k = 0;
    for (let xik in a.index) {
        if (k >= b.index.length()) {
            return false;
        }
        if (xik != b.index[k]) {
            return xik < b.index[k];
        }
        k += 1;
    }
    a.index.length() < b.index.length()
}

function less_to_ordering(less: bool, greater: bool) -> baml.ops.Ordering {
    if (less) {
        return baml.ops.Ordering.Less;
    }
    if (greater) {
        return baml.ops.Ordering.Greater;
    }
    baml.ops.Ordering.Equal
}

// typeFields returns a list of fields that TOML should recognize for the given
// type. The algorithm is breadth-first search over the set of structs to
// include - the top struct and then any reachable anonymous structs.
function type_fields(t: reflect.Type) -> Field[] {
    // Anonymous fields to explore at the current level and the next.
    let current: Field[] = [];
    let next: Field[] = [Field { name: "", tag: false, index: [], typ: t }];

    // Count of queued names for current level and the next.
    // (Go keys these maps by reflect.Type; BAML map keys must be strings, so
    // the type's rendered name is used.)
    let count: map<string, int> = {};
    let next_count: map<string, int> = {};

    // Types already visited at an earlier level.
    let visited: map<string, bool> = {};

    // Fields found.
    let fields: Field[] = [];

    while (next.length() > 0) {
        current = next;
        next = [];
        count = next_count;
        next_count = {};

        for (let f in current) {
            let tkey = f.typ.to_string();
            if (visited.has(tkey)) {
                continue;
            }
            visited.set(tkey, true);

            // Scan f.typ for fields to include.
            let i = 0;
            for (let sf in go_type_fields(f.typ)) {
                let this_i = i;
                i += 1;
                if (sf.unexported && !sf.anonymous) { // unexported
                    continue;
                }
                let opts = get_options(sf.tag);
                if (opts.skip) {
                    continue;
                }
                let index = f.index.concat([this_i]);

                let ft0 = sf.typ ?? reflect.Type.of<unknown>();
                // Follow pointer.
                let ft = deref_type(ft0);

                // Record found field and index sequence.
                if (opts.name != "" || !sf.anonymous || !type_is_struct(ft)) {
                    let tagged = opts.name != "";
                    let name = opts.name;
                    if (name == "") {
                        name = sf.name;
                    }
                    fields.push(Field { name: name, tag: tagged, index: index, typ: ft });
                    if ((count.get(tkey) ?? 0) > 1) {
                        // If there were multiple instances, add a second,
                        // so that the annihilation code will see a duplicate.
                        // It only cares about the distinction between 1 or 2,
                        // so don't bother generating any more copies.
                        fields.push(fields[fields.length() - 1]);
                    }
                    continue;
                }

                // Record new anonymous struct to explore in next round.
                let fkey = ft.to_string();
                next_count.set(fkey, (next_count.get(fkey) ?? 0) + 1);
                if ((next_count.get(fkey) ?? 0) == 1) {
                    next.push(Field { name: ft.to_string(), tag: false, index: index, typ: ft });
                }
            }
        }
    }

    fields = fields.sort_by((a: Field, b: Field) -> baml.ops.Ordering {
        less_to_ordering(by_name_less(a, b), by_name_less(b, a))
    });

    // Delete all fields that are hidden by the Go rules for embedded fields,
    // except that fields with TOML tags are promoted.

    // The fields are sorted in primary order of name, secondary order
    // of field index length. Loop over names; for each name, delete
    // hidden fields by choosing the one dominant field that survives.
    let out: Field[] = [];
    let advance = 0;
    let i = 0;
    while (i < fields.length()) {
        // One iteration per name.
        // Find the sequence of fields with the name of this first field.
        let fi = fields[i];
        let name = fi.name;
        advance = 1;
        while (i + advance < fields.length()) {
            let fj = fields[i + advance];
            if (fj.name != name) {
                break;
            }
            advance += 1;
        }
        if (advance == 1) { // Only one field with this name
            out.push(fi);
            i += advance;
            continue;
        }
        let dominant = dominant_field(fields.slice(i, i + advance));
        if (dominant != null) {
            out.push(dominant);
        }
        i += advance;
    }

    fields = out.sort_by((a: Field, b: Field) -> baml.ops.Ordering {
        less_to_ordering(by_index_less(a, b), by_index_less(b, a))
    });

    fields
}

// dominantField looks through the fields, all of which are known to
// have the same name, to find the single field that dominates the
// others using Go's embedding rules, modified by the presence of
// TOML tags. If there are multiple top-level fields, the boolean
// will be false: This condition is an error in Go and we skip all
// the fields.
//
// (Go returns (field, bool); the port returns null for "false".)
function dominant_field(fields0: Field[]) -> Field? {
    // The fields are sorted in increasing index-length order. The winner
    // must therefore be one with the shortest index length. Drop all
    // longer entries, which is easy: just truncate the slice.
    let fields = fields0;
    let length = fields[0].index.length();
    let tagged = -1; // Index of first tagged field.
    let i = 0;
    for (let f in fields0) {
        if (f.index.length() > length) {
            fields = fields0.slice(0, i);
            break;
        }
        if (f.tag) {
            if (tagged >= 0) {
                // Multiple tagged fields at the same level: conflict.
                // Return no field.
                return null;
            }
            tagged = i;
        }
        i += 1;
    }
    if (tagged >= 0) {
        return fields[tagged];
    }
    // All remaining fields have the same length. If there's more than one,
    // we have a conflict (two fields named "X" at the same level) and we
    // return no field.
    if (fields.length() > 1) {
        return null;
    }
    fields[0]
}

// cachedTypeFields is like typeFields but uses a cache to avoid repeated work.
//
// Go caches in a package-level map guarded by a sync.RWMutex. BAML has no
// package-level mutable state, so the port recomputes every time.
function cached_type_fields(t: reflect.Type) -> Field[] {
    type_fields(t)
}
