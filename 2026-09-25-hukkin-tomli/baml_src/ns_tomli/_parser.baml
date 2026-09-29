// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2021 Taneli Hukkinen
// Licensed to PSF under a Contributor Agreement.
//
// BAML port of `tomli/_parser.py`.
//
// Porting conventions (see PORTING_NOTES.md for the full story):
// * Module-level constants (`Final`) become zero-argument functions: BAML has
//   no top-level `let`/`const`.
// * `frozenset[str]` of characters becomes `CharSet` (see `_compat.baml`).
// * Functions returning Python tuples return `Tuple2`/`Tuple3` instances:
//   BAML has no tuple types.
// * Python's `try: char = src[pos] except IndexError: char = None` idiom maps
//   directly onto `src.at(pos)`, which returns `null` when out of range.
// * `raise X from None` has no BAML counterpart (errors carry no implicit
//   `__context__` unless thrown inside a `catch`), so it is simply `throw X`.

// Python's `lazy import` of `tomli._re` (`__lazy_modules__`) has no BAML
// counterpart: namespaces are not loaded at run time.

/// A 2-tuple (BAML has no tuple types).
class Tuple2<A, B> {
    first: A,
    second: B,
}

/// A 3-tuple (BAML has no tuple types).
class Tuple3<A, B, C> {
    first: A,
    second: B,
    third: C,
}

// Inline tables/arrays are implemented using recursion. Pathologically
// nested documents cause pure Python to raise RecursionError (which is OK),
// but mypyc binary wheels will crash unrecoverably (not OK). According to
// mypyc docs this will be fixed in the future:
// https://mypyc.readthedocs.io/en/latest/differences_from_python.html#stack-overflows
// Before mypyc's fix is in, recursion needs to be limited by this library.
// Choosing `sys.getrecursionlimit()` as maximum inline table/array nesting
// level, as it allows more nesting than pure Python, but still seems a far
// lower number than where mypyc binaries crash.
//
// BAML port: the BAML VM is in the same situation as mypyc -- overflowing its
// call stack is an *uncatchable* `baml.panics.StackOverflow` panic -- and its
// stack is tiny: a fixed 256 frames per task (Python: 1000). A nesting level
// costs up to three frames (`parse_value` -> `parse_inline_table` ->
// `parse_key_value_pair`), so without help inline tables would overflow at
// ~83 levels. Every spawned task gets a fresh frame stack, though, so
// `parse_value` continues parsing on a new task every
// `NESTING_LEVELS_PER_TASK()` levels (see `_nested`). With that, the original
// limit can be kept as is.
function MAX_INLINE_NESTING() -> int {
    getrecursionlimit()
}

/// BAML port: how many inline nesting levels are parsed on one task's frame
/// stack before `_nested` hops to a fresh task. At <= 3 frames per level this
/// uses <= 60 of the 256 frames, leaving plenty for callers and helpers.
function NESTING_LEVELS_PER_TASK() -> int {
    20
}

/// BAML port: runs `f` (which parses one nested array/table at `nest_lvl`) on a
/// fresh task -- and therefore a fresh VM frame stack -- every
/// `NESTING_LEVELS_PER_TASK()` levels. Thrown errors propagate through
/// `await` unchanged.
function _nested<T, E>(nest_lvl: int, f: () -> T throws E) -> T throws E {
    if (nest_lvl % NESTING_LEVELS_PER_TASK() == 0) {
        await spawn { f() }
    } else {
        f()
    }
}

// Pathologically excessive number of parts in a key runs into quadratic
// behavior (e.g. in Flags.is_).
// Even if keys aren't currently parsed using recursion, they name a
// recursive structure, so it makes sense to limit it using getrecursionlimit()
// and RecursionError.
function MAX_KEY_PARTS() -> int {
    getrecursionlimit()
}

function ASCII_CTRL() -> CharSet {
    let cps: int[] = [];
    for (let i = 0; i < 32; i += 1) {
        cps.push(i);
    }
    CharSet.from_code_points(cps).union(CharSet.from_code_points([127]))
}

// Neither of these sets include quotation mark or backslash. They are
// currently handled as separate cases in the parser functions.
function ILLEGAL_BASIC_STR_CHARS() -> CharSet {
    ASCII_CTRL().minus(CharSet.from_string("\t"))
}

function ILLEGAL_MULTILINE_BASIC_STR_CHARS() -> CharSet {
    ASCII_CTRL().minus(CharSet.from_string("\t\n"))
}

function ILLEGAL_LITERAL_STR_CHARS() -> CharSet {
    ILLEGAL_BASIC_STR_CHARS()
}

function ILLEGAL_MULTILINE_LITERAL_STR_CHARS() -> CharSet {
    ILLEGAL_MULTILINE_BASIC_STR_CHARS()
}

function ILLEGAL_COMMENT_CHARS() -> CharSet {
    ILLEGAL_BASIC_STR_CHARS()
}

function TOML_WS() -> CharSet {
    CharSet.from_string(" \t")
}

function TOML_WS_AND_NEWLINE() -> CharSet {
    TOML_WS().union(CharSet.from_string("\n"))
}

