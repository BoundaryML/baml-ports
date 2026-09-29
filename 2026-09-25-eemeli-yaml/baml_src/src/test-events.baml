// Port of src/test-events.ts
//
// Test harness for yaml-test-suite event tests

function scalarChar(type: string) -> string? {
  match (type) {
    "BLOCK_FOLDED" => ">",
    "BLOCK_LITERAL" => "|",
    "PLAIN" => ":",
    "QUOTE_DOUBLE" => "\"",
    "QUOTE_SINGLE" => "'",
    _ => null,
  }
}

function anchorExists(doc: Document, anchor: string) -> bool {
  let found = false;
  visit(doc, VisitorFns {
    Value: (key: VisitKey, node: Scalar | YAMLMap | YAMLSeq | YAMLSet, path: VisitPathItem[]) -> VisitResult {
      if (nb(node).anchor == anchor) {
        found = true;
        return visit_BREAK();
      }
      null
    },
  });
  found
}

class TestEventsResult {
  events: string[]
  error: unknown?
}

/// Marker thrown by `addEvents` (`throw new Error()` in the original).
class TestEventsAbort {
  message: string
}

function testEvents(src_: string) -> TestEventsResult {
  let docs = parseAllDocuments(src_, null).docs;
  let errDoc = docs.find((doc: Document) -> bool { doc.errors.length() > 0 });
  let error: unknown = if (errDoc != null) { errDoc.errors[0].message } else { null };
  let events = ["+STR"];
  let aborted = testEventsLoop(docs, events) catch_all (e) {
    _ => {
      return TestEventsResult { events: events, error: error ?? e };
    },
  };
  events.push("-STR");
  TestEventsResult { events: events, error: error }
}

function testEventsLoop(docs: Document[], events: string[]) -> bool {
  let i = 0;
  while (i < docs.length()) {
    let doc = docs[i];
    let root = doc.value;
    let rootStart = (doc.range ?? [0])[0];
    let error = doc.errors.at(0);
    if (error != null && (error?.pos ?? [0])[0] < rootStart) {
      throw TestEventsAbort { message: "" };
    }
    let docStart = "+DOC";
    let rr = root.range ?? [0, 0, 0];
    if (doc.directives?.docStart ?? false) {
      docStart += " ---";
    } else if (rr[2] == rr[0] && (root.anchor == null || root.anchor == "") && (root.tag == null || root.tag == "")) {
      i += 1;
      continue;
    }
    events.push(docStart);
    addEvents(events, doc, if (error != null) { error.pos[0] } else { -1 }, root);

    let docEnd = "-DOC";
    if (doc.directives?.docEnd ?? false) {
      docEnd += " ...";
    }
    events.push(docEnd);
    i += 1;
  }
  true
}

function addEvents(events: string[], doc: Document, errPos: int, node: SeqItem?) -> null {
  if (node == null) {
    events.push("=VAL :");
    return null;
  }
  let nn = as_node(node);
  if (errPos != -1 && nn != null && (nn?.range ?? [0])[0] >= errPos) {
    throw TestEventsAbort { message: "" };
  }
  let props = "";
  let anchor = if (nn != null) { nn.anchor } else { null };
  if (anchor != null && anchor != "") {
    let a: string = anchor;
    if (re("\\d$").has_match(a)) {
      let alt = a.replace(re("\\d$"), "");
      if (anchorExists(doc, alt)) {
        a = alt;
      }
    }
    props = " &" + a;
  }
  if (nn?.tag != null && nn?.tag != "") {
    props += " <" + (nn?.tag ?? "") + ">";
  }

  match (node) {
    let m: YAMLMap => {
      let ev = if (m.flow ?? false) { "+MAP {}" } else { "+MAP" };
      events.push(ev + props);
      for (let p in m.values.values()) {
        addEvents(events, doc, errPos, p.key);
        addEvents(events, doc, errPos, p.value);
      }
      events.push("-MAP");
    },
    let s: YAMLSeq => {
      let ev = if (s.flow ?? false) { "+SEQ []" } else { "+SEQ" };
      events.push(ev + props);
      for (let item in s.items) {
        addEvents(events, doc, errPos, item);
      }
      events.push("-SEQ");
    },
    let s: YAMLSet => {
      let ev = if (s.flow ?? false) { "+MAP {}" } else { "+MAP" };
      events.push(ev + props);
      for (let value in s.values.values()) {
        addEvents(events, doc, errPos, value);
        events.push("=VAL :");
      }
      events.push("-MAP");
    },
    let p: Pair => {
      events.push("+MAP" + props);
      addEvents(events, doc, errPos, p.key);
      addEvents(events, doc, errPos, p.value);
      events.push("-MAP");
    },
    let a: Alias => {
      let alias = a.source;
      if (alias != "" && re("\\d$").has_match(alias)) {
        let alt = alias.replace(re("\\d$"), "");
        if (anchorExists(doc, alt)) {
          alias = alt;
        }
      }
      events.push("=ALI" + props + " *" + alias);
    },
    let s: Scalar => {
      let scalar = scalarChar(s.type ?? "undefined");
      if (scalar == null) {
        throw js_error("Unexpected node type " + (s.type ?? "undefined"));
      }
      let value = (s.source ?? "")
        .replace_all("\\", "\\\\")
        .replace_all("\0", "\\0")
        .replace_all(chr(7), "\\a")
        .replace_all("\b", "\\b")
        .replace_all("\t", "\\t")
        .replace_all("\n", "\\n")
        .replace_all("\v", "\\v")
        .replace_all("\f", "\\f")
        .replace_all("\r", "\\r")
        .replace_all(chr(0x1b), "\\e");
      events.push("=VAL" + props + " " + (scalar ?? "") + value);
    },
  }
  null
}
