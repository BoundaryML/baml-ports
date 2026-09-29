// Port of src/schema/Schema.ts

class Schema {
  _id: int
  compat: Tag[]?
  knownTags: map<string, Tag>
  mapKey: (unknown) -> unknown throws unknown
  name: string
  tags: Tag[]
  toStringOptions: ToStringOptions?

  /// `new Schema(options)`
  function new(opts: SchemaOptions) -> Schema {
    let compat_ = opts.compat;
    let compat: Tag[]? = match (compat_) {
      null => null,
      let s: string => if (s != "") { getTags(null, s, null) } else { null },
      let arr: TagRef[] => getTags(arr, "compat", null),
    };
    let schema_ = opts.schema;
    let name = match (schema_) {
      let s: string => if (s != "") { s } else { "core" },
      _ => "core",
    };
    let mk = opts.mapKey;
    Schema {
      _id: new_id(),
      compat: compat,
      mapKey: if (mk != null) { mk } else { defaultMapKey },
      name: name,
      knownTags: if (opts.resolveKnownTags ?? false) { coreKnownTags() } else { {} },
      tags: getTags(opts.customTags, name, opts.merge),
      toStringOptions: opts.toStringDefaults,
    }
  }

  // These are used by createNode() and composeScalar()
  /// @internal (`schema.map`)
  function mapTag(self) -> Tag {
    map_tag()
  }

  /// @internal (`schema.scalar`)
  function scalarTag(self) -> Tag {
    string_tag()
  }

  /// @internal (`schema.seq`)
  function seqTag(self) -> Tag {
    seq_tag()
  }

  function clone(self) -> Schema {
    Schema { ...self, _id: new_id(), tags: self.tags.slice(0, self.tags.length()) }
  }
}

function defaultMapKey(value0: unknown) -> unknown {
  let value = match (value0) {
    let p: Pair => p.key,
    _ => value0,
  };
  match (value) {
    let s: Scalar => s.value,
    _ => value,
  }
}
