// Port of clap-cargo/src/style.rs
//
// `clap-cargo` is a dev-dependency of `clap` (used by `examples/cargo-example.rs`)
// providing cargo's terminal styling.

function NOP() -> root.anstyle.Style { root.anstyle.Style.new() }
function HEADER() -> root.anstyle.Style { root.anstyle.on_default(root.anstyle.AnsiColor.BrightGreen).effects(root.anstyle.Effects.BOLD()) }
function USAGE() -> root.anstyle.Style { root.anstyle.on_default(root.anstyle.AnsiColor.BrightGreen).effects(root.anstyle.Effects.BOLD()) }
function LITERAL() -> root.anstyle.Style { root.anstyle.on_default(root.anstyle.AnsiColor.BrightCyan).effects(root.anstyle.Effects.BOLD()) }
function PLACEHOLDER() -> root.anstyle.Style { root.anstyle.on_default(root.anstyle.AnsiColor.Cyan) }
function ERROR() -> root.anstyle.Style { root.anstyle.on_default(root.anstyle.AnsiColor.BrightRed).effects(root.anstyle.Effects.BOLD()) }
function WARN() -> root.anstyle.Style { root.anstyle.on_default(root.anstyle.AnsiColor.BrightYellow).effects(root.anstyle.Effects.BOLD()) }
function NOTE() -> root.anstyle.Style { root.anstyle.on_default(root.anstyle.AnsiColor.BrightCyan).effects(root.anstyle.Effects.BOLD()) }
function GOOD() -> root.anstyle.Style { root.anstyle.on_default(root.anstyle.AnsiColor.BrightGreen).effects(root.anstyle.Effects.BOLD()) }
function VALID() -> root.anstyle.Style { root.anstyle.on_default(root.anstyle.AnsiColor.BrightCyan).effects(root.anstyle.Effects.BOLD()) }
function INVALID() -> root.anstyle.Style { root.anstyle.on_default(root.anstyle.AnsiColor.Yellow).effects(root.anstyle.Effects.BOLD()) }
