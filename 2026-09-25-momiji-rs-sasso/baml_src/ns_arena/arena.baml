// Ported from sasso `src/arena.rs` (namespace `root.arena`).
//
// The scoped bump allocator (perf #5) — the library's one `unsafe` module.
//
// A single `compile()` is a flood of short-lived allocations freed all at once,
// so within a compile scope every allocation is a pointer bump from a
// per-thread arena, and the whole arena is reset when the scope ends. Outside a
// scope, allocations forward to the system allocator. Because a compile is
// `!Send` (the evaluator uses `Rc`), each thread keeps its own arena, so the
// state is thread-local and single-threaded (`Cell`, not atomics).
//
// ## Safety strategy
//
// - Bump arithmetic is the pure [`bump_compute`] (exhaustively unit-tested:
//   alignment / boundary / overflow, no `unsafe`).
// - Pointers are derived via `base.add(..)` (never `addr as *mut u8`) so they
//   keep provenance — required for Miri's Stacked/Tree-Borrows checks.
// - The thread-local [`ThreadState`] gives its region and registry slot back
//   when the thread ends. It used to be POD so that the first TLS access
//   registered no destructor — but leaving the 2 GiB reservation behind cost
//   an embedder with short-lived threads one per compile, until the host
//   could no longer `fork()`. The destructor frees rather than allocates, and
//   `alloc`/`realloc` reach the state through `try_with` so allocations made
//   while other thread-locals are being dropped route to System instead of
//   panicking on a destroyed slot.
// - [`Arena`] (test-only) is a standalone, `Drop`-ing twin of the same bump +
//   provenance logic, run under `cargo miri test` for UB detection without
//   leaking (Miri does not execute `#[global_allocator]`, so the live
//   [`ScopedAlloc`] path is covered by AddressSanitizer + the full sass-spec
//   suite run under the arena instead).

// PORT: `#![allow(unsafe_code)]` / `#![allow(dead_code)]` dropped ("Some scope
// primitives are wired up in later steps (Importer boundary).").
//
// PORT: how this module maps onto BAML. BAML is garbage-collected: there is no
// global allocator to install and no raw memory, so nothing here ever touches
// real memory and `ScopedAlloc` is never called by the runtime. The logic is
// ported line by line over integer "addresses" (`*mut u8` / `usize` → `int`,
// null → `0`), with local stand-ins for `std::alloc::Layout` and `System`
// (below). BAML also has no globals or thread-locals (PORTING_GUIDE.md §11), and
// the entry points (`Scope::enter`, `leave_no_reset`, `reset`, `pause`) take no
// context object to carry the state in; so the statics `REGIONS`,
// `REGION_SLOTS`, `ARENA_CONFIG` and the thread-local `TL` are zero-arg
// functions that materialize their initial value on every access. The
// bookkeeping is therefore inert — every scope looks outermost, every
// allocation routes to the modeled System — which is unobservable because
// BAML's own allocator is the GC either way.

// PORT: `std::alloc::Layout` — a local stand-in (size + power-of-two
// alignment). Rust's `layout.size()` / `layout.align()` read the fields.
class Layout {
    size: int,
    align: int,

    /// `Layout::from_size_align`: `None` (Rust's `Err(LayoutError)`) unless
    /// `align` is a power of two and `size` rounded up to `align` stays within
    /// `isize::MAX` (BAML's `int` range here).
    function from_size_align(size: int, align: int) -> Layout? {
        if (align <= 0 || (align & (align - 1)) != 0) {
            return null;
        }
        if (size < 0 || size > root.std.INT_MAX() - (align - 1)) {
            return null;
        }
        Layout { size: size, align: align }
    }

    /// `Layout::from_size_align_unchecked`.
    function from_size_align_unchecked(size: int, align: int) -> Layout {
        Layout { size: size, align: align }
    }
}

