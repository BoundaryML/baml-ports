// run: root.r10_catch()
function r10(n: int) -> int { if (n == 0) { 0 } else { 1 + r10(n - 1) } }
function r10_catch() -> int { r10(300) catch_all (e) { _ => -1 } }
