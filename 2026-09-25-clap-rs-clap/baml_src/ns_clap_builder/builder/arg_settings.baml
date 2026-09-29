// Port of clap_builder/src/builder/arg_settings.rs

class ArgFlags {
    _0: int,

    function new() -> ArgFlags { ArgFlags { _0: 0 } }

    function set(self, setting: ArgSettings) -> void {
        self._0 = self._0 | arg_setting_bit(setting);
    }

    function unset(self, setting: ArgSettings) -> void {
        self._0 = self._0 & ~arg_setting_bit(setting);
    }

    function is_set(self, setting: ArgSettings) -> bool {
        (self._0 & arg_setting_bit(setting)) != 0
    }

    function insert(self, other: ArgFlags) -> void {
        self._0 = self._0 | other._0;
    }

    function copy(self) -> ArgFlags { ArgFlags { _0: self._0 } }
}

/// Various settings that apply to arguments and may be set, unset, and checked via getter/setter
/// methods [`Arg::setting`], [`Arg::unset_setting`], and [`Arg::is_set`]. This is what the
/// [`Arg`] methods which accept a `bool` use internally.
enum ArgSettings {
    Required,
    Global,
    Hidden,
    NextLineHelp,
    HidePossibleValues,
    AllowHyphenValues,
    AllowNegativeNumbers,
    RequireEquals,
    Last,
    TrailingVarArg,
    HideDefaultValue,
    IgnoreCase,
    HideEnv,
    HideEnvValues,
    HiddenShortHelp,
    HiddenLongHelp,
    Exclusive,
}

function arg_setting_bit(s: ArgSettings) -> int {
    let idx = match (s) {
        ArgSettings.Required => 0,
        ArgSettings.Global => 1,
        ArgSettings.Hidden => 2,
        ArgSettings.NextLineHelp => 3,
        ArgSettings.HidePossibleValues => 4,
        ArgSettings.AllowHyphenValues => 5,
        ArgSettings.AllowNegativeNumbers => 6,
        ArgSettings.RequireEquals => 7,
        ArgSettings.Last => 8,
        ArgSettings.TrailingVarArg => 9,
        ArgSettings.HideDefaultValue => 10,
        ArgSettings.IgnoreCase => 11,
        ArgSettings.HideEnv => 12,
        ArgSettings.HideEnvValues => 13,
        ArgSettings.HiddenShortHelp => 14,
        ArgSettings.HiddenLongHelp => 15,
        ArgSettings.Exclusive => 16,
    };
    1 << idx
}
