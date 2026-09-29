// Ported from sasso `src/builtins/list.rs` `#[cfg(test)] mod tests`
// (namespace `root.builtins.list.tests`; `use super::*` →
// `root.builtins.list.*`, plus the parent's imports `root.value.*`,
// `root.scanner.Pos`, `root.error.Error`).

function pos() -> root.scanner.Pos {
    root.scanner.Pos { line: 1, col: 1 }
}

function n(value: float) -> root.value.Value {
    root.value.Value_Number { _0: root.value.Number.unitless(value) }
}

function num_unit(value: float, unit: string) -> root.value.Value {
    root.value.Value_Number { _0: root.value.Number.with_unit(value, unit) }
}

function s(text: string) -> root.value.Value {
    root.value.Value_Str { _0: root.value.SassStr { text: text, quoted: false } }
}

function list(items: root.value.Value[], sep: root.value.ListSep) -> root.value.Value {
    root.value.Value_List {
        _0: root.value.List { items: items, sep: sep, bracketed: false, keywords: null },
    }
}

function call(name: string, args: root.value.Value[]) -> root.value.Value {
    let named: root.std.Tuple2<string, root.value.Value>[] = [];
    let r = root.std.expect(
        root.builtins.list.try_call(name, args, named, pos()),
        "name owned by list family",
    );
    // PORT: `Result::expect("no error")` on the stored `Ok`/`Err` value.
    match (r) {
        let ok: root.std.Ok<root.value.Value> => ok.value,
        let err: root.std.Err<root.error.Error> => root.std.panic(`no error: ${err.error.message}`),
    }
}

function call_err(name: string, args: root.value.Value[]) -> root.error.Error {
    let named: root.std.Tuple2<string, root.value.Value>[] = [];
    let r = root.std.expect(
        root.builtins.list.try_call(name, args, named, pos()),
        "name owned by list family",
    );
    // PORT: `Result::expect_err("expected error")` on the stored `Ok`/`Err` value.
    match (r) {
        let ok: root.std.Ok<root.value.Value> => {
            root.std.panic(`expected error: ${ok.value.to_css(false)}`)
        },
        let err: root.std.Err<root.error.Error> => err.error,
    }
}

test "length_counts_elements" {
    let empty: root.value.Value[] = [];
    assert.equal(call("length", [list(empty, root.value.ListSep.Space)]).to_css(false), "0");
    assert.equal(call("length", [num_unit(5.0, "px")]).to_css(false), "1");
    assert.equal(
        call(
            "length",
            [
                list(
                    [num_unit(1.0, "px"), num_unit(2.0, "px"), num_unit(3.0, "px")],
                    root.value.ListSep.Space,
                ),
            ],
        )
            .to_css(false),
        "3",
    )
}

test "nth_one_based_and_negative" {
    let l = list([s("a"), s("b"), s("c")], root.value.ListSep.Space);
    // PORT: `l.clone()` → `l` (neither copy is mutated).
    assert.equal(call("nth", [l, n(1.0)]).to_css(false), "a");
    assert.equal(call("nth", [l, n(-1.0)]).to_css(false), "c");
    // Single non-list value behaves as a one-element list.
    assert.equal(call("nth", [s("solo"), n(1.0)]).to_css(false), "solo")
}

test "nth_index_errors" {
    let l = list([s("a"), s("b"), s("c")], root.value.ListSep.Space);
    assert.equal(call_err("nth", [l, n(0.0)]).message, "$n: List index may not be 0.");
    assert.equal(
        call_err("nth", [l, n(5.0)]).message,
        "$n: Invalid index 5 for a list with 3 elements.",
    );
    assert.equal(call_err("nth", [l, n(1.5)]).message, "$n: 1.5 is not an int.")
}

test "set_nth_replaces_and_keeps_separator" {
    let l = list([s("a"), s("b"), s("c")], root.value.ListSep.Space);
    assert.equal(call("set-nth", [l, n(2.0), s("x")]).to_css(false), "a x c");
    assert.equal(call("set-nth", [l, n(-1.0), s("z")]).to_css(false), "a b z");
    // Single value -> one-element list.
    assert.equal(call("set-nth", [s("a"), n(1.0), s("z")]).to_css(false), "z")
}

test "join_default_uses_list1_separator" {
    let a = list([num_unit(1.0, "px"), num_unit(2.0, "px")], root.value.ListSep.Space);
    let b = list([num_unit(3.0, "px"), num_unit(4.0, "px")], root.value.ListSep.Space);
    assert.equal(call("join", [a, b]).to_css(false), "1px 2px 3px 4px");

    let c = list([s("a"), s("b")], root.value.ListSep.Comma);
    let d = list([s("c"), s("d")], root.value.ListSep.Comma);
    assert.equal(call("join", [c, d]).to_css(false), "a, b, c, d")
}

test "join_single_list_borrows_list2_separator" {
    // list1 has <2 items, so list2's comma wins.
    let a = s("a");
    let b = list([s("b"), s("c")], root.value.ListSep.Comma);
    assert.equal(call("join", [a, b]).to_css(false), "a, b, c")
}

