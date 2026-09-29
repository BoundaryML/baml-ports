// Port of clap-4.6.1/src/lib.rs
//
// > **Command Line Argument Parser for Rust**
//
// The `clap` crate is a facade: `pub use clap_builder::*;` plus the derive
// macros from `clap_derive`. In BAML the facade is the `root.clap` namespace:
// types are re-exported as aliases (static calls such as
// `root.clap.Command.new("app")` work through an alias) and free functions as
// thin wrappers.
//
// Enum *variants* cannot be reached through an alias either, so they are
// written with the defining namespace: `root.clap_builder.ArgAction.SetTrue`
// (Rust: `clap::ArgAction::SetTrue`, a re-export of the same enum).
//
// Interfaces can be *named* through the aliases below, but BAML only accepts
// the defining path in an `implements` clause, so "deriving" is written as:
//
// ```baml
// class Cli {
//     implements root.clap_builder.Parser {}
//     implements root.clap_builder.CommandFactory {}
//     implements root.clap_builder.FromArgMatches {}
//     implements root.clap_builder.Args {}
// }
// ```
//
// Documentation modules (`_concepts`, `_cookbook`, `_derive`, `_faq`,
// `_features`, `_tutorial`) are Rust doc pages and are represented by the
// runnable examples under `examples/` (`ns_examples/`).

// ===== pub use clap_builder::* =====

type Command = root.clap_builder.Command
type Arg = root.clap_builder.Arg
type ArgGroup = root.clap_builder.ArgGroup
type ArgAction = root.clap_builder.ArgAction
type ArgMatches = root.clap_builder.ArgMatches
type ValueHint = root.clap_builder.ValueHint
type ColorChoice = root.clap_builder.ColorChoice
type Id = root.clap_builder.Id
type Error = root.clap_builder.Error
type ErrorKind = root.clap_builder.ErrorKind
type ContextKind = root.clap_builder.ContextKind
type ContextValue = root.clap_builder.ContextValue
type ValueSource = root.clap_builder.ValueSource
type SubcommandMatch = root.clap_builder.SubcommandMatch

// builder
type ArgPredicate = root.clap_builder.ArgPredicate
type ArgPredicateEquals = root.clap_builder.ArgPredicateEquals
type ArgPredicateIsPresent = root.clap_builder.ArgPredicateIsPresent
type ArgIdValue = root.clap_builder.ArgIdValue
type ArgRequire = root.clap_builder.ArgRequire
type DefaultValueIf = root.clap_builder.DefaultValueIf
type PossibleValue = root.clap_builder.PossibleValue
type ValueRange = root.clap_builder.ValueRange
type Str = root.clap_builder.Str
type OsStr = root.clap_builder.OsStr
type OsString = root.clap_builder.OsString
type PathBuf = root.clap_builder.PathBuf
type StyledStr = root.clap_builder.StyledStr
type Styles = root.clap_builder.Styles
type ValueParser = root.clap_builder.ValueParser
type TypedValueParser = root.clap_builder.TypedValueParser
type ValueParserFactory = root.clap_builder.ValueParserFactory
type BoolValueParser = root.clap_builder.BoolValueParser
type BoolishValueParser = root.clap_builder.BoolishValueParser
type EnumValueParser = root.clap_builder.EnumValueParser
type FalseyValueParser = root.clap_builder.FalseyValueParser
type FloatValueParser = root.clap_builder.FloatValueParser
type FnValueParser = root.clap_builder.FnValueParser
type MapValueParser = root.clap_builder.MapValueParser
type NonEmptyStringValueParser = root.clap_builder.NonEmptyStringValueParser
type OsStringValueParser = root.clap_builder.OsStringValueParser
type PathBufValueParser = root.clap_builder.PathBufValueParser
type PossibleValuesParser = root.clap_builder.PossibleValuesParser
type RangedI64ValueParser = root.clap_builder.RangedI64ValueParser
type RangedU64ValueParser = root.clap_builder.RangedU64ValueParser
type StringValueParser = root.clap_builder.StringValueParser
type TryMapValueParser = root.clap_builder.TryMapValueParser
type UnknownArgumentValueParser = root.clap_builder.UnknownArgumentValueParser