// PORT: `std::alloc::System` — a local stand-in. There is no raw memory in
// BAML, so the system allocator is modeled: `alloc` hands out an opaque,
// non-null address aligned to `layout.align` (drawn at random from a range far
// larger than any modeled arena, as a real allocator's addresses are
// unpredictable), and `dealloc` has nothing to release. Nothing dereferences
// these addresses.
class System {
    function alloc(layout: Layout) -> int {
        let slot = baml.Int.random(1, 1 << 40) catch (e) {
            _ => root.std.unreachable()
        };
        slot * layout.align
    }

    function dealloc(ptr: int, layout: Layout) -> void {}
}

// =========================================================================
// Process-global arena-region registry.
//
// `dealloc` only needs to answer "is this pointer inside SOME thread's arena
// region?" — an in-arena free is a no-op (reclaimed wholesale on scope reset),
// anything else forwards to System. A global table of `[base, end)` ranges
// answers that with two atomic loads per registered region and no thread-local
// access. This halves the macOS `_tlv_get_addr` dynamic-TLS traffic, which
// `alloc` (which genuinely needs the per-thread cursor) still pays.
//
// What a slot holds and what it lends are different things. `base`/`end` are
// WRITE-ONCE: a slot's region is created the first time anyone uses that slot
// and lives for the rest of the process. What a thread takes and gives back is
// the RIGHT to bump inside it — `taken`, claimed by CAS at the start of a
// compile and released when the outermost scope ends, not when the thread
// does. `REGION_SLOTS` bounds the scan and never shrinks.
//
// Write-once is the whole safety argument, and it is why the region is pooled
// rather than freed. Freeing it would let a slot point at one range and then
// another, and `in_any_arena` reads `base` and `end` separately: a reader can
// take `base` from the old region, lose the slot to a new owner, and take
// `end` from the new one. That pair describes a range neither region ever had,
// and a System pointer inside it would be called arena-owned — where freeing
// is a no-op, so it would leak. Pooling removes the question instead of
// synchronising around it; no epoch or reader guard is needed because nothing
// a reader can observe ever changes.
//
// Memory ordering: `base` is published with Release and read with ACQUIRE,
// which is what makes the preceding `end` store visible. Relaxed on both would
// let a weakly ordered target (aarch64, which this ships on) hand back a
// freshly published `base` with the `end` that preceded it — zero — and call a
// live arena pointer a System one. Everything after the acquire is relaxed:
// a nonzero `base` from a write-once slot is its final value, so containment
// is real. A false "not in arena" (a stale 0) could only misroute a pointer in
// the unobserved region, and a thread always sees its own publication, while
// any pointer legitimately handed to another thread rides that channel's
// happens-before edge. A thread with no such edge cannot hold the pointer.
// (The old per-thread check misclassified cross-thread frees of arena
// pointers as System allocations — the registry handles them correctly.)
// =========================================================================
// PORT: atomics (`AtomicPtr`/`AtomicUsize`/`AtomicBool`) → plain fields and
// `root.std.Cell<int>`; the `Ordering` arguments have no BAML counterpart (a
// BAML program shares no memory between threads) and are dropped.

/// Max arena regions, and so the most compiles that can bump at once.
///
/// Regions are pooled and leased for the length of one compile, so this caps
/// CONCURRENT compiles — not threads, and not history. A thread that finishes
/// compiling gives its lease back while staying alive, so a worker pool larger
/// than this is fine as long as they are not all inside `compile()` together.
/// A thread arriving when every region is leased runs without an arena and
/// tries again on its next compile.
function MAX_ARENAS() -> int {
    128
}

