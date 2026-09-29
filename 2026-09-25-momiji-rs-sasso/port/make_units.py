#!/usr/bin/env python3
import os, re, sys
SASSO = sys.argv[1]
sys.argv = [sys.argv[0], SASSO, '.']
src_py = open('port/skeleton.py').read()
src_py = src_py[:src_py.index('def main():')]
g = {'__name__': 'skel'}
exec(compile(src_py, 'skeleton', 'exec'), g)
g['collect']()
SRC = os.path.join(SASSO, 'src')
BIG = 10**9
UNITS = {
 'U01': [('eval/mod.rs', 1, 2032)], 'U02': [('eval/mod.rs', 2033, 3735)], 'U03': [('eval/mod.rs', 3736, 5749)],
 'U04': [('eval/mod.rs', 5750, 7688)], 'U05': [('eval/mod.rs', 7689, 8973), ('eval/scope.rs', 1, BIG)],
 'U06': [('selector/mod.rs', 1, 1961)], 'U07': [('selector/mod.rs', 1962, 3953)],
 'U08': [('selector/mod.rs', 3954, 5217), ('selector/parse.rs', 1, BIG)],
 'U09': [('value.rs', 1, 1853)],
 'U10': [('value.rs', 1854, 3347), ('deprecation.rs', 1, BIG), ('scanner.rs', 1, BIG), ('error.rs', 1, BIG), ('fxhash.rs', 1, BIG)],
 'U11': [('parser/at_rules.rs', 1, 1593)],
 'U12': [('parser/at_rules.rs', 1594, 2870), ('parser/control_flow.rs', 1, BIG), ('parser/statements.rs', 1, BIG)],
 'U13': [('parser/value.rs', 1, 1461)], 'U14': [('parser/value.rs', 1462, 2543)],
 'U15': [('parser/mod.rs', 1, BIG), ('ast.rs', 1, BIG)],
 'U16': [('sass_parser.rs', 1, BIG)],
 'U18': [('main.rs', 1, 1818)], 'U19': [('main.rs', 1819, 3420), ('watch.rs', 1, BIG)],
 'U20': [('builtins/color/legacy.rs', 1, BIG)],
 'U21': [('builtins/color/math.rs', 1, BIG), ('builtins/color/modern.rs', 1, BIG)],
 'U22': [('builtins/color_ext.rs', 1, BIG), ('builtins/color/mod.rs', 1, BIG), ('builtins/color/deprecate.rs', 1, BIG), ('builtins/color/removed.rs', 1, BIG)],
 'U23': [('builtins/colorspace.rs', 1, BIG), ('builtins/colorspace_matrices.rs', 1, BIG), ('musl_math.rs', 1, BIG), ('musl_math_tables.rs', 1, BIG)],
 'U24': [('eval/modules.rs', 1, BIG)],
 'U25': [('eval/control_flow.rs', 1, BIG), ('eval/calc.rs', 1, BIG)],
 'U26': [('eval/meta.rs', 1, BIG), ('eval/binop.rs', 1, BIG)],
 'U27': [('eval/at_rules.rs', 1, BIG), ('eval/plain_css.rs', 1, BIG)],
 'U28': [('eval/expr.rs', 1, BIG), ('host_fn.rs', 1, BIG)],
 'U29': [('builtins/math.rs', 1, BIG), ('builtins/string.rs', 1, BIG)],
 'U30': [('builtins/mod.rs', 1, BIG), ('builtins/selector.rs', 1, BIG)],
 'U31': [('builtins/list.rs', 1, BIG), ('builtins/map.rs', 1, BIG), ('builtins/meta.rs', 1, BIG)],
 'U32': [('emit.rs', 1, BIG), ('sourcemap.rs', 1, BIG)],
 'U33': [('diag.rs', 1, BIG), ('ast_writer.rs', 1, BIG)],
 'U34': [('lib.rs', 1, BIG), ('importer.rs', 1, BIG), ('pathstyle.rs', 1, BIG)],
 'U35': [('arena.rs', 1, BIG), ('ryu.rs', 1, BIG), ('ryu_tables.rs', 1, BIG)],
 'U36': [('localtime/mod.rs', 1, BIG), ('localtime/civil.rs', 1, BIG), ('localtime/posix.rs', 1, BIG), ('localtime/sys.rs', 1, BIG), ('localtime/tzif.rs', 1, BIG)],
}
# which files are shared
count = {}
for u, parts in UNITS.items():
    for rel, a, b in parts:
        count[rel] = count.get(rel, 0) + 1

def line_of(text, pos):
    return text.count('\n', 0, pos) + 1

def items_in(rel, a, b):
    fi = g['files'][rel]
    out = []
    for it in fi.items:
        if g['cfg_excluded'](it.attrs):
            continue
        ln = line_of(fi.src, it.kw_pos)
        head = fi.clean[it.kw_pos:it.b]
        if it.kind == 'impl':
            trait, target = g['impl_target'](fi, it)
            for m in g['impl_method_items'](fi, it):
                if g['cfg_excluded'](m.attrs) or m.kind not in ('fn', 'const fn', 'const'):
                    continue
                ml = line_of(fi.src, m.kw_pos)
                if a <= ml <= b:
                    mh = fi.clean[m.kw_pos:m.b]
                    nm = re.search(r'(?:fn|const)\s+([A-Za-z_0-9]+)', mh)
                    out.append((ml, f'{"impl " + trait + " for " if trait else "impl "}{target}::{nm.group(1) if nm else "?"}'))
            continue
        if not (a <= ln <= b):
            continue
        nm = re.match(r'(?:const\s+fn|fn|struct|enum|trait|type|const|static|mod)\s+([A-Za-z_0-9]+)', head)
        if it.kind in ('use',) or not nm:
            continue
        if it.kind == 'mod':
            continue
        out.append((ln, f'{it.kind} {nm.group(1)}'))
    return out

for u, parts in UNITS.items():
    lines = [f'# {u}', '', 'Read `port/PORTER_BRIEF.md` and `PORTING_GUIDE.md` first.', '']
    total = 0
    for rel, a, b in parts:
        fi = g['files'][rel]
        n = len(fi.src.splitlines())
        bb = min(b, n)
        shared = count[rel] > 1
        bfile = g['baml_file_of'](rel)
        lines.append(f'## `src/{rel}` lines {a}–{bb}  →  `{bfile}` (namespace `{fi.module}`) — ' + ('**SHARED** with other units: edit only via `port/splice.py`' if shared else 'exclusive to you: edit freely'))
        lines.append('')
        its = items_in(rel, a, bb)
        lines.append('Items you own (Rust line: item). Structs/enums: fix their declarations if needed; functions/methods: port the bodies.')
        lines.append('')
        for ln, desc in its:
            lines.append(f'- L{ln}: `{desc}`')
        lines.append('')
        total += bb - a + 1
    lines.append(f'(~{total} Rust lines)')
    open(f'port/units/{u}.md', 'w').write('\n'.join(lines) + '\n')
    print(u, total, sum(1 for l in lines if l.startswith('- L')))
