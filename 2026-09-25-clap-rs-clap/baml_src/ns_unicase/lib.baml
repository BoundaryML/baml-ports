// Port of unicase-2.9.0/src/lib.rs
//
// A case-insensitive wrapper around strings. `clap_builder` uses
// `unicase::eq` (as `eq_ignore_case`) for `ignore_case` value matching.

/// Case Insensitive wrapper of strings.
class UniCase {
    _inner: string,

    /// Creates a new `UniCase`.
    function new(s: string) -> UniCase { UniCase { _inner: s } }

    /// Unwraps the inner value held by this `UniCase`.
    function into_inner(self) -> string { self._inner }

    function to_folded_case(self) -> string { fold(self._inner) }

    function eq(self, other: UniCase) -> bool { fold(self._inner) == fold(other._inner) }
}

/// Unicode full case-folding (approximated by lowercasing; the special cases
/// where folding and lowercasing differ are handled explicitly).
function fold(s: string) -> string {
    s.to_lower_case().replace_all("ß", "ss").replace_all("ς", "σ").replace_all("ẞ", "ss")
}

/// Compare two string-like types for case-less equality, using unicode folding.
///
/// Equivalent to `UniCase::new(left) == UniCase::new(right)`.
function eq(left: string, right: string) -> bool {
    fold(left) == fold(right)
}

/// Compare two string-like types for case-less equality, ignoring ASCII case.
function eq_ascii(left: string, right: string) -> bool {
    ascii_lower(left) == ascii_lower(right)
}

function ascii_lower(s: string) -> string {
    s.chars().map((c) -> { if (c.is_ascii_uppercase()) { c.to_lower_case() } else { c } }).join("")
}

testset "unicase" {
    test "case_insensitive" {
        assert.is_true(eq("foobar", "FOOBAR"));
        assert.is_true(eq("Maße", "MASSE"));
        assert.is_true(!eq("foo", "bar"));
        assert.is_true(eq_ascii("fooBAR", "FOObar"));
        assert.is_true(UniCase.new("ΣΑΣ").eq(UniCase.new("σας")))
    }
}