/// A `[base, end)` region plus whether a thread currently holds it.
///
/// `base` and `end` are written ONCE, the first time a slot is used, and never
/// again — the region outlives every thread that borrows it. That is what lets
/// `in_any_arena` read the pair without synchronising against reuse: there is
/// no reuse of the *range* to synchronise against, only of the right to bump
/// within it. A design that freed the region and re-pointed the slot would
/// have to make the two loads atomic with respect to each other, since a
/// reader can load `base`, lose the slot to a new owner, and then load that
/// owner's `end` — pairing a stale base with a fresh end and classifying an
/// unrelated System pointer as arena-owned, where freeing is a no-op and the
/// allocation would leak.
class Region {
    /// The region's start, kept as a pointer rather than an address so that a
    /// thread leasing a slot another thread created gets the pointer
    /// `System.alloc` returned, provenance and all. Storing it as a `usize`
    /// and casting back would be the `addr as *mut u8` this module's safety
    /// strategy rules out: every allocation handed out is derived from this
    /// with `add`, so a base without provenance makes each of them undefined
    /// under strict provenance, and Miri's Stacked/Tree-Borrows would say so.
    base: int,
    end: int,
    /// Held by a live thread. Readers ignore this: a region is a region
    /// whether or not anyone is bumping in it right now.
    taken: bool,
}

// repeated-element array init (MSRV < 1.79)
function ZERO_REGION() -> Region {
    Region { base: 0, end: 0, taken: false }
}

/// High-water mark: slots `0..REGION_SLOTS` have been used at some point and
/// are what [`in_any_arena`] scans. It never shrinks — a slot given back is
/// skipped by its zero `base`, not by moving this — so the scan bound stays
/// monotonic while the slots beneath it are recycled.
// PORT: mutable static — BAML has no globals (see the module note): a fresh
// `AtomicUsize::new(0)` per access.
function REGION_SLOTS() -> root.std.Cell<int> {
    root.std.Cell<int> { value: 0 }
}

// PORT: mutable static — BAML has no globals (see the module note): a fresh
// `[ZERO_REGION; MAX_ARENAS]` per access (one distinct `Region` per slot).
function REGIONS() -> Region[] {
    baml.Array.generate(MAX_ARENAS(), (i: int) -> Region {
        ZERO_REGION()
    })
}

/// PORT: `region.taken.compare_exchange(current, new, _, _).is_ok()` — BAML
/// has no atomics; a check-and-set (nothing else can run in between).
function taken_compare_exchange(region: Region, current: bool, new: bool) -> bool {
    if (region.taken != current) {
        return false;
    }
    region.taken = new;
    true
}

/// PORT: `AtomicUsize::fetch_max(v, _)` on a `Cell` — returns the previous value.
function cell_fetch_max(cell: root.std.Cell<int>, v: int) -> int {
    let prev = cell.get();
    cell.set(root.std.imax(prev, v));
    prev
}

/// Borrow a free slot. `None` when every slot is held right now — which is a
/// moment, not a verdict: the holders are compiling and will give theirs back.
function claim_slot(preferred: int) -> int? {
    // The slot this thread held for its previous compile, if it is still free:
    // the region is then already warm in cache and TLB. Leases are given back
    // between compiles, so without this a busy thread would wander the array.
    if (preferred != NO_SLOT() && taken_compare_exchange(REGIONS()[preferred], false, true)) {
        return preferred;
    }
    let regions = REGIONS();
    let idx = 0;
    while (idx < regions.length()) {
        let region = regions[idx];
        if (taken_compare_exchange(region, false, true)) {
            // Scan bound for `in_any_arena`. Raised on claim rather than on
            // publication; a slot whose region does not exist yet reads
            // `base == 0` and is skipped.
            let _ = cell_fetch_max(REGION_SLOTS(), idx + 1);
            return idx;
        }
        idx += 1;
    }
    null
}

/// Give the slot back. The REGION stays registered — see [`Region`]. Nothing
/// else may be written here: the moment `taken` reads false another thread can
/// take the slot, and this one has no business touching it afterwards.
function release_slot(idx: int) -> void {
    REGIONS()[idx].taken = false;
}

