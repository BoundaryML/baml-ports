// Port of clap_builder/src/builder/value_parser.rs

/// `std::path::PathBuf`
///
/// BAML has no distinct path type; paths are strings. `ValueParser.path_buf()`
/// still rejects empty values and marks the argument with `ValueHint::AnyPath`.
type PathBuf = string

/// `std::ffi::OsString`
type OsString = string

enum ValueParserKind {
    // Common enough to optimize and for possible values
    Bool,
    // Common enough to optimize
    String,
    // Common enough to optimize
    OsString,
    // Common enough to optimize
    PathBuf,
    Other,
}

/// Parse/validate argument values
///
/// Specified with [`Arg::value_parser`][crate::Arg::value_parser].
///
/// `ValueParser` defines how to convert a raw argument value into a validated and typed value for
/// use within an application.
///
/// See
/// - [`value_parser!`][crate::value_parser] for automatically selecting an implementation for a given type
/// - [`ValueParser::new`] for additional [`TypedValueParser`] that can be used
///
/// # Example
///
/// ```baml
/// let mut cmd = Command.new("raw")
///     .arg(
///         Arg.new("color")
///             .long("color")
///             .value_parser(["always", "auto", "never"])
///             .default_value("auto")
///     )
///     .arg(
///         Arg.new("hostname")
///             .long("hostname")
///             .value_parser(ValueParser.new(NonEmptyStringValueParser.new()))
///             .action(ArgAction.Set)
///             .required(true)
///     )
///     .arg(
///         Arg.new("port")
///             .long("port")
///             .value_parser(value_parser_u16().range(3000, null))
///             .action(ArgAction.Set)
///             .required(true)
///     );
///
/// let m = cmd.try_get_matches_from_mut(
///     ["cmd", "--hostname", "rust-lang.org", "--port", "3001"]
/// );
/// let port = m.get_one<int>("port");
/// ```
class ValueParser {
    _kind: ValueParserKind,
    _other: TypedValueParser?,

    /// Custom parser for argument values
    ///
    /// Pre-existing [`TypedValueParser`] implementations include:
    /// - `Fn(&str) -> Result<T, E>` (see `FnValueParser`)
    /// - [`EnumValueParser`] and  [`PossibleValuesParser`] for static enumerated values
    /// - [`BoolishValueParser`] and [`FalseyValueParser`] for alternative `bool` implementations
    /// - [`RangedI64ValueParser`] and [`RangedU64ValueParser`]
    /// - [`NonEmptyStringValueParser`]
    function new(other: TypedValueParser) -> ValueParser {
        ValueParser { _kind: ValueParserKind.Other, _other: other }
    }

    /// [`bool`] parser for argument values
    ///
    /// See also:
    /// - [`BoolishValueParser`] for different human readable bool representations
    /// - [`FalseyValueParser`] for assuming non-false is true
    function bool() -> ValueParser { ValueParser { _kind: ValueParserKind.Bool, _other: null } }

    /// [`String`] parser for argument values
    ///
    /// See also:
    /// - [`NonEmptyStringValueParser`]
    function string() -> ValueParser { ValueParser { _kind: ValueParserKind.String, _other: null } }

    /// [`OsString`][std::ffi::OsString] parser for argument values
    function os_string() -> ValueParser { ValueParser { _kind: ValueParserKind.OsString, _other: null } }

    /// [`PathBuf`][std::path::PathBuf] parser for argument values
    function path_buf() -> ValueParser { ValueParser { _kind: ValueParserKind.PathBuf, _other: null } }

    /// Parse into a `AnyValue`
    ///
    /// When `arg` is `None`, an external subcommand value is being parsed.
    function parse_ref(self, cmd: Command, arg: Arg?, value: string, source: ValueSource) -> AnyValue throws Error {
        let p = self.any_value_parser();
        let v = p.parse_ref_(cmd, arg, value, source);
        AnyValue.with_id(v, p.type_id())
    }

    /// Describes the content of `AnyValue`
    function type_id(self) -> AnyValueId { self.any_value_parser().type_id() }

    /// Reflect on enumerated value properties
    ///
    /// Error checking should not be done with this; it is mostly targeted at user-facing
    /// applications like errors and completion.
    function possible_values(self) -> PossibleValue[]? { self.any_value_parser().possible_values() }

    function is_path(self) -> bool { self._kind == ValueParserKind.PathBuf }

