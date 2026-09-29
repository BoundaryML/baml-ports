// Port of src/nodes/identity.ts

/// Type predicate for collections
function isCollection(node: unknown) -> bool {
  match (node) {
    YAMLMap => true,
    YAMLSeq => true,
    YAMLSet => true,
    _ => false,
  }
}

/// Type predicate for `Node` values
function isNode(node: unknown) -> bool {
  match (node) {
    Scalar => true,
    Alias => true,
    YAMLMap => true,
    YAMLSeq => true,
    YAMLSet => true,
    _ => false,
  }
}

/// `node as Node` after an `isNode()` check.
function as_node(value: unknown) -> Node? {
  match (value) {
    let n: Scalar => n,
    let n: Alias => n,
    let n: YAMLMap => n,
    let n: YAMLSeq => n,
    let n: YAMLSet => n,
    _ => null,
  }
}

/// `node as Collection` after an `isCollection()` check.
function as_collection(value: unknown) -> Collection? {
  match (value) {
    let n: YAMLMap => n,
    let n: YAMLSeq => n,
    let n: YAMLSet => n,
    _ => null,
  }
}