function BARE_KEY_CHARS() -> CharSet {
    CharSet.from_string(
        "abcdefghijklmnopqrstuvwxyz" + "ABCDEFGHIJKLMNOPQRSTUVWXYZ" + "0123456789" + "-_",
    )
}

function KEY_INITIAL_CHARS() -> CharSet {
    BARE_KEY_CHARS().union(CharSet.from_string("\"'"))
}

function HEXDIGIT_CHARS() -> CharSet {
    CharSet.from_string("abcdef" + "ABCDEF" + "0123456789")
}

function BASIC_STR_ESCAPE_REPLACEMENTS() -> map<string, string> {
    {
        "\\b": chr(8), // backspace
        "\\t": chr(9), // tab
        "\\n": chr(10), // linefeed
        "\\f": chr(12), // form feed
        "\\r": chr(13), // carriage return
        "\\e": chr(27), // escape
        "\\\"": chr(34), // quote
        "\\\\": chr(92), // backslash
    }
}

/// Sentinel to be used as default arg during deprecation
/// period of TOMLDecodeError's free-form arguments.
///
/// BAML port: Python uses the *class object* as the sentinel; BAML has no
/// class objects as values, so an instance is used and detected with `is`.
class DEPRECATED_DEFAULT {
}

/// An error raised if a document is not valid TOML.
///
/// Adds the following attributes to ValueError:
/// msg: The unformatted error message
/// doc: The TOML document being parsed
/// pos: The index of doc where parsing failed
/// lineno: The line corresponding to pos
/// colno: The column corresponding to pos
///
/// BAML port: Python's `TOMLDecodeError(ValueError)` subclassing cannot be
/// expressed (no inheritance). `args` mirrors `BaseException.args` and
/// `to_string()` mirrors `str(exc)`. The attributes are optional because the
/// deprecated free-form constructor path leaves them unset (Python leaves them
/// *missing*, which raises `AttributeError` on access).
class TOMLDecodeError {
    args: unknown[],
    msg: string?,
    doc: string?,
    pos: Pos?,
    lineno: int?,
    colno: int?,

    /// `TOMLDecodeError(msg, doc, pos)` -- the non-deprecated constructor.
    function new(msg: string, doc: string, pos: Pos) -> TOMLDecodeError {
        TOMLDecodeError.from_args([msg, doc, pos])
    }

    /// Python's `TOMLDecodeError.__init__`, called as `TOMLDecodeError(*args)`.
    ///
    /// BAML port: Python's signature is
    /// `(msg=DEPRECATED_DEFAULT, doc=DEPRECATED_DEFAULT, pos=DEPRECATED_DEFAULT, *args)`.
    /// BAML requires defaulted parameters to be passed *by name* and has no
    /// varargs, so the positional-or-default parameters cannot be expressed;
    /// the whole positional argument list is taken as an array instead.
    function from_args(all_args: unknown[]) -> TOMLDecodeError {
        let msg: unknown = if (all_args.length() > 0) {
            all_args[0]
        } else {
            DEPRECATED_DEFAULT {  }
        };
        let doc: unknown = if (all_args.length() > 1) {
            all_args[1]
        } else {
            DEPRECATED_DEFAULT {  }
        };
        let pos: unknown = if (all_args.length() > 2) {
            all_args[2]
        } else {
            DEPRECATED_DEFAULT {  }
        };
        let args = all_args.slice(3, all_args.length());
        if (args.length() > 0 || !(msg is string) || !(doc is string) || !(pos is int)) {
            warnings_warn(
                "Free-form arguments for TOMLDecodeError are deprecated. "
                    + "Please set 'msg' (str), 'doc' (str) and 'pos' (int) arguments only.",
                "DeprecationWarning",
            );
            if (!(pos is DEPRECATED_DEFAULT)) {
                args = [pos].concat(args);
            }
            if (!(doc is DEPRECATED_DEFAULT)) {
                args = [doc].concat(args);
            }
            if (!(msg is DEPRECATED_DEFAULT)) {
                args = [msg].concat(args);
            }
            // ValueError.__init__(self, *args)
            return TOMLDecodeError {
                args: args,
                msg: null,
                doc: null,
                pos: null,
                lineno: null,
                colno: null,
            };
        }

        let lineno = str_count(doc, "\n", 0, pos) + 1;
        let colno = if (lineno == 1) {
            pos + 1
        } else {
            pos - str_rindex(doc, "\n", 0, pos)
        };

        let coord_repr = if (pos >= doc.length()) {
            "end of document"
        } else {
            "line " + lineno.to_string() + ", column " + colno.to_string()
        };
        let errmsg = msg + " (at " + coord_repr + ")";
        TOMLDecodeError {
            args: [errmsg],
            msg: msg,
            doc: doc,
            pos: pos,
            lineno: lineno,
            colno: colno,
        }
    }

    implements baml.ToString {
        /// Python's `str(exc)` (`BaseException.__str__`).
        function to_string(self) -> string throws never {
            py_exception_str(self.args)
        }
    }
}

