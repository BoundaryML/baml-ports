// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2021 Taneli Hukkinen
// Licensed to PSF under a Contributor Agreement.
//
// BAML port of `tests/test_misc.py`.

testset "TestMiscellaneous" {
    test "test_load" {
        assert.is_true(check_load())
    }

    // test_incorrect_load: NOT PORTABLE. The original opens the file in text
    // mode (`open(file_path, "r")`) and expects `load` to raise `TypeError`.
    // `baml.fs.File` has no text mode (its `"r"` mode is what Python calls
    // `"rb"`), and `load(fp: baml.fs.File)` rejects anything else statically.

    test "test_parse_float" {
        assert.is_true(check_parse_float())
    }

    test "test_deepcopy" {
        assert.is_true(check_deepcopy())
    }

    test "test_inline_array_recursion_limit" {
        assert.is_true(check_inline_array_recursion_limit())
    }

    test "test_inline_table_recursion_limit" {
        assert.is_true(check_inline_table_recursion_limit())
    }

    test "test_key_recursion_limit" {
        assert.is_true(check_key_recursion_limit())
    }

    // Test that `_types` module runs.
    //
    // The module is for type annotations only, so it is otherwise never
    // imported by tests. BAML port: there is no run-time module import; the
    // closest analogue is that the `_types.baml` aliases resolve.
    test "test_types_import" {
        assert.is_true(check_types_import())
    }

    // test_lazy_import: NOT PORTABLE (and skipped by the original on Python
    // < 3.15). It checks that `tomli._re` is not imported when no regex is
    // needed; BAML namespaces are compiled together and have no run-time
    // import step at all.
}

// Port addition: pins the exact nesting boundary. The BAML VM's call stack is
// only 256 frames deep, so the port parses deep nesting across several tasks
// (see `_nested` in `_parser.baml`); this checks that exactly
// `MAX_INLINE_NESTING()` levels still parse and one more is rejected.
testset "PortAdditions" {
    test "inline_nesting_at_the_limit_parses" {
        assert.is_true(inline_nesting_at_limit_parses())
    }
}

function check_load() -> bool {
    let content = "one=1 \n two='two' \n arr=[]";
    let expected_arr: root.tomli.Value[] = [];
    let expected: map<string, root.tomli.Value> = { "one": 1n, "two": "two", "arr": expected_arr };
    // Python: `tempfile.TemporaryDirectory()`; BAML has no tempfile module.
    let tmp_dir_path = (baml.env.get("TMPDIR") ?? "/tmp") + "/tomli-baml-test-" + baml.sys.pid().to_string();
    baml.fs.mkdir(tmp_dir_path, baml.fs.MkdirOptions { recursive: true });
    defer { baml.fs.remove_dir_all(tmp_dir_path); }
    let file_path = tmp_dir_path + "/test.toml";
    baml.fs.write(file_path, content);

    // Python: `open(file_path, "rb")`
    let bin_f = baml.fs.open(file_path, "r");
    defer { bin_f.close(); }
    let actual = root.tomli.load(bin_f);
    assert.equal(actual, expected);
    true
}

/// A minimal stand-in for `decimal.Decimal`, just enough for
/// `test_parse_float`: construction from a string, `is_nan()` and equality.
class D {
    /// Canonical text: no leading `+`, lower case.
    text: string,

    function new(s: string) -> D {
        let t = s.to_lower_case();
        if (t.starts_with("+")) {
            t = t.slice(1, t.length());
        }
        D { text: t }
    }

    function is_nan(self) -> bool {
        self.text.includes("nan")
    }

    implements root.tomli.CustomFloat {
        function repr(self) -> string throws never {
            "Decimal('" + self.text + "')"
        }
    }
}

function check_parse_float() -> bool {
    let doc = `
        val=0.1
        biggest1=inf
        biggest2=+inf
        smallest=-inf
        notnum1=nan
        notnum2=-nan
        notnum3=+nan
    `;
    let obj = root.tomli.loads(doc, parse_float = (s: string) -> root.tomli.Value {
        D.new(s)
    });
    let expected: map<string, D> = {
        "val": D.new("0.1"),
        "biggest1": D.new("inf"),
        "biggest2": D.new("inf"),
        "smallest": D.new("-inf"),
        "notnum1": D.new("nan"),
        "notnum2": D.new("-nan"),
        "notnum3": D.new("nan"),
    };
    for (let k in expected.keys()) {
        let expected_val = expected[k];
        let actual_val = obj[k];
        // self.assertIsInstance(actual_val, D)
        let actual_d = match (actual_val) {
            let d: D => d,
            _ => baml.sys.panic(k + ": not a D instance"),
        };
        if (actual_d.is_nan()) {
            assert.is_true(expected_val.is_nan());
        } else {
            assert.equal(actual_d, expected_val);
        }
    }
    true
}

