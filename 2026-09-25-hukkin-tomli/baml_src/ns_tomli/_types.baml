// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2021 Taneli Hukkinen
// Licensed to PSF under a Contributor Agreement.
//
// BAML port of `tomli/_types.py`.
//
// Python's `_types` holds nothing but type annotations (`Any`, `Callable`,
// `Tuple`). BAML has no `Any` that survives a round trip through typed
// containers (arrays/maps are invariant and carry their element type at
// run time), so the port additionally spells out `Value` -- the closed set of
// things `loads` can return -- which Python leaves as `dict[str, Any]`.

/// Escape hatch for `parse_float` implementations that return something other
/// than a builtin (Python lets `parse_float` return *any* object, e.g.
/// `decimal.Decimal`). Implement this interface on your own class to return it
/// from `parse_float`.
interface CustomFloat {
    /// Human readable rendering (plays the role of Python's `repr`).
    function repr(self) -> string throws never;
}

/// A parsed TOML value (Python: `Any`).
///
/// * integers are `bigint`: Python's `int` is arbitrary precision and BAML's
///   `int` only holds 63 bits, which cannot represent TOML's int64 range.
/// * `baml.time.ZonedDateTime` is an offset date-time (tz-aware `datetime`),
///   `baml.time.PlainDateTime` a local date-time (naive `datetime`),
///   `baml.time.PlainDate` a local date, `baml.time.PlainTime` a local time.
type Value = string
    | bool
    | bigint
    | float
    | baml.time.ZonedDateTime
    | baml.time.PlainDateTime
    | baml.time.PlainDate
    | baml.time.PlainTime
    | CustomFloat
    | Value[]
    | map<string, Value>;

/// Python: `ParseFloat = Callable[[str], Any]`
type ParseFloat = (string) -> Value throws unknown;

/// Python: `Key = Tuple[str, ...]` (BAML has no tuples; an array is used and
/// treated as immutable by convention).
type Key = string[];

/// Python: `Pos = int`
type Pos = int;
