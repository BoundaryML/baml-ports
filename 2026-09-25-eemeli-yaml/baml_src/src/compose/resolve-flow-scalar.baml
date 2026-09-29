// Port of src/compose/resolve-flow-scalar.ts

/// `(offset, code, message) => void`
type FlowScalarErrorHandler = (int, string, string) -> void throws unknown

function resolveFlowScalar(scalar: Token, strict: bool, onError: ComposeErrorHandler) -> ResolvedScalar {
  let offset = scalar.offset;
  let type = scalar.type;
  let source = tsrc(scalar);
  let end = scalar.end;
  let _type = "";
  let value = "";
  let _onError = (rel: int, code: string, msg: string) -> void {
    onError(offset + rel, code, msg, false);
  };
  match (type) {
    "scalar" => {
      _type = Scalar.PLAIN();
      value = plainValue(source, _onError);
    },
    "single-quoted-scalar" => {
      _type = Scalar.QUOTE_SINGLE();
      value = singleQuotedValue(source, _onError);
    },
    "double-quoted-scalar" => {
      _type = Scalar.QUOTE_DOUBLE();
      value = doubleQuotedValue(source, _onError);
    },
    /* istanbul ignore next should not happen */
    _ => {
      onError(scalar, "UNEXPECTED_TOKEN", "Expected a flow scalar value, but found: " + type, false);
      return ResolvedScalar {
        value: "",
        type: null,
        comment: "",
        range: [offset, offset + source.length(), offset + source.length()],
      };
    },
  }

  let valueEnd = offset + source.length();
  let re_ = resolveEnd(end, valueEnd, strict, onError);
  ResolvedScalar {
    value: value,
    type: _type,
    comment: re_.comment,
    range: [offset, valueEnd, re_.offset],
  }
}

function plainValue(source: string, onError: FlowScalarErrorHandler) -> string {
  let badChar = "";
  let c0 = source.at(0) ?? "";
  match (c0) {
    /* istanbul ignore next should not happen */
    "\t" => {
      badChar = "a tab character";
    },
    "," => {
      badChar = "flow indicator character ,";
    },
    "%" => {
      badChar = "directive indicator character %";
    },
    "|" => {
      badChar = "block scalar indicator " + c0;
    },
    ">" => {
      badChar = "block scalar indicator " + c0;
    },
    "@" => {
      badChar = "reserved character " + c0;
    },
    "`" => {
      badChar = "reserved character " + c0;
    },
    _ => {},
  }
  if (badChar != "") {
    onError(0, "BAD_SCALAR_START", "Plain value cannot start with " + badChar);
  }
  foldLines(source)
}

function singleQuotedValue(source: string, onError: FlowScalarErrorHandler) -> string {
  if (source.at(source.length() - 1) != "'" || source.length() == 1) {
    onError(source.length(), "MISSING_CHAR", "Missing closing 'quote");
  }
  foldLines(source.slice(1, source.length() - 1)).replace_all("''", "'")
}

function foldLines(source0: string) -> string {
  let s = src(source0);
  let newLineIndex = s.index_of_char("\n", 0);
  if (newLineIndex == -1) {
    return source0;
  }

  // This finds the index in the first line of the last non-space/non-tab char
  let end = newLineIndex;
  let cc = s.code(end - 1);
  if (cc == 13) {
    end -= 1;
    cc = s.code(end - 1);
  }
  while (end > 0 && (cc == 32 || cc == 9)) {
    end -= 1;
    cc = s.code(end - 1);
  }
  let res = s.slice(0, end);

  let sep = " ";
  let pos = newLineIndex + 1;

  // now we go through each line, find the first non-space/tab char.
  // then find the last non-space/tab char.
  // the slice between those is added to the result with a separator
  newLineIndex = s.index_of_char("\n", pos);
  while (newLineIndex != -1) {
    let start = pos;
    cc = s.code(start);
    while (start < newLineIndex && (cc == 32 || cc == 9)) {
      start += 1;
      cc = s.code(start);
    }
    end = newLineIndex;
    cc = s.code(end - 1);
    if (cc == 13) {
      end -= 1;
      cc = s.code(end - 1);
    }
    while (end > start && (cc == 32 || cc == 9)) {
      end -= 1;
      cc = s.code(end - 1);
    }

    if (start == end) {
      if (sep == "\n") {
        res += sep;
      } else {
        sep = "\n";
      }
    } else {
      res += sep + s.slice(start, end);
      sep = " ";
    }
    pos = newLineIndex + 1;
    newLineIndex = s.index_of_char("\n", pos);
  }

  // finally we find the first non-space/tab char in the last line and
  // add the rest to the result
  let start = pos;
  cc = s.code(start);
  while (start < s.len() && (cc == 32 || cc == 9)) {
    start += 1;
    cc = s.code(start);
  }
  res + sep + s.slice(start, s.len())
}

