// Port of anstyle/src/effect.rs

/// A set of text effects
///
/// Stored as a bitset, like the Rust `Effects(u16)`.
class Effects {
    bits: int,

    function new() -> Effects { Effects { bits: 0 } }
    function PLAIN() -> Effects { Effects { bits: 0 } }
    function BOLD() -> Effects { Effects { bits: 1 << 0 } }
    function DIMMED() -> Effects { Effects { bits: 1 << 1 } }
    function ITALIC() -> Effects { Effects { bits: 1 << 2 } }
    function UNDERLINE() -> Effects { Effects { bits: 1 << 3 } }
    function DOUBLE_UNDERLINE() -> Effects { Effects { bits: 1 << 4 } }
    function CURLY_UNDERLINE() -> Effects { Effects { bits: 1 << 5 } }
    function DOTTED_UNDERLINE() -> Effects { Effects { bits: 1 << 6 } }
    function DASHED_UNDERLINE() -> Effects { Effects { bits: 1 << 7 } }
    function BLINK() -> Effects { Effects { bits: 1 << 8 } }
    function INVERT() -> Effects { Effects { bits: 1 << 9 } }
    function HIDDEN() -> Effects { Effects { bits: 1 << 10 } }
    function STRIKETHROUGH() -> Effects { Effects { bits: 1 << 11 } }

    /// Check if no effects are enabled
    function is_plain(self) -> bool { self.bits == 0 }

    /// Returns `true` if all of the effects in `other` are contained within `self`.
    function contains(self, other: Effects) -> bool { (other.bits & self.bits) == other.bits }

    /// Inserts the specified effects in-place.
    function insert(self, other: Effects) -> Effects { Effects { bits: self.bits | other.bits } }

    /// Removes the specified effects in-place.
    function remove(self, other: Effects) -> Effects { Effects { bits: self.bits & ~other.bits } }

    /// Reset all effects in-place
    function clear(self) -> Effects { Effects.new() }

    /// Enable or disable the specified effects depending on the passed value.
    function set(self, other: Effects, enable: bool) -> Effects {
        if (enable) { self.insert(other) } else { self.remove(other) }
    }

    /// Iterate over enabled effects (as single-bit `Effects`)
    function iter(self) -> Effects[] {
        self.index_iter().map((i) -> { Effects { bits: 1 << i } })
    }

    function index_iter(self) -> int[] {
        let out: int[] = [];
        for (let i in baml.iter.Range.new(0, effect_metadata().length())) {
            if ((self.bits & (1 << i)) != 0) { out.push(i); }
        }
        out
    }

    /// Render the ANSI code
    function render(self) -> string {
        let meta = effect_metadata();
        self.index_iter().map((i) -> { meta[i].escape }).join("")
    }

    /// `Debug` impl: `Effects(BOLD | UNDERLINE)`
    function debug(self) -> string {
        let meta = effect_metadata();
        `Effects(${self.index_iter().map((i) -> { meta[i].name }).join(" | ")})`
    }
}

class EffectMetadata {
    name: string,
    escape: string,
}

/// `METADATA` const
function effect_metadata() -> EffectMetadata[] {
    [
        EffectMetadata { name: "BOLD", escape: escape(["1"]) },
        EffectMetadata { name: "DIMMED", escape: escape(["2"]) },
        EffectMetadata { name: "ITALIC", escape: escape(["3"]) },
        EffectMetadata { name: "UNDERLINE", escape: escape(["4"]) },
        EffectMetadata { name: "DOUBLE_UNDERLINE", escape: escape(["21"]) },
        EffectMetadata { name: "CURLY_UNDERLINE", escape: escape(["4:3"]) },
        EffectMetadata { name: "DOTTED_UNDERLINE", escape: escape(["4:4"]) },
        EffectMetadata { name: "DASHED_UNDERLINE", escape: escape(["4:5"]) },
        EffectMetadata { name: "BLINK", escape: escape(["5"]) },
        EffectMetadata { name: "INVERT", escape: escape(["7"]) },
        EffectMetadata { name: "HIDDEN", escape: escape(["8"]) },
        EffectMetadata { name: "STRIKETHROUGH", escape: escape(["9"]) },
    ]
}
