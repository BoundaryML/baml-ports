// Port of src/schema/common/string.ts

function string_tag() -> Tag {
  Tag {
    _id: 3,
    identify: (value: unknown) -> bool { js_typeof(value) == "string" || js_is_raw_json(value) },
    default: true,
    tag: "tag:yaml.org,2002:str",
    resolve: (str: string, onError: TagOnError, opts: Options) -> unknown { str },
    stringify: (item: Scalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string {
      let ctx2 = StringifyContext { ...ctx, actualString: ctx.actualString ?? true };
      stringifyString(item, ctx2, onComment, onChompKeep)
    },
  }
}
