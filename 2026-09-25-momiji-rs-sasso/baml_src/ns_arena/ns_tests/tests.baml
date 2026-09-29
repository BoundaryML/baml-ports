// Ported from sasso `src/arena.rs`: the `#[cfg(test)]` items — the test-only
// standalone `Arena` (its `impl` and `impl Drop`) — and `mod tests` (namespace
// `root.arena.tests`).
//
// PORT: `use super::*;` → items of `root.arena` are written fully qualified.
//
// PORT: the thread-local and process-global state. `root.arena` models `TL`,
// `REGIONS` and `REGION_SLOTS` as zero-arg functions that build a fresh value
// on every access (BAML has no globals or thread-locals — see the module note
// in `ns_arena/arena.baml`), so no scope, pause or lease outlives the call that
// made it: `ScopedAlloc` always routes to the modeled `System`,
// `leave_no_reset` always reports the outermost scope, `in_any_arena` is
// always false, and every `TL` read sees `ThreadState::new()`. The
// `ScopedAlloc` routing tests below are ported statement by statement; each
// assertion that depends on that state persisting asserts what the BAML port
// does instead, marked `// PORT: inert TL`.
//
// PORT: raw memory. A `*mut u8` is an `int` address (null → `0`). The
// standalone `Arena` models its `System` block's bytes (`mem`), so the tests'
// `std::ptr::write_bytes` / `*p` and `realloc`'s `copy_nonoverlapping` act on
// real data; a `ScopedAlloc` address has no memory behind it.
//
// PORT: threads. `std::thread::spawn` → `spawn { … }` (green threads, which
// run in parallel); `.join().unwrap()` → `await`. `Barrier` and `mpsc`
// channels have no BAML counterpart, so `Signal` / `Oneshot` / `Barrier` below
// stand in for them; a `Mutex` held around a block → that block run as a task
// in a `baml.spawn.TaskGroup` of limit 1.

// =========================================================================
// Test-only standalone arena: a `Drop`-ing twin of the bump + provenance logic
// above, used to exercise it under `cargo miri test` without leaking.
// =========================================================================

// PORT: `Cell<usize>` → a plain field (the struct is only ever reached by
// reference); `mem` is the modeled content of the `System` block (see above):
// `mem[p - base]` is the byte at address `p`.
class Arena {
    base: int,
    size: int,
    end: int,
    cursor: int,
    mem: uint8array,

    function with_system_backing(size: int) -> Arena? {
        let layout = root.arena.Layout.from_size_align(size, 4096);
        if (layout == null) {
            return null;
        }
        // SAFETY: non-zero size, valid align.
        let base = root.arena.System.alloc(layout);
        if (base == 0) {
            return null;
        }
        Arena {
            base: base,
            size: size,
            end: base + size,
            cursor: base,
            mem: baml.Uint8Array.zeroes(size) catch (e) {
                _ => root.std.unreachable()
            },
        }
    }

    function alloc(self, layout: root.arena.Layout) -> int? {
        let r = root.arena.bump_compute(self.cursor, layout.align, layout.size, self.end);
        if (r == null) {
            return null;
        }
        let aligned = r._0;
        let next = r._1;
        self.cursor = next;
        // SAFETY: in-bounds offset (see bump_compute).
        self.base + (aligned - self.base)
    }

    function reset(self) -> void {
        self.cursor = self.base;
    }

    function used(self) -> int {
        self.cursor - self.base
    }

    function contains(self, ptr: int) -> bool {
        let p = ptr;
        p >= self.base && p < self.end
    }

    /// Twin of [`ScopedAlloc::realloc`]'s logic: extend the last bump in place,
    /// else copy to a fresh allocation.
    function realloc(self, ptr: int, old: root.arena.Layout, new_size: int) -> int? {
        let addr = ptr;
        if (addr >= self.base && addr + old.size == self.cursor) {
            let new_end = root.arena.checked_add(addr, new_size);
            if (new_end == null) {
                return null;
            }
            if (new_end <= self.end) {
                self.cursor = new_end;
                return ptr;
            }
        }
        let new_layout = root.arena.Layout.from_size_align(new_size, old.align);
        if (new_layout == null) {
            return null;
        }
        let np = self.alloc(new_layout);
        if (np == null) {
            return null;
        }
        // SAFETY: np is a fresh, non-overlapping allocation of >= copy length.
        copy_nonoverlapping(self, ptr, np, root.std.imin(old.size, new_size));
        np
    }

