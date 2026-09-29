// Port of clap_builder/src/builder/arg_group.rs

/// Family of related [arguments].
///
/// By placing arguments in a logical group, you can create easier requirement and
/// exclusion rules instead of having to list each argument individually, or when you want a rule
/// to apply "any but not all" arguments.
///
/// For instance, you can make an entire `ArgGroup` required. If [`ArgGroup::multiple(true)`] is
/// set, this means that at least one argument from that group must be present. If
/// [`ArgGroup::multiple(false)`] is set (the default), one and *only* one must be present.
///
/// You can also do things such as name an entire `ArgGroup` as a [conflict] or [requirement] for
/// another argument, meaning any of the arguments that belong to that group will cause a failure
/// if present, or must be present respectively.
///
/// Perhaps the most common use of `ArgGroup`s is to require one and *only* one argument to be
/// present out of a given set. Imagine that you had multiple arguments, and you want one of them
/// to be required, but making all of them required isn't feasible because perhaps they conflict
/// with each other. For example, lets say that you were building an application where one could
/// set a given version number by supplying a string with an option argument, i.e.
/// `--set-ver v1.2.3`, you also wanted to support automatically using a previous version number
/// and simply incrementing one of the three numbers. So you create three flags `--major`,
/// `--minor`, and `--patch`. All of these arguments shouldn't be used at one time but you want to
/// specify that *at least one* of them is used. For this, you can create a group.
///
/// Finally, you may use `ArgGroup`s to pull a value from a group of arguments when you don't care
/// exactly which argument was actually used at runtime.
///
/// # Examples
///
/// The following example demonstrates using an `ArgGroup` to ensure that one, and only one, of
/// the arguments from the specified group is present at runtime.
///
/// ```baml
/// let result = Command.new("cmd")
///     .arg(arg("--set-ver [ver] 'set the version manually'"))
///     .arg(arg("--major 'auto increase major'"))
///     .arg(arg("--minor 'auto increase minor'"))
///     .arg(arg("--patch 'auto increase patch'"))
///     .group(ArgGroup.new("vers")
///          .args(["set-ver", "major", "minor", "patch"])
///          .required(true))
///     .try_get_matches_from(["cmd", "--major", "--patch"]);
/// // Because we used two args in the group it's an error
/// ```
class ArgGroup {
    _id: Id,
    _args: Id[],
    _required: bool,
    _requires: Id[],
    _conflicts: Id[],
    _multiple: bool,

    /// Create a `ArgGroup` using a unique name.
    ///
    /// The name will be used to get values from the group or refer to the group inside of conflict
    /// and requirement rules.
    function new(id: Id) -> ArgGroup {
        ArgGroup { _id: id, _args: [], _required: false, _requires: [], _conflicts: [], _multiple: false }
    }

    /// Sets the group name.
    function id(self, id: Id) -> ArgGroup {
        self._id = id;
        self
    }

    /// Adds an [argument] to this group by name
    function arg(self, arg_id: Id?) -> ArgGroup {
        if let a: string = arg_id {
            self._args.push(a);
        } else {
            self._args.clear();
        }
        self
    }

    /// Adds multiple [arguments] to this group by name
    function args(self, ns: Id[]) -> ArgGroup {
        for (let n in ns) { self._args.push(n); }
        self
    }

    /// Getters for all args. It will return a vector of `Id`
    function get_args(self) -> Id[] { self._args }

    /// Allows more than one of the [`Arg`]s in this group to be used. (Default: `false`)
    function multiple(self, yes: bool) -> ArgGroup {
        self._multiple = yes;
        self
    }

    /// Return true if the group allows more than one of the arguments
    /// in this group to be used. (Default: `false`)
    function is_multiple(self) -> bool { self._multiple }

    /// Require an argument from the group to be present when parsing.
    ///
    /// This is unless conflicting with another argument.  A required group will be displayed in
    /// the usage string of the application in the format `<arg|arg2|arg3>`.
    ///
    /// **NOTE:** This setting only applies to the current [`Command`] / [`Subcommand`]s, and not
    /// globally.
    ///
    /// **NOTE:** By default, [`ArgGroup::multiple`] is set to `false` which when combined with
    /// `ArgGroup::required(true)` states, "One and *only one* arg must be used from this group.
    /// Use of more than one arg is an error." Vice setting `ArgGroup::multiple(true)` which
    /// states, '*At least* one arg from this group must be used. Using multiple is OK."
    function required(self, yes: bool) -> ArgGroup {
        self._required = yes;
        self
    }

    /// Specify an argument or group that must be present when this group is.
    ///
    /// This is not to be confused with a [required group]. Requirement rules function just like
    /// [argument requirement rules], you can name other arguments or groups that must be present
    /// when any one of the arguments from this group is used.
    function requires(self, id: Id?) -> ArgGroup {
        if let i: string = id {
            self._requires.push(i);
        } else {
            self._requires.clear();
        }
        self
    }

    /// Specify arguments or groups that must be present when this group is.
    function requires_all(self, ns: Id[]) -> ArgGroup {
        for (let n in ns) { self._requires.push(n); }
        self
    }

    /// Specify an argument or group that must **not** be present when this group is.
    ///
    /// Exclusion (aka conflict) rules function just like [argument exclusion rules], you can name
    /// other arguments or groups that must *not* be present when one of the arguments from this
    /// group are used.
    function conflicts_with(self, id: Id?) -> ArgGroup {
        if let i: string = id {
            self._conflicts.push(i);
        } else {
            self._conflicts.clear();
        }
        self
    }

    /// Specify arguments or groups that must **not** be present when this group is.
    function conflicts_with_all(self, ns: Id[]) -> ArgGroup {
        for (let n in ns) { self._conflicts.push(n); }
        self
    }

    /// Get the name of the group
    function get_id(self) -> Id { self._id }

    /// Reports whether [`ArgGroup::required`] is set
    function is_required_set(self) -> bool { self._required }

    function clone(self) -> ArgGroup {
        ArgGroup {
            ...self,
            _args: self._args.slice(0, self._args.length()),
            _requires: self._requires.slice(0, self._requires.length()),
            _conflicts: self._conflicts.slice(0, self._conflicts.length()),
        }
    }
}

testset "arg_group" {
    test "groups" {
        let g = ArgGroup.new("test")
            .arg("a1")
            .arg("a4")
            .args(["a2", "a3"])
            .required(true)
            .conflicts_with("c1")
            .conflicts_with_all(["c2", "c3"])
            .conflicts_with("c4")
            .requires("r1")
            .requires_all(["r2", "r3"])
            .requires("r4");

        assert.equal(g.get_args(), ["a1", "a4", "a2", "a3"]);
        assert.equal(g._requires, ["r1", "r2", "r3", "r4"]);
        assert.equal(g._conflicts, ["c1", "c2", "c3", "c4"])
    }
    test "arg_group_expose_is_multiple_helper" {
        let grp_multiple = ArgGroup.new("test_multiple").args(["a1"]).multiple(true);
        assert.is_true(grp_multiple.is_multiple());
        let grp_not_multiple = ArgGroup.new("test_multiple").args(["a1"]).multiple(false);
        assert.is_true(!grp_not_multiple.is_multiple())
    }
    test "arg_group_expose_get_args_helper" {
        let args = ["a1", "a2", "a3"];
        let grp = ArgGroup.new("program").args(args);
        assert.equal(grp.get_args(), args)
    }
}