/// Parse TOML from a binary file object.
///
/// BAML port: Python's `IO[bytes]` is a `baml.fs.File`. The original's
/// `TypeError` for text-mode files cannot happen: BAML files have no text
/// mode, and the static type rules out other objects.
function load(fp: baml.fs.File, parse_float: ParseFloat? = null) -> map<string, Value> {
    let b = fp.bytes();
    let s = baml.String.from_utf8(b);
    loads(s, parse_float = parse_float)
}

/// Parse TOML from a string.
///
/// BAML port: `parse_float = null` stands for Python's default `float`
/// (BAML cannot compare function values for identity, which is how the
/// original detects the default). The original's `TypeError` for non-`str`
/// input is enforced statically by the parameter type instead.
function loads(s: string, parse_float: ParseFloat? = null) -> map<string, Value> {
    // The spec allows converting "\r\n" to "\n", even in string
    // literals. Let's do so to simplify parsing.
    let src = s.replace_all("\r\n", "\n");
    let pos = 0;
    let out = Output.new();
    let header: Key = [];
    let safe_parse_float = make_safe_parse_float(parse_float);

    // Parse one statement at a time
    // (typically means one line in TOML source)
    while (true) {
        // 1. Skip line leading whitespace
        pos = skip_chars(src, pos, TOML_WS());

        // 2. Parse rules. Expect one of the following:
        //    - end of file
        //    - end of line
        //    - comment
        //    - key/value pair
        //    - append dict to list (and move to its namespace)
        //    - create dict (and move to its namespace)
        // Skip trailing whitespace when applicable.
        let char = src.at(pos);
        if (char == null) {
            break;
        }
        if (char == "\n") {
            pos += 1;
            continue;
        }
        if (KEY_INITIAL_CHARS().contains(char)) {
            pos = key_value_rule(src, pos, out, header, safe_parse_float);
            pos = skip_chars(src, pos, TOML_WS());
        } else if (char == "[") {
            let second_char = src.at(pos + 1);
            out.flags.finalize_pending();
            let r = if (second_char == "[") {
                create_list_rule(src, pos, out)
            } else {
                create_dict_rule(src, pos, out)
            };
            pos = r.first;
            header = r.second;
            pos = skip_chars(src, pos, TOML_WS());
        } else if (char != "#") {
            throw TOMLDecodeError.new("Invalid statement", src, pos);
        }

        // 3. Skip comment
        pos = skip_comment(src, pos);

        // 4. Expect end of line or end of file
        let char2 = src.at(pos);
        if (char2 == null) {
            break;
        }
        if (char2 != "\n") {
            throw TOMLDecodeError.new(
                "Expected newline or end of document after a statement", src, pos
            );
        }
        pos += 1;
    }

    out.data.dict
}

/// Python's `Flags.FROZEN` / `Flags.EXPLICIT_NEST` int constants.
enum Flag {
    // Marks an immutable namespace (inline array or inline table).
    FROZEN,
    // Marks a nest that has been explicitly created and can no longer
    // be opened using the "[table]" syntax.
    EXPLICIT_NEST,
}

/// One node of `Flags._flags`. Python uses an ad-hoc
/// `{"flags": set(), "recursive_flags": set(), "nested": {}}` dict.
class FlagNode {
    flags: Flag[],
    recursive_flags: Flag[],
    nested: map<string, FlagNode>,

    function new() -> FlagNode {
        FlagNode { flags: [], recursive_flags: [], nested: {} }
    }
}

/// Python: an element of `set[tuple[Key, int]]`.
class PendingFlag {
    key: Key,
    flag: Flag,
}

/// Flags that map to parsed keys/namespaces.
class Flags {
    _flags: map<string, FlagNode>,
    _pending_flags: PendingFlag[],

    function new() -> Flags {
        Flags { _flags: {}, _pending_flags: [] }
    }

    function add_pending(self, key: Key, flag: Flag) -> void {
        // A Python `set`: ignore duplicates (structural equality).
        let item = PendingFlag { key: key, flag: flag };
        if (!self._pending_flags.includes(item)) {
            self._pending_flags.push(item);
        }
    }

    function finalize_pending(self) -> void {
        for (let p in self._pending_flags) {
            self.set(p.key, p.flag, recursive = false);
        }
        self._pending_flags.clear();
    }

    function unset_all(self, key: Key) -> void {
        let cont = self._flags;
        for (let k in key.slice(0, key.length() - 1)) {
            let node = cont.get(k);
            if (node == null) {
                return;
            }
            cont = node.nested;
        }
        cont.delete(key[key.length() - 1]);
    }

    function set(self, key: Key, flag: Flag, recursive: bool) -> void {
        let cont = self._flags;
        let key_parent = key.slice(0, key.length() - 1);
        let key_stem = key[key.length() - 1];
        for (let k in key_parent) {
            if (!cont.has(k)) {
                cont.set(k, FlagNode.new());
            }
            cont = cont[k].nested;
        }
        if (!cont.has(key_stem)) {
            cont.set(key_stem, FlagNode.new());
        }
        if (recursive) {
            _set_add(cont[key_stem].recursive_flags, flag);
        } else {
            _set_add(cont[key_stem].flags, flag);
        }
    }

