// Port of src/parse/lexer.ts
//
// The original matches five sticky (`/y`) regular expressions at `lastIndex`.
// `baml.regex` has no sticky/`lastIndex` matching, and anchoring on a sliced
// suffix would cost O(n) per call (string slicing is O(index) in BAML), so each
// one is re-implemented as a hand-written scanner with identical semantics.
// The original pattern is quoted above each scanner.

function lex_is_empty(ch: string?) -> bool {
  match (ch) {
    null => true,
    " " => true,
    "\n" => true,
    "\r" => true,
    "\t" => true,
    _ => false,
  }
}

function CHAR_TAB() -> int { 9 }
function CHAR_LF() -> int { 10 }
function CHAR_CR() -> int { 13 }
function CHAR_SPACE() -> int { 32 }
function CHAR_HASH() -> int { 35 }
function CHAR_COLON() -> int { 58 }

/// `ch` is -1 for NaN
function lex_is_empty_char(ch: int) -> bool {
  ch == -1 || ch == 32 || ch == 10 || ch == 13 || ch == 9
}

/// `, [ ] { }`
function lex_is_flow_indicator_code(ch: int) -> bool {
  ch == 44 || ch == 91 || ch == 93 || ch == 123 || ch == 125
}

/// ' ,[]{}\n\r\t'
function lex_is_not_anchor_char(ch: string?) -> bool {
  match (ch) {
    null => true,
    "" => true,
    " " => true,
    "," => true,
    "[" => true,
    "]" => true,
    "{" => true,
    "}" => true,
    "\n" => true,
    "\r" => true,
    "\t" => true,
    _ => false,
  }
}

/// JS regex `\s`
function js_is_space_code(c: int) -> bool {
  c == 9 || c == 10 || c == 11 || c == 12 || c == 13 || c == 32 || c == 0xa0 || c == 0x1680 || (c >= 0x2000 && c <= 0x200a) || c == 0x2028 || c == 0x2029 || c == 0x202f || c == 0x205f || c == 0x3000 || c == 0xfeff
}

/// JS regex line terminators (what `.` does not match, and where `$` matches
/// in multiline mode)
function js_is_line_terminator(c: int) -> bool {
  c == 10 || c == 13 || c == 0x2028 || c == 0x2029
}

/// Splits an input `source` string into lexical YAML tokens,
/// i.e. smaller strings that are easily identifiable by `token_type()`.
///
/// Lexing starts always in a "stream" context.
///
/// In addition to slices of the original input, the following control
/// characters may also be emitted:
///
/// - `\x02` (Start of Text): A document starts with the next token
/// - `\x18` (Cancel): Unexpected end of flow-mode (indicates an error)
/// - `\x1f` (Unit Separator): Next token is a scalar value
/// - `\u{FEFF}` (Byte order mark): Emitted separately outside documents
function lex(source: string) -> string[] {
  let lexer = new_lexer(source);
  let end = lexer.src.len();
  let state = "stream";
  while (lexer.pos < end) {
    match (state) {
      "stream" => {
        state = lexer.stream();
      },
      "document" => {
        state = lexer.document();
      },
      "flow" => {
        state = lexer.flow();
      },
      _ => {},
    }
  }
  lexer.tokens
}

function new_lexer(source: string) -> Lexer {
  Lexer {
    src: src(source),
    flowKey: false,
    flowLevel: 0,
    indentNext: 0,
    indentValue: 0,
    pos: 0,
    tokens: [],
  }
}

class Lexer {
  /// Current input
  src: Src
  /// Flag noting whether the map value indicator : can immediately follow
  /// this node within a flow context.
  flowKey: bool
  /// Count of surrounding flow collection levels.
  flowLevel: int
  /// Minimum level of indentation required for next lines to be parsed as a
  /// part of the current scalar value.
  indentNext: int
  /// Indentation level of the current line.
  indentValue: int
  /// A pointer to `source`; the current position of the lexer.
  pos: int
  tokens: string[]

