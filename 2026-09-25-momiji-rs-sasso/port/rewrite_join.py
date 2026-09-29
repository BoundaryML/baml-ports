#!/usr/bin/env python3
"""Rewrite `RECV.join(SEP)` → `root.std.join(RECV, SEP)` in ported files.

BAML's builtin `Array.join` renders each element through the generic
`string.from`, which dominates profiles; `root.std.join` concatenates
strings natively. Sites whose receiver is not a `string[]` fail to type-check
and are reverted. Files are edited under port/splice.py's locks."""
import fcntl, glob, os, re, subprocess, sys

sys.path.insert(0, os.path.dirname(__file__))
from splice import strip_strings  # noqa: E402

LOCKS = os.path.join(os.environ.get('TMPDIR', '/tmp'), 'baml-splice-locks')
os.makedirs(LOCKS, exist_ok=True)
ENV = dict(os.environ, RUST_MIN_STACK='1073741824')


def receiver_start(line, dot):
    """Index where the receiver expression ending at `dot` begins."""
    i = dot - 1
    while i >= 0:
        c = line[i]
        if c in ')]':
            close, open_ = c, '(' if c == ')' else '['
            depth = 0
            while i >= 0:
                if line[i] == close:
                    depth += 1
                elif line[i] == open_:
                    depth -= 1
                    if depth == 0:
                        break
                i -= 1
            i -= 1
            continue
        if c.isalnum() or c in '_.':
            i -= 1
            continue
        break
    return i + 1


def rewrite_line(line):
    out = line
    for m in reversed(list(re.finditer(r'\.join\(', line))):
        code = strip_strings(line[:m.start()])
        if len(code) != len(line[:m.start()]):
            continue  # inside a string or comment
        start = receiver_start(line, m.start())
        recv = line[start:m.start()]
        if not recv or recv.startswith('.') or recv.split('.')[0] in ('root', 'baml'):
            continue
        # find the matching `)` of the call
        depth = 0
        j = m.end() - 1
        while j < len(line):
            if line[j] == '(':
                depth += 1
            elif line[j] == ')':
                depth -= 1
                if depth == 0:
                    break
            j += 1
        if j >= len(line):
            continue
        args = line[m.end():j]
        out = out[:start] + f'root.std.join({recv}, {args})' + out[j + 1:]
    return out


def locked(path):
    f = open(os.path.join(LOCKS, os.path.abspath(path).replace('/', '_') + '.lock'), 'w')
    fcntl.flock(f, fcntl.LOCK_EX)
    return f


def check():
    r = subprocess.run(['baml', 'check', '--no-progress', '--color', 'never'], capture_output=True, text=True, env=ENV)
    return r.stdout + r.stderr


files = [p for p in glob.glob('baml_src/**/*.baml', recursive=True)
         if '/ns_std/' not in p and '/ns_tests/' not in p and '_tests/' not in p and 'harness' not in p]
changed = {}
for path in files:
    lf = locked(path)
    text = open(path).read()
    lines = text.split('\n')
    new = [rewrite_line(l) if '.join(' in l and not l.strip().startswith('//') else l for l in lines]
    if new != lines:
        changed[path] = (text, [i for i, (a, b) in enumerate(zip(lines, new)) if a != b])
        open(path, 'w').write('\n'.join(new))
    lf.close()
print('sites rewritten:', sum(len(v[1]) for v in changed.values()), 'in', len(changed), 'files')
# revert sites that no longer type-check
for it in range(5):
    out = check()
    bad = {}
    for m in re.finditer(r'^(\S+?\.baml):(\d+):\d+\S*\s+error', out, re.M):
        f, ln = m.group(1), int(m.group(2))
        for p in changed:
            if p == f or p.endswith('/' + f):
                bad.setdefault(p, set()).add(ln - 1)
    if not bad:
        break
    for p, lns in bad.items():
        lf = locked(p)
        cur = open(p).read().split('\n')
        orig = changed[p][0].split('\n')
        for ln in lns:
            if ln < len(cur) and 'root.std.join(' in cur[ln] and ln < len(orig):
                cur[ln] = orig[ln]
        open(p, 'w').write('\n'.join(cur))
        lf.close()
        print('reverted', len(lns), 'line(s) in', p)
print('errors after rewrite:', len(re.findall(r'^\S+\.baml:\d+:\d+\S*\s+error', check(), re.M)))
