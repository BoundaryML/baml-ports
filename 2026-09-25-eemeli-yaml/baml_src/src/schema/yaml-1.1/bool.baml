// Port of src/schema/yaml-1.1/bool.ts

function yaml11_boolStringify(item: Scalar, ctx: StringifyContext) -> string {
  let value = item.value;
  let boolObj = if (js_truthy(value)) { yaml11_true_tag() } else { yaml11_false_tag() };
  let source = item.source;
  let t = boolObj.testFn;
  if (source != null && source != "" && t != null) {
    if (t(source)) {
      return source;
    }
  }
  if (js_truthy(value)) { ctx.options.trueStr } else { ctx.options.falseStr }
}

function yaml11_true_tag() -> Tag {
  let rx = re("^(?:Y|y|[Yy]es|YES|[Tt]rue|TRUE|[Oo]n|ON)$");
  Tag {
    _id: 19,
    identify: (value: unknown) -> bool { value == true },
    default: true,
    tag: "tag:yaml.org,2002:bool",
    testFn: (str: string) -> bool { rx.has_match(str) },
    resolve: (str: string, onError: TagOnError, opts: Options) -> unknown { Scalar.new(true) },
    stringify: (item: Scalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string {
      yaml11_boolStringify(item, ctx)
    },
  }
}

function yaml11_false_tag() -> Tag {
  let rx = re("^(?:N|n|[Nn]o|NO|[Ff]alse|FALSE|[Oo]ff|OFF)$");
  Tag {
    _id: 20,
    identify: (value: unknown) -> bool { value == false },
    default: true,
    tag: "tag:yaml.org,2002:bool",
    testFn: (str: string) -> bool { rx.has_match(str) },
    resolve: (str: string, onError: TagOnError, opts: Options) -> unknown { Scalar.new(false) },
    stringify: (item: Scalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string {
      yaml11_boolStringify(item, ctx)
    },
  }
}
