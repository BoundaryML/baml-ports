// Port of src/schema/core/bool.ts

function core_bool_values_has(value: string) -> bool {
  value == "true" || value == "True" || value == "TRUE" || value == "false" || value == "False" || value == "FALSE"
}

function core_bool_tag() -> Tag {
  Tag {
    _id: 5,
    identify: (value: unknown) -> bool { js_typeof(value) == "boolean" },
    default: true,
    tag: "tag:yaml.org,2002:bool",
    testFn: (value: string) -> bool { core_bool_values_has(value) },
    resolve: (str: string, onError: TagOnError, opts: Options) -> unknown {
      Scalar.new(str.at(0) == "t" || str.at(0) == "T")
    },
    stringify: (item: Scalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string {
      let source = item.source;
      if (source != null) {
        if (source != "" && core_bool_values_has(source)) {
          let sv = source.at(0) == "t" || source.at(0) == "T";
          if (item.value == sv) {
            return source;
          }
        }
      }
      if (js_truthy(item.value)) { ctx.options.trueStr } else { ctx.options.falseStr }
    },
  }
}
