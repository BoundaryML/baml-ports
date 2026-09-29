// Port of src/errors.ts

/// `ErrorCode` string union:
/// 'ALIAS_PROPS' | 'BAD_ALIAS' | 'BAD_DIRECTIVE' | 'BAD_DQ_ESCAPE' | 'BAD_INDENT'
/// | 'BAD_PROP_ORDER' | 'BAD_SCALAR_START' | 'BLOCK_AS_IMPLICIT_KEY'
/// | 'BLOCK_IN_FLOW' | 'DUPLICATE_KEY' | 'IMPOSSIBLE' | 'KEY_OVER_1024_CHARS'
/// | 'MISSING_CHAR' | 'MULTILINE_IMPLICIT_KEY' | 'MULTIPLE_ANCHORS'
/// | 'MULTIPLE_DOCS' | 'MULTIPLE_TAGS' | 'NON_STRING_KEY' | 'RESOURCE_EXHAUSTION'
/// | 'TAB_AS_INDENT' | 'TAG_RESOLVE_FAILED' | 'UNEXPECTED_TOKEN'
/// | 'BAD_COLLECTION_TYPE'
type ErrorCode = string

/// `YAMLError extends Error`, with subclasses `YAMLParseError` and
/// `YAMLWarning` distinguished by `name` (BAML has no inheritance).
class YAMLError {
  name: string
  code: string
  message: string
  pos: int[]
  linePos: LinePos[]?
}

function YAMLParseError(pos: int[], code: string, message: string) -> YAMLError {
  YAMLError { name: "YAMLParseError", code: code, message: message, pos: pos }
}

function YAMLWarning(pos: int[], code: string, message: string) -> YAMLError {
  YAMLError { name: "YAMLWarning", code: code, message: message, pos: pos }
}

/// `prettifyError(src, lc)(error)`
function prettify_error(src_: string, lc: LineCounter, error: YAMLError) -> null {
  if (error.pos[0] == -1) {
    return null;
  }
  error.linePos = error.pos.map((pos: int) -> LinePos { lc.linePos(pos) });
  let lp = error.linePos ?? [];
  let line = lp[0].line;
  let col = lp[0].col;
  error.message += " at line " + line.to_string() + ", column " + col.to_string();

  let ci = col - 1;
  let ls = lc.lineStarts;
  let lineStr = src_.slice(ls.at(line - 1) ?? 0, ls.at(line) ?? src_.length())
    .replace(re("[\\n\\r]+$"), "");

  // Trim to max 80 chars, keeping col position near the middle
  if (ci >= 60 && lineStr.length() > 80) {
    let a = ci - 39;
    let b = lineStr.length() - 79;
    let trimStart = if (a < b) { a } else { b };
    lineStr = "…" + str_from(lineStr, trimStart);
    ci -= trimStart - 1;
  }
  if (lineStr.length() > 80) {
    lineStr = lineStr.slice(0, 79) + "…";
  }

  // Include previous line in context if pointing at line start
  if (line > 1 && re("^ *$").has_match(lineStr.slice(0, ci))) {
    // Regexp won't match if start is trimmed
    let prev = src_.slice(ls.at(line - 2) ?? 0, ls.at(line - 1) ?? src_.length());
    if (prev.length() > 80) {
      prev = prev.slice(0, 79) + "…\n";
    }
    lineStr = prev + lineStr;
  }

  if (re("[^ ]").has_match(lineStr)) {
    let count = 1;
    let end = lp.at(1);
    if (end != null) {
      if (end.line == line && end.col > col) {
        let a = end.col - col;
        let b = 80 - ci;
        let m = if (a < b) { a } else { b };
        count = if (m > 1) { m } else { 1 };
      }
    }
    let pointer = " ".repeat(ci) + "^".repeat(count);
    error.message += ":\n\n" + lineStr + "\n" + pointer + "\n";
  }
  null
}
