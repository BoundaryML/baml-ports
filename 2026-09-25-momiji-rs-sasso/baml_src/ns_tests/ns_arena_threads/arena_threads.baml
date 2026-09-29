// Ported from sasso `tests/arena_threads.rs` (namespace `root.tests.arena_threads`).
//
// Concurrency regression test for the scoped bump arena's global region
// registry: many threads compile under the live `ScopedAlloc` at once, so
// each registers its own arena region and every `dealloc` classifies
// pointers against the shared (relaxed-atomic, write-once) registry while
// other threads are registering and bump-allocating. Each result must be
// byte-identical to the single-threaded one.
//
// PORT: `use sasso::{compile, Options}` → `root.compile`, `root.Options`
// (`sasso::WarnEvent` → `root.WarnEvent`). `std::thread::spawn(move || …)` →
// `spawn { … }` (a green thread) and `h.join().expect(…)` → `await h` (a
// panic or throw inside the task re-raises there and fails the test).
// `(0..n).map(|t| …).collect()` → `baml.Array.generate(n, (t) -> { … })`.
// `Rc<RefCell<…>>` shared with a handler → the (reference-typed) value itself.
// BAML is garbage-collected, so the arena these tests stress is a no-op
// bookkeeping port (see the module note in `baml_src/ns_arena/arena.baml`):
// what stays observable — and is asserted — is that every concurrent, nested
// or callback-retaining compile produces exactly the expected output.

// PORT: `#[global_allocator] static GLOBAL: sasso::ScopedAlloc = sasso::ScopedAlloc;`
// — a static → a zero-arg function. BAML has no allocator hook, so it is never
// installed; the library's arena scopes stay inert bookkeeping.
function GLOBAL() -> root.arena.ScopedAlloc {
    root.arena.ScopedAlloc {  }
}

