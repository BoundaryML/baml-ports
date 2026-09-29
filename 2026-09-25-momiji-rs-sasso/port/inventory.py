#!/usr/bin/env python3
"""Extract a Rust item inventory from sasso's sources, for the BAML port.

Usage: inventory.py <sasso-checkout> > port/INVENTORY.md
Rough (regex + brace matching), but good enough to tell a porter what kind of
thing a foreign name is and where its methods live.
"""
import os, re, sys

ROOT = sys.argv[1]

def strip_comments_and_strings(src):
    # Replace comments and string/char literal contents with spaces, keeping
    # offsets, so brace matching is not fooled.
    out = list(src)
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith('//', i):
            j = src.find('\n', i)
            j = n if j < 0 else j
            for k in range(i, j): out[k] = ' '
            i = j
        elif src.startswith('/*', i):
            depth, j = 1, i + 2
            while j < n and depth:
                if src.startswith('/*', j): depth += 1; j += 2
                elif src.startswith('*/', j): depth -= 1; j += 2
                else: j += 1
            for k in range(i, j):
                if out[k] != '\n': out[k] = ' '
            i = j
        elif c == 'r' and re.match(r'r#*"', src[i:i+10]) and (i == 0 or not (src[i-1].isalnum() or src[i-1] == '_')):
            m = re.match(r'r(#*)"', src[i:])
            hashes = m.group(1)
            end = src.find('"' + hashes, i + len(m.group(0)))
            end = n if end < 0 else end + 1 + len(hashes)
            for k in range(i + 1, end - 1):
                if out[k] != '\n': out[k] = ' '
            i = end
        elif c == '"':
            j = i + 1
            while j < n and src[j] != '"':
                j += 2 if src[j] == '\\' else 1
            for k in range(i + 1, j):
                if out[k] != '\n': out[k] = ' '
            i = j + 1
        elif c == "'":
            m = re.match(r"'(\\u\{[0-9a-fA-F]+\}|\\x[0-9a-fA-F]{2}|\\.|[^\\'])'", src[i:])
            if m:
                for k in range(i + 1, i + len(m.group(0)) - 1): out[k] = ' '
                i += len(m.group(0))
            else:
                i += 1
        else:
            i += 1
    return ''.join(out)

def match_brace(s, i):
    depth = 0
    while i < len(s):
        if s[i] == '{': depth += 1
        elif s[i] == '}':
            depth -= 1
            if depth == 0: return i
        i += 1
    return len(s)

def sig_text(src, start, end):
    t = src[start:end]
    t = re.sub(r'\s+', ' ', t).strip()
    return t

def module_of(rel):
    p = rel[:-3]
    parts = p.split('/')
    if parts[-1] == 'mod': parts = parts[:-1]
    if parts == ['lib'] or parts == ['main']: return 'root'
    return 'root.' + '.'.join(parts)

def baml_path(rel):
    parts = rel[:-3].split('/')
    if parts == ['lib']: return 'baml_src/lib.baml'
    if parts == ['main']: return 'baml_src/main.baml'
    if parts[-1] == 'mod':
        return 'baml_src/' + '/'.join('ns_' + p for p in parts[:-1]) + '/mod.baml'
    return 'baml_src/' + '/'.join('ns_' + p for p in parts) + '/' + parts[-1] + '.baml'

ITEM = re.compile(r'(?m)^(\s*)((?:#\[[^\]]*\]\s*)*)(?:pub(?:\([^)]*\))?\s+)?(?:unsafe\s+)?(?:const\s+fn|fn|struct|enum|trait|type|const|static|impl|mod|macro_rules!)\b')

def scan(rel, src):
    clean = strip_comments_and_strings(src)
    items = []
    i = 0
    n = len(clean)
    def scan_level(lo, hi, depth, in_impl=None):
        pos = lo
        while pos < hi:
            m = ITEM.search(clean, pos, hi)
            if not m: break
            start = m.start()
            # skip matches not at brace depth of this level: ensure preceding text at this level
            head_end = m.end()
            kw = re.search(r'(const\s+fn|fn|struct|enum|trait|type|const|static|impl|mod|macro_rules!)\b', clean[m.start(2)+len(m.group(2)):head_end + 5])
            kw = kw.group(1) if kw else ''
            attrs = src[m.start(2):m.end(2)]
            # find end of item header: '{' or ';'
            j = head_end
            depth_paren = 0
            while j < hi:
                ch = clean[j]
                if ch in '([<': depth_paren += 1
                elif ch in ')]>':
                    if not (ch == '>' and clean[j-1] == '-'): depth_paren -= 1
                elif ch == '{' and depth_paren <= 0: break
                elif ch == ';' and depth_paren <= 0: break
                j += 1
            header = sig_text(src, m.start(2) + len(m.group(2)), j)
            if j < hi and clean[j] == '{':
                end = match_brace(clean, j)
            else:
                end = j
            yield (kw, header, attrs, j, end)
            pos = end + 1
    for kw, header, attrs, j, end in scan_level(0, n, 0):
        items.append((kw, header, attrs, j, end))
    return clean, items