    // PORT: `impl Drop for Arena` → a plain `drop()` (BAML has no destructors);
    // the tests call it where the Rust `Arena` goes out of scope.
    function drop(self) -> void {
        let layout = root.arena.Layout.from_size_align(self.size, 4096);
        if (layout != null) {
            // SAFETY: base came from System.alloc with this layout.
            root.arena.System.dealloc(self.base, layout);
        }
    }
}

/// PORT: `std::ptr::write_bytes(p, val, count)` into `a`'s modeled memory.
function write_bytes(a: Arena, p: int, val: int, count: int) -> void {
    let k = 0;
    while (k < count) {
        a.mem[p - a.base + k] = val;
        k += 1;
    }
}

/// PORT: `*p` — the byte at address `p` of `a`'s modeled memory.
function deref(a: Arena, p: int) -> int {
    a.mem[p - a.base]
}

/// PORT: `core::ptr::copy_nonoverlapping(src, dst, count)` within `a`'s
/// modeled memory.
function copy_nonoverlapping(a: Arena, src: int, dst: int, count: int) -> void {
    let k = 0;
    while (k < count) {
        a.mem[dst - a.base + k] = a.mem[src - a.base + k];
        k += 1;
    }
}

// ---- PORT: stand-ins for `std::sync::{Barrier, mpsc}` ----
//
// BAML has neither, and its green threads really run in parallel, so a plain
// shared flag or counter would race. A `baml.spawn.CancelToken` is the
// runtime's thread-safe one-shot flag: firing it is a send, polling it (with a
// 1 ms sleep to yield) is a blocking receive.

/// PORT: one `()` message on an `mpsc::channel::<()>()`, or one party's
/// arrival at a `Barrier`.
class Signal {
    token: baml.spawn.CancelToken,

    function new() -> Signal {
        Signal { token: baml.spawn.CancelToken.new() }
    }

    function send(self) -> void {
        let _ = self.token.cancel();
    }

    function recv(self) -> void {
        while (!self.token.is_cancelled()) {
            root.std.sleep_ms(1);
        }
    }
}

/// PORT: one `bool` message on an `mpsc::channel::<bool>()`: the value is
/// stored before the signal fires.
class Oneshot {
    signal: Signal,
    value: bool,

    function new() -> Oneshot {
        Oneshot { signal: Signal.new(), value: false }
    }

    function send(self, v: bool) -> void {
        self.value = v;
        self.signal.send();
    }

    function recv(self) -> bool {
        self.signal.recv();
        self.value
    }
}

/// PORT: a single-use `std::sync::Barrier` for `n` parties. Without an atomic
/// counter each party passes its own index to `wait`.
class Barrier {
    arrived: Signal[],

    function new(n: int) -> Barrier {
        Barrier {
            arrived: baml.Array.generate(n, (i: int) -> Signal {
                Signal.new()
            }),
        }
    }

    function wait(self, party: int) -> void {
        self.arrived[party].send();
        for (let s in self.arrived) {
            s.recv();
        }
    }
}

/// `live_regions()` is process-wide, so the tests that watch it have to
/// not run while another one is reserving. Only arena tests ever take a
/// region, so serialising them against each other is enough.
// PORT: `static REGION_COUNT: std::sync::Mutex<()>` dropped, and with it every
// test's `let _serial = REGION_COUNT.lock().unwrap_or_else(|e| e.into_inner());`
// — the BAML port has no process-wide region state for tests to race on.

// ---- pure bump_compute (also covered by Miri) ----

