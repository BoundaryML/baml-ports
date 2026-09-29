#!/usr/bin/env python3
import os, re, sys, json
SASSO = sys.argv[1]
sys.argv = [sys.argv[0], SASSO, '.']
src_py = open('port/skeleton.py').read()
src_py = src_py[:src_py.index('def main():')]
g = {'__name__': 'skel'}
exec(compile(src_py, 'skeleton', 'exec'), g)
g['collect']()
def line_of(t, p): return t.count('\n', 0, p) + 1
out = []
for rel, fi in sorted(g['files'].items()):
    for it in fi.items:
        head = fi.clean[it.kw_pos:it.b]
        if g['is_test'](it.attrs) or '#[cfg(test)]' in it.attrs.replace(' ', ''):
            m = re.match(r'(mod|fn|struct|const|static|impl|use|enum|type)\s*([A-Za-z_0-9]*)', head)
            kind, name = (m.group(1), m.group(2)) if m else ('?', '?')
            a, b = line_of(fi.src, it.a), line_of(fi.src, it.b)
            if kind == 'use': continue
            ntests = len(re.findall(r'#\[test\]', fi.src[it.a:it.b]))
            parent = fi.module
            if kind == 'mod':
                ns = (parent + '.' + name) if parent != 'root' else 'root.' + name
                bfile = g['baml_file_of'](rel)
                d = os.path.dirname(bfile)
                if parent == 'root':
                    d = 'baml_src'
                target = f'{d}/ns_{name}/{name}.baml'
            else:
                ns = parent; target = g['baml_file_of'](rel) + ' (inline cfg(test) item)'
            out.append(dict(rel=rel, kind=kind, name=name, a=a, b=b, tests=ntests, ns=ns, target=target))
for o in out:
    print(f"{o['rel']:32s} {o['kind']:4s} {o['name']:28s} L{o['a']}-{o['b']:<5d} tests={o['tests']:3d} -> {o['target']}")
json.dump(out, open('port/tests.json', 'w'), indent=1)
print(sum(o['tests'] for o in out), 'tests;', sum(o['b']-o['a']+1 for o in out), 'lines')
