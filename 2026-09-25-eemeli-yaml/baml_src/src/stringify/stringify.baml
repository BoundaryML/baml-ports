// Port of src/stringify/stringify.ts

class StringifyContext {
  actualString: bool?
  /// `Set<string>` of anchors defined so far
  anchors: JsSet
  doc: Document
  forceBlockIndent: bool?
  implicitKey: bool?
  indent: string
  indentStep: string
  indentAtStart: int?
  inFlow: bool?
  inStringifyKey: bool?
  flowCollectionPadding: string
  options: StringifyOptions
  /// `Set<Alias>`
  resolvedAliases: JsSet?
  sortMapEntries: ((Pair, Pair) -> int throws unknown)?
}

/// `Readonly<Required<Omit<ToStringOptions, 'collectionStyle' | 'indent'>>>`
/// (plus the two omitted ones, as they are also carried through).
class StringifyOptions {
  blockQuote: bool | "folded" | "literal"
  commentString: (string) -> string throws unknown
  defaultKeyType: string?
  defaultStringType: string
  directives: bool?
  doubleQuotedAsJSON: bool
  doubleQuotedMinMultiLineLength: int
  falseStr: string
  flowCollectionPadding: bool
  indentSeq: bool
  lineWidth: int
  minContentWidth: int
  nullStr: string
  simpleKeys: bool
  singleQuote: bool?
  sortMapEntries: bool | ((Pair, Pair) -> int throws unknown)
  trailingComma: bool
  trueStr: string
  verifyAliasOrder: bool
  collectionStyle: string?
  indent: int?
}

function defaultStringifyOptions() -> StringifyOptions {
  StringifyOptions {
    blockQuote: true,
    commentString: (s: string) -> string { stringifyComment(s) },
    defaultKeyType: null,
    defaultStringType: "PLAIN",
    directives: null,
    doubleQuotedAsJSON: false,
    doubleQuotedMinMultiLineLength: 40,
    falseStr: "false",
    flowCollectionPadding: true,
    indentSeq: true,
    lineWidth: 80,
    minContentWidth: 20,
    nullStr: "null",
    simpleKeys: false,
    singleQuote: null,
    sortMapEntries: false,
    trailingComma: false,
    trueStr: "true",
    verifyAliasOrder: true,
  }
}

/// `{ ...resolved, ...options }` for stringify options.
function stringify_options_merge(base: StringifyOptions, o: Options?) -> StringifyOptions {
  if (o == null) {
    return base;
  }
  let bq = o.blockQuote;
  let cs = o.commentString;
  let sme = o.sortMapEntries;
  StringifyOptions {
    blockQuote: if (bq != null) { bq } else { base.blockQuote },
    commentString: if (cs != null) { cs } else { base.commentString },
    defaultKeyType: o.defaultKeyType ?? base.defaultKeyType,
    defaultStringType: o.defaultStringType ?? base.defaultStringType,
    directives: o.directives ?? base.directives,
    doubleQuotedAsJSON: o.doubleQuotedAsJSON ?? base.doubleQuotedAsJSON,
    doubleQuotedMinMultiLineLength: o.doubleQuotedMinMultiLineLength ?? base.doubleQuotedMinMultiLineLength,
    falseStr: o.falseStr ?? base.falseStr,
    flowCollectionPadding: o.flowCollectionPadding ?? base.flowCollectionPadding,
    indentSeq: o.indentSeq ?? base.indentSeq,
    lineWidth: o.lineWidth ?? base.lineWidth,
    minContentWidth: o.minContentWidth ?? base.minContentWidth,
    nullStr: o.nullStr ?? base.nullStr,
    simpleKeys: o.simpleKeys ?? base.simpleKeys,
    singleQuote: o.singleQuote ?? base.singleQuote,
    sortMapEntries: if (sme != null) { sme } else { base.sortMapEntries },
    trailingComma: o.trailingComma ?? base.trailingComma,
    trueStr: o.trueStr ?? base.trueStr,
    verifyAliasOrder: o.verifyAliasOrder ?? base.verifyAliasOrder,
    collectionStyle: o.collectionStyle ?? base.collectionStyle,
    indent: o.indent ?? base.indent,
  }
}

/// (The original caches this per `toStringOptions` object in a WeakMap.)
function getResolvedOptions(schema: Schema) -> StringifyOptions {
  stringify_options_merge(defaultStringifyOptions(), schema.toStringOptions)
}

/// `a.key < b.key ? -1 : a.key > b.key ? 1 : 0` — JS relational comparison
/// of two Node objects coerces them with `String(node)`.
function sortMapEntriesByKey(a: Pair, b: Pair) -> int {
  let ak = js_string(a.key);
  let bk = js_string(b.key);
  if (ak < bk) { -1 } else if (ak > bk) { 1 } else { 0 }
}

function createStringifyContext(doc: Document, options: ToStringOptions?) -> StringifyContext {
  let resolved = getResolvedOptions(doc.schema);
  let opt = stringify_options_merge(resolved, options);

  let inFlow: bool? = match (opt.collectionStyle) {
    "block" => false,
    "flow" => true,
    _ => null,
  };

  let sme = opt.sortMapEntries;
  let sortMapEntries = match (sme) {
    let b: bool => if (b) { sortMapEntriesByKey } else { null },
    let f: (Pair, Pair) -> int throws unknown => f,
  };

  let ind = opt.indent;
  StringifyContext {
    anchors: js_set(),
    doc: doc,
    flowCollectionPadding: if (opt.flowCollectionPadding) { " " } else { "" },
    indent: "",
    indentStep: if (ind != null) { " ".repeat(ind) } else { "  " },
    inFlow: inFlow,
    options: opt,
    sortMapEntries: sortMapEntries,
  }
}

