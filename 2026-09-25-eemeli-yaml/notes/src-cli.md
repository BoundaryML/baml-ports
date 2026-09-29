# src/cli.ts → baml_src/src/cli.baml

New library file porting `src/cli.ts` (the `yaml` command), together with the `bin.js` wrapper.

## Design

- **`yaml_cli_run(stdin: string, argv: string[], importVisitor: CliVisitorLoader?) -> CliResult`** is upstream's `cli(stdin, done, argv)`. It takes the whole stdin contents as a string instead of a Node stream.
  - It returns `CliResult { stdout: unknown[], stderr: unknown[], done: bool, error: unknown? }`: the values that would have gone to `console.log`/`console.dir` (stdout) and to `console.error` (stderr), and the argument of the first `done(...)` call.
  - Upstream can call `done(error)` and then keep going: a `toString()` failure calls `done(err)` and then `done()` again at the end. That flow is preserved, and only the first call is recorded.
- **`yaml_cli(args: string[]) -> int`** is the process entry point, standing in for `bin.js`:
  - It reads stdin with `baml.fs.open("/dev/stdin", "r").text()`. `baml.io.input` only reads a single line and returns `""` both at EOF and for an empty line, so it cannot read a whole stream.
  - It prints stdout/stderr through `baml.io.println`/`eprintln`. On a `UserError` it prints the help text (for ARGS errors) and the message, then exits with the error's code (2 = ARGS, 3 = SINGLE) via `baml.sys.exit`. Other errors exit with 1; upstream rethrows them.
  - Usage: `baml run yaml_cli -- --json-args '{"args": ["--json", "--indent", "2"]}' < in.yaml`. Generated function CLIs accept list parameters only through `--json-args`, so plain `yaml --json` style argv is not possible (`baml.sys.argv()` holds the raw `baml-cli run …` argv).
  - `console.dir(obj)` output is approximated by `cli_format`: CST tokens and Documents are printed as indented JSON, and errors as `name [code]: message`.
- **Parts of the port:**
  - `cli_parse_args` is a strict `node:util` `parseArgs` for the fixed option table. It handles long, `--opt=value`, short, grouped-short (`-dj`), `-i2` and `--`. Unknown options, value-less string options and values given to boolean options throw Node-like TypeErrors, which become `UserError(ARGS)`.
  - `UserError` is a class with `name`, `message` and `code`. `UserError.ARGS` and `.SINGLE` become `UserError_ARGS()` and `UserError_SINGLE()`.
  - `cli_help()` holds the help text.
  - `cli_token_json` / `cli_item_json` produce the plain-object view `JSON.stringify` sees for CST tokens: absent fields dropped, `_id` removed, and `fcStart` renamed back to `start`.
- **Modes:** all of `lex`, `cst`, `valid` and the default, and all options: `--json`, `--indent`, `--single`, `--strict`, `--doc`, `--yaml`, `--merge`, `--help`.
  - `--indent` follows JS `Number(opt.indent)`, with NaN when absent. JSON uses the JS clamp: below 1 means compact, above 10 is capped at 10.
  - YAML output applies `indent ||= 2`. A non-integer indent is passed as `-1`, so `toString` throws, as it does upstream.
- **`--visit`** (unportable as written): upstream does `(await import(resolve(path))).default`, and BAML has no dynamic code loading. It is emulated with the injected `importVisitor: (string) -> Visitor` loader; the tests provide one. `yaml_cli` passes `null`, so there `--visit` ends with `done(Error("Cannot import …: dynamic import is not supported in BAML"))`.
- `Object.defineProperties(doc, { options/schema: { enumerable: false } })` in `--doc` mode only affects `console.dir` rendering, so it is dropped.

## Library additions elsewhere

- `src/js.baml`: `json_stringify_indent(v, space: float)` / `json_stringify_gap(v, gap, indent)` implement `JSON.stringify(v, null, space)` pretty-printing (JS SerializeJSONObject/Array with a gap string, and `[]`/`{}` for empty containers).

## BAML gaps hit

- No dynamic import or module loading, so `--visit` needs dependency injection.
- `baml.io` has no "read all of stdin" (only line-wise `input()`, and it cannot tell EOF from an empty line); `/dev/stdin` via `baml.fs.open` works on Unix.
- Function entry points taking `string[]` need `--json-args`; you cannot pass a raw argv through to a function.
- `||` does not narrow its right operand (like `&&`, PORTING_NOTES #1).
