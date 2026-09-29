// Port of src/stringify/stringifyString.ts

/// `{ value: string; comment?: string | null; type?: string }`
class StringifyScalar {
  value: string
  comment: string?
  type: string?
}

function getFoldOptions(ctx: StringifyContext, isBlock: bool) -> FoldOptions {
  FoldOptions {
    indentAtStart: if (isBlock) { ctx.indent.length() } else { ctx.indentAtStart },
    lineWidth: ctx.options.lineWidth,
    minContentWidth: ctx.options.minContentWidth,
  }
}

/// Also checks for lines starting with %, as parsing the output as YAML 1.1
/// will presume that's starting a new document.
function containsDocumentMarker(str: string) -> bool {
  re("(?m)^(%|---|\\.\\.\\.)").has_match(str)
}

function lineLengthOverLimit(str: string, lineWidth: int, indentLength: int) -> bool {
  if (lineWidth == 0 || lineWidth < 0) {
    return false;
  }
  let limit = lineWidth - indentLength;
  let chars = str.chars();
  let strLen = chars.length();
  if (strLen <= limit) {
    return false;
  }
  let i = 0;
  let start = 0;
  while (i < strLen) {
    if (chars[i] == "\n") {
      if (i - start > limit) {
        return true;
      }
      start = i + 1;
      if (strLen - start <= limit) {
        return false;
      }
    }
    i += 1;
  }
  true
}

function doubleQuotedString(value: string, ctx: StringifyContext) -> string {
  let json = json_quote(value);
  if (ctx.options.doubleQuotedAsJSON) {
    return json;
  }

  let implicitKey = ctx.implicitKey ?? false;
  let minMultiLineLength = ctx.options.doubleQuotedMinMultiLineLength;
  let indent = if (ctx.indent != "") { ctx.indent } else if (containsDocumentMarker(value)) { "  " } else { "" };
  let j = src(json);
  let str = "";
  let start = 0;
  let i = 0;
  let ch = j.ch(i);
  while (ch != null && ch != "") {
    if (ch == " " && j.ch(i + 1) == "\\" && j.ch(i + 2) == "n") {
      // space before newline needs to be escaped to not be folded
      str += j.slice(start, i) + "\\ ";
      i += 1;
      start = i;
      ch = "\\";
    }
    if (ch == "\\") {
      match (j.ch(i + 1)) {
        "u" => {
          str += j.slice(start, i);
          let code = j.slice(i + 2, i + 6);
          match (code) {
            "0000" => {
              str += "\\0";
            },
            "0007" => {
              str += "\\a";
            },
            "000b" => {
              str += "\\v";
            },
            "001b" => {
              str += "\\e";
            },
            "0085" => {
              str += "\\N";
            },
            "00a0" => {
              str += "\\_";
            },
            "2028" => {
              str += "\\L";
            },
            "2029" => {
              str += "\\P";
            },
            _ => {
              if (code.slice(0, 2) == "00") {
                str += "\\x" + code.slice(2, 4);
              } else {
                str += j.slice(i, i + 6);
              }
            },
          }
          i += 5;
          start = i + 1;
        },
        "n" => {
          if (implicitKey || j.ch(i + 2) == "\"" || j.len() < minMultiLineLength) {
            i += 1;
          } else {
            // folding will eat first newline
            str += j.slice(start, i) + "\n\n";
            while (j.ch(i + 2) == "\\" && j.ch(i + 3) == "n" && j.ch(i + 4) != "\"") {
              str += "\n";
              i += 2;
            }
            str += indent;
            // space after newline needs to be escaped to not be folded
            if (j.ch(i + 2) == " ") {
              str += "\\";
            }
            i += 1;
            start = i + 1;
          }
        },
        _ => {
          i += 1;
        },
      }
    }
    i += 1;
    ch = j.ch(i);
  }
  str = if (start != 0) { str + j.slice(start, j.len()) } else { json };
  if (implicitKey) {
    str
  } else {
    foldFlowLines(str, indent, FOLD_QUOTED(), getFoldOptions(ctx, false))
  }
}