function getTagObject(tags: Tag[], item: Node) -> Tag {
  let itag = item.tag;
  if (itag != null && itag != "") {
    let matched = tags.filter((t: Tag) -> bool { t.tag == itag });
    if (matched.length() > 0) {
      let fmt = match (item) {
        let s: Scalar => s.format,
        _ => null,
      };
      return matched.find((t: Tag) -> bool { t.format == fmt }) ?? matched[0];
    }
  }

  let tagObj: Tag? = null;
  let obj: unknown = null;
  match (item) {
    let s: Scalar => {
      obj = s.value;
      let o = s.value;
      let matched = tags.filter((t: Tag) -> bool {
        let id = t.identify;
        if (id != null) { id(o) } else { false }
      });
      if (matched.length() > 1) {
        let testMatch = matched.filter((t: Tag) -> bool { t.testFn != null });
        if (testMatch.length() > 0) {
          matched = testMatch;
        }
      }
      let fmt = s.format;
      tagObj = matched.find((t: Tag) -> bool { t.format == fmt }) ?? matched.find((t: Tag) -> bool { t.format == null });
    },
    _ => {
      obj = item;
      tagObj = tags.find((t: Tag) -> bool {
        let nc = t.nodeClass;
        if (nc != null) { node_is_instance_of(item, nc) } else { false }
      });
    },
  }

  if (tagObj == null) {
    let name = js_constructor_name(obj);
    throw js_error("Tag not resolved for " + name + " value");
  }
  tagObj ?? tags[0]
}

/// `obj?.constructor?.name ?? (obj === null ? 'null' : typeof obj)`
function js_constructor_name(obj: unknown) -> string {
  match (obj) {
    null => "null",
    bool => "Boolean",
    int => "Number",
    float => "Number",
    bigint => "BigInt",
    string => "String",
    JsSymbol => "Symbol",
    JsMap<unknown> => "Map",
    JsSet => "Set",
    JsDate => "Date",
    uint8array => "Uint8Array",
    Scalar => "Scalar",
    YAMLMap => "YAMLMap",
    YAMLSeq => "YAMLSeq",
    YAMLSet => "YAMLSet",
    Alias => "Alias",
    Pair => "Pair",
    _ => if (js_is_array(obj)) { "Array" } else { "Object" },
  }
}

// needs to be called before value stringifier to allow for circular anchor refs
function stringifyProps(node: Node, tagObj: Tag, ctx: StringifyContext) -> string {
  let directives = ctx.doc.directives;
  if (directives == null) {
    return "";
  }
  let props: string[] = [];
  let anchor = node.anchor;
  if (anchor != null) {
    if (anchor != "" && anchorIsValid(anchor)) {
      ctx.anchors.add(anchor);
      props.push("&" + anchor);
    }
  }
  let tag = node.tag ?? (if (tag_default_truthy(tagObj)) { null } else { tagObj.tag });
  if (tag != null && tag != "") {
    props.push(directives.tagString(tag));
  }
  props.join(" ")
}

function stringifyNode(node0: SeqItem?, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string {
  let node: Node? = null;
  match (node0) {
    let p: Pair => {
      return p.toString(ctx, onComment, onChompKeep);
    },
    let a: Alias => {
      if (ctx.doc.directives != null) {
        return a.toString(ctx, null, null);
      }
      let ra = ctx.resolvedAliases;
      if (ra?.has(a) ?? false) {
        let msg = "Cannot stringify circular structure without alias nodes";
        throw js_type_error(msg);
      }

      if (ra != null) {
        ra.add(a);
      } else {
        let s = js_set();
        s.add(a);
        ctx.resolvedAliases = s;
      }
      node = a.resolve(ctx.doc, null);
    },
    let n: Node => {
      node = n;
    },
    null => {},
  }

  let tagObj: Tag? = null;
  if (node == null) {
    node = ctx.doc.createNode(null, null, Options {
      onTagObj: (o: Tag) -> void {
        tagObj = o;
      },
    });
  }
  let n: Node = node ?? Scalar.new(null);
  let to: Tag = tagObj ?? getTagObject(ctx.doc.schema.tags, n);

  let props = stringifyProps(n, to, ctx);
  if (props.length() > 0) {
    ctx.indentAtStart = (ctx.indentAtStart ?? 0) + props.length() + 1;
  }

  let tsf = to.stringify;
  let str = match (n) {
    let s: Scalar => if (tsf != null) { tsf(s, ctx, onComment, onChompKeep) } else { stringifyString(s, ctx, onComment, onChompKeep) },
    _ => n.toString(ctx, onComment, onChompKeep),
  };
  if (props == "") {
    return str;
  }
  let isScalar = match (n) {
    Scalar => true,
    _ => false,
  };
  if (isScalar || str.at(0) == "{" || str.at(0) == "[") {
    props + " " + str
  } else {
    props + "\n" + ctx.indent + str
  }
}