/// Whether `p` lies inside any registered arena region.
///
/// This reads `base` and `end` and ignores `taken` entirely: the question is
/// whether the ADDRESS belongs to an arena, not whether anyone is bumping in
/// it at this instant. A region that no thread currently leases still holds
/// pointers handed out moments ago, and they must keep routing here.
///
/// There is exactly one transition to synchronise with — the first time a
/// slot is ever used, when its region is created. `end` is written, then
/// `base` with `Release`, and `base` gates every reader; a slot whose region
/// does not exist yet reads `base == 0` and is skipped. After that neither
/// value ever changes again, which is what makes the two separate loads safe.
/// Leasing writes only `taken`, which nothing here reads.
///
/// The ACQUIRE is what makes that one transition hold. `base` is published
/// with `Release`, and release pairs with acquire or with nothing at all: read
/// relaxed there is no happens-before edge, and a weakly ordered target —
/// aarch64, which this ships on — may hand back a freshly published `base`
/// alongside the `end` that preceded it, which is zero. A live arena pointer
/// then compares outside its own region, `dealloc` calls it a System pointer,
/// and frees something System never allocated. The scan is short — the
/// high-water mark is how many slots have ever been leased, not `MAX_ARENAS`
/// — so the acquire costs little and buys the guarantee this comment makes.
function in_any_arena(p: int) -> bool {
    let n = root.std.imin(REGION_SLOTS().get(), MAX_ARENAS());
    for (let r in REGIONS().slice(0, n)) {
        // Pointer to address for the comparison only. That direction is free:
        // it is deriving a pointer FROM an address that loses provenance, and
        // nothing here is dereferenced.
        let base = r.base;
        if (base != 0 && p >= base && p < r.end) {
            return true;
        }
    }
    false
}

/// Pure bump arithmetic over absolute addresses: align `cur` up to `align`, add
/// `size`, and check the result fits at or below `end` (exclusive). Returns
/// `(aligned_start, new_cursor)` or `None` on overflow / no fit. Touches no
/// memory. `align` must be a power of two (guaranteed by [`Layout`]).
function bump_compute(cur: int, align: int, size: int, end: int) -> root.std.Tuple2<int, int>? {
    let sum = checked_add(cur, align - 1);
    if (sum == null) {
        return null;
    }
    // PORT: `!(align - 1)` — for a power-of-two `align` that mask is `-align`
    // in two's complement (BAML has no bitwise-not operator).
    let aligned = sum & -align;
    let next = checked_add(aligned, size);
    if (next == null) {
        return null;
    }
    if (next <= end) {
        root.std.Tuple2<int, int> { _0: aligned, _1: next }
    } else {
        null
    }
}

/// PORT: `usize::checked_add` — `None` past `usize::MAX` (BAML's `INT_MAX`,
/// since `int` is 63-bit and panics on overflow instead of wrapping).
function checked_add(a: int, b: int) -> int? {
    if (a > root.std.INT_MAX() - b) {
        return null;
    }
    a + b
}

// ── Arena reservation size ──────────────────────────────────────────────
//
// The region is reserved up front on first use. On a 64-bit host this is
// virtual — physical pages commit lazily on first touch, so a huge unused
// reservation costs ~nothing, and the size is a fixed 2 GiB. On wasm32 there
// is no lazy commit (`memory.grow` zero-fills and commits every page
// immediately) and the address space is only 4 GiB, so the reservation must
// be a realistic peak working-set bound: a single large-stylesheet compile
// peaks around 25 MiB, and the region grows the wasm heap ONCE on the first
// compile and is then reused (reset, not freed) — a fixed footprint, not
// per-compile growth. Anything that overflows the region spills to the system
// allocator with no loss of correctness.
//
// The wasm size has two layers of developer control:
//   • compile-time default — `SASSO_WASM_ARENA_MB` at build time (default 32),
//   • runtime override — [`set_arena_bytes`] before the first compile (0
//     disables the arena entirely: every allocation forwards to System).
// Native ignores both and always uses its 2 GiB virtual reservation.

// PORT: cfg(target_arch = "wasm32") items not ported: `const fn parse_mb`,
// `const WASM_DEFAULT_ARENA_SIZE`, and the wasm `effective_arena_size`.

/// Runtime override of the wasm arena size: `0` = unset (use the compile-time
/// default), `usize::MAX` = explicitly disabled, anything else = that many
/// bytes. Read only on wasm; native's [`effective_arena_size`] ignores it.
// PORT: mutable static — BAML has no globals (see the module note): a fresh
// `AtomicUsize::new(0)` per access.
function ARENA_CONFIG() -> root.std.Cell<int> {
    root.std.Cell<int> { value: 0 }
}

