// Port of src/parse/parser.ts

function includes_token(list: Token[], type: string) -> bool {
  for (let t in list) {
    if (t.type == type) {
      return true;
    }
  }
  false
}

function find_non_empty_index(list: Token[]) -> int {
  let i = 0;
  while (i < list.length()) {
    let t = list[i].type;
    if (t != "space" && t != "comment" && t != "newline") {
      return i;
    }
    i += 1;
  }
  -1
}

function is_flow_token(token: Token?) -> bool {
  if (token == null) {
    return false;
  }
  match (token.type) {
    "alias" => true,
    "scalar" => true,
    "single-quoted-scalar" => true,
    "double-quoted-scalar" => true,
    "flow-collection" => true,
    _ => false,
  }
}

function get_prev_props(parent: Token) -> Token[] {
  match (parent.type) {
    "document" => tstart(parent),
    "block-map" => {
      let items = titems(parent);
      let it = items[items.length() - 1];
      it.sep ?? it.start
    },
    "block-seq" => {
      let items = titems(parent);
      items[items.length() - 1].start
    },
    _ => {
      let empty: Token[] = [];
      empty
    },
  }
}

/// Note: May modify input array
function get_first_key_start_props(prev: Token[]) -> Token[] {
  if (prev.length() == 0) {
    let empty: Token[] = [];
    return empty;
  }
  let i = prev.length();
  i -= 1;
  while (i >= 0) {
    let t = prev[i].type;
    if (t == "doc-start" || t == "explicit-key-ind" || t == "map-value-ind" || t == "seq-item-ind" || t == "newline") {
      break;
    }
    i -= 1;
  }
  i += 1;
  while (i < prev.length() && prev[i].type == "space") {
    i += 1;
  }
  // prev.splice(i, prev.length)
  let out: Token[] = [];
  while (prev.length() > i) {
    out.unshift(prev.pop() ?? source_token("error", 0, 0, ""));
  }
  out
}

function fix_flow_seq_items(fc: Token) -> null {
  if (fc.fcStart?.type == "flow-seq-start") {
    for (let it in titems(fc)) {
      let sep = it.sep ?? [];
      if (
        it.sep != null &&
        it.value == null &&
        !includes_token(it.start, "explicit-key-ind") &&
        !includes_token(sep, "map-value-ind")
      ) {
        if (it.key != null) {
          it.value = it.key;
        }
        it.key = null;
        let v = it.value;
        if (v != null && is_flow_token(v)) {
          let vend = v.end;
          if (vend != null) {
            for (let st in sep) {
              vend.push(st);
            }
          } else {
            v.end = sep;
          }
        } else {
          for (let st in sep) {
            it.start.push(st);
          }
        }
        it.sep = null;
      }
    }
  }
  null
}

/// A YAML concrete syntax tree (CST) parser
///
/// ```
/// for (let token in new_parser(null).parse(src)) { ... }
/// ```
class Parser {
  onNewLine: ((int) -> void throws never)?
  /// If true, space and sequence indicators count as indentation
  atNewLine: bool
  /// If true, next token is a scalar value
  atScalar: bool
  /// Current indentation level
  indent: int
  /// Current offset since the start of parsing
  offset: int
  /// On the same line with a block map key
  onKeyLine: bool
  /// Top indicates the node that's currently being built
  stack: Token[]
  /// The source of the current token, set in parse()
  source: string
  /// The type of the current token, set in parse()
  type: string
  tokens: Token[]

  /// Parse `source` as a YAML stream.
  ///
  /// Errors are not thrown, but included in the result as
  /// `{ type: 'error', message }` tokens.
  ///
  /// @returns Tokens representing each directive, document, and other structure.
  function parse(self, source: string) -> Token[] {
    let onNewLine = self.onNewLine;
    if (onNewLine != null && self.offset == 0) {
      onNewLine(0);
    }
    for (let lexeme in lex(source)) {
      self.next(lexeme);
    }
    self.end()
  }

