// Port of src/nodes/YAMLSeq.ts
//
// In the original `YAMLSeq extends Array`; here the elements live in
// `items`, and the Array methods the class overrides (`push`, `set`,
// `splice`, `unshift`, `fill`, `at`, `length`) are provided explicitly.
//
// `class YAMLOMap extends YAMLSeq<Pair>` (schema/yaml-1.1/omap.ts) is a
// YAMLSeq with `_class == "YAMLOMap"`; its overrides are dispatched on that
// field.

type SeqItem = Node | Pair

class YAMLSeq {
  _id: int
  /// "YAMLSeq" or "YAMLOMap"
  _class: string
  schema: Schema
  items: SeqItem[]
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
  /// A fully qualified tag, if required
  tag: string?

  function tagName() -> string {
    "tag:yaml.org,2002:seq"
  }

  /// `new YAMLSeq(schema, elements = [])`
  function new(schema: Schema, elements: unknown[]?) -> YAMLSeq {
    let seq = YAMLSeq { _id: new_id(), _class: "YAMLSeq", schema: schema, items: [] };
    if (elements != null) {
      seq.items = nodeValues(schema, elements);
    }
    seq
  }

  /// A generic collection factory method that can be extended
  /// to other node classes that inherit from YAMLSeq
  function create(nc: NodeCreator, obj: unknown) -> YAMLSeq {
    let seq = YAMLSeq.new(nc.schema, null);
    let iter = js_iterable(obj);
    if (iter != null) {
      let i = 0;
      for (let it0 in iter) {
        let it = it0;
        let r = nc.replacer;
        match (r) {
          let f: ReplacerFn => {
            let key: unknown = match (obj) {
              JsSet => it,
              _ => i.to_string(),
            };
            i += 1;
            it = f(key, it, obj);
          },
          _ => {},
        }
        seq.items.push(nc.create(it, null));
      }
    }
    seq
  }

  function length(self) -> int {
    self.items.length()
  }

  function at(self, idx: int) -> SeqItem? {
    self.items.at(idx)
  }

  /// Create a copy of this collection.
  ///
  /// @param schema - If defined, overwrites the original's schema
  function clone(self, schema: Schema?) -> YAMLSeq {
    let copy = YAMLSeq { ...self, _id: new_id(), items: [] };
    for (let it in self.items) {
      match (it) {
        let p: Pair => {
          copy.items.push(p.clone(schema));
        },
        let n: Node => {
          copy.items.push(n.cloneNode(schema));
        },
      }
    }
    let r = self.range;
    if (r != null) {
      copy.range = r.slice(0, r.length());
    }
    if (schema != null) {
      copy.schema = schema;
    }
    copy
  }

  /// Change all elements within a range of indices in this sequence to a
  /// static value.
  ///
  /// Non-node values are converted to Node values.
  function fill(self, value: unknown, start: int?, end: int?) -> YAMLSeq {
    let nv = nodeValue(self.schema, value, null);
    let len = self.items.length();
    let s = start ?? 0;
    let e = end ?? len;
    if (s < 0) { s += len; }
    if (e < 0) { e += len; }
    let i = if (s < 0) { 0 } else { s };
    while (i < e && i < len) {
      self.items[i] = nv;
      i += 1;
    }
    self
  }

  /// @private
  function _push(self, item: SeqItem) -> null {
    self.items.push(item);
    null
  }

  /// Append new elements to this sequence, and return its new length.
  ///
  /// Non-node values are converted to Node values.
  function push(self, value: unknown) -> int {
    if (self._class == "YAMLOMap") {
      match (value) {
        let p: Pair => {
          self.items.push(p);
        },
        _ => {
          throw js_error("Omap only supports Pair values");
        },
      }
      return self.items.length();
    }
    self.items.push(nodeValue(self.schema, value, null));
    self.items.length()
  }

