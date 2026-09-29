// Port of src/nodes/YAMLMap.ts
//
// `KeyArg<K, V>` (a key, a key node, a scalar value, or a Pair) is `unknown`.
// JS optional positional parameters do not exist in BAML (a defaulted
// parameter must be passed by name), so `set(key, value, options?)` is split
// into `set(key, value)` and `setWithOptions(key, value, options)`; a Pair is
// set with `set(pair, null)`.

class YAMLMap {
  _id: int
  schema: Schema
  values: JsMap<Pair>
  /// An optional anchor on this map. Used by alias nodes.
  anchor: string?
  /// If true, stringify this and all child nodes using flow rather than block styles.
  flow: bool?
  /// A comment on or immediately after this map.
  comment: string?
  /// A comment before this map.
  commentBefore: string?
  /// The `[start, value-end, node-end]` character offsets for
  /// the part of the source parsed into this map (undefined if not parsed).
  range: int[]?
  /// A blank line before this map and its commentBefore
  spaceBefore: bool?
  /// The CST token that was composed into this map.
  srcToken: Token?
  /// A fully qualified tag, if required
  tag: string?

  function tagName() -> string {
    "tag:yaml.org,2002:map"
  }

  /// `new YAMLMap(schema, elements?)`
  function new(schema: Schema, elements: Pair[]?) -> YAMLMap {
    let map_ = YAMLMap { _id: new_id(), schema: schema, values: js_map_new() };
    if (elements != null) {
      for (let pair in elements) {
        map_.values.set(schema.mapKey(pair), pair);
      }
    }
    map_
  }

  /// A generic collection factory method that can be used
  /// by other node classes that inherit from YAMLMap
  function create(nc: NodeCreator, obj: unknown) -> YAMLMap {
    let replacer = nc.replacer;
    let map_ = YAMLMap.new(nc.schema, null);
    let entries = js_entries(obj);
    if (entries != null) {
      let i = 0;
      while (i < entries.keys.length()) {
        let key = entries.keys[i];
        let value = entries.values[i];
        let skip = false;
        if (replacer != null) {
          match (replacer) {
            let f: ReplacerFn => {
              value = f(key, value, obj);
            },
            let arr: unknown[] => {
              if (!arr.some((r: unknown) -> bool { js_same(r, key) })) {
                skip = true;
              }
            },
          }
        }
        // `value !== undefined || nc.keepUndefined` (JS `undefined` is the
        // `js_undefined()` sentinel)
        if (!skip && (!is_js_undefined(value) || nc.keepUndefined)) {
          let mk = nc.schema.mapKey(key);
          let pair = nc.createPair(key, value);
          map_.values.set(mk, pair);
        }
        i += 1;
      }
    }
    map_
  }

  /// Create a copy of this map.
  ///
  /// @param schema - If defined, overwrites the original's schema
  function clone(self, schema: Schema?) -> YAMLMap {
    let s = schema ?? self.schema;
    let copy = YAMLMap { ...self, _id: new_id(), schema: s, values: js_map_new() };
    let keys = self.values.keys();
    let vals = self.values.values();
    let i = 0;
    while (i < keys.length()) {
      copy.values.set(keys[i], vals[i].clone(s));
      i += 1;
    }
    let r = self.range;
    if (r != null) {
      copy.range = r.slice(0, r.length());
    }
    copy
  }

  /// Remove a value from the mapping.
  /// @returns `true` if the item was found and removed.
  function delete(self, key: unknown) -> bool {
    let mk = self.schema.mapKey(key);
    if (self.values.delete(mk)) {
      return true;
    }
    let mk2 = key_node_of(key);
    if (mk2 != null) {
      let keys = self.values.keys();
      let vals = self.values.values();
      let i = 0;
      while (i < keys.length()) {
        if (js_same(vals[i].key, mk2)) {
          return self.values.delete(keys[i]);
        }
        i += 1;
      }
    }
    false
  }

  /// Return value at `key`, or `undefined` if not found.
  function get(self, key: unknown) -> Node? {
    self.getPair(key)?.value
  }

  /// Return pair at `key`, or `undefined` if not found.
  function getPair(self, key: unknown) -> Pair? {
    let mk = self.schema.mapKey(key);
    let pair = self.values.get(mk);
    if (pair != null) {
      return pair;
    }
    let mk2 = key_node_of(key);
    if (mk2 != null) {
      for (let p in self.values.values()) {
        if (js_same(p.key, mk2)) {
          return p;
        }
      }
    }
    null
  }

  /// Check if the mapping includes a value with the key `key`.
  function has(self, key: unknown) -> bool {
    let mk = self.schema.mapKey(key);
    if (self.values.has(mk)) {
      return true;
    }
    let mk2 = key_node_of(key);
    if (mk2 != null) {
      for (let p in self.values.values()) {
        if (js_same(p.key, mk2)) {
          return true;
        }
      }
    }
    false
  }

