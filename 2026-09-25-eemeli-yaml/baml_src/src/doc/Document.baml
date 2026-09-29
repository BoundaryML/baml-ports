// Port of src/doc/Document.ts
//
// Constructor overloads `new Document(value?, options?)` and
// `new Document(value, replacer, options?)` become
// `Document.new(value, replacer, options)` with explicit nulls.

/// `DocValue = Scalar | YAMLSeq | YAMLMap | YAMLSet`
type DocValue = Node

class Document {
  _id: int
  /// A comment before this Document
  commentBefore: string?
  /// A comment immediately after this Document
  comment: string?
  /// The document value.
  value: Node
  directives: Directives?
  /// Errors encountered during parsing.
  errors: YAMLError[]
  options: Options
  /// The `[start, value-end, node-end]` character offsets for the part of the
  /// source parsed into this document (undefined if not parsed). The
  /// `value-end` and `node-end` positions are themselves not included in
  /// their respective ranges.
  range: int[]?
  /// The schema used with the document. Use `setSchema()` to change.
  schema: Schema
  /// Warnings encountered during parsing.
  warnings: YAMLError[]

  /// @param value - The initial value for the document, which will be
  ///   wrapped in a Node container.
  function new(value: unknown, replacer: Replacer?, options: Options?) -> Document {
    let defaults = Options {
      intAsBigInt: false,
      keepSourceTokens: false,
      logLevel: "warn",
      prettyErrors: true,
      strict: true,
      stringKeys: false,
      version: "1.2",
    };
    let opt = options_assign(defaults, options);
    let doc = Document {
      _id: new_id(),
      value: Scalar.new(null),
      errors: [],
      options: opt,
      schema: Schema.new(Options {}),
      warnings: [],
    };
    let version: string? = opt.version;
    let dirs = options?._directives;
    if (dirs != null) {
      let d = dirs.atDocument();
      doc.directives = d;
      if (d.yaml.explicit ?? false) {
        version = d.yaml.version;
      }
    } else {
      doc.directives = Directives.new(DirectivesYaml { version: version ?? "1.2" }, null);
    }
    doc.setSchema(version, options);

    doc.value = doc.createNode(value, replacer, options);
    doc
  }

  /// Create a deep copy of this Document and its value.
  ///
  /// Custom Node values that inherit from `Object` still refer to their
  /// original instances.
  function clone(self) -> Document {
    let schema = self.schema.clone();
    let d = self.directives;
    let r = self.range;
    Document {
      _id: new_id(),
      commentBefore: self.commentBefore,
      comment: self.comment,
      errors: self.errors.slice(0, self.errors.length()),
      warnings: self.warnings.slice(0, self.warnings.length()),
      options: Options { ...self.options },
      directives: if (d != null) { d.clone() } else { null },
      schema: schema,
      value: self.value.cloneNode(schema),
      range: if (r != null) { r.slice(0, r.length()) } else { null },
    }
  }

  /// Create a new `Alias` node, ensuring that the target `node` has the
  /// required anchor.
  ///
  /// If `node` already has an anchor, `name` is ignored.
  /// Otherwise, the `node.anchor` value will be set to `name`,
  /// or if an anchor with that name is already present in the document,
  /// `name` will be used as a prefix for a new unique anchor.
  /// If `name` is undefined, the generated anchor will use 'a' as a prefix.
  function createAlias(self, node: Node, name: string?) -> Alias {
    let base = nb(node);
    let a = base.anchor;
    if (a == null || a == "") {
      let prev = anchorNames(self);
      base.anchor = if (name == null || name == "" || prev.has(name)) {
        findNewAnchor(if (name != null && name != "") { name } else { "a" }, prev)
      } else {
        name
      };
    }
    Alias.new(base.anchor ?? "")
  }

  /// Convert any value into a `Node` using the current schema, recursively
  /// turning objects into collections.
  function createNode(self, value0: unknown, replacer0: Replacer?, options: CreateNodeOptions?) -> Node {
    let value = value0;
    let nc = NodeCreator.new(self, options, null);
    match (replacer0) {
      let f: ReplacerFn => {
        let holder: map<string, unknown> = { "": value };
        value = f("", value, holder);
        nc = NodeCreator.new(self, options, f);
      },
      let arr: unknown[] => {
        let asStr: unknown[] = [];
        for (let v in arr) {
          match (v) {
            int => {
              asStr.push(js_string(v));
            },
            float => {
              asStr.push(js_string(v));
            },
            _ => {},
          }
        }
        let r: unknown[] = arr.slice(0, arr.length());
        for (let s in asStr) {
          r.push(s);
        }
        nc = NodeCreator.new(self, options, r);
      },
      null => {},
    }
    let node = nc.create(value, options?.tag);
    nc.setAnchors();
    node
  }

  /// Convert a key and a value into a `Pair` using the current schema,
  /// recursively wrapping all values as `Scalar` or `Collection` nodes.
  function createPair(self, key: unknown, value: unknown, options: CreateNodeOptions?) -> Pair {
    let nc = NodeCreator.new(self, options ?? Options {}, null);
    let pair = nc.createPair(key, value);
    nc.setAnchors();
    pair
  }

