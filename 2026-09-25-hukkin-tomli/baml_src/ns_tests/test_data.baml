// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2021 Taneli Hukkinen
// Licensed to PSF under a Contributor Agreement.
//
// BAML port of `tests/test_data.py`.
//
// Differences from the original:
// * `Path(__file__).parent / "data"`: BAML has no `__file__`, so the data
//   directory is resolved relative to the working directory (run `baml test`
//   from the project root), overridable with `TOMLI_TEST_DATA`.
// * `unittest`'s `subTest` has no BAML equivalent (and `test` blocks cannot
//   be generated dynamically). The loops below collect per-file failures,
//   print a pass count, and fail once at the end, listing the failures.
//   Caveat: a VM *panic* (as opposed to a thrown error) cannot be caught, so
//   a single panicking file would abort the whole loop.
// * Module-level `VALID_FILES` / `VALID_FILES_EXPECTED` / `INVALID_FILES`
//   tuples become functions (no module-level state).

function DATA_DIR() -> string {
    baml.env.get("TOMLI_TEST_DATA") ?? "tests/data"
}

function _glob_toml(dir: string) -> string[] {
    let files = baml.glob.new("**/*.toml").scan(dir);
    files.map((f) -> {
        dir + "/" + f
    })
}

function VALID_FILES() -> string[] {
    let files = _glob_toml(DATA_DIR() + "/valid");
    // Python: `assert VALID_FILES, "..."` (`assert.is_true` takes no message).
    if (files.length() == 0) {
        baml.sys.panic("Valid TOML test files not found");
    }
    files
}

function INVALID_FILES() -> string[] {
    let files = _glob_toml(DATA_DIR() + "/invalid");
    // Python: `assert VALID_FILES, "..."` (`assert.is_true` takes no message).
    if (files.length() == 0) {
        baml.sys.panic("Invalid TOML test files not found");
    }
    files
}

/// Python: `p.with_suffix(".json")`
function _with_json_suffix(p: string) -> string {
    p.slice(0, p.length() - ".toml".length()) + ".json"
}

/// Python: `path.read_bytes().decode()`; `null` stands for `UnicodeDecodeError`.
function _read_text(path: string) -> string? {
    let f = baml.fs.open(path, "r");
    let b = f.bytes();
    f.close();
    baml.String.from_utf8(b) catch (e) {
        baml.errors.InvalidArgument => null,
    }
}

/// Python: `path.stem`
function _stem(path: string) -> string {
    let name = path.slice((path.last_index_of("/") ?? -1) + 1, path.length());
    name.slice(0, name.last_index_of(".") ?? name.length())
}

/// One `subTest` of `test_invalid`. Returns a failure description, or `null`
/// on success (or skip).
function check_invalid(path: string) -> string? {
    let toml_str = _read_text(path);
    if (toml_str == null) {
        // Some BurntSushi tests are not valid UTF-8. Skip those.
        return null;
    }
    // Python: `with self.assertRaises(tomllib.TOMLDecodeError): tomllib.loads(toml_str)`
    let outcome = {
        let _ = root.tomli.loads(toml_str);
        "no exception raised"
    } catch (e) {
        root.tomli.TOMLDecodeError => "ok",
        _ => "unexpected exception raised",
    };
    if (outcome == "ok") {
        null
    } else {
        _stem(path) + ": " + outcome
    }
}

/// One `subTest` of `test_valid`. Returns a failure description, or `null`.
function check_valid(path: string) -> string? {
    let toml_str = _read_text(path) ?? "";
    let expected_text = _read_text(_with_json_suffix(path)) ?? "";
    let expected_raw = baml.json.parse(expected_text);

    let parsed = root.tomli.loads(toml_str) catch (e) {
        root.tomli.TOMLDecodeError => {
            return _stem(path) + ": TOMLDecodeError: " + e.to_string();
        },
        _ => {
            return _stem(path) + ": unexpected exception";
        },
    };
    let actual = convert(parsed);
    let expected = normalize(expected_raw);
    if (actual == expected) {
        return null;
    }
    _stem(path) + ": " + baml.json.stringify(actual) + " != " + baml.json.stringify(expected)
}

function _report(kind: string, total: int, failures: string[]) -> null {
    baml.io.println(
        kind + ": " + (total - failures.length()).to_string() + "/" + total.to_string() + " passed",
    );
    for (let f in failures) {
        baml.io.println("  FAIL " + f);
    }
    null
}

function run_test_invalid() -> string[] {
    let failures: string[] = [];
    let files = INVALID_FILES();
    for (let invalid in files) {
        let failure = check_invalid(invalid);
        if (failure != null) {
            failures.push(failure);
        }
    }
    _report("test_invalid", files.length(), failures);
    failures
}

function run_test_valid() -> string[] {
    let failures: string[] = [];
    let files = VALID_FILES();
    for (let valid in files) {
        let failure = check_valid(valid);
        if (failure != null) {
            failures.push(failure);
        }
    }
    _report("test_valid", files.length(), failures);
    failures
}

testset "TestData" {
    test "test_invalid" {
        assert.equal(run_test_invalid(), [])
    }

    test "test_valid" {
        assert.equal(run_test_valid(), [])
    }
}
