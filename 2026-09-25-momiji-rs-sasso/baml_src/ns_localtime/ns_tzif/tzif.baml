// Ported from sasso `src/localtime/tzif.rs` (namespace `root.localtime.tzif`).
//
// The TZif binary format (RFC 8536) — the files under `/usr/share/zoneinfo`
// that every Unix keeps its timezone rules in.
//
// The layout, once through for the reader who has not met it:
//
// ```text
// "TZif" version[1] reserved[15]
// six 32-bit counts: isutcnt isstdcnt leapcnt timecnt typecnt charcnt
// a 32-bit data block                 <- kept only for pre-2005 readers
// "TZif" ... the same header again    <- version >= 2 only
// a 64-bit data block                 <- the one to read
// "\n" a POSIX TZ string "\n"         <- what to do past the last transition
// ```
//
// This reader BORROWS the bytes and allocates nothing: the transition list
// is binary-searched in place rather than collected. A directory build can
// ask for a timestamp thousands of times, and none of them should allocate.
//
// It also never panics and never indexes without checking. The input is a
// file on disk that no part of this program wrote, and a malformed or
// truncated one must produce `None`, not a crash in a build tool.

/// A parsed TZif file: offsets into the caller's bytes, nothing owned.
class TimeZone {
    bytes: uint8array,
    /// Where the 64-bit transition times begin.
    transitions: int,
    count: int,
    /// Where the per-transition type indices begin.
    indices: int,
    /// Where the local-time-type records begin (6 bytes each).
    types: int,
    type_count: int,
    /// The POSIX TZ footer, when the file has a usable one.
    footer: root.localtime.posix.Posix?,
    /// Parse `bytes`. `None` if they are not a version 2+ TZif file.
    ///
    /// Version 1 files are refused rather than given a second code path:
    /// they have no 64-bit block and no footer, they stopped being produced
    /// in 2005, and supporting them would mean maintaining a parser that
    /// nothing exercises.
    function parse(bytes: uint8array) -> TimeZone? {
        let v1 = header(bytes, 0)
            ?? return null;
        if (v1.version < 50) { // b'2'
            return null;
        }
        // Skip the whole 32-bit block; the 64-bit one supersedes it.
        let second = checked_add(
            44,
            block_len(v1, 4)
                ?? return null,
        )
            ?? return null;
        let c = header(bytes, second)
            ?? return null;

        let transitions = checked_add(second, 44)
            ?? return null;
        let indices = checked_add(
            transitions,
            checked_mul(c.timecnt, 8)
                ?? return null,
        )
            ?? return null;
        let types = checked_add(indices, c.timecnt)
            ?? return null;
        let chars = checked_add(
            types,
            checked_mul(c.typecnt, 6)
                ?? return null,
        )
            ?? return null;
        // Everything above must be inside the file before any of it is read.
        let end = checked_add(chars, c.charcnt)
            ?? return null;
        end
            = checked_add(
                end,
                checked_mul(c.leapcnt, 12)
                    ?? return null,
            )
                ?? return null;
        end
            = checked_add(end, c.isstdcnt)
                ?? return null;
        end
            = checked_add(end, c.isutcnt)
                ?? return null;
        if (end > bytes.length() || c.typecnt == 0) {
            return null;
        }

        // The footer is the rest, wrapped in newlines. A file without one,
        // or with one this parser does not fully understand, simply has no
        // footer — the last tabulated offset is then the answer, which is
        // right for every zone that has stopped changing its rules.
        // PORT: the `Option` combinator chain is written as nested `if`s.
        let footer: root.localtime.posix.Posix? = null;
        let rest = get_range(bytes, end, bytes.length());
        if (rest != null) {
            let s: string? = string.from_utf8(rest) catch (e) {
                let _e: baml.errors.InvalidArgument => null
            };
            if (s != null) {
                let s = root.std.trim_matches(s, "\n");
                if (s != "") {
                    footer = root.localtime.posix.parse(s);
                }
            }
        }

        TimeZone {
            bytes: bytes,
            transitions: transitions,
            count: c.timecnt,
            indices: indices,
            types: types,
            type_count: c.typecnt,
            footer: footer,
        }
    }

    function transition(self, i: int) -> int {
        be_i64(self.bytes, self.transitions + i * 8) ?? root.std.INT_MIN()
    }

    function offset_of_type(self, t: int) -> int? {
        if (t >= self.type_count) {
            return null;
        }
        be_i32(self.bytes, self.types + t * 6)
    }

    /// The first local time type that is not daylight saving, which RFC 8536
    /// names as the answer for instants before the first transition.
    function first_standard(self) -> int? {
        for (let t in baml.iter.Range.new(0, self.type_count)) {
            if (self.bytes.at(self.types + t * 6 + 4) == 0) {
                return self.offset_of_type(t);
            }
        }
        self.offset_of_type(0)
    }

