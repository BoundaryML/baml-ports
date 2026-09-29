#!/usr/bin/env python3
"""Conformance harness: replays clap's `examples/**/*.md` transcripts (trycmd
format) against the BAML port.

Each Rust example `examples/<path>/<name>.rs` is ported to the BAML namespace
`clap.examples.<path>.<name>` (digit-leading names get an `ex_` prefix, `-`
becomes `_`), whose `main()` is packed with `baml pack` into an executable named
exactly like the Rust binary, so `argv[0]` (and thus clap's `bin_name`) matches.

Usage: python3 tests/trycmd.py [filter...] [-v]
"""
import os, re, shlex, subprocess, sys, tempfile, glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXAMPLES = os.path.join(ROOT, "tests", "examples")  # copies of clap's examples/*.md
BIN_DIR = os.path.join(tempfile.gettempdir(), "clap-baml-bins")


def ns_segment(name):
    name = name.replace("-", "_")
    return "ex_" + name if name[0].isdigit() else name


def target_for_rs(rs_path):
    """`examples/tutorial_builder/01_quick.rs` -> `clap.examples.tutorial_builder.ex_01_quick.main`"""
    rel = rs_path[len("examples/"):-3]
    parts = rel.split("/")
    if parts[-1] == "main":
        # `examples/typed-derive/main.rs` is the binary for the whole directory
        parts = parts[:-1]
    return "clap.examples." + ".".join(ns_segment(p) for p in parts) + ".main"


def load_bins():
    """Binary name -> BAML target, from clap's `Cargo.toml` `[[example]]` table."""
    bins = {}
    for line in open(os.path.join(EXAMPLES, "bins.txt")):
        name, path = line.split()
        bins[name] = target_for_rs(path)
    return bins


def parse_md(path):
    """Yield (cmdline, expected_status, expected_output) triples."""
    text = open(path).read()
    cases = []
    for block in re.findall(r"```console\n(.*?)```", text, re.S):
        lines = block.split("\n")
        i = 0
        while i < len(lines):
            line = lines[i]
            if line.startswith("$ "):
                cmd = line[2:]
                i += 1
                status = "success"
                if i < len(lines) and lines[i].startswith("? "):
                    status = lines[i][2:].strip()
                    i += 1
                out = []
                while i < len(lines) and not lines[i].startswith("$ "):
                    out.append(lines[i])
                    i += 1
                while out and out[-1] == "":
                    out.pop()
                cases.append((cmd, status, "\n".join(out)))
            else:
                i += 1
    return cases


def matches(expected, actual):
    exp = expected.replace("[EXE]", "").split("\n")
    act = actual.split("\n")

    def line_re(l):
        parts = l.split("[..]")
        return re.compile("^" + ".*".join(re.escape(p) for p in parts) + "$")

    def rec(ei, ai):
        if ei == len(exp):
            return ai == len(act)
        if exp[ei] == "...":
            for k in range(ai, len(act) + 1):
                if rec(ei + 1, k):
                    return True
            return False
        if ai < len(act) and line_re(exp[ei]).match(act[ai]):
            return rec(ei + 1, ai + 1)
        return False

    return rec(0, 0)


def pack(target, bin_name):
    os.makedirs(BIN_DIR, exist_ok=True)
    out = os.path.join(BIN_DIR, bin_name)
    r = subprocess.run(["baml", "pack", target, "--output", out], cwd=ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        return r.stdout + r.stderr
    return None


def main():
    verbose = "-v" in sys.argv
    filters = [a for a in sys.argv[1:] if a != "-v"]
    mds = sorted(glob.glob(os.path.join(EXAMPLES, "**", "*.md"), recursive=True))
    targets = load_bins()
    packed = {}
    total = passed = 0
    failures = []
    for md in mds:
        rel = os.path.relpath(md, EXAMPLES)
        if filters and not any(f in rel for f in filters):
            continue
        cases = parse_md(md)
        if not cases:
            continue
        for cmd, status, expected in cases:
            total += 1
            b = shlex.split(cmd)[0]
            if b not in packed:
                packed[b] = pack(targets[b], b) if b in targets else f"unknown binary {b}"
            pack_err = packed[b]
            if pack_err:
                failures.append((rel, cmd, "pack failed:\n" + pack_err[-2000:], expected))
                continue
            argv = shlex.split(cmd)
            # clap's transcripts are generated without a terminal and with the
            # `wrap_help` + `env` features (see clap's CI).
            env = dict(os.environ, NO_COLOR="1", CLAP_FEATURES="wrap_help,env")
            env.pop("COLUMNS", None)
            r = subprocess.run([os.path.join(BIN_DIR, argv[0])] + argv[1:], capture_output=True, text=True,
                               env=env, cwd=ROOT, stdin=subprocess.DEVNULL)
            actual = (r.stdout + r.stderr).rstrip("\n")
            ok_status = (status == "success" and r.returncode == 0) or \
                        (status == "failed" and r.returncode != 0) or \
                        (status.isdigit() and r.returncode == int(status))
            if ok_status and matches(expected, actual):
                passed += 1
            else:
                failures.append((rel, cmd, f"[exit {r.returncode}, expected {status}]\n{actual}", expected))
    for rel, cmd, actual, expected in failures:
        print(f"FAIL {rel}: $ {cmd}")
        if verbose:
            print("--- expected ---")
            print(expected)
            print("--- actual ---")
            print(actual)
            print()
    print(f"{passed}/{total} transcript commands passed")
    sys.exit(0 if passed == total else 1)


if __name__ == "__main__":
    main()