  /// Set a value in this sequence.
  ///
  /// Non-node values are converted to Node values.
  function set(self, idx: unknown, value: unknown) -> null {
    self.setWithOptions(idx, value, null)
  }

  function setWithOptions(self, idx0: unknown, value: unknown, options: Options?) -> null {
    if (!js_is_integer(idx0)) {
      throw js_type_error("Expected an integer, not " + json_stringify(idx0) + ".");
    }
    let idx = js_int(idx0);
    if (self._class == "YAMLOMap") {
      if (idx < 0) {
        if (idx < 0 - self.items.length()) {
          throw js_range_error("Invalid index " + idx.to_string());
        }
        idx += self.items.length();
      }
      match (value) {
        let p: Pair => {
          self._setIndex(idx, p);
        },
        _ => {},
      }
      return null;
    }
    let prev = self.items.at(idx);
    let done = false;
    match (prev) {
      let ps: Scalar => {
        if (isScalarValue(value)) {
          ps.value = value;
          done = true;
        }
      },
      _ => {},
    }
    if (!done) {
      if (idx < 0) {
        if (idx < 0 - self.items.length()) {
          throw js_range_error("Invalid index " + idx.to_string());
        }
        idx += self.items.length();
      }
      self._setIndex(idx, nodeValue(self.schema, value, options));
    }
    null
  }

  /// `this[idx] = value`, growing the array if needed.
  function _setIndex(self, idx: int, value: SeqItem) -> null {
    if (idx < self.items.length()) {
      self.items[idx] = value;
    } else {
      // JS would create holes; there are no holes in a BAML array, so
      // they are filled with null scalars (which stringify as `null`).
      while (self.items.length() < idx) {
        self.items.push(Scalar.new(null));
      }
      self.items.push(value);
    }
    null
  }

  /// Changes the contents of this sequence by removing or replacing existing
  /// elements and/or adding new elements in place.
  ///
  /// Non-node values are converted to Node values.
  function splice(self, start: int, deleteCount: int?, values: unknown[]) -> SeqItem[] {
    let nv = nodeValues(self.schema, values);
    let len = self.items.length();
    let s = if (start < 0) { if (start + len < 0) { 0 } else { start + len } } else if (start > len) { len } else { start };
    let dc = deleteCount ?? (len - s);
    if (dc < 0) {
      dc = 0;
    }
    if (s + dc > len) {
      dc = len - s;
    }
    let removed = self.items.slice(s, s + dc);
    let next: SeqItem[] = self.items.slice(0, s);
    for (let v in nv) {
      next.push(v);
    }
    for (let v in self.items.slice(s + dc, len)) {
      next.push(v);
    }
    self.items = next;
    removed
  }

  /// Prepend new elements to this sequence, and return its new length.
  ///
  /// Non-node values are converted to Node values.
  function unshift(self, values: unknown[]) -> int {
    let nv = nodeValues(self.schema, values);
    let next: SeqItem[] = nv;
    for (let v in self.items) {
      next.push(v);
    }
    self.items = next;
    self.items.length()
  }