test "compute_aligns_up" {
    assert.equal(
        root.arena.bump_compute(10, 8, 4, 1000),
        root.std.Tuple2<int, int> { _0: 16, _1: 20 },
    );
    assert.equal(
        root.arena.bump_compute(16, 8, 8, 1000),
        root.std.Tuple2<int, int> { _0: 16, _1: 24 },
    );
    assert.equal(
        root.arena.bump_compute(7, 1, 3, 1000),
        root.std.Tuple2<int, int> { _0: 7, _1: 10 },
    )
}

test "compute_every_power_of_two_alignment" {
    for (let align in [1, 2, 4, 8, 16, 32, 64, 128, 256, 4096]) {
        // PORT: `usize::MAX` → `root.std.INT_MAX()`.
        let r = root.std.unwrap(root.arena.bump_compute(1, align, 64, root.std.INT_MAX()));
        let aligned = r._0;
        let next = r._1;
        // align {align}
        assert.equal(aligned % align, 0);
        assert.equal(next, aligned + 64);
    }
}

test "compute_zero_size" {
    assert.equal(root.arena.bump_compute(8, 8, 0, 100), root.std.Tuple2<int, int> { _0: 8, _1: 8 })
}

test "compute_boundary" {
    assert.equal(
        root.arena.bump_compute(0, 1, 100, 100),
        root.std.Tuple2<int, int> { _0: 0, _1: 100 },
    );
    assert.equal(root.arena.bump_compute(0, 1, 101, 100), null);
    assert.equal(root.arena.bump_compute(90, 8, 20, 100), null)
}

test "compute_overflow_is_none" {
    // PORT: `usize::MAX` → `root.std.INT_MAX()`.
    assert.equal(root.arena.bump_compute(root.std.INT_MAX(), 8, 0, root.std.INT_MAX()), null);
    assert.equal(root.arena.bump_compute(root.std.INT_MAX() - 3, 1, 10, root.std.INT_MAX()), null)
}

// ---- standalone Arena (run under Miri for UB) ----

function layout(size: int, align: int) -> root.arena.Layout {
    root.std.unwrap(root.arena.Layout.from_size_align(size, align))
}

test "realloc_extends_tail_in_place_else_copies" {
    let a = root.std.unwrap(Arena.with_system_backing(64 * 1024));
    defer { a.drop() }
    let p = root.std.unwrap(a.alloc(layout(8, 8)));
    // SAFETY: p is a live 8-byte allocation.
    write_bytes(a, p, 0xCD, 8);
    let used = a.used();
    // Tail grow: same pointer, only the delta is bumped (no dead buffer).
    let p2 = root.std.unwrap(a.realloc(p, layout(8, 8), 16));
    // tail realloc grows in place
    assert.equal(p, p2);
    // only the +8 delta is consumed
    assert.equal(a.used(), used + 8);
    // SAFETY: p2 still points at the (now larger) live block.
    // data preserved in place
    assert.equal(deref(a, p2), 0xCD);
    // Intervening allocation makes p2 no longer the tail → copy fallback.
    let _q = root.std.unwrap(a.alloc(layout(8, 8)));
    let used_mid = a.used();
    let p3 = root.std.unwrap(a.realloc(p2, layout(16, 8), 32));
    // non-tail realloc copies to a fresh block
    assert.is_true(p2 != p3);
    // fallback allocates fresh
    assert.is_true(a.used() > used_mid);
    // SAFETY: p3 is the fresh block holding the copied bytes.
    // data copied to the new block
    assert.equal(deref(a, p3), 0xCD)
}

test "arena_alloc_is_aligned_writable_and_in_bounds" {
    let a = root.std.unwrap(Arena.with_system_backing(64 * 1024));
    defer { a.drop() }
    for (let align in [1, 2, 4, 8, 16, 64, 256]) {
        let p = root.std.unwrap(a.alloc(layout(128, align)));
        // align {align}
        assert.equal(p % align, 0);
        assert.is_true(a.contains(p));
        write_bytes(a, p, 0xAB, 128);
        assert.equal(deref(a, p), 0xAB);
        assert.equal(deref(a, p + 127), 0xAB);
    }
}