  /// Advance the parser by the `source` of one lexical token.
  function next(self, source: string) -> null {
    self.source = source;

    if (self.atScalar) {
      self.atScalar = false;
      self.step();
      self.offset += source.length();
      return null;
    }

    let type = token_type(source);
    if (type == null) {
      let message = "Not a YAML token: " + source;
      self.pop(Token { _id: new_id(), type: "error", offset: self.offset, message: message, source: source });
      self.offset += source.length();
    } else if (type == "scalar") {
      self.atNewLine = false;
      self.atScalar = true;
      self.type = "scalar";
    } else {
      self.type = type;
      self.step();
      match (type) {
        "newline" => {
          self.atNewLine = true;
          self.indent = 0;
          let onNewLine = self.onNewLine;
          if (onNewLine != null) {
            onNewLine(self.offset + source.length());
          }
        },
        "space" => {
          if (self.atNewLine && source.at(0) == " ") {
            self.indent += source.length();
          }
        },
        "explicit-key-ind" => {
          if (self.atNewLine) {
            self.indent += source.length();
          }
        },
        "map-value-ind" => {
          if (self.atNewLine) {
            self.indent += source.length();
          }
        },
        "seq-item-ind" => {
          if (self.atNewLine) {
            self.indent += source.length();
          }
        },
        "doc-mode" => {
          return null;
        },
        "flow-error-end" => {
          return null;
        },
        _ => {
          self.atNewLine = false;
        },
      }
      self.offset += source.length();
    }
    null
  }

  /// Call at end of input to account for any remaining constructions
  function end(self) -> Token[] {
    while (self.stack.length() > 0) {
      self.pop(null);
    }
    self.tokens
  }

  function sourceToken(self) -> Token {
    source_token(self.type, self.offset, self.indent, self.source)
  }

  function step(self) -> null {
    let top = self.peek(1);
    if (self.type == "doc-end" && top?.type != "doc-end") {
      while (self.stack.length() > 0) {
        self.pop(null);
      }
      self.stack.push(Token { _id: new_id(), type: "doc-end", offset: self.offset, source: self.source });
      return null;
    }
    if (top == null) {
      let token = self.stream();
      if (token != null) {
        self.tokens.push(token);
      }
      return null;
    }
    match (top.type) {
      "document" => {
        self.document(top);
        return null;
      },
      "alias" => {
        self.scalar(top);
        return null;
      },
      "scalar" => {
        self.scalar(top);
        return null;
      },
      "single-quoted-scalar" => {
        self.scalar(top);
        return null;
      },
      "double-quoted-scalar" => {
        self.scalar(top);
        return null;
      },
      "block-scalar" => {
        self.blockScalar(top);
        return null;
      },
      "block-map" => {
        self.blockMap(top);
        return null;
      },
      "block-seq" => {
        self.blockSequence(top);
        return null;
      },
      "flow-collection" => {
        self.flowCollection(top);
        return null;
      },
      "doc-end" => {
        self.documentEnd(top);
        return null;
      },
      _ => {},
    }
    self.pop(null);
    null
  }

  function peek(self, n: int) -> Token? {
    self.stack.at(self.stack.length() - n)
  }

