// Port of heck-0.5.0/src/train.rs

/// This function converts to train case.
///
/// ```baml
/// assert.equal(to_train_case("We are going to inherit the earth."), "We-Are-Going-To-Inherit-The-Earth")
/// ```
function to_train_case(s: string) -> string { transform(s, WordStyle.Capitalize, "-") }
