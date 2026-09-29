// Port of src/doc/directives.ts

function escape_tag_name(tn: string) -> string {
  let out = "";
  for (let ch in tn.chars()) {
    out += match (ch) {
      "!" => "%21",
      "," => "%2C",
      "[" => "%5B",
      "]" => "%5D",
      "{" => "%7B",
      "}" => "%7D",
      _ => ch,
    };
  }
  out
}

/// `{ version: '1.1' | '1.2' | 'next'; explicit?: boolean }`
class DirectivesYaml {
  version: string
  explicit: bool?
}

class Directives {
  /// The directives-end/doc-start marker `---`. If `null`, a marker may still
  /// be included in the document's stringified representation.
  yaml: DirectivesYaml
  tags: map<string, string>
  docStart: bool?
  /// The doc-end marker `...`.
  docEnd: bool
  /// Used when parsing YAML 1.1, where:
  /// > If the document specifies no directives, it is parsed using the same
  /// > settings as the previous document. If the document does specify any
  /// > directives, all directives of previous documents, if any, are ignored.
  atNextDocument: bool?

  function defaultYaml() -> DirectivesYaml {
    DirectivesYaml { explicit: false, version: "1.2" }
  }

  function defaultTags() -> map<string, string> {
    { "!!": "tag:yaml.org,2002:" }
  }

  /// `new Directives(yaml?, tags?)`
  function new(yaml: DirectivesYaml?, tags: map<string, string>?) -> Directives {
    let dy = Directives.defaultYaml();
    let y = DirectivesYaml {
      version: yaml?.version ?? dy.version,
      explicit: if (yaml?.explicit != null) { yaml?.explicit } else { dy.explicit },
    };
    let t = Directives.defaultTags();
    if (tags != null) {
      for (let k in tags.keys()) {
        t.set(k, tags[k]);
      }
    }
    Directives { yaml: y, tags: t, docEnd: false }
  }

  function clone(self) -> Directives {
    let copy = Directives.new(self.yaml, self.tags);
    copy.docStart = self.docStart;
    copy
  }

  /// During parsing, get a Directives instance for the current document and
  /// update the stream state according to the current version's spec.
  function atDocument(self) -> Directives {
    let res = Directives.new(self.yaml, self.tags);
    match (self.yaml.version) {
      "1.1" => {
        self.atNextDocument = true;
      },
      "1.2" => {
        self.atNextDocument = false;
        self.yaml = DirectivesYaml {
          explicit: Directives.defaultYaml().explicit,
          version: "1.2",
        };
        self.tags = Directives.defaultTags();
      },
      _ => {},
    }
    res
  }

  /// @param onError - May be called even if the action was successful
  /// @returns `true` on success
  function add(self, line: string, onError: (int, string, bool) -> void throws unknown) -> bool {
    if (self.atNextDocument ?? false) {
      self.yaml = DirectivesYaml { explicit: Directives.defaultYaml().explicit, version: "1.1" };
      self.tags = Directives.defaultTags();
      self.atNextDocument = false;
    }
    let parts = re("[ \\t]+").split(line.trim());
    let name = parts.shift();
    match (name) {
      "%TAG" => {
        if (parts.length() != 2) {
          onError(0, "%TAG directive should contain exactly two parts", false);
          if (parts.length() < 2) {
            return false;
          }
        }
        let handle = parts[0];
        let prefix = parts[1];
        self.tags.set(handle, prefix);
        true
      },
      "%YAML" => {
        self.yaml.explicit = true;
        if (parts.length() != 1) {
          onError(0, "%YAML directive should contain exactly one part", false);
          return false;
        }
        let version = parts[0];
        if (version == "1.1" || version == "1.2") {
          self.yaml.version = version;
          true
        } else {
          let isValid = re("^\\d+\\.\\d+$").has_match(version);
          onError(6, "Unsupported YAML version " + version, isValid);
          false
        }
      },
      _ => {
        onError(0, "Unknown directive " + (name ?? "undefined"), true);
        false
      },
    }
  }