  function pop(self, error: Token?) -> null {
    let token = error ?? self.stack.pop();
    if (token == null) {
      let message = "Tried to pop an empty stack";
      self.tokens.push(Token { _id: new_id(), type: "error", offset: self.offset, source: "", message: message });
      return null;
    }
    if (self.stack.length() == 0) {
      self.tokens.push(token);
      return null;
    }
    let top = self.peek(1) ?? token;
    let tok: Token = token;
    if (token.type == "block-scalar") {
      // Block scalars use their parent rather than header indent
      token.indent = top.indent ?? 0;
    } else if (token.type == "flow-collection" && top.type == "document") {
      // Ignore all indent for top-level flow collections
      token.indent = 0;
    }
    if (token.type == "flow-collection") {
      fix_flow_seq_items(token);
    }
    match (top.type) {
      "document" => {
        top.value = token;
      },
      "block-scalar" => {
        tprops(top).push(token); // error
      },
      "block-map" => {
        let items = titems(top);
        let it = items[items.length() - 1];
        if (it.value != null) {
          let ni = collection_item([]);
          ni.key = token;
          ni.sep = [];
          items.push(ni);
          self.onKeyLine = true;
          return null;
        } else if (it.sep != null) {
          it.value = token;
        } else {
          it.key = token;
          it.sep = [];
          self.onKeyLine = !(it.explicitKey ?? false);
          return null;
        }
      },
      "block-seq" => {
        let items = titems(top);
        let it = items[items.length() - 1];
        if (it.value != null) {
          let ni = collection_item([]);
          ni.value = token;
          items.push(ni);
        } else {
          it.value = token;
        }
      },
      "flow-collection" => {
        let items = titems(top);
        let it_ = items.at(items.length() - 1);
        if (it_ == null) {
          let ni = collection_item([]);
          ni.key = token;
          ni.sep = [];
          items.push(ni);
          return null;
        }
        let it: CollectionItem = it_;
        if (it.value != null) {
          let ni = collection_item([]);
          ni.key = token;
          ni.sep = [];
          items.push(ni);
        } else if (it.sep != null) {
          it.value = token;
        } else {
          it.key = token;
          it.sep = [];
        }
        return null;
      },
      _ => {
        self.pop(null);
        self.pop(token);
      },
    }

    if (
      (top.type == "document" || top.type == "block-map" || top.type == "block-seq") &&
      (token.type == "block-map" || token.type == "block-seq")
    ) {
      let titems_ = titems(token);
      let last = titems_.at(titems_.length() - 1) ?? collection_item([]);
      if (
        titems_.length() > 0 &&
        last.sep == null &&
        last.value == null &&
        last.start.length() > 0 &&
        find_non_empty_index(last.start) == -1 &&
        (tindent(token) == 0 ||
          last.start.every((st: Token) -> bool { st.type != "comment" || tindent(st) < tindent(tok) }))
      ) {
        if (top.type == "document") {
          top.end = last.start;
        } else {
          titems(top).push(collection_item(last.start));
        }
        titems_.pop();
      }
    }
    null
  }

  function stream(self) -> Token? {
    match (self.type) {
      "directive-line" => {
        return Token { _id: new_id(), type: "directive", offset: self.offset, source: self.source };
      },
      "byte-order-mark" => {
        return self.sourceToken();
      },
      "space" => {
        return self.sourceToken();
      },
      "comment" => {
        return self.sourceToken();
      },
      "newline" => {
        return self.sourceToken();
      },
      "doc-mode" => {
        let doc = Token { _id: new_id(), type: "document", offset: self.offset, start: [] };
        self.stack.push(doc);
        return null;
      },
      "doc-start" => {
        let doc = Token { _id: new_id(), type: "document", offset: self.offset, start: [] };
        tstart(doc).push(self.sourceToken());
        self.stack.push(doc);
        return null;
      },
      _ => {},
    }
    Token {
      _id: new_id(),
      type: "error",
      offset: self.offset,
      message: "Unexpected " + self.type + " token in YAML stream",
      source: self.source,
    }
  }

  function document(self, doc: Token) -> null {
    if (doc.value != null) {
      self.lineEnd(doc);
      return null;
    }
    match (self.type) {
      "doc-start" => {
        if (find_non_empty_index(tstart(doc)) != -1) {
          self.pop(null);
          self.step();
        } else {
          tstart(doc).push(self.sourceToken());
        }
        return null;
      },
      "anchor" => {
        tstart(doc).push(self.sourceToken());
        return null;
      },
      "tag" => {
        tstart(doc).push(self.sourceToken());
        return null;
      },
      "space" => {
        tstart(doc).push(self.sourceToken());
        return null;
      },
      "comment" => {
        tstart(doc).push(self.sourceToken());
        return null;
      },
      "newline" => {
        tstart(doc).push(self.sourceToken());
        return null;
      },
      _ => {},
    }
    let bv = self.startBlockValue(doc);
    if (bv != null) {
      self.stack.push(bv);
    } else {
      self.tokens.push(Token {
        _id: new_id(),
        type: "error",
        offset: self.offset,
        message: "Unexpected " + self.type + " token in YAML document",
        source: self.source,
      });
    }
    null
  }

  function scalar(self, scalar: Token) -> null {
    if (self.type == "map-value-ind") {
      let prev = get_prev_props(self.peek(2) ?? scalar);
      let start = get_first_key_start_props(prev);

      let sep: Token[] = [];
      let send = scalar.end;
      if (send != null) {
        sep = send;
        sep.push(self.sourceToken());
        scalar.end = null;
      } else {
        sep = [self.sourceToken()];
      }

      let item = collection_item(start);
      item.key = scalar;
      item.sep = sep;
      let map = Token {
        _id: new_id(),
        type: "block-map",
        offset: scalar.offset,
        indent: scalar.indent,
        items: [item],
      };
      self.onKeyLine = true;
      self.stack[self.stack.length() - 1] = map;
    } else {
      self.lineEnd(scalar);
    }
    null
  }

