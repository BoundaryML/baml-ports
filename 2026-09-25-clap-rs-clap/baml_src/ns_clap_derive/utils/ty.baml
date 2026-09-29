// Port of clap_derive/src/utils/ty.rs
//
// Rust classifies the field's *syntactic* type (`Option<Vec<T>>`, ...). BAML
// uses the reflected type: `T?` is a union with `null`, `T[]` an array.

enum Ty {
    Unit,
    Vec,
    VecVec,
    Option,
    OptionOption,
    OptionVec,
    OptionVecVec,
    Other,
}

function ty_as_str(t: Ty) -> string {
    match (t) {
        Ty.Unit => "()",
        Ty.Vec => "Vec<T>",
        Ty.Option => "Option<T>",
        Ty.OptionOption => "Option<Option<T>>",
        Ty.OptionVec => "Option<Vec<T>>",
        Ty.VecVec => "Vec<Vec<T>>",
        Ty.OptionVecVec => "Option<Vec<Vec<T>>>",
        Ty.Other => "...other...",
    }
}

/// If `t` is `T?`, return `T`
function option_inner(t: reflect.Type) -> reflect.Type? {
    if let u: reflect.union.Type = t.as_union() {
        let members = u.member_types();
        let non_null = members.filter((m) -> { !is_null_type(m) });
        if (non_null.length() < members.length()) {
            if (non_null.length() == 1) {
                return non_null[0];
            }
            return reflect.union.new(non_null).as_type() catch_all (e) { _ => null };
        }
    }
    null
}

function is_null_type(t: reflect.Type) -> bool {
    t.to_string() == "null"
}

/// If `t` is `T[]`, return `T`
function vec_inner(t: reflect.Type) -> reflect.Type? {
    if let a: reflect.array.Type = t.as_array() { a.element_type() } else { null }
}

/// `Ty::from_syn_ty`
function ty_from_type(t: reflect.Type) -> Ty {
    if let inner: reflect.Type = option_inner(t) {
        if (option_inner(inner) != null) {
            return Ty.OptionOption;
        }
        if let v: reflect.Type = vec_inner(inner) {
            if (vec_inner(v) != null) { return Ty.OptionVecVec; }
            return Ty.OptionVec;
        }
        return Ty.Option;
    }
    if let v: reflect.Type = vec_inner(t) {
        if (vec_inner(v) != null) { return Ty.VecVec; }
        return Ty.Vec;
    }
    if (is_null_type(t)) {
        return Ty.Unit;
    }
    Ty.Other
}

/// `inner_type`: the value type (`T` in `Option<T>`, `Vec<T>`, `Option<Vec<T>>`, ...)
function inner_type(t: reflect.Type) -> reflect.Type {
    let ty = ty_from_type(t);
    match (ty) {
        Ty.Vec | Ty.Option => option_inner(t) ?? vec_inner(t) ?? t,
        Ty.OptionOption => option_inner(option_inner(t) ?? t) ?? t,
        Ty.OptionVec => vec_inner(option_inner(t) ?? t) ?? t,
        Ty.VecVec => vec_inner(vec_inner(t) ?? t) ?? t,
        Ty.OptionVecVec => vec_inner(vec_inner(option_inner(t) ?? t) ?? t) ?? t,
        _ => t,
    }
}

/// `sub_type`: the `T` in `Option<T>`
function sub_type(t: reflect.Type) -> reflect.Type? {
    option_inner(t)
}

/// `is_simple_ty(ty, "bool")`
function is_simple_ty(t: reflect.Type, name: string) -> bool {
    t.to_string() == name
}
