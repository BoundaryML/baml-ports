# tests/doc/comments.ts → baml_src/tests/doc/comments.baml

## Results

`$B test -i "root::doc/comments::*"`: **85 passed, 0 failed, 0 skipped** (85 total).

All 81 upstream `test()`s are ported in order with the same names; the `for (const { name, src } of [...]) test(name, …)` loop in "line comments with leading tabs (#548)" is unrolled into its 4 tests (BAML can't generate tests in a loop).

Porting notes:
- `doc.value` / `doc.value[0]` / `doc.getPair(k)!.key` etc. are typed unions (`Node`, `SeqItem?`, `Pair?`), so every mutation goes through small narrowing helpers `tcom_scalar` / `tcom_seq` / `tcom_map` / `tcom_pair` (match-or-throw). This replaces TS generics + `!`.
- `expect(it).not.toHaveProperty('spaceBefore', true)` → `expect_true(it.spaceBefore != true, …)` (the helper has no value argument).
- `commentString: str => str.replace(/^/gm, '// ')` → `(str: string) -> string { str.replace_all(re("(?m)^"), "// ") }`.
- `_seq(a, b, …)` varargs → `_seq([a, b, …])`.

## Library fixes

None needed in `baml_src/src/`.

Test-infra fixes (shared `baml_src/tests/_expect.baml`):
- `t_match` with a class-instance `expected` (e.g. `toMatchObject(new Scalar('bar'))`) now compares only the expected instance's non-null fields, recursively with subset semantics (Jest semantics), instead of full `t_equal`. (Needed by clone.ts; noted here since it's shared.)
- `t_jsmap_entries` failed for every `JsMap` because reflection reports the generic class name as `JsMap<Pair>` / `JsMap<unknown>`; this broke all 13 `_map(...)` assertions in this file. Another agent landed the same fix (strip `<…>` in `t_class_name`) concurrently; I picked theirs up.

## BAML gaps / pain points (new)

1. **pain-point — multiline backtick literals trim their boundary newlines, so they can't stand in for JS template literals + the `source` tag.** Since #4914, `` `\n    a: 1\n  ` `` is `"a: 1"`: leading and trailing blank lines are dropped (and the text dedented). Upstream's `source\`…\`` keeps the final newline (and any extra leading/trailing blank lines), so `source(`…`)` as suggested in the guide is off by a trailing `"\n"` nearly everywhere. Worked around with `tcom_src(s) = source(s) + "\n"`, and plain `"…"` strings for sources with leading blank lines (`newlines as comments`) / `+ "\n\n"` for a trailing blank line (#277). There is no raw/verbatim multiline string form that keeps boundary whitespace.
   ```baml
   function f() -> string { `
       a
     ` }          // == "a", not "a\n"
   ```
2. **pain-point — reflected class names of generic classes include type arguments** (`reflect.AnyClass.name()` on a `JsMap<Pair>` returns `"JsMap<Pair>"`), so name-based dispatch must strip `<…>`.
