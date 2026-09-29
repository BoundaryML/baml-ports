#!/usr/bin/env python3
"""Step through BAML's project cache (.baml/) to see what cold vs warm costs.

    python3 port/bench_baml_cache.py <baml-project-copy> [repeats]

Each step is timed (median of `repeats` when the step is repeatable)."""
import os, shutil, statistics, subprocess, sys, time

proj = os.path.abspath(sys.argv[1])
reps = int(sys.argv[2]) if len(sys.argv) > 2 else 3
env = dict(os.environ, RUST_MIN_STACK='1073741824')
F = os.path.join(proj, 'baml_src/ns_value/value.baml')
orig = open(F).read()
CMDS = {'check': ['baml', 'check'],
        'test': ['baml', 'test', '-i', 'root.fxhash.tests::basic_map_roundtrips']}


def run(cmd):
    t = time.perf_counter()
    r = subprocess.run(cmd, cwd=proj, env=env, capture_output=True, text=True)
    dt = time.perf_counter() - t
    if r.returncode != 0:
        sys.exit(f'FAILED: {cmd}\n{r.stdout[-1500:]}{r.stderr[-1500:]}')
    return dt


def rm(p):
    shutil.rmtree(os.path.join(proj, p), ignore_errors=True)


def write(extra=''):
    open(F, 'w').write(orig + extra)


def size(p):
    total = 0
    for d, _, fs in os.walk(os.path.join(proj, p)):
        for f in fs:
            total += os.path.getsize(os.path.join(d, f))
    return total / 1e6


try:
    for name, cmd in CMDS.items():
        print(f'=== baml {" ".join(cmd[1:])}')

        def step(label, prep=None, repeat=True):
            ts = []
            for i in range(reps if repeat else 1):
                if prep:
                    prep(i)
                ts.append(run(cmd))
            print(f'  {label:34s} {statistics.median(ts):6.2f}s   (cache {size(".baml/cache"):6.1f} MB, profiles {size(".baml/profiles-v1"):5.1f} MB)', flush=True)

        write()
        step('cold (no .baml/)', lambda i: rm('.baml'))
        step('warm, no change')
        step('warm, profiles-v1/ removed', lambda i: rm('.baml/profiles-v1'))
        step('warm, cache/ removed', lambda i: rm('.baml/cache'))
        step('warm + edit (new content each run)', lambda i: write(f'\n// bench-edit {name}-{time.time_ns()}\n'))
        write()
        run(cmd)
        step('warm + revert to seen content', lambda i: (write('\n// seen\n'), run(cmd), write()) and None)
        step('cold + edit', lambda i: (rm('.baml'), write(f'\n// cold-edit {i}\n')) and None)
        write()
        run(cmd)
finally:
    write()
