# Guide: porting eemeli/yaml tests to BAML

This repo is a BAML port of eemeli/yaml (source: `~/work-repos/yaml-baml-port-src`). The library is in `baml_src/src/` (one `.baml` per upstream `.ts`, all in the root namespace). Tests go in `baml_src/tests/`, one `.baml` per upstream test file (e.g. `tests/doc/stringify.ts` → `baml_src/tests/doc/stringify.baml`).

## Toolchain

```sh
cd ~/work-repos/yaml-baml && source env.sh   # sets $B (baml-cli) and BAML_AGENT_SKILL_CHECK=off
./check.sh 80                                  # compile-check, first 80 diagnostic lines from this project
$B test -i "root::doc/stringify::*" 2>&1 | grep -v '^warning'   # run one file's tests
$B run -e 'root.yaml_stringify({"a": 1})'     # quick expression eval (use root. prefix)
```

Do NOT modify the BAML compiler/runtime. Do not use `git commit` (the coordinator commits). Never run `git stash`/`git checkout`/`git reset`.

## Test file shape

Wrap the whole file in a testset named after the upstream path without `tests/` and `.ts`, and nest `describe` blocks as `testset`s:

```baml
// Port of tests/doc/stringify.ts
testset "doc/stringify" {
  testset "some describe()" {
    test "some test()" {
      let doc = parseDocument("a: 1\n", null);
      expect_toBe(doc.toString(null), "a: 1\n")
    }
  }
}
```

- Test names must be unique within their testset. Keep upstream names verbatim where possible.
- All top-level `function`/`class` names share one namespace with the library and other test files: **prefix your helpers** with a short file-specific prefix (e.g. `tstr_` for doc/stringify).
- A `let` inside a testset is shared state for its tests (like a `describe` closure / `beforeAll`).
- Last statement in a test body has no trailing `;` (not required but conventional).
- Keep the order and number of tests the same as upstream. If a test cannot be ported, keep a `test` with the same name whose body documents why and is skipped, e.g. `// UNPORTABLE: uses vi.spyOn(console, 'warn')` plus a trivially-passing body — and count it as **skipped** in your report, not passed. Prefer porting the observable behaviour instead (see MockCalls below).

## Expect helpers (`baml_src/tests/_expect.baml`)

| vitest | BAML |
|---|---|
| `expect(a).toBe(b)` | `expect_toBe(a, b)` (numbers compare across int/float; objects by identity) |
| `expect(a).not.toBe(b)` | `expect_not_toBe(a, b)` |
| `expect(a).toEqual(b)` | `expect_toEqual(a, b)` (deep, JS semantics; `null` ≈ `undefined`) |
| `expect(a).toMatchObject(b)` | `expect_toMatchObject(a, b)` (partial; works on class instances via reflection) |
| `expect(a).toHaveLength(n)` | `expect_toHaveLength(a, n)` |
| `expect(a).toBeNull()` / `.toBeUndefined()` | `expect_toBeNull(a)` |
| `expect(a).not.toBeUndefined()` | `expect_not_toBeNull(a)` |
| `expect(s).toMatch(/re/)` | `expect_toMatch(s, "re")` (Rust/fancy-regex syntax) |
| `expect(o).toHaveProperty('k')` | `expect_toHaveProperty(o, "k")` / `expect_not_toHaveProperty` |
| `expect(x).toBeInstanceOf(YAMLMap)` | `expect_toBeInstanceOf(x, "YAMLMap")` (also "Map", "Set", "Array", "Scalar", "YAMLOMap", "MergeKey", "Error", "Date", "Uint8Array"...) |
| `expect(() => f()).toThrow('msg')` | `expect_toThrow(() -> unknown { f() }, "msg")` (substring match; `null` for any) |
| `expect(() => f()).toThrow(TypeError)` | `expect_toThrowNamed(() -> unknown { f() }, "TypeError")` |
| `expect(() => f()).not.toThrow()` | `expect_not_toThrow(() -> unknown { f() })` |
| condition | `expect_true(cond, "message")` |
| `vi.fn()` call recording | `let calls = mock_calls();` then in your callback `calls.record([a, b]);` and assert on `calls.calls` / `calls.count()` |

Lambdas passed to `expect_toThrow` must return `unknown`: write `() -> unknown { f(); null }` if `f` returns nothing useful.

