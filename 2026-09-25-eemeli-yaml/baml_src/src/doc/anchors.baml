// Port of src/doc/anchors.ts

/// Verify that the input string is a valid anchor.
///
/// Will throw on errors.
function anchorIsValid(anchor: string) -> bool {
  if (re("[\\x00-\\x19\\s,\\[\\]{}]").has_match(anchor)) {
    let sa = json_quote(anchor);
    let msg = "Anchor must not contain whitespace or control characters: " + sa;
    throw js_error(msg);
  }
  true
}

function anchorNames(root: Document | Node) -> JsSet {
  let anchors = js_set();
  visit(root, VisitorFns {
    Value: (key: VisitKey, node: Scalar | YAMLMap | YAMLSeq | YAMLSet, path: VisitPathItem[]) -> VisitResult {
      let a = nb(node).anchor;
      if (a != null && a != "") {
        anchors.add(a);
      }
      null
    },
  });
  anchors
}

/// Find a new anchor name with the given `prefix` and a one-indexed suffix.
function findNewAnchor(prefix: string, exclude: JsSet) -> string {
  let i = 1;
  while (true) {
    let name = prefix + i.to_string();
    if (!exclude.has(name)) {
      return name;
    }
    i += 1;
  }
  ""
}
