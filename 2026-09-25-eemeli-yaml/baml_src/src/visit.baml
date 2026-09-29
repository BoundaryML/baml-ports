// Port of src/visit.ts
//
// JS `Symbol` control values (BREAK / SKIP / REMOVE) are unique strings.
// `visitAsync` accepts visitor functions that may return a
// `baml.future.Future` (the BAML counterpart of a Promise), which is awaited.

/// `number | 'key' | 'value' | null`
type VisitKey = int | string | null

type VisitPathItem = Document | Node | Pair

/// `void | symbol | number | Node | Pair`
type VisitResult = int | string | Node | Pair | null

/// `visitorFn<Node | Pair | null>`
type VisitorFn = (VisitKey, Node | Pair | null, VisitPathItem[]) -> VisitResult throws unknown

/// The object form of a visitor, with type-specific visitor functions.
class VisitorFns {
  Alias: ((VisitKey, Alias, VisitPathItem[]) -> VisitResult throws unknown)?
  Collection: ((VisitKey, YAMLMap | YAMLSeq | YAMLSet, VisitPathItem[]) -> VisitResult throws unknown)?
  Map: ((VisitKey, YAMLMap | YAMLSet, VisitPathItem[]) -> VisitResult throws unknown)?
  Node: ((VisitKey, Node, VisitPathItem[]) -> VisitResult throws unknown)?
  Pair: ((VisitKey, Pair, VisitPathItem[]) -> VisitResult throws unknown)?
  Scalar: ((VisitKey, Scalar, VisitPathItem[]) -> VisitResult throws unknown)?
  Seq: ((VisitKey, YAMLSeq, VisitPathItem[]) -> VisitResult throws unknown)?
  Value: ((VisitKey, Scalar | YAMLMap | YAMLSeq | YAMLSet, VisitPathItem[]) -> VisitResult throws unknown)?
}

type Visitor = VisitorFn | VisitorFns

/// Identity helper so object visitors can be written inline.
function visitor_fns(v: VisitorFns) -> VisitorFns {
  v
}

/// Terminate visit traversal completely
function visit_BREAK() -> string {
  "\0Symbol(break visit)"
}

/// Do not visit the children of the current node
function visit_SKIP() -> string {
  "\0Symbol(skip children)"
}

/// Remove the current node
function visit_REMOVE() -> string {
  "\0Symbol(remove node)"
}

/// Apply a visitor to an AST node or document.
///
/// Walks through the tree (depth-first) starting from `node`, calling a
/// `visitor` function with three arguments:
///   - `key`: For sequence values and map `Pair`, the node's index in the
///     collection. Within a `Pair`, `'key'` or `'value'`, correspondingly.
///     `null` for the root node.
///   - `node`: The current node.
///   - `path`: The ancestry of the current node.
///
/// The return value of the visitor may be used to control the traversal:
///   - `undefined` (default): Do nothing and continue
///   - `visit.SKIP`: Do not visit the children of this node, continue with
///     next sibling
///   - `visit.BREAK`: Terminate traversal completely
///   - `visit.REMOVE`: Remove the current node, then continue with the next one
///   - `Node`: Replace the current node, then continue by visiting it
///   - `number`: While iterating the items of a sequence or map, set the index
///     of the next step. This is useful especially if the index of the current
///     node has changed.
///
/// If `visitor` is a single function, it will be called with all values
/// encountered in the tree, including e.g. `null` values. Alternatively,
/// separate visitor functions may be defined for each `Map`, `Pair`, `Seq`,
/// `Alias` and `Scalar` node. To define the same visitor function for more
/// than one node type, use the `Collection` (map and seq), `Value` (map, seq
/// & scalar) and `Node` (alias, map, seq & scalar) targets. Of all these,
/// only the most specific defined one will be used for each node.
function visit(node: Document | Node | null, visitor: Visitor) -> null {
  let visitor_ = initVisitor(visitor);
  match (node) {
    let doc: Document => {
      let cd = visit_(null, doc.value, visitor_, [doc]);
      if (cd == visit_REMOVE()) {
        doc.value = Scalar.new(null);
      }
    },
    let n: Node => {
      visit_(null, n, visitor_, []);
    },
    null => {
      visit_(null, null, visitor_, []);
    },
  }
  null
}

