// Port of src/schema/yaml-1.1/merge.ts
//
// If the value associated with a merge key is a single mapping node, each of
// its key/value pairs is inserted into the current mapping, unless the key
// already exists in it. If the value associated with the merge key is a
// sequence, then this sequence is expected to contain mapping nodes and each
// of these nodes is merged in turn according to its order in the sequence.
// Keys in mapping nodes earlier in the sequence override keys specified in
// later mapping nodes. -- http://yaml.org/type/merge.html

function MERGE_KEY() -> string {
  "<<"
}

function merge_tag() -> Tag {
  Tag {
    _id: 28,
    identify: (value: unknown) -> bool {
      match (value) {
        let s: JsSymbol => s.description == MERGE_KEY(),
        _ => false,
      }
    },
    default: "key",
    tag: "tag:yaml.org,2002:merge",
    testFn: (str: string) -> bool { str == MERGE_KEY() },
    resolve: (str: string, onError: TagOnError, opts: Options) -> unknown { MergeKey() },
    stringify: (node: Scalar, ctx: StringifyContext, onComment: Callback?, onChompKeep: Callback?) -> string { MERGE_KEY() },
  }
}

/// `new MergeKey()` (`class MergeKey extends Scalar<symbol>`)
function MergeKey() -> Scalar {
  let s = Scalar.new(js_symbol(MERGE_KEY()));
  s._class = "MergeKey";
  s.addToJSMap = merge_addToJSMap;
  s
}

function merge_addToJSMap(doc: Document?, ctx: ToJSContext, map_: MapLike, value: unknown) -> void {
  let source = getMergeSource(doc, ctx, value);
  match (source) {
    let seq: YAMLSeq => {
      for (let v in seq.items) {
        let s = getMergeSource(doc, ctx, v);
        mergeValue(doc, ctx, map_, s);
      }
    },
    _ => {
      mergeValue(doc, ctx, map_, source);
    },
  }
}

function mergeValue(doc: Document?, ctx: ToJSContext, map_: MapLike, source: unknown) -> MapLike {
  let srcNode = match (source) {
    let m: YAMLMap => m,
    _ => {
      throw js_error("Merge sources must be maps or map aliases");
    },
  };
  let srcMap = srcNode.toJS(doc, ctx);
  let entries = js_entries(srcMap) ?? JsEntries { keys: [], values: [] };
  let i = 0;
  while (i < entries.keys.length()) {
    let key = entries.keys[i];
    let value = entries.values[i];
    let reviverSource = ctx.reviverSources?.get(srcMap)?.get(key);
    match (map_) {
      let m: JsMap<unknown> => {
        if (!m.has(key)) {
          m.set(key, value);
          ctx.setSource(m, key, reviverSource);
        }
      },
      let o: map<string, unknown> => {
        let sk = js_string(key);
        if (!o.has(sk)) {
          o.set(sk, value);
          ctx.setSource(o, sk, reviverSource);
        }
      },
    }
    i += 1;
  }
  map_
}

function getMergeSource(doc: Document?, ctx: ToJSContext, value: unknown) -> unknown {
  let a = match (value) {
    let a: Alias => a,
    _ => {
      return value;
    },
  };
  if (doc == null) {
    throw js_type_error("A document argument is required");
  }
  let source = a.resolve(doc, ctx);
  if (source == null) {
    let msg = "Unresolved alias (the anchor must be set before the alias): " + a.source;
    throw js_reference_error(msg);
  }

  ctx.resolveAlias(doc, source);
  source
}
