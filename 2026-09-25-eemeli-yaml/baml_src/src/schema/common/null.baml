// Port of src/schema/common/null.ts

function null_values_has(value: string) -> bool {
  value == "" || value == "~" || value == "null" || value == "Null" || value == "NULL"
}

function null_tag() -> Tag {
  Tag {
    _id: 4,
    identify: (value: unknown) -> bool { value == null },
    createNode: (nc: NodeCreator, value: unknown) -> Node { Scalar.new(null) },
    default: true,
    tag: "tag:yaml.org,2002:null",
    testFn: (value: string) -> bool { null_values_has(value) },
    resolve: (str: string, onError: TagOnError, opts: Options) -> unknown { Scalar.new(null) },
    stringify: (item: Scalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string {
      let source = item.source;
      if (source != null) {
        if (null_values_has(source)) {
          return source;
        }
      }
      ctx.options.nullStr
    },
  }
}
