#!/usr/bin/env python3
"""Extract SCSS snippets from sasso's tests into port/corpus/, with the Rust
binary's output as the expected CSS (the Rust sasso matches dart-sass there)."""
import os, re, subprocess, sys
SASSO = sys.argv[1]
BIN = os.path.join(SASSO, 'target/release/sasso')
src_py = open('port/skeleton.py').read()
start = src_py.index('def rust_str_value(lit):'); end = src_py.index('def baml_str(value):')
exec(src_py[start:end])
bl_start = src_py.index('def blank_comments_strings(src):'); bl_end = src_py.index('def match_close(')
exec(src_py[bl_start:bl_end])

STR = re.compile(r'(r#*"|")')
def read_literal(src, i):
    """Parse a Rust string literal at src[i:]; return (value, end) or None."""
    m = re.match(r'r(#*)"', src[i:])
    if m:
        h = m.group(1)
        j = src.find('"' + h, i + len(m.group(0)))
        return rust_str_value(src[i:j + 1 + len(h)]), j + 1 + len(h)
    if src[i] == '"':
        j = i + 1
        while src[j] != '"':
            j += 2 if src[j] == '\\' else 1
        return rust_str_value(src[i:j + 1]), j + 1
    return None

cases = []
for fname, calls in [('parity.rs', {'assert_parity': 'expanded', 'assert_parity_compressed': 'compressed', 'assert_error_parity': 'error'}),
                     ('integration.rs', {'css': 'expanded', 'css_compressed': 'compressed'})]:
    src = open(os.path.join(SASSO, 'tests', fname)).read()
    for m in re.finditer(r'\b(' + '|'.join(calls) + r')\(\s*', src):
        i = m.end()
        lit = read_literal(src, i) if i < len(src) and (src[i] in '"r') else None
        if not lit:
            continue
        val, end = lit
        rest = src[end:end + 3].lstrip()
        if rest.startswith('.') or rest.startswith('+'):
            continue  # not a plain literal argument
        cases.append((fname, calls[m.group(1)], val))
seen = set()
n = 0
for fname, style, scss in cases:
    key = (style, scss)
    if key in seen: continue
    seen.add(key)
    args = [BIN, '--stdin']
    if style == 'compressed':
        args.append('--style=compressed')
    r = subprocess.run(args, input=scss.encode(), capture_output=True)
    base = f'port/corpus/{n:04d}'
    open(base + '.scss', 'w').write(scss)
    open(base + '.style', 'w').write(style + '\n')
    open(base + '.expected', 'wb').write(r.stdout)
    open(base + '.expected_err', 'wb').write(r.stderr)
    open(base + '.expected_code', 'w').write(str(r.returncode) + '\n')
    n += 1
print(n, 'cases')