    function is_(self, key: Key, flag: Flag) -> bool {
        if (key.length() == 0) {
            return false; // document root has no flags
        }
        let cont = self._flags;
        for (let k in key.slice(0, key.length() - 1)) {
            let inner_cont = cont.get(k);
            if (inner_cont == null) {
                return false;
            }
            if (inner_cont.recursive_flags.includes(flag)) {
                return true;
            }
            cont = inner_cont.nested;
        }
        let key_stem = key[key.length() - 1];
        let inner = cont.get(key_stem);
        if (inner != null) {
            return inner.flags.includes(flag) || inner.recursive_flags.includes(flag);
        }
        false
    }
}

/// `set.add` on an array used as a set.
function _set_add(s: Flag[], flag: Flag) -> void {
    if (!s.includes(flag)) {
        s.push(flag);
    }
}

class NestedDict {
    // The parsed content of the TOML document
    dict: map<string, Value>,

    function new() -> NestedDict {
        NestedDict { dict: {} }
    }

    function get_or_create_nest(
        self,
        key: Key,
        access_lists: bool = true,
    ) -> map<string, Value> throws KeyError {
        let cont: map<string, Value> = self.dict;
        for (let k in key) {
            if (!cont.has(k)) {
                let fresh: map<string, Value> = {};
                cont.set(k, fresh);
            }
            let next: Value? = cont[k];
            // BAML port (performance): test for the (common) dict case first;
            // a failing `Value[]` test is slow (see `is_dict_or_list`).
            if (access_lists && !(next is map<string, Value>)) {
                if let lst: Value[] = next {
                    next = lst.at(-1);
                }
            }
            cont
                = match (next) {
                    let d: map<string, Value> => d,
                    _ => {
                        throw KeyError { message: "There is no nest behind this key" }
                    },
                };
        }
        cont
    }

    function append_nest_to_list(self, key: Key) -> void throws KeyError {
        let cont = self.get_or_create_nest(key.slice(0, key.length() - 1));
        let last_key = key[key.length() - 1];
        let fresh: map<string, Value> = {};
        if (cont.has(last_key)) {
            let list_ = cont[last_key];
            match (list_) {
                let l: Value[] => {
                    l.push(fresh);
                },
                _ => {
                    throw KeyError { message: "An object other than list found behind this key" }
                },
            }
        } else {
            let l: Value[] = [fresh];
            cont.set(last_key, l);
        }
    }
}

class Output {
    data: NestedDict,
    flags: Flags,

    function new() -> Output {
        Output { data: NestedDict.new(), flags: Flags.new() }
    }
}

function skip_chars(src: string, pos: Pos, chars: CharSet) -> Pos {
    let p = pos;
    while (chars.contains(src.at(p))) {
        p += 1;
    }
    p
}

function skip_until(
    src: string,
    pos: Pos,
    expect: string,
    error_on: CharSet,
    error_on_eof: bool,
) -> Pos throws TOMLDecodeError {
    let found = str_find(src, expect, pos);
    let new_pos = if (found == null) {
        if (error_on_eof) {
            throw TOMLDecodeError.new("Expected " + py_repr_str(expect), src, src.length());
        }
        src.length()
    } else {
        found
    };

    if (!error_on.isdisjoint(src.slice(pos, new_pos))) {
        let p = pos;
        while (!error_on.contains(src.at(p))) {
            p += 1;
        }
        throw TOMLDecodeError.new(
            "Found invalid character " + py_repr_str(src.at(p) ?? ""), src, p
        );
    }
    new_pos
}

function skip_comment(src: string, pos: Pos) -> Pos throws TOMLDecodeError {
    let char = src.at(pos);
    if (char == "#") {
        return skip_until(src, pos + 1, "\n", error_on = ILLEGAL_COMMENT_CHARS(), error_on_eof = false);
    }
    pos
}

function skip_comments_and_array_ws(src: string, pos: Pos) -> Pos throws TOMLDecodeError {
    let p = pos;
    while (true) {
        let pos_before_skip = p;
        p = skip_chars(src, p, TOML_WS_AND_NEWLINE());
        p = skip_comment(src, p);
        if (p == pos_before_skip) {
            return p;
        }
    }
    p
}

function create_dict_rule(src: string, pos: Pos, out: Output) -> Tuple2<Pos, Key> {
    let p = pos + 1; // Skip "["
    p = skip_chars(src, p, TOML_WS());
    let r = parse_key(src, p);
    p = r.first;
    let key = r.second;

    if (out.flags.is_(key, Flag.EXPLICIT_NEST) || out.flags.is_(key, Flag.FROZEN)) {
        throw TOMLDecodeError.new("Cannot declare " + py_repr_key(key) + " twice", src, p);
    }
    out.flags.set(key, Flag.EXPLICIT_NEST, recursive = false);
    out.data.get_or_create_nest(key) catch (e) {
        KeyError => {
            throw TOMLDecodeError.new("Cannot overwrite a value", src, p)
        },
    };

    if (!src.slice(p, src.length()).starts_with("]")) {
        throw TOMLDecodeError.new(
            "Expected ']' at the end of a table declaration", src, p
        );
    }
    Tuple2 { first: p + 1, second: key }
}

