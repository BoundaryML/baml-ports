// Port of clap_builder/src/builder/arg_predicate.rs

/// Operations to perform on argument values
///
/// These do not apply to [`ValueSource::DefaultValue`][crate::parser::ValueSource::DefaultValue]
type ArgPredicate = ArgPredicateIsPresent | ArgPredicateEquals

/// Is the argument present?
class ArgPredicateIsPresent {}

/// Does the argument match the specified value?
class ArgPredicateEquals {
    value: OsStr,
}

function arg_predicate_is_present() -> ArgPredicate { ArgPredicateIsPresent {} }

function arg_predicate_equals(value: OsStr) -> ArgPredicate { ArgPredicateEquals { value: value } }

/// `impl<S: Into<OsStr>> From<S> for ArgPredicate`
function into_arg_predicate(p: ArgPredicate | string) -> ArgPredicate {
    match (p) {
        let s: string => ArgPredicateEquals { value: s },
        let a: ArgPredicate => a,
    }
}
