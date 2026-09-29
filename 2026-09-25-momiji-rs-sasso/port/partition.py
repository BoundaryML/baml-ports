#!/usr/bin/env python3
"""Partition sasso's src/ into porting work units (Rust line ranges)."""
import os, re, sys, json
sys.argv = [sys.argv[0], sys.argv[1], '.']
SASSO = sys.argv[1]
src_py = open(os.path.join(os.path.dirname(__file__), 'skeleton.py')).read()
src_py = src_py[:src_py.index('def main():')]
g = {'__name__': 'skel'}
sys_argv = sys.argv
exec(compile(src_py, 'skeleton', 'exec'), g)
SRC = os.path.join(SASSO, 'src')
TARGET = int(os.environ.get('TARGET', '1900'))

def line_of(text, pos):
    return text.count('\n', 0, pos) + 1

units = []
for d, _, fs in os.walk(SRC):
    for f in fs:
        if not f.endswith('.rs'): continue
        rel = os.path.relpath(os.path.join(d, f), SRC)
        src = open(os.path.join(SRC, rel)).read()
        clean = g['blank_comments_strings'](src)
        items = g['parse_items'](src, clean, 0, len(src))
        # break points: item starts; descend into big impls
        pieces = []  # (start_line, end_line, is_test)
        for it in items:
            test = g['is_test'](it.attrs) or (it.kind == 'mod' and 'test' in clean[it.kw_pos:it.kw_pos+60])
            a = line_of(src, it.a); b = line_of(src, it.b)
            if it.kind == 'impl' and b - a > TARGET and not test:
                head = clean[it.kw_pos:it.b]
                lo = it.kw_pos + head.find('{') + 1
                hi = it.kw_pos + head.rfind('}')
                sub = g['parse_items'](src, clean, lo, hi)
                prev = a
                for s in sub:
                    sa = line_of(src, s.a)
                    pieces.append((prev, line_of(src, s.b), False))
                    prev = line_of(src, s.b) + 1
                pieces.append((prev, b, False))
            else:
                pieces.append((a, b, test))
        total = sum(e - s + 1 for s, e, t in pieces if not t)
        nparts = max(1, round(total / TARGET))
        per = total / nparts
        cur = []; acc = 0; part = []
        for s, e, t in pieces:
            if t: continue
            n = e - s + 1
            if acc + n > per * 1.15 and acc > 0 and len(part) < nparts - 1:
                part.append((cur[0][0], cur[-1][1], acc)); cur = []; acc = 0
            cur.append((s, e)); acc += n
        if cur: part.append((cur[0][0], cur[-1][1], acc))
        tests = [(s, e) for s, e, t in pieces if t]
        units.append(dict(rel=rel, lines=len(src.splitlines()), code=total, parts=part, tests=tests))
units.sort(key=lambda u: -u['code'])
for u in units:
    print(f"{u['rel']:36s} code={u['code']:5d} parts=" + ' '.join(f"[{a}-{b}:{n}]" for a, b, n in u['parts']) + (f"  tests={u['tests']}" if u['tests'] else ''))
json.dump(units, open('port/units.json', 'w'), indent=1)
