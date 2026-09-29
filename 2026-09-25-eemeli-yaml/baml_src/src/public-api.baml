// Port of src/public-api.ts
//
// Overloads like `parse(src, reviver?, options?)` / `parse(src, options?)`
// become one signature with explicit (nullable) arguments.

/// `EmptyStream extends Array<Document.Parsed>, ReturnType<Composer['streamInfo']>`
///
/// A JS array with extra properties has no BAML counterpart, so
/// `parseAllDocuments` returns this wrapper: `docs` holds the documents, and
/// `empty` + the stream info are set when there are none.
class ParsedDocuments {
  docs: Document[]
  empty: bool
  comment: string?
  directives: Directives?
  errors: YAMLError[]
  warnings: YAMLError[]
}

class ParseOptionsResolved {
  lineCounter: LineCounter?
  prettyErrors: bool
}

function parseOptions(options: ParseOptions) -> ParseOptionsResolved {
  let prettyErrors = options.prettyErrors != false;
  let lineCounter = options.lineCounter ?? (if (prettyErrors) { new_line_counter() } else { null });
  ParseOptionsResolved { lineCounter: lineCounter, prettyErrors: prettyErrors }
}

function line_counter_fn(lc: LineCounter?) -> ((int) -> void throws never)? {
  if (lc == null) {
    return null;
  }
  let l: LineCounter = lc;
  (offset: int) -> void {
    l.addNewLine(offset);
  }
}

/// Parse the input as a stream of YAML documents.
///
/// Documents should be separated from each other by `...` or `---` marker
/// lines.
///
/// @returns If an empty `docs` array is returned, it will be of type
///   EmptyStream and contain additional stream information.
function parseAllDocuments(source: string, options0: Options?) -> ParsedDocuments {
  let options = options0 ?? Options {};
  let po = parseOptions(options);
  let lineCounter = po.lineCounter;
  let parser = new_parser(line_counter_fn(lineCounter));
  let composer = Composer.new(options);
  let docs = composer.compose(parser.parse(source), false, -1);

  if (po.prettyErrors && lineCounter != null) {
    for (let doc in docs) {
      for (let e in doc.errors) {
        prettify_error(source, lineCounter, e);
      }
      for (let w in doc.warnings) {
        prettify_error(source, lineCounter, w);
      }
    }
  }

  if (docs.length() > 0) {
    return ParsedDocuments { docs: docs, empty: false, errors: [], warnings: [] };
  }
  let info = composer.streamInfo();
  ParsedDocuments {
    docs: docs,
    empty: true,
    comment: info.comment,
    directives: info.directives,
    errors: info.errors,
    warnings: info.warnings,
  }
}

/// Parse an input string into a single YAML.Document
function parseDocument(source: string, options0: Options?) -> Document {
  let options = options0 ?? Options {};
  let po = parseOptions(options);
  let lineCounter = po.lineCounter;
  let parser = new_parser(line_counter_fn(lineCounter));
  let composer = Composer.new(options);

  // `doc` is always set by compose.end(true) at the very latest
  let doc: Document? = null;
  for (let d in composer.compose(parser.parse(source), true, source.length())) {
    let cur = doc;
    if (cur == null) {
      doc = d;
    } else if (cur.options.logLevel != "silent") {
      let r = d.range ?? [0, 0, 0];
      cur.errors.push(YAMLParseError(
        [r[0], r[1]],
        "MULTIPLE_DOCS",
        "Source contains multiple documents; please use YAML.parseAllDocuments()",
      ));
      break;
    }
  }

  let res: Document = doc ?? Document.new(null, null, options);
  if (po.prettyErrors && lineCounter != null) {
    for (let e in res.errors) {
      prettify_error(source, lineCounter, e);
    }
    for (let w in res.warnings) {
      prettify_error(source, lineCounter, w);
    }
  }
  res
}

/// Parse an input string into JavaScript.
///
/// Only supports input consisting of a single YAML document; for
/// multi-document support you should use `YAML.parseAllDocuments`. May throw
/// on error, and may log warnings using `console.warn`.
///
/// @param src - A string with YAML formatting.
/// @param reviver - A reviver function, as in `JSON.parse()`
/// @returns The value will match the type of the root value of the parsed
///   YAML document, so Maps become objects, Sequences arrays, and scalars
///   result in nulls, booleans, numbers and strings.
function parse(src_: string, reviver: Reviver?, options0: Options?) -> unknown {
  let options = options0 ?? Options {};
  let doc = parseDocument(src_, options);
  for (let warning in doc.warnings) {
    warn(doc.options.logLevel ?? "warn", warning.message);
  }
  if (doc.errors.length() > 0) {
    if (doc.options.logLevel != "silent") {
      throw doc.errors[0];
    } else {
      doc.errors = [];
    }
  }
  doc.toJS(options_assign(Options { reviver: reviver }, options))
}

/// `YAML.parse(src)` / `YAML.parse(src, options)`
function yaml_parse(src_: string) -> unknown {
  parse(src_, null, null)
}

/// Stringify a value as a YAML document.
///
/// @param replacer - A replacer array or function, as in `JSON.stringify()`
/// @returns Will always include `\n` as the last character, as is expected
///   of YAML documents.
///
/// (`options` may also be a number or string giving the indent, as in
/// `JSON.stringify`; here that is `indentArg`.)
function stringify(value: unknown, replacer: Replacer?, options0: Options?) -> string? {
  let options = options0;
  if (is_js_undefined(value)) {
    // `value === undefined` returns undefined unless keepUndefined
    if (!(options?.keepUndefined ?? false)) {
      return null;
    }
  }
  match (value) {
    let d: Document => {
      if (replacer == null) {
        return d.toString(options);
      }
    },
    _ => {},
  }
  Document.new(value, replacer, options).toString(options)
}

/// `stringify(value, replacer, indent: number | string)`
function stringify_indent(value: unknown, replacer: Replacer?, indentArg: int | string) -> string? {
  let n = match (indentArg) {
    let i: int => i,
    let s: string => s.length(),
  };
  let options: Options? = if (n < 1) { null } else if (n > 8) { Options { indent: 8 } } else { Options { indent: n } };
  stringify(value, replacer, options)
}

/// `YAML.stringify(value)`
function yaml_stringify(value: unknown) -> string {
  stringify(value, null, null) ?? ""
}