test "join_explicit_separator" {
    let a = list([num_unit(1.0, "px"), num_unit(2.0, "px")], root.value.ListSep.Space);
    assert.equal(call("join", [a, num_unit(3.0, "px"), s("comma")]).to_css(false), "1px, 2px, 3px")
}

test "append_default_and_explicit" {
    let a = list([num_unit(1.0, "px"), num_unit(2.0, "px")], root.value.ListSep.Space);
    assert.equal(call("append", [a, num_unit(3.0, "px")]).to_css(false), "1px 2px 3px");
    let c = list([s("a"), s("b")], root.value.ListSep.Comma);
    assert.equal(call("append", [c, s("c")]).to_css(false), "a, b, c");
    assert.equal(
        call("append", [a, num_unit(3.0, "px"), s("comma")]).to_css(false),
        "1px, 2px, 3px",
    )
}

test "append_to_empty_list" {
    let empty: root.value.Value[] = [];
    assert.equal(call("append", [list(empty, root.value.ListSep.Space), s("x")]).to_css(false), "x")
}

test "index_finds_or_null" {
    let l = list([s("a"), s("b"), s("c")], root.value.ListSep.Space);
    assert.equal(call("index", [l, s("b")]).to_css(false), "2");
    assert.is_true(call("index", [l, s("z")]) is root.value.Value_Null);
    // Number equality is by value+unit.
    let nums = list([num_unit(1.0, "px"), num_unit(2.0, ""), num_unit(3.0, "px")], root.value.ListSep.Space);
    assert.is_true(call("index", [nums, num_unit(2.0, "px")]) is root.value.Value_Null)
}

test "list_separator_reports_keyword" {
    let empty: root.value.Value[] = [];
    assert.equal(
        call("list-separator", [list([s("a"), s("b")], root.value.ListSep.Comma)]).to_css(false),
        "comma",
    );
    assert.equal(
        call("list-separator", [list([s("a"), s("b")], root.value.ListSep.Space)]).to_css(false),
        "space",
    );
    // A bare value (not a list) -> space.
    assert.equal(call("list-separator", [s("a")]).to_css(false), "space");
    // A deliberately comma-separated empty list (e.g. the result of
    // `map.keys(())`) reports comma; a space-separated empty list (the
    // literal `()`) stays undecided and reports space.
    assert.equal(
        call("list-separator", [list(empty, root.value.ListSep.Comma)]).to_css(false),
        "comma",
    );
    assert.equal(
        call("list-separator", [list(empty, root.value.ListSep.Space)]).to_css(false),
        "space",
    )
}

test "is_bracketed_reports_flag" {
    let empty: root.value.Value[] = [];
    let bracketed: root.value.Value = root.value.Value_List {
        _0: root.value.List {
            items: [s("a"), s("b")],
            sep: root.value.ListSep.Space,
            bracketed: true,
            keywords: null,
        },
    };
    assert.is_true(
        match (call("is-bracketed", [bracketed])) {
            root.value.Value_Bool { _0: true } => true,
            _ => false,
        },
    );
    assert.is_true(
        match (call("is-bracketed", [list([s("a"), s("b")], root.value.ListSep.Space)])) {
            root.value.Value_Bool { _0: false } => true,
            _ => false,
        },
    );
    // A bare value and an empty list are not bracketed.
    assert.is_true(
        match (call("is-bracketed", [s("a")])) {
            root.value.Value_Bool { _0: false } => true,
            _ => false,
        },
    );
    assert.is_true(
        match (call("is-bracketed", [list(empty, root.value.ListSep.Space)])) {
            root.value.Value_Bool { _0: false } => true,
            _ => false,
        },
    )
}

test "zip_interleaves_to_shortest" {
    let a = list([n(1.0), n(2.0), n(3.0)], root.value.ListSep.Space);
    let b = list([s("c"), s("d"), s("e")], root.value.ListSep.Space);
    assert.equal(call("zip", [a, b]).to_css(false), "1 c, 2 d, 3 e");
    // Truncates to the shortest input.
    let a = list([n(1.0), n(2.0), n(3.0)], root.value.ListSep.Space);
    let b = list([s("c"), s("d")], root.value.ListSep.Space);
    assert.equal(call("zip", [a, b]).to_css(false), "1 c, 2 d");
    // A single list yields one element per row.
    let a = list([s("a"), s("b"), s("c")], root.value.ListSep.Space);
    assert.equal(call("zip", [a]).to_css(false), "a, b, c")
}

test "rejects_unknown_names_and_bad_separator" {
    let named: root.std.Tuple2<string, root.value.Value>[] = [];
    assert.is_true(root.builtins.list.try_call("frobnicate", [s("x")], named, pos()) == null);
    let err = call_err("join", [s("a"), s("b"), s("dash")]);
    assert.equal(err.message, "$separator: Must be \"space\", \"comma\", \"slash\", or \"auto\".")
}