  /// Create a YAML 1.1 `<<` merge pair with the provided value.
  ///
  /// Throws if the current schema does not support merge keys,
  /// or if the value has an invalid shape.
  function createMergePair(self, value: unknown, options: CreateNodeOptions?) -> Pair {
    if (self.schema.tags.every((tag: Tag) -> bool { tag.tag != "tag:yaml.org,2002:merge" })) {
      throw js_error("Merge tags are not supported in this Document");
    }
    let vn = as_node(value);
    let v: Node = if (options == null && vn != null) { vn } else { self.createNode(value, null, options) };
    let ok = match (v) {
      Alias => true,
      YAMLMap => true,
      let s: YAMLSeq => s.items.every((a: SeqItem) -> bool {
        match (a) {
          Alias => true,
          YAMLMap => true,
          _ => false,
        }
      }),
      _ => false,
    };
    if (ok) {
      return Pair.new(MergeKey(), v);
    }
    throw js_error("Invalid merge pair value")
  }

  /// Returns item at `key`, or `undefined` if not found.
  function get(self, key: unknown) -> SeqItem? {
    match (self.value) {
      let m: YAMLMap => m.get(key),
      let s: YAMLSet => s.get(key),
      let q: YAMLSeq => {
        if (js_is_integer(key)) {
          q.at(js_int(key))
        } else {
          throw js_type_error("Expected an integer, not " + json_stringify(key) + ".");
        }
      },
      _ => null,
    }
  }

  /// Returns pair at `key`, or `undefined` if not found.
  function getPair(self, key: unknown) -> Pair? {
    match (self.value) {
      let m: YAMLMap => m.getPair(key),
      let q: YAMLSeq => {
        if (!js_is_integer(key)) {
          throw js_type_error("Expected an integer, not " + json_stringify(key) + ".");
        }
        let pair = q.at(js_int(key));
        match (pair) {
          let p: Pair => p,
          _ => {
            throw js_type_error("Value at " + js_string(key) + " is not a Pair");
          },
        }
      },
      _ => null,
    }
  }

  /// Sets a value in this document's top-level collection.
  /// For `!!set`, `value` is ignored.
  function set(self, key: unknown, value: unknown) -> null {
    match (self.value) {
      let s: YAMLSet => {
        s.add(key);
      },
      let m: YAMLMap => {
        m.set(key, value);
      },
      let q: YAMLSeq => {
        q.set(key, value);
      },
      _ => {
        throw js_error("Expected a YAML collection as document value");
      },
    }
    null
  }

  /// Change the YAML version and schema used by the document.
  /// A `null` version disables support for directives, explicit tags,
  /// anchors, and aliases. It also requires the `schema` option to be given
  /// as a `Schema` instance value.
  ///
  /// Overrides all previously set schema options.
  function setSchema(self, version: string?, options: SchemaOptions?) -> null {
    let opt: Options? = null;
    match (version) {
      "1.1" => {
        let d = self.directives;
        if (d != null) {
          d.yaml.version = "1.1";
        } else {
          self.directives = Directives.new(DirectivesYaml { version: "1.1" }, null);
        }
        opt = Options { resolveKnownTags: false, schema: "yaml-1.1" };
      },
      "1.2" => {
        self.setSchemaVersion("1.2");
        opt = Options { resolveKnownTags: true, schema: "core" };
      },
      "next" => {
        self.setSchemaVersion("next");
        opt = Options { resolveKnownTags: true, schema: "core" };
      },
      null => {
        self.directives = null;
        opt = null;
      },
      _ => {
        let sv = json_stringify(version);
        throw js_error("Expected '1.1', '1.2' or null as first argument, but found: " + sv);
      },
    }

    // Not using `instanceof Schema` to allow for duck typing
    let s = options?.schema;
    match (s) {
      let sch: Schema => {
        self.schema = sch;
      },
      _ => {
        if (opt != null) {
          self.schema = Schema.new(options_assign(opt, options));
        } else {
          throw js_error("With a null YAML version, the { schema: Schema } option is required");
        }
      },
    }
    null
  }

  function setSchemaVersion(self, version: string) -> null {
    let d = self.directives;
    if (d != null) {
      d.yaml.version = version;
    } else {
      self.directives = Directives.new(DirectivesYaml { version: version }, null);
    }
    null
  }

  /// A plain JavaScript representation of the document `value`.
  function toJS(self, opt0: ToJSOptions?) -> unknown {
    let opt = opt0 ?? Options {};
    let ctx = ToJSContext.new(opt);
    let res = self.value.toJS(self, ctx);
    let onAnchor = opt.onAnchor;
    if (onAnchor != null) {
      for (let av in ctx.anchors.values()) {
        onAnchor(av.res, av.count);
      }
    }
    let reviver = opt.reviver;
    if (reviver != null) {
      let holder: map<string, unknown> = { "": res };
      ctx.setSource(holder, "", self.value);
      return applyReviver(reviver, ctx.reviverSources ?? ReviverSources { holders: [], sources: [] }, holder, "", res);
    }
    res
  }

  /// A JSON representation of the document `value`.
  function toJSON(self) -> unknown {
    self.toJS(Options { mapAsMap: false })
  }

  /// A YAML representation of the document.
  function toString(self, options: ToStringOptions?) -> string {
    if (self.errors.length() > 0) {
      throw js_error("Document with errors cannot be stringified");
    }
    let ind = options?.indent;
    if (ind != null) {
      if (ind <= 0) {
        let s = json_stringify(ind);
        throw js_error("\"indent\" option must be a positive integer, not " + s);
      }
    }
    stringifyDocument(self, options ?? Options {})
  }
}
