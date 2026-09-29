// Port of src/nodes/YAMLSet.ts

class YAMLSet {
  _id: int
  schema: Schema
  tag: string?
  values: JsMap<Node>
  /// An optional anchor on this collection. Used by alias nodes.
  anchor: string?
  /// If true, stringify this and all child nodes using flow rather than
  /// block styles.
  flow: bool?
  /// A comment on or immediately after this collection.
  comment: string?
  /// A comment before this collection.
  commentBefore: string?
  /// The `[start, value-end, node-end]` character offsets for
  /// the part of the source parsed into this collection (undefined if not parsed).
  range: int[]?
  /// A blank line before this collection and its commentBefore
  spaceBefore: bool?
  /// The CST token that was composed into this collection.
  srcToken: Token?

  function tagName() -> string {
    "tag:yaml.org,2002:set"
  }

  /// `new YAMLSet(schema)`
  function new(schema: Schema) -> YAMLSet {
    YAMLSet {
      _id: new_id(),
      schema: schema,
      tag: "tag:yaml.org,2002:set",
      values: js_map_new(),
    }
  }

  /// Adds a value to the set.
  ///
  /// If `value` is not a Node, it will be converted to one.
  /// If the set already includes an equivalent value, it is not added.
  function add(self, value: unknown) -> YAMLSet {
    self.addWithOptions(value, null)
  }

  function addWithOptions(self, value: unknown, options: Options?) -> YAMLSet {
    if (self.has(value)) {
      return self;
    }

    let mk = self.schema.mapKey(value);
    let n = as_node(value);
    let node = if (n != null) { n } else { NodeCreator.fromSchema(self.schema, options).create(value, null) };
    self.values.set(mk, node);
    self
  }

  /// Create a copy of this set.
  ///
  /// @param schema - If defined, overwrites the original's schema
  function clone(self, schema: Schema?) -> YAMLSet {
    let s = schema ?? self.schema;
    let copy = YAMLSet { ...self, _id: new_id(), schema: s, values: js_map_new() };
    let keys = self.values.keys();
    let vals = self.values.values();
    let i = 0;
    while (i < keys.length()) {
      copy.values.set(keys[i], vals[i].cloneNode(s));
      i += 1;
    }
    let r = self.range;
    if (r != null) {
      copy.range = r.slice(0, r.length());
    }
    copy
  }

  /// Removes a value from the set.
  /// @returns `true` if the item was found and removed.
  function delete(self, value: unknown) -> bool {
    let mk = self.schema.mapKey(value);
    if (self.values.delete(mk)) {
      return true;
    }
    if (isNode(value)) {
      let keys = self.values.keys();
      let vals = self.values.values();
      let i = 0;
      while (i < keys.length()) {
        if (js_same(vals[i], value)) {
          return self.values.delete(keys[i]);
        }
        i += 1;
      }
    }
    false
  }

  /// Returns the node of `value` from the set, or `undefined` if not found.
  function get(self, value: unknown) -> Node? {
    let mk = self.schema.mapKey(value);
    let node = self.values.get(mk);
    if (node != null) {
      return node;
    }
    if (isNode(value)) {
      for (let v in self.values.values()) {
        if (js_same(v, value)) {
          return v;
        }
      }
    }
    null
  }

  /// Checks if the set includes a value
  function has(self, value: unknown) -> bool {
    let mk = self.schema.mapKey(value);
    if (self.values.has(mk)) {
      return true;
    }
    if (isNode(value)) {
      for (let v in self.values.values()) {
        if (js_same(v, value)) {
          return true;
        }
      }
    }
    false
  }

  /// Return the internal Map key matching `value`, or `undefined` if not found.
  ///
  /// @param allowMissing - If `true`, a key is always returned,
  ///                       even if the key is not in the set.
  function keyOf(self, value: unknown, allowMissing: bool) -> unknown {
    let mk = self.schema.mapKey(value);
    if (allowMissing || self.values.has(mk)) {
      return mk;
    }
    if (isNode(value)) {
      let keys = self.values.keys();
      let vals = self.values.values();
      let i = 0;
      while (i < keys.length()) {
        if (js_same(vals[i], value)) {
          return keys[i];
        }
        i += 1;
      }
    }
    null
  }

