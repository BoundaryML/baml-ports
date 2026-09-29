// Port of src/compose/resolve-end.ts

class ResolveEndResult {
  comment: string
  offset: int
}

function resolveEnd(end: Token[]?, offset0: int, reqSpace: bool, onError: ComposeErrorHandler) -> ResolveEndResult {
  let comment = "";
  let offset = offset0;
  if (end != null) {
    let hasSpace = false;
    let sep = "";
    for (let token in end) {
      let source = tsrc(token);
      let type = token.type;
      match (type) {
        "space" => {
          hasSpace = true;
        },
        "comment" => {
          if (reqSpace && !hasSpace) {
            onError(token, "MISSING_CHAR", "Comments must be separated from other tokens by white space characters", false);
          }
          let cb0 = str_from(source, 1);
          let cb = if (cb0 != "") { cb0 } else { " " };
          if (comment == "") {
            comment = cb;
          } else {
            comment += sep + cb;
          }
          sep = "";
        },
        "newline" => {
          if (comment != "") {
            sep += source;
          }
          hasSpace = true;
        },
        _ => {
          onError(token, "UNEXPECTED_TOKEN", "Unexpected " + type + " at node end", false);
        },
      }
      offset += source.length();
    }
  }
  ResolveEndResult { comment: comment, offset: offset }
}