function create_list_rule(src: string, pos: Pos, out: Output) -> Tuple2<Pos, Key> {
    let p = pos + 2; // Skip "[["
    p = skip_chars(src, p, TOML_WS());
    let r = parse_key(src, p);
    p = r.first;
    let key = r.second;

    if (out.flags.is_(key, Flag.FROZEN)) {
        throw TOMLDecodeError.new(
            "Cannot mutate immutable namespace " + py_repr_key(key), src, p
        );
    }
    // Free the namespace now that it points to another empty list item...
    out.flags.unset_all(key);
    // ...but this key precisely is still prohibited from table declaration
    out.flags.set(key, Flag.EXPLICIT_NEST, recursive = false);
    out.data.append_nest_to_list(key) catch (e) {
        KeyError => {
            throw TOMLDecodeError.new("Cannot overwrite a value", src, p)
        },
    };

    if (!src.slice(p, src.length()).starts_with("]]")) {
        throw TOMLDecodeError.new(
            "Expected ']]' at the end of an array declaration", src, p
        );
    }
    Tuple2 { first: p + 2, second: key }
}

function key_value_rule(
    src: string,
    pos: Pos,
    out: Output,
    header: Key,
    parse_float: ParseFloat,
) -> Pos {
    let r = parse_key_value_pair(src, pos, parse_float, 0);
    let p = r.first;
    let key = r.second;
    let value = r.third;
    let key_parent = key.slice(0, key.length() - 1);
    let key_stem = key[key.length() - 1];
    let abs_key_parent = header.concat(key_parent);

    // Python: `relative_path_cont_keys = (header + key[:i] for i in range(1, len(key)))`
    for (let i = 1; i < key.length(); i += 1) {
        let cont_key = header.concat(key.slice(0, i));
        // Check that dotted key syntax does not redefine an existing table
        if (out.flags.is_(cont_key, Flag.EXPLICIT_NEST)) {
            throw TOMLDecodeError.new(
                "Cannot redefine namespace " + py_repr_key(cont_key), src, p
            );
        }
        // Containers in the relative path can't be opened with the table syntax or
        // dotted key/value syntax in following table sections.
        out.flags.add_pending(cont_key, Flag.EXPLICIT_NEST);
    }

    if (out.flags.is_(abs_key_parent, Flag.FROZEN)) {
        throw TOMLDecodeError.new(
            "Cannot mutate immutable namespace " + py_repr_key(abs_key_parent), src, p
        );
    }

    let nest = out.data.get_or_create_nest(abs_key_parent) catch (e) {
        KeyError => {
            throw TOMLDecodeError.new("Cannot overwrite a value", src, p)
        },
    };
    if (nest.has(key_stem)) {
        throw TOMLDecodeError.new("Cannot overwrite a value", src, p);
    }
    // Mark inline table and array namespaces recursively immutable
    if (is_dict_or_list(value)) {
        out.flags.set(header.concat(key), Flag.FROZEN, recursive = true);
    }
    nest.set(key_stem, value);
    p
}

/// Python's `isinstance(value, (dict, list))`.
///
/// BAML port (performance): a *failing* run-time test of a value against
/// `map<string, Value>` / `Value[]` is very slow (~170us per test in a release
/// build, growing with the size of the recursive `Value` alias; see
/// PORTING_NOTES.md), while a succeeding one, or a test against a scalar type,
/// is ~free. So scalars are ruled out first.
function is_dict_or_list(value: Value) -> bool {
    match (value) {
        let s: string => false,
        let b: bool => false,
        let i: bigint => false,
        let f: float => false,
        let zdt: baml.time.ZonedDateTime => false,
        let pdt: baml.time.PlainDateTime => false,
        let pd: baml.time.PlainDate => false,
        let pt: baml.time.PlainTime => false,
        let d: map<string, Value> => true,
        let l: Value[] => true,
        _ => false,
    }
}

function parse_key_value_pair(
    src: string,
    pos: Pos,
    parse_float: ParseFloat,
    nest_lvl: int,
) -> Tuple3<Pos, Key, Value> {
    let r = parse_key(src, pos);
    let p = r.first;
    let key = r.second;
    let char = src.at(p);
    if (char != "=") {
        throw TOMLDecodeError.new("Expected '=' after a key in a key/value pair", src, p);
    }
    p += 1;
    p = skip_chars(src, p, TOML_WS());
    let rv = parse_value(src, p, parse_float, nest_lvl);
    Tuple3 { first: rv.first, second: key, third: rv.second }
}