  function blockScalar(self, scalar: Token) -> null {
    match (self.type) {
      "space" => {
        tprops(scalar).push(self.sourceToken());
      },
      "comment" => {
        tprops(scalar).push(self.sourceToken());
      },
      "newline" => {
        tprops(scalar).push(self.sourceToken());
      },
      "scalar" => {
        scalar.source = self.source;
        // block-scalar source includes trailing newline
        self.atNewLine = true;
        self.indent = 0;
        let onNewLine = self.onNewLine;
        if (onNewLine != null) {
          let nl = str_index_of(self.source, "\n", 0) + 1;
          while (nl != 0) {
            onNewLine(self.offset + nl);
            nl = str_index_of(self.source, "\n", nl) + 1;
          }
        }
        self.pop(null);
      },
      _ => {
        self.pop(null);
        self.step();
      },
    }
    null
  }

  function blockMap(self, map: Token) -> null {
    let mitems = titems(map);
    let it = mitems[mitems.length() - 1];

    // it.sep is true-ish if pair already has key or : separator
    match (self.type) {
      "newline" => {
        self.onKeyLine = false;
        let itv = it.value;
        let itsep = it.sep;
        if (itv != null) {
          let end = itv.end;
          let last = if (end != null) { end.at(end.length() - 1) } else { null };
          if (last?.type == "comment") {
            end?.push(self.sourceToken());
          } else {
            mitems.push(collection_item([self.sourceToken()]));
          }
        } else if (itsep != null) {
          itsep.push(self.sourceToken());
        } else {
          it.start.push(self.sourceToken());
        }
        return null;
      },
      "space" => {
        self.blockMapSpaceOrComment(map, it);
        return null;
      },
      "comment" => {
        self.blockMapSpaceOrComment(map, it);
        return null;
      },
      _ => {},
    }

    if (self.indent >= tindent(map)) {
      let atMapIndent = !self.onKeyLine && self.indent == tindent(map);
      let atNextItem = atMapIndent && (it.sep != null || (it.explicitKey ?? false)) && self.type != "seq-item-ind";

      // For empty nodes, assign newline-separated not indented empty tokens to following node
      let start: Token[] = [];
      let itsep0 = it.sep;
      if (atNextItem && itsep0 != null && it.value == null) {
        let nl: int[] = [];
        let i = 0;
        while (i < itsep0.length()) {
          let st = itsep0[i];
          match (st.type) {
            "newline" => {
              nl.push(i);
            },
            "space" => {},
            "comment" => {
              if (tindent(st) > tindent(map)) {
                nl = [];
              }
            },
            _ => {
              nl = [];
            },
          }
          i += 1;
        }
        if (nl.length() >= 2) {
          // start = it.sep.splice(nl[1])
          let cut = nl[1];
          while (itsep0.length() > cut) {
            start.unshift(itsep0.pop() ?? self.sourceToken());
          }
        }
      }

      match (self.type) {
        "anchor" => {
          self.blockMapProp(map, it, atNextItem, start);
          return null;
        },
        "tag" => {
          self.blockMapProp(map, it, atNextItem, start);
          return null;
        },
        "explicit-key-ind" => {
          if (it.sep == null && !(it.explicitKey ?? false)) {
            it.start.push(self.sourceToken());
            it.explicitKey = true;
          } else if (atNextItem || it.value != null) {
            start.push(self.sourceToken());
            let ni = collection_item(start);
            ni.explicitKey = true;
            mitems.push(ni);
          } else {
            let ni = collection_item([self.sourceToken()]);
            ni.explicitKey = true;
            self.stack.push(Token {
              _id: new_id(),
              type: "block-map",
              offset: self.offset,
              indent: self.indent,
              items: [ni],
            });
          }
          self.onKeyLine = true;
          return null;
        },
        "map-value-ind" => {
          let itsep = it.sep;
          if (it.explicitKey ?? false) {
            if (itsep == null) {
              if (includes_token(it.start, "newline")) {
                it.key = null;
                it.sep = [self.sourceToken()];
              } else {
                let start2 = get_first_key_start_props(it.start);
                let ni = collection_item(start2);
                ni.key = null;
                ni.sep = [self.sourceToken()];
                self.stack.push(Token {
                  _id: new_id(),
                  type: "block-map",
                  offset: self.offset,
                  indent: self.indent,
                  items: [ni],
                });
              }
            } else if (it.value != null) {
              let ni = collection_item([]);
              ni.key = null;
              ni.sep = [self.sourceToken()];
              mitems.push(ni);
            } else if (includes_token(itsep, "map-value-ind")) {
              let ni = collection_item(start);
              ni.key = null;
              ni.sep = [self.sourceToken()];
              self.stack.push(Token {
                _id: new_id(),
                type: "block-map",
                offset: self.offset,
                indent: self.indent,
                items: [ni],
              });
            } else if (is_flow_token(it.key) && !includes_token(itsep, "newline")) {
              let start2 = get_first_key_start_props(it.start);
              let key = it.key;
              let sep = itsep;
              sep.push(self.sourceToken());
              it.key = null;
              it.sep = null;
              let ni = collection_item(start2);
              ni.key = key;
              ni.sep = sep;
              self.stack.push(Token {
                _id: new_id(),
                type: "block-map",
                offset: self.offset,
                indent: self.indent,
                items: [ni],
              });
            } else if (start.length() > 0) {
              // Not actually at next item
              let ns: Token[] = [];
              for (let t in itsep) {
                ns.push(t);
              }
              for (let t in start) {
                ns.push(t);
              }
              ns.push(self.sourceToken());
              it.sep = ns;
            } else {
              itsep.push(self.sourceToken());
            }
          } else {
            if (itsep == null) {
              it.key = null;
              it.sep = [self.sourceToken()];
            } else if (it.value != null || atNextItem) {
              let ni = collection_item(start);
              ni.key = null;
              ni.sep = [self.sourceToken()];
              mitems.push(ni);
            } else if (includes_token(itsep, "map-value-ind")) {
              let ni = collection_item([]);
              ni.key = null;
              ni.sep = [self.sourceToken()];
              self.stack.push(Token {
                _id: new_id(),
                type: "block-map",
                offset: self.offset,
                indent: self.indent,
                items: [ni],
              });
            } else {
              itsep.push(self.sourceToken());
            }
          }
          self.onKeyLine = true;
          return null;
        },
        "alias" => {
          self.blockMapFlowScalar(map, it, atNextItem, start);
          return null;
        },
        "scalar" => {
          self.blockMapFlowScalar(map, it, atNextItem, start);
          return null;
        },
        "single-quoted-scalar" => {
          self.blockMapFlowScalar(map, it, atNextItem, start);
          return null;
        },
        "double-quoted-scalar" => {
          self.blockMapFlowScalar(map, it, atNextItem, start);
          return null;
        },
        _ => {
          let bv = self.startBlockValue(map);
          if (bv != null) {
            if (bv.type == "block-seq") {
              let itsep = it.sep;
              if (!(it.explicitKey ?? false) && it.sep != null && !includes_token(itsep ?? [], "newline")) {
                self.pop(Token {
                  _id: new_id(),
                  type: "error",
                  offset: self.offset,
                  message: "Unexpected block-seq-ind on same line with key",
                  source: self.source,
                });
                return null;
              }
            } else if (atMapIndent && (it.sep != null || (it.explicitKey ?? false) || start.length() > 0)) {
              mitems.push(collection_item(start));
            }
            self.stack.push(bv);
            return null;
          }
        },
      }
    }
    self.pop(null);
    self.step();
    null
  }