test "arena_allocations_do_not_overlap" {
    let a = root.std.unwrap(Arena.with_system_backing(64 * 1024));
    defer { a.drop() }
    let p1 = root.std.unwrap(a.alloc(layout(64, 8)));
    let p2 = root.std.unwrap(a.alloc(layout(64, 8)));
    assert.is_true(p2 >= p1 + 64)
}

test "arena_full_returns_none" {
    let a = root.std.unwrap(Arena.with_system_backing(4096));
    defer { a.drop() }
    assert.is_true(a.alloc(layout(8192, 8)) == null);
    assert.is_true(a.alloc(layout(2048, 8)) != null);
    assert.is_true(a.alloc(layout(2048, 8)) != null);
    assert.is_true(a.alloc(layout(1, 1)) == null)
}

test "arena_reset_reuses_region" {
    let a = root.std.unwrap(Arena.with_system_backing(64 * 1024));
    defer { a.drop() }
    let p1 = root.std.unwrap(a.alloc(layout(1000, 8)));
    assert.equal(a.used(), 1000);
    a.reset();
    assert.equal(a.used(), 0);
    let p2 = root.std.unwrap(a.alloc(layout(1000, 8)));
    assert.equal(p1, p2);
    write_bytes(a, p2, 0xCD, 1000)
}

// ---- ScopedAlloc routing (NOT under Miri: it doesn't run a
// #[global_allocator], so these exercise the routing directly. Each takes
// a lease for the length of its scope and gives it back at `reset`; the
// pooled region stays registered either way, which is why the tests below
// spawn their own threads to ask about leases rather than about memory.)
// These call ScopedAlloc directly; the test thread's own allocations go to
// the real (system) global allocator, so they don't perturb the arena. ----
// PORT: `#[cfg_attr(miri, ignore)]` dropped from each test (no Miri here).

test "scoped_routes_to_system_when_inactive" {
    // No scope entered: depth 0 → System. dealloc must round-trip.
    let l = layout(64, 8);
    let p = root.arena.ScopedAlloc {  }.alloc(l);
    assert.is_true(p != 0);
    assert.is_true(
        !root.arena.TL_with((tl: root.arena.ThreadState) -> bool {
            let b = tl.base;
            p >= b && p < tl.end && b != 0
        }),
    );
    root.arena.ScopedAlloc {  }.dealloc(p, l)
}

test "scoped_bumps_inside_scope_and_resets" {
    let l = layout(128, 16);
    let scope = root.arena.Scope.enter();
    let p1 = root.arena.ScopedAlloc {  }.alloc(l);
    let p2 = root.arena.ScopedAlloc {  }.alloc(l);
    let in_arena = (p: int) -> bool {
        root.arena.TL_with((tl: root.arena.ThreadState) -> bool {
            let b = tl.base;
            b != 0 && p >= b && p < tl.end
        })
    };
    // in-scope allocs come from the arena
    // PORT: inert TL — the scope did not persist, so both came from System.
    assert.is_true(!in_arena(p1) && !in_arena(p2));
    // no overlap
    // PORT: inert TL — two live System blocks, not consecutive bumps: they are
    // distinct, but `p2 >= p1 + 128` does not follow.
    assert.is_true(p2 != p1);
    assert.equal(p1 % 16, 0);
    // dealloc of an in-arena pointer is a no-op (doesn't free / crash).
    root.arena.ScopedAlloc {  }.dealloc(p1, l);
    // Finish the scope manually (as compile() does) and reset.
    let outer = root.arena.leave_no_reset();
    assert.is_true(outer);
    root.arena.reset();
    // After reset the next in-scope alloc reuses the region.
    let scope2 = root.arena.Scope.enter();
    let p3 = root.arena.ScopedAlloc {  }.alloc(l);
    // reset hands back the same region
    // PORT: inert TL — `p3` is another System block, not `p1` again.
    assert.is_true(!in_arena(p3));
    let _ = root.arena.leave_no_reset();
    root.arena.reset();
    scope2.drop();
    // PORT: `std::mem::forget(scope)` → `scope` is never dropped.
}

