// Port of src/doc/NodeCreator.ts
//
// The constructor overloads `new NodeCreator(doc, options?, replacer?)` and
// `new NodeCreator(schema, options?)` become `NodeCreator.new(doc, …)` and
// `NodeCreator.fromSchema(schema, …)`. The `#private` fields are plain
// fields with a leading underscore.

function defaultTagPrefix() -> string {
  "tag:yaml.org,2002:"
}

/// `{ anchor: string | null; node: Node | null }`
class SourceRef {
  anchor: string?
  node: Node?
}

class NodeCreator {
  keepUndefined: bool
  replacer: Replacer?
  schema: Schema

  _anchorPrefix: string
  _aliasObjects: unknown[]
  _doc: Document?
  _flow: bool
  _onTagObj: ((Tag) -> void throws unknown)?
  _prevAnchors: JsSet?
  /// `Map<unknown, { anchor, node }>` keyed by object identity. BAML maps and
  /// arrays have no identity, so this is an association list searched with
  /// `js_identical`.
  _sourceKeys: unknown[]
  _sourceRefs: SourceRef[]

  function new(doc: Document, options0: CreateNodeOptions?, replacer: Replacer?) -> NodeCreator {
    let options = options0 ?? Options {};
    NodeCreator {
      keepUndefined: options.keepUndefined ?? false,
      replacer: replacer,
      schema: doc.schema,
      _anchorPrefix: if (options.anchorPrefix != null && options.anchorPrefix != "") { options.anchorPrefix ?? "a" } else { "a" },
      _aliasObjects: [],
      _doc: if (options.aliasDuplicateObjects ?? true) { doc } else { null },
      _flow: options.flow ?? false,
      _onTagObj: options.onTagObj,
      _sourceKeys: [],
      _sourceRefs: [],
    }
  }

  function fromSchema(schema: Schema, options0: CreateNodeOptions?) -> NodeCreator {
    let options = options0 ?? Options {};
    NodeCreator {
      keepUndefined: options.keepUndefined ?? false,
      replacer: null,
      schema: schema,
      _anchorPrefix: if (options.anchorPrefix != null && options.anchorPrefix != "") { options.anchorPrefix ?? "a" } else { "a" },
      _aliasObjects: [],
      _doc: null,
      _flow: options.flow ?? false,
      _onTagObj: options.onTagObj,
      _sourceKeys: [],
      _sourceRefs: [],
    }
  }

  function _getRef(self, value: unknown) -> SourceRef? {
    let i = 0;
    while (i < self._sourceKeys.length()) {
      if (js_identical(self._sourceKeys[i], value)) {
        return self._sourceRefs[i];
      }
      i += 1;
    }
    null
  }

  function create(self, value0: unknown, tagName0: string?) -> Node {
    let value = match (value0) {
      let d: Document => d.value,
      _ => value0,
    };
    // JS `undefined` (the `js_undefined()` sentinel) behaves as `null` from
    // here on: `nullTag.identify` is `value == null`.
    if (is_js_undefined(value)) {
      value = null;
    }
    let vn = as_node(value);
    if (vn != null) {
      return vn;
    }
    match (value) {
      let p: Pair => {
        let map_ = self.schema.mapTag().createNode;
        if (map_ != null) {
          let m = map_(self, null);
          match (m) {
            let mm: YAMLMap => {
              return mm.set(p, null);
            },
            _ => {
              return m;
            },
          }
        }
      },
      _ => {},
    }

    // Detect duplicate references to the same object & use Alias nodes for
    // all after first. The `ref` wrapper allows for circular references to
    // resolve.
    let ref_: SourceRef? = null;
    let doc = self._doc;
    if (doc != null && js_truthy(value) && js_typeof(value) == "object") {
      let existing = self._getRef(value);
      if (existing != null) {
        if (existing.anchor == null) {
          self._aliasObjects.push(value);
          let prev = self._prevAnchors ?? anchorNames(doc);
          self._prevAnchors = prev;
          let a = findNewAnchor(self._anchorPrefix, prev);
          existing.anchor = a;
          prev.add(a);
        }
        return Alias.new(existing.anchor ?? "");
      } else {
        let r = SourceRef {};
        self._sourceKeys.push(value);
        self._sourceRefs.push(r);
        ref_ = r;
      }
    }

    let tagObj: Tag? = null;
    let tagName = tagName0;
    if (tagName != null && tagName != "") {
      let tn: string = tagName;
      if (tn.starts_with("!!")) {
        tn = defaultTagPrefix() + str_from(tn, 2);
        tagName = tn;
      }
      let matched = self.schema.tags.filter((t: Tag) -> bool { t.tag == tn });
      tagObj = matched.find((t: Tag) -> bool { t.format == null }) ?? matched.at(0);
      if (tagObj == null) {
        throw js_error("Tag " + tn + " not found");
      }
    } else {
      for (let t in self.schema.tags) {
        let identify = t.identify;
        if (identify != null && t.format == null) {
          if (identify(value)) {
            tagObj = t;
            break;
          }
        }
      }
    }
    if (tagObj == null) {
      // `value.toJSON()`: only JS Date has one among the values modelled here
      match (value) {
        let d: JsDate => {
          value = d.toISOString();
        },
        _ => {},
      }
      if (!js_truthy(value) || js_typeof(value) != "object" || js_is_raw_json(value)) {
        let node = Scalar.new(value);
        if (ref_ != null) {
          ref_.node = node;
        }
        return node;
      }
      tagObj = match (value) {
        JsMap<unknown> => self.schema.mapTag(),
        _ => if (js_iterable(value) != null) { self.schema.seqTag() } else { self.schema.mapTag() },
      };
    }
    let to: Tag = tagObj ?? self.schema.mapTag();
    let onTagObj = self._onTagObj;
    if (onTagObj != null) {
      onTagObj(to);
      self._onTagObj = null;
    }

    let cn = to.createNode;
    let node: Node = if (cn != null) { cn(self, value) } else { Scalar.new(value) };
    if (tagName != null && tagName != "") {
      nb(node).tag = tagName;
    } else if (!tag_default_truthy(to)) {
      nb(node).tag = to.tag;
    }

    if (ref_ != null) {
      ref_.node = node;
    }
    if (self._flow) {
      match (node) {
        let m: YAMLMap => {
          m.flow = true;
        },
        let s: YAMLSeq => {
          s.flow = true;
        },
        let s: YAMLSet => {
          s.flow = true;
        },
        _ => {},
      }
    }
    node
  }

  function createPair(self, key: unknown, value: unknown) -> Pair {
    let k = self.create(key, null);
    let v = if (value == null || is_js_undefined(value)) { null } else { self.create(value, null) };
    Pair.new(k, v)
  }

  function setAnchors(self) -> null {
    for (let source in self._aliasObjects) {
      let ref_ = self._getRef(source);
      let done = false;
      if (ref_ != null) {
        let a = ref_.anchor;
        let n = ref_.node;
        if (a != null && a != "" && n != null) {
          match (n) {
            Alias => {},
            _ => {
              nb(n).anchor = a;
              done = true;
            },
          }
        }
      }
      if (!done) {
        let msg = "Failed to resolve repeated object (this should not happen)";
        throw JsError { name: "Error", message: msg, extra: source };
      }
    }
    null
  }
}
