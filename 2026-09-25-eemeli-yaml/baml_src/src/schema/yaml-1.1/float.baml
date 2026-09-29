// Port of src/schema/yaml-1.1/float.ts

function yaml11_float_nan_tag() -> Tag {
  let rx = re("^(?:[-+]?\\.(?:inf|Inf|INF)|\\.nan|\\.NaN|\\.NAN)$");
  Tag {
    _id: 25,
    identify: (value: unknown) -> bool { js_typeof(value) == "number" },
    default: true,
    tag: "tag:yaml.org,2002:float",
    testFn: (str: string) -> bool { rx.has_match(str) },
    resolve: (str: string, onError: TagOnError, opts: Options) -> unknown { resolve_float_nan(str) },
    stringify: (node: Scalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string {
      stringifyNumber(node, "1.1")
    },
  }
}

function yaml11_float_exp_tag() -> Tag {
  let rx = re("^[-+]?(?:[0-9][0-9_]*)?(?:\\.[0-9_]*)?[eE][-+]?[0-9]+$");
  Tag {
    _id: 26,
    identify: (value: unknown) -> bool { js_typeof(value) == "number" },
    default: true,
    tag: "tag:yaml.org,2002:float",
    format: "EXP",
    testFn: (str: string) -> bool { rx.has_match(str) },
    resolve: (str: string, onError: TagOnError, opts: Options) -> unknown { js_parse_float(str.replace_all("_", "")) },
    stringify: (node: Scalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string {
      let num = js_to_number(node.value);
      if (num.is_finite()) { js_to_exponential(num) } else { stringifyNumber(node, "1.1") }
    },
  }
}

function yaml11_float_tag() -> Tag {
  let rx = re("^[-+]?(?:[0-9][0-9_]*)?\\.[0-9_]*$");
  Tag {
    _id: 27,
    identify: (value: unknown) -> bool { js_typeof(value) == "number" },
    default: true,
    tag: "tag:yaml.org,2002:float",
    testFn: (str: string) -> bool { rx.has_match(str) },
    resolve: (str: string, onError: TagOnError, opts: Options) -> unknown {
      let node = Scalar.new(js_parse_float(str.replace_all("_", "")));
      let dot = str.index_of(".");
      if (dot != null) {
        let f = str_from(str, dot + 1).replace_all("_", "");
        if (f.at(f.length() - 1) == "0") {
          node.minFractionDigits = f.length();
        }
      }
      node
    },
    stringify: (node: Scalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string {
      stringifyNumber(node, "1.1")
    },
  }
}