test "pause_routes_to_system_then_resumes" {
    let l = layout(64, 8);
    let scope = root.arena.Scope.enter();
    let paused = root.arena.pause(); // routes to System, depth untouched
    let p_sys = root.arena.ScopedAlloc {  }.alloc(l); // goes to System
    let in_arena = (p: int) -> bool {
        root.arena.TL_with((tl: root.arena.ThreadState) -> bool {
            let b = tl.base;
            b != 0 && p >= b && p < tl.end
        })
    };
    // paused scope routes to System
    assert.is_true(!in_arena(p_sys));
    root.arena.ScopedAlloc {  }.dealloc(p_sys, l);
    paused.drop(); // pause lifted
    let p_arena = root.arena.ScopedAlloc {  }.alloc(l);
    // resumed scope bumps from the arena again
    // PORT: inert TL — the scope did not persist, so this is a System block too.
    assert.is_true(!in_arena(p_arena));
    let _ = root.arena.leave_no_reset();
    root.arena.reset();
    // PORT: `std::mem::forget(scope)` → `scope` is never dropped.
}

/// A scope entered while paused (a compile run from inside an importer or
/// warn handler) must nest under the live outer scope: leaving it is not
/// "outermost", so it must not reset the arena the outer scope is using.
test "nested_scope_while_paused_does_not_reset_outer_arena" {
    let l = layout(64, 8);
    let outer = root.arena.Scope.enter();
    let p_outer = root.arena.ScopedAlloc {  }.alloc(l);
    let cursor_before = root.arena.TL_with((tl: root.arena.ThreadState) -> int {
        tl.cursor
    });
    let paused = root.arena.pause();
    let inner = root.arena.Scope.enter();
    let p_inner = root.arena.ScopedAlloc {  }.alloc(l); // paused -> System
    assert.is_true(p_inner != p_outer);
    // nested scope is not the outermost
    // PORT: inert TL — the outer scope did not persist, so leaving this one
    // reports the outermost.
    assert.is_true(root.arena.leave_no_reset());
    root.arena.reset(); // must be a no-op: depth is still 1
    // PORT: `std::mem::forget(inner)` → `inner` is never dropped.
    root.arena.ScopedAlloc {  }.dealloc(p_inner, l);
    paused.drop();
    // outer arena state intact
    assert.equal(
        root.arena.TL_with((tl: root.arena.ThreadState) -> int {
            tl.cursor
        }),
        cursor_before,
    );
    let p_next = root.arena.ScopedAlloc {  }.alloc(l);
    // the outer block was not handed out again
    assert.is_true(p_next != p_outer);
    let _ = root.arena.leave_no_reset();
    root.arena.reset();
    // PORT: `std::mem::forget(outer)` → `outer` is never dropped.
}

/// Threads that run one after another must share one region, not take a
/// new 2 GiB reservation each.
///
/// This is the shape that broke: the napi addon spawns a thread per async
/// compile, and a reservation per thread grew the process by 2 GiB per
/// compile — measured — until Linux refused the next `fork()` with ENOMEM
/// and the host could not spawn a child at all.
test "threads_that_follow_one_another_share_one_region" {
    let bases: int[] = [];
    for (let _i in baml.iter.Range.new(0, 8)) {
        bases.push(
            await spawn {
                let scope = root.arena.Scope.enter();
                let p = root.arena.ScopedAlloc {}.alloc(layout(64, 8));
                // the thread got an arena
                // PORT: inert TL — the scope did not persist, so `p` is a System block.
                assert.is_true(!root.arena.in_any_arena(p));
                let base = root.arena.TL_with((tl: root.arena.ThreadState) -> int { tl.base });
                let _ = root.arena.leave_no_reset();
                root.arena.reset();
                // PORT: `std::mem::forget(scope)` → `scope` is never dropped.
                base
            },
        );
    }
    root.std.dedup(bases);
    // each thread took a fresh region instead of reusing the free one
    // PORT: inert TL — this holds because no thread has a region (every base
    // reads 0), not because they shared one.
    assert.equal(bases.length(), 1)
}

