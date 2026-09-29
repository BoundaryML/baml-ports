// Port of src/schema/types.ts
//
// `ScalarTag` and `CollectionTag` share `TagBase`; here they are one `Tag`
// class. `collection` is set for collection tags. Their differently-typed
// `resolve` functions are split into `resolve` (scalar) and
// `resolveCollection` (collection). `test` is a reserved word in BAML and so
// is renamed `testFn`. `nodeClass` (a JS class) is the class name as a
// string: "YAMLMap" | "YAMLSeq" | "YAMLSet" | "YAMLOMap".

type TagOnError = (string) -> void throws unknown

class Tag {
  _id: int
  /// The identifier for your data type, with which its stringified form will
  /// be prefixed. Should either be a !-prefixed local `!tag`, or a fully
  /// qualified `tag:domain,date:foo`.
  tag: string
  /// The source collection type supported by this tag ('map' | 'seq').
  collection: string?
  /// If `true`, allows for values to be stringified without an explicit tag
  /// together with `test`. If `'key'`, this only applies if the value is used
  /// as a mapping key.
  default: (bool | "key")?
  /// If a tag has multiple forms that should be parsed and/or stringified
  /// differently, use `format` to identify them.
  format: string?
  /// Used by `YAML.createNode` to detect your data type, e.g. using `typeof`
  /// or `instanceof`.
  identify: ((unknown) -> bool throws unknown)?
  /// Together with `default` allows for values to be stringified without an
  /// explicit tag and detected using a regular expression or a test function.
  testFn: ((string) -> bool throws unknown)?
  /// ScalarTag: Turns a value into an AST node. If returning a non-`Node`
  /// value, the output will be wrapped as a `Scalar`.
  resolve: ((string, TagOnError, Options) -> unknown throws unknown)?
  /// CollectionTag: Turns a value into an AST node. If returning a non-`Node`
  /// value, the output will be wrapped as a `Scalar`.
  resolveCollection: ((Node, TagOnError, Options) -> unknown throws unknown)?
  /// Optional function stringifying a Scalar node.
  stringify: ((Scalar, StringifyContext, Callback?, Callback?) -> string throws unknown)?
  /// An optional factory function, used e.g. by collections when wrapping JS
  /// objects as AST nodes.
  createNode: ((NodeCreator, unknown) -> Node throws unknown)?
  /// The class that implements this tag.
  /// If set, used to select this tag when stringifying.
  nodeClass: string?
}

/// Whether `default` is `true` (not `'key'`).
function tag_default_true(t: Tag) -> bool {
  match (t.default) {
    let b: bool => b,
    _ => false,
  }
}

/// JS truthiness of `tag.default` (`true` or `'key'`).
function tag_default_truthy(t: Tag) -> bool {
  match (t.default) {
    let b: bool => b,
    "key" => true,
    _ => false,
  }
}

/// Whether `node instanceof tag.nodeClass`.
function node_is_instance_of(node: unknown, nodeClass: string) -> bool {
  match (node) {
    let m: YAMLMap => nodeClass == "YAMLMap",
    let s: YAMLSet => nodeClass == "YAMLSet",
    let q: YAMLSeq => nodeClass == "YAMLSeq" || (nodeClass == "YAMLOMap" && q._class == "YAMLOMap"),
    _ => false,
  }
}
