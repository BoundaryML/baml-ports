// Port of anstyle/src/reset.rs

/// Reset terminal formatting
class Reset {
    function new() -> Reset { Reset {} }

    /// Render the ANSI code
    function render(self) -> string { reset_str() }
}

/// `RESET` const
function reset_str() -> string { `${esc()}[0m` }
