// Port of strsim-0.11.1/src/lib.rs
//
// This library implements string similarity metrics.
//
// `strsim` is a dependency of `clap_builder` (feature `suggestions`), used by
// `parser/features/suggestions.baml` to power "a similar argument exists" tips.

/// `enum StrSimError { DifferentLengthArgs }`
class StrSimError {
    message: string,
}

function different_length_args() -> StrSimError {
    StrSimError { message: "Differing length arguments provided" }
}

/// Calculates the number of positions in the two sequences where the elements
/// differ. Returns an error if the sequences have different lengths.
function generic_hamming<T>(a: T[], b: T[]) -> int throws StrSimError {
    if (a.length() != b.length()) {
        throw different_length_args();
    }
    let count = 0;
    for (let i in baml.iter.Range.new(0, a.length())) {
        if (a[i] != b[i]) { count += 1; }
    }
    count
}

/// Calculates the number of positions in the two strings where the characters
/// differ. Returns an error if the strings have different lengths.
function hamming(a: string, b: string) -> int throws StrSimError {
    generic_hamming(a.chars(), b.chars())
}

/// Calculates the Jaro similarity between two sequences. The returned value
/// is between 0.0 and 1.0 (higher value means more similar).
function generic_jaro<T>(a: T[], b: T[]) -> float {
    let a_len = a.length();
    let b_len = b.length();

    if (a_len == 0 && b_len == 0) {
        return 1.0;
    } else if (a_len == 0 || b_len == 0) {
        return 0.0;
    }

    let search_range = max_int(a_len, b_len) / 2;
    search_range = max_int(search_range - 1, 0);

    let a_flags = baml.Array.filled(a_len, false);
    let b_flags = baml.Array.filled(b_len, false);
    let matches = 0;

    for (let i in baml.iter.Range.new(0, a_len)) {
        let a_elem = a[i];
        // prevent integer wrapping
        let min_bound = if (i > search_range) { i - search_range } else { 0 };
        let max_bound = min_int(b_len, i + search_range + 1);

        for (let j in baml.iter.Range.new(0, max_bound)) {
            if (min_bound <= j && a_elem == b[j] && !b_flags[j]) {
                a_flags[i] = true;
                b_flags[j] = true;
                matches += 1;
                break;
            }
        }
    }

    let transpositions = 0;
    if (matches != 0) {
        let bj = 0;
        for (let i in baml.iter.Range.new(0, a_len)) {
            if (a_flags[i]) {
                while (bj < b_len) {
                    let j = bj;
                    bj += 1;
                    if (!b_flags[j]) {
                        continue;
                    }
                    if (a[i] != b[j]) {
                        transpositions += 1;
                    }
                    break;
                }
            }
        }
    }
    transpositions = transpositions / 2;

    if (matches == 0) {
        0.0
    } else {
        let m = matches * 1.0;
        ((m / a_len) + (m / b_len) + ((matches - transpositions) / m)) / 3.0
    }
}

/// Calculates the Jaro similarity between two strings. The returned value
/// is between 0.0 and 1.0 (higher value means more similar).
function jaro(a: string, b: string) -> float {
    generic_jaro(a.chars(), b.chars())
}

/// Like Jaro but gives a boost to sequences that have a common prefix.
function generic_jaro_winkler<T>(a: T[], b: T[]) -> float {
    let sim = generic_jaro(a, b);

    if (sim > 0.7) {
        let prefix_length = 0;
        let limit = min_int(4, min_int(a.length(), b.length()));
        while (prefix_length < limit && a[prefix_length] == b[prefix_length]) {
            prefix_length += 1;
        }
        sim + 0.1 * prefix_length * (1.0 - sim)
    } else {
        sim
    }
}

/// Like Jaro but gives a boost to strings that have a common prefix.
function jaro_winkler(a: string, b: string) -> float {
    generic_jaro_winkler(a.chars(), b.chars())
}

/// Calculates the minimum number of insertions, deletions, and substitutions
/// required to change one sequence into the other.
function generic_levenshtein<T>(a: T[], b: T[]) -> int {
    let b_len = b.length();
    let cache = baml.Array.generate(b_len, (i) -> { i + 1 });
    let result = b_len;

    for (let i in baml.iter.Range.new(0, a.length())) {
        result = i + 1;
        let distance_b = i;

        for (let j in baml.iter.Range.new(0, b_len)) {
            let cost = if (a[i] != b[j]) { 1 } else { 0 };
            let distance_a = distance_b + cost;
            distance_b = cache[j];
            result = min_int(result + 1, min_int(distance_a, distance_b + 1));
            cache[j] = result;
        }
    }

    result
}