function parse_key(
    src: string,
    pos: Pos,
) -> Tuple2<Pos, Key> throws TOMLDecodeError | RecursionError {
    let r = parse_key_part(src, pos);
    let p = r.first;
    let key: Key = [r.second];
    p = skip_chars(src, p, TOML_WS());
    while (true) {
        let char = src.at(p);
        if (char != ".") {
            return Tuple2 { first: p, second: key };
        }
        p += 1;
        p = skip_chars(src, p, TOML_WS());
        let rp = parse_key_part(src, p);
        p = rp.first;
        // Python: `key += (key_part,)` builds a new tuple.
        key = key.concat([rp.second]);
        if (key.length() > MAX_KEY_PARTS()) {
            throw RecursionError {
                message: "TOML key has more than the allowed " + MAX_KEY_PARTS().to_string() + " parts",
            };
        }
        p = skip_chars(src, p, TOML_WS());
    }
    Tuple2 { first: p, second: key }
}

function parse_key_part(src: string, pos: Pos) -> Tuple2<Pos, string> throws TOMLDecodeError {
    let char = src.at(pos);
    if (BARE_KEY_CHARS().contains(char)) {
        let start_pos = pos;
        let p = skip_chars(src, pos, BARE_KEY_CHARS());
        return Tuple2 { first: p, second: src.slice(start_pos, p) };
    }
    if (char == "'") {
        return parse_literal_str(src, pos);
    }
    if (char == "\"") {
        return parse_one_line_basic_str(src, pos);
    }
    throw TOMLDecodeError.new("Invalid initial character for a key part", src, pos);
}

function parse_one_line_basic_str(
    src: string,
    pos: Pos,
) -> Tuple2<Pos, string> throws TOMLDecodeError {
    parse_basic_str(src, pos + 1, multiline = false)
}

function parse_array(
    src: string,
    pos: Pos,
    parse_float: ParseFloat,
    nest_lvl: int,
) -> Tuple2<Pos, Value[]> {
    let p = pos + 1;
    let array: Value[] = [];

    p = skip_comments_and_array_ws(src, p);
    if (src.slice(p, src.length()).starts_with("]")) {
        return Tuple2 { first: p + 1, second: array };
    }
    while (true) {
        let rv = parse_value(src, p, parse_float, nest_lvl);
        p = rv.first;
        array.push(rv.second);
        p = skip_comments_and_array_ws(src, p);

        let c = src.slice(p, p + 1);
        if (c == "]") {
            return Tuple2 { first: p + 1, second: array };
        }
        if (c != ",") {
            throw TOMLDecodeError.new("Unclosed array", src, p);
        }
        p += 1;

        p = skip_comments_and_array_ws(src, p);
        if (src.slice(p, src.length()).starts_with("]")) {
            return Tuple2 { first: p + 1, second: array };
        }
    }
    Tuple2 { first: p, second: array }
}

function parse_inline_table(
    src: string,
    pos: Pos,
    parse_float: ParseFloat,
    nest_lvl: int,
) -> Tuple2<Pos, map<string, Value>> {
    let p = pos + 1;
    let nested_dict = NestedDict.new();
    let flags = Flags.new();

    p = skip_comments_and_array_ws(src, p);
    if (src.slice(p, src.length()).starts_with("}")) {
        return Tuple2 { first: p + 1, second: nested_dict.dict };
    }
    while (true) {
        let r = parse_key_value_pair(src, p, parse_float, nest_lvl);
        p = r.first;
        let key = r.second;
        let value = r.third;
        let key_parent = key.slice(0, key.length() - 1);
        let key_stem = key[key.length() - 1];
        if (flags.is_(key, Flag.FROZEN)) {
            throw TOMLDecodeError.new(
                "Cannot mutate immutable namespace " + py_repr_key(key), src, p
            );
        }
        let nest = nested_dict.get_or_create_nest(key_parent, access_lists = false) catch (e) {
            KeyError => {
                throw TOMLDecodeError.new("Cannot overwrite a value", src, p)
            },
        };
        if (nest.has(key_stem)) {
            throw TOMLDecodeError.new(
                "Duplicate inline table key " + py_repr_str(key_stem), src, p
            );
        }
        nest.set(key_stem, value);
        p = skip_comments_and_array_ws(src, p);
        let c = src.slice(p, p + 1);
        if (c == "}") {
            return Tuple2 { first: p + 1, second: nested_dict.dict };
        }
        if (c != ",") {
            throw TOMLDecodeError.new("Unclosed inline table", src, p);
        }
        p += 1;
        p = skip_comments_and_array_ws(src, p);
        if (src.slice(p, src.length()).starts_with("}")) {
            return Tuple2 { first: p + 1, second: nested_dict.dict };
        }
        if (is_dict_or_list(value)) {
            flags.set(key, Flag.FROZEN, recursive = true);
        }
    }
    Tuple2 { first: p, second: nested_dict.dict }
}