    function any_value_parser(self) -> TypedValueParser {
        match (self._kind) {
            ValueParserKind.Bool => BoolValueParser.new(),
            ValueParserKind.String => StringValueParser.new(),
            ValueParserKind.OsString => OsStringValueParser.new(),
            ValueParserKind.PathBuf => PathBufValueParser.new(),
            ValueParserKind.Other => self._other ?? StringValueParser.new(),
        }
    }

    /// `impl Debug for ValueParser`
    function debug(self) -> string {
        match (self._kind) {
            ValueParserKind.Bool => "ValueParser::bool",
            ValueParserKind.String => "ValueParser::string",
            ValueParserKind.OsString => "ValueParser::os_string",
            ValueParserKind.PathBuf => "ValueParser::path_buf",
            ValueParserKind.Other => `ValueParser::other(${self.type_id().debug()})`,
        }
    }
}

/// `impl From<P: TypedValueParser> for ValueParser`, `From<[P; C]>`, `From<Vec<P>>`
/// (possible values), and `From<RangeBounds<i64>>` (via `RangedI64ValueParser`).
function into_value_parser(p: ValueParser | TypedValueParser | string[] | PossibleValue[]) -> ValueParser {
    match (p) {
        let v: ValueParser => v,
        let s: string[] => ValueParser.new(PossibleValuesParser.new(s)),
        let pv: PossibleValue[] => ValueParser.new(PossibleValuesParser.new(pv)),
        let t: TypedValueParser => ValueParser.new(t),
    }
}

/// Parse/validate argument values
///
/// As alternatives to implementing `TypedValueParser`,
/// - Use `Fn(&str) -> Result<T, E>` which implements `TypedValueParser`
/// - [`TypedValueParser::map`] or [`TypedValueParser::try_map`] to adapt an existing `TypedValueParser`
///
/// See `ValueParserFactory` to register `TypedValueParser::Value` with
/// [`value_parser!`][crate::value_parser].
///
/// Rust's `type Value` associated type is erased to `unknown` here; the
/// produced type is reported through `type_id`.
interface TypedValueParser {
    /// Parse the argument value
    ///
    /// When `arg` is `None`, an external subcommand value is being parsed.
    function parse_ref(self, cmd: Command, arg: Arg?, value: string) -> unknown throws Error

    /// Parse the argument value
    ///
    /// When `arg` is `None`, an external subcommand value is being parsed.
    function parse_ref_(self, cmd: Command, arg: Arg?, value: string, source: ValueSource) -> unknown throws Error {
        self.parse_ref(cmd, arg, value)
    }

    /// Describes the content of the parsed value (`AnyValueId::of::<Self::Value>()`)
    function type_id(self) -> AnyValueId throws never

    /// Reflect on enumerated value properties
    ///
    /// Error checking should not be done with this; it is mostly targeted at user-facing
    /// applications like errors and completion.
    function possible_values(self) -> PossibleValue[]? throws never {
        null
    }
}

/// `impl<F, T, E> TypedValueParser for F where F: Fn(&str) -> Result<T, E>`
///
/// # Example
///
/// ```baml
/// let parser = FnValueParser.new<int>((s) -> { parse_i64(s) });
/// ```
class FnValueParser {
    _func: (string) -> unknown throws unknown,
    _type_id: AnyValueId,

    function new<T>(func: (string) -> T throws unknown) -> FnValueParser {
        FnValueParser { _func: func, _type_id: AnyValueId.of<T>() }
    }

    implements TypedValueParser {
        function parse_ref(self, cmd: Command, arg: Arg?, value: string) -> unknown throws Error {
            let f = self._func;
            f(value) catch_all (e) {
                _ => {
                    let a = if let x: Arg = arg { x.to_string() } else { "..." };
                    throw error_value_validation(a, value, error_to_string(e)).with_cmd(cmd)
                },
            }
        }
        function type_id(self) -> AnyValueId throws never { self._type_id }
    }
}

/// Implementation for [`ValueParser::string`]
///
/// Useful for composing new [`TypedValueParser`]s
class StringValueParser {
    function new() -> StringValueParser { StringValueParser {} }

    implements TypedValueParser {
        function parse_ref(self, cmd: Command, arg: Arg?, value: string) -> unknown throws Error {
            value
        }
        function type_id(self) -> AnyValueId throws never { AnyValueId.of<string>() }
    }
}

/// Implementation for [`ValueParser::os_string`]
///
/// Useful for composing new [`TypedValueParser`]s
class OsStringValueParser {
    function new() -> OsStringValueParser { OsStringValueParser {} }

