// Port of src/schema/json/schema.ts

function stringifyJSON(node: Scalar) -> string {
  json_stringify(node.value)
}

function json_scalars() -> Tag[] {
  let intRe = re("^-?(?:0|[1-9][0-9]*)$");
  let floatRe = re("^-?(?:0|[1-9][0-9]*)(?:\\.[0-9]*)?(?:[eE][-+]?[0-9]+)?$");
  [
    Tag {
      _id: 12,
      identify: (value: unknown) -> bool { js_typeof(value) == "string" },
      default: true,
      tag: "tag:yaml.org,2002:str",
      resolve: (str: string, onError: TagOnError, opts: Options) -> unknown { str },
      stringify: (node: Scalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string { stringifyJSON(node) },
    },
    Tag {
      _id: 13,
      identify: (value: unknown) -> bool { value == null },
      createNode: (nc: NodeCreator, value: unknown) -> Node { Scalar.new(null) },
      default: true,
      tag: "tag:yaml.org,2002:null",
      testFn: (str: string) -> bool { str == "null" },
      resolve: (str: string, onError: TagOnError, opts: Options) -> unknown { null },
      stringify: (node: Scalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string { stringifyJSON(node) },
    },
    Tag {
      _id: 14,
      identify: (value: unknown) -> bool { js_typeof(value) == "boolean" },
      default: true,
      tag: "tag:yaml.org,2002:bool",
      testFn: (str: string) -> bool { str == "true" || str == "false" },
      resolve: (str: string, onError: TagOnError, opts: Options) -> unknown { str == "true" },
      stringify: (node: Scalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string { stringifyJSON(node) },
    },
    Tag {
      _id: 15,
      identify: (value: unknown) -> bool { intIdentify(value) },
      default: true,
      tag: "tag:yaml.org,2002:int",
      testFn: (str: string) -> bool { intRe.has_match(str) },
      resolve: (str: string, onError: TagOnError, opts: Options) -> unknown {
        if (opts.intAsBigInt ?? false) { js_parse_bigint(str) } else { js_parse_int(str, 10) }
      },
      stringify: (node: Scalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string {
        if (intIdentify(node.value)) { js_string(node.value) } else { json_stringify(node.value) }
      },
    },
    Tag {
      _id: 16,
      identify: (value: unknown) -> bool { js_typeof(value) == "number" },
      default: true,
      tag: "tag:yaml.org,2002:float",
      testFn: (str: string) -> bool { floatRe.has_match(str) },
      resolve: (str: string, onError: TagOnError, opts: Options) -> unknown { js_parse_float(str) },
      stringify: (node: Scalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string { stringifyJSON(node) },
    },
  ]
}

function json_error_tag() -> Tag {
  Tag {
    _id: 17,
    default: true,
    tag: "",
    testFn: (str: string) -> bool { true },
    resolve: (str: string, onError: TagOnError, opts: Options) -> unknown {
      onError("Unresolved plain scalar " + json_quote(str));
      str
    },
  }
}

function json_schema() -> Tag[] {
  let tags: Tag[] = [map_tag(), seq_tag()];
  for (let t in json_scalars()) {
    tags.push(t);
  }
  tags.push(json_error_tag());
  tags
}