  /// Return the internal Map key matching `key`, or `undefined` if not found.
  ///
  /// @param allowMissing - If `true`, a key is always returned,
  ///                       even if the key is not in the map.
  function keyOf(self, key: unknown, allowMissing: bool) -> unknown {
    let mk = self.schema.mapKey(key);
    if (allowMissing || self.values.has(mk)) {
      return mk;
    }
    let mk2 = key_node_of(key);
    if (mk2 != null) {
      let keys = self.values.keys();
      let vals = self.values.values();
      let i = 0;
      while (i < keys.length()) {
        if (js_same(vals[i].key, mk2)) {
          return keys[i];
        }
        i += 1;
      }
    }
    null
  }

  function pairs(self) -> Pair[] {
    self.values.values()
  }

  /// `set(key, value)` / `set(pair)`
  function set(self, keyOrPair: unknown, value: unknown) -> YAMLMap {
    self.setWithOptions(keyOrPair, value, null)
  }

  function setWithOptions(self, keyOrPair: unknown, value: unknown, options: Options?) -> YAMLMap {
    let mk = self.schema.mapKey(keyOrPair);

    let pair = match (keyOrPair) {
      let p: Pair => p,
      _ => {
        let kn = as_node(keyOrPair);
        let vn = as_node(value);
        if (kn != null && (value == null || vn != null)) {
          Pair.new(kn, vn)
        } else {
          let nc = NodeCreator.fromSchema(self.schema, options);
          nc.createPair(keyOrPair, value)
        }
      },
    };

    match (pair.value) {
      let sv: Scalar => {
        let prev = self.values.get(mk);
        if (prev != null) {
          let pv = prev.value;
          if (pv == null) {
            prev.value = sv;
            return self;
          }
          match (pv) {
            let ps: Scalar => {
              // For scalars, keep the old node & its comments and anchors
              scalar_assign(ps, sv);
              return self;
            },
            _ => {},
          }
        }
      },
      _ => {},
    }
    self.values.set(mk, pair);
    self
  }

  function _stringifyBlockMap(self, ctx: StringifyContext, pairs: Pair[], onComment: Callback?, onChompKeep: Callback?) -> string {
    let indent = ctx.indent;
    let commentString = ctx.options.commentString;

    let chompKeep = false; // flag for the preceding node's status
    let lines: string[] = [];
    for (let pair in pairs) {
      let comment: string? = null;
      if (!chompKeep && (pair.key.spaceBefore ?? false)) {
        lines.push("");
      }

      let cb = pair.key.commentBefore;
      if (cb != null && chompKeep) {
        cb = cb.replace(re("^\\n+"), "");
      }
      if (cb != null && cb != "") {
        let ic = indentComment(commentString(cb), indent).trim_start();
        lines.push(ic);
      }

      chompKeep = false;
      let str = stringifyPair(
        pair,
        ctx,
        () -> void { comment = null; },
        () -> void { chompKeep = true; },
      );
      let c = comment;
      if (c != null && c != "") {
        str += lineComment(str, indent, commentString(c));
      }
      if (chompKeep && c != null && c != "") {
        chompKeep = false;
      }
      lines.push(str);
    }

    let str = "";
    if (lines.length() == 0) {
      str = "{}";
    } else {
      str = lines[0];
      let i = 1;
      while (i < lines.length()) {
        let line = lines[i];
        str += if (line != "") { "\n" + indent + line } else { "\n" };
        i += 1;
      }
    }

    let mc = self.comment;
    if (mc != null && mc != "") {
      str += "\n" + indentComment(commentString(mc), indent);
      if (onComment != null) {
        onComment();
      }
    } else if (chompKeep) {
      if (onChompKeep != null) {
        onChompKeep();
      }
    }

    str
  }

  function _stringifyFlowMap(self, ctx: StringifyContext, pairs: Pair[]) -> string {
    let indent = ctx.indent;
    let indentStep = ctx.indentStep;
    let fcPadding = ctx.flowCollectionPadding;
    let commentString = ctx.options.commentString;
    let lineWidth = ctx.options.lineWidth;
    let trailingComma = ctx.options.trailingComma;
    let itemIndent = indent + indentStep;
    let itemCtx = StringifyContext { ...ctx, indent: itemIndent, inFlow: true };

    let reqNewline = false;
    let linesAtValue = 0;
    let lines: string[] = [];
    let itemsLeft = self.values.size();
    for (let pair in pairs) {
      itemsLeft -= 1;

      let comment: string? = null;
      let ik = pair.key;
      if (ik.spaceBefore ?? false) {
        lines.push("");
        reqNewline = true;
      }
      let ikcb = ik.commentBefore;
      if (ikcb != null && ikcb != "") {
        let ic = indentComment(commentString(ikcb), indent);
        lines.push(ic.trim_start()); // Avoid double indent on first line
        reqNewline = true;
      }
      if (ik.comment != null && ik.comment != "") {
        reqNewline = true;
      }

      let iv = pair.value;
      if (iv != null) {
        if (iv.comment != null && iv.comment != "") {
          comment = iv.comment;
        }
        if (iv.commentBefore != null && iv.commentBefore != "") {
          reqNewline = true;
        }
      } else if (ik.comment != null && ik.comment != "") {
        comment = ik.comment;
      }

      if (comment != null) {
        reqNewline = true;
      }
      let str = stringifyPair(pair, itemCtx, () -> void { comment = null; }, null);
      reqNewline = reqNewline || lines.length() > linesAtValue || str.includes("\n");
      if (itemsLeft > 0) {
        str += ",";
      } else if (trailingComma) {
        if (!reqNewline && lineWidth > 0) {
          let len = lines.reduce((sum: int, line: string) -> int { sum + line.length() + 2 }, 2) + (str.length() + 2);
          reqNewline = len > lineWidth;
        }
        if (reqNewline) {
          str += ",";
        }
      }
      let c = comment;
      if (c != null) {
        str += lineComment(str, itemIndent, commentString(c));
      }
      lines.push(str);
      linesAtValue = lines.length();
    }

    if (lines.length() == 0) {
      return "{}";
    }
    if (!reqNewline) {
      let len = lines.reduce((sum: int, line: string) -> int { sum + line.length() + 2 }, 2);
      reqNewline = ctx.options.lineWidth > 0 && len > ctx.options.lineWidth;
    }
    if (reqNewline) {
      let str = "{";
      for (let line in lines) {
        str += if (line != "") { "\n" + indentStep + indent + line } else { "\n" };
      }
      return str + "\n" + indent + "}";
    }
    "{" + fcPadding + lines.join(" ") + fcPadding + "}"
  }

