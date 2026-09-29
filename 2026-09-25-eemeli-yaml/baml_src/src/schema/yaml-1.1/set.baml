// Port of src/schema/yaml-1.1/set.ts

function set_tag() -> Tag {
  Tag {
    _id: 31,
    collection: "map",
    identify: (value: unknown) -> bool {
      match (value) {
        JsSet => true,
        _ => false,
      }
    },
    nodeClass: "YAMLSet",
    default: false,
    tag: "tag:yaml.org,2002:set",
    createNode: (nc: NodeCreator, iterable: unknown) -> Node {
      let set = YAMLSet.new(nc.schema);
      let iter = js_iterable(iterable);
      if (iter != null) {
        for (let value0 in iter) {
          let value = value0;
          let r = nc.replacer;
          match (r) {
            let f: ReplacerFn => {
              value = f(value, value, iterable);
            },
            _ => {},
          }
          let mk = nc.schema.mapKey(value);
          set.values.set(mk, nc.create(value, null));
        }
      }
      set
    },
    resolveCollection: (set: Node, onError: TagOnError, opts: Options) -> unknown {
      match (set) {
        YAMLSet => {},
        _ => {
          onError("Expected a set for this tag");
        },
      }
      set
    },
  }
}
