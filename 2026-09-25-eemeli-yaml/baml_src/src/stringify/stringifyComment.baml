// Port of src/stringify/stringifyComment.ts

/// Stringifies a comment.
///
/// Empty comment lines are left empty,
/// lines consisting of a single space are replaced by `#`,
/// and all other lines are prefixed with a `#`.
function stringifyComment(str: string) -> string {
  str.replace_all(re("(?m)^(?!$)(?: $)?"), "#")
}

function indentComment(comment: string, indent: string) -> string {
  if (re("^\\n+$").has_match(comment)) {
    return str_from(comment, 1);
  }
  if (indent != "") {
    comment.replace_all(re("(?m)^(?! *$)"), indent.replace_all("$", "$$"))
  } else {
    comment
  }
}

function lineComment(str: string, indent: string, comment: string) -> string {
  if (str.ends_with("\n")) {
    indentComment(comment, indent)
  } else if (comment.includes("\n")) {
    "\n" + indentComment(comment, indent)
  } else {
    (if (str.ends_with(" ")) { "" } else { " " }) + comment
  }
}