  function _stringifyBlockSet(self, ctx: StringifyContext, items: Node[], onComment: Callback?, onChompKeep: Callback?) -> string {
    let indent = ctx.indent;
    let indentStep = ctx.indentStep;
    let commentString = ctx.options.commentString;
    let itemCtx = StringifyContext { ...ctx, implicitKey: false, indent: indent + indentStep };

    let chompKeep = false; // flag for the preceding node's status
    let res: string? = null;
    for (let item in items) {
      if (!chompKeep && (item.spaceBefore ?? false)) {
        res = if (res != null) { res + "\n" } else { "" };
      }
      let cb = item.commentBefore;
      if (cb != null && cb != "" && chompKeep) {
        cb = cb.replace(re("^\\n+"), "");
      }
      if (cb != null && cb != "") {
        let ic = indentComment(commentString(cb), indent).trim_start();
        res = if (res != null) { res + "\n" + indent + ic } else { ic };
      }

      chompKeep = false;
      let comment = item.comment;
      let str = stringifyNode(
        item,
        itemCtx,
        () -> void { comment = null; },
        () -> void { chompKeep = true; },
      );
      str = if (str != "") { "? " + str } else { "?" };
      let c = comment;
      if (c != null && c != "") {
        str += lineComment(str, itemCtx.indent, commentString(c));
        chompKeep = false;
      }
      res = if (res != null) { res + "\n" + indent + str } else { str };
    }

    let sc = self.comment;
    if (sc != null && sc != "") {
      let cs = commentString(sc);
      res = if (res != null) { res + "\n" + indentComment(cs, indent) } else { "{}" + lineComment("", indent, cs) };
      if (onComment != null) {
        onComment();
      }
    } else if (chompKeep) {
      if (onChompKeep != null) {
        onChompKeep();
      }
    }

    res ?? "{}"
  }

  function _stringifyFlowSet(self, ctx: StringifyContext, items: Node[]) -> string {
    let indent = ctx.indent;
    let indentStep = ctx.indentStep;
    let fcPadding = ctx.flowCollectionPadding;
    let commentString = ctx.options.commentString;
    let lineWidth = ctx.options.lineWidth;
    let trailingComma = ctx.options.trailingComma;
    let itemCtx = StringifyContext { ...ctx, indent: indent + indentStep + indentStep, inFlow: true };

    let reqNewline = false;
    let lines: string[] = [];
    let itemsLeft = self.values.size();
    let singleLineWidth = 2 * fcPadding.length(); // '{}' + ' ' + ' ' - ', '
    for (let item in items) {
      itemsLeft -= 1;

      if (item.spaceBefore ?? false) {
        lines.push("");
        reqNewline = true;
      }
      let icb = item.commentBefore;
      if (icb != null && icb != "") {
        let ic = indentComment(commentString(icb), indent);
        lines.push(ic.trim_start()); // Avoid double indent on first line
        reqNewline = true;
      }
      let comment = item.comment;
      if (comment != null && comment != "") {
        reqNewline = true;
      }

      itemCtx.implicitKey = !isCollection(item);
      let str = stringifyNode(item, itemCtx, () -> void { comment = null; }, null);
      if (str == "") {
        str = "?";
      }
      if (isCollection(item)) {
        str = "? " + str;
      }

      reqNewline = reqNewline || str.includes("\n");
      if (!reqNewline && lineWidth > 0) {
        singleLineWidth += str.length() + 2; // str + ', '
        if (singleLineWidth > lineWidth) {
          reqNewline = true;
        }
      }

      if (itemsLeft > 0 || (trailingComma && reqNewline)) {
        str += ",";
      }
      let c = comment;
      if (c != null && c != "") {
        str += lineComment(str, indent + indentStep, commentString(c));
      }
      lines.push(str);
    }

    if (lines.length() == 0) {
      return "{}";
    }
    if (!reqNewline) {
      return "{" + fcPadding + lines.join(" ") + fcPadding + "}";
    }
    let str = "{";
    for (let line in lines) {
      str += if (line != "") { "\n" + indentStep + indent + line } else { "\n" };
    }
    str + "\n" + indent + "}"
  }

  implements NodeBase {
    function cloneNode(self, schema: Schema?) -> Node {
      self.clone(schema)
    }

    function toJS(self, doc: Document?, ctx: ToJSContext?) -> unknown {
      let ctx_ = ctx ?? ToJSContext.new(null);
      let set = js_set();
      if (self.anchor != null && self.anchor != "") {
        ctx_.setAnchor(self, set);
      }
      for (let item in self.values.values()) {
        let value = item.toJS(doc, ctx_);
        set.add(value);
        ctx_.setSource(set, value, item);
      }
      set
    }

    function toString(self, ctx: StringifyContext?, onComment: Callback?, onChompKeep: Callback?) -> string {
      if (ctx == null) {
        return json_stringify(self);
      }
      let items = self.values.values();
      let sme = ctx.sortMapEntries;
      if (sme != null) {
        let pairs = items.map((item: Node) -> Pair { Pair.new(item, null) });
        items = js_sort(pairs, sme).map((pair: Pair) -> Node { pair.key });
      }
      let flow = ctx.inFlow ?? (self.flow ?? false);
      if (flow) {
        self._stringifyFlowSet(ctx, items)
      } else {
        self._stringifyBlockSet(ctx, items, onComment, onChompKeep)
      }
    }
  }

  implements CollectionBase {
    function size(self) -> int {
      self.values.size()
    }
  }
}