    implements TypedValueParser {
        function parse_ref(self, cmd: Command, arg: Arg?, value: string) -> unknown throws Error {
            value
        }
        function type_id(self) -> AnyValueId throws never { AnyValueId.of<OsString>() }
    }
}

/// Implementation for [`ValueParser::path_buf`]
///
/// Useful for composing new [`TypedValueParser`]s
class PathBufValueParser {
    function new() -> PathBufValueParser { PathBufValueParser {} }

    implements TypedValueParser {
        function parse_ref(self, cmd: Command, arg: Arg?, value: string) -> unknown throws Error {
            if (value.is_empty()) {
                let a = if let x: Arg = arg { x.to_string() } else { "..." };
                throw error_empty_value(cmd, [], a);
            }
            value
        }
        function type_id(self) -> AnyValueId throws never { AnyValueId.of<PathBuf>() }
    }
}

/// Parse an [`ValueEnum`][crate::ValueEnum] value.
///
/// See also:
/// - [`PossibleValuesParser`]
///
/// Rust is generic over `E: ValueEnum`; the BAML port reflects over the
/// variants of a BAML `enum` (see `derive.baml`'s `ValueEnum` support) and
/// produces the enum value itself.
class EnumValueParser {
    _variants: EnumVariant[],
    _type_id: AnyValueId,

    /// Parse an [`ValueEnum`][crate::ValueEnum] (a BAML `enum`, by reflection)
    function new<E>() -> EnumValueParser {
        EnumValueParser { _variants: enum_variants<E>(), _type_id: AnyValueId.of<E>() }
    }

    /// Parse a hand-written [`ValueEnum`][crate::ValueEnum] implementation
    function from_value_enum<E extends ValueEnum>() -> EnumValueParser {
        let variants = (E as ValueEnum).value_variants().filter_map((v) -> {
            if let pv: PossibleValue = v.to_possible_value() {
                EnumVariant { value: v, possible_value: pv }
            } else {
                null
            }
        });
        EnumValueParser { _variants: variants, _type_id: AnyValueId.of<E>() }
    }

    function possible_vals(self) -> string[] {
        self._variants.filter((v) -> { !v.possible_value.is_hide_set() }).map((v) -> { v.possible_value.get_name() })
    }

    implements TypedValueParser {
        function parse_ref(self, cmd: Command, arg: Arg?, value: string) -> unknown throws Error {
            let ignore_case = if let a: Arg = arg { a.is_ignore_case_set() } else { false };
            let found = self._variants.find((v) -> { v.possible_value.matches(value, ignore_case) });
            if let v: EnumVariant = found {
                v.value
            } else {
                let a = if let x: Arg = arg { x.to_string() } else { "..." };
                throw error_invalid_value(cmd, value, self.possible_vals(), a)
            }
        }
        function type_id(self) -> AnyValueId throws never { self._type_id }
        function possible_values(self) -> PossibleValue[]? throws never {
            self._variants.map((v) -> { v.possible_value })
        }
    }
}

/// One variant of a `ValueEnum`: its value and how it is spelled on the command line
class EnumVariant {
    value: unknown,
    possible_value: PossibleValue,
}

/// Verify the value is from an enumerated set of [`PossibleValue`][crate::builder::PossibleValue].
///
/// See also:
/// - [`EnumValueParser`] for directly supporting [`ValueEnum`][crate::ValueEnum] types
/// - [`TypedValueParser::map`] for adapting values to a more specialized type, like an external
///   enums that can't implement [`ValueEnum`][crate::ValueEnum]
class PossibleValuesParser {
    _0: PossibleValue[],

    /// Verify the value is from an enumerated set of [`PossibleValue`][crate::builder::PossibleValue].
    function new(values: string[] | PossibleValue[]) -> PossibleValuesParser {
        let pvs: PossibleValue[] = match (values) {
            let s: string[] => s.map((v) -> { PossibleValue.new(v) }),
            let p: PossibleValue[] => p,
        };
        PossibleValuesParser { _0: pvs }
    }

    /// `TypedValueParser::map`
    function map(self, func: (unknown) -> unknown throws never) -> MapValueParser { MapValueParser.new(self, func) }