function parse_basic_str_escape(
    src: string,
    pos: Pos,
    multiline: bool = false,
) -> Tuple2<Pos, string> throws TOMLDecodeError {
    let escape_id = src.slice(pos, pos + 2);
    let p = pos + 2;
    if (multiline && (escape_id == "\\ " || escape_id == "\\\t" || escape_id == "\\\n")) {
        // Skip whitespace until next non-whitespace character or end of
        // the doc. Error if non-whitespace is found before newline.
        if (escape_id != "\\\n") {
            p = skip_chars(src, p, TOML_WS());
            let char = src.at(p);
            if (char == null) {
                return Tuple2 { first: p, second: "" };
            }
            if (char != "\n") {
                throw TOMLDecodeError.new("Unescaped '\\' in a string", src, p);
            }
            p += 1;
        }
        p = skip_chars(src, p, TOML_WS_AND_NEWLINE());
        return Tuple2 { first: p, second: "" };
    }
    if (escape_id == "\\x") {
        return parse_hex_char(src, p, 2);
    }
    if (escape_id == "\\u") {
        return parse_hex_char(src, p, 4);
    }
    if (escape_id == "\\U") {
        return parse_hex_char(src, p, 8);
    }
    let replacement = BASIC_STR_ESCAPE_REPLACEMENTS().get(escape_id);
    if (replacement == null) {
        throw TOMLDecodeError.new("Unescaped '\\' in a string", src, p);
    }
    Tuple2 { first: p, second: replacement }
}

function parse_basic_str_escape_multiline(
    src: string,
    pos: Pos,
) -> Tuple2<Pos, string> throws TOMLDecodeError {
    parse_basic_str_escape(src, pos, multiline = true)
}

function parse_hex_char(
    src: string,
    pos: Pos,
    hex_len: int,
) -> Tuple2<Pos, string> throws TOMLDecodeError {
    let hex_str = src.slice(pos, pos + hex_len);
    if (hex_str.length() != hex_len || !HEXDIGIT_CHARS().issuperset(hex_str)) {
        throw TOMLDecodeError.new("Invalid hex value", src, pos);
    }
    let p = pos + hex_len;
    let hex_int = py_int_digits(hex_str, 16) catch (e) {
        ValueError => {
            throw TOMLDecodeError.new("Invalid hex value", src, pos)
        },
    };
    if (!is_unicode_scalar_value(hex_int)) {
        throw TOMLDecodeError.new(
            "Escaped character is not a Unicode scalar value", src, p
        );
    }
    Tuple2 { first: p, second: chr(bigint_to_int(hex_int)) }
}

function parse_literal_str(src: string, pos: Pos) -> Tuple2<Pos, string> throws TOMLDecodeError {
    let p = pos + 1; // Skip starting apostrophe
    let start_pos = p;
    p = skip_until(src, p, "'", error_on = ILLEGAL_LITERAL_STR_CHARS(), error_on_eof = true);
    Tuple2 { first: p + 1, second: src.slice(start_pos, p) } // Skip ending apostrophe
}

function parse_multiline_str(
    src: string,
    pos: Pos,
    literal: bool,
) -> Tuple2<Pos, string> throws TOMLDecodeError {
    let p = pos + 3;
    if (src.slice(p, src.length()).starts_with("\n")) {
        p += 1;
    }

    let delim = "";
    let result = "";
    if (literal) {
        delim = "'";
        let end_pos = skip_until(src, p, "'''", error_on = ILLEGAL_MULTILINE_LITERAL_STR_CHARS(), error_on_eof = true);
        result = src.slice(p, end_pos);
        p = end_pos + 3;
    } else {
        delim = "\"";
        let r = parse_basic_str(src, p, multiline = true);
        p = r.first;
        result = r.second;
    }

    // Add at maximum two extra apostrophes/quotes if the end sequence
    // is 4 or 5 chars long instead of just 3.
    if (!src.slice(p, src.length()).starts_with(delim)) {
        return Tuple2 { first: p, second: result };
    }
    p += 1;
    if (!src.slice(p, src.length()).starts_with(delim)) {
        return Tuple2 { first: p, second: result + delim };
    }
    p += 1;
    Tuple2 { first: p, second: result + delim + delim }
}

function parse_basic_str(
    src: string,
    pos: Pos,
    multiline: bool,
) -> Tuple2<Pos, string> throws TOMLDecodeError {
    let error_on = if (multiline) {
        ILLEGAL_MULTILINE_BASIC_STR_CHARS()
    } else {
        ILLEGAL_BASIC_STR_CHARS()
    };
    let parse_escapes = if (multiline) {
        parse_basic_str_escape_multiline
    } else {
        (s: string, p: Pos) -> Tuple2<Pos, string> throws TOMLDecodeError {
            parse_basic_str_escape(s, p)
        }
    };
    let result = "";
    let p = pos;
    let start_pos = p;
    while (true) {
        let char = src.at(p);
        if (char == null) {
            throw TOMLDecodeError.new("Unterminated string", src, p);
        }
        if (char == "\"") {
            if (!multiline) {
                return Tuple2 { first: p + 1, second: result + src.slice(start_pos, p) };
            }
            if (src.slice(p, src.length()).starts_with("\"\"\"")) {
                return Tuple2 { first: p + 3, second: result + src.slice(start_pos, p) };
            }
            p += 1;
            continue;
        }
        if (char == "\\") {
            result += src.slice(start_pos, p);
            let r = parse_escapes(src, p);
            p = r.first;
            result += r.second;
            start_pos = p;
            continue;
        }
        if (error_on.contains(char)) {
            throw TOMLDecodeError.new("Illegal character " + py_repr_str(char), src, p);
        }
        p += 1;
    }
    Tuple2 { first: p, second: result }
}

