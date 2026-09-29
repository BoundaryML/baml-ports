// Port of src/doc/applyReviver.ts
//
// Applies the JSON.parse reviver algorithm as defined in the ECMA-262 spec,
// in section 24.5.1.1 "Runtime Semantics: InternalizeJSONProperty" of the
// 2021 edition: https://tc39.es/ecma262/#sec-json.parse
//
// Includes extensions for handling Map and Set objects.
//
// The reviver returns `undefined` to delete a property; BAML has no
// `undefined`, so a reviver deletes by returning the sentinel `js_undefined()`.

class ReviverCtx {
  reviver: Reviver
  seen: unknown[]
  sources: ReviverSources
}

/// Sentinel standing in for JS `undefined` as a reviver result.
function js_undefined() -> JsSymbol {
  JsSymbol { _id: -1, description: "undefined" }
}

function is_js_undefined(v: unknown) -> bool {
  match (v) {
    let s: JsSymbol => s._id == -1,
    _ => false,
  }
}

function applyReviver(reviver: Reviver, sources: ReviverSources, obj: unknown, key: unknown, val: unknown) -> unknown throws unknown {
  let ctx = ReviverCtx { reviver: reviver, seen: [], sources: sources };
  applyReviver_(ctx, obj, key, val)
}

function applyReviver_(ctx: ReviverCtx, obj: unknown, key: unknown, val: unknown) -> unknown throws unknown {
  if (js_truthy(val) && js_typeof(val) == "object") {
    if (ctx.seen.some((s: unknown) -> bool { js_identical(s, val) })) {
      return val;
    }
    ctx.seen.push(val);
    match (val) {
      let arr: unknown[] => {
        let i = 0;
        let len = arr.length();
        while (i < len) {
          let v0 = arr[i];
          let v1 = applyReviver_(ctx, arr, i.to_string(), v0);
          if (is_js_undefined(v1)) {
            // `delete val[i]` leaves a hole, which reads as `undefined`
            // (`null` here); the array keeps its length.
            arr[i] = null;
          } else if (!js_same(v1, v0)) {
            arr[i] = v1;
          }
          i += 1;
        }
      },
      let m: JsMap<unknown> => {
        for (let k in m.keys()) {
          let v0 = m.get(k);
          let v1 = applyReviver_(ctx, m, k, v0);
          if (is_js_undefined(v1)) {
            m.delete(k);
          } else if (!js_same(v1, v0)) {
            m.set(k, v1);
          }
        }
      },
      let s: JsSet => {
        for (let v0 in s.values()) {
          let v1 = applyReviver_(ctx, s, v0, v0);
          if (is_js_undefined(v1)) {
            s.delete(v0);
          } else if (!js_same(v1, v0)) {
            s.delete(v0);
            s.add(v1);
          }
        }
      },
      let o: map<string, unknown> => {
        for (let k in o.keys()) {
          let v0 = o[k];
          let v1 = applyReviver_(ctx, o, k, v0);
          if (is_js_undefined(v1)) {
            o.delete(k);
          } else if (!js_same(v1, v0)) {
            o.set(k, v1);
          }
        }
      },
      _ => {},
    }
  }
  let context = ReviverContext {};
  let source = ctx.sources.get(obj)?.get(key);
  if (source != null) {
    context.source = source;
  }
  let reviver = ctx.reviver;
  reviver(key, val, context, obj)
}