    implements TypedValueParser {
        function parse_ref(self, cmd: Command, arg: Arg?, value: string) -> unknown throws Error {
            let ignore_case = if let a: Arg = arg { a.is_ignore_case_set() } else { false };
            if (self._0.some((v) -> { v.matches(value, ignore_case) })) {
                value
            } else {
                let possible_vals = self._0.filter((v) -> { !v.is_hide_set() }).map((v) -> { v.get_name() });
                let a = if let x: Arg = arg { x.to_string() } else { "..." };
                throw error_invalid_value(cmd, value, possible_vals, a)
            }
        }
        function type_id(self) -> AnyValueId throws never { AnyValueId.of<string>() }
        function possible_values(self) -> PossibleValue[]? throws never { self._0 }
    }
}

/// `std::ops::Bound<i64>`
class Bound {
    kind: "included" | "excluded" | "unbounded",
    value: int,
}

function bound_included(v: int) -> Bound { Bound { kind: "included", value: v } }
function bound_excluded(v: int) -> Bound { Bound { kind: "excluded", value: v } }
function bound_unbounded() -> Bound { Bound { kind: "unbounded", value: 0 } }

/// `i64::MIN` / `i64::MAX` (BAML ints are 63-bit)
function I64_MIN() -> int { -4611686018427387904 }
function I64_MAX() -> int { 4611686018427387903 }

/// Parse number that fall within a range of values
///
/// **NOTE:** To capture negative values, you will also need to set
/// [`Arg::allow_negative_numbers`][crate::Arg::allow_negative_numbers] or
/// [`Arg::allow_hyphen_values`][crate::Arg::allow_hyphen_values].
class RangedI64ValueParser {
    _start: Bound,
    _end: Bound,
    /// The target integer type's own range (`T: TryFrom<i64>`), e.g. `u8` => `0..=255`
    _target_min: int,
    _target_max: int,
    _type_name: string,
    _unsigned: bool,

    /// Select full range of `i64`
    function new() -> RangedI64ValueParser {
        RangedI64ValueParser {
            _start: bound_unbounded(),
            _end: bound_unbounded(),
            _target_min: I64_MIN(),
            _target_max: I64_MAX(),
            _type_name: "i64",
            _unsigned: false,
        }
    }

    /// `RangedI64ValueParser::<T>::new()` for a narrower integer type (e.g. `u8`)
    function for_type(type_name: string, min: int, max: int) -> RangedI64ValueParser {
        RangedI64ValueParser {
            _start: bound_unbounded(),
            _end: bound_unbounded(),
            _target_min: min,
            _target_max: max,
            _type_name: type_name,
            _unsigned: min >= 0,
        }
    }

    /// Narrow the supported range
    ///
    /// `start`/`end` are inclusive bounds; `null` leaves that side unbounded.
    function range(self, start: int?, end: int?) -> RangedI64ValueParser {
        // Consideration: when the user does `value_parser!(u8).range()`
        // - Avoid programming mistakes by accidentally expanding the range
        // - Make it convenient to limit the range like with `..10`
        let s = if let v: int = start { bound_included(v) } else { self._start };
        let e = if let v: int = end { bound_included(v) } else { self._end };
        RangedI64ValueParser { ...self, _start: s, _end: e }
    }

    /// `.range(start..end)`: end-exclusive
    function range_exclusive(self, start: int, end: int) -> RangedI64ValueParser {
        RangedI64ValueParser { ...self, _start: bound_included(start), _end: bound_excluded(end) }
    }

    function contains(self, v: int) -> bool {
        let lo_ok = match (self._start.kind) {
            "included" => v >= self._start.value,
            "excluded" => v > self._start.value,
            "unbounded" => true,
        };
        let hi_ok = match (self._end.kind) {
            "included" => v <= self._end.value,
            "excluded" => v < self._end.value,
            "unbounded" => true,
        };
        lo_ok && hi_ok
    }

    function format_bounds(self) -> string {
        let result = match (self._start.kind) {
            "included" => `${self._start.value}`,
            "excluded" => `${self._start.value + 1}`,
            "unbounded" => if (self._unsigned) { "0" } else { "-9223372036854775808" },
        };
        result = result + "..";
        match (self._end.kind) {
            "included" => result + `=${self._end.value}`,
            "excluded" => result + `${self._end.value}`,
            "unbounded" => result + if (self._unsigned) { "18446744073709551615" } else { "9223372036854775807" },
        }
    }

    /// `CountType` flag
    function count_type(self) -> RangedI64ValueParser { RangedI64ValueParser { ...self, _type_name: "u8" } }

    function map(self, func: (unknown) -> unknown throws never) -> MapValueParser { MapValueParser.new(self, func) }