/// Calculates the minimum number of insertions, deletions, and substitutions
/// required to change one string into the other.
function levenshtein(a: string, b: string) -> int {
    generic_levenshtein(a.chars(), b.chars())
}

/// Calculates a normalized score of the Levenshtein algorithm between 0.0 and
/// 1.0 (inclusive), where 1.0 means the strings are the same.
function normalized_levenshtein(a: string, b: string) -> float {
    if (a.is_empty() && b.is_empty()) {
        return 1.0;
    }
    1.0 - (levenshtein(a, b) * 1.0) / max_int(a.length(), b.length())
}

/// Like Levenshtein but allows for adjacent transpositions. Each substring can
/// only be edited once.
function osa_distance(a: string, b: string) -> int {
    let ac = a.chars();
    let bc = b.chars();
    let b_len = bc.length();
    let prev_two_distances = baml.Array.generate(b_len + 1, (i) -> { i });
    let prev_distances = baml.Array.generate(b_len + 1, (i) -> { i });
    let curr_distances = baml.Array.filled(b_len + 1, 0);

    let prev_a_char = "";
    let prev_b_char = "";

    for (let i in baml.iter.Range.new(0, ac.length())) {
        let a_char = ac[i];
        curr_distances[0] = i + 1;

        for (let j in baml.iter.Range.new(0, b_len)) {
            let b_char = bc[j];
            let cost = if (a_char != b_char) { 1 } else { 0 };
            curr_distances[j + 1] = min_int(
                curr_distances[j] + 1,
                min_int(prev_distances[j + 1] + 1, prev_distances[j] + cost),
            );
            if (i > 0 && j > 0 && a_char != b_char && a_char == prev_b_char && b_char == prev_a_char) {
                curr_distances[j + 1] = min_int(curr_distances[j + 1], prev_two_distances[j - 1] + 1);
            }

            prev_b_char = b_char;
        }

        let tmp = prev_two_distances;
        prev_two_distances = prev_distances;
        prev_distances = curr_distances;
        curr_distances = tmp;
        prev_a_char = a_char;
    }

    prev_distances[b_len]
}

/// Like optimal string alignment, but substrings can be edited an unlimited
/// number of times, and the triangle inequality holds.
function generic_damerau_levenshtein<T>(a_elems: T[], b_elems: T[]) -> int {
    let a_len = a_elems.length();
    let b_len = b_elems.length();

    if (a_len == 0) {
        return b_len;
    }
    if (b_len == 0) {
        return a_len;
    }

    let width = a_len + 2;
    let distances = baml.Array.filled((a_len + 2) * (b_len + 2), 0);
    let max_distance = a_len + b_len;
    distances[flat_index(0, 0, width)] = max_distance;

    for (let i in baml.iter.Range.new(0, a_len + 1)) {
        distances[flat_index(i + 1, 0, width)] = max_distance;
        distances[flat_index(i + 1, 1, width)] = i;
    }

    for (let j in baml.iter.Range.new(0, b_len + 1)) {
        distances[flat_index(0, j + 1, width)] = max_distance;
        distances[flat_index(1, j + 1, width)] = j;
    }

    // `HashMap<Elem, usize>` keyed by the element's string form
    let elems: map<string, int> = {};

    for (let i in baml.iter.Range.new(1, a_len + 1)) {
        let db = 0;

        for (let j in baml.iter.Range.new(1, b_len + 1)) {
            let k = elems.get(`${b_elems[j - 1]}`) ?? 0;

            let insertion_cost = distances[flat_index(i, j + 1, width)] + 1;
            let deletion_cost = distances[flat_index(i + 1, j, width)] + 1;
            let transposition_cost = distances[flat_index(k, db, width)] + (i - k - 1) + 1 + (j - db - 1);

            let substitution_cost = distances[flat_index(i, j, width)] + 1;
            if (a_elems[i - 1] == b_elems[j - 1]) {
                db = j;
                substitution_cost -= 1;
            }

            distances[flat_index(i + 1, j + 1, width)] = min_int(
                substitution_cost,
                min_int(insertion_cost, min_int(deletion_cost, transposition_cost)),
            );
        }

        elems.set(`${a_elems[i - 1]}`, i);
    }

    distances[flat_index(a_len + 1, b_len + 1, width)]
}

/// Returns the final index for a value in a single vector that represents a
/// fixed 2d grid
function flat_index(i: int, j: int, width: int) -> int {
    j * width + i
}