/// Override the wasm arena reservation size, in **bytes**. Must be called
/// BEFORE the first `compile()` — the region is reserved on first use and then
/// fixed, so a later call has no effect. `0` disables the arena entirely
/// (every allocation forwards to the system allocator: lower memory, slower).
/// No effect on native targets (they always use the 2 GiB virtual reservation).
function set_arena_bytes(bytes: int) -> void {
    // PORT: `usize::MAX` → `root.std.INT_MAX()`.
    ARENA_CONFIG().set(
        if (bytes == 0) {
            root.std.INT_MAX()
        } else {
            bytes
        },
    );
}

// PORT: the `#[cfg(not(target_arch = "wasm32"))]` variant.
function effective_arena_size() -> int {
    2 * 1024 * 1024 * 1024 // 2 GiB virtual; the runtime override is wasm-only
}

/// Per-thread bump state. Its `Drop` returns the region and the registry slot
/// when the thread ends — see the module-level safety note for why the
/// allocator reaches this through `try_with`.
// PORT: `Cell<…>` fields → plain fields (the struct is only ever reached by
// reference); `Cell<*mut u8>` → `int` address, null → `0`.
class ThreadState {
    base: int,
    end: int,
    cursor: int,
    /// Scope nesting depth. `0` = inactive: allocations pass through to System.
    depth: int,
    /// [`pause`] nesting count. While `> 0`, allocations pass through to
    /// System even inside a scope, without touching `depth` — so a compile
    /// started from within a paused callback nests as usual and cannot mistake
    /// itself for the outermost scope and reset the arena under its caller.
    paused: int,
    /// Set once if [`Self::reserve`] fails for a reason that cannot change —
    /// the arena is disabled, or the 2 GiB reservation itself failed. The
    /// alloc path then forwards straight to System without retrying the
    /// `#[cold]` reservation on every allocation.
    reserve_failed: bool,
    /// Set when every registry slot was busy. Separate from `reserve_failed`
    /// because, now that slots come back, "full" is a moment rather than a
    /// verdict: a thread that started while 128 others held slots would
    /// otherwise run on the system allocator for the rest of its life. Cleared
    /// when a scope opens, so each compile gets one fresh attempt — and not
    /// per allocation, which would mean a 2 GiB reserve-and-free apiece.
    registry_full: bool,
    /// Registry slot this thread is currently leasing. `NO_SLOT` between
    /// compiles — the lease is given back when the outermost scope ends, so
    /// the cap is on threads compiling AT ONCE rather than on threads that
    /// have ever compiled. Holding it for the life of the thread would leave
    /// a pool of 128 long-lived workers permanently full, and everyone who
    /// arrived later on the system allocator, silently and for good.
    slot: int,
    /// The slot leased for the previous compile, tried first next time so a
    /// busy thread keeps the same warm region.
    last_slot: int,

    function new() -> ThreadState {
        ThreadState {
            base: 0,
            end: 0,
            cursor: 0,
            depth: 0,
            paused: 0,
            reserve_failed: false,
            registry_full: false,
            slot: NO_SLOT(),
            last_slot: NO_SLOT(),
        }
    }

