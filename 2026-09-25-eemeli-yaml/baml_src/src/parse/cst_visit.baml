// Port of src/parse/cst-visit.ts
//
// JS `Symbol` control values (BREAK / SKIP / REMOVE) are modelled as unique
// strings; the visitor result is `int | string | CstVisitor | null`.

/// One step of a `VisitPath`: `['key' | 'value', number]`
class CstPathItem {
  field: string
  index: int
}

type CstVisitResult = int | string | CstVisitor | null
type CstVisitor = (CollectionItem, CstPathItem[]) -> CstVisitResult throws unknown

/// Terminate visit traversal completely
function cst_visit_BREAK() -> string {
  "\0Symbol(break visit)"
}

/// Do not visit the children of the current item
function cst_visit_SKIP() -> string {
  "\0Symbol(skip children)"
}

/// Remove the current item
function cst_visit_REMOVE() -> string {
  "\0Symbol(remove item)"
}

function cst_is_symbol(ctrl: CstVisitResult) -> bool {
  match (ctrl) {
    let s: string => true,
    _ => false,
  }
}

/// Apply a visitor to a CST document or item.
///
/// Walks through the tree (depth-first) starting from the root, calling a
/// `visitor` function with two arguments when entering each item:
///   - `item`: The current item, which included the following members:
///     - `start: SourceToken[]` – Source tokens before the key or value,
///       possibly including its anchor or tag.
///     - `key?: Token | null` – Set for pair values. May then be `null`, if
///       the key before the `:` separator is empty.
///     - `sep?: SourceToken[]` – Source tokens between the key and the value,
///       which should include the `:` map value indicator if `value` is set.
///     - `value?: Token` – The value of a sequence item, or of a map pair.
///   - `path`: The steps from the root to the current node, as an array of
///     `['key' | 'value', number]` tuples.
///
/// The return value of the visitor may be used to control the traversal:
///   - `undefined` (default): Do nothing and continue
///   - `visit.SKIP`: Do not visit the children of this token, continue with
///      next sibling
///   - `visit.BREAK`: Terminate traversal completely
///   - `visit.REMOVE`: Remove the current item, then continue with the next one
///   - `number`: Set the index of the next step. This is useful especially if
///     the index of the current token has changed.
///   - `function`: Define the next visitor for this item. After the original
///     visitor is called on item entry, next visitors are called after
///     handling a non-empty `key` and when exiting the item.
function cst_visit(cst: Token | CollectionItem, visitor: CstVisitor) -> null {
  let item = match (cst) {
    let t: Token => {
      if (t.type == "document") {
        let ci = collection_item(tstart(t));
        ci.value = t.value;
        ci
      } else {
        // Not reachable for well-typed input: only documents and items are visited.
        collection_item([])
      }
    },
    let i: CollectionItem => i,
  };
  cst_visit_(cst_path_new(), item, visitor);
  null
}

function cst_path_new() -> CstPathItem[] {
  let p: CstPathItem[] = [];
  p
}

/// Find the item at `path` from `cst` as the root
function cst_visit_itemAtPath(cst: Token | CollectionItem, path: CstPathItem[]) -> CollectionItem? {
  let item: CollectionItem? = match (cst) {
    let t: Token => {
      let ci = collection_item(tstart(t));
      ci.value = t.value;
      ci
    },
    let i: CollectionItem => i,
  };
  for (let step in path) {
    if (item == null) {
      return null;
    }
    let tok = if (step.field == "key") { item.key } else { item.value };
    if (tok == null) {
      return null;
    }
    if (tok.items == null) {
      return null;
    }
    item = titems(tok).at(step.index);
  }
  item
}

/// Get the immediate parent collection of the item at `path` from `cst` as
/// the root.
///
/// Throws an error if the collection is not found, which should never
/// happen if the item itself exists.
function cst_visit_parentCollection(cst: Token | CollectionItem, path: CstPathItem[]) -> Token {
  let parent = cst_visit_itemAtPath(cst, path.slice(0, path.length() - 1));
  let field = path[path.length() - 1].field;
  let coll = if (parent == null) { null } else if (field == "key") { parent.key } else { parent.value };
  if (coll != null) {
    if (coll.items != null) {
      return coll;
    }
  }
  throw js_error("Parent collection not found")
}

function cst_visit_(path: CstPathItem[], item: CollectionItem, visitor: CstVisitor) -> CstVisitResult {
  let ctrl = visitor(item, path);
  if (cst_is_symbol(ctrl)) {
    return ctrl;
  }
  for (let field in ["key", "value"]) {
    let token = if (field == "key") { item.key } else { item.value };
    if (token?.items != null) {
      let items = token?.items ?? [];
      let i = 0;
      while (i < items.length()) {
        let np = path.slice(0, path.length());
        np.push(CstPathItem { field: field, index: i });
        let ci = cst_visit_(np, items[i], visitor);
        match (ci) {
          let n: int => {
            i = n - 1;
          },
          let s: string => {
            if (s == cst_visit_BREAK()) {
              return cst_visit_BREAK();
            } else if (s == cst_visit_REMOVE()) {
              items.remove_at(i);
              i -= 1;
            }
          },
          _ => {},
        }
        i += 1;
      }
      if (field == "key") {
        match (ctrl) {
          let f: CstVisitor => {
            ctrl = f(item, path);
          },
          _ => {},
        }
      }
    }
  }
  match (ctrl) {
    let f: CstVisitor => f(item, path),
    _ => ctrl,
  }
}
