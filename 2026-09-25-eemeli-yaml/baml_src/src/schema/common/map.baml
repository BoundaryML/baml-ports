// Port of src/schema/common/map.ts

function map_tag() -> Tag {
  Tag {
    _id: 1,
    collection: "map",
    default: true,
    nodeClass: "YAMLMap",
    tag: "tag:yaml.org,2002:map",
    createNode: (nc: NodeCreator, obj: unknown) -> Node { YAMLMap.create(nc, obj) },
    resolveCollection: (map_: Node, onError: TagOnError, opts: Options) -> unknown {
      match (map_) {
        YAMLMap => {},
        _ => {
          onError("Expected a mapping for this tag");
        },
      }
      map_
    },
  }
}
