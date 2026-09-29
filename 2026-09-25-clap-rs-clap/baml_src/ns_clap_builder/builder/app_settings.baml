// Port of clap_builder/src/builder/app_settings.rs

class AppFlags {
    _0: int,

    function new() -> AppFlags { AppFlags { _0: 0 } }

    function set(self, setting: AppSettings) -> void {
        self._0 = self._0 | app_setting_bit(setting);
    }

    function unset(self, setting: AppSettings) -> void {
        self._0 = self._0 & ~app_setting_bit(setting);
    }

    function is_set(self, setting: AppSettings) -> bool {
        (self._0 & app_setting_bit(setting)) != 0
    }

    function insert(self, other: AppFlags) -> void {
        self._0 = self._0 | other._0;
    }

    /// `impl BitOr for AppFlags`
    function or(self, other: AppFlags) -> AppFlags { AppFlags { _0: self._0 | other._0 } }

    function copy(self) -> AppFlags { AppFlags { _0: self._0 } }
}

/// Application level settings, which affect how [`Command`] operates
///
/// **NOTE:** When these settings are used, they apply only to current command, and are *not*
/// propagated down or up through child or parent subcommands
enum AppSettings {
    IgnoreErrors,
    AllowHyphenValues,
    AllowNegativeNumbers,
    AllArgsOverrideSelf,
    AllowMissingPositional,
    TrailingVarArg,
    DontDelimitTrailingValues,
    InferLongArgs,
    InferSubcommands,
    SubcommandRequired,
    AllowExternalSubcommands,
    Multicall,
    SubcommandsNegateReqs,
    ArgsNegateSubcommands,
    SubcommandPrecedenceOverArg,
    FlattenHelp,
    ArgRequiredElseHelp,
    NextLineHelp,
    DisableColoredHelp,
    DisableHelpFlag,
    DisableHelpSubcommand,
    DisableVersionFlag,
    PropagateVersion,
    Hidden,
    HidePossibleValues,
    HelpExpected,
    NoBinaryName,
    ColorAuto,
    ColorAlways,
    ColorNever,
    Built,
    BinNameBuilt,
}

function app_setting_bit(s: AppSettings) -> int {
    let idx = match (s) {
        AppSettings.IgnoreErrors => 0,
        AppSettings.AllowHyphenValues => 1,
        AppSettings.AllowNegativeNumbers => 2,
        AppSettings.AllArgsOverrideSelf => 3,
        AppSettings.AllowMissingPositional => 4,
        AppSettings.TrailingVarArg => 5,
        AppSettings.DontDelimitTrailingValues => 6,
        AppSettings.InferLongArgs => 7,
        AppSettings.InferSubcommands => 8,
        AppSettings.SubcommandRequired => 9,
        AppSettings.AllowExternalSubcommands => 10,
        AppSettings.Multicall => 11,
        AppSettings.SubcommandsNegateReqs => 12,
        AppSettings.ArgsNegateSubcommands => 13,
        AppSettings.SubcommandPrecedenceOverArg => 14,
        AppSettings.FlattenHelp => 15,
        AppSettings.ArgRequiredElseHelp => 16,
        AppSettings.NextLineHelp => 17,
        AppSettings.DisableColoredHelp => 18,
        AppSettings.DisableHelpFlag => 19,
        AppSettings.DisableHelpSubcommand => 20,
        AppSettings.DisableVersionFlag => 21,
        AppSettings.PropagateVersion => 22,
        AppSettings.Hidden => 23,
        AppSettings.HidePossibleValues => 24,
        AppSettings.HelpExpected => 25,
        AppSettings.NoBinaryName => 26,
        AppSettings.ColorAuto => 27,
        AppSettings.ColorAlways => 28,
        AppSettings.ColorNever => 29,
        AppSettings.Built => 30,
        AppSettings.BinNameBuilt => 31,
    };
    1 << idx
}
