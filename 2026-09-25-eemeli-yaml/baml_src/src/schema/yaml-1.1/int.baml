// Port of src/schema/yaml-1.1/int.ts

function yaml11_intResolve(str0: string, offset0: int, radix: int, opts: Options) -> unknown {
  let sign = str0.at(0) ?? "";
  let offset = offset0;
  if (sign == "-" || sign == "+") {
    offset += 1;
  }
  let str = str_from(str0, offset).replace_all("_", "");
  if (opts.intAsBigInt ?? false) {
    if (radix == 2) {
      str = "0b" + str;
    } else if (radix == 8) {
      str = "0o" + str;
    } else if (radix == 16) {
      str = "0x" + str;
    }
    let n = js_parse_bigint(str);
    return if (sign == "-") { 0n - n } else { n };
  }
  let n = js_parse_int(str, radix);
  if (sign == "-") {
    match (n) {
      let i: int => 0 - i,
      let f: float => 0.0 - f,
    }
  } else {
    n
  }
}

function yaml11_intStringify(node: Scalar, radix: int, prefix: string) -> string {
  let value = node.value;
  if (intIdentify(value)) {
    let str = match (value) {
      let b: bigint => js_bigint_to_radix(b, radix),
      _ => js_int_to_radix(js_int(value), radix),
    };
    return if (!js_nonneg(value)) { "-" + prefix + str_from(str, 1) } else { prefix + str };
  }
  stringifyNumber(node, "1.2")
}

function yaml11_int_bin_tag() -> Tag {
  let rx = re("^[-+]?0b[0-1_]+$");
  Tag {
    _id: 21,
    identify: (value: unknown) -> bool { intIdentify(value) },
    default: true,
    tag: "tag:yaml.org,2002:int",
    format: "BIN",
    testFn: (str: string) -> bool { rx.has_match(str) },
    resolve: (str: string, onError: TagOnError, opts: Options) -> unknown { yaml11_intResolve(str, 2, 2, opts) },
    stringify: (node: Scalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string {
      yaml11_intStringify(node, 2, "0b")
    },
  }
}

function yaml11_int_oct_tag() -> Tag {
  let rx = re("^[-+]?0[0-7_]+$");
  Tag {
    _id: 22,
    identify: (value: unknown) -> bool { intIdentify(value) },
    default: true,
    tag: "tag:yaml.org,2002:int",
    format: "OCT",
    testFn: (str: string) -> bool { rx.has_match(str) },
    resolve: (str: string, onError: TagOnError, opts: Options) -> unknown { yaml11_intResolve(str, 1, 8, opts) },
    stringify: (node: Scalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string {
      yaml11_intStringify(node, 8, "0")
    },
  }
}

function yaml11_int_tag() -> Tag {
  let rx = re("^[-+]?[0-9][0-9_]*$");
  Tag {
    _id: 23,
    identify: (value: unknown) -> bool { intIdentify(value) },
    default: true,
    tag: "tag:yaml.org,2002:int",
    testFn: (str: string) -> bool { rx.has_match(str) },
    resolve: (str: string, onError: TagOnError, opts: Options) -> unknown { yaml11_intResolve(str, 0, 10, opts) },
    stringify: (node: Scalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string {
      stringifyNumber(node, "1.1")
    },
  }
}

function yaml11_int_hex_tag() -> Tag {
  let rx = re("^[-+]?0x[0-9a-fA-F_]+$");
  Tag {
    _id: 24,
    identify: (value: unknown) -> bool { intIdentify(value) },
    default: true,
    tag: "tag:yaml.org,2002:int",
    format: "HEX",
    testFn: (str: string) -> bool { rx.has_match(str) },
    resolve: (str: string, onError: TagOnError, opts: Options) -> unknown { yaml11_intResolve(str, 2, 16, opts) },
    stringify: (node: Scalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string {
      yaml11_intStringify(node, 16, "0x")
    },
  }
}