    implements TypedValueParser {
        function parse_ref(self, cmd: Command, arg: Arg?, raw_value: string) -> unknown throws Error {
            let a = if let x: Arg = arg { x.to_string() } else { "..." };
            let value = parse_i64(raw_value) catch (e) {
                let msg: string => throw error_value_validation(a, raw_value, msg).with_cmd(cmd),
            };
            if (!self.contains(value)) {
                throw error_value_validation(a, raw_value, `${value} is not in ${self.format_bounds()}`).with_cmd(cmd);
            }
            if (value < self._target_min) {
                throw error_value_validation(a, raw_value, "out of range integral type conversion attempted").with_cmd(cmd);
            }
            if (value > self._target_max) {
                throw error_value_validation(a, raw_value, "out of range integral type conversion attempted").with_cmd(cmd);
            }
            value
        }
        function type_id(self) -> AnyValueId throws never { AnyValueId.of<int>() }
    }
}

/// Parse number that fall within a range of values
class RangedU64ValueParser {
    _inner: RangedI64ValueParser,

    /// Select full range of `u64`
    function new() -> RangedU64ValueParser {
        RangedU64ValueParser { _inner: RangedI64ValueParser.for_type("u64", 0, I64_MAX()) }
    }

    /// Narrow the supported range
    function range(self, start: int?, end: int?) -> RangedU64ValueParser {
        RangedU64ValueParser { _inner: self._inner.range(start, end) }
    }

    function count_type(self) -> RangedU64ValueParser { RangedU64ValueParser { _inner: self._inner.count_type() } }

    implements TypedValueParser {
        function parse_ref(self, cmd: Command, arg: Arg?, raw_value: string) -> unknown throws Error {
            let a = if let x: Arg = arg { x.to_string() } else { "..." };
            let value = parse_u64(raw_value) catch (e) {
                let msg: string => throw error_value_validation(a, raw_value, msg).with_cmd(cmd),
            };
            if (!self._inner.contains(value)) {
                throw error_value_validation(a, raw_value, `${value} is not in ${self._inner.format_bounds()}`).with_cmd(cmd);
            }
            value
        }
        function type_id(self) -> AnyValueId throws never { AnyValueId.of<int>() }
    }
}

/// Parse floating point numbers (`value_parser!(f64)`, via `FromStr`)
class FloatValueParser {
    function new() -> FloatValueParser { FloatValueParser {} }

    implements TypedValueParser {
        function parse_ref(self, cmd: Command, arg: Arg?, raw_value: string) -> unknown throws Error {
            let a = if let x: Arg = arg { x.to_string() } else { "..." };
            parse_f64(raw_value) catch (e) {
                let msg: string => throw error_value_validation(a, raw_value, msg).with_cmd(cmd),
            }
        }
        function type_id(self) -> AnyValueId throws never { AnyValueId.of<float>() }
    }
}

/// Implementation for [`ValueParser::bool`]
///
/// Useful for composing new [`TypedValueParser`]s
class BoolValueParser {
    function new() -> BoolValueParser { BoolValueParser {} }

    function possible_values_static() -> PossibleValue[] {
        ["true", "false"].map((s) -> { PossibleValue.new(s) })
    }

    implements TypedValueParser {
        function parse_ref(self, cmd: Command, arg: Arg?, value: string) -> unknown throws Error {
            if (value == "true") {
                true
            } else if (value == "false") {
                false
            } else {
                // Intentionally showing hidden as we hide all of them
                let possible_vals = BoolValueParser.possible_values_static().map((v) -> { v.get_name() });
                let a = if let x: Arg = arg { x.to_string() } else { "..." };
                throw error_invalid_value(cmd, value, possible_vals, a)
            }
        }
        function type_id(self) -> AnyValueId throws never { AnyValueId.of<bool>() }
        function possible_values(self) -> PossibleValue[]? throws never { BoolValueParser.possible_values_static() }
    }
}

/// Parse false-like string values, everything else is `true`
///
/// See also:
/// - [`ValueParser::bool`] for assuming non-false is true
/// - [`BoolishValueParser`] for different human readable bool representations
class FalseyValueParser {
    function new() -> FalseyValueParser { FalseyValueParser {} }

    implements TypedValueParser {
        function parse_ref(self, cmd: Command, arg: Arg?, value: string) -> unknown throws Error {
            if (value.is_empty()) { false } else { str_to_bool(value) ?? true }
        }
        function type_id(self) -> AnyValueId throws never { AnyValueId.of<bool>() }
        function possible_values(self) -> PossibleValue[]? throws never { boolish_possible_values() }
    }
}