`tests/_utils.baml` has `source(str)` (dedent helper; upstream's template tag — call it on a backtick string), `_map`, `_pair`, `_seq`, `_set`, `readArtifact(path)`, `tests_root()`.

## Library API mapping (JS → BAML)

- Module functions: `YAML.parse(src)` → `yaml_parse(src)`; `YAML.parse(src, reviver, opts)` → `parse(src, reviver, opts)` (reviver: `(key, value, ctx, holder) -> unknown`); `YAML.parseDocument(src, opts?)` → `parseDocument(src, opts_or_null)`; `YAML.parseAllDocuments(src, opts?)` → `parseAllDocuments(src, opts).docs` (returns a `ParsedDocuments` wrapper: `.docs`, `.empty`, and for an empty stream `.comment/.directives/.errors/.warnings`); `YAML.stringify(v)` → `yaml_stringify(v)`; `YAML.stringify(v, replacer, opts)` → `stringify(v, replacer, opts)` (returns `string?`); numeric/str indent arg → `stringify_indent(v, replacer, 4)`.
- Options: a single class `Options { … }` with every option field (camelCase, as upstream), all optional: `parseDocument(src, Options { version: "1.1", prettyErrors: false })`.
- `new Document(value, opts)` → `Document.new(value, null, opts)`; `new Document(v, replacer, opts)` → `Document.new(v, replacer, opts)`.
- `doc.toString(opts?)` → `doc.toString(opts_or_null)`; `String(doc)` → `doc.toString(null)`. `doc.toJS(opts?)` → `doc.toJS(opts_or_null)`; `doc.toJSON()`.
- `doc.contents` is called `doc.value` in this version of the library (so is upstream). `doc.createNode(v, replacer?, opts?)` → `doc.createNode(v, null, opts_or_null)`; `doc.createPair(k, v, opts?)`; `doc.createAlias(node, name?)`; `doc.get(k)`, `doc.set(k, v)`, `doc.getPair(k)`, `doc.clone()`, `doc.setSchema(version, opts)`.
- Nodes: `new Scalar(v)` → `Scalar.new(v)`; `new Alias('a')` → `Alias.new("a")`; `new Pair(k, v?)` → `Pair.new(k, v_or_null)`; `new YAMLMap(schema)` → `YAMLMap.new(schema, null)`; `new YAMLSeq(schema)` → `YAMLSeq.new(schema, null)`; `new YAMLSet(schema)` → `YAMLSet.new(schema)`. Node unions: `type Node = Scalar | YAMLMap | YAMLSeq | YAMLSet | Alias`. Use `match (x) { let m: YAMLMap => …, _ => … }` to narrow.
- `YAMLSeq` is not an Array: its elements are `seq.items` (`SeqItem = Node | Pair`); `seq.length()`, `seq.at(i)`, `seq.push(v)`, `seq.set(i, v)`, `seq.splice(start, deleteCount_or_null, [values])`, `seq.unshift([values])`. `YAMLMap.values` / `YAMLSet.values` are `JsMap` (`.keys()`, `.values()`, `.size()`, `.get(k)`, `.has(k)`); `map.get(k)`, `map.set(k, v)` (set a Pair with `map.set(pair, null)`), `map.setWithOptions(k, v, opts)`, `map.has`, `map.delete`, `map.getPair`, `map.keyOf(k, allowMissing)`, `map.size()`. `set.add(v)`.
- `node.toJS(doc, ctx)` exists on every node (pass `null`s); `node.toString(ctx, onComment, onChompKeep)` (pass `null`s). `node.clone()` on Scalar/Alias; `clone(schema_or_null)` on collections and Pair; `cloneNode(schema)` works on any `Node`.
- Class statics: `Scalar.PLAIN()`, `Scalar.QUOTE_DOUBLE()`, `YAMLMap.tagName()`, …
- Errors: thrown errors are `JsError { name, message }` (JS Error/TypeError/…) or `YAMLError { name: "YAMLParseError"|"YAMLWarning", code, message, pos, linePos }`. `doc.errors` / `doc.warnings` are `YAMLError[]`.
- `visit(node_or_doc, visitor)`: visitor is either a function `(key: VisitKey, node: Node | Pair | null, path: VisitPathItem[]) -> VisitResult` or `VisitorFns { Map: …, Pair: …, Scalar: …, Seq: …, Alias: …, Node: …, Value: …, Collection: … }`. `visit.BREAK/SKIP/REMOVE` → `visit_BREAK()/visit_SKIP()/visit_REMOVE()`. Return `null` for "continue".
- CST: `CST.visit` → `cst_visit`, `CST.stringify` → `cst_stringify`, `CST.createScalarToken` → `createScalarToken(value, ScalarTokenContext {…})`, `CST.setScalarValue` → `setScalarValue(tok, value, SetScalarValueContext{…}_or_null)`, `CST.resolveAsScalar` → `resolveAsScalar(tok, strict, onError_or_null)`, `CST.isCollection/isScalar` → `cst_is_collection/cst_is_scalar`, `new Parser()` → `new_parser(null)`, `new LineCounter()` → `new_line_counter()`, `lex(src)`. CST tokens are one class `Token` (fields `type, offset, indent, source, start, value, end, props, items`; a flow collection's opening `start` token is `fcStart`), items are `CollectionItem { start, key, sep, value, explicitKey }`.
- Schema/tags: a tag object is `Tag { tag, collection, default, format, identify, testFn (not "test"), resolve, resolveCollection, stringify, createNode, nodeClass }`. Custom tags: `Options { customTags: [Tag {...}, "timestamp", ...] }`. Built-in tags: `binary_tag()`, `omap_tag()`, `pairs_tag()`, `set_tag()`, `timestamp_tag()`, `merge_tag()`, `map_tag()`, `seq_tag()`, `string_tag()`, …
- JS values produced by `toJS`: `null`, `bool`, `int` (YAML ints) or `float` (YAML floats), `bigint` (with `intAsBigInt`), `string`, arrays `unknown[]`, plain objects `map<string, unknown>`, `JsMap<unknown>` (JS Map; `js_map()`), `JsSet` (JS Set; `js_set()`), `JsDate` (`js_date(ms)`), `uint8array` (`!!binary`), `JsSymbol`. Write expected objects as BAML map literals: `{ "a": 1, "b": [1, 2] }`. A JS Map literal: build with `let m = js_map(); m.set("a", 1);`. `undefined` is `null`.
- JS helpers: `js_string(v)` (String(v)), `json_stringify(v)`, `json_quote(s)`, `js_same(a, b)` (===), `js_identical`, `js_typeof`, `js_as_array`, `js_as_object`.

## BAML language gotchas (read these!)

- `x != null && x.field` does NOT narrow `x` on the right of `&&` (compile error). Use `x?.field`, nested `if`, or bind first. Field accesses never narrow: copy to a local (`let v = obj.f; if (v != null) { … }`). A local captured by any lambda loses narrowing in the whole function — re-bind (`let y: T = x;`).
- There is no `x!`. Use `x ?? fallback` or narrow.
- Empty arrays/maps/strings are falsy in `if` (unlike JS). Compare with `!= null` / `!= ""` explicitly.
- No implicit string coercion: `"a" + 1` fails; use `"a" + (1).to_string()` or backtick interpolation `` `a${n}` ``.
- `int / int` is integer division. `3 == 3.0` is false in plain BAML (`expect_toBe` handles it).
- A defaulted parameter must be passed by name; the library avoids defaults, pass `null` explicitly.
- `test`, `self`, `enum`, `const`, `then` etc. are reserved; don't use them as identifiers.
- Regexes: `re("pattern")` compiles with the backtracking (lookaround-capable) engine; `"str".replace(re("x"), "$0")` uses `$0`/`${1}` templates (not `$&`).
- A statement starting with `[` after a block is parsed as an index expression — bind arrays to a `let` first.
- Function-typed values must declare `throws` when stored in fields/aliases: `(string) -> string throws unknown`.

## Reporting

When done, write `notes/tests-<name>.md` (one per upstream test file you ported) with:
1. Pass/fail/skipped counts (from `$B test -i "root::<testset>::*"`), and a one-line cause for each failing test.
2. Any library bugs you fixed in `baml_src/src/` (file + one-line description). Keep such fixes minimal and targeted; run `./check.sh` after. Other agents are editing other test files concurrently, and may also touch `src/`: re-read a file right before editing it and never rewrite whole library files.
3. New BAML language/toolchain gaps, bugs or pain points you hit (with a minimal repro if you have one) that are not already in PORTING_NOTES.md.

## IMPORTANT: work in a private copy (added after launch)

All agents share one BAML project, and any compile error anywhere (e.g. a half-written test file) makes `$B test`/`$B check` fail for EVERYONE. So:

1. Make a private copy: `rsync -a --exclude .git ~/work-repos/yaml-baml/ /private/tmp/claude-501/yaml-baml-<yourprefix>/` and do all editing/compiling/testing there (`cd` into it; `source env.sh` works as-is).
2. Only copy a test file into `~/work-repos/yaml-baml/baml_src/tests/…` once it compiles cleanly in your copy (and delete any partial copy you already put in the shared tree NOW if it doesn't compile).
3. Library fixes: make them in your copy, and apply the same minimal edit to `~/work-repos/yaml-baml/baml_src/src/…` (re-read before editing; small targeted edits only). Occasionally re-sync `baml_src/src/` from the shared tree into your copy to pick up others' fixes.
4. Before finishing, run your tests once more in the shared tree to confirm the reported counts.
5. Note: BAML string literals only decode `\n \t \r \0 \b \v \f \\ \"`; `\u{…}`/`\uXXXX`/`\xNN` are kept VERBATIM (no error). Use `chr(codepoint)` (in `src/js.baml`) for other characters.