/// Like optimal string alignment, but substrings can be edited an unlimited
/// number of times, and the triangle inequality holds.
function damerau_levenshtein(a: string, b: string) -> int {
    generic_damerau_levenshtein(a.chars(), b.chars())
}

/// Calculates a normalized score of the Damerau–Levenshtein algorithm between
/// 0.0 and 1.0 (inclusive), where 1.0 means the strings are the same.
function normalized_damerau_levenshtein(a: string, b: string) -> float {
    if (a.is_empty() && b.is_empty()) {
        return 1.0;
    }
    let len1 = a.length();
    let len2 = b.length();
    let dist = damerau_levenshtein(a, b);
    1.0 - (dist * 1.0) / max_int(len1, len2)
}

/// Returns an array of the character bigrams of `s`
function bigrams(s: string) -> string[] {
    let chars = s.chars();
    let out: string[] = [];
    for (let i in baml.iter.Range.new(1, chars.length())) {
        out.push(chars[i - 1] + chars[i]);
    }
    out
}

/// Calculates a Sørensen-Dice similarity distance using bigrams.
function sorensen_dice(a: string, b: string) -> float {
    let a2 = a.chars().filter((c) -> { !c.is_whitespace() }).join("");
    let b2 = b.chars().filter((c) -> { !c.is_whitespace() }).join("");

    if (a2 == b2) {
        return 1.0;
    }

    if (a2.byte_length() < 2 || b2.byte_length() < 2) {
        return 0.0;
    }

    let a_bigrams: map<string, int> = {};
    for (let bigram in bigrams(a2)) {
        a_bigrams.set(bigram, (a_bigrams.get(bigram) ?? 0) + 1);
    }

    let intersection_size = 0;
    for (let bigram in bigrams(b2)) {
        let count = a_bigrams.get(bigram) ?? 0;
        if (count > 0) {
            a_bigrams.set(bigram, count - 1);
            intersection_size += 1;
        }
    }

    (2 * intersection_size * 1.0) / (a2.byte_length() + b2.byte_length() - 2)
}

function min_int(a: int, b: int) -> int { if (a < b) { a } else { b } }
function max_int(a: int, b: int) -> int { if (a > b) { a } else { b } }

// #[cfg(test)] mod tests
testset "strsim" {
    test "hamming" {
        assert.equal(hamming("hamming", "hammers"), 3);
        assert.equal(hamming("", ""), 0);
        let err = hamming("ham", "hamming") catch (e) { let x: StrSimError => -1 };
        assert.equal(err, -1)
    }
    test "jaro" {
        assert.equal(jaro("", ""), 1.0);
        assert.equal(jaro("", "jaro"), 0.0);
        assert.approx_equal(jaro("Friedrich Nietzsche", "Jean-Paul Sartre"), 0.392, 0.001);
        assert.approx_equal(jaro("martha", "marhta"), 0.944, 0.001);
        assert.approx_equal(jaro("dixon", "dicksonx"), 0.767, 0.001);
        assert.approx_equal(jaro("a", "a"), 1.0, 0.00001)
    }
    test "jaro_winkler" {
        assert.approx_equal(jaro_winkler("cheeseburger", "cheese fries"), 0.866, 0.001);
        assert.approx_equal(jaro_winkler("dixon", "dicksonx"), 0.813, 0.001);
        assert.approx_equal(jaro_winkler("martha", "marhta"), 0.961, 0.001)
    }
    test "levenshtein" {
        assert.equal(levenshtein("kitten", "sitting"), 3);
        assert.equal(levenshtein("", "abc"), 3);
        assert.equal(levenshtein("hello, world", "bye, world"), 5);
        assert.approx_equal(normalized_levenshtein("kitten", "sitting"), 0.57142, 0.0001)
    }
    test "osa_and_damerau" {
        assert.equal(osa_distance("ab", "bca"), 3);
        assert.equal(damerau_levenshtein("ab", "bca"), 2);
        assert.equal(osa_distance("damerau", "aderua"), 3);
        assert.equal(damerau_levenshtein("damerau", "aderua"), 3);
        assert.equal(damerau_levenshtein("", ""), 0);
        assert.approx_equal(normalized_damerau_levenshtein("levenshtein", "löwenbräu"), 0.27272, 0.0001)
    }
    test "sorensen_dice" {
        assert.equal(sorensen_dice("a", "a"), 1.0);
        assert.equal(sorensen_dice("french", "quebec"), 0.0);
        assert.approx_equal(sorensen_dice("france", "french"), 0.4, 0.00001);
        assert.approx_equal(sorensen_dice("night", "nacht"), 0.25, 0.00001)
    }
}
