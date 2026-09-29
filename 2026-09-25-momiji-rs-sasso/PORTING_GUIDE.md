# sasso → BAML porting guide

The contract for porting [momiji-rs/sasso @ 15c44de](https://github.com/momiji-rs/sasso/tree/15c44de208f4fa6b4886d2b84d1db08af79851f6)
(a zero-dependency Rust SCSS compiler) to BAML **line by line**. Every porter
follows these rules so that code written in parallel links up: a name, type or
signature in one file must be predictable from another file's Rust source.

* Rust source (read-only reference): `$SASSO` =
  `port/upstream/sasso` (see README for how to fetch it)
* BAML project: this directory (`baml.toml`, `baml_src/`)
* Item inventory (every Rust item, per file, with its BAML file/namespace, the
  enum registry and the `Copy` struct list): `port/INVENTORY.md`
* Rust-std shim (what BAML lacks): `baml_src/ns_std/*.baml` → namespace `root.std`
* BAML language skill: `.claude/skills/baml-core/SKILL.md`; stdlib docs:
  `baml describe <name>` (e.g. `baml describe baml.String --budget 200`).

"Line by line" means: same items, same order, same control flow, same helper
decomposition, comments and doc comments carried over. Deviate only where BAML
forces it, and then leave a short `// PORT:` comment saying what changed.

---

## 1. Layout and namespaces

One Rust module = one BAML namespace. A directory `ns_<name>/` under
`baml_src/` is namespace `<name>`; nesting stacks.

| Rust file | BAML file | namespace |
|---|---|---|
| `src/lib.rs` | `baml_src/lib.baml` | `root` |
| `src/main.rs` (binary crate root) | `baml_src/main.baml` | `root` |
| `src/value.rs` | `baml_src/ns_value/value.baml` | `root.value` |
| `src/eval/mod.rs` | `baml_src/ns_eval/mod.baml` | `root.eval` |
| `src/eval/expr.rs` | `baml_src/ns_eval/ns_expr/expr.baml` | `root.eval.expr` |
| `src/builtins/color/legacy.rs` | `baml_src/ns_builtins/ns_color/ns_legacy/legacy.baml` | `root.builtins.color.legacy` |
| inline `mod tests { … }` in `src/value.rs` | `baml_src/ns_value/ns_tests/tests.baml` | `root.value.tests` |
| inline `mod foo_tests { … }` in `src/main.rs` | `baml_src/ns_foo_tests/foo_tests.baml` | `root.foo_tests` |
| `tests/parity.rs` (integration test crate) | `baml_src/ns_tests/ns_parity/parity.baml` | `root.tests.parity` |

`port/INVENTORY.md` lists the exact target for every file.

**There are no imports, and a namespace does NOT see `root`'s names.** Inside
`root.eval`, the Rust `Value` (from `use crate::value::Value`) is written
`root.value.Value`; `crate::scanner::Pos` is `root.scanner.Pos`; a `lib.rs`
item such as `crate::Syntax` is `root.Syntax`. Items in the *same* namespace
are referenced bare. `super::foo` from `eval/expr.rs` is `root.eval.foo`.
Always use the fully-qualified `root.…` path for anything outside the current
namespace — in types, constructors, patterns, static calls and free calls.

Visibility (`pub`, `pub(crate)`) does not exist in BAML; drop it.

## 2. Names

* Keep every Rust name exactly (types, fields, functions, methods, variables).
* **Reserved in BAML** — if a Rust identifier is one of these, append `_`:
  `in client test match self function generator template_string let if else
  for while return break continue throw throws catch catch_all spawn await
  implements interface true false null is enum class const defer testset
  retry_policy instanceof requires extends`.
  (`type`, `as`, `new`, `from`, `default`, `env`, `map`, `string`, `log`, … are allowed.)
* A class may not have a field and a method with the same name (Rust allows
  it). Keep the field; rename the **method** to `<name>_` (e.g. `fn line(&self)`
  → `function line_(self)`). Call sites use `x.line_()`.
* `to_string` cannot be a plain method: a Rust `fn to_string(&self)` or
  `impl Display` becomes `implements baml.ToString { function to_string(self) -> string { … } }`.
  Other plain methods named `to_string`, `to_json` or `from_json` get a `_`
  suffix (`to_json_`) — those names are reserved for `baml.ToString`/`baml.ToJson`.
* Rust `const`/`static` items → zero-arg functions with the same name:
  `const MAX: usize = 32;` → `function MAX() -> int { 32 }`, used as `MAX()`
  (`root.eval.SCOPE_POOL_MAX()` from elsewhere). Tables too:
  `static T: [u64; 3] = [...]` → `function T() -> bigint[] { [...] }` (array
  literals are cheap; no need to cache).
* Nested `fn` inside a function body → hoist to a top-level function named
  `<outer>__<inner>` in the same file, placed right after the outer function
  (or a local closure when it captures locals).
* Tuple types → `root.std.Tuple2<A, B>` … `Tuple6` with fields `_0`, `_1`, …

## 3. Types

| Rust | BAML |
|---|---|
| `bool` | `bool` |
| `i8 i16 i32 i64 isize u8 u16 u32 usize` | `int` (63-bit: ±2^62) |
| `u64` | `int` when it is a count/size/index/length; `bigint` when it is a hash, bit pattern or may exceed 2^62 |
| `u128`/`i128` | `bigint` |
| `f64`, `f32` | `float` |
| `char` | `string` holding exactly one character |
| `String`, `&str`, `Rc<str>`, `Box<str>`, `Cow<'_, str>` | `string` |
| `String` that is appended to in a loop / passed as `&mut String` | `root.std.StrBuf` (§8) |
| `Vec<T>`, `&[T]`, `&mut [T]`, `Box<[T]>`, `[T; N]`, `VecDeque<T>`, `SmallVec` | `T[]` |
| `Vec<u8>`, `&[u8]` (byte strings) | `uint8array` (index → `int`) |
| `Option<T>` | `T?` (`None` → `null`, `Some(x)` → `x`) |
| `Option<Option<T>>` | `root.std.Some<T>?` |
| `Result<T, E>` return type | `T` + errors thrown (§6) |
| `HashMap<String, V>`, `FxHashMap`, `BTreeMap`, `IndexMap` | `map<string, V>` |
| `HashMap<K, V>` with non-string `K` | `map<string, V>` with a documented key encoding (`k.to_string()`, or `a + "\t" + b` for tuples (pick a separator the parts cannot contain)); write the encoding in a `// key:` comment on the field |
| `HashSet<T>`, `BTreeSet<T>` | `map<string, bool>` (see `root.std.set_insert/set_of`) |
| `Rc<T>`, `Arc<T>`, `Box<T>`, `&T`, `&mut T` (T a class/array/map) | `T` (classes, arrays and maps are reference types) |
| `Rc<RefCell<T>>`, `RefCell<T>`, `Cell<T>` (T a class/array/map) | `T` — mutate in place |
| `Cell<T>` / `&mut T` / `Rc<Cell<T>>` with T a value type (int, float, bool, string, Option) that must be shared/mutated through the reference | `root.std.Cell<T>` (`.value`, `.get()`, `.set(v)`, `.replace(v)`) |
| `Rc<dyn Any>` | `unknown` (downcast with `match`/`is`/`if let x: T = v`) |
| `Weak<T>` | `T?` |
| `(A, B)` | `root.std.Tuple2<A, B>` |
| `()` | `void` in return position, `null` as a value |
| `fn(A) -> B`, `impl Fn(A) -> B`, `&dyn Fn`, `Box<dyn Fn>` | `(A) -> B throws unknown` (a function type must declare `throws`) |
| `&dyn Trait`, `Box<dyn Trait>`, `impl Trait` | the trait's interface type |
| `std::path::Path`, `PathBuf`, `OsStr`, `OsString` | `string` (ops in `root.std.path_*`) |
| `std::cmp::Ordering` | `baml.ops.Ordering` (`Less`/`Equal`/`Greater`) |
| `std::time::Instant` | `bigint` nanoseconds via `root.std.now_nanos()`, or `baml.time.Instant` |
| `std::io::Error` | `baml.errors.Io` |

A type alias `type X = …;` → `type X = …` (non-generic aliases are allowed,
including aliases to a concrete generic instantiation). BAML has **no generic
type aliases** — inline them. Lifetimes, `where` clauses and trait bounds are
dropped (keep generic parameters: `function f<T>(x: T) -> T`).

## 4. Structs

```rust
#[derive(Clone, Default, PartialEq)]
pub(crate) struct SrcLines { pub file: u32, pub start: u32 }
impl SrcLines {
    pub(crate) const NONE: SrcLines = SrcLines { file: 0, start: 0 };
    pub(crate) fn new(file: u32) -> Self { SrcLines { file, start: 0 } }
    pub(crate) fn mapped_line(&self) -> u32 { self.start }
}
```
```baml
class SrcLines {
    file: int,
    start: int,

    function NONE() -> SrcLines {
        SrcLines { file: 0, start: 0 }
    }

    /// derive(Default)
    function default() -> SrcLines {
        SrcLines { file: 0, start: 0 }
    }

    function new(file: int) -> SrcLines {
        SrcLines { file: file, start: 0 }
    }

    function mapped_line(self) -> int {
        self.start
    }
}
```

* Fields become `name: type,`; methods (with `self`) and associated functions
  (without) go **inside the class body**, in Rust order. All `impl` blocks of a
  struct *in the same file* are merged into the class body in order.
* Associated functions are static methods: `Type::new(a)` → `Type.new(a)`,
  `root.value.Number.new(a)` from another namespace.
* `#[derive(Default)]` → a static `default()` that builds every field's default
  (`0`, `0.0`, `false`, `""`, `[]`, `{}`, `null`, `T.default()`).
  `Default::default()` / `T::default()` → `T.default()`. `..Default::default()`
  → spread: `T { ...T.default(), a: 1 }`.
* Struct literal shorthand `Foo { a, b }` → `Foo { a: a, b: b }`.
* `impl PartialEq for T` (custom) → `implements baml.ops.Equals { function eq(self, other: T) -> bool { … } }`
  so `==` uses it. `derive(PartialEq)` needs nothing: BAML `==` is structural.
* `impl Display for T` → `implements baml.ToString { … }`; `impl Debug` → drop
  (unless the code formats with `{:?}` — then a `debug()` method).
* `impl Drop` → a `function cleanup(self) -> void` only if the drop has
  observable effects; otherwise drop it with a `// PORT:` note.
* `impl Deref for T` → call the target explicitly (e.g. `x.deref()` method).

### Copy structs — value semantics!

Rust `Copy` structs (listed in `port/INVENTORY.md`, e.g. `root.scanner.Pos`,
`root.ast.SrcLines`) are copied on every assignment. BAML classes are
references. **Never mutate a field of an instance you did not just construct
yourself.** Where Rust copies then mutates (`let mut l = self.lines; l.start = 3;`)
write `let l = root.ast.SrcLines { ...self.lines }; l.start = 3;`.

### `.clone()` — reference semantics!

Arrays, maps and classes alias in BAML. A Rust `.clone()` is only a no-op if
neither the clone nor the original is mutated afterwards (common: values are
built once, then read). Otherwise copy explicitly:
* array: `root.std.clone_vec(v)` (shallow) — or `v.map((x) -> { T { ...x } })`;
* map: `root.std.clone_map(m)` (shallow);
* class: `T { ...x }` (shallow) or `baml.deep_copy(x)` (deep).
`Rc::clone(&x)` is always a plain alias. When unsure, copy (shallow is cheap).

## 5. Enums

Decide by the **Enum registry** in `port/INVENTORY.md` (C-LIKE vs DATA).

### C-like enums (no variant carries data) → BAML `enum`

```rust
#[derive(Clone, Copy, PartialEq)]
pub(crate) enum ListSep { Space, Comma }
impl ListSep {
    pub(crate) fn sep_str(self) -> &'static str { match self { ListSep::Space => " ", ListSep::Comma => ", " } }
    pub(crate) fn parse(s: &str) -> Option<ListSep> { … }
}
```
```baml
enum ListSep {
    Space,
    Comma,
}

interface ListSepMethods {
    function sep_str(self) -> string throws unknown
}

implements ListSepMethods for ListSep {
    function sep_str(self) -> string {
        match (self) {
            ListSep.Space => " ",
            ListSep.Comma => ", ",
        }
    }
}

/// `ListSep::parse` (associated fn of a C-like enum → free function `<Enum>_<fn>`).
function ListSep_parse(s: string) -> ListSep? { … }
```
* `ListSep::Comma` → `ListSep.Comma` (`root.value.ListSep.Comma` elsewhere).
* Methods with `self` → an interface named `<Enum>Methods` (every method
  `throws unknown`) + `implements <Enum>Methods for <Enum>`; call sites stay
  `sep.sep_str()`. Associated fns (no `self`) → free function `<Enum>_<fn>`
  in the same namespace.
* **Gotcha:** `let s = ListSep.Space;` gets the *literal* type `ListSep.Space`,
  which has no methods — annotate: `let s: root.value.ListSep = …;`.
* `derive(Default)` + `#[default]` variant → free function `<Enum>_default()`.

### Data enums (any variant carries data) → interface + one class per variant

```rust
pub(crate) enum Expr {
    Number(f64, Option<String>),
    Null,
    Var { name: String, pos: Pos },
    Binary { op: BinOp, lhs: Box<Expr>, rhs: Box<Expr> },
}
impl Expr {
    pub(crate) fn is_null(&self) -> bool { matches!(self, Expr::Null) }
    pub(crate) fn number(n: f64) -> Expr { Expr::Number(n, None) }
}
```
```baml
interface Expr {
    function is_null(self) -> bool throws unknown {
        self is Expr_Null
    }
}

class Expr_Number {
    _0: float,
    _1: string?,
    implements Expr {}
}

class Expr_Null {
    implements Expr {}
}

class Expr_Var {
    name: string,
    pos: root.scanner.Pos,
    implements Expr {}
}

class Expr_Binary {
    op: BinOp,
    lhs: Expr,
    rhs: Expr,
    implements Expr {}
}

/// `Expr::number` (associated fn of a data enum → free function `<Enum>_<fn>`).
function Expr_number(n: float) -> Expr {
    Expr_Number { _0: n, _1: null }
}
```
* The enum name is an **interface**; each variant is a class
  `<Enum>_<Variant>` that `implements <Enum> {}`. Tuple-variant fields are
  `_0`, `_1`, …; struct-variant fields keep their names; unit variants are
  empty classes.
* The `impl Enum` methods (with `self`) become **default methods in the
  interface body**; they typically `match (self) { … }`. A default method must
  declare `throws`, and BAML rejects `throws unknown` on a body that cannot
  throw: use `throws never` when the Rust fn does not return `Result` (and the
  body only panics), `throws unknown` when it does. The skeleton already
  chose by that rule; if your body ends up (not) throwing, flip it.
* Associated fns → free functions `<Enum>_<fn>`.
* Construct: `Expr::Var { name, pos }` → `Expr_Var { name: name, pos: pos }`;
  `Value::Null` → `root.value.Value_Null {}`.
* Match:
  ```baml
  match (e) {
      Expr_Number { _0: let n, _1: null } => …,                 // tuple variant, literal field
      Expr_Binary { op: BinOp.Add, lhs: let l, rhs: let r } => …, // nested enum literal
      let v: Expr_Var => v.name,                                 // bind whole variant
      Expr_Null {} => …,
      _ => …,                                                    // needed: an interface is open
  }
  ```
  `matches!(e, Expr::Null | Expr::Var { .. })` → `(e is Expr_Null || e is Expr_Var)`.
  `if let Expr::Var { name, .. } = e` → `if let v: Expr_Var = e { … v.name … }`.
* A method that reassigns `*self` cannot exist in BAML; return the new value
  and assign at the call site (`// PORT:` note).

## 6. Errors and panics

* The compiler error is `root.error.Error` (a class). A Rust function
  returning `Result<T, Error>` returns `T` in BAML and raises with
  `throw root.error.Error.at(msg, pos);` (`return Err(e)` → `throw e;`).
  Do not write a `throws` clause on ordinary functions — errors propagate
  implicitly.
* `expr?` → just `expr` (propagates). `.map_err(|e| f(e))?` →
  `expr catch (e) { let x: root.error.Error => throw f(x) }`.
* Matching a Result:
  ```baml
  // match f() { Ok(v) => a(v), Err(e) => b(e) }
  let r = f() catch (e) {
      let err: root.error.Error => {
          return b(err);          // or produce a value for the let
      }
  };
  a(r)
  ```
  `f().is_ok()` / `.ok()` / `.unwrap_or(d)` → `f() catch (e) { let _x: root.error.Error => d }`.
  **Only catch the error type the Rust `Result` carries** (`root.error.Error`,
  `baml.errors.Io`, `root.std.StrError`, …) so panics and other errors keep
  propagating. `catch_all` only where Rust also catches everything.
* A `Result` stored as a value (in a field, a Vec, returned then inspected
  later) → `root.std.Ok<T> | root.std.Err<E>`.
* `Result<T, String>` → throw `root.std.StrError { message: s }`
  (`root.std.err_str(s)`), catch `let e: root.std.StrError`.
* `Option` `?` → early return: `let x = f(); if (x == null) { return null; }`.
* `panic!(m)` → `root.std.panic(m)`; `unreachable!()` → `root.std.unreachable()`;
  `.unwrap()` on Option → `root.std.unwrap(x)` or `x ?? root.std.panic("…")`;
  `.expect(m)` → `root.std.expect(x, m)`. `assert!` in non-test code →
  `root.std.assert_true(c, m)`; `debug_assert!` → keep as a comment.
* Interface methods (trait methods, split-impl methods, enum methods) must
  declare a `throws` clause: always write `throws unknown`.
* A builtin that throws something other than what your function should
  surface (e.g. `f.itrunc()` throws `baml.errors.InvalidArgument`) — Rust
  would not fail there; wrap: `x.itrunc() catch (e) { _ => 0 }` (or use
  `root.std.f64_to_int(x)`).

## 7. `impl` blocks split across files, and traits

`Evaluator` (eval/*.rs), `Parser` (parser/*.rs) and `ColorSpace`
(builtins/color/math.rs) have `impl` blocks in files other than the one that
defines the type. Methods defined in the type's own file go in its class body
(or `<Enum>Methods` interface). Methods defined in **another** file go in that
file as an interface named `<Type><ModuleInPascalCase>` plus an `implements`
block — so call sites everywhere stay `self.method(…)`:

```baml
// baml_src/ns_eval/ns_expr/expr.baml   (namespace root.eval.expr)
interface EvaluatorExpr {
    function eval_expr(self, e: root.ast.Expr) -> root.value.Value throws unknown
    function eval_call(self, name: string, args: root.ast.CallArg[]) -> root.value.Value throws unknown
}

implements EvaluatorExpr for root.eval.Evaluator {
    function eval_expr(self, e: root.ast.Expr) -> root.value.Value {
        …
    }
    …
}
```
An associated fn (no `self`) inside such a split `impl` block becomes a free
function `<Type>_<fn>` in that file's namespace (e.g.
`root.eval.expr.Evaluator_helper(…)`; Rust calls it `Self::helper`/`Evaluator::helper`).

Interface names: `EvaluatorExpr`, `EvaluatorAtRules`, `EvaluatorBinop`,
`EvaluatorCalc`, `EvaluatorControlFlow`, `EvaluatorMeta`, `EvaluatorModules`,
`EvaluatorPlainCss`, `EvaluatorScope`, `ParserAtRules`, `ParserControlFlow`,
`ParserStatements`, `ParserValue`, `ColorSpaceMath`. The signature in the
interface and in the `implements` block must match exactly (parameter names,
types, return type); interface declares `throws unknown`, the implementation
omits `throws`.

A Rust `trait Importer { fn f(&self, …) -> R; fn g(&self) -> R { default } }`
→ `interface Importer { function f(self, …) -> R throws unknown  function g(self) -> R throws unknown { default } }`;
`impl Importer for FsImporter` → `implements root.importer.Importer { … }`
inside the class body (or top-level `implements … for …` when the class is in
another file).

## 8. Strings and chars

* A `char` is a one-character `string`. `'a'` → `"a"`, `'\n'` → `"\n"`.
  Comparisons work: `c >= "a" && c <= "z"` (code-point order).
* **BAML string escapes are only** `\n \t \r \0 \b \v \f \\ \"` (plus
  `` \` `` and `\$` in backtick strings). There is **no `\u{…}` / `\x..`
  escape** — `"\u{FEFF}"` is six literal characters. Write a printable
  non-ASCII character literally (`"é"`, `"—"`, `"�"`) and build invisible/control
  ones with `root.std.chr_unchecked(0xFEFF)`; `'\x0C'` → `"\f"`.
* **Offsets are CHARACTER offsets** in the port: Rust's byte offsets into a
  `str` become char offsets consistently — `s.len()` → `s.length()`,
  `&s[a..b]` → `s.slice(a, b)`, `&s[a..]` → `s.slice(a, s.length())`,
  `s.find(p)` → `s.index_of(p)`, `s.rfind(p)` → `s.last_index_of(p)`. The
  substrings produced are identical as long as every offset used with a string
  was computed on that same string.
* Where the Rust result depends on the **byte count itself** (a UTF-8 length
  reported to the user, a span length "in bytes", `c.len_utf8()`, a source-map
  column) use bytes explicitly: `s.byte_length()`, `root.std.len_utf8(c)`,
  `root.std.byte_slice/byte_find/char_to_byte_offset/byte_to_char_offset`.
* **Never index a long string per character in a loop** (`s.at(i)`,
  `s.code_point_at(i)`, `s.slice(i, i + 1)` are O(n) each). Convert once:
  `let cs = s.chars();` then `cs[i]` / `cs.at(i)`. `for c in s.chars()` →
  `for (let c in s.chars())`. For `s.as_bytes()` loops: `let b = s.to_utf8();`
  then `b[i]` (an `int`); compare with numeric byte values.
* Char predicates: `is_ascii_digit` → `c.is_ascii_numeric()` (or
  `root.std.is_ascii_digit(c)` which accepts `null`), `is_ascii_alphabetic`,
  `is_ascii_alphanumeric`, `is_ascii_hexdigit` → `c.is_ascii_hex()`,
  `is_ascii_whitespace` → `root.std.is_ascii_whitespace(c)`, `is_whitespace`,
  `is_alphabetic`, `is_alphanumeric`, `is_numeric`, `is_ascii_uppercase`,
  `is_ascii_lowercase`, `is_uppercase`, `is_lowercase`, `is_control`, `is_ascii`
  — same names on `string`.
* `c as u32` → `root.std.ord(c)`; `char::from_u32(n)` → `root.std.chr(n)` (`string?`);
  `n as u8 as char` → `root.std.chr_unchecked(n)`; `c.to_digit(r)` →
  `root.std.to_digit(c, r)`; `char::from_digit` → `root.std.from_digit`.
* `to_ascii_lowercase()`/`to_ascii_uppercase()` → `root.std.ascii_lower/ascii_upper`
  (NOT `to_lower_case()`, which is Unicode-aware); `eq_ignore_ascii_case` →
  `root.std.eq_ignore_ascii_case(a, b)`; `to_lowercase()` → `to_lower_case()`.
* `trim()` → `root.std.trim(s)` (Rust White_Space semantics),
  `trim_start/trim_end` → `root.std.trim_start/trim_end`;
  `strip_prefix/strip_suffix` → `root.std.strip_prefix/strip_suffix` (`string?`);
  `trim_start_matches/trim_end_matches/trim_matches` (string pattern or
  closure: `root.std.trim_start_by(s, pred)` …); `split_once/rsplit_once` →
  `root.std.split_once` (`Tuple2<string,string>?`); `splitn` → `root.std.splitn`;
  `s.contains(p)` → `s.includes(p)`; `s.starts_with/ends_with` same;
  `s.split(p)` → `s.split(p)` (array); `s.lines()` → `s.lines()`;
  `s.chars().rev()` → `s.chars().reverse()`; `s.chars().count()` → `s.length()`;
  `s.is_empty()` → `s == ""`; `s.replace(a, b)` → `s.replace_all(a, b)`
  (Rust `replace` replaces ALL); `s.replacen(a, b, 1)` → `s.replace(a, b)`;
  `s.repeat(n)` same; `s.char_indices()` → iterate `s.chars()` with your own
  char counter (or `root.std.char_indices_bytes(s)` if byte offsets matter).
* `String::new()` → `""`; `s.push_str(x)`/`s.push(c)` on a local that stays
  small → `s = s + x;` (`+` needs both sides `string`); `format!("a{}b", x)`
  → `` `a${x}b` `` — but **a float must go through `root.std.fmt_f64(x)`**
  (`${x}` renders `1.0` where Rust prints `1`). `{:?}` of a str →
  `root.std.debug_str(s)`, of an f64 → `root.std.fmt_f64_debug(x)`; `{:.3}` →
  `root.std.fmt_f64_prec(x, 3)`; `{:e}` → `root.std.fmt_f64_exp(x)`; `{:>5}` →
  `root.std.pad_left(s, 5)`; `{:02}` → `root.std.zero_pad(n, 2)`; `{:x}` →
  `root.std.hex_lower(n)`.
* **`root.std.StrBuf`** replaces a `String` that is (a) passed as `&mut String`,
  or (b) appended to in a loop that may run many times (output buffers,
  serializers, per-character escapers). A plain `s = s + x` loop over a
  100K-character input builds a rope that overflows the VM. API mirrors
  `String` in char units: `push_str`, `push`, `len()` (chars), `byte_len()`,
  `is_empty`, `as_str()`, `truncate(n)`, `pop()`, `last_char()`, `ends_with`,
  `starts_with`, `slice(a,b)`, `slice_from(a)`, `insert_str(i,s)`, `clear()`,
  `take()`, `set(s)`. A Rust `fn f(out: &mut String)` → `function f(out: root.std.StrBuf) -> void`.
  Create with `root.std.StrBuf.new()` / `root.std.StrBuf.from(s)`.
* Joining many parts: `root.std.join(parts, sep)` / `root.std.concat(parts)`
  (safe for long lists; `parts.join(sep)` is fine for short ones).

## 9. Numbers

* `int` is 63-bit and **overflow panics**. Hash functions, `wrapping_*` on
  `u64`, FxHash, ryu's 64/128-bit math and f64 bit patterns use `bigint`
  (`0x7ff0n`, `1n << 52`, `&`, `|`, `^`, `<<`, `>>` all work) with the
  `root.std.u64_*` helpers; `u32` wrapping math uses `root.std.u32_*`.
  `bigint`↔`int`: `root.std.bigint_of(i)`, `root.std.int_of(b)`.
* `int / int` truncates toward zero and `%` keeps the dividend's sign — same
  as Rust. Mixing int and float is a compile error for assignment; convert:
  `i as f64` → `i * 1.0` (or `root.std.int_to_f64(i)`).
* `x as i64/i32/isize` (float→int) → `root.std.f64_to_int(x)` /
  `root.std.f64_to_i32(x)`; `as usize/u64` → `root.std.f64_to_usize(x)`;
  `as u32` → `root.std.f64_to_u32(x)`; `as u8` → `root.std.f64_to_u8(x)`
  (all saturating, NaN → 0, like Rust). Int→int narrowing: `root.std.as_u8/as_u16/as_u32/as_i32/as_i8`.
* f64 bits: `x.to_bits()` → `root.std.f64_to_bits(x)` (bigint);
  `f64::from_bits(b)` → `root.std.f64_from_bits(b)`; `0x3ff0000000000000u64` →
  `0x3ff0000000000000n`.
* f64 methods: `abs floor ceil round trunc sqrt cbrt exp ln log10 log2 sin cos
  tan asin acos atan sinh cosh tanh asinh acosh atanh hypot to_degrees
  to_radians is_nan is_infinite is_finite signum` exist with the same names
  and Rust semantics (`round` is half-away-from-zero; `atan2`: `y.atan2(x)`;
  `powf(e)` → `pow(e)`; `ln` is `ln`). Use `root.std.powi(x, n)` (NOT `pow`) for
  `powi`, `root.std.fract(x)`, `root.std.fmax/fmin/fclamp`, `root.std.copysign`,
  `root.std.f_rem_euclid/f_div_euclid`, `root.std.is_sign_negative/positive`.
  `%` on floats is Rust's `%` (fmod).
* Int helpers: `a.max(b)`/`a.min(b)`/`clamp` → `root.std.imax/imin/iclamp`;
  `rem_euclid/div_euclid` → `root.std.rem_euclid/div_euclid`;
  `saturating_sub` (unsigned) → `root.std.saturating_sub_u`; `checked_sub` →
  `root.std.checked_sub_u`; `abs_diff` → `root.std.abs_diff`; `abs()` → `.abs()`;
  `pow` → `.pow(n)`; `leading_zeros/trailing_zeros/count_ones` exist on `int`
  (63-bit! for u32/u64 semantics compute explicitly).
* Constants: `f64::EPSILON` → `root.std.F64_EPSILON()`, `f64::MAX/MIN/MIN_POSITIVE/INFINITY/NEG_INFINITY/NAN`,
  `std::f64::consts::PI/E` → `root.std.F64_*()`; `usize::MAX/i64::MAX` →
  `root.std.INT_MAX()`; `u32::MAX` → `4294967295`; `u8::MAX` → `255`.
* Integer parsing: `s.parse::<i64>()` → `baml.Int.parse(s)` (throws
  `baml.errors.ParseError`); float → `baml.Float.parse(s)`. Rust's parse
  grammar differs in corners (leading `+`, whitespace); if it matters, write
  the check explicitly.

## 10. Collections and iterators

* `Vec::new()`/`vec![]` → `[]` (annotate when the element type is not
  inferable: `let v: root.value.Value[] = [];`); `vec![x; n]` →
  `baml.Array.filled(n, x)` — careful, for a class `x` every slot aliases one
  object: use `baml.Array.generate(n, (i) -> { T { … } })`.
* `v.len()` → `v.length()`; `v.is_empty()` → `v.length() == 0`; `v.push(x)`;
  `v.pop()` (→ `T?`); `v[i]` (panics out of range, like Rust); `v.get(i)` →
  `v.at(i)`; `v.first()` → `v.at(0)`; `v.last()` → `root.std.last(v)`;
  `v.insert(i, x)` → `v.insert(x, i)` (**argument order swapped**, and it
  throws `InvalidArgument` on a bad index); `v.remove(i)` → `v.remove_at(i)`;
  `v.truncate(n)` → `root.std.truncate(v, n)`; `v.clear()`;
  `v.extend(o)`/`extend_from_slice(o)` → `root.std.extend(v, o)`;
  `v.retain(p)` → `root.std.retain(v, p)`; `v.dedup()` → `root.std.dedup(v)`;
  `v.drain(a..b)` → `root.std.drain(v, a, b)`; `v.split_off(i)` →
  `root.std.split_off(v, i)`; `v.swap(i, j)` → `root.std.swap(v, i, j)`;
  `v.contains(&x)` → `root.std.contains(v, x)` (structural — BAML's own
  `includes`/`index_of` compare class and array elements by IDENTITY, so use
  them only for primitives); `v.iter().position(|e| *e == x)` →
  `root.std.position(v, x)`; `v.iter().position(p)` → `v.find_index(p)`; `v.reverse()` (in place in Rust!) → `let r = v.reverse();
  v.clear(); root.std.extend(v, r);` — BAML `reverse()` returns a NEW array.
  `&v[a..b]` → `v.slice(a, b)` (a copy — fine for reading).
* Sorting: `v.sort()` → `root.std.sort_strings(v)` / `root.std.sort_ints(v)`
  or `v.sort_by((a, b) -> { a.cmp(b) })`; `sort_by(|a, b| …)` →
  `v.sort_by((a, b) -> { … })` (in place, stable — same as Rust's `sort_by`);
  `sort_by_key(|x| k)` → `v.sort_by_key((x) -> { k })`; `sort_unstable*` →
  the stable versions. `a.cmp(&b)` → `a.cmp(b)` (int, float, string);
  `Ordering::then_with` → nest the comparison explicitly.
* Iterator chains become array methods (eager): `.iter().map(f).collect()` →
  `.map(f)`; `.filter(p)` → `.filter(p)`; `.filter_map(f)` → `.filter_map(f)`;
  `.flat_map(f)` → `.flat_map(f)`; `.any(p)` → `.some(p)`; `.all(p)` →
  `.every(p)`; `.find(p)` → `.find(p)`; `.count()` → `.length()`;
  `.fold(init, f)` → `.reduce((acc, x) -> {…}, init)`; `.sum()` → loop or
  `.reduce`; `.max()/.min()` → loop; `.rev()` → `.reverse()`;
  `.enumerate()` → an index loop (`let i = 0; for (let x in v) { …; i += 1; }`
  or `while (i < v.length())`); `.zip(o)` → an index loop; `.skip(n)` →
  `.slice(n, v.length())`; `.take(n)` → `.slice(0, n)`; `.windows(2)` → index
  loop; `.peekable()` → an index cursor; `.chain(o)` → `.concat(o)`;
  `.cloned()/.copied()/.iter()/.into_iter()` → nothing. `(a..b)` →
  `baml.iter.Range.new(a, b)` in a `for`, or a `while` loop; `(a..=b)` →
  `Range.new(a, b + 1)`; `.rev()` over a range → a descending `while` loop.
  **Break/continue/return inside a closure do not affect the outer loop** —
  where Rust uses an early exit, write a `for`/`while` loop.
* Maps: `m.get(&k)` → `m.get(k)` (`V?`); `m[&k]` → `m[k]`; `m.insert(k, v)` →
  `m.set(k, v)` (returns the old `V?` — discard with `let _ = …;` when unused);
  `m.remove(&k)` → `m.delete(k)`; `m.contains_key(&k)` → `m.has(k)`;
  `m.len()` → `m.length()`; `m.keys()/values()` → arrays;
  `for (k, v) in &m` → `for (let k in m.keys()) { let v = m[k]; … }`;
  `*m.entry(k).or_insert(0) += 1` → `m.set(k, (m.get(k) ?? 0) + 1)`;
  `m.entry(k).or_insert_with(|| v)` → `m.get_or_insert(k, v)` (evaluate `v`
  only if absent when it is expensive or has effects); `m.clear()`;
  `m.retain(p)` → `root.std.map_retain(m, p)`; BTreeMap iteration order →
  `root.std.sorted_keys(m)`. Empty map needs a type: `let m: map<string, int> = {};`.
* Sets: `HashSet<String>` → `map<string, bool>`; `s.insert(k)` →
  `root.std.set_insert(s, k)` (returns bool); `s.contains(&k)` → `s.has(k)`;
  `s.remove(&k)` → `s.delete(k)`.
* `std::mem::take(&mut x)` → `let t = x; x = <empty>; t` (for a field:
  `let t = self.f; self.f = [];`); `mem::replace(&mut x, v)` → `let old = x; x = v; old`;
  `mem::swap` → temp variable. `Option::take()` on a field →
  `let v = self.f; self.f = null; v`.
* Option combinators: `o.map(f)` → `if (o != null) { f(o) } else { null }` (or
  `o?.method()`); `o.unwrap_or(d)` → `o ?? d`; `o.unwrap_or_else(f)` →
  `o ?? f()`; `o.unwrap_or_default()` → `o ?? <default>`; `o.is_some()` →
  `o != null`; `o.is_none()` → `o == null`; `o.and_then(f)` → `if (o != null) { f(o) } else { null }`;
  `o.filter(p)`, `o.map_or(d, f)`, `o.ok_or(e)?` → explicit `if`s.
  `if let Some(x) = o { … }` → `if (o != null) { … o … }` or
  `if let x: T = o { … }`.

## 11. Control flow and BAML gotchas

* `if`/`while` conditions need parentheses; bodies need braces; **no ternary**
  — `if (c) { a } else { b }` is an expression. Blocks are expressions (last
  expression without `;` is the value).
* `loop { … }` → `while (true) { … }`. Labeled `break 'outer` / `continue
  'outer` → a flag variable checked after the inner loop.
* `match` works on ints, strings, enums, classes; arms are `pattern => expr,`.
  Char/int ranges `'a'..='z'` → guard: `let c if c >= "a" && c <= "z" => …`.
  Matching a tuple `match (a, b) { … }` → an `if`/`else if` chain. Slice
  patterns: `[let first, ..let rest]`, `[]`. `x @ pat` → bind separately.
  `ref`/`&`/`*` in patterns → drop. A `match` must be exhaustive (`_` arm).
* `while let Some(x) = it.next()` → `while let x: T = expr { … }` or an index loop.
* **Narrowing:** `if (x != null) { … }`, early `return`, `while (x != null)`
  and `if let v: T = x` narrow `x`. **`x != null && x.f` does NOT narrow inside
  the `&&`** — nest the `if`, or use `x?.f == …` only when `null`-comparisons are
  acceptable, or `if let`. Generic `T?` does not narrow on `== null` — use `??`.
* Closures: `|a, b| a + b` → `(a, b) -> { a + b }`; annotate params when the
  type is not inferable: `(a: int) -> int { … }`. `move` → nothing.
  Closures can assign captured locals.
* `return` inside a `match` arm / `catch` arm returns from the function.
* Function parameters are reassignable (Rust `mut x: T` param → plain `x: T`).
  Shadowing with `let x = …;` twice in one scope is allowed.
* Default arguments exist but must be passed by name — do not introduce them;
  keep Rust's positional parameter lists.
* **Call depth is capped at 256 frames by the BAML VM.** Never turn a Rust
  loop into recursion. Keep Rust's recursion as-is.
* No globals: BAML has no top-level `let`/`static`. `thread_local!` / `static`
  *mutable* state → (a) a pure cache: compute without caching, `// PORT:
  cache dropped`; (b) real state (counters, RNG, "current evaluator"): move it
  into a field of the context object that is available at every use (usually
  the `Evaluator`), and note it. Pointer identity (`Rc::ptr_eq`, `std::ptr::eq`)
  → give the class an `_id: string` field set from `root.std.fresh_id()` at
  construction and compare ids (or restructure with a `// PORT:` note).
  Pointer arithmetic on slices (`s.as_ptr() as usize - base`) → carry the
  offset explicitly.
* `#[cfg(...)]` code: port the branch that is active for a macOS/Linux host
  build (not wasm, not windows). `#[cfg(test)]` helpers live with the tests.
* `eprintln!(…)` → `baml.io.eprintln(…)`; `println!` → `baml.io.println`;
  `print!`/`eprint!` → `baml.io.print`/`baml.io.eprint`. `std::process::exit(c)`
  → `root.std.exit(c)`. Env/args/fs/time → `root.std.args()`, `env_var`,
  `current_dir`, `read_to_string`, `read_bytes`, `write_file`, `exists`,
  `is_dir`, `is_file`, `read_dir_names`, `create_dir_all`, `remove_file`,
  `canonicalize`, `mtime_nanos`, `read_stdin`, `now_nanos`, `sleep_ms`,
  `available_parallelism`; paths → `root.std.path_join/parent/file_name/
  extension/file_stem/with_extension/is_absolute/components/starts_with/strip_prefix`.
* Threads (`std::thread::spawn`/`scope`) → `spawn { … }` + `await` (green
  threads), or sequential execution with a `// PORT:` note when the threading
  only exists for throughput.

## 12. Comments, docs, formatting

* Keep comments. `///` doc comments → `///` on the BAML item; `//!` module docs
  → `//` at the top of the file; `//` comments as-is.
* Use 4-space indentation, one item per line, trailing commas in multi-line
  class bodies. You may run `baml fmt <your-file>` on files you own; never
  format files you do not own.

## 13. Tests

* Rust `#[cfg(test)] mod tests { … }` → its own namespace file (see §1).
  `#[test] fn name() { … }` → `test "name" { … }`; helper fns in the test module
  → plain functions in that test namespace.
* `assert_eq!(a, b)` → `assert.equal(a, b);` (structural; floats exact);
  `assert_ne!(a, b)` → `assert.is_true(a != b);`; `assert!(c)` →
  `assert.is_true(c);`; `assert!(r.is_err())` →
  `let failed = (f() catch (e) { let _e: root.error.Error => null }) == null; assert.is_true(failed);`
  (adapt to the return type); `#[should_panic]` → wrap the body in
  `catch_all` and assert it panicked. The last statement in a test has no `;`.
* Run: `baml test -i "root::value::tests::name"`; list with `baml test --list`.

## 14. Workflow

**The BAML compiler needs a big thread stack on this project**: run it as `RUST_MIN_STACK=1073741824 baml check` / `RUST_MIN_STACK=1073741824 baml run …` (without it, it aborts with "thread has overflowed its stack" and prints no diagnostics). `port/errors_for.py` and `port/progress.sh` set this themselves and abort loudly if the checker crashes.

The declaration skeleton (`port/skeleton.py`) already exists: every item of
every file is declared, with bodies stubbed as `root.std.todo()` (or
`root.std.todo_throws()`), and the whole project compiles. Porting a function
means replacing its stub body with the line-by-line port of the Rust body. A
skeleton type the generator could not translate reads
`unknown /* PORT-TYPE: … */` — fix it.

* **Shared files** (several porters fill stubs in one file): never use an
  editor on them. Write the complete function (signature + body, column 0)
  to a scratch file and splice it in:
  `python3 port/splice.py <file.baml> <fn_name> /tmp/x.baml [--in <Container>]`
  (`--show` prints the current text; `--after` inserts a new helper after a
  function; `--append FILE` appends top-level code;
  `--replace-text OLD_FILE NEW_FILE` swaps one exact, unique snippet — use it
  for declaration edits such as a class field). The tool locks the file.
* **Your own file** (no one else assigned to it): Edit/Write freely.
* Errors for your functions only: `python3 port/errors_for.py <file.baml> --fn f1,f2`
  (without `--fn`: every error in the file, labelled `Container.fn`).
* The skeleton's signatures follow this guide mechanically. If one is wrong
  for its Rust body (e.g. a parameter the callee reassigns needs a
  `root.std.Cell`), fix the declaration of the item you own and list the
  change in your final report; callers still being ported will see it.
* Do not run `baml fmt`.

* Compile-check the whole project: `baml check` (≈ seconds). Your files must
  have **zero errors**; filter with `baml check 2>&1 | grep -A3 '<your file name>'`.
  Errors in files you do not own are someone else's — do not edit those files.
* Evaluate snippets fast with a scratch project (`baml init` in a temp dir) or
  `baml run -e 'root.std.fmt_f64(1.5)'`.
* Look up stdlib behavior with `baml describe <name>`; do not guess.
* If a signature another file depends on turns out to be wrong/unportable,
  do not silently change other people's files: fix your own file and report
  the cross-file change in your final summary.

## 15. Findings from porters (append-only)

* An empty class pattern `T {}` matches a `T` with **any** field values (it is
  not "all fields default"); `T { f: 1 }` constrains only `f`.
* A `match` guard cannot contain a parenthesized `is` test; use class
  patterns / or-patterns instead.
* An or-pattern whose alternatives bind a field is not accepted across
  different variant classes — write one arm per variant.
* `root.ast.SrcLines.default()` exists (Rust `SrcLines::default()`).
* BAML has no bitwise-not operator: `!(x - 1)` on an alignment mask → `& -x`.
* **BAML compiler bug — `-0.0` and `0.0` constants merge within one
  function**: `if (c) { -0.0 } else { 0.0 }` yields `+0.0`. Where a negative
  zero literal matters, write `root.std.NEG_ZERO()` (= `f64_from_bits(0x8000000000000000n)`).
* Parser gotcha: an `if { … }` statement followed on the next line by an
  array literal `[ … ]` parses as indexing the `if` — end the `if` with `;`.
* `x.signum()` returns `1.0` for NaN (Rust returns NaN).
* Tuple literals holding named functions infer `throws never` function types
  that do not unify with `… throws unknown` fields — give the tuple an explicit type.
* A `match` guard that begins with a parenthesised `match` (`pat if (match (x) {…}) =>`)
  misparses as a lambda — write the guard as a plain `==`/`||` chain.
* Never write relative paths while your cwd might be elsewhere: an agent
  that `cd`s into a scratch dir and fails will write into the project root.
  Use absolute paths for scratch files.
* **Float comparisons are a total order in BAML**: `NaN == NaN` is `true`,
  `NaN > 1.0` is `true`, `NaN >= NaN` is `true`. Rust follows IEEE (all false
  except `!=`). Wherever a NaN can reach a float comparison, use
  `root.std.feq/fne/flt/fle/fgt/fge(a, b)` (IEEE semantics). `root.std.fmax/fmin`
  already follow Rust.
* RAII guards (`root.arena.Paused`, `root.importer.DependencyScope`, arena
  `Scope`) have a plain `drop()` method — BAML has no destructors. Call it
  where the Rust guard would go out of scope, usually `defer { g.drop() }`.
* A `catch` arm cannot take an `if` guard — test inside the arm.
* `root.eval.Module` has an identity field `_id: string` (set with
  `root.std.fresh_id()` wherever a Module is built; `""` = null pointer).
  Rust `Rc::ptr_eq`/`Rc::as_ptr` on modules → compare `_id`s.
  `Forwarded.*_src` and `Evaluator.forwarded_globals` hold module `_id`s.
* Inside a `match` arm, `self` is narrowed to that arm's type, so a later
  `_` arm can be a compile error ("unreachable") — drop it.
* Scratch BAML projects (outside this directory) need
  `BAML_AGENT_SKILL_CHECK=off` for `baml init/check/run`.
* `port/errors_for.py` exits 3 when syntax errors elsewhere in the project
  stopped type checking (a syntax error anywhere hides every type error
  project-wide) — re-run later; that "0" is not a pass.
* Match guards: no multi-line guards and no `&& (obj.method())`-style
  parenthesized member calls — compute the value before the `match`.
* A parenthesized match `(match (x) { … })` parses as a lambda parameter
  list — write `match` without wrapping parentheses (in guards, after `&&`,
  in `let` initialisers).
* Parser lookahead: don't call `self.sc.rest()` in per-statement/per-token
  paths (it copies the rest of the input); index `self.sc.chars` from
  `self.sc.pos` instead, with a `// PORT:` note.
* **`Array.includes` / `index_of` use identity for class/array elements**
  (`[T { a: 1 }].includes(T { a: 1 })` is `false`); `==` is structural. Use
  `root.std.contains/position` for Rust `contains`/`position`-by-value.
* Calling `.to_string()` on an INTERFACE-typed value crashes at runtime
  ("interface … declares no method `to_string`"); call it on a concrete class.
* `||` does not narrow either; a captured optional is not narrowed inside a
  closure unless copied to a local first.
* A `uint8array` cannot be iterated with `for … in` — use an index loop.
* Destructuring a generic class in a pattern needs type arguments:
  `root.std.Tuple2<string, string> { _0: let a, _1: let b }`.
* `root.selector.Extension.matched` is a `root.std.Cell<bool>` (shared flag).
  Maps keyed by selector `Simple` use `s.render()` as the key.
* Importer failures are thrown as `root.importer.ImporterError`.
* **Compiler panic trigger**: `x ?? root.std.Tuple2 { … }` (a generic class
  literal with inferred type arguments on the right of `??`) crashes codegen
  with "indirect calls require an explicit caller layout". Spell the type
  arguments: `root.std.Tuple2<A, B> { … }`.
* **Global mutable state (Rust `static` atomics / `thread_local!`)**: a
  top-level `client` declaration is evaluated once and shared for the whole
  process, so it can hold a mutable cell:
  ```baml
  client EXTEND_WORK_CELL = root.std.Cell<int> { value: 0 };
  function EXTEND_WORK() -> root.std.Cell<int> { EXTEND_WORK_CELL }
  // Rust: EXTEND_WORK.with(|w| w.get())  →  EXTEND_WORK().get()
  ```
  (This repurposes BAML's LLM-client declaration; it is process-wide, not
  per-thread.) Prefer it over dropping state that matters (counters, RNG
  state, "current evaluator" slots); pure caches may still be dropped.
* **BAML miscompile — throwing `catch` arm in an `else` branch**: when a
  `catch` arm that always throws sits inside the `else` of `if (x != null)`,
  the checker treats the whole branch as diverging and folds a LATER
  `x != null` to always-true (warning E0004), so the wrong path runs. Store
  the error in a local inside the arm and `throw` it after the statement.
* `env` as a parameter/local whose fields you read resolves to BAML's builtin
  `env` reference — rename it `env_`.
* VM bug: inside a class METHOD, `bigint ^ bigint` can fail at runtime
  ("cannot apply binary operation"); use `(a | b) - (a & b)`.
* `uint8array.at(-1)` / `array.at(-1)` count from the end (JS-style) — never
  pass a computed index that may go negative.
* `x ?? return null` works as Rust's `?` on an `Option`.
* A narrowed optional that a closure captures loses its narrowing for the
  rest of the block — copy it to a non-optional local first.
* Interface default methods declared `throws never` break as soon as a
  callee may throw; `port/fix_throws.py` widens them to `throws unknown`.
* **`catch_all` / `_` do not catch panics.** To catch any panic use
  `catch (e) { let _p: baml.panics.Panic => … }` (e.g. for `#[should_panic]`).
* `spawn` tasks run truly in parallel — never share mutable state across
  spawned tasks without a primitive (a shared counter loses updates).
* `baml.sys.exec` with a large `stdin` string can deadlock when the child
  fills its stdout pipe; redirect through files (`/bin/sh -c 'exec "$0" <"$1" >"$2"'`).
* Function references work as callbacks: `.map(root.std.f64_to_bits)`.
