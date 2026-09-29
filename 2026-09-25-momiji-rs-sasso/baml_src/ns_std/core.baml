// `root.std` — the Rust standard-library surface the sasso port relies on that
// BAML does not ship. The Rust crate has zero runtime dependencies; everything
// it takes from `std` that has no BAML builtin lives in this namespace.
//
// Conventions (see PORTING_GUIDE.md):
//   * Rust tuples              -> Tuple2 .. Tuple6 (`_0`, `_1`, ...)
//   * `&mut` to a primitive    -> Cell<T>
//   * `Option<Option<T>>`      -> Some<T>? (outer layer is `Some`)
//   * `Result<T, E>` as value  -> Ok<T> | Err<E>
//   * `Result<T, String>`      -> throws StrError

/// A Rust 2-tuple `(A, B)`.
class Tuple2<A, B> {
    _0: A,
    _1: B,
}

/// A Rust 3-tuple `(A, B, C)`.
class Tuple3<A, B, C> {
    _0: A,
    _1: B,
    _2: C,
}

/// A Rust 4-tuple.
class Tuple4<A, B, C, D> {
    _0: A,
    _1: B,
    _2: C,
    _3: D,
}

/// A Rust 5-tuple.
class Tuple5<A, B, C, D, E> {
    _0: A,
    _1: B,
    _2: C,
    _3: D,
    _4: E,
}

/// A Rust 6-tuple.
class Tuple6<A, B, C, D, E, F> {
    _0: A,
    _1: B,
    _2: C,
    _3: D,
    _4: E,
    _5: F,
}

/// A mutable box: stands in for `&mut T` of a value type (int, float, bool,
/// string, an `Option`), for `Cell<T>`, and for `Rc<Cell<T>>`/`Rc<RefCell<T>>`
/// over a value type. Classes are already reference types and need no box.
class Cell<T> {
    value: T,

    function new(value: T) -> Cell<T> {
        Cell { value: value }
    }

    function get(self) -> T {
        self.value
    }

    function set(self, value: T) -> void {
        self.value = value;
    }

    /// `std::mem::replace(&mut cell, value)`.
    function replace(self, value: T) -> T {
        let old = self.value;
        self.value = value;
        old
    }
}

/// The outer layer of an `Option<Option<T>>`: `None` is `null`, `Some(None)`
/// is `Some { value: null }`, `Some(Some(x))` is `Some { value: x }`.
class Some<T> {
    value: T,
}

/// `Ok(T)` when a Rust `Result` is kept as a value (stored, collected, matched
/// later). A `Result` that is only ever `?`-propagated maps to `throws` instead.
class Ok<T> {
    value: T,
}

/// `Err(E)` when a Rust `Result` is kept as a value.
class Err<E> {
    error: E,
}

/// The error of a Rust `Result<T, String>` (the string is the message).
class StrError {
    message: string,
}

/// Throw a `StrError` — `return Err(msg)` in a `Result<T, String>` function.
function err_str(message: string) -> never {
    throw StrError { message: message };
}

/// `panic!(msg)`.
function panic(message: string) -> never {
    baml.sys.panic(message)
}

/// `unreachable!()`.
function unreachable() -> never {
    baml.sys.panic("internal error: entered unreachable code")
}

/// `todo!()` / `unimplemented!()`.
function todo() -> never {
    baml.sys.panic("not yet implemented")
}

/// `opt.unwrap()`.
function unwrap<T>(value: T?) -> T {
    value ?? baml.sys.panic("called `Option::unwrap()` on a `None` value")
}

/// `opt.expect(msg)`.
function expect<T>(value: T?, message: string) -> T {
    value ?? baml.sys.panic(message)
}

/// `debug_assert!` / `assert!` outside tests.
function assert_true(cond: bool, message: string) -> void {
    if (!cond) {
        baml.sys.panic(message);
    }
}

/// A process-unique identity token. BAML has no reference-identity operator,
/// so a class that Rust compares with `Rc::ptr_eq` carries one of these.
/// PORT: was `baml.id.new()`, which toolchain 0.20.2-nightly.20260925.a
/// removed; 63 random bits from the OS CSPRNG serve the same purpose.
function fresh_id() -> string {
    `${baml.random.SystemRandom.get().random_int()}`
}

/// `todo!()` in a function that returns `Result` (so that it is seen as able
/// to throw). Skeleton stub only.
function todo_throws() -> never {
    throw StrError { message: "not yet implemented" };
}
