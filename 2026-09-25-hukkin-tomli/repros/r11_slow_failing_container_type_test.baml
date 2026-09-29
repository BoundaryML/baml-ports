// run: root.r11()
// A *failing* run-time type test against a container of a recursive alias is
// slow, and gets slower as the alias grows; a succeeding one is ~free.
type V = bool | V[] | map<string, V>
type W = bool | int | string | float | bigint | W[] | map<string, W>

function time_us(n: int, f: () -> void) -> int {
    let start = baml.time.Instant.now();
    for (let i = 0; i < n; i += 1) { f(); }
    baml.Bigint.to_int(start.elapsed().to_microseconds() / n) catch (e) { _ => -1 }
}

// Parameters (not locals) so the checks cannot be folded at compile time.
function is_v_arr(v: V) -> bool { v is V[] }
function is_w_arr(w: W) -> bool { w is W[] }
function is_w_bool(w: W) -> bool { w is bool }

function r11() -> map<string, int> {
    let b: V = true;
    let arr: V[] = [];
    let w: W = true;
    {
        "V: `true is V[]` (fails)": time_us(200, () -> void { let _ = is_v_arr(b); }),
        "V: `[] is V[]` (succeeds)": time_us(200, () -> void { let _ = is_v_arr(arr); }),
        "W: `true is W[]` (fails)": time_us(200, () -> void { let _ = is_w_arr(w); }),
        "W: `true is bool` (succeeds)": time_us(200, () -> void { let _ = is_w_bool(w); }),
    }
}
