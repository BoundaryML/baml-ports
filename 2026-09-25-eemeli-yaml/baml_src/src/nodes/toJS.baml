// Port of src/nodes/toJS.ts

class AnchorData {
  node: Node
  aliasCount: int
  count: int
  res: unknown?
}

/// A context used in `node.toJS()` implementations
class ToJSContext {
  /// `Map<Node, { aliasCount, count, res }>`
  anchors: JsMap<AnchorData>
  /// Cached anchor and alias nodes in the order they occur in the document
  aliasResolveCache: Node[]?
  mapAsMap: bool
  mapKeyWarned: bool
  maxAliasCount: int
  /// `WeakMap<holder, Map<key, source>>`. BAML maps/arrays have no identity,
  /// so this is an association list searched with `js_identical`.
  reviverSources: ReviverSources?

  function new(opt: ToJSOptions?) -> ToJSContext {
    ToJSContext {
      anchors: js_map_new(),
      mapAsMap: opt?.mapAsMap == true,
      mapKeyWarned: false,
      maxAliasCount: opt?.maxAliasCount ?? 100,
      reviverSources: if (opt?.reviver != null) { ReviverSources { holders: [], sources: [] } } else { null },
    }
  }

  function setAnchor(self, node: Node, res: unknown) -> null {
    let anchor = self.anchors.get(node);
    if (anchor != null) {
      anchor.res = res;
    } else {
      self.anchors.set(node, AnchorData { node: node, aliasCount: 0, count: 1, res: res });
    }
    null
  }

  function resolveAlias(self, doc: Document, source: Node) -> unknown {
    let data = self.anchors.get(source);
    if (data == null) {
      source.toJS(doc, self);
      data = self.anchors.get(source);
    }
    if (data == null) {
      let msg = "This should not happen: Alias anchor was not resolved?";
      throw js_reference_error(msg);
    }
    let d: AnchorData = data;
    // `data?.res === undefined`: undefined is not representable separately
    // from null here, so this check is skipped.
    if (self.maxAliasCount >= 0) {
      d.count += 1;
      if (d.aliasCount == 0) {
        d.aliasCount = self.getAliasCount(doc, source);
      }
      if (d.count * d.aliasCount > self.maxAliasCount) {
        let msg = "Excessive alias count indicates a resource exhaustion attack";
        throw js_reference_error(msg);
      }
    }
    d.res
  }

  /// `#getAliasCount(doc, node: Node | Pair | null)`
  function getAliasCount(self, doc: Document, node: unknown) -> int {
    match (node) {
      let a: Alias => {
        let source = a.resolve(doc, self);
        let anchor = if (source == null) { null } else { self.anchors.get(source) };
        if (anchor != null) { anchor.count * anchor.aliasCount } else { 0 }
      },
      let p: Pair => {
        let kc = self.getAliasCount(doc, p.key);
        let vc = self.getAliasCount(doc, p.value);
        if (kc > vc) { kc } else { vc }
      },
      // `Array.isArray(node)`: YAMLSeq extends Array in the original
      let s: YAMLSeq => {
        let count = 0;
        for (let item in s.items) {
          let c = self.getAliasCount(doc, item);
          if (c > count) {
            count = c;
          }
        }
        count
      },
      _ => 1,
    }
  }

  /// Only effective if `source` is a `string` or a `Scalar`,
  /// and a reviver function is being used.
  function setSource(self, holder: unknown, key: unknown, source: unknown) -> null {
    let rs = self.reviverSources;
    if (rs == null) {
      return null;
    }
    let src_ = match (source) {
      let s: Scalar => s.source,
      let s: string => s,
      _ => null,
    };
    if (src_ != null) {
      rs.getOrCreate(holder).set(key, src_);
    }
    null
  }
}

/// `WeakMap<object, Map<unknown, string>>` emulation (see ToJSContext).
class ReviverSources {
  holders: unknown[]
  sources: JsMap<string>[]

  function get(self, holder: unknown) -> JsMap<string>? {
    let i = 0;
    while (i < self.holders.length()) {
      if (js_identical(self.holders[i], holder)) {
        return self.sources[i];
      }
      i += 1;
    }
    null
  }

  function getOrCreate(self, holder: unknown) -> JsMap<string> {
    let m = self.get(holder);
    if (m != null) {
      return m;
    }
    let nm: JsMap<string> = js_map_new();
    self.holders.push(holder);
    self.sources.push(nm);
    nm
  }
}

/// A general-purpose JSON reviver function
function toJSON(key: unknown, value: unknown) -> unknown {
  match (value) {
    let b: bigint => {
      let s = b.to_string();
      baml.Float.parse(s) catch (e) { _ => 0.0 }
    },
    _ => value,
  }
}
