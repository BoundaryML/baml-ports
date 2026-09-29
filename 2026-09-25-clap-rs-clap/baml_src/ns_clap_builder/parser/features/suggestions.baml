// Port of clap_builder/src/parser/features/suggestions.rs

class Candidate {
    confidence: float,
    value: string,
}

/// Returns a Vec of all possible values that exceed a similarity threshold
/// sorted by ascending similarity, most similar comes last
function did_you_mean(v: string, possible_values: string[]) -> string[] {
    if (!features().suggestions) {
        return [];
    }
    let candidates: Candidate[] = [];
    for (let pv in possible_values) {
        // GH #4660: using `jaro` because `jaro_winkler` implementation in `strsim-rs` is wrong
        // causing strings with common prefix >=10 to be considered perfectly similar
        let confidence = root.strsim.jaro(v, pv);

        if (confidence > 0.7) {
            let new_elem = Candidate { confidence: confidence, value: pv };
            // `binary_search_by` with a comparator that never returns `Equal`: the
            // insertion point is the first candidate with a strictly higher confidence
            let pos = candidates.find_index((probe) -> { probe.confidence > confidence }) ?? candidates.length();
            candidates.insert(new_elem, pos) catch_all (e) { _ => 0 };
        }
    }

    candidates.map((c) -> { c.value })
}

/// `(candidate, Option<subcommand>)` returned by `did_you_mean_flag`
class FlagSuggestion {
    candidate: string,
    subcommand: string?,
}

/// Returns a suffix that can be empty, or is the standard 'did you mean' phrase
function did_you_mean_flag(arg: string, remaining_args: string[], longs: string[], subcommands: Command[]) -> FlagSuggestion? {
    let own = did_you_mean(arg, longs).pop();
    if let candidate: string = own {
        return FlagSuggestion { candidate: candidate, subcommand: null };
    }

    let best: FlagSuggestion? = null;
    let best_score = -1;
    for (let subcommand in subcommands) {
        subcommand._build_self(false);

        let sub_longs = subcommand.get_keymap().keys().filter_map((a) -> {
            match (a) {
                let l: KeyLong => l.s,
                _ => null,
            }
        });

        let subcommand_name = subcommand.get_name();

        let c = did_you_mean(arg, sub_longs).pop();
        if let candidate: string = c {
            let score = remaining_args.find_index((x) -> { subcommand_name == x });
            if let s: int = score {
                if (best == null || s < best_score) {
                    best_score = s;
                    best = FlagSuggestion { candidate: candidate, subcommand: subcommand_name };
                }
            }
        }
    }
    best
}

testset "suggestions" {
    test "missing_letter" {
        assert.equal(did_you_mean("tst", ["test", "possible", "values"]), ["test"])
    }
    test "ambiguous" {
        assert.equal(did_you_mean("te", ["test", "temp", "possible", "values"]), ["test", "temp"])
    }
    test "unrelated" {
        assert.equal(did_you_mean("hahaahahah", ["test", "possible", "values"]), [])
    }
    test "best_fit" {
        assert.equal(
            did_you_mean("alignmentScorr", ["test", "possible", "values", "alignmentStart", "alignmentScore"]),
            ["alignmentStart", "alignmentScore"]
        )
    }
    test "best_fit_long_common_prefix_issue_4660" {
        assert.equal(did_you_mean("alignmentScorr", ["alignmentScore", "alignmentStart"]), ["alignmentStart", "alignmentScore"])
    }
    test "flag_missing_letter" {
        assert.equal(did_you_mean_flag("tst", [], ["test", "possible", "values"], []), FlagSuggestion { candidate: "test", subcommand: null })
    }
    test "flag_ambiguous" {
        assert.equal(did_you_mean_flag("te", [], ["test", "temp", "possible", "values"], []), FlagSuggestion { candidate: "temp", subcommand: null })
    }
    test "flag_unrelated" {
        assert.equal(did_you_mean_flag("hahaahahah", [], ["test", "possible", "values"], []), null)
    }
    test "flag_best_fit" {
        assert.equal(
            did_you_mean_flag("alignmentScorr", [], ["test", "possible", "values", "alignmentStart", "alignmentScore"], []),
            FlagSuggestion { candidate: "alignmentScore", subcommand: null }
        )
    }
}
