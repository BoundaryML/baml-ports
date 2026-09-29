// Port of src/schema/yaml-1.1/omap.ts
//
// `class YAMLOMap extends YAMLSeq<Pair>`: a YAMLSeq with
// `_class == "YAMLOMap"`. Its `push`/`set` overrides live in YAMLSeq.baml;
// `toJS` and the duplicate-key check of `toString` are here.

/// `new YAMLOMap(schema, elements?)`
function YAMLOMap(schema: Schema, elements: Pair[]?) -> YAMLSeq {
  let seq = YAMLSeq.new(schema, null);
  seq._class = "YAMLOMap";
  if (elements != null) {
    for (let p in elements) {
      seq.items.push(p);
    }
  }
  seq.tag = "tag:yaml.org,2002:omap";
  seq
}

function yamlOMap_toJS(om: YAMLSeq, doc: Document?, ctx: ToJSContext?) -> unknown throws unknown {
  if (ctx == null) {
    // `super.toJS(doc)`: plain array of pair objects
    let plain = YAMLSeq { ...om, _class: "YAMLSeq" };
    return plain.toJS(doc, null);
  }
  let map_ = js_map();
  if (om.anchor != null && om.anchor != "") {
    ctx.anchors.set(om, AnchorData { node: om, aliasCount: 0, count: 1, res: map_ });
  }
  for (let item in om.items) {
    match (item) {
      let pair: Pair => {
        let key = pair.key.toJS(doc, ctx);
        let pv = pair.value;
        let value = if (pv != null) { pv.toJS(doc, ctx) } else { null };
        if (map_.has(key)) {
          throw js_error("Ordered maps must not include duplicate keys");
        }
        map_.set(key, value);
        ctx.setSource(map_, key, pair.value);
      },
      _ => {},
    }
  }
  map_
}

function yamlOMap_checkKeys(om: YAMLSeq) -> null throws unknown {
  let keys = js_set();
  for (let pair in om.items) {
    let key = om.schema.mapKey(pair);
    if (keys.has(key)) {
      throw js_error("Ordered maps must not include duplicate keys");
    }
    keys.add(key);
  }
  null
}

function omap_tag() -> Tag {
  Tag {
    _id: 29,
    collection: "seq",
    identify: (value: unknown) -> bool {
      match (value) {
        JsMap<unknown> => true,
        _ => false,
      }
    },
    nodeClass: "YAMLOMap",
    default: false,
    tag: "tag:yaml.org,2002:omap",
    createNode: (nc: NodeCreator, iterable: unknown) -> Node {
      let pairs = createPairs(nc, iterable);
      let ps: Pair[] = [];
      for (let it in pairs.items) {
        match (it) {
          let p: Pair => {
            ps.push(p);
          },
          _ => {},
        }
      }
      YAMLOMap(nc.schema, ps)
    },
    resolveCollection: (seq: Node, onError: TagOnError, opts: Options) -> unknown {
      let pairs = resolvePairs(seq, onError);
      let seenKeys: unknown[] = [];
      let ps: Pair[] = [];
      match (pairs) {
        let s: YAMLSeq => {
          for (let it in s.items) {
            match (it) {
              let p: Pair => {
                ps.push(p);
                match (p.key) {
                  let k: Scalar => {
                    if (seenKeys.includes(k.value)) {
                      onError("Ordered maps must not include duplicate keys: " + js_string(k.value));
                    } else {
                      seenKeys.push(k.value);
                    }
                  },
                  _ => {},
                }
              },
              _ => {},
            }
          }
        },
        _ => {},
      }
      let schema = match (seq) {
        let s: YAMLSeq => s.schema,
        let m: YAMLMap => m.schema,
        let s: YAMLSet => s.schema,
        _ => Schema.new(Options {}),
      };
      // `Object.assign(new YAMLOMap(seq.schema), pairs)`: copies the pairs
      // and own props (range, etc.) onto the new node.
      let om = YAMLOMap(schema, ps);
      match (pairs) {
        let s: YAMLSeq => {
          om.range = s.range;
          om.comment = s.comment;
          om.commentBefore = s.commentBefore;
          om.flow = s.flow;
          om.spaceBefore = s.spaceBefore;
          om.srcToken = s.srcToken;
          om.anchor = s.anchor;
        },
        _ => {},
      }
      om
    },
  }
}