    /// The UTC offset, in seconds east, at `secs`.
    function offset_at(self, secs: int) -> int? {
        // partition_point over the transitions, without materialising them.
        let lo = 0;
        let hi = self.count;
        while (lo < hi) {
            let mid = lo + (hi - lo) / 2;
            if (self.transition(mid) <= secs) {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }

        // Past the last transition the footer is the authority. This is the
        // branch that makes a 2065 timestamp right instead of an hour out,
        // and it is reached for EVERY instant in a zone that has no
        // transitions left — which includes every zone without DST.
        if (lo == self.count) {
            if let p: root.localtime.posix.Posix = self.footer {
                return root.localtime.posix.offset_at(p, secs);
            }
        }
        if (lo == 0) {
            return self.first_standard();
        }
        let t = self.bytes.at(self.indices + lo - 1)
            ?? return null;
        self.offset_of_type(t)
    }
}

class Counts {
    isutcnt: int,
    isstdcnt: int,
    leapcnt: int,
    timecnt: int,
    typecnt: int,
    charcnt: int,
    version: int,
}

/// `b.get(start..end)`: the bytes in `[start, end)`, or `None` when the range
/// is not inside `b`.
// PORT: helper for Rust's checked slice `get`; `uint8array.slice` clamps
// instead of failing. `start` and `end` are never negative here (usize).
function get_range(b: uint8array, start: int, end: int) -> uint8array? {
    if (start > end || end > b.length()) {
        return null;
    }
    b.slice(start, end)
}

/// `usize::checked_mul`.
// PORT: helper for Rust's checked arithmetic; the bound is BAML's 63-bit int
// range rather than usize's.
function checked_mul(a: int, b: int) -> int? {
    let r = root.std.bigint_of(a) * root.std.bigint_of(b);
    if (r > root.std.bigint_of(root.std.INT_MAX()) || r < 0n) {
        null
    } else {
        root.std.int_of(r)
    }
}

/// `usize::checked_add`.
// PORT: helper for Rust's checked arithmetic; the bound is BAML's 63-bit int
// range rather than usize's.
function checked_add(a: int, b: int) -> int? {
    let r = root.std.bigint_of(a) + root.std.bigint_of(b);
    if (r > root.std.bigint_of(root.std.INT_MAX()) || r < 0n) {
        null
    } else {
        root.std.int_of(r)
    }
}

function be_u32(b: uint8array, at: int) -> int? {
    let s = get_range(b, at, at + 4)
        ?? return null;
    (s[0] << 24) | (s[1] << 16) | (s[2] << 8) | s[3]
}

function be_i64(b: uint8array, at: int) -> int? {
    let s = get_range(b, at, at + 8)
        ?? return null;
    // PORT: `i64::from_be_bytes` goes through a bigint. BAML ints are 63-bit,
    // so a value outside ±2^62 (only a corrupt file holds one) saturates; that
    // keeps its order against every `secs` the binary search compares it to.
    let u: bigint = 0n;
    for (let x in s.to_array()) {
        u = (u << 8) | root.std.bigint_of(x);
    }
    let v = if (u >= (1n << 63)) {
        u - (1n << 64)
    } else {
        u
    };
    if (v > root.std.bigint_of(root.std.INT_MAX())) {
        root.std.INT_MAX()
    } else if (v < root.std.bigint_of(root.std.INT_MIN())) {
        root.std.INT_MIN()
    } else {
        root.std.int_of(v)
    }
}

function be_i32(b: uint8array, at: int) -> int? {
    root.std.as_i32(
        be_u32(b, at)
            ?? return null,
    )
}

/// Read a 44-byte header at `at`.
function header(b: uint8array, at: int) -> Counts? {
    if (
        (
            get_range(b, at, at + 4)
                ?? return null
        )
            != b"TZif"
    ) {
        return null;
    }
    let version = b.at(at + 4)
        ?? return null;
    // Counts are `u32` on disk but index into a slice, so they are widened
    // to `usize` once here; every later use is then checked arithmetic.
    Counts {
        isutcnt: be_u32(b, at + 20)
            ?? return null,
        isstdcnt: be_u32(b, at + 24)
            ?? return null,
        leapcnt: be_u32(b, at + 28)
            ?? return null,
        timecnt: be_u32(b, at + 32)
            ?? return null,
        typecnt: be_u32(b, at + 36)
            ?? return null,
        charcnt: be_u32(b, at + 40)
            ?? return null,
        version: version,
    }
}

/// The size of a data block, in bytes. `stride` is 4 for the 32-bit block
/// and 8 for the 64-bit one. Returns `None` on overflow, which is how an
/// absurd count in a corrupt file is rejected rather than wrapping.
function block_len(c: Counts, stride: int) -> int? {
    let leap_entry = stride + 4;
    // PORT: the `checked_*` method chain is one `?`-step per line.
    let n = checked_mul(c.timecnt, stride + 1)
        ?? return null;
    n
        = checked_add(
            n,
            checked_mul(c.typecnt, 6)
                ?? return null,
        )
            ?? return null;
    n
        = checked_add(n, c.charcnt)
            ?? return null;
    n
        = checked_add(
            n,
            checked_mul(c.leapcnt, leap_entry)
                ?? return null,
        )
            ?? return null;
    n
        = checked_add(n, c.isstdcnt)
            ?? return null;
    checked_add(n, c.isutcnt)
}