  function charAt(self, n: int) -> string? {
    self.src.ch(self.pos + n)
  }

  // ─── Regex replacements ───────────────────────────────────────────────────

  /// `/[-.]{3}(?=[ \n\r\t]|$)(?:([ \t]+)(#.*)?)?/y`
  /// Returns null on no match, else [line, spaces, comment].
  function matchDocMarker(self, at: int) -> string[]? {
    let s = self.src;
    let i = at;
    while (i < at + 3) {
      let c = s.code(i);
      if (c != 45 && c != 46) {
        return null;
      }
      i += 1;
    }
    let next = s.code(i);
    if (!(next == -1 || next == 32 || next == 10 || next == 13 || next == 9)) {
      return null;
    }
    let spStart = i;
    while (s.code(i) == 32 || s.code(i) == 9) {
      i += 1;
    }
    let spaces = "";
    let comment = "";
    if (i > spStart) {
      spaces = s.slice(spStart, i);
      if (s.code(i) == 35) {
        let cStart = i;
        while (i < s.len() && !js_is_line_terminator(s.code(i))) {
          i += 1;
        }
        comment = s.slice(cStart, i);
      }
    }
    return [s.slice(at, i), spaces, comment];
  }

  /// `/(%(?:[^ \t\n\r]|[ \t](?![\n\r#]))*)([ \t]*)(#.*)?$/my`
  /// Returns null on no match, else [line, directive, spaces, comment].
  function matchDirectiveLine(self, at: int) -> string[]? {
    let s = self.src;
    if (s.code(at) != 37) {
      return null;
    }
    let i = at + 1;
    while (i < s.len()) {
      let c = s.code(i);
      if (c != 32 && c != 9 && c != 10 && c != 13) {
        i += 1;
      } else if (c == 32 || c == 9) {
        let n = s.code(i + 1);
        if (n == 10 || n == 13 || n == 35) {
          break;
        }
        i += 1;
      } else {
        break;
      }
    }
    let directive = s.slice(at, i);
    let spStart = i;
    while (s.code(i) == 32 || s.code(i) == 9) {
      i += 1;
    }
    let spaces = s.slice(spStart, i);
    let comment = "";
    if (s.code(i) == 35) {
      let cStart = i;
      while (i < s.len() && !js_is_line_terminator(s.code(i))) {
        i += 1;
      }
      comment = s.slice(cStart, i);
    }
    if (i < s.len() && !js_is_line_terminator(s.code(i))) {
      return null;
    }
    return [s.slice(at, i), directive, spaces, comment];
  }

  /// `/([ \t]*)(#.*)?$/my`
  /// Returns null on no match, else [line, spaces, comment].
  function matchEmptyLineOrComment(self, at: int) -> string[]? {
    let s = self.src;
    let i = at;
    while (s.code(i) == 32 || s.code(i) == 9) {
      i += 1;
    }
    let spaces = s.slice(at, i);
    let comment = "";
    if (s.code(i) == 35) {
      let cStart = i;
      while (i < s.len() && !js_is_line_terminator(s.code(i))) {
        i += 1;
      }
      comment = s.slice(cStart, i);
    }
    if (i < s.len() && !js_is_line_terminator(s.code(i))) {
      return null;
    }
    return [s.slice(at, i), spaces, comment];
  }

  /// `/([|>][^\s#]*)([ \t]*)((?:.|\r(?!\n))*)$/my`
  /// Returns [line, header, spaces, comment]. Only called at `|` or `>`.
  function matchBlockScalarHeader(self, at: int) -> string[] {
    let s = self.src;
    let i = at + 1;
    while (i < s.len() && !js_is_space_code(s.code(i)) && s.code(i) != 35) {
      i += 1;
    }
    let header = s.slice(at, i);
    let spStart = i;
    while (s.code(i) == 32 || s.code(i) == 9) {
      i += 1;
    }
    let spaces = s.slice(spStart, i);
    let cStart = i;
    while (i < s.len()) {
      let c = s.code(i);
      if (c == 13) {
        if (s.code(i + 1) == 10) {
          break;
        }
        i += 1;
      } else if (js_is_line_terminator(c)) {
        break;
      } else {
        i += 1;
      }
    }
    let comment = s.slice(cStart, i);
    return [s.slice(at, i), header, spaces, comment];
  }

