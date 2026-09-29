#!/usr/bin/env python3
"""Count lines of the Rust original and the BAML port, by category.

    python3 port/loc.py

Both languages use `//` line comments and `/* … */` block comments, so the
same rules classify every line as blank, comment or code. Rust `#[cfg(test)]
mod … { … }` blocks inside `src/` count as unit tests.
"""
import os
import re

PROJ = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
RUST = os.path.join(PROJ, 'port/upstream/sasso')
BAML = os.path.join(PROJ, 'baml_src')


def classify(lines):
    """Yield 'blank' | 'comment' | 'code' per line."""
    in_block = False
    for line in lines:
        s = line.strip()
        if in_block:
            if '*/' in s:
                in_block = False
                rest = s.split('*/', 1)[1].strip()
                yield 'code' if rest and not rest.startswith('//') else 'comment'
            else:
                yield 'comment'
            continue
        if not s:
            yield 'blank'
        elif s.startswith('//'):
            yield 'comment'
        elif s.startswith('/*'):
            if '*/' not in s[2:]:
                in_block = True
            yield 'comment'
        else:
            yield 'code'


def rust_test_mask(lines):
    """True for lines inside a `#[cfg(test)] mod … { … }` block."""
    mask = [False] * len(lines)
    i = 0
    while i < len(lines):
        k = i + 1
        while k < len(lines) and lines[k].strip().startswith('#['):
            k += 1  # further attributes between `#[cfg(test)]` and `mod`
        if lines[i].strip() == '#[cfg(test)]' and k < len(lines) and re.match(r'\s*(pub(\(\w+\))?\s+)?mod\s+\w+\s*\{', lines[k]):
            depth = 0
            j = k
            while j < len(lines):
                depth += lines[j].count('{') - lines[j].count('}')
                if depth <= 0 and '{' in ''.join(lines[k:j + 1]):
                    break
                j += 1
            for k in range(i, min(j + 1, len(lines))):
                mask[k] = True
            i = j + 1
        else:
            i += 1
    return mask


def add(totals, cat, kinds):
    t = totals.setdefault(cat, {'files': 0, 'lines': 0, 'blank': 0, 'comment': 0, 'code': 0})
    for k in kinds:
        t['lines'] += 1
        t[k] += 1


def rust_counts():
    totals = {}
    for top, cat in [('src', 'Library + CLI'), ('tests', 'Integration tests'),
                     ('examples', 'Examples + benches'), ('benches', 'Examples + benches')]:
        for root, _, files in os.walk(os.path.join(RUST, top)):
            for f in sorted(files):
                if not f.endswith('.rs'):
                    continue
                lines = open(os.path.join(root, f), encoding='utf-8').read().split('\n')
                if lines and lines[-1] == '':
                    lines.pop()
                kinds = list(classify(lines))
                if top == 'src':
                    mask = rust_test_mask(lines)
                    add(totals, 'Unit tests', [k for k, m in zip(kinds, mask) if m])
                    add(totals, cat, [k for k, m in zip(kinds, mask) if not m])
                    if any(mask):
                        totals['Unit tests']['files'] += 1
                else:
                    add(totals, cat, kinds)
                totals[cat]['files'] += 1
    return totals


def baml_category(rel):
    parts = rel.split(os.sep)
    if parts[0] == 'ns_std':
        return 'Rust std shim (`root.std`)'
    if parts[0] == 'ns_tests':
        return 'Integration tests'
    if parts[0] in ('ns_examples', 'ns_benches'):
        return 'Examples + benches'
    if parts[0] == 'ns_port_harness':
        return 'Port-only harness'
    if any(re.fullmatch(r'ns_(\w+_)?tests', p) for p in parts[:-1]):
        return 'Unit tests'  # `mod tests` / `mod <name>_tests` of a module
    return 'Library + CLI'


def baml_counts():
    totals = {}
    for root, _, files in os.walk(BAML):
        for f in sorted(files):
            if not f.endswith('.baml'):
                continue
            path = os.path.join(root, f)
            lines = open(path, encoding='utf-8').read().split('\n')
            if lines and lines[-1] == '':
                lines.pop()
            cat = baml_category(os.path.relpath(path, BAML))
            add(totals, cat, classify(lines))
            totals[cat]['files'] += 1
    return totals


def main():
    r, b = rust_counts(), baml_counts()
    cats = ['Library + CLI', 'Unit tests', 'Integration tests', 'Examples + benches',
            'Rust std shim (`root.std`)', 'Port-only harness']
    print('| Category | Rust files | Rust lines | Rust code | BAML files | BAML lines | BAML code | Code ratio |')
    print('|---|---|---|---|---|---|---|---|')
    tr = {'files': 0, 'lines': 0, 'code': 0}
    tb = {'files': 0, 'lines': 0, 'code': 0}
    for c in cats:
        x, y = r.get(c), b.get(c)
        for t, v in ((tr, x), (tb, y)):
            if v:
                for k in t:
                    t[k] += v[k]
        ratio = f"{y['code'] / x['code']:.2f}×" if x and y and x['code'] else 'n/a'
        fx = f"{x['files']} | {x['lines']:,} | {x['code']:,}" if x else 'n/a | n/a | n/a'
        fy = f"{y['files']} | {y['lines']:,} | {y['code']:,}" if y else 'n/a | n/a | n/a'
        print(f'| {c} | {fx} | {fy} | {ratio} |')
    print(f"| **Total** | {tr['files']} | {tr['lines']:,} | {tr['code']:,} | {tb['files']} | {tb['lines']:,} | {tb['code']:,} | {tb['code'] / tr['code']:.2f}× |")
    print('\n(Rust unit-test "files" = src files containing a #[cfg(test)] module; those files are also counted under Library + CLI.)')


main()
