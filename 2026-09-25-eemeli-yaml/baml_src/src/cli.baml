// Port of src/cli.ts
//
// Upstream `cli(stdin, done, argv)` reads a Node stream, writes through
// `console.log` / `console.dir` / `console.error`, and reports completion
// through a `done(error?)` callback. Here the core is a pure function:
// `yaml_cli_run(stdin, argv, importVisitor)` takes the whole stdin contents
// and returns what would have been written to stdout/stderr plus the value
// passed to `done()` (see `CliResult`), so tests can drive it without a
// process. `yaml_cli(args)` is the process entry point (the equivalent of
// upstream's `bin.js`), runnable as
//   baml run yaml_cli -- --json-args '{"args": ["--json"]}' < file.yaml
//
// `--visit <path>` does `(await import(resolve(path))).default` upstream.
// BAML cannot load code at runtime, so module loading is injected: callers
// pass an `importVisitor` function mapping the path to a `Visitor`. The
// `yaml_cli` entry point passes none, so there `--visit` fails with an error.

/// `help`
function cli_help() -> string {
  "yaml: A command-line YAML processor and inspector\n\nReads stdin and writes output to stdout and errors & warnings to stderr.\n\nUsage:\n  yaml          Process a YAML stream, outputting it as YAML\n  yaml cst      Parse the CST of a YAML stream\n  yaml lex      Parse the lexical tokens of a YAML stream\n  yaml valid    Validate a YAML stream, returning 0 on success\n\nOptions:\n  --help, -h    Show this message.\n  --json, -j    Output JSON.\n  --indent 2    Output pretty-printed data, indented by the given number of spaces.\n  --merge, -m   Enable support for \"<<\" merge keys.\n\nAdditional options for bare \"yaml\" command:\n  --doc, -d     Output pretty-printed JS Document objects.\n  --single, -1  Require the input to consist of a single YAML document.\n  --strict, -s  Stop on errors.\n  --visit, -v   Apply a visitor to each document (requires a path to import)\n  --yaml 1.1    Set the YAML version. (default: 1.2)"
}

/// `class UserError extends Error { code }`
class UserError {
  name: string
  message: string
  code: int
}

/// `UserError.ARGS`
function UserError_ARGS() -> int {
  2
}

/// `UserError.SINGLE`
function UserError_SINGLE() -> int {
  3
}

function new_user_error(code: int, message: string) -> UserError {
  UserError { name: "UserError", message: "Error: " + message, code: code }
}

/// Stand-in for `(await import(resolve(path))).default`.
type CliVisitorLoader = (string) -> Visitor throws unknown

/// The observable effects of one `cli()` run.
class CliResult {
  /// Values passed to `console.log` / `console.dir`, in order.
  stdout: unknown[]
  /// Values passed to `console.error`, in order.
  stderr: unknown[]
  /// Whether `done()` was called.
  done: bool
  /// The error passed to the first `done(error)` call, or null for `done()`.
  error: unknown?
}

function cli_done(res: CliResult, error: unknown?) -> CliResult {
  if (!res.done) {
    res.done = true;
    res.error = error;
  }
  res
}

// ─── node:util parseArgs ──────────────────────────────────────────────────

/// `parseArgs(...)` result: `values` (as fields) and `positionals`.
class CliArgs {
  positionals: string[]
  doc: bool?
  help: bool?
  indent: string?
  merge: bool?
  json: bool?
  single: bool?
  strict: bool?
  visit: string?
  yaml: string
}

/// Option table: long name → [short name, type].
function cli_option_type(name: string) -> string? {
  match (name) {
    "doc" => "boolean",
    "help" => "boolean",
    "indent" => "string",
    "merge" => "boolean",
    "json" => "boolean",
    "single" => "boolean",
    "strict" => "boolean",
    "visit" => "string",
    "yaml" => "string",
    _ => null,
  }
}

function cli_short_option(short: string) -> string? {
  match (short) {
    "d" => "doc",
    "h" => "help",
    "i" => "indent",
    "m" => "merge",
    "j" => "json",
    "1" => "single",
    "s" => "strict",
    "v" => "visit",
    _ => null,
  }
}