def is_test_attr(attrs):
    return '#[cfg(test)]' in attrs.replace(' ', '')

def main():
    src_root = os.path.join(ROOT, 'src')
    files = []
    for d, _, fs in os.walk(src_root):
        for f in fs:
            if f.endswith('.rs'):
                files.append(os.path.relpath(os.path.join(d, f), src_root))
    files.sort()
    enums = []
    copies = []
    out = []
    for rel in files:
        src = open(os.path.join(src_root, rel)).read()
        clean, items = scan(rel, src)
        mod = module_of(rel)
        out.append(f'\n## src/{rel}  ->  {baml_path(rel)}  (namespace `{mod}`)\n')
        for kw, header, attrs, j, end in items:
            test = is_test_attr(attrs)
            tag = ' [cfg(test)]' if test else ''
            derive = re.findall(r'derive\(([^)]*)\)', attrs)
            dtag = f' derive({", ".join(derive)})' if derive else ''
            if kw == 'enum':
                body = clean[j+1:end] if j < end else ''
                # variants at depth 0 of body
                variants, depth, cur = [], 0, ''
                for ch in body:
                    if ch in '({[': depth += 1
                    elif ch in ')}]': depth -= 1
                    if ch == ',' and depth == 0:
                        variants.append(cur); cur = ''
                    else:
                        cur += ch
                variants.append(cur)
                vs = []
                data = False
                for v in variants:
                    v = re.sub(r'#\[[^\]]*\]', '', v).strip()
                    if not v: continue
                    name = re.match(r'[A-Za-z_0-9]+', v)
                    if not name: continue
                    has = '(' in v or '{' in v
                    data = data or has
                    vs.append(name.group(0) + ('(..)' if '(' in v else '{..}' if '{' in v else ''))
                ename = re.search(r'enum\s+([A-Za-z_0-9]+)', header).group(1)
                kind = 'DATA' if data else 'C-LIKE'
                enums.append((mod, ename, kind, vs))
                out.append(f'- enum `{ename}` **{kind}**{dtag}{tag}: {", ".join(vs)}')
            elif kw == 'struct':
                sname = re.search(r'struct\s+([A-Za-z_0-9]+)', header).group(1)
                if any('Copy' in d for d in derive): copies.append((mod, sname))
                fields = ''
                if j < end:
                    body = sig_text(src, j + 1, end)
                    body = re.sub(r'///[^\n]*', '', src[j+1:end])
                    body = re.sub(r'//[^\n]*', '', body)
                    body = re.sub(r'#\[[^\]]*\]', '', body)
                    body = re.sub(r'\s+', ' ', body).strip()
                    fields = ' { ' + body + ' }'
                out.append(f'- struct `{header}`{dtag}{tag}{fields}')
            elif kw == 'impl':
                out.append(f'- `{header}`{tag}:')
                body_clean = clean[j+1:end]
                for fm in re.finditer(r'(?m)^\s*((?:#\[[^\]]*\]\s*)*)(?:pub(?:\([^)]*\))?\s+)?(?:const\s+)?fn\s+([A-Za-z_0-9]+)', body_clean):
                    # only depth-0 fns within impl body
                    pre = body_clean[:fm.start()]
                    if pre.count('{') - pre.count('}') != 0: continue
                    k = j + 1 + fm.end()
                    dp = 0
                    while k < end:
                        ch = clean[k]
                        if ch in '([<': dp += 1
                        elif ch in ')]>':
                            if not (ch == '>' and clean[k-1] == '-'): dp -= 1
                        elif (ch == '{' or ch == ';') and dp <= 0: break
                        k += 1
                    sig = sig_text(src, j + 1 + fm.start(2) - 3, k)
                    sig = re.sub(r'^.*?fn ', 'fn ', sig)
                    out.append(f'    - `{sig}`')
            elif kw == 'mod':
                out.append(f'- `{header}`{tag}' + (' (inline)' if j < end else ''))
            elif kw in ('fn', 'const fn'):
                out.append(f'- `{header}`{tag}')
            elif kw in ('const', 'static', 'type', 'trait'):
                h = header if len(header) < 200 else header[:200] + '…'
                out.append(f'- `{h}`{tag}')
    print('# sasso Rust item inventory (generated by port/inventory.py)\n')
    print('Every Rust item, by file, with the BAML file/namespace it ports to.')
    print('Enum kind decides the BAML shape (see PORTING_GUIDE.md §Enums).\n')
    print('## Enum registry\n')
    print('| namespace | enum | kind | variants |\n|---|---|---|---|')
    for mod, e, k, vs in enums:
        print(f'| `{mod}` | `{e}` | {k} | {", ".join(vs)} |')
    print('\n## `Copy` structs (value semantics in Rust — copy before mutating in BAML)\n')
    print(', '.join(f'`{m}.{s}`' for m, s in copies))
    print('\n'.join(out))

main()
