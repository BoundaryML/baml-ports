// Port of src/stringify/foldFlowLines.ts

function FOLD_FLOW() -> string {
  "flow"
}

function FOLD_BLOCK() -> string {
  "block"
}

function FOLD_QUOTED() -> string {
  "quoted"
}

/// `'block'` prevents more-indented lines from being folded;
/// `'quoted'` allows for `\` escapes, including escaped newlines
type FoldMode = string

class FoldOptions {
  /// Accounts for leading contents on the first line, defaulting to
  /// `indent.length`
  indentAtStart: int?
  /// Default: `80`
  lineWidth: int?
  /// Allow highly indented lines to stretch the line width or indent content
  /// from the start.
  ///
  /// Default: `20`
  minContentWidth: int?
  /// Called once if the text is folded
  onFold: (() -> void throws never)?
  /// Called once if any line of text exceeds lineWidth characters
  onOverflow: (() -> void throws never)?
}

/// Tries to keep input at up to `lineWidth` characters, splitting only on
/// spaces not followed by newlines or spaces unless `mode` is `'quoted'`.
/// Lines are terminated with `\n` and started with `indent`.
function foldFlowLines(text: string, indent: string, mode: string, opts: FoldOptions?) -> string {
  let indentAtStart = opts?.indentAtStart;
  let lineWidth = opts?.lineWidth ?? 80;
  let minContentWidth = opts?.minContentWidth ?? 20;
  let onFold = opts?.onFold;
  let onOverflow = opts?.onOverflow;
  if (lineWidth == 0 || lineWidth < 0) {
    return text;
  }
  if (lineWidth < minContentWidth) {
    minContentWidth = 0;
  }
  let es1 = 1 + minContentWidth;
  let es2 = 1 + lineWidth - indent.length();
  let endStep = if (es1 > es2) { es1 } else { es2 };
  let t = src(text);
  if (t.len() <= endStep) {
    return text;
  }
  let folds: int[] = [];
  let escapedFolds: map<string, bool> = {};
  let end = lineWidth - indent.length();
  if (indentAtStart != null) {
    let m = if (minContentWidth > 2) { minContentWidth } else { 2 };
    if (indentAtStart > lineWidth - m) {
      folds.push(0);
    } else {
      end = lineWidth - indentAtStart;
    }
  }
  let split: int? = null;
  let prev: string? = null;
  let overflow = false;
  let i = -1;
  let escStart = -1;
  let escEnd = -1;
  if (mode == FOLD_BLOCK()) {
    i = consumeMoreIndentedLines(t, i, indent.length());
    if (i != -1) {
      end = i + endStep;
    }
  }
  i += 1;
  let ch = t.ch(i);
  while (ch != null && ch != "") {
    if (mode == FOLD_QUOTED() && ch == "\\") {
      escStart = i;
      match (t.ch(i + 1)) {
        "x" => {
          i += 3;
        },
        "u" => {
          i += 5;
        },
        "U" => {
          i += 9;
        },
        _ => {
          i += 1;
        },
      }
      escEnd = i;
    }
    if (ch == "\n") {
      if (mode == FOLD_BLOCK()) {
        i = consumeMoreIndentedLines(t, i, indent.length());
      }
      end = i + indent.length() + endStep;
      split = null;
    } else {
      if (ch == " " && prev != null && prev != " " && prev != "\n" && prev != "\t") {
        // space surrounded by non-space can be replaced with newline + indent
        let next = t.ch(i + 1);
        if (next != null && next != " " && next != "\n" && next != "\t") {
          split = i;
        }
      }
      if (i >= end) {
        let sp = split;
        if (sp != null && sp != 0) {
          folds.push(sp);
          end = sp + endStep;
          split = null;
        } else if (mode == FOLD_QUOTED()) {
          // white-space collected at end may stretch past lineWidth
          while (prev == " " || prev == "\t") {
            prev = ch;
            i += 1;
            ch = t.ch(i);
            overflow = true;
          }
          // Account for newline escape, but don't break preceding escape
          let j = if (i > escEnd + 1) { i - 2 } else { escStart - 1 };
          // Bail out if lineWidth & minContentWidth are shorter than an escape string
          if (escapedFolds.has(j.to_string())) {
            return text;
          }
          folds.push(j);
          escapedFolds.set(j.to_string(), true);
          end = j + endStep;
          split = null;
        } else {
          overflow = true;
        }
      }
    }
    prev = ch;
    i += 1;
    ch = t.ch(i);
  }
  if (overflow && onOverflow != null) {
    onOverflow();
  }
  if (folds.length() == 0) {
    return text;
  }
  if (onFold != null) {
    onFold();
  }
  let res = t.slice(0, folds[0]);
  let k = 0;
  while (k < folds.length()) {
    let fold = folds[k];
    let nf = folds.at(k + 1) ?? 0;
    let fend = if (nf != 0) { nf } else { t.len() };
    if (fold == 0) {
      res = "\n" + indent + t.slice(0, fend);
    } else {
      if (mode == FOLD_QUOTED() && escapedFolds.has(fold.to_string())) {
        res += (t.ch(fold) ?? "") + "\\";
      }
      res += "\n" + indent + t.slice(fold + 1, fend);
    }
    k += 1;
  }
  res
}

/// Presumes `i + 1` is at the start of a line
/// @returns index of last newline in more-indented block
function consumeMoreIndentedLines(text: Src, i0: int, indent: int) -> int {
  let i = i0;
  let end = i;
  let start = i + 1;
  let ch = text.ch(start);
  while (ch == " " || ch == "\t") {
    if (i < start + indent) {
      i += 1;
      ch = text.ch(i);
    } else {
      let go = true;
      while (go) {
        i += 1;
        ch = text.ch(i);
        go = ch != null && ch != "\n";
      }
      end = i;
      start = i + 1;
      ch = text.ch(start);
    }
  }
  end
}
