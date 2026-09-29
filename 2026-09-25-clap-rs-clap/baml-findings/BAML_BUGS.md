# BAML issues found while porting clap

- **BAML version:** `baml wrapper 0.2.5` / `baml toolchain 0.20.2-nightly.20260923.a (nightly)`
- **Date:** 2026-09-28 (macOS, aarch64-apple-darwin)
- **Repros:** each repro is a tiny project `bugrepro/<dir>/{baml.toml, baml_src/...}` (scratch copy was at `/private/tmp/claude-501/-Users-bamlbot/12e0c878-f57d-47b4-b456-6a039c0a0511/scratchpad/bugrepro`, which is temporary). The full source of every repro is inlined below, so this file is self-contained.

To re-run a repro:

```sh
mkdir -p b01/baml_src && cd b01
printf '[package]\nname = "b01"\n' > baml.toml
# paste the snippet into baml_src/main.baml (other files at the paths shown)
export BAML_AGENT_SKILL_CHECK=off   # needed inside an AI-agent shell, see #33
baml run main                       # or `baml check` where shown
```

`baml.toml` is always just `[package]\nname = "<dir>"` unless shown. Outputs are pasted verbatim (only very long lines trimmed). The line `warning: code is unformatted; run \`baml fmt\`` in outputs is item #35 and can be ignored elsewhere.

Severity: **high** = silent wrong behaviour, **medium** = confusing error / blocks a natural design, **low** = clear error or cosmetic.

## Summary

| # | Title | Category | Severity | Status |
|---|---|---|---|---|
| 1 | `Array.includes`/`index_of` use identity for class instances; `==` is structural | bug | high | Reproduced |
| 2 | Unknown string escapes (`\x1b`, `\u{1b}`, `\u001b`) are kept literally | bug | high | Reproduced |
| 3 | `baml.json.to<T>` / `from_string<T>` into a union picks the first member that decodes | surprising semantics | high | Reproduced |
| 4 | `expr.field` resolves to a same-named static interface method when `expr` is not a variable | bug | high | Reproduced |
| 5 | `implements` through a type alias is accepted but not registered | bug | medium | Reproduced |
| 6 | Enum variants are not accessible through a type alias | bug | medium | Reproduced |
| 7 | Field default values unsupported, with garbled errors | diagnostics | medium | Reproduced |
| 8 | Fields and methods share one namespace | surprising semantics | low | Reproduced |
| 9 | `to_string` cannot be a plain method; must implement `baml.ToString` | surprising semantics | low | Reproduced |
| 10 | Enum-valued locals are inferred / narrowed to a single-variant literal type | bug | medium | Reproduced |
| 11 | Function types / interface methods require an explicit `throws` | diagnostics | low | Reproduced |
| 12 | A function type cannot be written as an explicit generic argument | bug | medium | Reproduced |
| 13 | A statement starting with `[` after a block statement is parsed as indexing | bug | high | Reproduced |
| 14 | `defer` is a reserved keyword, but the error does not say so | diagnostics | medium | Reproduced |
| 15 | A local named `env` is shadowed by the builtin `env.NAME` syntax | bug | high | Reproduced |
| 16 | Generic type aliases are not supported (garbled parse errors) | missing feature | medium | Reproduced |
| 17 | `interface P extends A` is unsupported | missing feature | medium | Reproduced |
| 18 | Static interface method not callable on a bounded generic parameter | bug | medium | Reproduced |
| 19 | Arrays are invariant | surprising semantics | low | Reproduced |
| 20 | Unions cannot implement interfaces; enums cannot declare methods inline | missing feature | low | Partially |
| 21 | No custom attributes (`@meta(...)`) | missing feature | low | Reproduced |
| 22 | `///` comments become reflected docstrings (including internal notes) | surprising semantics | medium | Reproduced |
| 23 | No top-level `let`; no isatty/terminal-detection API | missing feature | low | Reproduced |
| 24 | `ns_<digit>...` directories are silently not namespaces; their code merges into the parent namespace | bug | high | Reproduced |
| 25 | Static class methods are missing from `Package.functions()` / `get_function` | missing feature | medium | Reproduced |
| 26 | An `unreflect`ed type cannot be cast to an interface | missing feature | medium | Reproduced |
| 27 | `get_function<(unknown) -> string throws unknown>` on a `(E) -> string` function | surprising semantics | low | Not reproduced (works as designed) |
| 28 | Map-literal keys are literal strings; `call_any` then reports a confusing error | surprising semantics | medium | Reproduced |
| 29 | `reflect.Session` over `Package.current()`: types resolve, but `eval<T>` with the host's own `T` fails | bug | medium | Partially |
| 30 | Internal `!error` type leaks into user-facing messages | diagnostics | low | Reproduced |
| 31 | `baml.sys.shell` needs an explicit `null` options argument; stdout is `uint8array` | surprising semantics | low | Reproduced |
| 32 | Redundant `?.` is a hard error (E0004) | diagnostics | low | Reproduced |
| 33 | Every command (even `baml init`) fails in an agent environment without the agent skill | tooling | medium | Reproduced |
| 34 | `[package] version` / `description` in baml.toml warn on every command | tooling | low | Reproduced |
| 35 | "code is unformatted; run `baml fmt`" printed on every run/pack | tooling | low | Partially |
| 36 | E0097 "extraneous throws declaration" on functions that only `panic` | diagnostics | low | Reproduced |
| N1 | `baml run` / `baml pack` do not show compiler warnings | tooling | medium | Reproduced |
| N2 | Method call directly on an enum variant literal fails | bug | medium | Reproduced |
| N3 | `(self as I)` inside an interface gives `unresolved type: self` | diagnostics | low | Reproduced |
| N4 | Typed `_` binding not allowed in match arms | missing feature | low | Reproduced |