function doubleQuotedValue(source0: string, onError: FlowScalarErrorHandler) -> string {
  let s = src(source0);
  let res = "";
  let i = 1;
  while (i < s.len() - 1) {
    let ch = s.ch(i) ?? "";
    if (ch == "\r" && s.ch(i + 1) == "\n") {
      i += 1;
      continue;
    }
    if (ch == "\n") {
      let fo = foldNewline(s, i);
      res += fo.fold;
      i = fo.offset;
    } else if (ch == "\\") {
      i += 1;
      let next = s.ch(i);
      let cc = escapeCodes(next ?? "");
      if (cc != null) {
        res += cc;
      } else if (next == "\n") {
        // skip escaped newlines, but still trim the following line
        next = s.ch(i + 1);
        while (next == " " || next == "\t") {
          i += 1;
          next = s.ch(i + 1);
        }
      } else if (next == "\r" && s.ch(i + 1) == "\n") {
        // skip escaped CRLF newlines, but still trim the following line
        i += 1;
        next = s.ch(i + 1);
        while (next == " " || next == "\t") {
          i += 1;
          next = s.ch(i + 1);
        }
      } else if (next == "x" || next == "u" || next == "U") {
        let length = if (next == "x") { 2 } else if (next == "u") { 4 } else { 8 };
        let pc = parseCharCode(s, i + 1, length, onError);
        res += pc.str;
        i += length + pc.extra;
      } else {
        let raw = s.slice(i - 1, i + 1);
        onError(i - 1, "BAD_DQ_ESCAPE", "Invalid escape sequence " + raw);
        res += raw;
      }
    } else if (ch == " " || ch == "\t") {
      // trim trailing whitespace
      let wsStart = i;
      let next = s.ch(i + 1);
      while (next == " " || next == "\t") {
        i += 1;
        next = s.ch(i + 1);
      }
      if (next != "\n" && !(next == "\r" && s.ch(i + 2) == "\n")) {
        res += if (i > wsStart) { s.slice(wsStart, i + 1) } else { ch };
      }
    } else {
      res += ch;
    }
    i += 1;
  }
  if (s.ch(s.len() - 1) != "\"" || s.len() == 1) {
    onError(s.len(), "MISSING_CHAR", "Missing closing \"quote");
  }
  res
}

class FoldResult {
  fold: string
  offset: int
}

function foldNewline(source: Src, offset0: int) -> FoldResult {
  let offset = offset0;
  let fold = "";
  let ch = source.ch(offset + 1);
  while (ch == " " || ch == "\t" || ch == "\n" || ch == "\r") {
    if (ch == "\r" && source.ch(offset + 2) != "\n") {
      break;
    }
    if (ch == "\n") {
      fold += "\n";
    }
    offset += 1;
    ch = source.ch(offset + 1);
  }
  if (fold == "") {
    fold = " ";
  }
  FoldResult { fold: fold, offset: offset }
}

function escapeCodes(c: string) -> string? {
  match (c) {
    "0" => "\0", // null character
    "a" => chr(7), // bell character
    "b" => "\b", // backspace
    "e" => chr(0x1b), // escape character
    "f" => "\f", // form feed
    "n" => "\n", // line feed
    "r" => "\r", // carriage return
    "t" => "\t", // horizontal tab
    "v" => "\v", // vertical tab
    "N" => chr(0x85), // Unicode next line
    "_" => chr(0xa0), // Unicode non-breaking space
    "L" => chr(0x2028), // Unicode line separator
    "P" => chr(0x2029), // Unicode paragraph separator
    " " => " ",
    "\"" => "\"",
    "/" => "/",
    "\\" => "\\",
    "\t" => "\t",
    _ => null,
  }
}

class CharCodeResult {
  str: string
  /// Extra source characters consumed (for a `\uD8xx\uDCxx` surrogate pair)
  extra: int
}

/// JS `String.fromCodePoint(code)` accepts lone surrogates (producing an
/// ill-formed UTF-16 string), and JS strings joined from a high + low
/// surrogate escape form one character. BAML strings are UTF-8, so a
/// `😀` pair is decoded here as one code point; a lone surrogate
/// is reported as an invalid escape.
function parseCharCode(source: Src, offset: int, length: int, onError: FlowScalarErrorHandler) -> CharCodeResult {
  let cc = source.slice(offset, offset + length);
  let ok = cc.length() == length && re("^[0-9a-fA-F]+$").has_match(cc);
  let code = if (ok) { js_int(js_parse_int(cc, 16)) } else { -1 };
  if (code >= 0xd800 && code <= 0xdbff && length == 4 && source.ch(offset + 4) == "\\" && source.ch(offset + 5) == "u") {
    let lo_s = source.slice(offset + 6, offset + 10);
    if (re("^[0-9a-fA-F]{4}$").has_match(lo_s)) {
      let lo = js_int(js_parse_int(lo_s, 16));
      if (lo >= 0xdc00 && lo <= 0xdfff) {
        let cp = 0x10000 + (code - 0xd800) * 0x400 + (lo - 0xdc00);
        let s2 = baml.String.from_code_points([cp]) catch (e) { _ => "" };
        return CharCodeResult { str: s2, extra: 6 };
      }
    }
  }
  let s = if (code < 0) {
    null
  } else {
    baml.String.from_code_points([code]) catch (e) { _ => null }
  };
  if (s == null) {
    let raw = source.slice(offset - 2, offset + length);
    onError(offset - 2, "BAD_DQ_ESCAPE", "Invalid escape sequence " + raw);
    return CharCodeResult { str: raw, extra: 0 };
  }
  CharCodeResult { str: s ?? "", extra: 0 }
}