  implements NodeBase {
    function cloneNode(self, schema: Schema?) -> Node {
      self.clone(schema)
    }

    /// A plain JavaScript representation of this node.
    function toJS(self, doc: Document?, ctx: ToJSContext?) -> unknown {
      let ctx_ = ctx ?? ToJSContext.new(null);
      let map_: MapLike = if (ctx_.mapAsMap) { js_map() } else { js_object() };
      if (self.anchor != null && self.anchor != "") {
        ctx_.setAnchor(self, map_);
      }
      for (let pair in self.values.values()) {
        addPairToJSMap(doc, ctx_, map_, pair);
      }
      map_
    }

    function toString(self, ctx: StringifyContext?, onComment: Callback?, onChompKeep: Callback?) -> string {
      if (ctx == null) {
        return json_stringify(self);
      }
      let pairs = self.values.values();
      let sme = ctx.sortMapEntries;
      if (sme != null) {
        pairs = js_sort(pairs, sme);
      }
      let flow = ctx.inFlow ?? (self.flow ?? false);
      if (flow) {
        self._stringifyFlowMap(ctx, pairs)
      } else {
        self._stringifyBlockMap(ctx, pairs, onComment, onChompKeep)
      }
    }
  }

  implements CollectionBase {
    function size(self) -> int {
      self.values.size()
    }
  }
}

/// `key instanceof Pair ? key.key : isNode(key) ? key : null`
function key_node_of(key: unknown) -> Node? {
  match (key) {
    let p: Pair => p.key,
    _ => as_node(key),
  }
}

/// `Object.assign(prev, next)` for two Scalar nodes: copy every property
/// that is set on `next` (identity `_id` is kept).
function scalar_assign(prev: Scalar, next: Scalar) -> null {
  prev.value = next.value;
  prev._class = next._class;
  if (next.anchor != null) { prev.anchor = next.anchor; }
  if (next.comment != null) { prev.comment = next.comment; }
  if (next.commentBefore != null) { prev.commentBefore = next.commentBefore; }
  if (next.format != null) { prev.format = next.format; }
  if (next.minFractionDigits != null) { prev.minFractionDigits = next.minFractionDigits; }
  if (next.range != null) { prev.range = next.range; }
  if (next.spaceBefore != null) { prev.spaceBefore = next.spaceBefore; }
  if (next.srcToken != null) { prev.srcToken = next.srcToken; }
  if (next.source != null) { prev.source = next.source; }
  if (next.tag != null) { prev.tag = next.tag; }
  if (next.type != null) { prev.type = next.type; }
  if (next.addToJSMap != null) { prev.addToJSMap = next.addToJSMap; }
  null
}

class JsEntries {
  keys: unknown[]
  values: unknown[]
}

/// `obj instanceof Map ? obj : Object.entries(obj)` for map-like objects.
function js_entries(obj: unknown) -> JsEntries? {
  match (obj) {
    null => null,
    let m: JsMap<unknown> => JsEntries { keys: m.keys(), values: m.values() },
    _ => {
      let o = js_as_object(obj);
      if (o != null) {
        let keys: unknown[] = [];
        let values: unknown[] = [];
        for (let k in o.keys()) {
          keys.push(k);
          values.push(o[k]);
        }
        return JsEntries { keys: keys, values: values };
      }
      let arr = js_as_array(obj);
      if (arr != null) {
        // Object.entries of an array: index keys
        let keys: unknown[] = [];
        let i = 0;
        while (i < arr.length()) {
          keys.push(i.to_string());
          i += 1;
        }
        return JsEntries { keys: keys, values: arr };
      }
      null
    },
  }
}