function boolish_possible_values() -> PossibleValue[] {
    TRUE_LITERALS().concat(FALSE_LITERALS()).map((l) -> { PossibleValue.new(l).hide(l != "true" && l != "false") })
}

/// Parse bool-like string values
///
/// See also:
/// - [`ValueParser::bool`] for different human readable bool representations
/// - [`FalseyValueParser`] for assuming non-false is true
class BoolishValueParser {
    function new() -> BoolishValueParser { BoolishValueParser {} }

    implements TypedValueParser {
        function parse_ref(self, cmd: Command, arg: Arg?, value: string) -> unknown throws Error {
            let b = str_to_bool(value);
            if let v: bool = b {
                v
            } else {
                let a = if let x: Arg = arg { x.to_string() } else { "..." };
                throw error_value_validation(a, value, "value was not a boolean").with_cmd(cmd)
            }
        }
        function type_id(self) -> AnyValueId throws never { AnyValueId.of<bool>() }
        function possible_values(self) -> PossibleValue[]? throws never { boolish_possible_values() }
    }
}

/// Parse non-empty string values
///
/// See also:
/// - [`ValueParser::string`]
class NonEmptyStringValueParser {
    function new() -> NonEmptyStringValueParser { NonEmptyStringValueParser {} }

    implements TypedValueParser {
        function parse_ref(self, cmd: Command, arg: Arg?, value: string) -> unknown throws Error {
            if (value.is_empty()) {
                let a = if let x: Arg = arg { x.to_string() } else { "..." };
                throw error_empty_value(cmd, [], a);
            }
            value
        }
        function type_id(self) -> AnyValueId throws never { AnyValueId.of<string>() }
    }
}

/// Adapt a `TypedValueParser` from one value to another
///
/// See [`TypedValueParser::map`]
class MapValueParser {
    _parser: TypedValueParser,
    _func: (unknown) -> unknown throws never,

    function new(parser: TypedValueParser, func: (unknown) -> unknown throws never) -> MapValueParser {
        MapValueParser { _parser: parser, _func: func }
    }

    implements TypedValueParser {
        function parse_ref(self, cmd: Command, arg: Arg?, value: string) -> unknown throws Error {
            let v = self._parser.parse_ref(cmd, arg, value);
            let f = self._func;
            f(v)
        }
        function type_id(self) -> AnyValueId throws never { self._parser.type_id() }
        function possible_values(self) -> PossibleValue[]? throws never { self._parser.possible_values() }
    }
}

/// Adapt a `TypedValueParser` from one value to another
///
/// See [`TypedValueParser::try_map`]
class TryMapValueParser {
    _parser: TypedValueParser,
    _func: (unknown) -> unknown throws unknown,

    function new(parser: TypedValueParser, func: (unknown) -> unknown throws unknown) -> TryMapValueParser {
        TryMapValueParser { _parser: parser, _func: func }
    }

    implements TypedValueParser {
        function parse_ref(self, cmd: Command, arg: Arg?, value: string) -> unknown throws Error {
            let mid_value = self._parser.parse_ref(cmd, arg, value);
            let f = self._func;
            f(mid_value) catch_all (e) {
                _ => {
                    let a = if let x: Arg = arg { x.to_string() } else { "..." };
                    throw error_value_validation(a, value, error_to_string(e)).with_cmd(cmd)
                },
            }
        }
        function type_id(self) -> AnyValueId throws never { self._parser.type_id() }
        function possible_values(self) -> PossibleValue[]? throws never { self._parser.possible_values() }
    }
}

/// When encountered, report [`ErrorKind::UnknownArgument`][crate::error::ErrorKind::UnknownArgument]
///
/// Useful to help users migrate, either from old versions or similar tools.
class UnknownArgumentValueParser {
    _arg: Str?,
    _suggestions: StyledStr[],

    /// Suggest an alternative argument
    function suggest_arg(arg: Str) -> UnknownArgumentValueParser {
        UnknownArgumentValueParser { _arg: arg, _suggestions: [] }
    }

    /// Provide a general suggestion
    function suggest(text: StyledStr | string) -> UnknownArgumentValueParser {
        UnknownArgumentValueParser { _arg: null, _suggestions: [into_styled(text)] }
    }

    /// Extend the suggestions
    function and_suggest(self, text: StyledStr | string) -> UnknownArgumentValueParser {
        self._suggestions.push(into_styled(text));
        self
    }