    /// Take a pooled region for this thread, creating it if this slot has
    /// never been used. The caller forwards the request to the system
    /// allocator on anything but [`Reserved::Yes`] — and the two failures
    /// differ: [`Reserved::Never`] is disabled or out of memory and is
    /// remembered, [`Reserved::NotNow`] is every slot busy and is retried when
    /// the next scope opens.
    function reserve(self) -> Reserved {
        let size = effective_arena_size();
        if (size == 0) {
            return Reserved.Never; // disabled: run on the system allocator
        }
        let slot = claim_slot(self.last_slot);
        if (slot == null) {
            return Reserved.NotNow; // every slot held; a holder will finish
        }
        let region = REGIONS()[slot];
        let base = region.base;
        if (base == 0) {
            // First thread ever to hold this slot: give it a region, once.
            // Every later holder bumps in the same one.
            let layout = Layout.from_size_align(size, 4096);
            if (layout == null) {
                release_slot(slot);
                return Reserved.Never;
            }
            // SAFETY: non-zero size, 4096 is a valid power-of-two alignment.
            let p = System.alloc(layout);
            if (p == 0) {
                release_slot(slot);
                return Reserved.Never;
            }
            // `end` before `base`: `base` is what readers gate on, so writing
            // it last means a reader sees the whole region or skips the slot.
            region.end = p + size;
            region.base = p;
            base = p;
        }
        self.slot = slot;
        self.base = base;
        self.end = region.end;
        self.cursor = base;
        Reserved.Yes
    }

    // PORT: `impl Drop` — kept as a plain method (the thread-local it tears
    // down is inert here; see the module note).
    /// Give back a lease the thread still holds.
    ///
    /// Normally there is none: [`reset`] hands it back when the compile ends.
    /// This catches the paths that do not get there — a thread unwinding out
    /// of a compile, or one that reserved and then died.
    ///
    /// The region itself stays. It is pooled, and the next thread to lease
    /// this slot bumps in the same memory. What must not happen is what
    /// happened before any of this: a reservation per thread that ever
    /// compiled, 2 GiB of address space each, until an embedder with
    /// short-lived threads (the napi addon spawns one per async compile)
    /// leaves the host unable to `fork()`.
    ///
    /// This runs during TLS teardown, which is why `alloc` reaches the state
    /// through `try_with`: allocations happen while other thread-locals are
    /// being dropped, and after this one is gone they must route to System
    /// rather than panic on a destroyed TLS slot.
    function drop(self) -> void {
        let slot = self.slot;
        if (slot == NO_SLOT()) {
            return;
        }
        self.slot = NO_SLOT();
        self.base = 0;
        self.end = 0;
        self.cursor = 0;
        release_slot(slot);
    }
}

/// No registry slot held.
function NO_SLOT() -> int {
    // PORT: `usize::MAX` → `root.std.INT_MAX()`.
    root.std.INT_MAX()
}

/// Why a reservation did or did not happen — the two failures differ in how
/// long they last.
enum Reserved {
    Yes,
    /// Disabled or out of memory: nothing about a later attempt would differ.
    Never,
    /// Every registry slot was taken. Slots come back, so this one can.
    NotNow,
}

// PORT: `thread_local! { static TL: ThreadState = const { ThreadState::new() }; }`
// — BAML has no thread-locals or globals (see the module note): `TL()`
// materializes a fresh `ThreadState::new()` per access, and `TL.with` /
// `TL.try_with` are the helpers below.
//
// `const {}` init: no lazy allocation, so reaching this from inside the
// global allocator cannot re-enter it. The destructor (above) means the
// state CAN be gone late in thread teardown, so the allocator uses
// `try_with` and falls back to System when it is.
function TL() -> ThreadState {
    ThreadState.new()
}

/// PORT: `TL.with(f)`.
function TL_with<R>(f: (ThreadState) -> R throws unknown) -> R {
    f(TL())
}

/// PORT: `TL.try_with(f)` — `Err(AccessError)` → `null`. There is no TLS
/// teardown in BAML, so the state is always reachable.
function TL_try_with<R>(f: (ThreadState) -> R throws unknown) -> R? {
    f(TL())
}

