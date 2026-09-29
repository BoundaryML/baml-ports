// Port of clap_builder/src/builder/possible_value.rs

/// A possible value of an argument.
///
/// This is used for specifying [possible values] of [Args].
///
/// See also [`PossibleValuesParser`][crate::builder::PossibleValuesParser]
///
/// **NOTE:** Most likely you can use strings, rather than `PossibleValue` as it is only required
/// to [hide] single values from help messages and shell completions or to attach [help] to
/// possible values.
class PossibleValue {
    _name: Str,
    _help: StyledStr?,
    _aliases: Str[],
    _hide: bool,

    /// Create a [`PossibleValue`] with its name.
    ///
    /// The name will be used to decide whether this value was provided by the user to an argument.
    ///
    /// **NOTE:** In case it is not [hidden] it will also be shown in help messages for arguments
    /// that use it as a [possible value] and have not hidden them through [`Arg::hide_possible_values(true)`].
    function new(name: Str) -> PossibleValue {
        PossibleValue { _name: name, _help: null, _aliases: [], _hide: false }
    }

    /// Sets the help description of the value.
    ///
    /// This is typically displayed in completions (where supported) and should be a short, one-line
    /// description.
    function help(self, help: StyledStr | string | null) -> PossibleValue {
        self._help = into_styled_opt(help);
        self
    }

    /// Hides this value from help and shell completions.
    ///
    /// This is an alternative to hiding through [`Arg::hide_possible_values(true)`], if you only
    /// want to hide some values.
    function hide(self, yes: bool) -> PossibleValue {
        self._hide = yes;
        self
    }

    /// Sets a *hidden* alias for this argument value.
    function alias(self, name: Str?) -> PossibleValue {
        if let n: string = name {
            self._aliases.push(n);
        } else {
            self._aliases.clear();
        }
        self
    }

    /// Sets multiple *hidden* aliases for this argument value.
    function aliases(self, names: Str[]) -> PossibleValue {
        for (let n in names) { self._aliases.push(n); }
        self
    }

    /// Get the name of the argument value
    function get_name(self) -> string { self._name }

    /// Get the help specified for this argument, if any
    function get_help(self) -> StyledStr? { self._help }

    /// Report if [`PossibleValue::hide`] is set
    function is_hide_set(self) -> bool { self._hide }

    /// Report if PossibleValue is not hidden and has a help message
    function should_show_help(self) -> bool { !self._hide && self._help != null }

    /// Get the name if argument value is not hidden, `None` otherwise,
    /// but wrapped in quotes if it contains whitespace
    function get_visible_quoted_name(self) -> string? {
        if (!self._hide) { Escape.new(self._name).to_cow() } else { null }
    }

    /// Returns all valid values of the argument value.
    ///
    /// Namely the name and all aliases.
    function get_name_and_aliases(self) -> string[] {
        [self._name].concat(self._aliases)
    }

    /// Tests if the value is valid for this argument value
    ///
    /// The value is valid if it is either the name or one of the aliases.
    function matches(self, value: string, ignore_case: bool) -> bool {
        if (ignore_case) {
            self.get_name_and_aliases().some((name) -> { eq_ignore_case(name, value) })
        } else {
            self.get_name_and_aliases().some((name) -> { name == value })
        }
    }
}

/// `impl<S: Into<Str>> From<S> for PossibleValue`
function into_possible_value(v: PossibleValue | string) -> PossibleValue {
    match (v) {
        let s: string => PossibleValue.new(s),
        let p: PossibleValue => p,
    }
}

testset "possible_value" {
    test "possible_value" {
        let pv = PossibleValue.new("option1");
        assert.is_true(pv.matches("option1", false));
        assert.is_true(!pv.matches("OPTION1", false))
    }
    test "possible_value_ignore_case" {
        let pv = PossibleValue.new("option1");
        assert.is_true(pv.matches("OPTION1", true))
    }
    test "possible_value_aliases" {
        let pv = PossibleValue.new("option1").alias("o1").aliases(["o2", "o3"]);
        assert.equal(pv.get_name_and_aliases(), ["option1", "o1", "o2", "o3"]);
        assert.is_true(pv.matches("o2", false));
        assert.is_true(!pv.matches("o4", false))
    }
    test "quoted_name" {
        assert.equal(PossibleValue.new("a b").get_visible_quoted_name(), "\"a b\"");
        assert.equal(PossibleValue.new("ab").hide(true).get_visible_quoted_name(), null)
    }
}
