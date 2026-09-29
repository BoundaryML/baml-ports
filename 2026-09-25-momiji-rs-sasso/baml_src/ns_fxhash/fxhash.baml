// Ported from sasso `src/fxhash.rs` (namespace `root.fxhash`).
//
// A small, fast, non-cryptographic hasher (the "FxHash" algorithm, as used by
// rustc and Firefox) for the compiler's internal `String`-keyed maps.
//
// The default `std` `HashMap` uses SipHash, which is DoS-resistant but slow —
// and the compiler's hot path is dominated by variable / function / mixin
// lookups keyed on short identifiers, where collision-resistance against
// adversarial input is irrelevant (the keys come from the stylesheet being
// compiled, not the network). Swapping in FxHash cut a visible chunk of the
// profile's hashing time.
//
// Implemented inline (no `rustc-hash` dependency) to preserve sasso's
// zero-runtime-dependency property, and with no `unsafe` (the crate forbids
// it): the byte path uses `copy_from_slice` + `from_le_bytes`.

/// The FxHash mixing constant (a large odd number; same as rustc-hash).
function SEED() -> bigint {
    0x51_7c_c1_b7_27_22_0a_95n
}

/// A `HashMap` using [`FxHasher`] instead of the default SipHash.
// PORT: generic type alias expanded at use sites: type FxHashMap<K, V> = HashMap<K, V, BuildHasherDefault<FxHasher>>

/// A `HashSet` using [`FxHasher`] instead of the default SipHash.
// PORT: generic type alias expanded at use sites: type FxHashSet<K> = HashSet<K, BuildHasherDefault<FxHasher>>

/// FxHash: fold each machine word of the input into the running hash with a
/// rotate-xor-multiply step. Fast for short keys; not collision-resistant
/// against adversarial input (which the compiler never hashes).
class FxHasher {
    hash: bigint,
    /// derive(Default)
    function default() -> FxHasher {
        FxHasher { hash: 0n }
    }

    function add(self, word: bigint) -> void {
        self.hash = root.std.u64_wrapping_mul(root.std.u64_rotate_left(self.hash, 5) ^ word, SEED());
    }

    // PORT: `impl Hasher` — methods kept as plain methods.
    // PORT: an offset cursor `i` stands in for re-slicing `bytes`, and
    // `FxHasher_le_word` for `copy_from_slice` + `from_le_bytes`.
    function write(self, bytes: uint8array) -> void {
        let i = 0;
        let len = bytes.length();
        // Consume 8/4/2/1-byte chunks, each as a little-endian word.
        while (len - i >= 8) {
            self.add(FxHasher_le_word(bytes, i, 8));
            i += 8;
        }
        if (len - i >= 4) {
            self.add(FxHasher_le_word(bytes, i, 4));
            i += 4;
        }
        if (len - i >= 2) {
            self.add(FxHasher_le_word(bytes, i, 2));
            i += 2;
        }
        if let b: int = bytes.at(i) {
            self.add(root.std.bigint_of(b));
        }
    }

    function write_u8(self, i: int) -> void {
        self.add(root.std.bigint_of(i));
    }

    function write_u16(self, i: int) -> void {
        self.add(root.std.bigint_of(i));
    }

    function write_u32(self, i: int) -> void {
        self.add(root.std.bigint_of(i));
    }

    function write_u64(self, i: bigint) -> void {
        self.add(i);
    }

    function write_usize(self, i: int) -> void {
        self.add(root.std.bigint_of(i));
    }

    function finish(self) -> bigint {
        self.hash
    }
}

/// PORT: helper for `u64::from_le_bytes` / `u32::from_le_bytes` /
/// `u16::from_le_bytes` over `bytes[start..start + n]`.
function FxHasher_le_word(bytes: uint8array, start: int, n: int) -> bigint {
    let w: bigint = 0n;
    let k = n - 1;
    while (k >= 0) {
        w = (w << 8) | root.std.bigint_of(bytes[start + k]);
        k -= 1;
    }
    w
}
