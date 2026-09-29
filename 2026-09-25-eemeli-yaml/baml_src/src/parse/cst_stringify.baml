// Port of src/parse/cst-stringify.ts

/// Stringify a CST document, token, or collection item
function cst_stringify(cst: Token | CollectionItem) -> string {
  match (cst) {
    let t: Token => cst_stringify_token(t),
    let i: CollectionItem => cst_stringify_item(i.start, i.key, i.sep, i.value),
  }
}

function cst_stringify_token(token: Token) -> string {
  match (token.type) {
    "block-scalar" => {
      let res = "";
      for (let tok in tprops(token)) {
        res += cst_stringify_token(tok);
      }
      res + tsrc(token)
    },
    "block-map" => cst_stringify_items(token),
    "block-seq" => cst_stringify_items(token),
    "flow-collection" => {
      let fs = token.fcStart;
      let res = if (fs != null) { tsrc(fs) } else { "" };
      for (let item in titems(token)) {
        res += cst_stringify_item(item.start, item.key, item.sep, item.value);
      }
      for (let st in tend(token)) {
        res += tsrc(st);
      }
      res
    },
    "document" => {
      let res = cst_stringify_item(tstart(token), null, null, token.value);
      for (let st in tend(token)) {
        res += tsrc(st);
      }
      res
    },
    _ => {
      let res = tsrc(token);
      for (let st in tend(token)) {
        res += tsrc(st);
      }
      res
    },
  }
}

function cst_stringify_items(token: Token) -> string {
  let res = "";
  for (let item in titems(token)) {
    res += cst_stringify_item(item.start, item.key, item.sep, item.value);
  }
  res
}

function cst_stringify_item(start: Token[], key: Token?, sep: Token[]?, value: Token?) -> string {
  let res = "";
  for (let st in start) {
    res += tsrc(st);
  }
  if (key != null) {
    res += cst_stringify_token(key);
  }
  if (sep != null) {
    for (let st in sep) {
      res += tsrc(st);
    }
  }
  if (value != null) {
    res += cst_stringify_token(value);
  }
  res
}
