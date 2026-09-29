// Port of src/compose/util-empty-scalar-position.ts

function emptyScalarPosition(offset0: int, before: Token[]?, pos0: int?) -> int {
  let offset = offset0;
  if (before != null) {
    let pos = pos0 ?? before.length();
    let i = pos - 1;
    while (i >= 0) {
      let st = before[i];
      let t = st.type;
      if (t == "space" || t == "comment" || t == "newline") {
        offset -= tsrc(st).length();
        i -= 1;
        continue;
      }

      // Technically, an empty scalar is immediately after the last non-empty
      // node, but it's more useful to place it after any whitespace.
      i += 1;
      let st2 = before.at(i);
      while (st2?.type == "space") {
        offset += tsrc(st2 ?? st).length();
        i += 1;
        st2 = before.at(i);
      }
      break;
    }
  }
  offset
}
