// Port of src/nodes/addPairToJSMap.ts

function addPairToJSMap(doc: Document?, ctx: ToJSContext, map_: MapLike, pair: Pair) -> null {
  let key = pair.key;
  let value = pair.value;
  let atj = match (key) {
    let s: Scalar => s.addToJSMap,
    _ => null,
  };
  if (atj != null) {
    atj(doc, ctx, map_, value);
    return null;
  }
  let jsKey = key.toJS(doc, ctx);
  let jsValue = if (value != null) { value.toJS(doc, ctx) } else { null };
  match (map_) {
    let m: JsMap<unknown> => {
      m.set(jsKey, jsValue);
      ctx.setSource(m, jsKey, value);
    },
    let o: map<string, unknown> => {
      let stringKey = stringifyKey(doc, ctx, key, jsKey);
      // `__proto__` / `constructor` need defineProperty in JS; a BAML map
      // has no prototype, so a plain set is equivalent.
      o.set(stringKey, jsValue);
      ctx.setSource(o, stringKey, value);
    },
  }
  null
}

function stringifyKey(doc: Document?, ctx: ToJSContext, key: Node, jsKey: unknown) -> string {
  if (jsKey == null) {
    return "";
  }
  if (js_typeof(jsKey) != "object") {
    return js_string(jsKey);
  }
  let d = doc ?? Document.new(null, null, null);
  let strCtx = createStringifyContext(d, null);
  for (let ad in ctx.anchors.values()) {
    let a = nb(ad.node).anchor;
    if (a != null) {
      strCtx.anchors.add(a);
    }
  }
  strCtx.inFlow = true;
  strCtx.inStringifyKey = true;
  let strKey = key.toString(strCtx, null, null);
  if (!ctx.mapKeyWarned) {
    let jsonStr = json_quote(strKey);
    if (jsonStr.length() > 40) {
      jsonStr = jsonStr.slice(0, 36) + "...\"";
    }
    let msg = "Keys with collection values will be stringified due to JS Object restrictions: " + jsonStr + ". Set mapAsMap: true to use a Map instead.";
    warn(d.options.logLevel ?? "warn", msg);
    ctx.mapKeyWarned = true;
  }
  strKey
}