function SRC() -> string {
    "@use \"sass:math\";
$gutter: 12px;
@mixin pad($n) { padding: $n * $gutter; }
.grid {
  width: math.div(100%, 3);
  @include pad(2);
  &:hover { color: rgba(10, 20, 30, 0.5); }
  .cell, .cap {
    margin: 1px + 2px;
    @for $i from 1 through 4 { &.s#{$i} { flex: $i; } }
  }
}
"
}

test "concurrent_compiles_share_the_region_registry" {
    // PORT: `.expect("single-threaded compile")` — a thrown error fails the test.
    let expected = root.compile(SRC(), root.Options.default());
    let threads = baml.Array.generate(8, (_t) -> {
        let expected = expected;
        spawn {
            let i = 0;
            while (i < 200) {
                let out = root.compile(SRC(), root.Options.default());
                // threaded result diverged
                assert.equal(out, expected);
                i += 1;
            }
        }
    });
    for (let t in threads) {
        // compile thread panicked
        await t;
    }
}

/// A warn handler that RETAINS what it is handed (here: appends every
/// `formatted` block to one growing `String`) must see intact data afterwards.
/// The handler runs inside the compile's arena scope, so without the library
/// pausing the arena around it, the `String`'s reallocations would come from
/// the arena and dangle once the scope resets — showing up as garbled or
/// cross-contaminated warnings, most visibly when several threads compile at
/// once. Regression test for the CLI's ordered, buffered diagnostics.
test "warn_handler_may_retain_event_data_under_the_arena" {
    // PORT: `use std::cell::RefCell; use std::rc::Rc;` — not needed.
    let handles = baml.Array.generate(8, (t) -> {
        spawn {
            let expected = "";
            let src = "";
            let i = 0;
            while (i < 40) {
                let pad = "x".repeat(i * 7);
                src = src + `@warn "thread ${t} warning ${root.std.zero_pad(i, 2)} ${pad}";\n`;
                expected
                    = expected
                        + `WARNING: thread ${t} warning ${root.std.zero_pad(i, 2)} ${pad}\n\n`;
                i += 1;
            }
            src = src + "a { b: c }\n";
            // PORT: `Rc<RefCell<String>>` → one shared `StrBuf`.
            let log = root.std.StrBuf.new();
            let sink = log;
            let opts = root.Options.default().with_warn_handler((ev: root.WarnEvent) -> void {
                // `formatted` carries the frame block; keep only the header
                // line so the expectation stays simple.
                let header = ev.formatted.lines().at(0) ?? "";
                let s = sink;
                s.push_str(header);
                s.push_str("\n\n");
            });
            let k = 0;
            while (k < 5) {
                log.clear();
                let css = root.compile(src, opts);
                assert.equal(css, "a {\n  b: c;\n}");
                // thread {t}: retained warnings are intact
                assert.equal(log.as_str(), expected);
                k += 1;
            }
        }
    });
    for (let h in handles) {
        // thread panicked
        await h;
    }
}

/// A warn handler may itself call `compile` (an embedder that formats the
/// warning with Sass, or a logger that compiles a template). That nested
/// compile runs while the outer one is paused around the handler; it must nest
/// under the outer arena scope, not reset the arena the outer evaluator is
/// still using. Regression test for `arena::pause` keeping the scope depth.
test "warn_handler_may_run_a_nested_compile" {
    // PORT: `use std::cell::RefCell; use std::rc::Rc;` — not needed.
    let handles = baml.Array.generate(4, (t) -> {
        spawn {
            let src = "";
            let i = 0;
            while (i < 30) {
                src = src + `$v${i}: ${i}px;\n@warn "w${i}";\n`;
                i += 1;
            }
            src = src + ".out {\n";
            let i = 0;
            while (i < 30) {
                src = src + `  p${i}: $v${i};\n`;
                i += 1;
            }
            src = src + "}\n";
            let expected = ".out {\n";
            let i = 0;
            while (i < 30) {
                expected = expected + `  p${i}: ${i}px;\n`;
                i += 1;
            }
            expected = expected + "}";

            // PORT: `Rc<RefCell<Vec<usize>>>` → the array itself.
            let nested_results: int[] = [];
            let sink = nested_results;
            let opts = root.Options.default().with_warn_handler((ev: root.WarnEvent) -> void {
                // Compile something substantial inside the handler so the
                // nested scope allocates plenty.
                let nested_src = `$m: "${ev.message}";\n@for $i from 1 through 40 { .n-#{$i} { w: $i * 2px; m: $m; } }\n`;
                // PORT: `.expect("nested compile")` — a thrown error propagates.
                let css = root.compile(nested_src, root.Options.default());
                // PORT: `css.len()` is the UTF-8 byte length.
                sink.push(css.byte_length());
            });
            let k = 0;
            while (k < 3) {
                nested_results.clear();
                let css = root.compile(src, opts);
                // thread {t}: outer result intact after nested compiles
                assert.equal(css, expected);
                assert.equal(nested_results.length(), 30);
                k += 1;
            }
        }
    });
    for (let h in handles) {
        // thread panicked
        await h;
    }
}

// Wire format: a `u32` argument count, then each value as a tag byte and
// payload; a string is tag 3, a quoted flag, a `u32` length, UTF-8.
// PORT: nested `fn string_value` hoisted (PORTING_GUIDE.md §2).
function host_function_may_retain_its_bytes_under_the_arena__string_value(
    quoted: bool,
    text: string,
) -> uint8array {
    let v = baml.Uint8Array.zeroes(0) catch (e) {
        _ => root.std.unreachable()
    };
    v.push(3);
    v.push(
        if (quoted) {
            1
        } else {
            0
        },
    );
    // PORT: `(text.len() as u32).to_le_bytes()` → the four little-endian
    // bytes of the UTF-8 length by hand.
    let n = root.std.as_u32(text.byte_length());
    v.push(n & 0xFF);
    v.push((n >> 8) & 0xFF);
    v.push((n >> 16) & 0xFF);
    v.push((n >> 24) & 0xFF);
    // PORT: `v.extend_from_slice(text.as_bytes())`.
    root.host_fn.extend_bytes(v, text.to_utf8());
    v
}

// PORT: nested `fn one_arg` hoisted (PORTING_GUIDE.md §2).
function host_function_may_retain_its_bytes_under_the_arena__one_arg(
    value: uint8array,
) -> uint8array {
    // PORT: `1u32.to_le_bytes().to_vec()`.
    let v = baml.Uint8Array.zeroes(0) catch (e) {
        _ => root.std.unreachable()
    };
    v.push(1);
    v.push(0);
    v.push(0);
    v.push(0);
    root.host_fn.extend_bytes(v, value);
    v
}

/// A host function (`Options::with_function`) that RETAINS what it is handed —
/// its serialized arguments and the bytes it returned — must see intact data
/// afterwards, like a warn handler. The callback runs inside the compile's
/// arena scope; without the library pausing the arena around it, the copies
/// it keeps would be arena-allocated and dangle once the scope resets, showing
/// up as garbled bytes on the next compile. Regression test for the pause
/// around the host callback.
test "host_function_may_retain_its_bytes_under_the_arena" {
    // PORT: `use std::cell::RefCell; use std::rc::Rc;` — not needed.
    let handles = baml.Array.generate(4, (t) -> {
        spawn {
            // PORT: `const N: usize = 40;` — a local.
            let N = 40;
            let src = ".out {\n";
            let expected_css = ".out {\n";
            let expected_inputs: uint8array[] = [];
            let i = 0;
            while (i < N) {
                let text = `thread ${t} value ${root.std.zero_pad(i, 2)} ${"y".repeat(i * 5)}`;
                src = src + `  p${i}: echo("${text}");\n`;
                expected_css = expected_css + `  p${i}: ${text};\n`;
                expected_inputs.push(
                    host_function_may_retain_its_bytes_under_the_arena__one_arg(host_function_may_retain_its_bytes_under_the_arena__string_value(true, text)),
                );
                i += 1;
            }
            src = src + "}";
            expected_css = expected_css + "}";
            // Everything the callback saw and produced, kept across calls
            // and across compiles.
            // PORT: `type Retained = Vec<(Vec<u8>, Vec<u8>)>` inlined; the
            // `Rc<RefCell<Retained>>` is the array itself.
            let retained: root.std.Tuple2<uint8array, uint8array>[] = [];
            let sink = retained;
            let opts = root.Options.default().with_function("echo($s)", (bytes: uint8array) -> uint8array {
                // Unquote: return the same text as an unquoted string.
                // PORT: `u32::from_le_bytes([bytes[6], …, bytes[9]]) as usize`.
                let len = bytes[6] | (bytes[7] << 8) | (bytes[8] << 16) | (bytes[9] << 24);
                // PORT: `std::str::from_utf8(..).map_err(|e| e.to_string())?` —
                // the `Err(String)` is a thrown `root.std.StrError`.
                let text = string.from_utf8(bytes.slice(10, 10 + len)) catch (e) {
                    let err: baml.errors.InvalidArgument => root.std.err_str(err.message)
                };
                let out = host_function_may_retain_its_bytes_under_the_arena__string_value(false, text);
                // PORT: `bytes.to_vec()` / `out.clone()` — fresh copies.
                sink.push(
                    root.std.Tuple2 {
                        _0: bytes.slice(0, bytes.length()),
                        _1: out.slice(0, out.length()),
                    },
                );
                out
            });
            let k = 0;
            while (k < 5) {
                retained.clear();
                let css = root.compile(src, opts);
                // thread {t}: output intact
                assert.equal(css, expected_css);
                let seen = retained;
                assert.equal(seen.length(), N);
                let i = 0;
                while (i < seen.length()) {
                    let input = seen[i]._0;
                    let output = seen[i]._1;
                    // thread {t}: retained input {i} intact
                    assert.equal(input, expected_inputs[i]);
                    let text = `thread ${t} value ${root.std.zero_pad(i, 2)} ${"y".repeat(i * 5)}`;
                    // thread {t}: retained output {i} intact
                    assert.equal(
                        output,
                        host_function_may_retain_its_bytes_under_the_arena__string_value(false, text),
                    );
                    i += 1;
                }
                k += 1;
            }
        }
    });
    for (let h in handles) {
        // thread panicked
        await h;
    }
}