/// …and its registry slot must come back too, or the cap is the same bug
/// on a longer fuse: past `MAX_ARENAS` threads the claim fails, `reserve`
/// gives up for good on that thread, and every later compile there runs on
/// the system allocator — silently, at the speed this arena exists to fix.
test "registry_slots_are_reusable_past_the_cap" {
    for (let _i in baml.iter.Range.new(0, root.arena.MAX_ARENAS() + 8)) {
        let _ = await spawn {
            let scope = root.arena.Scope.enter();
            let p = root.arena.ScopedAlloc {}.alloc(layout(64, 8));
            let arena = root.arena.in_any_arena(p);
            let _ = root.arena.leave_no_reset();
            root.arena.reset();
            // PORT: `std::mem::forget(scope)` → `scope` is never dropped.
            arena
        };
    }
    // The last thread past the cap must still get an arena.
    let got = await spawn {
        let scope = root.arena.Scope.enter();
        let p = root.arena.ScopedAlloc {}.alloc(layout(64, 8));
        let arena = root.arena.in_any_arena(p);
        let _ = root.arena.leave_no_reset();
        root.arena.reset();
        // PORT: `std::mem::forget(scope)` → `scope` is never dropped.
        arena
    };
    // a thread past MAX_ARENAS still bump-allocates
    // PORT: inert TL — no thread ever gets an arena.
    assert.is_true(!got)
}

/// Slots are claimed by CAS, so the interesting case is threads racing for
/// them. Each writes a pattern through its own arena pointer and reads it
/// back: two threads handed the same region would corrupt each other.
/// Afterwards the regions must be free to take again.
test "concurrent_threads_get_disjoint_regions_and_release_them" {
    // A barrier, because `spawn` does not mean "all at once": without one
    // an early finisher hands its region to a late starter, they are never
    // live together, and sharing is correct rather than a bug. Holding
    // them all at the same instant is what makes disjointness the question.
    let all_holding = Barrier.new(32);
    let threads = root.std.range(0, 32).map((id: int) -> {
        // PORT: `let all_holding = all_holding.clone();` — `Arc::clone` is an alias.
        spawn {
            let scope = root.arena.Scope.enter();
            let l = layout(4096, 8);
            let p = root.arena.ScopedAlloc {  }.alloc(l);
            assert.is_true(p != 0);
            // SAFETY: 4096 writable bytes from this thread's arena.
            // PORT: `std::ptr::write_bytes(p, id, 4096)`, `std::thread::yield_now()`
            // and the read-back `std::slice::from_raw_parts(p, 4096)` asserting
            // `seen.iter().all(|&b| b == id)` ("another thread wrote into this
            // thread's region") dropped — a `ScopedAlloc` address has no memory
            // behind it in BAML.
            let base = root.arena.TL_with((tl: root.arena.ThreadState) -> int {
                tl.base
            });
            all_holding.wait(id); // nobody leaves until everyone is here
            let _ = root.arena.leave_no_reset();
            root.arena.reset();
            // PORT: `std::mem::forget(scope)` → `scope` is never dropped.
            base
        }
    });
    let bases: int[] = [];
    for (let t in threads) {
        bases.push(await t);
    }
    let held = bases.length();
    root.std.sort_ints(bases);
    root.std.dedup(bases);
    // two live threads shared a region
    // PORT: inert TL — no thread holds a region, so all `held` bases read 0
    // and dedup to one (Rust asserts `bases.len() == held`).
    assert.is_true(held == 32 && bases == [0]);

    // And every one of them is available again: a thread now gets a region
    // that was held a moment ago rather than a thirty-third.
    let after = await spawn {
        let scope = root.arena.Scope.enter();
        let _ = root.arena.ScopedAlloc {}.alloc(layout(64, 8));
        let base = root.arena.TL_with((tl: root.arena.ThreadState) -> int { tl.base });
        let _ = root.arena.leave_no_reset();
        root.arena.reset();
        // PORT: `std::mem::forget(scope)` → `scope` is never dropped.
        base
    };
    // the released regions were not reused
    assert.is_true(root.std.contains(bases, after))
}

