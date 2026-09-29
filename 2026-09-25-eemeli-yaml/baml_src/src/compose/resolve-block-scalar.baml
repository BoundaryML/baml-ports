// Port of src/compose/resolve-block-scalar.ts

class BlockScalarHeader {
  mode: string
  indent: int
  chomp: string
  comment: string
  length: int
}

function resolveBlockScalar(ctx: ComposeContext, scalar: Token, onError: ComposeErrorHandler) -> ResolvedScalar {
  let start = scalar.offset;
  let header_ = parseBlockScalarHeader(scalar, ctx.options.strict ?? true, onError);
  if (header_ == null) {
    return ResolvedScalar { value: "", type: null, comment: "", range: [start, start, start] };
  }
  let header: BlockScalarHeader = header_;
  let type = if (header.mode == ">") { Scalar.BLOCK_FOLDED() } else { Scalar.BLOCK_LITERAL() };
  let ssrc = tsrc(scalar);
  let lines: string[][] = if (ssrc != "") { splitLines(ssrc) } else { [] };

  // determine the end of content & start of chomping
  let chompStart = lines.length();
  let i = lines.length() - 1;
  while (i >= 0) {
    let content = lines[i][1];
    if (content == "" || content == "\r") {
      chompStart = i;
    } else {
      break;
    }
    i -= 1;
  }

  // shortcut for empty contents
  if (chompStart == 0) {
    let value = if (header.chomp == "+" && lines.length() > 0) {
      "\n".repeat(if (lines.length() - 1 > 1) { lines.length() - 1 } else { 1 })
    } else {
      ""
    };
    let end = start + header.length;
    if (ssrc != "") {
      end += ssrc.length();
    }
    return ResolvedScalar { value: value, type: type, comment: header.comment, range: [start, end, end] };
  }

  // find the indentation level to trim from start
  let trimIndent = tindent(scalar) + header.indent;
  let offset = scalar.offset + header.length;
  let contentStart = 0;
  i = 0;
  while (i < chompStart) {
    let indent = lines[i][0];
    let content = lines[i][1];
    if (content == "" || content == "\r") {
      if (header.indent == 0 && indent.length() > trimIndent) {
        trimIndent = indent.length();
      }
    } else {
      if (indent.length() < trimIndent) {
        let message = "Block scalars with more-indented leading empty lines must use an explicit indentation indicator";
        onError(offset + indent.length(), "MISSING_CHAR", message, false);
      }
      if (header.indent == 0) {
        trimIndent = indent.length();
      }
      contentStart = i;
      if (trimIndent == 0 && !ctx.atRoot) {
        let message = "Block scalar values in collections must be indented";
        onError(offset, "BAD_INDENT", message, false);
      }
      break;
    }
    offset += indent.length() + content.length() + 1;
    i += 1;
  }

  // include trailing more-indented empty lines in content
  i = lines.length() - 1;
  while (i >= chompStart) {
    if (lines[i][0].length() > trimIndent) {
      chompStart = i + 1;
    }
    i -= 1;
  }

  let value = "";
  let sep = "";
  let prevMoreIndented = false;

  // leading whitespace is kept intact
  i = 0;
  while (i < contentStart) {
    value += str_from(lines[i][0], trimIndent) + "\n";
    i += 1;
  }

  i = contentStart;
  while (i < chompStart) {
    let indent = lines[i][0];
    let content = lines[i][1];
    offset += indent.length() + content.length() + 1;
    let crlf = content.at(content.length() - 1) == "\r";
    if (crlf) {
      content = content.slice(0, content.length() - 1);
    }

    /* istanbul ignore if already caught in lexer */
    if (content != "" && indent.length() < trimIndent) {
      let src_ = if (header.indent != 0) { "explicit indentation indicator" } else { "first line" };
      let message = "Block scalar lines must not be less indented than their " + src_;
      onError(offset - content.length() - (if (crlf) { 2 } else { 1 }), "BAD_INDENT", message, false);
      indent = "";
    }

    if (type == Scalar.BLOCK_LITERAL()) {
      value += sep + str_from(indent, trimIndent) + content;
      sep = "\n";
    } else if (indent.length() > trimIndent || content.at(0) == "\t") {
      // more-indented content within a folded block
      if (sep == " ") {
        sep = "\n";
      } else if (!prevMoreIndented && sep == "\n") {
        sep = "\n\n";
      }
      value += sep + str_from(indent, trimIndent) + content;
      sep = "\n";
      prevMoreIndented = true;
    } else if (content == "") {
      // empty line
      if (sep == "\n") {
        value += "\n";
      } else {
        sep = "\n";
      }
    } else {
      value += sep + content;
      sep = " ";
      prevMoreIndented = false;
    }
    i += 1;
  }

  match (header.chomp) {
    "-" => {},
    "+" => {
      i = chompStart;
      while (i < lines.length()) {
        value += "\n" + str_from(lines[i][0], trimIndent);
        i += 1;
      }
      if (value.at(value.length() - 1) != "\n") {
        value += "\n";
      }
    },
    _ => {
      value += "\n";
    },
  }

  let end = start + header.length + ssrc.length();
  ResolvedScalar { value: value, type: type, comment: header.comment, range: [start, end, end] }
}

