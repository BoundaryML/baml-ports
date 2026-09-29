#!/usr/bin/env python3
"""Run `baml check` and show only the errors in the given file(s)/functions.

    python3 port/errors_for.py FILE [FILE ...] [--fn NAME,NAME,...] [--all]

Each error is labelled with the function it falls in (`Container.fn`), so a
porter sharing a file with others can pick out their own. Without --fn, every
error in FILE is shown. Exit status 0 when none match.
"""
import re
import subprocess
import sys

sys.path.insert(0, __import__('os').path.dirname(__file__))


def enclosing(lines):
    """line index -> 'Container.fn' (or 'Container' / 'top')."""
    from importlib import import_module
    sp = import_module('splice')
    owners = sp.find_blocks(lines)
    res = [None] * len(lines)
    cur = None
    cur_end = -1
    for i, ln in enumerate(lines):
        m = re.match(r'^\s*function\s+([A-Za-z_][A-Za-z0-9_]*)', ln)
        if m and i > cur_end:
            end = sp.function_span(lines, i)
            if end is not None and '{' in ''.join(lines[i:end + 1]):
                cur = f'{owners[i]}.{m.group(1)}'
                cur_end = end
        res[i] = cur if i <= cur_end else owners[i]
    return res


def main():
    args = sys.argv[1:]
    fns = None
    if '--fn' in args:
        k = args.index('--fn')
        fns = set(x.strip() for x in args[k + 1].split(',') if x.strip())
        del args[k:k + 2]
    files = args
    import os
    env = dict(os.environ)
    # The BAML compiler recurses deeply on this project; its default thread
    # stack overflows (a silent abort with no diagnostics).
    env['RUST_MIN_STACK'] = env.get('RUST_MIN_STACK', '1073741824')
    # The human format names files by their shortest UNIQUE path suffix
    # (`ns_eval/mod.baml`); the concise one uses bare basenames, which are
    # ambiguous for the many `mod.baml`s.
    out = subprocess.run(['baml', 'check', '--no-progress', '--color', 'never'],
                         capture_output=True, text=True, env=env, cwd=os.path.join(os.path.dirname(__file__), '..'))
    text = out.stdout + out.stderr
    if 'overflowed its stack' in text or out.returncode < 0 or out.returncode >= 100 or ('Finished' not in text and not re.search(r'\[E\d+\]', text)):
        print('!! baml check did not complete (exit %d) — diagnostics unavailable:' % out.returncode)
        print(text[-2000:])
        sys.exit(2)
    count = 0
    cache = {}
    lines = text.split('\n')
    for idx, line in enumerate(lines):
        m = re.match(r'^(\S+?\.baml):(\d+):(\d+)\S*\s+error', line)
        if not m:
            continue
        f = m.group(1)
        match = None
        for want in files:
            w = want[2:] if want.startswith('./') else want
            if w == f or w.endswith('/' + f):
                match = want
        if not match:
            continue
        ln = int(m.group(2))
        if match not in cache:
            cache[match] = enclosing(open(match).read().split('\n'))
        owner = cache[match][ln - 1] if ln - 1 < len(cache[match]) else '?'
        if fns is not None:
            fname = (owner or '').split('.')[-1]
            if fname not in fns and owner not in fns:
                continue
        count += 1
        detail = []
        k = idx + 1
        while k < len(lines) and lines[k].startswith('  '):
            detail.append(lines[k].strip())
            k += 1
        print(f'[{owner}] {line}' + (('  | ' + ' | '.join(detail)) if detail else ''))
    # A syntax error anywhere stops type checking for the WHOLE project, so a
    # clean result for FILE means little while one exists elsewhere.
    blockers = []
    for line in lines:
        m = re.match(r'^(\S+?\.baml):(\d+):\d+\S*\s+error\[(E0010|E0107)\]', line)
        if m:
            blockers.append(f'{m.group(1)}:{m.group(2)}')
    if blockers:
        print(f'!! {len(blockers)} syntax error(s) in the project block type checking '
              f'(first: {", ".join(sorted(set(blockers))[:5])}); a clean result above is NOT reliable')
        if count == 0:
            print(f'-- 0 error(s) shown, but type checking did not run')
            sys.exit(3)
    print(f'-- {count} error(s)')
    sys.exit(1 if count else 0)


main()
