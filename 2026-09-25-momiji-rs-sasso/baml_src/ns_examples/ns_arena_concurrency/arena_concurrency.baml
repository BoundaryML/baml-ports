// Ported from sasso `examples/arena_concurrency.rs` (namespace
// `root.examples.arena_concurrency`).
//
// Concurrency-isolation check for the scoped bump arena (perf #5).
//
// Installs [`sasso::ScopedAlloc`] as the global allocator, then spawns N
// threads that each call `sasso::compile` many times concurrently and assert
// every result is byte-identical to a single-threaded reference. Because each
// thread keeps its own thread-local arena (a compile is `!Send`), the threads'
// arenas must never interfere; a corrupt or shared arena would surface as a
// wrong/garbled output here.
//
// Run with: `cargo run --release --example arena_concurrency`
// PORT: run it with
// `RUST_MIN_STACK=1073741824 baml run examples.arena_concurrency.main`.
// The OS threads are BAML green threads (`spawn`, joined by `await`), which
// interleave compiles on the VM's scheduler; `Arc` is dropped (arrays are
// shared by reference).

// PORT: `use std::sync::Arc; use std::thread;` and
// `use sasso::{compile, Options};` → `spawn`/`await`, `root.compile`,
// `root.Options`.

function GLOBAL() -> root.arena.ScopedAlloc {
    // PORT: `#[global_allocator]` has no BAML counterpart (the VM owns all
    // memory); the static is kept as a plain value, as in `main.baml`.
    root.arena.ScopedAlloc {  }
}

function SOURCES() -> string[] {
    [
        "$c: #336699;\n.a { color: $c; .b { color: lighten($c, 10%); } &:hover { color: mix($c, white, 50%); } }",
        "@function double($n) { @return $n * 2; }\n@for $i from 1 through 20 { .c#{$i} { w: double($i) * 1px; } }",
        "@mixin box($p, $c: blue) { padding: $p; color: $c; }\n.x { @include box(4px); }\n.y { @include box(8px, red); }",
        ".grid { @each $n in a, b, c, d { .col-#{$n} { content: \"#{$n}\"; } } }",
    ]
}

function main() -> void {
    let threads = 8;
    let iters = 2000;

    // Single-threaded reference outputs (also produced under ScopedAlloc).
    // PORT: `Arc<Vec<String>>` → a plain array, shared by reference.
    let reference: string[] = SOURCES().map((src: string) -> string throws unknown {
        // PORT: `.expect("reference compile")`.
        root.compile(src, root.Options.default()) catch (e) {
            let e: root.error.Error => root.std.panic(`reference compile: ${e.to_string()}`)
        }
    });

    let handles = [];
    for (let t in baml.iter.Range.new(0, threads)) {
        // PORT: `let reference = Arc::clone(&reference);` — the closure
        // captures the same array.
        handles.push(spawn {
            for (let i in baml.iter.Range.new(0, iters)) {
                let idx = (t + i) % SOURCES().length();
                // PORT: `.expect("threaded compile should succeed")`.
                let got = root.compile(SOURCES()[idx], root.Options.default()) catch (e) {
                    let e: root.error.Error => {
                        root.std.panic(`threaded compile should succeed: ${e.to_string()}`)
                    }
                };
                // PORT: `assert_eq!(got, reference[idx], "…")` → panic with the
                // same message (and the `left`/`right` report) on a mismatch.
                if (got != reference[idx]) {
                    root.std.panic(
                        `assertion \`left == right\` failed: thread ${t} iter ${i}: output diverged from the reference (arena interference?)\n  left: ${root.std.debug_str(got)}\n right: ${root.std.debug_str(reference[idx])}`,
                    );
                }
            }
        });
    }
    for (let h in handles) {
        // PORT: `h.join().expect("worker thread panicked")` — a panic in a
        // green thread propagates out of `await`.
        await h;
    }

    baml.io.println(
        `concurrency OK: ${threads} threads x ${iters} compiles each = ${threads * iters} compiles, all byte-identical`,
    );
}
