# Conventions for porting goldmark code to BAML (read before writing code)

Source: `~/work-repos/goldmark-baml-port-src` (goldmark v2). Port: this repo. Toolchain: `bin/b` (wraps the locally built `baml-cli`). Never modify the BAML compiler/runtime.

## Commands

- `bin/b check 2>&1 | grep -v E0146` — compile-check the whole project (stdlib prints many E0146 warnings; filter them).
- `bin/b test 2>&1 | grep -v E0146` — run all `test` blocks. `bin/b test -i "root.extension::TestTable"` runs one.
- `bin/b run --function f -- f --arg value` — run a function; `bin/b run -e 'expr'` evaluates an expression.
- `bin/b describe baml.String --budget 200` — stdlib docs. Never guess stdlib names.

## Layout

- Go package `p` → directory `baml_src/ns_p/` → namespace `root.p`. Nested: `extension/ast` → `baml_src/ns_extension/ns_ast/` → `root.extension.ast`; `renderer/html` → `root.renderer.html`.
- One `.baml` per Go file, same base name (`table.go` → `table.baml`, `table_test.go` → `table_test.baml`).
- Always refer to other namespaces fully qualified: `root.ast.Node`, `root.text.Segment`, `root.util.is_space(c)`, `root.parser.Context`, `root.renderer.html.Config`. (Inside `ns_extension`, a bare `ast` is ambiguous; don't use it.)
- Test data lives at the same relative path as in Go, relative to the project root: `testdata/…`, `extension/testdata/…` (tests are run from the project root, so use `"extension/testdata/table.txt"`).

## Mapping rules (already used by the ported core — follow them)

- Names: Go `CamelCase` → BAML `snake_case` for functions/methods/fields (`NewTableParser` → `new_table_parser`, `IsTight` → `is_tight`); types keep CamelCase. Keep Go doc comments as `///` doc comments.
- `[]byte` → `uint8array`; `byte`/`rune` → `int`. No char literals: write byte values as ints with a comment where helpful (`124 // '|'`). `uint8array.slice(a, b)` copies (no aliasing).
- Helpers in `root.util`: `new_bytes()`, `bytes_of([..])`, `byte_array(c)`, `append_bytes(dst, src)`, `index_byte(b, c)`, `index_byte_from(b, from, c)`, `has_prefix(b, p)`, `has_prefix_at(b, at, "str")`, `bytes_index`, `bytes_contains`, `bytes_equal`, `bytes_replace_all`, `trim_space`, `trim_left_space`, `trim_right_space`, `is_space`, `is_punct`, `is_alpha_numeric`, `is_blank`, `to_rune(b, i)`, `utf8_decode_rune`, `utf8_encode_rune`, `BufWriter`, `new_buffer()`, `BytesFilter`, `prioritized(v, p)`. Read `baml_src/ns_util/util.baml` before adding helpers; put genuinely new stdlib-like helpers next to your code, not in util.
- Go value structs (Segment, Index, values) are BAML classes = references. Treat `Segment` as immutable: build a new one (`seg.with_stop(x)`, `root.text.new_segment_padding(..)`, or `root.text.Segment { start: .., stop: .., padding: .., force_newline: .. }`) instead of mutating fields.
- Multi-value returns → a small result class, or `T?` when the second value is an `ok` bool.
- Package-level `var`s/constants → zero-arg functions (`function kind_table() -> root.ast.NodeKind { "Table" }`). NodeKind is a string (the kind name). Context keys are unique strings (`"extension.footnoteList"`).
- AST nodes: copy the pattern in `baml_src/ns_ast/block.baml` / `inline.baml`: class with field `b: root.ast.BaseNode` (init with `root.ast.new_base_node()`), `implements root.ast.Node { base / kind / dump (+ overrides) }`, and `implements root.ast.BlockNode {}` or `implements root.ast.InlineNode {}`.
- Type switches / assertions: `match (n) { let t: root.extension.ast.Table => ..., _ => ... }`. Do NOT use `if (x is SomeInterface)` (crashes at runtime); `is` with a class type is fine but `match` is preferred. To test an interface-typed value against an unrelated interface, first widen to `unknown`: `let u: unknown = v; match (u) { let cb: I2 => .., _ => .. }`.
- NEVER compare nodes (or other class instances) with `==`/`!=` except against `null`: `==` is deep structural equality. Use `root.ast.same_node(a, b)` for identity.
- Parser interfaces (see `ns_parser/parser.baml`): `BlockParser { trigger() -> uint8array?; open(parent, reader, pc) -> OpenResult; do_continue(node, reader, pc) -> State; close(..); can_interrupt_paragraph(); can_accept_indented_line() }`, `InlineParser { trigger() -> uint8array; parse(parent, block, pc) -> root.ast.Node? }`, `CloseBlocker`, `ParagraphTransformer`, `ASTTransformer`, `Extension { parser_options(cfg) -> Option[] }`. States: `root.parser.CONTINUE() | root.parser.HAS_CHILDREN()` etc. `reader.peek_line()` returns `PeekedLine { line: uint8array?, segment }` (null line = Go nil); common idiom: `let pl = reader.peek_line(); let line = pl.line ?? root.util.new_bytes(); let segment = pl.segment;`. `reader.position()` → `ReaderPosition { line, segment }`.
- Renderer (see `ns_renderer/ns_html/html.baml`, especially `CommonMarkRenderer`): a node-renderer extension is a class implementing `root.renderer.Extension<root.renderer.html.Config>` whose `renderer_options(cfg)` returns `[root.renderer.html.with_node_renderers(map)]`. Render methods have signature `(self, w: root.util.BufWriter, source: uint8array, node: root.ast.Node, entering: bool, rc: root.renderer.Context) -> root.ast.WalkStatus`. Bind methods to typed locals before wrapping: `let r: root.renderer.NodeRendererFuncType = self.render_table; ... root.renderer.html.node_renderer_func(r)` (assigning a bound method directly into a field/map crashes the compiler). Writers: `root.renderer.html.context_text_writer(rc)` etc. Render functions return no error.
- Options: Go functional options become a class implementing the option interface (`interface TableOption { function set_table_option(self, c: TableConfig) -> void throws never }`); a Go option implementing several interfaces becomes one class with several `implements` blocks. `renderer.NewOptionFunc` → `root.renderer.new_option_func<root.renderer.html.Config>((c: root.renderer.html.Config) -> void { .. })`.
- Variadic `opts ...X` → `opts: X[] = []`. **Defaulted parameters must be passed by name at call sites**: `root.parser.new(options = [..])`, `root.renderer.html.new(opts = [..])`, `root.ast.new_link(dest, opts = [..])`, `root.testutil.do_test_case_file(m, file, t, no = root.testutil.parse_cli_case_arg())`.
- Tests: port each Go `TestXxx` to `test "TestXxx" { ... }`. Put the logic in a helper function that returns a `string[]` of failures and assert it is empty (asserting on test-block locals has known VM bugs). Use `root.testutil.new_recording_t()` + `root.testutil.do_test_case_file(...)` / `do_test_case(...)`, then `assert.equal(t.errors, [])` inside a helper-returned value. See `baml_src/commonmark_test.baml`. Parser is `root.parser.new(options = [root.parser.with_extensions([..])])`; renderer `root.renderer.html.new(opts = [root.renderer.html.with_xhtml(), root.renderer.html.with_extensions([..])])`; `root.testutil.new_markdown_to_string_func(p, r)`.

## Known BAML pitfalls (work around, and report NEW ones)

1. Narrowing does not flow into the right-hand side of `&&`/`||`: `x != null && x.len()` fails to compile. Use nested `if` or `let ok = if (x == null) { false } else { x.len() > 0 };`. (Narrowing *inside the body* of `if (a && x != null)` works.)
2. No narrowing on fields: `if (self.f != null) { self.f.g() }` fails; copy to a local first.
3. A loop-carried `T?` local reassigned inside the loop may lose narrowing; use non-optional locals where possible.
4. `let k = Enum.A;` infers the literal type `Enum.A`; reassigning `k = Enum.B` fails. Annotate: `let k: Enum = Enum.A;`.
5. A statement-initial `[` right after a `}` is parsed as an index expression. Bind array literals to a `let` first.
6. Keywords can't be identifiers: e.g. `generator`, `is`, `continue`, `match`, `type`, … rename (`gen`, `ps`, `do_continue`).
7. String escapes: there are NO unicode or hex escapes in BAML string literals. `"\uFFFD"`, `"\u{FFFD}"` and `"\x41"` are all silently kept verbatim (backslash included, no diagnostic). Put the literal character in the source (write such files from a script: some tool layers decode `\u` sequences before the file is written), or build it with `baml.String.from_code_points([..])` (throws).
8. Interface methods must declare `throws never`; a class implementing them must not call anything that can throw (e.g. `baml.String.from_code_points` throws) — use `catch_all (e) { _ => fallback }`.
9. Panics (`baml.sys.panic`, index out of bounds) cannot be caught.
10. `unknown` values from `pc.get(key)` must be matched: `match (pc.get(k)) { let v: MyClass => v, _ => null }`.

Record every new BAML bug / gap / pain point you hit (with a minimal repro if you can make one) — the final report should list them.
