#!/usr/bin/env python3
"""Compare Rust (cargo) and BAML toolchain times on the sasso port.

    python3 port/bench_toolchains.py [--runs-cold N] [--runs-warm N]

Scenarios, each timed as the median of several runs:
  check      type-check the whole crate / project
  test       build + run ONE test: fxhash::tests::basic_map_roundtrips
States:
  cold       no build artefacts (fresh cargo target dir / no .baml cache)
  noop       immediately re-run with nothing changed
  edit       after a one-line content change to value.rs / value.baml

Rust builds go to a private CARGO_TARGET_DIR (the upstream release build is
untouched); BAML runs use a copy of the project so its `.baml/` cache can be
removed for cold runs.
"""
import os
import shutil
import statistics
import subprocess
import sys
import time

PROJ = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
RUST = os.path.join(PROJ, 'port/upstream/sasso')
SCRATCH = os.environ.get('BENCH_DIR', os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '.scratch/toolbench'))
TARGET = os.path.join(SCRATCH, 'cargo-target')
BCOPY = os.path.join(SCRATCH, 'baml-proj')
RUST_EDIT = os.path.join(RUST, 'src/value.rs')
BAML_EDIT = os.path.join(BCOPY, 'baml_src/ns_value/value.baml')

args = sys.argv[1:]
RUNS_COLD = int(args[args.index('--runs-cold') + 1]) if '--runs-cold' in args else 3
RUNS_WARM = int(args[args.index('--runs-warm') + 1]) if '--runs-warm' in args else 5

ENV_RUST = dict(os.environ, CARGO_TARGET_DIR=TARGET, CARGO_TERM_COLOR='never')
ENV_BAML = dict(os.environ, RUST_MIN_STACK='1073741824')

RUST_TEST = ['cargo', 'nextest', 'run', '--lib', '--no-fail-fast', '-E', 'test(=fxhash::tests::basic_map_roundtrips)']
BAML_TEST = ['baml', 'test', '-i', 'root.fxhash.tests::basic_map_roundtrips']
COMMANDS = {
    ('rust', 'check'): (['cargo', 'check'], RUST, ENV_RUST),
    ('rust', 'check --all-targets'): (['cargo', 'check', '--all-targets'], RUST, ENV_RUST),
    ('rust', 'test'): (RUST_TEST, RUST, ENV_RUST),
    ('baml', 'check'): (['baml', 'check'], BCOPY, ENV_BAML),
    ('baml', 'test'): (BAML_TEST, BCOPY, ENV_BAML),
}


def run(cmd, cwd, env):
    t = time.perf_counter()
    r = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True)
    dt = time.perf_counter() - t
    if r.returncode != 0:
        sys.exit(f'command failed ({r.returncode}): {" ".join(cmd)}\n{r.stdout[-2000:]}\n{r.stderr[-2000:]}')
    return dt


def make_cold(lang):
    if lang == 'rust':
        shutil.rmtree(TARGET, ignore_errors=True)
    else:
        shutil.rmtree(os.path.join(BCOPY, '.baml'), ignore_errors=True)


def edit(lang, n):
    """Append (and later strip) a trailing comment line: a real content change."""
    path = RUST_EDIT if lang == 'rust' else BAML_EDIT
    text = open(path).read()
    base = text.split('\n// bench-edit')[0]
    open(path, 'w').write(base + f'\n// bench-edit {n}\n')


def restore(lang):
    path = RUST_EDIT if lang == 'rust' else BAML_EDIT
    text = open(path).read()
    open(path, 'w').write(text.split('\n// bench-edit')[0])


def bench(lang, what, state):
    cmd, cwd, env = COMMANDS[(lang, what)]
    times = []
    runs = RUNS_COLD if state == 'cold' else RUNS_WARM
    # warm up to the state's precondition
    if state != 'cold':
        run(cmd, cwd, env)
    for i in range(runs):
        if state == 'cold':
            make_cold(lang)
        elif state == 'edit':
            edit(lang, i)
        times.append(run(cmd, cwd, env))
    if state == 'edit':
        restore(lang)
        run(cmd, cwd, env)
    return times


def main():
    os.makedirs(SCRATCH, exist_ok=True)
    shutil.rmtree(BCOPY, ignore_errors=True)
    shutil.copytree(PROJ, BCOPY, ignore=shutil.ignore_patterns('.baml', 'port', 'dist'))
    os.makedirs(os.path.join(BCOPY, 'dist'), exist_ok=True)
    # the ported fxhash tests need nothing from dist/ or port/
    rows = []
    plan = [
        ('rust', 'check'), ('rust', 'check --all-targets'), ('baml', 'check'),
        ('rust', 'test'), ('baml', 'test'),
    ]
    try:
        for lang, what in plan:
            for state in ('cold', 'noop', 'edit'):
                ts = bench(lang, what, state)
                med = statistics.median(ts)
                rows.append((lang, what, state, med, min(ts), max(ts), len(ts)))
                print(f'{lang:5s} {what:22s} {state:5s} median {med:7.2f}s  (min {min(ts):.2f}, max {max(ts):.2f}, n={len(ts)})', flush=True)
    finally:
        restore('rust')
    print()
    print('| tool | operation | state | median | min | max | runs |')
    print('|---|---|---|---|---|---|---|')
    for lang, what, state, med, mn, mx, n in rows:
        print(f'| {lang} | {what} | {state} | {med:.2f} s | {mn:.2f} s | {mx:.2f} s | {n} |')


main()
