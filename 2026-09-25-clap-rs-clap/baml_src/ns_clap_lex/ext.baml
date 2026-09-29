// Port of clap_lex-1.1.0/src/ext.rs
//
// String methods for `OsStr`. Rust needs an extension trait because `OsStr`
// lacks `str`'s API; with BAML strings these are free functions over `string`.

/// `OsStrExt::try_str`: always succeeds, BAML strings are UTF-8
function try_str(s: string) -> string { s }

/// Returns `true` if the given pattern matches a sub-slice of this string slice.
function contains(s: string, needle: string) -> bool { s.includes(needle) }

/// Returns the byte index of the first character of this string slice that
/// matches the pattern.
function find(s: string, needle: string) -> int? { s.index_of(needle) }

/// Returns a string slice with the prefix removed.
function strip_prefix(s: string, prefix: string) -> string? {
    if (s.starts_with(prefix)) { s.slice(prefix.length(), s.length()) } else { null }
}

/// Returns `true` if the given pattern matches a prefix of this string slice.
function starts_with(s: string, prefix: string) -> bool { s.starts_with(prefix) }

/// An iterator over substrings of this string slice, separated by characters
/// matched by a pattern.
function split(s: string, needle: string) -> string[] {
    s.split(needle)
}

/// Splits the string on the first occurrence of the specified delimiter and
/// returns prefix before delimiter and suffix after delimiter.
function split_once(s: string, needle: string) -> string[]? {
    if let start: int = s.index_of(needle) {
        [s.slice(0, start), s.slice(start + needle.length(), s.length())]
    } else {
        null
    }
}

testset "ext" {
    test "find" {
        assert.equal(find("", "="), null);
        assert.equal(find("a=b", "="), 1);
        assert.equal(find("a=b", "c"), null)
    }
    test "split_once" {
        assert.equal(split_once("a=b=c", "="), ["a", "b=c"]);
        assert.equal(split_once("abc", "="), null)
    }
    test "strip_prefix" {
        assert.equal(strip_prefix("--hello", "--"), "hello");
        assert.equal(strip_prefix("hello", "--"), null)
    }
    test "split" {
        assert.equal(split("a,b,,c", ","), ["a", "b", "", "c"])
    }
}