  /// `case 'space': case 'comment':` of blockMap()
  function blockMapSpaceOrComment(self, map: Token, it: CollectionItem) -> null {
    let mitems = titems(map);
    let itsep = it.sep;
    if (it.value != null) {
      mitems.push(collection_item([self.sourceToken()]));
    } else if (itsep != null) {
      itsep.push(self.sourceToken());
    } else {
      if (self.atIndentedComment(it.start, tindent(map))) {
        let prev = mitems.at(mitems.length() - 2);
        let pv = prev?.value;
        let end = pv?.end;
        if (end != null) {
          for (let t in it.start) {
            end.push(t);
          }
          end.push(self.sourceToken());
          mitems.pop();
          return null;
        }
      }
      it.start.push(self.sourceToken());
    }
    null
  }

  /// `case 'anchor': case 'tag':` of blockMap()
  function blockMapProp(self, map: Token, it: CollectionItem, atNextItem: bool, start: Token[]) -> null {
    let itsep = it.sep;
    if (atNextItem || it.value != null) {
      start.push(self.sourceToken());
      titems(map).push(collection_item(start));
      self.onKeyLine = true;
    } else if (itsep != null) {
      itsep.push(self.sourceToken());
    } else {
      it.start.push(self.sourceToken());
    }
    null
  }