function parseBlockScalarHeader(scalar: Token, strict: bool, onError: ComposeErrorHandler) -> BlockScalarHeader? {
  let offset = scalar.offset;
  let props = tprops(scalar);
  /* istanbul ignore if should not happen */
  if (props[0].type != "block-scalar-header") {
    onError(props[0], "IMPOSSIBLE", "Block scalar header not found", false);
    return null;
  }
  let source = tsrc(props[0]);
  let mode = source.at(0) ?? "|";
  let indent = 0;
  let chomp = "";
  let error = -1;
  let chars = source.chars();
  let i = 1;
  while (i < chars.length()) {
    let ch = chars[i];
    if (chomp == "" && (ch == "-" || ch == "+")) {
      chomp = ch;
    } else {
      let n = js_to_number(ch);
      if (indent == 0 && !n.is_nan() && n != 0.0) {
        indent = js_int(n);
      } else if (error == -1) {
        error = offset + i;
      }
    }
    i += 1;
  }
  if (error != -1) {
    onError(error, "UNEXPECTED_TOKEN", "Block scalar header includes extra characters: " + source, false);
  }
  let hasSpace = false;
  let comment = "";
  let length = source.length();
  i = 1;
  while (i < props.length()) {
    let token = props[i];
    match (token.type) {
      "space" => {
        hasSpace = true;
        length += tsrc(token).length();
      },
      "newline" => {
        length += tsrc(token).length();
      },
      "comment" => {
        if (strict && !hasSpace) {
          let message = "Comments must be separated from other tokens by white space characters";
          onError(token, "MISSING_CHAR", message, false);
        }
        length += tsrc(token).length();
        comment = str_from(tsrc(token), 1);
      },
      "error" => {
        onError(token, "UNEXPECTED_TOKEN", token.message ?? "", false);
        length += tsrc(token).length();
      },
      _ => {
        let message = "Unexpected token in block scalar header: " + token.type;
        onError(token, "UNEXPECTED_TOKEN", message, false);
        let ts = token.source;
        if (ts != null && ts != "") {
          length += ts.length();
        }
      },
    }
    i += 1;
  }
  BlockScalarHeader { mode: mode, indent: indent, chomp: chomp, comment: comment, length: length }
}

/// `source.split(/\n( *)/)` then pairs of [indent, content]
/// (`Regex.split` includes capture groups in its output, as JS does.)
function splitLines(source: string) -> string[][] {
  let parts = re("\\n( *)").split(source);
  let first = parts[0];
  let m = re("^( *)").match_once(first);
  let g1 = m?.groups?.at(1);
  let lead = if (g1 != null) { g1.text } else { "" };
  let line0: string[] = if (lead != "") { [lead, str_from(first, lead.length())] } else { ["", first] };
  let lines: string[][] = [line0];
  let i = 1;
  while (i < parts.length()) {
    lines.push([parts[i], parts.at(i + 1) ?? ""]);
    i += 2;
  }
  lines
}
