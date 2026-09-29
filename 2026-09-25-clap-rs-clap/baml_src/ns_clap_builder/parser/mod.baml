// Port of clap_builder/src/parser/mod.rs
//
// [`Command`][crate::Command] line argument parser
//
//   mod arg_matcher;        -> arg_matcher.baml   (ArgMatcher)
//   mod error;              -> error.baml         (MatchesError)
//   mod matches;            -> matches/           (ArgMatches, ValueSource, MatchedArg, ...)
//   mod parser;             -> parser.baml        (CmdParser, Identifier, PendingArg)
//   mod validator;          -> validator.baml     (Validator, get_possible_values_cli)
//   pub(crate) mod features -> features/          (suggestions)
//
// Note: Rust's internal `parser::Parser` struct is named `CmdParser` in this
// port, because `Parser` is taken by the public derive trait (`derive.baml`)
// in the same namespace.