  /// `case 'alias': case 'scalar': ...` of blockMap()
  function blockMapFlowScalar(self, map: Token, it: CollectionItem, atNextItem: bool, start: Token[]) -> null {
    let fs = self.flowScalar(self.type);
    if (atNextItem || it.value != null) {
      let ni = collection_item(start);
      ni.key = fs;
      ni.sep = [];
      titems(map).push(ni);
      self.onKeyLine = true;
    } else if (it.sep != null) {
      self.stack.push(fs);
    } else {
      it.key = fs;
      it.sep = [];
      self.onKeyLine = true;
    }
    null
  }

  function blockSequence(self, seq: Token) -> null {
    let sitems = titems(seq);
    let it = sitems[sitems.length() - 1];
    match (self.type) {
      "newline" => {
        let itv = it.value;
        if (itv != null) {
          let end = itv.end;
          let last = if (end != null) { end.at(end.length() - 1) } else { null };
          if (last?.type == "comment") {
            end?.push(self.sourceToken());
          } else {
            sitems.push(collection_item([self.sourceToken()]));
          }
        } else {
          it.start.push(self.sourceToken());
        }
        return null;
      },
      "space" => {
        self.blockSeqSpaceOrComment(seq, it);
        return null;
      },
      "comment" => {
        self.blockSeqSpaceOrComment(seq, it);
        return null;
      },
      "anchor" => {
        if (!(it.value != null || self.indent <= tindent(seq))) {
          it.start.push(self.sourceToken());
          return null;
        }
      },
      "tag" => {
        if (!(it.value != null || self.indent <= tindent(seq))) {
          it.start.push(self.sourceToken());
          return null;
        }
      },
      "seq-item-ind" => {
        if (self.indent == tindent(seq)) {
          if (it.value != null || includes_token(it.start, "seq-item-ind")) {
            sitems.push(collection_item([self.sourceToken()]));
          } else {
            it.start.push(self.sourceToken());
          }
          return null;
        }
      },
      _ => {},
    }
    if (self.indent > tindent(seq)) {
      let bv = self.startBlockValue(seq);
      if (bv != null) {
        self.stack.push(bv);
        return null;
      }
    }
    self.pop(null);
    self.step();
    null
  }

  function blockSeqSpaceOrComment(self, seq: Token, it: CollectionItem) -> null {
    let sitems = titems(seq);
    if (it.value != null) {
      sitems.push(collection_item([self.sourceToken()]));
    } else {
      if (self.atIndentedComment(it.start, tindent(seq))) {
        let prev = sitems.at(sitems.length() - 2);
        let pv = prev?.value;
        let end = pv?.end;
        if (end != null) {
          for (let t in it.start) {
            end.push(t);
          }
          end.push(self.sourceToken());
          sitems.pop();
          return null;
        }
      }
      it.start.push(self.sourceToken());
    }
    null
  }