  /// ```
  /// /(?:(&[^\s,[\]{}]*|!<[^\s>]*>?|!(?:[0-9a-z-#;/?:@&=+$_.!~*'()]|%[0-9a-f]{2})*)
  ///    |([-?:])(?=[ \n\r\t]|$)|([-?:])(?=[,[\]{}]|$))([ \t]*)/iy
  /// ```
  /// Returns null on no match, else [full, tagOrAnchor, bsEmpty, bsInFlow, spaces]
  /// with "" for groups that did not participate.
  function matchIndicator(self, at: int) -> string[]? {
    let s = self.src;
    let c = s.code(at);
    let i = at;
    let tagOrAnchor = "";
    let bsEmpty = "";
    let bsInFlow = "";
    if (c == 38) {
      // &anchor
      i += 1;
      while (i < s.len()) {
        let d = s.code(i);
        if (js_is_space_code(d) || d == 44 || d == 91 || d == 93 || d == 123 || d == 125) {
          break;
        }
        i += 1;
      }
      tagOrAnchor = s.slice(at, i);
    } else if (c == 33 && s.code(at + 1) == 60) {
      // !<verbatim>
      i += 2;
      while (i < s.len() && !js_is_space_code(s.code(i)) && s.code(i) != 62) {
        i += 1;
      }
      if (s.code(i) == 62) {
        i += 1;
      }
      tagOrAnchor = s.slice(at, i);
    } else if (c == 33) {
      // !tag
      i += 1;
      while (i < s.len()) {
        let d = s.code(i);
        if (lex_is_tag_char(d)) {
          i += 1;
        } else if (d == 37 && lex_is_hex(s.code(i + 1)) && lex_is_hex(s.code(i + 2))) {
          i += 3;
        } else {
          break;
        }
      }
      tagOrAnchor = s.slice(at, i);
    } else if (c == 45 || c == 63 || c == 58) {
      let n = s.code(at + 1);
      if (n == -1 || n == 32 || n == 10 || n == 13 || n == 9) {
        bsEmpty = s.slice(at, at + 1);
      } else if (n == 44 || n == 91 || n == 93 || n == 123 || n == 125) {
        bsInFlow = s.slice(at, at + 1);
      } else {
        return null;
      }
      i += 1;
    } else {
      return null;
    }
    let spStart = i;
    while (s.code(i) == 32 || s.code(i) == 9) {
      i += 1;
    }
    return [s.slice(at, i), tagOrAnchor, bsEmpty, bsInFlow, s.slice(spStart, i)];
  }

  // ─── Lexer proper ─────────────────────────────────────────────────────────

  function continueScalar(self, offset: int) -> int {
    if (self.indentNext > 0) {
      let len = self.src.len();
      let indent = 0;
      while (offset + indent < len && self.src.code(offset + indent) == 32) {
        indent += 1;
      }
      let cc = if (offset + indent < len) { self.src.code(offset + indent) } else { -1 };
      if (cc == 13) {
        let next = self.src.code(indent + offset + 1);
        if (next == 10) {
          return offset + indent + 1;
        }
      }
      return if (cc == 10 || indent >= self.indentNext) { offset + indent } else { -1 };
    }
    if (self.matchDocMarker(offset) != null) { -1 } else { offset }
  }