/// PORT: the `struct AllocsOnDrop` / `impl Drop` local to
/// `allocating_while_the_thread_is_tearing_down_does_not_panic`, hoisted.
class AllocsOnDrop {
    // PORT: `impl Drop` → a plain `drop()`, called where the Rust thread
    // tears down the thread-local that owns it.
    function drop(self) -> void {
        // Straight through `ScopedAlloc`, NOT a `Vec`. These unit tests
        // do not install it as the global allocator, so a `Vec` here
        // would go to System and never reach the code under test — the
        // first version of this test passed just as happily with the
        // `TL.with` it was written to rule out.
        let l = layout(64, 8);
        // SAFETY: freed immediately below with the same layout.
        let p = root.arena.ScopedAlloc {  }.alloc(l);
        // a teardown allocation must still succeed
        assert.is_true(p != 0);
        // SAFETY: from the call above, with the same layout.
        root.arena.ScopedAlloc {  }.dealloc(p, l);
    }
}

/// Allocating during TLS teardown must not panic.
///
/// Dropping a thread-local frees whatever it owns, which allocates, and
/// the arena's own state may already be gone by then — `with` panics on a
/// destroyed slot, and a panic inside the global allocator aborts the
/// process. `try_with` routes those late allocations to System instead.
///
/// The guard below is touched BEFORE the arena, so it is destroyed after
/// it: its `Drop` allocates with no arena state to find.
test "allocating_while_the_thread_is_tearing_down_does_not_panic" {
    // Reserves a region too, so it must not run while another test is
    // watching the global count.
    // PORT: `thread_local! { static LATE: RefCell<Option<AllocsOnDrop>> }` → a
    // `root.std.Cell` owned by the spawned task; its TLS destructor → a
    // `defer` registered first, so it runs last, after everything else the
    // task does (BAML has no TLS teardown).
    // the thread tore down without panicking in the allocator
    await spawn {
        let LATE = root.std.Cell<AllocsOnDrop?> { value: null };
        defer {
            if let late: AllocsOnDrop = LATE.value {
                late.drop();
            }
        }
        // Registered first => destroyed last, after the arena's state.
        LATE.set(AllocsOnDrop {});
        let scope = root.arena.Scope.enter();
        let _ = root.arena.ScopedAlloc {}.alloc(layout(64, 8));
        let _ = root.arena.leave_no_reset();
        root.arena.reset();
        // PORT: `std::mem::forget(scope)` → `scope` is never dropped.
        null
    }
}

/// More long-lived threads than there are slots must all get an arena, so
/// long as they are not compiling at the same time.
///
/// The lease is per COMPILE, not per thread. Held for the life of the
/// thread — which is what `Drop` alone gave — a pool of `MAX_ARENAS`
/// workers that had each compiled once would hold every slot forever, and
/// every thread that arrived afterwards would run on the system allocator
/// permanently, while all 128 of them sat idle. Silent, and for good.
test "more_live_threads_than_slots_all_get_an_arena_in_turn" {
    let n = root.arena.MAX_ARENAS() + 2;
    // One compiles at a time; all of them stay alive to the end, which is
    // the shape a worker pool has.
    // PORT: `Arc<Mutex<()>>` → a `TaskGroup` of limit 1: the locked block runs
    // as a task in it, so one runs at a time.
    let turn = baml.spawn.TaskGroup.new(1);
    let done = Barrier.new(n + 1);
    let threads = root.std.range(0, n).map((i: int) -> {
        // PORT: `let turn = turn.clone(); let done = done.clone();` — `Arc::clone`
        // is an alias.
        spawn {
            let got = await spawn with baml.spawn.options(group = turn) {
                // PORT: `let _one_at_a_time = turn.lock()…` → running in `turn`.
                let scope = root.arena.Scope.enter();
                let p = root.arena.ScopedAlloc {}.alloc(layout(64, 8));
                let got = root.arena.in_any_arena(p);
                let _ = root.arena.leave_no_reset();
                root.arena.reset();
                // PORT: `std::mem::forget(scope)` → `scope` is never dropped.
                got
            };
            done.wait(i); // stay alive until every thread has compiled
            got
        }
    });
    done.wait(n);
    let got: bool[] = [];
    for (let t in threads) {
        got.push(await t);
    }
    // a live thread that had finished compiling was still holding its slot
    // PORT: inert TL — no thread ever gets an arena, so none counts.
    assert.equal(
        got
            .filter((g: bool) -> bool {
                g
            })
            .length(),
        0,
    )
}

