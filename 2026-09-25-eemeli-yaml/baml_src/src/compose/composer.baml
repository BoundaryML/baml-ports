// Port of src/compose/composer.ts

/// `number | [number, number] | Range | { offset: number; source?: string }`
type ErrorSource = int | int[] | Token

/// `(source, code, message, warning?) => void`. The optional `warning` is an
/// explicit bool here.
type ComposeErrorHandler = (ErrorSource, string, string, bool) -> void throws unknown

function getErrorPos(src_: ErrorSource) -> int[] {
  match (src_) {
    let n: int => [n, n + 1],
    let arr: int[] => if (arr.length() == 2) { arr.slice(0, 2) } else { [arr[0], arr[1]] },
    let t: Token => {
      let s = t.source;
      [t.offset, t.offset + (if (s != null) { s.length() } else { 1 })]
    },
  }
}

class PreludeInfo {
  comment: string
  afterEmptyLine: bool
}

function parsePrelude(prelude: string[]) -> PreludeInfo {
  let comment = "";
  let atComment = false;
  let afterEmptyLine = false;
  let i = 0;
  while (i < prelude.length()) {
    let source = prelude[i];
    let c0 = source.at(0) ?? "";
    if (c0 == "#") {
      let body = str_from(source, 1);
      comment += (if (comment == "") { "" } else if (afterEmptyLine) { "\n\n" } else { "\n" }) + (if (body != "") { body } else { " " });
      atComment = true;
      afterEmptyLine = false;
    } else if (c0 == "%") {
      if ((prelude.at(i + 1) ?? "").at(0) != "#") {
        i += 1;
      }
      atComment = false;
    } else {
      // This may be wrong after doc-end, but in that case it doesn't matter
      if (!atComment) {
        afterEmptyLine = true;
      }
      atComment = false;
    }
    i += 1;
  }
  PreludeInfo { comment: comment, afterEmptyLine: afterEmptyLine }
}

/// `Composer.streamInfo()` result
class StreamInfo {
  comment: string
  directives: Directives
  errors: YAMLError[]
  warnings: YAMLError[]
}

/// Compose a stream of CST nodes into a stream of YAML Documents.
class Composer {
  directives: Directives
  doc: Document?
  docs: Document[]
  options: Options
  atDirectives: bool
  prelude: string[]
  errors: YAMLError[]
  warnings: YAMLError[]

  function new(options0: Options?) -> Composer {
    let options = options0 ?? Options {};
    let v = options.version;
    Composer {
      directives: Directives.new(DirectivesYaml { version: if (v != null && v != "") { v } else { "1.2" } }, null),
      docs: [],
      options: options,
      atDirectives: false,
      prelude: [],
      errors: [],
      warnings: [],
    }
  }

  function onError(self, source: ErrorSource, code: string, message: string, warning: bool) -> null {
    let pos = getErrorPos(source);
    if (warning) {
      self.warnings.push(YAMLWarning(pos, code, message));
    } else {
      self.errors.push(YAMLParseError(pos, code, message));
    }
    null
  }

  function onErrorFn(self) -> ComposeErrorHandler {
    (source: ErrorSource, code: string, message: string, warning: bool) -> void {
      self.onError(source, code, message, warning);
    }
  }

  function decorate(self, doc: Document, afterDoc: bool) -> null {
    let pp = parsePrelude(self.prelude);
    let comment = pp.comment;
    if (comment != "") {
      let dc = doc.value;
      let dcComment = doc.comment;
      if (afterDoc) {
        doc.comment = if (dcComment != null && dcComment != "") { dcComment + "\n" + comment } else { comment };
      } else if (pp.afterEmptyLine || (doc.directives?.docStart ?? false)) {
        doc.commentBefore = comment;
      } else if (isCollection(dc) && !(collection_flow(dc)) && collection_size(dc) > 0) {
        let it: NodeBase = match (dc) {
          let s: YAMLSeq => match (s.items[0]) {
            let p: Pair => p.key,
            let n: Node => n,
          },
          let m: YAMLMap => m.values.values()[0].key,
          let s: YAMLSet => s.values.values()[0],
          _ => dc,
        };
        let cb = it.commentBefore;
        it.commentBefore = if (cb != null && cb != "") { comment + "\n" + cb } else { comment };
      } else {
        let cb = dc.commentBefore;
        dc.commentBefore = if (cb != null && cb != "") { comment + "\n" + cb } else { comment };
      }
    }

    if (afterDoc) {
      for (let e in self.errors) {
        doc.errors.push(e);
      }
      for (let w in self.warnings) {
        doc.warnings.push(w);
      }
    } else {
      doc.errors = self.errors;
      doc.warnings = self.warnings;
    }

    self.prelude = [];
    self.errors = [];
    self.warnings = [];
    null
  }