function cli_option_label(name: string) -> string {
  let short: string? = match (name) {
    "doc" => "d",
    "help" => "h",
    "indent" => "i",
    "merge" => "m",
    "json" => "j",
    "single" => "1",
    "strict" => "s",
    "visit" => "v",
    _ => null,
  };
  let base = if (short != null) { "-" + short + ", --" + name } else { "--" + name };
  if (cli_option_type(name) == "string") { base + " <value>" } else { base }
}

function cli_set_option(args: CliArgs, name: string, value: string?) -> null {
  match (name) {
    "doc" => { args.doc = true; },
    "help" => { args.help = true; },
    "indent" => { args.indent = value; },
    "merge" => { args.merge = true; },
    "json" => { args.json = true; },
    "single" => { args.single = true; },
    "strict" => { args.strict = true; },
    "visit" => { args.visit = value; },
    "yaml" => { args.yaml = value ?? "1.2"; },
    _ => {},
  }
  null
}

/// A strict `parseArgs({ args, allowPositionals: true, options })` for the
/// cli's fixed option table. Throws a `TypeError` like Node does
/// (ERR_PARSE_ARGS_UNKNOWN_OPTION, ERR_PARSE_ARGS_INVALID_OPTION_VALUE).
function cli_parse_args(argv: string[]) -> CliArgs throws JsError {
  let args = CliArgs { positionals: [], yaml: "1.2" };
  let n = argv.length();
  let i = 0;
  while (i < n) {
    let arg = argv[i];
    i += 1;
    if (arg == "--") {
      // everything after a bare `--` is positional
      while (i < n) {
        args.positionals.push(argv[i]);
        i += 1;
      }
      break;
    }
    if (arg.starts_with("--")) {
      let body = arg.slice(2, arg.length());
      let eq = body.index_of("=");
      let name = if (eq != null) { body.slice(0, eq) } else { body };
      let inline: string? = if (eq != null) { body.slice(eq + 1, body.length()) } else { null };
      let type_ = cli_option_type(name);
      if (type_ == null) {
        throw js_type_error("Unknown option '" + arg + "'. To specify a positional argument starting with a '-', place it at the end of the command after '--', as in '-- \"" + arg + "\"");
      }
      if (type_ == "boolean") {
        if (inline != null) {
          throw js_type_error("Option '" + cli_option_label(name) + "' does not take an argument");
        }
        cli_set_option(args, name, null);
      } else if (inline != null) {
        cli_set_option(args, name, inline);
      } else {
        let next = argv.at(i);
        if (next?.starts_with("-") ?? true) {
          throw js_type_error("Option '" + cli_option_label(name) + "' argument missing");
        }
        cli_set_option(args, name, next);
        i += 1;
      }
    } else if (arg.starts_with("-") && arg != "-") {
      // one or more short options, e.g. `-j`, `-dj`, `-i2`, `-i 2`
      let chars = arg.chars();
      let j = 1;
      while (j < chars.length()) {
        let c = chars[j];
        j += 1;
        let name = cli_short_option(c);
        if (name == null) {
          throw js_type_error("Unknown option '-" + c + "'. To specify a positional argument starting with a '-', place it at the end of the command after '--', as in '-- \"" + arg + "\"");
        }
        if (cli_option_type(name) == "string") {
          if (j < chars.length()) {
            cli_set_option(args, name, chars.slice(j, chars.length()).join(""));
          } else {
            let next = argv.at(i);
            if (next?.starts_with("-") ?? true) {
              throw js_type_error("Option '" + cli_option_label(name) + "' argument missing");
            }
            cli_set_option(args, name, next);
            i += 1;
          }
          break;
        }
        cli_set_option(args, name, null);
      }
    } else {
      args.positionals.push(arg);
    }
  }
  args
}

// ─── JSON representation of CST tokens ─────────────────────────────────────

