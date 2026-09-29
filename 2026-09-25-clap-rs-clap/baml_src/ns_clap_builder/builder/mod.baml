// Port of clap_builder/src/builder/mod.rs
//
// Define [`Command`] line [arguments][`Arg`]
//
//   mod action;          -> action.baml          (ArgAction)
//   mod app_settings;    -> app_settings.baml    (AppSettings, AppFlags)
//   mod arg;             -> arg.baml             (Arg)
//   mod arg_group;       -> arg_group.baml       (ArgGroup)
//   mod arg_predicate;   -> arg_predicate.baml   (ArgPredicate)
//   mod arg_settings;    -> arg_settings.baml    (ArgSettings, ArgFlags)
//   mod command;         -> command.baml         (Command)
//   mod ext;             -> ext.baml             (Extensions)
//   mod os_str;          -> os_str.baml          (OsStr)
//   mod possible_value;  -> possible_value.baml  (PossibleValue)
//   mod range;           -> range.baml           (ValueRange)
//   mod resettable;      -> resettable.baml      (Resettable)
//   mod str;             -> str.baml             (Str)
//   mod styled_str;      -> styled_str.baml      (StyledStr)
//   mod value_hint;      -> value_hint.baml      (ValueHint)
//   mod value_parser;    -> value_parser.baml    (ValueParser, TypedValueParser, ...)
//   mod debug_asserts;   -> debug_asserts.baml   (assert_app, assert_arg, ...)
//   mod tests;           -> tests.baml
//   pub mod styling;     -> styling.baml         (Styles + anstyle re-exports)
