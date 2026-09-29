// Ported from sasso `src/main.rs` `#[cfg(test)] mod silenced_tests`
// (namespace `root.silenced_tests`).
//
// PORT: `use super::{parse_silenced, DEPRECATION_IDS}` — reached as
// `root.parse_silenced` and `root.DEPRECATION_IDS()` (a const → zero-arg
// function). `parse_silenced` throws a `root.std.StrError` for its `Err`.

/// Every id the evaluator can emit must be silenceable.
///
/// This is the bug the test exists for: `DEPRECATION_IDS` was first
/// assembled by probing candidate names against dart, and `if-function` —
/// one we emit — was not among the names guessed, so
/// `--silence-deprecation=if-function` failed on a warning sasso itself had
/// just printed. Reading the emitter source keeps the two from drifting
/// apart again: a new `Deprecation` constructor cannot be added without
/// this noticing.
test "every_id_we_emit_is_accepted" {
    // PORT: `include_str!("deprecation.rs")` embeds the emitter's source at
    // compile time; BAML has no such macro, so the port's emitter source —
    // `deprecation.rs` ported, which builds each `Deprecation` with the same
    // `id: "…"` literals — is read at run time, relative to the project root
    // that `baml test` runs from.
    let src = root.std.read_to_string("baml_src/ns_deprecation/deprecation.baml");
    // PORT: `src.match_indices(pat)` → a non-overlapping `index_of` scan.
    let pat = "id: \"";
    let emitted: string[] = [];
    let from = 0;
    while let off: int = src.slice(from, src.length()).index_of(pat) {
        let at = from + off;
        let rest = src.slice(at + pat.length(), src.length());
        emitted.push(rest.slice(0, root.std.expect(rest.index_of("\""), "unterminated id literal")));
        from = at + pat.length();
    }

    // Without this the parse silently matching nothing would pass.
    // found only {} ids in deprecation.rs — has the shape changed?
    assert.is_true(emitted.length() >= 6);

    for (let id in emitted) {
        // deprecation.rs emits {id:?} but --silence-deprecation rejects it
        assert.is_true(root.DEPRECATION_IDS().includes(id));
        let into: string[] = [];
        // parse_silenced rejected {id:?}
        let is_ok = {
            root.parse_silenced(id, into);
            true
        } catch (e) {
            let _e: root.std.StrError => false
        };
        assert.is_true(is_ok);
    }
}

test "the_list_is_dart_1_104_1s_enum" {
    // Guards a careless edit: the count is the whole enum, including the
    // three obsolete ids and the two future ones dart still accepts.
    assert.equal(root.DEPRECATION_IDS().length(), 31);
    for (let id in ["if-function", "calc-interp", "user-authored", "adjacent-compounds"]) {
        // missing {id:?}
        assert.is_true(root.DEPRECATION_IDS().includes(id));
    }
    // PORT: `let mut sorted = DEPRECATION_IDS;` copies the array; the
    // zero-arg function returns a fresh one.
    let sorted = root.DEPRECATION_IDS();
    root.std.sort_strings(sorted);
    let deduped = root.std.clone_vec(sorted);
    root.std.dedup(deduped);
    // duplicate id in the list
    assert.equal(deduped.length(), root.DEPRECATION_IDS().length())
}

test "an_unknown_id_is_still_rejected" {
    let into: string[] = [];
    // PORT: `.is_err()` → the call throws a `root.std.StrError`.
    let is_err = {
        root.parse_silenced("no-such-deprecation", into);
        false
    } catch (e) {
        let _e: root.std.StrError => true
    };
    assert.is_true(is_err);
    let is_err = {
        root.parse_silenced("", into);
        false
    } catch (e) {
        let _e: root.std.StrError => true
    };
    assert.is_true(is_err)
}