/// The plain-object shape `JSON.stringify` sees for a CST token upstream:
/// absent fields omitted, `_id` dropped, and `fcStart` named `start` again.
function cli_token_json(tok: Token) -> map<string, unknown> {
  let o: map<string, unknown> = { "type": tok.type, "offset": tok.offset };
  let indent = tok.indent;
  if (indent != null) {
    o["indent"] = indent;
  }
  let props = tok.props;
  if (props != null) {
    o["props"] = props.map((t: Token) -> unknown { cli_token_json(t) });
  }
  let source = tok.source;
  if (source != null) {
    o["source"] = source;
  }
  let message = tok.message;
  if (message != null) {
    o["message"] = message;
  }
  let start = tok.start;
  if (start != null) {
    o["start"] = start.map((t: Token) -> unknown { cli_token_json(t) });
  }
  let fcStart = tok.fcStart;
  if (fcStart != null) {
    o["start"] = cli_token_json(fcStart);
  }
  let items = tok.items;
  if (items != null) {
    o["items"] = items.map((it: CollectionItem) -> unknown { cli_item_json(it) });
  }
  let value = tok.value;
  if (value != null) {
    o["value"] = cli_token_json(value);
  }
  let end = tok.end;
  if (end != null) {
    o["end"] = end.map((t: Token) -> unknown { cli_token_json(t) });
  }
  o
}

function cli_item_json(it: CollectionItem) -> map<string, unknown> {
  let o: map<string, unknown> = { "start": it.start.map((t: Token) -> unknown { cli_token_json(t) }) };
  let ek = it.explicitKey;
  if (ek != null) {
    o["explicitKey"] = ek;
  }
  let key = it.key;
  if (key != null) {
    o["key"] = cli_token_json(key);
  }
  let sep = it.sep;
  if (sep != null) {
    o["sep"] = sep.map((t: Token) -> unknown { cli_token_json(t) });
  }
  let value = it.value;
  if (value != null) {
    o["value"] = cli_token_json(value);
  }
  o
}

// ─── cli() ────────────────────────────────────────────────────────────────

/// `cli(stdin, done, argv)`, with `stdin` given as its full contents.
function yaml_cli_run(stdin: string, argv: string[], importVisitor: CliVisitorLoader?) -> CliResult {
  let res = CliResult { stdout: [], stderr: [], done: false };
  let args = cli_parse_args(argv) catch (e) {
    let err: JsError => {
      return cli_done(res, new_user_error(UserError_ARGS(), err.message));
    },
  };

  let mode: string? = args.positionals.at(0);
  let indent = js_to_number_or_nan(args.indent);

  // switch (opt.help || mode)
  if (args.help == true) {
    res.stdout.push(cli_help());
    return res;
  }

  if (mode == "lex") {
    let data: unknown[] = [];
    for (let tok in lex(stdin)) {
      if (args.json == true) {
        data.push(tok);
      } else {
        res.stdout.push(pretty_token(tok));
      }
    }
    if (args.json == true) {
      res.stdout.push(json_stringify_indent(data, indent));
    }
    return cli_done(res, null);
  }

  if (mode == "cst") {
    let data: unknown[] = [];
    for (let tok in new_parser(null).parse(stdin)) {
      if (args.json == true) {
        data.push(cli_token_json(tok));
      } else {
        res.stdout.push(tok);
      }
    }
    if (args.json == true) {
      res.stdout.push(json_stringify_indent(data, indent));
    }
    return cli_done(res, null);
  }

  if (mode == null || mode == "valid") {
    let visitor: Visitor? = null;
    let visitPath = args.visit;
    if (visitPath != null && visitPath != "") {
      if (importVisitor == null) {
        return cli_done(res, js_error("Cannot import " + json_quote(visitPath) + ": dynamic import is not supported in BAML"));
      }
      let loader: CliVisitorLoader = importVisitor;
      visitor = loader(visitPath) catch (e) {
        _ => {
          return cli_done(res, e);
        },
      };
    }
    let source = stdin;
    let lineCounter = new_line_counter();
    let composer = Composer.new(Options {
      version: args.yaml,
      merge: if (args.merge == true) { true } else { null },
    });
    let parser = new_parser(line_counter_fn(lineCounter));
    let hasDoc = false;
    let reqDocEnd = false;
    let data: unknown[] = [];
    for (let tok in parser.parse(source)) {
      composer.next(tok);
    }
    for (let doc in composer.end(false, -1)) {
      if (hasDoc && args.single == true) {
        let msg = "Input stream contains multiple documents";
        return cli_done(res, new_user_error(UserError_SINGLE(), msg));
      }
      for (let error in doc.errors) {
        prettify_error(source, lineCounter, error);
        if (args.strict == true || mode == "valid") {
          return cli_done(res, error);
        }
        res.stderr.push(error);
      }
      for (let warning in doc.warnings) {
        prettify_error(source, lineCounter, warning);
        res.stderr.push(warning);
      }
      if (visitor != null) {
        let v: Visitor = visitor;
        visit(doc, v) catch (e) {
          _ => {
            return cli_done(res, e);
          },
        };
      }
      if (mode == "valid") {
        doc.toJS(null);
      } else if (args.json == true) {
        data.push(doc);
      } else if (args.doc == true) {
        // Object.defineProperties(doc, { options/schema: non-enumerable }) only
        // affects console.dir's rendering; the Document itself is output.
        res.stdout.push(doc);
      } else {
        if (reqDocEnd) {
          res.stdout.push("...");
        }
        // indent ||= 2
        if (indent.is_nan() || indent == 0.0) {
          indent = 2.0;
        }
        let ind = cli_indent_int(indent);
        let str: string? = doc.toString(Options { indent: ind }) catch (e) {
          _ => {
            // done(error), but processing continues as upstream
            cli_done(res, e);
            null
          },
        };
        if (str != null) {
          res.stdout.push(if (str.ends_with("\n")) { str.slice(0, str.length() - 1) } else { str });
        }
      }
      hasDoc = true;
      reqDocEnd = !(doc.directives?.docEnd ?? false);
    }
    if (args.single == true && !hasDoc) {
      let msg = "Input stream contained no documents";
      return cli_done(res, new_user_error(UserError_SINGLE(), msg));
    }
    if (mode != "valid" && args.json == true) {
      // JSON.stringify calls Document#toJSON()
      let json = data.map((d: unknown) -> unknown {
        match (d) {
          let doc: Document => doc.toJSON(),
          _ => d,
        }
      });
      let out: unknown = if (args.single == true) { json.at(0) } else { json };
      res.stdout.push(json_stringify_indent(out, indent));
    }
    return cli_done(res, null);
  }

  let msg = "Unknown command: " + json_quote(mode ?? "");
  cli_done(res, new_user_error(UserError_ARGS(), msg))
}