    implements TypedValueParser {
        function parse_ref(self, cmd: Command, arg: Arg?, value: string) -> unknown throws Error {
            self.parse_ref_(cmd, arg, value, ValueSource.CommandLine)
        }
        function parse_ref_(self, cmd: Command, arg: Arg?, value: string, source: ValueSource) -> unknown throws Error {
            match (source) {
                ValueSource.DefaultValue => StringValueParser.new().parse_ref(cmd, arg, value),
                _ => {
                    let a = if let x: Arg = arg { x.to_string() } else { ".." };
                    let suggested = if let s: string = self._arg { SuggestedArg { arg: s, subcmd: null } } else { null };
                    let err = error_unknown_argument(
                        cmd,
                        a,
                        suggested,
                        false,
                        Usage.new(cmd).create_usage_with_title([]),
                    );
                    if (features().error_context) {
                        throw err.insert_context_unchecked(ContextKind.Suggested, ContextValueStyledStrs { value: self._suggestions });
                    }
                    throw err
                },
            }
        }
        function type_id(self) -> AnyValueId throws never { AnyValueId.of<string>() }
    }
}

// ===== `value_parser!` =====
//
// Rust's `value_parser!(T)` macro uses autoref specialization to pick the best
// parser for `T` at compile time: `ValueParserFactory`, then `ValueEnum`, then
// `From<OsString>`/`From<&OsStr>`/`From<String>`/`From<&str>`, then `FromStr`.
//
// BAML selects at runtime on `reflect.Type.of<T>()`:
// - `string`      => `ValueParser::string()`
// - `bool`        => `ValueParser::bool()`
// - `int`         => `RangedI64ValueParser` (i64)
// - `float`       => `FloatValueParser` (f64)
// - a BAML `enum` => `EnumValueParser` (like `#[derive(ValueEnum)]`)
// - a class implementing `ValueParserFactory` => its `value_parser()`
// Rust's sized integer types map to the `value_parser_u8()`, `value_parser_i32()`, ... helpers.

/// Register a type with [`value_parser!`][crate::value_parser!]
interface ValueParserFactory {
    /// Create the specified [`Self::Parser`]
    function value_parser() -> ValueParser throws never
}

/// Select a [`ValueParser`] implementation from the intended type
function value_parser<T>() -> ValueParser {
    let t = reflect.Type.of<T>();
    let name = t.to_string();
    if (name == "string") {
        return ValueParser.string();
    }
    if (name == "bool") {
        return ValueParser.bool();
    }
    if (name == "int") {
        return ValueParser.new(RangedI64ValueParser.new());
    }
    if (name == "float") {
        return ValueParser.new(FloatValueParser.new());
    }
    if (t.as_enum() != null) {
        return ValueParser.new(EnumValueParser.new<T>());
    }
    if (t.implements(reflect.Type.of<ValueParserFactory>())) {
        return value_parser_from_factory<T>();
    }
    ValueParser.string()
}

function value_parser_from_factory<T>() -> ValueParser {
    type F = T;
    ValueParser.string()
}

/// `value_parser!(E)` for a type with a hand-written `impl ValueEnum`
function value_parser_value_enum<E extends ValueEnum>() -> ValueParser {
    ValueParser.new(EnumValueParser.from_value_enum<E>())
}

/// `value_parser!(u8)`
function value_parser_u8() -> RangedI64ValueParser { RangedI64ValueParser.for_type("u8", 0, 255).range(0, 255) }
/// `value_parser!(i8)`
function value_parser_i8() -> RangedI64ValueParser { RangedI64ValueParser.for_type("i8", -128, 127).range(-128, 127) }
/// `value_parser!(u16)`
function value_parser_u16() -> RangedI64ValueParser { RangedI64ValueParser.for_type("u16", 0, 65535).range(0, 65535) }
/// `value_parser!(i16)`
function value_parser_i16() -> RangedI64ValueParser { RangedI64ValueParser.for_type("i16", -32768, 32767).range(-32768, 32767) }
/// `value_parser!(u32)`
function value_parser_u32() -> RangedI64ValueParser { RangedI64ValueParser.for_type("u32", 0, 4294967295).range(0, 4294967295) }
/// `value_parser!(i32)`
function value_parser_i32() -> RangedI64ValueParser { RangedI64ValueParser.for_type("i32", -2147483648, 2147483647).range(-2147483648, 2147483647) }
/// `value_parser!(i64)`
function value_parser_i64() -> RangedI64ValueParser { RangedI64ValueParser.new() }
/// `value_parser!(u64)`
function value_parser_u64() -> RangedU64ValueParser { RangedU64ValueParser.new() }
/// `value_parser!(usize)`
function value_parser_usize() -> RangedU64ValueParser { RangedU64ValueParser.new() }
/// `value_parser!(f64)`
function value_parser_f64() -> FloatValueParser { FloatValueParser.new() }
/// `value_parser!(PathBuf)`
function value_parser_path_buf() -> ValueParser { ValueParser.path_buf() }

