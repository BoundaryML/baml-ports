// Port of src/schema/yaml-1.1/pairs.ts

function resolvePairs(seq: Node, onError: TagOnError) -> Node throws unknown {
  match (seq) {
    let s: YAMLSeq => {
      let i = 0;
      while (i < s.items.length()) {
        let item = s.items[i];
        match (item) {
          Pair => {},
          let m: YAMLMap => {
            if (m.size() > 1) {
              onError("Each pair must have its own sequence indicator");
            }
            let pair = m.values.values().at(0) ?? Pair.new(Scalar.new(null), null);
            let mcb = m.commentBefore;
            if (mcb != null && mcb != "") {
              let kcb = pair.key.commentBefore;
              pair.key.commentBefore = if (kcb != null && kcb != "") { mcb + "\n" + kcb } else { mcb };
            }
            let mc = m.comment;
            if (mc != null && mc != "") {
              let cn: Node = pair.value ?? pair.key;
              let cc = cn.comment;
              cn.comment = if (cc != null && cc != "") { mc + "\n" + cc } else { mc };
            }
            s.items[i] = pair;
          },
          let n: Node => {
            s.items[i] = Pair.new(n, null);
          },
        }
        i += 1;
      }
    },
    _ => {
      onError("Expected a sequence for this tag");
    },
  }
  seq
}

function createPairs(nc: NodeCreator, iterable: unknown) -> YAMLSeq throws unknown {
  let pairs = YAMLSeq.new(nc.schema, null);
  pairs.tag = "tag:yaml.org,2002:pairs";
  let i = 0;
  let iter = js_iterable(iterable);
  if (iter != null) {
    for (let it0 in iter) {
      let it = it0;
      let r = nc.replacer;
      match (r) {
        let f: ReplacerFn => {
          it = f(i.to_string(), it, iterable);
          i += 1;
        },
        _ => {},
      }
      let key: unknown = null;
      let value: unknown = null;
      let arr = js_as_array(it);
      let obj = js_as_object(it);
      if (arr != null) {
        if (arr.length() == 2) {
          key = arr[0];
          value = arr[1];
        } else {
          throw js_type_error("Expected [key, value] tuple: " + js_string(it));
        }
      } else if (obj != null) {
        let keys = obj.keys();
        if (keys.length() == 1) {
          key = keys[0];
          value = obj[keys[0]];
        } else {
          throw js_type_error("Expected tuple with one key, not " + keys.length().to_string() + " keys");
        }
      } else {
        key = it;
      }
      pairs.items.push(nc.createPair(key, value));
    }
  }
  pairs
}

function pairs_tag() -> Tag {
  Tag {
    _id: 30,
    collection: "seq",
    default: false,
    tag: "tag:yaml.org,2002:pairs",
    resolveCollection: (seq: Node, onError: TagOnError, opts: Options) -> unknown { resolvePairs(seq, onError) },
    createNode: (nc: NodeCreator, iterable: unknown) -> Node { createPairs(nc, iterable) },
  }
}
