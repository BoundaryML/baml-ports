// Port of deprecated.go.

// TextMarshaler is an alias for encoding.TextMarshaler.
//
// Deprecated: use encoding.TextMarshaler
//
// (Go declares `type TextMarshaler encoding.TextMarshaler`; in the port the
// interface itself is declared in encode.baml as `TextMarshaler`, and
// TextUnmarshaler in decode.baml, so these aliases are the interfaces.)

// DecodeReader is an alias for NewDecoder(r).Decode(v).
//
// Deprecated: use NewDecoder(reader).Decode(&value).
function decode_reader<T>(r: baml.io.Read, v: T?) -> Decoded<T> throws TomlError {
    new_decoder(r).decode<T>(v)
}

// PrimitiveDecode is an alias for MetaData.PrimitiveDecode().
//
// Deprecated: use MetaData.PrimitiveDecode.
//
// (Named primitive_decode_deprecated: primitive_decode is already the
// MetaData method's free-function form, see decode.baml.)
function primitive_decode_deprecated<T>(prim_value: Primitive, v: T?) -> T throws TomlError {
    let md = MetaData { context: new_key([]), key_info: {}, mapping: {}, keys_list: [], decoded: {}, data: [] };
    md_unify_into<T>(md, prim_value.undecoded(), v)
}