/// A scoped bump global allocator. Inside a `compile()` scope it bump-allocates
/// from a per-thread arena that is reset when the scope ends; outside any scope
/// it forwards to the system allocator. Install it in a binary or wasm wrapper:
///
/// ```ignore
/// #[global_allocator]
/// static ALLOC: sasso::ScopedAlloc = sasso::ScopedAlloc;
/// ```
///
/// It is safe to install even if `compile` is never called: with no active scope
/// every request goes straight to the system allocator.
class ScopedAlloc {
    // PORT: `unsafe impl GlobalAlloc` — methods kept as plain methods (BAML has
    // no allocator hook to install them in; see the module note).
    function alloc(self, layout: Layout) -> int {
        // `try_with`, not `with`: freeing other thread-locals during teardown
        // allocates, and by then this one may already be dropped. `with` would
        // panic there — inside the global allocator, which aborts the process.
        // No state means no scope, which means System, which is correct.
        let p = TL_try_with((tl: ThreadState) -> int {
            if (tl.depth == 0 || tl.paused > 0) {
                // SAFETY: forwarding an unchanged layout to the system allocator.
                return System.alloc(layout);
            }
            if (tl.base == 0) {
                // Take a region once. A permanent failure (disabled, out of
                // memory) is remembered for the life of the thread; a busy
                // registry is remembered only until the next scope opens, so
                // this does not re-run the cold path per allocation either
                // way.
                if (tl.reserve_failed || tl.registry_full) {
                    return System.alloc(layout);
                }
                match (tl.reserve()) {
                    Reserved.Yes => {},
                    Reserved.Never => {
                        tl.reserve_failed = true;
                        return System.alloc(layout);
                    },
                    Reserved.NotNow => {
                        tl.registry_full = true;
                        return System.alloc(layout);
                    },
                }
            }
            match (bump_compute(tl.cursor, layout.align, layout.size, tl.end)) {
                root.std.Tuple2<int, int> { _0: let aligned, _1: let next } => {
                    tl.cursor = next;
                    let base = tl.base;
                    // SAFETY: bump_compute guarantees base <= aligned and
                    // aligned + size <= base + size, so the offset is in-bounds.
                    base + (aligned - base)
                },
                // Arena exhausted → fall back to the system allocator.
                // SAFETY: forwarding an unchanged layout to the system allocator.
                null => System.alloc(layout),
            }
        });
        if (p == null) {
            // SAFETY: forwarding an unchanged layout to the system allocator.
            return System.alloc(layout);
        }
        p
    }

    function dealloc(self, ptr: int, layout: Layout) -> void {
        // The global region registry answers "arena or System?" without a
        // thread-local lookup (see its module section above).
        if (!in_any_arena(ptr)) {
            // SAFETY: not from any arena, so it came from the system
            // allocator with this same layout.
            System.dealloc(ptr, layout);
        }
        // in-arena: no-op (reclaimed wholesale on scope reset)
    }

    function realloc(self, ptr: int, layout: Layout, new_size: int) -> int {
        // Bump-arena fast path: if `ptr` is the MOST RECENT allocation in this
        // thread's arena (its end sits exactly at the cursor), resize it in
        // place by moving the cursor — no copy, and no dead intermediate buffer
        // left behind. A naive realloc (alloc-new + copy + no-op dealloc) is
        // what makes a growing `Vec` leak arena space on every doubling
        // (4→8→16→…); this reclaims it for the common "grow the value just
        // allocated" pattern, the dominant case in the parser/evaluator.
        // `try_with` for the same reason as `alloc`: no state means no scope,
        // so nothing can be resized in place and the copy path is correct.
        let resized = TL_try_with((tl: ThreadState) -> bool {
            if (tl.depth == 0 || tl.paused > 0) {
                return false;
            }
            let base = tl.base;
            if (base == 0) {
                return false;
            }
            let addr = ptr;
            // `ptr` must lie in THIS arena (≥ base) AND be the last bump
            // (`addr + old_size == cursor`). A system pointer or an earlier
            // (non-tail) arena block fails this and takes the copy fallback.
            if (addr < base || addr + layout.size != tl.cursor) {
                return false;
            }
            match (checked_add(addr, new_size)) {
                let new_end: int if new_end <= tl.end => {
                    tl.cursor = new_end;
                    true
                },
                // A grow past the arena end (or overflow) → copy fallback.
                _ => false,
            }
        });
        if (resized ?? false) {
            return ptr;
        }
        // Fallback: the stock `GlobalAlloc::realloc` (alloc new, copy the
        // overlap, free old). `self.alloc`/`self.dealloc` route arena-vs-system
        // themselves; the old block, if in-arena, is reclaimed at scope reset.
        // SAFETY: same contract and aliasing as the default impl.
        let new_layout = Layout.from_size_align_unchecked(new_size, layout.align);
        let new_ptr = self.alloc(new_layout);
        if (new_ptr != 0) {
            // PORT: `core::ptr::copy_nonoverlapping(ptr, new_ptr,
            // layout.size().min(new_size))` — no raw memory in BAML, so there
            // are no bytes to copy.
            self.dealloc(ptr, layout);
        }
        new_ptr
    }
}

