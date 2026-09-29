#!/usr/bin/env python3
"""Replace one function (stub) in a .baml file, safely under concurrency.

Several porters may fill stubs in the same file at once, so edits go through
this tool, which holds an exclusive lock on the file for the read-modify-write.

    python3 port/splice.py FILE NAME NEW_CODE_FILE [--in CONTAINER] [--nth N]
    python3 port/splice.py FILE NAME NEW_CODE_FILE --after      # insert after NAME
    python3 port/splice.py FILE --append NEW_CODE_FILE          # append at file end
    python3 port/splice.py FILE NAME --show [--in CONTAINER]    # print current text
    python3 port/splice.py FILE --replace-text OLD_FILE NEW_FILE # exact, unique text swap

NAME is the function name (`eval_expr`). CONTAINER disambiguates by the
enclosing block's name: a class (`Evaluator`), an interface (`Value`), or an
`implements` block (use the implemented interface's name, e.g.
`EvaluatorExpr`); `--in top` selects a top-level function. Interface
declarations without a body are never matched.

NEW_CODE_FILE holds the complete replacement (doc comments optional,
signature + body) at column 0; it is re-indented to the target's indentation.
Existing doc comments directly above the target are kept unless the new code
starts with its own comment lines.
"""
import fcntl
import os
import re
import sys


def find_blocks(lines):
    """Map line index -> name of the innermost enclosing container block."""
    stack = []  # (name, depth_at_open)
    depth = 0
    owner = []
    for ln in lines:
        stripped = ln.strip()
        owner.append(stack[-1][0] if stack else 'top')
        m = re.match(r'^(?:class|interface)\s+([A-Za-z_][A-Za-z0-9_]*)', stripped)
        m2 = re.match(r'^implements\s+([A-Za-z_.][A-Za-z0-9_.<>, ]*?)(?:\s+for\s+.*)?\s*\{', stripped)
        opened = ln.count('{') - ln.count('}')
        code = strip_strings(ln)
        opened = code.count('{') - code.count('}')
        if (m or m2) and '{' in code:
            name = (m.group(1) if m else m2.group(1).split('.')[-1].split('<')[0].strip())
            stack.append((name, depth))
        depth += opened
        while stack and depth <= stack[-1][1]:
            stack.pop()
    return owner


def strip_strings(line):
    out = []
    i = 0
    in_s = None
    while i < len(line):
        c = line[i]
        if in_s:
            if c == '\\':
                i += 2
                continue
            if c == in_s:
                in_s = None
            i += 1
            continue
        if c in '"`':
            in_s = c
            i += 1
            continue
        if line.startswith('//', i):
            break
        out.append(c)
        i += 1
    return ''.join(out)


def function_span(lines, start):
    """[start, end] line indices of the function whose signature starts at start."""
    depth = 0
    seen = False
    for i in range(start, len(lines)):
        code = strip_strings(lines[i])
        for ch in code:
            if ch == '{':
                depth += 1
                seen = True
            elif ch == '}':
                depth -= 1
        if seen and depth == 0:
            return i
    return None


def find_targets(lines, name, container):
    owners = find_blocks(lines)
    hits = []
    pat = re.compile(r'^\s*function\s+' + re.escape(name) + r'\s*[<(]')
    for i, ln in enumerate(lines):
        if not pat.match(ln):
            continue
        # must have a body: find `{` before a line that ends the signature
        j = i
        body = False
        while j < len(lines):
            code = strip_strings(lines[j])
            if '{' in code:
                body = True
                break
            if j > i and re.match(r'^\s*(function|///|//|\}|$)', lines[j]):
                break
            if j == i and code.rstrip().endswith(')') is False and 'throws unknown' in code and '{' not in code:
                break
            j += 1
            if j - i > 12:
                break
        if not body:
            continue
        if container and owners[i] != container:
            continue
        hits.append(i)
    return hits


def doc_start(lines, i):
    k = i
    while k > 0 and lines[k - 1].strip().startswith('//'):
        k -= 1
    return k


def reindent(code, indent):
    out = []
    for ln in code.rstrip('\n').split('\n'):
        out.append((indent + ln) if ln.strip() else '')
    return out


def main():
    args = sys.argv[1:]
    container = None
    nth = None
    if '--in' in args:
        k = args.index('--in')
        container = args[k + 1]
        del args[k:k + 2]
    if '--nth' in args:
        k = args.index('--nth')
        nth = int(args[k + 1])
        del args[k:k + 2]
    after = '--after' in args
    if after:
        args.remove('--after')
    show = '--show' in args
    if show:
        args.remove('--show')
    append = '--append' in args
    if append:
        args.remove('--append')
    replace_text = '--replace-text' in args
    if replace_text:
        args.remove('--replace-text')
    path = args[0]
    lock_dir = os.path.join(os.environ.get('TMPDIR', '/tmp'), 'baml-splice-locks')
    os.makedirs(lock_dir, exist_ok=True)
    lock_path = os.path.join(lock_dir, os.path.abspath(path).replace('/', '_') + '.lock')
    with open(lock_path, 'w') as lf:
        fcntl.flock(lf, fcntl.LOCK_EX)
        try:
            if replace_text:
                text = open(path).read()
                old = open(args[1]).read()
                new = open(args[2]).read()
                if old.endswith('\n') and not new.endswith('\n'):
                    new += '\n'
                n = text.count(old)
                if n != 1:
                    sys.exit(f'error: the old text occurs {n} times in {path} (must be exactly once)')
                open(path, 'w').write(text.replace(old, new))
                print(f'replaced text in {path}')
                return
            lines = open(path).read().split('\n')
            if append:
                code = open(args[1]).read()
                if lines and lines[-1] == '':
                    lines = lines[:-1]
                lines += [''] + reindent(code, '') + ['']
                open(path, 'w').write('\n'.join(lines))
                print(f'appended to {path}')
                return
            name = args[1]
            hits = find_targets(lines, name, container)
            if not hits:
                sys.exit(f'error: no function `{name}` with a body' + (f' in `{container}`' if container else '') + f' in {path}')
            if len(hits) > 1 and nth is None:
                owners = find_blocks(lines)
                desc = ', '.join(f'line {h + 1} in `{owners[h]}`' for h in hits)
                sys.exit(f'error: `{name}` is ambiguous ({desc}); pass --in CONTAINER or --nth N')
            i = hits[nth or 0]
            end = function_span(lines, i)
            if end is None:
                sys.exit('error: unbalanced braces after line %d' % (i + 1))
            if show:
                ds = doc_start(lines, i)
                print('\n'.join(lines[ds:end + 1]))
                return
            indent = re.match(r'^(\s*)', lines[i]).group(1)
            code = open(args[2]).read()
            new = reindent(code, indent)
            if after:
                lines[end + 1:end + 1] = [''] + new
            else:
                start = i
                if new and new[0].strip().startswith('//'):
                    start = doc_start(lines, i)
                lines[start:end + 1] = new
            open(path, 'w').write('\n'.join(lines))
            print(f'{"inserted after" if after else "replaced"} `{name}` at line {i + 1} of {path}')
        finally:
            fcntl.flock(lf, fcntl.LOCK_UN)


if __name__ == '__main__':
    main()