  function stream(self) -> string {
    if (self.charAt(0) == BOM()) {
      self.count(1);
      return "stream";
    }

    // Directives
    let m = self.matchDirectiveLine(self.pos);
    if (m != null) {
      let line = m[0];
      let directive = m[1];
      let spaces = m[2];
      let comment = m[3];
      self.tokens.push(directive);
      if (spaces != "") {
        self.tokens.push(spaces);
      }
      if (comment != "") {
        self.tokens.push(comment);
      }
      self.pos += line.length();
      self.newline();
      return "stream";
    }

    // Comments and empty lines
    let m2 = self.matchEmptyLineOrComment(self.pos);
    if (m2 != null) {
      let line = m2[0];
      let spaces = m2[1];
      let comment = m2[2];
      if (spaces != "") {
        self.tokens.push(spaces);
      }
      if (comment != "") {
        self.tokens.push(comment);
      }
      self.pos += line.length();
      self.newline();
      return "stream";
    }

    self.tokens.push(DOCUMENT());
    self.lineStart()
  }

  function lineStart(self) -> string {
    let dmm = self.matchDocMarker(self.pos);
    if (dmm != null) {
      let line = dmm[0];
      let spaces = dmm[1];
      let comment = dmm[2];
      self.count(3);
      if (spaces != "") {
        self.tokens.push(spaces);
        self.pos += spaces.length();
      }
      if (comment != "") {
        self.tokens.push(comment);
        self.pos += comment.length();
      }
      self.newline();
      self.indentValue = 0;
      self.indentNext = 0;
      return if (line.starts_with("-")) { self.lineStart() } else { "stream" };
    }

    self.indentValue = self.spaces(false);
    if (self.indentNext > self.indentValue && !lex_is_empty(self.charAt(1))) {
      self.indentNext = self.indentValue;
    }
    while (true) {
      let ch = self.src.ch(self.pos);
      if (ch != "-" && ch != "?" && ch != ":") {
        break;
      }
      let next = self.src.ch(self.pos + 1);
      if (next != null && next != " " && next != "\n" && next != "\r" && next != "\t") {
        break;
      }
      self.tokens.push(ch ?? "");
      let start = self.pos;
      self.pos += 1;
      let sc = self.src.code(self.pos);
      while (sc == 32 || sc == 9) {
        self.pos += 1;
        sc = self.src.code(self.pos);
      }
      if (self.pos > start + 1) {
        self.tokens.push(self.src.slice(start + 1, self.pos));
      }
      self.indentNext = self.indentValue + 1;
      self.indentValue += self.pos - start;
    }
    "document"
  }

  function document(self) -> string {
    self.spaces(true);
    self.indicators();
    let ch = self.charAt(0);
    match (ch) {
      "#" => {
        self.toLineEnd();
        self.newline();
        self.lineStart()
      },
      "\n" => {
        self.newline();
        self.lineStart()
      },
      null => {
        self.newline();
        self.lineStart()
      },
      "{" => {
        self.count(1);
        self.flowKey = false;
        self.flowLevel = 1;
        "flow"
      },
      "[" => {
        self.count(1);
        self.flowKey = false;
        self.flowLevel = 1;
        "flow"
      },
      "}" => {
        // this is an error
        self.count(1);
        "document"
      },
      "]" => {
        // this is an error
        self.count(1);
        "document"
      },
      "*" => {
        self.until_not_anchor_char();
        "document"
      },
      "\"" => {
        self.quotedScalar("\"");
        "document"
      },
      "'" => {
        self.quotedScalar("'");
        "document"
      },
      "|" => {
        self.blockScalar();
        self.lineStart()
      },
      ">" => {
        self.blockScalar();
        self.lineStart()
      },
      _ => {
        if (ch == "\r" && self.charAt(1) == "\n") {
          self.count(2);
          return self.lineStart();
        }
        self.plainScalar();
        "document"
      },
    }
  }

