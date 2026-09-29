#!/usr/bin/env python3
"""Wall-clock runtime of the native Rust `sasso` vs the BAML port packed as
`dist/sasso`, on identical inputs (outputs are checked to be identical).

    python3 port/bench_runtime.py
"""
import os, statistics, subprocess, sys, time

PROJ = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
RUST = os.path.join(PROJ, 'port/upstream/sasso/target/release/sasso')
BAML = os.path.join(PROJ, 'dist/sasso')
CORPUS = os.path.join(PROJ, 'port/upstream/sasso/bench/corpus')
BOOT = os.environ.get('BOOTSTRAP_SCSS', os.path.join(os.path.dirname(__file__), '..', '.scratch/bootstrap/scss'))

CASES = [
    ('startup (`--version`)', None, ['--version'], None),
    ('tiny rule (stdin)', None, ['--stdin'], '.a { color: red; }'),
    ('legacy_deprecations.scss (0.8 KB)', os.path.join(CORPUS, 'gate'), ['legacy_deprecations.scss'], None),
    ('large.scss (9 KB, generated)', os.path.join(CORPUS, 'generated'), ['large.scss'], None),
    ('extend_heavy.scss (11 KB)', os.path.join(CORPUS, 'gate'), ['extend_heavy.scss'], None),
    ('selector_lists.scss (25 KB)', os.path.join(CORPUS, 'gate'), ['selector_lists.scss'], None),
    ('Bootstrap 5.3 (bootstrap.scss)', BOOT, ['bootstrap.scss'], None),
]


def run(binary, cwd, args, stdin):
    t = time.perf_counter()
    r = subprocess.run([binary] + args, cwd=cwd, input=(stdin or '').encode(), capture_output=True)
    return time.perf_counter() - t, r.returncode, r.stdout, r.stderr


rows = []
for label, cwd, args, stdin in CASES:
    rust = [run(RUST, cwd, args, stdin) for _ in range(5)]
    baml = [run(BAML, cwd, args, stdin) for _ in range(3)]
    same = all(b[1:] == rust[0][1:] for b in baml)
    rt = statistics.median(t for t, *_ in rust)
    bt = statistics.median(t for t, *_ in baml)
    rows.append((label, rt, bt, bt / rt, same, len(rust[0][2])))
    print(f'{label:36s} rust {rt*1000:9.1f} ms   baml {bt*1000:10.1f} ms   {bt/rt:7.0f}x   identical={same}', flush=True)

print('\n| input | Rust | BAML | slowdown | output identical |\n|---|---|---|---|---|')
for label, rt, bt, x, same, n in rows:
    f = lambda s: f'{s*1000:.0f} ms' if s < 1 else f'{s:.2f} s'
    print(f'| {label} | {f(rt)} | {f(bt)} | {x:.0f}× | {"yes" if same else "NO"} |')
