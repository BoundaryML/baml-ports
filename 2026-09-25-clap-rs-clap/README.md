# clap → BAML

A port of Rust's [clap](https://github.com/clap-rs/clap) 4.6.1 (builder + derive APIs)
to BAML. Every crate becomes a BAML namespace (`ns_<crate>`), and each crate's Rust modules
map to files at the same relative path (`mod.rs` → `mod.baml`).

## Layout

| Rust crate | BAML namespace | Role |
|---|---|---|
| `clap` | `baml_src/ns_clap/` | Facade (re-exports, `arg`, `command`, `value_parser<T>`), examples |
| `clap_builder` | `baml_src/ns_clap_builder/` | `builder/`, `parser/`, `output/`, `error/`, `util/`, `derive.baml` (traits) |
| `clap_derive` | `baml_src/ns_clap_derive/` | Reflection-driven derive (`attr`, `item`, `derives/`, `utils/`) |
| `clap_lex` | `ns_clap_lex/` | Raw argv lexing |
| `anstyle`, `anstyle-query`, `anstream`, `colorchoice` | `ns_anstyle/` … | Styling / color output |
| `strsim`, `unicase`, `unicode-width`, `terminal_size`, `backtrace` | `ns_strsim/` … | Parser/output support |
| `heck`, `proc-macro2`, `syn` | `ns_heck/`, `ns_proc_macro2/`, `ns_syn/` | Used by `clap_derive` to parse `#[arg(...)]` attributes |
| `clap-cargo`, `semver`, `jiff` | `ns_clap_cargo/`, `ns_semver/`, `ns_jiff/` | Example dev-dependencies |

Examples live under `baml_src/ns_clap/ns_examples/` and mirror `clap/examples/`
(`tutorial_builder/01_quick.rs` → `ns_tutorial_builder/ns_ex_01_quick/`, since
namespaces can't start with a digit).

## Running

```sh
baml test                                   # 110 unit tests
baml run clap.examples.git.main -- clone x  # run an example
python3 tests/trycmd.py [filter] [-v]       # clap's own .md transcripts (273/273 pass)
```

`tests/trycmd.py` packs each example with `baml pack` and replays upstream
`examples/**/*.md` transcripts. `tests/examples/bins.txt` maps Cargo `[[example]]` names to paths.

## Derive

Rust attributes go in `///` doc comments as `#[...]` lines and are read at runtime via reflection:

```baml
/// #[command(version, about, long_about = None)]
class Cli {
    /// Name of the person to greet
    /// #[arg(short, long)]
    name: string,
    implements root.clap_builder.Parser {}
    implements root.clap_builder.CommandFactory {}
    implements root.clap_builder.FromArgMatches {}
    implements root.clap_builder.Args {}
}
```

Subcommand enums are unions of classes (use `root.clap_derive.augment_subcommands<U>` /
`subcommand_from_matches<U>`); value enums are BAML enums. You can hand-write trait methods by
overriding them in the `implements` block. Derived code picks those overrides up
(`derive_ref/flatten_hand_args`, `hand_subcommand`).

## Differences from Rust

- Cargo features come from the `CLAP_FEATURES` env var (for example `CLAP_FEATURES=wrap_help,env`).
  Color comes from `NO_COLOR`/`BAML_COLORCHOICE`, and terminal detection from `BAML_IS_TERMINAL`.
- `update_from_arg_matches` can't be derived; hand-write it if you need it.
- If two union variants would decode the same way, give each one a literal tag field (for example `kind: "push"`).
  The derive reports an error when variants are ambiguous.
- Enum variants and `implements` have to use the full `root.clap_builder.*` path. Aliases in `root.clap` don't work for these.
- `Id` is a `string`, so `ArgMatches` can't tell group ids apart by type. Look groups up through the `Command`.
- Porting notes use `//` comments. `///` would end up in help text.
- `Debug` output (`{:#?}`) in the examples is written by hand.