// derive traits (`clap_builder::derive`, re-exported with the `clap_derive` macros)
type Parser = root.clap_builder.Parser
type CommandFactory = root.clap_builder.CommandFactory
type FromArgMatches = root.clap_builder.FromArgMatches
type Args = root.clap_builder.Args
type Subcommand = root.clap_builder.Subcommand
type ValueEnum = root.clap_builder.ValueEnum

// error formatters
type ErrorFormatter = root.clap_builder.ErrorFormatter
type KindFormatter = root.clap_builder.KindFormatter
type RichFormatter = root.clap_builder.RichFormatter

// styling (`clap::builder::styling`, which re-exports `anstyle`)
type Style = root.anstyle.Style
type Color = root.anstyle.Color
type AnsiColor = root.anstyle.AnsiColor
type Ansi256Color = root.anstyle.Ansi256Color
type RgbColor = root.anstyle.RgbColor
type Effects = root.anstyle.Effects

// ===== macros =====

/// `arg!(...)`
function arg(spec: string) -> Arg { root.clap_builder.arg(spec) }

/// `command!()` / `command!(name)`
function command(name: string? = null) -> Command { root.clap_builder.command(name = name) }

/// `crate_version!()`
function crate_version() -> string { root.clap_builder.crate_version() }

/// `crate_authors!()` / `crate_authors!(sep)`
function crate_authors(sep: string? = null) -> string { root.clap_builder.crate_authors(sep = sep) }

/// `crate_description!()`
function crate_description() -> string { root.clap_builder.crate_description() }

/// `crate_name!()`
function crate_name() -> string { root.clap_builder.crate_name() }

/// `value_parser!(T)`
function value_parser<T>() -> ValueParser { root.clap_builder.value_parser<T>() }

/// `value_parser!(E)` for a type with a hand-written `impl ValueEnum`
function value_parser_value_enum<E extends root.clap_builder.ValueEnum>() -> ValueParser { root.clap_builder.value_parser_value_enum<E>() }

/// `value_parser!(u8)` .. `value_parser!(u64)`, `value_parser!(f64)`
function value_parser_u8() -> RangedI64ValueParser { root.clap_builder.value_parser_u8() }
function value_parser_i8() -> RangedI64ValueParser { root.clap_builder.value_parser_i8() }
function value_parser_u16() -> RangedI64ValueParser { root.clap_builder.value_parser_u16() }
function value_parser_i16() -> RangedI64ValueParser { root.clap_builder.value_parser_i16() }
function value_parser_u32() -> RangedI64ValueParser { root.clap_builder.value_parser_u32() }
function value_parser_i32() -> RangedI64ValueParser { root.clap_builder.value_parser_i32() }
function value_parser_i64() -> RangedI64ValueParser { root.clap_builder.value_parser_i64() }
function value_parser_u64() -> RangedU64ValueParser { root.clap_builder.value_parser_u64() }
function value_parser_usize() -> RangedU64ValueParser { root.clap_builder.value_parser_usize() }
function value_parser_f64() -> FloatValueParser { root.clap_builder.value_parser_f64() }

// ===== helpers for porting Rust `{:?}` formatting =====

/// `format!("{:?}", s)` for a `&str`/`String`
function debug_str(s: string) -> string { root.clap_builder.debug_str(s) }

/// `format!("{:?}", v)` for a `Vec<String>`
function debug_str_list(v: string[]) -> string { root.clap_builder.debug_str_list(v) }

/// `format!("{:?}", o)` for an `Option<String>`
function debug_opt_str(o: string?) -> string { root.clap_builder.debug_opt_str(o) }
