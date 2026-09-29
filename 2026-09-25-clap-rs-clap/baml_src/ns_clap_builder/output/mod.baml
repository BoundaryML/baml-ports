// Port of clap_builder/src/output/mod.rs
//
//   mod help;               -> help.baml          (write_help)
//   mod help_template;      -> help_template.baml (AutoHelp, HelpTemplate)
//   mod usage;              -> usage.baml         (Usage)
//   pub(crate) mod fmt;     -> fmt.baml           (Colorizer, Stream)
//   pub(crate) mod textwrap -> textwrap/          (display_width, wrap)

function TAB() -> string { "  " }

function TAB_WIDTH() -> int { 2 }
