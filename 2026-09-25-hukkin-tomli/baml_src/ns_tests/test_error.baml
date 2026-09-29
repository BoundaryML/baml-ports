// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2021 Taneli Hukkinen
// Licensed to PSF under a Contributor Agreement.
//
// BAML port of `tests/test_error.py`.
//
// `with self.assertRaises(X) as exc_info:` becomes a helper that runs the
// code, catches `X`, and returns `str(exc_info.exception)` -- or panics when
// nothing (or something else) was thrown.

/// `assertRaises(tomllib.TOMLDecodeError)` around `tomllib.loads(doc)`;
/// returns `str(exc_info.exception)`.
function decode_error_str(doc: string) -> string {
    let _ = root.tomli.loads(doc) catch (e) {
        root.tomli.TOMLDecodeError => {
            return e.to_string();
        },
    };
    baml.sys.panic("TOMLDecodeError not raised")
}

testset "TestError" {
    test "test_line_and_col" {
        assert.equal(decode_error_str("val=."), "Invalid value (at line 1, column 5)");
        assert.equal(decode_error_str("."), "Invalid statement (at line 1, column 1)");
        assert.equal(decode_error_str("\n\nval=."), "Invalid value (at line 3, column 5)");
        assert.equal(decode_error_str("\n\n."), "Invalid statement (at line 3, column 1)")
    }

    test "test_missing_value" {
        assert.equal(decode_error_str("\n\nfwfw="), "Invalid value (at end of document)")
    }

    test "test_invalid_char_quotes" {
        assert.is_true(decode_error_str("v = '\n'").includes(" '\\n' "))
    }

    // test_type_error: NOT PORTABLE. The original passes `bytes` and `bool` to
    // `loads` and expects a run-time `TypeError`. In BAML `loads(s: string)`
    // is statically typed, so `root.tomli.loads(false)` is a compile error
    // (E0001-class type mismatch), not a run-time error that a test can
    // observe.

    test "test_invalid_parse_float" {
        assert.equal(
            invalid_parse_float_messages(),
            [
                "parse_float must not return dicts or lists",
                "parse_float must not return dicts or lists",
            ],
        )
    }

    test "test_deprecated_tomldecodeerror" {
        assert.equal(deprecated_tomldecodeerror_mismatches(), [])
    }

    test "test_tomldecodeerror" {
        assert.is_true(check_tomldecodeerror())
    }
}

function invalid_parse_float_messages() -> string[] {
    let dict_returner = (s: string) -> root.tomli.Value {
        let d: map<string, root.tomli.Value> = {};
        d
    };
    let list_returner = (s: string) -> root.tomli.Value {
        let l: root.tomli.Value[] = [];
        l
    };

    let messages: string[] = [];
    for (let invalid_parse_float in [dict_returner, list_returner]) {
        // with self.assertRaises(ValueError) as exc_info:
        let msg = {
            let _ = root.tomli.loads("f=0.1", parse_float = invalid_parse_float);
            "ValueError not raised"
        } catch (e) {
            root.tomli.ValueError => e.message,
        };
        messages.push(msg);
    }
    messages
}

/// Returns a description of every argument list for which `e.args != args`.
///
/// `self.assertWarns(DeprecationWarning)` is not portable: BAML has no
/// warnings machinery, so the port logs the warning (`log.warn`) where a test
/// cannot observe it.
function deprecated_tomldecodeerror_mismatches() -> string[] {
    let cases: unknown[][] = [
        [],
        ["err msg"],
        [null],
        [null, "doc"],
        ["err msg", null],
        [null, "doc", null],
        ["err msg", "doc", null],
        ["one", "two", "three", "four"],
        ["one", "two", 3, "four", "five"],
    ];
    let mismatches: string[] = [];
    for (let args in cases) {
        let e = root.tomli.TOMLDecodeError.from_args(args);
        if (e.args != args) {
            mismatches.push(root.tomli.py_exception_str(args));
        }
    }
    mismatches
}

function check_tomldecodeerror() -> bool {
    let msg = "error parsing";
    let doc = "v=1\n[table]\nv='val'";
    let pos = 13;
    let formatted_msg = "error parsing (at line 3, column 2)";
    let e = root.tomli.TOMLDecodeError.new(msg, doc, pos);
    assert.equal(e.args, [formatted_msg]);
    assert.equal(e.to_string(), formatted_msg);
    assert.equal(e.msg, msg);
    assert.equal(e.doc, doc);
    assert.equal(e.pos, pos);
    assert.equal(e.lineno, 3);
    assert.equal(e.colno, 2);
    true
}
