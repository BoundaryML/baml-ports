// Port of src/schema/yaml-1.1/timestamp.ts

/// `parseSexagesimal(str, asBigInt)`: an int (or bigint) when every part is
/// an integer, else a float.
function parseSexagesimal(str: string, asBigInt: bool) -> unknown {
  let sign = str.at(0) ?? "";
  let parts = if (sign == "-" || sign == "+") { str_from(str, 1) } else { str };
  let ps = parts.replace_all("_", "").split(":");
  if (asBigInt) {
    let res = 0n;
    for (let p in ps) {
      res = res * 60n + js_parse_bigint(p);
    }
    return if (sign == "-") { 0n - res } else { res };
  }
  let allInt = ps.every((p: string) -> bool { !p.includes(".") });
  if (allInt) {
    let res = 0;
    for (let p in ps) {
      res = res * 60 + js_int(js_parse_int(p, 10));
    }
    return if (sign == "-") { 0 - res } else { res };
  }
  let res = 0.0;
  for (let p in ps) {
    res = res * 60.0 + js_to_number(p);
  }
  if (sign == "-") { 0.0 - res } else { res }
}

function stringifySexagesimal(node: Scalar) -> string {
  let value = node.value;
  match (value) {
    let b: bigint => {
      let v = b;
      let sign = "";
      if (v < 0n) {
        sign = "-";
        v = 0n - v;
      }
      let parts: string[] = [];
      let sec = v % 60n;
      parts.push(sec.to_string());
      if (v < 60n) {
        parts.unshift("0");
      } else {
        v = (v - sec) / 60n;
        let mins = v % 60n;
        parts.unshift(mins.to_string());
        if (v >= 60n) {
          v = (v - mins) / 60n;
          parts.unshift(v.to_string());
        }
      }
      sign + parts.map((n: string) -> string { if (n.length() < 2) { "0" + n } else { n } }).join(":")
    },
    _ => {
      let f = js_to_float(value);
      if (f == null) {
        return stringifyNumber(node, "1.2");
      }
      let v: float = f;
      if (v.is_nan() || !v.is_finite()) {
        return stringifyNumber(node, "1.2");
      }
      let sign = "";
      if (v < 0.0) {
        sign = "-";
        v = 0.0 - v;
      }
      let parts: float[] = [js_fmod(v, 60.0)]; // seconds, including ms
      if (v < 60.0) {
        parts.unshift(0.0); // at least one : is required
      } else {
        v = (v - parts[0]) / 60.0;
        parts.unshift(js_fmod(v, 60.0)); // minutes
        if (v >= 60.0) {
          v = (v - parts[0]) / 60.0;
          parts.unshift(v); // hours
        }
      }
      sign + parts.map((n: float) -> string {
        let s = js_number_to_string(n);
        if (s.length() < 2) { "0" + s } else { s }
      }).join(":").replace(re("000000\\d*$"), "") // % 60 may introduce error
    },
  }
}

/// JS `a % b` for floats
function js_fmod(a: float, b: float) -> float {
  a - (a / b).trunc() * b
}

function int_time_tag() -> Tag {
  let rx = re("^[-+]?[0-9][0-9_]*(?::[0-5]?[0-9])+$");
  Tag {
    _id: 32,
    identify: (value: unknown) -> bool { js_typeof(value) == "bigint" || js_is_integer(value) },
    default: true,
    tag: "tag:yaml.org,2002:int",
    format: "TIME",
    testFn: (str: string) -> bool { rx.has_match(str) },
    resolve: (str: string, onError: TagOnError, opts: Options) -> unknown { parseSexagesimal(str, opts.intAsBigInt ?? false) },
    stringify: (node: Scalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string {
      stringifySexagesimal(node)
    },
  }
}

function float_time_tag() -> Tag {
  let rx = re("^[-+]?[0-9][0-9_]*(?::[0-5]?[0-9])+\\.[0-9_]*$");
  Tag {
    _id: 33,
    identify: (value: unknown) -> bool { js_typeof(value) == "number" },
    default: true,
    tag: "tag:yaml.org,2002:float",
    format: "TIME",
    testFn: (str: string) -> bool { rx.has_match(str) },
    resolve: (str: string, onError: TagOnError, opts: Options) -> unknown {
      let v = parseSexagesimal(str, false);
      match (v) {
        let i: int => i * 1.0,
        _ => v,
      }
    },
    stringify: (node: Scalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string {
      stringifySexagesimal(node)
    },
  }
}

function timestamp_re() -> baml.regex.Regex {
  re(
    "^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2})" + // YYYY-Mm-Dd
      "(?:" + // time is optional
      "(?:t|T|[ \\t]+)" + // t | T | whitespace
      "([0-9]{1,2}):([0-9]{1,2}):([0-9]{1,2}(\\.[0-9]+)?)" + // Hh:Mm:Ss(.ss)?
      "(?:[ \\t]*(Z|[-+][012]?[0-9](?::[0-9]{2})?))?" + // Z | +5 | -03:30
      ")?$"
  )
}

function timestamp_tag() -> Tag {
  let timestampRe = timestamp_re();
  Tag {
    _id: 34,
    identify: (value: unknown) -> bool {
      match (value) {
        JsDate => true,
        _ => false,
      }
    },
    default: true,
    tag: "tag:yaml.org,2002:timestamp",

    // If the time zone is omitted, the timestamp is assumed to be specified
    // in UTC. The time part may be omitted altogether, resulting in a date
    // format. In such a case, the time part is assumed to be 00:00:00Z
    // (start of day, UTC).
    testFn: (str: string) -> bool { timestampRe.has_match(str) },

    resolve: (str: string, onError: TagOnError, opts: Options) -> unknown {
      let m = timestampRe.match_once(str);
      if (m == null) {
        throw js_error("!!timestamp expects a date, starting with yyyy-mm-dd");
      }
      let g = m.groups;
      let num = (i: int) -> int {
        let gi = g.at(i);
        if (gi == null) {
          0
        } else {
          let t = gi?.text ?? "";
          js_int(js_parse_int(t, 10))
        }
      };
      let year = num(1);
      let month = num(2);
      let day = num(3);
      let hour = num(4);
      let minute = num(5);
      let second = num(6);
      let g7 = g.at(7);
      let millisec = 0;
      if (g7 != null) {
        let t7 = g7?.text ?? "";
        millisec = js_int(js_parse_int((t7 + "00").slice(1, 4), 10));
      }
      let date = js_date_utc(year, month - 1, day, hour, minute, second, millisec);
      let g8 = g.at(8);
      let tz = if (g8 != null) { g8?.text ?? "" } else { "" };
      if (tz != "" && tz != "Z") {
        let d = js_to_float(parseSexagesimal(tz, false)) ?? 0.0;
        if (d.abs() < 30.0) {
          d = d * 60.0;
        }
        date -= js_int(60000.0 * d);
      }
      js_date(date)
    },

    stringify: (node: Scalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string {
      match (node.value) {
        let d: JsDate => d.toISOString().replace(re("(T00:00:00)?\\.000Z$"), ""),
        _ => "",
      }
    },
  }
}