  function flow(self) -> string {
    let nl = 0;
    let sp = 0;
    let indent = -1;
    let first = true;
    while (first || nl + sp > 0) {
      first = false;
      nl = self.newline();
      if (nl > 0) {
        sp = self.spaces(false);
        indent = sp;
        self.indentValue = sp;
      } else {
        sp = 0;
      }
      sp += self.spaces(true);
    }
    let ch = self.charAt(0);
    if (
      indent != -1 &&
      indent < self.indentNext &&
      ch != "#" &&
      // Allowing for the terminal ] or } at the same (rather than greater)
      // indent level as the initial [ or { is technically invalid, but
      // failing here would be surprising to users.
      !(indent == self.indentNext - 1 && self.flowLevel == 1 && (ch == "]" || ch == "}"))
    ) {
      // this is an error
      self.flowLevel = 0;
      self.tokens.push(FLOW_END());
      return self.lineStart();
    }
    if (indent == 0) {
      if (self.matchDocMarker(self.pos) != null) {
        // this is an error
        self.flowLevel = 0;
        self.tokens.push(FLOW_END());
        return self.lineStart();
      }
    }
    while (ch == ",") {
      self.count(1);
      self.spaces(true);
      self.flowKey = false;
      ch = self.charAt(0);
    }
    if (self.indicators()) {
      ch = self.charAt(0);
    }
    match (ch) {
      "\n" => {},
      null => {},
      "#" => {
        self.toLineEnd();
      },
      "{" => {
        self.count(1);
        self.flowKey = false;
        self.flowLevel += 1;
      },
      "[" => {
        self.count(1);
        self.flowKey = false;
        self.flowLevel += 1;
      },
      "}" => {
        self.count(1);
        self.flowKey = true;
        self.flowLevel -= 1;
        return if (self.flowLevel != 0) { "flow" } else { "document" };
      },
      "]" => {
        self.count(1);
        self.flowKey = true;
        self.flowLevel -= 1;
        return if (self.flowLevel != 0) { "flow" } else { "document" };
      },
      "*" => {
        self.until_not_anchor_char();
      },
      "\"" => {
        self.flowKey = true;
        self.quotedScalar("\"");
      },
      "'" => {
        self.flowKey = true;
        self.quotedScalar("'");
      },
      ":" => {
        if (self.flowKey) {
          self.flowKey = false;
          self.count(1);
          self.spaces(true);
        } else {
          let next = self.charAt(1);
          if (lex_is_empty(next) || next == ",") {
            self.count(1);
            self.spaces(true);
          } else {
            self.plainScalar();
          }
        }
      },
      _ => {
        if (ch == "\r" && self.charAt(1) == "\n") {
          // break
        } else {
          self.flowKey = false;
          self.plainScalar();
        }
      },
    }
    "flow"
  }

  function indicators(self) -> bool {
    let hasIndicators = false;
    while (true) {
      let m = self.matchIndicator(self.pos);
      if (m == null) {
        break;
      }
      hasIndicators = true;
      let fm = m[0];
      let tagOrAnchor = m[1];
      let bsEmpty = m[2];
      let bsInFlow = m[3];
      let spaces = m[4];
      if (tagOrAnchor != "") {
        self.tokens.push(tagOrAnchor);
      } else if (self.flowLevel > 0) {
        self.tokens.push(if (bsEmpty != "") { bsEmpty } else { bsInFlow });
        if (self.flowKey) {
          self.flowKey = false;
        }
      } else if (bsEmpty != "") {
        self.tokens.push(bsEmpty);
        self.indentNext = self.indentValue + 1;
      } else {
        break;
      }
      if (spaces != "") {
        self.tokens.push(spaces);
      }
      self.pos += fm.length();
    }
    hasIndicators
  }

