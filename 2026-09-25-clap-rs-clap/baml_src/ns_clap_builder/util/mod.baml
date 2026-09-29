// Port of clap_builder/src/util/mod.rs
//
//   mod any_value;          -> any_value.baml   (AnyValue, AnyValueId)
//   mod escape;             -> escape.baml      (Escape)
//   pub(crate) mod flat_map -> flat_map.baml    (FlatMap)
//   pub(crate) mod flat_set -> flat_set.baml    (FlatSet)
//   mod graph;              -> graph.baml       (ChildGraph)
//   mod id;                 -> id.baml          (Id)
//   mod str_to_bool;        -> str_to_bool.baml (str_to_bool, TRUE_LITERALS, FALSE_LITERALS)
//   pub(crate) mod color;   -> color.baml       (ColorChoice)

function SUCCESS_CODE() -> int { 0 }

// While sysexists.h defines EX_USAGE as 64, this doesn't seem to be used much in practice but
// instead 2 seems to be frequently used.
// Examples
// - GNU `ls` returns 2
// - Python's `argparse` returns 2
function USAGE_CODE() -> int { 2 }

/// `#[cfg(not(feature = "unicode"))] eq_ignore_case` uses ASCII case folding,
/// `#[cfg(feature = "unicode")]` re-exports `unicase::eq`.
function eq_ignore_case(left: string, right: string) -> bool {
    if (features().unicode) {
        root.unicase.eq(left, right)
    } else {
        root.unicase.eq_ascii(left, right)
    }
}
