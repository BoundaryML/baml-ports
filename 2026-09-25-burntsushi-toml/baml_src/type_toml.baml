// Port of type_toml.go.

// tomlType represents any Go type that corresponds to a TOML type.
// While the first draft of the TOML spec has a simplistic type system that
// probably doesn't need this level of sophistication, we seem to be militating
// toward adding real composite types.
//
// Go models this as an interface with a single `typeString()` method that is
// only ever implemented by `tomlBaseType` (a named string). BAML enums cannot
// carry methods, so the port uses a small class wrapping the type name; the
// "interface" and its only implementation collapse into this one class. A Go
// `nil` tomlType is a BAML `null`.
class TomlType {
    name: string,

    function type_string(self) -> string {
        self.name
    }

    implements baml.ToString {
        function to_string(self) -> string throws never {
            self.type_string()
        }
    }
}

// typeEqual accepts any two types and returns true if they are equal.
function type_equal(t1: TomlType?, t2: TomlType?) -> bool {
    if (t1 == null || t2 == null) {
        return false;
    }
    t1.type_string() == t2.type_string()
}

function type_is_table(t: TomlType?) -> bool {
    type_equal(t, toml_hash()) || type_equal(t, toml_array_hash())
}

// Go declares these as package-level variables of type tomlBaseType. BAML has
// no package-level variables, so each is a zero-argument function.
function toml_integer() -> TomlType {
    TomlType { name: "Integer" }
}

function toml_float() -> TomlType {
    TomlType { name: "Float" }
}

function toml_datetime() -> TomlType {
    TomlType { name: "Datetime" }
}

function toml_string() -> TomlType {
    TomlType { name: "String" }
}

function toml_bool() -> TomlType {
    TomlType { name: "Bool" }
}

function toml_array() -> TomlType {
    TomlType { name: "Array" }
}

function toml_hash() -> TomlType {
    TomlType { name: "Hash" }
}

function toml_array_hash() -> TomlType {
    TomlType { name: "ArrayHash" }
}

// typeOfPrimitive returns a tomlType of any primitive value in TOML.
// Primitive values are: Integer, Float, Datetime, String and Bool.
//
// Passing a lexer item other than the following will cause a BUG message
// to occur: itemString, itemBool, itemInteger, itemFloat, itemDatetime.
//
// (A method on *parser in Go; it only uses the parser to report bugs.)
function type_of_primitive(lex_item: Item) -> TomlType {
    match (lex_item.typ) {
        ItemType.Integer => toml_integer(),
        ItemType.Float => toml_float(),
        ItemType.Datetime => toml_datetime(),
        ItemType.String | ItemType.StringEsc => toml_string(),
        ItemType.MultilineString => toml_string(),
        ItemType.RawString => toml_string(),
        ItemType.RawMultilineString => toml_string(),
        ItemType.Bool => toml_bool(),
        _ => bug(`Cannot infer primitive type of lex item '${lex_item.to_string()}'.`),
    }
}