function singleQuotedString(value: string, ctx: StringifyContext) -> string {
  if (
    ctx.options.singleQuote == false ||
    ((ctx.implicitKey ?? false) && value.includes("\n")) ||
    re("[ \\t]\\n|\\n[ \\t]").has_match(value) // single quoted string can't have leading or trailing whitespace around newline
  ) {
    return doubleQuotedString(value, ctx);
  }

  let indent = if (ctx.indent != "") { ctx.indent } else if (containsDocumentMarker(value)) { "  " } else { "" };
  let res = "'" + value.replace_all("'", "''").replace_all(re("\\n+"), "${0}\n" + indent) + "'";
  if (ctx.implicitKey ?? false) {
    res
  } else {
    foldFlowLines(res, indent, FOLD_FLOW(), getFoldOptions(ctx, false))
  }
}

function quotedString(value: string, ctx: StringifyContext) -> string {
  let singleQuote = ctx.options.singleQuote;
  let useSingle = false;
  if (singleQuote == false) {
    useSingle = false;
  } else {
    let hasDouble = value.includes("\"");
    let hasSingle = value.includes("'");
    if (hasDouble && !hasSingle) {
      useSingle = true;
    } else if (hasSingle && !hasDouble) {
      useSingle = false;
    } else {
      useSingle = singleQuote ?? false;
    }
  }
  if (useSingle) {
    singleQuotedString(value, ctx)
  } else {
    doubleQuotedString(value, ctx)
  }
}

/// The negative lookbehind avoids a polynomial search,
/// but isn't supported yet on Safari: https://caniuse.com/js-regexp-lookbehind
function blockEndNewlines() -> baml.regex.Regex {
  re("(^|(?<!\\n))\\n+(?!\\n|$)")
}