  function flowCollection(self, fc: Token) -> null {
    let fitems = titems(fc);
    let it = fitems.at(fitems.length() - 1);
    let fcend = tend(fc);
    if (self.type == "flow-error-end") {
      let top: Token? = null;
      let go = true;
      while (go) {
        self.pop(null);
        top = self.peek(1);
        go = top?.type == "flow-collection";
      }
    } else if (fcend.length() == 0) {
      // `it` may be undefined; `itx` is the same item when it is defined.
      let itx = it ?? collection_item([]);
      match (self.type) {
        "comma" => {
          if (it == null || itx.sep != null) {
            fitems.push(collection_item([self.sourceToken()]));
          } else {
            itx.start.push(self.sourceToken());
          }
          return null;
        },
        "explicit-key-ind" => {
          if (it == null || itx.sep != null) {
            fitems.push(collection_item([self.sourceToken()]));
          } else {
            itx.start.push(self.sourceToken());
          }
          return null;
        },
        "map-value-ind" => {
          if (it == null || itx.value != null) {
            let ni = collection_item([]);
            ni.key = null;
            ni.sep = [self.sourceToken()];
            fitems.push(ni);
          } else {
            let itsep = itx.sep;
            if (itsep != null) {
              itsep.push(self.sourceToken());
            } else {
              itx.key = null;
              itx.sep = [self.sourceToken()];
            }
          }
          return null;
        },
        "space" => {
          self.flowCollProp(fc, it);
          return null;
        },
        "comment" => {
          self.flowCollProp(fc, it);
          return null;
        },
        "newline" => {
          self.flowCollProp(fc, it);
          return null;
        },
        "anchor" => {
          self.flowCollProp(fc, it);
          return null;
        },
        "tag" => {
          self.flowCollProp(fc, it);
          return null;
        },
        "alias" => {
          self.flowCollScalar(fc, it);
          return null;
        },
        "scalar" => {
          self.flowCollScalar(fc, it);
          return null;
        },
        "single-quoted-scalar" => {
          self.flowCollScalar(fc, it);
          return null;
        },
        "double-quoted-scalar" => {
          self.flowCollScalar(fc, it);
          return null;
        },
        "flow-map-end" => {
          fcend.push(self.sourceToken());
          fc.end = fcend;
          return null;
        },
        "flow-seq-end" => {
          fcend.push(self.sourceToken());
          fc.end = fcend;
          return null;
        },
        _ => {},
      }
      let bv = self.startBlockValue(fc);
      if (bv != null) {
        self.stack.push(bv);
      } else {
        self.pop(null);
        self.step();
      }
    } else {
      let parent = self.peek(2) ?? fc;
      let pitems = parent.items;
      if (
        parent.type == "block-map" &&
        ((self.type == "map-value-ind" && tindent(parent) == tindent(fc)) ||
          (self.type == "newline" && (pitems ?? [])[(pitems ?? []).length() - 1].sep == null))
      ) {
        self.pop(null);
        self.step();
      } else if (self.type == "map-value-ind" && parent.type != "flow-collection") {
        let prev = get_prev_props(parent);
        let start = get_first_key_start_props(prev);
        fix_flow_seq_items(fc);
        // const sep = fc.end.splice(1, fc.end.length)
        let sep: Token[] = [];
        while (fcend.length() > 1) {
          sep.unshift(fcend.pop() ?? self.sourceToken());
        }
        sep.push(self.sourceToken());
        let ni = collection_item(start);
        ni.key = fc;
        ni.sep = sep;
        let map = Token {
          _id: new_id(),
          type: "block-map",
          offset: fc.offset,
          indent: fc.indent,
          items: [ni],
        };
        self.onKeyLine = true;
        self.stack[self.stack.length() - 1] = map;
      } else {
        self.lineEnd(fc);
      }
    }
    null
  }

  function flowCollProp(self, fc: Token, it_: CollectionItem?) -> null {
    if (it_ == null) {
      titems(fc).push(collection_item([self.sourceToken()]));
      return null;
    }
    let it: CollectionItem = it_;
    if (it.value != null) {
      titems(fc).push(collection_item([self.sourceToken()]));
    } else {
      let itsep = it.sep;
      if (itsep != null) {
        itsep.push(self.sourceToken());
      } else {
        it.start.push(self.sourceToken());
      }
    }
    null
  }

  function flowCollScalar(self, fc: Token, it_: CollectionItem?) -> null {
    let fs = self.flowScalar(self.type);
    if (it_ == null) {
      let ni = collection_item([]);
      ni.key = fs;
      ni.sep = [];
      titems(fc).push(ni);
      return null;
    }
    let it: CollectionItem = it_;
    if (it.value != null) {
      let ni = collection_item([]);
      ni.key = fs;
      ni.sep = [];
      titems(fc).push(ni);
    } else if (it.sep != null) {
      self.stack.push(fs);
    } else {
      it.key = fs;
      it.sep = [];
    }
    null
  }