function is_visit_symbol(ctrl: VisitResult) -> bool {
  match (ctrl) {
    let s: string => true,
    _ => false,
  }
}

function path_plus(path: VisitPathItem[], item: VisitPathItem) -> VisitPathItem[] {
  let p = path.slice(0, path.length());
  p.push(item);
  p
}

function visit_(key: VisitKey, node: Node | Pair | null, visitor: Visitor, path0: VisitPathItem[]) -> VisitResult throws unknown {
  let ctrl = callVisitor(key, node, visitor, path0);
  let path = path0;

  match (ctrl) {
    let p: Pair => {
      replaceNode(key, path, p);
      return visit_(key, p, visitor, path);
    },
    let n: Node => {
      replaceNode(key, path, n);
      return visit_(key, n, visitor, path);
    },
    _ => {},
  }

  if (!is_visit_symbol(ctrl)) {
    match (node) {
      let seq: YAMLSeq => {
        path = path_plus(path, seq);
        let i = 0;
        while (i < seq.items.length()) {
          let ci = visit_(i, seq.items[i], visitor, path);
          match (ci) {
            let n: int => {
              i = n - 1;
            },
            let s: string => {
              if (s == visit_BREAK()) {
                return visit_BREAK();
              } else if (s == visit_REMOVE()) {
                seq.items.remove_at(i);
                i -= 1;
              }
            },
            _ => {},
          }
          i += 1;
        }
      },
      let m: YAMLMap => {
        path = path_plus(path, m);
        let keys = m.values.keys();
        let vals = m.values.values();
        let delKeys: unknown[] = [];
        let i = 0;
        while (i < vals.length()) {
          let ci = visit_(i, vals[i], visitor, path);
          match (ci) {
            let n: int => {
              i = n - 1;
            },
            let s: string => {
              if (s == visit_BREAK()) {
                return visit_BREAK();
              } else if (s == visit_REMOVE()) {
                delKeys.push(keys[i]);
              }
            },
            _ => {},
          }
          i += 1;
        }
        for (let dk in delKeys) {
          m.values.delete(dk);
        }
      },
      let st: YAMLSet => {
        path = path_plus(path, st);
        let keys = st.values.keys();
        let vals = st.values.values();
        let delKeys: unknown[] = [];
        let i = 0;
        while (i < vals.length()) {
          let ci = visit_(i, vals[i], visitor, path);
          match (ci) {
            let n: int => {
              i = n - 1;
            },
            let s: string => {
              if (s == visit_BREAK()) {
                return visit_BREAK();
              } else if (s == visit_REMOVE()) {
                delKeys.push(keys[i]);
              }
            },
            _ => {},
          }
          i += 1;
        }
        for (let dk in delKeys) {
          st.values.delete(dk);
        }
      },
      let pair: Pair => {
        path = path_plus(path, pair);
        let ck = visit_("key", pair.key, visitor, path);
        if (ck == visit_BREAK()) {
          return visit_BREAK();
        } else if (ck == visit_REMOVE()) {
          pair.key = Scalar.new(null);
        }
        let cv = visit_("value", pair.value, visitor, path);
        if (cv == visit_BREAK()) {
          return visit_BREAK();
        } else if (cv == visit_REMOVE()) {
          pair.value = null;
        }
      },
      _ => {},
    }
  }

  ctrl
}

/// `visitAsync(node, visitor)`: as `visit`, but visitor functions may return
/// a `Future` which is awaited before continuing.
type AsyncVisitResult = VisitResult | baml.future.Future<VisitResult, unknown>
type AsyncVisitorFn = (VisitKey, Node | Pair | null, VisitPathItem[]) -> AsyncVisitResult throws unknown

