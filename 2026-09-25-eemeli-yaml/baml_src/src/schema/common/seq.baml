// Port of src/schema/common/seq.ts

function seq_tag() -> Tag {
  Tag {
    _id: 2,
    collection: "seq",
    default: true,
    nodeClass: "YAMLSeq",
    tag: "tag:yaml.org,2002:seq",
    createNode: (nc: NodeCreator, obj: unknown) -> Node { YAMLSeq.create(nc, obj) },
    resolveCollection: (seq: Node, onError: TagOnError, opts: Options) -> unknown {
      match (seq) {
        YAMLSeq => {},
        _ => {
          onError("Expected a sequence for this tag");
        },
      }
      seq
    },
  }
}