  function _stringifyBlockSeq(self, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string {
    let indent = ctx.indent;
    let commentString = ctx.options.commentString;
    let itemIndent = indent + "  ";
    let itemCtx = StringifyContext { ...ctx, indent: itemIndent };

    let chompKeep = false; // flag for the preceding node's status
    let lines: string[] = [];
    let i = 0;
    while (i < self.items.length()) {
      let item = self.items[i];
      let comment: string? = null;
      match (item) {
        let p: Pair => {
          if (!chompKeep && (p.key.spaceBefore ?? false)) {
            lines.push("");
          }
          addCommentBefore(ctx, lines, p.key.commentBefore, chompKeep);
        },
        let n: Node => {
          if (!chompKeep && (n.spaceBefore ?? false)) {
            lines.push("");
          }
          addCommentBefore(ctx, lines, n.commentBefore, chompKeep);
          if (n.comment != null && n.comment != "") {
            comment = n.comment;
          }
        },
      }

      chompKeep = false;
      let str = stringifyNode(
        item,
        itemCtx,
        () -> void { comment = null; },
        () -> void { chompKeep = true; },
      );
      let c = comment;
      if (c != null) {
        str += lineComment(str, itemIndent, commentString(c));
      }
      if (chompKeep && c != null) {
        chompKeep = false;
      }
      lines.push("- " + str);
      i += 1;
    }

    let str = "";
    if (lines.length() == 0) {
      str = "[]";
    } else {
      str = lines[0];
      let j = 1;
      while (j < lines.length()) {
        let line = lines[j];
        str += if (line != "") { "\n" + indent + line } else { "\n" };
        j += 1;
      }
    }

    let sc = self.comment;
    if (sc != null && sc != "") {
      str += "\n" + indentComment(commentString(sc), indent);
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

  function _stringifyFlowSeq(self, ctx: StringifyContext) -> string {
    let indent = ctx.indent;
    let indentStep = ctx.indentStep;
    let fcPadding = ctx.flowCollectionPadding;
    let commentString = ctx.options.commentString;
    let itemIndent = indent + "  " + indentStep;
    let itemCtx = StringifyContext { ...ctx, indent: itemIndent, inFlow: true };

    let reqNewline = false;
    let linesAtValue = 0;
    let lines: string[] = [];
    let i = 0;
    while (i < self.items.length()) {
      let item = self.items[i];
      let comment: string? = null;
      match (item) {
        let p: Pair => {
          let ik = p.key;
          if (ik.spaceBefore ?? false) {
            lines.push("");
          }
          addCommentBefore(ctx, lines, ik.commentBefore, false);
          if (ik.comment != null && ik.comment != "") {
            reqNewline = true;
          }

          let iv = p.value;
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
        },
        let n: Node => {
          if (n.spaceBefore ?? false) {
            lines.push("");
          }
          addCommentBefore(ctx, lines, n.commentBefore, false);
          if (n.comment != null && n.comment != "") {
            comment = n.comment;
          }
        },
      }

      if (comment != null) {
        reqNewline = true;
      }
      let str = stringifyNode(item, itemCtx, () -> void { comment = null; }, null);
      reqNewline = reqNewline || lines.length() > linesAtValue || str.includes("\n");
      if (i < self.items.length() - 1) {
        str += ",";
      } else if (ctx.options.trailingComma) {
        if (ctx.options.lineWidth > 0) {
          reqNewline = reqNewline ||
            lines.reduce((sum: int, line: string) -> int { sum + line.length() + 2 }, 2) + (str.length() + 2) > ctx.options.lineWidth;
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
      i += 1;
    }

    if (lines.length() == 0) {
      return "[]";
    }
    if (!reqNewline) {
      let len = lines.reduce((sum: int, line: string) -> int { sum + line.length() + 2 }, 2);
      reqNewline = ctx.options.lineWidth > 0 && len > ctx.options.lineWidth;
    }
    if (reqNewline) {
      let str = "[";
      for (let line in lines) {
        str += if (line != "") { "\n" + indentStep + indent + line } else { "\n" };
      }
      return str + "\n" + indent + "]";
    }
    "[" + fcPadding + lines.join(" ") + fcPadding + "]"
  }

  implements NodeBase {
    function cloneNode(self, schema: Schema?) -> Node {
      self.clone(schema)
    }

    /// A plain JavaScript representation of this node.
    function toJS(self, doc: Document?, ctx: ToJSContext?) -> unknown {
      if (self._class == "YAMLOMap") {
        return yamlOMap_toJS(self, doc, ctx);
      }
      let ctx_ = ctx ?? ToJSContext.new(null);
      if (self.anchor != null && self.anchor != "") {
        let res: unknown[] = [];
        ctx_.setAnchor(self, res);
        for (let item in self.items) {
          res.push(seq_item_to_js(item, doc, ctx_));
        }
        return res;
      }

      let res: unknown[] = [];
      for (let item in self.items) {
        res.push(seq_item_to_js(item, doc, ctx_));
      }
      if (ctx_.reviverSources != null) {
        let i = 0;
        while (i < self.items.length()) {
          ctx_.setSource(res, i.to_string(), self.items[i]);
          i += 1;
        }
      }

      res
    }

    function toString(self, ctx: StringifyContext?, onComment: Callback?, onChompKeep: Callback?) -> string {
      if (self._class == "YAMLOMap") {
        yamlOMap_checkKeys(self);
      }
      if (ctx == null) {
        return json_stringify(self.items.map((it: SeqItem) -> unknown { it }));
      }
      let flow = ctx.inFlow ?? (self.flow ?? false);
      if (flow) {
        self._stringifyFlowSeq(ctx)
      } else {
        self._stringifyBlockSeq(ctx, onComment, onChompKeep)
      }
    }
  }

  implements CollectionBase {
    function size(self) -> int {
      self.items.length()
    }
  }
}

/// `item.toJS(doc, ctx)` for a Node or Pair sequence item.
function seq_item_to_js(item: SeqItem, doc: Document?, ctx: ToJSContext) -> unknown {
  match (item) {
    let p: Pair => p.toJS(doc, ctx),
    let n: Node => n.toJS(doc, ctx),
  }
}

function isScalarValue(value: unknown) -> bool {
  !js_truthy(value) || js_typeof(value) != "object"
}

function nodeValue(schema: Schema, value: unknown, options: CreateNodeOptions?) -> SeqItem {
  match (value) {
    let p: Pair => p,
    _ => {
      let n = as_node(value);
      if (n != null) {
        return n;
      }
      let nc = NodeCreator.fromSchema(schema, options);
      nc.create(value, null)
    },
  }
}

function nodeValues(schema: Schema, values: unknown[]) -> SeqItem[] {
  let nc: NodeCreator? = null;
  let out: SeqItem[] = [];
  for (let value in values) {
    match (value) {
      let p: Pair => {
        out.push(p);
      },
      _ => {
        let n = as_node(value);
        if (n != null) {
          out.push(n);
        } else {
          let c = nc ?? NodeCreator.fromSchema(schema, null);
          nc = c;
          out.push(c.create(value, null));
        }
      },
    }
  }
  out
}

function addCommentBefore(ctx: StringifyContext, lines: string[], comment0: string?, chompKeep: bool) -> null {
  let comment = comment0;
  if (comment != null && comment != "" && chompKeep) {
    comment = comment.replace(re("^\\n+"), "");
  }
  if (comment != null && comment != "") {
    let ic = indentComment(ctx.options.commentString(comment), ctx.indent);
    lines.push(ic.trim_start()); // Avoid double indent on first line
  }
  null
}

/// The values of a JS iterable (`Symbol.iterator in Object(obj)`): arrays,
/// Sets, Maps (as `[key, value]` entries) and strings (as characters).
function js_iterable(obj: unknown) -> unknown[]? {
  match (obj) {
    null => null,
    let s: string => {
      let out: unknown[] = [];
      for (let c in s.chars()) {
        out.push(c);
      }
      out
    },
    let s: JsSet => s.values(),
    let m: JsMap<unknown> => {
      let out: unknown[] = [];
      let keys = m.keys();
      let vals = m.values();
      let i = 0;
      while (i < keys.length()) {
        let entry: unknown[] = [keys[i], vals[i]];
        out.push(entry);
        i += 1;
      }
      out
    },
    _ => js_as_array(obj),
  }
}

/// A JS integer number value as a BAML int.
function js_int(v: unknown) -> int {
  match (v) {
    let i: int => i,
    let f: float => f.itrunc() catch (e) { _ => 0 },
    _ => 0,
  }
}
