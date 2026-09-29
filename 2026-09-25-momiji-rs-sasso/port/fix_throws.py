#!/usr/bin/env python3
"""Iterate `baml check`; wherever E0096 says a `throws never` function may
throw `unknown`, widen its declaration to `throws unknown`. Repeat to a
fixed point (each widening can expose callers)."""
import re, subprocess, fcntl, os, glob
env = dict(os.environ, RUST_MIN_STACK='1073741824')
lock_dir = os.path.join(os.environ.get('TMPDIR', '/tmp'), 'baml-splice-locks')
os.makedirs(lock_dir, exist_ok=True)
files = glob.glob('baml_src/**/*.baml', recursive=True)
for it in range(15):
    r = subprocess.run(['baml', 'check', '--no-progress', '--color', 'never'], capture_output=True, text=True, env=env)
    out = r.stdout + r.stderr
    hits = {}
    for m in re.finditer(r'^(\S+?\.baml):(\d+):\d+\S*\s+error\[E0096\]: declared throws is `never`', out, re.M):
        f = m.group(1)
        cands = [p for p in files if p == f or p.endswith('/' + f)]
        if len(cands) == 1:
            hits.setdefault(cands[0], set()).add(int(m.group(2)))
    if not hits:
        print('fixed point after', it, 'iterations')
        break
    for path, lns in hits.items():
        with open(os.path.join(lock_dir, os.path.abspath(path).replace('/', '_') + '.lock'), 'w') as lf:
            fcntl.flock(lf, fcntl.LOCK_EX)
            lines = open(path).read().split('\n')
            for ln in sorted(lns):
                i = ln - 1
                while i >= 0 and not re.match(r'\s*function\s', lines[i]):
                    i -= 1
                if i >= 0 and 'throws never' in lines[i]:
                    lines[i] = lines[i].replace('throws never', 'throws unknown')
                    print(f'{path}:{i+1}: {lines[i].strip()[:80]}')
            open(path, 'w').write('\n'.join(lines))