/// The object form of an async visitor (`asyncVisitor` upstream): as
/// `VisitorFns`, but each function may return a `Future`.
class AsyncVisitorFns {
  Alias: ((VisitKey, Alias, VisitPathItem[]) -> AsyncVisitResult throws unknown)?
  Collection: ((VisitKey, YAMLMap | YAMLSeq | YAMLSet, VisitPathItem[]) -> AsyncVisitResult throws unknown)?
  Map: ((VisitKey, YAMLMap | YAMLSet, VisitPathItem[]) -> AsyncVisitResult throws unknown)?
  Node: ((VisitKey, Node, VisitPathItem[]) -> AsyncVisitResult throws unknown)?
  Pair: ((VisitKey, Pair, VisitPathItem[]) -> AsyncVisitResult throws unknown)?
  Scalar: ((VisitKey, Scalar, VisitPathItem[]) -> AsyncVisitResult throws unknown)?
  Seq: ((VisitKey, YAMLSeq, VisitPathItem[]) -> AsyncVisitResult throws unknown)?
  Value: ((VisitKey, Scalar | YAMLMap | YAMLSeq | YAMLSet, VisitPathItem[]) -> AsyncVisitResult throws unknown)?
}

type AsyncVisitor = AsyncVisitorFn | AsyncVisitorFns

function visitAsync(node: Document | Node | null, visitor: AsyncVisitor) -> null throws unknown {
  let fn_: AsyncVisitorFn = match (visitor) {
    let v: AsyncVisitorFns => {
      let iv = initAsyncVisitor(v);
      (key: VisitKey, n: Node | Pair | null, path: VisitPathItem[]) -> AsyncVisitResult throws unknown {
        callAsyncVisitor(key, n, iv, path)
      }
    },
    let f: AsyncVisitorFn => f,
  };
  let sync = (key: VisitKey, n: Node | Pair | null, path: VisitPathItem[]) -> VisitResult throws unknown {
    let r = fn_(key, n, path);
    match (r) {
      let f: baml.future.Future<VisitResult, unknown> => await f,
      let v: VisitResult => v,
    }
  };
  visit(node, sync);
  null
}

function initAsyncVisitor(v: AsyncVisitorFns) -> AsyncVisitorFns {
  if (v.Collection != null || v.Node != null || v.Value != null) {
    let nodeFn = v.Node;
    AsyncVisitorFns {
      Alias: v.Alias ?? nodeFn,
      Map: v.Map ?? v.Collection ?? v.Value ?? nodeFn,
      Scalar: v.Scalar ?? v.Value ?? nodeFn,
      Seq: v.Seq ?? v.Collection ?? v.Value ?? nodeFn,
      Pair: v.Pair,
      Collection: v.Collection,
      Node: v.Node,
      Value: v.Value,
    }
  } else {
    v
  }
}

function callAsyncVisitor(key: VisitKey, node: Node | Pair | null, v: AsyncVisitorFns, path: VisitPathItem[]) -> AsyncVisitResult throws unknown {
  match (node) {
    let m: YAMLMap => {
      let f = v.Map;
      if (f != null) { f(key, m, path) } else { null }
    },
    let s: YAMLSet => {
      let f = v.Map;
      if (f != null) { f(key, s, path) } else { null }
    },
    let s: YAMLSeq => {
      let f = v.Seq;
      if (f != null) { f(key, s, path) } else { null }
    },
    let p: Pair => {
      let f = v.Pair;
      if (f != null) { f(key, p, path) } else { null }
    },
    let s: Scalar => {
      let f = v.Scalar;
      if (f != null) { f(key, s, path) } else { null }
    },
    let a: Alias => {
      let f = v.Alias;
      if (f != null) { f(key, a, path) } else { null }
    },
    null => null,
  }
}

