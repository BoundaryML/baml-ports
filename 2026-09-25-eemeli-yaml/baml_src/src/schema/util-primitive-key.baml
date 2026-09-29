// Port of src/schema/util-primitive-key.ts

/// Returns the primitive value of a key (unwrapping a Pair and a Scalar), or
/// `undefined` (null here) for object keys.
function primitiveKey(value: unknown) -> Primitive {
  let value_ = match (value) {
    let p: Pair => p.key,
    _ => value,
  };
  let v = match (value_) {
    let s: Scalar => s.value,
    _ => value_,
  };
  match (v) {
    let b: bool => b,
    let i: int => i,
    let f: float => f,
    let g: bigint => g,
    let s: string => s,
    _ => null,
  }
}
