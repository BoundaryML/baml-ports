// Port of src/nodes/Pair.ts

class Pair {
  _id: int
  key: Node
  value: Node?
  /// The CST token that was composed into this pair.
  srcToken: CollectionItem?

  /// `new Pair(key, value = null)`
  function new(key: Node, value: Node?) -> Pair {
    Pair { _id: new_id(), key: key, value: value }
  }

  function clone(self, schema: Schema?) -> Pair {
    let key = self.key.cloneNode(schema);
    let v = self.value;
    let value = if (v == null) { null } else { v.cloneNode(schema) };
    Pair.new(key, value)
  }

  function toJS(self, doc: Document?, ctx: ToJSContext) -> MapLike {
    let pair: MapLike = if (ctx.mapAsMap) { js_map() } else { js_object() };
    addPairToJSMap(doc, ctx, pair, self);
    pair
  }

  function toString(self, ctx: StringifyContext?, onComment: Callback?, onChompKeep: Callback?) -> string {
    if (ctx != null) {
      stringifyPair(self, ctx, onComment, onChompKeep)
    } else {
      json_stringify(self)
    }
  }
}

/// `{}`: an empty plain JS object.
function js_object() -> map<string, unknown> {
  let o: map<string, unknown> = {};
  o
}
