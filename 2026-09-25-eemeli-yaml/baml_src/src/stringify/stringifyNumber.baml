// Port of src/stringify/stringifyNumber.ts

function stringifyNumber(node: Scalar, version: string) -> string {
  let value = node.value;
  let format = node.format;
  let minFractionDigits = node.minFractionDigits;
  let source = node.source;
  let tag = node.tag;
  match (value) {
    let b: bigint => {
      return b.to_string();
    },
    _ => {},
  }
  let num = match (value) {
    let i: int => i * 1.0,
    let f: float => f,
    _ => js_to_number(value),
  };
  if (!num.is_finite()) {
    if (js_typeof(value) == "number" && source != null && source != "") {
      let source_ = if (version == "1.1") { source.replace_all("_", "") } else { source };
      let pf = js_parse_float(source_);
      // `parseFloat(src) === num` is false for NaN; BAML `NaN == NaN` is true
      if (pf == num && !num.is_nan()) {
        return source;
      }
    }
    return if (num.is_nan()) { ".nan" } else if (num < 0.0) { "-.inf" } else { ".inf" };
  }
  // `Object.is(value, -0) ? '-0' : JSON.stringify(value)`
  let n = match (value) {
    let f: float => if (f == 0.0 && (1.0 / f) < 0.0) { "-0" } else { json_stringify(value) },
    _ => json_stringify(value),
  };
  if (
    format == null &&
    minFractionDigits != null && minFractionDigits != 0 &&
    (tag == null || tag == "" || tag == "tag:yaml.org,2002:float") &&
    re("^-?\\d").has_match(n) &&
    !n.includes("e")
  ) {
    let i = n.index_of(".") ?? -1;
    if (i < 0) {
      i = n.length();
      n += ".";
    }
    let d = minFractionDigits - (n.length() - i - 1);
    while (d > 0) {
      n += "0";
      d -= 1;
    }
  }
  n
}