function parse_value(
    src: string,
    pos: Pos,
    parse_float: ParseFloat,
    nest_lvl: int,
) -> Tuple2<Pos, Value> {
    if (nest_lvl > MAX_INLINE_NESTING()) {
        // Pure Python should have raised RecursionError already.
        // This ensures mypyc binaries eventually do the same.
        throw RecursionError {
            message: "TOML inline arrays/tables are nested more than the allowed"
                + " " + MAX_INLINE_NESTING().to_string() + " levels",
        };
    }

    let char = src.at(pos);
    let rest = src.slice(pos, src.length());

    // IMPORTANT: order conditions based on speed of checking and likelihood

    // Basic strings
    if (char == "\"") {
        if (rest.starts_with("\"\"\"")) {
            return _widen(parse_multiline_str(src, pos, literal = false));
        }
        return _widen(parse_one_line_basic_str(src, pos));
    }

    // Literal strings
    if (char == "'") {
        if (rest.starts_with("'''")) {
            return _widen(parse_multiline_str(src, pos, literal = true));
        }
        return _widen(parse_literal_str(src, pos));
    }

    // Booleans
    if (char == "t") {
        if (rest.starts_with("true")) {
            return Tuple2 { first: pos + 4, second: true };
        }
    }
    if (char == "f") {
        if (rest.starts_with("false")) {
            return Tuple2 { first: pos + 5, second: false };
        }
    }

    // Arrays
    if (char == "[") {
        let ra = _nested(nest_lvl + 1, () -> {
            parse_array(src, pos, parse_float, nest_lvl + 1)
        });
        return Tuple2 { first: ra.first, second: ra.second };
    }

    // Inline tables
    if (char == "{") {
        let rt = _nested(nest_lvl + 1, () -> {
            parse_inline_table(src, pos, parse_float, nest_lvl + 1)
        });
        return Tuple2 { first: rt.first, second: rt.second };
    }

    // Dates and times
    let datetime_match = re_match_at(RE_DATETIME(), src, pos);
    if (datetime_match != null) {
        let datetime_obj = match_to_datetime(datetime_match) catch (e) {
            ValueError => {
                throw TOMLDecodeError.new("Invalid date or datetime", src, pos)
            },
        };
        return Tuple2 { first: datetime_match.end(), second: datetime_obj };
    }
    let localtime_match = re_match_at(RE_LOCALTIME(), src, pos);
    if (localtime_match != null) {
        return Tuple2 { first: localtime_match.end(), second: match_to_localtime(localtime_match) };
    }

    // Integers and "normal" floats.
    // The regex will greedily match any type starting with a decimal
    // char, so needs to be located after handling of dates and times.
    let number_match = re_match_at(RE_NUMBER(), src, pos);
    if (number_match != null) {
        return Tuple2 { first: number_match.end(), second: match_to_number(number_match, parse_float) };
    }

    // Special floats
    let first_three = src.slice(pos, pos + 3);
    if (first_three == "inf" || first_three == "nan") {
        return Tuple2 { first: pos + 3, second: parse_float(first_three) };
    }
    let first_four = src.slice(pos, pos + 4);
    if (first_four == "-inf" || first_four == "+inf" || first_four == "-nan" || first_four == "+nan") {
        return Tuple2 { first: pos + 4, second: parse_float(first_four) };
    }

    throw TOMLDecodeError.new("Invalid value", src, pos);
}

/// Re-types a `Tuple2<Pos, string>` as `Tuple2<Pos, Value>` (generic classes
/// are invariant, so this needs a copy).
function _widen(t: Tuple2<Pos, string>) -> Tuple2<Pos, Value> {
    Tuple2 { first: t.first, second: t.second }
}

function is_unicode_scalar_value(codepoint: bigint) -> bool {
    (0n <= codepoint && codepoint <= 55295n) || (57344n <= codepoint && codepoint <= 1114111n)
}

/// A decorator to make `parse_float` safe.
///
/// `parse_float` must not return dicts or lists, because these types
/// would be mixed with parsed TOML tables and arrays, thus confusing
/// the parser. The returned decorated callable raises `ValueError`
/// instead of returning illegal types.
function make_safe_parse_float(parse_float: ParseFloat?) -> ParseFloat {
    // The default `float` callable never returns illegal types. Optimize it.
    if (parse_float == null) {
        return (float_str: string) -> Value {
            py_float(float_str)
        };
    }

    // NOTE: the narrowing of `parse_float` (non-null after the early return)
    // is lost inside the closure (E0006 "`... | null` is not a function"), so
    // re-bind it to a narrowed local first.
    let inner: ParseFloat = parse_float;
    (float_str: string) -> Value {
        let float_value = inner(float_str);
        if (is_dict_or_list(float_value)) {
            throw ValueError { message: "parse_float must not return dicts or lists" };
        }
        float_value
    }
}