function initVisitor(visitor: Visitor) -> Visitor {
  match (visitor) {
    let v: VisitorFns => {
      if (v.Collection != null || v.Node != null || v.Value != null) {
        let nodeFn = v.Node;
        let res = VisitorFns {
          Alias: v.Alias ?? nodeFn,
          Map: v.Map ?? v.Collection ?? v.Value ?? nodeFn,
          Scalar: v.Scalar ?? v.Value ?? nodeFn,
          Seq: v.Seq ?? v.Collection ?? v.Value ?? nodeFn,
          Pair: v.Pair,
          Collection: v.Collection,
          Node: v.Node,
          Value: v.Value,
        };
        res
      } else {
        v
      }
    },
    _ => visitor,
  }
}

function callVisitor(key: VisitKey, node: Node | Pair | null, visitor: Visitor, path: VisitPathItem[]) -> VisitResult throws unknown {
  match (visitor) {
    let v: VisitorFns => match (node) {
      let m: YAMLMap => {
        let f = v.Map;
        if (f != null) { f(key, m, path) } else { null }
      },
      let s: YAMLSet => {
        let f = v.Map;
        if (f != null) { f(key, s, path) } else { null }
      },
      let s: YAMLSeq => {
        let f = v.Seq;
        if (f != null) { f(key, s, path) } else { null }
      },
      let p: Pair => {
        let f = v.Pair;
        if (f != null) { f(key, p, path) } else { null }
      },
      let s: Scalar => {
        let f = v.Scalar;
        if (f != null) { f(key, s, path) } else { null }
      },
      let a: Alias => {
        let f = v.Alias;
        if (f != null) { f(key, a, path) } else { null }
      },
      null => null,
    },
    let f: VisitorFn => f(key, node, path),
  }
}

function replaceNode(key: VisitKey, path: VisitPathItem[], node: Node | Pair) -> null throws unknown {
  // JS: `path[path.length - 1]` is undefined for an empty path.
  let parent: VisitPathItem? = if (path.length() > 0) { path[path.length() - 1] } else { null };
  match (parent) {
    let seq: YAMLSeq => {
      let idx = match (key) {
        let i: int => i,
        _ => 0,
      };
      seq.items[idx] = node;
    },
    let m: YAMLMap => {
      match (node) {
        let p: Pair => {
          let idx = match (key) {
            let i: int => i,
            _ => 0,
          };
          let keys = m.values.keys();
          let vals = m.values.values();
          keys[idx] = m.keyOf(p, true);
          vals[idx] = p;
          let nm: JsMap<Pair> = js_map_new();
          let j = 0;
          while (j < keys.length()) {
            nm.set(keys[j], vals[j]);
            j += 1;
          }
          m.values = nm;
        },
        _ => {
          throw js_error("Cannot replace map pair with non-pair value");
        },
      }
    },
    let st: YAMLSet => {
      match (node) {
        let n: Node => {
          let idx = match (key) {
            let i: int => i,
            _ => 0,
          };
          let keys = st.values.keys();
          let vals = st.values.values();
          keys[idx] = st.keyOf(n, true);
          vals[idx] = n;
          let nm: JsMap<Node> = js_map_new();
          let j = 0;
          while (j < keys.length()) {
            nm.set(keys[j], vals[j]);
            j += 1;
          }
          st.values = nm;
        },
        _ => {
          throw js_error("Cannot replace set value with non-node value");
        },
      }
    },
    let pair: Pair => {
      match (node) {
        let n: Node => {
          if (key == "key") {
            pair.key = n;
          } else {
            pair.value = n;
          }
        },
        _ => {
          throw js_error("Cannot replace pair " + js_string(key) + " with non-node value");
        },
      }
    },
    let doc: Document => {
      match (node) {
        let n: Alias => {
          throw js_error("Cannot replace Document value with non-node value");
        },
        let n: Node => {
          doc.value = n;
        },
        _ => {
          throw js_error("Cannot replace Document value with non-node value");
        },
      }
    },
    let a: Alias => {
      throw js_error("Cannot replace node with alias parent");
    },
    _ => {
      throw js_error("Cannot replace node with scalar parent");
    },
  }
  null
}