/// An RAII scope marker. Construct it on entering a compile; on `drop` (the
/// panic / early-exit path) it leaves the scope and resets the arena. The
/// success path in `compile` finishes manually — leaving, copying the result
/// out, then resetting — and `mem::forget`s the guard.
class Scope {
    function enter() -> Scope {
        TL_with((tl: ThreadState) -> null {
            tl.depth = tl.depth + 1;
            // One fresh attempt per compile if the registry was full last time.
            // Not per allocation: that would reserve and free 2 GiB apiece.
            tl.registry_full = false;
            null
        });
        Scope {  }
    }

    // PORT: `impl Drop` — kept as a plain method; BAML has no destructors, so a
    // caller that relies on the drop calls `drop()` itself (`mem::forget` →
    // not calling it).
    function drop(self) -> void {
        // Panic / early-exit path: leave and, if outermost, reset.
        if (leave_no_reset()) {
            reset();
        }
    }
}

/// Leave the current scope WITHOUT resetting, returning whether this was the
/// outermost scope. The success path copies the result out before [`reset`].
function leave_no_reset() -> bool {
    TL_with((tl: ThreadState) -> bool {
        let d = root.std.saturating_sub_u(tl.depth, 1);
        tl.depth = d;
        d == 0
    })
}

/// Reset the arena to empty. Only resets when no scope is active (so a nested
/// scope can't free an outer scope's allocations).
function reset() -> void {
    TL_with((tl: ThreadState) -> null {
        if (tl.depth != 0) {
            return null;
        }
        // The compile is over and `compile()` has already copied its result
        // out to the system allocator, so nothing points in here any more:
        // hand the lease back for the next thread that needs one.
        let slot = tl.slot;
        if (slot == NO_SLOT()) {
            tl.cursor = tl.base;
            return null;
        }
        tl.last_slot = slot;
        tl.slot = NO_SLOT();
        tl.base = 0;
        tl.end = 0;
        tl.cursor = 0;
        release_slot(slot);
        null
    });
}

/// Suspend arena allocation (requests go to System) around a caller callback
/// whose allocations may outlive the arena — an `Importer`, a `WarnHandler`.
/// The scope depth is left untouched: if the callback itself runs a `compile`,
/// that nested scope sees a live outer scope, so on return it neither resets
/// the arena nor frees its caller's state. Returns a guard; the pause lifts
/// when it drops — on unwind too, so a panicking callback cannot leave the
/// thread routing every later allocation to System.
function pause() -> Paused {
    TL_with((tl: ThreadState) -> null {
        tl.paused = tl.paused + 1;
        null
    });
    Paused {  }
}

/// RAII token from [`pause`]: dropping it lifts one pause.
class Paused {
    // PORT: `impl Drop` — kept as a plain method; BAML has no destructors, so
    // the holder calls `drop()` where the Rust guard goes out of scope.
    function drop(self) -> void {
        TL_with((tl: ThreadState) -> null {
            tl.paused = root.std.saturating_sub_u(tl.paused, 1);
            null
        });
    }
}

// =========================================================================
// Test-only standalone arena: a `Drop`-ing twin of the bump + provenance logic
// above, used to exercise it under `cargo miri test` without leaking.
// =========================================================================
// PORT: the `#[cfg(test)]` items `struct Arena`, `impl Arena` and
// `impl Drop for Arena` are ported with the tests, in
// `baml_src/ns_arena/ns_tests/tests.baml` (namespace `root.arena.tests`).