function check_deepcopy() -> bool {
    let doc = `
        [bliibaa.diibaa]
        offsettime=[1979-05-27T00:32:00.999999-07:00]
    `;
    let obj = root.tomli.loads(doc);
    let obj_copy = baml.deep_copy(obj);
    assert.equal(obj_copy, obj);
    let tz = baml.time.TimeZoneOffset.new(-7, 0);
    let offsettime: root.tomli.Value[] = [
        baml.time.ZonedDateTime.from_components(
            tz,
            1979,
            5,
            27,
            hour = 0,
            minute = 32,
            second = 0,
            millisecond = 999,
            microsecond = 999,
        ),
    ];
    let diibaa: map<string, root.tomli.Value> = { "offsettime": offsettime };
    let bliibaa: map<string, root.tomli.Value> = { "diibaa": diibaa };
    let expected_obj: map<string, root.tomli.Value> = { "bliibaa": bliibaa };
    assert.equal(obj_copy, expected_obj);
    true
}

/// `self.assertRaisesRegex(RecursionError, pattern)` around `loads(doc)`.
function raises_recursion_error(doc: string, pattern: string) -> bool {
    let msg = {
        let _ = root.tomli.loads(doc);
        null
    } catch (e) {
        root.tomli.RecursionError => e.message,
    };
    if (msg == null) {
        return false;
    }
    let re = baml.regex.new(pattern) catch (e) {
        baml.regex.Error => baml.sys.panic(e.message)
    };
    re.has_match(msg)
}

function _nesting_pattern() -> string {
    "maximum recursion depth exceeded"
        + "|"
        + "TOML inline arrays/tables are nested more than the allowed [0-9]+ levels"
}

function check_inline_array_recursion_limit() -> bool {
    let nest_count = 470;
    let recursive_array_toml = "arr = " + "[".repeat(nest_count) + "]".repeat(nest_count);
    root.tomli.loads(recursive_array_toml);

    nest_count = root.tomli.getrecursionlimit() + 2;
    recursive_array_toml = "arr = " + "[".repeat(nest_count) + "]".repeat(nest_count);
    raises_recursion_error(recursive_array_toml, _nesting_pattern())
}

function check_inline_table_recursion_limit() -> bool {
    let nest_count = 310;
    let recursive_table_toml = "key = {".repeat(nest_count) + "}".repeat(nest_count);
    root.tomli.loads(recursive_table_toml);

    nest_count = root.tomli.getrecursionlimit() + 2;
    recursive_table_toml = "key = {".repeat(nest_count) + "}".repeat(nest_count);
    raises_recursion_error(recursive_table_toml, _nesting_pattern())
}

/// Port addition: the deepest nesting the BAML port supports still parses.
function inline_nesting_at_limit_parses() -> bool {
    let n = root.tomli.MAX_INLINE_NESTING();
    root.tomli.loads("arr = " + "[".repeat(n) + "]".repeat(n));
    root.tomli.loads("key = {".repeat(n) + "}".repeat(n));
    // `parse_value` checks the level of the value it is *about to parse*, and
    // the innermost `[]` is never entered, so `n + 1` brackets still parse.
    root.tomli.loads("arr = " + "[".repeat(n + 1) + "]".repeat(n + 1));
    let too_deep = n + 2;
    raises_recursion_error("arr = " + "[".repeat(too_deep) + "]".repeat(too_deep), _nesting_pattern())
}

function check_key_recursion_limit() -> bool {
    let nest_count = 310;
    let nested_key_toml = "a.".repeat(nest_count) + "a = 1";
    root.tomli.loads(nested_key_toml);

    nest_count = root.tomli.getrecursionlimit() - 2;
    nested_key_toml = "a.".repeat(nest_count) + "a = 1";
    root.tomli.loads(nested_key_toml);

    nest_count = root.tomli.getrecursionlimit() + 2;
    nested_key_toml = "a.".repeat(nest_count) + "a = 1";
    raises_recursion_error(nested_key_toml, "TOML key has more than the allowed [0-9]+ parts")
}

function check_types_import() -> bool {
    let key: root.tomli.Key = ["a", "b"];
    let pos: root.tomli.Pos = 0;
    let pf: root.tomli.ParseFloat = (s: string) -> root.tomli.Value {
        s
    };
    key.length() == 2 && pos == 0 && pf("x") == "x"
}
