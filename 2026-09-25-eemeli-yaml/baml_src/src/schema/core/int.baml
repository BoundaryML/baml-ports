// Port of src/schema/core/int.ts

function intIdentify(value: unknown) -> bool {
  js_typeof(value) == "bigint" || js_is_integer(value)
}

/// `value >= 0` for an int/float/bigint value.
function js_nonneg(value: unknown) -> bool {
  match (value) {
    let i: int => i >= 0,
    let f: float => f >= 0.0,
    let b: bigint => b >= 0n,
    _ => false,
  }
}

function core_int_resolve(str: string, offset: int, radix: int, opts: Options) -> unknown {
  if (opts.intAsBigInt ?? false) {
    js_parse_bigint(str)
  } else {
    js_parse_int(str_from(str, offset), radix)
  }
}

function core_intStringify(node: Scalar, radix: int, prefix: string) -> string {
  let value = node.value;
  if (intIdentify(value) && js_nonneg(value)) {
    return match (value) {
      let b: bigint => prefix + js_bigint_to_radix(b, radix),
      _ => prefix + js_int_to_radix(js_int(value), radix),
    };
  }
  stringifyNumber(node, "1.2")
}

function isOctInt(value: string) -> bool {
  let cps = value.to_code_points();
  if (cps.length() < 3 || cps[0] != 48 || cps[1] != 111) {
    return false;
  }
  let i = 2;
  while (i < cps.length()) {
    let c = cps[i];
    if (c < 0x30 || c > 0x37) {
      return false; // not 0-7
    }
    i += 1;
  }
  true
}

function isInt(value: string) -> bool {
  let cps = value.to_code_points();
  let i = 0;
  if (cps.length() == 0) {
    return false;
  }
  if (cps[0] == 0x2b || cps[0] == 0x2d) {
    i = 1; // +/-
  }
  if (i == cps.length()) {
    return false;
  }
  while (i < cps.length()) {
    let c = cps[i];
    if (c < 0x30 || c > 0x39) {
      return false; // not 0-9
    }
    i += 1;
  }
  true
}

function isHexInt(value: string) -> bool {
  let cps = value.to_code_points();
  if (cps.length() < 3 || cps[0] != 48 || cps[1] != 120) {
    return false;
  }
  let i = 2;
  while (i < cps.length()) {
    let c = cps[i];
    if (!(c >= 0x30 && c <= 0x39) && !(c >= 0x41 && c <= 0x46) && !(c >= 0x61 && c <= 0x66)) {
      return false;
    }
    i += 1;
  }
  true
}

function core_int_oct_tag() -> Tag {
  Tag {
    _id: 6,
    identify: (value: unknown) -> bool { intIdentify(value) && js_nonneg(value) },
    default: true,
    tag: "tag:yaml.org,2002:int",
    format: "OCT",
    testFn: (value: string) -> bool { isOctInt(value) },
    resolve: (str: string, onError: TagOnError, opts: Options) -> unknown { core_int_resolve(str, 2, 8, opts) },
    stringify: (node: Scalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string {
      core_intStringify(node, 8, "0o")
    },
  }
}

function core_int_tag() -> Tag {
  Tag {
    _id: 7,
    identify: (value: unknown) -> bool { intIdentify(value) },
    default: true,
    tag: "tag:yaml.org,2002:int",
    testFn: (value: string) -> bool { isInt(value) },
    resolve: (str: string, onError: TagOnError, opts: Options) -> unknown { core_int_resolve(str, 0, 10, opts) },
    stringify: (node: Scalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string {
      stringifyNumber(node, "1.2")
    },
  }
}

function core_int_hex_tag() -> Tag {
  Tag {
    _id: 8,
    identify: (value: unknown) -> bool { intIdentify(value) && js_nonneg(value) },
    default: true,
    tag: "tag:yaml.org,2002:int",
    format: "HEX",
    testFn: (value: string) -> bool { isHexInt(value) },
    resolve: (str: string, onError: TagOnError, opts: Options) -> unknown { core_int_resolve(str, 2, 16, opts) },
    stringify: (node: Scalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string {
      core_intStringify(node, 16, "0x")
    },
  }
}