  /// Current stream status information.
  ///
  /// Mostly useful at the end of input for an empty stream.
  function streamInfo(self) -> StreamInfo {
    StreamInfo {
      comment: parsePrelude(self.prelude).comment,
      directives: self.directives,
      errors: self.errors,
      warnings: self.warnings,
    }
  }

  /// Compose tokens into documents.
  ///
  /// @param forceDoc - If the stream contains no document, still emit a final
  ///   document including any comments and directives that would be applied
  ///   to a subsequent document.
  /// @param endOffset - Should be set if `forceDoc` is also set, to set the
  ///   document range end and to indicate errors correctly.
  function compose(self, tokens: Token[], forceDoc: bool, endOffset: int) -> Document[] {
    self.docs = [];
    for (let token in tokens) {
      self.next(token);
    }
    self.end(forceDoc, endOffset)
  }

  /// Advance the composer by one CST token.
  function next(self, token: Token) -> null {
    let onError = self.onErrorFn();
    match (token.type) {
      "directive" => {
        self.directives.add(tsrc(token), (offset: int, message: string, warning: bool) -> void {
          let pos = getErrorPos(token);
          pos[0] += offset;
          self.onError(pos, "BAD_DIRECTIVE", message, warning);
        });
        self.prelude.push(tsrc(token));
        self.atDirectives = true;
      },
      "document" => {
        let doc = composeDoc(self.options, self.directives, token, onError);
        if (self.atDirectives && !(doc.directives?.docStart ?? false)) {
          self.onError(token, "MISSING_CHAR", "Missing directives-end/doc-start indicator line", false);
        }
        self.decorate(doc, false);
        let prev = self.doc;
        if (prev != null) {
          self.docs.push(prev);
        }
        self.doc = doc;
        self.atDirectives = false;
      },
      "byte-order-mark" => {},
      "space" => {},
      "comment" => {
        self.prelude.push(tsrc(token));
      },
      "newline" => {
        self.prelude.push(tsrc(token));
      },
      "error" => {
        let msg = if (tsrc(token) != "") {
          (token.message ?? "") + ": " + json_quote(tsrc(token))
        } else {
          token.message ?? ""
        };
        let error = YAMLParseError(getErrorPos(token), "UNEXPECTED_TOKEN", msg);
        let d = self.doc;
        if (self.atDirectives || d == null) {
          self.errors.push(error);
        } else {
          d.errors.push(error);
        }
      },
      "doc-end" => {
        let d = self.doc;
        if (d == null) {
          let msg = "Unexpected doc-end without preceding document";
          self.errors.push(YAMLParseError(getErrorPos(token), "UNEXPECTED_TOKEN", msg));
        } else {
          let dd = d.directives;
          if (dd != null) {
            dd.docEnd = true;
          }
          let end = resolveEnd(token.end, token.offset + tsrc(token).length(), d.options.strict ?? true, onError);
          self.decorate(d, true);
          if (end.comment != "") {
            let dc = d.comment;
            d.comment = if (dc != null && dc != "") { dc + "\n" + end.comment } else { end.comment };
          }
          let r = d.range;
          if (r != null) {
            r[2] = end.offset;
          }
        }
      },
      _ => {
        self.errors.push(YAMLParseError(getErrorPos(token), "UNEXPECTED_TOKEN", "Unsupported token " + token.type));
      },
    }
    null
  }

  /// Call at end of input to handle any remaining document.
  ///
  /// @param forceDoc - If the stream contains no document, still emit a final
  ///   document including any comments and directives that would be applied
  ///   to a subsequent document.
  /// @param endOffset - Should be set if `forceDoc` is also set, to set the
  ///   document range end and to indicate errors correctly.
  function end(self, forceDoc: bool, endOffset: int) -> Document[] {
    let d = self.doc;
    if (d != null) {
      self.decorate(d, true);
      self.docs.push(d);
      self.doc = null;
    } else if (forceDoc) {
      let opts = options_assign(Options { _directives: self.directives }, self.options);
      let doc = Document.new(null, null, opts);
      if (self.atDirectives) {
        self.onError(endOffset, "MISSING_CHAR", "Missing directives-end indicator line", false);
      }
      doc.range = [0, endOffset, endOffset];
      self.decorate(doc, false);
      self.docs.push(doc);
    }
    self.docs
  }
}

function collection_flow(n: Node) -> bool {
  match (n) {
    let m: YAMLMap => m.flow ?? false,
    let s: YAMLSeq => s.flow ?? false,
    let s: YAMLSet => s.flow ?? false,
    _ => false,
  }
}

function collection_size(n: Node) -> int {
  match (n) {
    let m: YAMLMap => m.size(),
    let s: YAMLSeq => s.size(),
    let s: YAMLSet => s.size(),
    _ => 0,
  }
}
