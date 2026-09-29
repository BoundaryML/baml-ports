// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2021 Taneli Hukkinen
// Licensed to PSF under a Contributor Agreement.
//
// BAML port of `tomli/__init__.py`.
//
// Python's `__all__ = ("loads", "load", "TOMLDecodeError")` and the
// re-export `from ._parser import TOMLDecodeError, load, loads` have no BAML
// equivalent and are not needed: every file in `ns_tomli/` shares the
// `tomli` namespace, so `root.tomli.loads`, `root.tomli.load` and
// `root.tomli.TOMLDecodeError` are already the public names. BAML has no
// visibility control either, so the "private" helpers (`_parser`, `_re`
// functions) are equally reachable.

/// `tomli.__version__`. (A function: BAML has no module-level constants.)
function __version__() -> string {
    "2.4.1" // DO NOT EDIT THIS LINE MANUALLY. LET bump2version UTILITY DO IT
}
