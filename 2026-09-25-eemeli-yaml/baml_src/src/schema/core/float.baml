// Port of src/schema/core/float.ts

function core_float_nan_values_has(v: string) -> bool {
  v == ".nan" || v == ".NaN" || v == ".NAN" || v == ".inf" || v == ".Inf" || v == ".INF" || v == "+.inf" || v == "+.Inf" || v == "+.INF" || v == "-.inf" || v == "-.Inf" || v == "-.INF"
}

function couldBeFloat(value: string) -> bool {
  let c = value.code_point_at(0) ?? -1;
  (c >= 0x30 && c <= 0x39) || // 0-9
    c == 0x2b || // +
    c == 0x2d || // -
    c == 0x2e // .
}

/// `str.slice(-3).toLowerCase() === 'nan' ? NaN : str[0] === '-' ? -Infinity : Infinity`
function resolve_float_nan(str: string) -> float {
  let n = str.length();
  let tail = str.slice(if (n >= 3) { n - 3 } else { 0 }, n).to_lower_case();
  if (tail == "nan") {
    baml.Float.nan()
  } else if (str.at(0) == "-") {
    0.0 - baml.Float.inf()
  } else {
    baml.Float.inf()
  }
}

function core_float_nan_tag() -> Tag {
  Tag {
    _id: 9,
    identify: (value: unknown) -> bool { js_typeof(value) == "number" },
    default: true,
    tag: "tag:yaml.org,2002:float",
    testFn: (value: string) -> bool { core_float_nan_values_has(value) },
    resolve: (str: string, onError: TagOnError, opts: Options) -> unknown { resolve_float_nan(str) },
    stringify: (node: Scalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string {
      stringifyNumber(node, "1.2")
    },
  }
}

function core_float_exp_tag() -> Tag {
  let floatExpRe = re("^[-+]?(?:\\.[0-9]+|[0-9]+(?:\\.[0-9]*)?)[eE][-+]?[0-9]+$");
  Tag {
    _id: 10,
    identify: (value: unknown) -> bool { js_typeof(value) == "number" },
    default: true,
    tag: "tag:yaml.org,2002:float",
    format: "EXP",
    testFn: (value: string) -> bool { couldBeFloat(value) && floatExpRe.has_match(value) },
    resolve: (str: string, onError: TagOnError, opts: Options) -> unknown { js_parse_float(str) },
    stringify: (node: Scalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string {
      let num = js_to_number(node.value);
      if (num.is_finite()) { js_to_exponential(num) } else { stringifyNumber(node, "1.2") }
    },
  }
}

function core_float_tag() -> Tag {
  let floatRe = re("^[-+]?(?:\\.[0-9]+|[0-9]+\\.[0-9]*)$");
  Tag {
    _id: 11,
    identify: (value: unknown) -> bool { js_typeof(value) == "number" },
    default: true,
    tag: "tag:yaml.org,2002:float",
    testFn: (value: string) -> bool { couldBeFloat(value) && floatRe.has_match(value) },
    resolve: (str: string, onError: TagOnError, opts: Options) -> unknown {
      let node = Scalar.new(js_parse_float(str));
      let dot = str.index_of(".");
      if (dot != null && str.at(str.length() - 1) == "0") {
        node.minFractionDigits = str.length() - dot - 1;
      }
      node
    },
    stringify: (node: Scalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string {
      stringifyNumber(node, "1.2")
    },
  }
}