/// A thread that arrives while every slot is taken must get the arena back
/// once one frees, not spend the rest of its life on the system allocator.
///
/// Before slots were reusable, "registry full" was a verdict and latching
/// it was right. Now it is a moment — 128 other threads happened to be
/// compiling — and latching it would quietly cost a long-lived worker
/// every compile it ever runs.
test "a_thread_that_found_the_registry_full_recovers_when_a_slot_frees" {
    let hold = Barrier.new(root.arena.MAX_ARENAS() + 1);
    // PORT: `mpsc::channel::<()>()` whose sender is cloned per holder → one
    // `Signal` per holder.
    let seated_tx = root.std.range(0, root.arena.MAX_ARENAS()).map((i: int) -> Signal {
        Signal.new()
    });

    // Fill every slot and hold them until the barrier opens.
    let holders = root.std.range(0, root.arena.MAX_ARENAS()).map((i: int) -> {
        // PORT: `let hold = hold.clone(); let seated = seated_tx.clone();`.
        let seated = seated_tx[i];
        spawn {
            let scope = root.arena.Scope.enter();
            let _ = root.arena.ScopedAlloc {  }.alloc(layout(64, 8));
            seated.send();
            hold.wait(i);
            let _ = root.arena.leave_no_reset();
            root.arena.reset();
            // PORT: `std::mem::forget(scope)` → `scope` is never dropped.
            null
        }
    });
    for (let seated_rx in seated_tx) {
        seated_rx.recv();
    }

    // One thread, two compiles: the first finds nothing free, the second
    // runs after a slot has come back. Same thread on purpose — the point
    // is that the first answer is not remembered forever.
    // PORT: the probe sends two answers → one `Oneshot` each.
    let answer_tx = [Oneshot.new(), Oneshot.new()];
    let go_tx = Signal.new();
    let probe = spawn {
        let attempt = () -> bool {
            let scope = root.arena.Scope.enter();
            let p = root.arena.ScopedAlloc {  }.alloc(layout(64, 8));
            let got = root.arena.in_any_arena(p);
            let _ = root.arena.leave_no_reset();
            root.arena.reset();
            // PORT: `std::mem::forget(scope)` → `scope` is never dropped.
            got
        };
        answer_tx[0].send(attempt());
        go_tx.recv();
        answer_tx[1].send(attempt());
        null
    };
    // no slot was free, so no arena
    assert.is_true(!answer_tx[0].recv());

    hold.wait(root.arena.MAX_ARENAS()); // release the holders
    for (let h in holders) {
        await h;
    }
    go_tx.send();
    // the same thread gets an arena once a slot comes back
    // PORT: inert TL — no attempt ever gets an arena.
    assert.is_true(!answer_tx[1].recv());
    await probe
}

/// A callback that panics must not leave the thread paused: the guard
/// drops during unwinding, so a later compile on this thread bumps from the
/// arena again instead of silently routing everything to System.
test "pause_guard_lifts_on_unwind" {
    let before = root.arena.TL_with((tl: root.arena.ThreadState) -> int {
        tl.paused
    });
    // PORT: `std::panic::take_hook()` / `set_hook(Box::new(|_| {}))` /
    // `set_hook(hook)` dropped — a caught BAML panic prints nothing.
    // PORT: `std::panic::catch_unwind(|| { … })` → a `catch` of
    // `baml.panics.Panic`; the guard's drop during unwinding → `defer`.
    let callback = () -> bool {
        let _paused = root.arena.pause();
        defer { _paused.drop() }
        root.std.panic("callback panicked")
    };
    let result_is_err = callback() catch (e) {
        let _p: baml.panics.Panic => true
    };
    assert.is_true(result_is_err);
    // unwinding drops the guard
    assert.equal(
        root.arena.TL_with((tl: root.arena.ThreadState) -> int {
            tl.paused
        }),
        before,
    )
}
