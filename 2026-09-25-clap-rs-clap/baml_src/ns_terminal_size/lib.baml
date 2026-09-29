// Port of terminal_size-0.4.3/src/lib.rs (+ unix.rs)
//
// A simple utility for getting the size of a terminal. Used by `clap_builder`
// when the `wrap_help` feature is enabled.

class Width { value: int }
class Height { value: int }

class TerminalSize {
    width: Width,
    height: Height,
}

/// Returns the size of the terminal.
///
/// Rust queries stdout, stderr, then stdin with the `TIOCGWINSZ` ioctl. BAML
/// cannot issue ioctls and a child process's stdout/stderr are pipes, so this
/// asks `stty` about the inherited stdin, returning `null` when it is not a
/// terminal (e.g. when running under CI or piped).
function terminal_size() -> TerminalSize? {
    let out = baml.sys.shell("stty size 2>/dev/null", null) catch_all (e) { _ => null };
    if let o: baml.sys.ShellOutput = out {
        parse_stty(baml.String.from_utf8(o.stdout) catch_all (e) { _ => "" })
    } else {
        null
    }
}

function parse_stty(s: string) -> TerminalSize? {
    let parts = s.trim().split(" ").filter((p) -> { !p.is_empty() });
    if (parts.length() != 2) {
        return null;
    }
    let rows = baml.Int.parse(parts[0]) catch_all (e) { _ => 0 };
    let cols = baml.Int.parse(parts[1]) catch_all (e) { _ => 0 };
    if (rows > 0 && cols > 0) {
        TerminalSize { width: Width { value: cols }, height: Height { value: rows } }
    } else {
        null
    }
}

test "parse_stty" {
    let size = parse_stty("40 120\n");
    assert.equal(size?.width?.value, 120);
    assert.equal(size?.height?.value, 40);
    assert.equal(parse_stty(""), null)
}