  function flowScalar(self, type: string) -> Token {
    let onNewLine = self.onNewLine;
    if (onNewLine != null) {
      let nl = str_index_of(self.source, "\n", 0) + 1;
      while (nl != 0) {
        onNewLine(self.offset + nl);
        nl = str_index_of(self.source, "\n", nl) + 1;
      }
    }
    Token {
      _id: new_id(),
      type: type,
      offset: self.offset,
      indent: self.indent,
      source: self.source,
    }
  }

  function startBlockValue(self, parent: Token) -> Token? {
    match (self.type) {
      "alias" => self.flowScalar(self.type),
      "scalar" => self.flowScalar(self.type),
      "single-quoted-scalar" => self.flowScalar(self.type),
      "double-quoted-scalar" => self.flowScalar(self.type),
      "block-scalar-header" => Token {
        _id: new_id(),
        type: "block-scalar",
        offset: self.offset,
        indent: self.indent,
        props: [self.sourceToken()],
        source: "",
      },
      "flow-map-start" => Token {
        _id: new_id(),
        type: "flow-collection",
        offset: self.offset,
        indent: self.indent,
        fcStart: self.sourceToken(),
        items: [],
        end: [],
      },
      "flow-seq-start" => Token {
        _id: new_id(),
        type: "flow-collection",
        offset: self.offset,
        indent: self.indent,
        fcStart: self.sourceToken(),
        items: [],
        end: [],
      },
      "seq-item-ind" => Token {
        _id: new_id(),
        type: "block-seq",
        offset: self.offset,
        indent: self.indent,
        items: [collection_item([self.sourceToken()])],
      },
      "explicit-key-ind" => {
        self.onKeyLine = true;
        let prev = get_prev_props(parent);
        let start = get_first_key_start_props(prev);
        start.push(self.sourceToken());
        let ni = collection_item(start);
        ni.explicitKey = true;
        Token {
          _id: new_id(),
          type: "block-map",
          offset: self.offset,
          indent: self.indent,
          items: [ni],
        }
      },
      "map-value-ind" => {
        self.onKeyLine = true;
        let prev = get_prev_props(parent);
        let start = get_first_key_start_props(prev);
        let ni = collection_item(start);
        ni.key = null;
        ni.sep = [self.sourceToken()];
        Token {
          _id: new_id(),
          type: "block-map",
          offset: self.offset,
          indent: self.indent,
          items: [ni],
        }
      },
      _ => null,
    }
  }

  function atIndentedComment(self, start: Token[], indent: int) -> bool {
    if (self.type != "comment") {
      return false;
    }
    if (self.indent <= indent) {
      return false;
    }
    start.every((st: Token) -> bool { st.type == "newline" || st.type == "space" })
  }

  function documentEnd(self, docEnd: Token) -> null {
    if (self.type != "doc-mode") {
      let end = docEnd.end;
      if (end != null) {
        end.push(self.sourceToken());
      } else {
        docEnd.end = [self.sourceToken()];
      }
      if (self.type == "newline") {
        self.pop(null);
      }
    }
    null
  }

  function lineEnd(self, token: Token) -> null {
    match (self.type) {
      "comma" => {
        self.pop(null);
        self.step();
      },
      "doc-start" => {
        self.pop(null);
        self.step();
      },
      "doc-end" => {
        self.pop(null);
        self.step();
      },
      "flow-seq-end" => {
        self.pop(null);
        self.step();
      },
      "flow-map-end" => {
        self.pop(null);
        self.step();
      },
      "map-value-ind" => {
        self.pop(null);
        self.step();
      },
      _ => {
        if (self.type == "newline") {
          self.onKeyLine = false;
        }
        // all other values are errors
        let end = token.end;
        if (end != null) {
          end.push(self.sourceToken());
        } else {
          token.end = [self.sourceToken()];
        }
        if (self.type == "newline") {
          self.pop(null);
        }
      },
    }
    null
  }
}

/// `new Parser(onNewLine)`
///
/// @param onNewLine - If defined, called separately with the start position of
///   each new line (in `parse()`, including the start of input).
function new_parser(onNewLine: ((int) -> void throws never)?) -> Parser {
  Parser {
    onNewLine: onNewLine,
    atNewLine: true,
    atScalar: false,
    indent: 0,
    offset: 0,
    onKeyLine: false,
    stack: [],
    source: "",
    type: "",
    tokens: [],
  }
}