Of the 36 reported items: **32 reproduced**, **3 partially**, **1 not reproduced**. Plus 4 new findings (N1–N4); several other new details are folded into the item they relate to (e.g. #4 `b04d`, #10 `b10c`, #11 `n07`, #13 silent variant, #15 silent variant, #24 namespace merging, #28 root cause, #29 `eval<T>`, #35 `baml init` template, #36 `n10`).

## Severity: high

### 1. `Array.includes`/`index_of` use identity for class instances; `==` is structural

**Category:** bug · **Severity:** high · **Status:** Reproduced

**Summary.** Two structurally equal instances compare `true` with `==`, but `includes` / `index_of` do not find them (only the very same instance is found). No diagnostic.

**Repro, command and actual output.**

`bugrepro/b01`

```baml
class S { v: string }

function main() -> void {
    let a = S { v: "a" };
    let b = S { v: "a" };
    baml.io.println(`a == b: ${a == b}`);
    baml.io.println(`[a].includes(b): ${[a].includes(b)}`);
    baml.io.println(`[a].includes(a): ${[a].includes(a)}`);
    baml.io.println(`[a].index_of(b): ${[a].index_of(b) ?? -1}`);
}
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
a == b: true
[a].includes(b): false
[a].includes(a): true
[a].index_of(b): -1
```

**Expected.** `includes`/`index_of` use the same equality as `==` (`true` / `0`), or the docs state they use reference identity.

**Workaround.** Use a predicate: `xs.some((x) -> { x == b })` / `xs.find_index((x) -> { x == b })`.

*workaround* (`bugrepro/b01w`)

```baml
class S { v: string }
function main() -> void {
    let xs = [S { v: "a" }];
    let b = S { v: "a" };
    baml.io.println(`${xs.some((x) -> { x == b })} ${xs.find_index((x) -> { x == b }) ?? -1}`);
}
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
true 0
```


### 2. Unknown string escapes (`\x1b`, `\u{1b}`, `\u001b`) are kept literally

**Category:** bug · **Severity:** high · **Status:** Reproduced

**Summary.** `\x..` and both `\u` forms are not escape sequences in BAML; the backslash and the characters are kept verbatim (`"\x1b[0m"` has length 7 and prints as `\x1b[0m`). There is no error or warning, so ANSI escape codes silently break. `\t`/`\n` do work.

**Repro, command and actual output.**

`bugrepro/b02`

```baml
function main() -> void {
    let a = "\x1b[0m";
    let b = "\u{1b}";
    let c = "\u001b";
    let d = "\t";
    baml.io.println(`${a.length()} ${b.length()} ${c.length()} ${d.length()}`);
    baml.io.println(a);
}
```

```text
$ baml run main
7 6 6 1
\x1b[0m
```

**Expected.** Either support `\xHH` / `\u{...}` / `\uXXXX`, or reject unknown escapes with a compile error.

**Workaround.** Build the character from its code point: `string.from_code_points([27])`.

*workaround* (`bugrepro/b02w`)

```baml
function main() -> void {
    let esc = string.from_code_points([27]) catch (e) { _ => "" };
    let s = `${esc}[0m`;
    baml.io.println(`${s.length()}`);
}
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
4
```


### 3. `baml.json.to<T>` / `from_string<T>` into a union picks the first member that decodes

**Category:** surprising semantics · **Severity:** high · **Status:** Reproduced

**Summary.** Decoding `{"cmd":{"n":1}}` into `UA | UB | UC` yields `UA` because the empty class `UA` accepts any object (extra keys are ignored) and union members are tried in declaration order. This is documented in `baml describe baml.json.from_string` ("A union tries its members in declaration order and takes the first that decodes" / "keys in the object are ignored"), but it silently produces the wrong variant.

**Repro, command and actual output.**

`bugrepro/b03`

```baml
class UA {}
class UB {}
class UC { n: int }
type UU = UA | UB | UC
class Holder { cmd: UU }

function main() -> void {
    let j = baml.json.parse("{\"cmd\":{\"n\":1}}");
    let h = baml.json.to<Holder>(j);
    let which = match (h.cmd) { UA => "UA", UB => "UB", UC => "UC" };
    baml.io.println(which);
}
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
UA
```

**Expected.** Prefer the best/most specific match (e.g. the member that consumes the most keys), or reject ambiguous decodes, or at least offer a strict mode that rejects unknown keys.

**Workaround.** Give each union member a literal tag field (`kind: "a"`) so only one member can decode.

*workaround* (`bugrepro/b03w`)

```baml
class UA { kind: "a" }
class UB { kind: "b" }
class UC { kind: "c", n: int }
type UU = UA | UB | UC
class Holder { cmd: UU }

function main() -> void {
    let h = baml.json.from_string<Holder>("{\"cmd\":{\"kind\":\"c\",\"n\":1}}") catch (e) { _ => baml.sys.panic("decode") };
    let which = match (h.cmd) { UA => "UA", UB => "UB", UC => "UC" };
    baml.io.println(which);
}
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
UC
```


### 4. `expr.field` resolves to a same-named static interface method when `expr` is not a variable

**Category:** bug · **Severity:** high · **Status:** Reproduced

**Summary.** Class `Cli` has a field `command` and (through `implements Factory`) a static method `command()`. The type checker types `make().command` as `string` (the field), but at runtime the access yields the bound method, giving an `AccessError` (or a `VM internal error` when a method is called on it). Accessing the field through a local variable works. Note also the inconsistency: declaring the same method directly in the class body is rejected with E0012 (see `b04d`), but via an interface implementation it is accepted.

**Repro, command and actual output.**

*field access on a call result* (`bugrepro/b04`)

```baml
interface Factory {
    function command() -> string throws never;
}
class Cli {
    command: string,
    implements Factory {
        function command() -> string throws never { "static" }
    }
}
function make() -> Cli { Cli { command: "run" } }
function main() -> void {
    baml.io.println(make().command);
}
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
error: Traceback (most recent call last):
  File "baml_src/main.baml", line 12, in user.main
uncaught throw: baml.errors.AccessError {message: "Type mismatch: expected string, got <bound_method>"}
```

*calling a method on it -> VM internal error* (`bugrepro/b04b`)

```baml
interface Factory {
    function command() -> string throws never;
}
class Cli {
    command: string,
    implements Factory {
        function command() -> string throws never { "static" }
    }
}
function main() -> void {
    let n = (Cli { command: "run" }).command.length();
    baml.io.println(`${n}`);
}
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
error: Traceback (most recent call last):
  File "baml_src/main.baml", line 11, in user.main
  File "<builtin>/baml/string.baml", line 55, in baml.String.length
VM internal error: type error: expected string, got closure
```

*same name declared directly in the class is E0012* (`bugrepro/b04d`)

```baml
class Cli {
    command: string,
    function command() -> string { "static" }
}
function make() -> Cli { Cli { command: "run" } }
function main() -> void {
    baml.io.println(make().command);
}
```

```text
$ baml run main
main.baml:3:14-3:21 error[E0012]: name `Cli.command` defined 2 times as: field, method
  primary: duplicate method definition
  secondary main.baml:2:5-2:12: first defined as field here
error: cannot run: compilation errors found
```

**Expected.** `make().command` reads the field (as the type checker assumes), or the name clash is rejected at compile time.

**Workaround.** Bind the object to a variable first (`let c = make(); c.command`).

*workaround* (`bugrepro/b04w`)

```baml
interface Factory {
    function command() -> string throws never;
}
class Cli {
    command: string,
    implements Factory {
        function command() -> string throws never { "static" }
    }
}
function make() -> Cli { Cli { command: "run" } }
function main() -> void {
    let c = make();
    baml.io.println(c.command);
}
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
run
```


### 13. A statement starting with `[` after a block statement is parsed as indexing

**Category:** bug · **Severity:** high · **Status:** Reproduced

**Summary.** After `if (c) { ... }` on its own line, a next line starting with `[` is parsed as an index into the `if` expression. With a `void` block this is a confusing `cannot index into type void`; when the `if` yields an array, it **silently** indexes it (`b13t` returns `7`, i.e. `[7,8,9][0]`, instead of the array `[0]`).

**Repro, command and actual output.**

*confusing error* (`bugrepro/b13`)

```baml
function main() -> void {
    let c = true;
    let y = [2];
    if (c) { baml.io.println("c"); }
    [1].concat(y);
}
```

```text
$ baml run main
main.baml:4:5-5:8 error[E0008]: cannot index into type `void`
error: cannot run: compilation errors found
```

*silent wrong value* (`bugrepro/b13t`)

```baml
function pick(c: bool) -> unknown {
    if (c) { [7, 8, 9] } else { [4, 5, 6] }
    [0]
}
function main() -> void {
    baml.io.println(`${pick(true)}`);
}
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
7
```

**Expected.** A newline after a block-bodied statement ends the statement (as with Rust's block-like expression statements), or at least a lint.

**Workaround.** Put a `;` after the block (`if (c) { ... };`) or bind the array expression with `let`.

*workaround (`;` after the if)* (`bugrepro/b13u`)

```baml
function main() -> void {
    let c = true;
    let y = [2];
    if (c) { baml.io.println("c"); };
    [1].concat(y);
}
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
c
```


### 15. A local named `env` is shadowed by the builtin `env.NAME` syntax

**Category:** bug · **Severity:** high · **Status:** Reproduced

**Summary.** Minimal trigger: any local variable called `env` followed by a member access. `env.value` is resolved as the builtin environment-variable reference `baml.env.Ref { name: "value" }` instead of the local's field. In a typed context this gives a bare `mismatched types ... found baml.env.Ref` (`b15c`, and `string | baml.env.Ref` for the originally reported `if let env: C = ...` form, `b15`); in an untyped context (string interpolation) it **silently** prints `Ref { name: "value" }` (`b15d`). Using `env` alone (`b15b`) works.

**Repro, command and actual output.**

*original `if let env` form* (`bugrepro/b15`)

```baml
class C { value: string }
class Obj { maybe: C? }
function main() -> void {
    let obj = Obj { maybe: C { value: "v" } };
    let r = if let env: C = obj.maybe { env.value } else { "none" };
    baml.io.println(r);
}
```

```text
$ baml run main
main.baml:6:21-6:22 error[E0001]: mismatched types
  primary: expected `string`, found `string | baml.env.Ref`
error: cannot run: compilation errors found
```

*minimal* (`bugrepro/b15c`)

```baml
class C { value: string }
function main() -> void {
    let env = C { value: "v" };
    let s: string = env.value;
    baml.io.println(s);
}
```

```text
$ baml run main
main.baml:4:21-4:30 error[E0001]: mismatched types
  primary: expected `string`, found `baml.env.Ref`
error: cannot run: compilation errors found
```

*silent wrong value* (`bugrepro/b15d`)

```baml
class C { value: string }
function main() -> void {
    let env = C { value: "from local" };
    baml.io.println(`${env.value}`);
}
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
Ref { name: "value" }
```

*plain use of `env` is fine* (`bugrepro/b15b`)

```baml
function main() -> void {
    let env = "x";
    baml.io.println(env);
}
```

```text
$ baml run main
x
```

**Expected.** Local bindings shadow builtins, or naming a local `env` is rejected.

**Workaround.** Do not name locals `env` (e.g. `envv`, `e`).


### 24. `ns_<digit>...` directories are silently not namespaces; their code merges into the parent namespace

**Category:** bug · **Severity:** high · **Status:** Reproduced

**Summary.** `baml_src/ns_ex/ns_01_quick/main.baml` passes `baml check`, but no namespace `ex.01_quick` exists: `baml run ex.01_quick.main` and `baml pack ex.01_quick.main` say not found. Worse than reported: the file's declarations are **silently placed in the parent namespace `ex`** — `baml run ex.main` runs it, `reflect` lists `root.ex.main`, and a `main` in `ns_ex/lib.baml` would collide (E0011 duplicate function).

**Repro, command and actual output.**

`bugrepro/b24`

`baml_src/main.baml`:
```baml
function main() -> void { baml.io.println("root main"); }
```
`baml_src/ns_ex/ns_01_quick/main.baml`:
```baml
function main() -> void { baml.io.println("01_quick main"); }
```
`baml_src/ns_ex/ns_quick/main.baml`:
```baml
function main() -> void { baml.io.println("quick main"); }
```

```text
$ baml check; baml run ex.01_quick.main; baml run ex.quick.main; baml run ex.main; baml pack ex.01_quick.main -o /dev/null
    Finished checked 3 file(s) in 0s
warning: code is unformatted; run `baml fmt`
error: no runnable target `ex.01_quick.main` found. Did you mean one of:
  - ex (namespace)
  - ex.quick (namespace)
  - ex.quick.main
  - main
warning: code is unformatted; run `baml fmt`
quick main
warning: code is unformatted; run `baml fmt`
01_quick main
warning: code is unformatted; run `baml fmt`
error: function `ex.01_quick.main` not found. Did you mean one of:
  - ex.quick.main
  - main
```

*same ns_ex tree; root main lists functions via reflect* (`bugrepro/b24r`)

`baml_src/main.baml`:
```baml
function main() -> void { baml.io.println(`${reflect.Package.current().functions().keys()}`); }
```
`baml_src/ns_ex/ns_01_quick/main.baml`:
```baml
function main() -> void { baml.io.println("01_quick main"); }
```
`baml_src/ns_ex/ns_quick/main.baml`:
```baml
function main() -> void { baml.io.println("quick main"); }
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
["root.main", "root.ex.main", "root.ex.quick.main"]
```

Adding `baml_src/ns_ex/lib.baml` with `function main() -> void { baml.io.println("ex main"); }` to `b24` and running `baml check`:

```text
ns_01_quick/main.baml:1:10-1:14 error[E0011]: duplicate function `main`
  primary: duplicate function definition
  secondary lib.baml:1:10-1:14: first defined as function here
```

**Expected.** Either support namespaces whose name starts with a digit (e.g. quoted), or error on `ns_<invalid identifier>` directories.

**Workaround.** Rename to start with a letter (e.g. `ns_ex_01_quick`, as the clap port does).


## Severity: medium

### 5. `implements` through a type alias is accepted but not registered

**Category:** bug · **Severity:** medium · **Status:** Reproduced

**Summary.** `type P = root.ia.Parser` then `implements P {}` compiles cleanly (`b05a`: no diagnostics), but the class does not actually implement the interface; errors appear only at use sites (`unresolved name: parse`, `expected root.ia.Parser, found Cli`).

**Repro, command and actual output.**

*accepted silently* (`bugrepro/b05a`)

`baml_src/main.baml`:
```baml
type P = root.ia.Parser

class Cli {
    implements P {}
}
function main() -> void {}
```
`baml_src/ns_ia/lib.baml`:
```baml
interface Parser {
    function parse() -> Self throws never { baml.sys.panic("todo") }
}
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
```

*errors only at use sites* (`bugrepro/b05`)

`baml_src/main.baml`:
```baml
type P = root.ia.Parser

class Cli {
    implements P {}
}
function main() -> void {
    let c = Cli.parse();
    let p: root.ia.Parser = Cli {};
}
```
`baml_src/ns_ia/lib.baml`:
```baml
interface Parser {
    function parse() -> Self throws never { baml.sys.panic("todo") }
}
```

```text
$ baml check
main.baml:7:13-7:22 error[E0003]: unresolved name: `parse`
main.baml:8:29-8:35 error[E0001]: mismatched types
  primary: expected `root.ia.Parser`, found `Cli`
```

**Expected.** Either resolve the alias (register the implementation) or reject `implements <alias>` at the declaration.

**Workaround.** Use the full interface path in `implements root.ia.Parser {}`.

*workaround* (`bugrepro/b05w`)

`baml_src/main.baml`:
```baml
class Cli {
    implements root.ia.Parser {}
}
function main() -> void {
    let p: root.ia.Parser = Cli {};
    baml.io.println("ok");
}
```
`baml_src/ns_ia/lib.baml`:
```baml
interface Parser {
    function parse() -> Self throws never { baml.sys.panic("todo") }
}
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
ok
```


### 6. Enum variants are not accessible through a type alias

**Category:** bug · **Severity:** medium · **Status:** Reproduced

**Summary.** `type A = E` (same namespace or `root.x.E`) then `A.V` -> `unresolved name: V`. Static methods through a class alias (`K.make()`) do work.

**Repro, command and actual output.**

*minimal (same namespace)* (`bugrepro/b06b`)

```baml
enum E { V W }
type A = E
function main() -> void {
    let e: A = A.V;
}
```

```text
$ baml run main
main.baml:4:16-4:19 error[E0003]: unresolved name: `V`
error: cannot run: compilation errors found
```

*cross-namespace, with class alias for comparison* (`bugrepro/b06`)

`baml_src/main.baml`:
```baml
type A = root.x.E
type K = root.x.K

function main() -> void {
    baml.io.println(K.make());          // static method via class alias: OK
    let e = A.V;                        // enum variant via alias: error
    let e2 = root.x.E.V;                // full path: OK
}
```
`baml_src/ns_x/lib.baml`:
```baml
enum E { V W }
class K {
    function make() -> string { "k" }
}
```

```text
$ baml run main
main.baml:6:13-6:16 error[E0003]: unresolved name: `V`
error: cannot run: compilation errors found
```

**Expected.** `A.V` resolves to `E.V`.

**Workaround.** Use the full enum path (`root.x.E.V`).


### 7. Field default values unsupported, with garbled errors

**Category:** diagnostics · **Severity:** medium · **Status:** Reproduced

**Summary.** `short: string? = null` is a parse error, and the recovery produces nonsense: `field 'null' is missing a type annotation`, `duplicate field Arg.null`, and the placeholder text `expected Unexpected token in class body`.

**Repro, command and actual output.**

*`= null` defaults* (`bugrepro/b07`)

```baml
class Arg {
    short: string? = null
    long: string? = null
}
function main() -> void {}
```

```text
$ baml run main
main.baml:2:20-2:21 error[E0010]: unexpected token
  primary: expected `Unexpected token in class body`, found `'='`
main.baml:2:22-2:26 error[E0010]: invalid syntax
  primary: field 'null' is missing a type annotation
main.baml:3:19-3:20 error[E0010]: unexpected token
  primary: expected `Unexpected token in class body`, found `'='`
main.baml:3:21-3:25 error[E0012]: duplicate field `Arg.null`
  primary: duplicate field definition
  secondary main.baml:2:22-2:26: first defined as field here
main.baml:3:21-3:25 error[E0010]: invalid syntax
  primary: field 'null' is missing a type annotation
error: cannot run: compilation errors found
```

*`= 0` default* (`bugrepro/b07b`)

```baml
class Arg {
    count: int = 0
}
function main() -> void {}
```

```text
$ baml run main
main.baml:2:16-2:17 error[E0010]: unexpected token
  primary: expected `Unexpected token in class body`, found `'='`
main.baml:2:18-2:19 error[E0010]: unexpected token
  primary: expected `Unexpected token in class body`, found `integer`
error: cannot run: compilation errors found
```

**Expected.** A single clear error such as "field default values are not supported" (or support defaults).

**Workaround.** Provide a constructor/static `new()` function that fills defaults; make optional fields nullable and set them explicitly in class literals.


### 10. Enum-valued locals are inferred / narrowed to a single-variant literal type

**Category:** bug · **Severity:** medium · **Status:** Reproduced

**Summary.** `let s = E.A;` infers type `E.A`, so `s = E.B` is a type error, and a `match` on `s` reports the other arm as mismatched + unreachable. Even with an explicit `let s: E = E.A;`, after `s = E.B` flow-narrowing makes a following `match (s) { E.A => ..., E.B => ... }` a hard *type error* (`expected E.B, found E.A`) rather than at most an unreachable-arm warning (`b10c`).

**Repro, command and actual output.**

*reassignment* (`bugrepro/b10`)

```baml
enum E { A B }
function main() -> void {
    let s = E.A;
    s = E.B;
}
```

```text
$ baml run main
main.baml:4:9-4:12 error[E0001]: mismatched types
  primary: expected `E.A`, found `E.B`
error: cannot run: compilation errors found
```

*match on inferred local* (`bugrepro/b10b`)

```baml
enum E { A B }
function main() -> void {
    let s = E.A;
    let t = match (s) { E.A => "a", E.B => "b" };
    baml.io.println(t);
}
```

```text
$ baml run main
main.baml:4:37-4:40 error[E0001]: mismatched types
  primary: expected `E.A`, found `E.B`
main.baml:4:44-4:47 error[E0063]: unreachable arm
error: cannot run: compilation errors found
```

*annotated `E`, match after reassignment* (`bugrepro/b10c`)

```baml
enum E { A B }
function main() -> void {
    let s: E = E.A;
    s = E.B;
    baml.io.println(match (s) { E.A => "a", E.B => "b" });
}
```

```text
$ baml run main
main.baml:5:33-5:36 error[E0001]: mismatched types
  primary: expected `E.B`, found `E.A`
error: cannot run: compilation errors found
```

**Expected.** `let s = E.A` infers `E` (like other languages widen literals for mutable bindings); narrowing should not turn an exhaustive match into a type error.

**Workaround.** Annotate `let s: E` *and* avoid matching on the narrowed local directly, e.g. pass it through a function parameter of type `E`.

*workaround* (`bugrepro/b10w`)

```baml
enum E { A B }
function name(s: E) -> string { match (s) { E.A => "a", E.B => "b" } }
function main() -> void {
    let s: E = E.A;
    baml.io.println(name(s));
    s = E.B;
    baml.io.println(name(s));
}
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
a
b
```


### 12. A function type cannot be written as an explicit generic argument

**Category:** bug · **Severity:** medium · **Status:** Reproduced

**Summary.** `id<(int) -> int throws never>(...)` is a parse error; the parser treats `(int) -> ...` as a lambda (`expected lambda body '{', found '>'`). Same for `pkg.get_function<() -> string throws never>(name)`. (The originally reported text was `expected expression, found '->'`; in this build the message is the lambda-body one.)

**Repro, command and actual output.**

`bugrepro/b12`

```baml
function id<T>(x: T) -> T { x }
function main() -> void {
    let f = id<(int) -> int throws never>((x) -> { x + 1 });
}
```

```text
$ baml run main
main.baml:3:41-3:42 error[E0010]: unexpected token
  primary: expected `lambda body '{'`, found `'>'`
error: cannot run: compilation errors found
```

**Expected.** Function types are accepted as type arguments.

**Workaround.** Declare a type alias and pass the alias: `type IntFn = (int) -> int throws never; id<IntFn>(...)`.

*workaround* (`bugrepro/b12w`)

```baml
function id<T>(x: T) -> T { x }
type IntFn = (int) -> int throws never
function main() -> void {
    let f = id<IntFn>((x) -> { x + 1 });
    baml.io.println(`${f(1)}`);
}
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
2
```


### 14. `defer` is a reserved keyword, but the error does not say so

**Category:** diagnostics · **Severity:** medium · **Status:** Reproduced

**Summary.** A method or function named `defer` produces `function is missing a name` + `expected function name, found defer` without mentioning that `defer` is a keyword.

**Repro, command and actual output.**

*method* (`bugrepro/b14`)

```baml
class Guard {
    function defer(self) -> void {}
}
function main() -> void {}
```

```text
$ baml run main
main.baml:2:5-2:36 error[E0107]: function is missing a name
  primary: expected a name here
main.baml:2:14-2:19 error[E0010]: unexpected token
  primary: expected `function name`, found `defer`
error: cannot run: compilation errors found
```

*free function* (`bugrepro/b14b`)

```baml
function defer() -> void {}
function main() -> void {}
```

```text
$ baml run main
main.baml:1:1-1:28 error[E0107]: function is missing a name
  primary: expected a name here
main.baml:1:10-1:15 error[E0010]: unexpected token
  primary: expected `function name`, found `defer`
error: cannot run: compilation errors found
```

**Expected.** `defer` is a reserved keyword; choose another name (or allow keywords as method names).

**Workaround.** Rename (e.g. `defer_`, `deferred`).


### 16. Generic type aliases are not supported (garbled parse errors)

**Category:** missing feature · **Severity:** medium · **Status:** Reproduced

**Summary.** `type Resettable<T> = T | null` produces a cascade of parse errors including the misleading `a function type cannot declare generic parameters`.

**Repro, command and actual output.**

`bugrepro/b16`

```baml
type Resettable<T> = T | null
function main() -> void {}
```

```text
$ baml run main
main.baml:1:16-1:19 error[E0108]: could not parse type expression for type alias `Resettable`
  primary: unparseable type
main.baml:1:16-1:17 error[E0010]: invalid syntax
  primary: a function type cannot declare generic parameters
main.baml:1:16-1:17 error[E0010]: unexpected token
  primary: expected `'='`, found `'<'`
main.baml:1:20-1:21 error[E0010]: unexpected token
  primary: expected `function type parameter list`, found `'='`
main.baml:1:22-1:23 error[E0010]: unexpected token
  primary: expected `top-level declaration`, found `identifier`
main.baml:1:24-1:25 error[E0010]: unexpected token
  primary: expected `top-level declaration`, found `'|'`
main.baml:1:26-1:30 error[E0010]: unexpected token
  primary: expected `top-level declaration`, found `identifier`
error: cannot run: compilation errors found
```

**Expected.** Support generic aliases, or one clear "type aliases cannot be generic" error.

**Workaround.** Spell out `X | null` at each use site, or use a generic class wrapper.


### 17. `interface P extends A` is unsupported

**Category:** missing feature · **Severity:** medium · **Status:** Reproduced

**Summary.** `extends` on an interface is a raw parse error cascade that does not suggest `requires`. (Documented in `baml describe interface`: "Interfaces compose with `requires`, not `extends`".)

**Repro, command and actual output.**

`bugrepro/b17`

```baml
interface A {
    function a(self) -> int throws never;
}
interface P extends A {
    function p(self) -> int throws never;
}
function main() -> void {}
```

```text
$ baml run main
main.baml:4:13-4:20 error[E0010]: unexpected token
  primary: expected `'{'`, found `extends`
main.baml:4:21-4:22 error[E0010]: unexpected token
  primary: expected `top-level declaration`, found `identifier`
main.baml:4:23-4:24 error[E0010]: unexpected token
  primary: expected `top-level declaration`, found `'{'`
main.baml:5:41-5:42 error[E0010]: unexpected token
  primary: expected `function body`, found `';'`
main.baml:6:1-6:2 error[E0010]: unexpected token
  primary: expected `top-level declaration`, found `'}'`
error: cannot run: compilation errors found
```

**Expected.** Parser error mentioning `requires`.

**Workaround.** `interface P requires A { ... }`; inside default methods call `self.a()` directly. Note `(self as A).a()` fails with a misleading `unresolved type: self` (see N3).

*workaround* (`bugrepro/b17w`)

```baml
interface A {
    function a(self) -> int throws never;
}
interface P requires A {
    function p(self) -> int throws never { self.a() + 1 }
}
class K {
    implements A { function a(self) -> int throws never { 1 } }
    implements P {}
}
function main() -> void {
    baml.io.println(`${(K {}).p()}`);
}
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
2
```


### 18. Static interface method not callable on a bounded generic parameter

**Category:** bug · **Severity:** medium · **Status:** Reproduced

**Summary.** With `T extends Parser`, `T.parse()` -> `unresolved name: T.parse`.

**Repro, command and actual output.**

`bugrepro/b18`

```baml
interface Parser {
    function parse() -> Self throws never;
}
class Cli {
    implements Parser { function parse() -> Cli throws never { Cli {} } }
}
function run<T extends Parser>() -> T { T.parse() }
function main() -> void { run<Cli>(); }
```

```text
$ baml run main
main.baml:7:41-7:48 error[E0003]: unresolved name: `T.parse`
error: cannot run: compilation errors found
```

**Expected.** `T.parse()` resolves through the bound.

**Workaround.** `(T as Parser).parse()`.

*workaround* (`bugrepro/b18w`)

```baml
interface Parser {
    function parse() -> Self throws never;
}
class Cli {
    implements Parser { function parse() -> Cli throws never { Cli {} } }
}
function run<T extends Parser>() -> T { (T as Parser).parse() }
function main() -> void { run<Cli>(); baml.io.println("ok"); }
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
ok
```


### 22. `///` comments become reflected docstrings (including internal notes)

**Category:** surprising semantics · **Severity:** medium · **Status:** Reproduced

**Summary.** Every `///` line on a field is part of `reflect.class.Field.meta.docstring`. In the clap port, docstrings become user-visible `--help` text, so implementation notes written with `///` leak into program output. Design behaviour; documented here as a gotcha.

**Repro, command and actual output.**

`bugrepro/b22`

```baml
class Cli {
    /// Name of the person to greet
    /// NOTE: internal implementation note, not for users
    name: string,
}
function main() -> void {
    let cls = reflect.Package.current().get_class("Cli");
    for (let f in cls?.fields() ?? []) {
        baml.io.println(`${f.name}: ${f.meta.docstring ?? "<none>"}`);
    }
}
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
name: Name of the person to greet
NOTE: internal implementation note, not for users
```

**Expected.** (By design.)

**Workaround.** Use `//` for notes that must not be reflected.

*workaround* (`bugrepro/b22w`)

```baml
class Cli {
    /// Name of the person to greet
    // NOTE: internal implementation note, not for users
    name: string,
}
function main() -> void {
    let cls = reflect.Package.current().get_class("Cli");
    for (let f in cls?.fields() ?? []) {
        baml.io.println(`${f.name}: ${f.meta.docstring ?? "<none>"}`);
    }
}
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
name: <none>
```


### 25. Static class methods are missing from `Package.functions()` / `get_function`

**Category:** missing feature · **Severity:** medium · **Status:** Reproduced

**Summary.** `reflect.Package.current().functions()` lists only free functions (`root.free`, `root.main`); `get_function` returns `null` for `K.make` and `root.K.make`. (The doc comment of `functions()` says "Exported free-function signatures", so this is the documented scope, but there is no alternative API for static methods.)

**Repro, command and actual output.**

`bugrepro/b25`

```baml
class K {
    function make() -> string { "k" }
}
function free() -> string { "f" }
type Thunk = () -> string throws never
function main() -> void {
    let pkg = reflect.Package.current();
    baml.io.println(`${pkg.functions().keys()}`);
    for (let name in ["free", "root.free", "K.make", "root.K.make"]) {
        let f = pkg.get_function<Thunk>(name) catch_all (e) { _ => null };
        baml.io.println(`${name} found: ${f != null}`);
    }
}
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
["root.free", "root.main"]
free found: true
root.free found: true
K.make found: false
root.K.make found: false
```

**Expected.** A way to look up static methods by name (e.g. via `reflect.class.Type`).

**Workaround.** Wrap static methods in free functions and look those up.


### 26. An `unreflect`ed type cannot be cast to an interface

**Category:** missing feature · **Severity:** medium · **Status:** Reproduced

**Summary.** `type F = unreflect(t); (F as I).m()` -> `type F does not implement interface I`, even when the runtime type (`K`) does. Passing `F` to a generic `go<T extends I>()` fails as well (`b26w`).

**Repro, command and actual output.**

`bugrepro/b26`

```baml
interface I { function m() -> string throws never; }
class K { implements I { function m() -> string throws never { "K.m" } } }
function call_m(t: reflect.Type) -> string {
    type F = unreflect(t);
    (F as I).m()
}
function main() -> void {
    baml.io.println(call_m(reflect.Type.of<K>()));
}
```

```text
$ baml run main
main.baml:5:5-5:15 error[E0001]: type `F` does not implement interface `I`
error: cannot run: compilation errors found
```

*attempted workaround via generic bound: also rejected* (`bugrepro/b26w`)

```baml
interface I { function m() -> string throws never; }
class K { implements I { function m() -> string throws never { "K.m" } } }
function go<T extends I>() -> string { (T as I).m() }
function call_m(t: reflect.Type) -> string {
    type F = unreflect(t);
    go<F>()
}
function main() -> void {
    baml.io.println(call_m(reflect.Type.of<K>()));
}
```

```text
$ baml run main
main.baml:6:5-6:12 error[E0001]: mismatched types
  primary: expected `I`, found `F`
error: cannot run: compilation errors found
```

**Expected.** A checked (runtime) cast from an unreflected type to an interface, e.g. throwing if `t.implements(I)` is false.

**Workaround.** No direct workaround found; route through a free function looked up by name (`Package.get_function`).


### 28. Map-literal keys are literal strings; `call_any` then reports a confusing error

**Category:** surprising semantics · **Severity:** medium · **Status:** Reproduced

**Summary.** Root cause: in a map literal, a bare identifier key is a string literal, not a variable: `{ pname: "bob" }` has key `"pname"` (`b28x` prints `["pname"]`). There is no computed-key syntax (`{ [k]: v }`, `{ (k): v }` are parse errors). `reflect.call_any(greet, { pname: v })` then fails with `InvalidArgumentError { argument: "name", expected: string, got: never }` — i.e. a *missing* argument is reported as `got: never`, and the unexpected key `pname` is not mentioned. For an unknown key the error even reports the function type as `expected` (`b28x`, last line).

**Repro, command and actual output.**

`bugrepro/b28`

```baml
function greet(name: string) -> string { `hi ${name}` }
function main() -> void {
    let pname = "name";
    let r = reflect.call_any(greet, { pname: "bob" }) catch (e) { _ => `threw: ${e}` };
    baml.io.println(`${r}`);
}
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
threw: InvalidArgumentError { argument: "name", expected: string, got: never }
```

*what is going on* (`bugrepro/b28x`)

```baml
function greet(name: string) -> string { `hi ${name}` }
function main() -> void {
    let pname = "name";
    let m = { pname: "bob" };
    baml.io.println(`${m.keys()}`);
    let r1 = reflect.call_any(greet, { "name": "bob" }) catch (e) { _ => `threw: ${e}` };
    baml.io.println(`${r1}`);
    let r2 = reflect.call_any(greet, { name: "bob" }) catch (e) { _ => `threw: ${e}` };
    baml.io.println(`${r2}`);
    let r3 = reflect.call_any(greet, { "name": "bob", "extra": 1 }) catch (e) { _ => `threw: ${e}` };
    baml.io.println(`${r3}`);
}
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
["pname"]
hi bob
hi bob
threw: InvalidArgumentError { argument: "extra", expected: (string) -> string throws never, got: int }
```

**Expected.** Warn when a bare-identifier key shadows a local variable of type string; clearer `InvalidArgumentError` ("missing required parameter `name`" / "unknown parameter `pname`").

**Workaround.** Build the map imperatively: `let args: map<string, unknown> = {}; args.set(pname, v);`.

*workaround* (`bugrepro/b28w`)

```baml
function greet(name: string) -> string { `hi ${name}` }
function main() -> void {
    let pname = "name";
    let args: map<string, unknown> = {};
    args.set(pname, "bob");
    let r = reflect.call_any(greet, args) catch (e) { _ => `threw: ${e}` };
    baml.io.println(`${r}`);
}
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
hi bob
```


### 29. `reflect.Session` over `Package.current()`: types resolve, but `eval<T>` with the host's own `T` fails

**Category:** bug · **Severity:** medium · **Status:** Partially

**Summary.** The originally reported `unresolved type` did **not** reproduce: with `reflect.Session.new(packages = { "app": reflect.Package.current() })`, `app.Point { x: 3 }.x`, nested `app.ns.Inner`, and `function px(p: app.Point)` all resolve (only unqualified names like `double(2)` are unresolved, as expected). What does fail: `s.eval<Point>("app.Point { x: 9 }")` is rejected with "submission result has type `app.Point`, which is not a subtype of requested contract `Point`" — the same class seen through the session alias is not identified with the host's type. A runtime `if let p: Point = r` on an `eval<unknown>` result does match.

**Repro, command and actual output.**

`bugrepro/b29`

`baml_src/main.baml`:
```baml
class Point { x: int }
function main() -> void {
    let s = reflect.Session.new(packages = { "app": reflect.Package.current() }) catch (e) { _ => baml.sys.panic(`${e}`) };
    let a = s.eval<int>("app.Point { x: 3 }.x") catch (e) { _ => -1 };
    baml.io.println(`eval<int> => ${a}`);
    let pt = s.eval<Point>("app.Point { x: 9 }") catch (e) {
        let c: reflect.errors.CompilationError => { baml.io.println(`ERR ${c.message}`); Point { x: -1 } },
        _ => { baml.io.println(`ERR ${e}`); Point { x: -1 } },
    };
    baml.io.println(`eval<Point> => ${pt.x}`);
}
```
`baml_src/ns_ns/lib.baml`:
```baml
class Inner { y: int }
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
eval<int> => 3
ERR submission result has type `app.Point`, which is not a subtype of requested contract `Point`
eval<Point> => -1
```

**Expected.** `app.Point` from a session over the current package is the same type as the host's `Point`.

**Workaround.** `eval<unknown>` then narrow with `if let p: Point = r` (or re-decode through JSON).

*workaround* (`bugrepro/b29w`)

```baml
class Point { x: int }
function main() -> void {
    let s = reflect.Session.new(packages = { "app": reflect.Package.current() }) catch (e) { _ => baml.sys.panic(`${e}`) };
    let r = s.eval<unknown>("app.Point { x: 9 }") catch (e) { _ => null };
    let direct = if let p: Point = r { `${p.x}` } else { "not a Point" };
    let viaJson = baml.json.to<Point>(baml.json.from(r)) catch (e) { _ => Point { x: -1 } };
    baml.io.println(`match: ${direct}, via json: ${viaJson.x}`);
}
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
match: 9, via json: 9
```


### 33. Every command (even `baml init`) fails in an agent environment without the agent skill

**Category:** tooling · **Severity:** medium · **Status:** Reproduced

**Summary.** When `CLAUDECODE` or `AI_AGENT` is set, `baml init`, `check`, `run`, `fmt`, `describe` all hard-fail until `baml agent install` has been run. `--version` and `help` still work. With these variables unset it is only a warning. Because `init` itself fails, a fresh project cannot even be created without the override (or installing the skill first). Installing the skill locally (`baml agent install --project .`, writes `.claude/skills/baml-core` and `.agents/skills/baml-core`) fixes it.

```text
$ env | grep -E "^(CLAUDECODE|AI_AGENT)="; baml init / check / run main / fmt (no BAML_AGENT_SKILL_CHECK)
AI_AGENT=claude-code_2-1-283_agent
CLAUDECODE=1
$ baml init
error: the BAML agent skill is required but is not installed; run `baml agent install`, restart the agent, then retry; set BAML_AGENT_SKILL_CHECK=off to bypass this check
$ baml check
error: the BAML agent skill is required but is not installed; run `baml agent install`, restart the agent, then retry; set BAML_AGENT_SKILL_CHECK=off to bypass this check
$ baml run main
error: the BAML agent skill is required but is not installed; run `baml agent install`, restart the agent, then retry; set BAML_AGENT_SKILL_CHECK=off to bypass this check
$ baml fmt
error: the BAML agent skill is required but is not installed; run `baml agent install`, restart the agent, then retry; set BAML_AGENT_SKILL_CHECK=off to bypass this check
$ env -u CLAUDECODE -u AI_AGENT baml check
warning: no baml skill is installed; set it up with `baml agent install`
error: `/private/tmp/claude-501/-Users-bamlbot/12e0c878-f57d-47b4-b456-6a039c0a0511/scratchpad/bugrepro/b33b` doesn't look like it belongs to a BAML project — no `baml.toml` and no `baml_src/` directory found in it or its ancestors.
add a `baml_src/` directory with your `.baml` files, run `baml init`, or pass `--project <DIR>` to load an explicit source directory.
```

After `BAML_AGENT_SKILL_CHECK=off baml init` in `bugrepro/b33` and then `baml agent install --project .`:

```text
Claude Code:
  .claude/skills/baml-core/SKILL.md

Codex / OpenCode:
  .agents/skills/baml-core/SKILL.md
...
$ baml check
    Finished checked 1 file(s) in 0s
$ baml run main
warning: code is unformatted; run `baml fmt`
"hello from baml"
```

**Expected.** A warning (as for non-agent environments), or at least `init` and `describe` should work.

**Workaround.** `BAML_AGENT_SKILL_CHECK=off` / `--agent-skill-check warn`, or `baml agent install --project <dir>`.


## Severity: low

### 8. Fields and methods share one namespace

**Category:** surprising semantics · **Severity:** low · **Status:** Reproduced

**Summary.** A field `effects` and a method `effects()` cannot coexist (E0012). Common in Rust ports (getter named like the field).

**Repro, command and actual output.**

`bugrepro/b08`

```baml
class Style {
    effects: int,
    function effects(self) -> int { self.effects }
}
function main() -> void {}
```

```text
$ baml run main
main.baml:3:14-3:21 error[E0012]: name `Style.effects` defined 2 times as: field, method
  primary: duplicate method definition
  secondary main.baml:2:5-2:12: first defined as field here
error: cannot run: compilation errors found
```

**Expected.** (Design decision.) Clear error is shown.

**Workaround.** Rename the field (e.g. `effects_` / `_effects`) or the method (`get_effects`).


### 9. `to_string` cannot be a plain method; must implement `baml.ToString`

**Category:** surprising semantics · **Severity:** low · **Status:** Reproduced

**Summary.** Defining `function to_string(self)` on a class is E0140. The error message is clear and tells you what to do.

**Repro, command and actual output.**

`bugrepro/b09`

```baml
class Color {
    name: string,
    function to_string(self) -> string { self.name }
}
function main() -> void {}
```

```text
$ baml run main
main.baml:3:14-3:23 error[E0140]: `to_string` cannot be defined as a method on class `Color`; implement the `baml.ToString` interface instead
  primary: move this into `implements baml.ToString { ... }`
error: cannot run: compilation errors found
```

**Expected.** (Design decision.)

**Workaround.** `implements baml.ToString { function to_string(self) -> string throws never { ... } }`. This also makes template interpolation use it.

*workaround* (`bugrepro/b09w`)

```baml
class Color {
    name: string,
    implements baml.ToString {
        function to_string(self) -> string throws never { self.name }
    }
}
function main() -> void {
    baml.io.println((Color { name: "red" }).to_string());
    baml.io.println(`${Color { name: "blue" }}`);
}
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
red
blue
```


### 11. Function types / interface methods require an explicit `throws`

**Category:** diagnostics · **Severity:** low · **Status:** Reproduced

**Summary.** Function types in type aliases and fields need `throws ...` (E0151); interface methods need it too (E0170). Inconsistently, a function type in a *parameter* position is accepted without `throws` (`n07`). The built-in docs (`baml describe interface`) show interface methods without `throws` (`function label(self) -> string`), which then fails with E0170.

**Repro, command and actual output.**

*alias and field (E0151)* (`bugrepro/b11`)

```baml
type IntFn = (int) -> int
class Holder { f: (int) -> int }
function main() -> void {}
```

```text
$ baml run main
main.baml:1:14-1:26 error[E0151]: function type must declare an explicit `throws` clause; add `throws never` if calling it cannot throw
main.baml:2:19-2:31 error[E0151]: function type must declare an explicit `throws` clause; add `throws never` if calling it cannot throw
error: cannot run: compilation errors found
```

*interface method (E0170)* (`bugrepro/b11b`)

```baml
interface Named {
    function name(self) -> string;
}
function main() -> void {}
```

```text
$ baml run main
main.baml:2:14-2:18 error[E0170]: interface method `name` on `Named` must declare an explicit `throws` clause
error: cannot run: compilation errors found
```

*parameter position is accepted, alias is not* (`bugrepro/n07`)

```baml
function apply(f: (int) -> int, x: int) -> int { f(x) }   // accepted
type IntFn = (int) -> int                                 // E0151
function main() -> void {
    baml.io.println(`${apply((x) -> { x + 1 }, 1)}`);
}
```

```text
$ baml run main
main.baml:2:14-2:26 error[E0151]: function type must declare an explicit `throws` clause; add `throws never` if calling it cannot throw
error: cannot run: compilation errors found
```

**Expected.** Consistent rules (default to `throws never` or infer), and docs examples that compile.

**Workaround.** Always write `throws never` (or the actual error type) on function types and interface methods.


### 19. Arrays are invariant

**Category:** surprising semantics · **Severity:** low · **Status:** Reproduced

**Summary.** `Sub[]` is not accepted where `(Sub | Other)[]` is expected; `string[]` not accepted for `(PossibleValue | string)[]`. The error is clear, but it makes ports of Rust `impl Into<...>`/`IntoIterator` APIs noisy.

**Repro, command and actual output.**

`bugrepro/b19`

```baml
class Sub {}
class Other {}
class PossibleValue {}
function take(xs: (Sub | Other)[]) -> int { xs.length() }
function take2(xs: (PossibleValue | string)[]) -> int { xs.length() }
function main() -> void {
    let subs: Sub[] = [Sub {}];
    take(subs);
    let names: string[] = ["a"];
    take2(names);
}
```

```text
$ baml run main
main.baml:8:10-8:14 error[E0001]: mismatched types
  primary: expected `(Other | Sub)[]`, found `Sub[]`
main.baml:10:11-10:16 error[E0001]: mismatched types
  primary: expected `(string | PossibleValue)[]`, found `string[]`
error: cannot run: compilation errors found
```

**Expected.** (Sound for mutable arrays; a read-only view type or covariance for literals/temporaries would help.)

**Workaround.** Widen explicitly: `let w: (Sub | Other)[] = subs.map((s) -> { s });`, or pass an array literal (literals are checked against the expected type).

*workaround* (`bugrepro/b19w`)

```baml
class Sub {}
class Other {}
function take(xs: (Sub | Other)[]) -> int { xs.length() }
function main() -> void {
    let subs: Sub[] = [Sub {}];
    let widened: (Sub | Other)[] = subs.map((s) -> { s });
    baml.io.println(`${take(widened)} ${take([Sub {}])}`);
}
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
1 1
```


### 20. Unions cannot implement interfaces; enums cannot declare methods inline

**Category:** missing feature · **Severity:** low · **Status:** Partially

**Summary.** A union cannot implement an interface (E0138, clear message). Enums cannot contain `function` members (bare parse error). **However**, enums *can* implement interfaces via a top-level `implements I for Enum { ... }` block (`b20c`), which is a workable substitute for enum methods. Calling a method directly on a variant literal (`Mode.Fast.name()`) fails though (see N2).

**Repro, command and actual output.**

*union* (`bugrepro/b20b`)

```baml
interface Named { function name(self) -> string throws never; }
class A {}
class B {}
type AB = A | B
implements Named for AB {
    function name(self) -> string throws never { "ab" }
}
function main() -> void {}
```

```text
$ baml run main
main.baml:5:22-5:24 error[E0138]: cannot implement an interface for AB — the target must be a single concrete type
error: cannot run: compilation errors found
```

*enum inline method* (`bugrepro/b20a`)

```baml
enum Mode {
    Fast
    Slow
    function label(self) -> string { "x" }
}
function main() -> void {}
```

```text
$ baml run main
main.baml:4:5-4:13 error[E0010]: unexpected token
  primary: expected `'}'`, found `function`
main.baml:5:1-5:2 error[E0010]: unexpected token
  primary: expected `top-level declaration`, found `'}'`
error: cannot run: compilation errors found
```

*enum via top-level `implements ... for` works* (`bugrepro/b20c`)

```baml
interface Named { function name(self) -> string throws never; }
enum Mode { Fast Slow }
implements Named for Mode {
    function name(self) -> string throws never { "m" }
}
function main() -> void {
    let m: Mode = Mode.Fast;
    baml.io.println(m.name());
}
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
m
```

**Expected.** Enum inline-method error should point to `implements ... for`.

**Workaround.** Enums: `implements I for Enum { ... }`. Unions: wrap in a class holding the union.


### 21. No custom attributes (`@meta(...)`)

**Category:** missing feature · **Severity:** low · **Status:** Reproduced

**Summary.** Unknown attribute E0015 lists the valid attributes (clear), followed by a cascade of parse errors over the argument syntax.

**Repro, command and actual output.**

`bugrepro/b21`

```baml
class Cli {
    name: string @meta(short = "n")
}
function main() -> void {}
```

```text
$ baml run main
main.baml:2:18-2:29 error[E0015]: unknown attribute `@meta`; valid on a class field: `@description`, `@alias`, `@skip`, `@stream.done`, `@stream.must_exist`
  primary: unknown attribute
main.baml:2:30-2:31 error[E0010]: unexpected token
  primary: expected `')'`, found `'='`
main.baml:2:32-2:33 error[E0010]: unexpected token
  primary: expected `Unexpected token in class body`, found `'"'`
main.baml:4:27 error[E0010]: unexpected token
  primary: expected `Unclosed string literal`, found `EOF`
error: cannot run: compilation errors found
```

**Expected.** Just the E0015 error (no cascade), or user-defined attributes surfaced via `reflect.Meta.other`.

**Workaround.** Encode metadata in `///` docstrings (which are reflected, see #22) or `@description`.


### 23. No top-level `let`; no isatty/terminal-detection API

**Category:** missing feature · **Severity:** low · **Status:** Reproduced

**Summary.** Top-level `let` is rejected with a clear message. `baml describe isatty` / `tty` / `is_terminal` find nothing; `baml.io` only has `input/print/println/eprint/eprintln` and `baml.sys` has no terminal query, so color auto-detection (anstream/`ColorChoice::Auto`) cannot be ported.

**Repro, command and actual output.**

`bugrepro/b23`

```baml
let GREETING = "hi";
function main() -> void { baml.io.println(GREETING); }
```

```text
$ baml run main
main.baml:1:1-1:21 error[E0010]: top-level `let` bindings are not supported
  primary: move this binding into a function body
main.baml:2:43-2:51 error[E0003]: unresolved name: `GREETING`
error: cannot run: compilation errors found
```

```text
$ baml describe isatty
no symbol found: isatty
$ baml describe tty
no symbol found: tty
$ baml describe baml.io
function         baml.io.input                    <builtin>/baml/ns_io/io.baml:13
function         baml.io.print                    <builtin>/baml/ns_io/io.baml:23
function         baml.io.println                  <builtin>/baml/ns_io/io.baml:32
function         baml.io.eprint                   <builtin>/baml/ns_io/io.baml:41
function         baml.io.eprintln                 <builtin>/baml/ns_io/io.baml:50
interface        baml.io.Read                     <builtin>/baml/ns_io/read.baml:7
interface        baml.io.Write                    <builtin>/baml/ns_io/write.baml:9
```

**Expected.** (Constants: a `const` or top-level `let`.) A `baml.io.is_terminal(stream)` API.

**Workaround.** Constants: zero-arg functions. Terminal detection: env heuristics (`NO_COLOR`, `CLICOLOR_FORCE`, `TERM`) via `baml.env.get`.


### 27. `get_function<(unknown) -> string throws unknown>` on a `(E) -> string` function

**Category:** surprising semantics · **Severity:** low · **Status:** Not reproduced (works as designed)

**Summary.** It does not silently return nothing: it throws `reflect.errors.CompilationError` ("`(E) -> string throws never` ... is not a subtype of requested contract `(unknown) -> string throws unknown`"), which is correct by parameter contravariance. It only looks like `null` if the error is swallowed with `catch_all`. Requesting `(E) -> string throws unknown` or `reflect.AnyFunction` works.

**Repro, command and actual output.**

`bugrepro/b27`

```baml
enum E { A B }
function show(e: E) -> string { "shown" }
type AnyToStr = (unknown) -> string throws unknown
type EToStr = (E) -> string throws unknown
function main() -> void {
    let pkg = reflect.Package.current();
    let f = pkg.get_function<AnyToStr>("show") catch (e) { _ => { baml.io.println(`threw: ${e}`); null } };
    baml.io.println(`as (unknown) -> string: ${if (f == null) { "null" } else { "found" }}`);
    let g = pkg.get_function<EToStr>("show") catch (e) { _ => { baml.io.println(`threw: ${e}`); null } };
    baml.io.println(`as (E) -> string: ${if (g == null) { "null" } else { "found" }}`);
    let h = pkg.get_function<reflect.AnyFunction>("show") catch (e) { _ => null };
    baml.io.println(`as reflect.AnyFunction: ${if (h == null) { "null" } else { "found" }}`);
}
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
threw: CompilationError { message: "function `show` has type `(E) -> string throws never`, which is not a subtype of requested contract `(unknown) -> string throws unknown`", diagnostics: [Diagnostic { code: "E0001", span: null, message: "function `show` has type `(E) -> string throws never`, which is not a subtype of requested contract `(unknown) -> string throws unknown`", severity: "error", pha …(trimmed)
as (unknown) -> string: null
as (E) -> string: found
as reflect.AnyFunction: found
```

**Expected.** (As is.)

**Workaround.** Request `reflect.AnyFunction` and call through `reflect.call_any`, or request the exact parameter type.


### 30. Internal `!error` type leaks into user-facing messages

**Category:** diagnostics · **Severity:** low · **Status:** Reproduced

**Summary.** An empty array literal inside one of several map literals in an unannotated array yields a type printed as `map<string, !error[]>`. (Also note that an array of map literals is typed as a *union of map types* rather than a unified map type.)

**Repro, command and actual output.**

`bugrepro/b30`

```baml
function takes(xs: map<string, int[]>[]) -> void {}
function main() -> void {
    let xs = [{ "a": [] }, { "b": [1] }, { "c": 1 }];
    takes(xs);
}
```

```text
$ baml run main
main.baml:3:22-3:24 error[E0155]: type annotations needed
full type: `unknown[]`
main.baml:4:11-4:13 error[E0001]: mismatched types
  primary: expected `map<string, int[]>[]`, found `(map<string, !error[]> | map<string, int[]> | map<string, int>)[]`
error: cannot run: compilation errors found
```

**Expected.** Error types should not be printed (show `unknown[]` or elide the secondary error).

**Workaround.** Annotate the variable (`let xs: map<string, int[]>[] = ...`).


### 31. `baml.sys.shell` needs an explicit `null` options argument; stdout is `uint8array`

**Category:** surprising semantics · **Severity:** low · **Status:** Reproduced

**Summary.** `options: ProcessOptions?` is a nullable but not an optional parameter, so `shell(cmd)` is `expected 2 argument(s), got 1`. `stdout`/`stderr` are `uint8array`.

**Repro, command and actual output.**

`bugrepro/b31`

```baml
function main() -> void {
    let out = baml.sys.shell("echo hi");
    baml.io.println(out.stdout);
}
```

```text
$ baml run main
main.baml:2:15-2:40 error[E0005]: expected 2 argument(s), got 1
main.baml:3:21-3:31 error[E0001]: mismatched types
  primary: expected `string`, found `uint8array`
error: cannot run: compilation errors found
```

**Expected.** Make `options` optional (`options?:`, like `Package.compile(files, packages?)`), maybe a `stdout_text()` helper.

**Workaround.** `baml.sys.shell(cmd, null)` and `string.from_utf8(out.stdout)`.

*workaround* (`bugrepro/b31w`)

```baml
function main() -> void {
    let out = baml.sys.shell("echo hi", null) catch (e) { _ => baml.sys.panic("shell failed") };
    let text = string.from_utf8(out.stdout) catch (e) { _ => "" };
    baml.io.println(text.trim());
}
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
hi
```


### 32. Redundant `?.` is a hard error (E0004)

**Category:** diagnostics · **Severity:** low · **Status:** Reproduced

**Summary.** `a?.b()?.c` where `b()` returns non-null is a compile error rather than a warning. The message is also slightly misleading ("`a?.b()` cannot be null" — it can, when `a` is null; the point is that `?.` short-circuits the whole chain, which `b32w` confirms).

**Repro, command and actual output.**

`bugrepro/b32`

```baml
class B { c: int }
class A { function b(self) -> B { B { c: 1 } } }
function main() -> void {
    let a: A? = A {};
    let x = a?.b()?.c;
}
```

```text
$ baml run main
main.baml:5:13-5:22 error[E0004]: did you mean `a?.b().c`? `a?.b()?.c` is unnecessary, because `a?.b()` cannot be null
error: cannot run: compilation errors found
```

**Expected.** A warning (or auto-fixable lint).

**Workaround.** Write `a?.b().c` (short-circuits the whole chain).

*workaround* (`bugrepro/b32w`)

```baml
class B { c: int }
class A { function b(self) -> B { B { c: 1 } } }
function main() -> void {
    let a: A? = null;
    let x = a?.b().c;
    baml.io.println(`${x ?? -1}`);
}
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
-1
```


### 34. `[package] version` / `description` in baml.toml warn on every command

**Category:** tooling · **Severity:** low · **Status:** Reproduced

**Summary.** Standard package metadata keys are "unrecognized" and produce two warnings on every `check`/`run`/`pack`.

**Repro, command and actual output.**

`bugrepro/b34`

`baml.toml`:
```toml
[package]
name = "b34"
version = "4.6.1"
description = "A CLI parser"
```
`baml_src/main.baml`:
```baml
function main() -> void {
    baml.io.println("hi");
}
```

```text
$ baml check; baml run main
warning: ignoring unrecognized key `version` in [package]
warning: ignoring unrecognized key `description` in [package]
    Finished checked 1 file(s) in 0s
warning: ignoring unrecognized key `version` in [package]
warning: ignoring unrecognized key `description` in [package]
hi
```

**Expected.** Accept common metadata keys (`version`, `description`, `authors`, ...), or warn once.

**Workaround.** Move them into comments.


### 35. "code is unformatted; run `baml fmt`" printed on every run/pack

**Category:** tooling · **Severity:** low · **Status:** Partially

**Summary.** The warning appears on every `baml run` and `baml pack` whenever any file is not `baml fmt`-clean (it disappears after formatting, so it is not unconditional), but `baml check` does *not* show it. Notably, the `main.baml` generated by `baml init` is itself unformatted (2-space indent; `baml fmt` changes it to 4), so a brand-new project warns on the first run.

**Repro, command and actual output.**

`bugrepro/b35`

```baml
function main() -> void {
  baml.io.println("hi")
}
```

```text
$ baml run main
warning: code is unformatted; run `baml fmt`
hi
```

`baml init` template before/after `baml fmt`:

```text
2c2
<   "hello from baml"
---
>     "hello from baml"
```

**Expected.** Show it in `check` (where diagnostics belong) rather than on every run, and make the `init` template fmt-clean.

**Workaround.** Run `baml fmt` (or `-q`).


### 36. E0097 "extraneous throws declaration" on functions that only `panic`

**Category:** diagnostics · **Severity:** low · **Status:** Reproduced

**Summary.** A function whose body only calls `baml.sys.panic` but declares `throws MyError` gets `warning[E0097]: extraneous throws declaration`. This also fires on an *interface implementation* whose signature mirrors the interface (`b36c`). It is only a warning and only visible in `baml check` — `baml run` does not print it (see N1). Related inconsistency: `throws unknown` on a function that throws a narrower type is E0097 as an *error* ("imprecise"), see `n10`.

**Repro, command and actual output.**

`bugrepro/b36`

```baml
class MyError { msg: string }
function todo() -> int throws MyError {
    baml.sys.panic("not implemented yet")
}
function main() -> void {}
```

```text
$ baml check; baml run main
main.baml:2:39-4:2 warning[E0097]: extraneous throws declaration: MyError
    Finished checked 1 file(s) in 0s
warning: code is unformatted; run `baml fmt`
```

*interface implementation* (`bugrepro/b36c`)

```baml
class MyError { msg: string }
interface Parse { function parse(s: string) -> int throws MyError; }
class P {
    implements Parse {
        function parse(s: string) -> int throws MyError { baml.sys.panic("todo") }
    }
}
function main() -> void {}
```

```text
$ baml check
main.baml:5:57-5:83 warning[E0097]: extraneous throws declaration: MyError
    Finished checked 1 file(s) in 0s
```

*`throws unknown` is an error, same code E0097* (`bugrepro/n10`)

```baml
function parse_it(s: string) -> baml.json.json throws unknown {
    baml.json.parse(s)
}
function main() -> void {}
```

```text
$ baml check
main.baml:1:63-3:2 error[E0097]: `throws unknown` is imprecise: this function only throws `baml.json.ParseError`. BAML infers thrown types automatically, so remove the declaration; write `throws baml.json.ParseError` only to explicitly bound what may escape
```

**Expected.** No warning for stubs/`panic`-only bodies (or for implementations matching the interface signature); consistent severity for E0097.

**Workaround.** Omit the `throws` clause on the stub/implementation (it is allowed to be narrower than the interface).


## New findings

### N1. `baml run` / `baml pack` do not show compiler warnings

**Category:** tooling · **Severity:** medium · **Status:** Reproduced

**Summary.** Warnings reported by `baml check` (e.g. E0097 in `b36`) are not printed by `baml run` or `baml pack`, while the fmt warning is. Users relying on `run` never see them.

**Repro, command and actual output.**

`bugrepro/b36`

```baml
class MyError { msg: string }
function todo() -> int throws MyError {
    baml.sys.panic("not implemented yet")
}
function main() -> void {}
```

```text
$ baml check; baml run main
main.baml:2:39-4:2 warning[E0097]: extraneous throws declaration: MyError
    Finished checked 1 file(s) in 0s
warning: code is unformatted; run `baml fmt`
```

`baml pack main -o b36.bin` in `b36`:

```text
warning: code is unformatted; run `baml fmt`
    Finished ../b36.bin [main, aarch64-apple-darwin] in 0s
```

**Expected.** `run` prints compiler warnings (or a summary count).

**Workaround.** Run `baml check` separately.


### N2. Method call directly on an enum variant literal fails

**Category:** bug · **Severity:** medium · **Status:** Reproduced

**Summary.** `Mode.Fast.to_string()` (or any method) -> `unresolved name: Fast`: the chain is parsed as a namespace path. Works when bound to a variable (`let m: Mode = Mode.Fast; m.name()`, see `b20c`).

**Repro, command and actual output.**

`bugrepro/b20d`

```baml
enum Mode { Fast Slow }
function main() -> void {
    baml.io.println(`${Mode.Fast}`);
    let s = Mode.Fast.to_string();
}
```

```text
$ baml run main
main.baml:4:13-4:32 error[E0003]: unresolved name: `Fast`
error: cannot run: compilation errors found
```

**Expected.** `Mode.Fast.method()` works.

**Workaround.** Bind the variant to a variable first.


### N3. `(self as I)` inside an interface gives `unresolved type: self`

**Category:** diagnostics · **Severity:** low · **Status:** Reproduced

**Summary.** Casting `self` to an interface in a default method is reported as an unresolved *type* named `self`.

**Repro, command and actual output.**

`bugrepro/b17x`

```baml
interface A {
    function a(self) -> int throws never;
    function b(self) -> int throws never { (self as A).a() }
}
function main() -> void {}
```

```text
$ baml run main
main.baml:3:45-3:49 error[E0002]: unresolved type: self
error: cannot run: compilation errors found
```

**Expected.** Either allow it or say "`self` cannot be cast; call `self.a()` directly".

**Workaround.** Call `self.a()` directly.


### N4. Typed `_` binding not allowed in match arms

**Category:** missing feature · **Severity:** low · **Status:** Reproduced

**Summary.** `match (x) { let _: A => ... }` is a parse error (`expected '=>' after pattern, found ':'`). A named binding `let a: A =>` or a bare type pattern `A =>` works.

**Repro, command and actual output.**

`bugrepro/n15`

```baml
class A {}
class B {}
function name(x: A | B) -> string {
    match (x) { let _: A => "A", let _: B => "B" }
}
function main() -> void {}
```

```text
$ baml run main
main.baml:4:22-4:23 error[E0010]: unexpected token
  primary: expected `'=>' after pattern`, found `':'`
main.baml:4:39-4:40 error[E0010]: unexpected token
  primary: expected `'=>' after pattern`, found `':'`
error: cannot run: compilation errors found
```

**Expected.** Accept `let _: T`.

**Workaround.** Use the bare type pattern `A => ...`.

