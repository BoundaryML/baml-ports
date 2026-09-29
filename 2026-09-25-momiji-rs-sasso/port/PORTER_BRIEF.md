# Porter brief (phase 2: function bodies)

You are one of ~35 porters working **in parallel** on a line-by-line port of
the Rust crate `sasso` (an SCSS→CSS compiler) to BAML. Your unit's assignment
is in `port/units/<UNIT>.md`.

## Read first, fully
1. `PORTING_GUIDE.md` — the binding contract (names, types, enums, errors,
   strings, numbers, collections, gotchas, workflow). Follow it exactly.
2. `.claude/skills/baml-core/SKILL.md` — the BAML language.
3. Skim `baml_src/ns_std/*.baml` — the Rust-std shim (`root.std.*`) you will
   call constantly (StrBuf, Tuple2.., Cell, chars/strings, numbers, paths, fs).

`port/INVENTORY.md` lists every Rust item with its BAML file/namespace and the
enum registry (C-LIKE vs DATA). The Rust sources are at
`port/upstream/sasso/src/`
(read-only). Work from the project root (the directory holding `baml.toml`).

## The job
Every item of every file is already declared in `baml_src/` (generated from
the Rust by `port/skeleton.py`); function bodies are stubs
`root.std.todo()` / `root.std.todo_throws()`, and the project compiles. For
every item your unit owns, replace the stub with a **line-by-line** port of
the Rust body: same statements in the same order, same control flow, same
local names, the Rust comments inside the body carried over. Nested `fn`s are
hoisted per the guide. Leave `// PORT: …` notes where BAML forces a change.
Do not port `#[cfg(test)]` code or test modules (a later phase does).

Before calling anything in another module, read its BAML declaration (grep the
target file, e.g. `grep -n 'function parse_list' baml_src/ns_selector/mod.baml`)
and match that signature exactly — even if its body is still a stub. The
skeleton's type choices are the shared contract; if one is wrong for an item
**you own**, fix its declaration (and report it). Never edit items you do not
own; if you need a change elsewhere, work around it locally and report it.

## Mechanics
* Shared BAML files (marked in your assignment): only through
  `python3 port/splice.py` (see guide §14). Never Edit/Write them directly.
* Files only you own: edit freely.
* Put scratch files under
  `<scratch>/work/<UNIT>/`.
* Check your work continuously:
  `python3 port/errors_for.py <file.baml> --fn name1,name2,...`
  (other porters' in-progress errors in shared files are not yours — filter
  by your function names). `baml check` compiles the whole project in seconds.
* Quick experiments: `baml run -e '<expr>'` from the project root, or a
  throwaway project (`baml init` in a scratch dir). Use `baml describe` for
  stdlib questions; don't guess.
* Do not run `baml fmt`. Do not create files under `baml_src/` other than
  your assigned ones. Do not touch `port/*.py`, the guide, or `ns_std`
  (report missing std helpers instead; you may write a local helper function in
  your own namespace).

**The BAML compiler needs a big thread stack on this project**: run it as `RUST_MIN_STACK=1073741824 baml check` / `RUST_MIN_STACK=1073741824 baml run …` (without it, it aborts with "thread has overflowed its stack" and prints no diagnostics). `port/errors_for.py` and `port/progress.sh` set this themselves and abort loudly if the checker crashes.

## Done means
* No `root.std.todo()` / `root.std.todo_throws()` left in the items you own
  (check with grep), and
* `python3 port/errors_for.py <your files> --fn <all your functions>` → 0
  errors (for an exclusive file: 0 errors in the whole file).

## Final message (your report back)
Keep it short and factual:
1. Unit id; items ported; anything left stubbed and why.
2. Declarations you changed (signature/field/type) that other modules use.
3. Cross-module problems you worked around or need someone else to fix
   (file, item, what).
4. Notable `// PORT:` deviations and any BAML bugs/limits you hit.