// ===== `str::parse` with Rust's error messages =====

/// `str::parse::<i64>()`
function parse_i64(s: string) -> int throws string {
    if (s.is_empty()) {
        throw "cannot parse integer from empty string";
    }
    let chars = s.chars();
    let negative = false;
    let start = 0;
    if (chars[0] == "+" || chars[0] == "-") {
        negative = chars[0] == "-";
        start = 1;
        if (chars.length() == 1) {
            throw "invalid digit found in string";
        }
    }
    let value = 0;
    for (let i in baml.iter.Range.new(start, chars.length())) {
        let c = chars[i];
        if (!c.is_ascii_numeric()) {
            throw "invalid digit found in string";
        }
        let d = (c.code_point_at(0) ?? 48) - 48;
        if (negative) {
            if (value < (I64_MIN() + d) / 10) {
                throw "number too small to fit in target type";
            }
            value = value * 10 - d;
        } else {
            if (value > (I64_MAX() - d) / 10) {
                throw "number too large to fit in target type";
            }
            value = value * 10 + d;
        }
    }
    value
}

/// `str::parse::<u64>()`
function parse_u64(s: string) -> int throws string {
    if (s.starts_with("-")) {
        if (s.length() == 1) {
            throw "invalid digit found in string";
        }
        throw "invalid digit found in string";
    }
    parse_i64(s)
}

/// `str::parse::<f64>()`
function parse_f64(s: string) -> float throws string {
    let t = s;
    if (t.is_empty()) {
        throw "cannot parse float from empty string";
    }
    let lower = t.to_lower_case();
    let body = if (lower.starts_with("+") || lower.starts_with("-")) { lower.slice(1, lower.length()) } else { lower };
    if (body == "inf" || body == "infinity" || body == "nan") {
        return baml.Float.parse(t) catch_all (e) { _ => throw "invalid float literal" };
    }
    // Validate the grammar: digits [. digits] [e [+-] digits]
    let seen_digit = false;
    let seen_dot = false;
    let seen_e = false;
    let chars = body.chars();
    for (let i in baml.iter.Range.new(0, chars.length())) {
        let c = chars[i];
        if (c.is_ascii_numeric()) {
            seen_digit = true;
        } else if (c == "." && !seen_dot && !seen_e) {
            seen_dot = true;
        } else if (c == "e" && !seen_e && seen_digit) {
            seen_e = true;
            seen_digit = false;
            if (i + 1 < chars.length() && (chars[i + 1] == "+" || chars[i + 1] == "-")) {
                // sign consumed by the next iteration check below
            }
        } else if ((c == "+" || c == "-") && i > 0 && chars[i - 1] == "e") {
            // exponent sign
        } else {
            throw "invalid float literal";
        }
    }
    if (!seen_digit) {
        throw "invalid float literal";
    }
    baml.Float.parse(t) catch_all (e) { _ => throw "invalid float literal" }
}

/// `Box<dyn std::error::Error>`'s `Display`
function error_to_string(e: unknown) -> string {
    match (e) {
        let s: string => s,
        let io: baml.errors.Io => io.message,
        let pe: baml.errors.ParseError => pe.message,
        let ia: baml.errors.InvalidArgument => ia.message,
        let ce: Error => ce.to_string(),
        _ => `${e}`,
    }
}

testset "value_parser" {
    test "parse_i64" {
        assert.equal(parse_i64("42"), 42);
        assert.equal(parse_i64("-42"), -42);
        assert.equal(parse_i64("+7"), 7);
        let e1 = parse_i64("4x") catch (e) { let m: string => -1 };
        assert.equal(e1, -1);
        let msg = "";
        let _ = parse_i64("") catch (e) { let m: string => { msg = m; 0 } };
        assert.equal(msg, "cannot parse integer from empty string")
    }
    test "parse_f64" {
        assert.equal(parse_f64("1.5"), 1.5);
        assert.equal(parse_f64("-2"), -2.0);
        assert.equal(parse_f64("1e3"), 1000.0);
        let r = parse_f64("abc") catch (e) { let m: string => -1.0 };
        assert.equal(r, -1.0)
    }
}
