// `Vec` / `HashMap` / `HashSet` operations with no direct BAML builtin.
// Arrays and maps are reference types, so the "in place" helpers mutate the
// caller's container exactly as Rust's `&mut self` methods do.

/// `v.retain(|x| pred(x))`.
function retain<T>(v: T[], pred: (T) -> bool) -> void {
    let kept = v.filter(pred);
    v.clear();
    for (let x in kept) {
        v.push(x);
    }
}

/// `v.truncate(n)`.
function truncate<T>(v: T[], n: int) -> void {
    while (v.length() > n) {
        let _ = v.pop();
    }
}

/// `v.extend(other)` / `v.extend_from_slice(other)` / `v.append(&mut other)`
/// (the last also clears `other`; do that at the call site).
function extend<T>(v: T[], other: T[]) -> void {
    for (let x in other) {
        v.push(x);
    }
}

/// `v.dedup()` — drop consecutive structural duplicates.
function dedup<T>(v: T[]) -> void {
    if (v.length() < 2) {
        return;
    }
    let out: T[] = [v[0]];
    let i = 1;
    while (i < v.length()) {
        if (v[i] != out[out.length() - 1]) {
            out.push(v[i]);
        }
        i += 1;
    }
    v.clear();
    for (let x in out) {
        v.push(x);
    }
}

/// `v.dedup_by_key(|x| key(x))`.
function dedup_by_key<T>(v: T[], key: (T) -> string) -> void {
    if (v.length() < 2) {
        return;
    }
    let out: T[] = [v[0]];
    let last = key(v[0]);
    let i = 1;
    while (i < v.length()) {
        let k = key(v[i]);
        if (k != last) {
            out.push(v[i]);
            last = k;
        }
        i += 1;
    }
    v.clear();
    for (let x in out) {
        v.push(x);
    }
}

/// `v.swap(i, j)`.
function swap<T>(v: T[], i: int, j: int) -> void {
    let t = v[i];
    v[i] = v[j];
    v[j] = t;
}

/// `std::mem::take(&mut v)` for a Vec: return the elements, leave it empty.
function take_all<T>(v: T[]) -> T[] {
    let out = v.slice(0, v.length());
    v.clear();
    out
}

/// `v.drain(start..end).collect()` — remove and return that range.
function drain<T>(v: T[], start: int, end: int) -> T[] {
    let out = v.slice(start, end);
    v.splice(start, end - start, []) catch (e) {
        _ => baml.sys.panic("std.drain: range out of bounds")
    };
    out
}

/// `v.split_off(at)` — keep `[0, at)`, return `[at, len)`.
function split_off<T>(v: T[], at: int) -> T[] {
    drain(v, at, v.length())
}

/// `v.clone()` / `v.to_vec()` for a Vec — a SHALLOW copy of the array.
function clone_vec<T>(v: T[]) -> T[] {
    v.slice(0, v.length())
}

/// `v.last()`.
function last<T>(v: T[]) -> T? {
    v.at(v.length() - 1)
}

/// `v.first()`.
function first<T>(v: T[]) -> T? {
    v.at(0)
}

/// `v.sort()` for strings (in place, by code point = Rust byte order).
function sort_strings(v: string[]) -> void {
    let _ = v.sort_by((a: string, b: string) -> baml.ops.Ordering {
        a.cmp(b)
    });
}

/// `v.sort()` for ints (in place).
function sort_ints(v: int[]) -> void {
    let _ = v.sort_by((a: int, b: int) -> baml.ops.Ordering {
        a.cmp(b)
    });
}

/// `v.iter().rev()` materialized.
function reversed<T>(v: T[]) -> T[] {
    v.reverse()
}

/// `(start..end).collect::<Vec<_>>()`.
function range(start: int, end: int) -> int[] {
    let out: int[] = [];
    let i = start;
    while (i < end) {
        out.push(i);
        i += 1;
    }
    out
}

/// `m.keys()` sorted — iteration order of a `BTreeMap` / `BTreeSet`.
function sorted_keys<V>(m: map<string, V>) -> string[] {
    let ks = m.keys();
    sort_strings(ks);
    ks
}

/// `m.retain(|k, v| pred(k, v))`.
function map_retain<V>(m: map<string, V>, pred: (string, V) -> bool) -> void {
    for (let k in m.keys()) {
        let v = m[k];
        if (!pred(k, v)) {
            let _ = m.delete(k);
        }
    }
}

/// A shallow copy of a map (`m.clone()` when values are immutable/shared).
function clone_map<V>(m: map<string, V>) -> map<string, V> {
    let out: map<string, V> = {};
    for (let k in m.keys()) {
        let _ = out.set(k, m[k]);
    }
    out
}

/// `set.insert(k)` for a `HashSet<String>` modelled as `map<string, bool>`:
/// returns whether `k` was newly inserted.
function set_insert(set: map<string, bool>, k: string) -> bool {
    if (set.has(k)) {
        return false;
    }
    let _ = set.set(k, true);
    true
}

/// A `HashSet<String>` from a list.
function set_of(items: string[]) -> map<string, bool> {
    let out: map<string, bool> = {};
    for (let k in items) {
        let _ = out.set(k, true);
    }
    out
}

/// `v.contains(&x)` — STRUCTURAL equality (`==`). BAML's `includes` compares
/// class/array elements by identity, so it is only right for primitives.
function contains<T>(v: T[], x: T) -> bool {
    for (let e in v) {
        if (e == x) {
            return true;
        }
    }
    false
}

/// `v.iter().position(|e| *e == x)` — structural equality.
function position<T>(v: T[], x: T) -> int? {
    let i = 0;
    while (i < v.length()) {
        if (v[i] == x) {
            return i;
        }
        i += 1;
    }
    null
}