  function quotedScalar(self, quote: string) -> null {
    let s = self.src;
    let end = s.index_of_char(quote, self.pos + 1);
    if (quote == "'") {
      while (end != -1 && s.ch(end + 1) == "'") {
        end = s.index_of_char("'", end + 2);
      }
    } else {
      // double-quote
      while (end != -1) {
        let n = 0;
        while (s.ch(end - 1 - n) == "\\") {
          n += 1;
        }
        if (n % 2 == 0) {
          break;
        }
        end = s.index_of_char("\"", end + 1);
      }
    }
    // Only looking for newlines within the quotes
    // (qb = source.substring(0, end); note that substring(0, -1) is "")
    let qbLen = if (end < 0) { 0 } else { end };
    let nl = s.index_of_char("\n", self.pos);
    if (nl >= qbLen) {
      nl = -1;
    }
    if (nl != -1) {
      while (nl != -1) {
        let cs = self.continueScalar(nl + 1);
        if (cs == -1) {
          break;
        }
        nl = s.index_of_char("\n", cs);
        if (nl >= qbLen) {
          nl = -1;
        }
      }
      if (nl != -1) {
        // this is an error caused by an unexpected unindent
        end = nl - (if (s.ch(nl - 1) == "\r") { 2 } else { 1 });
      }
    }
    if (end == -1) {
      end = s.len();
    }
    self.toIndex(end + 1, false);
    null
  }

  function blockScalar(self) -> null {
    let s = self.src;
    let bsIndent = -1;
    let bsKeep = false;
    let m = self.matchBlockScalarHeader(self.pos);
    let line = m[0];
    let header = m[1];
    let spaces = m[2];
    let comment = m[3];
    for (let ch in header.chars()) {
      if (ch == "+") {
        bsKeep = true;
      } else if (ch > "0" && ch <= "9") {
        bsIndent = (baml.Int.parse(ch) catch (e) { _ => 1 }) - 1;
      }
    }
    self.tokens.push(header);
    if (spaces != "") {
      self.tokens.push(spaces);
    }
    if (comment != "") {
      self.tokens.push(comment);
    }
    self.pos += line.length();
    self.newline();

    let nl = self.pos - 1; // may be -1 if this.pos === 0
    let indent = 0;
    let i = self.pos;
    // loop: for (let i = this.pos; (cc = this.source.charCodeAt(i)); ++i)
    while (true) {
      let cc = s.code(i);
      if (cc <= 0) {
        break;
      }
      if (cc == 32) {
        indent += 1;
      } else if (cc == 10) {
        nl = i;
        indent = 0;
      } else if (cc == 13 && s.code(i + 1) == 10) {
        // skip
      } else {
        break;
      }
      i += 1;
    }
    if (indent >= self.indentNext) {
      if (bsIndent == -1) {
        self.indentNext = indent;
      } else {
        self.indentNext = bsIndent + (if (self.indentNext == 0) { 1 } else { self.indentNext });
      }
      let go = true;
      while (go) {
        let cs = self.continueScalar(nl + 1);
        if (cs == -1) {
          break;
        }
        nl = s.index_of_char("\n", cs);
        go = nl != -1;
      }
      if (nl == -1) {
        nl = s.len();
      }
    }

    // Trailing insufficiently indented tabs are invalid.
    // To catch that during parsing, we include them in the block scalar value.
    let j = nl + 1;
    let cc2 = s.code(j);
    while (cc2 == 32) {
      j += 1;
      cc2 = s.code(j);
    }
    if (cc2 == 9) {
      while (cc2 == 9 || cc2 == 32 || cc2 == 13 || cc2 == 10) {
        j += 1;
        cc2 = s.code(j);
      }
      nl = j - 1;
    } else if (!bsKeep) {
      while (true) {
        let k = nl - 1;
        let cc3 = s.code(k);
        if (cc3 == 13) {
          k -= 1;
          cc3 = s.code(k);
        }
        let lastChar = k; // Drop the line if last char not more indented
        while (cc3 == 32) {
          k -= 1;
          cc3 = s.code(k);
        }
        if (cc3 == 10 && k >= self.pos && k + 1 + indent > lastChar) {
          nl = k;
        } else {
          break;
        }
      }
    }
    self.tokens.push(SCALAR());
    self.toIndex(nl + 1, true);
    null
  }

