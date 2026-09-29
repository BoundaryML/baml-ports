// `std::path::{Path, PathBuf}` with Unix semantics. A path is a `string`.

/// The normalized components of `p`, as Rust's `Path::components()` yields
/// them: repeated `/` collapse, interior `.` are dropped (a leading `.` is
/// kept), a trailing `/` is ignored, and a leading `/` is the component "/".
function path_components(p: string) -> string[] {
    let out: string[] = [];
    if (p == "") {
        return out;
    }
    if (p.starts_with("/")) {
        out.push("/");
    }
    let parts = p.split("/");
    let i = 0;
    for (let part in parts) {
        if (part == "") {
            i += 1;
            continue;
        }
        if (part == ".") {
            // Only a leading `.` (a relative path's first component) survives.
            if (i == 0 && !p.starts_with("/")) {
                out.push(".");
            }
            i += 1;
            continue;
        }
        out.push(part);
        i += 1;
    }
    out
}

/// Rebuild a path from components.
function path_from_components(comps: string[]) -> string {
    if (comps.length() == 0) {
        return "";
    }
    if (comps[0] == "/") {
        return "/" + comps.slice(1, comps.length()).join("/");
    }
    comps.join("/")
}

/// `p.is_absolute()`.
function path_is_absolute(p: string) -> bool {
    p.starts_with("/")
}

/// `p.is_relative()`.
function path_is_relative(p: string) -> bool {
    !p.starts_with("/")
}

/// `p.has_root()`.
function path_has_root(p: string) -> bool {
    p.starts_with("/")
}

/// `base.join(p)`.
function path_join(base: string, p: string) -> string {
    if (p.starts_with("/")) {
        return p;
    }
    if (base == "") {
        return p;
    }
    if (base.ends_with("/")) {
        base + p
    } else {
        base + "/" + p
    }
}

/// `p.parent()`: the path without its last component. `None` for "" and "/".
function path_parent(p: string) -> string? {
    let comps = path_components(p);
    if (comps.length() == 0) {
        return null;
    }
    let last = comps[comps.length() - 1];
    if (last == "/") {
        return null;
    }
    path_from_components(comps.slice(0, comps.length() - 1))
}

/// `p.file_name()`: the last component, unless it is `/`, `.` or `..`.
function path_file_name(p: string) -> string? {
    let comps = path_components(p);
    if (comps.length() == 0) {
        return null;
    }
    let last = comps[comps.length() - 1];
    if (last == "/" || last == ".." || last == ".") {
        return null;
    }
    last
}

/// `p.extension()`.
function path_extension(p: string) -> string? {
    let name = path_file_name(p);
    if (name == null) {
        return null;
    }
    let i = name.last_index_of(".");
    if (i == null || i == 0) {
        return null;
    }
    name.slice(i + 1, name.length())
}

/// `p.file_stem()`.
function path_file_stem(p: string) -> string? {
    let name = path_file_name(p);
    if (name == null) {
        return null;
    }
    let i = name.last_index_of(".");
    if (i == null || i == 0) {
        return name;
    }
    name.slice(0, i)
}

/// The raw prefix of `p` before its file name (trailing `/`s ignored), and
/// the file name itself, as Rust's `set_file_name`/`set_extension` see them.
function path_split_name(p: string) -> Tuple2<string, string>? {
    if (path_file_name(p) == null) {
        return null;
    }
    let t = p;
    while (t.length() > 1 && t.ends_with("/")) {
        t = t.slice(0, t.length() - 1);
    }
    let i = t.last_index_of("/");
    if (i == null) {
        return Tuple2 { _0: "", _1: t };
    }
    Tuple2 { _0: t.slice(0, i + 1), _1: t.slice(i + 1, t.length()) }
}

/// `p.with_extension(ext)` (an empty `ext` removes the extension).
function path_with_extension(p: string, ext: string) -> string {
    let split = path_split_name(p);
    if (split == null) {
        return p;
    }
    let stem = path_file_stem(split._1) ?? split._1;
    if (ext == "") {
        split._0 + stem
    } else {
        split._0 + stem + "." + ext
    }
}

/// `p.with_file_name(name)`.
function path_with_file_name(p: string, name: string) -> string {
    let split = path_split_name(p);
    if (split == null) {
        return path_join(p, name);
    }
    split._0 + name
}

/// `p.starts_with(base)` — component-wise.
function path_starts_with(p: string, base: string) -> bool {
    let a = path_components(p);
    let b = path_components(base);
    if (b.length() > a.length()) {
        return false;
    }
    let i = 0;
    while (i < b.length()) {
        if (a[i] != b[i]) {
            return false;
        }
        i += 1;
    }
    true
}

/// `p.strip_prefix(base)` — component-wise; `None` if `base` is not a prefix.
function path_strip_prefix(p: string, base: string) -> string? {
    if (!path_starts_with(p, base)) {
        return null;
    }
    let a = path_components(p);
    let b = path_components(base);
    path_from_components(a.slice(b.length(), a.length()))
}

/// `p.ends_with(child)` — component-wise.
function path_ends_with(p: string, child: string) -> bool {
    let a = path_components(p);
    let b = path_components(child);
    if (b.length() > a.length()) {
        return false;
    }
    let off = a.length() - b.length();
    let i = 0;
    while (i < b.length()) {
        if (a[off + i] != b[i]) {
            return false;
        }
        i += 1;
    }
    true
}

/// `Path == Path` — component-wise equality.
function path_eq(a: string, b: string) -> bool {
    path_components(a) == path_components(b)
}
