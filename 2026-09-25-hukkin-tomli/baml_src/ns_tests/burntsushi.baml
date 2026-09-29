// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2021 Taneli Hukkinen
// Licensed to PSF under a Contributor Agreement.
//
// BAML port of `tests/burntsushi.py`.
//
// Utilities for tests that are in the "burntsushi" format.
//
// Python's `Any`-typed JSON objects become `baml.json.json`.

/// Python's generic `Exception("...")`.
class Exception {
    message: string,
}

/// Python's `AssertionError`.
class AssertionError {
    message: string,
}

function convert(obj: root.tomli.Value) -> baml.json.json throws Exception {
    match (obj) {
        let s: string => _tagged("string", s),
        // Python: `str(obj).lower()`
        let b: bool => {
            _tagged(
                "bool",
                if (b) {
                    "true"
                } else {
                    "false"
                },
            )
        },
        let i: bigint => _tagged("integer", i.to_string()),
        let f: float => _tagged("float", _normalize_float_str(py_float_str(f))),
        let dt: baml.time.ZonedDateTime => {
            _tagged("datetime", _normalize_datetime_str(isoformat_zoned(dt)))
        },
        let dt: baml.time.PlainDateTime => {
            _tagged("datetime-local", _normalize_datetime_str(isoformat_plain(dt)))
        },
        let t: baml.time.PlainTime => _tagged("time-local", _normalize_localtime_str(str_time(t))),
        let d: baml.time.PlainDate => _tagged("date-local", str_date(d)),
        let l: root.tomli.Value[] => {
            let out: baml.json.json[] = [];
            for (let i in l) {
                out.push(convert(i));
            }
            out
        },
        let m: map<string, root.tomli.Value> => {
            let out: map<string, baml.json.json> = {};
            for (let k in m.keys()) {
                out.set(k, convert(m[k]));
            }
            out
        },
        _ => {
            throw Exception { message: "unsupported type" }
        },
    }
}

function _tagged(type_: string, value: string) -> baml.json.json {
    let m: map<string, baml.json.json> = { "type": type_, "value": value };
    m
}

/// Normalize test objects.
///
/// This normalizes primitive values (e.g. floats).
function normalize(obj: baml.json.json) -> baml.json.json throws AssertionError {
    match (obj) {
        let l: baml.json.json[] => {
            let out: baml.json.json[] = [];
            for (let item in l) {
                out.push(normalize(item));
            }
            out
        },
        let d: map<string, baml.json.json> => {
            if (d.has("type") && d.has("value")) {
                let type_ = d["type"];
                let value = d["value"];
                let norm_value: baml.json.json = value;
                if (type_ == "float") {
                    norm_value = _normalize_float_str(_as_str(value));
                } else if (type_ == "datetime" || type_ == "datetime-local") {
                    norm_value = _normalize_datetime_str(_as_str(value));
                } else if (type_ == "time-local") {
                    norm_value = _normalize_localtime_str(_as_str(value));
                } else {
                    norm_value = value;
                }

                if (type_ == "array") {
                    let out: baml.json.json[] = [];
                    let items = match (value) {
                        let a: baml.json.json[] => a,
                        _ => {
                            throw AssertionError { message: "array value must be a list" }
                        },
                    };
                    for (let item in items) {
                        out.push(normalize(item));
                    }
                    return out;
                }
                let tagged: map<string, baml.json.json> = { "type": type_, "value": norm_value };
                return tagged;
            }
            let out: map<string, baml.json.json> = {};
            for (let k in d.keys()) {
                out.set(k, normalize(d[k]));
            }
            out
        },
        _ => {
            throw AssertionError { message: "Burntsushi fixtures should be dicts/lists only" }
        },
    }
}

/// Python would raise a `TypeError`/`AttributeError` on a non-str here.
function _as_str(v: baml.json.json) -> string throws AssertionError {
    match (v) {
        let s: string => s,
        _ => {
            throw AssertionError { message: "expected a string value" }
        },
    }
}