  function plainScalar(self) -> null {
    let s = self.src;
    let inFlow = self.flowLevel > 0;
    let end = self.pos - 1;
    let i = self.pos - 1;
    let len = s.len();
    i += 1;
    while (i < len) {
      let cc = s.code(i);
      if (cc == 58) {
        let next = if (i + 1 < len) { s.code(i + 1) } else { -1 };
        if (lex_is_empty_char(next) || (inFlow && lex_is_flow_indicator_code(next))) {
          break;
        }
        end = i;
      } else if (lex_is_empty_char(cc)) {
        let next = if (i + 1 < len) { s.code(i + 1) } else { -1 };
        if (cc == 13) {
          if (next == 10) {
            i += 1;
            cc = 10;
            next = if (i + 1 < len) { s.code(i + 1) } else { -1 };
          } else {
            end = i;
          }
        }
        if (next == 35 || (inFlow && lex_is_flow_indicator_code(next))) {
          break;
        }
        if (cc == 10) {
          let cs = self.continueScalar(i + 1);
          if (cs == -1) {
            break;
          }
          i = if (i > cs - 2) { i } else { cs - 2 }; // to advance, but still account for ' #'
        }
      } else {
        if (inFlow && lex_is_flow_indicator_code(cc)) {
          break;
        }
        end = i;
      }
      i += 1;
    }
    self.tokens.push(SCALAR());
    self.toIndex(end + 1, true);
    null
  }

  function count(self, n: int) -> int {
    if (n > 0) {
      let s = self.src.slice(self.pos, self.pos + n);
      self.tokens.push(s);
      self.pos += n;
      return n;
    }
    0
  }

  function toIndex(self, i: int, allowEmpty: bool) -> int {
    let s = self.src.slice(self.pos, i);
    if (s != "") {
      self.tokens.push(s);
      self.pos += s.length();
    } else if (allowEmpty) {
      self.tokens.push("");
    }
    s.length()
  }

  function toLineEnd(self) -> int {
    let i = self.pos;
    let ch = self.src.code(i);
    while (ch > 0 && ch != 10) {
      i += 1;
      ch = self.src.code(i);
    }
    if (self.src.code(i - 1) == 13) {
      i -= 1;
    }
    self.toIndex(i, false)
  }

  function newline(self) -> int {
    let ch = self.src.ch(self.pos);
    if (ch == "\n") {
      self.count(1)
    } else if (ch == "\r" && self.charAt(1) == "\n") {
      self.count(2)
    } else {
      0
    }
  }

  function spaces(self, allowTabs: bool) -> int {
    let i = self.pos;
    let len = self.src.len();
    while (i < len) {
      let cc = self.src.code(i);
      if (cc != 32 && !(allowTabs && cc == 9)) {
        break;
      }
      i += 1;
    }
    let n = i - self.pos;
    if (n > 0) {
      let s = self.src.slice(self.pos, i);
      self.tokens.push(s);
      self.pos = i;
    }
    n
  }

  /// `this.until(isNotAnchorChar)` (the only caller)
  function until_not_anchor_char(self) -> int {
    let i = self.pos;
    let ch = self.src.ch(i);
    while (!lex_is_not_anchor_char(ch)) {
      i += 1;
      ch = self.src.ch(i);
    }
    self.toIndex(i, false)
  }
}

/// `[0-9a-z-#;/?:@&=+$_.!~*'()]` with the `i` flag
function lex_is_tag_char(d: int) -> bool {
  (d >= 48 && d <= 57) || (d >= 97 && d <= 122) || (d >= 65 && d <= 90) || d == 45 || d == 35 || d == 59 || d == 47 || d == 63 || d == 58 || d == 64 || d == 38 || d == 61 || d == 43 || d == 36 || d == 95 || d == 46 || d == 33 || d == 126 || d == 42 || d == 39 || d == 40 || d == 41
}

/// `[0-9a-f]` with the `i` flag
function lex_is_hex(d: int) -> bool {
  (d >= 48 && d <= 57) || (d >= 97 && d <= 102) || (d >= 65 && d <= 70)
}