function blockString(item: StringifyScalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string {
  let comment = item.comment;
  let type = item.type;
  let value = item.value;
  let blockQuote = ctx.options.blockQuote;
  let commentString = ctx.options.commentString;
  let lineWidth = ctx.options.lineWidth;
  // 1. Block can't end in whitespace unless the last line is non-empty.
  // 2. Strings consisting of only whitespace are best rendered explicitly.
  if (blockQuote == false || re("\\n[\\t ]+$").has_match(value)) {
    return quotedString(value, ctx);
  }

  let indent = if (ctx.indent != "") {
    ctx.indent
  } else if ((ctx.forceBlockIndent ?? false) || containsDocumentMarker(value)) {
    "  "
  } else {
    ""
  };
  let literal = if (blockQuote == "literal") {
    true
  } else if (blockQuote == "folded" || type == Scalar.BLOCK_FOLDED()) {
    false
  } else if (type == Scalar.BLOCK_LITERAL()) {
    true
  } else {
    !lineLengthOverLimit(value, lineWidth, indent.length())
  };
  if (value == "") {
    return if (literal) { "|\n" } else { ">\n" };
  }

  // determine chomping from whitespace at value end
  let chomp = "";
  let vs = src(value);
  let endStart = vs.len();
  while (endStart > 0) {
    let ch = vs.ch(endStart - 1);
    if (ch != "\n" && ch != "\t" && ch != " ") {
      break;
    }
    endStart -= 1;
  }
  let end = vs.slice(endStart, vs.len());
  let endNlPos = end.index_of("\n") ?? -1;
  if (endNlPos == -1) {
    chomp = "-"; // strip
  } else if (value == end || endNlPos != end.length() - 1) {
    chomp = "+"; // keep
    if (onChompKeep != null) {
      onChompKeep();
    }
  } else {
    chomp = ""; // clip
  }
  if (end != "") {
    value = vs.slice(0, vs.len() - end.length());
    if (end.at(end.length() - 1) == "\n") {
      end = end.slice(0, end.length() - 1);
    }
    end = end.replace_all(blockEndNewlines(), "${0}" + indent);
  }

  // determine indent indicator from whitespace at value start
  let startWithSpace = false;
  let startEnd = 0;
  let startNlPos = -1;
  let vs2 = src(value);
  while (startEnd < vs2.len()) {
    let ch = vs2.ch(startEnd);
    if (ch == " ") {
      startWithSpace = true;
    } else if (ch == "\n") {
      startNlPos = startEnd;
    } else {
      break;
    }
    startEnd += 1;
  }
  let start = vs2.slice(0, if (startNlPos < startEnd) { startNlPos + 1 } else { startEnd });
  if (start != "") {
    value = vs2.slice(start.length(), vs2.len());
    start = start.replace_all(re("\\n+"), "${0}" + indent);
  }

  let indentSize = if (indent != "") { "2" } else { "1" }; // root is at -1
  // Leading | or > is added later
  let header = (if (startWithSpace) { indentSize } else { "" }) + chomp;
  if (comment != null && comment != "") {
    header += " " + commentString(comment.replace_all(re(" ?[\\r\\n]+"), " "));
    if (onComment != null) {
      onComment();
    }
  }

  if (!literal) {
    let foldedValue = value
      .replace_all(re("\\n+"), "\n${0}")
      .replace_all(re("(?:^|\\n)([\\t ].*)(?:([\\n\\t ]*)\\n(?![\\n\\t ]))?"), "${1}${2}") // more-indented lines aren't folded
      //                ^ more-ind. ^ empty     ^ capture next empty lines only at end of indent
      .replace_all(re("\\n+"), "${0}" + indent);
    let literalFallback = false;
    let foldOptions = getFoldOptions(ctx, true);
    if (blockQuote != "folded" && type != Scalar.BLOCK_FOLDED()) {
      foldOptions.onOverflow = () -> void {
        literalFallback = true;
      };
    }
    let body = foldFlowLines(start + foldedValue + end, indent, FOLD_BLOCK(), foldOptions);
    if (!literalFallback) {
      return ">" + header + "\n" + indent + body;
    }
  }

  value = value.replace_all(re("\\n+"), "${0}" + indent);
  "|" + header + "\n" + indent + start + value + end
}

function plainString(item: StringifyScalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string {
  let type = item.type;
  let value = item.value;
  let actualString = ctx.actualString ?? false;
  let implicitKey = ctx.implicitKey ?? false;
  let indent = ctx.indent;
  let indentStep = ctx.indentStep;
  let inFlow = ctx.inFlow ?? false;
  if ((implicitKey && value.includes("\n")) || (inFlow && re("[\\[\\]{},]").has_match(value))) {
    return quotedString(value, ctx);
  }
  if (re("^[\\n\\t ,\\[\\]{}#&*!|>'\"%@`]|^[?-]$|^[?-][ \\t]|[\\n:][ \\t]|[ \\t]\\n|[\\n\\t ]#|[\\n\\t :]$").has_match(value)) {
    // not allowed:
    // - '-' or '?'
    // - start with an indicator character (except [?:-]) or /[?-] /
    // - '\n ', ': ' or ' \n' anywhere
    // - '#' not preceded by a non-space char
    // - end with ' ' or ':'
    return if (implicitKey || inFlow || !value.includes("\n")) {
      quotedString(value, ctx)
    } else {
      blockString(item, ctx, onComment, onChompKeep)
    };
  }
  if (!implicitKey && !inFlow && type != Scalar.PLAIN() && value.includes("\n")) {
    // Where allowed & type not set explicitly, prefer block style for multiline strings
    return blockString(item, ctx, onComment, onChompKeep);
  }
  if (containsDocumentMarker(value)) {
    if (indent == "") {
      ctx.forceBlockIndent = true;
      return blockString(item, ctx, onComment, onChompKeep);
    } else if (implicitKey && indent == indentStep) {
      return quotedString(value, ctx);
    }
  }
  let str = value.replace_all(re("\\n+"), "${0}\n" + indent);
  // Verify that output will be parsed as a string, as e.g. plain numbers and
  // booleans get parsed with those types in v1.2 (e.g. '42', 'true' & '0.9e-3'),
  // and others in v1.1.
  if (actualString) {
    let testTag = (tag: Tag) -> bool {
      let t = tag.testFn;
      if (t != null) {
        tag_default_truthy(tag) && tag.tag != "tag:yaml.org,2002:str" && t(str)
      } else {
        false
      }
    };
    let schema = ctx.doc.schema;
    let compat = schema.compat;
    if (schema.tags.some(testTag) || (compat?.some(testTag) ?? false)) {
      return quotedString(value, ctx);
    }
  }
  if (implicitKey) {
    str
  } else {
    foldFlowLines(str, indent, FOLD_FLOW(), getFoldOptions(ctx, false))
  }
}

function stringifyString(item: Scalar | StringifyScalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string {
  let implicitKey = ctx.implicitKey ?? false;
  let inFlow = ctx.inFlow ?? false;

  let ss = match (item) {
    let s: StringifyScalar => s,
    let sc: Scalar => {
      match (sc.value) {
        let v: string => StringifyScalar { value: v, comment: sc.comment, type: sc.type },
        // Raw JSON values are guaranteed to be valid JSON scalars,
        // and therefore also valid YAML scalars.
        let r: JsRawJSON => {
          return r.rawJSON;
        },
        _ => StringifyScalar { value: js_string(sc.value), comment: sc.comment, type: sc.type },
      }
    },
  };

  let type = ss.type;
  if (type != Scalar.QUOTE_DOUBLE()) {
    // force double quotes on control characters & unpaired surrogates
    // (BAML strings are valid UTF-8, so there are no unpaired surrogates)
    if (re("[\\x00-\\x08\\x0b-\\x1f\\x7f-\\x{9f}]").has_match(ss.value)) {
      type = Scalar.QUOTE_DOUBLE();
    }
  }

  let res = stringify_string_type(type, ss, ctx, onComment, onChompKeep, implicitKey, inFlow);
  if (res == null) {
    let defaultKeyType = ctx.options.defaultKeyType;
    let defaultStringType = ctx.options.defaultStringType;
    let t = if (implicitKey && defaultKeyType != null && defaultKeyType != "") { defaultKeyType } else { defaultStringType };
    res = stringify_string_type(t, ss, ctx, onComment, onChompKeep, implicitKey, inFlow);
    if (res == null) {
      throw js_error("Unsupported default string type " + (t ?? "undefined"));
    }
  }
  res ?? ""
}

/// The `_stringify(_type)` closure of `stringifyString`.
function stringify_string_type(
  type: string?,
  ss: StringifyScalar,
  ctx: StringifyContext,
  onComment: Callback?,
  onChompKeep: Callback?,
  implicitKey: bool,
  inFlow: bool,
) -> string? {
  match (type) {
    "BLOCK_FOLDED" => {
      if (implicitKey || inFlow) {
        quotedString(ss.value, ctx) // blocks are not valid inside flow containers
      } else {
        blockString(ss, ctx, onComment, onChompKeep)
      }
    },
    "BLOCK_LITERAL" => {
      if (implicitKey || inFlow) {
        quotedString(ss.value, ctx) // blocks are not valid inside flow containers
      } else {
        blockString(ss, ctx, onComment, onChompKeep)
      }
    },
    "QUOTE_DOUBLE" => doubleQuotedString(ss.value, ctx),
    "QUOTE_SINGLE" => singleQuotedString(ss.value, ctx),
    "PLAIN" => plainString(ss, ctx, onComment, onChompKeep),
    _ => null,
  }
}
