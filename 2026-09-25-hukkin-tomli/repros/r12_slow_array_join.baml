// run: root.r12()
// `Array.join` renders each element through `string.from` and is ~100x slower
// than concatenating in a loop.
function time_us(n: int, f: () -> void) -> int {
    let start = baml.time.Instant.now();
    for (let i = 0; i < n; i += 1) { f(); }
    baml.Bigint.to_int(start.elapsed().to_microseconds() / n) catch (e) { _ => -1 }
}

function r12() -> map<string, int> {
    let parts = "abcdefghijklmnopqrstuvwxyz0123456".chars();
    {
        "join(\"\") of 33 chars": time_us(200, () -> void { let _ = parts.join(""); }),
        "loop concat of 33 chars": time_us(200, () -> void {
            let out = "";
            for (let p in parts) { out = out + p; }
        }),
    }
}
