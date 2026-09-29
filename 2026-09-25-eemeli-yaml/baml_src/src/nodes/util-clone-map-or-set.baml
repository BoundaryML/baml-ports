// Port of src/nodes/util-clone-map-or-set.ts
//
// The original is shared by YAMLMap.clone and YAMLSet.clone via
// `new (coll.constructor)(schema)`; BAML has no constructor reflection, so
// each class implements `clone(schema)` itself (see YAMLMap.baml /
// YAMLSet.baml). This dispatcher is kept for API parity.

function cloneMapOrSet(coll: YAMLMap | YAMLSet, schema: Schema?) -> YAMLMap | YAMLSet {
  match (coll) {
    let m: YAMLMap => m.clone(schema),
    let s: YAMLSet => s.clone(schema),
  }
}