  /// Resolves a tag, matching handles to those defined in %TAG directives.
  ///
  /// @returns Resolved tag, which may also be the non-specific tag `'!'` or a
  ///   `'!local'` tag, or `null` if unresolvable.
  function tagName(self, source: string, onError: (string) -> void throws unknown) -> string? {
    if (source == "!") {
      return "!"; // non-specific tag
    }

    if (source.at(0) != "!") {
      onError("Not a valid tag: " + source);
      return null;
    }

    if (source.at(1) == "<") {
      let verbatim = source.slice(2, source.length() - 1);
      if (verbatim == "!" || verbatim == "!!") {
        onError("Verbatim tags aren't resolved, so " + source + " is invalid.");
        return null;
      }
      if (source.at(source.length() - 1) != ">") {
        onError("Verbatim tags must end with a >");
      }
      return verbatim;
    }

    // `source.match(/^(.*!)([^!]*)$/s)`
    let bang = source.last_index_of("!") ?? 0;
    let handle = source.slice(0, bang + 1);
    let suffix = str_from(source, bang + 1);
    if (suffix == "") {
      onError("The " + source + " tag has no suffix");
    }
    let prefix = self.tags.get(handle);
    if (prefix != null && prefix != "") {
      let decoded = js_decode_uri_component(suffix) catch (error) {
        _ => {
          onError(js_string(error));
          return null;
        },
      };
      return prefix + decoded;
    }
    if (handle == "!") {
      return source; // local tag
    }

    onError("Could not resolve tag: " + source);
    null
  }

  /// Given a fully resolved tag, returns its printable string form,
  /// taking into account current tag prefixes and defaults.
  function tagString(self, tag: string) -> string {
    for (let handle in self.tags.keys()) {
      let prefix = self.tags[handle];
      if (tag.starts_with(prefix)) {
        return handle + escape_tag_name(str_from(tag, prefix.length()));
      }
    }
    if (tag.at(0) == "!") { tag } else { "!<" + tag + ">" }
  }

  function toString(self, doc: Document?) -> string {
    let lines: string[] = if (self.yaml.explicit ?? false) {
      ["%YAML " + (if (self.yaml.version != "") { self.yaml.version } else { "1.2" })]
    } else {
      []
    };

    let tagEntries = self.tags.keys();

    let tagNames: string[] = [];
    if (doc != null && tagEntries.length() > 0) {
      let tags: map<string, bool> = {};
      visit(doc.value, (key: VisitKey, node: Node | Pair | null, path: VisitPathItem[]) -> VisitResult {
        match (node) {
          let n: Node => {
            let t = n.tag;
            if (t != null && t != "") {
              tags.set(t, true);
            }
          },
          _ => {},
        }
        null
      });
      tagNames = tags.keys();
    }

    for (let handle in tagEntries) {
      let prefix = self.tags[handle];
      if (handle == "!!" && prefix == "tag:yaml.org,2002:") {
        continue;
      }
      if (doc == null || tagNames.some((tn: string) -> bool { tn.starts_with(prefix) })) {
        lines.push("%TAG " + handle + " " + prefix);
      }
    }
    lines.join("\n")
  }
}

/// JS `decodeURIComponent`: decodes `%XX` UTF-8 escape sequences, throwing a
/// URIError for malformed ones.
function js_decode_uri_component(s: string) -> string {
  if (!s.includes("%")) {
    return s;
  }
  let chars = s.chars();
  let out = "";
  let i = 0;
  while (i < chars.length()) {
    let ch = chars[i];
    if (ch != "%") {
      out += ch;
      i += 1;
      continue;
    }
    let bytes: int[] = [];
    while (i < chars.length() && chars[i] == "%") {
      if (i + 2 >= chars.length() + 0 && i + 2 > chars.length() - 1) {
        throw JsError { name: "URIError", message: "URI malformed" };
      }
      let h = js_digit_value(chars[i + 1].code_point_at(0) ?? 0);
      let l = js_digit_value(chars[i + 2].code_point_at(0) ?? 0);
      if (h > 15 || l > 15) {
        throw JsError { name: "URIError", message: "URI malformed" };
      }
      bytes.push(h * 16 + l);
      i += 3;
    }
    let u8 = baml.Uint8Array.from_array(bytes) catch (e) {
      _ => {
        throw JsError { name: "URIError", message: "URI malformed" };
      },
    };
    out += baml.String.from_utf8(u8) catch (e) {
      _ => {
        throw JsError { name: "URIError", message: "URI malformed" };
      },
    };
  }
  out
}