function _normalize_datetime_str(dt_str_in: string) -> string {
    let dt_str = dt_str_in;
    if ((dt_str.at(-1) ?? "").to_lower_case() == "z") {
        dt_str = dt_str.slice(0, dt_str.length() - 1) + "+00:00";
    }

    let date = dt_str.slice(0, 10);
    let rest = dt_str.slice(11, dt_str.length());

    let sign = if (rest.includes("+")) {
        "+"
    } else if (rest.includes("-")) {
        "-"
    } else {
        ""
    };

    let time = rest;
    let offset = "";
    if (sign != "") {
        // Python: `time, _, offset = rest.partition(sign)`
        let idx = rest.index_of(sign) ?? rest.length();
        time = rest.slice(0, idx);
        offset = rest.slice(idx + 1, rest.length());
    }

    time
        = if (time.includes(".")) {
            _rstrip(time, "0")
        } else {
            time
        };
    date + "T" + time + sign + offset
}

function _normalize_localtime_str(lt_str: string) -> string {
    if (lt_str.includes(".")) {
        _rstrip(lt_str, "0")
    } else {
        lt_str
    }
}

function _normalize_float_str(float_str: string) -> string {
    let as_float = root.tomli.py_float(float_str) catch (e) {
        root.tomli.ValueError => baml.sys.panic(e.message)
    };

    // Normalize "-0.0" and "+0.0"
    if (as_float == 0.0) {
        return "0";
    }

    py_float_str(as_float)
}

// ---------------------------------------------------------------------------
// Python runtime behaviour the original gets for free.
// ---------------------------------------------------------------------------

/// Python's `str.rstrip(chars)` for a single character.
function _rstrip(s: string, ch: string) -> string {
    let out = s;
    while (out.ends_with(ch)) {
        out = out.slice(0, out.length() - 1);
    }
    out
}

/// Python's `str(float)`.
///
/// BAML's `float.to_string()` does not follow Python's `repr` algorithm
/// (e.g. `1e16` renders as `10000000000000000.0`, `inf` as `Infinity`).
/// Every float that is compared in these tests passes through this function
/// on *both* sides, so an injective rendering is all that is required; the
/// special values are mapped to Python's spelling for readability.
function py_float_str(f: float) -> string {
    if (f.is_nan()) {
        return "nan";
    }
    if (f.is_infinite()) {
        return if (f > 0.0) {
            "inf"
        } else {
            "-inf"
        };
    }
    f.to_string()
}

function _pad(n: int, width: int) -> string {
    let s = n.to_string();
    while (s.length() < width) {
        s = "0" + s;
    }
    s
}

/// Python's `str(datetime.date)`.
function str_date(d: baml.time.PlainDate) -> string {
    // `PlainDate.year()` etc. declare `throws InvalidArgument`, although a
    // constructed date is always valid.
    let y = d.year() catch (e) {
        _ => 0
    };
    let m = d.month() catch (e) {
        _ => 0
    };
    let dd = d.day() catch (e) {
        _ => 0
    };
    _pad(y, 4) + "-" + _pad(m, 2) + "-" + _pad(dd, 2)
}

/// Python's `str(datetime.time)` (== `time.isoformat()`).
function str_time(t: baml.time.PlainTime) -> string {
    // There is no `microsecond()` accessor; derive it from the (private)
    // nanosecond field.
    let micros = t._nanoseconds % 1000000000 / 1000;
    _hms(t.hour(), t.minute(), t.second(), micros)
}

function _hms(h: int, m: int, s: int, micros: int) -> string {
    let out = _pad(h, 2) + ":" + _pad(m, 2) + ":" + _pad(s, 2);
    if (micros != 0) {
        out = out + "." + _pad(micros, 6);
    }
    out
}

/// Python's `datetime.isoformat()` for a naive datetime.
function isoformat_plain(dt: baml.time.PlainDateTime) -> string {
    let d = dt.to_plain_date() catch (e) {
        _ => baml.sys.panic("invalid date")
    };
    str_date(d) + "T" + str_time(dt.to_plain_time())
}

/// Python's `datetime.isoformat()` for a tz-aware datetime.
function isoformat_zoned(dt: baml.time.ZonedDateTime) -> string {
    let plain = dt.to_plain() catch (e) {
        _ => baml.sys.panic("unknown timezone")
    };
    let off = dt.timezone_offset() catch (e) {
        _ => baml.sys.panic("unknown timezone")
    };
    let total_minutes = off.hours() * 60 + off.minutes();
    let sign = if (total_minutes < 0) {
        "-"
    } else {
        "+"
    };
    let abs_minutes = total_minutes.abs();
    isoformat_plain(plain) + sign + _pad(abs_minutes / 60, 2) + ":" + _pad(abs_minutes % 60, 2)
}