/// `Number(opt.indent)`: NaN when the option is absent.
function js_to_number_or_nan(s: string?) -> float {
  if (s == null) {
    return baml.Float.nan();
  }
  js_to_number(s)
}

/// The `{ indent }` passed to `doc.toString()`: a non-integer or negative
/// value makes upstream's toString throw, which `-1` reproduces here.
function cli_indent_int(indent: float) -> int {
  if (indent.is_finite() && indent == indent.floor() && indent > 0.0) {
    indent.ifloor() catch (e) { _ => -1 }
  } else {
    -1
  }
}

// ─── bin.js ───────────────────────────────────────────────────────────────

/// Render a `console.log` / `console.dir` / `console.error` argument.
function cli_format(v: unknown) -> string {
  match (v) {
    let s: string => s,
    let t: Token => json_stringify_indent(cli_token_json(t), 2.0),
    let d: Document => "Document " + json_stringify_indent(d.toJSON(), 2.0),
    let e: YAMLError => e.name + " [" + e.code + "]: " + e.message,
    let e: JsError => e.name + ": " + e.message,
    _ => json_stringify(v),
  }
}

/// The `yaml` command (upstream `bin.js`): reads stdin, prints to
/// stdout/stderr, and exits with the UserError code (or 1 for other errors).
function yaml_cli(args: string[]) -> int {
  let f = baml.fs.open("/dev/stdin", "r") catch (e) {
    _ => baml.sys.panic("cannot open stdin"),
  };
  let stdin = f.text() catch (e) {
    _ => baml.sys.panic("cannot read stdin"),
  };
  let res = yaml_cli_run(stdin, args, null);
  for (let line in res.stdout) {
    baml.io.println(cli_format(line));
  }
  for (let line in res.stderr) {
    baml.io.eprintln(cli_format(line));
  }
  let code = match (res.error) {
    null => 0,
    let ue: UserError => {
      if (ue.code == UserError_ARGS()) {
        baml.io.eprintln(cli_help() + "\n");
      }
      baml.io.eprintln(ue.message);
      ue.code
    },
    _ => {
      baml.io.eprintln(cli_format(res.error));
      1
    },
  };
  if (code != 0) {
    baml.sys.exit(code);
  }
  code
}
