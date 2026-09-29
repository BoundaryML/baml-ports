// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2021 Taneli Hukkinen
// Licensed to PSF under a Contributor Agreement.
//
// BAML port of `tests/__init__.py`.
//
// The original is:
//
//     __all__ = ("tomllib",)
//
//     # By changing this one line, we can run the tests against
//     # a different module name.
//     import tomli as tomllib
//
// NOT PORTABLE: BAML has no imports and no namespace aliases (`type` aliases
// only cover types, not functions), so the tests refer to the package by its
// absolute path, `root.tomli.*`. Running the suite against a different
// implementation means a search-and-replace of `root.tomli.` in `ns_tests/`.
