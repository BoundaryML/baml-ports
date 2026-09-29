// Ported from sasso `src/builtins/string.rs` `#[cfg(test)] mod tests`
// (namespace `root.builtins.string.tests`; `use super::*` →
// `root.builtins.string.*`, plus the parent's imports `root.value.*`,
// `root.scanner.Pos`, `root.error.Error`).

function pos() -> root.scanner.Pos {
    root.scanner.Pos { line: 1, col: 1 }
}

function s(text: string, quoted: bool) -> root.value.Value {
    root.value.Value_Str { _0: root.value.SassStr { text: text, quoted: quoted } }
}

function n(value: float) -> root.value.Value {
    root.value.Value_Number { _0: root.value.Number.unitless(value) }
}

function call(name: string, args: root.value.Value[]) -> root.value.Value {
    let named: root.std.Tuple2<string, root.value.Value>[] = [];
    let r = root.std.expect(
        root.builtins.string.try_call(name, args, named, pos()),
        "name owned by string family",
    );
    // PORT: `Result::expect("no error")` on the stored `Ok`/`Err` value.
    match (r) {
        let ok: root.std.Ok<root.value.Value> => ok.value,
        let err: root.std.Err<root.error.Error> => root.std.panic(`no error: ${err.error.message}`),
    }
}

// PORT: helper for Rust's `Result::is_err()` on the stored `Ok`/`Err` value
// (`err.expect("owned").is_err()` → `is_err(root.std.expect(err, "owned"))`).
function is_err(r: root.std.Ok<root.value.Value> | root.std.Err<root.error.Error>) -> bool {
    match (r) {
        let _ok: root.std.Ok<root.value.Value> => false,
        let _err: root.std.Err<root.error.Error> => true,
    }
}

test "quote_and_unquote_flip_quotedness" {
    assert.equal(call("quote", [s("hello", false)]).to_css(false), "\"hello\"");
    assert.equal(call("unquote", [s("foo", true)]).to_css(false), "foo")
}

test "quote_rejects_non_strings" {
    let named: root.std.Tuple2<string, root.value.Value>[] = [];
    let err = root.builtins.string.try_call("quote", [n(42.0)], named, pos());
    assert.is_true(is_err(root.std.expect(err, "owned")));
    let err = root.builtins.string.try_call("unquote", [root.value.Value_Bool { _0: true }], named, pos());
    assert.is_true(is_err(root.std.expect(err, "owned")))
}

test "case_change_is_ascii_and_preserves_quoting" {
    assert.equal(call("to-upper-case", [s("aBc-Def", true)]).to_css(false), "\"ABC-DEF\"");
    assert.equal(call("to-lower-case", [s("ABC", false)]).to_css(false), "abc")
}

test "str_length_counts_unicode_chars" {
    assert.equal(call("str-length", [s("hello", true)]).to_css(false), "5");
    assert.equal(call("str-length", [s("café", true)]).to_css(false), "4")
}

test "str_index_is_one_based_or_null" {
    assert.equal(call("str-index", [s("Hello World", true), s("o", true)]).to_css(false), "5");
    assert.is_true(call("str-index", [s("abc", true), s("z", true)]) is root.value.Value_Null)
}

test "str_slice_handles_negatives_and_defaults" {
    assert.equal(call("str-slice", [s("abcdef", true), n(2.0), n(4.0)]).to_css(false), "\"bcd\"");
    assert.equal(call("str-slice", [s("abcdef", true), n(2.0)]).to_css(false), "\"bcdef\"");
    assert.equal(call("str-slice", [s("abcdef", true), n(-3.0), n(-1.0)]).to_css(false), "\"def\"");
    // start > end yields empty; start 0 acts like 1.
    assert.equal(call("str-slice", [s("abcdef", true), n(4.0), n(2.0)]).to_css(false), "\"\"");
    assert.equal(call("str-slice", [s("abcde", false), n(0.0), n(3.0)]).to_css(false), "abc");
    // end 0 resolves before the first char -> empty.
    assert.equal(call("str-slice", [s("abcde", true), n(2.0), n(0.0)]).to_css(false), "\"\"")
}

test "str_insert_positions_and_clamps" {
    assert.equal(
        call("str-insert", [s("abc", true), s("X", true), n(2.0)]).to_css(false),
        "\"aXbc\"",
    );
    assert.equal(
        call("str-insert", [s("abc", true), s("X", true), n(-1.0)]).to_css(false),
        "\"abcX\"",
    );
    assert.equal(
        call("str-insert", [s("abc", true), s("X", true), n(100.0)]).to_css(false),
        "\"abcX\"",
    );
    assert.equal(call("str-insert", [s("abc", false), s("X", true), n(-5.0)]).to_css(false), "Xabc")
}

test "rejects_unknown_names_and_units" {
    let named: root.std.Tuple2<string, root.value.Value>[] = [];
    assert.is_true(
        root.builtins.string.try_call("frobnicate", [s("x", true)], named, pos()) == null,
    );
    let unit_idx = root.value.Value_Number { _0: root.value.Number.with_unit(2.0, "px") };
    let err = root.builtins.string.try_call("str-slice", [s("abc", true), unit_idx], named, pos());
    assert.is_true(is_err(root.std.expect(err, "owned")))
}
