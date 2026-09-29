// Port of src/compose/util-contains-newline.ts

function containsNewline(key: Token?) -> bool? {
  if (key == null) {
    return null;
  }
  match (key.type) {
    "alias" => containsNewlineFlowScalar(key),
    "scalar" => containsNewlineFlowScalar(key),
    "double-quoted-scalar" => containsNewlineFlowScalar(key),
    "single-quoted-scalar" => containsNewlineFlowScalar(key),
    "flow-collection" => {
      for (let it in titems(key)) {
        for (let st in it.start) {
          if (st.type == "newline") {
            return true;
          }
        }
        let sep = it.sep;
        if (sep != null) {
          for (let st in sep) {
            if (st.type == "newline") {
              return true;
            }
          }
        }
        if ((containsNewline(it.key) ?? false) || (containsNewline(it.value) ?? false)) {
          return true;
        }
      }
      false
    },
    _ => true,
  }
}

function containsNewlineFlowScalar(key: Token) -> bool {
  if (tsrc(key).includes("\n")) {
    return true;
  }
  let end = key.end;
  if (end != null) {
    for (let st in end) {
      if (st.type == "newline") {
        return true;
      }
    }
  }
  false
}
